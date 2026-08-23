extends SceneTree
## Assert the GDScript MPEG-1 decoder, and say what it costs.
##
##   godot --headless --audio-driver Dummy --path . --script tools/mpeg1_decode.gd -- \
##       --root res://test-games/itamar-magichat
##
##   --root R       the corpus (`DirectorPaths` honours it; default the config's)
##   --file P       one file instead of a sweep, `res://` or absolute
##   --frames N     decode at most N display frames per clip (default 12)
##   --from N       start at display frame N rather than at 0
##   --all-frames   decode every frame of every clip; minutes, not seconds
##   --png DIR      write the frames it decoded as PNG
##   --oracle       compare against an Ogg Theora sidecar where one exists
##
## ## Two halves, and only one of them needs a corpus
##
## `gate.sh` runs this **bare**, on `GATE_ROOT`, where there is no MPEG-1 file at
## all — the four `test-games/itamar-magichat` entries were removed from `ALL`
## because that corpus is not in the repository, and the same argument would
## remove this one. So the assertions are split:
##
##   * **The format half is corpus-independent and always runs.** Every
##     variable-length table is checked for being a prefix code, for having no
##     duplicate entry, and for round-tripping through the decoder's own reader;
##     the integer IDCT is checked against a direct floating-point evaluation of
##     the transform's definition; the dequantiser is checked against the two
##     properties §2.4.4.2 states about its output; and the colour matrix is
##     checked at the three points where BT.601 has an exact answer. None of that
##     needs a file, and all of it is where a decoder is wrong in ways that look
##     like "the picture is a bit soft" rather than like a crash.
##   * **The data half runs when there is data.** It says out loud when it finds
##     none, which is `avi_decode`'s pattern and is why that entry stayed green
##     when its fixture entries were deleted.
##
## ## The check that is worth more than all the others
##
## `desynced_slices`. A slice is a run of variable-length codes with no length
## field anywhere in it, so the only thing that says the decode was right is that
## the reader ran out of macroblocks exactly where the encoder ran out of bits —
## at the byte before the next start code. One wrong entry in one table
## desynchronises the reader and it stops landing there. `heb/mainmenu/intro.mpg`
## has 39,402 slices, and every one of them is an independent test of the whole
## VLC layer, the escape coding, the coded block pattern and the motion vector
## reconstruction at once. Nothing else in this harness is that strong.
##
## Title-agnostic: it names no game and no file.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const Mpeg1 := preload("res://director/director_mpeg1.gd")
const Mpeg1Video := preload("res://director/director_mpeg1_video.gd")
const Ps := preload("res://director/director_mpeg1_ps.gd")
const Sidecar := preload("res://director/director_sidecar.gd")

const EXTENSIONS := ["mpg", "mpeg", "m1v", "mpv"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	var args := Args.parse()
	_format_checks(h)
	await _corpus_checks(h, args)
	quit(h.finish("MPEG-1 decodes in GDScript, and what that costs is measured"))


# ============================================================ the format half


func _format_checks(h: Harness) -> void:
	var case := "the MPEG-1 format tables and transforms"
	h.begin(case)
	Mpeg1Video.build_tables()
	_check_vlc_tables(h)
	_check_idct(h)
	_check_dequant(h)
	_check_colour(h)
	h.complete(case)


## Every table is a prefix code, has no duplicates, and decodes back to itself
## through the decoder's own bit reader.
##
## The round trip is the part that matters: a table can be a perfect prefix code
## and still be wired into a lookup array at the wrong shift, which is a class of
## bug that produces plausible-looking rubbish. Each code is padded out with the
## bits that would follow it in a real stream — deliberately with 1s, because 0s
## are what a start code looks like and would hide an entry whose length is
## recorded one bit too long.
func _check_vlc_tables(h: Harness) -> void:
	# `[rows, peek width, the entry count Annex B states, the decoder's own table]`.
	var tables := {
		"macroblock_address_increment (B.1)": [_mba_rows(), 11, 35, "mba"],
		"macroblock_type, I (B.2)": [[["1", 0x10], ["01", 0x11]], 2, 2, "type_i"],
		"macroblock_type, P (B.3)": [_type_p_rows(), 6, 7, "type_p"],
		"macroblock_type, B (B.4)": [_type_b_rows(), 6, 11, "type_b"],
		"coded_block_pattern (B.9)": [_cbp_rows(), 9, 63, "cbp"],
		"motion_code (B.10)": [_motion_rows(), 11, 33, "motion"],
		"dct_dc_size_luminance (B.12)": [_dc_luma_rows(), 7, 9, "dc_luma"],
		"dct_dc_size_chrominance (B.13)": [_dc_chroma_rows(), 8, 9, "dc_chroma"],
	}
	for name in tables.keys():
		var spec: Array = tables[name]
		_check_one_table(h, str(name), spec[0], int(spec[1]), int(spec[2]), str(spec[3]))

	var dct_rows: Array = []
	for row_value in Mpeg1Video.dct_rows_for_audit():
		var row: Array = row_value
		var payload := int(row[1])
		if payload < 0x1000:
			payload = (payload << 8) | int(row[2])
		dct_rows.append([str(row[0]), payload])
	_check_one_table(h, "DCT coefficients (B.14)", dct_rows, 16, 113, "dct")

	# The decoder's own reader, driven over a synthesised bitstream per code. This
	# is the round trip that catches a lookup built at the wrong shift, and it now
	# exercises the sign bit and the escape as well, because
	# `_read_coefficient` folds all three into one call.
	#
	# One stream per code rather than one stream of all of them, so that a code
	# read at the wrong length fails on its own row instead of desynchronising
	# every row after it and reporting 112 failures for one mistake.
	var wrong: Array[String] = []
	for row_value in Mpeg1Video.dct_rows_for_audit():
		var row: Array = row_value
		var text := str(row[0])
		var run := int(row[1])
		var level := int(row[2])
		if run == 0x3FFFFF:
			var eob := _decode_coefficient(text)
			if eob != -1:
				wrong.append("end-of-block read as %d" % eob)
			continue
		if run == 0x3FFFFE:
			continue  # covered by the three escape forms below
		# `1` for the sign bit means negative, so the expected level is negated —
		# which also checks that the sign is read *after* the code and not folded
		# into the table.
		var got := _decode_coefficient(text + "1")
		if got < 0:
			wrong.append("%s read as end-of-block" % text)
			continue
		var got_run := got >> 12
		var got_level := (got & 0xFFF) - 2048
		if got_run != run or got_level != -level:
			wrong.append("%s wanted run %d level %d, read run %d level %d" % [
				text, run, -level, got_run, got_level])
	h.check("every B.14 code round-trips through the decoder's own reader",
		wrong.is_empty(), "; ".join(wrong.slice(0, 4)))

	# Table B.16's three level forms, which is where a decoder is wrong only on
	# the densest blocks of the highest-quality pictures and therefore only on
	# some files. The escape is `000001`, then six bits of run, then the level.
	var escapes := [
		["000001" + "000101" + "01111111", 5, 127, "an ordinary positive level"],
		["000001" + "000010" + "11111111", 2, -1, "an ordinary negative level"],
		["000001" + "000011" + "00000000" + "11101100", 3, 236, "the 0x00 escape to 128..255"],
		["000001" + "000001" + "10000000" + "01000101", 1, -187, "the 0x80 escape to -255..-128"],
	]
	var escape_wrong: Array[String] = []
	for probe_value in escapes:
		var probe: Array = probe_value
		var got := _decode_coefficient(str(probe[0]))
		var got_run := got >> 12
		var got_level := (got & 0xFFF) - 2048
		if got < 0 or got_run != int(probe[1]) or got_level != int(probe[2]):
			escape_wrong.append("%s: wanted run %d level %d, read run %d level %d" % [
				str(probe[3]), int(probe[1]), int(probe[2]), got_run, got_level])
	h.check("the escape's three level forms (B.16) decode",
		escape_wrong.is_empty(), "; ".join(escape_wrong))


func _check_one_table(h: Harness, name: String, rows: Array, bits: int,
		expected: int, lut_name: String) -> void:
	var seen: Dictionary = {}
	var duplicates: Array[String] = []
	var too_long: Array[String] = []
	var kraft := 0.0
	for row_value in rows:
		var row: Array = row_value
		var text := str(row[0])
		if text.length() > bits:
			too_long.append("%s is %d bits, table peeks %d" % [text, text.length(), bits])
		if seen.has(text):
			duplicates.append(text)
		seen[text] = true
		kraft += pow(2.0, -float(text.length()))
	var prefixes: Array[String] = []
	var codes: Array = seen.keys()
	codes.sort()
	for i in codes.size():
		var a := str(codes[i])
		for j in range(i + 1, codes.size()):
			var b := str(codes[j])
			if b.begins_with(a):
				prefixes.append("%s is a prefix of %s" % [a, b])
	h.check("%s: no code is a prefix of another" % name,
		prefixes.is_empty(), "; ".join(prefixes.slice(0, 3)))
	h.check("%s: no duplicate code" % name,
		duplicates.is_empty(), "; ".join(duplicates.slice(0, 3)))
	h.check("%s: no code longer than the %d bits the table peeks" % [name, bits],
		too_long.is_empty(), "; ".join(too_long.slice(0, 3)))
	# Kraft's inequality: a decodable prefix code sums to at most 1. It is
	# **deliberately not asserted equal to 1**, and that is a measurement rather
	# than a softened check: the first version of this line demanded completeness
	# and seven of the eight tables failed it, because Annex B leaves codes unused
	# — B.1 sums to 0.98926, B.9 to 0.99609, B.14 to 0.99976. What is asserted
	# instead is the entry count each table has in the standard, which is the
	# thing a transcription actually gets wrong.
	h.check("%s: the code is decodable (Kraft sum at most 1)" % name,
		kraft <= 1.0 + 1e-9, "Kraft sum %.9f over %d codes" % [kraft, rows.size()])
	h.check("%s: has the %d entries Annex B states" % [name, expected],
		rows.size() == expected, "%d rows" % rows.size())
	# And the entries reach the decoder's own lookup at the right shift. This is
	# a second transcription of the table checked against the array the decoder
	# will really read, which is the one thing a prefix check cannot see.
	var lut := Mpeg1Video.lut_for_audit(lut_name)
	var mis: Array[String] = []
	if lut.size() != (1 << bits):
		mis.append("the decoder's table is %d entries, not %d" % [lut.size(), 1 << bits])
	else:
		for row_value in rows:
			var row: Array = row_value
			var text := str(row[0])
			var value := int(row[1])
			var code := 0
			for i in text.length():
				code = (code << 1) | (1 if text[i] == "1" else 0)
			var at := code << (bits - text.length())
			var entry := lut[at]
			if (entry & 0xFF) != text.length() or (entry >> 8) != value:
				mis.append("%s -> length %d value %d, wanted %d and %d" % [
					text, entry & 0xFF, entry >> 8, text.length(), value])
	h.check("%s: every entry is in the decoder's lookup at the right shift" % name,
		mis.is_empty(), "; ".join(mis.slice(0, 3)))


## The integer IDCT against a direct evaluation of the transform's definition.
##
## The reference here is the double sum with the cosines written out in floating
## point — 11172-2 Annex A's own formula — and **not** another integer
## implementation, because two integer implementations that share a mistaken
## constant agree with each other perfectly. The tolerance is IEEE 1180's shape:
## every output within 1 of the real transform, which the fixed-point form holds
## comfortably for the coefficient ranges MPEG-1 can produce.
func _check_idct(h: Harness) -> void:
	var decoder := Mpeg1Video.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260815
	var worst := 0
	var worst_case := ""
	var cases := 0
	for trial in 48:
		var block := PackedInt32Array()
		block.resize(64)
		var non_zero := 1 + (trial % 12)
		for k in non_zero:
			var at := rng.randi_range(0, 63)
			block[at] = rng.randi_range(-320, 320)
		if trial == 0:
			block.fill(0)
			block[0] = 1024  # flat mid grey, the DC-only path
		var reference := _reference_idct(block)
		decoder.set("_block", block.duplicate())
		decoder.call("_idct")
		var got: PackedInt32Array = decoder.get("_block")
		cases += 1
		for i in 64:
			var diff: int = absi(got[i] - reference[i])
			if diff > worst:
				worst = diff
				worst_case = "trial %d, coefficient %d: %d against %d" % [
					trial, i, got[i], reference[i]]
	h.check("the integer IDCT matches the transform's own definition to within 1",
		worst <= 1, "worst error %d over %d blocks (%s)" % [worst, cases, worst_case])

	# The DC-only shortcut in `_store_block` claims to be exactly what the two
	# passes compute. Asserted rather than asserted-by-inspection, because it is
	# the path most blocks in a P or B picture take.
	var mismatch := 0
	for dc in [-2040, -1024, -8, 0, 8, 1024, 2040]:
		var block := PackedInt32Array()
		block.resize(64)
		block[0] = dc
		decoder.set("_block", block.duplicate())
		decoder.call("_idct")
		var full: PackedInt32Array = decoder.get("_block")
		var shortcut := ((int(dc) << 3) + 32) >> 6
		for i in 64:
			if full[i] != shortcut:
				mismatch += 1
	h.check("the DC-only shortcut equals the full transform",
		mismatch == 0, "%d of 448 samples differ" % mismatch)


## `f(x,y) = 1/4 * sum_u sum_v C(u)C(v) F(u,v) cos(...)`, Annex A, in doubles.
func _reference_idct(block: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(64)
	for y in 8:
		for x in 8:
			var total := 0.0
			for v in 8:
				for u in 8:
					var coefficient := float(block[v * 8 + u])
					if coefficient == 0.0:
						continue
					var cu := 1.0 / sqrt(2.0) if u == 0 else 1.0
					var cv := 1.0 / sqrt(2.0) if v == 0 else 1.0
					total += cu * cv * coefficient \
						* cos((2.0 * x + 1.0) * u * PI / 16.0) \
						* cos((2.0 * y + 1.0) * v * PI / 16.0)
			out[y * 8 + x] = int(round(total / 4.0))
	return out


## The two properties §2.4.4.2 states about a dequantised coefficient: it is
## always odd (the "oddification" step), and it never leaves [-2047, 2047].
##
## Asserted as properties rather than against a table of expected values, because
## a table of expected values computed the same way as the code proves nothing —
## which is `porting-fidelity-verification`'s whole subject.
func _check_dequant(h: Harness) -> void:
	var decoder := Mpeg1Video.new()
	decoder.call("_reset_matrices")
	var even := 0
	var out_of_range := 0
	var zero_stays_zero := true
	for quant in range(1, 32):
		decoder.set("_quant", quant)
		for level in [-255, -40, -2, -1, 1, 2, 40, 255]:
			for at in [0, 1, 9, 27, 63]:
				var intra: int = decoder.call("_dequant_intra", level, at)
				var inter: int = decoder.call("_dequant_non_intra", level, at)
				for value in [intra, inter]:
					if value != 0 and (int(value) & 1) == 0:
						even += 1
					if value > 2047 or value < -2047:
						out_of_range += 1
		if int(decoder.call("_dequant_intra", 0, 5)) != 0:
			zero_stays_zero = false
		if int(decoder.call("_dequant_non_intra", 0, 5)) != 0:
			zero_stays_zero = false
	h.check("every dequantised coefficient is odd", even == 0,
		"%d even results" % even)
	h.check("every dequantised coefficient is inside [-2047, 2047]",
		out_of_range == 0, "%d outside" % out_of_range)
	h.check("a zero coefficient dequantises to zero", zero_stays_zero)


## The colour matrix at the three points BT.601 studio range fixes exactly.
func _check_colour(h: Harness) -> void:
	var wrong: Array[String] = []
	for probe in [
		[16, 128, 128, 0, 0, 0],
		[235, 128, 128, 255, 255, 255],
		[128, 128, 128, 130, 130, 130],
	]:
		var got := _convert_one(int(probe[0]), int(probe[1]), int(probe[2]))
		for c in 3:
			if absi(int(got[c]) - int(probe[3 + c])) > 2:
				wrong.append("Y%d Cb%d Cr%d -> rgb(%d,%d,%d), wanted rgb(%d,%d,%d)" % [
					probe[0], probe[1], probe[2], got[0], got[1], got[2],
					probe[3], probe[4], probe[5]])
				break
	h.check("YCbCr to RGB is BT.601 with MPEG's studio range",
		wrong.is_empty(), "; ".join(wrong))


func _convert_one(y: int, cb: int, cr: int) -> PackedInt32Array:
	var decoder := Mpeg1Video.new()
	decoder.set("width", 2)
	decoder.set("height", 2)
	decoder.set("mb_width", 1)
	decoder.set("mb_height", 1)
	decoder.call("_allocate")
	decoder.set("_picture_type", Mpeg1Video.PICTURE_B)
	var planes: Array = decoder.call("current_planes")
	var y_plane: PackedByteArray = planes[0]
	var cb_plane: PackedByteArray = planes[1]
	var cr_plane: PackedByteArray = planes[2]
	y_plane.fill(y)
	cb_plane.fill(cb)
	cr_plane.fill(cr)
	var image: Image = decoder.call("to_image", [y_plane, cb_plane, cr_plane])
	var colour := image.get_pixel(0, 0)
	var out := PackedInt32Array()
	out.resize(3)
	out[0] = int(round(colour.r * 255.0))
	out[1] = int(round(colour.g * 255.0))
	out[2] = int(round(colour.b * 255.0))
	return out


## Decode one DCT coefficient out of a bit string, through the decoder's own
## reader. Returns what `_read_coefficient` returns.
func _decode_coefficient(bits: String) -> int:
	var decoder := Mpeg1Video.new()
	var stream := _bits_to_bytes(bits)
	decoder.set("_es", stream)
	decoder.set("_es_end", stream.size())
	decoder.call("_seek_bits", 0)
	return int(decoder.call("_read_coefficient"))


func _bits_to_bytes(bits: String) -> PackedByteArray:
	var out := PackedByteArray()
	var byte := 0
	var have := 0
	for i in bits.length():
		byte = (byte << 1) | (1 if bits[i] == "1" else 0)
		have += 1
		if have == 8:
			out.append(byte)
			byte = 0
			have = 0
	if have > 0:
		out.append(byte << (8 - have))
	for i in 8:
		out.append(0xFF)
	return out


# ============================================================== the data half


func _corpus_checks(h: Harness, args: Dictionary) -> void:
	var wanted := Args.text(args, "file", "")
	var png_dir := Args.text(args, "png", "")
	var limit := Args.number(args, "frames", 12)
	var from_frame := Args.number(args, "from", 0)
	if Args.flag(args, "all-frames"):
		limit = 1 << 30
		from_frame = 0
	var files: Array[String] = []
	if wanted != "":
		files.append(wanted)
	else:
		var paths := Paths.new()
		if paths.load_config():
			files = _find(str(paths.root))

	var case := "MPEG-1 files on the disc"
	h.begin(case)
	if files.is_empty():
		h.check(
			"this corpus holds no MPEG-1 file, so nothing was decoded here",
			true,
			"the format checks above are corpus-independent; "
			+ "run --root res://test-games/itamar-magichat for the only corpus with data")
		h.complete(case)
		return
	for file_path in files:
		await _one(h, file_path, limit, from_frame, png_dir, Args.flag(args, "oracle"))
	h.complete(case)


func _one(h: Harness, file_path: String, limit: int, from_frame: int,
		png_dir: String, oracle: bool) -> void:
	var name := file_path.get_file()
	print("")
	print("%s" % file_path)

	# Step 1: the system layer, on its own.
	var ps := Ps.new()
	if not ps.open(file_path):
		h.check("%s: the program stream demuxes" % name, false, str(ps.error))
		return
	print("  system: %d packs, %d video packets (%s), %d audio packets (%s), %d padding" % [
		ps.packs, ps.video_packets, "0x%02X" % ps.video_id,
		ps.audio_packets, "0x%02X" % ps.audio_id, ps.padding_packets])
	print("  clock : SCR span %.2f s, video PTS span %.2f s, %d video ES bytes" % [
		ps.scr_span_ms() / 1000.0, ps.pts_span_ms() / 1000.0, ps.video_bytes])
	var es := ps.video_elementary()
	h.check("%s: the video elementary stream opens with a sequence header" % name,
		es.size() > 4 and es[0] == 0 and es[1] == 0 and es[2] == 1 and es[3] == 0xB3,
		"first bytes %02X %02X %02X %02X" % [
			es[0] if es.size() > 0 else 0, es[1] if es.size() > 1 else 0,
			es[2] if es.size() > 2 else 0, es[3] if es.size() > 3 else 0])
	h.check("%s: every pack was walked and the clocks run forward" % name,
		ps.packs > 0 and ps.first_scr >= 0 and ps.last_scr >= ps.first_scr,
		"%d packs, SCR %d..%d" % [ps.packs, ps.first_scr, ps.last_scr])
	# The demux is a concatenation of payloads, so the elementary stream must be
	# shorter than the file and longer than nothing — a walk that lost its place
	# produces either a handful of bytes or something larger than the container.
	var file_size := 0
	var probe := FileAccess.open(file_path, FileAccess.READ)
	if probe != null:
		file_size = int(probe.get_length())
		probe.close()
	h.check("%s: the reassembled streams fit inside the file" % name,
		ps.video_bytes > 0 and ps.video_bytes + ps.audio_bytes < file_size
			and ps.video_bytes > file_size / 4,
		"%d video + %d audio bytes out of %d" % [
			ps.video_bytes, ps.audio_bytes, file_size])
	ps.close()

	# Step 2: the headers, through the reader the engine uses.
	var reader := Mpeg1.new()
	if not reader.open(file_path):
		h.check("%s: the reader opens it" % name, false, str(reader.error))
		return
	print("  video : %dx%d  %.4f fps  %d frames  %.2f s  %d bit/s  pel aspect %.4f" % [
		reader.width, reader.height, reader.fps, reader.frame_count,
		reader.duration_ms / 1000.0, reader.bit_rate, reader.pel_aspect])
	# The audio is `tools/mpeg1_audio.gd`'s subject and is only reported here, but
	# it is reported *truthfully*: this line said "no decoder — silent" for as
	# long as that was so, and a stale version of it would be the exact shape
	# `AGENTS.md` warns about — a sentence that reads as measured because it used
	# to be.
	print("  audio : layer %d, %d Hz, %d channel(s), %d bit/s, %d frames%s" % [
		reader.audio_layer, reader.audio_rate, reader.audio_channels,
		reader.audio_bitrate, reader.audio_frames,
		("  (%s)" % reader.audio_error) if str(reader.audio_error) != "" else ""])
	h.check("%s: the sequence header states a picture size and a frame rate" % name,
		reader.width > 0 and reader.height > 0 and reader.fps > 0.0,
		"%dx%d at %.4f fps" % [reader.width, reader.height, reader.fps])
	h.check("%s: it states a duration above zero" % name,
		reader.duration_ms > 0.0 and reader.frame_count > 0,
		"%.2f s, %d frames" % [reader.duration_ms / 1000.0, reader.frame_count])

	# Step 3 and 4: pictures.
	var start: int = clampi(from_frame, 0, maxi(reader.frame_count - 1, 0))
	var count: int = mini(limit, reader.frame_count - start)
	var began := Time.get_ticks_usec()
	var bad_size := 0
	var flat := 0
	var missing := 0
	var pictures := 0
	var best_colours := 0
	var best_mean := Vector3.ZERO
	var images: Array[Image] = []
	for k in count:
		var image: Image = reader.frame_at(start + k)
		if image == null:
			missing += 1
			continue
		if image.get_width() != reader.width or image.get_height() != reader.height:
			bad_size += 1
			continue
		var stats := _stats(image)
		var colours := int(stats["colours"])
		if colours <= 1:
			flat += 1
		if colours > 64:
			pictures += 1
		if colours > best_colours:
			best_colours = colours
			best_mean = stats["mean"]
		if png_dir != "" and images.size() < 8:
			images.append(image)
	var wall_us := Time.get_ticks_usec() - began
	var decoder = reader.video_decoder()
	var per_frame_ms := (wall_us / 1000.0) / maxf(count, 1)
	var budget_ms := 1000.0 / maxf(reader.fps, 0.001)
	print("  decode: %d display frames from %d coded pictures "
		% [count, reader.decoded_pictures()]
		+ "(%d I, %d P, %d B)" % [
			int(decoder.type_counts.get(Mpeg1Video.PICTURE_I, 0)),
			int(decoder.type_counts.get(Mpeg1Video.PICTURE_P, 0)),
			int(decoder.type_counts.get(Mpeg1Video.PICTURE_B, 0))])
	# Three numbers, because they answer three different questions and the first
	# one on its own has misled every reader of it. `per_frame_ms` is the wall
	# clock the caller waited per frame it asked for, and it includes decoding
	# every coded picture in front of the window — so asking for six frames from
	# frame 34 charges all 41 pictures to those six. `per_picture_ms` is the
	# steady-state cost of one coded picture, which is what sequential playback
	# pays. `convert_ms` is the YCbCr-to-RGB pass, which is per *displayed* frame
	# and scales with the picture area rather than with the bit rate.
	var per_picture_ms := reader.decode_cost_us() / 1000.0 		/ maxf(reader.decoded_pictures(), 1)
	var convert_ms := reader.convert_cost_us() / 1000.0 / maxf(count, 1)
	print("  cost  : %.1f ms per coded picture + %.1f ms to convert one frame; "
		% [per_picture_ms, convert_ms]
		+ "budget %.1f ms at %.4f fps -> %.0f%% of real time" % [
			budget_ms, reader.fps,
			100.0 * budget_ms / maxf(per_picture_ms + convert_ms, 0.001)])
	print("  window: %.1f ms/frame wall over %d frames from %d (%d pictures decoded), "
		% [per_frame_ms, count, start, reader.decoded_pictures()]
		+ "IDCT %.0f ms of %.0f ms" % [
			decoder.idct_us / 1000.0, decoder.decode_us / 1000.0])
	print("  slices: %d decoded, %d macroblocks (%d skipped), %d desynced" % [
		decoder.slices_decoded, decoder.macroblocks_decoded,
		decoder.skipped_macroblocks, decoder.desynced_slices])
	print("  pixels: %d of %d frames are pictures, %d flat; richest has %d colours, "
		% [pictures, count, flat, best_colours]
		+ "mean rgb(%.2f, %.2f, %.2f)" % [best_mean.x, best_mean.y, best_mean.z])

	h.check("%s: every requested frame decoded at the declared size" % name,
		missing == 0 and bad_size == 0,
		"%d missing, %d at the wrong size, of %d" % [missing, bad_size, count])
	# The strongest one. See this file's head.
	h.check("%s: every slice ended on padding rather than mid-code" % name,
		decoder.desynced_slices == 0,
		"%d of %d slices desynced — a VLC table or a reconstruction rule is wrong" % [
			decoder.desynced_slices, decoder.slices_decoded])
	# **Not "the first frame is a picture".** A clip that opens on a fade from
	# black decodes correctly to a flat black field, and asserting otherwise would
	# be this harness failing a right answer — which is exactly what it did on
	# `heb/mainmenu/intro.mpg`, whose first 30-odd frames are black on purpose.
	# What is asserted is that somewhere in the window asked for there is a real
	# picture, and `--from` is how a caller points the window at one.
	h.check("%s: at least one decoded frame is a picture rather than a flat field" % name,
		pictures > 0,
		"%d of %d frames above 64 colours on a 32x32 grid, from frame %d "
			% [pictures, count, start]
			+ "(a clip opening on a fade is legitimately flat; use --from)")
	h.check("%s: the richest frame's colours are plausible" % name,
		best_mean.x > 0.02 and best_mean.x < 0.98
			and best_mean.y > 0.02 and best_mean.y < 0.98
			and best_mean.z > 0.02 and best_mean.z < 0.98,
		"mean rgb(%.3f, %.3f, %.3f)" % [best_mean.x, best_mean.y, best_mean.z])
	# **Every I picture**, and not "most of every picture". An intra picture has
	# nothing to fall back on so all of it must be coded; a P or B picture may
	# leave macroblocks out of every slice and `heb/album/solution4.mpg` does. A
	# threshold over all three types failed that file for being well encoded,
	# which is a harness asserting a property of the data rather than of the port.
	h.check("%s: every I picture's slices accounted for all %d macroblocks" % [
			name, decoder.mb_width * decoder.mb_height],
		decoder.short_intra_pictures == 0,
		"%d I picture(s) short; least coverage of any picture %d%%" % [
			decoder.short_intra_pictures, decoder.least_coverage])

	# A backward seek must reproduce frame 0 exactly, which is the one property a
	# reordering decoder can get wrong invisibly — the same check
	# `tools/avi_decode.gd` makes of the MS-RLE delta chain, for the same reason.
	if count > 2 and start == 0:
		var first_again: Image = reader.frame_at(0)
		var first_data := PackedByteArray()
		var again_data := PackedByteArray()
		reader.close()
		var fresh := Mpeg1.new()
		if fresh.open(file_path):
			var straight: Image = fresh.frame_at(0)
			if straight != null:
				first_data = straight.get_data()
			fresh.close()
		if first_again != null:
			again_data = first_again.get_data()
		h.check("%s: a backward seek to frame 0 reproduces it" % name,
			not first_data.is_empty() and first_data == again_data,
			"a restart that lands on different pixels is a reference-buffer bug")
	else:
		reader.close()

	if png_dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(png_dir))
		for i in images.size():
			var out := "%s/%s.f%03d.png" % [png_dir, name.get_basename(), i]
			images[i].save_png(out)
			print("  wrote %s" % out)

	if oracle:
		await _oracle(h, file_path, name)


## Sample a grid of the picture: how many distinct colours it has, and the mean.
##
## A grid rather than every pixel, because this runs per frame and the question is
## "is there a picture here" rather than "what exactly is it". 1,024 samples is
## enough that a real frame reads in the hundreds and a flat field reads 1.
func _stats(image: Image) -> Dictionary:
	var seen: Dictionary = {}
	var total := Vector3.ZERO
	var samples := 0
	var w := image.get_width()
	var hgt := image.get_height()
	var step_x: int = maxi(w / 32, 1)
	var step_y: int = maxi(hgt / 32, 1)
	var y := 0
	while y < hgt:
		var x := 0
		while x < w:
			var colour := image.get_pixel(x, y)
			seen[colour.to_rgba32()] = true
			total += Vector3(colour.r, colour.g, colour.b)
			samples += 1
			x += step_x
		y += step_y
	if samples > 0:
		total /= float(samples)
	return {"colours": seen.size(), "mean": total}


## Compare against an Ogg Theora sidecar, frame for frame, where one exists.
##
## The sidecar is a **transcode of the same source**, so it is a genuinely
## independent decode: different container, different codec, different
## implementation, made by a tool that is not this port. Two decoders of the same
## original agreeing on the picture is a far stronger statement than "it is not
## blank" — and disagreeing tells which one to distrust, because Theora's decoder
## is Godot's own.
##
## The comparison is a **mean absolute difference on a downscaled pair**, not a
## byte compare: Theora is lossy, the transcode re-quantised everything, and the
## two chroma upsamplers differ. A frame that matches structurally lands in the
## low single digits out of 255; a frame that does not lands in the fifties.
func _oracle(h: Harness, file_path: String, name: String) -> void:
	var sidecar := Sidecar.fresh_for(file_path)
	if sidecar == "":
		h.check("%s: no sidecar to compare against (%s)" % [name, Sidecar.status_of(file_path)],
			true, "run tools/video_sidecar.gd to make one; this is not a failure")
		return
	var stream: VideoStream = ResourceLoader.load(sidecar, "VideoStream")
	if stream == null:
		h.check("%s: the sidecar loads as a VideoStream" % name, false, sidecar)
		return
	var player := VideoStreamPlayer.new()
	player.expand = true
	player.stream = stream
	root.add_child(player)
	player.play()
	var reader := Mpeg1.new()
	if not reader.open(file_path):
		h.check("%s: the reader opens it for the oracle" % name, false, str(reader.error))
		player.queue_free()
		return
	var worst := 0.0
	var mean_total := 0.0
	var compared := 0
	for probe in [0.5, 2.0, 5.0, 10.0]:
		if probe * 1000.0 > reader.duration_ms:
			continue
		player.stream_position = probe
		for _i in 6:
			await process_frame
		var theora: Texture2D = player.get_video_texture()
		if theora == null:
			continue
		var oracle_image: Image = theora.get_image()
		var ours: Image = reader.frame_at(reader.frame_index_at(probe * 1000.0))
		if oracle_image == null or ours == null:
			continue
		# **A headless run reads a `VideoStreamPlayer`'s texture back flat** —
		# `docs/DIGITAL_VIDEO.md` §9.1.1 measured exactly that and it is why the
		# figures there were taken from a windowed run. A flat oracle frame is not
		# a disagreement, it is no comparison at all, and treating it as one would
		# make this check fail on precisely the runs where it cannot work.
		if int(_stats(oracle_image)["colours"]) <= 2:
			print("  oracle: at %.1fs the sidecar read back flat — headless "
				% probe + "Theora yields no picture; not compared")
			continue
		var difference := _mean_difference(ours, oracle_image)
		if difference < 0.0:
			continue
		compared += 1
		mean_total += difference
		worst = maxf(worst, difference)
		print("  oracle: at %.1fs mean |difference| %.1f of 255" % [probe, difference])
	reader.close()
	player.queue_free()
	if compared == 0:
		h.check("%s: the sidecar produced no frame to compare" % name, true,
			"headless Theora playback did not yield a texture; not asserted")
		return
	h.check("%s: agrees with the Theora sidecar to within 24 of 255" % name,
		worst < 24.0,
		"worst %.1f, mean %.1f over %d probes" % [worst, mean_total / compared, compared])


## Mean absolute difference between two pictures, on a common 32x32 grid.
##
## Downscaled first, because the two decoders differ by a pixel of chroma phase
## and by whatever the transcoder's scaler did, and a per-pixel compare at full
## resolution measures those rather than whether the picture is the same picture.
func _mean_difference(a: Image, b: Image) -> float:
	if a == null or b == null:
		return -1.0
	var left := a.duplicate() as Image
	var right := b.duplicate() as Image
	left.convert(Image.FORMAT_RGB8)
	right.convert(Image.FORMAT_RGB8)
	left.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	right.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in 32:
		for x in 32:
			var p := left.get_pixel(x, y)
			var q := right.get_pixel(x, y)
			total += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
	return total / (32.0 * 32.0 * 3.0) * 255.0


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


# ------------------------------------------------- the tables, stated here too
#
# The tables the decoder builds from are private to it; these are the same rows
# written out a second time so that the audit above compares two statements of
# them rather than checking one against itself. That is deliberate duplication
# and it is the point: a Kraft sum computed from the decoder's own array would
# pass whatever the array said. B.14 is the exception — it is large enough that a
# second transcription would be a second source of error rather than a check, so
# it is read from the decoder and audited for structure only, with the round trip
# above as its behavioural test.


func _mba_rows() -> Array:
	return [
		["1", 1], ["011", 2], ["010", 3], ["0011", 4], ["0010", 5],
		["00011", 6], ["00010", 7], ["0000111", 8], ["0000110", 9],
		["00001011", 10], ["00001010", 11], ["00001001", 12], ["00001000", 13],
		["00000111", 14], ["00000110", 15], ["0000010111", 16], ["0000010110", 17],
		["0000010101", 18], ["0000010100", 19], ["0000010011", 20],
		["0000010010", 21], ["00000100011", 22], ["00000100010", 23],
		["00000100001", 24], ["00000100000", 25], ["00000011111", 26],
		["00000011110", 27], ["00000011101", 28], ["00000011100", 29],
		["00000011011", 30], ["00000011010", 31], ["00000011001", 32],
		["00000011000", 33], ["00000001111", 34], ["00000001000", 35],
	]


func _type_p_rows() -> Array:
	return [
		["1", 0x0A], ["01", 0x08], ["001", 0x02], ["00011", 0x10],
		["00010", 0x0B], ["00001", 0x09], ["000001", 0x11],
	]


func _type_b_rows() -> Array:
	return [
		["10", 0x06], ["11", 0x0E], ["010", 0x04], ["011", 0x0C],
		["0010", 0x02], ["0011", 0x0A], ["00011", 0x10], ["00010", 0x0F],
		["000011", 0x0B], ["000010", 0x0D], ["000001", 0x11],
	]


func _cbp_rows() -> Array:
	return [
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


func _motion_rows() -> Array:
	# Biased by +16, so the row for motion_code -16 carries 0. The pattern to read
	# it against: the code for -m and the code for +m differ in their last bit
	# only, odd for negative.
	return [
		["00000011001", 0], ["00000011011", 1], ["00000011101", 2],
		["00000011111", 3], ["00000100001", 4], ["00000100011", 5],
		["0000010011", 6], ["0000010101", 7], ["0000010111", 8],
		["00000111", 9], ["00001001", 10], ["00001011", 11],
		["0000111", 12], ["00011", 13], ["0011", 14], ["011", 15],
		["1", 16], ["010", 17], ["0010", 18], ["00010", 19], ["0000110", 20],
		["00001010", 21], ["00001000", 22], ["00000110", 23],
		["0000010110", 24], ["0000010100", 25], ["0000010010", 26],
		["00000100010", 27], ["00000100000", 28], ["00000011110", 29],
		["00000011100", 30], ["00000011010", 31], ["00000011000", 32],
	]


func _dc_luma_rows() -> Array:
	return [
		["100", 1], ["00", 2], ["01", 3], ["101", 4], ["110", 5],
		["1110", 6], ["11110", 7], ["111110", 8], ["1111110", 9],
	]


func _dc_chroma_rows() -> Array:
	return [
		["00", 1], ["01", 2], ["10", 3], ["110", 4], ["1110", 5],
		["11110", 6], ["111110", 7], ["1111110", 8], ["11111110", 9],
	]
