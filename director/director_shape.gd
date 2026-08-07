extends RefCounted
## QuickDraw shape cast members: what a type-8 member paints, and what it does not.
##
## Title-agnostic. Nothing here knows what game is loaded.
##
## The one thing to carry away: **most shape members paint nothing, and that is
## the point.** An outlined shape's stored line thickness is one greater than the
## drawn one, so a stored thickness of 1 is an outline zero pixels wide —
## invisible. Across this corpus 162 of the 169 shape members are unfilled
## rectangles with a stored thickness of exactly 1, and they account for 60,100 of
## the 60,914 shape sprite records the score writes. They are the game's hotspots:
## an invisible rectangle over the scenery, with a behaviour attached, named `to
## clif2` or `dwarf_well`. Director draws nothing for them and they go on catching
## clicks.
##
## That is why this returns `null` for them rather than a transparent image, and
## why it never paints the paper. A shape that filled its rect with the sprite's
## backColor before keying would be correct-looking under Background Transparent
## (68% of this corpus keys the paper out again) and would put an opaque white
## rectangle on the screen for each of the 8,302 shape records that use Copy —
## over the scenery, in every room. The image this returns is already keyed: the
## shape in foreColor, everything else transparent. Callers must not run an ink
## keying pass over it.
##
## What the corpus actually holds, from `tools/draw_survey.gd` and the per-member
## breakdown behind it, over 169 shape members and 60,914 sprite records:
##
##   shape kind    1 rectangle 167,  2 rounded rectangle 2
##   fill          unfilled 162,  filled 7            (60,100 / 814 records)
##   thickness     1 in 164,  2 in 4,  0 in 1
##   pattern       1 (solid) in all 169
##   sprite type   16 (cast member) in all 60,914 — so the member's kind always
##                 decides, and the sprite record's own shape type never does
##
## Colour comes from the *sprite*, not the member: 13. The member carries a fore
## and a back byte of its own and the score overrides both on every record.

## Director's shape kinds, from the member's own byte.
const RECTANGLE := 1
const ROUNDED_RECTANGLE := 2
const OVAL := 3
const LINE := 4

## The corner inset a rounded rectangle uses. Director stores no radius on the
## member — the authoring tool draws QuickDraw's default rounded corner — so this
## is a fixed inset chosen to look like one rather than a decoded value.
const CORNER_RADIUS := 6


## The image a shape sprite paints, or `null` when it paints nothing.
##
## `fore` and `back` are the sprite's colours already resolved through the
## palette. `size` is the sprite's drawn size, which is authoritative for every
## cast type (1.2) and for a shape is the whole geometry: a shape has no
## registration point and no natural art, so its rect *is* the shape.
## `_back` is taken and deliberately unused: the paper is left transparent rather
## than painted, for the reason in this file's header. It stays in the signature
## because a caller reading this has both colours in hand and would otherwise be
## left wondering which one it forgot to pass.
static func render(member: Dictionary, fore: Color, _back: Color, size: Vector2i) -> Image:
	if size.x <= 0 or size.y <= 0:
		return null
	var kind := int(member.get("shape_type", RECTANGLE))
	var filled := int(member.get("fill_type", 0)) != 0
	# The decrement applies to outlined shapes, which is what makes a stored 1
	# invisible. A filled shape keeps its stored thickness, because there the
	# thickness only widens a border it already has.
	var line: int = int(member.get("line_thickness", 1))
	if not filled:
		line -= 1
		if line <= 0:
			return null

	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Every shape member in this corpus carries pattern 1, which is solid. The
	# patterns that are not — 57-64 are tiles out of the movie's tile table — are
	# not implemented, and a patterned shape therefore comes out solid rather than
	# blank. Solid is the safer wrong answer: a blank hotspot is invisible either
	# way, and a blank *filled* shape would lose artwork.
	# Kinds 3 and 4 do not occur in this corpus — every member here is 1 or 2 —
	# so their arms are written from the reference and are unverified against
	# anything. They are here rather than absent because an engine that silently
	# drew nothing for an oval would be indistinguishable from one that had no
	# oval member to draw.
	match kind:
		OVAL:
			_oval(image, fore, filled, line)
		LINE:
			# Direction 5 draws top-left to bottom-right, 6 the other diagonal.
			_line(image, fore, line, int(member.get("line_direction", 5)) != 6)
		ROUNDED_RECTANGLE:
			_rect(image, fore, filled, line, CORNER_RADIUS)
		_:
			_rect(image, fore, filled, line, 0)
	return image


## Filled or outlined rectangle, optionally with rounded corners.
static func _rect(image: Image, colour: Color, filled: bool, line: int, radius: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var r: int = clampi(radius, 0, mini(w, h) / 2)
	for y in h:
		for x in w:
			if r > 0 and not _inside_rounded(x, y, w, h, r):
				continue
			if filled:
				image.set_pixel(x, y, colour)
				continue
			# Outlined: only the `line`-wide band inside the edge.
			if x < line or y < line or x >= w - line or y >= h - line:
				image.set_pixel(x, y, colour)


## Is a pixel inside a rounded rectangle — i.e. not cut off by a corner arc?
static func _inside_rounded(x: int, y: int, w: int, h: int, r: int) -> bool:
	var cx: int = x if x >= r else r
	if x >= w - r:
		cx = w - 1 - r
	var cy: int = y if y >= r else r
	if y >= h - r:
		cy = h - 1 - r
	var dx := x - cx
	var dy := y - cy
	return dx * dx + dy * dy <= r * r


## Ellipse inscribed in the image, filled or as a band of `line` pixels.
static func _oval(image: Image, colour: Color, filled: bool, line: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var rx := w / 2.0
	var ry := h / 2.0
	if rx <= 0.0 or ry <= 0.0:
		return
	for y in h:
		for x in w:
			var nx := (x + 0.5 - rx) / rx
			var ny := (y + 0.5 - ry) / ry
			var d := nx * nx + ny * ny
			if d > 1.0:
				continue
			if filled:
				image.set_pixel(x, y, colour)
				continue
			# The inner edge of the band, expressed in the same normalised space.
			var ix := maxf(rx - line, 0.001)
			var iy := maxf(ry - line, 0.001)
			var inner := pow((x + 0.5 - rx) / ix, 2.0) + pow((y + 0.5 - ry) / iy, 2.0)
			if inner >= 1.0:
				image.set_pixel(x, y, colour)


## A diagonal of `line` thickness across the image's rect.
static func _line(image: Image, colour: Color, line: int, down: bool) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var thickness: int = maxi(line, 1)
	var steps: int = maxi(w, h)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := int(round(t * (w - 1)))
		var y := int(round((t if down else 1.0 - t) * (h - 1)))
		for oy in range(-thickness / 2, thickness / 2 + 1):
			for ox in range(-thickness / 2, thickness / 2 + 1):
				var px := x + ox
				var py := y + oy
				if px >= 0 and py >= 0 and px < w and py < h:
					image.set_pixel(px, py, colour)
