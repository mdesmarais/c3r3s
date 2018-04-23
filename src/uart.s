.include "src/macros.s"
//"

.set GPIO_BASE, 0x3f200000
.set UART_BASE, 0x3f201000

// uart registers:
.set DR, 0
.set RDRECR, 4
.set FR, 0x18
.set IBRD, 0x24
.set FBRD, 0x28
.set LCRH, 0x2c
.set CR, 0x30
.set IFLS, 0x34
.set IMSC, 0x38
.set RIS, 0x3c
.set MIS, 0x40
.set ICR, 0x44
.set DMACR, 0x48

// gpio registers:
.set GPPUD, 0x94
.set GPPUDCLK0, 0x98
.set GPPUDCLK1, 0x9c

.set MODE_OFF, 0
.set TXD0, 14
.set RXD0, 15

.set USE_FIFO_8N1, 0x70
.set MASK_ALL, 0x7ff
.set ENABLE_RX_TX, 0x301

.set FR_TX_EMPTY, 0x80
.set FR_TX_FULL, 0x20
.set FR_RX_EMPTY, 0x10

.text

// [r0: uart_clock, r1: bps]
.global uart_init
uart_init:
  push {r4, r5, lr}

  // the baud divisor is stored as a 16Q6 fixed point, with the integer
  // part in IBRD and the fraction in FBRD. the manual says the divisor is
  // calculated from `uart_clock / (16 * bps)`.
  mov r0, r0, lsl #2
  bl divide
  and r5, r1, #0x3f
  mov r4, r1, lsr #6

  // shut off the uart
  ldr r3, =UART_BASE
  mov r0, #0
  str r0, [r3, #CR]

  // configure the RX/TX pins so they're not attached to the pulldown
  ldr r2, =GPIO_BASE
  mov r0, #MODE_OFF
  str r0, [r2, #GPPUD]
  delay 150
  mov r0, #((1 << TXD0) | (1 << RXD0))
  mov r1, #0
  str r0, [r2, #GPPUDCLK0]
  str r1, [r2, #GPPUDCLK1]
  delay 150
  mov r0, #0
  str r0, [r2, #GPPUDCLK0]
  str r0, [r2, #GPPUDCLK1]

  // clear all pending interrupts
  ldr r0, =MASK_ALL
  str r0, [r3, #ICR]

  // set bps
  str r4, [r3, #IBRD]
  str r5, [r3, #FBRD]

  // use fifo, set 8N1, and re-enable the uart
  mov r0, #USE_FIFO_8N1
  str r0, [r3, #LCRH]
  ldr r0, =MASK_ALL
  str r0, [r3, #IMSC]
  ldr r0, =ENABLE_RX_TX
  str r0, [r3, #CR]

  pop {r4, r5, lr}
  bx lr



@ // [r0] -> uart
@ .global uart_write
@ uart_write:
@   ldr r3, =UART_BASE
@ 1:
@   ldr r1, [r3, #FR]
@   tst r1, #FR_TX_FULL
@   bne 1b
@   str r0, [r3, #DR]
@   bx lr

// [r0: start, r1: end]
.global uart_write_string
uart_write_string:
  ldr r3, =UART_BASE
1:
  dmb
2:
  ldr r2, [r3, #FR]
  tst r2, #FR_TX_FULL
  bne 2b
  ldrb r2, [r0]
  str r2, [r3, #DR]
  add r0, r0, #1
  cmp r0, r1
  blo 1b

  bx lr

// -> [r0: non-zero if a byte was read]
.global uart_probe
uart_probe:
  mov r0, #0
  ldr r3, =UART_BASE
  dmb
  ldr r2, [r3, #FR]
  tst r2, #FR_RX_EMPTY
  ldreq r0, [r3, #DR]
  and r0, #0xff
  bx lr

// -> [r0], blocking, little-endian
.global uart_read_u32
uart_read_u32:
  // r0 = accumulator, r1 = shift
  mov r0, #0
  mov r1, #0
  ldr r3, =UART_BASE
1:
  dmb
  ldr r2, [r3, #FR]
  tst r2, #FR_RX_EMPTY
  bne 1b
  ldrb r2, [r3, #DR]
  add r0, r2, lsl r1
  add r1, #8
  cmp r1, #32
  blo 1b
  bx lr
