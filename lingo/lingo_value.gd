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


static func add(a: Variant, b: Variant) -> Variant:
	var na: Variant = to_num(a)
	var nb: Variant = to_num(b)
	if typeof(na) == TYPE_INT and typeof(nb) == TYPE_INT:
		return int(na) + int(nb)
	return float(na) + float(nb)


static func sub(a: Variant, b: Variant) -> Variant:
	var na: Variant = to_num(a)
	var nb: Variant = to_num(b)
	if typeof(na) == TYPE_INT and typeof(nb) == TYPE_INT:
		return int(na) - int(nb)
	return float(na) - float(nb)


static func mul(a: Variant, b: Variant) -> Variant:
	var na: Variant = to_num(a)
	var nb: Variant = to_num(b)
	if typeof(na) == TYPE_INT and typeof(nb) == TYPE_INT:
		return int(na) * int(nb)
	return float(na) * float(nb)


static func div(a: Variant, b: Variant) -> Variant:
	## Integer division when both sides are integers, as Director does. Getting
	## this wrong silently changes arithmetic in scripts that index by division.
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
		"line":
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
		"line":
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


static func count_of(text: String, unit: String, delimiter: String = ",") -> int:
	if unit == "char":
		return text.length()
	var parts := chunk_parts(text, unit, delimiter)
	if unit == "line":
		# Director counts a trailing empty line as absent.
		while parts.size() > 1 and parts[parts.size() - 1] == "":
			parts.remove_at(parts.size() - 1)
	return parts.size()
