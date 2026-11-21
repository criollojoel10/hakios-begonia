#!/bin/bash
# Prepare the microSD for M2: raw request/log, the XNU system image and a data
# partition.  THIS DESTROYS THE CURRENT SD CONTENTS.
#
#   tools/sd-layout.sh [--dev /dev/mmcblk0] [--yes]
#
# Without --yes it only prints the plan.  The target must be a removable block
# device and must not contain the running root.  Back up the SD first.
set -euo pipefail
DEV=/dev/mmcblk0
YES=0

while [ $# -gt 0 ]; do
    case "$1" in
    --dev) DEV="${2:?}"; shift 2 ;;
    --yes) YES=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }
NAME="$(basename "$DEV")"
REM="$(cat "/sys/block/$NAME/removable" 2>/dev/null || echo 0)"
[ "$REM" = 1 ] || { echo "$DEV is not removable (refusing to repartition it)" >&2; exit 1; }
ROOT="$(findmnt -n -o SOURCE /)"
case "$ROOT" in "$DEV"*) echo "$DEV contains the running root" >&2; exit 1 ;; esac
if findmnt -rn "$DEV" >/dev/null 2>&1; then
    echo "$DEV is mounted; unmount it first" >&2; exit 1
fi

cat <<EOF
Plan for $DEV ($(lsblk -dno SIZE "$DEV")):
  1  hackios-request   1 MiB   raw   (request string at sector 0)
  2  hackios-log      64 MiB   raw   (loader/XNU log)
  3  xnusys            8 GiB   raw   (XNU system image)
  4  hackios-data      rest    ext4  (your data; mounted by Linux)

The current partition table and ALL DATA on $DEV will be destroyed.
EOF

if [ "$YES" -ne 1 ]; then
    echo
    echo "Dry run. Re-run with --yes after a backup to apply."
    exit 0
fi

command -v sgdisk >/dev/null || { echo "install gptfdisk (sgdisk)" >&2; exit 1; }
command -v partprobe >/dev/null || { echo "install parted (partprobe)" >&2; exit 1; }

sudo sgdisk --zap-all "$DEV"
sudo sgdisk -n 1:2048:+1M   -c 1:hackios-request -t 1:8300 "$DEV"
sudo sgdisk -n 2:0:+64M     -c 2:hackios-log     -t 2:8300 "$DEV"
sudo sgdisk -n 3:0:+8G      -c 3:xnusys          -t 3:8300 "$DEV"
sudo sgdisk -n 4:0:0        -c 4:hackios-data    -t 4:8300 "$DEV"
sudo partprobe "$DEV"
udevadm settle || true
sleep 1

sudo mkfs.ext4 -F -L hackios-data "${DEV}p4"
sync

echo
echo "Done. Request: ${DEV}p1, log: ${DEV}p2, XNU system: ${DEV}p3, data: ${DEV}p4."
echo "The loader (M2) reads the raw partitions; Linux mounts ${DEV}p4."
