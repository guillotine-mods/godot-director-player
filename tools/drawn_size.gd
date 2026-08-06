extends SceneTree
## Which size is a sprite drawn at, and where does that put it?
##
##   godot --headless --script tools/drawn_size.gd -- --file PIP2DATA/EXODUS.DIR
##
## Two rules were in the tree and they contradicted each other.
##
## `director/director_score.gd:243-245` says the stored rect is **authoring
## residue** whenever the stretch flag is clear. `tools/film_loop_stretch.gd`
## proves that for a film loop's children: of the 2,053 children carrying the
## flag, zero have a rect equal to their member's natural size, which separates
## the two populations cleanly. The preview used to apply the same rule to the
## main score — draw at the member's natural size unless stretch is set, and take
## the registration offset raw.
##
## `docs/DIRECTOR_ENGINE.md` §1.2 says the opposite for the main score: the
## sprite's own width and height **always** win, `getBbox` uses them and nothing
## else, and the member's natural size enters only as the denominator when
## scaling the registration offset.
##
## This settles it against `assets/render_model/<movie>/frames.json` — the decode
## the previously working renderer drew from, and therefore the closest thing to
## a picture known to have been right. Both rules are scored on how often they
## reproduce the export's top-left exactly.
##
## The residue rule is not merely worse; it lands *only* where the two sizes
## happen to agree, which is what a rule that is wrong whenever it is load-bearing
## looks like from the outside.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var movie := Args.text(args, "file", "PIP2DATA/DAY1.DIR")
	var stem := movie.get_file().get_basename().to_upper()

	var frames_path := "res://assets/render_model/%s/frames.json" % stem
	var members_path := "res://assets/render_model/%s/members.json" % stem
	if not FileAccess.file_exists(frames_path) or not FileAccess.file_exists(members_path):
		print("no export for %s" % stem)
		quit(1)
		return
	var frames_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	var members_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(members_path))
	if typeof(frames_doc) != TYPE_DICTIONARY or typeof(members_doc) != TYPE_DICTIONARY:
		print("bad export")
		quit(1)
		return
	var frames: Array = (frames_doc as Dictionary).get("frames", [])
	var members: Dictionary = (members_doc as Dictionary).get("members", {})

	# Keyed the way a sprite record names its member.
	var by_id: Dictionary = {}
	for value in members.values():
		var m: Dictionary = value
		by_id["%d:%d" % [int(m.get("cast_lib", 1)), int(m.get("cast_id", 0))]] = m

	var compared := 0
	var sizes_agree := 0
	var own_size_ok := 0
	var natural_ok := 0
	var worst := 0

	h.begin("%s: the sprite's own size places it, the member's does not" % stem)
	for frame_value in frames:
		var frame: Dictionary = frame_value
		for sprite_value in frame.get("sprites", []):
			var sprite: Dictionary = sprite_value
			var key := "%d:%d" % [int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0))]
			var m: Dictionary = by_id.get(key, {})
			if m.is_empty() or int(m.get("width", 0)) <= 0:
				continue
			if not sprite.has("x") or not sprite.has("y"):
				continue
			compared += 1
			var natural := Vector2(float(m["width"]), float(m["height"]))
			var drawn := Vector2(float(sprite["width"]), float(sprite["height"]))
			if drawn == natural:
				sizes_agree += 1
			var reg := Vector2(
				float(m.get("reg_offset_x", 0)), float(m.get("reg_offset_y", 0))
			)
			var loc := Vector2(float(sprite["loc_h"]), float(sprite["loc_v"]))
			var theirs := Vector2i(int(sprite["x"]), int(sprite["y"]))

			# What the renderer now does: the sprite's own size, with the
			# registration offset scaled into it. `_stage_rect` / `_scaled_reg`.
			var scaled := Vector2(
				reg.x * drawn.x / maxf(natural.x, 1.0),
				reg.y * drawn.y / maxf(natural.y, 1.0)
			)
			if Vector2i((loc - scaled).round()) == theirs:
				own_size_ok += 1
			# What it used to do: the member's natural size, offset taken raw.
			if Vector2i((loc - reg).round()) == theirs:
				natural_ok += 1
			else:
				var slip := (loc - reg) - Vector2(theirs)
				worst = maxi(worst, int(maxf(absf(slip.x), absf(slip.y))))

	if compared == 0:
		print("no comparable sprites in %s" % stem)
		quit(1)
		return

	print("%s: %d sprites compared against the export" % [stem, compared])
	print("  score rect already equals the member's size: %d (%d%%)" % [
		sizes_agree, sizes_agree * 100 / compared
	])
	print("  placed exactly by the sprite's own size:     %d (%d%%)" % [
		own_size_ok, own_size_ok * 100 / compared
	])
	print("  placed exactly by the member's natural size: %d (%d%%)" % [
		natural_ok, natural_ok * 100 / compared
	])
	print("  worst miss under the old rule:               %dpx" % worst)

	h.check(
		"the sprite's own size reproduces the export",
		own_size_ok * 100 / compared >= 95,
		"%d of %d" % [own_size_ok, compared]
	)
	h.check(
		"it beats the rule it replaced",
		own_size_ok > natural_ok,
		"%d against %d" % [own_size_ok, natural_ok]
	)
	# The old rule's successes should be a subset of the cases where the question
	# does not arise. If it ever wins where the sizes differ, the story is wrong.
	h.check(
		"the old rule only ever landed where the sizes agreed anyway",
		natural_ok <= sizes_agree + 2,
		"%d correct against %d where sizes agree" % [natural_ok, sizes_agree]
	)
	h.complete("%s: the sprite's own size places it, the member's does not" % stem)
	quit(h.finish("which size a sprite is drawn at, against the export"))
