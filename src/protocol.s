.macro push a, b
  stp \a, \b, [sp, #-16]!
.endm

.macro pop a, b
  ldp \a, \b, [sp], #16
.endm

.text

// [x0: spinner index] -> uart
.global draw_banner
draw_banner:
  mov x6, lr
  adr x3, banner
  adr x4, banner_end
  bl uart_write_string
  adr x0, spinner
  adr x1, spinner_index
  ldrb w2, [x1]
  ldrb w0, [x0, x2]
  add x2, x2, #1
  and x2, x2, #3
  strb w2, [x1]
  bl uart_write
  ret x6

// probe for the "boot" sync from the host
// -> [w5 == 4 if we received the whole thing]
.global check_sync
check_sync:
  mov fp, lr
  adr x3, sync_state
  adr x4, sync_word
  ldrb w5, [x3]
1:
  ldrb w6, [x4, x5]
  bl uart_probe
  b.ne 2f
  // got a byte; was in the next desired one?
  cmp w0, w6
  csinc w5, wzr, w5, ne
  strb w5, [x3]
  b 1b
2:
  ret fp

// -> Z clear if successful
.global read_image_header
read_image_header:
  mov fp, lr
  adr x3, listen_word
  bl uart_write_word
  adr x6, header
  adr x7, header_end
  bl uart_read_block
  adr x6, header
  adr x7, send_word
  ldr w6, [x6]
  ldr w7, [x7]
  cmp w6, w7
  ret fp

.global read_image
read_image:
  mov fp, lr

  // x9: addr, w10: bytes so far, w11: total size
  adr x9, header_origin
  ldr w9, [x9]
  mov w10, #0
  adr x11, header_size
  ldr w11, [x11]
1:
  // read one block:
  bl uart_read_u32
  mov x6, x9
  add x7, x6, w3, uxtw
  // update addr, bytes so far:
  add x9, x9, w3, uxtw
  add w10, w10, w3
  bl uart_read_block
  mov w3, w10
  bl uart_write_u32

  cmp w10, w11
  b.lo 1b
  ret fp

.global check_crc32
check_crc32:
  .set START, 0xffffffff
  mov fp, lr
  bl uart_read_u32
  // w0: calculated crc, w1: addr, w2: addr_end, w3: received crc
  ldr w0, =START
  adr x1, header_origin
  ldr w1, [x1]
  adr x2, header_size
  ldr w2, [x2]
  add w2, w2, w1
1:
  ldrb w4, [x1], #1
  crc32b w0, w0, w4
  cmp x1, x2
  b.lo 1b
  ldr w4, =START
  eor w0, w0, w4
  cmp w0, w3
  ret fp


.data

banner:
  .ascii "\rc3r3s "
banner_end:
  .byte 0

spinner:
  .ascii "/-\\|"
spinner_end:

spinner_index:
  .word 0

// next byte of the sync_word we expect to read
sync_state:
  .word 0

// "send" header from the host
header:
  .word 0
header_origin:
  .word 0
header_size:
  .word 0
header_end:

sync_word:
  .ascii "boot"
listen_word:
  .ascii "lstn"
send_word:
  .ascii "send"
good_word:
  .ascii "good"
fail_word:
  .ascii "fail"

.global good_word, fail_word
