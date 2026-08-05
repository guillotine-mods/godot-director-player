extends SceneTree
## An uncovered shell or bottle stays uncovered until it is taken.
##
##   godot --headless --script tools/collectables.gd
##
## `searchfunk` (MASTER MovieScript 78) walks Piposh to a piece of scenery on the
## first click and reveals what is hidden there on the second, with
## `sprite(mydoing).visible = 1`. The room's own entry script `b4 bk's` blanks those
## same channels — `set the visible of sprite 15 to 0`, and 17 and 33 — so anything
## that re-runs the entry scripts while the player is standing in the room erases the
## reveal. It showed for exactly one frame and vanished.
##
## Taking it is `sprite(the clickOn).visible = 0` plus the room written into
## `shellfield` (MASTER CastScript 77) or `jokefield` (CastScript 69), so this
## asserts the reveal survives, the click hides it, and the record is written.

var _fails := 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["ok  " if ok else "FAIL", name, ("  (%s)" % detail) if detail != "" else ""])


func _fresh(movie: String, room: String) -> RefCounted:
	var r: RefCounted = load("res://director/director_runtime.gd").new()
	r.boot()
	root.get_node("GameState").new_game()
	r.goto_movie(movie, null, {"label": room})
	return r


func _sprite_on(runtime: RefCounted, channel: int) -> Dictionary:
	for s in runtime.clickable_sprites(runtime.loader.get_frame(runtime.frame_index)):
		if int((s as Dictionary).get("channel", 0)) == channel:
			return s
	return {}


func _case(movie: String, room: String, channel: int, field: String) -> void:
	var label := "%s @%s ch%d" % [movie, room, channel]

	# Find the scenery that hides it. Each candidate gets a fresh runtime, because a
	# wrong guess can walk Piposh somewhere else or leave the movie entirely.
	var scan: RefCounted = _fresh(movie, room)
	_check("%s: starts hidden" % label, scan.is_channel_hidden(channel))
	var candidates: Array = []
	for s in scan.clickable_sprites(scan.loader.get_frame(scan.frame_index)):
		var ch := int((s as Dictionary).get("channel", 0))
		if ch < 92 and ch != channel:
			candidates.append(ch)

	var runtime: RefCounted = null
	var searched := -1
	for ch in candidates:
		var attempt: RefCounted = _fresh(movie, room)
		var hotspot: Dictionary = _sprite_on(attempt, ch)
		if hotspot.is_empty():
			continue
		attempt._activate_sprite(hotspot, attempt.sprite_stage_rect(hotspot).get_center())
		for _i in 200:
			attempt.tick(0.1)
		if attempt.loader.movie_name.to_lower() != movie.to_lower():
			continue
		attempt._activate_sprite(hotspot, attempt.sprite_stage_rect(hotspot).get_center())
		if not attempt.is_channel_hidden(channel):
			runtime = attempt
			searched = ch
			break
	_check("%s: searching the scenery uncovers it" % label, runtime != null,
		"tried %s" % str(candidates))
	if runtime == null:
		return

	# The regression: it used to be blanked again by the next frame the room ran.
	var lost := -1
	for i in 300:
		runtime.tick(0.1)
		if runtime.is_channel_hidden(channel):
			lost = i
			break
	_check("%s: stays uncovered while the room runs" % label, lost < 0,
		("re-hidden after %d ticks at frame %d" % [lost, runtime.frame_index]) if lost >= 0 else "")
	if lost >= 0:
		return

	# And taking it hides it and records the room.
	var before := str(runtime.lingo.host.get_field(field, "master"))
	var target: Dictionary = _sprite_on(runtime, channel)
	_check("%s: uncovered means clickable" % label, not target.is_empty(),
		"scenery was ch%d" % searched)
	if target.is_empty():
		return
	var room_movie: String = runtime.loader.movie_name
	runtime._activate_sprite(target, runtime.sprite_stage_rect(target).get_center())
	var after := str(runtime.lingo.host.get_field(field, "master"))
	_check("%s: taking it records the room in %s" % [label, field], after != before,
		"%s -> %s" % [before.substr(0, 18), after.substr(0, 18)])

	if runtime.loader.movie_name == room_movie:
		_check("%s: taking it hides it" % label, runtime.is_channel_hidden(channel))
		return

	# A bottle opens joke.dxr, so the hide landed on a movie the port has since swapped
	# out — Director floats the joke over a DAY1 that never unloads, and a single-stage
	# port cannot. What has to hold is what the player sees on the way back, which is
	# the room's own entry blanking. That needs the interpreter to know it is back in
	# this movie: `go_back` did not tell it, so the entry scripts resolved against JOKE
	# and did not run at all.
	_check("%s: taking it opens the joke" % label, runtime.loader.movie_name == "JOKE",
		runtime.loader.movie_name)
	_check("%s: the joke picture is on stage, at its own size" % label,
		_joke_picture_ok(runtime))
	runtime.lingo.host.call_builtin("forget", ["joke"])
	_check("%s: closing it returns to the room" % label,
		runtime.loader.movie_name == room_movie, runtime.loader.movie_name)
	_check("%s: and it is still gone" % label, runtime.is_channel_hidden(channel))
	_check("%s: the interpreter came back with it" % label,
		runtime.lingo.script_for_member(1, 83).has("handlers"),
		"frame scripts resolve in %s" % runtime.loader.movie_name)


func _joke_picture_ok(runtime: RefCounted) -> bool:
	## `set the memberNum of sprite 3 to the number of member("joke" & day & slot)`.
	## JOKE's score parks channel 3 on `jokepfff`, a 1x1 placeholder at (318, 199), so
	## drawing the score's rect shows nothing. Director resizes the sprite to the new
	## member and re-anchors it on that member's registration point.
	var sprite: Dictionary = runtime.effective_sprite(3)
	if sprite.is_empty():
		print("      channel 3 is empty")
		return false
	var member: Dictionary = runtime.loader.get_member(
		int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0)))
	var width := float(member.get("width", 0))
	var height := float(member.get("height", 0))
	var ok: bool = (
		width > 1.0
		and height > 1.0
		and is_equal_approx(float(sprite.get("width", 0)), width)
		and is_equal_approx(float(sprite.get("height", 0)), height)
	)
	print("      channel 3: member %d, sprite %sx%s, member %sx%s, at (%s, %s)" % [
		int(sprite.get("cast_id", 0)), str(sprite.get("width")), str(sprite.get("height")),
		str(width), str(height), str(sprite.get("x")), str(sprite.get("y"))])
	return ok


func _initialize() -> void:
	var settings: Object = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true

	_case("DAY1", "gatego", 33, "shellfield")
	_case("DAY1", "edge1go", 15, "shellfield")
	_case("DAY1", "swinggo", 15, "jokefield")

	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
