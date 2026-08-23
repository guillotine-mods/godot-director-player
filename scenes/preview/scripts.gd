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
	# A fresh step budget per event. `MAX_STEPS` exists to stop a runaway loop
	# inside *one* dispatch, but `reset_steps()` had no callers anywhere, so the
	# count accumulated for the life of the session against a fixed ceiling --
	# meaning a long enough session would start aborting every handler with
	# "step budget exhausted", and the failure would look like the movie breaking
	# rather than like a counter. Resetting here can only ever give a handler more
	# budget, never less, so it cannot mask a real runaway.
	interpreter.reset_steps()
	var key := handler.to_lower()
	var owns: bool = interpreter.call("_script_has_handler", script, key)
	if owns or interpreter.has_handler(key):
		host._tally(host._ran, handler)
	# **One `Lingo::execute` scope per dispatch**, which is what `bugs.md` 123's
	# second half is about. `Lingo::processEvent` calls `execute()` around each
	# handler it delivers (`reference/scummvm/lingo/lingo-events.cpp:809`, `831`),
	# and the flag an abort sets is cleared by that call's epilogue -- so a
	# dispatch is where an abort stops.
	#
	# This is also the **nested** case, and it is why the line has to be here
	# rather than only at the outermost entry point: `sendSprite` and
	# `sendAllSprites` re-enter through `preview_lingo_host.gd` -> `_dispatch` ->
	# here, once per channel, exactly as the reference re-enters through
	# `callBehaviorHandler` once per instance (`lingo-builtins.cpp:3470-3547`). An
	# abort inside a `sendAllSprites` recipient must stop that recipient and let
	# the broadcast carry on to the next channel and then let its *caller* carry
	# on, and without a scope here it would unwind all of them.
	#
	# `reset_steps` above already clears the flag on the way in; this clears it on
	# the way out, which is the half the reference's epilogue performs and the half
	# that decides how far an abort travels.
	var scope: int = interpreter.begin_execute()
	interpreter.call_handler(
		handler, [], script, addressed_channel(host, interpreter, script))
	interpreter.end_execute(scope)


## Which sprite this dispatch is for -- `the currentSpriteNum`, 0 for the frame.
##
## **`bugs.md` 93, and the reason it is derived here rather than passed in.**
## `call_handler` reads its channel as "which behaviour instance is this message
## for", and every call through `dispatch` used to take the default 0 -- so
## `on exitFrame me` in a behaviour-channel script bound `me` to VOID while
## `on beginSprite me` in the *same script* got a real object, and a `property`
## written in one was invisible in the other. Two callers reach this function
## with two different needs and neither can be served by a constant:
##
##   the frame events   `prepareFrame`, `enterFrame`, `exitFrame`, `idle`,
##                      `timeout` -- Director's frame tier, channel 0. The
##                      recipient is the behaviour channel's instance when the
##                      score has one there and nothing at all when it does not,
##                      which is a distinction `call_handler` makes for itself:
##                      `live_behaviour` looks the channel-0 instance up and
##                      never creates one, so a plain frame script and a movie
##                      script still come away with no `me`.
##   `sendSprite` /     the caller *named* the recipient, and
##   `sendAllSprites`   `preview_lingo_host.gd` has already put that channel in
##                      `the currentSpriteNum` before reaching here (§7.1, and
##                      the reference brackets each send with the same save and
##                      restore). So the number this needs is already on the host
##                      and reading it is the join; passing it down through
##                      `_dispatch` would mean a second, parallel answer to a
##                      question one field already answers.
##
## Reading `the currentSpriteNum` is not a shortcut for the score: it is what
## `spriteNum` itself is answered from in the reference, where `ScriptContext::
## getProp` returns `_currentSpriteNum` for a behaviour that never declared the
## property (`reference/scummvm/lingo-object.cpp:719-721`) and `processEvent`
## sets that field from the queued event's channel (`lingo-events.cpp:806`).
##
## **A sprite channel is reported only when that sprite is already running this
## script**, and that guard is not belt-and-braces -- it is what keeps the field
## honest. `the currentSpriteNum` is ambient: `frame_loop.gd:send_sprite_message`
## and `event_chain.gd:run` both set it around a behaviour, so a handler reached
## from inside one of those that causes a *frame* event to be dispatched would
## otherwise report that behaviour's channel for the frame script. Asking for the
## live instance first makes the mismatch answer 0 instead, and -- because
## `call_handler` will happily *make* an instance for a channel above 0, the way
## the rollover messages need it to -- it is also what stops that case leaving a
## `<channel>:<frame script>` object behind on every tick.
static func addressed_channel(host, interpreter, script: Dictionary) -> int:
	if host == null or interpreter == null or script.is_empty():
		return 0
	var lingo_host: Variant = host.get("_host")
	if lingo_host == null:
		return 0
	var channel := int(lingo_host.get("current_sprite_num"))
	if channel <= 0:
		return 0
	return channel if interpreter.live_behaviour(script, channel) != null else 0



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
