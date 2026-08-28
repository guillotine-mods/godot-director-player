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
## The same layout as `[offset, size]` pairs, so `writes_between` can ask which
## *fields* a delta's byte range covers rather than only which channel.
##
## Written out beside the prose above rather than derived from `_snapshot`,
## because `_snapshot` reads fields and this describes them: the two are the same
## table read in opposite directions, and only one of them can be a loop. A field
## missing here is a field whose auto-puppet the score can never release, so the
## list is the whole record and not only the parts something currently consumes.
const FIELD_BYTES := {
	"sprite_type": [0, 1],
	"ink": [1, 1],
	"fore_color": [2, 1],
	"back_color": [3, 1],
	"cast_lib": [4, 2],
	"cast_id": [6, 2],
	"sprite_list_idx": [8, 4],
	"loc_v": [12, 2],
	"loc_h": [14, 2],
	"height": [16, 2],
	"width": [18, 2],
	"color_code": [20, 1],
	"blend_amount": [21, 1],
	"thickness": [22, 1],
	"sprite_flags": [23, 1],
	# The green and blue halves of the two true colours. They are fields of this
	# record like any other, and a field missing from this table is a field whose
	# auto-puppet the score can never release -- which for these four would mean a
	# script that had written `the backColor of sprite` once kept its index for
	# the rest of the movie on every channel the score later recoloured.
	"fore_color_g": [24, 1],
	"back_color_g": [25, 1],
	"fore_color_b": [26, 1],
	"back_color_b": [27, 1],
}
const COLOR_CODE_AT := 20
## Bytes 24-27, in the reference's own order (`frame.cpp:readSpriteDataD7`): the
## greens first and the blues after, fore before back in each pair. The *red*
## component of each colour is the byte the palette-index reading uses, 2 and 3.
const FORE_G_AT := 24
const BACK_G_AT := 25
const FORE_B_AT := 26
const BACK_B_AT := 27
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
## that the fore or back colour is a **true colour** whose red component is the
## byte the index reading uses (2 or 3) and whose green and blue are in 24-27,
## rather than an index into the movie's palette.
##
## **Both are decoded now, and the reason they were not is the reason to be
## careful with a number in a comment here.** This line used to end "because
## 1,124 of Piposh 2's records set the back-colour bit and none of Piposh 1's set
## either", which was true and was a measurement of two roots out of eight.
## `tools/sprite_rgb_colour.gd` over all of them:
##
##   root                    records   fore RGB   back RGB
##   itamar-magichat            9615        397        371
##   itamar-park                7671        501        501
##   piposh                  1886362          0          0
##   piposh-dream             766010      55134      55138
##   piposh-en               1872196          9          9
##   piposh-ru               1868941          9          9
##   piposh2                  816318        504       1124
##   rating                    847431         0          0
##
## Piposh Dream states one on **7.2% of its records**, and what it states is not
## an exotic tint: every one of the 57,152 back colours in the whole corpus is
## `(255,255,255)`, and the commonest fore colour is `(0,0,0)` on 32,875 — the
## *default* pair, written the D7 way. Read as indices those are 255 and 0, which
## in Director's 8-bit convention are black and white the other way round, so a
## sprite asking for black on white got white on black: `director_ink.gd`
## repainted the artwork with the pair inverted, and on the 23,343 records whose
## ink is Background Transparent it keyed out the black pixels instead of the
## white ones. `bugs.md` 30.
const SCORE_COLOR_MASK := 0x0F
const FORE_COLOR_RGB_FLAG := 0x10
const BACK_COLOR_RGB_FLAG := 0x20
## Where a decoded true colour lands on the sprite record, and the *only* signal
## that one is there. Named here rather than spelled twice, because the decoder
## writes them and `director_ink.gd` is the one thing that reads them; a sprite
## without the key is a sprite whose colour is an index, which is what every
## record in three of the eight roots is.
const FORE_RGB_KEY := "fore_rgb"
const BACK_RGB_KEY := "back_rgb"
const EDITABLE_FLAG := 0x40
const MOVEABLE_FLAG := 0x80
## A sprite record naming this library means "the movie's own cast".
const OWN_CAST_LIB := 0xFFFF
## The file version at which Director renumbered the tempo cell. `director_config.gd`
## reads it out of the movie's `VWCF`; `parse()` takes it, because **which
## convention the cell is in is a property of the movie and nothing in the byte
## says which** — the two numberings collide outright, and 247 is either "delay
## for the operand in seconds" or "delay nine seconds" depending only on this.
##
## `director_frame_clock.gd:63` carries the same constant for the rate half of
## the same cell. One number in two files is a drift waiting to happen; that file
## already preloads this one, so the fold is a one-line change there and is left
## for whoever owns it.
const FILE_VERSION_D6 := 0x4C2
## Tempo is a sentinel code and `tempo_cue` its operand — **from D6 on**.
const TEMPO_SET_FPS := 246
const TEMPO_DELAY := 247
const TEMPO_WAIT_CLICK := 248
## Wait for a sound to finish, or for a cue point in it, from D6 on. The cue
## index is the operand beside the code (§9.1).
##
## Unexercised by the corpus this port was built on: across all 61 scores and
## 61,371 frames the tempo cell holds only 246, 247 and 248, never either of
## these (`tools/sound_survey.gd`). So the numbering is the reference's.
const TEMPO_WAIT_SOUND_1 := 255
const TEMPO_WAIT_SOUND_2 := 254

## The pre-D6 cell, where the byte is the instruction and there is no operand.
##
## 1-120 is the frame rate itself and is resolved by `director_frame_clock.gd`,
## not here; what is left is the one-shot meanings, and they are a different set
## from D6's rather than a renumbering of it:
##
##   128            wait for a click
##   134, 135       wait on sound channel 2, 1 — with **no cue index**, which is
##                  why `wait_cue` reads 0 on this path however the operand byte
##                  happens to sit
##   136 .. 195     wait for the digital video in sprite channel `cell - 135`
##   196 .. 255     delay for `256 - cell` seconds
##
## The delay band starts at `256 - maxDelay`, and `maxDelay` is 60 from D4 on —
## 95 in D3 and 120 before that, which would put the band at 161 and 136 and
## overlap the digital-video range. Only the D4-and-later split is decoded: the
## container formats this port reads begin at D4, so a D3 movie could not get
## this far to be decoded wrongly.
##
## The collision with D6 is total and silent. Read a D6 movie with these rules
## and its `set the rate to 8` (246, operand 8) becomes a ten-second delay; read
## a D5 movie with D6's and its two-second delay (254) becomes a wait on a sound
## channel that will never report busy. Neither raises anything.
const TEMPO_D5_WAIT_CLICK := 128
const TEMPO_D5_WAIT_SOUND_2 := 134
const TEMPO_D5_WAIT_SOUND_1 := 135
const TEMPO_D5_VIDEO_FIRST := 136
const TEMPO_D5_VIDEO_CHANNEL_BIAS := 135
const TEMPO_D5_DELAY_FIRST := 196
## Cue indices with a meaning other than "the Nth cue point": Director writes -1
## for "the next one" and -2 for "the end of the sound".
const CUE_NEXT := -1
const CUE_END := -2
## The score-list marker the D5+ format writes at offset 4.
const SCORE_LIST_MARKER := -3
## One `BehaviorElement` of a span's behaviour entry: the script's cast library
## and member number, then the entry index of its authored parameters. See
## `_read_interval` for how the width was settled.
const BEHAVIOUR_ELEMENT_SIZE := 8
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
## The movie's own file version, as `parse()` was told it. 0 means "not told",
## which is read as D6-or-later — the convention every container in both corpora
## here is in, and the one the decoder used unconditionally before this existed.
var file_version: int = 0
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
var _buffer_size := 0
var _cached_index := -1
var _cached: Dictionary = {}
## channel -> the frames on which it carries a member, built on demand by
## `_scan_occupancy` for `last_occupied`. Score data, so it is built once and
## never invalidated.
var _occupied: Dictionary = {}


## `file_version` is the movie's own, from its config chunk. It is a parameter
## rather than a field set afterwards because the frame scan reads the tempo cell
## as it goes, and a version arriving after `parse()` would be a version that
## arrived too late for half the work it governs.
func parse(payload: PackedByteArray, movie_file_version: int = 0) -> bool:
	error = ""
	file_version = movie_file_version
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
	#
	# A span is three consecutive entries — its info record, its behaviour list
	# and a name string — and a sprite record reaches the last two by adding 1
	# and 2 to the `sprite_list_idx` it carries (`score.cpp:2107-2121`). So the
	# behaviour list is entry `i + 1` and can never be a later one. This used to
	# skip empty entries looking for it, which is the same answer by luck: after
	# an empty behaviour entry comes an empty name entry and then the next span's
	# info record, which is not 8 bytes wide, so the search gave up. Measured
	# over all three corpora it took a later entry **0 times** in 528,168 spans,
	# and the interval it produced was claimed by the record occupying that
	# channel and span **every time** — 2,680, 6,202 and 5,365 spans, 0 orphans.
	# Said here because the opposite was written down and acted on: the port
	# narrowed §4.3's clause 4 on the strength of attachments supposedly handed
	# to the wrong span, and that is not what the data says. The attachments
	# naming a bitmap are the record's own; see `preview/interaction.gd`.
	# **Entries named as behaviour initialisers are not span records**, and the skip
	# set is what stops the scan reading one as if it were. An initialiser entry is
	# a Lingo property-list *string* -- see `_read_interval` -- and the longer ones
	# clear the 44-byte floor: `[#prSprite: 7, #prSoundLoop: 0, #prSound: "",
	# #prBackToGame: 0, #prFreezFlash: 0, #prPlayMuisc: 0]` is 100 bytes in
	# `itamar-magichat/trivia/trivia.dir`, so without this the scan reads `dLoo` as
	# a sprite number and two ASCII words as a frame range and appends an interval
	# that is entirely text. Measured over all eight corpus roots by
	# `tools/behaviour_params.gd --survey`, which walks the entry table both ways
	# and diffs them: the scan without this set produces **122 intervals that are
	# not spans, every one of them `itamar-magichat`'s, and 0 in the six shipped
	# titles**. That is also why this cannot change what any shipped title decodes
	# -- a corpus that authors no initialiser has an empty set here and takes the
	# identical path -- and the survey asserts the diff is 0 the other way, so the
	# set can be seen not to have eaten a real span.
	#
	# The set is filled as the scan goes rather than in a pass of its own, and that
	# works because an initialiser entry is written *after* the span that names it:
	# every element in the corpus names a higher index. A backward reference would
	# be marked too late to skip, and it is recorded as a hazard rather than
	# guarded, because guarding it needs a first pass that is itself reading text as
	# spans -- the circularity this note exists to name.
	var initialisers: Dictionary = {}
	for i in range(2, entry_count):
		if initialisers.has(i):
			continue
		var primary: PackedByteArray = entry.call(i)
		if primary.size() < 44:
			continue
		_read_interval(i, primary, entry.call(i + 1), entry, initialisers)
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
	_keyframes.clear()
	_cached_index = -1

	# **No frame rate is resolved here any more, and none is published.** This
	# scan used to carry a rate forward from a literal 15.0 and hand it to every
	# frame as `fps`, which made the number a fabrication twice over: a movie
	# whose score never writes a tempo got the decoder's own guess reported as its
	# rate — 56 of Piposh 1's 99 scores, every one of them stating 2-12 in its
	# config — and the carry-forward applied D6's numbering to whatever version
	# the movie was in. `director_frame_clock.gd` resolves the rate now, from the
	# raw cell and the file version, and it is the only thing that does; a decoder
	# that also published an answer was a second source for one fact, and the
	# second source was the wrong one.
	var at := header_len
	var limit: int = min(stream.size(), stream_size if stream_size > 0 else stream.size())
	while at + 2 <= limit:
		var frame_size := _u16(stream, at)
		if frame_size == 0:
			break
		var index := _frame_at.size()
		_frame_at.append(at)
		if not _apply(stream, at, buffer):
			error = "frame %d writes outside the channel buffer" % index
			return false
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


## Which fields of which channels the **score itself writes** moving the playhead
## from frame `from` to frame `to`: `{channel: {field: true}}`, in the field names
## `_snapshot` decodes to.
##
## This is the delta stream answering a question only a delta stream can answer,
## and it is a different question from "did the value change". Director keeps one
## live sprite per channel and patches it from the frame's delta; the auto-puppet
## a script leaves on a property is released **when the score writes that
## property**, whatever it writes (§5.3, reference `Sprite::releaseAutoPuppet`,
## driven by the frame sprite's `_copyBackMask` — the set of fields the frame's
## own delta touched). A score that rewrites a channel with the member it already
## had still writes it, and still releases.
##
## Nothing that reads `frame()` can see that: `frame()` is the accumulated buffer,
## so it answers what a channel *holds* and never what was written to get there.
## That is why a port built on it has to approximate the release by comparing
## values, and why the approximation is wrong in exactly the case where a clip
## and the room it was entered from happen to put the same member on a channel
## (`bugs.md` 47).
##
## Four cases. Three are the reference's, from `Score::loadFrame`; the rewind is
## the one deliberate divergence in this file and carries its reason below.
##
## - `from < 0` — no frame has been entered yet, so nothing has been written
##   *since* one. There is no live channel state for the score to have moved.
## - `to == from` — the playhead has not moved. The reference does not release at
##   all on this path: `Score::update`'s second branch is the same-frame `go to
##   frame` case and it calls `updateSprites` without `releaseAutoPuppet`.
## - `to < from` — the target frame's **own** delta, and this is the one place this
##   function deliberately does not copy the reference. `Score::loadFrame` cannot
##   walk a delta stream backwards, so it rebuilds from the start of the movie and
##   sets the mask to all-ones for the whole rebuild (`score.cpp:2211`, commented
##   *"starting from rewind, copy back everything"*). That is a consequence of its
##   storage and not a rule of Director's: the mask is *defined* as the fields the
##   frame's own delta touched, and moving backwards does not change which fields
##   those are. Taken literally it releases every auto-puppet on every channel on
##   every backward `go`, which breaks any movie whose idle loop jumps back while
##   holding one — `piposh-dream/puzzle.dir` loops `go("start")` from f9 to f6 for
##   ever and its sliding-tile board reverted to the solved picture within four
##   frames of a move (`docs/bugs-closed.md` 120).
##   **Not the union over the rebuild path**, which is all-ones by another name:
##   replaying from frame 0 writes every channel the movie ever sets. And the
##   blanket is not what keeps `bugs.md` 47 closed — both legs of that journey
##   release through the target frame's own delta, which is why
##   `tools/puppet_persists.gd` still passes.
## - `to > from` — the deltas of frames `from + 1 .. to`, unioned. A `go` that
##   skips a thousand frames replays all thousand, so all thousand write.
func writes_between(from: int, to: int) -> Dictionary:
	var out: Dictionary = {}
	if from < 0 or to < 0 or to >= _frame_at.size():
		return out
	if to == from:
		return out
	if to < from:
		_writes_into(to, out)
		return out
	for index in range(from + 1, to + 1):
		_writes_into(index, out)
	return out


## One frame's own delta, as `{channel: {field: true}}`, merged into `out`.
##
## The chunks are byte ranges over the flat channel buffer and a single chunk
## routinely spans several 48-byte records, so this intersects each range with
## each field's extent rather than assuming a chunk is a channel — the same thing
## `_apply`'s header warns about, asked at field granularity.
func _writes_into(index: int, out: Dictionary) -> void:
	var at: int = _frame_at[index]
	if at + 2 > _stream.size():
		return
	var frame_end: int = at + _u16(_stream, at)
	var cursor := at + 2
	while cursor + 4 <= frame_end and cursor + 4 <= _stream.size():
		var chunk_size := _u16(_stream, cursor)
		var offset := _u16(_stream, cursor + 2)
		cursor += 4 + chunk_size
		if chunk_size <= 0:
			continue
		# Channel 1's record starts at `MAIN_CHANNEL_SIZE`, which is
		# `SPRITE_RECORD_SIZE * (CHANNEL_BIAS + 1)` and not
		# `SPRITE_RECORD_SIZE * CHANNEL_BIAS` -- the same base `_snapshot` reads
		# from, and the reference's `kMainChannelSizeD7` in
		# `frame.cpp:readChannelD7`'s `(offset - kMainChannelSizeD7) /
		# kSprChannelSizeD7`. Subtracting one record too few named channel N+1 for
		# a chunk that writes channel N, and the *whole* of the damage was hidden
		# by the field test below: a chunk lying inside one record intersected no
		# field of the record one channel further on, so it reported **nothing**,
		# and a chunk spanning several records lost only its lowest channel.
		# Director writes a channel's sub-ranges far more often than its whole
		# record -- `rating/NAVIGATE.dir` f3 writes bytes 0-7 and 10-19 of
		# nineteen channels in 34 such chunks, which is `sprite_type`, `ink`, both
		# colours, `cast_lib` and `cast_id` -- so `writes_between` answered `{}`
		# for a frame that rewrote every one of their members, and every
		# auto-puppet those frames should have released survived.
		var first := maxi(1, (offset - MAIN_CHANNEL_SIZE) / SPRITE_RECORD_SIZE + 1)
		var last := (offset + chunk_size - 1 - MAIN_CHANNEL_SIZE) / SPRITE_RECORD_SIZE + 1
		for channel in range(first, mini(last, channels_displayed) + 1):
			var base := SPRITE_RECORD_SIZE * (channel + CHANNEL_BIAS)
			var fields: Dictionary = out.get(channel, {})
			for field in FIELD_BYTES:
				var extent: Array = FIELD_BYTES[field]
				var start: int = base + int(extent[0])
				if offset < start + int(extent[1]) and offset + chunk_size > start:
					fields[field] = true
			if not fields.is_empty():
				out[channel] = fields


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


## The greatest frame at or before `index` on which `channel` carries a member,
## or -1 when it never has.
##
## **What it is for.** `the constraint of sprite N` clamps against another
## channel's box, and Director's own words for what that box is when the score
## has since blanked the channel are in `channel.cpp:getRollOverBbox` --
## "whatever the last contents of the sprite were, regardless of whether the
## score has zeroed it out". `scenes/preview/interaction.gd:constraint_box` needs
## that frame and nothing else about it.
##
## **Read off the delta stream, not off `frame()`.** Occupancy is `_snapshot`'s
## own test -- the record's member word, bytes 6 and 7 -- so the two bytes are
## tracked through the same chunk walk `_apply` performs and every frame is
## classified in one pass over the stream. Asking `frame()` per frame would
## decode up to 150 sprite records a frame to read one word, and would evict the
## one-frame cache the runtime is using for the frame it is actually on.
##
## Built once per channel and kept, because a movie's score does not change under
## it. Channels are asked for this only where a constraint names one, which is
## `constraint_box`'s early return away from every sprite in every other movie.
func last_occupied(channel: int, index: int) -> int:
	if channel <= 0 or index < 0 or _frame_at.is_empty():
		return -1
	if not _occupied.has(channel):
		_occupied[channel] = _scan_occupancy(channel)
	var frames: PackedInt32Array = _occupied[channel]
	var best := -1
	for frame_index in frames:
		if frame_index > index:
			break
		best = frame_index
	return best


## Every frame on which `channel`'s record names a member, in order.
##
## The member word is at `base + 6`, so only chunks overlapping those two bytes
## can change it; everything else in the stream is skipped without being read.
func _scan_occupancy(channel: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base := SPRITE_RECORD_SIZE * (channel + CHANNEL_BIAS)
	var hi := 0
	var lo := 0
	for index in _frame_at.size():
		var at: int = _frame_at[index]
		if at + 2 > _stream.size():
			break
		var frame_end: int = at + _u16(_stream, at)
		var cursor := at + 2
		while cursor + 4 <= frame_end and cursor + 4 <= _stream.size():
			var chunk_size := _u16(_stream, cursor)
			var offset := _u16(_stream, cursor + 2)
			cursor += 4
			var payload := cursor
			cursor += chunk_size
			if chunk_size <= 0 or payload + chunk_size > _stream.size():
				continue
			if offset <= base + 6 and offset + chunk_size > base + 6:
				hi = _stream[payload + (base + 6 - offset)]
			if offset <= base + 7 and offset + chunk_size > base + 7:
				lo = _stream[payload + (base + 7 - offset)]
		if (hi << 8) | lo != 0:
			out.append(index)
	return out


## Frame N's tempo cell and its operand, as `(cell, operand)`, without decoding
## anything else about the frame.
##
## The raw pair, not a meaning: what the cell means needs the file version, and
## the two callers that want it want different halves — `director_frame_clock.gd`
## resolves the rate from it and `tools/movie_tempo.gd` checks that resolution
## against the whole corpus.
##
## It exists because `frame()` is the wrong shape for the question. Reading two
## bytes through it costs a full `_snapshot`: up to 150 sprite records decoded
## into a dictionary each, thrown away unread. `movie_tempo.gd` asks it of every
## frame of every movie — about 110,000 frames a corpus — and it is in the gate,
## so that was four to six minutes of every run spent building sprite lists
## nobody looked at. The buffer replay is the same either way; only the decode is
## skipped.
func tempo_at(index: int) -> Vector2i:
	if index < 0 or index >= _frame_at.size():
		return Vector2i.ZERO
	var buffer := _buffer_at(index)
	if buffer.size() < 55:
		return Vector2i.ZERO
	return Vector2i(buffer[54], buffer[53])


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
		# Occupancy is the **member and nothing else**: hundreds of thousands of
		# records carry a type byte and no member, and those are the empty ones.
		# **The reference gates its render walk on `Channel::isEmpty()`**
		# (`channel.cpp:330`), which is `_spriteType == kInactiveSprite` and only
		# that. `Window::render` → `renderChannel` →
		# `Score::getSpriteIntersections` (`score.cpp:1723`) is the one walk that
		# puts a channel on the stage. This comment used to cite `score.cpp:503`
		# and `:2474` for a member test: 503 is the rollOver-bbox cache and 2474 is
		# `formatChannelInfo`, a debug printer. Right rule, wrong two lines.
		#
		# The two tests agree anyway, because `_spriteType` is not the record's
		# type byte by the time `isEmpty` reads it: `Score::loadFrame` ends in
		# `setSpriteCasts()` (`score.cpp:2326`) and `Sprite::setCast`
		# (`sprite.cpp:588`) promotes any non-QuickDraw sprite naming a member to
		# `kCastMemberSprite`. So the reference is empty only when the type byte,
		# the member and the cast lib are all zero — weaker than `member == 0`,
		# and able only to admit records this test drops, never the reverse.
		#
		# **Measured** (`bugs.md` 49, `tools/channel_occupancy.gd`): 65,883,235
		# records over 491 scores in all eight roots, **0 disagreements either
		# way**, with the type byte taking exactly two values — 16 on all
		# 8,079,420 records naming a member and 0 on all 57,803,815 naming none.
		# The one case that would diverge is a QuickDraw *shape sprite* (types
		# 2-6, 12-15, painted from the record with no member); from D5 a shape is
		# a cast member, so no container here can express one. That gap is in
		# `docs/ENGINE_TODO.md`, not here.
		#
		# **A stated size of zero used to be part of this test, and it is not an
		# emptiness signal in Director.** `frame.cpp:396` normalises a
		# non-positive width or height to `0` and keeps reading the record;
		# `Score::setSpriteCasts` (`score.cpp:2329`) then runs
		# `Sprite::setCast(castId, !stretch)` over *every* sprite of every frame
		# it loads, and for a bitmap that replaces `_width`/`_height` with the
		# member's `initialRect` (`sprite.cpp:627-637`). A 0x0 record naming a
		# bitmap therefore draws that bitmap at its natural size, which is
		# already what `sprite_geometry.drawn_size` does — the record was being
		# thrown away one layer earlier than the rule that handles it.
		#
		# Dropping it lost the record's **position and ink** as well as its size,
		# and that is what made it a bug rather than a redundancy. Removing the
		# size half admits 4,506 records in `itamar-park` and 370 across the six
		# shipped titles (`tools/scratch/zerosize.gd`, `bugs.md` 94's own count),
		# three groups of which name a member with real pixels
		# and so could put art on the stage that was not there
		# (`tools/scratch/zerosize_frames.gd` lists the frames;
		# `tools/scratch/chantimeline.gd` shows what the channel holds around
		# them). **All three were rendered before and after and looked at**, not
		# counted:
		#
		# - `piposh2 PIP2DATA/GOLDDEAD.dir` ch1 holds `1:3 a1`, the 640x400 room
		#   backdrop, at `loc(320,200)` ink 0 continuously from frame 0 to 1340 —
		#   except that the record states 0x0 on frames 944-962 and 964-970.
		#   Member, position and ink are identical either side of both gaps, so
		#   the filter was punching a 19-frame and a 7-frame hole in a backdrop
		#   that is on screen before and after it. On the stage it makes **no
		#   difference at all**: `tools/director_render.gd` on frames 943, 944,
		#   950, 955, 960, 962, 963, 964, 967, 970 and 971 is byte-identical with
		#   the filter and without it, because this is the darkened-stage scene
		#   and ch36's 654x409 `1:37` covers `a1` completely on every one of
		#   them. Admitting the record restores a hidden backdrop, which is the
		#   right state to be in and costs nothing to look at.
		# - `rating` ch48 holds `2:33 GlobalTime`, the 79x24 clock field, at a
		#   fixed `loc` and ink 36. `BLABOMB.dir` states its size as 88x36 on
		#   frames 6-13, 60-83 and 96-476 and as 0x0 on 2-5, 14-59 and 84-95 —
		#   the same hole, 176 frames of it across 11 movies. This one **is**
		#   visible, and it was a missing HUD element rather than a spurious one:
		#   `tools/scene_probe.gd --root rating --movie BLABOMB.dir --frame 20`
		#   photographs an empty rounded box beside the "שעה" (hour) label before
		#   the change and `07:01` in it after. `director_render.gd` cannot see
		#   this — it prints `skipped (field)` — which is why the shot has to come
		#   off the real preview.
		# - `piposh-dream meet7.dir` ch15 is the one group that is not a hole:
		#   `12:5` is the channel's only state, stated 2x0 on frames 337-471. The
		#   member is the 48x31 tuft of grass the *same* frame already draws from
		#   ch17, and the record puts a second one at `loc(469,430)` — rect
		#   `(445,415 48x31)` through the preview, on the ground beside the milk
		#   churn in the lower right, keyed by its own ink 36 and partly behind
		#   the churn. Photographed at frame 403 before and after: the scene is
		#   identical but for that tuft. It is scenery that belongs, so the
		#   change ships whole rather than as a position-and-ink-only variant.
		#
		# The fourth group is `1:86`, a 1x1 bitmap on three `piposh-dream`
		# frames, and `itamar-park`'s 4,506 are `1:60 ObjBlnk`, a 0x0 member —
		# `drawn_size` returns 0x0 for a 0x0 member, so neither draws anything
		# and both arrive with the position and ink the record carries. Park's
		# arcade is built on that (`bugs.md` 94), and it is the ink half that
		# nobody had noticed: with the record dropped, `channel.gd:_bare_sprite`
		# is what the object scripts write over and its ink is 0, Copy, so the
		# obstacles drew their paper as a white box. Measured through
		# `tools/scratch/chanink.gd` on the arcade — before, channels 21-39 all
		# report ink 0 at `locV` 0; after, channels 20-37 report ink 36 at
		# `locV` 340/210/110, the three ice rows.
		if cast_id <= 0:
			continue
		var height := _i16(buffer, at + 16)
		var width := _i16(buffer, at + 18)
		var ink_byte := buffer[at + 1]
		var cast_lib := _u16(buffer, at + 4)
		var thickness_byte := buffer[at + THICKNESS_AT]
		var color_code := buffer[at + COLOR_CODE_AT]
		var record := {
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
		}
		# The true colours, present only on the records that state one, so that
		# `has()` is the question "is this an index or a colour" and no consumer
		# has to carry a second flag beside the value. `fore_color`/`back_color`
		# keep the raw byte either way: it is still what `the foreColor of sprite`
		# answers, and it is still the red component of the colour beside it.
		if (color_code & FORE_COLOR_RGB_FLAG) != 0:
			record[FORE_RGB_KEY] = Color8(
				buffer[at + 2], buffer[at + FORE_G_AT], buffer[at + FORE_B_AT])
		if (color_code & BACK_COLOR_RGB_FLAG) != 0:
			record[BACK_RGB_KEY] = Color8(
				buffer[at + 3], buffer[at + BACK_G_AT], buffer[at + BACK_B_AT])
		sprites.append(record)

	var tempo := buffer[54]
	var tempo_cue := buffer[53]
	var script_member := _u16(buffer, 2)
	# The library the frame script lives in, recorded beside the member number.
	# Dropping it forces the caller to find the script by number alone, and
	# member numbers are per cast: a shared cast's script 105 loses to any
	# internal script that happens to be numbered 105, silently, and what runs
	# is a stranger.
	var script_lib := _u16(buffer, 0)
	var waits := _tempo_waits(tempo, tempo_cue)
	var out := {
		"frame_index": index,
		"sprites": sprites,
		"frame_script": script_member if script_member > 0 else null,
		"frame_script_lib": 1 if script_lib == OWN_CAST_LIB or script_lib == 0 else script_lib,
		"tempo": tempo,
		"tempo_cue": tempo_cue,
		"delay_ms": waits["delay_ms"],
		"wait_click": waits["wait_click"],
		# 0 when the frame waits for no sound, otherwise the channel it waits on.
		"wait_sound_channel": waits["wait_sound_channel"],
		# Which cue point in that sound releases the wait: a 1-based index, or
		# CUE_NEXT / CUE_END. Signed, because those two are negative and reading
		# the operand unsigned turns "wait for the end" into cue point 254.
		"wait_cue": waits["wait_cue"],
		# The sprite channel whose digital video this frame waits for, or 0.
		# **Decoded and nothing consumes it**: the clock's `enter_frame` reads the
		# other three waits and not this one, and no member in either corpus is a
		# digital video for it to wait on. It is here because it is what the cell
		# means — leaving it undecoded is what made a D6 movie's video wait on
		# channel 1 read as a *sound* wait on channel 2 below, which is a hold the
		# playhead would never have been released from.
		"wait_video_channel": waits["wait_video_channel"],
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
	return out


## Everything the tempo cell stops the playhead for, in this movie's convention.
##
## One function rather than four expressions inline, because the four answers are
## a *partition* of one byte: exactly one of them can be non-empty, and working
## each out separately is how `wait_sound_channel` came to answer 1 for a D6 cell
## of 135 while `delay_ms` was simultaneously answering 0 for the same byte. The
## rate is not here — it persists past the frame that sets it, so it belongs to
## the clock (`rate_from_tempo`) and not to a per-frame decode.
##
## The version split is the whole point; see `FILE_VERSION_D6` above for why a
## byte cannot be read without it. Version 0 means the caller did not say, and is
## taken as D6-or-later: that is what every container in both corpora here is,
## and it is what this decoder assumed unconditionally before the split existed,
## so an un-updated caller keeps exactly the behaviour it had.
##
## **Static, and the file version is a parameter**, because the score is not the
## only thing that has to read a tempo instruction. `puppetTempo` hands the clock
## a value that never came out of a frame at all, and the clock has to work out
## what it stops the playhead for; a second decoder there is the collision this
## function exists to prevent, written twice. `_tempo_waits` below is the
## instance form, which supplies this movie's own version.
static func tempo_waits(tempo: int, operand: int, file_version: int) -> Dictionary:
	var out := {
		"delay_ms": 0, "wait_click": false,
		"wait_sound_channel": 0, "wait_cue": 0, "wait_video_channel": 0,
	}
	if tempo <= 0:
		return out
	if file_version != 0 and file_version < FILE_VERSION_D6:
		# Pre-D6: the byte is the instruction and carries no operand at all, so
		# `wait_cue` stays 0 — the byte beside it is not a cue index here, and
		# reading it as one would arm a wait on a cue point the sound has not got.
		match tempo:
			TEMPO_D5_WAIT_CLICK:
				out["wait_click"] = true
			TEMPO_D5_WAIT_SOUND_1:
				out["wait_sound_channel"] = 1
			TEMPO_D5_WAIT_SOUND_2:
				out["wait_sound_channel"] = 2
			_:
				if tempo >= TEMPO_D5_DELAY_FIRST:
					out["delay_ms"] = (256 - tempo) * 1000
				elif tempo >= TEMPO_D5_VIDEO_FIRST:
					out["wait_video_channel"] = tempo - TEMPO_D5_VIDEO_CHANNEL_BIAS
				# 1-120 is the frame rate, which the clock takes; anything left
				# over is a cell this decoder has no meaning for, and saying
				# nothing is the honest answer to it.
		return out
	match tempo:
		TEMPO_SET_FPS:
			pass # A rate, and the clock's business.
		TEMPO_DELAY:
			out["delay_ms"] = operand * 1000
		TEMPO_WAIT_CLICK:
			out["wait_click"] = true
		TEMPO_WAIT_SOUND_1, TEMPO_WAIT_SOUND_2:
			out["wait_sound_channel"] = 1 if tempo == TEMPO_WAIT_SOUND_1 else 2
			# Signed: -1 is "the next cue" and -2 "the end of the sound", and
			# reading the operand unsigned turns the second into cue point 254.
			out["wait_cue"] = operand - 256 if operand >= 128 else operand
		_:
			# From D6 on **every other non-zero cell** waits for the digital video
			# in the sprite channel it numbers. 134 and 135 land here, and that is
			# the fix: they were being read as this format's sound waits, which
			# they are only in the format before it.
			out["wait_video_channel"] = tempo
	return out


## `tempo_waits` in this movie's own convention.
func _tempo_waits(tempo: int, operand: int) -> Dictionary:
	return tempo_waits(tempo, operand, file_version)


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


## Sprite behaviours and frame scripts, from one span's info entry and the
## behaviour entry that follows it.
##
## **The behaviour entry is a stream, not one element.** A D6+ sprite carries a
## *list* of behaviours and `score.cpp:loadFrameSpriteDetails` reads it as one --
## `while (stream->pos() < stream->size())`, pushing a `BehaviorElement` per pass
## -- where this used to take the entry only when it was exactly one element wide
## and drop a longer one whole. Measured over the three corpora, a span's
## behaviour entry is 0, 8 or 16 bytes and nothing else, so the element is 8 and
## the stride is the whole of what was missing: **2 spans of 158,001 in Piposh 2
## and 5 of 271,872 in Piposh 1 carry two, 0 of 98,295 in Rating.** Both of
## Piposh 2's name the *same* script twice, which Director answers by
## instantiating two behaviour objects and running the handler twice.
##
## The element's second half is `initializerIndex`, **an entry index holding the
## values an author typed into the behaviour's parameter dialog for this span**,
## and it is read here now (`bugs.md` 83). It is 0 in all 14,903 elements of
## Piposh 2 -- which is the corroboration that the element is 8 bytes rather than
## 4 with padding -- and 0 in all six shipped titles. `tools/behaviour_params.gd
## --survey` over all eight corpus roots, 677 containers and 491 scores: it walks
## 127,559 behaviour elements and **82 spans carry an authored initialiser, every
## one of them `test-games/itamar-magichat`'s**. That is the whole population, and
## it is why this cost nothing for as long as nobody looked.
##
## **The entry is a NUL-terminated Lingo property-list literal**, padded to a
## 4-byte boundary, and it is stored on the interval verbatim rather than
## evaluated here. `Score::loadSpriteBehavior` reads it with a plain
## `stream1->readString()` (`score.cpp:2062-2075`) and the evaluation happens much
## later and somewhere else -- `Score::createScriptInstance` pushes the string
## through `LB::b_value` at the moment the behaviour is instantiated
## (`lingo-events.cpp:900-935`). Keeping that split matters here for the same
## reason it does there: this file decodes a container and owns no interpreter,
## and a property list parsed at load time would be parsed by a second dialect
## that nothing else in the port uses. What the corpus actually holds:
##
##     [#prHide: 0]                      12 chars in a 16-byte entry
##     [#prFrameStep: 4]                 16 in 20
##     [#prGotoFrame: "mainmenu"]        26 in 28
##     [#prSpritesList: [], #prFreezJinny: "1"]        39 in 44
##
## so the terminator is real and the slack is alignment, not content.
##
## The **script channel** takes one element however long its entry is, which is
## the reference's own asymmetry: `loadFrameSpriteDetails` comments "We can have
## only one behavior here" and pushes a single element for the main channel while
## looping over a sprite's.
## `entry` fetches an entry of the score list by index -- `getSpriteDetailsStream`
## -- so that an element naming an initialiser can open it. `initialisers` is the
## scan's skip set and is written here for the reason `parse` gives.
func _read_interval(index: int, primary: PackedByteArray, behaviours: PackedByteArray,
		entry: Callable, initialisers: Dictionary) -> void:
	var sprite_number := _i32(primary, 16)
	# Sprite number 0 is the frame-script channel, not channel -5.
	var kind := "frame" if sprite_number == 0 else "sprite"
	var at := 0
	while at + BEHAVIOUR_ELEMENT_SIZE <= behaviours.size():
		var member := _u16(behaviours, at + 2)
		var initializer_index := _i32(behaviours, at + 4)
		var params := ""
		if initializer_index > 0:
			initialisers[initializer_index] = true
			params = _entry_string(entry.call(initializer_index))
		if member > 0:
			_intervals.append({
				"kind": kind,
				"channel": 0 if sprite_number == 0 else sprite_number - CHANNEL_BIAS,
				"start": _i32(primary, 0) - 1,
				"end": _i32(primary, 4) - 1,
				"script_cast_lib": _i16(behaviours, at),
				"script_member": member,
				# The parameter dialog's values for *this span*, as authored, and
				# the entry they came out of. Both are carried: the string is what
				# a consumer evaluates, and the index is what says "there was one"
				# when the string is empty, which a title with an empty initialiser
				# entry would otherwise be indistinguishable from.
				"initializer_index": initializer_index,
				"initializer_params": params,
				# Which entry this span is, so a consumer can match a sprite
				# record to its own behaviours exactly rather than by channel and
				# frame range. Nothing needs it yet -- the two agree on every one
				# of the corpus's 14,247 spans, measured -- and it is here so
				# that the day they disagree is a lookup change and not a decode
				# change.
				"sprite_list_idx": index,
			})
		if kind == "frame":
			return
		at += BEHAVIOUR_ELEMENT_SIZE


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


## One score-list entry read as text, exactly as far as `readString()` would go.
##
## `Common::ReadStream::readString()` stops at the first NUL or at the end of the
## stream, and both arms happen here: the initialiser entries are NUL-terminated
## and then padded to a 4-byte boundary, so `[#prHide: 0]` arrives as 12 bytes of
## text, one terminator and three bytes of slack in a 16-byte entry. Decoding the
## whole entry instead would hand the interpreter a string with NULs in it, which
## `value()` answers VOID for -- the same failure as not reading the entry at all,
## and harder to see.
static func _entry_string(bytes: PackedByteArray) -> String:
	var stop := bytes.find(0)
	if stop < 0:
		stop = bytes.size()
	return bytes.slice(0, stop).get_string_from_utf8()


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
