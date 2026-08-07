extends SceneTree
## What Movie-In-A-Window is actually used for, across every container.
##
##   godot --headless --script tools/window_survey.gd -- --all
##   godot --headless --script tools/window_survey.gd -- --all --list
##   godot --headless --script tools/window_survey.gd -- --file PIP2DATA/DAY1.dir
##
## `docs/DIRECTOR_ENGINE.md` §14 describes the whole feature — a window per
## movie, each with its own score, cast, Lingo state, frozen-state stack, modal
## blocking, window rects and titles. Building all of that is weeks. This says
## which parts this corpus reaches, so the rest can be left out on evidence
## rather than on a guess.
##
## It compiles from the containers rather than reading `reference/lingo/`,
## because the containers are what the port runs. The two should agree, and where
## they do not the container wins.
##
## Six questions:
##
##   1. How many `tell` statements are there, and what do they name? `tell the
##      stage` and `tell window(...)` are opposite directions of the same
##      mechanism and only one of them is about opening anything.
##   2. What is *inside* a `tell` body? That is the list of things routing has to
##      get right, and it is much shorter than "all of Lingo".
##   3. Which movies are named as windows, and does each one exist on disk? A
##      named window whose file is absent is dead code, and dead code should not
##      drive a design.
##   4. Which window properties are written, and which are read? §14 lists many;
##      the corpus may use two.
##   5. Does a window movie carry its own frame scripts and handlers — does it
##      need a score and a Lingo of its own, or is it only ever puppeted from
##      outside?
##   6. How is a window closed, and from which side?
##
## Title-agnostic in the engine sense only: a harness is allowed to name what it
## found, and this one prints names because the names are the finding.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Config := preload("res://director/director_config.gd")

## "<width>x<height>" -> how many containers declare that stage size, and
## "<left>,<top>" -> how many put their stage there. A window is drawn at its own
## size and placed by its own rect (§14), so both are the design input.
var _stage_sizes: Dictionary = {}
var _stage_origins: Dictionary = {}
## Movies whose DRCF disagreed with its own CASt count — the alignment check.
var _config_mismatches: Array[String] = []

## Where a `tell` was found and what it named, for `--list`.
var _tell_sites: Array[String] = []
## Statement node kind -> times it appears directly inside a `tell` body.
var _tell_body: Dictionary = {}
## The handler names called from inside a `tell` body — the messages that have to
## reach the other movie rather than this one.
var _tell_calls: Dictionary = {}
## Builtin/command names called from inside a `tell` body.
var _tell_props_read: Dictionary = {}
var _tell_props_written: Dictionary = {}
## `tell` target shape -> count.
var _targets: Dictionary = {}
## The literal text of every window name the corpus builds, where it is literal.
var _window_names: Dictionary = {}
## Verb -> count, for `window`, `open`, `close`, `forget`.
var _verbs: Dictionary = {}
## Window property name -> [writes, reads].
var _window_props: Dictionary = {}
var _paths: Paths = null


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


static func _bump(into: Dictionary, key: String, by: int = 1) -> void:
	into[key] = int(into.get(key, 0)) + by


## A `tell` target reduced to the shape the runtime has to dispatch on, so
## `window(cdsavepath & "saveload.dxr")` and `window("map.dxr")` count as one
## thing and `the stage` as another.
func _target_shape(node: Dictionary) -> String:
	match str(node.get("node", "")):
		"prop":
			return "the " + str(node.get("prop", "?")).to_lower()
		"call":
			return _callee_name(node) + "(...)"
		"var":
			return "<variable>"
		"str":
			return "<string literal>"
	return str(node.get("node", "?"))


## Every string literal reachable inside an expression, so `cdsavepath &
## "saveload.dxr"` still yields the file name it concatenates.
func _literals(node: Variant, out: Array[String]) -> void:
	if typeof(node) == TYPE_ARRAY:
		for child in node:
			_literals(child, out)
		return
	if typeof(node) != TYPE_DICTIONARY:
		return
	var d: Dictionary = node
	if str(d.get("node", "")) == "str":
		out.append(str(d.get("value", "")))
	for key in d.keys():
		if key == "node" or key == "value":
			continue
		_literals(d[key], out)


func _scan_stmt(stmt: Variant, where: String, inside_tell: bool) -> void:
	if typeof(stmt) == TYPE_ARRAY:
		for child in stmt:
			_scan_stmt(child, where, inside_tell)
		return
	if typeof(stmt) != TYPE_DICTIONARY:
		return
	var d: Dictionary = stmt
	var kind := str(d.get("node", ""))

	if kind == "tell":
		var target: Dictionary = d.get("target", {})
		var shape := _target_shape(target)
		_bump(_targets, shape)
		var names: Array[String] = []
		_literals(target, names)
		for n in names:
			if n.strip_edges() != "":
				_bump(_window_names, n.strip_edges().to_lower())
		_tell_sites.append("%s:%d  tell %s" % [where, int(d.get("line", 0)), shape])
		# The body's *direct* statements are what routing has to carry. Nested
		# blocks are counted too, because an `if` inside a `tell` still puts its
		# branches in the other movie.
		_scan_tell_body(d.get("body", []))
		# And the body is still ordinary Lingo, so it is scanned for windows.
		_scan_stmt(d.get("body", []), where, true)
		return

	if kind == "window_prop":
		var prop := str(d.get("prop", "")).to_lower()
		var entry: Array = _window_props.get(prop, [0, 0])
		# A `window_prop` reached from `_assign`'s target is a write. The AST does
		# not mark which, so both counts are kept and the caller resolves it: an
		# assign statement's `target` is scanned separately below.
		entry[1] = int(entry[1]) + 1
		_window_props[prop] = entry

	if kind == "assign" or kind == "put":
		var t: Variant = d.get("target", {})
		if typeof(t) == TYPE_DICTIONARY:
			var td: Dictionary = t
			var tk := str(td.get("node", ""))
			if tk == "window_prop":
				var prop2 := str(td.get("prop", "")).to_lower()
				var e2: Array = _window_props.get(prop2, [0, 0])
				e2[0] = int(e2[0]) + 1
				# It was already counted as a read by the branch above when the
				# scan descends into it, so that is undone here.
				e2[1] = maxi(int(e2[1]) - 1, 0)
				_window_props[prop2] = e2
			elif tk == "dot":
				var owner: Dictionary = td.get("target", {})
				if str(owner.get("node", "")) == "call" \
						and _callee_name(owner) == "window":
					var prop3 := str(td.get("prop", "")).to_lower()
					var e3: Array = _window_props.get(prop3, [0, 0])
					e3[0] = int(e3[0]) + 1
					_window_props[prop3] = e3
			if inside_tell and (tk == "prop" or tk == "prop_of" or tk == "dot"):
				_bump(_tell_props_written, _prop_label(td))

	if kind == "call":
		var name := _callee_name(d)
		if name == "window" or name == "open" or name == "close" or name == "forget":
			_bump(_verbs, name)
			var lits: Array[String] = []
			_literals(d.get("args", []), lits)
			for n in lits:
				var text := n.strip_edges().to_lower()
				# `open window "x"` is a command with a bare word, and the parser
				# emits that word as a string literal in the argument list
				# (`lingo_grammar.gd` COMMAND_WORDS). Counting it would report a
				# window called "window" that is not on disk.
				if text == "" or text == "window":
					continue
				_bump(_window_names, text)

	if inside_tell and kind == "prop":
		_bump(_tell_props_read, "the " + str(d.get("prop", "?")).to_lower())

	for key in d.keys():
		if key == "node":
			continue
		_scan_stmt(d[key], where, inside_tell)


## A call's name lives on its `callee`, which is a `var` node — the parser builds
## calls out of a general postfix `(` so that `x.y(z)` and `f(z)` share a path.
func _callee_name(node: Dictionary) -> String:
	var callee: Variant = node.get("callee", {})
	if typeof(callee) != TYPE_DICTIONARY:
		return "?"
	return str((callee as Dictionary).get("name", "?")).to_lower()


func _prop_label(node: Dictionary) -> String:
	match str(node.get("node", "")):
		"prop":
			return "the " + str(node.get("prop", "?")).to_lower()
		"prop_of", "dot":
			var owner: Dictionary = node.get("target", {})
			return "%s of %s" % [
				str(node.get("prop", "?")).to_lower(),
				str(owner.get("node", "?")),
			]
	return str(node.get("node", "?"))


## The statements a `tell` body carries, one level down, which is the list a
## router has to be right about.
func _scan_tell_body(body: Variant) -> void:
	if typeof(body) != TYPE_ARRAY:
		return
	for stmt in body:
		if typeof(stmt) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = stmt
		var kind := str(d.get("node", ""))
		match kind:
			"call_stmt":
				var call: Dictionary = d.get("call", {})
				var name := _callee_name(call)
				_bump(_tell_body, "call %s" % name)
				_bump(_tell_calls, name)
			"assign", "put":
				var t: Dictionary = d.get("target", {})
				_bump(_tell_body, "%s -> %s" % [kind, str(t.get("node", "?"))])
			_:
				_bump(_tell_body, kind)


func _init() -> void:
	var args := Args.parse()
	_paths = Paths.new()
	if not _paths.load_config():
		print("no game configured")
		quit(1)
		return

	var targets: Array[String] = []
	if Args.flag(args, "all"):
		_walk(_paths.root, targets)
		targets.sort()
	else:
		var one: String = _paths.resolve(Args.text(args, "file", _paths.boot_movie))
		if one == "":
			print("no such container")
			quit(1)
			return
		targets.append(one)

	var containers := 0
	var scripts := 0
	var seen_casts: Dictionary = {}
	var compiler := Compiler.new()

	for path in targets:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var table := CastTable.new()
		if not table.open(f, _paths):
			table.close()
			f.close()
			continue
		containers += 1
		# The movie's own stage rect, and the check that the header is aligned.
		var config := Config.new()
		if config.read(f):
			_bump(_stage_sizes, "%dx%d" % [config.rect.size.x, config.rect.size.y])
			_bump(_stage_origins, "%d,%d" % [config.rect.position.x, config.rect.position.y])
			var casts := f.ids_of("CASt").size()
			if casts > 0 and config.cast_array_end != casts:
				_config_mismatches.append("%s: DRCF castArrayEnd %d, %d CASt chunk(s)"
					% [path.get_file(), config.cast_array_end, casts])
		for lib in table.cast_libs.keys():
			var cast = table.cast_for(int(lib))
			if cast == null:
				continue
			# The shared cast is linked by nearly every movie; compiled once per
			# movie it would multiply every count by sixty.
			var key := "%s#%d" % [
				str(table.cast_libs[lib].get("resolved_path", "")), int(cast.cas_chunk_id)]
			if seen_casts.has(key):
				continue
			seen_casts[key] = true
			var movie := path.get_file().get_basename().to_upper()
			var cast_name := str(table.cast_libs[lib].get("name", "")).to_lower()
			if cast_name == "" or int(lib) == 1:
				cast_name = "internal"
			var bundle: Dictionary = compiler.compile_cast(cast, movie, cast_name)
			var by_name: Dictionary = bundle.get("scripts", {})
			for script_name in by_name.keys():
				scripts += 1
				var ast: Dictionary = by_name[script_name]
				for handler in ast.get("handlers", []):
					_scan_stmt((handler as Dictionary).get("body", []),
						"%s/%s/%s on %s" % [movie, cast_name, script_name,
							str((handler as Dictionary).get("name", "?"))], false)
		table.close()
		f.close()

	var tell_total := 0
	for k in _targets:
		tell_total += int(_targets[k])

	print("%d container(s), %d distinct cast librar(ies), %d script(s)"
		% [containers, seen_casts.size(), scripts])
	print("")
	print("1. `tell` statements: %d" % tell_total)
	var tkeys: Array = _targets.keys()
	tkeys.sort()
	for k in tkeys:
		print("   %-22s %5d" % [k, int(_targets[k])])
	print("")
	print("2. statements directly inside a `tell` body:")
	var bkeys: Array = _tell_body.keys()
	bkeys.sort()
	for k in bkeys:
		print("   %-34s %5d" % [k, int(_tell_body[k])])
	if not _tell_props_read.is_empty():
		print("   properties read inside one:")
		for k in _tell_props_read.keys():
			print("     %-32s %5d" % [k, int(_tell_props_read[k])])
	if not _tell_props_written.is_empty():
		print("   properties written inside one:")
		for k in _tell_props_written.keys():
			print("     %-32s %5d" % [k, int(_tell_props_written[k])])
	print("")
	print("3. names that reach a window verb, and whether the file exists:")
	var nkeys: Array = _window_names.keys()
	nkeys.sort()
	for k in nkeys:
		var resolved: String = _paths.resolve(str(k))
		print("   %-24s %4d site(s)  %s" % [
			k, int(_window_names[k]),
			resolved if resolved != "" else "NOT ON DISK"])
	print("")
	print("4. window verbs:")
	var vkeys: Array = _verbs.keys()
	vkeys.sort()
	for k in vkeys:
		print("   %-10s %5d" % [k, int(_verbs[k])])
	print("   window properties (writes / reads):")
	var pkeys: Array = _window_props.keys()
	pkeys.sort()
	if pkeys.is_empty():
		print("     none")
	for k in pkeys:
		var e: Array = _window_props[k]
		print("     %-16s %d / %d" % [k, int(e[0]), int(e[1])])
	print("")
	print("5. stage rects, from each movie's own DRCF:")
	var skeys: Array = _stage_sizes.keys()
	skeys.sort()
	for k in skeys:
		print("   size   %-12s %3d container(s)" % [k, int(_stage_sizes[k])])
	var okeys: Array = _stage_origins.keys()
	okeys.sort()
	for k in okeys:
		print("   origin %-12s %3d container(s)" % [k, int(_stage_origins[k])])
	print("   header alignment (castArrayEnd vs the CASt count): %s" % (
		"agrees everywhere" if _config_mismatches.is_empty()
		else "%d disagreement(s)" % _config_mismatches.size()))
	for line in _config_mismatches:
		print("     " + line)
	print("")
	print("6. what each named window movie carries of its own:")
	for k in nkeys:
		var resolved: String = _paths.resolve(str(k))
		if resolved == "":
			continue
		_describe_movie(resolved)
	if Args.flag(args, "list"):
		print("")
		print("every `tell` site (%d):" % _tell_sites.size())
		for line in _tell_sites:
			print("   " + line)

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one container", containers > 0, "%d" % containers)
	h.check("found the tell statements", tell_total > 0, "%d" % tell_total)
	h.complete("the survey ran")
	quit(h.finish("what Movie-In-A-Window is used for in this corpus"))


## Does a window movie run itself, or is it only ever driven from outside?
##
## The answer decides the whole design. A movie with frame scripts and an
## `exitFrame` needs a score, a playhead and an interpreter of its own; one with
## none could be a picture drawn over the stage.
func _describe_movie(path: String) -> void:
	var f := ContainerFile.new()
	if not f.open(path):
		return
	var frames := 0
	var vwsc: Array = f.ids_of("VWSC")
	if not vwsc.is_empty():
		var score := Score.new()
		if score.parse(f.read_chunk(int(vwsc[0]))):
			frames = score.frame_count
	var table := CastTable.new()
	var handlers: Dictionary = {}
	var script_count := 0
	var libs: Dictionary = {}
	if table.open(f, _paths):
		libs = table.cast_libs.duplicate()
		var compiler := Compiler.new()
		for lib in table.cast_libs.keys():
			var cast = table.cast_for(int(lib))
			if cast == null or int(lib) != 1:
				continue  # the movie's own cast only; linked casts are shared
			var bundle: Dictionary = compiler.compile_cast(cast, path.get_file(), "internal")
			var by_name: Dictionary = bundle.get("scripts", {})
			script_count = by_name.size()
			for script_name in by_name.keys():
				for handler in (by_name[script_name] as Dictionary).get("handlers", []):
					_bump(handlers, str((handler as Dictionary).get("name", "?")).to_lower())
	table.close()
	f.close()
	var names: Array = handlers.keys()
	names.sort()
	var parts: Array[String] = []
	for n in names:
		parts.append("%s x%d" % [n, int(handlers[n])])
	print("   %-14s %4d frames, %3d own script(s), handlers: %s" % [
		path.get_file(), frames, script_count,
		", ".join(parts) if not parts.is_empty() else "none"])
	# Which casts the window links, and under which library number. A window that
	# writes `field "points" of castLib "master"` is writing into a cast the host
	# also has open, and the library number is local to each movie — so the two
	# only agree if the port keys shared state by the cast's file, not its number.
	for lib in libs.keys():
		print("        lib %-3s %-10s %s" % [
			str(lib), str((libs[lib] as Dictionary).get("name", "")),
			str((libs[lib] as Dictionary).get("resolved_path", "")).get_file()])
