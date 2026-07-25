extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_large_delta_preserves_fractional_remainder()
	_test_ordinary_delta_advances_once()
	_test_title_opening_boot_and_skip()
	_test_boot_chain()
	_test_same_movie_transition_stops_catch_up()
	_test_go_back_discards_accumulated_time()
	_test_missing_movie_navigation_is_attempted_once_per_tick()
	_test_loader_failed_movie_load_is_transactional()
	_test_loader_rejects_invalid_numeric_metadata_transactionally()
	_test_failed_goto_preserves_runtime_state()
	_test_failed_go_back_preserves_runtime_state()

	if failures.is_empty():
		print("PASS: DirectorRuntime regression suite")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _make_runtime(fps: float = 10.0) -> RefCounted:
	var runtime := _new_runtime()
	var frames: Array = []
	for index in 20:
		frames.append({
			"frame_index": index,
			"fps": fps,
			"nav": null,
			"delay_ms": 0,
			"wait_click": false,
			"sounds": [],
			"sprites": [],
		})
	runtime.loader.movie_name = "TEST"
	runtime.loader.frames = frames
	runtime.enter_frame(0)
	return runtime


func _new_runtime() -> RefCounted:
	return load("res://director/director_runtime.gd").new()


func _test_large_delta_preserves_fractional_remainder() -> void:
	var runtime := _make_runtime()
	runtime.tick(1.05)
	_expect_eq(runtime.frame_index, 3, "large delta advances at most three score steps")

	runtime.tick(0.049)
	_expect_eq(runtime.frame_index, 3, "excess score backlog is discarded")

	runtime.tick(0.002)
	_expect_eq(runtime.frame_index, 4, "fractional score remainder is preserved")


func _test_ordinary_delta_advances_once() -> void:
	var runtime := _make_runtime()
	runtime.tick(0.1)
	_expect_eq(runtime.frame_index, 1, "ordinary delta advances one score step")


func _test_title_opening_boot_and_skip() -> void:
	var runtime := _new_runtime()
	_expect_eq(runtime.boot(), OK, "title opening loads the render model index")
	_expect_true(
		runtime.goto_movie("strtgame", null, {"play_opening": true}),
		"title opening loads"
	)
	_expect_eq(runtime.frame_index, 0, "initial title boot begins with the opening")

	runtime.skip_current()
	_expect_eq(
		runtime.frame_index,
		runtime.loader.lookup_label("mainmenu"),
		"skip moves the title opening to the main menu"
	)


func _test_boot_chain() -> void:
	var runtime := _new_runtime()
	_expect_eq(runtime.boot(), OK, "boot loads the render model index")
	_expect_true(runtime.goto_movie("strtgame"), "boot chain enters strtgame")
	runtime.perform_click(Vector2(300, 100))
	_expect_eq(runtime.loader.movie_name, "EXODUS", "boot chain loads EXODUS")
	_expect_eq(runtime.frame_index, 0, "EXODUS frame 1 uses zero-based frame 0")

	runtime.enter_frame(runtime.loader.frames.size() - 1)
	runtime.game_step()
	_expect_eq(runtime.loader.movie_name, "DAY1", "final EXODUS frame enters DAY1")
	_expect_eq(runtime.frame_index, 0, "DAY1 frame 1 uses zero-based frame 0")


func _test_same_movie_transition_stops_catch_up() -> void:
	var runtime := _new_runtime()
	_expect_eq(runtime.boot(), OK, "same-movie test loads the render model index")
	_expect_true(runtime.goto_movie("EXODUS"), "same-movie test enters EXODUS")
	runtime.loader.frames[0]["nav"] = {
		"kind": "movie",
		"value": "exodus",
		"frame": 2,
	}

	runtime.tick(1.0)
	_expect_eq(runtime.frame_index, 1, "same-movie transition stops score catch-up")


func _test_go_back_discards_accumulated_time() -> void:
	var runtime := _new_runtime()
	_expect_eq(runtime.boot(), OK, "go-back test loads the render model index")
	_expect_true(runtime.goto_movie("strtgame"), "go-back test enters strtgame")
	_expect_true(runtime.goto_movie("EXODUS"), "go-back test enters EXODUS")

	runtime.tick(0.05)
	_expect_true(runtime.go_back(), "go-back test returns to strtgame")
	_expect_eq(runtime.loader.movie_name, "strtgame", "go-back test restores strtgame")
	var returned_title_frame: int = runtime.frame_index
	runtime.tick(0.03)
	_expect_eq(runtime.frame_index, returned_title_frame, "go_back discards accumulated score time")


func _test_missing_movie_navigation_is_attempted_once_per_tick() -> void:
	var runtime := _make_runtime()
	runtime.loader.frames[0]["nav"] = {
		"kind": "movie",
		"value": "definitely_missing_movie",
	}
	var missing_event_count := [0]
	runtime.nav_event.connect(func(description: String):
		if description.begins_with("Missing movie:"):
			missing_event_count[0] += 1
	)

	runtime.tick(1.0)
	_expect_eq(missing_event_count[0], 1, "missing movie navigation is attempted once per tick")


func _test_loader_failed_movie_load_is_transactional() -> void:
	var loader: RefCounted = load("res://director/render_model_loader.gd").new()
	_expect_eq(loader.load_index(), OK, "transactional loader test loads the index")
	_expect_eq(loader.load_movie("EXODUS"), OK, "transactional loader test loads EXODUS")
	var previous_state := _snapshot_loader_state(loader)

	_expect_eq(
		loader.load_movie("BROKEN"),
		ERR_FILE_NOT_FOUND,
		"missing movie load returns ERR_FILE_NOT_FOUND"
	)
	_expect_loader_state(loader, previous_state, "failed movie load")


func _test_loader_rejects_invalid_numeric_metadata_transactionally() -> void:
	var cases := [
		{
			"movie": "_TEST_INVALID_FIRST_PLAYABLE",
			"description": "invalid first_playable_frame",
		},
		{
			"movie": "_TEST_INVALID_STAGE_WIDTH",
			"description": "invalid stage.width",
		},
		{
			"movie": "_TEST_INVALID_STAGE_HEIGHT",
			"description": "invalid stage.height",
		},
	]
	for test_case in cases:
		var description := str(test_case.description)
		var loader: RefCounted = load("res://director/render_model_loader.gd").new()
		_expect_eq(loader.load_index(), OK, "%s test loads the index" % description)
		_expect_eq(loader.load_movie("EXODUS"), OK, "%s test loads EXODUS" % description)
		var previous_state := _snapshot_loader_state(loader)

		_expect_eq(
			loader.load_movie(str(test_case.movie)),
			ERR_INVALID_DATA,
			"%s is rejected" % description
		)
		_expect_loader_state(loader, previous_state, description)


func _test_failed_goto_preserves_runtime_state() -> void:
	var runtime := _new_runtime()
	_expect_eq(runtime.boot(), OK, "failed-goto test loads the render model index")
	_expect_true(runtime.goto_movie("strtgame"), "failed-goto test enters strtgame")
	_expect_true(runtime.goto_movie("EXODUS"), "failed-goto test enters EXODUS")
	runtime.loader.index["exports"].append({"movie": "BROKEN"})
	var previous_movie_name: String = runtime.loader.movie_name
	var previous_base_path: String = runtime.loader.base_path
	var previous_frames: Array = runtime.loader.frames.duplicate(true)
	var previous_frame_index: int = runtime.frame_index
	var previous_route_stack: Array = runtime.route_stack.duplicate(true)

	_expect_true(not runtime.goto_movie("BROKEN"), "failed goto returns false")
	_expect_eq(runtime.loader.movie_name, previous_movie_name, "failed goto preserves active movie")
	_expect_eq(runtime.loader.base_path, previous_base_path, "failed goto preserves active base path")
	_expect_eq(runtime.loader.frames, previous_frames, "failed goto preserves active frame data")
	_expect_eq(runtime.frame_index, previous_frame_index, "failed goto preserves active frame")
	_expect_eq(runtime.route_stack, previous_route_stack, "failed goto preserves route stack")


func _test_failed_go_back_preserves_runtime_state() -> void:
	var runtime := _new_runtime()
	_expect_eq(runtime.boot(), OK, "failed-go-back test loads the render model index")
	_expect_true(runtime.goto_movie("EXODUS"), "failed-go-back test enters EXODUS")
	runtime.loader.index["exports"].append({"movie": "BROKEN"})
	runtime.route_stack.clear()
	runtime.route_stack.append({"movie": "BROKEN", "frame": 123})
	var previous_movie_name: String = runtime.loader.movie_name
	var previous_base_path: String = runtime.loader.base_path
	var previous_frames: Array = runtime.loader.frames.duplicate(true)
	var previous_frame_index: int = runtime.frame_index
	var previous_route_stack: Array = runtime.route_stack.duplicate(true)

	_expect_true(not runtime.go_back(), "failed go_back returns false")
	_expect_eq(runtime.loader.movie_name, previous_movie_name, "failed go_back preserves active movie")
	_expect_eq(runtime.loader.base_path, previous_base_path, "failed go_back preserves active base path")
	_expect_eq(runtime.loader.frames, previous_frames, "failed go_back preserves active frame data")
	_expect_eq(runtime.frame_index, previous_frame_index, "failed go_back preserves active frame")
	_expect_eq(runtime.route_stack, previous_route_stack, "failed go_back preserves route stack")


func _snapshot_loader_state(loader: RefCounted) -> Dictionary:
	return {
		"movie_name": loader.movie_name,
		"base_path": loader.base_path,
		"frames": loader.frames,
		"members": loader.members,
		"cast_libs": loader.cast_libs,
		"labels": loader.labels,
		"markers": loader.markers,
		"frame_values": loader.frames.duplicate(true),
		"member_values": loader.members.duplicate(true),
		"cast_lib_values": loader.cast_libs.duplicate(true),
		"label_values": loader.labels.duplicate(true),
		"marker_values": loader.markers.duplicate(true),
		"stage_size": loader.stage_size,
		"first_playable_frame": loader.first_playable_frame,
	}


func _expect_loader_state(loader: RefCounted, expected: Dictionary, context: String) -> void:
	_expect_eq(loader.movie_name, expected.movie_name, "%s preserves movie name" % context)
	_expect_eq(loader.base_path, expected.base_path, "%s preserves base path" % context)
	_expect_true(is_same(loader.frames, expected.frames), "%s preserves frames" % context)
	_expect_true(is_same(loader.members, expected.members), "%s preserves members" % context)
	_expect_true(
		is_same(loader.cast_libs, expected.cast_libs),
		"%s preserves cast libraries" % context
	)
	_expect_true(is_same(loader.labels, expected.labels), "%s preserves labels" % context)
	_expect_true(is_same(loader.markers, expected.markers), "%s preserves markers" % context)
	_expect_true(
		loader.frames == expected.frame_values,
		"%s preserves frame values" % context
	)
	_expect_true(
		loader.members == expected.member_values,
		"%s preserves member values" % context
	)
	_expect_true(
		loader.cast_libs == expected.cast_lib_values,
		"%s preserves cast library values" % context
	)
	_expect_true(
		loader.labels == expected.label_values,
		"%s preserves label values" % context
	)
	_expect_true(
		loader.markers == expected.marker_values,
		"%s preserves marker values" % context
	)
	_expect_eq(loader.stage_size, expected.stage_size, "%s preserves stage size" % context)
	_expect_eq(
		loader.first_playable_frame,
		expected.first_playable_frame,
		"%s preserves first playable frame" % context
	)


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		failures.append("%s: expected true, got false" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
