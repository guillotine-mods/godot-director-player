#!/usr/bin/env python3
"""Recover Director text members (fields) as name -> text.

Lingo reads and writes game state through fields: `field "objectsfield"` is the
inventory, `field "points"` the score, `field "Dprocess"` the per-day task list.
The text is already in the repository at `reference/chunks/<CAST>/STXT-*.bin`,
but the *names* are in the cast, so the two have to be joined:

    CAS_          int32[] of CASt resource ids, index = member number - 1
    CASt          int32 type, infoLen, specificDataLen, then the info block
                  (type 3 is a text member; the member name is a Pascal string
                  in the info block's item table)
    KEY_          (sectionID, castID, fourCC) triples linking a member to its
                  associated chunks, one of which is its STXT

Endianness varies by file: DAY1.DXR is big-endian, MASTER.CST little-endian, so
both are tried and the one producing sane four-character codes wins.

    python3 tools/dump_fields.py            # report
    python3 tools/dump_fields.py --emit     # write data/lingo/fields.json
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import struct
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CHUNK_ROOT = REPO / "reference" / "chunks"
OUT_PATH = REPO / "data" / "lingo" / "fields.json"
MEMBERS_PATH = REPO / "data" / "lingo" / "member_names.json"
DUMP_ROOT = Path(os.path.expanduser(
    "~/Downloads/piposh2extracted/piposh2-projectorrays"))

TEXT_TYPES = {3, 12}  # text, richtext
PRINTABLE = re.compile(rb"[ -~]{2,40}")


def chunk_dirs() -> dict[str, Path]:
    """cast name as used by reference/chunks -> its dumped chunks directory."""
    out: dict[str, Path] = {}
    for cast_dir in sorted(CHUNK_ROOT.iterdir()):
        if not cast_dir.is_dir():
            continue
        name = cast_dir.name
        for pattern in (f"PIP2DATA/{name}/{name}/chunks",
                        f"{name}/{name}/chunks",
                        f"PIP2DATA/{name}/chunks"):
            candidate = DUMP_ROOT / pattern
            if candidate.is_dir():
                out[name] = candidate
                break
    return out


def read_ints(data: bytes, endian: str) -> tuple[int, ...]:
    count = len(data) // 4
    return struct.unpack(f"{endian}{count}i", data[: count * 4])


def pick_endian_for_cas(data: bytes) -> str:
    for endian in (">", "<"):
        ids = read_ints(data, endian)
        if ids and sum(1 for i in ids if 0 <= i < 100000) == len(ids):
            return endian
    return ">"


def member_name(info: bytes) -> str:
    """The member name is the first short Pascal string in the info block."""
    for i in range(len(info) - 1):
        length = info[i]
        if 1 <= length <= 40 and i + 1 + length <= len(info):
            candidate = info[i + 1: i + 1 + length]
            if all(32 <= b < 127 for b in candidate):
                text = candidate.decode("latin1")
                # Names are identifier-ish; skip incidental ASCII runs.
                if re.fullmatch(r"[A-Za-z0-9_.\- ]+", text) and any(c.isalpha() for c in text):
                    return text
    return ""


def key_entries(chunks: Path) -> list[tuple[int, int, str]]:
    hits = sorted(glob.glob(str(chunks / "KEY_*.bin")))
    if not hits:
        return []
    data = Path(hits[0]).read_bytes()
    best: list[tuple[int, int, str]] = []
    for endian in (">", "<"):
        try:
            _, _, count, used = struct.unpack(f"{endian}HHII", data[:12])
        except struct.error:
            continue
        if not (0 < used <= 20000):
            continue
        entries: list[tuple[int, int, str]] = []
        for i in range(used):
            off = 12 + i * 12
            if off + 12 > len(data):
                break
            sect, cast, fcc = struct.unpack(f"{endian}iiI", data[off: off + 12])
            tag = struct.pack(">I", fcc).decode("latin1")
            if endian == "<":
                tag = tag[::-1]
            entries.append((sect, cast, tag))
        sane = sum(1 for _, _, tag in entries if re.fullmatch(r"[A-Za-z0-9_* ]{4}", tag))
        if sane > len(best):
            best = entries
    return best


def stxt_text(cast: str, resource: int) -> str | None:
    path = CHUNK_ROOT / cast / f"STXT-{resource}.bin"
    if not path.exists():
        return None
    data = path.read_bytes()
    if len(data) < 12:
        return None
    _, text_len, _ = struct.unpack(">III", data[:12])
    raw = data[12: 12 + text_len]
    return raw.decode("mac-roman", errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", action="store_true")
    args = ap.parse_args()

    fields: dict[str, dict[str, str]] = {}
    # cast -> member number -> name. Lingo goes both ways: `member(n).name` and
    # `the number of member "walkleft6"`.
    member_names: dict[str, dict[str, str]] = {}
    unnamed = 0
    for cast, chunks in chunk_dirs().items():
        cas_hits = sorted(glob.glob(str(chunks / "CAS_-*.bin")))
        if not cas_hits:
            continue
        cas = Path(cas_hits[0]).read_bytes()
        endian = pick_endian_for_cas(cas)
        ids = read_ints(cas, endian)

        # The key table's owner field is the CASt chunk's own resource id, not
        # the member number, so join on the resource.
        stxt_for_resource: dict[int, int] = {}
        for sect, owner, tag in key_entries(chunks):
            if tag.strip() == "STXT":
                stxt_for_resource[owner] = sect

        names: dict[str, str] = {}
        for number, resource in enumerate(ids, start=1):
            if resource <= 0:
                continue
            cast_path = chunks / f"CASt-{resource}.bin"
            if not cast_path.exists():
                continue
            blob = cast_path.read_bytes()
            if len(blob) < 12:
                continue
            kind, info_len, _spec = struct.unpack(">3I", blob[:12])
            if not (0 < info_len <= len(blob) - 12):
                info_len = max(0, len(blob) - 12)
            name = member_name(blob[12: 12 + info_len])
            if name:
                member_names.setdefault(cast, {})[str(number)] = name
            if kind not in TEXT_TYPES:
                continue
            resource_stxt = stxt_for_resource.get(resource)
            text = stxt_text(cast, resource_stxt) if resource_stxt else None
            if text is None:
                # Fall back to the member's own resource id, which some casts use.
                text = stxt_text(cast, resource)
            if text is None:
                continue
            if not name:
                unnamed += 1
                name = f"_unnamed_{number}"
            names[name] = text
        if names:
            fields[cast] = names

    total = sum(len(v) for v in fields.values())
    print(f"recovered {total} text members across {len(fields)} casts "
          f"({unnamed} without a usable name)")
    for cast in sorted(fields):
        keys = sorted(fields[cast])
        print(f"  {cast:10} {len(keys):3}  {keys[:8]}")

    master = fields.get("MASTER", {})
    print("\nvalidation against known contents:")
    checks = [
        ("objectsfield", lambda t: t.count("empty") >= 25, "30-odd lines of 'empty'"),
        ("points", lambda t: t.strip().isdigit(), "a numeric score"),
        ("Dprocess", lambda t: "igkey" in t.lower(), "the day-1 task list"),
    ]
    ok = True
    for name, test, why in checks:
        hit = next((k for k in master if k.lower() == name.lower()), None)
        if hit is None:
            print(f"  MISS {name}: not found ({why})")
            ok = False
            continue
        good = test(master[hit])
        print(f"  {'OK  ' if good else 'BAD '} {name}: {why}")
        ok = ok and good

    named = sum(len(v) for v in member_names.values())
    print(f"\nmember names recovered: {named} across {len(member_names)} casts")
    master_names = member_names.get("MASTER", {})
    for probe, expect in (("54", "piphead1"), ("55", "piphead2"), ("9", "object0"),
                          ("30", "sciser"), ("40", "sulam")):
        got = master_names.get(probe, "")
        print(f"  {'OK  ' if got == expect else 'BAD '} master member {probe}: "
              f"{got!r} (expected {expect!r})")

    if args.emit:
        OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUT_PATH.write_text(json.dumps(fields, separators=(",", ":")), encoding="utf-8")
        MEMBERS_PATH.write_text(json.dumps(member_names, separators=(",", ":")),
                                encoding="utf-8")
        print(f"wrote {OUT_PATH.relative_to(REPO)} and "
              f"{MEMBERS_PATH.relative_to(REPO)}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
