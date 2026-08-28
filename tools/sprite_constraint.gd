extends SceneTree
## `the constraint of sprite N` (§7.6): is a position write clamped to the box the
## named channel holds, **and to the box it last held** once the score has blanked
## that channel?
##
##   godot --headless --script tools/sprite_constraint.gd
##   godot --headless --script tools/sprite_constraint.gd -- --root rating --file ARCADE2.dir
##   godot --headless --script tools/sprite_constraint.gd -- --root piposh --file PIPDATA/SHUFFLE.dir
##
##   --root R / --file F   the corpus and the container (default the config's)
##   --verbose             print the subject and fence it derived
##
## ## The rule, and the half that was missing
##
## `channel.cpp:setPosition` clamps every position write -- not only a drag --
## between the constraint channel's `getRollOverBbox()` edges, per axis. The port
## does that in `director_preview._write_position` through `interaction.constrain`,
## and asked `lingo_sprite_rect` for the box.
##
## That is the right box only while the constraint channel still carries a sprite.
## Director's channels are live objects that outlive the score record that filled
## them, and `channel.cpp:getRollOverBbox` says what the box is once the score has
## zeroed the channel -- "whatever the last contents of the sprite were". This
## port keeps no such object, so an emptied fence channel answered `Rect2()` and
## `interaction.constraint_box` read that as **unconstrained**.
##
## `rating/ARCADE2.dir` is what that costs. Each race's setup frame runs
## `set the constraint of sprite 10 to 11` from its `exitFrame`, and channel 11
## carries its 231x230 shape on exactly those setup frames -- 6 of the movie's
## 1337. For the whole of every race the fence was blank, the clamp was skipped,
## and the car drove off the track: locH 226 -> 466 in 24 presses of the right
## arrow, with no limit at all.
##
## ## Why the subject is derived rather than named
##
## Nothing here may know a title. The score says which channels are occupied on
## which frames, so the cases are found in whatever movie is loaded: a channel
## occupied on one frame and blank on a later one is the fence, any other channel
## occupied on the later frame is the subject, and a channel the movie never fills
## is the third case. A movie that cannot offer one says so and asserts what it can
## rather than inventing a frame.
const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Far enough outside any stage that an unclamped write is unambiguous.
const FAR := 9000


func _init() -> void:
	var h := Harness.new()
	await _run(h)
	quit(h.finish("a position write is clamped to the constraint channel's box"))


func _run(h: Harness) -> bool:
	var args := Args.parse()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var movie := Args.text(args, "file", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		for i in 8:
			await process_frame
	preview.set("_paused", true)
	var score = preview.get("_score")
	var case := "%s: the fence is the channel's contents, live and last" % str(
		preview.call("movie_name"))
	h.begin(case)
	if not h.check("the movie has a score", score != null):
		return true

	var found := _pick(score)
	if not h.check("the score offers a channel that is filled and later blank",
			not found.is_empty(), "%d frames" % int(score.frame_count)):
		return true
	var fence := int(found[0])
	var live_at := int(found[1])
	var blank_at := int(found[2])
	var subject := int(found[3])
	if args.has("verbose"):
		print("      fence ch%d filled at f%d, blank at f%d; subject ch%d"
			% [fence, live_at, blank_at, subject])

	# ---------------------------------------------------------------- live
	preview.set("_index", live_at)
	preview.call("lingo_set_sprite_prop", subject, "constraint", fence)
	var box: Rect2 = preview.call("lingo_sprite_rect", fence)
	if not h.check("the fence channel has a box on the frame it is filled",
			box.size.x > 0.0, str(box)):
		return true
	preview.call("lingo_set_sprite_prop", subject, "loch", FAR)
	var live_right := int(preview.call("lingo_sprite_prop", subject, "loch"))
	h.check("a write past the right edge stops at it",
		live_right == int(box.end.x),
		"locH %d, box right %d" % [live_right, int(box.end.x)])
	preview.call("lingo_set_sprite_prop", subject, "loch", -FAR)
	var live_left := int(preview.call("lingo_sprite_prop", subject, "loch"))
	h.check("...and a write past the left edge stops at that",
		live_left == int(box.position.x),
		"locH %d, box left %d" % [live_left, int(box.position.x)])

	# ---------------------------------------------------------------- blanked
	# The playhead moves to a frame whose score has emptied the fence channel.
	# Director's channel still holds what it last held (`getRollOverBbox`), so the
	# same two edges must still bind. Without the fallback this reads locH 9000.
	preview.set("_index", blank_at)
	var still_there := false
	for value in (preview.call("frame_sprites") as Array):
		if int((value as Dictionary)["channel"]) == fence:
			still_there = true
	h.check("the fence channel is blank on the later frame", not still_there,
		"frame %d" % blank_at)
	preview.call("lingo_set_sprite_prop", subject, "loch", FAR)
	var blank_right := int(preview.call("lingo_sprite_prop", subject, "loch"))
	h.check("a blanked fence still stops the write at its last right edge",
		blank_right == int(box.end.x),
		"locH %d, box right %d" % [blank_right, int(box.end.x)])
	preview.call("lingo_set_sprite_prop", subject, "loch", -FAR)
	var blank_left := int(preview.call("lingo_sprite_prop", subject, "loch"))
	h.check("...and at its last left edge",
		blank_left == int(box.position.x),
		"locH %d, box left %d" % [blank_left, int(box.position.x)])

	# ---------------------------------------------------------------- never filled
	# The half of the old rule that survives: with no last contents there is no
	# box, and clamping onto the origin would be the teleport nobody authored.
	var never := _never_filled(score)
	if never > 0:
		preview.call("lingo_set_sprite_prop", subject, "constraint", never)
		preview.call("lingo_set_sprite_prop", subject, "loch", FAR)
		h.check("a fence channel the movie never fills does not constrain",
			int(preview.call("lingo_sprite_prop", subject, "loch")) == FAR,
			"ch%d, locH %s" % [never,
				str(preview.call("lingo_sprite_prop", subject, "loch"))])
	else:
		print("      every channel of this score is filled somewhere; "
			+ "the never-filled case is not staged here")

	# ---------------------------------------------------------------- unset
	preview.call("lingo_set_sprite_prop", subject, "constraint", 0)
	preview.call("lingo_set_sprite_prop", subject, "loch", FAR)
	h.check("constraint 0 is unconstrained",
		int(preview.call("lingo_sprite_prop", subject, "loch")) == FAR,
		"locH %s" % str(preview.call("lingo_sprite_prop", subject, "loch")))
	h.complete(case)
	return true


## `[fence, live_frame, blank_frame, subject]`, or `[]`.
##
## The first channel this score fills and later empties while some *other* channel
## is still on the stage to be pushed around. Bounded, because a long movie is not
## a better subject than a short prefix of it.
func _pick(score) -> Array:
	var limit: int = mini(int(score.frame_count), 400)
	var filled: Dictionary = {}
	for index in limit:
		var here: Dictionary = {}
		for value in (score.frame(index).get("sprites", []) as Array):
			here[int((value as Dictionary)["channel"])] = true
		for channel in filled:
			if here.has(channel):
				continue
			for other in here:
				if int(other) != int(channel):
					return [int(channel), int(filled[channel]), index, int(other)]
		for channel in here:
			if not filled.has(channel):
				filled[channel] = index
	return []


## A channel no frame of this score ever fills, or 0.
func _never_filled(score) -> int:
	var limit: int = mini(int(score.frame_count), 400)
	var seen: Dictionary = {}
	for index in limit:
		for value in (score.frame(index).get("sprites", []) as Array):
			seen[int((value as Dictionary)["channel"])] = true
	for channel in range(1, int(score.channels_displayed) + 1):
		if not seen.has(channel):
			return channel
	return 0
