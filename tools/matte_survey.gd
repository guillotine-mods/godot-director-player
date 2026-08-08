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
	#
	# `key_for` reads the member as well as the sprite, so the lookup happens here
	# rather than on the ink alone. A record whose member does not resolve is
	# counted as unkeyed, which is also what the renderer does with it.
	var wanted: Dictionary = {}
	# The third census: records the reference mattes and this port does not. It is
	# the shape of the defect `bugs.md` 50 was, asked as a number so that the next
	# one cannot hide -- a keying rule that silently disagrees with `Channel::getMask`
	# is invisible until somebody looks at the right frame of the right movie.
	var reference_only := 0
	var reference_only_names: Array[String] = []
	for i in score.frame_count:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var member: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			var keying := Ink.key_for(sprite, member)
			if _reference_mattes(sprite, member) and keying != Ink.KEY_MATTE:
				reference_only += 1
				if reference_only_names.size() < 10:
					reference_only_names.append("%d:%d %s ink %d%s" % [
						int(sprite["cast_lib"]), int(sprite["cast_id"]),
						str(member.get("name", "")),
						int(sprite["ink"]),
						" +blend" if bool(sprite.get("has_blend", false)) else "",
					])
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

		if Ink.key_for(sprite, m) == Ink.KEY_MATTE:
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
	print("  records ScummVM mattes and this port does not : %d" % reference_only)
	for name in reference_only_names:
		print("      %s" % name)

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
	# Zero, not "few". Every clause of `needsMatte` is implemented, so any record
	# the reference mattes and this port does not is a divergence rather than a
	# tolerance -- which is exactly what 27,914 of Rating's records were.
	h.check(
		"nothing the reference mattes is left unkeyed",
		reference_only == 0,
		"%d record(s) diverge" % reference_only
	)
	h.complete("matte-inked art has an exactly white border")
	quit(h.finish("matte and paper keying against exact colour matching"))


## `Channel::getMask` (`channel.cpp:188-226`) read straight from the reference, as
## an independent second opinion on `director_ink.gd:key_for`.
##
## Deliberately a *transcription* and not a call into the engine. A census that
## asks the code under test whether it agrees with itself measures nothing; this
## exists so that a future edit to `key_for` that drops a clause fails here instead
## of passing quietly. Keep it a copy, however much it looks like duplication.
func _reference_mattes(sprite: Dictionary, member: Dictionary) -> bool:
	if member.is_empty() or int(member.get("type", 0)) != 1:
		return false
	var ink := int(sprite.get("ink", 0)) & 0x3F
	var has_blend := bool(sprite.get("has_blend", false))
	var amount := int(sprite.get("blend_amount", 0))
	var needs := [8, 4, 5, 6, 7, 32, 33, 34, 35, 37, 38, 39].has(ink) \
		or ((has_blend or ink == 32) and amount > 0) \
		or (ink == 0 and has_blend \
			and not [2, 3, 4, 5, 6, 12, 13, 14, 15].has(
				int(sprite.get("sprite_type", 0))))
	if not needs:
		return false
	# The 1-bit exception: a matte only under Matte ink proper.
	if int(member.get("bits_per_pixel", 8)) == 1 and ink != 8:
		return false
	return true
