extends SceneTree
## Where `play` and `go` sit in the handlers that call them, across every
## container of a title.
##
##   godot --headless --path . --script tools/suspend_survey.gd -- --root rating
##   godot --headless --path . --script tools/suspend_survey.gd -- --root rating --list
##
## Director suspends the handler that calls `play` or `go` (§6.1 step 18, §9.4).
## The port ran the rest of the handler immediately, so a dialogue line's
## trailing `go` overwrote the branch the `play` had just set. Making the
## interpreter suspend is a change to `_exec_block`, and the size of that change
## is decided by *where in a handler* the call sits:
##
##   - **last statement of its handler** — suspending changes nothing, because
##     there is nothing after it to defer. This is the regression surface: it
##     must stay byte-for-byte identical.
##   - **last statement of a block, more statements after the block** — needs the
##     suspend to unwind through `if` / `case` and resume the outer block.
##   - **inside a repeat body** — needs the loop's own position carried too.
##   - **inside a `tell`** — the body runs in another interpreter, so a suspend
##     has to cross that boundary or be refused.
##
## Reports, never asserts: the numbers are inputs to a design decision, not an
## invariant. `tools/play_suspends.gd` is the harness that asserts.
##
## Title-agnostic: `--root` picks the game and nothing here knows a room name.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")

## The two verbs that freeze. `play done` is the *thaw*, so it is counted apart:
## it resumes a handler rather than suspending one.
const FREEZING := {"play": true, "go": true}

var _sites: Array[Dictionary] = []
var _handlers_with_sites: Dictionary = {}
## Handler name (lowercased) -> times some other handler calls it. A `play` in a
## handler that is called from another handler needs the suspend to unwind
## through `_invoke` as well as through `_exec_block`.
var _call_counts: Dictionary = {}
var _handler_names: Dictionary = {}
## `<cast key>|<script>` already scanned. A linked cast is compiled once per
## movie that references it, so MASTER.CST's handlers would otherwise be counted
## sixty times and every ratio in this report would be a count of *references*
## rather than of authored sites.
var _seen_scripts: Dictionary = {}


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var files: Array[String] = []
	_walk(paths.root, files)
	files.sort()
	var compiler := Compiler.new()
	var compiled := 0
	for path in files:
		var container := ContainerFile.new()
		if not container.open(path):
			continue
		var table := CastTable.new()
		if not table.open(container, paths):
			continue
		var movie := path.get_file().get_basename().to_upper()
		for lib in table.cast_libs:
			var cast = table.cast_for(int(lib))
			if cast == null:
				continue
			var entry: Dictionary = table.cast_libs[lib]
			var cast_name := str(entry.get("name", "")).to_lower()
			if cast_name == "" or int(lib) == 1:
				cast_name = "internal"
			var bundle: Dictionary = compiler.compile_cast(cast, movie, cast_name)
			var scripts: Dictionary = bundle.get("scripts", {})
			if scripts.is_empty():
				continue
			compiled += 1
			# A cast named by the container is shared; an unnamed internal one
			# belongs to this movie alone and two movies may both carry a
			# "BehaviorScript 39".
			var cast_key := "%s/internal" % movie if cast_name == "internal" else cast_name
			for script_name in scripts.keys():
				var seen_key := "%s|%s" % [cast_key, script_name]
				if _seen_scripts.has(seen_key):
					continue
				_seen_scripts[seen_key] = true
				var ast: Dictionary = scripts[script_name]
				for handler in ast.get("handlers", []):
					_scan_handler("%s/%s" % [cast_key, script_name], handler)

	_report(compiled, Args.flag(args, "list"))
	quit(0)


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


func _scan_handler(where: String, handler: Dictionary) -> void:
	var name := str(handler.get("name", "")).to_lower()
	_handler_names[name] = true
	_scan_block(handler.get("body", []), where, name, [], true)


## One statement list. `context` is the chain of enclosing block kinds, and
## `at_tail` says whether the *enclosing* construct has anything after it — so a
## statement that is last in its own block and whose block is last everywhere up
## the chain is last in the handler, which is the population that must not move.
func _scan_block(stmts: Variant, where: String, handler: String,
		context: Array, at_tail: bool) -> void:
	if typeof(stmts) != TYPE_ARRAY:
		return
	var list: Array = stmts
	for i in list.size():
		if typeof(list[i]) != TYPE_DICTIONARY:
			continue
		var stmt: Dictionary = list[i]
		var last_here := i == list.size() - 1
		var tail := at_tail and last_here
		var follows := "" if last_here else _describe(list[i + 1])
		_scan_stmt(stmt, where, handler, context, tail, last_here, follows)
		# Which handlers this one calls, so a `play` inside a callee can be told
		# from one at the top of an event handler.
		_collect_calls(stmt, handler)


## The next statement, named the way the report needs it: a trailing `go` and a
## trailing `sound` are the two shapes that make the divergence visible, and
## everything else is one bucket.
func _describe(stmt: Variant) -> String:
	if typeof(stmt) != TYPE_DICTIONARY:
		return "other"
	var d: Dictionary = stmt
	if str(d.get("node", "")) != "call_stmt":
		return str(d.get("node", "other"))
	var callee: Dictionary = (d.get("call", {}) as Dictionary).get("callee", {})
	if str(callee.get("node", "")) != "var":
		return "call"
	return str(callee.get("name", "call")).to_lower()


func _collect_calls(node: Variant, handler: String) -> void:
	if typeof(node) == TYPE_ARRAY:
		for child in node:
			_collect_calls(child, handler)
		return
	if typeof(node) != TYPE_DICTIONARY:
		return
	var d: Dictionary = node
	if str(d.get("node", "")) == "call":
		var callee: Dictionary = d.get("callee", {})
		if str(callee.get("node", "")) == "var":
			var target := str(callee.get("name", "")).to_lower()
			if target != handler:
				_call_counts[target] = int(_call_counts.get(target, 0)) + 1
	for key in d.keys():
		if key == "node":
			continue
		_collect_calls(d[key], handler)


func _scan_stmt(stmt: Dictionary, where: String, handler: String,
		context: Array, tail: bool, last_in_block: bool = true,
		follows: String = "") -> void:
	var kind := str(stmt.get("node", ""))
	match kind:
		"call_stmt":
			var call: Dictionary = stmt.get("call", {})
			var callee: Dictionary = call.get("callee", {})
			if str(callee.get("node", "")) != "var":
				return
			var name := str(callee.get("name", "")).to_lower()
			if not FREEZING.has(name):
				return
			var verb := ""
			var args: Array = call.get("args", [])
			if not args.is_empty() and typeof(args[0]) == TYPE_DICTIONARY \
					and str((args[0] as Dictionary).get("node", "")) == "str":
				verb = str((args[0] as Dictionary).get("value", "")).to_lower()
			if name == "play":
				name = "play %s" % (verb if verb != "" else "frame")
			_sites.append({
				"where": where,
				"handler": handler,
				"verb": name,
				"line": int(stmt.get("line", 0)),
				"tail": tail,
				"last_in_block": last_in_block,
				"follows": follows,
				"context": context.duplicate(),
			})
			_handlers_with_sites[handler] = true
		"if":
			_scan_block(stmt.get("then", []), where, handler,
				context + ["if"], tail)
			_scan_block(stmt.get("else", []), where, handler,
				context + ["if"], tail)
		"case":
			for branch in stmt.get("branches", []):
				_scan_block((branch as Dictionary).get("body", []), where, handler,
					context + ["case"], tail)
			_scan_block(stmt.get("default", []), where, handler,
				context + ["case"], tail)
		"repeat_while", "repeat_with", "repeat_in", "repeat_forever":
			# Never a tail: the loop runs its body again, so anything inside it has
			# the rest of the loop after it however it is placed.
			_scan_block(stmt.get("body", []), where, handler,
				context + ["repeat"], false)
		"tell":
			_scan_block(stmt.get("body", []), where, handler,
				context + ["tell"], tail)


func _report(compiled: int, listing: bool) -> void:
	var by_verb: Dictionary = {}
	var tails: Dictionary = {}
	var block_tails: Dictionary = {}
	var in_repeat: Dictionary = {}
	var in_tell: Dictionary = {}
	var follows: Dictionary = {}
	var callee_sites := 0
	for site in _sites:
		var verb := str(site["verb"])
		by_verb[verb] = int(by_verb.get(verb, 0)) + 1
		if bool(site["tail"]):
			tails[verb] = int(tails.get(verb, 0)) + 1
		if bool(site.get("last_in_block", true)):
			block_tails[verb] = int(block_tails.get(verb, 0)) + 1
		var context: Array = site["context"]
		if context.has("repeat"):
			in_repeat[verb] = int(in_repeat.get(verb, 0)) + 1
		if context.has("tell"):
			in_tell[verb] = int(in_tell.get(verb, 0)) + 1
		var next_kind := str(site.get("follows", ""))
		if next_kind != "":
			var key := "%s -> %s" % [verb, next_kind]
			follows[key] = int(follows.get(key, 0)) + 1
		if int(_call_counts.get(str(site["handler"]), 0)) > 0:
			callee_sites += 1

	print("")
	print("%d cast(s) compiled, %d authored site(s)" % [compiled, _sites.size()])
	print("")
	print("  block-tail : last statement of its own block -- the suspend has")
	print("               nothing to defer *here*, but an enclosing block may.")
	print("  handler-tail: last statement reached in the handler, everywhere up")
	print("               the chain. Suspending changes nothing at all.")
	print("")
	print("%-12s %7s %12s %11s %8s %6s" % [
		"verb", "sites", "handler-tail", "block-tail", "repeat", "tell"])
	var verbs: Array = by_verb.keys()
	verbs.sort()
	for verb in verbs:
		print("%-12s %7d %12d %11d %8d %6d" % [
			verb, int(by_verb[verb]), int(tails.get(verb, 0)),
			int(block_tails.get(verb, 0)), int(in_repeat.get(verb, 0)),
			int(in_tell.get(verb, 0))])
	print("")
	print("what runs after a site that has more (the statements Director defers):")
	var keys: Array = follows.keys()
	keys.sort_custom(func(a, b): return int(follows[a]) > int(follows[b]))
	for key in keys:
		if int(follows[key]) < 3:
			continue
		print("  %-28s %5d" % [key, int(follows[key])])
	print("")
	print("sites in a handler some other handler calls: %d" % callee_sites)
	print("handlers containing at least one site      : %d" % _handlers_with_sites.size())

	if not listing:
		return
	print("")
	for site in _sites:
		print("  %s  %s:%d  %s  %s%s" % [
			str(site["verb"]), str(site["where"]), int(site["line"]),
			str(site["handler"]),
			"TAIL" if bool(site["tail"]) else "has-more",
			"" if (site["context"] as Array).is_empty()
				else "  in %s" % str(site["context"]),
		])
