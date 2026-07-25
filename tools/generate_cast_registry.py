#!/usr/bin/env python3
"""Build the shared registry for linked Director cast libraries."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path


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
    args = parser.parse_args()

    if not args.model_root.is_dir():
        print(f"error: model root is not a directory: {args.model_root}")
        return 1

    linked: set[str] = set()
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

    for members_path in sorted(args.model_root.glob("*/members.json"), key=lambda path: path.parent.name.lower()):
        directory_name = norm(members_path.parent.name)
        if directory_name:
            directories.setdefault(directory_name, members_path.parent)

    casts: dict[str, dict] = {}
    for name in sorted(linked):
        directory = directories.get(name)
        if directory is None:
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
        casts[name] = {"directory": directory.name, "members": members}

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
    print(f"wrote {args.output}: {len(casts)} casts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
