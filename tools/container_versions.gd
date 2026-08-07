extends SceneTree
## Which score format every container in a game uses, and which ones this engine
## can read.
##
##   godot --headless --script tools/container_versions.gd
##   godot --headless --script tools/container_versions.gd -- --verbose
##
## A Director title is not necessarily uniform. Piposh 1 ships `STRTGAME.dir`
## with 48-byte sprite records and 94 of its 97 room movies with 24-byte ones --
## two Director versions in one game, which is invisible until a movie fails to
## open and the symptom is "the music plays and the scene never changes".
##
## The sprite record size is the discriminator. 48 bytes is Director 5 and later;
## 24 is the older layout, with different field offsets, a different main-channel
## block and no cast-library field at all. `director_score.gd` reads the 48-byte
## form and refuses the other, so this reports the split rather than guessing at
## it.
##
## Two uses. Before a bulk conversion it says how much there is to convert; after
## one it says whether the conversion actually covered everything, which is the
## question a spot-check on a single file cannot answer.
##
## It reads whatever `director_game.cfg` points at, so it follows the configured
## game rather than naming one.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")


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

	var by_size: Dictionary = {}
	var unreadable: Array[String] = []
	var no_score := 0
	var scored := 0

	for path in files:
		var f := ContainerFile.new()
		if not f.open(path):
			unreadable.append("%s — %s" % [path.get_file(), f.error])
			continue
		var ids: Array = f.ids_of("VWSC")
		if ids.is_empty():
			# A cast file has no score, which is not a fault.
			no_score += 1
			f.close()
			continue
		scored += 1
		var score := Score.new()
		if score.parse(f.read_chunk(int(ids[0]))):
			var key := "%d-byte records" % score.sprite_record_size
			by_size[key] = int(by_size.get(key, 0)) + 1
		else:
			# The record size is reported in the error even when the parse is
			# refused, which is the whole point: an unreadable score still says
			# *why* it is unreadable.
			unreadable.append("%s — %s" % [path.get_file(), score.error])
		f.close()

	print("%s" % paths.root)
	print("  containers found : %d" % files.size())
	print("  with a score     : %d  (%d are cast-only)" % [scored, no_score])
	print("")
	var keys: Array = by_size.keys()
	keys.sort()
	for key in keys:
		print("  readable, %-18s %d" % [key + ":", int(by_size[key])])
	print("  unreadable        : %d" % unreadable.size())
	if not unreadable.is_empty():
		var show: int = unreadable.size() if Args.flag(args, "verbose") else mini(8, unreadable.size())
		for i in show:
			print("      %s" % unreadable[i])
		if show < unreadable.size():
			print("      ... and %d more (pass --verbose)" % (unreadable.size() - show))

	h.begin("every score in the configured game can be read")
	h.check("at least one container was found", not files.is_empty(), paths.root)
	h.check("every score parses", unreadable.is_empty(),
		"%d of %d unreadable" % [unreadable.size(), scored])
	h.complete("every score in the configured game can be read")
	quit(h.finish("score formats across the configured game"))
