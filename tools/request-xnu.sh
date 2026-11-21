#!/bin/bash
# Ask the loader for one XNU boot.  The loader reads the request from:
#   1. /dev/hakios-ramoops at pmsg offset 0xd0000 (M1, linux/hakios_ramoops.ko), or
#   2. the microSD hackios-request partition (M2, raw sector 0).
# The request survives a warm reboot; the loader consumes/clears it.
set -euo pipefail
REQ="DARWIN-BEGONIA:BOOT-XNU"
RAMOOPS=/dev/hakios-ramoops
SD=/dev/disk/by-partlabel/hackios-request
NO_REBOOT=0
[ "${1:-}" = "--no-reboot" ] && NO_REBOOT=1

if [ -e "$RAMOOPS" ]; then
    printf '%s' "$REQ" | sudo dd of="$RAMOOPS" bs=1 seek=$((0xd0000)) conv=notrunc status=none
    echo "request written to $RAMOOPS pmsg (0xd0000)"
elif [ -e "$SD" ]; then
    printf '%s' "$REQ" | sudo dd of="$SD" bs=1 conv=notrunc status=none
    echo "request written to microSD $SD"
else
    echo "no $RAMOOPS and no $SD." >&2
    echo "Build/load linux/hakios_ramoops.ko (M1) or run tools/sd-layout.sh (M2)." >&2
    exit 1
fi

sync
echo "The next reboot will be requested as XNU; this kernel/loader is M1, so it will log the request and boot Linux."
if [ "$NO_REBOOT" -eq 0 ]; then
    sudo reboot
fi
