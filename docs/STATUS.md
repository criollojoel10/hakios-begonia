# Status — 2026-11-21 (M1)

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

The loader log now lives in the **pmsg log area** (`0xd0000..0xdefff`), not the
console: the console (`0x8f000`) is the kernel's `DBGC` pstore log, and
`CONFIG_PSTORE_PMSG` is off, so the kernel does not overwrite the loader log.
The request is the last 4 KiB (`0xdf000..0xdffff`).

## Not done yet

- The chain image has **not** been flashed or `fastboot boot`ed on hardware;
  the M1 hardware gate is the next manual step.
- No XNU payload is started; the M1 request is a logged dry run.
- No MT6785 XNU drivers (display/touch/GPU/storage/Wi-Fi/BT) and no iOS user
  space (the operator supplies their own IPSW).
- The `kernel` workflow (theos + `xnu-deps/setup.sh` + common `mtk` branch) is
  present but not yet run to completion; it is the M2 reference gate.

## Next

1. From a host with USB: `fastboot boot /tmp/begonia-real-chain2.img` (no
   write), or flash after a verified `boot` backup; verify Linux still boots.
2. `tools/capture-boot-log.sh ramoops` shows the M1 banner and the request
   state; `tools/request-xnu.sh` + reboot proves the request loop.
3. Trigger the `kernel` workflow; collect the reference build logs.
4. M2: the full mtkloader adapted to MT6785, the microSD `xnusys`/`hackios-log`,
   and the XNU `hello` payload.
