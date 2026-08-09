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


## Filled or outlined, matching `CanvasItem.draw_rect`'s signature and its pixels.
static func rect(canvas: CanvasItem, box: Rect2, color: Color,
		filled: bool = true, width: float = -1.0) -> void:
	var item: RID = canvas.get_canvas_item()
	var area := box.abs()
	if filled:
		RenderingServer.canvas_item_add_rect(item, area, color, false)
		return
	var thickness: float = 1.0 if width < 0.0 else width
	# An outline thicker than the rectangle is a filled rectangle grown by half
	# the line, which is what Godot degenerates to rather than drawing four
	# overlapping lines that cancel.
	if thickness >= area.size.x or thickness >= area.size.y:
		RenderingServer.canvas_item_add_rect(
			item, area.grow(0.5 * thickness), color, false)
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


static func texture_rect(canvas: CanvasItem, art: Texture2D, box: Rect2,
		tile: bool = false, modulate: Color = Color.WHITE) -> void:
	if art == null:
		return
	art.draw_rect(canvas.get_canvas_item(), box, tile, modulate)
