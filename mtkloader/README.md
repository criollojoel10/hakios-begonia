# mtkloader (begonia / MT6785)

Bare-metal AArch64 loader that runs in place of the Linux kernel. It brings up
the MediaTek platform, keeps the Linux image intact, logs to the ramoops pmsg
area, and either returns to Linux or starts the XNU payload.

The code comes from the `mtk` branch of
[`oosexgang/hakios-xnu-kernel`](https://github.com/oosexgang/hakios-xnu-kernel)
and the MT6768 reference
[`oosexgang/hakios-mt6768`](https://github.com/oosexgang/hakios-mt6768). The
begonia changes in this repository:

| Constant | MT6768 reference | begonia (MT6785) |
|---|---|---|
| Framebuffer | `0x787b0000`, pitch 2944 | `0x9b7d0000`, pitch 4320 (`mblock-15-framebuffer`) |
| Panel | 720x1640 | 1080x2340 |
| XNU window | `0xc0000000` + `0xfe000000` | `0xc0000000` + `0x94000000` (5.3 GiB usable) |
| System image | eMMC (`xnusys`) | microSD **MSDC1** (`xnusys`), `XNU_ROOT_EMMC=0` |
| Touch | TD4160 TCM firmware | disabled (Novatek NT36672A; firmware is vendor data) |

Build: `./build-begonia.sh` produces `mtkloader-begonia.bin`.
