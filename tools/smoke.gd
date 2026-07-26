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

	# Deliberately no "entry hides nothing" assertion: blanking sprites on entry
	# is what the original does, and the conditional handler on the next entry
	# frame restores whatever the player has not collected. The inventory-driven
	# checks at the end are the real invariant.
	runtime.goto_movie("DAY1", null, {})
	runtime.enter_frame(2649)
	var pickup: Dictionary = {}
	for sprite in runtime.clickable_sprites(runtime.loader.get_frame(runtime.frame_index)):
		if int((sprite as Dictionary).get("channel", 0)) == 18:
			pickup = sprite
	var before: int = Array(state.objects_field).count("empty")
	runtime._activate_sprite(pickup, Vector2(320, 240))
	_check("picking an item up adds it", Array(state.objects_field).count("empty") == before - 1)
	_check("picking an item up clears it from the room", runtime.is_channel_hidden(18))

	# Collectables are inventory-driven: DAY1's dwarfs room shows sprite 17 until
	# the player holds `masor`, then hides it. This has broken three separate ways
	# today, so it is asserted in both directions.
	for holds in [false, true]:
		var probe: RefCounted = load("res://director/director_runtime.gd").new()
		probe.boot()
		state.new_game()
		if holds:
			var carried: PackedStringArray = state.objects_field
			carried[0] = "masor"
			state.objects_field = carried
		probe.goto_movie("DAY1", null, {"label": "dwarfsgo"})
		var hidden: bool = probe.is_channel_hidden(17)
		_check("collectable %s when masor %s" % [
			"hidden" if holds else "shown", "held" if holds else "not held"],
			hidden == holds)

	# Conditional content keyed on `meetings`. DAY1 BehaviorScript 226 hides
	# Gondolin's corpse and handbag until the murder, and CastScript 218 reveals
	# what is inside the bag only when it is searched.
	for murdered in [false, true]:
		var scene: RefCounted = load("res://director/director_runtime.gd").new()
		scene.boot()
		state.new_game()
		if murdered:
			var seen: PackedStringArray = state.meetings
			seen[0] = "done"
			state.meetings = seen
			state.set_story_flag("murder1")
		scene.goto_movie("DAY1", null, {"label": "shore3go"})
		_check("handbag %s before the murder is %s" % [
			"visible" if murdered else "hidden", "done" if murdered else "pending"],
			scene.is_channel_hidden(16) != murdered)
		if not murdered:
			continue
		_check("bag contents stay hidden until searched", scene.is_channel_hidden(15))
		var bag: Dictionary = {}
		for sprite in scene.clickable_sprites(scene.loader.get_frame(scene.frame_index)):
			if int((sprite as Dictionary).get("channel", 0)) == 16:
				bag = sprite
		scene._activate_sprite(bag, scene.sprite_stage_rect(bag).get_center())
		for _i in 200:
			scene.tick(0.1)
		scene._activate_sprite(bag, scene.sprite_stage_rect(bag).get_center())
		_check("searching the bag reveals what is inside", not scene.is_channel_hidden(15))

	# Story-gated exit. ISLAND2 CastScript 34 only walks when
	# `item 1 of meetings <> "murder1"`, so the edge2 -> edge1 path is shut until
	# the murder is resolved. lingo_walk_diff scores this as a dead click, because
	# the lifted export it compares against has no story gating at all.
	for resolved in [false, true]:
		var exit_scene: RefCounted = load("res://director/director_runtime.gd").new()
		exit_scene.boot()
		state.new_game()
		if resolved:
			var seen: PackedStringArray = state.meetings
			seen[0] = "done"
			state.meetings = seen
		exit_scene.goto_movie("DAY1", null, {"label": "edge2go"})
		var exit_sprite: Dictionary = {}
		for sprite in exit_scene.clickable_sprites(exit_scene.loader.get_frame(exit_scene.frame_index)):
			if int((sprite as Dictionary).get("channel", 0)) == 10:
				exit_sprite = sprite
		exit_scene._activate_sprite(exit_sprite, exit_scene.sprite_stage_rect(exit_sprite).get_center())
		var walked: bool = exit_scene.puppet.is_walking()
		_check("edge2 exit %s while the murder is %s" % [
			"opens" if resolved else "stays shut", "done" if resolved else "pending"],
			walked == resolved)

	print("")
	print("%d checks failed" % _fails)
	quit(1 if _fails > 0 else 0)
