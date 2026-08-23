extends SceneTree
## How much of the corpus a text member's scrollbar Hole would cover, per §4.2.
##
##   godot --headless --audio-driver Dummy --path . --script tools/hole_survey.gd
##   godot --headless --audio-driver Dummy --path . --script tools/hole_survey.gd -- --roots piposh2
##
##   --roots A,B    bare root names under games/ or test-games/ (default: all eight)
##   --sites N      print the first N distinct (movie, channel, member) sites
##
## `isMouseIn` answers **three** things and only one producer of the third exists:
## `castmember/text.cpp:TextCastMember::isWithin` returns `kCollisionHole` when the
## point is inside the sprite's rect *and* inside the text widget's scrollbar. A
## Hole aborts the entire descent (`score.cpp:getSpriteIDFromPos` and its two
## siblings `break` on it), so it is not "this sprite is transparent here" -- it is
## "nothing under this point is clickable at all".
##
## ## What this counts, and why the strip is the interesting number
##
## The strip is `graphics/macgui/mactext.cpp:MacText::isInScrollBar`, which is a
## pure rectangle over the widget's own dims: the rightmost `bRight` columns, minus
## the top `bTop` rows and the bottom `bBottom` rows, split at half height into the
## up and the down arrow. Both arrows are Holes; everything else, including the two
## corners it excludes, is not. On a border nothing has written to, all three
## offsets fall back to `kBorderWidth` = 17 (`graphics/macgui/macwindow.h:48`),
## and that is the number counted here.
##
## **The count below is therefore of the literal reading, and the literal reading
## is settled as wrong** -- see `Interaction.has_scrollbar`. A widget built with
## `scrollBar = false` does not have *no* offsets, it has offsets `0,0,0,0`
## (`MacText::setScrollBar` -> `MacWindowBorder::disableBorder` -> the 3x3
## nine-patch whose padding parses to zero), so its strip is the empty interval
## and it cannot produce a Hole at any size. What this survey measures is the size
## of the hole that reading *would* have opened, which is why the number is worth
## having and why nothing in the engine is driven from it.
##
## So a sprite only has a Hole at all when its **drawn** rect is wider than 17 and
## taller than 34, and that is what this counts. A field 120x19 -- which is what
## every save-slot and score box in these titles is -- has `top + 17 >= bottom - 17`
## and can never produce one, whatever the pointer does. The number that decides
## how wide to build the rule is therefore not "how many text sprites are there"
## but "how many are big enough for the strip to be non-empty", broken down by the
## member's box type, because only `scroll` draws a scrollbar there.
##
## The drawn rect is `sprite_geometry.drawn_size`, which for a text member already
## reproduces `castmember/text.cpp:createWidget`'s box arithmetic -- so the rect
## measured here is the widget's dims, which is what `isInScrollBar` reads, rather
## than the score's stored rect. Cited at ScummVM 805f259a.
##
## Title-agnostic: it names no game and discovers its roots by listing them.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]

const BOX_NAMES := {0: "adjust", 1: "scroll", 2: "fixed", 3: "limit"}

## The two cast types `TextCastMember::isWithin` covers. `ButtonCastMember`
## derives from `TextCastMember` in the reference and inherits the override, so a
## button member answers the same three-way test a field does.
const TEXT_TYPES := [3, 7]


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


var _sites_left := 0
var _site_lines: Array[String] = []


func _init() -> void:
	var args := Args.parse()
	_sites_left = Args.number(args, "sites", 24)
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

	print("strip: right %d cols, minus top %d and bottom %d rows (mactext.cpp:isInScrollBar)"
		% [Interaction.SCROLLBAR_BORDER, Interaction.SCROLLBAR_BORDER,
			Interaction.SCROLLBAR_BORDER])
	print("")
	print("%-20s %9s %9s %9s   %s" % [
		"root", "records", "text", "with-strip", "with-strip by box type"])
	var grand := {"records": 0, "text": 0, "strip": 0}
	var by_box_all: Dictionary = {}
	for root_name in roots:
		var paths := Paths.new()
		if not paths.load_config(Paths.CONFIG_PATH, root_name):
			if paths.root == "":
				continue
		var targets: Array[String] = []
		_walk(paths.root, targets)
		targets.sort()
		var stats := {"records": 0, "text": 0, "strip": 0, "by_box": {}, "members": {}}
		for path in targets:
			_measure(path, paths, stats)
		var by_box: Dictionary = stats["by_box"]
		var keys: Array = by_box.keys()
		keys.sort()
		var detail := ""
		for k in keys:
			detail += "%s:%d  " % [BOX_NAMES.get(int(k), "box%d" % int(k)), int(by_box[k])]
			by_box_all[k] = int(by_box_all.get(k, 0)) + int(by_box[k])
		print("%-20s %9d %9d %9d   %s" % [
			root_name, int(stats["records"]), int(stats["text"]), int(stats["strip"]),
			detail if detail != "" else "-"])
		grand["records"] = int(grand["records"]) + int(stats["records"])
		grand["text"] = int(grand["text"]) + int(stats["text"])
		grand["strip"] = int(grand["strip"]) + int(stats["strip"])
		var mkeys: Array = (stats["members"] as Dictionary).keys()
		mkeys.sort()
		var mline := ""
		for k in mkeys:
			var slot: Dictionary = (stats["members"] as Dictionary)[k]
			mline += "%s:%d(%d big)  " % [
				BOX_NAMES.get(int(k), "box%d" % int(k)),
				int(slot["all"]), int(slot["big"])]
		print("%-20s %9s %9s %9s   members by box type: %s" % [
			"", "", "", "", mline if mline != "" else "-"])
	var all_keys: Array = by_box_all.keys()
	all_keys.sort()
	var all_detail := ""
	for k in all_keys:
		all_detail += "%s:%d  " % [BOX_NAMES.get(int(k), "box%d" % int(k)), int(by_box_all[k])]
	print("%-20s %9d %9d %9d   %s" % [
		"ALL", int(grand["records"]), int(grand["text"]), int(grand["strip"]),
		all_detail if all_detail != "" else "-"])
	print("")
	print("sites (movie, channel, member, drawn size, box type):")
	if _site_lines.is_empty():
		print("  none")
	for line in _site_lines:
		print(line)
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
	table.open(f, paths)
	var seen: Dictionary = {}
	# The member census, kept beside the record census because they answer
	# different questions and the second cannot be derived from the first: a box
	# type with no member anywhere is a mechanism this corpus cannot exercise at
	# all, while a box type with members but no big-enough sprite record is one it
	# places too small to matter. Only the first is "nothing to verify against".
	var members: Dictionary = stats["members"]
	for lib in table.cast_libs.keys():
		var cast_lib = table.cast_for(int(lib))
		if cast_lib == null:
			continue
		for i in int(cast_lib.member_count):
			var m: Dictionary = table.get_member(int(lib), int(cast_lib.min_member) + i)
			if m.is_empty() or not TEXT_TYPES.has(int(m.get("type", 0))):
				continue
			var mb := int(m.get("text_type", 0))
			var big := int(m.get("width", 0)) > 17 and int(m.get("height", 0)) > 34
			var slot: Dictionary = members.get(mb, {"all": 0, "big": 0})
			slot["all"] = int(slot["all"]) + 1
			if big:
				slot["big"] = int(slot["big"]) + 1
			members[mb] = slot
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			stats["records"] = int(stats["records"]) + 1
			var m: Dictionary = table.get_member(
				int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0)))
			if m.is_empty() or not TEXT_TYPES.has(int(m.get("type", 0))):
				continue
			stats["text"] = int(stats["text"]) + 1
			var drawn := Geometry.drawn_size(sprite, m)
			if not Interaction.scrollbar_strip_exists(drawn):
				continue
			stats["strip"] = int(stats["strip"]) + 1
			var box := int(m.get("text_type", 0))
			var by_box: Dictionary = stats["by_box"]
			by_box[box] = int(by_box.get(box, 0)) + 1
			var key := "%s|%s|%d:%d" % [path.get_file(), str(sprite.get("channel", "?")),
				int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0))]
			if seen.has(key) or _sites_left <= 0:
				continue
			seen[key] = true
			_sites_left -= 1
			_site_lines.append("  %-24s ch %-3s %d:%-4d %s  %dx%d  %s" % [
				path.get_file(), str(sprite.get("channel", "?")),
				int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0)),
				str(m.get("name", "")), int(drawn.x), int(drawn.y),
				BOX_NAMES.get(box, "box%d" % box)])
	table.close()
	f.close()
