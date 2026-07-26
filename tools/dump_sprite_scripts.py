#!/usr/bin/env python3
"""Recover which Lingo script is attached to which sprite, from the Director score.

The score does store it. The sprite records do not, and neither does `KEY_`, but
`VWSC` carries a list of **frame intervals** after the frame-delta stream, and
each interval names its behaviour script.

Score layout, verified against `assets/render_model/DAY1/frames.json`:

    0    int32  total length
    4    int32  -3
    8    int32  12
    12   int32  entryCount
    16   int32  entryCount + 1
    20   int32  sum of entry sizes
    24   int32[entryCount + 1]  entry offsets
    then the entry data

Entry 0 is the delta-compressed frame stream: a 20-byte header (length, header
length, frame count, then int16 version, sprite record size, channel count,
channels displayed) followed by one record per frame. A frame record is a uint16
byte length, then `(uint16 length, uint16 offset, bytes data)` triples applied to
a persistent channel buffer. Sprite channel N lives at buffer offset
`48 * (N + 5)`, after the six reserved score channels.

Entries 2 and up are the frame intervals, in pairs:

    primary   >= 44 bytes: int32 startFrame, endFrame, unk, unk, spriteNumber
    secondary    8 bytes:  int16 scriptCastLib, scriptMemberNum, unk, unk

`spriteNumber` carries the same +5 offset as the frame buffer, so the real
channel is `spriteNumber - 5`. The secondary's member number is a **cast member
number**, which is exactly how ProjectorRays names its output: a script file is
named after the member that owns it. Cross-checked two ways:

  * DAY1's cast has 100 script members plus 12 non-script members carrying a
    non-zero `scriptId` in their `CASt` info block (int32 index 4), and those 112
    member numbers are precisely the 112 `.ls` filenames ProjectorRays produced.
    Four of the twelve are `1:217`, `1:218`, `1:219` and `1:235`, which
    `data/movie_context.json` independently documents as Gondolin's corpse, her
    handbag, the lipstick and the third clue: the clickable hotspots of DAY1
    shore3.
  * MASTER's cast has 36 script members plus 4 non-script members with a
    `scriptId` (57, 59, 69, 77), and its dump has exactly 40 `.ls` files. Those
    four are `invright`, `invleft`, `jokebtl` and `shell` — button bitmaps whose
    script runs when the bitmap is clicked.

So there are three ways a script is reached, and all three are now resolvable:
sprite behaviours from the intervals here, cast member scripts from the displayed
member's `scriptId`, and frame scripts from the `frame_script` field the export
already carries (a member number: DAY1's 207 is the dynamic room redirect).

    python3 tools/dump_sprite_scripts.py            # report + validate
    python3 tools/dump_sprite_scripts.py --emit     # write data/lingo/<MOVIE>/sprite_scripts.json
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import struct
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT_ROOT = REPO / "data" / "lingo"
MODEL_ROOT = REPO / "assets" / "render_model"
DUMP_ROOTS = [
    Path(os.path.expanduser(
        "~/Downloads/piposh2extracted/piposh2-projectorrays/PIP2DATA")),
    Path(os.path.expanduser(
        "~/Downloads/piposh2extracted/piposh2-projectorrays")),
]

# Sprite channel N is at frame-buffer offset 48 * (N + CHANNEL_BIAS), and
# interval sprite numbers carry the same bias. The six reserved score channels
# (tempo, palette, transition, two sounds, script) sit below it.
CHANNEL_BIAS = 5

# The ten inventory drop behaviours, from
# reference/lingo/MASTER/External/BehaviorScript *.ls. Used as the validation
# oracle: these must land on the slot channels.
DROP_BEHAVIOURS = {52, 93, 94, 97, 108, 110, 111, 128, 129, 135}
SLOT_CHANNELS = range(103, 111)


def find_vwsc(movie: str) -> Path | None:
    for root in DUMP_ROOTS:
        for pattern in (f"{movie}/{movie}/chunks/VWSC-*.bin",
                        f"{movie}/chunks/VWSC-*.bin"):
            hits = sorted(glob.glob(str(root / pattern)))
            if hits:
                return Path(hits[0])
    return None


def read_score(path: Path) -> dict:
    data = path.read_bytes()
    total, unk1, unk2, count, count1, size_sum = struct.unpack(">6i", data[:24])
    offsets = struct.unpack(">%di" % count1, data[24:24 + 4 * count1])
    base = 24 + 4 * count1
    return {"data": data, "count": count, "offsets": offsets, "base": base}


def entry(score: dict, index: int) -> bytes:
    base, offsets = score["base"], score["offsets"]
    return score["data"][base + offsets[index]: base + offsets[index + 1]]


def frame_channel_members(score: dict) -> list[dict]:
    """Replay the delta stream; return per-frame {channel: (castLib, memberNum)}."""
    stream = entry(score, 0)
    _, header_len, frame_count = struct.unpack(">3i", stream[:12])
    version, rec_size, channels, shown = struct.unpack(">4h", stream[12:20])
    buf = bytearray(rec_size * (channels + CHANNEL_BIAS + 2))
    pos = header_len
    frames = []
    while pos < len(stream):
        (frame_len,) = struct.unpack_from(">H", stream, pos)
        if frame_len == 0:
            break
        end = pos + frame_len
        cursor = pos + 2
        while cursor < end:
            length, offset = struct.unpack_from(">HH", stream, cursor)
            cursor += 4
            buf[offset:offset + length] = stream[cursor:cursor + length]
            cursor += length
        snapshot = {}
        for channel in range(1, shown + 1):
            off = rec_size * (channel + CHANNEL_BIAS)
            record = buf[off:off + rec_size]
            if not any(record):
                continue
            lib, member = struct.unpack_from(">HH", record, 4)
            snapshot[channel] = (lib, member)
        frames.append(snapshot)
        pos = end
    return frames


def read_intervals(score: dict) -> list[dict]:
    out: list[dict] = []
    pending: dict | None = None
    for index in range(score["count"]):
        chunk = entry(score, index)
        if len(chunk) >= 44:
            start, stop, _, _, sprite = struct.unpack(">5i", chunk[:20])
            pending = {"channel": sprite - CHANNEL_BIAS,
                       "start": start, "end": stop, "script": None}
            out.append(pending)
        elif len(chunk) == 8 and pending is not None:
            lib, member, _, _ = struct.unpack(">4h", chunk)
            if lib > 0 and member > 0:
                pending["script"] = [lib, member]
            pending = None
    return [iv for iv in out if iv["script"]]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", action="store_true")
    args = ap.parse_args()

    movies = sorted(p.name for p in MODEL_ROOT.iterdir() if p.is_dir())
    rows = []
    totals = Counter()
    validation = defaultdict(set)
    for movie in movies:
        vwsc = find_vwsc(movie)
        if vwsc is None:
            totals["no_dump"] += 1
            continue
        score = read_score(vwsc)
        intervals = read_intervals(score)
        if not intervals:
            rows.append((movie, 0, 0, 0))
            continue
        channels = {iv["channel"] for iv in intervals}
        scripts = {tuple(iv["script"]) for iv in intervals}
        rows.append((movie, len(intervals), len(channels), len(scripts)))
        totals["intervals"] += len(intervals)
        totals["movies"] += 1
        for iv in intervals:
            if iv["channel"] in SLOT_CHANNELS:
                validation[movie].add(tuple(iv["script"]))
        if args.emit:
            out_dir = OUT_ROOT / movie
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / "sprite_scripts.json").write_text(
                json.dumps({"movie": movie,
                            "channel_bias": CHANNEL_BIAS,
                            "intervals": intervals},
                           separators=(",", ":")),
                encoding="utf-8")

    print(f"{'movie':10}{'intervals':>10}{'channels':>10}{'scripts':>9}")
    for row in sorted(rows, key=lambda r: -r[1]):
        if row[1]:
            print(f"{row[0]:10}{row[1]:>10}{row[2]:>10}{row[3]:>9}")
    print(f"\n{totals['intervals']} script-bearing intervals across "
          f"{totals['movies']} movies ({totals['no_dump']} movies have no dump)")

    print("\nvalidation: scripts attached to slot channels 103-110")
    ok = True
    for movie in ["DAY1", "NIGHT1", "HOTEL1", "SEA1", "AIR1"]:
        found = validation.get(movie, set())
        master = sorted(m for lib, m in found if m in DROP_BEHAVIOURS)
        others = sorted((lib, m) for lib, m in found if m not in DROP_BEHAVIOURS)
        mark = "OK  " if master else "MISS"
        if not master:
            ok = False
        print(f"  {mark} {movie:8} known drop behaviours: {master}  other: {others}")
    print("\nexpected drop behaviours:", sorted(DROP_BEHAVIOURS))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
