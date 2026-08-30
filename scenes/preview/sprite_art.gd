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
const VectorShape := preload("res://director/director_vector_shape.gd")
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
	# A `vectorShape` Xtra is Director's own vector art and this engine draws it;
	# every other Xtra symbol still has no renderer, which is the correct answer
	# for one whose pixels only a native DLL ever produced. See
	# `director/director_vector_shape.gd` for why the two are not the same case.
	var is_vector := type_code == Ink.TYPE_XTRA 		and str(m.get("xtra_symbol", "")).to_lower() == VECTOR_SHAPE_SYMBOL
	if type_code != Ink.TYPE_BITMAP and type_code != Ink.TYPE_SHAPE and not is_vector:
		return null
	var drawn := Geometry.drawn_size(sprite, m)
	var key := Geometry.texture_key(sprite, drawn)
	if textures.has(key):
		return textures[key]

	# A bitmap's indices are numbers in *its own* palette; see
	# `palette_view.gd:table_for_member`, which falls back to system Mac when that
	# palette does not resolve -- not to the stage's table, which is what drew
	# `piposh-dream`'s Piposh grey (`bugs.md` 104).
	# It has to be resolved before the colours below, because the keying compares
	# the paper colour against the pixels this table produced -- resolving the
	# paper through a different table is how a matte stops matching anything.
	if type_code == Ink.TYPE_BITMAP:
		palette = PaletteView.table_for_member(m, table, palette, stage_palette_id)

	textures[key] = null
	# Both colours, resolved once and used by both branches. Director's 8-bit
	# convention puts white at index 0 and black at 255, so the defaults a sprite
	# record carries are fore 255 and back 0 -- **unless the record states a true
	# colour instead**, which is what `Ink.fore_colour`/`back_colour` are for and
	# what this used to get wrong on 113,706 records across the corpus
	# (`bugs.md` 30, `tools/sprite_rgb_colour.gd`).
	var fore := Ink.fore_colour(sprite, palette)
	var back := Ink.back_colour(sprite, palette)

	if is_vector:
		# The member's own box, then the sprite's drawn size -- the same two
		# steps a bitmap takes, so a stretched vector stretches like stretched
		# artwork rather than being re-rasterised at the new size. Director
		# rasterises the vector at its authored size and scales the result too:
		# `the width of sprite` on a vector shape does not re-flatten the path.
		var art: Image = _vector_image(m)
		if art == null:
			return null
		if drawn.x > 0 and drawn.y > 0 				and (int(drawn.x) != art.get_width() or int(drawn.y) != art.get_height()):
			art.resize(int(drawn.x), int(drawn.y), Image.INTERPOLATE_NEAREST)
		hit_images[key] = art
		textures[key] = ImageTexture.create_from_image(art)
		return textures[key]

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
		Ink.KEY_MASK:
			# The refusal is reported, not swallowed. `Channel::getMask` calls
			# `warning()` on each of its three and carries on with no stencil, and
			# a Mask sprite whose mask is missing draws as an ordinary Copy sprite
			# -- which looks exactly like a port that has not implemented Mask ink.
			# Once per cache entry rather than once per repaint, since the keyed
			# image is what is cached.
			var refused := apply_mask_member(sprite, m, image, drawn, table)
			if refused != "":
				push_warning("mask ink on sprite %d:%d: %s" % [lib, id, refused])
	# Colourisation last, and after keying rather than before it, which is not an
	# arbitrary order. A matte is built by flooding *white* in from the border,
	# and Director builds it from the member's own image; repainting the whites
	# first leaves the flood nothing to match and the sprite comes out as a solid
	# rectangle. Keying first also means the pixels this repaints are exactly the
	# ones that survived, so the keyed-out paper cannot come back as a colour.
	# Asked of the record rather than of two indices, because a record whose
	# colour pair is a true colour cannot be judged by an index test: `(0,0,0)`
	# on `(255,255,255)` *is* the default pair, and its two red bytes read as
	# indices are 255 and 0 -- the default pair inverted, so the index test said
	# "colourise" and the line below then swapped the artwork's black and white.
	if Ink.applies_colour_to(sprite, ink):
		Ink.apply_colour(image, fore, back)
	hit_images[key] = image
	textures[key] = ImageTexture.create_from_image(image)
	return textures[key]


## Mask ink (§2.6): stencil this sprite's artwork with the **next cast member**.
##
## Returns "" when the mask was applied and the reason it was not otherwise. The
## reason is a string rather than a bool because all three refusals are real
## Director behaviours with the *same* outcome -- the sprite draws unmasked -- and
## a caller that could not tell them apart could not report which one happened.
## `Channel::getMask` warns and returns null for each:
##
##   the member `castId + 1` is absent
##   it is not a bitmap
##   it is a bitmap of more than one bit
##
## **Unmasked, not invisible**, and that direction is the whole risk of this
## feature. A null mask in the reference means the blit runs with no stencil at
## all, so a mask this port cannot resolve leaves a sprite fully drawn; guessing
## the other way -- treating a missing mask as "mask everything" -- makes the
## sprite disappear, which is the failure `ENGINE_TODO.md` names as the reason
## nobody built this from a coin flip.
##
## `castId + 1` is in the **same cast library**: the reference builds
## `CastMemberID(_castId.member + 1, _castId.castLib)`, so the mask is the next
## member of the sprite's own library and never the first member of the next one.
##
## The mask member's own registration point is what aligns it (`Ink.apply_mask`
## rule 1), and this is the one place the two members' geometry meets: `reg` is
## the sprite's registration point inside its drawn artwork -- scaled with the
## drawn size, because the *sprite* may be stretched -- and the mask's own offset
## is taken raw, because the reference asks `getBbox()` and not `getBbox(w, h)`.
static func apply_mask_member(sprite: Dictionary, member: Dictionary, image: Image,
		drawn: Vector2, table) -> String:
	var lib := int(sprite["cast_lib"])
	var mask_id := int(sprite["cast_id"]) + 1
	var mask: Dictionary = table.get_member(lib, mask_id)
	if mask.is_empty():
		return "mask member %d:%d is not in the cast" % [lib, mask_id]
	if int(mask.get("type", 0)) != Ink.TYPE_BITMAP:
		return "mask member %d:%d is %s, not a bitmap" % [
			lib, mask_id, str(mask.get("type_name", "type%d" % int(mask.get("type", 0))))]
	var f = table.file_for(lib)
	if f == null:
		return "no container for cast library %d" % lib
	var error: Array = []
	var bits := Bitmap.mask_bits(
		mask, f.read_chunk(int(mask.get("data_chunk_id", -1))), error)
	if bits.is_empty():
		return "mask member %d:%d: %s" % [
			lib, mask_id, "" if error.is_empty() else str(error[0])]
	var reg := Geometry.scaled_reg(member, drawn)
	var mask_reg := Vector2(
		float(mask.get("reg_offset_x", 0)), float(mask.get("reg_offset_y", 0)))
	Ink.apply_mask(image, bits, int(mask.get("width", 0)), int(mask.get("height", 0)),
		Vector2i((reg - mask_reg).round()))
	return ""


## The symbol whose payload is artwork. Lower case: the corpus is inconsistent
## about the capital, so nothing matches one case-sensitively.
const VECTOR_SHAPE_SYMBOL := "vectorshape"


## A `vectorShape` member's pixels at its own authored size, or null when the
## payload is not one this reading understands -- in which case the member draws
## nothing, exactly as every Xtra did before, rather than drawing a guess.
static func _vector_image(m: Dictionary) -> Image:
	var payload: PackedByteArray = m.get("xtra_data", PackedByteArray())
	if payload.is_empty():
		return null
	var shape := VectorShape.decode(payload)
	if shape.is_empty():
		return null
	return VectorShape.rasterise(shape)


## Why `texture_for` answered null, in the words a report can print.
##
## **`texture_for` returns null for two entirely different things and nothing
## downstream could tell them apart**, which is `bugs.md` 110. `plane1.dir`'s
## flyer tallied `{"child drawn": 29, "child has no art": 8}` in two independent
## runs, and "no art" reads as artwork that failed — a decode bug, a cast-library
## bug, something to fix. It is neither. All eight are film-loop children whose
## member is **type 15 with the Xtra symbol `vectorShape`**: Director 7 vector
## art, which at the time this port did not draw and `castmember/` in the
## reference still does not. Decoded off the disc:
## `plane1.dir` holds 15 film loops whose children are 11 distinct type-15
## members (88, 103-105, 113-117, 132, 150), every one of them `vectorShape`, and
## no `ccl ` chunk at all — so cast resolution, the closed nested-loop cause and
## every decode path are ruled out by the container itself.
##
## So the fix is not to make eight become zero. `tools/xtra_members.gd` states the
## rule this follows: *drawing nothing for an unregistered Xtra is correct
## behaviour; not knowing what the member is, is not.* The engine now says which,
## and a member type that genuinely failed to decode no longer hides in the same
## bucket as one there was never anything to draw for.
##
## **Eight did become zero in the end, and naming them is what did it.** With the
## symbol in the report it was plain that `vectorShape` was never an unregistered
## Xtra: it is Director's own vector art, and `director/director_vector_shape.gd`
## draws it. The sorting above is unchanged and still load-bearing -- `flash`,
## `animGif` and `VisibleLightOnStageMedia` are still declined by symbol, and a
## bitmap that fails to decode still has to be told apart from them.
##
## Empty when the member is one this renderer draws — in which case `texture_for`
## returning null is a real failure and the caller should say so.
static func decline_reason(sprite: Dictionary, table) -> String:
	var lib := int(sprite.get("cast_lib", 0))
	var id := int(sprite.get("cast_id", 0))
	if table == null:
		return "no cast table"
	var m: Dictionary = table.get_member(lib, id)
	if m.is_empty():
		return "member %d:%d is not in the cast" % [lib, id]
	var type_code := int(m.get("type", 0))
	if type_code == Ink.TYPE_BITMAP or type_code == Ink.TYPE_SHAPE:
		return ""
	# The member's own name for its type, and for an Xtra the symbol that says
	# *which* Xtra — the difference between "we do not draw Xtras" and "we do not
	# draw vectorShape", which is the difference between a rule and a gap.
	var named := str(m.get("type_name", "type%d" % type_code))
	var symbol := str(m.get("xtra_symbol", ""))
	if symbol != "":
		return "%s(%s) has no renderer" % [named, symbol]
	return "%s has no renderer" % named


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
	var local := local_point(image.get_width(), image.get_height(), rect, sprite, at)
	if local.x < 0:
		return false
	return image.get_pixel(local.x, local.y).a > OPAQUE_ALPHA


## Where a stage point lands inside a sprite's artwork, or `(-1, -1)` for outside.
##
## Extracted so that the mouse's point sample above and the collision operators'
## area scan (`mask_opaque`) share **one** copy of the mirroring rule. Two copies
## is how `channel_at` and `draw_hotspots` came to disagree over
## `hits_per_pixel`'s arguments; this is the same shape of hazard one level down,
## and a flip applied in one reader and not the other is invisible except on the
## handful of records that carry the bit.
static func local_point(width: int, height: int, rect: Rect2, sprite: Dictionary,
		at: Vector2) -> Vector2i:
	var local := (at - rect.position).floor()
	if local.x < 0 or local.y < 0 or local.x >= width or local.y >= height:
		return Vector2i(-1, -1)
	# The artwork is mirrored inside the rect when the score asks for a flip
	# (`draw`), so the sample point has to be mirrored with it or the clickable
	# pixels are the mirror image of the visible ones. The *rect* is deliberately
	# not mirrored: flip lives in a rendering attribute byte and leaves the
	# geometry alone.
	if bool(sprite.get("flip_h", false)):
		local.x = width - 1 - local.x
	if bool(sprite.get("flip_v", false)):
		local.y = height - 1 - local.y
	return Vector2i(int(local.x), int(local.y))


## `sample_opaque`, asked of a prebuilt `matte_mask` instead of the Image.
##
## The same question and the same geometry — `local_point` above — with the pixel
## read replaced by a byte index. `mask` must be `matte_mask`'s output for an image
## of `width` x `height`; an empty mask answers false, which is the caller's cue
## that there was nothing to ask.
static func mask_opaque(mask: PackedByteArray, width: int, height: int,
		rect: Rect2, sprite: Dictionary, at: Vector2) -> bool:
	if mask.size() < width * height:
		return false
	var local := local_point(width, height, rect, sprite, at)
	if local.x < 0:
		return false
	return mask[local.y * width + local.x] != 0


## Above what alpha a keyed pixel counts as artwork.
##
## Named because there are now two readers of it — the mouse's point sample above
## and the collision operators' area scan through `matte_mask` — and a threshold
## written twice is a threshold that drifts. §2.7's operators and §4.5's hit test
## must agree on which pixels exist; they may disagree about *whether to ask*, and
## `director_ink.gd` holds that difference in two named predicates.
const OPAQUE_ALPHA := 0.1


## An image's artwork as one byte per pixel, 1 where `sample_opaque` would answer
## true and 0 where it would not.
##
## **Why a mask rather than sampling the image directly.** `intersects` is asked
## inside a per-tick `repeat` loop in `piposh-dream`'s platformer, and the matte
## arms are O(overlap area) — a `get_pixel` call per pixel per operand, in
## GDScript, on every one of those calls. A slow operator does not merely cost
## frames: it changes how many score ticks fit inside a harness's awaited frame,
## and then `west_walk`, `plane_heading` and `frame_reentry` move with no logic
## change and the move gets attributed to the arms. The mask is built once per
## (member, ink, drawn size) — the same key the artwork is cached under — and the
## scan after that is byte indexing.
##
## Built *from* `sample_opaque`'s own threshold rather than from a second reading
## of the pixels, so the mouse and the operators cannot disagree about which
## pixels are artwork. That is the `hits_per_pixel` lesson in `interaction.gd`'s
## header, applied before it could happen again.
##
## Flip is deliberately **not** applied here. The mask is in the image's own
## coordinates and the mirroring belongs to the lookup, exactly as it does in
## `sample_opaque` — a mask built mirrored would then be mirrored twice.
static func matte_mask(image: Image) -> PackedByteArray:
	var out := PackedByteArray()
	if image == null:
		return out
	var w := image.get_width()
	var h := image.get_height()
	out.resize(w * h)
	# The build itself is O(w x h), and a terrain member in `hatul3.dir` is a few
	# hundred thousand pixels -- so on the tick that first touches it, a
	# `get_pixel` per pixel is a few hundred thousand GDScript calls inside the
	# score tick this whole cache exists to keep cheap. `get_data` is the same
	# pixels as one buffer; the alpha byte is the fourth of each group of four.
	if image.get_format() == Image.FORMAT_RGBA8:
		var data := image.get_data()
		var cut := int(OPAQUE_ALPHA * 255.0)
		for i in w * h:
			out[i] = 1 if data[i * 4 + 3] > cut else 0
		return out
	# Any other format, and there are several in this corpus's decode paths, goes
	# the slow way rather than through a conversion: `Image.convert` mutates the
	# Image, and this one is the cached artwork the renderer draws from.
	for y in h:
		var row := y * w
		for x in w:
			out[row + x] = 1 if image.get_pixel(x, y).a > OPAQUE_ALPHA else 0
	return out
