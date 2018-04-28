ENTRY(_start)

SECTIONS {
  . = 0x7fc00;
  _start = .;

  .text : {
    KEEP(*(.text.boot))
    *(.text)
  }

  . = ALIGN(16);
  _data_start = .;
  .data : {
    *(.data)
  }

  . = ALIGN(16);
  _end = .;
}
