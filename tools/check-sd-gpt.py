#!/usr/bin/env python3
"""Check the M2 microSD GPT: the four partitions, their names, order and sizes.

usage: check-sd-gpt.py IMAGE_OR_DEVICE [--xnusys SIZE]
Reads only; never writes.  Sizes: 1M, 64M, 8G (or --xnusys).
"""
import struct
import sys

NAMES = ["hackios-request", "hackios-log", "xnusys", "hackios-data"]
SIZES = [1 << 20, 64 << 20, 8 << 30, None]
SECTOR = 512


def gib(n):
    return f"{n / (1 << 30):.3f} GiB"


def main():
    path = sys.argv[1]
    sizes = list(SIZES)
    if "--xnusys" in sys.argv:
        v = sys.argv[sys.argv.index("--xnusys") + 1]
        mult = {"K": 1 << 10, "M": 1 << 20, "G": 1 << 30}[v[-1].upper()]
        sizes[2] = int(v[:-1]) * mult
    with open(path, "rb") as f:
        f.seek(SECTOR)
        hdr = f.read(SECTOR)
        assert hdr[:8] == b"EFI PART", "no GPT header at LBA 1"
        ent_lba = struct.unpack_from("<Q", hdr, 72)[0]
        count = struct.unpack_from("<I", hdr, 80)[0]
        esize = struct.unpack_from("<I", hdr, 84)[0]
        f.seek(ent_lba * SECTOR)
        ents = f.read(count * esize)
    parts = []
    for i in range(count):
        e = ents[i * esize:(i + 1) * esize]
        first, last = struct.unpack_from("<QQ", e, 32)
        if not first:
            continue
        name = e[56:128].decode("utf-16le").rstrip("\0")
        parts.append((name, first, last, (last - first + 1) * SECTOR))
    assert [p[0] for p in parts] == NAMES, f"partitions are {[p[0] for p in parts]}, expected {NAMES}"
    for p, want in zip(parts, sizes):
        if want is not None:
            assert p[3] == want, f"{p[0]}: {p[3]} bytes, expected {want}"
    assert parts[0][1] == 2048, f"p1 starts at {parts[0][1]}, expected 2048"
    for a, b in zip(parts, parts[1:]):
        assert b[1] == a[2] + 1, f"{b[0]} does not follow {a[0]}"
    for name, first, last, size in parts:
        print(f"{name:18} LBA {first:10}..{last:10}  {gib(size)}")
    print(f"OK: {len(parts)} partitions, xnusys {gib(parts[2][3])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
