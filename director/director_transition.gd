extends RefCounted
## Frame transitions: where the parameters come from, and how long one lasts.
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
## Only the *time* is modelled here. §10 is explicit that the algorithm can
## degrade to a cut without misleading anyone — "a cut reads as a stylistic
## choice, a wrong wipe reads as a bug" — but that the duration cannot, because
## the movie's own scripts are timed against it: a transition that renders
## instantly runs everything after it early, and pulls speech out of step with
## the picture it was authored over.
##
## What the corpus actually asks for, measured by `tools/transition_survey.gd`
## over all 61 containers (61,371 frames):
##
##   transition cast members          3  (CHESS 199, ENDMOVI2 121, ENDMOVI5 178)
##   frames referencing one           5  (CHESS f91; ENDMOVI2 f805, f849;
##                                        ENDMOVI5 f614, f698)
##   distinct types                   2  (11 push left ×4, 52 dissolve bits ×1)
##   durations                        600 ms ×1, 700 ms ×2, 1000 ms ×2
##   total time the corpus spends in transitions   4.0 s
##   `puppetTransition` calls in the decompiled Lingo               0
##
## So thirteen transition algorithms would be thirteen pieces of dead code for
## this title, and four seconds of held playhead is the whole of what is
## missing. The resolution order and the member decode are engine behaviour and
## are implemented in full; the drawing is deliberately a cut.
##
## Title-agnostic: nothing here knows which movie is loaded. The measurements
## above are evidence in a comment, not data in the code.

## The published Director transition numbering. Names only — nothing in this
## port branches on the type, so a wrong name misreports a diagnostic string and
## can never misplay a frame. Numbers outside the table are legal in a file and
## render as a cut like every other type.
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

## Director steps a transition once per 1/60 s tick and caps the step count at
## `duration × 60 / 1000` (§10). The cap is what makes the duration the real
## quantity: a transition never runs longer than it asks for, however coarse its
## chunk size.
const TICKS_PER_SECOND := 60.0

## A transition member's own record is 6 bytes and carries no cast info, so a
## duration this large is a misparse rather than a slow wipe. Director stores
## the duration as an unsigned 16-bit millisecond count, so anything is
## representable up to ~65 s; nothing in the corpus exceeds 1000 ms, and a hold
## of a minute is indistinguishable on screen from the movie having hung.
const MAX_DURATION_MS := 30000.0


## The 6-byte specific block of a type-14 cast member.
##
## Measured, not assumed. The three members in this corpus decode as:
##
##   CHESS 199     00 08 34 02 02 58   chunk 8,  type 52, 0x0258 =  600 ms
##   ENDMOVI2 121  00 10 0b 02 02 bc   chunk 16, type 11, 0x02bc =  700 ms
##   ENDMOVI5 178  00 10 0b 02 03 e8   chunk 16, type 11, 0x03e8 = 1000 ms
##
## Byte 0 is zero in all three and byte 3 is 2 in all three, so neither is
## pinned by this corpus: byte 0 reads as the flag byte and byte 3 as the
## change-area selector (whole stage versus the changed rectangle), which is the
## order §10 lists the parameters in, but a constant column cannot distinguish
## that from the two being swapped. Both are carried through unread — nothing
## here consumes them — so a wrong guess about which is which costs a label and
## not a behaviour.
static func decode_member(spec: PackedByteArray) -> Dictionary:
	if spec.size() < 6:
		return {}
	var duration := float((spec[4] << 8) | spec[5])
	return {
		"flags": spec[0],
		"chunk_size": spec[1],
		"transition_type": spec[2],
		"change_area": spec[3],
		"duration_ms": clampf(duration, 0.0, MAX_DURATION_MS),
	}


## Is this member record one this file can time a transition from?
static func is_transition(member: Dictionary) -> bool:
	return float(member.get("duration_ms", 0.0)) > 0.0


## Source 1 beats source 2 beats nothing (§10). `puppet` is consumed by the
## caller once this has returned it — a puppet transition applies to exactly one
## frame change, which is why `puppetTransition` is written immediately before
## the `go` that uses it and never needs cancelling.
static func resolve(puppet: Dictionary, frame_member: Dictionary) -> Dictionary:
	if is_transition(puppet):
		return puppet
	if is_transition(frame_member):
		return frame_member
	return {}


## How long the playhead is held, in milliseconds.
##
## The step count is capped at one per tick over the duration, so a duration
## shorter than a tick still costs a whole tick: Director cannot render half a
## step. Rounding up rather than down keeps a 10 ms transition from costing
## nothing at all, which is the one case where "instant" and "as authored"
## visibly differ.
static func hold_ms(transition: Dictionary) -> float:
	var duration := float(transition.get("duration_ms", 0.0))
	if duration <= 0.0:
		return 0.0
	var steps := ceilf(duration * TICKS_PER_SECOND / 1000.0)
	return maxf(duration, steps * 1000.0 / TICKS_PER_SECOND)


static func describe(transition: Dictionary) -> String:
	if not is_transition(transition):
		return "none"
	var type_code := int(transition.get("transition_type", 0))
	return "%d %s, %d ms, chunk %d" % [
		type_code,
		str(TYPE_NAMES.get(type_code, "unnamed")),
		int(transition.get("duration_ms", 0)),
		int(transition.get("chunk_size", 0)),
	]
