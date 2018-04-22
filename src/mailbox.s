.include "src/macros.s"
//"

.set MAILBOX_BASE, 0x3f00b880
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
.global clocks_get_info
clocks_get_info:
  push {lr}

  ldr r0, =property_buffer
  mov r1, #0
  ldr r2, =TAG_CLOCK_GET_RATE
  mov r3, #8

  str r1, [r0, #4]

  str r2, [r0, #8]
  str r3, [r0, #12]
  str r1, [r0, #16]
  ldr r12, =CLOCK_CORE
  str r12, [r0, #20]
  str r1, [r0, #24]

  str r2, [r0, #28]
  str r3, [r0, #32]
  str r1, [r0, #36]
  ldr r12, =CLOCK_UART
  str r12, [r0, #40]
  str r1, [r0, #44]

  str r1, [r0, #48]
  bl mailbox_send

  ldr r0, =property_buffer
  ldr r1, [r0, #44]
  ldr r0, [r0, #24]

  pop {lr}
  bx lr

// [r0: active_low]
.global set_led
set_led:
  push {r4, lr}
  mov r4, r0

  ldr r0, =property_buffer
  mov r1, #0
  ldr r2, =TAG_SET_GPIO_STATE
  mov r3, #8

  str r1, [r0, #4]

  str r2, [r0, #8]
  str r3, [r0, #12]
  str r1, [r0, #16]
  mov r12, #130
  str r12, [r0, #20]
  str r4, [r0, #24]

  str r1, [r0, #28]
  bl mailbox_send

  pop {r4, lr}
  bx lr

// [r0: addr]
.global mailbox_send
mailbox_send:
  push {r4, r5, r6, lr}
  mov r4, r0
  ldr r5, =MAILBOX_BASE
  dmb
1:
  ldr r6, [r5, #MAILBOX_STATUS_1]
  ands r6, r6, #FULL
  beq 2f
  delay 100
  b 1b
2:
  add r4, r4, #PROPERTY
  str r4, [r5, #MAILBOX_RW_1]

  // now wait for the reply:
  dmb
3:
  ldr r6, [r5, #MAILBOX_STATUS_0]
  ands r6, r6, #EMPTY
  beq 4f
  delay 100
  b 3b
4:
  ldr r0, [r5, #MAILBOX_RW_0]
  pop {r4, r5, r6, lr}
  mov pc, lr


.data

// [ #bytes align(16), 0: request, (tag, #bytes req, #bytes resp, args...)* ]
.align 4
property_buffer:
  // 64 bytes(!)
  .word 64
  .rept 15
  .word 0
  .endr
