AS := aarch64-none-elf-as
LD := aarch64-none-elf-ld
OBJCOPY := aarch64-none-elf-objcopy

AS_FLAGS := -mcpu=cortex-a53

SOURCES := $(addprefix src/, boot64.s common.s mailbox.s protocol.s uart.s)
OBJECTS := $(patsubst src/%.s,target/%.o,$(SOURCES))

all: c3r3s fling

c3r3s: dist/kernel8.img

fling: dist/fling

clean:
	rm -rf target dist
	(cd fling && cargo clean)

dist/kernel8.img: target/c3r3s.elf
	mkdir -p dist
	$(OBJCOPY) target/c3r3s.elf -O binary dist/kernel8.img

target/c3r3s.elf: target $(OBJECTS)
	$(LD) -T src/linker.ld -o target/c3r3s.elf --gc-sections $(OBJECTS)
	size -A -x target/c3r3s.elf

target/%.o: src/%.s
	$(AS) $(AS_FLAGS) -o $@ $<

target:
	mkdir -p target


# fling

dist/fling: fling/Cargo.* fling/src/*
	(cd fling && cargo build --release)
	mkdir -p dist
	cp fling/target/release/fling dist/fling

.PHONY: all clean c3r3s fling
