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
