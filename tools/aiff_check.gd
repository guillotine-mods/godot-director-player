extends SceneTree
## Every sound the game ships decodes to a playable stream.
##
##   godot --headless --script tools/aiff_check.gd
##   godot --headless --script tools/aiff_check.gd -- --limit 200
##
## Godot loads neither AIFF nor AIFF-C, so before this the game's 3,142 sounds
## were unreachable: `AudioDirector` indexes only wav/ogg/mp3, and a sound that
## does not resolve plays nothing and says nothing. Silence is the failure mode,
## which is why this asserts a decode rather than an absence of errors.
##
## Asserted per file: a stream comes back, its rate is one the corpus actually
## uses, and it carries samples. A zero-length stream would satisfy "no error"
## and play nothing, which is the same symptom as not loading at all.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const Aiff := preload("res://autoload/aiff_loader.gd")

## Rates measured across the corpus. A file outside this set is not a failure,
## but it is worth seeing, since it means the survey missed something.
## Plus the neighbours truncation produces: the 80-bit extended rate is read
## from its top 32 mantissa bits, so a rate the survey rounded to 22255 arrives
## as 22254. One part in 22,000 is four thousandths of a semitone and nobody will
## hear it, but it is a real difference, and the alternative is a check that
## tolerates any rate at all — including the negative ones an earlier bug in this
## conversion produced, which decode happily and play silence.
const KNOWN_RATES := [7000, 11000, 11127, 11128, 22000, 22050, 22254, 22255, 44100]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var files := PackedStringArray()
	_walk(paths.root, files)
	var limit := Args.number(args, "limit", 0)
	if limit > 0 and files.size() > limit:
		files = files.slice(0, limit)

	var decoded := 0
	var empty := 0
	var rates := {}
	var formats := {}
	## IFF chunk tag -> files carrying it. `MARK` is where an AIFF keeps its cue
	## points, so this is the measurement §12's cue-point row rests on.
	var chunks := {}
	## Carrying the chunk, declaring a marker and carrying a marker that is
	## actually inside the audio are three different facts, and only the last
	## would owe the port anything.
	var cue_files := 0
	var cue_markers := 0
	var cue_usable := 0
	var cue_examples: Array[String] = []
	var failures: Array[String] = []
	var started := Time.get_ticks_usec()
	var bytes := 0

	h.begin("every sound decodes to a playable stream")
	for path in files:
		var raw := FileAccess.get_file_as_bytes(path)
		if raw.is_empty():
			# One file in this game is genuinely 0 bytes in the original.
			empty += 1
			continue
		bytes += raw.size()
		var error: Array = []
		var stream: AudioStreamWAV = Aiff.load_from_buffer(raw, error)
		if stream == null:
			failures.append("%s: %s" % [path.get_file(), "; ".join(error)])
			continue
		if stream.data.is_empty():
			failures.append("%s: decoded to no samples" % path.get_file())
			continue
		decoded += 1
		rates[stream.mix_rate] = int(rates.get(stream.mix_rate, 0)) + 1
		formats[stream.format] = int(formats.get(stream.format, 0)) + 1
		for tag in Aiff.chunk_sizes(raw):
			chunks[tag] = int(chunks.get(tag, 0)) + 1
		var cues: Array = Aiff.cue_points(raw)
		if cues.is_empty():
			continue
		cue_files += 1
		# The file's own length in sample frames, from what actually decoded. A
		# marker past the end cannot be reached, so it is not a cue point however
		# the chunk is spelt.
		var frame_bytes := (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (
			2 if stream.stereo else 1)
		var sample_frames := stream.data.size() / maxi(frame_bytes, 1)
		for cue in cues:
			cue_markers += 1
			if int((cue as Dictionary)["frame"]) < sample_frames:
				cue_usable += 1
				if cue_examples.size() < 8:
					cue_examples.append("%s: %s of %d frames" % [
						path.get_file(), JSON.stringify(cue), sample_frames,
					])
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0

	h.check("%d of %d sound(s) decoded" % [decoded, files.size() - empty],
		failures.is_empty(), "" if failures.is_empty() else "%d failed" % failures.size())
	for line in failures.slice(0, 12):
		print("     %s" % line)
	if failures.size() > 12:
		print("     ... and %d more" % (failures.size() - 12))
	h.check("the game ships sounds at all", files.size() > 0, "%d file(s)" % files.size())
	var unknown: Array = []
	for rate in rates:
		if not KNOWN_RATES.has(int(rate)):
			unknown.append(rate)
	h.check("every sample rate is one the survey saw", unknown.is_empty(), str(unknown))
	# Cue points are a whole subsystem — `cuePassed`, the wait-for-cue tempo
	# values, `the cuePointNames of member` — and this is what decides whether
	# any of it is owed here. 168 of these files *do* carry a `MARK` chunk and
	# every one declares two markers, so "no MARK chunk" would have been the
	# wrong thing to assert and the right-looking answer for the wrong reason.
	# What is true is that none of the 336 markers sits inside its own audio:
	# they are eleven repeated byte patterns with empty names at positions
	# 0x53540000 and 0x007f007f, the same in file after file, which is authoring
	# residue and not something a movie can wait on. Asserted rather than printed
	# because it is the premise the cue-point row of §12 rests on — the day a
	# title ships genuinely marked audio, this says so.
	h.check("no sound carries a cue point inside its own audio", cue_usable == 0,
		"%d marker(s) in %d file(s), %d reachable" % [cue_markers, cue_files, cue_usable])
	for line in cue_examples:
		print("     %s" % line)
	h.complete("every sound decodes to a playable stream")

	print("")
	print("files      : %d  (%d empty in the original)" % [files.size(), empty])
	print("decoded    : %d  (%.1f MB)" % [decoded, bytes / 1048576.0])
	print("elapsed    : %.0f ms  (%.2f ms/file)" % [elapsed, elapsed / maxi(decoded, 1)])
	print("rates      :")
	var rate_keys := rates.keys()
	rate_keys.sort()
	for rate in rate_keys:
		print("  %8d  %d Hz" % [int(rates[rate]), int(rate)])
	print("formats    :")
	for f in formats:
		print("  %8d  %s" % [int(formats[f]), "8-bit" if int(f) == 0 else "16-bit"])
	print("chunks     :  (files carrying each)")
	var chunk_keys := chunks.keys()
	chunk_keys.sort()
	for tag in chunk_keys:
		print("  %8d  %s" % [int(chunks[tag]), str(tag)])

	quit(h.finish("the game's own sounds are loadable"))


func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if entry.get_extension().to_lower() == "aif":
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
