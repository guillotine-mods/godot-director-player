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

	# `delete word 1 of str`, `delete char 1 of linetext` (§16.2 listed this as a
	# known gap). **A statement, not a call**, because the chunk is a *place* and
	# the statement rewrites what holds it -- parsed as a command call, `delete`
	# received the chunk's *value*, the variable never shortened, and
	# `itamar-park`'s `repeat while str <> EMPTY / add(Languages, word 1 of str) /
	# delete word 1 of str` spun until the step budget aborted the handler.
	# Measured that way: 199,833 calls to an unbound `delete` in one boot.
	#
	# Gated on a chunk keyword following, so an ordinary handler or builtin
	# called `delete` -- FileIO has one, and it takes an instance -- still parses
	# as the call it is.
	if _at_word("delete") and _k(1) == "kw" and Grammar.CHUNKS.has(_v(1).to_lower()):
		_advance()
		var doomed := _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
		_skip_newlines()
		return {"node": "delete_chunk", "target": doomed, "line": line}

	if _at_when_event():
		return _parse_when()

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


## Director 3's primary-handler installation: `when keyDown then <text>` (§11.2).
##
## Five events only — `keyDown`, `keyUp`, `mouseDown`, `mouseUp`, `timeOut` — and
## the shape has to be all three tokens before it is claimed, because `when` is
## an ordinary identifier here (§11.3: nothing in Lingo is reserved) and a
## variable of that name is legal. Requiring `when <one of five> then` means the
## only thing that can be captured is the construct itself.
func _at_when_event() -> bool:
	return (
		_at_word("when")
		and _at_word_any(["keydown", "keyup", "mousedown", "mouseup", "timeout"], 1)
		and _at_word("then", 2)
	)


## In ScummVM's lexer this is *one token* whose tail is taken raw to end of line
## and compiled separately as a primary event handler (§11.2, §11.13.7). By the
## time this parser runs the text is already tokens, so the tail is parsed here
## instead and hung off the node rather than emitted into the enclosing block.
## The distinction that matters is not where it is parsed but that it does not
## *run* here: a primary handler runs at tier 1 of the mouse/key hierarchy
## (§6.3), before the sprite the click landed on, and this port implements no
## tier 1 at all.
##
## So this is deliberately a recorded gap and not an implementation.
## `lingo_interpreter.gd` reports the node and executes nothing, which §16.3 asks
## for in as many words: parsing it "would only convert a silent misparse into a
## recorded unimplemented feature — which is still the better of the two". What
## it replaces is genuinely junk — `when` became a call to a handler of that name
## taking `keyDown` as an argument, and `then go to "mainmenub4"` became a second
## statement, so the *navigation ran unconditionally* on every entry to
## `strtgame`'s `gomenu`.
##
## Storing the parsed tail rather than the source text costs one thing, recorded:
## a real primary handler is compiled in its own scope, so if tier 1 is ever
## implemented the body here must be treated as a separate handler and not as a
## closure over the enclosing frame.
func _parse_when() -> Dictionary:
	var line := _ln()
	_advance() # when
	var event := _advance().to_lower()
	_advance() # then
	var body: Array = []
	if _k() != "nl" and _k() != "eof":
		body.append(_parse_statement())
	_skip_newlines()
	return {"node": "when", "event": event, "body": body, "line": line}


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


## `set <place> to <value>` and `set <place> = <value>`, which Director accepts
## interchangeably.
##
## The target is parsed above the comparison level for the same reason the bare
## assignment at `_parse_statement` is: `=` is Lingo's equality operator as well
## as its assignment operator, and a full-precedence parse of the target swallows
## it — `set the searchpath = [...]` came back as one comparison expression, the
## `=` was gone by the time this function looked for it, and the statement failed
## with "set needs `to`".
##
## It fails the *whole script*, not the statement: a handler that will not compile
## is a handler that never runs, and nothing at run time says so. Piposh 1
## English lost 27 of `strtgame.dir`'s 75 scripts to this one line — every
## `option1`..`option26` frame of the CD-drive probe, which is what sets
## `cdsavepath`, `soundspathstart` and `gWinDriveLetter` for the rest of the
## game. The Hebrew and Russian builds of the same title spell every `set` with
## `to` and lost nothing, which is why it took a third localisation to surface.
func _parse_set() -> Dictionary:
	var line := _ln()
	_advance() # set
	var target := _parse_expr(Grammar.NO_COMPARISON)
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
	if kind == "symbol":
		# `#mouseUp` (§11.2). A literal like a number or a string -- the `#` is
		# gone by the time the lexer hands it over, so this carries the bare name
		# and the interpreter makes it a StringName, which is what this port's
		# `ilk` and `symbolP` already recognise as a symbol.
		return {"node": "sym", "value": _advance(), "line": line}
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
			# `of castLib` is part of the *reference*, not a trailing modifier
			# that may be dropped (§11.8, §11.13.15). The bare-string path below
			# has always looked for it; the parenthesised one did not, so
			# `field ("save" & i) of castLib 1` lost its library and left
			# `of castLib 1` behind as a statement calling a handler named `of`.
			# SAVELOAD scripts 20, 24, 38 and 39 write the save-slot names that
			# way, which is why the four save slots showed the wrong cast's text.
			cast = args[1] if args.size() > 1 else _parse_optional_castlib()
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
			# The same omission as `field(…)` above. No site in this game reaches
			# it — `member(…) of castLib …` only appears under `the number of`,
			# which `_parse_the` already handles — so this changes no AST here and
			# closes the shape for the next title rather than for this one.
			mcast = args[1] if args.size() > 1 else _parse_optional_castlib()
		else:
			which = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
			mcast = _parse_optional_castlib()
		return {"node": "member_ref", "which": which, "cast": mcast, "line": line}
	# `script "Parent"`, `script(12)` -- §7.1's designator for a script cast
	# member, and the argument of every `new`.
	#
	# **It takes exactly one operand, and that is the whole reason this arm
	# exists.** Without it `script` is an ordinary identifier, so `script "base"`
	# reaches the command-call path below, whose argument loop continues across
	# commas -- and `new(script "base", who)` then parses as `new(script("base",
	# who))`, handing the constructor's arguments to the designator and the
	# constructor none. Measured exactly that way: every property a parent script
	# set from an argument came out 0.
	#
	# Narrowed to a literal or a parenthesis on purpose. `script` is not a keyword
	# here and must not become one -- a title with a *variable* called `script`
	# would have every read of it swallow the next expression -- and a variable is
	# never followed by a string or a number.
	#
	# The result is a call to the `script` builtin rather than a node of its own,
	# so the designator spelling and the function spelling are one implementation
	# (`lingo_interpreter.gd:_own_builtin`) and cannot answer differently.
	if _at_word("script") and (_k(1) == "string" or _k(1) == "number" or _at_op("(", 1)):
		_advance()
		var script_which: Dictionary
		if _at_op("("):
			var script_args := _parse_call_args()
			script_which = script_args[0] if script_args.size() > 0 \
				else {"node": "num", "value": 0}
		else:
			script_which = _parse_expr(Grammar.TIGHT)
		return {
			"node": "call", "callee": {"node": "var", "name": "script"},
			"args": [script_which], "line": line,
		}
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
			# A command's own keyword is a keyword wherever it stands, including
			# immediately before `(`. Lingo has no `movie()`, `frame()` or
			# `window()` function for it to be mistaken for, so the parenthesis
			# after one opens either a grouped expression — `go to movie
			# (cdsavepath & "opening.dxr")` — or the command's arguments written in
			# call form. Both are handled below; treating the word as a callee
			# instead produced `go("to", movie(<path>))`, in which nothing looks
			# like a movie and no `movie` keyword survives, so `_go` fell through to
			# its marker branch, found no marker of that name and parked the
			# playhead on frame 0 with the music still running. That is
			# `strtgame.dir`'s Start Game button in Piposh 1 English: measured with
			# the old reading it lands on frame 0 of the movie it is already in,
			# with the button's `sound playFile` still running — "the music plays
			# and the scene never changes" — and with the new one it opens
			# `Opening.dir`, which is what the Hebrew build (spelt `go(1, …)`, so
			# never affected) has always done.
			#
			# The `window` sites in the same corpus are the other half of the same
			# misparse and are **not** behaviourally broken, measured the same way:
			# `open window (…)` mis-read as `open(window(…))` happens to land on a
			# binding that means the same thing. They are fixed here because the
			# parse was wrong, not because anything visible was.
			while (keywords != null and (_k() == "ident" or _k() == "kw")
					and keywords.has(_v().to_lower())):
				args.append({"node": "str", "value": _advance(), "line": line})
			if not (not args.is_empty() and (_k() == "nl" or _k() == "eof")):
				if not args.is_empty() and _at_op("(") and _paren_holds_arg_list():
					# `sound playFile(1, x)` — the call spelling of the command form.
					# Told apart from a grouped first argument by a comma at the
					# group's own depth, because `(a & b)` and `(a, b)` are different
					# statements and the parenthesis alone cannot say which.
					for a in _parse_call_args():
						args.append(a)
				elif not args.is_empty() and not _at_op(","):
					args.append(_parse_expr())
				elif args.is_empty():
					args.append(_parse_expr())
				while _eat_op(",") and not _failed():
					args.append(_parse_expr())
			var movie = _parse_optional_of_movie(keywords)
			if movie != null:
				args.append(movie)
			# The callee carries no `line`, unlike every other `var` node.
			return {
				"node": "call", "callee": {"node": "var", "name": name_text},
				"args": args, "command": true, "line": line,
			}
		return {"node": "var", "name": name_text, "line": line}
	return _fail("unexpected %s" % JSON.stringify(_v()), line)


## Does the parenthesised group the cursor is sitting on hold a comma of its own?
##
## Only the group's own depth counts: `(marker(0), 1)` is an argument list and
## `(f(a, b) & c)` is one expression, and a scan that did not track depth would
## call both the same. A group that runs to the end of the line without closing
## is not an argument list either — the caller then parses it as an expression
## and the missing `)` is reported there, where the error has the right line.
func _paren_holds_arg_list() -> bool:
	var depth := 0
	var ahead := 0
	while true:
		var kind := _k(ahead)
		if kind == "eof" or kind == "nl":
			return false
		if kind == "op":
			var op := _v(ahead)
			if op == "(" or op == "[":
				depth += 1
			elif op == ")" or op == "]":
				depth -= 1
				if depth <= 0:
					return false
			elif op == "," and depth == 1:
				return true
		ahead += 1
	return false


func _starts_command_args() -> bool:
	var kind := _k()
	if kind == "nl" or kind == "eof":
		return false
	# A symbol is a literal like the other two, so `call #mouseUp, obj` -- the
	# command spelling of the messaging builtins -- starts an argument list here
	# exactly as `sound playFile 1, x` does.
	if kind == "number" or kind == "string" or kind == "symbol":
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


## The movie half of `go to frame E of movie F`, or null when there is none.
##
## `of movie` is part of `go`'s and `play`'s frame-argument grammar (§11.5), not
## a modifier hanging off the label — the same distinction `_parse_optional_castlib`
## draws for a cast reference. Without it the argument loop stopped at the label,
## because the token after it is not a comma, and the leftover `of movie …`
## became a statement of its own calling a handler named `of`. The jump then
## landed on a marker of that name *in the current movie*: four of the six sites
## are the save/load round trip in `HEZSAVE.DIR` and two are the return into
## `day1` after a cutscene, so the destination was silently the room the player
## was already in.
##
## Gated on the command's own keyword set rather than on the spelling `go`, so
## `play` gets it for free and nothing else can pick it up: only `go` and `play`
## list `movie` in `Grammar.COMMAND_WORDS`.
##
## The movie is appended as a plain second argument, with no `"movie"` marker
## word between it and the frame. That is the `(frame_or_marker, movie)` shape
## `lingo_host.gd:_go` already reads for the `go(1, "exodus.dir")` spelling — it
## keys off the *second* argument ending in `.dxr`/`.dir` — so this needs no host
## change. Inserting the word `"movie"` would instead push the pair into `_go`'s
## `go to movie "x"` branch, which discards the frame.
func _parse_optional_of_movie(keywords):
	if keywords == null or not (keywords as Dictionary).has("movie"):
		return null
	if not (_at_kw("of") and _at_word("movie", 1)):
		return null
	_advance() # of
	_advance() # movie
	# A full expression, because the path is built: `of movie cdsavepath &
	# "saveload.dxr"` in all four HEZSAVE sites.
	return _parse_expr()


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
				# The fourth site of the same omission, and the one that was still
				# open: `:752`, `:777` and `:975` all reach for the trailing
				# `of castLib` after a parenthesised designator and this one did
				# not. It does not error -- the clause is simply left on the
				# floor, and what is left compiles: a bare `of`, a call to
				# `castlib("…")` and a call to `into(x)`, so the assignment in
				#
				#     put the name of member (the memberNum of sprite 1) ¬
				#         of castLib "decks" into x
				#
				# never happens and every later mention of `x` becomes a call to
				# a handler of that name returning VOID. `MASTER.CST` member 31
				# is `jokesfunk` and `cardsfunk`, run on every room entry in all
				# three Piposh 1 localisations, and both fall to their final
				# `else` because of it -- a collected joke's sprite stays hidden
				# for the rest of the movie. `tools/parse_residue.gd` finds the
				# leftovers; a dropped designator clause has now cost four
				# player-visible bugs (bugs.md 16 is one of them).
				mcast = args[1] if args.size() > 1 else _parse_optional_castlib()
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
		# `set the windowType of window "joke.dxr" to 2`. Same shape as `sound`
		# above and the same failure: `window` is not a keyword, so the generic
		# branch below made it a command-form call and the property became
		# `prop_of` over a *call*, which `_assign` has no case for. It recorded
		# `cannot assign to prop_of call` and carried on. The tell is that the dot
		# spelling `window("x").windowType = 2` already worked, because the `dot`
		# assignment path accepts an owner that evaluates to a string — so two
		# spellings of one statement behaved differently, which is the kind of
		# divergence that gets diagnosed as a data problem months later.
		# MASTER.CST scripts 12 and 69.
		if _at_word("window"):
			_advance()
			var which_window: Dictionary
			if _at_op("("):
				var wargs := _parse_call_args()
				which_window = wargs[0] if wargs.size() > 0 else {"node": "str", "value": ""}
			else:
				which_window = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
			return {"node": "window_prop", "prop": prop, "which": which_window, "line": line}
		# `the name of castLib 2`, `the fileName of castLib "sounds"` (§5.1).
		# `castlib` *is* a keyword here, and that is exactly why it needed an arm:
		# without one it fell to the generic branch below, where a keyword
		# followed by a number is a command-form call, so the statement became a
		# property of a call to an unbound handler named `castlib`. Every such
		# read reported a missing builtin and answered VOID.
		if _at_kw("castlib"):
			_advance()
			var which_cast: Dictionary
			if _at_op("("):
				var cargs := _parse_call_args()
				which_cast = cargs[0] if cargs.size() > 0 else {"node": "num", "value": 0}
			else:
				which_cast = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
			return {"node": "cast_prop", "prop": prop, "which": which_cast, "line": line}
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
