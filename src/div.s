// [r0: num, r1: den] -> [r0: remainder, r1: quotient]
// assumes num >= den.
.global divide
divide:
  // r3 = leading_zeros(den) - leading_zeros(num)
  // (this is how many times we have to shift-and-compare)
  clz r3, r0
  clz r2, r1
  sub r3, r2, r3
  // r2 = quotient
  mov r2, #0
1:
  // X = (den << r3). if num >= X, rotate a bit into Q, and subtract X from num.
  cmp r0, r1, lsl r3
  adc r2, r2, r2
  subcs r0, r0, r1, lsl r3
  // r3--, loop until r3 < 0.
  subs r3, r3, #1
  bpl 1b
  mov r1, r2
  bx lr
