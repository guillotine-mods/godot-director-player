extends RefCounted
## §2.7's `intersects` and `within`, past the bounding box: which arm the operands
## take, and the per-pixel scan when it is not the box one.
##
## **The box test is the caller's and stays there.** `preview_lingo_host.gd`'s arm
## answers `first.intersects(second)` / `second.encloses(first)` and only asks this
## module to refine a box answer of *true* — which is the reference's own shape,
## since every matte helper in `channel.cpp` opens by rejecting an empty
## `findIntersectingRect` or a failed `contains`. So this module can never turn a
## box "no" into a "yes", and the two documented rules of that arm — the zero-size
## guard, and that neither operator consults `the visible of sprite` — are
## untouched by anything here.
##
## **Not in `interaction.gd`, deliberately.** That module's header and
## `docs/bugs-closed.md` 43 exist to keep "what the mouse can reach" apart from
## "what the operators measure": the mouse refuses a hidden sprite and these
## operators measure one, which is the whole idiom Piposh 1's cannon is built on.
## The two share the *pixel* machinery (`sprite_art.gd`) and nothing else, and
## putting the arm selection beside the click descent is an invitation to
## re-conflate them.
##
## ## The arms, from `lingo/lingo-code.cpp`
##
## `c_intersects`, three arms, with `sprite2` the **second** operand:
##
##   both operands are Matte bitmaps      `sprite2->isMatteIntersect(sprite1)`
##   only the second is                   `sprite2->isMatteBoxIntersect(sprite1)`
##   anything else (the first alone, ...) `getBbox().intersects(getBbox())`
##
## `c_within`, two:
##
##   both operands Matte and not QD shape `sprite2->isMatteWithin(sprite1)`
##   otherwise                            `getBbox().contains(getBbox())`
##
## The asymmetry is reproduced as written and it is not symmetry lost in
## translation: only-the-first-operand-matte falls all the way back to boxes for
## `intersects`, and the two operators test **different predicates** —
## `_cast->_type == kCastBitmap` against `!isQDShape()`. `director_ink.gd` holds
## those as `hits_per_pixel` and `mattes_for_within` for that reason.
##
## ## The one deliberate deviation: a matte that does not exist
##
## `isMatteIntersect`, `isMatteBoxIntersect` and `isMatteWithin` each end in
## `return false` when a matte they wanted is null, and a matte is null in the
## reference in two ways: the operand's member is not a `kCastBitmap` (`getMatte`
## is called for nothing else), or it is a bitmap whose border has no white to
## flood from, which leaves `_noMatte` set (`castmember/bitmap.cpp:createMatte`).
## **Neither of them answers "no" here.** This port's artwork path does not split
## the same way, so it is worth spelling out as three cases rather than one:
##
## 1. **No artwork at all** -- a film loop, a field, a video, a `vectorShape`
##    Xtra. `_matte_mask` answers `{}` and that side of the test degrades to its
##    box. This is the deviation proper.
## 2. **A bitmap whose border has no white.** `director_ink.gd:key_matte` builds
##    nothing and leaves the image opaque, so the mask is solid and the scan
##    reaches the same answer through the artwork rather than through a fallback.
## 3. **A shape member**, which the reference never mattes at all: here the mask is
##    the shape `director_shape.gd` painted, so the scan runs against the drawn
##    outline. That is neither the reference's `false` nor a box, and it is the
##    nearest reachable thing to `Sprite::getQDMatte` -- which exists
##    (`sprite.cpp:257`) and which the three collision helpers simply never call.
##    An *unfilled* shape draws nothing, and a mask with no artwork is contained in
##    everything and intersects nothing, which is exactly what the reference's own
##    empty-matte *bitmaps* do.
##
## Three reasons for the direction, in the order they carry weight:
##
## 1. The reference's *own other consumer of the same matte* does exactly that.
##    `BitmapCastMember::isWithin` — the mouse's per-pixel test —
##    is `matte ? sample : true` (`castmember/bitmap.cpp:926`). A null matte
##    meaning "solid" there and "collides with nothing" here cannot both be
##    Director.
## 2. `Sprite::getQDMatte` (`sprite.cpp:257`) exists and builds a matte for a
##    QuickDraw shape with Matte ink; the three collision helpers simply never
##    call it. So "a matte-inked shape never collides" is a gap in that engine's
##    collision path rather than a behaviour of Director's.
## 3. `tools/sprite_collision.gd` asserts `sprite N within N` is true, on any
##    title, for a sprite the mouse can reach. The `return false` arm makes that
##    false for every matte-inked non-bitmap — an invariant no Director title
##    could have been authored against.
##
## Measured, by `tools/collision_ink.gd` over all six shipped roots: of the 585
## operand pairs that change arm, **0 reach a null matte by member type.** Every one
## is `matte-on-matte` (411) or `box-on-matte` (314 -- 725 pair/arm combinations
## over 585 pairs, since a pair can take different arms on different frames), and
## both of those demanded a bitmap of the operand whose matte they scan. So the
## deviation is unobservable on this corpus and is here for the model, which is
## the state `AGENTS.md` asks to be said out loud rather than left implicit. The
## other half of it -- a bitmap with no white on its border -- is not statically
## measurable and is unmeasured.

const Ink := preload("res://director/director_ink.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")


## Refine a box answer of true for `sprite first <op> second`.
##
## Returns what the operator should answer. **True is the box answer**, so every
## path this cannot evaluate returns true and leaves the caller's verdict standing
## rather than inventing a "no": a missing record, a member that will not resolve,
## artwork that will not decode. An operator that answered "no" because a decode
## failed would be indistinguishable from one answering the geometry.
static func refine(host, first: int, second: int, want_within: bool) -> bool:
	var one: Dictionary = host.lingo_sprite_record(first)
	var two: Dictionary = host.lingo_sprite_record(second)
	if one.is_empty() or two.is_empty():
		return true
	match arm(host, one, two, want_within):
		ARM_MATTE_WITHIN:
			return matte_within(
				host._matte_mask(one), host._sprite_rect(one), one,
				host._matte_mask(two), host._sprite_rect(two), two)
		ARM_MATTE_ON_MATTE:
			return matte_intersect(
				host._matte_mask(one), host._sprite_rect(one), one,
				host._matte_mask(two), host._sprite_rect(two), two)
		ARM_BOX_ON_MATTE:
			return box_matte_intersect(host._sprite_rect(one),
				host._matte_mask(two), host._sprite_rect(two), two)
	return true


## The four arm names. Strings rather than an enum, for the reason
## `director_ink.gd` gives about its own constants -- an enum does not survive a
## `preload` -- and because they are printed as often as they are compared.
const ARM_BOX := "box"
const ARM_MATTE_ON_MATTE := "matte-on-matte"
const ARM_BOX_ON_MATTE := "box-on-matte"
const ARM_MATTE_WITHIN := "matte-within"


## Which arm a pair of records takes.
##
## **Named rather than inferred**, so that a harness, the debug overlay and the
## operator itself cannot end up with three readings of one decision. That is the
## `hits_per_pixel` failure in `interaction.gd`'s header: the hit test and the
## overlay computed the same predicate separately and drifted, and the tool that
## existed to explain the engine started lying about it.
static func arm(host, one: Dictionary, two: Dictionary, want_within: bool) -> String:
	if want_within:
		# `c_within` tests `!isQDShape()` -- the sprite-type byte, not the cast
		# type. A matte-inked shape *member* on a `kCastMemberSprite` record
		# qualifies here and does not qualify below.
		if Ink.mattes_for_within(int(one["ink"]), int(one.get("sprite_type", 0))) \
				and Ink.mattes_for_within(
					int(two["ink"]), int(two.get("sprite_type", 0))):
			return ARM_MATTE_WITHIN
		return ARM_BOX
	# `c_intersects` tests the cast type, which is `hits_per_pixel` -- the same
	# predicate §4.5's click descent asks, reused rather than restated.
	var one_matte := Ink.hits_per_pixel(int(one["ink"]),
		int((host._table.get_member(int(one["cast_lib"]), int(one["cast_id"]))
			as Dictionary).get("type", 0)))
	var two_matte := Ink.hits_per_pixel(int(two["ink"]),
		int((host._table.get_member(int(two["cast_lib"]), int(two["cast_id"]))
			as Dictionary).get("type", 0)))
	# **Only the second operand decides whether a matte is consulted at all**, and
	# the first-operand-alone case falls all the way back to boxes -- the
	# reference's own comment spells that out ("just S1 matte: do a box-on-box
	# intersection"). It is the arm most likely to be "corrected" into symmetry by
	# a later reader, which is why it is written as a returned name rather than as
	# a fall-through.
	if not two_matte:
		return ARM_BOX
	return ARM_MATTE_ON_MATTE if one_matte else ARM_BOX_ON_MATTE


## `isMatteIntersect`: a stage pixel where **both** operands have artwork.
##
## Public, and taking masks and rects rather than the host, so that
## `tools/collision_arms.gd` can put a hole where it wants one. The three scans
## are the part of this file no corpus can be relied on to exercise in every
## combination, and a scan only ever reached through a real movie is a scan whose
## clearing case is never asserted.
static func matte_intersect(mask_one: Dictionary, rect_one: Rect2, one: Dictionary,
		mask_two: Dictionary, rect_two: Rect2, two: Dictionary) -> bool:
	if mask_one.is_empty() or mask_two.is_empty():
		return true
	var area := overlap(rect_one, rect_two)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2(x, y)
			if _opaque(mask_one, rect_one, one, at) \
					and _opaque(mask_two, rect_two, two, at):
				return true
	return false


## `isMatteBoxIntersect`: a stage pixel inside the first operand's **box** where
## the second has artwork.
##
## The first operand's pixels are not consulted at all -- it is handed in as a
## rect and nothing else, which is what makes this a third arm rather than a
## shortcut through the one above.
static func box_matte_intersect(rect_one: Rect2, mask_two: Dictionary,
		rect_two: Rect2, two: Dictionary) -> bool:
	if mask_two.is_empty():
		return true
	var area := overlap(rect_one, rect_two)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if _opaque(mask_two, rect_two, two, Vector2(x, y)):
				return true
	return false


## `isMatteWithin`: **no** pixel where the first operand has artwork and the
## second does not. The caller has already established that the second's box
## contains the first's, which is `isMatteWithin`'s own opening test, so the scan
## is over the overlap and that is the first operand's rect.
##
## Note the direction: `c_within` pushes `sprite2->isMatteWithin(sprite1)` and the
## reference's comment there reads "this contains channel", so the *second*
## operand is the container. `second.encloses(first)` in the caller says the same.
static func matte_within(mask_one: Dictionary, rect_one: Rect2, one: Dictionary,
		mask_two: Dictionary, rect_two: Rect2, two: Dictionary) -> bool:
	if mask_one.is_empty() or mask_two.is_empty():
		return true
	var area := overlap(rect_one, rect_two)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2(x, y)
			if _opaque(mask_one, rect_one, one, at) \
					and not _opaque(mask_two, rect_two, two, at):
				return false
	return true


## The integer stage pixels two rects share.
##
## `Rect2.intersection` widened to whole pixels, so the scan covers the same
## pixels the renderer painted rather than a half-open range derived twice. Empty
## when the rects only touch, which matches `findIntersectingRect().isEmpty()`.
##
## A `Rect2i` and two `for` loops rather than a list of points: these scans run
## inside a per-tick `repeat` loop in the platformer, and materialising the overlap
## would allocate one `Vector2` per pixel per call *and* lose the early-out the
## two `intersects` arms depend on.
static func overlap(a: Rect2, b: Rect2) -> Rect2i:
	var area := a.intersection(b)
	var left := int(floor(area.position.x))
	var top := int(floor(area.position.y))
	return Rect2i(left, top,
		maxi(0, int(ceil(area.end.x)) - left), maxi(0, int(ceil(area.end.y)) - top))


static func _opaque(mask: Dictionary, rect: Rect2, sprite: Dictionary,
		at: Vector2) -> bool:
	return SpriteArt.mask_opaque(mask["mask"], int(mask["width"]),
		int(mask["height"]), rect, sprite, at)
