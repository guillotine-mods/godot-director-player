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
## **None of this is verified against the corpus this port was built on.** That
## game has no sound cast member in any of its 86 containers and no score sound
## channel is ever written; every sound it plays is an external `.aif` played by
## `sound playFile` (`tools/sound_survey.gd`). The formats below are implemented
## from their published definitions, and `tools/sound_member.gd` exercises them
## against synthesised payloads, which proves the decoder and not the corpus. The
## first title that ships a sound member is what will confirm the reader.

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
## and fires `cuePassed` the same way a file-sourced one does. Only the embedded
## AIFF shape can carry them — a `snd ` resource has no marker chunk — which is
## why this returns an empty list rather than refusing for the others.
static func cue_points(data: PackedByteArray) -> Array:
	if data.size() >= 4 and data.slice(0, 4).get_string_from_ascii() == "FORM":
		return AiffLoader.cue_points(data)
	return []


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
