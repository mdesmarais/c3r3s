AS = arm-none-eabi-as
CC = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
ASFLAGS = -mfloat-abi=hard -mcpu=cortex-a7

SOURCES = $(addprefix src/,boot.s crc.s div.s hex.s mailbox.s uart.s)
OBJECTS = $(patsubst src/%.s,target/%.o,$(SOURCES))

all: dist/kernel.img dist/fling

clean:
	rm -rf target dist
	(cd fling && cargo clean)

dist/kernel.img: target/c3r3s.elf
	mkdir -p dist
	$(OBJCOPY) target/c3r3s.elf -O binary dist/kernel.img

target/c3r3s.elf: target $(OBJECTS)
	$(CC) $(ASFLAGS) -n -T src/linker.ld -o target/c3r3s.elf -O2 -nostdlib -Wl,--gc-sections $(OBJECTS)
	size -A -x target/c3r3s.elf

target/%.o: src/%.s
	$(AS) $(ASFLAGS) -o $@ $<

target:
	mkdir -p target


# fling

dist/fling: fling/Cargo.* fling/src/*
	(cd fling && cargo build --release)
	mkdir -p dist
	cp fling/target/release/fling dist/fling

.PHONY: all clean
