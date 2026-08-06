extends SceneTree
## Every Director container under the game root opens and indexes cleanly.
##
##   godot --headless --script tools/director_containers.gd
##
## This is the first rung of reading the game from its own files instead of from
## the exported render_model, so it asserts only what the container layer owes
## everything above it: the byte order is recognised, the memory map is where
## `imap` said, and no chunk addresses payload outside the file.
##
## The interesting case is byte order. 83 of the containers are big-endian
## `RIFX` and 3 are little-endian `XFIR`, and the three are `strtgame.dir`,
## `MASTER.CST` and `HEZSAVE.DIR` — the boot movie, the shared cast holding the
## globals and the inventory HUD, and save/load. Any of those failing to open is
## a game that does not start, so the boot movie is asserted separately rather
## than being averaged into a corpus-wide count.

const Harness := preload("res://tools/lib/harness.gd")
## Preloaded rather than reached by `class_name`: a headless `--script` run
## resolves global classes out of `.godot/global_script_class_cache.cfg`, which
## only lists what the editor has already scanned, so a class added since the
## last editor session is "not declared in the current scope" in a file nobody
## touched. Preload has no such dependency. Named apart from the classes
## themselves so these consts cannot shadow the globals once they are registered.
const ContainerFile := preload("res://director/director_file.gd")
const Paths := preload("res://director/director_paths.gd")


func _init() -> void:
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	print("root       : %s" % paths.root)
	print("boot movie : %s" % paths.boot_movie)
	print("")

	var containers := _find_containers(paths.root)
	h.begin("the game root holds Director containers")
	h.check(
		"containers found under the root",
		containers.size() > 0,
		"%d file(s)" % containers.size(),
	)
	h.complete("the game root holds Director containers")
	if containers.is_empty():
		quit(h.finish("nothing to read"))
		return

	var by_order := {"RIFX": 0, "XFIR": 0}
	var census := {}
	var failures: Array[String] = []
	var scripted := 0

	h.begin("every container opens and indexes")
	for path in containers:
		var f := DirectorFile.new()
		if not f.open(path):
			failures.append("%s: %s" % [path.get_file(), f.error])
			continue
		var order := "RIFX" if f.big_endian else "XFIR"
		by_order[order] += 1
		if f.codec != "MV93":
			failures.append("%s: unexpected codec %s" % [path.get_file(), f.codec])
		var bad := f.out_of_bounds()
		if not bad.is_empty():
			failures.append(
				"%s: %d chunk(s) address payload past the end (first id %d)"
				% [path.get_file(), bad.size(), bad[0]]
			)
		for tag in f.census():
			census[tag] = int(census.get(tag, 0)) + int(f.census()[tag])
		if f.ids_of("Lscr").size() > 0:
			scripted += 1
		f.close()
	h.check(
		"all %d container(s) opened and indexed" % containers.size(),
		failures.is_empty(),
		"" if failures.is_empty() else "%d failed" % failures.size(),
	)
	h.complete("every container opens and indexes")
	for line in failures:
		print("     %s" % line)

	# The boot movie is called out because averaging it into the corpus hides the
	# one failure that stops the game existing.
	h.begin("the boot movie opens")
	var boot := paths.boot_path()
	if h.check("boot movie resolves", boot != "", paths.boot_movie):
		var bf := DirectorFile.new()
		if h.check("boot movie opens", bf.open(boot), bf.error):
			h.check(
				"boot movie carries Lingo",
				bf.ids_of("Lscr").size() > 0,
				"%d Lscr, %s" % [bf.ids_of("Lscr").size(), "XFIR" if not bf.big_endian else "RIFX"],
			)
			bf.close()
	h.complete("the boot movie opens")

	print("")
	print("byte order : RIFX %d, XFIR %d" % [by_order["RIFX"], by_order["XFIR"]])
	print("with Lingo : %d of %d container(s)" % [scripted, containers.size()])
	print("chunks     :")
	var tags := census.keys()
	tags.sort_custom(func(a, b): return int(census[a]) > int(census[b]))
	for tag in tags:
		print("  %8d  %s" % [int(census[tag]), tag])

	quit(h.finish("the container layer reads this game's own files"))


func _find_containers(root: String) -> Array[String]:
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
