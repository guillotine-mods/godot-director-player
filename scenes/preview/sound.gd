extends RefCounted
## Sound: the score's channels, `puppetSound`, the `sound` verbs, and cue points.
##
## The state deliberately does not live here. Volumes, streams and cue queues are
## `AudioDirector`'s, because the two hosts -- the stage and any open window --
## must agree about a channel and neither survives a `go to movie`. What lives
## here is the routing: which member becomes which stream, which verb reaches
## which call, and the once-a-tick pass that consumes cue points.
##
## That pass is one pass on purpose. `take_cues_passed` is destructive -- it
## reports each cue once and then forgets it -- so a wait poll and an event
## dispatch that each called it would race, and whichever ran first would eat the
## cue the other was looking for. A bug with no symptom except a wait that never
## releases.
##
## Most of this is unverified against Director. No cast in this game holds a
## sound member, no score frame writes a sound channel, and none of its 3,141
## sounds carries a cue marker, so `puppetSound`, the score channels and the cue
## path are all reference-shaped rather than observed. Everything the game
## actually plays comes through `play_file` from Lingo.

const Score := preload("res://director/director_score.gd")
const SoundMember := preload("res://director/director_sound.gd")


## Everything sound-driven that happens once a tick: cue points passed, and the
## tempo channel's wait-for-sound.
static func pump(host, audio: Node, clock) -> void:
	if audio == null:
		return
	var wait: Dictionary = clock.waiting_sound()
	var wait_channel := int(wait["channel"])
	var wait_cue := int(wait["cue"])

	for channel_value in audio.call("cue_channels"):
		var channel := int(channel_value)
		for cue_value in audio.call("take_cues_passed", channel):
			var cue: Dictionary = cue_value
			host._dispatch_cue_passed(channel, cue)
			if channel != wait_channel:
				continue
			# -1 is "the next cue, whichever it is"; a positive index is that cue
			# or any after it, since a tick can cross more than one. -2 is "the
			# end", which is not a cue at all and is handled below.
			if wait_cue == Score.CUE_NEXT or (wait_cue > 0 and int(cue["index"]) >= wait_cue):
				clock.sound_arrived()
				wait_channel = 0

	if wait_channel <= 0:
		return
	# "The end" is the *sound* ending, not the last cue passing: a sound with no
	# cue points at all still ends, and reading it as "all cues passed" would
	# release the wait instantly on every unmarked sound -- which is every sound
	# in this corpus. A cue wait releases on the sound ending too, or a frame
	# waiting on a cue that never comes would hold for ever.
	if not bool(audio.call("sound_busy", wait_channel)):
		clock.sound_arrived()


## A sound cast member onto a channel: what the score's channels and
## `puppetSound` both need, and the one path that turns a member into audio.
##
## Returns false when the member does not resolve or does not decode, which is a
## fact about the movie rather than an error to raise -- the same contract the
## bitmap path has. It is traced rather than silent, because a sound that does
## not play and says nothing is indistinguishable from a score that asked for
## none, and that ambiguity is what costs most sessions.
static func play_member(host, audio: Node, table, channel: int, cast_lib: int,
		cast_id: int) -> bool:
	if audio == null or table == null:
		return false
	var member: Dictionary = table.get_member(cast_lib, cast_id)
	if member.is_empty() or int(member.get("data_chunk_id", -1)) < 0:
		host._trace("f%d sound ch%d member %d:%d -> not found" % [
			host._index, channel, cast_lib, cast_id])
		return false
	var file = table.file_for(cast_lib)
	if file == null:
		return false
	var payload: PackedByteArray = file.read_chunk(int(member["data_chunk_id"]))
	var header := PackedByteArray()
	var header_id := int(member.get("sound_header_chunk_id", -1))
	# `sndH` is the header of the `sndH`/`sndS` pair and never the payload: when
	# the member's own data chunk *is* the header, there are no separate samples
	# to point it at and passing it as both would decode the header twice.
	if header_id >= 0 and header_id != int(member["data_chunk_id"]):
		header = file.read_chunk(header_id)
	var error: Array = []
	var stream := SoundMember.decode(payload, header, error)
	if stream == null:
		host._trace("f%d sound ch%d member %d:%d -> %s" % [
			host._index, channel, cast_lib, cast_id, "; ".join(error),
		])
		return false
	audio.call("play_stream", channel, "%d:%d" % [cast_lib, cast_id], stream,
		SoundMember.cue_points(payload))
	host._trace("f%d sound ch%d member %d:%d" % [
		host._index, channel, cast_lib, cast_id])
	return true


## Start and stop whatever the frame's sound channels changed.
##
## The corpus never exercises this: no score frame in its 86 containers writes a
## sound channel across 61,371 frames, so `changes()` returns nothing on every
## frame of every room. The harness that proves the rule is
## `tools/score_sound_check.gd`, which drives the state machine directly.
static func begin_score_sound(host, score_sound, frame: Dictionary) -> void:
	var changes: Dictionary = score_sound.changes(frame.get("sound_channels", []))
	for channel in changes["stop"]:
		host.lingo_stop_sound(int(channel))
	for entry_value in changes["start"]:
		var entry: Dictionary = entry_value
		host.play_sound_member(
			int(entry["channel"]), int(entry["cast_lib"]), int(entry["cast_id"]))


## `the <prop> of sound N`. `volume` is the one this game sets: 66 writes and 2
## reads across channels 1 to 4.
static func read_prop(audio: Node, channel: int, prop: String) -> Variant:
	if audio == null:
		return 0
	match prop:
		"volume":
			return int(audio.call("channel_volume", channel))
		"cuepointnames":
			return audio.call("cue_point_names", channel)
		"loop", "looping":
			return 0
	return 0
