extends RefCounted
## MPEG-1/2 audio, Layer I and Layer II — ISO/IEC 11172-3 §2.4 and 13818-3 §2.4.
##
## `director_mpeg1_ps.gd` separates the audio elementary stream out of the program
## stream and `director_mpeg1.gd` reads its first frame header. This file is what
## turns those bytes into samples: it is the second decoder the video half's
## header called a named gap, and it is why the 22 clips are no longer silent.
##
## ## What the corpus is, and which allocation table that selects
##
## Measured over all 22 `.mpg` in `test-games/itamar-magichat`: **every frame of
## every file is MPEG-1 Layer II, 44,100 Hz, 224,000 bit/s, mode 0 (plain
## stereo), protection bit 1 (no CRC)** — 38,082 frames, no resynchronisation and
## no rejected header anywhere in the set. Frame lengths alternate 731 and 732
## bytes, which is `144 * 224000 / 44100 = 731.4` floored plus the padding bit.
##
## Layer II's bit allocation table is chosen by the bit rate **per channel** and
## the sampling rate, not by the bit rate in the header, and that is the single
## place a Layer II decoder is most often wrong: at 224 kbit/s *stereo* the rate
## per channel is 112 kbit/s, and 44.1 kHz at 96–192 kbit/s per channel is
## **ISO Table B.2b, sblimit 30**. Reading the header's 224 as if it were the
## per-channel figure selects Table B.2a instead, which has the same allocation
## rows for its first 27 subbands and simply stops there — so the mistake is not a
## crash and not noise, it is three subbands of treble quietly missing and a
## bitstream that still desynchronises a few frames later. `tools/mpeg1_audio.gd`
## asserts the selection over all 84 legal (rate, mode, bit rate) combinations
## against a second statement of ISO's own lookup, because one formulation
## checked against itself proves nothing.
##
## ## The arithmetic, stated rather than copied
##
## Requantisation is written from the definition rather than from a table of
## constants. ISO Table B.4 gives a scale `C` and an offset `D` per quantisation
## class, applied as `s'' = C * (fraction + D)`; substituting the class's own
## `steps` and code width collapses the whole table to
##
##     s'' = (2 * code + 1 - steps) / steps
##
## which is exact for all seventeen classes, grouped and ungrouped alike, and is
## what `tools/mpeg1_audio.gd` checks against the seventeen transcribed `C`/`D`
## pairs. Writing it this way matters because the widely copied minimal decoders
## divide by `steps + 1` instead — correct only when `steps` is `2^n - 1`, and
## audibly wrong for the grouped 3, 5 and 9 level classes, which is exactly the
## kind of error that survives listening tests.
##
## Scalefactors are the same story: ISO Table B.1's 63 entries are `2^(1 - i/3)`,
## so the table is three constants and a shift rather than 63 transcribed decimals.
##
## The synthesis filterbank is ISO Annex A's: a 32-to-64 point cosine transform
## into a 1,024-sample ring, then a 512-tap window summed 16 taps to an output
## sample. `_WINDOW` is ISO Table B.3 at 16.16 fixed point — its peak entry is
## 75,038, and 75,038 / 65,536 is 1.144989013671875, the standard's own maximum
## coefficient to the last digit, which is the cheapest available check that the
## table is the real one.
##
## ## What it costs, and why it is shaped for a thread
##
## The filterbank is the whole cost: 16 multiply-accumulates per output sample,
## and at 44,100 Hz stereo that is 1.41 million per second of audio — 123 million
## for `intro.mpg`'s 87 seconds. GDScript measured at **7.8 M MAC/s** on the
## scalar form of that loop (`--bench`), which would be 16 seconds of CPU.
##
## So the loop is not scalar. `V` and the window are held as `PackedVector4Array`,
## the sixteen taps of four adjacent output samples are gathered as four
## componentwise `Vector4` products, and the 512 scalar multiply-accumulates
## become **128 vector ones**. The intermediate `U` buffer ISO describes is not
## built at all — its indices are folded into the gather, because writing 512
## floats and reading them back costs more than the arithmetic does. Measured
## cost is in `tools/mpeg1_audio.gd`'s output; the caller's decision about *when*
## to pay it is `director_mpeg1.gd`'s, and it is a background thread.
##
## ## What is not here
##
## **Layer III.** It is a different decoder — Huffman coded coefficients, a bit
## reservoir that makes a frame's data start in an earlier frame, window
## switching and a hybrid IMDCT stage — and none of the four is present in Layer
## II. `scan` recognises it, names it, and refuses, so a Layer III file reports
## what it is rather than decoding to noise. Free-format streams (bitrate index 0)
## are refused for the same reason: their frame length is not in the header.
##
## Layer I **is** here, at a cost of about forty lines, because it shares the
## filterbank and the scalefactors and differs only in its allocation and its
## twelve one-sample granules. No file in any of the eight corpora is Layer I;
## it is implemented from the specification and is unverified against real data,
## which `AGENTS.md`'s "build Director, not this game" asks for and says to
## record in the comment rather than leave absent.

## Layer numbers as this file uses them: 1, 2, 3. The header's two bits are the
## complement (`4 - bits`), which `_read_header` converts once so that nothing
## below has to remember the inversion.
const LAYER_I := 1
const LAYER_II := 2
const LAYER_III := 3

## Channel mode, ISO §2.4.2.3.
const MODE_STEREO := 0
const MODE_JOINT := 1
const MODE_DUAL := 2
const MODE_MONO := 3

## Bit rates in kbit/s by index, MPEG-1 then MPEG-2/2.5 ("LSF"), Layer I on its
## own because Layer I's ladder is not Layer II's.
const BITRATE_V1_L1 := [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448]
const BITRATE_V1_L2 := [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384]
const BITRATE_V1_L3 := [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
const BITRATE_V2_L1 := [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256]
const BITRATE_V2_L23 := [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]

const RATE_V1 := [44100, 48000, 32000]
const RATE_V2 := [22050, 24000, 16000]
const RATE_V25 := [11025, 12000, 8000]

## The seventeen quantisation classes of ISO Table B.4, as
## `[steps, codeword bits, grouped]`. `steps` is the number of levels; `bits` is
## the width of the codeword actually read, which for a grouped class covers
## **three** samples at once and is why it is 5, 7 and 10 rather than 2, 3 and 4.
const QUANT_CLASS := [
	[3, 5, true], [5, 7, true], [7, 3, false], [9, 10, true], [15, 4, false],
	[31, 5, false], [63, 6, false], [127, 7, false], [255, 8, false],
	[511, 9, false], [1023, 10, false], [2047, 11, false], [4095, 12, false],
	[8191, 13, false], [16383, 14, false], [32767, 15, false], [65535, 16, false],
]

## Which quantisation class each allocation code selects, per row shape. A `0`
## means "this subband carries nothing"; anything else is `QUANT_CLASS` index
## plus one. These are ISO Annex B's columns, factored so that the four Layer II
## tables are three row shapes rather than four transcriptions — B.2a is B.2b
## truncated at 27 subbands and B.2c is B.2d truncated at 8, which is a property
## of the standard's own tables and not a simplification.
const ALLOC_CODES := [
	[0, 1, 2, 17],
	[0, 1, 2, 3, 4, 5, 6, 17],
	[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17],
	[0, 1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
	[0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17],
	[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
]

## `[nbal, ALLOC_CODES row]` per subband, per table. Index 0 is ISO Table B.2d
## (B.2c is its first 8 subbands), index 1 is Table B.2b (B.2a is its first 27),
## index 2 is 13818-3 Table B.1 for the half-rate sampling frequencies.
const ALLOC_ROWS := [
	[[4, 4], [4, 4], [3, 4], [3, 4], [3, 4], [3, 4], [3, 4], [3, 4],
	 [3, 4], [3, 4], [3, 4], [3, 4]],
	[[4, 3], [4, 3], [4, 3],
	 [4, 2], [4, 2], [4, 2], [4, 2], [4, 2], [4, 2], [4, 2], [4, 2],
	 [3, 1], [3, 1], [3, 1], [3, 1], [3, 1], [3, 1],
	 [3, 1], [3, 1], [3, 1], [3, 1], [3, 1], [3, 1],
	 [2, 0], [2, 0], [2, 0], [2, 0], [2, 0], [2, 0], [2, 0]],
	[[4, 5], [4, 5], [4, 5], [4, 5],
	 [3, 4], [3, 4], [3, 4], [3, 4], [3, 4], [3, 4], [3, 4],
	 [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4],
	 [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4], [2, 4],
	 [2, 4]],
]

## Table B.2a..d as `[ALLOC_ROWS index, sblimit]`, named so the selection below
## reads as ISO's own table letters.
const TABLE_A := [1, 27]
const TABLE_B := [1, 30]
const TABLE_C := [0, 8]
const TABLE_D := [0, 12]
const TABLE_LSF := [2, 30]

var error: String = ""

## The first frame's header, which every later frame is required to match on the
## fields that decide the frame's shape.
var version: int = 0  ## 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5
var layer: int = 0
var sample_rate: int = 0
var bit_rate: int = 0
var channels: int = 0
var mode: int = MODE_STEREO
var mode_extension: int = 0
var protected: bool = false

## What the walk found. `frame_offsets` is into the elementary stream this was
## handed; `sample_frames` is per channel, so the duration is that over the rate.
var frame_offsets := PackedInt32Array()
var frame_lengths := PackedInt32Array()
var frame_count: int = 0
var sample_frames: int = 0
var samples_per_frame: int = 0

## The three numbers that say whether the walk was a walk or a search. Every
## frame's declared length must land exactly on the next sync word; `resyncs`
## counts the times it did not and the reader had to hunt, and it is this file's
## `desynced_slices` — the one self-check that is strong because it is
## structural. `truncated_tail` is the bytes of a final frame the multiplex cut
## short, which is normal and is not a resynchronisation.
var resyncs: int = 0
var rejected_headers: int = 0
var truncated_tail: int = 0

var _es := PackedByteArray()
var _at: int = 0
## The bit reader's shift register and how many bits of it are live.
var _cache: int = 0
var _cache_bits: int = 0

## Decoder state that persists across frames: the 1,024-sample ring per channel
## the synthesis window reads back through, and where its head is.
var _v: Array[PackedVector4Array] = []
var _voffs: int = 0

var _decode_us: int = 0

## `QUANT_CLASS` flattened and indexed by allocation code rather than by class,
## so the sample loop never indexes an `Array` of `Array` — every such lookup in
## GDScript unboxes a `Variant`, and there are 2,160 of them per frame.
## Index 0 is unused and means "no allocation".
static var _q_steps := PackedInt32Array()
static var _q_width := PackedInt32Array()
static var _q_group := PackedInt32Array()
## `1 / steps`, because the requantiser divides by it once per sample.
static var _q_inv := PackedFloat32Array()

static var _window4 := PackedVector4Array()
static var _cos_table := PackedFloat32Array()
static var _scalefactor := PackedFloat32Array()
static var _tables_built := false


## ISO/IEC 11172-3 Table B.3, the 512 coefficient synthesis window, at 16.16
## fixed point — the values divided by 65,536 are the standard's own decimals.
##
## The one cheap check that this is the real table rather than a plausible one:
## its largest entry is 75,038, and 75,038 / 65,536 is **1.144989013671875**,
## which is Table B.3's maximum coefficient 1.144989014 to every digit the
## standard prints. `tools/mpeg1_audio.gd` restates that, checks the length, and
## then does the thing that actually proves it — drives one subband at a time
## through this filterbank and measures how much of the energy lands anywhere
## other than that subband's own frequency, which a wrong coefficient ruins.
##
## Held as integers and converted once in `build_tables`, because a `const` of
## 512 floats is 512 float literals to get right and 512 chances to mistype one.
const _WINDOW := [
	0, 0, 0, 0, 0, 0, 0, -1,
	-1, -1, -1, -2, -2, -3, -3, -4,
	-4, -5, -6, -6, -7, -8, -9, -10,
	-12, -13, -15, -16, -18, -20, -23, -25,
	-28, -30, -34, -37, -40, -44, -48, -52,
	-57, -62, -67, -72, -78, -84, -90, -96,
	-103, -110, -116, -124, -131, -138, -146, -153,
	-160, -168, -175, -182, -189, -195, -201, -207,
	213, 218, 222, 225, 227, 228, 228, 227,
	224, 221, 215, 208, 200, 189, 177, 163,
	146, 127, 106, 83, 57, 29, -1, -35,
	-71, -110, -152, -196, -243, -293, -346, -400,
	-458, -518, -580, -644, -710, -778, -847, -918,
	-990, -1063, -1136, -1209, -1282, -1355, -1427, -1497,
	-1566, -1633, -1697, -1758, -1816, -1869, -1918, -1961,
	-2000, -2031, -2056, -2074, -2084, -2086, -2079, -2062,
	2037, 2000, 1952, 1893, 1822, 1739, 1644, 1535,
	1414, 1280, 1131, 970, 794, 605, 402, 185,
	-44, -287, -544, -813, -1094, -1387, -1691, -2005,
	-2329, -2662, -3003, -3350, -3704, -4062, -4424, -4787,
	-5152, -5516, -5878, -6236, -6588, -6934, -7270, -7596,
	-7909, -8208, -8490, -8754, -8997, -9218, -9415, -9584,
	-9726, -9837, -9915, -9958, -9965, -9934, -9862, -9749,
	-9591, -9388, -9138, -8839, -8491, -8091, -7639, -7133,
	6574, 5959, 5288, 4561, 3776, 2935, 2037, 1082,
	70, -997, -2121, -3299, -4532, -5817, -7153, -8539,
	-9974, -11454, -12979, -14547, -16154, -17798, -19477, -21188,
	-22928, -24693, -26481, -28288, -30111, -31946, -33790, -35639,
	-37488, -39335, -41175, -43005, -44820, -46616, -48389, -50136,
	-51852, -53533, -55177, -56777, -58332, -59837, -61288, -62683,
	-64018, -65289, -66493, -67628, -68691, -69678, -70589, -71419,
	-72168, -72834, -73414, -73907, -74312, -74629, -74855, -74991,
	75038, 74992, 74856, 74630, 74313, 73908, 73415, 72835,
	72169, 71420, 70590, 69679, 68692, 67629, 66494, 65290,
	64019, 62684, 61289, 59838, 58333, 56778, 55178, 53534,
	51853, 50137, 48390, 46617, 44821, 43006, 41176, 39336,
	37489, 35640, 33791, 31947, 30112, 28289, 26482, 24694,
	22929, 21189, 19478, 17799, 16155, 14548, 12980, 11455,
	9975, 8540, 7154, 5818, 4533, 3300, 2122, 998,
	-69, -1081, -2036, -2934, -3775, -4560, -5287, -5958,
	6574, 7134, 7640, 8092, 8492, 8840, 9139, 9389,
	9592, 9750, 9863, 9935, 9966, 9959, 9916, 9838,
	9727, 9585, 9416, 9219, 8998, 8755, 8491, 8209,
	7910, 7597, 7271, 6935, 6589, 6237, 5879, 5517,
	5153, 4788, 4425, 4063, 3705, 3351, 3004, 2663,
	2330, 2006, 1692, 1388, 1095, 814, 545, 288,
	45, -184, -401, -604, -793, -969, -1130, -1279,
	-1413, -1534, -1643, -1738, -1821, -1892, -1951, -1999,
	2037, 2063, 2080, 2087, 2085, 2075, 2057, 2032,
	2001, 1962, 1919, 1870, 1817, 1759, 1698, 1634,
	1567, 1498, 1428, 1356, 1283, 1210, 1137, 1064,
	991, 919, 848, 779, 711, 645, 581, 519,
	459, 401, 347, 294, 244, 197, 153, 111,
	72, 36, 2, -28, -56, -82, -105, -126,
	-145, -162, -176, -188, -199, -207, -214, -220,
	-223, -226, -227, -227, -226, -224, -221, -217,
	213, 208, 202, 196, 190, 183, 176, 169,
	161, 154, 147, 139, 132, 125, 117, 111,
	104, 97, 91, 85, 79, 73, 68, 63,
	58, 53, 49, 45, 41, 38, 35, 31,
	29, 26, 24, 21, 19, 17, 16, 14,
	13, 11, 10, 9, 8, 7, 7, 6,
	5, 5, 4, 4, 3, 3, 2, 2,
	2, 2, 1, 1, 1, 1, 1, 1
]


## Build the three tables that are cheaper to compute once than to transcribe:
## the windowing coefficients in `Vector4` form, the 32x32 cosine matrix the
## harness checks the unrolled transform against, and ISO Table B.1's
## scalefactors.
static func build_tables() -> void:
	if _tables_built:
		return
	_window4.resize(128)
	for i in 128:
		_window4[i] = Vector4(
			float(_WINDOW[i * 4]) / 65536.0, float(_WINDOW[i * 4 + 1]) / 65536.0,
			float(_WINDOW[i * 4 + 2]) / 65536.0, float(_WINDOW[i * 4 + 3]) / 65536.0)
	_cos_table.resize(32 * 32)
	for m in 32:
		for k in 32:
			_cos_table[m * 32 + k] = float(cos(PI * float(m) * float(2 * k + 1) / 64.0))
	# ISO Table B.1: 63 scalefactors, 2^(1 - i/3), from 2.0 down to 1.19e-6.
	# Index 63 is the illegal one and is a silent zero rather than a refusal,
	# because one bad scalefactor in a 3,344 frame clip should cost a granule and
	# not the sound track.
	_scalefactor.resize(64)
	for i in 63:
		_scalefactor[i] = float(pow(2.0, 1.0 - float(i) / 3.0))
	_scalefactor[63] = 0.0
	_q_steps.resize(QUANT_CLASS.size() + 1)
	_q_width.resize(QUANT_CLASS.size() + 1)
	_q_group.resize(QUANT_CLASS.size() + 1)
	_q_inv.resize(QUANT_CLASS.size() + 1)
	for i in QUANT_CLASS.size():
		var spec: Array = QUANT_CLASS[i]
		_q_steps[i + 1] = int(spec[0])
		_q_width[i + 1] = int(spec[1])
		_q_group[i + 1] = 1 if bool(spec[2]) else 0
		_q_inv[i + 1] = 1.0 / float(spec[0])
	_tables_built = true


## The cosine matrix, for the harness that checks the unrolled transform.
static func cos_matrix() -> PackedFloat32Array:
	build_tables()
	return _cos_table


## ISO Table B.1's scalefactors, likewise.
static func scalefactors() -> PackedFloat32Array:
	build_tables()
	return _scalefactor


## The synthesis window at 16.16, so a harness can restate ISO Table B.3's peak
## and its length without reaching into a private constant.
static func window_raw() -> Array:
	return _WINDOW


## Requantise one code: ISO §2.4.3.2 and Table B.4, collapsed to a closed form.
##
## The standard writes `s'' = C * (fraction + D)`, where `fraction` is the code
## with its most significant bit inverted read as a two's complement fraction of
## `nb` bits, `C = 2^nb / steps` and `D = 1 - (steps - 1) / 2^nb`. Substituting
## both and cancelling `2^nb` leaves `(2 * code + 1 - steps) / steps`, with no
## dependence on `nb` at all — so Annex B's seventeen row table of `C` and `D` is
## one division here. `tools/mpeg1_audio.gd` checks this against those seventeen
## transcribed pairs rather than trusting the algebra.
##
## The result is in (-1, 1) and the caller multiplies it by the subband's
## scalefactor. **Not** `(2 * code + 1 - steps) / (steps + 1)`, which is what a
## decoder that treated `steps` as `2^nb` would write; it is right for the
## ungrouped classes to within a part in 65,536 and 25% quiet on a three level
## subband, which is the kind of error that survives a listening test.
static func requantise(code: int, steps: int) -> float:
	return float(2 * code + 1 - steps) / float(steps)


## Which of ISO Annex B's four Layer II allocation tables a stream selects, as
## `[ALLOC_ROWS index, sblimit]`.
##
## **The rule is stated in bit rate per channel**, which is the header's bit rate
## halved for every mode except single channel — and getting that halving wrong is
## the classic Layer II defect, because Table B.2a is Table B.2b truncated to 27
## subbands, so the wrong answer costs three subbands rather than producing
## nonsense somebody would notice. A stream at 44.1 kHz and 224 kbit/s stereo is
## 112 kbit/s per channel and selects **B.2b**; read as 224 per channel it selects
## B.2a instead and loses subbands 27 to 29.
##
## MPEG-2's half sampling frequencies have one table for everything (13818-3
## Table B.1), which is why they are answered before the rate is looked at.
static func allocation_table(version_bits: int, rate: int, bitrate_kbps: int,
		channel_mode: int) -> Array:
	if version_bits != 3:
		return TABLE_LSF
	var per_channel := bitrate_kbps if channel_mode == MODE_MONO else bitrate_kbps / 2
	if rate == 48000:
		return TABLE_A if per_channel >= 56 else TABLE_C
	if per_channel >= 96:
		return TABLE_B
	if per_channel >= 56:
		return TABLE_A
	# 32 kHz has a wider low rate table than the other two: ISO B.2d, not B.2c.
	return TABLE_D if rate == 32000 else TABLE_C


# ============================================================== locating frames


## Walk every frame of an elementary stream, validating as it goes.
##
## This is the audio half's `desynced_slices`, and it is the strongest self-check
## available here for the same reason. A frame header states a bit rate, a
## sampling rate and a padding bit; those three give a byte length; and **the
## length must land exactly on the next sync word**. There is no other field
## tying one frame to the next, so a walk that lands on 38,082 consecutive sync
## words across 22 files has read every one of those headers correctly.
##
## False leaves `error` set, for a stream this cannot decode at all: Layer III,
## free format, or no sync word anywhere. A stream that merely has damage in it
## walks as far as it can and reports `resyncs` above zero, because losing a
## frame is better than losing a sound track.
func scan(es: PackedByteArray) -> bool:
	_reset()
	_es = es
	var n := es.size()
	if n < 4:
		error = "the audio elementary stream is %d bytes" % n
		return false
	var at := _find_sync(0)
	if at < 0:
		error = "no MPEG audio sync word in %d bytes" % n
		return false
	var head := _read_header(at)
	if head.is_empty():
		error = "the first sync word at %d is not a usable frame header" % at
		return false
	version = int(head["version"])
	layer = int(head["layer"])
	sample_rate = int(head["rate"])
	bit_rate = int(head["bitrate"]) * 1000
	mode = int(head["mode"])
	mode_extension = int(head["mode_extension"])
	protected = bool(head["protected"])
	channels = 1 if mode == MODE_MONO else 2
	samples_per_frame = int(head["samples"])
	if layer == LAYER_III:
		error = ("Layer III at %d Hz, %d bit/s: only Layers I and II are decoded. "
			+ "Layer III is Huffman coded, with a bit reservoir that puts a "
			+ "frame's data in an earlier frame, window switching and a hybrid "
			+ "IMDCT — none of which Layer II has.") % [sample_rate, bit_rate]
		return false
	while at + 4 <= n:
		var frame := _read_header(at)
		if frame.is_empty():
			# Not a header here. Hunt for the next sync word and count it; that
			# count is what says whether this was a walk or a search.
			rejected_headers += 1
			var next := _find_sync(at + 1)
			if next < 0:
				break
			resyncs += 1
			at = next
			continue
		var length := int(frame["length"])
		if at + length > n:
			# The multiplex cut the last frame short. Normal, and not a
			# resynchronisation: all 22 files in this corpus end this way, by
			# between 28 and 725 bytes.
			truncated_tail = n - at
			break
		frame_offsets.append(at)
		frame_lengths.append(length)
		sample_frames += int(frame["samples"])
		at += length
	frame_count = frame_offsets.size()
	if frame_count == 0:
		error = "no complete MPEG audio frame in %d bytes" % n
		return false
	return true


## The running time of what `scan` found, in milliseconds.
func duration_ms() -> float:
	if sample_rate <= 0:
		return 0.0
	return float(sample_frames) * 1000.0 / float(sample_rate)


func decode_cost_us() -> int:
	return _decode_us


func _reset() -> void:
	error = ""
	frame_offsets = PackedInt32Array()
	frame_lengths = PackedInt32Array()
	frame_count = 0
	sample_frames = 0
	resyncs = 0
	rejected_headers = 0
	truncated_tail = 0
	_decode_us = 0


func _find_sync(from: int) -> int:
	var n := _es.size()
	var at := from
	while at + 4 <= n:
		if _es[at] == 0xFF and (_es[at + 1] & 0xE0) == 0xE0:
			return at
		at += 1
	return -1


## One frame header, or an empty dictionary when the four bytes at `at` are not
## one. Every field the rest of this file needs, plus the frame's byte length.
func _read_header(at: int) -> Dictionary:
	var n := _es.size()
	if at + 4 > n:
		return {}
	if _es[at] != 0xFF or (_es[at + 1] & 0xE0) != 0xE0:
		return {}
	var b1 := _es[at + 1]
	var b2 := _es[at + 2]
	var b3 := _es[at + 3]
	var ver := (b1 >> 3) & 0x03
	var lay_bits := (b1 >> 1) & 0x03
	var bitrate_index := (b2 >> 4) & 0x0F
	var rate_index := (b2 >> 2) & 0x03
	if ver == 1 or lay_bits == 0 or rate_index == 3:
		return {}
	if bitrate_index == 0 or bitrate_index == 15:
		# Free format states no length in the header, and 15 is reserved. Both are
		# refused rather than guessed at; a guess here desynchronises the walk.
		return {}
	var lay := 4 - lay_bits
	var rate := 0
	match ver:
		3: rate = RATE_V1[rate_index]
		2: rate = RATE_V2[rate_index]
		_: rate = RATE_V25[rate_index]
	var kbps := 0
	if ver == 3:
		kbps = int([BITRATE_V1_L1, BITRATE_V1_L2, BITRATE_V1_L3][lay - 1][bitrate_index])
	else:
		kbps = int((BITRATE_V2_L1 if lay == 1 else BITRATE_V2_L23)[bitrate_index])
	var padding := (b2 >> 1) & 0x01
	var length := 0
	var samples := 0
	if lay == LAYER_I:
		length = (12 * kbps * 1000 / rate + padding) * 4
		samples = 384
	elif lay == LAYER_II:
		length = 144 * kbps * 1000 / rate + padding
		samples = 1152
	else:
		length = (144 if ver == 3 else 72) * kbps * 1000 / rate + padding
		samples = 1152 if ver == 3 else 576
	if length <= 4:
		return {}
	return {
		"version": ver, "layer": lay, "rate": rate, "bitrate": kbps,
		"mode": (b3 >> 6) & 0x03, "mode_extension": (b3 >> 4) & 0x03,
		"protected": (b1 & 0x01) == 0, "length": length, "samples": samples,
	}


# ================================================================== the decode


## Decode frames `[from_frame, from_frame + count)` to interleaved signed 16-bit
## little-endian PCM. `count` below zero means "to the end".
##
## The filterbank carries state across frames — the 1,024 sample ring is what a
## polyphase filter *is* — so a decode that does not start at frame 0 starts with
## an empty ring and its first 481 output samples are the filter warming up. That
## is why `director_mpeg1.gd` decodes the whole track in one call rather than in
## chunks: the seam between two chunks would be an audible click, and the only
## honest way to decode from the middle is to have decoded what came before.
func decode(from_frame: int = 0, count: int = -1) -> PackedByteArray:
	build_tables()
	var began := Time.get_ticks_usec()
	var first: int = clampi(from_frame, 0, frame_count)
	var last := frame_count if count < 0 else mini(first + count, frame_count)
	var out := PackedByteArray()
	if last <= first:
		return out
	out.resize((last - first) * samples_per_frame * channels * 2)
	_v = []
	for _ch in 2:
		var ring := PackedVector4Array()
		ring.resize(256)
		_v.append(ring)
	_voffs = 0
	var write := 0
	for f in range(first, last):
		if layer == LAYER_I:
			write = _decode_layer1(frame_offsets[f], out, write)
		else:
			write = _decode_layer2(frame_offsets[f], out, write)
	if write < out.size():
		out.resize(write)
	_decode_us += Time.get_ticks_usec() - began
	return out


## Layer II, ISO §2.4.2.3 and §2.4.3.
##
## Order on the wire: allocations for every subband (both channels below the
## joint stereo bound, one shared above it), then two bits of scalefactor
## selection per allocated subband, then the scalefactors those select, then
## twelve granules of three subband samples each in three groups of four.
func _decode_layer2(at: int, out: PackedByteArray, write: int) -> int:
	var head := _read_header(at)
	if head.is_empty():
		return write
	_seek_bits(at + 4)
	if bool(head["protected"]):
		_bits(16)  # the CRC, which nothing here verifies; see this file's head
	var channel_mode := int(head["mode"])
	var nch := 1 if channel_mode == MODE_MONO else 2
	var selected := allocation_table(
		int(head["version"]), int(head["rate"]), int(head["bitrate"]), channel_mode)
	var rows: Array = ALLOC_ROWS[int(selected[0])]
	var sblimit := int(selected[1])
	# Above the bound a joint stereo stream sends one set of codes for both
	# channels. Plain stereo has no bound, mono is all shared, and either way the
	# bound never exceeds the table's own subband limit.
	var bound := 32
	if channel_mode == MODE_JOINT:
		bound = (int(head["mode_extension"]) + 1) << 2
	elif channel_mode == MODE_MONO:
		bound = 0
	bound = mini(bound, sblimit)

	var alloc := PackedInt32Array()
	alloc.resize(64)
	for sb in bound:
		for ch in 2:
			alloc[ch * 32 + sb] = _read_allocation(rows, sb)
	for sb in range(bound, sblimit):
		var shared := _read_allocation(rows, sb)
		alloc[sb] = shared
		alloc[32 + sb] = shared

	var scfsi := PackedInt32Array()
	scfsi.resize(64)
	for sb in sblimit:
		for ch in nch:
			if alloc[ch * 32 + sb] != 0:
				scfsi[ch * 32 + sb] = _bits(2)
		if nch == 1:
			scfsi[32 + sb] = scfsi[sb]

	var scale := PackedFloat32Array()
	scale.resize(192)
	for sb in sblimit:
		for ch in nch:
			if alloc[ch * 32 + sb] == 0:
				continue
			var base := (ch * 32 + sb) * 3
			match scfsi[ch * 32 + sb]:
				0:
					scale[base] = _scalefactor[_bits(6)]
					scale[base + 1] = _scalefactor[_bits(6)]
					scale[base + 2] = _scalefactor[_bits(6)]
				1:
					var a := _scalefactor[_bits(6)]
					scale[base] = a
					scale[base + 1] = a
					scale[base + 2] = _scalefactor[_bits(6)]
				2:
					var b := _scalefactor[_bits(6)]
					scale[base] = b
					scale[base + 1] = b
					scale[base + 2] = b
				_:
					scale[base] = _scalefactor[_bits(6)]
					var c := _scalefactor[_bits(6)]
					scale[base + 1] = c
					scale[base + 2] = c
		if nch == 1:
			for part in 3:
				scale[(32 + sb) * 3 + part] = scale[sb * 3 + part]

	# `[idx][ch][sb]` flattened, so that the 32 values one transform wants are
	# contiguous and can be read with a running index rather than a stride.
	#
	# Zeroed **once** rather than per granule. Every subband below `sblimit` is
	# written every granule, with an explicit zero for an unallocated one, so the
	# only slots that rely on this clear are the subbands above `sblimit` — and
	# nothing ever writes those. Clearing 192 floats twelve times a frame was
	# costing more than the samples it was clearing for.
	var sample := PackedFloat32Array()
	sample.resize(3 * 64)
	for part in 3:
		for _gr in 4:
			for sb in bound:
				for ch in 2:
					_read_subband(sample, ch * 32 + sb, alloc[ch * 32 + sb],
						scale[(ch * 32 + sb) * 3 + part])
			for sb in range(bound, sblimit):
				# **Each channel applies its own scalefactor to the shared code.**
				# ISO §2.4.3.2. The shortcut of requantising once and copying the
				# result — which the widely copied minimal decoders take — is what
				# makes an intensity coded stream lean to one side. Nothing in this
				# corpus reaches here (mode 0 is plain stereo, so `bound` is
				# `sblimit`), so it is written from the specification and is
				# unverified against real data.
				var cls := alloc[sb]
				if cls == 0:
					_read_subband(sample, sb, 0, 0.0)
					_read_subband(sample, 32 + sb, 0, 0.0)
					continue
				var steps := _q_steps[cls]
				var codes := PackedInt32Array()
				codes.resize(3)
				_read_codes(cls, codes)
				for ch2 in 2:
					var sf := scale[(ch2 * 32 + sb) * 3 + part]
					var base := ch2 * 32 + sb
					for idx in 3:
						sample[idx * 64 + base] = 							float(2 * codes[idx] + 1 - steps) * _q_inv[cls] * sf
			for idx3 in 3:
				write = _synthesise(sample, idx3 * 64, out, write)
	return write


## One subband's three samples for one granule, read and requantised in place.
##
## The requantisation is `requantise` inlined and folded into the scalefactor:
## `(2 * code + 1 - steps) * (1 / steps) * scalefactor`, with the reciprocal from
## a table and the `1 - steps` hoisted. That is 2,160 fewer static calls and 2,160
## fewer divisions per frame, and it is the difference between the bit reading
## and requantisation costing more than the filterbank and costing less.
##
## An unallocated subband writes zeroes rather than returning, because the
## sample buffer is only cleared once per frame; see `_decode_layer2`.
func _read_subband(sample: PackedFloat32Array, base: int, cls: int,
		scalefactor: float) -> void:
	if cls == 0:
		sample[base] = 0.0
		sample[64 + base] = 0.0
		sample[128 + base] = 0.0
		return
	var steps := _q_steps[cls]
	var c0 := 0
	var c1 := 0
	var c2 := 0
	if _q_group[cls] != 0:
		# Three samples in one codeword, in base `steps`. This is why a 3, 5 or 9
		# level quantiser costs 5, 7 and 10 bits rather than 6, 9 and 12.
		var packed := _bits(_q_width[cls])
		c0 = packed % steps
		@warning_ignore("integer_division")
		packed /= steps
		c1 = packed % steps
		@warning_ignore("integer_division")
		c2 = packed / steps
	else:
		var width := _q_width[cls]
		c0 = _bits(width)
		c1 = _bits(width)
		c2 = _bits(width)
	var gain := _q_inv[cls] * scalefactor
	var offset := 1 - steps
	sample[base] = float(2 * c0 + offset) * gain
	sample[64 + base] = float(2 * c1 + offset) * gain
	sample[128 + base] = float(2 * c2 + offset) * gain


## Layer I, ISO §2.4.2.2 and §2.4.3.
##
## Four bits of allocation per subband — a code of `n` means `n + 1` bits per
## sample and `2^(n+1) - 1` levels, with 0 meaning nothing and 15 reserved — one
## scalefactor per allocated subband, then twelve granules of one sample per
## subband. No `scfsi`, no grouping, no subband limit.
##
## **Unverified against real data**: no file in any of the eight corpora is Layer
## I. It is here because the filterbank and the scalefactors are already here and
## Director's own MPEG playback would have taken it.
func _decode_layer1(at: int, out: PackedByteArray, write: int) -> int:
	var head := _read_header(at)
	if head.is_empty():
		return write
	_seek_bits(at + 4)
	if bool(head["protected"]):
		_bits(16)
	var channel_mode := int(head["mode"])
	var nch := 1 if channel_mode == MODE_MONO else 2
	var bound := 32
	if channel_mode == MODE_JOINT:
		bound = (int(head["mode_extension"]) + 1) << 2
	elif channel_mode == MODE_MONO:
		bound = 0
	var alloc := PackedInt32Array()
	alloc.resize(64)
	for sb in bound:
		for ch in 2:
			alloc[ch * 32 + sb] = _bits(4)
	for sb in range(bound, 32):
		var shared := _bits(4)
		alloc[sb] = shared
		alloc[32 + sb] = shared
	var scale := PackedFloat32Array()
	scale.resize(64)
	for sb in 32:
		for ch in nch:
			if alloc[ch * 32 + sb] != 0:
				scale[ch * 32 + sb] = _scalefactor[_bits(6)]
		if nch == 1:
			scale[32 + sb] = scale[sb]
	var sample := PackedFloat32Array()
	sample.resize(64)
	for _gr in 12:
		for i in 64:
			sample[i] = 0.0
		for sb in bound:
			for ch in 2:
				var nb := alloc[ch * 32 + sb]
				if nb == 0 or nb == 15:
					continue
				var steps := (1 << (nb + 1)) - 1
				sample[ch * 32 + sb] = requantise(_bits(nb + 1), steps) * scale[ch * 32 + sb]
		for sb in range(bound, 32):
			var nb2 := alloc[sb]
			if nb2 == 0 or nb2 == 15:
				continue
			var steps2 := (1 << (nb2 + 1)) - 1
			var code := _bits(nb2 + 1)
			for ch2 in 2:
				sample[ch2 * 32 + sb] = requantise(code, steps2) * scale[ch2 * 32 + sb]
		write = _synthesise(sample, 0, out, write)
	return write


## The allocation code for one subband, through its table's own row.
func _read_allocation(rows: Array, sb: int) -> int:
	var row: Array = rows[sb]
	var code := _bits(int(row[0]))
	return int(ALLOC_CODES[int(row[1])][code])


## Three consecutive samples of one subband, as raw codes.
##
## A grouped class packs all three into one codeword in base `steps`, which is
## what makes 3, 5 and 9 level quantisers cost 5, 7 and 10 bits rather than 6, 9
## and 12 — the whole reason the grouping exists.
func _read_codes(cls: int, into: PackedInt32Array) -> void:
	var spec: Array = QUANT_CLASS[cls - 1]
	var width := int(spec[1])
	if bool(spec[2]):
		var steps := int(spec[0])
		var packed := _bits(width)
		into[0] = packed % steps
		packed /= steps
		into[1] = packed % steps
		into[2] = packed / steps
		return
	into[0] = _bits(width)
	into[1] = _bits(width)
	into[2] = _bits(width)


# ============================================================== the filterbank


## One granule of 32 subband samples per channel into 32 PCM frames.
##
## ISO Annex A: shift the ring back 64, write the cosine transform of the subband
## samples into the hole, gather 512 of the ring's samples into `U`, multiply by
## the window and sum 16 taps per output.
##
## `U` is never built. Its index arithmetic — two runs of 32 taken 128 apart, the
## second offset 96 into the block — is folded into the gather below, because
## writing 512 floats and reading them back costs more than the multiplications
## do. Four adjacent outputs are computed at once as a `Vector4`, which is exactly
## what makes the 512 scalar multiply-accumulates into 128 vector ones: outputs
## `4g..4g+3` are contiguous in `U`, so their taps are contiguous too, and the
## componentwise product accumulates all four.
func _synthesise(sample: PackedFloat32Array, at: int, out: PackedByteArray,
		write: int) -> int:
	_voffs = (_voffs - 64) & 1023
	var o := _voffs >> 2
	var nch := channels
	for ch in nch:
		var ring: PackedVector4Array = _v[ch]
		_dct32_into_ring(sample, at + ch * 32, ring, _voffs)
		var at_byte := write + ch * 2
		for g in 8:
			var acc := Vector4.ZERO
			var wi := g
			var vi := o + g
			for _b in 8:
				acc += ring[vi & 255] * _window4[wi]
				acc += ring[(vi + 24) & 255] * _window4[wi + 8]
				wi += 16
				vi += 32
			# 32,768 is the gain that takes ISO's unit scaled filterbank to signed
			# 16 bit; the derivation is in `tools/mpeg1_audio.gd`, which checks it
			# against a full scale sine rather than asserting it here.
			out.encode_s16(at_byte, clampi(int(round(acc.x * 32768.0)), -32768, 32767))
			out.encode_s16(at_byte + nch * 2, clampi(int(round(acc.y * 32768.0)), -32768, 32767))
			out.encode_s16(at_byte + nch * 4, clampi(int(round(acc.z * 32768.0)), -32768, 32767))
			out.encode_s16(at_byte + nch * 6, clampi(int(round(acc.w * 32768.0)), -32768, 32767))
			at_byte += nch * 8
	return write + 32 * nch * 2


# ============================================================== the bit reader


## `n` bits, most significant first, from the elementary stream.
##
## A shift register refilled a byte at a time. The obvious alternative — a byte
## index and a bit index, masking across the boundary — is what this was, and it
## was worth replacing: `n` is at most 16 and averages about 5, so the old form's
## loop ran once or twice per call, and the call happens roughly 2,700 times per
## frame. Here the refill loop runs at most twice and usually not at all.
##
## At most 23 bits are ever live, so masking the register to 32 keeps it from
## growing without bound. Reading past the end answers zeroes, which is what makes
## a truncated final frame decode to a quiet granule instead of to an error.
func _bits(n: int) -> int:
	var size := _es.size()
	while _cache_bits < n:
		var byte := 0
		if _at < size:
			byte = _es[_at]
		_at += 1
		_cache = ((_cache << 8) | byte) & 0xFFFFFFFF
		_cache_bits += 8
	_cache_bits -= n
	return (_cache >> _cache_bits) & ((1 << n) - 1)


## Enter a frame at a byte offset, discarding whatever the register held.
func _seek_bits(at: int) -> void:
	_at = at
	_cache = 0
	_cache_bits = 0


## The 32-to-64 point cosine transform of ISO Annex A, written as a 32-point
## DCT-II and a table of signs.
##
## ISO states the transform as `V[i] = sum_k S[k] cos((16 + i)(2k + 1)pi / 64)`
## for i in 0..63 — 2,048 multiply-accumulates, which is most of a Layer II
## decoder's arithmetic if it is taken literally. It need not be. Writing
## `n = 16 + i` and `phi = (2k + 1)pi / 64`, the kernel folds twice:
## `cos((128 - n)phi) = cos(n phi)` because `128 phi` is a whole number of turns,
## and `cos((64 +/- m)phi) = -cos(m phi)` because `64 phi` is an odd number of
## half turns. So all 64 outputs come from **32** values
## `T[m] = sum_k S[k] cos(m(2k+1)pi/64)`, m in 0..31 — which is exactly a 32-point
## DCT-II — with `T[32]` identically zero because its cosines all are.
##
## The DCT itself is Lee's recursion (`X[2k] = DCT(x[n] + x[N-1-n])[k]`,
## `X[2k+1] = DCT((x[n] - x[N-1-n]) / 2cos(...))[k] + [k+1]`) unrolled to straight
## line code: 80 multiplications and 209 statements against the definition's
## 1,024 multiply-accumulates, and every intermediate a local rather than an array
## slot, which in GDScript is the larger half of the win. The block below is
## generated; `tools/mpeg1_audio.gd` checks all 32 outputs against a direct
## evaluation of the definition, which is the only reason it is safe to have
## written this way — the same arrangement `tools/mpeg1_decode.gd` uses for the
## video half's integer IDCT.
##
## Writes the 64 results straight into the channel's ring as sixteen `Vector4`,
## because the windowing pass reads it in that form and a scalar intermediate
## would cost more than it saves.
func _dct32_into_ring(s: PackedFloat32Array, at: int, ring: PackedVector4Array, off: int) -> void:
	var s0 := s[at + 0]
	var s1 := s[at + 1]
	var s2 := s[at + 2]
	var s3 := s[at + 3]
	var s4 := s[at + 4]
	var s5 := s[at + 5]
	var s6 := s[at + 6]
	var s7 := s[at + 7]
	var s8 := s[at + 8]
	var s9 := s[at + 9]
	var s10 := s[at + 10]
	var s11 := s[at + 11]
	var s12 := s[at + 12]
	var s13 := s[at + 13]
	var s14 := s[at + 14]
	var s15 := s[at + 15]
	var s16 := s[at + 16]
	var s17 := s[at + 17]
	var s18 := s[at + 18]
	var s19 := s[at + 19]
	var s20 := s[at + 20]
	var s21 := s[at + 21]
	var s22 := s[at + 22]
	var s23 := s[at + 23]
	var s24 := s[at + 24]
	var s25 := s[at + 25]
	var s26 := s[at + 26]
	var s27 := s[at + 27]
	var s28 := s[at + 28]
	var s29 := s[at + 29]
	var s30 := s[at + 30]
	var s31 := s[at + 31]
	var t0 := s0 + s31
	var t1 := s1 + s30
	var t2 := s2 + s29
	var t3 := s3 + s28
	var t4 := s4 + s27
	var t5 := s5 + s26
	var t6 := s6 + s25
	var t7 := s7 + s24
	var t8 := s8 + s23
	var t9 := s9 + s22
	var t10 := s10 + s21
	var t11 := s11 + s20
	var t12 := s12 + s19
	var t13 := s13 + s18
	var t14 := s14 + s17
	var t15 := s15 + s16
	var t16 := (s0 - s31) * 0.50060299823519627
	var t17 := (s1 - s30) * 0.50547095989754365
	var t18 := (s2 - s29) * 0.51544730992262455
	var t19 := (s3 - s28) * 0.53104259108978413
	var t20 := (s4 - s27) * 0.55310389603444454
	var t21 := (s5 - s26) * 0.58293496820613389
	var t22 := (s6 - s25) * 0.62250412303566482
	var t23 := (s7 - s24) * 0.67480834145500568
	var t24 := (s8 - s23) * 0.74453627100229858
	var t25 := (s9 - s22) * 0.83934964541552681
	var t26 := (s10 - s21) * 0.97256823786196078
	var t27 := (s11 - s20) * 1.1694399334328847
	var t28 := (s12 - s19) * 1.4841646163141662
	var t29 := (s13 - s18) * 2.0577810099534108
	var t30 := (s14 - s17) * 3.407608418468719
	var t31 := (s15 - s16) * 10.190008123548033
	var t32 := t0 + t15
	var t33 := t1 + t14
	var t34 := t2 + t13
	var t35 := t3 + t12
	var t36 := t4 + t11
	var t37 := t5 + t10
	var t38 := t6 + t9
	var t39 := t7 + t8
	var t40 := (t0 - t15) * 0.50241928618815568
	var t41 := (t1 - t14) * 0.52249861493968885
	var t42 := (t2 - t13) * 0.56694403481635769
	var t43 := (t3 - t12) * 0.64682178335999008
	var t44 := (t4 - t11) * 0.7881546234512502
	var t45 := (t5 - t10) * 1.0606776859903471
	var t46 := (t6 - t9) * 1.7224470982383342
	var t47 := (t7 - t8) * 5.1011486186891553
	var t48 := t32 + t39
	var t49 := t33 + t38
	var t50 := t34 + t37
	var t51 := t35 + t36
	var t52 := (t32 - t39) * 0.50979557910415918
	var t53 := (t33 - t38) * 0.60134488693504529
	var t54 := (t34 - t37) * 0.89997622313641557
	var t55 := (t35 - t36) * 2.5629154477415055
	var t56 := t48 + t51
	var t57 := t49 + t50
	var t58 := (t48 - t51) * 0.54119610014619701
	var t59 := (t49 - t50) * 1.3065629648763764
	var t60 := t56 + t57
	var t61 := (t56 - t57) * 0.70710678118654746
	var t62 := t58 + t59
	var t63 := (t58 - t59) * 0.70710678118654746
	var t64 := t62 + t63
	var t65 := t52 + t55
	var t66 := t53 + t54
	var t67 := (t52 - t55) * 0.54119610014619701
	var t68 := (t53 - t54) * 1.3065629648763764
	var t69 := t65 + t66
	var t70 := (t65 - t66) * 0.70710678118654746
	var t71 := t67 + t68
	var t72 := (t67 - t68) * 0.70710678118654746
	var t73 := t71 + t72
	var t74 := t69 + t73
	var t75 := t73 + t70
	var t76 := t70 + t72
	var t77 := t40 + t47
	var t78 := t41 + t46
	var t79 := t42 + t45
	var t80 := t43 + t44
	var t81 := (t40 - t47) * 0.50979557910415918
	var t82 := (t41 - t46) * 0.60134488693504529
	var t83 := (t42 - t45) * 0.89997622313641557
	var t84 := (t43 - t44) * 2.5629154477415055
	var t85 := t77 + t80
	var t86 := t78 + t79
	var t87 := (t77 - t80) * 0.54119610014619701
	var t88 := (t78 - t79) * 1.3065629648763764
	var t89 := t85 + t86
	var t90 := (t85 - t86) * 0.70710678118654746
	var t91 := t87 + t88
	var t92 := (t87 - t88) * 0.70710678118654746
	var t93 := t91 + t92
	var t94 := t81 + t84
	var t95 := t82 + t83
	var t96 := (t81 - t84) * 0.54119610014619701
	var t97 := (t82 - t83) * 1.3065629648763764
	var t98 := t94 + t95
	var t99 := (t94 - t95) * 0.70710678118654746
	var t100 := t96 + t97
	var t101 := (t96 - t97) * 0.70710678118654746
	var t102 := t100 + t101
	var t103 := t98 + t102
	var t104 := t102 + t99
	var t105 := t99 + t101
	var t106 := t89 + t103
	var t107 := t103 + t93
	var t108 := t93 + t104
	var t109 := t104 + t90
	var t110 := t90 + t105
	var t111 := t105 + t92
	var t112 := t92 + t101
	var t113 := t16 + t31
	var t114 := t17 + t30
	var t115 := t18 + t29
	var t116 := t19 + t28
	var t117 := t20 + t27
	var t118 := t21 + t26
	var t119 := t22 + t25
	var t120 := t23 + t24
	var t121 := (t16 - t31) * 0.50241928618815568
	var t122 := (t17 - t30) * 0.52249861493968885
	var t123 := (t18 - t29) * 0.56694403481635769
	var t124 := (t19 - t28) * 0.64682178335999008
	var t125 := (t20 - t27) * 0.7881546234512502
	var t126 := (t21 - t26) * 1.0606776859903471
	var t127 := (t22 - t25) * 1.7224470982383342
	var t128 := (t23 - t24) * 5.1011486186891553
	var t129 := t113 + t120
	var t130 := t114 + t119
	var t131 := t115 + t118
	var t132 := t116 + t117
	var t133 := (t113 - t120) * 0.50979557910415918
	var t134 := (t114 - t119) * 0.60134488693504529
	var t135 := (t115 - t118) * 0.89997622313641557
	var t136 := (t116 - t117) * 2.5629154477415055
	var t137 := t129 + t132
	var t138 := t130 + t131
	var t139 := (t129 - t132) * 0.54119610014619701
	var t140 := (t130 - t131) * 1.3065629648763764
	var t141 := t137 + t138
	var t142 := (t137 - t138) * 0.70710678118654746
	var t143 := t139 + t140
	var t144 := (t139 - t140) * 0.70710678118654746
	var t145 := t143 + t144
	var t146 := t133 + t136
	var t147 := t134 + t135
	var t148 := (t133 - t136) * 0.54119610014619701
	var t149 := (t134 - t135) * 1.3065629648763764
	var t150 := t146 + t147
	var t151 := (t146 - t147) * 0.70710678118654746
	var t152 := t148 + t149
	var t153 := (t148 - t149) * 0.70710678118654746
	var t154 := t152 + t153
	var t155 := t150 + t154
	var t156 := t154 + t151
	var t157 := t151 + t153
	var t158 := t121 + t128
	var t159 := t122 + t127
	var t160 := t123 + t126
	var t161 := t124 + t125
	var t162 := (t121 - t128) * 0.50979557910415918
	var t163 := (t122 - t127) * 0.60134488693504529
	var t164 := (t123 - t126) * 0.89997622313641557
	var t165 := (t124 - t125) * 2.5629154477415055
	var t166 := t158 + t161
	var t167 := t159 + t160
	var t168 := (t158 - t161) * 0.54119610014619701
	var t169 := (t159 - t160) * 1.3065629648763764
	var t170 := t166 + t167
	var t171 := (t166 - t167) * 0.70710678118654746
	var t172 := t168 + t169
	var t173 := (t168 - t169) * 0.70710678118654746
	var t174 := t172 + t173
	var t175 := t162 + t165
	var t176 := t163 + t164
	var t177 := (t162 - t165) * 0.54119610014619701
	var t178 := (t163 - t164) * 1.3065629648763764
	var t179 := t175 + t176
	var t180 := (t175 - t176) * 0.70710678118654746
	var t181 := t177 + t178
	var t182 := (t177 - t178) * 0.70710678118654746
	var t183 := t181 + t182
	var t184 := t179 + t183
	var t185 := t183 + t180
	var t186 := t180 + t182
	var t187 := t170 + t184
	var t188 := t184 + t174
	var t189 := t174 + t185
	var t190 := t185 + t171
	var t191 := t171 + t186
	var t192 := t186 + t173
	var t193 := t173 + t182
	var t194 := t141 + t187
	var t195 := t187 + t155
	var t196 := t155 + t188
	var t197 := t188 + t145
	var t198 := t145 + t189
	var t199 := t189 + t156
	var t200 := t156 + t190
	var t201 := t190 + t142
	var t202 := t142 + t191
	var t203 := t191 + t157
	var t204 := t157 + t192
	var t205 := t192 + t144
	var t206 := t144 + t193
	var t207 := t193 + t153
	var t208 := t153 + t182
	var T0 := t60
	var T1 := t194
	var T2 := t106
	var T3 := t195
	var T4 := t74
	var T5 := t196
	var T6 := t107
	var T7 := t197
	var T8 := t64
	var T9 := t198
	var T10 := t108
	var T11 := t199
	var T12 := t75
	var T13 := t200
	var T14 := t109
	var T15 := t201
	var T16 := t61
	var T17 := t202
	var T18 := t110
	var T19 := t203
	var T20 := t76
	var T21 := t204
	var T22 := t111
	var T23 := t205
	var T24 := t63
	var T25 := t206
	var T26 := t112
	var T27 := t207
	var T28 := t72
	var T29 := t208
	var T30 := t101
	var T31 := t182
	var q := off >> 2
	ring[q + 0] = Vector4(T16, T17, T18, T19)
	ring[q + 1] = Vector4(T20, T21, T22, T23)
	ring[q + 2] = Vector4(T24, T25, T26, T27)
	ring[q + 3] = Vector4(T28, T29, T30, T31)
	ring[q + 4] = Vector4(0.0, -T31, -T30, -T29)
	ring[q + 5] = Vector4(-T28, -T27, -T26, -T25)
	ring[q + 6] = Vector4(-T24, -T23, -T22, -T21)
	ring[q + 7] = Vector4(-T20, -T19, -T18, -T17)
	ring[q + 8] = Vector4(-T16, -T15, -T14, -T13)
	ring[q + 9] = Vector4(-T12, -T11, -T10, -T9)
	ring[q + 10] = Vector4(-T8, -T7, -T6, -T5)
	ring[q + 11] = Vector4(-T4, -T3, -T2, -T1)
	ring[q + 12] = Vector4(-T0, -T1, -T2, -T3)
	ring[q + 13] = Vector4(-T4, -T5, -T6, -T7)
	ring[q + 14] = Vector4(-T8, -T9, -T10, -T11)
	ring[q + 15] = Vector4(-T12, -T13, -T14, -T15)
