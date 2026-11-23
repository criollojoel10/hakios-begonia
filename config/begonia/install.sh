#!/bin/bash
# Install the begonia Linux tuning: CPU/GPU performance, backlight max, charge
# limits.  Run as root from the repository.  Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
install -m 0755 "$HERE/charge-boost.sh" /usr/local/bin/begonia-charge-boost.sh
install -m 0755 "$HERE/brightness-max.sh" /usr/local/bin/begonia-brightness-max.sh
install -m 0644 "$HERE/begonia-performance.service" /etc/systemd/system/
install -m 0644 "$HERE/begonia-charge-boost.service" /etc/systemd/system/
install -m 0644 "$HERE/begonia-charge-boost.timer" /etc/systemd/system/
install -m 0644 "$HERE/begonia-brightness.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now begonia-performance.service
systemctl enable --now begonia-charge-boost.timer
systemctl enable --now begonia-brightness.service
/usr/local/bin/begonia-charge-boost.sh --status

# The session settings: no idle dim, no ambient auto-brightness.  Run as the
# desktop user (or set them from that session):
#   gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
#   gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false
#   gsettings set org.gnome.settings-daemon.plugins.power idle-brightness 100
