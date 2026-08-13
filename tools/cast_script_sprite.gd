extends SceneTree
## A **cast member script** knows which sprite it is running for.
##
##   godot --headless --script tools/cast_script_sprite.gd -- --root piposh-dream
##   godot --headless --script tools/cast_script_sprite.gd -- --root piposh-dream --play
##
## `--root` is needed and is not a default this tool should carry: `gate.sh` pins
## the corpus to `piposh2`, so the entry reads
## `cast_script_sprite:--root@piposh-dream`, the same shape `film_loop_restart`
## and `film_loop_nesting` already use for the same reason.
##
## `the currentSpriteNum` answered 0 in a cast script, and every read of it in the
## corpus is in one: **12 of 12**, across `hex1`/`hex2`/`hex3`, and 0 in a
## behaviour. `preview/event_chain.gd:element` carries the argument and the
## reference citation; this is the player-visible half of it.
##
## Piposh Dream's Hexxagon board is the site. The score fills 58 channels with
## member 56 (an empty hex) and the movie's own init swaps six of them to member 3
## (a piece) or 2 (an opponent). Member 3's **cast** script is the click handler:
##
##     on mouseUp me
##       ...
##       jumpFrom = the currentSpriteNum
##       lightUp1Hex(jumpFrom)
##
## and `lightUp1Hex` is a `case curHex of` over the channel numbers, so 0 matches
## no arm, nothing lights, and the board is unplayable -- reported as "nothing is
## clickable, the game is pretty much stuck". Members 103 and 105 are the lit
## tiles, and their cast scripts read the property twice more to complete the move.
##
## So the assertions are the move, not the property: a click on a piece lights
## tiles, and a click on a lit tile lands the piece somewhere else. A getter
## agreeing with a setter would pass with `lightUp1Hex` still matching nothing.
##
## ## Why it lands the playhead rather than watching the intro
##
## `hex1.dir` opens on ~200 frames of speech gated on `soundBusy`, which is real
## audio time and minutes of it. The init is the frame script at frame 202 (`1:99`
## `on enterFrame`), so this lands **inside the score before it** and lets the
## movie run into it -- the frame's own handler puppets the 58 channels, fills
## `field "Field"` and sets `turn`, exactly as it does when the intro hands over.
## Landing on the marker itself would skip it, which is the trap `AGENTS.md`
## names. `--play` walks the intro instead and asserts the same things; measured to
## produce the same board (pieces on channels 2, 36 and 58), which is what makes
## the shortcut legitimate rather than convenient.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## The container, and the frame to enter the score at: two before the init's own
## frame, so `1:99` runs on the way past rather than being jumped over.
const MOVIE := "hex1.dir"
const LAND := 200
const INIT_FRAME := 202
## Empty hex, the two lit states, and the piece whose cast script is the subject.
const EMPTY := 56
const STEP_HERE := 103
const JUMP_HERE := 105
const PIECE := 3
## The board is one span of channels; the movie's own `repeat with i = 2 to 62`.
const FIRST := 2
const LAST := 62
## The board's own frames: `start` runs the init, `startb` is the idle loop, and
## `1:61` at 221 sends the playhead round again. "The hop is over" is the playhead
## back inside this span, which is why the span is named rather than the animation.
const BOARD_FIRST := 202
const BOARD_LAST := 226


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", MOVIE, null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("no score loaded for %s" % MOVIE)
		quit(1)
		return

	var labels = preview.get("_labels")
	if Args.flag(args, "play"):
		await _play_to(preview, labels, "startb", Args.number(args, "ticks", 40000))
	else:
		preview.set("_index", LAND)
		# Real awaited frames, so the init's own `soundBusy` reads and the frame
		# clock behave as they do in play. A synthetic tick loop holds every guard.
		var seen_init := false
		for tick in 400:
			await process_frame
			if int(preview.call("current_frame")) >= INIT_FRAME:
				seen_init = true
			if seen_init and int(preview.call("current_frame")) > INIT_FRAME:
				break
	print("entered at frame %d, marker '%s'" % [
		int(preview.call("current_frame")),
		str(labels.marker_at(int(preview.call("current_frame")))) if labels != null else "",
	])

	# ------------------------------------------------------------- the board
	h.begin("the movie's own init dressed the board")
	var pieces := _channels_showing(preview, PIECE)
	h.check("the init put pieces on the board", pieces.size() > 0,
		"%d piece channel(s): %s" % [pieces.size(), str(pieces)])
	if pieces.is_empty():
		# Nothing below can mean anything without it, and a run that asserted the
		# rest against an undressed board would report the fix working on an empty
		# stage. Said out loud rather than skipped silently.
		print("the board was never dressed; the rest of this harness has no subject")
		h.complete("the movie's own init dressed the board")
		quit(h.finish("a cast script knows its sprite"))
		return
	h.complete("the movie's own init dressed the board")

	# ------------------------------------------- a click on a piece lights tiles
	h.begin("a click on a piece reaches its cast script *as that sprite*")
	var channel := int(pieces[0])
	var at: Vector2 = _centre(preview, channel)
	h.check("the piece is what the click descent picks",
		int(preview.call("_channel_at", at)) == channel,
		"channel_at %d, wanted %d" % [int(preview.call("_channel_at", at)), channel])
	await _click(preview, at)

	# The property, read back out of the interpreter's own globals rather than
	# inferred: the handler assigns `jumpFrom = the currentSpriteNum`, so this is
	# the value the movie saw and not a second opinion about it.
	var globals: Dictionary = preview.get("_interpreter").get("globals")
	var jump_from: Variant = globals.get("jumpFrom", globals.get("jumpfrom", null))
	h.check("the cast script read its own channel from `the currentSpriteNum`",
		jump_from != null and int(jump_from) == channel,
		"jumpFrom %s, wanted %d" % [str(jump_from), channel])

	var lit := _lit_channels(preview)
	h.check("tiles lit up around it", lit.size() > 0,
		"%d lit: %s" % [lit.size(), str(lit)])

	# The record, which is the other half of the report this closes: the tier that
	# answered, not the movie fallback. `_dispatch` runs the chain, so this is what
	# the click *record* says and it said `movie script none` about a handler that
	# ran (`bugs.md` 101's shape, reached the other way).
	var click: Dictionary = preview.get("_last_click")
	h.check("the click record names the script that answered, not `movie/none`",
		str(click.get("tier", "")) != "movie" and bool(click.get("handler", false)),
		"tier %s, script %s, handler %s" % [
			str(click.get("tier", "")), str(click.get("script", "")),
			str(click.get("handler", false))])
	h.complete("a click on a piece reaches its cast script *as that sprite*")

	if lit.is_empty():
		print("nothing lit, so there is no destination to click")
		quit(h.finish("a cast script knows its sprite"))
		return

	# --------------------------------------------------- and the move completes
	h.begin("a click on a lit tile completes the move")
	var destination := int(lit[0])
	var before := _board(preview)
	await _click(preview, _centre(preview, destination))
	# **The move is not finished when the handler returns.** `CastScript 103` and
	# `105` both call `play frame "animation2"` in the middle of themselves, which
	# suspends the handler (§6.1 step 18) and ends the chain until the played span
	# returns -- and everything that changes the board (`turnvalto`, `eatAroundd`,
	# `clearScreen`) is *after* that line. Asserting on the frames straight after
	# the release reads the board mid-hop and reports the destination still empty.
	#
	# Waited on the condition rather than on a frame budget, which is the fix
	# `play_suspends` got for the same shape (`bugs.md` 41): the movie's own signal
	# that the hop is over is the playhead coming back into the board's own frames.
	var settled := await _settle(preview, BOARD_FIRST, BOARD_LAST)
	h.check("the hop finished and the playhead came back to the board", settled,
		"frame %d" % int(preview.call("current_frame")))
	var after := _board(preview)
	h.check("the board changed", after != before,
		"origin ch%d, destination ch%d" % [channel, destination])
	# The piece moved rather than merely something repainting: Hexxagon's step
	# leaves the origin, its jump vacates it, and either way the destination stops
	# being an empty hex.
	h.check("the destination is no longer an empty hex",
		int(after.get(destination, EMPTY)) != EMPTY,
		"ch%d shows member %d" % [destination, int(after.get(destination, EMPTY))])
	h.check("no tile is left lit", _lit_channels(preview).is_empty(),
		"still lit: %s" % str(_lit_channels(preview)))
	h.complete("a click on a lit tile completes the move")

	quit(h.finish("a cast script knows its sprite"))


## Channel -> the member it is displaying, for the board's own span.
static func _board(preview) -> Dictionary:
	var out := {}
	for value in preview.call("frame_sprites"):
		var raw: Dictionary = value
		var channel := int(raw["channel"])
		if channel < FIRST or channel > LAST:
			continue
		var live: Dictionary = preview.call("_effective", raw)
		out[channel] = -1 if live.is_empty() else int(live["cast_id"])
	return out


static func _channels_showing(preview, member: int) -> Array:
	var out: Array = []
	var board := _board(preview)
	for channel in board:
		if int(board[channel]) == member:
			out.append(int(channel))
	out.sort()
	return out


static func _lit_channels(preview) -> Array:
	var out: Array = []
	var board := _board(preview)
	for channel in board:
		var member := int(board[channel])
		if member == STEP_HERE or member == JUMP_HERE:
			out.append(int(channel))
	out.sort()
	return out


## The middle of what a channel is drawing, so the click lands on the artwork
## rather than on the corner of a score rect the swapped member does not fill.
static func _centre(preview, channel: int) -> Vector2:
	for value in preview.call("frame_sprites"):
		var raw: Dictionary = value
		if int(raw["channel"]) != channel:
			continue
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty():
			return Vector2.ZERO
		var rect: Rect2 = preview.call("_sprite_rect", live)
		return rect.get_center()
	return Vector2.ZERO


## One click, on the movie's own clock. The release is a separate event because
## `mouseUp` is where every one of these handlers lives.
func _click(preview, at: Vector2) -> void:
	preview.call("route_press", at)
	for i in 4:
		await process_frame
	preview.call("route_release", at)
	for i in 40:
		await process_frame


## Wait for the playhead to come back inside `low..high` and for no Lingo to be
## parked, under a ceiling. Returns whether it did.
##
## Both conditions, because either alone is satisfied at the wrong moment: the
## playhead is still inside the board's frames for the first tick after the click,
## before `play` has moved it, and `_frozen_lingo` is empty then too.
func _settle(preview, low: int, high: int, ceiling := 1200) -> bool:
	var left := false
	for tick in ceiling:
		await process_frame
		var here := int(preview.call("current_frame"))
		var parked: int = (preview.get("_frozen_lingo") as Array).size()
		if here < low or here > high:
			left = true
			continue
		if left and parked == 0:
			return true
	return false


func _play_to(preview, labels, marker: String, ticks: int) -> void:
	var last := -1
	for tick in ticks:
		await process_frame
		var here := int(preview.call("current_frame"))
		if here == last:
			continue
		last = here
		if labels != null and str(labels.marker_at(here)).to_lower() == marker.to_lower():
			return
