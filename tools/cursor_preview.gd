extends SceneTree
## Does a custom cursor actually reach the screen in `scenes/director_preview.gd`?
##
##   godot --headless --script tools/cursor_preview.gd -- --file PIP2DATA/MAP.DIR
##
## `tools/cursors.gd` already covers the other renderer, the one that draws from
## the pre-decoded `assets/render_model/` export. This covers the preview, which
## reads the original containers at runtime and shares none of that code. Both
## paths compose the same Director cursor from the same two 1-bit members, and
## only one of them had ever been looked at.
##
## MAP is the reproduction case. Its frame script
## (`reference/lingo/MAP/Internal/BehaviorScript 6.ls`) does
##
##   repeat with i = 3 to 14
##     set the cursor of sprite i to [member("able1").memberNum, member("able2").memberNum]
##   end repeat
##
## which is the whole chain in one line: a name resolved to a member number, a
## pair stored on a channel, that channel arbitrated against the pointer, the pair
## composed into an image, the image pushed to the OS. Every one of those steps
## can fail silently, and the failure looks identical from the outside — the arrow
## stays. So this asserts each of them separately, and asserts the *image*, not
## that a function was reached: `[0, 0]` composes to null and installs the arrow
## without raising anything, which is precisely how this shipped broken.
##
## Deliberately does not restate which members MAP uses. The movie's own script is
## the only place that mapping exists; naming `able1` here would let the port and
## the harness agree with each other while both disagreed with the original.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## The composed cursor is a fixed 16x16 (DIRECTOR_ENGINE.md 7.3), so anything else
## is a crop or a pad going wrong rather than a member being an odd size.
const EXPECTED_SIZE := 16


func _opaque_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				count += 1
	return count


func _init() -> void:
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	if scene == null:
		print("no preview scene")
		quit(1)
		return
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	# Far enough for the room to have entered and run its exitFrame at least once.
	# Stepping the node rather than waiting on the clock keeps this deterministic;
	# MAP's assignment happens on the first exitFrame of the room it settles in.
	for i in 250:
		preview.call("_advance")

	var movie := Args.text(Args.parse(), "file", "<default>")
	var cursors: Dictionary = preview.get("_channel_cursors")
	var table = preview.get("_table")

	# ---------------------------------------------------------------- assignment
	h.begin("the movie's own script assigns cursors")
	h.check("some channel was given a cursor", not cursors.is_empty(),
		"%d channel(s) %s" % [cursors.size(), str(cursors.keys())])
	# The failure this harness exists for. `member("able1").memberNum` had no arm
	# in `lingo_member_prop`, so it returned 0 and every pair was stored as
	# [0, 0] — a well-formed list of two plausible member numbers that composes to
	# nothing. The channel count above was already right while this was broken,
	# which is why the count alone is not the check.
	var zeroed: Array = []
	var pairs: Dictionary = {}
	for channel in cursors.keys():
		var value: Variant = cursors[channel]
		if typeof(value) != TYPE_ARRAY:
			continue
		var pair: Array = value
		if pair.is_empty() or int(pair[0]) == 0:
			zeroed.append("ch%s %s" % [str(channel), str(pair)])
			continue
		pairs[str(pair)] = pair
	h.check("no pair resolved to member 0", zeroed.is_empty(),
		", ".join(PackedStringArray(zeroed)))
	h.complete("the movie's own script assigns cursors")

	# ------------------------------------------------------------------ the image
	h.begin("every assigned pair composes to something the player can see")
	var unnamed: Array = []
	var uncomposed: Array = []
	var wrong_size: Array = []
	var blank: Array = []
	var solid: Array = []
	for key in pairs.keys():
		var pair: Array = pairs[key]
		var data_id := int(pair[0])
		var mask_id: int = int(pair[1]) if pair.size() > 1 else 0
		# A named member proves the number came from the script's name lookup and
		# not from a stray integer that happened to land on a bitmap.
		var member: Dictionary = table.get_member(1, data_id)
		if str(member.get("name", "")) == "":
			unnamed.append("%s -> member %d" % [key, data_id])
		var composed = preview.call("_cursor_image", data_id, mask_id)
		if composed == null:
			uncomposed.append(key)
			continue
		var image: Image = composed["image"]
		if image.get_width() != EXPECTED_SIZE or image.get_height() != EXPECTED_SIZE:
			wrong_size.append("%s is %dx%d" % [key, image.get_width(), image.get_height()])
		var opaque := _opaque_pixels(image)
		# Both ends matter. Nothing opaque is an invisible cursor; everything
		# opaque is the mask having been ignored, which is the black rectangle the
		# composition comments warn about — and both pass any check that only asks
		# whether an image came back.
		if opaque == 0:
			blank.append(key)
		elif opaque == image.get_width() * image.get_height():
			solid.append(key)
		print("   %s -> %s: %dx%d, %d/%d opaque, hotspot %s" % [
			key, str(member.get("name", "<unnamed>")),
			image.get_width(), image.get_height(),
			opaque, image.get_width() * image.get_height(),
			str(composed["hotspot"])])
	h.check("the pairs were composed at all", not pairs.is_empty(),
		"%d distinct pair(s)" % pairs.size())
	h.check("every data member has a name", unnamed.is_empty(),
		", ".join(PackedStringArray(unnamed)))
	h.check("every pair composes to an image", uncomposed.is_empty(),
		", ".join(PackedStringArray(uncomposed)))
	h.check("every image is %dx%d" % [EXPECTED_SIZE, EXPECTED_SIZE],
		wrong_size.is_empty(), ", ".join(PackedStringArray(wrong_size)))
	h.check("no image is fully transparent", blank.is_empty(),
		", ".join(PackedStringArray(blank)))
	h.check("no image is fully opaque", solid.is_empty(),
		", ".join(PackedStringArray(solid)))
	h.complete("every assigned pair composes to something the player can see")

	# --------------------------------------------------------------- the negative
	# `set the cursor of sprite N to [1, 1]` is the corpus's "back to the arrow",
	# 208 times, and member 1 is a backdrop rather than cursor art. Composing it
	# anyway crops 16x16 out of the scenery and puts that under the pointer. The
	# largest bitmap in the cast is found here rather than named, so this stays a
	# statement about size and not about which member this game happens to have.
	h.begin("scenery is not accepted as cursor art")
	var biggest := 0
	var biggest_area := 0
	var biggest_name := ""
	var cast = table.cast_for(1)
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(number)
		if int(m.get("type", 0)) != 1:
			continue
		var area := int(m.get("width", 0)) * int(m.get("height", 0))
		if area > biggest_area:
			biggest_area = area
			biggest = number
			biggest_name = "%s (%sx%s)" % [
				str(m.get("name", "")), str(m.get("width", 0)), str(m.get("height", 0))]
	h.check("the cast has a bitmap far larger than a cursor", biggest_area > 32 * 32,
		"member %d %s" % [biggest, biggest_name])
	h.check("it does not compose as a cursor",
		preview.call("_cursor_image", biggest, biggest) == null,
		"member %d %s" % [biggest, biggest_name])
	h.complete("scenery is not accepted as cursor art")

	# ------------------------------------------------------------- arbitration
	# The pair being right and the image being right still shows nothing if the
	# descent never picks the channel out. Headless there is no pointer, so this
	# asks `cursor_at` directly at the centre of each cursor-bearing sprite.
	h.begin("the descent finds the cursor over the sprite that set it")
	var score = preview.get("_score")
	var index: int = preview.get("_index")
	var probed := 0
	var missed: Array = []
	for sprite in score.frame(index).get("sprites", []):
		var channel := int(sprite["channel"])
		if not cursors.has(channel):
			continue
		var rect: Rect2 = preview.call("_sprite_rect", sprite)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		probed += 1
		var found: Variant = preview.call("cursor_at", rect.get_center())
		# Not "some cursor": the one this channel asked for, or a higher channel's
		# if one covers the same point. Comparing to the set of assigned pairs
		# rather than to this channel's own keeps a legitimate overlap from
		# reading as a failure while still catching the global leaking through.
		if typeof(found) != TYPE_ARRAY or not pairs.has(str(found)):
			missed.append("ch%d at %s -> %s" % [channel, str(rect.get_center()), str(found)])
	h.check("there were cursor-bearing sprites on stage", probed > 0, "%d sprite(s)" % probed)
	h.check("each of them answers with an assigned pair", missed.is_empty(),
		", ".join(PackedStringArray(missed)))
	# The negative half. An arbitration that answered everywhere would satisfy the
	# line above and tell the player nothing.
	var nowhere: Variant = preview.call("cursor_at", Vector2(-4000, -4000))
	h.check("off the stage falls back to the global cursor",
		typeof(nowhere) != TYPE_ARRAY, str(nowhere))
	h.complete("the descent finds the cursor over the sprite that set it")

	# ------------------------------------------------------------------ the push
	# Through the real setter, so a pair that composes but is rejected on the way
	# to the OS is still caught. `lingo_set_cursor` reports what it installed in
	# `_cursor_now`, and its own fallback arms say so in words.
	h.begin("the pair is installed as a custom cursor")
	var first: Array = []
	for key in pairs.keys():
		first = pairs[key]
		break
	if first.is_empty():
		h.check("there was a pair to install", false)
	else:
		preview.call("lingo_set_cursor", first)
		var now := str(preview.get("_cursor_now"))
		h.check("the setter installed a custom cursor", now.begins_with("custom"),
			"%s -> %s" % [str(first), now])
		# And the arrow really is still reachable, so "custom" is not simply what
		# this function always says.
		preview.call("lingo_set_cursor", 0)
		h.check("cursor 0 goes back to the arrow",
			str(preview.get("_cursor_now")) == "0", str(preview.get("_cursor_now")))
	h.complete("the pair is installed as a custom cursor")

	# ------------------------------------------------------------ the movie change
	# Last, because it reloads the movie and throws away everything above. A pair is
	# a pair of member numbers and those are local to a cast, so they cannot follow
	# the playhead into another container. Reloading the same file is the
	# title-agnostic way to ask: no second movie has to be named.
	#
	# Via a sentinel on a channel the movie does not use, not by looking for an
	# empty dictionary. `lingo_go_movie` dispatches prepareMovie, startMovie and
	# enterFrame before it returns, and some movies assign their cursors in those —
	# AIR1 does, on channels 103-110 — so the dictionary is legitimately repopulated
	# by the time control comes back, and a reload of the same file repopulates it
	# with the identical numbers. Only a value the movie itself would never write
	# can tell "cleared and rebuilt" from "never cleared".
	h.begin("a new movie clears the channel cursors")
	var sentinel_channel := 1
	for channel in cursors.keys():
		sentinel_channel = maxi(sentinel_channel, int(channel) + 1)
	var sentinel: Array = [999999, 999999]
	preview.call("lingo_set_sprite_prop", sentinel_channel, "cursor", sentinel)
	var planted: Dictionary = preview.get("_channel_cursors")
	h.check("the sentinel was planted",
		str(planted.get(sentinel_channel, [])) == str(sentinel),
		"ch%d = %s" % [sentinel_channel, str(planted.get(sentinel_channel, []))])
	preview.call("lingo_go_movie", movie.get_file(), null)
	var after: Dictionary = preview.get("_channel_cursors")
	h.check("the sentinel did not survive the movie change",
		str(after.get(sentinel_channel, [])) != str(sentinel),
		"ch%d = %s" % [sentinel_channel, str(after.get(sentinel_channel, []))])
	for i in 250:
		preview.call("_advance")
	var again: Dictionary = preview.get("_channel_cursors")
	h.check("the reloaded movie assigns its own again", not again.is_empty(),
		"%d channel(s) %s" % [again.size(), str(again.keys())])
	h.complete("a new movie clears the channel cursors")

	print("")
	print("movie          : %s" % movie)
	print("channel cursors: %s" % JSON.stringify(cursors))
	quit(h.finish("custom cursors in the container-reading preview"))
