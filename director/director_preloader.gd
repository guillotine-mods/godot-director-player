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

## Drawn area, in pixels, past which a member is warmed at movie load instead of
## being left to the lookahead.
##
## **Derived from the measured decode rate, not chosen.** `_blit_8` is a GDScript
## loop over the pixels, and `piposh-dream/fritz2.dir` frame 254 decodes
## 2,150,000 of them in 417 ms -- about 5.2 megapixels a second. A 15 fps step is
## 66 ms and this file's own ceiling is 60, so a step can afford roughly 310,000
## pixels. Anything near that is what `LOOKAHEAD` is for. What it cannot help
## with is a member several times the stage, because those are reached by a
## **marker jump** -- `go("stage1")` -- and no linear window ahead of the playhead
## covers a jump to an arbitrary label.
##
## Two stage-fulls is the line: it clears an ordinary 640x480 backdrop, which the
## lookahead does hide, and catches the panoramas it cannot. `fritz2.dir`'s are
## 3000x480 and 2196x323.
const WARM_ABOVE_PIXELS := 640 * 480 * 2

## Milliseconds `warm_large` may spend. Far above `BUDGET_MS` on purpose: this
## runs once, when a movie is loading and a pause is already expected, and the
## whole point is to move a stall out of gameplay and into a moment the player
## reads as loading.
const WARM_BUDGET_MS := 500.0

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


## Decode the movie's oversized artwork now, before anything plays it.
##
## **The lookahead cannot cover a marker jump, and that is where this bites.**
## `run` walks `LOOKAHEAD` frames ahead of the playhead, which hides art the movie
## is about to scroll into. `piposh-dream/fritz2.dir` reaches its stages with
## `go("stage1")`, `go("stage2")`, `go("endstage1")` -- 54 markers -- so the frame
## that needs a 3000x480 panorama is entered from a frame 200 away and no window
## ahead of the playhead ever saw it. The owner reported it as "the screen flickers
## for a second when moving between stages"; `tools/decode_stall.gd` measures it as
## one step of **417 ms** against a 60 ms ceiling, with every other step in the
## movie under 27 ms.
##
## Walks the whole score once, offers only records past `WARM_ABOVE_PIXELS`, and
## dedupes on what the renderer's own cache is keyed by -- library, member and
## drawn size -- so the same panorama on two hundred frames is decoded once and
## the pass is cheap even when the budget is not reached.
##
## Time-boxed like `run`, for the same reason, and the box is checked per record:
## a single member can exceed the whole budget and there is nothing to be done
## about that one, but the next one should not follow it.
##
## Returns how many records it decoded, so a caller can say so.
func warm_large(decode: Callable, effective: Callable = Callable(),
		above_pixels: int = WARM_ABOVE_PIXELS,
		budget_ms: float = WARM_BUDGET_MS) -> int:
	if _score == null:
		return 0
	var deadline := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	var seen := {}
	var decoded := 0
	for index in int(_score.frame_count):
		var frame: Dictionary = _score.frame(index)
		for raw in frame.get("sprites", []):
			var sprite: Dictionary = raw
			if effective.is_valid():
				sprite = effective.call(raw)
				if sprite.is_empty():
					continue
			var area := int(sprite.get("width", 0)) * int(sprite.get("height", 0))
			if area < above_pixels:
				continue
			var key := "%d:%d:%dx%d" % [
				int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0)),
				int(sprite.get("width", 0)), int(sprite.get("height", 0))]
			if seen.has(key):
				continue
			seen[key] = true
			decode.call(sprite)
			decoded += 1
			if Time.get_ticks_usec() >= deadline:
				return decoded
	return decoded
