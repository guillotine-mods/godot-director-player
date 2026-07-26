#!/usr/bin/env python3
"""Fill in member names for the linked casts, from CastScript filenames.

`dump_fields.py` recovers names by parsing each CASt info block, but it only
looks at the casts under `reference/chunks/`, which is the seventeen whose text
members were committed. None of the linked casts are there, so
`member_names.json` had no `island2` at all.

That is load-bearing. MASTER's `searchfunk` identifies a searchable hotspot with

    myname = member(the memberNum of sprite the clickOn, "island2").name

and looks `myname` up in `field "searchinfo"` to find where to walk and what to
reveal. With no island2 names the lookup returned "", nothing matched, and
searching any bench, rock or patch of grass did nothing at all: no shell, no
bottle, no sound.

ProjectorRays names each decompiled script after the member that owns it, so
`CastScript 74 - edge1_bench.ls` is island2 member 74. Only CastScripts are read:
a BehaviorScript's suffix is the behaviour's name, not the member's, and trusting
those renamed master member 54 from `piphead1` to `ex_tx`.

Additive by design. An existing entry is never overwritten, so the CASt-derived
names dump_fields.py validates stay exactly as they are.

    python3 tools/add_cast_script_names.py           # report
    python3 tools/add_cast_script_names.py --emit    # update member_names.json
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LINGO_ROOT = REPO / "reference" / "lingo"
MEMBERS_PATH = REPO / "data" / "lingo" / "member_names.json"

CAST_SCRIPT = re.compile(r"^CastScript (\d+) - (.+)$")


def is_source_text(value: str) -> bool:
    """Whether a stored name is really a fragment of Lingo source.

    The CASt info-block parser returns the script body for members that carry a
    script, so master 77 came out as "  global soun" and later "on mou" instead of
    "shell". Real member names are bare tokens: `piphead1`, `object0`, `sciser`.
    Only these unmistakable cases are replaced, so a validated name is never
    touched.
    """
    if value != value.strip():
        return True
    lowered = value.lower()
    if lowered.startswith(("on ", "-- ", "--")):
        return True
    return "global" in lowered


def owning_cast(script: Path) -> str:
    ## `External` and `Internal` are ProjectorRays' own subdirectory names, so for
    ## those the cast is the directory above.
    parent = script.parent.name
    if parent.lower() in ("external", "internal"):
        return script.parent.parent.name
    return parent


def collect() -> dict[str, dict[str, str]]:
    found: dict[str, dict[str, str]] = {}
    for script in sorted(LINGO_ROOT.glob("*/*/*.ls")):
        match = CAST_SCRIPT.match(script.stem)
        if match is None:
            continue
        cast = owning_cast(script).lower()
        found.setdefault(cast, {})[match.group(1)] = match.group(2).strip()
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit", action="store_true")
    args = parser.parse_args()

    if not MEMBERS_PATH.exists():
        print(f"error: {MEMBERS_PATH} is missing; run dump_fields.py --emit first")
        return 1
    existing: dict[str, dict[str, str]] = json.loads(MEMBERS_PATH.read_text())
    lowered = {cast.lower(): cast for cast in existing}

    added = 0
    kept = 0
    repaired: list[str] = []
    new_casts: list[str] = []
    for cast, by_number in sorted(collect().items()):
        key = lowered.get(cast, cast)
        if key not in existing:
            existing[key] = {}
            new_casts.append(key)
        target = existing[key]
        for number, name in sorted(by_number.items(), key=lambda item: int(item[0])):
            current = target.get(number)
            if current is not None and not is_source_text(current):
                kept += 1
                continue
            if current is not None:
                repaired.append(f"{key} {number}: {current!r} -> {name!r}")
            target[number] = name
            added += 1

    print(f"{added} names added or repaired, {kept} existing names left alone")
    for line in repaired:
        print(f"  repaired {line}")
    print(f"casts introduced: {new_casts if new_casts else 'none'}")

    island2 = existing.get("island2") or existing.get("ISLAND2") or {}
    probe = {number: island2[number] for number in ("74", "75") if number in island2}
    print(f"island2 search-hotspot names: {probe if probe else 'MISSING'}")

    if args.emit:
        MEMBERS_PATH.write_text(json.dumps(existing, separators=(",", ":")), encoding="utf-8")
        print(f"wrote {MEMBERS_PATH}")
    else:
        print("(dry run; pass --emit to write)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
