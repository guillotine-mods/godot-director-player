extends RefCounted
## Where a click and a keypress go.
##
## (For *which* key runs which preview command, see `preview/debug_keys.gd`.)
##
## Two routings, and both are decided here rather than by Godot's own reverse-
## tree `_input` order. That is deliberate: the tree order is invisible to a
## headless harness, and "the click went to the wrong movie" is precisely the
## failure that needs to be assertable.
##
## **A click** goes to the front-most window whose frame contains it, chrome
## included, and it goes there *whole* -- including releasing that window's
## wait-for-click rather than the stage's. The SKIP control is tested before
## either the window routing or the sprite hit-test, because it is the preview's
## own affordance and is drawn over everything.
##
## A click is also two events at two moments, and the routing above is decided by
## the **press**. The release is then delivered to whatever the press landed on,
## however far the pointer has travelled in between -- which is the whole of a
## drag. `director_preview.gd:route_press` / `route_release` hold that pair, and
## `preview/interaction.gd:press` has why sending both halves at once broke every
## drop in the corpus.
##
## **A key** goes to the movie in the active window: the modal window if there is
## one, else the window under the pointer, else the front-most window, else the
## stage. The game's own keys are offered first and the debug bindings only see
## what the movie did not claim. Space is the case that matters -- `fromnow`,
## which 46 scripts install, stops sound channel 1 when the key code is 49, and
## that is how every line of speech in this game is skipped. Every preview
## binding is an F-key for exactly that reason -- a binding that ate space would
## make the movie look unresponsive to the one key a player reaches for first,
## and the arrows and the plain letters are no different. `debug_keys.gd` has the
## rest of that argument.

const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")
const Toast := preload("res://scenes/preview/toast.gd")
const ContainerPicker := preload("res://scenes/preview/container_picker.gd")
const SaveState := preload("res://scenes/preview/save_state.gd")
const SaveFiles := preload("res://scenes/preview/save_files.gd")
## For `MOD_SHIFT` and its three siblings alone -- §8.3's modifier word is the
## host's field and this file is where the events that write it arrive.
const LingoHost := preload("res://scenes/preview_lingo_host.gd")


## A keypress, in the order the three claimants get to see it.
##
## The container picker first, and only while it is open: it is then the thing in
## front of the player and it takes every key, letters included. While it is
## closed it is not consulted at all, which is the constraint it is designed
## around -- a picker that filtered on letters whenever it felt like it would be
## eating keys the game wants for a window that is not there.
##
## Then the movie, then the preview's own bindings. The movie is offered every
## key first, as it always was; what changed is that the preview's own command
## runs afterwards anyway, because a `keyDownScript` reports every key as claimed
## including the ones it ignores. See the note in the body.
##
## One call rather than four lines in `_input`, because this is routing and
## routing is what this file is for -- and because a decision made inside an
## `InputEvent` handler cannot be asserted headlessly.
## **The release takes the first branch and nothing else.** A `keyUp` is a real
## Director event -- §8.1 lists it from D4 and 205 sites across the corpus set
## `the keyUpScript` -- so it goes to the movie; it does *not* reach the picker,
## which filters on characters typed, and it does *not* reach `debug_key`, which
## would toggle a binding back off on the release of the very press that set it.
## `director_preview.gd:_input` used to drop every non-pressed key event one call
## short of here, so this branch had nothing to route.
static func key_event(host, event: InputEventKey) -> void:
	# §8.3, and it happens before every other branch because the reference does it
	# before every other branch: `events.cpp` writes `_keyFlags` in both the
	# key-down and the key-up arm, and a **modifier key returns without
	# dispatching anything at all**. So shift, control, alt and command are the
	# one class of key that is recorded and not delivered -- no `keyDown`, no
	# `keyDownScript`, no widget insertion. Without the early return `fromnow`,
	# which 46 scripts install and which sees every key in the game, was being run
	# once for the shift of every shifted character.
	if note_modifiers(host, event):
		return
	if not event.pressed:
		if not event.echo:
			key_focus(host)._dispatch_key_up(event)
		return
	if bool(host._picker.get("open", false)):
		host._picker = ContainerPicker.key(host._picker, event)
		var go := str(host._picker.get("go", ""))
		if go != "":
			# The engine's own `go to movie`, so a movie reached this way is
			# entered exactly as the game would enter it.
			host.lingo_go_movie(go, null)
			# `lingo_go_movie` leaves the current movie playing when the target
			# will not open, which is the right thing to do and indistinguishable
			# on screen from a key that did nothing.
			var landed: String = host.movie_name()
			var said: Array = Toast.show(
				"playing %s" % landed if landed.to_lower() == go.get_file()
				else "%s would not open — see the log" % go)
			host._toast = str(said[0])
			host._toast_until = int(said[1])
		host.queue_redraw()
		return
	# The movie sees the key first, and sees it whatever happens next: `the
	# keyCode` and `the key` are live during the dispatch, and a preview that
	# withheld a key from a `keyDownScript` would be a preview the game behaves
	# differently under.
	var focus := key_focus(host)
	if not event.echo:
		focus._dispatch_key(event)
	# ...but "claimed" is not evidence the movie *wanted* this key. A
	# `keyDownScript` is installed once and then receives everything, and it
	# reports every key as claimed including the ones it ignores: `fromnow`, which
	# 46 scripts install, acts on key code 49 and on nothing else, and answers
	# claimed for all the rest. So while a `keyDownScript` was installed -- which
	# is most of this game -- not one preview binding fired. F10 has been dead
	# since it was moved off space, and nobody noticed, because a debug key that
	# does nothing looks exactly like a debug key you misremembered.
	#
	# A command therefore runs on its own key regardless. That is safe only
	# because the band is chosen not to collide: every binding is an F-key, no
	# title in either corpus tests one, and a title that did has `[debug]` to move
	# it out of the way.
	#
	# **With the modifiers, not without.** `event.keycode` drops them, so a chord
	# binding could never have matched and `Shift+F5` ran whatever plain `F5` is
	# on -- which, with the save keys added, would have been "step the playhead
	# back" every time somebody tried to quick-save. `get_keycode_with_modifiers`
	# is the same number `OS.find_keycode_from_string("Shift+F5")` produces, which
	# is what `debug_keys.gd` built the map out of.
	debug_key(host, event.get_keycode_with_modifiers())


## Godot's four modifier keycodes, and the bit each carries in Director's word.
##
## Keyed on the *keycode* rather than on the `*_pressed` booleans because this
## table answers a second question the booleans cannot: **is this event a
## modifier key in its own right**, which is what §8.3 suppresses the dispatch
## for. Godot reports left and right shift as one keycode, so there is no pair to
## fold here.
## The bits are the host's own, not a second copy of them: the word is stored
## there, read there by the four properties and saved from there, and two files
## agreeing about which bit is shift by both writing `1` is the shape that comes
## apart the first time one of them gains a fifth modifier.
const MODIFIER_KEYS := {
	KEY_SHIFT: LingoHost.MOD_SHIFT,
	KEY_ALT: LingoHost.MOD_ALT,
	KEY_CTRL: LingoHost.MOD_CTRL,
	KEY_META: LingoHost.MOD_META,
}


## Latch the modifier word that came with this event, and say whether the event
## *is* a modifier key (§8.3).
##
## **The word is taken from the event, not from the keyboard.** That is the whole
## change: `the shiftDown` and its three siblings used to ask
## `Input.is_key_pressed` at the moment the property was read, which answers
## about the OS keyboard some milliseconds after the event that is being handled
## and about a keyboard no synthetic event ever touches. The reference stores
## `event.kbd.flags` on the way past and every one of the four properties reads
## that stored word (`lingo-the.cpp`), so a handler asking mid-dispatch is told
## what was held when the key arrived.
##
## Recorded on the movie the key is being delivered to, which is where
## `the keyCode` and `the key` are recorded as well: the reference keeps one word
## for the engine, this port keeps one host per movie, and splitting the pair
## would let `the keyCode` and `the shiftDown` describe different keystrokes.
static func note_modifiers(host, event: InputEventKey) -> bool:
	var focus: Node = key_focus(host)
	var lingo: Object = focus.get("_host")
	if lingo != null:
		var flags := 0
		if event.shift_pressed:
			flags |= LingoHost.MOD_SHIFT
		if event.alt_pressed:
			flags |= LingoHost.MOD_ALT
		if event.ctrl_pressed:
			flags |= LingoHost.MOD_CTRL
		if event.meta_pressed:
			flags |= LingoHost.MOD_META
		lingo.set("key_flags", flags)
	return MODIFIER_KEYS.has(event.keycode)


## The movie a keypress belongs to.
##
## Nothing in this corpus installs a `keyDownScript` in a window movie, so this
## is the engine's rule rather than this title's need -- but sending a key to the
## stage instead would have a covered movie skipping speech it is not playing.
static func key_focus(host) -> Node:
	var focus: Node = host.modal_window()
	if focus == null:
		focus = host.window_at(host.stage_mouse())
	if focus == null:
		focus = host._front_window()
	if focus == null:
		focus = host
	return focus


## A left mouse button event. True when it was fully handled.
static func mouse_button(host, event: InputEventMouseButton, at: Vector2,
		skip_rect: Rect2) -> void:
	# The picker covers the stage while it is open, so a click has to stop at it
	# rather than reach a sprite the player cannot see and did not aim at.
	if bool(host._picker.get("open", false)):
		return
	if event.pressed:
		# Recorded on every movie on the stage, windows included, so a window
		# that opens during this click still has not seen its press.
		host._saw_press = true
		for key in host._windows:
			var w: Node = host._windows[key]
			if w != null:
				w._saw_press = true
		# A press that never reaches `route_press` -- SKIP below takes it, or a
		# modal discards it -- must not leave the *previous* press latched, or the
		# release that follows sends a second `mouseUp` for a click that already
		# finished.
		host._press_target = null
	else:
		# The mouse-up. This used to clear `_drag_channel`, re-resolve the cursor
		# and `return` -- so the release of a drag was the one mouse event in the
		# engine that dispatched no message at all, and the drag was swallowing
		# the very `mouseUp` every drop is decided in. §7.6 is explicit that a
		# moveable sprite follows the cursor *until mouse-up*, and that Director
		# does not suppress the message because a drag was in progress.
		#
		# Both of those now live in `route_release`, so the drag ends and the
		# cursor is recomputed for whichever movie took the press rather than
		# always for the stage.
		host.route_release(at)
		# ...and once more unconditionally, because §7.5 recomputes the cursor on
		# every mouse-up, including one with no press behind it.
		host._resolve_cursor()
		return
	# Tested before the sprite hit-test, or a hotspot underneath would eat it.
	# Before the window routing too: it is the preview's own control and it is
	# drawn over everything, including a window.
	if skip_rect.has_point(at):
		host.skip_release()
		return
	# **`route_press`, not `route_click`.** `route_click` is press *and* release
	# back to back, and calling it from the button-down branch meant the entire
	# press/release split never applied to a real mouse at all: `mouseUp` went
	# out on the press exactly as before, `_press_target` was cleared by the
	# synthetic release, and the genuine button-up above then found nothing
	# latched and dispatched nothing.
	#
	# So the fix that split the two halves reached `route_press`/`route_release`
	# and stopped one line short of the only caller a player can reach. It was
	# invisible to the harnesses because every one of them drives `route_press`
	# and `route_release` directly -- which is the right thing for asserting the
	# routing, and is why `tools/touch_input.gd`, which goes in through
	# `Input.parse_input_event` and therefore through `_input`, is the check that
	# found it. `route_click` stays: it is one *whole* click, which is what a
	# harness with no button to hold down actually wants.
	host.route_press(at)


## The right button (§8.1, D5). Nearly a click in every sense the left button is:
## `interaction.gd:latch_press` runs the whole §15 mouse-down block for either
## button, and §9.2's wait-for-click is released by either too -- the reference
## clears `_waitForClick` in the arm it shares between `EVENT_LBUTTONDOWN` and
## `EVENT_RBUTTONDOWN` (`events.cpp:250-254`), because the frame is waiting for a
## click and not for a particular one. What the right button does *not* raise is
## the left pair of messages; that is the whole of the difference.
##
## This header used to say the opposite -- no drag, no `the clickOn`, no
## wait-for-click release, each of them deliberate. The first two stopped being
## true when the latch block landed and this one was never checked against the
## reference at all, which is how a stale "deliberate" note outlives the decision
## it records.
##
## Routed to the same movie a left press would reach, because "which movie owns
## this point" is a property of the point and not of the button.
static func right_mouse_button(host, event: InputEventMouseButton, at: Vector2) -> void:
	if bool(host._picker.get("open", false)):
		return
	if event.pressed:
		# The same record the left button keeps, and for the same reason: a movie
		# answers a click whose *press* it saw, and a window that opened during
		# this click has not seen one. Without it the wait-for-click release in
		# `route_right_button` is guarded on a flag only the left button ever
		# sets, which is a fix that never fires.
		host._saw_press = true
		for key in host._windows:
			var w: Node = host._windows[key]
			if w != null:
				w._saw_press = true
	var blocking: Node = host.modal_window()
	if blocking != null and not blocking.window_frame().has_point(at):
		return
	var front: Node = host.window_at(at)
	if front != null and front != host:
		front.call("route_right_button", front.stage_to_local(at), event.pressed)
		return
	host.call("route_right_button", at, event.pressed)


## Pointer movement: rollover tracking, hover tracking, drag, and the cursor
## recompute.
##
## **Two channels are tracked, not one, and they answer different questions.**
## `_hover_channel` is what a *click* would reach -- eligibility filtered, matte
## sampled -- and it drives the hotspot overlay. `_rollover_channel` is what the
## pointer is simply *over*, a pure rect test with no filter (§4.5), and it is
## what `the rollOver`, `mouseEnter` and `mouseLeave` are defined against.
## Collapsing them was a divergence with a visible shape: a backdrop with no
## handler is rolled over and is not clickable, so a menu that highlights on
## rollover and acts on click needs both answers and would otherwise get the
## click one twice.
## `at` is the point the event carried, in stage coordinates. It is optional so
## that a harness which warps a real pointer and then calls this directly still
## works -- `tools/sprite_drag.gd` does exactly that, and for it the OS cursor is
## the truth. `Vector2.INF` rather than a null default because the parameter is
## typed, and an untyped one would lose the compile-time check on every caller.
## **Where the pointer is now, for the movie that owns that point**, and nothing
## else: the two hover channels, `the mouseH`/`the mouseV` inside a window, and
## the `mouseEnter`/`mouseLeave` crossing that follows from the first.
##
## Split out of `mouse_motion` because a **button** event has to do it too, and
## for the reference's own reason rather than for the touchscreen's:
## `Movie::processSysEvent` recomputes `_currentHoveredSpriteId` and
## `_lastMousePos` from `event.mouse` at the top of the function, before the
## switch that separates a move from a press. `director_preview.gd:_input` calls
## this ahead of routing either button. What it deliberately does **not** do is
## the rest of `mouse_motion` -- the drag, the text selection and the cursor
## recompute are movement, and a press is not movement.
##
## Returns the movie that took the point, so `mouse_motion` can carry on in it.
static func aim_pointer(host, at: Vector2) -> Node:
	var over: Node = host.window_at(at)
	if over != null and over != host:
		var local: Vector2 = over.stage_to_local(at)
		# The window cannot see the event itself -- its input processing is off --
		# so this is the only thing that keeps `the mouseH` and `rollOver` inside
		# a Movie-In-A-Window current.
		over.call("note_pointer", local)
		over._hover_channel = over._channel_at(local)
		over.call("track_rollover", local)
		return over
	host._hover_channel = host._channel_at(at)
	host.call("track_rollover", at)
	return host


static func mouse_motion(host, at: Vector2 = Vector2.INF) -> void:
	var point: Vector2 = host.stage_mouse() if at == Vector2.INF else at
	var was: int = host._hover_channel
	var over: Node = aim_pointer(host, point)
	if over != host:
		over._resolve_cursor()
		host.queue_redraw()
		return
	if host._drag_channel > 0:
		# §7.6 ends the drag on mouse-up **or when the sprite stops being
		# moveable**, and only the first half was here. A script that cleared
		# `the moveableSprite` mid-gesture -- or a score that moved the channel to
		# a frame the sprite is not on -- left the sprite following the cursor
		# anyway until the button came up, which reads as "the game will not let
		# go of this thing" rather than as a missing clause.
		# `Interaction.still_moveable` has why it is a real exit rather than a
		# skipped frame, and why the answer has to come from the effective sprite.
		if not Interaction.still_moveable(
				host, host._drag_channel,
				host.frame_sprites()):
			host._drag_channel = 0
			# §7.5: the cursor is recomputed when the drag ends, exactly as it is
			# on the mouse-up that usually ends it.
			host._resolve_cursor()
			host.queue_redraw()
			return
		# The dragged sprite follows the cursor by the offset recorded when the
		# drag began, so it does not snap its registration point to the pointer on
		# the first movement.
		var to: Vector2 = point + host._drag_offset
		host.lingo_set_sprite_prop(host._drag_channel, "loch", int(to.x))
		host.lingo_set_sprite_prop(host._drag_channel, "locv", int(to.y))
		host.queue_redraw()
		return
	# The cursor is resolved on mouse movement, not once per frame. Director
	# recomputes it on move, on button-up, on entering the window and on a new
	# movie -- so a sprite that swaps to a member with a different cursor under a
	# stationary mouse keeps the old one until the mouse moves.
	host._resolve_cursor()
	if was != host._hover_channel:
		host.queue_redraw()
		return
	# §4.6's hilite follows the pointer *inside* the sprite the press latched, and
	# that is a different question from which sprite is hovered: sliding off the
	# pressed sprite while staying over the same one above it changes the
	# inversion and changes no hover. Without this the repaint is left to the
	# score's own cadence -- invisible on a running movie, and a stale inversion
	# held on screen for as long as a paused preview stays paused.
	if int(host._press_channel) > 0:
		host.queue_redraw()


## The preview's own bindings, reached only by a key no script claimed.
##
## The keys come from `preview/debug_keys.gd`, which reads them out of
## `director_game.cfg`. They are matched on the *command* rather than on the
## keycode so that moving one is a config edit and not a code edit -- and so that
## the reason each command exists can be written next to the command instead of
## next to whichever key it happens to be on this week.
static func debug_key(host, code: int) -> void:
	match DebugKeys.command_for(code):
		"pause":
			host._paused = not host._paused
		"fast_forward":
			# A toggle, not a hold: one press runs the movie at the configured
			# rate, the next hands it back to the score. The rate is stored on
			# the node rather than a boolean because the node is what has to
			# apply it, and 0 is a clearer "off" than a separate flag that could
			# disagree with it.
			host._fast_forward_fps = (
				0.0 if host._fast_forward_fps > 0.0
				else DebugKeys.number("fast_forward_fps")
			)
			var rate: float = host._fast_forward_fps
			var said: Array = Toast.show(
				"fast forward: %.0f fps" % rate if rate > 0.0
				else "fast forward off")
			host._toast = str(said[0])
			host._toast_until = int(said[1])
			host.queue_redraw()
		"step_forward":
			host._paused = true
			host._index = mini(host._index + 1, host._score.frame_count - 1)
			host.queue_redraw()
		"step_back":
			host._paused = true
			host._index = maxi(host._index - 1, 0)
			host.queue_redraw()
		"restart":
			host._index = 0
			# Restarting from a frame that was holding -- a delay, a wait for a
			# click -- must not carry that hold onto the frame it restarts at, or
			# the restart looks like it did nothing.
			host._clock.reset()
			host._entered_index = -1
			host._pending_enter = null
			host.queue_redraw()
		"boxes":
			host._show_boxes = not host._show_boxes
			host.queue_redraw()
		"collisions":
			# Reported rather than silent, because an empty overlay is the
			# expected state in most rooms -- nothing in them uses the operators
			# -- and is indistinguishable from a key that did nothing.
			host._show_collisions = not host._show_collisions
			print("collision zones: %s (%d channel(s) measured so far)" % [
				"on" if host._show_collisions else "off",
				host._collision_channels.size(),
			])
			host.queue_redraw()
		"hit_test":
			host._hit_pixels = not host._hit_pixels
			print("hit test: %s" % ("artwork" if host._hit_pixels else "full rectangle"))
			host.queue_redraw()
		"report":
			host._report()
		"snapshot":
			# The toast is the whole point of the confirmation: a clipboard write
			# is invisible, so without it the key is indistinguishable from a key
			# that is not bound.
			var said: Array = Toast.show(Snapshot.toast_text(host))
			Snapshot.take(host)
			host._toast = str(said[0])
			host._toast_until = int(said[1])
			host.queue_redraw()
		"containers":
			host._picker = ContainerPicker.open(host)
			host.queue_redraw()
		"globals":
			# Printed rather than drawn: a globals dump is dozens of lines and the
			# stage is 640x480. It goes where the rest of the diagnostics go.
			print(SaveState.globals_text(host))
			_say(host, "globals printed to the log")
		"quick_save":
			_say(host, _saved_text(SaveFiles.save(host, SaveFiles.quick_path(host))))
		"quick_load":
			# "Whatever you were last working with": the last save this session
			# *loaded*, falling back to the quick-save. Saving does not move it, so
			# a quick-save followed by a quick-load reloads the named file you were
			# iterating on rather than silently switching you to the quick slot.
			var wanted := str(host._last_save)
			_say(host, load_save(host,
				wanted if wanted != "" else SaveFiles.quick_path(host)))
		"save_as":
			# Captured **now**, before the dialog, state and picture both. What
			# should be written is what the key was pressed on; the score keeps
			# running while somebody types a filename, and by the time they press
			# Save the movie is several frames past the thing they wanted to record.
			var record: Dictionary = SaveState.capture(host)
			var shot: Image = Snapshot.grab(host)
			SaveFiles.ask_where_to_save(host, func(path: String) -> void:
				_say(host, _saved_text(
					SaveFiles.write_record(host, path, record, shot))))
		"load_file":
			SaveFiles.ask_what_to_load(host, func(path: String) -> void:
				_say(host, load_save(host, path)))
		"fullscreen":
			var window: Window = host.get_window()
			window.mode = (
				Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN
				else Window.MODE_FULLSCREEN
			)
		"quit":
			host.get_tree().quit()


## Read a save and put it back onto this preview. Returns the line to show.
##
## **The movie is re-entered even when it is the one already playing.** That is
## not laziness: `lingo_go_movie` is the engine's own arrival, so a movie reached
## by a load has run `prepareMovie` and `startMovie` and had its per-movie state
## dropped by `movie_session.gd:forget_previous` exactly as it would arriving any
## other way. Restoring on top of a movie that had merely been *running* would
## leave whatever the session had accumulated underneath the record — and it
## would make an in-session load and a `--save` boot produce two different
## states, which is the one thing this feature cannot afford.
static func load_save(host, path: String) -> String:
	var got: Dictionary = SaveFiles.read(path)
	if str(got["error"]) != "":
		push_warning("load: %s" % str(got["error"]))
		return str(got["error"])
	var data: Dictionary = got["data"]
	var verdict: Dictionary = SaveFiles.check(host, data)
	if str(verdict["refuse"]) != "":
		# Refused rather than loaded wrong. A save of another game is a pile of
		# member and channel numbers that all resolve against this one — to real
		# members showing the wrong thing, which reads as corruption.
		push_error("load refused: %s" % str(verdict["refuse"]))
		print("load refused: %s" % str(verdict["refuse"]))
		return "load refused — see the log"
	if str(verdict["warn"]) != "":
		push_warning("load: %s" % str(verdict["warn"]))
		print("load WARNING: %s" % str(verdict["warn"]))
	host.lingo_go_movie(str(data.get("movie", "")), null)
	var failed: String = SaveState.restore(host, data)
	if failed != "":
		push_warning("load: %s" % failed)
		return failed
	SaveState.restore_windows(host, data)
	host._last_save = path
	host.queue_redraw()
	return "loaded %s  %s frame %d" % [
		path.get_file(), host.movie_name(), int(host._index)]


static func _saved_text(report: Dictionary) -> String:
	if str(report["error"]) != "":
		push_warning("save: %s" % str(report["error"]))
		print("save failed: %s" % str(report["error"]))
		return "save failed — see the log"
	print("saved %s%s" % [str(report["path"]),
		("  + %s" % str(report["png"]).get_file()) if str(report["png"]) != "" else ""])
	return "saved %s" % str(report["path"]).get_file()


## The toast is the whole confirmation for these: writing a file is invisible, so
## without one a save key is indistinguishable from a key that is not bound. Same
## argument as the snapshot's.
static func _say(host, text: String) -> void:
	var said: Array = Toast.show(text)
	host._toast = str(said[0])
	host._toast_until = int(said[1])
	host.queue_redraw()
