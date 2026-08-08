extends RefCounted
## Which palette is current, and what it is doing. `DIRECTOR_ENGINE.md` §11.
##
## `director/director_palette.gd` holds the tables and the pure transforms; this
## holds the state Director keeps around them — the resolution order, the puppet
## override, the cycling offset and the fade progress. Split that way because the
## transforms are assertable without a movie and this is not.
##
## **Resolution order** (§11, `setLastPalette`): the frame's palette channel id
## if that palette is actually loaded, else the score-cached id, else the movie
## default. Every step re-checks existence rather than trusting the id, because
## Director tolerates references to palettes of long-deleted members — a score
## authored against a palette that was later deleted still plays, on whatever
## palette resolves next. A **puppet palette** short-circuits all of it.
##
## `table_for` is how this stays ignorant of casts: it is handed a callable that
## turns an id into a table, or into an empty array for "not loaded", and the
## host decides whether that means a built-in, a `CLUT` chunk in a palette cast
## member, or nothing. Without one, built-ins resolve and cast members do not.
##
## **Cycling state is keyed by palette id only** — deliberately, and it is
## authentic: re-arming a cycle with a different first/last on the *same* palette
## keeps the offset it had rather than resetting to zero, so a cycle that is
## reconfigured mid-run continues from where it was.
##
## **The blocking cycle is expressed as time, not as a blocked thread.** §11 says
## a cycle without *over time* runs the whole thing inside one frame transition,
## as a loop that steps, redraws, pumps events and sleeps. A GDScript loop that
## slept would freeze the process and take input handling with it, so the same
## observable behaviour is produced by holding the playhead for the cycle's
## duration (`director/director_frame_clock.gd` already does exactly this for
## transitions and tempo delays) and stepping the palette on the way through.
## The frame still takes the right length of time, the stage still redraws, input
## is still live, and `abort()` is still what a click does to it.
##
## **Unverified against this corpus**, all of it: 0 of 61,371 frames switch
## cycling on and none names a palette other than system Mac
## (`tools/palette_survey.gd`). The single frame with any effect at all is
## `strtgame` f38, one fade step. What is asserted instead is the machine itself,
## against synthetic records — `tools/palette_cycle.gd` — plus that one real
## frame. Title-agnostic: this knows palette ids and milliseconds, never a movie.

const Palette := preload("res://director/director_palette.gd")

## §11: "Speed 30 is unbounded (10 ms floor)". Below that the speed is a rate in
## frames per second, so a step lasts 1000/speed ms.
const UNBOUNDED_SPEED := 30
const SPEED_FLOOR_MS := 10.0
## Director stores the palette channel's first and last colour offset by 0x80,
## so the byte 0x7f names index 255. From the reference and **unverified**: every
## record in this corpus has first equal to last, which cannot distinguish this
## transform from any other. `director_score.gd:_palette_record` keeps the raw
## bytes for that reason and the un-offsetting happens here, where an index is
## actually needed.
const COLOR_BIAS := 0x80

## What is on screen now.
var table: PackedByteArray = Palette.system_mac()
## The id `table` was built from. 0 until something names one.
var current_id: int = Palette.SYSTEM_MAC
## The movie's own default, the last resort of the resolution order.
var default_id: int = Palette.SYSTEM_MAC
## The score cache: the id the score last successfully resolved. §11 gives it
## priority over the movie default and makes a switch that comes from it
## immediate rather than staged, because reaching it means the score was jumped
## into rather than played into.
var cached_id: int = 0
## `puppetPalette`. 0 is off, and off is not the same as "system Mac": a puppet
## palette of -1 pins the palette against the score, which is the whole point.
var puppet_id: int = 0
## func(id: int) -> PackedByteArray; empty means "that palette is not loaded".
var table_for: Callable = Callable()

## Cycling, keyed by palette id. See the header: the key is the id and nothing
## else, so reconfiguring a cycle on the same palette resumes rather than resets.
var _offset: Dictionary = {}
## The cycle or fade the current frame armed, or {} when the frame armed none.
var _effect: Dictionary = {}
## Milliseconds spent in the current effect.
var _elapsed := 0.0
## The table as it was before the current effect started, so `abort()` and the
## end of a fade both have something exact to restore.
var _before: PackedByteArray = PackedByteArray()


## Reset to a movie's starting state. The cycling offsets go with it: they are
## keyed by palette id, and ids are per movie.
func reset(movie_default: int = Palette.SYSTEM_MAC) -> void:
	default_id = movie_default
	current_id = movie_default
	cached_id = 0
	puppet_id = 0
	_offset.clear()
	_effect.clear()
	_elapsed = 0.0
	_before = PackedByteArray()
	table = _load(movie_default)


## The four ids and the cycling offsets, for a save state.
##
## **The running effect is not here, and that is the one judgement call in this
## file's half of a save.** A cycle or a fade is a *frame transition* (§11): it
## is armed by entering a frame and it runs to completion inside that frame's
## hold, so it is at most one frame long and the frame it belongs to is being
## re-entered by the restore anyway -- `save_state.gd` forces `_entered_index`
## apart from `_index` precisely so the frame arms itself again. Writing down
## `_elapsed` and `_before` would reproduce the *middle* of an effect that the
## restore then re-arms from the start, which is worse than not carrying it.
##
## The offsets do carry, because they outlive the effect on purpose: a cycle
## re-armed on the same palette resumes from where the last one stopped, and that
## is the behaviour a save has to preserve or a room's colours come back one
## rotation out.
func state() -> Dictionary:
	var offsets: Dictionary = {}
	for id in _offset:
		offsets[str(id)] = int(_offset[id])
	return {
		"current": current_id,
		"default": default_id,
		"cached": cached_id,
		"puppet": puppet_id,
		"offsets": offsets,
	}


func restore_state(from: Dictionary) -> void:
	if from.is_empty():
		return
	default_id = int(from.get("default", default_id))
	cached_id = int(from.get("cached", 0))
	puppet_id = int(from.get("puppet", 0))
	_offset.clear()
	for id in (from.get("offsets", {}) as Dictionary):
		_offset[int(str(id))] = int((from["offsets"] as Dictionary)[id])
	_effect.clear()
	_elapsed = 0.0
	_before = PackedByteArray()
	# Through `_apply` rather than by assigning `current_id`, so the table is
	# actually loaded: `current_id` is a claim about `table`, and setting one
	# without the other is how a restored room draws in the previous palette.
	_apply(int(from.get("current", current_id)))


## `puppetPalette <id>` — or 0 to hand the palette back to the score. Returns
## true when the table changed, which is the caller's signal to rebuild anything
## it baked against the old one.
func set_puppet(id: int) -> bool:
	puppet_id = id
	return _apply(resolve_id({}))


## Enter a frame: resolve the palette it names and arm whatever effect it asks
## for. `record` is `director_score.gd:_palette_record`'s output; an empty one, or
## one naming no palette, leaves everything as it stands — which is what the
## 61,104 frames in this corpus that write nothing to the channel mean.
##
## Returns true when the visible table changed.
func enter_frame(record: Dictionary) -> bool:
	var id := resolve_id(record)
	var changed := _apply(id)
	_arm(record)
	return changed


## §11's order, with existence re-checked at every step.
func resolve_id(record: Dictionary) -> int:
	if puppet_id != 0:
		return puppet_id
	var named := int(record.get("member", 0))
	if named != 0 and _loadable(named):
		# Reaching a palette through the score is what fills the cache; §11 has
		# the cache consulted before the movie default on every later frame.
		cached_id = named
		return named
	if cached_id != 0 and _loadable(cached_id):
		return cached_id
	return default_id


## Advance an armed cycle or fade by `ms` of real time. Returns true when the
## table changed and anything baked against it is stale.
func step(ms: float) -> bool:
	if _effect.is_empty():
		return false
	_elapsed += ms
	if bool(_effect.get("fade", false)):
		return _step_fade()
	return _step_cycle()


## How long the current frame must be held for, in milliseconds. Zero unless a
## cycle or fade is running without *over time*, which §11 runs to completion
## inside one frame transition. The caller hands this to the frame clock.
func hold_ms() -> float:
	if _effect.is_empty() or bool(_effect.get("over_time", false)):
		return 0.0
	return float(_effect.get("total_ms", 0.0))


func effect_running() -> bool:
	return not _effect.is_empty()


## What a click does to a cycle (§11): it stops and the palette goes back to what
## it was before the cycle started. Returns true when that changed the table.
func abort() -> bool:
	if _effect.is_empty():
		return false
	_effect.clear()
	_elapsed = 0.0
	if _before.size() == Palette.TABLE_BYTES and _before != table:
		table = _before
		return true
	return false


## Milliseconds one cycle step lasts, from the channel's speed. §11.
static func step_ms(speed: int) -> float:
	if speed >= UNBOUNDED_SPEED:
		return SPEED_FLOOR_MS
	if speed <= 0:
		return 0.0
	return 1000.0 / float(speed)


## The channel's stored colour byte as a palette index. See COLOR_BIAS.
static func color_index(raw: int) -> int:
	return (raw ^ COLOR_BIAS) & 0xFF


func _arm(record: Dictionary) -> void:
	if record.is_empty():
		return
	var cycling := bool(record.get("cycling", false))
	var fade := bool(record.get("fade", false))
	if not cycling and not fade:
		return
	var per_step := step_ms(int(record.get("speed", 0)))
	if per_step <= 0.0:
		return
	var first := color_index(int(record.get("first_color_raw", 0)))
	var last := color_index(int(record.get("last_color_raw", 0)))
	if first > last:
		var swap := first
		first = last
		last = swap
	_before = table.duplicate()
	_elapsed = 0.0
	if fade:
		# The frame count is the number of steps the fade takes, and a count of
		# zero would divide by nothing, so it floors at one -- a fade that arrives
		# in one step, which is what a zero-length fade means. `strtgame` f38, the
		# only fade in this corpus, carries exactly 1.
		var steps: int = maxi(int(record.get("frame_count", 1)), 1)
		var to_white := bool(record.get("fade_to_white", false))
		_effect = {
			"fade": true,
			"target": Color.WHITE if to_white else Color.BLACK,
			"steps": steps,
			"per_step": per_step,
			"total_ms": per_step * steps,
			"over_time": bool(record.get("over_time", false)),
		}
		return
	# A cycle runs over a closed range, `cycle_count` times, and auto-reverse
	# runs it backwards afterwards -- so the reverse doubles the duration rather
	# than replacing it.
	var span := last - first + 1
	if span <= 1:
		_effect.clear()
		return
	var counts: int = maxi(int(record.get("cycle_count", 1)), 1)
	var reverse := bool(record.get("auto_reverse", false))
	var steps_total: int = span * counts * (2 if reverse else 1)
	_effect = {
		"fade": false,
		"first": first,
		"last": last,
		"span": span,
		"steps": steps_total,
		"forward_steps": span * counts,
		"auto_reverse": reverse,
		"per_step": per_step,
		"total_ms": per_step * steps_total,
		"over_time": bool(record.get("over_time", false)),
	}


func _step_cycle() -> bool:
	var per_step: float = float(_effect["per_step"])
	var done: int = int(_elapsed / per_step)
	var total: int = int(_effect["steps"])
	var finished := done >= total
	done = mini(done, total)
	var id := current_id
	var base: int = int(_offset.get(id, 0))
	# Auto-reverse walks back down through the same offsets rather than
	# continuing to rotate, so the palette ends where it started.
	var forward: int = int(_effect["forward_steps"])
	var walked: int = done if done <= forward else forward - (done - forward)
	var next := Palette.cycled(
		_before, int(_effect["first"]), int(_effect["last"]), base + walked
	)
	var changed := next != table
	table = next
	if finished:
		# The offset survives the cycle, keyed by id: that is what makes a
		# re-armed cycle on the same palette resume instead of restarting.
		_offset[id] = base + walked
		_effect.clear()
		_elapsed = 0.0
	return changed


func _step_fade() -> bool:
	var total: float = float(_effect["total_ms"])
	var t: float = 1.0 if total <= 0.0 else clampf(_elapsed / total, 0.0, 1.0)
	var next := Palette.faded(_before, _effect["target"], t)
	var changed := next != table
	table = next
	if t >= 1.0:
		_effect.clear()
		_elapsed = 0.0
	return changed


## Install the table `id` names. Returns true when the pixels would differ.
func _apply(id: int) -> bool:
	var next := _load(id)
	current_id = id
	if next == table:
		return false
	table = next
	# A palette switch lands under any effect that was running, so the effect's
	# restore point has to move with it or an abort would put the old palette
	# back on a frame that had already left it.
	if not _effect.is_empty():
		_before = next.duplicate()
	return true


func _load(id: int) -> PackedByteArray:
	if table_for.is_valid():
		var supplied: PackedByteArray = table_for.call(id)
		if supplied.size() == Palette.TABLE_BYTES:
			return supplied
	return Palette.builtin(id)


## Whether `id` names a palette that is actually there. A positive id is a cast
## member and only the host can answer for it; without a host, only built-ins
## resolve, which is the correct answer for a movie with no palette members.
func _loadable(id: int) -> bool:
	if table_for.is_valid():
		var supplied: PackedByteArray = table_for.call(id)
		if supplied.size() == Palette.TABLE_BYTES:
			return true
	return id < 0 and Palette.can_build(id)
