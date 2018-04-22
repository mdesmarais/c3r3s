.set POLYNOMIAL, 0xedb88320
.set START, 0xffffffff

// [r0: start, r1: end] -> [r0: crc32]
.global compute_crc32
compute_crc32:
  // r3 = crc
  ldr r3, =START
  ldr r12, =POLYNOMIAL

1:
  // crc ^= *start++
  ldrb r2, [r0], #1
  eor r3, r3, r2

  .rept 8
  // crc = (crc >> 1) ^ (crc & 1 ? POLYNOMIAL : 0)
  lsrs r3, r3, #1
  eorcs r3, r12
  .endr

  cmp r0, r1
  blo 1b

  ldr r0, =START
  eor r0, r3
  bx lr
