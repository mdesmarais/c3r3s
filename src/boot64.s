.set stack, 0x7fc00
.set bootloader, 0x80000

.macro push a, b
  stp \a, \b, [sp, #-16]!
.endm

.macro pop a, b
  ldp \a, \b, [sp], #16
.endm

.section ".text.boot"

.global _start
_start:
  mov sp, #stack
  // in theory, the previous stage bootloader stored interesting facts in x0-x2.
  push x0, x1
  push x2, x3
  // move code to $7fc00, then jump-absolute to it.
  ldr x0, =_start
  mov x1, #bootloader
  ldr x2, =_end
1:
  ldp x8, x9, [x1], #16
  stp x8, x9, [x0], #16
  cmp x0, x2
  b.lo 1b
  adr x0, next
  br x0

.text

next:
  bl toggle_light
  bl get_uart_clock
  ldr w1, =115200
  bl uart_init
  bl toggle_light

wait_for_sync:
  bl delay_500ms
  bl toggle_light
  bl draw_banner
  bl check_sync
  // tricky way to notice if the state reached 4:
  tbz w5, #2, wait_for_sync

read_image_header:
  adr x3, listen_word
  bl uart_write_word

  bl uart_read_u32
  adr x4, send_word
  ldr w4, [x4]
  cmp w3, w4
  bne fail

  // w11: origin, w12: size
  bl uart_read_u32
  mov w11, w3
  bl uart_read_u32
  mov w12, w3

read_blocks:
  // x8: currrent addr, w9: bytes so far, w10: bytes left in current block
  mov w8, w11
  mov w9, #0
read_one_block:
  bl toggle_light
  bl uart_read_u32
  mov w10, w3
  add w9, w9, w3
1:
  bl uart_read_u32
  str w3, [x8], #4
  subs w10, w10, #4
  b.ne 1b
  // write ack:
  mov w3, w9
  bl uart_write_u32
  cmp w9, w12
  b.lo read_one_block

check_crc32:
  // w3: target crc
  bl uart_read_u32
  // x8: current addr, x9: end addr, w10: crc
  mov w8, w11
  add w9, w8, w12
  mov w10, #0xffffffff
1:
  ldrb w0, [x8], #1
  crc32b w10, w10, w0
  cmp x8, x9
  b.lo 1b
  mvn w10, w10
  cmp w3, w10
  b.ne fail

  // send "good", wait 1 second, then jump to the origin!
  adr x3, good_word
  bl uart_write_word
  bl toggle_light
  bl delay_500ms
  bl toggle_light
  bl delay_500ms
  pop x2, x3
  pop x0, x1
  br x11

fail:
  adr x3, fail_word
  bl uart_write_word

halt:
  wfi
  b halt
