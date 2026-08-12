class_name LingoValue
extends RefCounted
## Lingo value semantics, which differ from GDScript's in ways that matter.
##
## Verified against the language, not guessed: string comparison is
## case-insensitive, `/` between two integers truncates, chunk indices are
## 1-based, and `&&` joins with a space where `&` does not.

const CR := "\r"

## `the floatPrecision` — how many decimal places a float shows when it becomes a
## string. Director's default is 4 and its range is 0..19.
##
## Static rather than per-host because it is one setting for the whole session in
## Director too, and because `to_str` is static: threading a host through every
## coercion in the port to carry one integer would touch every call site of the
## commonest function in this file.
##
## **This changes what a whole float prints as, and it is now applied.** The rule
## in `to_str` used to be "print a whole float without a decimal part", which made
## `float(1)` come out as `1`; Director formats every float with the current
## precision, so the same value is `1.0000`. The reference settles it: the write
## arm for this property compiles a printf format from the value
## (`"%%.%df"`), and that format is the language's only float-to-string path.
static var float_precision := 4


static func to_num(value: Variant) -> Variant:
	## Numbers pass through; strings coerce as far as they parse, else 0.
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return value
		TYPE_BOOL:
			return 1 if value else 0
		TYPE_NIL:
			return 0
		TYPE_STRING:
			var text := (value as String).strip_edges()
			if text.is_valid_int():
				return text.to_int()
			if text.is_valid_float():
				return text.to_float()
			return 0
		_:
			# `sprite(n)` is a reference rather than a number (see
			# `lingo_sprite_ref.gd`), and every consumer that wants a channel
			# number gets one here -- comparisons, arithmetic, `sendSprite`, and
			# each host call that takes a channel. Unwrapping in this one place
			# is what let the type be added without touching them.
			if value is LingoSpriteRef:
				return (value as LingoSpriteRef).channel
			return 0


static func to_int(value: Variant) -> int:
	return int(to_num(value))


static func to_str(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING:
			return value
		TYPE_NIL:
			return ""
		TYPE_FLOAT:
			# **Every float becomes a string through `the floatPrecision`.**
			#
			# Settled from the reference rather than left open. `lingo-the.cpp`'s
			# write arm for the property does not merely store it: it builds a
			# printf format out of it on the spot -- `"%%.%df"`, so `%.4f` at the
			# default -- and that format exists for one purpose. So `3.0` prints
			# as `3.0000` at 4, `3.1416` for pi, and `3` once a movie sets the
			# precision to 0.
			#
			# §8.17 recorded the opposite ("whole floats print without a decimal
			# part", `put 3.0` showing `3`) and that rule is what this arm used to
			# implement. It is wrong, and it was wrong in the direction that
			# hides: a whole float is exactly the case where the two rules differ,
			# and a script comparing `string(x)` against a literal was authored
			# against Director's answer, not this one.
			#
			# A half-applied version shipped neither: `String.num` trims trailing
			# zeros, so it produced `3.0`.
			return ("%%.%df" % clampi(float_precision, 0, 19)) % (value as float)
		TYPE_BOOL:
			return "1" if value else "0"
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append(to_str(item))
			return "[" + ", ".join(parts) + "]"
		_:
			return str(value)


static func truthy(value: Variant) -> bool:
	# A **script object is true** (§7.1). `to_num` has no arm for one and answers
	# 0, so without this `if myObject then` and `if the perFrameHook then` are
	# false for an object that exists -- and `set the perFrameHook to me` stored
	# nothing, because its setter asks this question. VOID is still false, which
	# is what tells "no object" from "an object".
	if typeof(value) == TYPE_OBJECT:
		return value != null
	if typeof(value) == TYPE_STRING:
		var text := (value as String).to_lower()
		if text == "true":
			return true
		if text == "false" or text == "":
			return false
		return to_num(value) != 0
	return to_num(value) != 0


static func is_numeric(value: Variant) -> bool:
	var t := typeof(value)
	if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL or t == TYPE_NIL:
		return true
	if t != TYPE_STRING:
		return false
	var text := (value as String).strip_edges()
	return text != "" and (text.is_valid_int() or text.is_valid_float())


## Whether two names mean the same Director container is a format question, not
## a value-coercion one, so it lives in `director_container.gd` and is consulted
## from here. `lingo/` otherwise does not reach into `director/`; it does for
## this because the alternative is a second copy of the rule, and a rule kept in
## two places is a rule that will disagree with itself.
const ContainerName := preload("res://director/director_container.gd")


static func equal(a: Variant, b: Variant) -> bool:
	## Lingo compares strings without regard to case.
	if is_numeric(a) and is_numeric(b):
		return is_equal_approx(float(to_num(a)), float(to_num(b)))
	var sa := to_str(a).to_lower()
	var sb := to_str(b).to_lower()
	if sa == sb:
		return true
	# `day1.dxr` and `day1.dir` are one movie in two packagings. See
	# `director_container.gd` for why this belongs in equality rather than in
	# whatever supplies `the movieName`.
	return ContainerName.same(sa, sb)


static func compare(a: Variant, b: Variant) -> int:
	if is_numeric(a) and is_numeric(b):
		var fa := float(to_num(a))
		var fb := float(to_num(b))
		if is_equal_approx(fa, fb):
			return 0
		return -1 if fa < fb else 1
	var sa := to_str(a).to_lower()
	var sb := to_str(b).to_lower()
	if sa == sb or ContainerName.same(sa, sb):
		return 0
	return -1 if sa < sb else 1


## Arithmetic maps over a list, element by element, when either side is one.
##
## **This is how Director does point and rect maths**, and it is not an extra on
## top of the scalar rule -- it is the first thing every arithmetic operator
## checks (`LC::addData`, `subData`, `mulData`, `divData`, `modData`, all five
## delegating to `LC::mapBinaryOp`). A port that answers only the scalar case
## does not merely lose points: `to_num` of a list is 0, so
## `point(3, 4) + point(1, 1)` comes back as the integer `0`, and every caller
## downstream is then working with a number where it asked for a position.
##
## Magic Hat is where that surfaced. Its `HideSprite` is the standard Director
## idiom for parking a sprite off-stage:
##
##     on HideSprite spr
##       if sprite(spr).locH < 0 then exit
##       sprite(spr).loc = sprite(spr).loc + point(-1000, -1000)
##
## The addition answered 0, `set the loc of sprite` requires a pair and drops
## anything shorter, and the write vanished. The visible result was that the
## title's full-stage `black` fade curtain -- two 800x600 shape sprites the score
## parks in channels 24 and 50 -- was never moved away, so it covered the main
## menu completely and the player saw a blank stage with the music playing.
##
## Rules taken from `mapBinaryOp`: both lists, and the result is as long as the
## *shorter*; one list and one scalar, and the scalar is broadcast across every
## element; the mapped function is the operator itself, so nested lists work by
## recursion. This port has no distinct POINT or RECT type -- a point is the
## two-element list `the loc of sprite` already answers -- so the reference's
## type-alignment half has nothing to align and the result is always a list.
## A list, a point or a rect as a plain Array of components; `[]` for anything
## else.
##
## **Director's point and rect are lists**, which is why `count(point(1, 2))` is
## 2 and `getAt(r, 3)` is a rect's right edge -- `lingo_builtins.gd` already
## answers both. This port stores them as `Vector2` and `Rect2`, so every rule
## written against "is it an array" has to come through here or it answers no to
## two thirds of Director's list types. A `Rect2` is position-and-size and
## Director's rect is left-top-right-bottom, so the conversion is part of the
## flattening rather than something a caller remembers.
##
## Public because it has callers outside this file. `director_preview.gd`'s
## `the loc of sprite` writer already reached in for it under its old private
## spelling, and `preview/members.gd:write_prop` needs it for the same reason:
## `member(i).regPoint = point(x, y)` and `member(i).regPoint = sprite(n).loc`
## hand it a `Vector2` and an `Array` for one Director type, and a second
## flattener written next to either one is how they start disagreeing.
static func components(value: Variant) -> Array:
	match typeof(value):
		TYPE_ARRAY:
			return value
		TYPE_VECTOR2:
			var point: Vector2 = value
			return [point.x, point.y]
		TYPE_RECT2:
			var box: Rect2 = value
			return [box.position.x, box.position.y,
				box.position.x + box.size.x, box.position.y + box.size.y]
	return []


static func _either_is_list(a: Variant, b: Variant) -> bool:
	return _is_list(a) or _is_list(b)


static func _is_list(value: Variant) -> bool:
	var kind := typeof(value)
	return kind == TYPE_ARRAY or kind == TYPE_VECTOR2 or kind == TYPE_RECT2


## Which of the three types the result wears, from `LC::getArrayAlignedType`.
##
## The left operand decides, but only while the right one has a compatible
## length: a point plus a four-element list is a plain list, not a point, because
## there is no point that could hold the answer. A scalar on the left defers to
## whatever the right side is, which is what makes `2 * point(3, 4)` a point.
static func _aligned_type(a: Variant, b: Variant) -> int:
	var ka := typeof(a)
	var kb := typeof(b)
	if ka == TYPE_VECTOR2:
		if kb == TYPE_RECT2 or (kb == TYPE_ARRAY and (b as Array).size() != 2):
			return TYPE_ARRAY
		return TYPE_VECTOR2
	if ka == TYPE_RECT2:
		if kb == TYPE_VECTOR2 or (kb == TYPE_ARRAY and (b as Array).size() != 4):
			return TYPE_ARRAY
		return TYPE_RECT2
	if not _is_list(a):
		return kb
	return TYPE_ARRAY


static func _rebuild(kind: int, parts: Array) -> Variant:
	if kind == TYPE_VECTOR2 and parts.size() == 2:
		return Vector2(to_num(parts[0]), to_num(parts[1]))
	if kind == TYPE_RECT2 and parts.size() == 4:
		var left := float(to_num(parts[0]))
		var top := float(to_num(parts[1]))
		return Rect2(left, top, float(to_num(parts[2])) - left, float(to_num(parts[3])) - top)
	return parts


static func _map_pairwise(a: Variant, b: Variant, op: Callable) -> Variant:
	var a_list := _is_list(a)
	var b_list := _is_list(b)
	var left := components(a)
	var right := components(b)
	var size := 0
	if a_list and b_list:
		size = mini(left.size(), right.size())
	elif a_list:
		size = left.size()
	else:
		size = right.size()
	var out: Array = []
	out.resize(size)
	for i in size:
		out[i] = op.call(left[i] if a_list else a, right[i] if b_list else b)
	return _rebuild(_aligned_type(a, b), out)


static func add(a: Variant, b: Variant) -> Variant:
	if _either_is_list(a, b):
		return _map_pairwise(a, b, Callable(LingoValue, "add"))
	var na: Variant = to_num(a)
	var nb: Variant = to_num(b)
	if typeof(na) == TYPE_INT and typeof(nb) == TYPE_INT:
		return int(na) + int(nb)
	return float(na) + float(nb)


static func sub(a: Variant, b: Variant) -> Variant:
	if _either_is_list(a, b):
		return _map_pairwise(a, b, Callable(LingoValue, "sub"))
	var na: Variant = to_num(a)
	var nb: Variant = to_num(b)
	if typeof(na) == TYPE_INT and typeof(nb) == TYPE_INT:
		return int(na) - int(nb)
	return float(na) - float(nb)


static func mul(a: Variant, b: Variant) -> Variant:
	if _either_is_list(a, b):
		return _map_pairwise(a, b, Callable(LingoValue, "mul"))
	var na: Variant = to_num(a)
	var nb: Variant = to_num(b)
	if typeof(na) == TYPE_INT and typeof(nb) == TYPE_INT:
		return int(na) * int(nb)
	return float(na) * float(nb)


static func div(a: Variant, b: Variant) -> Variant:
	## Integer division when both sides are integers, as Director does. Getting
	## this wrong silently changes arithmetic in scripts that index by division.
	if _either_is_list(a, b):
		return _map_pairwise(a, b, Callable(LingoValue, "div"))
	var na: Variant = to_num(a)
	var nb: Variant = to_num(b)
	if typeof(na) == TYPE_INT and typeof(nb) == TYPE_INT:
		if int(nb) == 0:
			return 0
		return int(na) / int(nb)
	if is_zero_approx(float(nb)):
		return 0
	return float(na) / float(nb)


static func modulo(a: Variant, b: Variant) -> Variant:
	if _either_is_list(a, b):
		return _map_pairwise(a, b, Callable(LingoValue, "modulo"))
	var ia := to_int(a)
	var ib := to_int(b)
	if ib == 0:
		return 0
	return ia % ib


static func concat(a: Variant, b: Variant) -> String:
	return to_str(a) + to_str(b)


static func concat_space(a: Variant, b: Variant) -> String:
	return to_str(a) + " " + to_str(b)


## `contains` and `starts` reconcile container packaging the same way `=` does.
##
## Equality alone is not enough, because a title is free to test its packaging
## any way Lingo allows. This game happens to write `the movieName = "day1.dxr"`
## and `the movieName contains "hotel"`, but `the movieName contains "dxr"` is
## just as natural to write and would fail against a converted `.dir` for exactly
## the same reason -- silently, and gating whatever the author put behind it.
##
## So when the haystack is a container name it is tested under every spelling of
## itself. A haystack that is not a container name is untouched, which keeps
## `"notes.txt" contains "dxr"` false.
static func contains(haystack: Variant, needle: Variant) -> bool:
	var text := to_str(haystack).to_lower()
	var want := to_str(needle).to_lower()
	for spelling in ContainerName.alternatives(text):
		if str(spelling).find(want) >= 0:
			return true
	return false


static func starts(haystack: Variant, needle: Variant) -> bool:
	var text := to_str(haystack).to_lower()
	var want := to_str(needle).to_lower()
	for spelling in ContainerName.alternatives(text):
		if str(spelling).begins_with(want):
			return true
	return false


static func split_lines(text: String) -> PackedStringArray:
	## Director separates lines with CR. Decoded text and hand-written data both
	## turn up with LF or CRLF, so accept all three.
	return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


static func join_lines(parts: PackedStringArray) -> String:
	return "\n".join(parts)


static func chunk_parts(text: String, kind: String, delimiter: String = ",") -> PackedStringArray:
	match kind:
		# `paragraph` is D7's name for the same chunk `line` names, and Director
		# keeps both. It differs from `line` only inside a rich-text member,
		# where a paragraph is a styled run that soft-wraps across several
		# displayed lines; on the plain strings and field text this port splits,
		# a paragraph *is* a line. Written as an alias rather than left to the
		# default arm, which returns the whole text as one part and would make
		# `x.paragraph[2]` answer the entire string.
		#
		# Unverified against the corpus: 0 sites in any of the six titles. Built
		# because Director has it (`AGENTS.md`), and reachable only through the
		# dot spelling — see `LingoGrammar.DOT_CHUNKS` for why the word is not a
		# lexer keyword.
		"line", "paragraph":
			return split_lines(text)
		"item":
			return text.split(delimiter)
		"word":
			var words := PackedStringArray()
			for piece in text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" "):
				if piece != "":
					words.append(piece)
			return words
		"char":
			var chars := PackedStringArray()
			for i in text.length():
				chars.append(text[i])
			return chars
		_:
			return PackedStringArray([text])


static func chunk_separator(kind: String, delimiter: String = ",") -> String:
	match kind:
		"line", "paragraph":
			return "\n"
		"item":
			return delimiter
		"word":
			return " "
		_:
			return ""


static func get_chunk(text: String, kind: String, start: int, stop: int,
		delimiter: String = ",") -> String:
	## 1-based and inclusive. Out of range yields "" rather than an error, which
	## is what Director does and what the scripts rely on.
	var parts := chunk_parts(text, kind, delimiter)
	if parts.is_empty() or start < 1:
		return ""
	var last := stop if stop >= start else start
	if start > parts.size():
		return ""
	last = mini(last, parts.size())
	var slice := PackedStringArray()
	for i in range(start - 1, last):
		slice.append(parts[i])
	return chunk_separator(kind, delimiter).join(slice)


static func set_chunk(text: String, kind: String, start: int, stop: int,
		value: Variant, delimiter: String = ",") -> String:
	## Writing past the end grows the text, because `put x into line 30 of field`
	## is how the scripts initialise fields.
	if start < 1:
		return text
	var parts := chunk_parts(text, kind, delimiter)
	var last := stop if stop >= start else start
	while parts.size() < start - 1:
		parts.append("")
	var head := PackedStringArray()
	for i in range(0, mini(start - 1, parts.size())):
		head.append(parts[i])
	var tail := PackedStringArray()
	for i in range(mini(last, parts.size()), parts.size()):
		tail.append(parts[i])
	var out := PackedStringArray()
	out.append_array(head)
	out.append(to_str(value))
	out.append_array(tail)
	return chunk_separator(kind, delimiter).join(out)


## `delete <chunk> of <place>` -- the chunk **and its separator** come out.
##
## Not `set_chunk(..., "")`, which is the difference that makes the statement
## work at all: putting "" into `word 1` of `"a b c"` leaves `" b c"`, so a
## script that deletes the first word in a loop and tests the string for EMPTY
## never terminates. Director removes the separator with the chunk, so the same
## loop shortens the string every pass and ends.
##
## The separator taken is the one *after* the chunk, or the one before it when
## the chunk runs to the end -- which is what keeps `delete line 3 of x` from
## leaving a trailing empty line on a three-line string.
##
## `char` has no separator, so the two readings agree there and the arm is the
## general one.
static func delete_chunk(text: String, kind: String, start: int, stop: int,
		delimiter: String = ",") -> String:
	if start < 1:
		return text
	var parts := chunk_parts(text, kind, delimiter)
	var last := stop if stop >= start else start
	if start > parts.size():
		return text
	var out := PackedStringArray()
	for i in parts.size():
		if i >= start - 1 and i <= mini(last, parts.size()) - 1:
			continue
		out.append(parts[i])
	return chunk_separator(kind, delimiter).join(out)


static func count_of(text: String, unit: String, delimiter: String = ",") -> int:
	if unit == "char":
		return text.length()
	var parts := chunk_parts(text, unit, delimiter)
	if unit == "line" or unit == "paragraph":
		# Director counts a trailing empty line as absent.
		while parts.size() > 1 and parts[parts.size() - 1] == "":
			parts.remove_at(parts.size() - 1)
	return parts.size()
