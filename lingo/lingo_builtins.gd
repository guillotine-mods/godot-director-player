class_name LingoBuiltins
extends RefCounted
## Director's title-agnostic builtins: the half of Lingo's surface that needs no
## engine behind it.
##
## `docs/LINGO_SURFACE.md` §1 is the specification, and everything here is a
## function of its arguments alone — no score, no cast, no sprites, no host.
## That is what makes it reusable: Piposh 1, Rating and any other Director title
## reach for the same `getAt` and the same `random`, and none of them should
## need this file changed. Nothing in it may learn which game is loaded. A name
## that needs the playhead, a member, a channel or a sound belongs in the host
## (`lingo/lingo_host.gd`), not here, and is deliberately absent below.
##
## Coercion is not reimplemented. `LingoValue` already owns `to_num`, `to_str`,
## `equal`, `compare`, the integer-division rule and the chunk splitter; a
## second set of rules here would be a second set of bugs, and they would drift.
##
##   var handled: Array = []
##   var value: Variant = LingoBuiltins.call_builtin("getAt", [list, 2], handled)
##   if handled.is_empty():
##       ...  # not ours: try the host, then report it
##
## `handled` is an out-parameter rather than a sentinel return because VOID is a
## legitimate answer: `findPos` on a missing key, `getAt` past the end and
## `void()` itself all return VOID, and a caller that read null as "no such
## builtin" would report every one of them as a missing binding.
##
## ## How values are represented
##
##   linear list     Array
##   property list   Dictionary, insertion-ordered, string keys
##   symbol          StringName
##   point           Vector2
##   rect            Rect2
##   VOID            null
##   TRUE / FALSE    1 / 0
##
## None of that is invented here. `lingo_interpreter.gd` already evaluates
## `[a, b]` to an Array and `[a: b]` to a Dictionary, and `lingo_host.gd`
## already answers sprite rectangles as `Rect2`. Two representations for one
## value is how a port grows a conversion at every boundary.
##
## The Dictionary costs one thing, recorded rather than worked around: Director
## property lists may hold the same key twice and a Godot Dictionary may not, so
## `addProp` on a key that is already there overwrites where Director would
## append a second pair. The alternative is a bespoke ordered-pair type that
## every other file in the port would then have to understand.
##
## Wrong-typed and out-of-range arguments answer VOID or 0 and never raise,
## because that is what Director does (§8) and what the scripts are written
## against. A raise here would turn a script that has always run into a dead
## handler.

## Lists and property lists that `sort` has touched. `add` and `addProp` insert
## in order on these and append on everything else (§1.3, §8.13) — a behaviour
## that is invisible until a menu comes out in the wrong order.
##
## A Godot Array carries no room for a flag, so identity is tracked here
## instead. The registry is bounded because a reference held here keeps the list
## alive: the case worth serving is a long-lived sorted list, and the oldest
## entry is the one least likely to still be one. A list that falls out of the
## registry does not break — `add` reverts to appending, which is what an
## unsorted list does anyway.
const SORTED_TRACKED := 256

static var _sorted: Array = []

## `the randomSeed`. Director's `random` is seedable and a title that seeds it is
## asking for the same sequence twice — a demo that replays, a puzzle that deals
## the same board. 0 means "never seeded", and then `random` draws from the
## process-wide generator, which is what an unseeded Director does.
##
## The seed is held with the generator that consumes it rather than on the host,
## so there is no second copy to disagree with the sequence it describes. It is
## read back as written: Director answers the seed, not the generator's position.
static var _random_seed := 0
static var _rng: RandomNumberGenerator = null


static func random_seed() -> int:
	return _random_seed


static func set_random_seed(value: int) -> void:
	_random_seed = value
	if value == 0:
		_rng = null
		return
	_rng = RandomNumberGenerator.new()
	_rng.seed = value


static func call_builtin(name: String, args: Array, handled: Array) -> Variant:
	## Name matching is case-insensitive: Lingo is, and the corpus spells
	## `getAt`, `getat` and `GetAt` in the same movie.
	var key := name.to_lower()
	var out: Array = []
	if _constants(key, args, out) \
			or _math(key, args, out) \
			or _strings(key, args, out) \
			or _lists(key, args, out) \
			or _predicates(key, args, out) \
			or _geometry(key, args, out) \
			or _time(key, args, out):
		handled.append(true)
		return out[0]
	return null


# --- arguments -----------------------------------------------------------


static func _arg(args: Array, index: int) -> Variant:
	## A missing argument is VOID, not an error. Lingo calls a two-argument
	## builtin with one argument more often than a port expects.
	if index < 0 or index >= args.size():
		return null
	var value: Variant = args[index]
	return value


static func _f(value: Variant) -> float:
	return float(LingoValue.to_num(value))


static func _i(value: Variant) -> int:
	return LingoValue.to_int(value)


static func _s(value: Variant) -> String:
	return LingoValue.to_str(value)


# --- constants (§1.15) ---------------------------------------------------


static func _constants(key: String, args: Array, out: Array) -> bool:
	## These are bare words, so a call carrying arguments is a different thing
	## wearing the same name. `return` is the clearest case — it is both this
	## constant and the control-flow statement (§1) — and `pi`, `void` and the
	## rest are only ever the constant at zero arity. Refusing the call form
	## here leaves the collision for the caller to resolve instead of guessing.
	if not args.is_empty():
		return false
	match key:
		"backspace":
			out.append(String.chr(8))
		"empty":
			out.append("")
		"enter":
			# ENTER is the keypad Enter, character 3 — not RETURN, which is the
			# carriage return below. Scripts that test `the key` against one and
			# not the other depend on them differing.
			out.append(String.chr(3))
		"quote":
			out.append("\"")
		"return", "cr":
			# Director's RETURN is CR. This port normalises every line separator
			# to LF (`LingoValue.split_lines` / `join_lines`) and the
			# interpreter's own constant table already answers "\n", so
			# answering "\r" here would put two different separators into the
			# same field and only one of them would round-trip.
			out.append("\n")
		"tab":
			out.append("\t")
		"true":
			out.append(1)
		"false":
			out.append(0)
		"void":
			out.append(null)
		"pi":
			out.append(PI)
		_:
			return false
	return true


# --- math (§1.1) ---------------------------------------------------------


static func _math(key: String, args: Array, out: Array) -> bool:
	match key:
		"abs":
			# Type-preserving, because `abs(-7)/2` is 3 and `abs(-7.0)/2` is 3.5
			# (§2.1). A float-only `abs` silently moves every such expression
			# onto the float path.
			var n: Variant = LingoValue.to_num(_arg(args, 0))
			if typeof(n) == TYPE_INT:
				out.append(absi(int(n)))
			else:
				out.append(absf(float(n)))
		"atan":
			out.append(atan(_f(_arg(args, 0))))
		"cos":
			out.append(cos(_f(_arg(args, 0))))
		"exp":
			out.append(exp(_f(_arg(args, 0))))
		"float":
			out.append(_f(_arg(args, 0)))
		"integer":
			# The doc says "coerce to integer, **rounding**" (§1.1), which is not
			# what `LingoValue.to_int` does — that truncates, correctly, because
			# it serves the arithmetic path. Following the doc over the
			# convenient helper: `integer(3.7)` is 4, and half rounds away from
			# zero, so `integer(-3.5)` is -4.
			var value: Variant = LingoValue.to_num(_arg(args, 0))
			if typeof(value) == TYPE_INT:
				out.append(int(value))
			else:
				out.append(int(roundf(float(value))))
		"log":
			# Director answers rather than raising, and a NAN or -INF here would
			# poison every comparison downstream instead of failing where it
			# happened.
			var x := _f(_arg(args, 0))
			out.append(log(x) if x > 0.0 else 0.0)
		"power":
			out.append(pow(_f(_arg(args, 0)), _f(_arg(args, 1))))
		"random":
			# 1..n **inclusive** (§1.1, §8.11). The classic port off-by-one: a
			# 0-based version shifts every "one of N" choice and never picks the
			# last option. Below 1 there is nothing to choose, so 0.
			var span := _i(_arg(args, 0))
			if span < 1:
				out.append(0)
			elif _rng != null:
				out.append(_rng.randi_range(1, span))
			else:
				out.append(randi_range(1, span))
		"sin":
			out.append(sin(_f(_arg(args, 0))))
		"sqrt":
			var s := _f(_arg(args, 0))
			out.append(sqrt(s) if s >= 0.0 else 0.0)
		"tan":
			out.append(tan(_f(_arg(args, 0))))
		_:
			return false
	return true


# --- strings (§1.2) ------------------------------------------------------


static func _strings(key: String, args: Array, out: Array) -> bool:
	match key:
		"chars":
			# 1-based and inclusive, via the port's own chunk rule so that
			# `chars(x, 2, 4)` and `char 2 to 4 of x` cannot disagree.
			if args.size() < 3:
				out.append("")
			else:
				out.append(LingoValue.get_chunk(
					_s(_arg(args, 0)), "char", _i(_arg(args, 1)), _i(_arg(args, 2))))
		"chartonum":
			var text := _s(_arg(args, 0))
			out.append(text.unicode_at(0) if text.length() > 0 else 0)
		"length":
			out.append(_s(_arg(args, 0)).length())
		"numtochar":
			var code := _i(_arg(args, 0))
			out.append(String.chr(code) if code >= 0 else "")
		"offset":
			out.append(_offset(args))
		"string":
			out.append(_s(_arg(args, 0)))
		"value":
			out.append(_value_of(_arg(args, 0)))
		"numberofchars", "numberofitems", "numberoflines", "numberofwords":
			# The call spelling of a chunk count the interpreter already answers
			# for `the number of lines in X` (§1.2), so it delegates to the same
			# `LingoValue.count_of` rather than counting again. Two answers to
			# one question is the failure worth avoiding here; matching Director
			# exactly on an empty string matters less than the two agreeing.
			#
			# `the itemDelimiter` is engine state and this module holds none, so
			# `numberOfItems` uses the default comma. A host with a mutable
			# delimiter passes it as an optional second argument (§8.7).
			var unit := key.substr(8).to_lower()
			if unit == "chars":
				unit = "char"
			elif unit == "items":
				unit = "item"
			elif unit == "lines":
				unit = "line"
			else:
				unit = "word"
			var delimiter: String = _s(_arg(args, 1)) if args.size() > 1 else ","
			out.append(LingoValue.count_of(_s(_arg(args, 0)), unit, delimiter))
		_:
			return false
	return true


static func _offset(args: Array) -> int:
	## 1-based, 0 when absent (§1.2, §8.12) — GDScript's `find` needs both its
	## `+1` and its `-1 -> 0`, and a port that gets only one half right is
	## correct except when the needle sits at the very start.
	##
	## Case-insensitive, because every string comparison in Lingo is (§2.2).
	var needle := _s(_arg(args, 0)).to_lower()
	var hay := _s(_arg(args, 1)).to_lower()
	if needle == "":
		# The doc does not say. "Not found" is the safer of the two answers:
		# reporting position 1 makes `if offset(x, y) then` fire on an empty
		# needle, which is never what the script meant.
		return 0
	var from := 0
	if args.size() > 2:
		from = maxi(_i(_arg(args, 2)) - 1, 0)
	return hay.find(needle, from) + 1


static func _value_of(raw: Variant) -> Variant:
	## `value` parses; it does not coerce (§1.2). A number answers itself, a
	## list or property-list literal answers the built container, and anything
	## else is a Lingo expression this module cannot evaluate — VOID, not 0,
	## because §8.6 is explicit that the two are not interchangeable and VOID
	## still counts as 0 in arithmetic where the reverse is not true.
	if typeof(raw) != TYPE_STRING:
		return raw
	var text := (raw as String).strip_edges()
	if text == "":
		return null
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	if text.begins_with("[") and text.ends_with("]"):
		return _parse_container(text)
	return null


static func _parse_container(text: String) -> Variant:
	var inner := text.substr(1, text.length() - 2).strip_edges()
	if inner == ":":
		return {}
	if inner == "":
		return []
	var parts := _split_top_level(inner)
	var keyed := true
	for part in parts:
		if _top_colon(part) < 0:
			keyed = false
			break
	if keyed:
		var dict := {}
		for part in parts:
			var at := _top_colon(part)
			var name := part.substr(0, at).strip_edges()
			if name.begins_with("#") or name.begins_with("\""):
				name = name.trim_prefix("#").trim_prefix("\"").trim_suffix("\"")
			dict[name] = _parse_scalar(part.substr(at + 1))
		return dict
	var list: Array = []
	for part in parts:
		list.append(_parse_scalar(part))
	return list


static func _parse_scalar(part: String) -> Variant:
	var text := part.strip_edges()
	if text.length() >= 2 and text.begins_with("\"") and text.ends_with("\""):
		return text.substr(1, text.length() - 2)
	return _value_of(text)


static func _split_top_level(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var quoted := false
	var start := 0
	for i in text.length():
		var c: String = text[i]
		if c == "\"":
			quoted = not quoted
		elif quoted:
			continue
		elif c == "[":
			depth += 1
		elif c == "]":
			depth -= 1
		elif c == "," and depth == 0:
			out.append(text.substr(start, i - start))
			start = i + 1
	out.append(text.substr(start))
	return out


static func _top_colon(part: String) -> int:
	var depth := 0
	var quoted := false
	for i in part.length():
		var c: String = part[i]
		if c == "\"":
			quoted = not quoted
		elif quoted:
			continue
		elif c == "[":
			depth += 1
		elif c == "]":
			depth -= 1
		elif c == ":" and depth == 0:
			return i
	return -1


# --- lists and property lists (§1.3) -------------------------------------


static func _lists(key: String, args: Array, out: Array) -> bool:
	var first: Variant = _arg(args, 0)
	match key:
		"list":
			out.append(args.duplicate())
		"add":
			# On a sorted list this inserts rather than appends (§1.3, §8.13).
			# Implementing it as "push to the end" produces the right contents
			# for an unsorted list and a subtly wrong order for a sorted one.
			if typeof(first) == TYPE_ARRAY:
				var target: Array = first
				var value: Variant = _arg(args, 1)
				if _is_sorted(target):
					target.insert(_order_position(target, value), value)
				else:
					target.append(value)
			out.append(null)
		"addat":
			# The doc states no out-of-range rule for `addAt`, so the position
			# clamps and nothing errors. Deliberately unlike `setAt`, which the
			# doc *does* say extends the list — padding here would invent
			# elements that `count` would then report.
			if typeof(first) == TYPE_ARRAY:
				var target: Array = first
				var where := clampi(_i(_arg(args, 1)), 1, target.size() + 1)
				target.insert(where - 1, _arg(args, 2))
			out.append(null)
		"addprop":
			if typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				var name: String = _s(_arg(args, 1))
				var existing: Variant = _key_of(target, name)
				var sorted := _is_sorted(target)
				if existing == null:
					target[name] = _arg(args, 2)
				else:
					target[existing] = _arg(args, 2)
				if sorted:
					# Re-sorting is the same result as inserting in key order,
					# for a list that was already in key order.
					_sort_dict(target)
			out.append(null)
		"append":
			if typeof(first) == TYPE_ARRAY:
				var target: Array = first
				target.append(_arg(args, 1))
			out.append(null)
		"count":
			match typeof(first):
				TYPE_ARRAY:
					out.append((first as Array).size())
				TYPE_DICTIONARY:
					out.append((first as Dictionary).size())
				TYPE_VECTOR2:
					out.append(2)
				TYPE_RECT2:
					out.append(4)
				_:
					out.append(0)
		"deleteat":
			if typeof(first) == TYPE_ARRAY:
				var target: Array = first
				var where := _i(_arg(args, 1))
				if where >= 1 and where <= target.size():
					target.remove_at(where - 1)
			elif typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				var keys: Array = target.keys()
				var where := _i(_arg(args, 1))
				if where >= 1 and where <= keys.size():
					target.erase(keys[where - 1])
			out.append(null)
		"deleteone":
			# By value, and Lingo equality is case-insensitive (§2.2), so
			# `deleteOne(l, "kitchen")` removes an entry spelled "Kitchen".
			if typeof(first) == TYPE_ARRAY:
				var target: Array = first
				for i in target.size():
					if LingoValue.equal(target[i], _arg(args, 1)):
						target.remove_at(i)
						break
			elif typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				for name in target.keys():
					if LingoValue.equal(target[name], _arg(args, 1)):
						target.erase(name)
						break
			out.append(null)
		"deleteprop":
			if typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				var found: Variant = _key_of(target, _s(_arg(args, 1)))
				if found != null:
					target.erase(found)
			elif typeof(first) == TYPE_ARRAY:
				# On a linear list the "property" is the position.
				var target: Array = first
				var where := _i(_arg(args, 1))
				if where >= 1 and where <= target.size():
					target.remove_at(where - 1)
			out.append(null)
		"duplicate":
			# Two builtins share this name (§1): the list copy here and the
			# cast-member copy in §1.6, which needs the cast and so belongs to
			# the host. Claiming the member form would swallow it silently, so
			# only the one-argument list form is answered.
			if args.size() != 1:
				return false
			match typeof(first):
				TYPE_ARRAY:
					out.append((first as Array).duplicate())
				TYPE_DICTIONARY:
					out.append((first as Dictionary).duplicate())
				_:
					return false
		"findpos":
			# VOID when absent, where `getPos` answers 0 (§1.3). The two read
			# identically at a call site and only one of them is a number.
			out.append(_prop_position(first, _s(_arg(args, 1))))
		"findposnear":
			out.append(_prop_position_near(first, _s(_arg(args, 1))))
		"getaprop", "getprop":
			# `getProp` is documented to error where `getaProp` answers VOID.
			# This module has no error channel and inventing one would make a
			# missing key fatal in a title where it never was, so both answer
			# VOID and the difference is left to a host that wants to raise.
			out.append(_prop_value(first, _arg(args, 1)))
		"getat":
			out.append(_at(first, _i(_arg(args, 1))))
		"getlast":
			match typeof(first):
				TYPE_ARRAY:
					var target: Array = first
					out.append(target[target.size() - 1] if not target.is_empty() else null)
				TYPE_DICTIONARY:
					var target: Dictionary = first
					var keys: Array = target.keys()
					out.append(target[keys[keys.size() - 1]] if not keys.is_empty() else null)
				_:
					out.append(null)
		"getone":
			# Position in a linear list, but the *key* in a property list.
			if typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				var answer: Variant = null
				for name in target.keys():
					if LingoValue.equal(target[name], _arg(args, 1)):
						answer = name
						break
				out.append(answer)
			else:
				out.append(_position_of(first, _arg(args, 1)))
		"getpos":
			out.append(_position_of(first, _arg(args, 1)))
		"getpropat":
			if typeof(first) == TYPE_DICTIONARY:
				var keys: Array = (first as Dictionary).keys()
				var where := _i(_arg(args, 1))
				out.append(keys[where - 1] if where >= 1 and where <= keys.size() else null)
			else:
				out.append(null)
		"listp":
			out.append(1 if typeof(first) in [TYPE_ARRAY, TYPE_DICTIONARY] else 0)
		"max", "min":
			out.append(_extreme(args, key == "max"))
		"setat":
			# The doc says `setAt` extends the list if needed (§1.3). The pad
			# value is 0 rather than VOID so that the gap arithmetic in a script
			# that then walks the list still works.
			if typeof(first) == TYPE_ARRAY:
				var target: Array = first
				var where := _i(_arg(args, 1))
				if where >= 1:
					while target.size() < where - 1:
						target.append(0)
					if where - 1 < target.size():
						target[where - 1] = _arg(args, 2)
					else:
						target.append(_arg(args, 2))
			elif typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				var keys: Array = target.keys()
				var where := _i(_arg(args, 1))
				if where >= 1 and where <= keys.size():
					target[keys[where - 1]] = _arg(args, 2)
			out.append(null)
		"setaprop":
			if typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				var name: String = _s(_arg(args, 1))
				var existing: Variant = _key_of(target, name)
				target[existing if existing != null else name] = _arg(args, 2)
			elif typeof(first) == TYPE_ARRAY:
				var target: Array = first
				var where := _i(_arg(args, 1))
				if where >= 1 and where <= target.size():
					target[where - 1] = _arg(args, 2)
			out.append(null)
		"setprop":
			# Existing key only; a missing one is not added (§1.3).
			if typeof(first) == TYPE_DICTIONARY:
				var target: Dictionary = first
				var existing: Variant = _key_of(target, _s(_arg(args, 1)))
				if existing != null:
					target[existing] = _arg(args, 2)
			elif typeof(first) == TYPE_ARRAY:
				var target: Array = first
				var where := _i(_arg(args, 1))
				if where >= 1 and where <= target.size():
					target[where - 1] = _arg(args, 2)
			out.append(null)
		"sort":
			if typeof(first) == TYPE_ARRAY:
				_sort_array(first)
				_mark_sorted(first)
			elif typeof(first) == TYPE_DICTIONARY:
				_sort_dict(first)
				_mark_sorted(first)
			out.append(null)
		_:
			return false
	return true


static func _at(container: Variant, where: int) -> Variant:
	## 1-based. Past either end is VOID rather than 0: §8.6 is explicit that the
	## two are different, and VOID still counts as 0 in arithmetic and "" in
	## concatenation, so it is the answer that loses the least.
	match typeof(container):
		TYPE_ARRAY:
			var list: Array = container
			return list[where - 1] if where >= 1 and where <= list.size() else null
		TYPE_DICTIONARY:
			var dict: Dictionary = container
			var keys: Array = dict.keys()
			return dict[keys[where - 1]] if where >= 1 and where <= keys.size() else null
		TYPE_VECTOR2:
			# A point's components are whole in every Director script that makes
			# one, and `Vector2` can only hold floats — handing a whole
			# component back as an int keeps `LingoValue.div` on the integer
			# path, where `getAt(p, 1) / 2` belongs.
			var point: Vector2 = container
			if where == 1:
				return _whole(point.x)
			if where == 2:
				return _whole(point.y)
			return null
		TYPE_RECT2:
			var rect: Rect2 = container
			match where:
				1: return _whole(rect.position.x)
				2: return _whole(rect.position.y)
				3: return _whole(rect.position.x + rect.size.x)
				4: return _whole(rect.position.y + rect.size.y)
			return null
		_:
			return null


static func _whole(value: float) -> Variant:
	if is_equal_approx(value, roundf(value)):
		return int(roundf(value))
	return value


static func _position_of(container: Variant, value: Variant) -> int:
	## 0 when absent, which is `getPos`'s contract and not `findPos`'s.
	match typeof(container):
		TYPE_ARRAY:
			var list: Array = container
			for i in list.size():
				if LingoValue.equal(list[i], value):
					return i + 1
		TYPE_DICTIONARY:
			var dict: Dictionary = container
			var keys: Array = dict.keys()
			for i in keys.size():
				if LingoValue.equal(dict[keys[i]], value):
					return i + 1
	return 0


static func _key_of(dict: Dictionary, name: String) -> Variant:
	## The stored key equal to `name` under Lingo's rules, or VOID. Property-list
	## keys compare case-insensitively because every Lingo string comparison
	## does (§2.2), and a Godot Dictionary lookup does not — so a script that
	## writes `[#Room: 1]` and reads `getaProp(l, "room")` would otherwise miss.
	if dict.has(name):
		return name
	for existing in dict.keys():
		if LingoValue.equal(existing, name):
			return existing
	return null


static func _prop_value(container: Variant, name: Variant) -> Variant:
	if typeof(container) == TYPE_DICTIONARY:
		var dict: Dictionary = container
		var found: Variant = _key_of(dict, _s(name))
		return dict[found] if found != null else null
	# On a linear list the "property" is the position.
	return _at(container, LingoValue.to_int(name))


static func _prop_position(container: Variant, name: String) -> Variant:
	if typeof(container) != TYPE_DICTIONARY:
		return null
	var keys: Array = (container as Dictionary).keys()
	for i in keys.size():
		if LingoValue.equal(keys[i], name):
			return i + 1
	return null


static func _prop_position_near(container: Variant, name: String) -> Variant:
	## The position the key holds, or the one it would take in a sorted property
	## list. The doc gives the meaning and not the out-of-range rule, so a key
	## that sorts after everything answers one past the end — inference, marked
	## as such, and the only answer that lets a caller insert without a second
	## test.
	if typeof(container) != TYPE_DICTIONARY:
		return null
	var keys: Array = (container as Dictionary).keys()
	for i in keys.size():
		if LingoValue.compare(keys[i], name) >= 0:
			return i + 1
	return keys.size() + 1


static func _extreme(args: Array, want_max: bool) -> Variant:
	## Variadic, or over a single list argument (§1.3). Nothing to compare
	## answers 0, not VOID, because `max()` sits in arithmetic.
	var pool: Array = args
	if args.size() == 1:
		var only: Variant = args[0]
		if typeof(only) == TYPE_ARRAY:
			pool = only
		elif typeof(only) == TYPE_DICTIONARY:
			pool = (only as Dictionary).values()
	if pool.is_empty():
		return 0
	var best: Variant = pool[0]
	for i in range(1, pool.size()):
		var candidate: Variant = pool[i]
		var order := LingoValue.compare(candidate, best)
		if (want_max and order > 0) or (not want_max and order < 0):
			best = candidate
	return best


static func _order_position(list: Array, value: Variant) -> int:
	## The index `value` takes in an already-ordered list. Equal elements keep
	## their arrival order.
	for i in list.size():
		if LingoValue.compare(list[i], value) > 0:
			return i
	return list.size()


static func _sort_array(list: Array) -> void:
	## Insertion sort against `LingoValue.compare`, so that sorting agrees with
	## `<` — case-insensitive for strings, numeric for numbers. Written out
	## rather than handed to `sort_custom` because the comparison is the part
	## worth being able to read.
	for i in range(1, list.size()):
		var value: Variant = list[i]
		var j := i - 1
		while j >= 0 and LingoValue.compare(list[j], value) > 0:
			list[j + 1] = list[j]
			j -= 1
		list[j + 1] = value


static func _sort_dict(dict: Dictionary) -> void:
	## A property list sorts by key, in place, because callers hold the
	## reference.
	var keys: Array = dict.keys()
	_sort_array(keys)
	var values: Array = []
	for name in keys:
		values.append(dict[name])
	dict.clear()
	for i in keys.size():
		dict[keys[i]] = values[i]


static func _mark_sorted(container: Variant) -> void:
	if _find_sorted(container) >= 0:
		return
	_sorted.append(container)
	if _sorted.size() > SORTED_TRACKED:
		_sorted.remove_at(0)


static func _find_sorted(container: Variant) -> int:
	for i in _sorted.size():
		if is_same(_sorted[i], container):
			return i
	return -1


static func _is_sorted(container: Variant) -> bool:
	return _find_sorted(container) >= 0


# --- type predicates (§1.9) ----------------------------------------------


static func _predicates(key: String, args: Array, out: Array) -> bool:
	var first: Variant = _arg(args, 0)
	match key:
		"floatp":
			# The value's own type, not what it would coerce to: `floatP("1.5")`
			# is FALSE in Director, and a predicate that coerced first would
			# answer TRUE for every numeric string in the corpus.
			out.append(1 if typeof(first) == TYPE_FLOAT else 0)
		"integerp":
			out.append(1 if typeof(first) == TYPE_INT else 0)
		"stringp":
			out.append(1 if typeof(first) == TYPE_STRING else 0)
		"symbolp":
			out.append(1 if typeof(first) == TYPE_STRING_NAME else 0)
		"objectp":
			out.append(1 if typeof(first) == TYPE_OBJECT else 0)
		"voidp":
			out.append(1 if first == null else 0)
		"picturep":
			# This module has no picture type, so every value it can see is not
			# one. A host that carries real pictures must answer `pictureP`
			# before delegating here, exactly as it must for `duplicate`.
			out.append(0)
		"ilk":
			var kind := _ilk_of(first)
			if args.size() < 2:
				out.append(kind)
			else:
				out.append(_ilk_matches(first, kind, _s(_arg(args, 1))))
		_:
			return false
	return true


static func _ilk_of(value: Variant) -> StringName:
	match typeof(value):
		TYPE_NIL:
			return &"void"
		TYPE_INT, TYPE_BOOL:
			return &"integer"
		TYPE_FLOAT:
			return &"float"
		TYPE_STRING:
			return &"string"
		TYPE_STRING_NAME:
			return &"symbol"
		TYPE_ARRAY:
			return &"list"
		TYPE_DICTIONARY:
			return &"propList"
		TYPE_VECTOR2:
			return &"point"
		TYPE_RECT2:
			return &"rect"
		TYPE_OBJECT:
			return &"object"
		_:
			return &"void"


static func _ilk_matches(value: Variant, kind: StringName, want: String) -> int:
	## The doc gives `ilk`'s two-argument form as "tests against one" and stops
	## there. Director is looser than a straight equality: a property list
	## answers to #list as well as to #propList, and only a linear list answers
	## to #linearList. Both spellings are accepted here so that a title using
	## either reads the same.
	var wanted := want.to_lower().trim_prefix("#")
	if wanted == String(kind).to_lower():
		return 1
	if wanted == "list":
		return 1 if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else 0
	if wanted == "linearlist":
		return 1 if typeof(value) == TYPE_ARRAY else 0
	return 0


# --- points and rectangles (§1.8) ----------------------------------------


static func _geometry(key: String, args: Array, out: Array) -> bool:
	var first: Variant = _arg(args, 0)
	match key:
		"point":
			out.append(Vector2(_f(_arg(args, 0)), _f(_arg(args, 1))))
		"rect":
			# Four edges, or two points. `Rect2` stores position and size, so
			# the right edge is derived on the way in and back out; the four
			# accessors live in `_at` so `getAt(r, 3)` still answers `right`.
			if args.size() >= 4:
				var left := _f(_arg(args, 0))
				var top := _f(_arg(args, 1))
				out.append(Rect2(left, top, _f(_arg(args, 2)) - left, _f(_arg(args, 3)) - top))
			elif args.size() == 2 and typeof(first) == TYPE_VECTOR2 \
					and typeof(_arg(args, 1)) == TYPE_VECTOR2:
				var a: Vector2 = first
				var b: Vector2 = _arg(args, 1)
				out.append(Rect2(a, b - a))
			else:
				out.append(null)
		"inflate":
			if typeof(first) != TYPE_RECT2:
				out.append(null)
			else:
				# The doc gives 2..3 arguments without saying what the
				# two-argument form means; one delta applied to both axes is the
				# reading that makes the shorter call useful.
				var rect: Rect2 = first
				var dh := _f(_arg(args, 1))
				var dv: float = _f(_arg(args, 2)) if args.size() > 2 else dh
				out.append(Rect2(
					rect.position - Vector2(dh, dv), rect.size + Vector2(dh, dv) * 2.0))
		"inside":
			if typeof(first) != TYPE_VECTOR2 or typeof(_arg(args, 1)) != TYPE_RECT2:
				out.append(0)
			else:
				# Left and top edges are inside, right and bottom are not — the
				# same half-open rule the score uses, so two rectangles that
				# share an edge do not both claim the pixel on it.
				var point: Vector2 = first
				var rect: Rect2 = _arg(args, 1)
				var within := point.x >= rect.position.x and point.y >= rect.position.y \
					and point.x < rect.position.x + rect.size.x \
					and point.y < rect.position.y + rect.size.y
				out.append(1 if within else 0)
		"intersect":
			if typeof(first) != TYPE_RECT2 or typeof(_arg(args, 1)) != TYPE_RECT2:
				out.append(null)
			else:
				var a: Rect2 = first
				var b: Rect2 = _arg(args, 1)
				out.append(a.intersection(b))
		"union":
			if typeof(first) != TYPE_RECT2 or typeof(_arg(args, 1)) != TYPE_RECT2:
				out.append(null)
			else:
				var a: Rect2 = first
				var b: Rect2 = _arg(args, 1)
				out.append(a.merge(b))
		"map":
			out.append(_map(first, _arg(args, 1), _arg(args, 2)))
		_:
			return false
	return true


static func _map(what: Variant, source: Variant, destination: Variant) -> Variant:
	if typeof(source) != TYPE_RECT2 or typeof(destination) != TYPE_RECT2:
		return null
	var src: Rect2 = source
	var dst: Rect2 = destination
	if is_zero_approx(src.size.x) or is_zero_approx(src.size.y):
		# A source with no area has no proportions to map through, and dividing
		# by it would answer INF rather than failing where it happened.
		return null
	var scale := Vector2(dst.size.x / src.size.x, dst.size.y / src.size.y)
	match typeof(what):
		TYPE_VECTOR2:
			var point: Vector2 = what
			return dst.position + (point - src.position) * scale
		TYPE_RECT2:
			var rect: Rect2 = what
			return Rect2(dst.position + (rect.position - src.position) * scale, rect.size * scale)
		_:
			return null


# --- time (§1.14) --------------------------------------------------------


static func _time(key: String, args: Array, out: Array) -> bool:
	match key:
		"framestohms":
			out.append(_frames_to_hms(
				_i(_arg(args, 0)), _i(_arg(args, 1)), LingoValue.truthy(_arg(args, 3))))
		"hmstoframes":
			out.append(_hms_to_frames(
				_s(_arg(args, 0)), _i(_arg(args, 1)), LingoValue.truthy(_arg(args, 3))))
		_:
			return false
	return true


static func _frames_to_hms(frames: int, tempo: int, fractional: bool) -> String:
	## "HH:MM:SS.FF", where the last field is frames or hundredths of a second
	## depending on the fourth argument. The doc names the conversion and not
	## the exact spelling; Director is reported to pad the result with a space
	## at each end, and that is not reproduced here because it was not
	## verifiable and a caller can pad far more easily than it can strip.
	##
	## The third argument, drop-frame, is accepted and inert: it only means
	## anything at NTSC's 29.97 and the doc describes no rule for it. Answering
	## the non-drop count is wrong by two frames a minute at that one tempo and
	## right everywhere else.
	if tempo < 1:
		return "00:00:00.00"
	var seconds := frames / tempo
	var remainder := frames % tempo
	var last := remainder
	if fractional:
		last = int(roundf(float(remainder) * 100.0 / float(tempo)))
	return "%02d:%02d:%02d.%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60, last]


static func _hms_to_frames(text: String, tempo: int, fractional: bool) -> int:
	if tempo < 1:
		return 0
	var parts := text.strip_edges().split(":")
	if parts.size() != 3:
		return 0
	var tail := parts[2].split(".")
	var seconds := (LingoValue.to_int(parts[0]) * 60 + LingoValue.to_int(parts[1])) * 60 \
		+ LingoValue.to_int(tail[0])
	var last: int = LingoValue.to_int(tail[1]) if tail.size() > 1 else 0
	if fractional:
		last = int(roundf(float(last) * float(tempo) / 100.0))
	return seconds * tempo + last
