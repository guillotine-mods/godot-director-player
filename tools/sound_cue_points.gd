extends SceneTree
## A sound member's cue points come out of its `cupt` chunk.
##
##   godot --headless --audio-driver Dummy --path . --script tools/sound_cue_points.gd
##   godot --headless --audio-driver Dummy --path . --script tools/sound_cue_points.gd -- --roots res://games/rating
##
## Director 6 does not put a sound member's cue points in its audio. It writes
## them to a **separate `cupt` child chunk of the member** — an `int32` count,
## then per cue an `int32` position and a fixed 32-byte name — and
## `castmember/sound.cpp:SoundCastMember::load()` reads that arm in the same walk
## as `sndH`, `sndS`, `snd ` and `ediM`.
##
## **`director_sound.gd:cue_points` read markers out of an embedded AIFF and
## nothing else.** That is the one shape of the four that can carry them inline,
## and it is not the shape Director writes — so `the cuePointNames`, `the
## cuePointTimes`, the `cuePassed` event and a tempo cell waiting on a cue index
## all answered nothing for every member authored the ordinary way. Three
## surfaces, one unread chunk.
##
## ## What this asserts and what it cannot
##
## **No container in reach holds a `cupt` chunk** — 0 across 651 containers in
## eight roots (`tools/scratch/sndprobe.gd`), and the AIFF arm beside it is no
## better off, because all 336 markers in the corpus's 168 marked AIFFs sit past
## the end of their own file (`tools/aiff_check.gd`). So this proves the decoder
## against bytes laid out from the reference, and it says so rather than implying
## a corpus check. That is the honest state for a feature Director has and this
## corpus does not exercise, and it is not the same as absent.
##
## What is *not* synthesised is the second half: the cues the decoder produces are
## pushed through the real `AudioDirector` channel machinery and read back through
## the same calls `preview/sound.gd:pump` and `the cuePointNames of sound` use, so
## the record shape the decoder emits and the record shape the player consumes
## cannot drift apart. That drift is the actual defect this file guards: the AIFF
## arm has always emitted `{id, frame, name}` and `preview/media.gd` has always
## read `cue["ms"]`, so **`the cuePointTimes` answered 0 for every cue it had**,
## silently, for as long as both existed.
##
## The corpus half runs anyway and reports what it finds, so the day a title with
## cue points arrives this stops being a synthetic-only harness without anyone
## editing it.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const SoundMember := preload("res://director/director_sound.gd")
const AiffLoader := preload("res://autoload/aiff_loader.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]
## A spare channel, so nothing here can be reading a sound the booted movie
## started. `tools/sound_wait.gd` reserves one the same way.
const SPARE := 8
const RATE := 22050


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if audio == null:
		print("no AudioDirector autoload")
		quit(1)
		return

	# ------------------------------------------------------------- the `cupt` read
	h.begin("a `cupt` chunk decodes to the cues it names")
	var chunk := _cupt([
		[0, "start"], [1500, "middle"], [4000, "end of the line"],
	])
	var cues: Array = SoundMember.decode_cue_chunk(chunk, RATE)
	h.check("all three cues come back", cues.size() == 3, "%d came back" % cues.size())
	h.check("in the order the chunk states them",
		_names(cues) == ["start", "middle", "end of the line"], str(_names(cues)))
	h.check("numbered from 1, the way `cuePassed`'s cueNumber counts",
		cues.size() == 3 and int((cues[0] as Dictionary)["index"]) == 1
			and int((cues[2] as Dictionary)["index"]) == 3, str(_indices(cues)))
	h.check("with the position the chunk carries, in milliseconds",
		cues.size() == 3 and float((cues[1] as Dictionary)["ms"]) == 1500.0,
		str(_times(cues)))
	# The conversion is the whole reason the rate is a parameter: the property
	# surface counts time and the playback clock counts sample frames, and
	# whichever end does not convert answers 0 for every cue it has.
	h.check("and the sample frame that position is at the member's rate",
		cues.size() == 3 and int((cues[1] as Dictionary)["frame"]) == int(1.5 * RATE),
		str(_frames(cues)))
	h.check("with no rate the time survives and the frame is 0 rather than a guess",
		_frame_of(SoundMember.decode_cue_chunk(chunk), 1) == 0
			and _time_of(SoundMember.decode_cue_chunk(chunk), 1) == 1500.0,
		str(SoundMember.decode_cue_chunk(chunk)))
	h.complete("a `cupt` chunk decodes to the cues it names")

	# --------------------------------------------------------------- the edges
	h.begin("a malformed or empty `cupt` is a fact about the movie, not an error")
	h.check("a count of zero decodes to no cues",
		SoundMember.decode_cue_chunk(_cupt([])).is_empty(),
		str(SoundMember.decode_cue_chunk(_cupt([]))))
	h.check("an empty chunk decodes to no cues",
		SoundMember.decode_cue_chunk(PackedByteArray()).is_empty(), "")
	# Truncation rather than refusal: a half-written cue list is still worth the
	# cues it does hold, and no caller can do anything with a refusal.
	var short := _cupt([[10, "a"], [20, "b"], [30, "c"]]).slice(0, 4 + 36 + 20)
	h.check("a chunk that ends mid-cue keeps the whole cues it holds",
		SoundMember.decode_cue_chunk(short, RATE).size() == 1,
		"%d from %d bytes" % [SoundMember.decode_cue_chunk(short, RATE).size(), short.size()])
	# The reference reads 32 bytes and NUL-terminates at byte 31, so a name that
	# fills the field has no terminator in the file. Stopping at the first NUL is
	# the same answer for every shorter name and the reference's answer for this one.
	var full := "".rpad(32, "x")
	h.check("a name that fills all 32 bytes is not truncated by a terminator",
		_name_of(SoundMember.decode_cue_chunk(_cupt([[0, full]]), RATE), 0) == full,
		_name_of(SoundMember.decode_cue_chunk(_cupt([[0, full]]), RATE), 0))
	h.complete("a malformed or empty `cupt` is a fact about the movie, not an error")

	# ------------------------------------------------------- which source wins
	h.begin("the member's own chunk beats markers inside the audio")
	var aiff := _aiff_with_marker(9999, "inline")
	var inline: Array = SoundMember.cue_points(aiff, PackedByteArray(), RATE)
	h.check("an embedded AIFF's markers are still read when there is no `cupt`",
		_names(inline) == ["inline"], str(_names(inline)))
	# The AIFF arm states a sample frame and says nothing about time. That gap is
	# what `the cuePointTimes` was reading, and it read 0.
	h.check("and they now carry a time as well as a frame",
		_time_of(inline, 0) == 9999.0 * 1000.0 / float(RATE)
			and _frame_of(inline, 0) == 9999,
		"%s" % str(inline))
	var both: Array = SoundMember.cue_points(aiff, chunk, RATE)
	h.check("with both present the member's chunk is what answers",
		_names(both) == ["start", "middle", "end of the line"], str(_names(both)))
	h.complete("the member's own chunk beats markers inside the audio")

	# ------------------------------------------- the shape the player consumes
	h.begin("the cues the decoder emits are the cues the player reads back")
	audio.call("stop_channel", SPARE)
	audio.call("play_stream", SPARE, "3:9", _silence(2.0), cues)
	h.check("`the cuePointNames of sound` answers the member's names",
		Array(audio.call("cue_point_names", SPARE))
			== ["start", "middle", "end of the line"],
		str(audio.call("cue_point_names", SPARE)))
	# The channel is polled for cues at all only because something was played on
	# it -- `cue_channels` asks rather than assuming a count -- and `pump` walks
	# exactly that list. A cue record the channel machinery cannot key on would
	# show up here as a channel that is never polled.
	h.check("and the channel is one `preview/sound.gd:pump` will poll",
		Array(audio.call("cue_channels")).has(SPARE),
		str(audio.call("cue_channels")))
	# The first cue is at frame 0, so it is passed the moment the sound starts:
	# `take_cues_passed` compares the cue's frame against the player's position,
	# which is the field the decoder has to have filled for any of this to fire.
	var passed: Array = audio.call("take_cues_passed", SPARE)
	h.check("the cue at frame 0 is reported as soon as the sound is playing",
		passed.size() >= 1 and str((passed[0] as Dictionary)["name"]) == "start"
			and int((passed[0] as Dictionary)["index"]) == 1,
		str(passed))
	# Destructive by design (`preview/sound.gd`'s header): reporting a cue twice
	# would fire `cuePassed` twice and release a wait that was looking for the next
	# one.
	h.check("and it is not reported a second time",
		_named(audio.call("take_cues_passed", SPARE), "start") == 0,
		str(audio.call("take_cues_passed", SPARE)))
	audio.call("stop_channel", SPARE)
	h.complete("the cues the decoder emits are the cues the player reads back")

	# ------------------------------------------------------------- the corpus
	var roots: Array[String] = []
	var explicit := Args.text(args, "roots", "")
	if explicit != "":
		for part in explicit.split(",", false):
			roots.append(str(part).strip_edges())
	else:
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	roots.sort()
	var found := _sweep(roots)
	print("")
	print("%d container(s) over %d root(s); `cupt` chunks: %d, cues in them: %d"
		% [int(found["containers"]), roots.size(), int(found["chunks"]),
			int(found["cues"])])
	for line in (found["where"] as Array).slice(0, 12):
		print("  %s" % line)
	h.begin("every `cupt` the corpus does hold decodes")
	if int(found["chunks"]) == 0:
		# Said out loud rather than asserted over. Director has this feature; these
		# eight roots do not use it, and a check over an empty set reads exactly
		# like a clean pass in the gate's one-line table.
		print("no root in reach ships a `cupt` chunk; the decode above is all that is proved.")
		h.check("the sweep opened a container at all", int(found["containers"]) >= 1,
			"0 containers under %s" % str(roots))
	else:
		h.check("every one of them yields at least one cue",
			int(found["empty"]) == 0,
			"%d of %d decoded to nothing" % [int(found["empty"]), int(found["chunks"])])
	h.complete("every `cupt` the corpus does hold decodes")

	quit(h.finish("cue points out of a sound member's `cupt` chunk"))


# ------------------------------------------------------------------- fixtures

## One `cupt` chunk: an `int32` count, then per cue an `int32` position and a
## fixed 32-byte name. Laid out from `castmember/sound.cpp:load()`'s own read.
func _cupt(entries: Array) -> PackedByteArray:
	var out := PackedByteArray()
	_push_be_i32(out, entries.size())
	for entry in entries:
		_push_be_i32(out, int((entry as Array)[0]))
		var name := str((entry as Array)[1]).to_ascii_buffer()
		for i in SoundMember.CUE_NAME_BYTES:
			out.append(name[i] if i < name.size() else 0)
	return out


## The smallest AIFF that carries one marker: `FORM`/`AIFF` with a `COMM`, an
## `SSND` and a `MARK`. Only the marker is read by the arm under test, but the
## rest has to be there or `cue_points` never gets past the tag.
func _aiff_with_marker(frame: int, name: String) -> PackedByteArray:
	var mark := PackedByteArray()
	_push_be_u16(mark, 1)
	_push_be_u16(mark, 1)
	_push_be_i32(mark, frame)
	mark.append(name.length())
	mark.append_array(name.to_ascii_buffer())
	if (name.length() + 1) % 2 == 1:
		mark.append(0)

	var comm := PackedByteArray()
	_push_be_u16(comm, 1)
	_push_be_i32(comm, 100)
	_push_be_u16(comm, 8)
	comm.append_array(_extended(RATE))

	var ssnd := PackedByteArray()
	_push_be_i32(ssnd, 0)
	_push_be_i32(ssnd, 0)
	for _i in 100:
		ssnd.append(0x80)

	var body := PackedByteArray()
	body.append_array("AIFF".to_ascii_buffer())
	_push_chunk(body, "COMM", comm)
	_push_chunk(body, "SSND", ssnd)
	_push_chunk(body, "MARK", mark)

	var out := PackedByteArray()
	out.append_array("FORM".to_ascii_buffer())
	_push_be_i32(out, body.size())
	out.append_array(body)
	return out


## Two seconds of nothing to hang the cues on. The cue positions are what is being
## read back, not the audio, so the samples only have to exist and state a length.
func _silence(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = RATE
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	var data := PackedByteArray()
	data.resize(int(RATE * seconds))
	stream.data = data
	return stream


## The 80-bit IEEE 754 extended a `COMM` states its rate as.
func _extended(rate: int) -> PackedByteArray:
	var out := PackedByteArray()
	var exponent := 16383 + 31
	var mantissa := rate
	while mantissa != 0 and (mantissa & 0x80000000) == 0:
		mantissa <<= 1
		exponent -= 1
	_push_be_u16(out, exponent)
	for shift in [24, 16, 8, 0]:
		out.append((mantissa >> shift) & 0xFF)
	for _i in 4:
		out.append(0)
	return out


# --------------------------------------------------------------------- sweep

func _sweep(roots: Array[String]) -> Dictionary:
	var out := {"containers": 0, "chunks": 0, "cues": 0, "empty": 0, "where": []}
	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			out["containers"] = int(out["containers"]) + 1
			for id in f.ids_of("cupt"):
				out["chunks"] = int(out["chunks"]) + 1
				var cues: Array = SoundMember.decode_cue_chunk(f.read_chunk(int(id)))
				out["cues"] = int(out["cues"]) + cues.size()
				if cues.is_empty():
					out["empty"] = int(out["empty"]) + 1
				(out["where"] as Array).append("%s %s cupt %d -> %d cue(s) %s" % [
					str(root).get_file(), path.get_file(), int(id), cues.size(),
					str(_names(cues))])
			f.close()
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		var lower := str(name).to_lower()
		if lower.ends_with(".dir") or lower.ends_with(".cst") \
				or lower.ends_with(".dxr") or lower.ends_with(".cxt"):
			out.append(dir_path.path_join(name))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


# --------------------------------------------------------------------- bytes

func _names(cues: Array) -> Array:
	var out: Array = []
	for cue in cues:
		out.append(str((cue as Dictionary).get("name", "")))
	return out


func _indices(cues: Array) -> Array:
	var out: Array = []
	for cue in cues:
		out.append(int((cue as Dictionary).get("index", 0)))
	return out


func _times(cues: Array) -> Array:
	var out: Array = []
	for cue in cues:
		out.append(float((cue as Dictionary).get("ms", -1.0)))
	return out


func _frames(cues: Array) -> Array:
	var out: Array = []
	for cue in cues:
		out.append(int((cue as Dictionary).get("frame", -1)))
	return out


func _name_of(cues: Array, at: int) -> String:
	return "" if at >= cues.size() else str((cues[at] as Dictionary).get("name", ""))


func _time_of(cues: Array, at: int) -> float:
	return -1.0 if at >= cues.size() else float((cues[at] as Dictionary).get("ms", -1.0))


func _frame_of(cues: Array, at: int) -> int:
	return -1 if at >= cues.size() else int((cues[at] as Dictionary).get("frame", -1))


func _named(cues: Array, name: String) -> int:
	var count := 0
	for cue in cues:
		if str((cue as Dictionary).get("name", "")) == name:
			count += 1
	return count


func _push_chunk(out: PackedByteArray, tag: String, body: PackedByteArray) -> void:
	out.append_array(tag.to_ascii_buffer())
	_push_be_i32(out, body.size())
	out.append_array(body)
	if body.size() % 2 == 1:
		out.append(0)


func _push_be_i32(out: PackedByteArray, value: int) -> void:
	for shift in [24, 16, 8, 0]:
		out.append((value >> shift) & 0xFF)


func _push_be_u16(out: PackedByteArray, value: int) -> void:
	out.append((value >> 8) & 0xFF)
	out.append(value & 0xFF)
