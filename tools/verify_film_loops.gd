extends SceneTree
## Do the film loops recovered from the chunk dump actually resolve to drawable
## children?
##
## `check_cast_coverage.py` proves the mini-scores are in the registry. It says
## nothing about whether the runtime can turn one into pixels: the loop has to
## resolve through the linked cast, every child member has to find a bitmap, and
## the frame cursor has to have somewhere to advance to. A loop that parses but
## whose children resolve to nothing looks exactly like the bug this was meant to
## fix.
##
##   godot --headless --script tools/verify_film_loops.gd

## Each newly recovered loop, with a movie that references it.
const CASES := [
	{"cast": "black", "id": 173, "movie": "SAMNIGHT"},
	{"cast": "detectiv", "id": 202, "movie": "ENDMOVI5"},
	{"cast": "detectiv", "id": 204, "movie": "ENDMOVI5"},
	{"cast": "hatuli", "id": 152, "movie": "MIROLO"},
	{"cast": "hatuli", "id": 157, "movie": "MIROLO"},
	{"cast": "hatuli", "id": 158, "movie": "MIROLO"},
	{"cast": "heznigt", "id": 295, "movie": "SAMNIGHT"},
	{"cast": "heznigt", "id": 296, "movie": "FUGEL"},
	{"cast": "heznigt", "id": 297, "movie": "FUGEL"},
	{"cast": "jokers", "id": 101, "movie": "DIVEFIGT"},
	{"cast": "jokers", "id": 105, "movie": "DIVEFIGT"},
	{"cast": "sabmon", "id": 135, "movie": "SABMON2"},
	{"cast": "sabmon", "id": 140, "movie": "SABMON2"},
]


func _initialize() -> void:
	var loader := RenderModelLoader.new()
	if loader.load_index() != OK:
		print("error: cannot load render model index")
		quit(1)
		return

	var failures := 0
	var loaded := ""
	for case in CASES:
		var movie: String = case["movie"]
		if movie != loaded:
			if loader.load_movie(movie) != OK:
				print("%s: cannot load movie" % movie)
				failures += 1
				continue
			loaded = movie
		failures += _check(loader, case)

	print("")
	if failures == 0:
		print("all %d recovered film loops resolve to drawable children" % CASES.size())
	else:
		print("%d of %d film loops did not resolve" % [failures, CASES.size()])
	quit(1 if failures > 0 else 0)


func _check(loader: RenderModelLoader, case: Dictionary) -> int:
	var cast_name: String = case["cast"]
	var cast_id: int = case["id"]
	var movie: String = case["movie"]
	var lib := loader.cast_lib_index(cast_name)
	if lib < 0:
		print("%-9s %3d  %-9s FAIL: movie does not link the cast" % [cast_name, cast_id, movie])
		return 1

	var loop := loader.get_film_loop(lib, cast_id)
	if loop.is_empty():
		print("%-9s %3d  %-9s FAIL: loop did not resolve" % [cast_name, cast_id, movie])
		return 1

	var loop_frames: Array = loop.get("frames", [])
	var distinct_members := {}
	var drawable := 0
	var undrawable := 0
	for loop_frame in loop_frames:
		for child in (loop_frame as Dictionary).get("sprites", []):
			var child_id := int((child as Dictionary).get("cast_id", 0))
			if distinct_members.has(child_id):
				continue
			distinct_members[child_id] = true
			if loader.get_registry_texture(cast_name, child_id) != null:
				drawable += 1
			else:
				undrawable += 1

	var status := "ok"
	var failed := 0
	if loop_frames.size() < 2:
		status = "FAIL: %d frame, nothing to animate" % loop_frames.size()
		failed = 1
	elif drawable == 0:
		status = "FAIL: no child member resolves to a bitmap"
		failed = 1
	elif undrawable > 0:
		status = "WARN: %d of %d children have no bitmap" % [undrawable, drawable + undrawable]

	print("%-9s %3d  %-9s %2d frames, %2d children  %s" % [
		cast_name, cast_id, movie, loop_frames.size(), distinct_members.size(), status,
	])
	return failed
