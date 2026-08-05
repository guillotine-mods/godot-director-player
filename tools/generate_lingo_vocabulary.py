#!/usr/bin/env python3
"""Generate the Lingo vocabulary manifest the runtime's bound tables are diffed against.

Coverage of the Lingo surface has to be measured against what the language can
express, not against what the shipped scripts happen to say: a property no
script reads today is still a gap the moment a newly-migrated script reads it.
This writes that vocabulary out once, per category, so the coverage check can
compare bound-versus-enumerable instead of surveying usage.

Three sources feed it, and every name records which ones contain it:

  compiler   tools/lingo_compile.py's own tables. Only SYSTEM_PROPS exists, and
             the parser does not consult it (see the `closed` flags below).
  reference  ScummVM's `the`-entity, entity-field and builtin tables, at the
             revision tools/fetch_scummvm_reference.sh pins. This is the only
             closed vocabulary available for sprite, member and builtin names.
             Names, canonical spelling and owning entity only. Those
             transcribe Director's language and object model. The version
             column and the type tags are the reference's own determination,
             read to route a name and then discarded, never committed.
  corpus     Every name the compiler actually produces from reference/lingo/,
             with read and write counts. Bounds the other two from below.

    python3 tools/generate_lingo_vocabulary.py            # write the manifest
    python3 tools/generate_lingo_vocabulary.py --check    # fail if it is stale
    python3 tools/generate_lingo_vocabulary.py --summary  # per-category counts

The manifest enumerates the whole vocabulary, with no way to narrow it. Which
Director version this game is has not been established (three sources disagree;
OpenSpec task 2.1 settles it from the movie file), and a manifest narrowed on a
guess would let the coverage check pass on names it cannot see. There is no
version filter to defeat, and no version column to filter on: see below.

The ScummVM sources are fetched, not vendored (see .gitignore), so run
tools/fetch_scummvm_reference.sh before regenerating.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import lingo_compile as lc  # noqa: E402  - path set above

REPO = Path(__file__).resolve().parent.parent
SCUMMVM_ROOT = REPO / "reference" / "scummvm" / "lingo"
OUT_PATH = REPO / "data" / "lingo_vocabulary.json"

# Settled by OpenSpec task 2.1: the movies are Director 7. The three sources
# that looked like a conflict were describing different things, and all three
# are kept below, because "850 is the projector, not the movies" is the kind of
# fact that gets rediscovered painfully if only the winner is recorded.
#
# Nothing here filters the vocabulary. The version is recorded, not applied: a
# manifest narrowed to one version would let the coverage check pass on names
# it cannot see, which is the failure surface-diagnostics forbids. Over-report
# and let the coverage check report the gaps.
DIRECTOR_VERSION = 700
VERSION_STATUS = ("resolved by OpenSpec task 2.1; see "
                  "openspec/changes/director-playback-machine/director-version.md")
VERSION_CANDIDATES = [
    {"version": 700, "source": ".claude/skills/director-data-recovery/SKILL.md",
     "describes": "the movies, and it is correct",
     "detail": "Confirmed: every file the game plays reports config version "
               "0x57E at DRCF payload offset 36, which humanVersion() maps to "
               "700, and carries a VERS chunk of 7.0."},
    {"version": 850, "source": "reference/scummvm/detection_tables.h",
     "describes": "the projector, not the movies",
     "detail": "Correct about what it fingerprints - the executable. Two "
               "genuine D8.5 files ship at the install root; they are outside "
               "the movie set under PIP2DATA/."},
    {"version": None, "source": "assets/render_model/*/summary.json",
     "describes": "the score format, and it agrees with 700",
     "detail": "frames_version 13 with sprite_record_size 48 is what a D7 "
               "movie writes: 48 is kSprChannelSizeD7, and ScummVM dispatches "
               "sprite layout on the config version, never on framesVersion. "
               "Never evidence of an older score format."},
]

CATEGORIES = ("sprite", "movie", "member", "builtin")

# ScummVM entity tags, mapped onto this port's four categories. kTheCastLib and
# kTheChunk have no counterpart in the compiler's AST, so they are dropped
# rather than folded into a category whose bound table could never serve them.
ENTITY_CATEGORY = {
    "kTheSprite": "sprite",
    "kTheCast": "member",
    "kTheField": "member",
}

# AST node kinds that name a property, and the category the interpreter routes
# each one to (see lingo/lingo_interpreter.gd's assign and eval switches).
NODE_CATEGORY = {
    "sprite_prop": "sprite",
    "member_prop": "member",
    "field_prop": "member",
    "prop": "movie",
}

# `sprite(15).visible` and `member("x").text` are the dot spelling of the same
# properties. The game reaches for these far more often than for `the X of Y`,
# so a walk that only counted the `the` forms would under-report every category.
DOT_OWNER_CATEGORY = {
    "sprite_ref": "sprite",
    "member_ref": "member",
}

# Words the language reserves. One reaching a callee position means the parser
# mis-split a command-form statement, not that the corpus calls a builtin.
ARTEFACTS = {word.lower() for word in lc.KEYWORDS | lc.RESERVED_AFTER_PROP}


# ---------------------------------------------------------------- reference


def scummvm_revision() -> str:
    path = SCUMMVM_ROOT.parent / "REVISION"
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def read_reference(name: str) -> str:
    path = SCUMMVM_ROOT / name
    if not path.exists():
        raise SystemExit(
            f"missing {path.relative_to(REPO)} - run tools/fetch_scummvm_reference.sh"
        )
    return path.read_text(encoding="utf-8", errors="replace")


def table_body(src: str, opener: str) -> str:
    """The text between `opener` and the `};` that closes it."""
    start = src.index(opener) + len(opener)
    return src[start:src.index("\n};", start)]


ENTITY_RE = re.compile(
    r'\{\s*kThe(\w+),\s*"([^"]+)",\s*(true|false),\s*(\d+),\s*(true|false)\s*\}')
FIELD_RE = re.compile(r'\{\s*(kThe\w+),\s*"([^"]+)",\s*kThe\w+,\s*(\d+)\s*\}')
BUILTIN_RE = re.compile(
    r'\{\s*"([^"]+)",\s*LB::\w+,\s*(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\w+)\s*\}')


def reference_names() -> tuple[dict[str, dict[str, dict]], dict[str, list[str]]]:
    """Per category, the reference's names keyed by their lowercased spelling.

    Only names, their canonical spelling and the entity each property belongs
    to are taken. Which Director release introduced a name, and the builtin and
    property type tags, are the reference's own determination and are read to
    route a name here and then discarded, never committed.

    Also returns the property names of the Lingo entities this port has no
    category for, still grouped by entity. The host binds four window
    properties, and "a window property we do not model" is a far more useful
    gap report than "a name outside our four categories".
    """
    out: dict[str, dict[str, dict]] = {c: {} for c in CATEGORIES}
    other_entity: dict[str, set[str]] = defaultdict(set)

    the_src = read_reference("lingo-the.cpp")

    # `the <prop>` with no `of` clause: the movie-level vocabulary. Entities
    # that take an id (`hasId`) are targets such as `sprite`, not properties.
    for tag, spelling, has_id, since, is_function in ENTITY_RE.findall(
            table_body(the_src, "TheEntity entities[] = {")):
        if has_id == "true":
            continue
        out["movie"][spelling.lower()] = {"spelling": spelling}

    # `the <prop> of <entity>`: the sprite and member vocabularies.
    for tag, spelling, since in FIELD_RE.findall(
            table_body(the_src, "TheEntityField fields[] = {")):
        category = ENTITY_CATEGORY.get(tag)
        if category is None:
            other_entity[tag[4:].lower()].add(spelling.lower())
            continue
        out[category].setdefault(spelling.lower(), {"spelling": spelling})

    for spelling, arg_min, arg_max, since, kind in BUILTIN_RE.findall(
            table_body(read_reference("lingo-builtins.cpp"),
                       "static const BuiltinProto builtins[] = {")):
        out["builtin"][spelling.lower()] = {"spelling": spelling}

    return out, {tag: sorted(names) for tag, names in sorted(other_entity.items())}


# ---------------------------------------------------------------- corpus


class CorpusWalk:
    """Every property and call name the compiler produces from the corpus.

    Direction matters: `set_sprite_prop` accepts any key while `get_sprite_prop`
    falls through to 0, so a name can be bound for writes and unbound for reads.
    The coverage check needs both counts to tell those apart.
    """

    def __init__(self) -> None:
        self.hits: dict[str, dict[str, dict[str, int]]] = {
            c: defaultdict(lambda: {"reads": 0, "writes": 0}) for c in CATEGORIES
        }
        # `the <prop> of <expr>` where the target is only known at runtime.
        self.ambiguous: dict[str, dict[str, int]] = defaultdict(
            lambda: {"reads": 0, "writes": 0})
        self.handlers: set[str] = set()
        self.scripts = 0
        self.unparsed = 0

    def record(self, category: str, name: str, writing: bool) -> None:
        bucket = self.hits[category] if category in self.hits else self.ambiguous
        bucket[name.lower()]["writes" if writing else "reads"] += 1

    def walk(self, node: object, writing: bool = False) -> None:
        if isinstance(node, list):
            for item in node:
                self.walk(item, writing)
            return
        if not isinstance(node, dict):
            return

        kind = node.get("node")
        if kind == "handler":
            self.handlers.add(str(node.get("name", "")).lower())
        elif kind == "assign":
            self.walk(node.get("target"), True)
            self.walk(node.get("value"), False)
            return
        elif kind in NODE_CATEGORY:
            self.record(NODE_CATEGORY[kind], str(node.get("prop", "")), writing)
        elif kind == "prop_of":
            self.record("ambiguous", str(node.get("prop", "")), writing)
        elif kind == "dot":
            owner = node.get("target")
            owner_kind = owner.get("node") if isinstance(owner, dict) else None
            self.record(DOT_OWNER_CATEGORY.get(owner_kind, "ambiguous"),
                        str(node.get("prop", "")), writing)
        elif kind == "call":
            callee = node.get("callee")
            if isinstance(callee, dict) and callee.get("node") == "var":
                self.record("builtin", str(callee.get("name", "")), False)
        elif kind == "call_stmt":
            self.walk(node.get("call"), False)
            return

        for key, value in node.items():
            if key in ("node", "prop", "name", "words", "line"):
                continue
            self.walk(value, False)


def walk_corpus() -> CorpusWalk:
    walk = CorpusWalk()
    for path in lc.script_files():
        try:
            ast = lc.parse_source(
                path.read_text(encoding="utf-8", errors="replace"), path.stem)
        except lc.LingoError:
            walk.unparsed += 1
            continue
        walk.scripts += 1
        walk.walk(ast)
    return walk


# ---------------------------------------------------------------- manifest


def build() -> dict:
    reference, other_entities = reference_names()
    corpus = walk_corpus()

    # The compiler's only vocabulary table. The parser never consults it:
    # parse_the accepts any word that is not in RESERVED_AFTER_PROP, so this
    # constrains nothing and is recorded as provenance, not as closure.
    compiler = {"movie": {name.lower() for name in lc.SYSTEM_PROPS}}

    categories: dict[str, dict] = {}
    for category in CATEGORIES:
        from_compiler = compiler.get(category, set())
        from_reference = reference[category]
        from_corpus = corpus.hits[category]

        names = []
        for name in sorted(set(from_compiler) | set(from_reference) | set(from_corpus)):
            sources = []
            if name in from_compiler:
                sources.append("compiler")
            if name in from_reference:
                sources.append("reference")
            if name in from_corpus:
                sources.append("corpus")
            entry = {"name": name, "sources": sources}
            entry.update(from_reference.get(name, {}))
            counts = from_corpus.get(name)
            entry["reads"] = counts["reads"] if counts else 0
            entry["writes"] = counts["writes"] if counts else 0
            if category == "builtin" and name in corpus.handlers:
                # Defined by a script in the corpus, so an unbound one is not a
                # missing builtin.
                entry["handler_defined"] = True
            if category == "builtin" and sources == ["corpus"] and name in ARTEFACTS:
                # A reserved word can only reach a callee position when the
                # parser mis-splits a command-form statement. `then` is not a
                # builtin anyone will ever bind, so it is not a coverage gap.
                entry["artefact"] = True
            names.append(entry)

        categories[category] = {
            "closed": bool(from_reference),
            "closure_source": "reference" if from_reference else None,
            "counts": {
                "total": len(names),
                "compiler": len(from_compiler),
                "reference": len(from_reference),
                "corpus": len(from_corpus),
            },
            "names": names,
        }

    return {
        "generated_by": "tools/generate_lingo_vocabulary.py",
        "director_version": {
            "resolved": DIRECTOR_VERSION,
            "status": VERSION_STATUS,
            "applied_as_filter": False,
            "candidates": VERSION_CANDIDATES,
        },
        "categories_order": list(CATEGORIES),
        "sources": {
            "compiler": {
                "file": "tools/lingo_compile.py",
                "tables": ["SYSTEM_PROPS"],
                "note": "SYSTEM_PROPS is unreferenced by the parser; it closes nothing.",
            },
            "reference": {
                "files": ["reference/scummvm/lingo/lingo-the.cpp",
                          "reference/scummvm/lingo/lingo-builtins.cpp"],
                "revision": scummvm_revision(),
                "pinned_by": "tools/fetch_scummvm_reference.sh",
                "taken": "Property and builtin names, their canonical spelling, "
                         "and the entity each property belongs to. These "
                         "transcribe Director's own language and object model: "
                         "`the windowType of window \"x\"` is Lingo syntax, and "
                         "window, castLib, menu, menuItem, chunk, date and time "
                         "are Director objects.",
                "not_taken": "The Director release each name was introduced in, "
                             "and the property and builtin type tags. Determining "
                             "those is the reference's own research rather than a "
                             "fact about the language, so they are read to route a "
                             "name into a category and then discarded. Do not "
                             "reintroduce them.",
                "authority": "A source, not an authority. It is wrong about this "
                             "game in at least one measured case: score.cpp:1976 "
                             "hard-codes 120 displayed channels on the "
                             "framesVersion <= 13 branch, skipping the uint16 that "
                             "follows, but 21 of the 60 movies declare 150 and "
                             "ENDMOVI1.DXR writes sprite channel 150 - past that "
                             "ceiling, so the reference truncates it. The port "
                             "reads the per-movie field at VWSC-header offset 18. "
                             "Evidence: openspec/changes/director-playback-machine"
                             "/director-version.md. Where the two disagree, the "
                             "game's own data decides.",
            },
            "corpus": {
                "root": "reference/lingo",
                "scripts": corpus.scripts,
                "unparsed": corpus.unparsed,
            },
        },
        "categories": categories,
        "other_entities": other_entities,
        "ambiguous": [
            {"name": name, "reads": counts["reads"], "writes": counts["writes"]}
            for name, counts in sorted(corpus.ambiguous.items())
        ],
    }


def render(manifest: dict) -> str:
    return json.dumps(manifest, indent=1, sort_keys=False) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if the committed manifest is stale")
    ap.add_argument("--summary", action="store_true",
                    help="print per-category counts")
    args = ap.parse_args()

    manifest = build()
    text = render(manifest)

    if args.check:
        current = OUT_PATH.read_text(encoding="utf-8") if OUT_PATH.exists() else ""
        if current != text:
            print(f"{OUT_PATH.relative_to(REPO)} is stale - regenerate it",
                  file=sys.stderr)
            return 1
        print(f"{OUT_PATH.relative_to(REPO)} is up to date")
        return 0

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(text, encoding="utf-8")
    print(f"wrote {OUT_PATH.relative_to(REPO)}")

    if args.summary:
        out = sys.stderr
        source = manifest["sources"]["corpus"]
        print(f"corpus: {source['scripts']} scripts parsed, "
              f"{source['unparsed']} unparsed", file=out)
        for category in CATEGORIES:
            block = manifest["categories"][category]
            counts = block["counts"]
            print(f"  {category:<8} total {counts['total']:>4}  "
                  f"compiler {counts['compiler']:>3}  "
                  f"reference {counts['reference']:>3}  "
                  f"corpus {counts['corpus']:>3}  "
                  f"closed={str(block['closed']).lower()}", file=out)
        print(f"  ambiguous (`the X of <expr>`): {len(manifest['ambiguous'])}\n"
              f"  other Lingo entities: "
              f"{sum(len(v) for v in manifest['other_entities'].values())} names "
              f"over {len(manifest['other_entities'])} entities "
              f"({', '.join(manifest['other_entities'])})", file=out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
