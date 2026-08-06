extends SceneTree
## The GDScript Lingo compiler against the committed ASTs, script for script.
##
##   godot --headless --script tools/lingo_compile_check.gd
##   godot --headless --script tools/lingo_compile_check.gd -- --file DAY1.dir
##   godot --headless --script tools/lingo_compile_check.gd -- --all
##   godot --headless --script tools/lingo_compile_check.gd -- --all --diffs 60
##   godot --headless --script tools/lingo_compile_check.gd -- --allow res://x.allow
##
## `lingo/compile/lingo_compiler.gd` is replacing `tools/lingo_compile.py`, and
## the two have to agree or the port changes behaviour with nobody editing the
## interpreter. The Python read `reference/lingo/**/*.ls` — a ProjectorRays dump
## of the original DXRs — and emitted `data/lingo/<MOVIE>/<cast>.json`. The
## GDScript reads the Lingo straight out of the containers the game ships.
## Different input, same output required.
##
## The baseline is the committed JSON, read with `JSON.parse_string`, because
## that is exactly what `lingo/lingo_engine.gd` hands the interpreter today.
## Comparing against a fresh run of the Python would only prove the two
## compilers agree with each other; comparing against the shipped bundle proves
## the swap is invisible to the running game.
##
## Compared in memory, never as serialised text. `JSON.stringify` of two equal
## ASTs differs on key order and on `1` vs `1.0`, so a text diff prints noise and
## buries the one difference that matters: `typeof`. `lingo/lingo_value.gd`
## divides int by int as integer division, so a `num` node whose `value` is 2 and
## one whose value is 2.0 are different games — `x / 4` is 0 or it is 0.5. Every
## leaf is therefore compared on `typeof` first and on value second.
##
## WHAT THE NUMBERS ACTUALLY ARE, because the obvious assumption is wrong.
## Godot 4.7.1's `JSON.parse_string` widens every JSON number to float: probed
## on this build, `{"i": 1}` comes back typed 3 (float), not 2 (int), and so do
## 0, -3 and 1e2. The Python emitted `"value":1` for an integer literal, but by
## the time `lingo_engine.gd` has read the bundle back the interpreter is holding
## a float — so what this game runs today is float arithmetic on every literal in
## the corpus. A GDScript compiler that hands the interpreter an int 1 instead is
## therefore changing behaviour, not formatting, and it will print here as a wall
## of `type` differences on `num.value`. That wall is the finding. It does not
## belong on the allow-list: a corpus-wide numeric regime is a decision about
## `lingo_value.gd`, not an exception about one script.
##
## `_diff` is self-tested against exactly that pair before anything is compared.
## The obvious way to quiet the wall is a numeric tolerance, and a comparator
## carrying one cannot fail on the thing it exists to catch.
##
## What this would MISS, spelled out so nobody reads the fraction as fidelity:
##
##   dropped members  a script the container never yields is never handed to the
##                    compiler, so the "identical" fraction stays 100% while the
##                    game loses a handler. The committed bundle is therefore
##                    walked in the other direction too, and a baseline script no
##                    member accounts for fails.
##   shared mistakes  both sides are measured against the port's own generated
##                    data, not against Director. `porting-fidelity-verification`
##                    applies in full: agreeing with the export proves the swap,
##                    never the behaviour.
##   coverage gaps    86 containers ship under the game root and 75 movie
##                    directories exist under `data/lingo/`. A container with no
##                    bundle still gets its compile coverage measured; it just
##                    has nothing to be compared against, and that is reported
##                    rather than counted as agreement.
##   a contested dir  two different files are called MASTER.CST — 640,786 bytes
##                    at the game root and 483,150 in PIP2DATA — and both would
##                    claim `data/lingo/MASTER/`, which was decompiled from one
##                    of them. Comparing the other against it would invent a few
##                    hundred differences and, keyed on `movie/cast/script`,
##                    would silently merge the two containers' results under one
##                    id. Such a directory is therefore compiled but NOT
##                    compared, and named in the report. Guessing which container
##                    the baseline came from is not this tool's call to make.
##
## Scripts are paired by MEMBER NUMBER, not by name. ProjectorRays keyed a script
## by the member that owns it — "BehaviorScript 207", "CastScript 91 - ex_tx" —
## and `lingo_interpreter.gd:find_script_by_member` matches on the trailing
## number of everything before " - ". Pairing the same way here means a wrong
## script *name* surfaces as a difference at `script`, instead of as a script
## that silently went missing. The name is data the compiler emits; a check that
## paired on it could not fail on it.
##
## Differences at `line` are counted apart from the rest. The container stores
## Lingo with Mac CR line endings and the `.ls` dump has LF, so a compiler that
## mis-counts one form shifts `line` on every node in the corpus. That is one
## bug, and without the split it prints as forty thousand differences and hides
## whatever else is in the list.
##
## `--file` is the shape of the default run and the default target is the boot
## movie from `director_game.cfg`. The corpus sweep costs minutes and is opt-in
## through `--all`, so a mistyped argument narrows the run instead of widening
## it into a sweep nobody reads.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
## Preloaded rather than reached by `class_name`, for the reason
## `tools/director_containers.gd` spells out: a headless `--script` run resolves
## global classes out of `.godot/global_script_class_cache.cfg`, which only lists
## what the editor has already scanned, so a class added since the last editor
## session is "not declared in the current scope" in a file nobody touched.
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")

const LINGO_ROOT := "res://data/lingo"
const DEFAULT_ALLOW_PATH := "res://tools/lingo_compile_check.allow"

## Bundles in a movie directory that are not compiled scripts. Spelled the same
## way `lingo_engine.gd:_load_bundles_for` spells it, so the two cannot drift:
## `JSON.parse_string` is perfectly happy to hand back `attach.json`, and a
## bundle with no `scripts` key would otherwise read as a cast with no scripts.
const NON_SCRIPT_BUNDLES := {"attach.json": true, "sprite_scripts.json": true}

## Director's script types under ProjectorRays' names, which is what the
## committed bundles are keyed by. Member type 11 is a script member; any other
## type that carries source is a member script, which the dump calls CastScript.
## 7 (parent script) is unused by this title and kept because the naming rule is
## Director's, not this game's.
const SCRIPT_MEMBER_TYPE := 11
const SCRIPT_TYPE_NAMES := {1: "BehaviorScript", 3: "MovieScript", 7: "ParentScript"}
const MEMBER_SCRIPT_NAME := "CastScript"

const TYPE_LABELS := {
	TYPE_NIL: "null", TYPE_BOOL: "bool", TYPE_INT: "int", TYPE_FLOAT: "float",
	TYPE_STRING: "String", TYPE_ARRAY: "Array", TYPE_DICTIONARY: "Dictionary",
}


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var max_diffs := Args.number(args, "diffs", 25)
	var allow_path := Args.text(args, "allow", DEFAULT_ALLOW_PATH)
	var allow_file := _read_allow(allow_path)
	var allow: Dictionary = allow_file["entries"]
	var malformed: Array = allow_file["malformed"]

	# --- the comparator can still see what it exists to see ------------------
	# Run before anything is compared. Every other check in this file reports
	# `_diff`'s verdict, so a `_diff` that had stopped distinguishing int from
	# float would make all of them agree loudly about nothing.
	h.begin("the comparator can see an int/float difference")
	var probe_type: Array = []
	_diff({"node": "num", "value": 1}, {"node": "num", "value": 1.0}, "", "", probe_type)
	var probe_ok := probe_type.size() == 1
	var probe_detail := "%d record(s)" % probe_type.size()
	if probe_ok:
		var record: Dictionary = probe_type[0]
		probe_ok = str(record["reason"]) == "type"
		probe_detail = _render(record)
	h.check("int 1 against float 1.0 is one difference at num.value", probe_ok, probe_detail)
	var probe_same: Array = []
	_diff({"node": "num", "value": 1}, {"node": "num", "value": 1}, "", "", probe_same)
	h.check("an identical pair is no difference", probe_same.is_empty(),
		"%d record(s)" % probe_same.size())
	h.complete("the comparator can see an int/float difference")

	h.begin("the allow-list is readable")
	h.check(
		"every allow-list entry carries a reason",
		malformed.is_empty(),
		"" if malformed.is_empty() else "%d line(s) in %s" % [malformed.size(), allow_path],
	)
	for line in malformed:
		print("     unparsed: %s" % str(line))
	h.complete("the allow-list is readable")

	var bundle_dirs := _index_bundle_dirs()
	var targets := _targets(paths, args)
	if targets.is_empty():
		print("nothing to check")
		quit(h.finish("no container selected"))
		return
	print("allow-list : %s (%d entry/entries)" % [allow_path, allow.size()])
	print("containers : %d" % targets.size())
	# Reported, not asserted. Which regime the reader is in decides how to READ a
	# wall of numeric type differences, and neither regime is a fault of this
	# tool — but a run that does not say which one it was in is a run whose
	# numeric result cannot be interpreted six months later.
	print("baseline   : %s" % ("JSON.parse_string preserves int and float"
		if _baseline_keeps_int() else
		"JSON.parse_string widens every number to float, so the interpreter runs "
		+ "float arithmetic on every literal today"))
	print("")

	# --- run -----------------------------------------------------------------
	var contested := _contested(targets, bundle_dirs)
	var results: Array[Dictionary] = []
	for path in targets:
		results.append(_run_container(path, bundle_dirs, contested))

	var sources := 0
	var compiled := 0
	var compared := 0
	var clean := 0
	var with_bundle := 0
	# Differing scripts counted per container, against which the id table's size
	# is checked below. Two containers writing one id would make them disagree.
	var id_records := 0
	var compile_errors: Array[String] = []
	var orphans: Array[String] = []
	var unmatched: Array[String] = []
	var collisions: Array[String] = []
	var no_bundle: Array[String] = []
	var ambiguous: Array[String] = []
	var broken: Array[String] = []
	var diffs: Array = []
	# script id -> difference count, split by whether the allow-list excuses it.
	var offenders: Dictionary = {}
	var allowed: Dictionary = {}
	# Every script id actually compared, so a stale allow-list entry can only be
	# reported for something this run really looked at.
	var visited: Dictionary = {}

	print("%-16s %-24s %6s %6s %6s %6s %6s" % [
		"container", "movie/cast", "src", "ok", "cmp", "same", "diff",
	])
	for result in results:
		var label: String = str(result["container"])
		if str(result["note"]) != "":
			broken.append("%s: %s" % [label, str(result["note"])])
			print("%-16s %s" % [label, str(result["note"])])
			continue
		if not bool(result["has_cast"]):
			# A container with no CAS* is not a cast; that is a fact, not a fault.
			continue
		if bool(result["ambiguous"]):
			# The full path, not the filename: the whole point of this list is
			# that the filenames are identical.
			ambiguous.append("%s (would claim %s)" % [str(result["path"]), str(result["movie"])])
		elif bool(result["has_bundle"]):
			with_bundle += 1
		else:
			no_bundle.append(label)
		var result_diffs: Array = result["diffs"]
		var per_script: Dictionary = result["per_script"]
		sources += int(result["sources"])
		compiled += int(result["compiled"])
		compared += int(result["compared"])
		clean += int(result["clean"])
		compile_errors.append_array(result["compile_errors"])
		orphans.append_array(result["orphans"])
		unmatched.append_array(result["unmatched"])
		collisions.append_array(result["collisions"])
		diffs.append_array(result_diffs)
		for id in result["visited"]:
			visited[str(id)] = true
		id_records += per_script.size()
		for id in per_script:
			var key := str(id)
			if allow.has(key):
				allowed[key] = int(per_script[id])
			else:
				offenders[key] = int(per_script[id])
		print("%-16s %-24s %6d %6d %6d %6d %6d" % [
			label, "%s/%s" % [str(result["movie"]), str(result["cast"])],
			int(result["sources"]), int(result["compiled"]), int(result["compared"]),
			int(result["clean"]), result_diffs.size(),
		])
	print("")

	# --- every script the containers hold reaches the compiler ---------------
	h.begin("every script the containers hold reaches the compiler")
	h.check(
		"all %d container(s) opened" % targets.size(),
		broken.is_empty(),
		"" if broken.is_empty() else "%d failed" % broken.size(),
	)
	# `sources > 0` is part of the assertion, not a guard around it: a selection
	# that reaches no Lingo at all would otherwise report 0/0 and pass, which is
	# the shape of every check this repo has had to delete.
	var compile_detail := ""
	if not compile_errors.is_empty():
		compile_detail = "%d failure(s)" % compile_errors.size()
	elif sources == 0:
		compile_detail = "no member in the selection carries Lingo source"
	h.check(
		"%d/%d source members compile" % [compiled, sources],
		compile_errors.is_empty() and sources > 0,
		compile_detail,
	)
	for line in compile_errors.slice(0, max_diffs):
		print("     %s" % line)
	h.complete("every script the containers hold reaches the compiler")

	# --- every compiled AST matches the committed bundle ---------------------
	h.begin("every compiled AST matches the committed bundle")
	# A selection whose containers all have a bundle must actually compare
	# something. Without this, a pairing rule that stopped matching anything
	# reports "0/0 identical" and passes, which is the failure mode `harness.gd`
	# was written for in the first place.
	h.check(
		"the pairing rule matched scripts to compare",
		compared > 0 or with_bundle <= 0,
		"%d compared across %d container(s) holding a bundle" % [compared, with_bundle],
	)
	# `movie/cast/script` has to address one script and no other, or a divergence
	# is quietly overwritten by another container's and one allow-list entry
	# excuses two scripts. This is the invariant `_contested` was written for, and
	# it is asserted rather than assumed because the way it broke — two files
	# named MASTER.CST — is not visible from anything else this tool prints.
	h.check(
		"every compared script has an id of its own",
		offenders.size() + allowed.size() == id_records,
		"%d id(s) for %d differing script(s)" % [offenders.size() + allowed.size(), id_records],
	)
	h.check(
		"%d/%d compared scripts identical" % [clean, compared],
		offenders.is_empty(),
		"" if offenders.is_empty() else "%d script(s) differ" % offenders.size(),
	)
	var shown := 0
	for diff in diffs:
		var record: Dictionary = diff
		if allow.has(str(record["id"])):
			continue
		if shown >= max_diffs:
			break
		shown += 1
		print("     %s" % _render(record))
	if not offenders.is_empty() and shown < diffs.size():
		print("     ... %d more, raise --diffs to see them" % (diffs.size() - shown))
	# Reported apart, never averaged in: an allowed divergence is a decision
	# somebody wrote down, and folding it into the pass count erases the decision.
	if not allowed.is_empty():
		print("")
		print("allowed divergences (%d):" % allowed.size())
		for id in allowed:
			print("     %-52s %d diff(s)  %s" % [str(id), int(allowed[id]), str(allow[id])])
	h.complete("every compiled AST matches the committed bundle")

	# --- nothing quietly went missing on either side -------------------------
	h.begin("the container and the bundle hold the same scripts")
	h.check(
		"no committed script is unaccounted for",
		orphans.is_empty(),
		"" if orphans.is_empty() else "%d script(s) with no member" % orphans.size(),
	)
	for line in orphans.slice(0, max_diffs):
		print("     %s" % line)
	h.check(
		"no bundle key claims a member twice",
		collisions.is_empty(),
		"" if collisions.is_empty() else "%d collision(s)" % collisions.size(),
	)
	for line in collisions.slice(0, max_diffs):
		print("     %s" % line)
	h.complete("the container and the bundle hold the same scripts")

	# --- the allow-list is not carrying dead weight --------------------------
	var stale: Array[String] = []
	for id in allow:
		var key := str(id)
		if visited.has(key) and not allowed.has(key):
			stale.append(key)
	h.begin("the allow-list only excuses live divergences")
	h.check(
		"no allow-list entry is stale",
		stale.is_empty(),
		"" if stale.is_empty() else "%d entry/entries now match" % stale.size(),
	)
	for id in stale:
		print("     %s: %s" % [id, str(allow[id])])
	h.complete("the allow-list only excuses live divergences")

	_report(diffs, unmatched, no_bundle, ambiguous, max_diffs)
	quit(h.finish("the GDScript compiler reproduces the committed ASTs"))


# ---------------------------------------------------------------- targets


## One container by default. `--all` is the only way to widen the run, and
## `--file` beats it when both are given: a corpus sweep that happens because an
## argument was misspelled is a sweep whose result nobody trusts.
func _targets(paths, args: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var wanted := Args.text(args, "file")
	if wanted == "" and Args.flag(args, "all"):
		_walk(str(paths.root), out)
		out.sort()
		return out
	if wanted == "":
		wanted = str(paths.boot_movie)
	var path: String = paths.resolve(wanted)
	if path == "":
		print("no such container: %s" % wanted)
		return out
	out.append(path)
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(str(entry).get_extension().to_lower()):
			out.append(dir_path.path_join(str(entry)))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(str(sub)), out)


# ---------------------------------------------------------------- one container


## Bundle directories more than one selected container would claim, as a set.
##
## The baseline is addressed by the container's stem, and this game ships two
## unrelated files called MASTER.CST (640,786 bytes at the root, 483,150 in
## PIP2DATA). `data/lingo/MASTER/` came from one of them. Left alone, the other
## is compared against a baseline that is not its own, and because ids are
## `movie/cast/script` the two containers' results land on the same key: the
## corpus sweep reported 3307 scripts compared and only 3267 distinct ids, so 40
## results were being overwritten in silence. Neither is compared now.
func _contested(targets: Array[String], bundle_dirs: Dictionary) -> Dictionary:
	var claimants: Dictionary = {}
	for path in targets:
		var dir_name := str(bundle_dirs.get(path.get_file().get_basename().to_lower(), ""))
		if dir_name == "":
			continue
		claimants[dir_name] = int(claimants.get(dir_name, 0)) + 1
	var out: Dictionary = {}
	for dir_name in claimants:
		if int(claimants[dir_name]) > 1:
			out[str(dir_name)] = true
	return out


func _run_container(path: String, bundle_dirs: Dictionary, contested: Dictionary) -> Dictionary:
	var stem := path.get_file().get_basename()
	var compile_errors: Array[String] = []
	var orphans: Array[String] = []
	var unmatched: Array[String] = []
	var collisions: Array[String] = []
	var diffs: Array = []
	var visited: Array[String] = []
	var per_script: Dictionary = {}
	var result := {
		"container": path.get_file(), "path": path, "movie": stem, "cast": "-", "note": "",
		"has_cast": false, "has_bundle": false, "ambiguous": false,
		"sources": 0, "compiled": 0, "compared": 0, "clean": 0,
		"compile_errors": compile_errors, "orphans": orphans, "unmatched": unmatched,
		"collisions": collisions, "diffs": diffs, "visited": visited,
		"per_script": per_script,
	}

	var f := ContainerFile.new()
	if not f.open(path):
		result["note"] = str(f.error)
		return result
	var c := Cast.new()
	if not c.open(f):
		f.close()
		return result
	result["has_cast"] = true

	var dir_name := str(bundle_dirs.get(stem.to_lower(), ""))
	var baseline: Dictionary = {}
	if dir_name != "" and contested.has(dir_name):
		# Compiled below all the same — coverage over these scripts is real. Only
		# the comparison is withheld, because there is no way to know which of the
		# claimants the bundle was decompiled from.
		result["movie"] = dir_name
		result["ambiguous"] = true
	elif dir_name != "":
		var loaded := _load_baseline(dir_name)
		baseline = loaded["scripts"]
		result["movie"] = dir_name
		result["cast"] = str(loaded["cast"])
		collisions.append_array(loaded["collisions"])
		result["has_bundle"] = not baseline.is_empty()

	# The baseline indexed the way the interpreter indexes it, so this harness
	# pairs the same scripts `find_script_by_member` would pair at runtime.
	var by_member: Dictionary = {}
	for script_name in baseline:
		var number := _member_of(str(script_name))
		if number <= 0:
			continue
		if by_member.has(number):
			collisions.append("%s/%s: %s and %s both name member %d" % [
				dir_name, str(result["cast"]), str(by_member[number]), str(script_name), number,
			])
			continue
		by_member[number] = str(script_name)

	var seen: Dictionary = {}
	for number in c.member_numbers():
		var m: Dictionary = c.member(int(number))
		if m.is_empty():
			continue
		var source := str(m.get("source", ""))
		if source.strip_edges() == "":
			continue
		result["sources"] = int(result["sources"]) + 1
		var script_name := _script_name(m, int(number))
		var id := "%s/%s/%s" % [str(result["movie"]), str(result["cast"]), script_name]
		# A fresh compiler per script. `error` and `error_line` are per-call
		# state and nothing in the API promises they are reset, so reusing one
		# instance would let a stale message describe the wrong script.
		var compiler := Compiler.new()
		var ast: Dictionary = compiler.compile_source(source, script_name)
		if ast.is_empty():
			compile_errors.append("%s: line %d: %s" % [
				id, int(compiler.error_line), str(compiler.error),
			])
			continue
		result["compiled"] = int(result["compiled"]) + 1
		if not by_member.has(int(number)):
			unmatched.append(id)
			continue
		seen[int(number)] = true
		result["compared"] = int(result["compared"]) + 1
		visited.append(id)
		var want: Variant = baseline[str(by_member[int(number)])]
		var found: Array = []
		_diff(want, ast, "", "", found)
		if found.is_empty():
			result["clean"] = int(result["clean"]) + 1
			continue
		per_script[id] = found.size()
		for entry in found:
			# Dictionaries are references, so stamping the local stamps the one
			# already in `found` — no copy, and the id travels with the record.
			var record: Dictionary = entry
			record["id"] = id
			diffs.append(record)

	# The other direction. Without it a cast reader that drops members scores a
	# perfect run: the compiler is never asked, so it never disagrees.
	for number in by_member:
		if not seen.has(number):
			orphans.append("%s/%s/%s" % [
				str(result["movie"]), str(result["cast"]), str(by_member[number]),
			])
	f.close()
	return result


# ---------------------------------------------------------------- the baseline


## Lowercased directory name -> the real spelling. `reference/lingo/` named its
## directories after the container it decompiled and kept that file's own case,
## so the corpus holds `DAY1` beside `strtgame`. Building the path from the
## container's spelling and trusting the filesystem to find it works on Windows
## and breaks on Android — the trap `director_paths.gd:resolve` exists to avoid.
func _index_bundle_dirs() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(LINGO_ROOT)
	if dir == null:
		return out
	for name in dir.get_directories():
		out[str(name).to_lower()] = str(name)
	return out


## Every compiled bundle in a movie's directory, merged. Loaded the way the
## engine loads it, non-script bundles skipped by the same names, because the
## question is what the interpreter would be handed and not what is on disk.
func _load_baseline(dir_name: String) -> Dictionary:
	var scripts: Dictionary = {}
	var casts: Array[String] = []
	var collisions: Array[String] = []
	var out := {"cast": "-", "scripts": scripts, "collisions": collisions}
	var dir := DirAccess.open("%s/%s" % [LINGO_ROOT, dir_name])
	if dir == null:
		return out
	for entry in dir.get_files():
		var file := str(entry)
		if not file.ends_with(".json") or NON_SCRIPT_BUNDLES.has(file):
			continue
		var text := FileAccess.get_file_as_string("%s/%s/%s" % [LINGO_ROOT, dir_name, file])
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var bundle: Dictionary = parsed
		var by_name: Variant = bundle.get("scripts", {})
		if typeof(by_name) != TYPE_DICTIONARY:
			continue
		var table: Dictionary = by_name
		casts.append(str(bundle.get("cast", file.get_basename())))
		for key in table:
			var script_name := str(key)
			if scripts.has(script_name):
				collisions.append("%s/%s: %s defined twice" % [dir_name, file, script_name])
				continue
			scripts[script_name] = table[key]
	# One bundle per movie directory across this corpus; the join is for the day
	# a movie links a second cast, so the id stays honest instead of guessing.
	var cast_name: String = casts[0] if casts.size() == 1 else "+".join(casts)
	out["cast"] = cast_name if cast_name != "" else "-"
	return out


## Which numeric regime the baseline reader is in. False on Godot 4.7.1, which
## widens every JSON number to float — so `num.value` reads back as 1.0 for every
## literal the Python wrote as 1, and float arithmetic is what the game runs. It
## is asked so the run can SAY so; it never changes what is compared. Suppressing
## numeric type differences because the reader cannot produce ints would delete
## the one comparison this file exists for, on the build where it matters most.
func _baseline_keeps_int() -> bool:
	var probe: Variant = JSON.parse_string("{\"i\": 1, \"f\": 1.5}")
	if typeof(probe) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = probe
	return typeof(d.get("i")) == TYPE_INT and typeof(d.get("f")) == TYPE_FLOAT


# ---------------------------------------------------------------- naming


## The member number a bundle key names. `lingo_interpreter.gd`'s
## `find_script_by_member` reads the same field the same way — everything before
## " - ", trailing number — and if this drifts from that, the harness compares
## pairs the engine would never pair and reports on scripts nobody runs.
func _member_of(script_name: String) -> int:
	var parts := script_name.split(" - ")
	var head: String = parts[0]
	var cut := head.rfind(" ")
	if cut < 0:
		return -1
	var tail: String = head.substr(cut + 1)
	if not tail.is_valid_int():
		return -1
	return int(tail)


## ProjectorRays' key for a member's script, rebuilt from the container. It goes
## into the AST as `script`, so getting it wrong shows up as a difference at
## `script` rather than as a missing script — see the header on why pairing is by
## member number. A type-11 member with a script type this table does not know
## falls through to CastScript, which is wrong on purpose: the diff names it.
func _script_name(m: Dictionary, number: int) -> String:
	var head := MEMBER_SCRIPT_NAME
	if int(m.get("type", 0)) == SCRIPT_MEMBER_TYPE:
		head = str(SCRIPT_TYPE_NAMES.get(int(m.get("script_type", 0)), MEMBER_SCRIPT_NAME))
	var out := "%s %d" % [head, number]
	var member_name := str(m.get("name", "")).strip_edges()
	if member_name != "":
		out += " - %s" % member_name
	return out


# ---------------------------------------------------------------- the compare


## Structural comparison of the parsed baseline against the compiled AST.
##
## `kind` is the `node` of the nearest enclosing AST node, carried down so a
## difference deep inside an expression can still be attributed to the node kind
## that produced it. It comes from the baseline, which is the side that is right
## by definition here.
func _diff(want: Variant, got: Variant, path: String, kind: String, out: Array) -> void:
	var want_type := typeof(want)
	var got_type := typeof(got)
	if want_type != got_type:
		# int against float is recorded as its own reason and never folded into
		# "value": `lingo_value.gd` branches on it, so 1 and 1.0 are a difference
		# in behaviour while comparing equal as numbers. No tolerance here, ever.
		out.append(_note(path, kind, "type",
			"%s %s" % [_label(want_type), _brief(want)],
			"%s %s" % [_label(got_type), _brief(got)]))
		return
	match want_type:
		TYPE_DICTIONARY:
			var want_dict: Dictionary = want
			var got_dict: Dictionary = got
			var here := kind
			if want_dict.has("node"):
				here = str(want_dict["node"])
			for key in want_dict:
				var child := _step(path, str(key))
				if not got_dict.has(key):
					out.append(_note(child, here, "missing", _brief(want_dict[key]), "-"))
					continue
				_diff(want_dict[key], got_dict[key], child, here, out)
			for key in got_dict:
				if not want_dict.has(key):
					out.append(_note(_step(path, str(key)), here, "extra",
						"-", _brief(got_dict[key])))
		TYPE_ARRAY:
			var want_arr: Array = want
			var got_arr: Array = got
			if want_arr.size() != got_arr.size():
				out.append(_note(path, kind, "length",
					str(want_arr.size()), str(got_arr.size())))
			var shared: int = mini(want_arr.size(), got_arr.size())
			for i in shared:
				_diff(want_arr[i], got_arr[i], "%s[%d]" % [path, i], kind, out)
		_:
			if want != got:
				out.append(_note(path, kind, "value", _brief(want), _brief(got)))


func _step(path: String, key: String) -> String:
	return key if path == "" else "%s.%s" % [path, key]


func _note(path: String, kind: String, reason: String, want: String, got: String) -> Dictionary:
	return {
		"path": path if path != "" else "<root>",
		"kind": kind if kind != "" else "<root>",
		"reason": reason, "want": want, "got": got, "id": "",
	}


## Short enough to sit on one line. Note that Godot prints 1.0 as "1", which is
## why `_diff` puts the type label in front of the value: on a numeric type
## difference the number is identical and the label is the entire message.
func _brief(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_STRING:
			return JSON.stringify(value)
		TYPE_DICTIONARY:
			var d: Dictionary = value
			return "{%s, %d key(s)}" % [str(d.get("node", "?")), d.size()]
		TYPE_ARRAY:
			var a: Array = value
			return "[%d item(s)]" % a.size()
	return str(value)


func _label(type_code: int) -> String:
	return str(TYPE_LABELS.get(type_code, "type%d" % type_code))


## `movie/cast/script/<path>`, which is the address asked for in a report. The id
## is empty only for the comparator's own self-test, which has no script.
func _render(record: Dictionary) -> String:
	var id := str(record["id"])
	var where := str(record["path"])
	if id != "":
		where = "%s/%s" % [id, where]
	return "%s  %s: %s vs %s" % [
		where, str(record["reason"]), str(record["want"]), str(record["got"]),
	]


# ---------------------------------------------------------------- reporting


func _report(diffs: Array, unmatched: Array, no_bundle: Array, ambiguous: Array,
		limit: int) -> void:
	print("")
	if not ambiguous.is_empty():
		# Compiled, deliberately not compared. See `_contested`.
		print("compiled but NOT compared, two containers claim one bundle (%d):" % ambiguous.size())
		for line in ambiguous:
			print("     %s" % str(line))
	if not unmatched.is_empty():
		# Not a failure: `reference/lingo/` was merged from two ProjectorRays runs
		# over the original DXRs, and the DIRs under the game root are not those
		# files. A script only one side has is a fact to look at, not a verdict.
		print("compiled with no committed counterpart (%d):" % unmatched.size())
		for line in unmatched.slice(0, limit):
			print("     %s" % str(line))
	if not no_bundle.is_empty():
		print("containers with no bundle under %s (%d): %s" % [
			LINGO_ROOT, no_bundle.size(), ", ".join(no_bundle),
		])
	if diffs.is_empty():
		return

	var by_kind: Dictionary = {}
	var by_reason: Dictionary = {}
	var on_line := 0
	for diff in diffs:
		var record: Dictionary = diff
		var kind := str(record["kind"])
		var reason := str(record["reason"])
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
		by_reason[reason] = int(by_reason.get(reason, 0)) + 1
		if str(record["path"]).ends_with("line"):
			on_line += 1

	print("")
	print("differences by AST node kind:")
	var kinds := by_kind.keys()
	kinds.sort_custom(func(a, b): return int(by_kind[a]) > int(by_kind[b]))
	for key in kinds:
		print("  %8d  %s" % [int(by_kind[key]), str(key)])
	print("by reason:")
	var reasons := by_reason.keys()
	reasons.sort_custom(func(a, b): return int(by_reason[a]) > int(by_reason[b]))
	for key in reasons:
		print("  %8d  %s" % [int(by_reason[key]), str(key)])
	# Counted apart because a line-ending bug shifts every node in the corpus and
	# would otherwise drown the list it is sitting in.
	print("  %8d  of the above are at `line` (%.1f%%)" % [
		on_line, 0.0 if diffs.is_empty() else on_line * 100.0 / diffs.size(),
	])


# ---------------------------------------------------------------- allow-list


## `<movie>/<cast>/<script>` then two spaces or a tab, then why it diverges:
##
##     # anything after a leading # is a comment
##     DAY1/wonder/CastScript 91 - ex_tx    ProjectorRays sanitised the name
##
## Two spaces rather than one, because script names contain single spaces
## ("BehaviorScript 103 - play done") and splitting on one would cut the id in
## half and silently excuse nothing.
##
## The reason is required. An allow-list entry nobody had to justify is a
## divergence that stops being looked at, and a missing file is zero entries
## rather than an error: the empty allow-list is the goal state, and the tool has
## to run in it.
func _read_allow(path: String) -> Dictionary:
	var entries: Dictionary = {}
	var malformed: Array[String] = []
	var out := {"entries": entries, "malformed": malformed}
	if not FileAccess.file_exists(path):
		return out
	var text := FileAccess.get_file_as_string(path)
	for raw in text.split("\n"):
		var body := str(raw).replace("\t", "  ").strip_edges()
		if body == "" or body.begins_with("#"):
			continue
		var cut := body.find("  ")
		if cut < 0:
			malformed.append(body)
			continue
		var id := body.substr(0, cut).strip_edges()
		var reason := body.substr(cut + 2).strip_edges().lstrip("#").strip_edges()
		if id == "" or reason == "":
			malformed.append(body)
			continue
		entries[id] = reason
	return out
