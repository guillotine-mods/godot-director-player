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

var _stem_index: Dictionary = {} ## lower stem -> res path
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
	_stem_index.clear()
	# The game's own tree first. `_index_dir_recursive` is first-writer-wins, and
	# the game's files are the source of truth: everything under `assets/audio`
	# was produced from them by the Python pipeline and is scheduled for
	# deletion, so indexing it first would mean the port quietly played the
	# derived copy until the day that folder went away and then changed
	# behaviour with nothing to point at.
	var paths := Paths.new()
	if paths.load_config():
		_index_dir_recursive(paths.root)
	# Then the generated WAVs, as a fallback for as long as they exist. Delete
	# these two lines with the folder.
	_index_dir_recursive("res://assets/audio/sounds")
	_index_dir_recursive("res://assets/audio/fx")
	GameState.emit_log("Audio index: %d stems" % _stem_index.size(), "info")


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
				var stem := name.get_basename().to_lower()
				if not _stem_index.has(stem):
					_stem_index[stem] = full
		name = dir.get_next()
	dir.list_dir_end()


func resolve_path(file_name: String) -> String:
	_ensure_index()
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
		return ""
	if raw == "$whichsnd":
		raw = str(GameState.whichsnd).to_lower()
	raw = raw.get_file()
	var stem := raw.get_basename()
	if _stem_index.has(stem):
		return str(_stem_index[stem])
	return ""


func play_file(channel: int, file_name: String) -> void:
	_ensure_index()
	var ch := maxi(1, channel)
	var raw := file_name.to_lower().strip_edges()
	if raw.is_empty():
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
	if str(_channel_file.get(ch, "")) == stem:
		var existing: AudioStreamPlayer = _channels.get(ch)
		if existing and existing.playing:
			return

	_channel_file[ch] = stem
	_channel_failed[ch] = false
	var path := resolve_path(stem)
	if path.is_empty():
		_channel_failed[ch] = true
		GameState.emit_log("Audio miss: %s" % stem, "warn")
		return

	var stream := _load_stream(path)
	if stream == null:
		_channel_failed[ch] = true
		GameState.emit_log("Audio load fail: %s" % path, "warn")
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
	if path.get_extension().to_lower() == "aif":
		cues = AiffLoader.cue_points(FileAccess.get_file_as_bytes(path))
	_cue_cache[path] = cues
	return cues


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


func play_frame_sounds(frame: Dictionary) -> void:
	for snd in frame.get("sounds", []):
		if typeof(snd) != TYPE_DICTIONARY:
			continue
		play_file(int(snd.get("channel", 1)), str(snd.get("file", "")))


func play_click_sounds(on_click: Dictionary) -> void:
	for snd in on_click.get("sounds", []):
		if typeof(snd) != TYPE_DICTIONARY:
			continue
		play_file(int(snd.get("channel", 1)), str(snd.get("file", "")))


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
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is AudioStream:
			stream = res
	var extension := path.get_extension().to_lower()
	if stream == null and extension == "wav":
		stream = _load_wav_runtime(path)
	# Godot recognises neither AIFF nor AIFF-C, so a title whose sounds ship as
	# `.aif` is silent with nothing logged. See `autoload/aiff_loader.gd`.
	if stream == null and extension == "aif":
		var error: Array = []
		stream = AiffLoader.load_from_buffer(FileAccess.get_file_as_bytes(path), error)
		if stream == null and not error.is_empty():
			GameState.emit_log("aiff %s: %s" % [path.get_file(), "; ".join(error)], "warn")
	if stream != null:
		_stream_cache[path] = stream
	return stream


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
