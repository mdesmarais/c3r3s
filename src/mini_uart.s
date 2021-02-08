.macro push a, b
  stp \a, \b, [sp, #-16]!
.endm

.macro pop a, b
  ldp \a, \b, [sp], #16
.endm

.set GPIO_BASE, 0x3f200000
.set UART_BASE, 0x3f215000

// uart registers:
.set AUX_ENB, 0x4
.set AUX_MU_IO, 0x40
.set AUX_MU_IER, 0x44
.set AUX_MU_IIR, 0x48
.set AUX_MU_LCR, 0x4c
.set AUX_MU_MCR, 0x50
.set AUX_MU_LSR, 0x54
.set AUX_MU_CNTL, 0x60
.set AUX_MU_BAND, 0x68

// gpio registers:
.set GPFSEL1, 0x4
.set GPPUD, 0x94
.set GPPUDCLK0, 0x98
.set GPPUDCLK1, 0x9c

.set MODE_OFF, 0
.set TXD0, 14
.set RXD0, 15

.text

// [w0: uart_clock, w1: bps]
.global uart_init
uart_init:
  mov fp, lr

  ldr w3, =UART_BASE
  mov w0, #1
  str w0, [x3, #AUX_ENB]

  // Auto-flow control is disabled, same for receiver and transmitter before configuration is done
  str wzr, [x3, #AUX_MU_CNTL]

  // Disable interrupts
  str wzr, [x3, #AUX_MU_IER]

  mov w0, #0xc6
  str w0, [x3, #AUX_MU_IIR]

  // 8 bit mode
  mov w0, #3
  str w0, [x3, #AUX_MU_LCR]

  // Without the auto-flow control mode, the RTS line should always set to HIGH
  str wzr, [x3, #AUX_MU_MCR]

  // Baudrate of 115200
  mov w0, #270
  str w0, [x3, #AUX_MU_BAND]

  // configure the RX/TX pins so they're not attached to the pulldown
  ldr w2, =GPIO_BASE
  mov w0, #(2 << 12)
  eor w0, w0, #(2 << 15)
  str w0, [x2, GPFSEL1]

  str wzr, [x2, #GPPUD]
  mov w0, #150
  bl delay_small
  mov w0, #((1 << TXD0) | (1 << RXD0))
  str w0, [x2, #GPPUDCLK0]
  str wzr, [x2, #GPPUDCLK1]
  mov w0, #150
  bl delay_small
  str wzr, [x2, #GPPUDCLK0]
  str wzr, [x2, #GPPUDCLK1]

  // Enables transmitter and receiver
  mov w0, #3
  str w0, [x3, #AUX_MU_CNTL]

  ret fp

.global uart_stop
uart_stop:
  ldr w3, =UART_BASE
  str wzr, [x3, #AUX_ENB]
  ret

// [w0] -> uart
// trash: x0 - x2
.global uart_write
uart_write:
  dmb sy
  ldr w2, =UART_BASE
1:
  ldr w1, [x2, #AUX_MU_LSR]
  tst w1, #0x20
  b.eq 1b // If Z flag has been set then the bus is not ready yet
  // Dirty hack to write only byte on the transmitter queue
  mov w1, #0xff
  and w1, w0, w1
  //strb w0, [x2, #AUX_MU_IO]
  str w1, [x2, #AUX_MU_IO]
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
  tbz w4, #5, 1b // 32 -> 100000 in binary, bit 5 is 1. Loop while this bit is 0
  ret x5

// -> [w0: byte if Z is clear]
// trash: x0 - x2
.global uart_probe
uart_probe:
  dmb sy
  ldr w2, =UART_BASE
  ldr w1, [x2, #AUX_MU_LSR]
  mvn w1, w1 // POUET
  tst w1, #0x1
  b.ne 1f // Z is set, no value is ready yet
  ldr w0, [x2, #AUX_MU_IO]
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
  b.ne 1b // Waits until a byte is ready to read
  // w3 = (w0 << 24) | (w3 >> 8)
  extr w3, w0, w3, #8
  subs w4, w4, #1
  b.ne 1b
  ret x5
