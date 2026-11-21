# Begonia hardware facts (measured)

Only what was read from this phone is listed; "TBD" means the M2 loader must
discover/verify it from LK's device tree or the phone's firmware.

| Item | Value |
|---|---|
| Phone | Xiaomi Redmi Note 8 Pro (`begonia`) |
| SoC | MediaTek **MT6785** / MT6785V "Helio G90T" |
| CPU | 8 cores: 2× Cortex-A76 + 6× Cortex-A55 |
| GPU | Mali-G76 MC4 |
| RAM | 5.3 GiB usable (`free -h`); 8 cores |
| Root storage | **UFS** `/dev/sdc` 59.6 GiB; Linux root `/dev/sdc46` (`userdata`, ext4, 52.3 GiB) |
| Boot partition | `/dev/sdc34`, 64 MiB, Android boot image header **v2** |
| Current boot image | `/home/alarm/boot-work/aboot-tfa2.img`, **33 MiB** (kernel 17 MiB, ramdisk 17 MiB, DTB 62 KiB) |
| Boot backup | `/home/alarm/boot-work/boot-backup-7.1.img`, 64 MiB |
| microSD | `/dev/mmcblk0`, model **SD32G**, 29 GiB, one ext4 partition today |
| Display | 1080×2340; Novatek **NT36672A** panel (`panel@0` in the Linux DTS) |
| Touch | Novatek **NT36672A** (`novatek,nt36672a-ts`) over SPI |
| PMIC/charger | MT6359 + MT6360 (charger, fuel gauge/ADC, regulators) |
| Audio | TFA9874 smart PA + MT6359; the Linux audio stack is currently disabled |
| Kernel | Linux 7.1.0 (custom), modules in `/usr/lib/modules/7.1.0` |
| Ramoops | `0x4d010000`, size `0xe0000`, console `0x4d09f000` (0x40000), pmsg `0x4d0e0000` (0x10000) |
| Linux cmdline | `ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000 ramoops.console_size=0x40000 ramoops.pmsg_size=0x10000` |

## Partitions (excerpt, `lsblk`)

```text
sdc        59.6G
├─sdc1       64M
├─sdc2        4M        misc
├─sdc3      512K        para
├─sdc4       20M        expdb
...
├─sdc9       32M        metadata
├─sdc32       2M        lk
├─sdc33       2M        lk2
├─sdc34      64M        boot          <- chainloader target
├─sdc35      64M        logo
├─sdc36      32M        dtbo
...
├─sdc39     1.5G ext4   vendor
├─sdc40     3.5G        system
├─sdc41     432M ext4   cache
├─sdc45     832M ext4   cust
├─sdc46    52.3G ext4   userdata      <- Linux root
└─sdc47      16M        flashinfo
mmcblk0     29G        SD32G          <- microSD (M2: request/log/xnusys/data)
└─mmcblk0p1 29G ext4
```

## Memory (`/proc/iomem`, excerpt)

```text
40000000-4cdfffff : System RAM
4ce00000-4d0fffff : reserved        <- ramoops 0x4d010000..0x4d0effff
4d100000-6fffffff : System RAM
70000000-751fffff : reserved
75200000-77feffff : System RAM
77ff0000-77ffffff : reserved
78000000-7d9affff : System RAM
7d9b0000-7fdfffff : reserved
7fe00000-7febffff : System RAM
7fec0000-7ffbffff : reserved
7ffc0000-aaffffff : System RAM
8c000000-8d77ffff : reserved
8e000000-8f76ffff : reserved
ab000000-ab3fffff : reserved
ab400000-bbffffff : System RAM
```

The XNU window (`XNU_PHYS_BASE`/`XNU_MEM_SIZE`) and LK's framebuffer
address/pitch are **TBD**: the M2 loader must log LK's device tree and the
framebuffer, then choose a free contiguous range. The mt6768 uses
`0xc0000000`/`0xfe000000`; do not assume it for begonia.

## Boot image

Current `aboot-tfa2.img` header (Python unpack):

```text
magic ANDROID!
kernel_size 17069246, kernel_addr 0x40080000
ramdisk_size 16874710, ramdisk_addr 0x47c80000
second_size 0
tags_addr 0x40000100
page_size 2048
header_version 2
```

`tools/chainboot.py` reads this header v2, decompresses the Linux Image, packs
`mtkchain-begonia` at `CHAIN_OFFSET 0x40000` in front of it, and copies the
ramdisk/DTB from the original. The output must stay ≤ 64 MiB.

## Linux device-tree references

- `arch/arm64/boot/dts/mediatek/mt6785-xiaomi-begonia-common.dtsi`
  (panel, touch `novatek,nt36672a-ts`, MT6360, UFS `&ufshci`, regulators).
- `arch/arm64/boot/dts/mediatek/mt6785-xiaomi-begonia-audio.dtsi`
  (AFE/sound/I2S3/TFA9874).
- `arch/arm64/boot/dts/mediatek/mt6785-xiaomi-begonia*.dts*` (board).
- The vendor tree `/home/alarm/kw/begonia-dts/mt6785-vendor.dts` (full vendor
  nodes, for the M2 memory/framebuffer/PMIC addresses).

## What is not known yet

- The exact LK framebuffer address/pitch for begonia (M2 logs it).
- The free DRAM window for XNU (M2 logs LK's tree).
- The MT6785 UFS/SD controller registers for the loader (M2 starts with MSDC1
  SD; UFS is a later driver).
- The Novatek NT36672A firmware/initialization for XNU (M3).
- The MT6785 Mali-G76 and CONNSYS details (M3, from the common mt6768 paths).
