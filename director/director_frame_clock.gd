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
## Four properties of Director that are easy to lose in a port:
##
## **A step the engine could not afford is dropped, not owed back.** The next
## frame's due time is recomputed from *now* once per update cycle, so a cycle
## that ran long makes that one frame longer and leaves nothing behind it. This
## is the property a port loses by writing the obvious accumulator, and it is
## the whole subject of `tick`, which carries the reference lines and the
## measurement.
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
##
## **And the cell is not the only thing that can name a tempo.** `puppetTempo`
## names one from Lingo, and §9.1 gives it precedence over the score's until the
## score writes a tempo or the effective tempo changes. That is a rule about
## *which* instruction is in force on a frame rather than about what a byte
## means, so it is resolved here and not in the decoder: `director_score.gd`
## reads the byte a frame carries, and this decides whether that byte or the
## puppet's is what the playhead obeys. See `_effective_tempo`.

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
## The numbering a `puppetTempo` argument is read in, whatever the movie's own
## file version is.
##
## **This is the one place the version test is deliberately not the movie's**, so
## the reason is written here rather than left to be rediscovered. The renumbering
## at D6 is a change to the *score format*: the tempo channel gained an operand
## field, so the cell became a code and the number moved beside it. A
## `puppetTempo` argument is not in the file at all — it is one Lingo integer,
## with nowhere for an operand to live — so there is nothing about it for a file
## format to have renumbered, and the verb has meant the same thing since D2:
## 1-120 is frames per second, 128 waits for a click, and the bands above are the
## sound, video and delay waits (§9.1's pre-D6 list).
##
## The reference disagrees, and it is worth saying exactly how, because this is a
## divergence and not an oversight. `Score::updateNextFrameTime` substitutes
## `_puppetTempo` into the same local the frame's cell would have filled and then
## decodes that local under the *movie's* version, so in a D6 movie
## `puppetTempo 30` is read as "wait for the digital video in channel 30", which
## resolves to no video and releases immediately. Under that reading the verb
## does nothing at all in any D6 or later movie — a verb Macromedia documented
## and shipped through D8. Reading one Lingo integer in the vocabulary the verb
## was defined in is the reading that leaves it working, and it costs nothing:
## no score cell reaches this constant, so the rule that a *cell* is read by file
## version and never by value is untouched.
const PUPPET_TEMPO_NUMBERING := FILE_VERSION_D6 - 1

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
## Seconds of the movie's own clock still to run before the next score step is
## due. Counted down by `tick` and **re-armed by assignment**, never by addition;
## that one word is the whole of Director's dropped-step rule. See `tick`.
var _due_in := 0.0
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
## The tempo channel's wait-for-video: the sprite channel whose digital video
## holds the playhead, 0 for none.
##
## Held the same way the sound wait is held, and released the same way — by
## asking something outside this file whether the condition still holds. The
## difference is who does the asking: a sound wait is polled by the caller once a
## tick (`preview/sound.gd`), and this is polled *here*, through `video_probe`,
## because there is no equivalent pass to hang it on and an unpolled wait is a
## playhead nothing ever releases. The reference clears its own
## `_waitForVideoChannel` inside `isWaitingForNextFrame` for the same reason, so
## a query that releases the wait it reports on is its shape rather than a
## shortcut taken here.
var _waiting_video := 0
## Milliseconds left of the *transition* specifically, inside `_hold_ms`.
##
## Tracked separately because `holding_transition` is a question about the
## transition and not about whichever hold happens to be the longest. A frame
## carrying a two-second tempo delay and a half-second wipe holds for both, and
## with one counter the wipe is invisible: `hold` keeps the longer, the reason
## reads "delay", and `_enter_frame_or_defer` — which exists to keep `enterFrame`
## from running over a frame that is still arriving — sends the event straight
## through the wipe.
var _transition_ms := 0.0

## The rate or wait a script named with `puppetTempo`, 0 for none.
##
## Read in `PUPPET_TEMPO_NUMBERING`, not the movie's; see that constant.
var _puppet_tempo := 0
## The score's own effective tempo on the frame before this one -- the cell it
## carried, or the carried-forward one if it carried none, and never the puppet's
## value. §9.1's release condition is "the score writes a tempo *or the effective
## tempo changes*", and this is the second half of it.
##
## Not the puppet's value, and the reference stores exactly that: it assigns
## `_lastTempo` *after* substituting `_puppetTempo`, so the next frame compares
## the score's tempo against the puppet's, finds them different, and cancels. The
## puppet therefore survives exactly one frame in the reference whatever the
## movie does — which contradicts both §9.1 and Macromedia's own description of
## the verb ("remains in effect until the tempo channel specifies a new tempo").
## Recording the score's side here is what makes the release condition mean what
## it says.
var _last_tempo := 0
## The last tempo cell that named a rate, carried forward for a frame that
## carries none (the reference's `scoreCachedTempo`). Only a cell of 1-120 is
## cached, which pre-D6 is exactly the rates; from D6 the rates are written as
## 246 with an operand, so this stays 0 for every container in both corpora.
var _cached_tempo := 0

## Answers "is the digital video in this sprite channel still running?", for the
## one wait this file cannot resolve on its own.
##
## Unset by default, and the default is the whole of the degrade rule: with no
## decoder installed every video wait reports *finished*, which releases the
## playhead on the first poll. That is the same answer a frame waiting on a
## channel holding no video gets in Director, and it is the only safe default —
## the alternative, holding until something says otherwise, is a movie that stops
## dead on a frame nothing will ever release.
##
## The contract is the reference's condition, negated: it keeps waiting while the
## channel `isActiveVideo()` **and** its `_movieRate` is non-zero, so a paused
## video does not hold the playhead and neither does a channel that is not a
## video at all. Installed from outside, by whatever owns digital video.
var video_probe := Callable()


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
	# Zero, so the first tick of a movie steps rather than waiting out a period.
	# `Score::startPlay` sets `_nextFrameTime = 0` (`score.cpp:299`), which its
	# `millis < _nextFrameTime` test reads as "due now".
	_due_in = 0.0
	_hold_ms = 0.0
	_transition_ms = 0.0
	_hold_reason = ""
	_waiting_click = false
	_waiting_sound = 0
	_waiting_cue = 0
	_waiting_video = 0
	# The puppet belongs to the movie that set it: a `puppetTempo` is not carried
	# into the next container, and neither is the carry-forward it is measured
	# against. §5.5 drops the sprite puppets across the same boundary.
	_puppet_tempo = 0
	_last_tempo = 0
	_cached_tempo = 0


## The playhead has moved onto `frame`: take its tempo and arm whatever it waits
## for.
##
## Called on a genuine frame *change*, not once per tick. A room holding itself
## with `go to the frame` re-enters the same index every tick, and re-arming a
## two-second delay from there would hold it for ever rather than for two
## seconds. `director/director_runtime.gd:281` measures the same delay from the
## moment the frame was entered, for the same reason.
## **The frame's own decoded waits are not what is armed.** They are the score's
## reading of the cell the frame carries, and the instruction actually in force
## may be a different one — a `puppetTempo` overriding it, or the carried-forward
## cell on a frame that writes none. So the effective instruction is resolved
## first and then decoded, through the score's own decoder rather than a second
## copy of it. On a frame where nothing overrides anything the two are the same
## byte and the same answer, which is every frame in both corpora.
func enter_frame(frame: Dictionary) -> void:
	# A frame dictionary with no `tempo` key is a synthetic one — the harnesses
	# build them, and `preview/save_state.gd` restores one — so it carries a rate
	# and its waits already decoded, and there is no cell to resolve.
	if not frame.has("tempo"):
		var stated := float(frame.get("fps", 0.0))
		if stated > 0.0:
			fps = stated
		_arm_waits(frame)
		return
	var in_force := _effective_tempo(int(frame.get("tempo", 0)), int(frame.get("tempo_cue", 0)))
	var rate := rate_for(int(in_force["tempo"]), int(in_force["operand"]), int(in_force["version"]))
	if rate > 0.0:
		fps = rate
	_arm_waits(Score.tempo_waits(
		int(in_force["tempo"]), int(in_force["operand"]), int(in_force["version"])))


## Which tempo instruction this frame actually obeys, and in which numbering.
##
## Three sources, resolved the way `Score::updateNextFrameTime` resolves them:
##
## 1. The **cell this frame carries**, if it carries one. A frame that writes a
##    tempo also cancels any puppet, which is §9.1's first release condition and
##    the reason authors could rely on the score taking the wheel back.
## 2. The **cell carried forward**, for a frame that writes none. Only a cell
##    that named a rate is carried (`_cached_tempo`), so this re-states the rate
##    rather than re-arming a wait.
## 3. The **puppet**, when neither of the above changed anything. It is cancelled
##    the moment the score's own effective tempo moves, which is §9.1's second
##    release condition, and it is read in `PUPPET_TEMPO_NUMBERING` because a
##    Lingo integer is not a score cell.
##
## Returned as the triple the decoders need rather than applied here, because the
## rate and the waits are taken by different code and must not be able to
## disagree about which instruction they were reading.
func _effective_tempo(cell: int, operand: int) -> Dictionary:
	if cell > 0 and cell <= 120:
		_cached_tempo = cell
	var scored := cell if cell != 0 else _cached_tempo
	var out := {"tempo": scored, "operand": operand, "version": movie_file_version}
	if cell != 0 or scored != _last_tempo:
		_puppet_tempo = 0
	elif _puppet_tempo != 0:
		# The puppet carries no operand: there is nowhere in a one-argument Lingo
		# call for one, which is the other half of why it cannot be read in the
		# D6 numbering, where every meaning but the video wait needs one.
		out = {"tempo": _puppet_tempo, "operand": 0, "version": PUPPET_TEMPO_NUMBERING}
	_last_tempo = scored
	return out


## `puppetTempo <value>` — override the score's tempo until it takes the wheel
## back. Zero hands it back immediately.
##
## **Applied at the call and not only at the next frame entry.** The reference
## re-resolves the tempo once per update cycle, so a puppet set inside a handler
## is in force on the very next step even if the playhead has not moved; this
## port resolves it on a genuine frame *change*, because that is the only place a
## delay may be re-armed without holding a self-looping room for ever. A room
## holding itself with `go to the frame` never changes frame, so a puppet that
## waited for one would never take effect at all — and a room holding itself is
## exactly where a script that sets the tempo is written.
func set_puppet_tempo(value: int) -> void:
	_puppet_tempo = maxi(value, 0)
	if _puppet_tempo == 0:
		# Not a rate change. Director leaves `_currentFrameRate` wherever it was
		# until something names a new one, so handing the tempo back does not
		# restore the rate the score last set — it stops overriding the next one.
		return
	var rate := rate_for(_puppet_tempo, 0, PUPPET_TEMPO_NUMBERING)
	if rate > 0.0:
		fps = rate
	_arm_waits(Score.tempo_waits(_puppet_tempo, 0, PUPPET_TEMPO_NUMBERING), false)


## What a script last asked for with `puppetTempo`, 0 for none. For the harnesses
## and the HUD; the precedence itself is `_effective_tempo`'s.
func puppet_tempo() -> int:
	return _puppet_tempo


## Arm the four one-shot holds a tempo instruction can carry.
##
## A delay is *added* to whatever is already holding and the three waits are
## *assigned*, which is the reference's shape: a delay moves the next frame's due
## time and the waits are flags set on the frame that armed them. Assignment is
## also what clears them — a frame whose tempo waits for nothing must not inherit
## the wait the frame before it was released from.
##
## `clearing` is false for the one caller that is not a frame entry.
## `set_puppet_tempo` arms a tempo *inside* a frame that has already armed its
## own, and a script raising the frame rate must not cancel the wait-for-click
## the frame it is standing on is holding for: the reference never clears a wait
## flag from `updateNextFrameTime` either, only ever sets one, and the flags go
## down when their own condition is met.
func _arm_waits(waits: Dictionary, clearing := true) -> void:
	var delay := float(waits.get("delay_ms", 0.0))
	if delay > 0.0:
		hold(delay, REASON_DELAY)
	var click := bool(waits.get("wait_click", false))
	var sound := int(waits.get("wait_sound_channel", 0))
	var video := int(waits.get("wait_video_channel", 0))
	if clearing or click:
		_waiting_click = click
	if clearing or sound > 0:
		_waiting_sound = sound
		_waiting_cue = int(waits.get("wait_cue", 0))
	if clearing or video > 0:
		_waiting_video = video


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
	return rate_for(tempo, tempo_cue, movie_file_version)


## `rate_from_tempo` with the numbering named rather than taken from the movie.
##
## Static and parameterised for the same reason `Score.tempo_waits` is: a
## `puppetTempo` names a tempo that never came out of a frame, and its numbering
## is the verb's rather than the container's (`PUPPET_TEMPO_NUMBERING`). One
## reader, two callers, no second copy of the collision.
static func rate_for(tempo: int, tempo_cue: int, file_version: int) -> float:
	if tempo <= 0:
		return 0.0
	if file_version != 0 and file_version < FILE_VERSION_D6:
		return float(tempo) if tempo <= 120 else 0.0
	if tempo != Score.TEMPO_SET_FPS:
		return 0.0
	return float(tempo_cue) if tempo_cue > 0 else 0.0


## Hold the playhead for `ms`, whatever the reason.
##
## **The longer of the two wins when something is already holding**, so a
## transition on a frame that also carries a tempo delay cannot cut the delay
## short. That is the reference's arithmetic for every hold but one: `the delay`
## and the tempo delay are two independent gates on the same step
## (`_nextFrameDelay` beside `_nextFrameTime`, both tested, both must have
## passed), which is a maximum written as two clocks.
##
## **A transition is the exception, and it adds.** Director plays it inside the
## render, synchronously, and only computes the next frame's due time when it has
## finished — so the wipe's time is spent *before* the delay is armed and the two
## are consecutive rather than overlapping. Written here rather than at the call
## site so that `preview/frame_loop.gd` keeps handing every hold to one function;
## the reason string is the whole of the distinction and it is already a named
## constant precisely so this cannot be a typo.
func hold(ms: float, reason: String) -> void:
	if ms <= 0.0:
		return
	if reason == REASON_TRANSITION:
		_transition_ms = maxf(_transition_ms, ms)
		_hold_ms += ms
		if _hold_reason == "":
			_hold_reason = reason
		return
	if ms > _hold_ms:
		_hold_ms = ms
		_hold_reason = reason


## A click satisfies a wait-for-click and nothing else. A timed hold is not
## clickable-through: §9.2 gives the alternating cursor and the mouse-down
## release to the wait-for-click case alone.
func clicked() -> void:
	_waiting_click = false


## A queued `go to` cancels the waits that are *waiting for something*, and does
## not shorten the clock.
##
## `Score::isWaitingForNextFrame` computes `goingTo` once and consults it in three
## of its four arms (`score.cpp:400-441`): the sound-channel wait, the
## wait-for-click and the wait-for-video all end early when a jump is pending, and
## each clears its own channel on the way out. The fourth arm is
## `millis < _nextFrameTime` — the tempo channel's frame rate and its
## `256 - tempo` seconds delay — and it does not mention `goingTo` at all. `the
## delay`'s own timer is the same (`score.cpp:681-692`): a pending jump skips the
## frozen-script processing inside the delay branch and does not end the delay.
##
## The distinction is not arbitrary. The three that yield are waiting on something
## that may never come — a sound that was never queued, a click nobody makes, a
## video with no decoder — so a jump is the escape hatch, and this port's own
## comment about "how a script escapes a frame whose sound was never going to
## arrive" is right about them. The clock is not waiting on anything: it is how
## long the frame *lasts*, and a movie that jumps out of it early plays faster
## than Director did.
##
## Reachable only from a `go` issued outside the step loop — a click, a key, an
## `idle` — because a `go` from `exitFrame` runs after the wait has expired. This
## corpus spends 74.0 s in tempo delays across thirty-six frames, so clicking
## through one is an ordinary thing for a player to do. `bugs.md` 55.
func release() -> void:
	_waiting_click = false
	_waiting_sound = 0
	_waiting_cue = 0
	_waiting_video = 0


## Every hold, the clock included. A movie change, not a jump within one: the
## frame the old movie was timing does not exist any more, so there is nothing
## left for its delay to be the length of.
func release_all() -> void:
	release()
	_hold_ms = 0.0
	_transition_ms = 0.0
	_hold_reason = ""


## Drop one timed hold by name, and leave every other reason to hold alone.
##
## A click aborting a colour cycle (§11) is the case this exists for: the cycle's
## hold is the player's to cut short and the sound wait on the same frame is not,
## and `release` — which is the *jump*'s cancel-everything — cannot tell them
## apart. Nothing happens if the named reason is not the one holding.
func release_hold(reason: String) -> void:
	if _hold_reason != reason:
		return
	_hold_ms = 0.0
	_hold_reason = ""
	if reason == REASON_TRANSITION:
		_transition_ms = 0.0


## The sound channel this frame is waiting on, and which cue point releases it.
## `{channel, cue}`, channel 0 when nothing is waiting. See `_waiting_sound` for
## why the condition is evaluated by the caller and not here.
func waiting_sound() -> Dictionary:
	return {"channel": _waiting_sound, "cue": _waiting_cue}


## The sound the frame was waiting for has finished, or its cue has passed.
func sound_arrived() -> void:
	_waiting_sound = 0
	_waiting_cue = 0


## Is the playhead waiting for a click? The cursor is the caller: §9.2 gives a
## wait-for-click frame an alternating up/down arrow, which is the only thing on
## screen saying the movie wants a click rather than having stopped.
func waiting_click() -> bool:
	return _waiting_click


## The sprite channel whose digital video is holding the playhead, 0 for none.
func waiting_video() -> int:
	return _waiting_video


## The video the frame was waiting for has finished. The counterpart to
## `sound_arrived`, for a caller that would rather push than be polled.
func video_finished() -> void:
	_waiting_video = 0


## Is the digital video this frame waits for still running?
##
## Asks `video_probe` and *releases the wait* when the answer is no, which is
## where the reference clears the same flag. With no probe installed the answer
## is always no, so a movie with no decoder behind it treats every video wait as
## a video that has already finished rather than stopping on it for ever.
func _video_holds() -> bool:
	if _waiting_video <= 0:
		return false
	if video_probe.is_valid() and bool(video_probe.call(_waiting_video)):
		return true
	_waiting_video = 0
	return false


## Is something stopping the playhead from stepping?
func playhead_held() -> bool:
	return _hold_ms > 0.0 or _waiting_click or _waiting_sound > 0 or _video_holds()


## Is a transition still playing? Asked separately from `hold_reason` because a
## frame can wait for a click *and* carry a transition, and the caller that
## defers `enterFrame` past a transition needs the transition specifically rather
## than whichever hold happens to read as the dominant one. Which is why it is
## `_transition_ms` and not the reason string: on a frame carrying both a wipe
## and a longer tempo delay the dominant reason is the delay, and answering false
## there let `enterFrame` run over a frame that was still arriving.
func holding_transition() -> bool:
	return _transition_ms > 0.0


## What a HUD should say is stopping the playhead. A click wait outranks a timed
## hold here because it is the one the player has to do something about.
func hold_reason() -> String:
	if _waiting_click:
		return "wait for click"
	if _waiting_sound > 0:
		return "wait for sound %d" % _waiting_sound
	if _waiting_video > 0:
		return "wait for video in channel %d" % _waiting_video
	if _transition_ms > 0.0:
		return REASON_TRANSITION
	return _hold_reason


## `delta` seconds of the movie's clock have passed: is a score step due?
##
## **At most one, and time the engine could not afford is dropped rather than
## owed back.** That is `Score::updateNextFrameTime` (`score.cpp:531-632`), which
## ends every arm with `_nextFrameTime = g_system->getMillis() + 1000/rate` — an
## *absolute* re-arm from the moment the step's work finished, assigned and never
## accumulated — and `Score::update` calls it exactly once per cycle, including
## the "loading the same frame" path a room holding itself with `go to the frame`
## takes (`score.cpp:443-528`, `:640-711`). `isWaitingForNextFrame` then refuses
## the next step while `millis < _nextFrameTime` (`score.cpp:433-434`), so an
## update that ran long makes *that one frame* longer and leaves no debt behind
## it. Director drops score steps it cannot afford and never repays them.
##
## This counts down to the same instant instead of comparing against a wall
## clock, because the seconds handed in here are the *movie's* and not the
## machine's: `director_preview.gd:_fast_forward_delta` scales them, and a clock
## reading `Time.get_ticks_msec()` would ignore the toggle entirely. `_due_in` is
## therefore `_nextFrameTime - getMillis()` carried as a countdown, and the line
## that matters is the assignment — `_due_in = period`, discarding the overshoot,
## where the accumulator this replaces wrote `_owed -= period` and kept it.
##
## **What the accumulator cost, measured.** It banked `delta` and drained up to
## four steps in one rendered tick. Measured on Itamar Park's arcade — the movie
## `bugs.md` 86 was filed from, `torfim.dir` frame 20 `[Ant]`, 80 fps tempo, with
## `Engine.max_fps` pinned to 60 to stand for a display
## (`tools/scratch/playrate.gd -- --root res://test-games/itamar-park --file
## torfim/torfim.dir --max-fps 60 --steps 1200 --clicks "play+10:11" --at 600
## --sample 60`), over 60 rendered ticks:
##
##   accumulator   136 score steps in 1.73 s — 78.7/s, **2.27 steps per paint**,
##                 and the paint rate itself down to 34.7 Hz because each one
##                 carried 2.27 `exitFrame`s of Lingo
##   this          58 score steps in 1.04 s — 56.0/s, **0.97 steps per paint**,
##                 at 57.7 Hz
##
## The accumulator hit the movie's stated 80 fps and the player saw a third of
## it: two of every three states were stepped and never drawn. Director cannot
## do that — one `Score::update`, one step, one render — and this now cannot
## either. `exitFrame` tracked the step count exactly in both runs, which also
## disposes of `bugs.md` 86's second suspect: nothing was re-entering the frame
## inside a step, the burst was the drain and only the drain.
##
## The cold-art case is worse still and is what the cap made invisible: at 12.5 ms
## a step, any rendered tick costing 50 ms reached the ceiling, so a 200 ms tick
## returned 4 where 16 were owed — a quarter of the tempo — and then burst as the
## art warmed. `discount` existed only to take the preloader's own milliseconds
## back out of that debt and is gone with it: there is no debt left to subtract
## from, and pushing `_due_in` forward instead would make the movie run *slower*
## than Director, which spends the same milliseconds and simply arrives late.
##
## **A tempo above the rate the host loop turns over at is not reached, and that
## is Director's answer too.** The reference takes one score step per turn of
## `DirectorEngine::run`'s loop, which ends in `delayMillis(10)`
## (`director.cpp:370-405`), so it cannot exceed about 100 steps a second whatever
## the score asks for and drops the difference. Here the loop turn is the rendered
## `_process` frame, so a movie at 80 fps on a 60 Hz display plays at 60. Raising
## the ceiling by draining a queue is precisely the accumulator, and the same
## title says why it does not matter: `torfim.dir`'s scroll is regulated against
## `the ticks`, not against the frame rate, which is how a 1990s title survived
## machines that could not hit 80 either.
##
## Returned as "a step is due" rather than a count, because a count is a promise
## this cannot keep: the caller's loop over it was where the burst was spent.
## Whether the playhead may *use* the step is a separate question — a hold does
## not stop the movie's clock, because film loops animate through a wait exactly
## as they animate through a room holding itself still — so the caller asks
## `playhead_held()` for that and counts this either way.
func tick(delta: float) -> bool:
	if delta > 0.0:
		_hold_ms = maxf(0.0, _hold_ms - delta * 1000.0)
		# The transition's own share runs down with it, and first: Director spends
		# the wipe's time inside the render and only then arms the delay, so the
		# frame has finished arriving while the rest of the hold is still running.
		_transition_ms = maxf(0.0, _transition_ms - delta * 1000.0)
		if _hold_ms <= 0.0:
			_hold_reason = ""
	_due_in -= maxf(delta, 0.0)
	if _due_in > 0.0:
		return false
	# `<= 0` rather than `< 0` above, and assignment rather than `+=` here. A movie
	# whose tempo divides the tick exactly -- 60 fps against a 60 Hz process loop,
	# which is what the fast-forward toggle asks for -- leaves `_due_in` at exactly
	# zero, and a strict test would refuse every step it ever offered.
	_due_in = 1.0 / maxf(fps, 0.001)
	return true


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
		# The phase, not a debt. An old save carrying the retired `owed` key is
		# read as zero here, which means "a step is due on the first tick after
		# the restore" -- at most one step early, where honouring the debt it
		# recorded would replay up to four.
		"due_in": _due_in,
		"hold_ms": _hold_ms,
		"transition_ms": _transition_ms,
		"hold_reason": _hold_reason,
		"waiting_click": _waiting_click,
		"waiting_sound": _waiting_sound,
		"waiting_cue": _waiting_cue,
		"waiting_video": _waiting_video,
		# The puppet tempo and the two carries it is measured against. A save made
		# on a frame a script had set the tempo on comes back at the score's rate
		# without them, and comes back with the puppet already cancelled -- which
		# is a different movie from the one that was saved in exactly the way this
		# function's header warns about.
		"puppet_tempo": _puppet_tempo,
		"last_tempo": _last_tempo,
		"cached_tempo": _cached_tempo,
	}


func restore_state(from: Dictionary) -> void:
	if from.is_empty():
		return
	fps = float(from.get("fps", fps))
	_due_in = float(from.get("due_in", 0.0))
	_hold_ms = float(from.get("hold_ms", 0.0))
	_transition_ms = float(from.get("transition_ms", 0.0))
	_hold_reason = str(from.get("hold_reason", ""))
	_waiting_click = bool(from.get("waiting_click", false))
	_waiting_sound = int(from.get("waiting_sound", 0))
	_waiting_cue = int(from.get("waiting_cue", 0))
	_waiting_video = int(from.get("waiting_video", 0))
	_puppet_tempo = int(from.get("puppet_tempo", 0))
	_last_tempo = int(from.get("last_tempo", 0))
	_cached_tempo = int(from.get("cached_tempo", 0))


## One line for a HUD: the rate, and what is stopping the playhead if anything.
func status() -> String:
	if not playhead_held():
		return "%.0f fps" % fps
	if _waiting_click:
		return "%.0f fps, waiting for a click" % fps
	if _waiting_sound > 0:
		return "%.0f fps, waiting for sound %d" % [fps, _waiting_sound]
	if _waiting_video > 0:
		return "%.0f fps, waiting for video in channel %d" % [fps, _waiting_video]
	return "%.0f fps, holding %d ms (%s)" % [fps, int(ceilf(_hold_ms)), hold_reason()]
