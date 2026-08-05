extends SceneTree
## `nof` must be the name of sprite 1's member, resolved in sprite 1's own cast.
##
##   godot --headless --script tools/room_names.gd
##
## Every room announces itself with `nof = member(the castNum of sprite 1).name`
## (DAY1 BehaviorScript 83, and 17 more sites). Sprite 1 is the background, and in
## DAY1 it comes from the linked `island` cast, so the reference only resolves if it
## carries its cast library: DAY1's own member 10 is the cursor `wlkcur1` while
## island's is `shore2`. Without the library, 25 of DAY1's 32 rooms answered with a
## cursor name and the other 7 with nothing at all.
##
## `nof` is the key the collectables are recorded under. MASTER CastScript 77 puts it
## into `shellfield`, CastScript 69 into `jokefield`, and `searchfunk`
## (MovieScript 78) refuses to reveal anything in a room already listed there. So an
## empty `nof` silently marks every room that has one as already collected.
##
## Deliberately not asserted: that rooms have *distinct* keys. They do not, in the
## original either. HOTEL1's rooms A, B, C and the bathroom all score `hotel:6` in
## sprite 1, and NIGHT1 carries two different members both named `path4`. The
## original shares those keys too, so requiring uniqueness would be asserting a
## tidier game than the one being ported. Reported below, not failed.

var _fails := 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["ok  " if ok else "FAIL", name, ("  (%s)" % detail) if detail != "" else ""])


func _expected(runtime: RefCounted, frame_index: int) -> String:
	## What the original resolves: sprite 1's member, named in its own cast library.
	##
	## Read from the room's own score frame rather than from wherever the runtime
	## ended up. Entering a room can trigger a meeting, which loads another movie, and
	## the comparison would then be against a frame of that one.
	var sprite: Dictionary = {}
	for candidate in runtime.loader.get_frame(frame_index).get("sprites", []):
		if typeof(candidate) == TYPE_DICTIONARY and int(candidate.get("channel", 0)) == 1:
			sprite = candidate
	if sprite.is_empty():
		return "<no sprite 1>"
	var lib := int(sprite.get("cast_lib", 1))
	var member := int(sprite.get("cast_id", 0))
	var entry: Variant = runtime.loader.cast_libs.get(str(lib), null)
	var cast := ""
	if typeof(entry) == TYPE_DICTIONARY:
		cast = str((entry as Dictionary).get("name", "")).strip_edges().to_lower()
	if cast == "" or cast == "internal":
		cast = runtime.loader.movie_name.to_lower()
	var by_number: Variant = runtime.lingo.host.member_names.get(cast, {})
	if typeof(by_number) != TYPE_DICTIONARY or not (by_number as Dictionary).has(member):
		return ""
	return str((by_number as Dictionary)[member])


func _initialize() -> void:
	var settings: Object = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true
	root.get_node("GameState").new_game()

	for movie in ["DAY1", "NIGHT1", "HOTEL1"]:
		var runtime: RefCounted = load("res://director/director_runtime.gd").new()
		runtime.boot()
		runtime.goto_movie(movie, null, {})
		var rooms: Array = []
		for label in runtime.loader.labels.keys():
			var name := str(label)
			if name.ends_with("go") and name.length() > 2:
				rooms.append(name)
		rooms.sort()

		var empty: Array = []
		var wrong: Array = []
		var seen: Dictionary = {}
		var shared := 0
		var departed := 0
		for room in rooms:
			runtime.goto_movie(movie, null, {"label": room})
			var nof := str(runtime.lingo.interpreter.globals.get("nof", ""))
			if nof == "":
				empty.append(room)
			# Arriving can trigger a meeting, which loads another movie: `shore3go` and
			# `receptgo` both do. `nof` was set before that happened and is still the
			# room's, but the loader now holds the meeting, so there is nothing here to
			# compare against.
			if runtime.loader.movie_name.to_lower() != movie.to_lower():
				departed += 1
			else:
				var want := _expected(runtime, runtime.loader.resolve_label(room, false))
				if nof != "" and nof != want:
					wrong.append("%s: got %s want %s" % [room, nof, want])
			if seen.has(nof):
				shared += 1
			seen[nof] = true

		_check("%s: every room has a nof" % movie, empty.is_empty(),
			"%d without: %s" % [empty.size(), str(empty.slice(0, 6))])
		_check("%s: nof is sprite 1's member, in sprite 1's cast" % movie, wrong.is_empty(),
			"%d wrong: %s" % [wrong.size(), str(wrong.slice(0, 4))])
		print("      %d rooms, %d sharing a key with an earlier room, %d left for a meeting" % [
			rooms.size(), shared, departed])

	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
