extends SceneTree
## Does a film loop drawn at a size other than its own keep its contents inside
## the sprite?
##
##   godot --headless --path . --script tools/film_loop_scale.gd
##   godot --headless --path . --script tools/film_loop_scale.gd -- --root piposh
##   godot --headless --path . --script tools/film_loop_scale.gd -- --verbose
##
## A loop's `initialRect` is the union bounding box of its own contents, so it is
## both the loop's natural size and the coordinate space its children are measured
## in (DIRECTOR_ENGINE.md §1.6). Put that loop on a sprite of another size and
## **everything inside scales by `drawn / initialRect`** — the child positions and
## the children themselves. Miss it and the children keep their authored
## coordinates at their authored size, so the animation appears wherever the
## author happened to build it rather than where the sprite is.
##
## That was §16.8, and the retired renderer was the half that scaled. The symptom
## it left behind: `PIPDATA/DISKSHOT.dir`'s clay pigeons are sprites of about 26x7
## and the `diskblow` loop they swap to is 287x279 with its child at (320,240), so
## every explosion drew full-size in the middle of the stage, on top of the player.
##
## ### What is asserted, and why it is not plain containment
##
## The obvious invariant — every child draws inside the sprite's rect — is false
## in this corpus before anything is scaled: **248 of 4,901 children are already
## outside their loop's own rect at natural size**, across containers this change
## does not touch. `day2`'s `singright` is the shape of it: the loop's rect is
## 145x257 and its child 220 draws 104x257 starting 61px in, so it hangs 20px off
## the right. Either the rect is not the union of the contents for those loops or
## the child's drawn size is not the one it was authored at (the child stretch
## flag, `tools/film_loop_stretch.gd`'s subject). That is a real and separate
## question, it is reported here as a number, and asserting on it would make this
## file fail for a reason that has nothing to do with scale.
##
## So what is asserted is the **comparison**: a child that is inside its box when
## the loop is drawn at its own size must still be inside it when the loop is
## squeezed. Scaling is the only difference between the two runs, so a child that
## crosses that line crossed it because of scaling — and a loop whose contents
## keep their authored coordinates while the sprite shrinks crosses it for
## every child it has. No oracle is needed and nothing is compared against the
## code's own arithmetic.
##
##   * **natural** — the loop drawn at `initialRect`, where `child_scale` returns
##     exactly 1 and the arithmetic is untouched. The baseline, and the control:
##     its count must not move.
##   * **squeezed** — a quarter size on each axis, which is what a stretched
##     sprite does to a loop and what no container in this corpus records in its
##     score, because a loop reaches a stretched channel through a script
##     (`set the memberNum of sprite`) rather than through the score. Sweeping
##     score records alone would have found nothing.
##
## Delete the `* scale` from `film_loop_view.place_child` and this goes red with
## thousands of regressions; delete the size scaling in `child_sprite` and it goes
## red on the children that no longer fit their shrunken box.
##
## Title-agnostic: it names no movie, member or channel of its own and sweeps
## whatever `director_game.cfg` (or `--root`) points at.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")

const LOOP_TYPE := 2
## Somewhere on the stage, and deliberately not the origin: a placement bug that
## happens to leave everything at (0,0) would hide against a zero anchor.
const AT := Vector2(320, 240)
## The squeeze applied to the second case. A quarter on each axis is well inside
## what this corpus really does — DISKSHOT's disks are 26/287 and 7/279 — while
## staying large enough that a child still has pixels to be wrong about.
const SQUEEZE := 4

var _verbose := false


func _init() -> void:
	var args := Args.parse()
	_verbose = Args.flag(args, "verbose")
	var h := Harness.new()

	var paths = Paths.new()
	if not paths.load_config():
		print("FAIL  no game configured")
		quit(1)
		return

	var containers: Array = []
	for rel in paths.containers():
		var ext := str(rel).get_extension().to_lower()
		if ext == "dir" or ext == "cst":
			containers.append(str(rel))

	h.begin("squeezing a loop puts none of its children outside the sprite")

	var tally := {
		"loops": 0, "children": 0, "natural_outside": 0, "regressed": 0,
		"scaled_loops": 0, "inside_both": 0,
	}
	var lines: Array[String] = []
	for rel in containers:
		_sweep(paths, str(rel), tally, lines)

	for line in lines.slice(0, 40):
		print("     %s" % line)
	if lines.size() > 40:
		print("     ... and %d more" % (lines.size() - 40))
	print("     %d of %d children already sit outside their loop's rect at natural"
		% [int(tally["natural_outside"]), int(tally["children"])]
		+ " size — a separate question, see the header")

	# The population is asserted beside the failures. "0 regressed" is also what a
	# sweep that found no loops prints, and this file's whole subject is a case
	# the corpus's own score records do not contain: without the count of loops
	# that really scaled, a `child_scale` that returned 1 for everything would
	# pass this silently.
	h.check("a child inside its box at natural size is still inside it when squeezed",
		int(tally["regressed"]) == 0 and int(tally["scaled_loops"]) > 0
			and int(tally["inside_both"]) > 0,
		"%d regressed, %d children held, over %d of %d loops that really scaled "
		% [int(tally["regressed"]), int(tally["inside_both"]),
			int(tally["scaled_loops"]), int(tally["loops"])]
		+ "(1/%d on each axis) across %d containers" % [SQUEEZE, containers.size()])
	h.complete("squeezing a loop puts none of its children outside the sprite")

	quit(h.finish("a film loop's contents follow the sprite it is drawn as"))


func _sweep(paths, rel: String, tally: Dictionary, lines: Array[String]) -> void:
	var movie_path: String = paths.resolve(rel)
	var f = ContainerFile.new()
	if not f.open(movie_path):
		return
	var table = CastTable.new()
	if not table.open(f, paths):
		f.close()
		return

	for n in table.cast_libs:
		var lib := int(n)
		var cast = table.cast_for(lib)
		if cast == null:
			continue
		for number in range(1, cast.member_count + 2):
			var m: Dictionary = cast.member(number)
			if m.is_empty() or int(m.get("type", 0)) != LOOP_TYPE:
				continue
			if int(m.get("data_chunk_id", -1)) < 0:
				continue
			# Through the preview's own entry point, so what is measured is what
			# the player draws rather than a second reading written here.
			var loop = FilmLoopView.open_loop(lib, m, table)
			if loop == null:
				continue
			var natural := Vector2(int(m.get("width", 0)), int(m.get("height", 0)))
			if natural.x <= 0.0 or natural.y <= 0.0:
				continue
			tally["loops"] = int(tally["loops"]) + 1
			var small := Vector2(
				maxf(1.0, floor(natural.x / SQUEEZE)),
				maxf(1.0, floor(natural.y / SQUEEZE)))
			var scaled := small != natural
			if scaled:
				tally["scaled_loops"] = int(tally["scaled_loops"]) + 1
			var was_in := _case(lib, number, m, loop, table, natural, false)
			var now_in := _case(lib, number, m, loop, table, small, true)

			for key in was_in:
				tally["children"] = int(tally["children"]) + 1
				var was: Dictionary = was_in[key]
				if not bool(was["inside"]):
					tally["natural_outside"] = int(tally["natural_outside"]) + 1
				if not scaled or not now_in.has(key) or not bool(was["inside"]):
					continue
				var now: Dictionary = now_in[key]
				if bool(now["inside"]):
					tally["inside_both"] = int(tally["inside_both"]) + 1
					continue
				tally["regressed"] = int(tally["regressed"]) + 1
				if _verbose or lines.size() < 60:
					lines.append("%s  %d:%d %s %s: %s in %s at %dx%d, %s in %s at %dx%d"
						% [rel, lib, number, str(m.get("name", "")), str(key),
							str(was["art"]), str(was["box"]),
							int(natural.x), int(natural.y),
							str(now["art"]), str(now["box"]),
							int(small.x), int(small.y)])
	f.close()
	table.close()


## One loop drawn at one size: `"frame N child M"` -> is its artwork inside the
## sprite's own rect. Placed through the renderer's own functions, so what is
## measured is what the player sees rather than a second reading written here.
func _case(lib: int, number: int, m: Dictionary, loop, table,
		size: Vector2, squeezed: bool) -> Dictionary:
	# The stretch flag is what makes `drawn_size` honour a size that is not the
	# member's own, exactly as an authored sprite record does.
	var sprite := {
		"channel": 1, "cast_lib": lib, "cast_id": number,
		"loc_h": int(AT.x), "loc_v": int(AT.y),
		"width": int(size.x), "height": int(size.y),
		"ink": 0, "stretch": squeezed,
	}
	var box: Rect2 = Geometry.stage_rect(sprite, m)
	var origin: Vector2 = FilmLoopView.stage_origin(sprite, m)
	var space: Vector2 = FilmLoopView.loop_origin(m)
	var scale: Vector2 = FilmLoopView.child_scale(sprite, m)
	# One pixel, because the placement is float and the sizes are truncated ints;
	# §1.10 says Director is integer throughout and this port draws in floats.
	var slack := box.grow(1.0)

	var out := {}
	for i in loop.frame_count:
		for kid in loop.children(i):
			var kid_lib: int = FilmLoopView.child_lib(kid, lib, table)
			if kid_lib < 0:
				continue
			var cm: Dictionary = table.get_member(kid_lib, int(kid["cast_id"]))
			if cm.is_empty():
				continue
			var drawn: Dictionary = FilmLoopView.child_sprite(kid, kid_lib, cm, scale)
			var kid_size := Vector2(int(drawn["width"]), int(drawn["height"]))
			var reg: Vector2 = Geometry.scaled_reg(cm, kid_size)
			var at: Vector2 = FilmLoopView.place_child(origin, space, kid, reg, scale)
			# A child's drawn size is an integer, so it misses the exact scaled
			# size by up to a pixel in either direction — truncated down, or
			# clamped up when the scaled size falls below one. Its registration
			# offset is derived from that same integer, so the miss lands on the
			# position too, and the edge of the artwork can sit that far outside a
			# box computed in floats. The allowance is therefore the miss itself
			# rather than a number chosen to make the corpus quiet: `arcade2`'s
			# `gunup` overshoots by 0.18px and `ultrablow`'s 1x1 marker by 0.006.
			#
			# The unscaled size comes from `child_sprite`'s own answer rather than
			# from the size rule restated here, so this cannot drift from it.
			var base: Dictionary = FilmLoopView.child_sprite(kid, kid_lib, cm)
			var missed := Vector2(
				absf(kid_size.x - int(base["width"]) * scale.x),
				absf(kid_size.y - int(base["height"]) * scale.y))
			var room := slack.grow_individual(
				missed.x, missed.y, missed.x, missed.y)
			out["frame %d child %d" % [i, int(kid["cast_id"])]] = {
				"inside": room.encloses(Rect2(at, kid_size)),
				"art": Rect2(at, kid_size), "box": box,
			}
	return out
