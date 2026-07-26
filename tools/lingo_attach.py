#!/usr/bin/env python3
"""Work out which Lingo script belongs to which sprite, per movie and frame.

Why this exists
---------------
An `on mouseUp` handler is useless until the runtime knows which sprite owns it.
The obvious source is the Director score, and that turned out to be a dead end.
Measured on DAY1's `VWSC-1827.bin` (see docs/superpowers/plans for the record):

  * The 48-byte sprite record decodes cleanly and every field cross-checks
    against `assets/render_model/DAY1/frames.json`: byte 0 spriteType, byte 1
    ink+flags, byte 2 foreColor, byte 3 backColor, u16@4 castLib, u16@6
    memberNum, i16@12 locV, i16@14 locH, u16@16 height, u16@18 width, and
    bytes 20-23 sprite flags (only 7 distinct values across the movie).
  * The field where a script reference would live, u16@8, is **zero in all
    73,220 sprite records**. u16@10 is a sprite-interval id: it holds steady
    while a sprite persists and appears as a value in score entry 1.
  * Every frame-interval entry in the score is empty (offsets 2..19535 are all
    identical), so there are no Director-6 style sprite behaviours to read.
  * `KEY_` carries no `Lscr` entries for DAY1, so no member owns a script
    through the key table either. MASTER.CST is little-endian where DAY1.DXR is
    big-endian, so a shared parser would need to handle both.

So the score does not say. What does say is the export itself: the web-era
`lingo_nav.py` already resolved attachment and left its answer behind as
per-sprite `on_click` entries in `frames.json`. This tool recovers the mapping
by matching those entries against signatures computed from the ASTs that
`lingo_compile.py` produced: navigation targets, sound files and inventory
operations. Where exactly one script matches, attachment is known. Everything
else is reported as a number rather than guessed at.

    python3 tools/lingo_attach.py              # coverage report
    python3 tools/lingo_attach.py --emit       # write data/lingo/<MOVIE>/attach.json
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LINGO_DIR = REPO / "data" / "lingo"
MODEL_DIR = REPO / "assets" / "render_model"

# Handlers that a click can reach. A script with none of these cannot be what
# an on_click came from.
CLICK_HANDLERS = {"mouseup", "mousedown", "mouseupoutside"}


def walk(node, out):
    """Yield every dict node in an AST."""
    if isinstance(node, dict):
        out.append(node)
        for value in node.values():
            walk(value, out)
    elif isinstance(node, list):
        for value in node:
            walk(value, out)


def const_str(node) -> str | None:
    if isinstance(node, dict) and node.get("node") == "str":
        return str(node["value"])
    return None


def signature_of_handler(handler: dict) -> dict:
    """Lifted signature of one handler: what the old exporter could see."""
    nodes: list[dict] = []
    walk(handler.get("body", []), nodes)
    navs: set[str] = set()
    sounds: set[str] = set()
    for node in nodes:
        if node.get("node") != "call":
            continue
        callee = node.get("callee") or {}
        name = str(callee.get("name", "")).lower() if callee.get("node") == "var" else ""
        args = node.get("args") or []
        if name in ("go", "gotoframe", "play") and args:
            literal = const_str(args[0])
            if literal:
                navs.add(literal.lower())
        if name == "sound" and args:
            # Command form: `sound playFile 1, path`. The path is a
            # concatenation, so keep only literal fragments that look like a
            # file name.
            frags: list[dict] = []
            walk(args, frags)
            for frag in frags:
                literal = const_str(frag)
                if literal and literal.lower().endswith((".aif", ".wav", ".aiff")):
                    sounds.add(Path(literal).stem.lower())
    return {"navs": navs, "sounds": sounds}


def load_scripts() -> dict[str, list[dict]]:
    """movie -> [{cast, script, handler, signature}] for click handlers."""
    per_movie: dict[str, list[dict]] = defaultdict(list)
    for bundle_path in sorted(LINGO_DIR.glob("*/*.json")):
        if bundle_path.name == "attach.json":
            continue
        bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
        movie = bundle["movie"]
        cast = bundle["cast"]
        for script_name, ast in bundle["scripts"].items():
            for handler in ast["handlers"]:
                if handler["name"].lower() not in CLICK_HANDLERS:
                    continue
                sig = signature_of_handler(handler)
                if not sig["navs"] and not sig["sounds"]:
                    continue
                per_movie[movie].append({
                    "cast": cast,
                    "script": script_name,
                    "handler": handler["name"],
                    "sig": sig,
                })
    return per_movie


def export_signature(on_click: dict) -> dict:
    navs: set[str] = set()
    nav = on_click.get("nav")
    if isinstance(nav, dict):
        for key in ("value", "label", "target_label"):
            value = nav.get(key)
            if isinstance(value, str) and value:
                navs.add(value.lower())
    sounds = set()
    for sound in on_click.get("sounds") or []:
        if isinstance(sound, dict):
            name = str(sound.get("file", ""))
            if name:
                sounds.add(Path(name).stem.lower())
    return {"navs": navs, "sounds": sounds}


def score(script_sig: dict, want: dict) -> int:
    """How well a script explains an exported on_click. 0 means not at all."""
    nav_hits = len(script_sig["navs"] & want["navs"])
    snd_hits = len(script_sig["sounds"] & want["sounds"])
    if nav_hits == 0 and snd_hits == 0:
        return 0
    # Navigation is the stronger signal: many scripts share a sound.
    return nav_hits * 10 + snd_hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", action="store_true")
    ap.add_argument("--movie", help="limit to one movie")
    args = ap.parse_args()

    scripts = load_scripts()
    if not scripts:
        print("no ASTs found; run tools/lingo_compile.py --emit first")
        return 2

    totals = Counter()
    per_movie_report = []
    for model in sorted(MODEL_DIR.iterdir()):
        if not model.is_dir():
            continue
        movie = model.name
        if args.movie and movie.upper() != args.movie.upper():
            continue
        frames_path = model / "frames.json"
        if not frames_path.exists():
            continue
        candidates = scripts.get(movie, [])
        frames = json.loads(frames_path.read_text(encoding="utf-8"))["frames"]

        attach: dict[str, dict] = {}
        exact = ambiguous = unmatched = clickables = 0
        for frame in frames:
            for sprite in frame.get("sprites", []):
                on_click = sprite.get("on_click")
                if not on_click:
                    continue
                clickables += 1
                want = export_signature(on_click)
                if not want["navs"] and not want["sounds"]:
                    unmatched += 1
                    continue
                ranked = sorted(
                    ((score(c["sig"], want), c) for c in candidates),
                    key=lambda pair: -pair[0],
                )
                ranked = [(s, c) for s, c in ranked if s > 0]
                if not ranked:
                    unmatched += 1
                    continue
                best = ranked[0][0]
                winners = [c for s, c in ranked if s == best]
                key = "%d:%d" % (frame["frame_index"], sprite["channel"])
                if len(winners) == 1:
                    exact += 1
                    attach[key] = {"cast": winners[0]["cast"],
                                   "script": winners[0]["script"],
                                   "handler": winners[0]["handler"]}
                else:
                    ambiguous += 1
                    attach[key] = {"cast": winners[0]["cast"],
                                   "script": winners[0]["script"],
                                   "handler": winners[0]["handler"],
                                   "ambiguous": len(winners)}
        totals["exact"] += exact
        totals["ambiguous"] += ambiguous
        totals["unmatched"] += unmatched
        totals["clickable"] += clickables
        if clickables:
            per_movie_report.append((movie, clickables, exact, ambiguous,
                                     unmatched, len(candidates)))
        if args.emit and attach:
            out_dir = LINGO_DIR / movie
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / "attach.json").write_text(
                json.dumps({"movie": movie, "attach": attach},
                           separators=(",", ":")),
                encoding="utf-8")

    print(f"{'movie':10}{'clickable':>10}{'exact':>8}{'ambig':>8}{'none':>8}{'cands':>7}")
    for row in sorted(per_movie_report, key=lambda r: -r[1]):
        print(f"{row[0]:10}{row[1]:>10}{row[2]:>8}{row[3]:>8}{row[4]:>8}{row[5]:>7}")
    click = totals["clickable"] or 1
    print(f"\ntotal clickable sprite-frames: {totals['clickable']}")
    print(f"  attributed to exactly one script: {totals['exact']} "
          f"({totals['exact'] * 100.0 / click:.1f}%)")
    print(f"  ambiguous (several scripts fit):  {totals['ambiguous']} "
          f"({totals['ambiguous'] * 100.0 / click:.1f}%)")
    print(f"  no candidate script:              {totals['unmatched']} "
          f"({totals['unmatched'] * 100.0 / click:.1f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
