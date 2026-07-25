extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_large_delta_preserves_fractional_remainder()
	_test_ordinary_delta_advances_once()
	_test_boot_chain()
	_test_same_movie_transition_stops_catch_up()
	_test_go_back_discards_accumulated_time()

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


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		failures.append("%s: expected true, got false" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
