#!/bin/bash
# Build mtkloader-begonia.bin: MT6785/begonia config, microSD (MSDC1) system
# image, begonia framebuffer, touch disabled by the stub.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
CC=${CC:-clang}
LD=${LD:-ld.lld}
CFLAGS="--target=aarch64-linux-gnu -ffreestanding -nostdlib -fno-builtin \
  -mgeneral-regs-only -mstrict-align -fno-stack-protector -Os -Wall -Wextra \
  -DBEGONIA -DXNU_ROOT_EMMC=0 \
  -DXNU_CORES=1 -DXNU_EXTRA_ARGS=\"cpus=1\" \
  -DXNU_RETURN_AFTER=\"30\" -DXNU_WATCH_SECONDS=45 \
  -I$HERE -I$HERE/../xnuloader"
$CC $CFLAGS -c "$HERE/start.S" -o "$HERE/start.o"
$CC $CFLAGS -c "$HERE/mtkloader.c" -o "$HERE/mtkloader.o"
$LD -T "$HERE/link.ld" --oformat binary "$HERE/start.o" "$HERE/mtkloader.o" -o "$HERE/mtkloader-begonia.bin"
ls -l "$HERE/mtkloader-begonia.bin"
