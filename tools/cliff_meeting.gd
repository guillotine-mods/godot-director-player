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

const Driver := preload("res://tools/lib/driver.gd")
const Harness := preload("res://tools/lib/harness.gd")
const Hooks := preload("res://tools/lib/game_hooks.gd")

## Long enough for the whole conversation to play out at 8 fps with its speech.
const BUDGET_MS := 420000
## Frames spent looking at a prompt before picking a line, as a player would.
const DWELL_FRAMES := 120
## After clicking, ignore the prompt long enough for the score to leave it.
const AFTER_CLICK_FRAMES := 600

var _h := Harness.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_h.begin("the cliff meeting")
	if await _play():
		_h.complete("the cliff meeting")
	quit(_h.finish())


## Returns whether it ran to a conclusion, not whether the checks passed. A
## GDScript runtime error would abort this handler and hand `_run` `false`, which
## leaves the case open and reports it rather than ending the run early and quiet.
func _play() -> bool:
	var hooks := Hooks.new()
	var driver := Driver.new(self, hooks)

	# Arriving at the cliff with `murder1` pending is what fires the meeting.
	driver.open({
		"movie": "DAY1", "label": "clif2",
		"flags": {"lingo_frames": true, "lingo_clicks": true},
	})
	if not _h.check("walking to clif2 fires the meeting",
			driver.movie().to_upper() == "MURDER1", driver.movie()):
		return true

	var run: Dictionary = await driver.run_for(BUDGET_MS, {
		"click_prompts": true,
		"dwell": DWELL_FRAMES,
		"after_click": AFTER_CLICK_FRAMES,
		"until_movie_change": true,
	})
	var clicks := int(run["clicks"])
	var seconds := int(run["elapsed_ms"]) / 1000

	_h.check("both dialogue prompts offer a choice", clicks == 2,
		"%d prompts at frames %s" % [clicks, str(run["click_frames"])])
	_h.check("the scene leaves MURDER1", bool(run["movie_changed"]),
		"" if run["movie_changed"] else "still in MURDER1:%d after %d s" % [
			driver.frame(), seconds])
	_h.check("it returns to the DAY1 hub", driver.movie().to_upper() == "DAY1", driver.movie())
	var state: Node = hooks.game_state(self)
	_h.check("the meeting marks itself done, so it cannot retrigger",
		state.is_meeting_done("murder1"), str(Array(state.meetings)))

	print("   %d s, %d clicks at frames %s" % [seconds, clicks, str(run["click_frames"])])
	return true
