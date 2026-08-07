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


## How big the sprite is drawn.
##
## The sprite's own size wins when it states one. That is not an optimisation --
## it is the rule, and the member's natural size is the fallback for a sprite
## that states nothing rather than the default. Reading the member first instead
## makes every resized sprite in a score draw at its original dimensions, which
## is what `tools/drawn_size.gd` exists to keep from happening again.
static func drawn_size(sprite: Dictionary, member: Dictionary) -> Vector2:
	var w := int(sprite.get("width", 0))
	var h := int(sprite.get("height", 0))
	if w > 0 and h > 0:
		return Vector2(w, h)
	return Vector2(int(member.get("width", 0)), int(member.get("height", 0)))


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
static func texture_key(sprite: Dictionary, drawn: Vector2) -> String:
	return "%d:%d:%d:%dx%d:%d:%d" % [
		int(sprite["cast_lib"]), int(sprite["cast_id"]), int(sprite["ink"]),
		int(drawn.x), int(drawn.y), int(sprite.get("back_color", 0)),
		int(sprite.get("fore_color", Ink.INDEX_BLACK)),
	]
