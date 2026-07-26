#!/usr/bin/env python3
"""Compile the decompiled Lingo in reference/lingo/ to JSON ASTs.

The port executes these ASTs at runtime (see lingo/interpreter.gd), so this is
the front half of the full migration: every script parses here or it cannot run
there. Coverage is reported as a hard fraction, never as "most".

    python3 tools/lingo_compile.py                 # report only
    python3 tools/lingo_compile.py --emit          # also write data/lingo/
    python3 tools/lingo_compile.py --file <path>   # one file, dump its AST
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LINGO_ROOT = REPO / "reference" / "lingo"
# NOT under assets/: assets/SOURCE.txt documents that tree as mirrored with
# `robocopy /MIR`, which would delete anything generated into it.
OUT_ROOT = REPO / "data" / "lingo"

# ---------------------------------------------------------------- lexer

KEYWORDS = {
    "on", "end", "if", "then", "else", "repeat", "while", "with", "to", "of",
    "put", "into", "after", "before", "set", "global", "case", "otherwise",
    "exit", "return", "next", "and", "or", "not", "contains", "starts", "mod",
    "the", "sprite", "member", "field", "castlib", "line", "item", "word",
    "char", "intersects", "within", "in", "down", "property", "instance",
    "tell",
}

# Chunk expression heads, e.g. `line 3 of field "x"`.
CHUNKS = {"line", "item", "word", "char"}

TOKEN_RE = re.compile(
    r"""
    (?P<ws>[ \t]+)
  | (?P<comment>--[^\r\n]*)
  | (?P<continuation>\\\s*\r?\n)
  | (?P<newline>\r?\n)
  | (?P<number>\d+\.\d+|\.\d+|\d+)
  | (?P<string>"(?:[^"\r\n])*")
  | (?P<ident>[A-Za-z_][A-Za-z0-9_.]*)
  | (?P<op><>|<=|>=|&&|[-+*/<>=&(),:.\[\]])
    """,
    re.VERBOSE,
)


class Tok:
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind: str, value: str, line: int):
        self.kind = kind
        self.value = value
        self.line = line

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"{self.kind}:{self.value!r}@{self.line}"


class LingoError(Exception):
    def __init__(self, message: str, line: int):
        super().__init__(f"line {line}: {message}")
        self.line = line


def tokenize(src: str) -> list[Tok]:
    out: list[Tok] = []
    pos = 0
    line = 1
    n = len(src)
    while pos < n:
        m = TOKEN_RE.match(src, pos)
        if m is None:
            raise LingoError(f"unexpected character {src[pos]!r}", line)
        pos = m.end()
        kind = m.lastgroup
        text = m.group()
        if kind in ("ws", "comment"):
            continue
        if kind == "continuation":
            line += 1
            continue
        if kind == "newline":
            out.append(Tok("nl", "\n", line))
            line += 1
            continue
        if kind == "number":
            out.append(Tok("number", text, line))
            continue
        if kind == "string":
            out.append(Tok("string", text[1:-1], line))
            continue
        if kind == "ident":
            low = text.lower()
            # `the number of lines in x` and friends read better with `number`
            # left as an identifier; keywords are matched case-insensitively.
            out.append(Tok("kw" if low in KEYWORDS else "ident", text, line))
            continue
        out.append(Tok("op", text, line))
    out.append(Tok("eof", "", line))
    return out


# ---------------------------------------------------------------- parser

# Lowest to highest binding power. Lingo's precedence is shallow.
# Index into BINARY_LEVELS. Chunk indices bind loosely enough to include
# arithmetic (`line i - 102 of field "x"`) but stop before `of`, which is a
# keyword rather than an operator.
ADDITIVE = 4
TIGHT = 5
# Above the comparison level, so parsing a statement's left-hand side does not
# swallow `=`. Lingo spells assignment and equality the same way and resolves it
# by position: a statement whose target is followed by `=` is an assignment.
NO_COMPARISON = 3

BINARY_LEVELS = [
    {"or"},
    {"and"},
    {"=", "<>", "<", ">", "<=", ">=", "contains", "starts"},
    {"&", "&&"},
    {"+", "-"},
    {"*", "/", "mod"},
]

# Words that end a `the <property>` phrase rather than extending it.
RESERVED_AFTER_PROP = {
    "of", "to", "into", "then", "and", "or", "not", "mod", "contains",
    "starts", "intersects", "within", "in", "down", "after", "before", "end",
    "else", "with", "while", "is", "repeat", "case", "otherwise", "exit",
    "return", "next", "put", "set", "global", "on", "if",
}

# The only adjectives that legitimately precede a property name.
THE_ADJECTIVES = {"long", "short", "abbreviated", "abbrev", "number"}

# Commands whose first argument is a bare word rather than an expression:
# `sound playFile 1, x`, `go to frame 5`, `play frame "x"`. Without this the
# second word parses as a nested command call and swallows the real arguments.
COMMAND_WORDS = {
    "sound": {"playfile", "stop", "fadein", "fadeout", "close", "play"},
    "go": {"to", "frame", "loop", "next", "previous", "movie"},
    "play": {"frame", "done", "movie"},
    "open": {"window"},
    "close": {"window"},
}

SYSTEM_PROPS = {
    "moviename", "machinetype", "keycode", "clickon", "mouseh", "mousev",
    "frame", "timer", "ticks", "milliseconds", "key", "shiftdown",
    "optiondown", "commanddown", "controldown", "doubleclick", "mousedown",
    "mouseup", "lastclick", "colordepth", "stagecolor", "soundlevel",
    "movierate", "framepalette", "exitlock", "keydownscript", "actorlist",
    "randomseed", "result", "time", "date", "long", "short", "abbreviated",
    "number", "runmode", "platform", "productversion", "environment",
    "searchpath", "moviepath", "pathname", "applicationpath", "fixstagesize",
    "centerstage", "puppet", "visible", "volume", "cursor", "updatelock",
    "freeblock", "memorysize", "objectlist", "windowlist", "activewindow",
    "frontwindow", "score", "labellist", "framelabel", "framescript",
    "frametempo", "frametransition", "beepon", "checkboxaccess",
    "checkboxtype", "selection", "selstart", "selend", "itemdelimiter",
    "floatprecision", "traceload", "tracelogfile", "tracescript",
}


class Parser:
    def __init__(self, toks: list[Tok], name: str):
        self.toks = toks
        self.i = 0
        self.name = name

    # -- token helpers

    def peek(self, ahead: int = 0) -> Tok:
        return self.toks[min(self.i + ahead, len(self.toks) - 1)]

    def next(self) -> Tok:
        tok = self.toks[self.i]
        if tok.kind != "eof":
            self.i += 1
        return tok

    def at_kw(self, *words: str, ahead: int = 0) -> bool:
        tok = self.peek(ahead)
        return tok.kind == "kw" and tok.value.lower() in words

    def at_op(self, *ops: str, ahead: int = 0) -> bool:
        tok = self.peek(ahead)
        return tok.kind == "op" and tok.value in ops

    def at_word(self, *words: str, ahead: int = 0) -> bool:
        """Match by spelling regardless of keyword status."""
        tok = self.peek(ahead)
        return tok.kind in ("kw", "ident") and tok.value.lower() in words

    def eat_kw(self, *words: str) -> bool:
        if self.at_kw(*words):
            self.next()
            return True
        return False

    def eat_op(self, *ops: str) -> bool:
        if self.at_op(*ops):
            self.next()
            return True
        return False

    def eat_word(self, *words: str) -> bool:
        if self.at_word(*words):
            self.next()
            return True
        return False

    def expect_op(self, op: str) -> None:
        if not self.eat_op(op):
            raise LingoError(f"expected {op!r}, got {self.peek().value!r}", self.peek().line)

    def skip_newlines(self) -> None:
        while self.peek().kind == "nl":
            self.next()

    def end_of_statement(self) -> None:
        while self.peek().kind == "nl":
            self.next()

    # -- top level

    def parse_script(self) -> dict:
        handlers: list[dict] = []
        properties: list[str] = []
        globals_: list[str] = []
        loose: list[dict] = []
        self.skip_newlines()
        while self.peek().kind != "eof":
            if self.at_kw("on"):
                handlers.append(self.parse_handler())
            elif self.at_kw("property", "instance"):
                self.next()
                properties += self.parse_name_list()
            elif self.at_kw("global"):
                self.next()
                globals_ += self.parse_name_list()
            else:
                # Frame and cast scripts sometimes carry bare statements.
                loose.append(self.parse_statement())
            self.skip_newlines()
        return {
            "script": self.name,
            "handlers": handlers,
            "properties": properties,
            "globals": globals_,
            "body": loose,
        }

    def parse_name_list(self) -> list[str]:
        names: list[str] = []
        while True:
            tok = self.peek()
            if tok.kind not in ("ident", "kw"):
                break
            names.append(self.next().value)
            if not self.eat_op(","):
                break
        self.end_of_statement()
        return names

    def parse_handler(self) -> dict:
        line = self.peek().line
        self.next()  # on
        name_tok = self.next()
        if name_tok.kind not in ("ident", "kw"):
            raise LingoError("handler needs a name", line)
        params: list[str] = []
        while self.peek().kind in ("ident", "kw") and self.peek().kind != "nl":
            if self.at_kw("end"):
                break
            params.append(self.next().value)
            if not self.eat_op(","):
                break
        self.end_of_statement()
        body = self.parse_block(("end",))
        self.expect_end("end")
        # `end mouseUp` names the handler again; swallow it.
        if self.peek().kind in ("ident", "kw") and self.peek().kind != "nl":
            if self.peek().value.lower() == name_tok.value.lower():
                self.next()
        self.end_of_statement()
        return {"node": "handler", "name": name_tok.value, "params": params,
                "body": body, "line": line}

    def expect_end(self, word: str) -> None:
        if not self.eat_kw(word):
            raise LingoError(f"expected {word}", self.peek().line)

    def parse_block(self, stop_words: tuple[str, ...]) -> list[dict]:
        stmts: list[dict] = []
        while True:
            self.skip_newlines()
            tok = self.peek()
            if tok.kind == "eof":
                return stmts
            if tok.kind == "kw" and tok.value.lower() in stop_words:
                return stmts
            # `otherwise:` inside a case, and bare case labels, stop a block.
            if "otherwise" in stop_words and self.at_kw("otherwise"):
                return stmts
            stmts.append(self.parse_statement())

    # -- statements

    def parse_statement(self) -> dict:
        tok = self.peek()
        line = tok.line
        if tok.kind == "kw":
            low = tok.value.lower()
            if low == "global":
                self.next()
                return {"node": "global", "names": self.parse_name_list(), "line": line}
            if low == "property" or low == "instance":
                self.next()
                return {"node": "property", "names": self.parse_name_list(), "line": line}
            if low == "if":
                return self.parse_if()
            if low == "repeat":
                return self.parse_repeat()
            if low == "case":
                return self.parse_case()
            if low == "put":
                return self.parse_put()
            if low == "set":
                return self.parse_set()
            if low == "exit":
                self.next()
                if self.eat_kw("repeat"):
                    self.end_of_statement()
                    return {"node": "exit_repeat", "line": line}
                self.end_of_statement()
                return {"node": "exit", "line": line}
            if low == "return":
                self.next()
                value = None
                if self.peek().kind not in ("nl", "eof"):
                    value = self.parse_expr()
                self.end_of_statement()
                return {"node": "return", "value": value, "line": line}
            if low == "tell":
                return self.parse_tell()
            if low == "next":
                self.next()
                self.eat_kw("repeat")
                self.end_of_statement()
                return {"node": "next_repeat", "line": line}

        # Assignment to a place, or a command call.
        start = self.i
        place = self.parse_expr(NO_COMPARISON)
        if self.at_op("=") and self.is_place(place):
            self.next()
            value = self.parse_expr()
            self.end_of_statement()
            return {"node": "assign", "target": place, "value": value, "line": line}
        # Not an assignment, so re-read the whole thing as one expression: a
        # command call such as `updateStage()`, `go("x")`, `sound playFile 1, x`,
        # or a parameterless handler call.
        self.i = start
        call = self.parse_expr()
        self.end_of_statement()
        return {"node": "call_stmt", "call": call, "line": line}

    @staticmethod
    def is_place(node: dict) -> bool:
        return node.get("node") in ("var", "prop", "sprite_prop", "member_prop",
                                    "chunk", "field", "field_prop", "menu_prop",
                                    "index", "dot", "prop_of")

    def parse_if(self) -> dict:
        line = self.peek().line
        self.next()  # if
        cond = self.parse_expr()
        self.eat_kw("then")
        # Single-line form: `if x then go("y")` with no `end if`.
        if self.peek().kind not in ("nl", "eof"):
            then_body = [self.parse_statement()]
            else_body: list[dict] = []
            self.skip_newlines()
            if self.at_kw("else"):
                self.next()
                if self.peek().kind not in ("nl", "eof"):
                    else_body = [self.parse_statement()]
                else:
                    else_body = self.parse_block(("end", "else"))
                    self.finish_if()
            elif self.at_kw("end") and self.at_word("if", ahead=1):
                self.finish_if()
            return {"node": "if", "cond": cond, "then": then_body,
                    "else": else_body, "line": line}

        then_body = self.parse_block(("end", "else"))
        else_body = []
        if self.at_kw("else"):
            self.next()
            # `else if` chains without a matching `end if` per level.
            if self.at_kw("if"):
                else_body = [self.parse_if()]
                return {"node": "if", "cond": cond, "then": then_body,
                        "else": else_body, "line": line}
            if self.peek().kind not in ("nl", "eof"):
                else_body = [self.parse_statement()]
            else:
                else_body = self.parse_block(("end",))
        self.finish_if()
        return {"node": "if", "cond": cond, "then": then_body,
                "else": else_body, "line": line}

    def finish_if(self) -> None:
        if self.eat_kw("end"):
            self.eat_word("if")
        self.end_of_statement()

    def parse_repeat(self) -> dict:
        line = self.peek().line
        self.next()  # repeat
        if self.eat_kw("while"):
            cond = self.parse_expr()
            self.end_of_statement()
            body = self.parse_block(("end",))
            self.expect_end("end")
            self.eat_word("repeat")
            self.end_of_statement()
            return {"node": "repeat_while", "cond": cond, "body": body, "line": line}
        if self.eat_kw("with"):
            name = self.next().value
            if self.eat_kw("in"):
                seq = self.parse_expr()
                self.end_of_statement()
                body = self.parse_block(("end",))
                self.expect_end("end")
                self.eat_word("repeat")
                self.end_of_statement()
                return {"node": "repeat_in", "var": name, "seq": seq,
                        "body": body, "line": line}
            self.expect_op("=")
            start = self.parse_expr()
            descending = False
            if self.eat_kw("down"):
                descending = True
            if not self.eat_kw("to"):
                raise LingoError("repeat with needs `to`", self.peek().line)
            stop = self.parse_expr()
            self.end_of_statement()
            body = self.parse_block(("end",))
            self.expect_end("end")
            self.eat_word("repeat")
            self.end_of_statement()
            return {"node": "repeat_with", "var": name, "from": start,
                    "to": stop, "down": descending, "body": body, "line": line}
        # `repeat` with no qualifier: loop until `exit repeat`.
        self.end_of_statement()
        body = self.parse_block(("end",))
        self.expect_end("end")
        self.eat_word("repeat")
        self.end_of_statement()
        return {"node": "repeat_forever", "body": body, "line": line}

    def parse_case(self) -> dict:
        line = self.peek().line
        self.next()  # case
        subject = self.parse_expr()
        if not self.eat_kw("of"):
            raise LingoError("case needs `of`", self.peek().line)
        self.end_of_statement()
        branches: list[dict] = []
        default: list[dict] = []
        while True:
            self.skip_newlines()
            if self.peek().kind == "eof":
                break
            if self.at_kw("end"):
                break
            if self.at_kw("otherwise"):
                self.next()
                self.eat_op(":")
                self.end_of_statement()
                default = self.parse_block(("end",))
                break
            values = [self.parse_expr()]
            while self.eat_op(","):
                values.append(self.parse_expr())
            self.expect_op(":")
            self.end_of_statement()
            body = self.parse_case_body()
            branches.append({"values": values, "body": body})
        self.expect_end("end")
        self.eat_word("case")
        self.end_of_statement()
        return {"node": "case", "subject": subject, "branches": branches,
                "default": default, "line": line}

    def parse_tell(self) -> dict:
        """`tell the stage ... end tell`.

        Director retargets messages at another movie or window. This port has a
        single stage, so the body simply runs, but the target is kept so a
        future multi-window case is not silently mistranslated.
        """
        line = self.peek().line
        self.next()  # tell
        target = self.parse_expr()
        # Single-line form: `tell the stage to go("x")`.
        if self.eat_kw("to"):
            body = [self.parse_statement()]
            return {"node": "tell", "target": target, "body": body, "line": line}
        self.end_of_statement()
        body = self.parse_block(("end",))
        self.expect_end("end")
        self.eat_word("tell")
        self.end_of_statement()
        return {"node": "tell", "target": target, "body": body, "line": line}

    def parse_case_body(self) -> list[dict]:
        """A branch body runs until the next label, `otherwise`, or `end case`.

        Labels are not keyword-introduced — `"joystk":` is just an expression
        followed by a colon — so the only way to know a branch ended is to look
        ahead for a top-level colon on the coming line.
        """
        stmts: list[dict] = []
        while True:
            self.skip_newlines()
            tok = self.peek()
            if tok.kind == "eof" or self.at_kw("end", "otherwise"):
                return stmts
            if self.line_is_case_label():
                return stmts
            stmts.append(self.parse_statement())

    def line_is_case_label(self) -> bool:
        depth = 0
        j = self.i
        while j < len(self.toks):
            tok = self.toks[j]
            if tok.kind in ("nl", "eof"):
                return False
            if tok.kind == "op":
                if tok.value in ("(", "["):
                    depth += 1
                elif tok.value in (")", "]"):
                    depth -= 1
                elif tok.value == ":" and depth == 0:
                    return True
            j += 1
        return False

    def parse_put(self) -> dict:
        line = self.peek().line
        self.next()  # put
        if self.peek().kind in ("nl", "eof"):
            # A bare `put` with no argument. One decompiled script has this;
            # in Director it echoes nothing.
            self.end_of_statement()
            return {"node": "put_echo", "value": None, "line": line}
        value = self.parse_expr()
        mode = "into"
        if self.eat_kw("into"):
            mode = "into"
        elif self.eat_kw("after"):
            mode = "after"
        elif self.eat_kw("before"):
            mode = "before"
        else:
            # `put x` on its own is Director's message-window echo. Harmless.
            self.end_of_statement()
            return {"node": "put_echo", "value": value, "line": line}
        target = self.parse_expr()
        self.end_of_statement()
        return {"node": "put", "mode": mode, "value": value,
                "target": target, "line": line}

    def parse_set(self) -> dict:
        line = self.peek().line
        self.next()  # set
        target = self.parse_expr()
        if not (self.eat_kw("to") or self.eat_op("=")):
            raise LingoError("set needs `to`", self.peek().line)
        value = self.parse_expr()
        self.end_of_statement()
        return {"node": "assign", "target": target, "value": value, "line": line}

    # -- expressions

    def parse_expr(self, level: int = 0) -> dict:
        if level >= len(BINARY_LEVELS):
            return self.parse_unary()
        left = self.parse_expr(level + 1)
        while True:
            tok = self.peek()
            op = tok.value.lower() if tok.kind in ("op", "kw") else None
            if op is None or op not in BINARY_LEVELS[level]:
                break
            self.next()
            right = self.parse_expr(level + 1)
            left = {"node": "binary", "op": op, "left": left, "right": right,
                    "line": tok.line}
        # `intersects` / `within` sit at the comparison level in practice.
        if level == 2:
            while self.at_kw("intersects", "within"):
                op = self.next().value.lower()
                right = self.parse_expr(level + 1)
                left = {"node": "binary", "op": op, "left": left,
                        "right": right, "line": self.peek().line}
        return left

    def parse_unary(self) -> dict:
        tok = self.peek()
        if self.at_kw("not"):
            self.next()
            return {"node": "unary", "op": "not", "value": self.parse_unary(),
                    "line": tok.line}
        if self.at_op("-"):
            self.next()
            return {"node": "unary", "op": "-", "value": self.parse_unary(),
                    "line": tok.line}
        return self.parse_postfix()

    def parse_postfix(self) -> dict:
        node = self.parse_primary()
        while True:
            if self.at_op(".") and self.peek(1).kind in ("ident", "kw"):
                self.next()
                prop = self.next().value
                node = {"node": "dot", "target": node, "prop": prop,
                        "line": self.peek().line}
                continue
            if self.at_op("(") and node.get("node") in ("var", "dot"):
                args = self.parse_call_args()
                node = {"node": "call", "callee": node, "args": args,
                        "line": self.peek().line}
                continue
            if self.at_op("["):
                self.next()
                index = self.parse_expr()
                if self.eat_op(".") and self.eat_op("."):
                    pass
                self.expect_op("]")
                node = {"node": "index", "target": node, "index": index,
                        "line": self.peek().line}
                continue
            break
        return node

    def parse_call_args(self) -> list[dict]:
        self.expect_op("(")
        args: list[dict] = []
        if self.eat_op(")"):
            return args
        while True:
            args.append(self.parse_expr())
            if self.eat_op(","):
                continue
            self.expect_op(")")
            return args

    def parse_primary(self) -> dict:
        tok = self.peek()
        line = tok.line
        if tok.kind == "number":
            self.next()
            text = tok.value
            value = float(text) if "." in text else int(text)
            return {"node": "num", "value": value, "line": line}
        if tok.kind == "string":
            self.next()
            return {"node": "str", "value": tok.value, "line": line}
        if self.at_op("("):
            self.next()
            inner = self.parse_expr()
            self.expect_op(")")
            return inner
        if self.at_op("["):
            self.next()
            items: list[dict] = []
            props: list[dict] = []
            if not self.at_op("]"):
                while True:
                    first = self.parse_expr()
                    if self.eat_op(":"):
                        props.append({"key": first, "value": self.parse_expr()})
                    else:
                        items.append(first)
                    if self.eat_op(","):
                        continue
                    break
            self.expect_op("]")
            if props:
                return {"node": "proplist", "pairs": props, "line": line}
            return {"node": "list", "items": items, "line": line}
        if self.at_kw("the"):
            return self.parse_the()
        if self.at_kw("field"):
            self.next()
            # Both `field "x" of castLib "master"` and `field("x", "master")`.
            if self.at_op("("):
                args = self.parse_call_args()
                name = args[0] if args else {"node": "str", "value": ""}
                cast = args[1] if len(args) > 1 else None
            else:
                name = self.parse_expr(TIGHT)
                cast = self.parse_optional_castlib()
            return {"node": "field", "name": name, "cast": cast, "line": line}
        if self.at_kw("sprite"):
            self.next()
            if self.at_op("("):
                args = self.parse_call_args()
                target = args[0] if args else {"node": "num", "value": 0}
            else:
                target = self.parse_expr(len(BINARY_LEVELS) - 1)
            return {"node": "sprite_ref", "which": target, "line": line}
        if self.at_kw("member"):
            self.next()
            if self.at_op("("):
                args = self.parse_call_args()
                which = args[0] if args else {"node": "num", "value": 0}
                cast = args[1] if len(args) > 1 else None
            else:
                which = self.parse_expr(len(BINARY_LEVELS) - 1)
                cast = self.parse_optional_castlib()
            return {"node": "member_ref", "which": which, "cast": cast, "line": line}
        if self.at_kw(*CHUNKS):
            return self.parse_chunk()
        if tok.kind in ("ident", "kw"):
            self.next()
            name = tok.value
            # Command-form call: `go "label"`, `sound playFile 1, x`,
            # `puppetSprite i, 1`. An operator or newline means it is a bare
            # variable reference instead.
            if self.starts_command_args():
                args: list[dict] = []
                keywords = COMMAND_WORDS.get(name.lower())
                while (keywords is not None
                       and self.peek().kind in ("ident", "kw")
                       and self.peek().value.lower() in keywords
                       and not self.at_op("(", ahead=1)):
                    args.append({"node": "str", "value": self.next().value,
                                 "line": line})
                if not (args and self.peek().kind in ("nl", "eof")):
                    if args and not self.at_op(","):
                        args.append(self.parse_expr())
                    elif not args:
                        args.append(self.parse_expr())
                    while self.eat_op(","):
                        args.append(self.parse_expr())
                return {"node": "call", "callee": {"node": "var", "name": name},
                        "args": args, "command": True, "line": line}
            return {"node": "var", "name": name, "line": line}
        raise LingoError(f"unexpected {tok.value!r}", line)

    def starts_command_args(self) -> bool:
        tok = self.peek()
        if tok.kind in ("nl", "eof"):
            return False
        if tok.kind == "number" or tok.kind == "string":
            return True
        if tok.kind == "op":
            return tok.value in ("[",)
        if tok.kind == "kw":
            low = tok.value.lower()
            if low in ("the", "field", "sprite", "member", "not") or low in CHUNKS:
                return True
            if low in ("to", "of", "into", "then", "with", "while", "and", "or",
                       "mod", "contains", "starts", "intersects", "within",
                       "down", "in", "else", "end", "after", "before"):
                return False
            return False
        # A following identifier means a command word pair such as
        # `sound playFile`, `go to`, `play frame`, `go loop`.
        return True

    def parse_optional_castlib(self) -> dict | None:
        if self.at_kw("of") and self.at_word("castlib", ahead=1):
            self.next()
            self.next()
            return self.parse_expr(len(BINARY_LEVELS) - 1)
        return None

    def parse_chunk(self) -> dict:
        line = self.peek().line
        kind = self.next().value.lower()
        start = self.parse_expr(ADDITIVE)
        stop = None
        if self.eat_kw("to"):
            stop = self.parse_expr(ADDITIVE)
        if not self.eat_kw("of"):
            raise LingoError(f"{kind} chunk needs `of`", self.peek().line)
        source = self.parse_expr(len(BINARY_LEVELS) - 1)
        return {"node": "chunk", "kind": kind, "start": start, "stop": stop,
                "source": source, "line": line}

    def parse_the(self) -> dict:
        line = self.peek().line
        self.next()  # the
        # `the number of lines in x` counts, but `the number of member "x"` is
        # that member's number. Same three words, different meaning.
        if self.at_word("number") and self.at_kw("of", ahead=1):
            self.next()
            self.next()
            if self.at_word("member", "castmember"):
                self.next()
                if self.at_op("("):
                    args = self.parse_call_args()
                    which = args[0] if args else {"node": "num", "value": 0}
                    cast = args[1] if len(args) > 1 else self.parse_optional_castlib()
                else:
                    which = self.parse_expr(ADDITIVE)
                    cast = self.parse_optional_castlib()
                return {"node": "member_number", "which": which, "cast": cast,
                        "line": line}
            if self.at_word("sprite"):
                self.next()
                which = self.parse_expr(TIGHT)
                return {"node": "sprite_number", "which": which, "line": line}
            unit_tok = self.next()
            unit = unit_tok.value.lower().rstrip("s")
            if not (self.eat_kw("in") or self.eat_kw("of")):
                raise LingoError("`the number of X` needs `in`", self.peek().line)
            source = self.parse_expr(TIGHT)
            return {"node": "count", "unit": unit, "source": source, "line": line}

        # Adjective-style system properties: `the long time`. Only a handful of
        # adjectives may precede the property, and no reserved word may be
        # swallowed as one, or `set the keyDownScript to EMPTY` reads its
        # property as "to".
        words: list[str] = []
        while self.peek().kind in ("ident", "kw"):
            if self.peek().value.lower() in RESERVED_AFTER_PROP:
                break
            words.append(self.next().value)
            if len(words) >= 2 or words[-1].lower() not in THE_ADJECTIVES:
                break
        if not words:
            raise LingoError("`the` needs a property", line)
        prop = words[-1].lower()

        if self.eat_kw("of"):
            if self.at_kw("sprite"):
                self.next()
                if self.at_op("("):
                    args = self.parse_call_args()
                    which = args[0] if args else {"node": "num", "value": 0}
                else:
                    which = self.parse_expr(len(BINARY_LEVELS) - 1)
                return {"node": "sprite_prop", "prop": prop, "which": which,
                        "line": line}
            if self.at_kw("member"):
                self.next()
                if self.at_op("("):
                    args = self.parse_call_args()
                    which = args[0] if args else {"node": "num", "value": 0}
                    cast = args[1] if len(args) > 1 else None
                else:
                    which = self.parse_expr(len(BINARY_LEVELS) - 1)
                    cast = self.parse_optional_castlib()
                return {"node": "member_prop", "prop": prop, "which": which,
                        "cast": cast, "line": line}
            if self.at_kw("field"):
                self.next()
                name = self.parse_expr(len(BINARY_LEVELS) - 1)
                cast = self.parse_optional_castlib()
                return {"node": "field_prop", "prop": prop, "name": name,
                        "cast": cast, "line": line}
            target = self.parse_expr(len(BINARY_LEVELS) - 1)
            return {"node": "prop_of", "prop": prop, "target": target, "line": line}

        return {"node": "prop", "prop": prop, "words": [w.lower() for w in words],
                "line": line}


def parse_source(src: str, name: str) -> dict:
    return Parser(tokenize(src), name).parse_script()


# ---------------------------------------------------------------- driver


def script_files() -> list[Path]:
    return sorted(LINGO_ROOT.rglob("*.ls"))


def relative_id(path: Path) -> tuple[str, str, str]:
    rel = path.relative_to(LINGO_ROOT)
    parts = rel.parts
    movie = parts[0]
    cast = parts[1] if len(parts) > 2 else "internal"
    return movie, cast, rel.stem


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", action="store_true", help="write data/lingo/")
    ap.add_argument("--file", help="parse one file and print its AST")
    ap.add_argument("--failures", type=int, default=25,
                    help="how many failures to list")
    args = ap.parse_args()

    if args.file:
        path = Path(args.file)
        ast = parse_source(path.read_text(encoding="utf-8", errors="replace"), path.stem)
        print(json.dumps(ast, indent=1))
        return 0

    files = script_files()
    if not files:
        print(f"no .ls files under {LINGO_ROOT}", file=sys.stderr)
        return 2

    bundles: dict[tuple[str, str], dict] = {}
    failures: list[tuple[str, str]] = []
    handlers = 0
    for path in files:
        movie, cast, stem = relative_id(path)
        src = path.read_text(encoding="utf-8", errors="replace")
        try:
            ast = parse_source(src, stem)
        except LingoError as exc:
            failures.append((str(path.relative_to(REPO)), str(exc)))
            continue
        except RecursionError:
            failures.append((str(path.relative_to(REPO)), "recursion limit"))
            continue
        handlers += len(ast["handlers"])
        bundles.setdefault((movie, cast), {})[stem] = ast

    ok = len(files) - len(failures)
    print(f"parsed {ok}/{len(files)} scripts ({ok * 100.0 / len(files):.2f}%), "
          f"{handlers} handlers")
    if failures:
        print(f"\n{len(failures)} failures, first {min(args.failures, len(failures))}:")
        for path, msg in failures[: args.failures]:
            print(f"  {path}: {msg}")
        reasons: dict[str, int] = {}
        for _, msg in failures:
            key = re.sub(r"^line \d+: ", "", msg)
            key = re.sub(r"'[^']*'", "'X'", key)
            reasons[key] = reasons.get(key, 0) + 1
        print("\nby reason:")
        for key, count in sorted(reasons.items(), key=lambda kv: -kv[1])[:15]:
            print(f"  {count:5d}  {key}")

    if args.emit:
        for (movie, cast), scripts in sorted(bundles.items()):
            out_dir = OUT_ROOT / movie
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / f"{cast}.json").write_text(
                json.dumps({"movie": movie, "cast": cast, "scripts": scripts},
                           separators=(",", ":")),
                encoding="utf-8",
            )
        print(f"\nwrote {len(bundles)} bundles under {OUT_ROOT.relative_to(REPO)}")

    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
