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

const WAKEUP_DELAY: Duration = Duration::from_millis(250);

fn main() {
  let matches = App::new("fling")
    .version("0.1")
    .about("send a baremetal kernel to a raspberry pi 3 using c3r3s")
    .arg(Arg::with_name("verbose").short("v").help("show verbose debugging messages"))
    .arg(Arg::with_name("serial-device").required(true))
    .arg(Arg::with_name("filename").required(true))
    .get_matches();

  let verbose = matches.occurrences_of("verbose") > 0;
  let filename = matches.value_of("filename").unwrap();

  let file_size = metadata(filename).unwrap_or_else(|err| {
    log_error(&format!("Can't open kernel file '{}': {}", filename, err));
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

  // listen for c3r3s and tell it we're here.
  if scan_for(&mut serial, "c3r3s").is_err() { process::exit(1) }
  if verbose {
    println!("Found c3r3s on raspi");
  }
  serial.write("boot".as_bytes());
  if scan_for(&mut serial, "lstn").is_err() { process::exit(1) }
  log(&format!("Sending {} ({}B)", filename, human_size(file_size)));

  // move serial port into nonblocking mode
  use std::os::unix::io::AsRawFd;
  if unsafe { libc::fcntl(serial.as_raw_fd(), libc::F_SETFL, libc::O_NONBLOCK) } < 0 {
    log_error(&format!("O_NONBLOCK: {}", io::Error::last_os_error()));
  }
  // serial.set_nonblocking(true);
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
    if index >= 128 {
      log_error(&format!("Serial device failed to sync on '{}'", scan));
      return Err(io::Error::from(io::ErrorKind::Other));
    }
  }
}

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
