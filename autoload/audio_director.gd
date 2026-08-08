extends Node
## Director's sound channels: `sound playFile`, `sound stop`, `soundBusy`,
## `the volume of sound N` and `the soundLevel`, over one `AudioStreamPlayer` per
## channel.
##
## Streams are decoded at runtime rather than imported, because the game's own
## files are read where they lie and Godot's importer has never seen them —
## `.aif` in this title, which Godot cannot load at all (`aiff_loader.gd`).
##
## This is the one place channel state lives. Both hosts route here, and the
## reason is that a channel outlives the movie that set it up: volume set in one
## room is still in force in the next, and `the soundLevel` is written in an
## options screen and read back somewhere else entirely. Two hosts each keeping
## their own copy is `docs/bugs-closed.md` 27 waiting to happen again.
##
## What the corpus asks of it, counted over `reference/lingo/`: 2,515
## `sound playFile`, 245 `soundBusy`, 69 `sound stop`, 67 lines naming
## `the volume of sound N` and 14 `the soundLevel`. Nothing calls `puppetSound`,
## `sound close`, `sound fadeIn` or `sound fadeOut`, and the score's own sound
## channels play nothing at all — no cast in the game holds a `sound` member.
## `tools/sound_survey.gd`.

## Director's default volume for a sound channel, and the range it is written in.
const VOLUME_MAX := 255
## `the soundLevel` is the *system* volume, 0-7, not a channel property — it is
## the Mac speaker setting Director exposed, and it multiplies whatever the
## channels are doing. 7 is the level a movie starts at.
const SOUND_LEVEL_MAX := 7

## Every path-tail of every file -> the file, so a request that carries part of a
## path is answered by that part rather than by the filename alone. `d1prom1`,
## `days/d1prom1` and `sounds/days/d1prom1` are three tails of one file and all
## three are keys; the bare filename is simply the shortest of them.
var _tail_index: Dictionary = {}
## Relative path (no extension) -> file on disc. The precise index.

var _path_index: Dictionary = {}

## Tails that more than one file ends with, so a request that resolves only by
## guessing can say so rather than silently picking one.

var _ambiguous: Dictionary = {}

var _root_key := ""

var _stream_cache: Dictionary = {} ## path -> AudioStream
var _channels: Dictionary = {} ## int -> AudioStreamPlayer
var _channel_file: Dictionary = {} ## int -> stem currently requested
var _channel_failed: Dictionary = {}
## `the volume of sound N`, 0-255, per channel. Kept here rather than in a host
## because both hosts set it and Director's channels outlive any one movie: a
## room that turns speech down to 75 and jumps to the next expects it to still
## be 75 there. 255 is Director's default and the level a channel starts at.
var _channel_volume: Dictionary = {}
## channel -> {from, to, seconds, elapsed} while a `sound fadeIn`/`fadeOut` runs.
var _fades: Dictionary = {}
## channel -> the cue points of the sound on it, and how many have been reported.
var _channel_cues: Dictionary = {}
var _channel_cues_passed: Dictionary = {}
## path -> cue points, so a sound played twice is not re-parsed for its markers.
var _cue_cache: Dictionary = {}
## `the soundLevel`, 0-7. Nothing else in the port owns the master bus, so
## `set_sound_level` drives it directly. Both hosts route here rather than each
## keeping a copy: one movie's option screen sets it and another reads it back.
var sound_level: int = SOUND_LEVEL_MAX

var _indexed: bool = false


func _ready() -> void:
	# Lazy index on first play — scanning 3k+ WAVs at boot stalls headless/editor.
	#
	# Ahead of the movie, deliberately. §12 steps sound fades "from the top of
	# the update, ahead of everything else", and the reason it matters is that a
	# fade-out reaching the bottom *stops* the channel: a `soundBusy` wait
	# released after the renderer has already decided this tick holds costs the
	# frame it was waiting on. An autoload processes before the main scene, and
	# this makes that ordering something the file states rather than something
	# the tree happens to give.
	process_priority = -100


## The fade ramp lives on the mixer's own clock rather than on a renderer's.
##
## Both renderers would otherwise have to remember to step it, and a harness that
## exercises a fade without a renderer at all — `tools/score_sound_check.gd` —
## would have to fake one. A fade that nothing steps does not fail, it holds at
## its starting level for ever, and a `soundBusy` wait behind a fade-out never
## releases. That is the failure mode this placement removes.
func _process(delta: float) -> void:
	step_fades(delta)


func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_build_index()


## Preloaded rather than reached by `class_name`: an autoload resolves global
## classes out of the editor's script cache, which a headless run has no reason
## to have refreshed, and the failure is "Identifier not declared" in a file
## nobody touched.
const Paths := preload("res://director/director_paths.gd")
const AiffLoader := preload("res://autoload/aiff_loader.gd")


func _build_index() -> void:
	_tail_index.clear()
	_path_index.clear()
	_ambiguous.clear()
	# The game's own tree first. `_index_dir_recursive` is first-writer-wins, and
	# the game's files are the source of truth: everything under `assets/audio`
	# was produced from them by the Python pipeline and is scheduled for
	# deletion, so indexing it first would mean the port quietly played the
	# derived copy until the day that folder went away and then changed
	# behaviour with nothing to point at.
	var paths := Paths.new()
	if paths.load_config():
		_index_dir_recursive(paths.root)
	GameState.emit_log("Audio index: %d files, %d ambiguous tail(s)" % [
		_path_index.size(), _ambiguous.size()
	], "info")


func _index_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_index_dir_recursive(full)
		else:
			var ext := name.get_extension().to_lower()
			if ext in ["wav", "ogg", "mp3", "aif"]:
				# What the scripts actually name: a path. Keyed relative to the
				# game root, lowercased, separators normalised and the extension
				# dropped, so `songs\strtgame\krupsong.aif` can find
				# `SONGS/strtgame/KRUPSONG.WAV`.
				var key := _relative_key(full)
				_path_index[key] = full
				# And every tail of it, because a script may name any suffix of
				# the path. This is where the folder used to be thrown away: only
				# the bare filename was indexed beside the whole path, so a
				# request for `days\d1prom1.aif` -- a real one, and what every
				# entry that skips the CD-drive probe builds -- fell through to
				# the filename and picked whichever of `SOUNDS/DAYS` and
				# `SOUNDS/S_DAY1` the directory walk reached first. That is a
				# wrong take of a line of speech, and it is silent.
				var parts := key.split("/", false)
				for start in range(parts.size()):
					var tail := "/".join(Array(parts).slice(start))
					if _tail_index.has(tail):
						_ambiguous[tail] = true
					else:
						_tail_index[tail] = full
		name = dir.get_next()
	dir.list_dir_end()


func resolve_path(file_name: String) -> String:
	_ensure_index()
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
		return ""
	if raw == "$whichsnd":
		raw = str(GameState.whichsnd).to_lower()
	return _resolve_normalised(raw)


## A request is a path, and the folder in it is meaning, not decoration.
##
## Scripts build these by concatenation from a global -- `playfromdisk` is
## `"songs\strtgame\\"`, `soundspath` is `soundspathstart & "days" & "\"` -- so
## the same filename appears under several folders and only the folder picks the
## right one. Matching on the filename alone is how the wrong take of a line gets
## played, and it is silent: a sound plays, so nothing looks broken. 315 of this
## corpus's 3,142 sounds share a filename with another; 0 share a folder and a
## filename.
##
## Matched by suffix at **both** ends, because a request is a path fragment and
## may be missing segments from either side. It carries a prefix this engine
## cannot see -- `the moviePath` on the authoring machine, or a CD drive letter --
## so leading segments are dropped until something matches; and it may be missing
## a leading segment the disc has, because the global that supplies it was set by
## a movie this entry never passed through. `soundspath` is
## `soundspathstart & "days" & "\"`, and `soundspathstart` is written only by
## `strtgame`'s drive probe: reach the room any other way and every request is
## `days\<name>.aif` against a disc whose files are under `SOUNDS/DAYS/`.
##
## The longest match wins in both directions, so a more specific request beats a
## less specific one, and the whole path beats a tail of it. A bare filename is
## the shortest tail, still legal and still common, and it is the only one this
## corpus can leave ambiguous.
func _resolve_normalised(raw: String) -> String:
	var key := _normalise(raw)
	if key == "":
		return ""
	if _path_index.has(key):
		return str(_path_index[key])
	# Drop leading segments until something matches: the request may be absolute
	# where the index is relative to the game root.
	var parts := key.split("/", false)
	for start in range(1, parts.size()):
		var tail := "/".join(Array(parts).slice(start))
		if _path_index.has(tail):
			return str(_path_index[tail])
	# Then the other direction: the request may be a tail of a path on disc.
	for start in range(parts.size()):
		var tail := "/".join(Array(parts).slice(start))
		if not _tail_index.has(tail):
			continue
		if _ambiguous.has(tail):
			push_warning(
				"sound '%s' resolves only by '%s', which more than one file ends with"
				% [raw, tail]
			)
		return str(_tail_index[tail])
	return _search_path_hit(raw)


## `the searchPath` — where Director looks once the indexed tree has said no.
##
## Set from Lingo (`preview_lingo_host.gd:search_path`) and empty otherwise, so
## the ordinary lookup above is unchanged for every title that never writes it.
## The entries are absolute paths outside the game root — Piposh 1 writes `d:`,
## `e:`, `f:` and `b:` in turn, looking for the CD — so they are tried directly
## against the filesystem rather than through the index, which only knows what is
## under the game folder.
##
## The request's own leading segments are dropped one at a time here too, for the
## same reason `_resolve_normalised` drops them: a request carries a prefix from
## the authoring machine and the search path supplies the real one.
func _search_path_hit(raw: String) -> String:
	if search_path.is_empty():
		return ""
	var wanted := raw.replace("\\", "/").replace(":", "/").trim_prefix("/")
	var parts := wanted.split("/", false)
	for entry in search_path:
		var base := str(entry).replace("\\", "/").replace(":", "/")
		if base.strip_edges() == "":
			continue
		if not base.ends_with("/"):
			base += "/"
		for start in parts.size():
			var tail := "/".join(Array(parts).slice(start))
			for candidate in [base + tail, base + tail + ".aif", base + tail + ".wav"]:
				if FileAccess.file_exists(candidate):
					return candidate
	return ""


## `the searchPath`, as the movie last set it. Paths outside the game root, so
## they are never indexed and are only ever tried on demand — see
## `_search_path_hit`. Empty until a movie writes one, which is 326 sites in
## Piposh 1 and none anywhere else.
var search_path: Array = []


func set_search_path(paths: Array) -> void:
	search_path = paths.duplicate()


## Director's `beep`: the machine's alert sound, `repeats` times, 400 ms apart.
##
## Synthesised rather than shipped. There is no beep on the disc — it is the
## Mac's own system alert, which this port has no copy of and no licence to — so
## what is played is a short tone with a fast attack and a decay, which is what a
## 1997 Mac's simple beep was. The whole run including its gaps is rendered into
## one buffer, so `beep 3` does not stop the handler that asked for it.
##
## Its own player, deliberately off the numbered channels: `soundBusy(1)` is what
## every line of speech in this corpus waits on, and a beep that claimed a
## channel would make a room wait for it.
func system_beep(repeats: int = 1) -> void:
	var player := _beep_player()
	if player == null:
		return
	player.stream = _beep_stream(maxi(repeats, 1))
	# Full on its own player; `the soundLevel` is the master bus and still
	# applies, which is right — the system volume turns the beep down too.
	player.volume_db = _volume_db(VOLUME_MAX)
	player.play()


var _beep: AudioStreamPlayer = null
## One rendered beep run per repeat count. There is exactly one count in the
## corpus (all 154 sites are the bare `beep`), so this caches one entry in
## practice and exists so that a beep in a loop does not resynthesise.
var _beep_cache: Dictionary = {}

const BEEP_RATE := 22050
const BEEP_HZ := 1000.0
const BEEP_MS := 120
## Director's own spacing between repeats.
const BEEP_GAP_MS := 400


func _beep_player() -> AudioStreamPlayer:
	if _beep != null:
		return _beep
	_beep = AudioStreamPlayer.new()
	_beep.name = "SystemBeep"
	_beep.bus = "Master"
	add_child(_beep)
	return _beep


func _beep_stream(repeats: int) -> AudioStreamWAV:
	if _beep_cache.has(repeats):
		return _beep_cache[repeats]
	var tone := int(BEEP_RATE * BEEP_MS / 1000.0)
	var gap := int(BEEP_RATE * BEEP_GAP_MS / 1000.0)
	var frames := tone * repeats + gap * maxi(repeats - 1, 0)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for r in repeats:
		var at := r * (tone + gap)
		for i in tone:
			# A quick attack and a long decay, so the tone starts without a click
			# and ends without one either -- a raw square gate reads as two clicks
			# with a whistle between them rather than as a beep.
			var envelope := minf(float(i) / (BEEP_RATE * 0.004), 1.0) \
				* (1.0 - float(i) / tone)
			var sample := int(sin(TAU * BEEP_HZ * i / BEEP_RATE) * envelope * 20000.0)
			data.encode_s16((at + i) * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = BEEP_RATE
	stream.stereo = false
	stream.data = data
	_beep_cache[repeats] = stream
	return stream


## Lowercased, **all three separators** folded to `/`, extension dropped.
##
## Three, not two, and the third is the one a port forgets. Director ran on the
## Mac first and its path separator is the **colon**: `the moviePath` on a Mac
## answers `HD:Rating:` and a script concatenating onto it produces
## `HD:Rating:sounds:batzegoz:f1.aif`. The Windows player wrote backslashes, and
## the same corpus carries both -- `soundspath` is built as
## `soundspathstart & "days" & "\"` in one movie and `the moviePath &
## "sounds:batzegoz:f1.aif"` in another, and BATZEGOZ.dir is a movie that does
## both within four members of each other. They are one problem and this is the
## one rule: a request is a path, and which byte the author's machine wrote
## between its segments is not information the lookup may act on.
##
## Applied to the request *and* to every file on disc (`_relative_key`), so both
## sides of the comparison are in the same alphabet. It folds the colon in
## `res://` as well, which costs nothing: `_resolve_normalised` drops leading
## segments until something matches, and a prefix this engine cannot see -- an
## authoring machine's volume name, a CD drive letter -- is exactly what those
## leading segments are.
##
## The extension is dropped because the scripts name `.aif` and a converted disc
## may hold `.wav`.
static func _normalise(path: String) -> String:
	return path.to_lower() \
		.replace("\\", "/") \
		.replace(":", "/") \
		.trim_suffix("/") \
		.get_basename()


## The index key for a file on disc: its path relative to the game root.
func _relative_key(full: String) -> String:
	var root := _root_prefix()
	var key := _normalise(full)
	if root != "" and key.begins_with(root):
		key = key.substr(root.length())
	return key.lstrip("/")


func _root_prefix() -> String:
	if _root_key != "":
		return _root_key
	var paths := Paths.new()
	if paths.load_config():
		_root_key = _normalise(paths.root)
	return _root_key


func play_file(channel: int, file_name: String) -> void:
	_ensure_index()
	var ch := maxi(1, channel)
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
		# A request for nothing is still a request, and it still takes the
		# channel. Returning here left the previous sound playing *and* left
		# `soundBusy` answering for it, so a `soundBusy` guard placed after the
		# `playFile` waited out a sound the script had already replaced -- and if
		# nothing ever replaced it, waited for ever. See `_fail` below.
		_fail(ch, "", "sound playFile named nothing")
		return
	if raw == "$whichsnd":
		raw = "%s.aif" % str(GameState.whichsnd).to_lower()
	var stem := raw.get_file().get_basename()
	if ch == 2 and not stem.begins_with("$"):
		GameState.whichsnd = stem

	# Idempotent: the same file already playing on this channel is left alone.
	#
	# A knowing deviation. Director's `sound playFile` restarts unconditionally,
	# and the reason this does not is `play_frame_sounds`: the older renderer
	# replays a frame's sounds on every frame *entry*, and a Director hold loop
	# re-enters the same frame every tick, so an unconditional restart machine-
	# guns the first 40 ms of the sound for as long as the room holds.
	#
	# It costs almost nothing here, measured over `reference/lingo/`: of the
	# 2,515 `sound playFile` statements, 11 sit in a frame handler that also
	# holds the playhead, 9 of those are behind a `soundBusy` guard, and the
	# remaining 2 (CHESS BehaviorScript 81 and 87) are gated on `the mouseDown`
	# and jump to another marker in the same branch — so no authored path in this
	# game re-plays a file on a channel that is already playing it.
	# Identity is the whole request, not the filename in it. Two folders holding
	# the same filename are two different sounds -- this game keeps the same
	# actor's lines under several -- and comparing stems made the second one
	# look like the first and skip.
	#
	# Compared *normalised*, for the reason `_normalise` gives: the same file can
	# be asked for with colons or with backslashes, and this corpus does both.
	# Comparing the raw strings made `sounds:batzegoz:h.aif` and
	# `sounds\batzegoz\h.aif` two different sounds, so a room that reached the
	# same line by two routes restarted it from the top instead of leaving it
	# alone -- which is the machine-gunning this guard exists to prevent, arrived
	# at through the separator instead of through the frame loop.
	var previous := str(_channel_file.get(ch, ""))
	if previous != "" and _normalise(previous) == _normalise(raw):
		var existing: AudioStreamPlayer = _channels.get(ch)
		if existing and existing.playing:
			return

	_channel_file[ch] = raw
	_channel_failed[ch] = false
	# The whole path, so the folder can pick between same-named files. Passing
	# the stem here is what made it play the wrong take: the resolver never saw
	# the folder the script had gone to the trouble of building.
	var path := resolve_path(raw)
	if path.is_empty():
		_fail(ch, raw, "Audio miss: %s" % raw)
		return

	var stream := _load_stream(path)
	if stream == null:
		_fail(ch, raw, "Audio load fail: %s" % path)
		return
	_start(ch, stream, _cue_points_of(path))


## Play a stream the caller already has, which is how a *cast member* reaches a
## channel: the score's two sound channels and `puppetSound` name a member, not a
## file, and `director/director_sound.gd` is what turns one into a stream.
##
## `id` is what `sound_member` reports back and what restart-on-change compares,
## so it must identify the source rather than describe it — "<lib>:<member>" for
## a member, the stem for a file.
func play_stream(channel: int, id: String, stream: AudioStream, cues: Array = []) -> void:
	var ch := maxi(1, channel)
	if stream == null:
		_channel_failed[ch] = true
		return
	_channel_file[ch] = id
	_channel_failed[ch] = false
	_start(ch, stream, cues)


func _start(channel: int, stream: AudioStream, cues: Array) -> void:
	_channel_cues[channel] = cues
	_channel_cues_passed[channel] = 0
	# A fade in progress belongs to the sound that was playing, not to this one.
	_fades.erase(channel)
	var player := _ensure_player(channel)
	player.stream = stream
	# Restored rather than assumed: `_fade_step` writes `volume_db` directly, so
	# a channel that was mid-fade when this sound started would otherwise inherit
	# the level the fade had reached.
	player.volume_db = _volume_db(channel_volume(channel))
	player.play()


## What is on a channel now: the stem of a file or "<lib>:<member>" of a cast
## member, and "" when nothing has been put there. Restart-on-change compares
## this, and so does `play_file`'s idempotence guard.
func channel_source(channel: int) -> String:
	return str(_channel_file.get(maxi(1, channel), ""))


## `the volume of sound N`. This game names it on 67 lines — 66 writes and 2
## reads — over channels 1 to 4, so a read has to answer what the last write said
## even on a channel that has never played: `set the volume of sound 3 to the
## volume of sound 3 - 20` steps a loop down and reads its own previous write
## every time round.
func channel_volume(channel: int) -> int:
	return int(_channel_volume.get(maxi(1, channel), VOLUME_MAX))


## Director's volume is 0-255 and linear in amplitude; Godot's is decibels, and
## the conversion is what makes 128 sound like half rather than nearly full.
## Applied to the channel's own player, so it survives the next `play_file` — a
## room sets the volume once and then speaks several lines through it.
func set_channel_volume(channel: int, level: int) -> void:
	var ch := maxi(1, channel)
	var clamped := clampi(level, 0, VOLUME_MAX)
	_channel_volume[ch] = clamped
	# A write to the volume cancels a fade. Director's fade *is* a series of
	# volume writes, so a script that sets the volume mid-fade has taken the
	# channel back; leaving the fade running would let it overwrite the value on
	# the very next tick.
	_fades.erase(ch)
	_ensure_player(ch).volume_db = _volume_db(clamped)


func _volume_db(level: int) -> float:
	return -80.0 if level <= 0 else linear_to_db(float(level) / VOLUME_MAX)


func set_sound_level(level: int) -> void:
	sound_level = clampi(level, 0, SOUND_LEVEL_MAX)
	AudioServer.set_bus_volume_db(0,
		-80.0 if sound_level == 0 else linear_to_db(float(sound_level) / SOUND_LEVEL_MAX))


# ------------------------------------------------------------------ fades

## `sound fadeIn <channel>, <ticks>` and `sound fadeOut`.
##
## Director ramps the channel's volume between 0 and whatever the channel's
## volume property says, over a number of ticks — 60 to the second — and a
## fade-out **stops the channel when it reaches the bottom**, which is the part
## that matters to a script: `sound fadeOut 1, 60` followed by a `soundBusy(1)`
## wait must eventually release. A fade that only turned the volume down would
## hold that loop for ever.
##
## The volume property itself is left alone. `the volume of sound N` after a fade
## reads what it read before, because Director fades the *output* and not the
## setting; that is why `set the volume of sound N` cancels a fade rather than
## being overridden by it.
##
## **Unexercised by the corpus this port was built on** — neither verb appears in
## any of its 3,349 scripts (`tools/sound_survey.gd`) — so the ramp shape and the
## stop-at-the-bottom rule are implemented from the reference, and
## `tools/sound_state.gd` asserts them against the engine rather than against the
## game.
const TICKS_PER_SECOND := 60.0
## Director's default when a fade names no duration.
const DEFAULT_FADE_TICKS := 60


func fade_in(channel: int, ticks: int = DEFAULT_FADE_TICKS) -> void:
	_begin_fade(channel, 0.0, 1.0, ticks)


func fade_out(channel: int, ticks: int = DEFAULT_FADE_TICKS) -> void:
	_begin_fade(channel, 1.0, 0.0, ticks)


func _begin_fade(channel: int, from: float, to: float, ticks: int) -> void:
	var ch := maxi(1, channel)
	var seconds := maxf(float(ticks) / TICKS_PER_SECOND, 0.0)
	if seconds <= 0.0:
		# A zero-tick fade is the endpoint, immediately — including the stop.
		_apply_fade(ch, to)
		if to <= 0.0:
			stop_channel(ch)
		return
	_fades[ch] = {"from": from, "to": to, "seconds": seconds, "elapsed": 0.0}
	_apply_fade(ch, from)


## Stepped once per tick from the top of the update, ahead of everything else —
## §12. Called by whichever renderer owns the clock; a fade that nothing steps
## simply holds at its starting level, which is visible rather than silent.
func step_fades(delta: float) -> void:
	if _fades.is_empty():
		return
	for ch in _fades.keys():
		var fade: Dictionary = _fades[ch]
		fade["elapsed"] = float(fade["elapsed"]) + delta
		var t: float = clampf(float(fade["elapsed"]) / float(fade["seconds"]), 0.0, 1.0)
		var level: float = lerpf(float(fade["from"]), float(fade["to"]), t)
		_apply_fade(int(ch), level)
		if t < 1.0:
			continue
		_fades.erase(ch)
		if level <= 0.0:
			stop_channel(int(ch))


func _apply_fade(channel: int, scale: float) -> void:
	var level := int(round(float(channel_volume(channel)) * clampf(scale, 0.0, 1.0)))
	_ensure_player(channel).volume_db = _volume_db(level)


func fading(channel: int) -> bool:
	return _fades.has(maxi(1, channel))


# ------------------------------------------------------------------ cue points

## Cue points passed since the current sound started, as `{index, name, frame}`,
## and cleared as they are read.
##
## Director sends `cuePassed me, channel, cueNumber, cueName` as the playhead of
## a *sound* crosses a marker in it, which is a second, sound-driven source of
## events alongside the frame's. Polled rather than pushed because the audio
## server has no callback at a sample position: the renderer asks once a tick,
## which is the same resolution every other Director event has.
##
## **Unexercised by the corpus this port was built on.** No script in it names
## `cuePoint`, `cuePassed` or `the cuePointNames of member`, and none of its
## 3,141 sounds carries a marker inside its own audio — 168 do carry a `MARK`
## chunk, and all 336 markers in them sit past the end of the file they are in
## (`tools/aiff_check.gd`). So this is implemented from the reference and proved
## against synthesised markers, not against the game.
func take_cues_passed(channel: int) -> Array:
	var ch := maxi(1, channel)
	var cues: Array = _channel_cues.get(ch, [])
	if cues.is_empty():
		return []
	var player: AudioStreamPlayer = _channels.get(ch)
	if player == null or not player.playing:
		return []
	var stream: AudioStream = player.stream
	var rate: float = float(stream.mix_rate) if stream is AudioStreamWAV else 44100.0
	var frame := int(player.get_playback_position() * rate)
	var passed := int(_channel_cues_passed.get(ch, 0))
	var out: Array = []
	while passed < cues.size() and int((cues[passed] as Dictionary).get("frame", 0)) <= frame:
		var cue: Dictionary = cues[passed]
		# 1-based: `cuePassed`'s cueNumber counts from 1, as every Director index
		# does, and an off-by-one here silences the first cue of every sound.
		out.append({
			"index": passed + 1,
			"name": str(cue.get("name", "")),
			"frame": int(cue.get("frame", 0)),
		})
		passed += 1
	_channel_cues_passed[ch] = passed
	return out


## Channels worth polling for cues: the ones something has actually been played
## on. Asking rather than assuming a count keeps the puppet channels above the
## score's two in scope without naming a limit Director does not have.
func cue_channels() -> Array:
	return _channel_cues.keys()


## The cue point names of whatever is on a channel, for
## `the cuePointNames of sound N`.
func cue_point_names(channel: int) -> Array:
	var out: Array = []
	for cue in _channel_cues.get(maxi(1, channel), []):
		out.append(str((cue as Dictionary).get("name", "")))
	return out


## True once every cue point of the sound on this channel has been passed, which
## is what a wait-for-cue tempo of −2 ("end") resolves to.
func cues_exhausted(channel: int) -> bool:
	var ch := maxi(1, channel)
	var cues: Array = _channel_cues.get(ch, [])
	return int(_channel_cues_passed.get(ch, 0)) >= cues.size()


func _cue_points_of(path: String) -> Array:
	if _cue_cache.has(path):
		return _cue_cache[path]
	var cues: Array = []
	# The tag, for `_load_stream`'s reason. Gating this on the extension instead
	# was the quieter half of the same bug: an AIFF named `.wav` would play once
	# the loader was fixed and then silently carry no cue points, so a tempo of
	# −2 waiting on one would wait forever with nothing to say why.
	if _container_tag(path) == "FORM":
		cues = AiffLoader.cue_points(FileAccess.get_file_as_bytes(path))
	_cue_cache[path] = cues
	return cues


## A `playFile` that could not start: the channel is taken, and it is silent.
##
## Director's `sound playFile` claims the channel before it opens the file, so a
## request it cannot satisfy leaves the channel *empty* -- not still playing what
## was there a moment ago. The distinction is the whole of `soundBusy`'s
## usefulness. `BehaviorScript 250` in this corpus is the shape that depends on
## it:
##
##     on exitFrame
##       if not soundBusy(1) then go(marker(0))
##     end
##
## and its counterpart is a frame that plays a line and then polls. Answering
## "busy" for a sound the script has already replaced makes that poll wait out the
## *old* sound; answering it for a sound that never started at all makes the poll
## wait for something that can never end. Both are the same mistake, and neither
## is recoverable from inside the movie -- the script has no way to ask whether
## its `playFile` worked.
##
## Stopping the player is the second half and it is not cosmetic: without it the
## previous sound stays audible while `soundBusy` says the channel is free, so
## the next line of speech is spoken over the last one.
func _fail(channel: int, request: String, why: String) -> void:
	var player: AudioStreamPlayer = _channels.get(channel)
	if player and player.playing:
		player.stop()
	_fades.erase(channel)
	_channel_cues[channel] = []
	_channel_cues_passed[channel] = 0
	_channel_file[channel] = request
	_channel_failed[channel] = true
	GameState.emit_log(why, "warn")


func sound_busy(channel: int) -> bool:
	var ch := maxi(1, channel)
	if bool(_channel_failed.get(ch, false)):
		return false
	var player: AudioStreamPlayer = _channels.get(ch)
	if player == null:
		return false
	return player.playing


func stop_all() -> void:
	for key in _channels.keys():
		stop_channel(int(key))


func stop_channel(channel: int) -> void:
	var ch := maxi(1, channel)
	var player: AudioStreamPlayer = _channels.get(ch)
	if player and player.playing:
		player.stop()
	_channel_file[ch] = ""
	_channel_failed[ch] = false
	_fades.erase(ch)
	_channel_cues[ch] = []
	_channel_cues_passed[ch] = 0


## `sound close <channel>` — stop, and give the channel's device back.
##
## Distinct from `sound stop` in Director, which leaves the channel allocated;
## `close` releases it, and the next `playFile` on it re-opens. Nothing here
## holds a scarce device, so the difference that survives the port is the volume:
## a closed channel is a *new* channel when it re-opens, so it comes back at
## Director's default rather than at whatever the last movie left. Written
## nowhere in the corpus this port was built on, so this is the reference's
## reading and not an observed one.
func close_channel(channel: int) -> void:
	var ch := maxi(1, channel)
	stop_channel(ch)
	_channel_volume.erase(ch)
	var player: AudioStreamPlayer = _channels.get(ch)
	if player != null:
		player.volume_db = _volume_db(VOLUME_MAX)


## A record with no file name in it is a record that names no sound, and it is
## not the same thing as `sound playFile <ch>, ""` — that is a script asking for
## nothing, which takes the channel. A score record that simply carries no name
## must leave the channel alone, or every frame entry would stop whatever a
## script had put there.
func play_frame_sounds(frame: Dictionary) -> void:
	for snd in frame.get("sounds", []):
		if typeof(snd) != TYPE_DICTIONARY:
			continue
		var file := str((snd as Dictionary).get("file", ""))
		if file.strip_edges().is_empty():
			continue
		play_file(int((snd as Dictionary).get("channel", 1)), file)


func play_click_sounds(on_click: Dictionary) -> void:
	for snd in on_click.get("sounds", []):
		if typeof(snd) != TYPE_DICTIONARY:
			continue
		var file := str((snd as Dictionary).get("file", ""))
		if file.strip_edges().is_empty():
			continue
		play_file(int((snd as Dictionary).get("channel", 1)), file)


func _ensure_player(channel: int) -> AudioStreamPlayer:
	if _channels.has(channel):
		return _channels[channel]
	var player := AudioStreamPlayer.new()
	player.name = "SoundCh%d" % channel
	player.bus = "Master"
	add_child(player)
	_channels[channel] = player
	return player


func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var stream: AudioStream = null
	# The **container tag**, not the extension. A disc's filenames are as much a
	# guess as its paths are: `FX/DRILL.WAV` is an AIFF and `FX/BIRDS.AIF` is a
	# RIFF, in the same folder, in a game that ships 187 sounds. Choosing the
	# decoder by name sent each of those to the one that would refuse it, and a
	# sound that will not load is silent with the channel taken -- the exact state
	# `tools/sound_wait.gd` exists to prove impossible.
	#
	# `director/director_sound.gd:decode` had this right from the start, because a
	# *cast member* has no filename to be wrong about, so it had to read the tag.
	# This is the same dispatcher for the same formats, and it should never have
	# been the odd one out.
	var tag := _container_tag(path)
	# Never ask the importer about a container this port decodes itself. That is
	# already what happens on a clean checkout -- game data ships no `.import`
	# stubs, so `exists()` is false for all 12,794 sounds -- and `.gitignore` says
	# as much in as many words: "BMPs/WAVs load at runtime from source files".
	#
	# It stops being a no-op the moment the editor scans the project, which writes
	# a stub next to every `.wav` it finds. For a file whose name lies the import
	# then fails, leaving a stub pointing at a `.sample` that was never written --
	# so `exists()` answers true, `load()` fails, and four ERROR lines are printed
	# for a sound the next three lines go on to decode perfectly. The importer is
	# kept only for a container this port has no decoder for; no root holds one
	# today (0 ogg, 0 mp3 across all six), which is exactly why it must not be
	# consulted about the ones it does.
	if stream == null and not tag in ["RIFF", "FORM"] and ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is AudioStream:
			stream = res
	if stream == null and tag == "RIFF":
		stream = _load_wav_runtime(path)
	# Godot recognises neither AIFF nor AIFF-C, so a title whose sounds ship as
	# `.aif` is silent with nothing logged. See `autoload/aiff_loader.gd`.
	if stream == null and tag == "FORM":
		var error: Array = []
		stream = AiffLoader.load_from_buffer(FileAccess.get_file_as_bytes(path), error)
		if stream == null and not error.is_empty():
			GameState.emit_log("aiff %s: %s" % [path.get_file(), "; ".join(error)], "warn")
	# Neither tag, and `ResourceLoader` did not know it either: `ogg` and `mp3`
	# arrive that way and are fine, but so does a container this port cannot read,
	# and that one used to be indistinguishable from silence. `tools/sound_format_check.gd`
	# names the two the corpus holds.
	if stream == null and not tag in ["RIFF", "FORM"]:
		GameState.emit_log("sound %s: %s is no container this port decodes"
			% [path.get_file(), JSON.stringify(tag)], "warn")
	if stream != null:
		_stream_cache[path] = stream
	return stream


## A sound file's first four bytes, or `""` when it is empty or unreadable.
##
## Cheap enough to be unconditional: `_load_stream` and `_cue_points_of` each
## cache by path, so this opens a given file once per run.
func _container_tag(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var head := file.get_buffer(4)
	if head.size() < 4:
		return ""
	return head.get_string_from_ascii()


func _load_wav_runtime(path: String) -> AudioStreamWAV:
	## Minimal PCM WAV loader so audio works without editor import.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data := file.get_buffer(file.get_length())
	if data.size() < 44:
		return null
	if data[0] != 0x52 or data[1] != 0x49 or data[2] != 0x46 or data[3] != 0x46:
		return null
	var offset := 12
	var audio_format := 1
	var channels := 1
	var sample_rate := 22050
	var bits_per_sample := 16
	var pcm := PackedByteArray()
	while offset + 8 <= data.size():
		var chunk_id := data.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := data[offset + 4] | (data[offset + 5] << 8) | (data[offset + 6] << 16) | (data[offset + 7] << 24)
		offset += 8
		if chunk_id == "fmt " and offset + 16 <= data.size():
			audio_format = data[offset] | (data[offset + 1] << 8)
			channels = data[offset + 2] | (data[offset + 3] << 8)
			sample_rate = data[offset + 4] | (data[offset + 5] << 8) | (data[offset + 6] << 16) | (data[offset + 7] << 24)
			bits_per_sample = data[offset + 14] | (data[offset + 15] << 8)
		elif chunk_id == "data":
			var end := mini(offset + chunk_size, data.size())
			pcm = data.slice(offset, end)
			break
		offset += chunk_size
		if chunk_size % 2 == 1:
			offset += 1
	if pcm.is_empty():
		return null
	if audio_format != 1:
		GameState.emit_log("WAV not PCM: %s (fmt %d)" % [path.get_file(), audio_format], "warn")
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.stereo = channels > 1
	match bits_per_sample:
		8:
			stream.format = AudioStreamWAV.FORMAT_8_BITS
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		_:
			GameState.emit_log("WAV bits unsupported: %s (%d)" % [path.get_file(), bits_per_sample], "warn")
			return null
	stream.data = pcm
	return stream
