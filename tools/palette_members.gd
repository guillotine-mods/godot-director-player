extends SceneTree
## Custom palettes: that they are read the right way up, that a bitmap names one,
## and that the member's own table is what its pixels are decoded through.
##
##   godot --headless --script tools/palette_members.gd -- --root res://test-games/itamar-park
##
## `tools/palette_survey.gd` counts what a corpus *names*; this asserts what the
## renderer does with it. The two are separate because the survey has to be
## runnable on a corpus with no palettes at all and this must not be — a corpus
## that ships no `CLUT` chunk cannot exercise any of this, so being pointed at
## one is a failure with that sentence in it rather than a green run over
## nothing. It is the same rule `tools/cursor_cross_cast.gd` follows for a corpus
## with no cross-cast cursor pair, and for the same reason: a harness that passes
## by having nothing to check is worse than no harness.
##
## **Three things go red here, and each one was a real defect.**
##
## *Paper is white.* A `CLUT` chunk stores entry 0 first, and it was being read
## last-entry-first on the theory that the reversal is what puts white at index 0
## the way the generated system Mac table has it. The chunks already open with
## white, so the reversal moved **black** to index 0 — which is paper, the index
## both ink passes key out and the one index that has to be exactly white. Every
## custom palette came out inverted: `itamar-park`'s Antarctic backdrop drew
## 84,255 black pixels with an orange sea instead of 61,600 white ones with a
## teal one, and its matte stopped keying anything.
##
## *A bitmap names its palette.* The clut id sits at offset 26 of a D5+ bitmap's
## specific block, after the clut *cast library* at 24. Reading the library
## instead answers -1 — system Mac — for every bitmap in every title ever
## loaded, which is why a corpus of six titles that genuinely are all system Mac
## could not tell the two apart. Here 655 of 657 bitmap members name a palette
## member in their own cast, so a wrong offset drops to zero.
##
## *The member's table, not the stage's.* Director on an 8-bit screen blits
## indices into one screen CLUT; on a 16-bit or deeper screen — `movieDepth` 32,
## which is what these movies state — it converts each bitmap through the palette
## its own member names. Over this title's scores the stage is holding the
## palette a bitmap names for 22 of 5,692 (frame, sprite) pairs, so drawing it
## the first way makes 99.6% of the artwork the wrong colour.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const PaletteView := preload("res://scenes/preview/palette_view.gd")
const Bitmap := preload("res://director/director_bitmap.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")
const Config := preload("res://director/director_config.gd")

## Both ink passes treat "every channel at or above this" as paper, and
## `tools/director_bitmaps.gd` uses the same number for the same reason.
const PAPER_MIN_BYTE := 241


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var targets: Array[String] = []
	_walk(paths.root, targets)
	targets.sort()

	var clut_chunks := 0
	var palette_members := 0
	# Palette member -> whether its table's paper index is white.
	var paper_wrong: Array[String] = []
	var ink_wrong: Array[String] = []
	var short_tables: Array[String] = []
	# Bitmap members naming a palette member, and whether that member is there.
	var naming_member := 0
	var naming_missing: Array[String] = []
	var naming_builtin: Dictionary = {}
	# Members whose own table is not the one the stage is on.
	var own_table := 0
	var own_table_same := 0
	var recoloured: Array[String] = []
	var defaults: Dictionary = {}
	var system := Palette.system_mac()

	for path in targets:
		var movie := ContainerFile.new()
		if not movie.open(path):
			continue
		clut_chunks += movie.ids_of("CLUT").size()
		var config = Config.new()
		if config.read(movie):
			defaults[int(config.default_palette)] = \
				int(defaults.get(int(config.default_palette), 0)) + 1
		var table := CastTable.new()
		if not table.open(movie, paths):
			movie.close()
			continue
		var c = table.cast_for(1)
		if c == null:
			movie.close()
			continue
		for n in c.member_numbers():
			var m: Dictionary = table.get_member(1, n)
			if m.is_empty():
				continue
			var type_code := int(m.get("type", 0))
			if type_code == Palette.MEMBER_TYPE:
				palette_members += 1
				var built := PaletteView.table_for(n, table, 1)
				var where := "%s #%d '%s'" % [path.get_file(), n, m.get("name", "")]
				if built.size() != Palette.TABLE_BYTES:
					short_tables.append(where)
					continue
				if not _is_paper(built, Palette.PAPER_INDEX):
					paper_wrong.append("%s: index %d is (%d,%d,%d)" % [
						where, Palette.PAPER_INDEX,
						built[0], built[1], built[2],
					])
				# The other end is the check that a merely *dim* palette does not
				# pass the first one: a reversed read swaps the two, so asserting
				# both pins the direction rather than the brightness.
				if _is_paper(built, Palette.INK_INDEX):
					ink_wrong.append("%s: index %d is white too" % [where, Palette.INK_INDEX])
				continue
			if type_code != 1:
				continue
			var clut := int(m.get("palette_id", Palette.SYSTEM_MAC))
			if clut < 0:
				naming_builtin[clut] = int(naming_builtin.get(clut, 0)) + 1
			elif clut > 0:
				naming_member += 1
				var owner: Dictionary = table.get_member(
					int(m.get("palette_lib", 0)) if int(m.get("palette_lib", 0)) > 0 else 1, clut
				)
				if owner.is_empty() or int(owner.get("type", 0)) != Palette.MEMBER_TYPE:
					naming_missing.append("%s #%d -> %d" % [path.get_file(), n, clut])
			# What the renderer would actually decode this member through, with the
			# stage on system Mac.
			var chosen := PaletteView.table_for_member(m, table, system, Palette.SYSTEM_MAC)
			if chosen == system:
				own_table_same += 1
				continue
			own_table += 1
			if recoloured.size() < 40 and int(m.get("width", 0)) > 0:
				recoloured.append("%s|%d|%s" % [path, n, m.get("name", "")])
		movie.close()

	print("%d container(s) under %s" % [targets.size(), paths.root])
	print("  CLUT chunks               : %d" % clut_chunks)
	print("  palette cast members      : %d" % palette_members)
	print("  bitmaps naming a member   : %d" % naming_member)
	print("  bitmaps naming a built-in : %s" % str(naming_builtin))
	print("  bitmaps on their own table: %d (on the stage's: %d)" % [own_table, own_table_same])
	print("  movie default palettes    : %s" % str(defaults))

	h.begin("a corpus that can exercise custom palettes")
	h.check(
		"the corpus ships CLUT chunks",
		clut_chunks > 0,
		"%d; point --root at a title with custom palettes, this one cannot exercise any of it"
			% clut_chunks,
	)
	h.check("the corpus ships palette cast members", palette_members > 0,
		"%d" % palette_members)
	h.complete("a corpus that can exercise custom palettes")

	h.begin("a CLUT is read entry 0 first")
	h.check("every palette member builds a 768-byte table", short_tables.is_empty(),
		"%d short: %s" % [short_tables.size(), ", ".join(short_tables.slice(0, 4))])
	h.check(
		"paper (index %d) is white in every palette" % Palette.PAPER_INDEX,
		paper_wrong.is_empty(),
		"%d are not: %s" % [paper_wrong.size(), ", ".join(paper_wrong.slice(0, 4))],
	)
	h.check(
		"index %d is not white in any palette" % Palette.INK_INDEX,
		ink_wrong.is_empty(),
		"%d are: %s" % [ink_wrong.size(), ", ".join(ink_wrong.slice(0, 4))],
	)
	h.complete("a CLUT is read entry 0 first")

	h.begin("a bitmap names the palette its indices are numbers in")
	h.check(
		"at least one bitmap member names a palette member",
		naming_member > 0,
		"%d; the clut id is at offset 26 of the specific block, not 24" % naming_member,
	)
	h.check(
		"every named palette member is in the cast",
		naming_missing.is_empty(),
		"%d missing: %s" % [naming_missing.size(), ", ".join(naming_missing.slice(0, 4))],
	)
	h.complete("a bitmap names the palette its indices are numbers in")

	h.begin("a member is decoded through its own palette")
	h.check(
		"at least one bitmap is drawn through a table the stage is not on",
		own_table > 0,
		"%d" % own_table,
	)
	# The end of the chain: decoding one real member both ways has to produce
	# different pixels, or the table is being resolved and then not used.
	var moved := 0
	var sampled := 0
	for entry in recoloured:
		var parts := entry.split("|")
		var pair := _decode_both(parts[0], int(parts[1]), paths, system)
		if pair.is_empty():
			continue
		sampled += 1
		if pair["own"] != pair["stage"]:
			moved += 1
	h.check(
		"decoding through it changes the pixels",
		sampled > 0 and moved == sampled,
		"%d of %d sampled members differ" % [moved, sampled],
	)
	h.complete("a member is decoded through its own palette")

	quit(h.finish("custom palettes, as the renderer uses them"))


## `{stage, own}` — the same member's pixels as the stage table alone would
## produce them, and as **the renderer** produces them. Empty when the member
## does not decode at all, which `tools/director_bitmaps.gd` is the harness for.
##
## The second half goes through `sprite_art.gd` rather than through
## `DirectorBitmap` directly, and that is the point of it: resolving the member's
## table and then not handing it to the decoder is exactly the failure this check
## exists to catch, and a comparison of two direct decodes could not see it.
func _decode_both(path: String, number: int, paths: Paths,
		stage: PackedByteArray) -> Dictionary:
	var movie := ContainerFile.new()
	if not movie.open(path):
		return {}
	var table := CastTable.new()
	if not table.open(movie, paths):
		movie.close()
		return {}
	var m: Dictionary = table.get_member(1, number)
	var f = table.file_for(1)
	if m.is_empty() or f == null:
		movie.close()
		return {}
	var chunk: PackedByteArray = f.read_chunk(int(m.get("data_chunk_id", -1)))
	# Copy ink, so no keying pass runs and the comparison is of colour alone.
	var sprite := {
		"cast_lib": 1, "cast_id": number, "ink": 0,
		"width": 0, "height": 0, "fore_color": 255, "back_color": 0,
	}
	var hit: Dictionary = {}
	SpriteArt.texture_for(sprite, table, stage, {}, hit, Palette.SYSTEM_MAC)
	var drawn: Image = hit.get(hit.keys()[0], null) if not hit.is_empty() else null
	var plain: Image = Bitmap.decode(m, chunk, stage, [])
	movie.close()
	if plain == null or drawn == null:
		return {}
	return {"stage": plain.get_data(), "own": drawn.get_data()}


## Paper, as both ink passes define it: every channel at or above the threshold.
static func _is_paper(table: PackedByteArray, index: int) -> bool:
	return table[index * 3] >= PAPER_MIN_BYTE \
		and table[index * 3 + 1] >= PAPER_MIN_BYTE \
		and table[index * 3 + 2] >= PAPER_MIN_BYTE


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
