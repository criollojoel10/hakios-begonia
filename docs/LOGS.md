# Logs: ramoops (M1) and microSD (M2)

The loader and XNU run before Linux; their log has to be left where the next
Linux can read it. Two transports:

1. **ramoops**, the reserved RAM region the bootloader already sets up. Fast,
   no storage driver, survives a warm reboot, limited to the console size
   (256 KiB) and lost on a power cycle.
2. **microSD `hackios-log`** (M2): 64 MiB raw partition, written by the full
   loader/XNU, readable by Linux with `dd`; persistent across power cycles and
   large enough for a real XNU session. This is the store the operator asked
   for and the one M2 uses.

## 1. The ramoops layout

The bootloader command line (measured):

```text
ramoops.mem_address=0x4d010000 ramoops.mem_size=0xe0000
ramoops.console_size=0x40000 ramoops.pmsg_size=0x10000
```

| offset from `0x4d010000` | size | use |
|---|---|---|
| `0x00000` | `0x8f000` | ramoops dump records |
| `0x8f000` | `0x40000` | kernel pstore console (`DBGC`; already in use) |
| `0xd0000` | `0xf000` | mtkchain log (`DBGC` ring) |
| `0xdf000` | `0x1000` | one-shot request |

The delivered Linux kernel has `CONFIG_PSTORE_CONSOLE` and
`CONFIG_PSTORE_PMSG` **off**, so `/sys/fs/pstore` is empty and `/dev/pmsg0`
does not exist. `CONFIG_STRICT_DEVMEM=y` blocks `/dev/mem` access to the
region. The repo's `linux/hakios_ramoops.ko` maps the reserved region:

```text
/dev/hakios-ramoops
  console at 0x8f000, 0x40000 bytes
  pmsg    at 0xd0000, 0x10000 bytes
```

The loader writes a small ring with a `DBGC` header (`sig`, `start`, `size`)
at the **pmsg log area**. The console (`0x8f000`) is the kernel's pstore
console and already contains a `DBGC` + "Booting Linux" log; the loader must
not overwrite it. `CONFIG_PSTORE_PMSG` is off, so the kernel does not touch the
pmsg and the loader log survives the Linux boot. `tools/capture-boot-log.sh`
reads the pmsg log and the request area. The request is the ASCII string
`DARWIN-BEGONIA:BOOT-XNU` at `0xdf000`; the loader scans, logs and clears it.

## 2. M1 capture

```bash
cd linux && make KDIR=/home/alarm/kw/src/linux-7.1-r0
sudo insmod hakios_ramoops.ko
../tools/capture-boot-log.sh ramoops
```

Expected M1 banner:

```text
mtkchain-begonia M1
ramoops console 0x4d09f000 pmsg 0x4d0e0000
request: Linux
linux image len: 0x...
dtb: 0x... -> 0x4b000000 size ...
stub: ...
chaining Linux at 0x40080000
```

After `tools/request-xnu.sh --no-reboot` + reboot:

```text
request: XNU
XNU requested; M1 dry-run, no XNU payload started
M2: mtkloader will load the XNU payload and the microSD xnusys image
chaining Linux at 0x40080000
```

The pmsg is cleared, so the next boot is `request: Linux` again.

## 3. M2: the microSD log

`tools/sd-layout.sh` creates (destroys the SD contents):

```text
p2  hackios-log  64 MiB raw
```

The full mtkloader writes the XNU console/panic/return log there; Linux reads
it without mounting:

```bash
sudo dd if=/dev/disk/by-partlabel/hackios-log of=logs/hackios-log.bin bs=1M
strings logs/hackios-log.bin | tail -200
# or
tools/capture-boot-log.sh sd /dev/disk/by-partlabel/hackios-log
```

The log format is the loader's ring (a header plus text); `strings` is enough
to read it. The M2 loader also keeps the ramoops console for compatibility
with the M1 tools.

## 4. Why not `/sys/fs/pstore`?

The current kernel does not enable the pstore console/pmsg backends. Rebuilding
the kernel with `CONFIG_PSTORE_CONSOLE=y`/`CONFIG_PSTORE_PMSG=y` would expose
`/sys/fs/pstore/console-ramoops-0` and `/dev/pmsg0`, but that is a full kernel
rebuild and a boot image update; the ramoops module + SD log avoid it. If the
kernel is rebuilt later, the same region and the same addresses remain valid.

## 5. UART

The MediaTek UART is at `0x11002000` (the mt6768 loader's `uart_putc`). The
phone's UART pads are not exposed on a normal USB cable, so the project logs to
ramoops/SD; the UART is a debugging option only if the test points are
accessible.

## 6. XNU's log

XNU writes its console to the framebuffer and, in the mt6768 design, returns to
the loader through `loader_return.c` with a log pointer/length; the loader
copies it to ramoops/`hackios-log`. In M1 there is no XNU log; M2 adds the
return stub and the SD/ramoops copy. A panic before the return is caught by the
loader's watcher (the mt6768 `xnu_return_stub`/watchdog) and logged the same
way.
