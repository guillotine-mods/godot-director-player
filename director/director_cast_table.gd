class_name DirectorCastTable
extends RefCounted
## Every cast library one movie can address, keyed by its `MCsL` library number.
##
## A sprite names its member as `(cast library, member number)`, and the library
## number is local to the movie: `master` is 2 in one room and 4 in another. The
## `MCsL` chunk is what maps that number to a name, a file path and a member
## range.
##
## Libraries are cached by *resolved path*, not by name. One movie links the same
## cast file twice under two names, and keying by name parses it twice and then
## needs an alias record to reconcile them; keying by path makes the two entries
## the same object and the problem disappears.
##
## A library's file path can also be empty while still not being the internal
## cast: one movie embeds a second cast in its own container. Those are found by
## matching the library's `castID` against the `KEY*` owner of each `CAS*`.

const Cast := preload("res://director/director_cast.gd")
const ContainerFile := preload("res://director/director_file.gd")
const FilmLoop := preload("res://director/director_film_loop.gd")

## lib number -> {name, path, min, max, id, resolved_path, embedded}
var cast_libs: Dictionary = {}
var movie_name: String = ""
var error: String = ""

var _paths = null
var _movie = null
## lib number -> DirectorCast
var _casts: Dictionary = {}
## resolved path -> {"file": DirectorFile, "cast": DirectorCast}
var _by_path: Dictionary = {}
## container path -> its `ccl ` list, read once.
var _cast_lists: Dictionary = {}


func open(movie, director_paths) -> bool:
	error = ""
	_movie = movie
	_paths = director_paths
	movie_name = str(movie.path).get_file().get_basename()

	# The internal cast is library 1 whether or not an MCsL says so; a pure cast
	# file has no MCsL at all and is a single library by definition.
	var internal := Cast.new()
	if internal.open(movie):
		_casts[1] = internal
	cast_libs[1] = {
		"name": "internal", "path": "", "min": 1,
		"max": internal.member_count, "id": internal.owner_id,
		"resolved_path": str(movie.path), "embedded": true,
	}

	var ids: Array = movie.ids_of("MCsL")
	if ids.is_empty():
		return true
	return _read_mcsl(movie.read_chunk(ids[0]))


func _read_mcsl(data: PackedByteArray) -> bool:
	if data.size() < 12:
		error = "MCsL too short"
		return false
	var data_offset := _be_u32(data, 0)
	var cast_count := _be_u32(data, 4)
	var per_cast := _be_u16(data, 8)
	if data_offset + 2 > data.size() or per_cast <= 0:
		error = "unusable MCsL shape"
		return false

	var count := _be_u16(data, data_offset)
	var offsets_at := data_offset + 2
	if offsets_at + count * 4 + 4 > data.size():
		error = "MCsL offset table runs past the chunk"
		return false
	var offsets: Array = []
	for i in count:
		offsets.append(_be_u32(data, offsets_at + i * 4))
	var items_len := _be_u32(data, offsets_at + count * 4)
	var items_base := offsets_at + count * 4 + 4

	var item := func(index: int) -> PackedByteArray:
		if index < 0 or index >= count:
			return PackedByteArray()
		var start: int = items_base + int(offsets[index])
		var stop: int = items_base + (
			int(offsets[index + 1]) if index + 1 < count else items_len
		)
		if start < 0 or stop > data.size() or stop < start:
			return PackedByteArray()
		return data.slice(start, stop)

	for lib in range(1, cast_count + 1):
		var i := (lib - 1) * per_cast
		var name := _pascal(item.call(i + 1))
		var path := _pascal(item.call(i + 2))
		var range_item: PackedByteArray = item.call(i + 4)
		var lo := 1
		var hi := 0
		var cast_id := -1
		if range_item.size() >= 8:
			lo = _be_u16(range_item, 0)
			hi = _be_u16(range_item, 2)
			cast_id = _be_u32(range_item, 4)
		# **A library with no file path lives in this container**, which is what
		# the header says and what `_cast_for` acts on -- so its resolved path is
		# the movie's own file, and it is recorded here rather than only when the
		# library is first opened.
		#
		# Recording it late was a real bug and not a tidy-up. `open` sets library
		# 1 to the movie's path before this runs, and this loop overwrote it with
		# `""` for every movie that carries an `MCsL`; `_cast_for(1)` then found
		# the cast already cached and returned without ever filling it in. So the
		# *internal* cast of every such movie had no path, and
		# `text_art.gd:key_for` -- which keys every field override by the cast's
		# file precisely so that two movies cannot collide -- fell back to its
		# `#1` placeholder. One namespace, shared by every movie in the game.
		#
		# Two consequences, both of them the reason this was found. A movie's own
		# field writes were never dropped on `go to movie`, because
		# `TextArt.forget` matches on the container path and nothing was keyed by
		# one. And SAVELOAD's `field "save1"` and HEZSAVE's `field "gamename1"`
		# are member 1 of their own internal casts, so the two movies that hand
		# the save screen back and forth were reading and writing *the same
		# entry*.
		var resolved := str(cast_libs.get(lib, {}).get("resolved_path", ""))
		if resolved == "" and path == "":
			resolved = str(_movie.path)
		cast_libs[lib] = {
			"name": name, "path": path, "min": lo, "max": hi, "id": cast_id,
			"resolved_path": resolved, "embedded": path == "",
		}
	return true


## The member a sprite names. `{}` when the library or the member is absent,
## which for a shape or a script member is the expected answer.
func get_member(cast_lib: int, cast_id: int) -> Dictionary:
	var cast = _cast_for(cast_lib)
	if cast == null:
		return {}
	var m: Dictionary = cast.member(cast_id)
	if m.is_empty():
		return {}
	m = m.duplicate()
	m["cast_lib"] = cast_lib
	m["cast_lib_name"] = str(cast_libs.get(cast_lib, {}).get("name", ""))
	return m


## The parsed cast of a library, opened and cached on first ask. Callers that
## want members should use `get_member`; this is for the ones that need the cast
## itself, such as compiling every script it holds.
func cast_for(cast_lib: int):
	return _cast_for(cast_lib)


## The container a library lives in, so a caller can read its payload chunks.
func file_for(cast_lib: int):
	if cast_lib == 1:
		return _movie
	var entry: Dictionary = cast_libs.get(cast_lib, {})
	var resolved := str(entry.get("resolved_path", ""))
	if resolved == "" or not _by_path.has(resolved):
		_cast_for(cast_lib)
		resolved = str(cast_libs.get(cast_lib, {}).get("resolved_path", ""))
	if _by_path.has(resolved):
		return _by_path[resolved]["file"]
	return _movie if cast_lib == 1 else null


## The `ccl ` list of the container library `cast_lib` lives in: the ordered
## external casts *that file's* film loops index into.
##
## Which file it comes from is the whole point, and it is why this lives here
## rather than being read once from the playing movie. A film loop is a cast
## member, so a loop in a linked cast indexes the linked cast's own list — and a
## `.cst` in this corpus usually has none, which says its loops reference nothing
## outside themselves. Handing every loop the *movie's* list instead resolves
## those children through a list they were never written against: MURDER1's
## `MASTER:invright` and `HEZI:hezr` both drew out of `tofi`, because tofi is
## what MURDER1's own first `ccl ` entry happens to be. Same class as reading a
## member number in the wrong library, one level down.
##
## Cached by container path rather than by library number, for the reason the
## casts themselves are: one movie can link the same file twice.
func cast_list_for(cast_lib: int) -> PackedStringArray:
	var f = file_for(cast_lib)
	if f == null:
		return PackedStringArray()
	var key := str(f.path)
	if _cast_lists.has(key):
		return _cast_lists[key]
	var out := PackedStringArray()
	var ids: Array = f.ids_of("ccl ")
	if not ids.is_empty():
		out = FilmLoop.read_cast_list(f.read_chunk(ids[0]))
	_cast_lists[key] = out
	return out


func _cast_for(cast_lib: int):
	if _casts.has(cast_lib):
		return _casts[cast_lib]
	if not cast_libs.has(cast_lib):
		return null
	var entry: Dictionary = cast_libs[cast_lib]

	# An empty path can still mean a second cast inside this container, matched
	# by the library's own castID against the owner of each CAS*.
	if str(entry["path"]) == "":
		var embedded := Cast.new()
		if embedded.open(_movie, int(entry["id"])):
			entry["embedded"] = true
			entry["resolved_path"] = str(_movie.path)
			_casts[cast_lib] = embedded
			return embedded
		return null

	# Resolved from the movie's own directory first. This game ships two
	# different files called MASTER.CST — one at the root, one beside the
	# movies — so a bare-filename lookup picks whichever the scan met first,
	# and a movie in PIP2DATA can end up reading the root's cast.
	var beside: String = str(_movie.path).get_base_dir()
	var resolved: String = _paths.resolve(str(entry["path"]), beside)
	if resolved == "":
		# Director paths are Mac colon form and name a volume that no longer
		# exists, so the filename is what actually resolves.
		resolved = _paths.resolve(str(entry["path"]).replace(":", "/").get_file(), beside)
	if resolved == "":
		return null
	entry["resolved_path"] = resolved

	if _by_path.has(resolved):
		_casts[cast_lib] = _by_path[resolved]["cast"]
		return _casts[cast_lib]

	var f := ContainerFile.new()
	if not f.open(resolved):
		return null
	var cast := Cast.new()
	if not cast.open(f):
		f.close()
		return null
	_by_path[resolved] = {"file": f, "cast": cast}
	_casts[cast_lib] = cast
	return cast


func close() -> void:
	for resolved in _by_path:
		_by_path[resolved]["file"].close()
	_by_path.clear()
	_casts.clear()
	_cast_lists.clear()


static func _pascal(raw: PackedByteArray) -> String:
	if raw.size() < 1:
		return ""
	var length: int = raw[0]
	if length + 1 > raw.size():
		return ""
	return raw.slice(1, 1 + length).get_string_from_ascii()


static func _be_u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _be_u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]
