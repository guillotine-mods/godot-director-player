extends SceneTree
## Does any sprite change size while nothing about it changes?
##
##   godot --headless --script tools/drawn_size_stability.gd
##   godot --headless --script tools/drawn_size_stability.gd -- --file PIPDATA/WRESTLE.dir
##   godot --headless --script tools/drawn_size_stability.gd -- --worst 20
##
## It sweeps every container under the configured root by default rather than the
## boot movie, because the shape it looks for is spread thinly -- 419 runs across
## 61 movies in Piposh 2 -- and a one-movie default would have gated nothing. The
## whole corpus costs about 40 seconds.
##
## The invariant, and why it is the right one to assert.
##
## `tools/drawn_size.gd` scored the two candidate sizing rules against
## `assets/render_model/<movie>/frames.json`, and that comparison cannot settle
## the question: `frames.json` carries the exporter's own `x`/`y`, computed from
## the same score rect, so "the sprite's own size reproduces the export" is an
## arithmetic identity rather than a fact about Director. Worse, the renderer
## that drew from that export never used those numbers -- `RenderModelLoader`
## `._resolve_sprite_rects` rewrites the rect and the top-left of every
## *unstretched* sprite at load, 22,806 of them in Piposh 2, before the first
## frame is drawn. The picture known to have been right is the corrected one.
##
## So this harness asks nothing of the export. It asserts a property the player
## can see:
##
##   **A sprite the author did not mark as stretched must not change size while
##   its member and its position hold still.**
##
## Art that pulses wider for a few frames and snaps back, with the same picture
## on the same spot throughout, is not something an author can express -- the
## Score has no way to say it and no reason to want it. A run that does that is
## the renderer reading authoring residue as an instruction.
##
## A run is exempt when any of its records sets the stretch flag: the flag is the
## author saying "I resized this deliberately", and a deliberate resize across a
## span -- a zoom, a perspective walk -- is exactly what it is for. So is a run
## whose member is a shape (`sprite_geometry.KEEPS_ITS_OWN_SIZE`): a shape has no
## natural size, its rect *is* the sprite's by design, so a score that changes it
## is the author changing it.
##
## **Text fields used to be exempt here too, and are not any more.** They were
## exempt because `sprite_geometry` excepted them from the dimension reset, and
## that turned out to be half a rule -- the reference goes on to push the widget's
## laid-out size back onto the sprite, so a field's box is its member's and the
## score's is residue like anybody else's. Dropping the exemption took the exempt
## count from 153 runs to 8 and left the unstable count at 0, which is the useful
## half of the answer: none of the field runs this now measures pulses.
##
## The measurement is reported beside the verdict: how many records the score's
## rect and the member's natural size disagree on, split by the flag, so the same
## run says both what is broken and how much of the corpus the rule touches.
##
## Title-agnostic: it names no movie, channel or member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")

## A rect within this many pixels of the member's natural size on both axes is
## the natural size. The member's stored rect and the score's are written by
## different parts of the authoring tool and one pixel is not a resize anybody
## authored or anybody can see.
const NATURAL_SLACK := 1


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


func _init() -> void:
	var args := Args.parse()
	var worst_limit := Args.number(args, "worst", 12)
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var targets: Array[String] = []
	var only: String = Args.text(args, "file", "")
	if only == "":
		_walk(paths.root, targets)
		targets.sort()
	else:
		var one: String = paths.resolve(only)
		if one == "":
			print("no such container")
			quit(1)
			return
		targets.append(one)

	var movies := 0
	var records := 0
	# How far the two candidate rules part company, split by the stretch flag.
	var differs := {true: 0, false: 0}
	var same := {true: 0, false: 0}
	var runs := 0
	var runs_exempt := 0
	var runs_own_size := 0
	var unstable: Array[Dictionary] = []
	var unstable_before: Array[Dictionary] = []

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

		# channel -> the run of one member at one place currently open on it
		var open_runs: Dictionary = {}
		for i in score.frame_count:
			var present: Dictionary = {}
			for sprite_value in score.frame(i).get("sprites", []):
				var sprite: Dictionary = sprite_value
				var channel := int(sprite["channel"])
				present[channel] = true
				var member: Dictionary = table.get_member(
					int(sprite["cast_lib"]), int(sprite["cast_id"])
				)
				if member.is_empty() or int(member.get("width", 0)) <= 0:
					# A shape, a script or a member this cast does not describe.
					# Nothing to compare a size against, so it cannot be counted
					# either way -- and it closes any run open on the channel,
					# because the run is about one member's geometry.
					if open_runs.has(channel):
						_close_run(open_runs[channel], unstable, unstable_before)
						open_runs.erase(channel)
					continue
				records += 1
				var stretched := bool(sprite["stretch"])
				var natural := Vector2(
					float(member.get("width", 0)), float(member.get("height", 0))
				)
				var stated := Vector2(float(sprite["width"]), float(sprite["height"]))
				if (
					absf(stated.x - natural.x) <= NATURAL_SLACK
					and absf(stated.y - natural.y) <= NATURAL_SLACK
				):
					same[stretched] = int(same[stretched]) + 1
				else:
					differs[stretched] = int(differs[stretched]) + 1

				# The run is keyed on everything the player would call "the same
				# picture in the same place": the member and the registration
				# point. A sprite that moves or swaps art is allowed to resize.
				var key := "%d:%d@%d,%d" % [
					int(sprite["cast_lib"]), int(sprite["cast_id"]),
					int(sprite["loc_h"]), int(sprite["loc_v"]),
				]
				var run: Dictionary = open_runs.get(channel, {})
				if run.is_empty() or str(run["key"]) != key:
					if not run.is_empty():
						_close_run(run, unstable, unstable_before)
					run = {
						"movie": movie, "channel": channel, "key": key,
						"start": i, "natural": natural, "stretched": false,
						"type": int(member.get("type", 0)),
						"type_name": str(member.get("type_name", "")),
						"sizes": [], "seen": {},
						"was_sizes": [], "was_seen": {},
					}
					open_runs[channel] = run
				run["end"] = i
				if stretched:
					run["stretched"] = true
				var drawn := Geometry.drawn_size(sprite, member)
				if not run["seen"].has(drawn):
					run["seen"][drawn] = true
					run["sizes"].append(drawn)
				# The same run scored under the rule this replaced -- the score's
				# own rect whenever it states one -- so the harness reports the
				# attribution as well as the verdict, and a revert is a number
				# rather than an argument.
				var was := Vector2(stated) if stated.x > 0.0 and stated.y > 0.0 else natural
				if not run["was_seen"].has(was):
					run["was_seen"][was] = true
					run["was_sizes"].append(was)
			for channel in open_runs.keys():
				if present.has(channel):
					continue
				_close_run(open_runs[channel], unstable, unstable_before)
				open_runs.erase(channel)
		for channel in open_runs.keys():
			_close_run(open_runs[channel], unstable, unstable_before)
		runs += _runs
		runs_exempt += _exempt
		runs_own_size += _own_size
		_runs = 0
		_exempt = 0
		_own_size = 0
		table.close()
		f.close()

	print("%d movie(s), %d sprite records resolved to a member with a size"
		% [movies, records])
	print("")
	print("the score's rect against the member's natural size (+/-%d px):" % NATURAL_SLACK)
	for stretched in [false, true]:
		var s := int(same[stretched])
		var d := int(differs[stretched])
		print("  stretch %-5s  agree %7d   differ %7d  of %d" % [
			"set" if stretched else "clear", s, d, s + d,
		])
	print("")
	print("runs of one member at one place: %d, %d author-stretched, %d a shape"
		% [runs, runs_exempt, runs_own_size])
	print("unstable runs (drawn size changes with nothing else changing): %d"
		% unstable.size())
	print("  under the rule this replaced, the score's own rect:              %d"
		% unstable_before.size())
	if not unstable.is_empty():
		unstable.sort_custom(func(a, b): return float(a["ratio"]) > float(b["ratio"]))
		print("")
		print("worst:")
		for row in unstable.slice(0, worst_limit):
			print("  %-16s ch%-4d %-20s %-9s f%d..%d  natural %dx%d  drawn %s" % [
				str(row["movie"]), int(row["channel"]), str(row["key"]),
				str(row["type_name"]), int(row["start"]), int(row["end"]),
				int(row["natural"].x), int(row["natural"].y), str(row["sizes"]),
			])

	var h := Harness.new()
	h.begin("no sprite resizes while its picture and its place hold still")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	h.check("resolved members", records > 0, "%d records" % records)
	h.check(
		"every unstretched run holds one drawn size",
		unstable.is_empty(),
		"%d runs pulse" % unstable.size()
	)
	h.complete("no sprite resizes while its picture and its place hold still")
	quit(h.finish("drawn size stability across the corpus"))


var _runs := 0
var _exempt := 0
var _own_size := 0


## Score one finished run. Unstable means the drawn size took more than one value
## while the member, the registration point and the channel all held still.
func _close_run(run: Dictionary, unstable: Array[Dictionary],
		unstable_before: Array[Dictionary]) -> void:
	_runs += 1
	if bool(run["stretched"]):
		_exempt += 1
		return
	if Geometry.KEEPS_ITS_OWN_SIZE.has(int(run["type"])):
		_own_size += 1
		return
	if (run["was_sizes"] as Array).size() > 1:
		unstable_before.append(run)
	var sizes: Array = run["sizes"]
	if sizes.size() < 2:
		return
	var natural: Vector2 = run["natural"]
	var ratio := 1.0
	for size_value in sizes:
		var size: Vector2 = size_value
		ratio = maxf(ratio, maxf(
			size.x / maxf(natural.x, 1.0), size.y / maxf(natural.y, 1.0)))
	run["ratio"] = ratio
	unstable.append(run)
