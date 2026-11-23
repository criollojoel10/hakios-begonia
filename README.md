# hakios-begonia

HakiOS (Apple's open-source **XNU**/Darwin kernel) on the **Xiaomi Redmi Note 8
Pro** (`begonia`, MediaTek **MT6785** / Helio G90T), **dual booting with the
existing Arch Linux ARM + Phosh installation**.

[![ci](https://github.com/criollojoel10/hakios-begonia/actions/workflows/ci.yml/badge.svg)](https://github.com/criollojoel10/hakios-begonia/actions/workflows/ci.yml)

> **Status: M2 images built; hardware gate pending.** The M1 `mtkchain` loop
> and the M2 `mtkloader` port for MT6785 are built and verified in software; the
> CI builds the reference XNU kernel (8796.121.2) and a Linux + XNU `hello`
> chain image (39.6 MiB, under the 64 MiB boot partition). **Nothing has run on
> the phone yet:** `fastboot boot` needs a PC with USB. Evidence:
> [docs/STATUS.md](docs/STATUS.md); hardware runbook:
> [docs/RUN-ON-PC.md](docs/RUN-ON-PC.md); gates: [docs/PLAN.md](docs/PLAN.md).

This is a research project, not a ROM. It does not distribute Apple's user
space, an IPSW, vendor firmware, or any phone image. The Darwin user space, if
you want it, you lay out yourself from an IPSW you obtained yourself. Apple's
services (activation, Apple ID, iCloud, App Store) are not supported and are
not a goal. Not affiliated with or endorsed by Apple.

## Why this can work

The upstream **HakiOS** project already runs XNU + an unmodified **iOS 16.5**
user space on a **MediaTek** phone: [`oosexgang/hakios-mt6768`](https://github.com/oosexgang/hakios-mt6768)
(Infinix Hot 20, Helio G85, eMMC) with its own bare-metal `mtkloader`. It boots
XNU once from `boot_a`, then returns to Android, and reads the XNU system image
from a raw `xnusys` partition. The same mechanism is the basis here:

- put a **chain loader** in front of the Linux kernel in the existing `boot`
  partition;
- boot **Linux** by default (the current installation remains the daily OS);
- read a one-shot **request** for XNU, start the XNU payload, and return to
  Linux with the log;
- store the XNU system image and the persistent log on the **32 GiB microSD**
  (`SD32G`, `mmcblk0`), not in the Linux root.

The begonia boot chain (verified on this phone):

```text
LK (bootloader)
  -> boot.img (64 MiB, Android header v2, currently 33 MiB)
       kernel = gzip( mtkchain-begonia | Linux arm64 Image )
       ramdisk + DTB from the Linux installation
  -> mtkloader-begonia (M2; M1 is the smaller mtkchain)
       default: copy the Linux Image down to 0x40080000, start it
       requested: copy the XNU Mach-O, build the tree/boot_args, run it,
                  save its log into ramoops, warm-reset back to Linux
  -> Linux ARM + Phosh (root on UFS, /dev/sdc46)
```

The bootloader already reserves **ramoops** at `0x4d010000` with the exact
layout mtkloader uses (`console 0x4d09f000`, `pmsg 0x4d0e0000`). The Linux
kernel has `CONFIG_PSTORE_CONSOLE/PMSG` off, so this repo provides
`linux/hakios_ramoops.ko` to expose the reserved region and the two helper
scripts. M2 writes the same log to the microSD for persistence.

## What is in this repository

| Path | What |
|---|---|
| `loader/` | `mtkchain-begonia` M1: arm64 header, ramoops log/request, chainstub |
| `tools/chainboot.py` | pack the loader + Linux Image (and optional XNU payload) into a boot image v2 |
| `tools/build-chain-image.sh` | build `build/begonia-chain.img` from the current Linux boot image |
| `tools/request-xnu.sh` | write the one-shot request (ramoops pmsg or microSD) and reboot |
| `tools/capture-boot-log.sh` | read the last loader/XNU log (ramoops or microSD) |
| `tools/fetch-xnu.sh` | download the CI `hakios-kernel` and the pinned reference `hello` |
| `tools/build-m2.sh` | loader + Linux-only chain + XNU hello chain, one command |
| `tools/m2-chain.sh` | pack the boot image + loader + optional `XNUP` payload |
| `tools/check-sd-gpt.py` | verify the microSD GPT offline or on a loop device |
| `tools/sd-layout.sh` | guarded microSD layout: request, log, xnusys, data |
| `linux/hakios_ramoops.c` | expose the reserved ramoops region when pstore console/pmsg are off |
| `configs/`, `soc/`, `device.conf` | the HakiOS device/SoC contract for MT6785 |
| `config/begonia/` | Linux daily-use tuning: performance, backlight max, charge limits |
| `docs/BEGONIA-POWER.md` | measured values, install, risks and rollback for that tuning |
| `docs/` | plan, feasibility, dual boot, logs, hardware, references, status |
| `.github/workflows/ci.yml` | builds the loader + a synthetic chain image on every push |
| `.github/workflows/kernel.yml` | manual XNU kernel build (the heavy gate) |

## M1: build and verify (no phone write)

```bash
git clone https://github.com/criollojoel10/hakios-begonia.git
cd hakios-begonia

# 1. loader + chain image from the current Linux boot image
tools/build-chain-image.sh /home/alarm/boot-work/aboot-tfa2.img
# -> build/begonia-chain.img, verified by tools/check-chain-image.py

# 2. try it without flashing (if the bootloader supports fastboot boot)
fastboot boot build/begonia-chain.img
# if it does not: back up boot first, then flash it
#   sudo dd if=/dev/sdc34 of=boot-backup.img bs=1M
#   fastboot flash boot build/begonia-chain.img
```

The loader logs to the ramoops pmsg area, then boots Linux. To read the log
and exercise the request path on Linux:

```bash
cd linux && make KDIR=/home/alarm/kw/src/linux-7.1-r0
sudo insmod hakios_ramoops.ko
../tools/capture-boot-log.sh ramoops      # the M1 banner + request state
../tools/request-xnu.sh --no-reboot       # writes the one-shot request
sudo reboot                               # loader sees it, logs "XNU requested", boots Linux
../tools/capture-boot-log.sh ramoops      # the request was consumed
```

M1 does **not** start XNU: it is the dual-boot/control/log loop, tested before
touching the XNU payload. M2 adds the full mtkloader (adapted from
`hakios-mt6768`) and the MT6785 platform layer.

## M2: microSD, the XNU payload and the hardware gate

Build both M2 images (fetching the CI kernel and the reference `hello` if they
are not there):

```bash
tools/build-m2.sh /home/alarm/boot-work/aboot-tfa2.img
#  build/begonia-m2-linux.img    Linux only, 34 MB
#  build/begonia-m2-hello.img    Linux + XNU hello, 39.6 MB
```

The loader boots Linux unless the one-shot request `DARWIN-BEGONIA:BOOT-XNU`
is in the ramoops pmsg tail; it runs XNU with `cpus=1`, returns after 30 s and
has a 45 s watchdog. The framebuffer is the real `0x7d9b0000` / 1080x2340 /
4320, and the OVL/RDMA block is probed, not guessed (`docs/M3-MT6785.md`).

To run it, follow **[docs/RUN-ON-PC.md](docs/RUN-ON-PC.md)**: `fastboot boot`
writes nothing, the flashed dual-boot loop needs the verified backup, and
`boot-current-20261121.img` is the current partition.

`tools/sd-layout.sh` (guarded, destructive) prepares the 32 GiB SD:

```text
p1  hackios-request   1 MiB   raw  (one-shot request)
p2  hackios-log      64 MiB   raw  (loader/XNU log, persistent)
p3  xnusys            8 GiB   raw  (XNU system image)
p4  hackios-data      rest    ext4 (your data; mounted by Linux)
```

The XNU kernel comes from the common [`oosexgang/hakios-xnu-kernel`](https://github.com/oosexgang/hakios-xnu-kernel)
branch `mtk` (XNU 8796.121.2 / iOS 16.5, APSL-2.0). The MT6785 platform layer
and the `mtkloader` adaptation are the port: see
[docs/PLAN.md](docs/PLAN.md) and [docs/FEASIBILITY.md](docs/FEASIBILITY.md).

## Why the microSD

- The Linux root is on **UFS** (`/dev/sdc`, 59.6 GiB), while the mt6768
  `mtkloader` has an **eMMC** reader (MSDC0). The XNU system image and logs go
  to the **SD** (`mmcblk0`, 29 GiB, MSDC1), which is easier to add to the
  loader than a UFS stack and keeps the Linux root untouched.
- A raw `hackios-log` partition is readable by both the loader and Linux; the
  ramoops console (256 KiB) is the M1 fallback, not the final log store.
- The boot partition is 64 MiB; the current Linux image is 33 MiB. The XNU
  payload (kernel + small userland) fits; the 2.5 GiB Darwin system image goes
  on the SD `xnusys`.

## Legal

The code written here is MIT (see `LICENSE`); `loader/start.S` and
`tools/chainboot.py` are derived from the MIT-licensed
[`hakios-mt6768`](https://github.com/oosexgang/hakios-mt6768), with attribution
in `NOTICE`. XNU and XNU-derived patches are APSL-2.0. **No Apple user space,
IPSW, vendor firmware, or phone image is in this repository.** Nothing here
circumvents activation or Apple's services.

## References

- [docs/REFERENCES.md](docs/REFERENCES.md): the upstream HakiOS repositories,
  the MediaTek loader, the Qualcomm/laurel reference, U-Boot/porting docs.
- [docs/HARDWARE.md](docs/HARDWARE.md): the measured begonia facts.
