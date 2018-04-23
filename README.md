

## protocol

- raspi: "c3r3s" + other random
- host: "boot"
- raspi: "lstn"
- host:
    - origin: u32
    - size: u32
    - (data...)
    - crc32: u32
- raspi, every 1KB, and at the end:
    - "recv"
    - size so far: u32
- raspi, if crc32 matches:
    - "good"
- raspi, if crc32 fails:
    - "fail"
