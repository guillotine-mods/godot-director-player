class_name SpriteChannel
extends RefCounted
## One live sprite channel: the runtime instance of a score sprite.
##
## Director keeps an array of channels, not a per-frame list of sprites. The score
## writes a channel when the playhead moves; `puppetSprite N, 1` takes the channel
## away from the score until it is released, and from then on Lingo's writes are
## what the channel holds. Reads, drawing and hit-testing all go through the
## channel, never through the score frame.
##
## ScummVM models this as `Channel` holding a copy of the score's `Sprite`
## (engines/director/channel.cpp, `setClean` / `replaceSprite`). This is the same
## shape: `sprite` is a mutable duplicate of the frame's sprite dictionary, so every
## existing consumer that reads `sprite.get("cast_id")` keeps working while a Lingo
## write actually lands.
##
## Not implemented yet, deliberately: implicit puppeting. Director auto-puppets a
## sprite when a script writes a puppet-able property, which is what makes the write
## survive the next frame on a channel nobody called `puppetSprite` on. ScummVM
## applies it per property in `setTheSprite` and the set is not uniform, so it needs
## reading against the source before this port guesses. Every channel this game
## drives from Lingo is puppeted explicitly by its hub's `init all`
## (`puppetSprite(30, 1)`, and 103-110 for the inventory), so nothing in the current
## paths depends on it. See docs/SCUMMVM_REFERENCE.md.

## Which channel this is. Held separately from `sprite`, so an existing-but-empty
## channel stays empty: a script reading `the visible of sprite 12` must not bring a
## phantom sprite into being that the renderer then tries to draw.
var number: int = 0
## The score sprite for this channel, duplicated so writes are local. Empty when the
## channel holds nothing.
var sprite: Dictionary = {}
## True once `puppetSprite N, 1` has been seen. The score stops overwriting.
var puppet: bool = false
## `the visible of sprite N`. Survives frame entry, because the original treats it as
## game state: a room's frame handler sets it from the inventory on every step.
var visible: bool = true
## `the moveableSprite of sprite N`, `the constraint of sprite N`, and the cursor
## pair. Recorded so reads round-trip; nothing consumes them yet.
var moveable: bool = false
var constraint: int = 0
var cursor: Variant = 0

## Film-loop playback cursor, per channel, so a member change restarts the loop.
var loop_frame: int = 0
var loop_cast_lib: int = -1
var loop_cast_id: int = -1
var loop_score_frame: int = -1


func is_empty() -> bool:
	return sprite.is_empty()


func replace_from_score(score_sprite: Dictionary) -> void:
	## Director's per-frame reconcile. Only for non-puppeted channels: a puppeted
	## channel keeps whatever the script last wrote.
	if puppet:
		return
	sprite = score_sprite.duplicate(true)


func clear_score() -> void:
	## The channel is absent from the incoming frame. A puppeted channel survives,
	## because the script owns it and the score has nothing to say.
	if puppet:
		return
	sprite = {}


func release_puppet() -> void:
	## `puppetSprite N, 0`. The score takes the channel back on the next reconcile;
	## until then the channel keeps what it has, which is what Director does.
	puppet = false


func loc() -> Vector2:
	if sprite.is_empty():
		return Vector2.ZERO
	return Vector2(
		float(sprite.get("loc_h", sprite.get("x", 0))),
		float(sprite.get("loc_v", sprite.get("y", 0))),
	)


func set_loc(h: float, v: float) -> void:
	## `set the locH/locV of sprite N`. The bounding box moves with the registration
	## point rather than being recentred on it: the score records both, and their
	## difference is this member's own registration offset. Recentring would shift
	## every off-centre sprite the first time a script nudged it.
	if sprite.is_empty():
		return
	var here := loc()
	sprite["x"] = float(sprite.get("x", 0)) + (h - here.x)
	sprite["y"] = float(sprite.get("y", 0)) + (v - here.y)
	sprite["loc_h"] = h
	sprite["loc_v"] = v


func set_member(cast_lib: int, cast_id: int, member: Dictionary = {}) -> void:
	## `set the memberNum of sprite N`. Director resizes the sprite to the new
	## member and re-anchors it on the member's registration point, which is what
	## makes a walk cycle of unequal frames hold still. Without member dimensions
	## the rect is left alone, so the caller can pass {} when the member is unknown.
	##
	## A stretched sprite is the exception: its rect is the author's, not the
	## member's, so the new member is scaled into the rect it already has. That is
	## the same distinction `RenderModelLoader._resolve_sprite_rects` applies to the
	## score's own sprites.
	var stretched := bool(sprite.get("stretch", false))
	if sprite.is_empty():
		sprite = {"channel": number}
	sprite["cast_lib"] = cast_lib
	sprite["cast_id"] = cast_id
	if member.is_empty():
		return
	var w := float(member.get("width", 0))
	var h := float(member.get("height", 0))
	if w <= 0.0 or h <= 0.0:
		return
	if not stretched:
		var here := loc()
		sprite["width"] = w
		sprite["height"] = h
		sprite["x"] = here.x - float(member.get("reg_offset_x", w * 0.5))
		sprite["y"] = here.y - float(member.get("reg_offset_y", h * 0.5))
	# The member changed, so any film loop on this channel starts again.
	loop_frame = 0
	loop_cast_lib = -1
	loop_cast_id = -1


func set_size(width: Variant = null, height: Variant = null) -> void:
	if sprite.is_empty():
		return
	if width != null:
		sprite["width"] = float(width)
	if height != null:
		sprite["height"] = float(height)
