#!/bin/bash
# Read the last loader/XNU log after booting Linux.
#
#   tools/capture-boot-log.sh [auto|ramoops|sd] [device]
#
# ramoops (M1): /dev/hakios-ramoops, console at offset 0x8f000 (0x40000),
#               pmsg at 0xd0000 (0x10000).
# sd (M2):     the raw microSD hackios-log partition (default
#               /dev/disk/by-partlabel/hackios-log) or a saved file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-auto}"
mkdir -p "$ROOT/logs"

if [ "$MODE" = auto ]; then
    if [ -e /dev/hakios-ramoops ]; then MODE=ramoops; else MODE=sd; fi
fi

case "$MODE" in
ramoops)
    SRC=/dev/hakios-ramoops
    [ -e "$SRC" ] || { echo "missing $SRC; build/load linux/hakios_ramoops.ko" >&2; exit 1; }
    sudo dd if="$SRC" of="$ROOT/logs/ramoops-console.bin" bs=4096 \
        skip=$((0x8f000 / 4096)) count=$((0x40000 / 4096)) status=none
    sudo dd if="$SRC" of="$ROOT/logs/ramoops-pmsg.bin" bs=4096 \
        skip=$((0xd0000 / 4096)) count=$((0x10000 / 4096)) status=none
    echo "=== ramoops console (strings) ==="
    strings "$ROOT/logs/ramoops-console.bin" | tail -80
    echo
    echo "=== ramoops pmsg ==="
    strings "$ROOT/logs/ramoops-pmsg.bin" | tail -20
    echo
    echo "saved: $ROOT/logs/ramoops-console.bin, $ROOT/logs/ramoops-pmsg.bin"
    ;;
sd)
    SRC="${2:-/dev/disk/by-partlabel/hackios-log}"
    [ -e "$SRC" ] || { echo "missing $SRC; run tools/sd-layout.sh (M2)" >&2; exit 1; }
    sudo dd if="$SRC" of="$ROOT/logs/hackios-log.bin" bs=1M status=none
    echo "=== microSD hackios-log (strings) ==="
    strings "$ROOT/logs/hackios-log.bin" | tail -120
    echo
    echo "saved: $ROOT/logs/hackios-log.bin"
    ;;
*)
    echo "usage: $0 [auto|ramoops|sd] [device]" >&2
    exit 2
    ;;
esac
