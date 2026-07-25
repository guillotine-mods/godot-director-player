#!/usr/bin/env python3
"""Extract Director 7 film-loop scores from decompiled cast chunks."""

from __future__ import annotations

import struct
from pathlib import Path


MAIN_CHANNEL_SIZE = 288
SPRITE_CHANNEL_SIZE = 48


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


def _frame_sprites(buffer: bytearray) -> list[dict]:
    sprites: list[dict] = []
    channels = (len(buffer) - MAIN_CHANNEL_SIZE) // SPRITE_CHANNEL_SIZE
    for index in range(channels):
        base = MAIN_CHANNEL_SIZE + index * SPRITE_CHANNEL_SIZE
        cast_id = _u16(buffer, base + 6)
        width = _i16(buffer, base + 18)
        height = _i16(buffer, base + 16)
        if cast_id <= 0 or width <= 0 or height <= 0:
            continue
        sprites.append(
            {
                "channel": index + 1,
                "cast_id": cast_id,
                "start_x": _i16(buffer, base + 14),
                "start_y": _i16(buffer, base + 12),
                "width": width,
                "height": height,
                "ink": buffer[base + 1] & 0x3F,
            }
        )
    return sprites


def parse_scvw(path: Path) -> list[dict] | None:
    """Parse a Director 7 SCVW mini-score into persistent sprite frames."""
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

    buffer = bytearray(max(max_data_len, MAIN_CHANNEL_SIZE + SPRITE_CHANNEL_SIZE * 200) + SPRITE_CHANNEL_SIZE)
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
        frames.append({"sprites": _frame_sprites(buffer)})
    return frames if frames else None


def extract_film_loops(chunks_dir: Path) -> dict[str, dict]:
    """Return stable cast-ID keyed film-loop records for one canonical cast."""
    cas = parse_cas(chunks_dir)
    key = parse_key(chunks_dir)
    loops: dict[str, dict] = {}
    for cast_id, cast_resource_id in sorted(cas.items()):
        scvw_id = key.get(cast_resource_id)
        if scvw_id is None:
            continue
        cast = parse_film_cast(chunks_dir / f"CASt-{cast_resource_id}.bin")
        if cast is None:
            continue
        frames = parse_scvw(chunks_dir / f"SCVW-{scvw_id}.bin")
        if frames is None:
            continue
        loops[str(cast_id)] = {"cast_id": cast_id, **cast, "frames": frames}
    return loops
