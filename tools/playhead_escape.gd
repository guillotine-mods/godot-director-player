extends SceneTree
## Can the movie still get anywhere? The mirror of `tools/movie_churn.gd`.
##
##   godot --headless --path . --script tools/playhead_escape.gd
##   godot --headless --path . --script tools/playhead_escape.gd -- --cold
##   godot --headless --path . --script tools/playhead_escape.gd -- \
##       --label field --channel 20 --ticks 600
##
##   --label L     the marker to click something on (default veranda)
##   --channel N   the sprite channel to click (default 18)
##   --ticks N     score ticks to watch after the click (default 480)
##   --settle N    score ticks to let the movie open in (default 60)
##   --arrive N    score ticks to let the room settle before clicking (default 24)
##   --cold        skip the boot chain: open the room's movie directly, which is
##                 what the F12 container picker and `--file` do
##   --via M       the movie the boot chain passes through (default EXODUS.DIR)
##   --room M      the movie the room is in (default PIP2DATA/DAY1.dir)
##
## `movie_churn` catches a movie that changes *too often*. This catches the other
## end: a playhead that can no longer reach anywhere new. Nothing else detected
## it. `skip_state` asserts "the movie can still move", and the case this was
## written from **passes that check** -- the playhead moves every single step,
## between two frames, for ever. Counting frame changes is not the question; the
## question is whether the set of frames it can reach is one the player can leave.
##
## ## What is asserted
##
## Over any window of `WINDOW` score ticks the playhead must either visit more
## than `TRAPPED` distinct frames, or something must be able to *say why not*:
## the clock naming a hold (a tempo delay, a transition, a wait-for-click, a
## wait-for-sound), or a sound playing that a `soundBusy` guard is waiting on.
## A room idling on `go to the frame` while it waits for a click is the first;
## a line of speech holding a cut scene still is the second. Two frames, no
## hold, and silence is none of them, and it is the shape a player reports as
## "it never comes back".
##
## Deliberately *not* asserted: that a clickable sprite is on offer. It was the
## first idea and it is wrong here -- this game's inventory HUD is on all 2,783
## frames of DAY1, so every frame of a cut scene the player cannot escape still
## offers fifteen sprites that answer a click.
##
## ## The reproduction
##
## DAY1's tail holds nine `<character>clicktalk` clips, each one frame of preamble
## and a `soundBusy` loop. `BehaviorScript 250` is the loop body:
##
##     on exitFrame
##       if not soundBusy(1) then
##         go(marker(0))
##       end if
##     end
##
## Its only exit is the clip's first frame having started a sound. That frame
## (`BehaviorScript 291` for `tofclicktalk`) looks its line up in the `master`
## cast's `clickoncharacter` field by the key `"tofday" & globalday` -- so with
## `globalday` VOID the key is `"tofday"`, no line matches, nothing plays, and
## the two frames trade places until the player quits. The mouth keeps moving
## because a film loop advances on the movie's clock and not the playhead's,
## which is correct (`film_loop_view.gd`); the player character is gone because
## the clip's frames have no channel 30 at all and the restore that puts it back
## is on the exit path that is never reached. One fault, two reports.
##
## `globalday` is VOID exactly when DAY1 was not entered through `EXODUS`, which
## sets it -- so the default run here goes through the boot chain and passes, and
## `--cold` opens DAY1 directly and reproduces the report. That is the same gap
## `tools/boot_state.gd` reports as "every global the next room reads is set",
## from the other end: boot_state asserts the state, this asserts what the player
## can do with it.
##
## Corpus-aware on purpose, as `frame_events.gd` is: `tools/lib/` may not know
## which game is loaded, but a harness that asserts nothing about the movie in
## front of it is a tautology. The rule -- the detector below -- knows no movie.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Score ticks the frame set is measured over, and the most frames a trap may span.
##
## Score ticks, not process frames: the window has to mean the same length of
## *movie* whatever rate the machine renders at, and headless renders four times
## faster than the score runs. `host._ticks` is the movie's own clock, and it
## keeps counting through a hold, which is what makes it the right unit here --
## a held frame is still time the player is sitting through.
##
## `WINDOW` is generous: 120 ticks is 15 s of the 8 fps this movie runs at, longer
## than any gap between two lines of speech in a clip. `TRAPPED` is the *size* of
## the reachable set, not a repeat count -- a room's idle loop cycles the whole
## span from its marker to its last frame, 31 frames for the veranda.
const WINDOW := 120
const TRAPPED := 3
## Channels a sound may be playing on. Director has eight; this game uses four.
const SOUND_CHANNELS := 8


## Watch the playhead in real time and report the tightest trap it fell into.
##
## Real frames are awaited rather than ticked synthetically, and that is
## load-bearing rather than tidy: a `for i in N: tick()` loop advances the
## runtime's clock and not the audio server's, so every sound stays busy for ever,
## every `soundBusy` guard holds, and this detector would excuse every trap it
## was built to find. That is bugs.md 22, diagnosed wrong twice.
##
## `budget` is in score ticks and `cap_ms` is only the liveness bound, for the
## same reason the window is: how much *movie* was watched has to be the same on a
## loaded machine as on an idle one. Measured while writing this — a 30 s watch on
## a machine also running `gate.sh` did not contain one full window and reported
## the parked case green.
##
## Returns `{trapped, frames, ticks, hold_reasons, sound, tail}`.
static func watch(tree: SceneTree, preview: Node, audio: Node, budget: int,
		cap_ms: int) -> Dictionary:
	var seen: Array[int] = []
	var reasons: Dictionary = {}
	var sounded := false
	var worst: Dictionary = {}
	var tail: Array[int] = []
	var start := Time.get_ticks_msec()
	var clock = preview.get("_clock")
	var last_tick := -1
	var began := int(preview.get("_ticks"))
	while int(preview.get("_ticks")) - began < budget \
			and Time.get_ticks_msec() - start < cap_ms:
		await tree.process_frame
		var frame := int(preview.get("_index"))
		if tail.is_empty() or tail[-1] != frame:
			tail.append(frame)
		var reason := str(clock.hold_reason())
		if reason != "":
			reasons[reason] = int(reasons.get(reason, 0)) + 1
		var busy := false
		for channel in range(1, SOUND_CHANNELS + 1):
			if bool(audio.call("sound_busy", channel)):
				busy = true
				sounded = true
				break
		# A tick that can say why the playhead is not moving is not a trap, and
		# neither is one that is waiting on a sound that is actually playing. The
		# window is cleared rather than annotated: what is being looked for is
		# `WINDOW` *consecutive* score ticks with nothing to show for them.
		#
		# Read every process frame, because a hold can be armed and released
		# between two score ticks and a poll that only looked on the tick would
		# miss it -- but recorded once per score tick, so the window is a length
		# of movie and not a length of wall clock.
		if reason != "" or busy:
			seen.clear()
			last_tick = int(preview.get("_ticks"))
			continue
		var now := int(preview.get("_ticks"))
		if now == last_tick:
			continue
		last_tick = now
		seen.append(frame)
		if seen.size() < WINDOW:
			continue
		var distinct: Dictionary = {}
		for f in seen:
			distinct[f] = true
		if distinct.size() <= TRAPPED and (
				worst.is_empty() or distinct.size() < int(worst["span"])):
			var frames: Array = distinct.keys()
			frames.sort()
			worst = {"span": distinct.size(), "frames": frames}
		seen.remove_at(0)
	return {
		"trapped": not worst.is_empty(),
		"frames": worst.get("frames", []),
		"ticks": int(preview.get("_ticks")) - began,
		"hold_reasons": reasons,
		"sound": sounded,
		"tail": tail.slice(maxi(0, tail.size() - 10)),
	}


## Let the movie run `ticks` of its *own* clock, up to `cap_ms` of real time.
##
## Score ticks rather than seconds because the setup steps have to mean the same
## amount of movie on a loaded machine as on an idle one: a fixed wall-clock
## settle is the difference between arriving in the room and still being in the
## movie's opening region, and the harness then fails on "no sprite to click"
## rather than on anything it is about. The cap is the liveness bound.
static func run_ticks(tree: SceneTree, preview: Node, ticks: int, cap_ms: int) -> void:
	var until := int(preview.get("_ticks")) + ticks
	var start := Time.get_ticks_msec()
	while int(preview.get("_ticks")) < until and Time.get_ticks_msec() - start < cap_ms:
		await tree.process_frame


## The centre of the sprite on `channel` in the frame the playhead is on, or
## `Vector2(-1, -1)` when the frame does not hold one.
static func sprite_centre(preview: Node, channel: int) -> Vector2:
	var score = preview.get("_score")
	if score == null:
		return Vector2(-1, -1)
	for s_value in score.frame(int(preview.get("_index"))).get("sprites", []):
		var raw: Dictionary = s_value
		if int(raw.get("channel", 0)) != channel:
			continue
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			return Vector2(-1, -1)
		var rect: Rect2 = preview.call("_stage_rect", sprite)
		return rect.get_center()
	return Vector2(-1, -1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _play(h)
	quit(h.finish("the playhead can still reach somewhere new"))


## Returns whether it ran to a conclusion rather than whether the checks passed:
## a GDScript runtime error aborts this handler, and an open case reports FAIL
## rather than ending the run quietly. See `harness.gd`.
func _play(h: Harness) -> bool:
	var args := Args.parse()
	var room := Args.text(args, "room", "PIP2DATA/DAY1.dir")
	var label := Args.text(args, "label", "veranda")
	var channel := Args.number(args, "channel", 18)
	var cold := Args.flag(args, "cold")
	var case := "%s @%s: clicking channel %d leaves the player able to move" % [
		room.get_file(), label, channel]
	h.begin(case)

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if not h.check("AudioDirector is in the tree", audio != null):
		return true
	# `_ticks` is the window's unit and it is *not* in `tools/preview_surface.gd`'s
	# asserted list, so a rename would make `get()` answer null, `int(null)` answer
	# 0, the window never fill, and this harness go green over a movie it never
	# looked at. `scenes/preview/README.md` names that failure mode; this is the
	# guard against it.
	if not h.check("the movie's own tick counter is readable",
			preview.get("_ticks") != null):
		return true

	# The boot chain, or deliberately not it. `EXODUS` is where this title sets
	# the day; opening the room's movie directly is what the container picker
	# does, and it is the state the bug was reported from.
	if not cold:
		preview.call("lingo_go_movie", Args.text(args, "via", "PIP2DATA/EXODUS.DIR"), null)
		for i in Args.number(args, "via-steps", 400):
			preview.call("_advance")
	preview.call("lingo_go_movie", room, null)
	await process_frame
	if not h.check("%s is playing" % room.get_file(),
			str(preview.call("movie_name")).to_lower() == room.get_file().to_lower(),
			str(preview.call("movie_name"))):
		return true

	# Let the movie run its own opening frame -- `init all` is DAY1's, and it ends
	# by jumping to the room proper -- before asking it to go anywhere.
	await run_ticks(self, preview, Args.number(args, "settle", 60), 60000)
	preview.call("lingo_go_label", label)
	# Then let the room reach its own idle span, and take the sprite from whatever
	# frame of that span the playhead is on when it appears. A marker frame is the
	# room's *entry* -- it puppets, places and swaps -- and the sprite a player
	# clicks is the one standing in the loop the entry falls into, not the one on
	# the marker itself.
	#
	# The wait is unconditional and not "until the sprite is there": the marker
	# frame carries a channel 18 of its own, so a loop that stopped at the first
	# frame holding one would click the entry's sprite, which answers nothing —
	# measured, `f942 -> f942`, the click dispatching no handler at all.
	await run_ticks(self, preview, Args.number(args, "arrive", 24), 30000)
	var centre := sprite_centre(preview, channel)
	var waited := 0
	while centre.x < 0.0 and waited < 40:
		await run_ticks(self, preview, 1, 5000)
		waited += 1
		centre = sprite_centre(preview, channel)
	if not h.check("the room has a sprite on channel %d to click" % channel,
			centre.x >= 0.0, "frame %d" % int(preview.get("_index"))):
		return true

	var before := int(preview.get("_index"))
	# The real mouse-down/mouse-up pair, as `tools/mouse_events.gd` drives it: the
	# press decides the recipient and the release is what dispatches `mouseUp`,
	# which is the handler that starts the clip.
	preview.call("route_press", centre)
	preview.call("route_release", centre)
	var after := int(preview.get("_index"))
	h.check("the click was answered", after != before, "f%d -> f%d" % [before, after])

	# Four windows' worth, so a trap has to be entered and *stayed in* rather than
	# passed through, and a clip that takes three windows to speak its lines still
	# has room to end.
	var seen: Dictionary = await watch(
		self, preview, audio, Args.number(args, "ticks", WINDOW * 4), 300000)
	print("   clicked f%d -> f%d, ended on f%d after %d score tick(s)" % [
		before, after, int(preview.get("_index")), int(seen["ticks"])])
	print("   last frames: %s" % str(seen["tail"]))
	print("   holds the clock could name: %s   any sound played: %s" % [
		JSON.stringify(seen["hold_reasons"]), "yes" if seen["sound"] else "no"])
	if not cold:
		print("   `--cold` runs the same click without the boot chain: bugs.md 36")
	var rule := "the playhead is never confined to %d frame(s) or fewer for %d score ticks with nothing holding it" % [
		TRAPPED, WINDOW]
	h.check(rule, not bool(seen["trapped"]),
		"trapped on %s" % str(seen["frames"]) if seen["trapped"] else "")
	h.complete(case)
	return true
