extends SceneTree
## Which movie-script handlers does a movie reach that it does not own?
##
##   godot --headless --script tools/lingo_handler_scope.gd
##   godot --headless --script tools/lingo_handler_scope.gd -- core
##   godot --headless --script tools/lingo_handler_scope.gd -- full
##   godot --headless --script tools/lingo_handler_scope.gd -- core archive-foreign
##
## Director builds a movie's handler table from that movie's own casts, plus the
## cast libraries the movie links. A handler another movie defines is not
## reachable at all. This measures whether the port agrees.
##
## It asks the engine; it does not re-implement the engine. For every handler
## name the movie's own scripts invoke, `LingoEngine.resolve_movie_handler` says
## which definition wins and from which tier — the same call `dispatch_sprite_
## event` and `dispatch_frame_event` make before they invoke a movie script. A
## name whose winning definition sits in a directory the movie neither owns nor
## links is a cross-movie resolution, and that is the defect.
##
## Written for task 4.1 against the flat, first-loaded-wins table in
## `lingo_interpreter.gd`, and rewritten for 4.7 once 4.3-4.5 gave the engine
## real per-movie tables. The 4.1 version diffed a fresh engine per movie against
## one engine carried across every movie. That comparison measures nothing now:
## per-movie tables make the two passes agree by construction, so it would print
## zero however broken resolution was. What replaced it:
##
##   resolution   every invoked name resolved through the engine's own entry
##                point, and the winning directory checked against the movie's
##                own plus linked set
##   order        the same movies traversed backwards through a second engine and
##                every resolution compared, for the spec's "the same movie
##                entered from two different predecessors resolves identically"
##   archive      `-- archive-foreign` counts a resolution into a linked cast
##                library as foreign. Those resolutions are correct, so this is
##                not a real check: it is the proof that the check above can
##                still report something
##
## The population is what the game can actually call while the movie is loaded:
## every handler name invoked by a script in the movie's own directory or in a
## cast library it links, narrowed to names some movie script defines somewhere
## in the corpus. Bare identifiers count, because `_eval` resolves an unknown one
## as a parameterless handler call. That over-counts a local sharing a handler's
## name; it cannot under-count.
##
## Two directories holding the same handler name are not automatically two
## behaviours: data/lingo/DAY1/wonder.json and data/lingo/SEA1/wonder.json carry
## byte-identical `walkonby` bodies, and resolving one for the other changes
## nothing. Bodies are hashed so a foreign resolution says whether it would have
## behaved differently.
##
## The hashes do more than annotate. The owner a resolution reports is a label
## the engine wrote next to the handler, so a check that reads it is asking the
## engine to mark its own work. `_scan_dir` reads data/lingo off disk and never
## touches the engine, so hashing the body the engine is about to invoke and
## comparing it against the scan's hash is a check the engine cannot influence:
##
##   owner   the invoked body must match what the scan says the reported owner
##           holds, or the label is wrong
##   scope   where the movie's own directory defines the name, the invoked body
##           must be that one, and where only a linked cast does, it must be the
##           first such cast. This is "own casts before the shared archive"
##           asserted against the filesystem rather than against the table

const LINGO_ROOT := "res://data/lingo"
## The set tools/lingo_converge.gd sweeps, kept so the numbers stay comparable
## with the analysis that produced the design's estimate.
const CORE_MOVIES := ["DAY1", "NIGHT1", "HOTEL1", "SEA1", "AIR1"]

## dir name -> {handler name: true}, invoked anywhere in that directory.
var _invoked_by_dir: Dictionary = {}
## dir name -> {handler name: {script, body}}, defined as a movie script there.
var _defined_by_dir: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scope := ""
	var archive_foreign := false
	for arg in OS.get_cmdline_user_args():
		var value := str(arg).strip_edges().to_lower()
		if value == "archive-foreign":
			archive_foreign = true
		elif value != "":
			scope = value

	# One runtime for the whole run. A second DirectorRuntime instantiated in the
	# same process leaves LingoEngine.new() with a null interpreter, so the
	# loader is booted once here and handed to both scopes.
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK:
		print("boot failed")
		quit(1)
		return

	if scope == "" or scope == "core":
		_report("core", CORE_MOVIES, runtime, archive_foreign)
	if scope == "" or scope == "full":
		_report("full", _playable_movies(runtime), runtime, archive_foreign)
	quit(0)


func _playable_movies(runtime: RefCounted) -> Array:
	## Every movie the runtime would actually play. Fourteen exports hold zero
	## frames: they are .CST cast libraries the export pipeline emitted as
	## movies, and goto_movie refuses them. Counting them as movies would
	## manufacture leaks out of directories no movie ever enters.
	var out: Array = []
	for name in runtime.loader.available_movies():
		if runtime.context.is_playable(runtime.loader.index, str(name)):
			out.append(str(name).to_upper())
	out.sort()
	return out


func _order(movies: Array) -> Array:
	## DAY1 first: the game's start movie and the save-file default
	## (director_runtime.gd `_snapshot_return_into_state`), then the rest
	## alphabetically. Under the flat table this order decided who won.
	var out: Array = []
	var rest: Array = []
	for movie in movies:
		if str(movie) == "DAY1":
			continue
		rest.append(str(movie))
	rest.sort()
	if movies.has("DAY1"):
		out.append("DAY1")
	out.append_array(rest)
	return out


## ------------------------------------------------------------ corpus scan


func _scan_dir(dir_name: String) -> void:
	## One pass over a directory's bundles, collecting both what it defines as a
	## movie script and what its scripts of any type call. Cached: the full scope
	## asks for the same cast libraries dozens of times.
	if _invoked_by_dir.has(dir_name):
		return
	var invoked: Dictionary = {}
	var defined: Dictionary = {}
	_invoked_by_dir[dir_name] = invoked
	_defined_by_dir[dir_name] = defined
	var dir := DirAccess.open("%s/%s" % [LINGO_ROOT, dir_name])
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".json") and file != "attach.json" and file != "sprite_scripts.json":
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string("%s/%s/%s" % [LINGO_ROOT, dir_name, file]))
			if typeof(parsed) == TYPE_DICTIONARY:
				var scripts: Dictionary = (parsed as Dictionary).get("scripts", {})
				for script_name in scripts.keys():
					var ast: Dictionary = scripts[script_name]
					if str(script_name).to_lower().begins_with("moviescript"):
						_collect_definitions(defined, str(script_name), ast)
					_collect_calls(ast, invoked)
		file = dir.get_next()
	dir.list_dir_end()


func _collect_definitions(out: Dictionary, script_name: String, ast: Dictionary) -> void:
	for handler in ast.get("handlers", []):
		var key := str((handler as Dictionary).get("name", "")).to_lower()
		if key == "" or out.has(key):
			continue
		# Keys sorted, so the hash does not turn on the order the exporter
		# happened to write them.
		out[key] = {
			"script": script_name,
			"body": JSON.stringify(
				(handler as Dictionary).get("body", []), "", true).sha256_text(),
		}


func _collect_calls(node: Variant, out: Dictionary) -> void:
	## Every name this AST could reach a handler table with: an explicit call's
	## callee, and a bare identifier, which `lingo_interpreter.gd` resolves as a
	## parameterless handler call when it is neither local nor global.
	if typeof(node) == TYPE_ARRAY:
		for child in node as Array:
			_collect_calls(child, out)
		return
	if typeof(node) != TYPE_DICTIONARY:
		return
	var dict: Dictionary = node
	var kind := str(dict.get("node", ""))
	if kind == "var":
		out[str(dict.get("name", "")).to_lower()] = true
	elif kind == "call":
		var callee: Variant = dict.get("callee", null)
		if typeof(callee) == TYPE_DICTIONARY \
				and str((callee as Dictionary).get("node", "")) == "var":
			out[str((callee as Dictionary).get("name", "")).to_lower()] = true
	for key in dict.keys():
		if key != "node" and key != "name":
			_collect_calls(dict[key], out)


func _own_dirs(runtime: RefCounted, movie: String) -> Array:
	## The directories prepare_movie will scan for this movie: its own, plus
	## every non-internal cast library the movie links. The movie owns the first
	## and shares the rest, and both are legitimate places for a name it calls to
	## resolve. MASTER is exported both as a movie and as a cast library, so it is
	## foreign only to movies that do not link it.
	var out: Array = [movie]
	var libs: Dictionary = runtime.loader.cast_libs
	for key in libs.keys():
		var entry: Variant = libs[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name := str((entry as Dictionary).get("name", "")).strip_edges().to_upper()
		if name == "" or name == "INTERNAL" or out.has(name):
			continue
		out.append(name)
	return out


func _population(dirs: Array, defined_anywhere: Dictionary) -> Array:
	## Names invoked from these directories that some movie script defines. A name
	## nothing defines is a builtin, a global or a local, and never reaches a
	## handler table.
	var seen: Dictionary = {}
	for dir_name in dirs:
		for name in (_invoked_by_dir.get(dir_name, {}) as Dictionary).keys():
			if defined_anywhere.has(name):
				seen[str(name)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func _body_of(dir_name: String, name: String) -> String:
	var defined: Dictionary = _defined_by_dir.get(dir_name, {})
	if not defined.has(name):
		return ""
	return str((defined[name] as Dictionary).get("body", ""))


## ------------------------------------------------------------ traversal


func _traverse(runtime: RefCounted, movies: Array, defined_anywhere: Dictionary) -> Dictionary:
	## One engine carried across every movie in turn, which is what
	## director_runtime.gd holds: `lingo` is built once in boot() and
	## prepare_movie is called on every move.
	var engine: RefCounted = load("res://lingo/lingo_engine.gd").new(runtime)
	var out: Dictionary = {}
	for movie in movies:
		if runtime.loader.load_movie(movie) != OK:
			continue
		engine.prepare_movie(str(movie))
		var dirs := _own_dirs(runtime, str(movie))
		var resolved: Dictionary = {}
		for name in _population(dirs, defined_anywhere):
			resolved[str(name)] = engine.resolve_movie_handler(str(name))
		out[movie] = {"dirs": dirs, "resolved": resolved}
	return out


func _report(scope: String, movies_in: Array, runtime: RefCounted, archive_foreign: bool) -> void:
	var movies := _order(movies_in)
	print("\n================================================================")
	print("scope: %s, %d movies, load order %s" % [
		scope, movies.size(),
		", ".join(PackedStringArray(movies.slice(0, mini(8, movies.size())))
			) + ("…" if movies.size() > 8 else "")])
	if archive_foreign:
		print("archive-foreign: a resolution into a linked cast library counts as foreign")
	print("================================================================")

	# ---- scan every directory in scope ----------------------------------
	var all_dirs: Array = []
	for movie in movies:
		if runtime.loader.load_movie(movie) != OK:
			continue
		for dir_name in _own_dirs(runtime, str(movie)):
			if not all_dirs.has(str(dir_name)):
				all_dirs.append(str(dir_name))
	for dir_name in all_dirs:
		_scan_dir(str(dir_name))
	## handler name -> the directories defining it, so a name nothing defines is
	## dropped from the population and a name several define can be listed.
	var defined_anywhere: Dictionary = {}
	for dir_name in all_dirs:
		for name in (_defined_by_dir.get(dir_name, {}) as Dictionary).keys():
			if not defined_anywhere.has(name):
				defined_anywhere[str(name)] = []
			(defined_anywhere[name] as Array).append(str(dir_name))

	# ---- resolve, forwards and backwards --------------------------------
	var forward := _traverse(runtime, movies, defined_anywhere)
	var backward_order: Array = movies.duplicate()
	backward_order.reverse()
	var backward := _traverse(runtime, backward_order, defined_anywhere)

	# ---- classify --------------------------------------------------------
	var rows: Array = []
	var foreign_names: Dictionary = {}
	var owners: Dictionary = {}
	var total_foreign := 0
	var differing_bodies := 0
	var movies_with_foreign := 0
	## Both measured against the filesystem scan, not against the engine.
	var owner_mismatch: Array = []
	var scope_mismatch: Array = []
	for movie in movies:
		if not forward.has(movie):
			continue
		var dirs: Array = forward[movie]["dirs"]
		var resolved: Dictionary = forward[movie]["resolved"]
		var own := 0
		var archive := 0
		var unresolved: Array = []
		var foreign: Array = []
		for name in resolved.keys():
			var hit: Dictionary = resolved[name]
			if hit.is_empty():
				unresolved.append(str(name))
				continue
			var owner := str(hit.get("owner", ""))
			# The body the interpreter would run: `call_handler` invokes the
			# table entry's own AST, which is what `handler` carries.
			var ran := JSON.stringify(
				(hit.get("handler", {}) as Dictionary).get("body", []), "", true).sha256_text()
			if ran != _body_of(owner, str(name)):
				owner_mismatch.append({"movie": movie, "name": str(name), "owner": owner,
					"script": str(hit.get("script", ""))})
			# What the rule says should have won, taken from the filesystem: the
			# movie's own directory if it defines the name, else the first linked
			# cast that does.
			var expected := ""
			var expected_dir := ""
			for dir_name in dirs:
				expected = _body_of(str(dir_name), str(name))
				if expected != "":
					expected_dir = str(dir_name)
					break
			if expected != "" and ran != expected:
				scope_mismatch.append({"movie": movie, "name": str(name), "want": expected_dir,
					"got": owner, "script": str(hit.get("script", ""))})
			var is_foreign := not dirs.has(owner)
			if str(hit.get("tier", "")) == "archive" and archive_foreign:
				is_foreign = true
			if not is_foreign:
				if owner == str(movie):
					own += 1
				else:
					archive += 1
				continue
			# What the movie would have run instead, when it defines the name at
			# all. An identical body means the resolution was wrong but inert.
			var wanted := ""
			for dir_name in dirs:
				wanted = _body_of(str(dir_name), str(name))
				if wanted != "":
					break
			var same_body := wanted != "" and wanted == _body_of(owner, str(name))
			if not same_body:
				differing_bodies += 1
			foreign.append({"name": str(name), "owner": owner, "tier": str(hit.get("tier", "")),
				"script": str(hit.get("script", "")),
				"body": "same" if same_body else ("DIFFERS" if wanted != "" else "not defined here")})
			owners[owner] = int(owners.get(owner, 0)) + 1
			if not foreign_names.has(name):
				foreign_names[str(name)] = []
			if not (foreign_names[name] as Array).has(owner):
				(foreign_names[name] as Array).append(owner)
		foreign.sort_custom(func(a, b): return str(a.name) < str(b.name))
		unresolved.sort()
		if not foreign.is_empty():
			movies_with_foreign += 1
		total_foreign += foreign.size()
		rows.append({"movie": movie, "invoked": resolved.size(), "own": own,
			"archive": archive, "unresolved": unresolved, "foreign": foreign})

	# ---- order independence ----------------------------------------------
	var order_diffs: Array = []
	for movie in movies:
		if not forward.has(movie) or not backward.has(movie):
			continue
		var one_way: Dictionary = forward[movie]["resolved"]
		var other_way: Dictionary = backward[movie]["resolved"]
		for name in one_way.keys():
			var a: Dictionary = one_way[name]
			var b: Dictionary = other_way.get(name, {})
			if str(a.get("owner", "")) == str(b.get("owner", "")) \
					and str(a.get("script", "")) == str(b.get("script", "")):
				continue
			order_diffs.append({"movie": movie, "name": str(name),
				"forward": "%s (%s)" % [str(a.get("owner", "-")), str(a.get("script", "-"))],
				"backward": "%s (%s)" % [str(b.get("owner", "-")), str(b.get("script", "-"))]})

	# ---- print ------------------------------------------------------------
	print("\n%-10s %8s %8s %9s %11s %8s" % [
		"movie", "invoked", "own", "archive", "unresolved", "foreign"])
	for row in rows:
		print("%-10s %8d %8d %9d %11d %8d" % [
			row.movie, row.invoked, row.own, row.archive,
			(row.unresolved as Array).size(), (row.foreign as Array).size()])
	print("%-10s %8s %8s %9s %11s %8d" % ["TOTAL", "", "", "", "", total_foreign])

	var duplicated: Array = []
	for name in defined_anywhere.keys():
		if (defined_anywhere[name] as Array).size() > 1:
			duplicated.append(str(name))
	duplicated.sort()
	print("\nhandler names defined in more than one directory: %d" % duplicated.size())
	for name in duplicated:
		var places := PackedStringArray()
		var bodies: Array = []
		for dir_name in defined_anywhere[name]:
			var body := _body_of(str(dir_name), str(name))
			if not bodies.has(body):
				bodies.append(body)
			places.append("%s (%s)" % [str(dir_name),
				str((_defined_by_dir[dir_name] as Dictionary)[name]["script"])])
		print("  %-24s %d %s %s" % [name, bodies.size(),
			"body" if bodies.size() == 1 else "bodies", " | ".join(places)])

	print("\nforeign: an invoked name whose winning definition is in a directory")
	print("         the movie neither owns nor links")
	var any_foreign := false
	for row in rows:
		for hit in row.foreign:
			any_foreign = true
			print("  %-10s %-24s %-8s owner %-10s %-16s %s" % [
				row.movie, hit.name, hit.tier, hit.owner, hit.body, hit.script])
	if not any_foreign:
		print("  (none)")

	print("\ninvoked and defined somewhere in the corpus, but not reachable here:")
	var any_unresolved := false
	for row in rows:
		if (row.unresolved as Array).is_empty():
			continue
		any_unresolved = true
		print("  %-10s %d: %s" % [row.movie, (row.unresolved as Array).size(),
			" ".join(PackedStringArray(row.unresolved))])
	if not any_unresolved:
		print("  (none)")

	print("\nbody check: what the engine would invoke, against the filesystem scan")
	if owner_mismatch.is_empty():
		print("  owner: every resolution runs the body its reported owner holds")
	else:
		for bad in owner_mismatch:
			print("  owner  %-10s %-24s claims %-10s %s" % [
				bad.movie, bad.name, bad.owner, bad.script])
	if scope_mismatch.is_empty():
		print("  scope: every resolution runs the body the movie's own casts, then its")
		print("         linked casts, say it should")
	else:
		for bad in scope_mismatch:
			print("  scope  %-10s %-24s want %-10s got %-10s %s" % [
				bad.movie, bad.name, bad.want, bad.got, bad.script])

	print("\norder independence: the same movies traversed backwards")
	if order_diffs.is_empty():
		print("  identical for every movie and every name")
	else:
		for diff in order_diffs:
			print("  %-10s %-24s forward %s backward %s" % [
				diff.movie, diff.name, diff.forward, diff.backward])

	var owner_keys: Array = owners.keys()
	owner_keys.sort()
	var owner_line := PackedStringArray()
	for owner in owner_keys:
		owner_line.append("%s=%d" % [str(owner), int(owners[owner])])
	var foreign_keys: Array = foreign_names.keys()
	foreign_keys.sort()
	print("\ndistinct handler names resolving outside their movie: %d" % foreign_names.size())
	if not foreign_keys.is_empty():
		print("  %s" % " ".join(PackedStringArray(foreign_keys)))
	print("movies resolving at least one handler outside themselves: %d of %d" % [
		movies_with_foreign, rows.size()])
	print("foreign resolutions by owner: %s" % (
		" ".join(owner_line) if not owner_line.is_empty() else "(none)"))
	print("of those, landing on a definition with a different body: %d" % differing_bodies)
	print("\nCROSS-MOVIE RESOLUTIONS: %d   ORDER DIFFERENCES: %d   BODY MISMATCHES: %d owner, %d scope" % [
		total_foreign, order_diffs.size(), owner_mismatch.size(), scope_mismatch.size()])
