class_name LingoLexer
extends RefCounted
## Lingo source to a flat token stream.
##
## Hand-written rather than a port of the Python's regex, for one reason that
## would otherwise be a silent corruption: `re.match(src, pos)` is *anchored* at
## the position, while Godot's `RegEx.search(subject, offset)` is not. A spot
## that should fail to match instead matches further along, so a malformed
## script would lex into something plausible instead of raising. A character
## scanner cannot do that, and is faster besides.
##
## Tokens are kept in three parallel packed arrays rather than an array of
## dictionaries: the parser touches every token several times, and the corpus is
## 845 KB of source across 3300-odd scripts.
##
## Alternation order matters and is preserved from the Python: `--` is a comment
## before `-` is an operator, and `.5` is a number before `.` is an operator.

const Grammar := preload("res://lingo/compile/lingo_grammar.gd")

## "nl" | "number" | "string" | "symbol" | "ident" | "kw" | "op" | "eof"
var kinds := PackedStringArray()
var values := PackedStringArray()
var lines := PackedInt32Array()
var error := ""
var error_line := 0

const _TAB := 9
const _LF := 10
const _SPACE := 32
const _QUOTE := 34
const _BACKSLASH := 92
const _MINUS := 45
const _HASH := 35
const _DOT := 46
const _ZERO := 48
const _NINE := 57
const _UPPER_A := 65
const _UPPER_Z := 90
const _UNDERSCORE := 95
const _LOWER_A := 97
const _LOWER_Z := 122


func tokenize(source: String) -> bool:
	kinds = PackedStringArray()
	values = PackedStringArray()
	lines = PackedInt32Array()
	error = ""
	error_line = 0

	# The `.ls` files use CRLF and the text inside a container uses bare CR. The
	# Python's newline pattern is `\r?\n`, which does not match a lone CR at all,
	# so feeding it container text fails on the first line. Normalising here
	# means one newline rule for both sources and identical line numbers.
	var src := source.replace("\r\n", "\n").replace("\r", "\n")
	var length := src.length()
	var at := 0
	var line := 1

	while at < length:
		var c := src.unicode_at(at)

		if c == _SPACE or c == _TAB:
			at += 1
			continue

		# `--` to end of line. Before the operator test, or it lexes as minus.
		if c == _MINUS and at + 1 < length and src.unicode_at(at + 1) == _MINUS:
			while at < length and src.unicode_at(at) != _LF:
				at += 1
			continue

		# A backslash, any spacing, then a newline: the line continues, and the
		# line number advances without a token being emitted.
		if c == _BACKSLASH:
			var scan := at + 1
			while scan < length and _is_space(src.unicode_at(scan)):
				scan += 1
			if scan < length and src.unicode_at(scan) == _LF:
				line += 1
				at = scan + 1
				continue
			error = "stray backslash"
			error_line = line
			return false

		if c == _LF:
			_push("nl", "\n", line)
			line += 1
			at += 1
			continue

		# **`.4` is a float unless a `.` was just emitted**, in which case the two
		# dots are Director's range operator and this one is the second half of
		# it. `x.char[1..3]` lexes `1`, then `.` (rejected as a float below,
		# because the character after it is another dot), and then reached here
		# with `.3` -- a number. The parser's range arm read `1` and `0.3`, took
		# `to_int(0.3)` as 0, saw a stop below the start and answered the single
		# chunk at the start. So `x.char[1..3]` was `x.char[1]`: a range that
		# silently narrowed, which is the accept-and-drop shape §19 is about.
		#
		# The leading-dot float itself is real Lingo (`put .5` is 0.5) and the
		# header records that its rule wins over the operator; this narrows *that*
		# rule by one case rather than removing it. Nothing else can put a `.`
		# immediately before a leading-dot number: the dot operator's other job is
		# property access, and `x..5` is not an expression in any spelling.
		#
		# 0 range sites in all six shipped titles and in the two D5 corpora --
		# they spell chunks one at a time -- so this is built from the reference
		# rather than measured against a script, and the probe that exercises it
		# is `"abcdef".char[2..4]` answering "bcd".
		var dot_float: bool = c == _DOT and at + 1 < length \
			and _is_digit(src.unicode_at(at + 1)) \
			and not (kinds.size() > 0 and kinds[kinds.size() - 1] == "op"
				and values[values.size() - 1] == ".")
		if _is_digit(c) or dot_float:
			var start := at
			while at < length and _is_digit(src.unicode_at(at)):
				at += 1
			if at < length and src.unicode_at(at) == _DOT and at + 1 < length \
					and _is_digit(src.unicode_at(at + 1)):
				at += 1
				while at < length and _is_digit(src.unicode_at(at)):
					at += 1
			_push("number", src.substr(start, at - start), line)
			continue

		if c == _QUOTE:
			var open_line := line
			var from := at + 1
			at = from
			# A string may not span lines; an unterminated one is an error rather
			# than something to close at the newline.
			while at < length and src.unicode_at(at) != _QUOTE and src.unicode_at(at) != _LF:
				at += 1
			if at >= length or src.unicode_at(at) == _LF:
				error = "unterminated string"
				error_line = open_line
				return false
			_push("string", src.substr(from, at - from), open_line)
			at += 1
			continue

		# `#name` -- a symbol literal (§11.2, §11.13 rule 20). The `#` is not an
		# operator and there is no expression it could begin: it is stripped and
		# the name is the value.
		#
		# Absent until now, and it failed *loudly* -- "unexpected character" --
		# which is why §16.2 could record it as a known gap for as long as no
		# script in the corpus wrote one. It is the spelling every object message
		# is written in (`call(#mouseUp, obj)`), so the messaging half of §7.1
		# could not be reached without it.
		#
		# The name is lexed with the identifier rule so `#a.b` matches whatever
		# `member.name` matches, which is the one place a dot is part of a word.
		if c == _HASH and at + 1 < length and _is_ident_start(src.unicode_at(at + 1)):
			var sym_start := at + 1
			at = sym_start + 1
			while at < length and _is_ident_body(src.unicode_at(at)):
				at += 1
			_push("symbol", src.substr(sym_start, at - sym_start), line)
			continue

		if _is_ident_start(c):
			var ident_start := at
			at += 1
			while at < length and _is_ident_body(src.unicode_at(at)):
				at += 1
			var text := src.substr(ident_start, at - ident_start)
			_push("kw" if Grammar.KEYWORDS.has(text.to_lower()) else "ident", text, line)
			continue

		var two := src.substr(at, 2)
		if Grammar.LONG_OPERATORS.has(two):
			_push("op", two, line)
			at += 2
			continue
		var one := src.substr(at, 1)
		if Grammar.SHORT_OPERATORS.contains(one):
			_push("op", one, line)
			at += 1
			continue

		error = "unexpected character %s" % JSON.stringify(one)
		error_line = line
		return false

	_push("eof", "", line)
	return true


func size() -> int:
	return kinds.size()


## A readable dump of the stream, for a tool that wants to show what it lexed.
func describe(limit: int = 40) -> String:
	var out := PackedStringArray()
	for i in mini(limit, kinds.size()):
		var shown := values[i] if kinds[i] != "nl" else "\\n"
		out.append("%s:%s@%d" % [kinds[i], shown, lines[i]])
	return " ".join(out)


func _push(kind: String, value: String, line: int) -> void:
	kinds.append(kind)
	values.append(value)
	lines.append(line)


static func _is_space(c: int) -> bool:
	return c == _SPACE or c == _TAB


static func _is_digit(c: int) -> bool:
	return c >= _ZERO and c <= _NINE


static func _is_ident_start(c: int) -> bool:
	return (c >= _UPPER_A and c <= _UPPER_Z) or (c >= _LOWER_A and c <= _LOWER_Z) or c == _UNDERSCORE


## **A dot is not part of an identifier.**
##
## It used to be, "exactly as in the Python", so `myObject.pTag` lexed as one
## token called `myobject.ptag` and every dot access whose receiver is a *bare
## variable* resolved to an unset name. `member(x).name` was unaffected -- the
## dot there follows a `)`, which is not an identifier character -- which is
## exactly why the hole survived: the corpus's only dot spelling is the one shape
## the rule did not break, and §7.1's `obj.someProperty` is the one it did.
##
## Measured before changing rather than reasoned about, because the rule was
## inherited and might have been load-bearing: **0 identifier tokens contain a
## dot across all 38,396 scripts in the six titles.** Nothing in this corpus can
## tell the two readings apart, and Director's own lexer has no such rule.
static func _is_ident_body(c: int) -> bool:
	return _is_ident_start(c) or _is_digit(c)
