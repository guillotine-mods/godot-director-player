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

## Each newly recovered loop, with a movie that references it. `in` names the cast
## the loop's children are expected to come from where that is not the cast the
## loop itself lives in, with the member and its size the port must find there:
## a child resolved against the wrong library is either invisible or a stranger's
## bitmap, and both look like a loop that works from a count alone.
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
	# The cliff: both characters animate out of a loop kept in MURDER1's own cast
	# whose frames are members of the linked casts.
	{"cast": "murder1", "id": 5, "movie": "MURDER1", "in": "tofi", "member": 4, "size": [108, 273]},
	{"cast": "murder1", "id": 10, "movie": "MURDER1", "in": "goldolin", "member": 63, "size": [115, 252]},
	{"cast": "murder1", "id": 13, "movie": "MURDER1", "in": "tofi", "member": 10, "size": [103, 267]},
	{"cast": "murder1", "id": 15, "movie": "MURDER1", "in": "hezi", "member": 81, "size": [118, 254]},
	{"cast": "mirolo", "id": 143, "movie": "MIROLO", "in": "hatuli", "member": 49, "size": [130, 259]},
	{"cast": "mirolo", "id": 179, "movie": "MIROLO", "in": "ishurun", "member": 150, "size": [173, 269]},
]


## The two frames the cliff was reported on, asserted through the renderer rather
## than through the registry: the channel, the score frame, and the members the
## composition must come out as, `<cast>:<id>` low channel first.
const COMPOSITIONS := [
	{
		"movie": "MURDER1", "frame": 10, "channel": 9,
		"children": ["tofi:4"],
		"note": "Tofi's body, whose mouth on channel 11 drew without him",
	},
	{
		"movie": "MURDER1", "frame": 110, "channel": 3,
		"children": ["goldolin:63"],
		"note": "Goldolin walking, absent in the reported screenshot",
	},
	{
		"movie": "MURDER1", "frame": 145, "channel": 9,
		"children": ["tofi:4", "tofi:31"],
		"note": "Tofi's body and his mouth, both children of one loop",
	},
]


func _initialize() -> void:
	var loader := RenderModelLoader.new()
	if loader.load_index() != OK:
		print("error: cannot load render model index")
		quit(1)
		return

	var failures := 0
	var loaded := ""
	var loop_labels: Array = []
	for case in CASES:
		var label := "%s %d" % [case["cast"], case["id"]]
		loop_labels.append(label)
		var movie: String = case["movie"]
		if movie != loaded:
			if loader.load_movie(movie) != OK:
				print("%s: cannot load movie" % movie)
				_complete(label, 1)
				failures += 1
				continue
			loaded = movie
		failures += _check(loader, case)
	failures += _report_incomplete(loop_labels)

	print("")
	if failures == 0:
		print("all %d recovered film loops resolve to drawable children" % CASES.size())
	else:
		print("%d of %d film loops did not resolve" % [failures, CASES.size()])

	print("")
	var composition_failures := 0
	var composition_labels: Array = []
	for case in COMPOSITIONS:
		composition_labels.append("%s frame %d" % [case["movie"], case["frame"]])
		composition_failures += _check_composition(case)
	composition_failures += _report_incomplete(composition_labels)
	if composition_failures == 0:
		print("all %d loop compositions draw the expected members" % COMPOSITIONS.size())
	else:
		print("%d of %d loop compositions are wrong" % [
			composition_failures, COMPOSITIONS.size(),
		])
	quit(1 if failures + composition_failures > 0 else 0)


## Every check that ran to completion, by label. A check is only counted from its
## own last line, so one that died part-way is missing rather than passing.
##
## A GDScript runtime error aborts the handler and hands back the return type's
## zero value — `0` for a function typed `-> int` — so `failures += _check(...)`
## scores a dead check as a pass. This harness printed "all 3 loop compositions
## draw the expected members" twice while every one of them had aborted: once on a
## mistyped call, once when a stale `global_script_class_cache.cfg` made every
## `load()` of a script fail to parse. Neither was visible in the summary.
var _completed: Dictionary = {}


func _complete(label: String, failed: int) -> int:
	_completed[label] = failed
	return failed


func _report_incomplete(labels: Array) -> int:
	var missing := 0
	for label in labels:
		if not _completed.has(label):
			print("%-32s FAIL: the check did not complete (see the errors above)" % label)
			missing += 1
	return missing


func _check_composition(case: Dictionary) -> int:
	## What `MoviePlayer.film_loop_draw_commands` actually resolves for one score
	## frame's loop channel. This is the renderer's own decision, so a regression in
	## it fails here; the case list above is what the fix was reported against.
	var movie: String = case["movie"]
	var frame: int = case["frame"]
	var channel: int = case["channel"]
	var expected: Array = case["children"]
	var label := "%s frame %d" % [movie, frame]

	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK or not runtime.goto_movie(movie, frame):
		print("%-9s frame %4d  FAIL: cannot reach the frame" % [movie, frame])
		return _complete(label, 1)
	# Park the playhead rather than let the clock carry it off the frame.
	runtime.running = false
	runtime.frame_index = frame - 1
	runtime.reconcile_channels(runtime.loader.get_frame(runtime.frame_index))

	var sprite: Dictionary = runtime.effective_sprite(channel)
	if sprite.is_empty():
		print("%-9s frame %4d  FAIL: channel %d is empty" % [movie, frame, channel])
		return _complete(label, 1)
	var loop: Dictionary = runtime.loader.get_film_loop(
		int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0))
	)
	if loop.is_empty():
		print("%-9s frame %4d  FAIL: channel %d is not a film loop" % [movie, frame, channel])
		return _complete(label, 1)

	var player: Control = load("res://director/movie_player.gd").new()
	player.runtime = runtime
	var commands: Array = player.film_loop_draw_commands(sprite, loop, channel)
	var drawn: Array = []
	for command_value in commands:
		var command: Dictionary = command_value
		drawn.append("%s:%d" % [command.cast, command.cast_id])
	player.free()

	# An empty composition is a failure even where none is expected: it is what a
	# broken call into the renderer looks like, and it must not read as agreement.
	var ok: bool = not drawn.is_empty() and drawn == expected
	print("%-9s frame %4d ch%-3d %s  %s  %s" % [
		movie, frame, channel,
		"ok  " if ok else "FAIL",
		str(drawn) if ok else "%s, expected %s" % [str(drawn), str(expected)],
		str(case.get("note", "")),
	])
	return _complete(label, 0 if ok else 1)


func _check(loader: RenderModelLoader, case: Dictionary) -> int:
	var cast_name: String = case["cast"]
	var cast_id: int = case["id"]
	var movie: String = case["movie"]
	var label := "%s %d" % [cast_name, cast_id]
	# A loop kept in the movie's own cast is library 1; a loop in a linked cast is
	# whichever library the movie links it as.
	var lib := 1 if cast_name == movie.to_lower() else loader.cast_lib_index(cast_name)
	if lib < 0:
		print("%-9s %3d  %-9s FAIL: movie does not link the cast" % [cast_name, cast_id, movie])
		return _complete(label, 1)

	var loop := loader.get_film_loop(lib, cast_id)
	if loop.is_empty():
		print("%-9s %3d  %-9s FAIL: loop did not resolve" % [cast_name, cast_id, movie])
		return _complete(label, 1)

	var loop_frames: Array = loop.get("frames", [])
	var distinct_members := {}
	var drawable := 0
	var undrawable := 0
	# What the named member was found as, so an expectation can be checked against
	# the cast the child itself names rather than against the loop's owner.
	var expected_member: int = int(case.get("member", -1))
	var expected_in: String = str(case.get("in", ""))
	var found_in := ""
	var found_size := Vector2i.ZERO
	for loop_frame in loop_frames:
		for child in (loop_frame as Dictionary).get("sprites", []):
			var child_dict: Dictionary = child
			var child_id := int(child_dict.get("cast_id", 0))
			var child_cast := str(child_dict.get("cast", cast_name))
			var key := "%s:%d" % [child_cast, child_id]
			if distinct_members.has(key):
				continue
			distinct_members[key] = true
			var member := loader.get_registry_member(child_cast, child_id)
			if loader.get_registry_texture(child_cast, child_id) != null:
				drawable += 1
			else:
				undrawable += 1
			if child_id == expected_member and not member.is_empty():
				found_in = child_cast
				found_size = Vector2i(
					int(member.get("width", 0)), int(member.get("height", 0))
				)

	var status := "ok"
	var failed := 0
	if loop_frames.size() < 2:
		status = "FAIL: %d frame, nothing to animate" % loop_frames.size()
		failed = 1
	elif drawable == 0:
		status = "FAIL: no child member resolves to a bitmap"
		failed = 1
	elif expected_member >= 0:
		var expected_size := Vector2i(
			int((case.get("size", [0, 0]) as Array)[0]),
			int((case.get("size", [0, 0]) as Array)[1]),
		)
		if found_in != expected_in:
			status = "FAIL: member %d came from %s, expected %s" % [
				expected_member, found_in if not found_in.is_empty() else "nowhere", expected_in,
			]
			failed = 1
		elif found_size != expected_size:
			status = "FAIL: %s member %d is %dx%d, expected %dx%d" % [
				expected_in, expected_member,
				found_size.x, found_size.y, expected_size.x, expected_size.y,
			]
			failed = 1
		else:
			status = "ok, member %d from %s at %dx%d" % [
				expected_member, found_in, found_size.x, found_size.y,
			]
	if failed == 0 and undrawable > 0:
		status = "WARN: %d of %d children have no bitmap" % [undrawable, drawable + undrawable]

	print("%-9s %3d  %-9s %2d frames, %2d children  %s" % [
		cast_name, cast_id, movie, loop_frames.size(), distinct_members.size(), status,
	])
	return _complete(label, failed)
