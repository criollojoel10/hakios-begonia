#!/bin/bash
# Build begonia-chain.img: the M1 mtkchain loader in front of an existing
# Linux Android boot image.  Nothing is written to the phone.
#
#   tools/build-chain-image.sh [linux-boot.img] [xnu-payload]
#
# Default linux-boot.img: /home/alarm/boot-work/aboot-tfa2.img (the current
# Linux boot image).  The optional payload is a complete XNUP container made
# by the common tree's xnuloader/mkpayload.py; without it the loader only
# boots Linux (M1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-/home/alarm/boot-work/aboot-tfa2.img}"
PAYLOAD="${2:-}"
OUT="${OUT:-$ROOT/build/begonia-chain.img}"

[ -f "$SRC" ] || { echo "no such boot image: $SRC" >&2; exit 1; }
mkdir -p "$ROOT/build" "$ROOT/logs"

make -C "$ROOT/loader" >/dev/null

if [ -n "$PAYLOAD" ]; then
    python3 "$ROOT/tools/chainboot.py" "$SRC" "$ROOT/loader/chain.bin" "$OUT" "$PAYLOAD"
else
    python3 "$ROOT/tools/chainboot.py" "$SRC" "$ROOT/loader/chain.bin" "$OUT"
fi

python3 "$ROOT/tools/check-chain-image.py" "$OUT"
echo
echo "chain image: $OUT"
echo "test without touching boot:  fastboot boot $OUT"
echo "flash (after a verified backup): fastboot flash boot $OUT"
