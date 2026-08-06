extends SceneTree
## Where the preview puts a sprite, against where the export says it goes.
##
##   godot --headless --script tools/place_diff.gd -- --file PIP2DATA/EXODUS.DIR
##
## The score records and the member geometry are both proven exact
## (`tools/score_diff.gd`, `tools/member_diff.gd`), and the anchoring rule
## matches `render_model_loader._resolve_sprite_rects`. Every ingredient checks
## out and the picture is still wrong, so the remaining question is whether
## `loc - reg_offset` is the rule at all.
##
## The runtime never computes placement at draw time: it draws `x`/`y` straight
## out of `frames.json`, and only overrides them for sprites whose score rect
## disagrees with their member's size. If the exporter used more than one rule,
## reproducing it with a single formula is the mistake — and this reports the
## delta per sprite rather than a verdict, because the *shape* of the error says
## which rule is missing.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var path: String = paths.resolve(Args.text(args, "file", paths.boot_movie))
	if path == "":
		print("no such container")
		quit(1)
		return
	var movie := path.get_file().get_basename().to_upper()
	var export_path := "res://assets/render_model/%s/frames.json" % movie
	if not FileAccess.file_exists(export_path):
		print("no export: %s" % export_path)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("bad export")
		quit(1)
		return
	var frames: Array = (parsed as Dictionary).get("frames", [])

	var movie_file := ContainerFile.new()
	if not movie_file.open(path):
		print("%s: %s" % [path, movie_file.error])
		quit(1)
		return
	var table := CastTable.new()
	table.open(movie_file, paths)

	var compared := 0
	var exact := 0
	var deltas: Dictionary = {}
	var samples: Array[String] = []
	var stretched_wrong := 0
	var plain_wrong := 0
	var limit := Args.number(args, "frames", 120)

	h.begin("computed placement matches the export")
	for i in mini(limit, frames.size()):
		var frame: Dictionary = frames[i]
		for sprite_value in frame.get("sprites", []):
			var sprite: Dictionary = sprite_value
			if not sprite.has("x") or not sprite.has("y"):
				continue
			var m: Dictionary = table.get_member(
				int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0))
			)
			if m.is_empty() or int(m.get("width", 0)) <= 0:
				continue
			compared += 1
			# Hypothesis under test: a member from a linked cast is placed at
			# `loc` directly, while the movie's own cast subtracts the
			# registration point. The measured deltas equal `reg` exactly for
			# lib 2 and lib 4 members and are zero for lib 1, which is what a
			# second placement rule looks like from the outside.
			# The rule from `_resolve_sprite_rects`: it *skips* a sprite whose
			# score rect already equals its member's size, leaving the top-left
			# at `loc`, and only anchors on the registration point when the two
			# disagree. Reading that as "always subtract reg" displaces every
			# sprite whose rect already matched — by exactly its registration
			# point, which is 250px on MURDER1's member 2:1.
			# The renderer's current rule, measured as a baseline. Two
			# alternatives were tested against it and both scored worse overall:
			# treating linked-cast members as unanchored (MURDER1 298 -> 650 but
			# EXODUS 741 -> 544), and skipping the anchor when the score rect
			# already matches the member (worse everywhere, EXODUS to zero).
			#
			# What the deltas say is that there is no single rule. On MURDER1 the
			# error equals the registration point exactly, so those sprites are
			# placed at `loc`. On full-stage backgrounds the error is (320,200) —
			# half of 640x400 — so those are anchored at their centre. At least
			# two conventions are in play and the discriminator is not yet known.
			var mine := Vector2i(
				int(sprite.get("loc_h", 0)) - int(m.get("reg_offset_x", 0)),
				int(sprite.get("loc_v", 0)) - int(m.get("reg_offset_y", 0))
			)
			var theirs := Vector2i(int(sprite["x"]), int(sprite["y"]))
			if mine == theirs:
				exact += 1
				continue
			var d := theirs - mine
			var key := "%d,%d" % [d.x, d.y]
			deltas[key] = int(deltas.get(key, 0)) + 1
			if bool(sprite.get("stretch", false)):
				stretched_wrong += 1
			else:
				plain_wrong += 1
			if samples.size() < 10:
				samples.append(
					"f%d ch%s %s:%s  mine(%d,%d) export(%d,%d) delta(%d,%d) member %dx%d reg(%d,%d)%s"
					% [
						i, str(sprite.get("channel", 0)), str(sprite.get("cast_lib", 0)),
						str(sprite.get("cast_id", 0)), mine.x, mine.y, theirs.x, theirs.y,
						d.x, d.y, int(m["width"]), int(m["height"]),
						int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0)),
						"  stretched" if sprite.get("stretch", false) else "",
					]
				)

	h.check("sprites were compared", compared > 0, "%d" % compared)
	h.check("placement matches", exact == compared, "%d of %d exact" % [exact, compared])
	h.complete("computed placement matches the export")

	for line in samples:
		print("     %s" % line)
	print("")
	print("%s: %d compared, %d exact, %d wrong (%d stretched, %d plain)" % [
		movie, compared, exact, compared - exact, stretched_wrong, plain_wrong,
	])
	# The commonest deltas first: one dominant offset means one missing rule,
	# a spread means the offset is proportional to something.
	var keys := deltas.keys()
	keys.sort_custom(func(a, b): return int(deltas[a]) > int(deltas[b]))
	print("top deltas (x,y -> count):")
	for key in keys.slice(0, 12):
		print("  %-12s %d" % [key, int(deltas[key])])
	table.close()
	movie_file.close()
	quit(h.finish("the preview places sprites where the export does"))
