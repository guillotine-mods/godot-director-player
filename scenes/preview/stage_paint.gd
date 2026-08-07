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
static func paint_frame(host, frame: Dictionary, table, stage: Vector2i) -> void:
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
	var track_trails: bool = host._trail_image != null or host._wants_trails(frame)
	for raw_sprite in frame.get("sprites", []):
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
	host.draw_rect(skip_rect, Color(0, 0, 0, 0.55), true)
	host.draw_rect(skip_rect, Color(1, 1, 1, 0.65), false, 1.0)
	host.draw_string(
		ThemeDB.fallback_font, skip_rect.position + Vector2(11, 16), "SKIP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9)
	)
	var marker: String = host._labels.marker_at(host._index) if host._labels != null else ""
	var hud := "frame %d/%d  %s  fps %.0f  hit:%s  cur:%s%s" % [
		host._index, host._score.frame_count - 1, marker, frame.get("fps", 0.0),
		"art" if host._hit_pixels else "rect", host._cursor_now,
		"  PAUSED" if host._paused else "",
	]
	host.draw_string(ThemeDB.fallback_font, Vector2(8, stage.y - 8), hud,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
