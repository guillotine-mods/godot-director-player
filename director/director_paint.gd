extends RefCounted
## The four drawing primitives the player uses, issued to a canvas item's command
## list rather than through `CanvasItem.draw_*`.
##
## **This file exists so that one paint routine has two entry points.**
## `CanvasItem.draw_rect` and friends assert `drawing`, which Godot raises only
## for the duration of `NOTIFICATION_DRAW`, so a painter written against them can
## be called from `_draw` and from nowhere else. `updateStage` is Director asking
## for a paint *mid-handler* (§9.1, 3,717 sites), and there is no way to make
## Godot deliver a `NOTIFICATION_DRAW` on demand: `queue_redraw()` pushes the
## redraw callback onto the message queue, which is flushed at the end of the
## process frame, and GDScript cannot flush it.
##
## What Godot *does* allow at any time is appending commands to a canvas item's
## own list through `RenderingServer`, and presenting the result with
## `RenderingServer.force_draw()`. `CanvasItem.draw_*` is a thin wrapper over
## exactly those calls, so routing the player's painting through here costs
## nothing and buys `director_preview.gd:repaint_now()`.
##
## The alternative -- a second, cut-down painter for the synchronous path -- is
## the shape `AGENTS.md` warns about: two renderers that agree until they do not.
## Every draw the player makes goes through this file, so the stage a movie sees
## from `updateStage` is the stage it sees from the frame loop, by construction.
##
## `rect` is the only primitive with any code in it. Godot's unfilled `draw_rect`
## draws a *closed polyline centred on the boundary* -- measured, not assumed: a
## `Rect2(4, 4, 40, 20)` outlined at width 1 covers x 3..43 and y 3..23, half a
## pixel outside the rectangle on every side, and an implementation that inset
## the lines instead disagreed with it on 447 pixels of a 100x100 probe. With the
## polyline the same probe differs on one pixel, at one corner of one rectangle.
## The other three primitives already take an RID in their own right --
## `Texture2D.draw`, `Texture2D.draw_rect` and `Font.draw_string` are what
## `CanvasItem` calls -- so they are pass-throughs and cannot drift at all.
##
## ## The second backend, and why it is here rather than in a SubViewport
##
## Every primitive below writes to the canvas item **and**, when the canvas
## carries one, to a `Surface` -- a stage-sized `Image` composed on the CPU. That
## exists for one reason: a transition composes two whole frames of the movie
## (§10), both read back from the framebuffer, and **a build with no screen has no
## framebuffer to read**. Every headless run and therefore every gate run created
## the play, held the playhead for its duration and drew a cut, so nothing
## automated had ever seen this port composite two frames of an actual movie.
##
## `docs/ENGINE_TODO.md` named the fix as "a second `SubViewport` that the same
## painter could target". **That does not work, and it is worth writing down so
## the next reader does not spend the afternoon finding out.** `--headless` is a
## headless *display server*, and the headless display server registers exactly
## one rendering driver -- the dummy one -- whatever `--rendering-driver` says.
## Measured on 4.7.1 with a `SubViewport` at `UPDATE_ALWAYS`, a `Node2D` inside
## it, two rects issued through `RenderingServer` and a `force_draw(false)`:
## `vulkan`, `opengl3` and `d3d12` all answered `texture_2d_get: Parameter "t" is
## null` from `servers/rendering/dummy/storage/texture_storage.h` and returned no
## image. There is nothing to read back because nothing rasterises.
##
## So the offscreen target is a rasteriser rather than a render target, and the
## thing that keeps it from being the "two renderers that agree until they do
## not" `AGENTS.md` warns about is that **it is not a second painter**: it is a
## second backend of the same four calls, fed the same arguments in the same
## order by the same `_paint`. A sprite that reaches the screen reaches the
## surface, by construction, and the only place the two can disagree is inside
## these four functions.
##
## Two disagreements are known and stated at their code: `texture_rect`'s `tile`
## is not tiled, and glyphs are rasterised at 1:1 instead of at the viewport
## oversampling `text` passes the GPU. Both are counted -- `Surface.approximated`
## -- so a caller can say how much of a frame it is unsure of instead of assuming
## none of it.


## The property a canvas item exposes to say "and also draw into this".
##
## Read per primitive rather than held in a `static var`: a static here would be
## engine-wide state on a class every module draws through, and
## `director_preview.gd`'s teardown note (`bugs.md` 112) is about what Godot does
## to a script's statics while `_draw` is still firing. `Object.get` of a name a
## node does not declare answers null without an error, which is exactly the
## behaviour the launcher's canvas items want.
const CAPTURE_PROPERTY := &"paint_capture"


static func capture_of(canvas: CanvasItem):
	if canvas == null:
		return null
	return canvas.get(CAPTURE_PROPERTY)


## Filled or outlined, matching `CanvasItem.draw_rect`'s signature and its pixels.
static func rect(canvas: CanvasItem, box: Rect2, color: Color,
		filled: bool = true, width: float = -1.0) -> void:
	var item: RID = canvas.get_canvas_item()
	var area := box.abs()
	var surface = capture_of(canvas)
	if filled:
		RenderingServer.canvas_item_add_rect(item, area, color, false)
		if surface != null:
			surface.fill(area, color)
		return
	var thickness: float = 1.0 if width < 0.0 else width
	# An outline thicker than the rectangle is a filled rectangle grown by half
	# the line, which is what Godot degenerates to rather than drawing four
	# overlapping lines that cancel.
	if thickness >= area.size.x or thickness >= area.size.y:
		RenderingServer.canvas_item_add_rect(
			item, area.grow(0.5 * thickness), color, false)
		if surface != null:
			surface.fill(area.grow(0.5 * thickness), color)
		return
	var right := area.position.x + area.size.x
	var bottom := area.position.y + area.size.y
	RenderingServer.canvas_item_add_polyline(item, PackedVector2Array([
		area.position,
		Vector2(right, area.position.y),
		Vector2(right, bottom),
		Vector2(area.position.x, bottom),
		area.position,
	]), PackedColorArray([color]), thickness, false)
	if surface != null:
		surface.outline(area, color, thickness)


## Glyphs, at the oversampling Godot's own `_draw` would have chosen.
##
## **The one primitive that is not a pass-through, and it is not optional.**
## `Font.draw_string`'s `oversampling` argument defaults to 0, meaning "work it
## out", and the way it works it out is from the canvas item Godot is currently
## drawing -- which exists only inside `NOTIFICATION_DRAW`. Left at 0 from
## `repaint_now`, glyphs rasterise at a different size and the whole of a field's
## text changes appearance the moment a movie calls `updateStage`: measured at
## 18,499 differing pixels on a `SEA1.dir` frame with one field and 48,220 on a
## `SAVELOAD.dir` frame with nine, against 0 between two ordinary paints.
##
## The value auto resolves to is the **viewport's** scale, not the item's:
## a probe drawing the same string through `_draw` and through the RID inside
## the same `_draw` matched exactly at the viewport transform's 2.25 and differed
## at 1, 2, 3, 4, 4.5 (the item's own scale), 5, 6, 9 and 10.125. So this is not
## a correction factor -- it is the number `_draw` was already using, said out
## loud so that the second entry point can say it too.
static func text(canvas: CanvasItem, font: Font, at: Vector2, value: String,
		alignment: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		size: int = 16, color: Color = Color.WHITE) -> void:
	if font == null:
		return
	font.draw_string(canvas.get_canvas_item(), at, value, alignment, width,
		size, color,
		TextServer.JUSTIFICATION_KASHIDA | TextServer.JUSTIFICATION_WORD_BOUND,
		TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL,
		oversampling(canvas))
	var surface = capture_of(canvas)
	if surface != null:
		surface.glyphs(font, at, value, alignment, width, size, color)


## What `_draw` would pass for `oversampling`, computed rather than deferred.
## Zero outside the tree, which is `Font.draw_string`'s own "work it out" and the
## best answer available when there is no viewport to ask.
static func oversampling(canvas: CanvasItem) -> float:
	if not canvas.is_inside_tree():
		return 0.0
	return canvas.get_viewport_transform().get_scale().x


static func texture(canvas: CanvasItem, art: Texture2D, at: Vector2,
		modulate: Color = Color.WHITE) -> void:
	if art == null:
		return
	art.draw(canvas.get_canvas_item(), at, modulate)
	var surface = capture_of(canvas)
	if surface != null:
		surface.blit(art, at, modulate)


static func texture_rect(canvas: CanvasItem, art: Texture2D, box: Rect2,
		tile: bool = false, modulate: Color = Color.WHITE) -> void:
	if art == null:
		return
	art.draw_rect(canvas.get_canvas_item(), box, tile, modulate)
	var surface = capture_of(canvas)
	if surface != null:
		surface.blit_rect(art, box, tile, modulate)


## The offscreen half of the painter: the same four primitives, rasterised into
## an `Image` the caller owns.
##
## **Stage pixels, not window pixels.** The framebuffer path crops the letterboxed
## viewport and resizes it down (`director_preview.gd:_grab_stage`) because a
## transition's chunk size, strip count and step distance are all in Director's
## own pixels. A canvas item's *local* space already is those pixels, and every
## primitive above is handed local coordinates, so the surface needs no crop and
## no resize -- which also means it cannot pick up the resampling error the
## framebuffer path's `INTERPOLATE_NEAREST` fallback can.
##
## **Nothing here is a second decision about what to draw.** Every method is the
## last step of a call the GPU backend has already taken, with the arguments it
## took. The clip is the surface's own bounds, which is what `clip_to_stage` sets
## on the canvas item for the stage; a window's surface is its own size and the
## chrome outside local (0,0) falls off both.
class Surface extends RefCounted:
	## The composed frame. Read it through `snapshot()` rather than directly: the
	## next paint overwrites this one in place.
	var image: Image
	## How many primitives this surface drew in a way it knows is not exactly what
	## the GPU drew: a tiled `texture_rect` (nothing in this port passes one) and
	## every string of glyphs, which rasterise at 1:1 rather than at the viewport
	## oversampling. A caller that cares can then say how much of a frame it is
	## unsure of instead of assuming none of it.
	##
	## Not zero in practice, and the number is small: `rating`'s `EGOZROO1.dir`
	## frame 227 -- a room with three lines of Hebrew, the HUD and the SKIP button
	## on it -- reports **3 of 16 primitives**, all three of them text. A frame with
	## no field on it reports 0 outside the debug overlays.
	var approximated := 0
	## Primitives rasterised since `begin()`, so a caller can tell "the capture is
	## black because the frame is black" from "the capture is black because nothing
	## reached it".
	var drawn := 0

	var _size := Vector2i.ZERO
	## One opaque black frame, kept so that clearing is a copy rather than a loop.
	##
	## **Measured, and it is the difference between a usable harness and a slow
	## one.** `Image.fill` walks the image a pixel at a time through
	## `_set_color_at_ofs`; a 640x480 stage is 307,200 of those, and a paint does
	## it twice -- once here and once for the stage colour `_paint` opens with.
	## `set_data` over a pre-built buffer is a memcpy.
	var _blank := PackedByteArray()
	## `"<font rid>:<size>:<page>" -> Image`, the glyph atlas pages this surface has
	## already asked for.
	##
	## **`TextServer.font_get_texture_image` copies the whole page**, which is
	## 256x256 for the fallback font, and a naive rasteriser asks for it once per
	## glyph -- so a frame of `EGOZROO1.dir` with three lines of Hebrew in it copied
	## about four million pixels to draw sixty. Held for the life of the surface
	## rather than one call, because the next paint wants the same pages.
	var _atlases: Dictionary = {}

	func _init(size: Vector2i) -> void:
		_size = Vector2i(maxi(1, size.x), maxi(1, size.y))
		_blank.resize(_size.x * _size.y * 4)
		_blank.fill(0)
		for i in range(3, _blank.size(), 4):
			_blank[i] = 255
		image = Image.create_from_data(_size.x, _size.y, false,
			Image.FORMAT_RGBA8, _blank)

	func size() -> Vector2i:
		return _size

	## Start a frame. Opaque black rather than transparent, because that is what a
	## viewport reads back as where nothing was drawn, and the two frames a
	## transition composes have to be comparable to each other pixel for pixel.
	func begin() -> void:
		image.set_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, _blank)
		approximated = 0
		drawn = 0

	## A copy, because the surface is reused by the next paint. `Image.duplicate`
	## returns a `Resource` and needs a cast at every call site; building from the
	## bytes says the format out loud instead.
	func snapshot() -> Image:
		return Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_RGBA8,
			image.get_data())

	func fill(box: Rect2, color: Color) -> void:
		var area := _clip(_pixels(box))
		if area.size.x <= 0 or area.size.y <= 0:
			return
		drawn += 1
		# The whole surface in one opaque colour is what `_paint` opens every frame
		# with, and black is what almost every movie opens it with, so it gets the
		# memcpy `begin` uses rather than 307,200 `fill_rect` iterations.
		if color.a >= 1.0 and area == Rect2i(Vector2i.ZERO, _size) \
				and color.r8 == 0 and color.g8 == 0 and color.b8 == 0:
			image.set_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, _blank)
			return
		# `fill_rect` overwrites and is the fast path for everything else. A
		# translucent rect -- the SKIP button, the toast, EXODUS's selection bar --
		# has to blend, and blending is one allocation plus one native call.
		if color.a >= 1.0:
			image.fill_rect(area, color)
			return
		var patch := Image.create_empty(area.size.x, area.size.y, false,
			Image.FORMAT_RGBA8)
		patch.fill(color)
		image.blend_rect(patch, Rect2i(Vector2i.ZERO, area.size), area.position)

	## Four edges, the same closed polyline `rect` issues, at `thickness` wide.
	##
	## Godot centres that polyline on the boundary, so each edge covers half the
	## line outside the rectangle and half inside; `grow(thickness * 0.5)` on the
	## outer band and `grow(-thickness * 0.5)` on the inner one is the same figure.
	func outline(box: Rect2, color: Color, thickness: float) -> void:
		var outer := box.grow(thickness * 0.5)
		var inner := box.grow(-thickness * 0.5)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			fill(outer, color)
			return
		fill(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), color)
		fill(Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y), color)
		fill(Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y), color)
		fill(Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y), color)

	func blit(art: Texture2D, at: Vector2, modulate: Color) -> void:
		var src := _image_of(art)
		if src == null:
			return
		drawn += 1
		_compose(_modulated(src, modulate), Vector2i(at.round()))

	## The stretched and mirrored form. A negative extent asks Godot to mirror in
	## place and leaves the rectangle covered unchanged (`sprite_art.gd:draw`
	## carries the measurement), so the destination is `abs()` and the source is
	## flipped to match.
	func blit_rect(art: Texture2D, box: Rect2, tile: bool, modulate: Color) -> void:
		var src := _image_of(art)
		if src == null:
			return
		drawn += 1
		var area := box.abs()
		var target := Vector2i(area.size.round())
		if target.x <= 0 or target.y <= 0:
			return
		var work := _modulated(src, modulate)
		if tile:
			# Not tiled. Nothing in this port passes `tile = true` -- the two callers
			# are `sprite_art.gd:draw` and `stage_paint.gd:draw_transition`, both
			# false -- so this is a stated hole rather than a measured cost, and it
			# is counted so a capture cannot silently be wrong about one.
			approximated += 1
		if work.get_size() != target:
			if work == src:
				work = Image.create_from_data(src.get_width(), src.get_height(),
					false, src.get_format(), src.get_data())
			# Nearest for `_grab_stage`'s reason: a resampled edge invents colours
			# neither frame holds, and a "which picture is this pixel from" test then
			# reads it as a third picture.
			work.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
		if box.size.x < 0.0 or box.size.y < 0.0:
			if work == src:
				work = Image.create_from_data(work.get_width(), work.get_height(),
					false, work.get_format(), work.get_data())
			if box.size.x < 0.0:
				work.flip_x()
			if box.size.y < 0.0:
				work.flip_y()
		_compose(work, Vector2i(area.position.round()))

	## Glyphs, shaped by the same `TextServer` `Font.draw_string` shapes with and
	## blended from the same glyph atlas it samples.
	##
	## **Rasterised at 1:1, where the GPU path rasterises at the viewport's
	## oversampling** (`Paint.oversampling`, and the 18,499-pixel measurement in
	## its docstring). That is the right answer for a surface whose coordinates are
	## Director's pixels -- an oversampled glyph would be the wrong size here -- and
	## it is still a difference from the screen, so it is counted.
	##
	## Works headless: the glyph atlas is a CPU-side `Image` on the font, not a
	## texture on the renderer. Measured on 4.7.1 `--headless`, which answers
	## `font_get_texture_image` with a 256x256 `FORMAT_LA8` page while
	## `ViewportTexture.get_image` answers nothing at all.
	func glyphs(font: Font, at: Vector2, value: String, alignment: int,
			width: float, size: int, color: Color) -> void:
		if font == null or value == "":
			return
		var ts := TextServerManager.get_primary_interface()
		var shaped := ts.create_shaped_text()
		ts.shaped_text_add_string(shaped, value, font.get_rids(), size)
		ts.shaped_text_shape(shaped)
		var pen := at
		if width > 0.0:
			var span := ts.shaped_text_get_width(shaped)
			match alignment:
				HORIZONTAL_ALIGNMENT_CENTER:
					pen.x += maxf(0.0, (width - span) * 0.5)
				HORIZONTAL_ALIGNMENT_RIGHT:
					pen.x += maxf(0.0, width - span)
		for glyph in ts.shaped_text_get_glyphs(shaped):
			var advance := float(glyph["advance"])
			for _repeat in maxi(1, int(glyph["repeat"])):
				_one_glyph(ts, glyph, pen, color)
				pen.x += advance
		ts.free_rid(shaped)
		approximated += 1
		drawn += 1

	func _one_glyph(ts: TextServer, glyph: Dictionary, pen: Vector2,
			color: Color) -> void:
		var font_rid: RID = glyph["font_rid"]
		if not font_rid.is_valid():
			return
		var font_size := Vector2i(int(glyph["font_size"]), 0)
		var index := int(glyph["index"])
		var page := ts.font_get_glyph_texture_idx(font_rid, font_size, index)
		if page < 0:
			return
		var key := "%s:%d:%d" % [str(font_rid), font_size.x, page]
		var atlas: Image = _atlases.get(key)
		if atlas == null:
			atlas = ts.font_get_texture_image(font_rid, font_size, page)
			if atlas == null:
				return
			_atlases[key] = atlas
		var uv := Rect2i(ts.font_get_glyph_uv_rect(font_rid, font_size, index))
		uv = uv.intersection(Rect2i(Vector2i.ZERO, atlas.get_size()))
		if uv.size.x <= 0 or uv.size.y <= 0:
			return
		var cell := atlas.get_region(uv)
		if cell.get_format() != Image.FORMAT_RGBA8:
			cell.convert(Image.FORMAT_RGBA8)
		# The atlas carries coverage in alpha and the glyph's own luminance in RGB;
		# `draw_string` multiplies both by the colour, so the tint is the colour's
		# RGB with the coverage kept.
		var bytes := cell.get_data()
		var red := int(clampf(color.r, 0.0, 1.0) * 255.0)
		var green := int(clampf(color.g, 0.0, 1.0) * 255.0)
		var blue := int(clampf(color.b, 0.0, 1.0) * 255.0)
		var alpha := clampf(color.a, 0.0, 1.0)
		for i in range(0, bytes.size(), 4):
			bytes[i] = red
			bytes[i + 1] = green
			bytes[i + 2] = blue
			bytes[i + 3] = int(bytes[i + 3] * alpha)
		var tinted := Image.create_from_data(uv.size.x, uv.size.y, false,
			Image.FORMAT_RGBA8, bytes)
		var offset := ts.font_get_glyph_offset(font_rid, font_size, index)
		_compose(tinted, Vector2i((pen + offset).round()))

	func _clip(box: Rect2i) -> Rect2i:
		return box.intersection(Rect2i(Vector2i.ZERO, _size))

	## A float rectangle as whole pixels. **Both corners are rounded and the size
	## is their difference**, rather than rounding the position and the size
	## separately: those two disagree by a pixel whenever the position's fraction
	## and the size's fraction round in opposite directions, which for the stage
	## fill is never and for a one-pixel outline edge is often.
	static func _pixels(box: Rect2) -> Rect2i:
		var area := box.abs()
		var start := Vector2i(area.position.round())
		return Rect2i(start, Vector2i(area.end.round()) - start)

	## Source-over, clipped to the surface. `Image.blend_rect` clamps a destination
	## that runs off the right or the bottom and does *not* handle a negative one,
	## so the visible region is worked out here and the source rect moved with it.
	func _compose(src: Image, at: Vector2i) -> void:
		if src == null:
			return
		var visible := _clip(Rect2i(at, src.get_size()))
		if visible.size.x <= 0 or visible.size.y <= 0:
			return
		if src.get_format() != Image.FORMAT_RGBA8:
			src = Image.create_from_data(src.get_width(), src.get_height(), false,
				src.get_format(), src.get_data())
			src.convert(Image.FORMAT_RGBA8)
		image.blend_rect(src, Rect2i(visible.position - at, visible.size),
			visible.position)

	## The pixels behind a texture. `ImageTexture.get_image` reaches
	## `RenderingServer.texture_2d_get`, which the dummy renderer answers from the
	## `Image` it was handed at creation -- so this is one of the few readbacks that
	## survives having no renderer, and it is why the surface can compose real
	## artwork on a machine with no screen.
	static func _image_of(art: Texture2D) -> Image:
		if art == null:
			return null
		return art.get_image()

	## `modulate` applied, or the source itself when there is nothing to apply.
	##
	## The alpha-only case is separated because it is the only one this port
	## actually produces -- `Ink.blend_alpha` rides in as `Color(1, 1, 1, a)` -- and
	## it touches one byte in four instead of three.
	static func _modulated(src: Image, modulate: Color) -> Image:
		if src == null:
			return null
		if modulate.is_equal_approx(Color.WHITE):
			return src
		var work := src
		if work.get_format() != Image.FORMAT_RGBA8:
			work = Image.create_from_data(src.get_width(), src.get_height(), false,
				src.get_format(), src.get_data())
			work.convert(Image.FORMAT_RGBA8)
		var bytes := work.get_data()
		var alpha := int(clampf(modulate.a, 0.0, 1.0) * 255.0)
		if is_equal_approx(modulate.r, 1.0) and is_equal_approx(modulate.g, 1.0) \
				and is_equal_approx(modulate.b, 1.0):
			if alpha < 255:
				for i in range(3, bytes.size(), 4):
					bytes[i] = (bytes[i] * alpha + 127) / 255
		else:
			var red := int(clampf(modulate.r, 0.0, 1.0) * 255.0)
			var green := int(clampf(modulate.g, 0.0, 1.0) * 255.0)
			var blue := int(clampf(modulate.b, 0.0, 1.0) * 255.0)
			for i in range(0, bytes.size(), 4):
				bytes[i] = (bytes[i] * red + 127) / 255
				bytes[i + 1] = (bytes[i + 1] * green + 127) / 255
				bytes[i + 2] = (bytes[i + 2] * blue + 127) / 255
				bytes[i + 3] = (bytes[i + 3] * alpha + 127) / 255
		return Image.create_from_data(work.get_width(), work.get_height(), false,
			Image.FORMAT_RGBA8, bytes)
