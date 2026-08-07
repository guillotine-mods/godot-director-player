extends SceneTree
## Does a finger reach the Director mouse path, and where does it land?
##
##   godot --path . --script tools/touch_input.gd
##   godot --path . --script tools/touch_input.gd -- --movie DAY1.dir
##
## **Run this windowed.** It needs a viewport with a real transform to map a
## touch point through, and headless Godot has neither that nor a pointer to
## compare against. The run detects it and says so rather than passing hollowly.
##
## **Why this can be checked at all without a phone.** Touch-to-mouse emulation
## is not Android code: `input_devices/pointing/emulate_mouse_from_touch` is
## honoured inside `Input` itself, on every platform, so an `InputEventScreenTouch`
## fed through `Input.parse_input_event()` on Windows takes exactly the path it
## would take on a device -- synthesised into an `InputEventMouseButton`, queued,
## routed through the viewport, delivered to `_input`. What a device would add is
## the driver that produces the touch; everything downstream of that is what runs
## here. That makes this a real check of the mobile input path and not a
## simulation of one, and it is the difference between `docs/MOBILE.md` asserting
## something and guessing it.
##
## What it cannot check: the OS gestures that steal a touch (back swipe, notification
## shade), the on-screen keyboard, and anything about how big a target feels
## under a fingertip. Those need hardware.
##
## **The finding this exists to pin down is the negative one.** A touch produces
## motion only while a finger is down. There is no hover, so `the rollOver`,
## `mouseEnter`, `mouseLeave` and the cursor arbitration have no input to run on
## between taps, and the last case below asserts exactly that rather than leaving
## it as a claim in a document.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _sent(preview: Node, key: String) -> int:
	return int((preview.get("_sent") as Dictionary).get(key, 0))


## Stage point -> the window pixel an OS touch would carry.
##
## The same composition `tools/sprite_drag.gd` warps a real pointer with, and for
## the same reason: three transforms, not one -- the node's letterbox placement,
## the canvas, and the project's `canvas_items` stretch. Getting it wrong puts
## the touch somewhere else entirely and reads as "touch does not work".
func _to_window(preview: Node, stage: Vector2) -> Vector2:
	var to_screen: Transform2D = (
		preview.get_viewport().get_screen_transform()
		* preview.get_global_transform_with_canvas()
	)
	return to_screen * stage


func _touch(preview: Node, stage: Vector2, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = _to_window(preview, stage)
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(preview: Node, from: Vector2, to: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = _to_window(preview, to)
	event.relative = _to_window(preview, to) - _to_window(preview, from)
	Input.parse_input_event(event)


func _busiest_frame(preview: Node) -> int:
	var score = preview.get("_score")
	var best := 0
	var most := -1
	for i in score.frame_count:
		var count: int = score.frame(i).get("sprites", []).size()
		if count > most:
			most = count
			best = i
	return best


## A sprite the mouse path can reach, made reachable if the frame offers none.
## §4.3: `moveable` alone is enough, with no script at all -- the same
## title-agnostic subject `tools/mouse_events.gd` uses, and the same reasoning.
func _subject(preview: Node) -> Array:
	var sprites: Array = preview.get("_score").frame(
		int(preview.get("_index"))).get("sprites", [])
	var stage := Vector2(preview.get("STAGE"))
	var best := 0
	var best_area := 64.0
	var best_rect := Rect2()
	for raw in sprites:
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		var rect: Rect2 = preview.call("_sprite_rect", sprite)
		var area := rect.size.x * rect.size.y
		if area > best_area and area < stage.x * stage.y * 0.6:
			best_area = area
			best = int(sprite["channel"])
			best_rect = rect
	if best <= 0:
		return []
	preview.call("lingo_set_sprite_prop", best, "moveablesprite", 1)
	for row in 7:
		for column in 7:
			var at := best_rect.position + best_rect.size * Vector2(
				(column + 1) / 8.0, (row + 1) / 8.0)
			if int(preview.call("_channel_at", at)) == best:
				return [best, at, best_rect]
	return []


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	for i in 4:
		await process_frame

	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		await process_frame

	h.begin("the emulation that makes any of this possible is on")
	# Not set in `project.godot`, so this is Godot's own default -- which means a
	# future edit to that file could switch it off without anybody connecting the
	# two. Asserted rather than assumed for exactly that reason.
	h.check("`emulate_mouse_from_touch` is enabled",
		bool(ProjectSettings.get_setting(
			"input_devices/pointing/emulate_mouse_from_touch", false)))
	h.complete("the emulation that makes any of this possible is on")

	if DisplayServer.get_name() == "headless":
		print("")
		print("headless: a touch has no viewport to land in — run without --headless")
		quit(h.finish("touch reaching the Director mouse path"))
		return

	# **The one thing this has to fake, and it fakes exactly one thing.** On a
	# device `DisplayServer.has_feature(FEATURE_MOUSE)` is false and the engine
	# takes the pointer from input events; on this machine it is true and the OS
	# cursor wins. Everything else below is the real code path -- the emulation,
	# the routing, the transforms, the dispatch. Without this line the harness
	# would silently measure the desktop cursor and report that touch works,
	# which is worse than not running at all: `the mouseH` came out as the mouse's
	# position while the touch was somewhere else entirely, and two checks passed
	# anyway because the cursor happened to be inside the same sprite.
	preview.set("_pointer_from_events", true)
	preview.set("_index", _busiest_frame(preview))
	preview.set("_paused", true)
	var host: Object = preview.get("_host")
	var found := _subject(preview)

	h.begin("the frame offers a sprite a finger can land on")
	if not h.check("one channel answers the hit test", not found.is_empty()):
		h.complete("the frame offers a sprite a finger can land on")
		quit(h.finish("touch reaching the Director mouse path"))
		return
	h.complete("the frame offers a sprite a finger can land on")
	var channel := int(found[0])
	var inside: Vector2 = found[1]

	# ------------------------------------------------------- the tap
	h.begin("a tap is a Director click, at the right stage point")
	var downs := _sent(preview, "mouseDown")
	var ups := _sent(preview, "mouseUp")
	_touch(preview, inside, true)
	for i in 3:
		await process_frame
	h.check("the touch-down sent mouseDown",
		_sent(preview, "mouseDown") == downs + 1,
		"mouseDown %d, wanted %d" % [_sent(preview, "mouseDown"), downs + 1])
	# The coordinate check is the whole question `docs/MOBILE.md` had to answer:
	# the stage is a fixed 640x480 letterboxed into whatever the device gives,
	# and a touch that arrives in window pixels has to come out the far end in
	# stage pixels. If this drifts, every hotspot in every title is offset by the
	# letterbox and nothing is clickable where it is drawn.
	h.check("it landed on the sprite that was touched",
		int(host.get("click_sprite")) == channel,
		"clickOn %d, wanted %d" % [int(host.get("click_sprite")), channel])
	h.check("`the mouseH` / `the mouseV` are in stage coordinates",
		absf(float(host.call("get_system_prop", "mouseh")) - inside.x) < 3.0
		and absf(float(host.call("get_system_prop", "mousev")) - inside.y) < 3.0,
		"host (%s,%s), touched %s" % [
			str(host.call("get_system_prop", "mouseh")),
			str(host.call("get_system_prop", "mousev")), str(inside)])
	h.check("the touch-down alone sent no mouseUp", _sent(preview, "mouseUp") == ups)
	_touch(preview, inside, false)
	for i in 3:
		await process_frame
	h.check("the lift sent mouseUp", _sent(preview, "mouseUp") == ups + 1,
		"mouseUp %d, wanted %d" % [_sent(preview, "mouseUp"), ups + 1])
	h.complete("a tap is a Director click, at the right stage point")

	# ------------------------------------------------------- the drag
	# `route_press`/`route_release` were split so a drop is decided at the moment
	# the button comes up. A finger has the same three phases, and this asserts
	# the split holds for them: down, move, up, with the sprite following.
	h.begin("a finger drag is press-move-release, and the sprite follows")
	var rect: Rect2 = preview.call("lingo_sprite_rect", channel)
	var started := rect.get_center()
	_touch(preview, inside, true)
	for i in 2:
		await process_frame
	h.check("the touch started a drag", int(preview.get("_drag_channel")) == channel,
		"drag channel %d, wanted %d" % [int(preview.get("_drag_channel")), channel])
	var moved := inside + Vector2(30, 20)
	_drag(preview, inside, moved)
	for i in 3:
		await process_frame
	var now: Rect2 = preview.call("lingo_sprite_rect", channel)
	h.check("the sprite moved with the finger",
		now.get_center().distance_to(started) > 8.0,
		"centre %s, started %s" % [str(now.get_center()), str(started)])
	ups = _sent(preview, "mouseUp")
	_touch(preview, moved, false)
	for i in 3:
		await process_frame
	h.check("the lift ended the drag", int(preview.get("_drag_channel")) == 0)
	h.check("...and still delivered the message the drop is decided in",
		_sent(preview, "mouseUp") == ups + 1,
		"mouseUp %d, wanted %d" % [_sent(preview, "mouseUp"), ups + 1])
	h.complete("a finger drag is press-move-release, and the sprite follows")

	# ------------------------------------------------------- second finger
	# Exactly one finger is emulated as a mouse, and it is whichever one went
	# down while none was tracked -- **not** index 0 specifically. So the second
	# finger has to be tested *while the first is still down*, which is also the
	# only arrangement a player can produce: a press with no matching release
	# would leave `_press_target` latched into the next gesture and the one after
	# it would deliver two `mouseUp`s.
	h.begin("a second finger, while the first is down, sends nothing")
	_touch(preview, inside, true, 0)
	for i in 2:
		await process_frame
	downs = _sent(preview, "mouseDown")
	ups = _sent(preview, "mouseUp")
	_touch(preview, inside, true, 1)
	_touch(preview, inside, false, 1)
	for i in 3:
		await process_frame
	h.check("no mouseDown from the second finger",
		_sent(preview, "mouseDown") == downs,
		"mouseDown %d, was %d" % [_sent(preview, "mouseDown"), downs])
	h.check("no mouseUp either", _sent(preview, "mouseUp") == ups)
	_touch(preview, inside, false, 0)
	for i in 2:
		await process_frame
	h.check("lifting the first finger still completes its own click",
		_sent(preview, "mouseUp") == ups + 1,
		"mouseUp %d, wanted %d" % [_sent(preview, "mouseUp"), ups + 1])
	h.complete("a second finger, while the first is down, sends nothing")

	# ------------------------------------------------------- the blocker
	# The case that decides whether this game is playable on a phone, and it is
	# asserted as a *fact about the platform* rather than as a defect to fix.
	#
	# There is no hover on a touchscreen, so the rollover cannot track intent: it
	# tracks the last place a finger was. The engine recomputes it every tick
	# (§6.3 step 10) from the last known pointer, which is the best that can be
	# done -- and the consequence is that it is **sticky**, not absent. A menu
	# built on `rollOver` highlights the item the player already tapped and
	# nothing else, for as long as they do not tap again. That is the finding,
	# and pinning it here is what stops `docs/MOBILE.md` being a guess.
	h.begin("there is no hover: the rollover sticks where the last finger was")
	preview.set("_paused", false)
	var elsewhere := Vector2(4, 4)
	_touch(preview, elsewhere, true)
	_touch(preview, elsewhere, false)
	for i in 4:
		await process_frame
	var parked := int(preview.get("_rollover_channel"))
	# Asserted on the pointer rather than on the rollover channel, because the
	# channel is only as movable as the frame allows: this corpus's boot movie
	# has one sprite covering the whole stage on the highest channel, so every
	# point on it rolls over the same channel and a channel-based check would
	# pass or fail for reasons that have nothing to do with touch. The pointer is
	# the thing the platform does or does not update, and it is what every
	# rollover, cursor and `the mouseH` read is derived from.
	var parked_h := int(host.call("get_system_prop", "mouseh"))
	h.check("the parked pointer is where the finger last was",
		absf(float(parked_h) - elsewhere.x) < 3.0,
		"mouseH %d, touched %s" % [parked_h, str(elsewhere)])
	# Ten ticks with the glass untouched. On a mouse this is where a player would
	# move the pointer and the highlight would follow; here nothing arrives.
	for i in 10:
		await process_frame
	h.check("the pointer does not move on its own",
		int(host.call("get_system_prop", "mouseh")) == parked_h,
		"mouseH %d, was %d" % [int(host.call("get_system_prop", "mouseh")), parked_h])
	h.check("nor does the rollover channel",
		int(preview.get("_rollover_channel")) == parked,
		"rollover %d, was %d" % [int(preview.get("_rollover_channel")), parked])
	# ...and it moves only by touching somewhere else, which is a *click* -- so on
	# this platform every rollover is preceded by the click it was meant to
	# preview. That is the whole of the menu problem in one assertion.
	_touch(preview, inside, true)
	for i in 4:
		await process_frame
	h.check("only another touch moves it",
		absf(float(host.call("get_system_prop", "mouseh")) - inside.x) < 3.0,
		"mouseH %s, touched %s" % [
			str(host.call("get_system_prop", "mouseh")), str(inside)])
	_touch(preview, inside, false)
	for i in 2:
		await process_frame
	h.complete("there is no hover: the rollover sticks where the last finger was")

	print("")
	print("NOTE: rollOver-driven menus need a finger held down to highlight.")
	print("      See docs/MOBILE.md, \"Hover has no touch equivalent\".")
	quit(h.finish("touch reaching the Director mouse path"))
