extends SceneTree
## What the score actually asks to be drawn, by cast type — and which of those
## sprites Director would colourise.
##
##   godot --headless --script tools/draw_survey.gd -- --file PIP2DATA/DAY1.dir
##   godot --headless --script tools/draw_survey.gd -- --all
##
## Two questions, and they turn out to be one.
##
## 1. `scenes/director_preview.gd:_texture_for` returns null for every member
##    whose type is not 1, so anything that is not a bitmap is simply absent from
##    the stage. This counts how much of the score that is, per type, which is
##    the only honest way to decide whether text rendering is worth building.
## 2. `director/director_score.gd` decodes `fore_color`/`back_color` and nothing
##    consumes them (DIRECTOR_ENGINE.md 2.3, gap 16.4). This counts the sprites
##    whose colours are non-default *and* whose ink admits applyColor, split by
##    the member type they name — because a colourisation pass that only handles
##    bitmaps may be answering almost none of them.
##
## `ink_survey.gd` cannot answer either: it never opens a cast, so it cannot say
## what type a sprite record points at.
##
## Title-agnostic. Nothing here knows what game is loaded.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Cast := preload("res://director/director_cast.gd")
const Ink := preload("res://director/director_ink.gd")

## Director's 8-bit convention is inverted: white is palette index 0 and black is
## 255 (DIRECTOR_ENGINE.md 2.2). So the *default* foreColor is 255 and the
## default backColor is 0, and "non-default" is anything else.
const DEFAULT_FORE := 255
const DEFAULT_BACK := 0

## The inks whose applyColor switch can fire at all (2.3). The reference states
## the switch as two clauses — "fore != black or back != white" for one group and
## "not (fore == black and back == white)" for the other — which are the same
## condition written two ways, so one test serves both groups and only the ink
## membership actually differs from "never".
const APPLY_COLOR_INKS := [
	Ink.MATTE, Ink.MASK, Ink.COPY, Ink.NOT_COPY,
	Ink.TRANSPARENT, Ink.NOT_TRANSPARENT, Ink.BACKGND_TRANS,
	Ink.GHOST, Ink.NOT_GHOST,
]


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


func _bump(into: Dictionary, key: String, by: int = 1) -> void:
	into[key] = int(into.get(key, 0)) + by


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var targets: Array[String] = []
	if Args.flag(args, "all"):
		_walk(paths.root, targets)
		targets.sort()
	else:
		var one: String = paths.resolve(Args.text(args, "file", paths.boot_movie))
		if one == "":
			print("no such container")
			quit(1)
			return
		targets.append(one)

	# sprite records, keyed by the type name of the member they name
	var drawn: Dictionary = {}
	# of those, the ones with non-default colours and an applyColor-capable ink
	var colourised: Dictionary = {}
	# every member in every cast this survey opened, by type name
	var members: Dictionary = {}
	# members of the non-bitmap drawing types, with a note of what they carry
	var text_members: Array[String] = []
	var shape_members: Array[String] = []
	var total := 0
	var movies := 0
	var seen_casts: Dictionary = {}

	for path in targets:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var vwsc: Array = f.ids_of("VWSC")
		if vwsc.is_empty():
			f.close()
			continue
		var score := Score.new()
		if not score.parse(f.read_chunk(int(vwsc[0]))):
			f.close()
			continue
		var table := CastTable.new()
		if not table.open(f, paths):
			table.close()
			f.close()
			continue
		movies += 1

		for i in score.frame_count:
			for sprite_value in score.frame(i).get("sprites", []):
				var sprite: Dictionary = sprite_value
				total += 1
				var m: Dictionary = table.get_member(
					int(sprite["cast_lib"]), int(sprite["cast_id"]))
				var type_name: String = (
					"<unresolved>" if m.is_empty()
					else str(m.get("type_name", "?")))
				_bump(drawn, type_name)
				var fore := int(sprite.get("fore_color", DEFAULT_FORE))
				var back := int(sprite.get("back_color", DEFAULT_BACK))
				if fore == DEFAULT_FORE and back == DEFAULT_BACK:
					continue
				if not APPLY_COLOR_INKS.has(int(sprite["ink"])):
					continue
				_bump(colourised, type_name)

		# The cast inventory, once per distinct library rather than once per
		# movie that links it: the shared cast is reachable from nearly every
		# movie and counting it each time inflates every total.
		for lib in table.cast_libs.keys():
			var cast = table.cast_for(int(lib))
			if cast == null:
				continue
			var key := "%s#%d" % [str(table.cast_libs[lib].get("resolved_path", "")),
				int(cast.cas_chunk_id)]
			if seen_casts.has(key):
				continue
			seen_casts[key] = true
			for number in cast.member_numbers():
				var m: Dictionary = cast.member(number)
				if m.is_empty():
					continue
				var type_code := int(m.get("type", 0))
				var type_name := str(m.get("type_name", "?"))
				_bump(members, type_name)
				if type_code == 3 or type_code == 12 or type_code == 7:
					var text := str(m.get("text", ""))
					text_members.append("%s %s %d '%s' %dx%d text=%d %s" % [
						key.get_file(), type_name, number, str(m.get("name", "")),
						int(m.get("width", 0)), int(m.get("height", 0)),
						text.length(), text.substr(0, 40).replace("\n", "\\n")])
				elif type_code == 8:
					shape_members.append("%s shape %d '%s' %dx%d filled=%s" % [
						key.get_file(), number, str(m.get("name", "")),
						int(m.get("width", 0)), int(m.get("height", 0)),
						str(m.get("filled", false))])
		table.close()
		f.close()

	print("%d movie(s), %d sprite records, %d distinct cast librar(ies)"
		% [movies, total, seen_casts.size()])
	print("")
	print("sprite records by the type of the member they name:")
	var keys: Array = drawn.keys()
	keys.sort()
	for k in keys:
		print("  %-14s %8d  %5.2f%%   colourisable %d" % [
			k, int(drawn[k]), 100.0 * float(drawn[k]) / maxf(total, 1),
			int(colourised.get(k, 0))])
	var colour_total := 0
	for k in colourised:
		colour_total += int(colourised[k])
	print("")
	print("total colourisable sprite records: %d (%.2f%%)"
		% [colour_total, 100.0 * float(colour_total) / maxf(total, 1)])
	print("")
	print("cast members by type:")
	var mkeys: Array = members.keys()
	mkeys.sort()
	for k in mkeys:
		print("  %-14s %6d" % [k, int(members[k])])

	if Args.flag(args, "list"):
		print("")
		print("text-ish members (%d):" % text_members.size())
		for line in text_members:
			print("  " + line)
		print("")
		print("shape members (%d):" % shape_members.size())
		for line in shape_members:
			print("  " + line)

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	h.complete("the survey ran")
	quit(h.finish("what the score draws, and what would colourise"))
