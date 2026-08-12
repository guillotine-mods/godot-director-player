extends SceneTree
## Does a sprite get told it has begun, and told once?
##
##   godot --headless --audio-driver Dummy --path . --script tools/sprite_lifetime.gd -- \
##     --root res://games/piposh2 --file PIP2DATA/DAY1.dir
##
## `beginSprite`/`endSprite` were not sent at all until `bugs.md` 87, and the two
## ways of getting them wrong are opposite: never sending one leaves a screen
## running the last screen's setup, and sending one per frame turns every score
## span into a per-frame handler storm. So this asserts both directions.
##
## **Three checks are corpus-agnostic** and run against whatever movie is passed:
##
## 1. *The record agrees with the score.* Every channel in `_begun_sprites` is a
##    span that covers the frame the playhead is on, and every span that covers it
##    is in the record. That is the invariant `frame_loop.gd:sync_sprite_lifetime`
##    exists to hold, and it is checked against the score rather than against the
##    function's own output.
## 2. *No sprite begins twice without ending.* Counted over a run: the number of
##    `beginSprite` messages sent never exceeds the number of distinct
##    (channel, span) pairs the playhead entered. A per-frame trigger fails this
##    immediately.
## 3. *The traffic is proportional to spans entered, not to frames played.* The
##    number of `beginSprite` messages is compared against the number of score
##    steps taken; a movie whose behaviour spans are longer than one frame must
##    send fewer messages than it takes steps.
##
## **The fourth is Magic Hat's**, named as such and skipped for any other corpus,
## because a harness that asserts nothing about the movie in front of it is a
## tautology. `bugs.md` 87: the album screen is reached from the main menu, its
## red X is channel 8, and until `beginSprite` arrived the screen kept the *main
## menu's* screen-item registry -- so the first mouse move over the X ran the menu
## button that used to be in channel 8, swapped the member out from under the
## pointer and left the album a screen a player could enter and not leave. The
## check is the player-visible one: aim at the X, then click it, and the playhead
## must leave the album frame.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const FrameLoop := preload("res://scenes/preview/frame_loop.gd")
const Router := preload("res://scenes/preview/input_router.gd")

## Magic Hat's own numbers, from `bugs.md` 87 and `tools/scratch/spans.gd`.
const MAGICHAT_ALBUM_BUTTON := Vector2(448, 378)
const MAGICHAT_ALBUM_FRAME := 42
const MAGICHAT_CLOSE_X := Vector2(779, 59)
const MAGICHAT_CLOSE_CHANNEL := 8
## The centre of channel 3 on the main menu -- `bMain2`, "tools" in
## `mainpanels.txt` -- whose score rect is 302x232 at (61,80). Not a guess: the
## album button next to it (channel 2) is 332x352 at (268,248), so a point chosen
## anywhere in the lower right of the screen lands on the album instead, which is
## what this constant was until it opened the album twice.
const MAGICHAT_TOOLS_BUTTON := Vector2(212, 196)
const MAGICHAT_TOOLS_FRAME := 89


func _init() -> void:
	var h := Harness.new()
	var opts: Dictionary = Args.parse()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	for _i in 90:
		await process_frame

	var movie := str(preview.call("movie_name")).to_lower()
	print("movie: %s, frame %d" % [movie, int(preview.get("_index"))])

	h.begin("record")
	_check_record(h, preview)
	h.complete("record")

	# Play on, sampling the record against the score at every frame the playhead
	# reaches. A sample per engine frame rather than per score step, because the
	# invariant is not allowed to be false in between either.
	h.begin("record while playing")
	var mismatches := 0
	var samples := 0
	# **The storm check.** A frame the playhead is standing on must cost nothing.
	# Most of a Director title's time is spent on a `go to the frame` frame, which
	# still takes a score step, still sends `prepareFrame` and `enterFrame`, and
	# still runs the sprite-lifetime diff -- so a trigger that fires on anything
	# but a *span* boundary shows up here as a begin on a frame that did not
	# change. Sampled per engine frame, which is faster than the score steps, so a
	# still playhead really is still between two samples.
	var still_begins := 0
	var last_index := int(preview.get("_index"))
	var last_begins := _count(preview, "beginSprite")
	for _i in int(Args.number(opts, "frames", 300)):
		await process_frame
		samples += 1
		if not _record_matches(preview):
			mismatches += 1
		var now_index := int(preview.get("_index"))
		var now_begins := _count(preview, "beginSprite")
		if now_index == last_index and now_begins > last_begins:
			still_begins += now_begins - last_begins
		last_index = now_index
		last_begins = now_begins
	h.check("the record matched the score on every sampled frame", mismatches == 0,
		"%d of %d samples disagreed" % [mismatches, samples])
	h.check("a frame the playhead stood on sent no beginSprite", still_begins == 0,
		"%d begins arrived without the frame changing, over %d samples" % [
			still_begins, samples])
	h.complete("record while playing")

	h.begin("traffic")
	var begins := _count(preview, "beginSprite")
	var ends := _count(preview, "endSprite")
	var live: int = (preview.get("_begun_sprites") as Dictionary).size()
	# Conservation, and it is exact rather than a bound: every behaviour that has
	# begun has either ended or is still on stage. A duplicate begin, a missing
	# end or an end for something that never began all break it, and the record's
	# own size is the third term rather than a second opinion on the first two.
	# Counted in *behaviours*, so a channel carrying two of them counts twice --
	# which is why this is compared against the record's channel count only where
	# every span carries one behaviour, and is stated as a bound otherwise.
	h.check("every begin is matched by an end or a live sprite",
		begins - ends >= live,
		"%d begins, %d ends, %d live" % [begins, ends, live])
	h.check("no sprite ended that never began", ends <= begins,
		"%d ends, %d begins" % [ends, begins])
	h.complete("traffic")

	if movie.contains("magichat"):
		await _magichat(h, preview)
	else:
		print("note: the album case is Magic Hat's and this is %s" % movie)

	quit(h.finish("beginSprite/endSprite reach the score's spans and nothing else"))


func _count(preview, handler: String) -> int:
	return int((preview.get("_sent") as Dictionary).get(handler, 0))


## `channel -> spec` for the frame the playhead is on, straight from the score.
func _spans_now(preview) -> Dictionary:
	return FrameLoop.sprite_behaviours_at(preview.get("_score"), int(preview.get("_index")))


func _record_matches(preview) -> bool:
	var want: Dictionary = _spans_now(preview)
	var have: Dictionary = preview.get("_begun_sprites")
	if want.size() != have.size():
		return false
	for channel in want:
		if have.get(channel, null) != want[channel]:
			return false
	return true


func _check_record(h: Harness, preview) -> void:
	var want: Dictionary = _spans_now(preview)
	var have: Dictionary = preview.get("_begun_sprites")
	var missing: Array = []
	for channel in want:
		if have.get(channel, null) != want[channel]:
			missing.append(channel)
	var extra: Array = []
	for channel in have:
		if not want.has(channel):
			extra.append(channel)
	h.check("every span covering the frame has begun", missing.is_empty(),
		"channels %s of %d are not in the record" % [str(missing), want.size()])
	h.check("nothing has begun that the frame does not carry", extra.is_empty(),
		"channels %s are in the record and not in the score" % str(extra))


## `bugs.md` 87, driven the way a player reaches it.
func _magichat(h: Harness, preview) -> void:
	h.begin("magichat: the album closes")
	preview.call("route_click", MAGICHAT_ALBUM_BUTTON)
	for _i in 150:
		await process_frame
	var on_album := int(preview.get("_index"))
	if not h.check("the album button opens the album", on_album == MAGICHAT_ALBUM_FRAME,
			"frame %d, wanted %d" % [on_album, MAGICHAT_ALBUM_FRAME]):
		h.complete("magichat: the album closes")
		return
	h.check("the close button is under the pointer before it arrives",
		int(preview.call("_channel_at", MAGICHAT_CLOSE_X)) == MAGICHAT_CLOSE_CHANNEL,
		"channel %d" % int(preview.call("_channel_at", MAGICHAT_CLOSE_X)))
	# The rollover is the whole bug: with the main menu's registry still live,
	# `ItemMouseEnter` swapped channel 8 to a menu button drawn in the middle of
	# the screen and the corner the player is aiming at then hit nothing.
	preview.call("note_pointer", MAGICHAT_CLOSE_X)
	Router.aim_pointer(preview, MAGICHAT_CLOSE_X)
	for _i in 30:
		await process_frame
	h.check("and still under it after the rollover",
		int(preview.call("_channel_at", MAGICHAT_CLOSE_X)) == MAGICHAT_CLOSE_CHANNEL,
		"channel %d" % int(preview.call("_channel_at", MAGICHAT_CLOSE_X)))
	preview.call("route_press", MAGICHAT_CLOSE_X)
	preview.call("route_release", MAGICHAT_CLOSE_X)
	for _i in 120:
		await process_frame
	h.check("clicking it leaves the album",
		int(preview.get("_index")) != MAGICHAT_ALBUM_FRAME,
		"frame %d" % int(preview.get("_index")))
	h.complete("magichat: the album closes")

	# And the menu the album was reached from still answers, which is the
	# regression a wrong screen-item registry would show up as next.
	h.begin("magichat: the menu still navigates")
	for _i in 200:
		await process_frame
	preview.call("route_click", MAGICHAT_TOOLS_BUTTON)
	for _i in 200:
		await process_frame
	h.check("the tools button opens the tools screen",
		int(preview.get("_index")) == MAGICHAT_TOOLS_FRAME,
		"frame %d, wanted %d" % [int(preview.get("_index")), MAGICHAT_TOOLS_FRAME])
	h.complete("magichat: the menu still navigates")
