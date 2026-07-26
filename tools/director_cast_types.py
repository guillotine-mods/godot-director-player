#!/usr/bin/env python3
"""Read Director cast member types from decompiled cast chunks.

A sprite whose member is a bitmap and does not resolve is missing art. A sprite
whose member is a shape is *meant* to draw nothing: Director shapes are what this
game uses for its invisible hotspots, and `island2` member 30 is exactly `DAY1`
channel 10, the left-edge walk hotspot. Both look identical to a renderer that
only knows about bitmaps, which is why `check_cast_coverage.py` once reported 222
unresolvable members when only 13 were real.

This module tells the two apart by reading the int32 type at the head of each
CASt chunk.
"""

from __future__ import annotations

from pathlib import Path

from director_film_loops import _read_bytes, _u32, _warning, parse_cas

## Director cast member types, from the int32 at CASt offset 0.
MEMBER_TYPES = {
    1: "bitmap",
    2: "filmLoop",
    3: "field",
    4: "palette",
    5: "picture",
    6: "sound",
    7: "button",
    8: "shape",
    9: "movie",
    10: "digitalVideo",
    11: "script",
    12: "richText",
    13: "OLE",
    14: "transition",
}

## Types that resolve to pixels the renderer is expected to draw. Everything else
## legitimately draws nothing, and absence from the registry is not a defect.
DRAWING_TYPES = frozenset({"bitmap", "filmLoop", "picture", "richText"})


def member_types(chunks_dir: Path) -> dict[str, str]:
    """Map one-based cast member ID to its Director type name."""
    types: dict[str, str] = {}
    for member_id, resource_id in sorted(parse_cas(chunks_dir).items()):
        data = _read_bytes(chunks_dir / f"CASt-{resource_id}.bin")
        if data is None:
            continue
        if len(data) < 4:
            _warning(f"short CASt resource {resource_id} in {chunks_dir}")
            continue
        code = _u32(data, 0)
        types[str(member_id)] = MEMBER_TYPES.get(code, f"type{code}")
    return types


def non_drawing_members(chunks_dir: Path) -> dict[str, str]:
    """Map member ID to type name for every member that draws nothing by design."""
    return {
        member_id: type_name
        for member_id, type_name in member_types(chunks_dir).items()
        if type_name not in DRAWING_TYPES
    }
