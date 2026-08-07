extends SceneTree
## Sprite trails: does a trails sprite stop being erased between frames?
##
##   godot --headless --script tools/trails.gd -- --file PIP2DATA/DAY1.dir
##   godot           --script tools/trails.gd -- --file PIP2DATA/DAY1.dir
##
## `DIRECTOR_ENGINE.md` §13. A trails sprite's old position is never repainted,
## so the stage keeps what it painted; the port has no dirty rects (§16.25), so
## it keeps an accumulation layer instead —
## `scenes/director_preview.gd:_trail_stamp`, where the resulting divergence is
## written down.
##
## **This corpus sets the trails bit 0 times in 816,318 sprite records**
## (`tools/ink_survey.gd`), so there is no authored trails sprite to test with.
## That is a reason to build the lever, not to skip the feature: `the trails of
## sprite N` is a real Director property, it is the other way a movie asks for
## this, and it is what the cases below use. A movie would reach the same code by
## the same route.
##
## Two levels of evidence, as in `tools/stage_clip.gd`:
##
##   headless   the accumulation layer is a CPU-side `Image` this port owns, so
##              what it holds can be read back with no renderer at all. This is
##              where "the mark is at the OLD position after the sprite moves"
##              is asserted, which is the whole feature.
##   windowed   run without `--headless` and the last case reads the framebuffer
##              to confirm the layer actually reaches the screen, and that the
##              stage clear does not wipe it.
##
## The control case matters as much as the others: a sprite *without* trails must
## leave nothing behind, or "trails work" would be satisfied by a renderer that
## had simply stopped clearing.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

const STAGE := Vector2i(640, 480)


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
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

	# A frame with a bitmap sprite big enough to find again once it has moved.
	var found := _find_sprite(preview, score)
	if found.is_empty():
		print("%s: no bitmap sprite to drive; try another movie" % movie)
		quit(1)
		return
	var frame_index := int(found["frame"])
	var channel := int(found["channel"])
	preview.set("_index", frame_index)

	# The window is sized now rather than at the end, because the pixel case
	# compares the finished stage against a shot of it taken *before* anything
	# had trails, and the two have to be the same size to be comparable.
	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		var window := root.get_window()
		window.mode = Window.MODE_WINDOWED
		window.size = Vector2i(1100, 500)
		await process_frame
		preview.call("_fit_to_window")

	# ------------------------------------------------ the control: no trails
	h.begin("%s: a sprite without trails leaves nothing" % movie)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	var pristine: Image = root.get_texture().get_image() if windowed else null
	h.check(
		"nothing accumulated before anything asked for trails",
		preview.get("_trail_image") == null,
		"the layer is not even allocated until a trails sprite is drawn"
	)
	h.complete("%s: a sprite without trails leaves nothing" % movie)

	# ------------------------------------------------- the feature, headless
	h.begin("%s: a trails sprite is not erased when it moves" % movie)
	# Through the Lingo property, because that is the route a movie has. Setting
	# the renderer's own flag directly would test the renderer against itself.
	preview.call("lingo_set_sprite_prop", channel, "trails", 1)
	h.check(
		"the property reads back as set",
		int(preview.call("lingo_sprite_prop", channel, "trails")) == 1
	)
	preview.call("queue_redraw")
	await process_frame
	await process_frame

	var layer: Image = preview.get("_trail_image")
	if not h.check("the trail layer now exists", layer != null):
		h.complete("%s: a trails sprite is not erased when it moves" % movie)
		quit(h.finish("sprite trails"))
		return
	h.check("it is the size of the stage",
		layer.get_size() == STAGE, str(layer.get_size()))

	var first_rect: Rect2 = preview.call("_stage_rect", found["sprite"])
	var painted_first := _opaque_in(layer, first_rect)
	h.check("the sprite's first position is in the layer",
		painted_first > 0, "%d opaque pixel(s) in %s" % [painted_first, str(first_rect)])

	# Move it far enough that the two positions cannot overlap, which is what
	# makes "the old one is still there" mean anything.
	var moved_by := int(first_rect.size.x) + 20
	var start_h := int(preview.call("lingo_sprite_prop", channel, "loch"))
	preview.call("lingo_set_sprite_prop", channel, "loch", start_h + moved_by)
	preview.call("queue_redraw")
	await process_frame
	await process_frame

	layer = preview.get("_trail_image")
	var second_rect := Rect2(first_rect.position + Vector2(moved_by, 0), first_rect.size)
	var still_first := _opaque_in(layer, first_rect)
	var painted_second := _opaque_in(layer, second_rect)
	# The whole of §13 in one check: Director never repaints the rectangle a
	# trails sprite vacated, so what it painted there is still on the stage.
	h.check("what it painted at the old position is still there",
		still_first > 0, "%d opaque pixel(s)" % still_first)
	h.check("and the new position has been added too",
		painted_second > 0, "%d opaque pixel(s)" % painted_second)

	# Move once more, still with trails on, so the sprite is nowhere near the
	# second position. Anything painted there afterwards is the layer and nothing
	# else, which is what the pixel case rests on.
	preview.call("lingo_set_sprite_prop", channel, "loch", start_h + moved_by * 2)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	h.check("moving on again leaves the second mark behind as well",
		_opaque_in(preview.get("_trail_image"), second_rect) > 0)
	h.complete("%s: a trails sprite is not erased when it moves" % movie)

	# Ordered before the "trails off" case on purpose: switching the flag off
	# makes the sprite dirty its old rectangle again, which correctly wipes the
	# mark at the second position, and the pixel case needs it still there.
	await _pixel_case(h, preview, movie, second_rect, pristine)

	# ------------------------------------------- switching the flag back off
	h.begin("%s: with trails off, the sprite goes back to erasing itself" % movie)
	preview.call("lingo_set_sprite_prop", channel, "trails", 0)
	preview.call("lingo_set_sprite_prop", channel, "loch", start_h + moved_by * 3)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	var fourth_rect := Rect2(first_rect.position + Vector2(moved_by * 3, 0), first_rect.size)
	h.check("the new position leaves no mark",
		_opaque_in(preview.get("_trail_image"), fourth_rect) == 0)
	# Director repaints the rectangle a *non*-trails sprite vacates, so the mark
	# it had left there goes with it. The marks further back are untouched,
	# because nothing repainted them.
	h.check("and the rectangle it just vacated is repainted, taking that mark",
		_opaque_in(preview.get("_trail_image"),
			Rect2(first_rect.position + Vector2(moved_by * 2, 0), first_rect.size)) == 0)
	h.check("while marks nothing has repainted stay",
		_opaque_in(preview.get("_trail_image"), first_rect) > 0)
	h.complete("%s: with trails off, the sprite goes back to erasing itself" % movie)

	quit(h.finish("sprite trails, and the stage clear that must not wipe them"))


## Opaque pixels of the accumulation layer inside a stage rectangle.
static func _opaque_in(layer: Image, rect: Rect2) -> int:
	if layer == null:
		return 0
	var area := Rect2(Vector2.ZERO, Vector2(STAGE)).intersection(rect)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return 0
	var count := 0
	for y in range(int(area.position.y), int(area.end.y)):
		for x in range(int(area.position.x), int(area.end.x)):
			if layer.get_pixel(x, y).a > 0.5:
				count += 1
	return count


## The first frame carrying a bitmap sprite the preview actually draws, with a
## rect big enough to still be findable once it has been moved sideways.
func _find_sprite(preview: Node, score) -> Dictionary:
	var table = preview.get("_table")
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var m: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"])
			)
			if m.is_empty() or int(m.get("type", 0)) != 1:
				continue
			var rect: Rect2 = preview.call("_stage_rect", sprite)
			# Comfortably on the stage, so moving it sideways keeps both
			# positions visible and the check is not measuring the stage clip.
			if rect.size.x < 16.0 or rect.size.y < 16.0 or rect.size.x > 200.0:
				continue
			if rect.position.x < 0.0 or rect.end.x + rect.size.x + 20.0 > 640.0:
				continue
			if rect.position.y < 0.0 or rect.end.y > 480.0:
				continue
			if preview.call("_texture_for", sprite) == null:
				continue
			return {"frame": i, "channel": int(sprite["channel"]), "sprite": sprite}
	return {}


## That the layer reaches the screen, and survives the stage clear that runs at
## the top of every paint. Needs a renderer; declared only when there is one,
## because a case begun and skipped is a failure and rightly so.
##
## **Against the pristine shot, not against black.** The first version of this
## asked whether the vacated rectangle was painted at all, which every movie with
## a backdrop answers yes to whether or not trails work — it passed with the
## layer's `draw_texture` commented out. What makes the question meaningful is
## the *difference*: `rect` is a position the sprite was never at when `pristine`
## was taken, so anything that changed there came from the trail.
func _pixel_case(
	h: RefCounted, preview: Node, movie: String, rect: Rect2, pristine: Image
) -> void:
	if pristine == null:
		print("")
		print("pixel case not run: no renderer. Re-run without --headless to")
		print("confirm the accumulated marks survive the stage clear on screen.")
		return

	preview.call("queue_redraw")
	await process_frame
	await process_frame
	await process_frame
	var shot := root.get_texture().get_image()
	if shot.get_size() != pristine.get_size():
		print("")
		print("pixel case not run: the window was resized under it")
		return

	# The readback is in framebuffer pixels and the node's transform in canvas
	# units; on a scaled display those differ, so the rect is converted rather
	# than used raw.
	var canvas: Vector2 = root.get_viewport().get_visible_rect().size
	var factor := Vector2(shot.get_width() / canvas.x, shot.get_height() / canvas.y)
	var transform: Transform2D = preview.get_global_transform_with_canvas()
	var on_screen: Rect2 = transform * rect
	var sample := Rect2(on_screen.position * factor, on_screen.size * factor)

	h.begin("%s: the trail reaches the framebuffer" % movie)
	print("")
	print("  sampling %s of %s" % [str(sample), str(shot.get_size())])
	var changed := _differing(pristine, shot, sample)
	h.check(
		"a position the sprite only passed through is painted differently now",
		changed > 0,
		"%d pixel(s) differ from the same stage before anything had trails" % changed
	)
	# The control for that control. The movie is paused and only this one sprite
	# was ever moved, so a band of stage it never crossed must be pixel-identical
	# — otherwise "the region changed" is measuring something else entirely and
	# the check above proves nothing.
	var untouched := Rect2(0.0, rect.position.y, maxf(rect.position.x - 120.0, 0.0), rect.size.y)
	if untouched.size.x >= 8.0:
		var control_area := Rect2(
			transform * untouched.position * factor,
			(transform * untouched).size * factor
		)
		h.check(
			"while stage the sprite never crossed is untouched",
			_differing(pristine, shot, control_area) == 0,
			"%d pixel(s) differ where nothing moved"
			% _differing(pristine, shot, control_area)
		)
	h.complete("%s: the trail reaches the framebuffer" % movie)


## Pixels of `area` that differ between two shots. Sampled on a grid: this asks
## whether the region changed at all, and reading every pixel of a large
## framebuffer to answer that costs seconds.
static func _differing(before: Image, after: Image, area: Rect2) -> int:
	var count := 0
	var y := maxi(int(area.position.y), 0)
	while y < mini(int(area.end.y), after.get_height()):
		var x := maxi(int(area.position.x), 0)
		while x < mini(int(area.end.x), after.get_width()):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			# A tolerance, because the framebuffer may be through a colour
			# conversion and a unit of drift is not a trail.
			if absi(a.r8 - b.r8) + absi(a.g8 - b.g8) + absi(a.b8 - b.b8) > 12:
				count += 1
			x += 2
		y += 2
	return count
