extends SceneTree
## Is a film loop centred on its real size, or on authoring residue?
##
##   godot --headless --script tools/loop_anchor.gd -- --file PIP2DATA/DAY1.DIR
##
## A film loop's registration point is the centre of its rect, so the renderer
## puts its top-left at `loc - half the drawn size`. Which size is "the drawn
## size" is the whole question. The score record carries a width and a height,
## but by the same rule `tools/film_loop_stretch.gd` establishes for a loop's
## children, those are the drawn rect **only when the stretch flag is set** — with
## the flag clear they are authoring residue, and the drawn size is the member's
## own.
##
## `scenes/director_preview.gd._draw_film_loop` centres on the score record's
## width and height unconditionally. Where the record disagrees with the member
## and the flag is clear, every child of that loop is displaced by half the
## difference — a constant per-loop offset that moves when the loop does, which
## is what "the character is in the wrong place" looks like from the outside.
##
## This reports the displacement per loop rather than a verdict, because the
## distribution says whether the rule is wrong or merely untidy.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
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

	var movie_file := ContainerFile.new()
	if not movie_file.open(path):
		print("%s: %s" % [path, movie_file.error])
		quit(1)
		return
	var table := CastTable.new()
	table.open(movie_file, paths)
	var vwsc: Array = movie_file.ids_of("VWSC")
	if vwsc.is_empty():
		print("no VWSC in %s" % path)
		quit(1)
		return
	var score := Score.new()
	if not score.parse(movie_file.read_chunk(int(vwsc[0]))):
		print("no score: %s" % score.error)
		quit(1)
		return

	var loops := 0
	var stretched := 0
	var agreeing := 0
	var seen: Dictionary = {}
	var offsets: Dictionary = {}
	var worst := 0
	var limit: int = mini(Args.number(args, "frames", 600), score.frame_count)

	h.begin("a film loop is centred on its member's size, not the score's residue")
	for i in limit:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var lib := int(sprite["cast_lib"])
			var id := int(sprite["cast_id"])
			var m: Dictionary = table.get_member(lib, id)
			if m.is_empty() or int(m.get("type", 0)) != 2:
				continue
			loops += 1
			var key := "%d:%d" % [lib, id]
			if bool(sprite["stretch"]):
				stretched += 1
				continue
			var scored := Vector2i(int(sprite["width"]), int(sprite["height"]))
			var natural := Vector2i(int(m.get("width", 0)), int(m.get("height", 0)))
			if scored == natural:
				agreeing += 1
				continue
			# What the renderer does, minus what the rule says it should do.
			# Both halve, so the displacement is half the disagreement.
			var slip := Vector2i(
				int(floor(natural.x * 0.5)) - int(floor(scored.x * 0.5)),
				int(floor(natural.y * 0.5)) - int(floor(scored.y * 0.5))
			)
			worst = maxi(worst, maxi(absi(slip.x), absi(slip.y)))
			if not seen.has(key):
				seen[key] = true
				offsets[key] = [scored, natural, slip]

	print("film-loop sprite records: %d over %d frames" % [loops, limit])
	print("  stretch set (rect is real):    %d" % stretched)
	print("  rect already equals member:    %d" % agreeing)
	print("  displaced by the wrong size:   %d records, %d distinct loops" % [
		loops - stretched - agreeing, offsets.size()
	])
	var keys: Array = offsets.keys()
	keys.sort()
	for key in keys:
		var row: Array = offsets[key]
		print("    %-10s score %s  member %s  moves by %s" % [
			key, str(row[0]), str(row[1]), str(row[2])
		])

	h.check(
		"a film loop is centred on its member's size, not the score's residue",
		offsets.is_empty(),
		"%d loops displaced, worst %dpx" % [offsets.size(), worst]
	)
	h.complete("a film loop is centred on its member's size, not the score's residue")
	quit(h.finish("film-loop anchoring against the stretch rule"))
