extends SceneTree
## Photograph the running player's stage **headlessly**, at one image pixel per
## stage pixel, and compare it against a picture composited some other way.
##
##   godot --headless --path . --audio-driver Dummy --script tools/stage_compare.gd -- \
##       --root piposh --boot PIPDATA/PIANO.dir --frame 37 --debug-ui off \
##       --render PIPDATA/PIANO.dir --band 8,466,252,9 --skip-top 60
##
##   --boot C       the container to boot (the player's own `--boot`/`--root`)
##   --movie C      `go to movie` after boot, when the frame wanted is elsewhere
##   --frame N      stand here (`--marker M` for a label instead)
##   --settle N     process frames after each step (default 8)
##   --band x,y,w,h one rectangle to report separately from the whole stage
##   --render C     compose the picture to difference against here and now,
##                  through `director_render.gd:compose`, at whatever frame the
##                  player turned out to be standing on
##   --against PNG  or difference against a picture some earlier run wrote
##   --skip-top N   ignore the first N rows of both (a HUD the diagnostic
##                  cannot dress, which is the usual reason a whole-stage
##                  number is not the interesting one)
##   --out PATH     write the player's own stage image
##   --debug-ui off **required** -- see below
##
## ## The debug layer has to be off, and this refuses to run with it on
##
## `bugs.md` 74 -- "eight rows of Piposh 1's piano keyboard draw differently in
## the player and in `director_render.gd`" -- was **this tool photographing our
## own debug HUD** and reporting it as a compositor disagreement. It cost two
## sessions and three wrong theories, so the check is a hard failure rather than
## a note.
##
## `stage_paint.gd:295` draws `frame 37/206  playpiano  fps 15  hit:art  cur:0`
## at `Vector2(8, stage.y - 8)` = (8,472), white at alpha 0.75, whenever
## `DebugKeys.enabled()` -- which on a run from source is `auto`, which is on.
## Every number the entry recorded is that one string:
##
##   * the band it names, `(8,466) 252x9`, is the string's bounding box;
##   * "the player produces 243 distinct values where the diagnostic produces 23
##     exact palette entries" is antialiased glyph coverage -- `Surface.glyphs`
##     composes atlas cells whose alpha is partial, `Image.blend_rect` blends
##     rather than replaces, and the results land between palette entries;
##   * it showed only on the dark seam under the keys because white text over a
##     white key changes nothing, which is what made it look like a dither fault
##     in the artwork;
##   * and it was stable across frames 37 and 39 because the HUD is.
##
## Measured with `--debug-ui off`: **0 of 268,800 px below y60 differ**, on frame
## 37 and on frame 39, band included. That number is also what rules out the two
## candidates the entry carried -- a palette disagreement cannot come out exact on
## every pixel of 67 sprites, and the partial alpha was ours.
##
## The whole stage *including* the top 60 rows differs on 496 px, which is the
## two field members `director_render.gd` skips by design. `--skip-top` is for
## that and nothing else.
##
## ## What a real disagreement looks like, so 74's shape is not mistaken again
##
## `--root piposh2 --boot PIP2DATA/CHESS.dir --marker ches1 --debug-ui off
## --render PIP2DATA/CHESS.dir --skip-top 60` differs on **7,005 px (2.61%)**,
## and **both sides are exact palette entries** -- 9 distinct on the player's
## side, 16 on the diagnostic's, `(255,204,0)` x1772 against x1806 at the top of
## each. That is the movie having dressed itself with Lingo the diagnostic does
## not run, and it is the *expected* asymmetry this tool's header describes. The
## signature to be suspicious of is the other one: one side holding values no
## palette entry holds. That is either a blend somewhere, or -- as it was in 74
## -- something of ours in the picture. So CHESS is not a gate entry: it has no
## principled budget, and a number picked to make it green would gate nothing.
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
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const Render := preload("res://tools/director_render.gd")

## How many distinct colours to name on each side of a differing band. Enough to
## show whether one side's values are palette entries and the other's are not,
## which is the shape `bugs.md` 74 is about.
const LIST_LIMIT := 8


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var case := "the player's own stage, headless, at one pixel per stage pixel"
	h.begin(case)

	# First, before anything paints. The debug layer draws a translucent white
	# HUD line across the bottom of the stage and a SKIP button at the top, and
	# neither is the movie -- a comparison taken with them on is a comparison
	# against our own overlay. `bugs.md` 74 is the whole of what that costs, and
	# the header carries the account.
	if not h.check("the debug layer is off, so this photographs the movie and "
			+ "not our own HUD", not DebugKeys.enabled(),
			"pass --debug-ui off; the HUD alone accounts for 833 px of "
			+ "PIANO.dir frame 37"):
		h.complete(case)
		quit(h.finish("stage comparison"))
		return

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
	# How much of this capture the surface knows it did not rasterise the way the
	# GPU would have -- every string of glyphs, and a tiled `texture_rect` nothing
	# in this port passes. Printed rather than asserted because a movie with a
	# field on the frame legitimately raises it, and because a non-zero here is
	# the first thing to look at when a difference turns out to be text-shaped:
	# that is what `bugs.md` 74 was.
	var capture = preview.get("paint_capture")
	if capture != null:
		print("surface: %d primitives, %d approximated" % [
			int(capture.drawn), int(capture.approximated)])

	var out := Args.text(args, "out", "")
	if out != "":
		mine.save_png(out)
		print("wrote %s" % out)

	var container := Args.text(args, "render", "")
	if container != "":
		# Composed here rather than loaded from a PNG some earlier command wrote,
		# and composed at the frame the player *turned out* to be standing on
		# rather than at the one that was asked for. Both halves close the same
		# hole: two invocations can be of two different frames, and the entry this
		# tool was written for was compared at 37 against a player standing on 41.
		var lines: Array[String] = []
		var theirs := Render.compose(container, int(preview.call("current_frame")),
			"", lines)
		if Args.flag(args, "verbose"):
			for line in lines:
				print(line)
		if h.check("the reference frame composited", theirs != null,
				"%s frame %d%s" % [container, int(preview.call("current_frame")),
					"" if theirs != null else ": " + "; ".join(lines)]):
			_measure(h, mine, theirs, args)
	var against := Args.text(args, "against", "")
	if against != "":
		_compare(h, mine, against, args)
	# **A run that named neither is dark, not clean.** Every version of this tool
	# before today would photograph the stage, print five green lines about the
	# capture and exit 0 without comparing anything at all, which is the failure
	# `gate.sh`'s EMPTY guard exists for and which that guard cannot see, because
	# five checks is not zero checks. It is worth a red of its own: a gate entry
	# whose `--render` was dropped in an edit would otherwise go on passing.
	h.check("a picture to compare against was named",
		container != "" or against != "",
		"pass --render <container> or --against <png>")
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
	var theirs := Image.load_from_file(against)
	if not h.check("the picture to compare against loaded", theirs != null, against):
		return
	_measure(h, mine, theirs, args)


## The two pictures, counted and asserted.
##
## **It asserts now, and it did not before.** Every earlier version printed a
## percentage and passed, which is how `bugs.md` 74 could reproduce for two
## sessions with nobody able to put it in `gate.sh`: a tool that only prints is
## a tool nothing runs. `--max-differ` is the budget, and it defaults to **0**
## because that is the measurement -- with the debug layer off, the player and
## `director_render.gd` agree on every one of the 268,800 px of `PIANO.dir`
## frame 37 below y60, and on frame 39 too. A budget above zero is a claim that
## something is legitimately undressed on that frame (the diagnostic runs no
## scripts and skips field members), and it should be written on the gate entry
## where the next reader can see the number and ask about it.
func _measure(h, mine: Image, theirs: Image, args: Dictionary) -> void:
	var case := "the two compositors, pixel by pixel"
	h.begin(case)
	if not h.check("both pictures are the same size",
			theirs.get_size() == mine.get_size(),
			"player %dx%d, other %dx%d" % [mine.get_width(), mine.get_height(),
				theirs.get_width(), theirs.get_height()]):
		h.complete(case)
		return

	var skip_top := Args.number(args, "skip-top", 0)
	var budget := Args.number(args, "max-differ", 0)
	var whole := _band(mine, theirs, Rect2i(0, skip_top,
		mine.get_width(), mine.get_height() - skip_top))
	print("whole stage below y%d: %d of %d px differ (%.2f%%)" % [
		skip_top, int(whole["differ"]), int(whole["total"]),
		100.0 * float(whole["differ"]) / maxf(1.0, float(whole["total"]))])
	if int(whole["differ"]) > 0:
		_name_colours("  player ", whole["mine"])
		_name_colours("  other  ", whole["theirs"])

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
		h.check("the band agrees within its budget", int(band["differ"]) <= budget,
			"%d differ, budget %d" % [int(band["differ"]), budget])

	h.check("the two compositors agree within the budget",
		int(whole["differ"]) <= budget,
		"%d of %d differ below y%d, budget %d" % [int(whole["differ"]),
			int(whole["total"]), skip_top, budget])
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
