# Status — 2026-11-21 (M1 hardware gate, M2 build)

**Repository:** <https://github.com/criollojoel10/hakios-begonia> (public)

**CI:** [run 44923189846](https://github.com/criollojoel10/hakios-begonia/actions/runs/44923189846)
— **success**. It builds `mtkchain-begonia`, validates the device/SoC
contract, and packs a synthetic Android boot image with `chainboot.py`; the
`ci` badge on the README shows the latest run.

## Verified on the phone (M1)

| Check | Evidence |
|---|---|
| Loader builds | `loader/chain.bin` 1,848 B (`clang --target=aarch64-linux-gnu` + `ld.lld`) |
| Synthetic chain | 8,192 B; Linux Image 1,088; `res2=1088`; payload 0; `check-chain-image.py` OK |
| Real chain | `/tmp/begonia-real-chain2.img` **34,013,184 B**; Linux Image **43,682,304 B**; `res2=43682304`; payload 0; check OK; boot partition is 64 MiB |
| Boot image source | `/home/alarm/boot-work/aboot-tfa2.img`, header **v2**, 33 MiB, kernel/ramdisk/DTB |
| ramoops module | `linux/hakios_ramoops.ko` 280,424 B; `insmod` OK; `/dev/hakios-ramoops`; `dmesg`: `0x4d010000..0x4d0effff` |
| ramoops console | reads the kernel's `DBGC` zone ("Booting Linux on phys…"), proving the mapping |
| Request | `tools/request-xnu.sh --no-reboot` writes `DARWIN-BEGONIA:BOOT-XNU` at pmsg `0xdf000`; `dd` reads it back; cleared |
| microSD | `/dev/mmcblk0`, 29 G, model **SD32G**; `tools/sd-layout.sh` dry run: request 1 MiB, log 64 MiB, xnusys 8 GiB, data rest; **not applied** |
| microSD GPT (offline) | `tools/sd-layout.sh --image ...` + `tools/check-sd-gpt.py`: 4 partitions, contiguous LBAs, names/sizes verified; device mode validated on a loop device; CI step added |

The loader log now lives in the **pmsg log area** (`0xd0000..0xdefff`), not the
console: the console (`0x8f000`) is the kernel's `DBGC` pstore log, and
`CONFIG_PSTORE_PMSG` is off, so the kernel does not overwrite the loader log.
The request is the last 4 KiB (`0xdf000..0xdffff`).

## M2 build (in progress)

| Check | Evidence |
|---|---|
| mtkloader port | `mtkloader/mtkloader-begonia.bin` **44,984 B**, from the common `mtk` sources with `-DBEGONIA -DXNU_ROOT_EMMC=0` |
| Framebuffer | real begonia `mblock-15-framebuffer`: `0x7d9b0000`, 1080x2340, pitch 4320 (from the Linux DT/fb0) |
| XNU window | `0xc0000000` + `0x94000000` (5.3 GiB usable bound), boot_args `dram-base`/`dram-size` |
| Storage | system image `xnusys` read through **MSDC1** (microSD), GPT lookup; touch/TCM disabled (Novatek NT36672A, vendor firmware not in git) |
| Request | mtkloader reads/clears `DARWIN-BEGONIA:BOOT-XNU` from the raw pmsg tail (`0xdf000`), the same path M1 proved; the ramoops-header path is kept |
| Linux chain | `/tmp/begonia-m2-nopayload.img` **34,035,712 B**; Image 43,682,304; check OK |
| XNU reference | `kernel` runs **44924952512** and **44926233119 success**: theos + `xnu-deps` stage 1/2 + XNU 8796.121.2; artifact `hakios-kernel` is the linked Mach-O (15,077,968 B) |
| Payload tooling | `xnuloader/mkpayload.py` + `tools/m2-chain.sh` (Linux boot image + loader + optional `XNUP` kernel/ramdisk; 64 MiB guard) |
| M2 chain | `/tmp/begonia-m2-hello.img` **39,639,040 B**: Linux Image 43,682,304; XNUP payload 15,094,560 (kernel 15,077,968 + hello 16,480 + cmdline); res3 43,944,448; check OK |
| CI artifact | the first upload grabbed a symbols YAML; the fixed workflow selects the linked Mach-O and uploads only `hakios-kernel` (verified on run 44926233119) |

## Not done yet

- The chain image has **not** been flashed or `fastboot boot`ed on hardware;
  the M1 hardware gate is the next manual step.
- No XNU payload has run on the phone; the M2 payload is built and packed but
  the hardware boot is blocked on a host with USB.
- No MT6785 XNU drivers (display/touch/GPU/storage/Wi-Fi/BT) and no iOS user
  space (the operator supplies their own IPSW).
- The reference kernel is the common `mtk` build (MT6768 drivers, arm64
  `BCM2837` machine config); the MT6785 device layer is the M3 port.

## Next

1. From a host with USB: `fastboot boot /tmp/begonia-real-chain2.img` (no
   write), or flash after a verified `boot` backup; verify Linux still boots.
2. `tools/capture-boot-log.sh ramoops` shows the M1 banner and the request
   state; `tools/request-xnu.sh` + reboot proves the request loop.
3. Build the `hello` payload from the CI kernel and pack
   `tools/m2-chain.sh ... hello`; keep the result under 64 MiB.
4. From a host with USB, `fastboot boot` the M2 chain (`/tmp/begonia-m2-chain.img`)
   and verify: Linux default, request -> XNU hello -> return to Linux.
5. M3: the MT6785 device layer; move each `device.conf` status to `works` only
   after seeing it on the phone.
