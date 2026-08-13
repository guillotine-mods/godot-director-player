extends SceneTree
## A film loop re-shown on a channel starts its animation again, even when the
## member it is re-shown with is the one that channel held last.
##
##   godot --script tools/film_loop_restart.gd -- --root piposh-dream
##
##   --root R    the corpus (default the config's)
##   --ticks N   process frames to play for (default 9000)
##
## Runs headless, which `gate.sh` requires of every entry. That is worth stating
## because the restart has two sources and only one of them needs a window:
## `preview/stage_paint.gd` calls `_note_member` per *drawn* sprite, and
## `director_preview.gd:lingo_set_sprite_prop` calls it per *assigned* member.
## Measured: with the assignment arm removed this fails headless too, reporting
## the same shape (drops starting at frames 27, 66, 93, 120), so the paint arm
## does run without a display and the check is not testing a window.
##
## ## What the number means
##
## A film loop's drawn frame is `_ticks - _loop_start[channel]`, and
## `director_film_loop.gd:frame_index` clamps a non-looping loop to its last frame. So a
## loop whose counter was not restarted does not animate *slightly* wrong -- it
## draws its final frame from the moment it appears. For a 14-frame fall that is
## the difference between watching a flowerpot drop and finding it already smashed
## on the ground.
##
## ## Why this container
##
## COMEIN's pot game is the corpus site and the only one that exercises the case,
## because it re-shows the *same* loop on the *same* channel: the drop handler
## blanks all three pot channels to member 87 while they are hidden and then
## dresses one of them with the pot loop it may already have been holding. That
## middle value is invisible to the painter -- `_effective` answers `{}` for a
## hidden sprite -- so before `bugs.md` 97 the channel looked unchanged, the
## restart was skipped, and the first pot in each of the three lanes fell while
## every later pot in a lane appeared already landed. Measured at loop frames 0,
## 28, 56 and 196 on successive drops into one lane; three good falls and then
## none, for the rest of the game.
##
## The assertion is on the phase rather than on pixels because the phase is what
## selects the frame, and a pixel comparison here would be a comparison against
## whichever frame this port happens to draw. The pot is played, not staged: the
## bell is rung the way a player rings it and the arrows are pressed on the
## movie's own clock, so the drops are the movie's own and their lanes are its
## `random(5)`.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## The frames the pot channels live on, from the score: `puppetSprite` claims
## 27, 28 and 29 in COMEIN's `return1` init and the drop handler dresses one.
const POT_CHANNELS := [27, 28, 29]
## Where the idle loop waits for the doorbell, and where the bell is.
const IDLE_FRAME := 173
const BELL := Vector2(576, 382)
## A press every third score tick: fast enough to dodge and reach a second drop
## in one lane, slow enough that the movie's own gates do not swallow it
## (`bugs.md` 96's neighbour -- a press per tick pins the playhead on the drop
## frame and no pot drops at all).
const PRESS_EVERY := 3


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", "COMEIN.dir", null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("no score loaded")
		quit(1)
		return
	preview.set("_index", IDLE_FRAME)
	for i in 8:
		await process_frame
	# Rung, not jumped past: the marker after this one is the game's own init, and
	# arriving there directly skips the `puppetSprite` the pots need.
	preview.call("route_press", BELL)
	preview.call("route_release", BELL)

	var seen: Dictionary = {}      # channel -> how many drops into it
	var late: Array[String] = []   # drops that did not start at frame one
	var loops: Dictionary = {}     # channel -> whether the member is a film loop
	var was: Dictionary = {}
	var drops := 0
	var last_frame := -1
	var since_press := 0
	var right := true
	var table = preview.get("_table")
	for tick in Args.number(args, "ticks", 9000):
		await process_frame
		var here := int(preview.call("current_frame"))
		if here != last_frame:
			last_frame = here
			since_press += 1
			if since_press >= PRESS_EVERY:
				since_press = 0
				right = not right
				_press(preview, KEY_RIGHT if right else KEY_LEFT)
		var starts: Dictionary = preview.get("_loop_start")
		var ticks_now := int(preview.get("_ticks"))
		for channel in POT_CHANNELS:
			var visible := bool(preview.call("lingo_sprite_prop", channel, "visible"))
			if visible and not bool(was.get(channel, false)):
				var member := int(preview.call("lingo_sprite_prop", channel, "membernum"))
				var m: Dictionary = table.get_member(1, member)
				# Only a film loop has a frame counter to restart. The score's own
				# pot member is a bitmap and is not this test's subject.
				if int(m.get("type", 0)) == 2:
					drops += 1
					seen[channel] = int(seen.get(channel, 0)) + 1
					loops[member] = true
					var since := ticks_now - int(starts.get(channel, ticks_now))
					if since != 0:
						late.append("f%d ch%d member %d started at frame %d" % [
							here, channel, member, since,
						])
			was[channel] = visible

	# A lane that has taken two drops has re-shown the same loop on the same
	# channel, which is the case that regressed. Without one the run proves
	# nothing, so it is a failure rather than a pass.
	var repeated := 0
	for channel in seen:
		if int(seen[channel]) >= 2:
			repeated += 1

	h.begin("a film loop re-shown on a channel restarts")
	h.check("the pot game dropped film loops at all", drops > 0, "%d drop(s)" % drops)
	h.check("at least one lane took a second drop", repeated > 0,
		"%d of %d lane(s) repeated" % [repeated, seen.size()])
	h.check("every drop started at its loop's first frame", late.is_empty(),
		"" if late.is_empty() else "%d did not" % late.size())
	for line in late.slice(0, 8):
		print("     %s" % line)
	h.complete("a film loop re-shown on a channel restarts")

	print("")
	print("drops      : %d over %d lane(s), %d of which repeated" % [
		drops, seen.size(), repeated,
	])
	print("loops seen : %s" % str(loops.keys()))
	quit(h.finish("a re-shown film loop animates from its first frame"))


func _press(preview: Node, code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	preview.call("_dispatch_key", down)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	preview.call("_dispatch_key_up", up)
