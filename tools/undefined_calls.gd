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
## Three buckets per root, and only the third decides:
##
##   1. **resolved** -- some script in the root declares a handler of that name.
##   2. **reference-known** -- `lingo_reference_names.gd`, i.e. a builtin, a `the`
##      entity or an object method the reference answers. If this port has not
##      bound one of these it is a hole on our side, and the reference does not
##      abort on it, so neither may we.
##   3. **undefined** -- in neither. Nothing anywhere in the root declares it and
##      the reference has no table entry, so the reference aborts. This is the
##      only bucket the abort can fire in.
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
## Bare-word calls are counted separately and are **not** in the three buckets.
## `foo` with no arguments parses as a `var` node and reaches `_read_var`, not
## `_call`, where an unbound name is VOID with no abort. The reference compiles
## the statement form to `c_callcmd` and would abort, so the divergence is real
## there too -- but that arm is also every uninitialised local in the corpus, and
## separating those is its own entry. The number is here so the size of the
## deferred half is on the record rather than assumed small.
##
## A survey, not a gate: it prints numbers, and none of them is higher-is-better.
## `tools/undefined_handler.gd` is the pass/fail half.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Paths := preload("res://director/director_paths.gd")
const RefNames := preload("res://lingo/lingo_reference_names.gd")

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

	var grand := {"sites": 0, "resolved": 0, "known": 0, "undefined": 0, "bare": 0}
	var grand_names: Dictionary = {}
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
			per_file[path] = entry

		var counts := {"sites": 0, "resolved": 0, "known": 0, "undefined": 0, "bare": 0}
		var undefined_names: Dictionary = {}
		var strict := 0
		for path in per_file:
			var entry: Dictionary = per_file[path]
			counts["bare"] = int(counts["bare"]) + (entry["bare"] as Array).size()
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
		print("               resolved %6d   reference-known %5d   UNDEFINED %4d"
			% [int(counts["resolved"]), int(counts["known"]), int(counts["undefined"])])
		print("               undefined under strict per-container scoping: %d" % strict)
		print("               bare-word statements (a `_read_var` path, not `_call`): %d"
			% int(counts["bare"]))
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
	print("ALL ROOTS      %6d call site(s): resolved %d, reference-known %d, UNDEFINED %d"
		% [int(grand["sites"]), int(grand["resolved"]), int(grand["known"]),
			int(grand["undefined"])])
	print("               bare-word statements: %d" % int(grand["bare"]))
	if grand_names.is_empty():
		print("               no call in the sweep resolves nowhere")
	else:
		var names: Array = grand_names.keys()
		names.sort()
		print("               %d distinct undefined name(s): %s"
			% [names.size(), ", ".join(PackedStringArray(names))])
	quit(0)


## Collect every `call` whose callee is a plain name -- the shape that reaches
## `_call`'s fall-through -- and, separately, every bare-word statement.
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
		"call_stmt":
			var call: Variant = d.get("call", null)
			if call is Dictionary and str((call as Dictionary).get("node", "")) == "var":
				(entry["bare"] as Array).append(
					str((call as Dictionary).get("name", "")).to_lower())
	for key in d:
		_walk(d[key], entry, member, source)


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
