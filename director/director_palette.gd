class_name DirectorPalette
extends RefCounted
## Director's built-in palettes, as flat RGB8 tables of 3 bytes per entry.
##
## A cast member names its palette in the `CASt` specific block. This game ships
## no `CLUT` chunk and no palette cast member — every bitmap carries clut id 0,
## which is the system Mac palette — so the built-in table is the only one any
## member here can reach. A `CLUT` reader belongs behind `builtin()` when a title
## needs one; nothing in this one can get there.
##
## The table is generated rather than embedded because its structure is the
## thing worth stating: a 6x6x6 colour cube in *descending* order, then four
## ramps, then black. Assuming the cube alone put black at 215 and painted every
## repaired cursor red, so `index_of_black` looks the value up and fails loudly
## rather than trusting the shape.

const SYSTEM_MAC := -1
## Paper. Both ink passes key this index out, and it must be exactly white.
const PAPER_INDEX := 0
const INK_INDEX := 255
## The 6x6x6 cube occupies the first 215 entries.
const CUBE_SIZE := 215
## The greys and primaries that follow the cube, in the order Director stores.
const RAMP_VALUES := [238, 221, 187, 170, 136, 119, 85, 68, 34, 17]


## The palette a member's clut id names. Anything other than a built-in falls
## back to system Mac with a warning: a wrong palette is visible, a missing one
## is a crash, and this corpus can produce neither.
static func builtin(clut_id: int) -> PackedByteArray:
	if clut_id > 0:
		push_warning("custom palette %d requested; no CLUT reader exists" % clut_id)
	return system_mac()


static func system_mac() -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(768)
	for i in CUBE_SIZE:
		# Descending, so entry 0 is white rather than black.
		table[i * 3] = 255 - 51 * (i / 36)
		table[i * 3 + 1] = 255 - 51 * ((i / 6) % 6)
		table[i * 3 + 2] = 255 - 51 * (i % 6)
	var at := CUBE_SIZE
	# Four ramps: reds, greens, blues, then greys.
	for channel in 4:
		for value in RAMP_VALUES:
			# Typed explicitly: `value` comes out of an untyped constant array,
			# so `:=` over a ternary has nothing to infer from and the file will
			# not compile.
			var r: int = value if channel == 0 or channel == 3 else 0
			var g: int = value if channel == 1 or channel == 3 else 0
			var b: int = value if channel == 2 or channel == 3 else 0
			table[at * 3] = r
			table[at * 3 + 1] = g
			table[at * 3 + 2] = b
			at += 1
	# 255: black, the one entry the ramps do not reach.
	table[255 * 3] = 0
	table[255 * 3 + 1] = 0
	table[255 * 3 + 2] = 0
	return table


## The index that is exactly white, or -1. Looked up rather than assumed.
static func index_of_white(table: PackedByteArray) -> int:
	return _index_of(table, 255, 255, 255)


static func index_of_black(table: PackedByteArray) -> int:
	return _index_of(table, 0, 0, 0)


## Indices whose every channel is at or above `threshold`. Both ink passes treat
## these as paper, so a palette with more than one is a palette that would key
## out artwork.
static func indices_at_least(table: PackedByteArray, threshold: int) -> Array[int]:
	var out: Array[int] = []
	for i in 256:
		if table[i * 3] >= threshold and table[i * 3 + 1] >= threshold \
				and table[i * 3 + 2] >= threshold:
			out.append(i)
	return out


static func _index_of(table: PackedByteArray, r: int, g: int, b: int) -> int:
	for i in 256:
		if table[i * 3] == r and table[i * 3 + 1] == g and table[i * 3 + 2] == b:
			return i
	return -1
