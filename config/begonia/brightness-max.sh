#!/bin/bash
# begonia: put the panel backlight at the hardware maximum (lm36274, 1879).
# A service after graphical.target runs it after gsd-power has restored the
# session's saved value; the slider can still lower it afterwards.
set -u
for b in /sys/class/backlight/*; do
    [ -w "$b/brightness" ] || continue
    max=$(cat "$b/max_brightness" 2>/dev/null || echo 0)
    [ "$max" -gt 0 ] || continue
    echo 0 > "$b/bl_power" 2>/dev/null || true
    echo "$max" > "$b/brightness" 2>/dev/null || true
    logger -t begonia-brightness "$(basename "$b"): $max"
done
exit 0
