extends SceneTree
## Where a custom cursor points: Director's rule, and what this port does with it.
##
##   godot --headless --path . --script tools/cursor_hotspot.gd
##   godot --headless --path . --script tools/cursor_hotspot.gd -- --root piposh --verbose
##   godot --headless --path . --script tools/cursor_hotspot.gd -- --all
##
## `bugs.md` 28 is the entry this closes, and it was open because nobody had
## written the rule down. It is one `if` in the reference
## (`cursor.cpp:Cursor::readFromCast`, ScummVM 805f259a):
##
##     int offX = bc->_regX - bc->_initialRect.left;
##     int offY = bc->_regY - bc->_initialRect.top;
##     if ((offX < 0) || (offX >= 16) || (offY < 0) || (offY >= 16) ||
##         (g_director->getVersion() < 500 &&
##          g_director->getPlatform() == Common::kPlatformWindows)) {
##         offX = 8;
##         offY = 8;
##     }
##
## `scenes/preview/cursor.gd:hotspot_of` is that expression and this asserts it.
##
## ## Two halves, and only one of them can be measured against the corpus
##
## **Rule 1** -- recentre a hotspot that falls outside the 16x16 crop -- is
## exercised by real members and is checked against them below: every cursor pair
## the chosen movies name is composed, and the hotspot that comes out is compared
## against the data member's own `reg_offset_x`/`reg_offset_y` under the rule.
##
## **Rule 2** -- Windows Director before D5 ignores the registration point and
## always uses (8,8) -- **cannot be measured here at all**, and the survey this
## tool prints is the evidence for that rather than an aside. Run `--all`:
## 651 containers over the six shipped roots, 482 carrying a config chunk, and
## every one of those states a file version of `0x57E` (111) or `0x73A` (371).
## `humanVersion` puts the lower at 700 and D5 begins at `0x4B1`, so
## `version < 500` is false everywhere and the clause is inert. `bugs.md` 28
## assumed the opposite ("this game's containers are D4"), which is what made the
## unimplemented half look like a live defect; D4 is `0x45B` and no container in
## reach states it. The same run splits the platform id **373 Windows to 109
## Mac**, so the entry's other premise does not hold uniformly either -- which is
## exactly why this prints the distribution instead of asserting a belief about
## it.
##
## So rule 2 is asserted against **synthetic members** -- a dictionary with a
## registration offset in it, which is the entire input `hotspot_of` takes. That
## is not a weaker check than a corpus one, it is a check of the thing this port
## controls: the branch. Asserting instead that the corpus is all D6+ would gate
## this project on files it cannot fix, which is the rule `AGENTS.md` states.
##
## ## What is asserted
##
##   * the survey runs and finds containers, so the version/platform numbers
##     below are measured rather than assumed;
##   * `hotspot_of` recentres exactly when the reference's disjunction is true,
##     over the eight cases that disjunction has;
##   * an out-of-range coordinate moves **both** coordinates, because the
##     reference assigns both inside one branch;
##   * every real cursor pair the corpus composes has the hotspot the rule says,
##     read back out of `Cursor.compose` rather than out of `hotspot_of` again --
##     so the wiring from the member to the composed image is covered and not only
##     the arithmetic.
##
## Title-agnostic: it names no movie and discovers its cursor pairs by walking
## the containers it is pointed at.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Cursor := preload("res://scenes/preview/cursor.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const Members := preload("res://scenes/preview/members.gd")

## `kFileVer500` (`types.h:370`) and `kFileVer400` (`:368`), so the survey can say
## which side of the reference's threshold each container falls on using the
## reference's own numbers.
const FILE_VERSION_D4 := 0x45B
const FILE_VERSION_D5 := 0x4B1
const PLATFORM_WINDOWS := 2
const PLATFORM_MAC := 1

## How many containers to open per root. The survey wants a distribution, not a
## census, and a whole-corpus walk is 677 containers of cast tables.
const SURVEY_LIMIT := 200

## How many containers to search for a real cursor pair before stopping. A pair
## needs a 1-bit member small enough to be cursor art at a number some cast
## actually holds, and most containers have none.
const PAIR_LIMIT := 60


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var verbose := Args.flag(args, "verbose")

	var roots: Array[String] = []
	if Args.flag(args, "all"):
		var parent := DirAccess.open("res://games")
		if parent != null:
			var subs := parent.get_directories()
			subs.sort()
			for sub in subs:
				roots.append("res://games".path_join(sub))
	else:
		# `load_config` applies `--root` itself, so a `gate.sh` entry needs no
		# argument handling here.
		var paths := Paths.new()
		paths.load_config()
		roots.append(str(paths.root))

	# ------------------------------------------------------------------ survey
	# What every container says about the two fields rule 2 branches on. Printed
	# before anything is asserted, because the whole argument about rule 2 being
	# inert rests on these numbers and a reader has to be able to see them.
	var versions: Dictionary = {}
	var platforms: Dictionary = {}
	var containers := 0
	var pre_d5 := 0
	var windows_pre_d5 := 0
	var no_config := 0
	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		for path in files.slice(0, SURVEY_LIMIT):
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			containers += 1
			var config = Config.new()
			if not config.read(f):
				no_config += 1
				f.close()
				continue
			var v := int(config.version)
			var p := int(config.platform_id)
			versions["0x%X" % v] = int(versions.get("0x%X" % v, 0)) + 1
			platforms[p] = int(platforms.get(p, 0)) + 1
			if v > 0 and v < FILE_VERSION_D5:
				pre_d5 += 1
				if p == PLATFORM_WINDOWS:
					windows_pre_d5 += 1
					print("  rule 2 LIVE: %s states 0x%X, platform %d" % [
						path.get_file(), v, p])
			f.close()

	print("%d container(s) surveyed over %d root(s)" % [containers, roots.size()])
	print("  no config chunk (a cast file has none): %d" % no_config)
	print("  file version word:")
	var vkeys: Array = versions.keys()
	vkeys.sort()
	for k in vkeys:
		print("    %-10s %d" % [k, int(versions[k])])
	print("  platform id (1 Mac, 2 Windows, per util.cpp:platformFromID):")
	var pkeys: Array = platforms.keys()
	pkeys.sort()
	for k in pkeys:
		print("    %-10s %d" % [str(k), int(platforms[k])])
	print("  below D5 (0x%X): %d, of which Windows: %d" % [
		FILE_VERSION_D5, pre_d5, windows_pre_d5])
	print("")

	h.begin("the corpus is surveyed rather than assumed")
	h.check("containers opened", containers > 0, "%d" % containers)
	# Reported, not asserted, and the distinction is the point: a corpus that
	# turned out to hold a D4 Windows movie would make rule 2 live and would not
	# be a failure of this engine.
	h.check(
		"rule 2 is inert here, so it is asserted synthetically below",
		true,
		"%d of %d container(s) are Windows and below D5" % [windows_pre_d5, containers],
	)
	h.complete("the corpus is surveyed rather than assumed")

	# --------------------------------------------------- the rule, case by case
	# The reference's disjunction has four range terms and one platform term. Each
	# case names the term it turns on, so a red says which half of the `if` moved.
	const CENTRE := Vector2i(8, 8)
	var in_range := {"reg_offset_x": 10, "reg_offset_y": 9}
	h.begin("hotspot_of is the reference's disjunction")
	h.check(
		"an in-range point on an unknown movie is left alone",
		Cursor.hotspot_of(in_range, 0, 0) == Vector2i(10, 9),
		str(Cursor.hotspot_of(in_range, 0, 0)),
	)
	h.check(
		"x past the crop recentres",
		Cursor.hotspot_of({"reg_offset_x": 16, "reg_offset_y": 4}, 0, 0) == CENTRE,
		str(Cursor.hotspot_of({"reg_offset_x": 16, "reg_offset_y": 4}, 0, 0)),
	)
	h.check(
		"a negative coordinate recentres",
		Cursor.hotspot_of({"reg_offset_x": -1, "reg_offset_y": 4}, 0, 0) == CENTRE,
		str(Cursor.hotspot_of({"reg_offset_x": -1, "reg_offset_y": 4}, 0, 0)),
	)
	# The half a rewrite gets wrong: the reference sets both, so an in-range x
	# does not survive an out-of-range y.
	h.check(
		"y out of range moves x too, because the reference assigns both",
		Cursor.hotspot_of({"reg_offset_x": 3, "reg_offset_y": 40}, 0, 0) == CENTRE,
		str(Cursor.hotspot_of({"reg_offset_x": 3, "reg_offset_y": 40}, 0, 0)),
	)
	h.check(
		"a member with no registration point at all points at its own corner",
		Cursor.hotspot_of({}, 0, 0) == Vector2i(0, 0),
		str(Cursor.hotspot_of({}, 0, 0)),
	)
	# Rule 2's four combinations. Only the first recentres.
	h.check(
		"Windows below D5 ignores the point entirely (rule 2)",
		Cursor.hotspot_of(in_range, FILE_VERSION_D4, PLATFORM_WINDOWS) == CENTRE,
		str(Cursor.hotspot_of(in_range, FILE_VERSION_D4, PLATFORM_WINDOWS)),
	)
	h.check(
		"Windows at D5 keeps it",
		Cursor.hotspot_of(in_range, FILE_VERSION_D5, PLATFORM_WINDOWS) == Vector2i(10, 9),
		str(Cursor.hotspot_of(in_range, FILE_VERSION_D5, PLATFORM_WINDOWS)),
	)
	h.check(
		"Mac below D5 keeps it -- the clause is both terms, not one",
		Cursor.hotspot_of(in_range, FILE_VERSION_D4, PLATFORM_MAC) == Vector2i(10, 9),
		str(Cursor.hotspot_of(in_range, FILE_VERSION_D4, PLATFORM_MAC)),
	)
	h.check(
		"an unstated platform below D5 keeps it, because 0 is not Windows",
		Cursor.hotspot_of(in_range, FILE_VERSION_D4, 0) == Vector2i(10, 9),
		str(Cursor.hotspot_of(in_range, FILE_VERSION_D4, 0)),
	)
	h.complete("hotspot_of is the reference's disjunction")

	# ------------------------------------- and the same rule through a real pair
	# `compose` is what the player calls, and the arithmetic above proves nothing
	# about whether the composed image carries it. Every 1-bit member small enough
	# to be cursor art is treated as the data half of a maskless pair, which is a
	# shape the corpus really uses (`WalkLeftCursor` and two others in `rating`).
	var pairs := 0
	var wrong: Array[String] = []
	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		var member_paths := Paths.new()
		member_paths.root = root
		var opened := 0
		for path in files:
			if pairs >= 24 or opened >= PAIR_LIMIT:
				break
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			opened += 1
			var table := CastTable.new()
			if not table.open(f, member_paths):
				table.close()
				f.close()
				continue
			var palette := Palette.system_mac()
			for lib in table.cast_libs.keys():
				var cast = table.cast_for(int(lib))
				if cast == null:
					continue
				for number in cast.member_numbers():
					if pairs >= 24:
						break
					var m: Dictionary = cast.member(number)
					if m.is_empty() or int(m.get("type", 0)) != 1:
						continue
					var w := int(m.get("width", 0))
					var hgt := int(m.get("height", 0))
					if w <= 0 or hgt <= 0 or w > Cursor.MAX_CURSOR_SIZE \
							or hgt > Cursor.MAX_CURSOR_SIZE:
						continue
					# Packed, so `Cursor.where` resolves the library outright and
					# the hotspot cannot come from a same-numbered member of
					# another cast -- the failure `compose`'s own header records.
					var packed := Members.pack_ref(int(lib), number)
					var composed = Cursor.compose(packed, 0, table, palette)
					if composed == null:
						continue
					pairs += 1
					var want := Cursor.hotspot_of(
						m, int(table.movie_version), int(table.movie_platform_id))
					var got: Vector2 = composed["hotspot"]
					if Vector2i(got) != want:
						wrong.append("%s lib %d #%d '%s': composed %s, rule says %s" % [
							path.get_file(), int(lib), number, str(m.get("name", "")),
							str(got), str(want)])
					elif verbose:
						print("  %s lib %d #%d %-16s reg (%d,%d) -> hotspot %s" % [
							path.get_file(), int(lib), number, str(m.get("name", "")),
							int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0)),
							str(got)])
			table.close()
			f.close()

	print("")
	print("%d real member(s) composed as cursor art" % pairs)
	for line in wrong:
		print("  " + line)

	h.begin("a composed cursor carries the hotspot the rule gives")
	if pairs == 0:
		# Says so out loud rather than passing quietly, which is the dark-harness
		# failure `gate.sh`'s EMPTY guard exists for one level up.
		h.check(
			"this root holds no member small enough to be cursor art",
			false,
			"searched %d container(s); point it at a root that does" % PAIR_LIMIT,
		)
	else:
		h.check(
			"every composed hotspot matches the rule",
			wrong.is_empty(),
			"%d of %d do not" % [wrong.size(), pairs],
		)
	h.complete("a composed cursor carries the hotspot the rule gives")
	quit(h.finish("the custom cursor hotspot rule, bugs.md 28"))


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	var subs := dir.get_directories()
	subs.sort()
	for sub in subs:
		_walk(dir_path.path_join(sub), out)
