extends RefCounted
## What holds the playhead on a frame, and for how long.
##
## The tempo codes are the score format's, so they are taken from the file that
## reads the format rather than restated here where the two could drift apart.
##
## `docs/DIRECTOR_ENGINE.md` §6.1 steps 5-6, §9.1-9.2 and §10. The score's tempo
## channel is one byte and only one of its four meanings is a frame rate (§9.1);
## the other three stop the playhead rather than pace it. `director_score.gd`
## decodes the byte's one-shot meanings into `delay_ms`, `wait_click` and the
## sound waits, and this decides what the playhead does about them. The rate is
## read here, from the raw cell, for the reason below.
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
##
## **The rate has exactly one carrier, and it is this file.** A tempo that sets
## the rate is the only tempo whose effect outlives its own frame — a delay, a
## wait-for-click and a wait-for-sound are all discharged on the frame that
## armed them — so `fps` here is the whole of Director's `currentFrameRate` and
## a frame that carries no tempo must leave it alone. That is not a style
## preference; it is the bug this file was carrying. `director_score.gd` also
## resolves a per-frame `fps` by carrying the last tempo forward *and seeds that
## carry with a literal 15*, so every frame of a movie whose score never writes
## a tempo reported 15 fps, and `enter_frame` took it because it was greater
## than zero. `movie_default_fps` — the movie's own stated rate, which is the
## only thing such a movie has to go on — was therefore overwritten on the very
## first frame and never used. Measured on Piposh 1's `OPENING.dir`: 334 frames,
## not one tempo cell set, config states 8 fps, engine ran it at 15. Nearly
## twice too fast for the whole movie, silently. So `enter_frame` reads the
## *raw* tempo cell and ignores the score's resolved `fps` whenever the cell is
## there; see `rate_from_tempo`.

const Score := preload("res://director/director_score.gd")

## What Director falls back to when no frame has ever set a tempo *and the movie
## states none*. Reachable only for a movie whose config chunk will not read: a
## movie that has one always states a rate (`DirectorConfig.default_tempo`), and
## no container in either corpus states zero. The reference starts its score at
## 20 and overwrites it with the config's rate the moment the movie loads, which
## is the same "unreachable in practice" — the number itself is nobody's rule.
const DEFAULT_FPS := 15.0
## Director's own file-version word at which the tempo cell was renumbered.
##
## Below it the cell *is* the instruction and a value of 1-120 is the frame rate
## itself; at or above it the cell is a code and the operand beside it carries
## the number. See `rate_from_tempo`. The reference's threshold, in its own
## file-version numbering — the same word `DirectorConfig.version` reads.
const FILE_VERSION_D6 := 0x4C2
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
##
## Confirmed against the reference rather than inferred: the reference sets its
## score's current frame rate from this field of the config chunk the moment the
## movie's archive is loaded, before a single frame is read. So "the rate a movie
## starts at" is not a fallback to be reached for when the score is silent — it
## is the rate, until the score says otherwise.
var movie_default_fps := DEFAULT_FPS

## Director's file-version word for the movie being played, from its config
## chunk (`DirectorConfig.version`); 0 when the movie states none.
##
## Which tempo convention the score's cell is written in is a property of the
## *movie*, not of the value, and this is the only thing that says which. Zero
## reads as D6-or-later, because that is the only main-channel layout
## `director_score.gd` decodes: a frame dictionary that reaches this file came
## out of the 48-byte-record reader, so guessing the older numbering for a movie
## whose version went unread would misread every frame that did decode.
##
## Set alongside `movie_default_fps` when a movie loads.
var movie_file_version := 0


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
	_take_rate(frame)
	var delay := float(frame.get("delay_ms", 0.0))
	if delay > 0.0:
		hold(delay, REASON_DELAY)
	_waiting_click = bool(frame.get("wait_click", false))
	_waiting_sound = int(frame.get("wait_sound_channel", 0))
	_waiting_cue = int(frame.get("wait_cue", 0))


## Take whatever rate this frame asks for, and leave it alone if it asks for
## none.
##
## The raw tempo cell wins over the score's resolved `fps` whenever the frame
## carries one, because the resolved value cannot say *why* it is what it is: a
## movie whose score never writes a tempo gets the decoder's own seed reported
## on every frame, and taking it discards the movie's stated rate. See the
## header. A frame dictionary with no `tempo` key is a synthetic one — the
## harnesses build them — and keeps the old reading so a caller that only has a
## rate can still hand one over.
func _take_rate(frame: Dictionary) -> void:
	if not frame.has("tempo"):
		var stated := float(frame.get("fps", 0.0))
		if stated > 0.0:
			fps = stated
		return
	var rate := rate_from_tempo(int(frame.get("tempo", 0)), int(frame.get("tempo_cue", 0)))
	if rate > 0.0:
		fps = rate


## The frame rate a tempo cell asks for, or 0 for "this frame changes no rate".
##
## The cell is one byte and only one of its meanings is a rate; the rest stop
## the playhead instead, and those are decoded on the frame — `delay_ms`,
## `wait_click`, `wait_sound_channel` — because they are discharged where they
## are armed. This is the one meaning that persists, so it is read here.
##
## **Which convention the byte is in depends on the movie, not on the value.**
## The reference branches on the movie's file version and nothing else, and it
## has to: the two numberings collide outright. 246, 247 and 248 mean "set the
## rate", "delay" and "wait for a click" from D6 on, and in every version before
## that the same three bytes are delays of ten, nine and eight seconds. Read one
## movie's convention into the other's file and the collision is silent — a
## frame that meant to pause ten seconds sets a frame rate instead, or a frame
## that meant to run at 8 fps sets nothing at all and the movie keeps whatever
## rate it had. The second of those is not hypothetical: it is exactly the shape
## of the bug this file's header describes, arrived at from the other end.
##
## **D6 and later.** The byte is a code and the two bytes beside it in the same
## record are its operand. 246 sets the rate to the operand — that, and only
## that, is a rate. 247 delays for the operand in seconds, 248 waits for a
## click, 255 and 254 wait on sound channels 1 and 2 at the cue point the
## operand names, and *any other non-zero value* is a wait for the digital video
## playing in the sprite channel that value numbers. A zero cell asks for
## nothing and the rate stands.
##
## **Before D6.** The byte is the instruction. 1-120 *is* the frame rate, in
## frames per second, with no operand involved. Values from `256 - maxDelay`
## upward are a delay of `256 - value` seconds, where `maxDelay` is 60 from D4,
## 95 in D3 and 120 before that — so the delay band starts at 196, 161 and 136
## respectively and can never reach down into the 1-120 the rate occupies, which
## is why the rate rule needs no version of its own below D6. Of what is left,
## 128 waits for a click, 135 and 134 wait on sound channels 1 and 2 with no cue
## index, and 136 upward wait for the digital video in channel `value - 135`.
##
## **Out of range.** The reference range-checks nothing on either path: it takes
## the operand as the rate and divides by it. A zero or negative one would make
## the frame infinitely long, so that is the one value refused here — the rate
## stands instead, which is what a frame that set no rate would have done. An
## implausibly *large* one is passed through deliberately, because inventing a
## ceiling would hide a misread cell rather than report it; `tools/movie_tempo.gd`
## is where that is checked, against the whole corpus, where a wrong offset shows
## up as a distribution rather than as one odd frame.
##
## Unverified below D6: `director_score.gd` decodes the D6-and-later
## main-channel layout only, and both corpora here are D6 or later (Piposh 2's
## containers state file version 0x57E, Piposh 1's 0x73A, against the D6
## threshold of 0x4C2), so nothing available can exercise the older branch. It
## is implemented from the reference and says so, which is not the same as
## absent.
func rate_from_tempo(tempo: int, tempo_cue: int) -> float:
	if tempo <= 0:
		return 0.0
	if movie_file_version != 0 and movie_file_version < FILE_VERSION_D6:
		return float(tempo) if tempo <= 120 else 0.0
	if tempo != Score.TEMPO_SET_FPS:
		return 0.0
	return float(tempo_cue) if tempo_cue > 0 else 0.0


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


## Everything a save state has to carry, and nothing derived.
##
## `movie_default_fps` and `movie_file_version` are deliberately absent: both are
## read off the movie's own config chunk when it is adopted, so a restore that
## reopened the container already has them, and writing them down would be
## storing a second copy of the file's own bytes for the two to disagree over.
##
## The rest is genuinely state. A frame that armed a two-second delay and is
## 1,400 ms into it is *holding*, and a save that dropped the hold would come
## back on a frame that immediately stepped -- which is a different movie from
## the one that was saved, at exactly the moment somebody is trying to reproduce
## a timing bug.
func state() -> Dictionary:
	return {
		"fps": fps,
		"owed": _owed,
		"hold_ms": _hold_ms,
		"hold_reason": _hold_reason,
		"waiting_click": _waiting_click,
		"waiting_sound": _waiting_sound,
		"waiting_cue": _waiting_cue,
	}


func restore_state(from: Dictionary) -> void:
	if from.is_empty():
		return
	fps = float(from.get("fps", fps))
	_owed = float(from.get("owed", 0.0))
	_hold_ms = float(from.get("hold_ms", 0.0))
	_hold_reason = str(from.get("hold_reason", ""))
	_waiting_click = bool(from.get("waiting_click", false))
	_waiting_sound = int(from.get("waiting_sound", 0))
	_waiting_cue = int(from.get("waiting_cue", 0))


## One line for a HUD: the rate, and what is stopping the playhead if anything.
func status() -> String:
	if not playhead_held():
		return "%.0f fps" % fps
	if _waiting_click:
		return "%.0f fps, waiting for a click" % fps
	if _waiting_sound > 0:
		return "%.0f fps, waiting for sound %d" % [fps, _waiting_sound]
	return "%.0f fps, holding %d ms (%s)" % [fps, int(ceilf(_hold_ms)), _hold_reason]
