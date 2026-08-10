extends SceneTree
## Hilite on click: does the pressed sprite invert, and only where it has pixels?
##
##   godot --headless --script tools/hilite.gd -- --file PIP2DATA/DAY1.dir
##   godot           --script tools/hilite.gd -- --file PIP2DATA/DAY1.dir
##
## `DIRECTOR_ENGINE.md` §4.6, implemented in `scenes/preview/hilite.gd`.
##
## **Nothing in this corpus carries the Auto Hilite flag.** 0 of Piposh 2's
## 73,994 cast members, 0 of Piposh 1's 282,995 and 0 of Rating's 75,000
## (`tools/hilite_survey.gd`). Piposh 2 cannot reach the fallback arm either:
## every one of its members has a cast info block, so "no info, Matte ink" never
## fires -- while Piposh 1 has 267,985 sprite records that *do* match it and
## Rating 87,549. So this game's buttons do not use hilite, and the feature is
## built because Director has it (AGENTS.md, "Build Director, not this game").
##
## Which decides how it is tested. The flag is a bit in the container and there
## is no Lingo that sets it -- `the hilite of member` is the button/field
## property and a different mechanism -- so the cases below set `auto_hilite` on
## the **parsed** member, which is the same dictionary the container would have
## produced with the tick box on. Nothing under `games/` is touched or could be.
## `tools/trails.gd` faces the same problem and solves it the same way, through
## the closest lever the port has to the authored bit.
##
## Two levels of evidence, and the second is not optional here:
##
##   headless   the predicate, clause by clause, and the pixels of the inverted
##              image -- both are CPU-side and readable with no renderer.
##   windowed   run without `--headless` and the last case reads the
##              framebuffer. It asserts the inversion **reaches the screen** and
##              that it is a *silhouette*: a point inside the sprite's rectangle
##              but outside its artwork must not change colour. A box-shaped
##              flash passes every headless check and is the wrong picture.
##
## Headless alone proves nothing about a drawing change -- Godot builds the draw
## list and throws it away, so every check can pass while the screen never moves.
## `tools/window_renders.gd` documents that trap at length; it exists because it
## happened.

const Harness := preload("res://tools/lib/harness.gd")
const Hilite := preload("res://scenes/preview/hilite.gd")
const Ink := preload("res://director/director_ink.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")

## The stage, as `director_preview.gd` declares it. A local copy because a
## `const` on the node is not reachable through `get()`, which is the same reason
## `tools/trails.gd` carries one.
const STAGE := Vector2i(640, 480)


## A frame, a channel and two sample points: a bitmap sprite `isActive()` accepts,
## with a pixel of it that nothing paints over and a hole in it that nothing
## paints over either.
##
## Active rather than merely present, because a sprite with nothing attached
## cannot hilite whatever its member says, and a case built on one would assert
## the wrong half of the predicate.
##
## **Highest channel first, and the sample points must be uncovered.** Channel
## number is paint order, so a low channel is mostly buried: the first version of
## this took the first candidate it found -- channel 5 of 21 -- pressed it, and
## reported that 330 bytes of the 170,109 under its rectangle had changed, all of
## them in the sliver still visible. Both pixel assertions then read the room
## behind it and neither said anything about hilite. A screen check has to look
## at pixels the sprite is the last thing to paint.
func _find(preview: Node, score) -> Dictionary:
	var table = preview.get("_table")
	for i in score.frame_count:
		preview.set("_index", i)
		var sprites: Array = score.frame(i).get("sprites", [])
		var live_sprites: Array[Dictionary] = []
		for raw in sprites:
			var s: Dictionary = preview.call("_effective", raw)
			if not s.is_empty():
				live_sprites.append(s)
		for at in range(live_sprites.size() - 1, -1, -1):
			var sprite: Dictionary = live_sprites[at]
			var m: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if int(m.get("type", 0)) != Ink.TYPE_BITMAP:
				continue
			if bool(sprite.get("moveable", false)):
				continue
			if not Hilite.is_active(preview, sprite):
				continue
			var rect: Rect2 = preview.call("_sprite_rect", sprite)
			if rect.size.x < 16.0 or rect.size.y < 16.0:
				continue
			var points := _sample_points(preview, sprite, rect, live_sprites)
			if not points.has("on") or not points.has("off"):
				continue
			# The *cached* member, not `get_member`'s copy. `get_member` duplicates
			# before stamping the library on it, so a flag set on what it returns
			# is set on a dictionary nothing else will ever read -- which is a
			# case that reports the corpus's answer while looking like it tested
			# the mechanism.
			var live: Dictionary = table.cast_for(
				int(sprite["cast_lib"])).member(int(sprite["cast_id"]))
			return {"frame": i, "channel": int(sprite["channel"]),
				"sprite": sprite, "member": live, "rect": rect, "points": points}
	return {}


## How far a sample point has to be from anything unlike it, in stage pixels.
##
## **Not a tolerance, a margin.** A windowed run scales the stage to the window
## and the pointer comes back off the OS at the scale's resolution: asking for
## stage (317,153) and reading 316.16,152.64 is normal and correct. The first
## opaque pixel in scan order is on the artwork's edge by construction, so a
## sample taken there lands one pixel outside it after the round trip and the
## case reports "pressing it changed nothing" while everything works. That is
## what the first windowed run of this file said.
const SAMPLE_MARGIN := 3
## Director's cast type for a button (`director_cast.gd:TYPE_NAMES`). Named here
## because nothing in the engine has a constant for it: no member in any of the
## three corpora is one, so no decode path ever compares against it.
const BUTTON_TYPE := 7


## A stage point the sprite certainly has a pixel at, and one inside its rect it
## certainly does not, each with `SAMPLE_MARGIN` pixels of the same kind around
## it and neither of them painted over by a higher channel. The second is what
## tells a silhouette from a box, and it is absent when the member fills its
## whole rectangle -- an honest "cannot ask here" rather than a case that quietly
## passes.
func _sample_points(preview: Node, sprite: Dictionary, rect: Rect2,
		live_sprites: Array[Dictionary]) -> Dictionary:
	var out := {}
	for y in range(SAMPLE_MARGIN, int(rect.size.y) - SAMPLE_MARGIN):
		for x in range(SAMPLE_MARGIN, int(rect.size.x) - SAMPLE_MARGIN):
			var at := rect.position + Vector2(x, y)
			var opaque: bool = preview.call("_opaque_at", sprite, at)
			var want := "on" if opaque else "off"
			if out.has(want):
				continue
			if not _surrounded_by(preview, sprite, at, opaque):
				continue
			if not _on_stage(at):
				continue
			if _covered(preview, sprite, at, live_sprites):
				continue
			out[want] = at
			if out.has("on") and out.has("off"):
				return out
	return out


## Is the whole margin around this point inside the stage rectangle?
##
## The stage is clipped to itself (`preview/stage_paint.gd:clip_to_stage`), so a
## sprite hanging over the edge is drawn only as far as the letterbox -- and the
## sample point this file found on the first windowed run was in the part that is
## never painted. A pixel outside the stage reads back transparent and says
## nothing about hilite.
func _on_stage(at: Vector2) -> bool:
	return Rect2(Vector2.ZERO, Vector2(STAGE)).grow(-SAMPLE_MARGIN - 1).has_point(at)


func _surrounded_by(preview: Node, sprite: Dictionary, at: Vector2,
		opaque: bool) -> bool:
	for dy in range(-SAMPLE_MARGIN, SAMPLE_MARGIN + 1):
		for dx in range(-SAMPLE_MARGIN, SAMPLE_MARGIN + 1):
			if bool(preview.call("_opaque_at", sprite, at + Vector2(dx, dy))) != opaque:
				return false
	return true


## Does anything painted after `sprite` put a pixel on this point, anywhere in
## the margin around it?
##
## `_opaque_at` is the right question for every sprite and not only for matte
## ones: it samples the *keyed* image, which is exactly the set of pixels the
## sprite paints, whatever ink produced it.
func _covered(preview: Node, sprite: Dictionary, at: Vector2,
		live_sprites: Array[Dictionary]) -> bool:
	var channel := int(sprite["channel"])
	for other in live_sprites:
		if int(other["channel"]) <= channel:
			continue
		if not preview.call("_sprite_rect", other).grow(SAMPLE_MARGIN).has_point(at):
			continue
		for dy in range(-SAMPLE_MARGIN, SAMPLE_MARGIN + 1):
			for dx in range(-SAMPLE_MARGIN, SAMPLE_MARGIN + 1):
				if bool(preview.call("_opaque_at", other, at + Vector2(dx, dy))):
					return true
	return false


## Put the pointer at a stage point, by whichever route this platform actually
## reads it on.
##
## Not a convenience. `stage_mouse` answers from the cached event position where
## the platform has no cursor -- headless and a phone -- or where the last mouse
## event was one Godot synthesised from a finger, and from the **real OS cursor**
## otherwise, which is deliberate (`director_preview.gd`) and
## is the whole reason `tools/touch_input.gd` exists. A harness that only ever
## called `note_pointer` would drive the headless run correctly and, windowed,
## silently measure wherever the developer left their mouse: the first version of
## this file did exactly that, and every headless check passed while the pixel
## case reported that pressing the sprite changed nothing. `tools/sprite_drag.gd`
## warps for the same reason and this follows it.
func _point_at(preview: Node, at: Vector2) -> void:
	preview.call("note_pointer", at)
	if bool(preview.get("_pointer_from_events")):
		return
	Input.warp_mouse(_to_screen(preview) * at)
	await process_frame
	await process_frame


## Stage coordinates to framebuffer pixels.
##
## **Both halves, and the screen transform is the half that is easy to leave
## out.** `get_global_transform_with_canvas()` maps into the viewport's *base*
## coordinate space, and this project stretches its canvas -- so with a 1280x960
## base drawn into a 960x720 window it is out by a factor of 0.75, which is
## enough to put every sample outside the image. `get_screen_transform()` carries
## exactly that factor. `tools/sprite_drag.gd` composes the same pair to warp the
## pointer, and for the same reason.
func _to_screen(preview: Node) -> Transform2D:
	return preview.get_viewport().get_screen_transform() 		* preview.get_global_transform_with_canvas()


func _region(rect: Rect2i) -> PackedByteArray:
	var image := root.get_texture().get_image()
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return PackedByteArray()
	return image.get_region(clipped).get_data()


func _pixel(at: Vector2i) -> Color:
	var image := root.get_texture().get_image()
	if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
		return Color(0, 0, 0, 0)
	return image.get_pixel(at.x, at.y)


func _init() -> void:
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	# Paused throughout. A running movie would advance the score out from under
	# the measurement, and hilite is a state that lasts exactly as long as a
	# button is held.
	preview.set("_paused", true)

	var score = preview.get("_score")
	if score == null:
		print("no score loaded")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))

	var found := _find(preview, score)
	if found.is_empty():
		print("%s: no active bitmap sprite to drive; try another movie" % movie)
		quit(1)
		return
	var frame_index := int(found["frame"])
	var channel := int(found["channel"])
	var sprite: Dictionary = found["sprite"]
	var member: Dictionary = found["member"]
	var rect: Rect2 = found["rect"]
	var points: Dictionary = found["points"]
	preview.set("_index", frame_index)
	# Decode it, which is also what fills `_hit_images` for everything below.
	preview.call("_texture_for", sprite)

	var inside: Vector2 = points["on"]

	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		# Exactly 1.5x the stage in both axes, so the whole of it is on screen and
		# nothing sampled is outside the letterbox. `_fit_to_window` reads
		# `get_viewport_rect()`, which follows the window a frame or two later --
		# calling it on the next frame fitted to the *previous* size, which put a
		# third of the stage outside the viewport and made every pixel read there
		# come back fully transparent.
		# **The window is left at whatever size the project opens it at, and every
		# screen coordinate below goes through `_to_screen`.** Resizing it looks
		# tidier and is a trap: the project stretches its canvas, so
		# `get_viewport_rect()` answers the *base* resolution whatever the window
		# is, `_fit_to_window` scales the stage to that, and the framebuffer is a
		# different size again. Two runs of this file chased the resulting
		# mismatch -- every sampled pixel landed off the right-hand edge and read
		# back fully transparent, which is indistinguishable from "the sprite did
		# not draw".
		root.get_window().mode = Window.MODE_WINDOWED
		for i in 4:
			await process_frame
		preview.call("_fit_to_window")
		for i in 2:
			await process_frame

	# ------------------------------------------- the corpus, as it really is
	h.begin("%s: nothing in this corpus hilites by itself" % movie)
	# The state the game ships in, asserted rather than assumed: if a member here
	# ever did carry the flag, the cases below would be measuring the corpus
	# instead of the mechanism and would need rewriting, not repairing.
	h.check("the member does not carry Auto Hilite",
		not bool(member.get("auto_hilite", false)),
		"%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])])
	h.check("so a press does not hilite it",
		not Hilite.should_hilite(preview, sprite),
		"ch%d, ink %d" % [channel, int(sprite["ink"])])
	h.complete("%s: nothing in this corpus hilites by itself" % movie)

	# ------------------------------------------------- the predicate, §4.6
	h.begin("%s: shouldHilite, clause by clause" % movie)
	# The authored bit, set on the parsed member. See the header.
	member["auto_hilite"] = true
	member["has_cast_info"] = true
	h.check("a bitmap whose member carries the flag hilites",
		Hilite.should_hilite(preview, sprite))

	# Moveable loses, even though `isActive` accepts it -- that pair of clauses is
	# the reference's, and it is why a draggable inventory icon does not flash.
	var draggable := sprite.duplicate()
	draggable["moveable"] = true
	h.check("a moveable sprite does not, flag or no flag",
		not Hilite.should_hilite(preview, draggable))

	# A puppeted channel belongs to the scripts.
	preview.call("lingo_puppet_sprite", channel, true)
	h.check("a puppeted channel does not",
		not Hilite.should_hilite(preview, sprite))
	preview.call("lingo_puppet_sprite", channel, false)
	h.check("and hilites again once the puppet is dropped",
		Hilite.should_hilite(preview, sprite))

	# The D3 fallback: no cast info at all, so Matte ink stands in for the flag.
	member["has_cast_info"] = false
	member["auto_hilite"] = false
	var matte := sprite.duplicate()
	matte["ink"] = Ink.MATTE
	var copy_ink := sprite.duplicate()
	copy_ink["ink"] = Ink.COPY
	h.check("with no cast info, Matte ink hilites", Hilite.should_hilite(preview, matte))
	h.check("with no cast info, Copy ink does not",
		not Hilite.should_hilite(preview, copy_ink))
	member["has_cast_info"] = true
	member["auto_hilite"] = true

	# A shape *member* never hilites, whatever its ink -- the reference tests the
	# member type before the ink. This corpus's doors are matte-inked shapes, so
	# without the clause every one of them would flash a rectangle.
	var as_shape := sprite.duplicate()
	as_shape["ink"] = Ink.MATTE
	var saved_type := int(member["type"])
	member["type"] = Ink.TYPE_SHAPE
	h.check("a matte-inked shape member does not hilite",
		not Hilite.should_hilite(preview, as_shape))
	member["type"] = saved_type
	h.complete("%s: shouldHilite, clause by clause" % movie)

	# --------------------------------------- the inversion is a silhouette
	h.begin("%s: the inversion is masked by the artwork" % movie)
	var key := Geometry.texture_key(sprite, Geometry.drawn_size(sprite, member))
	var source: Image = (preview.get("_hit_images") as Dictionary).get(key)
	if not h.check("the sprite's artwork decoded", source != null, key):
		h.complete("%s: the inversion is masked by the artwork" % movie)
		quit(h.finish("hilite on click"))
		return
	var flipped := Ink.invert(source)
	var same_alpha := true
	var inverted_pixels := 0
	var wrong := 0
	for y in source.get_height():
		for x in source.get_width():
			var before := source.get_pixel(x, y)
			var after := flipped.get_pixel(x, y)
			if before.a8 != after.a8:
				same_alpha = false
			if after.r8 != 255 - before.r8 or after.g8 != 255 - before.g8 \
					or after.b8 != 255 - before.b8:
				wrong += 1
			elif before.a8 > 0 and after.r8 != before.r8:
				inverted_pixels += 1
	# Alpha carried through is what makes drawing the inverted copy *in place of*
	# the artwork the same thing as a masked XOR. Invert the alpha too and the
	# sprite would flash as a filled rectangle.
	h.check("every alpha is carried through unchanged", same_alpha)
	h.check("every colour is 255 minus itself", wrong == 0, "%d wrong" % wrong)
	h.check("and something actually changed", inverted_pixels > 0,
		"%d pixel(s)" % inverted_pixels)
	h.complete("%s: the inversion is masked by the artwork" % movie)

	# ------------------------------------------------------- on and off, §4.6
	h.begin("%s: it is on while held and off otherwise" % movie)
	var plain: Texture2D = preview.call("_texture_for", sprite)
	h.check("before any press, the sprite draws its own artwork",
		Hilite.artwork(preview, plain, sprite) == plain)

	await _point_at(preview, inside)
	preview.call("route_press", inside)
	var held: Texture2D = Hilite.artwork(preview, plain, sprite)
	h.check("while the button is down it draws the inverted copy",
		held != null and held != plain,
		"asked at %s, stage_mouse %s" % [str(inside), str(preview.call("stage_mouse"))])

	# Off the sprite while still held, which is the reference's own rule:
	# `events.cpp` drops the hilite on a move that leaves the sprite and re-arms
	# it on one that comes back.
	var outside := rect.position + rect.size + Vector2(40, 40)
	await _point_at(preview, outside)
	h.check("dragging off it while held drops the inversion",
		Hilite.artwork(preview, plain, sprite) == plain, "at %s" % str(outside))
	await _point_at(preview, inside)
	h.check("coming back restores it",
		Hilite.artwork(preview, plain, sprite) == held)

	preview.call("route_release", inside)
	h.check("and the release ends it",
		Hilite.artwork(preview, plain, sprite) == plain)
	h.complete("%s: it is on while held and off otherwise" % movie)

	# ------------------------------- `set the hilite of member`, the other one
	#
	# **The flag is stored for every member type and drawn for one.** The
	# reference keeps `_hilite` on the cast member base class -- `CastMember::
	# setField(kTheHilite)` accepts it whatever the type and never refuses -- and
	# reads it back in exactly one place, `text.cpp:355` under `case kCastButton:`,
	# where it becomes `MacButton::setHilite`. `bitmap.cpp` and `shape.cpp` never
	# mention it. So the two halves have to be asserted separately, and asserting
	# only the drawing half would let a fix that gates the *write* through: `the
	# hilite of member` would then read back 0 after being set to 1, which is the
	# round-tripping lie `preview/sprite_props.gd` exists to prevent.
	#
	# Driven through `lingo_set_member_prop`/`lingo_member_prop` rather than by
	# poking `_member_hilite`, so what is measured is the path a script takes.
	#
	# **This fails against the code before the fix**, which had no type test at
	# all: Rating writes this flag at 39 sites across 21 containers, naming 26
	# shapes, 5 bitmaps and 3 film loops and not one button, and every one of them
	# drew in reverse video. Zehava in `thepool` was the visible one.
	# **The button half of it cannot be driven, and the check says so rather than
	# faking it.** An earlier edition stamped `type_name = "button"` on the cached
	# member and asserted that `artwork` then inverted. That passed, and it proved
	# nothing: `Hilite.is_button` reads `type_name` while
	# `preview/sprite_art.gd:texture_for` reads `type`, and the stamp moved only
	# the first, so what inverted was the **bitmap** path wearing a button label.
	# A member whose two fields disagree cannot exist -- `director_cast.gd:204`
	# derives `type_name` from `type` -- so the lever tested a state the engine
	# cannot reach, and it would have stayed green with the button arm broken or
	# deleted. Stamp `type` instead and the truth comes out: the arm is
	# unreachable, which is what the two checks below assert.
	h.begin("%s: the script-set flag draws on nothing, and the button arm is unreachable" % movie)
	var lib_arg := str(int(sprite["cast_lib"]))
	var id_arg := int(sprite["cast_id"])
	preview.call("lingo_set_member_prop", id_arg, lib_arg, "hilite", 1)
	h.check("the write round-trips, whatever the member type is",
		int(preview.call("lingo_member_prop", id_arg, lib_arg, "hilite")) == 1)
	h.check("but a bitmap member with the flag set draws its own artwork",
		Hilite.artwork(preview, plain, sprite) == plain,
		"%s:%d" % [lib_arg, id_arg])

	# The predicate on its own, which is the half that *is* testable: it answers
	# for the real member as decoded, and for the same member seen as a button
	# through the cached dictionary the table copies from -- the lever
	# `auto_hilite` above already uses, and the only one short of a button member
	# this corpus does not have.
	h.check("a bitmap member is not a button",
		not Hilite.is_button(preview, sprite))
	var was_type := int(member.get("type", 0))
	var was_type_name := str(member.get("type_name", ""))
	member["type"] = BUTTON_TYPE
	member["type_name"] = "button"
	h.check("a button member is",
		Hilite.is_button(preview, sprite))
	# And the reason that predicate cannot put anything on the screen today.
	# `texture_for` decodes bitmaps and shapes and returns null for every other
	# type, `stage_paint.gd` skips a sprite with no texture, and `artwork` returns
	# on its own first line -- so the arm `is_button` guards is unreachable, and
	# calling it "an approximation" would overstate it. This check is here to fail
	# the day a button member becomes drawable, because that is the day the arm
	# starts running and the day its `Ink.invert` has to be compared against
	# Director's `MacButton` widget rather than assumed to match it.
	h.check("and a button member is not drawable, so the arm cannot run",
		preview.call("_texture_for", sprite) == null)
	member["type"] = was_type
	member["type_name"] = was_type_name

	preview.call("lingo_set_member_prop", id_arg, lib_arg, "hilite", 0)
	h.check("clearing it puts the artwork back",
		Hilite.artwork(preview, plain, sprite) == plain)
	h.complete("%s: the script-set flag draws on nothing, and the button arm is unreachable" % movie)

	if not windowed:
		print("")
		print("NOTE: run without --headless for the pixel case -- headless Godot")
		print("      discards the draw list, so nothing above proves the")
		print("      inversion reaches the screen.")
		quit(h.finish("hilite on click"))
		return

	# ------------------------------------------------------------- the screen
	h.begin("%s: the inversion reaches the framebuffer" % movie)
	# Back to the frame the sprite is on. The presses above are real presses and
	# they dispatch real handlers: this movie's `mouseUp` on that sprite runs a
	# `go`, and it moved the playhead 71 frames on. Pausing stops the *clock*, not
	# the scripts, and a pixel case measured on whatever room the click navigated
	# to would be comparing two pictures of nothing.
	preview.set("_index", frame_index)
	preview.call("queue_redraw")
	await process_frame
	var to_screen := _to_screen(preview)
	var screen_rect := Rect2i(
		Vector2i((to_screen * rect.position).floor()),
		Vector2i(to_screen.basis_xform(rect.size).ceil()))
	await _point_at(preview, inside)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	var before_press := _region(screen_rect)
	var off_pixel: Vector2i = Vector2i((to_screen * points["off"]).floor()) \
		if points.has("off") else Vector2i(-1, -1)
	var off_before := _pixel(off_pixel)
	var on_before := _pixel(Vector2i((to_screen * inside).floor()))

	preview.call("route_press", inside)
	preview.set("_index", frame_index)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	var after_press := _region(screen_rect)

	h.check("the sprite's rectangle is on screen", not before_press.is_empty(),
		"rect %s, viewport %s" % [
			str(screen_rect), str(root.get_texture().get_image().get_size())])
	var changed := 0
	for i in mini(before_press.size(), after_press.size()):
		if before_press[i] != after_press[i]:
			changed += 1
	h.check("pressing it changes the pixels under it", changed > 0,
		"%d byte(s) of %d" % [changed, before_press.size()])
	# The whole point of the matte. A pixel the sprite does not paint must be
	# untouched, or this is a rectangle flashing rather than a silhouette
	# inverting -- and that is the failure that looks obviously wrong on
	# irregular buttons.
	if points.has("off"):
		h.check("a point inside the rect but outside the artwork is untouched",
			_pixel(off_pixel).is_equal_approx(off_before),
			"%s: %s -> %s" % [str(off_pixel), str(off_before), str(_pixel(off_pixel))])
	else:
		h.check("a point inside the rect but outside the artwork is untouched",
			false, "this member fills its whole rect -- pick another movie")
	var on_pixel := Vector2i((to_screen * inside).floor())
	var on_after := _pixel(on_pixel)
	# Nearer the inverse than to what it was, rather than equal to the inverse.
	# The project stretches its canvas, so what reaches the framebuffer has been
	# resampled and a high-contrast edge two stage-pixels away bleeds in: the
	# measured pixel came back (0.36, 0.18, 0.73) where the exact inverse is
	# (0.47, 0.00, 0.76). Asking for equality would be asking the filter not to
	# filter; asking which of the two colours it is nearer to is the question the
	# case actually cares about, and it answered 0.21 against 0.97.
	var want_inverse := Color(1.0 - on_before.r, 1.0 - on_before.g, 1.0 - on_before.b)
	var to_inverse := Vector3(on_after.r, on_after.g, on_after.b).distance_to(
		Vector3(want_inverse.r, want_inverse.g, want_inverse.b))
	var to_original := Vector3(on_after.r, on_after.g, on_after.b).distance_to(
		Vector3(on_before.r, on_before.g, on_before.b))
	h.check("a point on the artwork is inverted", to_inverse < to_original,
		"%s: %s -> %s, wanted %s (%.2f away, %.2f from where it was)" % [
			str(on_pixel), str(on_before), str(on_after), str(want_inverse),
			to_inverse, to_original])

	preview.call("route_release", inside)
	preview.set("_index", frame_index)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	var after_release := _region(screen_rect)
	var restored := 0
	for i in mini(before_press.size(), after_release.size()):
		if before_press[i] != after_release[i]:
			restored += 1
	h.check("and the release puts every pixel back", restored == 0,
		"%d byte(s) still different" % restored)
	h.complete("%s: the inversion reaches the framebuffer" % movie)

	quit(h.finish("hilite on click"))
