class_name DirectorBitmap
extends RefCounted
## One bitmap cast member's pixels: a `BITD` chunk unpacked and coloured.
##
## Geometry comes from the member record, never from the chunk. The `BITD` is a
## byte stream with no header of its own, so its width, height, row stride and
## depth are only knowable from the `CASt` that owns it — which is why this takes
## a member dictionary rather than trying to infer anything.
##
## Two rules the corpus enforces, both of which look like optimisations and are
## not:
##
## A chunk whose length is exactly `stride * height` is stored raw, and must be
## tested for *before* the run-length decoder is tried. 294 members here are
## stored that way. For 289 of them the RLE reading runs off the end; for the
## other 5 it succeeds and produces different pixels, and all 5 are one pixel
## wide, which is why nobody noticed.
##
## A decode that does not fill the buffer is a failure, not a partial success.
## Accepting a clean prefix is what left most of one movie's members decoding to
## the wrong size and being recorded as authentic.

## Run-length byte: high bit set means a repeat, clear means a literal.
const RUN_FLAG := 0x80
## Stated here rather than reached through `DirectorPalette`: a global class name
## resolves out of the editor's script cache, which a headless `--script` run has
## no reason to have refreshed, so referring to one turns this file into a parse
## error in a tool nobody touched.
const PAPER_INDEX := 0
const INK_INDEX := 255


## Unpack a `BITD` payload to exactly `stride * height` bytes. Empty on failure,
## with the reason in `error`.
static func unpack(chunk: PackedByteArray, stride: int, height: int, error: Array) -> PackedByteArray:
	var needed := stride * height
	if needed <= 0:
		error.append("zero-area member")
		return PackedByteArray()
	# Uncompressed first: see the note above.
	if chunk.size() == needed:
		return chunk

	var out := PackedByteArray()
	out.resize(needed)
	var written := 0
	var at := 0
	var size := chunk.size()
	while written < needed and at < size:
		var control := chunk[at]
		at += 1
		if (control & RUN_FLAG) != 0:
			var run := 257 - control
			if at >= size:
				break
			var value := chunk[at]
			at += 1
			for _i in run:
				if written >= needed:
					break
				out[written] = value
				written += 1
		else:
			var count := control + 1
			for _i in count:
				if written >= needed or at >= size:
					break
				out[written] = chunk[at]
				at += 1
				written += 1
	if written != needed:
		error.append("filled %d of %d bytes" % [written, needed])
		return PackedByteArray()
	return out


## The finished image: `FORMAT_RGBA8`, `width x height`, opaque everywhere.
##
## Not `stride x height`: the row padding is real in the buffer and must not
## reach the image. The matte pass floods inward from the border, so padding
## carried into the picture would seed the fill from bytes that are not artwork.
##
## Alpha is left at 255 for every pixel. Keying is the ink passes' job, and they
## depend on palette index 0 arriving as exactly (255,255,255).
static func decode(member: Dictionary, chunk: PackedByteArray, palette: PackedByteArray, error: Array) -> Image:
	var width := int(member.get("width", 0))
	var height := int(member.get("height", 0))
	var stride := int(member.get("row_stride", 0))
	var depth := int(member.get("bits_per_pixel", 8))
	if width <= 0 or height <= 0:
		error.append("zero-area member")
		return null
	# A stride shorter than the row the width and depth need is a **misread
	# member record**, not a picture to attempt. The blits below index
	# `y * stride + x` against a buffer of exactly `stride * height`, so a short
	# stride runs off the end on the first row -- and a GDScript out-of-bounds
	# read aborts the function it happens in, which means the blit stops
	# half-written and `Image.create_from_data` is handed whatever was in the
	# buffer. That is a wrong picture drawn silently on every repaint, with the
	# only trace an engine error in a log nobody is reading.
	#
	# Reported here rather than clamped. Clamping would draw *something* for a
	# member whose geometry the port has misunderstood, and the wrong picture is
	# the failure that survives review; `director_cast.gd:STRIDE_MASK` is where
	# the one real instance came from and what it cost to find.
	var row := int(ceili(float(width) * float(depth) / 8.0))
	if stride < row:
		error.append("row stride %d is shorter than the %d byte(s) a %d-pixel row of %d-bit pixels needs"
			% [stride, row, width, depth])
		return null

	var buffer := unpack(chunk, stride, height, error)
	if buffer.is_empty():
		return null

	# One loop per depth rather than one branch per pixel. The obvious shape —
	# a `match depth` inside the x loop — costs a dispatch and four bounds-checked
	# writes on every one of ten million pixels, which measured at 0.24 us/pixel
	# and put a 640x480 background at 75 ms by itself.
	var pixels := PackedByteArray()
	pixels.resize(width * height * 4)
	match depth:
		8:
			_blit_8(buffer, pixels, width, height, stride, _rgba_table(palette))
		1:
			_blit_1(buffer, pixels, width, height, stride, _rgba_table(palette))
		16:
			_blit_16(buffer, pixels, width, height, stride)
		32:
			_blit_32(buffer, pixels, width, height, stride)
		_:
			error.append("unsupported depth %d" % depth)
			return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)


## A 1-bit member's bits as one byte per pixel: 255 where the bit is set, 0 where
## it is clear. Empty when the member is not 1-bit or the chunk will not unpack.
##
## **This is Mask ink's mask (§2.6), and it deliberately does not go through
## `decode`.** `decode` turns a 1-bit member into RGBA through the palette, and
## the mask is not a picture: `Channel::getMask`'s Mask arm copies the mask
## bitmap's *surface* into a scratch surface and `DirectorPlotData::inkBlitSurface`
## then draws a pixel wherever that byte is **non-zero**
## (`graphics.cpp:806`, `if (!(mask || srfMask) || (msk && (*msk++)))`). Reading it
## as colour instead would make the answer depend on which palette the mask member
## happens to name -- entry 255 is black in the port's own table and is whatever
## the cast says in a member that names its own -- and the mask would silently
## invert on any member whose palette does not put black at 255.
##
## **The polarity is settled from the reference and is not a guess.**
## `BITDDecoder::loadStream`'s `case 1` writes `0xff` for a set bit and `0x00` for
## a clear one (ScummVM `engines/director/images.cpp` @ 805f259a), and the blit
## draws on non-zero. So **a set bit shows the sprite and a clear bit hides it**,
## which in Director's 1-bit convention means the mask member's *black* pixels are
## the ones the artwork comes through. `ENGINE_TODO.md` recorded the polarity as
## "undecidable" with 0 records of ink 9 in the corpus; it is undecidable from the
## *data*, and the decoder and the blitter between them decide it exactly.
##
## The bit order is MSB-first within each byte, the same as `_blit_1` -- one rule,
## written twice because the two produce different things, and any disagreement
## between them would show as a mask mirrored inside every group of eight pixels.
static func mask_bits(member: Dictionary, chunk: PackedByteArray, error: Array) -> PackedByteArray:
	var out := PackedByteArray()
	if int(member.get("bits_per_pixel", 8)) != 1:
		error.append("mask member is %d-bit, not 1-bit"
			% int(member.get("bits_per_pixel", 8)))
		return out
	var width := int(member.get("width", 0))
	var height := int(member.get("height", 0))
	var stride := int(member.get("row_stride", 0))
	if width <= 0 or height <= 0:
		error.append("zero-area mask member")
		return out
	var row := int(ceili(float(width) / 8.0))
	if stride < row:
		error.append("row stride %d is shorter than the %d byte(s) a %d-pixel 1-bit row needs"
			% [stride, row, width])
		return out
	var buffer := unpack(chunk, stride, height, error)
	if buffer.is_empty():
		return out
	out.resize(width * height)
	var at := 0
	for y in height:
		var base := y * stride
		for x in width:
			out[at] = 255 if ((buffer[base + (x >> 3)] >> (7 - (x & 7))) & 1) == 1 else 0
			at += 1
	return out


## The palette expanded to 256 opaque RGBA entries, so the inner loop reads four
## adjacent bytes instead of doing three multiplies and an alpha store.
static func _rgba_table(palette: PackedByteArray) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(1024)
	for i in 256:
		lut[i * 4] = palette[i * 3]
		lut[i * 4 + 1] = palette[i * 3 + 1]
		lut[i * 4 + 2] = palette[i * 3 + 2]
		lut[i * 4 + 3] = 255
	return lut


static func _blit_8(src: PackedByteArray, dst: PackedByteArray, width: int, height: int, stride: int, lut: PackedByteArray) -> void:
	var at := 0
	for y in height:
		var row := y * stride
		for x in width:
			var i := src[row + x] << 2
			dst[at] = lut[i]
			dst[at + 1] = lut[i + 1]
			dst[at + 2] = lut[i + 2]
			dst[at + 3] = lut[i + 3]
			at += 4


## MSB first within each byte; a set bit is ink.
static func _blit_1(src: PackedByteArray, dst: PackedByteArray, width: int, height: int, stride: int, lut: PackedByteArray) -> void:
	var paper := PAPER_INDEX << 2
	var ink := INK_INDEX << 2
	var at := 0
	for y in height:
		var row := y * stride
		for x in width:
			var bit := (src[row + (x >> 3)] >> (7 - (x & 7))) & 1
			var i: int = ink if bit == 1 else paper
			dst[at] = lut[i]
			dst[at + 1] = lut[i + 1]
			dst[at + 2] = lut[i + 2]
			dst[at + 3] = 255
			at += 4


## Planar within the row: every high byte, then every low byte. Read as
## interleaved pairs it comes out as noise.
static func _blit_16(src: PackedByteArray, dst: PackedByteArray, width: int, height: int, stride: int) -> void:
	var at := 0
	for y in height:
		var row := y * stride
		for x in width:
			var rgb555 := (src[row + x] << 8) | src[row + width + x]
			dst[at] = ((rgb555 >> 10) & 0x1F) * 255 / 31
			dst[at + 1] = ((rgb555 >> 5) & 0x1F) * 255 / 31
			dst[at + 2] = (rgb555 & 0x1F) * 255 / 31
			dst[at + 3] = 255
			at += 4


## Four planes per row. Plane 0 is zero on real white pixels, so it is not alpha
## and every pixel stays opaque.
static func _blit_32(src: PackedByteArray, dst: PackedByteArray, width: int, height: int, stride: int) -> void:
	var at := 0
	for y in height:
		var row := y * stride
		var g_row := row + width * 2
		var b_row := row + width * 3
		var r_row := row + width
		for x in width:
			dst[at] = src[r_row + x]
			dst[at + 1] = src[g_row + x]
			dst[at + 2] = src[b_row + x]
			dst[at + 3] = 255
			at += 4
