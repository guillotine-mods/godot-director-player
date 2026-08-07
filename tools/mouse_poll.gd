extends SceneTree
## Can a movie still see a click that is shorter than one of its own frames?
##
##   godot --script tools/mouse_poll.gd -- --file PIP2DATA/CHESS.dir --label ches1
##   godot --script tools/mouse_poll.gd -- --root rating --file MAINMENU.dir \
##       --label oliver --settle 20 --reach 504
##   godot --script tools/mouse_poll.gd -- --press 1 --tries 8
##
##   --label L    the marker to click on (default `ches1`)
##   --reach N    the frame the click must get the movie to (default: the frame
##                of the marker after `--label`)
##   --settle N   score ticks to let the movie reach its idle loop (default 12)
##   --press N    process frames to hold the button for (default 1, ~16 ms)
##   --tries N    clicks to make (default 6)
##
## Runs headless or not; it is green both ways and red both ways, because the
## button is driven through `Input.parse_input_event` and `Input`'s own state is
## not a display-server question. The `flush_buffered_events` in `_button` is
## what makes that true and is not tidiness — see there.
##
## ## What this is about
##
## `the mouseDown` is polled from `on exitFrame`, which is Director's standard
## click-to-skip and charge-and-fire idiom -- 17 sites in `rating`, 4 in this
## game's CHESS -- and `exitFrame` runs at the *score's* rate. These movies run
## at 4 to 8 fps, so 125 to 250 ms separates one poll from the next, while a
## click off a human hand lasts 40 to 100 ms. Answer the poll from the live
## button and the majority of clicks happen entirely between two polls and are
## never seen at all.
##
## Measured on `rating`'s MAINMENU, whose 449-frame opening has exactly one exit
## (`on exitFrame / if the mouseDown then go("mainscreen")`), driving real button
## events at its own 8 fps:
##
##   press held   before   after
##   ~35 ms       2 of 8   8 of 8
##   ~60 ms       2 of 8   8 of 8
##   ~90 ms       7 of 8   8 of 8
##
## The player's report was "clicking does not skip the opening". Every harness in
## `gate.sh` held the button for longer than a hand does, so none of them could
## see it, and a click that works two times in eight reads as a hit-test bug
## rather than a timing one.
##
## ## What is asserted
##
## The player-visible half first: on the movie in front of it, a click of
## `--press` process frames must move the playhead to `--reach` **every time**.
## Not "usually" -- an intermittent click is the fault, so a rate is the
## measurement and 100% is the bar.
##
## Then the mechanism, because the first check can also pass for the wrong
## reason (a click long enough to span a step proves nothing):
##
## - a press outlives its own release, until a score step has been able to see it
## - one press is seen by exactly one step, so charge-and-fire does not fire
##   twice for one click (`blaegoz` and CHESS both write
##   `if the mouseDown then go(marker(1)) else go(marker(0))`)
## - a button genuinely still held keeps reading down across several steps
##
## Title-agnostic in the rule and corpus-aware in the subject, as
## `tools/playhead_escape.gd` is: the movie and marker are arguments, and what is
## asserted about them names neither.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _play(h)
	quit(h.finish("a click shorter than a frame still reaches the movie"))


## Feed the engine a real button transition. `parse_input_event` is buffered, so
## the flush is not tidiness: without it `Input.is_mouse_button_pressed` still
## answers the *previous* state for the rest of this frame, and a harness built
## on that measures its own buffering rather than the engine.
func _button(pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Let the movie run `ticks` of its *own* clock, up to `cap_ms` of real time.
## Score ticks rather than seconds for the reason `playhead_escape.gd` gives: how
## much *movie* was watched has to be the same on a loaded machine as on an idle
## one.
func _run_ticks(preview: Node, ticks: int, cap_ms: int) -> void:
	var until := int(preview.get("_ticks")) + ticks
	var started := Time.get_ticks_msec()
	while int(preview.get("_ticks")) < until \
			and Time.get_ticks_msec() - started < cap_ms:
		await process_frame


func _play(h: Harness) -> bool:
	var args := Args.parse()
	var label := Args.text(args, "label", "ches1")
	var press_frames := Args.number(args, "press", 1)
	var tries := Args.number(args, "tries", 6)
	var case := "@%s: a %d-frame press is seen by the movie's own poll" % [
		label, press_frames]
	h.begin(case)

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	if not h.check("the movie's own tick counter is readable",
			preview.get("_ticks") != null):
		return true
	if not h.check("the preview answers `the mouseDown`",
			preview.has_method("mouse_button_down")):
		return true

	var labels = preview.get("_labels")
	var target := Args.number(args, "reach", -1)
	if not h.check("the movie has a marker called `%s`" % label,
			labels != null and labels.labels.has(label.to_lower())):
		return true
	var from := int(labels.labels[label.to_lower()])
	if target < 0:
		# The marker after the one clicked on, which is where every one of these
		# handlers sends the playhead: they all end in `go(marker(1))`.
		for marker in labels.markers:
			var at := int(marker.get("frame", -1))
			if at > from:
				target = at
				break
	if not h.check("there is a frame for the click to reach", target > from,
			"from f%d to f%d" % [from, target]):
		return true

	# ------------------------------------------------ what the player can see
	var settle := Args.number(args, "settle", 12)
	var reached := 0
	var where := Vector2(320, 240)
	for attempt in tries:
		preview.call("lingo_go_label", label)
		await _run_ticks(preview, settle, 30000)
		var before := int(preview.get("_index"))
		var began := Time.get_ticks_msec()
		_button(true, where)
		preview.call("route_press", where)
		for i in press_frames:
			await process_frame
		_button(false, where)
		preview.call("route_release", where)
		var held := Time.get_ticks_msec() - began
		# Two score ticks, because the poll is in `exitFrame`: the click cannot be
		# answered until the movie takes a step, and the step it takes may be the
		# one already under way when the button went down.
		await _run_ticks(preview, 2, 30000)
		var after := int(preview.get("_index"))
		if after >= target:
			reached += 1
		print("   try %d: %d ms held, f%d -> f%d  %s" % [
			attempt, held, before, after,
			"reached f%d" % target if after >= target else "MISSED"])
	h.check("every one of %d click(s) reached f%d" % [tries, target],
		reached == tries, "%d of %d" % [reached, tries])

	# ---------------------------------------------------------- the mechanism
	_button(true, where)
	preview.call("route_press", where)
	await process_frame
	_button(false, where)
	preview.call("route_release", where)
	var survived: bool = preview.call("mouse_button_down")
	h.check("a press outlives its own release", survived,
		"" if survived else "`the mouseDown` went false before the movie could step")
	await _run_ticks(preview, 2, 30000)
	var still_down: bool = preview.call("mouse_button_down")
	h.check("and is consumed by the step that sees it", not still_down,
		"still down two score ticks after the release" if still_down else "")

	_button(true, where)
	preview.call("route_press", where)
	await _run_ticks(preview, 3, 30000)
	var held_down: bool = preview.call("mouse_button_down")
	h.check("a button still held still reads down", held_down,
		"" if held_down else "went false while the button was down")
	_button(false, where)
	preview.call("route_release", where)
	await _run_ticks(preview, 2, 30000)
	h.check("and reads up once it is let go",
		not bool(preview.call("mouse_button_down")))
	h.complete(case)
	return true
