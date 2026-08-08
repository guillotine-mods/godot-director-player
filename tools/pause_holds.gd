extends SceneTree
## Where Director's `pause` leaves the playhead, and what a paused frame still is.
##
##   godot --headless --path . --script tools/pause_holds.gd -- --root piposh2 \
##       --file PIP2DATA/SAVELOAD.dir --label savegame2 --hotspot
##   godot --headless --path . --script tools/pause_holds.gd -- --root rating \
##       --boot BLAEGOZ.dir --label EgozKey --hotspot
##
## `pause` is the one hold in Director that does not name a destination. Every
## other one — `go`, `go to the frame`, `play done` — writes where the playhead is
## going, so this port could implement them by writing `_index` and setting
## `_held`. `pause` writes nothing, and the port therefore read the flag at the
## *top of a step*, which is one step too late: the handler that calls `pause` is
## an `exitFrame` handler, so by the time the flag is set the step has already
## decided to advance. The playhead parked one frame past the frame that paused,
## ran a `prepareFrame` and an `enterFrame` Director does not, and any hotspot
## scoped to the pausing frame was gone before the player could reach it —
## `docs/bugs-closed.md` 52, and it made a room of Rating unfinishable.
##
## Three invariants, and the first is the whole bug in one line:
##
##   * **the frame a step exits is the frame a `pause` leaves the playhead on**
##     (`reference/scummvm/score.cpp:443-452`: `nextFrameNumberToLoad` starts at
##     the current frame and only the `if (!_playbackPaused)` arm moves it);
##   * `continue` advances, and does **not** re-run the handler that paused
##     (`score.cpp:668-675`, `:827-828` — `_exitFrameCalled`). Without this the
##     first invariant turns a one-frame skip into a permanent lock: the room sits
##     on the pausing frame re-pausing itself on every click;
##   * an unpaused step still receives `exitFrame` for the frame it is on, which is
##     the regression the latch can cause and would break every room in every title
##     at once, so it is asserted beside it rather than trusted;
##   * `--hotspot`: **a paused frame keeps its click targets** — `score.cpp:701-702`
##     skips `killScriptInstances` while paused, so the behaviour that lifts the
##     pause is still there to be clicked. This is the player-visible half, and it is
##     the check that goes red on the old code with the words the bug report used:
##     *no sprite on the paused frame both declares `mouseUp` and wins a hit test*.
##
## **The pausing frame is found, not named.** The harness steps the movie and
## takes the first step that sets the flag, so it asserts about whatever the movie
## does; nothing here knows which title it is looking at.
##
## **What the gate does and does not cover.** `--hotspot` is in `gate.sh`'s `ALL`,
## on `PIP2DATA/SAVELOAD.dir` `savegame2` — the pinned corpus turns out to have a
## pause frame with ten `mouseUp` behaviours on it, so the case needs no Rating
## entry and gets one anyway by hand, above. What is **not** covered is the sharpest
## form of the third invariant, a frame that holds *itself* with `go to the frame`:
## see the note on `_self_hold_keeps_dispatching` for why no movie in either corpus
## reaches one under a headless drive, and `docs/bugs-closed.md` 52 for the gap
## stated where somebody will find it. `--hold <container>` exists to point the
## search at a movie that does, for whoever closes that.
##
## Steps the movie by calling `_advance` directly with the debug pause set, which
## is how `tools/click_trace.gd` drives it: the assertions are about the *step's*
## ordering, and a room holding on a sound wait would never reach a pause frame on
## the clock.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")

## How many steps to spend looking for the movie's first `pause`, and for a frame
## that holds itself. Bounded because a movie that never pauses is a legitimate
## answer and must not read as a hang.
const SEARCH_STEPS := 4000
## Steps to hold a self-holding frame for. Four is enough to tell "dispatched
## every step" from "dispatched once and then latched shut", which is the only
## thing this case can get wrong.
const HOLD_STEPS := 4


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	if preview.get("_score") == null:
		print("no score loaded")
		quit(1)
		return

	# **Two subjects, because no one movie is both.** A movie that pauses is a screen
	# the game opens deliberately and leaves within a few frames of doing it, which
	# is too short a window to go looking for a `go to the frame` in; a movie that
	# holds itself may never pause at all. `--hold` names the second one and is
	# visited first, because the pause cases end where the movie's own scripts
	# decided and there is no coming back to a known frame after that.
	var movie := Args.text(args, "file", "")
	var label := Args.text(args, "label", "")
	var hold_movie := Args.text(args, "hold", "")
	if hold_movie != "":
		preview.call("lingo_go_movie", hold_movie, null)
		for _i in 8:
			await process_frame
	# The debug pause, not the movie's: it stops the tick so that the only thing
	# moving the playhead is this file's own `_advance` calls.
	preview.set("_paused", true)
	print("%s  from frame %d of %d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame")),
		int(preview.get("_score").frame_count) - 1])
	print("")
	await _self_hold_keeps_dispatching(preview, h)

	if movie != "" or label != "":
		# Handed back to the clock for the switch: a movie change is entered by the
		# ticks after the call, not by the call, and `prepareMovie`, `startMovie` and
		# the first frame's own scripts run on those ticks.
		preview.set("_paused", false)
		if movie != "":
			preview.call("lingo_go_movie", movie, null)
			for _i in 8:
				await process_frame
		if label != "":
			preview.call("lingo_go_label", label)
			for _i in 8:
				await process_frame
		preview.set("_paused", true)
		print("")
		print("%s  from frame %d of %d" % [
			str(preview.call("movie_name")), int(preview.call("current_frame")),
			int(preview.get("_score").frame_count) - 1])
		print("")

	var paused_at := await _first_pause(preview, h)
	if paused_at >= 0:
		if Args.flag(args, "hotspot"):
			_paused_frame_keeps_its_hotspots(preview, h, paused_at)
		await _resumes_without_rerun(preview, h, paused_at)

	quit(h.finish("Director's `pause` holds the frame that paused"))


## Step until the movie pauses itself, and assert the playhead did not move past
## the frame whose handler did it. Returns that frame, or -1.
func _first_pause(preview: Node, h: Harness) -> int:
	var case_name := "a `pause` leaves the playhead on the frame that paused"
	h.begin(case_name)
	var host = preview.get("_host")
	var found := -1
	var stepped: Dictionary = {}
	var detail := ""
	# Already paused before a single step of ours is a *setup* failure and not a
	# quiet pass: there is no `exited` to compare a playhead against, so the case
	# cannot be answered and must not look answered.
	if bool(host.playback_paused):
		detail = "already paused on arrival; nothing to compare an `exited` against"
	else:
		var movie: String = str(preview.call("movie_name"))
		for _i in SEARCH_STEPS:
			stepped = preview.call("_advance")
			await process_frame
			if bool(host.playback_paused):
				found = int(stepped.get("exited", -1))
				break
			# A movie change means the search has left its subject. Following it
			# would assert about whichever room the game wandered into, which is
			# how a harness comes to pass for a reason nobody can reproduce.
			if str(preview.call("movie_name")) != movie:
				detail = "the movie changed to %s before any `pause`" % \
					str(preview.call("movie_name"))
				break
		if found < 0 and detail == "":
			detail = "no `pause` reached in %d steps" % SEARCH_STEPS
	if not h.check("the movie pauses itself", found >= 0, detail):
		h.complete(case_name)
		return -1
	# The invariant. `exited` is the frame `exitFrame` was sent for and `frame` is
	# where the step left the playhead; a `pause` from that handler must leave them
	# equal, and the defect was `frame` being `exited + 1`.
	h.check("the step that paused exited and stayed on frame %d" % found,
		int(stepped.get("frame", -1)) == found,
		"exited %d, left the playhead on %d" % [found, int(stepped.get("frame", -1))])
	h.check("the playhead reads that frame afterwards",
		int(preview.call("current_frame")) == found,
		"current_frame %d" % int(preview.call("current_frame")))
	h.complete(case_name)
	return found


## `continue` must advance, and must not hand the pausing handler a second turn.
func _resumes_without_rerun(preview: Node, h: Harness, paused_at: int) -> void:
	var case_name := "`continue` advances without re-running the handler that paused"
	h.begin(case_name)
	var host = preview.get("_host")
	var pauses_before := int((host.reached as Dictionary).get("pause", 0))
	host.call_builtin("continue", [])
	h.check("`continue` cleared the flag", not bool(host.playback_paused))
	var stepped: Dictionary = preview.call("_advance")
	await process_frame
	# The frame was already exited before the pause, so this step sends no
	# `exitFrame` at all -- which is what stops it pausing again.
	h.check("the resuming step sent no `exitFrame`",
		int(stepped.get("exited", -2)) == -1,
		"exited %d" % int(stepped.get("exited", -2)))
	h.check("`pause` was not reached again",
		int((host.reached as Dictionary).get("pause", 0)) == pauses_before,
		"%d -> %d" % [pauses_before, int((host.reached as Dictionary).get("pause", 0))])
	h.check("the playhead left frame %d" % paused_at,
		int(preview.call("current_frame")) != paused_at,
		"still on %d" % int(preview.call("current_frame")))
	h.complete(case_name)


## The regression guard for the latch.
##
## The latch can only ever go wrong in one direction — suppressing an `exitFrame`
## that was due — and the frame that shows it is any unpaused one: a step that is
## not held and not paused owes an `exitFrame` for the frame it is standing on, and
## a latch cleared in the wrong place eats the second one. That is asserted over
## `HOLD_STEPS` steps here and needs no particular movie, which is the point:
## `mainmenu.dir`-style pause screens and self-holding rooms are different movies,
## and this half has to hold in both.
##
## **What is asserted with a subject and what is only reported.** The sharpest form
## of the same property is a frame that holds *itself* with `go to the frame`, where
## the playhead does not move and the port's frame-entry hook early-returns —
## `frame_loop.gd:sync_frame_entry` returns when the index has not changed, so a
## latch cleared there instead of beside `enterFrame` would go deaf exactly there
## and nowhere else. Finding one has to be done by playing, and neither
## `strtgame.dir` nor `PIP2DATA/CHESS.dir` reaches its `go(the frame)` inside
## `SEARCH_STEPS` steps of a headless drive — CHESS's is inside a handler waiting on
## a move the harness does not make. So that case is **reported, not asserted**, and
## `docs/bugs-closed.md` 52 records the gap rather than leaving a check that is red
## for a reason no change to the engine can fix. The weaker assertion below does run
## everywhere and would catch a latch that is never cleared at all.
func _self_hold_keeps_dispatching(preview: Node, h: Harness) -> void:
	var case_name := "an unpaused step still receives `exitFrame` for the frame it is on"
	h.begin(case_name)
	var host = preview.get("_host")
	if bool(host.playback_paused):
		host.call_builtin("continue", [])
	var owed := 0
	var dispatched := 0
	var self_hold := -1
	var movie: String = str(preview.call("movie_name"))
	for _i in HOLD_STEPS:
		var before := int(preview.call("current_frame"))
		# A step that begins already holding a queued `go` owes no `exitFrame` --
		# Director sends none for a frame it is leaving that way (§6.1 step 7) -- so
		# it is not evidence either way and is not counted.
		var queued := bool(preview.get("_jump_queued"))
		var stepped: Dictionary = preview.call("_advance")
		await process_frame
		# The first pause ends the window: from there on, "no `exitFrame`" is the
		# correct answer rather than a suppressed one, and that is the *next* case's
		# subject rather than this one's.
		if bool(host.playback_paused):
			break
		if str(preview.call("movie_name")) != movie:
			break
		if queued:
			continue
		owed += 1
		if int(stepped.get("exited", -1)) == before:
			dispatched += 1
		if int(stepped.get("frame", -1)) == before:
			self_hold = before
	h.check("every one of %d unpaused steps exited the frame it was on" % owed,
		owed > 0 and dispatched == owed, "%d of %d" % [dispatched, owed])
	# Reported, not asserted -- see the note above this function.
	print("      (`go to the frame` subject: %s)" % (
		"frame %d, and it kept receiving `exitFrame`" % self_hold if self_hold >= 0
		else "none reached in this movie -- the sharper form of this case is uncovered"))
	h.complete(case_name)


## A paused frame keeps its click targets — `score.cpp:701-702` skips
## `killScriptInstances` while paused, so the behaviour that lifts the pause is
## still there to be clicked. Opt-in; see the header for why it is not in `ALL`.
func _paused_frame_keeps_its_hotspots(preview: Node, h: Harness, paused_at: int) -> void:
	var case_name := "the paused frame still answers the mouse"
	h.begin(case_name)
	var reachable: Array[String] = []
	for sprite in preview.call("frame_sprites"):
		var channel := int((sprite as Dictionary)["channel"])
		var script: Dictionary = preview.call("_sprite_script", channel, paused_at)
		if script.is_empty():
			continue
		if not bool(preview.get("_interpreter").call(
				"_script_has_handler", script, "mouseup")):
			continue
		var at: Variant = _reachable_point(preview, sprite, channel)
		if at == null:
			continue
		var point: Vector2 = at
		reachable.append("ch%d at (%d,%d)" % [channel, int(point.x), int(point.y)])
	h.check("a behaviour with `mouseUp` on frame %d is reachable by the mouse" % paused_at,
		not reachable.is_empty(),
		", ".join(reachable) if not reachable.is_empty()
			else "no sprite on the paused frame both declares `mouseUp` and wins a hit test")
	h.complete(case_name)


## A point the mouse can actually reach this sprite at, or null.
##
## Scanned rather than taken from the centre, and that is not fussiness: the key
## on Rating's desk is 91x24 with a transparent gap at its middle, so the centre
## of its rect reaches the sprite behind it. "Is there anywhere on this sprite a
## click lands" is the question a player asks.
func _reachable_point(preview: Node, sprite: Dictionary, channel: int):
	var rect: Rect2 = preview.call("_sprite_rect", sprite)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return null
	for iy in 5:
		for ix in 9:
			var at := rect.position + Vector2(
				rect.size.x * (ix + 0.5) / 9.0, rect.size.y * (iy + 0.5) / 5.0)
			if int(preview.call("_channel_at", at)) == channel:
				return at
	return null
