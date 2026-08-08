extends RefCounted
## One step of the movie, and the tick that decides how many steps are owed.
##
## Two orderings live here and both are load-bearing, so they are stated once at
## the top rather than rediscovered inside the functions.
##
## **Within a tick**, the order is: sync the frame entry, pump sound, step the
## palette, preload, and only then ask the clock. Everything before the clock can
## *release* a hold this tick, and anything evaluated after the clock has already
## decided the tick holds costs the frame it was waiting for.
##
## **Within a step**, `exitFrame` comes before the playhead moves. This game has
## 232 `on exitFrame` handlers against 33 `on enterFrame`, so its walk state
## machine is stepped from there, and the frame it is stepped *for* must be the
## one the player is looking at rather than the one the score is about to move
## to. The first step of a movie therefore sends `exitFrame` for the frame it
## started on -- DAY1's frame 0 `init all` is an `on exitFrame` handler that
## establishes the entire opening state of the room and ends with `go("shore2")`.
## Skip it and the room draws with nothing initialised.
##
## Film loops advance on the movie's clock rather than the playhead's, which is
## why the tick is counted before the hold is tested: a character keeps talking
## on a frame the score is standing still on.

const FrameClock := preload("res://director/director_frame_clock.gd")
const Transition := preload("res://director/director_transition.gd")


## The playhead has landed somewhere this tick has not accounted for yet: release
## the auto-puppets the score wrote on the way, take the frame's tempo, arm
## whatever it waits for, and start any transition it carries.
##
## **The release is first, and it is here rather than in `advance`** because this
## is the port's "the frame number changed" event and there is exactly one of it:
## `advance` is not the only thing that moves the playhead -- `go`, `play`, `play
## done`, the debug arrows and a restored save all write `_index` and leave this
## to notice -- and Director hangs the same call on the same event, inside the
## `if (_curFrameNumber != nextFrameNumberToLoad)` that this function's own early
## return mirrors.
##
## First within the function, too. A frame's scripts run after this returns, so a
## release ordered after them would take back the write the frame just made
## instead of the one the frame before it left behind.
static func sync_frame_entry(host) -> void:
	if host._index == host._entered_index or host._score == null:
		return
	var came_from: int = host._entered_index
	host._entered_index = host._index
	host._release_auto_puppets(came_from, host._index)
	var frame: Dictionary = host._score.frame(host._index)
	if frame.is_empty():
		return
	host._clock.enter_frame(frame)
	# Before the transition, deliberately: a frame's sounds start *in parallel*
	# with its transition rather than after it, so a cut scene's line of speech
	# begins as the wipe does and not a second later.
	host._begin_score_sound(frame)
	host._begin_palette(frame)
	host._begin_transition(frame)


## Resolve this frame's transition and hold the playhead for as long as it takes.
##
## Three sources in order: a puppet transition set from Lingo, which is one-shot
## and consumed here; the frame's own, which in a D5 score is a reference to a
## transition cast member; or nothing. Only the *time* is reproduced -- the new
## frame cuts in rather than wiping -- because a cut reads as a stylistic choice
## while a wrong wipe reads as a bug, and the duration is the part scripts are
## timed against.
##
## `tools/transition_survey.gd` says this corpus spends 4.0 s in transitions
## across five frames of three movies, against 74.0 s in tempo delays across
## thirty-six. Both were being skipped entirely.
static func begin_transition(host, frame: Dictionary, table) -> bool:
	var puppet: Dictionary = host._puppet_transition
	host._puppet_transition = {}
	var from_frame: Dictionary = {}
	var number := int(frame.get("transition_member", 0))
	if number > 0 and table != null:
		var cast = table.cast_for(int(frame.get("transition_lib", 1)))
		if cast != null:
			from_frame = cast.member(number)
	var transition: Dictionary = Transition.resolve(puppet, from_frame)
	if not Transition.is_transition(transition):
		return false
	host._transitions_played += 1
	host._clock.hold(Transition.hold_ms(transition), FrameClock.REASON_TRANSITION)
	host._trace("f%d transition %s" % [host._index, Transition.describe(transition)])
	return true


## One tick of the movie: release what can be released, then take whatever steps
## the clock says are due.
static func tick(host, delta: float) -> void:
	# The player's button, sampled at the *engine's* rate rather than the score's.
	# A click is 40-100 ms and a score step here is 125-250 ms, so a movie that
	# only looked at the button from inside `exitFrame` misses most of them --
	# which is every `if the mouseDown then go ...`, Director's click-to-skip
	# idiom, in both titles. `director_preview.gd:_mouse_down_seen` carries the
	# measurements and the argument that this is Director's model and not a
	# workaround: the press is an event, and a movie stepping eight times a
	# second still receives every event that happened in between.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		host._mouse_down_seen = true
	# A click or a key may have moved the playhead since the last step. Take the
	# frame it landed on before deciding how much time that frame is owed, or the
	# old frame's tempo paces the new one.
	sync_frame_entry(host)
	# Cue points and the tempo channel's wait-for-sound, before the clock. The
	# fade ramp they interact with is stepped by `AudioDirector` itself, one
	# process priority earlier.
	host._pump_sound(delta)
	# Before the clock, because a cycle or a fade is what the clock is *holding*
	# the playhead for: stepping it after would advance the frame that the effect
	# is the reason for, and the last step of a fade would land on the next one.
	if host._palette_state.effect_running() and host._palette_state.step(delta * 1000.0):
		host._palette_applied()
	# Pay for the artwork of frames not yet reached, before asking the clock for
	# work. Time-boxed, so this cannot become the stall it exists to prevent --
	# and measured *and discounted*, because a movie should not owe catch-up
	# steps for time Director would have spent preloading.
	if host._preloader != null:
		var loading := Time.get_ticks_usec()
		host._preloader.run(host._index, host._preload_one, host._effective_ahead)
		host._clock.discount((Time.get_ticks_usec() - loading) / 1000000.0)
	var due: int = host._clock.tick(delta)
	if due <= 0:
		return
	for _i in due:
		# Counted before the hold is tested, not after: a wait-for-click frame
		# with a character talking on it must not freeze the character.
		host._ticks += 1
		if host._clock.playhead_held():
			continue
		if host._pending_enter != null:
			# The transition has finished arriving; the frame it revealed gets its
			# `enterFrame` now.
			var resumed: Dictionary = host._pending_enter
			host._pending_enter = null
			host._dispatch("enterFrame", resumed)
			continue
		host._advance()
		# The press has now been offered to a step, so it stops being owed. What
		# the button is *still* doing it says for itself, which is why this is the
		# live state and not `false`: a held button keeps reading down, and
		# `if the mouseDown then go(marker(1)) else go(marker(0))` -- the
		# charge-and-fire idiom -- needs both halves to be honest. Cleared here
		# rather than at the top of the tick because the steps of one tick run
		# back to back with no sample between them, so only the first of a
		# catch-up burst may see a press that is already over.
		host._mouse_down_seen = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	host.queue_redraw()


## One step of the movie, in Director's order.
##
## Returns what the step did, so a harness can assert the ordering rather than
## infer it: `exited` is the frame `exitFrame` was sent for, -1 when it was
## skipped, and `frame` is the frame the rest of the step ran on.
static func advance(host) -> Dictionary:
	if not host._lingo_on:
		host._index = (host._index + 1) % maxi(host._score.frame_count, 1)
		sync_frame_entry(host)
		return {"exited": -1, "frame": host._index}

	# A step must never begin with an `enterFrame` still owed for the frame it is
	# about to leave. The tick normally pays it when the transition's hold runs
	# out; a caller stepping this directly -- a harness, the arrow keys -- never
	# consults the clock, so the debt is settled here instead of being carried
	# into the next frame and dispatched against the wrong one.
	if host._pending_enter != null:
		var owed: Dictionary = host._pending_enter
		host._pending_enter = null
		host._dispatch("enterFrame", owed)
	# A `go to` queued from outside the step loop has already moved the playhead,
	# and Director sends no `exitFrame` for a frame it is leaving that way. The
	# step still runs: it renders and enters the frame the jump landed on, and
	# the *next* step is the one that leaves it.
	var exited := -1
	host._held = host._jump_queued
	host._jump_queued = false
	if not host._held:
		exited = host._index
		host._in_exit_frame = true
		host._dispatch("exitFrame", host._frame_script(host._index))
		host._in_exit_frame = false

	# `updateCurrentFrame`: the handler above decided where the playhead goes.
	# `go to the frame` -- how a room stands still at all -- reaches this as a
	# hold, and any other `go` has already written the destination.
	if not host._held:
		host._index += 1
		if host._index >= host._score.frame_count:
			host._index = 0
	host._held = false
	sync_frame_entry(host)

	var script: Dictionary = host._frame_script(host._index)
	host._dispatch("prepareFrame", script)
	# The draw. Godot paints at the end of the process frame rather than here, so
	# this is a request and not a completed paint: what `enterFrame` writes below
	# still lands in the same painted frame, where Director would have shown it
	# on the next one. A real divergence, and the cheapest one on offer -- the
	# alternative is deferring every `enterFrame` by a whole frame.
	host.queue_redraw()
	host._enter_frame_or_defer(script)
	return {"exited": exited, "frame": host._index}
