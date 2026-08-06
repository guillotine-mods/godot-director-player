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
## It also asserts what happens *after* the handover, because the reported loop
## was real and lived there. The first version of this harness stopped at the
## movie change, and stopping one frame early is what let it pass while the
## return landed on DAY1 frame 1, ran `init all`, reset `meetings`, emptied the
## inventory and put the player back on the beach — a genuine endless loop the
## check "it returns to the DAY1 hub" could not see. Where a scene hands the
## player back, the invariant is where they are standing and what they still
## have, not which movie is loaded.
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
## Left alone in the room afterwards, long enough for an entry script to fire.
const SETTLE_MS := 30000

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

	# Carry something in, or the inventory check below has nothing to lose and
	# scores a pass either way. `init all` empties `objectsfield` line by line, so
	# one item is enough to tell a return from a restart. Added after `open`,
	# which starts a new game and would clear it.
	var state: Node = hooks.game_state(self)
	if not _h.check("the item carried in is a real one",
			state.add_inventory_item("camera"), str(Array(state.objects_field).slice(0, 2))):
		return true
	# Snapshot before the meeting, not after it: the restart this asserts against
	# happens *during* the return, so a snapshot taken on arrival is already the
	# emptied one and the check compares nothing to nothing.
	var carried := Array(state.objects_field)

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
	_h.check("the meeting marks itself done, so it cannot retrigger",
		state.is_meeting_done("murder1"), str(Array(state.meetings)))

	# `go("clif2", "day1.dir")` names the room it hands the player back to, and
	# landing anywhere else means landing in DAY1's init region, which restarts
	# the day. The frame is reported either way, because "which frame" is the
	# whole difference between a return and a restart.
	var landed: String = str(driver.runtime.label_near_frame(driver.frame()))
	_h.check("it hands the player back to the cliff, not to the top of DAY1",
		landed.begins_with("clif2"), "%s (frame %d, label %s)" % [
			driver.state(), driver.frame() + 1, landed if landed != "" else "none"])

	# Nothing is clicked from here. What the score does when left alone is the
	# question: DAY1 frame 1 falls through `init all` into `go("shore2")`.
	await driver.run_for(SETTLE_MS, {})
	var settled: String = str(driver.runtime.label_near_frame(driver.frame()))
	_h.check("the player is still at the cliff a while later",
		settled.begins_with("clif2"), "%s (label %s)" % [
			driver.state(), settled if settled != "" else "none"])
	_h.check("the day's progress survives the return",
		state.is_meeting_done("murder1"), str(Array(state.meetings)))
	_h.check("the inventory survives the return",
		Array(state.objects_field) == carried, str(Array(state.objects_field)))

	# The loop's closing edge: walking back into the room must not replay it.
	driver.go("DAY1", "clif2")
	_h.check("walking back to the cliff does not replay the meeting",
		driver.movie().to_upper() == "DAY1", driver.movie())

	print("   %d s, %d clicks at frames %s" % [seconds, clicks, str(run["click_frames"])])
	return true
