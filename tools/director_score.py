#!/usr/bin/env python3
"""Read a Director 7 score chunk into per-frame sprite channel records.

The score is stored as deltas, not as frames: each frame carries only the byte
ranges that changed since the previous one, applied to a channel buffer that
persists across the whole movie. So a sprite that sits still for 800 frames is
written once, and reading frame 900 means replaying every delta up to it.

    <u32 ?> <i32 -3> <u32 list offset> ...
    at list offset:  <u32 ?> <u32 entry count> <u32 max channel data> ...
                     then `count` u32 offsets, then the frame stream
    frame:           <u16 total size> then (<u16 size> <u16 buffer offset> bytes)*

Channel buffer layout is 288 bytes of main channels — tempo, palette, transition
and the sound and script channels — then 48 bytes per sprite channel. Within a
sprite record:

    0     sprite type (16 for a bitmap; every sprite in this game is one)
    1     ink and flags: ink in the low 6 bits, 0x40 trails, 0x80 STRETCH
    2, 3  fore and back colour
    4-7   cast library and member number, u16 each (0xFFFF means the movie's own)
    12-15 locV then locH: the registration point's position on the stage
    16-19 height then width: the sprite's rect, which is only what gets drawn
          when the stretch flag is set

`tools/director_film_loops.py` walks the same bytes for a film loop's own
mini-score and predates this module.
"""

from __future__ import annotations

import struct
from pathlib import Path

MAIN_CHANNEL_SIZE = 288
SPRITE_CHANNEL_SIZE = 48
MAX_SPRITE_CHANNELS = 200
MAX_CHANNEL_DATA = MAIN_CHANNEL_SIZE + SPRITE_CHANNEL_SIZE * MAX_SPRITE_CHANNELS

## Bit 0x80 of the ink byte. Clear means Director draws the member at its own
## size and the rect in the score is authoring residue; see bugs.md 14.
STRETCH_FLAG = 0x80
INK_MASK = 0x3F
## castLib 0xFFFF in the score means "this movie's own cast", which the upstream
## exporter records as library 1.
OWN_CAST_LIB = 0xFFFF


class ScoreError(Exception):
    """The chunk is not a score this reader understands."""


def frame_buffers(path: Path) -> list[bytes]:
    """Replay the delta stream into one channel buffer snapshot per frame."""
    data = path.read_bytes()
    if len(data) < 24 or struct.unpack_from(">i", data, 4)[0] != -3:
        raise ScoreError(f"{path.name}: not a D7 score chunk")

    list_start = struct.unpack_from(">I", data, 8)[0]
    if list_start + 16 > len(data):
        raise ScoreError(f"{path.name}: score list header past end of chunk")
    list_size = struct.unpack_from(">I", data, list_start + 4)[0]
    # The u32 at list_start + 8 is *not* the per-frame channel data size a film
    # loop's mini-score puts there: ALLIN reports 645,980 against a D7 limit of
    # 9,888, and 61 of the 69 movies would be refused on it. The bound that does
    # hold is the buffer itself — a delta landing past the last sprite channel
    # raises below rather than being clamped or wrapped.
    index_start = list_start + 12
    frame_data_offset = index_start + list_size * 4
    if list_size == 0 or frame_data_offset > len(data):
        raise ScoreError(f"{path.name}: malformed score index")
    header = frame_data_offset + struct.unpack_from(">I", data, index_start)[0]
    if header + 18 > len(data):
        raise ScoreError(f"{path.name}: missing score header")
    stream_size = struct.unpack_from(">I", data, header)[0]
    position = header + struct.unpack_from(">I", data, header + 4)[0]
    if position > len(data):
        raise ScoreError(f"{path.name}: invalid first frame offset")

    buffer = bytearray(MAX_CHANNEL_DATA + SPRITE_CHANNEL_SIZE)
    frames: list[bytes] = []
    while position + 2 <= len(data) and position - frame_data_offset < stream_size:
        frame_size = struct.unpack_from(">H", data, position)[0]
        position += 2
        if frame_size == 0:
            break
        remaining = frame_size - 2
        while remaining > 0:
            if remaining < 4 or position + 4 > len(data):
                raise ScoreError(f"{path.name}: truncated channel delta")
            size, offset = struct.unpack_from(">HH", data, position)
            position += 4
            remaining -= 4
            if size > remaining or position + size > len(data):
                raise ScoreError(f"{path.name}: invalid channel delta")
            if offset + size > len(buffer):
                raise ScoreError(f"{path.name}: channel delta exceeds the buffer")
            buffer[offset : offset + size] = data[position : position + size]
            position += size
            remaining -= size
        frames.append(bytes(buffer))
    if not frames:
        raise ScoreError(f"{path.name}: score carries no frames")
    return frames


def sprite_records(buffer: bytes) -> list[dict]:
    """Every occupied sprite channel in one frame's buffer, low channel first."""
    out: list[dict] = []
    for index in range(MAX_SPRITE_CHANNELS):
        base = MAIN_CHANNEL_SIZE + index * SPRITE_CHANNEL_SIZE
        cast_lib, cast_id = struct.unpack_from(">HH", buffer, base + 4)
        height, width = struct.unpack_from(">hh", buffer, base + 16)
        if cast_id <= 0 or width <= 0 or height <= 0:
            continue
        loc_v, loc_h = struct.unpack_from(">hh", buffer, base + 12)
        ink_and_flags = buffer[base + 1]
        out.append(
            {
                "channel": index + 1,
                "cast_lib": 1 if cast_lib == OWN_CAST_LIB else cast_lib,
                "cast_id": cast_id,
                "width": width,
                "height": height,
                "loc_h": loc_h,
                "loc_v": loc_v,
                "ink": ink_and_flags & INK_MASK,
                "stretch": bool(ink_and_flags & STRETCH_FLAG),
            }
        )
    return out
