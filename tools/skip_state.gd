extends SceneTree
## What the preview's SKIP button leaves behind.
##
##   godot --headless --script tools/skip_state.gd
##   godot --headless --script tools/skip_state.gd -- --file PIP2DATA/DAY1.DIR
##   godot --headless --script tools/skip_state.gd -- --all
##
## **A Director movie's last frame is not its ending.** A movie is a strip of
## independently labelled segments, and the last frame is only the last segment's
## last frame. `skip_to_end` moves the playhead there and nothing else, on the
## premise that the end of the file is the end of the scene, and that premise is
## false often enough to strand the player:
##
##   MURDER1 frame 883 (last)  `on exitFrame / go("conect2")`  -> frame 790
##   DAY1    frame 2783 (last) `on exitFrame / play "done"`    -> nowhere
##
## The first is a jump *backwards* into the tail the player was trying to escape,
## so SKIP visibly does not skip; the player presses it again. The second is a
## subroutine return with no `play` on the stack — `lingo_play_done` finds
## `_play_stack` empty and returns without moving anything — and it is the last
## frame, so the score's own advance has nowhere to go either. The playhead is
## parked, permanently.
##
## That is where the reported "the cursor reverts to the plain arrow and never
## comes back" comes from, and why it was not reproducible by playing MURDER1 to
## its own exit. Nothing is wrong with the cursor: `_channel_cursors` still holds
## every pair the room assigned, but none of *those* channels have a sprite on the
## parked frame, so the descent correctly falls through to the global cursor —
## which is 0, the arrow — at every point on the stage, for ever. See bugs.md 32.
##
## So this asserts the property SKIP actually needs, which is not "the playhead
## reached the last frame" but **the movie can still move**. Title-agnostic: no
## movie, frame or label is named, and a title whose last frames happen to be real
## endings passes without changing anything here.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerName := preload("res://director/director_container.gd")

## Long enough for the landing frame to have run its `exitFrame` many times over,
## and for a `go` it issues to have been taken.
const STEPS_AFTER := 400
## Enough for the movie to have entered a room and armed whatever it arms.
const STEPS_BEFORE := 250


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


## Skip the movie now playing and report where it ends up.
##
## Two checks, because the premise fails in two different directions and each one
## strands the player differently.
##
## **The landing frame is an ending.** One step after the skip, the movie must not
## have jumped *backwards*. A last frame whose `exitFrame` says `go(<a label
## earlier in the movie>)` is a loop-back, not an end: SKIP drops the player into
## the tail they were trying to escape and, from their chair, does nothing at all.
##
## **The movie can still move.** Deliberately generous about what counts: a new
## frame or a new movie, either means the movie's own scripts are still driving
## and the player can get out. Only "the same frame of the same movie, four
## hundred steps later" is the parked state.
func _measure(h: Harness, preview: Node, label: String) -> void:
	var before := _where(preview)
	var before_index := int(preview.get("_index"))
	var before_cursor: Variant = preview.call("cursor_at", Vector2(320, 240))
	preview.call("skip_to_end")
	var landed := _where(preview)
	var landed_index := int(preview.get("_index"))
	# The first frame that is not the landing frame, not simply the next step: the
	# landing frame is *entered* by the step after the jump and its `exitFrame`
	# does not run until the step after that, so a one-step probe always reports
	# the landing frame back to itself and would never see the loop-back.
	var stepped := landed
	var stepped_index := landed_index
	var steps := 0
	while steps < STEPS_AFTER:
		preview.call("_advance")
		steps += 1
		if _where(preview) != landed:
			stepped = _where(preview)
			stepped_index = int(preview.get("_index"))
			break
	var same_movie := stepped.get_slice(" ", 0) == landed.get_slice(" ", 0)
	while steps < STEPS_AFTER:
		preview.call("_advance")
		steps += 1
	var after := _where(preview)
	var after_cursor: Variant = preview.call("cursor_at", Vector2(320, 240))
	var cursors: Dictionary = preview.get("_channel_cursors")
	print("   %-14s %s -> skip -> %s -> %s -> %s" % [label, before, landed, stepped, after])
	print("   %-14s cursor at the stage centre: %s -> %s, %d channel(s) still recorded" % [
		"", str(before_cursor), str(after_cursor), cursors.size()])
	h.check("%s: the last frame is an ending, not a jump back" % label,
		not (same_movie and stepped_index < landed_index),
		"skipped from f%d, landed on f%d, next frame f%d" % [
			before_index, landed_index, stepped_index])
	h.check("%s: the movie can still move after SKIP" % label, after != landed,
		"parked on %s" % landed if after == landed else "moved to %s" % after)


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
	h.begin("SKIP leaves the movie somewhere it can leave")
	for i in STEPS_BEFORE:
		preview.call("_advance")
	_measure(h, preview, _where(preview).get_slice(" ", 0))

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
			_measure(h, preview, str(candidate).get_file())
	h.complete("SKIP leaves the movie somewhere it can leave")

	quit(h.finish("the preview's SKIP button"))
