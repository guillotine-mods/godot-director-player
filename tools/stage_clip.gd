extends SceneTree
## Does the preview keep its paint inside the stage, and is a full clear still
## the right way to start one?
##
##   godot --headless --script tools/stage_clip.gd -- --file PIP2DATA/DAY1.dir
##   godot --headless --script tools/stage_clip.gd -- --file PIP2DATA/EXODUS.DIR
##
## Two halves of the same question — what a repaint does with the stage rect.
##
## **Clipping.** Director clips every sprite to the stage. A sprite is placed by
## its registration point, so art hanging off the edge is normal rather than
## exceptional: over the corpus 131,337 of 816,318 drawing sprite records (16.1%)
## reach past 640x480 and 2,121 sit wholly outside it, across 60 of the 61
## movies. Unclipped, all of that was painted into the letterbox. The working
## renderer has clipped since `director/movie_player.gd:43-44`; the preview did
## not until `_clip_to_stage`.
##
## **Clearing.** `_draw` fills the whole stage with the stage colour before
## drawing anything. §13 says that is exactly what a trails sprite must *not*
## get: a trails channel is not erased between frames, and the repaint starts at
## that channel rather than at the stage colour. So the unconditional clear is
## not a general truth, it is a licence this corpus grants — 0 of 816,318 sprite
## records set the trails bit (`tools/ink_survey.gd`) — and the check below is
## what withdraws the licence if a movie ever does.
##
## **Two levels of evidence, and the difference matters.** Headless Godot builds
## the draw list and throws it away, so headless this can only check the geometry
## either side of the clip: that the node applied the stage rect, that the movie
## really does place art outside it (or the case would pass by being empty), and
## that the intersection is exact. Every one of those passed while the clip was
## doing nothing at all — the flag was being armed once in `_ready` and Godot
## resets it on every repaint — so the geometry checks alone are not enough to
## believe.
##
## Run **without `--headless`** and the last case reads the framebuffer back and
## settles it: the movie is fitted into a window wide enough to leave a letterbox
## bar, parked on the frame with the largest overhang past the left edge, and the
## bar is required to be black. Then the clip is switched off *after* the paint,
## with no redraw to re-arm it, and the same bar is required to light up. Without
## that second half the first is satisfied by a movie that never reached the bar.
##
## The Lingo host does not compile under `--script` (it reaches an autoload only a
## scene run has), so the movie here is the score alone — the right scope for a
## geometry check, and why the playhead is set directly rather than stepped.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Config := preload("res://director/director_config.gd")

## What size the movie says its stage is, decoded here from the container's own
## config chunk rather than read off the preview -- so the clip check below still
## compares two independent statements of the stage size instead of one with
## itself.
##
## This was `const STAGE := Rect2(0, 0, 640, 480)`, and the constant was the
## assumption rather than the independence: every movie of this corpus declares
## 640x480, so it agreed with the renderer for reasons that had nothing to do
## with the renderer being right, and it would have disagreed with a correct
## renderer on `test-games/itamar-magichat/magichat.dir` (800x600).
##
## Falls back to 640x480 for a container with no readable config, which is the
## same fallback `director_preview.gd:stage_size` takes and the reason the two
## can still be compared for such a movie.
static func _declared_stage(preview: Node) -> Rect2:
	var config = Config.new()
	if config.read(preview.get("_movie")):
		return Rect2(Vector2.ZERO, Vector2(config.rect.size))
	return Rect2(0, 0, 640, 480)


## Cast types that put pixels on the stage. A script or a sound member occupies a
## channel and paints nothing, so counting it as "inside the stage" would dilute
## the measurement with sprites that could never have spilled.
const DRAWING := ["bitmap", "filmLoop", "picture", "richText", "field", "shape"]


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	# Paused for the whole run: this asserts the renderer's geometry, and an
	# unpaused preview would step the movie underneath the measurement.
	preview.set("_paused", true)

	var score = preview.get("_score")
	var table = preview.get("_table")
	if score == null or table == null:
		print("no score loaded")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))
	var stage := _declared_stage(preview)

	# ------------------------------------------------- the clip the node applied
	h.begin("%s: the stage clips" % movie)
	var clip: Rect2 = preview.get("_clip_rect")
	h.check(
		"the preview clips to the stage rect",
		clip == stage,
		"clip %s, stage %s" % [str(clip), str(stage)]
	)

	# ------------------------------------------- what the clip has to cut, if any
	var drawing := 0
	var spilling := 0
	var wholly_off := 0
	var trails := 0
	var bad_intersection: Array[String] = []
	var worst := 0.0
	var worst_where := ""
	var cut_area := 0.0
	var total_area := 0.0
	# The frame the pixel case parks on: the one whose art reaches furthest past
	# the *left* edge while still showing on the stage, which is the frame most
	# likely to paint something into the left letterbox bar if nothing stops it.
	var left_worst := 0.0
	var left_frame := -1

	for i in score.frame_count:
		var frame: Dictionary = score.frame(i)
		for sprite_value in frame.get("sprites", []):
			var sprite: Dictionary = sprite_value
			if bool(sprite.get("trails", false)):
				trails += 1
			var m: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"])
			)
			if m.is_empty() or not DRAWING.has(str(m.get("type_name", ""))):
				continue
			# The renderer's own placement rule, called rather than reproduced: a
			# copy here would agree with itself while disagreeing with the paint.
			var rect: Rect2 = preview.call("_stage_rect", sprite)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			drawing += 1
			total_area += rect.size.x * rect.size.y
			if stage.encloses(rect):
				continue
			spilling += 1
			var visible := stage.intersection(rect)
			cut_area += rect.size.x * rect.size.y - visible.size.x * visible.size.y
			var over := maxf(
				maxf(-rect.position.x, -rect.position.y),
				maxf(rect.end.x - stage.end.x, rect.end.y - stage.end.y)
			)
			if over > worst:
				worst = over
				worst_where = "f%d ch%d member %d %s" % [
					i, int(sprite["channel"]), int(sprite["cast_id"]),
					str(m.get("name", ""))
				]
			if not stage.intersects(rect):
				wholly_off += 1
				# An empty intersection is the correct answer for art entirely
				# off-stage, and the only one that must not paint anything.
				if visible.size.x > 0.0 and visible.size.y > 0.0:
					bad_intersection.append("f%d ch%d %s -> %s" % [
						i, int(sprite["channel"]), str(rect), str(visible)
					])
				continue
			if not stage.encloses(visible):
				bad_intersection.append("f%d ch%d %s -> %s" % [
					i, int(sprite["channel"]), str(rect), str(visible)
				])
			if -rect.position.x > left_worst:
				left_worst = -rect.position.x
				left_frame = i

	print("")
	print("%s  %d frame(s)" % [movie, score.frame_count])
	print("  drawing sprite records : %d" % drawing)
	print("  reaching past the stage: %d (%.1f%%)" % [
		spilling, 100.0 * float(spilling) / maxf(drawing, 1)])
	print("  wholly off the stage   : %d" % wholly_off)
	print("  painted area cut away  : %.1f%%" % (100.0 * cut_area / maxf(total_area, 1.0)))
	if worst_where != "":
		print("  worst overhang         : %d px  %s" % [int(worst), worst_where])

	# Without this the two checks below are satisfied by a movie that never puts
	# anything near the edge, and a clip that had been deleted would still pass.
	h.check(
		"this movie has art to clip",
		spilling > 0,
		"%d of %d records reach past the stage" % [spilling, drawing]
	)
	h.check(
		"every clipped rect lands inside the stage",
		bad_intersection.is_empty(),
		"" if bad_intersection.is_empty()
		else "%d wrong: %s" % [bad_intersection.size(), "; ".join(bad_intersection.slice(0, 3))]
	)
	h.complete("%s: the stage clips" % movie)

	# ------------------------------------------- the clear and the trail layer
	# `_draw` clears the whole stage before every paint, and §13's trails sprites
	# are the pixels that must survive it. Both paths exist now, so this is no
	# longer "nothing asks for trails, so the clear is safe" — it is that the two
	# agree: a movie with no trails records must allocate no layer, and a movie
	# with them must end up with one. `tools/trails.gd` asserts what the layer
	# then holds; this only asserts that the score and the renderer are talking
	# about the same thing.
	h.begin("%s: the clear and the trail layer agree about this movie" % movie)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	var layer = preview.get("_trail_image")
	print("  sprite records asking for trails: %d" % trails)
	h.check(
		"the accumulation layer exists exactly when the score asks for one",
		(trails > 0) == (layer != null),
		"%d trails record(s), layer %s" % [trails, "allocated" if layer != null else "absent"]
	)
	h.complete("%s: the clear and the trail layer agree about this movie" % movie)

	await _pixel_case(h, preview, movie, stage, left_frame, left_worst)
	quit(h.finish("the preview paints inside the stage, and clears all of it"))


## The only check here that the rasteriser has to pass. Needs a real renderer, so
## it is declared only when one is present — a case begun and skipped would be
## reported as a failure by `harness.gd`, and rightly.
func _pixel_case(
	h: RefCounted, preview: Node, movie: String, stage: Rect2,
	frame_index: int, overhang: float
) -> void:
	if DisplayServer.get_name() == "headless":
		print("")
		print("pixel case not run: no renderer. Re-run without --headless to")
		print("read the letterbox back and prove the clip reaches the framebuffer.")
		return
	if frame_index < 0 or overhang < 1.0:
		print("")
		print("pixel case not run: %s never places art past the left edge" % movie)
		return

	# A window wider than 4:3 so the fit leaves a bar either side. The size is a
	# request, not a guarantee — a window manager may refuse it — so the bar is
	# measured after the fit rather than assumed from these numbers.
	var window := root.get_window()
	window.mode = Window.MODE_WINDOWED
	window.size = Vector2i(1100, 500)
	await process_frame
	preview.call("_fit_to_window")
	preview.set("_index", frame_index)
	preview.call("queue_redraw")
	await process_frame
	await process_frame
	await process_frame

	# The readback is in framebuffer pixels and the node's transform is in canvas
	# units; on a scaled display those differ, so the bar is converted rather than
	# used raw. Getting this wrong samples inside the stage and passes for the
	# wrong reason.
	var canvas: Vector2 = root.get_viewport().get_visible_rect().size
	var clipped := root.get_texture().get_image()
	var factor := Vector2(clipped.get_width() / canvas.x, clipped.get_height() / canvas.y)
	var stage_on_screen: Rect2 = preview.get_global_transform_with_canvas() * stage
	var bar_width := int(stage_on_screen.position.x * factor.x)
	if bar_width < 16:
		print("")
		print("pixel case not run: the fit left a %d px letterbox" % bar_width)
		return

	h.begin("%s: the clip reaches the framebuffer" % movie)
	print("")
	print("  frame %d, overhang %d px, letterbox %d x %d px" % [
		frame_index, int(overhang), bar_width, clipped.get_height()])
	var lit_clipped := _lit(clipped, bar_width)
	h.check(
		"nothing is painted into the letterbox",
		lit_clipped == 0,
		"%d lit pixel(s) left of the stage" % lit_clipped
	)

	# Switched off *after* the paint, so `_draw` does not re-arm it. Without this
	# the check above is satisfied by a frame that never reached the bar, and the
	# whole case would go on passing with the clip deleted.
	RenderingServer.canvas_item_set_clip(preview.get_canvas_item(), false)
	await process_frame
	await process_frame
	var unclipped := root.get_texture().get_image()
	var lit_unclipped := _lit(unclipped, bar_width)
	h.check(
		"and it is the clip that stops it, not the movie",
		lit_unclipped > 0,
		"unclipped the letterbox holds %d lit pixel(s)" % lit_unclipped
	)
	preview.call("queue_redraw")
	h.complete("%s: the clip reaches the framebuffer" % movie)


## Pixels in the letterbox bar left of the stage that are not the clear colour.
## Sampled on a grid: this is asking whether artwork is there at all, and reading
## every pixel of a 4K framebuffer to answer that costs seconds.
static func _lit(shot: Image, bar_width: int) -> int:
	var count := 0
	for y in range(2, shot.get_height() - 2, 3):
		for x in range(2, bar_width - 2, 3):
			var c := shot.get_pixel(x, y)
			# Not an exact black test: the framebuffer may be through a colour
			# conversion, and a single stray unit must not read as artwork.
			if c.r8 + c.g8 + c.b8 > 12:
				count += 1
	return count
