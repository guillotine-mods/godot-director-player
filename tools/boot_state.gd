extends SceneTree
## Does a room arrive in the state the rooms before it were supposed to leave?
##
##   godot --headless --script tools/boot_state.gd -- --file PIP2DATA/EXODUS.DIR
##
## Director games are state machines spread across movies. A room's opening
## condition is not in that room: `EXODUS` sets `globalday` and `syz` and then
## goes to `DAY1`, and `DAY1`'s own `init all` only sets `meetings` *inside* an
## `if globalday = 1` branch. Enter `DAY1` without `globalday` and it initialises
## half of itself, silently -- and `meetings` is what `peoplefunk` tests to decide
## whether walking to `clif2` launches `murder1`, so its absence reads as "the
## door works but the movie never plays".
##
## Three separate faults conspired to produce that, all now fixed, and this is the
## gate that keeps them fixed:
##
##   - globals were discarded on every `go to movie`, so nothing upstream could
##     ever reach a later room;
##   - a frame jump across a marker cleared all puppet state, so `init all`'s own
##     work was thrown away by the `go("shore2")` on its last line;
##   - `int(null)` on a puppeted VOID aborted `_draw` mid-frame.
##
## It walks the real boot chain rather than asserting on a synthetic interpreter,
## because what is being tested is the chain.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## What DAY1 cannot open correctly without, and where each is supposed to come
## from. Named here rather than in the engine: a harness is allowed to know the
## corpus it asserts against, which is what makes it a measurement.
const REQUIRED := {
	"globalday": "strtgame / EXODUS",
	"meetings": "DAY1 init all, but only when globalday = 1",
	"syz": "EXODUS",
	"egozh": "DAY1 init all",
	"egozv": "DAY1 init all",
	"nof": "DAY1 init all",
	"whatodo": "DAY1 init all",
}


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	# Far enough into EXODUS for its own frame scripts to set what they set.
	for i in Args.number(args, "steps", 80):
		preview.call("_advance")

	var from := str(preview.call("movie_name"))
	preview.call("lingo_go_movie", Args.text(args, "to", "day1.dxr"), null)
	await process_frame
	var into := str(preview.call("movie_name"))

	h.begin("the boot chain leaves the next room able to open")
	h.check("the movie changed", into.to_lower() != from.to_lower(),
		"%s -> %s" % [from, into])

	# Let the arriving movie run its own initialisation. `init all` is DAY1's
	# frame-0 script and it ends by jumping to the room proper.
	for i in 120:
		preview.call("_advance")

	var g: Dictionary = preview.get("_interpreter").globals
	var missing: Array[String] = []
	for name in REQUIRED:
		var value: Variant = g.get(name, null)
		var present: bool = value != null and str(value) != ""
		print("  %-12s %-44s %s" % [
			name, str(REQUIRED[name]), JSON.stringify(value) if present else "<MISSING>"
		])
		if not present:
			missing.append(str(name))
	h.check("every global the next room reads is set", missing.is_empty(),
		", ".join(missing))

	# `meetings` is the one that gates the day's set-piece movies, and it is a
	# comma list of eight. A truncated or empty one still "exists".
	var meetings := str(g.get("meetings", ""))
	h.check("meetings carries its full list",
		meetings.split(",").size() >= 8, "%d item(s): '%s'" % [
			meetings.split(",").size(), meetings
		])

	# Puppet state has to survive the jump `init all` makes on its own last line.
	var overrides: Dictionary = preview.get("_overrides")
	h.check("the room's initialisation survived its own `go`",
		not overrides.is_empty(), JSON.stringify(overrides.keys()))
	h.complete("the boot chain leaves the next room able to open")
	quit(h.finish("cross-movie state on the real boot chain"))
