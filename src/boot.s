// assume r0-r4 are params, r12 is scratch (caller save).

.include "src/macros.s"
//"

.set stack, 0x7800
.set bootloader, 0x8000

.set TIMER_LO, 0x3f003004

.section ".text.boot"

.global _start
_start:
  mov sp, #stack
  push {r0, r1, r2}

  // kill all existing cores except #0.
  mrc p15, #0, r1, c0, c0, #5
  and r1, r1, #3
  cmp r1, #0
  bne halt

  // move code to $7800, then jump-absolute to it.
  ldr r0, =_start
  ldr r1, =bootloader
  ldr r2, =_end
1:
  ldmia r1!, {r8-r11}
  stmia r0!, {r8-r11}
  cmp r0, r2
  blo 1b

  ldr r0, =next
  bx r0

.text

next:
  bl toggle_light

  // r8: core, r9: uart
  bl clocks_get_info
  mov r8, r0
  mov r9, r1

  mov r0, r9
  ldr r1, =115200
  bl uart_init
  bl toggle_light

  ldr r11, =spinner
  ldr r10, =spinner_end
1:
  ldr r0, =banner
  ldr r1, =banner_end
  bl uart_write_string
  mov r0, r11
  add r1, r0, #1
  bl uart_write_string
  add r11, #1
  cmp r11, r10
  ldreq r11, =spinner

  ldr r0, =500000
  bl delay_usec
  bl toggle_light
  b 1b

// foo
  bl write_hex
  bl compute_crc32

halt:
  wfi
  b halt

delay_usec:
  dmb
  ldr r3, =TIMER_LO
  ldr r2, [r3]
  add r0, r2
1:
  dmb
  ldr r2, [r3]
  cmp r0, r2
  bhi 1b
  bx lr

toggle_light:
  push {lr}
  ldr r3, =light
  ldr r0, [r3]
  subs r0, #1
  movmi r0, #1
  str r0, [r3]
  bl set_led
  pop {lr}
  bx lr


.data

light:
  .word 0

// unaligned:

banner:
  .ascii "\rc3r3s "
banner_end:

spinner:
  .ascii "/-\\|"
spinner_end:
