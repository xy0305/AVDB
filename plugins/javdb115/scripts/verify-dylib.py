#!/usr/bin/env python3
"""Mach-O checks for the iOS arm64 plugin dylib. Fail if this is not a real binary."""
from __future__ import annotations
import argparse, struct, sys
from pathlib import Path

MH_MAGIC_64 = 0xfeedfacf
MH_CIGAM_64 = 0xcffaedfe
FAT_MAGIC = 0xcafebabe
FAT_CIGAM = 0xbebafeca
MH_DYLIB = 6
CPU_ARM64 = 0x0100000C
LC_LOAD_DYLIB = 0x0C
LC_ID_DYLIB = 0x0D
LC_ENCRYPTION_INFO = 0x21
LC_ENCRYPTION_INFO_64 = 0x2C
LC_BUILD_VERSION = 0x32
LC_CODE_SIGNATURE = 0x1D


def parse_thin(data: bytes, off: int = 0):
    magic = struct.unpack_from("<I", data, off)[0]
    endian = "<" if magic in (MH_MAGIC_64, 0xFEEDFACE) else ">"
    if magic not in (MH_MAGIC_64, MH_CIGAM_64):
        raise SystemExit(f"not a 64-bit mach-o (magic={hex(magic)})")
    cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from(endian + "IIIIIII", data, off + 4)
    cmd_off = off + 32
    dylibs = []
    cryptid = 0
    platform = None
    has_sig = False
    o = cmd_off
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from(endian + "II", data, o)
        if cmd in (LC_LOAD_DYLIB, LC_ID_DYLIB):
            namoff = struct.unpack_from(endian + "I", data, o + 8)[0]
            end = data.find(b"\x00", o + namoff)
            dylibs.append((cmd, data[o + namoff:end].decode()))
        if cmd in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64):
            if cmd == LC_ENCRYPTION_INFO:
                _, _, cryptid = struct.unpack_from(endian + "III", data, o + 8)
            else:
                _, _, cryptid, _ = struct.unpack_from(endian + "IIII", data, o + 8)
        if cmd == LC_BUILD_VERSION:
            platform, minos, sdk, ntools = struct.unpack_from(endian + "IIII", data, o + 8)
        if cmd == LC_CODE_SIGNATURE:
            has_sig = True
        o += cmdsize
    return {
        "cputype": cputype,
        "filetype": filetype,
        "ncmds": ncmds,
        "cryptid": cryptid,
        "platform": platform,
        "dylibs": dylibs,
        "has_sig": has_sig,
        "minos": minos if platform is not None else None,
        "sdk": sdk if platform is not None else None,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    args = ap.parse_args()
    path = Path(args.path)
    data = path.read_bytes()
    if len(data) < 32:
        raise SystemExit("file too small to be a dylib")
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic in (FAT_MAGIC, FAT_CIGAM, 0xCAFEBABF, 0xBFBAFECA):
        nfat = struct.unpack_from(">I", data, 4)[0]
        # inspect first slice
        cputype, cpusub, offset, size, align = struct.unpack_from(">IIIII", data, 8)
        info = parse_thin(data, offset)
        info["fat"] = True
        info["nfat"] = nfat
    else:
        info = parse_thin(data, 0)
        info["fat"] = False

    errors = []
    if info["filetype"] != MH_DYLIB:
        errors.append(f"filetype {info['filetype']} is not MH_DYLIB (6)")
    if info["cputype"] != CPU_ARM64 and (info["cputype"] & 0xFFFFFFFF) != CPU_ARM64:
        errors.append(f"cputype {hex(info['cputype'])} is not ARM64")
    if info["cryptid"]:
        errors.append(f"encrypted cryptid={info['cryptid']}")
    ids = [n for c, n in info["dylibs"] if c == LC_ID_DYLIB]
    if not ids:
        errors.append("missing LC_ID_DYLIB")
    # platform 2 = iOS
    if info["platform"] not in (None, 2, 7):  # 7 is iOS simulator; we want 2
        if info["platform"] != 2:
            errors.append(f"unexpected platform {info['platform']} (want iOS=2)")

    print(f"path: {path}")
    print(f"size: {path.stat().st_size}")
    print(f"fat: {info['fat']}  filetype: {info['filetype']}  cputype: {hex(info['cputype'])}")
    print(f"cryptid: {info['cryptid']}  platform: {info['platform']}  signed: {info['has_sig']}")
    print("id:", ids)
    print("load:")
    for c, n in info["dylibs"]:
        kind = "id" if c == LC_ID_DYLIB else "load"
        print(f"  {kind}: {n}")
    if errors:
        print("FAIL:", "; ".join(errors))
        sys.exit(1)
    print("PASS: arm64 iOS MH_DYLIB, unencrypted")


if __name__ == "__main__":
    main()
