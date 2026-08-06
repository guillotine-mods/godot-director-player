extends SceneTree
## Does a film-loop child draw at its member's size unless the mini-score says stretch?
##
## A loop's children are sprite records in the same 48-byte format as the movie's
## own score, so the same rule governs them: the width and height stored on a child
## are the drawn rect only when bit 0x80 of its ink byte is set, and with the flag
## clear they are authoring residue. `tools/director_film_loops.py` masked the ink
## byte to its low 6 bits and dropped the flag with it — the same loss
## `generate_sprite_stretch.py` exists to undo for the main score — so the renderer
## scaled every child into its recorded rect. 235 of the corpus's 13,612 children
## disagree with their member, `wonder` member 27 worst: 101x144 blown up to
## 203x289, which is the giant black dress that appears over DAY1's field.
##
## The checks are on the rect `MoviePlayer.film_loop_draw_commands` hands the
## canvas, not on the flag round-tripping through a getter. The flagged case is the
## negative control and matters as much as the rest: a fix that simply stopped
## honouring the recorded rect would pass every unflagged case here and be wrong
## about the 2,053 children Director really does scale.
##
## The corpus line at the end guards the pipeline — the flags surviving export into
## `cast_registry.json` and being read — not the semantics. It cannot tell you the
## rects are right.
##
##   godot --headless --script tools/film_loop_stretch.gd

## Each case is a score frame in a movie, the loop channel on it, and which frame of
## the loop to park the cursor on. `size` is the member's own size, which is what the
## child must draw at; `residue` is the rect the mini-score stores, which it must not.
const CASES := [
	{
		"movie": "DAY1", "frame": 1805, "channel": 20, "loop_frame": 0,
		"cast": "wonder", "member": 27, "size": [101, 144], "residue": [203, 289],
		"note": "the giant black dress over the field, reported from play",
	},
	{
		"movie": "DAY1", "frame": 1805, "channel": 19, "loop_frame": 0,
		"cast": "wonder", "member": 1, "size": [142, 192], "residue": [101, 144],
		"note": "residue smaller than the member: the guest on the bench, drawn shrunk",
	},
	{
		"movie": "DAY1", "frame": 1805, "channel": 21, "loop_frame": 0,
		"cast": "wonder", "member": 59, "size": [84, 159], "residue": [97, 159],
		"note": "one axis only, which is what 'scratching over too much' looks like",
	},
	{
		"movie": "DAY1", "frame": 342, "channel": 20, "loop_frame": 0,
		"cast": "wonder", "member": 156, "size": [94, 172], "residue": [94, 172],
		"stretched": true,
		"note": "NEGATIVE CONTROL: flag set, so the recorded rect is the drawn rect",
	},
]

var _completed: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


## A check is counted from its own last line. A GDScript runtime error aborts the
## handler and hands back the return type's zero value, so `failures += _check(...)`
## scores a dead check as a pass; `verify_film_loops.gd` printed "all 3 loop
## compositions draw the expected members" twice while every one had aborted.
func _complete(label: String, failed: int) -> int:
	_completed[label] = failed
	return failed


func _run() -> void:
	var failures := 0
	var labels: Array = []
	for case in CASES:
		var label := "%s frame %d ch%d" % [case["movie"], case["frame"], case["channel"]]
		labels.append(label)
		failures += _check(case, label)
	for label in labels:
		if not _completed.has(label):
			print("%-26s FAIL: the check did not complete (see the errors above)" % label)
			failures += 1

	print("")
	failures += _check_corpus()

	print("")
	if failures == 0:
		print("all %d film-loop children draw at the size Director gives them" % CASES.size())
	else:
		print("%d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _check(case: Dictionary, label: String) -> int:
	var movie: String = case["movie"]
	var frame: int = case["frame"]
	var channel: int = case["channel"]
	var member: int = case["member"]
	var expected := Vector2(
		float((case["size"] as Array)[0]), float((case["size"] as Array)[1])
	)
	var residue := Vector2(
		float((case["residue"] as Array)[0]), float((case["residue"] as Array)[1])
	)

	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK or not runtime.goto_movie(movie, frame):
		print("%-26s FAIL: cannot reach the frame" % label)
		return _complete(label, 1)
	# Park the playhead rather than let the clock carry it off the frame.
	runtime.running = false
	runtime.frame_index = frame - 1
	runtime.reconcile_channels(runtime.loader.get_frame(runtime.frame_index))

	var sprite: Dictionary = runtime.effective_sprite(channel)
	if sprite.is_empty():
		print("%-26s FAIL: channel is empty" % label)
		return _complete(label, 1)
	var loop: Dictionary = runtime.loader.get_film_loop(
		int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0))
	)
	if loop.is_empty():
		print("%-26s FAIL: channel is not a film loop" % label)
		return _complete(label, 1)

	# The cursor is the channel's, so parking it is how a named loop frame is
	# reached without stepping the score until it happens to come round.
	var entry: Variant = runtime.channels.get(channel, null)
	if entry == null:
		print("%-26s FAIL: no sprite channel" % label)
		return _complete(label, 1)
	entry.loop_frame = int(case["loop_frame"])

	var player: Control = load("res://director/movie_player.gd").new()
	player.runtime = runtime
	var commands: Array = player.film_loop_draw_commands(sprite, loop, channel)
	player.free()

	var drawn := Vector2.ZERO
	var found := false
	for command_value in commands:
		var command: Dictionary = command_value
		if int(command.cast_id) == member and str(command.cast) == str(case["cast"]):
			drawn = (command.rect as Rect2).size
			found = true
			break
	if not found:
		print("%-26s FAIL: %s member %d is not in the composition" % [
			label, case["cast"], member,
		])
		return _complete(label, 1)

	var ok := drawn.is_equal_approx(expected)
	# Only meaningful where the two differ; on the flagged case they are the same
	# number and this line would accuse a correct draw.
	var still_residue := (not expected.is_equal_approx(residue)) and drawn.is_equal_approx(residue)
	print("%-26s %s  %s %d drew %dx%d, expected %dx%d%s  %s" % [
		label, "ok  " if ok else "FAIL", case["cast"], member,
		int(drawn.x), int(drawn.y), int(expected.x), int(expected.y),
		"  (still the stored rect)" if still_residue else "",
		str(case.get("note", "")),
	])
	return _complete(label, 0 if ok else 1)


func _check_corpus() -> int:
	## The flags surviving into the registry and being readable. Counts, not rects:
	## a child whose recorded rect happens to equal its member's size is
	## indistinguishable here whichever way the renderer decides.
	var loader := RenderModelLoader.new()
	if loader.load_index() != OK:
		print("corpus  FAIL: cannot load the render model index")
		return 1
	var total := 0
	var flagged := 0
	for cast_value in loader.cast_registry.values():
		if typeof(cast_value) != TYPE_DICTIONARY:
			continue
		var loops: Variant = (cast_value as Dictionary).get("film_loops", {})
		if typeof(loops) != TYPE_DICTIONARY:
			continue
		for loop_value in (loops as Dictionary).values():
			if typeof(loop_value) != TYPE_DICTIONARY:
				continue
			var loop_frames: Variant = (loop_value as Dictionary).get("frames", [])
			if typeof(loop_frames) != TYPE_ARRAY:
				continue
			for loop_frame in loop_frames as Array:
				if typeof(loop_frame) != TYPE_DICTIONARY:
					continue
				var children: Variant = (loop_frame as Dictionary).get("sprites", [])
				if typeof(children) != TYPE_ARRAY:
					continue
				for child_value in children as Array:
					if typeof(child_value) != TYPE_DICTIONARY:
						continue
					total += 1
					if bool((child_value as Dictionary).get("stretch", false)):
						flagged += 1
	# Zero would mean the generator ran without the flag, which is the state this
	# harness was written against and is invisible in any resolve count.
	var ok := flagged > 0
	print("corpus  %s  %d of %d film-loop children carry the stretch flag" % [
		"ok  " if ok else "FAIL", flagged, total,
	])
	return 0 if ok else 1
