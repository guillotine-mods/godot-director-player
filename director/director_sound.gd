extends RefCounted
## A sound cast member's payload, decoded to an `AudioStreamWAV`.
##
## The score's two sound channels name cast members, and `puppetSound` names one
## by name — so a Director engine has to turn a member into something playable
## without going near a file on disk. `autoload/aiff_loader.gd` is the same job
## for the external files `sound playFile` names; this is the in-container half.
##
## Three shapes reach here, and which one a movie uses is a fact about how it was
## authored rather than about its Director version, so the payload is *sniffed*
## rather than selected by version:
##
##   - a whole `FORM…AIFF` or `RIFF…WAVE` file embedded in the member, which is
##     what a modern authoring tool writes. Handed straight to the file loaders.
##   - a Mac `snd ` resource, format 1 or 2, which is what Director 3 and 4 wrote
##     and what a Mac-authored movie still carries.
##   - the D4+ `sndH` header plus `sndS` samples pair, where the sample format
##     lives in a separate chunk from the samples.
##
## **The trap, and it is the mirror of the one in `aiff_loader.gd`: 8-bit Mac
## `snd ` samples are *unsigned* offset binary, and `AudioStreamWAV.FORMAT_8_BITS`
## is signed.** So these need the 0x80 flip that AIFF's do not. Getting it wrong
## does not fail — it plays, at full volume, as loud symmetrical distortion.
##
## **This used to say "none of this is verified against the corpus", and the
## sentence was a measurement of Piposh 2 written as a fact about eight roots.**
## Piposh 2 has no sound cast member in any of its 86 containers; the corpus has
## **204** (`tools/member_type_census.gd`), and
## `tools/sound_member_census.gd` decodes every one the cast walk can address --
## 102 embedded, all 102 decoding, across 7 sample rates and both sample widths.
## The `sndS` arm is measured. The `snd ` resource and the embedded RIFF/AIFF arms
## still are not: no member in any root comes in under either tag, so those two
## are implemented from their published definitions and exercised against
## synthesised payloads only, which proves the decoder and not the corpus.
##
## A fourth shape exists and is **not** implemented: `ediM`, a whole compressed
## stream (`castmember/sound.cpp:load()` opens it only for `kMoaCfFormat_AIFF`).
## Zero members in reach carry one.

const AiffLoader := preload("res://autoload/aiff_loader.gd")

## `bufferCmd` in a `snd ` command list, with the data-offset bit set. The low 15
## bits are the command; 0x8000 means "param2 is an offset into this resource"
## rather than a pointer, which is the only form that survives being written to
## a file.
const BUFFER_CMD := 0x51
const DATA_OFFSET_FLAG := 0x8000
## Encoding byte of a `snd ` sound header.
const ENCODE_STANDARD := 0x00
const ENCODE_COMPRESSED := 0xFE
const ENCODE_EXTENDED := 0xFF
## Mac 8-bit samples are unsigned; this is the offset to signed.
const UNSIGNED_TO_SIGNED := 0x80
## The name field of one `cupt` entry: a fixed 32 bytes, whatever the name is.
const CUE_NAME_BYTES := 32


## `null` when the bytes are not a sound this can read, with the reason appended
## to `error`. A member that will not decode is a fact about the movie; callers
## report it and carry on, the same contract `AiffLoader.load_from_buffer` has.
##
## `header` is the `sndH` chunk where the member has one, and is ignored for
## every other shape.
static func decode(data: PackedByteArray, header: PackedByteArray = PackedByteArray(),
		error: Array = []) -> AudioStreamWAV:
	if data.size() < 4:
		error.append("sound payload is %d bytes" % data.size())
		return null
	var tag := data.slice(0, 4).get_string_from_ascii()
	if tag == "FORM":
		return AiffLoader.load_from_buffer(data, error)
	if tag == "RIFF":
		return _from_wav(data, error)
	if not header.is_empty():
		return _from_header_and_samples(header, data, error)
	return _from_snd_resource(data, error)


## Cue points, so a member-sourced sound answers `the cuePointNames of member`
## and fires `cuePassed` the same way a file-sourced one does.
##
## **Two sources, and for years this read only the weaker one.** An embedded AIFF
## can carry `MARK` inline, which is the shape `aiff_loader.gd` decodes; every
## other shape a sound member has — a `snd ` resource, the `sndH`/`sndS` pair, an
## `ediM` stream — carries no marker chunk at all, and Director 6 does not put
## them there in any case. It writes them to a **separate `cupt` child chunk of
## the member**, which `castmember/sound.cpp:SoundCastMember::load()` reads in the
## same walk as the audio (`MKTAG('c','u','p','t')`). Nothing here read that
## chunk, so `the cuePointNames`, `the cuePointTimes`, the `cuePassed` event and a
## tempo cell waiting on a cue index answered nothing for every member authored
## the ordinary way — which is every member with cue points that Director 6 wrote.
##
## `cue_chunk` is preferred over the inline markers when both are present: the
## member's own chunk is what the author edited in the Cast window, and an AIFF
## imported with markers already in it keeps them in the file whether or not
## Director still agrees with them.
##
## Every entry carries **three keys, deliberately redundant**, because the two
## consumers count in different units and neither should be converting:
##
##   - `frame` — the sample frame, which is what `AudioDirector.take_cues_passed`
##     compares against the player's own playback position;
##   - `ms` — milliseconds, which is what `the cuePointTimes` is derived from;
##   - `name` — the cue's name, for `the cuePointNames` and `cuePassed`.
##
## `mix_rate` is what converts between the two and is the decoded stream's rate.
## Passing 0 leaves whichever unit the source did not state at 0 rather than
## guessing a rate: a cue at the wrong sample frame fires at the wrong moment,
## which is worse than one that never fires at all.
##
## **Unverified against the corpus.** `tools/scratch/sndprobe.gd` finds **zero
## `cupt` chunks across all eight roots** — 651 containers, 204 sound members —
## so this arm is implemented from the reference and proved against synthesised
## bytes (`tools/sound_cue_points.gd`). That is the honest state and it is not the
## same as absent; the AIFF arm beside it is equally unexercised, because all 336
## markers in the corpus's 168 marked AIFFs sit past the end of their own file
## (`tools/aiff_check.gd`).
static func cue_points(data: PackedByteArray, cue_chunk: PackedByteArray = PackedByteArray(),
		mix_rate: int = 0) -> Array:
	if not cue_chunk.is_empty():
		return decode_cue_chunk(cue_chunk, mix_rate)
	if data.size() >= 4 and data.slice(0, 4).get_string_from_ascii() == "FORM":
		var out: Array = []
		for cue in AiffLoader.cue_points(data):
			var entry: Dictionary = cue
			# AIFF states the position as a sample frame and says nothing about
			# time, so the millisecond figure is derived here rather than in the
			# loader — `aiff_loader.gd` is also the `sound playFile` path and has no
			# business knowing what a Lingo property wants.
			var frame := int(entry.get("frame", 0))
			entry["ms"] = 0.0 if mix_rate <= 0 else float(frame) * 1000.0 / float(mix_rate)
			out.append(entry)
		return out
	return []


## Bytes of one `cupt` chunk to cue records.
##
## The layout is `castmember/sound.cpp:load()`'s own read, in its own order: an
## `int32` count, then per cue an `int32` position followed by a fixed **32-byte**
## name field which the reference NUL-terminates at byte 31 before taking it as a
## string. Fixed width, not a Pascal or C string with a length — a name that fills
## all 32 bytes has no terminator in the file and the reference supplies one, so a
## reader that stops at the first NUL and a reader that takes all 32 disagree only
## on the longest names. This stops at the first NUL and then strips, which is the
## same answer for every shorter name and the reference's answer for the longest.
##
## **The position is milliseconds.** The reference stores the `int32` unchanged
## and hands it to `the cuePointTimes` unchanged (`SoundCastMember::getField`,
## `kTheCuePointTimes`), so it does not name the unit; Director's own
## documentation does, and `the cuePointTimes` is a list of times in
## milliseconds. That is the one fact in this decoder that is neither measured nor
## quoted from the reference, and it is where to look first if a member's cues
## ever fire at the wrong moment.
##
## A count that does not fit the chunk truncates rather than refusing: a cue list
## the author half-wrote is still worth the cues it does hold, and there is no
## caller that can do anything with a refusal.
static func decode_cue_chunk(chunk: PackedByteArray, mix_rate: int = 0) -> Array:
	var out: Array = []
	if chunk.size() < 4:
		return out
	var count := _be_i32(chunk, 0)
	var at := 4
	for i in count:
		if at + 4 + CUE_NAME_BYTES > chunk.size():
			break
		var ms := _be_i32(chunk, at)
		var raw := chunk.slice(at + 4, at + 4 + CUE_NAME_BYTES)
		var stop := raw.find(0)
		if stop >= 0:
			raw = raw.slice(0, stop)
		out.append({
			# 1-based, the way `take_cues_passed` numbers what it reports and the
			# way `cuePassed`'s cueNumber counts.
			"index": i + 1,
			"ms": float(ms),
			"frame": 0 if mix_rate <= 0 else int(round(float(ms) * float(mix_rate) / 1000.0)),
			"name": raw.get_string_from_ascii().strip_edges(),
		})
		at += 4 + CUE_NAME_BYTES
	return out


# ------------------------------------------------------------------ snd

## A Mac `snd ` resource. Format 1 carries a synthesiser list before the command
## list and format 2 a reference count; both then hold commands, and the one that
## matters is `bufferCmd`, whose second parameter is the offset of the sound
## header inside the resource.
static func _from_snd_resource(data: PackedByteArray, error: Array) -> AudioStreamWAV:
	if data.size() < 6:
		error.append("snd resource is %d bytes" % data.size())
		return null
	var format := _be_u16(data, 0)
	var at := 2
	if format == 1:
		var synths := _be_u16(data, at)
		at += 2
		# Each synthesiser is an id and a 4-byte init parameter.
		at += synths * 6
	elif format == 2:
		# A reference count, which means nothing to a player.
		at += 2
	else:
		error.append("snd format %d is not 1 or 2" % format)
		return null

	if at + 2 > data.size():
		error.append("snd resource ends before its command list")
		return null
	var commands := _be_u16(data, at)
	at += 2
	var header_at := -1
	for i in commands:
		if at + 8 > data.size():
			break
		var cmd := _be_u16(data, at)
		var param2 := _be_u32(data, at + 4)
		if (cmd & 0x7FFF) == BUFFER_CMD and (cmd & DATA_OFFSET_FLAG) != 0:
			header_at = param2
			break
		at += 8
	if header_at < 0 or header_at + 22 > data.size():
		error.append("no bufferCmd with a usable data offset")
		return null
	return _from_sound_header(data, header_at, error)


## The sound header a `bufferCmd` points at: a pointer slot, the length in sample
## frames, the rate as a 16.16 fixed-point number, a loop range, an encoding byte
## and a base frequency — then the samples, unless the encoding says otherwise.
static func _from_sound_header(data: PackedByteArray, at: int, error: Array) -> AudioStreamWAV:
	var frames := _be_u32(data, at + 4)
	# 16.16 fixed point. The fraction is dropped rather than rounded: every rate
	# Director wrote here is a whole number of hertz, and the fraction exists
	# because the field doubles as a playback-rate multiplier.
	var rate := _be_u32(data, at + 8) >> 16
	var encoding := data[at + 20]
	var samples_at := at + 22
	var channels := 1
	var bits := 8

	if encoding == ENCODE_EXTENDED:
		# The extended header inserts a channel count *before* the fields above
		# are followed by its own: 14 more bytes plus a 10-byte 80-bit rate.
		if at + 64 > data.size():
			error.append("extended sound header runs past the resource")
			return null
		channels = _be_u32(data, at + 4)
		frames = _be_u32(data, at + 22)
		bits = _be_u16(data, at + 48)
		samples_at = at + 64
	elif encoding == ENCODE_COMPRESSED:
		# MACE 3:1 and 6:1. Refused rather than decoded as if it were PCM, the
		# same call `aiff_loader.gd` makes about AIFF-C.
		error.append("compressed snd resources (MACE) are not supported")
		return null
	elif encoding != ENCODE_STANDARD:
		error.append("snd encoding 0x%02x is not one of standard/extended" % encoding)
		return null

	if rate <= 0 or channels <= 0:
		error.append("snd header claims rate %d, %d channel(s)" % [rate, channels])
		return null
	var want := frames * channels * (bits / 8)
	var stop := samples_at + want if want > 0 else data.size()
	if stop > data.size():
		stop = data.size()
	if samples_at >= stop:
		error.append("snd header leaves no samples")
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = channels >= 2
	var payload := data.slice(samples_at, stop)
	if bits == 8:
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.data = _unsigned_to_signed(payload)
	elif bits == 16:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = _swap16(payload)
	else:
		error.append("%d-bit snd samples are not supported" % bits)
		return null
	return stream


# ------------------------------------------------------------------ sndH/sndS

## Field offsets in a `sndH`, all big-endian 32-bit signed.
##
## This is not the Mac sound header. It is the **MOA sound format record**, a
## flat run of `int32`s that Director 6 writes ahead of the samples, and
## `sound.cpp:MoaSoundFormatDecoder::loadHeaderStream` reads them in this order:
## `offset`, `size`, `playbackStart`, `playbackStartFrame`, `loopStart`,
## `loopStartFrame`, `loopEnd`, `loopEndFrame`, `playbackEnd`,
## `playbackEndFrame`, `numFrames`, `frameRate`, `byteRate`, a 16-byte
## `compressionType`, `bitsPerSample`, `bytesPerSample`, `numChannels`,
## `bytesPerFrame`, a 16-byte `soundHeaderType`, then `platformData[63]` and
## `bytesPerBlock`.
##
## **The corpus's headers are 100 bytes and stop at the end of
## `soundHeaderType`**, so the last two fields are off the end of the chunk and
## nothing here reads them. That is the file's length, not a truncated read.
const SNDH_SIZE := 4
const SNDH_LOOP_START_FRAME := 20
const SNDH_LOOP_END_FRAME := 28
const SNDH_NUM_FRAMES := 40
const SNDH_FRAME_RATE := 44
const SNDH_BITS_PER_SAMPLE := 68
const SNDH_NUM_CHANNELS := 76
## Everything above lies inside this many bytes.
const SNDH_MIN := 80


## Director's own split: `sndH` describes the samples and `sndS` *is* the samples.
##
## **This used to concatenate the two and hand the result to the Mac `snd `
## decoder**, on the reading that a `sndH` "opens with the sound header the
## `snd ` resource embeds, at a fixed offset". It does not — the two formats
## share nothing — and the mistake was invisible because the only `sndH` this
## decoder had ever seen was one the harness synthesised to match the belief.
## Against the real thing it read the rate out of `loopStartFrame` and got 0, and
## refused all 17 of Piposh 1's sound members with "snd header claims rate 0".
##
## The layout is settled twice over. `sound.cpp:MoaSoundFormatDecoder` names the
## fields, and two members of different sizes pin them independently:
##
##   PIANO.dir #8  `PIANOKEY`  size 16384   numFrames 16384   frameRate 22000
##   DAY1.dir #142 `ATTIC_DO`  size 126600  numFrames 126600  frameRate 22000
##
## `size` equals the `sndS` chunk's own length in both, which is the check that
## says the field is what it is called rather than a coincidence at one offset.
## `bitsPerSample` 8, `bytesPerSample` 1, `numChannels` 1 and `bytesPerFrame` 1
## are constant across the corpus and so are *not* distinguished by it — the four
## are told apart by the reference alone, which is why the offsets above are
## quoted from it rather than derived here.
##
## 8-bit MOA samples are **unsigned** and 16-bit are big-endian signed, the same
## pair as the `snd ` resource: `getAudioStream` sets `FLAG_UNSIGNED` when
## `bitsPerSample == 8` and never sets `FLAG_LITTLE_ENDIAN`.
static func _from_header_and_samples(header: PackedByteArray, samples: PackedByteArray,
		error: Array) -> AudioStreamWAV:
	if header.size() < SNDH_MIN:
		error.append("sndH is %d bytes, need %d" % [header.size(), SNDH_MIN])
		return null
	var rate := _be_i32(header, SNDH_FRAME_RATE)
	var bits := _be_i32(header, SNDH_BITS_PER_SAMPLE)
	var channels := _be_i32(header, SNDH_NUM_CHANNELS)
	if rate <= 0 or channels <= 0:
		error.append("sndH claims rate %d, %d channel(s)" % [rate, channels])
		return null

	# `size` is what the header says the samples are; the chunk is what they
	# actually are. They agree everywhere in this corpus, and where they would not
	# the chunk wins -- reading past it is the one outcome that is never right,
	# and a header claiming *less* than the chunk holds is how a sound gets
	# silently truncated. The disagreement is reported either way, because a
	# header that does not describe its own samples is a decode fact worth having.
	var declared := _be_i32(header, SNDH_SIZE)
	var stop := samples.size()
	if declared > 0 and declared != samples.size():
		error.append("sndH declares %d sample bytes, sndS holds %d"
			% [declared, samples.size()])
		stop = mini(declared, samples.size())
	if stop <= 0:
		error.append("sndS holds no samples")
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = channels >= 2
	var payload := samples.slice(0, stop)
	if bits == 8:
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.data = _unsigned_to_signed(payload)
	elif bits == 16:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = _swap16(payload)
	else:
		error.append("%d-bit sndH samples are not supported" % bits)
		return null

	# Director loops a member between these two, in frames, and treats an end at
	# or before the start as "loop the whole thing" —
	# `MoaSoundFormatDecoder::getAudioStream` picks `LoopingAudioStream` over
	# `SubLoopingAudioStream` on exactly that test. Both are zero across this
	# corpus, so the sub-loop arm is carried and unexercised.
	var loop_start := _be_i32(header, SNDH_LOOP_START_FRAME)
	var loop_end := _be_i32(header, SNDH_LOOP_END_FRAME)
	if loop_end > loop_start:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_start
		stream.loop_end = loop_end
	return stream


# ------------------------------------------------------------------ wav

## A whole RIFF file embedded in the member. Deliberately not a second copy of
## `AudioDirector._load_wav_runtime`'s chunk walk — that one reads from a path
## and this from bytes — but the same rules: PCM only, and 8-bit WAV samples are
## unsigned where 16-bit are signed, which is the opposite way round from AIFF.
static func _from_wav(data: PackedByteArray, error: Array) -> AudioStreamWAV:
	if data.size() < 12 or data.slice(8, 12).get_string_from_ascii() != "WAVE":
		error.append("RIFF container is not WAVE")
		return null
	var at := 12
	var audio_format := 1
	var channels := 1
	var rate := 0
	var bits := 16
	var pcm := PackedByteArray()
	while at + 8 <= data.size():
		var tag := data.slice(at, at + 4).get_string_from_ascii()
		var size := _le_u32(data, at + 4)
		var body := at + 8
		if size < 0 or body + size > data.size():
			break
		if tag == "fmt " and size >= 16:
			audio_format = _le_u16(data, body)
			channels = _le_u16(data, body + 2)
			rate = _le_u32(data, body + 4)
			bits = _le_u16(data, body + 14)
		elif tag == "data":
			pcm = data.slice(body, body + size)
		at = body + size + (size & 1)

	if audio_format != 1:
		error.append("WAV format %d is not PCM" % audio_format)
		return null
	if rate <= 0 or pcm.is_empty():
		error.append("WAV claims rate %d, %d sample bytes" % [rate, pcm.size()])
		return null
	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = channels >= 2
	if bits == 8:
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.data = _unsigned_to_signed(pcm)
	elif bits == 16:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = pcm
	else:
		error.append("%d-bit WAV samples are not supported" % bits)
		return null
	return stream


# ------------------------------------------------------------------ bytes

static func _unsigned_to_signed(source: PackedByteArray) -> PackedByteArray:
	var out := source.duplicate()
	for i in out.size():
		out[i] = (out[i] + UNSIGNED_TO_SIGNED) & 0xFF
	return out


static func _swap16(source: PackedByteArray) -> PackedByteArray:
	var out := source.duplicate()
	var count := out.size() - 1
	var i := 0
	while i < count:
		var high := out[i]
		out[i] = out[i + 1]
		out[i + 1] = high
		i += 2
	return out


static func _be_u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _be_u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


## Every field of a `sndH` is a *signed* 32-bit, and the sign is load-bearing:
## the reference reads them with `readSint32BE` and the decode branches on
## `rate <= 0` and `loopEnd > loopStart`, both of which a two-billion-and-change
## unsigned reading would turn into the wrong answer rather than a rejection.
static func _be_i32(d: PackedByteArray, o: int) -> int:
	var raw := _be_u32(d, o)
	return raw - 0x100000000 if raw >= 0x80000000 else raw


static func _le_u16(d: PackedByteArray, o: int) -> int:
	return d[o] | (d[o + 1] << 8)


static func _le_u32(d: PackedByteArray, o: int) -> int:
	return d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24)
