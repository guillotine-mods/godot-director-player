extends SceneTree
## A dropped clause leaves a statement calling a handler named `of`. Find it.
##
##   godot --headless --path . --script tools/parse_residue.gd
##   godot --headless --path . --script tools/parse_residue.gd -- --root piposh
##   godot --headless --path . --script tools/parse_residue.gd -- --all
##
## `tools/script_compile_check.gd` asks whether every script *compiles*. This asks
## the question that has actually cost this port four player-visible bugs: whether
## a script that compiled compiled into what it says.
##
## Director's designators carry trailing clauses -- `field "x" of castLib 1`,
## `member (n) of castLib "decks"`, `go to frame 3 of movie "day1"`. When the
## parser stops consuming before one of them, the expression is still valid, the
## statement still compiles, and the leftover words become **a statement of their
## own**: `of` parses as a bare variable reference, `castLib "decks"` as a
## command-form call to a handler named `castlib`, `into x` as one to a handler
## named `into`. Nothing anywhere reports it. The enclosing `put ... into x` loses
## its target, so `x` is never assigned, and every later mention of `x` becomes a
## call to a handler that does not exist and answers VOID.
##
## That shape has now been found four times, each by a different bug report and
## none by a tool:
##
## | site | symptom |
## |---|---|
## | `field (…) of castLib` | the four save slots showed the wrong cast's text |
## | `member (…) of castLib` under `the number of` | `bugs.md` 16 |
## | `go to frame E of movie F` | six jumps landed on a marker in the movie the player was already in |
## | `the <prop> of member (…) of castLib` | Piposh 1's jokes and cards never reappear (`bugs.md` 41) |
##
## Three of the four are fixed and the fixes are one line each. What was missing
## was anything that would find the fourth without a player noticing first, which
## is what this is: the residue is the same in every case, and it is a shape the
## AST can be asked about directly rather than a spelling somebody has to think of.
##
## Title-agnostic. `RESIDUE` is Director's clause vocabulary, not this corpus's,
## and a name on it is one no title may legitimately declare a handler for --
## measured across all six roots in `games/`, the only hits are the real bug.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Paths := preload("res://director/director_paths.gd")

## Words that introduce a clause and can therefore be left behind by one. A
## statement calling a handler of this name is not a call the author wrote: these
## are keywords in every position Director allows them, so a movie declaring `on
## of` or `on castLib` is not a thing that exists.
const RESIDUE := ["of", "castlib", "into", "movie"]

## Every root under `games/`, for `--all`. Named rather than discovered, so that
## a directory somebody drops in beside them does not silently join the sweep and
## change the number this reports.
const ROOTS := ["piposh", "piposh2", "piposh-en", "piposh-ru", "piposh-dream", "rating"]


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var h := Harness.new()
	var roots: Array = ROOTS if Args.flag(args, "all") else [paths.root]
	for root in roots:
		var dir := str(root)
		if not dir.begins_with("res://"):
			dir = "res://games/%s" % dir
		var files := PackedStringArray()
		_collect(dir, files)
		var case_name := dir.get_file()
		h.begin(case_name)
		var scripts := 0
		var hits: Array = []
		var compiler := Compiler.new()
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var cast := Cast.new()
			if not cast.open(f):
				continue
			for number in cast.member_numbers():
				var member: Dictionary = cast.member(number)
				var source := str(member.get("source", ""))
				if source.strip_edges() == "":
					continue
				scripts += 1
				var ast := compiler.compile_source(
					source, Compiler.script_key(member, number))
				# A script that did not compile is `script_compile_check.gd`'s
				# subject, not this one. Counting it here would report one fault
				# as two and move the number every time that one moves.
				if ast.is_empty():
					continue
				var found: Array = []
				_walk(ast, found)
				for line in found:
					hits.append("%-16s %4d  line %d: a statement calling `%s`   %s" % [
						str(path).get_file(), number, int(line["line"]),
						str(line["name"]), _source_line(source, int(line["line"]))])
		for hit in hits:
			print("   %s" % hit)
		h.check("%s: no compiled statement calls a clause keyword" % case_name,
			hits.is_empty(), "%d in %d script(s)" % [hits.size(), scripts])
		# A sweep that compiled nothing asserts nothing, and a root whose
		# containers failed to open would otherwise read as the cleanest of the
		# six.
		h.check("%s: the sweep reached its scripts" % case_name, scripts > 0,
			"%d script(s)" % scripts)
		h.complete(case_name)

	quit(h.finish("no designator clause was dropped into a statement of its own"))


## `[{name, line}]` for every `call_stmt` whose callee is a clause keyword.
func _walk(node: Variant, found: Array) -> void:
	if node is Array:
		for item in node:
			_walk(item, found)
		return
	if not (node is Dictionary):
		return
	var d: Dictionary = node
	if str(d.get("node", "")) == "call_stmt":
		var name := _callee_name(d.get("call", null))
		if RESIDUE.has(name):
			found.append({"name": name, "line": int(d.get("line", 0))})
	for key in d:
		_walk(d[key], found)


## The handler name a `call_stmt` invokes, lowercased, or "".
##
## Two shapes, because the parser produces both: a bare word with no arguments is
## a `var` node used as a statement, and a word with arguments is a `call` with a
## `callee`. The first is what `of` becomes and the second what `castLib "decks"`
## becomes, so a check that knows only one of them finds half of every instance.
func _callee_name(call: Variant) -> String:
	if not (call is Dictionary):
		return ""
	var d: Dictionary = call
	if str(d.get("node", "")) == "var":
		return str(d.get("name", "")).to_lower()
	var callee = d.get("callee", null)
	if callee is Dictionary:
		return str((callee as Dictionary).get("name", "")).to_lower()
	return ""


## The source line a fault was reported on, trimmed, for a message somebody can
## act on without opening the container.
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
