extends SceneTree
## §6.3 tier 1: the four `*Script` properties, and the modifier word a key event
## carries with it.
##
##   godot --headless --script tools/primary_scripts.gd
##   godot --headless --script tools/primary_scripts.gd -- --root rating
##
## Three things that used to be true and are not, each of which failed silently:
##
## 1. **The `*Script` properties held a handler *name*.** Director's value is a
##    string of Lingo compiled on assignment, and the recorded reason for the
##    shortcut -- "this port has no runtime compile-a-string path" -- stopped
##    being true when `do` landed. A movie that assembled a fragment and assigned
##    it got a property that stored the fragment and ran nothing.
## 2. **`the shiftDown` and its three siblings asked the OS keyboard.** Not the
##    event: a chord released while the handler ran read as never held, and a
##    synthetic key event carrying `shift_pressed` could not make the property
##    true at all -- which is why nothing tested it and why this harness could
##    not have been written before the change it checks.
## 3. **A modifier key ran the whole `keyDown` chain.** §8.3 says shift, control,
##    alt and command are recorded and *not* dispatched; `fromnow`, installed by
##    46 scripts, was firing once for the shift of every shifted character.
##
## The `mouseUpScript` case is doing double duty and that is deliberate: it is
## the only way to observe **`the clickOn` from inside the mouse-up dispatch**,
## which is the half of §15 that had to land with the recipient rule. A property
## read from the harness afterwards cannot tell "rewritten before the dispatch"
## from "rewritten after it".
##
## Title-agnostic: it installs its own Lingo rather than looking for the movie's,
## so it asserts the engine and not this corpus. It still boots the real player,
## because a primary handler that runs outside a dispatch proves nothing about
## the tier it is supposed to be at.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const LingoHost := preload("res://scenes/preview_lingo_host.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")


func _key(code: Key, pressed := true, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	return event


## A stage point the hit test answers a sprite for, and that sprite's channel.
## `[Vector2, channel]`, or `[]` when this frame has nothing clickable on it.
##
## Eligibility is asked **first**, and cheaply, before any point is probed. The
## descent is O(sprites) per point and decodes artwork for a Matte sprite, so
## probing a grid over every sprite of every frame is minutes of work for an
## answer that one predicate rules out in microseconds. Highest channel first,
## because that is the only one a descent can answer with.
func _reachable(preview: Node) -> Array:
	var score = preview.get("_score")
	var table = preview.get("_table")
	if score == null or table == null:
		return []
	var sprites: Array = score.frame(int(preview.get("_index"))).get("sprites", [])
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = preview.call("_effective", sprites[i])
		if sprite.is_empty():
			continue
		if not Interaction.responds_to_mouse(preview, sprite, table):
			continue
		var rect: Rect2 = preview.call("_sprite_rect", sprite)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var channel := int(sprite["channel"])
		for row in 3:
			for column in 3:
				var at := rect.position + rect.size * Vector2(
					(column + 1) / 4.0, (row + 1) / 4.0)
				if int(preview.call("_channel_at", at)) == channel:
					return [at, channel]
	return []


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var _root := Args.text(args, "root", "")

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	if scene == null:
		print("no preview scene")
		quit(1)
		return
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	# Far enough in that the movie's own scripts have run, then **stopped**: a
	# score running underneath moves the sprite out from under the point being
	# clicked, and every check below drives its events by hand.
	for i in 60:
		preview.call("_advance")
	preview.set("_paused", true)
	# Then a frame with a sprite the descent actually answers. Walked over the
	# score by setting the playhead rather than by advancing it, because
	# `_advance` follows the movie's flow and an intro that holds on
	# `go to the frame` never leaves the frames it holds on -- this boot movie's
	# does, which is how the mouse half of this harness came to be skipped in
	# silence. `tools/mouse_events.gd` picks its subject the same way and for the
	# same reason.
	var found: Array = _reachable(preview)
	var subject_frame := int(preview.get("_index"))
	if found.is_empty():
		var score = preview.get("_score")
		for frame in (score.frame_count if score != null else 0):
			preview.set("_index", frame)
			found = _reachable(preview)
			if not found.is_empty():
				subject_frame = frame
				break
		preview.set("_index", subject_frame)

	var host: Object = preview.get("_host")
	var interp = preview.get("_interpreter")
	if host == null or interp == null:
		print("no lingo host")
		quit(1)
		return

	# ---------------------------------------------------------------- compiling
	#
	# The assignment is what compiles (`Movie::setPrimaryEventHandler` ->
	# `replaceCode`), so this is asserted on the *property write* rather than on
	# the first event: a port that compiled lazily would pass every behavioural
	# check below and still report a syntax error hours later, from inside an
	# event, with the assignment long gone from the log.
	h.begin("§6.3: a `*Script` property holds Lingo source and compiles on assignment")
	host.call("set_system_prop", "keydownscript", "global probe\nprobe = 41 + 1")
	h.check("the property reads back the source, not what it compiled to",
		str(host.call("get_system_prop", "keydownscript")) == "global probe\nprobe = 41 + 1",
		str(host.call("get_system_prop", "keydownscript")))
	h.check("and it compiled to something runnable",
		not (host.get("key_down_compiled") as Dictionary).is_empty(),
		JSON.stringify((host.get("key_down_compiled") as Dictionary).keys()))
	# A bare word is Lingo's no-argument call, so Director's own reading of
	# `"fromnow"` is a one-statement script. Both forms are carried on one record
	# and the name is preferred where it resolves -- see `_compile_primary`.
	host.call("set_system_prop", "keyupscript", "fromnow")
	h.check("a bare identifier is still recognised as a handler name",
		str((host.get("key_up_compiled") as Dictionary).get("name", "")) == "fromnow",
		JSON.stringify(host.get("key_up_compiled")))
	# Director reports a `do` that will not compile and carries on. So does this,
	# and the property that would not compile installs nothing rather than
	# installing half a script.
	host.call("set_system_prop", "mousedownscript", "set the = = of")
	h.check("a source that will not compile installs nothing",
		(host.get("mouse_down_compiled") as Dictionary).is_empty(),
		JSON.stringify(host.get("mouse_down_compiled")))
	host.call("set_system_prop", "mousedownscript", "")
	h.check("and the empty string removes the handler, as Director's does",
		(host.get("mouse_down_compiled") as Dictionary).is_empty())
	h.complete("§6.3: a `*Script` property holds Lingo source and compiles on assignment")

	# ---------------------------------------------------------------- the keyboard
	h.begin("§6.3 tier 1: `the keyDownScript` runs its source on a keypress")
	host.set("globals", host.get("globals"))
	interp.globals["probe"] = 0
	host.call("set_system_prop", "keydownscript", "global probe\nprobe = probe + 7")
	preview.call("_dispatch_key", _key(KEY_SPACE))
	h.check("the compiled statement ran, in the movie's own globals",
		int(interp.globals.get("probe", 0)) == 7,
		"probe = %s" % str(interp.globals.get("probe", 0)))
	var ran: Dictionary = preview.get("_ran")
	h.check("and it is tallied at tier 1",
		ran.has("keyDownScript:<source>"), JSON.stringify(ran.keys()))
	# §8.2: a primary handler **passes by default**. The whole chain below it runs
	# unless the source says otherwise, and inverting that is the classic bug.
	var sent_before := int((preview.get("_sent") as Dictionary).get("keyDown", 0))
	preview.call("_dispatch_key", _key(KEY_SPACE))
	h.check("a primary handler passes the event on by default",
		int((preview.get("_sent") as Dictionary).get("keyDown", 0)) == sent_before + 1,
		"keyDown sent %d, was %d" % [
			int((preview.get("_sent") as Dictionary).get("keyDown", 0)), sent_before])
	# ...and `dontPassEvent` in the source stops it. Written as source rather than
	# as a named handler on purpose: this is the case a handler name could never
	# have covered, because there is no handler to name.
	host.call("set_system_prop", "keydownscript", "dontPassEvent")
	sent_before = int((preview.get("_sent") as Dictionary).get("keyDown", 0))
	preview.call("_dispatch_key", _key(KEY_SPACE))
	h.check("`dontPassEvent` from the source stops the chain",
		int((preview.get("_sent") as Dictionary).get("keyDown", 0)) == sent_before,
		"keyDown sent %d, was %d" % [
			int((preview.get("_sent") as Dictionary).get("keyDown", 0)), sent_before])
	h.complete("§6.3 tier 1: `the keyDownScript` runs its source on a keypress")

	# ---------------------------------------------------------------- §8.3
	h.begin("§8.3: the modifier word is latched with the event, not read live")
	# The word is written by the router, which is where a real key event enters.
	# Driving `_dispatch_key` alone would bypass it -- and that is the divergence
	# this replaces: the four properties used to answer from
	# `Input.is_key_pressed`, which no synthetic event can move, so the value was
	# unassertable in either direction.
	InputRouter.key_event(preview, _key(KEY_A, true, true))
	h.check("`the shiftDown` is true for a keystroke that carried shift",
		int(host.call("get_system_prop", "shiftdown")) == 1,
		"shiftDown %s, flags %s" % [
			str(host.call("get_system_prop", "shiftdown")), str(host.get("key_flags"))])
	InputRouter.key_event(preview, _key(KEY_A, true, false))
	h.check("...and false for the next one that did not",
		int(host.call("get_system_prop", "shiftdown")) == 0,
		str(host.call("get_system_prop", "shiftdown")))
	h.check("the other three are independent booleans off the same word",
		int(host.call("get_system_prop", "optiondown")) == 0
		and int(host.call("get_system_prop", "commanddown")) == 0
		and int(host.call("get_system_prop", "controldown")) == 0)
	# §8.3: a modifier key records the word and dispatches nothing at all.
	var keydowns := int((preview.get("_sent") as Dictionary).get("keyDown", 0))
	var code_before := int(host.get("key_code"))
	InputRouter.key_event(preview, _key(KEY_SHIFT, true, true))
	h.check("a modifier key generates no keyDown event",
		int((preview.get("_sent") as Dictionary).get("keyDown", 0)) == keydowns,
		"keyDown sent %d, was %d" % [
			int((preview.get("_sent") as Dictionary).get("keyDown", 0)), keydowns])
	h.check("...and does not overwrite `the keyCode` with itself",
		int(host.get("key_code")) == code_before,
		"keyCode %d, was %d" % [int(host.get("key_code")), code_before])
	h.check("...but is recorded in the word",
		int(host.call("get_system_prop", "shiftdown")) == 1,
		str(host.get("key_flags")))
	InputRouter.key_event(preview, _key(KEY_SHIFT, false, false))
	h.check("and the release of it clears the bit",
		int(host.call("get_system_prop", "shiftdown")) == 0,
		str(host.get("key_flags")))
	h.complete("§8.3: the modifier word is latched with the event, not read live")

	# ---------------------------------------------------------------- timeoutKeyDown
	h.begin("§8.3: `the timeoutKeyDown` round-trips")
	# **On by default**, which is Director's value (`movie.cpp:92`). It was false
	# here while the property was an inert store, and false stopped being harmless
	# the moment the timeout clock landed: with the clock running, false means
	# typing does not count as the player being present, so an idle timeout fires
	# under someone who is typing. `tools/timeout_and_actors.gd` covers the clock
	# itself; this covers the round trip.
	h.check("it is on by default", int(host.call("get_system_prop", "timeoutkeydown")) == 1)
	host.call("set_system_prop", "timeoutkeydown", 0)
	h.check("a movie can turn it off and read it back",
		int(host.call("get_system_prop", "timeoutkeydown")) == 0)
	host.call("set_system_prop", "timeoutkeydown", 1)
	h.complete("§8.3: `the timeoutKeyDown` round-trips")

	# ---------------------------------------------------------------- the mouse
	host.call("set_system_prop", "keydownscript", "")
	# Back to the frame the subject was found on. A `keyDown` handler is entitled
	# to `go` somewhere, and a harness that measured its subject on one frame and
	# clicked it on another would report a hit-test failure that is its own.
	preview.set("_index", subject_frame)
	h.begin("§15: `the mouseUpScript` sees `the clickOn` naming the release")
	if found.is_empty():
		print("      this frame carries no reachable sprite; skipped")
		h.complete("§15: `the mouseUpScript` sees `the clickOn` naming the release")
	else:
		var at: Vector2 = found[0]
		var channel := int(found[1])
		interp.globals["downon"] = -1
		interp.globals["upon"] = -1
		# Real Lingo in both, which is the point: neither of these is a handler
		# this or any movie declares, so a port that stored a name would run
		# nothing and both globals would keep their sentinel.
		host.call("set_system_prop", "mousedownscript", "global downon\ndownon = the clickOn")
		host.call("set_system_prop", "mouseupscript", "global upon\nupon = the clickOn")
		preview.call("route_press", at)
		h.check("the mouseDownScript ran and read the press",
			int(interp.globals.get("downon", -1)) == channel,
			"downOn %s, wanted %d" % [str(interp.globals.get("downon", -1)), channel])
		preview.call("route_release", at)
		# §15's clause, observed *from inside the dispatch* rather than after it.
		# Reading the property from here afterwards cannot tell a rewrite that
		# happened before the mouse-up from one that happened after.
		h.check("the mouseUpScript ran and `the clickOn` was already the release's",
			int(interp.globals.get("upon", -1)) == channel,
			"upOn %s, wanted %d" % [str(interp.globals.get("upon", -1)), channel])
		var tally: Dictionary = preview.get("_ran")
		h.check("both are tallied at tier 1",
			tally.has("mouseDownScript:<source>") and tally.has("mouseUpScript:<source>"),
			JSON.stringify(tally.keys()))
		h.complete("§15: `the mouseUpScript` sees `the clickOn` naming the release")

		# The right button reaches the same five latches and **no `*Script`**:
		# Director files a primary handler under the event it was installed for
		# and the language spells no `rightMouseDownScript`.
		h.begin("§15: a right click latches, and runs no `*Script`")
		interp.globals["downon"] = -1
		interp.globals["upon"] = -1
		# The click above ran the movie's own `on mouseUp`, which is entitled to
		# have gone somewhere or hidden what it was on -- `mouseUp@sprite` in the
		# tally above is a real behaviour running. So the subject is re-pinned and
		# re-found rather than reused; a right click aimed at where a sprite used
		# to be would fail this as a latching bug when it is a stale coordinate.
		preview.set("_index", subject_frame)
		var again := _reachable(preview)
		if not again.is_empty():
			at = again[0]
			channel = int(again[1])
		preview.call("route_right_button", at, true)
		h.check("the right press latched `the clickOn`",
			int(host.get("click_sprite")) == channel,
			"clickOn %d, wanted %d" % [int(host.get("click_sprite")), channel])
		h.check("...and the press channel with it",
			int(preview.get("_press_channel")) == channel)
		preview.call("route_right_button", at, false)
		h.check("the mouseDownScript did not run for it",
			int(interp.globals.get("downon", -1)) == -1,
			"downOn %s, wanted -1" % str(interp.globals.get("downon", -1)))
		h.check("nor the mouseUpScript",
			int(interp.globals.get("upon", -1)) == -1,
			"upOn %s, wanted -1" % str(interp.globals.get("upon", -1)))
		h.check("and the release cleared the press",
			int(preview.get("_press_channel")) == 0
			and int(preview.get("_drag_channel")) == 0)
		h.complete("§15: a right click latches, and runs no `*Script`")

	# ---------------------------------------------------------------- §15 the beep
	#
	# `the beepOn` gates the empty-stage click and nothing else -- `LB::b_beep`
	# never asks it -- and it is off by default, which is the reference's default
	# and the original's. Both halves matter: with the old `true` default every
	# click that missed a hotspot would beep, and most of this game's stage is
	# ineligible backdrop.
	h.begin("§15: `the beepOn` is off by default and gates the empty-stage click")
	h.check("off by default", int(host.call("get_system_prop", "beepon")) == 0,
		str(host.call("get_system_prop", "beepon")))
	host.call("set_system_prop", "beepon", 1)
	h.check("a movie can turn it on", int(host.call("get_system_prop", "beepon")) == 1)
	host.call("set_system_prop", "beepon", 0)
	h.complete("§15: `the beepOn` is off by default and gates the empty-stage click")

	host.call("set_system_prop", "mousedownscript", "")
	host.call("set_system_prop", "mouseupscript", "")
	host.call("set_system_prop", "keyupscript", "")
	quit(h.finish("§6.3 tier 1 and §8.3's modifier word"))
