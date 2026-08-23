extends SceneTree
## Assert the GDScript MPEG-1 Layer II audio decoder, and say what it costs.
##
##   godot --headless --audio-driver Dummy --path . --script tools/mpeg1_audio.gd -- \
##       --root res://test-games/itamar-magichat --oracle
##
##   --root R       the corpus (`DirectorPaths` honours it; default the config's)
##   --file P       one file instead of a sweep, `res://` or absolute
##   --seconds N    decode at most N seconds of each clip (default 8)
##   --all          decode every clip in full; minutes, not seconds
##   --oracle       compare against the Vorbis track of an Ogg sidecar
##   --wav DIR      write what it decoded as `.wav`, for listening to by hand
##   --bench        time the filterbank's inner loop on its own
##
## ## Two halves, and only one of them needs a corpus
##
## `gate.sh` runs this **bare**, on `GATE_ROOT`, where there is no MPEG-1 file at
## all — the same position `mpeg1_decode` is in, and for the same reason: the one
## corpus with MPEG audio in it is `test-games/itamar-magichat`, which is not in
## the repository. So the assertions are split the way that file splits them.
##
## **The format half is corpus-independent and always runs.** It is where a Layer
## II decoder is wrong in ways that sound like a bad encode rather than like a
## bug:
##
##   * the **allocation table selection**, checked over all 168 legal combinations
##     of sampling rate, channel mode and bit rate against a second, independent
##     statement of ISO's own lookup. This is the one to care about. Layer II
##     picks its table from the bit rate **per channel**, and Table B.2a is Table
##     B.2b truncated at 27 subbands — so reading the header's 224 kbit/s as if
##     it were per-channel does not crash and does not produce noise, it silently
##     drops subbands 27 to 29 and then desynchronises the bitstream a few frames
##     later, which reads as a bad file rather than as a bad decoder;
##   * the **requantiser**, checked in closed form against the seventeen `C` and
##     `D` constants ISO Table B.4 prints. The widely copied minimal decoders
##     divide by `steps + 1`, which is right to a part in 65,536 for the ungrouped
##     classes and 25% quiet on a three level subband;
##   * the **32-point cosine transform**, which is unrolled straight line code
##     generated from Lee's recursion, checked against a direct evaluation of the
##     transform's definition — the same arrangement `tools/mpeg1_decode.gd` uses
##     for the video half's integer IDCT, and for the same reason;
##   * the **synthesis window**, checked by driving one subband at a time through
##     the filterbank and measuring how much of the energy lands anywhere other
##     than that subband's own frequency. A window with one coefficient wrong is
##     still a low-pass filter and still produces a tone; what it stops doing is
##     confining that tone;
##   * the **frame length arithmetic**, over every legal (layer, rate, bit rate)
##     triple, because that is what the walk below navigates by.
##
## **The data half runs when there is data**, and says out loud when it finds
## none.
##
## ## The check that is worth more than all the others
##
## `resyncs`. An MPEG audio frame has no length field: the length is computed
## from the bit rate, the sampling rate and one padding bit, and the only thing
## that says those three were read correctly is that the computed length lands
## exactly on the next sync word. Nothing else ties one frame to the next. Over
## the 22 files of `test-games/itamar-magichat` that is **38,060 consecutive
## landings** — this file's equivalent of `mpeg1_decode`'s `0 desynchronised
## slices`, and the strongest statement available without a second decoder.
##
## When there *is* a second decoder — `--oracle` — the comparison is against the
## Vorbis track of the owner's Ogg sidecar, which is an independent decode of the
## same source by a tool that is not this port, exactly as its Theora track is
## the oracle for the pictures. The sidecar's Vorbis stream is lifted out of the
## `.ogv` by page serial number and handed to Godot's own decoder, so nothing is
## written and no transcoder runs.
##
## Title-agnostic: it names no game and no file.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const Mpeg1 := preload("res://director/director_mpeg1.gd")
const Mp2 := preload("res://director/director_mpeg1_audio.gd")
const Ps := preload("res://director/director_mpeg1_ps.gd")
const Sidecar := preload("res://director/director_sidecar.gd")

const EXTENSIONS := ["mpg", "mpeg", "mp2", "mpa"]

## ISO/IEC 11172-3 Table B.4 as the standard prints it: the scale `C` and the
## offset `D` of each of the seventeen quantisation classes, to the eight decimal
## places Annex B gives. Written out here a second time rather than derived, so
## that `Mp2.requantise`'s closed form is compared against a statement of the
## table and not against itself — the same deliberate duplication
## `tools/mpeg1_decode.gd` applies to the video half's VLC tables.
const TABLE_B4 := [
	[3, 1.33333333, 0.50000000], [5, 1.60000000, 0.50000000],
	[7, 1.14285714, 0.25000000], [9, 1.77777778, 0.50000000],
	[15, 1.06666667, 0.12500000], [31, 1.03225806, 0.06250000],
	[63, 1.01587302, 0.03125000], [127, 1.00787402, 0.01562500],
	[255, 1.00392157, 0.00781250], [511, 1.00195695, 0.00390625],
	[1023, 1.00097752, 0.00195313], [2047, 1.00048852, 0.00097656],
	[4095, 1.00024420, 0.00048828], [8191, 1.00012209, 0.00024414],
	[16383, 1.00006104, 0.00012207], [32767, 1.00003052, 0.00006104],
	[65535, 1.00001526, 0.00003052],
]

## ISO's own allocation table lookup, restated. `[mode][bitrate index - 1]`
## chooses a group, and the group and the sampling frequency index choose the
## table — which is the form the standard's implementation notes give and is a
## genuinely different shape from `Mp2.allocation_table`'s "bit rate per channel"
## rule. Two formulations that agree over all 168 combinations is the check; one
## formulation compared against itself is not.
const ISO_GROUP_STEREO := [0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2]
const ISO_GROUP_MONO := [0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2]
## `[group][sampling frequency index]`, 0 = 44.1 kHz, 1 = 48 kHz, 2 = 32 kHz.
const ISO_TABLE_BY_GROUP := [
	["C", "C", "D"],
	["A", "A", "A"],
	["B", "A", "B"],
]
const ISO_BITRATE_L2 := [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	var args := Args.parse()
	_format_checks(h, args)
	_corpus_checks(h, args)
	quit(h.finish("MPEG-1 Layer II decodes in GDScript, and what that costs is measured"))


# ============================================================ the format half


func _format_checks(h: Harness, args: Dictionary) -> void:
	var case := "the MPEG audio format tables and the filterbank"
	h.begin(case)
	Mp2.build_tables()
	_check_window(h)
	_check_dct(h)
	_check_requantiser(h)
	_check_allocation_selection(h)
	_check_allocation_rows(h)
	_check_scalefactors(h)
	_check_frame_lengths(h)
	_check_filterbank(h)
	if Args.flag(args, "bench"):
		_bench()
	h.complete(case)


## ISO Table B.3 by its own peak.
##
## 512 coefficients is too many to check by transcribing them a second time, and
## the standard prints exactly one number that identifies the table on sight: its
## largest coefficient, 1.144989014. At the 16.16 fixed point this decoder holds
## the window in, that is 75,038 — and 75,038 / 65,536 is 1.144989013671875,
## which rounds to the standard's printed nine digits and to no other table's.
## The behavioural check is `_check_filterbank`.
func _check_window(h: Harness) -> void:
	var raw: Array = Mp2.window_raw()
	h.check("the synthesis window has ISO Table B.3's 512 coefficients",
		raw.size() == 512, "%d entries" % raw.size())
	var peak := 0
	var zeroes := 0
	for value in raw:
		peak = maxi(peak, absi(int(value)))
		if int(value) == 0:
			zeroes += 1
	h.check("its largest coefficient is Table B.3's 1.144989014",
		peak == 75038 and is_equal_approx(float(peak) / 65536.0, 1.144989013671875),
		"peak %d, %.15f at 16.16" % [peak, float(peak) / 65536.0])
	# The window tapers to nothing at both ends; a table that had been truncated
	# or shifted would not have its zeroes at the front.
	h.check("the window is a taper: its only zero coefficients are at the head",
		zeroes == 7 and int(raw[0]) == 0 and int(raw[6]) == 0 and int(raw[7]) != 0,
		"%d zero coefficients" % zeroes)


## The unrolled 32-point transform against a direct evaluation of its definition.
##
## `V[i] = sum_k S[k] cos((16 + i)(2k + 1)pi / 64)` is what ISO Annex A states;
## the decoder computes it as a 32-point DCT-II folded three ways and unrolled to
## straight line code, which is 80 multiplications instead of 2,048 and is
## unreadable. So it is checked against the definition, evaluated here at full
## width, on a signal designed to leave nothing untouched: every subband non-zero,
## alternating in sign, and no two the same.
func _check_dct(h: Harness) -> void:
	var s := PackedFloat32Array()
	s.resize(32)
	for k in 32:
		s[k] = (1.0 if k % 2 == 0 else -1.0) * (0.11 + 0.03 * float(k)) * cos(float(k))
	var ring := PackedVector4Array()
	ring.resize(256)
	var probe := Mp2.new()
	probe._dct32_into_ring(s, 0, ring, 0)
	var worst := 0.0
	for i in 64:
		var want := 0.0
		for k in 32:
			want += s[k] * cos(PI * float(16 + i) * float(2 * k + 1) / 64.0)
		var got: float = ring[i >> 2][i & 3]
		worst = maxf(worst, absf(want - got))
	h.check("the unrolled cosine transform matches the definition it folds",
		worst < 1.0e-4, "worst |difference| %.10f over all 64 outputs" % worst)


## The requantiser's closed form against ISO Table B.4's printed constants.
##
## The decoder computes `(2 * code + 1 - steps) / steps`. The standard computes
## `C * (fraction + D)` from a seventeen row table. Every code of every class is
## checked, which is 143,000 comparisons and takes no measurable time.
func _check_requantiser(h: Harness) -> void:
	var worst := 0.0
	var worst_at := ""
	var wrong_alternative := 0.0
	for row in TABLE_B4:
		var steps := int(row[0])
		var c := float(row[1])
		var d := float(row[2])
		var nb := 1
		while (1 << nb) < steps + 1:
			nb += 1
		for code in steps:
			# ISO: invert the most significant bit, read as a two's complement
			# fraction of `nb` bits, then scale and offset.
			var fraction := float(code - (1 << (nb - 1))) / float(1 << (nb - 1))
			var want := c * (fraction + d)
			var got: float = Mp2.requantise(code, steps)
			if absf(want - got) > worst:
				worst = absf(want - got)
				worst_at = "%d levels, code %d: table %.6f, closed form %.6f" % [
					steps, code, want, got]
			wrong_alternative = maxf(wrong_alternative,
				absf(want - float(2 * code + 1 - steps) / float(steps + 1)))
	h.check("requantisation matches ISO Table B.4 for every code of every class",
		worst < 1.0e-6, "worst %.10f%s" % [worst, ("  (%s)" % worst_at) if worst_at != "" else ""])
	# The control for the check above: the form this decoder deliberately does
	# not use has to be measurably wrong, or the check has proved nothing.
	h.check("dividing by steps + 1 instead would be wrong, so the check has teeth",
		wrong_alternative > 0.1,
		"the (steps + 1) form is off by up to %.3f of full scale" % wrong_alternative)


## Which allocation table a stream selects, over all 168 legal combinations.
##
## The decoder decides from the bit rate **per channel** and the sampling rate,
## which is how ISO §2.4.2.3 states the rule. This checks it against ISO's own
## implementation lookup — a bit rate index into a group, then the group and the
## sampling frequency into a table letter — which arrives at the same answer by a
## different route. Both formulations exist in the wild and disagreeing is the
## classic Layer II defect, so they are made to agree here over everything.
func _check_allocation_selection(h: Harness) -> void:
	var letters := {
		"A": Mp2.TABLE_A, "B": Mp2.TABLE_B, "C": Mp2.TABLE_C, "D": Mp2.TABLE_D,
	}
	var rates := [44100, 48000, 32000]
	var wrong: Array[String] = []
	var checked := 0
	for rate_index in 3:
		for mode in [Mp2.MODE_STEREO, Mp2.MODE_JOINT, Mp2.MODE_DUAL, Mp2.MODE_MONO]:
			for i in ISO_BITRATE_L2.size():
				var kbps: int = ISO_BITRATE_L2[i]
				var group: int = int(
					ISO_GROUP_MONO[i] if mode == Mp2.MODE_MONO else ISO_GROUP_STEREO[i])
				var want: Array = letters[ISO_TABLE_BY_GROUP[group][rate_index]]
				var got: Array = Mp2.allocation_table(3, rates[rate_index], kbps, mode)
				checked += 1
				if got != want:
					wrong.append("%d Hz, mode %d, %d kbit/s: rows %d/sblimit %d, wanted %d/%d" % [
						rates[rate_index], mode, kbps, got[0], got[1], want[0], want[1]])
	h.check("the allocation table is selected per channel over all %d combinations" % checked,
		wrong.is_empty(), "; ".join(wrong.slice(0, 4)))
	# The corpus's own case, named, because it is the one this port had to get
	# right and the one a reader of the report wants to see stated.
	var corpus: Array = Mp2.allocation_table(3, 44100, 224, Mp2.MODE_STEREO)
	h.check("44.1 kHz stereo at 224 kbit/s is 112 per channel, so Table B.2b",
		corpus == Mp2.TABLE_B,
		"selected rows %d with sblimit %d; B.2b is rows 1 sblimit 30, B.2a sblimit 27" % [
			corpus[0], corpus[1]])
	# **224 kbit/s stereo is not where the halving bites**, and saying it was
	# would be this harness claiming a bug it cannot demonstrate: 112 and 224 are
	# both at or above B.2b's 96 kbit/s floor, so this corpus decodes correctly
	# either way. The boundary is at 56 and at 96 per channel, so the case that
	# separates the two readings is 128 kbit/s stereo — 64 per channel, which is
	# Table B.2a and 27 subbands, against the 128-as-per-channel misreading's
	# B.2b and 30. That is the control, and it is stated on the combination that
	# actually distinguishes them.
	h.check("at 128 kbit/s stereo the halving is the difference between B.2a and B.2b",
		Mp2.allocation_table(3, 44100, 128, Mp2.MODE_STEREO) == Mp2.TABLE_A
			and Mp2.allocation_table(3, 44100, 128, Mp2.MODE_MONO) == Mp2.TABLE_B,
		"64 per channel is B.2a's 27 subbands; reading 128 as per-channel gives B.2b's 30")


## The allocation rows themselves: the subband limits, and the two containments
## the tables are factored on.
func _check_allocation_rows(h: Harness) -> void:
	var rows: Array = Mp2.ALLOC_ROWS
	h.check("the four Layer II tables are three row shapes",
		rows.size() == 3, "%d row shapes" % rows.size())
	h.check("Table B.2d has 12 subbands and B.2c is its first 8",
		int(rows[0].size()) == 12 and int(Mp2.TABLE_C[1]) == 8
			and int(Mp2.TABLE_D[1]) == 12,
		"row 0 has %d subbands" % int(rows[0].size()))
	h.check("Table B.2b has 30 subbands and B.2a is its first 27",
		int(rows[1].size()) == 30 and int(Mp2.TABLE_A[1]) == 27
			and int(Mp2.TABLE_B[1]) == 30,
		"row 1 has %d subbands" % int(rows[1].size()))
	h.check("13818-3's half-rate table has 30 subbands",
		int(rows[2].size()) == 30, "row 2 has %d subbands" % int(rows[2].size()))
	# Every code of every subband must name a quantisation class that exists, and
	# the row must be exactly as long as its own allocation field can address.
	var bad: Array[String] = []
	for t in rows.size():
		for sb in int(rows[t].size()):
			var entry: Array = rows[t][sb]
			var nbal := int(entry[0])
			var codes: Array = Mp2.ALLOC_CODES[int(entry[1])]
			if codes.size() < (1 << nbal):
				bad.append("table %d subband %d: %d bits addresses %d codes, row has %d" % [
					t, sb, nbal, 1 << nbal, codes.size()])
				continue
			for code in (1 << nbal):
				var cls := int(codes[code])
				if cls < 0 or cls > Mp2.QUANT_CLASS.size():
					bad.append("table %d subband %d code %d -> class %d" % [t, sb, code, cls])
			if int(codes[0]) != 0:
				bad.append("table %d subband %d: code 0 must mean no allocation" % [t, sb])
	h.check("every allocation code of every table names a real quantisation class",
		bad.is_empty(), "; ".join(bad.slice(0, 4)))
	# The seventeen classes, checked for the property that makes grouping worth
	# doing: three samples of a `steps` level quantiser must fit in the codeword.
	var narrow: Array[String] = []
	for i in Mp2.QUANT_CLASS.size():
		var spec: Array = Mp2.QUANT_CLASS[i]
		var steps := int(spec[0])
		var width := int(spec[1])
		if bool(spec[2]):
			if steps * steps * steps > (1 << width):
				narrow.append("%d levels grouped into %d bits" % [steps, width])
		elif steps > (1 << width) - 1 or steps < (1 << (width - 1)):
			narrow.append("%d levels in %d bits" % [steps, width])
	h.check("every quantisation class's codeword is wide enough for what it holds",
		narrow.is_empty(), "; ".join(narrow))


## ISO Table B.1's 63 scalefactors are a geometric series, so they are computed
## rather than transcribed; this is the check that the series is the right one.
func _check_scalefactors(h: Harness) -> void:
	var sf: PackedFloat32Array = Mp2.scalefactors()
	h.check("scalefactor 0 is 2.0 and scalefactor 3 is 1.0",
		is_equal_approx(sf[0], 2.0) and is_equal_approx(sf[3], 1.0),
		"%.6f and %.6f" % [sf[0], sf[3]])
	var worst := 0.0
	for i in 62:
		worst = maxf(worst, absf(sf[i + 1] / sf[i] - pow(2.0, -1.0 / 3.0)))
	h.check("every step down the table is a factor of 2^(-1/3)",
		worst < 1.0e-5, "worst deviation %.10f" % worst)
	h.check("the illegal scalefactor 63 is silent rather than enormous",
		sf[63] == 0.0, "%.6f" % sf[63])


## The frame length arithmetic, over every legal (layer, rate, bit rate) triple.
##
## This is what the walk navigates by and it is the only thing tying one frame to
## the next, so it is checked against the standard's formulas written out a
## second time: Layer I is `(12 * rate / frequency + padding) * 4` bytes for 384
## samples, Layer II is `144 * rate / frequency + padding` for 1,152.
func _check_frame_lengths(h: Harness) -> void:
	var probe := Mp2.new()
	var wrong: Array[String] = []
	var checked := 0
	for layer in [1, 2]:
		var ladder: Array = Mp2.BITRATE_V1_L1 if layer == 1 else Mp2.BITRATE_V1_L2
		for rate_index in 3:
			var rate: int = int(Mp2.RATE_V1[rate_index])
			for index in range(1, 15):
				for padding in 2:
					var kbps := int(ladder[index])
					var es := PackedByteArray()
					es.resize(8)
					es[0] = 0xFF
					es[1] = 0xF8 | ((4 - layer) << 1) | 1
					es[2] = (index << 4) | (rate_index << 2) | (padding << 1)
					es[3] = 0x00
					probe._reset()
					probe._es = es
					var head: Dictionary = probe._read_header(0)
					checked += 1
					if head.is_empty():
						wrong.append("layer %d, %d Hz, %d kbit/s: no header read" % [
							layer, rate, kbps])
						continue
					var want := 0
					if layer == 1:
						want = (12 * kbps * 1000 / rate + padding) * 4
					else:
						want = 144 * kbps * 1000 / rate + padding
					if int(head["length"]) != want or int(head["bitrate"]) != kbps \
							or int(head["rate"]) != rate:
						wrong.append("layer %d, %d Hz, %d kbit/s, pad %d: %d bytes, wanted %d" % [
							layer, rate, kbps, padding, int(head["length"]), want])
	h.check("the frame length is read correctly for all %d header combinations" % checked,
		wrong.is_empty(), "; ".join(wrong.slice(0, 4)))
	# Free format and the reserved index state no length, so they must be refused
	# rather than guessed at: a guess here walks the reader off the frame grid.
	var es2 := PackedByteArray()
	es2.resize(8)
	es2[0] = 0xFF
	es2[1] = 0xFD
	es2[2] = 0x00
	probe._reset()
	probe._es = es2
	var free: Dictionary = probe._read_header(0)
	es2[2] = 0xF0
	probe._es = es2
	var reserved: Dictionary = probe._read_header(0)
	h.check("free format and the reserved bit rate index are refused, not guessed",
		free.is_empty() and reserved.is_empty(),
		"free %s, reserved %s" % [str(free.size()), str(reserved.size())])


## The filterbank, driven one subband at a time.
##
## A constant in subband `k` and silence everywhere else must come out of the
## synthesis inside subband `k`'s own frequency band and nowhere else — that is
## what a cosine modulated filterbank *is*, and driving it this way exercises the
## whole chain: the folded transform, the 1,024 sample ring's indexing, the
## `Vector4` gather that replaces ISO's `U` buffer, and every one of the 512
## window coefficients.
##
## **A constant subband signal is not one tone, it is two.** The subband signal is
## decimated by 32, so its DC maps back to both edges of the band the subband
## covers — `k / 64` and `(k + 1) / 64` of the sampling rate — with half the
## energy at each. Measuring against the band *centre* instead finds half the
## energy missing and reads as a broken filterbank, which is what the first
## version of this check reported before the two components were understood.
##
## So the measurement is a least squares residual: fit the two edge sinusoids,
## subtract them, and see what is left. With the right window that residual is a
## fraction of a percent. A window with one coefficient wrong still produces
## tones at those two frequencies; what it stops doing is producing *only* them,
## and the leak shows up here as residual.
##
## The gain falls out of the same drive, and it is exact rather than approximate:
## the analysis-synthesis pair is unity gain, so a subband held at `A` comes out
## with a root mean square of `A`. That is where the 32,768 in `_synthesise`
## comes from — full scale in, full scale out.
func _check_filterbank(h: Harness) -> void:
	var granules := 64
	var level := 0.25
	var skip := 512
	var worst_leak := 0.0
	var worst_at := 0
	var gains: Array[float] = []
	for k in 32:
		var pcm := _drive_subband(k, granules, level)
		var total := 0.0
		for i in range(skip, pcm.size()):
			total += pcm[i] * pcm[i]
		var residual := _project_out(pcm, skip, float(k) / 64.0)
		residual = _project_out(residual, 0, float(k + 1) / 64.0)
		var left := 0.0
		for v in residual:
			left += v * v
		var leak := left / maxf(total, 1.0e-12)
		if leak > worst_leak:
			worst_leak = leak
			worst_at = k
		gains.append(sqrt(total / float(pcm.size() - skip)) / level)
	# **The threshold is set from what a wrong window actually measures**, not
	# from a round number. With ISO Table B.3 the leak is 0.0000005% — five parts
	# in a billion, which is the float arithmetic and the 16-bit rounding of the
	# output and nothing else. Zeroing one coefficient takes it to 2%, and getting
	# one coefficient 10% wrong takes it to 0.02%; a 1% threshold would have
	# passed both of the latter, which is what it did before this line was
	# measured rather than guessed. 0.001% sits four orders of magnitude above
	# the true figure and two below the smallest corruption tried.
	h.check("a subband driven alone comes out inside that subband's own band",
		worst_leak < 1.0e-5,
		"worst subband %d leaks %.7f%% of its energy outside its two band edges" % [
			worst_at, 100.0 * worst_leak])
	h.check("the filterbank is unity gain, so 16-bit full scale is 32,768",
		absf(gains.min() - 1.0) < 0.02 and absf(gains.max() - 1.0) < 0.02,
		"subband output/input amplitude spans %.4f..%.4f over all 32" % [
			gains.min(), gains.max()])


## One subband held at `level` for `granules` granules, as mono float PCM.
func _drive_subband(k: int, granules: int, level: float) -> PackedFloat32Array:
	var mp2 := Mp2.new()
	Mp2.build_tables()
	mp2.channels = 1
	mp2._voffs = 0
	var rings: Array[PackedVector4Array] = []
	var ring := PackedVector4Array()
	ring.resize(256)
	rings.append(ring)
	rings.append(ring)
	mp2._v = rings
	var sample := PackedFloat32Array()
	sample.resize(64)
	sample[k] = level
	var out := PackedByteArray()
	out.resize(granules * 32 * 2)
	var write := 0
	for _g in granules:
		write = mp2._synthesise(sample, 0, out, write)
	var pcm := PackedFloat32Array()
	pcm.resize(granules * 32)
	for i in pcm.size():
		pcm[i] = float(out.decode_s16(i * 2)) / 32768.0
	return pcm


## Least squares removal of one frequency from a signal, returning the residual.
##
## The cosine and sine at `frequency` are projected out using their **own** norms
## rather than an assumed `n / 2`, which is what makes this correct at DC and at
## Nyquist as well — and subbands 0 and 31 have one band edge at each of those, so
## an implementation that assumed the general case would fail exactly two of the
## thirty-two and look like a filterbank defect at the extremes.
func _project_out(pcm: PackedFloat32Array, from: int, frequency: float) -> PackedFloat32Array:
	var n := pcm.size() - from
	var w := TAU * frequency
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = pcm[from + i]
	for phase in 2:
		var dot := 0.0
		var norm := 0.0
		for i in n:
			var basis := cos(w * float(i)) if phase == 0 else sin(w * float(i))
			dot += out[i] * basis
			norm += basis * basis
		if norm < 1.0e-9:
			continue
		var coefficient := dot / norm
		for i in n:
			var basis2 := cos(w * float(i)) if phase == 0 else sin(w * float(i))
			out[i] -= coefficient * basis2
	return out


## The filterbank's inner loop, timed on its own, for the header's numbers.
##
## Two channels of nothing but synthesis, with no bit reading and no
## requantisation, so the number is the cost of the part that dominates: 16
## multiply-accumulates per output sample, gathered four at a time.
func _bench() -> void:
	var mp2 := Mp2.new()
	Mp2.build_tables()
	mp2.channels = 2
	var rings: Array[PackedVector4Array] = []
	for _c in 2:
		var ring := PackedVector4Array()
		ring.resize(256)
		rings.append(ring)
	mp2._v = rings
	var sample := PackedFloat32Array()
	sample.resize(192)
	for i in 64:
		sample[i] = sin(float(i))
	var out := PackedByteArray()
	var granules := 4096
	out.resize(granules * 32 * 2 * 2)
	var began := Time.get_ticks_usec()
	var write := 0
	for _g in granules:
		write = mp2._synthesise(sample, 0, out, write)
	var us := Time.get_ticks_usec() - began
	var seconds := float(granules) * 32.0 / 44100.0
	print("  bench : %d stereo granules (%.2f s of 44.1 kHz audio) in %.3f s"
		% [granules, seconds, us / 1.0e6]
		+ " -> %.1fx real time, %.1f us per granule" % [
			seconds / (us / 1.0e6), float(us) / float(granules)])


# ============================================================== the data half


func _corpus_checks(h: Harness, args: Dictionary) -> void:
	var wanted := Args.text(args, "file", "")
	var files: Array[String] = []
	if wanted != "":
		files.append(wanted)
	else:
		var paths := Paths.new()
		if paths.load_config():
			files = _find(str(paths.root))
	var case := "MPEG audio on the disc"
	h.begin(case)
	if files.is_empty():
		h.check(
			"this corpus holds no MPEG audio, so nothing was decoded here",
			true,
			"the format checks above are corpus-independent; "
			+ "run --root res://test-games/itamar-magichat for the only corpus with data")
		h.complete(case)
		return
	var seconds := float(Args.number(args, "seconds", 8))
	if Args.flag(args, "all"):
		seconds = 1.0e9
	var wav_dir := Args.text(args, "wav", "")
	var totals := {"frames": 0, "resyncs": 0, "rejected": 0, "files": 0}
	for file_path in files:
		_one(h, file_path, seconds, wav_dir, Args.flag(args, "oracle"), totals)
	print("")
	print("total : %d frames over %d files, %d resynchronisations, %d rejected headers" % [
		totals["frames"], totals["files"], totals["resyncs"], totals["rejected"]])
	h.check("no frame in the corpus needed the reader to hunt for the next sync word",
		int(totals["resyncs"]) == 0 and int(totals["rejected"]) == 0,
		"%d resyncs and %d rejected headers over %d frames" % [
			totals["resyncs"], totals["rejected"], totals["frames"]])
	h.complete(case)


func _one(h: Harness, file_path: String, seconds: float, wav_dir: String,
		oracle: bool, totals: Dictionary) -> void:
	var name := file_path.get_file()
	print("")
	print("%s" % file_path)
	var ps := Ps.new()
	if not ps.open(file_path):
		h.check("%s: the program stream demuxes" % name, false, str(ps.error))
		return
	var es := ps.audio_elementary()
	var audio_packets := ps.audio_packets
	var audio_id := ps.audio_id
	ps.close()
	if es.is_empty():
		h.check("%s: carries no audio elementary stream" % name, true,
			"a silent clip is a legitimate thing for a file to be; nothing asserted")
		return
	var mp2 := Mp2.new()
	if not mp2.scan(es):
		h.check("%s: the audio elementary stream scans" % name, false, str(mp2.error))
		return
	totals["files"] = int(totals["files"]) + 1
	totals["frames"] = int(totals["frames"]) + mp2.frame_count
	totals["resyncs"] = int(totals["resyncs"]) + mp2.resyncs
	totals["rejected"] = int(totals["rejected"]) + mp2.rejected_headers
	print("  stream: %d bytes in %d packets (id 0x%02X)" % [
		es.size(), audio_packets, audio_id])
	print("  header: MPEG-%s Layer %s, %d Hz, %d bit/s, mode %d, %d channel(s), %s" % [
		["2.5", "?", "2", "1"][mp2.version], ["?", "I", "II", "III"][mp2.layer],
		mp2.sample_rate, mp2.bit_rate, mp2.mode, mp2.channels,
		"CRC" if mp2.protected else "no CRC"])
	var table: Array = Mp2.allocation_table(
		mp2.version, mp2.sample_rate, mp2.bit_rate / 1000, mp2.mode)
	var per_channel: int = (mp2.bit_rate / 1000) / mp2.channels
	print("  alloc : %d kbit/s per channel at %d Hz -> ISO Table B.2%s, sblimit %d" % [
		per_channel, mp2.sample_rate,
		["c" if int(table[1]) == 8 else "d", "a" if int(table[1]) == 27 else "b",
			" (13818-3)"][int(table[0])], int(table[1])])
	print("  frames: %d complete, %d resync, %d rejected, %d bytes of a truncated last frame" % [
		mp2.frame_count, mp2.resyncs, mp2.rejected_headers, mp2.truncated_tail])
	print("  length: %.2f s of audio (%d sample frames)" % [
		mp2.duration_ms() / 1000.0, mp2.sample_frames])

	h.check("%s: every frame's declared length lands on the next sync word" % name,
		mp2.resyncs == 0 and mp2.rejected_headers == 0,
		"%d resyncs, %d rejected, over %d frames" % [
			mp2.resyncs, mp2.rejected_headers, mp2.frame_count])
	# A frame the multiplex cut short is normal; a *large* remainder is a walk
	# that lost its place near the end and stopped early.
	h.check("%s: what is left over is one partial frame, not a lost tail" % name,
		mp2.truncated_tail >= 0 and mp2.truncated_tail < 1500,
		"%d bytes left over, frame length about %d" % [
			mp2.truncated_tail, es.size() / maxi(mp2.frame_count, 1)])

	var wanted_frames := mp2.frame_count
	if seconds < 1.0e8:
		wanted_frames = mini(wanted_frames,
			maxi(int(ceil(seconds * mp2.sample_rate / float(mp2.samples_per_frame))), 1))
	var pcm := mp2.decode(0, wanted_frames)
	var decoded_seconds := float(wanted_frames * mp2.samples_per_frame) / float(mp2.sample_rate)
	var cost := mp2.decode_cost_us() / 1.0e6
	print("  decode: %d frames -> %.2f s of PCM (%d KiB) in %.3f s -> %.2fx real time" % [
		wanted_frames, decoded_seconds, pcm.size() >> 10, cost,
		decoded_seconds / maxf(cost, 1.0e-9)])
	var stats := _pcm_stats(pcm)
	print("  pcm   : peak %d, rms %.1f, %d samples at full scale, %d silent of %d" % [
		int(stats["peak"]), float(stats["rms"]), int(stats["clipped"]),
		int(stats["silent"]), int(stats["count"])])

	h.check("%s: the decode produced the sample count the headers promised" % name,
		pcm.size() == wanted_frames * mp2.samples_per_frame * mp2.channels * 2,
		"%d bytes for %d frames of %d samples x %d channels" % [
			pcm.size(), wanted_frames, mp2.samples_per_frame, mp2.channels])
	# Not "it produced bytes". A decoder that got the tables wrong produces a
	# full scale square wave or silence, and both are excluded here: real audio
	# uses its range without living at the rails.
	h.check("%s: the samples are audio rather than silence or a rail" % name,
		float(stats["rms"]) > 200.0 and int(stats["peak"]) > 4000
			and float(stats["clipped"]) < 0.001 * float(stats["count"])
			and float(stats["silent"]) < 0.9 * float(stats["count"]),
		"peak %d, rms %.1f, %d clipped, %d silent" % [
			int(stats["peak"]), float(stats["rms"]), int(stats["clipped"]),
			int(stats["silent"])])

	if wav_dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(wav_dir))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = mp2.sample_rate
		wav.stereo = mp2.channels >= 2
		wav.data = pcm
		var out_path := "%s/%s.wav" % [wav_dir, name.get_basename()]
		wav.save_to_wav(out_path)
		print("  wrote %s" % out_path)

	_through_the_reader(h, file_path, name, mp2)

	if oracle:
		_oracle(h, file_path, name, pcm, mp2)


## The same file through `director_mpeg1.gd`, which is the reader
## `preview/video.gd` actually drives.
##
## Everything above this point talks to the codec directly. This talks to the
## engine's reader, and it is the only thing that covers the three seams between
## them: that `open` starts the background decode at all, that `audio_stream`
## answers **null while it is running** rather than blocking or handing back a
## half-filled buffer, and that what it finally answers is an `AudioStreamWAV` as
## long as the frame walk said the track is.
##
## The null-while-running assertion is the one worth having. It is what
## `preview/video.gd:_join_audio` is written against, and a reader that blocked
## instead would pass every other check in this file while freezing the movie for
## fourteen seconds inside a Lingo statement — which is exactly the failure
## `docs/DIGITAL_VIDEO.md` §3 exists to prevent, and it would be invisible to a
## harness that only waited for the answer.
func _through_the_reader(h: Harness, file_path: String, name: String, mp2) -> void:
	var reader := Mpeg1.new()
	if not reader.open(file_path):
		h.check("%s: the engine's reader opens it" % name, false, str(reader.error))
		return
	# Immediately after `open`, before anything has been waited for.
	#
	# **The time the call takes is the assertion**, not what it returns. Asking
	# whether it answered null while `audio_ready()` was false is what this did
	# first, and it was vacuous: reading `audio_ready()` *after* the call meant a
	# blocking implementation had already finished by the time it was asked, so
	# both readings agreed and a deliberately blocking control passed. That is the
	# shape `porting-fidelity-verification` names — a check whose two readings
	# cannot disagree — and the fix is to measure the thing that actually differs.
	var before_ready: bool = reader.audio_ready()
	var began_early := Time.get_ticks_usec()
	var early = reader.audio_stream()
	var early_us := Time.get_ticks_usec() - began_early
	var early_ready: bool = before_ready
	h.check("%s: the reader reports the track's own header without decoding it" % name,
		reader.audio_rate == int(mp2.sample_rate)
			and reader.audio_channels == int(mp2.channels)
			and reader.audio_layer == int(mp2.layer)
			and reader.audio_frames == int(mp2.frame_count),
		"%d Hz, %d channels, layer %d, %d frames" % [
			reader.audio_rate, reader.audio_channels, reader.audio_layer,
			reader.audio_frames])
	h.check("%s: audio_stream returns at once rather than waiting for the decode" % name,
		early_us < 100000 and (early_ready or early == null),
		"the first call took %.3f s and %s (audio_ready() was %s beforehand); "
			% [early_us / 1.0e6, "answered a stream" if early != null else "answered null",
				str(early_ready)]
			+ "anything above a tick would freeze the movie inside the Lingo "
			+ "statement that wrote the movieRate")
	var waited := Time.get_ticks_usec()
	while not reader.audio_ready():
		OS.delay_msec(20)
		if Time.get_ticks_usec() - waited > 600 * 1000 * 1000:
			break
	var lead := (Time.get_ticks_usec() - waited) / 1.0e6
	var stream: AudioStreamWAV = reader.audio_stream()
	print("  reader: the background decode took %.3f s%s; %d KiB of PCM" % [
		reader.audio_decode_us() / 1.0e6,
		"" if early_ready else " (%.3f s of it after open returned)" % lead,
		reader.audio_pcm_bytes() >> 10])
	if stream == null:
		h.check("%s: the reader hands back a sound track" % name, false,
			"audio_ready() true but audio_stream() null; %s" % str(reader.audio_error))
		reader.close()
		return
	var seconds := stream.get_length()
	print("  reader: AudioStreamWAV of %.2f s at %d Hz, %s" % [
		seconds, stream.mix_rate, "stereo" if stream.stereo else "mono"])
	h.check("%s: the sound track is as long as the frame walk said" % name,
		absf(seconds - mp2.duration_ms() / 1000.0) < 0.05,
		"%.3f s of PCM against %.3f s of frames" % [
			seconds, mp2.duration_ms() / 1000.0])
	# `preview/video.gd` starts it with `player.play(seconds)`, so the picture and
	# the sound are put in step by the playhead rather than by the multiplex —
	# which only works because the whole track is one seekable stream.
	h.check("%s: it is one seekable stream, which is what late joining needs" % name,
		stream.format == AudioStreamWAV.FORMAT_16_BITS
			and stream.mix_rate == int(mp2.sample_rate)
			and stream.stereo == (int(mp2.channels) >= 2),
		"format %d, %d Hz, stereo %s" % [stream.format, stream.mix_rate, str(stream.stereo)])
	reader.close()


func _pcm_stats(pcm: PackedByteArray) -> Dictionary:
	var count := pcm.size() / 2
	var peak := 0
	var sum_sq := 0.0
	var clipped := 0
	var silent := 0
	for i in count:
		var v := pcm.decode_s16(i * 2)
		var a := absi(v)
		if a > peak:
			peak = a
		sum_sq += float(v) * float(v)
		if a >= 32767:
			clipped += 1
		if a == 0:
			silent += 1
	return {
		"peak": peak, "rms": sqrt(sum_sq / maxf(count, 1)), "clipped": clipped,
		"silent": silent, "count": count,
	}


# ================================================================== the oracle


## Compare against the Vorbis track of an Ogg sidecar.
##
## The sidecar is a **transcode of the same source**, so its sound track is a
## genuinely independent decode of these bytes: a different container, a
## different codec, and an implementation that is not this port. Its Theora track
## is already the oracle for the pictures (`tools/mpeg1_decode.gd --oracle`); this
## is the same argument applied to the half that was missing.
##
## Three things make the comparison honest. The Vorbis stream is lifted out of
## the `.ogv` by page serial number and decoded by Godot, so nothing is written
## and no transcoder runs. The alignment is **searched for** rather than assumed,
## because a filterbank has a group delay and a transcode may trim — the shift it
## lands on is reported, and a shift near zero is itself evidence. And the
## residual is stated as a fraction of the oracle's own level, because "mean
## absolute difference 0.008" means nothing without knowing that the signal it is
## a difference from averages 0.118.
##
## The threshold is loose on purpose: Vorbis is lossy, the transcode requantised
## everything, and the two decoders' phase differs by a fraction of a sample. Two
## decoders of the same original land within a tenth of the signal's own level;
## a decoder with a table wrong lands at or above it.
func _oracle(h: Harness, file_path: String, name: String, pcm: PackedByteArray,
		mp2) -> void:
	var sidecar := Sidecar.fresh_for(file_path)
	if sidecar == "":
		h.check("%s: no sidecar to compare against (%s)" % [name, Sidecar.status_of(file_path)],
			true, "run tools/video_sidecar.gd to make one; this is not a failure")
		return
	var file := FileAccess.open(sidecar, FileAccess.READ)
	if file == null:
		h.check("%s: the sidecar opens" % name, false, sidecar)
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var serial := _vorbis_serial(bytes)
	if serial < 0:
		h.check("%s: the sidecar carries a Vorbis track" % name, true,
			"a video-only sidecar is not a failure; nothing compared")
		return
	var stream := AudioStreamOggVorbis.load_from_buffer(_only_stream(bytes, serial))
	if stream == null:
		h.check("%s: the sidecar's Vorbis track loads" % name, false,
			"page serial %d" % serial)
		return
	var stride: int = int(mp2.channels)
	var ours := PackedFloat32Array()
	var n: int = pcm.size() / (2 * stride)
	ours.resize(n)
	for i in n:
		ours[i] = float(pcm.decode_s16(i * 2 * stride)) / 32768.0
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	var theirs := PackedFloat32Array()
	while theirs.size() < n + 4000:
		var chunk: PackedVector2Array = playback.mix_audio(1.0, 4096)
		if chunk.is_empty():
			break
		for v in chunk:
			theirs.append(v.x)
	if theirs.size() < 20000 or n < 20000:
		h.check("%s: the sidecar produced enough audio to compare" % name, true,
			"%d oracle samples against %d of ours; not asserted" % [theirs.size(), n])
		return
	var limit: int = mini(n, theirs.size() - 2100) - 100
	var best := 0
	var best_score := -1.0e30
	for shift in range(-2000, 2001):
		var score := 0.0
		var i := 2100
		while i < limit:
			score += ours[i] * theirs[i + shift]
			i += 11
		if score > best_score:
			best_score = score
			best = shift
	var difference := 0.0
	var level := 0.0
	var ours_level := 0.0
	var product := 0.0
	var ours_sq := 0.0
	var theirs_sq := 0.0
	var counted := 0
	var k := 2100
	while k < limit:
		var a := ours[k]
		var b := theirs[k + best]
		difference += absf(a - b)
		level += absf(b)
		ours_level += absf(a)
		product += a * b
		ours_sq += a * a
		theirs_sq += b * b
		counted += 1
		k += 1
	var mean_difference := difference / float(counted)
	var mean_level := level / float(counted)
	var correlation := product / maxf(sqrt(ours_sq * theirs_sq), 1.0e-12)
	print("  oracle: aligned at %+d samples (%.2f ms); mean |difference| %.5f "
		% [best, float(best) * 1000.0 / float(int(mp2.sample_rate)), mean_difference]
		+ "against the oracle's own %.5f -> %.1f%%" % [
			mean_level, 100.0 * mean_difference / maxf(mean_level, 1.0e-9)])
	print("  oracle: correlation %.5f over %d samples; our mean level %.5f" % [
		correlation, counted, ours_level / float(counted)])
	h.check("%s: aligns with the sidecar's Vorbis track within a millisecond" % name,
		absi(best) < 64,
		"best shift %d samples — a large one means the two are not the same audio" % best)
	h.check("%s: agrees with the sidecar's Vorbis track to within a tenth of its level" % name,
		mean_difference < 0.1 * mean_level and correlation > 0.9,
		"mean |difference| %.5f of %.5f (%.1f%%), correlation %.5f" % [
			mean_difference, mean_level,
			100.0 * mean_difference / maxf(mean_level, 1.0e-9), correlation])


## The page serial number of the `.ogv`'s Vorbis logical stream, or -1.
func _vorbis_serial(bytes: PackedByteArray) -> int:
	var at := 0
	var n := bytes.size()
	while at + 27 <= n:
		if bytes.decode_u32(at) != 0x5367674F:  # "OggS"
			at += 1
			continue
		var segments := bytes[at + 26]
		var header := 27 + segments
		if at + header > n:
			break
		var payload := 0
		for i in segments:
			payload += bytes[at + 27 + i]
		var body := at + header
		if (bytes[at + 5] & 0x02) != 0 and payload > 7:
			var codec := ""
			for i in range(1, 7):
				codec += char(bytes[body + i])
			if codec == "vorbis":
				return bytes.decode_u32(at + 14)
		at = body + payload
	return -1


## Every page of one logical stream, concatenated.
##
## No repair and no renumbering: Ogg's page sequence number and its CRC are both
## **per logical stream**, so dropping the other streams' pages leaves this one's
## numbering contiguous and every checksum still correct. What comes out is a
## valid single-stream Ogg file, which is what a Vorbis decoder wants.
func _only_stream(bytes: PackedByteArray, serial: int) -> PackedByteArray:
	var out := PackedByteArray()
	var at := 0
	var n := bytes.size()
	while at + 27 <= n:
		if bytes.decode_u32(at) != 0x5367674F:
			at += 1
			continue
		var segments := bytes[at + 26]
		var header := 27 + segments
		if at + header > n:
			break
		var payload := 0
		for i in segments:
			payload += bytes[at + 27 + i]
		var end := at + header + payload
		if end > n:
			break
		if bytes.decode_u32(at + 14) == serial:
			out.append_array(bytes.slice(at, end))
		at = end
	return out


func _find(root_path: String) -> Array[String]:
	var out: Array[String] = []
	_scan(root_path, out)
	out.sort()
	return out


func _scan(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_scan(full, out)
		elif EXTENSIONS.has(name.get_extension().to_lower()):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
