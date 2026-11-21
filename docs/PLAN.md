# Plan and gates

The objective: **HakiOS XNU on begonia (MT6785), dual booting with the existing
Arch Linux ARM + Phosh**, with logs captured from Linux. The work is staged so
each gate is testable and reversible.

| Gate | What | State |
|---|---|---|
| **M0** | repository, device/SoC contract, CI, docs | done: `ci.yml` builds the loader and a synthetic chain image |
| **M1** | chainloader in front of Linux + ramoops log/request | **in progress**: loader and chain image build; hardware test pending |
| **M2** | full MediaTek loader, microSD (`xnusys`/`hackios-log`), XNU `hello` payload | planned |
| **M3** | MT6785 drivers: display, touch, buttons, storage, Wi-Fi/BT, GPU; iOS 16.5 user space (user IPSW) | planned |
| **M4** | dual-boot menu/automation, persistent logs, release docs | planned |

## M0 — contracts and CI

- `device.conf` (`device begonia`), `soc/mt6785/soc.conf`,
  `configs/begonia_defconfig` (`common_defconfig`, `mt6785.config`,
  `begonia.config`).
- `tools/check-device.py` validates the contract.
- `.github/workflows/ci.yml`: shell/Python parse, device contract, loader
  build, synthetic Android boot image, `chainboot.py`, output verification.
- **Evidence**: a green `ci` run; `loader/chain.bin`; a chain image whose
  `res2` equals the Linux Image length and whose size is under 64 MiB.

## M1 — dual-boot control and logs, no XNU yet

**Goal**: prove that the existing Linux boot still works with a loader in
front of it, and that the loader can read a one-shot request and leave a log
that Linux can read.

Gates:

1. `tools/build-chain-image.sh /home/alarm/boot-work/aboot-tfa2.img` produces
   `build/begonia-chain.img`; `tools/check-chain-image.py` passes.
2. `fastboot boot build/begonia-chain.img` (preferred, no write) or, after a
   verified `boot` backup, `fastboot flash boot ...`; the phone still boots
   Linux. **Evidence**: Linux `uname -r` after the loader.
3. `linux/hakios_ramoops.ko` loads; `tools/capture-boot-log.sh ramoops` shows
   the M1 banner (`mtkchain-begonia M1`, `request: Linux`, the Linux Image
   length, the DTB copy, `chaining Linux`).
4. `tools/request-xnu.sh --no-reboot` + reboot: the loader logs
   `request: XNU` and `XNU requested; M1 dry-run`; Linux boots again; the log
   shows the request was consumed (pmsg cleared). **This is the full dual-boot
   control loop, without XNU yet.**
5. Rollback: the original `boot-backup-7.1.img` is restored with
   `fastboot flash boot boot-backup-7.1.img` (or `dd` if fastboot is not
   available). The Linux root is never touched.

**Current state**: steps 1–2 build/verify locally and in CI; the hardware run
(2–4) is the next manual step. The loader has not been flashed.

## M2 — the MediaTek loader, the SD and XNU `hello`

**Goal**: start the XNU kernel on begonia with the project's `hello` user
space, not yet iOS.

Work:

- Adapt `oosexgang/hakios-mt6768`'s `mtkloader` (MIT) to MT6785:
  - memory window/DT (`dram-base`, `dram-size`, GIC, UART);
  - LK framebuffer address/pitch/panel for begonia (1080x2340);
  - MSDC1 (microSD) instead of the mt6768 eMMC/MSDC0 for the XNU system image
    and `hackios-log`;
  - the XNU payload (`XNUP`) and the return-to-Linux path.
- Build the XNU kernel from the common `mtk` branch (XNU 8796.121.2, APSL) in
  `.github/workflows/kernel.yml`; the first target is the common `hello`
  user space, not iOS.
- Build the XNU payload (`xnuloader/mkpayload.py`), pack it after the Linux
  Image in `begonia-chain.img` or put it on the SD; the loader starts it when
  the request is set.
- **Evidence**: XNU's first lines/`kernel.ver` in the log; `Hello from user
  space on Darwin!`; the return to Linux; the log on `hackios-log`/ramoops.

## M3 — MT6785 drivers and the Darwin user space

Order (each depends on the previous): CPUFREQ/THERMAL/SOCINFO, buttons,
display/touch, storage (SD/UFS), GPU (Mali-G76), Wi-Fi/BT (CONNSYS),
audio/battery, camera.

- Panel/touch: Novatek **NT36672A** (`novatek,nt36672a-ts` in the Linux DTS);
  the mt6768's OmniVision TD4160 is not this phone.
- GPU: Mali-G76 MC4; the common mt6768 Mali driver and the kernel's GPU/IOKit
  path are the starting point.
- Storage: the XNU system image on the SD `xnusys`; if UFS is needed, a UFS
  driver is a later, larger task.
- User space: the operator's own iOS 16.5 IPSW (`ios165/fetch.sh` in the
  common tree); no Apple binary is distributed here; activation/Apple services
  are out of scope.
- **Evidence**: each `status` line in `device.conf` moves from `not started` to
  `works` only after it is seen on the phone.

## M4 — productise the dual boot

- A menu (or a key/volume gesture) to choose Linux/XNU; the default stays
  Linux.
- `hackios-log` rotation and retrieval from Linux; the request clears itself.
- `fastboot`/recovery runbook; a tested `boot-backup`; a release note.
- Optional: a second boot slot/partition for the XNU payload instead of the SD.

## Risks and invariants

- **Never write `/dev/sdc34` without a verified backup.** The original image is
  `/home/alarm/boot-work/boot-backup-7.1.img`; `fastboot flash boot` restores
  it. The Linux root `/dev/sdc46` is untouched by M1/M2.
- **UFS vs SD**: the Linux root is UFS; do not attempt a UFS write from the
  M2 loader until the driver exists. The SD is the XNU/log storage.
- **Warm reset**: ramoops survives a reboot; a power cycle may lose it. The SD
  is the persistent log store.
- **Legal**: no Apple user space/IPSW/vendor firmware in git; XNU patches under
  APSL-2.0; the loader/tools MIT.
