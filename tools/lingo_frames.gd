extends SceneTree
## Does the interpreted `on exitFrame` drive the score the same way the existing
## runner does?
##
## 2504 of the game's 3457 handlers are `on exitFrame`, so this is the bulk of the
## migration. Two things are measured:
##
##   coverage  how many frames have a frame script the interpreter can resolve,
##             and how many of those actually define exitFrame
##   agreement the frame path from a fixed start, ticked N times, with the
##             interpreter off versus on. Divergence is not automatically wrong
##             (the interpreter may be more faithful than the lifted nav) but it
##             is what has to be read before the flag can default on.
##
##   godot --headless --script tools/lingo_frames.gd

const TICKS := 220
const DELTA := 0.1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var AppSettings: Node = root.get_node("AppSettings")
	var cases := [
		{"movie": "DAY1", "label": "shore2"},
		{"movie": "NIGHT1", "label": "shore3"},
		{"movie": "HOTEL1", "label": "recept"},
		{"movie": "SEA1", "label": ""},
		{"movie": "AIR1", "label": ""},
	]

	print("%-9s %8s %9s %9s   %s" % ["movie", "frames", "resolved", "exitFrame", "coverage"])
	var total_frames := 0
	var total_resolved := 0
	var total_exit := 0
	for case in cases:
		var row := _coverage(str(case.movie))
		total_frames += int(row.frames)
		total_resolved += int(row.resolved)
		total_exit += int(row.exit)
		print("%-9s %8d %9d %9d   %5.1f%%" % [
			case.movie, row.frames, row.resolved, row.exit,
			0.0 if row.frames == 0 else float(row.exit) * 100.0 / float(row.frames)])
	print("\n%d frames, %d with a resolvable frame script, %d of those define exitFrame (%.1f%% of frames)" % [
		total_frames, total_resolved, total_exit,
		0.0 if total_frames == 0 else total_exit * 100.0 / total_frames])

	print("\nframe path, interpreter off vs on, %d ticks:" % TICKS)
	for case in cases:
		AppSettings.use_lingo_frames = false
		AppSettings.use_lingo_clicks = false
		var before := _path(str(case.movie), str(case.label))
		AppSettings.use_lingo_frames = true
		AppSettings.use_lingo_clicks = true
		var after := _path(str(case.movie), str(case.label))
		var same := 0
		for i in mini(before.size(), after.size()):
			if before[i] != after[i]:
				break
			same += 1
		print("  %-9s off: %3d distinct frames %s | on: %3d %s | identical for %d/%d ticks" % [
			case.movie, _distinct(before), _summary(before),
			_distinct(after), _summary(after), same, TICKS])
	quit(0)


func _coverage(movie: String) -> Dictionary:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK or runtime.loader.load_movie(movie) != OK:
		return {"frames": 0, "resolved": 0, "exit": 0}
	var engine: RefCounted = load("res://lingo/lingo_engine.gd").new(runtime)
	engine.prepare_movie(movie)
	var frames: Array = runtime.loader.frames
	var resolved := 0
	var with_exit := 0
	var cache := {}
	for index in frames.size():
		var member: Variant = (frames[index] as Dictionary).get("frame_script", null)
		if member == null:
			continue
		var key := int(member)
		if not cache.has(key):
			var script: Dictionary = engine.script_for_member(1, key)
			cache[key] = {
				"resolved": not script.is_empty(),
				"exit": engine._script_handles(script, "exitFrame"),
			}
		if bool((cache[key] as Dictionary)["resolved"]):
			resolved += 1
		if bool((cache[key] as Dictionary)["exit"]):
			with_exit += 1
	return {"frames": frames.size(), "resolved": resolved, "exit": with_exit}


func _path(movie: String, label: String) -> PackedInt32Array:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	var out := PackedInt32Array()
	if runtime.boot() != OK:
		return out
	var opts := {}
	if label != "":
		opts["label"] = label
	if not runtime.goto_movie(movie, null, opts):
		return out
	for _i in TICKS:
		runtime.tick(DELTA)
		out.append(runtime.frame_index)
	return out


func _distinct(path: PackedInt32Array) -> int:
	var seen := {}
	for value in path:
		seen[value] = true
	return seen.size()


func _summary(path: PackedInt32Array) -> String:
	if path.is_empty():
		return "(none)"
	return "%d..%d" % [path[0] + 1, path[path.size() - 1] + 1]
