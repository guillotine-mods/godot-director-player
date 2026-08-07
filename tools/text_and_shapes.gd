extends SceneTree
## Do field members and shape members actually reach the stage, and do the ones
## that are meant to stay invisible stay clickable?
##
##   godot --headless --script tools/text_and_shapes.gd -- --file PIP2DATA/DAY1.dir
##   godot --headless --script tools/text_and_shapes.gd -- --file PIP2DATA/SAVELOAD.dir
##
## `scenes/director_preview.gd:_texture_for` used to answer null for every member
## whose type was not 1, so two whole cast types drew nothing: 11,525 field sprite
## records and 60,914 shape records across this corpus. The field half is the
## game's HUD — its score, its inventory, its process list — and the Lingo behind
## it worked the whole time and had nowhere to show it.
##
## The shape half is the opposite problem and the one worth being careful about.
## 60,100 of those 60,914 records name an unfilled rectangle whose stored line
## thickness is 1, which Director draws as **nothing** (13, and see
## `director/director_shape.gd`). They are invisible hotspots. So "shapes now
## render" must not mean "60,000 rectangles appeared on screen"; it means the few
## filled ones paint and the rest go on catching clicks while painting nothing.
## Both halves of that are asserted below, and the second is the regression this
## file exists to catch.
##
## Reads the real preview node, so what it checks is what the game sees. It sets
## the playhead directly rather than stepping: this asserts the *renderer*, and a
## room that holds on `go to the frame` would never step to the frames where the
## interesting sprites are.
##
## **What cannot be asserted here.** Headless Godot builds the draw list and
## discards it, so there is no painted surface to read back and no pixel test for
## text. `Shape.render` and the bitmap path return `Image`s and *are* checked at
## pixel level. For text the closest available thing is `_text_drawn`, which the
## paint fills in with the string, the box and the line count it actually laid
## out — enough to tell "the text reached the canvas" from "the sprite was
## skipped", which is the failure this replaces, and not enough to tell whether a
## glyph landed on the right pixel. Nothing here claims otherwise.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Shape := preload("res://director/director_shape.gd")
const Text := preload("res://director/director_text.gd")
const Palette := preload("res://director/director_palette.gd")

const STAGE := Vector2(640, 480)


func _opaque_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				count += 1
	return count


## Every pixel that is painted at all, and whether they are all one colour.
func _painted_colours(image: Image) -> Dictionary:
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			seen["%d,%d,%d" % [c.r8, c.g8, c.b8]] = true
	return seen


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	# Paused for the whole run. This sets the playhead directly and then waits a
	# process frame to get a paint, and an unpaused preview would step the movie
	# during that wait — running the frame scripts, which is how the field-write
	# case below lost its sentinel to the game putting its own value back one
	# frame later. Pausing stops the clock; `queue_redraw` still paints.
	preview.set("_paused", true)

	var score = preview.get("_score")
	var table = preview.get("_table")
	if score == null:
		print("no score loaded")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))
	var palette: PackedByteArray = preview.get("_palette")

	# ------------------------------------------------------- the ink rules alone
	# First, because everything below depends on them and they need no movie. Both
	# directions each time: a rule that answered yes everywhere would satisfy half
	# of these and be useless.
	h.begin("the applyColor switch and the matte rule")
	h.check("default colours never colourise, whatever the ink",
		not Ink.applies_colour(Ink.BACKGND_TRANS, Ink.INDEX_BLACK, Ink.INDEX_WHITE)
		and not Ink.applies_colour(Ink.COPY, Ink.INDEX_BLACK, Ink.INDEX_WHITE)
		and not Ink.applies_colour(Ink.MATTE, Ink.INDEX_BLACK, Ink.INDEX_WHITE))
	h.check("a non-default colour colourises the inks that admit it",
		Ink.applies_colour(Ink.BACKGND_TRANS, 245, Ink.INDEX_WHITE)
		and Ink.applies_colour(Ink.COPY, Ink.INDEX_BLACK, 255))
	h.check("and never the inks that do not",
		not Ink.applies_colour(Ink.BLEND, 245, Ink.INDEX_WHITE)
		and not Ink.applies_colour(Ink.REVERSE, 245, Ink.INDEX_WHITE)
		and not Ink.applies_colour(Ink.ADD, 245, Ink.INDEX_WHITE))
	h.check("matte hit-tests per pixel on a bitmap",
		Ink.hits_per_pixel(Ink.MATTE, Ink.TYPE_BITMAP))
	h.check("and as a rectangle on a shape, which has no image to flood",
		not Ink.hits_per_pixel(Ink.MATTE, Ink.TYPE_SHAPE))
	h.check("a keying ink that is not matte still hit-tests as a rectangle",
		not Ink.hits_per_pixel(Ink.BACKGND_TRANS, Ink.TYPE_BITMAP))
	h.complete("the applyColor switch and the matte rule")

	# ------------------------------------------------------------ colourisation
	# Against a synthetic image, because the corpus barely exercises this: only 7
	# distinct bitmap sprites in 61 movies ever colourise. A made-up image is the
	# honest way to assert a rule that real data cannot cover, and it is labelled
	# as such rather than dressed up as a corpus measurement.
	h.begin("colourisation repaints black and white and leaves the rest")
	var probe := Image.create_empty(3, 1, false, Image.FORMAT_RGBA8)
	probe.set_pixel(0, 0, Color(0, 0, 0, 1))
	probe.set_pixel(1, 0, Color(1, 1, 1, 1))
	var middle := Color8(120, 30, 200)
	probe.set_pixel(2, 0, middle)
	var fore := Color8(255, 0, 0)
	var back := Color8(0, 0, 255)
	var changed := Ink.apply_colour(probe, fore, back)
	h.check("black became the foreground colour",
		probe.get_pixel(0, 0).r8 == fore.r8 and probe.get_pixel(0, 0).b8 == fore.b8,
		str(probe.get_pixel(0, 0)))
	h.check("white became the background colour",
		probe.get_pixel(1, 0).b8 == back.b8 and probe.get_pixel(1, 0).r8 == back.r8,
		str(probe.get_pixel(1, 0)))
	# The clause that keeps colourisation from eating artwork. Director's Copy arm
	# leaves every other pixel as the *destination*, which is a hole; leaving it as
	# the source is the conservative half of that rule, and either way it must not
	# be repainted.
	h.check("a colour that is neither is untouched",
		probe.get_pixel(2, 0).r8 == middle.r8 and probe.get_pixel(2, 0).g8 == middle.g8
		and probe.get_pixel(2, 0).b8 == middle.b8, str(probe.get_pixel(2, 0)))
	h.check("it reported exactly the two it changed", changed == 2, "%d" % changed)
	h.complete("colourisation repaints black and white and leaves the rest")

	# ----------------------------------------- colourisation, on real cast art
	# The synthetic case above says the remapping is right; this says it reaches
	# the artwork. Very few sprites in this corpus qualify — 651 records on 7
	# distinct bitmap sprites in 61 movies — so most movies skip this entirely and
	# that is the honest outcome rather than a hole.
	var colourised := {}
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			if not Ink.applies_colour(int(sprite["ink"]),
					int(sprite["fore_color"]), int(sprite["back_color"])):
				continue
			var m: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if int(m.get("type", 0)) != Ink.TYPE_BITMAP:
				continue
			var key := "%d:%d:%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"]),
				int(sprite["fore_color"]), int(sprite["back_color"])]
			if not colourised.has(key):
				colourised[key] = {"frame": i, "sprite": sprite, "member": m}
	if not colourised.is_empty():
		h.begin("a bitmap with non-default colours comes out repainted")
		var survived: Array = []
		var undrawn: Array = []
		for key in colourised:
			var entry: Dictionary = colourised[key]
			var sprite: Dictionary = entry["sprite"]
			if preview.call("_texture_for", sprite) == null:
				undrawn.append(key)
				continue
			var images: Dictionary = preview.get("_hit_images")
			var cache_key := str(preview.call("_texture_key", sprite,
				preview.call("_drawn_size", sprite, entry["member"])))
			var image: Image = images.get(cache_key)
			if image == null:
				undrawn.append(key)
				continue
			# What applyColor guarantees, stated directly against the pixels: if the
			# foreground is not black then no opaque black can be left, and if the
			# background is not white then no opaque white can be left. Both are
			# checked only where they apply, so a sprite that changes only one of
			# the two is not held to the other.
			var wants_no_black := int(sprite["fore_color"]) != Ink.INDEX_BLACK
			var wants_no_white := int(sprite["back_color"]) != Ink.INDEX_WHITE
			var black := 0
			var white := 0
			for y in image.get_height():
				for x in image.get_width():
					var c := image.get_pixel(x, y)
					if c.a <= 0.5:
						continue
					if c.r8 == 0 and c.g8 == 0 and c.b8 == 0:
						black += 1
					elif c.r8 == 255 and c.g8 == 255 and c.b8 == 255:
						white += 1
			print("   f%-5d %-16s %-14s fore%d back%d ink%d -> %d black, %d white left" % [
				int(entry["frame"]), key, str(entry["member"].get("name", "")),
				int(sprite["fore_color"]), int(sprite["back_color"]),
				int(sprite["ink"]), black, white])
			if wants_no_black and black > 0:
				survived.append("%s kept %d black" % [key, black])
			if wants_no_white and white > 0:
				survived.append("%s kept %d white" % [key, white])
		h.check("each of them decoded to an image", undrawn.is_empty(),
			", ".join(PackedStringArray(undrawn)))
		h.check("no pixel Director would have repainted survived", survived.is_empty(),
			", ".join(PackedStringArray(survived)))
		h.complete("a bitmap with non-default colours comes out repainted")

	# ----------------------------------------------- what this movie has to show
	# Found by walking the score rather than named: which frame holds a field is a
	# property of the movie, and writing one in would make this tool about one game.
	var field_frames := {}
	var invisible_shapes := {}
	var filled_shapes := {}
	var matte_shapes := {}
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var m: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if m.is_empty():
				continue
			var key := "%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])]
			match int(m.get("type", 0)):
				Ink.TYPE_FIELD:
					if not field_frames.has(key):
						field_frames[key] = {"frame": i, "sprite": sprite, "member": m}
				Ink.TYPE_SHAPE:
					var draws: bool = int(m.get("fill_type", 0)) != 0 \
						or int(m.get("line_thickness", 1)) > 1
					var into: Dictionary = filled_shapes if draws else invisible_shapes
					if not into.has(key):
						into[key] = {"frame": i, "sprite": sprite, "member": m}
					if Ink.hits_per_pixel(int(sprite["ink"]), Ink.TYPE_BITMAP) \
							and not matte_shapes.has(key):
						matte_shapes[key] = {"frame": i, "sprite": sprite, "member": m}

	print("%s: %d field member(s), %d shape member(s) that paint, %d that do not, %d matte-inked"
		% [movie, field_frames.size(), filled_shapes.size(),
			invisible_shapes.size(), matte_shapes.size()])
	print("")

	# ------------------------------------------------------------------- fields
	# Skipped rather than failed when the movie has none: "every movie has a field
	# on screen" is not a property of Director and a gate that failed on a movie
	# without one would be teaching the wrong lesson.
	if not field_frames.is_empty():
		h.begin("every field on the stage lays out text where the score put it")
		var blank: Array = []
		var offstage: Array = []
		var wrong_box: Array = []
		var unstyled: Array = []
		var checked := 0
		for key in field_frames:
			var entry: Dictionary = field_frames[key]
			# The playhead is set directly: this is about the renderer, and a room
			# that holds would never step to the frame the field is on.
			preview.set("_index", int(entry["frame"]))
			preview.call("queue_redraw")
			await process_frame
			var drawn: Dictionary = preview.get("_text_drawn")
			var channel := int(entry["sprite"]["channel"])
			if not drawn.has(channel):
				blank.append("ch%d m%s never reached the paint" % [channel, key])
				continue
			checked += 1
			var laid: Dictionary = drawn[channel]
			var rect: Rect2 = laid["rect"]
			print("   f%-5d ch%-4d %-16s %2d lines, %2dpt, box (%d,%d) %dx%d  %s" % [
				int(entry["frame"]), channel, str(laid["name"]), int(laid["lines"]),
				int(laid["font_size"]), int(rect.position.x), int(rect.position.y),
				int(rect.size.x), int(rect.size.y),
				str(laid["text"]).substr(0, 28).replace("\n", "\\n")])
			# Something was actually laid out. A field whose text is empty draws no
			# lines legitimately, so the assertion is against members that have text.
			if str(laid["text"]) != "" and int(laid["lines"]) <= 0:
				blank.append("ch%d %s has text and drew no lines" % [channel, str(laid["name"])])
			# The box is the score's, through the single placement rule. A field has
			# no registration point, so its top-left is its own start point.
			if int(rect.size.x) != int(entry["sprite"]["width"]) \
					or int(rect.size.y) != int(entry["sprite"]["height"]):
				wrong_box.append("ch%d %s is %s, score says %dx%d" % [
					channel, str(laid["name"]), str(rect.size),
					int(entry["sprite"]["width"]), int(entry["sprite"]["height"])])
			if rect.position.x > STAGE.x or rect.position.y > STAGE.y \
					or rect.position.x + rect.size.x < 0.0 \
					or rect.position.y + rect.size.y < 0.0:
				offstage.append("ch%d %s at %s" % [channel, str(laid["name"]), str(rect.position)])
			# The style came out of the member's own STXT rather than a default.
			if int(laid["font_size"]) <= 0:
				unstyled.append("ch%d %s" % [channel, str(laid["name"])])
		h.check("a field sprite reached the paint", checked > 0, "%d of %d" % [
			checked, field_frames.size()])
		h.check("every field with text drew at least one line", blank.is_empty(),
			", ".join(PackedStringArray(blank)))
		h.check("every field's box is the size the score gave the sprite",
			wrong_box.is_empty(), ", ".join(PackedStringArray(wrong_box)))
		h.check("no field was laid out off the stage", offstage.is_empty(),
			", ".join(PackedStringArray(offstage)))
		h.check("every field resolved a point size", unstyled.is_empty(),
			", ".join(PackedStringArray(unstyled)))
		# The negative. A field must go through the text path and *only* the text
		# path: if `_texture_for` ever starts answering for one it would be drawn
		# twice, once as glyphs and once as whatever the bitmap decoder made of a
		# member with no BITD.
		var doubled: Array = []
		for key in field_frames:
			var entry: Dictionary = field_frames[key]
			if preview.call("_texture_for", entry["sprite"]) != null:
				doubled.append(key)
		h.check("no field also produces a texture", doubled.is_empty(),
			", ".join(PackedStringArray(doubled)))
		h.complete("every field on the stage lays out text where the score put it")

		# --------------------------------------------------- a script's own write
		# End to end, through the same call the interpreter makes. The write used to
		# be a no-op and the read used to look only in the movie's own cast, so a
		# field in a linked cast — which is where this game keeps its shared HUD —
		# could be neither written nor read. A sentinel no authored field would hold.
		h.begin("what a script puts into a field is what the stage shows")
		var first: Dictionary = field_frames[field_frames.keys()[0]]
		var name := str(first["member"].get("name", ""))
		var before: Variant = preview.call("lingo_field", name, "")
		var sentinel := "9182736450"
		preview.call("lingo_set_field", name, "", sentinel)
		h.check("the field had a name to write to", name != "", name)
		h.check("reading it back gives what was written",
			str(preview.call("lingo_field", name, "")) == sentinel,
			"%s -> %s" % [name, str(preview.call("lingo_field", name, ""))])
		preview.set("_index", int(first["frame"]))
		preview.call("queue_redraw")
		await process_frame
		var after: Dictionary = preview.get("_text_drawn")
		var channel_after := int(first["sprite"]["channel"])
		h.check("and the paint lays out the new text, not the authored one",
			after.has(channel_after)
			and str((after[channel_after] as Dictionary)["text"]) == sentinel,
			"was '%s'" % str(before).substr(0, 20))
		# The negative: a name that is not a field must not resolve to one, or a
		# bitmap sharing a name with a field would silently become the write target.
		h.check("a name no field carries resolves to nothing",
			str(preview.call("lingo_field", "no_such_field_9182736450", "")) == "")
		h.complete("what a script puts into a field is what the stage shows")

	# --------------------------------------------------------- invisible shapes
	if not invisible_shapes.is_empty():
		h.begin("an unfilled shape with a thickness of 1 paints nothing and still catches clicks")
		# Puppet overrides are dropped first. The playhead is moved here without
		# running the scripts that wrote them, so a `set the visible of sprite 6 to
		# 0` from the frame the movie happens to be sitting on would be applied to
		# a frame two thousand later, and the sprite would be reported unclickable
		# for a reason that only exists inside this harness.
		preview.get("_overrides").clear()
		var painted: Array = []
		var textured: Array = []
		var degenerate: Array = []
		var unreachable: Array = []
		var eligible := 0
		for key in invisible_shapes:
			var entry: Dictionary = invisible_shapes[key]
			var sprite: Dictionary = entry["sprite"]
			var size := Vector2i(int(sprite["width"]), int(sprite["height"]))
			if Shape.render(entry["member"], Color.RED, Color.WHITE, size) != null:
				painted.append(key)
			if preview.call("_texture_for", sprite) != null:
				textured.append(key)
			preview.set("_index", int(entry["frame"]))
			var rect: Rect2 = preview.call("_stage_rect", sprite)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				degenerate.append("%s is %s" % [key, str(rect.size)])
				continue
			# Only the ones the movie's own scripts make clickable. A shape with no
			# behaviour is legitimately not a hotspot, and asserting that every
			# shape answers a click would be asserting something Director does not
			# do. The centre is used because a hotspot the player cannot hit in the
			# middle is not a hotspot.
			if not bool(preview.call("_responds_to_mouse", sprite)):
				continue
			eligible += 1
			var found := int(preview.call("_channel_at", rect.get_center()))
			if found < int(sprite["channel"]):
				unreachable.append("%s ch%d at %s -> ch%d" % [
					key, int(sprite["channel"]), str(rect.get_center()), found])
		h.check("none of them paints anything", painted.is_empty(),
			", ".join(PackedStringArray(painted)))
		h.check("none of them produces a texture either", textured.is_empty(),
			", ".join(PackedStringArray(textured)))
		h.check("every one still has a real rect", degenerate.is_empty(),
			", ".join(PackedStringArray(degenerate)))
		# A higher channel legitimately covers a hotspot, so the assertion is that
		# the click is not lost to something *underneath* it — which is what a
		# per-pixel test against nothing produces.
		h.check("a click in the middle of one is not lost to a lower channel",
			unreachable.is_empty(), ", ".join(PackedStringArray(unreachable)))
		# Why the rule above has to exist, stated as a fact rather than as a
		# comment. These shapes have no pixels anywhere, so a per-pixel test —
		# which is what a matte-inked sprite would get if the cast type were not
		# part of `hits_per_pixel` — rejects every point inside them. The check is
		# that `_opaque_at` really does say no, so the day someone re-reads
		# `hits_per_pixel` and decides the type argument looks redundant, this says
		# what removing it costs.
		var solid: Array = []
		for key in invisible_shapes:
			var entry: Dictionary = invisible_shapes[key]
			preview.set("_index", int(entry["frame"]))
			var rect: Rect2 = preview.call("_stage_rect", entry["sprite"])
			if bool(preview.call("_opaque_at", entry["sprite"], rect.get_center())):
				solid.append(key)
		h.check("a per-pixel test would reject all of them, which is why it is not used",
			solid.is_empty(), ", ".join(PackedStringArray(solid)))
		print("   %d invisible shape(s), %d of them clickable by the movie's own scripts"
			% [invisible_shapes.size(), eligible])
		h.complete("an unfilled shape with a thickness of 1 paints nothing and still catches clicks")

	# ------------------------------------------------------------ shapes that do
	if not filled_shapes.is_empty():
		h.begin("a shape that does paint paints its sprite's foreColor")
		var blank_shape: Array = []
		var wrong_size: Array = []
		var wrong_colour: Array = []
		for key in filled_shapes:
			var entry: Dictionary = filled_shapes[key]
			var sprite: Dictionary = entry["sprite"]
			var size := Vector2i(int(sprite["width"]), int(sprite["height"]))
			var want := Ink.colour_of(palette, int(sprite["fore_color"]))
			var image: Image = Shape.render(entry["member"], want, Color.WHITE, size)
			if image == null:
				blank_shape.append(key)
				continue
			if image.get_width() != size.x or image.get_height() != size.y:
				wrong_size.append("%s is %dx%d, wanted %s" % [
					key, image.get_width(), image.get_height(), str(size)])
			var opaque := _opaque_pixels(image)
			var colours := _painted_colours(image)
			var want_key := "%d,%d,%d" % [want.r8, want.g8, want.b8]
			if colours.size() != 1 or not colours.has(want_key):
				wrong_colour.append("%s painted %s, wanted %s" % [
					key, str(colours.keys()), want_key])
			if opaque == 0:
				blank_shape.append("%s painted no pixels" % key)
			print("   f%-5d %-10s %-14s fill=%d thick=%d  %d/%d px in %s" % [
				int(entry["frame"]), key, str(entry["member"].get("name", "")),
				int(entry["member"].get("fill_type", 0)),
				int(entry["member"].get("line_thickness", 0)),
				opaque, size.x * size.y, want_key])
		h.check("each of them painted something", blank_shape.is_empty(),
			", ".join(PackedStringArray(blank_shape)))
		h.check("at the size the score gave the sprite", wrong_size.is_empty(),
			", ".join(PackedStringArray(wrong_size)))
		h.check("in exactly the sprite's foreColor and nothing else",
			wrong_colour.is_empty(), ", ".join(PackedStringArray(wrong_colour)))
		# The cache key. One member drawn twice in two colours must not hand the
		# second appearance the first one's pixels — which is the whole reason
		# colourisation needs the fore colour in the key.
		var one: Dictionary = filled_shapes[filled_shapes.keys()[0]]
		var recoloured: Dictionary = (one["sprite"] as Dictionary).duplicate()
		recoloured["fore_color"] = 255 if int(recoloured["fore_color"]) != 255 else 0
		h.check("the same member in another colour keys differently in the cache",
			str(preview.call("_texture_key", one["sprite"], Vector2(8, 8)))
			!= str(preview.call("_texture_key", recoloured, Vector2(8, 8))),
			str(preview.call("_texture_key", recoloured, Vector2(8, 8))))
		h.complete("a shape that does paint paints its sprite's foreColor")

	print("")
	quit(h.finish("field and shape members reaching the stage in %s" % movie))
