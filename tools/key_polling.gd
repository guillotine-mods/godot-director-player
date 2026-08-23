extends SceneTree
## `the key` and `the keyCode` are the *last key pressed*. Can a script that is
## not a key handler read them? §8.3, §8.6.
##
##   godot --path . --script tools/key_polling.gd -- --root rating --file BATZEGOZ.dir
##   godot --headless --script tools/key_polling.gd
##   godot --headless --script tools/key_polling.gd -- --root rating --file BATZEGOZ.dir
##
## **Two paths, and the difference is the point.** Most of this drives
## `_dispatch_key` directly, which proves the *rule* and nothing about the
## wiring. The last section feeds `InputEventKey`s through
## `Input.parse_input_event` -- the player's own route, through `_input`,
## `autoload/input_router.gd` and `preview/input_router.gd` -- and reads the
## answer back out of the host the way `the key` compiles to.
## `tools/editable_text.gd` is the same shape.
##
## **That section used to be gated on a window and no longer is.** The gate was
## justified by headless Godot having no keyboard focus, which is true of a
## physical keypress and beside the point: the injection happens at the Input
## singleton, below focus, and the event travels the same nodes either way.
## Measured -- H, S, space and all four arrows report identical codes headless
## and windowed. Gating it meant `gate.sh`, which runs headless, asserted nothing
## about the only path a player actually uses.
##
## **What still nothing here can reach** is the layer below the injection: the OS
## and Godot's platform code turning a physical key into an `InputEvent`. A key
## lost *there* looks exactly like a key lost in the engine, and no harness in
## this repo can tell the two apart. Say so rather than concluding from a green
## run that a player's keyboard works.
##
## **What this is for.** Polling the keyboard from `exitFrame` or `idle` is a
## documented Director idiom -- §8.6 lists it first, "several games poll these
## from `idle` without ever using a handler" -- and this port cleared both
## properties the moment `_dispatch_key` returned, so the idiom could never once
## be true. Rating's `BATZEGOZ.dir`, the *Aderet* frames, is nothing but the
## idiom:
##
##     on exitFrame
##       if (the key = "h") or (the keyCode = 4) then
##         sound playFile 1, soundspath & "h.aif"
##         go("f1")
##       end if
##     end
##
## Three of those, for H, J and Q. The keys reached the engine; the engine forgot
## them before the frame that asks ran; the room did nothing. That is a reported
## bug and it is what the last section here replays.
##
## Title-agnostic. The general rule is asserted against whatever movie is loaded.
## The replay finds its own subject: `tools/lib/key_sites.gd` says which members
## of this movie poll for a character, and the score says which frames those
## members are the frame script of. A movie with no polling site skips that
## section rather than inventing one.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Keys := preload("res://director/director_keys.gd")
## For the modifier case below, which has to go in at the routing rather than at
## `_dispatch_key`: the early return that makes a modifier stamp nothing lives
## here, and a check that called the dispatcher directly would jump over it.
const InputRouter := preload("res://scenes/preview/input_router.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const Paths := preload("res://director/director_paths.gd")

## How far the playhead is stepped while waiting for a frame script to act. The
## Aderet frames hold on a `go the frame` loop, so the poll fires on the next
## `exitFrame` and not on this one; a handful of steps is plenty and a cap means
## a movie that never acts reports a failure rather than hanging.
const STEPS := 40


## One keystroke as the OS delivers it: keycode, physical keycode **and the
## character**. `director_keys.gd:char_for` reads `unicode` first, so an event
## with only a keycode set answers "" for every letter -- which would make a
## check about `the key` pass by measuring nothing.
func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	if code >= 32 and code <= 126:
		event.unicode = String.chr(code).to_lower().unicode_at(0)
	return event


## `the key`, read the way a compiled script reads it.
func _the_key(host) -> String:
	return str(host.call("get_system_prop", "key"))


## `the keyCode`, likewise.
func _the_code(host) -> int:
	return int(host.call("get_system_prop", "keycode"))


## Every frame this member is the frame script of, from the score itself.
func _frames_scripted_by(score, member: int) -> Array:
	var out: Array = []
	for i in score.frame_count:
		var frame: Dictionary = score.frame(i)
		var direct = frame.get("frame_script")
		if direct != null and int(direct) == member:
			out.append(i)
	if not out.is_empty():
		return out
	for interval in score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		if int(interval["script_member"]) != member:
			continue
		for i in range(int(interval["start"]), int(interval["end"]) + 1):
			out.append(i)
	return out


## Put the playhead on a frame, press one key, and step until it leaves. Returns
## where it ended up.
##
## The key is pressed *before* the frame is stepped, exactly as a player does it:
## it lands mid-frame and the `exitFrame` that reads it is the next one out.
func _run_from(preview: Node, from: int, code: Key) -> int:
	preview.set("_paused", false)
	preview.set("_index", from)
	preview.set("_entered_index", -1)
	preview.get("_clock").reset()
	preview.call("_dispatch_key", _key(code))
	for _i in STEPS:
		preview.call("_advance")
		if int(preview.get("_index")) != from:
			break
	return int(preview.get("_index"))


## The member number out of a `key_sites` site string ("batzegoz.dir #6 name").
func _member_of(site: String) -> int:
	var hash_at := site.find("#")
	if hash_at < 0:
		return -1
	return int(site.substr(hash_at + 1).strip_edges().split(" ")[0])


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var windowed := DisplayServer.get_name() != "headless"

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var wanted := Args.text(args, "file", "")
	if wanted != "":
		preview.call("lingo_go_movie", wanted, null)
		await process_frame

	var host = preview.get("_host")
	var score = preview.get("_score")
	if host == null or score == null:
		print("no movie loaded; pass --file")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))
	print("%s: %d frames, %s" % [
		movie, score.frame_count, "windowed" if windowed else "headless",
	])

	# --------------------------------------------------- the rule, everywhere
	# Untouched keyboard first. `-1` and `""` are the *never pressed* value, and
	# they have to be distinguishable from a real press: ScummVM starts `_keyCode`
	# at 0, which is the Mac code for `A`, and Rating tests `the keyCode = 0` at
	# 17 sites -- so a port that copies the 0 has the A key held down before the
	# player has touched anything.
	h.begin("`the key` and `the keyCode` before anything is pressed")
	h.check("`the key` is empty", _the_key(host) == "", "'%s'" % _the_key(host))
	h.check("`the keyCode` is -1, not 0 (0 is the `A` key)",
		_the_code(host) == -1, str(_the_code(host)))
	h.complete("`the key` and `the keyCode` before anything is pressed")

	# The regression itself. Both properties used to be cleared on the last line
	# of `_dispatch_key`, so every one of these read back empty the instant the
	# dispatch returned -- and a frame script polling them therefore never saw a
	# key in its life.
	h.begin("a keypress is still readable after the dispatch returns")
	preview.call("_dispatch_key", _key(KEY_H))
	h.check("`the key` is \"h\"", _the_key(host) == "h", "'%s'" % _the_key(host))
	h.check("`the keyCode` is H's Mac code (%d)" % Keys.MAC_CODES[KEY_H],
		_the_code(host) == int(Keys.MAC_CODES[KEY_H]), str(_the_code(host)))
	# The half an `exitFrame` poll actually depends on: the value has to outlive
	# the frame the key landed on, because the handler that reads it runs later.
	for _i in 5:
		preview.call("_advance")
	h.check("and still \"h\" five frames later, which is when `exitFrame` asks",
		_the_key(host) == "h", "'%s'" % _the_key(host))
	# It is the *last* key, not every key: a second press replaces it rather than
	# accumulating, or a room's `if the key = "h"` would stay true forever.
	preview.call("_dispatch_key", _key(KEY_J))
	h.check("a second press replaces it", _the_key(host) == "j", "'%s'" % _the_key(host))
	h.check("and so does its code",
		_the_code(host) == int(Keys.MAC_CODES[KEY_J]), str(_the_code(host)))
	h.complete("a keypress is still readable after the dispatch returns")

	# §8.3's documented quirk, from ScummVM `events.cpp:341-354`. Unexercised by
	# every title under `games/` -- all 60-odd arrow sites test `the keyCode` --
	# and implemented because Director has it.
	h.begin("§8.3 the arrows substitute characters 28-31 into `the key`")
	for pair in [[KEY_LEFT, 28, Keys.LEFT], [KEY_RIGHT, 29, Keys.RIGHT],
			[KEY_UP, 30, Keys.UP], [KEY_DOWN, 31, Keys.DOWN]]:
		preview.call("_dispatch_key", _key(pair[0] as Key))
		h.check("%s reports character %d" % [OS.get_keycode_string(pair[0]), pair[1]],
			_the_key(host) == String.chr(int(pair[1])),
			"%d" % (_the_key(host).unicode_at(0) if _the_key(host) != "" else -1))
		h.check("%s reports key code %d" % [OS.get_keycode_string(pair[0]), pair[2]],
			_the_code(host) == int(pair[2]), str(_the_code(host)))
	h.complete("§8.3 the arrows substitute characters 28-31 into `the key`")

	# ------------------------------------------------------------ `the lastKey`
	# **Ticks since the last keypress, and it is `the lastClick`'s twin.** §4.5's
	# table in `ENGINE_TODO.md` lists it as unbound and reading VOID. It has been
	# bound since `d9bc27e3` and the row is stale -- which is worth *pinning*
	# rather than merely correcting, because the thing that makes it work is
	# invisible at the property: the stamp rides on `key_code`'s **setter**
	# (`preview_lingo_host.gd`), so it is written by whoever assigns the key and
	# by nobody who remembers to.
	#
	# Three rules, all of them about which keys do **not** stamp it, because that
	# is where a port drifts and none of it is visible from the property alone:
	#
	#   the key going down    stamps. `events.cpp:369-370`.
	#   a modifier key        does not. The stamp is *below* the early return at
	#                         `events.cpp:359-365`, so shift, control, alt and
	#                         command record `_keyFlags` and dispatch nothing --
	#                         and here `preview/input_router.gd:note_modifiers`
	#                         returns before `_dispatch_key` is reached.
	#   the key coming up     does not. `EVENT_KEYUP` at `:378-381` writes
	#                         `_keyFlags` and dispatches; there is no second stamp.
	#
	# Staged by back-dating the field rather than by sleeping, and the routing is
	# driven through `InputRouter.key_event` rather than `_dispatch_key` for the
	# modifier case **on purpose**: `_dispatch_key` is below the early return, so
	# calling it directly would stamp for a modifier and prove nothing about the
	# path a real shift key takes.
	const STALE_MS := 4000
	const RECENT_TICKS := 30
	h.begin("`the lastKey` is stamped by the key going down, and by nothing else")
	var uptime := Time.get_ticks_msec()
	var stale := maxi(uptime - STALE_MS, 0)
	if h.check("the session is old enough to stage a stale key clock",
			int((uptime - stale) * 60.0 / 1000.0) > RECENT_TICKS,
			"%d ms of uptime" % uptime):
		preview.call("_dispatch_key", _key(KEY_H))
		h.check("a keypress leaves `the lastKey` at a small number of ticks",
			int(host.call("get_system_prop", "lastkey")) < RECENT_TICKS,
			"lastKey %s" % str(host.call("get_system_prop", "lastkey")))
		# The modifier. Through the router, so the early return is in the path.
		host.set("last_key_ms", stale)
		var shift := InputEventKey.new()
		shift.keycode = KEY_SHIFT
		shift.physical_keycode = KEY_SHIFT
		shift.shift_pressed = true
		shift.pressed = true
		InputRouter.key_event(preview, shift)
		h.check("a modifier key does not stamp it (§8.3: it raises no keyDown)",
			int(host.call("get_system_prop", "lastkey")) > RECENT_TICKS,
			"lastKey %s after shift" % str(host.call("get_system_prop", "lastkey")))
		# ...but it *did* record the modifier word, or the check above would pass
		# against a router that dropped the event on the floor.
		h.check("...but it did record `the shiftDown`",
			int(host.call("get_system_prop", "shiftdown")) == 1,
			"shiftDown %s" % str(host.call("get_system_prop", "shiftdown")))
		# The release.
		host.set("last_key_ms", stale)
		var release := _key(KEY_H)
		release.pressed = false
		preview.call("_dispatch_key_up", release)
		h.check("a key coming up does not stamp it either",
			int(host.call("get_system_prop", "lastkey")) > RECENT_TICKS,
			"lastKey %s after keyUp" % str(host.call("get_system_prop", "lastkey")))
		# The modifier word is left where a real shift release would leave it.
		# Nothing below reads it, and a harness that leaves a chord held is a
		# harness the next section has to know about.
		host.set("key_flags", 0)
	h.complete("`the lastKey` is stamped by the key going down, and by nothing else")

	# ------------------------------------------- the movie's own polling sites
	var paths := Paths.new()
	paths.load_config()
	var sites := KeySites.for_root(paths.root, movie)
	var chars: Dictionary = sites["chars"]
	var polls: bool = int((sites["asks"] as Dictionary).get("on keyDown", 0)) == 0 \
		and not chars.is_empty()
	print("")
	print("%s polls for %s" % [movie, JSON.stringify(chars.keys())] if polls
		else "%s has no `the key = \"x\"` site; the replay below is skipped" % movie)

	if polls:
		h.begin("a frame script polling `the key` acts on the key that was pressed")
		var acted := 0
		for literal in chars.keys():
			var character := str(literal)
			if character.length() != 1:
				continue
			var keycode := OS.find_keycode_from_string(character.to_upper())
			if keycode == KEY_NONE:
				continue
			for site in (chars[literal] as Array):
				var member := _member_of(str(site))
				var frames := _frames_scripted_by(score, member)
				if frames.is_empty():
					continue
				var from := int(frames[0])
				# **Against a control, not against "the playhead moved".** These
				# frames hold on a `go the frame` loop and the playhead steps
				# forward on its own regardless, so "it is no longer on frame 87"
				# is satisfied by frame 88 and says nothing. The control is the
				# same run with a key no site tests: whatever that reaches is what
				# the score does by itself, and the claim is that the wanted key
				# reaches somewhere else.
				var idle_to := _run_from(preview, from, KEY_Z)
				var landed := _run_from(preview, from, keycode)
				h.check("\"%s\" on frame %d (member %d) sends the playhead somewhere the score does not"
					% [character, from, member], landed != idle_to,
					"with the key: %d; with an unrelated key: %d" % [landed, idle_to])
				if landed != idle_to:
					acted += 1
				print("   \"%s\"  member %-4d frame %-4d -> %-4d (control -> %d)" % [
					character, member, from, landed, idle_to])
		h.check("at least one polling site acted", acted > 0, "%d acted" % acted)
		h.complete("a frame script polling `the key` acts on the key that was pressed")

	# ----------------------------------------------------------- the wiring
	# Everything above went in through `_dispatch_key`. None of it shows that a
	# key a *player* presses gets there: that path is `_input` ->
	# `preview/input_router.gd` -> the movie, and it needs a window with keyboard
	# focus, which headless Godot does not have.
	# **This section runs headless too, and that is a correction.** The paragraph
	# at the top of this file used to gate the whole thing on a window, on the
	# grounds that headless Godot has no keyboard focus. That is true of a
	# *physical* keypress and irrelevant to what is actually being asserted:
	# `Input.parse_input_event` injects at the Input singleton and the event then
	# travels `_input` -> `autoload/input_router.gd` -> `preview/input_router.gd`
	# -> `_dispatch_key` exactly as it does with a window. Measured both ways --
	# every key below reports the same code headless and windowed -- so gating it
	# left the one path nothing else covers unasserted in `gate.sh`, which runs
	# headless. What no run here can exercise is the layer *below* the injection:
	# the platform turning a physical key into an `InputEvent`. That is the honest
	# boundary and it is stated in the header rather than implied by a skip.
	if true:
		if windowed:
			var window := preview.get_window()
			window.grab_focus()
			DisplayServer.window_move_to_foreground()
			await process_frame
		preview.call("_dispatch_key", _key(KEY_Q))
		h.begin("a real keypress reaches the movie through `_input`")
		Input.parse_input_event(_key(KEY_H))
		await process_frame
		await process_frame
		# `the key` was set to "q" a line above, so reading "h" here can only mean
		# the real event travelled the whole way. Reading "q" means it did not.
		h.check("`the key` is what was actually typed", _the_key(host) == "h",
			"'%s'" % _the_key(host))
		h.check("`the keyCode` came with it",
			_the_code(host) == int(Keys.MAC_CODES[KEY_H]), str(_the_code(host)))
		# **The four arrows, through the same real path.** Everything above and
		# the arrow block earlier in this file went in through `_dispatch_key`,
		# which skips `_input` and both routers -- so until now no assertion
		# anywhere covered an arrow arriving the way a player sends one, and the
		# corpus reads arrows more than any other key: all ~60 arrow sites test
		# `the keyCode`, and `piposh-dream` alone tests 123/124/125/126 at 147
		# sites. A player's report of "letters work, arrows do not" is exactly the
		# shape this would have caught and did not, which is why it is here.
		#
		# Poisoned before each one so a stale read is visible rather than
		# plausible: with the field left alone, an arrow that never arrives reads
		# as the *previous* arrow and three of the four still pass.
		for pair in [[KEY_LEFT, 123], [KEY_RIGHT, 124], [KEY_UP, 126], [KEY_DOWN, 125]]:
			var code: Key = pair[0]
			host.set("key_code", -999)
			Input.parse_input_event(_key(code))
			await process_frame
			await process_frame
			h.check("%s reaches the movie through `_input` as %d"
					% [OS.get_keycode_string(code), int(pair[1])],
				_the_code(host) == int(pair[1]), str(_the_code(host)))
		# And the preview's own bindings did not swallow it on the way past. F10
		# is the case with a history: Rating tests `the keyCode = 109` at 48 sites
		# and the pause binding sat on it, so the key that leaves a timed room
		# also paused the player's game.
		var paused_before: bool = bool(preview.get("_paused"))
		Input.parse_input_event(_key(KEY_F10))
		await process_frame
		h.check("F10 reaches the movie and does not pause the preview",
			bool(preview.get("_paused")) == paused_before
			and _the_code(host) == int(Keys.MAC_CODES[KEY_F10]),
			"paused %s, keyCode %d" % [str(preview.get("_paused")), _the_code(host)])
		h.complete("a real keypress reaches the movie through `_input`")

	print("")
	print("`the key`     : '%s'" % _the_key(host))
	print("`the keyCode` : %d" % _the_code(host))
	quit(h.finish("keyboard polling in %s" % movie))
