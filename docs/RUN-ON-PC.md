# Running the chain from a PC with USB (hardware gate)

This is the step that cannot be done from the phone itself: `fastboot` needs a
host with USB. Nothing here writes the phone unless you choose to flash.

## Invariants

- The only risky write is the **boot partition** `/dev/sdc34` (64 MiB). The
  Linux root `/dev/sdc46` is never touched.
- `fastboot boot IMAGE` loads the image for **one boot** and writes nothing.
  On the next reset the stock boot partition is used again.
- Flashing is allowed only after a verified backup of the *current* partition,
  not of an older one.
- A hung boot with `fastboot boot` costs a power cycle, not a rescue.
- Keep `boot-current-20261121.img` and `boot-backup-7.1.img` at hand for
  `fastboot flash boot`.

## Current artifacts (built on the phone)

| File | Size | SHA-256 |
|---|---|---|
| `build/begonia-m2-linux.img` (Linux only) | 34,037,760 | `3a9569b42d68c0951faac614d0ee2e9c8b33c7abc01a67d8a6a0c7113e3c6ca3` |
| `build/begonia-m2-hello.img` (Linux + XNU hello) | 39,641,088 | `2d8ba5a13277445ebe173130456799a90d386b505920a8e7b8cc83956d0c3fea` |
| `xnu/hakios-kernel` (CI, Mach-O arm64) | 15,077,968 | `2cc22c9a581be95737cabbbf80cb9ccc3996d620d0ae33219fe9d8af778bb6fd` |
| `build/hello` (reference userland) | 16,480 | `db564073effc31e7ab1679a7ffe0631ec22c3030ad347c927028f3e53c8583c3` |
| `boot-current-20261121.img` (64 MiB) | 67,108,864 | `c3804bb264357a3a06cc6897c37808d9627eeba0d90bae1cd305f249d0e58992` |

The M2 loader boots with `cpus=1`, returns after **30 s**
(`loader_return_after=30`) and has a **45 s** watchdog. The framebuffer is
`0x7d9b0000`, 1080x2340, pitch 4320. The speaker stays with `Speaker [off]`
and `begonia-audio.service` disabled.

## 0. Before leaving the phone

```bash
# a fresh copy of what is in the partition, and its hash
sudo dd if=/dev/sdc34 of=/home/alarm/boot-work/boot-current-20261121.img bs=1M
sha256sum /home/alarm/boot-work/boot-current-20261121.img
sudo dd if=/dev/sdc34 bs=1M count=64 status=none | sha256sum   # must match
```

The existing `boot-backup-7.1.img` is an older image
(`17b3472…`), not the current partition (`c3804bb…`); use the fresh one for
this test.

Copy the images to the host (or build there):

```bash
scp build/begonia-m2-linux.img build/begonia-m2-hello.img user@host:/tmp/
```

## 1. Linux-only chain (`fastboot boot`, no write)

```bash
adb reboot bootloader            # or power+volume-down
fastboot devices
fastboot boot begonia-m2-linux.img
```

Expected: the phone boots Arch Linux as usual. The loader has run, logged to
the ramoops pmsg zone, and chained the same Linux Image. Nothing was written.

After Linux is up:

```bash
cd linux && make KDIR=/home/alarm/kw/src/linux-7.1-r0
sudo insmod hakios_ramoops.ko
../tools/capture-boot-log.sh ramoops
```

The pmsg part should show the loader banner (`boot: Linux (mtkchain)`,
`framebuffer 0x7d9b0000 pitch 4320`, `md0 ... (root.apfs only)`, `chaining
Linux at 0x40080000`). This proves M1/M2 on hardware.

## 2. XNU hello (`fastboot boot`, one-shot)

```bash
fastboot boot begonia-m2-hello.img
```

The loader starts Linux by default. To start XNU, the one-shot request must be
present in the pmsg zone. With `fastboot boot` the chain is not in the boot
partition, so the full request → XNU → return loop needs the flashed image
(step 3). For a pure loader/payload smoke test, either:

- build a variant with `-DMENU_DEFAULT_XNU=1` (XNU once, no request), or
- flash the chain (step 3) and use `tools/request-xnu.sh`.

With XNU running, the expected evidence is in the ramoops log after the return
(30 s): the XNU version banner, the kernel's page counts, and
`Hello from user space on Darwin!` from the `hello` RAM disk.

## 3. Full dual-boot loop (flash after backup)

```bash
# backup already verified; write the chain
fastboot flash boot begonia-m2-hello.img
fastboot reboot
```

Linux boots by default. Then:

```bash
sudo insmod linux/hakios_ramoops.ko
tools/request-xnu.sh --no-reboot       # writes DARWIN-BEGONIA:BOOT-XNU
sudo reboot
```

On the warm reboot the loader finds the request, clears it, runs XNU for 30 s,
saves its log into the pmsg zone, and warm-resets. The next boot has no request
and Linux comes back. Capture the log with

```bash
sudo insmod linux/hakios_ramoops.ko
tools/capture-boot-log.sh ramoops
```

The log must show `boot: Darwin / XNU (requested)`, the XNU kernel size, the
payload entries, the boot-args, and then the kernel's own lines. The request
area is overwritten with `-`, so the following boot is Linux again.

## 4. Rollback

```bash
# the verified current partition
fastboot flash boot boot-current-20261121.img
# or the older known-good image
fastboot flash boot boot-backup-7.1.img
```

If fastboot is unreachable, the boot ROM's download mode with `mtkclient`
(`mtk.py w boot <image>`) is the rescue; test that path **before** the first
flash. Do not write slot B or any partition other than `boot`.

## Notes

- The 2.3 GiB XNU window still contains the modem/TEE reserved holes
  (`0xf9e00000..0xffefffff`). It is enough for the `hello` kernel; before
  loading the iOS system image, move to the clear window (see
  [M3-MT6785.md](M3-MT6785.md)).
- Touch is disabled in this loader (the NT36672A is not the TD4160 the common
  TCM path expects). The serial/console is `serial=3` in the boot args, but the
  log's reliable path is ramoops.
- Do not put serial numbers, MACs, keys or the operator's IPSW in the
  repository.
