#!/usr/bin/env python3
"""Build the shared registry for linked Director cast libraries."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

from director_cast_types import non_drawing_members
from director_film_loops import extract_film_loops


def read_object(path: Path) -> dict:
    """Read a JSON object, reporting malformed inputs without stopping generation."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"warning: cannot read {path}: {error}")
        return {}
    if not isinstance(value, dict):
        print(f"warning: expected object in {path}")
        return {}
    return value


def norm(value: object) -> str:
    """Normalize valid cast-library names for case-insensitive lookup."""
    return value.strip().lower() if isinstance(value, str) else ""


def path_stem(value: object) -> str:
    """Return the cast file's base name, lowercased, from a Director path.

    Movies name the same linked library inconsistently: `ISHDAY1` links
    `hezi.cst` twice, once as `hezi` and once as `hezi1`, so a name-keyed lookup
    misses 59 members that are in fact exported. The path agrees where the names
    do not.
    """
    if not isinstance(value, str):
        return ""
    tail = value.strip().lower()
    for separator in (":", "\\", "/"):
        tail = tail.rsplit(separator, 1)[-1]
    for suffix in (".cst", ".cxt", ".dxr", ".dir"):
        if tail.endswith(suffix):
            return tail[: -len(suffix)]
    return tail


def internal_members(source: dict, path: Path) -> dict[str, dict]:
    """Return one complete internal member record per cast ID."""
    members: dict[str, dict] = {}
    for source_key in sorted(source):
        member = source[source_key]
        if not isinstance(member, dict):
            print(f"warning: invalid member {source_key!r} in {path}")
            continue
        try:
            cast_lib = int(member.get("cast_lib", 0))
            cast_id = int(member.get("cast_id", 0))
        except (TypeError, ValueError):
            print(f"warning: invalid cast IDs for member {source_key!r} in {path}")
            continue
        if cast_lib != 1:
            continue
        if cast_id <= 0:
            print(f"warning: invalid internal cast ID for member {source_key!r} in {path}")
            continue
        members.setdefault(str(cast_id), member)
    return {cast_id: members[cast_id] for cast_id in sorted(members, key=int)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", type=Path, default=Path("assets/render_model"))
    parser.add_argument(
        "--output", type=Path, default=Path("assets/render_model/cast_registry.json")
    )
    parser.add_argument(
        "--chunks-root",
        type=Path,
        default=Path("../Piposh2-Web-Alpha/decompiled_chunks"),
        help="Director chunk-dump root used to export film loops and member types",
    )
    args = parser.parse_args()

    if not args.model_root.is_dir():
        print(f"error: model root is not a directory: {args.model_root}")
        return 1

    linked: set[str] = set()
    aliases: dict[str, str] = {}
    directories: dict[str, Path] = {}
    for frames_path in sorted(args.model_root.glob("*/frames.json"), key=lambda path: path.parent.name.lower()):
        cast_libs = read_object(frames_path).get("cast_libs", {})
        if not isinstance(cast_libs, dict):
            print(f"warning: invalid cast_libs in {frames_path}")
            continue
        for library_id, library in cast_libs.items():
            if not isinstance(library, dict):
                print(f"warning: invalid cast library in {frames_path}")
                continue
            name = norm(library.get("name"))
            if not name:
                print(
                    "warning: invalid cast library name for "
                    f"{library_id!r} in {frames_path}: expected non-empty string"
                )
                continue
            if name != "internal":
                linked.add(name)
                stem = path_stem(library.get("path"))
                if stem and stem != name:
                    aliases.setdefault(name, stem)

    for members_path in sorted(args.model_root.glob("*/members.json"), key=lambda path: path.parent.name.lower()):
        directory_name = norm(members_path.parent.name)
        if directory_name:
            directories.setdefault(directory_name, members_path.parent)

    chunks_available = args.chunks_root.is_dir()
    if not chunks_available:
        print(f"warning: chunk dump unavailable: {args.chunks_root}")

    ## Film loops and member types come from the chunk dump, which is not in the
    ## repository. Regenerating without it must not silently drop what a previous
    ## run recovered, or the coverage check reverts to reporting members that were
    ## already accounted for.
    previous = read_object(args.output).get("casts", {}) if args.output.is_file() else {}
    if not isinstance(previous, dict):
        previous = {}

    casts: dict[str, dict] = {}
    film_loop_count = 0
    non_drawing_count = 0
    aliased: dict[str, str] = {}
    for name in sorted(linked):
        directory = directories.get(name)
        if directory is None:
            ## The cast is exported, the movie just calls it something else.
            ## Recorded as a reference rather than a copy: `hezi` is 474 members
            ## and duplicating it to model one alias would add 300 KB to a file
            ## the runtime parses at boot.
            target = aliases.get(name, "")
            if target and target in directories:
                aliased[name] = target
                continue
            print(f"warning: no standalone export for linked cast {name}")
            continue
        members_path = directory / "members.json"
        source = read_object(members_path).get("members", {})
        if not isinstance(source, dict):
            print(f"warning: invalid members in {members_path}")
            continue
        members = internal_members(source, members_path)
        if not members:
            print(f"warning: no internal members for linked cast {name} in {directory}")
            continue
        cast = {"directory": directory.name, "members": members}
        carried = previous.get(name) if isinstance(previous.get(name), dict) else {}
        chunks_dir = args.chunks_root / directory.name / directory.name / "chunks"
        if chunks_available and chunks_dir.is_dir():
            film_loops = extract_film_loops(chunks_dir)
            non_drawing = non_drawing_members(chunks_dir)
        else:
            film_loops = carried.get("film_loops") or {}
            non_drawing = carried.get("non_drawing") or {}
        if film_loops:
            cast["film_loops"] = film_loops
            film_loop_count += len(film_loops)
        if non_drawing:
            cast["non_drawing"] = non_drawing
            non_drawing_count += len(non_drawing)
        casts[name] = cast

    for name, target in sorted(aliased.items()):
        if target in casts:
            casts[name] = {"alias_of": target}
        else:
            print(f"warning: alias {name} points at missing cast {target}")

    contents = json.dumps({"casts": casts}, indent=2, sort_keys=True) + "\n"
    temporary_path: Path | None = None
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=args.output.parent,
            prefix=f".{args.output.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            temporary_file.write(contents)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, args.output)
    except OSError as error:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
        print(f"error: cannot write {args.output}: {error}")
        return 1
    print(
        f"wrote {args.output}: {len(casts)} casts ({len(aliased)} aliased), "
        f"{film_loop_count} film loops, {non_drawing_count} non-drawing members"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
