extends SceneTree
## Every mouse message Director defines, and whether this port sends it.
##
##   godot --headless --script tools/mouse_events.gd
##   godot --script tools/mouse_events.gd -- --movie DAY1.dir
##
## `tools/sprite_drag.gd` covers one path through the mouse -- pick a sprite up,
## move it, put it down -- and covers it well. This covers the *vocabulary*: the
## eight events in §8.1 and the fifteen properties in §6, which were audited
## together after the release path was repaired and turned out to be missing in
## three different ways at once.
##
## **The three ways, because they fail differently and none of them looks like a
## bug from the player's chair.**
##
## 1. `mouseUpOutSide` did not exist, so a press-here-release-there click ran the
##    `mouseUp` handler anyway. Backing out of a mis-aimed press by sliding off
##    the button before letting go -- the standard gesture, and the entire reason
##    Director has two messages instead of one -- fired the button.
## 2. `mouseEnter`, `mouseLeave` and `mouseWithin` did not exist at all, and
##    neither did the channel they are defined against: §4.5's rollover is a pure
##    rect test with no eligibility filter, and this port had only the *click*
##    channel, which filters. One number was answering two questions.
## 3. Eleven of §6's mouse properties were unbound in the live host, `the
##    mouseDown` among them. An unbound read answers VOID, `if the mouseDown
##    then` is false for ever, and a handler polling for a held button simply
##    never takes its branch.
##
## **What is asserted, and what deliberately is not.** Whether a *handler ran* is
## the movie's business and no corpus is guaranteed to carry one -- nothing in
## either title here declares `on mouseEnter`, `on mouseWithin` or
## `on rightMouseDown`. What the engine owes the movie is that the **message goes
## out at the right moment, to the right recipient, and not otherwise**, and that
## is what `_sent` records: `preview/scripts.gd:dispatch` tallies before it looks
## for a handler, so a dispatch to a script with nothing in it still counts. The
## sprite-local messages are the mirror image -- they must NOT be tallied,
## because §6.5 confines them to sprite behaviours and a movie-script fallback
## would run one of them for every sprite on the stage sixty times a second.
##
## Title-agnostic. It picks its own subject out of whatever `director_game.cfg`
## names: the busiest frame, and on it a sprite the hit test actually answers.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")

## §8.1's input events, and §6's mouse properties. Listed rather than tested one
## by one so that adding a name to the engine without adding it here is visible
## as a shorter list, not as a silently absent check.
const MOUSE_PROPS := [
	"mouseh", "mousev", "clickon", "clickloc", "mousedown", "mouseup",
	"rightmousedown", "rightmouseup", "stilldown", "doubleclick",
	"lastclick", "lastroll", "mousecast", "mousemember",
	"shiftdown", "optiondown", "commanddown", "controldown",
	"mousedownscript", "mouseupscript",
]


func _sent(preview: Node, key: String) -> int:
	return int((preview.get("_sent") as Dictionary).get(key, 0))


func _sprites(preview: Node) -> Array:
	var score = preview.get("_score")
	return score.frame(int(preview.get("_index"))).get("sprites", [])


func _sprite_on(preview: Node, channel: int) -> Dictionary:
	for raw in _sprites(preview):
		if int((raw as Dictionary)["channel"]) == channel:
			return raw
	return {}


## The busiest frame, which is the one most likely to carry a sprite the mouse
## can reach. Chosen the same way `sprite_drag.gd` chooses its subject, and for
## the same reason: a harness that hardcodes a frame is a harness that tests one
## title.
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


## A stage point the hit test answers `channel` for, or (-1,-1). The centre is
## right nine times in ten; a Matte sprite is transparent to the mouse wherever
## it has no pixels, and a transparent centre is bad luck rather than a bug.
func _point_on(preview: Node, rect: Rect2, channel: int) -> Vector2:
	if int(preview.call("_channel_at", rect.get_center())) == channel:
		return rect.get_center()
	for row in 7:
		for column in 7:
			var at := rect.position + rect.size * Vector2(
				(column + 1) / 8.0, (row + 1) / 8.0)
			if int(preview.call("_channel_at", at)) == channel:
				return at
	return Vector2(-1, -1)


## A channel the mouse can reach on this frame, with a point that reaches it.
## Highest first, because channel number is depth and nothing above it can
## absorb the press.
##
## **A subject is made if the frame does not offer one, and that is deliberate
## rather than a fallback.** §4.3: `moveable` alone makes a sprite click-eligible
## with no script whatsoever -- it has to, or nothing could start a drag -- so
## setting `the moveableSprite` is Director's own way of turning any sprite into
## a mouse target, and it is title-agnostic in a way "find a room with buttons"
## is not. The boot movie of this corpus is a splash screen with four sprite
## intervals and no hotspot anywhere in 1,375 frames; a harness that needed a
## real button would be a harness that only ran after somebody navigated, which
## is exactly how `cursor_preview` came to be measuring a splash screen.
##
## What is being asserted is the engine's routing, not the movie's scripts, and
## the routing cannot tell the two subjects apart.
func _clickable(preview: Node) -> Array:
	var natural := _reachable(preview)
	if not natural.is_empty():
		print("      subject: channel %d, eligible on its own" % int(natural[0]))
		return natural
	# Largest first: a 1x1 score entry is a real sprite and a hopeless target,
	# too small to probe pixels around. But **not the backdrop** -- the
	# cancelled-click case needs somewhere on the stage that is outside the
	# sprite, and a room backdrop covers all of it. This corpus's boot movie is
	# one 640x485 sprite over a 640x480 stage, so "largest" without the ceiling
	# picks the one subject the outside-release case cannot be tested on.
	var stage := Vector2(preview.get("STAGE"))
	var ceiling := stage.x * stage.y * 0.6
	var best := 0
	var best_area := 64.0
	for raw in _sprites(preview):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		var rect: Rect2 = preview.call("_sprite_rect", sprite)
		var area := rect.size.x * rect.size.y
		if area > best_area and area < ceiling:
			best_area = area
			best = int(sprite["channel"])
	if best <= 0:
		return []
	preview.call("lingo_set_sprite_prop", best, "moveablesprite", 1)
	print("      subject: channel %d, made eligible with `the moveableSprite` (§4.3)"
		% best)
	return _reachable(preview)


func _reachable(preview: Node) -> Array:
	var sprites := _sprites(preview)
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = preview.call("_effective", sprites[i])
		if sprite.is_empty():
			continue
		var rect: Rect2 = preview.call("_sprite_rect", sprite)
		if rect.size.x < 8.0 or rect.size.y < 8.0:
			continue
		var channel := int(sprite["channel"])
		var at := _point_on(preview, rect, channel)
		if at.x >= 0.0:
			return [channel, at, rect]
	return []


## The channel next to `subject` in stacking order, on the given side, big enough
## to aim at, and made eligible for the mouse. 0 when the frame has nothing there.
##
## Nearest rather than furthest, deliberately: the topmost sprite on a room frame
## is usually a full-stage backdrop, and a drop target that covers everything
## cannot be told apart from a drop target that was never found.
##
## Made eligible with `the moveableSprite` rather than searched for as an
## authored hotspot, for the reason `_clickable` gives at length -- §4.3 makes
## that Director's own way of turning any sprite into a mouse target, and a
## harness that needed two authored, overlapping hotspots would run on almost no
## frame of any title.
func _neighbour_channel(preview: Node, subject: int, above: bool) -> int:
	var best := 0
	for raw in _sprites(preview):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		if above:
			if channel <= subject or (best > 0 and channel > best):
				continue
		else:
			if channel >= subject or (best > 0 and channel < best):
				continue
		var rect: Rect2 = preview.call("_sprite_rect", sprite)
		if rect.size.x < 8.0 or rect.size.y < 8.0:
			continue
		best = channel
	if best > 0:
		preview.call("lingo_set_sprite_prop", best, "moveablesprite", 1)
	return best


## Which two channels to stage the drop with: `[carried, target]` with
## `target > carried`, or `[]`.
##
## The subject is the frame's topmost reachable sprite, so on a lot of frames
## there is nothing above it -- DAY1's inventory bar ends at channel 110 and the
## subject *is* 110. Rather than skip, the roles swap: carry the sprite below and
## drop it onto the subject. The rule under test is about channel order, and it
## does not care which of the two the harness happens to have found first.
func _drop_pair(preview: Node, subject: int) -> Array:
	var above := _neighbour_channel(preview, subject, true)
	if above > 0:
		return [subject, above]
	var below := _neighbour_channel(preview, subject, false)
	if below > 0:
		return [below, subject]
	return []


## Stage point -> window pixel. Three transforms, not one: the node's own
## letterbox placement, the canvas, and the project's `canvas_items` stretch.
func _to_window(preview: Node, stage: Vector2) -> Vector2:
	var to_screen: Transform2D = (
		preview.get_viewport().get_screen_transform()
		* preview.get_global_transform_with_canvas()
	)
	return to_screen * stage


## One event, delivered the way a mouse delivers one: queued through
## `Input.parse_input_event`, routed by the viewport, handed to `_input`. The
## event carries its own position and `_input` routes by *that*, so nothing here
## warps the OS cursor -- see `tools/sprite_drag.gd` for why warping as well puts
## a second, OS-generated motion into the queue behind the synthetic one.
func _send(preview: Node, stage: Vector2, event: InputEventMouse) -> void:
	event.position = _to_window(preview, stage)
	Input.parse_input_event(event)


## Pick a sprite up, carry it over a **higher** channel, and let go there.
##
## `the clickOn` must still name the sprite that was pressed, because that is the
## sprite this port delivers the `mouseUp` to, and one dispatch cannot give two
## answers to "which sprite is this about". Recomputing it under the pointer
## instead is §15's clause read literally and is what ScummVM does -- but ScummVM
## also delivers the message to the sprite under the release, and taking one
## without the other is what this exists to stop coming back.
##
## It is the corpus's entire drop idiom. `MASTER/External/BehaviorScript 52`, on
## all eight of DAY1's inventory slots and in eleven near-copies elsewhere,
## records `objectxx = the locH of sprite the clickOn` on the way down and writes
## it back to `sprite the clickOn` on the way up. With the recompute, dragging the
## ladder one slot along the bar wrote slot 1's home coordinates onto slot 4's
## sprite -- the empty marker jumped into the ladder's place and the ladder was
## abandoned mid-bar. `preview/interaction.gd:release` carries the measurement.
##
## Run twice: once driving the routing directly, which is the only way to assert
## it headlessly, and once through `_input` with real events, which is the path a
## player has. The two have been wrong separately before (`107b0a4f`: the
## press/release split reached `route_press`/`route_release` and stopped one line
## short of the only caller a mouse can reach), so neither alone is the check.
func _drop_over_a_higher_channel(preview: Node, h, host: Object, subject: int,
		real: bool) -> void:
	var how := "real events through `_input`" if real else "the routing directly"
	var pair := _drop_pair(preview, subject)
	if pair.is_empty():
		print("      this frame carries one usable sprite; no drop to stage")
		return
	var carried := int(pair[0])
	var target := int(pair[1])
	var target_rect: Rect2 = preview.call("_sprite_rect",
		preview.call("_effective", _sprite_on(preview, target)))
	var home := Vector2(
		float(preview.call("lingo_sprite_prop", carried, "loch")),
		float(preview.call("lingo_sprite_prop", carried, "locv")))
	# Both points are found *after* the target was made eligible, and that is not
	# fussiness: a target the subject sits under is now the topmost answer over
	# part of the subject too, so a point that reached the subject a moment ago
	# may not any more. A target that covers the subject completely leaves nothing
	# to pick up, and the case cannot be staged on this frame at all.
	var lift := _point_on(preview, preview.call("_sprite_rect",
		preview.call("_effective", _sprite_on(preview, carried))), carried)
	var land := _point_on(preview, target_rect, target)
	h.check("[%s] the drop target is reachable" % how, land.x >= 0.0,
		"channel %d, rect %s" % [target, str(target_rect)])
	h.check("[%s] the subject is still reachable under it" % how, lift.x >= 0.0,
		"channel %d under channel %d" % [carried, target])
	if land.x >= 0.0 and lift.x >= 0.0:
		if real:
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			_send(preview, lift, down)
			await preview.get_tree().process_frame
		else:
			preview.call("route_press", lift)
		h.check("[%s] the press latched the sprite that was pressed" % how,
			int(host.get("click_sprite")) == carried,
			"clickOn %d, wanted %d" % [int(host.get("click_sprite")), carried])
		if real:
			# The real drag: `InputRouter.mouse_motion` makes the position writes
			# itself off the event's own point.
			var move := InputEventMouseMotion.new()
			move.relative = _to_window(preview, land) - _to_window(preview, lift)
			_send(preview, land, move)
			await preview.get_tree().process_frame
			await preview.get_tree().process_frame
		else:
			# Exactly the two writes `InputRouter.mouse_motion` makes on each move.
			var carry: Vector2 = preview.get("_drag_offset")
			preview.call("lingo_set_sprite_prop", carried, "loch", int(land.x + carry.x))
			preview.call("lingo_set_sprite_prop", carried, "locv", int(land.y + carry.y))
		# The situation is real, and asserted rather than assumed: with the carried
		# sprite now under the pointer as well, the hit test must still answer the
		# *higher* channel, or there is nothing here to get wrong.
		h.check("[%s] the drop point answers the higher channel" % how,
			int(preview.call("_channel_at", land)) == target,
			"under the pointer: %d, wanted %d" % [
				int(preview.call("_channel_at", land)), target])
		if real:
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			_send(preview, land, up)
			await preview.get_tree().process_frame
		else:
			preview.call("route_release", land)
		h.check("[%s] the release did not hand `the clickOn` to the drop target" % how,
			int(host.get("click_sprite")) == carried,
			"clickOn %d, wanted %d (drop target %d)" % [
				int(host.get("click_sprite")), carried, target])
	# Put it back: what follows measures the rollover where the subject started,
	# and a sprite left sitting somewhere else changes what is there.
	preview.call("lingo_set_sprite_prop", carried, "loch", int(home.x))
	preview.call("lingo_set_sprite_prop", carried, "locv", int(home.y))


## Somewhere on the stage that is NOT inside `rect`, for the cancelled-click
## case. Walked outward along the four axes rather than picked at random, so a
## failure names a reproducible point.
func _point_off(preview: Node, rect: Rect2) -> Vector2:
	var stage := Vector2(preview.get("STAGE"))
	for candidate in [
		Vector2(rect.position.x - 20.0, rect.get_center().y),
		Vector2(rect.end.x + 20.0, rect.get_center().y),
		Vector2(rect.get_center().x, rect.position.y - 20.0),
		Vector2(rect.get_center().x, rect.end.y + 20.0),
	]:
		if candidate.x < 1.0 or candidate.y < 1.0:
			continue
		if candidate.x > stage.x - 1.0 or candidate.y > stage.y - 1.0:
			continue
		if not rect.has_point(candidate):
			return candidate
	return Vector2(-1, -1)


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

	preview.set("_index", _busiest_frame(preview))
	preview.set("_paused", true)
	var host: Object = preview.get("_host")

	# ------------------------------------------------------------------ §6
	# The properties first, because they are the cheapest thing to get wrong and
	# the hardest to notice: an unbound read is not an error, it is VOID, and VOID
	# is falsy. Every guard written against one silently takes its other branch.
	h.begin("§6: every mouse property answers something")
	var unbound: Array = []
	for prop in MOUSE_PROPS:
		if host.call("get_system_prop", prop) == null:
			unbound.append(prop)
	h.check("no mouse property reads back VOID", unbound.is_empty(),
		"unbound: %s" % str(unbound))
	# Not merely bound -- bound to the right thing. `the mouseH` that answers a
	# constant is bound, passes the check above, and is useless.
	var pointer: Vector2 = preview.call("stage_mouse")
	h.check("`the mouseH` / `the mouseV` follow the pointer",
		int(host.call("get_system_prop", "mouseh")) == int(pointer.x)
		and int(host.call("get_system_prop", "mousev")) == int(pointer.y),
		"host says (%s,%s), stage says %s" % [
			str(host.call("get_system_prop", "mouseh")),
			str(host.call("get_system_prop", "mousev")), str(pointer)])
	# `the mouseUp` is defined as the negation of `the mouseDown`, not as a
	# separate latch, so a port that binds one and invents the other drifts.
	h.check("`the mouseUp` is the exact negation of `the mouseDown`",
		int(host.call("get_system_prop", "mousedown"))
			!= int(host.call("get_system_prop", "mouseup")))
	h.complete("§6: every mouse property answers something")

	var found := _clickable(preview)
	h.begin("the frame offers a sprite the mouse can reach")
	if not h.check("one channel answers the hit test", not found.is_empty(),
			"frame %d" % (int(preview.get("_index")) + 1)):
		h.complete("the frame offers a sprite the mouse can reach")
		quit(h.finish("Director's mouse event vocabulary"))
		return
	h.complete("the frame offers a sprite the mouse can reach")
	var channel := int(found[0])
	var inside: Vector2 = found[1]
	var rect: Rect2 = found[2]
	var outside := _point_off(preview, rect)

	# ------------------------------------------------------------------ §8.1
	# The whole point of the two messages. A press that is released inside the
	# sprite is a click; a press released anywhere else is a click the player
	# cancelled, and running its handler anyway is the port doing something the
	# player explicitly declined.
	h.begin("§8.1: a click released inside the sprite sends mouseUp")
	var ups := _sent(preview, "mouseUp")
	preview.call("route_press", inside)
	h.check("the press alone sends no mouseUp", _sent(preview, "mouseUp") == ups,
		"mouseUp %d, was %d" % [_sent(preview, "mouseUp"), ups])
	preview.call("route_release", inside)
	h.check("the release sends exactly one", _sent(preview, "mouseUp") == ups + 1,
		"mouseUp %d, wanted %d" % [_sent(preview, "mouseUp"), ups + 1])
	h.complete("§8.1: a click released inside the sprite sends mouseUp")

	h.begin("§8.1: a click released outside it sends mouseUpOutSide instead")
	if not h.check("the stage has room for a point outside the sprite",
			outside.x >= 0.0, "rect %s" % str(rect)):
		h.complete("§8.1: a click released outside it sends mouseUpOutSide instead")
	else:
		ups = _sent(preview, "mouseUp")
		var outs := _sent(preview, "mouseUpOutSide")
		preview.call("route_press", inside)
		preview.call("route_release", outside)
		# The half that matters to a player, and the one that held for every
		# title until now: the handler for a cancelled click must not run.
		h.check("no mouseUp goes out", _sent(preview, "mouseUp") == ups,
			"mouseUp %d, wanted %d (released at %s, sprite %s)" % [
				_sent(preview, "mouseUp"), ups, str(outside), str(rect)])
		# The other half is only observable where the corpus declares the
		# handler, which no script in either title does -- so this is reported
		# rather than required. §6.5 confines it to sprite behaviours, and
		# `dispatch_sprite_only` refuses to send it anywhere else.
		print("      mouseUpOutSide dispatched: %s (no script in this corpus declares one)"
			% str(_sent(preview, "mouseUpOutSide") > outs))
		h.complete("§8.1: a click released outside it sends mouseUpOutSide instead")

	# The regression guard for the fix this was written alongside. A drop lands
	# the dragged sprite on a target, and a target drawn above it is the normal
	# case -- so an "is the pressed channel still topmost here" test would call
	# every successful drop a cancelled click and silently delete the corpus's
	# entire inventory idiom. The test is the pressed sprite's own rect.
	h.begin("a sprite that followed the cursor is still 'inside' at the drop")
	preview.call("lingo_set_sprite_prop", channel, "moveablesprite", 1)
	ups = _sent(preview, "mouseUp")
	preview.call("route_press", inside)
	var moved := inside + Vector2(24, 24)
	var offset: Vector2 = preview.get("_drag_offset")
	if int(preview.get("_drag_channel")) == channel:
		preview.call("lingo_set_sprite_prop", channel, "loch", int(moved.x + offset.x))
		preview.call("lingo_set_sprite_prop", channel, "locv", int(moved.y + offset.y))
	preview.call("route_release", moved)
	h.check("the drop sends mouseUp, not mouseUpOutSide",
		_sent(preview, "mouseUp") == ups + 1,
		"mouseUp %d, wanted %d" % [_sent(preview, "mouseUp"), ups + 1])
	h.complete("a sprite that followed the cursor is still 'inside' at the drop")

	# ------------------------------------------------------------------ §7.6
	# The drag's *other* ending. §7.6 gives two -- mouse-up, or the sprite ceasing
	# to be moveable -- and the port had only the first, so a script that cleared
	# `the moveableSprite` mid-gesture left the sprite following the cursor until
	# the button came up. Asserted on the position as well as on the channel,
	# because clearing `_drag_channel` and still writing this frame's position
	# would pass a channel-only check and look identical on screen.
	#
	# **Unexercised by the corpus**: all 15 `moveableSprite` writes across 7
	# titles set the flag to 1 and none clears it, so this is the reference's rule
	# rather than this title's need.
	h.begin("§7.6: the drag also ends when the sprite stops being moveable")
	preview.call("lingo_set_sprite_prop", channel, "moveablesprite", 1)
	preview.call("route_press", inside)
	if not h.check("the press started a drag",
			int(preview.get("_drag_channel")) == channel,
			"drag %d, wanted %d" % [int(preview.get("_drag_channel")), channel]):
		preview.call("route_release", inside)
	else:
		var held_h := int(preview.call("lingo_sprite_prop", channel, "loch"))
		var held_v := int(preview.call("lingo_sprite_prop", channel, "locv"))
		preview.call("lingo_set_sprite_prop", channel, "moveablesprite", 0)
		InputRouter.mouse_motion(preview, inside + Vector2(40, 40))
		h.check("the motion after it dropped the channel",
			int(preview.get("_drag_channel")) == 0,
			"drag %d, wanted 0" % int(preview.get("_drag_channel")))
		h.check("and did not carry the sprite with it",
			int(preview.call("lingo_sprite_prop", channel, "loch")) == held_h
			and int(preview.call("lingo_sprite_prop", channel, "locv")) == held_v,
			"loc (%d,%d), was (%d,%d)" % [
				int(preview.call("lingo_sprite_prop", channel, "loch")),
				int(preview.call("lingo_sprite_prop", channel, "locv")),
				held_h, held_v])
		# Setting the flag again must not resume it: the reference drops the
		# dragged channel outright rather than skipping one frame's write, so the
		# gesture is over and only a new press can start another.
		preview.call("lingo_set_sprite_prop", channel, "moveablesprite", 1)
		InputRouter.mouse_motion(preview, inside + Vector2(80, 80))
		h.check("restoring the flag does not resume the same gesture",
			int(preview.get("_drag_channel")) == 0,
			"drag %d, wanted 0" % int(preview.get("_drag_channel")))
		preview.call("route_release", inside)
	h.complete("§7.6: the drag also ends when the sprite stops being moveable")

	# ------------------------------------------------------------------ §15
	h.begin("§15: `the clickOn` updates on mouse-down, and on mouse-up over a sprite")
	preview.call("route_press", inside)
	h.check("the press latches it", int(host.get("click_sprite")) == channel,
		"clickOn %d, wanted %d" % [int(host.get("click_sprite")), channel])
	preview.call("route_release", inside)
	h.check("a release over the same sprite leaves it alone",
		int(host.get("click_sprite")) == channel,
		"clickOn %d, wanted %d" % [int(host.get("click_sprite")), channel])
	if outside.x >= 0.0 and int(preview.call("_channel_at", outside)) == 0:
		preview.call("route_press", inside)
		preview.call("route_release", outside)
		# "Only when the release was over a sprite" is the whole clause. Over
		# bare stage it must not be cleared, or `sprite the clickOn` -- which is
		# how every drop in the corpus asks its question -- names channel 0.
		h.check("a release over bare stage does not clear it",
			int(host.get("click_sprite")) == channel,
			"clickOn %d, wanted %d" % [int(host.get("click_sprite")), channel])
	h.complete("§15: `the clickOn` updates on mouse-down, and on mouse-up over a sprite")

	# ------------------------------------------------------------------ §4.5
	# Two channels, two questions. `_hover_channel` is what a click would reach;
	# `_rollover_channel` is what the pointer is over. They differ over any
	# sprite that is visible and not clickable -- which is most of a room.
	h.begin("§4.5: rollOver is a rect test, and is not the hit test")
	preview.call("track_rollover", inside)
	var rolled := int(preview.get("_rollover_channel"))
	h.check("the pointer is over something", rolled > 0)
	h.check("`rollOver()` with no argument answers a channel, not a boolean",
		int(host.call("call_builtin", "rollover", [])) == rolled,
		"rollOver() %s, _rollover_channel %d" % [
			str(host.call("call_builtin", "rollover", [])), rolled])
	# Shape, not value. `rollOver(n)` is measured against the **live pointer**
	# and headless Godot has none, so demanding 1 here would be demanding that
	# an absent mouse be over the sprite. The windowed stage below warps a real
	# pointer onto it and asserts the value.
	var one_arg: int = int(host.call("call_builtin", "rollover", [rolled]))
	h.check("`rollOver(n)` with an argument answers a boolean",
		one_arg == 0 or one_arg == 1, "rollOver(%d) = %d" % [rolled, one_arg])
	# The filter is the difference, and it has a direction: every clickable
	# sprite is rolled over, and not every rolled-over sprite is clickable.
	var covered := 0
	for raw in _sprites(preview):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		if not Interaction.responds_to_mouse(preview, sprite, preview.get("_table")):
			covered += 1
	print("      %d of %d sprites on this frame are rolled over but not clickable"
		% [covered, _sprites(preview).size()])
	h.complete("§4.5: rollOver is a rect test, and is not the hit test")

	# ------------------------------------------------------------------ §6.5
	# The inverse assertion, and the one that protects the frame rate. A movie
	# script fallback on these would run a handler for every sprite on the stage
	# on every tick, and the first symptom would be a room that runs at 4fps for
	# no reason anybody could find.
	h.begin("§6.5: sprite-local messages never reach a frame or movie script")
	var within_before := _sent(preview, "mouseWithin")
	var enter_before := _sent(preview, "mouseEnter")
	preview.set("_paused", false)
	for i in 20:
		await process_frame
	preview.set("_paused", true)
	h.check("20 ticks over a sprite with no such behaviour send no mouseWithin",
		_sent(preview, "mouseWithin") == within_before,
		"mouseWithin %d, was %d" % [_sent(preview, "mouseWithin"), within_before])
	# The crossing itself still has to happen, or the absence above proves
	# nothing. Driven through `track_rollover`, which is what a pointer move
	# calls, and asserted on the channel rather than on a handler.
	preview.call("track_rollover", Vector2(-100, -100))
	h.check("leaving every sprite clears the rollover channel",
		int(preview.get("_rollover_channel")) == 0)
	preview.call("track_rollover", inside)
	h.check("re-entering finds it again",
		int(preview.get("_rollover_channel")) == rolled)
	h.check("no mouseEnter was dispatched to a movie script either",
		_sent(preview, "mouseEnter") == enter_before,
		"mouseEnter %d, was %d" % [_sent(preview, "mouseEnter"), enter_before])
	h.complete("§6.5: sprite-local messages never reach a frame or movie script")

	# ------------------------------------------------------------------ §8.1 D5
	h.begin("§8.1: the right button sends its own pair")
	var rd := _sent(preview, "rightMouseDown")
	var ru := _sent(preview, "rightMouseUp")
	var dragging := int(preview.get("_drag_channel"))
	preview.call("route_right_button", inside, true)
	preview.call("route_right_button", inside, false)
	h.check("rightMouseDown and rightMouseUp both go out",
		_sent(preview, "rightMouseDown") == rd + 1
		and _sent(preview, "rightMouseUp") == ru + 1,
		"down %d/%d, up %d/%d" % [
			_sent(preview, "rightMouseDown"), rd + 1,
			_sent(preview, "rightMouseUp"), ru + 1])
	# §7.6's drag and §9.2's wait are the left button's. A right-click that
	# cancelled a drag would be this port inventing behaviour.
	h.check("it does not touch the drag",
		int(preview.get("_drag_channel")) == dragging)
	h.complete("§8.1: the right button sends its own pair")

	# ------------------------------------------------------------------ §6 timing
	h.begin("§6: the click clock — clickLoc, lastClick, doubleClick")
	preview.call("route_press", inside)
	preview.call("route_release", inside)
	var loc: Variant = host.call("get_system_prop", "clickloc")
	h.check("`the clickLoc` is the point that was pressed",
		typeof(loc) == TYPE_ARRAY and int(loc[0]) == int(inside.x)
		and int(loc[1]) == int(inside.y),
		"clickLoc %s, pressed %s" % [str(loc), str(inside)])
	h.check("`the lastClick` is a small number of ticks, not a timestamp",
		int(host.call("get_system_prop", "lastclick")) < 60,
		"lastClick %s" % str(host.call("get_system_prop", "lastclick")))
	# Two presses back to back are inside any plausible double-click interval.
	preview.call("route_press", inside)
	h.check("a second press straight after the first is a double click",
		int(host.call("get_system_prop", "doubleclick")) == 1)
	preview.call("route_release", inside)
	# ...and one after the interval has passed is not. Faked by moving the
	# recorded timestamp rather than by sleeping, because a harness that waits
	# half a second per assertion is a harness nobody runs.
	host.set("last_click_ms", Time.get_ticks_msec() - (Interaction.DOUBLE_CLICK_MS + 50))
	preview.call("route_press", inside)
	h.check("a press after the interval is not",
		int(host.call("get_system_prop", "doubleclick")) == 0)
	preview.call("route_release", inside)
	h.complete("§6: the click clock — clickLoc, lastClick, doubleClick")

	# The drop check goes **last**, after the real-pointer section below rather
	# than before it, and that ordering is load-bearing: staging a drop is
	# destructive. It makes a second sprite eligible, carries one sprite across
	# the stage, and sends a genuine `mouseDown`/`mouseUp` pair into whatever the
	# movie has attached to the two channels -- which in DAY1 is
	# `BehaviorScript 52` itself, a handler that moves sprites and swaps members
	# of its own accord. Placed before the rollover checks it moved their subject
	# out from under them, and cost three failures that were the harness's.
	var windowed := DisplayServer.get_name() != "headless"

	# ------------------------------------------------------------- real pointer
	# Everything above drives the routing directly, which is the only way to
	# assert it -- but it proves the routing and not the wiring. `_input` is
	# reached by a real event, and headless Godot has no pointer to make one
	# with, so a run that skips this has not shown that moving the mouse does
	# anything at all. Same trap `tools/window_renders.gd` documents.
	if not windowed:
		print("")
		print("windowed stage skipped: run without --headless to drive a real pointer")

	if windowed:
		h.begin("a real pointer move updates the rollover channel through `_input`")
		preview.set("_paused", false)
		var to_screen: Transform2D = (
			preview.get_viewport().get_screen_transform()
			* preview.get_global_transform_with_canvas()
		)
		# Away first, so the move onto the sprite is a genuine crossing rather than
		# a no-op from wherever the OS left the pointer.
		Input.warp_mouse(to_screen * Vector2(4, 4))
		for i in 4:
			await process_frame
		Input.warp_mouse(to_screen * inside)
		for i in 4:
			await process_frame
		h.check("the pointer landed on the sprite",
			int(preview.get("_rollover_channel")) == rolled,
			"rollover %d, wanted %d" % [int(preview.get("_rollover_channel")), rolled])
		h.check("`the mouseH` / `the mouseV` agree with where it landed",
			absf(float(host.call("get_system_prop", "mouseh")) - inside.x) < 3.0
			and absf(float(host.call("get_system_prop", "mousev")) - inside.y) < 3.0,
			"host (%s,%s), wanted %s" % [
				str(host.call("get_system_prop", "mouseh")),
				str(host.call("get_system_prop", "mousev")), str(inside)])
		h.check("`the lastRoll` is a small number of ticks",
			int(host.call("get_system_prop", "lastroll")) < 120,
			"lastRoll %s" % str(host.call("get_system_prop", "lastroll")))
		# The value `rollOver(n)` could not be asserted headlessly, now that there
		# is a pointer for it to be measured against.
		h.check("`rollOver(n)` is true of the sprite the pointer is on",
			int(host.call("call_builtin", "rollover", [rolled])) == 1,
			"rollOver(%d) = %s" % [
				rolled, str(host.call("call_builtin", "rollover", [rolled]))])
		h.complete("a real pointer move updates the rollover channel through `_input`")

	# ------------------------------------------------------------- §15, the drop
	# The half of `the clickOn` a single subject cannot show: a release that lands
	# over a **higher** channel than the one that was pressed. See
	# `_drop_over_a_higher_channel` for the rule and what breaking it did to the
	# corpus's inventory.
	#
	# The playhead is stopped for both. The score keeps running across every
	# `await` above, and a frame change moves the two subjects out from under the
	# measurement -- which reads as the check failing when it is the harness
	# measuring a different frame.
	preview.set("_paused", true)
	h.begin("§15: `the clickOn` survives a release over a higher channel")
	await _drop_over_a_higher_channel(preview, h, host, channel, false)
	h.complete("§15: `the clickOn` survives a release over a higher channel")

	if windowed:
		# ...and again all the way in through `_input`: press, carry and release
		# are all `Input.parse_input_event`, so what is checked is the path a
		# player has rather than the path a harness has.
		h.begin("a real drop over a higher channel leaves `the clickOn` alone")
		await _drop_over_a_higher_channel(preview, h, host, channel, true)
		h.complete("a real drop over a higher channel leaves `the clickOn` alone")

	quit(h.finish("Director's mouse event vocabulary"))
