extends SceneTree
## What rate does a movie play at before its score says anything?
##
##   godot --headless --script tools/movie_tempo.gd
##   godot --headless --script tools/movie_tempo.gd -- --verbose
##
## `DIRECTOR_ENGINE.md` §9.1 says "with no tempo, the previous rate carries
## forward" and never says what the *first* rate is. It is the movie's own
## default, in its config chunk, and a port that assumes one instead runs every
## movie that never writes a tempo at the wrong speed for its whole length --
## silently, because nothing errors and the movie plays.
##
## This exists because that is exactly what happened: the engine assumed 15 fps,
## and a second title's rooms mostly want 8. Nearly twice too fast, and the only
## symptom is that it feels wrong.
##
## The gap it closes is also the one worth reporting on: a movie that writes no
## tempo *and* states no default is running on the engine's guess, and this says
## how many of those there are.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")

## Anything outside this is not a frame rate, whatever else the field may be.
const PLAUSIBLE_MAX := 120


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var files: Array[String] = []
	_walk(paths.root, files)
	files.sort()

	var stated: Dictionary = {}
	var implausible: Array[String] = []
	var silent: Array[String] = []
	var with_config := 0

	for path in files:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var config = Config.new()
		var has_config: bool = config.read(f)
		var tempo := int(config.default_tempo) if has_config else 0
		if has_config:
			with_config += 1
			stated[tempo] = int(stated.get(tempo, 0)) + 1
			if tempo > PLAUSIBLE_MAX:
				implausible.append("%s states %d" % [path.get_file(), tempo])

		# A movie that states no default *and* never writes a tempo runs on the
		# engine's assumption for its whole length, which is the case worth
		# naming rather than counting.
		if tempo <= 0:
			var ids: Array = f.ids_of("VWSC")
			if not ids.is_empty():
				var score := Score.new()
				if score.parse(f.read_chunk(int(ids[0]))):
					var writes := false
					for i in score.frame_count:
						if int(score.frame(i).get("tempo", 0)) != 0:
							writes = true
							break
					if not writes:
						silent.append(path.get_file())
		f.close()

	print("%s" % paths.root)
	print("  containers with a config : %d of %d" % [with_config, files.size()])
	var keys: Array = stated.keys()
	keys.sort()
	print("  stated default tempo     : %s" % JSON.stringify(stated))
	print("  states none and never writes one: %d" % silent.size())
	if not silent.is_empty():
		var show: int = silent.size() if Args.flag(args, "verbose") else mini(6, silent.size())
		for i in show:
			print("      %s" % silent[i])
		if show < silent.size():
			print("      ... and %d more (pass --verbose)" % (silent.size() - show))

	h.begin("every stated default tempo is a plausible frame rate")
	h.check("at least one container was read", not files.is_empty(), paths.root)
	# The field is settled by distribution, not by a spec, so the assertion is
	# that it stays shaped like a frame rate. A value above 120 would mean the
	# offset is wrong for some file and the reading needs revisiting.
	h.check("no movie states a rate above %d" % PLAUSIBLE_MAX,
		implausible.is_empty(), ", ".join(implausible.slice(0, 4)))
	h.complete("every stated default tempo is a plausible frame rate")
	quit(h.finish("the rate a movie starts at"))
