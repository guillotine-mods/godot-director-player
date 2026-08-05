extends SceneTree
## The cursor over a hotspot must be the one the original assigns to its channel.
##
##   godot --headless --script tools/cursors.gd
##
## `MASTER/External/MovieScript 13 - cursor funk.ls` gives channel 2 the walking
## legs, 7 to 9 the magnifier, 10 to 13 the exit arrows and 14 the target. That
## handler is the only place the mapping exists; nothing here restates it, so a
## channel changing hands in the original shows up as a failure rather than as two
## tables quietly disagreeing.
##
## Asserts what the player sees, not that a setter and a getter agree. A channel
## can hold the right member pair and still show nothing if the pair does not
## compose — which is what happened while the 1-bit members decoded as 8-bit and
## `wlkcur1` was 5x6 pixels of colour noise. So the image is composed and checked
## for actual ink.

var _fails := 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["ok  " if ok else "FAIL", name, ("  (%s)" % detail) if detail != "" else ""])


func _member_name(host: Object, movie: String, number: int) -> String:
	var by_number: Variant = host.member_names.get(movie.to_lower(), {})
	if typeof(by_number) != TYPE_DICTIONARY:
		return ""
	return str((by_number as Dictionary).get(number, ""))


func _has_ink(image: Image) -> bool:
	## An all-transparent composition would pass every geometry check and draw
	## nothing, which is the failure this whole harness exists to catch.
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false


func _initialize() -> void:
	var settings: Object = root.get_node("AppSettings")
	settings.use_lingo_frames = true
	settings.use_lingo_clicks = true
	root.get_node("GameState").new_game()

	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	runtime.boot()

	# The movies cursorfunk's own gate covers, minus NIGHT1, whose cursor members
	# have no local chunk dump and so are still the broken export.
	for movie in ["DAY1", "HOTEL1", "SEA1", "AIR1"]:
		runtime.goto_movie(movie, null, {})
		var host: Object = runtime.lingo.host

		var assigned: Dictionary = {}
		for number in runtime.channels.keys():
			var entry: SpriteChannel = runtime.channels[number]
			if typeof(entry.cursor) == TYPE_ARRAY and (entry.cursor as Array).size() == 2:
				assigned[number] = entry.cursor
		_check("%s: cursorfunk assigned channels" % movie, not assigned.is_empty(),
			"%d channels" % assigned.size())

		# Channel 2 is the floor in every movie the handler covers, so it is the one
		# assignment that can be named without restating the mapping.
		var floor_pair: Variant = assigned.get(2, null)
		var floor_named := ""
		if typeof(floor_pair) == TYPE_ARRAY and (floor_pair as Array).size() == 2:
			floor_named = _member_name(host, movie, int((floor_pair as Array)[0]))
		_check("%s: channel 2 is the walk cursor" % movie,
			floor_named.begins_with("wlkcur"), "got %s" % (floor_named if floor_named != "" else "<none>"))

		# Every assigned pair must compose into a visible image, and must be the
		# member the original named. "Has ink" alone is not enough: resolving the
		# pair against the channel's own cast library instead of the movie's found
		# island2's members 10 and 11, a 640x124 piece of scenery, and that passed an
		# ink check comfortably. The name is the invariant; the size is the tell.
		var blank: Array = []
		var unresolved: Array = []
		var misnamed: Array = []
		var oversized: Array = []
		for number in assigned.keys():
			var pair: Array = assigned[number]
			var composed: Dictionary = runtime.loader.cursor_image(
				runtime.CURSOR_CAST_LIB, int(pair[0]), int(pair[1]))
			if composed.is_empty():
				unresolved.append("ch%d %s" % [number, str(pair)])
				continue
			var named := _member_name(host, movie, int(pair[0]))
			if not named.ends_with("cur1") and not named.begins_with("hand") \
					and not named.begins_with("magni"):
				misnamed.append("ch%d -> %s" % [number, named if named != "" else "<unnamed>"])
			var image: Image = composed.image
			if image.get_width() > 32 or image.get_height() > 32:
				oversized.append("ch%d %s is %dx%d" % [
					number, named, image.get_width(), image.get_height()])
			if not _has_ink(image):
				blank.append("ch%d %s" % [number, named])
		_check("%s: every pair resolves to an image" % movie, unresolved.is_empty(),
			", ".join(PackedStringArray(unresolved)))
		_check("%s: every pair is a named cursor member" % movie, misnamed.is_empty(),
			", ".join(PackedStringArray(misnamed)))
		_check("%s: no cursor is scenery-sized" % movie, oversized.is_empty(),
			", ".join(PackedStringArray(oversized)))
		_check("%s: no cursor composes to nothing" % movie, blank.is_empty(),
			", ".join(PackedStringArray(blank)))

		# And the arbitration must actually return one somewhere on the stage. The
		# floor sprite is the broadest target, so its own centre is the fair probe.
		var floor_entry: Variant = runtime.channels.get(2, null)
		if floor_entry != null and not (floor_entry as SpriteChannel).is_empty():
			var rect: Rect2 = runtime.sprite_stage_rect((floor_entry as SpriteChannel).sprite)
			var found: Dictionary = runtime.cursor_at(rect.get_center())
			_check("%s: cursor_at finds a cursor on the floor" % movie,
				not found.is_empty(), "at %s" % str(rect.get_center()))
			# Through the real path, not a locally composed copy. The checks above
			# resolve the pair themselves, so they cannot see `cursor_at` picking the
			# wrong cast library — which it did, returning island2's 640x124 scenery
			# for DAY1's floor while every one of them still passed.
			if not found.is_empty():
				var got: Image = found.image
				_check("%s: the floor cursor is cursor-sized" % movie,
					got.get_width() <= 32 and got.get_height() <= 32,
					"%dx%d" % [got.get_width(), got.get_height()])

		# The negative half. An arbitration that answered everywhere would pass every
		# check above while telling the player nothing, so somewhere off the stage
		# has to come back empty.
		var nowhere: Dictionary = runtime.cursor_at(Vector2(-4000, -4000))
		_check("%s: no cursor far off the stage" % movie, nowhere.is_empty())

	print("")
	if _fails > 0:
		print("FAILED: %d" % _fails)
		quit(1)
		return
	print("PASS")
	quit(0)
