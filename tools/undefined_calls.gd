extends SceneTree
## Which calls in the corpus resolve nowhere at all -- the set the reference ends
## with `lingoError`, and this port answers 0 to.
##
##   godot --headless --path . --script tools/undefined_calls.gd -- --all
##   godot --headless --path . --script tools/undefined_calls.gd -- --root piposh-dream
##   godot --headless --path . --script tools/undefined_calls.gd -- --all --verbose
##
## `bugs.md` 123's question, and the one that decides whether the abort is safe
## to implement: a call to a handler nothing defines aborts the whole callstack in
## the reference (`LC::call` -> `lingoError` -> `_abort`, tested by
## `Lingo::execute`'s loop condition and cleared only when that loop returns).
## Turning that on here truncates a dispatch, so the number that matters is how
## many calls in the corpus would actually reach it.
##
## Four buckets per root, and only the fourth decides:
##
##   1. **resolved** -- some script in the root declares a handler of that name.
##   2. **reference-known** -- `lingo_reference_names.gd`, i.e. a builtin, a `the`
##      entity or an object method the reference answers. If this port has not
##      bound one of these it is a hole on our side, and the reference does not
##      abort on it, so neither may we.
##   3. **Director-known** -- `lingo_director_names.gd`: documented in Macromedia's
##      own Lingo Dictionary and *not* implemented by the reference. `gotoNetPage`
##      is the case this bucket was added for. Director answers these, so an abort
##      here would be an abort caused by a gap in ScummVM.
##   4. **undefined** -- in none of the three. Nothing anywhere in the root
##      declares it, the reference has no table entry, and Director's dictionary
##      does not document it, so it is the movie's own fault and Director aborts.
##      This is the only bucket the abort can fire in.
##
## Bucket 3 is what `bugs.md` 123 was blocked on. Before it existed, bucket 4 held
## 19 sites over 7 names and two of them were `gotoNetPage`, so "in neither table"
## was a statement about ScummVM's coverage rather than about Director's language
## and could not carry a control-flow decision.
##
## **The handler universe is the whole root, not the container.** Director scopes
## movie scripts to the movie, so this under-counts, and that is the direction
## chosen on purpose: bucket 3 is then a *floor* -- a name no scoping rule of any
## kind could resolve -- and a floor is what a decision to change control flow
## needs. The per-container count is printed beside it as the ceiling, because the
## gap between them is entirely names that resolve in some other movie of the same
## title and would abort under strict scoping. Entry 123's own false start is why:
## `wlkleftintersects` was called undefined because `hatul2.dir`'s internal cast
## was never read, and reading only one container reproduces that mistake 651
## times.
##
## Counts *sites*, not names, because the abort fires per execution and a name
## called from thirty places is thirty truncated handlers.
##
## Bare-word statements are counted separately and are **not** in the four buckets
## above. `foo` with no arguments parses as a `var` node and reaches `_read_var`,
## not `_call`, where an unbound name is VOID with no abort at all. The reference
## compiles the statement form to `c_callcmd` and would abort, so the divergence is
## real there too. `bugs.md` 123 recorded the count -- 218 -- and said nobody had
## looked; **this tool now buckets them the same way it buckets the call sites**,
## because a bare count cannot distinguish "218 places Director would abort" from
## "218 uninitialised loop counters", and the entry's own argument turns on which.
##
## The extra bucket the calls do not need is `local`: a bare word the enclosing
## handler assigns somewhere, declares `global`, or takes as a parameter. That is
## the interpreter's own test -- `_handler_assigns`, and `_read_var`'s locals,
## globals and `me`-slot arms ahead of it -- so a name in this bucket never reaches
## the unbound arm at runtime and no abort could fire on it however the flag is
## wired. It is computed here per handler, out of the same AST shapes
## `_collect_assigned` walks, so the two agree by construction rather than by
## coincidence. `property` declarations on a parent script are *not* counted as
## local, deliberately: `_read_var` reads them off `me`, which only exists when the
## handler is running on an object, and this tool cannot know that.
##
## A survey, not a gate: it prints numbers, and none of them is higher-is-better.
## `tools/undefined_handler.gd` is the pass/fail half.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Paths := preload("res://director/director_paths.gd")
const RefNames := preload("res://lingo/lingo_reference_names.gd")
const DirNames := preload("res://lingo/lingo_director_names.gd")

## Every root under `games/`. Named rather than discovered, for the reason
## `parse_residue.gd` names its own: a directory dropped in beside them must not
## silently join the sweep and move the number.
const ROOTS := ["piposh", "piposh2", "piposh-en", "piposh-ru", "piposh-dream", "rating"]


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return
	var verbose := Args.flag(args, "verbose")
	var roots: Array = ROOTS if Args.flag(args, "all") else [Args.text(args, "root", paths.root)]

	var grand := {"sites": 0, "resolved": 0, "known": 0, "director": 0, "undefined": 0,
		"bare": 0, "bare_local": 0, "bare_resolved": 0, "bare_known": 0,
		"bare_director": 0, "bare_undefined": 0}
	var grand_names: Dictionary = {}
	var grand_bare_names: Dictionary = {}
	for root in roots:
		var dir := "res://games/%s" % str(root)
		var files := PackedStringArray()
		_collect(dir, files)
		if files.is_empty():
			print("%-14s no containers under %s" % [str(root), dir])
			continue
		var compiler := Compiler.new()
		# path -> {"defined": {name: true}, "calls": [ {name, member, line, args} ]}
		var per_file: Dictionary = {}
		var defined_root: Dictionary = {}
		var scripts := 0
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var cast := Cast.new()
			if not cast.open(f):
				continue
			var entry := {"defined": {}, "calls": [], "bare": []}
			for number in cast.member_numbers():
				var member: Dictionary = cast.member(number)
				var source := str(member.get("source", ""))
				if source.strip_edges() == "":
					continue
				scripts += 1
				var ast := compiler.compile_source(
					source, Compiler.script_key(member, number))
				# A script that did not compile is `script_compile_check.gd`'s
				# subject. Its calls are not this tool's evidence either way.
				if ast.is_empty():
					continue
				for handler in ast.get("handlers", []):
					var hname := str((handler as Dictionary).get("name", "")).to_lower()
					if hname != "":
						(entry["defined"] as Dictionary)[hname] = true
						defined_root[hname] = true
				_walk(ast, entry, number, source)
				_bare_pass(ast, entry, number, source)
			per_file[path] = entry

		var counts := {"sites": 0, "resolved": 0, "known": 0, "director": 0, "undefined": 0,
			"bare": 0, "bare_local": 0, "bare_resolved": 0, "bare_known": 0,
			"bare_director": 0, "bare_undefined": 0}
		var undefined_names: Dictionary = {}
		var bare_undefined_names: Dictionary = {}
		var strict := 0
		for path in per_file:
			var entry: Dictionary = per_file[path]
			for bare in entry["bare"]:
				var bname := str((bare as Dictionary)["name"])
				counts["bare"] = int(counts["bare"]) + 1
				# Ordered exactly as `_read_var` orders its arms, so a bucket here
				# names the arm that would answer at runtime: locals/globals/`me`
				# first, then a handler, then the builtin tables. A bare word that
				# reaches none of them is the one `c_callcmd` would abort on.
				if bool((bare as Dictionary)["local"]):
					counts["bare_local"] = int(counts["bare_local"]) + 1
				elif defined_root.has(bname):
					counts["bare_resolved"] = int(counts["bare_resolved"]) + 1
				elif RefNames.knows(bname):
					counts["bare_known"] = int(counts["bare_known"]) + 1
				elif DirNames.knows(bname):
					counts["bare_director"] = int(counts["bare_director"]) + 1
				else:
					counts["bare_undefined"] = int(counts["bare_undefined"]) + 1
					bare_undefined_names[bname] = int(
						bare_undefined_names.get(bname, 0)) + 1
					if verbose:
						print("      bare %-16s member %-4d line %-4d %-24s %s" % [
							str(path).get_file(), int((bare as Dictionary)["member"]),
							int((bare as Dictionary)["line"]), bname,
							str((bare as Dictionary)["text"])])
			for call in entry["calls"]:
				var name := str((call as Dictionary)["name"])
				counts["sites"] = int(counts["sites"]) + 1
				# The ceiling: what would abort if a movie script's scope were the
				# container it is in, which is Director's actual rule.
				if not (entry["defined"] as Dictionary).has(name) \
						and not RefNames.knows(name):
					strict += 1
				# The floor: nothing in the whole root declares it and the
				# reference has no table entry for it.
				if defined_root.has(name):
					counts["resolved"] = int(counts["resolved"]) + 1
				elif RefNames.knows(name):
					counts["known"] = int(counts["known"]) + 1
				elif DirNames.knows(name):
					counts["director"] = int(counts["director"]) + 1
				else:
					counts["undefined"] = int(counts["undefined"]) + 1
					undefined_names[name] = int(undefined_names.get(name, 0)) + 1
					if verbose:
						print("      %-16s member %-4d line %-4d %-24s %s" % [
							str(path).get_file(), int((call as Dictionary)["member"]),
							int((call as Dictionary)["line"]), name,
							str((call as Dictionary)["text"])])

		print("%-14s %5d container(s) %6d script(s) %6d call site(s)" % [
			str(root), per_file.size(), scripts, int(counts["sites"])])
		print("               resolved %6d   reference-known %5d   Director-known %3d   UNDEFINED %4d"
			% [int(counts["resolved"]), int(counts["known"]),
				int(counts["director"]), int(counts["undefined"])])
		print("               undefined under strict per-container scoping: %d" % strict)
		print("               bare-word statements (a `_read_var` path, not `_call`): %d"
			% int(counts["bare"]))
		print("                 local %5d  resolved %5d  reference-known %4d  Director-known %3d  UNDEFINED %4d"
			% [int(counts["bare_local"]), int(counts["bare_resolved"]),
				int(counts["bare_known"]), int(counts["bare_director"]),
				int(counts["bare_undefined"])])
		if not bare_undefined_names.is_empty():
			var bnames: Array = bare_undefined_names.keys()
			bnames.sort()
			for bname in bnames:
				print("               ~ %-28s %d bare statement(s)" % [
					str(bname), int(bare_undefined_names[bname])])
				grand_bare_names[str(bname)] = int(grand_bare_names.get(str(bname), 0)) 					+ int(bare_undefined_names[bname])
		if not undefined_names.is_empty():
			var names: Array = undefined_names.keys()
			names.sort()
			for name in names:
				print("               ! %-28s %d site(s)" % [
					str(name), int(undefined_names[name])])
				grand_names[str(name)] = int(grand_names.get(str(name), 0)) \
					+ int(undefined_names[name])
		for k in counts:
			grand[k] = int(grand[k]) + int(counts[k])

	print("")
	print("ALL ROOTS      %6d call site(s): resolved %d, reference-known %d, Director-known %d, UNDEFINED %d"
		% [int(grand["sites"]), int(grand["resolved"]), int(grand["known"]),
			int(grand["director"]), int(grand["undefined"])])
	print("               bare-word statements: %d -- local %d, resolved %d, reference-known %d, Director-known %d, UNDEFINED %d"
		% [int(grand["bare"]), int(grand["bare_local"]), int(grand["bare_resolved"]),
			int(grand["bare_known"]), int(grand["bare_director"]),
			int(grand["bare_undefined"])])
	if not grand_bare_names.is_empty():
		var bare_names: Array = grand_bare_names.keys()
		bare_names.sort()
		print("               %d distinct undefined bare name(s): %s"
			% [bare_names.size(), ", ".join(PackedStringArray(bare_names))])
	if grand_names.is_empty():
		print("               no call in the sweep resolves nowhere")
	else:
		var names: Array = grand_names.keys()
		names.sort()
		print("               %d distinct undefined name(s): %s"
			% [names.size(), ", ".join(PackedStringArray(names))])
	quit(0)


## Collect every `call` whose callee is a plain name -- the shape that reaches
## `_call`'s fall-through. Bare-word statements are `_bare_pass`'s, because they
## need the enclosing handler and this walk does not have one.
func _walk(node: Variant, entry: Dictionary, member: int, source: String) -> void:
	if node is Array:
		for item in node:
			_walk(item, entry, member, source)
		return
	if not (node is Dictionary):
		return
	var d: Dictionary = node
	match str(d.get("node", "")):
		"call":
			var callee: Variant = d.get("callee", null)
			if callee is Dictionary and str((callee as Dictionary).get("node", "")) == "var":
				(entry["calls"] as Array).append({
					"name": str((callee as Dictionary).get("name", "")).to_lower(),
					"member": member,
					"line": int(d.get("line", 0)),
					"text": _source_line(source, int(d.get("line", 0))),
				})
	for key in d:
		_walk(d[key], entry, member, source)


## Every bare-word statement in every handler of one script, tagged with whether
## the enclosing handler already owns the name.
##
## Driven per handler rather than over the whole AST, because "does this handler
## assign it" is the question `_read_var` answers first and it cannot be asked of
## a script. A `global` written at script level counts for every handler in the
## script -- that is `_invoke`'s own rule, applied per invocation there and once
## here -- and a handler's own `global` and `property` lines are collected with
## its assignments.
func _bare_pass(ast: Dictionary, entry: Dictionary, member: int, source: String) -> void:
	var script_globals: Dictionary = {}
	for name in ast.get("globals", []):
		script_globals[str(name).to_lower()] = true
	for value in ast.get("handlers", []):
		var handler: Dictionary = value
		var owned: Dictionary = script_globals.duplicate()
		for param in handler.get("params", []):
			owned[str(param).to_lower()] = true
		# `me` is bound on the frame for every message to an object and is never a
		# call, whether or not it was declared a parameter.
		owned["me"] = true
		_owned_names(handler.get("body", []), owned)
		_bare_walk(handler.get("body", []), entry, member, source, owned)
	# **The loose statements a frame or cast script carries outside any handler**
	# (`lingo_parser.gd`'s `body`). One of these is why this tool's bare count is
	# 217 handler statements and 218 in total, and dropping it would have moved a
	# number `bugs.md` 123 quotes without saying why.
	var loose: Dictionary = script_globals.duplicate()
	_owned_names(ast.get("body", []), loose)
	_bare_walk(ast.get("body", []), entry, member, source, loose)


## The names a handler body binds: assignment targets, `repeat with` counters and
## `global` / `property` declarations. The same shapes
## `lingo_interpreter.gd:_collect_assigned` walks, plus the two declaration nodes
## it does not need to.
func _owned_names(stmts: Variant, out: Dictionary) -> void:
	if not (stmts is Array):
		return
	for value in stmts:
		if not (value is Dictionary):
			continue
		var node: Dictionary = value
		match str(node.get("node", "")):
			"assign", "put":
				var base := _assigned_base(node.get("target", {}))
				if base != "":
					out[base] = true
			"global", "property":
				for name in node.get("names", []):
					out[str(name).to_lower()] = true
			"if":
				_owned_names(node.get("then", []), out)
				_owned_names(node.get("else", []), out)
			"repeat_while", "repeat_forever", "tell":
				_owned_names(node.get("body", []), out)
			"repeat_with", "repeat_in":
				out[str(node.get("var", "")).to_lower()] = true
				_owned_names(node.get("body", []), out)
			"case":
				for branch in node.get("branches", []):
					_owned_names((branch as Dictionary).get("body", []), out)
				_owned_names(node.get("default", []), out)


## Copied in shape from `lingo_interpreter.gd:_assigned_base`, and it has to stay
## in step with it: a target shape this misses is a name reported as undefined
## that the interpreter treats as the handler's own.
func _assigned_base(target: Variant) -> String:
	if not (target is Dictionary):
		return ""
	var node: Dictionary = target
	match str(node.get("node", "")):
		"var":
			return str(node.get("name", "")).to_lower()
		"chunk":
			return _assigned_base(node.get("source", {}))
		"index", "dot", "prop_of":
			return _assigned_base(node.get("target", {}))
	return ""


func _bare_walk(node: Variant, entry: Dictionary, member: int, source: String,
		owned: Dictionary) -> void:
	if node is Array:
		for item in node:
			_bare_walk(item, entry, member, source, owned)
		return
	if not (node is Dictionary):
		return
	var d: Dictionary = node
	if str(d.get("node", "")) == "call_stmt":
		var call: Variant = d.get("call", null)
		if call is Dictionary and str((call as Dictionary).get("node", "")) == "var":
			var name := str((call as Dictionary).get("name", "")).to_lower()
			(entry["bare"] as Array).append({
				"name": name,
				"member": member,
				"line": int(d.get("line", 0)),
				"text": _source_line(source, int(d.get("line", 0))),
				"local": owned.has(name),
			})
	for key in d:
		_bare_walk(d[key], entry, member, source, owned)


func _source_line(source: String, line: int) -> String:
	var lines := source.split("\n")
	if line < 1 or line > lines.size():
		return ""
	return str(lines[line - 1]).strip_edges()


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.get_extension().to_lower() in ["dir", "dxr", "cst", "cxt"]:
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
