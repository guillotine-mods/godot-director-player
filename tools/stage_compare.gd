extends SceneTree
## Photograph the running player's stage **headlessly**, at one image pixel per
## stage pixel, and compare it against a picture composited some other way.
##
##   godot --headless --path . --audio-driver Dummy --script tools/director_render.gd -- \
##       --root piposh --file PIPDATA/PIANO.dir --frame 37 --out C:/tmp/rend.png
##   godot --headless --path . --audio-driver Dummy --script tools/stage_compare.gd -- \
##       --root piposh --boot PIPDATA/PIANO.dir --frame 37 \
##       --against C:/tmp/rend.png --band 8,466,252,9 --out C:/tmp/prev.png
##
##   --boot C       the container to boot (the player's own `--boot`/`--root`)
##   --movie C      `go to movie` after boot, when the frame wanted is elsewhere
##   --frame N      stand here (`--marker M` for a label instead)
##   --settle N     process frames after each step (default 8)
##   --band x,y,w,h one rectangle to report separately from the whole stage
##   --against PNG  a second picture, in stage pixels, to difference against
##   --skip-top N   ignore the first N rows of both (a HUD the diagnostic
##                  cannot dress, which is the usual reason a whole-stage
##                  number is not the interesting one)
##   --out PATH     write the player's own stage image
##
## ## Why this exists, and why it is not `scene_probe.gd`
##
## `scene_probe.gd` photographs the *window* and refuses to run headless, because
## it reads the framebuffer through `snapshot.gd:grab` and a dummy renderer paints
## nothing. That is the right tool for "what does a person see", and it is the
## wrong one for "do these two compositors agree", for a reason `bugs.md` 74 paid
## a session for: **a window capture is a measurement of the capture as much as of
## the renderer.** The stage is a `Node2D` inside a project that stretches with
## `canvas_items`, so what reaches the framebuffer is the node's own `float32`
## scale composed with the viewport's stretch transform
## (`scenes/preview/stage_paint.gd:framebuffer_region` carries the numbers), and
## the product of two float scales is not the integer the arithmetic promises.
## `bugs.md` 117 is the same two spaces confused one level up, and
## `transition_render.gd:_crop_follows_the_stretch` allows two pixels of width for
## exactly this and says why.
##
## There is no such transform here. `director_preview.gd:_arm_paint_capture` arms
## a `director_paint.gd:Surface` -- a stage-sized `Image` composed on the CPU --
## on every headless run, and `_grab_stage()` prefers it over the framebuffer
## precisely because "it is already in stage pixels, so it skips the crop and the
## resample". So this photographs the same paint the player made, at 1:1, with no
## scale in the path to be wrong about.
##
## The player and the diagnostic are not the same program and are not meant to
## agree everywhere: `director_render.gd` has no scripts, no puppets and no
## fields, so a frame a movie dresses on arrival comes out undressed and it skips
## field members outright. A difference is therefore a *question*, not a verdict --
## which is why this prints the distinct colours on each side of a disagreement
## rather than only a percentage. What it removes is the one explanation that was
## never about either compositor.
##
## Title-agnostic: nothing here names a game, a room or a channel.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## How many distinct colours to name on each side of a differing band. Enough to
## show whether one side's values are palette entries and the other's are not,
## which is the shape `bugs.md` 74 is about.
const LIST_LIMIT := 8


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var case := "the player's own stage, headless, at one pixel per stage pixel"
	h.begin(case)

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame

	var settle := Args.number(args, "settle", 8)
	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		for i in settle:
			await process_frame

	var score = preview.get("_score")
	if not h.check("a score loaded", score != null and int(score.frame_count) > 0,
			"%s" % str(preview.call("movie_name"))):
		h.complete(case)
		quit(h.finish("stage comparison"))
		return

	var frame := _target_frame(preview, args)
	if frame >= 0:
		# Entered rather than indexed, the way `scene_probe.gd` does it: a frame
		# nobody stood on has run no `enterFrame`, so its sprites still carry the
		# previous frame's puppet state and the picture is of neither frame.
		preview.set("_index", frame)
		for i in settle:
			await process_frame
		# **Then put it back, and only then hold.** The settle is what runs the
		# frame's scripts and it is also a running score, so on a movie that does
		# not hold itself the playhead has left by the time the picture is taken:
		# measured at frame 41 against a `--frame 37` that reported itself as 37
		# and was compared, pixel for pixel, against a render of 37. A comparison
		# of two different frames is the one failure this whole tool exists to
		# stop somebody making.
		preview.set("_paused", true)
		preview.set("_index", frame)
	else:
		preview.set("_paused", true)
	await process_frame
	await process_frame
	h.check("the playhead is standing on the frame that was asked for",
		frame < 0 or int(preview.call("current_frame")) == frame,
		"asked %d, standing on %d" % [frame, int(preview.call("current_frame"))])

	h.check("the painter armed an offscreen surface (this is what makes it 1:1)",
		preview.get("paint_capture") != null,
		"display server %s" % DisplayServer.get_name())

	var mine: Image = preview.call("_grab_stage")
	var stage: Vector2i = preview.call("stage_size")
	if not h.check("the stage came back as an image", mine != null,
			"%s frame %d, stage %dx%d" % [str(preview.call("movie_name")),
				int(preview.call("current_frame")), stage.x, stage.y]):
		h.complete(case)
		quit(h.finish("stage comparison"))
		return
	h.check("it is the stage's own size, not the window's",
		mine.get_size() == stage,
		"grabbed %dx%d, stage %dx%d" % [mine.get_width(), mine.get_height(),
			stage.x, stage.y])
	print("player: %s frame %d of %d, %dx%d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame")),
		int(score.frame_count), mine.get_width(), mine.get_height()])

	var out := Args.text(args, "out", "")
	if out != "":
		mine.save_png(out)
		print("wrote %s" % out)

	var against := Args.text(args, "against", "")
	if against != "":
		_compare(h, mine, against, args)
	h.complete(case)
	quit(h.finish("stage comparison"))


func _target_frame(preview: Node, args: Dictionary) -> int:
	var marker := Args.text(args, "marker", "")
	if marker == "":
		return Args.number(args, "frame", -1)
	var labels = preview.get("_labels")
	if labels != null:
		for m in labels.markers:
			if str((m as Dictionary)["name"]).to_lower() == marker.to_lower():
				return int((m as Dictionary)["frame"])
	print("no marker '%s' in %s" % [marker, str(preview.call("movie_name"))])
	return -1


func _compare(h, mine: Image, against: String, args: Dictionary) -> void:
	var case := "the two compositors, pixel by pixel"
	h.begin(case)
	var theirs := Image.load_from_file(against)
	if not h.check("the picture to compare against loaded", theirs != null, against):
		h.complete(case)
		return
	if not h.check("both pictures are the same size",
			theirs.get_size() == mine.get_size(),
			"player %dx%d, other %dx%d" % [mine.get_width(), mine.get_height(),
				theirs.get_width(), theirs.get_height()]):
		h.complete(case)
		return

	var skip_top := Args.number(args, "skip-top", 0)
	var whole := _band(mine, theirs, Rect2i(0, skip_top,
		mine.get_width(), mine.get_height() - skip_top))
	print("whole stage below y%d: %d of %d px differ (%.2f%%)" % [
		skip_top, int(whole["differ"]), int(whole["total"]),
		100.0 * float(whole["differ"]) / maxf(1.0, float(whole["total"]))])

	var spec := Args.text(args, "band", "").split(",", false)
	if spec.size() == 4:
		var rect := Rect2i(int(spec[0]), int(spec[1]), int(spec[2]), int(spec[3]))
		var band := _band(mine, theirs, rect)
		print("band (%d,%d %dx%d): %d of %d px differ (%.2f%%)" % [
			rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			int(band["differ"]), int(band["total"]),
			100.0 * float(band["differ"]) / maxf(1.0, float(band["total"]))])
		_name_colours("  player ", band["mine"])
		_name_colours("  other  ", band["theirs"])
	h.complete(case)


## Counts and, for the pixels that differ, the distinct colours each side put
## there. The colours are the half that says *how* they differ -- one side
## holding values no palette entry holds is a different fault from one side
## holding a different palette entry.
func _band(mine: Image, theirs: Image, rect: Rect2i) -> Dictionary:
	var clip := rect.intersection(Rect2i(Vector2i.ZERO, mine.get_size()))
	var differ := 0
	var total := 0
	var a: Dictionary = {}
	var b: Dictionary = {}
	for y in range(clip.position.y, clip.position.y + clip.size.y):
		for x in range(clip.position.x, clip.position.x + clip.size.x):
			total += 1
			var p := mine.get_pixel(x, y)
			var q := theirs.get_pixel(x, y)
			if p.r8 == q.r8 and p.g8 == q.g8 and p.b8 == q.b8:
				continue
			differ += 1
			var pk := "(%d,%d,%d)" % [p.r8, p.g8, p.b8]
			var qk := "(%d,%d,%d)" % [q.r8, q.g8, q.b8]
			a[pk] = int(a.get(pk, 0)) + 1
			b[qk] = int(b.get(qk, 0)) + 1
	return {"differ": differ, "total": total, "mine": a, "theirs": b}


func _name_colours(label: String, counts: Dictionary) -> void:
	var keys: Array = counts.keys()
	keys.sort_custom(func(x, y): return int(counts[x]) > int(counts[y]))
	var parts: Array[String] = []
	for k in keys.slice(0, LIST_LIMIT):
		parts.append("%s x%d" % [str(k), int(counts[k])])
	print("%s%d distinct: %s" % [label, keys.size(), ", ".join(parts)])
