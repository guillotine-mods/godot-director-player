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
## A sprite record naming this library means "the movie's own cast".
const OWN_CAST_LIB := 0xFFFF
## Tempo is a sentinel code and `tempo_cue` its operand.
const TEMPO_SET_FPS := 246
const TEMPO_DELAY := 247
const TEMPO_WAIT_CLICK := 248
## The score-list marker the D5+ format writes at offset 4.
const SCORE_LIST_MARKER := -3
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
	var carried_fps := 0.0
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
	_cached_index = index
	_cached = _snapshot(buffer, index)
	return _cached


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
		sprites.append({
			"channel": channel,
			"cast_lib": 1 if cast_lib == OWN_CAST_LIB else cast_lib,
			"cast_id": cast_id,
			"loc_h": _i16(buffer, at + 14),
			"loc_v": _i16(buffer, at + 12),
			"width": width,
			"height": height,
			"ink": ink_byte & INK_MASK,
			# Masking the ink byte to six bits throws this away, and the stored
			# rect is authoring residue whenever it is clear.
			"stretch": (ink_byte & STRETCH_FLAG) != 0,
			"trails": (ink_byte & TRAILS_FLAG) != 0,
			"sprite_type": buffer[at],
			"fore_color": buffer[at + 2],
			"back_color": buffer[at + 3],
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
		"transition_member": _u16(buffer, 98),
		"palette_member": _u16(buffer, 242),
	}
	out["fps"] = _fps[index] if index < _fps.size() else 0.0
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


static func _i16(d: PackedByteArray, o: int) -> int:
	var v := _u16(d, o)
	return v - 65536 if v >= 32768 else v


static func _i32(d: PackedByteArray, o: int) -> int:
	var v := (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]
	return v - 4294967296 if v >= 2147483648 else v
