#!/usr/bin/env python3
"""Make a synthetic Android boot image (header v2) for CI.

The kernel is a fake arm64 Image (header + a little data), gzip-compressed;
the ramdisk and DTB are small blobs.  It is only used to exercise
tools/chainboot.py and tools/check-chain-image.py without a phone.
"""
import gzip
import struct
import sys

PAGE = 2048


def pad(b, n):
    return b + b"\0" * (-len(b) % n)


def main(out):
    image = bytearray(64 + 1024)
    struct.pack_into("<I", image, 0, 0x14000000)       # b
    struct.pack_into("<Q", image, 0x10, len(image))     # image_size
    struct.pack_into("<Q", image, 0x20, 0x0A)           # flags
    image[0x38:0x3C] = b"ARM\x64"
    kernel = gzip.compress(bytes(image), 9, mtime=0)
    ramdisk = b"R" * 512
    dtb = b"D" * 128

    hdr = bytearray(PAGE)
    hdr[0:8] = b"ANDROID!"
    struct.pack_into("<10I", hdr, 8,
                     len(kernel), 0x40080000, len(ramdisk), 0x41000000,
                     0, 0, 0x40000100, PAGE, 2, 0)
    struct.pack_into("<I", hdr, 1632, 0)                # recovery_dtbo_size
    struct.pack_into("<I", hdr, 1648, len(dtb))         # dtb_size

    img = bytes(hdr) + pad(kernel, PAGE) + pad(ramdisk, PAGE) + pad(dtb, PAGE)
    open(out, "wb").write(img)
    print(f"{out}: {len(img)} bytes, fake Image {len(image)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/linux-boot.img"))
