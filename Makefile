AS := aarch64-linux-gnu-as
LD := aarch64-linux-gnu-ld
OBJCOPY := aarch64-linux-gnu-objcopy

AS_FLAGS := -mcpu=cortex-a53

# Available files : mini_uart.s and uart.s
UART := mini_uart.s

SOURCES := $(addprefix src/, boot64.s common.s mailbox.s protocol.s $(UART))
OBJECTS := $(patsubst src/%.s,target/%.o,$(SOURCES))

all: c3r3s

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

run: c3r3s
	qemu-system-aarch64 -M raspi3 -kernel dist/kernel8.img -serial stdio

debug: c3r3s
	qemu-system-aarch64 -s -S -M raspi3 -kernel dist/kernel8.img -serial null -serial stdio

dump: target/c3r3s.elf
	aarch64-linux-gnu-objdump -D $< > dump

# fling

dist/fling: fling/Cargo.* fling/src/*
	(cd fling && cargo build --release)
	mkdir -p dist
	cp fling/target/release/fling dist/fling

.PHONY: all clean c3r3s fling debug run dump
