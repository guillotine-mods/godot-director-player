extends SceneTree
## Where does interpreting `on exitFrame` change what the player experiences?
##
## tools/lingo_frames.gd compares the frame path from a single start point and
## reported "identical" for all five movies, which was not enough: enabling the
## flag broke walk arrival and transitions. This sweeps the paths that missed,
## every walk hotspot in every room, and diffs the outcome with the interpreter
## off against on.
##
## For each case: enter the room, click the hotspot, run the walk to completion,
## and record where the player ended up. A difference is not automatically a bug,
## but every one has to be read before the flag can default on.
##
##   godot --headless --script tools/lingo_walk_diff.gd
##   godot --headless --script tools/lingo_walk_diff.gd -- DAY1

const TICKS_AFTER_CLICK := 260
const DELTA := 0.1
## Rooms per movie. Enough to cover the exits without walking the whole game.
const MAX_ROOMS := 14
const MAX_HOTSPOTS_PER_ROOM := 3


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var AppSettings: Node = root.get_node("AppSettings")
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).strip_edges() != "":
			only = str(arg).to_upper()
	var movies := ["DAY1", "NIGHT1", "HOTEL1"] if only == "" else [only]

	var cases: Array = []
	for movie in movies:
		cases.append_array(_walk_cases(movie))
	print("%d walk cases across %d movies\n" % [cases.size(), movies.size()])

	var same := 0
	var differ := 0
	# Severity matters: reaching a different room is a failure, reaching the same
	# room facing the other way is cosmetic, and not walking at all is a dead
	# hotspot.
	var facing_only := 0
	var wrong_room := 0
	var no_walk := 0
	var lines := PackedStringArray()
	for case in cases:
		AppSettings.use_lingo_frames = false
		AppSettings.use_lingo_clicks = false
		var off := _outcome(case)
		# The target configuration: both on. Clicks are the half that needs
		# walkonby, so testing frames alone hides exactly what matters here.
		AppSettings.use_lingo_frames = true
		AppSettings.use_lingo_clicks = true
		var on := _outcome(case)
		if off == on:
			same += 1
		else:
			differ += 1
			var off_room := off.split(" ")[0]
			var on_room := on.split(" ")[0]
			if on.contains("walked=n") and off.contains("walked=y"):
				no_walk += 1
			elif off_room != on_room:
				wrong_room += 1
			else:
				facing_only += 1
			var bucket := "facing"
			if on.contains("walked=n") and off.contains("walked=y"):
				bucket = "no-walk"
			elif off_room != on_room:
				bucket = "wrong-room"
			lines.append("  [%-10s] %s @%s ch%d: off=%s | on=%s" % [
				bucket, case.movie, case.room, case.channel, off, on])
	print("identical outcome: %d/%d" % [same, cases.size()])
	print("different outcome: %d" % differ)
	print("  same room, facing differs: %d" % facing_only)
	print("  different room:           %d" % wrong_room)
	print("  click no longer walks:    %d" % no_walk)
	for line in lines:
		print(line)
	quit(0)


func _walk_cases(movie: String) -> Array:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	var out: Array = []
	if runtime.boot() != OK or runtime.loader.load_movie(movie) != OK:
		return out
	var labels: Dictionary = runtime.loader.labels
	var rooms: Array = []
	for key in labels.keys():
		var name := str(key)
		# `*go` markers are the standing-in-a-room frames.
		if name.to_lower().ends_with("go"):
			rooms.append(name)
	rooms.sort()
	for room in rooms:
		if out.size() >= MAX_ROOMS * MAX_HOTSPOTS_PER_ROOM:
			break
		var frame_index := int(labels[room])
		runtime.frame_index = frame_index
		var found := 0
		for sprite in runtime.clickable_sprites(runtime.loader.get_frame(frame_index)):
			if found >= MAX_HOTSPOTS_PER_ROOM:
				break
			var on_click: Dictionary = (sprite as Dictionary).get("on_click", {})
			var nav: Variant = on_click.get("nav", null)
			if typeof(nav) != TYPE_DICTIONARY:
				continue
			if not str((nav as Dictionary).get("kind", "")).to_lower().begins_with("walk"):
				continue
			var rect: Rect2 = runtime.sprite_stage_rect(sprite)
			out.append({
				"movie": movie,
				"room": room,
				"channel": int((sprite as Dictionary).get("channel", 0)),
				"frame": frame_index,
				"point": rect.position + rect.size * 0.5,
			})
			found += 1
	return out


func _outcome(case: Dictionary) -> String:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK:
		return "boot-failed"
	if not runtime.goto_movie(str(case.movie), null, {"label": str(case.room)}):
		return "enter-failed"
	runtime.enter_frame(int(case.frame))
	runtime.perform_click(case.point)
	var walked: bool = runtime.puppet.is_walking()
	for _i in TICKS_AFTER_CLICK:
		runtime.tick(DELTA)
	return "%s@%s walked=%s facing=%s" % [
		runtime.loader.movie_name,
		runtime.label_near_frame(runtime.frame_index),
		"y" if walked else "n",
		str(runtime.puppet.facing),
	]
