.set stack, 0x7f800
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
  // in theory, the previous bootloader stored interesting facts in x0-x2.
  push x0, x1
  push x2, x3
  // move code to $7f800, then jump-absolute to it.
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

  bl read_image_header
  b.ne fail
  bl read_image
  bl check_crc32
  b.ne fail

  adr x3, good_word
  bl uart_write_word
  b halt

fail:
  adr x3, fail_word
  bl uart_write_word

halt:
  wfi
  b halt
