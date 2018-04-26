// why doesn't rust have a working crc32 lib?

const POLYNOMIAL: u32 = 0xedb88320;
const CRC32_START: u32 = 0xffffffff;
const BIT_TABLE: [u32; 2] = [ 0, POLYNOMIAL ];

pub struct Crc32 {
  value: u32
}

impl Crc32 {
  pub fn new() -> Crc32 {
    Crc32 { value: CRC32_START }
  }

  pub fn add(&mut self, buffer: &[u8]) {
    for byte in buffer.iter() {
      self.value ^= *byte as u32;
      for _i in 0..8 {
        self.value = (self.value >> 1) ^ BIT_TABLE[(self.value & 1) as usize];
      }
    }
  }

  pub fn finish(self) -> u32 {
    self.value ^ CRC32_START
  }
}
