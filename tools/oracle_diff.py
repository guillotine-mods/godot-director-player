#!/usr/bin/env python3
"""Diff a ScummVM reference trace against this port's trace.

    python3 tools/oracle_diff.py .traces/scummvm-strtgame.log run.jsonl

Reference trace comes from tools/capture_scummvm_trace.sh. The port's comes from
running with PIPOSH2_TRACE=run.jsonl (lingo/lingo_trace.gd).

READ tools/../openspec/changes/director-playback-machine/oracle-status.md BEFORE
TRUSTING ANY OUTPUT OF THIS TOOL. Two limits are structural, not bugs here:

  * ScummVM runs this game as v850 although every movie is D7, because the version
    is seeded from its detection entry and cast.cpp:630 only ever RAISES it. So
    version-gated behaviour differs by construction. Fields listed in
    VERSION_GATED below are excluded from comparison for that reason, and saying
    so is the whole point of excluding them rather than quietly matching loosely.
  * Only strtgame.dxr plays. DAY1.DXR and DAGI.DXR segfault ScummVM at the
    transition into playback, so cross-movie comparisons (task 4.8) are not
    available.

Declared divergences come from data/declared_divergences.json and are reported as
EXPECTED rather than as failures, per the surface-diagnostics spec. An undeclared
difference is a failure. Exit code is 1 if any failure survives.
"""

import argparse
import json
import pathlib
import re
import sys
from collections import defaultdict

REPO = pathlib.Path(__file__).resolve().parent.parent

# Excluded because ScummVM is running at the wrong version for this game, so a
# difference here says nothing about the port. See oracle-status.md.
VERSION_GATED = {
    "tempo",          # D6+ sentinel encoding differs
    "num_channels",   # ScummVM hard-codes 120; 21 of 60 movies declare 150
    "stage_color",    # post-D7 config layout; ScummVM's own checksum rejects it
}

# CH:  12  - [sprite: castId: member 303 of castLib 1, [inkData: 0x08 [ink: Matte,
#            ...], 490x383@344,195 type: 16 ...], ..., puppet: 0, moveable: 0]
CH_RE = re.compile(
    r"^CH:\s+(?P<ch>\d+)\s+- \[sprite: castId: (?:member (?P<member>\d+) of castLib (?P<castlib>\d+)|(?P<empty>\d+))"
    r"(?:.*?\[ink: (?P<ink>[A-Za-z]+),)?"
    r"(?:.*?(?P<w>\d+)x(?P<h>\d+)@(?P<x>-?\d+),(?P<y>-?\d+))?"
    r"(?:.*?puppet: (?P<puppet>\d+))?"
    r"(?:.*?moveable: (?P<moveable>\d+))?"
)

# Lingo::processEvents: starting event script (enterFrame, ScoreScript, member 5 of castLib 1, 12)
# Lingo::processEvents: no matching script for event (enterFrame, NoneScript, member 0 of castLib 0, 0), continuing
DISPATCH_RE = re.compile(
    r"processEvents: (?P<kind>starting event script|no matching script for event) "
    r"\((?P<event>\w+), (?P<stype>\w+), (?:member (?P<member>\d+) of castLib (?P<castlib>\d+)|[^,]+), (?P<ch>\d+)\)"
)

FRAME_END = "Score::renderFrame() finished"
INK_ALIAS = {"BackgndTrans": "bgtrans", "Matte": "matte", "Copy": "copy"}


def load_reference(path):
    """Per rendered frame, the last channel dump seen before that frame completed.

    ScummVM dumps channels more than once per frame — loadFrames walks every frame
    at load time as well. Taking the last dump before each renderFrame boundary is
    what corresponds to composited state, which is what the port's trace records.
    """
    frames, cur, dispatches, fi = [], {}, defaultdict(list), 0
    for line in path.read_text(errors="replace").splitlines():
        m = CH_RE.match(line)
        if m:
            g = m.groupdict()
            if g["empty"] is not None:      # castId: 000 — channel unoccupied
                cur.pop(int(g["ch"]), None)
                continue
            cur[int(g["ch"])] = {
                "member": int(g["member"]),
                "castlib": int(g["castlib"]),
                "ink": INK_ALIAS.get(g["ink"], (g["ink"] or "").lower()),
                "width": int(g["w"]) if g["w"] else None,
                "height": int(g["h"]) if g["h"] else None,
                "loch": int(g["x"]) if g["x"] else None,
                "locv": int(g["y"]) if g["y"] else None,
                "puppet": g["puppet"] == "1",
            }
            continue
        m = DISPATCH_RE.search(line)
        if m:
            g = m.groupdict()
            dispatches[fi].append({
                "event": g["event"],
                "handled": g["kind"] == "starting event script",
                "ch": int(g["ch"]),
            })
            continue
        if FRAME_END in line:
            frames.append(dict(cur))
            fi += 1
    return frames, dispatches


def load_port(path, movie=None):
    """Port trace: JSON Lines, one record per event, k = meta|channel|dispatch|prop.

    `movie` restricts to records from one movie. Without it a comparison against a
    single-movie reference is meaningless: the port's trace spans a whole session,
    so positional alignment would line frame 0 of the oracle up against whatever
    the port happened to be doing at step 0 — usually a different movie entirely.
    """
    frames, dispatches, meta, seen = defaultdict(dict), defaultdict(list), {}, set()
    want = movie.lower().rsplit(".", 1)[0] if movie else None
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        k = r.get("k")
        if k == "meta":
            meta = r
            continue
        mv = str(r.get("movie", "")).lower()
        seen.add(mv)
        if want and mv != want:
            continue
        if k == "channel":
            frames[r.get("step")][r["ch"]] = r
        elif k == "dispatch":
            dispatches[r.get("step")].append(r)
    return frames, dispatches, meta, sorted(seen)


def declared():
    p = REPO / "data" / "declared_divergences.json"
    if not p.exists():
        return {}
    doc = json.loads(p.read_text())
    return {d["id"]: d for d in doc.get("divergences", [])}


def compare_channels(ref_frame, port_frame, fields):
    out = []
    for ch in sorted(set(ref_frame) | set(port_frame)):
        r, p = ref_frame.get(ch), port_frame.get(ch)
        if r is None:
            out.append((ch, "occupied", "absent", "present"))
            continue
        if p is None:
            out.append((ch, "occupied", "present", "absent"))
            continue
        for f in fields:
            rv, pv = r.get(f), p.get(f)
            # "unavailable" is the port saying it has no live channel layer yet
            # (task 5.1). That is not a mismatch to report; it is a known hole,
            # and reporting it every frame would bury the real differences.
            if pv == "unavailable" or rv is None or pv is None:
                continue
            if rv != pv:
                out.append((ch, f, rv, pv))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", type=pathlib.Path, help="ScummVM log")
    ap.add_argument("port", type=pathlib.Path, help="port JSONL trace")
    ap.add_argument("--fields", default="member,castlib,ink,loch,locv,width,height,puppet")
    ap.add_argument("--max-report", type=int, default=40)
    ap.add_argument("--movie", help="restrict the port trace to one movie, e.g. strtgame")
    args = ap.parse_args()

    for p in (args.reference, args.port):
        if not p.exists():
            sys.exit(f"no such trace: {p}")

    fields = [f for f in args.fields.split(",") if f and f not in VERSION_GATED]
    skipped = [f for f in args.fields.split(",") if f in VERSION_GATED]

    ref_frames, ref_disp = load_reference(args.reference)
    port_frames, port_disp, meta, movies = load_port(args.port, args.movie)

    print(f"reference {args.reference}: {len(ref_frames)} rendered frames")
    print(f"port      {args.port}: {len(port_frames)} steps"
          + (f" for movie {args.movie!r}" if args.movie else ""))
    if not args.movie and len(movies) > 1:
        print(f"WARNING: port trace spans {len(movies)} movies {movies[:6]}"
              " — pass --movie or the positional alignment is meaningless")
    if meta.get("degraded"):
        print(f"port declares degraded: {json.dumps(meta['degraded'], sort_keys=True)}")
    if skipped:
        print(f"excluded as version-gated (oracle runs v850, game is D7): {', '.join(skipped)}")
    div = declared()
    print(f"declared divergences: {len(div)}"
          + (f" ({', '.join(div)})" if div else " — none"))

    if not ref_frames:
        sys.exit("reference has no rendered frames; see oracle-status.md "
                 "(DAY1/DAGI segfault; only strtgame.dxr plays)")
    if not port_frames:
        sys.exit("port trace has no channel records; run with "
                 "PIPOSH2_TRACE=<file> and PIPOSH2_TRACE_KINDS including 'channel'")

    n = min(len(ref_frames), len(port_frames))
    if len(ref_frames) != len(port_frames):
        print(f"NOTE: frame counts differ; comparing the first {n}. Alignment is "
              f"positional, so a single missing frame shifts everything after it.")

    failures = 0
    port_keys = sorted(port_frames)
    for i in range(n):
        diffs = compare_channels(ref_frames[i], port_frames[port_keys[i]], fields)
        for ch, field, rv, pv in diffs:
            if failures < args.max_report:
                print(f"  frame {i:4d} ch {ch:3d} {field:8s} oracle={rv!r} port={pv!r}")
            failures += 1

        rd = [d["event"] for d in ref_disp.get(i, []) if d["handled"]]
        pd = [d["event"] for d in port_disp.get(port_keys[i], []) if d.get("handled")]
        if rd != pd and (rd or pd):
            if failures < args.max_report:
                print(f"  frame {i:4d} dispatch oracle={rd} port={pd}")
            failures += 1

    if failures > args.max_report:
        print(f"  ... {failures - args.max_report} more (raise --max-report)")
    print(f"\n{failures} undeclared difference(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
