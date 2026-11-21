#!/bin/bash
# Build the M2 chain image: Android boot image (Linux Image, ramdisk, DTB)
#   -> mtkloader-begonia (runs first)
#   -> optional XNU "XNUP" payload (kernel + ramdisk)
# The loader boots Linux by default and XNU once when the pmsg request
# "DARWIN-BEGONIA:BOOT-XNU" is present.
#
#   tools/m2-chain.sh <linux-boot.img> <xnu-kernel> [ramdisk] [out.img]
#
# Without <xnu-kernel> it builds the Linux-only chain (useful to verify the
# loader on hardware before adding XNU).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BOOT=${1:?usage: m2-chain.sh <linux-boot.img> <xnu-kernel> [ramdisk] [out.img]}
KERNEL=${2:?}
RAMDISK=${3:-}
OUT=${4:-/tmp/begonia-m2-chain.img}
LOADER=$HERE/mtkloader/mtkloader-begonia.bin

[ -f "$LOADER" ] || "$HERE/mtkloader/build-begonia.sh"

if [ -n "$KERNEL" ] && [ -n "$RAMDISK" ]; then
    python3 "$HERE/xnuloader/mkpayload.py" -o /tmp/xnu-begonia.payload \
        kernel="$KERNEL" ramdisk="$RAMDISK" --cmdline=-v
    PAYLOAD=/tmp/xnu-begonia.payload
elif [ -n "$KERNEL" ] && [ "$KERNEL" != "-" ]; then
    echo "m2-chain: pass a ramdisk too (the XNU payload needs kernel + ramdisk)" >&2
    exit 1
else
    PAYLOAD=
fi

if [ -n "$PAYLOAD" ]; then
    python3 "$HERE/tools/chainboot.py" "$BOOT" "$LOADER" "$OUT" "$PAYLOAD"
else
    python3 "$HERE/tools/chainboot.py" "$BOOT" "$LOADER" "$OUT"
fi
python3 "$HERE/tools/check-chain-image.py" "$OUT"
ls -lh "$OUT"
