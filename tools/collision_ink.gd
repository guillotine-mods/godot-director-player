extends SceneTree
## Which `intersects`/`within` operands are matte, i.e. which pairs would change
## arm once the operators stop being bounding-box-only.
##
##   godot --headless --path . --script tools/collision_ink.gd
##   godot --headless --path . --script tools/collision_ink.gd -- --root piposh-dream
##   godot --headless --path . --script tools/collision_ink.gd -- --all
##   godot --headless --path . --script tools/collision_ink.gd -- \
##     --root piposh --file PIPDATA/CANON.dir --channels 17,18,19,20,21,22,48
##
##   --root NAME       one corpus root under games/ (overrides the config in memory)
##   --roots A,B       explicit roots, `res://`-prefixed or bare
##   --all             every subdirectory of games/ and test-games/
##   --file PATH       one container of the chosen root
##   --sites N         print the first N script sites, resolved or not
##   --channels A,B    profile these channels' ink too, beside the literal operands
##
## `bugs.md` 126. `scenes/preview_lingo_host.gd`'s arm answered
## `first.intersects(second)` / `second.encloses(first)` unconditionally, and the
## reference is ink-aware — three arms for `intersects`, two for `within`
## (`lingo/lingo-code.cpp:c_intersects`, `:c_within`). The arms only differ when an
## operand is matte, so **the size of that defect is a measurement nobody had
## taken**: how many operand pairs in real containers would take a non-box arm.
##
## ## The two predicates, reduced to what this port can read
##
## `c_intersects` asks `_cast->_type == kCastBitmap && _sprite->_ink ==
## kInkTypeMatte` of each operand. `c_within` asks `!isQDShape() && _ink ==
## kInkTypeMatte`. Those are **not** the same test, and the difference is the
## whole reason this file counts two populations rather than one:
##
##   intersects-eligible   ink == Matte  and the member is a bitmap
##   within-eligible       ink == Matte  and the *sprite type* is not QuickDraw
##
## `isQDShape` reads the sprite-type byte (`sprite.cpp:189`), not the cast type, so
## a matte-inked *shape cast member* on a type-16 record is within-eligible and not
## intersects-eligible. That is the sharp edge: `isMatteWithin` only builds a matte
## for a `kCastBitmap` operand, so a shape member reaches the matte arm and then
## answers **false**, where the box arm would have answered true. This corpus's
## invisible hotspots are matte-inked shape members (`scenes/preview/hilite.gd`),
## and Piposh 1's cannon asks `sprite 48 within i` over six of them.
##
## The sprite-type histogram is printed and asserted for exactly that reason. The
## reduction "every record here is type 16, so `isQDShape` is always false" is a
## sentence in another tool's docstring; a survey that rests on it has to re-measure
## it or it is repeating a number rather than reading one.
##
## ## The bound, which is what makes an answer possible at all
##
## Most operands are *variables* — `sprite 15 intersects i` inside a repeat loop —
## and no static pass can say which channel `i` holds. So the resolved-pair count
## is a floor, not the answer, and the **container-level bound** is what carries the
## claim: a container with zero matte records cannot change arm on any pair
## whatever its variables resolve to. The unresolved operand count is printed as
## loudly as the resolved one, because "0 resolved pairs change arm" reads as "0
## pairs change arm" and is not the same statement.
##
## Title-agnostic: it names no game and discovers its roots by listing them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Ink := preload("res://director/director_ink.gd")

## Where corpora live, the same discovery `tools/channel_occupancy.gd` does.
const CORPUS_DIRS := ["res://games", "res://test-games"]

## Cast libraries a movie can address. `director_cast_table.gd` keys by `MCsL`
## number and nothing in the corpus numbers one above the high thirties.
const MAX_CAST_LIB := 40

## Every occurrence of either keyword, so the structured count can be reported
## against the raw one rather than passed off as complete.
const WORD_RE := "(?i)\\b(intersects|within)\\b"

## How far back from a keyword `sprite` may be and still be its left operand's
## designator. Generous -- `sprite(getAt(bltsprite, i)).within(` is 30 characters
## -- and bounded so that the word `within` in a comment or in the container's
## symbol table does not attach itself to an unrelated `sprite` two lines up.
const LEFT_SCAN := 80


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


## One container's tally.
class Row extends RefCounted:
	var path := ""
	## Raw keyword occurrences, and the ones that are operator sites.
	var words := 0
	## Keyword occurrences with no `sprite` designator in reach: prose, or the
	## container's own symbol table, and not operator sites.
	var bare_words := 0
	var sites := 0
	var sites_intersects := 0
	var sites_within := 0
	## Operands that are a literal channel, and ones that are not.
	var literal_operands := 0
	var unresolved_operands := 0
	## Distinct literal (op, a, b) triples.
	var pairs: Dictionary = {}
	## Sprite records, and the two matte populations.
	var records := 0
	var matte_records := 0
	var matte_bitmap_records := 0
	## **Matte records whose member did not resolve at all**, and the guard on the
	## whole `intersects` half of this survey. `is_bitmap` is what selects the arm,
	## and for an unresolved member it is false *by failure* rather than by fact --
	## so a container with a high count here reports a floor and not a count. The
	## `master.cst is ambiguous` warning in `piposh2` is what makes this real
	## rather than theoretical.
	var matte_unresolved := 0
	## channel -> true, for channels a literal operand names.
	var operand_channels: Dictionary = {}
	## channel -> "ink|member type" -> count, over the channels being profiled.
	## This is the measurement `bugs.md` 126 asks for in as many words: the ink of
	## the sprite in each operand channel, at every frame the channel is occupied.
	var channel_ink: Dictionary = {}
	## Distinct (op, a, b) triples that take a non-box arm on at least one frame,
	## and the per-frame instances of that.
	var changing_pairs: Dictionary = {}
	var changing_instances := 0
	## Of those, the ones that reach a matte arm with a **non-bitmap** operand --
	## `within`'s predicate is the only one that can, since it tests the sprite
	## type rather than the cast type. That is where the reference answers `false`
	## outright and this port answers the box question instead
	## (`scenes/preview/collision.gd`), so it is the reach of the one deliberate
	## deviation and it is counted rather than described.
	var changing_null_matte: Dictionary = {}
	## (op, a, b) triples where both channels are occupied on some frame at all.
	var resolved_pairs: Dictionary = {}


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var roots: Array[String] = []
	var explicit := Args.text(args, "roots", "")
	var one_root := Args.text(args, "root", "")
	if explicit != "":
		for part in explicit.split(",", false):
			var name := str(part).strip_edges()
			roots.append(name if name.begins_with("res://") else "res://games/%s" % name)
	elif Args.flag(args, "all"):
		for parent in CORPUS_DIRS:
			var dir := DirAccess.open(parent)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(str(parent).path_join(sub))
	elif one_root != "":
		roots.append(one_root if one_root.begins_with("res://")
			else "res://games/%s" % one_root)
	else:
		roots.append(paths.root)
	roots.sort()

	var only_file := Args.text(args, "file", "")
	var sites_left := Args.number(args, "sites", 0)
	# Channels to profile beside the literal operands. The variable operands are
	# what make this necessary: `sprite 48 within i` names one channel statically
	# and the loop bound names the rest in the script's own prose.
	var extra: Dictionary = {}
	for part in Args.text(args, "channels", "").split(",", false):
		var channel := int(str(part).strip_edges())
		if channel > 0:
			extra[channel] = true

	var word_re := RegEx.new()
	word_re.compile(WORD_RE)

	# The guard on the whole `within` analysis: a survey that assumes every record
	# is type 16 has to see the histogram it assumed.
	var sprite_types: Dictionary = {}
	var ink_of_matte_records: Dictionary = {}
	## "path|op|a|b|arm" -> {first frame, per-frame instances}. The whole
	## population, printed in full; see the comment at the write site.
	var changed: Dictionary = {}
	var site_lines: Array[String] = []
	var rows_by_root: Dictionary = {}
	var containers := 0
	var scores := 0

	for root in roots:
		# A survey is asked across titles, and the configured root is a working
		# file `gate.sh` and other sessions share -- so the root is overridden in
		# memory rather than written back out.
		var root_paths := Paths.new()
		root_paths.load_config()
		root_paths.root = root
		var targets: Array[String] = []
		if only_file != "":
			var resolved: String = root_paths.resolve(only_file)
			if resolved == "":
				print("no such container in %s: %s" % [root, only_file])
				continue
			targets.append(resolved)
		else:
			_walk(root, targets)
			targets.sort()

		var rows: Array[Row] = []
		for path in targets:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			containers += 1
			var row := Row.new()
			row.path = path
			var table := CastTable.new()
			table.open(f, root_paths)

			# Every script this container can reach, member scripts included:
			# item 0 of a cast info block is the member's own script whatever the
			# member's type, so scanning `source` covers behaviours, movie
			# scripts and cast scripts in one pass.
			for lib in range(1, MAX_CAST_LIB + 1):
				var cast = table.cast_for(lib)
				if cast == null:
					continue
				for number in cast.member_numbers():
					var m: Dictionary = cast.member(number)
					var source := str(m.get("source", ""))
					if source == "":
						continue
					if source.findn("intersects") < 0 and source.findn("within") < 0:
						continue
					var found := _sites(source, word_re)
					row.words += found.size()
					for site_value in found:
						var site: Dictionary = site_value
						var op := str(site["op"])
						var left_text := str(site["left"])
						if left_text.strip_edges() == "":
							# No `sprite` designator within reach: the keyword is
							# a bare word rather than an operator site. Counted in
							# `words` and nowhere else.
							row.bare_words += 1
							continue
						row.sites += 1
						if op == "intersects":
							row.sites_intersects += 1
						else:
							row.sites_within += 1
						var a := _literal(left_text)
						var b := _literal(str(site["right"]))
						row.literal_operands += (1 if a > 0 else 0) + (1 if b > 0 else 0)
						row.unresolved_operands += (1 if a <= 0 else 0) + (1 if b <= 0 else 0)
						if a > 0:
							row.operand_channels[a] = true
						if b > 0:
							row.operand_channels[b] = true
						if a > 0 and b > 0:
							row.pairs["%s %d %d" % [op, a, b]] = true
						if sites_left > 0:
							sites_left -= 1
							site_lines.append("    %s %d:%d  sprite %s %s %s" % [
								path.trim_prefix("res://"), lib, number,
								left_text.strip_edges(), op,
								str(site["right"]) if str(site["right"]) != ""
									else "(unresolved)"])

			var vwsc: Array = f.ids_of("VWSC")
			if not vwsc.is_empty():
				var score := Score.new()
				if score.parse(f.read_chunk(int(vwsc[0]))):
					scores += 1
					for i in score.frame_count:
						# channel -> [within_eligible, intersects_eligible]
						var eligible: Dictionary = {}
						# channel -> true. The port drops a record with no member
						# (`director_score.gd`), so being in the frame's sprite
						# list is the whole of "occupied".
						var occupied: Dictionary = {}
						for sprite_value in score.frame(i).get("sprites", []):
							var sprite: Dictionary = sprite_value
							row.records += 1
							var channel := int(sprite["channel"])
							occupied[channel] = true
							var st := int(sprite.get("sprite_type", 0))
							sprite_types[st] = int(sprite_types.get(st, 0)) + 1
							var ink := int(sprite["ink"]) & Ink.INK_MASK
							var m: Dictionary = table.get_member(
								int(sprite["cast_lib"]), int(sprite["cast_id"]))
							var is_bitmap := int(m.get("type", 0)) == Ink.TYPE_BITMAP
							var is_qd := Ink.QD_SHAPE_SPRITE_TYPES.has(st)
							if row.operand_channels.has(channel) or extra.has(channel):
								if not row.channel_ink.has(channel):
									row.channel_ink[channel] = {}
								var hist: Dictionary = row.channel_ink[channel]
								var key := "ink %2d %-14s %s" % [ink,
									str(m.get("type_name", "?")),
									"MATTE" if ink == Ink.MATTE else ""]
								hist[key] = int(hist.get(key, 0)) + 1
							if ink != Ink.MATTE:
								continue
							row.matte_records += 1
							if is_bitmap:
								row.matte_bitmap_records += 1
							if m.is_empty():
								row.matte_unresolved += 1
							var tn := str(m.get("type_name", "?"))
							ink_of_matte_records[tn] = int(
								ink_of_matte_records.get(tn, 0)) + 1
							eligible[channel] = [not is_qd, is_bitmap]
						if row.pairs.is_empty():
							continue
						for key in row.pairs:
							var parts: PackedStringArray = str(key).split(" ")
							var op := parts[0]
							var a := int(parts[1])
							var b := int(parts[2])
							if not occupied.has(a) or not occupied.has(b):
								continue
							row.resolved_pairs[key] = true
							var arm := _arm(op, eligible.get(a, [false, false]),
								eligible.get(b, [false, false]))
							if arm == "box":
								continue
							row.changing_pairs[key] = true
							row.changing_instances += 1
							# Only `matte-within` can reach it. The other two arms
							# only scan mattes they demanded a *bitmap* for --
							# `matte-on-matte` both operands, `box-on-matte` the
							# second -- so a non-bitmap operand there is impossible
							# by construction rather than merely unseen.
							if arm == "matte-within":
								var ea: Array = eligible.get(a, [false, false])
								var eb: Array = eligible.get(b, [false, false])
								if not bool(ea[1]) or not bool(eb[1]):
									row.changing_null_matte[key] = true
							# Keyed by pair rather than appended per frame, so the
							# list below is the whole population and not the first
							# N frames of whichever movie came first. A tool that
							# reports a count and then a truncated list reads as
							# complete and shapes decisions for hours
							# (`porting-fidelity-verification`, "find the silent
							# caps"): the earlier version's 60-line cap was 60
							# consecutive frames of one movie.
							var ck := "%s|%s|%d|%d|%s" % [
								path.trim_prefix("res://"), op, a, b, arm]
							if not changed.has(ck):
								changed[ck] = {"first": i, "count": 0}
							(changed[ck] as Dictionary)["count"] = int(
								(changed[ck] as Dictionary)["count"]) + 1
			f.close()
			if row.words > 0 or row.matte_records > 0:
				rows.append(row)
		rows_by_root[root] = rows

	print("%d container(s), %d score(s)" % [containers, scores])
	print("")
	print("sprite-type byte over every record walked (the `within` reduction's guard):")
	var st_keys: Array = sprite_types.keys()
	st_keys.sort()
	for k in st_keys:
		print("  %3d %s %d" % [int(k),
			"QuickDraw shape" if Ink.QD_SHAPE_SPRITE_TYPES.has(int(k)) else "               ",
			int(sprite_types[k])])
	print("")
	print("member type of every Matte-inked record:")
	var tn_keys: Array = ink_of_matte_records.keys()
	tn_keys.sort()
	for k in tn_keys:
		print("  %-14s %d" % [str(k), int(ink_of_matte_records[k])])

	var total_words := 0
	var total_sites := 0
	var total_unresolved := 0
	var total_pairs := 0
	var total_resolved := 0
	var total_changing := 0
	var total_instances := 0
	var total_matte := 0
	var total_matte_bitmap := 0
	var total_matte_unresolved := 0
	var total_null_matte := 0
	for root in roots:
		var rows: Array = rows_by_root.get(root, [])
		print("")
		print("%s" % str(root).trim_prefix("res://"))
		print("  %-24s %6s %5s %5s %6s %6s %6s %6s %7s %7s" % [
			"container", "words", "sites", "lit", "unres", "pairs", "resolv",
			"matte", "m-bmp", "m-none"])
		var root_changing := 0
		var root_unresolved := 0
		for row_value in rows:
			var row: Row = row_value
			total_words += row.words
			total_sites += row.sites
			total_unresolved += row.unresolved_operands
			total_pairs += row.pairs.size()
			total_resolved += row.resolved_pairs.size()
			total_changing += row.changing_pairs.size()
			root_changing += row.changing_pairs.size()
			total_instances += row.changing_instances
			total_matte += row.matte_records
			total_matte_bitmap += row.matte_bitmap_records
			total_matte_unresolved += row.matte_unresolved
			root_unresolved += row.matte_unresolved
			total_null_matte += row.changing_null_matte.size()
			if row.words == 0:
				continue
			print("  %-24s %6d %5d %5d %6d %6d %6d %6d %7d %7d%s" % [
				row.path.get_file(), row.words, row.sites, row.literal_operands,
				row.unresolved_operands, row.pairs.size(),
				row.resolved_pairs.size(), row.matte_records,
				row.matte_bitmap_records, row.matte_unresolved,
				"  CHANGES %d" % row.changing_pairs.size()
					if not row.changing_pairs.is_empty() else ""])
			var channels: Array = row.channel_ink.keys()
			channels.sort()
			for channel in channels:
				var hist: Dictionary = row.channel_ink[channel]
				var keys: Array = hist.keys()
				keys.sort()
				for key in keys:
					print("      channel %-3d %s  x%d" % [
						int(channel), str(key), int(hist[key])])
		print("  pairs that change arm in this root: %d" % root_changing)
		# Printed next to it deliberately: `m-none` is the count of Matte records
		# whose member did not resolve, and `is_bitmap` is false-by-failure for
		# every one of them. A root with a high count reports a **floor**.
		print("  Matte records whose member did not resolve: %d" % root_unresolved)

	print("")
	print("totals over %d root(s):" % roots.size())
	print("  keyword occurrences in script text      : %d" % total_words)
	print("  sites the regex gave structure to       : %d" % total_sites)
	print("  operands that are a literal channel     : %d" % (
		total_sites * 2 - total_unresolved))
	print("  operands that are NOT (a variable, ...) : %d" % total_unresolved)
	print("  distinct literal (op, a, b) triples     : %d" % total_pairs)
	print("  ... with both channels occupied somewhere: %d" % total_resolved)
	print("  ... that take a non-box arm             : %d" % total_changing)
	print("  per-frame instances of that             : %d" % total_instances)
	print("  Matte-inked sprite records              : %d" % total_matte)
	print("  ... naming a bitmap member              : %d" % total_matte_bitmap)
	print("  ... whose member did not resolve at all : %d  <- makes the above a floor"
		% total_matte_unresolved)
	print("  changing pairs that reach a null matte  : %d  (the one deviation's reach)"
		% total_null_matte)
	if not site_lines.is_empty():
		print("")
		print("  first %d site(s):" % site_lines.size())
		for line in site_lines:
			print(line)
	if not changed.is_empty():
		print("")
		print("  every pair that changes arm (%d):" % changed.size())
		var ckeys: Array = changed.keys()
		ckeys.sort()
		for ck in ckeys:
			var parts: PackedStringArray = str(ck).split("|")
			var info: Dictionary = changed[ck]
			print("    %-40s sprite %-4s %-10s %-4s -> %-14s first frame %d, %d frame(s)" % [
				parts[0], parts[2], parts[1], parts[3], parts[4],
				int(info["first"]), int(info["count"])])

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("opened containers", containers > 0, "%d" % containers)
	h.check("read at least one score", scores > 0, "%d" % scores)
	# **The guard, not decoration.** A run reporting "no pair changes arm" is
	# indistinguishable from a run that read a structurally-zero ink byte, so the
	# ink byte has to be shown live before the zero means anything.
	h.check("the ink byte is live -- some record is Matte", total_matte > 0,
		"%d Matte records" % total_matte)
	h.check("the sprite-type byte is live", not sprite_types.is_empty(),
		"%d distinct values" % sprite_types.size())
	# **The second guard, and the one this survey did not have at first.**
	# `is_bitmap` selects the `intersects` arm, and for a member the cast table
	# cannot resolve it is false by failure. A run where most Matte records are
	# unresolved is reporting a floor and must say so rather than a count.
	h.check("member resolution is live -- most Matte records resolve",
		total_matte == 0 or total_matte_unresolved * 2 < total_matte,
		"%d of %d Matte records unresolved" % [total_matte_unresolved, total_matte])
	h.complete("the survey ran")
	quit(h.finish("how many operand pairs would change arm"))


## Which arm the reference takes, given each operand's `[within_eligible,
## intersects_eligible]`. Reproduced from `c_intersects`/`c_within` including the
## asymmetry: only the **second** operand being matte is a distinct arm for
## `intersects`, and only the first being matte falls all the way back to boxes.
func _arm(op: String, a: Array, b: Array) -> String:
	if op == "within":
		return "matte-within" if bool(a[0]) and bool(b[0]) else "box"
	if bool(a[1]) and bool(b[1]):
		return "matte-on-matte"
	if bool(b[1]):
		return "box-on-matte"
	return "box"


## The last occurrence of `word` in `text` that is not part of a longer identifier.
func _rfind_word(text: String, word: String) -> int:
	var at := text.rfind(word)
	while at > 0:
		var before := text[at - 1]
		if not (before.is_valid_identifier() or (before >= "0" and before <= "9")):
			return at
		at = text.rfind(word, at - 1)
	return at


## A literal channel number, or 0 for anything this pass cannot resolve.
func _literal(text: String) -> int:
	var t := text.strip_edges()
	while t.begins_with("(") and t.ends_with(")"):
		t = t.substr(1, t.length() - 2).strip_edges()
	return int(t) if t.is_valid_int() and int(t) > 0 else 0


## Every `intersects`/`within` site in one script, with each operand's text.
##
## **A regex was tried first and undercounted badly**, which is the reason this is
## a scanner. Lingo writes these operators three ways and the corpus uses all
## three:
##
##     sprite 5 within getAt(ppl, 1)                 infix, literal left
##     sprite getAt(ppl, 1) intersects 25            infix, call on the left
##     sprite(getAt(bltsprite, i)).within(66)        method syntax
##
## A `sprite\s+(\w+)\s+(intersects|within)` pattern matches only the first, and
## `getAt(ppl, 1)` breaks it on the second -- so `WEST1/2/3.dir` and `psy.cst`
## reported **zero** sites against 7, 8, 9 and 3 keyword occurrences, and the ones
## it did structure were the minority form. Extracting each operand's text and
## then asking whether *that* is a literal keeps the two questions apart: how many
## sites there are, and how many of their operands this pass can resolve.
func _sites(source: String, word_re: RegEx) -> Array:
	var out: Array = []
	for hit in word_re.search_all(source):
		var op := hit.get_string(1).to_lower()
		var start := hit.get_start()
		# The left operand. `sprite` is its designator in every form; where there
		# is none within reach the site is a bare word (a comment, or the
		# container's own symbol table) and the operand text stays empty.
		var window := source.substr(maxi(0, start - LEFT_SCAN), mini(start, LEFT_SCAN))
		# **On a word boundary**, which is not fussiness: `getAt(bltsprite, i)` ends
		# in the six letters being searched for, so a plain `rfind` extracted `, i))`
		# as the left operand of every one of `WEST*.dir`'s method-form sites.
		var at := _rfind_word(window.to_lower(), "sprite")
		var left := ""
		if at >= 0:
			left = window.substr(at + 6)
			# The method form puts the operator behind a dot; drop it and the dot.
			if left.strip_edges().ends_with("."):
				left = left.strip_edges().trim_suffix(".")
		# The right operand: past the keyword, past an opening paren of the method
		# form, past an optional `sprite` designator, then one token.
		var rest := source.substr(hit.get_end()).strip_edges()
		rest = rest.trim_prefix("(").strip_edges()
		if rest.to_lower().begins_with("sprite"):
			rest = rest.substr(6).strip_edges().trim_prefix("(").strip_edges()
		var right := ""
		for i in rest.length():
			var c := rest[i]
			if c.is_valid_identifier() or (c >= "0" and c <= "9") or c == "_":
				right += c
			else:
				# A token followed by `(` is a call, not a channel number.
				if c == "(":
					right = ""
				break
		out.append({"op": op, "left": left, "right": right})
	return out
