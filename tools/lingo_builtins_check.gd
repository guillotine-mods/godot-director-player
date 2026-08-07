extends SceneTree
## The title-agnostic builtins, checked against a table of what Director answers.
##
##   godot --headless --script tools/lingo_builtins_check.gd
##
## The table is the deliverable as much as `lingo/lingo_builtins.gd` is. A
## module meant to run Piposh 1 or Rating as well as Piposh 2 is only worth
## reusing if another title can see what it promises without reading the
## implementation, and the rows below are that promise: for each builtin, the
## ordinary case, a boundary (empty list, index 0, index past the end), a
## wrong-typed argument, and whichever documented oddity it carries — 1-based
## and inclusive `random`, `offset` answering 0 rather than -1, `getPos` versus
## `findPos`, integer versus float division surviving `abs`.
##
## Types are compared as strictly as values. `abs(-7)` answering 3.5 instead of
## 3.5-the-integer is not a cosmetic difference: `LingoValue.div` truncates
## between two integers and does not between a float and anything, so a builtin
## that returns the right number with the wrong type moves every expression
## downstream onto the other arithmetic (§2.1).
##
## Title-agnostic on purpose, like `tools/lib/harness.gd`. Nothing here may know
## which game is loaded, and no row may reference a member, a channel or a room.

const Harness := preload("res://tools/lib/harness.gd")
const Builtins := preload("res://lingo/lingo_builtins.gd")
## The last group drives the interpreter rather than the module, because the
## question it asks — "is there exactly one answer for this name?" — cannot be
## asked of the module alone. Preloaded rather than reached by `class_name`, for
## the reason `lingo_interpreter.gd` records at its own `preload`.
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")


func _init() -> void:
	var h := Harness.new()

	for group in [
		["math (LINGO_SURFACE §1.1)", _math_cases()],
		["constants (§1.15)", _constant_cases()],
		["strings (§1.2)", _string_cases()],
		["chunk counts (§1.2)", _chunk_cases()],
		["lists and property lists (§1.3)", _list_cases()],
		["type predicates (§1.9)", _predicate_cases()],
		["points and rectangles (§1.8)", _geometry_cases()],
		["frames and time strings (§1.14)", _time_cases()],
	]:
		var row: Array = group
		var title: String = row[0]
		h.begin(title)
		_run(h, row[1])
		h.complete(title)

	h.begin("random is 1-based and inclusive (§8.11)")
	_random_case(h)
	h.complete("random is 1-based and inclusive (§8.11)")

	h.begin("sort marks the list, and add then inserts (§8.13)")
	_sorted_case(h)
	h.complete("sort marks the list, and add then inserts (§8.13)")

	h.begin("one answer per name, reached from Lingo (§16.4 item 2)")
	_reconciled_case(h)
	h.complete("one answer per name, reached from Lingo (§16.4 item 2)")

	quit(h.finish("the engine-free half of Lingo answers what Director answers"))


# --- the tables ----------------------------------------------------------
#
# Built by a function rather than held in a `const`, because a constant Array is
# read-only in Godot 4 and half these rows exist to watch a list get mutated.
#
# Row keys: name, args, want, type-strict by construction; `after` is the
# expected state of args[0] once the call has returned, `handled: false` says
# the module must leave the name alone, `range` bounds a value that is not
# deterministic, `approx` compares floats loosely, `distinct` asserts the answer
# is not the argument itself, and `note` prints alongside the case.


func _math_cases() -> Array:
	return [
		# abs keeps the type, because abs(-7)/2 is 3 and abs(-7.0)/2 is 3.5.
		{"name": "abs", "args": [-3], "want": 3},
		{"name": "abs", "args": [-3.5], "want": 3.5},
		{"name": "abs", "args": ["-4"], "want": 4, "note": "numeric string stays an integer"},
		{"name": "abs", "args": ["abc"], "want": 0, "note": "non-numeric string is 0 (§2.8)"},
		{"name": "abs", "args": [null], "want": 0, "note": "VOID is 0 in arithmetic"},

		{"name": "atan", "args": [0], "want": 0.0},
		{"name": "atan", "args": [1], "want": 0.7853981633974483, "approx": true},
		{"name": "atan", "args": ["1"], "want": 0.7853981633974483, "approx": true},
		{"name": "atan", "args": [null], "want": 0.0},

		{"name": "cos", "args": [0], "want": 1.0},
		{"name": "cos", "args": [PI], "want": -1.0, "approx": true},
		{"name": "cos", "args": ["0"], "want": 1.0},
		{"name": "cos", "args": [null], "want": 1.0},

		{"name": "exp", "args": [0], "want": 1.0},
		{"name": "exp", "args": [1], "want": 2.718281828459045, "approx": true},
		{"name": "exp", "args": ["2"], "want": 7.38905609893065, "approx": true},
		{"name": "exp", "args": [null], "want": 1.0},

		{"name": "float", "args": [3], "want": 3.0},
		{"name": "float", "args": ["2.5"], "want": 2.5},
		{"name": "float", "args": ["abc"], "want": 0.0},
		{"name": "float", "args": [null], "want": 0.0},

		# The doc says integer() rounds. LingoValue.to_int truncates, correctly,
		# for the arithmetic path — so this one may not use it.
		{"name": "integer", "args": [3.7], "want": 4, "note": "rounds, not truncates (§1.1)"},
		{"name": "integer", "args": [-3.5], "want": -4, "note": "half rounds away from zero"},
		{"name": "integer", "args": ["2.5"], "want": 3},
		{"name": "integer", "args": [5], "want": 5},
		{"name": "integer", "args": ["abc"], "want": 0},
		{"name": "integer", "args": [null], "want": 0},

		{"name": "log", "args": [1], "want": 0.0},
		{"name": "log", "args": [10], "want": 2.302585092994046, "approx": true},
		{"name": "log", "args": [0], "want": 0.0, "note": "answers rather than raising -INF"},
		{"name": "log", "args": [-1], "want": 0.0, "note": "no NAN escapes into a comparison"},

		{"name": "pi", "args": [], "want": PI},
		{"name": "PI", "args": [], "want": PI, "note": "names match case-insensitively"},
		{"name": "Pi", "args": [], "want": PI},
		{"name": "pi", "args": [1], "handled": false, "note": "a bare word, never a call"},

		{"name": "power", "args": [2, 3], "want": 8.0, "note": "always a float"},
		{"name": "power", "args": [2, 0], "want": 1.0},
		{"name": "power", "args": [2, -1], "want": 0.5},
		{"name": "power", "args": ["2", "3"], "want": 8.0},
		{"name": "power", "args": [0, 0], "want": 1.0},

		{"name": "random", "args": [6], "range": [1, 6]},
		{"name": "random", "args": ["6"], "range": [1, 6]},
		{"name": "random", "args": [1], "want": 1, "note": "1..n inclusive, so random(1) is 1"},
		{"name": "random", "args": [0], "want": 0, "note": "nothing to choose from"},
		{"name": "random", "args": [-5], "want": 0},

		{"name": "sin", "args": [0], "want": 0.0},
		{"name": "sin", "args": [PI / 2.0], "want": 1.0, "approx": true},
		{"name": "sin", "args": ["0"], "want": 0.0},
		{"name": "sin", "args": [null], "want": 0.0},

		{"name": "sqrt", "args": [9], "want": 3.0},
		{"name": "sqrt", "args": [0], "want": 0.0},
		{"name": "sqrt", "args": [-4], "want": 0.0, "note": "0 rather than NAN"},
		{"name": "sqrt", "args": ["16"], "want": 4.0},

		{"name": "void", "args": [], "want": null},
		{"name": "VOID", "args": [], "want": null},
		{"name": "Void", "args": [], "want": null},
		{"name": "void", "args": [1], "handled": false},
	]


func _constant_cases() -> Array:
	var rows: Array = []
	for pair in [
		["backspace", String.chr(8)],
		["empty", ""],
		["enter", String.chr(3)],
		["quote", "\""],
		["return", "\n"],
		["tab", "\t"],
		["true", 1],
		["false", 0],
	]:
		var entry: Array = pair
		var name: String = entry[0]
		var want: Variant = entry[1]
		rows.append({"name": name, "args": [], "want": want})
		rows.append({"name": name.to_upper(), "args": [], "want": want})
		rows.append({"name": name.capitalize(), "args": [], "want": want})
		# A call with arguments is a different name wearing the same spelling —
		# `return` most of all, which is also the control-flow statement (§1).
		rows.append({"name": name, "args": [1], "handled": false})
	# ENTER and RETURN must not be the same character, or a script that tests
	# `the key` against one and not the other stops distinguishing them.
	rows.append({"name": "enter", "args": [], "want": String.chr(3),
		"note": "keypad Enter is character 3, not the carriage return"})
	return rows


func _string_cases() -> Array:
	return [
		{"name": "chars", "args": ["hello", 2, 4], "want": "ell"},
		{"name": "chars", "args": ["hello", 0, 2], "want": "",
			"note": "index 0 yields empty, per the port's chunk rule (§2.6)"},
		{"name": "chars", "args": ["hello", 4, 2], "want": "l", "note": "stop before start"},
		{"name": "chars", "args": ["hello", 4, 99], "want": "lo", "note": "past the end clamps"},
		{"name": "chars", "args": [12345, 2, 3], "want": "23"},
		{"name": "chars", "args": ["hello", 2], "want": ""},

		{"name": "charToNum", "args": ["A"], "want": 65},
		{"name": "charToNum", "args": [""], "want": 0},
		{"name": "charToNum", "args": ["abc"], "want": 97, "note": "first character only"},
		{"name": "charToNum", "args": [65], "want": 54, "note": "coerces to \"65\", so \"6\""},
		{"name": "charToNum", "args": [null], "want": 0},

		{"name": "length", "args": ["hello"], "want": 5},
		{"name": "length", "args": [""], "want": 0},
		{"name": "length", "args": [12345], "want": 5},
		{"name": "length", "args": [null], "want": 0},
		{"name": "length", "args": [[1, 2, 3]], "want": 9, "note": "a list prints bracketed (§2.8)"},

		{"name": "numToChar", "args": [65], "want": "A"},
		{"name": "numToChar", "args": ["65"], "want": "A"},
		{"name": "numToChar", "args": [13], "want": "\r"},
		{"name": "numToChar", "args": [32], "want": " "},
		{"name": "numToChar", "args": [-1], "want": "", "note": "no such character"},

		{"name": "offset", "args": ["l", "hello"], "want": 3, "note": "1-based (§8.12)"},
		{"name": "offset", "args": ["h", "hello"], "want": 1,
			"note": "the case a find()+1 without the -1 mapping still gets right"},
		{"name": "offset", "args": ["L", "hello"], "want": 3, "note": "case-insensitive (§2.2)"},
		{"name": "offset", "args": ["z", "hello"], "want": 0, "note": "absent is 0, not -1"},
		{"name": "offset", "args": ["l", "hello", 4], "want": 4, "note": "third argument starts later"},
		{"name": "offset", "args": ["", "hello"], "want": 0, "note": "nothing to find"},

		{"name": "string", "args": [3.0], "want": "3", "note": "whole floats lose the point (§8.17)"},
		{"name": "string", "args": [7], "want": "7"},
		{"name": "string", "args": [null], "want": "", "note": "VOID concatenates as empty (§8.6)"},
		{"name": "string", "args": [[1, 2]], "want": "[1, 2]"},
		{"name": "string", "args": ["x"], "want": "x"},

		{"name": "value", "args": ["42"], "want": 42},
		{"name": "value", "args": ["4.5"], "want": 4.5},
		{"name": "value", "args": [7], "want": 7, "note": "a number answers itself"},
		{"name": "value", "args": ["abc"], "want": null,
			"note": "an expression this module cannot evaluate is VOID, not 0"},
		{"name": "value", "args": [""], "want": null},
		{"name": "value", "args": ["[1,2]"], "want": [1, 2]},
		{"name": "value", "args": ["[a: 1]"], "want": {"a": 1}},
		{"name": "value", "args": ["[:]"], "want": {}, "note": "the empty property list"},
	]


func _chunk_cases() -> Array:
	# These delegate to LingoValue.count_of, so that the call spelling and
	# `the number of lines in X` cannot answer differently.
	return [
		{"name": "numberOfChars", "args": ["hello"], "want": 5},
		{"name": "numberOfChars", "args": [""], "want": 0},
		{"name": "numberOfChars", "args": [12345], "want": 5},
		{"name": "numberOfChars", "args": [[1, 2]], "want": 6},

		{"name": "numberOfItems", "args": ["a,b,c"], "want": 3},
		{"name": "numberOfItems", "args": [""], "want": 1, "note": "one empty item"},
		{"name": "numberOfItems", "args": ["a"], "want": 1},
		{"name": "numberOfItems", "args": [","], "want": 2},
		{"name": "numberOfItems", "args": ["a;b", ";"], "want": 2,
			"note": "the itemDelimiter is engine state, so a host may pass it"},

		{"name": "numberOfLines", "args": ["a\nb"], "want": 2},
		{"name": "numberOfLines", "args": ["a\r\nb\r\nc"], "want": 3, "note": "CR, LF or CRLF (§8.8)"},
		{"name": "numberOfLines", "args": ["a\n"], "want": 1, "note": "a trailing empty line is absent"},
		{"name": "numberOfLines", "args": [""], "want": 1},

		{"name": "numberOfWords", "args": ["one two"], "want": 2},
		{"name": "numberOfWords", "args": [""], "want": 0},
		{"name": "numberOfWords", "args": ["  a  b  "], "want": 2, "note": "empty runs make no words"},
		{"name": "numberOfWords", "args": ["a\tb"], "want": 2},
	]


func _list_cases() -> Array:
	return [
		{"name": "list", "args": [1, 2, 3], "want": [1, 2, 3]},
		{"name": "list", "args": [], "want": []},
		{"name": "list", "args": ["a"], "want": ["a"]},
		{"name": "list", "args": [[1], 2], "want": [[1], 2], "note": "nests, not flattens"},

		{"name": "add", "args": [[1, 2], 3], "want": null, "after": [1, 2, 3]},
		{"name": "add", "args": [[], 1], "want": null, "after": [1]},
		{"name": "add", "args": [[1, 2], "x"], "want": null, "after": [1, 2, "x"]},
		{"name": "add", "args": [{}, 1], "want": null, "after": {},
			"note": "add is not a property-list operation"},

		{"name": "addAt", "args": [[1, 3], 2, 2], "want": null, "after": [1, 2, 3]},
		{"name": "addAt", "args": [[1, 2], 1, 0], "want": null, "after": [0, 1, 2]},
		{"name": "addAt", "args": [[1, 2], 9, 9], "want": null, "after": [1, 2, 9],
			"note": "past the end clamps rather than padding (unlike setAt)"},
		{"name": "addAt", "args": [[1, 2], 0, 9], "want": null, "after": [9, 1, 2]},
		{"name": "addAt", "args": ["nope", 1, 1], "want": null, "after": "nope"},

		{"name": "addProp", "args": [{}, "a", 1], "want": null, "after": {"a": 1}},
		{"name": "addProp", "args": [{"a": 1}, "b", 2], "want": null, "after": {"a": 1, "b": 2}},
		{"name": "addProp", "args": [{"a": 1}, "a", 9], "want": null, "after": {"a": 9},
			"note": "Director would append a second pair; a Dictionary cannot"},
		{"name": "addProp", "args": [[], "a", 1], "want": null, "after": []},

		{"name": "append", "args": [[1], 2], "want": null, "after": [1, 2]},
		{"name": "append", "args": [[], "x"], "want": null, "after": ["x"]},
		{"name": "append", "args": [[1], null], "want": null, "after": [1, null]},
		{"name": "append", "args": [{}, 1], "want": null, "after": {}},

		{"name": "count", "args": [[1, 2, 3]], "want": 3},
		{"name": "count", "args": [[]], "want": 0},
		{"name": "count", "args": [{"a": 1, "b": 2}], "want": 2},
		{"name": "count", "args": ["abc"], "want": 0, "note": "a string is not a list"},
		{"name": "count", "args": [Rect2(0, 0, 10, 10)], "want": 4, "note": "a rect has four edges"},

		{"name": "deleteAt", "args": [[1, 2, 3], 2], "want": null, "after": [1, 3]},
		{"name": "deleteAt", "args": [[1, 2, 3], 0], "want": null, "after": [1, 2, 3]},
		{"name": "deleteAt", "args": [[1, 2, 3], 4], "want": null, "after": [1, 2, 3]},
		{"name": "deleteAt", "args": [{"a": 1, "b": 2}, 1], "want": null, "after": {"b": 2}},

		{"name": "deleteOne", "args": [[1, 2, 3], 2], "want": null, "after": [1, 3]},
		{"name": "deleteOne", "args": [[1, 2, 2], 2], "want": null, "after": [1, 2],
			"note": "the first match only"},
		{"name": "deleteOne", "args": [[1, 2], 9], "want": null, "after": [1, 2]},
		{"name": "deleteOne", "args": [["A", "b"], "a"], "want": null, "after": ["b"],
			"note": "equality is case-insensitive (§2.2)"},
		{"name": "deleteOne", "args": [{"a": 1, "b": 2}, 2], "want": null, "after": {"a": 1},
			"note": "by value on a property list too"},

		{"name": "deleteProp", "args": [{"a": 1, "b": 2}, "a"], "want": null, "after": {"b": 2}},
		{"name": "deleteProp", "args": [{"a": 1}, "z"], "want": null, "after": {"a": 1}},
		{"name": "deleteProp", "args": [{"A": 1}, "a"], "want": null, "after": {},
			"note": "keys match case-insensitively, where a Dictionary lookup would not"},
		{"name": "deleteProp", "args": [[1, 2, 3], 2], "want": null, "after": [1, 3],
			"note": "on a linear list the property is the position"},

		{"name": "duplicate", "args": [[1, 2]], "want": [1, 2], "after": [1, 2], "distinct": true},
		{"name": "duplicate", "args": [{"a": 1}], "want": {"a": 1}},
		{"name": "duplicate", "args": [5], "handled": false,
			"note": "the cast-member copy shares this name and needs the cast (§1.6)"},
		{"name": "duplicate", "args": [[1, 2], 3], "handled": false, "note": "two arguments is the member form"},
		{"name": "duplicate", "args": ["x"], "handled": false},

		{"name": "findPos", "args": [{"a": 1, "b": 2}, "b"], "want": 2},
		{"name": "findPos", "args": [{"a": 1}, "z"], "want": null,
			"note": "VOID where getPos answers 0 (§1.3)"},
		{"name": "findPos", "args": [{"A": 1}, "a"], "want": 1},
		{"name": "findPos", "args": [[1, 2], "a"], "want": null},

		{"name": "findPosNear", "args": [{"a": 1, "c": 3}, "b"], "want": 2},
		{"name": "findPosNear", "args": [{"a": 1, "c": 3}, "a"], "want": 1},
		{"name": "findPosNear", "args": [{"a": 1, "c": 3}, "z"], "want": 3,
			"note": "one past the end; the doc gives no rule and this is the inference"},
		{"name": "findPosNear", "args": [[], "a"], "want": null},

		{"name": "getaProp", "args": [{"a": 1}, "a"], "want": 1},
		{"name": "getaProp", "args": [{"a": 1}, "z"], "want": null},
		{"name": "getaProp", "args": [[10, 20], 2], "want": 20},
		{"name": "getaProp", "args": [[10, 20], 5], "want": null},

		{"name": "getProp", "args": [{"a": 1}, "a"], "want": 1},
		{"name": "getProp", "args": [{"a": 1}, "z"], "want": null,
			"note": "Director errors here; this module has no error channel"},
		{"name": "getProp", "args": [[10, 20], 1], "want": 10},
		{"name": "getProp", "args": [[10, 20], 0], "want": null},

		{"name": "getAt", "args": [[1, 2, 3], 2], "want": 2},
		{"name": "getAt", "args": [[1, 2, 3], 0], "want": null, "note": "1-based, so 0 is off the end"},
		{"name": "getAt", "args": [[1, 2, 3], 4], "want": null},
		{"name": "getAt", "args": ["abc", 1], "want": null},
		{"name": "getAt", "args": [{"a": 1, "b": 2}, 2], "want": 2},
		{"name": "getAt", "args": [Vector2(3, 4), 1], "want": 3,
			"note": "a whole component comes back as an integer, so div stays truncating"},

		{"name": "getLast", "args": [[1, 2, 3]], "want": 3},
		{"name": "getLast", "args": [[]], "want": null},
		{"name": "getLast", "args": [{"a": 1, "b": 2}], "want": 2},
		{"name": "getLast", "args": ["x"], "want": null},

		{"name": "getOne", "args": [[10, 20, 30], 20], "want": 2},
		{"name": "getOne", "args": [[10], 99], "want": 0},
		{"name": "getOne", "args": [{"a": 1, "b": 2}, 2], "want": "b",
			"note": "the key on a property list, the position on a linear one"},
		{"name": "getOne", "args": [{"a": 1}, 9], "want": null},

		{"name": "getPos", "args": [[10, 20], 20], "want": 2},
		{"name": "getPos", "args": [[10, 20], 99], "want": 0, "note": "0 where findPos answers VOID"},
		{"name": "getPos", "args": [["A"], "a"], "want": 1},
		{"name": "getPos", "args": [{"a": 1, "b": 2}, 2], "want": 2},

		{"name": "getPropAt", "args": [{"a": 1, "b": 2}, 2], "want": "b"},
		{"name": "getPropAt", "args": [{"a": 1}, 0], "want": null},
		{"name": "getPropAt", "args": [{"a": 1}, 5], "want": null},
		{"name": "getPropAt", "args": [[1, 2], 1], "want": null},

		{"name": "listP", "args": [[]], "want": 1},
		{"name": "listP", "args": [{}], "want": 1, "note": "a property list is a list"},
		{"name": "listP", "args": ["x"], "want": 0},
		{"name": "listP", "args": [null], "want": 0},

		{"name": "max", "args": [3, 1, 2], "want": 3},
		{"name": "max", "args": [[3, 1, 2]], "want": 3, "note": "or over one list argument"},
		{"name": "max", "args": [[]], "want": 0},
		{"name": "max", "args": [], "want": 0},
		{"name": "max", "args": ["b", "a"], "want": "b"},

		{"name": "min", "args": [3, 1, 2], "want": 1},
		{"name": "min", "args": [[3, 1, 2]], "want": 1},
		{"name": "min", "args": [[]], "want": 0},
		{"name": "min", "args": [], "want": 0},
		{"name": "min", "args": ["b", "a"], "want": "a"},

		{"name": "setAt", "args": [[1, 2, 3], 2, 9], "want": null, "after": [1, 9, 3]},
		{"name": "setAt", "args": [[1], 3, 9], "want": null, "after": [1, 0, 9],
			"note": "extends the list, padding with 0 (§1.3)"},
		{"name": "setAt", "args": [[1], 0, 9], "want": null, "after": [1]},
		{"name": "setAt", "args": [{"a": 1, "b": 2}, 2, 9], "want": null, "after": {"a": 1, "b": 9}},

		{"name": "setaProp", "args": [{"a": 1}, "a", 2], "want": null, "after": {"a": 2}},
		{"name": "setaProp", "args": [{"a": 1}, "b", 2], "want": null, "after": {"a": 1, "b": 2},
			"note": "adds the key if it is absent"},
		{"name": "setaProp", "args": [{"A": 1}, "a", 2], "want": null, "after": {"A": 2},
			"note": "the stored spelling is kept"},
		{"name": "setaProp", "args": [[1, 2], 2, 9], "want": null, "after": [1, 9]},

		{"name": "setProp", "args": [{"a": 1}, "a", 2], "want": null, "after": {"a": 2}},
		{"name": "setProp", "args": [{"a": 1}, "z", 2], "want": null, "after": {"a": 1},
			"note": "an existing key only; nothing is added"},
		{"name": "setProp", "args": [[1, 2], 1, 9], "want": null, "after": [9, 2]},
		{"name": "setProp", "args": [[1, 2], 5, 9], "want": null, "after": [1, 2]},

		{"name": "sort", "args": [[3, 1, 2]], "want": null, "after": [1, 2, 3]},
		{"name": "sort", "args": [[]], "want": null, "after": []},
		{"name": "sort", "args": [{"b": 2, "a": 1}], "want": null, "after": {"a": 1, "b": 2},
			"note": "a property list sorts by key"},
		{"name": "sort", "args": [["b", "A"]], "want": null, "after": ["A", "b"],
			"note": "ordering folds case, exactly as < does"},
		{"name": "sort", "args": ["x"], "want": null, "after": "x"},
	]


func _predicate_cases() -> Array:
	return [
		{"name": "floatP", "args": [1.5], "want": 1},
		{"name": "floatP", "args": [1], "want": 0},
		{"name": "floatP", "args": ["1.5"], "want": 0, "note": "the value's own type, not what it coerces to"},
		{"name": "floatP", "args": [null], "want": 0},

		{"name": "integerP", "args": [1], "want": 1},
		{"name": "integerP", "args": [1.0], "want": 0},
		{"name": "integerP", "args": ["1"], "want": 0},
		{"name": "integerP", "args": [null], "want": 0},

		{"name": "stringP", "args": ["x"], "want": 1},
		{"name": "stringP", "args": [&"x"], "want": 0, "note": "a symbol is not a string"},
		{"name": "stringP", "args": [1], "want": 0},
		{"name": "stringP", "args": [null], "want": 0},

		{"name": "symbolP", "args": [&"x"], "want": 1},
		{"name": "symbolP", "args": ["x"], "want": 0},
		{"name": "symbolP", "args": [null], "want": 0},
		{"name": "symbolP", "args": [[]], "want": 0},

		{"name": "objectP", "args": [RefCounted.new()], "want": 1},
		{"name": "objectP", "args": [[]], "want": 0, "note": "a list is not an object"},
		{"name": "objectP", "args": [null], "want": 0},
		{"name": "objectP", "args": ["x"], "want": 0},

		{"name": "voidP", "args": [null], "want": 1},
		{"name": "voidP", "args": [0], "want": 0, "note": "VOID is not 0 (§8.6)"},
		{"name": "voidP", "args": [""], "want": 0},
		{"name": "voidP", "args": [[]], "want": 0},

		{"name": "pictureP", "args": [1], "want": 0},
		{"name": "pictureP", "args": ["x"], "want": 0},
		{"name": "pictureP", "args": [null], "want": 0},
		{"name": "pictureP", "args": [[]], "want": 0,
			"note": "no picture type here; a host that has one answers before delegating"},

		{"name": "ilk", "args": [1], "want": &"integer"},
		{"name": "ilk", "args": [1.0], "want": &"float"},
		{"name": "ilk", "args": ["x"], "want": &"string"},
		{"name": "ilk", "args": [&"x"], "want": &"symbol"},
		{"name": "ilk", "args": [[]], "want": &"list"},
		{"name": "ilk", "args": [{}], "want": &"propList"},
		{"name": "ilk", "args": [null], "want": &"void"},
		{"name": "ilk", "args": [Vector2(1, 2)], "want": &"point"},
		{"name": "ilk", "args": [Rect2(0, 0, 1, 1)], "want": &"rect"},
		{"name": "ilk", "args": [1, "integer"], "want": 1},
		{"name": "ilk", "args": [1, "#integer"], "want": 1, "note": "with or without the hash"},
		{"name": "ilk", "args": [{}, "list"], "want": 1, "note": "a property list answers to #list too"},
		{"name": "ilk", "args": [{}, "linearList"], "want": 0},
		{"name": "ilk", "args": [[], "propList"], "want": 0},
		{"name": "ilk", "args": [1, "string"], "want": 0},
	]


func _geometry_cases() -> Array:
	return [
		{"name": "point", "args": [3, 4], "want": Vector2(3, 4)},
		{"name": "point", "args": ["3", "4"], "want": Vector2(3, 4)},
		{"name": "point", "args": [3], "want": Vector2(3, 0), "note": "a missing argument is VOID, so 0"},
		{"name": "point", "args": ["a", "b"], "want": Vector2(0, 0)},

		{"name": "rect", "args": [1, 2, 3, 4], "want": Rect2(1, 2, 2, 2),
			"note": "four edges in, position and size stored"},
		{"name": "rect", "args": [Vector2(1, 2), Vector2(3, 4)], "want": Rect2(1, 2, 2, 2)},
		{"name": "rect", "args": [1, 2], "want": null, "note": "two numbers is not one of the forms"},
		{"name": "rect", "args": [1, 2, 3], "want": null},
		{"name": "rect", "args": [], "want": null},

		{"name": "inflate", "args": [Rect2(10, 10, 10, 10), 5, 5], "want": Rect2(5, 5, 20, 20)},
		{"name": "inflate", "args": [Rect2(10, 10, 10, 10), -5, -5], "want": Rect2(15, 15, 0, 0),
			"note": "a negative delta shrinks"},
		{"name": "inflate", "args": [Rect2(10, 10, 10, 10), 2], "want": Rect2(8, 8, 14, 14),
			"note": "one delta applies to both axes"},
		{"name": "inflate", "args": ["x", 1, 1], "want": null},

		{"name": "inside", "args": [Vector2(5, 5), Rect2(0, 0, 10, 10)], "want": 1},
		{"name": "inside", "args": [Vector2(0, 0), Rect2(0, 0, 10, 10)], "want": 1,
			"note": "left and top edges are inside"},
		{"name": "inside", "args": [Vector2(10, 10), Rect2(0, 0, 10, 10)], "want": 0,
			"note": "right and bottom are not, so touching rects do not both claim a pixel"},
		{"name": "inside", "args": [Vector2(-1, 5), Rect2(0, 0, 10, 10)], "want": 0},
		{"name": "inside", "args": ["x", Rect2(0, 0, 10, 10)], "want": 0},

		{"name": "intersect", "args": [Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10)],
			"want": Rect2(5, 5, 5, 5)},
		{"name": "intersect", "args": [Rect2(0, 0, 10, 10), Rect2(20, 20, 5, 5)],
			"want": Rect2(0, 0, 0, 0), "note": "no overlap is the empty rect, not VOID"},
		{"name": "intersect", "args": [Rect2(0, 0, 10, 10), Rect2(0, 0, 10, 10)],
			"want": Rect2(0, 0, 10, 10)},
		{"name": "intersect", "args": [Rect2(0, 0, 10, 10), "x"], "want": null},

		{"name": "union", "args": [Rect2(0, 0, 10, 10), Rect2(20, 20, 5, 5)],
			"want": Rect2(0, 0, 25, 25)},
		{"name": "union", "args": [Rect2(0, 0, 10, 10), Rect2(0, 0, 10, 10)],
			"want": Rect2(0, 0, 10, 10)},
		{"name": "union", "args": [Rect2(0, 0, 0, 0), Rect2(5, 5, 5, 5)],
			"want": Rect2(0, 0, 10, 10), "note": "an empty rect still contributes its corner"},
		{"name": "union", "args": ["x", Rect2(0, 0, 10, 10)], "want": null},

		{"name": "map", "args": [Vector2(5, 5), Rect2(0, 0, 10, 10), Rect2(0, 0, 20, 20)],
			"want": Vector2(10, 10)},
		{"name": "map", "args": [Vector2(5, 5), Rect2(10, 10, 10, 10), Rect2(0, 0, 20, 20)],
			"want": Vector2(-10, -10), "note": "outside the source maps outside the destination"},
		{"name": "map", "args": [Rect2(0, 0, 5, 5), Rect2(0, 0, 10, 10), Rect2(0, 0, 20, 20)],
			"want": Rect2(0, 0, 10, 10), "note": "a rect maps as well as a point"},
		{"name": "map", "args": [Vector2(5, 5), Rect2(0, 0, 0, 0), Rect2(0, 0, 20, 20)],
			"want": null, "note": "a source with no area has no proportions"},
		{"name": "map", "args": ["x", Rect2(0, 0, 10, 10), Rect2(0, 0, 20, 20)], "want": null},
	]


func _time_cases() -> Array:
	return [
		{"name": "framesToHMS", "args": [2345, 15, 0, 0], "want": "00:02:36.05"},
		{"name": "framesToHMS", "args": ["2345", "15", 0, 0], "want": "00:02:36.05"},
		{"name": "framesToHMS", "args": [0, 15, 0, 0], "want": "00:00:00.00"},
		{"name": "framesToHMS", "args": [216000, 60, 0, 0], "want": "01:00:00.00"},
		{"name": "framesToHMS", "args": [2345, 15, 0, 1], "want": "00:02:36.33",
			"note": "the fourth argument makes the last field hundredths"},
		{"name": "framesToHMS", "args": [100, 0, 0, 0], "want": "00:00:00.00",
			"note": "a tempo of 0 answers rather than dividing by it"},

		{"name": "HMStoFrames", "args": ["00:02:36.05", 15, 0, 0], "want": 2345},
		{"name": "HMStoFrames", "args": ["00:02:36.33", 15, 0, 1], "want": 2345,
			"note": "round-trips the fractional form"},
		{"name": "HMStoFrames", "args": ["00:00:10", 15, 0, 0], "want": 150,
			"note": "the last field may be absent"},
		{"name": "HMStoFrames", "args": ["", 15, 0, 0], "want": 0},
		{"name": "HMStoFrames", "args": ["garbage", 15, 0, 0], "want": 0},
		{"name": "HMStoFrames", "args": ["00:00:10.00", 0, 0, 0], "want": 0},
	]


# --- the driving ---------------------------------------------------------


func _run(h, cases: Array) -> void:
	for entry in cases:
		var row: Dictionary = entry
		_one(h, row)


func _one(h, row: Dictionary) -> void:
	var name: String = str(row.get("name", ""))
	var args: Array = row.get("args", [])
	var label: String = "%s(%s)" % [name, _show_args(args)]
	if row.has("note"):
		label = "%s  -- %s" % [label, str(row["note"])]

	var handled: Array = []
	var got: Variant = Builtins.call_builtin(name, args, handled)
	var want_handled: bool = bool(row.get("handled", true))
	if handled.is_empty() != (not want_handled):
		h.check(label, false, "handled %s, expected %s" % [not handled.is_empty(), want_handled])
		return
	if not want_handled:
		h.check(label, true, "left for the host")
		return

	# Detail is reported only when a case fails. A passing check that carries
	# "5 not in 1..6" alongside it reads as a failure to anyone skimming, and a
	# 400-line pass is only useful if it is skimmable.
	var approx: bool = bool(row.get("approx", false))
	if row.has("range"):
		var span: Array = row["range"]
		var low: int = int(span[0])
		var high: int = int(span[1])
		var within: bool = typeof(got) == TYPE_INT and int(got) >= low and int(got) <= high
		if not h.check(label, within, "" if within else \
				"got %s <%s>, want an integer in %d..%d" % [
					_show(got), _type_name(got), low, high]):
			return
	else:
		var want: Variant = row.get("want", null)
		var agreed: bool = _same(got, want, approx)
		if not h.check(label, agreed, "" if agreed else "got %s <%s>, want %s <%s>" % [
				_show(got), _type_name(got), _show(want), _type_name(want)]):
			return

	if row.has("after"):
		var after: Variant = row["after"]
		var subject: Variant = args[0] if not args.is_empty() else null
		var kept: bool = _same(subject, after, approx)
		h.check(
			"%s  leaves %s" % [label, _show(after)],
			kept,
			"" if kept else "got %s" % _show(subject),
		)
	if bool(row.get("distinct", false)):
		var subject: Variant = args[0] if not args.is_empty() else null
		h.check("%s  answers a copy, not the argument" % label, not is_same(got, subject))


func _random_case(h) -> void:
	## Not a table row, because the thing being asserted is the shape of the
	## distribution and not one value: 1..n **inclusive**, which is the port
	## off-by-one that makes the last option of every "one of N" unreachable.
	var seen := {}
	for _i in 400:
		var drawn: Variant = Builtins.call_builtin("random", [4], [])
		seen[drawn] = true
	h.check("random(4) reaches 1", seen.has(1))
	h.check("random(4) reaches 4", seen.has(4), "the option a 0-based port never picks")
	h.check("random(4) never answers 0", not seen.has(0))
	h.check("random(4) never answers 5", not seen.has(5))


func _sorted_case(h) -> void:
	## Two calls, so it cannot be a table row. `sort` marks the list and `add`
	## then inserts in order instead of appending — the failure that produces
	## correct contents in the wrong order and surfaces much later as a menu
	## nobody can explain.
	var ordered: Array = [3, 1, 2]
	Builtins.call_builtin("sort", [ordered], [])
	h.check("sort orders in place", _same(ordered, [1, 2, 3], false), _show(ordered))
	Builtins.call_builtin("add", [ordered, 2], [])
	h.check("add on a sorted list inserts", _same(ordered, [1, 2, 2, 3], false), _show(ordered))

	var loose: Array = [3, 1]
	Builtins.call_builtin("add", [loose, 2], [])
	h.check("add on an untouched list appends", _same(loose, [3, 1, 2], false), _show(loose))

	var ordered_props: Dictionary = {"c": 3, "a": 1}
	Builtins.call_builtin("sort", [ordered_props], [])
	Builtins.call_builtin("addProp", [ordered_props, "b", 2], [])
	h.check(
		"addProp on a sorted property list keeps key order",
		_same(ordered_props, {"a": 1, "b": 2, "c": 3}, false),
		_show(ordered_props),
	)

	var loose_props: Dictionary = {"c": 3, "a": 1}
	Builtins.call_builtin("addProp", [loose_props, "b", 2], [])
	h.check(
		"addProp on an untouched property list appends",
		_same(loose_props, {"c": 3, "a": 1, "b": 2}, false),
		_show(loose_props),
	)


func _reconciled_case(h) -> void:
	## Ten names this module and `lingo_interpreter.gd` both used to answer.
	##
	## Every other case in this file calls `Builtins.call_builtin` directly, which
	## can only ever see one implementation — so it could not have caught the
	## duplication it is meant to guard against. The interpreter carried its own
	## inline `match` for `value`, `string`, `integer`, `float`, `abs`, `length`,
	## `chars`, `offset`, `count` and `getAt`, placed *above* the dispatch that
	## reaches this module, and the two disagreed on six of the ten. The scripts
	## only ever saw the inline copy, so passing rows here proved nothing about
	## what the game ran.
	##
	## These cases therefore go in through the interpreter, from Lingo source, and
	## assert the module's answer arrives. Each note names the answer the deleted
	## copy gave, because that is the regression this exists to catch.
	var cases := [
		# getAt past the end: VOID, not 0. §8.6 — a 0 cannot be told from a
		# stored 0, so `if getAt(l, i) then` read the same either way.
		{"lingo": "getAt([1, 2, 3], 5)", "want": null, "was": "0"},
		{"lingo": "getAt([1, 2, 3], 2)", "want": 2, "was": "2, agreed"},
		{"lingo": "getAt([\"a\": 1, \"b\": 2], 2)", "want": 2, "was": "0: it knew only lists"},
		# abs keeps the operand's type, so §2.1's integer division survives it.
		{"lingo": "abs(-7) / 2", "want": 3, "was": "3.5: it coerced to float"},
		{"lingo": "abs(-7.0) / 2", "want": 3.5, "was": "3.5, agreed"},
		{"lingo": "abs(-3)", "want": 3, "was": "3.0"},
		# value parses, it does not coerce (§1.2).
		{"lingo": "value(\"abc\")", "want": null, "was": "0: it used to_num"},
		{"lingo": "value(\"42\")", "want": 42, "was": "42, agreed"},
		# integer rounds (§1.1); the inline copy used to_int, which truncates.
		{"lingo": "integer(3.7)", "want": 4, "was": "3"},
		{"lingo": "integer(-3.5)", "want": -4, "was": "-3"},
		# offset honours its third argument and finds nothing in an empty needle.
		{"lingo": "offset(\"l\", \"hello\", 4)", "want": 4, "was": "3: it ignored the third argument"},
		{"lingo": "offset(\"\", \"hello\")", "want": 0, "was": "1: `if offset(\"\", s) then` fired"},
		# count knows the containers §1.3 gives it.
		{"lingo": "count([\"a\": 1, \"b\": 2])", "want": 2, "was": "0: lists only"},
		{"lingo": "count([1, 2, 3])", "want": 3, "was": "3, agreed"},
		# The four that already agreed, pinned so the surviving copy cannot drift.
		{"lingo": "chars(\"hello\", 2, 4)", "want": "ell", "was": "\"ell\", agreed"},
		{"lingo": "length(\"hello\")", "want": 5, "was": "5, agreed"},
		{"lingo": "string(3.0)", "want": "3", "was": "\"3\", agreed"},
		{"lingo": "float(3)", "want": 3.0, "was": "3.0, agreed"},
	]
	for row in cases:
		var case_row: Dictionary = row
		var expression: String = str(case_row["lingo"])
		var want: Variant = case_row["want"]
		var got: Variant = _evaluate(expression)
		var agreed: bool = _same(got, want, false)
		h.check(
			"%s  ->  %s <%s>" % [expression, _show(want), _type_name(want)],
			agreed,
			("was %s" % str(case_row["was"])) if agreed else "got %s <%s>" % [
				_show(got), _type_name(got)],
		)


func _evaluate(expression: String) -> Variant:
	## One Lingo expression, compiled and run through the interpreter with no
	## host, so the answer is whatever the *dispatch order* in
	## `lingo_interpreter.gd:_call` produces. A host is deliberately absent: every
	## name here is engine-free by definition, and a nil host means a name that
	## escaped this module answers VOID rather than being quietly caught.
	var script := Compiler.new().compile_source(
		"on probe\n  return %s\nend\n" % expression, "ReconciledCase")
	if script.is_empty():
		return "<did not compile>"
	return Interpreter.new(null).call_handler("probe", [], script)


# --- comparing and printing ----------------------------------------------


func _same(a: Variant, b: Variant, approx: bool) -> bool:
	## Type-strict, then deep. Written out rather than left to `==` because the
	## type half is the point: 3 and 3.0 are the same number and different
	## arguments to `LingoValue.div`.
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			if approx:
				return is_equal_approx(float(a), float(b))
			return float(a) == float(b)
		TYPE_ARRAY:
			var left: Array = a
			var right: Array = b
			if left.size() != right.size():
				return false
			for i in left.size():
				if not _same(left[i], right[i], approx):
					return false
			return true
		TYPE_DICTIONARY:
			# Key order is compared too: a property list is ordered, and `sort`
			# and `addProp` exist to change that order.
			var left: Dictionary = a
			var right: Dictionary = b
			if left.size() != right.size():
				return false
			var left_keys: Array = left.keys()
			var right_keys: Array = right.keys()
			for i in left_keys.size():
				if not _same(left_keys[i], right_keys[i], approx):
					return false
				if not _same(left[left_keys[i]], right[right_keys[i]], approx):
					return false
			return true
		_:
			return a == b


func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "VOID"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_STRING_NAME: return "symbol"
		TYPE_ARRAY: return "list"
		TYPE_DICTIONARY: return "propList"
		TYPE_VECTOR2: return "point"
		TYPE_RECT2: return "rect"
		TYPE_OBJECT: return "object"
		_: return "?"


func _show(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "VOID"
		TYPE_STRING:
			# JSON has no escape for most control characters, and BACKSPACE and
			# ENTER are two of the constants under test — printing them as
			# nothing would hide the case that matters.
			var text: String = value
			var shown := ""
			for i in text.length():
				var code := text.unicode_at(i)
				if code < 0x20 and not (code in [0x09, 0x0A, 0x0D]):
					shown += "\\x%02x" % code
				else:
					shown += text[i]
			return JSON.stringify(shown)
		TYPE_STRING_NAME:
			return "#%s" % value
		TYPE_ARRAY:
			return "[%s]" % _show_args(value)
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			if dict.is_empty():
				return "[:]"
			var parts := PackedStringArray()
			for name in dict.keys():
				parts.append("%s: %s" % [_show(name), _show(dict[name])])
			return "[%s]" % ", ".join(parts)
		TYPE_OBJECT:
			return "<object>"
		_:
			return str(value)


func _show_args(args: Array) -> String:
	var parts := PackedStringArray()
	for value in args:
		parts.append(_show(value))
	return ", ".join(parts)
