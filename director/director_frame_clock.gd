extends RefCounted
## What holds the playhead on a frame, and for how long.
##
## `docs/DIRECTOR_ENGINE.md` §6.1 steps 5-6, §9.1-9.2 and §10. The score's tempo
## channel is one byte and only one of its four meanings is a frame rate (§9.1);
## the other three stop the playhead rather than pace it. `director_score.gd`
## decodes the byte into `fps`, `delay_ms` and `wait_click`; this decides what
## the playhead does about it.
##
## Three properties of Director that are easy to lose in a port:
##
## **A wait is a state polled every tick, not a sleep** (§9.2). The movie keeps
## rendering and keeps taking input through one — which is the only way a
## wait-for-click frame is ever escaped — so a `delay` implemented by blocking
## loses the click that was supposed to end it.
##
## **`exitFrame` does not fire while a wait holds.** The wait check is step 6 of
## the tick and `exitFrame` is step 7, and "if waiting, the update ends here".
## So a room that holds itself with `go to the frame` stops holding itself for
## the length of the wait, and only the wait's own release resumes it.
##
## **A pending `go to` cancels every wait** (§9.2). A script that jumps out of a
## waiting frame is not made to sit out the rest of the wait first.
##
## Title-agnostic: this knows tempo codes and milliseconds, never a movie.

## What Director falls back to when no frame has ever set a tempo.
const DEFAULT_FPS := 15.0
## The most score ticks one real frame may be asked to make up.
##
## Not a Director rule. Director recomputes the next frame's due time from *now*
## once per update, so a tick that runs late makes that one frame longer and no
## debt survives; a port that accumulates `delta` instead owes every millisecond
## it lost. The compile-and-open pause at movie start is around half a second,
## which at 15 fps is seven frames of walk-state-machine owed in a single burst
## the moment the first frame is drawn. The cap keeps ordinary jitter smoothed —
## which the accumulator is there for — and refuses to replay a stall.
const MAX_CATCHUP_STEPS := 4

## Why a timed hold exists. Named rather than spelled out at each call site: the
## transition one is tested from outside this file, and a typo in a string
## literal would silently mean "no transition is playing" rather than fail.
const REASON_DELAY := "delay"
const REASON_TRANSITION := "transition"
## A colour cycle or a palette fade without *over time*, which §11 runs to
## completion inside one frame transition. Director spends that time in a loop
## that steps the palette and sleeps; expressing it as a hold keeps the process
## live and the frame the same length. See `director_palette_state.gd`.
const REASON_PALETTE := "palette"

## The rate the score last asked for. Carried forward across frames, as Director
## does: a frame with no tempo keeps the rate the last one set.
var fps := DEFAULT_FPS
## Seconds of score time owed but not yet stepped.
var _owed := 0.0
## Milliseconds left on a timed hold — a tempo delay, or a transition.
var _hold_ms := 0.0
## Why, for the HUD and for the harnesses. "" when nothing is holding.
var _hold_reason := ""
## The tempo channel's wait-for-click, released only by a click or a jump.
var _waiting_click := false
## The tempo channel's wait-for-sound: the channel it waits on, 0 for none, and
## which cue point in that sound releases it (`DirectorScore.CUE_NEXT`,
## `CUE_END`, or a 1-based index).
##
## Held rather than resolved, because whether a sound has finished is the mixer's
## question and this file may not know a mixer exists — the same split the
## palette and transition holds use. The caller polls `waiting_sound()` once a
## tick and calls `sound_arrived()` when the condition it names is met.
var _waiting_sound := 0
var _waiting_cue := 0


## The rate this movie plays at until its score writes a tempo, from the movie's
## own config chunk. `DEFAULT_FPS` is only what to assume when a movie states
## none -- it is not Director's answer, it is the engine's guess, and a movie
## that never writes a tempo ran at that guess for its whole length. Set once
## when a movie loads; see `DirectorConfig.default_tempo`.
var movie_default_fps := DEFAULT_FPS


func reset(rate: float = 0.0) -> void:
	fps = rate if rate > 0.0 else movie_default_fps
	_owed = 0.0
	_hold_ms = 0.0
	_hold_reason = ""
	_waiting_click = false
	_waiting_sound = 0
	_waiting_cue = 0


## The playhead has moved onto `frame`: take its tempo and arm whatever it waits
## for.
##
## Called on a genuine frame *change*, not once per tick. A room holding itself
## with `go to the frame` re-enters the same index every tick, and re-arming a
## two-second delay from there would hold it for ever rather than for two
## seconds. `director/director_runtime.gd:281` measures the same delay from the
## moment the frame was entered, for the same reason.
func enter_frame(frame: Dictionary) -> void:
	var rate := float(frame.get("fps", 0.0))
	if rate > 0.0:
		fps = rate
	var delay := float(frame.get("delay_ms", 0.0))
	if delay > 0.0:
		hold(delay, REASON_DELAY)
	_waiting_click = bool(frame.get("wait_click", false))
	_waiting_sound = int(frame.get("wait_sound_channel", 0))
	_waiting_cue = int(frame.get("wait_cue", 0))


## Hold the playhead for `ms`, whatever the reason. The longer of the two wins
## when something is already holding: a transition on a frame that also carries
## a tempo delay does not cut the delay short.
func hold(ms: float, reason: String) -> void:
	if ms <= 0.0:
		return
	if ms > _hold_ms:
		_hold_ms = ms
		_hold_reason = reason


## A click satisfies a wait-for-click and nothing else. A timed hold is not
## clickable-through: §9.2 gives the alternating cursor and the mouse-down
## release to the wait-for-click case alone.
func clicked() -> void:
	_waiting_click = false


## A queued `go to` cancels every wait (§9.2) — sound waits included, which is
## how a script escapes a frame whose sound was never going to arrive.
func release() -> void:
	_hold_ms = 0.0
	_hold_reason = ""
	_waiting_click = false
	_waiting_sound = 0
	_waiting_cue = 0


## The sound channel this frame is waiting on, and which cue point releases it.
## `{channel, cue}`, channel 0 when nothing is waiting. See `_waiting_sound` for
## why the condition is evaluated by the caller and not here.
func waiting_sound() -> Dictionary:
	return {"channel": _waiting_sound, "cue": _waiting_cue}


## The sound the frame was waiting for has finished, or its cue has passed.
func sound_arrived() -> void:
	_waiting_sound = 0
	_waiting_cue = 0


## Is something stopping the playhead from stepping?
func playhead_held() -> bool:
	return _hold_ms > 0.0 or _waiting_click or _waiting_sound > 0


## Is a transition still playing? Asked separately from `hold_reason` because a
## frame can wait for a click *and* carry a transition, and the caller that
## defers `enterFrame` past a transition needs the transition specifically rather
## than whichever hold happens to read as the dominant one.
func holding_transition() -> bool:
	return _hold_ms > 0.0 and _hold_reason == REASON_TRANSITION


## What a HUD should say is stopping the playhead. A click wait outranks a timed
## hold here because it is the one the player has to do something about.
func hold_reason() -> String:
	if _waiting_click:
		return "wait for click"
	if _waiting_sound > 0:
		return "wait for sound %d" % _waiting_sound
	return _hold_reason


## Score ticks due after `delta` seconds of real time.
##
## Ticks are counted whether or not the playhead is held, because they are the
## movie's clock and not the playhead's: film loops animate through a wait the
## same way they animate through a room that is holding itself still, which is
## what a character talking on a wait-for-click frame looks like. The caller
## asks `playhead_held()` separately to decide whether to run the frame step.
func tick(delta: float) -> int:
	if delta > 0.0:
		_hold_ms = maxf(0.0, _hold_ms - delta * 1000.0)
		if _hold_ms <= 0.0:
			_hold_reason = ""
	var step := 1.0 / maxf(fps, 0.001)
	_owed = minf(_owed + delta, step * MAX_CATCHUP_STEPS)
	var due := 0
	while _owed >= step:
		_owed -= step
		due += 1
	return due


## Forget time the movie spent loading rather than playing.
##
## The catch-up in `tick` is right for the case it was written for: a step that
## runs long because the machine was busy should not slow the movie down, so the
## debt is replayed and wall-clock pacing holds. It is wrong for a step that ran
## long because the engine was *decoding artwork*, because Director would not
## have been decoding then at all -- it preloads -- and replaying four steps to
## make the time back turns a one-frame stall into a visible jump.
##
## Measured, before `director_preloader.gd` existed: `strtgame` frame 38 spent
## 145.7 ms decoding inside one step and DAY1 frame 39 spent 105.5 ms, against a
## 66 ms step at 15 fps. Each of those bought a multi-step burst on the frame
## after it, which is what a menu background loop "jumping at the end" was.
##
## The preloader is the fix; this is the guard for what it cannot cover -- a
## marker jump straight onto cold art, or the first frame after a movie change.
## Called with the seconds actually spent, and discounts them from the debt.
func discount(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_owed = maxf(0.0, _owed - seconds)


## One line for a HUD: the rate, and what is stopping the playhead if anything.
func status() -> String:
	if not playhead_held():
		return "%.0f fps" % fps
	if _waiting_click:
		return "%.0f fps, waiting for a click" % fps
	if _waiting_sound > 0:
		return "%.0f fps, waiting for sound %d" % [fps, _waiting_sound]
	return "%.0f fps, holding %d ms (%s)" % [fps, int(ceilf(_hold_ms)), _hold_reason]
