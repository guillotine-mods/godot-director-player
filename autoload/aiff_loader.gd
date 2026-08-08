class_name AiffLoader
extends RefCounted
## AIFF to `AudioStreamWAV`, because Godot loads neither AIFF nor AIFF-C.
##
## `ResourceImporterWAV` recognises `wav` only and `AudioStreamWAV.load_from_buffer`
## requires WAV data, so a Director title whose sounds ship as `.aif` is silent
## with no error. This is the same shape as `AudioDirector._load_wav_runtime` —
## a chunk walk producing a stream directly — with IFF's rules instead of RIFF's:
## big-endian, and every chunk padded to an even length.
##
## Surveyed across all six roots the engine runs — 12,790 AIFF files, not the
## 3,142 of piposh2 this was first written against. Every one is plain `AIFF`
## rather than AIFF-C; 12,756 are mono and 12,628 are 8-bit.
##
## The 18-byte `COMM` this used to claim was universal is not: **11 files carry
## 22 bytes**, and reading the extra four as AIFF-C's compression field is what
## silenced them. Only AIFF-C has that field — see the gate below. One file
## (`piposh/SOUNDS/STIMDAY1/PIP21.AIF`) declares zero sample frames and is empty
## in the original; it is refused here, and `tools/sound_format_check.gd` scores
## it as the disc's rather than this decoder's.
##
## The one piece of luck worth naming: **8-bit AIFF samples are signed, and so is
## `AudioStreamWAV.FORMAT_8_BITS`**, so those files transfer verbatim. It is 8-bit
## *WAV* that is unsigned and needs converting — the opposite of the reflex.
## 16-bit does need a swap, AIFF being big-endian.

## `COMM` holds the sample rate as an 80-bit IEEE 754 extended float, which no
## other format in this codebase uses and Godot cannot read.
const EXTENDED_BIAS := 16383


## `null` when the bytes are not an AIFF this can read, with the reason appended
## to `error`. A sound that fails to load is a fact about the file; callers
## report it rather than taking the movie down.
static func load_from_buffer(data: PackedByteArray, error: Array = []) -> AudioStreamWAV:
	if data.size() < 12:
		error.append("too short to be a container")
		return null
	if data.slice(0, 4).get_string_from_ascii() != "FORM":
		error.append("not an IFF container")
		return null
	var form := data.slice(8, 12).get_string_from_ascii()
	if form != "AIFF" and form != "AIFC":
		error.append("FORM type is %s, not AIFF" % JSON.stringify(form))
		return null

	var channels := 0
	var bits := 0
	var rate := 0
	var frames := 0
	var samples := PackedByteArray()
	var compressed := false

	var at := 12
	while at + 8 <= data.size():
		var tag := data.slice(at, at + 4).get_string_from_ascii()
		var size := _be_u32(data, at + 4)
		var body := at + 8
		if size < 0 or body + size > data.size():
			break
		match tag:
			"COMM":
				if size < 18:
					error.append("COMM is %d bytes" % size)
					return null
				channels = _be_u16(data, body)
				frames = _be_u32(data, body + 2)
				bits = _be_u16(data, body + 6)
				rate = _extended_to_int(data, body + 8)
				# AIFF-C names a codec in the two words after the rate — and
				# **only** AIFF-C does. A `FORM AIFF` declares `COMM` to be
				# exactly 18 bytes with no compression field at all, so bytes
				# past 18 in one are the authoring tool's leftovers and mean
				# nothing. Reading them anyway is how 11 files across two of the
				# six roots went silent: `piposh` and `piposh-ru` ship a 22-byte
				# `COMM` whose trailer reads `Wave`, which is not a codec, does
				# not equal `NONE`, and so was refused as a compression that was
				# never there. All 11 are mono 8-bit 22050 PCM whose `SSND`
				# length matches their frame count exactly, and they play.
				#
				# Gated on the FORM type rather than on the string, because the
				# rule is the spec's and `Wave` is only this disc's spelling of
				# breaking it. Surveyed across all six roots: 12,790 FORM files
				# and not one AIFC, so nothing here is measured against a real
				# codec — the branch stays for the first disc that ships one.
				if form == "AIFC" and size >= 22:
					var codec := data.slice(body + 18, body + 22).get_string_from_ascii()
					compressed = codec != "NONE" and codec != "sowt"
			"SSND":
				# 8 bytes of offset and blockSize precede the samples.
				if size < 8:
					error.append("SSND is %d bytes" % size)
					return null
				var offset := _be_u32(data, body)
				var start := body + 8 + offset
				if start > data.size():
					error.append("SSND offset runs past the file")
					return null
				samples = data.slice(start, body + size)
		# Every IFF chunk is padded to an even length; the pad byte is not
		# counted in the size, and skipping that is how a walk desynchronises
		# halfway through a file and then reads garbage rather than failing.
		at = body + size + (size & 1)

	if compressed:
		error.append("AIFF-C compression is not supported")
		return null
	if channels <= 0 or rate <= 0 or samples.is_empty():
		error.append("no usable COMM/SSND (channels %d, rate %d, %d sample bytes)" % [
			channels, rate, samples.size(),
		])
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = channels >= 2
	match bits:
		8:
			# Signed on both sides: nothing to convert.
			stream.format = AudioStreamWAV.FORMAT_8_BITS
			stream.data = samples
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.data = _swap16(samples)
		_:
			error.append("%d-bit samples are not supported" % bits)
			return null
	return stream


## Every chunk in the container, tag -> byte size, without decoding anything.
##
## The question this exists for is cue points. Director's `cuePassed` and the
## wait-for-cue tempo values (§12) read a sound's cue points, and in an AIFF
## those are `MARK` chunks — so whether cue points are a subsystem this port owes
## anything is a fact about the *files*, answerable without a running movie.
## `tools/aiff_check.gd` asks it of all 3,142.
static func chunk_sizes(data: PackedByteArray) -> Dictionary:
	var out: Dictionary = {}
	if data.size() < 12 or data.slice(0, 4).get_string_from_ascii() != "FORM":
		return out
	var at := 12
	while at + 8 <= data.size():
		var tag := data.slice(at, at + 4).get_string_from_ascii()
		var size := _be_u32(data, at + 4)
		if size < 0 or at + 8 + size > data.size():
			break
		out[tag] = int(out.get(tag, 0)) + size
		at += 8 + size + (size & 1)
	return out


## The file's cue points, as `{id, frame, name}` in sample frames.
##
## A `MARK` chunk is a count followed by that many records of `id` (int16),
## `position` (uint32) and a Pascal-string name padded to an even length. The
## padding is on the *record*, not the string, which is why the name's own length
## byte counts towards it — get that wrong and the second marker of every file
## reads garbage.
##
## Carrying the chunk, declaring markers and carrying a *usable* cue point are
## three different questions, and in this game they have three different answers.
## 168 of the 3,141 files carry an 18-byte `MARK`; all 168 declare two markers;
## and not one of the 336 sits at a position inside its own audio — they are the
## same eleven byte patterns repeated file after file, positions 0x53540000 and
## 0x007f007f with empty names, which is authoring-tool boilerplate rather than
## anything a movie could wait on. `tools/aiff_check.gd` is what says so, and it
## checks the positions rather than the chunk for exactly that reason.
static func cue_points(data: PackedByteArray) -> Array:
	var out: Array = []
	if data.size() < 12 or data.slice(0, 4).get_string_from_ascii() != "FORM":
		return out
	var at := 12
	while at + 8 <= data.size():
		var tag := data.slice(at, at + 4).get_string_from_ascii()
		var size := _be_u32(data, at + 4)
		var body := at + 8
		if size < 0 or body + size > data.size():
			break
		if tag == "MARK" and size >= 2:
			var count := _be_u16(data, body)
			var cursor := body + 2
			for i in count:
				if cursor + 7 > body + size:
					break
				var id := _be_u16(data, cursor)
				var frame := _be_u32(data, cursor + 2)
				var name_length := data[cursor + 6]
				var name_at := cursor + 7
				if name_at + name_length > data.size():
					break
				out.append({
					"id": id - 65536 if id >= 32768 else id,
					"frame": frame,
					"name": data.slice(name_at, name_at + name_length).get_string_from_ascii(),
				})
				cursor = name_at + name_length
				if (name_length + 1) % 2 == 1:
					cursor += 1
		at = body + size + (size & 1)
	return out


static func load_from_file(path: String, error: Array = []) -> AudioStreamWAV:
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		error.append("cannot read %s" % path)
		return null
	return load_from_buffer(data, error)


## AIFF stores samples big-endian; `AudioStreamWAV` wants little.
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


## The 80-bit IEEE 754 extended the sample rate is stored as. Only the integer
## part is wanted, and every rate in this corpus is well under 2^31.
static func _extended_to_int(data: PackedByteArray, at: int) -> int:
	if at + 10 > data.size():
		return 0
	var exponent := _be_u16(data, at) & 0x7FFF
	# Only the top 32 bits of the mantissa. The field is 64 bits wide with an
	# explicit leading 1, so assembling it whole sets bit 63 and GDScript's
	# signed int reads it as negative: every rate came out as -10718 rather than
	# 22050, and a negative rate is a stream that decodes and never plays.
	var mantissa := 0
	for i in 4:
		mantissa = (mantissa << 8) | data[at + 2 + i]
	if exponent == 0 or mantissa == 0:
		return 0
	# value = (mantissa << 32) * 2^(exponent - bias - 63), with the shift folded
	# in so the intermediate never needs the low 32 bits.
	var shift := exponent - EXTENDED_BIAS - 31
	if shift >= 0:
		return mantissa << mini(shift, 32)
	if -shift >= 63:
		return 0
	return mantissa >> -shift


static func _be_u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _be_u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]
