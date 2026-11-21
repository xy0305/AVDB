#!/usr/bin/env python3
"""Insert LC_LOAD_DYLIB into an unsigned Mach-O binary.

Approach matches typo/insert_dylib: write a new load command in the unused
zero-filled slack between the current load commands and the first mapped
section. The file size does not change. Encrypted binaries are refused.
This script never signs and never claims a signature is valid.
"""
from __future__ import annotations

import argparse
import shutil
import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_ID_DYLIB = 0x0D
LC_LOAD_WEAK_DYLIB = 0x18
LC_REEXPORT_DYLIB = 0x1F
LC_ENCRYPTION_INFO = 0x21
LC_ENCRYPTION_INFO_64 = 0x2C
LC_CODE_SIGNATURE = 0x1D
CPU_ARM64 = 0x0100000C


def align(n: int, a: int) -> int:
    return (n + a - 1) & ~(a - 1)


def build_load_dylib(path: str) -> bytes:
    name = path.encode("utf-8") + b"\x00"
    cmdsize = align(24 + len(name), 8)
    payload = name + (b"\x00" * (cmdsize - 24 - len(name)))
    return struct.pack("<IIIIII", LC_LOAD_DYLIB, cmdsize, 24, 2, 0x10000, 0x10000) + payload


def parse_header(data: bytes, off: int) -> dict:
    magic = struct.unpack_from("<I", data, off)[0]
    if magic == MH_MAGIC_64:
        endian = "<"
    elif magic == MH_CIGAM_64:
        endian = ">"
    else:
        raise ValueError(f"unsupported magic {hex(magic)} at offset {off}")
    cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from(
        endian + "IIIIIII", data, off + 4
    )
    return {
        "endian": endian,
        "magic": magic,
        "cputype": cputype,
        "filetype": filetype,
        "ncmds": ncmds,
        "sizeofcmds": sizeofcmds,
        "header_size": 32,
    }


def iter_commands(data: bytes, off: int, hdr: dict):
    o = off + hdr["header_size"]
    for i in range(hdr["ncmds"]):
        cmd, cmdsize = struct.unpack_from(hdr["endian"] + "II", data, o)
        yield i, o, cmd, cmdsize
        o += cmdsize


def read_cstring(data: bytes, off: int) -> str:
    end = data.find(b"\x00", off)
    if end < 0:
        raise ValueError("unterminated string in load command")
    return data[off:end].decode("utf-8", "replace")


def slice_limit(data: bytes, off: int, hdr: dict) -> int:
    """Slice-relative cap for load commands: min later segment fileoff, else __TEXT filesize."""
    later = []
    text_filesz = None
    for _, o, cmd, _ in iter_commands(data, off, hdr):
        if cmd != LC_SEGMENT_64:
            continue
        fileoff, filesize = struct.unpack_from(hdr["endian"] + "QQ", data, o + 8 + 16 + 16)
        if fileoff == 0:
            text_filesz = filesize
        else:
            later.append(fileoff)
    if later:
        return min(later)
    if text_filesz is None:
        raise SystemExit("cannot determine header slack (no LC_SEGMENT_64)")
    return text_filesz


def dylib_names(data: bytes, off: int, hdr: dict) -> list[str]:
    names = []
    for _, o, cmd, _ in iter_commands(data, off, hdr):
        if cmd not in (LC_LOAD_DYLIB, LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB):
            continue
        namoff = struct.unpack_from(hdr["endian"] + "I", data, o + 8)[0]
        names.append(read_cstring(data, o + namoff))
    return names


def is_encrypted(data: bytes, off: int, hdr: dict) -> bool:
    for _, o, cmd, _ in iter_commands(data, off, hdr):
        if cmd in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64):
            cryptid = struct.unpack_from(hdr["endian"] + "I", data, o + 16)[0]
            if cryptid:
                return True
    return False


def has_code_signature(data: bytes, off: int, hdr: dict) -> bool:
    return any(cmd == LC_CODE_SIGNATURE for _, _, cmd, _ in iter_commands(data, off, hdr))


def patch_thin(buf: bytearray, off: int, dylib: str) -> str:
    hdr = parse_header(bytes(buf), off)
    if is_encrypted(bytes(buf), off, hdr):
        raise SystemExit("refusing to modify an encrypted Mach-O (cryptid != 0)")
    if dylib in dylib_names(bytes(buf), off, hdr):
        return "already-loaded"
    cmd = build_load_dylib(dylib)
    limit = slice_limit(bytes(buf), off, hdr)
    used = hdr["header_size"] + hdr["sizeofcmds"]
    slack = limit - used
    if slack < len(cmd):
        raise SystemExit(
            f"not enough header slack to insert load command "
            f"(need {len(cmd)} bytes, have {slack}; sizeofcmds={hdr['sizeofcmds']}, cap={limit})"
        )
    insert_at = off + used
    padding = bytes(buf[insert_at : insert_at + len(cmd)])
    if any(padding):
        raise SystemExit("header slack is not zero-filled; refusing to overwrite")
    buf[insert_at : insert_at + len(cmd)] = cmd
    struct.pack_into(hdr["endian"] + "I", buf, off + 16, hdr["ncmds"] + 1)
    struct.pack_into(hdr["endian"] + "I", buf, off + 20, hdr["sizeofcmds"] + len(cmd))
    note = "inserted"
    if has_code_signature(bytes(buf), off, hdr):
        note += " (LC_CODE_SIGNATURE no longer matches; output is unsigned)"
    return note


def patch_macho(data: bytes, dylib: str) -> tuple[bytearray, list[str]]:
    buf = bytearray(data)
    magic_be = struct.unpack_from(">I", data, 0)[0]
    notes = []
    if magic_be in (FAT_MAGIC, FAT_CIGAM):
        nfat = struct.unpack_from(">I", data, 4)[0]
        for i in range(nfat):
            cputype, cpusub, offset, size, align_ = struct.unpack_from(">IIIII", data, 8 + i * 20)
            notes.append(f"fat slice {i} cpu={hex(cputype)} @{offset}: {patch_thin(buf, offset, dylib)}")
        return buf, notes
    notes.append("thin: " + patch_thin(buf, 0, dylib))
    return buf, notes


def package_ipa(src_ipa: Path, dylib: Path, out_ipa: Path, exe_rel: str | None = None) -> None:
    import tempfile, zipfile, os, stat

    if out_ipa.exists():
        out_ipa.unlink()
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        with zipfile.ZipFile(src_ipa, "r") as zf:
            zf.extractall(tmp_path)
        payload = tmp_path / "Payload"
        apps = list(payload.glob("*.app"))
        if len(apps) != 1:
            raise SystemExit(f"expected one Payload/*.app, found {apps}")
        app = apps[0]
        frameworks = app / "Frameworks"
        frameworks.mkdir(exist_ok=True)
        dest = frameworks / dylib.name
        shutil.copy2(dylib, dest)
        dest.chmod(dest.stat().st_mode | stat.S_IXUSR)
        if exe_rel:
            exe = app / exe_rel
        else:
            # Info.plist CFBundleExecutable
            import plistlib
            with open(app / "Info.plist", "rb") as f:
                info = plistlib.load(f)
            exe = app / info["CFBundleExecutable"]
        if not exe.is_file():
            raise SystemExit(f"missing executable {exe}")
        original = exe.read_bytes()
        patched, notes = patch_macho(original, f"@executable_path/Frameworks/{dylib.name}")
        exe.write_bytes(patched)
        log = tmp_path / "AVDB115-insert-notes.txt"
        log.write_text("\n".join(notes) + "\n")
        # Zip with Payload at the root, like an IPA. No signing.
        with zipfile.ZipFile(out_ipa, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(payload.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(tmp_path).as_posix())
            zf.write(log, "AVDB115-insert-notes.txt")
        print("IPA:", out_ipa, f"({out_ipa.stat().st_size} bytes)")
        for n in notes:
            print(" ", n)
        print("unsigned: yes (no codesign step was attempted)")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_bin = sub.add_parser("binary", help="patch a Mach-O executable in place or to --output")
    p_bin.add_argument("binary")
    p_bin.add_argument("dylib_path", help="LC_LOAD_DYLIB path, e.g. @executable_path/Frameworks/AVDB115.dylib")
    p_bin.add_argument("-o", "--output")

    p_ipa = sub.add_parser("ipa", help="copy dylib into an IPA, patch Runner, write an unsigned IPA")
    p_ipa.add_argument("ipa")
    p_ipa.add_argument("dylib")
    p_ipa.add_argument("-o", "--output", required=True)

    args = ap.parse_args()
    if args.cmd == "binary":
        src = Path(args.binary)
        data = src.read_bytes()
        patched, notes = patch_macho(data, args.dylib_path)
        dest = Path(args.output) if args.output else src
        if dest == src:
            shutil.copy2(src, src.with_suffix(src.suffix + ".bak"))
        dest.write_bytes(patched)
        for n in notes:
            print(n)
        print("wrote", dest)
    else:
        package_ipa(Path(args.ipa), Path(args.dylib), Path(args.output))


if __name__ == "__main__":
    main()
