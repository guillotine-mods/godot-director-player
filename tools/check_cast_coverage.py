#!/usr/bin/env python3
"""Report linked cast members the game references but cannot resolve.

A sprite whose cast member resolves to neither a bitmap nor a film loop draws
nothing at all, which in play looks like a character simply missing from a room.
Run this after regenerating the cast registry to confirm the gaps closed:

    python3 tools/generate_cast_registry.py --chunks-root <decompiled_chunks>
    python3 tools/check_cast_coverage.py

Exit status is 1 while anything is still unresolvable, so this can gate a build.
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def read_object(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"warning: cannot read {path}: {error}")
        return {}
    return value if isinstance(value, dict) else {}


def norm(value: object) -> str:
    return value.strip().lower() if isinstance(value, str) else ""


def referenced_ids(model_root: Path) -> dict[str, set[int]]:
    """Cast ids each linked library is asked for, across every playable movie."""
    wanted: dict[str, set[int]] = defaultdict(set)
    for frames_path in sorted(model_root.glob("*/frames.json")):
        frames_json = read_object(frames_path)
        frames = frames_json.get("frames")
        if not isinstance(frames, list) or not frames:
            continue
        libraries = {}
        for library_id, library in (frames_json.get("cast_libs") or {}).items():
            if isinstance(library, dict):
                libraries[int(library_id)] = norm(library.get("name"))
        for frame in frames:
            for sprite in frame.get("sprites", []) if isinstance(frame, dict) else []:
                if not isinstance(sprite, dict):
                    continue
                name = libraries.get(int(sprite.get("cast_lib", 1)), "")
                if name and name != "internal":
                    wanted[name].add(int(sprite.get("cast_id", 0)))
    return wanted


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", type=Path, default=Path("assets/render_model"))
    parser.add_argument(
        "--registry",
        type=Path,
        default=Path("assets/render_model/cast_registry.json"),
    )
    args = parser.parse_args()

    if not args.model_root.is_dir():
        print(f"error: model root is not a directory: {args.model_root}")
        return 1
    casts = read_object(args.registry).get("casts")
    if not isinstance(casts, dict):
        print(f"error: no casts in {args.registry}")
        return 1

    wanted = referenced_ids(args.model_root)
    total = 0
    for name in sorted(wanted):
        cast = casts.get(name)
        if not isinstance(cast, dict):
            print(f"{name}: no standalone export — the linked cast was never exported")
            total += len(wanted[name])
            continue
        resolved = set(cast.get("members") or {}) | set(cast.get("film_loops") or {})
        missing = sorted(i for i in wanted[name] if str(i) not in resolved)
        if not missing:
            continue
        total += len(missing)
        loops = len(cast.get("film_loops") or {})
        print(
            f"{name}: {len(missing)} unresolvable of {len(wanted[name])} referenced "
            f"(bitmaps {len(cast.get('members') or {})}, film loops {loops})"
        )
        print(f"    {missing}")

    if total == 0:
        print("every referenced linked cast member resolves")
        return 0
    print(f"\n{total} referenced cast ids resolve to neither a bitmap nor a film loop.")
    print("Regenerate with the chunk dumps available:")
    print("    python3 tools/generate_cast_registry.py --chunks-root <decompiled_chunks>")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
