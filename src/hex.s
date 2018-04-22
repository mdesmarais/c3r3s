// dump 32 bits of hex into the hex buffer
// [r0: word]
.global write_hex
write_hex:
  mov r1, #7
  ldr r2, =hex_buffer
1:
  and r3, r0, #0xf
  add r3, r3, #'0'
  cmp r3, #'9'
  addhi r3, r3, #('a' - '9' - 1)
  strb r3, [r2, r1]
  // next nybble:
  lsr r0, r0, #4
  subs r1, r1, #1
  bpl 1b
  bx lr

.data

.global hex_buffer, hex_buffer_end
hex_buffer:
  .word 0
  .word 0
hex_buffer_end:
