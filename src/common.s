/*
 * arm64 calling convention:
 *   - x0-x7: arguments, returns
 *   - x8-x18: scratch
 *   - x19-x29: callee-preserve
 *   - x30 = LR
 *   - x31 = SP
 */

.set TIMER_LO, 0x3f003004

// arbitrary "100 cycles" (destroys x8)
.global delay_small
delay_small:
  mov x8, #100
1:
  subs x8, x8, #1
  bpl 1b
  ret

.global delay_500ms
delay_500ms:
  ldr w0, =500000
  // fall thru

// use the system timer to do a wall-clock delay
// [w0: microseconds]
.global delay_usec
delay_usec:
  ldr w2, =TIMER_LO
  ldr w1, [x2]
  add w1, w0, w1
1:
  dmb sy
  ldar w0, [x2]
  cmp w0, w1
  b.ls 1b
  ret

//   push {lr}
//   ldr r3, =light
//   ldr r0, [r3]
//   subs r0, #1
//   movmi r0, #1
//   str r0, [r3]
//   bl set_led
//   pop {lr}
//   bx lr
