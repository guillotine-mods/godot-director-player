extends SceneTree
## A cast library embedded in the movie's own container must be able to hand out
## its members' payload chunks.
##
##   godot --headless --audio-driver Dummy --path . --script tools/embedded_cast_payload.gd
##   godot --headless --audio-driver Dummy --path . --script tools/embedded_cast_payload.gd -- --roots res://games/piposh2
##
## **This currently FAILS, and it is the reproduction for the cast-table bug it
## reports.** It is deliberately not in `gate.sh`'s `ALL`: the suite is green and a
## standing red teaches everyone to read past reds. Put it in `ALL` in the same
## commit that fixes `DirectorCastTable.file_for`.
##
## ## What is wrong
##
## A Director movie can carry **more than one cast library inside its own
## container**. `MCsL` names them and gives each a `castID`; a library with an
## empty path is one of those, and `DirectorCastTable._cast_for` opens it
## correctly by matching that `castID` against the `KEY*` owner of each `CAS*`.
## Members resolve, names resolve, types resolve.
##
## `file_for()` then answers **null** for every one of them, because it looks the
## library up in `_by_path`, and `_by_path` is only ever written by the *external*
## `.cst` arm. An embedded library sets `resolved_path` to the movie's own file and
## is never registered, so the lookup misses and the function falls through to
## `return _movie if cast_lib == 1 else null`.
##
## `file_for` is how every payload in the engine is fetched —
## `preview/sprite_art.gd:89` for a bitmap's `BITD`, `preview/palette_view.gd:80`
## for a `CLUT`, `preview/film_loop_view.gd:66` for a loop's `SCVW`,
## `preview/sound.gd` and `preview/media.gd` for a sound's samples, and
## `DirectorCastTable.member_payload_size` for `the size of member`. So a member
## of an embedded library **resolves, reports its name and type and rect, and
## draws or plays nothing.**
##
## ## What it costs, measured
##
## Members with a payload chunk sitting behind that null, per root:
##
##   games/piposh2            290 bitmap, 4 filmLoop
##   games/piposh              43 bitmap
##   games/piposh-dream        23 bitmap
##   test-games/itamar-magichat  437 bitmap, 1 filmLoop, 48 sound
##   test-games/itamar-park     76 bitmap, 30 field, 17 palette
##
## The 48 sounds are the "48 of Magic Hat's 87 sound `CASt` chunks are addressable
## by neither cast walk" report, and the report was half wrong: **all 87 are
## addressable.** `tools/member_type_census.gd` reconciles the raw `CASt` scan
## against a *first-`CAS*`* walk, which is not what the player uses — Magic Hat's
## `hats.dir` holds six `CAS*` chunks and that walk sees one of them. Through
## `DirectorCastTable` every one of the 87 is reached, and it is only their bytes
## that are not.
##
## The reason the sound census reported 39 is this bug and not the walk: it skips
## a library whose `file_for` is null, so it skipped exactly the six embedded
## sound libraries and counted the three standalone `.cst` files.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")

const CORPUS_DIRS := ["res://games", "res://test-games"]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

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
				roots.append(str(parent).path_join(sub))
	roots.sort()

	var libs := 0
	var dark := 0
	var lost: Dictionary = {}
	var where: Array[String] = []
	for root in roots:
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		var member_paths := Paths.new()
		member_paths.root = root
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var table := CastTable.new()
			if table.open(f, member_paths):
				for lib in table.cast_libs.keys():
					if int(lib) == 1:
						continue
					var entry: Dictionary = table.cast_libs[lib]
					var cast = table.cast_for(int(lib))
					# Embedded: named by `MCsL` with no file path of its own, opened
					# out of this same container by its `castID`.
					if cast == null or str(entry.get("path", "")) != "":
						continue
					libs += 1
					if table.file_for(int(lib)) != null:
						continue
					dark += 1
					var here := 0
					for number in cast.member_numbers():
						var m: Dictionary = cast.member(number)
						if int(m.get("data_chunk_id", -1)) < 0:
							continue
						here += 1
						var kind := str(m.get("type_name", ""))
						lost[kind] = int(lost.get(kind, 0)) + 1
					where.append("%s %s lib%d '%s' (castID %s, CAS*%d): %d member(s) with a payload"
						% [str(root).get_file(), path.get_file(), int(lib),
							str(entry.get("name", "")), str(entry.get("id", -1)),
							int(cast.cas_chunk_id), here])
			table.close()
			f.close()

	print("")
	print("%d cast librar(ies) embedded in a movie's own container; %d cannot hand out a payload"
		% [libs, dark])
	var kinds: Array = lost.keys()
	kinds.sort()
	for kind in kinds:
		print("  %-12s %d member(s) with a payload chunk behind that null" % [kind, int(lost[kind])])
	for line in where:
		print("  %s" % line)

	h.begin("an embedded cast library can hand out its members' payload chunks")
	h.check("the walk found an embedded library at all", libs >= 1,
		"%d found; 0 means the MCsL walk broke, not that the corpus changed" % libs)
	h.check("every one of them answers file_for()", dark == 0,
		"%d of %d answer null, hiding %d member payload(s)"
			% [dark, libs, _total(lost)])
	h.complete("an embedded cast library can hand out its members' payload chunks")

	quit(h.finish("DirectorCastTable.file_for for a library embedded in the movie's container"))


func _total(counts: Dictionary) -> int:
	var sum := 0
	for k in counts:
		sum += int(counts[k])
	return sum


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		var lower := str(name).to_lower()
		if lower.ends_with(".dir") or lower.ends_with(".cst") \
				or lower.ends_with(".dxr") or lower.ends_with(".cxt"):
			out.append(dir_path.path_join(name))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
