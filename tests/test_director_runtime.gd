extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_large_delta_is_bounded()
	_test_excess_backlog_is_discarded()
	_test_ordinary_delta_advances_once()
	_test_boot_chain()

	if failures.is_empty():
		print("PASS: DirectorRuntime regression suite")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _make_runtime(fps: float = 10.0) -> RefCounted:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
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


func _test_large_delta_is_bounded() -> void:
	var runtime := _make_runtime()
	runtime.tick(1.0)
	_expect_eq(runtime.frame_index, 3, "large delta advances at most three score steps")


func _test_excess_backlog_is_discarded() -> void:
	var runtime := _make_runtime()
	runtime.tick(1.0)
	var bounded_frame: int = runtime.frame_index
	runtime.tick(0.01)
	_expect_eq(runtime.frame_index, bounded_frame, "excess score backlog is discarded")


func _test_ordinary_delta_advances_once() -> void:
	var runtime := _make_runtime()
	runtime.tick(0.1)
	_expect_eq(runtime.frame_index, 1, "ordinary delta advances one score step")


func _test_boot_chain() -> void:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	_expect_eq(runtime.boot(), OK, "boot loads the render model index")
	_expect_true(runtime.goto_movie("strtgame"), "boot chain enters strtgame")
	_expect_true(runtime.goto_movie("exodus", 1), "boot chain enters EXODUS frame 1")
	_expect_eq(runtime.loader.movie_name, "EXODUS", "boot chain loads EXODUS")
	_expect_eq(runtime.frame_index, 0, "EXODUS frame 1 uses zero-based frame 0")

	runtime.enter_frame(runtime.loader.frames.size() - 1)
	runtime.game_step()
	_expect_eq(runtime.loader.movie_name, "DAY1", "final EXODUS frame enters DAY1")
	_expect_eq(runtime.frame_index, 0, "DAY1 frame 1 uses zero-based frame 0")


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		failures.append("%s: expected true, got false" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
