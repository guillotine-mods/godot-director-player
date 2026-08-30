extends SceneTree
## `vectorShape` Xtra members: that the payload decodes, and that what comes out
## is the shape the container independently says it should be.
##
##   godot --headless --path . --script tools/vector_shape.gd -- --root piposh-dream
##   godot --headless --path . --script tools/vector_shape.gd -- --all
##
## `director/director_vector_shape.gd` carries the format and the argument for
## why this member type is drawn at all. This is the evidence.
##
## ## The check that matters is not "it parsed"
##
## A decoder can always parse something. Two properties here are falsifiable
## against data the decoder never touches:
##
## 1. **The value stream closes exactly on the last byte of the payload.** The
##    header is a fixed 164 bytes and everything after it is a self-describing
##    run of typed values. A grammar that mis-sized any one value -- a symbol
##    back-reference read as a length, a point read as two values, a proplist
##    counted in entries where it is counted in pairs -- lands somewhere other
##    than the end. It is the same self-check the Xtra envelope itself gets in
##    `tools/xtra_members.gd`.
##
## 2. **Every path fits the box its own header states**, and **that header
##    agrees with the info block**. The second half is what makes the first mean
##    something. This decoder takes the box from the payload header at +36/+40;
##    `director_cast.gd:_apply_xtra_rect` takes it from item 12 of the *info*
##    block, a different region of the chunk written by a different part of the
##    authoring tool and read by code that never sees this payload. Checking the
##    path against the header alone would be checking a payload against itself.
##
## **Property 2 is what caught the real bug and property 1 did not.** The points
## are stored (y, x), the same order as Director's `top, left, bottom, right`
## rects, and the first implementation read them (x, y). Every payload still
## parsed and every stream still closed on its last byte, because the byte
## layout is identical either way. What it did was transpose every non-square
## member: `plane2.dir` member 186 is a 514-wide, 113-tall panel, and read the
## wrong way its path is 111 wide and 512 tall. On the stage that came out as
## green columns lying across the scene. Only the box comparison sees it, and
## only on the members that are not square -- which is why the square ones are
## counted and reported below rather than being allowed to pad the result.
##
## It caught a second one the same way. The path is placed by the **centre** of
## the box and not by the registration point, and the first implementation used
## the registration point. That is right for the 86 members whose author left it
## near the centre and wrong for the eight who dragged it: chunk 229 is 248x234
## with its registration at (191, 60) against a centre of (124, 117), and it hung
## its path 56px above the box and 66px past its right edge. 26 of 94 failed, and
## every one was one of those eight repeated across movies that share a cast.
##
## ## The stage colour rides along
##
## Not a separate harness because it was the same bug report and the same movies
## settle it. `piposh-dream`'s three flying levels are the only containers in the
## title whose stage colour is neither black nor white, and they are the three
## where the player flies through the sky. `director_config.gd:_read_stage_colour`
## carries the reference citation; this asserts the numbers.
##
## Title-agnostic. A root with no `vectorShape` member says so and asserts
## nothing about one, rather than asserting over an empty set.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Paths := preload("res://director/director_paths.gd")
const Config := preload("res://director/director_config.gd")
const Cast := preload("res://director/director_cast.gd")
const VectorShape := preload("res://director/director_vector_shape.gd")

## Type code 15, the Xtra member. Spelled here rather than imported so this tool
## does not depend on the renderer's constants to find its own subjects.
const TYPE_XTRA := 15
const SYMBOL := "vectorshape"

## How far outside its own box a path may land before it counts as disagreeing.
##
## Not zero, and the slack is the stroke's. Director centres a stroke on the
## path, so a shape authored flush to the edge of its box puts half the stroke
## width outside it, and every member in this corpus states a stroke width of 1.
## Two pixels is that, doubled, so a member that is merely drawn tight cannot
## fail while a transposed one -- off by hundreds -- cannot pass.
const BOX_SLACK := 2.0

## The three movies whose stage colour this asserts, and what the config states.
## Written out rather than derived: a check that recomputed the expected value
## from the same bytes it is checking would assert nothing.
const STAGE_COLOURS := {
	"plane1.dir": Color8(102, 204, 255),
	"plane2.dir": Color8(204, 204, 204),
	"plane3.dir": Color8(153, 204, 255),
}


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		h.check("a corpus is configured", false, paths.error)
		quit(h.finish("vectorShape members"))
		return

	var verbose := Args.flag(args, "verbose")
	var total := 0
	var decoded := 0
	var square := 0
	var oblong := 0
	var closes: Array[String] = []
	var outside: Array[String] = []
	var disagree: Array[String] = []
	var boxes := 0
	var stage_seen := {}

	for name in paths.containers():
		var path = paths.resolve(name)
		var cf := ContainerFile.new()
		if not cf.open(path):
			continue
		_collect_stage_colour(cf, name, stage_seen)
		# The independent witness: the same members read through the cast parser,
		# whose size comes from the info block and not from this payload.
		var info_box := {}
		var cast := Cast.new()
		if cast.open(cf):
			for number in cast.member_numbers():
				var m: Dictionary = cast.member(number)
				if int(m.get("type", 0)) != TYPE_XTRA:
					continue
				if str(m.get("xtra_symbol", "")).to_lower() != SYMBOL:
					continue
				info_box[int(m.get("cast_chunk_id", -1))] = Vector2i(
					int(m.get("width", 0)), int(m.get("height", 0)))
		for id in cf.ids_of("CASt"):
			var payload := _vector_payload(cf.read_chunk(id))
			if payload.is_empty():
				continue
			total += 1
			var shape := VectorShape.decode(payload)
			if shape.is_empty():
				closes.append("%s chunk %d: payload did not decode (%d bytes)"
					% [name, id, payload.size()])
				continue
			decoded += 1
			var w := float(shape["width"])
			var hh := float(shape["height"])
			if is_equal_approx(w, hh):
				square += 1
			else:
				oblong += 1
			# A member carrying no info rect keeps 0x0 there -- 3 of this title's
			# 97 Xtras -- which is real data rather than a disagreement, so it is
			# skipped and the comparable ones are counted.
			if info_box.has(id) and info_box[id] != Vector2i.ZERO:
				boxes += 1
				var want: Vector2i = info_box[id]
				var got := Vector2i(int(w), int(hh))
				if got != want:
					disagree.append("%s chunk %d: header says %s, info block says %s"
						% [name, id, str(got), str(want)])
			var slip := _outside_box(shape)
			if slip > BOX_SLACK:
				outside.append("%s chunk %d: %dx%d, path %.1fpx outside its box"
					% [name, id, int(w), int(hh), slip])
			elif verbose:
				print("  %s chunk %d: %dx%d %s verts=%d"
					% [name, id, int(w), int(hh),
					   "closed" if shape["closed"] else "open",
					   (shape["vertices"] as Array).size()])
		cf.close()

	if total == 0:
		# The `video_fallback` shape: say the fixture is absent and assert
		# nothing about it.
		print("no vectorShape member in %s; nothing to assert about one"
			% paths.root)
	else:
		h.check("every vectorShape payload decodes", closes.is_empty(),
			"%d of %d did not: %s" % [closes.size(), total, "; ".join(closes)])
		# The property that catches a transposition, and the count that says the
		# corpus can actually exercise it.
		h.check("the payload header's box agrees with the info block's",
			disagree.is_empty(),
			"%d of %d disagree: %s" % [disagree.size(), boxes, "; ".join(disagree)])
		h.check("and enough members carry an info rect to compare against",
			boxes > 0, "%d carried one" % boxes)
		h.check("every path fits the box its header states",
			outside.is_empty(),
			"%d of %d outside: %s" % [outside.size(), decoded, "; ".join(outside)])
		h.check("and enough of them are not square for that to mean something",
			oblong > 0,
			"%d oblong, %d square -- a square member reads the same either way"
				% [oblong, square])
		print("vectorShape: %d member(s), %d decoded, %d oblong, %d square"
			% [total, decoded, oblong, square])

	# The stage colour, on whichever of the three movies this root holds.
	var checked := 0
	for movie in STAGE_COLOURS:
		if not stage_seen.has(movie):
			continue
		checked += 1
		var got: Color = stage_seen[movie]
		h.check("%s states its own stage colour" % movie,
			got.is_equal_approx(STAGE_COLOURS[movie]),
			"read %s, expected %s" % [got.to_html(false),
				(STAGE_COLOURS[movie] as Color).to_html(false)])
	if checked == 0:
		print("none of the three flying levels is in this root; stage colour not asserted")

	quit(h.finish("vectorShape members and the stage colour they need"))


## The `vectorShape` payload inside a `CASt` chunk, or empty when this chunk is
## not one. The envelope is `director_cast.gd`'s and is re-walked here rather
## than imported, so a change that broke the cast parser could not make this
## harness quietly agree with it.
static func _vector_payload(d: PackedByteArray) -> PackedByteArray:
	if d.size() < 12 or _u32(d, 0) != TYPE_XTRA:
		return PackedByteArray()
	var at := 12 + _u32(d, 4)
	if at + 8 > d.size():
		return PackedByteArray()
	var symbol_len := _u32(d, at)
	if at + 8 + symbol_len > d.size():
		return PackedByteArray()
	if d.slice(at + 4, at + 4 + symbol_len).get_string_from_ascii().to_lower() != SYMBOL:
		return PackedByteArray()
	var data_len := _u32(d, at + 4 + symbol_len)
	return d.slice(at + 8 + symbol_len,
		mini(at + 8 + symbol_len + data_len, d.size()))


## How far the flattened path escapes the member's own box, in pixels. Zero when
## it is wholly inside.
static func _outside_box(shape: Dictionary) -> float:
	var pts: PackedVector2Array = VectorShape.flatten(shape)
	if pts.is_empty():
		return 0.0
	var w := float(shape["width"])
	var h := float(shape["height"])
	var worst := 0.0
	for p in pts:
		worst = maxf(worst, -p.x)
		worst = maxf(worst, -p.y)
		worst = maxf(worst, p.x - w)
		worst = maxf(worst, p.y - h)
	return worst


func _collect_stage_colour(cf, name: String, into: Dictionary) -> void:
	if not STAGE_COLOURS.has(name.get_file()):
		return
	for tag in ["DRCF", "VWCF"]:
		for id in cf.ids_of(tag):
			var config = Config.new()
			if not config.parse(cf.read_chunk(id)):
				continue
			if config.stage_colour_is_rgb:
				into[name.get_file()] = config.stage_colour
			return


static func _u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]
