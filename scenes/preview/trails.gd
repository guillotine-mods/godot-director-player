extends RefCounted
## Trails: sprites that leave what they painted behind them.
##
## **This is where the trails flag stops being a flag and becomes the dirty-rect
## rule**, and the first attempt got it exactly backwards. Painting the layer
## under the frame's sprites is the obvious reading of "the repaint starts at the
## trails channel", and it makes trails invisible in any movie with a backdrop:
## the backdrop is a sprite, it is drawn after the layer, and it covers
## everything a trails sprite ever left. `tools/trails.gd` caught that by reading
## the framebuffer -- every headless check passed while nothing was visible.
##
## What Director actually does is repaint **dirty rectangles only**: fill with
## the stage colour, composite every intersecting channel in order. A region no
## changed sprite touches is not repainted at all, so a mark left there stays on
## screen *over* the backdrop that was under it. So:
##
##   a channel that moved or swapped member dirties both the rectangle it left
##   and the one it arrived at, and the layer is cleared there -- which is how a
##   non-trails sprite wipes a trail it passes over, and how a sprite whose
##   trails were switched off stops leaving marks behind it;
##
##   a **trails** channel does not dirty the rectangle it left (that is the whole
##   feature), so only its new rectangle is cleared before it stamps itself;
##
##   a channel that did not change dirties nothing, which is why a static
##   backdrop does not wipe the stage every frame.
##
## The layer is then drawn *over* the frame. That is right for everything a
## changed sprite has not repainted, and wrong for a sprite that is genuinely in
## front of an old mark and did not move -- it should occlude the mark and does
## not. Closing that means real dirty rects and a persistent composite surface;
## this reproduces the visible behaviour of trails without them.
##
## **Unverified against Director**: 0 of this corpus's 816,318 sprite records set
## the flag, so every check drives it from `the trails of sprite` instead.
##
## The layer lives on the node, because `tools/` reads `_trail_image` by name and
## because `Image` is reassigned to null on a movie change -- which a held
## reference could not do.

const LingoValue := preload("res://lingo/lingo_value.gd")
const Paint := preload("res://director/director_paint.gd")


## Does anything in this frame ask for trails, from the score or from a script?
## Cheap enough to ask once a paint; the alternative is paying for the tracking
## in every movie that never uses the feature.
static func wanted(sprites: Array, overrides: Dictionary) -> bool:
	for over_value in overrides.values():
		var over: Dictionary = over_value
		if over.has("trails") and LingoValue.to_int(over["trails"]) != 0:
			return true
	for sprite_value in sprites:
		var sprite: Dictionary = sprite_value
		if bool(sprite.get("trails", false)):
			return true
	return false


## Update the trail layer for this paint, and put it on the stage.
static func settle(host, placed_now: Dictionary,
		to_stamp: Array[Dictionary]) -> void:
	if host._trail_image != null:
		for channel in host._trail_placed:
			var was: Dictionary = host._trail_placed[channel]
			var now: Dictionary = placed_now.get(channel, {})
			var gone := now.is_empty()
			var moved: bool = gone \
				or Rect2(now["rect"]) != Rect2(was["rect"]) \
				or int(now["member"]) != int(was["member"])
			if not moved:
				continue
			# The one exception in the whole mechanism: a trails channel leaves
			# its old rectangle alone.
			#
			# Decided by the flag the channel carries **now**, not the one it
			# carried when it painted there. Director asks "do I erase where I
			# was?" as part of the update it is doing, so a sprite whose trails
			# were switched off goes back to erasing behind itself immediately,
			# including the mark it left on the move before. A channel that has
			# left the frame has no current flag to ask, and its last one stands.
			if not bool(now.get("trails", was.get("trails", false))):
				erase(host, Rect2(was["rect"]))
			if not gone:
				erase(host, Rect2(now["rect"]))
		# A channel that appeared this paint repaints where it landed.
		for channel in placed_now:
			if not host._trail_placed.has(channel):
				erase(host, Rect2(placed_now[channel]["rect"]))
	for entry in to_stamp:
		stamp(host, entry["image"], entry["at"])
	host._trail_placed = placed_now
	if host._trail_layer == null:
		return
	# One upload per paint rather than one per stamp: a movie with several trails
	# sprites would otherwise push the whole 640x480 layer to the GPU once each.
	if host._trail_dirty:
		host._trail_dirty = false
		host._trail_layer.update(host._trail_image)
	Paint.texture(host, host._trail_layer, Vector2.ZERO)


## Clear a rectangle of the trail layer: the region was repainted, so whatever a
## trails sprite had left there is gone.
static func erase(host, rect: Rect2) -> void:
	if host._trail_image == null:
		return
	var stage: Vector2i = host.STAGE
	var area := Rect2(Vector2.ZERO, Vector2(stage)).intersection(rect)
	if area.size.x < 1.0 or area.size.y < 1.0:
		return
	host._trail_image.fill_rect(Rect2i(area), Color(0, 0, 0, 0))
	host._trail_dirty = true


## Add what a sprite just painted to the trail layer.
##
## `blend_rect` rather than `blit_rect`: the artwork arrives already keyed by its
## ink, so it carries transparency, and a blit would stamp the transparent parts
## as holes punched through everything the sprite passed over. It also clips to
## the layer, which is the stage, so a trails sprite hanging off the edge
## accumulates only the part that was on screen -- the same rule the live paint
## applies.
static func stamp(host, image: Image, at: Vector2) -> void:
	if image == null:
		return
	if host._trail_image == null:
		var stage: Vector2i = host.STAGE
		host._trail_image = Image.create_empty(
			stage.x, stage.y, false, Image.FORMAT_RGBA8)
		host._trail_image.fill(Color(0, 0, 0, 0))
		host._trail_layer = ImageTexture.create_from_image(host._trail_image)
	var source := image
	# `blend_rect` needs both sides in the same format, and a member decoded from
	# an indexed bitmap is not guaranteed to arrive as RGBA8.
	if source.get_format() != Image.FORMAT_RGBA8:
		source = source.duplicate()
		source.convert(Image.FORMAT_RGBA8)
	host._trail_image.blend_rect(
		source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(at.floor())
	)
	host._trail_dirty = true
