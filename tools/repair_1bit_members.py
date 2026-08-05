#!/usr/bin/env python3
"""Repair the 1-bit cast members the upstream exporter decoded wrong.

`assets/render_model/` was produced on a Windows machine (`assets/SOURCE.txt`)
by an exporter that is not in any repo on this machine. That exporter reads
Director's CASt pitch field, records its high byte as `bpp_marker`, and then
ignores it: every member is decoded as 8 bits per pixel with geometry inferred
from the decoded byte count. It is right for 8-bit members and wrong for every
1-bit one. `cast_0010.bmp` in DAY1 is `wlkcur1`, the walking-legs cursor, and
comes out 5x6 pixels of colour noise.

CASt carries, after the `(type, common_size, specific_size)` header and the
common block, a u16 pitch and then a SIGNED rect as top, left, bottom, right.
Pitch bit 0x8000 is the depth flag: set means 8bpp, clear means 1bpp. The low
15 bits are the row stride in bytes. 1-bit members are stored raw, so the BITD
chunk length is exactly `stride * height`.

Rewrites the BMP at the true rect and corrects the geometry in members.json.
The BMP stays 8-bit paletted with the file's own palette, so only the pixels
and the dimensions change and nothing downstream sees a new format.

Usage:
    python3 tools/repair_1bit_members.py [--dry-run] [--chunks PATH]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# The pre-dumped ProjectorRays chunks. Not in this repo: 139 MB, and
# reference/README.md records them as already processed into render_model.
DEFAULT_CHUNKS = Path.home() / (
    "Projects/_private_projects/Piposh2-Port/originals/recovery"
    "/web-alpha/decompiled_chunks"
)

CAST_TYPE_BITMAP = 1
DEPTH_FLAG_8BPP = 0x8000
STRIDE_MASK = 0x7FFF

def palette_indices(palette: bytes):
    """Finds this palette's own black and white, rather than assuming them.

    Assuming a 6x6x6 descending colour cube put black at 215 and painted every
    repaired cursor red. These files carry the real system palette, where black
    and white each appear exactly once, so look them up and fail loudly if the
    palette turns out not to hold them.
    """
    black = white = None
    for i in range(len(palette) // 4):
        b, g, r = palette[i * 4], palette[i * 4 + 1], palette[i * 4 + 2]
        if (r, g, b) == (0, 0, 0) and black is None:
            black = i
        elif (r, g, b) == (255, 255, 255) and white is None:
            white = i
    return black, white


class Bitmap:
    """One member's true geometry and pixels, read from CASt + BITD."""

    def __init__(self, width, height, stride, reg_x, reg_y, bits):
        self.width = width
        self.height = height
        self.stride = stride
        self.reg_x = reg_x
        self.reg_y = reg_y
        self.bits = bits

    def pixel(self, x, y):
        return (self.bits[y * self.stride + (x >> 3)] >> (7 - (x & 7))) & 1


def read_cast(path: Path):
    """Returns (type, pitch, rect, reg) for a CASt chunk, or None if unusable.

    The rect is SIGNED. Read unsigned it is nonsense, which is the trap the
    bitd-export spike recorded after measuring the whole corpus.
    """
    raw = path.read_bytes()
    if len(raw) < 12:
        return None
    kind, common_size, specific_size = struct.unpack_from(">III", raw, 0)
    start = 12 + common_size
    if specific_size < 22 or start + specific_size > len(raw):
        return None
    pitch, = struct.unpack_from(">H", raw, start)
    top, left, bottom, right = struct.unpack_from(">hhhh", raw, start + 2)
    reg_y, reg_x = struct.unpack_from(">hh", raw, start + 18)
    return kind, pitch, (right - left, bottom - top), (reg_x - left, reg_y - top)


def read_bitmap(cast_path: Path, bitd_path: Path):
    """Returns a Bitmap for a 1-bit member, or None when it is not one."""
    parsed = read_cast(cast_path)
    if parsed is None:
        return None
    kind, pitch, (width, height), (reg_x, reg_y) = parsed
    if kind != CAST_TYPE_BITMAP or pitch & DEPTH_FLAG_8BPP:
        return None
    stride = pitch & STRIDE_MASK
    if width <= 0 or height <= 0 or stride <= 0:
        return None

    bits = bitd_path.read_bytes()
    if len(bits) != stride * height:
        # Every 1-bit member measured so far is stored raw and consumes its
        # chunk exactly. Refuse rather than guess at a PackBits fallback that
        # no member in the corpus has needed.
        return None
    # A registration point outside its own rect would mean the offsets below
    # drifted for this member; centre is the safe reading and is what Director
    # uses when a member has no meaningful one.
    if not (0 <= reg_x <= width and 0 <= reg_y <= height):
        reg_x, reg_y = width // 2, height // 2
    return Bitmap(width, height, stride, reg_x, reg_y, bits)


def encode_bmp(bitmap: Bitmap, palette: bytes, black: int, white: int) -> bytes:
    """8-bit paletted BMP, bottom-up, rows padded to 4 bytes."""
    row_pad = (-bitmap.width) % 4
    pixels = bytearray()
    for y in range(bitmap.height - 1, -1, -1):
        for x in range(bitmap.width):
            pixels.append(black if bitmap.pixel(x, y) else white)
        pixels.extend(b"\0" * row_pad)

    offset = 14 + 40 + len(palette)
    header = struct.pack(
        "<2sIHHI", b"BM", offset + len(pixels), 0, 0, offset
    )
    info = struct.pack(
        "<IiiHHIIiiII",
        40, bitmap.width, bitmap.height, 1, 8, 0,
        len(pixels), 0x0B13, 0x0B13, len(palette) // 4, 0,
    )
    return header + info + bytes(palette) + bytes(pixels)


def existing_palette(path: Path) -> bytes:
    """The 256-entry palette already in the exported BMP, reused verbatim."""
    raw = path.read_bytes()
    if len(raw) < 54:
        return b""
    offset, = struct.unpack_from("<I", raw, 10)
    colours, = struct.unpack_from("<I", raw, 46)
    colours = colours or 256
    return raw[54:54 + colours * 4] if offset >= 54 + colours * 4 else b""


def chunk_dirs(root: Path) -> dict:
    """movie -> its chunks directory, for the movies that have a dump."""
    found = {}
    for path in root.glob("*/*/chunks"):
        found.setdefault(path.parts[-3], path)
    return found


def repair_movie(movie_dir: Path, dumps: dict, dry_run: bool):
    """Repairs every 1-bit member of one movie. Returns (repaired, digests)."""
    members_path = movie_dir / "members.json"
    doc = json.loads(members_path.read_text())
    members = doc["members"]

    repaired = 0
    digests = {}
    for key, info in members.items():
        if ":" not in key or not isinstance(info, dict):
            continue
        if "cast_resource_id" not in info or "bitd_resource_id" not in info:
            continue
        # Resource ids are numbered per cast, so a shared-library member must be
        # looked up in its OWN cast's dump. Reading them out of the movie's dump
        # silently resolves to a different member that happens to hold that id:
        # AIR1's `3:14` is master:14, but AIR1's own CASt-58 parses fine and
        # describes something else entirely.
        owner = str(info.get("cast_lib_name", "")).upper()
        chunks = dumps.get(owner) if owner and owner != "INTERNAL" else dumps.get(movie_dir.name)
        if chunks is None:
            continue
        cast_path = chunks / f"CASt-{info['cast_resource_id']}.bin"
        bitd_path = chunks / f"BITD-{info['bitd_resource_id']}.bin"
        if not cast_path.exists() or not bitd_path.exists():
            continue
        bitmap = read_bitmap(cast_path, bitd_path)
        if bitmap is None:
            continue

        bmp_path = movie_dir / info["path"].removeprefix("./")
        palette = existing_palette(bmp_path) if bmp_path.exists() else b""
        if not palette:
            continue
        black, white = palette_indices(palette)
        if black is None or white is None:
            print(f"  {movie_dir.name} {key}: palette has no black/white, skipped",
                  file=sys.stderr)
            continue

        digests[key] = hashlib.sha1(bitmap.bits).hexdigest()
        if not dry_run:
            bmp_path.write_bytes(encode_bmp(bitmap, palette, black, white))
            info["width"] = bitmap.width
            info["height"] = bitmap.height
            info["decoded_bytes"] = bitmap.stride * bitmap.height
            info["row_stride_source"] = bitmap.stride
            info["bpp_marker"] = 1
            info["reg_offset_x"] = bitmap.reg_x
            info["reg_offset_y"] = bitmap.reg_y
        repaired += 1

    if repaired and not dry_run:
        members_path.write_text(json.dumps(doc, separators=(",", ":")))
    return repaired, digests


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chunks", type=Path, default=DEFAULT_CHUNKS)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.chunks.is_dir():
        print(f"no chunk dump at {args.chunks}", file=sys.stderr)
        return 1

    dumps = chunk_dirs(args.chunks)
    movies = sorted(p.parent for p in REPO.glob("assets/render_model/*/members.json"))

    total = 0
    with_members = 0
    per_name = {}
    names = json.loads((REPO / "data/lingo/member_names.json").read_text())
    for movie_dir in movies:
        count, digests = repair_movie(movie_dir, dumps, args.dry_run)
        if count:
            with_members += 1
        total += count
        if count:
            print(f"  {movie_dir.name:<10} {count:>4} members")
        for key, digest in digests.items():
            name = names.get(movie_dir.name, {}).get(key.split(":")[1])
            if name:
                per_name.setdefault(str(name).lower(), set()).add(digest)

    reachable = sum(1 for m in movies if m.name in dumps)
    disagreeing = {n: d for n, d in per_name.items() if len(d) > 1}
    print(f"\n{total} 1-bit members repaired, in {with_members} of the "
          f"{reachable} movies with a local chunk dump "
          f"({len(movies) - reachable} movies have none)")
    if disagreeing:
        print(f"WARNING: {len(disagreeing)} names differ between movies: "
              f"{sorted(disagreeing)[:6]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
