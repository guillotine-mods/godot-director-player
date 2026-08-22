extends SceneTree
## Mask ink (§2.6): the next cast member is a 1-bit stencil, and it is applied.
##
##   godot --headless --audio-driver Dummy --path . --script tools/mask_ink.gd
##   godot --headless --audio-driver Dummy --path . --script tools/mask_ink.gd -- \
##     --root rating --boot mainmenu.dir
##   godot --headless --audio-driver Dummy --path . --script tools/mask_ink.gd -- --scan
##
##   --file PATH   the container to take members from (default: the boot movie)
##   --scan        list every (member, member + 1) pair of the root that could be
##                 a Mask sprite and its mask, and print what each pair is
##
## ## What is real here and what is not, stated first
##
## **0 of 8,079,420 sprite records in all eight roots carry ink 9**
## (`tools/ink_survey.gd -- --all`, 491 scores, `games/` and `test-games/`). So no
## score in this project can drive this feature and none ever will; that is a
## measurement of the corpus and, per `AGENTS.md`, a reason to build it *after*
## the things the corpus does exercise rather than a reason not to build it.
##
## What that leaves is this shape, which is the same one `tools/sprite_flip.gd`
## takes for flip: **the cast members, their `BITD` bytes, their registration
## points, the palette, the cast table and the whole of `sprite_art.texture_for`
## are real and come off the disc.** The one thing composed here is the sprite
## record -- a Director author setting a sprite's ink to Mask in the score, which
## is one byte this corpus's authors never set.
##
## ## What it asserts, and why each check is not the same check twice
##
##   1. a pixel the mask's bit is SET at survives          -- polarity, one way
##   2. a pixel the mask's bit is CLEAR at is cleared      -- polarity, the other
##   3. the same pixel under Copy ink is untouched         -- it is the *ink* doing
##                                                            it, not the decode
##   4. the cleared count equals the mask's own clear-bit
##      count over the overlap, plus everything outside it -- the whole surface,
##                                                            not two lucky pixels
##   5. a sprite outside the mask member's rect is cleared -- rule 2 of
##                                                            `Ink.apply_mask`:
##                                                            the scratch surface
##                                                            is zeroed, so a
##                                                            small mask CROPS
##   6. a mask member that is not 1-bit is refused and the
##      sprite draws UNMASKED                              -- the reference warns
##                                                            and returns null,
##                                                            and unmasked is the
##                                                            direction that does
##                                                            not make art vanish
##
## Check 3 is the control that makes the rest mean something: without it every
## other check passes for a decoder that happened to produce transparent pixels.
##
## Title-agnostic: it names no member, no movie and no game. The pair it asserts
## about is the one whose mask covers the most of its artwork, chosen by
## `_find_pair` from the container it was pointed at.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Bitmap := preload("res://director/director_bitmap.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const Paths := preload("res://director/director_paths.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var paths := Paths.new()
	paths.load_config()
	var only := Args.text(args, "file", "")
	if only != "":
		var resolved: String = paths.resolve(only)
		if resolved == "" or not preview.call("_load_container", resolved):
			h.begin("the container opened")
			h.check("--file names a container of this root", false, only)
			quit(h.finish("Mask ink"))
			return
		await process_frame

	var table = preview.get("_table")
	var palette: PackedByteArray = preview.get("_palette")
	if table == null:
		h.begin("a cast table")
		h.check("the movie opened a cast table", false)
		quit(h.finish("Mask ink"))
		return

	if Args.flag(args, "scan"):
		await _scan(preview, paths)
		quit(0)
		return

	var pair := _find_pair(table, true)
	print("movie : %s" % str(preview.call("movie_name")))
	if pair.is_empty():
		# Nothing to drive the feature with. Said out loud and asserted as a
		# failure of *this run's inputs*, which is what `AGENTS.md` asks for over
		# a harness that quietly asserts nothing.
		print("no (member, member+1) pair in this container has a 1-bit bitmap"
			+ " as the second, so there is nothing to stencil with")
		h.begin("a pair to assert about")
		h.check("the container holds a bitmap followed by a 1-bit bitmap", false,
			"try --scan over the root")
		h.complete("a pair to assert about")
		quit(h.finish("Mask ink"))
		return

	var lib := int(pair["cast_lib"])
	var id := int(pair["cast_id"])
	var art: Dictionary = table.get_member(lib, id)
	var mask: Dictionary = table.get_member(lib, id + 1)
	var mask_w := int(mask.get("width", 0))
	var mask_h := int(mask.get("height", 0))
	print("art   : %d:%d %s %dx%d %d-bit" % [lib, id, str(art.get("name", "")),
		int(art.get("width", 0)), int(art.get("height", 0)),
		int(art.get("bits_per_pixel", 8))])
	print("mask  : %d:%d %s %dx%d 1-bit, overlapping %d pixel(s) of the sprite" % [
		lib, id + 1, str(mask.get("name", "")), mask_w, mask_h,
		int(pair.get("overlap", 0))])

	var f = table.file_for(lib)
	var bit_error: Array = []
	var bits := Bitmap.mask_bits(
		mask, f.read_chunk(int(mask.get("data_chunk_id", -1))), bit_error)
	h.begin("the mask member's bits decode")
	h.check("the 1-bit member unpacked to one byte per pixel",
		bits.size() == mask_w * mask_h,
		"%d bytes for %dx%d%s" % [bits.size(), mask_w, mask_h,
			"" if bit_error.is_empty() else ", " + str(bit_error[0])])
	var set_bits := 0
	for b in bits:
		if b != 0:
			set_bits += 1
	# A mask that is all-set or all-clear cannot separate a working stencil from a
	# no-op in one direction or the other, so the run says so rather than passing
	# on a picture that could not have failed.
	h.check("the mask has both set and clear bits, so both polarities are tested",
		set_bits > 0 and set_bits < bits.size(),
		"%d of %d bits set" % [set_bits, bits.size()])
	h.complete("the mask member's bits decode")

	var masked := _image_for(preview, table, palette, lib, id, Ink.MASK)
	var plain := _image_for(preview, table, palette, lib, id, Ink.COPY)
	h.begin("both readings of the sprite decoded")
	h.check("the artwork decodes under Mask ink", masked != null)
	h.check("the artwork decodes under Copy ink", plain != null)
	h.complete("both readings of the sprite decoded")
	if masked == null or plain == null:
		quit(h.finish("Mask ink"))
		return

	# Where the mask sits inside the artwork, recomputed here from the two
	# members rather than read back out of the code under test.
	var drawn := Geometry.drawn_size(_record(lib, id, Ink.MASK), art)
	var offset := Vector2i((Geometry.scaled_reg(art, drawn) - Vector2(
		float(mask.get("reg_offset_x", 0)), float(mask.get("reg_offset_y", 0)))).round())
	var shown := _first_pixel(bits, mask_w, mask_h, offset, drawn, true)
	var hidden := _first_pixel(bits, mask_w, mask_h, offset, drawn, false)
	print("align : mask top-left at (%d,%d) inside a %dx%d sprite"
		% [offset.x, offset.y, int(drawn.x), int(drawn.y)])

	h.begin("the stencil is applied, and the polarity is the reference's")
	if shown.x >= 0:
		h.check("a pixel the mask's bit is SET at is drawn",
			masked.get_pixel(shown.x, shown.y).a > 0.0,
			"(%d,%d) alpha %.2f" % [shown.x, shown.y,
				masked.get_pixel(shown.x, shown.y).a])
	else:
		h.check("a pixel the mask's bit is SET at is inside the sprite", false,
			"the mask's set bits all fall outside the artwork")
	if hidden.x >= 0:
		h.check("a pixel the mask's bit is CLEAR at is cleared",
			masked.get_pixel(hidden.x, hidden.y).a == 0.0,
			"(%d,%d) alpha %.2f" % [hidden.x, hidden.y,
				masked.get_pixel(hidden.x, hidden.y).a])
		# The control. Same member, same bytes, same decode, same size -- only the
		# ink byte differs. Without this every check above passes for a member
		# that simply decoded to transparent pixels.
		h.check("the same pixel under Copy ink is untouched, so it is the INK",
			plain.get_pixel(hidden.x, hidden.y).a > 0.0,
			"(%d,%d) alpha %.2f under Copy" % [hidden.x, hidden.y,
				plain.get_pixel(hidden.x, hidden.y).a])
	else:
		h.check("a pixel the mask's bit is CLEAR at is inside the sprite", false,
			"the mask's clear bits all fall outside the artwork")
	h.complete("the stencil is applied, and the polarity is the reference's")

	# The whole surface, counted independently: every pixel of the sprite that the
	# mask does not light up must be clear, whether it is a clear bit or is
	# outside the mask member's rect entirely.
	var want_clear := 0
	var got_clear := 0
	var outside_clear := 0
	var outside_total := 0
	for y in int(drawn.y):
		for x in int(drawn.x):
			var mx := x - offset.x
			var my := y - offset.y
			var inside := mx >= 0 and my >= 0 and mx < mask_w and my < mask_h
			var lit := inside and bits[my * mask_w + mx] != 0
			if not inside:
				outside_total += 1
				if masked.get_pixel(x, y).a == 0.0:
					outside_clear += 1
			if not lit:
				want_clear += 1
			if masked.get_pixel(x, y).a == 0.0:
				got_clear += 1
	h.begin("the stencil covers the whole sprite, not two sampled pixels")
	h.check("every pixel the mask does not light is clear, and no other is",
		want_clear == got_clear, "%d wanted, %d cleared" % [want_clear, got_clear])
	# `Ink.apply_mask` rule 2. The reference creates the scratch surface at the
	# channel's size and zeroes it before copying the mask in, so a mask smaller
	# than the sprite crops the sprite rather than leaving the remainder visible.
	# Reported rather than skipped when the mask covers everything, because a
	# silent skip is how a check with no subject reads as a check that passed.
	if outside_total > 0:
		h.check("the sprite is CROPPED to the mask member's own rect",
			outside_clear == outside_total,
			"%d of %d pixels outside the mask are clear" % [outside_clear, outside_total])
	else:
		h.check("the mask member covers the whole sprite, so cropping is untested",
			true, "0 pixels of the sprite fall outside the mask")
	h.complete("the stencil covers the whole sprite, not two sampled pixels")

	# The refusal. A mask member that is not 1-bit is a warning and a null mask in
	# the reference, and a null mask means an unstencilled blit.
	var bad := _find_pair(table, false)
	h.begin("a mask that is not 1-bit leaves the sprite unmasked")
	if bad.is_empty():
		h.check("this container has no non-1-bit pair to refuse, so it is untested",
			true, "every (n, n+1) bitmap pair here has a 1-bit second member")
	else:
		var bad_lib := int(bad["cast_lib"])
		var bad_id := int(bad["cast_id"])
		var reason := SpriteArt.apply_mask_member(
			_record(bad_lib, bad_id, Ink.MASK), table.get_member(bad_lib, bad_id),
			Image.create_empty(4, 4, false, Image.FORMAT_RGBA8), Vector2(4, 4), table)
		h.check("the refusal says which of the three it was", reason != "", reason)
		var bad_masked := _image_for(preview, table, palette, bad_lib, bad_id, Ink.MASK)
		var bad_plain := _image_for(preview, table, palette, bad_lib, bad_id, Ink.COPY)
		h.check("the sprite draws the same pixels it would under Copy",
			bad_masked != null and bad_plain != null
				and bad_masked.get_data() == bad_plain.get_data(),
			"%d:%d against %d:%d" % [bad_lib, bad_id, bad_lib, bad_id + 1])
	h.complete("a mask that is not 1-bit leaves the sprite unmasked")

	quit(h.finish("Mask ink stencils a sprite by the next cast member"))


## A sprite record naming `lib:id` at the member's natural size with `ink`.
##
## Composed, and the docstring at the top says why it has to be. Width and height
## are left at 0 so `drawn_size` answers the member's own size and no resample
## enters the comparison -- a mask asserted against a nearest-neighbour resize
## would be asserting the resampler.
static func _record(lib: int, id: int, ink: int) -> Dictionary:
	return {
		"channel": 1, "cast_lib": lib, "cast_id": id, "ink": ink,
		"loc_h": 0, "loc_v": 0, "width": 0, "height": 0,
		"fore_color": Ink.INDEX_BLACK, "back_color": Ink.INDEX_WHITE,
	}


## The decoded, keyed artwork the renderer would draw, through the real path.
##
## Reached through `texture_for` rather than by calling the mask code directly,
## so what is asserted is what a repaint produces -- including the cache key, the
## palette resolution and the ordering of keying against colourisation.
func _image_for(preview: Node, table, palette: PackedByteArray, lib: int, id: int,
		ink: int) -> Image:
	var sprite := _record(lib, id, ink)
	var textures: Dictionary = {}
	var hit_images: Dictionary = {}
	SpriteArt.texture_for(sprite, table, palette, textures, hit_images)
	var m: Dictionary = table.get_member(lib, id)
	var key := Geometry.texture_key(sprite, Geometry.drawn_size(sprite, m))
	return hit_images.get(key, null)


## The first pixel of the sprite where the mask's bit is set (or clear).
static func _first_pixel(bits: PackedByteArray, mask_w: int, mask_h: int,
		offset: Vector2i, drawn: Vector2, want_set: bool) -> Vector2i:
	for y in int(drawn.y):
		for x in int(drawn.x):
			var mx := x - offset.x
			var my := y - offset.y
			if mx < 0 or my < 0 or mx >= mask_w or my >= mask_h:
				continue
			if (bits[my * mask_w + mx] != 0) == want_set:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A (member, member + 1) pair where the first is a bitmap this renderer draws and
## the second is a bitmap of one bit (`want_1bit`) or of more than one.
##
## **The pair with the largest overlap wins, not the first one found**, and that
## is not a preference for a prettier picture. The two members are aligned by
## registration point, so a mask can land almost entirely outside the artwork --
## `DAY1.dir`'s first pair is a 9x2 member against an 11x16 cursor and shares 14
## pixels with it. Every per-pixel check below is then asserted over a handful of
## pixels that happen to fall in the overlap, and the run reads as green while
## covering almost nothing. Scoring by overlap picks the strongest subject the
## container actually holds, and the score is printed so a thin one is visible
## rather than silent.
func _find_pair(table, want_1bit: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_overlap := -1
	for lib in table.cast_libs.keys():
		var cast = table.cast_for(int(lib))
		if cast == null:
			continue
		for i in int(cast.member_count):
			var id := int(cast.min_member) + i
			var art: Dictionary = table.get_member(int(lib), id)
			var mask: Dictionary = table.get_member(int(lib), id + 1)
			if art.is_empty() or mask.is_empty():
				continue
			if int(art.get("type", 0)) != Ink.TYPE_BITMAP \
					or int(mask.get("type", 0)) != Ink.TYPE_BITMAP:
				continue
			if int(art.get("bits_per_pixel", 8)) == 1:
				# The artwork itself being 1-bit would put the check on the wrong
				# side of `key_for`'s 1-bit exception and make the two readings
				# harder to tell apart than they need to be.
				continue
			if (int(mask.get("bits_per_pixel", 8)) == 1) != want_1bit:
				continue
			if int(art.get("width", 0)) <= 0 or int(art.get("height", 0)) <= 0:
				continue
			var overlap := _overlap_of(art, mask)
			if overlap <= best_overlap:
				continue
			best_overlap = overlap
			best = {"cast_lib": int(lib), "cast_id": id, "overlap": overlap}
	return best


## How many pixels of the sprite the mask member would cover, at the alignment
## `Ink.apply_mask` uses. Derived here from the two members' own geometry, the
## same way `_init` derives the offset it asserts against.
func _overlap_of(art: Dictionary, mask: Dictionary) -> int:
	var drawn := Geometry.drawn_size(_record(0, 0, Ink.MASK), art)
	var offset := (Geometry.scaled_reg(art, drawn) - Vector2(
		float(mask.get("reg_offset_x", 0)), float(mask.get("reg_offset_y", 0)))).round()
	var shared := Rect2(Vector2.ZERO, drawn).intersection(Rect2(offset,
		Vector2(float(mask.get("width", 0)), float(mask.get("height", 0)))))
	return int(shared.size.x) * int(shared.size.y)


## Every candidate pair in every container of the root, with what each one is.
##
## Walks the whole root rather than the one movie, because a mask member is a
## *cast* member and this corpus keeps its 1-bit art in shared casts a single
## room movie may not link. Prints; asserts nothing.
func _scan(preview: Node, paths) -> void:
	var targets: Array[String] = []
	_walk(paths.root, targets)
	targets.sort()
	var depths: Dictionary = {}
	var pairs := 0
	var shown := 0
	print("%-22s %-12s %-8s %-22s" % ["container", "art", "depth", "mask (next member)"])
	for path in targets:
		if not preview.call("_load_container", path):
			continue
		await process_frame
		var table = preview.get("_table")
		if table == null:
			continue
		for lib in table.cast_libs.keys():
			var cast = table.cast_for(int(lib))
			if cast == null:
				continue
			for i in int(cast.member_count):
				var id := int(cast.min_member) + i
				var art: Dictionary = table.get_member(int(lib), id)
				if art.is_empty() or int(art.get("type", 0)) != Ink.TYPE_BITMAP:
					continue
				var depth := int(art.get("bits_per_pixel", 8))
				depths[depth] = int(depths.get(depth, 0)) + 1
				if depth == 1:
					continue
				var mask: Dictionary = table.get_member(int(lib), id + 1)
				if mask.is_empty() or int(mask.get("type", 0)) != Ink.TYPE_BITMAP:
					continue
				if int(mask.get("bits_per_pixel", 8)) != 1:
					continue
				pairs += 1
				shown += 1
				if shown <= 40:
					print("%-22s %-12s %-8d %-22s" % [
						path.get_file(), "%d:%d %s" % [int(lib), id,
							str(art.get("name", ""))], depth,
						"%d:%d %s %dx%d" % [int(lib), id + 1,
							str(mask.get("name", "")), int(mask.get("width", 0)),
							int(mask.get("height", 0))]])
	print("")
	print("%d usable pair(s) over %d container(s); bitmap members by depth: %s"
		% [pairs, targets.size(), str(depths)])


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
