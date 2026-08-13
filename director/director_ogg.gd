extends RefCounted
## An Ogg container walk that reads the Theora and Vorbis *identification
## headers* and the stream's last granule position — enough to answer what a
## `.ogv` is and how long it runs, without decoding a single frame.
##
## ## Why a parser at all, when Godot decodes Theora
##
## Godot 4 does decode Theora: `VideoStreamPlayer` plays an `.ogv` and
## `get_stream_length()` answers its duration. So this file is not here to make
## playback possible — `preview/video.gd` uses the engine's own player for the
## pixels and the sound. It is here because the *property surface* has to answer
## before anything plays, and the player cannot answer it:
##
##   * `the duration of member` is read by movies that never start the video at
##     all. Magic Hat's `Check avi` is `if sprite(3).movieTime >= FilmLen`, and
##     `FilmLen` is set in `enterFrame` — before the first tick of playback.
##     Asking a `VideoStreamPlayer` means instantiating a node, adding it to the
##     tree and waiting for it to open the stream, inside a property read.
##   * `the sampleRate`, `the sampleSize` and `the channelCount` of the sound
##     track have no accessor on `VideoStreamPlayer` in any Godot version.
##   * `the digitalVideoType` and the member's own picture size want the file's
##     own header, not the player's idea of a viewport.
##
## And there is a second reason, which is the one `AGENTS.md` states as a rule:
## **a decode is the port's input, not the original.** A duration that comes out
## of the same subsystem that plays the file cannot be used to check that
## subsystem. `tools/video_sidecar.gd` compares this file's answer against
## `VideoStreamPlayer.get_stream_length()` and fails when they disagree by more
## than a frame, which is only possible because the two are computed by
## different code from different parts of the file. Measured on a 3.08 s
## transcode of `retro.mpg`: this parser says 3080 ms and the player says 3.08 s.
##
## ## What is read, and where each number comes from
##
## The Ogg page header is fixed: `OggS`, a version byte that must be 0, a flags
## byte, a 64-bit little-endian granule position, a 32-bit serial, a 32-bit page
## sequence, a CRC, a segment count and that many segment lengths (RFC 3533 §6).
## Every stream in an Ogg file opens with a beginning-of-stream page whose first
## packet is that codec's identification header, so one pass over the opening
## pages names every stream in the file.
##
##   * **Theora** (`0x80` + `"theora"`, Theora I specification §6.2): the picture
##     size `PICW`/`PICH` as two 24-bit big-endian fields, the frame rate as the
##     ratio `FRN`/`FRD`, and `KFGSHIFT` — the bit width the granule position
##     splits into a key frame number and an offset from it.
##   * **Vorbis** (`0x01` + `"vorbis"`, Vorbis I specification §4.2.2): the
##     channel count and the sample rate, both at fixed offsets.
##
## The duration comes from the **last page of the Theora stream**, whose granule
## position is `(keyframe << KFGSHIFT) | offset`; adding the two halves gives the
## number of frames decoded by that point, and the frame rate turns it into a
## time. That is the same arithmetic every Ogg tool does and it is the only place
## a Theora file states its own length — there is no duration field.
##
## ## What this deliberately does not do
##
## No packet decode, no CRC check, no chained-stream support (a second logical
## stream after the first ends, which no transcoder writes for a single clip),
## and no Skeleton track. A file that fails any assumption is refused with a
## named error rather than half-read, which is the rule `director_avi.gd` states
## at its own head: a confident wrong answer is worse than an absent one.

## Which playback path `preview/video.gd` drives this reader with. Named on the
## reader rather than tested with `is` at the call site, because the two readers
## live in different files and a caller that asked "is this an `Avi`" would have
## to preload both to ask about either.
const BACKEND := "theora"

## The Ogg page header before the segment table, in bytes: capture pattern (4),
## version (1), header type (1), granule position (8), serial (4), page sequence
## (4), CRC (4), segment count (1).
const PAGE_HEADER := 27

## How much of the file's tail is searched for the last Theora page. A page's
## payload is at most 255 * 255 bytes plus its header, so 64 KB always contains
## the final page whole; reading the whole file to find one 8-byte field would
## cost 15 MB of allocation for a two-minute clip.
const TAIL_BYTES := 65536

## How far into the file the opening pages are looked for. Every identification
## header is on a beginning-of-stream page and Ogg requires those to come before
## any data, so they are inside the first few kilobytes of every file a muxer
## produces. Generous by a factor of thirty rather than tight, because the cost
## of being wrong is refusing a valid file.
const HEAD_BYTES := 65536

var error: String = ""
var path: String = ""

## `PICW` and `PICH` — the *picture* size, which is what a player shows. Theora
## codes in 16x16 macroblocks and pads up to them, so `FMBW * 16` is the coded
## size and is not the same number for a 352x288 clip. The picture size is the
## one that matches the member's `xtraRect`.
var width: int = 0
var height: int = 0
var fps: float = 0.0
## Frames decoded by the last page, derived from its granule position.
var frame_count: int = 0
var duration_ms: float = 0.0

var audio_rate: int = 0
## Vorbis is a lossy transform codec with no sample width of its own; Godot mixes
## it at 16 bits and that is what `the sampleSize of member` is answered with.
## Named here rather than written as a bare 16 at the call site, so the one place
## it is decided is the one place it is explained.
var audio_bits: int = 16
var audio_channels: int = 0

var has_theora: bool = false
var has_vorbis: bool = false

var _theora_serial: int = 0
var _kfgshift: int = 0


## Read the headers of an Ogg file. True when a Theora video stream was found
## with a picture size and a duration above zero.
##
## **A zero duration is a failure, not a fact**, and that is load-bearing rather
## than defensive: `preview/video.gd` treats an opened reader as a member whose
## media is ready, and a ready member with a duration of 0 is exactly the state
## `docs/DIGITAL_VIDEO.md` §3 warns turns Magic Hat's one-tick skip into
## `go(the frame)` for ever. A truncated or still-being-written sidecar has no
## last granule position, so refusing it here is what keeps that file a clean
## skip instead of a hang.
func open(file_path: String) -> bool:
	path = file_path
	error = ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		error = "cannot open (%d)" % FileAccess.get_open_error()
		return false
	var size := int(file.get_length())
	file.seek(0)
	var head := file.get_buffer(mini(size, HEAD_BYTES))
	_read_headers(head)
	if not has_theora:
		file.close()
		if error == "":
			error = "no Theora video stream"
		return false
	var tail_at := maxi(0, size - TAIL_BYTES)
	file.seek(tail_at)
	var tail := file.get_buffer(size - tail_at)
	file.close()
	frame_count = _frames_from_tail(tail)
	if frame_count <= 0:
		error = "no Theora granule position — the file is truncated or still being written"
		return false
	if fps <= 0.0:
		error = "the Theora header declares a frame rate of 0"
		return false
	duration_ms = float(frame_count) * 1000.0 / fps
	if width <= 0 or height <= 0:
		error = "the Theora header declares a %dx%d picture" % [width, height]
		return false
	return true


## Walk the opening pages and parse the identification header of each stream.
##
## Only beginning-of-stream pages are looked at (`header_type & 0x02`), which is
## the flag Ogg uses to mark exactly the pages that carry them, and the walk
## stops at the first page that is not one — every identification header
## precedes every data page in a valid file, so there is nothing after that point
## worth reading and a data payload that happens to start with `0x80 theora`
## cannot be mistaken for a second video stream.
func _read_headers(buffer: PackedByteArray) -> void:
	var at := 0
	while at + PAGE_HEADER <= buffer.size():
		if buffer.decode_u32(at) != 0x5367674F:  # "OggS", little-endian
			error = "not an Ogg file"
			return
		if buffer[at + 4] != 0:
			error = "Ogg stream structure version %d, expected 0" % buffer[at + 4]
			return
		var flags := buffer[at + 5]
		var serial := int(buffer.decode_u32(at + 14))
		var segments := buffer[at + 26]
		var table_at := at + PAGE_HEADER
		if table_at + segments > buffer.size():
			return
		var payload_at := table_at + segments
		var first_packet := 0
		var payload_size := 0
		for i in segments:
			payload_size += buffer[table_at + i]
		# The first packet ends at the first segment shorter than 255. An
		# identification header is well under that in both codecs, so the first
		# segment is the whole packet and this loop reads its length rather than
		# assuming one.
		for i in segments:
			first_packet += buffer[table_at + i]
			if buffer[table_at + i] < 255:
				break
		if (flags & 0x02) == 0:
			# The first page that is not a beginning-of-stream page: every
			# identification header has been seen.
			return
		if payload_at + first_packet <= buffer.size():
			_read_ident(buffer.slice(payload_at, payload_at + first_packet), serial)
		at = payload_at + payload_size


## One identification packet, dispatched on its own magic.
##
## A packet whose magic is neither Theora's nor Vorbis's is left alone rather
## than reported: an Ogg file may legitimately carry a Skeleton index or a
## comment-only stream, and refusing the file because it has one would refuse
## sidecars that play perfectly.
func _read_ident(packet: PackedByteArray, serial: int) -> void:
	if packet.size() >= 42 and packet[0] == 0x80 \
			and packet.slice(1, 7).get_string_from_ascii() == "theora":
		_read_theora_ident(packet, serial)
	elif packet.size() >= 16 and packet[0] == 0x01 \
			and packet.slice(1, 7).get_string_from_ascii() == "vorbis":
		# Vorbis I §4.2.2: version (4, little-endian), channels (1), sample rate
		# (4, little-endian). Little-endian, unlike Theora's, which is why the
		# two are read with different helpers rather than one shared one.
		audio_channels = packet[11]
		audio_rate = int(packet.decode_u32(12))
		has_vorbis = audio_channels > 0 and audio_rate > 0


## The Theora identification header, Theora I §6.2.
##
## Every multi-byte field here is **big-endian**, which is the opposite of both
## the Ogg page header around it and the Vorbis header beside it. Reading one of
## them with `decode_u32` — Godot's little-endian reader, correct for the page
## header two functions up — turns a 352-pixel picture into 1,644,167,168 and a
## 25 fps clip into something with a duration of microseconds. The helpers below
## exist so that byte order is stated once per field group rather than inferred.
func _read_theora_ident(packet: PackedByteArray, serial: int) -> void:
	width = _be_u24(packet, 14)
	height = _be_u24(packet, 17)
	var frn := _be_u32(packet, 22)
	var frd := _be_u32(packet, 26)
	if frd > 0:
		fps = float(frn) / float(frd)
	# Bytes 40-41 pack the quality hint, the key frame granule shift and the
	# pixel format into one 16-bit big-endian word: QUAL is the top 6 bits,
	# KFGSHIFT the next 5, PF the next 2. Only KFGSHIFT is read, because it is
	# the one the granule position cannot be interpreted without.
	var packed := _be_u16(packet, 40)
	_kfgshift = (packed >> 5) & 0x1F
	_theora_serial = serial
	has_theora = width > 0 and height > 0 and fps > 0.0


## Frames decoded by the last page of the Theora stream.
##
## The tail is scanned forwards for every `OggS` that parses as a page header of
## this stream, and the **highest** granule position wins rather than the last
## one found. That is deliberate: a page's payload can contain the four bytes
## `OggS` by chance, and a false page parsed out of compressed video data yields
## an arbitrary serial that almost never matches — but "almost never" is not
## "never", and taking the maximum means such a hit can only ever be ignored
## when it is behind the real one. A false hit *ahead* of the real one would
## overstate the duration, and the version-byte and segment-count validation
## below is what rejects those: a random 27 bytes passes all three tests with a
## probability of about one in sixty thousand per candidate.
func _frames_from_tail(buffer: PackedByteArray) -> int:
	var best := 0
	var at := 0
	while at + PAGE_HEADER <= buffer.size():
		if buffer.decode_u32(at) != 0x5367674F:
			at += 1
			continue
		if buffer[at + 4] != 0 or buffer[at + 5] > 0x07:
			at += 1
			continue
		var segments := buffer[at + 26]
		if at + PAGE_HEADER + segments > buffer.size():
			at += 1
			continue
		if int(buffer.decode_u32(at + 14)) == _theora_serial:
			# The granule position is 64-bit and signed: -1 means "no packet
			# finished on this page", which is what a header page carries, and
			# reading it unsigned would make it the largest number in the file.
			var granule := buffer.decode_s64(at + 6)
			if granule >= 0:
				var mask := (1 << _kfgshift) - 1
				best = maxi(best, int((granule >> _kfgshift) + (granule & mask)))
		at += PAGE_HEADER + segments
	return best


func backend() -> String:
	return BACKEND


## Nothing to release: `open` reads two windows of the file and closes the handle
## before it returns, because everything this reader answers is in the headers
## and the last page. Present so that `preview/video.gd:release` can close every
## reader it holds without asking which kind each one is — the alternative is a
## type test at a call site whose whole job is not to have one.
func close() -> void:
	pass


static func _be_u16(b: PackedByteArray, at: int) -> int:
	if at + 2 > b.size():
		return 0
	return (b[at] << 8) | b[at + 1]


static func _be_u24(b: PackedByteArray, at: int) -> int:
	if at + 3 > b.size():
		return 0
	return (b[at] << 16) | (b[at + 1] << 8) | b[at + 2]


static func _be_u32(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return 0
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]
