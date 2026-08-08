extends SceneTree
## A sound's **extension does not decide whether it loads** — its first four
## bytes do.
##
##   godot --headless --path . --script tools/sound_format_check.gd -- --root piposh-dream
##
## `director/director_sound.gd` already knows this: `decode()` reads the tag and
## branches on `FORM`/`RIFF`/`snd `, because a cast member has no filename to lie
## with. The *file* path did not, and that asymmetry is the bug this asserts
## against. `AudioDirector._load_stream` picked its decoder from
## `path.get_extension()`, so a file whose name disagreed with its contents fell
## between the two branches and returned null — and a sound that will not load is
## silent, with the channel taken. That is the failure mode `tools/sound_wait.gd`
## exists to catch one step later; this catches the cause.
##
## Measured across the six roots this engine runs, 12,795 sound-named files
## disagree with their contents exactly five times, all in two titles:
##
##   games/piposh-dream/FX/DRILL.WAV   AIFF named .WAV
##   games/piposh-dream/FX/BIRDS.AIF   RIFF named .AIF
##   games/piposh-dream/FX/DRUMS.AIF   NeXT/Sun `.snd` named .AIF
##   games/piposh2/SOUNDS/S_NIGHT3/HEZ61.AIF    0 bytes
##   games/rating/SOUNDS/BLASNAKE/EGOZHIT2.AIF  no container tag at all
##
## Five files is exactly why this is a harness and not a survey somebody reads
## once. One title in six is enough to make the rule real, and the *next* disc is
## not going to be cleaner — these are 1990s CD masters, and the tail is where
## the mastering mistakes live.
##
## Only the first two are this engine's to fix, and the split is the point of the
## two counts below. A container this port carries a decoder for **must** decode:
## that is a failure. A container it does not — an `au`, a truncated file, a file
## that is not audio — is a fact about the disc, and is reported by name so the
## next person does not go looking for it in the code.
##
## Title-agnostic: every file is discovered from the configured root.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")

## What `AudioDirector` indexes, and therefore everything a script can name.
const SOUND_EXTENSIONS := ["wav", "aif", "aiff", "mp3", "ogg"]

## The container tags this port carries a decoder for. A file tagged with one of
## these and refusing to decode is a bug here; anything else is the disc's.
const DECODABLE := ["FORM", "RIFF"]

## What a disc would normally name each container. Used **only** to describe a
## mismatch in the report — never to choose a decoder, which is the mistake being
## asserted against.
const CUSTOMARY_TAG := {"aif": "FORM", "aiff": "FORM", "wav": "RIFF"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return
	var audio := root.get_node_or_null("AudioDirector")
	if audio == null:
		print("AudioDirector autoload is not present")
		quit(1)
		return

	var files := PackedStringArray()
	_walk(paths.root, files)
	var limit := Args.number(args, "limit", 0)
	if limit > 0 and files.size() > limit:
		files = files.slice(0, limit)

	var mismatched: Array[String] = []
	var undecodable: Array[String] = []
	var failures: Array[String] = []
	var loaded := 0

	var title := "every sound this port can decode, decodes"
	h.begin(title)
	h.check("the configured root holds sounds to check", files.size() > 0,
		"%d file(s) under %s" % [files.size(), paths.root])

	for path in files:
		var tag := _container_tag(path)
		var extension := path.get_extension().to_lower()
		var customary := str(CUSTOMARY_TAG.get(extension, tag))
		if tag != customary:
			mismatched.append("%s is named .%s and is %s" % [path, extension, _describe(tag)])
		if not DECODABLE.has(tag):
			undecodable.append("%s: %s" % [path, _describe(tag)])
			continue
		# A container this port decodes, holding nothing to decode. That is a
		# third answer and not a softer version of either: the tag is one the
		# engine handles, so it cannot go in the bucket above, and there is no
		# implementation that would make it play, so it must not be a failure.
		# `piposh/SOUNDS/STIMDAY1/PIP21.AIF` is the corpus's only one — an 86-byte
		# AIFF declaring 0 sample frames — and without this it would hold the gate
		# permanently red for a file nobody can fix.
		if _declares_no_frames(path, tag):
			undecodable.append("%s: %s, declaring 0 sample frames" % [path, _describe(tag)])
			continue
		# The engine's own file path, not a decoder called directly. A decoder
		# that works while the thing that chooses it does not is the whole bug.
		var stream: AudioStream = audio.call("_load_stream", path)
		if stream == null:
			failures.append("%s (%s) returned no stream" % [path, tag])
			continue
		if stream is AudioStreamWAV and (stream as AudioStreamWAV).data.is_empty():
			# A zero-length stream satisfies "no error" and plays nothing, which
			# from the player's seat is not loading at all.
			failures.append("%s (%s) decoded to 0 samples" % [path, tag])
			continue
		loaded += 1

	for line in failures:
		h.check("decodes", false, line)
	h.check("every %s file decoded to a playable stream" % "/".join(DECODABLE),
		failures.is_empty(), "%d of %d" % [loaded, loaded + failures.size()])
	h.complete(title)

	print("")
	print("files       : %d" % files.size())
	print("decoded     : %d" % loaded)
	print("name lies about contents: %d" % mismatched.size())
	for line in mismatched:
		print("    %s" % line)
	print("no decoder in this port : %d  (a fact about the disc, not the code)" % undecodable.size())
	for line in undecodable:
		print("    %s" % line)

	quit(h.finish("a sound's extension does not decide whether it loads"))


## The first four bytes, or "" when the file is empty or unreadable.
func _container_tag(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var head := file.get_buffer(4)
	if head.size() < 4:
		return ""
	return head.get_string_from_ascii()


## True when the container says outright that it holds no audio, which is a fact
## about the disc rather than a decoder that failed. Only the two containers this
## port reads are asked: AIFF keeps the frame count in `COMM`, RIFF in `data`.
func _declares_no_frames(path: String, tag: String) -> bool:
	var data := FileAccess.get_file_as_bytes(path)
	var at := 12
	while at + 8 <= data.size():
		var chunk := data.slice(at, at + 4).get_string_from_ascii()
		var size := _u32(data, at + 4, tag == "FORM")
		if size < 0 or at + 8 + size > data.size():
			return false
		if tag == "FORM" and chunk == "COMM" and size >= 18:
			return _u32(data, at + 10, true) == 0
		if tag == "RIFF" and chunk == "data":
			return size == 0
		at += 8 + size + (size & 1)
	return false


## IFF is big-endian and RIFF little-endian, which is the whole difference
## between the two walks above.
func _u32(data: PackedByteArray, at: int, big_endian: bool) -> int:
	if at + 4 > data.size():
		return -1
	if big_endian:
		return (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3]
	return data[at] | (data[at + 1] << 8) | (data[at + 2] << 16) | (data[at + 3] << 24)


func _describe(tag: String) -> String:
	match tag:
		"":
			return "empty or unreadable"
		"FORM":
			return "an IFF/AIFF container"
		"RIFF":
			return "a RIFF/WAV container"
		".snd":
			return "a NeXT/Sun `au`, which this port has no decoder for"
		_:
			return "tagged %s, which is no audio container this port knows" % JSON.stringify(tag)


func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if entry.get_extension().to_lower() in SOUND_EXTENSIONS:
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
