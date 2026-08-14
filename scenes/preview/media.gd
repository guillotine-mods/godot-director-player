extends RefCounted
## Time-based media: the property surface Director gives a `#digitalVideo` and a
## `#sound` cast member, and the per-channel playback state a video sprite holds.
##
## ## Why one module for two member types
##
## Director does not have a "video property set" and a "sound property set". It
## has one set for media that *has a duration*, and the two member types share
## it: `the duration`, `the cuePointNames`, `the cuePointTimes`, `the loop`, `the
## preLoad`, `the mediaReady` and `the media` are asked of both, and `the
## sampleRate`, `the sampleSize` and `the channelCount` are asked of a sound
## member and of a digital video's audio track alike. Splitting them into two
## modules would put the same eleven answers in two places, and the first
## divergence would be a sound member answering a duration that a video member
## could not.
##
## `docs/ENGINE_TODO.md` records the block as "digital video (about 40 names)",
## which is the same set counted from the other end.
##
## ## What this port can and cannot know, per member type
##
## **A sound member is real here.** `director/director_sound.gd` decodes all
## three shapes Director ever wrote — an embedded AIFF or WAVE file, a Mac `snd `
## resource, and the D6+ `sndH`/`sndS` pair — so a sound member's duration,
## sample rate, sample size, channel count and cue points are computed from the
## member's own bytes rather than assumed.
##
## **This paragraph used to end "that decoder is unexercised by this corpus (no
## cast in any of the six titles holds a sound member)", and that was false.**
## The corpus holds **204** of them (`tools/member_type_census.gd`): 87 in
## `itamar-magichat`, 66 in `itamar-park`, 17 each in `piposh`, `piposh-en` and
## `piposh-ru`. Piposh 2 has none, which is where the sentence came from — a
## measurement of one title, written down as a fact about eight, and then
## repeated in AGENTS.md and `docs/ENGINE_TODO.md` in the same words.
##
## It cost exactly what an unexercised decoder costs. Handed its first real
## member the decoder failed twice: `director_cast.gd` preferred a zero-length
## `snd ` chunk sitting beside the real `sndH`/`sndS` pair, and the `sndH` decode
## had been written to a guess about the layout that the synthesised fixture was
## built to satisfy. `tools/sound_member_census.gd` is the instrument that hands
## the decoder the real ones, and it asserts against the corpus rather than
## against a count.
##
## **A digital video member has media when something can decode it, and answers
## that it has none when nothing can.** This paragraph twice said the second half
## alone — first "there is no QuickTime or AVI decoder in this port and Godot
## supplies none", which stopped being true when `director/director_avi.gd`
## landed, and it is worth recording that a header claiming *less* than the code
## does is as misleading as one claiming more: it sends the next reader to build
## what is already there.
##
## Two things can be behind a video member now:
##
##   * `director/director_avi.gd`, the MS-RLE reader, for the one AVI in the
##     tree; and
##   * an **Ogg Theora sidecar** under `user://`, for media in a format nothing
##     here decodes — the 22 MPEG-1 files behind Magic Hat's intro and album.
##     `director/director_sidecar.gd` says where one lives and
##     `preview/video.gd` says when it is used.
##
## When neither answers — no sidecar, not an AVI, or the file is not on the disc
## at all — nothing is worked around and nothing is hidden: `the mediaReady of
## member` answers **FALSE**, the duration is 0, there are no cue points and
## there are no tracks. That is exactly what Director answers for a digital video
## whose file is missing or whose codec is not installed, and it is the branch
## every defensive script in the language was written for. The alternative,
## answering the numbers a working video would have, is the shape this whole
## port's §19 exists to catch: a caller cannot tell a confident wrong answer from
## a right one.
##
## So a movie can still **drive** a video sprite whose media will not open — set
## its rate, its in and out points, its volume, and read every one of them back —
## and no picture and no sound will come out, because there is nothing to play.
## Director behaves the same way with an unloadable movie, down to
## `the movieTime` staying where it was put.
##
## ## The authoring flags are defaults, and that is said rather than implied
##
## `the controller`, `directToStage`, `video`, `sound`, `crop`, `center`,
## `scale`, `frameRate`, `pausedAtStart`, `loop` and `preLoad` are settings the
## author ticked in the member's dialog, and they live in the `#digitalVideo`
## member's specific block. **This port does not decode that block**: no member in
## any of the six titles is a digital video, so there is nothing to measure a
## layout against, and `reference/scummvm/` does not vendor the file that reads
## it. Every one of them therefore answers Director's own dialog default until a
## script writes it, and a script's write is stored and read back.
##
## That is a smaller claim than it looks and it is deliberately not dressed up:
## the read is right for any member left at the defaults, wrong for one the
## author changed, and there is no way to tell which from inside this port today.
## `docs/ENGINE_TODO.md` carries it as the open item it is. Inventing byte
## offsets for a block with no reference and no sample would be worse — it would
## answer with the same confidence and be wrong in a way nobody could see.

const SoundMember := preload("res://director/director_sound.gd")
const LingoValue := preload("res://lingo/lingo_value.gd")
## The moving half. This module answers *about* a video; that one opens it,
## advances it and draws it. See its header for the split and for the two rules
## `docs/DIGITAL_VIDEO.md` §3 lays down about answering a duration.
const Video := preload("res://scenes/preview/video.gd")
## Which cast members play video — cast type 10 and the type-15 Xtras whose
## symbol names a video player. One table, read by this module, by
## `preview/video.gd` and by `preview/stage_paint.gd`.
const VideoXtra := preload("res://director/director_video_xtra.gd")

## Director's tick, which is what `the duration of member` reports a **sound**
## member in. A digital video reports in its own `timeScale` units instead, which
## is why the two are converted at different points below rather than by one
## shared constant.
const TICKS_PER_SECOND := 60.0

## The member types this module answers for. Anything else falls straight
## through, so `the duration of member` goes on meaning a transition's duration
## for a transition member — `preview/members.gd` had that arm first and it is
## still the right answer there.
const SOUND_TYPE := "sound"
const VIDEO_TYPE := "digitalVideo"

## The member properties this module owns, as the one list every caller reads.
##
## `preview/members.gd` dispatches its read arm from this and
## `director_preview.gd` its write arm, so the two halves of the surface cannot
## come to know different names — which is the failure `set the textSize of
## member` had for as long as the read knew it and the write did not.
##
## `the media of member` is deliberately **not** here, and the omission is the
## point: Director hands back a duplicate of the member's media as an object a
## script can assign into another member, and this port has no member object and,
## for a digital video, no media behind one either. An arm that answered VOID
## would read as bound from every direction and be indistinguishable from a
## working one that happened to find nothing. Absent is the honest state and
## `docs/ENGINE_TODO.md` carries it with the mutable cast it needs.
const MEMBER_PROPS := [
	"controller", "directtostage", "video", "sound", "crop", "center", "scale",
	"framerate", "pausedatstart", "loop", "preload", "digitalvideotype",
	"timescale", "cuepointnames", "cuepointtimes", "channelcount", "samplerate",
	"samplesize", "filename", "mediafilename",
]

## The sprite properties this module owns. `volume` is here and not in
## `preview/channel.gd:FIELDS` for the reason the header gives: it is a property
## of the *playing movie in the channel*, not of the drawn sprite, and merging it
## into the sprite record would put it through the score's auto-puppet release
## rules, which Director does not apply to it.
const SPRITE_PROPS := [
	"movierate", "movietime", "starttime", "stoptime", "volume", "currenttime",
	"mostrecentcuepoint", "trackenabled", "settrackenabled", "tracktext",
	"tracknextkeytime", "tracknextsampletime", "trackpreviouskeytime",
	"trackprevioussampletime",
	# The **video Xtra's** three names, which are not Director's own and are here
	# for exactly that reason: an Xtra sprite's surface is whatever DLL is behind
	# it, and the two members in this tree carry Visible Light's OnStage Media —
	# `play()`, `stop()` and `getPlaybackEvent`. Answered from the same
	# per-channel playhead as the fourteen above, so a movie that starts a clip
	# with `play()` and then reads `the movieTime` of the same sprite is looking
	# at one position rather than two.
	#
	# `play` and `stop` are **methods**, not properties, and they arrive here as
	# property reads. `lingo/lingo_interpreter.gd:_call` resolves `sprite(N).x()`
	# by evaluating the callee, and a callee whose target is a `sprite_ref`
	# resolves to `get_sprite_prop(N, "x")` with the argument list dropped — which
	# is right for `member(x).name()` and is the shape every zero-argument sprite
	# method inherits. Both of these take no arguments in Director, so nothing is
	# lost; a sprite method that took one would need the interpreter to keep the
	# reference alive through the call, and that is a parser change rather than
	# something to approximate here.
	"getplaybackevent", "play", "stop",
]

## Director's dialog defaults for the authoring flags this port cannot decode.
## See the header: right for a member left as authored, wrong for one that was
## changed, and there is no third state available without the block.
const MEMBER_DEFAULTS := {
	# The QuickTime controller bar. Off, which is what a member dropped into a
	# score without opening its dialog carries.
	"controller": 0,
	# Draw over everything, bypassing the stage's compositing. A video that
	# cannot be decoded draws nothing either way.
	"directtostage": 0,
	# Play the video track, and play the sound track. Both on.
	"video": 1,
	"sound": 1,
	# Crop to the sprite rect rather than scaling to it, and centre within it.
	"crop": 0,
	"center": 0,
	# D7's scale, a point with float components. 1.0 is unscaled, and it is a
	# two-element list because that is how this port carries a point (§1.6).
	"scale": [1.0, 1.0],
	# 0 is Director's "play at the movie's own rate". A positive value is a
	# forced frames-per-second and a negative one is one of its two special
	# modes, neither of which can mean anything without frames to play.
	"framerate": 0,
	"pausedatstart": 0,
	"loop": 0,
	"preload": 0,
}

## Which key of the parsed member each authoring flag comes out of.
##
## The names differ on both sides and deliberately so: the left is Lingo's
## spelling, lowercased the way every property reaches this module, and the right
## is `director_cast.gd`'s, which follows the reference's field names
## (`castmember/digitalvideo.h`). One table rather than a `match` because the read
## above needs to ask "is this one of them" before it asks "which".
##
## **`scale` is not here.** It is D7's playback-size percentage pair and lives in
## no D5 specific block, so a D5 member has nothing to read and `MEMBER_DEFAULTS`
## answers 1.0 — which is the unscaled size and is right. `preload` and
## `framerate` are, and both come out of the same flag word as the tick boxes.
const VIDEO_FLAG_KEYS := {
	"controller": "controller",
	"directtostage": "direct_to_stage",
	"video": "video",
	"sound": "sound",
	"crop": "crop",
	"center": "center",
	"framerate": "dv_frame_rate",
	"pausedatstart": "paused_at_start",
	"loop": "looping",
	"preload": "preload",
}

## The member properties that name the *file* rather than describe it.
##
## `the fileName of member` is Director's spelling for a digital video and
## `the mediaFilename of member` is the media Xtras' spelling for the same idea;
## Magic Hat uses both — `logo.dir`'s `startMovie` writes `fileName` on a type-10
## member and `magichat.dir`'s album writes `mediaFilename` on a type-15 one.
## Both are bound here so that the two spellings cannot come to mean two
## different files.
##
## **The write now reaches a video Xtra too, and that sentence used to say the
## opposite.** It read: "a `mediaFilename` written to an Xtra is still reported
## and dropped, because there is no player behind that Xtra and storing the path
## would look bound from every direction". That was the right call while nothing
## could play an MPEG-1 file — a stored path with no player behind it is a
## binding that answers from every direction and does nothing. There is a player
## behind it now (`preview/video.gd`'s Theora backend, when a sidecar exists), so
## the write is stored, and the twenty clips `AlbumMenuObject.MenuMouseUp`
## repoints one member at are twenty different files rather than one name that
## went nowhere.
##
## What has *not* changed is what a stored path buys with no sidecar: nothing.
## `reader_for` resolves the name, finds no decodable media, and the member goes
## on answering exactly what it did. The write being real does not make the media
## real, and those are two separate questions.
const FILE_PROPS := ["filename", "mediafilename"]

## `the volume of sprite` before anything writes it.
##
## **255 and not 0.** Director's sprite volume is a 0-255 attenuation and a video
## dropped on the stage plays at full volume; seeding it at 0 would make the
## default state "muted", so a movie that never touches the property would read
## back a value it never chose and that Director never had. The reference's own
## `Sprite` field starts at 0, which is a statement about a field that its video
## path overwrites before use rather than about the property.
const DEFAULT_VOLUME := 255


## Does this module own the member's property surface?
##
## **Deliberately still "sound or cast type 10", with the video Xtras left out**,
## now that `preview/video.gd` can play one. The two are different questions and
## conflating them would bind names Director never gave an Xtra: `the mediaReady`,
## `the duration`, `the cuePointNames` and the authoring flags are the
## *`#digitalVideo` member's* surface, and a type-15 member's surface is whatever
## its DLL publishes — `docs/LINGO_SURFACE.md` gives it `interface` and
## `mediaBusy` instead, and neither is bound. `tools/video_fallback.gd` skips the
## Xtra members for exactly this reason and says so at the skip.
##
## What a video Xtra *does* get is `the mediaFilename` (see `FILE_PROPS`) and the
## three sprite names in `SPRITE_PROPS`, both of which are the Xtra's own and are
## reached through `is_playable` rather than through this.
static func is_media(member: Dictionary) -> bool:
	var kind := str(member.get("type_name", ""))
	return kind == SOUND_TYPE or kind == VIDEO_TYPE


static func is_video(member: Dictionary) -> bool:
	return str(member.get("type_name", "")) == VIDEO_TYPE


## Can something play this member — cast type 10, or a type-15 Xtra whose symbol
## is a video player's? One predicate, in `director/director_video_xtra.gd`, so
## that the answer here and the answer `preview/video.gd` opens a reader on
## cannot drift.
static func is_playable(member: Dictionary) -> bool:
	return VideoXtra.is_video(member)


# =============================================================== the member half


## `the <prop> of member M` for a sound or digital video member.
##
## Returns `null` for a member this module does not own or a property it does not
## carry, which is `preview/members.gd`'s own "no arm" answer — so a name that
## reaches neither is still reported by `director_preview.gd:_note_member_prop`
## rather than swallowed here.
static func read_member(host, where: Array, prop: String, table) -> Variant:
	var member: Dictionary = table.get_member(int(where[0]), int(where[1]))
	if not is_media(member):
		# A video Xtra gets `the mediaFilename` and nothing else — see `is_media`
		# for why the rest of this surface is not an Xtra's. Read through the same
		# override store the write below puts it in, so the two spellings and the
		# two member types share one answer.
		if is_playable(member) and FILE_PROPS.has(prop):
			return _linked_file(host, where, member)
		return null
	if not MEMBER_PROPS.has(prop):
		return null
	if FILE_PROPS.has(prop):
		# **Both spellings read the one key the write stores under**, which is what
		# the write's own comment claims and what this arm did not do. A
		# `mediaFilename` write landed on `"filename"` and a `mediaFilename` read
		# asked for `"mediafilename"`, missed, and fell through to the *authored*
		# link — so `member("x").mediaFilename = f` followed by
		# `put member("x").mediaFilename` answered the name in the cast record and
		# not `f`. The playback path was never affected (`video.gd:_wanted_file`
		# reads the stored key directly), which is why it survived: the only
		# visible symptom was a property that would not read back.
		return _linked_file(host, where, member)
	var written: Variant = _member_override(host, where, prop)
	if written != null:
		return written
	var facts: Dictionary = facts_of(host, where, table)
	match prop:
		# ------------------------------------------------- what the media itself says
		"cuepointnames":
			var names: Array = []
			for cue in (facts["cues"] as Array):
				names.append(str((cue as Dictionary).get("name", "")))
			return names
		"cuepointtimes":
			# Director reports a cue point's position in the same units as `the
			# duration` of the member it belongs to — ticks for a sound. The
			# decoder carries them in milliseconds, because that is what the audio
			# clock holds, so the conversion is here and the storage is not
			# duplicated.
			var times: Array = []
			for cue in (facts["cues"] as Array):
				times.append(_ms_to_ticks(float((cue as Dictionary).get("ms", 0.0))))
			return times
		"channelcount":
			return int(facts["channels"])
		"samplerate":
			return int(facts["sample_rate"])
		"samplesize":
			return int(facts["sample_size"])
		"timescale":
			# The units a digital video's own clock counts in. A sound member
			# answers Director's tick, which is the scale its duration is in.
			return int(facts["time_scale"])
		"digitalvideotype":
			# `#quickTime` or `#videoForWindows`, decided by reading the file's
			# own header rather than by trusting the member's own flag word: the
			# member is the author's claim and the file is the fact, and this
			# corpus has the two disagreeing — `logo`'s `vflags` sets neither
			# `0x8000` (QuickTime) nor `0x4000` (AVI), while the media behind it
			# is unambiguously RIFF AVI.
			#
			# `#other` when nothing opened, which is Director's third value and
			# the one it used for a video it could not identify. That is still
			# the answer for `logo.dir` #27 `prelogo`, whose file is not on the
			# disc.
			#
			# **Decided by the name the member carries, not by what is actually
			# being decoded**, now that the decoded stream can be an Ogg Theora
			# sidecar standing in for media this port has no decoder for.
			# `preview/video.gd:_declared_type` is the one place that rule lives.
			# Answering `#other` for an AVI that happens to be playing through a
			# sidecar, or inventing a fourth symbol for Ogg, would each tell a
			# movie something Director never said — and every script that reads
			# this was written against Director's three answers.
			if bool(facts["ready"]):
				return facts.get("dv_type", &"other")
			return &"other"
	if VIDEO_FLAG_KEYS.has(prop) and member.has(str(VIDEO_FLAG_KEYS[prop])):
		# The authoring flags, out of the member's own specific block.
		#
		# **This is the paragraph at the top of this file that stopped being
		# true.** The header said the block was not decoded and that every one of
		# these therefore answered Director's dialog default — right for a member
		# left as authored, wrong for one the author changed, with no way to tell
		# which from inside the port. `director_cast.gd`'s type-10 arm decodes it
		# now, against the two samples `logo.dir` supplies, so a member the author
		# changed reads back what the author set.
		#
		# The defaults below are still reached and still needed: a `#sound` member
		# has no such block at all, and neither has a digital video whose specific
		# block is shorter than the twelve bytes the D5 record needs.
		var carried: Variant = member[str(VIDEO_FLAG_KEYS[prop])]
		if typeof(carried) == TYPE_BOOL:
			return 1 if bool(carried) else 0
		return int(carried)
	return _member_default(prop)


## `set the <prop> of member M`. True when this module took the write.
##
## Only the authoring flags are writable, which is Director's own division: the
## media's own facts — its duration, its rate, its cue points — are what the file
## says and a script cannot argue with them.
static func write_member(host, where: Array, prop: String, value: Variant, table) -> bool:
	var member: Dictionary = table.get_member(int(where[0]), int(where[1]))
	# A video Xtra takes the file write and nothing else. `is_media` is the
	# `#digitalVideo` and `#sound` surface and stays that; `is_playable` is "can
	# something behind this member play", which is the only question
	# `the mediaFilename` asks.
	var takes := is_media(member) or (is_playable(member) and FILE_PROPS.has(prop))
	if not takes or not (MEMBER_DEFAULTS.has(prop) or FILE_PROPS.has(prop)):
		return false
	if host == null or host._host == null:
		return false
	var store: Dictionary = _member_store(host)
	var key := "%d:%d" % [int(where[0]), int(where[1])]
	var entry: Dictionary = store.get(key, {})
	if FILE_PROPS.has(prop):
		# Both spellings land on one key, so `member("x").mediaFilename = f`
		# followed by `put the fileName of member "x"` answers `f`. Two keys is how
		# a movie comes to set one and read the other -- the same argument
		# `the movieTime` / `the currentTime` gets on the sprite side.
		#
		# The reader is *not* reopened here. `preview/video.gd:reader_for` keys its
		# cache on the wanted filename and notices on the next read, which is what
		# lets Magic Hat's album repoint one member at twenty clips without this
		# module knowing a decoder exists.
		entry["filename"] = LingoValue.to_str(value)
		store[key] = entry
		return true
	if prop == "scale":
		entry[prop] = value if typeof(value) == TYPE_ARRAY else [
			float(LingoValue.to_num(value)), float(LingoValue.to_num(value))]
	elif prop == "framerate":
		entry[prop] = LingoValue.to_int(value)
	else:
		entry[prop] = 1 if LingoValue.to_int(value) != 0 else 0
	store[key] = entry
	return true


## What the media behind a member actually says, decoded once and kept.
##
## `{"ready", "duration", "time_scale", "cues", "channels", "sample_rate",
## "sample_size", "tracks"}`, in the member's own units.
##
## The cache is on the host, which is rebuilt per movie (`preview/boot.gd`), so a
## member re-read after a `go to movie` is decoded again rather than answered
## from the previous movie's cast. Keyed by library and slot, which is only safe
## because of that rebuild — the same pair names a different member in another
## movie's casts, and the two never meet.
static func facts_of(host, where: Array, table) -> Dictionary:
	var member: Dictionary = table.get_member(int(where[0]), int(where[1]))
	var key := "%d:%d" % [int(where[0]), int(where[1])]
	var cache: Dictionary = _facts_store(host)
	if cache.has(key):
		return cache[key]
	var facts := {
		# **FALSE for a digital video, and that is the whole of this module's
		# honesty.** There is no decoder, so the media never becomes ready, and a
		# movie that guards on it takes the branch that does not need the video.
		"ready": false,
		"duration": 0,
		"time_scale": int(TICKS_PER_SECOND),
		"cues": [],
		"channels": 0,
		"sample_rate": 0,
		"sample_size": 0,
		"tracks": 0,
	}
	if str(member.get("type_name", "")) == SOUND_TYPE:
		_decode_sound(member, table, int(where[0]), facts)
	elif str(member.get("type_name", "")) == VIDEO_TYPE:
		# **The `"ready": false` above is still the answer for every video whose
		# media will not open**, and that is the whole of `docs/DIGITAL_VIDEO.md`
		# §3's first rule. What changed is that one format can now open: MS-RLE
		# AVI, which is what both `#digitalVideo` members in eight corpora point
		# at. QuickTime and MPEG-1 still cannot, and `logo.dir` #27 `prelogo`
		# still cannot, because `prelogo.avi` is not on the disc.
		#
		# So this is not "the fallback was replaced". It is the same fallback with
		# a decoder in front of it, and the fallback is still what a member gets
		# when the decoder declines.
		Video.fill_facts(host, where, table, facts)
	# `_facts_store` answers a throwaway when there is no host to keep it on --
	# a harness holding the table alone -- and caching into that is harmless and
	# pointless. Written unconditionally rather than guarded, because the guard
	# would be a second statement of "is there a host" that could fall out of step
	# with the one in `_facts_store`.
	cache[key] = facts
	return facts


## A sound member's own numbers, out of the same decoder that plays it.
##
## Decoded rather than assumed: the sample rate, the width of a sample and the
## channel count are in the stream `director/director_sound.gd` builds, and the
## duration is its length. A member that will not decode leaves the defaults
## above, which say "not ready" — the same answer as a video, and for the same
## reason: the bytes could not be turned into media.
static func _decode_sound(member: Dictionary, table, cast_lib: int,
		facts: Dictionary) -> void:
	if int(member.get("data_chunk_id", -1)) < 0:
		return
	var file = table.file_for(cast_lib)
	if file == null:
		return
	var payload: PackedByteArray = file.read_chunk(int(member["data_chunk_id"]))
	var header := PackedByteArray()
	var header_id := int(member.get("sound_header_chunk_id", -1))
	if header_id >= 0 and header_id != int(member["data_chunk_id"]):
		header = file.read_chunk(header_id)
	var stream: AudioStreamWAV = SoundMember.decode(payload, header, [])
	if stream == null:
		return
	facts["ready"] = true
	facts["sample_rate"] = int(stream.mix_rate)
	facts["channels"] = 2 if stream.stereo else 1
	facts["sample_size"] = 16 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 8
	facts["duration"] = _ms_to_ticks(stream.get_length() * 1000.0)
	# One sound track, which is what a sound member is. `trackCount` asks the
	# same question of a video, where the answer would come from the file's own
	# track table.
	facts["tracks"] = 1
	for cue in SoundMember.cue_points(payload):
		(facts["cues"] as Array).append(cue)


static func _ms_to_ticks(ms: float) -> int:
	return int(round(ms * TICKS_PER_SECOND / 1000.0))


static func _member_default(prop: String) -> Variant:
	if MEMBER_DEFAULTS.has(prop):
		var value: Variant = MEMBER_DEFAULTS[prop]
		# The list default has to be copied, or the first script to write into
		# `the scale of member` would edit the constant every other member reads.
		return (value as Array).duplicate() if typeof(value) == TYPE_ARRAY else value
	return 0


## `the fileName` / `the mediaFilename` of a member that links to media: what a
## script last wrote, else the link the cast record itself carries.
##
## **Null for a sound member**, so `preview/members.gd` falls through to its own
## answer — the container the member lives in, which is right for an internal
## member and is what every member in the six shipped titles is.
##
## The authored link is `logo`'s `logo.avi`, out of item 3 of its info block,
## which is where Director stored the name of the file it imported from. One
## reader for the type-10 member and the type-15 Xtra, and one storage key for
## both spellings, so that the four combinations cannot answer four things.
static func _linked_file(host, where: Array, member: Dictionary) -> Variant:
	if not is_playable(member):
		return null
	var written: Variant = _member_override(host, where, FILE_PROPS[0])
	if written != null:
		return written
	return str(member.get("link_filename", ""))


static func _member_override(host, where: Array, prop: String) -> Variant:
	var store: Dictionary = _member_store(host)
	var entry: Dictionary = store.get("%d:%d" % [int(where[0]), int(where[1])], {})
	return entry.get(prop, null)


static func _member_store(host) -> Dictionary:
	if host == null or host._host == null:
		return {}
	return host._host.media_members


static func _facts_store(host) -> Dictionary:
	if host == null or host._host == null:
		return {}
	return host._host.media_facts


# =============================================================== the sprite half
#
# One playback state per channel, which is where Director keeps it: the member is
# the media and the sprite is the *performance* of it, so two sprites showing one
# video are two playheads. That is why `the movieTime` is a sprite property and
# `the duration` a member one, and it is the distinction a port collapses if it
# hangs the playhead off the member.


## `the <prop> of sprite N` for the digital-video property set, or `null` when
## this module does not own the name.
static func read_sprite(host, channel: int, prop: String) -> Variant:
	if not SPRITE_PROPS.has(prop):
		return null
	# The Xtra's three, before the playhead state is even touched. `play` and
	# `stop` are commands and must run for their effect rather than answer a
	# value, and `getPlaybackEvent` has to be able to answer VOID — which is the
	# one answer `channel_state`'s "create on first touch" would quietly turn into
	# a live channel with a rate of 0.
	match prop:
		"getplaybackevent":
			return Video.playback_event(host, channel)
		"play", "stop":
			# Created before the command runs, because a `play()` on a channel no
			# script has touched yet is the ordinary opening move: `init intro`'s
			# `enterFrame` calls `sprite(1).play()` before anything has read or
			# written a single playhead property on channel 1.
			channel_state(host, channel)
			Video.command(host, channel, prop)
			# VOID, because a Lingo command is a statement and not an expression.
			# A movie that wrote `if sprite(1).play() then` would be asking a
			# question Director has no answer to either.
			return null
	var state: Dictionary = channel_state(host, channel)
	match prop:
		"movierate":
			return state["rate"]
		"movietime", "currenttime":
			# `the currentTime of sprite` is D6's spelling of `the movieTime` and
			# the same number. Two names for one playhead: a port that stored them
			# separately would answer a position the other could not see.
			return int(state["time"])
		"starttime":
			return int(state["start"])
		"stoptime":
			return int(state["stop"])
		"volume":
			return int(state["volume"])
		"mostrecentcuepoint":
			# The index of the last cue point the playhead crossed, 1-based, 0 for
			# none. Nothing can cross one while no media plays.
			return int(state["cue"])
		"tracktext":
			# The text of the sprite's current text track at the playhead. There
			# are no tracks, so there is no text.
			return ""
		"trackenabled", "settrackenabled":
			return 0
		"tracknextkeytime", "tracknextsampletime", "trackpreviouskeytime", \
		"trackprevioussampletime":
			# Where the next and previous key frame and sample of the enabled
			# track sit, in the movie's time scale. With no track, the playhead's
			# own position is the only defensible answer: Director clamps these to
			# the ends of the track, and a track of zero length starts and stops
			# where the playhead is.
			return int(state["time"])
	return null


## `set the <prop> of sprite N`. True when this module took the write.
static func write_sprite(host, channel: int, prop: String, value: Variant) -> bool:
	if not SPRITE_PROPS.has(prop):
		return false
	var state: Dictionary = channel_state(host, channel)
	if state.is_empty():
		return false
	match prop:
		"movierate":
			# 0 is paused, 1 is forward at the movie's own rate, -1 is backwards,
			# and a fraction is a proportion of it — so this is a float and not an
			# integer.
			#
			# It is the **only** property that decides whether anything is playing,
			# which is why the soundtrack is started and stopped from here rather
			# than from the per-tick advance: hanging the transition off the tick
			# would put up to one engine frame of silence at the start of every
			# clip, and Director's `setMovieRate` starts the decoder inside the
			# write (`castmember/digitalvideo.cpp`).
			#
			# For a member with no media `rate_written` finds no reader and does
			# nothing, so this stays exactly what it was: a value that round-trips
			# and moves no playhead, which is Director with an unloadable video.
			state["rate"] = float(LingoValue.to_num(value))
			Video.rate_written(host, channel, float(state["rate"]))
		"movietime", "currenttime":
			state["time"] = _clamp_time(state, LingoValue.to_int(value))
		"starttime":
			state["start"] = maxi(LingoValue.to_int(value), 0)
			state["time"] = _clamp_time(state, int(state["time"]))
		"stoptime":
			state["stop"] = maxi(LingoValue.to_int(value), 0)
			state["time"] = _clamp_time(state, int(state["time"]))
		"volume":
			# Director's range, clamped rather than stored raw: a movie that
			# writes 300 reads back 255 there, and a port that hands the number
			# straight back would answer a volume no mixer could ever have used.
			state["volume"] = clampi(LingoValue.to_int(value), 0, 255)
		"mostrecentcuepoint", "tracktext", "tracknextkeytime", \
		"tracknextsampletime", "trackpreviouskeytime", "trackprevioussampletime":
			# Read-only in Director: they report where the media is, and a movie
			# moves the media with `the movieTime` instead. Refused here rather
			# than stored, for the reason `preview_lingo_host.gd:SPRITE_READ_ONLY`
			# gives about the derived rectangle — a stored value a script cannot
			# read back is worse than a refusal it can.
			return true
		"trackenabled", "settrackenabled":
			# `setTrackEnabled(sprite, track, state)` in Director is a command
			# rather than a property, and the property spelling addresses a track
			# that does not exist here. Accepted and dropped, which is what
			# enabling a track of a video with no tracks does.
			return true
		"getplaybackevent", "play", "stop":
			# The Xtra's surface: one report and two commands, none of them
			# assignable. Taken and dropped rather than refused, for the reason
			# `SPRITE_READ_ONLY` gives about the derived rectangle — falling
			# through would store the value in the channel's override table, where
			# the read above can never see it, and a value a script can set but
			# not read back is worse than one it cannot set.
			return true
	return true


## The playhead for a channel, created on first touch.
##
## Per channel and not per sprite record, because it has to outlive the score's
## per-frame list exactly as a puppet does: a video keeps playing while the
## score's own entry for that channel is rewritten frame by frame.
static func channel_state(host, channel: int) -> Dictionary:
	if host == null or host._host == null:
		return {}
	var store: Dictionary = host._host.media_channels
	if not store.has(channel):
		store[channel] = {
			"rate": 0.0, "time": 0, "start": 0, "stop": 0,
			"volume": DEFAULT_VOLUME, "cue": 0,
		}
	return store[channel]


## The playhead, held inside the in and out points a script has set.
##
## `stop` of 0 means "to the end", which is Director's own encoding and the
## reason this is not a plain `clampi`: a stop time nobody has written must not
## pin the playhead to the start.
static func _clamp_time(state: Dictionary, wanted: int) -> int:
	var low := int(state["start"])
	var high := int(state["stop"])
	if high > 0:
		return clampi(wanted, low, high)
	return maxi(wanted, low)


# ================================================================ the builtins
#
# `trackCount`, `trackType`, `trackStartTime`, `trackStopTime` and
# `isPastCuePoint`.
#
# **The first argument arrives as a bare integer whichever way it was written.**
# Director takes `trackCount(sprite 5)` and `trackCount(member "x")` and tells
# them apart by the reference's type; this port's parser evaluates a sprite
# reference to its channel number and a member reference to a packed
# `(library, slot)` integer (§1.6), so by the time an argument reaches a builtin
# both are integers and the spelling is gone. They are read as **sprite
# channels** here, which is the form every one of Director's own examples uses
# and the only one the sprite-side playhead can answer for. A member-side call
# would need the reference to survive the argument, which is a parser change and
# is recorded in `docs/ENGINE_TODO.md` rather than guessed at with a heuristic.


## `trackCount(sprite N)` — how many tracks the sprite's movie has.
static func track_count(host, channel: int, table) -> int:
	var where := _member_of_channel(host, channel)
	if where.is_empty() or table == null:
		return 0
	return int(facts_of(host, where, table)["tracks"])


## `trackType(sprite N, track)` — `#video`, `#sound`, `#text` or `#music`.
##
## VOID for a track that does not exist, which is Director's answer and not 0: a
## script switching on the symbol must not match an integer.
static func track_type(host, channel: int, track: int, table) -> Variant:
	if track < 1 or track > track_count(host, channel, table):
		return null
	var where := _member_of_channel(host, channel)
	# The only member type here that decodes to media is a sound, and its one
	# track is a sound track. A digital video's track table is in the file, which
	# nothing can open.
	if where.is_empty():
		return null
	return &"sound"


## `trackStartTime(sprite N, track)` / `trackStopTime(sprite N, track)`, in the
## movie's own time scale. A track that does not exist has no extent, and 0 is
## the answer for both ends of it.
static func track_time(host, channel: int, track: int, which: String, table) -> int:
	if track < 1 or track > track_count(host, channel, table):
		return 0
	if which == "start":
		return 0
	var where := _member_of_channel(host, channel)
	return 0 if where.is_empty() else int(facts_of(host, where, table)["duration"])


## `isPastCuePoint(sprite N, cuePoint)` — has the playhead crossed it?
##
## The second argument is an **index or a name**, which is Director's own pair of
## spellings: an integer counts cue points from 1, and a string matches one by
## name and answers TRUE once *any* cue point with that name has been passed.
##
## FALSE whenever the media is not playing, which here is always. That is not the
## stub answer it resembles: it is computed from the playhead against the decoded
## cue table, so a sound member with real markers answers correctly the moment
## something advances the playhead.
static func is_past_cue_point(host, channel: int, cue: Variant, table) -> int:
	var where := _member_of_channel(host, channel)
	if where.is_empty() or table == null:
		return 0
	var cues: Array = facts_of(host, where, table)["cues"]
	var passed := int(channel_state(host, channel)["cue"])
	if typeof(cue) == TYPE_INT or typeof(cue) == TYPE_FLOAT:
		var index := int(cue)
		return 1 if index >= 1 and index <= passed else 0
	var wanted := LingoValue.to_str(cue).to_lower()
	for i in cues.size():
		if i + 1 > passed:
			break
		if str((cues[i] as Dictionary).get("name", "")).to_lower() == wanted:
			return 1
	return 0


## `[library, slot]` for whatever a channel is showing, or `[]`.
##
## Through the node's own effective-sprite read rather than the score record, for
## the reason `preview/event_chain.gd:member_on` gives at its own: a `puppetSprite`
## write that swapped the member is what the channel is actually showing, and a
## video sprite is exactly the kind a script swaps.
static func _member_of_channel(host, channel: int) -> Array:
	if host == null or channel <= 0:
		return []
	var lib: int = LingoValue.to_int(host.lingo_sprite_prop(channel, "castlibnum"))
	var slot: int = LingoValue.to_int(host.lingo_sprite_prop(channel, "membernum"))
	if slot <= 0:
		return []
	return [maxi(lib, 1), slot]
