// not any known time unit, just "loop count"
.macro delay cycles
  mov r0, #\cycles
1:
  subs r0, r0, #1
  bpl 1b
.endm
