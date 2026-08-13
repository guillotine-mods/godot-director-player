extends RefCounted
## A RIFF AVI reader and a Microsoft RLE (`mrle`, `BI_RLE8`) decoder, in
## GDScript against stock Godot.
##
## ## Why this file exists at all, when `docs/DIGITAL_VIDEO.md` says not to write
## ## a decoder
##
## That document costs four options and recommends exactly one piece of decoder
## work — §4 option **C1** — on the grounds that MS-RLE is *not a codec*. It is a
## run-length encoding: two bytes per opcode, no transform, no motion vectors, no
## entropy coder. `image/codecs/msrle.cpp:MSRLEDecoder::decode8` is the whole of
## the reference's implementation and it is 80 lines. The MPEG-1 half (option C2)
## is a different proposition and is deliberately **not** here: it needs an IDCT
## and variable-length codes, and the only realistic shape for it is a native
## dependency this project does not have and must not acquire.
##
## The census that justifies the split is in that document: **both** `#digitalVideo`
## members in all eight corpora are one file, `itamar-magichat/logo/logo.avi`, and
## it is 640x480 MS-RLE, 112 frames, 1000/90 fps, with 8-bit unsigned PCM at
## 22050 Hz. So this file closes the whole of cast type 10 for this tree, and it
## adds nothing to the project's dependencies: no GDExtension, no addon, no
## native code, no FFmpeg.
##
## ## Frames on demand, and why that is not an optimisation
##
## 112 frames of 640x480 at RGBA8 is **137 MB** resident, and at the 8-bit indices
## the file actually stores it is still 34 MB. Decoding the lot at load time would
## stall the movie for as long as it takes and then hold the memory for the whole
## session, for a ten-second logo. So this decodes **one frame at a time, on
## demand, by time**, and holds exactly one RGBA buffer (1.2 MB at 640x480) plus
## the file handle.
##
## The cost of that choice is that MS-RLE frames are *deltas*: frame N is
## expressed against frame N-1, so a decoder that can only move forward one frame
## at a time is the natural fit and a random seek is not free. `frame_at` handles
## both — a step to `_frame + 1` applies one delta, and any other target replays
## from the last key frame the index marks. Sequential playback, which is what a
## movie does, is therefore O(1) per frame.
##
## ## What is measured and what is not
##
## Measured against `logo.avi` by `tools/avi_decode.gd`: every one of the 112
## frames decodes, the frame count and the picture size agree with three
## independent statements of them inside the file (`avih`, the video `strh`'s
## `dwLength` and `rcFrame`, and the `strf` `BITMAPINFOHEADER`), the index's
## entry count matches the chunks found by walking `movi`, and the per-frame
## decode cost is reported so that "does it hold 11.11 fps" is a number rather
## than a hope.
##
## **Unexercised and therefore unverified**: 4-bit MS-RLE (`BI_RLE4`), which the
## reference also refuses (`decodeFrame` errors on anything but 8), uncompressed
## `BI_RGB` AVI, palette-change chunks (`##pc`), OpenDML `indx`/`ix##` indices,
## and any AVI with more than one video stream. Each is refused with a named
## error rather than mis-decoded, which is the same rule the rest of this port
## follows: a confident wrong answer is worse than an absent one.
##
## Cited by file and function at ScummVM 805f259a, per `AGENTS.md`; no code is
## copied. `video/avi_decoder.cpp` for the container walk (`parseNextChunk`,
## `handleStreamHeader`, `handleList`, `readOldIndex`, `seekIntern`) and
## `image/codecs/msrle.cpp:MSRLEDecoder::decode8` for the run-length expansion.

const SoundMember := preload("res://director/director_sound.gd")

## Which playback path `preview/video.gd` drives this reader with — this one
## decodes a frame at a time on demand and hands its soundtrack over as one
## `AudioStreamWAV`, where the Theora reader beside it (`director_ogg.gd`) only
## reads headers and leaves both to Godot's own `VideoStreamPlayer`. Named on the
## reader rather than tested with `is` at the call site, because a caller that
## asked "is this an `Avi`" would have to preload both files to ask about either.
const BACKEND := "avi"

## `dwFlags` bit 4 of an `idx1` entry: this chunk is a key frame. ScummVM calls
## it `AVIIF_INDEX` (`video/avi_decoder.h`); the AVI documentation calls it
## `AVIIF_KEYFRAME`. Same bit, and the reference's own comment — "the first frame
## has to be a keyframe" — is reproduced in `_key_at_or_before`.
const AVIIF_KEYFRAME := 0x10

## `BITMAPINFOHEADER.biCompression` values this reader understands. `BI_RGB` is
## carried so that an uncompressed AVI is *named* rather than silently decoded as
## RLE, which is what reading the chunk type instead of the header would do.
const BI_RGB := 0
const BI_RLE8 := 1

## MS-RLE's five opcodes, as the reference's `decode8` branches on them. A pair
## `(count, value)`: `count > 0` is a run, and `count == 0` makes `value` the
## escape.
const ESCAPE_END_OF_LINE := 0
const ESCAPE_END_OF_IMAGE := 1
const ESCAPE_DELTA := 2

# ------------------------------------------------------------------ what it found

var error: String = ""
var path: String = ""
var width: int = 0
var height: int = 0
## `dwTotalFrames` cross-checked against the number of video chunks the index
## holds. `_frames.size()` is the authority; this is what the header claimed.
var declared_frames: int = 0
var frame_count: int = 0
## `dwRate / dwScale` of the video stream, which is the only statement of the
## frame rate that is exact — `avih`'s `dwMicroSecPerFrame` is the same number
## rounded to a microsecond.
var fps: float = 0.0
var duration_ms: float = 0.0
var video_fourcc: String = ""
var compression: int = -1
var bits_per_pixel: int = 0
## RGB triples, 256 entries, out of the `strf` colour table. The AVI carries its
## own palette and it is the one the pictures are numbers in — **not** the cast
## member's and not the stage's. Director dithered these onto its 8-bit stage
## (`castmember/digitalvideo.h:_ditheringPalette`); this port composites in RGB
## and has no such step to make.
var palette: PackedByteArray = PackedByteArray()

var audio_rate: int = 0
var audio_bits: int = 0
var audio_channels: int = 0
var audio_format: int = 0

# ------------------------------------------------------------------ private

var _file: FileAccess = null
## One entry per video chunk, in presentation order:
## `{"offset": file position of the chunk header, "size", "key"}`.
var _frames: Array[Dictionary] = []
var _audio_chunks: Array[Dictionary] = []
var _video_stream: int = -1
var _audio_stream: int = -1
## The frame currently in `_rgba`, or -1 for "nothing decoded yet".
var _frame: int = -1
## The picture, **bottom-up** — row 0 of this buffer is the bottom row of the
## image, which is the order a Windows DIB stores and the order MS-RLE writes in.
## Kept that way and flipped by `Image.flip_y` (native) rather than by a GDScript
## row shuffle, so the decoder's destination pointer stays monotonically
## increasing and the whole append strategy below works.
var _rgba: PackedByteArray = PackedByteArray()
## Palette index -> the four RGBA bytes packed little-endian, for `encode_u32`.
var _pal_u32: PackedInt64Array = PackedInt64Array()
## Palette index -> 256 pixels of that colour, so a run is one `slice` and one
## `append_array` — a memcpy — instead of up to 255 GDScript stores. 256 KB, and
## it is what makes a 640x480 key frame affordable in this language at all.
var _runs: Array[PackedByteArray] = []
var _decode_us: int = 0


## Open and index an AVI. False leaves `error` set and nothing allocated.
func open(file_path: String) -> bool:
	close()
	error = ""
	path = file_path
	_file = FileAccess.open(file_path, FileAccess.READ)
	if _file == null:
		error = "cannot open %s (%d)" % [file_path, FileAccess.get_open_error()]
		return false
	_file.big_endian = false
	if _file.get_length() < 12:
		error = "%s is %d bytes" % [file_path, _file.get_length()]
		close()
		return false
	if _tag(_file.get_buffer(4)) != "RIFF":
		error = "%s is not RIFF" % file_path
		close()
		return false
	var riff_size := _file.get_32()
	if _tag(_file.get_buffer(4)) != "AVI ":
		error = "%s is RIFF but not AVI" % file_path
		close()
		return false
	var end: int = mini(_file.get_length(), 8 + riff_size)
	_stream_seen = 0
	_walk(8 + 4, end)
	# `idx1` sits *after* `movi`, so which of the two indexes to believe cannot be
	# decided until the whole file has been walked. See `_settle_index`.
	_settle_index()
	if not error.is_empty():
		close()
		return false
	if _video_stream < 0:
		error = "%s has no video stream" % file_path
		close()
		return false
	if compression != BI_RLE8:
		error = "%s: biCompression %d ('%s') is not BI_RLE8" % [
			file_path, compression, video_fourcc]
		close()
		return false
	if bits_per_pixel != 8:
		error = "%s: %d-bit MS-RLE is not supported" % [file_path, bits_per_pixel]
		close()
		return false
	if width <= 0 or height <= 0:
		error = "%s: %dx%d" % [file_path, width, height]
		close()
		return false
	frame_count = _frames.size()
	if frame_count == 0:
		error = "%s: no video chunks" % file_path
		close()
		return false
	# Duration from the frame count and the stream's own rate, not from `avih`.
	# `dwRate / dwScale` is 1000/90 here and exact; `dwMicroSecPerFrame` is the
	# same rate rounded to 90,000 us, which over 112 frames is a 0.7 ms drift --
	# small, and there is no reason to carry the lossy one when the exact one is
	# in the same header.
	if fps > 0.0:
		duration_ms = frame_count * 1000.0 / fps
	_build_palette_tables()
	_rgba.resize(width * height * 4)
	_rgba.fill(0)
	_frame = -1
	return true


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
	_frames.clear()
	_audio_chunks.clear()
	_indexed_frames.clear()
	_indexed_audio.clear()
	_walked_frames.clear()
	_walked_audio.clear()
	_rgba = PackedByteArray()
	_runs.clear()
	_pal_u32 = PackedInt64Array()
	_video_stream = -1
	_audio_stream = -1
	_stream_seen = 0
	_frame = -1


func is_open() -> bool:
	return _file != null


func backend() -> String:
	return BACKEND


## Which frame is on screen at `ms` into the movie.
##
## Floored, not rounded: frame N covers `[N/fps, (N+1)/fps)`, so a playhead one
## microsecond into the movie is showing frame 0 and not frame 1. Clamped to the
## last frame rather than wrapping — looping is the *member's* `the loop`, and a
## decoder that wrapped on its own would make a non-looping video restart.
func frame_index_at(ms: float) -> int:
	if fps <= 0.0 or frame_count <= 0:
		return 0
	return clampi(int(floor(ms * fps / 1000.0)), 0, frame_count - 1)


## The picture at a frame index, as a fresh `Image`.
##
## Null when the index is out of range or the file is closed. The returned image
## is a copy: `Image.create_from_data` in Godot 4 does not alias the buffer, and
## the caller is free to keep it while the next frame is decoded over `_rgba`.
func frame_at(index: int) -> Image:
	if _file == null or index < 0 or index >= frame_count:
		return null
	_decode_through(index)
	var image := Image.create_from_data(
		width, height, false, Image.FORMAT_RGBA8, _rgba)
	# The DIB is bottom-up and so is `_rgba` (see the field's comment). One native
	# flip is cheaper than reordering 480 rows in GDScript on every frame, and it
	# keeps the RLE destination monotonic, which is what lets the runs be memcpys.
	image.flip_y()
	return image


## Microseconds spent inside `_decode_frame` since `open`. Read by
## `tools/avi_decode.gd` so that "can it hold 11.11 fps" is measured rather than
## asserted, and by nothing in the player.
func decode_cost_us() -> int:
	return _decode_us


## The soundtrack, as one `AudioStreamWAV`, or null when there is no audio stream
## this reader can turn into one.
##
## **Built whole rather than streamed**, which is the one place this file spends
## memory it could have avoided: `logo.avi` is 172,022 bytes of 8-bit mono PCM,
## and an `AudioStreamPlayer` in Godot takes a stream and not a pull callback, so
## a chunk-at-a-time feed would need a `AudioStreamGenerator` and a mixing thread
## to do what one buffer does. 168 KB against 1.7 MB of file is not the cost worth
## engineering around; a feature-length AVI would be, and this is where that
## decision is written down rather than discovered.
##
## 8-bit AVI PCM is **unsigned offset binary** and `AudioStreamWAV.FORMAT_8_BITS`
## is signed, so the samples are rebiased through the same helper the cast-member
## sound decoder uses — one conversion, not two that can drift apart.
func audio_stream() -> AudioStreamWAV:
	if _file == null or _audio_chunks.is_empty():
		return null
	if audio_format != 1:
		# WAVE_FORMAT_PCM is 1. Anything else is ADPCM, mu-law or a codec, and
		# naming it is more use than handing the mixer bytes it will play as noise.
		return null
	if audio_bits != 8 and audio_bits != 16:
		return null
	var payload := PackedByteArray()
	for entry_value in _audio_chunks:
		var entry: Dictionary = entry_value
		_file.seek(int(entry["offset"]) + 8)
		payload.append_array(_file.get_buffer(int(entry["size"])))
	if payload.is_empty():
		return null
	var stream := AudioStreamWAV.new()
	stream.mix_rate = audio_rate
	stream.stereo = audio_channels >= 2
	if audio_bits == 8:
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.data = SoundMember._unsigned_to_signed(payload)
	else:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		# WAV 16-bit is little-endian signed, which is what `AudioStreamWAV` wants,
		# so unlike the Mac `snd` path there is nothing to swap.
		stream.data = payload
	return stream


# ================================================================ the container
#
# `video/avi_decoder.cpp:parseNextChunk` and `handleList` are the model. The one
# structural difference is that this walks with explicit bounds rather than a
# stream position, because `FileAccess` has no end-of-chunk concept and a
# malformed size would otherwise walk off into the next list.


func _walk(at: int, end: int) -> void:
	while at + 8 <= end:
		_file.seek(at)
		var tag := _tag(_file.get_buffer(4))
		var size := _file.get_32()
		var body := at + 8
		if size < 0 or body + size > _file.get_length():
			# A truncated tail is not fatal: everything already indexed stays
			# valid, and refusing the whole file would lose a playable movie over
			# a trailing byte. Reported through `error` only when nothing usable
			# was found, which `open` decides.
			return
		match tag:
			"RIFF", "LIST":
				var list_type := _tag(_file.get_buffer(4))
				if list_type == "movi":
					_index_movi(body + 4, body + size)
				elif list_type == "INFO" or list_type == "PRMI":
					pass  # metadata; the reference skips these by name too
				else:
					_walk(body + 4, body + size)
			"strh":
				_read_stream_header(body, size)
			"strf":
				_read_stream_format(body, size)
			"idx1":
				_read_old_index(body, size)
		# Every RIFF chunk is padded to an even length, and the pad byte is not
		# counted in the size. Missing this is how a walk lands one byte inside
		# the next tag and reports "Unknown tag".
		at = body + size + (size & 1)


## `strh` — which stream this is and how fast it runs.
##
## Streams are numbered by the order their `strl` lists appear, which is the same
## number the `##dc` / `##wb` chunk ids carry. `_stream_seen` is that counter and
## it is the only thing that ties a header to its chunks.
var _stream_seen: int = 0

func _read_stream_header(at: int, size: int) -> void:
	if size < 40:
		return
	_file.seek(at)
	var kind := _tag(_file.get_buffer(4))
	var handler := _tag(_file.get_buffer(4))
	_file.get_32()  # dwFlags
	_file.get_16()  # wPriority
	_file.get_16()  # wLanguage
	_file.get_32()  # dwInitialFrames
	var scale := _file.get_32()
	var rate := _file.get_32()
	_file.get_32()  # dwStart
	var length := _file.get_32()
	var index := _stream_seen
	_stream_seen += 1
	if kind == "vids":
		if _video_stream >= 0:
			# A second video stream would need a second decoder state and a rule
			# for which one a sprite shows. Refused rather than half-supported.
			error = "%s has more than one video stream" % path
			return
		_video_stream = index
		video_fourcc = handler
		declared_frames = length
		if scale > 0:
			fps = float(rate) / float(scale)
	elif kind == "auds":
		if _audio_stream < 0:
			_audio_stream = index


## `strf` — the format the stream's chunks are in. A `BITMAPINFOHEADER` plus its
## colour table for video, a `WAVEFORMAT` for audio.
##
## Which stream it describes is **the one whose `strh` was read last**, because a
## `strf` carries no stream number of its own: RIFF says which stream it belongs
## to by putting it inside the same `strl` list, immediately after the `strh`
## (`video/avi_decoder.cpp:handleStreamFormat` reads it the same way, off the
## header it has just parsed). A file that reversed the two would mis-assign it,
## and there is no field in either chunk that could catch that.
func _read_stream_format(at: int, size: int) -> void:
	var index := _stream_seen - 1
	if index == _video_stream and size >= 40:
		_file.seek(at)
		_file.get_32()  # biSize
		width = _file.get_32()
		height = _file.get_32()
		_file.get_16()  # biPlanes
		bits_per_pixel = _file.get_16()
		compression = _file.get_32()
		_file.get_32()  # biSizeImage
		_file.get_32()  # biXPelsPerMeter
		_file.get_32()  # biYPelsPerMeter
		var used := _file.get_32()
		_file.get_32()  # biClrImportant
		# `biClrUsed` of 0 means "all of them" for an 8-bit DIB, which is 256.
		if used <= 0 or used > 256:
			used = 256
		var table_bytes: int = mini(used * 4, size - 40)
		var table := _file.get_buffer(maxi(table_bytes, 0))
		palette.resize(256 * 3)
		palette.fill(0)
		var entries: int = table.size() / 4
		for i in entries:
			# RGBQUAD is blue, green, red, reserved -- in that order, which is the
			# opposite of the RGB triples this port's own palettes carry. Reading
			# it straight through is how a decoder comes out looking channel-swapped
			# in exactly the way that reads as "the palette is wrong".
			palette[i * 3] = table[i * 4 + 2]
			palette[i * 3 + 1] = table[i * 4 + 1]
			palette[i * 3 + 2] = table[i * 4]
	elif index == _audio_stream and size >= 16:
		_file.seek(at)
		audio_format = _file.get_16()
		audio_channels = _file.get_16()
		audio_rate = _file.get_32()
		_file.get_32()  # nAvgBytesPerSec
		_file.get_16()  # nBlockAlign
		audio_bits = _file.get_16()


## Walk `movi` itself, which is the fallback for a file with no `idx1` and the
## cross-check for one that has.
func _index_movi(at: int, end: int) -> void:
	if not _walked_frames.is_empty() or _movi_end > 0:
		# A second `movi` is OpenDML -- an AVI over 2 GB, split into `RIFF AVIX`
		# segments each with its own movie list and its own `ix##` index. Refused
		# by name rather than absorbed, because absorbing it silently is the
		# failure mode: this reader would keep the first segment's frames, report a
		# frame count that disagrees with `avih`, and play the first two gigabytes
		# of a longer film as though that were the whole of it. Nothing in this
		# corpus is remotely near the limit -- the one AVI is 1.7 MB.
		error = "%s is OpenDML (more than one `movi` list)" % path
		return
	_movi_start = at
	_movi_end = end
	var walked: Array[Dictionary] = []
	var audio: Array[Dictionary] = []
	while at + 8 <= end:
		_file.seek(at)
		var id := _tag(_file.get_buffer(4))
		var size := _file.get_32()
		if size < 0 or at + 8 + size > end:
			break
		if id == "LIST" or id == "RIFF":
			# A `rec ` list groups the chunks of one frame; its members are the
			# real chunks, so descend rather than skip.
			at += 12
			continue
		var stream := _stream_of(id)
		var kind := id.substr(2, 2)
		if stream == _video_stream and (kind == "dc" or kind == "db"):
			# `db` is nominally an uncompressed DIB and `dc` a compressed one, and
			# the reference decodes both through the codec `biCompression` named
			# (`AVIVideoTrack::decodeFrame` hands the chunk straight to it). This
			# file's own frame 0 is tagged `00db` and is 24,536 bytes of RLE for a
			# 307,200-pixel picture, so believing the tag over the header would
			# refuse the only key frame it has.
			walked.append({"offset": at, "size": size, "key": walked.is_empty()})
		elif stream == _audio_stream and kind == "wb":
			audio.append({"offset": at, "size": size})
		at += 8 + size + (size & 1)
	_walked_frames = walked
	_walked_audio = audio


var _movi_start: int = 0
var _movi_end: int = 0
var _walked_frames: Array[Dictionary] = []
var _walked_audio: Array[Dictionary] = []


## `idx1` — the classic AVI index, 16 bytes per entry.
##
## Offsets in it are *usually* relative to the `movi` four-cc rather than to the
## file, and some writers store them absolute. The reference decides by testing
## the first entry against `_movieListStart` (`readOldIndex`), and that test is
## reproduced here rather than replaced by a heuristic: an index read at the wrong
## base seeks into the middle of a chunk and decodes noise.
##
## The index is preferred over the `movi` walk for one reason only — it is the
## only statement of **which frames are key frames**, which is what makes a seek
## possible at all. When it disagrees with the walk about how many video chunks
## there are, the walk wins and the index's key flags are dropped, because the
## walk is reading the chunks themselves.
func _read_old_index(at: int, size: int) -> void:
	var entries: int = size / 16
	if entries <= 0:
		return
	_file.seek(at)
	var raw := _file.get_buffer(entries * 16)
	if raw.size() < 16:
		return
	var first_offset := raw.decode_u32(8)
	var absolute := first_offset == _movi_start
	var base: int = 0 if absolute else _movi_start - 4
	var indexed: Array[Dictionary] = []
	var audio: Array[Dictionary] = []
	for i in entries:
		var o := i * 16
		var id := raw.slice(o, o + 4).get_string_from_ascii()
		var flags := raw.decode_u32(o + 4)
		var offset := int(raw.decode_u32(o + 8)) + base
		var chunk_size := int(raw.decode_u32(o + 12))
		if id == "rec ":
			continue
		var stream := _stream_of(id)
		var kind := id.substr(2, 2)
		if stream == _video_stream and (kind == "dc" or kind == "db"):
			indexed.append({
				"offset": offset, "size": chunk_size,
				# The reference's own rule: the flag decides, except that frame 0
				# is a key frame whatever the flag says, because a delta against
				# nothing is not decodable.
				"key": (flags & AVIIF_KEYFRAME) != 0 or indexed.is_empty(),
			})
		elif stream == _audio_stream and kind == "wb":
			audio.append({"offset": offset, "size": chunk_size})
	_indexed_frames = indexed
	_indexed_audio = audio


var _indexed_frames: Array[Dictionary] = []
var _indexed_audio: Array[Dictionary] = []


## Which of the two lists to trust, decided after the whole file has been read
## because `idx1` comes *after* `movi` and the walk is what it is checked against.
func _settle_index() -> void:
	if _indexed_frames.size() == _walked_frames.size() and not _indexed_frames.is_empty():
		_frames = _indexed_frames
		_audio_chunks = _indexed_audio if _indexed_audio.size() == _walked_audio.size() \
			else _walked_audio
		return
	_frames = _walked_frames
	_audio_chunks = _walked_audio


func _stream_of(id: String) -> int:
	if id.length() < 2:
		return -1
	var tens := id.unicode_at(0) - 48
	var units := id.unicode_at(1) - 48
	if tens < 0 or tens > 9 or units < 0 or units > 9:
		return -1
	return tens * 10 + units


# =================================================================== the codec
#
# `image/codecs/msrle.cpp:MSRLEDecoder::decode8`. The algorithm is that function's
# and the citation is the whole of the debt; the *strategy* below is not, and is
# where the two implementations differ on purpose.
#
# The reference writes one byte per pixel into a CLUT8 surface and lets the
# platform's blitter apply the palette. This port composites in RGBA, so a
# per-pixel palette lookup would be 307,200 GDScript iterations per frame at
# 640x480 -- which at 11.11 fps is 3.4 Mpix/s and is exactly the language this
# port is written in refusing.
#
# So the frame is **rebuilt by appending memcpys** instead. MS-RLE's destination
# pointer only ever moves forward (a run advances it, an end-of-line moves to the
# next row, a delta skips forward on both axes), so every frame is a sequence of
# three kinds of piece in increasing address order:
#
#   * a **run**   -- `_runs[value]` sliced to length; one memcpy
#   * a **skip**  -- untouched pixels, which are the *previous* frame's, so the
#                    piece is a slice of `_rgba`; one memcpy
#   * a **literal** -- the only per-pixel work, and the only place the palette is
#                    consulted at decode time
#
# That the destination is monotonic is what makes this correct rather than clever,
# and it is stated here because it is the assumption the whole strategy rests on.
# `_emit_gap` asserts it by construction: it can only ever copy *forwards*.


func _build_palette_tables() -> void:
	_pal_u32.resize(256)
	_runs.clear()
	_runs.resize(256)
	for i in 256:
		var r := int(palette[i * 3])
		var g := int(palette[i * 3 + 1])
		var b := int(palette[i * 3 + 2])
		# Little-endian RGBA8, which is the byte order `Image.FORMAT_RGBA8` reads
		# and the order `PackedByteArray.encode_u32` writes.
		_pal_u32[i] = r | (g << 8) | (b << 16) | (255 << 24)
		var run := PackedByteArray()
		run.resize(256 * 4)
		for p in 256:
			run.encode_u32(p * 4, _pal_u32[i])
		_runs[i] = run


## Bring `_rgba` to `target`, applying as few deltas as possible.
func _decode_through(target: int) -> void:
	var from := _frame + 1
	if target < _frame or _frame < 0:
		from = _key_at_or_before(target)
		if from == 0:
			_rgba.fill(0)
		_frame = from - 1
	for i in range(from, target + 1):
		_decode_frame(i)
		_frame = i


## The last frame at or before `index` that can be decoded without a predecessor.
func _key_at_or_before(index: int) -> int:
	var i: int = mini(index, frame_count - 1)
	while i > 0:
		if bool(_frames[i].get("key", false)):
			return i
		i -= 1
	return 0


func _decode_frame(index: int) -> void:
	var began := Time.get_ticks_usec()
	var entry: Dictionary = _frames[index]
	var size := int(entry["size"])
	if size <= 0:
		# A zero-length video chunk means "no change from the previous frame",
		# which is a real and common encoding of a still moment. Leaving `_rgba`
		# alone is the decode.
		_decode_us += Time.get_ticks_usec() - began
		return
	_file.seek(int(entry["offset"]) + 8)
	var chunk := _file.get_buffer(size)
	_rgba = _rle8(chunk)
	_decode_us += Time.get_ticks_usec() - began


## One MS-RLE frame, expanded over the previous one.
##
## Returns the new bottom-up RGBA buffer. `_rgba` is read as the previous frame
## and is not written, so a decode that runs off the end of the data leaves the
## last good picture on screen instead of a half-drawn one.
func _rle8(chunk: PackedByteArray) -> PackedByteArray:
	var pixels := width * height
	var pieces: Array[PackedByteArray] = []
	# The destination, in pixels, into the bottom-up buffer. `u` is the row
	# counted from the bottom, which is the reference's `y` counted from `h - 1`
	# downwards; `x` is the column. `dest` is derived from both and is what the
	# gap filling is expressed in.
	var u := 0
	var x := 0
	var dest := 0
	var emitted := 0
	var at := 0
	var size := chunk.size()
	while at + 1 < size:
		var count := int(chunk[at])
		var value := int(chunk[at + 1])
		at += 2
		if count > 0:
			# A run. The reference refuses one that would overflow the surface and
			# does *not* advance the pointer past it (`msrle.cpp`, "Run data is
			# beyond picture bounds" and the `output + count > output_end` guard);
			# the same refusal is here so that a malformed stream cannot smear.
			if u >= height:
				break
			if dest + count > pixels:
				continue
			var gap := _gap_piece(emitted, dest)
			if not gap.is_empty():
				pieces.append(gap)
				emitted = dest
			pieces.append(_runs[value].slice(0, count * 4))
			dest += count
			emitted = dest
			x += count
			continue
		match value:
			ESCAPE_END_OF_LINE:
				x = 0
				u += 1
				dest = u * width
			ESCAPE_END_OF_IMAGE:
				break
			ESCAPE_DELTA:
				if at + 1 >= size:
					break
				var dx := int(chunk[at])
				var dy := int(chunk[at + 1])
				at += 2
				x += dx
				u += dy
				if u >= height:
					break
				dest = u * width + x
			_:
				# A literal run of `value` pixels, padded to an even byte count.
				var n := value
				if u >= height:
					break
				if dest + n > pixels or at + n > size:
					# The reference skips the payload and continues here rather
					# than aborting, on the grounds that a later opcode may still
					# be in range. Note that it does *not* skip the alignment pad
					# in this path; that is reproduced rather than corrected,
					# because it can only fire on data no encoder produces and a
					# silent divergence from the reference is worth less than the
					# byte.
					at += n
					continue
				var gap := _gap_piece(emitted, dest)
				if not gap.is_empty():
					pieces.append(gap)
					emitted = dest
				var literal := PackedByteArray()
				literal.resize(n * 4)
				for i in n:
					literal.encode_u32(i * 4, _pal_u32[chunk[at + i]])
				pieces.append(literal)
				at += n + (n & 1)
				dest += n
				emitted = dest
				x += n
	var tail := _gap_piece(emitted, pixels)
	if not tail.is_empty():
		pieces.append(tail)
	var out := PackedByteArray()
	for piece in pieces:
		out.append_array(piece)
	# A frame whose opcodes did not account for the whole surface is padded from
	# the previous one above, so this can only be short if `_rgba` itself was --
	# which `open` makes impossible. Guarded anyway, because handing
	# `Image.create_from_data` a short buffer is a hard error rather than a
	# wrong picture.
	if out.size() != pixels * 4:
		out.resize(pixels * 4)
	return out


## The untouched pixels between two destinations, taken from the previous frame.
##
## Empty for an empty span, so the caller does not append a zero-length piece per
## opcode. This is the delta half of MS-RLE and it is the reason a talking-head
## frame costs almost nothing: the pixels nobody wrote are one `slice`.
func _gap_piece(from_pixel: int, to_pixel: int) -> PackedByteArray:
	if to_pixel <= from_pixel:
		return PackedByteArray()
	return _rgba.slice(from_pixel * 4, to_pixel * 4)


# ------------------------------------------------------------------ bytes

static func _tag(raw: PackedByteArray) -> String:
	return raw.get_string_from_ascii() if raw.size() == 4 else ""
