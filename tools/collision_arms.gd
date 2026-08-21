extends SceneTree
## §2.7's ink-aware arms: which one a pair of operands takes, and what each one
## answers where a bounding box would have said yes.
##
##   godot --headless --path . --script tools/collision_arms.gd
##   godot --headless --path . --script tools/collision_arms.gd -- --root piposh-dream --boot hatul3.dir
##
## `tools/sprite_collision.gd` next door asserts the *visibility* rule these
## operators obey and nothing about ink; this asserts the ink and nothing about
## visibility. They are deliberately two files: a port that fixed one by deleting
## the other's rule has happened once already (`docs/bugs-closed.md` 43).
##
## ## Why every arm is asserted, including the ones the corpus cannot reach
##
## `tools/collision_ink.gd` measured the corpus before this was written: over all
## six shipped roots, **82 operand pairs change arm** and every one of them is
## `matte-on-matte` or `box-on-matte`. Nothing measured reaches `matte-within`, and
## nothing reaches the null-matte fallback. So two of the four arms have no witness
## in any title this engine runs, and `AGENTS.md` is explicit that this is a reason
## to build them from the reference and say they are unverified -- not a reason to
## leave them unasserted. The scans therefore take masks and rects rather than a
## host (`scenes/preview/collision.gd`), and the cases below build the holes.
##
## ## The rule the cases are shaped by
##
## **Every arm that clears is paired with the box test that does not.** A matte
## test answering false proves nothing on its own -- a scan that always answered
## false would pass such a check -- so each negative case asserts in the same
## breath that `Rect2.intersects`/`Rect2.encloses` answers *true* on the same two
## rects. That is the difference between "the arm rejected this" and "the arm
## rejects everything", and it is the shape `porting-fidelity-verification` calls
## a round-trip assertion.
##
## The live case, last, is the one that depends on the loaded title, and it is the
## only check anywhere that can tell this change from doing nothing. Every other
## check here reaches `Collision` or `director_ink.gd` directly, and a `refine` that
## answered `true` unconditionally would pass all of them -- and all eleven
## minigame entries, and `sprite_collision`, whose `sprite N within N` and
## `intersects N N` are both satisfied by always-true. So this walks the movie's own
## score preferring a frame where the matte arm **disagrees** with the box, and
## asserts the operator answers 0 there. Where the title has no such pair it says
## which direction went unwitnessed rather than passing quietly, and where it has no
## matte pair at all it **says so and asserts nothing**, which is
## `tools/video_fallback.gd`'s and `sprite_lifetime`'s fourth case's pattern and
## the only honest thing to do with a corpus that cannot express a feature.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Collision := preload("res://scenes/preview/collision.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")

## A record the arm predicates can read. Only four fields matter to them, and
## naming the rest would suggest the predicates consult more than they do.
const BITMAP := Ink.TYPE_BITMAP
const SHAPE := Ink.TYPE_SHAPE
## `kCastMemberSprite`, the sprite-type byte every record in all six shipped roots
## carries (`tools/collision_ink.gd`, 8,057,628 of them).
const TYPE_CAST_MEMBER := 16
## A QuickDraw shape sprite type -- `kRectangleSprite`. No container this port can
## open holds one, which is exactly why the `within` predicate is asserted against
## it here rather than left to a corpus that has none.
const TYPE_QD_RECT := 2


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	_arms(h)
	_scans(h)
	await _live(h, args)

	quit(h.finish("the ink-aware arms of `intersects` and `within`"))


## Arm selection, against `director_ink.gd`'s two predicates directly.
##
## Pure functions, so this half runs on any root and on none. The two predicates
## are asserted *apart* because the whole defect they fix is that the reference has
## two and the port had neither: `c_intersects` tests the cast type and `c_within`
## tests the sprite-type byte, and a port that collapses them agrees with the
## reference on this corpus and disagrees with it on the first D3-era container.
func _arms(h: Harness) -> void:
	var name := "which arm a pair of operands takes"
	h.begin(name)

	# `intersects`, all four combinations of the two operands.
	h.check("intersects: neither operand Matte -> box",
		not Ink.hits_per_pixel(Ink.COPY, BITMAP))
	h.check("intersects: a Matte *bitmap* is the operand that qualifies",
		Ink.hits_per_pixel(Ink.MATTE, BITMAP))
	# The asymmetry, stated as its own check because it is the one a later reader
	# is most likely to tidy away: the reference chooses `isMatteBoxIntersect` off
	# the **second** operand alone, and only-the-first-matte is box-on-box.
	h.check("intersects: a Matte *shape member* does not qualify",
		not Ink.hits_per_pixel(Ink.MATTE, SHAPE))

	# `within`'s predicate is the other one, and the difference is the point.
	h.check("within: a Matte record on a cast-member sprite qualifies",
		Ink.mattes_for_within(Ink.MATTE, TYPE_CAST_MEMBER))
	h.check("within: a QuickDraw shape *sprite* never does, Matte or not",
		not Ink.mattes_for_within(Ink.MATTE, TYPE_QD_RECT))
	h.check("within: a non-Matte ink never does",
		not Ink.mattes_for_within(Ink.COPY, TYPE_CAST_MEMBER))
	# The two predicates disagree on exactly one thing, and this is it. A shape
	# *member* on a cast-member sprite record is compared per pixel by `within` and
	# as a box by `intersects`. Asserting the disagreement rather than each side
	# separately is what makes a future collapse of the two go red.
	h.check("the two predicates disagree on a Matte shape member, as the reference does",
		Ink.mattes_for_within(Ink.MATTE, TYPE_CAST_MEMBER)
			and not Ink.hits_per_pixel(Ink.MATTE, SHAPE))
	h.complete(name)


## The three scans, on masks this file builds, with the box answer beside each.
func _scans(h: Harness) -> void:
	var name := "what each matte arm answers where a box says yes"
	h.begin(name)

	# Two 4x4 sprites whose boxes overlap in a 2x2 corner. Sprite A has artwork
	# only in its top-left pixel, B only in its bottom-right -- so the overlap
	# contains artwork from neither.
	var rect_a := Rect2(0, 0, 4, 4)
	var rect_b := Rect2(2, 2, 4, 4)
	var a_corner := _mask(4, 4, [Vector2i(0, 0)])
	var b_corner := _mask(4, 4, [Vector2i(3, 3)])
	var plain := {}

	# The pairing this file exists for: the box test says yes on every one of the
	# negative cases below, so a scan that answered false unconditionally could not
	# pass them.
	h.check("the two rects overlap, so the box test would answer yes",
		rect_a.intersects(rect_b))

	h.check("matte-on-matte clears where neither operand has artwork in the overlap",
		not Collision.matte_intersect(a_corner, rect_a, {}, b_corner, rect_b, {}))
	# Artwork in the overlap for both: the 2x2 at (2,2)-(3,3) of A and (0,0)-(1,1)
	# of B, which are the same stage pixels.
	var a_middle := _mask(4, 4, [Vector2i(2, 2)])
	var b_origin := _mask(4, 4, [Vector2i(0, 0)])
	h.check("matte-on-matte answers yes on one shared artwork pixel",
		Collision.matte_intersect(a_middle, rect_a, {}, b_origin, rect_b, {}))
	h.check("matte-on-matte needs *both*: one operand's pixel alone is not a hit",
		not Collision.matte_intersect(a_middle, rect_a, {}, b_corner, rect_b, {}))

	# box-on-matte ignores the first operand's pixels entirely, and that is the
	# whole of the third arm. Handed a first operand whose artwork is nowhere near
	# the overlap, it must still answer yes off the second operand's pixels.
	h.check("box-on-matte answers off the second operand's pixels alone",
		Collision.box_matte_intersect(rect_a, b_origin, rect_b, {}))
	h.check("box-on-matte clears where the second operand's artwork misses the box",
		not Collision.box_matte_intersect(rect_a, b_corner, rect_b, {}))

	# `within`: the second operand is the container, and the scan looks for a pixel
	# the first has and the second does not.
	var outer := Rect2(0, 0, 6, 6)
	var inner := Rect2(2, 2, 2, 2)
	h.check("the inner rect is enclosed, so the box test would answer yes",
		outer.encloses(inner))
	var solid_inner := _mask(2, 2, [Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1)])
	var solid_outer := _mask(6, 6, _all(6, 6))
	h.check("matte-within answers yes where the container's artwork covers it",
		Collision.matte_within(solid_inner, inner, {}, solid_outer, outer, {}))
	# One hole in the container, exactly under one of the inner sprite's pixels.
	var holed_outer := _mask(6, 6, _all(6, 6, [Vector2i(2, 2)]))
	h.check("matte-within clears on a single hole under the inner artwork",
		not Collision.matte_within(solid_inner, inner, {}, holed_outer, outer, {}))
	# The inner sprite having no artwork where the hole is: still within.
	var sparse_inner := _mask(2, 2, [Vector2i(1, 1)])
	h.check("matte-within ignores a hole the inner sprite has no pixel over",
		Collision.matte_within(sparse_inner, inner, {}, holed_outer, outer, {}))

	# **The deviation, asserted so that it cannot be changed silently.** The
	# reference's three helpers each `return false` when a matte they wanted is
	# null; here a null matte reads as solid and the arm degrades to the box
	# answer. The reasoning is at the head of `scenes/preview/collision.gd`; the
	# measurement is that no pair in any shipped root reaches it.
	h.check("a null matte keeps the box answer rather than rejecting outright",
		Collision.matte_intersect(plain, rect_a, {}, b_corner, rect_b, {})
			and Collision.box_matte_intersect(rect_a, plain, rect_b, {})
			and Collision.matte_within(plain, inner, {}, solid_outer, outer, {}))

	# Flip, which the scan gets from the same `local_point` the mouse does. A
	# horizontally flipped first operand has its single pixel mirrored to the
	# opposite edge, so the shared-pixel case above must invert.
	h.check("a flipped operand's artwork is mirrored for the scan too",
		not Collision.matte_intersect(a_middle, rect_a, {"flip_h": true},
			b_origin, rect_b, {}))
	h.complete(name)


## How many frames of a score to walk looking for a live pair.
##
## Capped, and the cap named in the message when nothing is found, because the
## *slow* path here is the one that asserts nothing: a root with no matte pair at
## all would otherwise walk every frame of the score to say so. Both `gate.sh`
## entries land inside the first forty.
const FRAME_BUDGET := 400


## The loaded title's own operands, or a statement that it has none.
##
## **The one thing this half is for is the refuting direction.** Every other check
## in this file reaches `Collision`'s functions or `director_ink.gd`'s predicates
## directly, and would pass unchanged against a `refine` that answered `true`
## always -- so would all eleven of the minigame entries, and so would
## `sprite_collision`, whose `sprite N within N` and `intersects N N` are both
## satisfied by always-true. What is left unproved by all of them is the *path*:
## `preview_lingo_host.gd`'s arm -> `lingo_matte_collision` -> `refine` producing a
## **0 where the box test says yes.** That is the claim the change is about, and it
## is the one this looks for first.
func _live(h: Harness, args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		for i in 12:
			await process_frame
	preview.set("_paused", true)

	var name := "a real pair of this movie's channels, through the operator"
	h.begin(name)
	var found := _matte_pair(preview)
	if found.is_empty():
		# Says so and asserts nothing. `--root piposh-dream --boot hatul3.dir` is
		# the entry that does have one; `GATE_ROOT` may not, and a check invented
		# to fill the gap would be a check about this harness.
		print("")
		print("no frame in the first %d of %s puts two overlapping channels on a"
			% [FRAME_BUDGET, str(preview.call("movie_name"))])
		print("matte arm -- nothing asserted here.")
		h.complete(name)
		preview.queue_free()
		return

	preview.set("_index", int(found["frame"]))
	await process_frame
	var one := int(found["first"])
	var two := int(found["second"])
	print("")
	print("live pair: %s frame %d, sprite %d intersects %d  -> %s%s" % [
		str(preview.call("movie_name")), int(found["frame"]), one, two,
		str(found["arm"]),
		"   REFUTES THE BOX" if bool(found["refutes"]) else ""])
	var host = preview.get("_host")
	# The operator, not a rect comparison and not `Collision` again: what is
	# asserted is the answer a script gets, through the arm in
	# `preview_lingo_host.gd` that this change rewired.
	var answer := int(host.call("call_builtin", "intersects", [one, two]))
	var rect_one: Rect2 = preview.call("lingo_sprite_rect", one)
	var rect_two: Rect2 = preview.call("lingo_sprite_rect", two)
	var box := rect_one.intersects(rect_two)
	h.check("the arm is a matte one, so the ink reached the operator",
		str(found["arm"]) != Collision.ARM_BOX, str(found["arm"]))
	h.check("the box test says yes on this pair", box)
	# The plumbing, asserted even when the refuting direction is unwitnessed: the
	# answer a script gets and the arm's own verdict must be the same boolean, or
	# the host arm is dropping one of them.
	h.check("the operator's answer is the arm's verdict, not the box's",
		(answer == 1) == Collision.refine(preview, one, two, false),
		"operator %d, arm %s" % [answer, str(Collision.refine(preview, one, two, false))])
	if bool(found["refutes"]):
		# **The check the whole change rests on.** The box says these two overlap
		# and the matte arm says they do not, so the operator must answer 0 -- which
		# no other check in this repository can distinguish from always-true.
		h.check("a matte arm that clears makes the operator answer 0 where the box said yes",
			answer == 0, "%d" % answer)
	else:
		# Not a silent pass. The pair found runs on a matte arm and agrees with the
		# box on this frame, so the plumbing is asserted and the refutation is not,
		# and that distinction is the point of saying it out loud.
		print("this title's matte pairs all agree with the box in the first %d frames;"
			% FRAME_BUDGET)
		print("the refuting direction is unwitnessed here and asserted nowhere else.")
	h.complete(name)
	preview.queue_free()


## A frame where two occupied channels overlap and take a matte arm, preferring
## one where the matte arm **disagrees** with the box.
##
## Walks the whole budget looking for a disagreement and only falls back to the
## first agreeing pair, rather than returning the first matte pair it sees: an
## agreeing pair proves the arm ran and a disagreeing one proves what it did.
func _matte_pair(preview: Node) -> Dictionary:
	var score = preview.get("_score")
	if score == null:
		return {}
	var fallback: Dictionary = {}
	# **No awaited frame per score frame.** The preview is paused, so nothing
	# recomputes between reads and `frame_sprites` answers off `_index` directly --
	# and awaiting once per frame across the budget to find a pair in the first few
	# would cost minutes for nothing. The awaited frame comes once, in the caller,
	# after the frame is chosen.
	for index in range(0, mini(int(score.get("frame_count")), FRAME_BUDGET)):
		preview.set("_index", index)
		var sprites: Array = preview.call("frame_sprites")
		for a in sprites:
			for b in sprites:
				var one: Dictionary = preview.call("_effective", a, true)
				var two: Dictionary = preview.call("_effective", b, true)
				if one.is_empty() or two.is_empty():
					continue
				if int(one["channel"]) == int(two["channel"]):
					continue
				var arm: String = Collision.arm(preview, one, two, false)
				if arm == Collision.ARM_BOX:
					continue
				var rect_one: Rect2 = preview.call("_sprite_rect", one)
				var rect_two: Rect2 = preview.call("_sprite_rect", two)
				if rect_one.size == Vector2.ZERO or rect_two.size == Vector2.ZERO:
					continue
				if not rect_one.intersects(rect_two):
					continue
				var refutes := not Collision.refine(
					preview, int(one["channel"]), int(two["channel"]), false)
				var hit := {
					"frame": index, "first": int(one["channel"]),
					"second": int(two["channel"]), "arm": arm, "refutes": refutes,
				}
				if refutes:
					return hit
				if fallback.is_empty():
					fallback = hit
	return fallback


## A `_matte_mask` result with artwork at exactly the listed pixels.
##
## Built the way the engine builds it -- an Image through `SpriteArt.matte_mask`
## -- rather than by writing the bytes directly, so the threshold and the row
## order come from the engine and not from this file's reading of it. A mask
## written by hand here would agree with itself for ever.
func _mask(width: int, height: int, opaque: Array) -> Dictionary:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	for p in opaque:
		image.set_pixel((p as Vector2i).x, (p as Vector2i).y, Color(0, 0, 0, 1))
	return {
		"mask": SpriteArt.matte_mask(image), "width": width, "height": height,
	}


## Every pixel of a `width` x `height` grid, less the ones in `excluded`.
func _all(width: int, height: int, excluded: Array = []) -> Array:
	var out: Array = []
	for y in height:
		for x in width:
			var p := Vector2i(x, y)
			if not excluded.has(p):
				out.append(p)
	return out
