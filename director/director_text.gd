extends RefCounted
## Field and text cast members: laying their text out and drawing it.
##
## Title-agnostic. Nothing here knows what game is loaded.
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

## Director's alignment codes, from the member's specific block.
const ALIGN_LEFT := 0
const ALIGN_CENTRE := 1
const ALIGN_RIGHT := -1


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
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return 0
	var size := int(style.get("font_size", 12))
	var line_height := int(style.get("line_height", 16))
	var ascent := int(style.get("ascent", 12))
	var colour: Color = style.get("color", Color.BLACK)
	colour.a *= clampf(alpha, 0.0, 1.0)
	var align := int(style.get("align", ALIGN_LEFT))
	var h_align := HORIZONTAL_ALIGNMENT_LEFT
	if align == ALIGN_CENTRE:
		h_align = HORIZONTAL_ALIGNMENT_CENTER
	elif align == ALIGN_RIGHT:
		h_align = HORIZONTAL_ALIGNMENT_RIGHT

	var drawn := 0
	var y := rect.position.y + ascent
	# Director's own line breaks first, then wrapping inside each of them. Doing
	# it in this order matters: a field's text is frequently a record with one
	# item per line — `empty\nempty\nempty` for an inventory — and wrapping that
	# as one paragraph would silently merge rows that the scripts index by line.
	for raw_line in text.split("\n"):
		for line in _wrap(font, str(raw_line), size, rect.size.x):
			if y - ascent >= rect.position.y + rect.size.y:
				return drawn
			canvas.draw_string(font, Vector2(rect.position.x, y), line,
				h_align, rect.size.x, size, colour)
			y += line_height
			drawn += 1
	return drawn


## Break one authored line at the field's width. Returns at least one entry, so a
## line that cannot be broken is still drawn (and clipped) rather than dropped.
static func _wrap(font: Font, line: String, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	if line == "" or width <= 0.0:
		out.append(line)
		return out
	if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		out.append(line)
		return out
	var current := ""
	for word in line.split(" "):
		var candidate: String = word if current == "" else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width \
				or current == "":
			current = candidate
			continue
		out.append(current)
		current = str(word)
	out.append(current)
	return out
