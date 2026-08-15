extends SceneTree
## A sprite record that states a **true colour** is drawn in that colour, and not
## in whatever the palette happens to hold at the byte it shares with an index.
##
##   godot --headless --path . --audio-driver Dummy --script tools/sprite_true_colour.gd
##   godot --headless --path . --audio-driver Dummy --script tools/sprite_true_colour.gd -- --root piposh-dream
##
## `bugs.md` 30. Colour-code bits `0x10` and `0x20` (record offset 20) say that
## the fore or back colour is a colour rather than an index: its red component is
## the byte the index reading uses, and bytes 24-27 carry the greens and blues
## (`frame.cpp:readSpriteDataD7`, ScummVM 805f259a). The reference parses those
## four bytes, copies them in `replaceFrom`, and reads them nowhere afterwards, so
## it says what they *are* and nothing about what to do with them.
##
## ## The three things asserted, and why each is the player-visible one
##
## **1. The decoder puts a colour on the record, and only where the record says
## so.** `has(fore_rgb)` is the whole signal, so a false positive would make an
## indexed sprite ignore its palette. Asserted as a population: the corpus's
## records are overwhelmingly indexed, and a flag read out of the wrong bit would
## light up everywhere.
##
## **2. The default pair does not colourise.** This is the check that fails with
## the fix reverted, and it is the one that matters most, because `(0,0,0)` on
## `(255,255,255)` is Director's *default* colour pair written the D7 way -- and
## its two red bytes are 0 and 255, which as indices are that same pair
## **inverted**. So the old index test answered "these are not the defaults,
## colourise", and `apply_colour` then repainted the artwork's black pixels white
## and its white pixels black. Every one of the corpus's 57,152 back colours is
## `(255,255,255)` and 32,875 of its fore colours are `(0,0,0)`
## (`tools/sprite_rgb_colour.gd`), so this is the common case rather than an edge.
##
## **3. The two spellings do not share a cache slot.** A true colour's red
## component is the same byte an index uses, so `texture_key` had to grow a term
## or `(0,0,0)` and palette index 0 -- black and white -- would hand each other
## their pixels.
##
## The record is built here rather than found in a container, and that is
## deliberate: `piposh-dream` is the only root with a substantial population and a
## harness that asserts against one title's authoring is a harness that goes red
## when somebody points it at another. The bytes are laid out by hand, in the
## reference's own order, so what is under test is the port's reading of a
## documented layout. A corpus pass runs beside it and reports what it found
## **without asserting a count**, for the reason `AGENTS.md` gives: a number here
## would be a measurement of whichever roots this machine happens to have.
##
## Title-agnostic: it names no game, and the corpus half discovers its roots.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Score := preload("res://director/director_score.gd")
const Ink := preload("res://director/director_ink.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Paths := preload("res://director/director_paths.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	_decodes(h)
	_default_pair_does_not_colourise(h)
	_cache_key_separates_them(h)
	_the_corpus_agrees(h, args)
	quit(h.finish("true-RGB sprite colour, decoded and drawn"))


## A 48-byte D7 sprite record with the fields this harness needs, so the layout
## under test is the reference's and not one read back out of the decoder.
static func _record(code: int, fore_r: int, back_r: int,
		fore_g: int, back_g: int, fore_b: int, back_b: int) -> PackedByteArray:
	var buffer := PackedByteArray()
	buffer.resize(Score.SPRITE_RECORD_SIZE * (1 + Score.CHANNEL_BIAS + 1))
	buffer.fill(0)
	var at: int = Score.SPRITE_RECORD_SIZE * (1 + Score.CHANNEL_BIAS)
	buffer[at + 1] = Ink.COPY
	buffer[at + 2] = fore_r
	buffer[at + 3] = back_r
	buffer[at + 5] = 1        # cast lib 1
	buffer[at + 7] = 3        # member 3, so the occupancy test passes
	buffer[at + 17] = 20      # height
	buffer[at + 19] = 20      # width
	buffer[at + Score.COLOR_CODE_AT] = code
	buffer[at + Score.FORE_G_AT] = fore_g
	buffer[at + Score.BACK_G_AT] = back_g
	buffer[at + Score.FORE_B_AT] = fore_b
	buffer[at + Score.BACK_B_AT] = back_b
	return buffer


## The one sprite a hand-built record decodes to, through the decoder's own
## channel-buffer reader rather than through a second copy of it here -- so what
## is under test is the function the player calls.
static func _sprite(buffer: PackedByteArray) -> Dictionary:
	var score := Score.new()
	score.channels_displayed = 1
	var frame: Dictionary = score._snapshot(buffer, 0)
	for value in frame.get("sprites", []):
		return value
	return {}


func _decodes(h) -> void:
	var case := "the colour-code bits put a colour on the record, and only then"
	h.begin(case)
	var indexed := _sprite(_record(0x00, 255, 0, 0, 0, 0, 0))
	h.check("an indexed record carries no true colour at all",
		not indexed.has(Ink.FORE_RGB_KEY) and not indexed.has(Ink.BACK_RGB_KEY),
		"fore_rgb %s, back_rgb %s" % [str(indexed.get(Ink.FORE_RGB_KEY)),
			str(indexed.get(Ink.BACK_RGB_KEY))])
	h.check("and its two index bytes survive",
		int(indexed.get("fore_color", -1)) == 255
			and int(indexed.get("back_color", -1)) == 0,
		"fore %d, back %d" % [int(indexed.get("fore_color", -1)),
			int(indexed.get("back_color", -1))])

	# Bytes chosen so that every component is distinct and none of them is 0 or
	# 255: a swapped pair or a byte read from the neighbouring field shows up as
	# a wrong number rather than as a coincidence.
	var both := _sprite(_record(0x30, 17, 34, 51, 68, 85, 102))
	h.check("the fore bits give (red from byte 2, green from 24, blue from 26)",
		Ink._is_rgb(both.get(Ink.FORE_RGB_KEY), 17, 51, 85),
		str(both.get(Ink.FORE_RGB_KEY)))
	h.check("the back bits give (red from byte 3, green from 25, blue from 27)",
		Ink._is_rgb(both.get(Ink.BACK_RGB_KEY), 34, 68, 102),
		str(both.get(Ink.BACK_RGB_KEY)))

	# One bit at a time, because the two are independent in the record and a
	# reader that keyed both off one bit would pass the test above.
	var fore_only := _sprite(_record(Score.FORE_COLOR_RGB_FLAG, 17, 34, 51, 68, 85, 102))
	h.check("the fore bit alone states only the fore colour",
		fore_only.has(Ink.FORE_RGB_KEY) and not fore_only.has(Ink.BACK_RGB_KEY),
		"fore_rgb %s, back_rgb %s" % [str(fore_only.get(Ink.FORE_RGB_KEY)),
			str(fore_only.get(Ink.BACK_RGB_KEY))])
	var back_only := _sprite(_record(Score.BACK_COLOR_RGB_FLAG, 17, 34, 51, 68, 85, 102))
	h.check("the back bit alone states only the back colour",
		back_only.has(Ink.BACK_RGB_KEY) and not back_only.has(Ink.FORE_RGB_KEY),
		"fore_rgb %s, back_rgb %s" % [str(back_only.get(Ink.FORE_RGB_KEY)),
			str(back_only.get(Ink.BACK_RGB_KEY))])

	# The low nibble and the two high bits share the byte, so a mask that ate one
	# of them would be invisible in every check above.
	var with_extras := _sprite(_record(0x30 | 0x05, 17, 34, 51, 68, 85, 102))
	h.check("the score colour in the same byte is still read beside them",
		int(with_extras.get("score_color", -1)) == 5
			and with_extras.has(Ink.FORE_RGB_KEY),
		"score_color %d" % int(with_extras.get("score_color", -1)))
	h.complete(case)


func _default_pair_does_not_colourise(h) -> void:
	var case := "black on white is the default pair however the record spells it"
	h.begin(case)
	# The corpus's own commonest pair: fore (0,0,0), back (255,255,255).
	var rgb := _sprite(_record(0x30, 0, 255, 0, 255, 0, 255))
	h.check("the record decoded to that pair",
		Ink._is_rgb(rgb.get(Ink.FORE_RGB_KEY), 0, 0, 0)
			and Ink._is_rgb(rgb.get(Ink.BACK_RGB_KEY), 255, 255, 255),
		"%s on %s" % [str(rgb.get(Ink.FORE_RGB_KEY)), str(rgb.get(Ink.BACK_RGB_KEY))])
	# **This is the check that fails with the fix reverted.** The old test read
	# the two red bytes as indices -- 0 and 255, which in Director's inverted
	# 8-bit convention are white and black -- decided the pair was not the
	# default, and colourised: `apply_colour` repaints black pixels `fore` and
	# white pixels `back`, so the artwork came out inverted.
	h.check("a true-colour default pair does not colourise",
		not Ink.applies_colour_to(rgb, Ink.COPY),
		"fore %s back %s, indices %d/%d" % [str(rgb.get(Ink.FORE_RGB_KEY)),
			str(rgb.get(Ink.BACK_RGB_KEY)), int(rgb.get("fore_color", -1)),
			int(rgb.get("back_color", -1))])
	# And the palette is not consulted for it, which is the other half: a record
	# that states a colour is not asking about the movie's palette at all.
	var palette := PackedByteArray()
	palette.resize(256 * 3)
	palette.fill(0)
	palette[0] = 255
	palette[1] = 255
	palette[2] = 255          # index 0 is white, Director's convention
	h.check("the true colour is used instead of the palette entry its red shares",
		Ink.fore_colour(rgb, palette) == Color8(0, 0, 0)
			and Ink.back_colour(rgb, palette) == Color8(255, 255, 255),
		"fore %s, back %s" % [str(Ink.fore_colour(rgb, palette)),
			str(Ink.back_colour(rgb, palette))])

	# The indexed spelling of the same pair, unchanged: the whole corpus outside
	# the flagged records goes through this and none of it may move.
	var indexed := _sprite(_record(0x00, Ink.INDEX_BLACK, Ink.INDEX_WHITE, 0, 0, 0, 0))
	h.check("the indexed default pair still does not colourise either",
		not Ink.applies_colour_to(indexed, Ink.COPY),
		"fore %d, back %d" % [int(indexed.get("fore_color", -1)),
			int(indexed.get("back_color", -1))])
	# A non-default true colour must still colourise, or the fix would have
	# bought correctness by drawing nothing.
	var tinted := _sprite(_record(0x30, 204, 255, 255, 255, 0, 255))
	h.check("a true colour that is not the default pair does colourise",
		Ink.applies_colour_to(tinted, Ink.COPY),
		"fore %s" % str(tinted.get(Ink.FORE_RGB_KEY)))
	h.complete(case)


func _cache_key_separates_them(h) -> void:
	var case := "an index and a true colour that share a byte get different textures"
	h.begin(case)
	var indexed := _sprite(_record(0x00, 0, 0, 0, 0, 0, 0))
	var black := _sprite(_record(0x30, 0, 0, 0, 0, 0, 0))
	# Index 0 is white and (0,0,0) is black, and both spell their red component
	# as the byte 0 -- so without a term for the true colour these two records
	# produce the same key and whichever decodes first decides how the other
	# looks.
	h.check("the two records differ in what they name",
		not indexed.has(Ink.FORE_RGB_KEY) and black.has(Ink.FORE_RGB_KEY))
	h.check("so their texture keys differ",
		Geometry.texture_key(indexed, Vector2(20, 20))
			!= Geometry.texture_key(black, Vector2(20, 20)),
		Geometry.texture_key(indexed, Vector2(20, 20)))
	# And an indexed record's key is byte-for-byte what it was before true
	# colours existed, so nothing in the seven roots without them re-decodes.
	h.check("an indexed record's key gains nothing",
		not Geometry.texture_key(indexed, Vector2(20, 20)).ends_with(":"),
		Geometry.texture_key(indexed, Vector2(20, 20)))
	h.complete(case)


## What the corpus on this machine actually holds. Reported, not asserted beyond
## "the reading is coherent": the population is a property of whichever roots are
## checked out, and a count here would go red on a machine with one fewer.
func _the_corpus_agrees(h, args: Dictionary) -> void:
	var case := "the corpus's own records decode coherently"
	h.begin(case)
	var roots: Array[String] = []
	var one := Args.text(args, "root", "")
	if one != "":
		roots.append(one if one.begins_with("res://") else "res://games".path_join(one))
	else:
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			for sub in dir.get_directories():
				roots.append(str(parent).path_join(sub))
	roots.sort()

	var records := 0
	var with_rgb := 0
	var default_pair := 0
	var would_have_colourised := 0
	# Counted in the same pass rather than by a second walk. The first version
	# walked the corpus twice for this one boolean and took eleven minutes over
	# eight roots, which is the difference between an entry somebody runs and an
	# entry somebody skips.
	var default_colourises := 0
	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		for path in files:
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
			for i in score.frame_count:
				for value in (score.frame(i).get("sprites", []) as Array):
					var sprite: Dictionary = value
					records += 1
					if not sprite.has(Ink.FORE_RGB_KEY) and not sprite.has(Ink.BACK_RGB_KEY):
						continue
					with_rgb += 1
					if Ink.is_default_colour(sprite):
						default_pair += 1
						if Ink.applies_colour_to(sprite, int(sprite["ink"])):
							default_colourises += 1
						# What the index reading did with it: the same record,
						# judged the old way. Every one of these was repainted.
						if Ink.applies_colour(int(sprite["ink"]),
								int(sprite.get("fore_color", Ink.INDEX_BLACK)),
								int(sprite.get("back_color", Ink.INDEX_WHITE))):
							would_have_colourised += 1
			f.close()

	print("")
	print("%d sprite record(s) over %d root(s)" % [records, roots.size()])
	print("  stating a true colour                    : %d" % with_rgb)
	print("  of those, Director's default black/white : %d" % default_pair)
	print("  which the index reading would repaint    : %d" % would_have_colourised)
	h.check("the sweep read a corpus", records > 0, "%d record(s)" % records)
	# The coherence claim, and it is about the reading rather than about the
	# population: a record that states the default pair as a true colour must not
	# be judged non-default by the function that draws it. Vacuously true on a
	# checkout with no such records, which is the honest answer there.
	h.check("no record that states the default pair is treated as a tint",
		default_colourises == 0,
		"%d of %d default-pair record(s) would repaint" % [
			default_colourises, default_pair])
	h.complete(case)


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
