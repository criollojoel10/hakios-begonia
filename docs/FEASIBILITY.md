# Feasibility: HakiOS on begonia (MT6785)

This document records why the port is feasible, what is already known from the
phone, and the hard parts. It is deliberately conservative: only things seen on
the hardware or read from the current system are stated as facts.

## 1. The proof that MediaTek + XNU already works

[`oosexgang/hakios-mt6768`](https://github.com/oosexgang/hakios-mt6768) is
HakiOS for the **Infinix Hot 20 (X6826B, MediaTek Helio G85 / MT6768)**:

- `mtkloader`, a bare-metal loader, is installed **in front of Android's
  kernel in `boot_a`**; on a one-shot command it starts XNU, and afterwards the
  phone returns to Android.
- The iOS 16.5 user space (launchd → backboardd → SpringBoard → apps) runs on
  XNU 8796.121.2; display, touch, buttons, Mali-G52 GPU/Metal, Wi-Fi, BLE,
  battery and sensors are listed as working or partial in its README.
- The Android/Linux kernel image is chained: `mtkloader` sits at the start of
  the boot image's kernel, and when it does not start XNU it copies Android's
  Image down and jumps to it (`tools/chainboot.py`, `mtkloader/start.S`).
- The XNU system image lives in a raw `xnusys` partition read from eMMC; the
  logger uses the **ramoops** console/pmsg zones to survive a warm reset and
  deliver the XNU log to the next Android boot.

That is exactly the architecture this repository uses, with two begonia
differences: **MT6785** instead of MT6768 and **UFS root + microSD** instead of
eMMC.

## 2. The begonia boot chain

Measured on the phone (`/proc/cmdline`, `/proc/iomem`, `/home/alarm/boot-work`):

```text
LK
 -> boot partition /dev/sdc34, 64 MiB, Android boot image, header version 2
      current image: 33 MiB (aboot-tfa2.img), kernel/ramdisk/DTB from the
      Arch Linux ARM installation
 -> Linux arm64 Image (chainboot places a program before it)
 -> Linux ARM + Phosh, root /dev/sdc46 (userdata, ext4, 52.3 GiB)
```

The current boot image is **header v2**, 33 MiB, so a loader plus the Linux
Image (and a small XNU payload) fits the 64 MiB partition. The original backup
is `/home/alarm/boot-work/boot-backup-7.1.img` (64 MiB).

The loader M1 is `loader/`; `tools/chainboot.py` (adapted from the mt6768 MIT
tool) packs it in front of the Linux Image. LK decompresses the kernel to
`0x40080000` and enters it with `x0 = LK's device tree`; the loader copies the
Linux Image from `CHAIN_OFFSET 0x40000` down to `0x40080000` and jumps, passing
a copy of the DTB at `0x4b000000`.

## 3. Logs and the one-shot request: the ramoops match

The bootloader command line already contains:

```text
ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000
ramoops.console_size=0x40000 ramoops.pmsg_size=0x10000
```

That is the **same layout** mtkloader uses on MT6768:

| address | size | use |
|---|---|---|
| `0x4d010000` | `0x8f000` | ramoops dump records |
| `0x4d09f000` | `0x40000` | console (loader/XNU log) |
| `0x4d0e0000` | `0x10000` | pmsg (one-shot request / return) |

The delivered Linux kernel has `CONFIG_PSTORE_CONSOLE` and
`CONFIG_PSTORE_PMSG` **off** (checked in `/proc/config.gz`), so
`/sys/fs/pstore` stays empty and `/dev/pmsg0` does not exist. `CONFIG_STRICT_DEVMEM=y`
blocks `/dev/mem` reads of the region (`EFAULT`). The repo therefore includes
`linux/hakios_ramoops.ko`, a small misc device mapping the reserved region:

```text
/dev/hakios-ramoops
  0x8f000..0xcefff  console  (loader/XNU log, read)
  0xd0000..0xdffff  pmsg     (request, read/write)
```

The loader writes its banner/log to the console and scans the pmsg for
`DARWIN-BEGONIA:BOOT-XNU`; it clears the request after consuming it. This gives
the dual-boot control and the log loop **without rebuilding the kernel**. M2
also writes the log to the microSD (`hackios-log`) for persistence across a
power cycle.

## 4. Storage: UFS root, microSD for XNU

The phone has two block devices:

| device | size | what |
|---|---|---|
| `/dev/sdc` | 59.6 GiB | UFS; Linux root `/dev/sdc46` (`userdata`, 52.3 GiB), boot `sdc34` 64 MiB, `misc` 4 MiB, etc. |
| `/dev/mmcblk0` | 29 GiB | **SD32G microSD**, one ext4 partition today |

The mt6768 `mtkloader` reads **eMMC over MSDC0**. Begonia's Linux root is UFS,
and a UFS stack in the loader is a large task. The pragmatic split:

- Linux stays on UFS, untouched.
- The XNU system image (`xnusys`, 8 GiB) and the persistent log
  (`hackios-log`, 64 MiB) live on the **microSD** over MSDC1 (SD), which is a
  much smaller driver than UFS.
- The one-shot request (`hackios-request`, 1 MiB) also lives on the SD in M2;
  M1 uses the ramoops pmsg.
- `tools/sd-layout.sh` (guarded, destructive) prepares the SD; the data
  partition keeps the rest.

A RAM disk (`md0`) from the SD is a fallback for the first XNU run: the loader
reads the system image into DRAM; begonia has 5.3 GiB, the mt6768 used about
2.5 GiB for iOS. The final path is the SD-backed `emmc_root`/SD root.

## 5. The SoC port (MT6785 vs MT6768)

Both are MediaTek and share the GIC/UART/timer/PMIC idioms, but the port is not
a rename:

- **CPU/GPU**: MT6785 is 2× Cortex-A76 + 6× Cortex-A55, Mali-G76 MC4;
  MT6768 is 4×A75 + 4×A55, Mali-G52. The common `mtk` branch's Mali driver is
  a starting point, not a drop-in.
- **Display/touch**: begonia is 1080×2340 with a **Novatek NT36672A** panel and
  `novatek,nt36672a-ts` touch over SPI (Linux DTS:
  `mt6785-xiaomi-begonia-common.dtsi`). The mt6768 uses an OmniVision TD4160;
  the XNU touch/display drivers need the Novatek path.
- **PMIC/charger**: MT6359 + MT6360 (the Linux tree has the drivers); the mt6768
  uses MT6358/RT9471.
- **Memory map/framebuffer**: the loader must use begonia's DRAM window and
  LK's framebuffer address/pitch, not the mt6768 constants; the first M2 gate
  is to log LK's DTB and the framebuffer and derive them.
- **Wi-Fi/BT**: both use MediaTek CONNSYS with a gen4m/MT6631-family path; the
  common `mtk` branch's `connsys` driver is the reference, the firmware comes
  from the user's own phone.

The XNU kernel is built from the common `oosexgang/hakios-xnu-kernel` **`mtk`**
branch (XNU 8796.121.2, APSL-2.0), with the MT6785 deviations in a new SoC
layer/config. The Darwin user space is the operator's own iOS 16.5 IPSW; this
repository does not ship Apple binaries, vendor firmware, or an IPSW.

## 6. What is genuinely hard / not yet proven

1. **UFS in the loader** (if the SD path is not enough) — a real UFS/UniPro
   stack; avoided in M2 with the microSD.
2. **MT6785 display/touch/GPU** — drivers to write/adapt, not just addresses.
3. **XNU kernel config for MT6785** — the common mtk branch is MT6768; the SoC
   layer and config are the main kernel work.
4. **iOS user space** — closed, user-provided; activation/Apple services are
   out of scope. The project can run the open `hello` user space first.
5. **Power/thermal/DVFS** — needed for a usable system; later.
6. **Boot partition writes** — always after a verified backup; M1 prefers
   `fastboot boot`.

## 7. Conclusion

The mt6768 port proves the full stack (XNU + iOS 16.5 user space) on a
MediaTek phone with a boot-image chainloader and a raw system partition. On
begonia the same architecture is viable, with **UFS→microSD**, **MT6768→MT6785**
and **TD4160→NT36672A** as the port. The M1 chainloader/log/request loop is the
first tested step; M2 is the full loader plus an XNU `hello` boot.
