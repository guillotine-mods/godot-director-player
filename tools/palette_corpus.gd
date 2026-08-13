extends SceneTree
## Palettes across every shipped title, rather than across one.
##
##   godot --headless --script tools/palette_corpus.gd
##
## `tools/palette_members.gd` is the deeper harness, and it needs a corpus whose
## bitmaps name palette *members*. Only `test-games/itamar-park` does, and that
## title is not part of this project, so it left `gate.sh`'s `ALL` list -- and
## took the whole CLUT read path out of the gate with it, a path that had two
## real defects in it. This is what the six titles in `games/` can actually
## answer. It is less than `palette_members` asserts and a great deal more than
## nothing, which is what was covering this in between.
##
## **Every check here is floored, so none of them can pass by finding nothing.**
## That is not ceremony: `palette_cycle` sat outside `ALL` for its whole life and
## carried four reds nobody saw, and a harness that passes over an empty set is
## the same failure with better manners. Each floor is a count this corpus
## actually has, so the check fails if a scan silently stops reaching the data.
##
## What each title contributes, measured 2026-08-12:
##
##   piposh-ru      3 CLUT chunks and 3 palette members -- the only custom
##                  palettes in any shipped title, so it alone can exercise the
##                  reversed-read bug that `from_clut` was corrected for
##   piposh-dream   167 bitmaps naming member 154, which is not a palette
##   all six        ~40,000 bitmaps naming a built-in, and one default per movie
##
## The built-in half is the coverage that never existed anywhere. Every title
## leans on it for effectively all of its artwork, and until this file nothing
## asserted that the ids they name are ids the engine can even build.

const Harness := preload("res://tools/lib/harness.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const PaletteView := preload("res://scenes/preview/palette_view.gd")
const Config := preload("res://director/director_config.gd")

const GAMES_DIR := "res://games"

## Floors, not expectations. Each is well under what the corpus holds today, so
## they catch a scan that broke rather than a title that changed.
const MIN_ROOTS := 6
const MIN_CONTAINERS := 400
const MIN_BUILTIN_SITES := 5000
const MIN_CLUT_CHUNKS := 1
const MIN_PALETTE_MEMBERS := 1
const MIN_DEFAULTS := 20
## Measured 81, in `piposh-dream`'s six movies declaring the Windows D5 default.
const MIN_DANGLING_OFF_MAC := 40

## Both ink passes treat "every channel at or above this" as paper, the same
## number `palette_members.gd` and `director_bitmaps.gd` use.
const PAPER_MIN_BYTE := 241

## Bitmap. Palette members are `Palette.MEMBER_TYPE`.
const BITMAP_TYPE := 1


static func _is_paper(table: PackedByteArray, index: int) -> bool:
	return table[index * 3] >= PAPER_MIN_BYTE \
		and table[index * 3 + 1] >= PAPER_MIN_BYTE \
		and table[index * 3 + 2] >= PAPER_MIN_BYTE


func _init() -> void:
	var h := Harness.new()

	var roots := 0
	var containers := 0
	var clut_chunks := 0
	var palette_members := 0

	# Custom palettes, and the two directions of the reversed-read bug.
	var short_tables: Array[String] = []
	var paper_wrong: Array[String] = []
	var ink_wrong: Array[String] = []

	# Bitmaps naming a palette by member number, and what happens when the member
	# they name is not a palette. See the check for why that is not a failure.
	var naming_member := 0
	var naming_dangling := 0
	var dangling_wrong: Array[String] = []
	var dangling_wrong_count := 0
	# Of the dangling ones, those in a movie whose stage is *not* system Mac.
	# These are the only members the fallback rule can be observed on, so a floor
	# on them is what stops the check below passing over nothing.
	var dangling_off_mac := 0

	# Bitmaps naming a built-in, and whether the engine can build it.
	var naming_builtin := 0
	var builtin_ids: Dictionary = {}
	var builtin_unbuildable: Array[String] = []

	# Movie defaults, same question.
	var defaults := 0
	var default_unbuildable: Array[String] = []

	# What the renderer would actually hand the decoder for each bitmap.
	var chosen_checked := 0
	var chosen_wrong: Array[String] = []

	var system := Palette.system_mac()

	var games := DirAccess.open(GAMES_DIR)
	if games == null:
		h.begin("the corpus is reachable")
		h.check("res://games opens", false, "DirAccess could not open " + GAMES_DIR)
		h.complete("the corpus is reachable")
		quit(h.finish("palettes across every shipped title"))
		return

	for sub in games.get_directories():
		var paths := Paths.new()
		paths.root = GAMES_DIR.path_join(sub)
		var reached_any := false
		for relative in paths.containers():
			var path := paths.resolve(str(relative))
			if path == "":
				continue
			var movie := ContainerFile.new()
			if not movie.open(path):
				continue
			reached_any = true
			containers += 1
			clut_chunks += movie.ids_of("CLUT").size()

			# The stage this movie actually starts on, which is what a member whose
			# own palette does not resolve is drawn against if the fallback is
			# wrong. Read per movie rather than assumed, because six of
			# `piposh-dream`'s movies declare the Windows D5 table and the rest
			# declare system Mac -- and a check handed system Mac as the stage
			# cannot tell the two fallbacks apart at all.
			var stage_id := Palette.SYSTEM_MAC
			var config = Config.new()
			if config.read(movie):
				defaults += 1
				var d := int(config.default_palette)
				stage_id = d
				if d < 0 and not Palette.can_build(d):
					default_unbuildable.append("%s -> %d" % [path.get_file(), d])
			var stage_table := Palette.builtin(stage_id)

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
							where, Palette.PAPER_INDEX, built[0], built[1], built[2]])
					# The other end, which is what pins the *direction* rather
					# than the brightness: a reversed read swaps these two, so a
					# merely dim palette must not satisfy the first check.
					if _is_paper(built, Palette.INK_INDEX):
						ink_wrong.append("%s: index %d is white too" % [where, Palette.INK_INDEX])
					continue

				if type_code != BITMAP_TYPE:
					continue

				var clut := int(m.get("palette_id", Palette.SYSTEM_MAC))
				if clut < 0:
					naming_builtin += 1
					builtin_ids[clut] = int(builtin_ids.get(clut, 0)) + 1
					if not Palette.can_build(clut):
						if builtin_unbuildable.size() < 8:
							builtin_unbuildable.append("%s #%d -> %d" % [path.get_file(), n, clut])
				elif clut > 0:
					naming_member += 1
					# `-1` is not garbage: the reference reads the clut cast
					# library as a signed word and treats -1 as "the member's own
					# library" (castmember/bitmap.cpp, `if (clutCastLib == -1)`).
					var lib := int(m.get("palette_lib", 0))
					var owner: Dictionary = table.get_member(lib if lib > 0 else 1, clut)
					if owner.is_empty() or int(owner.get("type", 0)) != Palette.MEMBER_TYPE:
						naming_dangling += 1
						# The engine's obligation, and the only part of this that
						# is the port's to get right: the reference substitutes
						# **system Mac** for a palette it has not loaded, not the
						# palette the stage happens to be holding
						# (`castmember/bitmap.cpp:484`).
						#
						# **Handed this movie's own stage, not system Mac.** For as
						# long as this passed `system` as the stage it could not
						# fail: both readings return the same bytes when the stage
						# *is* system Mac, so the check agreed with itself while
						# 81 members drew in the Windows table (`bugs.md` 104).
						var fallback := PaletteView.table_for_member(
							m, table, stage_table, stage_id)
						if stage_id != Palette.SYSTEM_MAC:
							dangling_off_mac += 1
						if fallback != system:
							# Counted apart from the examples: the list is capped,
							# and a capped list read as a count is how two tools in
							# this repo reported 12 of 66 differences as if 12 were
							# the whole of it.
							dangling_wrong_count += 1
							if dangling_wrong.size() < 8:
								dangling_wrong.append(
									"%s #%d -> lib %d member %d, stage %d" % [
										path.get_file(), n, lib, clut, stage_id])

				# Whatever the renderer resolves for this member has to be a
				# table the decoder can use. A member that resolves to nothing,
				# or to a short table, produces no pixels and no error.
				var resolved := PaletteView.table_for_member(m, table, system, Palette.SYSTEM_MAC)
				chosen_checked += 1
				if resolved.size() != Palette.TABLE_BYTES:
					if chosen_wrong.size() < 8:
						chosen_wrong.append("%s #%d -> %d bytes" % [
							path.get_file(), n, resolved.size()])
			movie.close()
		if reached_any:
			roots += 1

	print("roots                     : %d" % roots)
	print("containers                : %d" % containers)
	print("CLUT chunks               : %d" % clut_chunks)
	print("palette cast members      : %d" % palette_members)
	print("bitmaps naming a member   : %d" % naming_member)
	print("bitmaps naming a built-in : %d %s" % [naming_builtin, str(builtin_ids)])
	print("movie defaults            : %d" % defaults)
	print("members resolved          : %d" % chosen_checked)

	# ------------------------------------------------------- the scan itself
	h.begin("the scan reached the corpus")
	h.check(
		"reached %d roots and %d containers (floors %d/%d)"
			% [roots, containers, MIN_ROOTS, MIN_CONTAINERS],
		roots >= MIN_ROOTS and containers >= MIN_CONTAINERS,
		"a scan that stopped reaching the data would make every check below pass over nothing")
	h.complete("the scan reached the corpus")

	# -------------------------------------------------------- custom palettes
	h.begin("a CLUT is read the right way up")
	h.check(
		"the corpus ships CLUT chunks (%d, floor %d)" % [clut_chunks, MIN_CLUT_CHUNKS],
		clut_chunks >= MIN_CLUT_CHUNKS,
		"only piposh-ru has any; if this hits 0 the corpus moved, not the reader")
	h.check(
		"the corpus ships palette cast members (%d, floor %d)"
			% [palette_members, MIN_PALETTE_MEMBERS],
		palette_members >= MIN_PALETTE_MEMBERS,
		"")
	h.check(
		"every palette member builds a %d-byte table" % Palette.TABLE_BYTES,
		short_tables.is_empty(),
		"%d short: %s" % [short_tables.size(), ", ".join(short_tables.slice(0, 4))])
	h.check(
		"paper (index %d) is white in every palette" % Palette.PAPER_INDEX,
		paper_wrong.is_empty(),
		"%d are not: %s" % [paper_wrong.size(), ", ".join(paper_wrong.slice(0, 4))])
	h.check(
		"index %d is not white in any palette" % Palette.INK_INDEX,
		ink_wrong.is_empty(),
		"%d are: %s" % [ink_wrong.size(), ", ".join(ink_wrong.slice(0, 4))])
	h.complete("a CLUT is read the right way up")

	# ------------------------------------------------------- built-in palettes
	h.begin("every palette a bitmap names is one the engine can produce")
	h.check(
		"bitmaps name a built-in at %d sites (floor %d)"
			% [naming_builtin, MIN_BUILTIN_SITES],
		naming_builtin >= MIN_BUILTIN_SITES,
		"effectively all artwork in all six titles goes through this")
	h.check(
		"every built-in id named is one the engine can build",
		builtin_unbuildable.is_empty(),
		"%d cannot: %s" % [builtin_unbuildable.size(), ", ".join(builtin_unbuildable.slice(0, 4))])
	# **This deliberately does not assert that the named member IS a palette**,
	# and the first version of this file did, which was wrong. `piposh-dream` has
	# 167 bitmaps naming member 154, which is a type-2 member. That is bad
	# authoring in a shipped title, not a defect in this port: the container
	# states file version 0x57E, so the D5 layout the reader uses is the right
	# one, and the reference resolves the same pair to the same non-palette.
	# Nothing here can fix another company's 1990s cast, so asserting it would
	# have gated this project on data it does not own -- and it would have gone
	# red for ever while measuring nothing about the engine.
	#
	# What IS the port's to get right is the fallback, so that is what is checked.
	h.check(
		"bitmaps name a palette by member number at %d sites, %d of them dangling"
			% [naming_member, naming_dangling],
		naming_member > 0,
		"if this reaches 0 the clut field stopped being read, which is how it "
			+ "failed before: reading the cast library instead answers -1 everywhere")
	# The floor is what makes the check below mean anything: the rule is only
	# observable on a member whose movie is on some *other* palette, and handing
	# system Mac in as the stage is how the previous version of this passed while
	# the engine had it wrong.
	h.check(
		"%d dangling member(s) sit in a movie not on system Mac (floor %d)"
			% [dangling_off_mac, MIN_DANGLING_OFF_MAC],
		dangling_off_mac >= MIN_DANGLING_OFF_MAC,
		"piposh-dream's six Windows-default movies hold these; with none of them "
			+ "reached, the fallback check agrees with itself and proves nothing")
	h.check(
		"a bitmap naming a member that is not a palette falls back to system Mac",
		dangling_wrong.is_empty(),
		"%d of %d fall back to the stage instead, first %d: %s"
			% [dangling_wrong_count, naming_dangling, dangling_wrong.size(),
				", ".join(dangling_wrong)])
	h.complete("every palette a bitmap names is one the engine can produce")

	# -------------------------------------------------------- movie defaults
	h.begin("every movie's default palette resolves")
	h.check(
		"movies declare a default palette (%d, floor %d)" % [defaults, MIN_DEFAULTS],
		defaults >= MIN_DEFAULTS,
		"")
	h.check(
		"every declared default is one the engine can build",
		default_unbuildable.is_empty(),
		"%d cannot: %s" % [default_unbuildable.size(), ", ".join(default_unbuildable.slice(0, 4))])
	h.complete("every movie's default palette resolves")

	# ------------------------------------------------ what reaches the decoder
	h.begin("every bitmap resolves to a usable table")
	h.check(
		"the renderer was asked for %d members (floor %d)"
			% [chosen_checked, MIN_BUILTIN_SITES],
		chosen_checked >= MIN_BUILTIN_SITES,
		"")
	h.check(
		"every member resolves to a %d-byte table" % Palette.TABLE_BYTES,
		chosen_wrong.is_empty(),
		"%d do not: %s" % [chosen_wrong.size(), ", ".join(chosen_wrong.slice(0, 4))])
	h.complete("every bitmap resolves to a usable table")

	quit(h.finish("palettes across every shipped title"))
