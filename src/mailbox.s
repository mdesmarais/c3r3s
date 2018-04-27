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
.set FULL, (1 << 31)
.set EMPTY, (1 << 30)

.set TAG_CLOCK_GET_RATE, 0x00030002
.set TAG_SET_GPIO_STATE, 0x00038041

.set CLOCK_CORE, 4
.set CLOCK_UART, 2

.text

// -> [r0: core, r1: uart]
// .global clocks_get_info
// clocks_get_info:
//   push {lr}
//
//   ldr r0, =property_buffer
//   mov r1, #0
//   ldr r2, =TAG_CLOCK_GET_RATE
//   mov r3, #8
//
//   str r1, [r0, #4]
//
//   str r2, [r0, #8]
//   str r3, [r0, #12]
//   str r1, [r0, #16]
//   ldr r12, =CLOCK_CORE
//   str r12, [r0, #20]
//   str r1, [r0, #24]
//
//   str r2, [r0, #28]
//   str r3, [r0, #32]
//   str r1, [r0, #36]
//   ldr r12, =CLOCK_UART
//   str r12, [r0, #40]
//   str r1, [r0, #44]
//
//   str r1, [r0, #48]
//   bl mailbox_send
//
//   ldr r0, =property_buffer
//   ldr r1, [r0, #44]
//   ldr r0, [r0, #24]
//
//   pop {lr}
//   bx lr

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
  ldr w5, =TAG_SET_GPIO_STATE
  mov w6, #8
  mov w7, #130

  ldr w4, =property_buffer
  str wzr, [x4, #4]     // request
  str w5, [x4, #8]
  str w6, [x4, #12]     // len = 8
  str wzr, [x4, #16]
  str w7, [x4, #20]     // pin 130
  str w0, [x4, #24]     // on/off
  str wzr, [x4, #28]
  mov x0, x4
  // fall thru

// [w0: 32-bit addr]
.global mailbox_send
mailbox_send:
  push fp, lr
  dmb sy
  ldr w1, =MAILBOX_BASE
1:
  bl delay_small
  add x2, x1, #MAILBOX_STATUS_1
  ldar w2, [x2]
  tst w2, #FULL
  b.ne 1b

  add w0, w0, #PROPERTY
  add x2, x1, #MAILBOX_RW_1
  stlr w0, [x2]

  // now wait for the reply:
2:
  bl delay_small
  add x2, x1, #MAILBOX_STATUS_0
  ldar w2, [x2]
  tst w2, #EMPTY
  b.ne 2b

  add x2, x1, #MAILBOX_RW_0
  ldar w0, [x2]
  pop fp, lr
  ret


.data

// [ #bytes align(16), 0: request, (tag, #bytes req, #bytes resp, args...)* ]
.align 4
property_buffer:
  // 64 bytes(!)
  .word 64
  .rept 15
  .word 0
  .endr

light:
  .word 0
