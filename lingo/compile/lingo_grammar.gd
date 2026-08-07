class_name LingoGrammar
extends RefCounted
## Lingo's vocabulary and precedence, as tables and nothing else.
##
## Held apart from the lexer and the parser so it can be diffed by eye against
## `tools/lingo_compile.py:29-154`, which is the implementation this one has to
## agree with script for script. Every set is a Dictionary rather than an Array
## because these are consulted per token and `Array.has` is a linear scan.
##
## `SYSTEM_PROPS` is deliberately absent: the Python declares it and never reads
## it, so porting it would carry a table nothing consults.

const KEYWORDS := {
	"on": true, "end": true, "if": true, "then": true, "else": true,
	"repeat": true, "while": true, "with": true, "to": true, "of": true,
	"put": true, "into": true, "after": true, "before": true, "set": true,
	"global": true, "case": true, "otherwise": true, "exit": true,
	"return": true, "next": true, "and": true, "or": true, "not": true,
	"contains": true, "starts": true, "mod": true, "the": true, "sprite": true,
	"member": true, "field": true, "castlib": true, "line": true, "item": true,
	"word": true, "char": true, "intersects": true, "within": true, "in": true,
	"down": true, "property": true, "instance": true, "tell": true,
}

## Chunk expression heads, e.g. `line 3 of field "x"`.
const CHUNKS := {"line": true, "item": true, "word": true, "char": true}

## Index into BINARY_LEVELS. Chunk indices bind loosely enough to include
## arithmetic (`line i - 102 of field "x"`) but stop before `of`, a keyword.
## Indices into `BINARY_LEVELS`. They shift whenever a level is added or removed,
## and nothing checks them: merging `and` and `or` onto one level moved every one
## of these down by one, so the parser silently parsed at the wrong precedence
## everywhere they are used and DAY1's `init all` stopped running. Renumber these
## with the table or not at all.
const ADDITIVE := 3
const TIGHT := 4
## Above the comparison level, so parsing a statement's left-hand side does not
## swallow `=`. Lingo spells assignment and equality alike and resolves it by
## position: a statement whose target is followed by `=` is an assignment.
const NO_COMPARISON := 2

## Lowest to highest binding power. Lingo's precedence is shallow.
const BINARY_LEVELS := [
	# `and` and `or` share one left-associative level, as they do in Director.
	# Ranking `or` below `and` -- the C habit -- reparses `a or b and c` as
	# `a or (b and c)` where Director means `(a or b) and c`, and the two differ
	# whenever `a` is true and `c` is false.
	#
	# No site in this game depends on it: of the fifteen lines that mix the two
	# operators, every one is fully parenthesised. That is why it survived, and
	# it is not a reason to leave it -- the next title will not be so careful,
	# and a precedence bug does not announce itself. It changes which branch
	# runs, silently, in a language where the branch is the whole behaviour.
	{"or": true, "and": true},
	{"=": true, "<>": true, "<": true, ">": true, "<=": true, ">=": true,
		"contains": true, "starts": true},
	{"&": true, "&&": true},
	{"+": true, "-": true},
	{"*": true, "/": true, "mod": true},
]

## Words that end a `the <property>` phrase rather than extending it.
const RESERVED_AFTER_PROP := {
	"of": true, "to": true, "into": true, "then": true, "and": true,
	"or": true, "not": true, "mod": true, "contains": true, "starts": true,
	"intersects": true, "within": true, "in": true, "down": true,
	"after": true, "before": true, "end": true, "else": true, "with": true,
	"while": true, "is": true, "repeat": true, "case": true,
	"otherwise": true, "exit": true, "return": true, "next": true,
	"put": true, "set": true, "global": true, "on": true, "if": true,
}

## The only adjectives that legitimately precede a property name.
const THE_ADJECTIVES := {
	"long": true, "short": true, "abbreviated": true, "abbrev": true,
	"number": true,
}

## Commands whose first argument is a bare word rather than an expression:
## `sound playFile 1, x`, `go to frame 5`, `play frame "x"`. Without this the
## second word parses as a nested command call and swallows the real arguments.
const COMMAND_WORDS := {
	"sound": {"playfile": true, "stop": true, "fadein": true, "fadeout": true,
		"close": true, "play": true},
	"go": {"to": true, "frame": true, "loop": true, "next": true,
		"previous": true, "movie": true},
	"play": {"frame": true, "done": true, "movie": true},
	"open": {"window": true},
	"close": {"window": true},
}

## Two-character operators, which must be tried before their first character.
const LONG_OPERATORS := ["<>", "<=", ">=", "&&"]
## Single characters that stand alone as operators.
const SHORT_OPERATORS := "-+*/<>=&(),:.[]"
