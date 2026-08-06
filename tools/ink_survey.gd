extends SceneTree
## What the ink byte and the thickness byte actually hold, across the corpus.
##
##   godot --headless --script tools/ink_survey.gd -- --file PIP2DATA/EXODUS.DIR
##   godot --headless --script tools/ink_survey.gd -- --all
##
## The export cannot answer this: `frames.json` carries the ink but not the
## thickness byte or the blend amount, because nothing decoded them until now.
## This reads the containers.
##
## What it is for: deciding which inks are worth implementing properly and which
## can honestly fall through to Copy, and — for blend — what the stored amount
## actually ranges over, which decides how it maps to an alpha.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")

const INK_NAMES := {
	0: "Copy", 1: "Transparent", 2: "Reverse", 3: "Ghost", 4: "Not Copy",
	5: "Not Transp", 6: "Not Reverse", 7: "Not Ghost", 8: "Matte", 9: "Mask",
	32: "Blend", 33: "Add Pin", 34: "Add", 35: "Sub Pin",
	36: "BackgndTrans", 37: "Light", 38: "Sub", 39: "Dark",
}


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

	var inks: Dictionary = {}
	var blend_amounts: Dictionary = {}
	var flip_h := 0
	var flip_v := 0
	var has_blend := 0
	var tweened := 0
	var thickness: Dictionary = {}
	var total := 0
	var movies := 0

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
		movies += 1
		for i in score.frame_count:
			for sprite_value in score.frame(i).get("sprites", []):
				var sprite: Dictionary = sprite_value
				total += 1
				var ink := int(sprite["ink"])
				inks[ink] = int(inks.get(ink, 0)) + 1
				if bool(sprite.get("flip_h", false)):
					flip_h += 1
				if bool(sprite.get("flip_v", false)):
					flip_v += 1
				if bool(sprite.get("tweened", false)):
					tweened += 1
				var t := int(sprite.get("thickness", 0))
				thickness[t] = int(thickness.get(t, 0)) + 1
				if bool(sprite.get("has_blend", false)):
					has_blend += 1
				if ink == 32 or bool(sprite.get("has_blend", false)):
					var a := int(sprite.get("blend_amount", 0))
					blend_amounts[a] = int(blend_amounts.get(a, 0)) + 1
		f.close()

	print("%d movie(s), %d sprite records" % [movies, total])
	print("")
	print("ink:")
	var ink_keys: Array = inks.keys()
	ink_keys.sort()
	for k in ink_keys:
		print("  %3d  %-14s %8d  %5.2f%%" % [
			k, INK_NAMES.get(k, "?"), int(inks[k]), 100.0 * float(inks[k]) / maxf(total, 1)
		])
	print("")
	print("thickness byte:")
	print("  flip horizontal : %d" % flip_h)
	print("  flip vertical   : %d" % flip_v)
	print("  has-blend flag  : %d" % has_blend)
	print("  tweened         : %d" % tweened)
	var t_keys: Array = thickness.keys()
	t_keys.sort()
	var t_line := ""
	for k in t_keys:
		t_line += "%d:%d  " % [k, int(thickness[k])]
	print("  line thickness  : %s" % t_line)
	print("")
	print("blend amount, where blend applies:")
	var b_keys: Array = blend_amounts.keys()
	b_keys.sort()
	if b_keys.is_empty():
		print("  none")
	for k in b_keys:
		print("  %3d -> %d records" % [k, int(blend_amounts[k])])

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	h.complete("the survey ran")
	quit(h.finish("ink and thickness byte usage"))
