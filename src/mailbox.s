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
  ldr w5, =TAG_CLOCK_GET_RATE
  mov w6, #8
  mov w7, #CLOCK_UART

  ldr w0, =property_buffer
  str wzr, [x0, #4]     // request
  str w5, [x0, #8]
  str w6, [x0, #12]     // len = 8
  str wzr, [x0, #16]
  str w7, [x0, #20]     // uart
  stp wzr, wzr, [x0, #24]
  push x0, lr
  bl mailbox_send
  pop x0, lr
  ldr x0, [x0, #24]
  ret

.global toggle_light
toggle_light:
  adr x1, light
  ldr w0, [x1]
  eor w0, w0, #1
  str w0, [x1]
  // fall thru

// [w0: active_low]
.global set_led
set_led:
  mov w4, w0
  ldr w5, =TAG_SET_GPIO_STATE
  mov w6, #8
  mov w7, #130

  ldr w0, =property_buffer
  str wzr, [x0, #4]     // request
  str w5, [x0, #8]
  str w6, [x0, #12]     // len = 8
  str wzr, [x0, #16]
  str w7, [x0, #20]     // pin 130
  str w4, [x0, #24]     // on/off
  str wzr, [x0, #28]    // end
  // fall thru

// [w0: 32-bit addr]
.global mailbox_send
mailbox_send:
  mov x3, lr
  dmb sy
  ldr w1, =MAILBOX_BASE
1:
  bl delay_small
  dmb sy
  ldr w2, [x1, #MAILBOX_STATUS_1]
  tbnz w2, #BIT_FULL, 1b
  add w0, w0, #PROPERTY
  str w0, [x1, #MAILBOX_RW_1]

  // now wait for the reply:
2:
  bl delay_small
  dmb sy
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
  .rept 7
  .word 0
  .endr

light:
  .word 0
