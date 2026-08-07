extends SceneTree
## Does the score's sprite rect agree with the member's natural size, and does it
## ever change while the member does not?
##
##   godot --headless --script tools/sprite_size_survey.gd -- --all
##   godot --headless --script tools/sprite_size_survey.gd -- --file PIPDATA/OPENING.dir
##   godot --headless --script tools/sprite_size_survey.gd -- --all --worst 20
##
## Why this exists. `scenes/director_preview.gd:_drawn_size` draws every sprite
## at the score's own width and height, falling back to the member only for a
## degenerate rect. That rule was settled against the pre-decoded export, and the
## export is gone — so the rule now has no evidence behind it at all, and a
## second, older title is loaded whose score was written by a different authoring
## version. If that title's records carry authoring residue in the rect, the
## renderer is stretching sprites Director drew at their natural size, and the
## symptom would be exactly "some sprites stretch and come back".
##
## Two measurements, because they answer different halves of it:
##
## **Agreement.** How often the score's rect equals the member's natural size,
## split by the stretch flag. Residue would show as widespread disagreement on
## *unstretched* records; deliberate authoring shows as disagreement clustered on
## the stretched ones.
##
## **Excursions.** A run of consecutive frames on one channel holding one member
## is a run Director would draw at one size unless the author resized it. Every
## run whose rect takes more than one value is reported, with the values and how
## far each is from the member's natural size. A sprite that "stretches outward
## and back in again" is a run whose sizes leave the natural size and return to
## it; that is a shape this counts rather than a shape anyone has to eyeball.
##
## Title-agnostic: it names no movie, channel or member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")

## A rect within this many pixels of the member's natural size on both axes is
## "the natural size". Not zero: a member's stored rect and the score's rect are
## written by different parts of the authoring tool and a one-pixel disagreement
## is not a resize anybody authored or anybody can see.
const NATURAL_SLACK := 1

## Run counters. Members rather than locals because `_close_run` is called from
## three places and GDScript has no out-parameter for an int; threading them
## through the run dictionary was tried first and lost counts.
var _runs := 0
var _runs_multi := 0
var _excursions := 0
var _rows: Array[Dictionary] = []


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


func _is_natural(w: int, h: int, m: Dictionary) -> bool:
	var mw := int(m.get("width", 0))
	var mh := int(m.get("height", 0))
	if mw <= 0 or mh <= 0:
		return false
	return absi(w - mw) <= NATURAL_SLACK and absi(h - mh) <= NATURAL_SLACK


func _init() -> void:
	var args := Args.parse()
	var worst_limit := Args.number(args, "worst", 12)
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var targets: Array[String] = []
	if Args.flag(args, "all"):
		_walk(paths.root, targets)
		targets.sort()
	else:
		var one: String = paths.resolve(Args.text(args, "file", paths.boot_movie))
		if one == "":
			print("no such container")
			quit(1)
			return
		targets.append(one)

	var movies := 0
	var records := 0
	var resolved := 0
	# agreement with the member's natural size, split by the stretch flag
	var agree := {true: 0, false: 0}
	var disagree := {true: 0, false: 0}

	for path in targets:
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
		var table := CastTable.new()
		if not table.open(f, paths):
			table.close()
			f.close()
			continue
		movies += 1
		var movie := path.get_file()

		# channel -> the run currently open on it
		var open_runs: Dictionary = {}
		for i in score.frame_count:
			var present: Dictionary = {}
			for sprite_value in score.frame(i).get("sprites", []):
				var sprite: Dictionary = sprite_value
				records += 1
				var channel := int(sprite["channel"])
				var lib := int(sprite["cast_lib"])
				var id := int(sprite["cast_id"])
				var w := int(sprite["width"])
				var h := int(sprite["height"])
				var stretched := bool(sprite["stretch"])
				present[channel] = true
				var m: Dictionary = table.get_member(lib, id)
				if not m.is_empty() and int(m.get("width", 0)) > 0:
					resolved += 1
					if _is_natural(w, h, m):
						agree[stretched] = int(agree[stretched]) + 1
					else:
						disagree[stretched] = int(disagree[stretched]) + 1
				var key := "%d:%d" % [lib, id]
				var run: Dictionary = open_runs.get(channel, {})
				if run.is_empty() or str(run["key"]) != key:
					if not run.is_empty():
						_close_run(run)
					run = {
						"movie": movie, "channel": channel, "key": key,
						"start": i, "sizes": {}, "order": [],
						"natural": Vector2i(int(m.get("width", 0)), int(m.get("height", 0))),
						"stretched": stretched,
					}
					open_runs[channel] = run
				var size := Vector2i(w, h)
				if not run["sizes"].has(size):
					run["sizes"][size] = 0
					run["order"].append(size)
				run["sizes"][size] = int(run["sizes"][size]) + 1
				run["end"] = i
			# A channel that emptied ends its run.
			for channel in open_runs.keys():
				if present.has(channel):
					continue
				_close_run(open_runs[channel])
				open_runs.erase(channel)
		for channel in open_runs.keys():
			_close_run(open_runs[channel])
		table.close()
		f.close()

	print("%d movie(s), %d sprite records, %d resolved to a member with a size"
		% [movies, records, resolved])
	print("")
	print("score rect versus the member's natural size (+/-%d px):" % NATURAL_SLACK)
	for stretched in [false, true]:
		var a := int(agree[stretched])
		var d := int(disagree[stretched])
		var n := a + d
		print("  stretch %-5s  natural %7d (%5.1f%%)   resized %7d (%5.1f%%)  of %d" % [
			"set" if stretched else "clear", a, 100.0 * a / maxi(n, 1),
			d, 100.0 * d / maxi(n, 1), n,
		])
	print("")
	print("runs of one member on one channel: %d, of which %d change size, %d leave"
		% [_runs, _runs_multi, _excursions]
		+ " the natural size and return")
	if not _rows.is_empty():
		_rows.sort_custom(func(a, b): return float(a["ratio"]) > float(b["ratio"]))
		print("")
		print("widest excursions:")
		for row in _rows.slice(0, worst_limit):
			print("  %-16s ch%-4d %s  natural %dx%d  x%.2f  sizes %s" % [
				str(row["movie"]), int(row["channel"]), str(row["key"]),
				int(row["natural"].x), int(row["natural"].y),
				float(row["ratio"]), str(row["sizes"]),
			])

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	h.check("resolved members", resolved > 0, "%d records" % resolved)
	h.complete("the survey ran")
	quit(h.finish("sprite rect versus member natural size"))


## Score one finished run into the survey's counters.
func _close_run(run: Dictionary) -> void:
	_runs += 1
	var order: Array = run["order"]
	if order.size() > 1:
		_runs_multi += 1
		var natural: Vector2i = run["natural"]
		if natural.x > 0 and natural.y > 0:
			# "Outward and back in again": the run both visits the natural size
			# and visits something else, in some order. Anything else is a
			# one-way resize, which is ordinary authoring.
			var visits_natural := false
			var visits_other := false
			var ratio := 1.0
			for size_value in order:
				var size: Vector2i = size_value
				if absi(size.x - natural.x) <= NATURAL_SLACK \
						and absi(size.y - natural.y) <= NATURAL_SLACK:
					visits_natural = true
				else:
					visits_other = true
				ratio = maxf(ratio, maxf(
					float(size.x) / maxf(natural.x, 1.0),
					float(size.y) / maxf(natural.y, 1.0)))
			if visits_natural and visits_other:
				_excursions += 1
				_rows.append({
					"movie": run["movie"], "channel": run["channel"],
					"key": run["key"], "natural": natural, "ratio": ratio,
					"sizes": order,
				})
