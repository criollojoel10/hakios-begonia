#!/bin/bash
# One command for the M2 images: mtkloader + Linux-only chain + XNU hello chain.
#
#   tools/build-m2.sh [linux-boot.img]
#
# Env: BOOT_IMG (default /home/alarm/boot-work/aboot-tfa2.img),
#      XNU_KERNEL (default xnu/hakios-kernel), HELLO (default build/hello).
# If the kernel/hello are missing it runs tools/fetch-xnu.sh (needs gh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
BOOT=${1:-${BOOT_IMG:-/home/alarm/boot-work/aboot-tfa2.img}}
KERNEL=${XNU_KERNEL:-xnu/hakios-kernel}
HELLO=${HELLO:-build/hello}

[ -f "$BOOT" ] || { echo "build-m2: no Linux boot image: $BOOT" >&2; exit 1; }
if [ ! -f "$KERNEL" ] || [ ! -f "$HELLO" ]; then
    echo "build-m2: kernel or hello missing; fetching from the CI/reference"
    tools/fetch-xnu.sh
    KERNEL=xnu/hakios-kernel
    HELLO=build/hello
fi
file "$KERNEL" | grep -q 'Mach-O' || { echo "build-m2: $KERNEL is not a Mach-O" >&2; exit 1; }
file "$HELLO" | grep -q 'Mach-O' || { echo "build-m2: $HELLO is not a Mach-O" >&2; exit 1; }

mtkloader/build-begonia.sh
tools/m2-chain.sh "$BOOT" - build/begonia-m2-linux.img
tools/m2-chain.sh "$BOOT" "$KERNEL" "$HELLO" build/begonia-m2-hello.img
echo
sha256sum build/begonia-m2-linux.img build/begonia-m2-hello.img "$KERNEL" "$HELLO"
