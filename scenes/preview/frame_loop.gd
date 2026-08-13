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
## The per-frame callouts and the timeout clock, which are the two things this
## loop owes Lingo on a clock rather than on a score event. See its header.
const Actors := preload("res://scenes/preview/actors.gd")
## The digital-video playheads, stepped once per engine tick beside the two
## above. See the call site in `tick` for why they cannot be stepped per score
## step.
const Video := preload("res://scenes/preview/video.gd")


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
	# The timeout clock, **before the clock is asked anything and once per engine
	# tick**, which is `Score::update`'s "process timeout events independently of
	# the frame delay" (`score.cpp:638-643`). A movie at 4 fps must not get its
	# three-minute idle timeout a quarter of a second late; more importantly, a
	# movie whose playhead is *held* -- `go to the frame`, which is where a title
	# spends its idle time -- takes no steps at all, and a timeout hung off the
	# step would never fire on exactly the frames it exists for.
	if Actors.check_timeout(host) and movie_gone(host, score_before):
		return
	# Cue points and the tempo channel's wait-for-sound, before the clock. The
	# fade ramp they interact with is stepped by `AudioDirector` itself, one
	# process priority earlier.
	host._pump_sound(delta)
	# Every playing digital video, on the engine's clock and **before** the frame
	# clock is asked anything -- the same placement, and the same argument, as
	# `idle` and the timeout above.
	#
	# It has to be here rather than in the step loop below because the movie that
	# needs it is standing still: Magic Hat's `Check avi` runs `go(the frame)`
	# until `sprite(3).movieTime >= FilmLen`, so the score takes no step at all for
	# the ten seconds the logo plays. A playhead carried by the step would never
	# move, the guard would never come true, and `the duration` becoming real would
	# have converted a clean skip into a hang -- which is exactly the regression
	# `tools/video_fallback.gd` exists to catch.
	#
	# The **scaled** delta, so the fast-forward key speeds a video up with the rest
	# of the movie instead of leaving one sprite running at wall-clock speed inside
	# a score that is not.
	Video.advance(host, delta)
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
	# `stage_redraw` rather than `queue_redraw`: this is the *movie's* repaint and
	# `the updateLock` suppresses it. The engine's own repaints -- a resize, a
	# debug overlay, a palette change -- still call `queue_redraw` directly,
	# because Director's lock is over the movie's updates and not over the
	# window's.
	host.stage_redraw()


## The sprite behaviours the score has on stage at `index`, as
## `channel -> [start, end, lib, member, start, end, lib, member, ...]`.
##
## **A "sprite" is a score *span*, not a channel that happens to be occupied.**
## That is the whole of what decides `beginSprite`/`endSprite`, and getting it
## from anywhere else is what turns these two messages into a per-frame storm.
## The reference keeps `_startFrame`/`_endFrame` on the channel, copies them from
## the sprite record (`channel.cpp:69-71`, `:685-688`) and asks one question in
## each direction: `Score::killScriptInstances` ends a sprite when
## `frameNum < channel->_startFrame || frameNum > channel->_endFrame`, and
## `Score::createScriptInstances` begins one when the frame *is* in range and the
## channel has no instances yet (both `lingo-events.cpp:845-993`). Neither looks
## at the member, the puppet flag or whether the channel drew anything. So a
## score that animates a channel by swapping its member for forty frames is **one**
## sprite and sends **one** `beginSprite`, and a puppeted member swap from Lingo
## sends none at all.
##
## This port already has the spans: `director_score.gd:_read_interval` decodes the
## score's own interval entries, which is where a behaviour is attached to a
## channel in the first place, and each carries `start`, `end` and the script.
## Only spans that name a behaviour are decoded at all, so a movie's sprites
## without scripts cost nothing here -- DAY1 has 425 sprite intervals against a
## score whose frames hold far more sprites than that.
##
## The flat int array is the identity *and* the payload: two adjacent spans in one
## channel naming the same script are two sprites and must end and begin, which a
## `channel -> script` key cannot express, and `endSprite` has to be sent to a span
## the playhead has already left, which a lookup by current frame cannot answer.
## Four ints per behaviour because a D6+ span carries a *list* of them (2 spans of
## 158,001 in Piposh 2 do, both naming the same script twice) and the reference
## instantiates and messages each.
##
## **Channel 0 is the behaviour channel and it is in here**, which is the half of
## this that the whole of `bugs.md` 87 actually turns on. Director's score has one
## row above the sprite channels holding the frame's own behaviour; it is "sprite
## 0", it is an instance, and it receives `beginSprite` and `endSprite` when the
## playhead enters and leaves its span like any other sprite. Magic Hat is built
## on that and on nothing else: `BehaviorScript 33 - init album` is a **frame**
## interval spanning [34..34] whose only handler is `on beginSprite`, and `init
## magic` [69], `init tools` [84], `init login` [9], `init teuda` [99], `init
## credits` [114], `init intro` [124] and `init retro` [134] are the same shape --
## seven of this title's eight screens are set up by a behaviour-channel
## `beginSprite` and by nothing else. Treating only sprite channels would have sent
## 32 messages on the way into the album and still not run the one handler the bug
## is about.
##
## The reference does *not* send these two to its script channel: `Score::
## killScriptInstances` and `Score::createScriptInstances` manage
## `_scriptChannelScriptInstance`'s lifetime (`lingo-events.cpp:845-856`,
## `:965-978`) and never call `processEvent` for it, where the channel loop below
## each of them does. That is a gap in ScummVM rather than in Director, and the
## evidence is outside the port: this title shipped, and seven of its screens are
## dead without the message.
##
## **The narrowest span covering the frame wins, for channel 0 only**, because the
## behaviour channel is one row and can hold one span at a time. The decode does
## produce overlapping frame intervals -- DAY1's `what to do everyframe` covers the
## whole movie underneath the room-specific ones -- and `preview/scripts.gd:
## for_frame` already resolves them this way to decide which script gets
## `exitFrame`. Resolving the lifetime by a different rule than the dispatch would
## mean sending `beginSprite` to one script and `exitFrame` to another on the same
## frame.
static func sprite_behaviours_at(score, index: int) -> Dictionary:
	var out: Dictionary = {}
	if score == null:
		return out
	var frame_span := 0x7FFFFFFF
	for interval in score.intervals():
		var start := int(interval["start"])
		var end := int(interval["end"])
		if index < start or index > end:
			continue
		var lib := int(interval["script_cast_lib"])
		var member := int(interval["script_member"])
		if str(interval["kind"]) == "frame":
			if end - start >= frame_span:
				continue
			frame_span = end - start
			out[0] = [start, end, lib, member]
			continue
		var channel := int(interval["channel"])
		if channel <= 0:
			continue
		var spec: Array = out.get(channel, [])
		spec.append(start)
		spec.append(end)
		spec.append(lib)
		spec.append(member)
		out[channel] = spec
	return out


## Send `beginSprite` or `endSprite` to one channel's behaviours.
##
## **It stops at the sprite tier.** `lingo-events.cpp:620-625` queues one element
## per behaviour on the channel and then `break`s out of the fall-through that
## would have added the cast, frame and movie tiers -- "These events do not go any
## further than the sprite behaviors". So this calls `call_in_script`, which runs
## the named handler in that script and nowhere else, rather than `_dispatch`,
## whose movie-script fallback would hand a movie-wide `on beginSprite` every
## sprite in the picture.
##
## **The instance is created whether or not the script answers**, because that is
## what `Score::createScriptInstances` does: it instantiates every behaviour on the
## span and only then sends the message. It is also what makes `me` and
## `me.spriteNum` correct for the *later* messages -- a button whose behaviour has
## only `on mouseUp me` still needs an instance, and creating it here means the
## instance exists from the moment the sprite appears rather than from the first
## click on it.
##
## `the currentSpriteNum` is saved and restored around the call for the reason
## `event_chain.gd:run` gives: a behaviour may `sendSprite` another sprite, and the
## outer one has to read its own channel again on the way back.
static func send_sprite_message(host, handler: String, channel: int,
		spec: Array) -> void:
	var interpreter = host._interpreter
	if interpreter == null:
		return
	var key := handler.to_lower()
	var at := 0
	while at + 4 <= spec.size():
		var lib := int(spec[at + 2])
		var member := int(spec[at + 3])
		at += 4
		var script: Dictionary = host._script_in_lib(lib, member)
		if script.is_empty():
			continue
		# Channel 0 is the behaviour channel, whose sprite number *is* 0 -- see
		# `LingoInterpreter.behaviour_instance` for why that needs saying out loud.
		var script_channel := channel == 0
		if key == "beginsprite":
			interpreter.behaviour_instance(script, channel, script_channel)
		host._tally(host._sent, handler)
		if not bool(interpreter.call("_script_has_handler", script, key)):
			if key == "endsprite":
				interpreter.release_behaviour(script, channel)
			continue
		host._tally(host._ran, handler)
		var outer := 0
		if host._host != null:
			outer = int(host._host.current_sprite_num)
			host._host.current_sprite_num = channel
		# §6.3's step budget, per message: `MAX_STEPS` stops a runaway loop inside
		# one dispatch, and a count that accumulates across a session eventually
		# aborts every handler.
		interpreter.reset_steps()
		host._sprite_message += 1
		interpreter.call_in_script(handler, script, channel, script_channel)
		host._sprite_message -= 1
		if host._host != null:
			host._host.current_sprite_num = outer
		if key == "endsprite":
			# `channel->_scriptInstanceList.clear()` (`lingo-events.cpp:872`): the
			# sprite is gone and so is its property bag. Without this a screen
			# re-entered later would find its behaviour still holding the values it
			# left, which is the one thing an *instance* is for.
			interpreter.release_behaviour(script, channel)


## `beginSprite` for every sprite the playhead has just entered, `endSprite` for
## every one it has just left.
##
## **Ends before begins, always.** `Score::update` calls `killScriptInstances`
## ahead of the frame load (`score.cpp:700-702`) and `createScriptInstances` after
## it, from inside the render (`score.cpp:1029`), so a screen tears its own
## registry down before the next screen builds one. Magic Hat depends on exactly
## that: `DisableAllMenus()` in one screen's `beginSprite` and `EnableMenu` in the
## next both write one global property list keyed by channel, and running them the
## other way round leaves the arriving screen's entries overwritten by the
## departing screen's.
##
## **This is a diff, not an edge trigger.** It compares the score's spans at the
## current frame against what is on stage and is a no-op when they agree, so the
## caller may run it on every frame entry without knowing whether the playhead
## moved, how it moved, or whether a jump skipped past a span entirely. A `go`
## that crosses forty frames ends every span it left and begins every span it
## landed in, in one pass, which a "did the frame number increase by one" trigger
## could not do.
##
## **Two divergences from the reference, both deliberate and both measured.**
##
## The reference sends `endSprite` *before* the new frame is loaded, against the
## frame number the playhead is about to reach; this sends it after. There is no
## "before the load" moment here to hang it on: `lingo_go_frame` writes `_index`
## inside the `go`, so by the time any step notices, the playhead has already
## moved. What an `on endSprite` handler sees is therefore the arriving frame's
## sprites rather than the departing frame's. Every `endSprite` in this corpus
## works on the global registries by channel number, which do not care.
##
## The reference sends `beginSprite` from inside the render, between `prepareFrame`
## and `enterFrame` (`score.cpp:806-830`, and "Window is drawn between the
## prepareFrame and enterFrame events"). This is called from
## `director_preview.gd:_enter_frame_or_defer`, which is the one door every frame
## entry in this port goes through -- the step loop, the first frame of a movie and
## a `go to movie` alike -- and which is called from exactly that position. The
## divergence is only at boot, where this port sends `prepareMovie`/`startMovie`
## before the first frame's `prepareFrame` and the reference sends `beginSprite`
## before `startMovie` (`score.cpp:317-321`). Later here rather than earlier is the
## safe direction: a `beginSprite` handler that reads a global the movie script
## sets in `prepareMovie` would find it VOID the other way round.
##
## **Nothing is sent when a movie is left.** The reference destroys the `Score` and
## with it every `_scriptInstanceList`, and `killScriptInstances` is called from
## one place only -- `score.cpp:702`, inside `update()`. So `go to movie` sends no
## `endSprite`, and neither does the end of the movie; `movie_session.gd` clears
## the record instead.
static func sync_sprite_lifetime(host) -> void:
	if not host._lingo_on or host._score == null or host._interpreter == null:
		return
	var begun: Dictionary = host._begun_sprites
	var now: Dictionary = sprite_behaviours_at(host._score, host._index)
	var score_before = host._score
	# The depth counter is restored here as well as decremented per message,
	# because a GDScript runtime error inside a handler aborts the statement it
	# happened in and carries on: the matching `-= 1` in `send_sprite_message` is
	# one of the statements it can skip. A counter left standing would refuse
	# every `go`, `play` and `updateStage` in the movie for the rest of the
	# session -- a silent, permanent freeze whose cause is nowhere near the error
	# that started it. Restored rather than zeroed, so a nested call (a
	# `sendSprite` from inside `beginSprite`) still unwinds to its own caller's
	# depth.
	var outer_depth: int = host._sprite_message
	var leaving: Array = []
	for channel in begun:
		if now.get(channel, null) != begun[channel]:
			leaving.append(int(channel))
	leaving.sort()
	for channel in leaving:
		var was: Array = begun[channel]
		# Erased before the message, not after: an `endSprite` handler is entitled
		# to ask the engine anything, and a record that still claims the sprite is
		# on stage would answer that it is.
		begun.erase(channel)
		send_sprite_message(host, "endSprite", channel, was)
		if movie_gone(host, score_before):
			host._sprite_message = outer_depth
			return
	var arriving: Array = []
	for channel in now:
		if not begun.has(channel):
			arriving.append(int(channel))
	arriving.sort()
	for channel in arriving:
		begun[channel] = now[channel]
		send_sprite_message(host, "beginSprite", channel, now[channel])
		if movie_gone(host, score_before):
			host._sprite_message = outer_depth
			return
	host._sprite_message = outer_depth


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

	# `the perFrameHook` and `the actorList`, each sent `stepFrame`
	# (`preview/actors.gd`). **Here**, which is `score.cpp:731-770`: as soon as
	# the frame switch is done, ahead of `prepareFrame` and the draw, and skipped
	# on a frame carrying a transition -- the reference calls it once per
	# transition subframe instead, and this port has no subframes to hang it on.
	#
	# A hook or an actor may `go`, which replaces the frame under everything
	# below exactly as an `exitFrame` handler may, so the same guard follows it.
	if not host._clock.holding_transition():
		Actors.step_frame(host)
		if movie_gone(host, score_before):
			host._held = false
			return {"exited": exited, "frame": host._index}

	var script: Dictionary = host._frame_script(host._index)
	host._dispatch("prepareFrame", script)
	# The draw. Godot paints at the end of the process frame rather than here, so
	# this is a request and not a completed paint: what `enterFrame` writes below
	# still lands in the same painted frame, where Director would have shown it
	# on the next one. A real divergence, and the cheapest one on offer -- the
	# alternative is deferring every `enterFrame` by a whole frame.
	host.stage_redraw()
	host._enter_frame_or_defer(script)
	return {"exited": exited, "frame": host._index}
