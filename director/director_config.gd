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
## The palette the movie starts on, and the cast library it lives in.
##
## §11's last resort: the frame's palette channel, else the score cache, else
## this. Every movie has one and it was never read, so every movie started on
## system Mac whatever it said — which is right for the six shipped titles, all
## of which state exactly that, and wrong for a Windows-authored title: both
## `itamar-park` movies and 16 of `itamar-magichat`'s state -101, the Windows D5
## system palette once the built-in offset below is applied.
##
## **Where.** The reference reads the chunk as a stream, and after the checksum
## at 64 the two layouts diverge: D4 puts a spare word at 68 and the palette
## member at 70, and D5 and later put the spare word at 68, a palette *number* at
## 70, a long word at 72, and then the cast library at 76 and the member at 78.
## Both stop at 80 bytes. Only the D5 form occurs in either corpus here — every
## container in all eight roots states a file version at or above `0x57E`, and D5
## begins at `0x4B1` — so the D4 arm is written from the reference and is
## **unexercised**.
##
## **The built-in offset.** In this chunk Director numbers the built-in palettes
## from 0 downward, and in the score's palette channel from -1 downward, because
## there 0 has to mean "no palette change this frame". The reference reconciles
## them by decrementing any id at or below zero here, so a movie storing 0 means
## system Mac and one storing -101 means the Windows D5 table. A positive id is a
## palette cast member and is left alone.
var default_palette := 0
var default_palette_lib := 0
## The machine the movie was authored on, as Director's own id: 1 Mac, 2 Windows,
## 0 when the chunk is too short to carry it.
##
## Offset 56, immediately after the frame rate at 54, and it is the *only*
## in-file answer to "which platform is this". The reference gets its platform
## from here too -- `cast.cpp:loadConfig` reads `_platformID = readUint16()` and
## `_platform = platformFromID(_platformID)` (`util.cpp:1348`, 1 Mac / 2 Windows,
## ScummVM 805f259a) -- so this is the same field read the same way rather than a
## guess from the container's endianness. `XFIR` is a strong hint and not the
## answer: byte order is a property of the file the projector wrote, and Director
## will happily write a little-endian container for a movie whose config says
## Mac.
##
## Read because **Director's cursor hotspot rule branches on it**. §7.3 rule 2:
## Windows Director before D5 ignores a custom cursor's registration point and
## always uses (8,8), and the reference expresses that as one clause of the same
## `if` that recentres an out-of-range hotspot
## (`cursor.cpp:Cursor::readFromCast`). Without this field the engine can only
## implement half of that rule, which is the state `bugs.md` 28 recorded.
## **Measured, and it is not one answer.** `tools/cursor_hotspot.gd --all` over
## the six shipped roots opens 651 containers, of which 482 carry a config at
## all: **373 state 2 (Windows) and 109 state 1 (Mac)**, which is worth knowing
## before anybody writes "these are Windows discs" into a comment. It does not
## reach the cursor rule either way, because the same survey puts every one of
## those 482 at file version `0x57E` (111) or `0x73A` (371) and D5 begins at
## `0x4B1` -- so **zero containers are Windows *and* below D5** and rule 2 is
## inert on this corpus. It is implemented because Director has it, not because
## anything here exercises it, and `tools/cursor_hotspot.gd` says that out loud
## and asserts the branch against a synthetic D4 member instead.
var platform_id := 0
var error: String = ""

## D5 and later, from the reference's own table. Below this the config's tail is
## the D4 layout.
const FILE_VERSION_D5 := 0x4B1


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
	platform_id = _u16(payload, 56) if payload.size() >= 58 else 0
	_read_default_palette(payload)
	return true


## The tail of the chunk, per the version split described on `default_palette`.
## A chunk too short to hold the field leaves the default at 0, which resolves to
## system Mac exactly as a stored 0 would.
func _read_default_palette(payload: PackedByteArray) -> void:
	default_palette = 0
	default_palette_lib = 0
	var stored := 0
	if version >= FILE_VERSION_D5:
		if payload.size() < 80:
			return
		default_palette_lib = _i16(payload, 76)
		stored = _i16(payload, 78)
	else:
		if payload.size() < 72:
			return
		stored = _i16(payload, 70)
	default_palette = stored - 1 if stored <= 0 else stored


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
