extends RefCounted
## Decode a frame's artwork *before* the frame is played.
##
## Title-agnostic. It knows about frames, sprites and a decode callback, and
## nothing about what is in them.
##
## Why this exists, measured: decoding a cast member costs real milliseconds, and
## the preview decoded on first appearance -- inside the step that wanted to draw
## it. `strtgame` frame 38 spends **145.7 ms** in one step that way and DAY1 frame
## 39 spends **105.5 ms**, against a step budget of 66 ms at 15 fps and 125 ms at
## 8. So the movie stalls for one frame and then, because the clock is owed that
## time, replays up to `MAX_CATCHUP_STEPS` in a single paint. Stall, then burst.
## From the player's chair that is a jump, and it lands exactly where new art
## appears: the first frame of a menu's background loop, or a full-screen bitmap
## fading in.
##
## Director did not have this problem because it preloads. The score carries
## per-frame preload settings and `preLoad`/`preLoadMember` exist precisely so a
## movie can pay for its artwork before it needs it. This is that, without the
## authored hints: walk ahead of the playhead and decode what is coming.
##
## The burst half of that measurement is gone independently of this file:
## `FrameClock.tick` re-arms absolutely now and drops the time it could not
## afford, as `Score::updateNextFrameTime` does, so a 145 ms step costs one long
## frame and no longer buys a four-step replay on the frame after it. The stall
## is still real and still this file's subject -- a dropped frame where new art
## appears is exactly as visible as it ever was.
##
## Two properties matter more than the lookahead distance:
##
## **It is time-boxed.** Preloading that itself overruns a step has moved the
## stall rather than removed it, so each pass spends at most `budget_ms` and
## resumes where it stopped. A frame with forty new members is paid for over
## several steps instead of one.
##
## **It is idempotent and cheap when warm.** The decode callback is expected to
## cache, so re-offering a member costs a dictionary lookup. That makes it safe
## to re-walk the same lookahead window every step without tracking what has
## already been done.

## How many frames ahead to look. Far enough to cover a marker jump landing on
## fresh art, short enough that a movie which never gets there has not paid for
## it. Frames are cheap to enumerate; only undecoded members cost anything.
const LOOKAHEAD := 24

## Milliseconds a single pass may spend. One quarter of a 15 fps step, so a pass
## that runs long still leaves the frame its own budget.
const BUDGET_MS := 4.0

var _score = null
## The next frame to consider, so a budgeted pass resumes rather than restarting
## and re-walking the frames it already paid for.
var _cursor := 0


func _init(score) -> void:
	_score = score


## Called when the playhead moves, so the window follows it rather than crawling
## forward from wherever it stopped. Only ever moves the cursor forward within
## the window: a `go` backwards into already-decoded art needs no work.
func seek(frame: int) -> void:
	if frame > _cursor or frame + LOOKAHEAD < _cursor:
		_cursor = frame


## Decode what the next few frames will need. `decode` is called once per sprite
## record and is expected to cache; `effective` may rewrite a record the way the
## renderer would, or be null to take the score's own.
func run(from_frame: int, decode: Callable, effective: Callable = Callable()) -> int:
	if _score == null:
		return 0
	seek(from_frame)
	var deadline := Time.get_ticks_usec() + int(BUDGET_MS * 1000.0)
	var limit: int = mini(from_frame + LOOKAHEAD, _score.frame_count)
	var decoded := 0
	while _cursor < limit:
		var frame: Dictionary = _score.frame(_cursor)
		for raw in frame.get("sprites", []):
			var sprite: Dictionary = raw
			if effective.is_valid():
				sprite = effective.call(raw)
				if sprite.is_empty():
					continue
			decode.call(sprite)
			decoded += 1
			# Checked per sprite, not per frame: one frame can hold more new
			# artwork than the whole budget, and a per-frame test would let it
			# through whole and reintroduce the stall this exists to remove.
			if Time.get_ticks_usec() >= deadline:
				return decoded
		_cursor += 1
	return decoded
