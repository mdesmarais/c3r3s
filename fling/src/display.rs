use std::io;
use std::io::Write;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

pub const RESET: &str = "\x1b[0m";
pub const GREEN: &str = "\x1b[32m";
pub const PURPLE: &str = "\x1b[35m";
pub const BRIGHT_RED: &str = "\x1b[1;31m";
pub const YELLOW: &str = "\x1b[1;33m";

// in no way does this need to be locked. this is just to have a static mutable.
pub static VERBOSING: AtomicBool = AtomicBool::new(false);

pub fn set_verbose(verbose: bool) {
  VERBOSING.store(verbose, Ordering::SeqCst);
}

macro_rules! log {
  ($($arg:tt)*) => (println!("{}{}{}", $crate::display::GREEN, format_args!($($arg)*), $crate::display::RESET));
}

macro_rules! error {
  ($($arg:tt)*) => (println!("{}{}{}", $crate::display::BRIGHT_RED, format_args!($($arg)*), $crate::display::RESET));
}

macro_rules! verbose {
  ($($arg:tt)*) => (
    if $crate::display::VERBOSING.load($crate::std::sync::atomic::Ordering::Relaxed) {
      println!("{}", format_args!($($arg)*));
    }
  )
}


pub struct ProgressBar {
  total: u32,
  start: Instant,
}

impl ProgressBar {
  pub fn new(total: u32) -> ProgressBar {
    ProgressBar { total, start: Instant::now() }
  }

  pub fn update(&mut self, count: u32) -> io::Result<()> {
    let blocks = (((count as f64) * 50.0 / (self.total as f64)) + 0.5) as usize;
    print!("\r  [{}", YELLOW);
    for _i in 0..blocks { print!("#") }
    print!("{}", RESET);
    for _i in 0..(50 - blocks) { print!("-") }
    print!("{}] {}B ", RESET, human_size(count as u64));
    io::stdout().flush()
  }

  pub fn finish(self) {
    print!("\n");
    log!("Finished in {}", human_duration(self.start.elapsed()));
  }
}


pub fn human_size(size: u64) -> String {
  if size < 2 * 1024 {
    format!("{}", size)
  } else if size < 2 * 1024 * 1024 {
    format!("{:.1}K", (size as f64) / 1024.0)
  } else {
    format!("{:.1}M", (size as f64) / (1024.0 * 1024.0))
  }
}

pub fn human_duration(d: Duration) -> String {
  let secs = d.as_secs() % 60;
  let mins = d.as_secs() / 60;
  format!("{:02}:{:02}", mins, secs)
}
