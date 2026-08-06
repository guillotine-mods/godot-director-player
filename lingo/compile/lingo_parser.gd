class_name LingoParser
extends RefCounted
## Lingo tokens to the JSON AST `lingo/lingo_interpreter.gd` executes.
##
## A transliteration of `tools/lingo_compile.py:174-886`, method for method and
## deliberately not improved. The interpreter has been fed that compiler's output
## for the whole life of the port, so "more sensible" here means "different AST",
## and different means the game behaves differently for reasons nothing records.
## Several things below look like defects and are load-bearing:
##
## A `dot`, `call` or `index` node takes its line from the token *after* the
## construct, not from the operator.
##
## A command-form call's callee carries no `line` key, unlike every other `var`.
##
## `the number of lines in x` counts lines, while `the number of member "x"` is
## that member's number. Same three words, different node.
##
## Where Python raises, this sets `error` and returns an empty Dictionary, and
## every loop head checks `_failed()`. GDScript has no exceptions, and it has no
## catchable recursion limit either — a runaway descent takes the process down
## with no diagnostic — so `MAX_DEPTH` reports what a stack overflow would not.

const Grammar := preload("res://lingo/compile/lingo_grammar.gd")

## Nesting beyond this is a malformed script, not a deep one. The corpus's
## worst case is nowhere near it; the guard exists because the failure it
## replaces is a hard crash rather than an error.
const MAX_DEPTH := 200

var error := ""
var error_line := 0

var _kinds := PackedStringArray()
var _values := PackedStringArray()
var _lines := PackedInt32Array()
var _i := 0
var _name := ""
var _depth := 0


func parse(lexer, script_name: String) -> Dictionary:
	_kinds = lexer.kinds
	_values = lexer.values
	_lines = lexer.lines
	_i = 0
	_name = script_name
	_depth = 0
	error = ""
	error_line = 0
	return _parse_script()


# ------------------------------------------------------------- token helpers

func _k(ahead: int = 0) -> String:
	return _kinds[mini(_i + ahead, _kinds.size() - 1)]


func _v(ahead: int = 0) -> String:
	return _values[mini(_i + ahead, _values.size() - 1)]


func _ln(ahead: int = 0) -> int:
	return _lines[mini(_i + ahead, _lines.size() - 1)]


## Returns the token's text. Never advances past `eof`.
func _advance() -> String:
	var value := _values[_i]
	if _kinds[_i] != "eof":
		_i += 1
	return value


func _at_kw(word: String, ahead: int = 0) -> bool:
	return _k(ahead) == "kw" and _v(ahead).to_lower() == word


func _at_kw_any(words: Array, ahead: int = 0) -> bool:
	return _k(ahead) == "kw" and words.has(_v(ahead).to_lower())


func _at_op(op: String, ahead: int = 0) -> bool:
	return _k(ahead) == "op" and _v(ahead) == op


## Match by spelling regardless of keyword status.
func _at_word(word: String, ahead: int = 0) -> bool:
	var kind := _k(ahead)
	return (kind == "kw" or kind == "ident") and _v(ahead).to_lower() == word


func _at_word_any(words: Array, ahead: int = 0) -> bool:
	var kind := _k(ahead)
	return (kind == "kw" or kind == "ident") and words.has(_v(ahead).to_lower())


func _eat_kw(word: String) -> bool:
	if _at_kw(word):
		_advance()
		return true
	return false


func _eat_kw_any(words: Array) -> bool:
	if _at_kw_any(words):
		_advance()
		return true
	return false


func _eat_op(op: String) -> bool:
	if _at_op(op):
		_advance()
		return true
	return false


func _eat_word(word: String) -> bool:
	if _at_word(word):
		_advance()
		return true
	return false


func _expect_op(op: String) -> bool:
	if _eat_op(op):
		return true
	_fail("expected %s, got %s" % [JSON.stringify(op), JSON.stringify(_v())], _ln())
	return false


func _skip_newlines() -> void:
	while _k() == "nl":
		_advance()


func _fail(message: String, line: int) -> Dictionary:
	if error == "":
		error = message
		error_line = line
	return {}


func _failed() -> bool:
	return error != ""


# ------------------------------------------------------------------ top level

func _parse_script() -> Dictionary:
	var handlers: Array = []
	var properties: Array = []
	var globals: Array = []
	var loose: Array = []
	_skip_newlines()
	while _k() != "eof" and not _failed():
		if _at_kw("on"):
			handlers.append(_parse_handler())
		elif _at_kw_any(["property", "instance"]):
			_advance()
			properties.append_array(_parse_name_list())
		elif _at_kw("global"):
			_advance()
			globals.append_array(_parse_name_list())
		else:
			# Frame and cast scripts sometimes carry bare statements.
			loose.append(_parse_statement())
		_skip_newlines()
	if _failed():
		return {}
	return {
		"script": _name,
		"handlers": handlers,
		"properties": properties,
		"globals": globals,
		"body": loose,
	}


func _parse_name_list() -> Array:
	var names: Array = []
	while not _failed():
		var kind := _k()
		if kind != "ident" and kind != "kw":
			break
		names.append(_advance())
		if not _eat_op(","):
			break
	_skip_newlines()
	return names


func _parse_handler() -> Dictionary:
	var line := _ln()
	_advance() # on
	var name_kind := _k()
	var name := _advance()
	if name_kind != "ident" and name_kind != "kw":
		return _fail("handler needs a name", line)
	var params: Array = []
	while (_k() == "ident" or _k() == "kw") and not _failed():
		if _at_kw("end"):
			break
		params.append(_advance())
		if not _eat_op(","):
			break
	_skip_newlines()
	var body := _parse_block(["end"])
	if not _eat_kw("end"):
		return _fail("expected end", _ln())
	# `end mouseUp` names the handler again; swallow it.
	if _k() == "ident" or _k() == "kw":
		if _v().to_lower() == name.to_lower():
			_advance()
	_skip_newlines()
	return {
		"node": "handler", "name": name, "params": params,
		"body": body, "line": line,
	}


func _parse_block(stop_words: Array) -> Array:
	var statements: Array = []
	while not _failed():
		_skip_newlines()
		if _k() == "eof":
			return statements
		if _k() == "kw" and stop_words.has(_v().to_lower()):
			return statements
		# `otherwise:` inside a case, and bare case labels, stop a block.
		if stop_words.has("otherwise") and _at_kw("otherwise"):
			return statements
		statements.append(_parse_statement())
	return statements


# ------------------------------------------------------------------ statements

func _parse_statement() -> Dictionary:
	if _depth > MAX_DEPTH:
		return _fail("nested past %d levels" % MAX_DEPTH, _ln())
	_depth += 1
	var out := _parse_statement_inner()
	_depth -= 1
	return out


func _parse_statement_inner() -> Dictionary:
	var line := _ln()
	if _k() == "kw":
		match _v().to_lower():
			"global":
				_advance()
				return {"node": "global", "names": _parse_name_list(), "line": line}
			"property", "instance":
				_advance()
				return {"node": "property", "names": _parse_name_list(), "line": line}
			"if":
				return _parse_if()
			"repeat":
				return _parse_repeat()
			"case":
				return _parse_case()
			"put":
				return _parse_put()
			"set":
				return _parse_set()
			"exit":
				_advance()
				if _eat_kw("repeat"):
					_skip_newlines()
					return {"node": "exit_repeat", "line": line}
				_skip_newlines()
				return {"node": "exit", "line": line}
			"return":
				_advance()
				var value = null
				if _k() != "nl" and _k() != "eof":
					value = _parse_expr()
				_skip_newlines()
				return {"node": "return", "value": value, "line": line}
			"tell":
				return _parse_tell()
			"next":
				_advance()
				_eat_kw("repeat")
				_skip_newlines()
				return {"node": "next_repeat", "line": line}

	# Assignment to a place, or a command call. The left-hand side is parsed
	# above the comparison level so `=` is not swallowed: Lingo spells
	# assignment and equality alike and resolves it by position.
	var start := _i
	var place := _parse_expr(Grammar.NO_COMPARISON)
	if _failed():
		return {}
	if _at_op("=") and _is_place(place):
		_advance()
		var value := _parse_expr()
		_skip_newlines()
		return {"node": "assign", "target": place, "value": value, "line": line}
	# Not an assignment, so re-read the whole line as one expression.
	_i = start
	var call := _parse_expr()
	_skip_newlines()
	return {"node": "call_stmt", "call": call, "line": line}


static func _is_place(node: Dictionary) -> bool:
	return [
		"var", "prop", "sprite_prop", "member_prop", "chunk", "field",
		"field_prop", "menu_prop", "index", "dot", "prop_of",
	].has(str(node.get("node", "")))


func _parse_if() -> Dictionary:
	var line := _ln()
	_advance() # if
	var cond := _parse_expr()
	_eat_kw("then")
	# Single-line form: `if x then go("y")` with no `end if`.
	if _k() != "nl" and _k() != "eof":
		var then_one: Array = [_parse_statement()]
		var else_one: Array = []
		_skip_newlines()
		if _at_kw("else"):
			_advance()
			if _k() != "nl" and _k() != "eof":
				else_one = [_parse_statement()]
			else:
				else_one = _parse_block(["end", "else"])
				_finish_if()
		elif _at_kw("end") and _at_word("if", 1):
			_finish_if()
		return {"node": "if", "cond": cond, "then": then_one, "else": else_one, "line": line}

	var then_body := _parse_block(["end", "else"])
	var else_body: Array = []
	if _at_kw("else"):
		_advance()
		# `else if` chains without a matching `end if` per level.
		if _at_kw("if"):
			else_body = [_parse_if()]
			return {"node": "if", "cond": cond, "then": then_body, "else": else_body, "line": line}
		if _k() != "nl" and _k() != "eof":
			else_body = [_parse_statement()]
		else:
			else_body = _parse_block(["end"])
	_finish_if()
	return {"node": "if", "cond": cond, "then": then_body, "else": else_body, "line": line}


func _finish_if() -> void:
	if _eat_kw("end"):
		_eat_word("if")
	_skip_newlines()


func _parse_repeat() -> Dictionary:
	var line := _ln()
	_advance() # repeat
	if _eat_kw("while"):
		var cond := _parse_expr()
		_skip_newlines()
		var body := _parse_block(["end"])
		if not _eat_kw("end"):
			return _fail("expected end", _ln())
		_eat_word("repeat")
		_skip_newlines()
		return {"node": "repeat_while", "cond": cond, "body": body, "line": line}
	if _eat_kw("with"):
		var name := _advance()
		if _eat_kw("in"):
			var seq := _parse_expr()
			_skip_newlines()
			var in_body := _parse_block(["end"])
			if not _eat_kw("end"):
				return _fail("expected end", _ln())
			_eat_word("repeat")
			_skip_newlines()
			return {"node": "repeat_in", "var": name, "seq": seq, "body": in_body, "line": line}
		if not _expect_op("="):
			return {}
		var from := _parse_expr()
		var descending := false
		if _eat_kw("down"):
			descending = true
		if not _eat_kw("to"):
			return _fail("repeat with needs `to`", _ln())
		var stop := _parse_expr()
		_skip_newlines()
		var with_body := _parse_block(["end"])
		if not _eat_kw("end"):
			return _fail("expected end", _ln())
		_eat_word("repeat")
		_skip_newlines()
		return {
			"node": "repeat_with", "var": name, "from": from, "to": stop,
			"down": descending, "body": with_body, "line": line,
		}
	# `repeat` with no qualifier: loop until `exit repeat`.
	_skip_newlines()
	var forever := _parse_block(["end"])
	if not _eat_kw("end"):
		return _fail("expected end", _ln())
	_eat_word("repeat")
	_skip_newlines()
	return {"node": "repeat_forever", "body": forever, "line": line}


func _parse_case() -> Dictionary:
	var line := _ln()
	_advance() # case
	var subject := _parse_expr()
	if not _eat_kw("of"):
		return _fail("case needs `of`", _ln())
	# `case whatsound of :` — one script writes a colon after `of`, which
	# `tools/lingo_compile.py:477-479` does not eat.
	_eat_op(":")
	_skip_newlines()
	var branches: Array = []
	var default: Array = []
	while not _failed():
		_skip_newlines()
		if _k() == "eof" or _at_kw("end"):
			break
		if _at_kw("otherwise"):
			_advance()
			_eat_op(":")
			_skip_newlines()
			default = _parse_block(["end"])
			break
		var values: Array = [_parse_expr()]
		while _eat_op(",") and not _failed():
			values.append(_parse_expr())
		if not _expect_op(":"):
			return {}
		_skip_newlines()
		branches.append({"values": values, "body": _parse_case_body()})
	if not _eat_kw("end"):
		return _fail("expected end", _ln())
	_eat_word("case")
	_skip_newlines()
	return {
		"node": "case", "subject": subject, "branches": branches,
		"default": default, "line": line,
	}


## `tell the stage ... end tell`. Director retargets messages at another movie
## or window; this port has one stage, so the body simply runs, but the target
## is kept so a future multi-window case is not silently mistranslated.
func _parse_tell() -> Dictionary:
	var line := _ln()
	_advance() # tell
	var target := _parse_expr()
	# Single-line form: `tell the stage to go("x")`.
	if _eat_kw("to"):
		return {"node": "tell", "target": target, "body": [_parse_statement()], "line": line}
	_skip_newlines()
	var body := _parse_block(["end"])
	if not _eat_kw("end"):
		return _fail("expected end", _ln())
	_eat_word("tell")
	_skip_newlines()
	return {"node": "tell", "target": target, "body": body, "line": line}


## A branch runs until the next label, `otherwise`, or `end case`. Labels are
## not keyword-introduced — `"joystk":` is an expression followed by a colon —
## so the only way to know a branch ended is to look ahead for a top-level colon.
func _parse_case_body() -> Array:
	var statements: Array = []
	while not _failed():
		_skip_newlines()
		if _k() == "eof" or _at_kw_any(["end", "otherwise"]):
			return statements
		if _line_is_case_label():
			return statements
		statements.append(_parse_statement())
	return statements


func _line_is_case_label() -> bool:
	var depth := 0
	var j := _i
	while j < _kinds.size():
		var kind := _kinds[j]
		if kind == "nl" or kind == "eof":
			return false
		if kind == "op":
			var value := _values[j]
			if value == "(" or value == "[":
				depth += 1
			elif value == ")" or value == "]":
				depth -= 1
			elif value == ":" and depth == 0:
				return true
		j += 1
	return false


func _parse_put() -> Dictionary:
	var line := _ln()
	_advance() # put
	if _k() == "nl" or _k() == "eof":
		# A bare `put`. One script has this; in Director it echoes nothing.
		_skip_newlines()
		return {"node": "put_echo", "value": null, "line": line}
	var value := _parse_expr()
	var mode := "into"
	if _eat_kw("into"):
		mode = "into"
	elif _eat_kw("after"):
		mode = "after"
	elif _eat_kw("before"):
		mode = "before"
	else:
		# `put x` alone is Director's message-window echo. Harmless.
		_skip_newlines()
		return {"node": "put_echo", "value": value, "line": line}
	var target := _parse_expr()
	_skip_newlines()
	return {"node": "put", "mode": mode, "value": value, "target": target, "line": line}


func _parse_set() -> Dictionary:
	var line := _ln()
	_advance() # set
	var target := _parse_expr()
	if not (_eat_kw("to") or _eat_op("=")):
		return _fail("set needs `to`", _ln())
	var value := _parse_expr()
	_skip_newlines()
	return {"node": "assign", "target": target, "value": value, "line": line}


# ----------------------------------------------------------------- expressions

func _parse_expr(level: int = 0) -> Dictionary:
	if level >= Grammar.BINARY_LEVELS.size():
		return _parse_unary()
	if _depth > MAX_DEPTH:
		return _fail("expression nested past %d levels" % MAX_DEPTH, _ln())
	_depth += 1
	var left := _parse_expr(level + 1)
	while not _failed():
		var kind := _k()
		if kind != "op" and kind != "kw":
			break
		var op := _v().to_lower()
		if not Grammar.BINARY_LEVELS[level].has(op):
			break
		var op_line := _ln()
		_advance()
		var right := _parse_expr(level + 1)
		left = {"node": "binary", "op": op, "left": left, "right": right, "line": op_line}
	# `intersects` / `within` sit at the comparison level in practice. Their
	# line comes from the token *after* the operand, as in the original.
	if level == 2:
		while _at_kw_any(["intersects", "within"]) and not _failed():
			var op2 := _advance().to_lower()
			var right2 := _parse_expr(level + 1)
			left = {"node": "binary", "op": op2, "left": left, "right": right2, "line": _ln()}
	_depth -= 1
	return left


func _parse_unary() -> Dictionary:
	var line := _ln()
	if _at_kw("not"):
		_advance()
		return {"node": "unary", "op": "not", "value": _parse_unary(), "line": line}
	if _at_op("-"):
		_advance()
		return {"node": "unary", "op": "-", "value": _parse_unary(), "line": line}
	if _at_op("+"):
		# Unary plus, which `tools/lingo_compile.py:621-631` has no case for:
		# `go to marker(+1)` in MASTER.CST fails there and used to fail here.
		# It means nothing, so the operand is returned unchanged rather than
		# wrapped in a node the interpreter has never been given.
		_advance()
		return _parse_unary()
	return _parse_postfix()


func _parse_postfix() -> Dictionary:
	var node := _parse_primary()
	while not _failed():
		if _at_op(".") and (_k(1) == "ident" or _k(1) == "kw"):
			_advance()
			var prop := _advance()
			# Line from the following token, matching the original.
			node = {"node": "dot", "target": node, "prop": prop, "line": _ln()}
			continue
		if _at_op("(") and ["var", "dot"].has(str(node.get("node", ""))):
			var args := _parse_call_args()
			node = {"node": "call", "callee": node, "args": args, "line": _ln()}
			continue
		if _at_op("["):
			_advance()
			var index := _parse_expr()
			if _eat_op("."):
				_eat_op(".")
			if not _expect_op("]"):
				return {}
			node = {"node": "index", "target": node, "index": index, "line": _ln()}
			continue
		break
	return node


func _parse_call_args() -> Array:
	if not _expect_op("("):
		return []
	var args: Array = []
	if _eat_op(")"):
		return args
	while not _failed():
		args.append(_parse_expr())
		if _eat_op(","):
			continue
		_expect_op(")")
		return args
	return args


func _parse_primary() -> Dictionary:
	var kind := _k()
	var line := _ln()
	if kind == "number":
		var text := _advance()
		# int and float are distinct: `LingoValue.div` branches on the type, so
		# widening every literal to float would change division everywhere.
		var value = text.to_float() if text.contains(".") else text.to_int()
		return {"node": "num", "value": value, "line": line}
	if kind == "string":
		return {"node": "str", "value": _advance(), "line": line}
	if _at_op("("):
		_advance()
		var inner := _parse_expr()
		if not _expect_op(")"):
			return {}
		return inner
	if _at_op("["):
		_advance()
		var items: Array = []
		var pairs: Array = []
		if not _at_op("]"):
			while not _failed():
				var first := _parse_expr()
				if _eat_op(":"):
					pairs.append({"key": first, "value": _parse_expr()})
				else:
					items.append(first)
				if _eat_op(","):
					continue
				break
		if not _expect_op("]"):
			return {}
		if not pairs.is_empty():
			return {"node": "proplist", "pairs": pairs, "line": line}
		return {"node": "list", "items": items, "line": line}
	if _at_kw("the"):
		return _parse_the()
	if _at_kw("field"):
		_advance()
		# Both `field "x" of castLib "master"` and `field("x", "master")`.
		var name: Dictionary
		var cast = null
		if _at_op("("):
			var args := _parse_call_args()
			name = args[0] if args.size() > 0 else {"node": "str", "value": ""}
			cast = args[1] if args.size() > 1 else null
		else:
			name = _parse_expr(Grammar.TIGHT)
			cast = _parse_optional_castlib()
		return {"node": "field", "name": name, "cast": cast, "line": line}
	if _at_kw("sprite"):
		_advance()
		var target: Dictionary
		if _at_op("("):
			var args := _parse_call_args()
			target = args[0] if args.size() > 0 else {"node": "num", "value": 0}
		else:
			target = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
		return {"node": "sprite_ref", "which": target, "line": line}
	if _at_kw("member"):
		_advance()
		var which: Dictionary
		var mcast = null
		if _at_op("("):
			var args := _parse_call_args()
			which = args[0] if args.size() > 0 else {"node": "num", "value": 0}
			mcast = args[1] if args.size() > 1 else null
		else:
			which = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
			mcast = _parse_optional_castlib()
		return {"node": "member_ref", "which": which, "cast": mcast, "line": line}
	if _k() == "kw" and Grammar.CHUNKS.has(_v().to_lower()):
		return _parse_chunk()
	if kind == "ident" or kind == "kw":
		var name_text := _advance()
		var keywords = Grammar.COMMAND_WORDS.get(name_text.to_lower())
		# A command word followed by one of its own keywords is a command call,
		# whatever `_starts_command_args` thinks. That gate answers false for
		# `to`, which makes `go to the frame` — the statement every Director room
		# holds itself with — parse as a bare variable named `go` and abandon the
		# rest of the line. Silently: no error, no handler, and every room runs
		# on as though the script were empty.
		#
		# `tools/lingo_compile.py:765-784` has the same gate and never met the
		# spelling, because ProjectorRays rewrites it to the function form
		# `go(...)`. Author source writes it the way Director documents it.
		var command_head: bool = (
			keywords != null
			and (_k() == "ident" or _k() == "kw")
			and keywords.has(_v().to_lower())
		)
		# Command-form call: `go "label"`, `sound playFile 1, x`. An operator or
		# a newline means a bare variable reference instead.
		if command_head or _starts_command_args():
			var args: Array = []
			while (keywords != null and (_k() == "ident" or _k() == "kw")
					and keywords.has(_v().to_lower()) and not _at_op("(", 1)):
				args.append({"node": "str", "value": _advance(), "line": line})
			if not (not args.is_empty() and (_k() == "nl" or _k() == "eof")):
				if not args.is_empty() and not _at_op(","):
					args.append(_parse_expr())
				elif args.is_empty():
					args.append(_parse_expr())
				while _eat_op(",") and not _failed():
					args.append(_parse_expr())
			# The callee carries no `line`, unlike every other `var` node.
			return {
				"node": "call", "callee": {"node": "var", "name": name_text},
				"args": args, "command": true, "line": line,
			}
		return {"node": "var", "name": name_text, "line": line}
	return _fail("unexpected %s" % JSON.stringify(_v()), line)


func _starts_command_args() -> bool:
	var kind := _k()
	if kind == "nl" or kind == "eof":
		return false
	if kind == "number" or kind == "string":
		return true
	if kind == "op":
		return _v() == "["
	if kind == "kw":
		var low := _v().to_lower()
		if ["the", "field", "sprite", "member", "not"].has(low) or Grammar.CHUNKS.has(low):
			return true
		return false
	# A following identifier means a command word pair: `sound playFile`, `go to`.
	return true


func _parse_optional_castlib():
	if _at_kw("of") and _at_word("castlib", 1):
		_advance()
		_advance()
		return _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
	return null


func _parse_chunk() -> Dictionary:
	var line := _ln()
	var kind := _advance().to_lower()
	var start := _parse_expr(Grammar.ADDITIVE)
	var stop = null
	if _eat_kw("to"):
		stop = _parse_expr(Grammar.ADDITIVE)
	if not _eat_kw("of"):
		return _fail("%s chunk needs `of`" % kind, _ln())
	var source := _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
	return {
		"node": "chunk", "kind": kind, "start": start, "stop": stop,
		"source": source, "line": line,
	}


func _parse_the() -> Dictionary:
	var line := _ln()
	_advance() # the
	# `the number of lines in x` counts, but `the number of member "x"` is that
	# member's number. Same three words, different meaning.
	if _at_word("number") and _at_kw("of", 1):
		_advance()
		_advance()
		if _at_word_any(["member", "castmember"]):
			_advance()
			var which: Dictionary
			var cast = null
			if _at_op("("):
				var args := _parse_call_args()
				which = args[0] if args.size() > 0 else {"node": "num", "value": 0}
				cast = args[1] if args.size() > 1 else _parse_optional_castlib()
			else:
				which = _parse_expr(Grammar.ADDITIVE)
				cast = _parse_optional_castlib()
			return {"node": "member_number", "which": which, "cast": cast, "line": line}
		if _at_word("sprite"):
			_advance()
			return {"node": "sprite_number", "which": _parse_expr(Grammar.TIGHT), "line": line}
		# One trailing `s` only: `lines` -> `line`. Stripping every trailing `s`
		# is the accidental behaviour of the original and no unit needs it.
		var unit := _advance().to_lower().trim_suffix("s")
		if not (_eat_kw("in") or _eat_kw("of")):
			return _fail("`the number of X` needs `in`", _ln())
		return {"node": "count", "unit": unit, "source": _parse_expr(Grammar.TIGHT), "line": line}

	# Adjective-style system properties: `the long time`. Only a handful of
	# adjectives may precede the property, and no reserved word may be swallowed
	# as one, or `set the keyDownScript to EMPTY` reads its property as "to".
	var words: Array = []
	while _k() == "ident" or _k() == "kw":
		if Grammar.RESERVED_AFTER_PROP.has(_v().to_lower()):
			break
		words.append(_advance())
		if words.size() >= 2 or not Grammar.THE_ADJECTIVES.has(str(words[words.size() - 1]).to_lower()):
			break
	if words.is_empty():
		return _fail("`the` needs a property", line)
	var prop := str(words[words.size() - 1]).to_lower()

	if _eat_kw("of"):
		if _at_kw("sprite"):
			_advance()
			var which: Dictionary
			if _at_op("("):
				var args := _parse_call_args()
				which = args[0] if args.size() > 0 else {"node": "num", "value": 0}
			else:
				which = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
			return {"node": "sprite_prop", "prop": prop, "which": which, "line": line}
		if _at_kw("member"):
			_advance()
			var mwhich: Dictionary
			var mcast = null
			if _at_op("("):
				var args := _parse_call_args()
				mwhich = args[0] if args.size() > 0 else {"node": "num", "value": 0}
				mcast = args[1] if args.size() > 1 else null
			else:
				mwhich = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
				mcast = _parse_optional_castlib()
			return {
				"node": "member_prop", "prop": prop, "which": mwhich,
				"cast": mcast, "line": line,
			}
		# `the volume of sound 2`. A sound channel is a designator, exactly like
		# `sprite` and `member`, and it is not a keyword — so without this it
		# falls through to the generic branch, `sound 2` parses as a command-form
		# call, and the assignment target becomes a property of a call, which
		# nothing can write to. The statement is then dropped with an error the
		# player never sees, in 52 scripts.
		if _at_word("sound"):
			_advance()
			var which_sound: Dictionary
			if _at_op("("):
				var sargs := _parse_call_args()
				which_sound = sargs[0] if sargs.size() > 0 else {"node": "num", "value": 0}
			else:
				which_sound = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
			return {"node": "sound_prop", "prop": prop, "which": which_sound, "line": line}
		if _at_kw("field"):
			_advance()
			var fname := _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
			var fcast = _parse_optional_castlib()
			return {
				"node": "field_prop", "prop": prop, "name": fname,
				"cast": fcast, "line": line,
			}
		var target := _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
		return {"node": "prop_of", "prop": prop, "target": target, "line": line}

	var lowered: Array = []
	for word in words:
		lowered.append(str(word).to_lower())
	return {"node": "prop", "prop": prop, "words": lowered, "line": line}
