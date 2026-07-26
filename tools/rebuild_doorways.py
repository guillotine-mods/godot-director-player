#!/usr/bin/env python3
"""Rebuild per-hotspot walk targets from the exported per-label walk navs.

Original-game model: a doorway is a place. The spot Piposh walks to in room S on
his way to room D is the same spot he is standing on when he arrives in S from D.
So each undirected edge {S,D} has two points:

    doorway(S->D)  the spot in S facing D
    doorway(D->S)  the spot in D facing S

The export collapsed walk navs to one (walk_to, arrive_at) pair per destination
*label*. That surviving pair is exactly one edge's doorway pair:

    walk_to(T)   = doorway(canonical_source(T) -> room(T))
    arrive_at(T) = doorway(room(T) -> canonical_source(T))

Identify the canonical source per label, fill the doorway map from both halves,
then re-derive every hotspot's walk_to / arrive_at from it.
"""
import json, os, sys
from collections import defaultdict

ROOT = "assets/render_model"
CTX = json.load(open("data/movie_context.json"))
SHARED = CTX["transitions"].get("shared", {})


def rect_dist(rect, p):
    x, y, w, h = rect
    dx = max(x - p[0], 0, p[0] - (x + w))
    dy = max(y - p[1], 0, p[1] - (y + h))
    return (dx * dx + dy * dy) ** 0.5


def in_rect(rect, p, pad=0.0):
    x, y, w, h = rect
    return x - pad <= p[0] <= x + w + pad and y - pad <= p[1] <= y + h + pad


def room_at(markers, i):
    best, bf = "", -1
    for m in markers:
        f = int(m.get("frame", -1))
        if f <= i and f >= bf:
            bf, best = f, m.get("name", "")
    return best


def scan(mv):
    p = os.path.join(ROOT, mv, "frames.json")
    if not os.path.isfile(p):
        return None
    try:
        d = json.load(open(p))
    except Exception:
        return None
    markers = d.get("markers") or []
    names = {m.get("name", "").lower() for m in markers}
    tmap = dict(SHARED)
    tmap.update(CTX["transitions"].get(mv, {}))

    def room_id(name):
        # Matches MovieContext._room_key: rooms appear as both "shore3" and
        # "shore3go" and the runtime strips the suffix unconditionally.
        n = name.lower()
        return n[:-2] if n.endswith("go") else n

    hotspots = {}   # (room, channel, target_label) -> rect
    navs = {}       # same key -> nav
    floors = {}     # room -> rect
    pair = {}       # label -> (P_out, P_in)

    for i, f in enumerate(d.get("frames") or []):
        r = room_id(room_at(markers, i))
        for s in f.get("sprites", []):
            nav = (s.get("on_click") or {}).get("nav")
            if not isinstance(nav, dict):
                continue
            rect = (s["x"], s["y"], s["width"], s["height"])
            kind = nav.get("kind")
            if kind == "walk_here":
                floors.setdefault(r, rect)
            elif kind == "walk" and nav.get("walk_to") and nav.get("arrive_at"):
                if nav.get("target_movie"):
                    continue
                t = str(nav.get("target_label") or "").lower()
                if not t:
                    continue
                key = (r, int(s.get("channel", 0)), t)
                if key not in hotspots:
                    hotspots[key] = rect
                    navs[key] = nav
                pair[t] = ((nav["walk_to"]["x"], nav["walk_to"]["y"]),
                           (nav["arrive_at"]["x"], nav["arrive_at"]["y"]))

    def dest_room(t):
        return room_id(tmap.get(t.lower(), t.lower()))

    return dict(mv=mv, hotspots=hotspots, navs=navs, floors=floors,
                pair=pair, dest_room=dest_room, names=names)


def canonical_sources(m):
    """label -> the room whose hotspot supplied that label's exported pair."""
    by_target = defaultdict(list)
    for (room, ch, t), rect in m["hotspots"].items():
        by_target[t].append((room, ch, rect))

    canon, why = {}, {}
    for t, (p_out, _p_in) in m["pair"].items():
        cands = by_target.get(t, [])
        rooms = {r for r, _, _ in cands}
        if len(rooms) == 1:
            canon[t] = cands[0][0]
            why[t] = "only source"
            continue
        # Score each candidate room: the exported walk_to is a spot in that room,
        # so it must sit on that room's floor, and it is near (usually just below)
        # the hotspot you click to use it.
        scored = []
        for room, ch, rect in cands:
            floor = m["floors"].get(room)
            off_floor = 0 if (floor is None or in_rect(floor, p_out, 40.0)) else 1
            scored.append((rect_dist(rect, p_out), off_floor, room))
        scored.sort()
        if not scored:
            continue
        best = scored[0]
        rivals = [s for s in scored[1:] if s[2] != best[2]]
        if rivals and rivals[0][0] - best[0] < 25.0:
            continue  # too close to call
        canon[t] = best[2]
        why[t] = "nearest rect (%.0f vs %s)" % (
            best[0], ("%.0f" % rivals[0][0]) if rivals else "-")
    return canon, why


def build(m):
    canon, why = canonical_sources(m)
    # A room pair can be joined by both a direct exit and a walking animation
    # (edge2 <-> lighthouse is reachable directly and via edge2up). Those are two
    # different doorways, so let the direct link win the slot.
    doorway = {}
    for direct_pass in (True, False):
        for t, (p_out, p_in) in m["pair"].items():
            s = canon.get(t)
            if s is None:
                continue
            dr = m["dest_room"](t)
            if dr == s or (dr == t.lower()) != direct_pass:
                continue
            doorway.setdefault((s, dr), p_out)
            doorway.setdefault((dr, s), p_in)

    repaired, kept, unresolved = {}, 0, 0
    for (room, ch, t), rect in sorted(m["hotspots"].items()):
        dr = m["dest_room"](t)
        nav = m["navs"][(room, ch, t)]
        cur = ((nav["walk_to"]["x"], nav["walk_to"]["y"]),
               (nav["arrive_at"]["x"], nav["arrive_at"]["y"]))
        # The exported walk target already sits on the hotspot you click, so this
        # hotspot is the one that supplied the pair. Leave it alone.
        if rect_dist(rect, cur[0]) <= 15.0:
            kept += 1
            continue
        w = doorway.get((room, dr))
        a = doorway.get((dr, room))
        if w is not None and rect_dist(rect, w) > rect_dist(rect, cur[0]):
            w = None  # would walk him further from the hotspot he clicked
            a = None
        if w is None and a is None:
            unresolved += 1
            continue
        new = (w or cur[0], a or cur[1])
        if new == cur:
            kept += 1
            continue
        repaired["%s|%d|%s" % (room, ch, t)] = {
            "walk_to": {"x": new[0][0], "y": new[0][1]},
            "arrive_at": {"x": new[1][0], "y": new[1][1]},
            "source": "reciprocity",
        }

    # Exits whose doorway no surviving pair can reach. Their exported walk_to
    # belongs to a hotspot on the other side of the room, so it walks Piposh
    # backwards; standing him in the exit he clicked at least faces him the
    # right way. arrive_at is left alone -- nothing here can recover it.
    for (room, ch, t), rect in sorted(m["hotspots"].items()):
        key = "%s|%d|%s" % (room, ch, t)
        if key in repaired:
            continue
        x, y, w, h = rect
        wx = m["navs"][(room, ch, t)]["walk_to"]["x"]
        if x - 100.0 <= wx <= x + w + 100.0:
            continue
        floor = m["floors"].get(room)
        if floor is None:
            continue
        # Only the height is taken from the walk_here band, to stand him on the
        # ground rather than in the sky. Its width often stops short of the exit
        # itself, so clamping x there would drag him back across the room.
        _fx, fy, _fw, fh = floor
        point = (
            int(round(x + w / 2.0)),
            int(round(min(max(y + h / 2.0, fy), fy + fh))),
        )
        exported = m["navs"][(room, ch, t)]["walk_to"]
        if rect_dist(rect, point) > rect_dist(rect, (exported["x"], exported["y"])):
            continue
        repaired[key] = {
            "walk_to": {"x": point[0], "y": point[1]},
            "source": "hotspot-centre",
        }
        unresolved -= 1
    return canon, why, doorway, repaired, kept, unresolved


def main():
    out = {}
    T = K = R = U = 0
    stats = []
    for mv in sorted(os.listdir(ROOT)):
        m = scan(mv)
        if not m or not m["hotspots"]:
            continue
        canon, why, doorway, repaired, kept, unresolved = build(m)
        T += len(m["hotspots"]); K += kept; R += len(repaired); U += unresolved
        if repaired:
            out[mv] = repaired
        stats.append((mv, len(m["hotspots"]), len(m["pair"]), len(canon),
                      kept, len(repaired), unresolved))

    print("%-10s %5s %6s %6s %6s %8s %10s" %
          ("movie", "hots", "labels", "canon", "kept", "repaired", "unresolved"))
    for s in stats:
        if s[1] >= 4:
            print("%-10s %5d %6d %6d %6d %8d %10d" % s)
    print("-" * 56)
    print("TOTAL      %5d %6s %6s %6d %8d %10d" % (T, "", "", K, R, U))
    print("resolved: %d/%d (%.0f%%)" % (K + R, T, 100 * (K + R) / T))

    dest = sys.argv[1] if len(sys.argv) > 1 else "data/walk_doorways.json"
    doc = json.load(open(dest)) if os.path.isfile(dest) else {}
    doc["overrides"] = {mv: dict(sorted(v.items())) for mv, v in sorted(out.items())}
    with open(dest, "w") as fh:
        fh.write(json.dumps(doc, indent="\t") + "\n")
    print("\nwrote %s: %d movies, %d hotspot overrides"
          % (dest, len(out), sum(len(v) for v in out.values())))


main()
