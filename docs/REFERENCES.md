# References

## HakiOS upstream

- [`oosexgang/hakios-xnu-kernel`](https://github.com/oosexgang/hakios-xnu-kernel)
  — the common tree: XNU 8796.121.2 (iOS 16.5), the loader, drivers, user space,
  tools, docs. Branch **`mtk`** is the MediaTek port and the reference for this
  repo.
- [`oosexgang/hakios-mt6768`](https://github.com/oosexgang/hakios-mt6768) — the
  Infinix Hot 20 (MT6768) port: `mtkloader`, the chainboot tools, the eMMC
  `xnusys` and the XNU drivers this port adapts. The source of the `start.S`
  chainstub and `tools/chainboot.py` mechanism (MIT).
- [`oosexgang/hakios-uefi`](https://github.com/oosexgang/hakios-uefi) — HakiOS's
  UEFI/U-Boot path (Qualcomm and QEMU); documented in the common tree's
  `docs/u-boot.md` and `docs/uefi-boot.md`.
- [`oosexgang/hackios-xnu-userland`](https://github.com/oosexgang/hackios-xnu-userland)
  — old pointer; the user space lives in the common tree's `userland/`.
- [`oosexgang/hackios-web`](https://github.com/oosexgang/hackios-web) — the
  project site.

## Device/SoC examples

- [`criollojoel10/hakios-sm6125`](https://github.com/criollojoel10/hakios-sm6125)
  — the Xiaomi Mi A3 (laurel_sprout, SM6125) device/SoC layer, UEFI platform and
  CI. The Qualcomm/UEFI reference; this begonia port uses the MediaTek path.
- `hakios-mt6768/configs/x6826b_defconfig` and `x6826b.config` — the MT6768
  device/SoC config shape this repo mirrors.
- `hakios-mt6768/mtkloader/`, `tools/chainboot.py`, `tools/xnu-cycle.sh`,
  `tools/boot-xnu.sh`, `tools/gpt-carve.py`, `tools/system-flash.sh` — the
  loader/dual-boot/log tools adapted here.

## Common documentation read for this port

- `docs/u-boot.md` (HakiOS U-Boot, the boot image, the payload, the `hakios`
  command, dual boot/menu).
- `docs/uefi-boot.md` (UEFI volume/loader; QEMU).
- `docs/porting/index.md` and `docs/porting/repositories.md` (device/SoC
  contract, `device.conf`, `soc.conf`, `configs/`, drivers, publishing).
- `docs/mtk-porting.md` and `docs/x6826b-emmc.md` (the MediaTek loader/eMMC
  path).
- `docs/install.md`, `docs/install-safe.md`, `docs/dual-boot.md` (installed vs
  RAM runs, slots, backups).

## Linux side

- `arch/arm64/boot/dts/mediatek/mt6785-xiaomi-begonia-common.dtsi` (panel,
  `novatek,nt36672a-ts`, MT6360, `&ufshci`).
- `arch/arm64/boot/dts/mediatek/mt6785-xiaomi-begonia-audio.dtsi`
  (AFE/I2S3/TFA9874).
- `/home/alarm/kw/begonia-dts/mt6785-vendor.dts` (vendor tree, full nodes).
- The bootloader command line's ramoops parameters (measured):
  `ramoops.mem_address=0x4d010000 mem_size=0xe0000 console_size=0x40000
  pmsg_size=0x10000`.

## Apple/XNU and legal

- XNU 8796.121.2 (iOS 16.5) source, Apple Public Source License 2.0
  (`LICENSE.APSL` in the common tree). The XNU patches/derived files keep APSL.
- No Apple user space, IPSW, vendor firmware or phone image is distributed
  here. The operator provides their own IPSW/user space; activation, Apple ID,
  iCloud and the App Store are out of scope.
- The code written in this repository is MIT (`LICENSE`); the loader's
  `start.S`/`chainboot.py` mechanism is derived from the MIT
  `hakios-mt6768`, attributed in `NOTICE`.
