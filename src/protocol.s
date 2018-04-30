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
  bl uart_write_word
  adr x3, banner2
  bl uart_write_word
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


.data

banner:
  .ascii "\r*c3"
banner2:
  .ascii "r3s "

spinner:
  .ascii "/-\\|"
spinner_end:

spinner_index:
  .byte 0
sync_state:
  // next byte of the sync_word we expect to read
  .byte 0
// align:
  .byte 0
  .byte 0

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

.global listen_word, send_word, good_word, fail_word
