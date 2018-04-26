extern crate clap;
extern crate libc;
extern crate termios;

use clap::{App, Arg};
use std::cmp::max;
use std::{io, process};
use std::io::Read;
use std::fs::{File, metadata};
use std::num::ParseIntError;

mod crc32;
#[macro_use]
mod display;
mod serial;

use serial::Serial;

const DEFAULT_ORIGIN: u32 = 0x8000;
const DEFAULT_BLOCK_SIZE: u32 = 1024;

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
        .help(&format!("set transmit block size (default is dynamic, minimum of {})", DEFAULT_BLOCK_SIZE))
        .takes_value(true)
    )
    .arg(Arg::with_name("serial-device").required(true))
    .arg(Arg::with_name("filename").required(true))
    .get_matches();

  display::set_verbose(matches.occurrences_of("verbose") > 0);
  let filename = matches.value_of("filename").unwrap();

  let mut origin = DEFAULT_ORIGIN;
  if let Some(origin_override) = matches.value_of("origin") {
    origin = parse_int(origin_override).unwrap_or_else(|err| {
      error!("Can't parse origin '{}': {}", origin_override, err);
      process::exit(1);
    });
  }

  let file_size = metadata(filename).unwrap_or_else(|err| {
    error!("Can't read kernel file '{}': {}", filename, err);
    process::exit(1);
  }).len();

  let mut file = File::open(filename).unwrap_or_else(|err| {
    error!("Can't read kernel file '{}': {}", filename, err);
    process::exit(1);
  });

  // try not to send more than 100 blocks:
  let mut block_size = max(DEFAULT_BLOCK_SIZE, (file_size as u32) / 100);
  if let Some(block_size_override) = matches.value_of("block_size") {
    block_size = parse_int(block_size_override).unwrap_or_else(|err| {
      error!("Can't parse block size '{}': {}", block_size_override, err);
      process::exit(1);
    });
  }

  let mut serial = Serial::connect(matches.value_of("serial-device").unwrap()).unwrap_or_else(|err| {
    error!("Failed to set TTY parameters: {}", err);
    process::exit(1);
  });

  send_kernel(&mut serial, &mut file, filename, file_size, origin, block_size).unwrap_or_else(|err| {
    error!("Failed: {}", err);
    process::exit(1);
  });
}

fn parse_int(s_in: &str) -> Result<u32, ParseIntError> {
  let mut s = s_in;
  let mut radix = 10;
  if &s[0..2] == "0x" {
    s = &s[2..];
    radix = 16;
  } else if &s[0..1] == "$" {
    s = &s[1..];
    radix = 16;
  }
  u32::from_str_radix(s, radix)
}


// ----- send_kernel

fn send_kernel(
  serial: &mut Serial,
  file: &mut File,
  filename: &str,
  file_size: u64,
  origin: u32,
  block_size: u32,
) -> io::Result<()> {
  // listen for c3r3s and tell it we're here.
  serial.scan_str("c3r3s")?;
  verbose!("Found c3r3s on raspi");
  serial.write_str("boot")?;
  serial.scan_str("lstn")?;

  log!("Sending {} ({}B) at ${:x}", filename, display::human_size(file_size), origin);

  // header
  serial.write_str("send")?;
  serial.write_u32(origin)?;
  serial.write_u32(file_size as u32)?;

  send_file(serial, file, file_size as u32, block_size)?;

  let response = serial.read_str()?;
  if response == "fail" {
    error!("Raspi rejected CRC :(");
    process::exit(1);
  } else if response == "good" {
    log!("CRC passed! Booting...");
  } else {
    error!("Corrupted response from c3r3s: {:?}", response);
    process::exit(1);
  }
  Ok(())
}

fn send_file(serial: &mut Serial, file: &mut File, file_size: u32, block_size: u32) -> io::Result<()> {
  let mut buffer: [u8; 1024] = [0; 1024];
  let mut count: u32 = 0;
  let mut next_ack = block_size;
  let mut crc = crc32::Crc32::new();
  let mut progress = display::ProgressBar::new(file_size);

  progress.update(0)?;
  loop {
    let n = file.read(&mut buffer)?;
    if n == 0 {
      print!("\n");
      error!("Kernel unexpectedly truncated at {}", count);
      return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "truncated kernel"));
    }

    serial.write_u32(n as u32)?;
    serial.write_bytes(&buffer[0..n])?;
    crc.add(&buffer[0..n]);

    count += n as u32;
    progress.update(count)?;
    while count >= next_ack {
      let ack = serial.read_u32()?;
      if ack != next_ack {
        print!("\n");
        error!("Incorrect ack: expected {}, got {}", next_ack, ack);
        return Err(io::Error::new(io::ErrorKind::InvalidData, "bad ack"));
      }
      if ack == file_size {
        serial.write_u32(crc.finish())?;
        progress.finish();
        return Ok(())
      }

      next_ack += block_size;
      if next_ack > file_size {
        next_ack = file_size;
      }
    }
  }
}
