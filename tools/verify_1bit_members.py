#!/usr/bin/env python3
"""Pass/fail check that the repaired 1-bit members match their CASt rect.

Asserts the player-visible invariant rather than that two derived numbers
agree: every 1-bit member's exported BMP must be exactly the size Director
recorded for it, and the cursor members the original names in `cursorfunk` must
all be present and non-blank. A cursor that decodes to the right size but is
entirely white would pass a geometry check and show nothing on screen.

Exits non-zero on any failure.

Usage:
    python3 tools/verify_1bit_members.py [--chunks PATH]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from repair_1bit_members import (  # noqa: E402
    DEFAULT_CHUNKS, REPO, chunk_dirs, read_bitmap,
)

# Assigned by MASTER/External/MovieScript 13 - cursor funk.ls, plus the hand
# each room's init puts on an occupied inventory slot.
CURSOR_NAMES = [
    "wlkcur1", "wlkcur2", "magni1", "magni2", "trgcur1", "trgcur2",
    "leftcur1", "leftcur2", "rightcur1", "rightcur2",
    "upcur1", "upcur2", "downcur1", "downcur2", "hand1", "hand2",
]


def bmp_size(path: Path):
    raw = path.read_bytes()
    if len(raw) < 26:
        return None
    width, height = struct.unpack_from("<ii", raw, 18)
    return width, height


def bmp_is_blank(path: Path) -> bool:
    """True when every pixel is the same index, so nothing would be visible."""
    raw = path.read_bytes()
    offset, = struct.unpack_from("<I", raw, 10)
    pixels = raw[offset:]
    return len(set(pixels)) <= 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chunks", type=Path, default=DEFAULT_CHUNKS)
    args = parser.parse_args()

    dumps = chunk_dirs(args.chunks)
    names = json.loads((REPO / "data/lingo/member_names.json").read_text())
    failures = []
    checked = 0
    cursors_seen = {}

    for members_path in sorted(REPO.glob("assets/render_model/*/members.json")):
        movie_dir = members_path.parent
        doc = json.loads(members_path.read_text())
        for key, info in doc["members"].items():
            if ":" not in key or not isinstance(info, dict):
                continue
            if "cast_resource_id" not in info or "bitd_resource_id" not in info:
                continue
            owner = str(info.get("cast_lib_name", "")).upper()
            chunks = (dumps.get(owner) if owner and owner != "INTERNAL"
                      else dumps.get(movie_dir.name))
            if chunks is None:
                continue
            cast_path = chunks / f"CASt-{info['cast_resource_id']}.bin"
            bitd_path = chunks / f"BITD-{info['bitd_resource_id']}.bin"
            if not cast_path.exists() or not bitd_path.exists():
                continue
            bitmap = read_bitmap(cast_path, bitd_path)
            if bitmap is None:
                continue

            checked += 1
            where = f"{movie_dir.name} {key}"
            if (info["width"], info["height"]) != (bitmap.width, bitmap.height):
                failures.append(
                    f"{where}: members.json says "
                    f"{info['width']}x{info['height']}, CASt says "
                    f"{bitmap.width}x{bitmap.height}")
                continue

            bmp_path = movie_dir / info["path"].removeprefix("./")
            size = bmp_size(bmp_path) if bmp_path.exists() else None
            if size != (bitmap.width, bitmap.height):
                failures.append(
                    f"{where}: {bmp_path.name} is {size}, "
                    f"CASt says {bitmap.width}x{bitmap.height}")
                continue

            name = str(names.get(movie_dir.name, {}).get(key.split(":")[1], "")).lower()
            if name in CURSOR_NAMES:
                cursors_seen.setdefault(name, set()).add(movie_dir.name)
                if bmp_is_blank(bmp_path):
                    failures.append(f"{where}: cursor {name} is a blank image")

    missing = [n for n in CURSOR_NAMES if n not in cursors_seen]
    if missing:
        failures.append(f"cursor members never found: {', '.join(missing)}")

    print(f"checked {checked} 1-bit members, "
          f"{len(cursors_seen)}/{len(CURSOR_NAMES)} cursor names present")
    for failure in failures:
        print(f"FAIL {failure}")
    if failures:
        print(f"\n{len(failures)} failures")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
