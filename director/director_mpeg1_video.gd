extends RefCounted
## An MPEG-1 **video** decoder (ISO/IEC 11172-2) in GDScript against stock Godot:
## variable-length codes, dequantisation, the 8x8 inverse DCT, motion
## compensation on 16x16 macroblocks, and YCbCr 4:2:0 to RGB.
##
## ## Why this exists when `docs/DIGITAL_VIDEO.md` refused it
##
## That document's §4C2 costs an MPEG-1 decoder in GDScript at "2.5 Mpix/s of
## IDCT output" and refuses it; §4D takes a plugin instead; §9 then measures the
## plugin decoding **0 of the 23 media files in this tree**, because
## EIRTeam.FFmpeg's bundled build is the `lgpl-godot` variant with
## `--disable-demuxers --disable-decoders` and no MPEG-PS demuxer re-enabled. So
## after all four options were tried, the only thing that put pictures on the
## stage was a hand-made Ogg Theora sidecar the owner has to produce by
## transcoding — and the owner has said plainly that transcoding is not what they
## want.
##
## `director/director_avi.gd` is the precedent and its header states the split
## this file crosses on purpose: MS-RLE "is not a codec", MPEG-1 "needs an IDCT
## and variable-length codes, and the only realistic shape for it is a native
## dependency this project does not have and must not acquire". The second half
## of that sentence is what turned out to be wrong — not because GDScript became
## fast, but because the native dependency was acquired, measured, and decoded
## nothing. What is left is this.
##
## **The cost is real and is measured rather than hidden.** `tools/mpeg1_decode.gd`
## reports milliseconds per picture for every clip it is pointed at, split by
## picture type, and prints the fraction of real time it achieves. A clip that
## plays slowly is worth more than one that does not play; a clip that plays
## slowly while the port claims it plays at 25 fps is worth less than either, so
## the number is printed and not asserted against a threshold it cannot meet.
##
## ## What is implemented
##
## The whole of the 11172-2 video layer that a program stream can contain:
##
##   * **sequence header** — size, pel aspect ratio, frame rate, bit rate, VBV
##     buffer size, the constrained-parameters flag, and both quantiser matrices,
##     including the mid-stream re-send that a long clip is allowed to make;
##   * **group of pictures** — the time code, `closed_gop` and `broken_link`,
##     both of which decide what a seek into the middle of a stream may assume;
##   * **picture** — `temporal_reference`, the coding type, the VBV delay, and the
##     forward and backward `f_code`s;
##   * **slice** — the vertical position, the quantiser scale, and the extra
##     information bytes;
##   * **macroblock** — address increments and escapes, all four `macroblock_type`
##     tables (I, P, B and D), per-macroblock quantiser changes, motion vectors
##     with the full `f_code` reconstruction, the coded block pattern, and the
##     skipped-macroblock rules, which differ between P and B pictures and are the
##     single most common way a decoder is subtly wrong;
##   * **block** — the DC size tables for luma and chroma, the DC predictor and
##     its three reset conditions, table B.14 for the coefficients including the
##     first-coefficient special case in non-intra blocks and the two-stage
##     escape, both dequantisation formulae with their "oddification" step, and
##     the coefficient clamp;
##   * **prediction** — forward, backward and interpolated, at full and half pel
##     on both axes, with chroma vectors derived by the truncating halving the
##     specification asks for.
##
## D-pictures (`picture_coding_type` 4) are decoded as well. Nothing in this
## corpus contains one and nothing since 1993 has produced one, and that is
## exactly `AGENTS.md`'s "build Director, not this game" applied one layer down:
## the format has them, so the decoder has them, and the comment says they are
## unverified rather than the code pretending they do not exist.
##
## ## What is not implemented, and why
##
##   * **The audio.** MPEG-1 Layer II is a second decoder — a 512-tap polyphase
##     synthesis filterbank at 44.1 kHz stereo, which is 45 million multiplies for
##     `intro.mpg` alone and would have to run before the first picture, inside a
##     property read. `director_mpeg1.gd` reads the audio frame header, so
##     `the sampleRate`, `the sampleSize` and `the channelCount of member` answer
##     the file's own numbers and `trackCount` counts the sound track that is
##     really there; `audio_stream()` answers null and the picture plays silent.
##     That is a named gap, not a claim that the file has no sound.
##   * **MPEG-2 video.** `sequence_extension` and everything under it is a
##     different specification. A stream carrying one is refused by name rather
##     than decoded as MPEG-1, which would produce a picture that is wrong in a
##     way nothing reports.
##   * **Frame-rate scaling and pull-down.** MPEG-1 has no repeat_first_field, so
##     there is nothing to do here; it is named because its absence is a fact
##     about the format rather than about this file.
##
## ## The one thing a seek cannot recover
##
## A backward seek restarts at the last I picture the decoder has passed. When
## that picture's group of pictures declares `closed_gop = 0`, the B pictures
## coded immediately after it reference a picture from the *previous* group,
## which the restart does not have — so they are predicted from the backward
## reference alone and are wrong for as long as that lasts, which is at most the
## B-picture run at the head of one group. Sequential playback never takes that
## path, and `_open_gop_frames` counts the pictures it happened to, so a harness
## can say how many rather than guess.
##
## No code is copied from anything. The tables are ISO/IEC 11172-2 Annex B — B.1
## through B.16 — and the reconstruction rules are §2.4.4; the integer IDCT is the
## classic separable row/column form whose fixed-point constants are
## `2048*sqrt(2)*cos(k*pi/16)`, and `tools/mpeg1_decode.gd` asserts it against a
## direct floating-point evaluation of the transform's own definition rather than
## against another implementation of it.

# ============================================================ format constants

const PICTURE_I := 1
const PICTURE_P := 2
const PICTURE_B := 3
const PICTURE_D := 4

const START_PICTURE := 0x00
const START_SLICE_FIRST := 0x01
const START_SLICE_LAST := 0xAF
const START_USER_DATA := 0xB2
const START_SEQUENCE := 0xB3
const START_EXTENSION := 0xB5
const START_SEQUENCE_END := 0xB7
const START_GOP := 0xB8

## `frame_rate_code` -> pictures per second. Table 2-6. The four fractional
## entries are the NTSC family and are exact ratios rather than the rounded
## decimals a reader expects: 24000/1001, not 23.976.
const FRAME_RATES := [
	0.0, 24000.0 / 1001.0, 24.0, 25.0, 30000.0 / 1001.0,
	30.0, 50.0, 60000.0 / 1001.0, 60.0,
]

## `pel_aspect_ratio` -> the height/width ratio of one sample. Table 2-4. Kept so
## that `director_mpeg1.gd` can report the shape of the picture honestly; nothing
## in this port stretches by it, because Director scaled a video sprite to its own
## rect and the two encodes in this corpus are square-pixel anyway.
const PEL_ASPECTS := [
	0.0, 1.0000, 0.6735, 0.7031, 0.7615, 0.8055, 0.8437, 0.8935,
	0.9157, 0.9815, 1.0255, 1.0695, 1.0950, 1.1575, 1.2015,
]

## Zigzag scan: `ZIGZAG[i]` is the raster position in the 8x8 block of the
## coefficient that arrives `i`th. Table 2-2 / Figure 2-6.
const ZIGZAG := [
	0, 1, 8, 16, 9, 2, 3, 10,
	17, 24, 32, 25, 18, 11, 4, 5,
	12, 19, 26, 33, 40, 48, 41, 34,
	27, 20, 13, 6, 7, 14, 21, 28,
	35, 42, 49, 56, 57, 50, 43, 36,
	29, 22, 15, 23, 30, 37, 44, 51,
	58, 59, 52, 45, 38, 31, 39, 46,
	53, 60, 61, 54, 47, 55, 62, 63,
]

## The default intra quantiser matrix, in **raster** order (Table 2-D.1). The
## bitstream sends a replacement in *zigzag* order, so `_load_matrix` de-zigzags
## it into this same order — one convention for both, decided here, because a
## decoder that mixed them produces a picture that is subtly soft rather than
## visibly broken.
const DEFAULT_INTRA_MATRIX := [
	8, 16, 19, 22, 26, 27, 29, 34,
	16, 16, 22, 24, 27, 29, 34, 37,
	19, 22, 26, 27, 29, 34, 34, 38,
	22, 22, 26, 27, 29, 34, 37, 40,
	22, 26, 27, 29, 32, 35, 40, 48,
	26, 27, 29, 32, 35, 40, 48, 58,
	26, 27, 29, 34, 38, 46, 56, 69,
	27, 29, 35, 38, 46, 56, 69, 83,
]

## IDCT fixed-point constants: `round(2048 * sqrt(2) * cos(k * PI / 16))`.
const W1 := 2841
const W2 := 2676
const W3 := 2408
const W5 := 1609
const W6 := 1108
const W7 := 565

## The clamp table's offset and mask. Big enough that every value a valid stream
## can produce lands inside it, and masked rather than clamped at the index so
## that a corrupt stream costs a wrong pixel and not a crash — the same trade
## `director_avi.gd:_rle8` makes when it refuses a run that would overflow.
const CLIP_OFFSET := 4096
const CLIP_MASK := 16383

# ================================================================ what it found

var error: String = ""

var width: int = 0
var height: int = 0
var mb_width: int = 0
var mb_height: int = 0
var fps: float = 0.0
var pel_aspect: float = 1.0
var bit_rate: int = 0
var vbv_buffer_size: int = 0
var constrained: bool = false

## Counts, for the harness rather than for the player.
var pictures_decoded: int = 0
var slices_decoded: int = 0
var macroblocks_decoded: int = 0
var skipped_macroblocks: int = 0
var gops_seen: int = 0
var sequence_headers_seen: int = 0
var type_counts := {PICTURE_I: 0, PICTURE_P: 0, PICTURE_B: 0, PICTURE_D: 0}
## Slices whose final bit position did not land on the byte before a start code.
## **The strongest correctness signal this decoder has**: every variable-length
## code in a slice is read in sequence with no length field anywhere, so a single
## wrong table entry desynchronises the reader and it stops landing on the next
## start code. Over the 39,402 slices of `heb/mainmenu/intro.mpg` that is 39,402
## independent checks of the whole VLC layer at once.
var desynced_slices: int = 0
var open_gop_frames: int = 0
## I pictures whose slices did not account for every macroblock.
##
## **Only I pictures**, and that distinction is the whole value of the counter.
## An intra picture has no reference to fall back on, so every one of its
## macroblocks must be coded and a short one is a decoder that lost its place. A
## P or B picture may legitimately leave macroblocks out of every slice — they
## keep whatever the reference had — and `heb/album/solution4.mpg` really does:
## 12,600 of 13,500 macroblock positions over 45 pictures, with not one
## desynchronised slice. A coverage threshold applied to all three types failed
## that file for being encoded efficiently.
var short_intra_pictures: int = 0
## The smallest fraction of a picture any one picture's slices covered, in
## percent. A finding rather than an assertion, for the reason above.
var least_coverage: int = 100
var decode_us: int = 0
var idct_us: int = 0

# ==================================================================== the state

var _es: PackedByteArray = PackedByteArray()
var _es_end: int = 0

# --- the bit reader. Inlined into this class rather than given one of its own,
# --- because every one of its operations happens millions of times per clip and
# --- a GDScript call across objects costs more than the work it would do.
var _pos: int = 0          ## next byte to shift into the cache
var _cache: int = 0        ## the low `_have` bits are unread, most significant first
var _have: int = 0

# --- picture buffers. Three sets: the past reference, the future reference and
# --- the picture being decoded. B pictures need all three at once, which is the
# --- reason for the third and the reason they cannot be decoded in place.
var _y_cur := PackedByteArray()
var _cb_cur := PackedByteArray()
var _cr_cur := PackedByteArray()
var _y_fwd := PackedByteArray()
var _cb_fwd := PackedByteArray()
var _cr_fwd := PackedByteArray()
var _y_bwd := PackedByteArray()
var _cb_bwd := PackedByteArray()
var _cr_bwd := PackedByteArray()
var _has_fwd: bool = false
var _has_bwd: bool = false

var _luma_w: int = 0
var _luma_h: int = 0
var _chroma_w: int = 0
var _chroma_h: int = 0

var _intra_matrix: PackedInt32Array = PackedInt32Array()
var _non_intra_matrix: PackedInt32Array = PackedInt32Array()

# --- per picture
var _picture_type: int = 0
var _temporal_reference: int = 0
var _full_pel_forward: bool = false
var _full_pel_backward: bool = false
## 2 when the picture's vectors are in whole pels, 1 otherwise. See `_read_motion`.
var _fwd_scale: int = 1
var _bwd_scale: int = 1
var _forward_f: int = 1
var _forward_r_size: int = 0
var _backward_f: int = 1
var _backward_r_size: int = 0

# --- per slice / macroblock
var _quant: int = 1
var _mb_address: int = 0
var _dc_y: int = 0
var _dc_cb: int = 0
var _dc_cr: int = 0
var _mv_fwd_x: int = 0
var _mv_fwd_y: int = 0
var _mv_bwd_x: int = 0
var _mv_bwd_y: int = 0
## The prediction the previous macroblock used, which is what a skipped
## macroblock in a B picture repeats. A P picture's skip is a different rule and
## resets the vectors instead; conflating them is the classic B-picture drift.
var _last_had_forward: bool = false
var _last_had_backward: bool = false
## Set when a slice hit a code that is not in its table. Carried rather than
## returned so the alignment check still runs and still counts the slice.
var _lost: bool = false

## One byte per macroblock address, set when a slice mentioned it. Read once per
## picture by `_fill_uncovered`; cleared with a native `fill`, which is why it is
## a packed array and not a dictionary of the addresses that were missed.
var _covered := PackedByteArray()

var _block := PackedInt32Array()
var _block_coeffs: int = 0

# --- shared tables, built once for the whole process
static var _clip: PackedByteArray = PackedByteArray()
static var _dct_lut: PackedInt32Array = PackedInt32Array()
static var _mba_lut: PackedInt32Array = PackedInt32Array()
static var _cbp_lut: PackedInt32Array = PackedInt32Array()
static var _motion_lut: PackedInt32Array = PackedInt32Array()
static var _type_i_lut: PackedInt32Array = PackedInt32Array()
static var _type_p_lut: PackedInt32Array = PackedInt32Array()
static var _type_b_lut: PackedInt32Array = PackedInt32Array()
static var _dc_luma_lut: PackedInt32Array = PackedInt32Array()
static var _dc_chroma_lut: PackedInt32Array = PackedInt32Array()
static var _zigzag: PackedInt32Array = PackedInt32Array()
static var _tables_built: bool = false

# --- colour conversion tables, per instance because they are tiny and building
# --- them costs 1,024 stores
static var _yt: PackedInt32Array = PackedInt32Array()
static var _rt: PackedInt32Array = PackedInt32Array()
static var _gt_cb: PackedInt32Array = PackedInt32Array()
static var _gt_cr: PackedInt32Array = PackedInt32Array()
static var _bt: PackedInt32Array = PackedInt32Array()
## `(chroma << 8) | luma -> the byte`, 64 KB each. Red depends on Cr alone and
## blue on Cb alone, so both collapse into one table lookup per pixel; green
## needs both and cannot.
static var _rlut: PackedByteArray = PackedByteArray()
static var _blut: PackedByteArray = PackedByteArray()


func _init() -> void:
	_block.resize(64)
	build_tables()


# ============================================================ opening a stream


## Take a video elementary stream and read its first sequence header.
##
## The stream is not scanned, indexed or decoded here: this reads exactly the
## header that `the duration`, the frame size and the frame rate come out of, and
## the reason it stops there is `docs/DIGITAL_VIDEO.md` §3's first rule — a member
## has to be able to answer those three without anything being decoded, because
## the movies that read them do so before they ever press play.
func begin(elementary: PackedByteArray) -> bool:
	error = ""
	_es = elementary
	_es_end = _es.size()
	if _es_end < 12:
		error = "the video elementary stream is %d bytes" % _es_end
		return false
	var at := _find_start_code(0, START_SEQUENCE)
	if at < 0:
		error = "no sequence header (00 00 01 B3) in %d bytes of elementary stream" % _es_end
		return false
	_seek_bits((at + 4) * 8)
	if not _read_sequence_header():
		return false
	_allocate()
	rewind()
	# The header just read was a probe, and `rewind` puts the reader back in
	# front of it so `decode_picture` reads it again for real. Counting it twice
	# would make every clip in the harness report one sequence header more than
	# it has.
	sequence_headers_seen = 0
	return true


## Throw away every decoded picture and put the reader back at the first
## sequence header. Called by `begin` and by a backward seek that found no usable
## restart point.
func rewind() -> void:
	var at := _find_start_code(0, START_SEQUENCE)
	_seek_bits(maxi(at, 0) * 8)
	_has_fwd = false
	_has_bwd = false
	_picture_type = 0


func release() -> void:
	_es = PackedByteArray()
	_es_end = 0
	_y_cur = PackedByteArray()
	_cb_cur = PackedByteArray()
	_cr_cur = PackedByteArray()
	_y_fwd = PackedByteArray()
	_cb_fwd = PackedByteArray()
	_cr_fwd = PackedByteArray()
	_y_bwd = PackedByteArray()
	_cb_bwd = PackedByteArray()
	_cr_bwd = PackedByteArray()
	_has_fwd = false
	_has_bwd = false


## Where the reader is, in bits from the start of the elementary stream. The unit
## a restart point is recorded in.
func bit_position() -> int:
	return (_pos << 3) - _have


func seek_bit(bit: int) -> void:
	_seek_bits(bit)


func at_end() -> bool:
	return _pos >= _es_end and _have <= 0


# ======================================================= decoding one picture


## Decode the next picture in **coded** order.
##
## Returns its `picture_coding_type`, or 0 at the end of the stream and -1 on a
## stream the decoder refuses. Reordering into display order is
## `director_mpeg1.gd`'s job and is deliberately not here: this file's whole
## contract is "one picture, in the order the file codes them", and a decoder
## that also owned the display schedule would have two reasons to hold state
## across calls instead of one.
##
## Everything between pictures — a repeated sequence header, a group header, user
## data, an extension — is consumed on the way, because in MPEG-1 those are not
## optional decorations: a mid-stream sequence header may replace the quantiser
## matrices, and a group header is what says whether a seek to the picture after
## it is safe.
func decode_picture() -> int:
	var began := Time.get_ticks_usec()
	var result := _decode_picture_inner()
	decode_us += Time.get_ticks_usec() - began
	return result


func _decode_picture_inner() -> int:
	while true:
		var code := _next_start_code()
		if code < 0:
			return 0
		match code:
			START_SEQUENCE:
				if not _read_sequence_header():
					return -1
			START_GOP:
				_read_gop_header()
			START_PICTURE:
				return _read_picture()
			START_SEQUENCE_END:
				return 0
			START_EXTENSION, START_USER_DATA:
				pass  # skipped by the start-code search on the next pass
			_:
				pass
	return 0


## The picture just decoded, as three planes. `[y, cb, cr]`, each a
## `PackedByteArray` at macroblock-aligned size — `_luma_w` by `_luma_h` and half
## that on both axes for the two chroma planes.
##
## Which of the three buffers holds it depends on what was decoded: a B picture is
## its own, and an I or P picture *is* the new backward reference, so handing back
## a copy would double the memory of every clip for nothing.
func current_planes() -> Array:
	if _picture_type == PICTURE_B:
		return [_y_cur, _cb_cur, _cr_cur]
	return [_y_bwd, _cb_bwd, _cr_bwd]


## The past reference, which is what the *previous* I or P picture became when
## this one displaced it. `director_mpeg1.gd`'s display reordering reads it.
func forward_planes() -> Array:
	return [_y_fwd, _cb_fwd, _cr_fwd]


## The future reference — which is also *this* picture when the one just decoded
## was an I or a P. The end-of-stream flush reads it, because the last reference
## in a clip is displayed after every B that follows it in coded order.
func backward_planes() -> Array:
	return [_y_bwd, _cb_bwd, _cr_bwd]


func picture_type() -> int:
	return _picture_type


func temporal_reference() -> int:
	return _temporal_reference


# ================================================================== the headers


func _read_sequence_header() -> bool:
	sequence_headers_seen += 1
	var w := _read(12)
	var h := _read(12)
	var aspect := _read(4)
	var rate_code := _read(4)
	bit_rate = _read(18)
	_read(1)  # marker
	vbv_buffer_size = _read(10)
	constrained = _read(1) == 1
	if w <= 0 or h <= 0:
		error = "the sequence header declares a %dx%d picture" % [w, h]
		return false
	if width != 0 and (w != width or h != height):
		# A mid-stream size change would need every buffer reallocated and every
		# reference discarded. No encoder emits one and the format barely permits
		# it; refusing by name beats decoding the rest at the wrong stride.
		error = "the sequence changes size from %dx%d to %dx%d" % [width, height, w, h]
		return false
	width = w
	height = h
	mb_width = (w + 15) >> 4
	mb_height = (h + 15) >> 4
	pel_aspect = float(PEL_ASPECTS[aspect]) if aspect < PEL_ASPECTS.size() else 1.0
	fps = float(FRAME_RATES[rate_code]) if rate_code < FRAME_RATES.size() else 0.0
	if fps <= 0.0:
		error = "the sequence header declares frame_rate_code %d" % rate_code
		return false
	if _intra_matrix.is_empty():
		_reset_matrices()
	if _read(1) == 1:
		_load_matrix(_intra_matrix)
	if _read(1) == 1:
		_load_matrix(_non_intra_matrix)
	return true


func _reset_matrices() -> void:
	_intra_matrix.resize(64)
	_non_intra_matrix.resize(64)
	for i in 64:
		_intra_matrix[i] = int(DEFAULT_INTRA_MATRIX[i])
		_non_intra_matrix[i] = 16


## 64 bytes in zigzag order, stored in raster order — see `DEFAULT_INTRA_MATRIX`.
func _load_matrix(into: PackedInt32Array) -> void:
	for i in 64:
		into[int(ZIGZAG[i])] = _read(8)


func _read_gop_header() -> void:
	gops_seen += 1
	_read(25)  # time code: drop frame, hour, minute, marker, second, picture
	_gop_closed = _read(1) == 1
	_gop_broken_link = _read(1) == 1


var _gop_closed: bool = true
var _gop_broken_link: bool = false


func gop_closed() -> bool:
	return _gop_closed


## The picture header, then every slice of the picture.
func _read_picture() -> int:
	_temporal_reference = _read(10)
	var kind := _read(3)
	_read(16)  # vbv_delay
	if kind == PICTURE_P or kind == PICTURE_B:
		_full_pel_forward = _read(1) == 1
		var f_code := _read(3)
		if f_code < 1:
			error = "picture type %d declares forward_f_code 0" % kind
			return -1
		_forward_r_size = f_code - 1
		_forward_f = 1 << _forward_r_size
		_fwd_scale = 2 if _full_pel_forward else 1
	if kind == PICTURE_B:
		_full_pel_backward = _read(1) == 1
		var b_code := _read(3)
		if b_code < 1:
			error = "a B picture declares backward_f_code 0"
			return -1
		_backward_r_size = b_code - 1
		_backward_f = 1 << _backward_r_size
		_bwd_scale = 2 if _full_pel_backward else 1
	# extra_bit_picture: a sequence of `1 <8 bits>` pairs terminated by a 0.
	while _read(1) == 1:
		_read(8)
	if kind < PICTURE_I or kind > PICTURE_D:
		error = "picture_coding_type %d" % kind
		return -1
	_picture_type = kind
	type_counts[kind] = int(type_counts.get(kind, 0)) + 1
	pictures_decoded += 1

	# A reference picture is decoded into the buffer that is about to become the
	# backward reference, and the one it displaces becomes the forward reference.
	# Rotating the *buffers* rather than copying the pixels is what keeps a
	# 352x288 clip at three planes rather than five.
	if kind != PICTURE_B:
		var ty := _y_fwd
		var tcb := _cb_fwd
		var tcr := _cr_fwd
		_y_fwd = _y_bwd
		_cb_fwd = _cb_bwd
		_cr_fwd = _cr_bwd
		_has_fwd = _has_bwd
		_y_bwd = ty
		_cb_bwd = tcb
		_cr_bwd = tcr
		_has_bwd = true
	if kind == PICTURE_B and not _has_bwd:
		# A B picture with no future reference: this is the two-frame cost of
		# restarting inside an open group, and it is counted rather than hidden.
		open_gop_frames += 1

	_target_y = _y_cur if kind == PICTURE_B else _y_bwd
	_target_cb = _cb_cur if kind == PICTURE_B else _cb_bwd
	_target_cr = _cr_cur if kind == PICTURE_B else _cr_bwd

	# Slices, until something that is not one.
	if _covered.size() != mb_width * mb_height:
		_covered.resize(mb_width * mb_height)
	_covered.fill(0)
	var before := macroblocks_decoded + skipped_macroblocks
	while true:
		var next := _peek_start_code()
		if next < START_SLICE_FIRST or next > START_SLICE_LAST:
			break
		_next_start_code()
		_read_slice(next)
	var total := mb_width * mb_height
	if total > 0:
		var covered := macroblocks_decoded + skipped_macroblocks - before
		least_coverage = mini(least_coverage, covered * 100 / total)
		if kind == PICTURE_I and covered != total:
			short_intra_pictures += 1
		if covered < total and kind != PICTURE_I:
			_fill_uncovered()
	return kind


## Macroblocks no slice of this picture mentioned, filled from the forward
## reference with a zero motion vector.
##
## **This is not defensive tidying; without it a real clip shows a frame of
## somebody else's picture.** `heb/album/solution4.mpg` carries three P pictures
## with *no slices at all* — a picture header followed straight by the next
## picture header, which is how its encoder said "nothing changed". A reference
## picture is decoded into a recycled buffer (see the rotation in `_read_picture`,
## which swaps buffers rather than copying pixels), so a picture that writes
## nothing into it inherits whatever was there two references ago. Measured: 3 of
## the first 45 pictures of that clip, and 0 of `heb/mainmenu/intro.mpg`'s.
##
## The fill is the forward reference at zero displacement, which is exactly what
## "this macroblock did not change" means. For a B picture the forward reference
## is the past one, which is the same reading. MPEG-1 requires slices to cover the
## picture, so nothing here is specified — a decoder either conceals or shows
## rubbish, and concealing with the picture the encoder was predicting from is the
## only choice that can be right.
func _fill_uncovered() -> void:
	if not _has_fwd:
		return
	var total := mb_width * mb_height
	for address in total:
		if _covered[address] != 0:
			continue
		_predict(address % mb_width, address / mb_width, 0, 0,
			_y_fwd, _cb_fwd, _cr_fwd, false)


var _target_y := PackedByteArray()
var _target_cb := PackedByteArray()
var _target_cr := PackedByteArray()


## One slice: a run of macroblocks on one macroblock row, self-contained apart
## from the picture's own prediction state.
##
## The address arithmetic is the specification's and is worth stating because it
## is off by one in the obvious reading: `slice_vertical_position` is 1-based, and
## `macroblock_address` is set to one *before* the first macroblock of that row so
## that the first `macroblock_address_increment` — which is at least 1 — lands on
## it.
func _read_slice(vertical: int) -> void:
	slices_decoded += 1
	_quant = _read(5)
	while _read(1) == 1:
		_read(8)  # extra_information_slice
	_mb_address = (vertical - 1) * mb_width - 1
	_dc_y = 1024
	_dc_cb = 1024
	_dc_cr = 1024
	_mv_fwd_x = 0
	_mv_fwd_y = 0
	_mv_bwd_x = 0
	_mv_bwd_y = 0
	_last_had_forward = false
	_last_had_backward = false
	_lost = false
	var total := mb_width * mb_height
	while true:
		var increment := 0
		while true:
			var code := _read_mba()
			if code == 0:
				# An address increment that is not in table B.1 — the reader is
				# lost. **Broken out of rather than returned from**, so that the
				# alignment check below runs and counts it: the first version
				# returned here, which is how a slice that gave up after a third of
				# its macroblocks reported itself as clean.
				_lost = true
				break
			if code == 34:
				continue  # macroblock_stuffing: no address change at all
			if code == 35:
				increment += 33  # macroblock_escape
				continue
			increment += code
			break
		if _lost:
			break
		# The macroblocks the increment jumped **over** — `increment - 1` of them,
		# not `increment`. Including the one the increment lands on would predict
		# it twice and then decode its coefficients over the second prediction,
		# which for a P picture is invisible (the second prediction is identical)
		# and for a B picture doubles the interpolation weighting.
		if increment > 1:
			_skip_macroblocks(_mb_address + 1, _mb_address + increment - 1)
		_mb_address += increment
		if _mb_address >= total or _mb_address < 0:
			break
		_read_macroblock()
		macroblocks_decoded += 1
		_covered[_mb_address] = 1
		# The slice ends when the next 23 bits are zero, which is the start of the
		# next start code. Reading it as "peek 23 and compare" rather than
		# byte-aligning first is the specification's own rule and is what makes
		# the desync check below meaningful.
		if _peek(23) == 0:
			break
	# Land the reader on the byte boundary before the next start code, and record
	# whether everything in between was padding. See `desynced_slices`.
	if not _align_to_start_code() or _lost:
		desynced_slices += 1


## Macroblocks the address increment jumped over.
##
## **The two picture types disagree here and that is the whole of this function.**
## In a P picture a skipped macroblock is a copy from the forward reference with a
## zero motion vector, and the motion vector predictors reset to zero (§2.4.4.4).
## In a B picture it repeats the *previous* macroblock's prediction — same modes,
## same vectors, and the predictors are **not** reset. Using the P rule in a B
## picture makes every skipped macroblock in a still scene drift towards the
## forward reference, which looks like a slow smear rather than like a bug.
func _skip_macroblocks(from_address: int, to_address: int) -> void:
	if _picture_type == PICTURE_I or _picture_type == PICTURE_D:
		return
	var total := mb_width * mb_height
	if _picture_type == PICTURE_P:
		_mv_fwd_x = 0
		_mv_fwd_y = 0
	for address in range(from_address, to_address + 1):
		if address < 0 or address >= total:
			continue
		skipped_macroblocks += 1
		_covered[address] = 1
		var mb_x := address % mb_width
		var mb_y := address / mb_width
		if _picture_type == PICTURE_P:
			_predict(mb_x, mb_y, 0, 0, _y_fwd, _cb_fwd, _cr_fwd, false)
		else:
			var averaged := false
			if _last_had_forward and _has_fwd:
				_predict(mb_x, mb_y, _mv_fwd_x * _fwd_scale, _mv_fwd_y * _fwd_scale,
					_y_fwd, _cb_fwd, _cr_fwd, false)
				averaged = true
			if _last_had_backward and _has_bwd:
				_predict(mb_x, mb_y, _mv_bwd_x * _bwd_scale, _mv_bwd_y * _bwd_scale,
					_y_bwd, _cb_bwd, _cr_bwd, averaged)
			elif not averaged:
				_predict(mb_x, mb_y, _mv_bwd_x * _bwd_scale, _mv_bwd_y * _bwd_scale,
					_y_bwd, _cb_bwd, _cr_bwd, false)
	_dc_y = 1024
	_dc_cb = 1024
	_dc_cr = 1024


# ================================================================ one macroblock


## When true, every macroblock prints what it decoded and where the reader was.
##
## Off by default and read by nothing in the engine. It is here because the one
## thing that cannot be reasoned about from the outside of a VLC decoder is
## *where the bits went*, and the first time this decoder desynchronised — P and
## B pictures skipping 394 of 396 macroblocks — no amount of reading the tables
## would have found it. Left in rather than deleted with the bug, because the
## next reconstruction rule that is subtly wrong will need exactly this again.
var trace: bool = false
## The per-macroblock half of `trace`, separate because a picture is 396 lines of
## it and the desync report above is usually the only part wanted.
var trace_macroblocks: bool = false

func _read_macroblock() -> void:
	var trace_at := bit_position() if trace_macroblocks else 0
	var flags := 0
	match _picture_type:
		PICTURE_I:
			flags = _read_vlc(_type_i_lut, 2)
		PICTURE_P:
			flags = _read_vlc(_type_p_lut, 6)
		PICTURE_B:
			flags = _read_vlc(_type_b_lut, 6)
		_:
			# D pictures: `macroblock_type` is the single bit `1` and the whole
			# macroblock is a DC-only intra block per component.
			_read(1)
			flags = 0x10
	var is_intra := (flags & 0x10) != 0
	var has_quant := (flags & 0x01) != 0
	var has_forward := (flags & 0x02) != 0
	var has_backward := (flags & 0x04) != 0
	var has_pattern := (flags & 0x08) != 0
	if has_quant:
		_quant = _read(5)

	var mb_x := _mb_address % mb_width
	var mb_y := _mb_address / mb_width

	if is_intra:
		# An intra macroblock resets both motion vector predictors, because the
		# next macroblock's vectors are differential against a macroblock that had
		# none.
		_mv_fwd_x = 0
		_mv_fwd_y = 0
		_mv_bwd_x = 0
		_mv_bwd_y = 0
		_last_had_forward = false
		_last_had_backward = false
	else:
		# The DC predictors reset on every non-intra macroblock (§2.4.4.1).
		_dc_y = 1024
		_dc_cb = 1024
		_dc_cr = 1024
		if has_forward:
			_mv_fwd_x = _read_motion(_mv_fwd_x, _forward_f, _forward_r_size, _full_pel_forward)
			_mv_fwd_y = _read_motion(_mv_fwd_y, _forward_f, _forward_r_size, _full_pel_forward)
		elif _picture_type == PICTURE_P:
			# A P macroblock with no motion vector is predicted with a zero one,
			# and the predictor resets with it.
			_mv_fwd_x = 0
			_mv_fwd_y = 0
		if has_backward:
			_mv_bwd_x = _read_motion(_mv_bwd_x, _backward_f, _backward_r_size, _full_pel_backward)
			_mv_bwd_y = _read_motion(_mv_bwd_y, _backward_f, _backward_r_size, _full_pel_backward)
		_last_had_forward = has_forward or _picture_type == PICTURE_P
		_last_had_backward = has_backward
		var averaged := false
		if _last_had_forward and _has_fwd:
			_predict(mb_x, mb_y, _mv_fwd_x * _fwd_scale, _mv_fwd_y * _fwd_scale,
				_y_fwd, _cb_fwd, _cr_fwd, false)
			averaged = true
		if has_backward and _has_bwd:
			_predict(mb_x, mb_y, _mv_bwd_x * _bwd_scale, _mv_bwd_y * _bwd_scale,
				_y_bwd, _cb_bwd, _cr_bwd, averaged)
		elif not averaged:
			# No usable reference at all — the open-group case. Predicting from
			# whichever buffer exists beats leaving the macroblock at whatever the
			# last picture in that buffer had, which is somebody else's picture.
			_predict(mb_x, mb_y, _mv_bwd_x * _bwd_scale, _mv_bwd_y * _bwd_scale,
				_y_bwd, _cb_bwd, _cr_bwd, false)

	var pattern := 0x3F if is_intra else 0
	if has_pattern:
		pattern = _read_vlc(_cbp_lut, 9)
	if trace_macroblocks:
		print("    mb %4d at bit %8d flags 0x%02X quant %2d mv (%d,%d)/(%d,%d) cbp %d" % [
			_mb_address, trace_at, flags, _quant,
			_mv_fwd_x, _mv_fwd_y, _mv_bwd_x, _mv_bwd_y, pattern])
	for b in 6:
		if (pattern & (0x20 >> b)) == 0:
			continue
		_read_block(b, is_intra, mb_x, mb_y)


## One 8x8 block: the coefficients, the dequantisation, the transform and the
## store.
func _read_block(b: int, is_intra: bool, mb_x: int, mb_y: int) -> void:
	_block.fill(0)
	_block_coeffs = 0
	var i := 0
	if is_intra:
		# `_build_sized` stores the size biased by one so that a legal size of 0
		# is distinguishable from the table's "no entry"; unbiased here, at the
		# one place that reads these two tables.
		var size := 0
		if b < 4:
			size = _read_vlc(_dc_luma_lut, 7) - 1
		else:
			size = _read_vlc(_dc_chroma_lut, 8) - 1
		if size < 0:
			size = 0
		var diff := 0
		if size > 0:
			diff = _read(size)
			if (diff & (1 << (size - 1))) == 0:
				diff = diff - (1 << size) + 1
		var predictor := _dc_y
		if b == 4:
			predictor = _dc_cb
		elif b == 5:
			predictor = _dc_cr
		predictor += diff * 8
		if b < 4:
			_dc_y = predictor
		elif b == 4:
			_dc_cb = predictor
		else:
			_dc_cr = predictor
		_block[0] = predictor
		_block_coeffs = 1
		i = 1
		if _picture_type == PICTURE_D:
			# A D picture's blocks are DC only, with one marker bit after the
			# sixth. Nothing since 1993 has produced one and nothing in this
			# corpus contains one, so this arm is written from §2.4.3.7 and is
			# **unverified**; it is here because the format has D pictures, which
			# is `AGENTS.md`'s rule rather than this corpus's requirement.
			if b == 5:
				_read(1)
			_store_block(b, true, mb_x, mb_y)
			return
	else:
		# The first coefficient of a non-intra block: the single bit `1` is
		# `run 0, level ±1`. Everywhere else `10` is end-of-block, which is why
		# this case cannot be folded into the table.
		if _peek(1) == 1:
			_skip(1)
			var negative := _read(1) == 1
			_block[0] = _dequant_non_intra(-1 if negative else 1, 0)
			_block_coeffs = 1
			i = 1
		else:
			i = 0

	# **The loop ends on the end-of-block code and on nothing else.** §2.4.3.7
	# writes it as `while (nextbits() != '10') dct_coeff_next; end_of_block`, so a
	# block whose last coefficient sits at position 63 still carries an EOB after
	# it — there is no "the block is full, stop reading" rule.
	#
	# Getting that wrong is invisible until it is not. The first version of this
	# loop broke as soon as the coefficient index passed 63 and left the EOB in the
	# bitstream, which desynchronised the reader for the rest of the slice.
	# Measured on `heb/mainmenu/intro.mpg`'s third I picture, at
	# `quantizer_scale` 1: the first 100 macroblocks decoded perfectly, macroblock
	# 100's third block was the first in the clip dense enough to fill all 64
	# coefficients, and every macroblock after it was rubbish — a picture correct
	# down to a third of its height and black below. With the EOB consumed, the
	# same slice runs to macroblock 395 and stops exactly on the padding.
	#
	# Coefficients past 63 are still *read* and simply not stored, because reading
	# them is what keeps the bitstream aligned; `guard` bounds the loop so that a
	# damaged stream costs one wrong block rather than a hang inside a property
	# read.
	var guard := 0
	var matrix := _intra_matrix if is_intra else _non_intra_matrix
	var quant := _quant
	var zz := _zigzag
	while true:
		var packed := _read_coefficient()
		if packed < 0:
			break
		guard += 1
		if guard > 128:
			break
		i += packed >> 12
		if i <= 63:
			var level := (packed & 0xFFF) - 2048
			var at: int = zz[i]
			# `_dequant_intra` / `_dequant_non_intra` written out, because they are
			# called once per coefficient and a GDScript call costs more than the
			# arithmetic in them. `tools/mpeg1_decode.gd` asserts the two named
			# functions against §2.4.4.2's own properties, and this must stay the
			# same arithmetic as those — the magnitude form, the odd-value
			# adjustment and the clamp, in that order.
			var value := 0
			if level != 0:
				var negative := level < 0
				var magnitude := -level if negative else level
				if is_intra:
					value = (2 * magnitude * quant * matrix[at]) / 16
				else:
					value = ((2 * magnitude + 1) * quant * matrix[at]) / 16
				if (value & 1) == 0:
					value -= 1
				if value > 2047:
					value = 2047
				if negative:
					value = -value
			_block[at] = value
			_block_coeffs += 1
		i += 1

	_store_block(b, is_intra, mb_x, mb_y)


## §2.4.4.2, intra, for every coefficient but the DC.
##
## `(2 * level * quantizer_scale * matrix) / 16`, then the "oddification" that
## drops the magnitude by one when the result is even, then the clamp. Computed on
## the magnitude and re-signed rather than on the signed value, because the
## specification's division truncates towards zero and GDScript's does too — but
## only the magnitude form makes that visible to a reader.
func _dequant_intra(level: int, at: int) -> int:
	if level == 0:
		return 0
	var negative := level < 0
	var magnitude := -level if negative else level
	var value := (2 * magnitude * _quant * _intra_matrix[at]) / 16
	if (value & 1) == 0:
		value -= 1
	if value > 2047:
		value = 2047
	return -value if negative else value


## §2.4.4.2, non-intra. The extra `+ sign(level)` inside the numerator is the
## whole difference and it is not a rounding term: it is what makes a level of 1
## dequantise to something non-zero at every quantiser scale.
func _dequant_non_intra(level: int, at: int) -> int:
	if level == 0:
		return 0
	var negative := level < 0
	var magnitude := -level if negative else level
	var value := ((2 * magnitude + 1) * _quant * _non_intra_matrix[at]) / 16
	if (value & 1) == 0:
		value -= 1
	if value > 2047:
		value = 2047
	return -value if negative else value


## Transform the block and write it into the target planes.
##
## The DC-only shortcut is the single largest saving in the whole decoder and it
## is not an approximation: with one non-zero coefficient the separable transform
## produces one constant, and `((dc << 3) + 32) >> 6` is exactly what the two
## passes below compute for that case. Measured on `heb/mainmenu/intro.mpg`, most
## coded blocks in P and B pictures have one coefficient or none.
func _store_block(b: int, is_intra: bool, mb_x: int, mb_y: int) -> void:
	var plane: PackedByteArray
	var stride := 0
	var origin := 0
	if b < 4:
		plane = _target_y
		stride = _luma_w
		origin = (mb_y * 16 + (b >> 1) * 8) * stride + mb_x * 16 + (b & 1) * 8
	elif b == 4:
		plane = _target_cb
		stride = _chroma_w
		origin = (mb_y * 8) * stride + mb_x * 8
	else:
		plane = _target_cr
		stride = _chroma_w
		origin = (mb_y * 8) * stride + mb_x * 8

	var clip := _clip
	var blk := _block
	if _block_coeffs == 1 and blk[0] != 0:
		var flat := ((blk[0] << 3) + 32) >> 6
		if is_intra:
			var byte := clip[(flat + CLIP_OFFSET) & CLIP_MASK]
			for row in 8:
				var p := origin + row * stride
				for col in 8:
					plane[p + col] = byte
		else:
			for row in 8:
				var p := origin + row * stride
				for col in 8:
					plane[p + col] = clip[(plane[p + col] + flat + CLIP_OFFSET) & CLIP_MASK]
		return
	if _block_coeffs == 0:
		return

	var began := Time.get_ticks_usec()
	_idct()
	idct_us += Time.get_ticks_usec() - began

	if is_intra:
		for row in 8:
			var p := origin + row * stride
			var q := row * 8
			for col in 8:
				plane[p + col] = clip[(blk[q + col] + CLIP_OFFSET) & CLIP_MASK]
	else:
		for row in 8:
			var p := origin + row * stride
			var q := row * 8
			for col in 8:
				plane[p + col] = clip[
					(plane[p + col] + blk[q + col] + CLIP_OFFSET) & CLIP_MASK]


# ======================================================================= the IDCT
#
# The separable integer inverse DCT: eight one-dimensional transforms across the
# rows, then eight down the columns, in the classic fixed-point form whose
# constants are `2048 * sqrt(2) * cos(k * PI / 16)`.
#
# **The zero shortcut at the head of each pass is not an optimisation of the
# common case, it is the reason this is affordable at all.** A row whose only
# non-zero entry is its first is a constant row, and in a P or B picture most
# rows of most coded blocks are entirely zero. Removing it roughly triples the
# cost of a picture, measured.
#
# `tools/mpeg1_decode.gd` asserts this against a direct floating-point evaluation
# of the transform's own definition — the double sum with the cosines written out
# — rather than against another implementation of it, which is the only kind of
# check that can catch a constant being one digit wrong.


func _idct() -> void:
	var blk := _block
	for r in 8:
		var o := r << 3
		var x1 := blk[o + 4] << 11
		var x2 := blk[o + 6]
		var x3 := blk[o + 2]
		var x4 := blk[o + 1]
		var x5 := blk[o + 7]
		var x6 := blk[o + 5]
		var x7 := blk[o + 3]
		if (x1 | x2 | x3 | x4 | x5 | x6 | x7) == 0:
			var flat := blk[o] << 3
			blk[o] = flat
			blk[o + 1] = flat
			blk[o + 2] = flat
			blk[o + 3] = flat
			blk[o + 4] = flat
			blk[o + 5] = flat
			blk[o + 6] = flat
			blk[o + 7] = flat
			continue
		var x0 := (blk[o] << 11) + 128
		var x8 := W7 * (x4 + x5)
		x4 = x8 + (W1 - W7) * x4
		x5 = x8 - (W1 + W7) * x5
		x8 = W3 * (x6 + x7)
		x6 = x8 - (W3 - W5) * x6
		x7 = x8 - (W3 + W5) * x7
		x8 = x0 + x1
		x0 -= x1
		x1 = W6 * (x3 + x2)
		x2 = x1 - (W2 + W6) * x2
		x3 = x1 + (W2 - W6) * x3
		x1 = x4 + x6
		x4 -= x6
		x6 = x5 + x7
		x5 -= x7
		x7 = x8 + x3
		x8 -= x3
		x3 = x0 + x2
		x0 -= x2
		x2 = (181 * (x4 + x5) + 128) >> 8
		x4 = (181 * (x4 - x5) + 128) >> 8
		blk[o] = (x7 + x1) >> 8
		blk[o + 1] = (x3 + x2) >> 8
		blk[o + 2] = (x0 + x4) >> 8
		blk[o + 3] = (x8 + x6) >> 8
		blk[o + 4] = (x8 - x6) >> 8
		blk[o + 5] = (x0 - x4) >> 8
		blk[o + 6] = (x3 - x2) >> 8
		blk[o + 7] = (x7 - x1) >> 8
	for c in 8:
		var x1 := blk[c + 32] << 8
		var x2 := blk[c + 48]
		var x3 := blk[c + 16]
		var x4 := blk[c + 8]
		var x5 := blk[c + 56]
		var x6 := blk[c + 40]
		var x7 := blk[c + 24]
		if (x1 | x2 | x3 | x4 | x5 | x6 | x7) == 0:
			var flat := (blk[c] + 32) >> 6
			blk[c] = flat
			blk[c + 8] = flat
			blk[c + 16] = flat
			blk[c + 24] = flat
			blk[c + 32] = flat
			blk[c + 40] = flat
			blk[c + 48] = flat
			blk[c + 56] = flat
			continue
		var x0 := (blk[c] << 8) + 8192
		var x8 := W7 * (x4 + x5) + 4
		x4 = (x8 + (W1 - W7) * x4) >> 3
		x5 = (x8 - (W1 + W7) * x5) >> 3
		x8 = W3 * (x6 + x7) + 4
		x6 = (x8 - (W3 - W5) * x6) >> 3
		x7 = (x8 - (W3 + W5) * x7) >> 3
		x8 = x0 + x1
		x0 -= x1
		x1 = W6 * (x3 + x2) + 4
		x2 = (x1 - (W2 + W6) * x2) >> 3
		x3 = (x1 + (W2 - W6) * x3) >> 3
		x1 = x4 + x6
		x4 -= x6
		x6 = x5 + x7
		x5 -= x7
		x7 = x8 + x3
		x8 -= x3
		x3 = x0 + x2
		x0 -= x2
		x2 = (181 * (x4 + x5) + 128) >> 8
		x4 = (181 * (x4 - x5) + 128) >> 8
		blk[c] = (x7 + x1) >> 14
		blk[c + 8] = (x3 + x2) >> 14
		blk[c + 16] = (x0 + x4) >> 14
		blk[c + 24] = (x8 + x6) >> 14
		blk[c + 32] = (x8 - x6) >> 14
		blk[c + 40] = (x0 - x4) >> 14
		blk[c + 48] = (x3 - x2) >> 14
		blk[c + 56] = (x7 - x1) >> 14


# ======================================================== motion compensation


## A motion vector component, reconstructed against its predictor.
##
## §2.4.4.3. The `f_code` scaling is the part that is easy to get half right:
## `motion_r` supplies the low bits only when `f` is above 1 *and* the code is
## non-zero, and the wrap at the end is modulo the whole representable range
## rather than a clamp — a vector that overflows wraps to the other end, which is
## how MPEG-1 expresses a large vector with a small `f_code`.
func _read_motion(predictor: int, f: int, r_size: int, full_pel: bool) -> int:
	var code := _read_vlc(_motion_lut, 11) - 16
	var delta := 0
	if code == 0:
		delta = 0
	elif f == 1:
		delta = code
	else:
		var r := _read(r_size) if r_size > 0 else 0
		var magnitude := (absi(code) - 1) * f + r + 1
		delta = -magnitude if code < 0 else magnitude
	var value := predictor + delta
	var limit := f << 4
	if value > limit - 1:
		value -= limit << 1
	elif value < -limit:
		value += limit << 1
	# `full_pel_*_vector` is deliberately **not** applied here. §2.4.4.2 scales the
	# reconstructed vector by two only where it is *used*; the value carried
	# forward as the predictor for the next macroblock is the unscaled one, so
	# doubling at this point would double it again on every subsequent
	# macroblock of the slice. `_fwd_scale` / `_bwd_scale` carry the factor to
	# each prediction site instead.
	return value


## Copy a 16x16 macroblock and its two 8x8 chroma blocks out of a reference
## picture, at half-pel precision, optionally averaging with what is already in
## the target.
##
## The chroma vector is the luma vector halved **towards zero**, which is what
## §2.4.4.2 asks for and what GDScript's integer division already does; writing it
## as `>> 1` instead would round -3 to -2 rather than to -1 and put the colour
## half a pixel out on everything moving left.
func _predict(mb_x: int, mb_y: int, mvx: int, mvy: int,
		src_y: PackedByteArray, src_cb: PackedByteArray, src_cr: PackedByteArray,
		average: bool) -> void:
	if src_y.size() < _luma_w * _luma_h:
		return
	_predict_plane(_target_y, src_y, _luma_w, _luma_h,
		mb_x * 16, mb_y * 16, mvx, mvy, 16, average)
	var cx := mvx / 2
	var cy := mvy / 2
	_predict_plane(_target_cb, src_cb, _chroma_w, _chroma_h,
		mb_x * 8, mb_y * 8, cx, cy, 8, average)
	_predict_plane(_target_cr, src_cr, _chroma_w, _chroma_h,
		mb_x * 8, mb_y * 8, cx, cy, 8, average)


## One plane of one macroblock's prediction.
##
## Four cases, because half-pel interpolation on each axis is independent: a plain
## copy, a horizontal average, a vertical average, and the four-tap average of
## both. They are written out rather than folded into one general loop because the
## plain copy is the overwhelming majority and a general loop would pay for the
## interpolation on every macroblock that does not use it.
##
## The source origin is clamped so the read window stays inside the plane. MPEG-1
## forbids a vector that points outside the picture, so this can only fire on a
## damaged stream — and on one, a clamped read is a slightly wrong macroblock
## where an unclamped one is a script error that takes the movie down.
func _predict_plane(dst: PackedByteArray, src: PackedByteArray, w: int, h: int,
		x: int, y: int, mvx: int, mvy: int, size: int, average: bool) -> void:
	var sx := x + (mvx >> 1)
	var sy := y + (mvy >> 1)
	var half_x := (mvx & 1) != 0
	var half_y := (mvy & 1) != 0
	if sx < 0:
		sx = 0
	elif sx > w - size - 1:
		sx = maxi(w - size - 1, 0)
	if sy < 0:
		sy = 0
	elif sy > h - size - 1:
		sy = maxi(h - size - 1, 0)
	var d := y * w + x
	var s := sy * w + sx
	if average:
		for row in size:
			var dr := d + row * w
			var sr := s + row * w
			for col in size:
				var v := 0
				if half_x and half_y:
					v = (src[sr + col] + src[sr + col + 1]
						+ src[sr + col + w] + src[sr + col + w + 1] + 2) >> 2
				elif half_x:
					v = (src[sr + col] + src[sr + col + 1] + 1) >> 1
				elif half_y:
					v = (src[sr + col] + src[sr + col + w] + 1) >> 1
				else:
					v = src[sr + col]
				dst[dr + col] = (dst[dr + col] + v + 1) >> 1
		return
	if not half_x and not half_y:
		# The plain copy, eight bytes at a time. `decode_u64` and `encode_u64` move
		# a row of a 16-wide luma block in two calls and an 8-wide chroma block in
		# one, where the byte loop below them costs sixteen index reads and sixteen
		# stores — **measured at about four times the cost** in GDScript, and this
		# is the branch nearly every macroblock of nearly every P and B picture
		# takes. Little-endian on both sides, so the bytes come back in the order
		# they went in; the value being read as signed does not matter, because
		# nothing looks at it.
		var words := size >> 3
		for row in size:
			var dr := d + row * w
			var sr := s + row * w
			for word in words:
				dst.encode_u64(dr, src.decode_u64(sr))
				dr += 8
				sr += 8
			for col in size & 7:
				dst[dr + col] = src[sr + col]
		return
	if half_x and not half_y:
		for row in size:
			var dr := d + row * w
			var sr := s + row * w
			for col in size:
				dst[dr + col] = (src[sr + col] + src[sr + col + 1] + 1) >> 1
		return
	if half_y and not half_x:
		for row in size:
			var dr := d + row * w
			var sr := s + row * w
			for col in size:
				dst[dr + col] = (src[sr + col] + src[sr + col + w] + 1) >> 1
		return
	for row in size:
		var dr := d + row * w
		var sr := s + row * w
		for col in size:
			dst[dr + col] = (src[sr + col] + src[sr + col + 1]
				+ src[sr + col + w] + src[sr + col + w + 1] + 2) >> 2


# ==================================================================== the picture


## The three planes as one RGB image, cropped back to the sequence header's own
## size from the macroblock-aligned buffers they are decoded in.
##
## 4:2:0 chroma is upsampled by replication — each chroma sample covers the 2x2
## luma quad it was subsampled from. Bilinear upsampling would be closer to what
## a broadcast decoder does and costs three more table lookups and two more adds
## per pixel, which at 101,376 pixels per picture is the same order as the whole
## rest of the conversion; at 320x240 stretched to a 320x240 sprite the difference
## is not visible, and the honest place to spend that budget is the decode.
##
## The colour matrix is BT.601 with the **studio range** MPEG-1 codes in: Y runs
## 16..235 and the conversion scales it back out, which is why a decoder that
## treats Y as 0..255 produces a picture that is washed out rather than wrong.
func to_image(planes: Array = []) -> Image:
	if width <= 0 or height <= 0:
		return null
	var out := PackedByteArray()
	out.resize(width * height * 3)
	if planes.is_empty():
		planes = current_planes()
	var y_plane: PackedByteArray = planes[0]
	var cb_plane: PackedByteArray = planes[1]
	var cr_plane: PackedByteArray = planes[2]
	if y_plane.size() < _luma_w * _luma_h:
		return null
	# Locals rather than members and rather than a nested inner loop, because this
	# runs 101,376 times per displayed 352x288 frame and every one of those costs
	# is paid a hundred thousand times. **Measured**: the readable version — a
	# `mini()` per chroma pair and a two-iteration inner loop — cost 165 ms per
	# frame, more than the whole decode of the pictures behind it. Red and blue
	# depend on one chroma channel each, so they are read straight out of a
	# 65,536-entry table indexed by `(chroma << 8) | luma`; only green needs both
	# and keeps the add-and-clamp.
	var yt := _yt
	var clip := _clip
	var rlut := _rlut
	var blut := _blut
	var gcb := _gt_cb
	var gcr := _gt_cr
	var pairs := width >> 1
	for row in height:
		var y_at := row * _luma_w
		var c_at := (row >> 1) * _chroma_w
		var o := row * width * 3
		for _pair in pairs:
			var cb := cb_plane[c_at]
			var cr := cr_plane[c_at]
			c_at += 1
			var r_base := cr << 8
			var b_base := cb << 8
			var g_add := gcb[cb] + gcr[cr] + CLIP_OFFSET
			var luma := y_plane[y_at]
			out[o] = rlut[r_base + luma]
			out[o + 1] = clip[(yt[luma] + g_add) & CLIP_MASK]
			out[o + 2] = blut[b_base + luma]
			luma = y_plane[y_at + 1]
			out[o + 3] = rlut[r_base + luma]
			out[o + 4] = clip[(yt[luma] + g_add) & CLIP_MASK]
			out[o + 5] = blut[b_base + luma]
			y_at += 2
			o += 6
		if (width & 1) == 1:
			# An odd width has one column with no partner. No MPEG-1 encode in this
			# corpus has one — 352 and 320 are both even, and 4:2:0 chroma makes an
			# odd luma width awkward for an encoder too — but the format permits it
			# and a loop that quietly dropped the last column would be wrong in a way
			# nothing here reports.
			var cb2 := cb_plane[c_at]
			var cr2 := cr_plane[c_at]
			var luma2 := y_plane[y_at]
			out[o] = rlut[(cr2 << 8) + luma2]
			out[o + 1] = clip[(yt[luma2] + gcb[cb2] + gcr[cr2] + CLIP_OFFSET) & CLIP_MASK]
			out[o + 2] = blut[(cb2 << 8) + luma2]
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, out)


func _allocate() -> void:
	_luma_w = mb_width * 16
	_luma_h = mb_height * 16
	_chroma_w = mb_width * 8
	_chroma_h = mb_height * 8
	var luma := _luma_w * _luma_h
	var chroma := _chroma_w * _chroma_h
	_y_cur.resize(luma)
	_y_fwd.resize(luma)
	_y_bwd.resize(luma)
	_cb_cur.resize(chroma)
	_cb_fwd.resize(chroma)
	_cb_bwd.resize(chroma)
	_cr_cur.resize(chroma)
	_cr_fwd.resize(chroma)
	_cr_bwd.resize(chroma)
	# Mid grey rather than black, so that a picture predicted from a reference
	# that does not exist yet reads as "nothing decoded here" instead of as a
	# black frame somebody might mistake for authored content.
	_y_cur.fill(128)
	_y_fwd.fill(128)
	_y_bwd.fill(128)
	_cb_cur.fill(128)
	_cb_fwd.fill(128)
	_cb_bwd.fill(128)
	_cr_cur.fill(128)
	_cr_fwd.fill(128)
	_cr_bwd.fill(128)


# ================================================================= the bit reader


func _seek_bits(bit: int) -> void:
	_pos = bit >> 3
	_cache = 0
	_have = 0
	_fill()
	_skip(bit & 7)


func _fill() -> void:
	if _have > 24:
		return
	_cache &= (1 << _have) - 1
	if _pos + 7 < _es_end:
		while _have <= 48:
			_cache = (_cache << 8) | _es[_pos]
			_pos += 1
			_have += 8
		return
	while _have <= 48:
		_cache = (_cache << 8) | (0 if _pos >= _es_end else _es[_pos])
		_pos += 1
		_have += 8


func _peek(n: int) -> int:
	if _have <= 24:
		_fill()
	return (_cache >> (_have - n)) & ((1 << n) - 1)


func _skip(n: int) -> void:
	_have -= n


func _read(n: int) -> int:
	if _have <= 24:
		_fill()
	_have -= n
	return (_cache >> _have) & ((1 << n) - 1)


## Decode one variable-length code out of a flat lookup table.
##
## The table is indexed by the next `bits` bits *peeked* rather than consumed, and
## each entry carries the true length of the code in its low byte — so a code of
## any length up to `bits` is one array read and one subtraction, where a
## bit-at-a-time tree walk would be up to sixteen of each. That trade is 256 KB
## for the DCT coefficient table and it is the difference between this decoder
## being slow and being unusable.
func _read_vlc(lut: PackedInt32Array, bits: int) -> int:
	if _have <= 24:
		_fill()
	var entry := lut[(_cache >> (_have - bits)) & ((1 << bits) - 1)]
	if entry == 0:
		# An invalid code. The slice is lost from here; the desync counter is what
		# reports it, and the reader is left where it was so the start-code search
		# can find its way out.
		_have -= 1
		return 0
	_have -= entry & 0xFF
	return entry >> 8


## One DCT coefficient, sign, escape and all — `(run << 12) | (level + 2048)`,
## or -1 for end-of-block.
##
## **Folded into one function on purpose.** A dense intra block at
## `quantizer_scale` 1 carries up to 64 coefficients and a 352x288 I picture has
## 2,376 blocks, so this runs about ninety thousand times per picture; the version
## that returned the table entry and left the caller to read the sign bit and the
## escape payload cost three more GDScript calls each time, which measured as a
## fifth of the whole decode. The packing exists for the same reason — one integer
## return beats two member writes.
##
## `level + 2048` because the level is signed and spans -255..255; twelve bits
## hold it and the run needs five.
func _read_coefficient() -> int:
	if _have <= 24:
		_fill()
	var entry := _dct_lut[(_cache >> (_have - 16)) & 0xFFFF]
	if entry == 0:
		# Not a code in table B.14. One bit is dropped so the caller cannot spin,
		# and the slice is reported through `desynced_slices`.
		_have -= 1
		return -1
	_have -= entry & 0xFF
	var payload := entry >> 8
	if payload == 0x3FFFFF:
		return -1
	var run := 0
	var level := 0
	if payload == 0x3FFFFE:
		_have -= 6
		run = (_cache >> _have) & 0x3F
		_have -= 8
		level = (_cache >> _have) & 0xFF
		if level == 0 or level == 128:
			# Table B.16's two-stage form. The refill is not optional here: the
			# escape code, the run and the first level byte are twenty bits, and the
			# cache is only guaranteed twenty-five.
			var negative := level == 128
			if _have <= 24:
				_fill()
			_have -= 8
			level = (_cache >> _have) & 0xFF
			if negative:
				level -= 256
		elif level > 128:
			level -= 256
	else:
		run = (payload >> 8) & 0x3F
		level = payload & 0xFF
		_have -= 1
		if ((_cache >> _have) & 1) == 1:
			level = -level
	return (run << 12) | (level + 2048)


func _read_mba() -> int:
	return _read_vlc(_mba_lut, 11)


# ============================================================== start codes


## The next start code, consuming everything up to and including its four bytes.
## -1 at the end of the stream.
func _next_start_code() -> int:
	var at := (bit_position() + 7) >> 3
	var found := _find_any_start_code(at)
	if found < 0:
		_pos = _es_end
		_have = 0
		return -1
	_seek_bits((found + 4) * 8)
	return _es[found + 3]


## What the next start code is, without consuming anything.
func _peek_start_code() -> int:
	var at := (bit_position() + 7) >> 3
	var found := _find_any_start_code(at)
	if found < 0:
		return -1
	return _es[found + 3]


## Move to the byte before the next start code, and say whether everything
## between the reader and it was padding.
##
## That "everything was padding" is what `desynced_slices` counts, and getting the
## rule right took one measurement. The first version demanded that the start code
## follow within two bytes, on the reasoning that a slice is byte-aligned to it.
## It reported 6 of 7 slices desynced on `heb/mainmenu/intro.mpg` — and the decode
## was correct. **That clip's slices are followed by thousands of zero bytes**:
## its opening seconds are a fade from black, so a P picture is one coded
## macroblock, an escape chain to the last one, and then VBV stuffing to hold the
## constant bit rate. The measured slice was 18 bytes of data and 4,840 bytes of
## zeros.
##
## So the rule is the one 11172-2 §2.4.2.2 actually states: any number of zero
## bytes may precede a start code. What a desynchronised reader leaves behind is
## *non-zero* bytes — half-consumed coefficient data — which is what this looks
## for, and it is still the strongest signal the VLC layer gives about itself.
##
## The gap is checked with a native `count` over a slice rather than a GDScript
## loop, because at 39,402 slices and up to five kilobytes of padding each a
## per-byte loop would cost more than the decode.
func _align_to_start_code() -> bool:
	var at_bit := bit_position()
	var here := (at_bit + 7) >> 3
	var found := _find_any_start_code(here)
	if found < 0:
		_pos = _es_end
		_have = 0
		return true
	var clean := true
	# The bits between the reader and the next byte boundary are the encoder's
	# alignment padding and must be zero.
	var stray := here * 8 - at_bit
	if stray > 0 and _peek(stray) != 0:
		clean = false
	if clean and found > here:
		var gap := _es.slice(here, found)
		clean = gap.count(0) == gap.size()
	if trace and not clean:
		print("    DESYNC: reader at bit %d (byte %d), next start code at byte %d (0x%02X)" % [
			at_bit, here, found, _es[found + 3]])
	_seek_bits(found * 8)
	return clean


## The next `00 00 01` at or after a byte offset.
##
## Found by asking `PackedByteArray.find` for the next zero byte rather than by
## walking every byte in GDScript. A start code is three bytes and the first is
## zero, so every candidate begins at a zero — and `find` is one native call that
## skips whatever lies between. On `heb/mainmenu/intro.mpg`'s 12.6 MB elementary
## stream that turns 12.6 million GDScript iterations into the number of zero
## bytes, which is what makes indexing the stream affordable at all.
func _find_any_start_code(from: int) -> int:
	var at := maxi(from, 0)
	while true:
		var z := _es.find(0, at)
		if z < 0 or z + 3 >= _es_end:
			return -1
		if _es[z + 1] == 0 and _es[z + 2] == 1:
			return z
		at = z + 1
	return -1


func _find_start_code(from: int, code: int) -> int:
	var at := from
	while true:
		var found := _find_any_start_code(at)
		if found < 0:
			return -1
		if _es[found + 3] == code:
			return found
		at = found + 4
	return -1


# ===================================================================== the tables


## Build every lookup table this decoder reads. Idempotent, static, and shared by
## every instance in the process, because the tables are the format's and not the
## file's — and rebuilding 65,536 entries per opened clip would be visible on an
## album that repoints one member at twenty of them.
static func build_tables() -> void:
	if _tables_built:
		return
	_tables_built = true

	_clip.resize(CLIP_MASK + 1)
	for i in CLIP_MASK + 1:
		var v := i - CLIP_OFFSET
		_clip[i] = 0 if v < 0 else (255 if v > 255 else v)

	_yt.resize(256)
	_rt.resize(256)
	_gt_cb.resize(256)
	_gt_cr.resize(256)
	_bt.resize(256)
	for i in 256:
		_yt[i] = ((i - 16) * 76309) >> 16
		var c := i - 128
		_rt[i] = (c * 104597) >> 16
		_gt_cb[i] = (c * -25675) >> 16
		_gt_cr[i] = (c * -53279) >> 16
		_bt[i] = (c * 132201) >> 16
	_rlut.resize(65536)
	_blut.resize(65536)
	for chroma in 256:
		var r_add := _rt[chroma] + CLIP_OFFSET
		var b_add := _bt[chroma] + CLIP_OFFSET
		var base := chroma << 8
		for luma in 256:
			_rlut[base + luma] = _clip[(_yt[luma] + r_add) & CLIP_MASK]
			_blut[base + luma] = _clip[(_yt[luma] + b_add) & CLIP_MASK]

	# Table B.1 — macroblock_address_increment. 34 is stuffing and 35 is the
	# escape, both named here rather than at the call site so the two magic
	# numbers exist once.
	var mba := [
		["1", 1], ["011", 2], ["010", 3], ["0011", 4], ["0010", 5],
		["00011", 6], ["00010", 7], ["0000111", 8], ["0000110", 9],
		["00001011", 10], ["00001010", 11], ["00001001", 12], ["00001000", 13],
		["00000111", 14], ["00000110", 15],
		["0000010111", 16], ["0000010110", 17], ["0000010101", 18],
		["0000010100", 19], ["0000010011", 20], ["0000010010", 21],
		["00000100011", 22], ["00000100010", 23], ["00000100001", 24],
		["00000100000", 25], ["00000011111", 26], ["00000011110", 27],
		["00000011101", 28], ["00000011100", 29], ["00000011011", 30],
		["00000011010", 31], ["00000011001", 32], ["00000011000", 33],
		["00000001111", 34], ["00000001000", 35],
	]
	_mba_lut = _build(mba, 11)

	# Table B.2/B.3/B.4 — macroblock_type. The value is a flag word:
	# 0x01 quant, 0x02 forward, 0x04 backward, 0x08 pattern, 0x10 intra.
	_type_i_lut = _build([["1", 0x10], ["01", 0x11]], 2)
	_type_p_lut = _build([
		["1", 0x0A], ["01", 0x08], ["001", 0x02], ["00011", 0x10],
		["00010", 0x0B], ["00001", 0x09], ["000001", 0x11],
	], 6)
	_type_b_lut = _build([
		["10", 0x06], ["11", 0x0E], ["010", 0x04], ["011", 0x0C],
		["0010", 0x02], ["0011", 0x0A], ["00011", 0x10], ["00010", 0x0F],
		["000011", 0x0B], ["000010", 0x0D], ["000001", 0x11],
	], 6)

	# Table B.9 — coded_block_pattern, 1..63.
	var cbp := [
		["111", 60], ["1101", 4], ["1100", 8], ["1011", 16], ["1010", 32],
		["10011", 12], ["10010", 48], ["10001", 20], ["10000", 40],
		["01111", 28], ["01110", 44], ["01101", 52], ["01100", 56],
		["01011", 1], ["01010", 61], ["01001", 2], ["01000", 62],
		["001111", 24], ["001110", 36], ["001101", 3], ["001100", 63],
		["0010111", 5], ["0010110", 9], ["0010101", 17], ["0010100", 33],
		["0010011", 6], ["0010010", 10], ["0010001", 18], ["0010000", 34],
		["00011111", 7], ["00011110", 11], ["00011101", 19], ["00011100", 35],
		["00011011", 13], ["00011010", 49], ["00011001", 21], ["00011000", 41],
		["00010111", 14], ["00010110", 50], ["00010101", 22], ["00010100", 42],
		["00010011", 15], ["00010010", 51], ["00010001", 23], ["00010000", 43],
		["00001111", 25], ["00001110", 37], ["00001101", 26], ["00001100", 38],
		["00001011", 29], ["00001010", 45], ["00001001", 53], ["00001000", 57],
		["00000111", 30], ["00000110", 46], ["00000101", 54], ["00000100", 58],
		["000000111", 31], ["000000110", 47], ["000000101", 55],
		["000000100", 59], ["000000011", 27], ["000000010", 39],
	]
	_cbp_lut = _build(cbp, 9)

	# Table B.10 — motion_code, -16..16, stored biased by +16 so that 0 can stay
	# the table's "no entry" value.
	#
	# **The table is a signed pair per magnitude and that is what says it is
	# transcribed right**: every code for -m and the code for +m differ only in
	# their last bit, odd for negative and even for positive. The first version of
	# this table broke that pattern at magnitudes 5 to 7 and was one leading zero
	# short on everything from 8 upwards — which `tools/mpeg1_decode.gd` caught as
	# a prefix violation (`00001010` was made a prefix of `000010100`) before a
	# single file had been decoded.
	var motion := [
		["00000011001", -16], ["00000011011", -15], ["00000011101", -14],
		["00000011111", -13], ["00000100001", -12], ["00000100011", -11],
		["0000010011", -10], ["0000010101", -9], ["0000010111", -8],
		["00000111", -7], ["00001001", -6], ["00001011", -5],
		["0000111", -4], ["00011", -3], ["0011", -2], ["011", -1],
		["1", 0], ["010", 1], ["0010", 2], ["00010", 3], ["0000110", 4],
		["00001010", 5], ["00001000", 6], ["00000110", 7],
		["0000010110", 8], ["0000010100", 9], ["0000010010", 10],
		["00000100010", 11], ["00000100000", 12], ["00000011110", 13],
		["00000011100", 14], ["00000011010", 15], ["00000011000", 16],
	]
	var motion_biased := []
	for row in motion:
		motion_biased.append([row[0], int(row[1]) + 16])
	_motion_lut = _build(motion_biased, 11)

	# Tables B.12 and B.13 — dct_dc_size. The value is a size in bits and 0 is a
	# legal one, so these are stored biased by +1 and unbiased at the call site…
	# except that they are not: `_read_vlc` returns the stored value and a size of
	# 0 would be indistinguishable from "no entry". So the entries carry the size
	# directly and the "no entry" case is caught by the length byte instead, which
	# is why `_build` refuses a table with a zero value.
	_dc_luma_lut = _build_sized([
		["100", 0], ["00", 1], ["01", 2], ["101", 3], ["110", 4],
		["1110", 5], ["11110", 6], ["111110", 7], ["1111110", 8],
	], 7)
	_dc_chroma_lut = _build_sized([
		["00", 0], ["01", 1], ["10", 2], ["110", 3], ["1110", 4],
		["11110", 5], ["111110", 6], ["1111110", 7], ["11111110", 8],
	], 8)

	_dct_lut = _build_dct()

	# The scan order as a packed array. `ZIGZAG` above is the readable statement
	# of it and stays; this is the same table in a form that does not unbox a
	# Variant on every one of the ninety thousand coefficient lookups a picture
	# makes.
	_zigzag.resize(64)
	for i in 64:
		_zigzag[i] = int(ZIGZAG[i])


## `code -> (value << 8) | length`, filled across every suffix so that a peek of
## `bits` bits lands on the right entry whatever follows the code.
static func _build(rows: Array, bits: int) -> PackedInt32Array:
	var lut := PackedInt32Array()
	lut.resize(1 << bits)
	for row_value in rows:
		var row: Array = row_value
		var text := str(row[0])
		var value := int(row[1])
		var length := text.length()
		var code := 0
		for i in length:
			code = (code << 1) | (1 if text[i] == "1" else 0)
		var shift := bits - length
		var base := code << shift
		var entry := (value << 8) | length
		for i in 1 << shift:
			lut[base + i] = entry
	return lut


## The same, for a table whose values may legitimately be 0 — the DC size tables.
## The value is stored biased so that the entry word is never 0, and unbiased on
## the way out by `_read_vlc`… which does not know about the bias, so the bias is
## applied here and removed here by storing `value + 1` and having the caller
## subtract. Kept separate rather than folding the bias into `_build`, because
## every other table's value is naturally non-zero and a bias applied to all of
## them would be one more thing to get wrong at five call sites instead of one.
static func _build_sized(rows: Array, bits: int) -> PackedInt32Array:
	var biased := []
	for row_value in rows:
		var row: Array = row_value
		biased.append([row[0], int(row[1]) + 1])
	return _build(biased, bits)


## Table B.14, the DCT coefficient table.
##
## Written as `[bits, run, level]` and expanded into a flat 65,536-entry lookup,
## with `0x3FFFFF` standing for end-of-block and `0x3FFFFE` for the escape. The
## sign bit that follows every coefficient code is deliberately **not** part of
## the table: it is read separately, so that the same entry serves both signs and
## the table stays at 16 bits instead of 17.
static func _dct_rows() -> Array:
	return [
		["10", 0x3FFFFF, 0],          # end of block
		["000001", 0x3FFFFE, 0],      # escape
		["11", 0, 1], ["011", 1, 1], ["0100", 0, 2], ["0101", 2, 1],
		["00101", 0, 3], ["00111", 3, 1], ["00110", 4, 1],
		["000110", 1, 2], ["000111", 5, 1], ["000101", 6, 1], ["000100", 7, 1],
		["0000110", 0, 4], ["0000100", 2, 2], ["0000111", 8, 1], ["0000101", 9, 1],
		["00100110", 0, 5], ["00100001", 0, 6], ["00100101", 1, 3],
		["00100100", 3, 2], ["00100111", 10, 1], ["00100011", 11, 1],
		["00100010", 12, 1], ["00100000", 13, 1],
		["0000001010", 0, 7], ["0000001100", 1, 4], ["0000001011", 2, 3],
		["0000001111", 4, 2], ["0000001001", 5, 2], ["0000001110", 14, 1],
		["0000001101", 15, 1], ["0000001000", 16, 1],
		["000000011101", 0, 8], ["000000011000", 0, 9], ["000000010011", 0, 10],
		["000000010000", 0, 11], ["000000011011", 1, 5], ["000000010100", 2, 4],
		["000000011100", 3, 3], ["000000010010", 4, 3], ["000000011110", 6, 2],
		["000000010101", 7, 2], ["000000010001", 8, 2], ["000000011111", 17, 1],
		["000000011010", 18, 1], ["000000011001", 19, 1], ["000000010111", 20, 1],
		["000000010110", 21, 1],
		["0000000011010", 0, 12], ["0000000011001", 0, 13],
		["0000000011000", 0, 14], ["0000000010111", 0, 15],
		["0000000010110", 1, 6], ["0000000010101", 1, 7], ["0000000010100", 2, 5],
		["0000000010011", 3, 4], ["0000000010010", 5, 3], ["0000000010001", 9, 2],
		["0000000010000", 10, 2], ["0000000011111", 22, 1],
		["0000000011110", 23, 1], ["0000000011101", 24, 1],
		["0000000011100", 25, 1], ["0000000011011", 26, 1],
		["00000000011111", 0, 16], ["00000000011110", 0, 17],
		["00000000011101", 0, 18], ["00000000011100", 0, 19],
		["00000000011011", 0, 20], ["00000000011010", 0, 21],
		["00000000011001", 0, 22], ["00000000011000", 0, 23],
		["00000000010111", 0, 24], ["00000000010110", 0, 25],
		["00000000010101", 0, 26], ["00000000010100", 0, 27],
		["00000000010011", 0, 28], ["00000000010010", 0, 29],
		["00000000010001", 0, 30], ["00000000010000", 0, 31],
		["000000000011000", 0, 32], ["000000000010111", 0, 33],
		["000000000010110", 0, 34], ["000000000010101", 0, 35],
		["000000000010100", 0, 36], ["000000000010011", 0, 37],
		["000000000010010", 0, 38], ["000000000010001", 0, 39],
		["000000000010000", 0, 40], ["000000000011111", 1, 8],
		["000000000011110", 1, 9], ["000000000011101", 1, 10],
		["000000000011100", 1, 11], ["000000000011011", 1, 12],
		["000000000011010", 1, 13], ["000000000011001", 1, 14],
		["0000000000010011", 1, 15], ["0000000000010010", 1, 16],
		["0000000000010001", 1, 17], ["0000000000010000", 1, 18],
		["0000000000010100", 6, 3], ["0000000000011010", 11, 2],
		["0000000000011001", 12, 2], ["0000000000011000", 13, 2],
		["0000000000010111", 14, 2], ["0000000000010110", 15, 2],
		["0000000000010101", 16, 2], ["0000000000011111", 27, 1],
		["0000000000011110", 28, 1], ["0000000000011101", 29, 1],
		["0000000000011100", 30, 1], ["0000000000011011", 31, 1],
	]


static func _build_dct() -> PackedInt32Array:
	var lut := PackedInt32Array()
	lut.resize(1 << 16)
	for row_value in _dct_rows():
		var row: Array = row_value
		var text := str(row[0])
		var run := int(row[1])
		var level := int(row[2])
		# The two sentinels are stored as themselves; everything else packs the
		# run and the level into one word so that a coefficient costs one array
		# read and no branch.
		var payload := run if run > 0xFF else ((run << 8) | level)
		var length := text.length()
		var code := 0
		for i in length:
			code = (code << 1) | (1 if text[i] == "1" else 0)
		var shift := 16 - length
		var base := code << shift
		var entry := (payload << 8) | length
		for i in 1 << shift:
			lut[base + i] = entry
	return lut


## The table rows, for a harness that wants to check them rather than trust them.
static func dct_rows_for_audit() -> Array:
	return _dct_rows()


## The built lookup for a named table, so a harness can assert that the rows it
## has a second transcription of really are the entries the decoder will read.
##
## A table can be a perfect prefix code and still be laid into the array at the
## wrong shift, which produces plausible-looking rubbish rather than a failure;
## this is what makes that checkable without decoding a file.
static func lut_for_audit(which: String) -> PackedInt32Array:
	build_tables()
	match which:
		"mba":
			return _mba_lut
		"cbp":
			return _cbp_lut
		"motion":
			return _motion_lut
		"type_i":
			return _type_i_lut
		"type_p":
			return _type_p_lut
		"type_b":
			return _type_b_lut
		"dc_luma":
			return _dc_luma_lut
		"dc_chroma":
			return _dc_chroma_lut
		"dct":
			return _dct_lut
	return PackedInt32Array()
