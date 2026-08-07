class_name DirectorConfig
extends RefCounted
## One movie's `DRCF` (`VWCF` before D5): where its stage is and how big it is.
##
## Nothing needed this until Movie-In-A-Window. A movie opened as a window brings
## its *own* stage rect with it — that is the size of the floating window and,
## when `the centerStage` is not set, where it sits — and the host has no other
## way to know it. `docs/DIRECTOR_ENGINE.md` §14.
##
## The chunk is 84 bytes here and stored big-endian in both `RIFX` and `XFIR`
## containers: `DAY1.dir` is little-endian and its `DRCF` still reads
## `00 54 07 3a 00 3c 00 10 …`, so the byte order of the container does not reach
## this chunk. Read the other way every field is nonsense, which is how it was
## settled.
##
## The layout is not guessed. `castArrayEnd` at offset 14 is an independent
## check on the whole header: `JOKE.dir` says 41 and the container holds exactly
## 41 `CASt` chunks, `MAP.dir` says 30 for 30, `SAVELOAD.dir` says 150 for 150.
## A layout that is off by a field cannot pass that three times.
##
## Only the fields that check out are decoded. `DIRECTOR_ENGINE.md` §14 also
## wants the stage *colour* from here, and the candidate offsets do not agree
## with anything measurable in this corpus, so it is deliberately absent rather
## than decoded on faith — see `bugs.md` if that ever matters.

## Top-left in the authoring machine's screen coordinates, and the size in
## pixels. Director stores the rect, not the size; both are kept because the
## position is what places a window and the size is what fills it.
var rect := Rect2i(0, 0, 0, 0)
## The member-number range the movie's own cast covers. Decoded only because it
## is the field that proves the rest of the header is aligned.
var cast_array_start := 0
var cast_array_end := 0
## Director's own version word, `0x57E` for D7.
var version := 0
var error: String = ""


func parse(payload: PackedByteArray) -> bool:
	error = ""
	if payload.size() < 16:
		error = "DRCF too short (%d bytes)" % payload.size()
		return false
	var declared := _u16(payload, 0)
	if declared != payload.size():
		# Not fatal: the length is a header field, and a container whose chunk is
		# padded still parses. Worth saying, because a mismatch is the first sign
		# the byte order assumption above is wrong for some file.
		error = "DRCF declares %d bytes, chunk is %d" % [declared, payload.size()]
	var top := _i16(payload, 4)
	var left := _i16(payload, 6)
	var bottom := _i16(payload, 8)
	var right := _i16(payload, 10)
	if right <= left or bottom <= top:
		error = "DRCF rect is empty or inverted: (%d,%d)-(%d,%d)" % [left, top, right, bottom]
		return false
	rect = Rect2i(left, top, right - left, bottom - top)
	cast_array_start = _u16(payload, 12)
	cast_array_end = _u16(payload, 14)
	version = _u16(payload, 36) if payload.size() >= 38 else 0
	return true


## Read a movie's config chunk. False when it has none, or when it does not
## parse; callers treat that as "no opinion" and fall back to the host stage,
## which is what Director does for a movie whose config it cannot read.
##
## An instance method rather than a static factory, because a static one would
## have to name its own `class_name` to construct the result and that identifier
## is unresolvable in a headless `--script` run — the same trap the `const X :=
## preload(...)` convention exists to avoid everywhere else in this port.
func read(movie) -> bool:
	if movie == null:
		error = "no movie"
		return false
	var ids: Array = movie.ids_of("DRCF")
	if ids.is_empty():
		ids = movie.ids_of("VWCF")
	if ids.is_empty():
		error = "no DRCF or VWCF chunk"
		return false
	return parse(movie.read_chunk(int(ids[0])))


static func _u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _i16(d: PackedByteArray, o: int) -> int:
	var raw := _u16(d, o)
	return raw - 0x10000 if raw >= 0x8000 else raw
