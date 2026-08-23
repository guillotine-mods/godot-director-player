extends RefCounted
## One step of the movie, and the tick that decides whether one is due.
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
## step. It is also what answers §9.1's wait-for-video tempo cell, through the
## probe `tick` installs on the clock.
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
##
## **The tempo is no longer this function's alone** -- see `rearm_tempo`, which is
## the same arm run once per score step for a playhead that is standing still.
## What stays here is everything the reference does inside
## `if (_curFrameNumber != nextFrameNumberToLoad)`: the auto-puppet release, the
## frame's sounds, its palette and its transition. A transition re-armed every
## step is a wipe that never finishes, which is why the split is here and not a
## flag.
## The playhead took a score step and did not move: re-read the frame's tempo cell
## and arm it again. `bugs.md` 60.
##
## **`Score::update` calls `updateCurrentFrame()` and then `updateNextFrameTime()`
## every update cycle, not only when the frame number changes**
## (`score.cpp:640-711`). A room holding itself with `go to the frame` sets
## `_nextFrame` to the frame it is already on, so `updateCurrentFrame` takes its
## else-arm and does nothing (`score.cpp:497`, `:518-526`) -- and
## `updateNextFrameTime` still runs, reads the same cell, and re-arms the same
## instruction. So in Director a frame carrying a two-second delay and holding
## itself steps **once every two seconds, for ever**; this port armed the delay on
## a genuine frame *change* only, so it ran out once and the room then stepped at
## the movie's frame rate -- 15 or 8 times a second against Director's once every
## two seconds. Piposh 2 carries 36 delay frames totalling 74.0 s, 23 of them with
## a frame script; *Rating* carries 160 totalling 439.0 s.
##
## The comment that used to sit on `enter_frame` said re-arming "would hold it for
## ever rather than for two seconds", and that is the reasoning this replaces: a
## re-arm does not hold the frame, it *re-delays* it, and the playhead takes a step
## between every pair of delays. What the old comment describes would need the
## delay re-armed without the playhead ever being let through, which is not what
## the reference does and is not what this is.
##
## **Once per score step, never per tick.** `sync_frame_entry` runs at the head of
## every engine tick and this must not: `_arm_waits` *adds* a delay to whatever is
## already holding, so a per-tick arm would grow the hold by two seconds sixty
## times a second and the room really would stop for ever. It is called from the
## one place a step is actually taken, after `advance`, and only when the playhead
## is still on the frame it started on -- a step that *moved* is armed by
## `sync_frame_entry` on the next tick, from the frame it moved to, which is the
## same "arm the cell of the frame the playhead now stands on" rule read from the
## other end.
##
## Three things it deliberately does not re-run, all of them inside the
## reference's own `if (_curFrameNumber != nextFrameNumberToLoad)`: the frame's
## sounds (a line of speech restarted every step is the loop `marker()` used to
## produce), its palette, and its transition (a wipe re-armed every step never
## finishes). Those stay in `sync_frame_entry`.
##
## What it *does* re-arm besides the delay is the wait-for-click and the
## wait-for-sound, and that is the reference too rather than an oversight: the
## same cell is decoded by the same `updateNextFrameTime`, so a self-holding frame
## whose cell says 248 waits for a click again after each click releases it. That
## is the click-to-advance idiom a Director title is built on, and a port that
## armed it once turns the second click into a free step.
static func rearm_tempo(host) -> void:
	if host._score == null:
		return
	var frame: Dictionary = host._score.frame(host._index)
	if frame.is_empty():
		return
	host._clock.enter_frame(frame)


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


## Resolve this frame's transition, hold the playhead for as long as it takes,
## and start the drawing that fills the hold.
##
## Three sources in order: a puppet transition set from Lingo, which is one-shot
## and consumed here; the frame's own, which in a D5 score is a reference to a
## transition cast member; or nothing. `score.cpp:renderTransition`.
##
## **The hold and the drawing are armed together and from the same number**, and
## that is the whole of what keeps them in step. Director plays the transition
## synchronously inside `renderFrame` and the frame is not finished arriving
## until the last subframe has been drawn, so the duration is simultaneously how
## long the playhead stands still and how long the wipe has to cross the stage.
## Splitting them -- arming a hold here and starting a wipe somewhere else -- is
## how a transition ends up running past the frame it belongs to or finishing
## early over a playhead that is still waiting, and the movie's own scripts are
## timed against the first of those two numbers.
##
## The two frames come from `_grab_stage`, which needs a framebuffer and does not
## have one headless. The play is created either way: a play with nothing to
## compose still counts its steps against the hold, so the wiring is the same
## code on both, and only the pixels are missing.
##
## ## Which rectangle the play is sized by, and why it is `window_size()`
##
## `bugs.md` 118. Three call sites decide how big a transition's pictures are and
## they were asking three different questions: `director_preview.gd`'s
## `paint_capture` is armed at `window_size()` for a Movie-In-A-Window and
## `stage_size()` for the stage, `_grab_stage`'s framebuffer arm crops and
## resizes to `stage_size()` unconditionally, and this line built the play at
## `stage_size()`. All three are equal in all eight corpora, so nothing can
## disagree today and no harness can fail on it -- which is why the entry was
## written down rather than left to be rediscovered, and why this paragraph
## exists even though the value below does not change.
##
## **The reference answers `window_size()` and it answers it structurally, not by
## preference.** A transition is played by `Window::playTransition`
## (`transitions.cpp:158`) -- a method *on the window the frame change happened
## in*, reached from `Score::renderTransition` through `_window`
## (`score.cpp:900-919`). Both composited pictures are allocated from that
## window's own surface, `composeSurface->w` by `composeSurface->h`
## (`:194-199`), and a changed-area transition's clip is then clipped to
## `_window->getInnerDimensions()` (`:217`). There is no path in which a window's
## transition is sized by the stage.
##
## In this port `window_size()` is already that question asked correctly for both
## cases: `preview/windows.gd:size_of` answers the node's own `_window_rect` when
## it has one and **falls back to `stage_size()` when it does not**, and the stage
## node never has one. So this is a no-op on the stage by construction rather than
## by measurement, and it is the correct size for a Movie-In-A-Window whose rect
## is smaller than the stage -- which is the case the entry is about and which no
## container here can express.
##
## **`_grab_stage`'s framebuffer arm is the remaining half and is not in this
## file.** It crops to `stage_size()`, so on a desktop run a window smaller than
## the stage still hands this a stage-sized crop of something that is not the
## stage, and the play would then refuse the pair as mismatched. The patch is the
## same substitution in `scenes/director_preview.gd:_grab_stage`; it is reported
## rather than made because that file has another owner.
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
	# Dropped before the grabs, not after them. A transition that is still
	# running is drawn *by the paint* `_grab_arriving` performs, so leaving it in
	# place would capture the previous wipe's half-composited surface as the new
	# transition's arriving frame -- and two transitions back to back is the
	# normal case at a scene change, not a corner one.
	host._transition_play = null
	# Grabbed in this order and no other: the departing frame is whatever is
	# still on screen, so it has to be taken before anything repaints, and the
	# arriving frame is a paint of the frame the playhead has already moved to.
	var departing: Image = host._grab_stage()
	var arriving: Image = host._grab_arriving() if departing != null else null
	# `window_size()`, not `stage_size()` -- see the header for the reference's
	# answer and for why the two are equal on the stage by construction. `Play`
	# names its parameter `stage`, which is the older reading; renaming it is a
	# change to `director/director_transition.gd` for no behaviour, so it is left.
	host._transition_play = Transition.Play.new(
		transition, Vector2i(host.window_size()), departing, arriving)
	host._trace("f%d transition %s" % [host._index, host._transition_play.status()])
	return true


## Step the transition that is playing, if one is.
##
## **Once per engine tick, and the one thing in the tick that runs *after* the
## clock rather than before it.** Everything above the clock -- `idle`, the
## timeout, the video playheads, the palette effect -- is there because it can
## release a hold this tick and would cost a frame if it were evaluated after the
## clock had already decided the tick holds. This is the opposite case: it is
## driven *by* the hold rather than able to end one, and the clock's first act in
## `tick` is to take this tick's delta off the transition's remaining time. Asked
## before it, "is the transition still running" answers for a tick ago and the
## play lands one tick late; asked after it, the last step and the release of the
## hold are the same tick.
##
## Still per engine tick and not per score step: the score step below it is
## refused on most ticks at any ordinary tempo, and a wipe drawn at 4 fps is a
## cut with extra steps.
##
## The step index is derived from **elapsed time against the step duration**,
## not incremented once per call. `Score::playTransition` sleeps the remainder of
## `stepDuration` after each subframe and lets a slow step eat the next one's
## budget, so a transition is `steps` subframes spread over `duration`
## milliseconds however many of them the machine can afford -- and this port's
## engine tick is not Director's 1/60 s. Counting calls instead would make every
## transition as long as the frame rate happened to make it.
##
## The elapsed clock is the *same* `delta` the frame clock is running the hold
## down with, so the last step lands on the tick the hold releases rather than
## near it. `tools/transition_render.gd` asserts exactly that.
static func advance_transition(host, delta: float) -> void:
	var play = host._transition_play
	if play == null:
		return
	if not host._clock.holding_transition():
		# The hold has gone -- the transition finished, or a `go` cancelled the
		# frame it belonged to. Either way the arriving frame is what is on screen
		# now, so the play lands on its last step and is dropped.
		play.advance_to(play.steps)
		host._transition_play = null
		return
	play.elapsed_ms += maxf(delta, 0.0) * 1000.0
	play.advance_to(int(ceilf(play.elapsed_ms / maxf(play.step_duration, 0.001))))
	if play.finished:
		host._transition_play = null


## One tick of the movie: release what can be released, then take the one score
## step the clock owes, if it owes one.
static func tick(host, delta: float) -> void:
	# §9.1's wait-for-video, wired here because this is the one place that holds
	# both halves of it: `host._clock` is the clock that arms and polls the wait,
	# and `host` is what `preview/video.gd` needs to answer it.
	#
	# **Before anything in this function asks the clock a question**, and the order
	# is the rule rather than tidiness. `FrameClock._video_holds()` *clears* the
	# wait whenever the probe declines, and it is reached from `playhead_held()`
	# and from `status()` alike -- so a tick that consulted the clock first would
	# release the wait on the degrade path and then install a probe that had
	# nothing left to vouch for. `tools/frame_events.gd` states the same ordering
	# for its synthetic probe and fails if it arrives second.
	#
	# Idempotent and one `Callable.is_valid()` per tick; see `Video.install_probe`
	# for why the binding lives on the tick at all rather than in `preview/boot.gd`.
	Video.install_probe(host)
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
	# work. Time-boxed, so this cannot become the stall it exists to prevent.
	#
	# It used to be measured and handed to `FrameClock.discount`, on the argument
	# that a movie should not owe catch-up steps for time Director would have spent
	# preloading. There is no debt left to discount from: the clock re-arms
	# absolutely and drops what it could not afford, which is
	# `Score::updateNextFrameTime`'s own arithmetic, so the preloader's
	# milliseconds now cost exactly what every other millisecond in the tick costs
	# -- the frame they land on is longer, and the frame after it is not shorter.
	if host._preloader != null:
		host._preloader.run(host._index, host._preload_one, host._effective_ahead)
	# **One score step per tick at most, and no queue behind it.** The loop that
	# used to be here is the half of `bugs.md` 86 that was real: measured on that
	# entry's own movie, `torfim.dir` frame 20 at 80 fps against a 60 Hz cap, it
	# took 2.27 score steps per paint and dragged the paint rate down to 34.7 Hz
	# doing it, so two of every three states the movie stepped through were never
	# drawn. `Score::update` takes one score step per call and the projector's loop
	# calls it once per turn (`score.cpp:640-711`, `director.cpp:370-405`); see
	# `FrameClock.tick` for both numbers and for what this does to a movie whose
	# tempo is above the loop's own rate.
	var step_due: bool = host._clock.tick(delta)
	# §9.2's alternating wait-for-click cursor, pushed the moment the clock says
	# its answer moved -- armed, flipped once a second, or released. Immediately
	# after `tick` because `tick` is where the flip happens, and gated on the flag
	# because a cursor recompute walks the whole sprite stack and Director's own
	# cadence is not per frame either (`preview/cursor.gd`'s header). `bugs.md` 62.
	if host._clock.take_cursor_change():
		host._resolve_cursor()
	# **After the clock, and this is the one thing in the tick that is.** The
	# clock takes this tick's delta off the transition's remaining hold as its
	# first act, so asking it here is asking whether the transition is still
	# running *now* rather than whether it was running a tick ago -- and that is
	# what makes the play's last step land on the tick the hold releases instead
	# of the tick after it. See `advance_transition`.
	advance_transition(host, delta)
	if not step_due:
		# A transition draws at the engine's rate, not the score's. Everything
		# below is the score step, and at 4 fps this returns on fourteen ticks out
		# of fifteen -- so without this a 1,000 ms wipe would be composed sixty
		# times and painted four, which is a cut with extra steps.
		if host._transition_play != null:
			host.stage_redraw()
		return
	# Director's `pause` freezes the film loops with the playhead and a *hold*
	# does not: `Score::incrementFilmLoops` returns early on `_playbackPaused`
	# and runs straight through a wait-for-click. So this is tested ahead of the
	# tick count rather than beside the hold below -- `host._ticks` is the film
	# loops' clock, and a paused room whose characters keep talking is what
	# skipping it looks like. The rest of what `pause` suspends is one guard in
	# `director_preview.gd:_advance`.
	if not paused(host):
		# Counted before the hold is tested, not after: a wait-for-click frame
		# with a character talking on it must not freeze the character.
		host._ticks += 1
		if not host._clock.playhead_held():
			if host._pending_enter != null:
				# The transition has finished arriving; the frame it revealed gets its
				# `enterFrame` now.
				var resumed: Dictionary = host._pending_enter
				host._pending_enter = null
				host._dispatch("enterFrame", resumed)
			else:
				var stood_on: int = host._index
				var score_here = host._score
				host._advance()
				if host._score == score_here and host._index == stood_on:
					rearm_tempo(host)
				# The press has now been offered to a step, so it stops being owed.
				# What the button is *still* doing it says for itself, which is why
				# this is the live state and not `false`: a held button keeps reading
				# down, and `if the mouseDown then go(marker(1)) else go(marker(0))`
				# -- the charge-and-fire idiom -- needs both halves to be honest.
				host._mouse_down_seen = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# `stage_redraw` rather than `queue_redraw`: this is the *movie's* repaint and
	# `the updateLock` suppresses it. The engine's own repaints -- a resize, a
	# debug overlay, a palette change -- still call `queue_redraw` directly,
	# because Director's lock is over the movie's updates and not over the
	# window's.
	host.stage_redraw()


## The sprite behaviours the score has on stage at `index`, as
## `channel -> [start, end, lib, member, params, start, end, lib, member, params, ...]`.
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
## The flat array is the identity *and* the payload: two adjacent spans in one
## channel naming the same script are two sprites and must end and begin, which a
## `channel -> script` key cannot express, and `endSprite` has to be sent to a span
## the playhead has already left, which a lookup by current frame cannot answer.
## Five slots per behaviour because a D6+ span carries a *list* of them (2 spans of
## 158,001 in Piposh 2 do, both naming the same script twice) and the reference
## instantiates and messages each.
##
## **The fifth slot is the span's authored behaviour parameters** (`bugs.md` 83) --
## the string `director_score.gd:_read_interval` lifts out of the score's
## initialiser entry, e.g. `[#prGotoFrame: "mainmenu"]`. It rides in the identity
## array rather than being looked up at instantiation time, and that is deliberate
## in both directions: the instance is built from it, and **two adjacent spans of
## one channel that name the same script with different parameters are two
## different sprites** -- which is exactly what the diff in `sync_sprite_lifetime`
## has to see, because the second one needs its own instance seeded with its own
## values. With four slots those two spans compared equal and the second inherited
## the first's parameters for as long as the channel stayed occupied.
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
		var params := str(interval.get("initializer_params", ""))
		if str(interval["kind"]) == "frame":
			if end - start >= frame_span:
				continue
			frame_span = end - start
			out[0] = [start, end, lib, member, params]
			continue
		var channel := int(interval["channel"])
		if channel <= 0:
			continue
		var spec: Array = out.get(channel, [])
		spec.append(start)
		spec.append(end)
		spec.append(lib)
		spec.append(member)
		spec.append(params)
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
	while at + 5 <= spec.size():
		var lib := int(spec[at + 2])
		var member := int(spec[at + 3])
		var params := str(spec[at + 4])
		at += 5
		var script: Dictionary = host._script_in_lib(lib, member)
		if script.is_empty():
			continue
		# Channel 0 is the behaviour channel, whose sprite number *is* 0 -- see
		# `LingoInterpreter.behaviour_instance` for why that needs saying out loud.
		var script_channel := channel == 0
		if key == "beginsprite":
			# The one place a behaviour's authored parameters can be applied, because
			# it is the one place the instance is *made*: the reference seeds them
			# inside `Score::createScriptInstance`, between `new` and the first
			# message (`lingo-events.cpp:879-935`). `bugs.md` 83.
			interpreter.behaviour_instance(script, channel, script_channel, params)
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
