extends RefCounted
## Frame transitions: where the parameters come from, how long one lasts, and
## what it draws while it lasts.
##
## `docs/DIRECTOR_ENGINE.md` §10. Director resolves a transition from three
## sources, in priority order:
##
##   1. a **puppet transition** set from Lingo — one-shot, consumed by the next
##      frame change;
##   2. the frame's own transition, which in a D5 score is a reference to a
##      **transition cast member** in the main channel (`transition_lib` /
##      `transition_member`);
##   3. nothing, and the frame cuts.
##
## **This file used to model only the time, and argued the omission from the
## corpus.** The argument is reproduced here because undoing it is the point of
## the file's current shape: it counted three transition members and five frames
## across "all 61 containers" of one title, concluded that "thirteen transition
## algorithms would be thirteen pieces of dead code for this title, and four
## seconds of held playhead is the whole of what is missing", and stopped at the
## hold. `AGENTS.md` rejects that reasoning by name — "a feature is implemented
## because Director has it, not because this corpus exercises it", and *the
## transition wipe algorithms* are one of the four calls it lists as already made
## the wrong way. **The census was also wrong on its own terms**, which is worth
## more than the argument about it: it measured one root of the six now shipped,
## and re-running `tools/transition_survey.gd --root <r> --all` gives
##
##   rating         52 frames   94.5 s   types 24, 25, 26, 28, 32, 33, 51, 52
##   piposh-dream   35 frames   21.5 s   types 4, 26, 27, 32, 33, 51, 52
##   piposh         17 frames    8.9 s   types 5, 51, 52
##   piposh-en       8 frames    5.8 s   types 5, 51, 52
##   piposh-ru       8 frames    5.8 s   types 5, 51, 52
##   piposh2         5 frames    4.0 s   types 11, 52
##   -----------------------------------------------------------------------
##   all six       125 frames  140.5 s   12 types, every record `changed area`
##
## **The argument for not building this was wrong by 25x on frames and 35x on
## seconds, and it was wrong in a specific way worth naming.** It claimed 2 types
## over 5 frames totalling 4.0 s, and called that "the whole of what is missing".
## The corpus is 12 types over 125 frames and 140.5 s. That is not a close call
## decided the wrong way -- it is a measurement taken on *one title* and written
## down as if it were a statement about *the engine*, which is the exact
## substitution `AGENTS.md` forbids.
##
## The single largest contributor is the one root the census never opened:
## `rating` is 52 of the 125 frames and 94.5 s of the 140.5 -- more than the other
## five roots put together -- it is the sole source of types 24, 25 and 28, and its
## `EGOZROO1.dir` cycles patterns, random columns, boxy squares, dissolve pixels
## and boxy rectangles through one room at 2000 ms each. 44 of its 52 frames run
## for 2000 ms, which is why its share of the seconds is larger than its share of
## the frames.
##
## Thinnest row in the table: type **27 (random rows) is `piposh-dream`'s alone**,
## two frames. `test-games/itamar-park` was swept and holds 0 type-14 members;
## `itamar-magichat` is the only corpus not swept and `tools/member_type_census.gd`
## puts one type-14 member in it.
##
## So all 52 numbered types are implemented here, over the thirteen algorithms
## the reference groups them into, together with the chunk size and change area
## that govern them. What the table above decides is which of them have been seen
## against a real frame -- the other forty-three are marked `UNVERIFIED` at their
## algorithm, which `AGENTS.md` is explicit is an honest state and not the same as
## absent.
##
## ## Where the rules came from
##
## `reference/scummvm/transitions.cpp` — `Window::playTransition` for the step
## loop and the rect arithmetic of every type, `Window::initTransParams` for the
## step count and step size, `Window::dissolveTrans` /
## `Window::dissolvePatternsTrans` / `Window::transMultiPass` / `Window::transZoom`
## for the four algorithms that do not go through the common loop.
## `reference/scummvm/score.cpp:Score::renderTransition` for the resolution order.
## `reference/scummvm/castmember/transition.cpp` for the member's 6-byte block.
## Every rule below cites the function it came from; the code is this port's own.
##
## ## What this file does *not* decide
##
## It does not paint. `Play` composes two stage-sized `Image`s — the frame that
## was on screen and the frame that is arriving — into a third, and hands that
## back; `scenes/preview/stage_paint.gd` draws it and `scenes/preview/frame_loop.gd`
## steps it against the hold that `director/director_frame_clock.gd` is already
## running. Keeping the algorithms on `Image`s rather than on the canvas is what
## makes them testable at all: `tools/transition_render.gd` runs them headless
## against synthetic frames, where nothing in this project can capture a real one
## (`preview/snapshot.gd:grab` — headless Godot never paints).

## The published Director transition numbering. `transitions.cpp:transProps`.
const TYPE_NAMES := {
	0: "none",
	1: "wipe right", 2: "wipe left", 3: "wipe down", 4: "wipe up",
	5: "centre out horizontal", 6: "edges in horizontal",
	7: "centre out vertical", 8: "edges in vertical",
	9: "centre out square", 10: "edges in square",
	11: "push left", 12: "push right", 13: "push down", 14: "push up",
	15: "reveal up", 16: "reveal up right", 17: "reveal right",
	18: "reveal down right", 19: "reveal down", 20: "reveal down left",
	21: "reveal left", 22: "reveal up left",
	23: "dissolve pixels fast", 24: "dissolve boxy rectangles",
	25: "dissolve boxy squares", 26: "dissolve patterns",
	27: "random rows", 28: "random columns",
	29: "cover down", 30: "cover down left", 31: "cover down right",
	32: "cover left", 33: "cover right", 34: "cover up",
	35: "cover up left", 36: "cover up right",
	37: "venetian blinds", 38: "checkerboard",
	39: "strips bottom build left", 40: "strips bottom build right",
	41: "strips left build down", 42: "strips left build up",
	43: "strips right build down", 44: "strips right build up",
	45: "strips top build left", 46: "strips top build right",
	47: "zoom open", 48: "zoom close", 49: "vertical blinds",
	50: "dissolve bits fast", 51: "dissolve pixels", 52: "dissolve bits",
}

## The thirteen algorithms (`transitions.cpp:TransitionAlgo`). A type's algorithm
## decides which loop runs it and, for the common loop, whether the pixels being
## slid around come from the frame that is arriving or the frame that is leaving.
enum {
	ALGO_BLINDS, ALGO_BOXY, ALGO_STRIPS, ALGO_CENTER_OUT, ALGO_CHECKER,
	ALGO_COVER, ALGO_DISSOLVE, ALGO_EDGES_IN, ALGO_PUSH, ALGO_RANDOM_LINES,
	ALGO_REVEAL, ALGO_WIPE, ALGO_ZOOM,
}

## The direction vocabulary (`transitions.cpp:TransitionDirection`). It is not
## "which way does it go" — the type already says that — but *which dimension the
## step count is derived from*, which is why `initTransParams` switches on it and
## the step loop does not.
enum {
	DIR_NONE, DIR_HORIZONTAL, DIR_VERTICAL, DIR_BOTH, DIR_STEPS_H, DIR_STEPS_V,
	DIR_CHECKERS, DIR_BLINDS_V, DIR_BLINDS_H, DIR_DISSOLVE,
}

## type -> [algorithm, direction]. `transitions.cpp:transProps`, transcribed.
## Index 0 is `kTransNone`, which the loop treats as an immediate stop.
const TYPE_PROPS := {
	0: [ALGO_WIPE, DIR_NONE],
	1: [ALGO_WIPE, DIR_HORIZONTAL], 2: [ALGO_WIPE, DIR_HORIZONTAL],
	3: [ALGO_WIPE, DIR_VERTICAL], 4: [ALGO_WIPE, DIR_VERTICAL],
	5: [ALGO_CENTER_OUT, DIR_HORIZONTAL], 6: [ALGO_EDGES_IN, DIR_HORIZONTAL],
	7: [ALGO_CENTER_OUT, DIR_VERTICAL], 8: [ALGO_EDGES_IN, DIR_VERTICAL],
	9: [ALGO_CENTER_OUT, DIR_BOTH], 10: [ALGO_EDGES_IN, DIR_BOTH],
	11: [ALGO_PUSH, DIR_HORIZONTAL], 12: [ALGO_PUSH, DIR_HORIZONTAL],
	13: [ALGO_PUSH, DIR_VERTICAL], 14: [ALGO_PUSH, DIR_VERTICAL],
	15: [ALGO_REVEAL, DIR_VERTICAL], 16: [ALGO_REVEAL, DIR_BOTH],
	17: [ALGO_REVEAL, DIR_HORIZONTAL], 18: [ALGO_REVEAL, DIR_BOTH],
	19: [ALGO_REVEAL, DIR_VERTICAL], 20: [ALGO_REVEAL, DIR_BOTH],
	21: [ALGO_REVEAL, DIR_HORIZONTAL], 22: [ALGO_REVEAL, DIR_BOTH],
	23: [ALGO_DISSOLVE, DIR_DISSOLVE], 24: [ALGO_DISSOLVE, DIR_DISSOLVE],
	25: [ALGO_DISSOLVE, DIR_DISSOLVE], 26: [ALGO_DISSOLVE, DIR_DISSOLVE],
	27: [ALGO_DISSOLVE, DIR_DISSOLVE], 28: [ALGO_DISSOLVE, DIR_DISSOLVE],
	29: [ALGO_COVER, DIR_VERTICAL], 30: [ALGO_COVER, DIR_BOTH],
	31: [ALGO_COVER, DIR_BOTH], 32: [ALGO_COVER, DIR_HORIZONTAL],
	33: [ALGO_COVER, DIR_HORIZONTAL], 34: [ALGO_COVER, DIR_VERTICAL],
	35: [ALGO_COVER, DIR_BOTH], 36: [ALGO_COVER, DIR_BOTH],
	37: [ALGO_BLINDS, DIR_BLINDS_H], 38: [ALGO_CHECKER, DIR_CHECKERS],
	39: [ALGO_STRIPS, DIR_STEPS_V], 40: [ALGO_STRIPS, DIR_STEPS_V],
	41: [ALGO_STRIPS, DIR_STEPS_H], 42: [ALGO_STRIPS, DIR_STEPS_H],
	43: [ALGO_STRIPS, DIR_STEPS_H], 44: [ALGO_STRIPS, DIR_STEPS_H],
	45: [ALGO_STRIPS, DIR_STEPS_V], 46: [ALGO_STRIPS, DIR_STEPS_V],
	47: [ALGO_ZOOM, DIR_BOTH], 48: [ALGO_ZOOM, DIR_BOTH],
	49: [ALGO_BLINDS, DIR_BLINDS_V],
	50: [ALGO_DISSOLVE, DIR_DISSOLVE], 51: [ALGO_DISSOLVE, DIR_DISSOLVE],
	52: [ALGO_DISSOLVE, DIR_DISSOLVE],
}

## Director steps a transition once per 1/60 s tick and caps the step count at
## `duration × 60 / 1000` (§10, `transitions.cpp:MAX_STEPS`). The cap is what
## makes the duration the real quantity: a transition never runs longer than it
## asks for, however coarse its chunk size.
const TICKS_PER_SECOND := 60.0

## Sub-pixel step arithmetic. `transitions.cpp:TSTEP_FRAC`: the per-step distance
## is kept in 1/1024ths of a pixel so that a wipe over 300 steps of a 640-pixel
## stage does not quantise to a 2-pixel step and finish two thirds of the way
## across. Every `x_step`/`y_step` in the common loop is in these units; the
## dissolve and multipass loops override them with plain pixels, which is why
## each says so where it does it.
const TSTEP_FRAC := 1024

## `transitions.cpp:kNumStrips` / `kNumChecks` / `kNumBlinds`. Director's strip
## and blind counts are fixed regardless of stage size; the chunk size moves the
## *speed* the strips build at, not how many there are.
const NUM_STRIPS := 16
const NUM_BLINDS := 12

## The shortest transition Director will play. `transitions.cpp:playTransition`
## clamps `duration` up to 250 ms ("When duration is < 1/4s, make it 1/4") before
## anything else reads it, so this is part of how long the playhead is held and
## not only of how the drawing is paced. Nothing in eight corpora asks for less
## than 350 ms, so the clamp is unexercised here and is implemented because the
## reference has it.
const MIN_DURATION_MS := 250.0

## A transition member's own record is 6 bytes and carries no cast info, so a
## duration this large is a misparse rather than a slow wipe. Director stores
## the duration as an unsigned 16-bit millisecond count, so anything is
## representable up to ~65 s; nothing in the corpus exceeds 1000 ms, and a hold
## of a minute is indistinguishable on screen from the movie having hung.
const MAX_DURATION_MS := 30000.0

## The dissolve's linear-feedback shift register taps, indexed by the total bit
## width of the cell grid. `transitions.cpp:randomSeed`. This is the table that
## makes a Director dissolve reproducible rather than merely random: the sequence
## visits every cell of a 2^n grid exactly once, which is why the last step lands
## on a complete frame with no cell missed and no cell drawn twice.
const RANDOM_SEED := [
	0x00000000,
	0x00000000, 0x00000003, 0x00000006, 0x0000000c,
	0x00000014, 0x00000030, 0x00000060, 0x000000b8,
	0x00000110, 0x00000240, 0x00000500, 0x00000ca0,
	0x00001b00, 0x00003500, 0x00006000, 0x0000b400,
	0x00012000, 0x00020400, 0x00072000, 0x00090000,
	0x00140000, 0x00300000, 0x00420000, 0x00d80000,
	0x01200000, 0x03880000, 0x07200000, 0x09000000,
	0x14000000, 0x32800000, 0x48000000, 0xa3000000,
]

## The 64 ordered-dither patterns of `kTransDissolvePatterns`.
## `transitions.cpp:dissolvePatterns`. Each row is one 8x8 tile as eight bytes;
## the tiles are **nested** — pattern n's bits are a superset of pattern n-1's —
## which is what `_step_patterns` relies on to copy each pixel exactly once
## rather than re-scanning the whole clip on every step.
const DISSOLVE_PATTERNS := [
	[0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x80, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00],
	[0x88, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00],
	[0x88, 0x00, 0x00, 0x00, 0x88, 0x00, 0x00, 0x00],
	[0x88, 0x00, 0x20, 0x00, 0x88, 0x00, 0x00, 0x00],
	[0x88, 0x00, 0x20, 0x00, 0x88, 0x00, 0x02, 0x00],
	[0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x02, 0x00],
	[0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00],
	[0xa8, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00],
	[0xa8, 0x00, 0x22, 0x00, 0x8a, 0x00, 0x22, 0x00],
	[0xaa, 0x00, 0x22, 0x00, 0x8a, 0x00, 0x22, 0x00],
	[0xaa, 0x00, 0x22, 0x00, 0xaa, 0x00, 0x22, 0x00],
	[0xaa, 0x00, 0xa2, 0x00, 0xaa, 0x00, 0x22, 0x00],
	[0xaa, 0x00, 0xa2, 0x00, 0xaa, 0x00, 0x2a, 0x00],
	[0xaa, 0x00, 0xaa, 0x00, 0xaa, 0x00, 0x2a, 0x00],
	[0xaa, 0x00, 0xaa, 0x00, 0xaa, 0x00, 0xaa, 0x00],
	[0xaa, 0x40, 0xaa, 0x00, 0xaa, 0x00, 0xaa, 0x00],
	[0xaa, 0x40, 0xaa, 0x00, 0xaa, 0x04, 0xaa, 0x00],
	[0xaa, 0x44, 0xaa, 0x00, 0xaa, 0x04, 0xaa, 0x00],
	[0xaa, 0x44, 0xaa, 0x00, 0xaa, 0x44, 0xaa, 0x00],
	[0xaa, 0x44, 0xaa, 0x10, 0xaa, 0x44, 0xaa, 0x00],
	[0xaa, 0x44, 0xaa, 0x10, 0xaa, 0x44, 0xaa, 0x01],
	[0xaa, 0x44, 0xaa, 0x11, 0xaa, 0x44, 0xaa, 0x01],
	[0xaa, 0x44, 0xaa, 0x11, 0xaa, 0x44, 0xaa, 0x11],
	[0xaa, 0x54, 0xaa, 0x11, 0xaa, 0x44, 0xaa, 0x11],
	[0xaa, 0x54, 0xaa, 0x11, 0xaa, 0x45, 0xaa, 0x11],
	[0xaa, 0x55, 0xaa, 0x11, 0xaa, 0x45, 0xaa, 0x11],
	[0xaa, 0x55, 0xaa, 0x11, 0xaa, 0x55, 0xaa, 0x11],
	[0xaa, 0x55, 0xaa, 0x51, 0xaa, 0x55, 0xaa, 0x11],
	[0xaa, 0x55, 0xaa, 0x51, 0xaa, 0x55, 0xaa, 0x15],
	[0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x15],
	[0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55],
	[0xea, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55],
	[0xea, 0x55, 0xaa, 0x55, 0xae, 0x55, 0xaa, 0x55],
	[0xee, 0x55, 0xaa, 0x55, 0xae, 0x55, 0xaa, 0x55],
	[0xee, 0x55, 0xaa, 0x55, 0xee, 0x55, 0xaa, 0x55],
	[0xee, 0x55, 0xba, 0x55, 0xee, 0x55, 0xaa, 0x55],
	[0xee, 0x55, 0xba, 0x55, 0xee, 0x55, 0xab, 0x55],
	[0xee, 0x55, 0xbb, 0x55, 0xee, 0x55, 0xab, 0x55],
	[0xee, 0x55, 0xbb, 0x55, 0xee, 0x55, 0xbb, 0x55],
	[0xfe, 0x55, 0xbb, 0x55, 0xee, 0x55, 0xbb, 0x55],
	[0xfe, 0x55, 0xbb, 0x55, 0xef, 0x55, 0xbb, 0x55],
	[0xff, 0x55, 0xbb, 0x55, 0xef, 0x55, 0xbb, 0x55],
	[0xff, 0x55, 0xbb, 0x55, 0xff, 0x55, 0xbb, 0x55],
	[0xff, 0x55, 0xfb, 0x55, 0xff, 0x55, 0xbb, 0x55],
	[0xff, 0x55, 0xfb, 0x55, 0xff, 0x55, 0xbf, 0x55],
	[0xff, 0x55, 0xff, 0x55, 0xff, 0x55, 0xbf, 0x55],
	[0xff, 0x55, 0xff, 0x55, 0xff, 0x55, 0xff, 0x55],
	[0xff, 0xd5, 0xff, 0x55, 0xff, 0x55, 0xff, 0x55],
	[0xff, 0xd5, 0xff, 0x55, 0xff, 0x5d, 0xff, 0x55],
	[0xff, 0xdd, 0xff, 0x55, 0xff, 0x5d, 0xff, 0x55],
	[0xff, 0xdd, 0xff, 0x55, 0xff, 0xdd, 0xff, 0x55],
	[0xff, 0xdd, 0xff, 0x75, 0xff, 0xdd, 0xff, 0x55],
	[0xff, 0xdd, 0xff, 0x75, 0xff, 0xdd, 0xff, 0x57],
	[0xff, 0xdd, 0xff, 0x77, 0xff, 0xdd, 0xff, 0x57],
	[0xff, 0xdd, 0xff, 0x77, 0xff, 0xdd, 0xff, 0x77],
	[0xff, 0xfd, 0xff, 0x77, 0xff, 0xdd, 0xff, 0x77],
	[0xff, 0xfd, 0xff, 0x77, 0xff, 0xdf, 0xff, 0x77],
	[0xff, 0xff, 0xff, 0x77, 0xff, 0xdf, 0xff, 0x77],
	[0xff, 0xff, 0xff, 0x77, 0xff, 0xff, 0xff, 0x77],
	[0xff, 0xff, 0xff, 0xf7, 0xff, 0xff, 0xff, 0x77],
	[0xff, 0xff, 0xff, 0xf7, 0xff, 0xff, 0xff, 0x7f],
	[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f],
	[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
]


## The 6-byte specific block of a type-14 cast member.
##
## **The two bytes this used to carry through unread are settled now, from
## `castmember/transition.cpp:TransitionCastMember`, and the old guess about them
## was wrong in both halves.** The reference reads, in order: `_transTime`,
## `_chunkSize`, `_transType`, `_flags`, then a big-endian `_durationMillis` —
## and derives `_area = !(_flags & 1)`. So byte 0 is not the flag byte, byte 3 is
## the flag byte, and the change area is not a byte at all but bit 0 of it,
## inverted. The previous comment recorded honestly that a corpus holding both
## columns constant could not distinguish the two; it could not, and the
## reference can, which is the whole reason to read a reference.
##
## `_transTime` is D3's transition time in ticks, superseded by the millisecond
## duration and kept in the record; it is decoded and reported because a member
## whose `duration_ms` is 0 but whose `trans_time` is not would be a D3-authored
## member this port would otherwise call "not a transition". None exists in eight
## corpora, so that stays an observation rather than a fallback.
##
## Measured, and re-measured across all eight corpora rather than one. The three
## members of Piposh 2, which is all the previous census saw:
##
##   CHESS 199     00 08 34 02 02 58   chunk 8,  type 52, 0x0258 =  600 ms
##   ENDMOVI2 121  00 10 0b 02 02 bc   chunk 16, type 11, 0x02bc =  700 ms
##   ENDMOVI5 178  00 10 0b 02 03 e8   chunk 16, type 11, 0x03e8 = 1000 ms
##
## Byte 3 is 2 in every member of every root, so `flags & 1` is clear everywhere
## and **every transition in this corpus is a changed-area transition**, which is
## a behaviour the old reading of byte 3 as the area selector would have got
## backwards had anything consumed it.
static func decode_member(spec: PackedByteArray) -> Dictionary:
	if spec.size() < 6:
		return {}
	var duration := float((spec[4] << 8) | spec[5])
	var flags := int(spec[3])
	return {
		"trans_time": spec[0],
		"chunk_size": spec[1],
		"transition_type": spec[2],
		"flags": flags,
		"change_area": 0 if (flags & 1) != 0 else 1,
		"duration_ms": clampf(duration, 0.0, MAX_DURATION_MS),
	}


## Is this member record one this file can play a transition from?
static func is_transition(member: Dictionary) -> bool:
	return float(member.get("duration_ms", 0.0)) > 0.0


## Source 1 beats source 2 beats nothing (`score.cpp:renderTransition`). `puppet`
## is consumed by the caller once this has returned it — a puppet transition
## applies to exactly one frame change, which is why `puppetTransition` is
## written immediately before the `go` that uses it and never needs cancelling.
static func resolve(puppet: Dictionary, frame_member: Dictionary) -> Dictionary:
	if is_transition(puppet):
		return puppet
	if is_transition(frame_member):
		return frame_member
	return {}


## How long the playhead is held, in milliseconds.
##
## This is the whole of what the port used to reproduce, and it is still the part
## that must not be got wrong: the movie's own scripts are timed against the
## transition's duration, so a transition that renders instantly runs everything
## after it early and pulls speech out of step with the picture it was authored
## over. The drawing now steps *inside* this hold rather than replacing it --
## `preview/frame_loop.gd:advance_transition` -- so the two cannot drift.
##
## It used to round the duration up to a whole 1/60 s tick, on the argument that a
## transition shorter than a tick still costs one. The reference makes that
## argument differently and more strongly: `playTransition` clamps the duration
## itself to 250 ms, fifteen ticks, before computing anything. Rounding up to one
## tick is subsumed by a floor of fifteen, and no duration in eight corpora is
## inside either.
##
## Delegated to `Play` rather than written here, and the wall is GDScript's: an
## inner class can read this script's constants and cannot call its functions, so
## anything both sides need has to live on the inside. The alternative was a
## second copy of the arithmetic that decides how long a transition is, which is
## precisely the number the hold and the drawing must agree on.
static func hold_ms(transition: Dictionary) -> float:
	return Play.played_duration_ms(transition)


## The duration Director actually plays, after the two adjustments
## `playTransition` and `initTransParams` make to the number in the file. See
## `Play.played_duration_ms`.
static func played_duration_ms(transition: Dictionary) -> float:
	return Play.played_duration_ms(transition)


## The rectangle a changed-area transition plays inside. See
## `Play.changed_bounds`.
static func changed_bounds(before: Image, after: Image) -> Rect2i:
	return Play.changed_bounds(before, after)


static func describe(transition: Dictionary) -> String:
	if not is_transition(transition):
		return "none"
	var type_code := int(transition.get("transition_type", 0))
	return "%d %s, %d ms, chunk %d, %s" % [
		type_code,
		str(TYPE_NAMES.get(type_code, "unnamed")),
		int(transition.get("duration_ms", 0)),
		int(transition.get("chunk_size", 0)),
		"changed area" if int(transition.get("change_area", 0)) != 0 else "whole stage",
	]


## One transition in progress: the parameters, the compose surface, and the step
## the surface is currently at.
##
## Modelled as an object rather than a pure function of the step number because
## four of the thirteen algorithms are **cumulative** — a dissolve's shift
## register, a cover's growing band and a strip build all depend on every step
## before them, and recomputing step 40 from scratch would mean replaying 39
## steps to draw one. `advance_to` therefore only ever moves forward, and the
## caller drives it from elapsed time rather than from a frame counter.
class Play extends RefCounted:
	var type := 0
	## Milliseconds, after `played_duration_ms`'s two adjustments.
	var duration := 0.0
	var chunk_size := 1
	## True for a changed-area transition, false for the whole stage.
	var area := false
	var clip := Rect2i()
	var steps := 1
	var step_duration := 0.0
	## In `TSTEP_FRAC`ths of a pixel for the common loop, in whole pixels for the
	## dissolve and multipass loops. Each loop says which it is using.
	var x_step := 0
	var y_step := 0
	var strip_size := 0
	## The frame that was on screen, the frame that is arriving, and what the two
	## compose into at `applied`.
	var before: Image = null
	var after: Image = null
	var surface: Image = null
	var applied := 0
	## Milliseconds of the hold this play has been given, accumulated by
	## `preview/frame_loop.gd:advance_transition` from the same `delta` the frame
	## clock is running the hold down with. Held here rather than on the node so
	## that the two numbers a step is derived from -- how long it has been and how
	## long a step is -- cannot end up in two different objects.
	var elapsed_ms := 0.0
	## Set once the last step has run and `surface` is the arriving frame exactly.
	var finished := false
	## Why this play is a cut rather than a wipe, empty when it is not one. A
	## transition with no frames to compose still holds the playhead; it just has
	## nothing to draw, which is what happens headless.
	var degraded := ""

	var _algo := 0
	var _dir := 0
	## Dissolve state. `w`/`h` here are the *cell grid*, not pixels.
	var _rnd := 0
	var _seed := 0
	var _h_mask := 0
	var _v_shift := 0
	var _bit_steps := 0
	var _pix_per_step_init := 1
	var _bit_index := -1
	var _cells_w := 0
	var _cells_h := 0
	var _pattern_at := -1
	## The compose surface and the arriving frame as raw RGBA8 bytes. The dissolve
	## families touch hundreds of thousands of individual cells, and a native blit
	## per cell costs more than the whole transition is allowed; four byte writes
	## do not. Only the dissolve path uses these, and it publishes `surface` from
	## `_sd` at the end of each step.
	var _sd := PackedByteArray()
	var _ad := PackedByteArray()
	var _stride := 0

	## The duration Director actually plays, after the two adjustments
	## `playTransition` and `initTransParams` make to the number in the file.
	##
	## The 250 ms floor is `playTransition`'s; the reset *down* to 250 ms for the two
	## "fast" dissolves is `initTransParams`' `kTransDirDissolve` arm, and it is a
	## reset rather than a floor — `kTransDissolvePixelsFast` and
	## `kTransDissolveBitsFast` play at 250 ms however long the file says, which is
	## what "fast" means in the name.
	static func played_duration_ms(transition: Dictionary) -> float:
		var duration := float(transition.get("duration_ms", 0.0))
		if duration <= 0.0:
			return 0.0
		var type_code := int(transition.get("transition_type", 0))
		if type_code == 23 or type_code == 50:
			return MIN_DURATION_MS
		return maxf(MIN_DURATION_MS, minf(duration, MAX_DURATION_MS))


	## The rectangle a changed-area transition plays inside.
	##
	## `playTransition` asks the score for `getChannelDirtyRectBounds()` — the union
	## of the rectangles the sprite channels dirtied — and then rounds the width and
	## height up to even numbers because "some transitions depend upon an even
	## clipRect size" (the centre-out and edges-in families halve it). This port has
	## no dirty-rect bookkeeping to ask, and it does not need one for this: it holds
	## both composited frames, so the changed area can be *measured* rather than
	## predicted, which is strictly the better answer — a channel that was dirtied
	## and drew the same pixels is not a changed area, and the reference's union
	## would say it was.
	##
	## Row bounds come from comparing whole rows as byte ranges, which is one native
	## comparison per row; column bounds come from doing the same to a 90-degree
	## rotation, which is one native rotation of each image. The obvious per-pixel
	## scan is 307,200 GDScript iterations on a 640x480 stage and would cost more
	## than the transition it is setting up.
	static func changed_bounds(before: Image, after: Image) -> Rect2i:
		if before == null or after == null:
			return Rect2i()
		var size := before.get_size()
		if size != after.get_size() or size.x <= 0 or size.y <= 0:
			return Rect2i()
		var rows := _changed_rows(before, after)
		if rows.x < 0:
			return Rect2i()
		# The same question turned on its side. `rotate_90` is native and allocates
		# two images once per transition; the alternative is a column scan in script.
		var b90 := Image.create_from_data(size.x, size.y, false, before.get_format(),
			before.get_data())
		var a90 := Image.create_from_data(size.x, size.y, false, after.get_format(),
			after.get_data())
		b90.rotate_90(CLOCKWISE)
		a90.rotate_90(CLOCKWISE)
		# A clockwise rotation sends the pixel at `(x, y)` to `(height - 1 - y, x)`, so
		# **the new row index is the old column index** and the band comes back
		# unmapped. Stated because the mirroring the other axis obviously needs is the
		# easy thing to write here by reflex, and it would report a horizontal band
		# reflected about the centre of the stage — which looks right on anything
		# symmetrical and is wrong on everything else.
		var cols := _changed_rows(b90, a90)
		if cols.x < 0:
			return Rect2i()
		return Rect2i(cols.x, rows.x, cols.y - cols.x + 1, rows.y - rows.x + 1)


	## First and last differing row as `Vector2i(top, bottom)`, or `(-1, -1)`.
	static func _changed_rows(before: Image, after: Image) -> Vector2i:
		var size := before.get_size()
		var b := before.get_data()
		var a := after.get_data()
		var stride := b.size() / maxi(size.y, 1)
		var top := -1
		var bottom := -1
		for y in size.y:
			var at := y * stride
			if b.slice(at, at + stride) != a.slice(at, at + stride):
				if top < 0:
					top = y
				bottom = y
		return Vector2i(top, bottom)


	## `transitions.cpp:getLog2` — the number of significant bits in `n`, which is
	## one more than the usual log2 and is what the dissolve's grid arithmetic wants.
	static func _log2_bits(n: int) -> int:
		var res := 0
		while n != 0:
			res += 1
			n >>= 1
		return res


	func _init(transition: Dictionary, stage: Vector2i, from_frame: Image,
			to_frame: Image) -> void:
		type = int(transition.get("transition_type", 0))
		duration = played_duration_ms(transition)
		# `playTransition`: `chunkSize = MAX(1, transChunkSize)`. A zero chunk is a
		# division by zero in every arm of `initTransParams`.
		chunk_size = maxi(1, int(transition.get("chunk_size", 0)))
		area = int(transition.get("change_area", 0)) != 0
		before = _as_rgba(from_frame)
		after = _as_rgba(to_frame)
		if before == null or after == null or before.get_size() != after.get_size():
			degraded = "no composited frames to work from"
			steps = maxi(1, int(duration * TICKS_PER_SECOND / 1000.0))
			step_duration = duration / float(steps)
			clip = Rect2i(Vector2i.ZERO, stage)
			return
		if not TYPE_PROPS.has(type):
			# `playTransition` refuses a type outside the table and returns without
			# drawing, which is a cut. The hold is already armed by the caller.
			degraded = "type %d is outside Director's table" % type
			steps = maxi(1, int(duration * TICKS_PER_SECOND / 1000.0))
			step_duration = duration / float(steps)
			clip = Rect2i(Vector2i.ZERO, stage)
			return
		var props: Array = TYPE_PROPS[type]
		_algo = int(props[0])
		_dir = int(props[1])
		clip = _resolve_clip(stage)
		if clip.size.x <= 0 or clip.size.y <= 0:
			# `playTransition` warns and aborts on a zero-sized clip rect. Reached
			# whenever a changed-area transition is armed on a frame that changed
			# nothing, which is a real authoring case and not an error.
			degraded = "nothing changed between the two frames"
			steps = maxi(1, int(duration * TICKS_PER_SECOND / 1000.0))
			step_duration = duration / float(steps)
			return
		surface = _as_rgba(before)
		_init_params()

	## Both frames as RGBA8, which is the one format the byte arithmetic below can
	## assume. A viewport grab is RGBA8 already, so this is a no-op in the player
	## and a conversion only for a harness that built its own frames.
	static func _as_rgba(image: Image) -> Image:
		if image == null or image.is_empty():
			return null
		var copy := Image.create_from_data(image.get_width(), image.get_height(),
			false, image.get_format(), image.get_data())
		if copy.get_format() != Image.FORMAT_RGBA8:
			copy.convert(Image.FORMAT_RGBA8)
		return copy

	## Whole stage or changed rectangle (`playTransition`'s `if (t.area)`).
	func _resolve_clip(stage: Vector2i) -> Rect2i:
		var whole := Rect2i(Vector2i.ZERO, stage)
		if not area:
			return whole
		var bounds := changed_bounds(before, after)
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			return Rect2i()
		# "Some transitions depend upon an even clipRect size" — the centre-out,
		# edges-in and zoom families halve it, and an odd size leaves a one-pixel
		# column the halves never meet across.
		if bounds.size.x % 2 == 1:
			bounds.size.x += 1
		if bounds.size.y % 2 == 1:
			bounds.size.y += 1
		return bounds.intersection(whole)

	## `transitions.cpp:initTransParams`, verbatim in shape and in the order the
	## divisions happen: the step count comes from the dimension the *direction*
	## names, and the step size is then the dimension divided by the step count.
	##
	## The reason it is derived in that order rather than "one chunk per step" is
	## the cap: `MAX_STEPS` limits the count to one step per 1/60 s of the
	## duration, so a fine chunk over a short duration silently becomes a coarse
	## step, and the last step still lands exactly on the edge of the clip.
	func _init_params() -> void:
		var w := clip.size.x
		var h := clip.size.y
		var m := mini(w, h)
		if _algo == ALGO_CENTER_OUT or _algo == ALGO_EDGES_IN \
				or _algo == ALGO_ZOOM:
			w = (w + 1) >> 1
			h = (h + 1) >> 1
		var max_steps := maxi(1, int(duration) * 60 / 1000)
		match _dir:
			DIR_HORIZONTAL:
				steps = mini(maxi(w / chunk_size, 1), max_steps)
				x_step = (w * TSTEP_FRAC) / steps
			DIR_VERTICAL:
				steps = mini(maxi(h / chunk_size, 1), max_steps)
				y_step = (h * TSTEP_FRAC) / steps
			DIR_BOTH:
				steps = mini(maxi(m / chunk_size, 1), max_steps)
				x_step = (w * TSTEP_FRAC) / steps
				y_step = (h * TSTEP_FRAC) / steps
			DIR_STEPS_H:
				# Pixels, not TSTEP_FRAC: the multipass loop indexes strips.
				var min_chunk_h := (w - 1) / maxi((max_steps / 2) - 1, 1)
				x_step = maxi(chunk_size, min_chunk_h)
				y_step = (h + NUM_STRIPS - 1) / NUM_STRIPS
				strip_size = (w + NUM_STRIPS - 1) / NUM_STRIPS
				steps = ((w + x_step - 1) / x_step) * 2
			DIR_STEPS_V:
				var min_chunk_v := (h - 1) / maxi((max_steps / 2) - 1, 1)
				x_step = (w + NUM_STRIPS - 1) / NUM_STRIPS
				y_step = maxi(chunk_size, min_chunk_v)
				strip_size = (h + NUM_STRIPS - 1) / NUM_STRIPS
				steps = ((h + y_step - 1) / y_step) * 2
			DIR_CHECKERS:
				strip_size = ((w if w > h else h) + NUM_STRIPS - 1) / NUM_STRIPS
				steps = ((strip_size + chunk_size - 1) / chunk_size) * 2 + 2
				# Counts of checkers, not distances.
				x_step = (w + strip_size - 1) / maxi(strip_size, 1)
				y_step = (h + strip_size - 1) / maxi(strip_size, 1)
			DIR_BLINDS_V:
				x_step = chunk_size
				strip_size = (w + NUM_BLINDS - 1) / NUM_BLINDS
				steps = (strip_size + x_step - 1) / x_step
			DIR_BLINDS_H:
				y_step = chunk_size
				strip_size = (h + NUM_BLINDS - 1) / NUM_BLINDS
				steps = (strip_size + y_step - 1) / y_step
			DIR_DISSOLVE:
				steps = mini(int(duration) * 60 / 1000, 64)
			_:
				steps = 1
		steps = maxi(steps, 1)
		if _algo == ALGO_ZOOM:
			# `transZoom` halves the step count and doubles the step size before it
			# runs, and then loops `1 .. steps - 1`. Applied here so that the caller's
			# progress arithmetic and the loop agree about how many steps there are.
			steps = (steps >> 1) + 1
			x_step <<= 1
			y_step <<= 1
		if _algo == ALGO_DISSOLVE:
			_init_dissolve()
		step_duration = duration / float(steps)

	## `dissolveTrans`' setup: what one cell of the dissolve grid is, and the shift
	## register that visits every cell of it exactly once.
	func _init_dissolve() -> void:
		var w := clip.size.x
		var h := clip.size.y
		var real_w := w
		var real_h := h
		# Pixels from here down, not TSTEP_FRAC. `dissolveTrans` says so out loud
		# and overwrites both fields on entry.
		x_step = 1
		y_step = 1
		match type:
			50, 52:
				# `kTransDissolveBitsFast` / `kTransDissolveBits`. The reference
				# widens the cell grid and drops to a *sub-byte* mask below chunk 8,
				# because on Director's 1-, 2- and 4-bit surfaces one byte holds
				# eight, four or two pixels and the mask blends the bits of a palette
				# index. **This port composes 32-bit RGBA frames, where a byte is not
				# a pixel and there is no sub-pixel to reach**, so the three fine
				# chunks collapse onto the finest thing a truecolour surface has,
				# which is one pixel — the same grid chunk 8 gets. Named as a
				# divergence rather than hidden: it makes chunks 1, 2 and 4 of types
				# 50 and 52 look like chunk 8 instead of looking like a colour-index
				# glitch, and the corpus asks for chunk 8 (CHESS 199) and chunk 8
				# (strtgame) and nothing finer.
				if chunk_size >= 32:
					w = (w + 3) >> 2
					x_step = 4
				elif chunk_size >= 16:
					w = (w + 1) >> 1
					x_step = 2
				else:
					x_step = 1
			27:
				x_step = real_w
				y_step = chunk_size
				w = 1
				h = (h + chunk_size - 1) / chunk_size
			28:
				x_step = chunk_size
				y_step = real_h
				w = (w + chunk_size - 1) / chunk_size
				h = 1
			25:
				x_step = chunk_size
				y_step = chunk_size
				w = (w + chunk_size - 1) / chunk_size
				h = (h + chunk_size - 1) / chunk_size
			24:
				if w > h:
					x_step = maxi(w * chunk_size / maxi(h, 1), 1)
					y_step = chunk_size
				else:
					x_step = chunk_size
					y_step = maxi(h * chunk_size / maxi(w, 1), 1)
				w = (w + x_step - 1) / x_step
				h = (h + y_step - 1) / y_step
			_:
				# `kTransDissolvePixelsFast` (23) and `kTransDissolvePixels` (51): one
				# cell is one pixel, whatever the chunk size says.
				pass
		_cells_w = w
		_cells_h = h
		_stride = surface.get_width() * 4
		_sd = surface.get_data()
		_ad = after.get_data()
		# The pattern dissolve shares this setup for the byte buffers and nothing
		# else: it walks a fixed table of tiles rather than a shift register, so a
		# grid it could not seed is not a reason to turn it into a cut.
		if type == 26:
			return
		var v_bits := _log2_bits(w)
		var h_bits := _log2_bits(h)
		if h_bits <= 0 or v_bits <= 0 or h_bits + v_bits >= RANDOM_SEED.size():
			degraded = "dissolve grid %dx%d has no shift register" % [w, h]
			return
		_seed = int(RANDOM_SEED[h_bits + v_bits]) & 0xFFFFFFFF
		_rnd = _seed
		_h_mask = (1 << h_bits) - 1
		_v_shift = h_bits
		_pix_per_step_init = 1
		_bit_steps = (1 << (h_bits + v_bits)) - 1
		while _bit_steps > 64:
			_pix_per_step_init <<= 1
			_bit_steps >>= 1
		_bit_steps += 1
		_bit_index = -1

	## Everything the caller needs to know without reaching into the object.
	func status() -> String:
		if degraded != "":
			return "%d %s: cut (%s)" % [
				type, str(TYPE_NAMES.get(type, "unnamed")), degraded]
		return "%d %s, %.0f ms, chunk %d, %s, %d steps of %.1f ms, clip %dx%d at %d,%d" % [
			type, str(TYPE_NAMES.get(type, "unnamed")), duration, chunk_size,
			"changed area" if area else "whole stage", steps, step_duration,
			clip.size.x, clip.size.y, clip.position.x, clip.position.y,
		]

	## True when there is a composited surface worth drawing.
	func draws() -> bool:
		return degraded == "" and surface != null

	## Run the transition forward to `target`, which the caller derives from how
	## much of the hold has elapsed. Never runs backwards: the cumulative
	## algorithms cannot, and a caller that jitters by a frame would otherwise
	## replay a dissolve's shift register from a state it has already passed.
	func advance_to(target: int) -> void:
		if finished:
			return
		var want := clampi(target, 0, steps)
		while applied < want:
			applied += 1
			# **`applied` moves whether or not there is anything to draw.** A play
			# that degraded to a cut is still a play: the playhead is held for the
			# same duration, and the step index is the only thing a harness can read
			# to prove the loop is running against the hold rather than beside it.
			# Headless Godot never paints (`preview/snapshot.gd:grab`), so this is
			# the branch every gate run takes.
			if degraded == "":
				_step_once(applied)
			if finished:
				break
		if applied >= steps:
			finish()

	## The transition has arrived. `exitTransition` blits the whole of the next
	## frame over the compose surface, and the port then drops the play and paints
	## the frame normally — so this exists for the one paint that may land between
	## the last step and the drop.
	func finish() -> void:
		if finished:
			return
		finished = true
		if surface != null and after != null:
			surface.blit_rect(after, clip, clip.position)

	func _step_once(i: int) -> void:
		match _algo:
			ALGO_DISSOLVE:
				if type == 26:
					_step_patterns(i - 1)
				else:
					_step_dissolve(i - 1)
			ALGO_BLINDS, ALGO_CHECKER, ALGO_STRIPS:
				_step_multipass(i - 1)
			ALGO_ZOOM:
				_step_zoom(i)
			_:
				_step_rect(i)

	## `surface.blit_rect` with the guards Godot does not make: an empty or
	## inverted source rectangle, and a source that has run off the image.
	func _blit(src: Image, from: Rect2i, to: Vector2i) -> void:
		if src == null or from.size.x <= 0 or from.size.y <= 0:
			return
		var bounded := from.intersection(Rect2i(Vector2i.ZERO, src.get_size()))
		if bounded.size.x <= 0 or bounded.size.y <= 0:
			return
		surface.blit_rect(src, bounded, to + (bounded.position - from.position))

	## The common step loop of `playTransition`: nine of the thirteen algorithms
	## are one source rectangle copied to one destination rectangle per step, and
	## the type decides which pair.
	##
	## Two things the switch does not say and the loop around it does. **Reveal
	## and edges-in repaint the whole clip from the arriving frame first**, then
	## slide the *departing* frame over it — they are the only two families whose
	## moving layer is the old picture over the new. And **push, reveal and
	## edges-in blit from the departing frame** while wipe, centre-out and cover
	## blit from the arriving one, which is `playTransition`'s `blitFrom`
	## selection and is the difference between a picture that slides and a picture
	## that is uncovered.
	##
	## **Verified against real frames: 4 (wipe up), 5 (centre out horizontal), 11
	## (push left), 32 and 33 (cover left/right).** The other twenty-one cases in
	## this switch are UNVERIFIED -- implemented from `playTransition` and asserted
	## only against `tools/transition_render.gd`'s synthetic frames, which do cover
	## one member of each family and both directions of the two axes.
	func _step_rect(i: int) -> void:
		var w := clip.size.x
		var h := clip.size.y
		var rto := clip
		var rfrom := clip
		var blit_from := after
		if _algo == ALGO_EDGES_IN or _algo == ALGO_REVEAL \
				or _algo == ALGO_PUSH:
			blit_from = before
		if _algo == ALGO_REVEAL or _algo == ALGO_EDGES_IN:
			_blit(after, clip, clip.position)
		var dx := x_step * i / TSTEP_FRAC
		var dy := y_step * i / TSTEP_FRAC
		match type:
			0:
				return
			1:  # wipe right
				rto.size.x = maxi(0, dx)
				rfrom = rto
			2:  # wipe left
				rto.size.x = maxi(0, dx)
				rto.position.x += w - dx
				rfrom = rto
			3:  # wipe down
				rto.size.y = maxi(0, dy)
				rfrom = rto
			4:  # wipe up
				rto.size.y = maxi(0, dy)
				rto.position.y += h - dy
				rfrom = rto
			5:  # centre out horizontal
				rto.size.x = maxi(0, dx * 2)
				rto.position.x += w / 2 - dx
				rfrom = rto
			6:  # edges in horizontal
				rto.size.x = maxi(0, w - dx * 2)
				rto.position.x += dx
				rfrom = rto
			7:  # centre out vertical
				rto.size.y = maxi(0, dy * 2)
				rto.position.y += h / 2 - dy
				rfrom = rto
			8:  # edges in vertical
				rto.size.y = maxi(0, h - dy * 2)
				rto.position.y += dy
				rfrom = rto
			9:  # centre out square
				rto.size = Vector2i(maxi(0, dx * 2), maxi(0, dy * 2))
				rto.position += Vector2i(w / 2 - dx, h / 2 - dy)
				rfrom = rto
			10:  # edges in square
				rto.size = Vector2i(maxi(0, w - dx * 2), maxi(0, h - dy * 2))
				rto.position = clip.position + Vector2i(dx, dy)
				rfrom = rto
			11:  # push left
				rto.position.x += w - dx
				rfrom.size.x -= w - _overlap(rto).size.x
				rto = rto.intersection(clip)
				_blit(after, rfrom, rto.position)
				rfrom.position.x += dx
				rfrom.size.x = maxi(0, w - dx)
				rto.position = clip.position
			12:  # push right
				rfrom.position.x += w - dx
				rfrom.size.x = maxi(0, dx)
				_blit(after, rfrom, rto.position)
				rto.size.x = maxi(0, w - dx)
				rto.position.x += dx
				rfrom.position = clip.position
				rfrom.size.x = maxi(0, w - dx)
			13:  # push down
				rfrom.position.y += h - dy
				rfrom.size.y = maxi(0, dy)
				_blit(after, rfrom, rto.position)
				rto.size.y = maxi(0, h - dy)
				rto.position.y += dy
				rfrom.position = clip.position
				rfrom.size.y = maxi(0, h - dy)
			14:  # push up
				rto.position.y += h - dy
				rfrom.size.y -= h - _overlap(rto).size.y
				rto = rto.intersection(clip)
				_blit(after, rfrom, rto.position)
				rfrom.position.y += dy
				rfrom.size.y = maxi(0, h - dy)
				rto.position = clip.position
			15:  # reveal up
				rto.position.y -= dy
				rfrom.position.y += h - _overlap(rto).size.y
				rfrom.size.y -= h - _overlap(rto).size.y
				rto = rto.intersection(clip)
			16:  # reveal up right
				rto.position += Vector2i(dx, -dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(-1, 1))
				rto = rto.intersection(clip)
			17:  # reveal right
				rto.position.x += dx
				rfrom.size.x -= w - _overlap(rto).size.x
				rto = rto.intersection(clip)
			18:  # reveal down right
				rto.position += Vector2i(dx, dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(-1, -1))
				rto = rto.intersection(clip)
			19:  # reveal down
				rto.position.y += dy
				rfrom.size.y -= h - _overlap(rto).size.y
				rto = rto.intersection(clip)
			20:  # reveal down left
				rto.position += Vector2i(-dx, dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(1, -1))
				rto = rto.intersection(clip)
			21:  # reveal left
				rto.position.x -= dx
				rfrom.position.x += w - _overlap(rto).size.x
				rfrom.size.x -= w - _overlap(rto).size.x
				rto = rto.intersection(clip)
			22:  # reveal up left
				# `translate`, where the reference writes `moveTo(-dx, -dy)` -- an
				# absolute move, which is the same thing only while the clip starts at
				# the origin. Every transition in this corpus is a changed-area one and
				# none of their clips does, so taking that literally would teleport the
				# departing frame to the top-left of the stage on every first step.
				rto.position += Vector2i(-dx, -dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(1, 1))
				rto = rto.intersection(clip)
			29:  # cover down
				rto.size.y = h
				rto.position.y += -h + dy
				rfrom.position.y += h - _overlap(rto).size.y
				rfrom.size.y -= h - _overlap(rto).size.y
				rto = rto.intersection(clip)
			30:  # cover down left
				rto.position += Vector2i(w - dx, -h + dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(-1, 1))
				rto = rto.intersection(clip)
			31:  # cover down right
				rto.position += Vector2i(-w + dx, -h + dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(1, 1))
				rto = rto.intersection(clip)
			32:  # cover left
				rto.position.x += w - dx
				rfrom.size.x -= w - _overlap(rto).size.x
				rto = rto.intersection(clip)
			33:  # cover right
				rto.position.x += -w + dx
				rfrom.position.x += w - _overlap(rto).size.x
				rfrom.size.x -= w - _overlap(rto).size.x
				rto = rto.intersection(clip)
			34:  # cover up
				rto.position.y += h - dy
				rfrom.size.y -= h - _overlap(rto).size.y
				rto = rto.intersection(clip)
			35:  # cover up left
				rto.position += Vector2i(w - dx, h - dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(-1, -1))
				rto = rto.intersection(clip)
			36:  # cover up right
				# **The one place this disagrees with the reference on purpose.**
				# `playTransition`'s case 36 trims `rfrom.right`, which is a copy of
				# case 35's line: the destination here is the *bottom-left* corner, so
				# the source has to be the arriving frame's right-hand columns and the
				# leading edge is what moves. Derived from the destination rather than
				# copied -- dest_x = src_x - (w - dx) inverts to src_x = dest_x + w - dx,
				# which is `left +=`. With the reference's line the incoming picture
				# shows its left edge twice and never its right. UNVERIFIED either way:
				# no container in eight corpora plays 36.
				rto.position += Vector2i(-w + dx, h - dy)
				rfrom = _reveal_from(rfrom, rto, Vector2i(1, -1))
				rto = rto.intersection(clip)
			_:
				return
		_blit(blit_from, rfrom, rto.position)

	## How much of the clip a displaced destination rectangle still covers.
	## `Common::Rect::findIntersectingRect`, which the arithmetic above uses to
	## turn "how far has it moved" into "how much of the source is still on
	## screen" without a second subtraction per direction.
	func _overlap(rto: Rect2i) -> Rect2i:
		return rto.intersection(clip)

	## The two-axis form of the trim the single-direction cases do inline. `sign`
	## says which edge each axis is trimmed from: +1 trims the leading edge (the
	## source scrolls in from the left/top), -1 the trailing edge.
	func _reveal_from(rfrom: Rect2i, rto: Rect2i, sign: Vector2i) -> Rect2i:
		var over := _overlap(rto)
		var lost := Vector2i(clip.size.x - over.size.x, clip.size.y - over.size.y)
		var out := rfrom
		if sign.x > 0:
			out.position.x += lost.x
			out.size.x -= lost.x
		else:
			out.size.x -= lost.x
		if sign.y > 0:
			out.position.y += lost.y
			out.size.y -= lost.y
		else:
			out.size.y -= lost.y
		return out

	## `dissolveTrans`' step: walk the shift register forward to the cell index
	## this step is entitled to, copying one cell of the arriving frame per visit.
	##
	## The register is what makes it a *Director* dissolve rather than a random
	## one — it enumerates a permutation of the grid, so no cell is drawn twice
	## and the last step completes the picture exactly. `pixPerStep` is the
	## reference's answer to a grid with more cells than the 64-step budget: it
	## draws that many cells per tick of the index rather than lengthening the
	## transition.
	##
	## **Verified against real frames: 24 (boxy rectangles), 25 (boxy squares), 27
	## (random rows), 28 (random columns), 51 (dissolve pixels) and 52 (dissolve
	## bits)** -- six of the eight, and `rating`'s `EGOZROO1.dir` alone plays four
	## of them through a single room. Only 23 and 50 are UNVERIFIED, and they are
	## the two "fast" variants, which differ from 51 and 52 in nothing but the
	## duration reset `played_duration_ms` applies.
	func _step_dissolve(i: int) -> void:
		if _seed == 0:
			return
		var real_w := clip.size.x
		var real_h := clip.size.y
		var bit_end := (_bit_steps - 1) * (i + 1) / steps
		var cell_w := maxi(1, x_step)
		var cell_h := maxi(1, y_step)
		var one_pixel := cell_w == 1 and cell_h == 1
		while _bit_index < bit_end:
			_bit_index += 1
			var per_step := _pix_per_step_init
			while true:
				var x := (_rnd - 1) >> _v_shift
				var y := (_rnd - 1) & _h_mask
				if x < _cells_w and y < _cells_h:
					var px := x * cell_w
					var py := y * cell_h
					if px < real_w and py < real_h:
						if one_pixel:
							# The corpus's own case, and the hot one: `dissolve pixels`
							# at chunk 1 and `dissolve bits` at chunk 8 both come out
							# as a 1x1 cell, and a 640x480 stage is half a million
							# visits to this line. Inlined rather than routed through
							# `_copy_cell`'s two nested loops for a single pixel.
							var o := (clip.position.y + py) * _stride 								+ (clip.position.x + px) * 4
							_sd[o] = _ad[o]
							_sd[o + 1] = _ad[o + 1]
							_sd[o + 2] = _ad[o + 2]
							_sd[o + 3] = _ad[o + 3]
						else:
							_copy_cell(clip.position.x + px, clip.position.y + py,
								mini(cell_w, real_w - px), mini(cell_h, real_h - py))
				_rnd = ((_rnd >> 1) ^ _seed) if (_rnd & 1) != 0 else (_rnd >> 1)
				per_step -= 1
				if per_step <= 0:
					break
				if _rnd == _seed:
					break
		surface = Image.create_from_data(surface.get_width(), surface.get_height(),
			false, Image.FORMAT_RGBA8, _sd)

	## One cell of the arriving frame into the compose surface, as bytes.
	func _copy_cell(x: int, y: int, w: int, h: int) -> void:
		for row in h:
			var at := (y + row) * _stride + x * 4
			for col in w * 4:
				_sd[at + col] = _ad[at + col]

	## `dissolvePatternsTrans`: 64 nested 8x8 ordered-dither tiles, one per 1/64th
	## of the transition.
	##
	## Written against the *difference* between consecutive tiles rather than by
	## re-scanning the clip, which the reference does. The tiles are nested, so
	## every pixel is copied exactly once across the whole transition — 307,200
	## byte-quads on a 640x480 stage instead of 19.6 million, which is the
	## difference between a dissolve and a stall.
	##
	## Verified against real frames: `piposh-dream` plays type 26 on sixteen frames
	## and `rating`'s `EGOZROO1.dir` cycles it with four other dissolves at 2000 ms
	## each, which together make it the most-played single type in the corpus.
	func _step_patterns(i: int) -> void:
		var index := 63 * (i + 1) / steps
		if index <= _pattern_at:
			return
		var now: Array = DISSOLVE_PATTERNS[index]
		var was: Array = DISSOLVE_PATTERNS[_pattern_at] if _pattern_at >= 0 \
			else [0, 0, 0, 0, 0, 0, 0, 0]
		_pattern_at = index
		var left := clip.position.x
		var top := clip.position.y
		var right := clip.position.x + clip.size.x
		var bottom := clip.position.y + clip.size.y
		for r in 8:
			var fresh: int = int(now[r]) & ~int(was[r])
			if fresh == 0:
				continue
			for b in 8:
				if (fresh & (0x80 >> b)) == 0:
					continue
				var y := top + r
				while y < bottom:
					var x := left + b
					var at := y * _stride
					while x < right:
						var o := at + x * 4
						_sd[o] = _ad[o]
						_sd[o + 1] = _ad[o + 1]
						_sd[o + 2] = _ad[o + 2]
						_sd[o + 3] = _ad[o + 3]
						x += 8
					y += 8
		surface = Image.create_from_data(surface.get_width(), surface.get_height(),
			false, Image.FORMAT_RGBA8, _sd)

	## `transMultiPass`: the three algorithms that reveal a *list* of rectangles
	## per step rather than one — venetian and vertical blinds, the checkerboard,
	## and the eight strip builds. All of them accumulate, so a step only ever
	## adds to what is already composed.
	##
	## **All eleven types here are UNVERIFIED**: nothing in the measured corpus
	## plays 37, 38, 39-46 or 49. `tools/transition_render.gd` asserts that a
	## venetian blind alternates down a column and a vertical blind across a row --
	## twelve bands where a wipe has one boundary -- and that every strip build and
	## the checkerboard only ever add.
	func _step_multipass(i: int) -> void:
		var w := clip.size.x
		var h := clip.size.y
		var rects: Array[Rect2i] = []
		var base := Rect2i(Vector2i.ZERO, clip.size)
		match type:
			37:  # venetian blinds
				base.size.y = y_step * (i + 1)
				for r in NUM_BLINDS:
					base.position = Vector2i(0, r * strip_size)
					rects.append(base)
			38:  # checkerboard
				base.size = Vector2i(strip_size, (i % maxi((steps + 1) / 2, 1)) * chunk_size)
				var flag := 1 if i + i > steps else 0
				for y in y_step:
					for x in x_step:
						if ((x & 2) ^ (y & 2) ^ flag) != 0:
							base.position = Vector2i(x * strip_size, y * strip_size)
							rects.append(base)
			39, 40, 45, 46:  # strips built along the vertical axis
				for r in NUM_STRIPS:
					var offset: int = r if (type == 40 or type == 46) \
						else NUM_STRIPS - r - 1
					var length := y_step * i - offset * strip_size
					if length <= 0:
						continue
					base.size = Vector2i(x_step, length)
					base.position = Vector2i(x_step * r,
						0 if (type == 45 or type == 46) else h - length)
					rects.append(base)
			41, 42, 43, 44:  # strips built along the horizontal axis
				for r in NUM_STRIPS:
					var offset: int = r if (type == 41 or type == 43) \
						else NUM_STRIPS - r - 1
					var length := x_step * i - offset * strip_size
					if length <= 0:
						continue
					base.size = Vector2i(length, y_step)
					base.position = Vector2i(
						0 if (type == 41 or type == 42) else w - length, y_step * r)
					rects.append(base)
			49:  # vertical blinds
				base.size.x = x_step * (i + 1)
				for r in NUM_BLINDS:
					base.position = Vector2i(r * strip_size, 0)
					rects.append(base)
			_:
				return
		for r in rects:
			var box := r
			box.position += clip.position
			box = box.intersection(clip)
			if box.size.x > 0 and box.size.y > 0:
				_blit(after, box, box.position)

	## `transZoom`: three nested rectangle outlines drawn in reverse ink over the
	## departing frame, growing (open) or shrinking (close), with the arriving
	## frame appearing only when the last step has run.
	##
	## **UNVERIFIED against real frames** — no container in eight corpora plays 47
	## or 48 — and one deliberate difference from the reference besides. ScummVM
	## draws the outlines through its ink primitives with `kInkTypeReverse`; this
	## inverts the RGB of the lines it draws directly, because the ink pipeline
	## here works on sprite artwork and there is no sprite. The visible result is
	## the same: an outline that is legible over any background, which is the
	## whole reason Director used reverse ink for it.
	func _step_zoom(i: int) -> void:
		var w := clip.size.x
		var h := clip.size.y
		# Every step redraws from the departing frame: the outlines are transient
		# marks, not an accumulating reveal.
		_blit(before, clip, clip.position)
		for s in range(2, -1, -1):
			var k := i - s
			if k < 0 or k > steps - 2:
				continue
			var box := _zoom_rect(k, w, h)
			_invert_outline(box)
		if i >= steps - 1:
			finish()

	func _zoom_rect(k: int, w: int, h: int) -> Rect2i:
		var dx := x_step * k / TSTEP_FRAC
		var dy := y_step * k / TSTEP_FRAC
		if type == 47:
			return Rect2i(clip.position.x + w / 2 - dx, clip.position.y + h / 2 - dy,
				dx * 2, dy * 2)
		return Rect2i(clip.position.x + dx, clip.position.y + dy,
			w - dx * 2, h - dy * 2)

	## Four one-pixel edges with their RGB inverted, clipped to the play's rect.
	func _invert_outline(box: Rect2i) -> void:
		if box.size.x <= 0 or box.size.y <= 0:
			return
		_invert_span(Rect2i(box.position.x, box.position.y, box.size.x, 1))
		_invert_span(Rect2i(box.position.x, box.position.y + box.size.y - 1,
			box.size.x, 1))
		_invert_span(Rect2i(box.position.x, box.position.y, 1, box.size.y))
		_invert_span(Rect2i(box.position.x + box.size.x - 1, box.position.y,
			1, box.size.y))

	func _invert_span(span: Rect2i) -> void:
		var box := span.intersection(clip)
		if box.size.x <= 0 or box.size.y <= 0:
			return
		for y in box.size.y:
			for x in box.size.x:
				var at := Vector2i(box.position.x + x, box.position.y + y)
				var c := surface.get_pixelv(at)
				surface.set_pixelv(at, Color(1.0 - c.r, 1.0 - c.g, 1.0 - c.b, c.a))
