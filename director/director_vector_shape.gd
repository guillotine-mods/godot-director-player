class_name DirectorVectorShape
extends RefCounted
## Director 7's built-in **Vector Shape** Xtra: its payload, and the pixels it
## stands for.
##
## A `vectorShape` cast member is type 15 -- an Xtra -- and until this file the
## engine drew nothing for it. `tools/xtra_members.gd` states the rule that
## justified that: *drawing nothing for an unregistered Xtra is correct
## behaviour, not a missing feature*, because `castmember/xtra.cpp:promote`
## leaves a member whose symbol is not in `xtraCastMemberProtos` as a plain
## `XtraCastMember`, and that inherits a `createWidget` returning `nullptr`.
##
## **That rule is about the reference, and this member is not an unregistered
## Xtra.** `vectorShape` shipped *inside* Director 7 -- it is the authoring
## tool's own vector art, with its own entry in the cast window and its own
## Lingo property surface (`the fillMode of member`, `the vertexList of member`,
## `the strokeWidth of member`) -- so an engine reproducing Director draws it for
## the same reason it draws a shape or a bitmap. ScummVM not having built it is a
## statement about ScummVM's completeness. `AGENTS.md` names the reference as the
## specification for *behaviour*, and `docs/ENGINE_TODO.md` records that
## completeness here is not corpus-driven: a Director feature is in scope because
## Director has it.
##
## The cost of the old rule was visible: `games/piposh-dream/plane2.dir` is
## **26.7% `vectorShape` sprite records**, and its opening scene rendered as two
## sprites on a black stage.
##
## ## The payload
##
## The Xtra envelope (`director_cast.gd`, type-15 arm) hands over an opaque blob.
## For this symbol it is not opaque:
##
##     'FLSH'  uint32 total   uint32 22   ... 164 bytes of header ...
##     <a stream of typed values, to the last byte of the payload>
##
## **The 164 is measured, not assumed.** `tools/vector_shape.gd` re-derives it the
## way it was found: for every member it tries each 4-byte-aligned start offset
## and keeps the ones whose value stream closes *exactly* on the end of the
## payload. Across the 94 members in reach exactly one offset does, and it is 164
## for all 94. A grammar that consumed the wrong number of bytes anywhere inside
## would not land on the final byte, so "it closes" is a real check and not a
## restatement of the parse.
##
## ### The value stream
##
## A tagged serialisation of Lingo values, big-endian throughout. The tags that
## occur, and there are no others in the corpus:
##
##     1   integer      int32
##     2   symbol       either uint32 length + that many ASCII bytes, appending
##                      to a per-payload symbol table, or 0x80000000|index --
##                      a back-reference into it. The three keys below are
##                      spelled once each and referenced thereafter, which is
##                      why a decoder that only handles the literal form reads
##                      the first vertex and then desynchronises.
##     3   float        32-bit IEEE
##     7   list         uint32 count, then that many values
##     8   point        two int32, (y, x) -- see `_point`
##     10  proplist     uint32 count, then that many key/value pairs
##     18  colour       three int32, r/g/b
##
## The stream is, in order: four colours, then one list of per-vertex property
## lists. A vertex carries `#vertex` always, and `#handle1`/`#handle2` when the
## author curved it -- so a polygon and a bezier are the same structure with the
## handle keys absent, and nothing here needs to know which it is looking at.
##
## ### Which colour is which
##
## Not guessed. The four are in stream order `strokeColor`, `fillColor`,
## `endColor`, `backgroundColor`, and the evidence is `plane2.dir`'s own scene:
## the members the opening frame places carry fills of rgb(102,153,153),
## rgb(153,153,204), rgb(238,238,238), rgb(187,187,187) and rgb(0,85,0) --
## a teal-grey sky, a blue-grey horizon, two near-white cloud banks and dark
## green foliage, which is a painted scene. Slot 1 is rgb(0,0,0) on **every**
## member in the corpus, which is what a stroke default looks like and not what a
## fill palette looks like; slot 4 is a single constant across each authoring
## session (rgb(102,51,51) for that scene's members, the rgb(255,0,0) default for
## the rest), which is what a background swatch looks like. And on the three
## members with `fill_mode == GRADIENT`, slot 2 is rgb(238,0,0) and slot 3 is
## rgb(255,255,255): a red-to-white ramp, with the ramp's ends in the two slots
## this reading calls `fillColor` and `endColor`.
##
## ## What is deliberately not implemented
##
## `fillCycles`, `fillDirection`, `fillOffset`, `fillScale` and the choice
## between a linear and a radial ramp all live in the header's constant fields in
## this corpus -- 100.0, 100.0, 1.0 and so on, identical across all 94 members --
## so there is no reading of them that any file here could tell apart from any
## other. They are named in `HEADER` below and left unread rather than
## implemented against a constant, which would be a guess wearing a citation.
## `gradient_is_radial` is the one exception and it defaults false; the three
## gradient members render as a linear ramp down the shape's own box.

## Byte offsets into the 164-byte header. Everything not named here is constant
## across all 94 members in reach and therefore carries no information this
## corpus can read.
##
## **The pairs are (y, x) and (height, width)**, which is Director's rect order
## -- `top, left, bottom, right` -- and not a transcription error. The witness is
## outside this file: `director_cast.gd:_apply_xtra_rect` reads the member's size
## from item 12 of the *info* block, a different part of the container written by
## a different part of the authoring tool, and it reports `plane2.dir`'s member
## 186 as 514x113 with its registration point at (257, 56). This header stores
## 113 at +36, 514 at +40, 56 at +20 and 257 at +24. Reading them in the other
## order would transpose every member in the corpus against the info block.
const MAGIC := "FLSH"
const HEADER_BYTES := 164
const OFF_TOTAL := 4
const OFF_VERSION := 8
const OFF_REG_Y := 20
const OFF_REG_X := 24
const OFF_HEIGHT := 36
const OFF_WIDTH := 40
const OFF_STROKE_WIDTH := 132
const OFF_FILL_MODE := 136
const OFF_CLOSED := 140

## `the fillMode of member`, in the header's own encoding.
enum { FILL_NONE = 0, FILL_SOLID = 1, FILL_GRADIENT = 2 }

## Value-stream tags. See the class comment for how they were established.
const TAG_INT := 1
const TAG_SYMBOL := 2
const TAG_FLOAT := 3
const TAG_LIST := 7
const TAG_POINT := 8
const TAG_PROPLIST := 10
const TAG_COLOUR := 18

## A back-referenced symbol has the top bit of its length word set; the rest is
## an index into the symbols this payload has already spelled out.
const SYMBOL_REF := 0x80000000

## How finely a curved segment is flattened. Director rasterises the bezier
## itself and the step count it used is not in the file, so this is a rendering
## choice rather than a decoded one: 16 keeps a full-stage 670x301 member's
## longest segment under a pixel of chord error, and the cost is linear in a
## count that is never large.
const CURVE_STEPS := 16


# --------------------------------------------------------------------- decode

## The shape a payload describes, or an empty dictionary if these bytes are not
## one. Never raises: a member whose payload this does not understand must draw
## nothing, exactly as it did before, rather than take the movie down.
##
## Keys: `width`, `height`, `reg` (Vector2 -- the member's registration point,
## which places the *sprite* and not the path; see `flatten`), `closed` (bool),
## `fill_mode`,
## `stroke_width` (float), `stroke`, `fill`, `end_colour`, `background` (Color),
## and `vertices` -- an array of `{"at": Vector2, "in": Vector2, "out": Vector2}`
## where the two handles are **relative to their own vertex** and are zero when
## the author left the point square.
static func decode(payload: PackedByteArray) -> Dictionary:
	if payload.size() < HEADER_BYTES + 4:
		return {}
	if payload.slice(0, 4).get_string_from_ascii() != MAGIC:
		return {}

	var out := {
		"width": _u32(payload, OFF_WIDTH),
		"height": _u32(payload, OFF_HEIGHT),
		"reg": Vector2(_u32(payload, OFF_REG_X), _u32(payload, OFF_REG_Y)),
		"closed": _u32(payload, OFF_CLOSED) != 0,
		"fill_mode": _u32(payload, OFF_FILL_MODE),
		"stroke_width": _f32(payload, OFF_STROKE_WIDTH),
		"stroke": Color.BLACK,
		"fill": Color.WHITE,
		"end_colour": Color.WHITE,
		"background": Color.WHITE,
		"vertices": [],
	}
	if int(out["width"]) <= 0 or int(out["height"]) <= 0:
		return {}

	# The stream is read positionally -- four colours then one list -- rather
	# than by hunting for the list, because a payload whose shape differs from
	# that is one this reading does not understand and should decline whole.
	var cursor := {"at": HEADER_BYTES, "symbols": PackedStringArray(), "bad": false}
	var colours: Array[Color] = []
	for i in 4:
		var v: Variant = _value(payload, cursor)
		if cursor["bad"] or not (v is Color):
			return {}
		colours.append(v)
	out["stroke"] = colours[0]
	out["fill"] = colours[1]
	out["end_colour"] = colours[2]
	out["background"] = colours[3]

	var list: Variant = _value(payload, cursor)
	if cursor["bad"] or not (list is Array):
		return {}
	for entry in (list as Array):
		if not (entry is Dictionary):
			return {}
		var e: Dictionary = entry
		if not e.has("vertex"):
			return {}
		out["vertices"].append({
			"at": e["vertex"],
			"in": e.get("handle1", Vector2.ZERO),
			"out": e.get("handle2", Vector2.ZERO),
		})
	if (out["vertices"] as Array).is_empty():
		return {}
	return out


## One value at `cursor.at`, advancing it. Sets `cursor.bad` rather than raising,
## so a payload that goes wrong half way through declines the whole member.
static func _value(d: PackedByteArray, cursor: Dictionary) -> Variant:
	var at := int(cursor["at"])
	if at + 4 > d.size():
		cursor["bad"] = true
		return null
	var tag := _u32(d, at)
	at += 4
	match tag:
		TAG_INT:
			if at + 4 > d.size():
				cursor["bad"] = true
				return null
			cursor["at"] = at + 4
			return _i32(d, at)
		TAG_FLOAT:
			if at + 4 > d.size():
				cursor["bad"] = true
				return null
			cursor["at"] = at + 4
			return _f32(d, at)
		TAG_SYMBOL:
			return _symbol(d, cursor, at)
		TAG_POINT:
			if at + 8 > d.size():
				cursor["bad"] = true
				return null
			cursor["at"] = at + 8
			return _point(d, at)
		TAG_COLOUR:
			if at + 12 > d.size():
				cursor["bad"] = true
				return null
			cursor["at"] = at + 12
			return Color8(
				clampi(_i32(d, at), 0, 255),
				clampi(_i32(d, at + 4), 0, 255),
				clampi(_i32(d, at + 8), 0, 255))
		TAG_LIST:
			if at + 4 > d.size():
				cursor["bad"] = true
				return null
			var count := _u32(d, at)
			cursor["at"] = at + 4
			var items: Array = []
			for i in count:
				var v: Variant = _value(d, cursor)
				if cursor["bad"]:
					return null
				items.append(v)
			return items
		TAG_PROPLIST:
			if at + 4 > d.size():
				cursor["bad"] = true
				return null
			var pairs := _u32(d, at)
			cursor["at"] = at + 4
			var props := {}
			for i in pairs:
				var k: Variant = _value(d, cursor)
				if cursor["bad"]:
					return null
				var v: Variant = _value(d, cursor)
				if cursor["bad"]:
					return null
				props[str(k)] = v
			return props
	cursor["bad"] = true
	return null


## A symbol, spelled out or referred back to.
##
## **The back-reference is the half a first attempt gets wrong.** `#vertex`,
## `#handle1` and `#handle2` are written in full for the first vertex and as
## `0x80000000|index` for every one after it, so a decoder that only handles the
## literal form reads vertex 1 correctly, then treats a 4-byte reference as a
## length, walks off into the point data and returns a shape with one vertex.
static func _symbol(d: PackedByteArray, cursor: Dictionary, at: int) -> Variant:
	if at + 4 > d.size():
		cursor["bad"] = true
		return null
	var n := _u32(d, at)
	var table: PackedStringArray = cursor["symbols"]
	if n >= SYMBOL_REF:
		var idx := int(n & ~SYMBOL_REF)
		if idx >= table.size():
			cursor["bad"] = true
			return null
		cursor["at"] = at + 4
		return table[idx]
	if at + 4 + n > d.size():
		cursor["bad"] = true
		return null
	var s := d.slice(at + 4, at + 4 + n).get_string_from_ascii()
	table.append(s)
	cursor["symbols"] = table
	cursor["at"] = at + 4 + n
	return s


## A point's two int32, **(y, x)** -- the same order as the header's pairs, and
## the same order as Director's `top, left, bottom, right` rect.
##
## **A square member cannot tell you this and every one of them was checked
## first.** `plane2.dir`'s member 88 is 25x25 and reads identically either way.
## The witness has to be a member that is not square, and member 186 is 514 wide
## by 113 tall: read (y, x) its path spans 1..513 across the 514 axis and 0..111
## down the 113 axis, filling its own box on both. Read (x, y) the same numbers
## describe a shape 111 wide and 512 tall -- a 514-wide box holding a 512-tall
## picture, transposed. The first render of `plane2.dir` made exactly that
## mistake and the scene came out as tall green columns lying across the stage.
static func _point(d: PackedByteArray, at: int) -> Vector2:
	return Vector2(_i32(d, at + 4), _i32(d, at))


# ------------------------------------------------------------------ rasterise

## The shape's pixels, at its own size, premultiplied against nothing -- a
## straight RGBA image with transparent where the shape is not.
##
## The member is drawn into its own box with the registration point as the
## origin, which is what puts a vertex list centred on (0,0) in the middle of the
## box. `sprite_art.gd` then places that image exactly as it places a bitmap's,
## so registration, ink, flip, stretch and hit testing all keep working without
## knowing this member type exists.
static func rasterise(shape: Dictionary) -> Image:
	var w := int(shape.get("width", 0))
	var h := int(shape.get("height", 0))
	if w <= 0 or h <= 0 or w > 4096 or h > 4096:
		return null
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var path := flatten(shape)
	if path.size() < 2:
		return img

	var mode := int(shape.get("fill_mode", FILL_NONE))
	if mode != FILL_NONE and path.size() >= 3:
		_fill(img, path, shape, mode)
	var width: float = maxf(float(shape.get("stroke_width", 1.0)), 0.0)
	if width > 0.0:
		_stroke(img, path, shape.get("stroke", Color.BLACK), width,
			bool(shape.get("closed", false)))
	return img


## The vertex list as a polyline in image space: beziers flattened, handles
## applied, and the path placed in the member's own box.
##
## Director's two handles are stored **relative to their own vertex**, and a
## segment's curve is the cubic through `v[i] + v[i].out` and
## `v[i+1] + v[i+1].in`. A segment where both are zero is a straight line, which
## is why a polygon needs no separate path here.
##
## **The path is placed by the centre of the box, not by the registration
## point**, and the two are not the same thing. Every stored vertex list in the
## corpus is centred on the origin and spans exactly `width - 2` by
## `height - 2` -- the stroke's own half-width inset on each side -- so the
## centre is where it belongs. The registration point is usually near the centre
## too, which is what makes using it look right: `plane2.dir` chunk 710 is
## 514x113 with its registration at (257, 56), and the centre is (257, 56.5).
## But the author is free to drag it, and eight members here have: chunk 229 is
## 248x234 with its registration at (191, 60) against a centre of (124, 117), and
## placed by the registration point its path hangs 56px above the box and 66px
## past the right edge. `tools/vector_shape.gd` asserts the whole corpus fits.
##
## The registration point is not unused -- it is what puts the sprite's `loc` at
## the right spot inside the picture, exactly as it does for a bitmap, and
## `director_cast.gd:_apply_xtra_rect` has been feeding it to the sprite geometry
## all along. It belongs to placing the member on the stage, not to placing the
## path inside the member.
static func flatten(shape: Dictionary) -> PackedVector2Array:
	var verts: Array = shape.get("vertices", [])
	var reg := Vector2(float(shape.get("width", 0)), float(shape.get("height", 0))) * 0.5
	var closed := bool(shape.get("closed", false))
	var out := PackedVector2Array()
	if verts.is_empty():
		return out
	var n := verts.size()
	var last := n if closed else n - 1
	out.append((verts[0]["at"] as Vector2) + reg)
	for i in last:
		var a: Dictionary = verts[i]
		var b: Dictionary = verts[(i + 1) % n]
		var p0: Vector2 = (a["at"] as Vector2) + reg
		var p3: Vector2 = (b["at"] as Vector2) + reg
		var c1: Vector2 = p0 + (a["out"] as Vector2)
		var c2: Vector2 = p3 + (b["in"] as Vector2)
		if c1.is_equal_approx(p0) and c2.is_equal_approx(p3):
			out.append(p3)
			continue
		for s in range(1, CURVE_STEPS + 1):
			var t := float(s) / float(CURVE_STEPS)
			out.append(p0.bezier_interpolate(c1, c2, p3, t))
	return out


## Scanline fill, even-odd, sampled at the pixel centre.
##
## Even-odd rather than non-zero because Director's vector shape has no winding
## control in its property surface -- there is no `the fillRule of member` -- and
## a self-intersecting path authored in the tool shows its holes.
static func _fill(img: Image, path: PackedVector2Array, shape: Dictionary,
		mode: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var fill: Color = shape.get("fill", Color.WHITE)
	var to: Color = shape.get("end_colour", fill)
	var gradient := mode == FILL_GRADIENT

	# The ramp runs down the shape's own box. `fillDirection` would turn it and
	# is constant across the corpus, so there is nothing here to read it from.
	var span := maxf(float(h - 1), 1.0)
	var n := path.size()
	var xs := PackedFloat32Array()
	for y in h:
		var scan := float(y) + 0.5
		xs.clear()
		for i in n:
			var a := path[i]
			var b := path[(i + 1) % n]
			if a.y == b.y:
				continue
			var lo := minf(a.y, b.y)
			var hi := maxf(a.y, b.y)
			if scan < lo or scan >= hi:
				continue
			xs.append(a.x + (scan - a.y) / (b.y - a.y) * (b.x - a.x))
		if xs.size() < 2:
			continue
		var sorted := Array(xs)
		sorted.sort()
		var colour := fill
		if gradient:
			colour = fill.lerp(to, float(y) / span)
		var k := 0
		while k + 1 < sorted.size():
			var x0 := int(ceil(float(sorted[k]) - 0.5))
			var x1 := int(floor(float(sorted[k + 1]) - 0.5))
			for x in range(maxi(x0, 0), mini(x1 + 1, w)):
				img.set_pixel(x, y, colour)
			k += 2


## The outline, as a run of thick segments.
static func _stroke(img: Image, path: PackedVector2Array, colour: Color,
		width: float, closed: bool) -> void:
	var n := path.size()
	var last := n if closed else n - 1
	for i in last:
		_segment(img, path[i], path[(i + 1) % n], colour, width)


## One thick segment, stamped as a disc swept along the line.
##
## A disc rather than a quad because Director's strokes join and cap round, and
## at the widths this corpus uses -- 1.0 on every member -- the two agree on
## every pixel anyway. The disc is what keeps a wider stroke from splitting at a
## sharp corner of a polygon.
static func _segment(img: Image, a: Vector2, b: Vector2, colour: Color,
		width: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var radius := maxf(width, 1.0) * 0.5
	var steps := maxi(int(ceil(a.distance_to(b))), 1)
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		var x0 := int(floor(p.x - radius))
		var x1 := int(ceil(p.x + radius))
		var y0 := int(floor(p.y - radius))
		var y1 := int(ceil(p.y + radius))
		for y in range(maxi(y0, 0), mini(y1 + 1, h)):
			for x in range(maxi(x0, 0), mini(x1 + 1, w)):
				if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(p) <= radius:
					img.set_pixel(x, y, colour)


# ---------------------------------------------------------------------- bytes

static func _u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


static func _i32(d: PackedByteArray, o: int) -> int:
	var v := _u32(d, o)
	return v - 0x100000000 if v >= 0x80000000 else v


## Big-endian IEEE 754 single. `PackedByteArray.decode_float` is little-endian
## and there is no big-endian variant, so the four bytes are reversed into a
## scratch array rather than reassembled by hand.
static func _f32(d: PackedByteArray, o: int) -> float:
	var b := PackedByteArray([d[o + 3], d[o + 2], d[o + 1], d[o]])
	return b.decode_float(0)
