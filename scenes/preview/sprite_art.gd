extends RefCounted
## Turning a cast member into pixels: decode, resize, key, colourise, cache.
##
## Two cast types come through `texture_for`. A bitmap is decoded from its chunk,
## resized to the sprite's drawn size, keyed according to its ink and then
## colourised; a shape is painted from its own geometry and needs none of that,
## because the shape primitives already draw only what they draw. Fields have no
## artwork at all and go through `text_art.gd` instead.
##
## Order is load-bearing in one place and the comments say so where it matters:
## **keying happens before colourisation.** A matte is built by flooding white in
## from the border, so repainting the whites first leaves the flood nothing to
## match and the sprite comes out as a solid rectangle. That was a real bug --
## EXODUS's selection highlight drew as a filled black box.
##
## `draw` adds one thing on top of that: the sprite being pressed draws its
## inverted copy instead of its artwork, which is Director's hilite-on-click. The
## rule and its cache live in `preview/hilite.gd`; only the substitution is here,
## so that flip, blend and placement are written once and apply to both pictures.
##
## The caches stay on the node and are passed in. `tools/` reads `_textures` and
## `_hit_images` by name, and they are dictionaries, so passing them reads as
## owning them. The palette is passed per call rather than held because it is a
## `PackedByteArray` -- a value type -- and a stored copy would go stale the
## moment a palette effect changed it.

const Ink := preload("res://director/director_ink.gd")
const Shape := preload("res://director/director_shape.gd")
const Bitmap := preload("res://director/director_bitmap.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const Hilite := preload("res://scenes/preview/hilite.gd")
const Paint := preload("res://director/director_paint.gd")
const PaletteView := preload("res://scenes/preview/palette_view.gd")


## Decoded once per (member, ink, size, colours) and kept. A member costs
## milliseconds to decode and nothing to draw again, so the cost is paid on
## first appearance.
##
## Populates `hit_images` alongside `textures`: a click lands on a sprite only
## where the sprite actually has pixels, so a keyed-out region passes the click
## through to whatever is behind it.
static func texture_for(sprite: Dictionary, table, palette: PackedByteArray,
		textures: Dictionary, hit_images: Dictionary,
		stage_palette_id: int = PaletteView.NO_STAGE_ID) -> Texture2D:
	var lib := int(sprite["cast_lib"])
	var id := int(sprite["cast_id"])
	var ink := int(sprite["ink"])
	var m: Dictionary = table.get_member(lib, id)
	if m.is_empty():
		return null
	var type_code := int(m.get("type", 0))
	if type_code != Ink.TYPE_BITMAP and type_code != Ink.TYPE_SHAPE:
		return null
	var drawn := Geometry.drawn_size(sprite, m)
	var key := Geometry.texture_key(sprite, drawn)
	if textures.has(key):
		return textures[key]

	# A bitmap's indices are numbers in *its own* palette; see
	# `palette_view.gd:table_for_member`, which falls back to the stage's table.
	# It has to be resolved before the colours below, because the keying compares
	# the paper colour against the pixels this table produced -- resolving the
	# paper through a different table is how a matte stops matching anything.
	if type_code == Ink.TYPE_BITMAP:
		palette = PaletteView.table_for_member(m, table, palette, stage_palette_id)

	textures[key] = null
	# Both colours, resolved through the palette once and used by both branches.
	# Director's 8-bit convention puts white at index 0 and black at 255, so the
	# defaults a sprite record carries are fore 255 and back 0.
	var fore := Ink.colour_of(palette, int(sprite.get("fore_color", Ink.INDEX_BLACK)))
	var back := Ink.colour_of(palette, int(sprite.get("back_color", Ink.INDEX_WHITE)))

	if type_code == Ink.TYPE_SHAPE:
		# A shape has no artwork and no registration point: its sprite rect is the
		# whole of its geometry, and the image comes back already keyed -- or as
		# null, which is the answer for the invisible hotspot rectangles that are
		# 60,100 of this corpus's 60,914 shape sprite records.
		var painted: Image = Shape.render(m, fore, back, Vector2i(drawn))
		if painted == null:
			return null
		hit_images[key] = painted
		textures[key] = ImageTexture.create_from_image(painted)
		return textures[key]

	var f = table.file_for(lib)
	if f == null:
		return null
	var chunk: PackedByteArray = f.read_chunk(int(m.get("data_chunk_id", -1)))
	var error: Array = []
	var image: Image = Bitmap.decode(m, chunk, palette, error)
	if image == null:
		return null
	if drawn.x > 0 and drawn.y > 0 \
			and (int(drawn.x) != image.get_width() or int(drawn.y) != image.get_height()):
		image.resize(int(drawn.x), int(drawn.y), Image.INTERPOLATE_NEAREST)
	# Matte keys only the paper a flood fill can reach from the edge; Background
	# Transparent keys the paper colour everywhere. Treating both as the second
	# punches holes through anything whose artwork encloses white -- the gaps
	# inside and between letters on a text button -- and a click then falls
	# straight through the middle of the button.
	#
	# The paper is the sprite's own backColor, resolved through the palette
	# rather than assumed: Director's 8-bit convention puts white at index 0, and
	# 99.9% of this corpus stores exactly that, but a sprite is free to name
	# another colour and the ink rule is defined against whatever it names.
	#
	# **The member goes in with the sprite, and that is load-bearing rather than
	# tidy.** Director decides the keying from the ink, the thickness byte's blend
	# flag and the member's bit depth together (`Channel::getMask`), so `key_for`
	# cannot answer from an ink number: a Copy sprite carrying the blend flag is
	# mattered, and asking with the ink alone drew `Rating`'s dialogue portraits as
	# opaque white rectangles (`bugs.md` 50).
	match Ink.key_for(sprite, m):
		Ink.KEY_MATTE:
			Ink.key_matte(image)
		Ink.KEY_PAPER:
			Ink.key_paper(image, back)
	# Colourisation last, and after keying rather than before it, which is not an
	# arbitrary order. A matte is built by flooding *white* in from the border,
	# and Director builds it from the member's own image; repainting the whites
	# first leaves the flood nothing to match and the sprite comes out as a solid
	# rectangle. Keying first also means the pixels this repaints are exactly the
	# ones that survived, so the keyed-out paper cannot come back as a colour.
	if Ink.applies_colour(ink, int(sprite.get("fore_color", Ink.INDEX_BLACK)),
			int(sprite.get("back_color", Ink.INDEX_WHITE))):
		Ink.apply_colour(image, fore, back)
	hit_images[key] = image
	textures[key] = ImageTexture.create_from_image(image)
	return textures[key]


## Draw a sprite's artwork at `at`, mirrored if the score asks for a flip.
##
## Flip is bits 0x20 and 0x40 of the thickness byte. Director supports it. The
## reference parses the bits, copies them between sprites and compares them in
## its dirty test, and then **never applies them anywhere in its render path**
## -- searching it for the flip constants finds only their definition -- so it is
## no use as a specification for how flip meets registration or hit testing. The
## reading implemented here is that the image is mirrored *within the sprite's
## rect*, and the rect itself is untouched. That is the only interpretation
## consistent with flip living in a rendering attribute byte rather than in the
## geometry fields, and it means the placement rule and the hit rectangle need no
## change at all. The visible consequence is that an off-centre character appears
## to shift when flipped, because the registration point has effectively moved
## relative to the artwork.
##
## **Unverified against Director.** Neither corpus sets either bit: 0 of Piposh
## 2's 816,318 sprite records and 0 of Piposh 1's 1,886,362, now that the bits
## are read from the byte that holds them rather than from the cast lib's high
## half (`tools/ink_survey.gd`). This is built because Director has it, not
## because anything here asks for it, and `tools/sprite_flip.gd` drives it from a
## synthetic record for that reason.
static func draw(canvas: CanvasItem, texture: Texture2D, at: Vector2,
		sprite: Dictionary, modulate: Color) -> void:
	# Hilite (§4.6) is a *substitution*, not an overlay, and that is the whole
	# reason it lands here rather than as another pass in `stage_paint`. Director
	# inverts the destination through the sprite's matte, and the inverted copy
	# carries the same alpha, so drawing it in place of the artwork inverts the
	# silhouette and nothing else. Painting a rectangle over the top instead is
	# the failure this ordering exists to avoid -- it is the same shape of bug as
	# the solid black box EXODUS's selection highlight drew.
	#
	# It also means flip, blend and the clip below apply to the hilited picture
	# exactly as they do to the plain one, with no second copy of any of them.
	texture = Hilite.artwork(canvas, texture, sprite)
	var flip_h := bool(sprite.get("flip_h", false))
	var flip_v := bool(sprite.get("flip_v", false))
	if not flip_h and not flip_v:
		Paint.texture(canvas, texture, at, modulate)
		return
	# A negative extent asks Godot to mirror. It negates the size and keeps the
	# position, so the rectangle covered is the same one the unflipped draw would
	# have covered and the origin must NOT be moved to the far edge to compensate.
	# Measured, not assumed: a four-pixel texture drawn with `Rect2(4, 0, -4, 1)`
	# lands on x 4..7 reversed, not on x 0..3.
	var size := texture.get_size()
	var rect := Rect2(at, size)
	if flip_h:
		rect.size.x = -size.x
	if flip_v:
		rect.size.y = -size.y
	Paint.texture_rect(canvas, texture, rect, false, modulate)


## Is there a visible pixel of `image` under a stage point?
##
## Rect-only hit-testing hands every click to the topmost sprite whose *box*
## contains the point, and one large mostly-transparent sprite in a high channel
## then swallows the whole screen. Director tests the artwork, not the box.
static func sample_opaque(image: Image, rect: Rect2, sprite: Dictionary,
		at: Vector2) -> bool:
	if image == null:
		return false
	var local := (at - rect.position).floor()
	if local.x < 0 or local.y < 0 \
			or local.x >= image.get_width() or local.y >= image.get_height():
		return false
	# The artwork is mirrored inside the rect when the score asks for a flip
	# (`draw`), so the sample point has to be mirrored with it or the clickable
	# pixels are the mirror image of the visible ones. The *rect* is deliberately
	# not mirrored: flip lives in a rendering attribute byte and leaves the
	# geometry alone.
	if bool(sprite.get("flip_h", false)):
		local.x = image.get_width() - 1 - local.x
	if bool(sprite.get("flip_v", false)):
		local.y = image.get_height() - 1 - local.y
	return image.get_pixel(int(local.x), int(local.y)).a > 0.1
