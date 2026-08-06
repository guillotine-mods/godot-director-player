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
## Names the runtime could not bind, with where each was reached from. Host
## bindings report through here too, via `report()`.
var diagnostics := LingoDiagnostics.new()
## Director 3's primary event handlers, installed by `when <event> then <stmt>`
## and keyed by event name. Tier 1 of the message hierarchy: a primary handler
## fires before the sprite an event landed on, and only for the event it names.
## The body is a statement list, stored rather than executed at the point the
## `when` appears — see the "when" branch in `_exec`.
var primary_handlers: Dictionary = {}

## Handlers reachable from anywhere: movie scripts.
var _movie_handlers: Dictionary = {}
## cast -> script name -> ast, for behaviour and cast scripts.
var _scripts: Dictionary = {}
var _steps: int = 0
var _return_value: Variant = null
var _depth: int = 0
## Where execution is, for locating a diagnostic. Statement granularity: the
## line of the statement being run, not of the expression inside it.
var _script_name: String = ""
var _handler_name: String = ""
var _line: int = 0
var _current_handler: Dictionary = {}
## script|handler -> {name: true}, built the first time a handler reports.
var _assigned_names: Dictionary = {}


func _init(host_object: Object = null) -> void:
	host = host_object


# ---------------------------------------------------------------- loading


func load_bundle(bundle: Dictionary, qualifier: String = "") -> void:
	## One compiled cast: {"movie":…, "cast":…, "scripts": {name: ast}}
	##
	## The bundle's own `cast` is the subdirectory ProjectorRays wrote it to, and
	## eleven casts use "External" — MASTER, ISLAND2, WONDER, BOOK and the rest.
	## Keyed on that alone they share one namespace and the last one loaded wins,
	## so DAY1 asking island2 for member 59 got MASTER's `invleft` instead of
	## `to forest1`, and the click played an inventory sound rather than walking.
	var cast := str(bundle.get("cast", ""))
	if qualifier != "":
		cast = "%s/%s" % [qualifier, cast]
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


## Fire the primary handler installed by `when <event> then`, if there is one.
##
## Returns true when one ran. Tier 1: the caller should run this *before* the
## ordinary hierarchy, because that is where Director puts it — ahead of the
## sprite the event landed on.
##
## The body runs in a fresh frame rather than as a closure over wherever the
## `when` was written. A real primary handler is compiled in its own scope, and
## treating it as a closure would let it see locals of a handler that has long
## since returned.
func run_primary(event: String) -> bool:
	var key := event.to_lower()
	if not primary_handlers.has(key):
		return false
	var body: Array = primary_handlers[key]
	if body.is_empty():
		return false
	_exec_block(body, {})
	return true


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
	# Saved on the stack rather than pushed onto one: a nested call must not
	# leave the caller reporting from the callee's line.
	var outer_script := _script_name
	var outer_handler := _handler_name
	var outer_body := _current_handler
	var outer_line := _line
	_script_name = str(script.get("script", ""))
	_handler_name = str(handler.get("name", ""))
	_current_handler = handler
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
	_script_name = outer_script
	_handler_name = outer_handler
	_current_handler = outer_body
	_line = outer_line
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
	# Diagnostics deliberately survive: they accumulate over a session so the
	# emitted set covers the whole run rather than the last dispatch.


func report(category: String, name: String) -> void:
	## Host bindings report through here, so the location comes from one place.
	diagnostics.report(category, name, _script_name, _handler_name, _line)


func location() -> Array:
	## Where execution is, for a trace record. The same three values `report`
	## hands the sink, so a trace entry and a diagnostic about one access agree.
	return [_script_name, _handler_name, _line]


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
	_line = int(stmt.get("line", _line))
	match str(stmt.get("node", "")):
		"global", "property":
			for name in stmt.get("names", []):
				var key := str(name).to_lower()
				frame["globals"][key] = true
				if not globals.has(key):
					# An unset global is VOID, not 0. It matters: `effectspath &
					# "x.aif"` must be "x.aif", and 0 would make it "0x.aif".
					globals[key] = null
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
		"when":
			## `when keyDown then go to "mainmenub4"` — Director 3's primary event
			## handler (§6.3, §11.2). **Installed here, not run here.**
			##
			## The distinction is the whole point. Executing the body where the
			## `when` sits turns a conditional statement into an unconditional
			## one, which is what the original misparse did: `then go to
			## "mainmenub4"` became a statement of its own and `strtgame`'s
			## `gomenu` navigated away the moment it was called rather than when a
			## key was pressed. So this stores the body against its event and
			## answers NORMAL, and something else fires it when that event
			## actually happens — `primary(event)` below.
			##
			## This used to be a recorded gap, on the grounds that the port had no
			## tier 1 to install into. It has one now for keys, so the honest
			## answer is no longer a report.
			primary_handlers[str(stmt.get("event", "")).to_lower()] = stmt.get("body", [])
			return Flow.NORMAL
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
		"sound_prop":
			_host_call("set_sound_prop", [
				LingoValue.to_int(_eval(target.get("which", {}), frame)),
				str(target.get("prop", "")), value,
			])
		"window_prop":
			## `set the windowType of window "joke.dxr" to 2`. Routed to the
			## system-property setter rather than to a `set_window_prop` of its own,
			## because that is already where the host meets these names: the other
			## spelling in this corpus is `tell window("map.dxr") / set the
			## windowType to 2`, whose body runs on the one stage and so arrives as
			## a plain movie property, and `lingo_host.gd`'s WINDOW_FIELDS table
			## accepts and drops it there. Two entry points to one table would be
			## two chances for them to disagree, which is the fault this node
			## exists to close — before it, the `the … of window` spelling was
			## dropped with an error and the dot spelling was not.
			##
			## The window the statement named is evaluated for its effects and then
			## discarded: a single-stage port has nothing to place, title or resize
			## (§7.4). The address stays in the AST for a port that grows real
			## windows, which is the whole reason this is a designator node rather
			## than `prop_of` over a call.
			_eval(target.get("which", {}), frame)
			_host_call("set_system_prop", [str(target.get("prop", "")).to_lower(), value])
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
			## `window("joke.dxr").windowType = 2` and friends. The owner is a call
			## returning a window handle, and every window property is about where
			## a floating window sits, which means nothing on a single stage.
			if typeof(_eval(owner_node, frame)) == TYPE_STRING:
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
	if host != null and host.has_method("owns_global") and host.owns_global(name):
		host.set_global(name, value)
		return
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
		"sound_prop":
			## `the volume of sound 2`. A sound channel is a designator like a
			## sprite, not a call; parsing it as one made every such assignment
			## unreachable, and 52 scripts here set a channel's volume with none
			## of them taking effect.
			return _host_call("get_sound_prop", [
				LingoValue.to_int(_eval(expr.get("which", {}), frame)),
				str(expr.get("prop", "")),
			])
		"window_prop":
			## Read side of the designator above, through the same table. Nothing
			## in this corpus reads a window property — all 2 sites are writes —
			## but a read that fell through to `_fail("unknown expression")` would
			## be a different answer from the write, which is what this node is
			## here to stop.
			_eval(expr.get("which", {}), frame)
			return _host_call("get_system_prop", [str(expr.get("prop", "")).to_lower()])
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
	## Left, then right, then operate — for every operator including `and` and
	## `or`. **They do not short-circuit** (`docs/LINGO_SURFACE.md` §13 and §14;
	## §17 records this as a correction to §2.3, which said they did). Director
	## compiles them to a single opcode that pops two operands, so the code
	## generator emits no jump and the right side runs whatever the left answered.
	##
	## This port short-circuited until now, and the reason that is worse than a
	## harmless optimisation is Lingo-specific: a bare identifier that is not a
	## variable is a parameterless *handler call* (`_read_var`), so an operand
	## that reads like a variable can be `cursorfunk` or `talkproc`. A
	## short-circuiting interpreter silently stops calling handlers it cannot see
	## it is skipping, and the symptom — a cursor that does not change, a line of
	## speech that never starts — looks like a binding gap rather than a
	## conditional. `tools/lingo_logic_check.gd` asserts both sides run.
	##
	## The result is the integer 0 or 1, not a boolean and not the operand:
	## `5 and 7` is 1, so nothing downstream can read a truth value as data.
	var left: Variant = _eval(expr.get("left", {}), frame)
	var right: Variant = _eval(expr.get("right", {}), frame)
	match op:
		"and": return 1 if LingoValue.truthy(left) and LingoValue.truthy(right) else 0
		"or": return 1 if LingoValue.truthy(left) or LingoValue.truthy(right) else 0
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
	# Globals the host owns: the walk state lives in PuppetController, so
	# `egozh`, `whatodo` and friends must alias it rather than shadow it.
	if host != null and host.has_method("owns_global") and host.owns_global(key):
		return host.get_global(key)
	if globals.has(key):
		var value: Variant = globals[key]
		if value == null:
			# Declared with `global x` and never assigned. VOID is the right
			# answer, but which name and where is still worth knowing, and it is
			# the script's own unset variable rather than a binding the port owes.
			report(LingoDiagnostics.UNSET_VARIABLE, key)
		return value
	# An unknown bare identifier is a parameterless handler call in Lingo.
	if host != null and host.has_method("is_native_handler") and host.is_native_handler(key):
		var native: Variant = _host_call("call_builtin", [key, []])
		return native if native != null else 0
	if has_handler(key) or _script_has_handler(frame.get("script", {}), key):
		return call_handler(key, [], frame.get("script", {}))
	var handled: Variant = _host_call("call_builtin", [key, []])
	if handled != null:
		return handled
	# Unknown identifiers are VOID, which concatenates as "" and counts as 0.
	report(
		LingoDiagnostics.UNSET_VARIABLE if _handler_assigns(key) else LingoDiagnostics.UNBOUND_NAME,
		key)
	return null


func _handler_assigns(key: String) -> bool:
	## Whether the running handler assigns this name anywhere. If it does, the
	## read is an uninitialised local — the branch that would have set it was not
	## taken — and not a name the port failed to bind. Scanning the body is only
	## ever paid for by a handler that already has something to report, and the
	## answer is cached per handler.
	var cache_key := "%s|%s" % [_script_name, _handler_name]
	var names: Variant = _assigned_names.get(cache_key, null)
	if names == null:
		names = {}
		for param in _current_handler.get("params", []):
			(names as Dictionary)[str(param).to_lower()] = true
		_collect_assigned(_current_handler.get("body", []), names)
		_assigned_names[cache_key] = names
	return (names as Dictionary).has(key)


func _collect_assigned(stmts: Variant, out: Dictionary) -> void:
	if typeof(stmts) != TYPE_ARRAY:
		return
	for stmt in stmts:
		if typeof(stmt) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = stmt
		match str(node.get("node", "")):
			"assign", "put":
				var target: Variant = node.get("target", {})
				if typeof(target) == TYPE_DICTIONARY \
						and str((target as Dictionary).get("node", "")) == "var":
					out[str((target as Dictionary).get("name", "")).to_lower()] = true
			"if":
				_collect_assigned(node.get("then", []), out)
				_collect_assigned(node.get("else", []), out)
			"repeat_while", "repeat_forever", "tell":
				_collect_assigned(node.get("body", []), out)
			"repeat_with", "repeat_in":
				out[str(node.get("var", "")).to_lower()] = true
				_collect_assigned(node.get("body", []), out)
			"case":
				for branch in node.get("branches", []):
					_collect_assigned((branch as Dictionary).get("body", []), out)
				_collect_assigned(node.get("default", []), out)


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

	## There is no second builtin table here. This file used to answer `value`,
	## `string`, `integer`, `float`, `abs`, `length`, `chars`, `offset`, `count`
	## and `getAt` from an inline `match` placed *above* the dispatch below, so
	## `lingo/lingo_builtins.gd` — the spec-driven module `tools/lingo_builtins_check.gd`
	## checks — could never be reached for those ten names and the two disagreed
	## in silence. The module is now the only answer. What the inline copies got
	## wrong, name by name, because "we deleted the duplicate" is not a reason:
	##
	##   getAt   answered 0 past either end where the module answers VOID. §8.6 is
	##           explicit that the two are not interchangeable, and 0 is the one
	##           that cannot be told from a stored 0 — `if getAt(l, i) then` reads
	##           the same either way. It also knew only Arrays, so `getAt` on a
	##           property list, a point or a rect answered 0 rather than the
	##           element (§1.3, §1.8).
	##   abs     coerced to float always, so `abs(-7)/2` was 3.5 where Director
	##           answers 3: §2.1's integer-division rule keys off the operand
	##           types, and a builtin that widens its result moves every
	##           expression downstream onto the other arithmetic.
	##   value   coerced with `to_num`, so a string that is not a number answered
	##           0. §1.2 says `value` *parses* — a number, a list or a property
	##           list — and anything else is VOID (§8.6 again). The coercing
	##           version also could not read `value("[1, 2]")` at all.
	##   integer truncated. §1.1 says it rounds; `integer(3.7)` is 4.
	##   offset  ignored the documented third argument (start position) and
	##           answered 1 for an empty needle, so `if offset("", s) then` fired.
	##   count   knew only Arrays, so a property list counted 0 (§1.3).
	##   chars, length, string, float agreed with the module and were duplicated
	##           for nothing — two copies of one rule is how the other six drifted.
	##
	## Deleting them also moves the ten names *below* user-handler resolution,
	## which is where Director puts them: a script may shadow a builtin (§14, and
	## the comment on the dispatch below). No handler in this corpus is named any
	## of the ten, so the corpus behaves the same; the ordering is now a decision
	## rather than an artefact of where the `match` happened to sit.

	# Handlers the host implements natively win even over a user handler: the port
	# reimplements the walk state machine in PuppetController, so running the
	# original `walkonby` would fight it.
	if host != null and host.has_method("is_native_handler") and host.is_native_handler(name):
		var native: Variant = _host_call("call_builtin", [name, args])
		return native if native != null else 0
	# Otherwise a user handler wins over a host builtin, matching Director.
	var script: Dictionary = frame.get("script", {})
	if _script_has_handler(script, name) or has_handler(name):
		return call_handler(name, args, script)
	# The engine-free builtins — math, strings, lists, geometry, predicates.
	# Offered after a user handler, because Director lets a script shadow a
	# builtin, and before the host, because the host is where a title's own
	# bindings live and nothing engine-free belongs there. `handled` is what
	# distinguishes "answered VOID" from "not mine".
	var handled: Array = []
	var pure: Variant = Builtins.call_builtin(name, args, handled)
	if not handled.is_empty():
		return pure
	var result: Variant = _host_call("call_builtin", [name, args])
	if result == null and name != "":
		# The host binds no builtin by this name. Distinguishable from one that
		# answers VOID, because every bound branch returns a value.
		report(LingoDiagnostics.BUILTIN, name)
	return result if result != null else 0


## Preloaded rather than reached by its `class_name`: a headless `--script` run
## resolves global classes out of the editor's script cache, so a class added
## since the last editor session fails with "not declared in the current scope"
## in a file nobody touched.
const Builtins := preload("res://lingo/lingo_builtins.gd")


func _host_call(method: String, args: Array) -> Variant:
	if host == null or not host.has_method(method):
		return null
	return host.callv(method, args)


func _fail(message: String) -> void:
	if errors.size() < 50:
		errors.append(message)
