# begonia Linux tuning: performance, brightness, charging

This is the **Linux side** of the phone (Arch Linux ARM + Phosh), not XNU. It
sets the daily-use knobs to their maximum and makes them survive a reboot. The
XNU side has its own loader and does not use these services.

## What was measured and what is applied

Measured with the phone running kernel 7.1.0 on 2026-11-23.

| Knob | Before | Applied | Where |
|---|---|---|---|
| CPU governor | `performance` (already) | `performance`, both policies | `/sys/devices/system/cpu/cpufreq/policy*` |
| CPU frequency | 2.00 / 2.05 GHz | same, at the top | `scaling_cur_freq` = `scaling_max_freq` |
| GPU (Mali-G76) | 900 MHz, `userspace` | 900 MHz, `userspace` | `/sys/class/devfreq/13040000.gpu` |
| Backlight | 1135 / 1879 (60 %) | **1879 / 1879** (hardware max) | `/sys/class/backlight/lm36274-backlight` |
| Idle dim | on, 30 % | **off** | `org.gnome.settings-daemon.plugins.power idle-dim false` |
| Ambient auto-brightness | on | **off** | `... ambient-enabled false` |
| Charge input limit | 1.0 A | **2.0 A** (source `current_max`; MT6360 AICR max 3.25 A) | `mt6360-chg*/input_current_limit` |
| Battery charge current | 1.5 A | **3.2 A** (top CCL step) | `mt6360-chg*/constant_charge_current` |
| Charge voltage | 4.35 V | **unchanged** | `constant_charge_voltage` |

The 3.2 A CCL is the highest value the MT6360 register returns
(`echo 3250000` reads back `3200000`); `constant_charge_current_max` reports
5 A but the register tops out at 3.2 A. The charge voltage stays at the
battery's 4.35 V: it is **not** raised, and `constant_charge_voltage_max`
(4.71 V) is a driver range, not a target.

## The current source is the real limit

The attached Type-C source reports `current_max = 2.0 A` (5 V, ~10 W) and the
MT6360 still presents itself as SDP in `usb_type`. With the CPU and GPU at the
top and the backlight at 1879, the phone's own load is several watts, so the
**net** battery current is small (tens of mA) even while `status` says
`Charging`. With a dedicated DCP/PD charger the script raises the input limit
to `min(source current_max, 3.25 A)`, so an 18 W (9 V/2 A) or 3 A source is used
fully.

`begonia-charge-boost.timer` re-reads the source every 30 s, so plugging a
better charger in is picked up without a reboot. It only writes when a value
changes and logs through `logger -t begonia-charge`.

> Forcing 2 A into a port that is really a 500 mA SDP port is outside the USB
> specification. The script trusts the Type-C source's `current_max`; if you
> use a plain PC port, expect slow charging and prefer not to keep the phone
> pinned at max performance/brightness while charging.

## Files

| File | Installed to |
|---|---|
| `config/begonia/charge-boost.sh` | `/usr/local/bin/begonia-charge-boost.sh` |
| `config/begonia/brightness-max.sh` | `/usr/local/bin/begonia-brightness-max.sh` |
| `config/begonia/begonia-performance.service` | `/etc/systemd/system/` |
| `config/begonia/begonia-charge-boost.service` | `/etc/systemd/system/` |
| `config/begonia/begonia-charge-boost.timer` | `/etc/systemd/system/` |
| `config/begonia/begonia-brightness.service` | `/etc/systemd/system/` |

`config/begonia/install.sh` copies them, reloads systemd and enables the
performance, charge-boost and brightness units. The brightness service runs
**after** `graphical.target` (5 s delay) so gsd-power cannot overwrite it with
the session's old value.

The session settings are per user; set them from the desktop session:

```bash
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false
gsettings set org.gnome.settings-daemon.plugins.power idle-brightness 100
```

Without `idle-dim false` the backlight drops to 30 % after the idle timeout
(576 of 1879) — that is the "low brightness" that was seen, not a panel limit.

## Verify

```bash
systemctl is-active begonia-performance.service begonia-charge-boost.timer begonia-brightness.service
/usr/local/bin/begonia-charge-boost.sh --status
cat /sys/class/backlight/lm36274-backlight/{brightness,max_brightness}
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo "$p $(cat $p/scaling_governor) $(cat $p/scaling_cur_freq)/$(cat $p/scaling_max_freq)"
done
cat /sys/class/devfreq/13040000.gpu/{cur_freq,max_freq,governor}
cat /sys/class/power_supply/battery/{status,capacity,voltage_now,current_now}
```

Expected: `performance` and the top frequency, GPU 900 MHz, backlight
1879/1879, charger `input=2000000 ccl=3200000 cv=4350000`.

## Risks and rollback

- **Heat and battery wear**: max CPU/GPU, max brightness and 3.2 A charging all
  add heat. The kernel's thermal throttling and the charger's own protection
  are **not** disabled; the battery health was `Good` when this was written.
- **Do not raise the charge voltage** above the battery's 4.35 V. The script
  never touches `constant_charge_voltage`.
- **Charging source**: the biggest risk is a weak port; see above.
- To undo:

```bash
sudo systemctl disable --now begonia-charge-boost.timer begonia-brightness.service
sudo systemctl disable --now begonia-performance.service
for d in /sys/class/power_supply/mt6360-chg*; do
  echo 1000000 | sudo tee "$d/input_current_limit"
  echo 1500000 | sudo tee "$d/constant_charge_current"
done
echo 1135 | sudo tee /sys/class/backlight/lm36274-backlight/brightness
# and, from the session:
gsettings set org.gnome.settings-daemon.plugins.power idle-dim true
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled true
```

This tuning does not touch the HackiOS loader, the boot partition or the XNU
window. The speaker remains `Speaker [off]` and `begonia-audio.service`
disabled.
