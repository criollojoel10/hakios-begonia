#!/bin/bash
# begonia: raise the MT6360 limits to what the attached source can deliver.
# - input current: min(source current_max, MT6360 AICR max 3.25 A)
# - battery current: 3.2 A (the CCL register's top step for this charger)
# - charge voltage is NOT changed (the battery's 4.35 V stays)
# Idempotent; safe to run on every power_supply change or from a timer.
set -u
AICR_MAX=3250000
CCL_MAX=3200000

src=2000000
for s in /sys/class/power_supply/tcpm-source-psy-*; do
    [ -r "$s/current_max" ] || continue
    m=$(cat "$s/current_max" 2>/dev/null) || continue
    case "$m" in ''|*[!0-9]*) continue ;; esac
    [ "$m" -gt 0 ] && src=$m
done
[ "$src" -gt "$AICR_MAX" ] && src=$AICR_MAX
[ "$src" -lt 500000 ] && src=500000

for d in /sys/class/power_supply/mt6360-chg*; do
    [ -w "$d/input_current_limit" ] || continue
    cur=$(cat "$d/input_current_limit" 2>/dev/null || echo 0)
    [ "$cur" != "$src" ] && echo "$src" > "$d/input_current_limit" 2>/dev/null || true
    ccl=$(cat "$d/constant_charge_current" 2>/dev/null || echo 0)
    [ "$ccl" != "$CCL_MAX" ] && echo "$CCL_MAX" > "$d/constant_charge_current" 2>/dev/null || true
    logger -t begonia-charge "$(basename "$d"): input ${src}uA, battery ${CCL_MAX}uA"
done
if [ "${1:-}" = "--status" ]; then
    for d in /sys/class/power_supply/mt6360-chg*; do
        echo "$(basename "$d"): input=$(cat "$d/input_current_limit" 2>/dev/null) ccl=$(cat "$d/constant_charge_current" 2>/dev/null) cv=$(cat "$d/constant_charge_voltage" 2>/dev/null)"
    done
    # MT6360 ADC: ibus/ibat/vbus say what the source actually delivers (mA/mV).
    adc=
    for d in /sys/bus/iio/devices/iio:device*; do
        case "$(cat "$d/name" 2>/dev/null)" in mt6360-adc*) adc=$d ;; esac
    done
    if [ -n "$adc" ]; then
        ibus=$(( $(cat "$adc/in_current5_raw") * $(cat "$adc/in_current5_scale") / 1000 ))
        ibat=$(( $(cat "$adc/in_current6_raw") * $(cat "$adc/in_current6_scale") / 1000 ))
        vbus=$(( $(cat "$adc/in_voltage2_raw") * $(cat "$adc/in_voltage2_scale") / 1000 ))
        echo "adc: ibus=${ibus}mA ibat=${ibat}mA vbus=${vbus}mV (VINDPM at 4.5 V means the source/cable is the limit)"
    fi
    for f in status capacity voltage_now current_now; do
        echo "battery.$f=$(cat /sys/class/power_supply/battery/$f 2>/dev/null)"
    done
    echo "source_max=$(cat /sys/class/power_supply/tcpm-source-psy-*/current_max 2>/dev/null) source_type=$(cat /sys/class/typec/port0-partner/type 2>/dev/null)"
fi
exit 0
