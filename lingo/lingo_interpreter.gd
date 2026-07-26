class_name LingoInterpreter
extends RefCounted
## Tree-walking interpreter for the ASTs that tools/lingo_compile.py produces.
##
## Everything Director-specific goes through `host`, so this file is testable on
## its own and the engine bindings stay in one place (lingo/lingo_host.gd).
## The host must provide:
##
##   get_field(name, cast) -> String
##   set_field(name, cast, text) -> void
##   get_sprite_prop(channel, prop) -> Variant
##   set_sprite_prop(channel, prop, value) -> void
##   get_member_prop(which, cast, prop) -> Variant
##   set_member_prop(which, cast, prop, value) -> void
##   member_number(which, cast) -> int
##   get_system_prop(prop) -> Variant
##   set_system_prop(prop, value) -> void
##   call_builtin(name, args) -> Array  # [handled: bool, value: Variant]

enum Flow { NORMAL, EXIT_REPEAT, NEXT_REPEAT, RETURN, ABORT }

## Runaway guard. `repeat while` with a condition the host never changes would
## otherwise hang the frame.
const MAX_STEPS := 400000

var globals: Dictionary = {}
var host: Object = null
var item_delimiter: String = ","
var errors: PackedStringArray = PackedStringArray()

## Handlers reachable from anywhere: movie scripts.
var _movie_handlers: Dictionary = {}
## cast -> script name -> ast, for behaviour and cast scripts.
var _scripts: Dictionary = {}
var _steps: int = 0
var _return_value: Variant = null
var _depth: int = 0


func _init(host_object: Object = null) -> void:
	host = host_object


# ---------------------------------------------------------------- loading


func load_bundle(bundle: Dictionary) -> void:
	## One compiled cast: {"movie":…, "cast":…, "scripts": {name: ast}}
	var cast := str(bundle.get("cast", ""))
	var scripts: Dictionary = bundle.get("scripts", {})
	var by_name: Dictionary = _scripts.get(cast, {})
	for script_name in scripts.keys():
		var ast: Dictionary = scripts[script_name]
		by_name[str(script_name)] = ast
		# A MovieScript's handlers are globally callable. Behaviour and cast
		# scripts are reached through their owning sprite or member instead.
		if str(script_name).to_lower().begins_with("moviescript"):
			for handler in ast.get("handlers", []):
				var key := str(handler.get("name", "")).to_lower()
				if key != "" and not _movie_handlers.has(key):
					_movie_handlers[key] = {"handler": handler, "cast": cast,
						"script": script_name}
	_scripts[cast] = by_name


func script_count() -> int:
	var total := 0
	for cast in _scripts.keys():
		total += (_scripts[cast] as Dictionary).size()
	return total


func movie_handler_names() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _movie_handlers.keys():
		out.append(str(key))
	out.sort()
	return out


func find_script(cast: String, script_name: String) -> Dictionary:
	var by_name: Variant = _scripts.get(cast, {})
	if typeof(by_name) != TYPE_DICTIONARY:
		return {}
	var ast: Variant = (by_name as Dictionary).get(script_name, {})
	return ast if typeof(ast) == TYPE_DICTIONARY else {}


func find_script_by_member(cast: String, member: int) -> Dictionary:
	## ProjectorRays names a script after the cast member that owns it, so
	## "BehaviorScript 108" is master member 108. That is the whole attachment
	## mechanism (see tools/dump_sprite_scripts.py).
	var by_name: Variant = _scripts.get(cast, {})
	if typeof(by_name) != TYPE_DICTIONARY:
		return {}
	var suffix := " %d" % member
	for script_name in (by_name as Dictionary).keys():
		var name := str(script_name)
		var head := name.split(" - ")[0]
		if head.ends_with(suffix):
			return (by_name as Dictionary)[script_name]
	return {}


# ---------------------------------------------------------------- calling


func has_handler(name: String) -> bool:
	return _movie_handlers.has(name.to_lower())


func call_handler(name: String, args: Array = [], script: Dictionary = {}) -> Variant:
	## Resolution order is Director's, narrowed to what this port needs: the
	## script that owns the event first, then any movie script.
	var key := name.to_lower()
	if not script.is_empty():
		for handler in script.get("handlers", []):
			if str(handler.get("name", "")).to_lower() == key:
				return _invoke(handler, args, script)
	if _movie_handlers.has(key):
		var entry: Dictionary = _movie_handlers[key]
		var owner := find_script(str(entry.get("cast", "")), str(entry.get("script", "")))
		return _invoke(entry["handler"], args, owner)
	return null


func _invoke(handler: Dictionary, args: Array, script: Dictionary) -> Variant:
	if _depth > 64:
		_fail("handler recursion too deep at %s" % str(handler.get("name", "?")))
		return null
	_depth += 1
	var frame := {
		"locals": {},
		"script": script,
		"globals": {},
	}
	var params: Array = handler.get("params", [])
	for i in params.size():
		frame["locals"][str(params[i]).to_lower()] = args[i] if i < args.size() else 0
	_return_value = null
	var flow := _exec_block(handler.get("body", []), frame)
	_depth -= 1
	if flow == Flow.RETURN:
		return _return_value
	return null


func run_handler_in_script(script: Dictionary, name: String, args: Array = []) -> bool:
	## Returns false when the script has no such handler, so callers can fall
	## through the message hierarchy.
	var key := name.to_lower()
	for handler in script.get("handlers", []):
		if str(handler.get("name", "")).to_lower() == key:
			_invoke(handler, args, script)
			return true
	return false


func reset_steps() -> void:
	_steps = 0
	errors.clear()


# ---------------------------------------------------------------- statements


func _exec_block(stmts: Variant, frame: Dictionary) -> int:
	if typeof(stmts) != TYPE_ARRAY:
		return Flow.NORMAL
	for stmt in stmts:
		if typeof(stmt) != TYPE_DICTIONARY:
			continue
		var flow := _exec(stmt, frame)
		if flow != Flow.NORMAL:
			return flow
	return Flow.NORMAL


func _exec(stmt: Dictionary, frame: Dictionary) -> int:
	_steps += 1
	if _steps > MAX_STEPS:
		_fail("step budget exhausted")
		return Flow.ABORT
	match str(stmt.get("node", "")):
		"global", "property":
			for name in stmt.get("names", []):
				var key := str(name).to_lower()
				frame["globals"][key] = true
				if not globals.has(key):
					globals[key] = 0
			return Flow.NORMAL
		"assign":
			_assign(stmt.get("target", {}), _eval(stmt.get("value", {}), frame), frame)
			return Flow.NORMAL
		"put":
			var value: Variant = _eval(stmt.get("value", {}), frame)
			var target: Dictionary = stmt.get("target", {})
			var mode := str(stmt.get("mode", "into"))
			if mode == "into":
				_assign(target, value, frame)
			else:
				var existing := LingoValue.to_str(_eval(target, frame))
				var joined := (
					existing + LingoValue.to_str(value)
					if mode == "after"
					else LingoValue.to_str(value) + existing
				)
				_assign(target, joined, frame)
			return Flow.NORMAL
		"put_echo":
			return Flow.NORMAL
		"call_stmt":
			_eval(stmt.get("call", {}), frame)
			return Flow.NORMAL
		"if":
			if LingoValue.truthy(_eval(stmt.get("cond", {}), frame)):
				return _exec_block(stmt.get("then", []), frame)
			return _exec_block(stmt.get("else", []), frame)
		"repeat_while":
			while LingoValue.truthy(_eval(stmt.get("cond", {}), frame)):
				_steps += 1
				if _steps > MAX_STEPS:
					_fail("repeat while did not terminate")
					return Flow.ABORT
				var flow := _exec_block(stmt.get("body", []), frame)
				if flow == Flow.EXIT_REPEAT:
					break
				if flow == Flow.RETURN or flow == Flow.ABORT:
					return flow
			return Flow.NORMAL
		"repeat_with":
			var name := str(stmt.get("var", "")).to_lower()
			var from := LingoValue.to_int(_eval(stmt.get("from", {}), frame))
			var to := LingoValue.to_int(_eval(stmt.get("to", {}), frame))
			var down := bool(stmt.get("down", false))
			var step := -1 if down else 1
			var i := from
			while (i <= to) if not down else (i >= to):
				_set_var(name, i, frame)
				var flow := _exec_block(stmt.get("body", []), frame)
				if flow == Flow.EXIT_REPEAT:
					break
				if flow == Flow.RETURN or flow == Flow.ABORT:
					return flow
				i += step
				_steps += 1
				if _steps > MAX_STEPS:
					_fail("repeat with did not terminate")
					return Flow.ABORT
			return Flow.NORMAL
		"repeat_in":
			var name := str(stmt.get("var", "")).to_lower()
			var seq: Variant = _eval(stmt.get("seq", {}), frame)
			var items: Array = seq if typeof(seq) == TYPE_ARRAY else []
			for value in items:
				_set_var(name, value, frame)
				var flow := _exec_block(stmt.get("body", []), frame)
				if flow == Flow.EXIT_REPEAT:
					break
				if flow == Flow.RETURN or flow == Flow.ABORT:
					return flow
			return Flow.NORMAL
		"repeat_forever":
			while true:
				_steps += 1
				if _steps > MAX_STEPS:
					_fail("bare repeat did not terminate")
					return Flow.ABORT
				var flow := _exec_block(stmt.get("body", []), frame)
				if flow == Flow.EXIT_REPEAT:
					break
				if flow == Flow.RETURN or flow == Flow.ABORT:
					return flow
			return Flow.NORMAL
		"case":
			var subject: Variant = _eval(stmt.get("subject", {}), frame)
			for branch in stmt.get("branches", []):
				for candidate in (branch as Dictionary).get("values", []):
					if LingoValue.equal(subject, _eval(candidate, frame)):
						return _exec_block((branch as Dictionary).get("body", []), frame)
			return _exec_block(stmt.get("default", []), frame)
		"tell":
			# One stage in this port, so the body simply runs.
			return _exec_block(stmt.get("body", []), frame)
		"exit_repeat":
			return Flow.EXIT_REPEAT
		"next_repeat":
			return Flow.NEXT_REPEAT
		"exit":
			return Flow.RETURN
		"return":
			var node: Variant = stmt.get("value", null)
			_return_value = _eval(node, frame) if node != null else null
			return Flow.RETURN
		_:
			_fail("unknown statement %s" % str(stmt.get("node", "?")))
			return Flow.NORMAL


# ---------------------------------------------------------------- assignment


func _assign(target: Dictionary, value: Variant, frame: Dictionary) -> void:
	match str(target.get("node", "")):
		"var":
			_set_var(str(target.get("name", "")).to_lower(), value, frame)
		"field":
			_set_field_node(target, LingoValue.to_str(value), frame)
		"sprite_prop":
			var channel := LingoValue.to_int(_eval(target.get("which", {}), frame))
			_host_call("set_sprite_prop", [channel, str(target.get("prop", "")), value])
		"member_prop":
			_host_call("set_member_prop", [
				_eval(target.get("which", {}), frame),
				_cast_of(target, frame),
				str(target.get("prop", "")),
				value,
			])
		"field_prop":
			_set_field_node({"node": "field", "name": target.get("name", {}),
				"cast": target.get("cast", null)}, LingoValue.to_str(value), frame)
		"prop":
			var prop := str(target.get("prop", "")).to_lower()
			if prop == "itemdelimiter":
				item_delimiter = LingoValue.to_str(value)
				return
			_host_call("set_system_prop", [prop, value])
		"prop_of":
			var owner: Dictionary = target.get("target", {})
			if str(owner.get("node", "")) == "sprite_ref":
				var channel := LingoValue.to_int(_eval(owner.get("which", {}), frame))
				_host_call("set_sprite_prop", [channel, str(target.get("prop", "")), value])
				return
			_fail("cannot assign to prop_of %s" % str(owner.get("node", "?")))
		"dot":
			var owner_node: Dictionary = target.get("target", {})
			var prop_name := str(target.get("prop", ""))
			if str(owner_node.get("node", "")) == "sprite_ref":
				var channel := LingoValue.to_int(_eval(owner_node.get("which", {}), frame))
				_host_call("set_sprite_prop", [channel, prop_name, value])
				return
			if str(owner_node.get("node", "")) == "member_ref":
				_host_call("set_member_prop", [
					_eval(owner_node.get("which", {}), frame),
					_cast_of(owner_node, frame), prop_name, value,
				])
				return
			_fail("cannot assign to %s.%s" % [str(owner_node.get("node", "?")), prop_name])
		"chunk":
			_assign_chunk(target, value, frame)
		_:
			_fail("cannot assign to %s" % str(target.get("node", "?")))


func _assign_chunk(target: Dictionary, value: Variant, frame: Dictionary) -> void:
	## `put x into line i of field "f"` and the nested forms. The source has to be
	## read, edited and written back, so only sources that are themselves
	## assignable can carry a chunk write.
	var kind := str(target.get("kind", "line"))
	var start := LingoValue.to_int(_eval(target.get("start", {}), frame))
	var stop_node: Variant = target.get("stop", null)
	var stop := LingoValue.to_int(_eval(stop_node, frame)) if stop_node != null else start
	var source: Dictionary = target.get("source", {})
	var text := LingoValue.to_str(_eval(source, frame))
	var updated := LingoValue.set_chunk(text, kind, start, stop, value, item_delimiter)
	_assign(source, updated, frame)


func _set_var(name: String, value: Variant, frame: Dictionary) -> void:
	if (frame.get("globals", {}) as Dictionary).has(name) or globals.has(name):
		globals[name] = value
		return
	(frame["locals"] as Dictionary)[name] = value


func _set_field_node(node: Dictionary, text: String, frame: Dictionary) -> void:
	_host_call("set_field", [
		LingoValue.to_str(_eval(node.get("name", {}), frame)),
		_cast_of(node, frame),
		text,
	])


func _cast_of(node: Dictionary, frame: Dictionary) -> String:
	var cast: Variant = node.get("cast", null)
	if cast == null:
		return ""
	return LingoValue.to_str(_eval(cast, frame))


# ---------------------------------------------------------------- expressions


func _eval(node: Variant, frame: Dictionary) -> Variant:
	if node == null:
		return 0
	if typeof(node) != TYPE_DICTIONARY:
		return node
	var expr: Dictionary = node
	match str(expr.get("node", "")):
		"num":
			return expr.get("value", 0)
		"str":
			return str(expr.get("value", ""))
		"var":
			return _read_var(str(expr.get("name", "")), frame)
		"list":
			var items: Array = []
			for item in expr.get("items", []):
				items.append(_eval(item, frame))
			return items
		"proplist":
			var dict := {}
			for pair in expr.get("pairs", []):
				dict[LingoValue.to_str(_eval((pair as Dictionary).get("key", {}), frame))] = \
					_eval((pair as Dictionary).get("value", {}), frame)
			return dict
		"unary":
			var value: Variant = _eval(expr.get("value", {}), frame)
			if str(expr.get("op", "")) == "not":
				return 0 if LingoValue.truthy(value) else 1
			return LingoValue.sub(0, value)
		"binary":
			return _binary(str(expr.get("op", "")), expr, frame)
		"chunk":
			var kind := str(expr.get("kind", "line"))
			var start := LingoValue.to_int(_eval(expr.get("start", {}), frame))
			var stop_node: Variant = expr.get("stop", null)
			var stop := LingoValue.to_int(_eval(stop_node, frame)) if stop_node != null else start
			var text := LingoValue.to_str(_eval(expr.get("source", {}), frame))
			return LingoValue.get_chunk(text, kind, start, stop, item_delimiter)
		"count":
			var unit := str(expr.get("unit", "line"))
			var source := LingoValue.to_str(_eval(expr.get("source", {}), frame))
			return LingoValue.count_of(source, unit, item_delimiter)
		"field":
			return _host_call("get_field", [
				LingoValue.to_str(_eval(expr.get("name", {}), frame)),
				_cast_of(expr, frame),
			])
		"field_prop":
			return _host_call("get_field", [
				LingoValue.to_str(_eval(expr.get("name", {}), frame)),
				_cast_of(expr, frame),
			])
		"sprite_ref":
			return LingoValue.to_int(_eval(expr.get("which", {}), frame))
		"member_ref":
			return _host_call("member_number", [
				_eval(expr.get("which", {}), frame), _cast_of(expr, frame),
			])
		"member_number":
			return _host_call("member_number", [
				_eval(expr.get("which", {}), frame), _cast_of(expr, frame),
			])
		"sprite_number":
			return LingoValue.to_int(_eval(expr.get("which", {}), frame))
		"sprite_prop":
			return _host_call("get_sprite_prop", [
				LingoValue.to_int(_eval(expr.get("which", {}), frame)),
				str(expr.get("prop", "")),
			])
		"member_prop":
			return _host_call("get_member_prop", [
				_eval(expr.get("which", {}), frame),
				_cast_of(expr, frame),
				str(expr.get("prop", "")),
			])
		"prop":
			var prop := str(expr.get("prop", "")).to_lower()
			if prop == "itemdelimiter":
				return item_delimiter
			return _host_call("get_system_prop", [prop])
		"prop_of":
			var owner: Dictionary = expr.get("target", {})
			if str(owner.get("node", "")) == "sprite_ref":
				return _host_call("get_sprite_prop", [
					LingoValue.to_int(_eval(owner.get("which", {}), frame)),
					str(expr.get("prop", "")),
				])
			if str(owner.get("node", "")) == "member_ref":
				return _host_call("get_member_prop", [
					_eval(owner.get("which", {}), frame),
					_cast_of(owner, frame), str(expr.get("prop", "")),
				])
			return _host_call("get_member_prop", [
				_eval(owner, frame), "", str(expr.get("prop", "")),
			])
		"dot":
			var owner_node: Dictionary = expr.get("target", {})
			var prop_name := str(expr.get("prop", ""))
			if str(owner_node.get("node", "")) == "sprite_ref":
				return _host_call("get_sprite_prop", [
					LingoValue.to_int(_eval(owner_node.get("which", {}), frame)), prop_name,
				])
			if str(owner_node.get("node", "")) == "member_ref":
				return _host_call("get_member_prop", [
					_eval(owner_node.get("which", {}), frame),
					_cast_of(owner_node, frame), prop_name,
				])
			return _host_call("get_member_prop", [_eval(owner_node, frame), "", prop_name])
		"index":
			var target: Variant = _eval(expr.get("target", {}), frame)
			var index := LingoValue.to_int(_eval(expr.get("index", {}), frame))
			if typeof(target) == TYPE_ARRAY:
				var list: Array = target
				if index >= 1 and index <= list.size():
					return list[index - 1]
				return 0
			return LingoValue.get_chunk(LingoValue.to_str(target), "char", index, index)
		"call":
			return _call(expr, frame)
		_:
			_fail("unknown expression %s" % str(expr.get("node", "?")))
			return 0


func _binary(op: String, expr: Dictionary, frame: Dictionary) -> Variant:
	var left: Variant = _eval(expr.get("left", {}), frame)
	# `and` / `or` short-circuit in Director.
	if op == "and":
		if not LingoValue.truthy(left):
			return 0
		return 1 if LingoValue.truthy(_eval(expr.get("right", {}), frame)) else 0
	if op == "or":
		if LingoValue.truthy(left):
			return 1
		return 1 if LingoValue.truthy(_eval(expr.get("right", {}), frame)) else 0
	var right: Variant = _eval(expr.get("right", {}), frame)
	match op:
		"+": return LingoValue.add(left, right)
		"-": return LingoValue.sub(left, right)
		"*": return LingoValue.mul(left, right)
		"/": return LingoValue.div(left, right)
		"mod": return LingoValue.modulo(left, right)
		"&": return LingoValue.concat(left, right)
		"&&": return LingoValue.concat_space(left, right)
		"=": return 1 if LingoValue.equal(left, right) else 0
		"<>": return 0 if LingoValue.equal(left, right) else 1
		"<": return 1 if LingoValue.compare(left, right) < 0 else 0
		">": return 1 if LingoValue.compare(left, right) > 0 else 0
		"<=": return 1 if LingoValue.compare(left, right) <= 0 else 0
		">=": return 1 if LingoValue.compare(left, right) >= 0 else 0
		"contains": return 1 if LingoValue.contains(left, right) else 0
		"starts": return 1 if LingoValue.starts(left, right) else 0
		"intersects", "within":
			return _host_call("call_builtin", [op, [left, right]])
		_:
			_fail("unknown operator %s" % op)
			return 0


func _read_var(name: String, frame: Dictionary) -> Variant:
	var key := name.to_lower()
	# Director's spelled-out constants.
	match key:
		"empty": return ""
		"true": return 1
		"false": return 0
		"return", "cr": return "\n"
		"quote": return "\""
		"tab": return "\t"
		"space": return " "
		"void": return null
	var locals: Dictionary = frame.get("locals", {})
	if locals.has(key):
		return locals[key]
	if globals.has(key):
		return globals[key]
	# An unknown bare identifier is a parameterless handler call in Lingo.
	if has_handler(key) or _script_has_handler(frame.get("script", {}), key):
		return call_handler(key, [], frame.get("script", {}))
	var handled: Variant = _host_call("call_builtin", [key, []])
	if handled != null:
		return handled
	return 0


func _script_has_handler(script: Variant, key: String) -> bool:
	if typeof(script) != TYPE_DICTIONARY:
		return false
	for handler in (script as Dictionary).get("handlers", []):
		if str((handler as Dictionary).get("name", "")).to_lower() == key:
			return true
	return false


func _call(expr: Dictionary, frame: Dictionary) -> Variant:
	var callee: Dictionary = expr.get("callee", {})
	var name := ""
	if str(callee.get("node", "")) == "var":
		name = str(callee.get("name", "")).to_lower()
	elif str(callee.get("node", "")) == "dot":
		# `member(x).name` style calls are handled as property reads.
		return _eval(callee, frame)
	var args: Array = []
	for arg in expr.get("args", []):
		args.append(_eval(arg, frame))

	# Pure-value builtins the interpreter owns, because they have no engine side.
	match name:
		"value":
			return LingoValue.to_num(args[0] if args.size() > 0 else 0)
		"string":
			return LingoValue.to_str(args[0] if args.size() > 0 else "")
		"integer":
			return LingoValue.to_int(args[0] if args.size() > 0 else 0)
		"float":
			return float(LingoValue.to_num(args[0] if args.size() > 0 else 0))
		"abs":
			return absf(float(LingoValue.to_num(args[0] if args.size() > 0 else 0)))
		"length":
			return LingoValue.to_str(args[0] if args.size() > 0 else "").length()
		"chars":
			if args.size() >= 3:
				return LingoValue.get_chunk(LingoValue.to_str(args[0]), "char",
					LingoValue.to_int(args[1]), LingoValue.to_int(args[2]))
			return ""
		"offset":
			if args.size() >= 2:
				var hay := LingoValue.to_str(args[1]).to_lower()
				var needle := LingoValue.to_str(args[0]).to_lower()
				return hay.find(needle) + 1
			return 0
		"count":
			if args.size() >= 1 and typeof(args[0]) == TYPE_ARRAY:
				return (args[0] as Array).size()
			return 0
		"getat":
			if args.size() >= 2 and typeof(args[0]) == TYPE_ARRAY:
				var list: Array = args[0]
				var i := LingoValue.to_int(args[1])
				return list[i - 1] if i >= 1 and i <= list.size() else 0
			return 0

	# A user handler wins over a host builtin, matching Director.
	var script: Dictionary = frame.get("script", {})
	if _script_has_handler(script, name) or has_handler(name):
		return call_handler(name, args, script)
	var result: Variant = _host_call("call_builtin", [name, args])
	return result if result != null else 0


func _host_call(method: String, args: Array) -> Variant:
	if host == null or not host.has_method(method):
		return null
	return host.callv(method, args)


func _fail(message: String) -> void:
	if errors.size() < 50:
		errors.append(message)
