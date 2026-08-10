extends SceneTree
## Sprite flip: does a flipped sprite draw mirrored, in the same rectangle?
##
##   godot --headless --script tools/sprite_flip.gd -- --file PIPDATA/OPENING.dir
##   godot           --script tools/sprite_flip.gd -- --file PIPDATA/OPENING.dir
##
## `DIRECTOR_ENGINE.md` §1.8. Horizontal and vertical flip are bits 0x20 and 0x40
## of the sprite record's thickness byte. Director has them; the reference parses
## them, copies them between sprites and compares them in its dirty test, and
## never applies them anywhere in its render path, so it cannot say how flip
## meets registration or hit testing. §1.8's reading — mirror the image inside
## the sprite's rect and leave the rect alone — is what this asserts.
##
## **Nothing in either corpus sets either bit**: 0 of Piposh 2's 816,318 records
## and 0 of Piposh 1's 1,886,362, read from the byte that actually holds them.
## So there is no authored flipped sprite to test with, and unlike trails there
## is no Lingo property to reach it through either — flip is a Score checkbox.
## This harness therefore sets the bit on a decoded record itself, which is
## exactly the record a Director file with the box ticked would have produced,
## and drives the ordinary render path with it. That is the honest shape for a
## feature built from the reference rather than from the data, and it is why the
## non-flipped control case is here: without it, "the sprite is mirrored" would
## also be satisfied by a renderer that had drawn something symmetrical.
##
## Two levels of evidence, as in `tools/trails.gd`:
##
##   headless   the per-pixel hit test reads a CPU-side image this port owns, so
##              "the clickable pixels moved with the artwork" can be asserted
##              with no renderer at all.
##   windowed   run without `--headless` and the pixel case reads the
##              framebuffer and requires the flipped stage to be the mirror of
##              the unflipped one. Headless Godot never paints, so that case
##              cannot run there and is skipped rather than faked.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## The stage this movie declares, read off the preview in `_init`. The 640x480 is
## only what stands before that read: the stage is the movie's own rect
## (`director_preview.gd:stage_size`), and sizing the OS window to a constant
## against a movie of another size stops the fit being 1:1 -- which is the one
## thing the windowed half of this file needs.
var _stage := Vector2i(640, 480)


func _init() -> void:
	var h := Harness.new()
	var _args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	# Paused throughout: this asserts the renderer, and a running movie would
	# move the sprite out from under the measurement.
	preview.set("_paused", true)

	var score = preview.get("_score")
	if score == null:
		print("no score loaded")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))
	_stage = preview.call("stage_size")

	var found := _find_asymmetric(preview, score)
	if found.is_empty():
		print("%s: no asymmetric bitmap sprite to drive; try another movie" % movie)
		quit(1)
		return
	var frame_index := int(found["frame"])
	preview.set("_index", frame_index)
	# The record itself, reached through the score's frame cache so that the bit
	# is set on the very dictionary the renderer and the hit test both read.
	var record: Dictionary = found["sprite"]

	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		var window := root.get_window()
		window.mode = Window.MODE_WINDOWED
		# Exactly the stage, so the fit is 1:1 and a mirror comparison is not
		# also a comparison of two different resamplings.
		window.size = _stage
		await process_frame
		preview.call("_fit_to_window")
	preview.call("queue_redraw")
	await process_frame
	await process_frame

	var rect: Rect2 = preview.call("_stage_rect", record)
	# Stage coordinates are the preview node's own; the framebuffer is the
	# viewport's. The node is scaled and offset to fit the window, so a pixel read
	# has to go through that transform -- sampling the framebuffer at stage
	# coordinates reads somewhere else entirely, which is how the first version of
	# this case found its comparison pixels and still compared the wrong ones.
	# ...and the framebuffer is not even in the viewport's units: the window
	# carries a content scale, so a 640x480 window renders a 1280x960 logical
	# viewport into a 640x480 image. Both steps are folded in here, measured off
	# the shot rather than assumed, because assuming either one reads the wrong
	# pixel and still finds *some* pixels to compare.
	var to_screen: Transform2D = preview.get_global_transform()
	if windowed:
		var shot_size := Vector2(root.get_texture().get_image().get_size())
		var logical := root.get_visible_rect().size
		to_screen = Transform2D().scaled(
			Vector2(shot_size.x / logical.x, shot_size.y / logical.y)) * to_screen
	# Sampled before the flag is touched, and only where the artwork is opaque on
	# *both* sides of the mirror line. A stage pixel outside the sprite belongs to
	# whatever is behind it, and nothing mirrors the backdrop -- comparing those
	# compares two unrelated things and fails for a reason that has nothing to do
	# with flip. This was the first version's mistake.
	var pairs: Array[Vector2] = _mirror_pairs(preview, record, rect, to_screen)
	var before: Image = root.get_texture().get_image() if windowed else null

	# ------------------------------------------------------- the hit test
	h.begin("%s: flipping moves the clickable pixels with the artwork" % movie)
	var probe: Vector2 = found["opaque_at"]
	var mirror_probe := Vector2(
		rect.position.x + rect.size.x - 1.0 - (probe.x - rect.position.x), probe.y)
	h.check("the sample point is opaque unflipped",
		bool(preview.call("_opaque_at", record, probe)), str(probe))
	h.check("and its mirror is not",
		not bool(preview.call("_opaque_at", record, mirror_probe)), str(mirror_probe))
	record["flip_h"] = true
	h.check("with the flip set, the mirror point is the opaque one",
		bool(preview.call("_opaque_at", record, mirror_probe)))
	h.check("and the original point is not",
		not bool(preview.call("_opaque_at", record, probe)))
	# The rect does not move. Flip lives in a rendering attribute byte, so the
	# geometry -- and therefore where the sprite can be clicked at all -- is
	# untouched (§1.8).
	var flipped_rect: Rect2 = preview.call("_stage_rect", record)
	h.check("the sprite's rectangle is unchanged", flipped_rect == rect,
		"%s vs %s" % [str(flipped_rect), str(rect)])
	h.complete("%s: flipping moves the clickable pixels with the artwork" % movie)

	# --------------------------------------------------------- the pixels
	if not windowed:
		print("")
		print("headless: the framebuffer case cannot run, run without --headless")
		quit(h.finish("sprite flip"))
		return

	h.begin("%s: the flipped sprite paints as the mirror of the unflipped one" % movie)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	var after: Image = root.get_texture().get_image()
	if not h.check("there are mirror-pair pixels to compare",
			pairs.size() >= 8, "%d pair(s)" % pairs.size()):
		h.complete("%s: the flipped sprite paints as the mirror of the unflipped one" % movie)
		quit(h.finish("sprite flip"))
		return

	var moved := 0
	var matched := 0
	for at in pairs:
		var mirror := Vector2(
			rect.position.x + rect.size.x - 1.0 - (at.x - rect.position.x), at.y)
		var was := _sample(before, to_screen, at)
		var now := _sample(after, to_screen, at)
		if was != now:
			moved += 1
		if now == _sample(before, to_screen, mirror):
			matched += 1
	# The control. Every pair sampled had a different colour at its mirror, so if
	# nothing changed the sprite was not flipped and the check below would be
	# satisfied by a renderer that had done nothing at all.
	h.check("flipping changed the stage where the artwork is",
		moved == pairs.size(), "%d of %d pixel(s) changed" % [moved, pairs.size()])
	h.check("and every changed pixel now holds what its mirror held",
		matched == pairs.size(), "%d of %d match" % [matched, pairs.size()])
	h.complete("%s: the flipped sprite paints as the mirror of the unflipped one" % movie)

	quit(h.finish("sprite flip"))


## Stage points inside the sprite where the artwork is opaque at the point *and*
## at its horizontal mirror, and where the two currently hold different colours.
## Both conditions are what makes the comparison mean anything: opaque on both
## sides keeps the backdrop out of it, and different colours mean a renderer that
## ignored the flip would be caught.
func _mirror_pairs(preview: Node, sprite: Dictionary, rect: Rect2,
		to_screen: Transform2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var shot: Image = root.get_texture().get_image()
	for step_y in range(2, int(rect.size.y) - 2, 3):
		for step_x in range(2, int(rect.size.x) - 2, 3):
			var at := rect.position + Vector2(step_x, step_y)
			var mirror := Vector2(rect.position.x + rect.size.x - 1.0 - step_x, at.y)
			if not bool(preview.call("_opaque_at", sprite, at)):
				continue
			if not bool(preview.call("_opaque_at", sprite, mirror)):
				continue
			if _sample(shot, to_screen, at) == _sample(shot, to_screen, mirror):
				continue
			out.append(at)
	return out


## The framebuffer pixel a stage pixel landed on. Sampled at the stage pixel's
## *centre*, because the fit is an integer magnification and the corner of a
## stage pixel is the corner of a block of screen pixels -- mirroring reverses
## the order inside that block, so a corner sample compares a left edge against a
## right one and disagrees for a reason that is not the flip.
static func _sample(shot: Image, to_screen: Transform2D, stage_at: Vector2) -> Color:
	var at := to_screen * (stage_at + Vector2(0.5, 0.5))
	var x := clampi(int(at.x), 0, shot.get_width() - 1)
	var y := clampi(int(at.y), 0, shot.get_height() - 1)
	return shot.get_pixel(x, y)


## The first frame carrying a bitmap sprite whose artwork is horizontally
## asymmetric, with the stage point of an opaque pixel whose mirror is
## transparent. Both halves matter: a symmetric sprite makes every assertion in
## this file true for the wrong reason.
func _find_asymmetric(preview: Node, score) -> Dictionary:
	var table = preview.get("_table")
	for i in mini(score.frame_count, 400):
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var m: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if int(m.get("type", 0)) != 1:
				continue
			var rect: Rect2 = preview.call("_stage_rect", sprite)
			if rect.size.x < 24.0 or rect.size.y < 24.0:
				continue
			if rect.position.x < 0.0 or rect.position.y < 0.0 \
					or rect.end.x > float(_stage.x) or rect.end.y > float(_stage.y):
				continue
			var probe := _asymmetric_point(preview, sprite, rect)
			if probe.x < 0.0:
				continue
			return {"frame": i, "sprite": sprite, "opaque_at": probe}
	return {}


## A stage point where the sprite is opaque and its horizontal mirror is not.
static func _asymmetric_point(preview: Node, sprite: Dictionary, rect: Rect2) -> Vector2:
	for step_y in range(4, int(rect.size.y) - 4, 5):
		for step_x in range(4, int(rect.size.x) - 4, 5):
			var at := rect.position + Vector2(step_x, step_y)
			var mirror := Vector2(rect.position.x + rect.size.x - 1.0 - step_x, at.y)
			if bool(preview.call("_opaque_at", sprite, at)) \
					and not bool(preview.call("_opaque_at", sprite, mirror)):
				return at
	return Vector2(-1, -1)
