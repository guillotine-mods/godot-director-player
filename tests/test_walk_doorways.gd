extends SceneTree
## Exits must send Piposh toward the hotspot he clicked, and land him on the
## side of the next room he actually arrived from.
##
## The export keys walk_to / arrive_at per destination label, so path1 and path3
## — which sit on opposite sides of path2 — both carried path3's coordinates:
## clicking path1's left-hand exit walked him right, to x=600, and then put him
## down on path2's left. data/walk_doorways.json restores the per-hotspot values.

var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_left_exit_walks_left()
	_test_arrives_on_the_side_he_came_from()
	_test_unlisted_hotspot_keeps_exported_nav()

	if failures.is_empty():
		print("PASS: walk doorway suite")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _new_runtime() -> RefCounted:
	## A parse error would otherwise leave every assertion unreached and the
	## suite would report PASS on a script that never ran.
	var script: Variant = load("res://director/director_runtime.gd")
	if script == null:
		failures.append("director_runtime.gd failed to load")
		return null
	var runtime: RefCounted = script.new()
	_expect_eq(runtime.boot(), OK, "boot loads the render-model index")
	return runtime


func _runtime_in_path1() -> RefCounted:
	## The label frame carries only the inventory channels; the exits appear a
	## few frames later, in the path1go idle loop. Run the score until they do.
	var runtime: RefCounted = _new_runtime()
	if runtime == null:
		return null
	_expect_true(
		runtime.goto_movie("DAY1", null, {"label": "path1"}),
		"DAY1 enters path1"
	)
	for _step in 20:
		if _exit_to_path2(runtime):
			break
		runtime.game_step()
	_expect_true(_exit_to_path2(runtime), "path1 idle loop offers the exit to path2")
	_expect_true(runtime.puppet.active, "the score puts Piposh on his feet in path1")
	return runtime


func _exit_to_path2(runtime: RefCounted) -> bool:
	for sprite in runtime.clickable_sprites(runtime.loader.get_frame(runtime.frame_index)):
		var nav: Variant = (sprite.get("on_click", {}) as Dictionary).get("nav", null)
		if typeof(nav) == TYPE_DICTIONARY and str(nav.get("target_label", "")) == "path2":
			return true
	return false


func _test_left_exit_walks_left() -> void:
	## path1's exit to path2 is channel 10, the strip down the left edge.
	var runtime := _runtime_in_path1()
	if runtime == null:
		return
	var started_at: float = runtime.puppet.loc_h
	runtime.perform_click(Vector2(15, 200))
	_expect_true(runtime.puppet.is_walking(), "clicking path1's left exit starts a walk")
	_expect_true(
		runtime.puppet.egozh < started_at,
		"path1's left exit walks left, not right (from %.0f to %.0f)"
			% [started_at, runtime.puppet.egozh]
	)
	_expect_eq(runtime.puppet.facing, "left", "Piposh faces the exit he was sent to")


func _test_arrives_on_the_side_he_came_from() -> void:
	## Leaving path1 on the left means entering path2 from its right.
	var runtime := _runtime_in_path1()
	if runtime == null:
		return
	runtime.perform_click(Vector2(15, 200))
	_expect_true(runtime.puppet.is_walking(), "walk to path2 started")
	for _step in 200:
		if not runtime.puppet.is_walking():
			break
		runtime.game_step()
	_expect_true(not runtime.puppet.is_walking(), "the walk to path2 finishes")
	_expect_eq(
		runtime.marker_name_for_frame(runtime.frame_index).to_lower().trim_suffix("go"),
		"path2",
		"the walk lands in path2"
	)
	# Deliberately tighter than "right of centre": path2's score parks channel 30
	# at x=352, so a loose bound would also pass if the arrive position were
	# dropped and the score position used instead.
	_expect_true(
		runtime.puppet.loc_h > 500.0,
		"entering path2 from path1 puts him at its right-hand doorway (loc_h=%.0f)"
			% runtime.puppet.loc_h
	)


func _test_unlisted_hotspot_keeps_exported_nav() -> void:
	## Only hotspots the rebuild could resolve are overridden; the rest pass
	## through untouched rather than silently pick up someone else's doorway.
	var runtime := _new_runtime()
	if runtime == null:
		return
	_expect_true(
		runtime.context.walk_override("DAY1", "path1go", 10, "path2").has("walk_to"),
		"path1's left-hand exit is overridden"
	)
	_expect_true(
		runtime.context.walk_override("DAY1", "path1go", 11, "veranda").is_empty(),
		"path1's right-hand exit already carried its own values"
	)
	_expect_true(
		runtime.context.walk_override("HOTEL1", "path1go", 10, "path2").is_empty(),
		"the override table is per movie"
	)
	_expect_true(
		runtime.context.walk_override("DAY1", "path1", 10, "path2").has("walk_to"),
		"a room matches with or without its 'go' suffix"
	)


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		failures.append("%s: expected true, got false" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
