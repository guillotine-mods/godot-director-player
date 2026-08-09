extends RefCounted
## Field and text cast members: laying their text out and drawing it.
##
## Title-agnostic. Nothing here knows what game is loaded.
##
## **`layout` is the piece everything else here is built on**, and it was split
## out of `draw` rather than added beside it. A caret is a character index and a
## glyph run is pixels, and the only honest bridge between them is knowing where
## each drawn line began *in the source string* -- which wrapping destroys unless
## it is tracked. Two layout functions that disagree by one wrapped line put the
## caret on the wrong row while the drawn text looks perfectly correct, so the
## painter, the caret and the click-to-caret mapping all read this one.
##
## **Scope, stated plainly rather than implied.** This draws legible text in
## roughly the right place at roughly the right size, in the member's own colour
## and alignment. It is *not* period-accurate glyph rendering: Director composed
## these fields out of Mac bitmap fonts named by a font id this port has no table
## to resolve, and what is drawn here is Godot's fallback typeface at the member's
## point size. Line breaks, wrapping width, colour, slant and alignment come from
## the data; the letterforms and therefore the exact advance widths do not. A
## caption will not land pixel-for-pixel where Director put it.
##
## That is still a large improvement over the alternative, which is what this port
## did until now: `_texture_for` returned null for every member that was not a
## bitmap, so 11,525 field sprite records across this corpus drew nothing at all
## and the game's whole HUD — its score, its inventory, its process list — was
## simply absent from the stage while the Lingo behind it worked.
##
## What the corpus holds, over its 321 field members (`tools/draw_survey.gd` and
## the STXT run measurements in `director_cast.gd`):
##
##   style runs   exactly 1 per member in all 321, so one style per field
##   point size   12 in 292, then 14, 48, 96, 24, 36, 9
##   slant        upright 306, italic 15
##   colour       black 308, near-white 2, blue (0,51,255) 11
##   alignment    left 308, centre 13
##   ink          Background Transparent on all 11,525 field sprite records
##   foreColor    255 (Director's black) on all 11,525 — no field ever colourises
##
## The last line is worth keeping: colourisation (2.3) and text rendering look
## like one piece of work and are not. Not one field sprite in this corpus carries
## a non-default foreColor. A field's colour comes from its own STXT run.

## Godot's fallback font has no bitmap-font metrics to match, so a line height has
## to be derived when the member's STXT run does not carry one. 4/3 of the point
## size is the ratio the runs that *do* carry one show (16 for a 12pt run).
const LINE_HEIGHT_RATIO := 4.0 / 3.0

## Glyphs go to the canvas item rather than through `CanvasItem.draw_string`, so
## that a field repaints from `updateStage` as well as from `_draw`. See
## `director_paint.gd`.
const Paint := preload("res://director/director_paint.gd")

## Director's alignment codes, from the member's specific block.
const ALIGN_LEFT := 0
const ALIGN_CENTRE := 1
const ALIGN_RIGHT := -1

## Godot's built-in fallback face carries Latin, and this port now hands it text
## that is not: `director/director_codepage.gd` decodes a title's bytes into real
## Unicode, so a Hebrew field arrives as Hebrew rather than as the Latin-1
## mojibake it used to be, and a player typing into an editable field can produce
## any script the keyboard has. A face with no glyph for a code point draws a
## blank box, which would read as "the encoding fix made it worse".
##
## So the built-in face is kept as the *base* -- every metric this port has ever
## measured is its, and swapping it wholesale would move every wrapped line -- and
## the platform's own fonts are hung off it as fallbacks. A code point the base
## has draws exactly as before; one it does not comes from the system. Built once
## and cached, because a `SystemFont` resolves through the OS.
static var _font: Font = null


static func face() -> Font:
	if _font != null:
		return _font
	_font = ThemeDB.fallback_font
	if _font == null:
		return _font
	var system := SystemFont.new()
	# Generic families rather than face names: naming a face is naming a
	# platform, and every desktop resolves at least one of these to something
	# with wide coverage.
	system.font_names = PackedStringArray(["sans-serif", "Arial", "Segoe UI",
		"Helvetica", "DejaVu Sans", "Noto Sans"])
	system.allow_system_fallback = true
	var variation := FontVariation.new()
	variation.base_font = _font
	variation.fallbacks = [system]
	_font = variation
	return _font


## The style a field draws in: its point size, colour, slant and alignment,
## resolved from the member with a usable answer for every missing piece.
static func style_of(member: Dictionary) -> Dictionary:
	var run: Dictionary = member.get("text_style", {})
	var size := int(run.get("font_size", 0))
	if size <= 0:
		size = 12
	var height := int(run.get("line_height", 0))
	if height <= 0:
		height = int(round(size * LINE_HEIGHT_RATIO))
	var ascent := int(run.get("ascent", 0))
	if ascent <= 0:
		# Director's own runs put the ascent at three quarters of the line height
		# (12 of 16 on a 12pt run), which is where a baseline sits for a Latin
		# face. Derived rather than assumed to be the point size: they differ.
		ascent = int(round(height * 0.75))
	var colour: Variant = run.get("color", null)
	return {
		"font_size": size,
		"line_height": height,
		"ascent": ascent,
		"color": colour if colour is Color else Color.BLACK,
		"italic": int(run.get("slant", 0)) != 0,
		"align": int(member.get("text_align", ALIGN_LEFT)),
	}


## Where every line of a field's text lands, before anything is painted.
##
## One entry per drawn line: `{"text", "start", "top", "baseline"}`, with `start`
## the offset of the line's first character **in the whole string**. That last
## field is what makes a caret possible at all -- a caret is a character index and
## a glyph run is pixels, and the only honest bridge between them is knowing where
## each drawn line began in the source.
##
## Split out of `draw` rather than added beside it on purpose. Two layout
## functions that disagree by one wrapped line put the caret on the wrong row and
## nothing about the drawn text looks wrong, so both the painter and the hit test
## read this one.
##
## Lines that fall past the bottom edge are **not** returned, because Director
## clips to the box and a caret cannot be placed where no glyph was drawn.
static func layout(rect: Rect2, text: String, style: Dictionary) -> Array:
	var out: Array = []
	var font: Font = face()
	if font == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return out
	var size := int(style.get("font_size", 12))
	var line_height := int(style.get("line_height", 16))
	var ascent := int(style.get("ascent", 12))
	var top := rect.position.y
	var at := 0
	# Director's own line breaks first, then wrapping inside each of them. Doing
	# it in this order matters: a field's text is frequently a record with one
	# item per line — `empty\nempty\nempty` for an inventory — and wrapping that
	# as one paragraph would silently merge rows that the scripts index by line.
	for raw_line in text.split("\n"):
		for span in _wrap(font, str(raw_line), size, rect.size.x):
			if top >= rect.position.y + rect.size.y:
				return out
			var start := at + int(span[0])
			out.append({
				"text": str(span[2]),
				"start": start,
				"top": top,
				"baseline": top + ascent,
			})
			top += line_height
		# +1 for the newline the split consumed. A trailing newline therefore
		# leaves the caret a row of its own, which is what a text widget does.
		at += str(raw_line).length() + 1
	return out


## Draw a field's text into a canvas, inside `rect`.
##
## `rect` is the sprite's stage rect — the single placement rule of 1.1, with a
## field's registration offset of (0,0) making its top-left the sprite's own
## start point. Director lays text out inside the member's box and clips to it;
## this wraps to the rect's width and stops at its bottom edge, which is the same
## observable behaviour for a field that fits and a visible truncation for one
## that does not.
##
## Deliberately drawn straight into the canvas rather than rendered to an image
## and returned as a texture. A texture would have to be rebuilt on every change
## to the text, and a field's text is exactly the thing a script rewrites every
## few frames; drawing it costs nothing to keep current.
##
## Returns the number of lines it actually drew, so a caller can assert that
## something reached the screen instead of assuming it did.
static func draw(canvas: CanvasItem, rect: Rect2, text: String, style: Dictionary,
		alpha: float = 1.0) -> int:
	if text == "" or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return 0
	var font: Font = face()
	if font == null:
		return 0
	var size := int(style.get("font_size", 12))
	var colour: Color = style.get("color", Color.BLACK)
	colour.a *= clampf(alpha, 0.0, 1.0)
	var h_align := h_alignment(style)

	var drawn := 0
	for line_value in layout(rect, text, style):
		var line: Dictionary = line_value
		Paint.text(canvas, font, Vector2(rect.position.x, float(line["baseline"])),
			str(line["text"]), h_align, rect.size.x, size, colour)
		drawn += 1
	return drawn


## The member's alignment as Godot spells it.
static func h_alignment(style: Dictionary) -> int:
	match int(style.get("align", ALIGN_LEFT)):
		ALIGN_CENTRE:
			return HORIZONTAL_ALIGNMENT_CENTER
		ALIGN_RIGHT:
			return HORIZONTAL_ALIGNMENT_RIGHT
	return HORIZONTAL_ALIGNMENT_LEFT


## Where a drawn line starts horizontally, which is only `rect.position.x` for a
## left-aligned field. `draw_string` is given the box width and does the
## alignment itself, so a caret that assumed the left edge would sit under the
## wrong character in all 13 of this corpus's centred fields.
static func line_origin_x(rect: Rect2, line: String, style: Dictionary) -> float:
	var font: Font = face()
	if font == null:
		return rect.position.x
	var size := int(style.get("font_size", 12))
	var width: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	match h_alignment(style):
		HORIZONTAL_ALIGNMENT_CENTER:
			return rect.position.x + maxf(0.0, (rect.size.x - width) * 0.5)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return rect.position.x + maxf(0.0, rect.size.x - width)
	return rect.position.x


## The caret rectangle for a character index: a one-pixel-wide bar the height of
## a line, or an empty rect when the index is not on a drawn line.
##
## An index past the end of the text is answered at the end of the last line
## rather than refused, because that is where the caret sits after typing the
## final character and refusing it would make the caret vanish exactly when the
## player is using it.
static func caret_rect(rect: Rect2, text: String, style: Dictionary, index: int) -> Rect2:
	var lines: Array = layout(rect, text, style)
	if lines.is_empty():
		# An empty field still has a caret, at the start of the box.
		return Rect2(line_origin_x(rect, "", style), rect.position.y,
			1.0, float(style.get("line_height", 16)))
	var want: int = clampi(index, 0, text.length())
	var chosen: Dictionary = lines[lines.size() - 1]
	var column: int = str(chosen["text"]).length()
	for line_value in lines:
		var line: Dictionary = line_value
		var start := int(line["start"])
		var length: int = str(line["text"]).length()
		if want <= start + length:
			chosen = line
			column = maxi(0, want - start)
			break
	var font: Font = face()
	var size := int(style.get("font_size", 12))
	var before: String = str(chosen["text"]).substr(0, column)
	var x: float = line_origin_x(rect, str(chosen["text"]), style)
	if font != null:
		x += font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Rect2(x, float(chosen["top"]), 1.0, float(style.get("line_height", 16)))


## The character index a stage point falls on: which line the y is in, then the
## nearest character boundary along it.
##
## **Boundary, not glyph.** Clicking the left half of a character puts the caret
## before it and the right half after it, which is what every text widget since
## the Mac has done and what makes clicking at the end of a word behave.
static func index_at(rect: Rect2, text: String, style: Dictionary, at: Vector2) -> int:
	var lines: Array = layout(rect, text, style)
	if lines.is_empty():
		return 0
	var chosen: Dictionary = lines[0]
	for line_value in lines:
		var line: Dictionary = line_value
		if at.y >= float(line["top"]):
			chosen = line
	var font: Font = face()
	var body: String = str(chosen["text"])
	if font == null:
		return int(chosen["start"])
	var size := int(style.get("font_size", 12))
	var origin: float = line_origin_x(rect, body, style)
	var best := 0
	var best_gap: float = absf(at.x - origin)
	for i in range(1, body.length() + 1):
		var edge: float = origin + font.get_string_size(
			body.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var gap: float = absf(at.x - edge)
		if gap < best_gap:
			best_gap = gap
			best = i
	return int(chosen["start"]) + best


## Break one authored line at the field's width. Returns at least one span, so a
## line that cannot be broken is still drawn (and clipped) rather than dropped.
##
## `[start, end, text]` per span, with the offsets relative to `line`. The
## offsets are the reason this returns triples rather than strings: reassembling
## the wrapped text with a single space between words loses where the break fell,
## and a caret index counted off the reassembly drifts by one per wrap.
static func _wrap(font: Font, line: String, size: int, width: float) -> Array:
	var out: Array = []
	if line == "" or width <= 0.0 \
			or font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		out.append([0, line.length(), line])
		return out
	# Greedy, one word at a time, exactly as this wrapped before indices were
	# tracked: take words while the line still fits, and break in front of the
	# first one that does not. A word wider than the box is kept on its own line
	# and clipped rather than dropped, which is the `or accepted < 0` arm.
	var start := 0
	var accepted := -1
	var word_at := 0
	var words: PackedStringArray = line.split(" ")
	for w in words.size():
		var word: String = str(words[w])
		var candidate_end: int = word_at + word.length()
		if accepted < 0 or font.get_string_size(line.substr(start, candidate_end - start),
				HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			accepted = candidate_end
		else:
			out.append([start, accepted, line.substr(start, accepted - start)])
			start = word_at
			accepted = candidate_end
		# +1 for the space the split consumed.
		word_at = candidate_end + 1
	out.append([start, accepted, line.substr(start, accepted - start)])
	return out
