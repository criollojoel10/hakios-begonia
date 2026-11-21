# linux/hakios_ramoops

The 7.1.0 begonia kernel has `CONFIG_PSTORE_CONSOLE` and
`CONFIG_PSTORE_PMSG` **off**, so `/sys/fs/pstore` stays empty and
`/dev/pmsg0` does not exist. The bootloader command line still reserves the
ramoops region:

```text
ramoops.mem_address=0x4d010000 mem_size=0xe0000
console_size=0x40000 pmsg_size=0x10000
```

`mtkchain-begonia` writes its log to `0x4d09f000` (console) and reads the
one-shot XNU request from `0x4d0e0000` (pmsg). This module maps the whole
reserved region as `/dev/hakios-ramoops` (root, 0600):

| offset | size | use |
|---|---|---|
| `0x00000` | `0x8f000` | ramoops dump records (unused here) |
| `0x8f000` | `0x40000` | loader/XNU console log |
| `0xd0000` | `0x10000` | request/return pmsg |

The region is reserved RAM; the kernel allocator does not use it, and a warm
reset keeps it for the next loader session. A full power cycle may lose it.
M2 writes the same log to the microSD (`hackios-log`) for persistence.

## Build and load

```bash
cd linux
make KDIR=/home/alarm/kw/src/linux-7.1-r0
sudo insmod hakios_ramoops.ko
ls -l /dev/hakios-ramoops
```

`dmesg | tail` should show `hakios-ramoops: 0x4d010000..0x4d0effff`.

## Use

```bash
# read the last loader/XNU log
../tools/capture-boot-log.sh ramoops

# request one XNU boot (M1 dry-run: the loader logs it and boots Linux)
../tools/request-xnu.sh --no-reboot
sudo reboot
```

Do not load the kernel's `ramoops` module at the same time: both would map the
same reserved region. The module is a development aid, not part of the final
design; M2 uses the microSD raw log partition.
