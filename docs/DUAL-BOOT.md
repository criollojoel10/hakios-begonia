# Dual boot: Linux (default) and XNU (requested)

The invariant: **the daily Linux installation keeps booting by default**. XNU
is an opt-in one-shot boot; after it returns, Linux comes back. Nothing on the
Linux root is modified.

## 1. The boot image chain

```text
boot partition /dev/sdc34 (64 MiB, Android header v2)
  kernel = gzip( mtkchain-begonia | Linux arm64 Image | optional XNU payload )
  ramdisk + DTB from the current Linux installation
```

LK decompresses the kernel to `0x40080000` and enters the loader with
`x0 = LK's DTB`. `mtkchain-begonia`:

1. scans the ramoops pmsg zone for `DARWIN-BEGONIA:BOOT-XNU`;
2. logs to the ramoops console;
3. copies the Linux Image down to `0x40080000` and starts it (default), or, in
   M2, starts the XNU payload when the request is present;
4. clears the request.

`tools/chainboot.py` builds the image; `tools/check-chain-image.py` verifies the
header, the Linux Image length (`res2`), the optional payload offset (`res3`)
and the 64 MiB limit.

## 2. M1: the control loop (no XNU yet)

M1 is the dry run that proves the chain and the logs before the XNU payload
exists.

```bash
# build from the current Linux boot image
tools/build-chain-image.sh /home/alarm/boot-work/aboot-tfa2.img

# try without writing boot (if the bootloader supports it)
fastboot boot build/begonia-chain.img

# or, after a verified backup of /dev/sdc34:
sudo dd if=/dev/sdc34 of=/home/alarm/boot-work/boot-backup-new.img bs=1M
fastboot flash boot build/begonia-chain.img
```

After Linux boots:

```bash
cd linux && make KDIR=/home/alarm/kw/src/linux-7.1-r0
sudo insmod hakios_ramoops.ko
../tools/capture-boot-log.sh ramoops       # mtkchain banner, request: Linux
../tools/request-xnu.sh --no-reboot        # writes the request
sudo reboot
../tools/capture-boot-log.sh ramoops       # request: XNU; M1 dry-run; request cleared
```

The M1 log makes the loop observable: `request: XNU`, `XNU requested; M1
dry-run, no XNU payload started`, then `chaining Linux`. The next boot has no
request.

## 3. M2: the full loader and the microSD

M2 replaces the M1 loader with the full mtkloader (adapted from
`hakios-mt6768`) and adds:

- the XNU payload (`XNUP`: kernel + ramdisk + cmdline) after the Linux Image or
  on the SD;
- the microSD `xnusys` system image and `hackios-log`;
- the one-shot request stays in the ramoops pmsg area (the same
  `DARWIN-BEGONIA:BOOT-XNU` at `0xdf000` that M1 proved), because the pmsg
  survives a warm reboot and needs no SD write; the SD `hackios-request`
  partition is reserved for a later transport;
- the return-to-Linux path with XNU's log saved before the chain.

The SD layout (guarded, destructive):

```text
p1  hackios-request   1 MiB   raw  request at sector 0
p2  hackios-log      64 MiB   raw  loader/XNU log
p3  xnusys            8 GiB   raw  XNU system image
p4  hackios-data      rest    ext4 your data; Linux mounts it
```

```bash
tools/sd-layout.sh --dev /dev/mmcblk0          # dry run: prints the plan
tools/sd-layout.sh --dev /dev/mmcblk0 --yes    # DESTROYS the SD contents
```

The loader (M2) reads MSDC1 (SD); the Linux root remains UFS. The request can
also be written from Linux with `tools/request-xnu.sh` (it prefers the ramoops
module, then the SD partition).

## 4. Choosing the next boot

- **Linux** (default): do nothing. The loader chains the Linux Image.
- **XNU once**: `tools/request-xnu.sh` (M1: ramoops pmsg; M2: SD
  `hackios-request`), then reboot. The loader consumes and clears the request.
- **Back to Linux**: after XNU ends (panic, orderly end or watchdog), the
  loader writes the log and chains Linux. The next boot is Linux.

A future M4 menu (volume key, U-Boot-style) can replace the request; the
default remains Linux.

## 5. Backup and recovery

The only risky write is the **boot partition** (`/dev/sdc34`, 64 MiB). The
original is `/home/alarm/boot-work/boot-backup-7.1.img`; a fresh backup with
`dd` or `fastboot` before every flash is mandatory.

```bash
# backup
sudo dd if=/dev/sdc34 of=/home/alarm/boot-work/boot-backup-$(date +%F).img bs=1M

# restore if a chain image does not boot
fastboot flash boot /home/alarm/boot-work/boot-backup-7.1.img
# or, from a Linux that still boots:
# sudo dd if=/home/alarm/boot-work/boot-backup-7.1.img of=/dev/sdc34 bs=1M
```

`fastboot boot build/begonia-chain.img` (if supported) is the preferred test: it
does not write the partition. Do not write `/dev/sdc34` from the M2 loader; the
Linux root `/dev/sdc46` is never touched.

## 6. What is not dual boot yet

- M1 starts **only Linux**; the XNU branch is a logged dry run.
- The XNU payload and the MT6785 drivers are M2/M3; until then, the request
  changes the log, not the OS.
- The SD `xnusys` is the XNU system image, not a Linux partition; do not point
  Linux at it.
