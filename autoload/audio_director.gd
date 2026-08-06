extends Node
## Director-style multi-channel `sound playFile` / `soundBusy`.
## Loads WAVs at runtime (assets may not be imported yet).

const AUDIO_ROOTS: PackedStringArray = [
	"res://assets/audio/fx",
	"res://assets/audio/sounds",
]

var _stem_index: Dictionary = {} ## lower stem -> res path
var _stream_cache: Dictionary = {} ## path -> AudioStream
var _channels: Dictionary = {} ## int -> AudioStreamPlayer
var _channel_file: Dictionary = {} ## int -> stem currently requested
var _channel_failed: Dictionary = {}


var _indexed: bool = false


func _ready() -> void:
	# Lazy index on first play — scanning 3k+ WAVs at boot stalls headless/editor.
	pass


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

	# Idempotent: same file already playing on channel.
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
	var player := _ensure_player(ch)
	player.stream = stream
	player.play()


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
		var player: AudioStreamPlayer = _channels[key]
		if player and player.playing:
			player.stop()
		_channel_file[key] = ""
		_channel_failed[key] = false


func stop_channel(channel: int) -> void:
	var ch := maxi(1, channel)
	var player: AudioStreamPlayer = _channels.get(ch)
	if player and player.playing:
		player.stop()
	_channel_file[ch] = ""
	_channel_failed[ch] = false


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
