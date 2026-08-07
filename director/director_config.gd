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
## Director's own file-version word. Piposh 2's containers state `0x57E` and
## Piposh 1's `0x73A`; the reference's own table puts D6 at `0x4C2` and D7 at
## `0x4C8`, so both corpora are D6 or later by a wide margin.
##
## Read, rather than decoded into a human version number, because what the engine
## needs it for is threshold tests: the reference chooses the score's channel
## layout and the tempo cell's numbering from this word and nothing else, and a
## comparison does not need the word turned into "8.5" first. See
## `FrameClock.movie_file_version`.
var version := 0
## The rate the movie plays at until its score says otherwise, in frames per
## second. Zero or below when the movie states none usable; no container in
## either corpus does.
##
## `DIRECTOR_ENGINE.md` §9.1 says "with no tempo, the previous rate carries
## forward" and never says what the *first* rate is. This is it, and without it a
## movie that never writes a tempo runs at whatever the engine assumed -- 15 fps
## here, which is nearly twice the speed most of these movies want.
##
## Offset 54, and no longer only a distribution argument. It was settled here by
## one: across the 124 containers of a second title it reads
## `{2:1, 3:2, 4:3, 5:2, 6:1, 8:84, 10:5, 12:1}` over the 99 that have a config
## at all -- small, plausible frame rates with a strong mode at 8. Nothing else
## in the chunk is shaped like that: offset 62 is 60 in all 124, which is a
## constant, and the fields either side are the stage rect and the cast range,
## both independently confirmed.
##
## The reference now confirms it outright. Walking its config reader field by
## field from the start of the chunk -- length, file version, the four rect
## edges, the cast range, then a run of single bytes and words for the comment
## font, the stage colour and the bit depth, the version word again at 36, the
## movie depth, and three long words -- lands a signed 16-bit **frame rate** at
## exactly 54, for every file version from D4 on. And the reference does with it
## precisely what `FrameClock.movie_default_fps` does: it sets the score's
## current frame rate from this field when the movie's archive is loaded, before
## a frame has been read.
##
## Two neighbours are worth naming because they are *not* this field. Offset 16
## is a single byte holding D3-and-below's rate, which is not a rate but an index
## into a table of authoring-tool slider positions; every container in both
## corpora holds 1 there and it is dead for D4 and later. Offset 56 is the
## platform id, which is why reading this field as 32 bits would come out
## enormous rather than merely wrong.
var default_tempo := 0
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
	# Signed, as the reference reads it. Unsigned turns a negative field into a
	# five-digit frame rate, which is a number a caller can plausibly act on;
	# negative is one nothing will take, and "the movie states no usable rate" is
	# the honest reading of a field that is out of range either way.
	default_tempo = _i16(payload, 54) if payload.size() >= 56 else 0
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
