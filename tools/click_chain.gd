extends SceneTree
## §6.3's event chain for the mouse: is the whole chain **queued before any of it
## runs**, and does each element honour `pass` / `dontPassEvent`?
##
##   godot --headless --path . --script tools/click_chain.gd
##   godot --headless --path . --script tools/click_chain.gd -- --file PIP2DATA/ISLAND2.dir
##   godot --headless --path . --script tools/click_chain.gd -- --root rating
##   godot --headless --path . --script tools/click_chain.gd -- --survey
##
## `tools/key_chain.gd` is this file's sibling and asserts the same two rules for
## the keyboard. They were fixed a fortnight apart and the mouse half was the one
## left behind: §8.2's flag was honoured on the key chain and inert on the mouse
## chain, because the mouse tiers stopped at the first handler that answered and
## there was nothing further along to suppress.
##
## **The two things that were wrong**, and they had to be fixed together:
##
## *The chain was resolved lazily.* `interaction.gd:script_for_click` took the
## sprite's behaviour *or*, only if there was none, the member's cast script, and
## `call_handler` then ran that one script or fell through to a movie script.
## Director queues all five tiers up front -- primary, sprite, cast, frame, movie
## -- with `passByDefault` true for the first and false for the rest, resets the
## flag to each element's own default before running it, and skips the next
## element only when the previous one *found a script* and left the flag false
## (`lingo-events.cpp`, `queueEvent` and `processEvents`). So a behaviour that
## declared only `mouseDown` shadowed its member's `mouseUp` completely, and a
## behaviour that said `pass` was talking to nobody.
##
## *`pass` was dropped.* `ISLAND2/External/BehaviorScript 325` is three lines --
## `on mouseUp / pass() / end` -- a sprite whose entire purpose is to hand the
## click to the tier below it, and which was therefore a dead zone. The decompile
## hides these: ProjectorRays renders bare `pass` as `pass()` and `dontPassEvent`
## as `dont(pass)`, so a token grep for either name finds 0 where the real count
## is 6.
##
## **Landing one without the other is a regression rather than progress**, and
## the failure is loud in opposite directions: the queue without the flag leaks
## every event to every tier, and the flag without the queue changes nothing. So
## this harness measures **how many handlers ran**, not only whether the right
## one did -- a chain that suddenly runs three where it ran one is either the fix
## working or the flag being ignored, and only the count tells you which.
##
## **The subject is a real sprite with a synthetic script.** The rules are the
## engine's rather than a title's, and no movie in `games/` has a behaviour, a
## cast script and a movie script all declaring `mouseUp` on one channel where a
## harness could reach them. So a clickable sprite is found in whatever movie is
## configured, and its behaviour, its member's cast script and a movie script are
## replaced with counters compiled by the port's own compiler -- which is what
## makes this run identically against any `--root`. The corpus's own `pass` and
## `dontPassEvent` sites are then *reported*, because what they prove is that the
## rule matters here, not that it is implemented.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const EventChain := preload("res://scenes/preview/event_chain.gd")
const Boot := preload("res://scenes/preview/boot.gd")

## The five tiers, as counters. Named so that nothing in any title can collide.
##
## Each variant is compiled into the *place* a tier lives -- the behaviour the
## score attaches to a channel, the cast script of the member that channel shows,
## a movie script -- rather than being called directly, because what is under
## test is the routing and not the handlers.
const SPRITE_CONSUMES := """
on mouseUp
  global ccsprite
  set ccsprite to ccsprite + 1
end
"""

const SPRITE_PASSES := """
on mouseUp
  global ccsprite
  set ccsprite to ccsprite + 1
  pass()
end
"""

## A behaviour that answers the press and says nothing about the release. This is
## the shape that used to shadow a cast member's `mouseUp` entirely: the old
## resolution picked the behaviour because it existed, then found no `mouseUp` in
## it and fell straight through to the movie scripts, skipping the cast script
## and the frame script on the way.
const SPRITE_DOWN_ONLY := """
on mouseDown
  global ccdown
  set ccdown to ccdown + 1
end
"""

## The §15 subject: a press that swaps the member under itself. Director latched
## the member at the start of the mouse-down chain, so the **old** member's cast
## script still answers the `mouseUp`.
const SPRITE_SWAPS := """
on mouseDown
  global ccdown, ccswapto
  set ccdown to ccdown + 1
  set the memberNum of sprite the clickOn to ccswapto
end
"""

const CAST_CONSUMES := """
on mouseUp
  global cccast
  set cccast to cccast + 1
end
"""

const CAST_PASSES := """
on mouseUp
  global cccast
  set cccast to cccast + 1
  pass()
end
"""

## The cast script of the member a press swaps *to*. It must never run: §15 says
## the release belongs to the member the chain started on.
const CAST_SWAPPED_IN := """
on mouseUp
  global ccswapped
  set ccswapped to ccswapped + 1
end
"""

const MOVIE_SCRIPT := """
on mouseUp
  global ccmovie
  set ccmovie to ccmovie + 1
end
"""

## A tier-1 primary handler that refuses to pass. Reached through
## `the mouseUpScript`, which is a real §6.3 tier-1 path and the only one a
## harness can install without reaching into the interpreter's tables.
const PRIMARY_STOPS := """
on ccstop
  global ccprimary
  set ccprimary to ccprimary + 1
  dontPassEvent
end

on ccgo
  global ccprimary
  set ccprimary to ccprimary + 1
end
"""

var _compiler = Compiler.new()


func _count(host, name: String) -> int:
	return int(host.get_global(name))


func _zero(host) -> void:
	for name in ["ccsprite", "cccast", "ccframe", "ccmovie", "ccdown",
			"ccprimary", "ccswapped"]:
		host.set_global(name, 0)


## Compile `source` and register it under `key` in `cast`, replacing whatever was
## there. `LingoInterpreter.load_bundle` writes into the cast's own name table,
## so reusing an existing script key is how a real attachment -- a score interval
## pointing at member 325 of a named cast -- is given a body this harness wrote.
func _install(interp, cast: String, key: String, source: String) -> bool:
	var ast: Dictionary = _compiler.compile_source(source, key)
	if ast.is_empty():
		print("compile failed for %s: %s" % [key, _compiler.error])
		return false
	interp.load_bundle({"movie": "clickchain", "cast": cast, "scripts": {key: ast}})
	return true


## The sprite-behaviour interval covering `channel` on `frame`, or `{}`.
func _interval(score, channel: int, frame: int) -> Dictionary:
	for value in score.intervals():
		var interval: Dictionary = value
		if str(interval["kind"]) != "sprite" or int(interval["channel"]) != channel:
			continue
		if frame < int(interval["start"]) or frame > int(interval["end"]):
			continue
		return interval
	return {}


## A frame, a channel and a point where a click reaches that channel and the
## score attaches a behaviour to it.
##
## Asked of `_channel_at` rather than of `responds_to_mouse`, so the subject is a
## sprite a *click* actually lands on and not merely one that would answer if it
## were reachable. Everything the assertions need is carried out: the behaviour's
## cast and script key so it can be replaced, and the member so its cast script
## can be written.
func _subject(preview: Node) -> Dictionary:
	var score = preview.get("_score")
	if score == null:
		return {}
	for index in int(score.frame_count):
		preview.set("_index", index)
		var sprites: Array = score.frame(index).get("sprites", [])
		for i in range(sprites.size() - 1, -1, -1):
			var raw: Dictionary = sprites[i]
			var channel := int(raw["channel"])
			var interval := _interval(score, channel, index)
			if interval.is_empty() or int(interval["script_member"]) <= 0:
				continue
			var live: Dictionary = preview.call("_effective", raw)
			if live.is_empty():
				continue
			var rect: Rect2 = preview.call("_sprite_rect", live)
			if rect.size.x <= 2.0 or rect.size.y <= 2.0:
				continue
			var at: Vector2 = rect.get_center()
			if int(preview.call("_channel_at", at)) != channel:
				continue
			var behaviour: Dictionary = preview.call("_sprite_script", channel, index)
			if behaviour.is_empty():
				continue
			var lib_keys: Dictionary = preview.get("_lib_keys")
			var script_lib := int(interval["script_cast_lib"])
			if script_lib <= 0 or script_lib == 0xFFFF:
				script_lib = 1
			if not lib_keys.has(script_lib) or not lib_keys.has(int(live["cast_lib"])):
				continue
			return {
				"frame": index, "channel": channel, "at": at,
				"script_cast": str(lib_keys[script_lib]),
				"script_key": str(behaviour.get("script", "")),
				"member_lib": int(live["cast_lib"]),
				"member_id": int(live["cast_id"]),
				"member_cast": str(lib_keys[int(live["cast_lib"])]),
			}
	return {}


## A member number this channel can be swapped to without moving out from under
## the pointer.
##
## The swap is the point of the §15 case and the rect is collateral: a different
## member is usually a different size, and a sprite that shrinks away from the
## click point gets `mouseUpOutSide` instead of `mouseUp` -- which would fail the
## case for a reason that has nothing to do with the chain. So candidates are
## tried against the real geometry and the first that keeps the point inside
## wins. 0 means there is none, and the case says so rather than passing empty.
##
## A candidate the title *already* has a script for is skipped as well.
## `find_script_by_member` answers the first script in the cast whose number
## matches, and a real one registered before this harness runs wins over the one
## written here -- so the case would then assert that a cast script it could not
## reach did not run, which is true of any number at all. Piposh 1's first
## subject picks that up: member 1 of its cast already carries `BehaviorScript 1`.
func _swap_target(preview: Node, subject: Dictionary) -> int:
	var channel := int(subject["channel"])
	var original := int(subject["member_id"])
	for candidate in range(1, 400):
		if candidate == original:
			continue
		if not (preview.call("_script_in_lib",
				int(subject["member_lib"]), candidate) as Dictionary).is_empty():
			continue
		preview.call("lingo_set_sprite_prop", channel, "membernum", candidate)
		var ok := false
		for raw in (preview.get("_score") as Object).call(
				"frame", int(subject["frame"])).get("sprites", []):
			if int((raw as Dictionary)["channel"]) != channel:
				continue
			var live: Dictionary = preview.call("_effective", raw)
			if live.is_empty():
				break
			ok = (preview.call("_sprite_rect", live) as Rect2).has_point(subject["at"])
			break
		preview.call("lingo_set_sprite_prop", channel, "membernum", original)
		if ok:
			return candidate
	return 0


## One click on the subject, with the counters zeroed first. Returns the tiers
## the `mouseUp` chain actually ran, in order, as a printable string.
##
## **This is the measurement, not decoration.** "The right handler ran" and "only
## the right handler ran" are different claims, and a queue landed without the
## pass flag satisfies the first while failing the second -- every event reaching
## every tier looks, from a counter on one handler, exactly like the fix working.
## So every case below prints what the whole chain did.
func _click(preview: Node, host, subject: Dictionary) -> String:
	_zero(host)
	preview.set("_index", int(subject["frame"]))
	var before := _chain_tallies(preview, "mouseUp")
	preview.call("route_press", subject["at"])
	preview.call("route_release", subject["at"])
	return _chain_delta(preview, "mouseUp", before)


## `_ran` for every tier of one handler: `{"": total, "sprite": n, ...}`.
func _chain_tallies(preview: Node, handler: String) -> Dictionary:
	var ran: Dictionary = preview.get("_ran")
	var out: Dictionary = {"": int(ran.get(handler, 0))}
	for tier in ["sprite", "cast", "frame", "movie"]:
		out[tier] = int(ran.get("%s@%s" % [handler, tier], 0))
	return out


func _chain_delta(preview: Node, handler: String, before: Dictionary) -> String:
	var now := _chain_tallies(preview, handler)
	var tiers: Array[String] = []
	for tier in ["sprite", "cast", "frame", "movie"]:
		var delta := int(now[tier]) - int(before[tier])
		if delta > 0:
			tiers.append(tier if delta == 1 else "%s x%d" % [tier, delta])
	return "%d handler(s): %s" % [
		int(now[""]) - int(before[""]),
		"nothing" if tiers.is_empty() else " -> ".join(tiers)]


func _tally(preview: Node, which: String, key: String) -> int:
	return int((preview.get(which) as Dictionary).get(key, 0))


## Every `pass` and `dontPassEvent` in the decompiled Lingo beside the repo.
##
## Counted on the shapes ProjectorRays emits rather than on the Lingo keywords,
## which is the whole trap: `pass()` and `dont(pass)` are what the decompile
## contains, so `grep -w pass` answers 0 for a corpus with six real sites. The
## reference tree covers one title; the count is reported for what it is.
func _pass_sites(dir_path: String, found: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if entry.get_extension().to_lower() != "ls":
			continue
		var text := FileAccess.get_file_as_string(dir_path.path_join(entry))
		var passes := text.count("pass()")
		var stops := text.count("dont(pass)")
		if passes > 0 or stops > 0:
			found["%s/%s" % [dir_path.get_file(), entry.get_basename()]] = [passes, stops]
	for sub in dir.get_directories():
		_pass_sites(dir_path.path_join(sub), found)


## Does `script` declare `key`? Asked of the interpreter, so the survey below
## cannot answer differently from the dispatcher.
##
## **The receiver is spelled out rather than abbreviated, and that is not
## style.** `tools/preview_surface.gd` scrapes `<receiver>.call(` out of every
## file in `tools/` to build the list of node methods it asserts, and one of the
## four receivers it looks for is the single letter `p` -- which is a *substring*
## of any name ending in one, `interp` included. A reflective call through such a
## local is scraped as though it were a call on the preview node, and the surface
## check then fails for a method that was never on the node and never moved. The
## same trap catches this comment, so it does not spell the pattern out either.
func _declares(interpreter, script: Dictionary, key: String) -> bool:
	if interpreter == null or script.is_empty():
		return false
	return bool(interpreter.call("_script_has_handler", script, key))


## Does `script`'s `key` handler say anything about propagation? `"pass"`,
## `"stop"` or `""`.
##
## This is the half of the measurement that "which tier answers" cannot see. The
## tier a click resolves to is the same under both rules almost everywhere; what
## changes is what happens *after* it, and only a handler that calls `pass` makes
## the chain run a second element at all. So the interesting number is not how
## many clicks moved, it is how many now run more than one handler.
##
## A walk of the compiled tree rather than of the source text, because the source
## is what hides these: ProjectorRays writes `pass()` and `dont(pass)`, so the
## names never appear as bare tokens. The parser resolves both into calls, and a
## call is what this looks for.
func _propagation(script: Dictionary, key: String) -> String:
	for value in script.get("handlers", []):
		var handler: Dictionary = value
		if str(handler.get("name", "")).to_lower() != key:
			continue
		var names: Dictionary = {}
		_names_in(handler.get("body", []), names)
		if names.has("dontpassevent") or names.has("stopevent"):
			return "stop"
		if names.has("pass"):
			return "pass"
		return ""
	return ""


## Every identifier named anywhere inside a statement tree, lowercased.
##
## Deliberately blunt: the three statements this is looking for reach the
## interpreter as a call, a bare-identifier read or a command, depending on how
## they were written, and a walk that knew which would have to be kept in step
## with the parser. A name that appears is a name the handler mentions, which for
## these three is the same thing as calling them -- nothing in Lingo has a
## variable called `dontPassEvent`.
func _names_in(node: Variant, out: Dictionary) -> void:
	match typeof(node):
		TYPE_ARRAY:
			for item in (node as Array):
				_names_in(item, out)
		TYPE_DICTIONARY:
			var dict := node as Dictionary
			if dict.has("name") and typeof(dict["name"]) == TYPE_STRING:
				out[str(dict["name"]).to_lower()] = true
			for k in dict.keys():
				if k != "name":
					_names_in(dict[k], out)


## Every container under a directory, for the survey.
func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


## Which tier answers a click, under the old rule and under the queue, for every
## clickable sprite in a whole title. `--survey`.
##
## **This is a model of both rules, not a reading of the engine**, and that is
## the only honest way to print a "before" column after the change has landed:
## the two resolutions are six lines each and they are written here side by side
## from the *engine's own lookups* -- `_sprite_script`, `_script_in_lib`,
## `_frame_script` and the interpreter's movie table -- so the only thing modelled
## is the selection, and the data both columns select from is the real thing.
## Read `porting-fidelity-verification` before believing the numbers; the
## assertions above are what proves the engine, and this says how much of the
## corpus the difference reaches.
##
## Counted per *sprite occurrence* -- one row per (frame, channel) a click can
## land on -- because that is the unit a player can reach. A cold score read, so
## no puppet state and no `moveable` a script has set: identical in both columns,
## which is what a differential measurement needs.
func _survey(preview: Node, handler: String, root_path: String) -> void:
	var targets: Array[String] = []
	_walk(root_path, targets)
	targets.sort()
	var key := handler.to_lower()
	# "old -> new" -> count, and the totals either side.
	var moves: Dictionary = {}
	var old_counts: Dictionary = {}
	var new_counts: Dictionary = {}
	# What the answering handler says about propagation: "" consumes, "pass"
	# continues, "stop" was already stopping. Only the middle one changes how many
	# handlers an event runs.
	var says: Dictionary = {}
	# Which scripts those are. An occurrence count alone is unreadable -- one
	# behaviour attached across a whole movie is thousands of them -- and a number
	# nobody can trace back to a script is a number nobody can check.
	var passers: Dictionary = {}
	var rows := 0
	var movies := 0
	var started := Time.get_ticks_msec()

	for path in targets:
		if not preview.call("_load_container", path):
			continue
		var score = preview.get("_score")
		if score == null or int(score.frame_count) <= 0:
			continue
		(preview.get("_lib_keys") as Dictionary).clear()
		Boot.start_lingo(preview, path)
		var lingo = preview.get("_interpreter")
		var table = preview.get("_table")
		movies += 1
		var movie_has_handler: bool = lingo != null and lingo.has_handler(key)
		var memo: Dictionary = {}
		for index in int(score.frame_count):
			preview.set("_index", index)
			var frame_declares := _declares(
				lingo, preview.call("_frame_script", index), key)
			for value in score.frame(index).get("sprites", []):
				var raw: Dictionary = value
				if not bool(preview.call("_responds_to_mouse", raw)):
					continue
				rows += 1
				var channel := int(raw["channel"])
				var memo_key := "%d|%d:%d|%d" % [channel, int(raw["cast_lib"]),
					int(raw["cast_id"]), int(frame_declares)]
				var move: String
				if memo.has(memo_key):
					move = str(memo[memo_key])
				else:
					var behaviour: Dictionary = preview.call(
						"_sprite_script", channel, index)
					var cast_script: Dictionary = preview.call("_script_in_lib",
						int(raw["cast_lib"]), int(raw["cast_id"]))
					var b_declares := _declares(lingo, behaviour, key)
					var c_declares := _declares(lingo, cast_script, key)
					# The old rule: one tier chosen, then a movie fallback.
					var chosen := "sprite" if not behaviour.is_empty() else (
						"cast" if not cast_script.is_empty() else "frame")
					var chosen_declares := (
						b_declares if chosen == "sprite"
						else (c_declares if chosen == "cast" else frame_declares))
					var was := chosen if chosen_declares else (
						"movie" if movie_has_handler else "none")
					# The queue: the first tier that declares it.
					var now := "none"
					if b_declares:
						now = "sprite"
					elif c_declares:
						now = "cast"
					elif frame_declares:
						now = "frame"
					elif movie_has_handler:
						now = "movie"
					# What the element that now answers says about carrying on.
					var winner: Dictionary = (
						behaviour if now == "sprite"
						else (cast_script if now == "cast"
						else (preview.call("_frame_script", index) if now == "frame"
						else {})))
					var says_what := (
						_propagation(winner, key) if now != "movie" else "")
					if says_what == "pass":
						passers["%s  %s" % [path.get_file(),
							str(winner.get("script", "?"))]] = true
					move = "%s -> %s|%s" % [was, now, says_what]
					memo[memo_key] = move
				var parts: PackedStringArray = move.split("|")
				var halves: PackedStringArray = parts[0].split(" -> ")
				moves[parts[0]] = int(moves.get(parts[0], 0)) + 1
				says[parts[1]] = int(says.get(parts[1], 0)) + 1
				old_counts[halves[0]] = int(old_counts.get(halves[0], 0)) + 1
				new_counts[halves[1]] = int(new_counts.get(halves[1], 0)) + 1
		if table != null:
			table.close()
		var container = preview.get("_movie")
		if container != null:
			container.close()

	var changed := 0
	var move_keys: Array = moves.keys()
	move_keys.sort()
	print("")
	print("`%s` targets across %s: %d movies, %d clickable sprite occurrence(s) in %.0f s"
		% [handler, root_path.get_file(), movies, rows,
			(Time.get_ticks_msec() - started) / 1000.0])
	for move in move_keys:
		var halves: PackedStringArray = str(move).split(" -> ")
		var same := halves[0] == halves[1]
		if not same:
			changed += int(moves[move])
		print("  %-22s %7d%s" % [move, int(moves[move]), "" if same else "   CHANGED"])
	print("  %d of %d occurrence(s) resolve to a different tier (%.2f%%)" % [
		changed, rows, 100.0 * float(changed) / maxf(rows, 1)])
	print("  which tier answers, old: %s" % JSON.stringify(old_counts))
	print("  which tier answers, new: %s" % JSON.stringify(new_counts))
	# The count the change is actually measured by. Everything above says *which*
	# handler answers; this says how many. Under the old rule it was one for every
	# occurrence that resolves to anything at all, whatever the handler said,
	# because there was nothing after it. Under the queue it is one for everything
	# that consumes and more than one for everything that passes.
	var one := int(says.get("", 0)) + int(says.get("stop", 0))
	print("  handlers per event, old: 1 for %d occurrence(s), 0 for %d" % [
		rows - int(new_counts.get("none", 0)), int(new_counts.get("none", 0))])
	print("  handlers per event, new: 1 for %d, >1 for %d (`pass`), 0 for %d" % [
		one - int(new_counts.get("none", 0)), int(says.get("pass", 0)),
		int(new_counts.get("none", 0))])
	var passer_keys: Array = passers.keys()
	passer_keys.sort()
	print("  the `pass` occurrences come from %d script(s):" % passer_keys.size())
	for name in passer_keys:
		print("    %s" % name)


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var wanted := Args.text(args, "file", "")
	if wanted != "":
		preview.call("lingo_go_movie", wanted, null)
		for i in 8:
			await process_frame

	var host = preview.get("_host")
	var interp = preview.get("_interpreter")
	if host == null or interp == null:
		print("no movie loaded; pass --file")
		quit(1)
		return
	preview.set("_paused", true)
	var movie := str(preview.call("movie_name"))

	var subject := _subject(preview)
	if subject.is_empty():
		print("%s: no frame in this movie has a clickable sprite with a behaviour "
			% movie + "attached -- pass --file to name one that has")
		quit(1)
		return
	print("")
	print("%s  frame %d  channel %d  behaviour %s in %s  member %d:%d" % [
		movie, int(subject["frame"]) + 1, int(subject["channel"]),
		str(subject["script_key"]), str(subject["script_cast"]),
		int(subject["member_lib"]), int(subject["member_id"])])

	var cast_key := "CastScript %d - clickchain" % int(subject["member_id"])

	# ------------------------------------------------------------- the subject
	h.begin("the five tiers are installed where the engine looks for them")
	h.check("the behaviour compiles into the script the score attaches",
		_install(interp, str(subject["script_cast"]), str(subject["script_key"]),
			SPRITE_CONSUMES))
	h.check("the cast script compiles into the member the sprite shows",
		_install(interp, str(subject["member_cast"]), cast_key, CAST_CONSUMES))
	h.check("a movie script declares `mouseUp`",
		_install(interp, "clickchain", "MovieScript 9001 - clickchain", MOVIE_SCRIPT)
		and interp.has_handler("mouseup"))
	h.check("the primary handlers are callable by name",
		_install(interp, "clickchain", "MovieScript 9002 - clickchain", PRIMARY_STOPS)
		and interp.has_handler("ccstop") and interp.has_handler("ccgo"))
	# The engine's own lookups, not the harness's: if `_script_in_lib` does not
	# find the cast script that was just written, every check below it would pass
	# by measuring nothing.
	var found_cast: Dictionary = preview.call("_script_in_lib",
		int(subject["member_lib"]), int(subject["member_id"]))
	h.check("and the engine's own member lookup finds the cast script",
		str(found_cast.get("script", "")) == cast_key,
		"resolved to '%s'" % str(found_cast.get("script", "")))
	h.complete("the five tiers are installed where the engine looks for them")

	# ------------------------------------- §8.2, a tier below the first consumes
	# The control, and the half that a queue landed without the flag would break.
	# Every element below the behaviour must stay silent.
	h.begin("§8.2 a sprite behaviour that says nothing consumes the click")
	var did := _click(preview, host, subject)
	h.check("the behaviour ran", _count(host, "ccsprite") == 1, did)
	h.check("the member's cast script did not", _count(host, "cccast") == 0, did)
	h.check("nor did the movie script", _count(host, "ccmovie") == 0, did)
	# The count, stated as a count. A queue landed without the flag would have
	# every element of it here and would satisfy every check above.
	h.check("exactly one handler ran, and it was the sprite tier",
		did == "1 handler(s): sprite", did)
	h.complete("§8.2 a sprite behaviour that says nothing consumes the click")

	# ------------------------------------------------------------ §8.2, `pass`
	h.begin("§8.2 `pass` hands the click to the tier below")
	h.check("the behaviour is replaced by one that passes",
		_install(interp, str(subject["script_cast"]), str(subject["script_key"]),
			SPRITE_PASSES))
	did = _click(preview, host, subject)
	h.check("the behaviour ran", _count(host, "ccsprite") == 1, did)
	h.check("and the member's cast script ran after it -- which is the whole fix",
		_count(host, "cccast") == 1, did)
	h.check("and the cast script, saying nothing, stopped it there",
		_count(host, "ccmovie") == 0 and did == "2 handler(s): sprite -> cast", did)
	h.complete("§8.2 `pass` hands the click to the tier below")

	h.begin("§8.2 `pass` all the way down reaches the movie script")
	h.check("the cast script is replaced by one that passes",
		_install(interp, str(subject["member_cast"]), cast_key, CAST_PASSES))
	did = _click(preview, host, subject)
	h.check("all three tiers ran, in Director's order",
		_count(host, "ccsprite") == 1 and _count(host, "cccast") == 1
		and _count(host, "ccmovie") == 1
		and did == "3 handler(s): sprite -> cast -> movie", did)
	h.complete("§8.2 `pass` all the way down reaches the movie script")

	# ------------------------------ a behaviour and a cast script are cumulative
	# The second concrete cost the old resolution carried: it took the behaviour
	# *or* the cast script, so a behaviour declaring only `mouseDown` hid a cast
	# script's `mouseUp` and the event fell past it to the movie scripts.
	h.begin("a behaviour with no `mouseUp` no longer shadows its member's cast script")
	h.check("the behaviour is replaced by one that answers only the press",
		_install(interp, str(subject["script_cast"]), str(subject["script_key"]),
			SPRITE_DOWN_ONLY)
		and _install(interp, str(subject["member_cast"]), cast_key, CAST_CONSUMES))
	did = _click(preview, host, subject)
	h.check("the press reached the behaviour", _count(host, "ccdown") == 1,
		str(_count(host, "ccdown")))
	h.check("the release reached the cast script", _count(host, "cccast") == 1, did)
	h.check("and did not skip past it to the movie script",
		_count(host, "ccmovie") == 0 and did == "1 handler(s): cast", did)
	h.complete("a behaviour with no `mouseUp` no longer shadows its member's cast script")

	# ------------------------------------------------- §6.3 tier 1, `dontPassEvent`
	h.begin("§8.2 `dontPassEvent` in a primary handler stops the whole chain")
	h.check("the behaviour is put back",
		_install(interp, str(subject["script_cast"]), str(subject["script_key"]),
			SPRITE_CONSUMES))
	host.set_system_prop("mouseupscript", "ccstop")
	did = _click(preview, host, subject)
	h.check("the primary handler ran", _count(host, "ccprimary") == 1,
		str(_count(host, "ccprimary")))
	h.check("and nothing below it did",
		_count(host, "ccsprite") == 0 and _count(host, "cccast") == 0
		and _count(host, "ccmovie") == 0 and did == "0 handler(s): nothing", did)
	# The flag is per element, not per movie: a refusal that outlived its own
	# event would silence every click after the first.
	host.set_system_prop("mouseupscript", "ccgo")
	did = _click(preview, host, subject)
	h.check("a primary handler that says nothing passes by default",
		_count(host, "ccprimary") == 1 and _count(host, "ccsprite") == 1, did)
	host.set_system_prop("mouseupscript", "")
	did = _click(preview, host, subject)
	h.check("and the refusal did not outlive its own event",
		_count(host, "ccsprite") == 1, did)
	h.complete("§8.2 `dontPassEvent` in a primary handler stops the whole chain")

	# --------------------------------------- §15, the member the chain started on
	var swap_to := _swap_target(preview, subject)
	h.begin("§15 a press that swaps the member leaves the old member answering")
	if swap_to <= 0:
		h.check("a swap target exists that keeps the sprite under the pointer",
			false, "none of members 1-399 in cast %d" % int(subject["member_lib"]))
	else:
		host.set_global("ccswapto", swap_to)
		var swapped_key := "CastScript %d - clickchain" % swap_to
		h.check("the pieces are installed",
			_install(interp, str(subject["script_cast"]), str(subject["script_key"]),
				SPRITE_SWAPS)
			and _install(interp, str(subject["member_cast"]), cast_key, CAST_CONSUMES)
			and _install(interp, str(subject["member_cast"]), swapped_key,
				CAST_SWAPPED_IN))
		# Without this the case proves nothing: "the swapped-in member's cast
		# script never ran" is satisfied by a cast script the engine cannot
		# resolve, which is the shape of a check that has gone dark.
		var swapped_found: Dictionary = preview.call("_script_in_lib",
			int(subject["member_lib"]), swap_to)
		h.check("the swapped-in member has a cast script the engine can find",
			str(swapped_found.get("script", "")) == swapped_key,
			"member %d resolved to '%s'" % [
				swap_to, str(swapped_found.get("script", ""))])
		_zero(host)
		preview.set("_index", int(subject["frame"]))
		preview.call("route_press", subject["at"])
		var now_showing := int(EventChain.member_on(
			preview, int(subject["channel"])).get("id", 0))
		h.check("the press ran and swapped the member under itself",
			_count(host, "ccdown") == 1 and now_showing == swap_to,
			"channel %d showed %d, now shows %d" % [
				int(subject["channel"]), int(subject["member_id"]), now_showing])
		# The latch itself, before the release is even sent: what the chain will
		# resolve its cast element against is the member the press landed on, and
		# the channel now shows a different one.
		h.check("but the chain still names the member the press landed on",
			int((preview.get("_press_member") as Dictionary).get("id", 0))
				== int(subject["member_id"]),
			str((preview.get("_press_member") as Dictionary).get("id", 0)))
		var up_before := _chain_tallies(preview, "mouseUp")
		preview.call("route_release", subject["at"])
		did = _chain_delta(preview, "mouseUp", up_before)
		h.check("so the old member's cast script answered the release",
			_count(host, "cccast") == 1, did)
		h.check("and the swapped-in member's never saw it",
			_count(host, "ccswapped") == 0, did)
		preview.call("lingo_set_sprite_prop", int(subject["channel"]), "membernum",
			int(subject["member_id"]))
	h.complete("§15 a press that swaps the member leaves the old member answering")

	# ------------------------------------------------ what the corpus asks for
	# Reported, not asserted. It says whether the rules above matter to a shipped
	# title; it cannot say whether they are implemented, and conflating the two is
	# how "no site for it" becomes a reason not to build it.
	var sites: Dictionary = {}
	_pass_sites("res://reference/lingo", sites)
	var keys: Array = sites.keys()
	keys.sort()
	var total_pass := 0
	var total_stop := 0
	print("")
	print("`pass` and `dontPassEvent` in the decompiled Lingo beside this repo:")
	for key in keys:
		var pair: Array = sites[key]
		print("  %-44s pass %d, dontPassEvent %d" % [key, int(pair[0]), int(pair[1])])
		total_pass += int(pair[0])
		total_stop += int(pair[1])
	print("  %d site(s): %d `pass`, %d `dontPassEvent`" % [
		keys.size(), total_pass, total_stop])
	print("  (ProjectorRays writes them `pass()` and `dont(pass)`, so a token")
	print("   search for either name answers 0 for all of them.)")

	var paths := Paths.new()
	paths.load_config()

	# Opt-in, because it re-reads every container in the root and the gate runs
	# this file for the assertions above. `-- --survey` when the question is how
	# much of a title the change reaches rather than whether it is right.
	if Args.flag(args, "survey"):
		preview.set_process(false)
		preview.set_process_input(false)
		var only := Args.text(args, "handler", "")
		for name in ["mouseUp", "mouseDown"]:
			if only == "" or only.to_lower() == name.to_lower():
				_survey(preview, name, paths.root)

	quit(h.finish("§6.3's mouse chain in %s (%s)" % [movie, str(paths.root).get_file()]))
