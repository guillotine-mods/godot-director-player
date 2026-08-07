extends SceneTree
## The score of one movie, replayed from its own container.
##
##   godot --headless --script tools/director_frames.gd -- --file DAY1.DIR
##   godot --headless --script tools/director_frames.gd -- --file DAY1.DIR --frame 40
##   godot --headless --script tools/director_frames.gd -- --file DAY1.DIR --label shore2
##   godot --headless --script tools/director_frames.gd -- --all
##
## One movie by default. `--all` sweeps the corpus and takes a while, so it is
## opt-in: a sweep that runs because an argument failed to parse is
## indistinguishable from a hang.
##
## What this asserts is that the score replays at all and yields sprites, labels
## and a frame count. Whether it agrees with the exported `frames.json` is a
## separate comparison and belongs in its own tool, because the export is the
## port's input and agreeing with it proves the reader, never fidelity.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	if Args.flag(args, "all"):
		quit(_sweep(paths))
		return

	var wanted := Args.text(args, "file", paths.boot_movie)
	var path = paths.resolve(wanted)
	if path == "":
		print("no such container under %s: %s" % [paths.root, wanted])
		quit(1)
		return

	var f := ContainerFile.new()
	if not f.open(path):
		print("%s: %s" % [path, f.error])
		quit(1)
		return

	var vwsc: Array = f.ids_of("VWSC")
	if vwsc.is_empty():
		print("%s has no VWSC: it is a cast, not a playable movie" % path)
		f.close()
		quit(0)
		return

	var started := Time.get_ticks_usec()
	var score := Score.new()
	var ok := score.parse(f.read_chunk(vwsc[0]))
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	if not ok:
		print("%s: %s" % [path, score.error])
		f.close()
		quit(1)
		return

	var labels := Labels.new()
	var vwlb: Array = f.ids_of("VWLB")
	if not vwlb.is_empty():
		labels.parse(f.read_chunk(vwlb[0]))

	print("%s  %s" % [path, "XFIR" if not f.big_endian else "RIFX"])
	print("frames     : %d  (version %d, %d channels, %d displayed)" % [
		score.frame_count, score.frames_version, score.channels, score.channels_displayed,
	])
	print("parsed in  : %.0f ms" % elapsed)
	print("markers    : %d, labels %d" % [labels.markers.size(), labels.labels.size()])
	print("intervals  : %d" % score.intervals().size())

	var index := Args.number(args, "frame", -1)
	var label := Args.text(args, "label")
	if label != "":
		index = int(labels.labels.get(label.to_lower(), -1))
		if index < 0:
			print("no label %s; have: %s" % [label, ", ".join(labels.labels.keys())])
			f.close()
			quit(1)
			return
		print("label %s is frame %d" % [label, index])
	if index < 0:
		print("")
		print("first markers:")
		for marker in labels.markers.slice(0, 12):
			print("  %6d  %s" % [marker["frame"], marker["name"]])
		f.close()
		quit(0)
		return

	if index >= score.frame_count:
		print("frame %d is past the end (%d frames)" % [index, score.frame_count])
		f.close()
		quit(1)
		return

	var seek_started := Time.get_ticks_usec()
	var frame: Dictionary = score.frame(index)
	print("seek       : %.1f ms" % ((Time.get_ticks_usec() - seek_started) / 1000.0))
	print("")
	# The raw tempo cell and its operand, not a resolved rate. `director_score.gd`
	# used to publish an `fps` it had carried forward from a hardcoded 15, so this
	# line reported 15 for every movie that never writes a tempo; resolving the
	# cell needs the movie's file version and belongs to `director_frame_clock.gd`,
	# which is what `tools/movie_tempo.gd` checks. Printing the byte is what a
	# dump of one frame can honestly say.
	print("frame %d  (%s)  tempo %d/%d  script %s%s%s" % [
		index, labels.marker_at(index), int(frame["tempo"]), int(frame["tempo_cue"]),
		str(frame["frame_script"]),
		"  wait-click" if frame["wait_click"] else "",
		("  delay %dms" % frame["delay_ms"]) if int(frame["delay_ms"]) > 0 else "",
	])
	print("  ch  lib:member   loc          size       ink  flags")
	for sprite in frame["sprites"]:
		print("  %3d  %3d:%-6d  (%4d,%4d)  %4dx%-4d  %3d  %s%s" % [
			sprite["channel"], sprite["cast_lib"], sprite["cast_id"],
			sprite["loc_h"], sprite["loc_v"], sprite["width"], sprite["height"],
			sprite["ink"],
			"stretch " if sprite["stretch"] else "",
			"trails" if sprite["trails"] else "",
		])
	f.close()
	quit(0)


func _sweep(paths) -> int:
	var h := Harness.new()
	var movies := 0
	var total_frames := 0
	var total_sprites := 0
	var total_markers := 0
	var failures: Array[String] = []
	var started := Time.get_ticks_usec()

	h.begin("every movie's score replays")
	for path in _find(paths.root):
		var f := ContainerFile.new()
		if not f.open(path):
			failures.append("%s: %s" % [path.get_file(), f.error])
			continue
		var vwsc: Array = f.ids_of("VWSC")
		if vwsc.is_empty():
			f.close()
			continue
		movies += 1
		var score := Score.new()
		if not score.parse(f.read_chunk(vwsc[0])):
			failures.append("%s: %s" % [path.get_file(), score.error])
			f.close()
			continue
		total_frames += score.frame_count
		for i in score.frame_count:
			total_sprites += score.frame(i)["sprites"].size()
		var vwlb: Array = f.ids_of("VWLB")
		if not vwlb.is_empty():
			var labels := Labels.new()
			if labels.parse(f.read_chunk(vwlb[0])):
				total_markers += labels.markers.size()
		f.close()
	h.check("all %d score(s) replayed" % movies, failures.is_empty(),
		"" if failures.is_empty() else "%d failed" % failures.size())
	for line in failures.slice(0, 10):
		print("     %s" % line)
	h.check("frames were produced", total_frames > 0, "%d frames" % total_frames)
	h.check("sprites were produced", total_sprites > 0, "%d sprite records" % total_sprites)
	h.check("markers were produced", total_markers > 0, "%d markers" % total_markers)
	h.complete("every movie's score replays")

	print("")
	print("movies     : %d" % movies)
	print("frames     : %d" % total_frames)
	print("sprites    : %d" % total_sprites)
	print("markers    : %d" % total_markers)
	print("elapsed    : %.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	return h.finish("the score layer reads this game's own files")


func _find(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, out)
	out.sort()
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
