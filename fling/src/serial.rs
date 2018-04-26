use libc;
use std::fs::File;
use std::io;
use std::io::{Read, Write};
use std::os::unix::io::FromRawFd;
use std::str;
use std::thread::sleep;
use std::time::Duration;
use termios;

// apparently windows never heard of 115200bps, so we all have to suffer.
#[cfg(target_os = "macos")]
use termios::os::macos::B115200;

#[cfg(target_os = "linux")]
use termios::os::linux::B115200;

// how often to check for the existence of the serial port
const WAKEUP_DELAY: Duration = Duration::from_millis(250);


pub struct Serial {
  file: File,
}

impl Serial {
  pub fn connect(filename: &str) -> io::Result<Serial> {
    let fd = Serial::wait_for(filename);
    if unsafe { libc::isatty(fd) } == 0 {
      return Err(io::Error::new(io::ErrorKind::Other, "Not a serial device"))
    }

    let mut term = termios::Termios::from_fd(fd)?;
    termios::cfsetspeed(&mut term, B115200)?;
    term.c_cflag |= termios::CLOCAL | termios::CREAD;
    // 8N1
    term.c_cflag |= termios::CS8;
    term.c_cflag &= !(termios::PARENB | termios::CSTOPB);
    // no flow control
    // term.c_cflag &= !termios::CRTSCTS;
    term.c_iflag &= !(termios::IXON | termios::IXOFF | termios::IXANY);
    termios::tcsetattr(fd, termios::TCSAFLUSH, &term)?;

    verbose!("Connected to serial port");
    let file = unsafe { File::from_raw_fd(fd) };
    Ok(Serial { file })
  }

  // wait for the serial port file to exist and become openable.
  // then return the raw fd of the open serial port.
  fn wait_for(filename: &str) -> i32 {
    let mut last_error: Option<io::Error> = None;

    log!("Waiting for {} ...", filename);
    let flags = libc::O_RDWR | libc::O_NOCTTY;
    loop {
      let fd = unsafe { libc::open(filename.as_ptr() as *const i8, flags, 0) };
      if fd >= 0 {
        return fd;
      }

      let error = io::Error::last_os_error();
      // io::Error: would it have killed you to add a to_string?
      if let Some(last) = last_error {
        if error.kind() != last.kind() || error.raw_os_error() != last.raw_os_error() {
          verbose!("Error (still trying): {}", error);
        }
      } else {
        verbose!("Error (still trying): {}", error);
      }
      last_error = Some(error);

      sleep(WAKEUP_DELAY);
    }
  }

  pub fn write_bytes(&mut self, b: &[u8]) -> io::Result<()> {
    self.file.write_all(b)
  }

  pub fn write_str(&mut self, s: &str) -> io::Result<()> {
    self.file.write_all(s.as_bytes())
  }

  pub fn read_str(&mut self) -> io::Result<String> {
    let mut buffer: [u8; 4] = [0; 4];
    self.file.read_exact(&mut buffer)?;
    String::from_utf8(buffer.to_vec()).map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))
  }

  // read into a small buffer until `s` is seen.
  pub fn scan_str(&mut self, s: &str) -> io::Result<()> {
    let mut buffer: [u8; 128] = [0; 128];
    let mut index = 0;
    loop {
      let n = self.file.read(&mut buffer[index..])?;

      index += n;
      let so_far = str::from_utf8(&buffer[0..index]);
      if so_far.is_err() {
        error!("Serial device failed to sync on '{}'", s);
        return Err(io::Error::new(io::ErrorKind::InvalidData, so_far.unwrap_err()));
      }
      if so_far.unwrap().contains(s) {
        return Ok(());
      }
      if index >= buffer.len() {
        error!("Serial device failed to sync on '{}'", s);
        return Err(io::Error::new(io::ErrorKind::Other, "Never saw keyword"));
      }
    }
  }

  pub fn write_u32(&mut self, data: u32) -> io::Result<()> {
    let mut buffer: [u8; 4] = [0; 4];
    buffer[0] = (data & 0xff) as u8;
    buffer[1] = ((data >> 8) & 0xff) as u8;
    buffer[2] = ((data >> 16) & 0xff) as u8;
    buffer[3] = ((data >> 24) & 0xff) as u8;
    self.file.write_all(&buffer)
  }

  pub fn read_u32(&mut self) -> io::Result<u32> {
    let mut buffer: [u8; 4] = [0; 4];
    self.file.read_exact(&mut buffer)?;
    Ok((buffer[0] as u32) | ((buffer[1] as u32) << 8) | ((buffer[2] as u32) << 16) | ((buffer[3] as u32) << 24))
  }
}
