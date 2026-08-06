#!/usr/bin/env python3
"""List the files packed inside a MindVision VISE installer.

The Piposh 2 Windows release ships as a VISE self-installer that carries every
Director movie (.DXR) and protected cast library (.CXT) the decode pipeline
needs. The directory is plain in the executable and is decoded here; the file
*payloads* use VISE's own compression, which is not zlib, bzip2 or lzma, so this
tool deliberately does not attempt extraction. Run the installer to get the
files out, then use this listing to verify the result is complete and
untruncated:

    python3 tools/list_vise_archive.py piposh2.exe --ext CXT CST
    python3 tools/list_vise_archive.py piposh2.exe --verify <installed dir>

Record layout, relative to the end of the length-prefixed name:
    +4  uncompressed size   +8  compressed size   +16  payload offset
Confirmed by chaining: every entry's offset + compressed size is exactly the
next entry's offset.
"""

from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path

NAME_RECORD = re.compile(rb"\x00([\x03-\x18])\x00([A-Za-z0-9_\-\. ]{3,24})")


def entries(data: bytes) -> list[dict]:
    """Every directory record whose payload chains to a plausible offset."""
    found: list[dict] = []
    for match in NAME_RECORD.finditer(data):
        length = match.group(1)[0]
        raw = match.group(2)
        if len(raw) < length:
            continue
        name = raw[:length].decode("latin1")
        if name.count(".") != 1:
            continue
        end = match.start(2) + length
        if end + 20 > len(data):
            continue
        uncompressed = struct.unpack_from("<I", data, end + 4)[0]
        compressed = struct.unpack_from("<I", data, end + 8)[0]
        offset = struct.unpack_from("<I", data, end + 16)[0]
        if not (0 < uncompressed < len(data) and 0 < compressed < len(data)):
            continue
        if not 0 < offset < len(data):
            continue
        found.append(
            {
                "name": name,
                "uncompressed": uncompressed,
                "compressed": compressed,
                "offset": offset,
            }
        )
    unique = {(e["name"].upper(), e["offset"]): e for e in found}
    return sorted(unique.values(), key=lambda e: e["offset"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("installer", type=Path)
    parser.add_argument("--ext", nargs="*", default=None, help="filter by extension")
    parser.add_argument(
        "--verify",
        type=Path,
        default=None,
        help="directory of extracted files to check against the listing",
    )
    args = parser.parse_args()

    data = args.installer.read_bytes()
    listing = entries(data)
    if args.ext:
        wanted = {e.upper().lstrip(".") for e in args.ext}
        listing = [e for e in listing if e["name"].rsplit(".", 1)[-1].upper() in wanted]

    if not listing:
        print("no directory records found — is this a VISE installer?")
        return 1

    print(f"{'file':20s}{'uncompressed':>14s}{'packed':>12s}{'offset':>12s}")
    for entry in listing:
        print(
            f"{entry['name']:20s}{entry['uncompressed']:14d}"
            f"{entry['compressed']:12d}{entry['offset']:12d}"
        )
    print(f"\n{len(listing)} files")

    if args.verify is None:
        return 0

    missing = 0
    for entry in listing:
        candidates = list(args.verify.rglob(entry["name"]))
        if not candidates:
            print(f"MISSING  {entry['name']}")
            missing += 1
            continue
        # A name can appear twice with different contents: the installer holds
        # two MASTER.CST, 483150 bytes in PIP2DATA and 481764 in the root. Take
        # any copy at the expected size, or comparing both entries against
        # whichever one rglob happened to return first fails a good extraction.
        sizes = [c.stat().st_size for c in candidates]
        if entry["uncompressed"] not in sizes:
            print(
                f"SIZE     {entry['name']}: {sizes[0]} on disk, "
                f"{entry['uncompressed']} expected"
            )
            missing += 1
    if missing:
        print(f"\n{missing} files missing or wrong size")
        return 1
    print("\nevery listed file is present at the expected size")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
