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

## `director_cast_types.py`'s spelling, kept so tooling and this agree.
const TYPE_NAMES := {
	1: "bitmap", 2: "filmLoop", 3: "field", 4: "palette", 5: "picture",
	6: "sound", 7: "button", 8: "shape", 9: "movie", 10: "digitalVideo",
	11: "script", 12: "richText", 13: "OLE", 14: "transition",
}
## A sprite whose member is one of these and does not resolve is missing art.
## Anything else — a shape, a script — is *meant* to draw nothing.
const DRAWING_TYPES := ["bitmap", "filmLoop", "picture", "richText"]
## The low bits of a bitmap's pitch are the row stride in bytes.
const STRIDE_MASK := 0x0FFF
## Bit 0x8000 of the pitch is set for every member that is not 1-bit. It says
## "not 1-bit" and nothing more: reading it as "8bpp" mis-decodes the 16- and
## 32-bit members, which is why the depth comes from the specific block's own
## byte and this is kept only as a cross-check.
const DEPTH_FLAG := 0x8000

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
	}

	# 5 of DAY1's 372 members carry no info block at all.
	if info_len > 0 and 12 + info_len <= data.size():
		_parse_info(data.slice(12, 12 + info_len), out)

	var specific_at := 12 + info_len
	if specific_len > 0 and specific_at + specific_len <= data.size():
		_parse_specific(data.slice(specific_at, specific_at + specific_len), type_code, out)

	# The payload chunk this member owns, by tag rather than by "its first
	# chunk": bitmaps also own `Thum` thumbnails, and taking the first would
	# hand the renderer a thumbnail instead of the art.
	var want := ""
	match type_code:
		1: want = "BITD"
		2: want = "SCVW"
		3: want = "STXT"
	if want != "":
		var owned: Dictionary = _owned.get(chunk_id, {})
		out["data_chunk_id"] = int(owned.get(want, -1))
		if type_code == 3 and out["data_chunk_id"] >= 0:
			out["text"] = _read_stxt(int(out["data_chunk_id"]))
	return out


## The info block: an offset table whose item 0 is the member's Lingo source and
## whose item 1 is its name.
func _parse_info(info: PackedByteArray, out: Dictionary) -> void:
	if info.size() < 20:
		return
	var data_offset := _be_u32(info, 0)
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
			out["palette_id"] = _be_i16(spec, 24) if spec.size() >= 26 else -1
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
			# The registration point stays at the rect's own origin. Centring it
			# was a guess and it is wrong: `tools/score_diff.gd` measured the
			# export's placement rule as `x = loc_h - reg_offset_x` taken from
			# the member, and centring matches only 19-27% of records. MURDER1's
			# member 2:1 is 115x251 with a registration point of (0,0), so
			# centring displaced it 57px left and 125px up — character-sized, and
			# the reason a mouth sat off its face.
			# Bit 0x20 CLEAR means looping.
			out["looping"] = (_be_u32(spec, 8) & 32) == 0
		8:
			if spec.size() < 15:
				return
			var st := _be_i16(spec, 2)
			var sl := _be_i16(spec, 4)
			var sb := _be_i16(spec, 6)
			var sr := _be_i16(spec, 8)
			out["width"] = sr - sl
			out["height"] = sb - st
			out["filled"] = spec[14] != 0
		11:
			if spec.size() >= 2:
				out["script_type"] = _be_u16(spec, 0)


func _read_stxt(chunk_id: int) -> String:
	var data: PackedByteArray = file.read_chunk(chunk_id)
	if data.size() < 12:
		return ""
	var offset := _be_u32(data, 0)
	var length := _be_u32(data, 4)
	if offset + length > data.size():
		return ""
	return _text(data.slice(offset, offset + length))


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


# ------------------------------------------------------------------ bytes

## Director stores text as Mac-Roman. Bytes above 127 are left as-is rather than
## mapped, which is correct for every member name in this corpus and wrong for
## accented text; a real mapping belongs here when a title needs one.
func _text(raw: PackedByteArray) -> String:
	return raw.get_string_from_ascii().replace("\r\n", "\n").replace("\r", "\n")


static func _be_u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _be_i16(d: PackedByteArray, o: int) -> int:
	var v := _be_u16(d, o)
	return v - 65536 if v >= 32768 else v


static func _be_u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


static func _u16(d: PackedByteArray, o: int, big: bool) -> int:
	return _be_u16(d, o) if big else (d[o + 1] << 8) | d[o]


static func _u32(d: PackedByteArray, o: int, big: bool) -> int:
	if big:
		return _be_u32(d, o)
	return (d[o + 3] << 24) | (d[o + 2] << 16) | (d[o + 1] << 8) | d[o]
