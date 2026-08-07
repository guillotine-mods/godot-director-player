extends SceneTree
## Do Lingo globals outlive a `go to movie`?
##
##   godot --headless --script tools/globals_survive.gd -- --file PIP2DATA/EXODUS.DIR
##
## They must. That is the entire point of a Lingo global, and this game is built
## on it: `EXODUS` sets `globalday` and `syz` and then goes to `DAY1`, which
## reads them. Director clears globals only on `clearGlobals` or on quitting, and
## never on a movie change.
##
## The preview stands up a fresh interpreter per movie, because the scripts, the
## casts and the handler tables all belong to the movie being left. It used to
## stand up fresh *globals* with them, so every room began with every global
## VOID. That is not a subtle failure: a room that decides what to show from
## accumulated state shows the wrong thing, and the wrongness reads as a
## rendering fault rather than as a lost variable.
##
## This sets a sentinel, crosses a real movie boundary using the movie's own
## navigation, and asks whether the sentinel is still there -- rather than
## testing the carry in isolation, which would not exercise `lingo_go_movie`.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var interp = preview.get("_interpreter")
	if interp == null:
		print("no interpreter; is Lingo enabled?")
		quit(1)
		return

	# Step first, so the movie has actually accumulated some globals to lose.
	# EXODUS sets `globalday`, `syz` and the sound paths across its opening
	# frames; testing at frame 0 would prove only that an empty dictionary
	# survives, which is not the claim.
	for i in Args.number(args, "steps", 60):
		preview.call("_advance")

	var before := str(preview.call("movie_name"))
	h.begin("a global survives the movie that set it")

	# A sentinel of our own, plus whatever the movie has already accumulated, so
	# the check covers both the mechanism and the real payload.
	interp.globals["__sentinel"] = "kept"
	var accumulated: Array[String] = []
	for key in interp.globals.keys():
		if str(key) != "__sentinel":
			accumulated.append(str(key))
	print("%s holds %d global(s) before the move" % [before, accumulated.size()])

	var target := Args.text(args, "to", "day1.dxr")
	preview.call("lingo_go_movie", target, null)
	await process_frame

	var after := str(preview.call("movie_name"))
	var moved := after.to_lower() != before.to_lower()
	h.check("the movie actually changed", moved, "%s -> %s" % [before, after])
	if not moved:
		h.complete("a global survives the movie that set it")
		quit(h.finish("globals across a movie change"))
		return

	# The interpreter is a new object; the dictionary must not be.
	var now = preview.get("_interpreter")
	h.check("the interpreter was rebuilt", now != interp, "")
	h.check("the sentinel crossed with it",
		str((now.globals as Dictionary).get("__sentinel", "")) == "kept",
		JSON.stringify((now.globals as Dictionary).keys()))

	var kept := 0
	for key in accumulated:
		if (now.globals as Dictionary).has(key):
			kept += 1
	h.check("every global the previous movie set is still there",
		kept == accumulated.size(), "%d of %d" % [kept, accumulated.size()])
	print("%s holds %d global(s) after the move" % [after, (now.globals as Dictionary).size()])
	h.complete("a global survives the movie that set it")
	quit(h.finish("globals across a movie change"))
