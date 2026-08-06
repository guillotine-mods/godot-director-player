extends SceneTree
## The cliff meeting, played the way a player plays it, pass/fail.
##
##   godot --headless --script tools/cliff_meeting.gd
##
## MURDER1 is the only day-1 meeting built around dialogue prompts, and it was
## twice reported as an infinite loop it is not (bugs.md 22). What the loop
## actually is: frames 489-508 and 676-695 each end on `go to marker(0)`, so the
## span cycles until the player clicks one of the subtitle lines. This asserts
## the whole scene — that both prompts offer a choice, that clicking one leaves
## the loop, that the score reaches its `go movie day1, label clif2` exit, and
## that the meeting marks itself done so it cannot retrigger.
##
## Two things this harness had to learn, both of which silently produce a false
## "the scene is stuck":
##
##   * **Real time is load-bearing.** The speech frames hold on `soundBusy(1)`.
##     A tight `for i in N: tick()` loop advances the runtime's clock and not the
##     audio server's, so no sound ever finishes and every guard holds for ever.
##     The `await process_frame` is the whole point; the run takes minutes.
##   * **A wait loop cycles a span, so same-frame stall detection never fires.**
##     The playhead moves every step while waiting. What marks a prompt is that
##     the frame is offering a clickable sprite, not that it stopped moving.

## Long enough for the whole conversation to play out at 8 fps with its speech.
const BUDGET_MS := 420000
## Frames spent looking at a prompt before picking a line, as a player would.
const DWELL_FRAMES := 120
## After clicking, ignore the prompt long enough for the score to leave it.
const AFTER_CLICK_FRAMES := 600

var _fails := 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["ok  " if ok else "FAIL", name, ("  (%s)" % detail) if detail != "" else ""])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings: Node = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true
	var state: Node = root.get_node("GameState")
	state.new_game()

	var rt: RefCounted = load("res://director/director_runtime.gd").new()
	rt.boot()

	# Arriving at the cliff with `murder1` pending is what fires the meeting.
	rt.goto_movie("DAY1", null, {"label": "clif2"})
	_check("walking to clif2 fires the meeting", rt.loader.movie_name.to_upper() == "MURDER1",
		rt.loader.movie_name)
	if rt.loader.movie_name.to_upper() != "MURDER1":
		quit(1)
		return

	var start_ms := Time.get_ticks_msec()
	var dwell := 0
	var clicks := 0
	var prompts: Array = []
	var reached_exit := false
	while Time.get_ticks_msec() - start_ms < BUDGET_MS:
		await process_frame
		rt.tick(0.016)
		if rt.loader.movie_name.to_upper() != "MURDER1":
			reached_exit = true
			break

		var offered: Array = rt.clickable_sprites(rt.loader.get_frame(rt.frame_index))
		if offered.is_empty():
			dwell = 0
			continue
		dwell += 1
		if dwell <= DWELL_FRAMES:
			continue
		dwell = -AFTER_CLICK_FRAMES
		clicks += 1
		var picked: Dictionary = offered[0]
		prompts.append(rt.frame_index)
		print("   prompt at frame %d, clicking channel %d" % [
			rt.frame_index, int(picked.get("channel", 0))])
		rt.perform_click(rt.sprite_stage_rect(picked).get_center())

	var elapsed := Time.get_ticks_msec() - start_ms
	_check("both dialogue prompts offer a choice", clicks == 2,
		"%d prompts at frames %s" % [clicks, str(prompts)])
	_check("the scene leaves MURDER1", reached_exit,
		"" if reached_exit else "still in MURDER1:%d after %d s" % [rt.frame_index, elapsed / 1000])
	_check("it returns to the DAY1 hub", rt.loader.movie_name.to_upper() == "DAY1",
		rt.loader.movie_name)
	_check("the meeting marks itself done, so it cannot retrigger",
		state.is_meeting_done("murder1"), str(Array(state.meetings)))

	print("%s (%d s, %d clicks)" % [
		"PASS" if _fails == 0 else "FAIL", elapsed / 1000, clicks])
	quit(1 if _fails > 0 else 0)
