.macro push a, b
  stp \a, \b, [sp, #-16]!
.endm

.macro pop a, b
  ldp \a, \b, [sp], #16
.endm

.set MAILBOX_BASE, 0x3f00b880
.set MAILBOX_STATUS_1, 0x38
.set MAILBOX_RW_0, 0x00
.set MAILBOX_STATUS_0, 0x18
.set MAILBOX_RW_1, 0x20
.set MAILBOX_STATUS_1, 0x38

.set PROPERTY, 8
.set BIT_FULL, 31
.set BIT_EMPTY, 30

.set TAG_CLOCK_GET_RATE, 0x00030002
.set TAG_SET_GPIO_STATE, 0x00038041

.set CLOCK_CORE, 4
.set CLOCK_UART, 2

.text

// -> [w0: uart Hz]
.global get_uart_clock
get_uart_clock:
  mov fp, lr
  ldr w5, =TAG_CLOCK_GET_RATE
  mov w7, #CLOCK_UART

  ldr w0, =property_buffer
  str wzr, [x0, #4]     // request
  str w5, [x0, #8]
  str w7, [x0, #20]     // uart
  mov x5, x0
  bl mailbox_send
  ldr x0, [x5, #24]
  ret fp

.global toggle_light
toggle_light:
  adr x1, light
  ldr w0, [x1]
  eor w0, w0, #1
  str w0, [x1]
  // fall thru

// [w0: active_low]
// trash: x0 - x6
.global set_led
set_led:
  mov w4, w0
  ldr w5, =TAG_SET_GPIO_STATE
  mov w6, #130

  ldr w0, =property_buffer
  str wzr, [x0, #4]     // request
  str w5, [x0, #8]
  str w6, [x0, #20]     // pin 130
  str w4, [x0, #24]     // on/off
  // fall thru

// [w0: 32-bit addr]
// trash: x0 - x3
.global mailbox_send
mailbox_send:
  mov x3, lr
  ldr w1, =MAILBOX_BASE
1:
  bl delay_small
  ldr w2, [x1, #MAILBOX_STATUS_1]
  tbnz w2, #BIT_FULL, 1b
  add w0, w0, #PROPERTY
  str w0, [x1, #MAILBOX_RW_1]

  // now wait for the reply:
2:
  bl delay_small
  ldr w2, [x1, #MAILBOX_STATUS_0]
  tbnz w2, #BIT_EMPTY, 2b
  ldr w0, [x1, #MAILBOX_RW_0]
  ret x3


.data

// [ #bytes align(16), 0: request, (tag, #bytes req, #bytes resp, args...)* ]
.align 4
property_buffer:
  // 32 bytes(!)
  .word 32
  .word 0
  .word 0
  // our requests are always 8 bytes long:
  .word 8
  .word 0
  // 2 words of args, then end tag:
  .word 0
  .word 0
  .word 0

light:
  .word 0
