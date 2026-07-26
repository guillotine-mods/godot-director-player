extends SceneTree
## The path a player takes in the first minute, asserted end to end.
##
##   godot --headless --script tools/smoke.gd
##
## Every regression this session landed here and nowhere else: the intro loop,
## the blanked collectables, the pickup that would not clear. The walk harness
## measures which room a walk reaches and sees none of it.

var _fails := 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["ok  " if ok else "FAIL", name, ("  (%s)" % detail) if detail != "" else ""])


func _initialize() -> void:
	var settings: Object = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true
	var state: Object = root.get_node("GameState")
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	runtime.boot()
	state.new_game()

	runtime.goto_movie("strtgame", null, {})
	for _i in 20:
		runtime.tick(0.1)
	_check("boots to the main menu", runtime.label_near_frame(runtime.frame_index) == "mainmenu",
		runtime.label_near_frame(runtime.frame_index))

	var new_game: Dictionary = {}
	for sprite in runtime.clickable_sprites(runtime.loader.get_frame(runtime.frame_index)):
		if int((sprite as Dictionary).get("channel", 0)) == 4:
			new_game = sprite
	runtime.perform_click(runtime.sprite_stage_rect(new_game).get_center())
	var reached: Array = []
	for _i in 1200:
		runtime.tick(0.1)
		if reached.is_empty() or reached[-1] != runtime.loader.movie_name:
			reached.append(runtime.loader.movie_name)
	_check("New Game runs the intro and lands in DAY1", reached == ["EXODUS", "DAY1"], str(reached))

	# The opening cinematic must advance rather than sit on one marker.
	var cinematic: RefCounted = load("res://director/director_runtime.gd").new()
	cinematic.boot()
	cinematic.goto_movie("strtgame", null, {})
	cinematic.enter_frame(42)
	var visited: Dictionary = {}
	for _i in 600:
		cinematic.game_step()
		visited[cinematic.frame_index] = true
	_check("opening cinematic advances", visited.size() > 100, "%d distinct frames" % visited.size())

	runtime.goto_movie("DAY1", null, {})
	runtime.enter_frame(976)
	_check("room entry hides nothing", runtime._lingo_hidden.is_empty(), str(runtime._lingo_hidden.keys()))

	runtime.enter_frame(2649)
	var pickup: Dictionary = {}
	for sprite in runtime.clickable_sprites(runtime.loader.get_frame(runtime.frame_index)):
		if int((sprite as Dictionary).get("channel", 0)) == 18:
			pickup = sprite
	var before: int = Array(state.objects_field).count("empty")
	runtime._activate_sprite(pickup, Vector2(320, 240))
	_check("picking an item up adds it", Array(state.objects_field).count("empty") == before - 1)
	_check("picking an item up clears it from the room", runtime.is_channel_hidden(18))

	print("")
	print("%d checks failed" % _fails)
	quit(1 if _fails > 0 else 0)
