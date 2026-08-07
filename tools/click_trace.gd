extends SceneTree
## What one click did: where the playhead went, what it played, what it ran.
##
##   godot --headless --script tools/click_trace.gd -- --root rating \
##       --movie BATZEGOZ.dir --marker Egoz1 --channel 12
##   godot --headless --script tools/click_trace.gd -- --marker shore2
##
## `AGENTS.md` has said for a long time that the single most useful tool this
## repo is missing is a "where did the playhead go" probe -- there was one,
## `tools/probe.gd`, and it was deleted with the renderer it drove. This is that
## probe narrowed to the question it was always reached for: **a click happened
## and the wrong thing came out of it.**
##
## The four answers it prints are the four that are indistinguishable from the
## player's chair, and the reason a symptom like "the speech is cut off" gets
## filed against the sound code:
##
## - **the playhead**, before and after, named by the marker it is inside rather
##   than by frame number, because a script says `go("batz2a")` and nobody knows
##   what frame that is;
## - **the play stack**, because `play frame` and `go` in one handler are two
##   branches competing for one playhead and the stack is the only evidence that
##   the losing one ran at all;
## - **the sound trace**, because a line of speech that starts and stops is two
##   `playFile` calls one tick apart and looks like one broken call;
## - **the dispatch tallies**, because "no handler ran" and "the handler ran and
##   did nothing" are the same picture.
##
## Reports, never asserts. There is no invariant here that holds across titles --
## a click on a frame with nothing on it is a legitimate answer -- so this prints
## and exits 0. It is the tool you reach for *before* writing the harness that
## does assert something.
##
## Title-agnostic: `--root` picks the game, `--movie` the container, `--marker`
## or `--frame` the place, and the subject is the frame's own topmost clickable
## sprite unless `--channel` names one.

const Args := preload("res://tools/lib/args.gd")


func _init() -> void:
	var args := Args.parse()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		# A movie change is entered by the next step, not by the call: the whole
		# of `prepareMovie`/`startMovie` and the first frame's own scripts run on
		# the ticks after it, and clicking before they have would be clicking a
		# frame the game has not reached.
		for i in 8:
			await process_frame

	var score = preview.get("_score")
	if score == null:
		print("no score loaded")
		quit(1)
		return

	var frame := _target_frame(preview, args)
	if frame < 0:
		quit(1)
		return
	if frame != int(preview.call("current_frame")):
		preview.set("_index", frame)
		# Entered rather than merely indexed. A frame the score has not entered
		# has run no `enterFrame`, so its sprites carry the previous frame's
		# puppet state and the hit test answers about a frame nobody is on.
		for i in 4:
			await process_frame
	preview.set("_paused", true)

	var before := int(preview.call("current_frame"))
	var traced_before: int = (preview.get("_traced") as Array).size()
	var sent_before: Dictionary = (preview.get("_sent") as Dictionary).duplicate()
	var ran_before: Dictionary = (preview.get("_ran") as Dictionary).duplicate()

	print("")
	print("%s  %s" % [str(preview.call("movie_name")), _where(preview, before)])

	var subject := _subject(preview, args, before)
	if subject.is_empty():
		print("nothing on this frame answers the mouse -- pass --channel to click anyway")
		quit(0)
		return
	print("clicking channel %d at (%d,%d)" % [
		int(subject[0]), int(subject[1].x), int(subject[1].y)])
	print("")

	preview.call("route_press", subject[1])
	preview.call("route_release", subject[1])
	print("  after the release   : %s" % _where(preview, int(preview.call("current_frame"))))

	# Let the score run on. A `go` from a mouse handler lands on the *next* tick
	# (§6.1 step 7), and the frame it lands on then runs its own `enterFrame` and
	# `exitFrame` -- which is where a second `playFile` on the same channel comes
	# from, and it is the tick after the click that the player hears.
	preview.set("_paused", false)
	var ticks := Args.number(args, "ticks", 30)
	for i in ticks:
		await process_frame
	preview.set("_paused", true)
	print("  %d ticks later      : %s" % [
		ticks, _where(preview, int(preview.call("current_frame")))])
	print("  started at          : %s" % _where(preview, before))

	var stack: Array = preview.get("_play_stack")
	print("")
	print("play stack          : %d entry(s)%s" % [
		stack.size(),
		"" if stack.is_empty() else "  %s" % str(stack),
	])
	# The other half of the same question, and the one the play stack alone could
	# not answer. A `play` suspends the handler that called it (§9.4), so an
	# entry on the stack and a handler in the play buffer are one pending return:
	# a stack entry with an *empty* buffer is a `play` whose caller had nothing
	# left to run, and a buffer that is still full long after the interlude ended
	# is a handler waiting on a `play done` the movie never reaches.
	print("suspended handlers  : %d parked at a `go`, %s at a `play`; %d parked in all" % [
		(preview.get("_frozen_lingo") as Array).size(),
		"one" if not (preview.get("_frozen_play") as Array).is_empty() else "none",
		int(preview.get("_frozen_parked")),
	])

	var traced: Array = preview.get("_traced")
	print("sound and score, from the click onward:")
	for i in range(traced_before, traced.size()):
		print("   %s" % str(traced[i]))
	if traced.size() == traced_before:
		print("   (nothing traced)")

	print("")
	print("dispatched by the click and the ticks after it:")
	_print_delta("  sent", preview.get("_sent"), sent_before)
	_print_delta("  ran ", preview.get("_ran"), ran_before)
	quit(0)


## The frame `--marker` or `--frame` names, or the one already playing.
func _target_frame(preview: Node, args: Dictionary) -> int:
	var marker := Args.text(args, "marker", "")
	if marker == "":
		return Args.number(args, "frame", int(preview.call("current_frame")))
	var labels = preview.get("_labels")
	if labels != null:
		for m in labels.markers:
			if str(m["name"]).to_lower() == marker.to_lower():
				return int(m["frame"])
	print("no marker '%s' in %s" % [marker, str(preview.call("movie_name"))])
	return -1


## A frame number said the way a script says it: the marker it is inside, and how
## far past that marker it is. `go("batz2a")` is what the Lingo reads; frame 216
## is what nobody can check by eye.
func _where(preview: Node, frame: int) -> String:
	var labels = preview.get("_labels")
	var name := ""
	var start := 0
	if labels != null:
		for m in labels.markers:
			# Unnamed markers are skipped rather than reported as a blank name.
			# `director_labels.gd` drops them today, so this changes nothing yet --
			# and it is what stops this reading "frame 215 ()" the moment they are
			# kept, which they have to be for `marker(n)` to count correctly
			# (`bugs.md`, the `play done` entry).
			if str(m["name"]) == "":
				continue
			if int(m["frame"]) <= frame and int(m["frame"]) >= start:
				start = int(m["frame"])
				name = str(m["name"])
	if name == "":
		return "frame %d" % (frame + 1)
	if start == frame:
		return "frame %d  (%s)" % [frame + 1, name]
	return "frame %d  (%s + %d)" % [frame + 1, name, frame - start]


## `[channel, point]` for the sprite to click, or `[]`.
##
## The frame's topmost sprite that answers the hit test, because channel number
## is depth and nothing above it can absorb the press. `--channel` overrides,
## and overrides the eligibility test with it: "this ought to be clickable and is
## not" is a question this tool should be able to be asked.
func _subject(preview: Node, args: Dictionary, frame: int) -> Array:
	var score = preview.get("_score")
	var wanted := Args.number(args, "channel", 0)
	var sprites: Array = score.frame(frame).get("sprites", [])
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = preview.call("_effective", sprites[i])
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		if wanted > 0 and channel != wanted:
			continue
		var rect: Rect2 = preview.call("_sprite_rect", sprite)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var at := rect.get_center()
		if wanted > 0:
			return [channel, at]
		# Asked of the hit test rather than of `responds_to_mouse` alone, so a
		# sprite that is eligible but keyed transparent at its own centre is not
		# reported as the subject when the click would reach past it.
		if int(preview.call("_channel_at", at)) == channel:
			return [channel, at]
	return []


func _print_delta(label: String, now_value: Variant, before: Dictionary) -> void:
	var now: Dictionary = now_value
	var out: Array[String] = []
	for key in now:
		var delta := int(now[key]) - int(before.get(key, 0))
		if delta > 0:
			out.append("%s x%d" % [key, delta])
	print("%s: %s" % [label, "nothing" if out.is_empty() else ", ".join(out)])
