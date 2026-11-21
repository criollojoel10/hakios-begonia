#!/bin/bash
# Prepare the microSD for M2: raw request/log, the XNU system image and a data
# partition.  THIS DESTROYS THE CURRENT SD CONTENTS.
#
#   tools/sd-layout.sh [--dev /dev/mmcblk0] [--yes]
#   tools/sd-layout.sh --image FILE [--xnusys 64M] [--yes]   (test, no card)
#
# Without --yes it only prints the plan.  The target must be a removable block
# device and must not contain the running root.  Back up the SD first.
# --image builds the same GPT in a file (shrunk xnusys by default for a test).
set -euo pipefail
DEV=/dev/mmcblk0
IMAGE=
XNUSYS=8G
YES=0

while [ $# -gt 0 ]; do
    case "$1" in
    --dev) DEV="${2:?}"; shift 2 ;;
    --image) IMAGE="${2:?}"; shift 2 ;;
    --xnusys) XNUSYS="${2:?}"; shift 2 ;;
    --yes) YES=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -n "$IMAGE" ]; then
    [ -e "$IMAGE" ] || { echo "no image file: $IMAGE (create it with truncate)" >&2; exit 1; }
    cat <<EOF
Plan for image $IMAGE ($(stat -c %s "$IMAGE") bytes), test mode:
  1  hackios-request   1 MiB   raw
  2  hackios-log      64 MiB   raw
  3  xnusys            $XNUSYS   raw
  4  hackios-data      rest    ext4
EOF
    [ "$YES" -eq 1 ] || { echo; echo "Dry run. Re-run with --yes to write the GPT into the file."; exit 0; }
    command -v sfdisk >/dev/null || { echo "install util-linux (sfdisk)" >&2; exit 1; }
    sfdisk --no-tell-kernel "$IMAGE" <<EOF
label: gpt
start=2048, size=1M, name="hackios-request", type=linux
size=64M, name="hackios-log", type=linux
size=$XNUSYS, name="xnusys", type=linux
size=, name="hackios-data", type=linux
EOF
    python3 "$(dirname "$0")/check-sd-gpt.py" "$IMAGE" --xnusys "$XNUSYS"
    exit 0
fi

[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }
NAME="$(basename "$DEV")"
REM="$(cat "/sys/block/$NAME/removable" 2>/dev/null || echo 0)"
MODEL="$(cat "/sys/block/$NAME/device/name" 2>/dev/null || echo unknown)"
# The phone's SD slot reports removable=0 although the card is an SD32G; accept
# a card-like model name, but still never touch the device that holds the root.
if [ "$REM" != 1 ] && ! echo "$MODEL" | grep -qiE 'sd|card|mmc'; then
    echo "$DEV is not removable (model '$MODEL'; refusing to repartition it)" >&2
    exit 1
fi
ROOT="$(findmnt -n -o SOURCE /)"
case "$ROOT" in "$DEV"*) echo "$DEV contains the running root" >&2; exit 1 ;; esac
if findmnt -rn "$DEV" >/dev/null 2>&1; then
    echo "$DEV is mounted; unmount it first" >&2; exit 1
fi

cat <<EOF
Plan for $DEV ($(lsblk -dno SIZE "$DEV"), model $MODEL, removable=$REM):
  1  hackios-request   1 MiB   raw   (request string at sector 0)
  2  hackios-log      64 MiB   raw   (loader/XNU log)
  3  xnusys            $XNUSYS   raw   (XNU system image)
  4  hackios-data      rest    ext4  (your data; mounted by Linux)

The current partition table and ALL DATA on $DEV will be destroyed.
EOF

if [ "$YES" -ne 1 ]; then
    echo
    echo "Dry run. Re-run with --yes after a backup to apply."
    exit 0
fi

command -v sfdisk >/dev/null || { echo "install util-linux (sfdisk)" >&2; exit 1; }

sudo sfdisk --wipe always "$DEV" <<EOF
label: gpt
start=2048, size=1M, name="hackios-request", type=linux
size=64M, name="hackios-log", type=linux
size=$XNUSYS, name="xnusys", type=linux
size=, name="hackios-data", type=linux
EOF
sudo partprobe "$DEV" 2>/dev/null || sudo sfdisk -R "$DEV" || true
udevadm settle 2>/dev/null || true
sleep 1
# Verify what the kernel now sees before touching any filesystem.
sudo python3 "$(dirname "$0")/check-sd-gpt.py" "$DEV" --xnusys "$XNUSYS"

sudo mkfs.ext4 -F -L hackios-data "${DEV}p4"
sync

echo
echo "Done. Request: ${DEV}p1, log: ${DEV}p2, XNU system: ${DEV}p3, data: ${DEV}p4."
echo "The loader (M2) reads the raw partitions; Linux mounts ${DEV}p4."
