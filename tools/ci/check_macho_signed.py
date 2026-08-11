#!/usr/bin/env python3
"""Refuses a macOS binary that carries no embedded code signature.

    tools/ci/check_macho_signed.py path/to/GodotDirectorPlayer.app/Contents/MacOS/...

An ad-hoc signature that silently did not happen is invisible in Godot's export
log and fatal on Apple Silicon, where an unsigned binary does not execute at all.
The player sees a launch failure; CI sees a green run. This closes that gap.

Why not `codesign -v`: it is Mac-only, and the export runs on a Linux runner.
Why not `objdump --macho`: that spelling is LLVM's, and `objdump` on
ubuntu-latest is GNU binutils, which rejects the flag. Why not `grep` for the
string: `LC_CODE_SIGNATURE` is a numeric load command, not text in the file.

So the load commands are parsed directly. That needs no tool beyond python3,
which is present on both the Linux runner and a developer's Mac, and it means the
identical check runs in both places.

**This is weaker than `codesign -dv` and is not a substitute for it.** It proves a
signature blob is present and non-empty, not that it validates, and not that
Gatekeeper would accept it. It exists to catch the silent-no-op case, which is
the one that reaches a player.

A universal binary is a fat archive of several Mach-O images. EVERY slice has to
be signed, not merely one: a player on the arch whose slice was missed is exactly
as stuck as if none were signed, and checking only the first slice would hide it.
"""

import struct
import sys

FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC = 0xFEEDFACE
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM = 0xCEFAEDFE
MH_CIGAM_64 = 0xCFFAEDFE

LC_CODE_SIGNATURE = 0x1D

# Apple's cpu_type_t values, for naming a failing slice in a way a human can act
# on. An unknown type is reported as a number rather than guessed at.
CPU_NAMES = {7: "x86", 0x01000007: "x86_64", 12: "arm", 0x0100000C: "arm64"}


def cpu_name(cputype: int) -> str:
    return CPU_NAMES.get(cputype, f"cputype {cputype}")


def slices(blob: bytes):
    """Yield (offset, cpu_name) for each Mach-O image in the file."""
    if len(blob) < 8:
        raise ValueError("file is too short to be a Mach-O binary")

    magic = struct.unpack_from(">I", blob, 0)[0]
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        # Fat headers are always big-endian, regardless of the slices inside.
        wide = magic == FAT_MAGIC_64
        count = struct.unpack_from(">I", blob, 4)[0]
        entry = 32 if wide else 20
        for i in range(count):
            base = 8 + i * entry
            if wide:
                cputype, _sub, offset = struct.unpack_from(">iiQ", blob, base)
            else:
                cputype, _sub, offset = struct.unpack_from(">iiI", blob, base)
            yield offset, cpu_name(cputype & 0xFFFFFFFF)
        return

    # Not fat: a single image starting at 0. Its own magic decides endianness,
    # which `has_signature` reads again, so nothing is assumed here.
    yield 0, "single slice"


def has_signature(blob: bytes, offset: int) -> bool:
    magic = struct.unpack_from("<I", blob, offset)[0]
    if magic in (MH_MAGIC, MH_MAGIC_64):
        end = "<"
    elif magic in (MH_CIGAM, MH_CIGAM_64):
        end = ">"
    else:
        raise ValueError(f"no Mach-O magic at offset {offset} (got {magic:#x})")

    wide = magic in (MH_MAGIC_64, MH_CIGAM_64)
    ncmds = struct.unpack_from(end + "I", blob, offset + 16)[0]
    # mach_header is 28 bytes, mach_header_64 is 32 (it has a trailing reserved
    # field). Getting this wrong reads the first load command from the wrong
    # place and finds nothing, so it would fail closed rather than pass wrongly.
    pos = offset + (32 if wide else 28)

    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from(end + "II", blob, pos)
        if cmdsize == 0:
            raise ValueError("load command of size 0; the binary is malformed")
        if cmd == LC_CODE_SIGNATURE:
            # dataoff/datasize follow. A zero-length blob is a signature in name
            # only, and treating it as present is precisely the silent no-op this
            # script exists to catch.
            _dataoff, datasize = struct.unpack_from(end + "II", blob, pos + 8)
            return datasize > 0
        pos += cmdsize
    return False


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: check_macho_signed.py <binary>", file=sys.stderr)
        return 2

    path = argv[1]
    try:
        with open(path, "rb") as fh:
            blob = fh.read()
    except OSError as exc:
        print(f"FAIL  {path}: {exc}", file=sys.stderr)
        return 1

    try:
        found = list(slices(blob))
    except (ValueError, struct.error) as exc:
        print(f"FAIL  {path}: {exc}", file=sys.stderr)
        return 1

    # No slices at all would otherwise fall through the loop below and report a
    # pass having checked nothing, the same trap check_asset_size.sh guards with
    # its empty-argument case.
    if not found:
        print(f"FAIL  {path}: no Mach-O images found", file=sys.stderr)
        return 1

    unsigned = []
    for offset, name in found:
        try:
            if not has_signature(blob, offset):
                unsigned.append(name)
        except (ValueError, struct.error) as exc:
            print(f"FAIL  {path}: {name}: {exc}", file=sys.stderr)
            return 1

    arches = ", ".join(name for _off, name in found)
    if unsigned:
        print(
            f"FAIL  {path}: no code signature on: {', '.join(unsigned)}"
            f" (of {len(found)} slice(s): {arches})",
            file=sys.stderr,
        )
        print(
            "The export did not sign the binary. It will not launch on Apple Silicon.",
            file=sys.stderr,
        )
        return 1

    print(f"ok    {path}: {len(found)} signed slice(s): {arches}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
