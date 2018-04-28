/*
 * arm64 calling convention:
 *   - x0-x7: arguments, returns
 *   - x8-x18: scratch
 *   - x19-x29: callee-preserve
 *   - x30 = LR
 *   - x31 = SP
 */

.set TIMER_LO, 0x3f003004

// arbitrary "100 cycles" (destroys ip1), then add a memory barrier
.global delay_small
delay_small:
  mov ip1, #100
1:
  subs ip1, ip1, #1
  bpl 1b
  dmb sy
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
  ldr w0, [x2]
  cmp w0, w1
  b.ls 1b
  ret
