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
## **Within that step, `pause` is read twice**, and both readings are the
## reference's. A step is refused before it starts when the movie is already
## paused, and the playhead move is refused *again* after `exitFrame` has run,
## because `pause` is normally called from inside that handler and there is no
## other moment at which its own frame is still the current one. A single guard at
## the top is the bug this file used to have: it parked the playhead one frame past
## every frame that paused itself.
##
## Film loops advance on the movie's clock rather than the playhead's, which is
## why the tick is counted before the hold is tested: a character keeps talking
## on a frame the score is standing still on.

const FrameClock := preload("res://director/director_frame_clock.gd")
const Transition := preload("res://director/director_transition.gd")


## Director's `pause` — the movie's own, not the debug key's `_paused`.
##
## One reader, because this file tests it in three places now and a host that is
## null in a harness would be three copies of the same null check.
static func paused(host) -> bool:
	return host._host != null and host._host.playback_paused


## The frame this step began on no longer exists.
##
## `score.cpp:696-698` and `:722-724` are two returns out of `update()` on the same
## question — the handler that just ran stopped the movie, or a `go to movie`
## swapped the container under it — and everything after them (the playhead move,
## `prepareFrame`, the draw, `enterFrame`) belongs to the movie that *arrived*.
##
## This port opens the next container inside the `go to movie` call rather than
## queueing it, so the arriving movie has already entered its own first frame by
## the time the dispatch returns. Without this test the rest of the step then ran
## over the top of it: measured on `DAY1.dir` frame 729, whose whole frame script is
## `on exitFrame / go(1, "air1.dir")`, one step sent **two** `enterFrame`s for
## AIR1's opening frame against one `prepareFrame`.
static func movie_gone(host, score_before) -> bool:
	return host._score != score_before or (host._host != null and host._host.stopped)


## `idle` — the gap between two frames, which is where Director spends most of its
## time and where a title puts anything that has to happen on a clock rather than
## on a frame.
##
## **Once per engine tick, not once per score step.** `Score::step` sends it
## (`score.cpp:336-338`) and `Window::step` calls that from the projector's main
## loop, which turns over every ~10 ms (`director.cpp:370-405`) — many times per
## score frame at any tempo, and `Score::update` is the half that gates on the
## frame clock. So `idle` is sent *before* the clock is consulted and regardless of
## what it says, which is also why the reference sends it from `step` and not from
## `update`.
##
## **And while the movie is paused.** `Score::step` returns early only on
## `kPlayPaused`/`kPlayStopped` — the projector's own states, `_paused` and
## `stopped` here — and reads `_playbackPaused` nowhere. Director's `pause` stops
## the playhead and leaves the movie live; that is the whole point of it, and a
## title whose clock hangs off `idle` must keep that clock while a screen is
## paused. `hezsave.dir` frame 8 is `on exitFrame / pause` and `HEZSAVE.dir` is one
## of the four `rating` movies carrying `on idle / ClockScript()`.
##
## Guarded on "no jump is pending", which is the reference's own `hasJump`
## (`score.cpp:330-332`): a step that already knows where it is going is not idle.
## A `go` from inside the handler is fine — it sets the flag for the *next* tick.
##
## **Sent to the movie script and to nothing else.** `lingo-events.cpp:552` queues
## it as `kMovieHandler`, alongside `startMovie` and `stepMovie`, where `exitFrame`
## is queued as `kFrameHandler`. Handing it the frame script would let a frame
## script's `on idle` answer an event Director never offers it.
##
## This was missing entirely, and it cost `rating` its whole clock. Its
## `NAVIGATE.dir`, `BLAEGOZ.dir`, `BATZEGOZ.dir` and `HEZSAVE.dir` each carry
## `on idle / ClockScript() / end`, and `Panel.cst`'s `ClockScript` is what
## advances `GlobalSecond` and `GlobalHour`, fires the seventeen timed story
## events in its `case h&s of`, and calls `checkroom` — which steps `TIMEKEEPER`
## and reads `line TIMEKEEPER of field "timebasebackup"` to decide where the
## player is sent and who is where. With no `idle` none of that ever ran: the
## player's own save records `timekeeper = 2`, `globalhour = 8` and
## `globalsecond = 0`, the init values, beside an `itemkeeper` of 14 and four
## items collected. Hours of play, and the clock had never ticked once.
static func send_idle(host) -> void:
	if not host._lingo_on or host._jump_queued:
		return
	host._dispatch("idle", {})


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
	# `idle`, at the engine's rate and before the clock is asked anything — see
	# `send_idle`. An `on idle` handler may `go to movie`, which replaces the score
	# under everything below, so the rest of the tick is skipped when it does.
	var score_before = host._score
	send_idle(host)
	if movie_gone(host, score_before):
		return
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
		# Director's `pause` freezes the film loops with the playhead and a *hold*
		# does not: `Score::incrementFilmLoops` returns early on `_playbackPaused`
		# and runs straight through a wait-for-click. So this is tested ahead of the
		# tick count rather than beside the hold below -- `host._ticks` is the film
		# loops' clock, and a paused room whose characters keep talking is what
		# skipping it looks like. The rest of what `pause` suspends is one guard in
		# `director_preview.gd:_advance`.
		if paused(host):
			continue
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

	# `idle` used to be sent from here, once per score step. It is sent from `tick`
	# now, once per engine tick and whether or not the playhead is held or paused,
	# which is where `Score::step` has it — see `send_idle`. A caller stepping this
	# directly (a harness, the arrow keys) therefore sends no `idle`, which is the
	# reference's shape too: `Score::update` sends none either.

	# The score the step began against. A handler dispatched below may open another
	# container or stop the movie, and everything after that point belongs to the
	# movie that arrived rather than to this one — see `movie_gone`.
	var score_before = host._score
	# A `go to` queued from outside the step loop has already moved the playhead,
	# and Director sends no `exitFrame` for a frame it is leaving that way. The
	# step still runs: it renders and enters the frame the jump landed on, and
	# the *next* step is the one that leaves it.
	var exited := -1
	host._held = host._jump_queued
	host._jump_queued = false
	# `score.cpp:668-675`: **two** independent reasons not to send this, and the
	# reference states both. It is sent at most once per frame (`_exitFrameCalled`),
	# and never on a frame the movie has paused on. They are not the same guard --
	# the pause one is what makes the paused frame stop receiving the event, and the
	# latch is what stops a *resumed* frame from receiving it a second time.
	if not host._held and not paused(host) and not host._exit_frame_called:
		exited = host._index
		host._in_exit_frame = true
		host._exit_frame_called = true
		host._dispatch("exitFrame", host._frame_script(host._index))
		host._in_exit_frame = false

	# `score.cpp:696-698`: "the exitFrame event handler may have stopped this
	# movie", and the same test again at `:722-724` for a window switch. Both
	# return out of `update()` before the playhead is resolved, so the frame the
	# handler navigated to is entered by the movie that owns it and not a second
	# time by this step.
	if movie_gone(host, score_before):
		host._held = false
		return {"exited": exited, "frame": host._index}

	# `updateCurrentFrame`: the handler above decided where the playhead goes.
	# `go to the frame` -- how a room stands still at all -- reaches this as a
	# hold, and any other `go` has already written the destination.
	#
	# **The pause is read here, after the handler that may have set it**, which is
	# `score.cpp:443-452` exactly: `nextFrameNumberToLoad` starts at the current
	# frame and only the `if (!_playbackPaused)` arm moves it. `pause` is the one
	# hold that does not set `_held` -- it cannot, because `_held` means "a jump
	# chose the destination" and is consumed by this step -- so a pause read only at
	# the top of the *next* step parks the playhead one frame past the frame that
	# paused. Rating's reception desk is what that costs: `BLAEGOZ.dir` frame 1079
	# pauses, the behaviour that lifts the pause is attached to 1079 alone, and a
	# playhead parked on 1080 can never be clicked, so the key is uncollectable and
	# the room is a lock (`docs/bugs-closed.md` 52).
	#
	# The rest of what the pause suspends is suspended by returning here:
	# `prepareFrame` and `enterFrame` are guarded the same way in the reference
	# (`score.cpp:812`, `:827`), and this is the one place they are sent.
	if paused(host):
		host._held = false
		return {"exited": exited, "frame": host._index}
	if not host._held:
		host._index += 1
		if host._index >= host._score.frame_count:
			# **Running off the end of the score is Director's *other* return from a
			# `play`**, and the only one an interlude that simply ends ever reaches.
			# `score.cpp:462-487` pops the movie stack inside the
			# `nextFrameNumberToLoad >= getFramesNum()` branch, before the wrap to
			# frame 1, and requeues the parked play state on the way past
			# (`:474-476`). Only `play` ever pushes that stack, so the test is "is an
			# interlude outstanding" and the wrap below is the no-interlude case.
			#
			# Without it a `play frame X` whose destination runs to the end of its
			# score wraps to frame 0 and plays the movie again from the top, with the
			# handler that called `play` parked for ever — the same hang, and the
			# same cause, as the one `lingo_play_done` documents.
			if not host._return_from_play_stack():
				host._index = 0
			elif movie_gone(host, score_before):
				# The return crossed back into another container, which enters its own
				# frame; the rest of this step would enter it a second time.
				host._held = false
				return {"exited": exited, "frame": host._index}
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
