extends SceneTree
## Does `updateStage` redraw the stage *inside* the handler that called it?
##
##   godot --headless --path . --script tools/update_stage.gd -- --root piposh2 --boot strtgame.dir
##
## 3,717 sites across the six titles under `games/`, and every one of them wants
## the same thing: Director paints the stage on the spot and returns, so a
## `repeat` loop that moves a sprite and calls this *animates*. With the name
## bound to nothing the loop drew once, when the handler ended, and the sprite
## teleported from where it started to where it stopped.
##
## The assertion has to be about a paint that happened **before the handler
## returned**, because a paint afterwards is what the engine already did. Two
## observables carry that, and they are the node's own rather than anything this
## file installs:
##
##   - `_repaints`, incremented by `director_preview.gd:repaint_now()`.
##   - `_last_member`, which `stage_paint.paint_frame` writes for **every**
##     sprite it paints, before it asks the cast for artwork. So a handler that
##     puts member A in a channel, calls `updateStage`, and then puts member B in
##     the same channel leaves the node reading B and the *paint* remembering A.
##     Nothing but a mid-handler paint can produce that pair, and it is the same
##     evidence a player has when they see the intermediate frame.
##
## Godot's own `_draw` is counted alongside, through the `draw` signal, and must
## not fire during any of it: if it did, the paint would be arriving at the end
## of the process frame after all and the loop would still be a teleport.
##
## Title-agnostic. The channel and the member numbers are read out of whatever
## frame the configured boot movie starts on; nothing here names a room, a
## channel or a member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")

var _preview: Node = null
var _interp = null
var _draws := 0


func _init() -> void:
	var h := Harness.new()
	Args.parse()
	_preview = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(_preview)
	await process_frame
	await process_frame
	_interp = _preview.get("_interpreter")
	# Let the movie reach a frame with something on it. A boot movie's frame 0
	# is often empty, and a harness that asserted over an empty stage would pass
	# by drawing nothing -- which is the `EMPTY` case `gate.sh` refuses. Real
	# frames, not a synthetic tick loop (`AGENTS.md`).
	var channel := _painted_channel()
	for _i in 120:
		if channel > 0:
			break
		await create_timer(0.02).timeout
		channel = _painted_channel()
	# Connected only now, so the frame loop's own paints are not counted against
	# the handlers below.
	_preview.draw.connect(func() -> void: _draws += 1)

	h.begin("the harness has a painted frame to drive")
	h.check("the preview booted a score", _preview.get("_score") != null)
	h.check("and an interpreter", _interp != null)
	h.check("and a channel the last paint drew (ch%d)" % channel, channel > 0,
		"every check below moves a member through this channel and asks what "
		+ "the paint saw")
	h.complete("the harness has a painted frame to drive")
	if _interp == null or channel <= 0:
		_preview.queue_free()
		await process_frame
		quit(h.finish("`updateStage` paints inside the handler"))
		return

	_one_paint(h, channel)
	_a_loop_animates(h, channel)
	_does_not_step_the_movie(h, channel)
	_does_not_suspend(h)
	_spends_a_puppet_transition(h)
	_same_painter(h)

	# Nothing above awaited, deliberately: a `_draw` between two of these cases
	# would repaint the stage from the state the previous case left and the
	# "what did the paint see" evidence would be the frame loop's rather than the
	# handler's. This is the first yield since the connection was made.
	var drew_during: int = _draws
	# A real step, not one process frame: the frame loop asks for a repaint when
	# the clock says a step is due, and at 8 fps that is not every frame.
	await create_timer(0.4).timeout
	h.begin("Godot's own paint stayed out of it")
	h.check(
		"`_draw` did not fire once while the handlers ran (%d)" % drew_during,
		drew_during == 0,
		"if it did, the paints being counted could be the message queue's at the "
		+ "end of the frame rather than the handler's, and the whole file proves "
		+ "nothing")
	h.check(
		"and it fires normally afterwards (%d)" % _draws,
		_draws > 0,
		"the synchronous path must not have taken the ordinary one away")
	h.complete("Godot's own paint stayed out of it")

	_preview.queue_free()
	await process_frame
	quit(h.finish("`updateStage` paints inside the handler"))


# ------------------------------------------------------------------- cases


## One call, one paint, and the paint saw the state as it was at the call.
func _one_paint(h, channel: int) -> void:
	h.begin("one `updateStage` is one paint of the stage as it stands")
	var before: int = _preview.get("_repaints")
	var calls: int = _preview.get("_update_stage_calls")
	_run("""
		puppetSprite %d, TRUE
		set the memberNum of sprite %d to 4001
		updateStage
		set the memberNum of sprite %d to 4002
	""" % [channel, channel, channel])
	var after: int = _preview.get("_repaints")
	h.check(
		"the call reached the arm (%d -> %d)"
			% [calls, int(_preview.get("_update_stage_calls"))],
		int(_preview.get("_update_stage_calls")) == calls + 1,
		"it was in the host's IGNORED list, which answered VOID and did nothing")
	h.check("and painted once (%d -> %d)" % [before, after], after == before + 1)
	h.check(
		"the paint saw member 4001, the value at the call, while the channel "
		+ "now holds 4002 (paint saw %d, channel reads %d)"
			% [_painted_member(channel), _channel_member(channel)],
		_painted_member(channel) == 4001 and _channel_member(channel) == 4002,
		"a paint that only happened after the handler would have seen 4002, "
		+ "which is exactly the teleport this closed")
	h.complete("one `updateStage` is one paint of the stage as it stands")


## The reason the name exists: a loop that draws each step.
func _a_loop_animates(h, channel: int) -> void:
	h.begin("a `repeat` loop that calls it draws every step, not just the last")
	var before: int = _preview.get("_repaints")
	_run("""
		puppetSprite %d, TRUE
		repeat with i = 1 to 8
			set the memberNum of sprite %d to 4100 + i
			updateStage
		end repeat
		set the memberNum of sprite %d to 4200
	""" % [channel, channel, channel])
	var painted: int = int(_preview.get("_repaints")) - before
	h.check(
		"eight iterations painted eight times (%d)" % painted,
		painted == 8,
		"one paint would mean the frames in between were never on the stage, "
		+ "which is a teleport wearing an animation's clothes")
	h.check(
		"and the last paint was the loop's last step, not the line after it "
		+ "(paint saw %d, channel reads %d)"
			% [_painted_member(channel), _channel_member(channel)],
		_painted_member(channel) == 4108 and _channel_member(channel) == 4200)
	h.complete("a `repeat` loop that calls it draws every step, not just the last")


## §9.1: it redraws *without advancing the frame*. The reference sends no event
## and moves no playhead -- it renders the window and returns.
func _does_not_step_the_movie(h, channel: int) -> void:
	h.begin("it redraws without advancing the frame")
	var frame: int = _preview.get("_index")
	var sent: Dictionary = _preview.get("_sent")
	var exits := int(sent.get("exitFrame", 0))
	var enters := int(sent.get("enterFrame", 0))
	_run("repeat with i = 1 to 4\n  updateStage\nend repeat")
	var now: Dictionary = _preview.get("_sent")
	h.check("the playhead has not moved (frame %d)" % int(_preview.get("_index")),
		int(_preview.get("_index")) == frame)
	h.check(
		"no `exitFrame` was sent (%d)" % (int(now.get("exitFrame", 0)) - exits),
		int(now.get("exitFrame", 0)) == exits)
	h.check(
		"no `enterFrame` was sent (%d)" % (int(now.get("enterFrame", 0)) - enters),
		int(now.get("enterFrame", 0)) == enters,
		"a redraw is not a frame; binding this to the step loop would make every "
		+ "one of the 3,717 sites a tick")
	_run("puppetSprite %d, FALSE" % channel)
	h.complete("it redraws without advancing the frame")


## Unlike `play` and `go` (§6.1 step 18) it does **not** suspend the handler.
func _does_not_suspend(h) -> void:
	h.begin("it does not suspend the handler that called it")
	var frozen: Array = _preview.get("_frozen_lingo")
	var parked := frozen.size()
	_run("""
		global updateStageTail
		set updateStageTail to 0
		updateStage
		set updateStageTail to 42
	""")
	var globals: Dictionary = _interp.globals
	h.check(
		"the statement after it ran in the same call (tail = %s)"
			% str(globals.get("updatestagetail", "<unset>")),
		int(globals.get("updatestagetail", 0)) == 42,
		"a suspending arm would have parked the handler here and the tail would "
		+ "wait for the next frame step, which is `go`'s behaviour and not this one")
	h.check(
		"and nothing was parked (%d -> %d)"
			% [parked, (_preview.get("_frozen_lingo") as Array).size()],
		(_preview.get("_frozen_lingo") as Array).size() == parked)
	h.complete("it does not suspend the handler that called it")


## `lingo-builtins.cpp:b_updateStage` plays a pending puppet transition here and
## drops it, rather than leaving it armed for the next frame change.
func _spends_a_puppet_transition(h) -> void:
	h.begin("a pending `puppetTransition` is spent by the redraw (§10)")
	var played: int = _preview.get("_transitions_played")
	_run("puppetTransition 1, 16, 1")
	var armed: Dictionary = _preview.get("_puppet_transition")
	h.check("the transition is armed", not armed.is_empty())
	_run("updateStage")
	h.check(
		"the redraw played it (%d -> %d)"
			% [played, int(_preview.get("_transitions_played"))],
		int(_preview.get("_transitions_played")) == played + 1)
	h.check(
		"and consumed it, so the next frame change does not play it again",
		(_preview.get("_puppet_transition") as Dictionary).is_empty(),
		"the reference deletes the puppet transition on the spot; leaving it "
		+ "armed would wipe the next `go` for no reason a script asked for")
	h.complete("a pending `puppetTransition` is spent by the redraw (§10)")


## The synchronous path is the *same* painter, not a cut-down copy of it.
##
## Pixels are the real assertion and cannot be taken here -- a headless run has
## no rasteriser -- so this compares what the paint *recorded*: `_text_drawn` is
## cleared and rebuilt from scratch on every pass through `_paint`, one entry per
## field sprite with its member, its text, its rect and the number of lines that
## reached the canvas. A synchronous paint that skipped fields, or ran a
## different sprite loop, produces a different table.
##
## The pixel measurement it stands in for was taken windowed and is written down
## in `director/director_paint.gd`: 0 differing pixels between `_draw` and
## `repaint_now` over a `SEA1.dir` frame and a `SAVELOAD.dir` frame with nine
## fields on it. It was 18,499 and 48,220 before `Paint.text` passed the
## oversampling `_draw` was already using, which is the one way the two entry
## points could differ and the reason that argument is spelled out rather than
## defaulted.
func _same_painter(h) -> void:
	h.begin("`updateStage` runs the same painter Godot's `_draw` runs")
	var through_lingo: Dictionary = (_preview.get("_text_drawn") as Dictionary).duplicate(true)
	_preview.call("_paint")
	var again: Dictionary = (_preview.get("_text_drawn") as Dictionary).duplicate(true)
	h.check(
		"the record of what was drawn is the same table either way (%d field(s))"
			% again.size(),
		str(through_lingo) == str(again),
		"`_text_drawn` is rebuilt from scratch by every pass through `_paint`, so "
		+ "two entry points that disagree here are two painters")
	h.complete("`updateStage` runs the same painter Godot's `_draw` runs")


# ----------------------------------------------------------------- reading


## A channel the last paint drew **and** the frame on screen still holds.
##
## Both halves matter: `_last_member` is a "last seen" record and keeps a channel
## the playhead has since left, so a channel taken from it alone can be one this
## frame never paints -- and then nothing the handlers below do would update it,
## and every check would fail for a reason that has nothing to do with
## `updateStage`. The lowest is taken so the choice is stable between runs.
func _painted_channel() -> int:
	var last: Dictionary = _preview.get("_last_member")
	var best := 0
	for value in _preview.call("frame_sprites"):
		var sprite: Dictionary = value
		var channel := int(sprite["channel"])
		if channel <= 0 or not last.has(channel):
			continue
		if (_preview.call("_effective", sprite) as Dictionary).is_empty():
			continue
		if best == 0 or channel < best:
			best = channel
	return best


## The member id the most recent paint of this channel recorded.
func _painted_member(channel: int) -> int:
	var last: Dictionary = _preview.get("_last_member")
	return int(last.get(channel, -1))


## The member id the channel holds *now*, which is what a script reads back.
func _channel_member(channel: int) -> int:
	return int(_preview.call("lingo_sprite_prop", channel, "membernum"))


## One handler, compiled and run against the live movie's interpreter.
func _run(source: String) -> void:
	var body := ""
	for raw in source.split("\n"):
		var line := str(raw).strip_edges()
		if line != "":
			body += "  " + line + "\n"
	var script := Compiler.new().compile_source(
		"on probe\n%send\n" % body, "UpdateStageProbe")
	if script.is_empty():
		push_warning("update_stage: probe did not compile:\n%s" % body)
		return
	_interp.call_handler("probe", [], script)
