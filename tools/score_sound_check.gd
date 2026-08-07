extends SceneTree
## The sound machinery this corpus cannot exercise, driven directly.
##
##   godot --headless --script tools/score_sound_check.gd
##
## Four Director features live here that the game this port was built on never
## reaches — the score's own sound channels, sound cast members, cue points and
## fades — and `tools/sound_survey.gd` and `tools/aiff_check.gd` are what
## establish that it never reaches them:
##
##   - its 86 containers hold 15,297 cast members and **none of type `sound`**;
##   - neither score sound channel is written in any of its 61,371 frames;
##   - no frame's tempo cell is a wait-for-sound;
##   - none of its 3,349 scripts writes `puppetSound`, `sound fadeIn`,
##     `sound fadeOut`, `sound close` or `cuePassed`;
##   - 168 of its 3,141 sounds carry a `MARK` chunk and not one of the 336
##     markers in them lies inside its own audio.
##
## A measured zero is a reason to build something *last*, not a reason to leave a
## hole in a general Director engine — so the features are built, and this is
## what keeps them honest. Every fixture below is **synthesised**: a byte buffer
## assembled here to the published format, or a channel record handed straight to
## the state machine. That proves the implementation and says nothing about the
## corpus, which is exactly the claim being made.
##
## What this cannot prove, and no harness can until a title ships score sound:
## which of the two 48-byte main-channel records is sound channel 1. They are
## taken in address order. See `director/director_score.gd:_sound_channels`.

const Harness := preload("res://tools/lib/harness.gd")
const ScoreSound := preload("res://director/score_sound.gd")
const SoundMember := preload("res://director/director_sound.gd")
const Aiff := preload("res://autoload/aiff_loader.gd")

## Frames of silence in a synthesised sound, and the rate it claims. One second
## at 22050 Hz, so a cue at frame 1000 lands 45 ms in and is reachable in real
## time without the case taking noticeably long.
const FIXTURE_RATE := 22050
const FIXTURE_FRAMES := 22050


func _initialize() -> void:
	var h := Harness.new()
	_restart_on_change(h)
	_puppet_ownership(h)
	_snd_resource(h)
	_embedded_aiff_and_wav(h)
	var audio := root.get_node_or_null("AudioDirector")
	if audio == null:
		print("AudioDirector autoload is not present")
		quit(1)
		return
	await process_frame
	await _cue_points(h, audio)
	await _fades(h, audio)
	quit(h.finish("the sound features this corpus never reaches"))


# ------------------------------------------------------- restart-on-change

## §12's rule, which is the whole reason the score's sound channels are not just
## "play what the frame says": a frame naming the same member as the one before
## must not restart it, and a frame naming a different one must.
func _restart_on_change(h: Harness) -> void:
	var title := "a score sound channel restarts only when its member changes"
	h.begin(title)
	var state := ScoreSound.new()

	var first := state.changes([_cell(1, 1, 20)])
	h.check("the first frame that names a member starts it",
		first["start"].size() == 1 and int((first["start"][0] as Dictionary)["cast_id"]) == 20,
		JSON.stringify(first))

	var same := state.changes([_cell(1, 1, 20)])
	h.check("naming the same member again changes nothing",
		same["start"].is_empty() and same["stop"].is_empty(), JSON.stringify(same))

	var changed := state.changes([_cell(1, 1, 21)])
	h.check("naming a different member restarts the channel",
		changed["start"].size() == 1 and int((changed["start"][0] as Dictionary)["cast_id"]) == 21,
		JSON.stringify(changed))

	# The same member *number* in a different library is a different member, and
	# a comparison on the number alone would call this "no change" and play the
	# wrong sound — the same trap `frame_script_lib` exists to prevent.
	var other_lib := state.changes([_cell(1, 3, 21)])
	h.check("the same number in another library is a change",
		other_lib["start"].size() == 1, JSON.stringify(other_lib))

	var silent := state.changes([])
	h.check("a frame that names nothing silences the channel",
		silent["stop"] == [1] and silent["start"].is_empty(), JSON.stringify(silent))

	# And after the stop the channel is forgotten, so the member that was playing
	# before plays again rather than being suppressed as unchanged.
	var again := state.changes([_cell(1, 3, 21)])
	h.check("the same member after a silence starts again",
		again["start"].size() == 1, JSON.stringify(again))

	var both := state.changes([_cell(1, 1, 5), _cell(2, 1, 6)])
	h.check("the two channels are independent", both["start"].size() == 2,
		JSON.stringify(both))

	state.reset()
	var after_reset := state.changes([_cell(1, 1, 5), _cell(2, 1, 6)])
	h.check("a movie change forgets what the channels held",
		after_reset["start"].size() == 2, JSON.stringify(after_reset))
	h.complete(title)


## `puppetSound` takes a channel off the score, and the score does not get it
## back until the script releases it. The asymmetry is the part worth asserting:
## releasing does not restore what the score had, it forgets it, so the next
## frame that names a member counts as a change and plays.
func _puppet_ownership(h: Harness) -> void:
	var title := "a puppeted sound channel is not the score's to drive"
	h.begin(title)
	var state := ScoreSound.new()
	state.changes([_cell(1, 1, 10)])

	state.set_puppet(1, true)
	var while_claimed := state.changes([_cell(1, 1, 11)])
	h.check("the score cannot start a sound on a claimed channel",
		while_claimed["start"].is_empty(), JSON.stringify(while_claimed))
	var claimed_silent := state.changes([])
	h.check("nor silence one", claimed_silent["stop"].is_empty(),
		JSON.stringify(claimed_silent))
	h.check("and it reports itself claimed", state.is_puppeted(1))

	state.set_puppet(1, false)
	var released := state.changes([_cell(1, 1, 11)])
	h.check("once released the next frame's member plays",
		released["start"].size() == 1, JSON.stringify(released))
	h.check("the other channel was never claimed", not state.is_puppeted(2))
	h.complete(title)


func _cell(channel: int, cast_lib: int, cast_id: int) -> Dictionary:
	return {"channel": channel, "cast_lib": cast_lib, "cast_id": cast_id}


# ------------------------------------------------------- sound cast members

## A Mac `snd ` resource, which is what a sound cast member holds in a movie
## authored on the platform Director came from. Synthesised to the published
## layout: a format-1 header, one synthesiser, and a `bufferCmd` whose second
## parameter is the offset of the sound header inside the resource.
func _snd_resource(h: Harness) -> void:
	var title := "a `snd ` sound cast member decodes, with its samples the right way up"
	h.begin(title)
	# 0x00, 0x80 and 0xff are the three points that matter: the bottom of the
	# range, the midpoint, and the top. Unsigned in a `snd `, signed in an
	# `AudioStreamWAV`, so they must come out as 0x80, 0x00 and 0x7f.
	var samples := PackedByteArray([0x00, 0x80, 0xFF, 0x40])
	var error: Array = []
	var stream := SoundMember.decode(_snd_bytes(samples), PackedByteArray(), error)
	if not h.check("it decodes", stream != null, "; ".join(error)):
		h.complete(title)
		return
	h.check("at the rate the header claims", stream.mix_rate == FIXTURE_RATE,
		"%d Hz" % stream.mix_rate)
	h.check("as 8-bit mono", stream.format == AudioStreamWAV.FORMAT_8_BITS and not stream.stereo)
	h.check("with unsigned samples converted to signed",
		stream.data == PackedByteArray([0x80, 0x00, 0x7F, 0xC0]),
		str(Array(stream.data)))

	# A compressed resource is refused rather than decoded as though it were PCM,
	# which is the same call `aiff_loader.gd` makes about AIFF-C. Playing MACE
	# bytes as samples is not quiet failure, it is loud noise.
	var compressed := _snd_bytes(samples)
	compressed[20 + 20] = 0xFE
	var refused: Array = []
	h.check("a MACE-compressed resource is refused, not played as noise",
		SoundMember.decode(compressed, PackedByteArray(), refused) == null,
		"; ".join(refused))
	h.complete(title)


## The other two shapes a sound member can hold: a whole AIFF or a whole WAV
## embedded in the member. Sniffed by their container tag rather than selected by
## Director version, because which one a movie uses is a fact about the tool that
## authored it.
func _embedded_aiff_and_wav(h: Harness) -> void:
	var title := "an embedded AIFF or WAV sound member decodes too"
	h.begin(title)
	var aiff_error: Array = []
	var aiff := SoundMember.decode(_aiff_bytes([]), PackedByteArray(), aiff_error)
	h.check("an embedded AIFF decodes", aiff != null and aiff.mix_rate == FIXTURE_RATE,
		"; ".join(aiff_error))

	var wav_error: Array = []
	var wav := SoundMember.decode(_wav_bytes(), PackedByteArray(), wav_error)
	h.check("an embedded WAV decodes", wav != null and wav.mix_rate == FIXTURE_RATE,
		"; ".join(wav_error))
	# 8-bit WAV is unsigned like `snd ` and unlike AIFF, which is the trap that
	# runs the other way from the one in `aiff_loader.gd`.
	h.check("its 8-bit samples are converted from unsigned",
		wav != null and wav.data.slice(0, 3) == PackedByteArray([0x80, 0x00, 0x7F]),
		str(Array(wav.data.slice(0, 3))) if wav != null else "-")

	var junk: Array = []
	h.check("bytes that are no sound at all are refused",
		SoundMember.decode(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]), PackedByteArray(),
			junk) == null, "; ".join(junk))
	h.complete(title)


# ------------------------------------------------------- cue points

## Cue points, end to end: parsed out of a `MARK` chunk, attached to the channel
## they are played on, and reported once each as the audio playhead crosses them.
##
## Real time, and awaited rather than ticked, for the reason `tools/lib/driver.gd`
## records: the audio server's clock is the only thing that moves a playback
## position, and a synthetic loop advances everything except that.
func _cue_points(h: Harness, audio: Node) -> void:
	var title := "cue points are parsed, attached to a channel and reported once each"
	h.begin(title)
	var cues := Aiff.cue_points(_aiff_bytes([
		{"id": 1, "frame": 1000, "name": "start"},
		{"id": 2, "frame": 5000, "name": "mid"},
	]))
	if not h.check("both markers parse out of the MARK chunk", cues.size() == 2,
			JSON.stringify(cues)):
		h.complete(title)
		return
	h.check("with their names intact",
		str((cues[0] as Dictionary)["name"]) == "start"
			and str((cues[1] as Dictionary)["name"]) == "mid", JSON.stringify(cues))
	h.check("and their positions", int((cues[0] as Dictionary)["frame"]) == 1000
		and int((cues[1] as Dictionary)["frame"]) == 5000, JSON.stringify(cues))

	var stream := Aiff.load_from_buffer(_aiff_bytes([]))
	audio.play_stream(7, "fixture", stream, cues)
	await process_frame
	h.check("the channel carries the cue names",
		audio.cue_point_names(7) == ["start", "mid"], str(audio.cue_point_names(7)))

	# Both cues are inside the first quarter-second of a one-second sound, so
	# this collects them well before the stream ends.
	var seen: Array = []
	var started := Time.get_ticks_msec()
	while seen.size() < 2 and Time.get_ticks_msec() - started < 3000:
		for cue in audio.take_cues_passed(7):
			seen.append(cue)
		await process_frame
	h.check("both are reported as the playhead crosses them", seen.size() == 2,
		JSON.stringify(seen))
	if seen.size() == 2:
		h.check("numbered from 1, in order",
			int((seen[0] as Dictionary)["index"]) == 1
				and int((seen[1] as Dictionary)["index"]) == 2, JSON.stringify(seen))
	# Destructive on purpose: a cue reported twice would fire `cuePassed` twice
	# and release a wait that had already been released.
	h.check("and not reported again", audio.take_cues_passed(7).is_empty())
	h.check("the channel reports its cues exhausted", audio.cues_exhausted(7))
	audio.stop_channel(7)
	h.complete(title)


# ------------------------------------------------------- fades

## `sound fadeOut` has to *stop* the channel at the bottom of the ramp, not just
## turn it down. That is the half a script can observe: a `soundBusy` wait behind
## a fade-out is released by the stop and by nothing else.
func _fades(h: Harness, audio: Node) -> void:
	var title := "a fade ramps the channel and a fade-out ends it"
	h.begin(title)
	var stream := Aiff.load_from_buffer(_aiff_bytes([]))
	audio.set_channel_volume(8, 255)
	audio.play_stream(8, "fixture", stream)
	await process_frame
	if not h.check("the fixture is playing", audio.sound_busy(8)):
		h.complete(title)
		return

	# 30 ticks is half a second, comfortably inside the one-second fixture, so
	# the channel stopping is the fade's doing and not the sound running out.
	audio.fade_out(8, 30)
	h.check("the fade is running", audio.fading(8))
	var player: AudioStreamPlayer = audio.call("_ensure_player", 8)
	var loudest := player.volume_db
	var started := Time.get_ticks_msec()
	while audio.fading(8) and Time.get_ticks_msec() - started < 2000:
		await process_frame
	var elapsed := Time.get_ticks_msec() - started
	h.check("it got quieter on the way down", player.volume_db < loudest,
		"%.1f dB -> %.1f dB" % [loudest, player.volume_db])
	h.check("it took about the ticks it was given", elapsed > 300 and elapsed < 1200,
		"%d ms for 30 ticks" % elapsed)
	h.check("and the channel is no longer busy", not audio.sound_busy(8),
		"a `soundBusy` wait behind this would never release otherwise")

	# The volume *property* is untouched: Director fades the output, which is why
	# `set the volume of sound N` cancels a fade rather than losing to it.
	h.check("the channel's volume property is where the script left it",
		audio.channel_volume(8) == 255, "%d" % audio.channel_volume(8))

	audio.play_stream(8, "fixture", stream)
	await process_frame
	audio.fade_out(8, 600)
	audio.set_channel_volume(8, 200)
	h.check("a volume write cancels a running fade", not audio.fading(8))
	audio.stop_channel(8)
	audio.set_channel_volume(8, 255)
	h.complete(title)


# ------------------------------------------------------- fixtures

## A format-1 `snd ` resource wrapping `samples`, with one synthesiser and a
## single `bufferCmd` pointing at the sound header.
func _snd_bytes(samples: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	_be16(out, 1)          # format
	_be16(out, 1)          # one synthesiser
	_be16(out, 5)          # synth id (sampledSynth)
	_be32(out, 0)          # its init parameter
	_be16(out, 1)          # one command
	_be16(out, 0x8051)     # bufferCmd, with the data-offset bit set
	_be16(out, 0)          # param1
	_be32(out, 20)         # param2: where the sound header starts
	# The sound header, at offset 20.
	_be32(out, 0)                    # samplePtr
	_be32(out, samples.size())       # length, in sample frames
	_be32(out, FIXTURE_RATE << 16)   # rate, 16.16 fixed point
	_be32(out, 0)                    # loopStart
	_be32(out, 0)                    # loopEnd
	out.append(0x00)                 # encode: standard
	out.append(60)                   # baseFrequency
	out.append_array(samples)
	return out


## An AIFF of `FIXTURE_FRAMES` silent 8-bit samples, with `marks` as its `MARK`
## chunk. Assembled rather than loaded from the game, because the point is a file
## carrying markers and the game ships none that do.
func _aiff_bytes(marks: Array) -> PackedByteArray:
	var comm := PackedByteArray()
	_be16(comm, 1)                 # channels
	_be32(comm, FIXTURE_FRAMES)    # sample frames
	_be16(comm, 8)                 # sample size
	# 22050 as an 80-bit IEEE extended: exponent 0x400D and a mantissa whose top
	# 32 bits are 22050 << 17.
	comm.append_array(PackedByteArray([0x40, 0x0D, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]))

	var mark := PackedByteArray()
	_be16(mark, marks.size())
	for entry in marks:
		var m: Dictionary = entry
		_be16(mark, int(m["id"]))
		_be32(mark, int(m["frame"]))
		var name := str(m["name"])
		mark.append(name.length())
		mark.append_array(name.to_ascii_buffer())
		# Every marker record is padded to an even length, and the name's own
		# length byte counts towards it.
		if (name.length() + 1) % 2 == 1:
			mark.append(0)

	var ssnd := PackedByteArray()
	_be32(ssnd, 0)   # offset
	_be32(ssnd, 0)   # blockSize
	var silence := PackedByteArray()
	silence.resize(FIXTURE_FRAMES)
	ssnd.append_array(silence)

	var body := PackedByteArray()
	body.append_array("AIFF".to_ascii_buffer())
	_chunk(body, "COMM", comm)
	if not marks.is_empty():
		_chunk(body, "MARK", mark)
	_chunk(body, "SSND", ssnd)

	var out := PackedByteArray()
	out.append_array("FORM".to_ascii_buffer())
	_be32(out, body.size())
	out.append_array(body)
	return out


## A RIFF/WAVE of the same shape, 8-bit unsigned.
func _wav_bytes() -> PackedByteArray:
	var fmt := PackedByteArray()
	_le16(fmt, 1)                  # PCM
	_le16(fmt, 1)                  # mono
	_le32(fmt, FIXTURE_RATE)
	_le32(fmt, FIXTURE_RATE)       # byte rate
	_le16(fmt, 1)                  # block align
	_le16(fmt, 8)                  # bits per sample

	var data := PackedByteArray([0x00, 0x80, 0xFF, 0x40])
	var body := PackedByteArray()
	body.append_array("WAVE".to_ascii_buffer())
	_le_chunk(body, "fmt ", fmt)
	_le_chunk(body, "data", data)

	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	_le32(out, body.size())
	out.append_array(body)
	return out


func _chunk(into: PackedByteArray, tag: String, body: PackedByteArray) -> void:
	into.append_array(tag.to_ascii_buffer())
	_be32(into, body.size())
	into.append_array(body)
	if body.size() % 2 == 1:
		into.append(0)


func _le_chunk(into: PackedByteArray, tag: String, body: PackedByteArray) -> void:
	into.append_array(tag.to_ascii_buffer())
	_le32(into, body.size())
	into.append_array(body)
	if body.size() % 2 == 1:
		into.append(0)


func _be16(into: PackedByteArray, value: int) -> void:
	into.append((value >> 8) & 0xFF)
	into.append(value & 0xFF)


func _be32(into: PackedByteArray, value: int) -> void:
	into.append((value >> 24) & 0xFF)
	into.append((value >> 16) & 0xFF)
	into.append((value >> 8) & 0xFF)
	into.append(value & 0xFF)


func _le16(into: PackedByteArray, value: int) -> void:
	into.append(value & 0xFF)
	into.append((value >> 8) & 0xFF)


func _le32(into: PackedByteArray, value: int) -> void:
	into.append(value & 0xFF)
	into.append((value >> 8) & 0xFF)
	into.append((value >> 16) & 0xFF)
	into.append((value >> 24) & 0xFF)
