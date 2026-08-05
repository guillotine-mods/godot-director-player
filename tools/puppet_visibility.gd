extends SceneTree
## `the visible of sprite 30` across a room transition, asserted.
##
##   godot --headless --script tools/puppet_visibility.gd
##
## The original keeps exactly one Piposh on screen with one mechanism. A room
## transition is a canned animation that draws him itself, in a low channel:
## DAY1's `edge2up` runs him up channel 3 for frames 406-421 while channel 30
## still carries a sprite. `whatodoeveryframe` hides sprite 30 when it hands the
## playhead to one of those, and `BehaviorScript 207` turns it back on at the end.
##
## Both halves have to hold. Only hiding strands an invisible protagonist; only
## restoring leaves the duplicate this measures.

var _fails := 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["ok  " if ok else "FAIL", name, ("  (%s)" % detail) if detail != "" else ""])


func _walk(runtime: RefCounted, nav: Dictionary) -> void:
	runtime.puppet.start_walk(nav, Vector2(320, 360), runtime.loader.stage_size, "edge2")
	for _i in 400:
		if not runtime.puppet.is_walking():
			break
		runtime.puppet.step()


func _initialize() -> void:
	var settings: Object = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true
	root.get_node("GameState").new_game()

	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	runtime.boot()
	runtime.goto_movie("DAY1", null, {})

	var channel: int = runtime.PUPPET_CHANNEL
	_check("puppet starts visible", not runtime.is_channel_hidden(channel))

	# A walk that ends in this room. `whatodoeveryframe` takes the
	# `item 1 of ifmovie = "0"` branch and leaves sprite 30 alone.
	_walk(runtime, {
		"kind": "walk",
		"walk_to": {"x": 400, "y": 360},
		"arrive_at": {"x": 400, "y": 360},
		"target_label": "edge2",
	})
	_check("an in-room walk leaves the puppet visible", not runtime.is_channel_hidden(channel))

	# A walk that hands over to a canned animation: `ifmovie = "1,edge2up"`.
	_walk(runtime, {
		"kind": "walk",
		"walk_to": {"x": 300, "y": 340},
		"arrive_at": {"x": 300, "y": 340},
		"target_label": "edge2",
		"after": {"kind": "label", "value": "edge2up"},
	})
	_check("handover to a transition hides the puppet", runtime.is_channel_hidden(channel))

	# ... and stays hidden for the animation's whole span, which is what the
	# duplicate was: the canned Piposh in channel 3 plus the standing puppet.
	var span_start: int = runtime.loader.resolve_label("edge2up", false)
	runtime.enter_frame(span_start)
	var shown_during := -1
	for _i in 60:
		if not runtime.is_channel_hidden(channel):
			shown_during = runtime.frame_index
			break
		if runtime.loader.get_frame(runtime.frame_index).get("frame_script") == 207:
			break
		runtime.game_step()
	_check("puppet stays hidden across the animation", shown_during < 0,
		"reappeared at frame %d" % (shown_during + 1) if shown_during >= 0 else "")

	# BehaviorScript 207 ends it, and it is the original script that runs: it goes
	# to `item 1 of nextroomdata`, which the room's own mouseUp handler wrote, and
	# then sets sprite 30 visible. Both come from the Lingo, not from
	# MovieContext's transition table.
	runtime.lingo.interpreter.globals["nextroomdata"] = "lighthouse,30,390"
	runtime.game_step()
	_check("BehaviorScript 207 navigates by nextroomdata",
		runtime.marker_name_for_frame(runtime.frame_index) == "lighthouse",
		runtime.marker_name_for_frame(runtime.frame_index))
	_check("BehaviorScript 207 restores the puppet", not runtime.is_channel_hidden(channel))

	# The same span with nothing for the script to go on. The native redirect
	# stands in, and standing in for 207 means its visibility line too.
	runtime.puppet.visible = false
	runtime.lingo.interpreter.globals["nextroomdata"] = "000"
	runtime.enter_frame(span_start)
	for _i in 60:
		if runtime.loader.get_frame(runtime.frame_index).get("frame_script") == 207:
			break
		runtime.game_step()
	runtime.game_step()
	_check("the fallback redirect restores the puppet too",
		not runtime.is_channel_hidden(channel))

	# The hide has to outlive the movie change, because the arrival half of a
	# cross-movie walk is a canned animation in the destination: coming back from
	# SEA1, DAY1 runs Piposh up channel 5 for frames 154-202 before its 207.
	# Nothing may clear it in between except a script that means to.
	runtime.puppet.visible = false
	runtime.goto_movie("DAY1", null, {"label": "shore2downdeck"})
	_check("the hide survives the movie change into the arrival animation",
		runtime.is_channel_hidden(channel))
	var shown_on_arrival := -1
	for _i in 80:
		if not runtime.is_channel_hidden(channel):
			shown_on_arrival = runtime.frame_index
			break
		if runtime.loader.get_frame(runtime.frame_index).get("frame_script") == 207:
			break
		runtime.game_step()
	_check("puppet stays hidden across the arrival animation", shown_on_arrival < 0,
		"reappeared at frame %d" % (shown_on_arrival + 1) if shown_on_arrival >= 0 else "")
	runtime.game_step()
	_check("the arrival animation's 207 restores the puppet",
		not runtime.is_channel_hidden(channel))

	runtime.puppet.visible = false
	runtime.puppet.reset()
	_check("reset restores the puppet", not runtime.is_channel_hidden(channel))

	# Piposh belongs to the movie whose channel 30 he is. A Movie In A Window has its
	# own channels and JOKE never mentions 30, so nothing of his may be drawn there —
	# and drawing him anyway resolved his member number against JOKE's own cast, where
	# 29 is the joke bitmap `joke33`.
	runtime.goto_movie("DAY1", null, {"label": "shore1go"})
	_check("the puppet is on stage in his own movie",
		not runtime.effective_sprite(channel).is_empty())
	runtime.goto_movie("JOKE", null, {})
	_check("the puppet is not on stage in a window movie",
		runtime.effective_sprite(channel).is_empty(),
		str(runtime.effective_sprite(channel).get("cast_id")))

	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
