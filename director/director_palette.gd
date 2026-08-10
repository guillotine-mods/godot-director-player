class_name DirectorPalette
extends RefCounted
## Palettes: the built-in tables, the `CLUT` reader, and the transforms cycling
## and fading are made of. Flat RGB8, 3 bytes per entry, 256 entries.
##
## `DIRECTOR_ENGINE.md` §11. The state machine that decides *which* palette is
## current, and when, is `director/director_palette_state.gd`; everything here is
## pure and static so it can be asserted without a movie
## (`tools/palette_cycle.gd`).
##
## **What the corpus exercises, and therefore what is verified.** The six shipped
## titles exercise none of it: `tools/palette_survey.gd` over Piposh 2's 86
## containers, 61,371 frames and 11,520 bitmap members counts **0** `CLUT`
## chunks, **0** palette cast members, **0** members naming a palette other than
## system Mac, **0** frames naming one, and the string "palette" appears **0**
## times in `reference/lingo/`. That was read, for a long time, as "custom
## palettes are unexercised, so the code for them is written from the reference
## and unverified" — an honest statement that was also **hiding two defects**,
## because a corpus that names one palette cannot tell a right reader from a
## wrong one.
##
## `test-games/itamar-park` names plenty and both defects fell out at once: 162
## `CLUT` chunks, 145 palette cast members, 655 of 657 bitmaps naming one of
## them, and every table read upside down (`from_clut`) off a field read from the
## wrong offset (`director_cast.gd:_parse_clut`). `tools/palette_members.gd` is
## the harness that now stands between those and the next reader.
##
## The built-in tables below are still written from the reference and
## **unverified**, which is a different thing from absent.
##
## The system Mac table is generated rather than embedded because its structure
## is the thing worth stating: a 6x6x6 colour cube in *descending* order, then
## four ramps, then black. Assuming the cube alone put black at 215 and painted
## every repaired cursor red, so `index_of_black` looks the value up and fails
## loudly rather than trusting the shape.
##
## **The tables that are data, not structure.** Rainbow, Pastels, Vivid, NTSC,
## Metallic and both Windows system palettes are hand-authored 768-byte tables
## with no generating rule to recover — there is nothing to derive them *from*, and inventing plausible ones
## would put wrong colours on screen while claiming to be Director's. So they are
## loaded from `data/director_palettes.json` when a title needs them, and
## `builtin()` says so out loud when the file has no entry. Supplying one is a
## data task, not an engine task: 768 bytes per id, and `PALETTE_DATA` documents
## the format. The dispatch, the resolution order, the cycling and the fades are
## all built and do not wait on it. Two titles in this tree now do -- `bugs.md`
## 77.

## Director numbers built-in palettes negatively and a custom one by its palette
## member number, so the sign is the branch. From the reference. Only SYSTEM_MAC
## occurs in the six shipped titles; the test corpora also name GRAYSCALE and
## SYSTEM_WIN_D5, and everything reaching those ids comes through the *offset*
## form Director stores — see `director_cast.gd:_parse_clut` and
## `director_config.gd:_read_default_palette`, which both apply it.
const SYSTEM_MAC := -1
const RAINBOW := -2
const GRAYSCALE := -3
const PASTELS := -4
const VIVID := -5
const NTSC := -6
const METALLIC := -7
const VGA := -8
## **These two were named the wrong way round.** The reference numbers the plain
## Windows system palette -101 and the Director 5 one -102; this file had the
## names swapped, so every warning about a missing table named the other table.
## Nothing depended on the constants — no caller used either — but the strings
## are what a reader would have believed.
const SYSTEM_WIN := -101
const SYSTEM_WIN_D5 := -102

const BUILTIN_NAMES := {
	-1: "System - Mac", -2: "Rainbow", -3: "Grayscale", -4: "Pastels",
	-5: "Vivid", -6: "NTSC", -7: "Metallic", -8: "VGA",
	-101: "System - Win", -102: "System - Win (D5)",
}

## The `CASt` type code of a palette member, whose payload chunk is its `CLUT`.
const MEMBER_TYPE := 4
## Paper. Both ink passes key this index out, and it must be exactly white.
const PAPER_INDEX := 0
const INK_INDEX := 255
## The 6x6x6 cube occupies the first 215 entries.
const CUBE_SIZE := 215
## The greys and primaries that follow the cube, in the order Director stores.
const RAMP_VALUES := [238, 221, 187, 170, 136, 119, 85, 68, 34, 17]
const ENTRIES := 256
const TABLE_BYTES := 768

## Where a title supplies the built-in tables this file cannot derive.
##
## **A title in this tree now needs it.** `itamar-magichat` states the Windows D5
## system palette (-102) as the default of 16 of its movies and on 881 of its
## 1,054 bitmap members, `itamar-park` on two movies and one member, and
## `piposh-en` / `piposh-ru` / `piposh-dream` on 244 members between them. All of
## those draw against a substituted system Mac table today, which is visibly
## wrong colour and is the largest remaining palette gap; `bugs.md` 77 carries it.
##
## Optional, and absent in this tree. Format is `{"<id>": "<hex>"}` where the id
## is the negative built-in number as a string and the hex is 1536 characters —
## 768 bytes, RGB8, entry 0 first. Lift them from a Director installation or from
## an implementation that carries them; do not reconstruct them by eye, because a
## palette that is nearly right is indistinguishable from artwork that is nearly
## right and the two get confused for weeks.
const PALETTE_DATA := "res://data/director_palettes.json"

## Loaded once. Empty when the file is absent, which is the normal state here.
static var _external: Dictionary = {}
static var _external_loaded := false


## The palette an id names, always a usable 768-byte table.
##
## Order: 0 means "none named" and resolves to the movie default, which is system
## Mac; a negative id is a built-in; a positive id is a palette cast member and
## belongs to `from_clut` rather than here, because only the caller can find the
## member's chunk. Anything this file cannot produce falls back to system Mac
## **with a warning naming the id** — a wrong palette is visible, a missing one
## is a crash, and silence about the difference is what makes it unfindable.
static func builtin(clut_id: int) -> PackedByteArray:
	match clut_id:
		0, SYSTEM_MAC:
			return system_mac()
		GRAYSCALE:
			return grayscale()
	var external := _external_table(clut_id)
	if not external.is_empty():
		return external
	if clut_id > 0:
		push_warning(
			"palette member %d asked of builtin(); read its CLUT chunk with from_clut()"
			% clut_id
		)
	else:
		push_warning(
			"built-in palette %d (%s) has no table: add it to %s (see PALETTE_DATA)"
			% [clut_id, str(BUILTIN_NAMES.get(clut_id, "unknown")), PALETTE_DATA]
		)
	return system_mac()


## True when `builtin()` can answer this id with the palette it actually names,
## rather than with the system Mac fallback. Lets a caller — or a survey — tell
## "resolved" from "substituted" without reading warnings out of a log.
static func can_build(clut_id: int) -> bool:
	if clut_id == 0 or clut_id == SYSTEM_MAC or clut_id == GRAYSCALE:
		return true
	return not _external_table(clut_id).is_empty()


static func system_mac() -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(TABLE_BYTES)
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


## A linear white-to-black ramp, entry 0 white, following the same descending
## convention as system Mac.
##
## Derived rather than lifted, and that is the one thing to know about it: the
## palette is a grey ramp by definition, so the *shape* is not in doubt, but
## whether Director's own table is exactly `255 - i` on every entry or is
## gamma-shaped somewhere in the middle has not been checked against Director.
## Unverified against this corpus, which never names it.
static func grayscale() -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(TABLE_BYTES)
	for i in ENTRIES:
		var v := 255 - i
		table[i * 3] = v
		table[i * 3 + 1] = v
		table[i * 3 + 2] = v
	return table


## A palette cast member's `CLUT` chunk.
##
## Six bytes per entry — three 16-bit Mac `RGBColor` channels, of which the high
## byte is the 8-bit value — **stored entry 0 first**, in the ordinary direction.
##
## **This used to fill backwards**, on the theory that the chunk stored the last
## entry first and that the reversal was what put white at index 0 the way the
## system Mac table does. Both halves of that were wrong, and the second one is
## why it survived: the chunk *already* opens with white and ends with black, so
## reversing it is what moves black to index 0 — which is paper, the index both
## ink passes key out and the one index that has to be exactly white. Every
## custom palette came out inverted, and the artwork drew in a garish, noisy
## version of itself with a black background.
##
## Measured rather than argued. `torfim.dir` #601 `Antark_back`, the palette its
## own 616x390 `Ant_back` backdrop names, opens `ffffff ffffff e4e4ececf4f4` and
## its last 12 bytes are zero; decoded forwards the backdrop is 61,600 white
## pixels over a pale blue sky and a teal sea, and decoded backwards it is 84,255
## black pixels with orange (`#eba515`) where the sea was. The reference agrees:
## its `CLUT` reader walks a colour index up from zero and takes the high byte of
## each 16-bit channel, with no reversal anywhere.
##
## A short chunk fills what it has and leaves the rest black rather than
## refusing: Director tolerates palettes of fewer than 256 entries, and a
## half-read palette that draws is findable where a crash on load is not.
static func from_clut(payload: PackedByteArray) -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(TABLE_BYTES)
	var steps: int = mini(payload.size() / 6, ENTRIES)
	for index in steps:
		var at := index * 6
		table[index * 3] = payload[at]
		table[index * 3 + 1] = payload[at + 2]
		table[index * 3 + 2] = payload[at + 4]
	return table


## Colour cycling: rotate the entries between `first` and `last` by `offset`.
##
## §11. The rotation is over a closed range and wraps inside it; everything
## outside is copied through untouched, which is what makes cycling a local
## effect on a few indices rather than a new palette. A reversed or degenerate
## range is returned unchanged rather than clamped — Director cycles nothing when
## there is nothing between the two, and inventing a direction here would animate
## a palette the author asked to leave alone.
static func cycled(
	table: PackedByteArray, first: int, last: int, offset: int
) -> PackedByteArray:
	var out := table.duplicate()
	if first < 0 or last >= ENTRIES or last <= first:
		return out
	var span := last - first + 1
	# GDScript's `%` keeps the sign of the dividend, so a negative offset -- which
	# is what auto-reverse runs on -- would index before `first`.
	var shift := ((offset % span) + span) % span
	if shift == 0:
		return out
	for i in span:
		var from: int = first + (i + shift) % span
		var to := first + i
		out[to * 3] = table[from * 3]
		out[to * 3 + 1] = table[from * 3 + 1]
		out[to * 3 + 2] = table[from * 3 + 2]
	return out


## A fade: every entry moved `t` of the way to one colour, `t` in 0..1.
##
## This is what §11's fade-to-black and fade-to-white are made of. It fades the
## whole table rather than a range: a fade is a transition of the *screen*, and
## restricting it to the cycling range would leave the rest of the picture up.
static func faded(table: PackedByteArray, target: Color, t: float) -> PackedByteArray:
	var out := table.duplicate()
	var k := clampf(t, 0.0, 1.0)
	var tr := target.r8
	var tg := target.g8
	var tb := target.b8
	for i in ENTRIES:
		out[i * 3] = int(round(lerpf(table[i * 3], tr, k)))
		out[i * 3 + 1] = int(round(lerpf(table[i * 3 + 1], tg, k)))
		out[i * 3 + 2] = int(round(lerpf(table[i * 3 + 2], tb, k)))
	return out


## A cross-fade between two palettes, `t` in 0..1. §11's "fade between old and
## new palettes over a number of steps", as opposed to the fade to a colour.
static func blended(
	from_table: PackedByteArray, to_table: PackedByteArray, t: float
) -> PackedByteArray:
	if from_table.size() != TABLE_BYTES or to_table.size() != TABLE_BYTES:
		return to_table.duplicate()
	var out := PackedByteArray()
	out.resize(TABLE_BYTES)
	var k := clampf(t, 0.0, 1.0)
	for i in TABLE_BYTES:
		out[i] = int(round(lerpf(from_table[i], to_table[i], k)))
	return out


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
	for i in ENTRIES:
		if table[i * 3] >= threshold and table[i * 3 + 1] >= threshold \
				and table[i * 3 + 2] >= threshold:
			out.append(i)
	return out


static func _index_of(table: PackedByteArray, r: int, g: int, b: int) -> int:
	for i in ENTRIES:
		if table[i * 3] == r and table[i * 3 + 1] == g and table[i * 3 + 2] == b:
			return i
	return -1


## A supplied table, or empty. Read once; a missing file is the normal case here
## and must not cost a file probe per palette resolution.
static func _external_table(clut_id: int) -> PackedByteArray:
	if not _external_loaded:
		_external_loaded = true
		if FileAccess.file_exists(PALETTE_DATA):
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(PALETTE_DATA)
			)
			if typeof(parsed) == TYPE_DICTIONARY:
				_external = parsed
			else:
				push_warning("%s is not a JSON object; ignored" % PALETTE_DATA)
	var hex := str(_external.get(str(clut_id), ""))
	if hex.length() != TABLE_BYTES * 2:
		if hex != "":
			push_warning(
				"%s entry %d is %d hex characters, expected %d"
				% [PALETTE_DATA, clut_id, hex.length(), TABLE_BYTES * 2]
			)
		return PackedByteArray()
	return hex.hex_decode()
