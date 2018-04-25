extern crate clap;
extern crate libc;
extern crate termios;

use clap::{App, Arg};
use std::{io, process, thread};
use std::io::{Read, Write};
use std::fs::{File, metadata};
use std::os::unix::io::FromRawFd;
use std::time::Duration;
use termios::Termios;

#[cfg(target_os = "macos")]
use termios::os::macos::B115200;

#[cfg(target_os = "linux")]
use termios::os::linux::B115200;

const DEFAULT_ORIGIN: u32 = 0x8000;
const DEFAULT_BLOCK_SIZE: u32 = 1024;
const WAKEUP_DELAY: Duration = Duration::from_millis(250);

fn main() {
  let matches = App::new("fling")
    .version("0.1")
    .about("send a baremetal kernel to a raspberry pi 3 using c3r3s")
    .arg(Arg::with_name("verbose").short("v").help("show verbose debugging messages"))
    .arg(
      Arg::with_name("origin").short("o").long("origin")
        .help(&format!("install kernel at alternate address (default: ${:x})", DEFAULT_ORIGIN))
        .takes_value(true)
    )
    .arg(
      Arg::with_name("block_size").short("b").long("block")
        .help(&format!("set transmit block size (default: {})", DEFAULT_BLOCK_SIZE))
        .takes_value(true)
    )
    .arg(Arg::with_name("serial-device").required(true))
    .arg(Arg::with_name("filename").required(true))
    .get_matches();

  let verbose = matches.occurrences_of("verbose") > 0;
  let filename = matches.value_of("filename").unwrap();

  let mut origin = DEFAULT_ORIGIN;
  if let Some(origin_override) = matches.value_of("origin") {
    let mut thing = origin_override;
    let mut radix = 10;
    if &origin_override[0..2] == "0x" {
      thing = &origin_override[2..];
      radix = 16;
    } else if &origin_override[0..1] == "$" {
      thing = &origin_override[1..];
      radix = 16;
    }
    origin = u32::from_str_radix(thing, radix).unwrap_or_else(|err| {
      log_error(&format!("Can't parse origin '{}': {}", origin_override, err));
      process::exit(1);
    });
  }

  let mut block_size = DEFAULT_BLOCK_SIZE;
  if let Some(block_size_override) = matches.value_of("block_size") {
    block_size = u32::from_str_radix(block_size_override, 10).unwrap_or_else(|err| {
      log_error(&format!("Can't parse block size '{}': {}", block_size_override, err));
      process::exit(1);
    });
  }

  let file_size = metadata(filename).unwrap_or_else(|err| {
    log_error(&format!("Can't read kernel file '{}': {}", filename, err));
    process::exit(1);
  }).len();

  let mut file = File::open(filename).unwrap_or_else(|err| {
    log_error(&format!("Can't read kernel file '{}': {}", filename, err));
    process::exit(1);
  });

  let mut serial = connect(matches.value_of("serial-device").unwrap(), verbose).unwrap_or_else(|err| {
    log_error(&format!("Failed to set TTY parameters: {}", err));
    process::exit(1);
  });

  send_kernel(&mut serial, &mut file, filename, file_size, origin, block_size, verbose).unwrap_or_else(|err| {
    log_error(&format!("Failed: {}", err));
    process::exit(1);
  });
}

fn connect(filename: &str, verbose: bool) -> io::Result<File> {
  let fd = wait_for_serial(filename, verbose);
  if unsafe { libc::isatty(fd) } == 0 {
    log_error("Not a serial device.");
    process::exit(1);
  }

  let mut term = Termios::from_fd(fd)?;
  termios::cfsetspeed(&mut term, B115200)?;
  term.c_cflag |= termios::CLOCAL | termios::CREAD;
  // 8N1
  term.c_cflag |= termios::CS8;
  term.c_cflag &= !(termios::PARENB | termios::CSTOPB);
  // no flow control
  // term.c_cflag &= !termios::CRTSCTS;
  term.c_iflag &= !(termios::IXON | termios::IXOFF | termios::IXANY);
  termios::tcsetattr(fd, termios::TCSAFLUSH, &term)?;

  if verbose {
    println!("Connected to serial port");
  }
  Ok(unsafe { File::from_raw_fd(fd) })
}

fn wait_for_serial(filename: &str, verbose: bool) -> i32 {
  let mut last_error: Option<io::Error> = None;

  log(&format!("Waiting for {} ...", filename));
  let flags = libc::O_RDWR | libc::O_NOCTTY;
  loop {
    let fd = unsafe { libc::open(filename.as_ptr() as *const i8, flags, 0) };
    if fd >= 0 {
      return fd;
    }
    if verbose {
      let error = io::Error::last_os_error();
      // would it have killed you to add a to_string?
      if format!("{:?}", Some(&error)) != format!("{:?}", last_error) {
        println!("Error (still trying): {}", error);
      }
      last_error = Some(error);
    }
    thread::sleep(WAKEUP_DELAY);
  }
}


// ----- send_kernel

fn send_kernel(
  serial: &mut File,
  file: &mut File,
  filename: &str,
  file_size: u64,
  origin: u32,
  block_size: u32,
  verbose: bool,
) -> io::Result<()> {
  // listen for c3r3s and tell it we're here.
  if scan_for(serial, "c3r3s").is_err() { process::exit(1) }
  if verbose {
    println!("Found c3r3s on raspi");
  }
  serial.write_all("boot".as_bytes())?;
  if scan_for(serial, "lstn").is_err() { process::exit(1) }

  log(&format!("Sending {} ({}B) at ${:x}", filename, human_size(file_size), origin));

  send_file_header(serial, origin, file_size as u32)?;
  send_file(serial, file, file_size as u32, block_size)?;

  let mut buffer: [u8; 4] = [0; 4];
  serial.read_exact(&mut buffer)?;
  if buffer == "fail".as_bytes() {
    log_error("Raspi rejected CRC :(");
    process::exit(1);
  } else if buffer == "good".as_bytes() {
    println!("");
    log("Rock on!");
  } else {
    log_error(&format!("Corrupted response from c3r3s: {:?}", buffer));
    process::exit(1);
  }
  Ok(())
}

fn send_file_header(serial: &mut File, origin: u32, size: u32) -> io::Result<()> {
  serial.write_all("send".as_bytes())?;
  let mut buffer: [u8; 8] = [0; 8];
  write_u32(&mut buffer[0..4], origin);
  write_u32(&mut buffer[4..8], size);
  serial.write_all(&buffer)
}

fn send_file(serial: &mut File, file: &mut File, file_size: u32, block_size: u32) -> io::Result<()> {
  let mut block_header: [u8; 4] = [0; 4];
  let mut buffer: [u8; 1024] = [0; 1024];
  let mut count: u32 = 0;
  let mut next_ack = block_size;
  let mut crc = crc32_start();

  draw_progress(0, file_size)?;
  loop {
    let n = file.read(&mut buffer)?;
    if n == 0 {
      print!("\n");
      log_error(&format!("Kernel unexpectedly truncated at {}", count));
      return Err(io::Error::from(io::ErrorKind::UnexpectedEof));
    }

    write_u32(&mut block_header, n as u32);
    serial.write_all(&block_header)?;
    serial.write_all(&buffer[0..n])?;
    crc = crc32_add(crc, &buffer[0..n]);

    count += n as u32;
    draw_progress(count, file_size)?;
    while count >= next_ack {
      serial.read_exact(&mut buffer[0..4])?;
      let ack = read_u32(&buffer[0..4]);
      if ack != next_ack {
        print!("\n");
        log_error(&format!("Incorrect ack: expected {}, got {}", next_ack, ack));
        return Err(io::Error::from(io::ErrorKind::InvalidData));
      }
      if ack == file_size {
        crc = crc32_finish(crc);
        write_u32(&mut block_header, crc);
        serial.write_all(&block_header)?;
        return Ok(())
      }

      next_ack += block_size;
      if next_ack > file_size {
        next_ack = file_size;
      }
    }
  }
}

fn draw_progress(count: u32, total: u32) -> io::Result<()> {
  let blocks = count * 50 / total;
  print!("\r  [\x1b[1;33m");
  for _i in 0..blocks { print!("#") }
  print!("\x1b[0;35m");
  for _i in 0..(50 - blocks) { print!("-") }
  print!("\x1b[0m] {}B ", human_size(count as u64));
  io::stdout().flush()
}

fn read_u32(buffer: &[u8]) -> u32 {
  (buffer[0] as u32) | ((buffer[1] as u32) << 8) | ((buffer[2] as u32) << 16) | ((buffer[3] as u32) << 24)
}

fn write_u32(buffer: &mut [u8], data: u32) {
  buffer[0] = (data & 0xff) as u8;
  buffer[1] = ((data >> 8) & 0xff) as u8;
  buffer[2] = ((data >> 16) & 0xff) as u8;
  buffer[3] = ((data >> 24) & 0xff) as u8;
}

fn scan_for(serial: &mut File, scan: &str) -> io::Result<()> {
  let mut buffer: [u8; 128] = [0; 128];
  let mut index = 0;
  loop {
    let n = serial.read(&mut buffer[index..])?;

    index += n;
    let so_far = std::str::from_utf8(&buffer[0..index]);
    if so_far.is_err() {
      log_error(&format!("Serial device failed to sync on '{}'", scan));
      return Err(io::Error::from(io::ErrorKind::InvalidData));
    }
    if so_far.unwrap().contains(scan) {
      return Ok(());
    }
    if index >= buffer.len() {
      log_error(&format!("Serial device failed to sync on '{}'", scan));
      return Err(io::Error::from(io::ErrorKind::Other));
    }
  }
}

// why doesn't rust have a working crc32 lib?
const POLYNOMIAL: u32 = 0xedb88320;
const CRC32_START: u32 = 0xffffffff;
const BIT_TABLE: [u32; 2] = [ 0, POLYNOMIAL ];

fn crc32_start() -> u32 {
  CRC32_START
}

fn crc32_add(crc_in: u32, buffer: &[u8]) -> u32 {
  let mut crc = crc_in;
  for byte in buffer.iter() {
    crc ^= *byte as u32;
    for _i in 0..8 {
      crc = (crc >> 1) ^ BIT_TABLE[(crc & 1) as usize];
    }
  }
  crc
}

fn crc32_finish(crc: u32) -> u32 {
  crc ^ CRC32_START
}

// nah.
// fn set_nonblocking(serial: &mut File) {
//   // move serial port into nonblocking mode
//   use std::os::unix::io::AsRawFd;
//   if unsafe { libc::fcntl(serial.as_raw_fd(), libc::F_SETFL, libc::O_NONBLOCK) } < 0 {
//     log_error(&format!("O_NONBLOCK: {}", io::Error::last_os_error()));
//   }
// }

fn human_size(size: u64) -> String {
  if size < 2 * 1024 {
    format!("{}", size)
  } else if size < 2 * 1024 * 1024 {
    format!("{:.1}K", (size as f64) / 1024.0)
  } else {
    format!("{:.1}M", (size as f64) / (1024.0 * 1024.0))
  }
}

fn log(s: &str) {
  println!("\x1b[32m{}\x1b[0m", s);
}

fn log_error(s: &str) {
  println!("\x1b[1;31m{}\x1b[0m", s);
}
