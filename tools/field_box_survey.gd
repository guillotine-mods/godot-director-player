extends SceneTree
## What an expanding field's box would become under each candidate sizing rule.
##
##   godot --headless --audio-driver Dummy --path . --script tools/field_box_survey.gd
##   godot --headless --audio-driver Dummy --path . --script tools/field_box_survey.gd -- --roots piposh
##
## Written for `bugs.md` 80, to settle two questions with numbers rather than
## with an argument:
##
##   1. how many `adjust`/`limit` sprite records grow once the laid-out height is
##      pushed back onto the sprite, and by how much;
##   2. how many would *shrink* if the reference's literal `MIN(bbox, initialRect)`
##      starting box were adopted as the answer -- which is the regression
##      `9d1b23d2` fixed and the reason the entry says the two halves of §1.2
##      cannot land separately.
##
## The text laid out here is the member's **authored** STXT, which is what
## `Geometry.drawn_size` sees for a record that never reached `_effective`. A
## runtime write is measured by `tools/field_expands.gd` instead, which needs a
## live player.
##
## Not in `gate.sh`: it asserts nothing, it prints, and every number it prints is
## quoted in `sprite_geometry.gd:_field_size`'s docstring. Tracked rather than left
## under `tools/scratch/`, which is gitignored, for exactly that reason: a docstring
## citing a measurement nobody else can re-run is a number with no provenance, which
## is the failure `AGENTS.md` opens with.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Text := preload("res://director/director_text.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]

const BOX_NAMES := {0: "adjust", 1: "scroll", 2: "fixed", 3: "limit"}


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
	var roots: Array[String] = []
	var explicit := Args.text(args, "roots", "")
	if explicit != "":
		for part in explicit.split(",", false):
			roots.append(str(part).strip_edges())
	else:
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(sub))
	roots.sort()

	for root_name in roots:
		var paths := Paths.new()
		if not paths.load_config(Paths.CONFIG_PATH, root_name):
			# A root whose boot movie the config does not name still has
			# containers worth counting; `load_config` fills `root` before it
			# refuses, so only a completely unresolvable one is skipped.
			if paths.root == "":
				continue
		var targets: Array[String] = []
		_walk(paths.root, targets)
		targets.sort()
		var stats := {
			"records": 0, "grew": 0, "grew_px": 0, "worst": 0, "worst_name": "",
			"min_shrinks_w": 0, "min_shrinks_h": 0, "members": {},
		}
		for path in targets:
			_measure(path, paths, stats)
		print("%-18s %6d adjust/limit records  grew %5d (max +%dpx on %s)  MIN would shrink w %5d h %5d"
			% [root_name, int(stats["records"]), int(stats["grew"]),
				int(stats["worst"]), str(stats["worst_name"]),
				int(stats["min_shrinks_w"]), int(stats["min_shrinks_h"])])
		var names: Array = (stats["members"] as Dictionary).keys()
		names.sort()
		for name in names:
			print("      %s" % str(name))
	quit(0)


func _measure(path: String, paths, stats: Dictionary) -> void:
	var f := ContainerFile.new()
	if not f.open(path):
		return
	var vwsc: Array = f.ids_of("VWSC")
	if vwsc.is_empty():
		f.close()
		return
	var score := Score.new()
	if not score.parse(f.read_chunk(int(vwsc[0]))):
		f.close()
		return
	var table := CastTable.new()
	if not table.open(f, paths):
		table.close()
		f.close()
		return
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var member: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if int(member.get("type", 0)) != 3:
				continue
			var box := int(member.get("text_type", 0))
			if box == 1 or box == 2:
				continue
			var natural := Vector2(
				float(member.get("width", 0)), float(member.get("height", 0)))
			if natural.x <= 0.0 or natural.y <= 0.0:
				continue
			stats["records"] = int(stats["records"]) + 1
			var style: Dictionary = Text.style_of(member)
			var text := str(member.get("text", ""))
			var need := Text.laid_out_height(natural.x, text, style)
			if need > natural.y:
				stats["grew"] = int(stats["grew"]) + 1
				var by := int(need - natural.y)
				if by > int(stats["worst"]):
					stats["worst"] = by
					stats["worst_name"] = "%s %s (%s)" % [
						path.get_file(), str(member.get("name", "")), BOX_NAMES.get(box, box)]
				(stats["members"] as Dictionary)["%s %s %s %dx%d -> %dx%d" % [
					path.get_file(), str(member.get("name", "")), BOX_NAMES.get(box, box),
					int(natural.x), int(natural.y), int(natural.x), int(maxf(natural.y, need))]] = true
			# The second question: what `MIN(bbox, initialRect)` would cost if the
			# reference's starting box were taken as the answer. Only `adjust` has
			# that MIN -- `limit` leaves the bbox alone -- so only `adjust` is counted.
			if box != 0:
				continue
			var stated := Vector2(float(sprite["width"]), float(sprite["height"]))
			if stated.x <= 0.0 or stated.y <= 0.0:
				continue
			# Narrower than the member: the text would be re-wrapped, and a centred
			# field would be centred in the wrong box. This is `GlobalMoney`.
			if stated.x < natural.x:
				stats["min_shrinks_w"] = int(stats["min_shrinks_w"]) + 1
			# Shorter than the member *and* still tall enough for the text, so the
			# only difference is a shorter box -- no clipping either way. This is the
			# cost of flooring at the member's rect instead.
			var floor_h := minf(stated.y, natural.y)
			if floor_h >= need and floor_h < maxf(natural.y, need):
				stats["min_shrinks_h"] = int(stats["min_shrinks_h"]) + 1
	table.close()
	f.close()
