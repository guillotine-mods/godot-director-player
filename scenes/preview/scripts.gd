extends RefCounted
## Finding the script that should answer a message, and sending it.
##
## The rule this module exists to hold in one place is that **a member number is
## per cast, so the library is part of the key and not a hint.** Searching every
## cast for any script with a given number finds something almost always -- 758
## of 758 frame-script intervals "resolved" that way -- and what it finds is a
## stranger, some sprite behaviour in another cast that happens to share the
## number. The symptom is not an error but silence, because the script that comes
## back has no `exitFrame` in it.
##
## The same mistake in the eligibility test made DAY1's beach backdrop answer
## clicks across its whole 640x400 rect, so clicking the sea walked the character
## into it. One bug class, two symptoms, and this is where it is prevented.


## The script at a member number, in a named library. `{}` when there is none.
static func in_lib(interpreter, lib_keys: Dictionary, cast_lib: int,
		member: int) -> Dictionary:
	if interpreter == null or member <= 0:
		return {}
	var lib := 1 if cast_lib <= 0 or cast_lib == 0xFFFF else cast_lib
	if lib_keys.has(lib):
		return interpreter.find_script_by_member(str(lib_keys[lib]), member)
	return {}


## Without a library to go on -- a member script reached through a sprite -- the
## movie's own cast wins over a linked one, as Director resolves it.
static func for_member(interpreter, script_casts: Array, member: int) -> Dictionary:
	if interpreter == null or member <= 0:
		return {}
	for key in script_casts:
		var script: Dictionary = interpreter.find_script_by_member(str(key), member)
		if not script.is_empty():
			return script
	return {}


## The behaviour attached to a sprite channel on this frame, from the score's own
## interval entries -- the only place the attachment exists.
static func for_sprite(host, score, channel: int, frame_index: int) -> Dictionary:
	if score == null:
		return {}
	for interval in score.intervals():
		if str(interval["kind"]) != "sprite" or int(interval["channel"]) != channel:
			continue
		if frame_index < int(interval["start"]) or frame_index > int(interval["end"]):
			continue
		return host._script_in_lib(
			int(interval["script_cast_lib"]), int(interval["script_member"])
		)
	return {}


## Director's message hierarchy, as much of it as this preview has: the script
## that owns the message first, then any movie script.
##
## The movie-script fallback is not a nicety. `prepareMovie`, `startMovie` and
## most of a room's sound live in movie scripts, not on the frame, so a dispatch
## that only ever asks the frame script runs nothing at all on a frame that has
## none -- which is every frame of some movies.
static func dispatch(host, interpreter, handler: String, script: Dictionary) -> void:
	if interpreter == null:
		return
	host._tally(host._sent, handler)
	# `call_handler` already resolves Director's order -- the owning script, then
	# any movie script -- and lowercases the name on the way in. Guarding it with
	# `_script_has_handler` was worse than redundant: that helper compares the
	# handler's lowercased name against the key *as given*, so "exitFrame" never
	# matched "exitframe" and every dispatch was refused before it ran.
	#
	# Whether it ran, not what it returned: a void handler answers null, so a
	# `!= null` test scores every successful dispatch as a miss.
	var key := handler.to_lower()
	var owns: bool = interpreter.call("_script_has_handler", script, key)
	if owns or interpreter.has_handler(key):
		host._tally(host._ran, handler)
	interpreter.call_handler(handler, [], script)



## The frame script covering a frame, or `{}`.
##
## The main channel's script slot is only one of the two places this lives, and
## the smaller one. Most frame scripts are interval entries -- a span of frames
## with a script attached, the same mechanism that attaches behaviours to sprite
## channels, distinguished by naming sprite 0. Reading only the main channel
## found a script on almost no frame, so `exitFrame` dispatched every tick and
## ran nothing: rooms did not hold and hotspots did not answer.
##
## **The narrowest interval covering the frame wins.** A movie carries both
## room-specific frame scripts and one that spans everything -- DAY1's
## `what to do everyframe` covers the whole movie -- so taking the first match
## hands every frame to the movie-wide script and the room-specific one never
## runs. In DAY1 that is `go to mrkr 0`, the `go(marker(0))` that holds the room:
## the playhead simply ran on, with no error anywhere.
static func for_frame(host, score, index: int) -> Dictionary:
	if score == null:
		return {}
	var frame: Dictionary = score.frame(index)
	var member = frame.get("frame_script")
	if member != null:
		# Resolved in the library the score names, not by number alone: the
		# talking loop's last-frame script lives in the shared cast, and a
		# number-only search hands the frame to whichever cast answers first.
		var direct: Dictionary = host._script_in_lib(
			int(frame.get("frame_script_lib", 1)), int(member))
		if direct.is_empty():
			direct = host._script_for_member(int(member))
		if not direct.is_empty():
			return direct
	var best: Dictionary = {}
	var narrowest := 0x7FFFFFFF
	for interval in score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		var from := int(interval["start"])
		var to := int(interval["end"])
		if index < from or index > to:
			continue
		var span := to - from
		if span >= narrowest:
			continue
		var script: Dictionary = host._script_in_lib(
			int(interval["script_cast_lib"]), int(interval["script_member"])
		)
		if not script.is_empty():
			best = script
			narrowest = span
	return best
