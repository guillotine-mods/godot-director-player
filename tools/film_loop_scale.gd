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
## flag, whose populations `tools/film_loop_stretch.gd` separated before it was
## deleted with the retired renderer's harnesses). That is a real and separate
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
## ### Which size is asked for, which is the third negative control
##
## The drawn size read here is **`Geometry.drawn_size(child_sprite(...), member)`**,
## not `child_sprite`'s own answer, because that is the size the painter's leaf
## branch really draws at: the artwork arrives from `host._texture_for`, which asks
## `drawn_size`, and the registration offset comes off `texture.get_size()`. Asking
## `child_sprite` instead measured the quantity the scaling *computes* rather than
## the one the renderer *uses*, and the two disagreed by the whole squeeze:
## `drawn_size` returned the member's natural size for any record without
## the stretch flag, which is every film-loop child in the general case. That is
## `docs/bugs-closed.md` 99, and this file passed over it — a harness green on the
## wrong noun, which is the shape `porting-fidelity-verification` is about.
##
## So it is now a measured control rather than a story. Revert that fix — both
## halves, since `child_sprite` names the constant `drawn_size` reads — and this
## reports **41,816 regressed of 48,750** over `piposh2`, **26,746 of 27,750** over
## `piposh-dream` and **2,077 of 2,578** over `rating`, while all three
## natural-size lines and both nested lines stay exactly where they are.
##
## The **tolerance** stays derived from `child_sprite`'s scaled answer, and
## `_case`'s comment says why at length: recomputing it against the new reading
## would make the allowance `0.75 x natural` at this squeeze and report 0 regressed
## by cancelling the bug instead of by its absence. That is the one edit here that
## would look like tidying and would silently disarm the file.
##
## The **nested** leg keeps reading `child_sprite`'s answer, because `paint_loop`'s
## type-2 branch does: it threads the record's own size into both `scaled_reg` and
## `nested_scale` and never asks `drawn_size` at all. Two branches in the painter,
## two readings here, and neither is a preference.
##
## ### One level down, for the same reason
##
## `paint_loop` recurses: a film-loop child expands inline, and its own children are
## placed by `nested_scale()` and a second `Geometry.scaled_reg`. **Neither of those
## was asserted anywhere**, so a nested loop drawn at the wrong size or the wrong
## offset passed every gate in the suite — the nesting harness
## (`tools/film_loop_nesting.gd`) asks whether the inner artwork reaches the painter
## at all, which is a different question from whether it lands in the right place.
##
## So the same comparison is applied one level down, and **the box changes with it**:
## a grandchild's box is the *nested loop's own rect on the stage*, not the top-level
## sprite's. That distinction is the whole care of the extension. The nested rect is
## `Rect2(place_child(...), child_sprite(...))` — the same two expressions
## `paint_loop` uses to recurse, read from the same functions — and using the sprite's
## box instead would assert something strictly stronger than this file's own
## reasoning allows, failing on exactly the population the header above spends
## fifteen lines explaining is already outside its box at natural size.
##
## The invariant is unchanged: a grandchild inside its nested loop's box at natural
## size must still be inside it when the *top-level* loop is squeezed.
##
## **Measured negative control**, because a new check that cannot go red is worth
## nothing: replace `nested_scale(box.size, member)` with `Vector2.ONE` — which is
## precisely the bug `nested_scale` exists to fix, since `child_scale` answers `ONE`
## for an unflagged loop child — and this reports **3,764 regressed of 4,044** over
## `--root piposh-dream`. Note that 280 of them fail at *natural* top-level size too,
## which is the useful surprise: a nested loop is routinely drawn at a size other than
## its own even when nothing above it is squeezed, because the child record carries a
## rect of its own. So `nested_scale` is load-bearing at both sizes and not only under
## a squeeze.
##
## **And what it does not catch, stated rather than left to be discovered.** Dropping
## the nested `Geometry.scaled_reg` — the second half of the recursive `place_child`
## in `paint_loop` — does *not* turn this red: it shifts the artwork by the
## registration offset, which pushes 1,689 of the 4,044 outside their box **at natural
## size**, and the comparison discipline then excludes exactly those from the squeezed
## comparison. The remaining 2,355 stay inside both and the check passes. That
## exclusion is the same rule the 248-of-4,901 paragraph above defends and it is right
## to keep, so the offset shows up here as a **number and not an assertion**: the
## natural-size line prints 0 of 4,044 outside for `piposh-dream` and 0 of 1,394 for
## `rating`, and a run where either becomes non-zero has moved something even though
## nothing went red. Asserting that zero outright is what this file declines to do, on
## `AGENTS.md`'s rule that a harness must assert what the port controls rather than
## what a 1990s cast got right — the count is a property of those two casts' authoring
## as much as of this arithmetic, and a third title may legitimately carry a loop whose
## rect is not the union of its contents. `tools/film_loop_nesting.gd` is the entry
## that would notice the artwork going missing; nothing yet notices it going one
## registration offset sideways.
##
## The tolerance compounds and is derived rather than chosen, the same way the
## depth-1 allowance is: the nested loop's own drawn size is an integer, so its box
## misses the exact scaled box by up to a pixel, and the grandchild inside it misses
## again. Both misses come from `child_sprite`'s own answers, so neither can drift
## from the rule it is allowing for.
##
## **The population lives in two roots and not in `gate.sh`'s.** Over all six
## corpora there are exactly 10 nested sites, in `piposh-dream` and `rating`;
## `piposh2`, which `gate.sh` pins, has none. So the nested check asserts zero
## regressions unconditionally and asserts a non-empty population only when the sweep
## found one at all — and prints which case it is, so a pinned run cannot be mistaken
## for a run that proved something. Measure the real population with
## `--root piposh-dream` and `--root rating`.
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
	h.begin("squeezing a loop puts none of a nested loop's children outside it")

	var tally := {
		"loops": 0, "children": 0, "natural_outside": 0, "regressed": 0,
		"scaled_loops": 0, "inside_both": 0,
		"nested_loops": 0, "grandchildren": 0, "nested_natural_outside": 0,
		"nested_regressed": 0, "nested_inside_both": 0,
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
	print("     %d of %d grandchildren likewise, over %d nested loop site(s)"
		% [int(tally["nested_natural_outside"]), int(tally["grandchildren"]),
			int(tally["nested_loops"])])

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

	# Two claims in one check, and deliberately asymmetric. **Zero regressions is
	# asserted unconditionally**, because a corpus with no nested loop in it cannot
	# regress and must not fail for that. The population half is conditional on there
	# being a population: `gate.sh` pins `piposh2`, which has none of the corpus's 10
	# nested sites, so a bare `grandchildren > 0` would take this entry red on the one
	# root the suite actually runs. What keeps that from being a hole is the detail
	# line — it says which of the two cases the run is, so "0 regressed" over 0
	# grandchildren cannot be read as a result. `--root piposh-dream` and
	# `--root rating` are where the number is.
	var deep := int(tally["grandchildren"])
	h.check("a grandchild inside its nested loop's box at natural size is still inside"
		+ " it when the loop above is squeezed",
		int(tally["nested_regressed"]) == 0
			and (deep == 0 or int(tally["nested_inside_both"]) > 0),
		"%d regressed, %d held, over %d grandchild(ren) in %d nested site(s)"
			% [int(tally["nested_regressed"]), int(tally["nested_inside_both"]),
				deep, int(tally["nested_loops"])]
			+ (" — this corpus nests nothing, so nothing here was exercised"
				if deep == 0 else ""))
	h.complete("squeezing a loop puts none of a nested loop's children outside it")

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
			var was_deep := {}
			var now_deep := {}
			var was_in := _case(lib, number, m, loop, table, natural, false, was_deep)
			var now_in := _case(lib, number, m, loop, table, small, true, now_deep)

			# The nested level, compared the same way and against its own box. Counted
			# per parent loop rather than per grandchild, because "how many sites nest"
			# is what says whether this half of the file ran at all.
			if not was_deep.is_empty():
				tally["nested_loops"] = int(tally["nested_loops"]) + 1
			for key in was_deep:
				tally["grandchildren"] = int(tally["grandchildren"]) + 1
				var deep_was: Dictionary = was_deep[key]
				if not bool(deep_was["inside"]):
					tally["nested_natural_outside"] = int(
						tally["nested_natural_outside"]) + 1
				if not scaled or not now_deep.has(key) or not bool(deep_was["inside"]):
					continue
				var deep_now: Dictionary = now_deep[key]
				if bool(deep_now["inside"]):
					tally["nested_inside_both"] = int(tally["nested_inside_both"]) + 1
					continue
				tally["nested_regressed"] = int(tally["nested_regressed"]) + 1
				if _verbose or lines.size() < 60:
					lines.append("%s  %d:%d %s NESTED %s: %s in %s at %dx%d, %s in %s at %dx%d"
						% [rel, lib, number, str(m.get("name", "")), str(key),
							str(deep_was["art"]), str(deep_was["box"]),
							int(natural.x), int(natural.y),
							str(deep_now["art"]), str(deep_now["box"]),
							int(small.x), int(small.y)])

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
##
## `deep` is filled with the same answer for the children of any child that is itself
## a film loop, keyed `"frame N loop L frame J child M"` and measured against the
## *nested* loop's rect rather than the sprite's — see the header. It is an out
## parameter rather than a second return so that the depth-1 map keeps the shape every
## line of the caller already reads.
func _case(lib: int, number: int, m: Dictionary, loop, table,
		size: Vector2, squeezed: bool, deep: Dictionary = {}) -> Dictionary:
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
			# Two sizes, because the painter reads two. A leaf's artwork comes back
			# from `host._texture_for` at `Geometry.drawn_size`'s answer and its
			# registration offset is taken from `texture.get_size()`, so that pair is
			# what the containment test below has to be built from. `child_sprite`'s
			# own answer is what `paint_loop` threads into the recursion instead, so
			# that is what the nested box is built from, and what the tolerance is
			# derived against. The two agreed trivially while only one of them was
			# ever read here, and the day they stopped agreeing was `bugs.md` 99.
			var scaled := Vector2(int(drawn["width"]), int(drawn["height"]))
			var kid_size: Vector2 = Geometry.drawn_size(drawn, cm)
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
			# Both halves come from `child_sprite`'s own answers -- the scaled one and
			# the unscaled one -- rather than from the size rule restated here, so the
			# allowance cannot drift from the rule it is allowing for.
			#
			# **Deliberately not recomputed against `kid_size`**, which is the trap
			# this line reads like an oversight of. `kid_size` is now `drawn_size`'s
			# answer, so a tolerance taken against it would be the whole difference
			# between the two -- an allowance of `0.75 x natural` at this squeeze --
			# and it would report 0 regressed by cancelling the bug rather than by the
			# bug being absent. The truncation being allowed for is `child_sprite`'s
			# own `int()`, and that is where it stays.
			var base: Dictionary = FilmLoopView.child_sprite(kid, kid_lib, cm)
			var missed := Vector2(
				absf(scaled.x - int(base["width"]) * scale.x),
				absf(scaled.y - int(base["height"]) * scale.y))
			var room := slack.grow_individual(
				missed.x, missed.y, missed.x, missed.y)
			out["frame %d child %d" % [i, int(kid["cast_id"])]] = {
				"inside": room.encloses(Rect2(at, kid_size)),
				"art": Rect2(at, kid_size), "box": box,
			}
			if int(cm.get("type", 0)) == LOOP_TYPE:
				# `paint_loop`'s type-2 branch reads `child_sprite`'s size, not
				# `drawn_size`'s -- it threads the record's own width and height into
				# both `Geometry.scaled_reg` and `nested_scale` -- so the nested box is
				# built from `scaled` and from its own `place_child`, which is that
				# branch written out. Reading `kid_size` here instead would assert the
				# leaf branch's arithmetic one level up, where the painter never uses
				# it. The two answers coincide once a scaled record is honoured; the
				# nested leg is on the record's side of that either way.
				var nested_reg: Vector2 = Geometry.scaled_reg(cm, scaled)
				_nested(kid_lib, kid, cm, table,
					Rect2(FilmLoopView.place_child(origin, space, kid, nested_reg, scale),
						scaled), missed, i, deep)
	return out


## The children of one nested loop, measured against **that loop's** rect.
##
## `box` is where the nested loop itself landed and how big it was drawn, which is
## exactly what `paint_loop` passes down: `place_child(...)` for the origin and
## `child_sprite(...)`'s size for the scale. So the question asked here is the same
## one the outer level asks, one level in, and it is the only level at which
## `nested_scale()` is exercised at all.
##
## `parent_missed` is the truncation the nested loop's own drawn size already carries.
## It is added to the allowance because a box computed from a truncated integer size is
## *smaller* than the exact scaled box, so leaving it out would report a rounding as a
## placement failure. Both halves of the allowance come from `child_sprite`'s own
## answers rather than from a tolerance chosen to keep the corpus quiet.
func _nested(lib: int, child: Dictionary, member: Dictionary, table, box: Rect2,
		parent_missed: Vector2, at_frame: int, deep: Dictionary) -> void:
	var inner = FilmLoopView.open_loop(lib, member, table)
	if inner == null:
		return
	var scale: Vector2 = FilmLoopView.nested_scale(box.size, member)
	var space: Vector2 = FilmLoopView.loop_origin(member)
	var slack := box.grow(1.0).grow_individual(
		parent_missed.x, parent_missed.y, parent_missed.x, parent_missed.y)
	for j in inner.frame_count:
		for kid in inner.children(j):
			var kid_lib: int = FilmLoopView.child_lib(kid, lib, table)
			if kid_lib < 0:
				continue
			var cm: Dictionary = table.get_member(kid_lib, int(kid["cast_id"]))
			if cm.is_empty():
				continue
			var drawn: Dictionary = FilmLoopView.child_sprite(kid, kid_lib, cm, scale)
			var kid_size := Vector2(int(drawn["width"]), int(drawn["height"]))
			var reg: Vector2 = Geometry.scaled_reg(cm, kid_size)
			var at: Vector2 = FilmLoopView.place_child(
				box.position, space, kid, reg, scale)
			var base: Dictionary = FilmLoopView.child_sprite(kid, kid_lib, cm)
			var missed := Vector2(
				absf(kid_size.x - int(base["width"]) * scale.x),
				absf(kid_size.y - int(base["height"]) * scale.y))
			var room := slack.grow_individual(
				missed.x, missed.y, missed.x, missed.y)
			deep["frame %d loop %d frame %d child %d" % [
					at_frame, int(child["cast_id"]), j, int(kid["cast_id"])]] = {
				"inside": room.encloses(Rect2(at, kid_size)),
				"art": Rect2(at, kid_size), "box": box,
			}
