class_name DirectorScore
extends RefCounted
## One movie's score: the `VWSC` chunk replayed into per-frame sprite records.
##
## The score is stored as deltas against a channel buffer that persists for the
## whole movie, not as frames. A sprite that sits still for 800 frames is written
## once, so frame N only exists after every delta up to it has been applied.
##
## Deltas are byte ranges, not channel records. Director writes several adjacent
## 48-byte records in one go, so the buffer has to be treated as flat bytes; a
## reader that assumes one delta is one channel silently misplaces sprites.
##
## `VWSC` payloads are big-endian in every container, including the little-endian
## `XFIR` ones — byte order here is a property of the chunk, not of the file.

const MAIN_CHANNEL_SIZE := 288
const SPRITE_RECORD_SIZE := 48
## Main channel slots sit below sprite channel 1, so channel N's record is at
## `48 * (N + 5)`.
const CHANNEL_BIAS := 5
const STRETCH_FLAG := 0x80
const TRAILS_FLAG := 0x40
const INK_MASK := 0x3F

## Where the fields of a 48-byte sprite record are.
##
## The record this format writes is the **D7** one — 48 bytes, the size the frame
## header declares and this reader insists on. Its layout, from the reference:
##
##   0 sprite type   1 ink byte      2 fore colour   3 back colour
##   4 cast lib u16  6 member u16    8 sprite-list index u32
##  12 loc v i16    14 loc h i16    16 height i16   18 width i16
##  20 colour code  21 blend amount 22 thickness    23 flags
##  24 fore G       25 back G       26 fore B       27 back B
##  28 rotation u32 32 skew u32     36 twelve bytes of alignment
##
## The four flag bytes used to be read from the wrong places: the thickness byte
## from offset 4 and the blend amount from offset 19. Both offsets are already
## occupied by fields this same decoder reads — 4 is the high half of the cast
## lib and 19 the low half of the width — so neither could ever have held what it
## was being asked for, and the flag counts were the tell. Flip, blend and
## tweened all came out **0** across Piposh 2's 816,318 records and **0** across
## Piposh 1's 1,886,362, which is what reading a structurally-zero byte looks
## like. `tools/sprite_record_bytes.gd` settled it from the data alone, without
## assuming any layout: offset 4 is constant zero across 2.7 million records
## while offset 5 ranges over 1-16, so the pair is a small cast lib; offset 21
## takes exactly eleven values in Piposh 2 — 0, 25, 51, 76, 102, 127, 153, 178,
## 204, 229, 255 — which is 0-100% in tenths scaled to a byte, and nothing but a
## blend amount looks like that; and offset 22 carries the tweened bit on 70.3%
## and 73.6% of the two corpora respectively.
const SPRITE_LIST_IDX_AT := 8
const COLOR_CODE_AT := 20
const BLEND_AMOUNT_AT := 21
const THICKNESS_AT := 22
const SPRITE_FLAGS_AT := 23

## Bits of the thickness byte, which is not only thickness.
const BLEND_FLAG := 0x10
const FLIP_H_FLAG := 0x20
const FLIP_V_FLAG := 0x40
const TWEENED_FLAG := 0x80
const THICKNESS_MASK := 0x0F

## Bits of the colour-code byte. The low nibble is the score colour — the tint
## the authoring tool paints the channel with in the Score window, which is
## editing furniture and not something the stage ever shows. The two RGB bits say
## that the fore or back colour is a true colour in bytes 24-27 rather than a
## palette index; the port reads the index and warns nowhere, because 1,124 of
## Piposh 2's records set the back-colour bit and none of Piposh 1's set either.
const SCORE_COLOR_MASK := 0x0F
const FORE_COLOR_RGB_FLAG := 0x10
const BACK_COLOR_RGB_FLAG := 0x20
const EDITABLE_FLAG := 0x40
const MOVEABLE_FLAG := 0x80
## A sprite record naming this library means "the movie's own cast".
const OWN_CAST_LIB := 0xFFFF
## Tempo is a sentinel code and `tempo_cue` its operand.
const TEMPO_SET_FPS := 246
const TEMPO_DELAY := 247
const TEMPO_WAIT_CLICK := 248
## Wait for a sound to finish, or for a cue point in it. D6 renumbered the tempo
## codes wholesale and put the cue index in the operand beside them (§9.1); D5
## and below used a different pair with no cue index at all. Both are decoded,
## because the code is a property of the movie's authoring version and this
## decoder reads containers from several.
##
## Unexercised by the corpus this port was built on: across all 61 scores and
## 61,371 frames the tempo cell holds only 246, 247 and 248, never any of these
## four (`tools/sound_survey.gd`). So the numbering is the reference's.
const TEMPO_WAIT_SOUND_1 := 255
const TEMPO_WAIT_SOUND_2 := 254
const TEMPO_WAIT_SOUND_1_D5 := 135
const TEMPO_WAIT_SOUND_2_D5 := 134
## Cue indices with a meaning other than "the Nth cue point": Director writes -1
## for "the next one" and -2 for "the end of the sound".
const CUE_NEXT := -1
const CUE_END := -2
## The score-list marker the D5+ format writes at offset 4.
const SCORE_LIST_MARKER := -3
## The palette channel is the last of the six main-channel records, at 48 * 5.
## Its contents are decoded in `_palette_record`, where the evidence is written
## down; cycling and the fades are flags in it rather than separate records.
const PALETTE_AT := 240
const PALETTE_CYCLING_FLAG := 0x80
const PALETTE_FADE_MASK := 0x60
const PALETTE_FADE_BLACK := 0x60
const PALETTE_FADE_WHITE := 0x40
const PALETTE_AUTO_REVERSE_FLAG := 0x10
const PALETTE_OVER_TIME_FLAG := 0x04
## Director's two score sound channels are main-channel records 3 and 4, at
## 48 * 3 and 48 * 4. See `_sound_channels` for how that is arrived at and for
## what this corpus can and cannot confirm about it.
const SOUND_CHANNEL_AT := [144, 192]
## Frames between buffer snapshots. Seeking replays at most this many deltas, so
## it trades a little memory for random access: 44 snapshots of 48 KB on the
## longest movie here, against decoding all 2784 frames up front.
const KEYFRAME_INTERVAL := 64

var frame_count: int = 0
var frames_version: int = 0
var sprite_record_size: int = 0
var channels: int = 0
## How many sprite channels this movie actually uses. Read, never assumed: the
## widely-quoted 120 truncates the movies that write up to channel 150.
var channels_displayed: int = 0
var error: String = ""

var _intervals: Array[Dictionary] = []
## The frame stream, kept so a frame can be materialised on demand.
var _stream := PackedByteArray()
## Where each frame's record starts in `_stream`.
var _frame_at := PackedInt32Array()
## Buffer state after every KEYFRAME_INTERVAL-th frame, keyed by frame index.
var _keyframes: Dictionary = {}
## Frame rate per frame. Tempo is rewritten to zero on frames that carry none
## while the rate it set persists, so the carry-forward is resolved during the
## scan rather than needing the previous frame to already be decoded.
var _fps := PackedFloat32Array()
var _buffer_size := 0
var _cached_index := -1
var _cached: Dictionary = {}


func parse(payload: PackedByteArray) -> bool:
	error = ""
	_intervals.clear()
	if payload.size() < 28:
		error = "VWSC too short (%d bytes)" % payload.size()
		return false
	if _i32(payload, 4) != SCORE_LIST_MARKER:
		error = "not a D5+ score list (marker %d)" % _i32(payload, 4)
		return false

	var entry_count := _i32(payload, 12)
	if entry_count <= 0:
		error = "score claims %d entries" % entry_count
		return false
	var offsets_at := 24
	var base := offsets_at + 4 * (entry_count + 1)
	if base > payload.size():
		error = "entry table runs past the chunk"
		return false

	var offsets := PackedInt32Array()
	offsets.resize(entry_count + 1)
	for i in entry_count + 1:
		offsets[i] = _i32(payload, offsets_at + i * 4)

	var entry := func(index: int) -> PackedByteArray:
		if index < 0 or index >= entry_count:
			return PackedByteArray()
		var start: int = base + offsets[index]
		var stop: int = base + offsets[index + 1]
		if start < 0 or stop > payload.size() or stop < start:
			return PackedByteArray()
		return payload.slice(start, stop)

	if not _read_frames(entry.call(0)):
		return false
	# Entries 0 and 1 are the frame stream and an id table; intervals start at 2.
	for i in range(2, entry_count):
		var primary: PackedByteArray = entry.call(i)
		if primary.size() < 44:
			continue
		var secondary := PackedByteArray()
		for j in range(i + 1, entry_count):
			var next: PackedByteArray = entry.call(j)
			if next.is_empty():
				continue
			if next.size() == 8:
				secondary = next
			break
		_read_interval(primary, secondary)
	return true


func _read_frames(stream: PackedByteArray) -> bool:
	if stream.size() < 20:
		error = "frame stream too short"
		return false
	var stream_size := _i32(stream, 0)
	var header_len := _i32(stream, 4)
	frame_count = _i32(stream, 8)
	frames_version = _i16(stream, 12)
	sprite_record_size = _i16(stream, 14)
	channels = _i16(stream, 16)
	channels_displayed = _i16(stream, 18)
	if sprite_record_size != SPRITE_RECORD_SIZE:
		error = "sprite record is %d bytes, expected %d" % [sprite_record_size, SPRITE_RECORD_SIZE]
		return false

	# One trailing record of slack, so a delta landing on the boundary is caught
	# by the bounds test rather than by a resize.
	var buffer := PackedByteArray()
	buffer.resize(MAIN_CHANNEL_SIZE + SPRITE_RECORD_SIZE * (channels + 1))

	# The stream is scanned once: frame boundaries are recorded, the buffer is
	# snapshotted periodically, and nothing is decoded. Building every frame's
	# sprite list here cost 481 ms on the longest movie to answer a question the
	# runtime asks about one frame at a time.
	_stream = stream
	_buffer_size = buffer.size()
	_frame_at = PackedInt32Array()
	_fps = PackedFloat32Array()
	_keyframes.clear()
	_cached_index = -1

	var at := header_len
	var limit: int = min(stream.size(), stream_size if stream_size > 0 else stream.size())
	# Director's default until a frame writes a tempo. Starting at zero made
	# every frame before the first tempo report 0 fps, and six movies in this
	# game never set one at all, so they reported 0 for their whole length.
	var carried_fps := 15.0
	while at + 2 <= limit:
		var frame_size := _u16(stream, at)
		if frame_size == 0:
			break
		var index := _frame_at.size()
		_frame_at.append(at)
		if not _apply(stream, at, buffer):
			error = "frame %d writes outside the channel buffer" % index
			return false
		if buffer[54] == TEMPO_SET_FPS:
			carried_fps = float(buffer[53])
		_fps.append(carried_fps)
		if index % KEYFRAME_INTERVAL == 0:
			_keyframes[index] = buffer.duplicate()
		at += frame_size
	# The header's count is what the movie declares; the stream is what it has.
	frame_count = _frame_at.size()
	return true


## Apply one frame's deltas to the channel buffer. Deltas are byte ranges, not
## channel records — Director writes several adjacent 48-byte records in one go.
func _apply(stream: PackedByteArray, at: int, buffer: PackedByteArray) -> bool:
	var frame_end: int = at + _u16(stream, at)
	var cursor := at + 2
	while cursor + 4 <= frame_end and cursor + 4 <= stream.size():
		var chunk_size := _u16(stream, cursor)
		var offset := _u16(stream, cursor + 2)
		cursor += 4
		if offset < 0 or offset + chunk_size > buffer.size() or cursor + chunk_size > stream.size():
			return false
		for k in chunk_size:
			buffer[offset + k] = stream[cursor + k]
		cursor += chunk_size
	return true


## Frame N, decoded on demand. Replays from the nearest snapshot at or before it,
## so a seek costs at most KEYFRAME_INTERVAL deltas rather than the whole movie.
func frame(index: int) -> Dictionary:
	if index == _cached_index:
		return _cached
	if index < 0 or index >= _frame_at.size():
		return {}
	_cached_index = index
	_cached = _snapshot(_buffer_at(index), index)
	return _cached


## The channel buffer as of frame N, undecoded. Split out of `frame` so a survey
## can read bytes this decoder does not claim to understand yet: "offset 60 is
## always zero across the corpus" is a measurement, and it cannot be taken
## through a view that only exposes the fields already decoded.
func _buffer_at(index: int) -> PackedByteArray:
	var base: int = (index / KEYFRAME_INTERVAL) * KEYFRAME_INTERVAL
	while base > 0 and not _keyframes.has(base):
		base -= KEYFRAME_INTERVAL
	var buffer: PackedByteArray = (
		_keyframes[base].duplicate() if _keyframes.has(base)
		else _fresh_buffer()
	)
	var from: int = base + 1 if _keyframes.has(base) else 0
	for i in range(from, index + 1):
		_apply(_stream, _frame_at[i], buffer)
	return buffer


## The 288-byte main channel block of frame N, for tools that survey raw bytes.
func main_channel(index: int) -> PackedByteArray:
	if index < 0 or index >= _frame_at.size():
		return PackedByteArray()
	return _buffer_at(index).slice(0, MAIN_CHANNEL_SIZE)


## The whole channel buffer on frame N, for the same reason `main_channel` exists
## and the reason `_buffer_at` was split out: a survey has to be able to read
## bytes this decoder does not claim to understand, and it cannot do that through
## a view that only exposes the fields already decoded. Returned whole rather
## than per channel because the buffer costs a replay to materialise and a survey
## wants every channel of the frame it just paid for.
## `tools/sprite_record_bytes.gd` is what settled where the flags byte lives, and
## it could not have been written against the dictionary `frame()` returns.
func channel_buffer(index: int) -> PackedByteArray:
	if index < 0 or index >= _frame_at.size():
		return PackedByteArray()
	return _buffer_at(index)


func _fresh_buffer() -> PackedByteArray:
	var buffer := PackedByteArray()
	buffer.resize(_buffer_size)
	return buffer


## The channel buffer as it stands is frame N. Only the decoded view is kept —
## holding 48 KB per frame would cost over a hundred megabytes on a long movie.
func _snapshot(buffer: PackedByteArray, index: int) -> Dictionary:
	var sprites: Array[Dictionary] = []
	for channel in range(1, channels_displayed + 1):
		var at := SPRITE_RECORD_SIZE * (channel + CHANNEL_BIAS)
		if at + SPRITE_RECORD_SIZE > buffer.size():
			break
		var cast_id := _u16(buffer, at + 6)
		var height := _i16(buffer, at + 16)
		var width := _i16(buffer, at + 18)
		# Occupancy is member-and-size, not "any non-zero byte": hundreds of
		# thousands of records carry a type byte and no member.
		if cast_id <= 0 or width <= 0 or height <= 0:
			continue
		var ink_byte := buffer[at + 1]
		var cast_lib := _u16(buffer, at + 4)
		var thickness_byte := buffer[at + THICKNESS_AT]
		var color_code := buffer[at + COLOR_CODE_AT]
		sprites.append({
			"channel": channel,
			"cast_lib": 1 if cast_lib == OWN_CAST_LIB else cast_lib,
			# The same field before `0xFFFF` is folded away, because the fold is
			# lossy and one caller cannot afford it. This decoder also reads a
			# *film loop's* mini-score, and there the u16 is not a cast-library
			# number at all -- it is a zero-based index into the owning
			# container's `ccl ` list, in which 1 is a real entry. Folded, "the
			# owning cast" and "`ccl ` entry 1" arrive as the same value with
			# nothing left to tell them apart. See `director_film_loop.gd`.
			"cast_lib_raw": cast_lib,
			"cast_id": cast_id,
			"loc_h": _i16(buffer, at + 14),
			"loc_v": _i16(buffer, at + 12),
			"width": width,
			"height": height,
			"ink": ink_byte & INK_MASK,
			# Masking the ink byte to six bits throws this away. It does not mean
			# "is resized": it means the author resized this sprite deliberately,
			# and all it governs is whether a cast swap may reset the size back to
			# the member's natural one (§1.3). The drawn size is the sprite's own
			# width and height either way.
			"stretch": (ink_byte & STRETCH_FLAG) != 0,
			"trails": (ink_byte & TRAILS_FLAG) != 0,
			"sprite_type": buffer[at],
			"fore_color": buffer[at + 2],
			"back_color": buffer[at + 3],
			# The thickness byte carries four things nobody would guess from its
			# name: the low nibble is the line thickness, 0x10 says the sprite
			# carries a blend, 0x20 and 0x40 are horizontal and vertical flip,
			# and 0x80 marks the sprite as tweened.
			"thickness": thickness_byte & THICKNESS_MASK,
			"has_blend": (thickness_byte & BLEND_FLAG) != 0,
			"flip_h": (thickness_byte & FLIP_H_FLAG) != 0,
			"flip_v": (thickness_byte & FLIP_V_FLAG) != 0,
			# **Decoded, and nothing consumes it, on measured grounds rather than
			# on not having got to it.** 1,326,064 of Piposh 1's 1,886,362 records
			# carry it and 600,968 of Piposh 2's 816,318, so it is not the rare
			# flag it was previously measured to be — that count was zero only
			# because the byte being read was the cast lib's high half.
			#
			# The question a decoded flag raises is whether the player has to
			# interpolate anything, and `tools/tween_survey.gd` answers it: of
			# Piposh 1's 88,197 tweened spans, 22,023 change value on every single
			# frame — a tween already baked into the stream — while others hold
			# one value for the whole span, up to **4,255 frames with zero
			# changes**. A span marked tweened that never changes has nothing to
			# interpolate, so the flag cannot be an instruction to the player; it
			# records that the span was authored in tween mode in the Score
			# window, and the frame stream already carries the result. The
			# reference agrees by omission: it parses the bit, copies it between
			# sprites, masks it *out* of the dirty test (`sprite.cpp:isDirty`
			# compares `_thickness | kTTweened`) and interpolates nothing.
			"tweened": (thickness_byte & TWEENED_FLAG) != 0,
			# Director stores `the blend of sprite` **inverted**: the property is
			# 0-100 and the byte is `(100 - blend) * 255 / 100`, so 0 is opaque
			# and 255 is invisible. `director_ink.gd:blend_alpha` un-inverts it.
			"blend_amount": buffer[at + BLEND_AMOUNT_AT],
			# The colour code, whose two interesting bits are the score's own
			# `moveable` and `editable`. They are the score-authored halves of two
			# properties this port otherwise only ever sees from Lingo, which is
			# why a sprite the author made draggable in the Score window could not
			# be dragged: nothing was reading the flag.
			"moveable": (color_code & MOVEABLE_FLAG) != 0,
			"editable": (color_code & EDITABLE_FLAG) != 0,
			"score_color": color_code & SCORE_COLOR_MASK,
			# Which entry of this same `VWSC` describes the span this record
			# belongs to. Not decoration: entry `sprite_list_idx` opens with the
			# span's first and last frame and the sprite number, and those match
			# the channel and the frames the record actually occupies — checked
			# on four spans of one movie by hand and swept by
			# `tools/tween_survey.gd`, which uses it to group records into spans
			# instead of guessing at boundaries from where the member changes.
			# The reference reads the field and then uses it for nothing.
			"sprite_list_idx": _u32(buffer, at + SPRITE_LIST_IDX_AT),
		})

	var tempo := buffer[54]
	var tempo_cue := buffer[53]
	var script_member := _u16(buffer, 2)
	# The library the frame script lives in, recorded beside the member number.
	# Dropping it forces the caller to find the script by number alone, and
	# member numbers are per cast: a shared cast's script 105 loses to any
	# internal script that happens to be numbered 105, silently, and what runs
	# is a stranger.
	var script_lib := _u16(buffer, 0)
	var out := {
		"frame_index": index,
		"sprites": sprites,
		"frame_script": script_member if script_member > 0 else null,
		"frame_script_lib": 1 if script_lib == OWN_CAST_LIB or script_lib == 0 else script_lib,
		"tempo": tempo,
		"tempo_cue": tempo_cue,
		"delay_ms": tempo_cue * 1000 if tempo == TEMPO_DELAY else 0,
		"wait_click": tempo == TEMPO_WAIT_CLICK,
		# 0 when the frame waits for no sound, otherwise the channel it waits on.
		"wait_sound_channel": _wait_sound_channel(tempo),
		# Which cue point in that sound releases the wait: a 1-based index, or
		# CUE_NEXT / CUE_END. Signed, because those two are negative and reading
		# the operand unsigned turns "wait for the end" into cue point 254.
		"wait_cue": (tempo_cue - 256 if tempo_cue >= 128 else tempo_cue) \
			if _wait_sound_channel(tempo) > 0 else 0,
		"transition_member": _u16(buffer, 98),
		# The library the transition member lives in, two bytes ahead of it, the
		# same pairing the frame script uses. Every one of the five frames in
		# this corpus that names a transition names library 1, so the field is
		# not what distinguishes them — it is here because resolving a member by
		# number alone is the mistake `frame_script_lib` exists to prevent, and a
		# transition in a linked cast would hit it in exactly the same way.
		"transition_lib": 1 if _u16(buffer, 96) == OWN_CAST_LIB else _u16(buffer, 96),
		"palette_member": _u16(buffer, 242),
		"palette": _palette_record(buffer),
		"sound_channels": _sound_channels(buffer),
	}
	out["fps"] = _fps[index] if index < _fps.size() else 0.0
	return out


## The palette channel, whose layout was settled by dumping the whole 48-byte
## record for every frame in the corpus that writes a non-zero byte into it.
## Only six distinct records exist, and they separate the two things it does:
##
##   0000 ffff 00 00 0000 0000 ...   x262   ARCADE1, ARCADE2, DAY1
##   ffff ffff 1e 00 7f7f 0001 0001  x4     HATDAY3 f0, ISHDAY1 f0, MORN2 f0,
##                                          PATDAY1 f0 (MORN2 has 0000 for 7f7f)
##   ffff ffff 14 60 7f7f 0001 0001  x1     strtgame f38
##
## So: cast lib, member, speed, flags, first and last colour, frame count, cycle
## count — with the lib/member pairing the frame script and the transition also
## use. The member is 0xffff on all 267 frames: as an i16 that is -1, Director's
## number for the built-in system Mac palette, and negative ids are how it names
## built-ins. **No frame in this corpus names a custom palette, and 262 of the
## 267 set every effect byte to zero** — a plain "the palette is system Mac",
## which it already was.
##
## The five that do carry effects carry no cycling: bit 0x80 of the flags is set
## on none of them, and speed 30 with first == last is a one-entry range. The
## single frame with non-zero flags is strtgame f38 at 0x60, the fade family
## rather than cycling, over one frame. That is the whole of the palette
## subsystem's exercise in this game — see `tools/palette_survey.gd`, and
## `DIRECTOR_ENGINE.md` §11 for what is deliberately not built on the strength
## of it.
##
## The colour bytes are stored raw. Director writes them offset by 0x80 (0x7f is
## index 255, 0x00 is 128), but every record here has first == last, so nothing
## in this corpus distinguishes that transform from any other and un-applying it
## would be a guess dressed as a decode.
func _palette_record(buffer: PackedByteArray) -> Dictionary:
	if PALETTE_AT + 12 > buffer.size():
		return {}
	var flags := buffer[PALETTE_AT + 5]
	return {
		"cast_lib": 1 if _u16(buffer, PALETTE_AT) == OWN_CAST_LIB else _u16(buffer, PALETTE_AT),
		# Signed: a built-in palette is a negative id, a custom one a member number.
		"member": _i16(buffer, PALETTE_AT + 2),
		"speed": buffer[PALETTE_AT + 4],
		"flags": flags,
		"cycling": (flags & PALETTE_CYCLING_FLAG) != 0,
		# The fade family is a two-bit field, not a flag: 0x00 is a plain palette
		# switch, 0x60 fades to black and 0x40 to white. Reading it as "any bit in
		# the mask" would call 0x20 a fade, and 0x20 is not one — it is a value the
		# reference does not name and this corpus never writes, so it decodes as
		# neither rather than as whichever fade is nearest.
		"fade_to_black": (flags & PALETTE_FADE_MASK) == PALETTE_FADE_BLACK,
		"fade_to_white": (flags & PALETTE_FADE_MASK) == PALETTE_FADE_WHITE,
		"fade": (flags & PALETTE_FADE_MASK) == PALETTE_FADE_BLACK
			or (flags & PALETTE_FADE_MASK) == PALETTE_FADE_WHITE,
		"auto_reverse": (flags & PALETTE_AUTO_REVERSE_FLAG) != 0,
		"over_time": (flags & PALETTE_OVER_TIME_FLAG) != 0,
		"first_color_raw": buffer[PALETTE_AT + 6],
		"last_color_raw": buffer[PALETTE_AT + 7],
		"frame_count": _u16(buffer, PALETTE_AT + 8),
		"cycle_count": _u16(buffer, PALETTE_AT + 10),
	}


## Which sound channel a wait-for-sound tempo names, or 0 for any other tempo.
## Both numberings answer here rather than the caller having to know which
## authoring version wrote the movie.
static func _wait_sound_channel(tempo: int) -> int:
	match tempo:
		TEMPO_WAIT_SOUND_1, TEMPO_WAIT_SOUND_1_D5:
			return 1
		TEMPO_WAIT_SOUND_2, TEMPO_WAIT_SOUND_2_D5:
			return 2
	return 0


## The two score sound channels, as `{channel, cast_lib, cast_id}` for whichever
## of them names a member. A channel that names nothing is left out, so "the
## frame is silent" and "the frame names member 0" are the same empty answer they
## are in Director.
##
## **Where they are.** The main channel block is six 48-byte records and every
## one of them opens with the same pair — `castLib` at +0, member at +2. That is
## confirmed three times over on this corpus: the frame script at 0/2 resolves to
## a `script` member on 14,886 frames, the transition at 96/98 resolves to a
## `transition` member on all five frames that carry one, and the palette record
## at 240/242 was settled independently. Record 0 is the script, 1 the tempo,
## 2 the transition and 5 the palette, which leaves records **3 and 4** for
## Director's two sound channels — the six special channels are exactly tempo,
## palette, transition, sound 1, sound 2 and script.
##
## **Unverified against this corpus, and it cannot be verified against it.** All
## 96 bytes of records 3 and 4 are zero in every one of the 61,371 frames here,
## because this game has no score sound at all to put in them: its 86 containers
## hold 15,297 cast members and not one is of type `sound` — every sound it plays
## is an external file played by `sound playFile` (`tools/sound_survey.gd`). So
## the offsets are deduced from the record layout rather than read off real data,
## and the one thing genuinely undetermined is which of the two records is
## channel 1: they are taken in address order, which is the convention every
## other channel set here follows, but nothing in this corpus can confirm it.
## The first title that ships score sound will.
func _sound_channels(buffer: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in SOUND_CHANNEL_AT.size():
		var at: int = SOUND_CHANNEL_AT[i]
		if at + 4 > buffer.size():
			break
		var member := _u16(buffer, at + 2)
		if member <= 0:
			continue
		var lib := _u16(buffer, at)
		out.append({
			"channel": i + 1,
			"cast_lib": 1 if lib == OWN_CAST_LIB or lib == 0 else lib,
			"cast_id": member,
		})
	return out


## Sprite behaviours and frame scripts, from the interval entries.
func _read_interval(primary: PackedByteArray, secondary: PackedByteArray) -> void:
	if secondary.size() < 4:
		return
	var member := _u16(secondary, 2)
	if member <= 0:
		return
	var sprite_number := _i32(primary, 16)
	_intervals.append({
		# Sprite number 0 is the frame-script channel, not channel -5.
		"kind": "frame" if sprite_number == 0 else "sprite",
		"channel": 0 if sprite_number == 0 else sprite_number - CHANNEL_BIAS,
		"start": _i32(primary, 0) - 1,
		"end": _i32(primary, 4) - 1,
		"script_cast_lib": _i16(secondary, 0),
		"script_member": member,
	})


func intervals() -> Array[Dictionary]:
	return _intervals


## Highest sprite channel this score ever writes. Walks every frame, so it is a
## question to ask once and keep, not one to ask per frame.
func max_channel() -> int:
	var highest := 0
	for i in _frame_at.size():
		for sprite in frame(i)["sprites"]:
			highest = max(highest, int(sprite["channel"]))
	return highest


static func _u16(d: PackedByteArray, o: int) -> int:
	return (d[o] << 8) | d[o + 1]


static func _u32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


static func _i16(d: PackedByteArray, o: int) -> int:
	var v := _u16(d, o)
	return v - 65536 if v >= 32768 else v


static func _i32(d: PackedByteArray, o: int) -> int:
	var v := (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]
	return v - 4294967296 if v >= 2147483648 else v
