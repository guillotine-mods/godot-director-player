extends SceneTree
## How much of Director's surface does the port actually bind, and how much of
## what it binds does anything?
##
##   godot --headless --script tools/check_surface_coverage.gd
##   godot --headless --script tools/check_surface_coverage.gd -- play
##
## The vocabulary is `data/lingo_vocabulary.json`, recorded from the reference
## implementation and the corpus by tools/generate_lingo_vocabulary.py. It is not
## the compiler's: `tools/lingo_compile.py` closes nothing, so "every name the
## compiler can produce" would be every identifier.
##
## Four things this prints that a naive coverage report would not:
##
##   per category   sprite, movie and member are compared separately. A union of
##                  all three would let a name bound in one category pass for a
##                  name missing from another, and become a check that cannot
##                  fail.
##   per direction  read binding and write binding are different surfaces. The
##                  vocabulary records no read/write tags — see `not_taken` in
##                  its `sources` — so a one-directional binding is reported with
##                  the corpus counts beside it, and a direction the corpus never
##                  uses reads as informational rather than as a hole.
##   reachability   a bound write that lands in `LingoHost.puppet` and is read by
##                  nothing but the script that wrote it is NOT covered. This
##                  port's recurring failure is code that runs and does plausible
##                  nothing, and a report saying "sprite writes 15/15" over a
##                  dead sprite-swap mechanism is that failure in report form.
##   decided vs not the runtime marks a name it deliberately does not bind with
##                  LingoHost.UNSUPPORTED_MARK. "We chose not to" and "we have not
##                  done this yet" are different backlogs, and `-- play` splits
##                  the diagnostics on that mark.
##
## The category-level comparison is a STALENESS GUARD, not the coverage number.
## The tables partition their vocabulary by construction — bound plus declared-
## unsupported is the whole of it — so the unclassified count is zero until the
## vocabulary is regenerated and a new name lands in no table. The coverage
## number is bound against declared-unsupported, and it is not flattering.
##
## Exit code is non-zero only for a broken check: an unclassified or
## double-classified name, a binding in neither the vocabulary nor Director's
## other entities, or a builtin scrape that lost its footing. Gaps are the
## backlog, not a failure.

const VOCAB_PATH := "res://data/lingo_vocabulary.json"
const HOST_PATH := "res://lingo/lingo_host.gd"
const INTERPRETER_PATH := "res://lingo/lingo_interpreter.gd"
const RENDERER_PATHS := [
	"res://director/movie_player.gd",
	"res://director/stage_canvas.gd",
	"res://director/render_model_loader.gd",
]

## Names the builtin scrape must find, or the regex has drifted and every
## unfound name would be reported as a missing binding. Twenty-nine names from
## both dispatch sites; a scrape that misses one is not trustworthy about the
## other two hundred.
const SCRAPE_CANARY := [
	"go", "puppetsprite", "updatestage", "sound", "random", "marker", "label",
	"rollover", "intersects", "within", "window", "open", "forget", "close",
	"cursor", "alert", "beep", "nothing", "updatelock", "preloadmember",
	"unloadmember", "value", "string", "integer", "float", "abs", "length",
	"chars", "offset", "count", "getat",
]
const SCRAPE_FLOOR := 30

var _vocab: Dictionary = {}
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var play := false
	for arg in OS.get_cmdline_user_args():
		if str(arg).strip_edges().to_lower() == "play":
			play = true

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VOCAB_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("cannot read %s" % VOCAB_PATH)
		quit(2)
		return
	_vocab = parsed

	_print_header()
	var host_consts: Dictionary = (load(HOST_PATH) as GDScript).get_script_constant_map()
	var categories := _categories(host_consts)
	_report_properties(categories)
	_report_builtins(host_consts)
	_report_reachability(host_consts)
	if play:
		_report_session(host_consts)
	_print_summary()
	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)


## ------------------------------------------------------------ vocabulary


func _names_of(category: String) -> Dictionary:
	## name -> entry, for one category of the manifest. Names are already
	## lowercased there, which is what the bound tables key on.
	var out: Dictionary = {}
	var categories: Dictionary = _vocab.get("categories", {})
	var entry: Dictionary = categories.get(category, {})
	for name in entry.get("names", []):
		out[str((name as Dictionary).get("name", ""))] = name
	return out


func _entity_of(name: String) -> String:
	## Which Director entity, other than the four categories, carries this
	## property. `the volume of sound 1` is real Lingo about an entity this port
	## does not model, and that is not the same as a name nobody ever defined.
	var owners: PackedStringArray = PackedStringArray()
	var others: Dictionary = _vocab.get("other_entities", {})
	var keys: Array = others.keys()
	keys.sort()
	for entity in keys:
		if (others[entity] as Array).has(name):
			owners.append(str(entity))
	return ", ".join(owners)


func _ambiguous_of(name: String) -> Variant:
	## Names the generator could not attribute to one entity, counted across the
	## whole corpus. `volume` is 2 reads and 66 writes bare, against 0 and 2 for
	## the sprite property, so nearly every use is about something else.
	for entry in _vocab.get("ambiguous", []):
		if str((entry as Dictionary).get("name", "")) == name:
			return entry
	return null


func _corpus(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "corpus -"
	var reads := int((entry as Dictionary).get("reads", 0))
	var writes := int((entry as Dictionary).get("writes", 0))
	if reads == 0 and writes == 0:
		return "corpus unused"
	return "corpus r=%d w=%d" % [reads, writes]


func _sorted(names: Dictionary) -> Array:
	var out: Array = names.keys()
	out.sort()
	return out


func _union(parts: Array) -> Dictionary:
	var out: Dictionary = {}
	for part in parts:
		for key in (part as Dictionary).keys():
			out[str(key)] = true
	return out


func _minus(from: Dictionary, remove: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in from.keys():
		if not remove.has(key):
			out[str(key)] = true
	return out


func _intersect(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in a.keys():
		if b.has(key):
			out[str(key)] = true
	return out


## ------------------------------------------------------------ properties


func _categories(host: Dictionary) -> Array:
	## The bound tables, straight off the host's script constants rather than
	## copied here, so a table that changes cannot leave this check describing the
	## old one.
	##
	## `aside` is a table of real Director property names that belong to another
	## entity, so the category vocabulary must not be searched for them: ScummVM
	## keeps drawRect, rect, titleVisible and windowType on kTheWindow. They still
	## go through the three-way test below, which resolves them against
	## `other_entities`.
	return [
		{
			"name": "sprite",
			"reads": host["SPRITE_READS"],
			"writes": host["SPRITE_WRITES"],
			"elsewhere": {},
			"unsupported": host["SPRITE_UNSUPPORTED"],
			"aside": {},
		},
		{
			"name": "movie",
			"reads": host["MOVIE_READS"],
			"writes": host["MOVIE_WRITES"],
			# `the itemDelimiter` never reaches the host: the interpreter answers
			# it at lingo_interpreter.gd:366 and :521, in both directions.
			"elsewhere": host["MOVIE_BOUND_ELSEWHERE"],
			"unsupported": host["MOVIE_UNSUPPORTED"],
			"aside": host["WINDOW_FIELDS"],
		},
		{
			"name": "member",
			"reads": host["MEMBER_READS"],
			"writes": host["MEMBER_WRITES"],
			"elsewhere": {},
			"unsupported": host["MEMBER_UNSUPPORTED"],
			"aside": {},
		},
	]


func _report_properties(categories: Array) -> void:
	print("\n================================================================")
	print("BOUND AGAINST THE VOCABULARY, PER CATEGORY")
	print("================================================================")
	print("bound = readable or writable by some binding. unsupported = in the")
	print("vocabulary and deliberately unbound, marked at runtime with")
	print("LingoHost.UNSUPPORTED_MARK. Those two are the coverage; the columns")
	print("after them are the guard.\n")
	print("%-8s %6s %6s %6s %6s %12s %13s %10s" % [
		"category", "vocab", "bound", "read", "write", "unsupported",
		"unclassified", "both"])

	var per_direction: Array = []
	var used_unsupported: Array = []
	var outside: Array = []
	for category in categories:
		var cat: Dictionary = category
		var name := str(cat["name"])
		var vocabulary := _names_of(name)
		var vocab_set: Dictionary = {}
		for key in vocabulary.keys():
			vocab_set[str(key)] = true

		var reads: Dictionary = cat["reads"]
		var writes: Dictionary = cat["writes"]
		var elsewhere: Dictionary = cat["elsewhere"]
		var unsupported: Dictionary = cat["unsupported"]
		var bound := _union([reads, writes, elsewhere])

		# ---- the staleness guard --------------------------------------------
		# Unclassified: in the vocabulary and in no table at all. Both: claimed as
		# bound and as deliberately unsupported, which makes the coverage number
		# meaningless because the same name is counted on both sides.
		var unclassified := _minus(_minus(vocab_set, bound), unsupported)
		var both := _intersect(bound, unsupported)
		print("%-8s %6d %6d %6d %6d %12d %13d %10d" % [
			name, vocab_set.size(), _intersect(bound, vocab_set).size(),
			_intersect(reads, vocab_set).size(), _intersect(writes, vocab_set).size(),
			_intersect(unsupported, vocab_set).size(), unclassified.size(), both.size()])
		if not unclassified.is_empty():
			_fail("%s: %d vocabulary names in no table: %s" % [
				name, unclassified.size(), " ".join(PackedStringArray(_sorted(unclassified)))])
		if not both.is_empty():
			_fail("%s: %d names both bound and declared unsupported: %s" % [
				name, both.size(), " ".join(PackedStringArray(_sorted(both)))])

		# ---- read and write are different surfaces ---------------------------
		for direction in ["read", "write"]:
			var side: Dictionary = _union([
				reads if direction == "read" else writes, elsewhere])
			var gap := _minus(_minus(vocab_set, side), unsupported)
			for missing in _sorted(gap):
				per_direction.append({
					"category": name, "direction": direction, "name": str(missing),
					"corpus": _corpus(vocabulary.get(missing, null)),
					"other": "bound to write" if direction == "read" else "bound to read",
				})

		# ---- declared unsupported, and used anyway ---------------------------
		for missing in _sorted(_intersect(unsupported, vocab_set)):
			var entry: Dictionary = vocabulary.get(missing, {})
			if int(entry.get("reads", 0)) == 0 and int(entry.get("writes", 0)) == 0:
				continue
			used_unsupported.append({
				"category": name, "name": str(missing), "corpus": _corpus(entry)})

		# ---- bound, but not in this category's vocabulary --------------------
		# Three answers, and only the third is a defect: in the vocabulary, in
		# `other_entities` (real Lingo about an entity the port does not model),
		# or in neither, which means the port made the name up.
		for extra in _sorted(_union([bound, cat["aside"]])):
			if vocab_set.has(extra):
				continue
			outside.append({
				"category": name, "name": str(extra), "entity": _entity_of(str(extra))})

	_print_direction_gaps(per_direction)
	_print_used_unsupported(used_unsupported)
	_print_outside(outside)


func _print_direction_gaps(rows: Array) -> void:
	print("\n---- bound in one direction only --------------------------------")
	print("The vocabulary records no read/write tags, so this cannot say whether")
	print("Director allows the other direction. What it does say is that the port")
	print("has no binding there. Read the corpus column: a direction the game")
	print("never uses is informational, a direction it does use is a gap.")
	if rows.is_empty():
		print("  (none)")
		return
	for row in rows:
		print("  %-7s %-6s %-22s %-16s %s" % [
			row.category, row.direction, row.name, row.other, row.corpus])


func _print_used_unsupported(rows: Array) -> void:
	print("\n---- declared unsupported, and used by the game anyway -----------")
	print("A deliberate divergence over a name the corpus never touches costs")
	print("nothing. Over one it does touch, it is a decision with a consequence,")
	print("and it belongs in the backlog with its usage count attached.")
	if rows.is_empty():
		print("  (none)")
		return
	for row in rows:
		print("  %-7s %-22s %s" % [row.category, row.name, row.corpus])


func _print_outside(rows: Array) -> void:
	print("\n---- bound, but not in that category's vocabulary ----------------")
	print("entity named: real Lingo, on a Director entity this port does not")
	print("model, so not a gap. blank: the port invented the name.")
	if rows.is_empty():
		print("  (none)")
		return
	for row in rows:
		var where := str(row.entity)
		print("  %-7s %-22s %s" % [
			row.category, row.name,
			("entity %s" % where) if where != "" else "INVENTED BY THE PORT"])
		if where == "":
			_fail("%s: binds `%s`, which the vocabulary does not enumerate anywhere" % [
				row.category, row.name])


## ------------------------------------------------------------ builtins


func _scrape_case_labels(path: String, function: String) -> Dictionary:
	## The case labels of the top-level match inside one function. Builtins are
	## not a table — they are match arms in `LingoHost.call_builtin` and in
	## `LingoInterpreter._call` — so the only way to enumerate what is bound is to
	## read the dispatch. Restricted to labels at exactly two tabs inside one
	## function so that nested matches and other functions' arms cannot leak in:
	## `_sound`'s playFile/stop/fadeOut are sound verbs, not builtin names, and
	## `_set_state_global`'s arms are global names.
	var out: Dictionary = {}
	var source := FileAccess.get_file_as_string(path)
	var inside := false
	var label := RegEx.new()
	label.compile("^\\t\\t(\"[a-z0-9_]+\"(,\\s*)?)+:$")
	var quoted := RegEx.new()
	quoted.compile("\"([a-z0-9_]+)\"")
	for line in source.split("\n"):
		var text := str(line)
		if text.begins_with("func "):
			inside = text.begins_with("func %s(" % function)
			continue
		if not inside:
			continue
		if label.search(text) == null:
			continue
		for hit in quoted.search_all(text):
			out[hit.get_string(1)] = true
	return out


func _report_builtins(host: Dictionary) -> void:
	print("\n================================================================")
	print("BUILTIN CALLS")
	print("================================================================")
	var bound := _scrape_case_labels(HOST_PATH, "call_builtin")
	var interpreter_side := _scrape_case_labels(INTERPRETER_PATH, "_call")
	var constants := _scrape_case_labels(INTERPRETER_PATH, "_read_var")
	for key in _union([interpreter_side, constants]).keys():
		bound[str(key)] = true
	for native in host["NATIVE_HANDLERS"]:
		bound[str(native).to_lower()] = true

	var missing_canary: PackedStringArray = PackedStringArray()
	for name in SCRAPE_CANARY:
		if not bound.has(str(name)):
			missing_canary.append(str(name))
	print("bound builtins found by reading the dispatch: %d" % bound.size())
	if not missing_canary.is_empty() or bound.size() < SCRAPE_FLOOR:
		print("SCRAPE FAILED: %d found, canary missing %s" % [
			bound.size(), " ".join(missing_canary)])
		print("The gap list is suppressed: a scrape that lost its footing would")
		print("report every builtin in the vocabulary as unbound.")
		_fail("builtin scrape failed: canary missing %s" % " ".join(missing_canary))
		return

	var vocabulary := _names_of("builtin")
	var considered: Dictionary = {}
	var excluded := 0
	for name in vocabulary.keys():
		var entry: Dictionary = vocabulary[name]
		# `handler_defined` names are this game's own handlers, which the corpus
		# defines and the runtime resolves through the handler table. `artefact`
		# names are parser wreckage. Neither is a builtin the port owes.
		if bool(entry.get("handler_defined", false)) or bool(entry.get("artefact", false)):
			excluded += 1
			continue
		considered[str(name)] = true
	print("vocabulary: %d names, %d excluded as game handlers or parser artefacts, %d considered" % [
		vocabulary.size(), excluded, considered.size()])
	var covered := _intersect(bound, considered)
	var gaps := _minus(considered, bound)
	print("bound: %d of %d   unbound: %d" % [covered.size(), considered.size(), gaps.size()])
	print("\nUnbound builtins the corpus actually calls (the part that matters):")
	var used := 0
	for name in _sorted(gaps):
		var entry: Dictionary = vocabulary[name]
		if int(entry.get("reads", 0)) == 0 and int(entry.get("writes", 0)) == 0:
			continue
		used += 1
		print("  %-24s %s" % [name, _corpus(entry)])
	if used == 0:
		print("  (none)")
	print("\nUnbound and never called by the corpus: %d" % (gaps.size() - used))
	var never: PackedStringArray = PackedStringArray()
	for name in _sorted(gaps):
		var entry: Dictionary = vocabulary[name]
		if int(entry.get("reads", 0)) == 0 and int(entry.get("writes", 0)) == 0:
			never.append(str(name))
	print("  %s" % " ".join(never))

	print("\nBound, but not in the builtin vocabulary:")
	var invented: PackedStringArray = PackedStringArray()
	for name in _sorted(_minus(bound, considered)):
		if vocabulary.has(name):
			continue  # excluded above as a game handler, and bound natively
		invented.append(str(name))
	print("  %s" % (" ".join(invented) if not invented.is_empty() else "(none)"))
	print("  Not automatically a defect: the builtin vocabulary is transcribed")
	print("  from lingo-builtins.cpp, so Lingo's operators and constants, which")
	print("  ScummVM keeps elsewhere, land here too. Each is named in the backlog.")


## ------------------------------------------------------------ reachability


func _report_reachability(host: Dictionary) -> void:
	print("\n================================================================")
	print("REACHABILITY: does a bound write reach anything?")
	print("================================================================")
	print("Binding is not coverage. `set the memberNum of sprite N` is bound, and")
	print("it writes into LingoHost.puppet, which the renderer never reads. Three")
	print("states, and the middle one must not count as covered:")
	print("  consumed   something outside lingo_host.gd acts on the value")
	print("  inert      stored, and read back only by the script that wrote it")
	print("  unbound    no binding at all\n")

	# REWRITTEN after SpriteChannel landed. This table is hand-maintained prose,
	# and it went silently wrong the moment the renderer changed under it: it had
	# 806 corpus writes filed as INERT on the strength of movie_player building
	# every sprite from the score frame. It no longer does. draw_current_frame now
	# reads runtime.channel_sprites() (movie_player.gd:390), whose own comment
	# names the defect this table used to measure — "reading the score frame here
	# is what made `set the memberNum of sprite N` and every Lingo-driven move
	# invisible".
	#
	# So a hardcoded verdict here is a claim with a shelf life. Anything below
	# marked `unverified` has NOT been traced to a consumer since that change and
	# must not be quoted as evidence. Re-read the consumer before trusting a line.
	var sprite_reach := {
		"visible": "consumed  runtime.set_channel_visible -> _lingo_hidden -> movie_player.gd:403",
		"puppet": "consumed  channel ownership; gates the per-frame reconcile",
		"membernum": "consumed  entry.set_member -> channel_sprites -> the draw",
		"castnum": "consumed  same path as memberNum",
		"member": "consumed  same path as memberNum",
		"castlibnum": "consumed  entry.sprite.cast_lib -> the draw",
		"castlib": "consumed  alias of castLibNum; not a Lingo sprite property",
		"loch": "consumed  entry.set_loc -> the draw, and sprite_rect for hit-testing",
		"locv": "consumed  entry.set_loc -> the draw, and sprite_rect for hit-testing",
		"width": "consumed  entry.set_size -> the draw",
		"height": "consumed  entry.set_size -> the draw",
		"ink": "consumed  entry.sprite.ink -> the draw",
		"moveablesprite": "unverified stored on the channel and read back; drag consumer not re-traced",
		"movablesprite": "unverified alias of moveableSprite; same question",
		"constraint": "unverified stored on the channel and read back; no consumer re-traced",
		"cursor": "unverified stored on the channel; the port substitutes a system cursor",
		"volume": "unverified no audio consumer found before the change; not re-traced",
	}
	# All five movie writes checked for a consumer outside lingo_host.gd. Two say
	# so in their own source comments: centerStage is "nothing to centre" and
	# exitLock is "nothing to lock here; stored so a read agrees".
	var movie_reach := {
		"soundlevel": "consumed  AudioServer.set_bus_volume_db, in set_system_prop",
		"keydownscript": "consumed  director_runtime.gd:554 runs the named handler on a keypress",
		"searchpath": "INERT     stored and read back; the declared divergence keeps it empty",
		"centerstage": "INERT     stored so a read agrees with the write",
		"exitlock": "INERT     stored so a read agrees with the write",
	}

	var guard_hits: PackedStringArray = PackedStringArray()
	var probe := RegEx.new()
	# `puppet` alone would match PuppetController, which movie_player uses on
	# every frame and which is a different thing entirely.
	probe.compile("get_sprite_prop|host\\.puppet|\\.puppet\\[|lingo\\.")
	for path in RENDERER_PATHS:
		for line in FileAccess.get_file_as_string(str(path)).split("\n"):
			if probe.search(str(line)) != null:
				guard_hits.append("%s: %s" % [str(path), str(line).strip_edges()])

	var vocabulary := _names_of("sprite")
	var inert_writes := 0
	print("sprite writes, by what consumes them:")
	for name in _sorted(host["SPRITE_WRITES"]):
		var state := str(sprite_reach.get(name, "UNCLASSIFIED — this table has gone stale"))
		if state.begins_with("INERT"):
			inert_writes += int(vocabulary.get(name, {}).get("writes", 0))
		if not sprite_reach.has(name):
			_fail("sprite write `%s` has no reachability classification" % name)
		print("  %-16s %-14s %s" % [name, _corpus(vocabulary.get(name, null)), state])
	var movie_vocab := _names_of("movie")
	print("\nmovie writes, by what consumes them:")
	for name in _sorted(host["MOVIE_WRITES"]):
		if not movie_reach.has(name):
			_fail("movie write `%s` has no reachability classification" % name)
		print("  %-16s %-14s %s" % [
			name, _corpus(movie_vocab.get(name, null)),
			str(movie_reach.get(name, "UNCLASSIFIED — this table has gone stale"))])
	print("\nwindow fields, accepted and dropped by set_system_prop:")
	print("(no movie-vocabulary counts: these are kTheWindow names. Where the")
	print("generator counted the bare name it could not say which entity meant it.)")
	for name in _sorted(host["WINDOW_FIELDS"]):
		print("  %-16s %-14s INERT     one stage here: nothing to place, title or resize" % [
			name, _corpus(_ambiguous_of(str(name)))])

	print("\nGuard: the draw path must not consult Lingo's sprite state, or the")
	print("classification above is out of date.")
	if guard_hits.is_empty():
		print("  holds: no reference to get_sprite_prop, host.puppet or the engine in")
		print("  %s" % ", ".join(PackedStringArray(RENDERER_PATHS)))
	else:
		for hit in guard_hits:
			print("  %s" % hit)
		_fail("the renderer now reads Lingo sprite state; the reachability table needs revisiting")

	print("\nCorpus writes landing in state nothing outside lingo_host.gd reads: %d" % inert_writes)
	print("That number is the size of the lie a plain `sprite writes %d/%d` would tell." % [
		(host["SPRITE_WRITES"] as Dictionary).size(),
		(host["SPRITE_WRITES"] as Dictionary).size()])


## ------------------------------------------------------------ a played session


## What the static check cannot say: which of these names the game reaches. The
## caps keep the sweep finite and are printed with the result, because a thin
## harness that reports nothing must not read as a clean surface.
##
## The movies the walk and convergence harnesses already sweep, so the numbers
## stay comparable, followed by whatever else is playable until the budget runs
## out. Room labels are how this game addresses rooms: `go to frame "edge1go"`.
const SESSION_MOVIES := ["DAY1", "NIGHT1", "HOTEL1", "SEA1", "AIR1"]
const SESSION_LABELS := 10
const SESSION_SPRITES := 6
const SESSION_TICKS := 6
const SESSION_BUDGET_MS := 240000
const SESSION_SEED := 12345


func _visit(runtime: RefCounted, movie: String, counters: Dictionary, started: int) -> void:
	if Time.get_ticks_msec() - started > SESSION_BUDGET_MS:
		return
	if not runtime.goto_movie(movie, null, {}):
		return
	counters["movies"] = int(counters["movies"]) + 1
	for _i in SESSION_TICKS:
		runtime.tick(0.1)
	var labels: Array = runtime.loader.labels.keys()
	labels.sort()
	var entered := 0
	for label in labels:
		if entered >= SESSION_LABELS or Time.get_ticks_msec() - started > SESSION_BUDGET_MS:
			break
		entered += 1
		counters["labels"] = int(counters["labels"]) + 1
		# Enter the room, then activate its hotspots one after another. A hotspot
		# that walks Piposh out of the room leaves the next one unreachable, so
		# the room is re-entered whenever the click moved the game somewhere else.
		if not runtime.goto_movie(movie, null, {"label": str(label)}):
			continue
		for _i in SESSION_TICKS:
			runtime.tick(0.1)
		var here: int = runtime.frame_index
		var sprites: Array = runtime.clickable_sprites(
			runtime.loader.get_frame(runtime.frame_index))
		for index in mini(SESSION_SPRITES, sprites.size()):
			if str(runtime.loader.movie_name).to_upper() != movie \
					or runtime.frame_index != here:
				if not runtime.goto_movie(movie, null, {"label": str(label)}):
					break
				for _i in SESSION_TICKS:
					runtime.tick(0.1)
				sprites = runtime.clickable_sprites(
					runtime.loader.get_frame(runtime.frame_index))
				here = runtime.frame_index
				if index >= sprites.size():
					break
			var sprite: Dictionary = sprites[index]
			runtime._activate_sprite(sprite, runtime.sprite_stage_rect(sprite).get_center())
			counters["clicks"] = int(counters["clicks"]) + 1
			for _i in SESSION_TICKS:
				runtime.tick(0.1)
	print("  %-10s %2d labels, %d clicks so far, %ds elapsed" % [
		movie, entered, int(counters["clicks"]), (Time.get_ticks_msec() - started) / 1000])


func _play(runtime: RefCounted, counters: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	## `random` is Godot's global RNG, so an unseeded sweep visits different
	## branches every run and two backlogs could not be diffed. Seeded here rather
	## than in the runtime, which must stay random when the game is played.
	seed(SESSION_SEED)
	## The first minute, the path tools/smoke.gd asserts: the menu, New Game, the
	## intro, and DAY1.
	runtime.goto_movie("strtgame", null, {})
	for _i in 20:
		runtime.tick(0.1)
	var new_game: Dictionary = {}
	for sprite in runtime.clickable_sprites(runtime.loader.get_frame(runtime.frame_index)):
		if int((sprite as Dictionary).get("channel", 0)) == 4:
			new_game = sprite
	if not new_game.is_empty():
		runtime.perform_click(runtime.sprite_stage_rect(new_game).get_center())
		counters["clicks"] = int(counters["clicks"]) + 1
	for _i in 1200:
		runtime.tick(0.1)
	counters["movies"] = int(counters["movies"]) + 1
	print("  strtgame   the menu, New Game, the intro, DAY1: %ds elapsed" % [
		(Time.get_ticks_msec() - started) / 1000])

	## Then wider than the first minute, because the first minute is not a survey.
	var visited: Dictionary = {}
	for movie in SESSION_MOVIES:
		visited[str(movie)] = true
		_visit(runtime, str(movie), counters, started)
	for movie in runtime.loader.available_movies():
		var name := str(movie).to_upper()
		if visited.has(name) or not runtime.context.is_playable(runtime.loader.index, name):
			continue
		visited[name] = true
		_visit(runtime, name, counters, started)
	counters["seconds"] = (Time.get_ticks_msec() - started) / 1000


func _report_session(host: Dictionary) -> void:
	print("\n================================================================")
	print("A PLAYED SESSION: what the game actually reached")
	print("================================================================")
	var settings: Object = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true
	var state: Object = root.get_node("GameState")
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	runtime.boot()
	state.new_game()
	var counters: Dictionary = {"movies": 0, "labels": 0, "clicks": 0, "seconds": 0}
	print("Sweeping: %d room labels and %d hotspots per movie, %ds budget." % [
		SESSION_LABELS, SESSION_SPRITES, SESSION_BUDGET_MS / 1000])
	_play(runtime, counters)

	var stats: Dictionary = runtime.lingo.stats()
	var entries: Array = stats.get("diagnostics", [])
	print("\nmovies entered %d, room labels entered %d, sprites activated %d, %ds" % [
		int(counters["movies"]), int(counters["labels"]), int(counters["clicks"]),
		int(counters["seconds"])])
	print("diagnostics: %d distinct name+location entries, %d dropped at the cap" % [
		entries.size(), int(stats.get("diagnostics_dropped", 0))])
	var unhandled: PackedStringArray = runtime.lingo.host.unhandled_names()
	print("host.unhandled_names(): %s" % (
		" ".join(unhandled) if not unhandled.is_empty() else "(empty)"))

	var mark := str(host["UNSUPPORTED_MARK"])
	var by_category: Dictionary = {}
	for entry in entries:
		var row: Dictionary = entry
		var category := str(row.get("category", ""))
		if not by_category.has(category):
			by_category[category] = {}
		var names: Dictionary = by_category[category]
		var raw := str(row.get("name", ""))
		if not names.has(raw):
			names[raw] = {"count": 0, "where": []}
		var slot: Dictionary = names[raw]
		slot["count"] = int(slot["count"]) + int(row.get("count", 1))
		var where := "%s/%s" % [str(row.get("script", "")), str(row.get("handler", ""))]
		if not (slot["where"] as Array).has(where):
			(slot["where"] as Array).append(where)

	print("\nA name the runtime deliberately does not bind is reported with")
	print("`%s` on the end; an unknown one is reported bare. Those are" % mark.strip_edges())
	print("two different backlogs: a decision taken and a decision not yet made.")
	var order: Array = by_category.keys()
	order.sort()
	if order.is_empty():
		print("\n  Nothing was reported. That is a statement about this harness, not")
		print("  about the surface: the static sections above list what is unbound.")
	for category in order:
		var names: Dictionary = by_category[category]
		var vocabulary := _names_of(_vocabulary_for(str(category)))
		print("\n  %s: %d distinct names" % [str(category), names.size()])
		if _vocabulary_for(str(category)) == "":
			# categories_order is sprite, movie, member, builtin. Events are not
			# enumerated at all, and an unset variable or an unbound bare name is
			# the game's own vocabulary rather than Director's, so "not in the
			# vocabulary" would be a statement about the manifest, not the port.
			print("    (no recorded vocabulary for this category: the manifest")
			print("     enumerates sprite, movie, member and builtin only)")
		if str(category) == LingoDiagnostics.EVENT:
			print("    An EVENT entry is lingo_engine.gd:401, reached when neither the")
			print("    frame script nor a movie handler resolves the event. That is")
			print("    ordinary Director playback on most frames, not an unbound name.")
		for name in _sorted(names):
			var raw := str(name)
			var decided := raw.ends_with(mark)
			var bare := raw.substr(0, raw.length() - mark.length()) if decided else raw
			print("    %-9s %-24s x%-5d %-30s %s" % [
				"DECIDED" if decided else "not yet", bare, int(names[raw]["count"]),
				_classify(bare, vocabulary),
				" ".join(PackedStringArray((names[raw]["where"] as Array).slice(0, 2)))])
	print("\n  member_prop over-collects: lingo_interpreter.gd:536 and :551 route")
	print("  every dot and `of` access on a non-sprite, non-member expression into")
	print("  get_member_prop, so a name listed there is not necessarily a member")
	print("  property. `the volume of sound 1` arrives that way.")
	_self_test(runtime, host, entries.size())


func _classify(name: String, vocabulary: Dictionary) -> String:
	## The three-way test, on a name the runtime actually reported. Only the third
	## answer is a binding the port owes.
	if vocabulary.has(name):
		var entry: Dictionary = vocabulary[name]
		if bool(entry.get("handler_defined", false)):
			# In the builtin vocabulary because the game defines it, not because
			# Director does. Reported here means the handler table did not resolve
			# it from where it was called, which is a scope question, not a
			# missing builtin.
			return "the game's own handler"
		return _corpus(entry)
	var entity := _entity_of(name)
	if entity != "":
		return "entity %s, not modelled" % entity
	return "in no vocabulary"


func _self_test(runtime: RefCounted, host: Dictionary, before: int) -> void:
	## The classification above has three arms and this session exercised one of
	## them, so the other two are unproven by it. Three deliberate accesses on the
	## live host, read back out of the same sink the session used:
	##
	##   blend    in the sprite vocabulary and in SPRITE_UNSUPPORTED, so the
	##            report must carry the mark and read DECIDED
	##   zorble   in nothing, so it must report bare
	##   volume   `the volume of sound 1`, which lingo_interpreter.gd:551 sends to
	##            get_member_prop. Real Lingo about an entity this port does not
	##            model, so the three-way test must name the entity rather than
	##            count it as a missing member binding
	print("\n---- the classifier, exercised on purpose --------------------------")
	var live: Object = runtime.lingo.host
	live.get_sprite_prop(1, "blend")
	live.get_sprite_prop(1, "zorble")
	live.get_member_prop(1, "", "volume")
	var mark := str(host["UNSUPPORTED_MARK"])
	var probes := {"blend": "sprite", "zorble": "sprite", "volume": "member"}
	var seen: Dictionary = {}
	for entry in runtime.lingo.stats().get("diagnostics", []).slice(0):
		var row: Dictionary = entry
		var raw := str(row.get("name", ""))
		var bare := raw.substr(0, raw.length() - mark.length()) if raw.ends_with(mark) else raw
		if probes.has(bare):
			seen[bare] = "%-9s %s" % [
				"DECIDED" if raw.ends_with(mark) else "not yet",
				_classify(bare, _names_of(str(probes[bare])))]
	for name in ["blend", "zorble", "volume"]:
		if not seen.has(name):
			_fail("the classifier probe for `%s` reported nothing" % name)
			print("  %-10s reported nothing — the diagnostic path has changed" % name)
			continue
		print("  %-10s %s" % [name, str(seen[name])])
	print("  (%d entries before the probes, %d after)" % [
		before, (runtime.lingo.stats().get("diagnostics", []) as Array).size()])


func _vocabulary_for(category: String) -> String:
	match category:
		"sprite_prop": return "sprite"
		"movie_prop": return "movie"
		"member_prop": return "member"
		"builtin": return "builtin"
	return ""


## ------------------------------------------------------------ summary


func _print_header() -> void:
	var version: Dictionary = _vocab.get("director_version", {})
	print("================================================================")
	print("SURFACE COVERAGE")
	print("vocabulary: %s, generated by %s" % [VOCAB_PATH, str(_vocab.get("generated_by", "?"))])
	print("Director %d, %s" % [
		int(version.get("resolved", 0)), str(version.get("status", ""))])
	print("================================================================")


func _print_summary() -> void:
	print("\n================================================================")
	if _failures.is_empty():
		print("CHECK OK: every vocabulary name is classified, every binding is")
		print("real Lingo, and the dispatch scrape found what it should.")
	else:
		print("CHECK FAILED: %d" % _failures.size())
		for failure in _failures:
			print("  %s" % failure)
	print("================================================================")
