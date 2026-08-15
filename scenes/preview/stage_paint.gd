extends RefCounted
## Painting one frame of the stage: clip, fill, sprites in channel order,
## trails, then the preview's own overlays.
##
## Draw order **is** stacking order here, and it is not a choice: the score
## builds its sprite array in ascending channel order and channel number is
## Director's depth, so painting the array front to back is correct by
## construction. Anything that reorders this list breaks layering silently.
##
## Each sprite is offered to three renderers in a fixed order -- film loop, then
## field, then bitmap or shape -- and the first that claims it wins. A field
## takes the canvas directly rather than going through the texture cache,
## because its text is the one thing in a frame a script rewrites constantly and
## a cached texture would be thrown away and rebuilt on every write.

const Ink := preload("res://director/director_ink.gd")
const Trails := preload("res://scenes/preview/trails.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const Paint := preload("res://director/director_paint.gd")
const Video := preload("res://scenes/preview/video.gd")


## Arm the clip rectangle. Returns the rect it set, for the node to record.
##
## **Called from `_draw`, every paint, and that is not belt-and-braces.** Godot
## clears a canvas item's command list before each `NOTIFICATION_DRAW`, and the
## clear resets the clip flag along with the commands -- the custom rect
## survives, the flag does not. Setting it once at startup therefore holds only
## until the first repaint, which is to say never: with the call in `_ready`
## alone the two screenshots either side of it were byte-identical and the
## artwork went on spilling into the letterbox. `tools/stage_clip.gd` is what
## caught that, by reading back real pixels rather than trusting the call.
static func clip_to_stage(host, stage: Vector2i) -> Rect2:
	# A window clips to its own movie's rect, not to the host stage's: a window
	# smaller than the stage must not paint outside itself, and one that is the
	# same size (every movie in this corpus) gets the same rectangle either way.
	#
	# The chrome sits *outside* the movie's rect -- the title bar is above local
	# y=0 and the border to the left of x=0 -- so the clip has to be widened by
	# it or a titled window would draw its movie and none of its frame. Zero for
	# `windowType` 2, which is what this corpus uses.
	var rect: Rect2
	if host._window_key == "":
		rect = Rect2(Vector2.ZERO, Vector2(stage))
	else:
		var inset: Vector2 = host.chrome_inset()
		var edge := float(host._border_width())
		rect = Rect2(-inset, host.window_size() + inset + Vector2(edge, edge))
	# Annotated rather than inferred: a call through `host` is untyped.
	var item: RID = host.get_canvas_item()
	RenderingServer.canvas_item_set_clip(item, true)
	RenderingServer.canvas_item_set_custom_rect(item, true, rect)
	return rect


## Where a rectangle of this node's own space lands **in the render target**,
## which is not where the node's transform alone says it lands.
##
## `bugs.md` 117, and the whole of the fix for it. `director_preview.gd:_grab_stage`
## reads `Viewport.get_texture().get_image()` — the framebuffer, in *window*
## pixels — and used to crop it with `get_global_transform_with_canvas()`, which
## answers in *canvas* pixels. Those are two different spaces the moment the
## project stretches, and this one does: `project.godot` sets
## `window/stretch/mode="canvas_items"` with `aspect="expand"`, so Godot leaves
## the 2D coordinate space at the content-scale size and hands the renderer a
## separate **stretch transform** that scales every canvas item up to the window
## on its way to the framebuffer. `CanvasItem.get_global_transform_with_canvas()`
## stops one transform short of it by definition — it is
## `viewport canvas transform * global transform` and nothing else — so the crop
## was being taken in a space 2.25x smaller than the image it was cropping.
##
## Measured on 4.7.1 on Windows against `rating`/`EGOZROO1.dir`, maximised
## (`tools/scratch/probe_stretch.gd`, since deleted; the numbers are the entry's):
##
##   window / framebuffer      2880 x 1690
##   viewport 2D space         1280 x 751   (`get_visible_rect()`)
##   node position / scale     (139, 0) / 1.564583
##   get_global_transform_with_canvas()  scale 1.564583, origin (139, 0)
##   viewport get_final_transform()      scale (2.25, 2.250333), origin (0, 0)
##
## `2880/1280 = 2.25` and `1690/751 = 2.250333` exactly, which is what says the
## second transform is the stretch and not something else. The old crop was
## `(139, 0, 1001, 751)` of a 2880x1690 image — the top-left corner of the stage
## with the letterbox still in it, magnified back to 640x480, mean channel drift
## **106.9 of 255** against the offscreen surface. Through the stretch it is
## `(312, 0, 2252, 1690)`: the letterboxed stage, edge to edge, and the drift is
## **0.2**. The width is one short of the exact `1001.33 x 2.25 = 2253` because
## `Node2D.scale` is float32; `transition_render.gd:_crop_follows_the_stretch`
## allows two pixels for that and says so.
##
## **`CanvasItem.get_screen_transform()` is not the answer** and is worth naming
## so nobody reaches for it next: measured on the same run it returned exactly
## `get_global_transform_with_canvas()`, because the window's own screen position
## is what it adds and the stretch is not part of it. The *viewport's*
## `get_screen_transform()` is the same thing as its `get_final_transform()` on
## the root window and either will do; `get_final_transform()` is named for what
## it is, so it is the one used here.
##
## **This was already known in `tools/` and had never crossed into the engine**,
## which is the part worth remembering rather than the arithmetic.
## `hilite.gd:_to_screen` composes exactly this pair and its comment calls the
## stretch "the half that is easy to leave out"; `mouse_events.gd`,
## `sprite_drag.gd`, `touch_input.gd` and `editable_text.gd` compose it too, and
## `stage_clip.gd` derives the same factor from `image size / visible rect`
## instead. Six harnesses had the fix and the one place that paints did not.
##
## Identity where there is no stretch, so every unstretched path — headless, a
## window at the base resolution, `stretch/mode="disabled"` — gets the rectangle
## it got before, byte for byte.
static func framebuffer_region(host, local: Rect2, image_size: Vector2i) -> Rect2i:
	# Annotated rather than inferred: a call through `host` is untyped.
	var placed: Rect2 = host.get_global_transform_with_canvas() * local
	var viewport: Viewport = host.get_viewport()
	var final := Transform2D() if viewport == null else viewport.get_final_transform()
	return render_target_region(placed, final, image_size)


## The arithmetic on its own, so a harness can hand it a stretch this machine's
## window does not happen to produce. `final` is the viewport's
## `get_final_transform()`: `stretch transform * global canvas transform`, which
## is precisely the pair `get_global_transform_with_canvas()` leaves out.
static func render_target_region(placed: Rect2, final: Transform2D,
		image_size: Vector2i) -> Rect2i:
	return Rect2i((final * placed).abs()).intersection(
		Rect2i(Vector2i.ZERO, image_size))


## Every sprite of one frame, in channel order.
static func paint_frame(host, table, stage: Vector2i) -> void:
	# Where each channel is this paint, and what it holds, so the trail layer can
	# be told which regions the frame repainted.
	#
	# Only collected when something is actually using trails: it is a dictionary
	# per drawn sprite per paint, on a path that runs for every sprite of every
	# frame, and 0 of this corpus's 816,318 sprite records ask for it. Once a
	# layer exists the tracking stays on, because the layer's contents then
	# depend on knowing where everything was.
	var placed_now: Dictionary = {}
	var to_stamp: Array[Dictionary] = []
	var track_trails: bool = host._trail_image != null or host._wants_trails()
	for raw_sprite in host.frame_sprites():
		# What a script puppeted wins over what the score recorded. Ignoring it
		# leaves sprites the Lingo hid still on screen and members it swapped
		# still showing the old art -- which looks like a layering fault and is
		# not one.
		var sprite: Dictionary = host._effective(raw_sprite)
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		host._note_member(channel, int(sprite["cast_id"]))
		var over: Dictionary = host._overrides.get(channel, {})
		# A film loop draws its own children rather than a bitmap of its own.
		if host._draw_film_loop(sprite):
			continue
		# A field draws glyphs, not pixels.
		if host._draw_text(sprite):
			continue
		# A digital video draws the frame its own playhead is on, which changes
		# under a texture key that does not -- so it cannot go through
		# `_texture_for`'s cache. Beside the film loop and the field for the same
		# reason all three are here: each is a member type whose picture is not
		# "decode the member's chunk", and each consumes the sprite whether or not
		# anything came out.
		if host._draw_video(sprite):
			continue
		# And a video **Xtra** sprite -- cast type 15 with a video player's symbol,
		# which is what Magic Hat's intro, retro film and twenty album clips are.
		# Same playback path, same texture-per-tick reason for being here rather
		# than in `_texture_for`; two calls only because the type-10 gate lives in
		# `director_preview.gd` and the pass that added this one did not own that
		# file. `preview/video.gd:draw_xtra` carries the note to merge them.
		if Video.draw_xtra(host, sprite, table):
			continue
		var texture: Texture2D = host._texture_for(sprite)
		if texture == null:
			continue
		# One rule for where a sprite is, shared with the hit test. `loc` is the
		# registration point, not the corner.
		var m: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var placed: Rect2 = host._stage_rect(sprite)
		var top_left := placed.position
		# Only the channels a script is driving. A member swap re-anchors on the
		# new member's registration point, so a walk cycle whose frames register
		# differently moves vertically on every frame unless that is honoured --
		# and the symptom is indistinguishable from the loop riding on it being
		# misplaced.
		if not over.is_empty():
			var reg := Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - top_left
			host._trace("f%d ch%d m=%d %dx%d reg(%d,%d) -> (%d,%d)" % [
				host._index, channel, int(sprite["cast_id"]),
				int(m.get("width", 0)), int(m.get("height", 0)),
				int(reg.x), int(reg.y), int(top_left.x), int(top_left.y),
			])
		# Blend is a draw-time alpha, not something baked into the artwork. A
		# blended sprite that ignored this drew fully opaque and unkeyed, which is
		# how EXODUS's selection highlight -- a semi-transparent bar meant to sit
		# over the option you are pointing at -- came out as a solid black
		# rectangle covering the text.
		host._draw_sprite_texture(texture, top_left, sprite,
			Color(1, 1, 1, Ink.blend_alpha(sprite)))
		# A trails sprite is not erased between frames, so what it painted joins
		# the layer that survives the next clear. Collected rather than stamped
		# here: the layer is first cleared where this frame repainted, and
		# stamping before that would wipe what was just added.
		var trails := bool(sprite.get("trails", false))
		if track_trails:
			placed_now[channel] = {
				"rect": placed, "member": int(sprite["cast_id"]), "trails": trails,
			}
		if trails:
			to_stamp.append({
				"image": host._hit_images.get(Geometry.texture_key(
					sprite, Geometry.drawn_size(sprite, m))),
				"at": top_left,
			})
	Trails.settle(host, placed_now, to_stamp)
	draw_transition(host, stage)


## The transition, over the top of the frame that has just been painted.
##
## §10: "the transition renders the *new* frame progressively over the *old*", so
## what is on the stage during one is a composite of two whole frames and not a
## frame with an effect applied to it.
## `director/director_transition.gd:Play` holds that composite; this is the whole
## of what puts it on screen.
##
## **The frame underneath is still painted, and the composite covers it.** The
## cheaper arrangement is to skip the sprite loop entirely while a transition is
## running, and it is wrong for a reason that has nothing to do with pixels: that
## loop is where `_note_member`, the `_text_drawn` record the focus arbitration
## reads and the trails layer are maintained, so a frame that skipped it would
## spend the whole of the transition telling the rest of the engine that nothing
## is on stage. The cost is one overdrawn paint per tick for the length of a wipe.
##
## Nothing is drawn when the play degraded to a cut. **That used to be every
## headless run** -- there was no framebuffer to capture the two frames from, so
## the gate, CI and any build without a screen held the playhead for the duration
## and cut. It is not any more: `director_preview.gd:paint_capture` composes the
## frame on the CPU through the same four primitives, so a headless run has both
## frames and composites them. What is left for `degraded` is what the reference
## also declines to play -- a type outside the table, and a changed-area
## transition on a frame that changed nothing.
static func draw_transition(host, stage: Vector2i) -> void:
	var play = host._transition_play
	if play == null or not play.draws():
		return
	# Rebuilt per paint rather than cached against the play: the compose surface is
	# a different `Image` object on every dissolve step -- it is republished from
	# the byte buffer the cells are written into -- so a texture holding on to the
	# old one would freeze the transition on its first subframe while the play went
	# on stepping underneath it.
	var texture := ImageTexture.create_from_image(play.surface)
	if texture == null:
		return
	# Over the movie's own rect, at stage scale. The two frames were cropped and
	# resized into stage pixels for the reason `_grab_stage` gives, so this is a
	# 1:1 blit rather than a stretch.
	Paint.texture_rect(host, texture, Rect2(Vector2.ZERO, Vector2(stage)),
		false, Color(1, 1, 1, 1))


## The preview's own affordances: the SKIP button and the status line.
##
## They belong to the preview, not to every movie in it. A window draws its movie
## and stops; these are drawn once, by the stage, and the stage's children paint
## after it -- so they would end up *under* an open window. That is a known
## cosmetic limit and not worth reordering the scene for: they are debug
## affordances, and a `windowType` 2 window has no chrome of its own to draw in
## their place.
static func draw_overlays(host, frame: Dictionary, stage: Vector2i,
		skip_rect: Rect2) -> void:
	# Drawn last so it sits above the stage, and in stage coordinates so it
	# scales with everything else.
	Paint.rect(host, skip_rect, Color(0, 0, 0, 0.55), true)
	Paint.rect(host, skip_rect, Color(1, 1, 1, 0.65), false, 1.0)
	Paint.text(
		host, ThemeDB.fallback_font, skip_rect.position + Vector2(11, 16), "SKIP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9)
	)
	var marker: String = host._labels.marker_at(host._index) if host._labels != null else ""
	# The rate is read off the clock, which is the only thing that resolves one.
	# It used to come from the frame dictionary, where `director_score.gd`
	# published a number it carried forward from a hardcoded 15 — so a movie that
	# writes no tempo, of which Piposh 1 has 56, read out at 15 on the HUD while
	# playing at the 2-12 its config states. The decoder no longer answers that
	# question at all; see `director_score.gd:_read_frames`.
	var rate: float = host._clock.fps if host._clock != null else 0.0
	var hud := "frame %d/%d  %s  fps %.0f  hit:%s  cur:%s%s" % [
		host._index, host._score.frame_count - 1, marker, rate,
		"art" if host._hit_pixels else "rect", host._cursor_now,
		"  PAUSED" if host._paused else "",
	]
	Paint.text(host, ThemeDB.fallback_font, Vector2(8, stage.y - 8), hud,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
