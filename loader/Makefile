CC = clang
LD = ld.lld
CFLAGS = --target=aarch64-linux-gnu -ffreestanding -nostdlib -fno-builtin \
	 -mgeneral-regs-only -mstrict-align -fno-stack-protector -Os -Wall -Wextra

all: chain.bin

start.o: start.S
	$(CC) $(CFLAGS) -c $< -o $@

chain.o: chain.c
	$(CC) $(CFLAGS) -c $< -o $@

chain.bin: start.o chain.o link.ld
	$(LD) -T link.ld --oformat binary start.o chain.o -o $@
	@ls -l $@

clean:
	rm -f *.o chain.bin

.PHONY: all clean
