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
## This game's 3,142 files are unusually easy, surveyed across all of them: every
## one is plain `AIFF` rather than AIFF-C, with an 18-byte `COMM`, so there is no
## compression field to honour. 3,140 are mono and 3,099 are 8-bit.
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
				# AIFF-C names a codec in the two words after the rate. None of
				# this game's files are AIFF-C; anything that is gets refused
				# rather than decoded as if it were PCM.
				if size >= 22:
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
