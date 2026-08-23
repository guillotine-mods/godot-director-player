extends RefCounted
## The reader `scenes/preview/video.gd` drives for an MPEG-1 file: the system
## demuxer and the video decoder joined, plus the two things neither of them can
## answer on its own — how long the clip is, and which coded picture a given
## *display* frame is.
##
## ## The interface, and why it is the AVI reader's
##
## `director/director_avi.gd` established the shape of a **pull** backend:
## `open`, `close`, `backend`, `duration_ms`, `frame_index_at(ms)`,
## `frame_at(index)`, `audio_stream()` and the four audio facts. `preview/video.gd`
## drives all of it without knowing which reader it has, so this file implements
## the same names and nothing else — a third pull backend cost that file one arm
## in `_open` and no other line.
##
## ## Coded order is not display order, and that is the whole of the reordering
##
## MPEG-1 codes a picture *after* both the pictures it predicts from, so a group
## coded `I0 P3 B1 B2 P6 B4 B5` is displayed `I0 B1 B2 P3 B4 B5 P6`. A decoder
## therefore always holds a reference picture that has been decoded and not yet
## shown, and the reordering is one rule:
##
##   * a **B** picture is displayed the moment it is decoded;
##   * an **I** or **P** picture is displayed when the *next* I or P is decoded,
##     because that is the moment every B that displays before it has been seen;
##   * the last one is displayed when the stream ends.
##
## That is implemented as `_step`, and it is what makes display index and coded
## index line up without a scan of the file. **Sequential playback never decodes a
## picture twice** and never seeks: display frame N+1 is always the next thing
## `_step` produces. That property is the reason this is done by streaming rather
## than by building an index of `temporal_reference` up front — an index would
## need a pass over 12.6 MB before the first picture could be shown, and would
## then be re-derivable from the same streaming rule anyway.
##
## ## Seeking backwards
##
## Restart points are recorded as they are passed — one per I picture, holding the
## bit offset and the display index that was next at that moment — so a backward
## seek rewinds to the latest one that can produce the wanted frame and decodes
## forward. Nothing is recorded for a part of the file that has never been
## decoded, so a seek into unvisited territory decodes from the beginning; that is
## the honest cost of not scanning the file, and it is paid by a harness rather
## than by a movie, because a movie plays forwards.
##
## ## The duration, and why it does not come from counting pictures
##
## `docs/DIGITAL_VIDEO.md` §3's first rule is that `the duration of member` must
## not be a confident guess and must not be a zero for a file that really opened —
## Magic Hat's `Check avi` reads it before the first tick of playback and
## `BehaviorScript 134`'s other arm is `go(the frame)` for ever. Counting the
## pictures would mean decoding the whole clip inside a property read. So the
## duration comes from the **system layer's presentation clock**, which
## `director_mpeg1_ps.gd` reads out of the packet headers without touching the
## video layer at all, plus one frame interval from the sequence header — the span
## between the first and last picture *shown* is one frame short of the running
## time.
##
## Measured on `heb/mainmenu/intro.mpg`: 87.48 s of PTS span, 25.000 fps from the
## sequence header, so 87.52 s against the 87.56 s that 2,189 pictures at that rate
## really are. Four hundredths of a second, on a clip whose own guard is
## `>= the duration`, and erring **short** rather than long — which is the safe
## direction, because a duration the playhead can never reach is the hang.
##
## ## What this costs, stated rather than implied
##
## GDScript decodes these clips well below their own frame rate;
## `tools/mpeg1_decode.gd` measures it per clip and prints the fraction of real
## time achieved. `preview/video.gd` computes the frame to show from
## `the movieTime` rather than by counting decoded frames, so a slow decode drops
## pictures and keeps the clock — which is the behaviour a movie polling
## `the movieTime` needs, and is already what that file's header promises for the
## AVI backend.
##
## ## The sound track, and why it is the picture's opposite
##
## `director_mpeg1_audio.gd` decodes the MPEG-1 Layer II track these files carry,
## and the thing worth knowing here is that it cannot be run the way the picture
## is. **A dropped picture is invisible and a dropped sample is a hole**, so the
## trade the paragraph above describes — decode what you can, keep the clock —
## has no audio equivalent, and neither does decoding on demand: a polyphase
## filterbank's 1,024 sample ring *is* its state, so there is no such thing as
## starting in the middle.
##
## So the whole track is decoded once, on a `Thread` this file starts in `open`,
## and `audio_stream` answers null until that finishes. Measured on
## `heb/mainmenu/intro.mpg`: **5.4 s of one background thread for 87.3 s of
## audio**, 15.7x real time, 15.0 MB of PCM. `preview/video.gd` polls once a tick
## and starts the player at whatever `the movieTime` has reached, so the picture
## never waits and a track that becomes ready late joins in sync rather than
## restarting. `audio_stream`'s own comment is the long form, including what that
## costs a clip played the instant it is opened.

const Ps := preload("res://director/director_mpeg1_ps.gd")
const Mpeg1Video := preload("res://director/director_mpeg1_video.gd")
const Mp2 := preload("res://director/director_mpeg1_audio.gd")

## Which playback path `preview/video.gd` drives this reader with. Pull, like the
## AVI reader: this file hands over one `Image` per call and owns no clock.
const BACKEND := "mpeg1"

## Extensions this reader is offered. Sniffing the first four bytes is what
## actually decides — `docs/DIGITAL_VIDEO.md` §1 makes the point that an extension
## is not evidence — but a list is what keeps the engine from reading 15 MB off
## the disc to find out that a `.wav` is a `.wav`.
const EXTENSIONS := ["mpg", "mpeg", "m1v", "mpv", "m2v", "vob", "ps"]

var error: String = ""
var path: String = ""

var width: int = 0
var height: int = 0
var fps: float = 0.0
var duration_ms: float = 0.0
var frame_count: int = 0
var pel_aspect: float = 1.0
var bit_rate: int = 0

## The sound track's own numbers, read out of the first MPEG audio frame header.
## These were the whole of the audio story when there was no decoder; they are
## still read the same way, because `the sampleRate of member` is answered before
## anything is decoded and must be the file's own number either way.
var audio_rate: int = 0
## Zero until a sound track is found, then 16 — which is what the Layer II
## decoder mixes at and is what `director_ogg.gd` answers for Vorbis, a format
## with no sample width of its own either. Left at zero for a file with no audio,
## because `the sampleSize of member` claiming 16 bits for a track that is not
## there is the kind of plausible invention `docs/DIGITAL_VIDEO.md` §3 forbids.
var audio_bits: int = 0
var audio_channels: int = 0
var audio_layer: int = 0
var audio_bitrate: int = 0

## What the frame walk found, for the harness and for the trace line. `audio_error`
## is set and the rest left at zero for a track this cannot decode — Layer III,
## free format — which is a different state from "there is no track" and reads
## differently in a report.
var audio_frames: int = 0
var audio_resyncs: int = 0
var audio_duration_ms: float = 0.0
var audio_error: String = ""

var _mp2: RefCounted = null
var _audio_thread: Thread = null
var _audio_mutex: Mutex = null
var _audio_pcm: PackedByteArray = PackedByteArray()
var _audio_done: bool = false
var _audio_us: int = 0
var _audio_wav: AudioStreamWAV = null

var _ps: RefCounted = null
var _video: RefCounted = null
var _open: bool = false

## Display bookkeeping. `_display_head` is how many display frames have been
## produced; `_ready_index` is the one the planes currently hold.
var _display_head: int = 0
var _ready_index: int = -1
var _ready_slot: String = ""
var _pending_ref: bool = false
var _ended: bool = false

## `{bit, display, closed}` per I picture passed, in increasing order.
var _restarts: Array[Dictionary] = []

var _cached_index: int = -1
var _cached_image: Image = null

var _decoded_pictures: int = 0
var _decode_us: int = 0
var _convert_us: int = 0


## Open an MPEG-1 file: demux it, read its sequence header, and settle its
## duration. No picture is decoded.
##
## False leaves `error` set and nothing held. **A duration of zero is a failure**,
## for the reason `director_ogg.gd:open` gives at its own head and
## `docs/DIGITAL_VIDEO.md` §3 argues at length: `preview/video.gd` treats an
## opened reader as a member whose media is ready, and a ready member with a
## duration of 0 is the state that turns Magic Hat's clean one-tick skip into an
## infinite `go(the frame)`.
func open(file_path: String) -> bool:
	close()
	path = file_path
	error = ""
	var ps := Ps.new()
	if not ps.open(file_path):
		error = str(ps.error)
		return false
	var video := Mpeg1Video.new()
	if not video.begin(ps.video_elementary()):
		error = "%s: %s" % [file_path.get_file(), str(video.error)]
		ps.close()
		return false
	_ps = ps
	_video = video
	width = video.width
	height = video.height
	fps = video.fps
	pel_aspect = video.pel_aspect
	bit_rate = video.bit_rate * 400
	_read_audio_header(ps.audio_elementary())

	var frame_ms := 1000.0 / maxf(fps, 0.001)
	var span := ps.pts_span_ms()
	if span <= 0.0:
		span = ps.scr_span_ms()
	if span > 0.0:
		duration_ms = span + frame_ms
	else:
		# A bare elementary stream carries no clock at all, so the only honest
		# answer is the picture count — and for a file with no container that is
		# a scan of the start codes rather than a decode, which is cheap.
		duration_ms = float(_count_pictures(ps.video_elementary())) * frame_ms
	if duration_ms <= 0.0:
		error = "%s: the stream states no duration (no PTS, no SCR, no pictures)" % file_path.get_file()
		close()
		return false
	frame_count = maxi(int(round(duration_ms * fps / 1000.0)), 1)
	_open = true
	_reset_playback()
	return true


func close() -> void:
	_join_audio()
	if _video != null:
		_video.release()
	if _ps != null:
		_ps.close()
	_ps = null
	_video = null
	_mp2 = null
	_audio_mutex = null
	_audio_pcm = PackedByteArray()
	_audio_wav = null
	_audio_done = false
	_open = false
	_cached_index = -1
	_cached_image = null
	_restarts.clear()
	_reset_playback()


func is_open() -> bool:
	return _open


func backend() -> String:
	return BACKEND


## Which display frame is on screen at `ms`. Floored and clamped, the same rule
## `director_avi.gd:frame_index_at` states: frame N covers `[N/fps, (N+1)/fps)`,
## and a decoder that wrapped on its own would make a non-looping video restart.
func frame_index_at(ms: float) -> int:
	if fps <= 0.0 or frame_count <= 0:
		return 0
	return clampi(int(floor(ms * fps / 1000.0)), 0, frame_count - 1)


## The picture at a display index, or null.
##
## Sequential access — which is what playback is — decodes exactly one coded
## picture per call. A backward step rewinds to the nearest recorded I picture; a
## forward jump decodes through what it skipped, because there is no other way to
## have the references a P or B picture needs.
func frame_at(index: int) -> Image:
	if not _open or index < 0:
		return null
	if index == _cached_index and _cached_image != null:
		return _cached_image
	var began := Time.get_ticks_usec()
	_advance_to(index)
	_decode_us += Time.get_ticks_usec() - began
	if _ready_index < 0:
		return null
	var planes: Array = []
	match _ready_slot:
		"cur":
			planes = _video.current_planes()
		"fwd":
			planes = _video.forward_planes()
		_:
			planes = _video.backward_planes()
	var convert_began := Time.get_ticks_usec()
	var image: Image = _video.to_image(planes)
	_convert_us += Time.get_ticks_usec() - convert_began
	# Cached under the index that was **asked for**, not under `_ready_index`. A
	# stream that ended early answers its last picture for every frame past the
	# end, which is what `preview/video.gd` draws while the playhead runs on to
	# the duration the system layer declared — the same "last picture stays on
	# the stage" that file already implements for a video that finishes.
	_cached_index = index
	_cached_image = image
	return image


## The whole sound track as one `AudioStreamWAV`, or **null while it is still
## being decoded**.
##
## ## Why the whole track, and why not here
##
## Layer II costs about a sixth of real time to decode in GDScript
## (`tools/mpeg1_audio.gd` measures it per clip), and `intro.mpg` is 87 seconds —
## so this is fourteen seconds of arithmetic, and there is nowhere on the main
## thread to put it. It cannot go in a property read: `docs/DIGITAL_VIDEO.md` §3
## is the argument, and Magic Hat's `Check avi` reads `the duration of member`
## before the first tick of playback. It cannot go in `the movieRate` being
## written either, which is where `preview/video.gd` starts a soundtrack: that is
## a Lingo statement, and freezing the movie inside one for fourteen seconds is
## the hang §3 exists to prevent.
##
## And it cannot be decoded a piece at a time as the playhead reaches it. **Audio
## cannot drop what it cannot afford**, which is the asymmetry with the picture:
## `frame_at` drops pictures to keep the clock and nobody minds, while a
## soundtrack that arrives late leaves a hole, and a filterbank restarted at a
## chunk boundary leaves a click — its 1,024 sample ring *is* its state, so
## decoding from the middle means having decoded what came before.
##
## So `open` starts a `Thread` and this answers null until it finishes. The
## picture never waits for the sound. `preview/video.gd` polls once a tick and
## starts the player at whatever `the movieTime` has reached, so a track that
## became ready ten seconds in joins ten seconds in and in sync, rather than
## restarting the clip or playing behind it.
##
## The cost of that decision, stated rather than implied: **for a clip that is
## played the instant it is opened, the first sixth of it is silent.** In Magic
## Hat it is not — `Check avi` opens the member and reads its duration well
## before `the movieRate` is written — but that is this title's shape and not a
## guarantee. The alternative was a frozen movie, and a clip whose sound starts
## late is worth more than one that does not start at all, which is the same
## trade `director_mpeg1_video.gd` made for the pictures.
##
## Memory: 16-bit stereo at the file's own rate, so 15.4 MB for `intro.mpg` and
## 20.7 MB for `heb/album/magic5.mpg`, the longest in the corpus. Held for as
## long as the reader is open, and released with it.
func audio_stream() -> AudioStreamWAV:
	if _audio_wav != null:
		return _audio_wav
	if not audio_ready():
		return null
	if _audio_pcm.is_empty():
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = audio_rate
	stream.stereo = audio_channels >= 2
	stream.data = _audio_pcm
	_audio_wav = stream
	return stream


## Has the background decode finished? False while it is still running, and false
## for a file with no decodable track at all.
func audio_ready() -> bool:
	if _audio_mutex == null:
		return false
	_audio_mutex.lock()
	var done := _audio_done
	_audio_mutex.unlock()
	if done and _audio_thread != null:
		# Join the moment it is known to be over, so the `Thread` is released here
		# rather than at `close` — `exit_leaks` counts what is still alive.
		_audio_thread.wait_to_finish()
		_audio_thread = null
	return done


## Microseconds the background decode took, and how many bytes of PCM it made.
## Read by `tools/mpeg1_audio.gd` and by nothing in the player.
func audio_decode_us() -> int:
	return _audio_us


func audio_pcm_bytes() -> int:
	return _audio_pcm.size()


## Microseconds spent inside `frame_at`, and the number of coded pictures that
## bought. Read by `tools/mpeg1_decode.gd` so that "how fast is it" is measured
## rather than asserted, and by nothing in the player.
func decode_cost_us() -> int:
	return _decode_us


func decoded_pictures() -> int:
	return _decoded_pictures


## Microseconds spent turning decoded planes into RGB images, counted apart from
## the decode because the two scale with different things — the decode with the
## bit rate and the conversion with the picture area — and a reader of the number
## needs to know which one a slow clip is paying.
func convert_cost_us() -> int:
	return _convert_us


func video_decoder() -> RefCounted:
	return _video


func demuxer() -> RefCounted:
	return _ps


# ============================================================ display ordering


func _reset_playback() -> void:
	_display_head = 0
	_ready_index = -1
	_ready_slot = ""
	_pending_ref = false
	_ended = false


## Decode until display frame `index` is the one the planes hold.
func _advance_to(index: int) -> void:
	if index < _display_head - 1:
		_restart_before(index)
	var guard := 0
	var ceiling := maxi(frame_count * 4 + 64, 1024)
	while _display_head <= index and not _ended:
		if not _step():
			break
		guard += 1
		if guard > ceiling:
			# A stream whose pictures never end — a length field that walks in a
			# circle, or a start-code search that stopped moving. Bounded rather
			# than trusted, because the alternative is a movie that never returns
			# from a property read.
			_ended = true
			break


## Decode one coded picture and emit whatever display frame that made available.
func _step() -> bool:
	var before: int = _video.bit_position()
	var kind: int = _video.decode_picture()
	if kind <= 0:
		_ended = true
		if _pending_ref:
			_pending_ref = false
			_emit("bwd")
			return true
		return false
	_decoded_pictures += 1
	if kind == Mpeg1Video.PICTURE_I:
		_note_restart(before)
	if kind == Mpeg1Video.PICTURE_B:
		_emit("cur")
		return true
	if _pending_ref:
		# The reference that was waiting has just been displaced into the forward
		# slot by the one now decoded, and that is the moment it becomes
		# displayable.
		_emit("fwd")
	_pending_ref = true
	return true


func _emit(slot: String) -> void:
	_ready_index = _display_head
	_ready_slot = slot
	_display_head += 1


## Record where an I picture was, so a backward seek has somewhere to land.
##
## Only the first 4,096 are kept. `heb/album/magic5.mpg` is 25 MB and has a few
## hundred; a hypothetical stream of one I picture per frame would otherwise grow
## a dictionary per frame for a seek nothing performs.
func _note_restart(bit: int) -> void:
	if _restarts.size() >= 4096:
		return
	if not _restarts.is_empty() and int(_restarts[-1]["bit"]) >= bit:
		return
	_restarts.append({
		"bit": bit, "display": _display_head, "closed": bool(_video.gop_closed()),
	})


## Rewind so that display frame `index` can be produced again.
##
## The restart point has to be one whose *next* emitted frame is at or before
## `index`, and its `display` field is exactly that number — the display index the
## decoder was about to produce when it reached that I picture. Restarting there
## discards the reference that was pending, so the frame at `display` itself
## cannot be reproduced from it and the search takes the last point strictly
## before `index`.
func _restart_before(index: int) -> void:
	var chosen := -1
	for i in _restarts.size():
		if int(_restarts[i]["display"]) <= index:
			chosen = i
		else:
			break
	# An **open** group's leading B pictures predict from the *previous* group's
	# last reference, which a restart at this I picture does not have — so step
	# back one recorded point when there is one. That costs a group of decoding
	# and buys pictures that are right instead of pictures that are two frames of
	# smear; `director_mpeg1_video.gd:open_gop_frames` counts the ones that still
	# land on the missing-reference path when there is no earlier point to take.
	if chosen >= 1 and not bool(_restarts[chosen]["closed"]):
		chosen -= 1
	if chosen < 0:
		_video.rewind()
		_reset_playback()
		return
	var point: Dictionary = _restarts[chosen]
	_video.seek_bit(int(point["bit"]))
	_reset_playback()
	_display_head = int(point["display"])


# ================================================================== the audio


## Walk the audio elementary stream's frames, and start decoding them.
##
## The walk is cheap and the decode is not, so they are separated: the walk is
## `director_mpeg1_audio.gd:scan`, which reads one header per frame — 3,343 of
## them for `intro.mpg`, thousandths of a second — and it is what answers
## `the sampleRate`, `the sampleSize` and `the channelCount of member` with the
## file's own numbers. It also validates, and its result is the strongest check
## either half of this decoder has: every frame's declared length must land on
## the next sync word.
##
## The decode is the 512-tap filterbank, and it goes on a `Thread`. See
## `audio_stream` for why it is here rather than at the first sample asked for.
##
## A track that walks but cannot be decoded — Layer III — still fills in the
## facts, because `scan` reads the header before it refuses. `audio_error` then
## says what it was, and `audio_stream` answers null for ever, which is the same
## thing `preview/video.gd` already does with a video it cannot decode.
func _read_audio_header(es: PackedByteArray) -> void:
	if es.is_empty():
		return
	var mp2 := Mp2.new()
	var walked := mp2.scan(es)
	if mp2.sample_rate <= 0:
		audio_error = str(mp2.error)
		return
	audio_layer = mp2.layer
	audio_rate = mp2.sample_rate
	audio_bits = 16
	audio_channels = mp2.channels
	audio_bitrate = mp2.bit_rate
	audio_frames = mp2.frame_count
	audio_resyncs = mp2.resyncs
	audio_duration_ms = mp2.duration_ms()
	if not walked:
		audio_error = str(mp2.error)
		return
	_mp2 = mp2
	_audio_mutex = Mutex.new()
	_audio_done = false
	_audio_thread = Thread.new()
	if _audio_thread.start(_decode_audio) != OK:
		# No thread available. Decode inline rather than losing the sound track:
		# a stall is worse than silence only while there is something else to do,
		# and on a machine that will not start a thread there is not.
		_audio_thread = null
		_decode_audio()


## The background decode, start to finish, in one call. Runs on `_audio_thread`.
##
## Nothing here touches anything the main thread reads except through the mutex,
## and it reads `_mp2` — which nothing else writes once the thread has started,
## and which `close` waits for before releasing.
func _decode_audio() -> void:
	var began := Time.get_ticks_usec()
	var pcm: PackedByteArray = _mp2.decode()
	var spent := Time.get_ticks_usec() - began
	_audio_mutex.lock()
	_audio_pcm = pcm
	_audio_us = spent
	_audio_done = true
	_audio_mutex.unlock()


## Wait for the background decode and release the thread.
##
## **A running `Thread` that is never joined is an error at exit and a leaked
## object in `exit_leaks`'s count**, so this is not optional tidying: a movie
## that changes while a clip is decoding drops the reader, and that is the
## ordinary case rather than the unusual one. `audio_ready` joins as soon as the
## decode is known to be over, and `close` joins whether it is or not, so the
## only way to leak one is to drop a reader without closing it —
## `preview/video.gd:release` closes every reader it holds, which is the one
## place that happens.
##
## There was a `NOTIFICATION_PREDELETE` arm here as a second net and it is gone:
## it fired with the script instance already detached and printed
## `Attempt to call function '_join_audio' in base 'null instance'` on every run,
## which is a standing error in a suite whose job is to say which runs are clean —
## `AGENTS.md`'s argument about `exit_leaks`, applied to the thing that was meant
## to prevent one.
func _join_audio() -> void:
	if _audio_thread != null:
		_audio_thread.wait_to_finish()
		_audio_thread = null


## Picture start codes in a bare elementary stream, for the one case with no
## clock to ask. Counted with the same `find(0)` walk the decoder uses.
func _count_pictures(es: PackedByteArray) -> int:
	var n := es.size()
	var at := 0
	var seen := 0
	while true:
		var z := es.find(0, at)
		if z < 0 or z + 3 >= n:
			break
		if es[z + 1] == 0 and es[z + 2] == 1 and es[z + 3] == 0x00:
			seen += 1
			at = z + 4
		else:
			at = z + 1
	return seen
