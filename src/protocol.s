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

.global read_image_block
read_image_block:
  bl uart_read_u32

//  // read blocks:
//  //   - r7: origin
//  //   - r8: current addr
//  //   - r9: end addr
//  //   - r10: count (so far)
//  //   - r11: current block size
//  ldr r0, =header_origin
//  ldr r7, [r0]
//  mov r8, r7
//  ldr r0, =header_size
//  ldr r9, [r0]
//  add r9, r7
//  mov r10, #0
//
//  cmp r8, r9
//  bhs 4f
//3:
//  // read one block
//  bl uart_read_u32
//  mov r11, r0
//  mov r1, r8
//  add r1, r0
//  mov r0, r8
//  bl uart_read_block
//  add r8, r11
//  mov r0, r8
//  sub r0, r7
//  bl uart_write_u32
//  cmp r8, r9
//  blo 3b





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
