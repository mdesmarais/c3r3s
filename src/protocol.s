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
  add x0, x6, #1
  and x0, x0, #3
  ret x6


.data

banner:
  .ascii "\rc3r3s "
banner_end:

spinner:
  .ascii "/-\\|"
spinner_end:

spinner_index:
  .byte 0
