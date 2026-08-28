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
## For the one line that says what a click resolved to, rather than a second
## spelling of it here: the printed line, the copied line and the line a failure
## message quotes are one string (`preview/snapshot.gd`).
const Snapshot := preload("res://scenes/preview/snapshot.gd")

## §8.1's input events, and §6's mouse properties. Listed rather than tested one
## by one so that adding a name to the engine without adding it here is visible
## as a shorter list, not as a silently absent check.
const MOUSE_PROPS := [
	"mouseh", "mousev", "mouseloc", "clickon", "clickloc", "mousedown", "mouseup",
	"rightmousedown", "rightmouseup", "stilldown", "doubleclick",
	"lastclick", "lastroll", "lastevent", "lastkey", "mousecast", "mousemember",
	"shiftdown", "optiondown", "commanddown", "controldown",
	"mousedownscript", "mouseupscript",
]

## Every string §4.3's six clauses can answer with, listed for the same reason
## the properties above are: a clause renamed or a seventh invented shows up here
## as an unrecognised answer rather than as a check that quietly stopped
## covering something.
const CLAUSES := [
	"moveable",
	"button member",
	"movie member with scripts enabled",
	"D6+ behaviour attached",
	"behaviour declares mouseDown/mouseUp",
	"generic behaviour, no handler scope",
	"member script declares mouseDown/mouseUp",
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


## `[frame, channel, point]` for a sprite the hit test reaches **whose own
## authored behaviour declares a mouse handler**, or `[]`.
##
## The subject `_clickable` finds is the one the *mouse* can reach, and on most
## frames it is eligible through §4.3's other clauses -- a `moveableSprite` this
## harness set itself, in the fallback. That is the right subject for the message
## vocabulary and the wrong one for the question below it, which is about the
## *recipient*: does a click on a sprite carrying a real `on mouseUp` reach that
## behaviour, or does it fall through to the frame script?
##
## Found rather than named, and it is found in every title: 270 (frame, channel)
## pairs in `piposh2`'s `strtgame.dir` (the gate's own root) and 216 in
## `piposh-dream`'s `eat.dir`.
func _authored_behaviour(preview: Node) -> Array:
	var score = preview.get("_score")
	var was := int(preview.get("_index"))
	var pixels: bool = preview.get("_hit_pixels")
	# Whole-rect for the search only, as `snapshot_check` does: decoding artwork
	# for every candidate over a thousand frames is minutes, which reads as a hung
	# harness rather than a slow one.
	preview.set("_hit_pixels", false)
	var found: Array = []
	for index in mini(int(score.frame_count), 1400):
		preview.set("_index", index)
		for raw in preview.call("frame_sprites"):
			var sprite: Dictionary = preview.call("_effective", raw)
			if sprite.is_empty():
				continue
			var channel := int(sprite["channel"])
			var behaviour: Dictionary = preview.call("_sprite_script", channel, index)
			if not Interaction.declares_mouse_handler(
					behaviour, preview.get("_interpreter")):
				continue
			var rect: Rect2 = preview.call("_sprite_rect", sprite)
			if rect.size.x < 8.0 or rect.size.y < 8.0:
				continue
			var at := _point_on(preview, rect, channel)
			if at.x < 0.0:
				continue
			found = [index, channel, at, str(behaviour.get("script", "?"))]
			break
		if not found.is_empty():
			break
	preview.set("_hit_pixels", pixels)
	if found.is_empty():
		preview.set("_index", was)
	return found


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
	var stage := Vector2(preview.call("stage_size"))
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
## §15: `the clickOn` is rewritten from the sprite under the **release**, and the
## `mouseUp` chain is built from that same sprite. **The two are asserted
## together in one scenario and that is the point of the scenario** -- either
## alone makes one dispatch give two answers to "which sprite is this about", and
## the clause was taken alone once and reverted for exactly that.
##
## This used to assert the opposite: that the press's channel survived the
## release. It was the honest check of a deliberate divergence, and the
## divergence is gone.
##
## What makes it safe is not asserted here because no synthetic frame can carry
## it: the corpus's drop idiom (`MASTER/External/BehaviorScript 52` on all eight
## of DAY1's inventory slots, eleven near-copies elsewhere) always drops onto a
## **lower** channel -- `intersects 100` is Pip's head, 103-110 are the slots --
## so the dragged sprite is the topmost answer and the rewrite names it. This
## harness stages the opposite on purpose, because the case where the two
## readings differ is the case worth pinning.
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
		h.check("[%s] the release handed `the clickOn` to the drop target" % how,
			int(host.get("click_sprite")) == target,
			"clickOn %d, wanted %d (pressed %d)" % [
				int(host.get("click_sprite")), target, carried])
		# ...while §15's *other* latch did not move with it. The cast element of
		# the mouse-up chain resolves against the member the mouse-DOWN landed on,
		# so the two are deliberately about different sprites: `the clickOn` names
		# the release, `_press_member` still names the press. A port that let the
		# release rewrite both would have lost the cast-targeting rule to the
		# clickOn one without anything saying so.
		var pressed_member: Dictionary = preview.get("_press_member")
		var carried_now: Dictionary = preview.call("_effective", _sprite_on(preview, carried))
		h.check("[%s] but the mouse-up's cast element still names the press" % how,
			not carried_now.is_empty()
			and int(pressed_member.get("id", -1)) == int(carried_now["cast_id"]),
			"press member %s, pressed sprite shows %s" % [
				str(pressed_member.get("id", -1)),
				str(carried_now.get("cast_id", -1))])
	# Put it back: what follows measures the rollover where the subject started,
	# and a sprite left sitting somewhere else changes what is there.
	preview.call("lingo_set_sprite_prop", carried, "loch", int(home.x))
	preview.call("lingo_set_sprite_prop", carried, "locv", int(home.y))


## Somewhere on the stage that is NOT inside `rect`, for the cancelled-click
## case. Walked outward along the four axes rather than picked at random, so a
## failure names a reproducible point.
func _point_off(preview: Node, rect: Rect2) -> Vector2:
	var stage := Vector2(preview.call("stage_size"))
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


## §4.3, the six eligibility clauses and the order they are tested in.
##
## The subject for the clause that matters is **synthesised**, and it has to be.
## The clause is "from D6 a sprite with any behaviour attached is a click target
## whatever that behaviour declares", so proving it needs a sprite whose
## behaviour declares no mouse handler -- and whether the movie under test has
## one is a property of the movie. The boot movie of this corpus has four
## behaviours and all four declare `mouseUp`, so a harness that went looking
## would assert nothing here and pass, which is the failure mode `gate.sh`'s
## empty-check guard exists for and would not catch, because the other checks in
## this block do have subjects.
##
## So a behaviour is *attached*: a frame-script interval is borrowed from the
## score (every movie has one, and this corpus's declare `exitFrame` and nothing
## else), verified to declare no mouse handler, and pushed onto the interval list
## as a sprite interval on a channel that is currently ineligible. That makes the
## subject the engine's own data structure rather than a mock, and it makes the
## check run identically against any `--root`. The interval is removed again, and
## the sprite going back to ineligible is itself asserted -- an attach that could
## not be undone would leave every later block measuring a different frame.
func _check_eligibility(preview: Node, h, subject: int) -> void:
	h.begin("§4.3: eligibility is six clauses, tested in order")
	var table = preview.get("_table")
	var score = preview.get("_score")
	var index := int(preview.get("_index"))

	# The predicate and the explanation are one function (`responds_to_mouse` is
	# `eligibility_reason() != ""`), and this is what keeps them one: the hit test
	# filters on the first and every debugging tool prints the second, so a port
	# where they can disagree is a port whose overlay lies.
	var disagreed := 0
	var unknown := PackedStringArray()
	var reasons: Dictionary = {}
	for raw in _sprites(preview):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		var why := Interaction.eligibility_reason(preview, sprite, table)
		if (why != "") != bool(Interaction.responds_to_mouse(preview, sprite, table)):
			disagreed += 1
		if why == "":
			continue
		reasons[why] = int(reasons.get(why, 0)) + 1
		if not CLAUSES.has(why):
			unknown.append(why)
	h.check("the verdict and the clause never disagree", disagreed == 0,
		"%d sprites" % disagreed)
	h.check("every clause named is one of §4.3's six", unknown.is_empty(),
		", ".join(unknown))
	print("      clauses on this frame: %s" % str(reasons))

	# The version gate. `is_d6_plus` is the whole switch between the D6+ clause
	# and the handler search below it, so it is asserted against the movie's own
	# config word rather than trusted.
	var config = preview.get("_config")
	var version := int(config.version) if config != null else 0
	h.check("the D6+ clause is gated on the movie's stated file version",
		Interaction.is_d6_plus(preview) == (version >= Interaction.FILE_VERSION_D6),
		"config version 0x%X, D6 threshold 0x%X" % [version, Interaction.FILE_VERSION_D6])

	# **The subject for the two experiments below is an ineligible sprite, and
	# never the one the rest of this harness clicks.** `_clickable` reaches its
	# subject by setting `the moveableSprite`, so making that channel eligible and
	# ineligible again to prove a clause takes the frame's only mouse target away
	# from every block after this one -- measured: the release-outside case then
	# saw `_press_channel` 0 and sent a `mouseUp` where it wanted
	# `mouseUpOutSide`, and the failure named the message rather than the cause.
	var victim := 0
	var victim_area := 0.0
	for raw in _sprites(preview):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty() or int(sprite["channel"]) == subject:
			continue
		if Interaction.responds_to_mouse(preview, sprite, table):
			continue
		var r: Rect2 = preview.call("_sprite_rect", sprite)
		if r.size.x * r.size.y > victim_area:
			victim_area = r.size.x * r.size.y
			victim = int(sprite["channel"])
	if not h.check("the frame has an ineligible sprite to experiment on", victim > 0):
		h.complete("§4.3: eligibility is six clauses, tested in order")
		return

	# Clause 1 is first, and "first" is the whole content of the ordering: a
	# moveable sprite is eligible before anything is asked about its scripts.
	preview.call("lingo_set_sprite_prop", victim, "moveablesprite", 1)
	h.check("clause 1: a moveable sprite reports `moveable` and asks nothing else",
		Interaction.eligibility_reason(
			preview, preview.call("_effective", _sprite_on(preview, victim)), table
		) == "moveable")
	preview.call("lingo_set_sprite_prop", victim, "moveablesprite", 0)
	h.check("and clearing it makes the sprite transparent to the mouse again",
		not bool(Interaction.responds_to_mouse(
			preview, preview.call("_effective", _sprite_on(preview, victim)), table)))

	# Clause 4 itself, on a borrowed behaviour.
	var donor: Dictionary = {}
	for value in score.intervals():
		var interval: Dictionary = value
		if str(interval["kind"]) != "frame":
			continue
		var script: Dictionary = preview.call("_script_in_lib",
			int(interval["script_cast_lib"]), int(interval["script_member"]))
		if script.is_empty() or not (script.get("body", []) as Array).is_empty():
			continue
		if preview.call("_declares_mouse_handler", script):
			continue
		donor = interval
		break
	if not h.check("the movie has a script that declares no mouse handler to attach",
			not donor.is_empty()):
		h.complete("§4.3: eligibility is six clauses, tested in order")
		return
	var attached := {
		"kind": "sprite", "channel": victim, "start": 0, "end": 0x7FFFFFFF,
		"script_cast_lib": int(donor["script_cast_lib"]),
		"script_member": int(donor["script_member"]),
	}
	score.intervals().append(attached)
	var reason: String = Interaction.eligibility_reason(
		preview, preview.call("_effective", _sprite_on(preview, victim)), table)
	if Interaction.is_d6_plus(preview):
		h.check("clause 4: a behaviour declaring no mouse handler still makes it a click target",
			reason == "D6+ behaviour attached", "channel %d reports `%s`" % [victim, reason])
		# The half that makes the check mean something. If the behaviour declared
		# `mouseDown` or `mouseUp` the D4/D5 arm would answer too, and the clause
		# under test would be unproven; asserting the arm is silent is what says
		# the eligibility came from D6 and from nowhere else.
		h.check("and the D4/D5 handler search below it says no",
			not bool(preview.call("_declares_mouse_handler", preview.call("_script_in_lib",
				int(donor["script_cast_lib"]), int(donor["script_member"])))))
		# §4.2: an eligible sprite stops the descent. That is the cost of the
		# clause and the reason it was measured before it was written, so it is
		# asserted rather than assumed.
		var r: Rect2 = preview.call("_sprite_rect",
			preview.call("_effective", _sprite_on(preview, victim)))
		var at := _point_on(preview, r, victim)
		h.check("and the descent now stops on it", at.x >= 0.0,
			"channel %d, %dx%d" % [victim, int(r.size.x), int(r.size.y)])
	else:
		h.check("clause 4 is off below D6: the attached behaviour changes nothing",
			reason == "", "channel %d reports `%s`" % [victim, reason])
	score.intervals().erase(attached)
	h.check("removing the behaviour hands the sprite back",
		not bool(Interaction.responds_to_mouse(
			preview, preview.call("_effective", _sprite_on(preview, victim)), table)))
	h.complete("§4.3: eligibility is six clauses, tested in order")


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

	var staged_frame := _busiest_frame(preview)
	preview.set("_index", staged_frame)
	preview.set("_paused", true)
	var host: Object = preview.get("_host")

	# ------------------------------------------------------------------ §6
	# The properties first, because they are the cheapest thing to get wrong and
	# the hardest to notice: an unbound read is not an error, it is VOID, and VOID
	# is falsy. Every guard written against one silently takes its other branch.
	# **`the mouseMember` is exempt, and it is the reference's own answer.**
	# `lingo-the.cpp:898-907` reads `getSpriteIDFromPos(pos)` and, when it is 0,
	# assigns `getVoid()` -- so VOID is what Director answers for a pointer over
	# nothing, not a symptom of an unbound name. This check could not tell those
	# apart and asserted the wrong one for it; every *other* property here is a
	# number or a string in every state, so the check keeps its teeth for them.
	#
	# It went red the day `the mouseMember` was bound to that descent
	# (`getSpriteIDFromPos`) instead of the click descent, which is when it first
	# became capable of answering VOID at all. A harness that reds for the arrival
	# of correct behaviour is the shape `porting-fidelity-verification` warns
	# about, so the fix is here rather than in the binding.
	const VOID_WHEN_OVER_NOTHING := ["mousemember"]
	h.begin("§6: every mouse property answers something")
	var unbound: Array = []
	for prop in MOUSE_PROPS:
		if prop in VOID_WHEN_OVER_NOTHING:
			continue
		if host.call("get_system_prop", prop) == null:
			unbound.append(prop)
	h.check("no mouse property but `the mouseMember` reads back VOID", unbound.is_empty(),
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

	_check_eligibility(preview, h, channel)

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
	# **Put the staged frame and the staged subject back.** Those twenty ticks are
	# the only place this file lets the movie move, and the movie moves: the
	# configured boot walks nine frames and rewrites the subject channel's whole
	# score record on the way, which is the score taking a `moveableSprite`
	# auto-puppet back -- §5.3, `Sprite::releaseAutoPuppet` on `kSCBMoveable`, and
	# correct. Every block below is staged on *this* channel at *this* frame and
	# read `pressed 0, wanted 8` without this: the subject is the harness's to
	# maintain, and re-staging it is not the same as asserting the release away.
	preview.set("_index", staged_frame)
	preview.call("lingo_set_sprite_prop", channel, "moveablesprite", 1)
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
	h.begin("§8.1: the right button sends its own pair, and latches like the left")
	var rd := _sent(preview, "rightMouseDown")
	var ru := _sent(preview, "rightMouseUp")
	var md := _sent(preview, "mouseDown")
	preview.call("route_right_button", inside, true)
	# §15's block runs at the primary tier for `rightMouseDown` exactly as for
	# `mouseDown`, so the press is latched and `the clickOn` is written. This used
	# to do none of it, on the recorded grounds that its five latches go in
	# together or not at all.
	h.check("the right press latches the channel it landed on",
		int(preview.get("_press_channel")) == channel,
		"pressed %d, wanted %d" % [int(preview.get("_press_channel")), channel])
	h.check("...and `the clickOn` with it",
		int(host.get("click_sprite")) == channel,
		"clickOn %d, wanted %d" % [int(host.get("click_sprite")), channel])
	h.check("...and the member the mouse-up will resolve against",
		not (preview.get("_press_member") as Dictionary).is_empty())
	preview.call("route_right_button", inside, false)
	h.check("rightMouseDown and rightMouseUp both go out",
		_sent(preview, "rightMouseDown") == rd + 1
		and _sent(preview, "rightMouseUp") == ru + 1,
		"down %d/%d, up %d/%d" % [
			_sent(preview, "rightMouseDown"), rd + 1,
			_sent(preview, "rightMouseUp"), ru + 1])
	# D5+: **only** the right-hand pair. A right click that also sent `mouseDown`
	# would be running every left-button handler in the movie a second time.
	h.check("and the left pair does not",
		_sent(preview, "mouseDown") == md,
		"mouseDown %d, was %d" % [_sent(preview, "mouseDown"), md])
	# The release block is the mirror: the drag it may have started is over.
	h.check("the right release ends the drag and the press",
		int(preview.get("_drag_channel")) == 0
		and int(preview.get("_press_channel")) == 0,
		"drag %d, press %d" % [
			int(preview.get("_drag_channel")), int(preview.get("_press_channel"))])
	h.complete("§8.1: the right button sends its own pair, and latches like the left")

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
	# The pair the answer is made of, asserted directly, because the two checks
	# above pass against a latched boolean as happily as against the pair and so
	# say nothing about which one is being read. `last_click_ms`'s setter is what
	# fills `last_click_ms2` (`preview_lingo_host.gd`), so a press path that
	# stopped going through the setter would show up here and nowhere else.
	var first := Time.get_ticks_msec()
	preview.call("route_press", inside)
	preview.call("route_release", inside)
	var second := Time.get_ticks_msec()
	preview.call("route_press", inside)
	preview.call("route_release", inside)
	h.check("two presses leave the *pair* of press times, not just the last one",
		int(host.get("last_click_ms2")) >= first
		and int(host.get("last_click_ms2")) <= second
		and int(host.get("last_click_ms")) >= second,
		"pair (%d, %d), presses at %d and >=%d" % [
			int(host.get("last_click_ms2")), int(host.get("last_click_ms")),
			first, second])
	h.complete("§6: the click clock — clickLoc, lastClick, doubleClick")

	_check_double_click(host, h)
	_check_last_event(host, h)

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

	await _check_live_button(preview, host, h)
	_check_authored_recipient(preview, h)
	quit(h.finish("Director's mouse event vocabulary"))


## **§4.5 row 1: `the doubleClick` is the last two press times compared on read,
## at 25 ticks.** `lingo-the.cpp:619-621`.
##
## The two checks in the click-clock section above pass against a latched boolean
## exactly as happily as against the pair, because both stage a *fresh* press and
## then read. These stage the states where the two readings disagree, which is
## the only way a check about this row can have teeth:
##
##   450 ms apart   27 ticks. Past the reference's 25, inside the 500 ms latch
##                  this replaced -- the whole band the port answered backwards.
##   400 ms apart,  24 ticks, asked 300 ms after the *second* press. The
##   asked late   answer stands until the next press in both engines, and this
##                  is the case the entry describes.
##   no press yet   0. A bare subtraction of two zeroed stamps is `0 <= 25` and
##                  reports a double-click into a session nobody has touched.
##   one press      0. The reference gets this from seeding `_lastClickTime` at
##                  load time; this port says it with -1.
##
## The timestamps are written straight into the host rather than produced by
## sleeping, which is the convention the section above already uses and the
## reason it is legitimate here: `last_click_ms`'s setter is the *only* way
## `last_click_ms2` is ever written, so a harness that sets the field exercises
## the same shift a press does. `double_click` -- the superseded latch -- is set
## to the *opposite* of the expected answer before each one, so a port still
## reading it fails rather than agreeing by luck.
func _check_double_click(host: Object, h) -> void:
	var case := "§4.5: `the doubleClick` is the last two press times, at 25 ticks"
	h.begin(case)

	var now := Time.get_ticks_msec()
	host.set("double_click", true)
	host.set("last_click_ms", now - 450)
	host.set("last_click_ms", now)
	h.check("450 ms apart is 27 ticks, so it is not a double click",
		int(host.call("get_system_prop", "doubleclick")) == 0,
		"doubleClick %s (latch says %s)" % [
			str(host.call("get_system_prop", "doubleclick")),
			str(host.get("double_click"))])

	now = Time.get_ticks_msec()
	host.set("double_click", false)
	host.set("last_click_ms", now - 700)
	host.set("last_click_ms", now - 300)
	h.check("400 ms apart is 24 ticks, and still answers 1 asked 300 ms later",
		int(host.call("get_system_prop", "doubleclick")) == 1,
		"doubleClick %s (latch says %s)" % [
			str(host.call("get_system_prop", "doubleclick")),
			str(host.get("double_click"))])

	host.set("double_click", true)
	host.set("last_click_ms", -1)
	host.set("last_click_ms2", -1)
	h.check("a session with no press in it is not in a double click",
		int(host.call("get_system_prop", "doubleclick")) == 0,
		"doubleClick %s" % str(host.call("get_system_prop", "doubleclick")))

	host.set("last_click_ms", Time.get_ticks_msec())
	host.set("last_click_ms2", -1)
	h.check("and neither is the first press of one",
		int(host.call("get_system_prop", "doubleclick")) == 0,
		"doubleClick %s" % str(host.call("get_system_prop", "doubleclick")))

	host.set("double_click", false)
	h.complete(case)


## **§4.5 row 4: `the lastEvent` counts the keyboard**, and row 5: `the lastKey`
## is bound and stamped.
##
## `events.cpp` writes `_lastEventTime` in three arms and only three -- the
## pointer move at `:185`, the button-down at `:266`, the key-down at `:369` --
## so the property is the smallest of three elapsed times and this port was
## taking the smallest of two. A title asking "has the player done anything" to
## drive an attract loop or a demo timer started it while somebody was typing.
##
## Row 5 is asserted **beside** it rather than on its own because the two share a
## timestamp: `the lastKey` reads `last_key_ms`, and the row above is that same
## number reaching `the lastEvent`. §4.5's table calls `the lastKey` unbound and
## reading VOID; it has been bound since `d9bc27e3`, the stamp rides on
## `key_code`'s setter, and this is where that stops being something a reader has
## to take on trust. `tools/key_polling.gd` pins the three *rules* about which
## keys stamp it.
##
## All three stamps are written directly. A harness that produced a ten-second
## gap by waiting ten seconds is a harness nobody runs, and the fields are the
## same ones a press and a roll write.
func _check_last_event(host: Object, h) -> void:
	var case := "§4.5: `the lastEvent` is the mouse *and* the keyboard"
	h.begin(case)

	# Ten seconds is 600 ticks: far enough outside the "just happened" window
	# below that no clock skew between the two reads can close the gap.
	#
	# **Clamped at 0, and the clamp is not cosmetic.** `Time.get_ticks_msec()` is
	# milliseconds since *this process* started, and a harness reaches here about
	# six seconds in -- so `now - 10000` is negative, and a negative
	# `last_click_ms` is this port's "no click has ever happened" sentinel. The
	# first version of these checks staged that by accident: `the lastClick` read
	# 2147483647 rather than 600, three of the four assertions passed through the
	# sentinel's arm instead of through the arithmetic they are about, and the
	# check that matters -- the keyboard reaching `the lastEvent` -- was the one
	# still doing real work only because `the lastRoll` has no such guard. 0 is a
	# real timestamp (the process starting), so the clamp stages a stale clock
	# rather than an absent one.
	const STALE_MS := 10000
	const RECENT_TICKS := 30
	var now := Time.get_ticks_msec()
	var stale := maxi(now - STALE_MS, 0)
	if not h.check("the session is old enough to stage a stale clock",
			int((now - stale) * 60.0 / 1000.0) > RECENT_TICKS,
			"%d ms of uptime is under %d ticks" % [now, RECENT_TICKS]):
		h.complete(case)
		return
	host.set("last_click_ms", stale)
	host.set("last_click_ms2", stale)
	host.set("last_roll_ms", stale)
	# The setter on `key_code` is the stamp -- see `preview_lingo_host.gd`. Going
	# through it rather than writing `last_key_ms` is deliberate: it is the wiring
	# a real keypress uses, and a port that moved the stamp elsewhere would pass a
	# direct write and fail here.
	host.set("key_code", 4)

	var last_key: Variant = host.call("get_system_prop", "lastkey")
	h.check("`the lastKey` answers ticks, not VOID",
		last_key != null and int(last_key) < RECENT_TICKS,
		"lastKey %s" % str(last_key))
	# The staleness is asserted in the same check as the answer. Without it a
	# `the lastClick` that had quietly become 0 -- or the sentinel, which is how
	# the first version of this passed -- would make "the key is the most recent
	# event" true of a clock where nothing was stale at all.
	h.check("a keypress is the most recent event, with the mouse stale",
		int(host.call("get_system_prop", "lastevent")) < RECENT_TICKS
		and int(host.call("get_system_prop", "lastclick")) > RECENT_TICKS
		and int(host.call("get_system_prop", "lastroll")) > RECENT_TICKS,
		"lastEvent %s, lastClick %s, lastRoll %s, lastKey %s" % [
			str(host.call("get_system_prop", "lastevent")),
			str(host.call("get_system_prop", "lastclick")),
			str(host.call("get_system_prop", "lastroll")), str(last_key)])
	# Not merely small -- the key's own age. A `the lastEvent` bound to a third
	# clock of its own would pass the check above and drift from every property
	# it is supposed to be the minimum of.
	h.check("...and it reads as the key's own age",
		absi(int(host.call("get_system_prop", "lastevent")) - int(last_key)) <= 1,
		"lastEvent %s, lastKey %s" % [
			str(host.call("get_system_prop", "lastevent")), str(last_key)])

	# The two arms that were already there, so that adding the third cannot have
	# been done by replacing one of them.
	now = Time.get_ticks_msec()
	host.set("last_key_ms", stale)
	host.set("last_roll_ms", now)
	h.check("a pointer move is still an event",
		int(host.call("get_system_prop", "lastevent")) < RECENT_TICKS,
		"lastEvent %s" % str(host.call("get_system_prop", "lastevent")))
	now = Time.get_ticks_msec()
	host.set("last_roll_ms", stale)
	host.set("last_click_ms", now)
	h.check("and so is a press",
		int(host.call("get_system_prop", "lastevent")) < RECENT_TICKS,
		"lastEvent %s" % str(host.call("get_system_prop", "lastevent")))
	h.complete(case)


## **§4.5 rows 2 and 3: what the two "is the button down" properties read.**
##
## They are one function because the assertion that separates them is the same
## staged state read twice, and because a port that binds them to one expression
## -- which this one did -- passes every check that reads only one of them.
##
##   `the mouseDown`   `getButtonState() & (LEFT | RIGHT)` (`lingo-the.cpp:865-871`).
##                     D5 splits the *messages* so a right press raises only
##                     `rightMouseDown`; it does not split the property.
##   `the stillDown`   `_vm->_wm->_mouseDown` (`:1135-1141`) -- the window
##                     manager's tracked down-state, left button, and **not** the
##                     score-step latch, because this is the property a
##                     `repeat while` inside a handler spins on.
##
## Three states, each of which one binding gets wrong:
##
##   latch set, no live button   `the mouseDown` 1 (the click-to-skip idiom this
##                               port added the latch for), `the stillDown` 0.
##   right button live           `the mouseDown` 1, `the mouseUp` 0. This is the
##                               row: the port read the left button alone.
##   nothing down                both 0, which is the state a green run would
##                               otherwise report by accident.
##
## **And the loop, which is the reason row 3 is the one to think hardest about.**
## `repeat while the stillDown` does not yield -- `lingo_interpreter.gd`'s
## `_repeat_while` runs to completion inside the frame that entered it -- so what
## moves the answer is `_breathe()`, once per iteration, reaching
## `director_preview.gd:lingo_breathe` and `DisplayServer.process_events()`. That
## is what writes `Input.is_mouse_button_pressed`, which is what the property now
## reads, so the two are the same read and the loop ends when the button does.
## Bound to the latch instead, the loop runs 31 spurious iterations before the
## first breathe clears `_mouse_down_seen` out from under it -- measured, not
## reasoned; see `_check_still_down_loop`, which is the assertion at the end here
## and which says why the number is 31 rather than the 400,000 it looks like.
func _check_live_button(preview: Node, host: Object, h) -> void:
	var case := "§4.5: `the mouseDown` takes either button, `the stillDown` takes no latch"
	h.begin(case)

	preview.set("_mouse_down_seen", false)
	await process_frame
	var live_left := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var live_right := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not h.check("no button is physically down to start with",
			not live_left and not live_right,
			"left %s, right %s -- let go of the mouse" % [str(live_left), str(live_right)]):
		h.complete(case)
		return
	h.check("nothing down: mouseDown 0, mouseUp 1, stillDown 0",
		int(host.call("get_system_prop", "mousedown")) == 0
		and int(host.call("get_system_prop", "mouseup")) == 1
		and int(host.call("get_system_prop", "stilldown")) == 0,
		_button_state(host))

	# The score-step latch on its own. `preview/frame_loop.gd:359` sets it from
	# the live left button once per engine tick and the score clears it a step
	# later, so this is the state a click shorter than one score step leaves
	# behind -- the whole reason the latch exists.
	preview.set("_mouse_down_seen", true)
	h.check("the score-step latch is `the mouseDown`, and is not `the stillDown`",
		int(host.call("get_system_prop", "mousedown")) == 1
		and int(host.call("get_system_prop", "mouseup")) == 0
		and int(host.call("get_system_prop", "stilldown")) == 0,
		_button_state(host))
	preview.set("_mouse_down_seen", false)

	# The right button, live, through the Input singleton -- which is where the
	# properties read it from, and which works headless (measured: the mask goes
	# to 2 and `is_mouse_button_pressed(RIGHT)` to true with no window at all).
	# The event is routed as well as recorded, exactly as a real right click is,
	# so the release below is not optional housekeeping.
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	down.button_mask = MOUSE_BUTTON_MASK_RIGHT
	_send(preview, Vector2(1.0, 1.0), down)
	await process_frame
	if h.check("the right button reads as physically down",
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			and int(host.call("get_system_prop", "rightmousedown")) == 1,
			_button_state(host)):
		h.check("the right button alone answers `the mouseDown`",
			int(host.call("get_system_prop", "mousedown")) == 1,
			_button_state(host))
		h.check("...and `the mouseUp` with it, as the exact negation",
			int(host.call("get_system_prop", "mouseup")) == 0,
			_button_state(host))
		# The reference's mask for `the stillDown` names no button at all; it
		# reads a Mac window manager's tracked flag, and the `LEFT | RIGHT` mask
		# is on `the mouseDown` and on nothing else.
		h.check("...and `the stillDown` does not, which is the left-only read",
			int(host.call("get_system_prop", "stilldown")) == 0,
			_button_state(host))
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	_send(preview, Vector2(1.0, 1.0), up)
	await process_frame
	h.check("the release puts all three back",
		int(host.call("get_system_prop", "mousedown")) == 0
		and int(host.call("get_system_prop", "mouseup")) == 1
		and int(host.call("get_system_prop", "rightmousedown")) == 0,
		_button_state(host))

	_check_still_down_loop(preview, h)
	h.complete(case)


## `mouseDown/mouseUp/stillDown/rightMouseDown` and the two things underneath
## them, as one line. Every failure message in `_check_live_button` is this,
## because "stillDown 1" alone never says which of the three inputs produced it.
func _button_state(host: Object) -> String:
	return "mouseDown %s  mouseUp %s  stillDown %s  rightMouseDown %s  (latch %s, live L %s R %s)" % [
		str(host.call("get_system_prop", "mousedown")),
		str(host.call("get_system_prop", "mouseup")),
		str(host.call("get_system_prop", "stilldown")),
		str(host.call("get_system_prop", "rightmousedown")),
		str(host.get("preview").get("_mouse_down_seen")) if host.get("preview") != null else "?",
		str(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)),
		str(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))]


## The player-visible half of row 3: **`repeat while the stillDown` terminates.**
##
## Staged in the state that separates the two readings -- the score-step latch
## set, no live button -- and run as real compiled Lingo through the movie's own
## interpreter, because the property being right in isolation is not the claim.
## The claim is that Director's drag idiom
##
##     on mouseDown
##       repeat while the stillDown
##         set the loc of sprite ... to the mouseLoc
##       end repeat
##     end
##
## is a loop over a live button and not a loop over a stale one.
##
## **It was worth measuring what the latched binding actually did, because the
## obvious answer is wrong.** No iteration of the loop can clear
## `_mouse_down_seen`, so the expectation is `MAX_STEPS` (400,000), an abort, and
## sixteen seconds with the message pump dead -- the failure
## `lingo_interpreter.gd:BREATHE_MS` was written about. Run with the arm
## reverted, it is **31 iterations, 0 faults, 1 ms**: `lingo_breathe` clears the
## latch on the same line it pumps the queue, so the loop leaves on the first
## test after the first breathe. The cost of the old binding was 31 spurious
## steps of a drag loop for a button that was never down, plus a silent
## dependence on that one courtesy line in a file this change does not own.
##
## So **only the counter discriminates**, and it is the check that matters: 0
## against 31. The two below it pass on the reverted arm as well and are said to
## be what they are -- a guard against the hang this turned out not to be, kept
## because a future edit to `lingo_breathe` or to `BREATHE_EVERY` is exactly what
## would turn 31 into 400,000, and because a harness that only counts iterations
## cannot tell "left on its own" from "was cut off".
func _check_still_down_loop(preview: Node, h) -> void:
	var interp = preview.get("_interpreter")
	if interp == null:
		print("      no interpreter on this movie; the stillDown loop is not staged")
		return
	preview.set("_mouse_down_seen", true)
	var errors: Array = []
	var code = interp.compile_statements(
		"global gStillSpins\n"
		+ "gStillSpins = 0\n"
		+ "repeat while the stillDown\n"
		+ "  gStillSpins = gStillSpins + 1\n"
		+ "end repeat\n", "mouse_events", errors)
	if not h.check("the `repeat while the stillDown` probe compiles",
			errors.is_empty(), str(errors)):
		preview.set("_mouse_down_seen", false)
		return
	var faults_before: int = int(interp.get("error_total"))
	var began := Time.get_ticks_msec()
	interp.reset_steps()
	interp.run_compiled(code)
	var took := Time.get_ticks_msec() - began
	preview.set("_mouse_down_seen", false)
	var spins: Variant = null
	for store in [interp.globals, (preview.get("_host") as Object).globals]:
		for key in (store as Dictionary).keys():
			if str(key).to_lower() == "gstillspins":
				spins = (store as Dictionary)[key]
	h.check("`repeat while the stillDown` exits on its first test with the latch set",
		spins != null and int(spins) == 0,
		"spun %s times (the latched binding spins 31)" % str(spins))
	# The two below do not discriminate -- see this function's note. They are the
	# hang guard, and they are here because the counter alone cannot tell a loop
	# that left from a loop that was cut off at `MAX_STEPS`.
	h.check("...raising no fault, so it left rather than being cut off (hang guard)",
		int(interp.get("error_total")) == faults_before,
		"faults %d, were %d" % [int(interp.get("error_total")), faults_before])
	h.check("...and inside a second, which a 400,000-step walk is not (hang guard)",
		took < 1000, "%d ms" % took)


## **The player-visible invariant: a click on a sprite whose behaviour declares
## `mouseUp` reaches that behaviour.**
##
## `tools/click_chain.gd` asserts the same rule against a behaviour it *compiles*
## into the score's own attachment, which is the right way to state §6.3's five
## tiers and their `pass` flag. What nothing asserted until now is the same thing
## on a movie's **own authored** behaviour, over the engine's real resolution path
## -- `interaction.gd:script_for_click` and `preview/scripts.gd:for_sprite`, keyed
## on the score's interval entries and resolved in the library the interval names.
## Any of those answering wrongly sends the click to the frame script, and the
## symptom is a hotspot that answers by doing nothing.
##
## That is what a player reported against `piposh-dream`'s `eat.dir`, where nine
## characters share `BehaviorScript 1:121`. The routing was right and the *report*
## was mislabelled (see `preview/snapshot.gd:note_click`), but the invariant had no
## gate on real data either way, so a real regression here would have read exactly
## the same from the player's chair.
##
## **The right button is asserted with it, and it is the same rule.** §4.3 makes a
## sprite with any D6+ behaviour a click target whatever that behaviour declares,
## so the descent stops here for a right click too -- and `script_for_click`
## resolves against the *pair* being sent, so a behaviour declaring only `mouseUp`
## must NOT answer `rightMouseUp` and the click falls to the frame. 0 of the six
## titles declare `rightMouseDown` or `rightMouseUp` anywhere, so a right click on
## an authored hotspot doing nothing is Director, not a fault. Asserting both
## directions is what keeps a future "make the right button work" change honest.
func _check_authored_recipient(preview: Node, h) -> void:
	var case := "a click on a sprite whose behaviour declares `mouseUp` reaches it"
	h.begin(case)
	var subject := _authored_behaviour(preview)
	if subject.is_empty():
		# Said out loud and asserted over nothing, which is this file's own
		# convention for a rule the loaded title cannot express (see
		# `mouseUpOutSide` above). Every title in this repo can: the smallest count
		# measured is 216 pairs.
		print("      no sprite in this movie carries an authored mouse behaviour the"
			+ " hit test reaches; the recipient rule is not stated here")
		h.complete(case)
		return
	var frame := int(subject[0])
	var channel := int(subject[1])
	var at: Vector2 = subject[2]
	var named := str(subject[3])
	print("      subject: frame %d, channel %d, %s" % [frame + 1, channel, named])

	var movie := str(preview.call("movie_name"))
	var ran := _ran(preview, "mouseUp@sprite")
	preview.call("route_press", at)
	# The press-time record, which is where the routing decision is: the tier and
	# the script `script_for_click` chose. Read before the release, because a
	# handler is allowed to navigate and this must not depend on it.
	var click: Dictionary = preview.get("_last_click")
	h.check("the press resolves to the sprite tier, not the frame",
		str(click.get("tier", "")) == "sprite",
		"tier %s, script %s" % [str(click.get("tier", "")), str(click.get("script", ""))])
	h.check("and to that sprite's own behaviour",
		str(click.get("script", "")) == named,
		"answered %s, wanted %s" % [str(click.get("script", "")), named])
	h.check("and the record says a handler for the message exists",
		bool(click.get("handler", false)), Snapshot.click_line(click))
	preview.call("route_release", at)
	# A `go to movie` inside the handler is proof the handler ran, and it also
	# takes the counters with it -- so the delta is asserted only where the movie
	# stood still, and the other case is reported rather than turned into a red.
	if str(preview.call("movie_name")) != movie:
		print("      the handler navigated to %s, which is itself proof it ran;"
			% str(preview.call("movie_name"))
			+ " the tally delta is not assertable across the jump")
	else:
		h.check("the behaviour's own `mouseUp` ran, at the sprite tier",
			_ran(preview, "mouseUp@sprite") == ran + 1,
			"mouseUp@sprite %d, wanted %d" % [_ran(preview, "mouseUp@sprite"), ran + 1])

	# The right pair on the same sprite. Only where the movie is still the one the
	# subject was found in; after a jump there is no such sprite to press.
	if str(preview.call("movie_name")) == movie:
		var right_ran := _ran(preview, "rightMouseUp@sprite")
		preview.call("route_right_button", at, true)
		var right_click: Dictionary = preview.get("_last_click")
		h.check("a right click on it does NOT resolve to the behaviour",
			str(right_click.get("tier", "")) != "sprite",
			Snapshot.click_line(right_click))
		preview.call("route_right_button", at, false)
		h.check("and no `rightMouseUp` handler ran at the sprite tier",
			_ran(preview, "rightMouseUp@sprite") == right_ran,
			"rightMouseUp@sprite %d, was %d" % [
				_ran(preview, "rightMouseUp@sprite"), right_ran])
	h.complete(case)


func _ran(preview: Node, key: String) -> int:
	return int((preview.get("_ran") as Dictionary).get(key, 0))
