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
## **The sentence this replaces measured Piposh 2 and spoke about Director.** It
## said "no cast in this game holds a sound member", which is true of Piposh 2 and
## of nothing else: the corpus holds **204** across five titles
## (`tools/member_type_census.gd`), 156 of them addressable, and
## `play_member` below is exercised against all of them by
## `tools/sound_member_census.gd`. What is still unobserved is narrower and worth
## naming exactly: **no score frame in any root writes a sound channel**, so
## `begin_score_sound` is driven only by `tools/score_sound_check.gd`; and **no
## sound in any root carries a cue point** — 0 `cupt` chunks in 651 containers,
## and all 336 AIFF markers in the corpus sit past the end of their own file — so
## the cue path is reference-shaped rather than observed.

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
	if member.is_empty():
		host._trace("f%d sound ch%d member %d:%d -> not found" % [
			host._index, channel, cast_lib, cast_id])
		return false
	var id := "%d:%d" % [cast_lib, cast_id]
	# **The linked case is tried before the payload case, not after it**, and the
	# order is the reference's. `castmember/sound.cpp:load()` reaches the external
	# file from a payload that is absent *or* zero bytes, so a member with a
	# zero-length `snd ` beside a link is a linked member and not a broken one --
	# and `director_cast.gd` has already made that call, in `sound_linked`, using
	# the chunk's size rather than its presence. Asking here would be a second
	# reading of the same bytes that could disagree with the first.
	if bool(member.get("sound_linked", false)):
		var link := str(member.get("link_filename", ""))
		if bool(audio.call("play_linked_member", channel, id, link)):
			host._trace("f%d sound ch%d member %s -> linked %s" % [
				host._index, channel, id, link])
			return true
		host._trace("f%d sound ch%d member %s -> linked %s not found" % [
			host._index, channel, id, link])
		return false
	if int(member.get("data_chunk_id", -1)) < 0:
		host._trace("f%d sound ch%d member %s -> no payload and no link" % [
			host._index, channel, id])
		return false
	var file = table.file_for(cast_lib)
	if file == null:
		# Not "the member has no audio": the *library* could not be opened. Traced
		# apart from the two misses above because the fix is in a different file --
		# see `bugs.md` on `DirectorCastTable.file_for` answering null for a cast
		# library embedded in the movie's own container, which is 48 of Magic Hat's
		# 87 sound members and 290 of Piposh 2's bitmaps.
		host._trace("f%d sound ch%d member %s -> library %d has no container" % [
			host._index, channel, id, cast_lib])
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
		host._trace("f%d sound ch%d member %s -> %s" % [
			host._index, channel, id, "; ".join(error),
		])
		return false
	# The `cupt` child, which is where Director 6 puts cue points -- the inline
	# AIFF markers `cue_points` used to be the whole of are the *other* source and
	# the rarer one. The rate is what turns a cue's millisecond position into the
	# sample frame `take_cues_passed` compares against the player's clock, so it
	# has to come from the decoded stream rather than from the header.
	var cue_chunk := PackedByteArray()
	var cue_id := int(member.get("sound_cue_chunk_id", -1))
	if cue_id >= 0:
		cue_chunk = file.read_chunk(cue_id)
	audio.call("play_stream", channel, id, stream,
		SoundMember.cue_points(payload, cue_chunk, int(stream.mix_rate)))
	host._trace("f%d sound ch%d member %s" % [host._index, channel, id])
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
