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
BOOT=${1:?usage: m2-chain.sh <linux-boot.img> (- | <xnu-kernel> <ramdisk>) [out.img]}
shift
KERNEL=
RAMDISK=
OUT=/tmp/begonia-m2-chain.img
if [ "${1:-}" = "-" ]; then
    shift                      # Linux only: the next argument, if any, is the output
    [ $# -ge 1 ] && OUT=$1
else
    KERNEL=${1:?pass - for a Linux-only chain, or the XNU kernel}
    shift
    RAMDISK=${1:?the XNU payload needs a ramdisk too}
    shift
    [ $# -ge 1 ] && OUT=$1
fi
LOADER=$HERE/mtkloader/mtkloader-begonia.bin

[ -f "$LOADER" ] || "$HERE/mtkloader/build-begonia.sh"

if [ -n "$KERNEL" ]; then
    PAYLOAD=${PAYLOAD:-$HERE/build/xnu-begonia.payload}
    python3 "$HERE/xnuloader/mkpayload.py" -o "$PAYLOAD" \
        kernel="$KERNEL" ramdisk="$RAMDISK" --cmdline=-v
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
