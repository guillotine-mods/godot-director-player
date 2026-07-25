extends SceneTree

var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	_expect_eq(runtime.boot(), OK, "mountain-stairs test loads the render-model index")
	_expect_true(
		runtime.goto_movie("DAY1", null, {"label": "stairs"}),
		"mountain-stairs test enters the stairs room"
	)

	runtime.perform_click(Vector2(100, 330))
	_expect_true(runtime.puppet.is_walking(), "mountain-stairs hotspot starts walking")

	var reached_lighttop := false
	var fell_into_stairsclimbdown := false
	for _step in 100:
		runtime.game_step()
		var marker: String = runtime.marker_name_for_frame(runtime.frame_index).to_lower()
		if marker == "stairsclimbdown":
			fell_into_stairsclimbdown = true
			break
		if marker == "lighttop":
			reached_lighttop = true
			break

	_expect_true(not fell_into_stairsclimbdown, "climb-up never enters climb-down")
	_expect_true(reached_lighttop, "climb-up finishes at lighttop")

	if failures.is_empty():
		print("PASS: Day 1 navigation regression suite")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect_true(actual: bool, message: String) -> void:
	if not actual:
		failures.append("%s: expected true, got false" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
