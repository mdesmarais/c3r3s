

## protocol

- raspi: "c3r3s" + other random, periodically
- host: "boot"
- raspi: "lstn"
- host:
    - "send"
    - origin: u32
    - size: u32
    - for each block:
        - block_size: u32
        - (data...)
    - crc32: u32
- raspi, every block_size, and at the end:
    - size so far: u32
- raspi, if crc32 matches:
    - "good"
- raspi, if crc32 fails:
    - "fail"
