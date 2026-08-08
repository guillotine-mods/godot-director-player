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
const KEEPS_ITS_OWN_SIZE := [8]  # shape


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
## Three things keep their stated size: a sprite whose stretch flag is set, a
## sprite a script has resized (`sprite_state.effective` marks it, because
## Director's `setWidth` makes the size stick without touching the flag), and a
## shape, which has no natural size to reset to.
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
## one, and `memo21`. What it does not do is the other half of §1.2: a field whose
## text overflows its `initialRect` still clips instead of growing, because the
## laid-out height is not pushed back. `CAPROOM.dir`'s memos are the members that
## would want it, and most of their records carry the stretch flag, so they keep
## their authored box anyway.
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
	if bool(sprite.get("stretch", false)) or bool(sprite.get("size_from_script", false)):
		return Vector2(w, h)
	if KEEPS_ITS_OWN_SIZE.has(int(member.get("type", 0))):
		return Vector2(w, h)
	return natural


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
	return "%d:%d:%d:%dx%d:%d:%d:%d" % [
		int(sprite["cast_lib"]), int(sprite["cast_id"]), int(sprite["ink"]),
		int(drawn.x), int(drawn.y), int(sprite.get("back_color", 0)),
		int(sprite.get("fore_color", Ink.INDEX_BLACK)),
		1 if bool(sprite.get("has_blend", false)) else 0,
	]
