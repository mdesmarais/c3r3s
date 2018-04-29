ENTRY(start)

SECTIONS {
  . = 0x7fc00;
  start = .;

  .text : {
    KEEP(*(.text.boot))
    *(.text)
  }

  . = ALIGN(16);
  .data : {
    *(.data)
  }

  . = ALIGN(16);
  end = .;
}
