#!/usr/bin/env python3
"""Extract Director 7 film-loop scores from decompiled cast chunks.

A loop's mini-score is the same channel-buffer format as the movie's own score,
so `tools/director_score.py` documents the 48-byte sprite record. The one place
they differ is the member reference at offset 4: in the movie's score that u16 is
the cast library, `0xFFFF` for the movie's own cast. In a loop's mini-score it is
a **zero-based index into the owning file's `ccl ` chunk**, an ordered list of the
external cast files the loops reference, which is not the movie's cast-library
order. MURDER1's cast libraries run internal, goldolin, hezi, tofi; its `ccl `
runs tofi, goldolin, hezi, and its loop children index the latter.
"""

from __future__ import annotations

import struct
from pathlib import Path


MAIN_CHANNEL_SIZE = 288
SPRITE_CHANNEL_SIZE = 48
MAX_D7_SPRITE_CHANNELS = 200
MAX_D7_CHANNEL_DATA = MAIN_CHANNEL_SIZE + SPRITE_CHANNEL_SIZE * MAX_D7_SPRITE_CHANNELS
## Offset 4 of a mini-score sprite record: the owning file's own cast.
OWN_CAST = 0xFFFF
## A `ccl ` chunk is a handful of cast paths, never a hundred.
MAX_CCL_ENTRIES = 64


def _u32(data: bytes, offset: int, endian: str = ">") -> int:
    return struct.unpack_from(f"{endian}I", data, offset)[0]


def _i32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">i", data, offset)[0]


def _u16(data: bytes, offset: int, endian: str = ">") -> int:
    return struct.unpack_from(f"{endian}H", data, offset)[0]


def _i16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">h", data, offset)[0]


def _warning(message: str) -> None:
    print(f"warning: {message}")


def _read_bytes(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except OSError as error:
        _warning(f"cannot read {path}: {error}")
        return None


def _chunk_tag(value: int, endian: str) -> str:
    raw = value.to_bytes(4, "big" if endian == ">" else "little", signed=False)
    if endian == "<":
        raw = raw[::-1]
    return raw.decode("latin1", errors="replace")


def parse_cas(chunks_dir: Path) -> dict[int, int]:
    """Map one-based cast member IDs to CASt resource IDs."""
    paths = sorted(chunks_dir.glob("CAS_-*.bin"), key=lambda path: path.name.upper())
    if not paths:
        return {}
    data = _read_bytes(paths[0])
    if data is None:
        return {}
    if len(data) % 4:
        _warning(f"truncated CAS resource {paths[0]}")
    return {
        member_id: _u32(data, offset)
        for member_id, offset in enumerate(range(0, len(data) - 3, 4), start=1)
        if _u32(data, offset) > 0
    }


def parse_key(chunks_dir: Path) -> dict[int, int]:
    """Map CASt resource IDs to their SCVW child resource IDs."""
    paths = sorted(chunks_dir.glob("KEY_-*.bin"), key=lambda path: path.name.upper())
    if not paths:
        return {}
    data = _read_bytes(paths[0])
    if data is None:
        return {}
    if len(data) < 12:
        _warning(f"short KEY resource {paths[0]}")
        return {}

    candidates: list[tuple[str, int, int, int]] = []
    for endian in (">", "<"):
        property_size = _u16(data, 0, endian)
        key_size = _u16(data, 2, endian)
        used_count = _u32(data, 8, endian)
        if 0 < property_size <= 64 and 12 <= key_size <= 64 and used_count > 0:
            candidates.append((endian, property_size, key_size, used_count))
    if not candidates:
        _warning(f"unrecognized KEY layout {paths[0]}")
        return {}

    endian, property_size, key_size, used_count = candidates[0]
    loops: dict[int, int] = {}
    for index in range(used_count):
        offset = property_size + index * key_size
        if offset + 12 > len(data):
            _warning(f"truncated KEY entry {index} in {paths[0]}")
            break
        owned_id = _u32(data, offset, endian)
        owner_id = _u32(data, offset + 4, endian)
        tag = _chunk_tag(_u32(data, offset + 8, endian), endian)
        if tag == "SCVW" and owned_id > 0 and owner_id > 0:
            loops.setdefault(owner_id, owned_id)
    return loops


def parse_ccl(chunks_dir: Path) -> list[str]:
    """The external cast paths a film loop's sprite records index into, in order.

        <u32 4> <u16 count> then count+1 u32 offsets, then length-prefixed paths

    The offsets are relative to a base a couple of bytes past the end of the
    table, and which couple varies with the dump, so the base is chosen as the one
    that makes every entry a length-prefixed printable string. An empty list means
    the loops here reference nothing outside their own cast, which is what the 9
    cast-only exports carry; a file with no `ccl ` at all says the same.
    """
    paths = sorted(chunks_dir.glob("ccl -*.bin"), key=lambda path: path.name.upper())
    if not paths:
        return []
    data = _read_bytes(paths[0])
    if data is None or len(data) < 10:
        return []
    count = _u16(data, 4)
    if count == 0 or count > MAX_CCL_ENTRIES:
        if count > MAX_CCL_ENTRIES:
            _warning(f"implausible ccl entry count {count} in {paths[0]}")
        return []
    table_end = 6 + 4 * (count + 1)
    if table_end + 2 > len(data):
        _warning(f"truncated ccl offset table in {paths[0]}")
        return []
    offsets = [_u32(data, 6 + 4 * index) for index in range(count + 1)]
    if offsets[0] != 0 or offsets != sorted(offsets):
        _warning(f"unrecognized ccl offset table in {paths[0]}")
        return []
    for base in (table_end + 2, table_end, table_end + 1, table_end + 3):
        entries: list[str] = []
        for offset in offsets[:count]:
            start = base + offset
            if start >= len(data):
                break
            end = start + 1 + data[start]
            if end > len(data):
                break
            text = data[start + 1 : end]
            if any(byte < 32 or byte > 126 for byte in text):
                break
            entries.append(text.decode("latin1"))
        if len(entries) == count:
            return entries
    _warning(f"cannot read ccl paths in {paths[0]}")
    return []


def parse_film_cast(path: Path) -> dict | None:
    """Read a Director 4+ type-2 CASt film-loop definition."""
    data = _read_bytes(path)
    if data is None:
        return None
    if len(data) < 26:
        _warning(f"short CASt resource {path}")
        return None
    if _u32(data, 0) != 2:
        return None
    info_len = _u32(data, 4)
    specific_len = _u32(data, 8)
    start = 12 + info_len
    end = start + specific_len
    if specific_len < 14 or end > len(data):
        _warning(f"malformed film-loop CASt resource {path}")
        return None
    spec = data[start:end]
    top, left, bottom, right = (_i16(spec, offset) for offset in range(0, 8, 2))
    width = right - left
    height = bottom - top
    if width <= 0 or height <= 0:
        _warning(f"invalid film-loop rectangle in {path}")
        return None
    flags = _u32(spec, 8)
    return {
        "initial_rect": {"top": top, "left": left, "bottom": bottom, "right": right},
        "width": width,
        "height": height,
        "looping": not bool(flags & 32),
    }


def _frame_sprites(buffer: bytearray, external_casts: list[str]) -> tuple[list[dict], int]:
    """One frame's children, plus how many were dropped as unresolvable.

    A child naming a cast this file's `ccl ` cannot resolve is dropped rather than
    left to fall back on the cast that owns the loop: that fallback is the bug this
    reading fixes, and it draws a wrong member rather than nothing.
    """
    sprites: list[dict] = []
    dropped = 0
    for index in range(MAX_D7_SPRITE_CHANNELS):
        base = MAIN_CHANNEL_SIZE + index * SPRITE_CHANNEL_SIZE
        cast_id = _u16(buffer, base + 6)
        width = _i16(buffer, base + 18)
        height = _i16(buffer, base + 16)
        if cast_id <= 0 or width <= 0 or height <= 0:
            continue
        cast_index = _u16(buffer, base + 4)
        cast_name = ""
        if cast_index != OWN_CAST:
            if cast_index >= len(external_casts):
                dropped += 1
                continue
            cast_name = external_casts[cast_index]
            if not cast_name:
                dropped += 1
                continue
        sprite = {
            "channel": index + 1,
            "cast_id": cast_id,
            "start_x": _i16(buffer, base + 14),
            "start_y": _i16(buffer, base + 12),
            "width": width,
            "height": height,
            "ink": buffer[base + 1] & 0x3F,
        }
        if cast_name:
            sprite["cast"] = cast_name
        sprites.append(sprite)
    return sprites, dropped


def parse_scvw(
    path: Path, external_casts: list[str] | None = None
) -> tuple[list[dict], int] | None:
    """Parse a Director 7 SCVW mini-score into persistent sprite frames.

    Returns the frames and how many children were dropped for naming a cast the
    `ccl ` chunk could not resolve.
    """
    casts = external_casts or []
    dropped_children = 0
    data = _read_bytes(path)
    if data is None:
        return None
    if len(data) < 24 or _i32(data, 4) != -3:
        _warning(f"unrecognized SCVW resource {path}")
        return None
    list_start = _u32(data, 8)
    if list_start + 16 > len(data):
        _warning(f"malformed SCVW list header {path}")
        return None
    list_size = _u32(data, list_start + 4)
    max_data_len = _u32(data, list_start + 8)
    if max_data_len > MAX_D7_CHANNEL_DATA:
        _warning(f"SCVW channel data exceeds D7 limit in {path}")
        return None
    index_start = list_start + 12
    frame_data_offset = index_start + list_size * 4
    if list_size == 0 or index_start + 4 > len(data) or frame_data_offset > len(data):
        _warning(f"malformed SCVW index {path}")
        return None
    header = frame_data_offset + _u32(data, index_start)
    if header + 18 > len(data):
        _warning(f"missing SCVW score header {path}")
        return None
    inner_stream_size = _u32(data, header)
    frame1_offset = _u32(data, header + 4)
    first_frame = header + frame1_offset
    if first_frame > len(data):
        _warning(f"invalid SCVW first frame offset {path}")
        return None

    # Preserve the established D7 capacity with one trailing record for a
    # boundary delta, without trusting an unbounded resource declaration.
    buffer = bytearray(MAX_D7_CHANNEL_DATA + SPRITE_CHANNEL_SIZE)
    frames: list[dict] = []
    position = first_frame
    while position + 2 <= len(data) and position - frame_data_offset < inner_stream_size:
        frame_size = _u16(data, position)
        position += 2
        if frame_size == 0:
            break
        remaining = frame_size - 2
        if remaining < 0 or position + remaining > len(data):
            _warning(f"truncated SCVW frame in {path}")
            return None
        while remaining:
            if remaining < 4 or position + 4 > len(data):
                _warning(f"truncated SCVW channel delta in {path}")
                return None
            channel_size = _u16(data, position)
            channel_offset = _u16(data, position + 2)
            position += 4
            remaining -= 4
            if channel_size > remaining or position + channel_size > len(data):
                _warning(f"invalid SCVW channel delta in {path}")
                return None
            end = channel_offset + channel_size
            if end > len(buffer):
                _warning(f"SCVW channel delta exceeds buffer in {path}")
                return None
            buffer[channel_offset:end] = data[position : position + channel_size]
            position += channel_size
            remaining -= channel_size
        sprites, dropped = _frame_sprites(buffer, casts)
        dropped_children += dropped
        frames.append({"sprites": sprites})
    return (frames, dropped_children) if frames else None


def extract_film_loops(
    chunks_dir: Path, resolve_cast=None
) -> tuple[dict[str, dict], int]:
    """Return stable cast-ID keyed film-loop records for one canonical cast.

    `resolve_cast` turns one of the `ccl ` chunk's Director paths into the name the
    cast is registered under, or "" when nothing answers to it. Without it every
    child is read as belonging to the cast that owns the loop, which is only true
    of the loops whose children carry `0xFFFF`.
    """
    cas = parse_cas(chunks_dir)
    key = parse_key(chunks_dir)
    external = [
        resolve_cast(path) if resolve_cast is not None else ""
        for path in parse_ccl(chunks_dir)
    ]
    loops: dict[str, dict] = {}
    dropped_children = 0
    for cast_id, cast_resource_id in sorted(cas.items()):
        scvw_id = key.get(cast_resource_id)
        if scvw_id is None:
            continue
        cast = parse_film_cast(chunks_dir / f"CASt-{cast_resource_id}.bin")
        if cast is None:
            continue
        parsed = parse_scvw(chunks_dir / f"SCVW-{scvw_id}.bin", external)
        if parsed is None:
            continue
        frames, dropped = parsed
        dropped_children += dropped
        loops[str(cast_id)] = {"cast_id": cast_id, **cast, "frames": frames}
    return loops, dropped_children
