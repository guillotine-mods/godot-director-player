extends SceneTree
## Can a `moveableSprite` actually be picked up, dragged, and held inside `the
## constraint of sprite`?
##
##   godot --headless --script tools/sprite_drag.gd
##   godot --script tools/sprite_drag.gd -- --movie DAY1.dir --channel 103
##   godot --script tools/sprite_drag.gd -- --movie SHUFFLE.dir --channel 6
##
## Director's own drag: a mouse-down over a sprite whose `moveable` is set
## records the channel and the offset from the click to the sprite's position,
## and every pointer move until mouse-up writes `locH`/`locV`.
##
## **Both ends of it, because they broke separately and a week apart.** Picking
## up failed on the property-name mismatch below; letting go failed because the
## engine sent `mouseUp` on the *press*, alongside `mouseDown`, and then threw
## the real release away — so a drag never delivered the one message a drop is
## decided in. The two look identical from the player's chair ("the inventory
## does not work") and share no code at all.
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
##
## The constraint sections work the same way: no movie in either corpus can be
## relied on to have one authored, so the harness sets one itself, against
## whichever other channel the frame happens to carry. `the constraint of sprite`
## only ever asks another channel for its box. The corpus's own five sites are
## SHUFFLE's -- `set the constraint of sprite 6 to 2` under the puck it makes
## moveable in the line before -- and `--movie SHUFFLE.dir --channel 6` runs this
## against them.

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


## A channel to constrain the dragged sprite *to*: the largest sprite on the
## frame that is not the subject and is **below** it, so it cannot cover the
## subject and steal the press that starts the drag. What it depicts does not
## matter -- `the constraint of sprite` only ever asks another channel for its
## box, and the box is the whole of what it uses.
func _fence(preview: Node, on_frame: int, not_channel: int) -> int:
	var score = preview.get("_score")
	var best := 0
	var best_area := 16.0
	for raw in score.frame(on_frame).get("sprites", []):
		var sprite: Dictionary = raw
		var channel := int(sprite["channel"])
		if channel == not_channel or channel > not_channel:
			continue
		var area := float(sprite.get("width", 0)) * float(sprite.get("height", 0))
		if area > best_area:
			best_area = area
			best = channel
	return best


## A channel number no sprite occupies on this frame, for the "constrained to an
## empty channel" case.
func _empty_channel(preview: Node, on_frame: int) -> int:
	var score = preview.get("_score")
	var taken: Dictionary = {}
	for raw in score.frame(on_frame).get("sprites", []):
		taken[int((raw as Dictionary)["channel"])] = true
	for channel in range(1, 1000):
		if not taken.has(channel):
			return channel
	return 0


## Stage point -> window pixel. Three transforms, not one: the node's own
## letterbox placement, the canvas, and the project's `canvas_items` stretch.
func _to_window(preview: Node, stage: Vector2) -> Vector2:
	var to_screen: Transform2D = (
		preview.get_viewport().get_screen_transform()
		* preview.get_global_transform_with_canvas()
	)
	return to_screen * stage


## A real mouse event, delivered the way a mouse delivers one: queued through
## `Input.parse_input_event`, routed by the viewport, and handed to `_input`.
##
## **Not `InputRouter.mouse_motion(preview)`.** That is the handler, and calling
## the handler is what let the press/release split be declared done twice while
## `_input`'s only caller was still wrong: every harness drove the routing
## directly, so the one line between a real button and the routing was the one
## line nothing covered (`preview/input_router.gd:mouse_button`). A constraint
## that works when a harness writes `locH` and not when a player drags is the
## same failure in a new place, so this half goes in through the front door.
func _send(preview: Node, stage: Vector2, event: InputEventMouse) -> void:
	event.position = _to_window(preview, stage)
	Input.parse_input_event(event)


## A stage point outside the constraint box and still on the stage, so a drag
## towards it is a drag the constraint has to stop. Prefers the far corner and
## falls back to the near one for a box already against the edge of the stage.
func _outside(box: Rect2, stage: Vector2) -> Vector2:
	var out := box.end + Vector2(40.0, 40.0)
	if out.x > stage.x - 2.0:
		out.x = box.position.x - 40.0
	if out.y > stage.y - 2.0:
		out.y = box.position.y - 40.0
	return out.clamp(Vector2(2.0, 2.0), stage - Vector2(2.0, 2.0))


## Where a position write asks to land, and where the constraint lets it.
func _clamped(box: Rect2, to: Vector2) -> Vector2:
	return Vector2(
		clampf(to.x, box.position.x, box.end.x),
		clampf(to.y, box.position.y, box.end.y))


## Somewhere to drag to: 60px towards the middle of the stage, so the
## destination is inside it wherever the sprite started. A fixed offset walks off
## the top for a sprite near the top, and the OS will not put the pointer outside
## the window -- so the warp lands short and a working drag reports as broken.
func _drag_to(preview: Node, from: Vector2) -> Vector2:
	var middle := Vector2(preview.call("stage_size")) * 0.5
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

	# 3. The drag, through the real mouse-down path: `route_press` is what
	# `InputRouter.mouse_button` calls on a press and it is where `_begin_drag`
	# sits. Asserting the sprite's *rect* moved, not that a setter and a getter
	# agree — the player's complaint is that the item does not follow the cursor.
	h.begin("mouse-down starts a drag and the sprite follows the pointer")
	var sent: Dictionary = preview.get("_sent")
	var ups_before := int(sent.get("mouseUp", 0))
	preview.call("route_press", centre)
	h.check("the drag took the sprite's channel",
		int(preview.get("_drag_channel")) == slot,
		"channel %d, wanted %d" % [int(preview.get("_drag_channel")), slot])
	# The regression this half of the harness exists for. `mouseDown` and
	# `mouseUp` used to go out back to back from the press, which meant a drop was
	# decided before the drag had moved the sprite a single pixel — see
	# `preview/interaction.gd:press`.
	h.check("the press sends mouseDown and NOT mouseUp",
		int(sent.get("mouseDown", 0)) > 0 and int(sent.get("mouseUp", 0)) == ups_before,
		"mouseDown %d, mouseUp %d (was %d)" % [
			int(sent.get("mouseDown", 0)), int(sent.get("mouseUp", 0)), ups_before])
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

	# 4. The release. Picking an item up is half a drag; the reported bug was the
	# other half — "I cannot drop the item I started dragging". §7.6: the drag
	# ends on mouse-up, and Director does not suppress the message because a drag
	# was in progress. `InputRouter.mouse_button` used to clear `_drag_channel`
	# and return, so the release of a drag was the one mouse event in the engine
	# that dispatched nothing at all.
	#
	# Asserted on the *engine's* invariants rather than on any drop's outcome,
	# because what a drop does is the movie's business and this harness has to
	# hold for whichever title `director_game.cfg` names. What the engine owes the
	# movie is exactly three things, and all three failed before: the drag has
	# ended, a `mouseUp` has gone out, and `the clickOn` still names the sprite
	# that was picked up so the handler can ask where it landed.
	h.begin("mouse-up ends the drag and delivers the message a drop is decided in")
	preview.call("route_release", moved)
	h.check("the drag has ended", int(preview.get("_drag_channel")) == 0,
		"channel %d" % int(preview.get("_drag_channel")))
	h.check("the release sends mouseUp",
		int(sent.get("mouseUp", 0)) == ups_before + 1,
		"mouseUp %d, wanted %d" % [int(sent.get("mouseUp", 0)), ups_before + 1])
	# Latched by the mouse-DOWN and held across the whole drag, which is what lets
	# `sprite the clickOn intersects <target>` — the corpus's entire drop idiom —
	# ask about the sprite the player picked up rather than about whatever the
	# pointer is over at the end.
	h.check("`the clickOn` still names the dragged sprite",
		int((preview.get("_host") as Object).get("click_sprite")) == slot,
		"clickOn %d, wanted %d" % [
			int((preview.get("_host") as Object).get("click_sprite")), slot])
	# A release with no press behind it is not a click. Before the split there was
	# no press to have: every release cleared the drag and returned, so this could
	# not be got wrong; with a latch there is now a stale-latch failure mode, and
	# it would show up as a phantom second `mouseUp` on the next button-up.
	var after_up := int(sent.get("mouseUp", 0))
	preview.call("route_release", moved)
	h.check("a second release with no press behind it sends nothing",
		int(sent.get("mouseUp", 0)) == after_up,
		"mouseUp %d, wanted %d" % [int(sent.get("mouseUp", 0)), after_up])
	h.complete("mouse-up ends the drag and delivers the message a drop is decided in")

	# 5. `the constraint of sprite` (§7.6). Position writes only -- no drag is in
	# progress for any of this, and that is one of the things being asserted:
	# Director applies the constraint in `Channel::setPosition`, which is where a
	# script's own `set the locH of sprite` arrives as well as the drag, so a
	# constrained sprite is constrained whether or not anything is dragging it.
	# SHUFFLE, the only movie in the corpus that uses the property, depends on
	# that directly -- it constrains sprite 7 as well as sprite 6, and only sprite
	# 6 is ever made moveable.
	var fence := _fence(preview, at_frame, slot)
	h.begin("`the constraint of sprite` is channel state, not a puppeted field")
	h.check("a sprite starts unconstrained",
		int(preview.call("lingo_sprite_prop", slot, "constraint")) == 0)
	preview.call("lingo_set_sprite_prop", slot, "constraint", fence)
	h.check("`the constraint of sprite` reads back what was written",
		int(preview.call("lingo_sprite_prop", slot, "constraint")) == fence,
		"read %d, wrote %d" % [
			int(preview.call("lingo_sprite_prop", slot, "constraint")), fence])
	# The storage class, asserted rather than assumed, because it is invisible
	# until the score moves the channel on and then the constraint is simply gone.
	# The record has no constraint field -- bytes 36-47 hold one distinct value,
	# 0x00, across all 2,702,680 occupied records in both corpora -- so there is
	# nothing for the per-field merge to merge with, and `effective` would discard
	# an override on the next member change. All five corpus sites set the
	# constraint and then immediately `go` to another marker.
	h.check("it did not land in the per-field override table",
		not (preview.get("_overrides") as Dictionary).get(slot, {}).has("constraint"),
		"override keys: %s" % str(
			(preview.get("_overrides") as Dictionary).get(slot, {}).keys()))
	h.complete("`the constraint of sprite` is channel state, not a puppeted field")

	if fence > 0:
		var box: Rect2 = preview.call("lingo_sprite_rect", fence)
		h.begin("a constrained position write is clamped into the constraint's box")
		# Far outside on both axes, so both edges are exercised and the answer
		# cannot be the position happening to be legal already.
		var far := box.end + Vector2(500.0, 500.0)
		preview.call("lingo_set_sprite_prop", slot, "loch", int(far.x))
		preview.call("lingo_set_sprite_prop", slot, "locv", int(far.y))
		var landed := Vector2(
			float(preview.call("lingo_sprite_prop", slot, "loch")),
			float(preview.call("lingo_sprite_prop", slot, "locv")))
		h.check("a write past the far edge lands on it",
			landed == Vector2(int(box.end.x), int(box.end.y)),
			"landed %s, box %s" % [str(landed), str(box)])
		# **The point, not the rect**, which is the one thing about this that is
		# easy to get wrong in a way that looks more correct. A sprite is placed
		# from its registration point, so a sprite pinned to the far edge hangs
		# outside the box by whatever artwork sits to the right of that point.
		# A version that clamped the *rect* would report a position short of the
		# edge -- the check above is what catches it -- and would stop a slider
		# knob reaching the end of its own track.
		var pinned: Rect2 = preview.call("_sprite_rect",
			preview.call("_effective", _sprite_on(preview, slot)))
		var reach := pinned.end.x - landed.x
		if reach > 0.0:
			h.check("the sprite is allowed to overhang the box by its registration offset",
				pinned.end.x > box.end.x,
				"rect ends %.0f, box ends %.0f, %.0f of artwork right of the position" % [
					pinned.end.x, box.end.x, reach])
		var near := box.position - Vector2(500.0, 500.0)
		preview.call("lingo_set_sprite_prop", slot, "loch", int(near.x))
		preview.call("lingo_set_sprite_prop", slot, "locv", int(near.y))
		h.check("a write past the near edge lands on it",
			Vector2(float(preview.call("lingo_sprite_prop", slot, "loch")),
				float(preview.call("lingo_sprite_prop", slot, "locv")))
				== Vector2(int(box.position.x), int(box.position.y)),
			"landed %s,%s box %s" % [
				str(preview.call("lingo_sprite_prop", slot, "loch")),
				str(preview.call("lingo_sprite_prop", slot, "locv")), str(box)])
		var inside := box.get_center().floor()
		preview.call("lingo_set_sprite_prop", slot, "loch", int(inside.x))
		preview.call("lingo_set_sprite_prop", slot, "locv", int(inside.y))
		h.check("a write inside the box is stored untouched",
			Vector2(float(preview.call("lingo_sprite_prop", slot, "loch")),
				float(preview.call("lingo_sprite_prop", slot, "locv"))) == inside,
			"landed %s, wanted %s" % [
				str(Vector2(float(preview.call("lingo_sprite_prop", slot, "loch")),
					float(preview.call("lingo_sprite_prop", slot, "locv")))), str(inside)])
		# Nothing was being dragged for any of the above.
		h.check("no drag was in progress for any of it",
			int(preview.get("_drag_channel")) == 0)
		h.complete("a constrained position write is clamped into the constraint's box")

	# The two answers that are not "clamp it": a constraint of 0 is Director's
	# default and means unconstrained, and a constraint naming a channel with no
	# sprite on it has no box to clamp into. The literal reading of the reference
	# would ask the empty channel anyway, get an empty rect at the origin and
	# teleport the sprite to (0, 0) the instant a script or a player moved it;
	# `interaction.gd:constraint_box` says why this port refuses to.
	h.begin("a constraint with no box does not move the sprite")
	var away := Vector2(600.0, 400.0)
	preview.call("lingo_set_sprite_prop", slot, "constraint", _empty_channel(preview, at_frame))
	preview.call("lingo_set_sprite_prop", slot, "loch", int(away.x))
	preview.call("lingo_set_sprite_prop", slot, "locv", int(away.y))
	h.check("a constraint on an empty channel leaves the write alone",
		Vector2(float(preview.call("lingo_sprite_prop", slot, "loch")),
			float(preview.call("lingo_sprite_prop", slot, "locv"))) == away,
		"landed %s, wanted %s" % [
			str(Vector2(float(preview.call("lingo_sprite_prop", slot, "loch")),
				float(preview.call("lingo_sprite_prop", slot, "locv")))), str(away)])
	preview.call("lingo_set_sprite_prop", slot, "constraint", 0)
	var free := Vector2(11.0, 13.0)
	preview.call("lingo_set_sprite_prop", slot, "loch", int(free.x))
	preview.call("lingo_set_sprite_prop", slot, "locv", int(free.y))
	h.check("a constraint of 0 means unconstrained",
		Vector2(float(preview.call("lingo_sprite_prop", slot, "loch")),
			float(preview.call("lingo_sprite_prop", slot, "locv"))) == free,
		"landed %s, wanted %s" % [
			str(Vector2(float(preview.call("lingo_sprite_prop", slot, "loch")),
				float(preview.call("lingo_sprite_prop", slot, "locv")))), str(free)])
	h.complete("a constraint with no box does not move the sprite")

	# 6. The same thing with a real pointer and real pixels. Headless Godot has
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
	var real_ups := int(sent.get("mouseUp", 0))
	preview.call("route_press", preview.call("stage_mouse"))
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

	# 7. Letting go, through `InputRouter.mouse_button` itself rather than through
	# `route_release`. That is the whole point of doing it here: the bug was not in
	# the routing but in the *router*, which took a non-pressed event, cleared the
	# drag and returned before anything was dispatched. A check that calls
	# `route_release` directly would have passed against the broken build.
	h.begin("a real button-up delivers the drop")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	InputRouter.mouse_button(preview, up, preview.call("stage_mouse"), Rect2())
	await process_frame
	await RenderingServer.frame_post_draw
	h.check("the real button-up ended the drag",
		int(preview.get("_drag_channel")) == 0,
		"channel %d" % int(preview.get("_drag_channel")))
	h.check("the real button-up sent mouseUp",
		int(sent.get("mouseUp", 0)) == real_ups + 1,
		"mouseUp %d, wanted %d" % [int(sent.get("mouseUp", 0)), real_ups + 1])
	# The sprite stops following the pointer once the button is up. Moving the
	# mouse again and finding the sprite still where it was let go is the
	# player-visible half of "the drag ended" — `_drag_channel` reading 0 is the
	# model agreeing with itself.
	var dropped: Rect2 = preview.call("_sprite_rect",
		preview.call("_effective", _sprite_on(preview, slot)))
	Input.warp_mouse(to_screen * (target + Vector2(0, 40)))
	await process_frame
	InputRouter.mouse_motion(preview)
	await process_frame
	var still: Rect2 = preview.call("_sprite_rect",
		preview.call("_effective", _sprite_on(preview, slot)))
	h.check("the sprite no longer follows the pointer",
		still.position.is_equal_approx(dropped.position),
		"was %s, now %s" % [str(dropped.position), str(still.position)])
	h.complete("a real button-up delivers the drop")

	# 8. The constraint under a real pointer, and the whole way in through
	# `_input` -- press, move and release are all `Input.parse_input_event`, so
	# what is being checked is the path a player has, not the path a harness has.
	# Section 5 proved the rule against position writes; this proves the rule is
	# reachable, and that the sprite is *drawn* where the constraint left it.
	#
	# The playhead is stopped for it. The score keeps running across every
	# `await` above, and a `mouseUp` handler that runs a `go` moves the frame out
	# from under the subject -- which reads as the constraint failing when it is
	# the harness measuring a different movie.
	if fence > 0:
		preview.set("_paused", true)
		var box: Rect2 = preview.call("lingo_sprite_rect", fence)
		preview.call("lingo_set_sprite_prop", slot, "constraint", 0)
		var home := box.get_center().floor()
		preview.call("lingo_set_sprite_prop", slot, "loch", int(home.x))
		preview.call("lingo_set_sprite_prop", slot, "locv", int(home.y))
		await process_frame
		var home_rect: Rect2 = preview.call("_sprite_rect",
			preview.call("_effective", _sprite_on(preview, slot)))
		var grab := _grab_point(preview, home_rect, slot)
		var out := _outside(box, Vector2(preview.call("stage_size")))

		h.begin("a real drag stops at the edge of the constraint")
		h.check("the sprite can be picked up inside the box", grab.x >= 0.0,
			"rect %s, box %s" % [str(home_rect), str(box)])
		h.check("the drag is aimed outside the box", not box.has_point(out),
			"pointer %s, box %s" % [str(out), str(box)])
		if grab.x >= 0.0 and not box.has_point(out):
			preview.call("lingo_set_sprite_prop", slot, "constraint", fence)
			# No `Input.warp_mouse` anywhere in this section, deliberately. The
			# events carry their own position and `_input` routes by *that* -- the
			# whole point of `note_pointer`, and what makes the engine work on a
			# touchscreen. Warping as well puts a second, OS-generated motion into
			# the queue behind the synthetic one, and the drag then ends wherever
			# the operating system decided to leave the cursor.
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			_send(preview, grab, down)
			await process_frame
			h.check("a real press inside the box started the drag",
				int(preview.get("_drag_channel")) == slot,
				"channel %d, wanted %d" % [int(preview.get("_drag_channel")), slot])
			await RenderingServer.frame_post_draw
			var edge_before := _sample(preview, home_rect)
			# Where the drag asks the sprite to go, and where §7.6 lets it. Derived
			# from the engine's own grab offset rather than assumed, so the check
			# holds for whichever member this title put on the channel.
			var wanted: Vector2 = out + (preview.get("_drag_offset") as Vector2)
			var expect := _clamped(box, wanted)
			h.check("the drag would leave the box if nothing stopped it",
				wanted != expect, "wanted %s, allowed %s" % [str(wanted), str(expect)])
			var move := InputEventMouseMotion.new()
			move.relative = _to_window(preview, out) - _to_window(preview, grab)
			_send(preview, out, move)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var stopped := Vector2(
				float(preview.call("lingo_sprite_prop", slot, "loch")),
				float(preview.call("lingo_sprite_prop", slot, "locv")))
			h.check("the dragged sprite stopped on the box's edge",
				stopped == Vector2(int(expect.x), int(expect.y)),
				"stopped %s, edge %s, pointer asked for %s" % [
					str(stopped), str(expect), str(wanted)])
			# The player-visible half: it is drawn there, and the place it left has
			# repainted. A run that renders nothing passes every model check above.
			var landed_rect: Rect2 = preview.call("_sprite_rect",
				preview.call("_effective", _sprite_on(preview, slot)))
			h.check("it is drawn where the constraint left it",
				landed_rect.get_center().distance_to(
					stopped + (home_rect.get_center() - home)) < 3.0,
				"rect %s, position %s" % [str(landed_rect), str(stopped)])
			h.check("the pixels where it started have changed",
				edge_before.size() > 0 and _sample(preview, home_rect) != edge_before,
				"%d bytes sampled" % edge_before.size())
			var up_again := InputEventMouseButton.new()
			up_again.button_index = MOUSE_BUTTON_LEFT
			up_again.pressed = false
			_send(preview, out, up_again)
			await process_frame
			h.check("the real button-up ended the constrained drag",
				int(preview.get("_drag_channel")) == 0,
				"channel %d" % int(preview.get("_drag_channel")))
		h.complete("a real drag stops at the edge of the constraint")
		preview.set("_paused", false)

	quit(h.finish("Director's moveableSprite drag"))
