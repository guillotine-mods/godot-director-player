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
## The three numbers `TextXtra::decodeXMED` is written in terms of: at most six
## ASCII hex digits of run length, and a run is text when at least four fifths of
## its bytes are printable. Named rather than inlined because the fraction is the
## whole of the heuristic — see `decode_xmed`.
const XMED_LEN_DIGITS := 6
const XMED_PRINTABLE_OF := 5
const XMED_PRINTABLE_IN := 4
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
## "name:type" -> lowest member number of that name *and* type. The reference's
## second name key; see `number_of_type`.
var _names_typed: Dictionary = {}
## Whether `_build_names` has run, which is **not** the same question as whether
## it found anything.
##
## The guard used to be `_names_lower.is_empty()`, so a library with no named
## members answered "not built yet" for ever and re-parsed every one of its
## `CASt` chunks on every single lookup. A name lookup that misses walks *all*
## the libraries (`preview/members.gd:resolve_ref`), so one miss re-scanned every
## nameless cast in the movie.
##
## Invisible until something asked often. Magic Hat asks on every rollover --
## `ItemMouseEnter` swaps the button to its `#active` member by name -- so moving
## the mouse across the main menu re-parsed whole cast libraries dozens of times
## a second and the title locked up. The engine had this all along; resolving
## `sprite(n).member = "name"` is what started asking.
var _names_built := false


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


## The child chunks one member owns, `{tag: chunk id}`, straight out of `KEY*`.
##
## `_parse_cast` picks a member's *payload* out of this by type, which is the
## right answer for the six types that have one and no answer at all for a type
## whose children are decided by the Xtra rather than by Director. A `text` Xtra
## owns an `XMED` and nothing in `TYPE_NAMES` says so; the reference finds it by
## walking the member's children and matching the tag
## (`lingo/xtras-cast/textxtra.cpp:TextXtraCastMember::load`, ScummVM 805f259a).
##
## Public because the survey that has to answer "is there anything behind this
## member" cannot get there any other way, and reaching into `_owned` from a tool
## would make the private name load-bearing outside this file.
func owned_chunks(chunk_id: int) -> Dictionary:
	return _owned.get(chunk_id, {})


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


## Move a member's registration point. `false` when the slot has no member.
##
## `the regPoint of member` is writable in Director and this cast is where the
## write has to land, because the registration point is the member's and every
## sprite drawn from it moves together -- `locH`/`locV` position the registration
## point rather than the top-left corner (`DIRECTOR_ENGINE.md` §8.10), so one
## write re-anchors eighteen channels at once. The reference's own writer is
## `BitmapCastMember::setField`'s `kTheRegPoint` arm
## (`castmember/bitmap.cpp` @ ScummVM 805f259a), which assigns `_regX`/`_regY`
## and sets `_modified`.
##
## **The argument is canvas space, and the stored offset is not.** ScummVM's
## `_regX` is the raw number the cast record carries — `getField(kTheRegPoint)`
## pushes it unchanged — while the offset the painter applies is
## `getRegistrationOffset()`, `_regX - _initialRect.left`. This port stores the
## *offset* (`_parse_specific`'s type-1 arm computes `regPoint - left/top`), so
## the translation happens here and `read_prop` puts it back on the way out.
## That is not a distinction without a difference in this corpus: **97,464 of
## 120,869 bitmap members across the six shipped titles and the two Itamar test
## corpora have a non-zero `initial_rect` origin** (`tools/scratch/regsurvey.gd`),
## so reading and writing the offset instead would move four members in five.
##
## **Written through the parsed cache, so it lasts exactly as long as the cast
## does.** `member()` hands out the cached dictionary itself and
## `DirectorCastTable.get_member` duplicates it per call, so a write here is seen
## by the next reader and by nothing that already ran. The cast is dropped when
## the movie changes (`director_preview.gd:lingo_go_movie` closes the table),
## which is the reference's lifetime for an *internal* cast — Director unloads it
## with the movie. A shared external cast outlives the movie there and does not
## here; nothing in this corpus writes a regPoint into an external cast, so that
## divergence is stated rather than measured.
func set_reg_point(number: int, reg_x: int, reg_y: int) -> bool:
	var m: Dictionary = member(number)
	if m.is_empty():
		return false
	var box: Dictionary = m.get("initial_rect", {})
	m["reg_offset_x"] = reg_x - int(box.get("left", 0))
	m["reg_offset_y"] = reg_y - int(box.get("top", 0))
	return true


## Member number for a name, case-insensitively, or 0 when there is none.
func number_of(name: String) -> int:
	_build_names()
	return int(_names_lower.get(name.to_lower(), 0))


## The same lookup restricted to one cast type, or 0.
##
## **A name is unique per type in Director, not per library.** The reference
## keeps two keys per named member -- `name` and `name:type` -- and
## `getCastMemberByNameAndType` picks between them on the type the caller asked
## for (`reference/scummvm/cast.cpp:174-186`, `rebuildCastNameCache` at 2448).
## `Movie::getCastMemberIDByNameAndType` is what every typed designator goes
## through, so `field "x"` asks for `x:3` and a member of another type sharing
## the name is simply not a candidate.
##
## Without this a typed designator has only the untyped answer to work with, and
## the untyped answer is the *lowest-numbered* member of that name whatever its
## type. `SLOTMACH.dir` is what that costs: member 83 is an Xtra named `credit`
## and member 97 is the field named `credit` the machine's own score draws, so
## `field "credit"` resolved to the Xtra, failed the type test and answered
## nothing. The handle then read `value(the text of field "credit")` as 0 on
## every pull and told the player they had not inserted a coin, while the coin
## slot's `put value(the text of field "credit") + 1 into field "credit"` wrote
## into the same nothing.
##
## Lowest number wins within the type, which is the reference's rule and the
## same one `_build_names` already applies untyped.
func number_of_type(name: String, type_code: int) -> int:
	_build_names()
	return int(_names_typed.get("%s:%d" % [name.to_lower(), type_code], 0))


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
	if _names_built:
		return
	_names_built = true
	for number in member_numbers():
		var m := member(number)
		var name := str(m.get("name", ""))
		if name != "":
			# First writer wins: duplicate names exist and Director resolves to
			# the lowest member number.
			var key := name.to_lower()
			if not _names_lower.has(key):
				_names_lower[key] = number
			# The second key the reference keeps, for the typed designators.
			# Built in the same walk because the walk is the expensive half:
			# `_build_names` parses every `CASt` record in the library, and doing
			# it twice would double the cost this cache exists to avoid.
			var typed := "%s:%d" % [key, int(m.get("type", 0))]
			if not _names_typed.has(typed):
				_names_typed[typed] = number


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
		# `XtraCastMember::promote` looks the member's symbol up in
		# `xtraCastMemberProtos` and hands it to whichever class registered that
		# name; anything unregistered stays an `XtraCastMember`. Of the five
		# symbols in this tree only `text` is in that table, so this is the whole
		# of the promotion surface here — and the reason 555 of the corpus's 566
		# Xtra members correctly get nothing.
		if str(out.get("xtra_symbol", "")).to_lower() == "text":
			_promote_text_xtra(out, chunk_id)

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
	# header. `sound_header_chunk_id` is reported alongside so
	# `director/director_sound.gd` can tell which shape it has.
	#
	# **The `sndH`/`sndS` pair wins over a `snd ` child, and the order used to be
	# the other way round.** `castmember/sound.cpp:SoundCastMember::load()` walks
	# *all* the children for D6+: a `sndH` and a `sndS` are loaded into one
	# decoder, and `if (sndFormat) { _audio = sndFormat; return; }` returns on the
	# pair before the `snd ` resource is ever opened. Only when no pair was seen
	# does it fall through to `getResource(tag, sndId)`, and only then does the
	# empty-payload branch below matter.
	#
	# This was `["snd ", "sndS", "sndH"]`, first match wins, and it cost the port
	# every sound member it has. Piposh 1's containers carry a **zero-length
	# `snd ` chunk beside a real pair**, so the engine took the empty one and the
	# member decoded to nothing: `PIANO.dir` #8 `PIANOKEY` has 16,384 bytes of
	# samples under `sndS` and answered 0, and `DAY1.dir`'s `ATTIC_DO`,
	# `SHOWER_O` and `POURING_` have 126,600, 138,538 and 342,934. All 17 of that
	# title's sound members failed, in the same way, for the same reason
	# (`tools/sound_member_census.gd`).
	#
	# **The claim that this was unexercised was about Piposh 2, not about the
	# corpus.** It read "this game has no sound cast member at all, in any of its
	# 86 containers", and the same sentence is in AGENTS.md, `ENGINE_TODO.md` and
	# `scenes/preview/media.gd`. Piposh 2 has none; the corpus has **204**
	# (`tools/member_type_census.gd`): 87 in `itamar-magichat`, 66 in
	# `itamar-park`, 17 each in `piposh`, `piposh-en` and `piposh-ru`. A
	# measurement of one title written down as a fact about eight is how a decoder
	# stays unexercised while its input sits in the tree.
	#
	# A zero-byte payload is not corruption. The reference treats
	# `sndData->size() == 0` as "the audio is a **linked** file" and loads it from
	# the path in the member's info block. **That fallback is implemented now** --
	# `preview/sound.gd:play_member` hands the name to
	# `AudioDirector.play_linked_member`, which is the same resolver
	# `sound playFile` goes through. The empty tag is still skipped rather than
	# preferred, so `data_chunk_id` never names a chunk with nothing in it.
	#
	# Two keys come out of it, and the difference matters. `sound_linked_empty` is
	# the reference's *zero-byte* arm specifically -- a `snd ` chunk that exists and
	# holds nothing -- and is kept because it is the shape Piposh 1's containers
	# carry and the one that cost this port every sound member it had.
	# `sound_linked` is the question a player asks: **this member has no payload
	# this engine can decode and does name an external file**, which is the union of
	# the reference's "absent *or* zero bytes" test with a non-empty
	# `getLinkedPath`. 54 of `itamar-park`'s 66 sound members reach it, and every
	# one of those reaches it through the *absent* arm rather than the zero-byte one
	# (`tools/sound_member_census.gd`): that title writes no `snd ` chunk at all for
	# a linked member, so a fallback keyed on `sound_linked_empty` alone would have
	# played none of them.
	if type_code == 6:
		var sound_owned: Dictionary = _owned.get(chunk_id, {})
		var header_id := int(sound_owned.get("sndH", -1))
		var samples_id := int(sound_owned.get("sndS", -1))
		var resource_id := int(sound_owned.get("snd ", -1))
		# Size, not presence: a tag whose chunk is empty is not a payload. Asking
		# the container costs one `mmap` lookup and is the only thing that
		# separates this corpus's real pair from the empty `snd ` sitting beside
		# it.
		var empty_resource := resource_id >= 0 and _chunk_is_empty(resource_id)
		if samples_id >= 0:
			out["data_chunk_id"] = samples_id
			out["sound_tag"] = "sndS"
		elif resource_id >= 0 and not empty_resource:
			out["data_chunk_id"] = resource_id
			out["sound_tag"] = "snd "
		elif header_id >= 0:
			out["data_chunk_id"] = header_id
			out["sound_tag"] = "sndH"
		elif resource_id >= 0:
			out["data_chunk_id"] = resource_id
			out["sound_tag"] = "snd "
		out["sound_header_chunk_id"] = header_id
		# The cue points, which are **not** in the audio. Director 6 writes them to a
		# `cupt` child of the member -- an `int32` count, then per cue an `int32`
		# position and a fixed 32-byte name -- and
		# `castmember/sound.cpp:SoundCastMember::load()` reads that arm alongside
		# `sndH`/`sndS`/`snd `/`ediM`. `director_sound.gd:cue_points` was reading
		# markers out of an embedded AIFF only, which is the one shape of the four
		# that can carry them inline, so `the cuePointNames`, `the cuePointTimes`,
		# `cuePassed` and a tempo cell waiting on a cue index all answered nothing for
		# every member authored the ordinary way.
		out["sound_cue_chunk_id"] = int(sound_owned.get("cupt", -1))
		out["sound_linked_empty"] = empty_resource and samples_id < 0
		# `_chunk_is_empty` and not `< 0`, because the last-resort arm above hands
		# `data_chunk_id` a zero-byte `snd ` when that is the only tag the member
		# owns -- which is exactly the state the reference calls linked.
		var payload_id := int(out.get("data_chunk_id", -1))
		out["sound_linked"] = (payload_id < 0 or _chunk_is_empty(payload_id)) \
			and str(out.get("link_filename", "")) != ""
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
	# Items 2 and 3 are the **linked file** a member draws its media from: the
	# directory it was imported from and the file's own name, both Pascal strings
	# (`cast.cpp:loadCastInfo`, `ci->directory` and `ci->fileName`, ScummVM
	# 805f259a). Positional in exactly the same way as the three below, so they
	# are read here for any member whose table is long enough, and consumed only
	# where they mean something -- `preview/media.gd` reads them for a
	# `#digitalVideo`.
	#
	# Only the **filename** is usable, and the directory deliberately is not:
	# `logo.dir` #28 records `G:\magic\logo`, which is the drive letter of the
	# machine the title was authored on. Director resolved linked media the way it
	# resolved a linked movie -- beside the movie that named it, then along the
	# search path -- and `DirectorPaths` is that rule. The directory is carried
	# rather than dropped because it is evidence, not because anything follows it.
	var directory: PackedByteArray = item.call(2)
	if directory.size() >= 1 and int(directory[0]) + 1 <= directory.size():
		out["link_directory"] = _text(directory.slice(1, 1 + int(directory[0])))
	var link: PackedByteArray = item.call(3)
	if link.size() >= 1 and int(link[0]) + 1 <= link.size():
		out["link_filename"] = _text(link.slice(1, 1 + int(link[0])))
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
		10:
			# A digital video member: eight bytes of rect and one flag word, and
			# that is the whole record.
			#
			# `castmember/digitalvideo.cpp:DigitalVideoCastMember()` reads exactly
			# that -- `Movie::readRect(stream)` then `stream.readUint32()` -- and
			# its own `getCastDataSize()` states the D5..D10 size as `8 + 4`.
			# Cited at ScummVM 805f259a.
			#
			# **Measured, on the two samples `docs/ENGINE_TODO.md` was waiting
			# for.** `test-games/itamar-magichat/logo/logo.dir` #27 `prelogo` and
			# #28 `logo` both carry a specific block of exactly 12 bytes, and both
			# decode to top 0, left 0, bottom 480, right 640. Three things outside
			# this decode agree with that size and none of them is derived from it:
			#
			#   * the media. `logo.avi`'s `BITMAPINFOHEADER` says 640x480, and so
			#     do `avih`'s `dwWidth`/`dwHeight` and the video stream's `rcFrame`
			#     (`tools/avi_decode.gd`).
			#   * the score. `logo.dir` channel 3 places member 28 with a recorded
			#     width and height of 640x480.
			#   * the stage. That sprite's `loc` is (400,300) on an 800x600 stage,
			#     which is its centre -- and the reference registers a digital
			#     video at the **centre** of its rect
			#     (`DigitalVideoCastMember::getRegistrationOffset`: `width / 2`,
			#     `height / 2`), so a 640x480 picture anchored there lands at
			#     (80,60) and fills the middle of the stage exactly. A corner
			#     registration would put its top-left at (400,300) and hang three
			#     quarters of it off the bottom-right.
			#
			# A wrong offset into these twelve bytes does not produce four
			# agreements.
			if spec.size() < 12:
				return
			var dt := _be_i16(spec, 0)
			var dl := _be_i16(spec, 2)
			var db := _be_i16(spec, 4)
			var dr := _be_i16(spec, 6)
			out["width"] = dr - dl
			out["height"] = db - dt
			out["initial_rect"] = {"top": dt, "left": dl, "bottom": db, "right": dr}
			# The centre, per the reference's override above. Stored as an offset
			# from the rect's own origin, which is this port's convention for every
			# type (see `set_reg_point`), so it is half the size rather than half
			# the size plus the origin.
			out["reg_offset_x"] = int((dr - dl) / 2.0)
			out["reg_offset_y"] = int((db - dt) / 2.0)
			var vflags := _be_u32(spec, 8)
			out["video_flags"] = vflags
			# The Digital Video dialog's tick boxes, one bit each, in the
			# reference's own order and with its own polarity -- `video` and `crop`
			# are stored **inverted**, and reproducing that is the difference
			# between "crop to the sprite rect" and "scale to it" for every member
			# of the type. `logo` reads 0x2A: directToStage on, sound on, video on,
			# scale to fit, no controller, no loop, not paused at start, no
			# preload.
			#
			# These are the eleven names `preview/media.gd:MEMBER_DEFAULTS` has
			# been answering Director's *dialog defaults* for, with its own header
			# saying so and saying it could not do better without a sample. It can
			# now: a member the author changed reads back what the author set.
			out["dv_frame_rate"] = (vflags >> 24) & 0xFF
			# Bit 0x0800 says the frame-rate byte means something; without it the
			# member plays at the media's own rate, which is the reference's
			# `kFrameRateDefault`. The two bits above it choose between Director's
			# fixed, maximum and synchronised modes.
			out["dv_frame_rate_type"] = \
				((vflags & 0x3000) >> 12) if (vflags & 0x0800) != 0 else 0
			out["dv_quicktime"] = (vflags & 0x8000) != 0
			out["dv_avi"] = (vflags & 0x4000) != 0
			out["preload"] = (vflags & 0x0400) != 0
			out["video"] = (vflags & 0x0200) == 0
			out["paused_at_start"] = (vflags & 0x0100) != 0
			out["controller"] = (vflags & 0x0040) != 0
			out["direct_to_stage"] = (vflags & 0x0020) != 0
			out["looping"] = (vflags & 0x0010) != 0
			out["sound"] = (vflags & 0x0008) != 0
			out["crop"] = (vflags & 0x0002) == 0
			out["center"] = (vflags & 0x0001) != 0
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
			_apply_text_xtra_rect(
				out, spec.slice(8 + symbol_len,
					mini(8 + symbol_len + data_len, spec.size())))
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
## The `text` Xtra's size, which is in the Xtra's own payload and nowhere else.
##
## **This is why all eleven `text` Xtra members in the tree carry a 0x0
## `xtraRect`, and the zero is not a decode gap.** `_apply_xtra_rect` above reads
## item 12 of the *info* block, which is where Director puts geometry for the
## Xtras that have it there; the `text` Xtra puts its own somewhere else, and the
## reference reads it from the payload without consulting the info rect at all
## (`lingo/xtras-cast/textxtra.cpp:TextXtra::parseXtraData`, ScummVM 805f259a):
## a big-endian int32 height at offset 36 and a width at 40, refused outright
## below 44 bytes of payload or outside `1..0x4000` on either axis. Those bounds
## are the reference's, copied because a payload that fails them is one this
## reading does not understand, and inventing a size from it would be worse than
## leaving the member sizeless.
##
## Measured by `tools/text_xtra_members.gd --all` over all eight roots: **all
## eleven** members with symbol `text` carry a payload that passes, and the sizes
## are the shapes of the things they name -- `SLOTMACH.dir` #83 `credit` is
## 60x23, a credit readout; `HEZSAVE.DIR` and `AIR1.dir` #118 `temporary` are
## 300x45 and 300x64; `MAP.dir` #12 and #17 are 300x560 and 300x160;
## `piposh-dream`'s three maze members are 457x496, 457x372 and 457x496; and
## `rating ARCADE1.dir` #136 `objectsfound includ :` is 360x144. Eleven of eleven
## landing in that range is what says offsets 36 and 40 are the right two.
##
## **No registration point is derived from it**, unlike the info-block rect. The
## reference builds `Common::Rect(w, h)`, whose origin is (0,0), so the
## registration offset stays the zero `_parse_cast` already put there.
##
## Applied for the symbol the reference promotes and no other. `promote` hands a
## `text` Xtra to `TextXtra` and everything else to `XtraCastMember`, which never
## looks at its payload, so reading these four bytes out of a Flash movie's
## private serialisation would be reading noise.
##
## **Nothing in this corpus is placed on a sprite**, so this changes no pixel: the
## same survey reports 0 of the 11 named by any score record in any container of
## any root. What it changes is what `the width of member` and `the height of
## member` answer, which was 0 for every one of them and is now the authored size.
func _apply_text_xtra_rect(out: Dictionary, payload: PackedByteArray) -> void:
	if str(out.get("xtra_symbol", "")).to_lower() != "text":
		return
	if payload.size() < 44:
		return
	var h := _be_i32(payload, 36)
	var w := _be_i32(payload, 40)
	if w <= 0 or h <= 0 or w > 0x4000 or h > 0x4000:
		return
	out["width"] = w
	out["height"] = h
	out["initial_rect"] = {"top": 0, "left": 0, "bottom": h, "right": w}
	out["xtra_text_rect"] = true


func _apply_xtra_rect(out: Dictionary) -> void:
	# The `text` Xtra already answered from its payload, which is the only place
	# the reference looks for one. An info rect would not be a second opinion, it
	# would be a different member's convention applied to this one.
	if bool(out.get("xtra_text_rect", false)):
		return
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


## Promote a `text` Xtra member the way `XtraCastMember::promote` does: give it
## the text of its `XMED` child, and let it keep its type.
##
## **The type is the load-bearing half and it is deliberately unchanged.**
## `TextXtraCastMember`'s constructor sets `_type = kCastXtra` with the comment
## "Not kCastText: the engine casts kCastText members to TextCastMember"
## (`lingo/xtras-cast/textxtra.cpp`, ScummVM 805f259a). That is what keeps
## `Cast::rebuildCastNameCache` keying `SLOTMACH.dir`'s promoted `credit` as
## `credit:15`, so `field "credit"` -- which goes through
## `getCastMemberByNameAndType` asking for `credit:3` -- still cannot see it and
## still resolves to the *field* #97 the slot machine's score draws. That is
## `02844f93`'s fix and this must not spend it: a port that promoted these into
## type-3 members would put the "you have not inserted money" bug back, because
## `value(the text of field "credit")` would read the Xtra's text instead of the
## field's. `tools/text_xtra_members.gd` asserts it in both directions -- the
## untyped lookup answers 83 and the typed field lookup answers 97 -- and does so
## generically, over every text Xtra in the tree that shares a name with a field.
##
## So nothing here touches `type`, `type_name` or `drawing`. What is added is the
## text, and one thing more: the reference's `getField(kTheCastType)` answers the
## **symbol `#text`** for a promoted member while its `_type` stays `kCastXtra`,
## which is the one place the two readings of "type" differ. `promoted_type_name`
## carries that second reading for `scenes/preview/members.gd:read_prop` and is
## kept beside `type_name` rather than replacing it, because `type_name` is what
## `DRAWING_TYPES`, the name cache and every survey in `tools/` are keyed on.
##
## **The one thing this does not do is draw.** The reference's
## `TextXtraCastMember::createWidget` builds a `Graphics::MacText`, so a promoted
## member placed on a sprite is drawn there; here `sprite_art.gd:texture_for`
## still answers null for type 15. That is a real remaining gap and it is stated
## rather than hidden -- it costs nothing measurable in this tree, because **0 of
## the 11 are named by any sprite record in any frame of any container of any
## root** (`tools/text_xtra_members.gd`), and it will cost the first title that
## places one.
func _promote_text_xtra(out: Dictionary, chunk_id: int) -> void:
	out["promoted_type_name"] = "text"
	# `TextXtraCastMember::load()` finds the payload by walking the member's own
	# children for the `XMED` tag rather than by asking the type what tag it owns,
	# which is why this cannot go through `_parse_cast`'s `want` table: nothing in
	# `TYPE_NAMES` says an Xtra owns an `XMED`, and which tag it owns is the
	# Xtra's decision rather than Director's.
	var xmed := int((_owned.get(chunk_id, {}) as Dictionary).get("XMED", -1))
	out["xmed_chunk_id"] = xmed
	if xmed < 0:
		return
	var raw := decode_xmed(file.read_chunk(xmed))
	# An empty answer is "not decoded" and never "decoded to nothing": the
	# reference refuses a zero length outright, so a run it accepts is at least
	# one byte long.
	out["xtra_text_decoded"] = not raw.is_empty()
	if not raw.is_empty():
		out["text"] = _text(raw)


## The text inside an `XMED` chunk, or empty bytes when there is none to be had.
##
## `XMED` is the serialised document of the Hermes **Paige** text engine, which is
## what the `text` Xtra is, and it is not a Director format: Director stores the
## chunk and never looks inside it. The whole of what is known about the layout is
## `TextXtra::decodeXMED` (`lingo/xtras-cast/textxtra.cpp`, ScummVM 805f259a --
## **not part of the vendored subset under `reference/scummvm/`**, fetched at that
## revision to write this), and what it knows is deliberately little:
##
##   * the chunk opens with the four ASCII bytes `FFFF`;
##   * the body is mostly ASCII hex -- record tags and lengths written as digits;
##   * a **literal run** is introduced by a `0x00` byte, then up to six ASCII hex
##     digits giving its length, then a `,`, then that many raw bytes;
##   * the first literal run that is at least four-fifths printable is the text.
##
## The last rule is the whole of the heuristic and it is doing real work rather
## than being a safety net. `SLOTMACH.dir` #83's chunk holds a 64-byte run at
## offset 487 whose content is `05 e7 f8 ee e5 ef 00 00 ...` -- a Pascal string in
## a fixed 64-byte buffer, the font name `קרמון` -- and 5 printable bytes in 64
## fails the test by a wide margin, which is what stops the member's *font* being
## returned as its *text*. Nothing else in the format distinguishes the two runs.
##
## Printable here is the reference's definition and not a narrower one: ASCII
## `0x20..0x7e`, **anything at or above `0x80`**, and the three whitespace control
## codes. The `>= 0x80` arm is not optional in this corpus -- five of the eleven
## members are Hebrew, in the title's own codepage, and every byte of their text
## is above 0x7f.
##
## **The scan starts at the beginning and takes the first run that passes**, which
## is what makes it deterministic on files with several. Measured over all eleven
## `text` Xtra members in the tree (`tools/text_xtra_members.gd --all`): eleven
## chunks, eleven decodes, and the first passing run is the authored text in all
## eleven -- `SLOTMACH`/`Slotmach` #83 `credit` is the single character `0`, the
## three `piposh-dream` maze members are a 437-byte Lingo scratchpad beginning
## `pathx=[]`, `HEZSAVE.DIR`/`AIR1.dir` #118 `temporary` are 98 bytes of
## `put the moviepath & "sounds:s_day1:" into tlkpath`, `MAP.dir` #12 is a
## 455-byte table of room names and coordinates, #17 is 192 bytes of the same
## commented out, and `rating`'s `objectsfound includ :` is its 131-byte checklist.
##
## The result is handed back as **bytes**, not as a `String`, so that the caller
## puts it through `_text` and the title's own codepage the same way every other
## member's text goes -- the reference does the same thing one step later,
## building `U32String(text, g_director->getPlatformEncoding())`.
##
## Static and public: `tools/text_xtra_members.gd` re-derives the same runs from
## its own copy of this, so the harness and the engine are two readings of the
## same bytes and can disagree.
static func decode_xmed(data: PackedByteArray) -> PackedByteArray:
	var size := data.size()
	# `FFFF`, as four ASCII characters rather than as a 16-bit sentinel.
	if size < 4 or data[0] != 0x46 or data[1] != 0x46 \
			or data[2] != 0x46 or data[3] != 0x46:
		return PackedByteArray()
	var i := 0
	while i + 2 < size:
		if data[i] != 0x00:
			i += 1
			continue
		var j := i + 1
		var length := 0
		var digits := 0
		while j < size and _is_hex_digit(data[j]) and digits < XMED_LEN_DIGITS:
			length = length * 16 + _hex_value(data[j])
			j += 1
			digits += 1
		# `,` is the separator, and a run that does not have one here is not a run
		# -- a `0x00` byte occurs all over a Paige document.
		if digits == 0 or length == 0 or j >= size or data[j] != 0x2C:
			i += 1
			continue
		j += 1
		if j + length > size:
			i += 1
			continue
		var printable := 0
		for k in length:
			var c := data[j + k]
			if (c >= 0x20 and c <= 0x7E) or c >= 0x80 \
					or c == 0x0D or c == 0x0A or c == 0x09:
				printable += 1
		if printable * XMED_PRINTABLE_OF < length * XMED_PRINTABLE_IN:
			i += 1
			continue
		return data.slice(j, j + length)
	return PackedByteArray()


static func _is_hex_digit(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x46) \
		or (c >= 0x61 and c <= 0x66)


static func _hex_value(c: int) -> int:
	if c <= 0x39:
		return c - 0x30
	if c <= 0x46:
		return c - 0x41 + 10
	return c - 0x61 + 10


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
## Does this chunk id address a payload of no bytes?
##
## Read from the memory map rather than by loading the chunk, because the only
## caller asks it about every sound member in a library and the answer is one
## field of a record `director_file.gd` already parsed at open time. A missing or
## out-of-range id counts as empty: the caller is choosing between payloads, and
## one it cannot address is not a payload it can choose.
func _chunk_is_empty(id: int) -> bool:
	if id < 0 or id >= file.chunks.size():
		return true
	return int(file.chunks[id].get("size", 0)) <= 0


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
