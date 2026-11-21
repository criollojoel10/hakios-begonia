#!/usr/bin/env python3
"""Verify a chainboot.py output image: header v2, gzip kernel, loader header,
Linux Image length (res2), optional XNU payload offset (res3), size <= 64 MiB."""
import gzip
import struct
import sys


def main(path, expected=None):
    d = open(path, "rb").read()
    assert d[:8] == b"ANDROID!", "not an Android boot image"
    vals = struct.unpack_from("<9I", d, 8)
    ksize, page, hver = vals[0], vals[7], vals[8]
    assert hver == 2, f"header v{hver}, expected v2"
    assert len(d) <= 64 << 20, f"{len(d)} bytes > 64 MiB boot partition"
    kernel = d[page:page + ksize]
    img = gzip.decompress(kernel)
    assert img[0x38:0x3C] == b"ARM\x64", "loader has no arm64 Image magic"
    res2 = struct.unpack_from("<Q", img, 0x28)[0]
    res3 = struct.unpack_from("<Q", img, 0x30)[0]
    assert res2 > 0, "res2 (Linux Image length) is zero"
    assert img[0x40000 + 0x38:0x40000 + 0x3C] == b"ARM\x64", \
        "Linux Image is not at CHAIN_OFFSET"
    if expected is not None:
        assert res2 == int(expected), f"res2 {res2} != {expected}"
    payload = ""
    if res3:
        assert res3 % 16 == 0, f"payload offset {res3} is not 16-aligned"
        assert res3 + 8 <= len(img), "payload offset is past the decompressed kernel"
        magic, size = struct.unpack_from("<II", img, res3)
        assert magic == 0x50554E58, f"no XNUP payload at {res3:#x} (magic {magic:#x})"
        assert res3 + 8 + size <= len(img), "payload size runs past the decompressed kernel"
        names = []
        at = res3 + 8
        while at + 24 <= res3 + 8 + size:
            name, n, _ = struct.unpack_from("<16sII", img, at)
            name = name.rstrip(b"\0").decode(errors="replace")
            if not name:
                break
            names.append(f"{name}={n}")
            at += 24 + ((n + 15) // 16) * 16
        assert "kernel=" in " ".join(names), "payload has no kernel entry"
        assert "ramdisk=" in " ".join(names), "payload has no ramdisk entry"
        payload = f"; payload {size} bytes ({', '.join(names)})"
    print(f"{path}: {len(d)} bytes; kernel {ksize}; Linux Image {res2}; "
          f"payload offset {res3}{payload}")
    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None))
