#!/usr/bin/env python3
"""Generate `lingo/compile/lscr_the.gd` from the vendored ScummVM tables.

`the` entity access in compiled Lingo is two opcodes -- `get` (0x5c) and `set`
(0x5d) -- whose operand is a *bank* number, with the first argument on the stack
selecting the field inside that bank.  The pair `(bank << 8) | firstArg` keys
`lingoV4TheEntity[]` in `reference/scummvm/lingo/lingo-bytecode.cpp`, 149 rows
carrying `(entity, field, writable, argsType)`.  Those rows name enum constants,
and turning them back into the Lingo words a decoder has to emit needs two more
tables from `lingo-the.cpp`: the entity names (`{ kTheSprite, "sprite", ... }`)
and the per-entity field names (`{ kTheSprite, "castNum", kTheCastNum, ... }`).

`docs/LSCR_FORMAT.md` section 4.3 says of this table: *"Do not retype it."*  This
script is why it does not have to be.  Retyping 149 rows against three enum
tables is exactly the kind of transcription that produces a decoder that is right
about 147 rows and silently wrong about two, and nothing downstream would ever
notice -- a mis-named `the` property becomes a property the interpreter does not
recognise, at run time, in a script nobody plays.

Run it after `tools/fetch_scummvm_reference.sh`:

    python tools/gen_lscr_the_table.py

It rewrites `lingo/compile/lscr_the.gd` in place and prints what changed.  The
generated file is committed, because `reference/` is fetched rather than tracked
and a checkout without it must still be able to run the decoder.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BYTECODE = ROOT / "reference" / "scummvm" / "lingo" / "lingo-bytecode.cpp"
THE = ROOT / "reference" / "scummvm" / "lingo" / "lingo-the.cpp"
OUT = ROOT / "lingo" / "compile" / "lscr_the.gd"

# `argsType`, `lingo-bytecode.h:36`.  What the opcode pops besides the field
# selector, which is the only part of the row a decoder acts on structurally.
ARGS = {
    "kTEANOArgs": "none",
    "kTEAItemId": "id",
    "kTEAString": "string",
    "kTEAMenuId": "menu",
    "kTEAMenuIdItemId": "menuitem",
    "kTEAChunk": "chunk",
}

ENTITY_ROW = re.compile(
    r'\{\s*(kThe\w+),\s*"([^"]*)",\s*(?:true|false),\s*\d+,\s*(?:true|false)\s*\}'
)
FIELD_ROW = re.compile(r'\{\s*(kThe\w+),\s*"([^"]*)",\s*(kThe\w+),\s*\d+\s*\}')
V4_ROW = re.compile(
    r"\{\s*0x([0-9a-fA-F]{2}),\s*0x([0-9a-fA-F]{2}),\s*(kThe\w+),\s*(kThe\w+),"
    r"\s*(true|false),\s*(kTEA\w+)\s*\}"
)


def demote(enum: str) -> str:
    """`kTheCastNum` -> `castNum`.

    The fallback for the handful of enum constants that carry no row in
    `lingo-the.cpp`'s name tables: `kTheChars`, `kTheWords`, `kTheItems`,
    `kTheLines` and `kTheMenus` are entities ScummVM only ever reaches through
    `the number of chars in ...` and never names, and `kTheLast` / `kTheNumber`
    are fields of exactly those.  The enum identifier *is* the Lingo word with a
    prefix and a capital on it, in every row the name tables do cover, so
    demoting it is the same transformation those tables already agree with
    rather than a guess about six of them.
    """
    stem = enum[4:] if enum.startswith("kThe") else enum
    return stem[:1].lower() + stem[1:] if stem else ""


def read(path: Path) -> str:
    if not path.exists():
        sys.exit(
            f"missing {path.relative_to(ROOT)} -- run bash tools/fetch_scummvm_reference.sh"
        )
    return path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    the_src = read(THE)
    entities = dict(ENTITY_ROW.findall(the_src))
    fields: dict[tuple[str, str], str] = {}
    for entity, name, field in FIELD_ROW.findall(the_src):
        fields.setdefault((entity, field), name)

    rows = V4_ROW.findall(read(BYTECODE))
    if not rows:
        sys.exit("no lingoV4TheEntity rows matched -- has the reference moved?")

    lines: list[str] = []
    unresolved: list[str] = []
    for bank_hex, arg_hex, entity, field, writable, args in rows:
        key = (int(bank_hex, 16) << 8) | int(arg_hex, 16)
        entity_name = entities.get(entity)
        if entity_name is None:
            unresolved.append(entity)
            entity_name = demote(entity)
        field_name = "" if field == "kTheNOField" else fields.get((entity, field), "")
        if field != "kTheNOField" and field_name == "":
            unresolved.append(f"{entity}.{field}")
            field_name = demote(field)
        lines.append(
            '\t0x%04X: {"entity": "%s", "field": "%s", "writable": %s, "args": "%s"},'
            % (key, entity_name, field_name, writable, ARGS[args])
        )

    body = "\n".join(lines)
    OUT.write_text(HEADER % (len(rows), body), encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} rows")
    if unresolved:
        print("  not in the name tables, demoted from the enum: " + ", ".join(sorted(set(unresolved))))
    return 0


HEADER = '''extends RefCounted
## `the <entity> of <target>` as compiled Lingo encodes it: bank, field, and what
## else the opcode pops.
##
## **Generated by `tools/gen_lscr_the_table.py` -- do not edit by hand.** The %d
## rows are `lingoV4TheEntity[]` from
## `reference/scummvm/lingo/lingo-bytecode.cpp`, joined against the entity and
## field name tables in `lingo-the.cpp` so the enum constants come back out as
## the Lingo words they stand for. `docs/LSCR_FORMAT.md` section 4.3 says of this
## table, in those words, "Do not retype it".
##
## `get` (0x5c) and `set` (0x5d) carry a **bank** as their operand; the *first
## argument on the stack* selects the field within the bank. So the key here is
## `(bank << 8) | firstArg`, which is how the reference keys it too.
##
## `args` says what the opcode pops besides that selector, and it is the only
## part of a row that changes the shape of the decode rather than the name in it:
##
## | `args` | popped |
## | --- | --- |
## | `none` | nothing |
## | `id` | an id (`the castNum of sprite 3`) -- and at D5+, for `the cast` and `the field`, an id **and** a cast-lib id |
## | `string` | a string (`the last word of "..."`) |
## | `menu` / `menuitem` | a menu id, and an item id for the pair |
## | `chunk` | a chunk expression |
##
## The regenerate step is `python tools/gen_lscr_the_table.py` after
## `bash tools/fetch_scummvm_reference.sh`. The file is committed because
## `reference/` is fetched rather than tracked, and a fresh checkout has to be
## able to run the decoder without it.

## `(bank << 8) | firstArg` -> `{entity, field, writable, args}`.
const ROWS := {
%s
}


## The row for a bank and its first stack argument, or `{}`.
##
## `{}` is a real answer rather than a failure: banks 0x02 and 0x03 are the menus,
## which this port has no node for at all, and a decoder is expected to emit an
## `unknown_the` node for them rather than guess. Failing the handler instead
## would lose every other statement in it.
static func row(bank: int, first_arg: int) -> Dictionary:
\treturn ROWS.get((bank << 8) | first_arg, {})
'''


if __name__ == "__main__":
    raise SystemExit(main())
