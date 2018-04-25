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

  bl check_sync
  cmp r0, #0
  bne 2f

  ldr r0, =500000
  bl delay_usec
  bl toggle_light
  b 1b

2:
  // write "lstn", receive "send"
  ldr r0, =listen_word
  add r1, r0, #4
  bl uart_write_string
  ldr r0, =header
  ldr r1, =header_end
  bl uart_read_block
  ldr r0, =header
  ldr r0, [r0]
  ldr r1, =send_word
  ldr r1, [r1]
  cmp r0, r1
  bne fail

  // read blocks:
  //   - r7: origin
  //   - r8: current addr
  //   - r9: end addr
  //   - r10: count (so far)
  //   - r11: current block size
  ldr r0, =header_origin
  ldr r7, [r0]
  mov r8, r7
  ldr r0, =header_size
  ldr r9, [r0]
  add r9, r7
  mov r10, #0

  cmp r8, r9
  bhs 4f
3:
  // read one block
  bl uart_read_u32
  mov r11, r0
  mov r1, r8
  add r1, r0
  mov r0, r8
  bl uart_read_block
  add r8, r11
  mov r0, r8
  sub r0, r7
  bl uart_write_u32
  cmp r8, r9
  blo 3b

4:
  // read crc32
  bl uart_read_u32
  mov r11, r0
  mov r0, r7
  mov r1, r9
  bl compute_crc32
  cmp r11, r0
  bne fail

  // send "good", wait 1 second, then jump to the origin!
  ldr r0, =good_word
  add r1, r0, #4
  bl uart_write_string

  bl toggle_light
  ldr r0, =#1000000
  bl delay_usec
  bl toggle_light

  // reload r0-r2
  pop {r0, r1, r2}
  bx r7

fail:
  ldr r0, =fail_word
  add r1, r0, #4
  bl uart_write_string
  b halt

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

// ----- protocol.s

// probe for the "boot" sync from the host
.global check_sync
check_sync:
  push {r4, r5, r6, r7, lr}
  ldr r4, =sync_state
  ldr r5, [r4]
  ldr r6, =sync_word

1:
  ldrb r7, [r6, r5]
  bl uart_probe
  cmp r0, #0
  beq 3f

  cmp r0, r7
  movne r5, #0
  addeq r5, #1
  str r5, [r4]
  movne r0, #0
  bne 3f

  // got one!
  cmp r5, #4
  blo 1b

2:
  // got it all!
  mov r0, #1
3:
  pop {r4, r5, r6, r7, lr}
  bx lr


.data

light:
  .word 0
sync_state:
  .word 0
sync_word:
  .ascii "boot"
listen_word:
  .ascii "lstn"
send_word:
  .ascii "send"
good_word:
  .ascii "good"
fail_word:
  .ascii "fail"

header:
  .word 0
header_origin:
  .word 0
header_size:
  .word 0
header_end:

banner:
  .ascii "\rc3r3s "
  .byte 0  // alignment
banner_end:

spinner:
  .ascii "/-\\|"
spinner_end:
