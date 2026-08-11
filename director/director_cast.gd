class_name DirectorCast
extends RefCounted
## One cast library: the `CAS*` table of one owner in one container, with every
## member's `CASt` parsed and its payload chunk located through `KEY*`.
##
## Byte order is per chunk, not per container. `imap`, `mmap` and `KEY*` follow
## the container, but `CAS*`, `CASt`, `STXT` and `MCsL` are big-endian in every
## file — including the little-endian `XFIR` ones. Reading a member record in the
## container's order works on 83 of this game's 86 files and silently produces
## nonsense on the other 3, which are the boot movie and the shared cast.
##
## A member's name and its Lingo source both live in the info block, addressed by
## an offset table: item 0 is the script text, item 1 is the name. Scanning the
## block for "the first Pascal string" instead lands inside item 0 for any member
## that carries a script, which is the defect `tools/add_cast_script_names.py`
## exists to repair after the fact. Read by the table and there is nothing to
## repair.

const Transition := preload("res://director/director_transition.gd")
const Codepage := preload("res://director/director_codepage.gd")

## `director_cast_types.py`'s spelling, kept so tooling and this agree.
const TYPE_NAMES := {
	1: "bitmap", 2: "filmLoop", 3: "field", 4: "palette", 5: "picture",
	6: "sound", 7: "button", 8: "shape", 9: "movie", 10: "digitalVideo",
	11: "script", 12: "richText", 13: "OLE", 14: "transition", 15: "xtra",
}
## A sprite whose member is one of these and does not resolve is missing art.
## Anything else — a shape, a script — is *meant* to draw nothing.
const DRAWING_TYPES := ["bitmap", "filmLoop", "picture", "richText"]
## Everything below the flag bit of a bitmap's pitch word is the row stride in
## bytes.
##
## **It was `0x0FFF`, which is the same number for every stride under 4,096 and a
## truncation for every one above.** Three members in the corpus are above it, all
## three the panoramic backdrop of a `piposh-dream` maze room: `hatul1.dir` #3
## `stage1` is 4943 x 400 at 8 bits, so its row is 4,944 bytes, its pitch word is
## `0x9350`, and masking to twelve bits handed the decoder 848. `unpack` then
## produced a buffer of `848 * 400` and `_blit_8` read `4943` bytes out of each
## 848-byte row, which is a GDScript "out of bounds get index" on the first row --
## an error that aborts the blit, so the member drew as whatever was already in
## the buffer, on every repaint, for as long as the room was on screen.
##
## The mask is `0x7FFF` because the corpus says so rather than because a document
## does. Over all six titles -- 119,013 bitmap members -- the top nibble of the
## pitch word is `0x8` or `0x0` everywhere except those three, where it is `0x9`;
## and with bit 15 alone removed, the remaining value equals the member's own
## width times its own depth rounded up to an even byte count for **every one of
## the 119,013**, with no exceptions in either direction. Bit 15 is `DEPTH_FLAG`
## below and is the only bit of that word that is not stride in any file here.
## `tools/liveness_sweep.gd` is what surfaced it: the decode error slowed the
## paint enough to show up as a movie the sweep could not sample.
const STRIDE_MASK := 0x7FFF
## Bit 0x8000 of the pitch is set for every member that is not 1-bit. It says
## "not 1-bit" and nothing more: reading it as "8bpp" mis-decodes the 16- and
## 32-bit members, which is why the depth comes from the specific block's own
## byte and this is kept only as a cross-check.
const DEPTH_FLAG := 0x8000
## Bit 1 of the cast info flag word: the Cast Info dialog's **Auto Hilite** tick
## box. §4.6 -- a bitmap sprite inverts on mouse-down when its member carries it.
const INFO_AUTO_HILITE := 0x02
## Bit 0 of the same word: the member's artwork is linked from an external file
## rather than stored in this cast. Decoded, unused, and named so it is not
## mistaken for a spare bit later.
const INFO_EXTERNAL := 0x01
## Byte 25 of a text member's specific block: the Field dialog's three tick
## boxes. `editable` is the one that matters — see `_parse_specific`, where the
## measurement that identifies this byte is written down. `word_wrap` is stored
## inverted, which is why the constant is named for the bit and not for the
## property.
const TEXT_EDITABLE_FLAG := 0x01
const TEXT_AUTO_TAB_FLAG := 0x02
const TEXT_NO_WRAP_FLAG := 0x04

## Not owned: the caller opened it and the caller closes it.
var file = null
## The `MCsL` castID, or the sole `CAS*` owner when the container has only one.
var owner_id: int = -1
var cas_chunk_id: int = -1
var min_member: int = 1
var member_count: int = 0
var error: String = ""

## member number -> its `CASt` chunk id. Empty `CAS*` slots are absent.
var _cast_chunk: Dictionary = {}
## {owner chunk id: {tag: section chunk id}} from `KEY*`.
var _owned: Dictionary = {}
var _members: Dictionary = {}
var _names_lower: Dictionary = {}


## Indexes one library. `cast_owner_id < 0` means "the only CAS* in this file".
func open(container, cast_owner_id: int = -1) -> bool:
	error = ""
	file = container
	owner_id = cast_owner_id
	_read_key_table()

	var candidates: Array = file.ids_of("CAS*")
	if candidates.is_empty():
		error = "no CAS* in %s" % file.path
		return false
	if owner_id >= 0:
		# A container can hold more than one cast. GARDUG.dir carries an
		# embedded library beside its internal one, and picking the first CAS*
		# happens to be right there only by luck of ordering, so the owner from
		# the library table is what selects it.
		cas_chunk_id = -1
		for id in candidates:
			if int(_owner_of(id)) == owner_id:
				cas_chunk_id = id
				break
		if cas_chunk_id < 0:
			error = "no CAS* owned by %d in %s" % [owner_id, file.path]
			return false
	else:
		cas_chunk_id = candidates[0]

	var table: PackedByteArray = file.read_chunk(cas_chunk_id)
	if table.is_empty():
		error = "CAS* %d unreadable: %s" % [cas_chunk_id, file.error]
		return false
	_cast_chunk.clear()
	var slots: int = table.size() / 4
	for i in slots:
		var chunk_id := _be_u32(table, i * 4)
		# A zero slot is a deleted member, not a gap to report.
		if chunk_id != 0:
			_cast_chunk[min_member + i] = chunk_id
	member_count = slots
	return true


## Member numbers that have a record, ascending.
func member_numbers() -> Array:
	var out: Array = _cast_chunk.keys()
	out.sort()
	return out


## One member, parsed and cached. `{}` means the slot is empty or unreadable,
## which for a deleted member is the expected answer rather than a fault.
func member(number: int) -> Dictionary:
	if _members.has(number):
		return _members[number]
	if not _cast_chunk.has(number):
		return {}
	var chunk_id: int = _cast_chunk[number]
	var data: PackedByteArray = file.read_chunk(chunk_id)
	var parsed := _parse_cast(data, chunk_id, number)
	_members[number] = parsed
	return parsed


## Member number for a name, case-insensitively, or 0 when there is none.
func number_of(name: String) -> int:
	_build_names()
	return int(_names_lower.get(name.to_lower(), 0))


## number -> lowercased name, for every member that has one.
func names() -> Dictionary:
	_build_names()
	var out := {}
	for number in member_numbers():
		var m := member(number)
		if m.get("name", "") != "":
			out[number] = str(m["name"]).to_lower()
	return out


## name -> text, for the field members only.
func fields() -> Dictionary:
	var out := {}
	for number in member_numbers():
		var m := member(number)
		if int(m.get("type", 0)) == 3 and m.get("name", "") != "":
			out[str(m["name"]).to_lower()] = str(m.get("text", ""))
	return out


func _build_names() -> void:
	if not _names_lower.is_empty():
		return
	for number in member_numbers():
		var m := member(number)
		var name := str(m.get("name", ""))
		if name != "":
			# First writer wins: duplicate names exist and Director resolves to
			# the lowest member number.
			var key := name.to_lower()
			if not _names_lower.has(key):
				_names_lower[key] = number


# ------------------------------------------------------------------ CASt

func _parse_cast(data: PackedByteArray, chunk_id: int, number: int) -> Dictionary:
	if data.size() < 12:
		return {}
	var type_code := _be_u32(data, 0)
	var info_len := _be_u32(data, 4)
	var specific_len := _be_u32(data, 8)
	var type_name := str(TYPE_NAMES.get(type_code, "type%d" % type_code))

	var out := {
		"cast_id": number,
		"cast_lib": 0,
		"cast_lib_name": "",
		"type": type_code,
		"type_name": type_name,
		"drawing": DRAWING_TYPES.has(type_name),
		"name": "",
		"script_id": 0,
		"cast_chunk_id": chunk_id,
		"data_chunk_id": -1,
		"width": 0,
		"height": 0,
		"reg_offset_x": 0,
		"reg_offset_y": 0,
		# The info block's own flag word, and the two bits of it anything reads.
		# **`has_cast_info` is not the same as `auto_hilite` being false**, and
		# §4.6 turns on the difference: a bitmap with cast info answers hilite
		# from the flag, and a bitmap *without* one falls back to "ink is Matte".
		# D3 only wrote an info block for a member the author had named, scripted
		# or otherwise touched, so the absent case is real data and not an error.
		"info_flags": 0,
		"auto_hilite": false,
		"has_cast_info": false,
	}

	# 5 of DAY1's 372 members carry no info block at all.
	if info_len > 0 and 12 + info_len <= data.size():
		_parse_info(data.slice(12, 12 + info_len), out)

	var specific_at := 12 + info_len
	if specific_len > 0 and specific_at + specific_len <= data.size():
		_parse_specific(data.slice(specific_at, specific_at + specific_len), type_code, out)

	# An Xtra member is the one type whose geometry is *not* in its specific
	# block, so it is applied here, after both halves have been read, rather than
	# in `_parse_specific` where every other type's rect is decoded. It has to be:
	# an external Xtra has no readable specific block at all (see the type 15 arm)
	# and still carries a rect.
	if type_code == 15:
		_apply_xtra_rect(out)

	# The payload chunk this member owns, by tag rather than by "its first
	# chunk": bitmaps also own `Thum` thumbnails, and taking the first would
	# hand the renderer a thumbnail instead of the art.
	var want := ""
	match type_code:
		1: want = "BITD"
		2: want = "SCVW"
		3: want = "STXT"
		# A palette member owns its colour table the same way. Unexercised here —
		# this corpus has no palette member and no `CLUT` chunk at all
		# (`tools/palette_survey.gd`) — and present because `director_palette.gd`
		# can read one and had no way to be handed it.
		4: want = "CLUT"
	# A sound member owns its audio under one of three tags depending on how the
	# movie was authored: `snd ` is the Mac resource Director 3 and 4 wrote,
	# `sndS` the samples of the D4+ header/samples pair, and `sndH` that pair's
	# header. Taken in that order and reported as `sound_header_chunk_id`
	# alongside, so `director/director_sound.gd` can tell which shape it has.
	#
	# **Unexercised by this corpus and therefore unverified**: this game has no
	# sound cast member at all, in any of its 86 containers — every sound it
	# plays is an external file (`tools/sound_survey.gd`). Present because the
	# score's sound channels name members and had no way to be handed one.
	if type_code == 6:
		var sound_owned: Dictionary = _owned.get(chunk_id, {})
		for tag in ["snd ", "sndS", "sndH"]:
			if sound_owned.has(tag):
				out["data_chunk_id"] = int(sound_owned[tag])
				out["sound_tag"] = tag
				break
		out["sound_header_chunk_id"] = int(sound_owned.get("sndH", -1))
	# A rich text member owns *three* chunks rather than one, so it cannot go
	# through `want` above. `castmember/richtext.cpp:load()` names them: `RTE0` is
	# the Paige editor document and is authoring-tool data with no runtime use,
	# `RTE1` is the plain text, and `RTE2` is the antialiased bitmap Director
	# actually draws. `data_chunk_id` is `RTE2` because that is the one a renderer
	# needs; the other two are reported beside it so nothing has to guess a tag.
	#
	# Zero members of this type exist in any corpus in reach, so which tags a real
	# rich text member owns here is the reference's claim and not a measurement.
	if type_code == 12:
		var rte: Dictionary = _owned.get(chunk_id, {})
		out["rte0_chunk_id"] = int(rte.get("RTE0", -1))
		out["rte1_chunk_id"] = int(rte.get("RTE1", -1))
		out["rte2_chunk_id"] = int(rte.get("RTE2", -1))
		out["data_chunk_id"] = int(rte.get("RTE2", -1))
		# `RTE1` is the text with no styling and no header -- the reference reads
		# the whole chunk as the string (`richtext.cpp:load()`), which is why this
		# does not go through `_read_stxt`.
		if int(out["rte1_chunk_id"]) >= 0:
			out["text"] = _text(file.read_chunk(int(out["rte1_chunk_id"])))
	if want != "":
		var owned: Dictionary = _owned.get(chunk_id, {})
		out["data_chunk_id"] = int(owned.get(want, -1))
		if type_code == 3 and out["data_chunk_id"] >= 0:
			out["text"] = _read_stxt(int(out["data_chunk_id"]))
			out["text_style"] = _read_stxt_style(int(out["data_chunk_id"]))
	return out


## The info block: an offset table whose item 0 is the member's Lingo source and
## whose item 1 is its name.
func _parse_info(info: PackedByteArray, out: Dictionary) -> void:
	if info.size() < 20:
		return
	var data_offset := _be_u32(info, 0)
	out["has_cast_info"] = true
	# The header is five big-endian words before the string table: the offset to
	# that table, two the reference does not name, the flag word, and the script
	# id. Only the first and last were read here, which is why the flag word had
	# to be found rather than looked up -- and it is checked by the same rule that
	# settled the script id: **script_id lands at 16**, so the word before it at
	# 12 is the flags, and nothing else can be.
	#
	# Bit 1 is Auto Hilite, the Cast Info dialog's tick box, and it is what §4.6
	# drives a bitmap's hilite-on-click from. Bit 0 is "external" (a linked
	# member), decoded here only because it is the other documented bit in the
	# same word and leaving it out would invite the next reader to re-derive it.
	out["info_flags"] = _be_u32(info, 12)
	out["auto_hilite"] = (int(out["info_flags"]) & INFO_AUTO_HILITE) != 0
	out["script_id"] = _be_u32(info, 16)
	if data_offset + 2 > info.size():
		return
	var count := _be_u16(info, data_offset)
	var offsets_at := data_offset + 2
	if offsets_at + count * 4 + 4 > info.size():
		return
	var offsets: Array = []
	for i in count:
		offsets.append(_be_u32(info, offsets_at + i * 4))
	var items_len := _be_u32(info, offsets_at + count * 4)
	var items_base := offsets_at + count * 4 + 4

	var item := func(index: int) -> PackedByteArray:
		if index >= count:
			return PackedByteArray()
		var start: int = items_base + int(offsets[index])
		var stop: int = items_base + (
			int(offsets[index + 1]) if index + 1 < count else items_len
		)
		if start < 0 or stop > info.size() or stop < start:
			return PackedByteArray()
		return info.slice(start, stop)

	var source: PackedByteArray = item.call(0)
	if not source.is_empty():
		out["source"] = _text(source)
	var name_item: PackedByteArray = item.call(1)
	if name_item.size() >= 1:
		var length: int = name_item[0]
		if length + 1 <= name_item.size():
			out["name"] = _text(name_item.slice(1, 1 + length))

	# Items 9, 10 and 12 are the Xtra block of the same table, and they are read
	# here rather than in the type-15 arm below because the table is *positional*:
	# item 12 is `xtraRect` wherever it appears, whatever the member's type, and
	# the offset table is the only thing that says where it starts. The indices
	# are the reference's own -- `cast.cpp:loadCastInfo` reads 9 as a 16-byte
	# `xtraGuid`, 10 as a C-string `xtraDisplayName` and 12 as four big-endian
	# int32 in the order top, left, bottom, right; `cast.cpp:getCastInfoStringLength`
	# and the writer beside it state the same widths. Cited at ScummVM 805f259a.
	#
	# They are read for any member whose table is long enough, and *consumed* only
	# for type 15 -- `_parse_cast` calls `_apply_xtra_rect` on nothing else. That
	# split is deliberate: whether a member of some other type can declare thirteen
	# items has not been measured, and a decode that depends on the answer would be
	# resting on an assumption. This one does not. A member with a long table and no
	# use for these keys simply carries them.
	var guid: PackedByteArray = item.call(9)
	if guid.size() == 16:
		out["xtra_guid"] = guid.hex_encode()
	var display: PackedByteArray = item.call(10)
	if not display.is_empty():
		# A C string, where the name above is a Pascal one: the reference reads it
		# with `readString(false)` and the trailing NUL is inside the item.
		out["xtra_display_name"] = _text(_c_string(display))
	var rect: PackedByteArray = item.call(12)
	if rect.size() >= 16:
		out["xtra_rect"] = {
			"top": _be_i32(rect, 0), "left": _be_i32(rect, 4),
			"bottom": _be_i32(rect, 8), "right": _be_i32(rect, 12),
		}


func _parse_specific(spec: PackedByteArray, type_code: int, out: Dictionary) -> void:
	match type_code:
		1:
			if spec.size() < 22:
				return
			var pitch := _be_u16(spec, 0)
			out["row_stride"] = pitch & STRIDE_MASK
			# 28 bytes for 8/16/32-bit members, 23 for 1-bit ones — the 1-bit
			# block ends at the flags byte and carries no depth field at all.
			var depth := int(spec[23]) if spec.size() >= 24 else 1
			out["bits_per_pixel"] = depth if depth > 0 else 1
			var top := _be_i16(spec, 2)
			var left := _be_i16(spec, 4)
			var bottom := _be_i16(spec, 6)
			var right := _be_i16(spec, 8)
			out["width"] = right - left
			out["height"] = bottom - top
			out["initial_rect"] = {"top": top, "left": left, "bottom": bottom, "right": right}
			var reg_y := _be_i16(spec, 18)
			var reg_x := _be_i16(spec, 20)
			out["reg_offset_x"] = reg_x - left
			out["reg_offset_y"] = reg_y - top
			_parse_clut(spec, out)
		3:
			# A field's specific block is 28 bytes in every one of this corpus's
			# 321 field members, and this layout was settled by measuring the
			# distribution of each slot rather than by reading one example: bytes
			# 0-2 are zero in all 321, byte 3 is 0 or 3, the i16 at 4 is 0 or 1,
			# the three u16 at 6-11 are ffff ffff ffff in all 321 (white, as a Mac
			# 48-bit RGB), and the rect at 14-21 comes out positive and under 1200
			# on both axes in all 321. A wrong alignment does not land that cleanly.
			#
			# Cross-checked against a number stored somewhere else entirely: over
			# the corpus this rect's width equals the sprite record's width in
			# 9,917 of 11,525 field sprite records and its height is exactly 2
			# larger in 9,723 of them. The 2 is the field's box, which Director
			# lays out inside the member rect.
			if spec.size() < 22:
				return
			out["border"] = spec[0]
			out["gutter"] = spec[1]
			out["box_shadow"] = spec[2]
			out["text_type"] = spec[3]
			# 0 left, 1 centre, -1 right. Only 0 (308 members) and 1 (13) occur
			# here, so the right-aligned arm is written from the reference and is
			# unexercised by this corpus.
			out["text_align"] = _be_i16(spec, 4)
			# Director stores a colour here as a Mac RGBColor — three 16-bit
			# channels, not a palette index — so the high byte of each is the
			# 8-bit value. This is the field's paper, and it is what an ink keys
			# against for a text sprite rather than the sprite's own backColor.
			out["bg_color"] = Color8(spec[6], spec[8], spec[10])
			out["scroll"] = _be_u16(spec, 12)
			var ft := _be_i16(spec, 14)
			var fl := _be_i16(spec, 16)
			var fb := _be_i16(spec, 18)
			var fr := _be_i16(spec, 20)
			out["width"] = fr - fl
			out["height"] = fb - ft
			out["initial_rect"] = {"top": ft, "left": fl, "bottom": fb, "right": fr}
			# Bytes 22-27, which used to be recorded as "three more u16, and what
			# they are is unsettled". They are not three u16: 22 is the maximum
			# height the box may grow to, **24 and 25 are two bytes** — a drop
			# shadow width and a **flag byte** — and 26 is the laid-out text
			# height. That the middle pair is two bytes and not one u16 is why the
			# old reading saw "24 is almost always zero": byte 24 is zero in all
			# 321 members here, so the u16 only ever moved when byte 25 did.
			#
			# **Byte 25 bit 0 is `the editable of member`, and it is the only
			# source of editability this corpus has.** Not one of Piposh 2's
			# 816,318 sprite records sets the score's own editable bit, nor one of
			# Piposh 1's 1,886,362, nor one of Rating's 847,431 — so a port that
			# read only the score's half would find nothing editable anywhere and
			# conclude, wrongly, that the feature is unexercised. The member half
			# says otherwise and says it in exactly the place it should:
			# `SAVELOAD.dir`'s `save1` (120x19, the save-slot name box), Piposh 1
			# English's eight 120x19 boxes in `Mainmenu.dir` and Russian's
			# sixteen, plus `Arcade`'s high-score entry, `Roullete`'s five bet
			# boxes and `Caproom`/`Zuzroom`. A wrong offset does not land on the
			# save screen of three different builds.
			#
			# Bits 1 and 2 come from the same byte and the same reference:
			# auto-tab (Tab moves to the next editable field) and do-not-wrap.
			if spec.size() >= 28:
				out["max_height"] = _be_u16(spec, 22)
				out["text_shadow"] = spec[24]
				out["text_flags"] = spec[25]
				out["editable"] = (spec[25] & TEXT_EDITABLE_FLAG) != 0
				out["auto_tab"] = (spec[25] & TEXT_AUTO_TAB_FLAG) != 0
				out["word_wrap"] = (spec[25] & TEXT_NO_WRAP_FLAG) == 0
				out["text_height"] = _be_u16(spec, 26)
		2:
			if spec.size() < 12:
				return
			var t := _be_i16(spec, 0)
			var l := _be_i16(spec, 2)
			var b := _be_i16(spec, 4)
			var r := _be_i16(spec, 6)
			out["width"] = r - l
			out["height"] = b - t
			out["initial_rect"] = {"top": t, "left": l, "bottom": b, "right": r}
			# A film loop registers at the CENTRE of its rect. It carries no
			# registration point of its own the way a bitmap does, and Director
			# uses (width/2, height/2). That stays self-consistent when the loop
			# is drawn at another size, because the scaled offset is then simply
			# half the drawn size.
			out["reg_offset_x"] = int((r - l) / 2.0)
			out["reg_offset_y"] = int((b - t) / 2.0)
			# Bit 0x20 CLEAR means looping.
			out["looping"] = (_be_u32(spec, 8) & 32) == 0
		8:
			if spec.size() < 17:
				return
			# Byte 0 is unidentified and zero throughout this corpus; byte 1 is
			# the shape kind, which from D3 overrides the sprite record's own
			# type byte. All 169 shape members here are 1 (rectangle, 167) or 2
			# (rounded rectangle, 2).
			out["shape_type"] = spec[1]
			var st := _be_i16(spec, 2)
			var sl := _be_i16(spec, 4)
			var sb := _be_i16(spec, 6)
			var sr := _be_i16(spec, 8)
			out["width"] = sr - sl
			out["height"] = sb - st
			out["initial_rect"] = {"top": st, "left": sl, "bottom": sb, "right": sr}
			out["pattern"] = _be_u16(spec, 10)
			# Bytes 12 and 13 are the member's own fore and back colour. The score
			# overrides both per sprite and every consumer here reads the sprite's,
			# so they are carried and not used.
			out["shape_fore"] = spec[12]
			out["shape_back"] = spec[13]
			out["fill_type"] = spec[14]
			out["filled"] = spec[14] != 0
			# The stored thickness is one greater than the drawn one: for an
			# outlined shape a stored 1 means an invisible outline. That is not a
			# quirk to work around, it is how this game hides its hotspots — 162 of
			# the 169 shape members here are unfilled rectangles with a stored
			# thickness of 1, which Director draws as nothing at all while they go
			# on catching clicks.
			out["line_thickness"] = spec[15]
			out["line_direction"] = spec[16]
		11:
			if spec.size() >= 2:
				out["script_type"] = _be_u16(spec, 0)
		12:
			# **Unverified against real data, and there is none to verify it
			# against.** `tools/member_type_census.gd` counts every `CASt` chunk in
			# all eight corpora in reach -- the six shipped titles under `games/`
			# and both test corpora -- and finds **0 members of type 12 in 160,932
			# cast members**. Piposh 1's credits census found none either. So this
			# arm is written from the reference and from nothing else, and the
			# thing that would verify it is one container with a rich text member
			# in it: run the census with `--type 12 --dump 4` over that corpus and
			# check that the two rects come out the size the member is on stage.
			# It is here because Director has the type, not because this corpus
			# does (AGENTS.md, "Build Director, not this game").
			#
			# The layout is `castmember/richtext.cpp:RichTextCastMember()`, whose
			# own `getCastDataSize()` states it as 34 bytes: two rects of four
			# int16 in the order top/left/bottom/right (`movie.cpp:Movie::readRect`),
			# an antialias flag, crop flags, the scroll position, the size below
			# which text is not antialiased, the laid-out height, one skipped byte,
			# the fore colour as three *bytes*, and the paper as three big-endian
			# int16 of which the high byte is the value. The two colours are stored
			# differently and that is not a transcription slip -- the reference
			# reads `readByte()` three times for one and `readUint16BE() >> 8`
			# three times for the other. Cited at ScummVM 805f259a.
			#
			# **The length is the version gate.** The reference decodes this layout
			# only for D5 through D11 and warns "RTE not yet supported" outside
			# that range, so a pre-D5 rich text member has no known layout in the
			# reference either. A cast has no version to test here -- the version
			# is in the movie's `VWCF`, which this class never opens -- so the
			# block's own length stands in for it: 34 bytes is the D5 record, and
			# anything shorter is refused rather than mis-read into a rect that
			# would then be handed to `sprite_geometry.drawn_size` as fact.
			if spec.size() < 34:
				return
			var rt := _be_i16(spec, 0)
			var rl := _be_i16(spec, 2)
			var rb := _be_i16(spec, 4)
			var rr := _be_i16(spec, 6)
			out["width"] = rr - rl
			out["height"] = rb - rt
			out["initial_rect"] = {"top": rt, "left": rl, "bottom": rb, "right": rr}
			# The laid-out extent, which for a rich text member can exceed the
			# authored box. Carried, not applied: nothing here lays the text out,
			# so a consumer that grew the sprite to it would be reporting a height
			# the port cannot draw.
			out["bounding_rect"] = {
				"top": _be_i16(spec, 8), "left": _be_i16(spec, 10),
				"bottom": _be_i16(spec, 12), "right": _be_i16(spec, 14),
			}
			# A rich text member carries no registration point of its own. The
			# reference gives it none either -- `RichTextCastMember` does not
			# override `CastMember::getRegistrationOffset`, which is (0,0)
			# (`castmember/castmember.h:99`) -- so the sprite's `loc` is the box's
			# top-left corner, and the zeros `_parse_cast` already put in
			# `reg_offset_x`/`reg_offset_y` are the answer rather than a gap.
			out["antialias"] = spec[16] != 0
			out["crop_flags"] = spec[17]
			out["scroll"] = _be_u16(spec, 18)
			out["antialias_font_size"] = _be_u16(spec, 20)
			out["text_height"] = _be_u16(spec, 22)
			out["fore_color_rgb"] = Color8(spec[25], spec[26], spec[27])
			out["bg_color"] = Color8(spec[28], spec[30], spec[32])
		15:
			# An Xtra cast member: a name and an opaque blob the named Xtra owns.
			#
			# `castmember/xtra.cpp:XtraCastMember()` reads exactly this and nothing
			# more -- a big-endian uint32 length, that many bytes of symbol, a
			# second uint32 length, and that many bytes of payload -- and the
			# member's geometry is *not* in here at all (see `_apply_xtra_rect`).
			# Cited at ScummVM 805f259a.
			#
			# Measured by `tools/xtra_members.gd`: `4 + symbol length + 4 + payload
			# length` equals the specific block's own length for every one of the
			# 551 Xtra members it reaches -- all 454 in `itamar-magichat`, all 97 in
			# `piposh-dream` -- which is the same self-check the field member's
			# 20-byte style run gets, and is what says the two length words are
			# being read in the right places. Every one of them also yields a
			# non-empty symbol, and there are five across those two titles:
			# `flash` (253), `animGif` (199), `vectorShape` (94), `text` (3) and
			# `VisibleLightOnStageMedia` (2). `itamar-park` adds a sixth spelling,
			# `animgif`, which is why nothing here matches a symbol case-sensitively.
			#
			# The payload is deliberately kept as a length and not as bytes. It is
			# the Xtra's private serialisation -- a Flash movie, a QuickTime path,
			# whatever the DLL wrote -- and this engine cannot interpret one it has
			# not implemented, so carrying it would be carrying a copy of something
			# nothing reads.
			#
			# **An external Xtra has no such envelope.** The reference returns from
			# the constructor before reading a byte of it when the member's info
			# flags say `isExternal` (bit 0, `INFO_EXTERNAL`), because for a linked
			# member the specific block is the link and not the envelope. Reading
			# it anyway would produce a symbol length of whatever the first four
			# bytes of a file reference happen to be.
			if bool(out.get("has_cast_info", false)) \
					and (int(out.get("info_flags", 0)) & INFO_EXTERNAL) != 0:
				out["xtra_external"] = true
				return
			if spec.size() < 8:
				return
			var symbol_len := _be_u32(spec, 0)
			if 4 + symbol_len + 4 > spec.size():
				return
			out["xtra_symbol"] = _text(spec.slice(4, 4 + symbol_len))
			var data_len := _be_u32(spec, 4 + symbol_len)
			out["xtra_data_size"] = mini(data_len, spec.size() - (8 + symbol_len))
			# The self-check, reported rather than asserted here so that
			# `tools/xtra_members.gd` can assert it over the whole corpus at once:
			# the two length words and the two runs they measure must account for
			# every byte of the block. No other split of those bytes does.
			out["xtra_specific_len"] = spec.size()
			out["xtra_envelope_len"] = 8 + symbol_len + data_len
		14:
			# A transition member is six bytes and no info block: the type, the
			# chunk size, the change area and the duration the frame that names
			# it will spend. Decoded in `director/director_transition.gd`, where
			# the byte layout is written down against the three members in this
			# corpus that exercise it.
			out.merge(Transition.decode_member(spec))


## An Xtra member's size and registration point, out of the `xtraRect` its *info*
## block carries.
##
## Geometry in the info block is peculiar to this one type and is the reason this
## is a function rather than a line in the type-15 arm above. An Xtra's specific
## block is the Xtra's own envelope -- a symbol and an opaque payload, nothing
## else (`castmember/xtra.cpp:XtraCastMember()`) -- so there is nowhere in it for
## a rect, and Director puts one at item 12 of the info table instead
## (`cast.cpp:loadCastInfo`, ScummVM 805f259a). An **external** Xtra has no
## readable envelope at all and still has a rect, which is the other reason this
## runs outside `_parse_specific`.
##
## **The reference does not do this, and the reason it does not is that it draws
## no Xtra.** ScummVM reads the same rect into `CastMemberInfo::xtraRect` and
## never puts it on the member, so `XtraCastMember::getInitialRect()` is the empty
## rect its base class default-constructed -- and `sprite.cpp:Sprite::setCast`
## then resets any sprite naming one to 0x0. That is survivable there because
## nothing is placed or hit-tested against it. It is not survivable here: this
## port's hit test is `sprite_geometry.stage_rect(...).has_point(at)`
## (`scenes/preview/interaction.gd`), so a member with no size hands the score's
## own rect straight through and a member with a *wrong* registration point moves
## every click by half its own size.
##
## So what the rect means was measured rather than assumed, and it is measured
## against a witness outside the decode -- `tools/xtra_members.gd`:
##
##   **The size.** For a sprite the author did not mark as stretched, Director
##   resets the score's width and height to the member's own rect
##   (`sprite.cpp:setCast`). Across the two corpora that place Xtra sprites --
##   `itamar-magichat` and `piposh-dream`, two unrelated titles using four
##   different Xtras between them -- **7,593 unstretched sprite records name an
##   Xtra member and the score's rect matches this rect within a pixel on 7,557**.
##   `piposh-dream`'s half of that is 6,765 records and **not one disagreement**;
##   magichat's 36 exceptions are ordinary authoring residue of the shape
##   `sprite_geometry.drawn_size` already documents -- `virus_2` recorded 14x18
##   against a 90x86 member, `BonusFire` 35x35 against 100x100 -- and not a second
##   convention. Nothing in this port derives one of those two numbers from the
##   other, so the agreement is evidence and not arithmetic.
##
##   **The registration point.** The rect's *origin* is it, exactly as it is for a
##   bitmap: `_parse_specific`'s type-1 arm stores `regPoint - left/top`, and an
##   Xtra has no separate regPoint, so the offset is `(0,0) - (left,top)`.
##
##   The evidence is where the origin falls. Of magichat's 400 members that carry
##   a rect, **287 are centred on it to within half a pixel** -- `title1` 800x600
##   at (-400,-300), the `leftheadin`/`rightheadin` family 170x150 at (-85,-75),
##   `no` and `yes` 125x141 at (-62,-70) -- **104 are at (0,0)**, both of the
##   `VisibleLightOnStageMedia` video members among them, and 9 sit elsewhere
##   inside the box. `piposh-dream`'s 94 split 68 centred and 26 elsewhere, which
##   is what a `vectorShape` Xtra should look like: a vector's registration point
##   is wherever the author dropped it, and a member type whose origin is *free*
##   inside the box while a Flash movie's defaults to the centre and a video's to
##   the corner is a registration point behaving like one.
##
##   **In all 494 rects across both corpora the origin lies on or inside the
##   member's own box**, which is the falsifiable part and the one
##   `tools/xtra_members.gd` asserts. "Centre or corner" is deliberately *not*
##   asserted: that rule was written from the first corpus looked at, and the 9 in
##   magichat plus the 26 here falsified it.
##
##   Reading the origin as (0,0) regardless -- which is what following the
##   reference's `getRegistrationOffset` literally would do -- therefore places
##   and hit-tests every centred member half its own size down and to the right.
##   For `jinnycard`, 500x230, that is 250px.
##
## **Some Xtra members carry no rect at all** -- 54 of magichat's 454, 3 of
## `piposh-dream`'s 97. They keep a width and height of zero, which sends
## `drawn_size` back to the score's own rect: the same answer any member with no
## natural size has always got, and the right one when the member cannot supply a
## better.
##
## Nothing here draws an Xtra: this makes the member's *geometry* right, and
## `scenes/preview/sprite_art.gd:texture_for` still returns null for the type,
## which is what Director does for an Xtra it has no DLL for.
func _apply_xtra_rect(out: Dictionary) -> void:
	var rect: Dictionary = out.get("xtra_rect", {})
	if rect.is_empty():
		return
	var left := int(rect["left"])
	var top := int(rect["top"])
	var w := int(rect["right"]) - left
	var h := int(rect["bottom"]) - top
	# A degenerate rect is left alone rather than turned into a 0x0 member: with
	# no size `sprite_geometry.drawn_size` falls back to the score's own rect,
	# which is the better of the two answers when the member cannot supply one.
	if w <= 0 or h <= 0:
		return
	out["width"] = w
	out["height"] = h
	out["initial_rect"] = rect.duplicate()
	out["reg_offset_x"] = -left
	out["reg_offset_y"] = -top


func _read_stxt(chunk_id: int) -> String:
	var data: PackedByteArray = file.read_chunk(chunk_id)
	if data.size() < 12:
		return ""
	var offset := _be_u32(data, 0)
	var length := _be_u32(data, 4)
	if offset + length > data.size():
		return ""
	return _text(data.slice(offset, offset + length))


## The first style run of an `STXT`: how the member's text is meant to look.
##
## `STXT` is a header, the characters, then a run table — a u16 count followed by
## 20 bytes per run: the character offset the run starts at (u32), the line height
## and the ascent (u16 each), then the font id, the slant byte, one unidentified
## byte, the point size, and the colour as a Mac RGBColor of three u16.
##
## That the run is 20 bytes is not assumed. Across this corpus's 321 field members
## `12 + strLen + 2 + 20 * count` equals the chunk size exactly 321 times out of
## 321, which no wrong stride does.
##
## Only the first run is read. Every field member here declares exactly one, so a
## run table is a uniform style per member in practice; a member with genuinely
## mixed styling would render in its first run's style, which is a visible
## simplification rather than a silent one.
func _read_stxt_style(chunk_id: int) -> Dictionary:
	var data: PackedByteArray = file.read_chunk(chunk_id)
	if data.size() < 12:
		return {}
	var at: int = _be_u32(data, 0) + _be_u32(data, 4)
	if at + 2 > data.size():
		return {}
	var count := _be_u16(data, at)
	at += 2
	if count <= 0 or at + 20 > data.size():
		return {}
	return {
		# Kept for the record: this corpus uses 13 distinct font ids and there is
		# no font table here to resolve them against, so nothing selects a
		# typeface from this. The point size below is what the renderer honours.
		"font_id": _be_u16(data, at + 8),
		"slant": data[at + 10],
		"font_size": _be_u16(data, at + 12),
		# Zero on some members, where the renderer has to derive a line height
		# from the point size instead.
		"line_height": _be_u16(data, at + 4),
		"ascent": _be_u16(data, at + 6),
		"color": Color8(data[at + 14], data[at + 16], data[at + 18]),
	}


# ------------------------------------------------------------------ KEY*

## `KEY*` maps an owning chunk id to the chunks it owns. Its body follows the
## container's byte order, unlike the cast chunks it points at.
func _read_key_table() -> void:
	_owned.clear()
	var ids: Array = file.ids_of("KEY*")
	if ids.is_empty():
		return
	var data: PackedByteArray = file.read_chunk(ids[0])
	if data.size() < 12:
		return
	var big: bool = file.big_endian
	var header_len := _u16(data, 0, big)
	var entry_len := _u16(data, 2, big)
	var used := _u32(data, 8, big)
	if header_len <= 0 or entry_len <= 0:
		return
	for i in used:
		var at := header_len + i * entry_len
		if at + 12 > data.size():
			break
		var section := _u32(data, at, big)
		var owner := _u32(data, at + 4, big)
		var raw: PackedByteArray = data.slice(at + 8, at + 12)
		if not big:
			raw.reverse()
		var tag: String = raw.get_string_from_ascii()
		if not _owned.has(owner):
			_owned[owner] = {}
		# No owner in this corpus holds two chunks of the same tag, so last
		# writer never fires; if it ever does, the first is the one Director
		# would have used.
		if not _owned[owner].has(tag):
			_owned[owner][tag] = section


func _owner_of(section_id: int) -> int:
	for owner in _owned:
		for tag in _owned[owner]:
			if int(_owned[owner][tag]) == section_id:
				return int(owner)
	return -1


## The palette a bitmap member's indices are numbers in, out of the tail of its
## specific block.
##
## **This used to read one signed word at offset 24, and offset 24 is not the
## palette — it is the palette's *cast library*.** Across the six shipped titles
## it reads -1 in 117,456 of the 117,542 bitmap members that carry the field at
## all, and 0 in the other 86; across the two test corpora it reads -1 in all
## 1,711. That is what a "the palette is in my own cast" library field looks like
## and it is nothing like a distribution of palette ids. The id is the word after
## it, and the proof is a name: in `itamar-park` **655 of 657** bitmap members
## read a positive number there and **all 655** of those numbers are a type-4
## palette member in the same cast library — usually the member immediately
## before the bitmap, which is what Director writes when artwork is imported with
## its own palette. In `itamar-magichat` it is 154 of 154. Offset 24 cannot
## produce that once.
##
## **The length decides the layout, because the reference's reader is
## sequential.** It reads pitch, the two rects, the registration pair, a spare
## byte and the depth byte — 24 bytes — and then reads the palette: one word for
## D4, and a library word followed by an id word from D5 on. So a specific block
## of 28 bytes carries the pair and one of 26 carries the lone D4 id, which is the
## same test the reference makes by checking whether the stream has run out.
## Anything shorter carries no palette field at all: the 1,616 one-bit members
## across the six titles stop at 23 bytes, and a 1-bit member is black and white
## by definition.
##
## **Zero and below are built-ins, offset by one.** Director numbers the built-in
## palettes from 0 downward *here*, and from -1 downward in the score's palette
## channel, where 0 has to mean "no palette change this frame" instead. The
## reference reconciles the two by decrementing any id at or below zero, and that
## is what makes the overwhelmingly common value 0 mean system Mac (-1) rather
## than a member number no cast has. It is also what makes `itamar-magichat`'s
## 881 members reading -101 mean the Windows D5 system palette (-102), and its 19
## reading -2 mean Grayscale (-3).
func _parse_clut(spec: PackedByteArray, out: Dictionary) -> void:
	var lib := 0
	var id := 0
	if spec.size() >= 28:
		lib = _be_i16(spec, 24)
		id = _be_i16(spec, 26)
	elif spec.size() >= 26:
		id = _be_i16(spec, 24)
	else:
		# No palette field: a 1-bit member, which has no palette to name.
		out["palette_id"] = -1
		out["palette_lib"] = 0
		return
	out["palette_id"] = id - 1 if id <= 0 else id
	out["palette_lib"] = lib


# ------------------------------------------------------------------ bytes

## Every authored string in a cast -- a member's name, its Lingo source, a field
## member's text -- through the title's codepage, then Lingo's line separator
## through Godot's.
##
## Bytes above 127 used to be left as-is, a Latin-1 pass-through that was
## reversible and wrong: reversible because `director_writer.gd` wrote the same
## way back, wrong because nothing typed on a real keyboard survived it. What
## decides now is `director/director_codepage.gd`, and the same module is the
## writer's other half -- one table, both directions, or the round trip corrupts.
func _text(raw: PackedByteArray) -> String:
	return Codepage.decode(raw).replace("\r\n", "\n").replace("\r", "\n")


static func _be_u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _be_i16(d: PackedByteArray, o: int) -> int:
	var v := _be_u16(d, o)
	return v - 65536 if v >= 32768 else v


static func _be_u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


## A signed 32-bit big-endian word. The info block's `xtraRect` is the only field
## in a cast record stored this wide, and it is genuinely signed: a member whose
## registration point is its centre records a negative top and left.
static func _be_i32(d: PackedByteArray, o: int) -> int:
	var v := _be_u32(d, o)
	return v - 4294967296 if v >= 2147483648 else v


## Everything up to the first NUL. The info block stores one string as a C string
## where every other one is a Pascal string, and decoding the terminator with it
## puts a stray character on the end of every Xtra's display name.
static func _c_string(raw: PackedByteArray) -> PackedByteArray:
	var stop := raw.find(0)
	return raw if stop < 0 else raw.slice(0, stop)


static func _u16(d: PackedByteArray, o: int, big: bool) -> int:
	return _be_u16(d, o) if big else (d[o + 1] << 8) | d[o]


static func _u32(d: PackedByteArray, o: int, big: bool) -> int:
	if big:
		return _be_u32(d, o)
	return (d[o + 3] << 24) | (d[o + 2] << 16) | (d[o + 1] << 8) | d[o]
