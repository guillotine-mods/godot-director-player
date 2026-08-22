class_name DirectorLscr
extends RefCounted
## Director's **compiled** Lingo: the `Lnam` name table, the `Lctx` script
## context, and the `Lscr` script chunks their indices reach.
##
## The rest of this port runs Lingo from the **source text** in a cast member's
## info block (`director_cast.gd`, info item 0), and for every container under
## `games/` that is enough -- all six titles ship unprotected `.dir`/`.cst`, so
## the text is there. This file exists for the case the source text is *not*
## there: a **protected** movie (`.dxr`/`.cxt`/`.dcr`) ships the bytecode with
## the source stripped, and for one of those the source-text path recovers no
## Lingo at all. The Movie-In-A-Window code in this corpus names
## `window("joke.dxr")`, so the original discs shipped protected builds; one will
## eventually be handed to this engine and there is nothing else to read then.
##
## `docs/LSCR_FORMAT.md` is the specification this implements and every offset
## below is its. Where it disagrees with ScummVM it says so and it is right: the
## three version-dependent quantities (literal record stride, handler record
## stride, operand divisor) follow ProjectorRays, because ScummVM conflates two
## of them under one `constEntrySize` and has no `divisor == 1` arm at all. This
## corpus contains both 700 and 850 containers, so the difference is live rather
## than theoretical -- `games/piposh2/PIP2DATA/DAY1.dir` states `0x73A` and its
## handler records are 46 bytes, while `BYAIR.cst` states `0x57E` and its are 42.
##
## **All three chunks are big-endian whatever the container is.** `MASTER.CST`
## begins with the little-endian magic `XFIR` and stores its mmap tags reversed,
## and its `Lscr` header only decodes big-endian. So this file never asks
## `DirectorFile.big_endian`; it reads the payload bytes itself.
##
## ## Sizes are detected, not assumed
##
## The version word lives in the movie's `DRCF`/`VWCF` chunk and **an external
## cast has no config chunk at all**, so a `.cst`/`.cxt` cannot state its own
## version. Rather than requiring the owning movie to be found first, the three
## sizes are *derived from the chunk's own arithmetic* and the version is used
## only as the starting guess and as a cross-check:
##
## - **literal record stride** -- `literalsOffset + count * stride` must land
##   exactly on `literalsDataOffset`. 8 or 6, and the test is exact.
## - **handler record stride** -- every record satisfies
##   `argumentOffset == compiledOffset + compiledLength` and
##   `localsOffset == argumentOffset + argumentCount * 2`, and consecutive
##   records satisfy `next.compiledOffset == prev.lineOffset + prev.lineCount`
##   (+1 for 2-byte alignment). 42 or 46, scored over every record.
## - **operand divisor** -- 1 when the handler stride is 46 (that is what 850
##   means), else 8 when the literal stride is 8, else 6.
##
## `tools/lscr_layout.gd` asserts the detected sizes against the version-derived
## ones over every container that *does* state a version, which is what keeps the
## detection honest where it can be checked and lets it stand where it cannot.

const Codepage := preload("res://director/director_codepage.gd")

## `Lscr` header length, `hexdump(0x5c)` in `compileLingoV4`.
const LSCR_HEADER := 92
## `Lctx` header length, `hexdump(0x2a)` in `Cast::loadLingoContext`.
const LCTX_HEADER := 42
## One `Lctx` entry.
const LCTX_ENTRY := 12
## `Lnam`'s minimum header, `0x14`.
const LNAM_HEADER := 20

## `scriptFlags` bits, `reference/scummvm/types.h:86`. Bit numbers are shift
## counts, so `kScriptFlagFactoryDef` is `1 << 0x4`.
const FLAG_UNUSED := 1 << 0x0
const FLAG_FACTORY_DEF := 1 << 0x4
const FLAG_EVENT_SCRIPT := 1 << 0x9

## Every name in the context's `Lnam`, in index order.
var names: PackedStringArray = PackedStringArray()
## One entry per `Lctx` slot, in slot order: `{chunk_id, flags, unused}`.
## `chunk_id` is `-1` for an empty slot. **The array is 0-based and `script_id`
## is 1-based** -- see `chunk_for_script_id`, which is the only thing that should
## index it.
var entries: Array[Dictionary] = []
## Every `Lscr` chunk id in mmap order. The fallback mapping for a container that
## has script chunks and no `Lctx`, and `MASTER.CST` is one.
var script_chunks: Array[int] = []
## The container's stated file version, raw (`0x57E`), and humanized (700).
## Zero for an external cast, which carries no config chunk.
var raw_version := 0
var human := 0
## True when the `script_id` -> chunk mapping came from mmap order rather than
## from an `Lctx`. Callers that care about confidence should report it:
## `docs/LSCR_FORMAT.md` section 2 marks the fallback MEASURED-ONLY.
var mmap_fallback := false
var error := ""

var _file = null
var _lnam_id := -1
var _lctx_id := -1


## Indexes the container's Lingo context. False when it holds no compiled Lingo
## at all, which is not an error -- `error` says which of the two it was.
##
## `version` overrides the container's own `DRCF` word, for an external cast
## whose owning movie states one. Left at -1 the config chunk is read, and a
## container with none decodes from its own arithmetic (see the class comment).
func open(container, version: int = -1) -> bool:
	error = ""
	names = PackedStringArray()
	entries.clear()
	script_chunks.clear()
	mmap_fallback = false
	_file = container
	_lnam_id = -1
	_lctx_id = -1
	if container == null:
		error = "no container"
		return false

	raw_version = version if version >= 0 else _read_raw_version(container)
	human = human_version(raw_version)

	for id in _ids_matching("lscr"):
		script_chunks.append(id)
	var lctx_ids := _ids_matching("lctx")
	var lnam_ids := _ids_matching("lnam")
	if script_chunks.is_empty() and lctx_ids.is_empty() and lnam_ids.is_empty():
		error = "no compiled Lingo in this container"
		return false

	if not lctx_ids.is_empty():
		_lctx_id = int(lctx_ids[0])
		if not _read_context(_lctx_id):
			return false
	else:
		# A container can carry `Lscr` chunks and no `Lctx`, and neither
		# reference handles it -- ScummVM only ever reaches `addCodeV4` from
		# `loadLingoContext`, so it finds no scripts at all in such a file.
		# `games/piposh2/MASTER.CST` is one, with 40 script chunks, one `Lnam`
		# and no context in either tag spelling, and it is the cast that owns the
		# globals and the inventory HUD. `script_id N` -> the N-th `Lscr` in mmap
		# order is what its ids say (1..40 against consecutive chunks 528..567)
		# and it is the only mapping available.
		mmap_fallback = true

	if _lnam_id < 0 and not lnam_ids.is_empty():
		_lnam_id = int(lnam_ids[0])
	if _lnam_id >= 0:
		_read_names(_lnam_id)
	return true


## The `Lscr` chunk a cast member's `script_id` names, or -1.
##
## Two levels of indirection and a 1-based index, which is the trap this exists
## to hold in one place: `script_id` is **not** a chunk id, it is a 1-based index
## into the `Lctx` entry array whose `+4` field is the chunk id. ScummVM loops
## `for (i = 1; i <= itemCount; i++)` into `entries[i - 1]`, ProjectorRays does
## the same. `script_id == 0` means the member carries no script.
##
## The `scriptNumber` word inside the `Lscr` header is deliberately not used for
## this: ScummVM reads it and throws it away with a named counterexample (script
## 261 of `DATA/LEVEL1.DIR` in *betterd-win* stores 263). The `Lctx` index is
## authoritative.
func chunk_for_script_id(script_id: int) -> int:
	if script_id <= 0:
		return -1
	if mmap_fallback:
		if script_id > script_chunks.size():
			return -1
		return script_chunks[script_id - 1]
	var index := script_id - 1
	if index >= entries.size():
		return -1
	var entry: Dictionary = entries[index]
	# An entry on the free list holds a stale chunk id: ScummVM compiles only
	# `!unused && chunkId >= 0`. Skipping it is the difference between running
	# the author's script and running whatever occupied the slot before it.
	if bool(entry.get("unused", false)):
		return -1
	return int(entry.get("chunk_id", -1))


## A name by `Lnam` index. Out of range yields "", which callers turn into a
## synthetic `arg_<n>` / `var_<n>` the way ScummVM does rather than failing the
## handler.
func name_at(index: int) -> String:
	if index < 0 or index >= names.size():
		return ""
	return names[index]


## One `Lscr` chunk, fully decoded: header, literals, property and global name
## lists, and every handler record with its bytecode and its three name lists.
##
## The bytecode itself is handed back as bytes; turning it into instructions is
## `lingo/compile/lscr_disasm.gd` and turning those into the port's AST is
## `lingo/compile/lscr_lower.gd`. The split is deliberate -- everything in this
## file is a fixed-shape table read, and everything past it is inference.
##
## `{}` with the reason in `error` when the chunk is unreadable. A script whose
## `kScriptFlagUnused` bit is set returns `{}` too, because ScummVM returns null
## for it and a decoder that ran it would run something the author deleted.
func read_script(chunk_id: int) -> Dictionary:
	error = ""
	if _file == null:
		error = "no container"
		return {}
	var d: PackedByteArray = _file.read_chunk(chunk_id)
	if d.size() < LSCR_HEADER:
		error = "chunk %d is %d bytes, shorter than the 92-byte Lscr header" % [chunk_id, d.size()]
		return {}

	var out := {
		"chunk_id": chunk_id,
		"total_length": _u32(d, 8),
		"code_store_offset": _u16(d, 16),
		"script_number": _u16(d, 18),
		"parent_number": _i16(d, 22),
		"flags": _u32(d, 38),
		"factory_name_id": _i16(d, 48),
		"event_map_count": _u16(d, 50),
		"event_map_offset": _u32(d, 52),
		"event_map_flags": _u32(d, 56),
	}
	var flags := int(out["flags"])
	if (flags & FLAG_UNUSED) != 0:
		error = "chunk %d has kScriptFlagUnused set" % chunk_id
		return {}
	out["is_factory"] = (flags & FLAG_FACTORY_DEF) != 0
	out["is_event_script"] = (flags & FLAG_EVENT_SCRIPT) != 0
	out["factory_name"] = name_at(int(out["factory_name_id"]))

	# Property and global name lists: flat arrays of i16 `Lnam` indices. `-1`
	# terminates the property list early; an out-of-range index is skipped with a
	# warning in the reference, and dropped here for the same reason.
	#
	# ProjectorRays drops a property literally named `me` from a factory's list.
	# Reproduced, or a decoded factory grows a `property me` its source never had.
	out["properties"] = _name_list(d, _u32(d, 62), _u16(d, 60), true, bool(out["is_factory"]))
	out["globals"] = _name_list(d, _u32(d, 68), _u16(d, 66), false, false)

	var literal_stride := _detect_literal_stride(d)
	out["literal_stride"] = literal_stride
	out["literals"] = _read_literals(
		d, _u32(d, 80), _u16(d, 78), _u32(d, 88), _u32(d, 84), literal_stride)

	var handler_count := _u16(d, 72)
	var handler_at := _u32(d, 74)
	var handler_stride := _detect_handler_stride(d, handler_at, handler_count)
	out["handler_stride"] = handler_stride
	# One quantity, two operand kinds. ProjectorRays applies
	# `variableMultiplier()` to `pushcons` operands *and* to
	# `getparam`/`getlocal`/`setparam`/`setlocal`; do not grow a second divisor.
	out["divisor"] = 1 if handler_stride == 46 else (8 if literal_stride == 8 else 6)
	out["handlers"] = _read_handlers(
		d, handler_at, handler_count, handler_stride, bool(out["is_factory"]))

	var slots: Array[int] = []
	var map_at := int(out["event_map_offset"])
	for i in int(out["event_map_count"]):
		if map_at + i * 2 + 2 <= d.size():
			slots.append(_i16(d, map_at + i * 2))
	out["event_map"] = slots
	return out


## Every script this context reaches, as `script_id -> chunk_id`. Only slots that
## are in use and hold a chunk.
func live_scripts() -> Dictionary:
	var out := {}
	var count := script_chunks.size() if mmap_fallback else entries.size()
	for i in count:
		var chunk := chunk_for_script_id(i + 1)
		if chunk >= 0:
			out[i + 1] = chunk
	return out


## ScummVM's ladder, `reference/scummvm/util.cpp:1316`, with the rungs from
## `types.h:362`. **The corpus states `0x57E`, which humanizes to 700, not 500** --
## the "D5 layout" phrase everywhere else in this repo is about the *cast member*
## reader, whose branch is at `>= 0x4B1`, and reading it as the Lingo version
## sends you to compare 700 against `kFileVer500`.
static func human_version(raw: int) -> int:
	if raw >= 0x79F:
		return 1200
	if raw >= 0x782:
		return 1150
	if raw >= 0x781:
		return 1100
	if raw >= 0x73B:
		return 1000
	if raw >= 0x6A4:
		return 850
	if raw >= 0x582:
		return 800
	if raw >= 0x4C8:
		return 700
	if raw >= 0x4C2:
		return 600
	if raw >= 0x4B1:
		return 500
	if raw >= 0x45D:
		return 404
	if raw >= 0x45B:
		return 400
	if raw >= 0x405:
		return 310
	if raw >= 0x404:
		return 300
	if raw >= 0x400:
		return 200
	return 100


## What the version *says* the three sizes are, for cross-checking the detected
## ones. `{literal, handler, divisor}`.
static func sizes_for(humanized: int) -> Dictionary:
	if humanized >= 850:
		return {"literal": 8, "handler": 46, "divisor": 1}
	if humanized >= 500:
		return {"literal": 8, "handler": 42, "divisor": 8}
	return {"literal": 6, "handler": 42, "divisor": 6}


# --- Lnam ------------------------------------------------------------------

func _read_names(chunk_id: int) -> void:
	var d: PackedByteArray = _file.read_chunk(chunk_id)
	if d.size() < LNAM_HEADER:
		return
	var at := _u16(d, 16)
	var count := _u16(d, 18)
	for _i in count:
		if at >= d.size():
			break
		var length: int = d[at]
		at += 1
		if at + length > d.size():
			break
		# Through the container's code page, not `get_string_from_ascii`. A
		# Hebrew or Russian handler name is bytes in the authoring machine's
		# script system and Latin-1 pass-through corrupts it -- and a corrupted
		# handler name is a handler the interpreter never finds.
		names.append(Codepage.decode(d.slice(at, at + length)))
		at += length


# --- Lctx ------------------------------------------------------------------

func _read_context(chunk_id: int) -> bool:
	var d: PackedByteArray = _file.read_chunk(chunk_id)
	if d.size() < LCTX_HEADER:
		error = "Lctx chunk %d is %d bytes, shorter than its 42-byte header" % [
			chunk_id, d.size()]
		return false
	var count := _i32(d, 8)
	var at := _u16(d, 16)
	_lnam_id = _i32(d, 32)
	var first_unused := _i16(d, 40)
	if count < 0 or at < 0 or at + count * LCTX_ENTRY > d.size():
		error = "Lctx chunk %d claims %d entries at %d, past its %d bytes" % [
			chunk_id, count, at, d.size()]
		return false
	for i in count:
		var base := at + i * LCTX_ENTRY
		entries.append({
			"chunk_id": _i32(d, base + 4),
			"flags": _u16(d, base + 8),
			"next_unused": _i16(d, base + 10),
			"unused": false,
		})
	# The free list. Walked with a step budget rather than to its end, because a
	# corrupt `nextUnused` that points at itself is a hang, and a stripped chunk
	# is exactly the kind of file that would carry one.
	var cursor := first_unused
	var budget := entries.size() + 1
	while cursor >= 0 and cursor < entries.size() and budget > 0:
		entries[cursor]["unused"] = true
		cursor = int(entries[cursor]["next_unused"])
		budget -= 1
	return true


# --- Lscr tables -----------------------------------------------------------

func _name_list(
	d: PackedByteArray, at: int, count: int, stop_at_minus_one: bool, drop_me: bool
) -> PackedStringArray:
	var out := PackedStringArray()
	for i in count:
		var o := at + i * 2
		if o + 2 > d.size():
			break
		var index := _i16(d, o)
		if stop_at_minus_one and index == -1:
			break
		var name := name_at(index)
		if name == "":
			continue
		if drop_me and name == "me":
			continue
		out.append(name)
	return out


## `literalsOffset + count * stride == literalsDataOffset` is exact, so this
## needs no version. With no literals the question does not arise and the
## version's answer stands.
func _detect_literal_stride(d: PackedByteArray) -> int:
	var count := _u16(d, 78)
	var table_at := _u32(d, 80)
	var data_at := _u32(d, 88)
	if count > 0:
		if table_at + count * 8 == data_at:
			return 8
		if table_at + count * 6 == data_at:
			return 6
	return int(sizes_for(human)["literal"])


func _read_literals(
	d: PackedByteArray, at: int, count: int, store_at: int, store_len: int, stride: int
) -> Array:
	var out: Array = []
	for i in count:
		var o := at + i * stride
		if o + stride > d.size():
			break
		var type_code := _u32(d, o) if stride == 8 else _u16(d, o)
		var operand := _u32(d, o + (4 if stride == 8 else 2))
		out.append(_literal(d, type_code, operand, store_at, store_len))
	return out


func _literal(
	d: PackedByteArray, type_code: int, operand: int, store_at: int, _store_len: int
) -> Dictionary:
	match type_code:
		1:
			var at := store_at + operand
			if at + 4 > d.size():
				return {"type": "unknown", "value": null, "raw": type_code}
			var length := _u32(d, at)
			var start := at + 4
			var stop: int = mini(start + length, d.size())
			var raw := d.slice(start, stop)
			# The stored length counts a trailing NUL. ScummVM scans to the first
			# NUL inside the length, which is the same string for a well-formed
			# record and the safer reading for one that is not.
			var nul := raw.find(0)
			if nul >= 0:
				raw = raw.slice(0, nul)
			return {"type": "string", "value": Codepage.decode(raw)}
		4:
			# The operand **is** the value, signed. No data-store access.
			var v := operand
			if v >= 0x80000000:
				v -= 0x100000000
			return {"type": "int", "value": v}
		9:
			var at2 := store_at + operand
			if at2 + 4 > d.size():
				return {"type": "unknown", "value": null, "raw": type_code}
			var length2 := _u32(d, at2)
			if length2 == 8 and at2 + 12 <= d.size():
				return {"type": "float", "value": _f64(d, at2 + 4)}
			if length2 == 10 and at2 + 14 <= d.size():
				return {"type": "float", "value": _sane80(d, at2 + 4)}
			return {"type": "unknown", "value": null, "raw": type_code}
	return {"type": "unknown", "value": null, "raw": type_code}


## Score both candidate strides against the record chain and keep the winner.
##
## Every handler record satisfies `argumentOffset == compiledOffset +
## compiledLength` and `localsOffset == argumentOffset + argumentCount * 2`, and
## consecutive records satisfy `next.compiledOffset == prev.lineOffset +
## prev.lineCount` (or that plus one, for 2-byte alignment). A record read at the
## wrong stride fails them: `MASTER.CST` at 42 reports `compiledLength = 131071`,
## which is how the error announces itself.
##
## A single-handler script cannot use the third rule, which is why `BYAIR.cst`
## could not have revealed the 42-vs-46 question on its own; the first two still
## discriminate there.
func _detect_handler_stride(d: PackedByteArray, at: int, count: int) -> int:
	if count <= 0:
		return int(sizes_for(human)["handler"])
	var stated := int(sizes_for(human)["handler"])
	var other := 46 if stated == 42 else 42
	var best := stated
	var best_score := _stride_score(d, at, count, stated)
	var other_score := _stride_score(d, at, count, other)
	if other_score > best_score:
		best = other
	return best


func _stride_score(d: PackedByteArray, at: int, count: int, stride: int) -> int:
	var score := 0
	var previous := {}
	for i in count:
		var o := at + i * stride
		if o + 42 > d.size():
			return -1
		var compiled_len := _u32(d, o + 4)
		var compiled_at := _u32(d, o + 8)
		var arg_count := _u16(d, o + 12)
		var arg_at := _u32(d, o + 14)
		var local_at := _u32(d, o + 20)
		if compiled_at + compiled_len > d.size():
			return -1
		score += 1 if arg_at == compiled_at + compiled_len else 0
		score += 1 if local_at == arg_at + arg_count * 2 else 0
		if not previous.is_empty():
			var want: int = int(previous["line_at"]) + int(previous["line_count"])
			score += 1 if compiled_at == want or compiled_at == want + 1 else 0
		previous = {"line_at": _u32(d, o + 38), "line_count": _u16(d, o + 36)}
	return score


func _read_handlers(
	d: PackedByteArray, at: int, count: int, stride: int, factory: bool
) -> Array:
	var out: Array = []
	for i in count:
		var o := at + i * stride
		if o + 42 > d.size():
			break
		var name_id := _i16(d, o)
		var compiled_len := _u32(d, o + 4)
		var compiled_at := _u32(d, o + 8)
		var arg_count := _u16(d, o + 12)
		var arg_at := _u32(d, o + 14)
		var code := PackedByteArray()
		if compiled_at >= 0 and compiled_at + compiled_len <= d.size():
			code = d.slice(compiled_at, compiled_at + compiled_len)
		var args := _slot_names(d, arg_at, arg_count, "arg")
		# A factory handler's argument 0 is `me` when its name index is invalid.
		if factory and args.size() > 0 and arg_at + 2 <= d.size() and _i16(d, arg_at) < 0:
			args[0] = "me"
		out.append({
			"index": i,
			"name_id": name_id,
			"name": name_at(name_id),
			"vector_pos": _u16(d, o + 2),
			"code": code,
			"code_offset": compiled_at,
			"args": args,
			# The four table offsets are kept beside the names they resolve so a
			# caller can assert the chain that validates the stride --
			# `arg_offset == code_offset + code.size()`, then locals, globals and
			# the line table each abutting the last. `tools/lscr_layout.gd` is
			# the caller, and without these it could only re-derive them from the
			# same bytes and agree with itself.
			"arg_offset": arg_at,
			"local_offset": _u32(d, o + 20),
			"global_offset": _u32(d, o + 26),
			"line_offset": _u32(d, o + 38),
			"locals": _slot_names(d, _u32(d, o + 20), _u16(d, o + 18), "var"),
			# **The per-handler globals list is where `global` declarations
			# live**, and ScummVM does not read it -- it consumes offsets 24..41
			# as nine anonymous `readUint16()`s and carries the name inline on
			# `cb_globalpush` instead. A decoder targeting a source-like AST needs
			# the list, because the port's parser emits a `global` node for the
			# declaration. `BYAIR.cst` chunk 342 has two here and zero in the
			# script-level list at header +66.
			"globals": _slot_names(d, _u32(d, o + 26), _u16(d, o + 24), ""),
			"line_count": _u16(d, o + 36),
			"lines": _read_lines(d, _u32(d, o + 38), _u16(d, o + 36)),
		})
	return out


## Argument, local and global name lists: `count` i16 `Lnam` indices.
##
## An out-of-range index becomes a synthetic `arg_<n>` / `var_<n>` rather than
## failing the handler, which is ScummVM's behaviour. `prefix == ""` (the globals
## list) drops it instead: a global with no name is not referenceable, and
## inventing one would put a `global var_3` into the decoded source.
func _slot_names(d: PackedByteArray, at: int, count: int, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for i in count:
		var o := at + i * 2
		var name := "" if o + 2 > d.size() else name_at(_i16(d, o))
		if name == "":
			if prefix == "":
				continue
			name = "%s_%d" % [prefix, i]
		out.append(name)
	return out


## The line-number table: `lineCount` unsigned bytes, no header, entry *i* being
## the number of bytecode bytes source line *i* compiled to.
##
## **Neither reference decodes this** -- ProjectorRays reads the two fields and
## leaves `// yet to implement`, ScummVM skips them. It is decoded because it is
## the only thing that can put source line numbers on the AST nodes this port's
## parser always carries a `line` on, and a decoded handler whose nodes all say
## line 0 is one nothing can be reported against.
##
## Best-effort by construction: a single byte cannot express a source line that
## compiled to more than 255 bytes, so a table that disagrees with
## `compiledLength` loses the attribution rather than the handler.
func _read_lines(d: PackedByteArray, at: int, count: int) -> PackedByteArray:
	if at < 0 or count < 0 or at + count > d.size():
		return PackedByteArray()
	return d.slice(at, at + count)


# --- container plumbing ----------------------------------------------------

## Tag ids matching case-insensitively.
##
## **The tag in this corpus is mostly `LctX`, not `Lctx`** -- 454 containers
## under `games/` carry the capital-X spelling and 136 the lower-case one, and
## ScummVM looks only for `Lctx`, so a decoder transcribed from it finds no
## script context in piposh 1 at all. Matching case-insensitively costs nothing
## and covers a spelling nobody has enumerated.
func _ids_matching(lower_tag: String) -> Array:
	var out: Array = []
	for tag in _file.by_tag:
		if str(tag).to_lower() == lower_tag:
			for id in _file.by_tag[tag]:
				out.append(int(id))
	out.sort()
	return out


func _read_raw_version(container) -> int:
	for want in ["DRCF", "VWCF"]:
		var ids: Array = container.ids_of(want)
		if ids.is_empty():
			continue
		var d: PackedByteArray = container.read_chunk(int(ids[0]))
		if d.size() >= 38:
			return _u16(d, 36)
	return 0


# --- big-endian readers ----------------------------------------------------
#
# Written out rather than taken from `DirectorFile`, because these three chunks
# are big-endian *whatever the container is* and reading them through the
# container's own byte order is exactly the mistake `MASTER.CST` catches.

static func _u16(d: PackedByteArray, o: int) -> int:
	if o < 0 or o + 2 > d.size():
		return 0
	return (d[o] << 8) | d[o + 1]


static func _i16(d: PackedByteArray, o: int) -> int:
	var v := _u16(d, o)
	return v - 0x10000 if v >= 0x8000 else v


static func _u32(d: PackedByteArray, o: int) -> int:
	if o < 0 or o + 4 > d.size():
		return 0
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


static func _i32(d: PackedByteArray, o: int) -> int:
	var v := _u32(d, o)
	return v - 0x100000000 if v >= 0x80000000 else v


static func _f64(d: PackedByteArray, o: int) -> float:
	var swapped := PackedByteArray()
	for i in range(7, -1, -1):
		swapped.append(d[o + i])
	return swapped.decode_double(0)


## Apple SANE 80-bit extended, which is what a D4-authored float literal is.
## Sign, 15-bit exponent biased 16383, and an explicit 64-bit significand -- no
## hidden bit, unlike IEEE.
static func _sane80(d: PackedByteArray, o: int) -> float:
	var sign := -1.0 if (d[o] & 0x80) != 0 else 1.0
	var exponent := ((d[o] & 0x7F) << 8) | d[o + 1]
	var mantissa := 0.0
	for i in range(2, 10):
		mantissa = mantissa * 256.0 + float(d[o + i])
	if exponent == 0 and mantissa == 0.0:
		return 0.0
	return sign * mantissa * pow(2.0, float(exponent - 16383 - 63))
