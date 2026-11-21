#!/usr/bin/env python3
"""Validate the device repository contract used by the HakiOS tooling:
a device.conf/soc.conf header with one field per tab-indented line, and a
defconfig that includes the common, SoC and device fragments."""
import pathlib
import sys


def parse(path, kind):
    lines = pathlib.Path(path).read_text().splitlines()
    head = [l for l in lines if l.strip() and not l.lstrip().startswith("#")][0].split()
    assert head[0] == kind and len(head) == 2, (path, head)
    rows = [l.split(None, 1)[0] for l in lines if l.startswith("\t")]
    assert rows, path
    print(f"{path}: {head[1]} ({len(rows)} fields)")


def main():
    parse("device.conf", "device")
    parse("soc/mt6785/soc.conf", "soc")

    defconfig = pathlib.Path("configs/begonia_defconfig").read_text()
    for inc in ("common_defconfig", "mt6785.config", "begonia.config"):
        assert f"#include {inc}" in defconfig, f"defconfig missing #include {inc}"
    for path in ("configs/begonia.config", "soc/mt6785/configs/mt6785.config"):
        assert pathlib.Path(path).is_file(), path
    print("defconfig includes: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
