extends SceneTree
## Which frames of which containers actually run a script matching a pattern, and
## under which marker.
##
##   godot --headless --path . --script tools/script_placement.gd -- --match 'rat[a-f]' --root piposh-dream --file rating.dir
##   godot --headless --path . --script tools/script_placement.gd -- --match 'item [0-9]+ of advancekeeper' --root piposh-dream
##   godot --headless --path . --script tools/script_placement.gd -- --match soundbusy --all
##
##   --match P    a RegEx over each script member's source. Required; no default,
##                because a survey with a default pattern answers a question nobody
##                asked. Case-insensitive unless `--case`.
##   --case       match case-sensitively.
##   --root R     the corpus (default the config's). One root per process.
##   --file F     one container of it, matched on the tail of its relative path.
##                Default is **every** container of the root.
##   --all        every root under `games/`, in one process. Refuses to run beside
##                `--root`, for the reason below.
##   --linked     also print the matching members the score never places. Off by
##                default because they are the population the counts are for and
##                there are usually forty times as many of them.
##   --lines      print every matching source line of a member, not the first.
##
## A survey and not a gate: it prints a table and numbers rather than pass/fail, so
## it is not in `gate.sh`'s `ALL`. `tools/puppet_members.gd` is the precedent.
##
## ## Why a name search cannot answer this
##
## Every container in these titles links the shared casts, so grepping the decompiled
## Lingo for a handler tells you the handler exists — never where it runs. In the
## words of the sweep that needed this: *"a handler in a shared cast can be attached
## by any of twelve containers, and only the score knows which."*
##
## The question has been answered by a throwaway three times and deleted three times
## (`_scratch_day2_scan.gd --frames`, `_scratch_day3_attach.gd`, `_scratch_ak_writes.gd`),
## which is what this file is for.
##
## ## Linked presence is not score placement, and the gap is the point
##
## `piposh-dream`'s `sherd.cst` members 62 and 101 are linked into **every** container
## that links that cast and each writes `item 1 of advancekeeper`. Counting matching
## members would report eighty-odd item-1 writers; **two** containers actually place
## one where the playhead reaches it — `show.dir` at f2377 and `RATB.dir` at f548.
## So three populations are counted and printed separately, and none of them is
## allowed to stand in for another:
##
##   distinct  one matching member of one cast *file*, however many movies link it
##   linked    one (container, library, member) triple — reachable from a container
##   placed    the triples the score puts on the frame-script channel or on a sprite
##
## ## What counts as running it
##
## A frame script's interval can be superseded by a narrower one over the same
## frames, so the frames a script *runs on* are the frames it is the narrowest cover
## of — `_coverage`, the same rule and the same reason as `tools/puppet_members.gd`.
## A placement whose every frame is taken by a narrower script is still printed, as
## `SHADOWED`: dropping it would turn a disagreement with an expected frame number
## into silence, and silence is the one answer a survey must not give.
##
## **That arm has no measurement behind it and the number is printed so that stays
## visible.** `--match 'the keyDownScript' --all` places 1,007 spans over all six
## roots and shadows 0 of them, and neither known-answer case shadows anything
## either. The rule is Director's and is implemented from it; a `0` in that row is
## the corpus not exercising it, not evidence the arm works.
##
## A script member's library comes off the score raw and must be normalised
## (`scripts.gd:in_lib`, `_lib` here). Missing that resolves the number in the wrong
## cast, where it finds a stranger.
##
## Markers come from `DirectorLabels`, whose own header carries the rules — most
## importantly that an entry is never dropped and only its *name* can be unreadable.
## A placement is reported under the last **named** marker at or before it, with that
## marker's own frame, because "f416 under `caveopen` at f402" is the answer and the
## name alone is not.
##
## ## The two cases this was built against, and what they actually print
##
## Both are established from earlier work, so this file disagreeing with either would
## be this file being wrong.
##
##   --match 'rat[a-f]' --root piposh-dream --file rating.dir
##
## `RATB.dir` is the one of the six `rat*` containers that is not a door: it is
## reached from a **frame script `3:191` at f416, under `caveopen` at f402**, and
## library 3 is `egoz`, the shared cast — which is exactly why a name search could
## only say "some container that links egoz.cst". The five doors come out as sprite
## behaviours on `rating.dir`'s own internal cast, f22..f37 in two score spans each:
## `1:73` ch31 ratC, `1:74` ch32 ratF, `1:75` ch33 ratD, `1:77` ch35 ratA, `1:78`
## ch36 ratE. A seventh member matches and is not an edge — `3:156` f0 holds the
## `movis` list naming all six — which is a regex hit reported rather than filtered,
## because a filter that knew which hits were edges would need the table this replaces.
##
##   --match 'item [0-9]+ of advancekeeper' --root piposh-dream
##
## 79 containers, 47 of them holding a matching member, 21 placements. Day 2's row is
## `show.dir 6:62 f2377`, `hex2.dir 1:138 f344` and f688, `hatul2.dir 1:148 f768`,
## `maze2.dir 1:223 f303`, `plane2.dir 1:181 f1782`, `west2.dir 1:256 f543`,
## `fritz2.dir 1:463 f853`; days 1 and 3 come out beside it, because the pattern is
## about the global and not about a day.
##
## Narrowed to `item 1 of advancekeeper`, the trap the tool exists for: **93 linked,
## 3 placed.** `sherd.cst`'s members 62 and 101 write item 1 and are reachable from
## 46 of the 79 containers; `show.dir` places 62 as a frame script at f2377 and
## `ratb.dir` places 101 at f548, and `hquest.dir` places its own `1:386` as a sprite
## behaviour on ch83. Nothing else in the title runs one.
##
## ## Two blind spots, printed beside every zero rather than only written here
##
## **Sourceless scripts.** The port runs Lingo from each member's source text and
## `Lscr` is undecoded, so a member carrying a script id with no source text is a
## script this scan cannot read. `e1ca332b` measured 64 of them over all six roots
## and 0 with a handler, so the loss is believed to be nil — but a zero from this
## tool has to say the population exists, and the run prints how many it met.
## `--all` reaches 651 containers and 654 casts and counts **64**, which is that
## commit's figure arrived at by a second route; the count is the run's own and not
## a number copied out of the commit.
##
## **Names built at runtime.** A regex over source cannot see `go to movie "rat" &
## thischar`. Where a title assembles a reference, this reports nothing and is right
## to; that is a different tool.
##
## ## `--all` and `--root` cannot both hold
##
## `DirectorPaths.load_config`'s `force_root` argument is deliberately beaten by the
## `--root` flag, so an all-roots loop run with `--root` given would pin every
## iteration to one corpus and print six copies of it — silently, which is the
## failure this refusal exists to prevent rather than a preference about flags.
##
## ## Reading the report
##
##   `|`  a source line the pattern matched
##   `+`  a placement: where the score runs this member
##   `-`  no placement in this container's score (`--linked` only)
##
## Title-agnostic: it names no game, no movie, no channel and no member.
##
## ## `-` is not absence, and two findings died on reading it as absence
##
## A member holding `on <handler>` and reported `- linked here, and this score
## places it nowhere` is **reachable**. That line means the member sits on no frame
## and no channel, which is exactly what a handler *called by name* looks like: the
## score never places it because a caller resolves it at run time. Read as absence it
## manufactures a missing-definition finding.
##
## Both of these came out of a day-3 sweep and both are false:
##
## - *"`hatul2.dir` calls `wlkleftintersects()` at eight sites and nothing defines
##   it."* It defines it, in its own internal cast: `1:10`, named `wlk intersects`,
##   reported `-` because no score places it. Confirmed at run time as well as
##   statically -- a `--play` run of the stage-4 mover, the arm that calls it, leaves
##   `builtins unbound` **empty** after 46 `exitFrame` dispatches, and an undefined
##   call in this port lands there.
## - *"no init in `hatul3.dir` ever sets `savespot` to `stage4`."* `1:122` sets it and
##   is placed, at f402 under the marker `stage4`. What misleads here is the mirror
##   case: `hatul1.dir` `1:100` also holds `savespot = "stage1"` and **is** genuinely
##   unplaced, superseded by `1:196` -- so a container can hold both shapes at once,
##   and only the `+` lines say which one ran.
##
## The check that settles it either way is the run, not the report: an undefined
## handler is visible in a played run's `builtins unbound` tally, empty when every
## call resolved.

const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")

## Where corpora live. Each subdirectory is one root, discovered rather than listed.
const GAMES_DIR := "res://games"
## How wide a printed source line may be before it is cut.
const LINE_WIDTH := 88

var _re: RegEx = null
var _show_linked := false
var _all_lines := false
## cast identity -> {member id -> {"name": String, "lines": Array}}. Keyed by the
## cast's container path *and* its `CAS*` owner id: one file can hold two casts, and
## their member numbers are per-cast, so the path alone would merge them. The cache
## is what keeps `linked` honest as well as what makes the sweep finish — a shared
## `.cst` is scanned once and counted once per container that links it.
var _cache := {}
## cast identity -> how many of its members carry a script id with no source.
var _sourceless := {}


func _init() -> void:
	var args := Args.parse()
	var pattern := Args.text(args, "match", "")
	if pattern == "":
		_usage()
		quit(1)
		return
	_re = RegEx.create_from_string(pattern if Args.flag(args, "case")
		else "(?i)" + pattern)
	if _re == null or not _re.is_valid():
		print("not a regular expression: %s" % pattern)
		quit(1)
		return
	_show_linked = Args.flag(args, "linked")
	_all_lines = Args.flag(args, "lines")

	var every := Args.flag(args, "all")
	if every and args.has("root"):
		print("--all sweeps every root and --root pins one; the flag beats"
			+ " load_config's force_root, so together they would print one root"
			+ " six times. Drop one of them.")
		quit(1)
		return

	var roots: Array[String] = []
	if every:
		var dir := DirAccess.open(GAMES_DIR)
		if dir == null:
			print("cannot list %s" % GAMES_DIR)
			quit(1)
			return
		var subs := dir.get_directories()
		subs.sort()
		for sub in subs:
			roots.append(str(sub))
	else:
		roots.append("")

	var only := Args.text(args, "file", "")
	var totals := {
		"containers": 0, "skipped": 0, "no_score": 0, "with_match": 0,
		"linked": 0, "placed": 0, "frame_spans": 0, "sprite_spans": 0,
		"shadowed": 0, "distinct": {}, "distinct_placed": {}, "roots": [],
	}

	print("pattern    : %s%s" % [pattern, "" if Args.flag(args, "case")
		else "   (case-insensitive)"])
	print("")
	for root in roots:
		var paths = Paths.new()
		if not paths.load_config(Paths.CONFIG_PATH, root):
			print("no game configured: %s" % paths.error)
			quit(1)
			return
		_sweep(paths, only, totals)

	_summary(pattern, totals)
	quit(0)


func _usage() -> void:
	print("which frames of which containers run a script matching a pattern")
	print("")
	print("  --match P   a RegEx over script member source (required)")
	print("  --case      match case-sensitively")
	print("  --root R    the corpus (default the config's)")
	print("  --file F    one container of it (default every container of the root)")
	print("  --all       every root under games/, in one process; not with --root")
	print("  --linked    also list the matching members the score never places")
	print("  --lines     every matching source line of a member, not the first")
	print("")
	print("  godot --headless --path . --script tools/script_placement.gd --"
		+ " --match 'item [0-9]+ of advancekeeper' --root piposh-dream")


## One root: every container of it, or the one `--file` names.
##
## `paths.containers()` lists the `.cst` files too. A cast file has no score and
## therefore places nothing, so it can still *hold* a matching member and is counted
## and reported as unplaced rather than skipped — which is exactly the shape of the
## shared-cast trap this tool exists for.
func _sweep(paths, only: String, totals: Dictionary) -> void:
	var rels: Array[String] = paths.containers()
	var chosen: Array[String] = []
	for rel in rels:
		if only != "" and not rel.to_lower().ends_with(only.to_lower()):
			continue
		chosen.append(rel)
	(totals["roots"] as Array).append(str(paths.root).get_file())
	print("root       : %s" % paths.root)
	print("containers : %d of %d under the root" % [chosen.size(), rels.size()])
	if chosen.is_empty() and only != "":
		print("             (no container under this root ends with %s)" % only)
	print("")
	for rel in chosen:
		_scan(paths, rel, totals)


func _scan(paths, rel: String, totals: Dictionary) -> void:
	var f := ContainerFile.new()
	if not f.open(paths.resolve(rel)):
		totals["skipped"] = int(totals["skipped"]) + 1
		return
	var table = CastTable.new()
	if not table.open(f, paths):
		totals["skipped"] = int(totals["skipped"]) + 1
		f.close()
		return
	totals["containers"] = int(totals["containers"]) + 1

	var matches := _matches_in(table, totals)
	if matches.is_empty():
		table.close()
		f.close()
		return
	totals["with_match"] = int(totals["with_match"]) + 1

	var score = null
	var ids: Array = f.ids_of("VWSC")
	if not ids.is_empty():
		var parsed = Score.new()
		if parsed.parse(f.read_chunk(ids[0])):
			score = parsed
	if score == null:
		totals["no_score"] = int(totals["no_score"]) + 1
	var labels = Labels.new()
	var label_ids: Array = f.ids_of("VWLB")
	if not label_ids.is_empty():
		labels.parse(f.read_chunk(label_ids[0]))

	var cover := {} if score == null else _coverage(score)
	var rows: Array = []
	for match_entry in matches:
		var where: Array = ([] if score == null
			else _placements(score, labels, cover, int(match_entry["lib"]),
				int(match_entry["member"])))
		totals["linked"] = int(totals["linked"]) + 1
		if not where.is_empty():
			totals["placed"] = int(totals["placed"]) + 1
			(totals["distinct_placed"] as Dictionary)["%s:%d" % [
				str(match_entry["cast"]), int(match_entry["member"])]] = true
		for spot in where:
			var kind := str(spot["kind"])
			var key := "frame_spans" if kind == "frame" else "sprite_spans"
			totals[key] = int(totals[key]) + 1
			if bool(spot.get("shadowed", false)):
				totals["shadowed"] = int(totals["shadowed"]) + 1
		if where.is_empty() and not _show_linked:
			continue
		rows.append({"match": match_entry, "where": where})

	if not rows.is_empty():
		_print_container(rel, score, labels, rows)
	table.close()
	f.close()


## Every matching member reachable from this container, in library order.
##
## Walks `cast_libs` rather than the movie's own cast, because a reference this tool
## is asked about is usually in a *shared* cast — which is the whole reason a name
## search could not answer the question.
func _matches_in(table, totals: Dictionary) -> Array:
	var out: Array = []
	var libs: Array = table.cast_libs.keys()
	libs.sort()
	for lib_number in libs:
		var lib := int(lib_number)
		var cast = table.cast_for(lib)
		if cast == null:
			continue
		var key := "%s#%d" % [table.container_path_of(lib), int(cast.owner_id)]
		if not _cache.has(key):
			_cache[key] = _scan_cast(cast, key)
		var found: Dictionary = _cache[key]
		var ids: Array = found.keys()
		ids.sort()
		for id in ids:
			(totals["distinct"] as Dictionary)["%s:%d" % [key, int(id)]] = true
			out.append({
				"lib": lib, "member": int(id), "cast": key,
				"lib_name": str(table.cast_libs[lib].get("name", "")),
				"name": str(found[id]["name"]), "lines": found[id]["lines"],
			})
	return out


## One cast file, scanned once. Also counts the members this scan cannot read.
func _scan_cast(cast, key: String) -> Dictionary:
	var out := {}
	var sourceless := 0
	for number in cast.member_numbers():
		var id := int(number)
		var m: Dictionary = cast.member(id)
		var src := str(m.get("source", ""))
		if src.is_empty():
			# A script id with no source text is a script whose `Lscr` never
			# decoded, not a member without a script. Counted so a zero from this
			# tool can say what it could not see.
			if int(m.get("script_id", 0)) > 0:
				sourceless += 1
			continue
		var lines := _matched_lines(src)
		if lines.is_empty():
			continue
		out[id] = {"name": str(m.get("name", "")), "lines": lines}
	_sourceless[key] = sourceless
	return out


## The distinct source lines the pattern matched, in the order they occur.
##
## Matched against the whole source and then mapped back to the containing line,
## rather than line by line, so a pattern that spans a newline still reports where it
## hit instead of reporting nothing.
func _matched_lines(src: String) -> Array:
	var out: Array = []
	var seen := {}
	for hit in _re.search_all(src):
		var at := hit.get_start()
		var begin := src.rfind("\n", at)
		begin = 0 if begin < 0 else begin + 1
		var stop := src.find("\n", at)
		if stop < 0:
			stop = src.length()
		var line := src.substr(begin, stop - begin).strip_edges()
		if line == "" or seen.has(line):
			continue
		seen[line] = true
		out.append(line)
	return out


## Frame to the narrowest frame-script interval covering it.
##
## The narrowest wins because that is what Director runs: an author who scores a
## one-frame script inside a long span means the short one on that frame. Same rule,
## same reason, as `tools/puppet_members.gd:_coverage`.
func _coverage(score) -> Dictionary:
	var out := {}
	for interval in score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		var span := int(interval["end"]) - int(interval["start"])
		var entry := {
			"lib": _lib(int(interval["script_cast_lib"])),
			"member": int(interval["script_member"]),
			"span": span,
		}
		for frame in range(int(interval["start"]), int(interval["end"]) + 1):
			if out.has(frame) and int(out[frame]["span"]) <= span:
				continue
			out[frame] = entry
	return out


## Every span of this score that attaches this member, frame scripts and sprite
## behaviours alike.
func _placements(score, labels, cover: Dictionary, lib: int, member: int) -> Array:
	var out: Array = []
	for interval in score.intervals():
		if _lib(int(interval["script_cast_lib"])) != lib:
			continue
		if int(interval["script_member"]) != member:
			continue
		var start := int(interval["start"])
		var stop := int(interval["end"])
		if str(interval["kind"]) != "frame":
			out.append({
				"kind": "sprite", "channel": int(interval["channel"]),
				"start": start, "end": stop, "marker": _marker_of(labels, start),
			})
			continue
		var effective: Array = []
		for frame in range(start, stop + 1):
			if not cover.has(frame):
				continue
			if int(cover[frame]["lib"]) != lib:
				continue
			if int(cover[frame]["member"]) != member:
				continue
			effective.append(frame)
		out.append({
			"kind": "frame", "start": start, "end": stop, "runs": effective,
			"shadowed": effective.is_empty(),
			"marker": _marker_of(labels, int(effective[0]) if not effective.is_empty()
				else start),
		})
	return out


## The last **named** marker at or before a frame, with its own frame. `{}` when the
## frame is before the first named marker.
##
## `DirectorLabels.marker_at` answers the name and this needs the pair: a placement
## is read as "f416, under `caveopen` at f402", and the name alone does not say how
## far into the marker's span the script sits. Unnamed entries are skipped for the
## name and never renumbered away — see that file's header.
func _marker_of(labels, frame: int) -> Dictionary:
	var found := {}
	for marker in labels.markers:
		var at := int(marker["frame"])
		if at > frame:
			break
		if str(marker["name"]) == "":
			continue
		found = {"name": str(marker["name"]), "frame": at}
	return found


func _print_container(rel: String, score, labels, rows: Array) -> void:
	print("-".repeat(78))
	if score == null:
		print("%s   no score — nothing here can be placed" % rel)
	else:
		print("%s   %d frames, %d markers" % [rel, score.frame_count,
			labels.markers.size()])
	for row in rows:
		var match_entry: Dictionary = row["match"]
		var name := str(match_entry["name"])
		print("  %d:%d  [%s]%s" % [int(match_entry["lib"]), int(match_entry["member"]),
			str(match_entry["lib_name"]), "" if name == "" else " \"%s\"" % name])
		var lines: Array = match_entry["lines"]
		for i in lines.size():
			if i > 0 and not _all_lines:
				print("      | ... %d more matching line(s), --lines for them"
					% (lines.size() - 1))
				break
			print("      | %s" % _cut(str(lines[i])))
		var where: Array = row["where"]
		if where.is_empty():
			print("      - linked here, and this score places it nowhere")
			continue
		for spot in _merged(where):
			print("      + %s" % _where_words(spot))


## Adjacent spans of the same kind and channel, printed as one range.
##
## The score splits a span wherever a sprite's record changes, so one behaviour on
## one channel across one scene is commonly several intervals: `piposh-dream`'s
## `rating.dir` attaches each of its five door behaviours over f22..f27 and f28..f37,
## and the scene is one row of doors from f22 to f37. Printing the intervals raw made
## the report twice as long and said nothing the merge does not — `%d spans` carries
## how many there were, and the span counts in the summary stay the score's own.
##
## Only *touching* spans merge (`next.start <= end + 1`). A gap means the score really
## does stop attaching it, which is a different fact and keeps its own row.
func _merged(where: Array) -> Array:
	var groups := {}
	var order: Array = []
	for spot in where:
		var key := "%s:%d" % [str(spot["kind"]), int(spot.get("channel", 0))]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(spot)
	var out: Array = []
	for key in order:
		var list: Array = groups[key]
		list.sort_custom(func(a, b): return int(a["start"]) < int(b["start"]))
		var open: Dictionary = {}
		for spot in list:
			if not open.is_empty() and int(spot["start"]) <= int(open["end"]) + 1:
				open["end"] = max(int(open["end"]), int(spot["end"]))
				open["spans"] = int(open["spans"]) + 1
				open["runs"] = (open.get("runs", []) as Array) + (
					spot.get("runs", []) as Array)
				open["shadowed"] = bool(open["shadowed"]) and bool(
					spot.get("shadowed", false))
				continue
			if not open.is_empty():
				out.append(open)
			open = spot.duplicate()
			open["spans"] = 1
			open["shadowed"] = bool(spot.get("shadowed", false))
		if not open.is_empty():
			out.append(open)
	for spot in out:
		if not spot.has("runs"):
			continue
		# Overlapping intervals would otherwise contribute a frame twice, and the
		# count is what decides whether the row says `runs`.
		var seen := {}
		for frame in spot["runs"]:
			seen[int(frame)] = true
		var unique: Array = seen.keys()
		unique.sort()
		spot["runs"] = unique
	return out


func _where_words(spot: Dictionary) -> String:
	var marker: Dictionary = spot["marker"]
	var under := ("no named marker at or before it" if marker.is_empty()
		else "marker \"%s\" f%d" % [str(marker["name"]), int(marker["frame"])])
	var spans := int(spot.get("spans", 1))
	var counted := "" if spans <= 1 else "   %d spans" % spans
	if str(spot["kind"]) == "sprite":
		return "sprite  ch%-3d %-22s %s%s" % [int(spot["channel"]),
			_span(int(spot["start"]), int(spot["end"])), under, counted]
	var runs: Array = spot["runs"]
	var span := _span(int(spot["start"]), int(spot["end"]))
	var detail := span
	if runs.is_empty():
		detail = "%s SHADOWED" % span
	elif runs.size() != int(spot["end"]) - int(spot["start"]) + 1:
		detail = "%s runs %s" % [span, _span(int(runs[0]), int(runs[-1]))]
	return "frame   %-26s %s%s" % [detail, under, counted]


static func _span(start: int, stop: int) -> String:
	return "f%d" % start if start == stop else "f%d..f%d" % [start, stop]


static func _cut(line: String) -> String:
	return line if line.length() <= LINE_WIDTH else line.substr(0, LINE_WIDTH - 3) + "..."


## The score writes a script's library raw; `scripts.gd:in_lib` normalises it.
## Missing this resolves the number in the wrong cast, where it finds a stranger.
static func _lib(raw: int) -> int:
	return 1 if raw <= 0 or raw == 0xFFFF else raw


func _summary(pattern: String, totals: Dictionary) -> void:
	var sourceless := 0
	for key in _sourceless:
		sourceless += int(_sourceless[key])
	print("")
	print("=".repeat(78))
	print("summary")
	print("  pattern                  : %s" % pattern)
	var swept := PackedStringArray()
	for name in totals["roots"]:
		swept.append(str(name))
	print("  roots swept              : %s" % ", ".join(swept))
	print("  containers opened        : %d  (%d would not open, %d hold a matching"
		% [int(totals["containers"]), int(totals["skipped"]),
			int(totals["with_match"])]
		+ " member, %d of those have no score)" % int(totals["no_score"]))
	print("  distinct members matched : %d  one per cast file and member number"
		% (totals["distinct"] as Dictionary).size())
	print("  linked                   : %d  (container, library, member) triples —"
		% int(totals["linked"]) + " reachable, not necessarily run")
	print("  placed by the score      : %d of those, %d distinct member(s)" % [
		int(totals["placed"]), (totals["distinct_placed"] as Dictionary).size()])
	print("    frame-script spans     : %d" % int(totals["frame_spans"]))
	print("    sprite-behaviour spans : %d" % int(totals["sprite_spans"]))
	print("    of them shadowed       : %d  placed, but a narrower frame script"
		% int(totals["shadowed"]) + " covers every frame of the span")
	print("  blind spots")
	print("    sourceless scripts     : %d member(s) in the %d cast(s) scanned carry"
		% [sourceless, _sourceless.size()]
		+ " a script id with no")
	print("                             decoded source, so a reference inside one is"
		+ " invisible")
	print("                             here. e1ca332b measured 64 over all six"
		+ " roots, 0 with a handler.")
	print("    assembled names        : a regex over source cannot see `go to movie"
		+ " \"rat\" & thischar`;")
	print("                             where a title builds a reference this reports"
		+ " nothing.")
