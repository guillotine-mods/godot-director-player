extends SceneTree
## Does a finger reach the Director mouse path, and does it reach it the way a
## **mouse** does?
##
##   godot --headless --path . --script tools/touch_input.gd
##   godot --path . --script tools/touch_input.gd -- --movie DAY1.dir
##
## Director never had touch, so there is no reference behaviour to match here and
## the standard is **parity**: every one of these titles was authored for a mouse
## and its Lingo assumes one, so a finger has to leave the engine in the state a
## mouse would have left it in. Where it cannot -- there is no hover without a
## button held -- the last two sections pin the divergence as a fact about the
## platform rather than leaving it as a claim in a document.
##
## **Why this can be checked at all without a phone.** Touch-to-mouse emulation
## is not Android code: `input_devices/pointing/emulate_mouse_from_touch` is
## honoured inside `Input` itself, on every platform, so an `InputEventScreenTouch`
## fed through `Input.parse_input_event()` on a desktop takes exactly the path it
## would take on a device -- synthesised into an `InputEventMouseButton`, queued,
## routed through the viewport, delivered to `_input`. What a device would add is
## the driver that produces the touch; everything downstream of that is what runs
## here. That makes this a real check of the mobile input path and not a
## simulation of one.
##
## **This used to bail out under `--headless` and so contributed one check to the
## gate for as long as it was in the list.** It does not any more: the touch
## point is mapped through the same three transforms either way and `_scale`
## below refuses to run at all if that composition has collapsed to an identity,
## which is the only way a headless run could pass the coordinate checks
## vacuously. Run it windowed as well when the pointer arbitration is what is in
## question -- windowed, the OS cursor is real and section 3 is not pretending.
##
## What it cannot check: the OS gestures that steal a touch (back swipe,
## notification shade) before Godot sees them, the on-screen keyboard, and
## anything about how big a target feels under a fingertip. Those need hardware.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _sent(preview: Node, key: String) -> int:
	return int((preview.get("_sent") as Dictionary).get(key, 0))


func _prop(preview: Node, name: String) -> Variant:
	return (preview.get("_host") as Object).call("get_system_prop", name)


## Stage point -> the window pixel an OS touch would carry.
##
## The same composition `tools/sprite_drag.gd` warps a real pointer with, and for
## the same reason: three transforms, not one -- the node's letterbox placement,
## the canvas, and the project's `canvas_items` stretch. Getting it wrong puts
## the touch somewhere else entirely and reads as "touch does not work".
func _to_window(preview: Node, stage: Vector2) -> Vector2:
	return _to_screen(preview) * stage


func _to_screen(preview: Node) -> Transform2D:
	return (preview.get_viewport().get_screen_transform()
		* preview.get_global_transform_with_canvas())


## How much that composition scales by. Asserted, because the coordinate checks
## below are only worth running where the mapping is a real one: if the whole
## chain ever collapsed to an identity they would pass by arithmetic accident and
## say nothing about the letterbox they exist to cover.
func _scale(preview: Node) -> float:
	return _to_screen(preview).get_scale().x


func _touch(preview: Node, stage: Vector2, pressed: bool, index: int = 0,
		canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = _to_window(preview, stage)
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)


func _drag(preview: Node, from: Vector2, to: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = _to_window(preview, to)
	event.relative = _to_window(preview, to) - _to_window(preview, from)
	Input.parse_input_event(event)


## A mouse doing what a finger is about to do. Two events, because a mouse cannot
## teleport: it arrives and then it presses, and the arrival is the half a
## touchscreen has no way to send.
func _mouse_to(preview: Node, stage: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = _to_window(preview, stage)
	Input.parse_input_event(move)


func _mouse_button(preview: Node, stage: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _to_window(preview, stage)
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
	var stage := Vector2(preview.call("stage_size"))
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


## A frame, and two stage points on it that roll over **different** channels:
## `[frame, home, target, target's channel]`, or `[]`.
##
## The parity section is about which channel the engine thinks the pointer is
## over at the instant a message goes out, and a frame where every point answers
## the same channel cannot express the question -- the frame this corpus's boot
## movie is busiest on is one of those, a single sprite covering the stage on the
## highest channel and every point under it. So the *movie* is searched rather
## than the current frame, and searched rather than named, because the harness
## may not know which title it is running. 261 of `strtgame.dir`'s 1,375 frames
## qualify; the first is frame 3.
func _rollover_pair(preview: Node) -> Array:
	var score = preview.get("_score")
	var stage := Vector2(preview.call("stage_size"))
	var was := int(preview.get("_index"))
	for frame in score.frame_count:
		if score.frame(frame).get("sprites", []).size() < 1:
			continue
		preview.set("_index", frame)
		var home := Vector2.INF
		var home_channel := -1
		for y in range(8, int(stage.y) - 8, 8):
			for x in range(8, int(stage.x) - 8, 8):
				var at := Vector2(x, y)
				var channel := _stable_rollover(preview, at)
				if channel < 0:
					continue
				if home_channel < 0:
					home = at
					home_channel = channel
				elif channel != home_channel and channel > 0:
					return [frame, home, at, channel]
	preview.set("_index", was)
	return []


## The rollover channel at `at`, or -1 if it is not the same a few pixels either
## way.
##
## A point on a sprite's own edge is not a subject: the touch is mapped out to
## window pixels and back through three transforms, so it lands within about half
## a pixel of where it was aimed and a boundary point answers one channel to the
## scan and another to the tap. That is a property of the harness's round trip
## and not of the engine, and it is exactly the kind of difference that reads as
## a real finding for an afternoon.
func _stable_rollover(preview: Node, at: Vector2) -> int:
	preview.call("track_rollover", at)
	var channel := int(preview.get("_rollover_channel"))
	for offset in [Vector2(2, 2), Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2)]:
		preview.call("track_rollover", at + offset)
		if int(preview.get("_rollover_channel")) != channel:
			return -1
	return channel


## Everything about the pointer a Director script can read, in one record.
##
## The parity section diffs two of these rather than asserting a list of named
## properties, because a list only covers what somebody thought of: a field that
## a finger and a mouse come to disagree over later shows up here without anybody
## adding a check for it.
func _pointer_state(preview: Node) -> Dictionary:
	return {
		"the mouseH": int(_prop(preview, "mouseh")),
		"the mouseV": int(_prop(preview, "mousev")),
		"the clickOn": int(_prop(preview, "clickon")),
		"the mouseDown": int(_prop(preview, "mousedown")),
		"the rollOver": int(preview.call("lingo_rollover_channel")),
		# `rollOver(0)` and `rollOver()` are the same call in the reference --
		# `b_rollOver` starts from `Datum(0)` and only overwrites it when an
		# argument was passed, so both reach `getRollOverSpriteIDFromPos`. Read
		# through the binding rather than the node so the *language* surface is
		# what is compared: it used to answer `_hover_channel > 0`, the
		# eligibility-filtered click channel, which is a different question and the
		# only rollover field nothing recomputes per tick.
		"rollOver(0)": int((preview.get("_host") as Object).call(
			"call_builtin", "rollover", [0])),
		"hover channel": int(preview.get("_hover_channel")),
		"press channel": int(preview.get("_press_channel")),
		"drag channel": int(preview.get("_drag_channel")),
		"mouseDown sent": _sent(preview, "mouseDown"),
		"mouseUp sent": _sent(preview, "mouseUp"),
		"mouseEnter sent": _sent(preview, "mouseEnter"),
		"mouseLeave sent": _sent(preview, "mouseLeave"),
	}


func _differences(mouse: Dictionary, finger: Dictionary) -> Array:
	var out: Array = []
	for key in mouse:
		if mouse[key] != finger[key]:
			out.append("%s: mouse %s, finger %s" % [key, str(mouse[key]), str(finger[key])])
	return out


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
	# ...and the mapping the coordinate checks below ride on is a real one. An
	# identity here would make every "it landed where it was touched" assertion
	# below pass without testing anything, which is the failure mode a harness is
	# least likely to notice in itself.
	var scale := _scale(preview)
	h.check("the stage-to-window transform is not an identity",
		absf(scale - 1.0) > 0.01, "scale %f" % scale)
	h.complete("the emulation that makes any of this possible is on")

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

	# ------------------------------------------------------- the seam
	# **The one thing the engine now decides from, so the one thing that has to be
	# asserted.** `director_preview.gd:_input` reads `event.device` to tell a
	# finger's mouse event from a mouse's, and Godot stamps `DEVICE_ID_EMULATION`
	# on the ones it synthesises. That is a contract with the engine, not with
	# this port, and nothing else in the tree would notice it changing.
	h.begin("a finger's mouse event says it came from a finger")
	var watcher := Node.new()
	watcher.set_script(load("res://tools/lib/event_watch.gd"))
	root.add_child(watcher)
	await process_frame
	watcher.set("seen", [])
	_touch(preview, inside, true)
	for i in 2:
		await process_frame
	var devices: Array = watcher.get("seen")
	h.check("the emulated press carries DEVICE_ID_EMULATION",
		devices.has(InputEvent.DEVICE_ID_EMULATION),
		"devices seen %s" % str(devices))
	_touch(preview, inside, false)
	for i in 2:
		await process_frame
	# The other half, and the one that decides whether the seam is a seam at all:
	# an event that did *not* come from a finger must not be marked as one, or the
	# engine would take the no-cursor arm for everything and the desktop pointer
	# would stop being authoritative. Measured rather than assumed to be 0 --
	# 4.7.1 hands a freshly constructed `InputEventMouseButton` device 32 -- so
	# the assertion is the contract the engine relies on and not a guess at the
	# number: **not** `DEVICE_ID_EMULATION`.
	watcher.set("seen", [])
	_mouse_button(preview, inside, true)
	_mouse_button(preview, inside, false)
	_mouse_to(preview, inside)
	for i in 2:
		await process_frame
	devices = watcher.get("seen")
	h.check("a mouse event that is not from a finger is not marked as one",
		not devices.is_empty() and not devices.has(InputEvent.DEVICE_ID_EMULATION),
		"devices seen %s" % str(devices))
	watcher.queue_free()
	h.complete("a finger's mouse event says it came from a finger")

	# ------------------------------------------------------- the pointer source
	# **The case a boot-time platform test cannot express, and the reason this
	# harness no longer fakes `_pointer_from_events`.** `_has_os_cursor` is a fact
	# about the machine -- windowed on a desktop it is already true and nothing
	# here is pretended; headless it is set, so the engine takes the arm every
	# Windows touch laptop, Chromebook, DeX session and trackpad-equipped iPad
	# takes and a run that never set it would only ever measure the phone arm.
	#
	# Measured before the fix: a touch at stage (238,240) came out of `the mouseH`
	# / `the mouseV` as (608,19) -- wherever the cursor happened to be -- and `the
	# clickOn` as 0. Every hotspot in every title answering for a point the player
	# never touched.
	h.begin("a finger wins the pointer from an OS cursor that did not move")
	preview.set("_has_os_cursor", true)
	preview.set("_pointer_from_events", false)
	if DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		# Park the real cursor somewhere unmistakable, so a `stage_mouse()` that
		# still reads it answers with a number nothing else could produce.
		Input.warp_mouse(_to_window(preview, Vector2(4, 4)))
		for i in 3:
			await process_frame
	_touch(preview, inside, true)
	for i in 3:
		await process_frame
	h.check("the engine worked out that the pointer came from the event",
		bool(preview.get("_pointer_from_events")))
	h.check("`the mouseH` / `the mouseV` are where the finger is",
		absf(float(_prop(preview, "mouseh")) - inside.x) < 3.0
		and absf(float(_prop(preview, "mousev")) - inside.y) < 3.0,
		"host (%s,%s), touched %s" % [str(_prop(preview, "mouseh")),
			str(_prop(preview, "mousev")), str(inside)])
	h.check("it landed on the sprite that was touched",
		int(host.get("click_sprite")) == channel,
		"clickOn %d, wanted %d" % [int(host.get("click_sprite")), channel])
	_touch(preview, inside, false)
	for i in 2:
		await process_frame
	# ...and a mouse takes it back, which is the half a static flag cannot do at
	# all: a tablet with a keyboard case, or a phone with a bluetooth mouse, is
	# both machines within one session.
	_mouse_to(preview, inside)
	for i in 2:
		await process_frame
	h.check("a genuine mouse event hands the cursor back",
		not bool(preview.get("_pointer_from_events")))
	preview.set("_has_os_cursor",
		DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE))
	preview.set("_pointer_from_events", not bool(preview.get("_has_os_cursor")))
	h.complete("a finger wins the pointer from an OS cursor that did not move")

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
		absf(float(_prop(preview, "mouseh")) - inside.x) < 3.0
		and absf(float(_prop(preview, "mousev")) - inside.y) < 3.0,
		"host (%s,%s), touched %s" % [str(_prop(preview, "mouseh")),
			str(_prop(preview, "mousev")), str(inside)])
	# `the mouseDown` / `the stillDown` are read *between* events, out of an
	# `exitFrame` poll, and they are the one Director property answered from live
	# hardware rather than from engine state. Godot's emulation updates the mouse
	# button mask for a finger, so the click-to-skip idiom -- 46 scripts -- works
	# on touch; without this check that would be an inference about Godot's
	# internals with nothing behind it.
	h.check("`the mouseDown` is true while the finger is down",
		int(_prop(preview, "mousedown")) == 1)
	h.check("`the mouseUp` is its negation", int(_prop(preview, "mouseup")) == 0)
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
	# The other order, and the one nothing covered: the *tracked* finger lifts
	# first and a second is still on the glass. Godot stops tracking on that lift,
	# so the remaining finger's drags and its eventual lift produce nothing at
	# all -- if either leaked through it would arrive as a press with no release
	# behind it, or as a second `mouseUp` for a click that already finished, and
	# both latch into the next gesture rather than showing up here.
	_touch(preview, inside, true, 0)
	_touch(preview, inside, true, 1)
	for i in 2:
		await process_frame
	_touch(preview, inside, false, 0)
	for i in 2:
		await process_frame
	downs = _sent(preview, "mouseDown")
	ups = _sent(preview, "mouseUp")
	_drag(preview, inside, inside + Vector2(20, 20), 1)
	_touch(preview, inside + Vector2(20, 20), false, 1)
	for i in 3:
		await process_frame
	h.check("the finger left behind sends no message when it lifts",
		_sent(preview, "mouseDown") == downs and _sent(preview, "mouseUp") == ups,
		"mouseDown %d/%d mouseUp %d/%d" % [_sent(preview, "mouseDown"), downs,
			_sent(preview, "mouseUp"), ups])
	h.check("...and leaves no press latched",
		preview.get("_press_target") == null)
	h.complete("a second finger, while the first is down, sends nothing")

	# ------------------------------------------------------- a cancelled touch
	# The system taking the finger away -- a back swipe, the notification shade.
	# **Measured rather than reasoned**, which `docs/MOBILE.md` could not do
	# before: Godot's emulation does forward a mouse *release* for a cancelled
	# touch, so the engine sees an ordinary lift and the press completes.
	#
	# Pinned as it stands rather than changed. A finger produces something a mouse
	# cannot, so there is no parity answer and no Director behaviour to match; the
	# alternative -- routing it to `mouseUpOutSide`, the message the engine already
	# has for an abandoned press -- is a design decision about the port and is
	# recorded in `docs/MOBILE.md` rather than taken here. What this check buys is
	# that a future change to it has to be deliberate.
	h.begin("a cancelled touch arrives as a lift, and the press completes")
	_touch(preview, inside, true)
	for i in 2:
		await process_frame
	h.check("the press latched", preview.get("_press_target") != null)
	ups = _sent(preview, "mouseUp")
	_touch(preview, inside, false, 0, true)
	for i in 3:
		await process_frame
	h.check("the cancel released the press", preview.get("_press_target") == null)
	h.check("...and it counted as a mouseUp", _sent(preview, "mouseUp") == ups + 1,
		"mouseUp %d, wanted %d" % [_sent(preview, "mouseUp"), ups + 1])
	h.check("...and ended any drag", int(preview.get("_drag_channel")) == 0)
	h.complete("a cancelled touch arrives as a lift, and the press completes")

	# ------------------------------------------------------- parity
	# **The whole question, asked as a diff.** A mouse cannot teleport, so it
	# arrives and then presses; a finger has no arrival to send. Everything a
	# Director script can read about the pointer has to come out the same either
	# way, and the record is compared whole rather than property by property so
	# that a field the two come to disagree over later shows up without anybody
	# adding a check for it.
	#
	# The rollover is the one this caught: a tap dispatched `mouseDown` with the
	# *previous* gesture's rollover still latched, because `_input` re-aimed the
	# pointer only on movement. `the mouseH` named the new point and `the rollOver`
	# named the old one, inside one handler. Measured on `SAVELOAD.dir` frame 5:
	# mouse 5, finger 4.
	h.begin("a finger leaves the engine where a mouse would have left it")
	# **Both runs on the no-cursor arm.** Whether the OS cursor or the event owns
	# the pointer is section 3's subject and it is settled there; here it would
	# only add a difference that is an artefact of the harness rather than of the
	# platform, because a synthetic mouse event does not move a real cursor the
	# way a hand on a real mouse does. With no cursor in the picture both streams
	# are compared on what the engine did with them, which is the question.
	var busiest := int(preview.get("_index"))
	preview.set("_has_os_cursor", false)
	preview.set("_pointer_from_events", true)
	var pair := _rollover_pair(preview)
	if pair.size() < 4:
		h.check("some frame offers two points with different rollovers", false,
			"no frame of this movie does")
	else:
		var home: Vector2 = pair[1]
		var target: Vector2 = pair[2]
		var states: Dictionary = {}
		for mode in ["mouse", "finger"]:
			# Park at `home` without using either device, so neither run starts
			# with an advantage the other did not get.
			preview.call("note_pointer", home)
			preview.call("track_rollover", home)
			var base := _pointer_state(preview)
			if mode == "mouse":
				_mouse_to(preview, target)
				_mouse_button(preview, target, true)
			else:
				_touch(preview, target, true)
			Input.flush_buffered_events()
			# The counters are cumulative and the two runs are sequential, so the
			# comparable quantity is what *this* gesture sent.
			var state := _pointer_state(preview)
			for key in state:
				if str(key).ends_with(" sent"):
					state[key] = int(state[key]) - int(base[key])
			states[mode] = state
			if mode == "mouse":
				_mouse_button(preview, target, false)
			else:
				_touch(preview, target, false)
			Input.flush_buffered_events()
			for i in 2:
				await process_frame
		var gaps: Array = _differences(states["mouse"], states["finger"])
		h.check("nothing a script can read about the pointer differs",
			gaps.is_empty(), "; ".join(gaps))
		h.check("`the rollOver` names the sprite that was touched",
			int(states["finger"]["the rollOver"]) == int(pair[3]),
			"rollOver %s, touched ch%d" % [
				str(states["finger"]["the rollOver"]), int(pair[3])])
		h.check("...and `rollOver(0)` is the same call, not a different question",
			int(states["finger"]["rollOver(0)"]) == int(pair[3]),
			"rollOver(0) %s, touched ch%d" % [
				str(states["finger"]["rollOver(0)"]), int(pair[3])])
	preview.set("_index", busiest)
	preview.set("_has_os_cursor",
		DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE))
	h.complete("a finger leaves the engine where a mouse would have left it")

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
	var parked_h := int(_prop(preview, "mouseh"))
	h.check("the parked pointer is where the finger last was",
		absf(float(parked_h) - elsewhere.x) < 3.0,
		"mouseH %d, touched %s" % [parked_h, str(elsewhere)])
	# Ten ticks with the glass untouched. On a mouse this is where a player would
	# move the pointer and the highlight would follow; here nothing arrives.
	for i in 10:
		await process_frame
	h.check("the pointer does not move on its own",
		int(_prop(preview, "mouseh")) == parked_h,
		"mouseH %d, was %d" % [int(_prop(preview, "mouseh")), parked_h])
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
		absf(float(_prop(preview, "mouseh")) - inside.x) < 3.0,
		"mouseH %s, touched %s" % [str(_prop(preview, "mouseh")), str(inside)])
	_touch(preview, inside, false)
	for i in 2:
		await process_frame
	h.complete("there is no hover: the rollover sticks where the last finger was")

	await _stage_size_case(h, preview)

	print("")
	print("NOTE: rollOver-driven menus need a finger held down to highlight.")
	print("      See docs/MOBILE.md, \"Hover has no touch equivalent\".")
	quit(h.finish("touch reaching the Director mouse path"))


## **Does a touch still land where it was aimed when the stage is not 640x480?**
##
## A stage point reaches the engine through three transforms -- the node's
## letterbox placement, the canvas, the project's `canvas_items` stretch -- and
## comes back through `make_input_local`. Every one of them is derived from the
## stage's *size*, and the stage's size is whatever the movie's own config chunk
## says (`director_preview.gd:stage_size`, `director/director_config.gd`). Get it
## wrong and nothing errors: the artwork is simply somewhere the hit test is not,
## by more the further from the centre you go.
##
## Every movie of the six titles this port was built on declares 640x480, which is
## why the renderer carried a hardcoded `Vector2i(640, 480)` for as long as it did
## and why no harness caught it. The real counter-example is
## `test-games/itamar-magichat/magichat.dir` at 800x600:
##
##   godot --headless --path . --script tools/touch_input.gd -- \
##     --root res://test-games/itamar-magichat --boot magichat.dir
##
## That container is not in the repository, so this case cannot depend on it and
## drives the engine's stage size instead -- through `_config.rect`, which is the
## one field a container's config decodes into and the one field `stage_size()`
## reads. That is a seam rather than a mock: a size written here reaches the
## letterbox, the clip rect, the SKIP control and the touch mapping by exactly the
## path a real 800x600 movie's size takes. Run the command above when the real
## title is on the machine; this runs everywhere.
##
## The four `[display] aspect` modes are covered because they are four different
## compositions and only one of them is uniform: `stretch_fill` scales x and y by
## different factors, which is the case a mapping written as "one scale factor"
## passes on a 4:3 stage and fails here.
##
## **What each half can and cannot catch, because the two are not the same.** The
## touch round trip maps a stage point out through the node's *own* transform and
## asks the engine to map it back, so it catches a mapping that disagrees with
## itself -- a wrong inverse, a `position` the engine forgets, a non-uniform scale
## read as one number -- and it cannot catch a mapping that is wrong the same way
## in both directions. A stage stuck at 640x480 is exactly that: the touch check
## still passes, because everything is consistently in the wrong place.
##
## The letterbox and clip checks are what catch it, and they are the reason this
## case is not just four more touches. Measured by reverting `stage_size()` to
## return the constant: **9 checks go red** -- `stage_size()` itself, the SKIP
## control's anchor, the clip rect in all four modes, and "the whole stage lands
## inside the canvas" in three of the four, where an 800x600 movie scaled by a
## 640x480 letterbox factor overflows the canvas by 320x320 pixels. Zero of the
## touch checks move. Worth knowing before trusting either half alone.
func _stage_size_case(h: RefCounted, preview: Node) -> void:
	h.begin("the stage is the movie's own size, and a touch survives the letterbox")
	var config = preview.get("_config")
	var declared: Vector2i = preview.call("stage_size")
	h.check("the stage size is the movie's own config rect",
		config == null or declared == config.rect.size,
		"stage %s, config %s" % [str(declared),
			"none" if config == null else str(config.rect.size)])

	# The fallback, asserted rather than assumed: a container with no config chunk,
	# or one whose chunk will not parse, must still open. `DirectorConfig.read`
	# answers false for both and leaves `_config` null, and 640x480 is what the
	# engine uses then -- a *fallback*, which is the whole distinction this change
	# is about.
	preview.set("_config", null)
	h.check("a movie that states no stage falls back to 640x480",
		Vector2i(preview.call("stage_size")) == Vector2i(640, 480),
		str(preview.call("stage_size")))
	preview.set("_config", config)
	if config == null:
		h.check("this movie states a stage size to drive", false,
			"no config chunk; run this against a container that has one")
		h.complete("the stage is the movie's own size, and a touch survives the letterbox")
		return

	var was_rect: Rect2i = config.rect
	var was_aspect := str(preview.get("_aspect"))
	# A size no title of this corpus declares, so nothing below can pass by
	# agreeing with the constant that used to be hardcoded.
	var other := Vector2i(800, 600) if declared != Vector2i(800, 600) \
		else Vector2i(512, 342)
	for size in [declared, other]:
		config.rect = Rect2i(was_rect.position, size)
		h.check("stage_size() follows the movie's rect (%dx%d)" % [size.x, size.y],
			Vector2i(preview.call("stage_size")) == size,
			str(preview.call("stage_size")))
		# The SKIP control is anchored to the stage's own top-right corner, so it
		# is the cheapest thing on the stage that says whether the size reached the
		# overlays -- it was a `const` written against 640 and would have sat 160px
		# inside the right edge of an 800-wide stage.
		var skip: Rect2 = preview.call("skip_rect")
		h.check("the SKIP control is at the stage's top-right (%dx%d)"
			% [size.x, size.y],
			absf(skip.end.x - (float(size.x) - 8.0)) < 0.01,
			"skip %s, stage width %d" % [str(skip), size.x])
		for aspect in ["native_4_3", "wide_16_9", "ultra_21_9", "stretch_fill"]:
			preview.set("_aspect", aspect)
			preview.call("_fit_to_window")
			# The clip is re-armed from `_paint`, which headless never reaches, so
			# it is asked for directly. What is being checked is that it names the
			# movie's rect and not a constant.
			preview.call("_clip_to_stage")
			await preview.get_tree().process_frame
			var label := "%s at %dx%d" % [aspect, size.x, size.y]

			var clip: Rect2 = preview.get("_clip_rect")
			h.check("the clip is the stage rect (%s)" % label,
				clip == Rect2(Vector2.ZERO, Vector2(size)),
				"clip %s, stage %s" % [str(clip), str(Vector2(size))])

			var canvas: Vector2 = preview.get_viewport_rect().size
			var on_screen := Rect2(preview.position, Vector2(size) * preview.scale)
			h.check("the whole stage lands inside the canvas (%s)" % label,
				on_screen.position.x >= -0.5 and on_screen.position.y >= -0.5
				and on_screen.end.x <= canvas.x + 1.0
				and on_screen.end.y <= canvas.y + 1.0,
				"stage on screen %s, canvas %s" % [str(on_screen), str(canvas)])
			# `stretch_fill` is the only mode that may distort, and it must: a mode
			# that quietly kept the aspect would be indistinguishable from a
			# letterbox on a 4:3 stage and is the reason this loop exists.
			var uniform := absf(preview.scale.x - preview.scale.y) < 0.001
			h.check("the aspect is kept unless the mode says otherwise (%s)" % label,
				uniform == (aspect != "stretch_fill"),
				"scale %s" % str(preview.scale))

			# ...and the whole point: a finger at a stage point comes back as that
			# stage point. 0.9 of each axis is outside 640x480 whenever the stage is
			# bigger, so a mapping still built on the old constant cannot pass it.
			var target := (Vector2(size) * 0.9).floor()
			_touch(preview, target, true)
			for i in 3:
				await preview.get_tree().process_frame
			h.check("a touch lands where it was aimed (%s)" % label,
				absf(float(_prop(preview, "mouseh")) - target.x) < 3.0
				and absf(float(_prop(preview, "mousev")) - target.y) < 3.0,
				"host (%s,%s), touched %s" % [str(_prop(preview, "mouseh")),
					str(_prop(preview, "mousev")), str(target)])
			_touch(preview, target, false)
			for i in 2:
				await preview.get_tree().process_frame

	config.rect = was_rect
	preview.set("_aspect", was_aspect)
	preview.call("_fit_to_window")
	h.complete("the stage is the movie's own size, and a touch survives the letterbox")
