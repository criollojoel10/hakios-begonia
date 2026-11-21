obj-m += hakios_ramoops.o

KDIR ?= /home/alarm/kw/src/linux-7.1-r0
LLVM ?= 1

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) LLVM=$(LLVM) KBUILD_MODPOST_WARN=1 modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
