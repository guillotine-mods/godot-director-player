class_name DirectorFile
extends RefCounted
## One Director container (.dir / .cst / .dxr / .cxt), opened and indexed.
##
## Everything needed to read one is inside it: the magic says which byte order
## the file uses, `imap` says where the memory map lives, and `mmap` lists every
## chunk with its tag, offset and size. Nothing here is configured per game.
##
## Byte order is a property of the file, not of the title. Piposh 2 ships 83
## big-endian `RIFX` containers and 3 little-endian `XFIR` ones — and the three
## are `strtgame.dir`, `MASTER.CST` and `HEZSAVE.DIR`: the boot movie, the shared
## cast that owns the globals and the inventory HUD, and save/load. A reader that
## handles one order cannot open the game at all, so this is not a later concern.
##
## In `XFIR` files the four-character tags are byte-reversed too, which is why
## every tag goes through `_read_tag` rather than being compared raw.

const MAGIC_BIG := "RIFX"
const MAGIC_LITTLE := "XFIR"
## Entries that occupy an id but address no payload of their own, so their
## offsets must not be range-checked as if they did.
##
## `free` and `junk` are map placeholders. `RIFX` is entry 0, the container
## itself: its extent is the whole file, and RIFF pads odd-length files to an
## even boundary, so a file whose pad byte was never written reports one byte
## more than it has. `HEZSAVE.DIR` is exactly that — 137,655 bytes claiming
## 137,656 — and Director opens it without complaint. Treating entry 0 as a
## chunk failed the only file in the game with an odd length.
const NON_PAYLOAD_TAGS := ["free", "junk", "RIFX", "XFIR"]
## Every chunk carries its own tag + size ahead of its payload.
const CHUNK_HEADER := 8

var path: String = ""
var big_endian: bool = true
## Container format, `MV93` for the Director 6/7 movies this game ships.
var codec: String = ""
## Where the memory map itself lives, and its shape. Read during `open` and kept
## because a *writer* needs them: `director/director_writer.gd` patches entries
## in place, and re-deriving the map's position from the `imap` would be a second
## copy of the rule above about where it is and how wide an entry is. Zero until
## a container has been opened.
var mmap_offset: int = 0
var mmap_header_len: int = 0
var mmap_entry_len: int = 0
## Every memory-map entry in id order: `{id, tag, offset, size}`. The id is the
## entry's index in the map, which is what `CAS*`, `KEY*` and ProjectorRays'
## filenames all refer to, so it is the join key for everything downstream.
var chunks: Array[Dictionary] = []
## tag -> Array[int] of ids, in map order.
var by_tag: Dictionary = {}
## Empty until something fails; the reason the last call returned false.
var error: String = ""

var _file: FileAccess = null
var _length: int = 0


## Opens and indexes the container. False leaves the reason in `error`.
func open(container_path: String) -> bool:
	error = ""
	path = container_path
	_file = FileAccess.open(container_path, FileAccess.READ)
	if _file == null:
		error = "cannot open: %s" % error_string(FileAccess.get_open_error())
		return false
	_length = _file.get_length()
	if _length < 20:
		error = "too short to be a container (%d bytes)" % _length
		return false

	# The magic is raw bytes, so it reads the same either way round; everything
	# after it depends on knowing the order first.
	var magic := _ascii(_file.get_buffer(4))
	if magic == MAGIC_BIG:
		big_endian = true
	elif magic == MAGIC_LITTLE:
		big_endian = false
	else:
		error = "not a Director container (magic %s)" % JSON.stringify(magic)
		return false
	_file.big_endian = big_endian

	_file.seek(8)
	codec = _read_tag()

	_file.seek(12)
	var imap_tag := _read_tag()
	if imap_tag != "imap":
		error = "expected imap at 12, found %s" % JSON.stringify(imap_tag)
		return false
	# imap body: u32 entry count, then the offset of the mmap chunk itself.
	_file.seek(24)
	var map_at := _file.get_32()
	if map_at <= 0 or map_at + CHUNK_HEADER >= _length:
		error = "imap points outside the file (mmap at %d of %d)" % [map_at, _length]
		return false

	return _read_memory_map(map_at)


func _read_memory_map(at: int) -> bool:
	_file.seek(at)
	var mmap_tag := _read_tag()
	if mmap_tag != "mmap":
		error = "expected mmap at %d, found %s" % [at, JSON.stringify(mmap_tag)]
		return false
	_file.get_32() # chunk size, already bounded by the file length

	# The header length is read rather than assumed: it is what says where the
	# entries start, and trusting a constant here would silently misalign every
	# entry in a container written by a different Director build.
	var body := at + CHUNK_HEADER
	var header_len := _file.get_16()
	var entry_len := _file.get_16()
	_file.get_32() # capacity
	var used := _file.get_32()
	if header_len <= 0 or entry_len <= 0:
		error = "unusable mmap shape (header %d, entry %d)" % [header_len, entry_len]
		return false
	mmap_offset = at
	mmap_header_len = header_len
	mmap_entry_len = entry_len

	var entries_at := body + header_len
	if entries_at + used * entry_len > _length:
		error = "mmap claims %d entries, past the end of the file" % used
		return false

	chunks.clear()
	by_tag.clear()
	for i in used:
		_file.seek(entries_at + i * entry_len)
		var tag := _read_tag()
		var size := _file.get_32()
		var offset := _file.get_32()
		var entry := {"id": i, "tag": tag, "offset": offset, "size": size}
		chunks.append(entry)
		if not by_tag.has(tag):
			by_tag[tag] = []
		by_tag[tag].append(i)
	return true


## Ids carrying the given tag, in map order. Empty when the tag is absent.
func ids_of(tag: String) -> Array:
	return by_tag.get(tag, [])


## A chunk's payload, without its tag + size header. Empty on any failure, with
## the reason in `error` — an unreadable chunk is a fact about the file, not a
## reason to take the whole movie down.
func read_chunk(id: int) -> PackedByteArray:
	error = ""
	if id < 0 or id >= chunks.size():
		error = "no chunk %d (have %d)" % [id, chunks.size()]
		return PackedByteArray()
	var entry: Dictionary = chunks[id]
	if entry["tag"] in NON_PAYLOAD_TAGS:
		error = "chunk %d is a %s placeholder" % [id, entry["tag"]]
		return PackedByteArray()
	var start: int = int(entry["offset"]) + CHUNK_HEADER
	var size: int = int(entry["size"])
	if start < 0 or size < 0 or start + size > _length:
		error = "chunk %d (%s) runs past the end of the file" % [id, entry["tag"]]
		return PackedByteArray()
	_file.seek(start)
	return _file.get_buffer(size)


## Every chunk that addresses a payload lies inside the file. Returns the list of
## offending ids, so a caller can report them rather than only knowing a count.
func out_of_bounds() -> Array[int]:
	var bad: Array[int] = []
	for entry in chunks:
		if entry["tag"] in NON_PAYLOAD_TAGS:
			continue
		var start: int = int(entry["offset"]) + CHUNK_HEADER
		var size: int = int(entry["size"])
		if start < 0 or size < 0 or start + size > _length:
			bad.append(int(entry["id"]))
	return bad


## tag -> count, for reporting what a container holds.
func census() -> Dictionary:
	var out := {}
	for tag in by_tag:
		out[tag] = by_tag[tag].size()
	return out


func length() -> int:
	return _length


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


func _read_tag() -> String:
	var raw := _file.get_buffer(4)
	if not big_endian:
		raw.reverse()
	return _ascii(raw)


func _ascii(raw: PackedByteArray) -> String:
	return raw.get_string_from_ascii()
