extends RefCounted
## The MPEG-1 **system** layer (ISO/IEC 11172-1): pack headers, packet headers,
## and the elementary streams pulled back out of them.
##
## ## Why this is a file of its own
##
## `docs/DIGITAL_VIDEO.md` §1 counts 22 `.mpg` in `test-games/itamar-magichat`
## and calls them "MPEG-1 *system* streams — muxed video and MPEG audio, pack
## header `00 00 01 BA` with MPEG-1's marker rather than MPEG-2's". Two entirely
## separate specifications are stacked there: 11172-1 wraps 11172-2, and the
## wrapper is a linked list of length-prefixed packets with no entropy coding, no
## transform and no state. It is the easy half by a wide margin, it is the half
## that can be asserted against the real files on its own (`tools/mpeg1_decode.gd`
## step 1), and it is the half a `.m1v` does not need at all.
##
## Keeping it apart from `director_mpeg1_video.gd` means the video decoder is
## handed one flat elementary stream and never learns that a container existed —
## which is what lets the same decoder be pointed at a bare `.m1v`, at a stream
## lifted out of a `.vob`, or at a synthesised fixture, and is why the harness can
## test the two independently.
##
## ## What it reads
##
## A program stream is a sequence of **packs**. Each pack is
##
##     00 00 01 BA  <SCR and mux rate>  [00 00 01 BB <system header>]  packet*
##
## and each packet is
##
##     00 00 01 <id>  <16-bit length>  <header>  <payload>
##
## where `id` is `0xE0`..`0xEF` for video, `0xC0`..`0xDF` for audio, and the
## reserved ids `0xBB` (system header), `0xBC` (map), `0xBE` (padding) and `0xBF`
## (private) carry nothing this port wants. The payload of every packet with the
## same id, concatenated in file order, **is** the elementary stream: the system
## layer adds no framing of its own inside a packet, which is why reassembly is a
## concatenation and not a parse.
##
## The packet header before the payload is the one place MPEG-1 and MPEG-2 differ
## enough to matter, and both shapes are read:
##
##   * **11172-1**: up to 16 stuffing bytes of `0xFF`, then optionally two bytes
##     of STD buffer size (`01` in the top two bits), then either a 5-byte PTS
##     (`0010` in the top four), a 10-byte PTS+DTS (`0011`), or the single byte
##     `0x0F` meaning neither.
##   * **13818-1**: one flags byte with `10` in the top two bits, a second flags
##     byte, and a length byte counting the rest of the header.
##
## Reading both costs eight lines and means a file that is MPEG-2 *system* around
## MPEG-1 *video* — which exists, and which a Director title could have been
## authored with — is demuxed rather than refused for the wrong reason. What is
## refused is MPEG-2 **video**, and that refusal is the video decoder's to make.
##
## ## Timing, and why the duration does not come from counting pictures
##
## `the duration of member` is read by movies that never start the video
## (`docs/DIGITAL_VIDEO.md` §3, and `director_ogg.gd`'s header makes the same
## argument for Theora), so it has to be answerable without decoding. The system
## layer answers it twice over, independently of the video layer:
##
##   * every pack carries a 33-bit **SCR** at 90 kHz, so the span from the first
##     pack to the last is the length of the multiplex;
##   * most video packets carry a **PTS** on the same clock, so the span from the
##     first video PTS to the last is the length of the picture stream.
##
## This reader keeps both and `director_mpeg1.gd` prefers the PTS span, because
## the SCR of the final pack is when the last *bytes* arrive and the PTS of the
## final picture is when the last *picture* is shown — and a multiplex ends with
## the audio still being fed. Measured on `heb/mainmenu/intro.mpg`: SCR span
## 87.59 s, video PTS span 87.48 s, and 2,189 pictures at the sequence header's
## own 25 fps is **87.56 s**. The PTS span plus one frame interval lands on it;
## the SCR span is 30 ms long.
##
## ## What it does not do
##
## No CRC, no system header validation, no STD buffer modelling, no more than one
## video stream, and no attempt to interleave audio and video by time — the two
## come out as two flat buffers and the player is what re-synchronises them. That
## last one is not a shortcut the audio half exposed: the sound track is decoded
## whole and played from `the movieTime`, so the picture and the sound are
## synchronised by the playhead rather than by the multiplex.
## A file whose packets are damaged is not repaired: the walk stops at the first
## length that would run past the end of the file and reports what it had, which
## is the same rule `director_avi.gd:_walk` states for a truncated RIFF tail.

## The 33-bit system clock's rate, in Hz. Fixed by 11172-1 and not negotiable per
## file, which is why it is a constant and not a field.
const CLOCK_HZ := 90000.0

## Start code prefix bytes. A start code is `00 00 01` followed by one byte that
## says what follows; the same prefix is what the *video* layer uses one level
## down, which is why an emulator of either has to be careful that a payload
## cannot contain one — 11172-2 §2.4.2.2 forbids it and this reader relies on it
## only for the tail scan, never for the walk.
const PACK_START := 0xBA
const SYSTEM_HEADER := 0xBB
const PROGRAM_END := 0xB9
const PADDING := 0xBE
const PRIVATE_1 := 0xBD
const PRIVATE_2 := 0xBF
const PROGRAM_MAP := 0xBC

var error: String = ""
var path: String = ""

## True when the file opened with a pack header. False means the bytes were taken
## as a bare video elementary stream, which is what a `.m1v` is and what
## `elementary` then answers with unchanged.
var is_program_stream: bool = false
## `0xE0`..`0xEF`, or 0 when no video packet was seen.
var video_id: int = 0
## `0xC0`..`0xDF`, or 0.
var audio_id: int = 0

## The SCR of the first and last pack, in 90 kHz units, and the PTS of the first
## and last *video* packet that carried one. -1 for "never seen".
var first_scr: int = -1
var last_scr: int = -1
var first_video_pts: int = -1
var last_video_pts: int = -1

## Counts, kept because they are what a harness asserts a walk against: a demux
## that silently dropped half the packets still produces a plausible-looking
## elementary stream.
var packs: int = 0
var video_packets: int = 0
var audio_packets: int = 0
var padding_packets: int = 0
var video_bytes: int = 0
var audio_bytes: int = 0

var _bytes: PackedByteArray = PackedByteArray()
var _video: PackedByteArray = PackedByteArray()
var _audio: PackedByteArray = PackedByteArray()
var _demuxed: bool = false


## Read a file and walk its system layer. False leaves `error` set.
##
## **The whole file is read into memory**, and that is a deliberate trade rather
## than an oversight. The alternative is 5,483 seeks and 5,483 six-byte reads for
## `intro.mpg` alone, which is the shape `FileAccess` is worst at; one
## `get_buffer` of 15 MB is a single native read and the walk that follows is
## ~12,000 GDScript iterations over an in-memory array. The corpus's largest file
## is `heb/album/magic5.mpg` at 25 MB, the elementary streams come to about 85% of
## that, and the source buffer is released as soon as they are extracted — so the
## resident cost of an open reader is the streams and not the file.
func open(file_path: String) -> bool:
	close()
	path = file_path
	error = ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		error = "cannot open %s (%d)" % [file_path, FileAccess.get_open_error()]
		return false
	var length := int(file.get_length())
	if length < 4:
		error = "%s is %d bytes" % [file_path, length]
		file.close()
		return false
	_bytes = file.get_buffer(length)
	file.close()
	if _bytes.size() < 4:
		error = "%s read short" % file_path
		return false
	if _bytes[0] == 0x00 and _bytes[1] == 0x00 and _bytes[2] == 0x01 \
			and _bytes[3] == PACK_START:
		is_program_stream = true
		return _walk()
	if _bytes[0] == 0x00 and _bytes[1] == 0x00 and _bytes[2] == 0x01 \
			and _bytes[3] == 0xB3:
		# A bare elementary stream — a `.m1v`, or a `.mpg` somebody stripped. The
		# video layer wants exactly these bytes, so there is nothing to walk.
		is_program_stream = false
		_video = _bytes
		_bytes = PackedByteArray()
		video_bytes = _video.size()
		_demuxed = true
		return true
	error = "%s does not begin with an MPEG-1 pack header or sequence header (%02X %02X %02X %02X)" % [
		file_path, _bytes[0], _bytes[1], _bytes[2], _bytes[3]]
	return false


func close() -> void:
	_bytes = PackedByteArray()
	_video = PackedByteArray()
	_audio = PackedByteArray()
	_demuxed = false
	is_program_stream = false
	video_id = 0
	audio_id = 0
	first_scr = -1
	last_scr = -1
	first_video_pts = -1
	last_video_pts = -1
	packs = 0
	video_packets = 0
	audio_packets = 0
	padding_packets = 0
	video_bytes = 0
	audio_bytes = 0


## The video elementary stream, reassembled. Empty when the file had none.
func video_elementary() -> PackedByteArray:
	return _video


## The audio elementary stream, reassembled.
##
## `director_mpeg1_audio.gd` walks its frames and decodes them; `director_mpeg1.gd`
## reads the first frame's *header* out of it before any of that, so that a movie
## asking `the sampleRate of member` gets the file's own answer without waiting
## for a sample. Both need exactly these bytes and neither needs to know a
## container was involved, which is the same separation the video half has.
func audio_elementary() -> PackedByteArray:
	return _audio


## The length of the multiplex from the pack clock, in milliseconds.
func scr_span_ms() -> float:
	if first_scr < 0 or last_scr < first_scr:
		return 0.0
	return float(last_scr - first_scr) * 1000.0 / CLOCK_HZ


## The length of the picture stream from the presentation clock, in milliseconds.
##
## This is the span between the **first and last picture shown**, so it is one
## frame interval short of the running time; the caller adds that, because only
## the video layer knows what a frame interval is.
func pts_span_ms() -> float:
	if first_video_pts < 0 or last_video_pts < first_video_pts:
		return 0.0
	return float(last_video_pts - first_video_pts) * 1000.0 / CLOCK_HZ


# ==================================================================== the walk


## One pass over the packs, appending every payload to its stream.
##
## Written against explicit lengths rather than by searching for the next start
## code, and that is the whole reason the system layer is cheap: a packet says how
## long it is, so the walk visits 12,000 header positions in a 15 MB file instead
## of 15 million byte positions. A search would also be *wrong* — a payload is
## compressed video and may contain `00 00 01` by chance in the parts of the
## elementary stream that are not start codes.
func _walk() -> bool:
	var at := 0
	var size := _bytes.size()
	var video := PackedByteArray()
	var audio := PackedByteArray()
	while at + 4 <= size:
		if _bytes[at] != 0x00 or _bytes[at + 1] != 0x00 or _bytes[at + 2] != 0x01:
			# Zero padding between packs is legal and some muxers emit it. A byte
			# that is not the start of a start code is skipped rather than fatal,
			# and the loop cannot run away because it only ever moves forward.
			at += 1
			continue
		var code := _bytes[at + 3]
		if code == PROGRAM_END:
			break
		if code == PACK_START:
			var consumed := _read_pack_header(at)
			if consumed <= 0:
				break
			at += consumed
			packs += 1
			continue
		if code < 0xBB:
			# 0xB0..0xBA that is not a pack: reserved, or the video layer's own
			# start codes appearing because the file is not a program stream after
			# all. Neither is walkable here.
			at += 4
			continue
		if at + 6 > size:
			break
		var packet_len := (_bytes[at + 4] << 8) | _bytes[at + 5]
		var body := at + 6
		var end := body + packet_len
		if packet_len <= 0 or end > size:
			# A truncated tail. Everything already collected stays valid, which is
			# `director_avi.gd:_walk`'s rule and for the same reason: refusing the
			# whole file would lose a playable clip over a trailing byte.
			break
		if code == SYSTEM_HEADER or code == PROGRAM_MAP or code == PRIVATE_2:
			at = end
			continue
		if code == PADDING:
			padding_packets += 1
			at = end
			continue
		var payload := _packet_payload(body, end, code)
		if payload >= 0 and payload < end:
			if code >= 0xE0 and code <= 0xEF:
				if video_id == 0:
					video_id = code
				if code == video_id:
					video.append_array(_bytes.slice(payload, end))
					video_packets += 1
			elif code >= 0xC0 and code <= 0xDF:
				if audio_id == 0:
					audio_id = code
				if code == audio_id:
					audio.append_array(_bytes.slice(payload, end))
					audio_packets += 1
		at = end
	_video = video
	_audio = audio
	video_bytes = video.size()
	audio_bytes = audio.size()
	_bytes = PackedByteArray()
	_demuxed = true
	if _video.is_empty():
		error = "%s carries no MPEG video packets (%d packs, %d audio packets)" % [
			path, packs, audio_packets]
		return false
	return true


## A pack header, returning how many bytes it occupies including the start code.
##
## The version is decided by the four bits after the start code, which is the one
## byte that separates the two system specifications: 11172-1 writes `0010` there
## (the top nibble of a 33-bit SCR split around marker bits) and 13818-1 writes
## `01`. Getting it wrong shifts every subsequent read by two bytes, so it is
## tested rather than assumed — and an MPEG-2 pack is walked correctly here even
## though the video inside it will be refused one layer down, because "this is
## MPEG-2 video" is a much more useful error than "this is not a pack header".
func _read_pack_header(at: int) -> int:
	var size := _bytes.size()
	if at + 12 > size:
		return 0
	var marker := _bytes[at + 4]
	if (marker & 0xF0) == 0x20:
		var scr := ((marker >> 1) & 0x07) << 30
		scr |= _bytes[at + 5] << 22
		scr |= (_bytes[at + 6] >> 1) << 15
		scr |= _bytes[at + 7] << 7
		scr |= _bytes[at + 8] >> 1
		if first_scr < 0:
			first_scr = scr
		last_scr = scr
		return 12
	if (marker & 0xC0) == 0x40:
		# 13818-1: a 6-byte SCR with an extension, a 3-byte mux rate, then a
		# 3-bit stuffing length in the low bits of the byte after them.
		if at + 14 > size:
			return 0
		var scr2 := ((marker >> 3) & 0x07) << 30
		scr2 |= (marker & 0x03) << 28
		scr2 |= _bytes[at + 5] << 20
		scr2 |= ((_bytes[at + 6] >> 3) & 0x1F) << 15
		scr2 |= (_bytes[at + 6] & 0x03) << 13
		scr2 |= _bytes[at + 7] << 5
		scr2 |= _bytes[at + 8] >> 3
		if first_scr < 0:
			first_scr = scr2
		last_scr = scr2
		var stuffing := _bytes[at + 13] & 0x07
		return 14 + stuffing
	return 0


## Where a packet's payload begins, given the bounds of its body.
##
## Returns the payload offset, or -1 when the header could not be read. Also
## records the PTS of a video packet, which is the only field in the system layer
## this port reads for anything other than skipping.
func _packet_payload(body: int, end: int, code: int) -> int:
	var i := body
	if i >= end:
		return -1
	if (_bytes[i] & 0xC0) == 0x80:
		# 13818-1 PES: flags, flags, header length.
		if i + 3 > end:
			return -1
		var flags := _bytes[i + 1]
		var header_len := _bytes[i + 2]
		var after := i + 3 + header_len
		if after > end:
			return -1
		if (flags & 0x80) != 0 and i + 8 <= end:
			_note_pts(_read_timestamp(i + 3), code)
		return after
	# 11172-1: stuffing, then an optional STD buffer field, then the timestamps.
	var stuffed := 0
	while i < end and _bytes[i] == 0xFF and stuffed < 16:
		i += 1
		stuffed += 1
	if i >= end:
		return -1
	if (_bytes[i] & 0xC0) == 0x40:
		i += 2
		if i >= end:
			return -1
	var lead := _bytes[i]
	if (lead & 0xF0) == 0x20:
		if i + 5 > end:
			return -1
		_note_pts(_read_timestamp(i), code)
		return i + 5
	if (lead & 0xF0) == 0x30:
		if i + 10 > end:
			return -1
		_note_pts(_read_timestamp(i), code)
		return i + 10
	if lead == 0x0F:
		return i + 1
	# No recognised header byte. The payload starts here; a packet that is all
	# payload is legal in a stream whose first packet carried the only timestamp.
	return i


## A 33-bit timestamp out of the five bytes that carry it, marker bits and all.
##
## `xxxx SSS1 SSSSSSSS SSSSSSS1 SSSSSSSS SSSSSSS1` — three bits, then two
## fifteen-bit halves, each followed by a marker bit that is always 1 and is
## always dropped. Reading it as a flat 40-bit number is the classic way to be
## eight times out on every timestamp in the file.
func _read_timestamp(at: int) -> int:
	if at + 5 > _bytes.size():
		return -1
	var v := ((_bytes[at] >> 1) & 0x07) << 30
	v |= _bytes[at + 1] << 22
	v |= (_bytes[at + 2] >> 1) << 15
	v |= _bytes[at + 3] << 7
	v |= _bytes[at + 4] >> 1
	return v


func _note_pts(pts: int, code: int) -> void:
	if pts < 0 or code < 0xE0 or code > 0xEF:
		return
	if first_video_pts < 0:
		first_video_pts = pts
	last_video_pts = pts
