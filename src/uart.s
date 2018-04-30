.macro push a, b
  stp \a, \b, [sp, #-16]!
.endm

.macro pop a, b
  ldp \a, \b, [sp], #16
.endm

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

.set BIT_FR_TX_EMPTY, 7
.set BIT_FR_TX_FULL, 5
.set BIT_FR_RX_EMPTY, 4

.text

// [w0: uart_clock, w1: bps]
.global uart_init
uart_init:
  mov fp, lr

  // the baud divisor is stored as a 16Q6 fixed point, with the integer
  // part in IBRD and the fraction in FBRD. the manual says the divisor is
  // calculated from `uart_clock / (16 * bps)`.
  mov w0, w0, lsl #2
  udiv w0, w0, w1
  and w5, w0, #0x3f
  mov w4, w0, lsr #6

  // shut off the uart
  ldr w3, =UART_BASE
  str wzr, [x3, #CR]

  // configure the RX/TX pins so they're not attached to the pulldown
  ldr w2, =GPIO_BASE
  mov w0, #MODE_OFF
  str w0, [x2, #GPPUD]
  bl delay_small
  mov w0, #((1 << TXD0) | (1 << RXD0))
  str w0, [x2, #GPPUDCLK0]
  str wzr, [x2, #GPPUDCLK1]
  bl delay_small
  str wzr, [x2, #GPPUDCLK0]
  str wzr, [x2, #GPPUDCLK1]

  // clear all pending interrupts
  ldr w0, =MASK_ALL
  str w0, [x3, #ICR]

  // set bps
  str w4, [x3, #IBRD]
  str w5, [x3, #FBRD]

  // use fifo, set 8N1, and re-enable the uart
  mov w0, #USE_FIFO_8N1
  str w0, [x3, #LCRH]
  ldr w0, =MASK_ALL
  str w0, [x3, #IMSC]
  ldr w0, =ENABLE_RX_TX
  str w0, [x3, #CR]

  ret fp

// [w0] -> uart
// trash: x0 - x2
.global uart_write
uart_write:
  dmb sy
  ldr w2, =UART_BASE
1:
  ldr w1, [x2, #FR]
  tbnz w1, #BIT_FR_TX_FULL, 1b
  strb w0, [x2, #DR]
  ret

// [*w3] -> uart as LSB u32
// trash: x0 - x5
.global uart_write_word
uart_write_word:
  ldr w3, [x3]

// [w3] -> uart as LSB u32
// trash: x0 - x5
.global uart_write_u32
uart_write_u32:
  mov x5, lr
  mov w4, #0
1:
  lsr w0, w3, w4
  bl uart_write
  add w4, w4, #8
  tbz w4, #5, 1b
  ret x5

// -> [w0: byte if Z is clear]
// trash: x0 - x2
.global uart_probe
uart_probe:
  dmb sy
  ldr w2, =UART_BASE
  ldr w1, [x2, #FR]
  tst w1, #(1 << BIT_FR_RX_EMPTY)
  b.ne 1f
  ldrb w0, [x2, #DR]
1:
  ret

// read LSB u32 from uart
// -> [w3]
// trash: x0 - x5
.global uart_read_u32
uart_read_u32:
  // w3 = accumulator, w4 = shift
  mov x5, lr
  mov w4, #4
  mov w3, #0
1:
  bl uart_probe
  b.ne 1b
  // w3 = (w0 << 24) | (w3 >> 8)
  extr w3, w0, w3, #8
  subs w4, w4, #1
  b.ne 1b
  ret x5
