extends SceneTree
## Can a `moveableSprite` actually be picked up and dragged?
##
##   godot --headless --script tools/sprite_drag.gd
##   godot --script tools/sprite_drag.gd -- --movie DAY1.dir --channel 103
##
## Director's own drag: a mouse-down over a sprite whose `moveable` is set
## records the channel and the offset from the click to the sprite's position,
## and every pointer move until mouse-up writes `locH`/`locV`.
##
## Reported symptom: in Piposh 2's DAY1 you cannot drag anything out of the
## inventory. `init all` and `displayobject` both run
##
##   set the moveableSprite of sprite i to 1
##
## over channels 103-110 for every occupied slot, and that write is the only
## thing that can make those sprites moveable -- Piposh 2's score sets the
## authored moveable bit on no record at all. So "the inventory will not drag" is
## this one mechanism failing, not an inventory bug.
##
## Root cause, asserted link by link below because the links fail in ways that
## look identical from the player's chair: the write arrived at
## `lingo_set_sprite_prop` as `moveablesprite`, Director's own spelling, and
## `preview/sprite_state.gd` merges the override table under the score record's
## spelling, `moveable`. Nothing sat between the two vocabularies. The property
## round-tripped perfectly through `read_prop` -- `the moveableSprite of sprite
## 103` answered 1 the instant it was set to 1 -- so it looked implemented, and
## the only thing that failed was every consumer of it. `Interaction` found the
## slots ineligible for the mouse entirely, so the click fell through to the
## inventory bar behind them and no drag ever began.
##
## **Title-agnostic by default, and deliberately so.** With no arguments it boots
## whatever `director_game.cfg` names and picks its own subject: the busiest
## frame, and the highest channel on it, which is the one nothing can cover.
## `moveableSprite` is a Director property rather than one game's, and a check
## that only runs against one title goes dark the moment the config is pointed
## somewhere else -- which is exactly what happened while this was being written.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")


func _sprite_on(preview: Node, channel: int) -> Dictionary:
	var score = preview.get("_score")
	for sprite in score.frame(int(preview.get("_index"))).get("sprites", []):
		if int((sprite as Dictionary)["channel"]) == channel:
			return sprite
	return {}


## A frame and a channel to try the drag on. An explicit channel is looked for
## across every frame that carries it; otherwise the topmost sprite of the
## busiest frame, because channel number is depth and nothing above it can absorb
## the click first.
##
## In both cases the *largest* candidate wins rather than the first. A channel
## occupied by a 1x1 record is a real score entry and a hopeless drag target: too
## small to sample pixels around, and in DAY1 that is exactly what frame 1 holds
## for every inventory slot, 36 frames before the inventory is on screen.
func _subject(preview: Node, want_channel: int) -> Array:
	var score = preview.get("_score")
	var best := [-1, 0]
	var best_area := -1.0
	var best_count := -1
	for i in score.frame_count:
		var sprites: Array = score.frame(i).get("sprites", [])
		if sprites.is_empty():
			continue
		var top := 0
		var top_area := 0.0
		for raw in sprites:
			var sprite: Dictionary = raw
			var channel := int(sprite["channel"])
			var area := float(sprite.get("width", 0)) * float(sprite.get("height", 0))
			if want_channel > 0:
				if channel == want_channel and area > best_area:
					best_area = area
					best = [i, channel]
				continue
			if channel > top:
				top = channel
				top_area = area
		if want_channel <= 0 and top_area > 4.0 and sprites.size() > best_count:
			best_count = sprites.size()
			best = [i, top]
	return best


## A stage point the hit test actually answers `channel` for. The centre is right
## nine times in ten, but a Matte sprite is transparent to the mouse wherever it
## has no pixels, and a transparent centre is the harness being unlucky rather
## than the drag being broken.
func _grab_point(preview: Node, rect: Rect2, channel: int) -> Vector2:
	if int(preview.call("_channel_at", rect.get_center())) == channel:
		return rect.get_center()
	for row in 7:
		for column in 7:
			var at := rect.position + rect.size * Vector2(
				(column + 1) / 8.0, (row + 1) / 8.0)
			if int(preview.call("_channel_at", at)) == channel:
				return at
	return Vector2(-1, -1)


## Somewhere to drag to: 60px towards the middle of the stage, so the
## destination is inside it wherever the sprite started. A fixed offset walks off
## the top for a sprite near the top, and the OS will not put the pointer outside
## the window -- so the warp lands short and a working drag reports as broken.
func _drag_to(preview: Node, from: Vector2) -> Vector2:
	var middle := Vector2(preview.get("STAGE")) * 0.5
	var toward := middle - from
	if toward.length() < 1.0:
		toward = Vector2(1, 0)
	return from + toward.normalized() * 60.0


## The framebuffer under a stage rectangle, in viewport pixels. Windowed runs
## only: headless Godot discards the draw list, so this would be comparing an
## image of what was never painted with another image of the same.
func _sample(preview: Node, stage_rect: Rect2) -> PackedByteArray:
	var image := root.get_texture().get_image()
	var to_viewport: Transform2D = preview.get_global_transform_with_canvas()
	var region := Rect2i(
		Vector2i((to_viewport * stage_rect.position).floor()),
		Vector2i((stage_rect.size * to_viewport.get_scale()).ceil())
	).grow(4)
	var clipped := region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return PackedByteArray()
	return image.get_region(clipped).get_data()


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		await process_frame

	var found := _subject(preview, Args.number(args, "channel", 0))
	var at_frame := int(found[0])
	var slot := int(found[1])
	h.begin("the movie offers a sprite to drag")
	if not h.check("a frame carries one", at_frame >= 0 and slot > 0,
			"frame %d, channel %d" % [at_frame + 1, slot]):
		h.complete("the movie offers a sprite to drag")
		quit(h.finish("Director's moveableSprite drag"))
		return
	preview.set("_index", at_frame)
	h.complete("the movie offers a sprite to drag")

	var sprite := _sprite_on(preview, slot)

	# 1. The write, through the same call `preview_lingo_host.set_sprite_prop`
	# makes and with the spelling the interpreter hands over, because the bug
	# lived entirely in the gap between that spelling and the merge's.
	h.begin("`set the moveableSprite of sprite` reaches the sprite")
	preview.call("lingo_set_sprite_prop", slot, "moveablesprite", 1)
	var after: Dictionary = preview.call("_effective", sprite)
	h.check("the effective sprite is moveable after the write",
		bool(after.get("moveable", false)),
		"override keys: %s" % str(
			(preview.get("_overrides") as Dictionary).get(slot, {}).keys()))
	h.check("`the moveableSprite of sprite` reads back as 1",
		int(preview.call("lingo_sprite_prop", slot, "moveablesprite")) == 1)
	h.complete("`set the moveableSprite of sprite` reaches the sprite")

	# 2. Eligibility. An inventory slot carries a bitmap with no script of its
	# own, so `moveable` is the only thing that can make a click land on it --
	# without it the descent walks straight past to whatever is behind.
	h.begin("a moveable sprite answers the mouse with no script")
	h.check("it responds to the mouse",
		Interaction.responds_to_mouse(preview, after, preview.get("_table")))
	var rect: Rect2 = preview.call("_sprite_rect", after)
	var centre := _grab_point(preview, rect, slot)
	h.check("the hit test finds it inside its own rect", centre.x >= 0.0,
		"rect %s" % str(rect))
	h.complete("a moveable sprite answers the mouse with no script")
	if centre.x < 0.0:
		quit(h.finish("Director's moveableSprite drag"))
		return

	# 3. The drag, through the real mouse-down path: `route_click` is what
	# `InputRouter.mouse_button` calls and it is where `_begin_drag` sits.
	# Asserting the sprite's *rect* moved, not that a setter and a getter agree —
	# the player's complaint is that the item does not follow the cursor.
	h.begin("mouse-down starts a drag and the sprite follows the pointer")
	preview.call("route_click", centre)
	h.check("the drag took the sprite's channel",
		int(preview.get("_drag_channel")) == slot,
		"channel %d, wanted %d" % [int(preview.get("_drag_channel")), slot])
	var moved := _drag_to(preview, centre)
	# Exactly the two writes `InputRouter.mouse_motion` makes on each move. It
	# cannot be called here: it reads the live pointer and headless Godot has
	# none. The windowed stage below drives the real thing.
	var offset: Vector2 = preview.get("_drag_offset")
	preview.call("lingo_set_sprite_prop", slot, "loch", int(moved.x + offset.x))
	preview.call("lingo_set_sprite_prop", slot, "locv", int(moved.y + offset.y))
	var now: Rect2 = preview.call("_sprite_rect",
		preview.call("_effective", _sprite_on(preview, slot)))
	# Within a member's own registration offset rather than exactly on the
	# pointer: `locH`/`locV` are integers and the rect is placed from the
	# registration point, so a 13x9 member with reg (7,5) puts its centre a pixel
	# and a half off the cursor by construction. Demanding equality would be
	# asserting the wrong thing, and would fail on a correct drag.
	h.check("the sprite is drawn where the pointer left it",
		now.get_center().distance_to(moved) < 3.0,
		"centre %s, pointer %s" % [str(now.get_center()), str(moved)])
	h.complete("mouse-down starts a drag and the sprite follows the pointer")

	# 4. The same thing with a real pointer and real pixels. Headless Godot has
	# neither -- it never paints, and its mouse never moves -- so every check
	# above can pass while nothing happens on screen. That is the trap
	# `tools/window_renders.gd` documents, and it applies here for the same
	# reason: `mouse_motion` is reached only by moving a pointer.
	if DisplayServer.get_name() == "headless":
		print("")
		print("windowed stage skipped: run without --headless to drive a real pointer")
		quit(h.finish("Director's moveableSprite drag"))
		return

	h.begin("a real pointer move drags the sprite on screen")
	preview.call("lingo_set_sprite_prop", slot, "loch", int(centre.x))
	preview.call("lingo_set_sprite_prop", slot, "locv", int(centre.y))
	preview.set("_drag_channel", 0)
	# Stage point -> window pixel. Three transforms, not one: the node's own
	# letterbox placement, the canvas, and the project's `canvas_items` stretch.
	# `get_global_transform()` alone puts the pointer somewhere else entirely,
	# which reads as "the drag does not work" and is the harness being wrong.
	var to_screen: Transform2D = (
		preview.get_viewport().get_screen_transform()
		* preview.get_global_transform_with_canvas()
	)
	Input.warp_mouse(to_screen * centre)
	await process_frame
	await process_frame
	preview.call("route_click", preview.call("stage_mouse"))
	h.check("the pointer is over the sprite and the drag started",
		int(preview.get("_drag_channel")) == slot,
		"stage_mouse %s, wanted %s" % [str(preview.call("stage_mouse")), str(centre)])

	await RenderingServer.frame_post_draw
	var before_pixels := _sample(preview, rect)
	var target := _drag_to(preview, centre)
	Input.warp_mouse(to_screen * target)
	await process_frame
	# The real handler, reading the real pointer.
	InputRouter.mouse_motion(preview)
	await process_frame
	await RenderingServer.frame_post_draw

	var landed: Rect2 = preview.call("_sprite_rect",
		preview.call("_effective", _sprite_on(preview, slot)))
	h.check("the sprite followed the real pointer",
		landed.get_center().distance_to(target) < 3.0,
		"centre %s, pointer %s" % [str(landed.get_center()), str(target)])
	# The place it left has to actually repaint, or the sprite is "dragged" only
	# in the model. A run that renders nothing passes every check above it.
	var after_pixels := _sample(preview, rect)
	h.check("the pixels where it was have changed",
		before_pixels.size() > 0 and after_pixels != before_pixels,
		"%d bytes sampled" % after_pixels.size())
	h.complete("a real pointer move drags the sprite on screen")

	quit(h.finish("Director's moveableSprite drag"))
