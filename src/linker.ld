ENTRY(_start)

SECTIONS {
  . = 0x7800;
  _start = .;

  .text 0x7800 : {
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
