extends SceneTree
## A Copy-inked sprite carrying the blend flag is keyed by its matte, not drawn
## solid — and still hit-tests as its whole rectangle.
##
##   godot --headless --path . --script tools/ink_blend_matte.gd -- --file BATZEGOZ.dir
##   godot --headless --path . --script tools/ink_blend_matte.gd -- --file BATZEGOZ.dir --label egozspeak1
##
## `bugs.md` 50. Director decides a sprite's keying in `Channel::getMask` from the
## ink **and** the thickness byte's blend flag **and** the member's bit depth
## (`channel.cpp:188-226`); this port decided it from the ink number alone, so the
## one combination where those disagree — ink Copy with the blend flag set,
## `channel.cpp:206`, which does not even consult the blend amount — fell through
## to "draw every pixel". *Rating*'s dialogue portraits carry exactly that, and
## Egoz's face drew inside an opaque white rectangle over the room.
##
## **Why this movie and this label.** The bug needs a real record with ink byte
## 0x00 and thickness byte 0x10 over a multi-bit bitmap whose paper is
## border-reachable white, and a synthetic sprite would prove only that the
## predicate returns what it was written to return. `BATZEGOZ.dir`'s `egozspeak1`
## segment is that record: channel 41 steps through `Panel.cst` members 22-28, one
## per frame, while every other segment of the movie parks it on member 3 at ink 8.
## 27,914 of Rating's 847,431 sprite records are Copy-with-blend against 209 of
## Piposh 2's 816,318, which is why the hole survived a corpus sweep.
##
## **The sprite is found, never named.** Nothing here knows about channel 41: it
## walks the segment for the first bitmap sprite whose ink is Copy and whose blend
## flag is set, and fails if there is none. A harness that hardcodes the channel
## passes for as long as the channel exists and stops testing the rule the day the
## score moves it, and this port has been bitten by exactly that.
##
## Five of the eight checks are guards rather than the assertion, and each one is
## a way this could pass while being wrong:
##
##   * that such a sprite was found at all — otherwise it asserts over nothing;
##   * that clearing the blend flag brings the white back, so the flag is what
##     moved and not some unrelated decode change (attribution, in-harness);
##   * that the keyed area is neither nothing nor almost everything;
##   * that **enclosed** white survives — the whites of the eyes. Background
##     Transparent would eat them and a matte must not, which is the check that
##     catches the tempting "just treat Copy as paper-keyed" simplification;
##   * that `hits_per_pixel` still answers **false**. Director mattes this sprite
##     for drawing and still hits it across its full box
##     (`castmember/bitmap.cpp:920-928`), so the render and hit tables are meant
##     to disagree here. Asserting the disagreement is what stops the next person
##     removing it.
##
## Not in `gate.sh`'s `ALL`: the gate pins the corpus to Piposh 2 and this needs
## Rating, so it would fail there for the right reason and read as a regression.
## It fails loudly rather than skipping when pointed at the wrong movie — a
## harness that quietly asserts nothing is the failure `preview_surface.gd` exists
## for.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Bitmap := preload("res://director/director_bitmap.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")

## How far past the marker to look for a talking frame. The segment is 9 frames
## long; 40 covers it without running into the next scene.
const SEGMENT_SPAN := 40


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var label := Args.text(args, "label", "egozspeak1")

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var score = preview.get("_score")
	var labels = preview.get("_labels")
	var table = preview.get("_table")
	if score == null or table == null:
		print("no movie loaded")
		quit(1)
		return

	h.begin("Copy ink with the blend flag is keyed by its matte")

	var movie := str(preview.call("movie_name")).to_lower()
	if not movie.begins_with("batzegoz"):
		print("this harness needs Rating's BATZEGOZ.dir and got '%s'." % movie)
		print("run: godot --headless --path . --script tools/ink_blend_matte.gd"
			+ " -- --file BATZEGOZ.dir")
		quit(1)
		return

	var start := -1
	if labels != null:
		start = int(labels.labels.get(label.to_lower(), -1))
	if start < 0:
		print("no marker '%s' in %s" % [label, movie])
		quit(1)
		return

	# The playhead is deliberately not stepped here. `tools/hotspots.gd` records
	# what that costs on this exact movie -- it parks on `go to the frame` and 400
	# steps do not reach frame 194 -- and nothing being asserted is time
	# dependent: these are pixels, not a wait. The index is pinned so that
	# anything reading the node agrees with the frame the score was read at.
	var found: Dictionary = {}
	var found_frame := -1
	for i in range(start, mini(start + SEGMENT_SPAN, score.frame_count)):
		for value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = value
			if (int(sprite["ink"]) & Ink.INK_MASK) != Ink.COPY:
				continue
			if not bool(sprite.get("has_blend", false)):
				continue
			var m: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if int(m.get("type", 0)) != Ink.TYPE_BITMAP:
				continue
			found = sprite
			found_frame = i
			break
		if found_frame >= 0:
			break

	h.check(
		"the segment contains a Copy sprite carrying the blend flag",
		found_frame >= 0,
		("found on frame %d of %d..%d" % [found_frame, start, start + SEGMENT_SPAN])
			if found_frame >= 0
			else ("none in frames %d..%d of %s" % [start, start + SEGMENT_SPAN, movie])
	)
	if found_frame < 0:
		h.complete("Copy ink with the blend flag is keyed by its matte")
		quit(h.finish("Copy-with-blend keying"))
		return

	preview._index = found_frame
	var lib := int(found["cast_lib"])
	var id := int(found["cast_id"])
	var member: Dictionary = table.get_member(lib, id)
	print("%s  frame %d (%s)  ch%d  %d:%d '%s'  %dx%d  %d bpp  ink %d +blend, amount %d" % [
		movie, found_frame, label, int(found["channel"]), lib, id,
		str(member.get("name", "")), int(member.get("width", 0)),
		int(member.get("height", 0)), int(member.get("bits_per_pixel", 0)),
		int(found["ink"]), int(found.get("blend_amount", 0)),
	])

	h.check(
		"the engine asks for a matte",
		Ink.key_for(found, member) == Ink.KEY_MATTE,
		"key_for answered %d, wanted %d" % [Ink.key_for(found, member), Ink.KEY_MATTE]
	)

	# Through the node's own `_texture_for`, so this is the call the renderer makes
	# with the arguments the renderer passes -- not a re-implementation of it.
	var texture: Texture2D = preview.call("_texture_for", found)
	var key := Geometry.texture_key(found, Geometry.drawn_size(found, member))
	var hits: Dictionary = preview.get("_hit_images")
	var image: Image = hits.get(key)
	if texture == null or image == null:
		h.check("the sprite decoded", false, "no texture or hit image for %s" % key)
		h.complete("Copy ink with the blend flag is keyed by its matte")
		quit(h.finish("Copy-with-blend keying"))
		return

	var w := image.get_width()
	var hgt := image.get_height()
	var corners: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, hgt - 1), Vector2i(w - 1, hgt - 1),
	]
	# The details on every check below are the *measurement*, not failure prose:
	# `harness.check` prints them whether it passed or failed, so a sentence about
	# what went wrong reads as an accusation on a green line.
	var opaque_corners: Array[String] = []
	for p in corners:
		if image.get_pixel(p.x, p.y).a > 0.0:
			opaque_corners.append("(%d,%d)" % [p.x, p.y])
	h.check(
		"every corner of the artwork is keyed out",
		opaque_corners.is_empty(),
		"%d of 4 still opaque%s" % [
			opaque_corners.size(),
			"" if opaque_corners.is_empty() else ": " + ", ".join(opaque_corners),
		]
	)
	h.check(
		"the middle of the artwork survives",
		image.get_pixel(w / 2, hgt / 2).a > 0.0,
		"centre alpha %.2f" % image.get_pixel(w / 2, hgt / 2).a
	)

	var cleared := _clear_count(image)
	var total := w * hgt
	h.check(
		"the keyed area is a paper's worth, not nothing and not everything",
		cleared > total / 20 and cleared < total * 9 / 10,
		"%d of %d px cleared" % [cleared, total]
	)

	# Attribution. The same record with the flag cleared must come back solid: that
	# is what says the blend flag is what changed the picture. It also exercises the
	# cache key -- with `has_blend` missing from it this would read the keyed image
	# straight back out of `_hit_images` and pass while proving nothing.
	var plain := found.duplicate()
	plain["has_blend"] = false
	h.check(
		"clearing the blend flag asks for no keying",
		Ink.key_for(plain, member) == Ink.KEY_NONE,
		"key_for = %d without the flag, KEY_NONE is %d"
			% [Ink.key_for(plain, member), Ink.KEY_NONE]
	)
	preview.call("_texture_for", plain)
	var plain_key := Geometry.texture_key(plain, Geometry.drawn_size(plain, member))
	var plain_image: Image = hits.get(plain_key)
	h.check(
		"and brings the white rectangle back",
		plain_key != key and plain_image != null and _clear_count(plain_image) == 0,
		"key %s, %s" % [
			plain_key,
			"no image" if plain_image == null
				else "%d px cleared" % _clear_count(plain_image),
		]
	)

	# Enclosed white survives a matte and would not survive paper keying. On this
	# member that difference is the whites of the eyes, and it is the whole reason
	# the fix is a matte rather than "treat Copy as Background Transparent".
	var f = table.file_for(lib)
	var errors: Array = []
	var fresh: Image = Bitmap.decode(
		member, f.read_chunk(int(member.get("data_chunk_id", -1))),
		preview.get("_palette"), errors
	)
	var papered := -1
	if fresh != null:
		papered = Ink.key_paper(
			fresh, Ink.colour_of(preview.get("_palette"), int(found.get("back_color", 0))))
	h.check(
		"white enclosed by artwork survives the matte",
		papered > cleared,
		"paper keying drops %d, the matte drops %d, so %d px are enclosed"
			% [papered, cleared, papered - cleared]
	)

	# The deliberate divergence, asserted so it cannot be tidied away.
	h.check(
		"and the sprite still hit-tests as its whole rectangle",
		not Ink.hits_per_pixel(int(found["ink"]), int(member.get("type", 0))),
		"hits_per_pixel = %s, and Director answers true for Matte ink only"
			% str(Ink.hits_per_pixel(int(found["ink"]), int(member.get("type", 0))))
	)

	print("  keyed %d of %d px; paper keying would drop %d (%d enclosed)" % [
		cleared, total, papered, papered - cleared])
	h.complete("Copy ink with the blend flag is keyed by its matte")
	quit(h.finish("Copy-with-blend keying"))


func _clear_count(image: Image) -> int:
	var clear := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.0:
				clear += 1
	return clear
