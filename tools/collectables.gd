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
	runtime._activate_sprite(target, runtime.sprite_stage_rect(target).get_center())
	_check("%s: taking it hides it" % label, runtime.is_channel_hidden(channel))
	var after := str(runtime.lingo.host.get_field(field, "master"))
	_check("%s: taking it records the room in %s" % [label, field], after != before,
		"%s -> %s" % [before.substr(0, 18), after.substr(0, 18)])


func _initialize() -> void:
	var settings: Object = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true

	_case("DAY1", "gatego", 33, "shellfield")
	_case("DAY1", "edge1go", 15, "shellfield")
	_case("DAY1", "swinggo", 15, "jokefield")

	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
