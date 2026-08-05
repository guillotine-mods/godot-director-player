class_name LingoTrace
extends RefCounted
## What playback actually did, as JSON Lines, for diffing against a trace from
## the reference implementation.
##
## A different thing from LingoDiagnostics. The sink records FAILURES — a name
## the runtime could not bind — and deduplicates them. This records WHAT
## HAPPENED, in order, with no deduplication, because an oracle diff aligns two
## runs step by step and a collapsed repeat destroys the alignment.
##
## Off unless PIPOSH2_TRACE names a file. Off costs one null compare at each
## hook: nothing is opened, allocated, formatted or counted. The per-kind flags
## are resolved once here and handed to each hook site as a reference that is
## null when that kind is off, so a disabled kind costs exactly what a disabled
## trace does.
##
##   PIPOSH2_TRACE=/tmp/run.jsonl godot --headless --script tools/smoke.gd
##   PIPOSH2_TRACE_KINDS=channel,dispatch   # default: all three
##   PIPOSH2_TRACE_MAX=200000               # records before truncation
##
## An env var rather than an AppSettings toggle: AppSettings is the player's
## persisted display and QoL config, and a trace is a tool's argument for one
## invocation. Writing it there would survive into the next run and into an
## exported build's config file.

const ENV_PATH := "PIPOSH2_TRACE"
const ENV_KINDS := "PIPOSH2_TRACE_KINDS"
const ENV_MAX := "PIPOSH2_TRACE_MAX"

const KIND_CHANNEL := "channel"
const KIND_DISPATCH := "dispatch"
const KIND_PROP := "prop"

## What a field says when this build cannot answer it. A word, not a zero or an
## empty string: a diff against the reference has to see the hole rather than
## read a plausible value and report confident nonsense.
const UNAVAILABLE := "unavailable"

const DEFAULT_MAX := 400000
## Records between flushes. The file has to survive a run that ends in quit()
## without paying a syscall per record.
const FLUSH_EVERY := 512

## What this build cannot supply truthfully, declared once in the meta record so
## tools/oracle_diff.py configures itself from the stream rather than from a
## hardcoded table that will rot when phase 5 lands.
##
## Neither entry is a missing value; both are values whose meaning is narrower
## than the reference's. Saying so here is the point: a trace that reported
## ownership as plain false for every channel would be diffed against ScummVM
## and generate confident nonsense.
const DEGRADED := {
	"channel.puppet":
		"true or \"unavailable\", never false. true means a script issued"
		+ " puppetSprite / set the puppet of sprite for the channel. \"unavailable\""
		+ " means this build cannot tell an unowned channel from one the score"
		+ " puppeted, because score-driven ownership is not modelled yet (task 5.1).",
	"channel.ovr":
		"Properties listed here come from LingoHost.puppet, an override table only"
		+ " `visible` reaches the renderer from. For any other name the record"
		+ " reports state the port holds but does not draw (task 5.2).",
	"dispatch.cast":
		"\"unavailable\" for the behaviour, member and frame tiers. Only the movie"
		+ " tier resolves through LingoEngine.resolve_movie_handler, which is the"
		+ " one place that knows the owning cast; the other tiers reach a script"
		+ " AST, and the AST does not carry it.",
}

static var _shared: LingoTrace = null
static var _shared_resolved := false
static var _next_run := 0

## Which kinds this run asked for. Hook sites do not read these: `for_kind` hands
## each site either the trace or null once, at wiring time, so a kind that is off
## costs a hook exactly what an off trace does. Bools rather than three `self`
## references, which would be a reference cycle and would leave the file
## unflushed at exit.
var wants_channels := false
var wants_dispatch := false
var wants_props := false

var _file: FileAccess = null
var _written := 0
var _max := DEFAULT_MAX
var _truncated := false
var _since_flush := 0

## Alignment context, set by the runtime. Every record carries it, because two
## traces are aligned on the playback step and nothing else is stable across
## implementations.
var _run := 0
var _step := 0
var _movie := ""
var _frame := 0


static func shared() -> LingoTrace:
	## Resolved once per process. Six DirectorRuntime instances share one file in
	## tools/smoke.gd, so opening per runtime would leave five truncated files
	## behind and one survivor.
	if not _shared_resolved:
		_shared_resolved = true
		_shared = _open_from_environment()
	return _shared


static func _open_from_environment() -> LingoTrace:
	var path := OS.get_environment(ENV_PATH).strip_edges()
	if path == "":
		return null
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LingoTrace: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return null
	var trace := LingoTrace.new()
	trace._file = file
	var kinds := OS.get_environment(ENV_KINDS).strip_edges().to_lower()
	var wanted: PackedStringArray = (
		kinds.split(",", false) if kinds != ""
		else PackedStringArray([KIND_CHANNEL, KIND_DISPATCH, KIND_PROP]))
	var selected := PackedStringArray()
	for kind in wanted:
		match kind.strip_edges():
			KIND_CHANNEL:
				trace.wants_channels = true
				selected.append(KIND_CHANNEL)
			KIND_DISPATCH:
				trace.wants_dispatch = true
				selected.append(KIND_DISPATCH)
			KIND_PROP:
				trace.wants_props = true
				selected.append(KIND_PROP)
	var cap := OS.get_environment(ENV_MAX).strip_edges()
	if cap != "" and cap.is_valid_int():
		trace._max = maxi(1, int(cap))
	trace._emit({
		"k": "meta",
		"v": 1,
		"kinds": selected,
		"max": trace._max,
		"degraded": DEGRADED,
	})
	return trace


func for_kind(kind: String) -> LingoTrace:
	## The reference a hook site holds: this trace, or null when the run did not
	## ask for that kind.
	match kind:
		KIND_CHANNEL:
			return self if wants_channels else null
		KIND_DISPATCH:
			return self if wants_dispatch else null
		KIND_PROP:
			return self if wants_props else null
	return null


static func next_run() -> int:
	## Which DirectorRuntime a record came from. smoke.gd builds six, and without
	## this their steps interleave into one unalignable stream.
	_next_run += 1
	return _next_run


func context(run: int, step: int, movie: String, frame: int) -> void:
	## Where playback is, for the records the next call produces. Separate from
	## `step_channels` because a click dispatches outside the score step and its
	## records still have to say which frame they happened on.
	_run = run
	_step = step
	_movie = movie
	_frame = frame


# ---------------------------------------------------------------- channel state


func step_channels(runtime: Object, host: Object) -> void:
	## One record per occupied channel per playback step.
	##
	## Read from the score frame and the override table directly rather than
	## through LingoHost.get_sprite_prop. The binding is right to collapse the two
	## into one answer; a trace is not, because which of them answered is the
	## provenance an oracle diff needs — and calling the binding here would emit a
	## property-access record for every channel on every step.
	if _truncated:
		return
	var frame: Dictionary = runtime.loader.get_frame(runtime.frame_index)
	var seen: Dictionary = {}
	for sprite_value in frame.get("sprites", []):
		if typeof(sprite_value) != TYPE_DICTIONARY:
			continue
		var sprite: Dictionary = sprite_value
		var channel := int(sprite.get("channel", 0))
		if channel <= 0 or seen.has(channel):
			continue
		seen[channel] = true
		_channel_record(runtime, host, channel, sprite)
	if host == null:
		return
	## A channel the score does not fill but a script puppeted into existence is
	## occupied too, and it is exactly the case phase 5 has to get right.
	var overrides: Dictionary = host.puppet
	for channel_value in overrides.keys():
		var channel := int(channel_value)
		if channel > 0 and not seen.has(channel):
			seen[channel] = true
			_channel_record(runtime, host, channel, {})


func _channel_record(runtime: Object, host: Object, channel: int, sprite: Dictionary) -> void:
	var over: Dictionary = {}
	## true or "unavailable", never false. Absence from `puppeted` means no script
	## issued puppetSprite for this channel — it does NOT mean Director would call
	## the channel unowned, because score-driven puppet ownership has no store here
	## to ask. Emitting false would make every channel in the movie read as a
	## confident "not owned" and the oracle diff would report the difference
	## against ScummVM as real.
	var owned: Variant = UNAVAILABLE
	if host != null:
		var raw: Variant = host.puppet.get(channel, {})
		if typeof(raw) == TYPE_DICTIONARY:
			over = raw
		if host.puppeted.has(channel):
			owned = true
	var applied := PackedStringArray()
	_emit({
		"k": KIND_CHANNEL,
		"run": _run,
		"step": _step,
		"movie": _movie,
		"frame": _frame,
		"ch": channel,
		"castlib": _channel_int(over, applied, "castlibnum", sprite, "cast_lib", 1),
		"member": _channel_int(over, applied, "membernum", sprite, "cast_id", 0),
		"loch": _channel_int(over, applied, "loch", sprite, "loc_h", int(sprite.get("x", 0))),
		"locv": _channel_int(over, applied, "locv", sprite, "loc_v", int(sprite.get("y", 0))),
		"width": _channel_int(over, applied, "width", sprite, "width", 0),
		"height": _channel_int(over, applied, "height", sprite, "height", 0),
		"ink": _channel_int(over, applied, "ink", sprite, "ink", 0),
		"visible": not bool(runtime.is_channel_hidden(channel)),
		"puppet": owned,
		"ovr": applied,
	})


func _channel_int(over: Dictionary, applied: PackedStringArray, key: String,
		sprite: Dictionary, score_key: String, fallback: int) -> int:
	## The effective value, and a note in `applied` when it came from the override
	## table. See DEGRADED["channel.ovr"]: an overridden name other than `visible`
	## is state the port holds and the renderer ignores, so the diff has to be able
	## to tell the two apart instead of reading a plausible number.
	if over.has(key):
		applied.append(key)
		return LingoValue.to_int(over[key])
	return int(sprite.get(score_key, fallback))


# ---------------------------------------------------------------- dispatch


func dispatch(event: String, source: String, channel: int, script: String, cast: String,
		tier: String, handled: bool) -> void:
	## `source` is which level of Director's message hierarchy answered:
	## behaviour, member, frame, movie, or unresolved when none did.
	_emit({
		"k": KIND_DISPATCH,
		"run": _run,
		"step": _step,
		"movie": _movie,
		"frame": _frame,
		"event": event,
		"source": source,
		"ch": channel,
		"script": script,
		"cast": cast,
		"tier": tier,
		"handled": handled,
	})


# ---------------------------------------------------------------- property access


func property(target: String, id: Variant, name: String, direction: String, value: Variant,
		interpreter: Object) -> void:
	## `target` is what the property hangs off — sprite, movie or member — and
	## `id` identifies which one. The script and handler come from the interpreter,
	## the same location LingoDiagnostics records, so a trace entry and a
	## diagnostic about the same access agree on where it happened.
	var script := ""
	var handler := ""
	var line := 0
	if interpreter != null:
		var at: Array = interpreter.location()
		script = str(at[0])
		handler = str(at[1])
		line = int(at[2])
	_emit({
		"k": KIND_PROP,
		"run": _run,
		"step": _step,
		"movie": _movie,
		"frame": _frame,
		"target": target,
		"id": _json_safe(id),
		"name": name,
		"dir": direction,
		"value": _json_safe(value),
		"script": script,
		"handler": handler,
		"line": line,
	})


# ---------------------------------------------------------------- emission


func _emit(record: Dictionary) -> void:
	if _truncated or _file == null:
		return
	if _written >= _max:
		_truncated = true
		## A record, not a counter: a file that stopped early has to say so where
		## it stopped, or a diff reads the missing tail as a divergence.
		_file.store_line(JSON.stringify({"k": "truncated", "run": _run, "step": _step,
			"written": _written}))
		_file.flush()
		return
	_written += 1
	_file.store_line(JSON.stringify(record))
	_since_flush += 1
	if _since_flush >= FLUSH_EVERY:
		_since_flush = 0
		_file.flush()


func _json_safe(value: Variant) -> Variant:
	## A script can store any Variant on a puppet channel, and JSON.stringify
	## drops what it cannot represent. Rendering the odd ones through str() keeps
	## the line parseable and still shows what was there.
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return str(value) if typeof(value) == TYPE_STRING_NAME else value
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var out: Array = []
			for item in value:
				out.append(_json_safe(item))
			return out
	return str(value)


func written() -> int:
	return _written


func flush() -> void:
	if _file != null:
		_since_flush = 0
		_file.flush()
