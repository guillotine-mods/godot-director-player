extends SceneTree
## What the preview's SKIP button leaves behind.
##
##   godot --headless --audio-driver Dummy --script tools/skip_state.gd
##   godot --headless --audio-driver Dummy --script tools/skip_state.gd -- --file PIP2DATA/DAY1.DIR
##   godot --headless --audio-driver Dummy --script tools/skip_state.gd -- --all
##   godot --headless --audio-driver Dummy --script tools/skip_state.gd -- --presses 8
##
## **SKIP releases; it does not navigate.** `skip_release` cuts the voice on
## channel 1 and drops every hold the clock is carrying, and then it returns
## without touching `_index`. Everything below is the measurement of that
## sentence, and it is written this way because the four reports SKIP has caused
## in this project were all one mistake -- the button choosing a destination.
##
## The destination it chose was "the marker after the playhead", falling back to
## the last frame, and both halves are unrecoverable from a container:
##
##   MURDER1 frame 883 (last)  `on exitFrame / go("conect2")`  -> frame 790
##   DAY1    frame 2783 (last) `on exitFrame / play "done"`    -> nowhere
##   MAINMENU marker 587       `option1`, a drive probe        -> frame 2
##   COMEIN   marker 180       `f1`, the pot game *after* its own `return1`
##
## The first is a jump backwards into the tail the player was trying to escape,
## so SKIP visibly did not skip and got pressed again. The second is a subroutine
## return with no `play` on the stack, on the last frame, so the playhead parked
## permanently -- which is where "the cursor reverts to the plain arrow and never
## comes back" came from (`bugs.md` 32; nothing was wrong with the cursor, it was
## recomputing correctly over a dead playhead). The third is a closed cycle
## belonging to the movie (`bugs.md` 37). The fourth lands *inside* a playable
## segment past the frame that puppets its channels and sets its counters, which
## reads as "the game is broken" (`bugs.md` 96). A `VWLB` does not say which
## markers are scenes, so no title-agnostic rule separates any of them.
##
## ## What is asserted
##
## **The press moves nothing.** `_index` before the call equals `_index` after
## it, for every press. This is the whole design, and it is the check that all
## four reports above would have failed. Asserted per press rather than once, so
## a rule that only misbehaves on the second or fifth press -- which is exactly
## what `bugs.md` 96 measured -- cannot hide behind the first.
##
## **The press leaves nothing on the clock.** After it, `hold_reason()` is empty
## and `playhead_held()` is false. This is what keeps the check above from being
## satisfied by a button that does nothing at all: the two together say the frame
## was released *and* the playhead was left alone, which is the only combination
## that lets the movie's own scripts decide where it goes.
##
## **The movie can still move.** Deliberately generous about what counts: a new
## frame or a new movie, either means the scripts are still driving. Only "the
## same frame of the same movie, four hundred steps later" is the parked state.
##
## Title-agnostic: no movie, frame or label is named. `--all` sweeps every
## container under the game root.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerName := preload("res://director/director_container.gd")

## Long enough for the landing frame to have run its `exitFrame` many times over,
## and for a `go` it issues to have been taken.
const STEPS_AFTER := 400
## Enough for the movie to have entered a room and armed whatever it arms.
const STEPS_BEFORE := 250
## Presses per movie. More than one on purpose: the marker walk this replaces was
## right on its first press in `COMEIN.dir` and wrong on every press after it, so
## a single-press harness is a harness that would have passed the report.
const PRESSES := 5
## Score steps between presses, so each one is made from a frame the movie itself
## reached rather than from the frame the previous press was made on.
const STEPS_BETWEEN := 40


func _where(preview: Node) -> String:
	var movie = preview.get("_movie")
	return "%s f%d" % [str(movie.path).get_file(), int(preview.get("_index"))]


func _movies(dir_path: String, prefix: String = "") -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for entry in files:
		if ContainerName.MOVIE.has(entry.get_extension().to_lower()):
			out.append(prefix + entry)
	var subs := dir.get_directories()
	subs.sort()
	for sub in subs:
		out.append_array(_movies(dir_path.path_join(sub), prefix + sub + "/"))
	return out


## Press SKIP `presses` times, letting the movie run between them, and report.
func _measure(h: Harness, preview: Node, label: String, presses: int) -> void:
	var clock = preview.get("_clock")
	var landed := ""
	var moved_by_press: Array[String] = []
	var still_holding: Array[String] = []
	var trail: Array[String] = []
	for press in presses:
		var before_index := int(preview.get("_index"))
		var before := _where(preview)
		preview.call("skip_release")
		var after_index := int(preview.get("_index"))
		if after_index != before_index:
			moved_by_press.append("press %d: %s -> f%d" % [press + 1, before, after_index])
		# Read straight after the call, before any step: a hold the *next* frame
		# arms is the movie's and not the button's failure to drop this one.
		if bool(clock.playhead_held()) or str(clock.hold_reason()) != "":
			still_holding.append("press %d: %s holding %s" % [
				press + 1, before, str(clock.hold_reason())])
		trail.append(before)
		landed = _where(preview)
		for i in STEPS_BETWEEN:
			preview.call("_advance")
	var after := _where(preview)
	for i in STEPS_AFTER:
		preview.call("_advance")
		if _where(preview) != after:
			break
	var settled := _where(preview)
	print("   %-14s pressed %d time(s) at %s" % [label, presses, ", ".join(trail)])
	print("   %-14s ended on %s, then %s" % ["", after, settled])
	h.check("%s: SKIP moves the playhead nowhere" % label,
		moved_by_press.is_empty(), "; ".join(moved_by_press))
	h.check("%s: SKIP leaves nothing holding the frame" % label,
		still_holding.is_empty(), "; ".join(still_holding))
	h.check("%s: the movie can still move after SKIP" % label, settled != after,
		"parked on %s" % after if settled == after else "moved to %s" % settled)


func _init() -> void:
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	if scene == null:
		print("no preview scene")
		quit(1)
		return
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var args := Args.parse()
	var presses := Args.number(args, "presses", PRESSES)
	h.begin("SKIP leaves the movie somewhere it can leave")
	# **A harness with no subject reports PASS, and that is the failure this file
	# exists to avoid making.** Measured while rewriting it: with another module
	# transiently un-parseable the preview instantiated as an empty node, every
	# `preview.get("_index")` answered null, `_measure` raised inside the awaited
	# `_init` and the run printed `PASS (0 checks, 0 failed)` -- the same shape
	# `bugs.md` 33 filed against `editable_text`. One check that a movie is loaded
	# turns that into a red.
	var loaded: bool = preview.get("_score") != null and preview.get("_movie") != null
	if not h.check("a movie is playing to press SKIP in", loaded,
			"" if loaded else "the preview did not reach a movie"):
		h.complete("SKIP leaves the movie somewhere it can leave")
		quit(h.finish("the preview's SKIP button"))
		return
	for i in STEPS_BEFORE:
		preview.call("_advance")
	# `--label` / `--frame` stand the playhead somewhere a bug report names before
	# the first press. `bugs.md` 96 is filed from `COMEIN.dir` f173, the idle loop
	# the pot game waits in, and the settle above lands nowhere near it -- a
	# harness that can only press SKIP wherever 250 steps happen to leave it
	# cannot reproduce an entry.
	if Args.text(args, "label") != "":
		preview.call("lingo_go_label", Args.text(args, "label"))
		preview.call("_advance")
	elif args.has("frame"):
		preview.call("lingo_go_frame", Args.number(args, "frame", 0))
		preview.call("_advance")
	_measure(h, preview, _where(preview).get_slice(" ", 0), presses)

	# The sweep is opt-in: it opens every container under the game root, which is
	# a compile and a settle each, and the single-movie run is what a bug report
	# is reproduced with.
	if Args.flag(args, "all"):
		var paths = preview.get("_paths")
		for candidate in _movies(str(paths.root)):
			preview.call("lingo_go_movie", candidate, null)
			if _where(preview).get_slice(" ", 0).to_lower() \
					!= str(candidate).get_file().to_lower():
				continue
			for i in STEPS_BEFORE:
				preview.call("_advance")
			_measure(h, preview, str(candidate).get_file(), presses)
	h.complete("SKIP leaves the movie somewhere it can leave")

	quit(h.finish("the preview's SKIP button"))
