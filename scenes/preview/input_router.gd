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
const Snapshot := preload("res://scenes/preview/snapshot.gd")
const Toast := preload("res://scenes/preview/toast.gd")
const ContainerPicker := preload("res://scenes/preview/container_picker.gd")


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
static func key_event(host, event: InputEventKey) -> void:
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
	debug_key(host, event.keycode)


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
	else:
		# A drag ends on mouse-up, and the cursor is re-resolved then.
		host._drag_channel = 0
		host._resolve_cursor()
		return
	# Tested before the sprite hit-test, or a hotspot underneath would eat it.
	# Before the window routing too: it is the preview's own control and it is
	# drawn over everything, including a window.
	if skip_rect.has_point(at):
		host.skip_to_end()
		return
	host.route_click(at)


## Pointer movement: hover tracking, drag, and the cursor recompute.
static func mouse_motion(host) -> void:
	var point: Vector2 = host.stage_mouse()
	var over: Node = host.window_at(point)
	if over != null and over != host:
		over._hover_channel = over._channel_at(over.stage_to_local(point))
		over._resolve_cursor()
		host.queue_redraw()
		return
	var was: int = host._hover_channel
	host._hover_channel = host._channel_at(point)
	if host._drag_channel > 0:
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
		"fullscreen":
			var window: Window = host.get_window()
			window.mode = (
				Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN
				else Window.MODE_FULLSCREEN
			)
		"quit":
			host.get_tree().quit()
