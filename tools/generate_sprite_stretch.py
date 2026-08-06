#!/usr/bin/env python3
"""Recover the sprite stretch flag the upstream exporter drops.

A Director sprite draws its member at the member's own size unless the sprite is
stretched, and the score's stored width and height only mean anything in the
stretched case. The exporter masks the score's ink byte to its low 6 bits, which
throws away bit 0x80 — the stretch flag — and then writes the stored rect into
`frames.json` unconditionally. The port drew and hit-tested that rect, so 22,806
sprite records were scaled to a rect Director would have ignored (bugs.md 14).

Rather than rewrite 187 MB of one-line `frames.json` files, the flags go in one
corpus-wide side-car, the same shape `cast_registry.json` already uses for
container-derived data the exporter did not produce. A re-export from the Windows
toolchain cannot silently undo it.

Every movie is verified before it is trusted: each frame's sprite records are
compared field by field against `frames.json`, and a movie whose score does not
reproduce the export exactly is left out of the file entirely. The port then
leaves that movie's rects alone rather than acting on an unverified reading. The
15 movies left out today all lack a score chunk in `frames.json` or a dump
directory; none is excluded for disagreeing with its container.

Usage:
    python3 tools/generate_sprite_stretch.py [--check] [--chunks PATH]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from director_score import ScoreError, frame_buffers, sprite_records

REPO = Path(__file__).resolve().parent.parent
MODEL_ROOT = REPO / "assets/render_model"
OUTPUT = MODEL_ROOT / "sprite_stretch.json"
DEFAULT_CHUNKS = Path.home() / "Projects/_private_projects/piposh2-toolcache/chunks"

## The fields the score and the export must agree on for the movie to be trusted.
## Deliberately everything the exporter reads from the same 48 bytes: agreeing on
## the member but not the rect would mean this reader is off by a field.
VERIFIED_FIELDS = ("cast_lib", "cast_id", "width", "height", "loc_h", "loc_v")


def movie_dirs() -> list[Path]:
    return sorted(p.parent for p in MODEL_ROOT.glob("*/frames.json"))


def chunk_dirs(root: Path) -> dict[str, Path]:
    """Maps a movie to its chunk directory, keyed by the *inner* directory name.

    A dump is `<root>/<outer>/<movie>/chunks`, and the two names are not always
    the same: `strtgame`'s ProjectorRays dump is filed under `STRT_CHUNKS`. The
    same keying is in `dump_movie_chunks.py`; assuming `<movie>/<movie>` here is
    what left strtgame's score unread and its stretch flags unrecovered, which
    bugs.md 14 recorded as a little-endian problem. Its score chunk was simply
    being looked for under a name nothing is filed under.
    """
    return {p.parts[-2]: p for p in root.glob("*/*/chunks")}


def verify_and_collect(movie: str, chunks: dict[str, Path]) -> tuple[dict | None, str]:
    """Returns ({score_chunk, frames}, note) for a movie whose score verifies."""
    export = json.loads((MODEL_ROOT / movie / "frames.json").read_text())
    score_chunk = export.get("score_chunk") or ""
    if not score_chunk:
        return None, "no score chunk named in frames.json"
    directory = chunks.get(movie)
    if directory is None:
        return None, "no chunk dump directory"
    path = directory / score_chunk
    if not path.exists():
        return None, f"no chunk dump for {score_chunk}"
    try:
        buffers = frame_buffers(path)
    except (ScoreError, OSError) as error:
        return None, str(error)

    exported = export.get("frames", [])
    if len(buffers) != len(exported):
        return None, f"score has {len(buffers)} frames, export has {len(exported)}"

    stretched: dict[str, list[int]] = {}
    records = 0
    for index, buffer in enumerate(buffers):
        by_channel = {
            int(sprite.get("channel", 0)): sprite
            for sprite in exported[index].get("sprites", [])
        }
        channels: list[int] = []
        for record in sprite_records(buffer):
            channel = record["channel"]
            other = by_channel.get(channel)
            if other is None:
                return None, f"frame {index} channel {channel} missing from the export"
            for field in VERIFIED_FIELDS:
                if other.get(field) != record[field]:
                    return None, (
                        f"frame {index} channel {channel} {field}: "
                        f"score {record[field]}, export {other.get(field)}"
                    )
            records += 1
            if record["stretch"]:
                channels.append(channel)
        if channels:
            stretched[str(index)] = channels
    return {"score_chunk": score_chunk, "frames": stretched}, f"{records} records"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chunks", type=Path, default=DEFAULT_CHUNKS)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the file on disk is not what this run would write",
    )
    args = parser.parse_args()

    movies: dict[str, dict] = {}
    refused: dict[str, str] = {}
    dumps = chunk_dirs(args.chunks)
    for directory in movie_dirs():
        movie = directory.name
        collected, note = verify_and_collect(movie, dumps)
        if collected is None:
            refused[movie] = note
            continue
        movies[movie] = collected

    stretched = sum(len(v) for m in movies.values() for v in m["frames"].values())
    payload = {
        "movies": movies,
        "verified_movies": len(movies),
        "refused_movies": refused,
        "stretched_sprites": stretched,
    }
    text = json.dumps(payload, indent=1, sort_keys=True) + "\n"

    print(f"{len(movies)} movies verified, {stretched} stretched sprite records")
    print(f"{len(refused)} movies refused:")
    for movie, note in sorted(refused.items()):
        print(f"  {movie:<10} {note}")

    if args.check:
        if not OUTPUT.exists():
            print(f"FAIL: {OUTPUT} does not exist")
            return 1
        if OUTPUT.read_text() != text:
            print(f"FAIL: {OUTPUT} is not what this run produces")
            return 1
        print(f"PASS: {OUTPUT} matches the containers")
        return 0

    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT.relative_to(REPO)} ({OUTPUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
