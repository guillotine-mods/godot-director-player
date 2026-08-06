extends SceneTree
## Does every matte-inked member actually have white on its border?
##
##   godot --headless --script tools/matte_survey.gd -- --file PIP2DATA/EXODUS.DIR
##
## Director builds a matte by scanning the border ring for an **exactly white**
## pixel, flood-filling from the whole perimeter with an **exact** colour test,
## and — when no white is found on the border — **building no matte at all**, so
## the sprite renders and hit-tests as a solid rectangle.
##
## That last rule is a real behaviour, not an error path, but it is also the one
## that can go badly wrong in a port: if this corpus's art does not hold an exact
## white edge, adopting the exact test turns matte sprites into opaque boxes that
## swallow every click inside them. The previous implementation hid that risk
## behind a 14/255 tolerance and a paper colour sampled from pixel (0,0).
##
## So this measures the thing the decision rests on: of the members actually
## drawn with Matte ink, how many have an exactly-white border pixel, how much of
## each is keyed out, and which ones come out solid.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Bitmap := preload("res://director/director_bitmap.gd")
const Palette := preload("res://director/director_palette.gd")
const Ink := preload("res://director/director_ink.gd")


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
		print("no VWSC")
		quit(1)
		return
	var score := Score.new()
	if not score.parse(movie_file.read_chunk(int(vwsc[0]))):
		print("no score: %s" % score.error)
		quit(1)
		return
	var palette := Palette.system_mac()

	# Which members are drawn with which keying, from the score itself.
	var wanted: Dictionary = {}
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var keying := Ink.key_for(int(sprite["ink"]))
			if keying == Ink.KEY_NONE:
				continue
			wanted["%d:%d:%d" % [
				int(sprite["cast_lib"]), int(sprite["cast_id"]), keying
			]] = sprite

	var matte_total := 0
	var matte_solid := 0
	var paper_total := 0
	var keyed_none := 0
	var solid_names: Array[String] = []
	var keyed_fraction := 0.0

	h.begin("matte-inked art has an exactly white border")
	for key in wanted:
		var sprite: Dictionary = wanted[key]
		var lib := int(sprite["cast_lib"])
		var id := int(sprite["cast_id"])
		var m: Dictionary = table.get_member(lib, id)
		if m.is_empty() or int(m.get("type", 0)) != 1:
			continue
		var f = table.file_for(lib)
		if f == null:
			continue
		var errors: Array = []
		var image: Image = Bitmap.decode(
			m, f.read_chunk(int(m.get("data_chunk_id", -1))), palette, errors
		)
		if image == null:
			continue
		var pixels := image.get_width() * image.get_height()
		if pixels <= 0:
			continue

		if Ink.key_for(int(sprite["ink"])) == Ink.KEY_MATTE:
			matte_total += 1
			if not Ink.key_matte(image):
				matte_solid += 1
				if solid_names.size() < 10:
					solid_names.append("%d:%d %s %dx%d" % [
						lib, id, str(m.get("name", "")),
						image.get_width(), image.get_height()
					])
				continue
		else:
			paper_total += 1
			var paper := Ink.colour_of(palette, int(sprite.get("back_color", 0)))
			if Ink.key_paper(image, paper) == 0:
				keyed_none += 1

		var clear := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a <= 0.0:
					clear += 1
		keyed_fraction += float(clear) / float(pixels)

	print("%s" % path.get_file())
	print("  matte-inked members : %d" % matte_total)
	print("    no white on border -> drawn solid : %d" % matte_solid)
	for name in solid_names:
		print("      %s" % name)
	print("  paper-keyed members : %d" % paper_total)
	print("    nothing keyed out : %d" % keyed_none)
	var counted := maxi(matte_total - matte_solid + paper_total, 1)
	print("  mean keyed-out area : %.1f%%" % (100.0 * keyed_fraction / counted))

	# The rule is real, so a few solid members are expected and correct. What
	# would mean the exact test is wrong for this art is most of them going solid.
	h.check(
		"most matte members still build a matte",
		matte_total == 0 or matte_solid * 2 < matte_total,
		"%d of %d come out solid" % [matte_solid, matte_total]
	)
	h.check(
		"paper keying removes something",
		paper_total == 0 or keyed_none * 2 < paper_total,
		"%d of %d had nothing to key" % [keyed_none, paper_total]
	)
	h.complete("matte-inked art has an exactly white border")
	quit(h.finish("matte and paper keying against exact colour matching"))
