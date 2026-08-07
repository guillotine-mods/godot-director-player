extends SceneTree
## Does every film-loop child draw out of the cast its own container named?
##
##   godot --headless --path . --script tools/film_loop_cast.gd
##   godot --headless --path . --script tools/film_loop_cast.gd -- --verbose
##
## This is the harness for a bug class that has now bitten five times and had no
## gate on it: **a member number is per cast, so resolving one in the wrong
## library returns a stranger rather than nothing.** `searchfunk` reading names
## in library 1, the `island2` members, the film-loop `won`/`wonder` prefix
## match, frame scripts found in whichever cast shared the number, and now a
## loop's `ccl ` index read one entry along and against the wrong file's list.
## Every one of them drew or ran something real and wrong, which is why nothing
## reported an error.
##
## A film loop is the sharpest case, because its children carry a `ccl `
## **index** and not a cast-library number, the two orders differ, and the
## container that owns the list is the loop's own rather than the movie's. Get
## any of that wrong and the child lands on a member that exists.
##
## ### The oracle
##
## A harness for this class must not be able to agree with the code by
## construction, so the expected cast comes from **outside the resolution rule**:
## a child whose stretch flag is clear carries a recorded rect equal to its
## member's natural size (`docs/bugs-closed.md`, the film-loop stretch entry — of
## 2,053 flagged children zero have a rect equal to their member, which is what
## identifies the flag). So ask which of the movie's libraries holds that member
## number *at exactly that size*. Where exactly one does, that is the answer.
## Where none or several do, the child is counted and not asserted.
##
## ### Two populations, because only one of them is a lookup
##
## A child carrying an index is a *choice*: the list, its order and its base all
## have to be right. Those are asserted outright, and any disagreement fails.
##
## A child carrying `0xFFFF` names its own cast and there is nothing to choose,
## so the oracle can only disagree with the **data**. It does, six times, all in
## GARDUG's `Internal:57 L` — a loop whose children are numbered for the
## `heznigt` library embedded beside the internal one in the same file, while the
## record says "my own cast" and GARDUG's `ccl ` is a single zero-length entry.
## No reading of that container can reach `heznigt`; only guessing by
## plausibility can, which is the whole mistake this file exists to catch. So the
## check that applies is narrower and still falsifiable: **a disputed own-cast
## child must be in a loop no score in the corpus ever plays.** GARDUG's score
## puts `1:56` and `1:68` on channels and never `1:57`. Break own-cast handling
## for a loop that is actually played and this goes red.
##
## Reverting any one part of the fix turns the first check red:
## `DirectorScore.cast_lib_raw`, the zero-based index in
## `DirectorFilmLoop.children`, the offset-table read in
## `DirectorFilmLoop.read_cast_list`, or `DirectorCastTable.cast_list_for`
## answering with the loop's own container's list.
##
## Title-agnostic: it sweeps whatever `director_game.cfg` points at and names no
## movie, cast or member of its own.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const FilmLoop := preload("res://director/director_film_loop.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Score := preload("res://director/director_score.gd")

const LOOP_TYPE := 2

var _verbose := false


func _init() -> void:
	var args := Args.parse()
	_verbose = Args.flag(args, "verbose")
	var h := Harness.new()

	var paths = Paths.new()
	if not paths.load_config():
		print("FAIL  no game configured")
		quit(1)
		return

	var movies: Array = []
	for rel in paths.containers():
		if str(rel).get_extension().to_lower() == "dir":
			movies.append(str(rel))

	h.begin("an indexed child resolves in the cast its own container's ccl names")
	h.begin("a disputed own-cast child is in a loop no score plays")
	h.begin("a loop's ccl list is its own container's")
	h.begin("every ccl entry names a cast the movie can address")

	var tally := {
		"children": 0, "loops": 0, "indexed": 0, "indexed_decisive": 0,
		"indexed_wrong": 0, "own": 0, "own_decisive": 0, "own_disputed": 0,
		"own_disputed_played": 0, "borrowed": 0, "unnameable": 0,
	}
	var lines: Array[String] = []

	for rel in movies:
		_sweep(paths, str(rel), tally, lines)

	for line in lines.slice(0, 40):
		print("     %s" % line)

	# The population is asserted alongside the failures, because "0 wrong" is
	# also what a check with nothing left to look at prints. Drop
	# `DirectorScore.cast_lib_raw` and every child reads as its own cast: the
	# indexed population goes to zero and this check would otherwise pass while
	# the whole `ccl ` path had stopped being exercised.
	h.check("indexed children resolve where their size says they do",
		int(tally["indexed_wrong"]) == 0 and int(tally["indexed_decisive"]) > 0,
		"%d of %d decided, from %d indexed children in %d loops across %d movies"
			% [int(tally["indexed_wrong"]), int(tally["indexed_decisive"]),
				int(tally["indexed"]), int(tally["loops"]), movies.size()])
	h.complete("an indexed child resolves in the cast its own container's ccl names")

	h.check("no played loop's own-cast child contradicts its size",
		int(tally["own_disputed_played"]) == 0,
		"%d of %d decided own-cast children disputed, %d of them in a loop a score plays"
			% [int(tally["own_disputed"]), int(tally["own_decisive"]),
				int(tally["own_disputed_played"])])
	h.complete("a disputed own-cast child is in a loop no score plays")

	h.check("a loop in a linked cast is read against that cast's own list",
		int(tally["borrowed"]) == 0,
		"%d libraries answered with a list that is not their container's"
			% int(tally["borrowed"]))
	h.complete("a loop's ccl list is its own container's")

	# A `ccl ` entry the movie's libraries cannot name is how a parse failure
	# hides: a truncated or shifted list still yields plausible strings, and the
	# only thing that says so is that they match no linked cast. This is what
	# `...\PIP2DATA\won` looked like, and matching it as a prefix of `wonder` is
	# how it drew somebody else's animation instead of failing.
	h.check("every ccl entry matches a linked cast",
		int(tally["unnameable"]) == 0,
		"%d ccl entries name no library of the movie that reaches them"
			% int(tally["unnameable"]))
	h.complete("every ccl entry names a cast the movie can address")

	quit(h.finish("film-loop children resolve in the cast their own container named"))


func _sweep(paths, rel: String, tally: Dictionary, lines: Array[String]) -> void:
	var movie_path: String = paths.resolve(rel)
	var f := ContainerFile.new()
	if not f.open(movie_path):
		return
	var table = CastTable.new()
	if not table.open(f, paths):
		f.close()
		return
	for n in table.cast_libs:
		table.cast_for(int(n))

	var by_name := {}
	for n in table.cast_libs:
		by_name[str(table.cast_libs[n].get("name", "")).to_lower()] = int(n)

	# Only built when something is disputed, which is normally never.
	var played: Dictionary = {}
	var played_read := false

	for n in table.cast_libs:
		var lib := int(n)
		var cast = table.cast_for(lib)
		var file = table.file_for(lib)
		if cast == null or file == null:
			continue

		var own_list: PackedStringArray = table.cast_list_for(lib)
		if str(own_list) != str(_list_of(file)):
			tally["borrowed"] = int(tally["borrowed"]) + 1
			lines.append("%s  lib %d's ccl list is not %s's" % [
				rel, lib, str(file.path).get_file()])
		for entry in own_list:
			if str(entry).strip_edges() == "":
				continue
			if _lib_of(by_name, str(entry)) < 0:
				tally["unnameable"] = int(tally["unnameable"]) + 1
				lines.append("%s  ccl entry %s names no linked cast" % [rel, str(entry)])

		for number in range(1, cast.member_count + 2):
			var m: Dictionary = cast.member(number)
			if m.is_empty() or int(m.get("type", 0)) != LOOP_TYPE:
				continue
			if int(m.get("data_chunk_id", -1)) < 0:
				continue
			# Through the preview's own entry point, so what is asserted is what
			# the player draws rather than a second reading written here.
			var loop = FilmLoopView.open_loop(lib, m, table)
			if loop == null:
				continue
			tally["loops"] = int(tally["loops"]) + 1
			var seen := {}
			for i in loop.frame_count:
				for kid in loop.children(i):
					var named := str(kid["cast_name"]) != ""
					var key := "%s/%d" % [str(kid["cast_name"]), int(kid["cast_id"])]
					if seen.has(key):
						continue
					seen[key] = true
					tally["children"] = int(tally["children"]) + 1
					tally["indexed" if named else "own"] = int(
						tally["indexed" if named else "own"]) + 1
					var truth := _oracle(table, kid)
					if truth < 0:
						continue
					var bucket := "indexed_decisive" if named else "own_decisive"
					tally[bucket] = int(tally[bucket]) + 1
					var got: int = FilmLoopView.child_lib(kid, lib, table)
					if got == truth:
						continue
					var detail := "%s  %s:%d %s child %d (%dx%d) wants %s, resolved %s" % [
						rel, str(table.cast_libs[lib]["name"]), number,
						str(m.get("name", "")), int(kid["cast_id"]),
						int(kid["width"]), int(kid["height"]),
						_name_of(table, truth), _name_of(table, got)]
					if named:
						tally["indexed_wrong"] = int(tally["indexed_wrong"]) + 1
						lines.append(detail)
						continue
					tally["own_disputed"] = int(tally["own_disputed"]) + 1
					if not played_read:
						played = _played_loops(f, table)
						played_read = true
					var on_screen: bool = played.has("%d:%d" % [lib, number])
					if on_screen:
						tally["own_disputed_played"] = int(
							tally["own_disputed_played"]) + 1
					if on_screen or _verbose:
						lines.append("%s  [%s]" % [
							detail, "PLAYED" if on_screen else "never played"])
	f.close()
	table.close()


## Which film-loop members this movie's score ever puts on a channel, as
## `"<lib>:<member>"`. What a loop nobody plays contains cannot be seen.
func _played_loops(f, table) -> Dictionary:
	var out := {}
	var ids: Array = f.ids_of("VWSC")
	if ids.is_empty():
		return out
	var score := Score.new()
	if not score.parse(f.read_chunk(ids[0])):
		return out
	for i in score.frame_count:
		for s in score.frame(i).get("sprites", []):
			var key := "%d:%d" % [int(s["cast_lib"]), int(s["cast_id"])]
			if out.has(key):
				continue
			var m: Dictionary = table.get_member(int(s["cast_lib"]), int(s["cast_id"]))
			if int(m.get("type", 0)) == LOOP_TYPE:
				out[key] = true
	return out


## Which library holds this child's member at exactly the child's recorded size.
## -1 where the evidence does not decide it: a stretched child's rect is the
## author's, and a size two casts happen to share proves nothing.
func _oracle(table, kid: Dictionary) -> int:
	if bool(kid["stretch"]):
		return -1
	var fits: Array = []
	for n in table.cast_libs:
		var cast = table.cast_for(int(n))
		if cast == null:
			continue
		var m: Dictionary = cast.member(int(kid["cast_id"]))
		if m.is_empty():
			continue
		if int(m.get("width", 0)) == int(kid["width"]) \
				and int(m.get("height", 0)) == int(kid["height"]):
			fits.append(int(n))
	return int(fits[0]) if fits.size() == 1 else -1


func _lib_of(by_name: Dictionary, entry: String) -> int:
	var stem := entry.replace(":", "/").replace("\\", "/").get_file().get_basename().to_lower()
	if stem == "":
		return -1
	return int(by_name.get(stem, -1))


func _name_of(table, lib: int) -> String:
	if lib < 0:
		return "nothing"
	return "%s(%d)" % [str(table.cast_libs.get(lib, {}).get("name", "?")), lib]


func _list_of(file) -> PackedStringArray:
	var ids: Array = file.ids_of("ccl ")
	if ids.is_empty():
		return PackedStringArray()
	return FilmLoop.read_cast_list(file.read_chunk(ids[0]))
