extends RefCounted
## Where a sprite lands on the stage, and how big it is drawn.
##
## Pure functions over a sprite record and its cast member. Nothing here reads
## the score, the cast table, the clock or the node -- everything it needs
## arrives as an argument, which is why it is the first thing split out and why
## it is the only module that can be tested without standing up a movie.
##
## The reason placement is worth isolating is that it used to be *two* rules.
## The renderer scaled the registration offset by the drawn size; the hit test
## took it raw. Those agree at natural size and part company the moment a sprite
## is resized, so a stretched sprite was clickable somewhere it was not drawn --
## further off the further it was from natural size. One rule, one place, and
## the divergence cannot come back by editing only half of it.

const Ink := preload("res://director/director_ink.gd")
const Text := preload("res://director/director_text.gd")

## The runtime text a field currently holds, stamped onto the *effective* sprite
## by `director_preview.gd:_effective`, and the style it is drawn in.
##
## **This is the vehicle `bugs.md` 80 was blocked on, and the shape of it is the
## finding.** An expanding field's height is a function of its text, and
## `drawn_size` is static: it is handed a sprite record and a cast member and has
## no route to the host, which is where a script's writes and a player's typing
## live (`_field_text`, `_member_style`). Making it non-static, or handing it the
## host, would put the node into the one module that can be reasoned about
## without standing a movie up -- and every caller in `tools/` that measures a
## score record without a player would lose the ability to ask.
##
## So the runtime state travels *on the record*, stamped once where the record is
## already being assembled. A raw score sprite carries neither key and
## `_field_size` falls back to the member's own authored `STXT` and style, which
## is the right answer for a record nobody has written to and is what keeps
## `drawn_size_stability.gd` and the corpus surveys able to run without a host.
##
## Deliberately **not** `size_from_script` and not `SIZE_COMPUTED`: those two say
## "the answer is already in `width`/`height`, use it", and this says "here is the
## input the answer has to be computed from". A `drawn_size` that could not tell
## the three apart could not be reasoned about, which is the argument
## `SIZE_COMPUTED` above makes for itself.
##
## Neither enters `texture_key`. A field produces no texture at all
## (`text_and_shapes.gd` asserts it), and the drawn size the key already carries
## is what the growth changes.
const FIELD_TEXT := "field_text"
const FIELD_STYLE := "field_style"

## Cast types whose sprite keeps its own width and height on a member swap.
## `sprite.cpp:Sprite::setCast` resets the sprite's dimensions to the member's
## `initialRect` for every type except shape and text -- but only one of those
## two belongs here, and reading the exception list as though it were one rule is
## what put Piposh 1's money in the wrong place (see `drawn_size`).
##
## A **shape** *is* its rect. It has no natural size to fall back to: the member
## says "rounded rectangle", the sprite says how big, and the score's stored rect
## is the only answer there is. Rich text is not here because the reference does
## not except it either -- it takes the default branch.
##
## **An Xtra (type 15) takes the default branch too, and used to reach it with
## nothing to fall back on.** Its rect is not in the specific block the way every
## other type's is -- it is item 12 of the *info* block -- so until
## `director_cast.gd:_apply_xtra_rect` read it, every Xtra member measured 0x0 and
## `drawn_size` below fell through to the score's own rect, which is the residue
## this whole file exists to stop trusting. It also had no registration point, and
## an Xtra's is its rect's origin -- the *centre* of the box for 355 of the 494
## members that carry one across `itamar-magichat` and `piposh-dream`, so a sprite
## naming the 500x230 `jinnycard` was placed and hit-tested 250px off. Neither is
## visible on the stage, because nothing draws an Xtra: they are visible in
## `interaction.gd`'s hit test, which is `stage_rect().has_point()`.
const KEEPS_ITS_OWN_SIZE := [8]  # shape

## "This record's width and height were computed, not read off the disc."
##
## The one thing `drawn_size` below is deciding is whether a rect is *authoring
## residue*, and that question only exists for a record that came out of a score.
## A film-loop child's record is built in
## `film_loop_view.child_sprite` a moment before it is drawn -- its size is the
## member's own natural size scaled by the loop's squeeze (§1.6) -- so there is no
## residue for the stretch flag to be asked about, and asking anyway is what
## `bugs.md` 99 was: the child positions scaled and the children themselves did
## not.
##
## **A separate key from `size_from_script` on purpose**, though `drawn_size`
## honours both in the same breath. That one means "a Lingo write set this"
## (`channel.gd:429`, the `size` kind, `the width of sprite N` and its `height`
## twin) and it has a release rule and a puppet story attached to it. This one
## means "the caller already did the arithmetic". They coincide in what
## `drawn_size` does with them and in nothing else. `bugs.md` 80 made the same
## argument for a third cause, which has since landed as `FIELD_TEXT` above -- a
## field grown by its own laid-out text -- and turned it down as a reader of
## `size_from_script` for precisely this reason: a size that sticks because a
## script wrote it, a size that sticks because somebody computed it, and an input
## a size has to be computed *from* are three different facts, and a `drawn_size`
## that cannot tell them apart cannot be reasoned about later.
##
## It deliberately does **not** enter `texture_key`: it changes the drawn size,
## which that key already carries, and not the pixels.
const SIZE_COMPUTED := "size_computed"


## How big the sprite is drawn.
##
## **The member's natural size wins unless the author resized the sprite.** The
## score's stored width and height are the drawn rect only when the sprite's
## stretch flag is set; with it clear they are authoring residue -- whatever the
## channel was last resized to, or the size of a member that used to be there --
## and Director never shows them, because every path that puts a member on a
## channel resets the dimensions to the member's own (`sprite.cpp:setCast`, via
## `channel.cpp:setCast`, with `replaceDims = !stretch`).
##
## This used to read the sprite's own size unconditionally, and that is what
## bugs.md 31 was: art elongated for a run of frames and then correct again.
## `tools/drawn_size_stability.gd` has the measurement. The clearest instance is
## `PIPDATA/WRESTLE.dir` channel 9, where every member of a wrestler's animation
## is written with the rect 556x438 on the two frames its record is rewritten in
## full and with its own size on the third -- 369x303, 375x308, 379x312 in turn.
## A rect that is right in the middle of a span and foreign at its edges is not a
## size anybody authored. `PIPDATA/INVENTOR.dir` shows the same residue moving
## between channels: the 1x1 member `dot` leaves 1x1 behind on channels 10 and 11
## whose members are 92x17 and 78x14, so those sprites drew as nothing at all.
##
## The rule this replaces was settled against `assets/render_model/*/frames.json`
## by `tools/drawn_size.gd`, and that comparison could not settle it: the export
## carries the exporter's own `x`/`y`, derived from the same rect, so agreement
## with it is arithmetic rather than evidence -- and the renderer that drew from
## that export applied `RenderModelLoader._resolve_sprite_rects` on top, which is
## this rule, to 22,806 Piposh 2 records before drawing a frame. The picture
## known to have been right was already the corrected one. That is also why the
## film-loop children in `film_loop_view.child_sprite` behave "the opposite way":
## they never did -- the main score was the odd one out.
##
## Four things keep their stated size: a sprite whose stretch flag is set, a
## sprite a script has resized (`sprite_state.effective` marks it, because
## Director's `setWidth` makes the size stick without touching the flag), a record
## carrying `SIZE_COMPUTED` — a film-loop child, whose rect was computed rather
## than read off a score and so cannot be residue — and a shape, which has no
## natural size to reset to.
##
## **`SIZE_COMPUTED` is tested above the shape and field branches, and that order
## is the load-bearing half of `bugs.md` 99's fix rather than a tidiness.** A
## squeezed loop's field child must be drawn at `natural * scale` like everything
## else inside the loop, and `_field_size`'s `MAX(bbox, initialRect, maxHeight)`
## would take it straight back up to the member's own size — the one answer that
## is certainly wrong for a child of a loop drawn at a quarter size. The two
## degenerate guards above it cannot swallow such a record either: `child_sprite`
## clamps a scaled size to `maxi(1, ...)` in the same branch that sets the marker,
## so a marked record always states at least 1x1.
##
## **A field is not one of them, and used to be.** `setCast` does except text
## from the dimension reset, but that is only the first half of what the
## reference does: the widget then lays the text out and pushes its size *back
## onto the sprite* -- clamped to the member's `initialRect` for a fixed field,
## grown for an expanding one (DIRECTOR_ENGINE.md 1.2). Excepting text from the
## reset without implementing the push left the score's stored rect standing, and
## that is the one value Director never shows: it is residue, the same residue
## the doc above describes for bitmaps.
##
## Piposh 1's top bar is what this looked like. `GlobalMoney` is a 102x19 centred
## member, and every room's score records its sprite as 68x32 -- the same 68x32
## three of its neighbours on that bar carry, which is how you can tell it is
## residue and not a size anyone authored. Centring 14pt text in a box 34px too
## narrow put the amount 17px left of where Director puts it, in 33,686 of that
## game's 82,323 field sprite records. `GlobalTime` beside it was never wrong,
## because its member is 68 wide and the residue agrees with it by accident.
##
## Measured before the change, over all six roots and honouring the stretch flag:
## switching a field's box from the score's rect to the member's drops a laid-out
## line in **11 sprite records** in the whole corpus, over 4 (member, box) pairs
## naming just two members -- `save2`, where the line lost is a trailing empty
## one, and `memo21`.
##
## **All four box types are implemented now**, in `_field_size` below: a fixed or
## scrolling field takes `MAX(score rect, initialRect, maxHeight)` and is then
## never touched again, and an `adjust` or `limit` field is grown to the height
## its text lays out to. The second half used to be missing, and what it was
## missing was not the arithmetic but a route to the *runtime* text -- see
## `FIELD_TEXT` above, which is that route and is why the two halves had to land
## in one commit.
##
## One claim that used to stand here was wrong and is worth recording as such: it
## said `CAPROOM.dir`'s memos "mostly carry the stretch flag, so they keep their
## authored box anyway". They do not -- all 112 of the records that move carry
## `stretch=false`, which is exactly why they were being drawn at the member's
## 87px instead of the 134px the score asked for.
static func drawn_size(sprite: Dictionary, member: Dictionary) -> Vector2:
	var w := int(sprite.get("width", 0))
	var h := int(sprite.get("height", 0))
	var natural := Vector2(int(member.get("width", 0)), int(member.get("height", 0)))
	# Nothing to fall back to: a member this cast does not describe, or one whose
	# geometry did not decode. The sprite's rect is all there is.
	if natural.x <= 0.0 or natural.y <= 0.0:
		return Vector2(w, h)
	if w <= 0 or h <= 0:
		return natural
	if bool(sprite.get("stretch", false)) or bool(sprite.get("size_from_script", false)) \
			or bool(sprite.get(SIZE_COMPUTED, false)):
		return Vector2(w, h)
	if KEEPS_ITS_OWN_SIZE.has(int(member.get("type", 0))):
		return Vector2(w, h)
	if int(member.get("type", 0)) == TEXT:
		return _field_size(sprite, member, natural)
	return natural


## Cast type of a field. Named because three rules below turn on it.
const TEXT := 3

## `the boxType of member`, from byte 3 of the field's specific block
## (`director_cast.gd:376` reads it as `text_type`). The names are Director's.
const BOX_ADJUST := 0
const BOX_SCROLL := 1
const BOX_FIXED := 2
const BOX_LIMIT := 3


## A field's drawn size, which is the widget's size and not the member's.
##
## `setCast` skips text when it resets a sprite's dimensions to the member's
## `initialRect` -- `sprite.cpp:627-632` breaks on `kCastShape` and `kCastText`
## alike -- so for a field the score's stored rect survives as the *bbox*, and
## `castmember/text.cpp:createWidget` then combines it with the member's own rect
## according to the author's box type. `channel.cpp:774-779` writes the widget's
## dimensions back onto the sprite unconditionally for text, which is why the
## widget's size is the drawn size and the sprite's own rect is only an input to
## it. Cited at ScummVM 805f259a.
##
##   adjust          MIN(bbox, initialRect), then the widget may expand
##   fixed/scrolling MAX(bbox, MAX(initialRect, maxHeight)), and never expands
##   limit           bbox unchanged, then the widget may expand
##
## **All four arms are implemented now.** The two that expand were waiting on a
## way to reach the runtime text, which `FIELD_TEXT` above is; what follows is
## what they do with it, and where it departs from the reference's literal
## arithmetic and why.
##
## An expanding field's height is **the greater of the member's own rect and the
## height its text lays out to** at the member's width. That is the write-back:
## `createWidget` builds MacText from a starting box it "can expand" but "can't
## shrink" below, `createWindowOrWidget` hands it a `maxWidth` of the member's
## width to wrap inside, and `channel.cpp:774-779` copies the widget's dimensions
## onto the sprite -- re-applied every frame by `channel.cpp:585-591`, which
## `getFixDims()` limits to exactly these two box types. So the sprite's height
## for an expanding field is *derived from the text*, and the port derives it
## here on demand instead of storing it.
##
## **Derived rather than stored, and that is the load-bearing decision.** A
## laid-out size written back into the sprite record becomes the next frame's
## input: `limit` leaves the bbox alone, so a stored height would be laid out
## again, grow again, and diverge without bound, and `adjust`'s MIN would ratchet
## a field down to residue and never let it out. Every input here -- the member's
## rect, its text or the stamped override, the style -- is stable across a
## re-read, so asking twice returns the same answer by construction.
## `tools/field_expands.gd` asserts exactly that, because "by construction" is
## what everyone says right up until the frame it oscillates.
##
## **The width is the member's, not `MIN(bbox, initialRect)`, and the departure is
## measured.** Director's Adjust to Fit grows a field *vertically*; the author's
## width is the wrapping width and the reference agrees, handing MacText the
## member's width as its `maxWidth`. Taking `dims` literally instead would make
## the drawn width the score's stored rect wherever that is narrower --
## authoring residue, the one value Director never shows, and precisely the
## regression `9d1b23d2` fixed. Measured by `tools/field_box_survey.gd` over all
## eight roots: it would narrow **33,767 records in `piposh`, 33,764 in
## `piposh-en`, 33,764 in `piposh-ru`, 1,679 in `rating` and 1,603 in `piposh2`**,
## and `GlobalMoney` -- 102x19, recorded 68x32 by every room -- is the clearest of
## them, its amount centred in a box 34px too narrow. The same run says the
## upside is real and small: with the *authored* text, 1,943 records of 333,217
## grow, over 24 members, the largest `rating`'s `MANAEGOZ.dir` `save2` at
## 119x19 -> 119x57. The rest of the value is at runtime, where a script's write
## or a player's typing is not in any score.
##
## The height floor is the member's rect for the same reason, rather than
## `MIN(bbox, initialRect)` for `adjust` or the bare bbox for `limit`: both read
## the score's residue, and both would make the drawn height follow a number that
## changes mid-run, which is the pulse `tools/drawn_size_stability.gd` exists to
## catch. Cost of the departure, from the same run: **52 records** whose bbox is
## shorter than the member (44 in `piposh2`, 8 in `piposh-dream`) keep the
## member's height where the reference would start them lower -- and since the
## text still fits either way, none of them clips.
##
## Fixed and scrolling carry no such coupling. `createWidget` passes
## `fixDims = (_textType == kTextTypeFixed || _textType == kTextTypeScrolling)`,
## and `channel.cpp:585-591` only re-pushes the widget's dimensions when
## `!getFixDims()` -- so a fixed field's size is decided once, by that MAX, and
## nothing grows it afterwards. The MAX can only ever return at least the member's
## own rect, so it cannot reintroduce a residue *smaller* than the member the way
## the MIN can. Measured over all six roots it moves **112 records in `piposh` and
## 112 in `piposh-en`, and shrinks none anywhere**: `CAPROOM.dir`'s `memo11`
## through `memo55` are recorded 290x134 against a 278x87 member with `maxHeight`
## 87, so the port drew them at 87px -- *below the score's own rect*, which the
## reference never does for text -- and clipped the sixth line of every memo.
static func _field_size(sprite: Dictionary, member: Dictionary, natural: Vector2) -> Vector2:
	var box := int(member.get("text_type", BOX_ADJUST))
	if box != BOX_FIXED and box != BOX_SCROLL:
		return Vector2(natural.x,
			maxf(natural.y, laid_out_height(sprite, member, natural.x)))
	var rect: Dictionary = member.get("initial_rect", {})
	if rect.is_empty():
		return natural
	var own := Vector2(
		float(int(rect.get("right", 0)) - int(rect.get("left", 0))),
		float(int(rect.get("bottom", 0)) - int(rect.get("top", 0)))
	)
	if own.x <= 0.0 or own.y <= 0.0:
		return natural
	return Vector2(
		maxf(float(int(sprite.get("width", 0))), own.x),
		maxf(float(int(sprite.get("height", 0))), maxf(own.y, float(int(member.get("max_height", 0)))))
	)


## How tall this field's text lays out at `width`, with nothing clipping it.
##
## **The runtime text if the record carries one, the member's authored `STXT`
## otherwise**, and the fallback is the half that keeps this module honest. A
## sprite that came through `director_preview.gd:_effective` has been stamped with
## what a script or the player put in the field; a raw score record read straight
## off a container by a survey has not, and its member's own text is the correct
## answer for it rather than a degraded one. Neither caller has to know which it
## is, and no caller has to hold a player to ask.
##
## The style travels with the text for the same reason: `set the textSize of
## member "x" to 24` re-derives the line height (`text_art.gd:style_for`), so a
## height computed from the authored 12pt run would be half the box the doubled
## text needs. Absent the stamp it is the member's own run.
##
## Zero for a field with no text, which lets the caller's `maxf` against the
## member's rect stand -- Director does the same thing from the other end, giving
## an empty adjust-to-fit member a one-line rect at load
## (`castmember/text.cpp:291-292`).
static func laid_out_height(sprite: Dictionary, member: Dictionary, width: float) -> float:
	var text := str(sprite.get(FIELD_TEXT, member.get("text", "")))
	if text == "":
		return 0.0
	var style: Dictionary = sprite.get(FIELD_STYLE, {}) if \
		sprite.get(FIELD_STYLE) is Dictionary else {}
	if style.is_empty():
		style = Text.style_of(member)
	return Text.laid_out_height(width, text, style)


## The registration offset, scaled into the size the sprite is actually drawn at.
##
## The offset is authored against the member's natural dimensions, so a sprite
## drawn at another size has to scale it or the artwork slides off its own
## anchor by the difference.
static func scaled_reg(member: Dictionary, drawn: Vector2) -> Vector2:
	var width := maxf(float(member.get("width", 1)), 1.0)
	var height := maxf(float(member.get("height", 1)), 1.0)
	var reg := Vector2(
		float(member.get("reg_offset_x", 0)),
		float(member.get("reg_offset_y", 0))
	)
	if drawn.x <= 0.0 or drawn.y <= 0.0:
		return reg
	return Vector2(reg.x * drawn.x / width, reg.y * drawn.y / height)


## Where a sprite is on the stage. The single placement rule, used by the
## renderer, the hit test, `rollOver` and the debug boxes alike.
static func stage_rect(sprite: Dictionary, member: Dictionary) -> Rect2:
	var size := drawn_size(sprite, member)
	var reg := scaled_reg(member, size)
	return Rect2(Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - reg, size)


## The cache key for a sprite's decoded artwork.
##
## Everything that changes the pixels belongs in it. The drawn size does, because
## one member legitimately appears at several sizes in the same movie and a key
## that omits it hands the second appearance the first one's pixels. So does the
## back colour, because it is what Background Transparent keys against -- two
## sprites sharing a member and naming different papers key differently.
##
## The blend amount deliberately does *not*: blending is applied as a draw-time
## modulate rather than baked into the image, so one decode serves every alpha.
## So does the fore colour, for two reasons that arrived together: it is what
## colourisation repaints an image's black pixels, and it is the colour a shape's
## primitives paint with. Without it the second sprite to share a member gets the
## first one's colour -- and this game recolours one 60x23 shape through several
## colours across 48,570 sprite records, so the omission would be visible
## everywhere the same hotspot is drawn twice.
##
## **The has-blend *flag* does belong in it, which is not the same claim as the
## amount.** The amount only scales a draw-time modulate; the flag changes which
## pixels survive the decode, because Director mattes a Copy sprite that carries it
## (`director_ink.gd:key_for`). Two sprites naming one member at one size, one with
## the flag and one without, therefore want two different images out of this cache.
## `BATZEGOZ.dir` is a live instance rather than a hypothetical: members `1:20` and
## `1:23` carry the flag while `1:21` and `1:22` do not, all four are baked lines of
## the same dialogue balloon, and all four are drawn Copy. Omit the flag and
## whichever decodes first decides how the others look.
static func texture_key(sprite: Dictionary, drawn: Vector2) -> String:
	return "%d:%d:%d:%dx%d:%d:%d:%d%s%s" % [
		int(sprite["cast_lib"]), int(sprite["cast_id"]), int(sprite["ink"]),
		int(drawn.x), int(drawn.y), int(sprite.get("back_color", 0)),
		int(sprite.get("fore_color", Ink.INDEX_BLACK)),
		1 if bool(sprite.get("has_blend", false)) else 0,
		_rgb_key(sprite, Ink.FORE_RGB_KEY), _rgb_key(sprite, Ink.BACK_RGB_KEY),
	]


## The true-colour half of the key, or nothing when the record has none.
##
## The two index bytes above are **not** enough on their own once true colours
## exist, and the collision is not a corner case: a true colour's red component
## *is* the byte the index reading uses, so `(0,0,0)` fore and palette index 0
## produce the same character in the key while naming black and white
## respectively. Empty for an indexed record, so the 7.9 million records in the
## corpus that state no true colour keep exactly the key they had and nothing
## re-decodes (`bugs.md` 30).
static func _rgb_key(sprite: Dictionary, key: String) -> String:
	if not (sprite.get(key) is Color):
		return ""
	var c: Color = sprite[key]
	return ":%02x%02x%02x" % [c.r8, c.g8, c.b8]
