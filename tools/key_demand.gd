extends SceneTree
## Which keys does each *scene* need, and how many scenes need which shape of key?
##
##   godot --headless --path . --script tools/key_demand.gd -- --root rating
##   godot --headless --path . --script tools/key_demand.gd -- --all
##   godot --headless --path . --script tools/key_demand.gd -- --root piposh --file PIPDATA/ROULLETE.dir --scenes
##   godot --headless --path . --script tools/key_demand.gd -- --all --csv keydemand.csv
##
## **Why this exists and why `tools/key_script_survey.gd` was not enough.** That
## tool answers "which key literals does this *title* contain", which is a union
## over a hundred movies: Rating's answer is 24 distinct keys and Piposh 2's is
## most of the alphabet, and neither number says anything about what a finger has
## to be able to do. A phone does not play a title, it plays whichever scene is on
## screen, and that scene needs four arrows, or one letter, or a typed number, or
## nothing at all. Those are four different on-screen controls and the decision
## between them cannot be taken from a union.
##
## So the unit here is the **scene**: a marker-delimited frame span, which is what
## Director calls a room and what `director_labels.gd` already indexes. A movie
## with no markers is one scene.
##
## **This tool computes nothing itself.** Every judgement -- what a script asks
## for, what an action is, which of the seven shapes a scene is -- comes from
## `scenes/preview/key_affordance.gd`, which is the module the *player* runs to
## decide what to put on screen. That is deliberate and it is the whole value of
## the run: a census that passes is a statement about the code that ships, not
## about a re-implementation of it written on the same afternoon. What this file
## owns is the sweep -- roots, containers, markers, and the editable-field walk --
## and the report.
##
## Where the demand comes from, in each movie's own data and nowhere else:
##
##   * **`score.intervals()`** -- every frame script and sprite behaviour carries
##     its own `start`/`end`, so a behaviour that tests `the keyCode = 123` is
##     demand on exactly the frames the score gave it. This is the whole reason the
##     answer can be per scene rather than per movie.
##   * **movie scripts** (`script_type == 3`) apply to every frame of the movie
##     that owns them -- but only their `on keyDown`/`on keyUp` hooks do. A named
##     handler in a movie script runs only where something installs it as `the
##     keyDownScript`, and following that name is what turns `arcade1.dir`'s
##     seventeen assignment sites from a movie-wide smear into demand on the spans
##     that install them.
##   * **editable field members** are the text-entry signal, read from the
##     *member* rather than from the score. Measured in `director_cast.gd:537`: not
##     one of Piposh 2's 816,318 sprite records sets the score's own editable bit,
##     so a reader that looked only at the score would find no typing anywhere in
##     this corpus.
##
## **What a static read cannot see, stated rather than smoothed over.** A handler
## reached only through `do`, a script attached by `puppetSprite` plus `set the
## scriptInstanceList`, and a `keyDownScript` whose *string* is built at run time
## are all invisible here. A `keyDownScript` also outlives the span that installed
## it, so a span's attribution is a lower bound; the `dynamic` count per root is
## the size of that blind spot as far as it can be measured.
##
## Title-agnostic. Nothing here knows what a game is called; `--all` discovers the
## roots, including the untracked ones under `test-games/`, because "what shape is
## Director key demand" is a question about Director titles and not about the six
## that happen to ship.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")
const KeyAffordance := preload("res://scenes/preview/key_affordance.gd")

## Where titles live. `games/` is the shipped six; `test-games/` holds the two
## Itamar corpora, which are gitignored and may not be there -- an absent root is
## skipped rather than reported empty, because "this checkout has no itamar-park"
## and "itamar-park needs no keys" are not the same statement.
const ROOT_DIRS := ["res://games", "res://test-games"]


func _init() -> void:
	var args := Args.parse()
	var only := Args.text(args, "file")
	var show_scenes := Args.flag(args, "scenes")
	var csv_path := Args.text(args, "csv")

	var roots: Array = []
	if Args.flag(args, "all"):
		roots = _roots()
	else:
		var wanted := Args.text(args, "root")
		if wanted != "":
			roots = [_root_path(wanted)]
		else:
			var paths := Paths.new()
			if not paths.load_config():
				print("no game configured: %s must set [game] root" % Paths.CONFIG_PATH)
				quit(1)
				return
			roots = [paths.root]

	var rows: Array[String] = ["root,movie,scene,start,end,shape,keys"]
	var totals: Dictionary = {}
	for root in roots:
		var report := _scan_root(str(root), only)
		_print_root(report, show_scenes)
		for shape in report["shapes"]:
			totals[shape] = int(totals.get(shape, 0)) + int(report["shapes"][shape])
		for row in report["rows"]:
			rows.append(str(row))

	if roots.size() > 1:
		print("")
		print("=== every root ===")
		_print_shapes(totals)
	if csv_path != "":
		var f := FileAccess.open(csv_path, FileAccess.WRITE)
		if f == null:
			print("could not write %s" % csv_path)
		else:
			f.store_string("\n".join(rows) + "\n")
			f.close()
			print("")
			print("wrote %s (%d rows)" % [csv_path, rows.size() - 1])
	quit(0)


## Every title directory under every root dir, as `res://` paths, sorted.
##
## Discovered rather than listed, for the reason `KeySites.roots()` gives: a title
## added to the tree is measured without anything here being edited. `test-games/`
## is included and `KeySites.roots()` does not include it, which is deliberate --
## that function feeds `debug_bindings.gd`, whose subject is which key the *engine*
## may bind in a shipped build.
func _roots() -> Array[String]:
	var out: Array[String] = []
	for base in ROOT_DIRS:
		var dir := DirAccess.open(str(base))
		if dir == null:
			continue
		for sub in dir.get_directories():
			out.append(str(base).path_join(sub))
	out.sort()
	return out


func _root_path(name: String) -> String:
	if name.begins_with("res://"):
		return name
	for base in ROOT_DIRS:
		if DirAccess.dir_exists_absolute(str(base).path_join(name)):
			return str(base).path_join(name)
	return "res://games".path_join(name)


## One title: every movie in it, scene by scene.
func _scan_root(root: String, only: String) -> Dictionary:
	var paths := Paths.new()
	paths.root = root
	var wanted: Array = [only] if only != "" else paths.containers()

	var out := {
		"root": root,
		"movies": 0, "movies_with_demand": 0, "casts_skipped": 0,
		"scenes": 0, "shapes": {}, "dynamic_movies": 0,
		"detail": [], "rows": [], "actions": {},
	}
	for shape in KeyAffordance.Shape.values():
		out["shapes"][shape] = 0

	for relative in wanted:
		var path := paths.resolve(str(relative))
		if path == "":
			continue
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		# A container with no `VWSC` is a cast, not a movie. It has no frames, so it
		# has no scenes, and its scripts reach the player only through a movie that
		# links it -- which is where they are counted.
		if f.ids_of("VWSC").is_empty():
			out["casts_skipped"] = int(out["casts_skipped"]) + 1
			f.close()
			continue
		_scan_movie(out, paths, f, str(relative))
		f.close()
	return out


func _scan_movie(out: Dictionary, paths: Paths, f, relative: String) -> void:
	var score := Score.new()
	if not score.parse(f.read_chunk(f.ids_of("VWSC")[0])):
		return
	out["movies"] = int(out["movies"]) + 1

	var labels := Labels.new()
	var vwlb: Array = f.ids_of("VWLB")
	if not vwlb.is_empty():
		labels.parse(f.read_chunk(vwlb[0]))

	var table := CastTable.new()
	table.open(f, paths)

	# Exactly the three calls the player makes. Anything this file decided for
	# itself would be a second opinion on the question the engine has to answer.
	var handlers := KeyAffordance.handler_index(table)
	var wide := KeyAffordance.movie_wide(table, handlers)
	var spans := KeyAffordance.spans(score, table, handlers)

	var installs := bool(wide["demand"]["installs"])
	for span in spans:
		if bool(span["demand"]["installs"]):
			installs = true
	# A `keyDownScript` outlives the span that installed it -- it stays hooked
	# until something clears it -- so a movie that installs one is counted as
	# `dynamic` even where the demand was attributed to a span. The number is
	# reported rather than folded into the census, because the alternative is to
	# widen every such movie's demand to every frame and lose the attribution that
	# makes the census useful at all.
	if installs:
		out["dynamic_movies"] = int(out["dynamic_movies"]) + 1

	# Editable fields are located by walking the score only when the movie has one
	# at all, which is the cheap half of an expensive question: a `_snapshot` per
	# frame decodes up to 150 sprite records, and across a corpus that is millions
	# of dictionaries built to answer "no" for movies holding no field.
	var editable_frames: Dictionary = {}
	if not (wide["editable"] as Dictionary).is_empty():
		editable_frames = _editable_frames(score, wide["editable"])

	var scenes := _scenes(labels, score.frame_count)
	var any_demand := false
	for scene in scenes:
		var start := int(scene["start"])
		var end := int(scene["end"])
		var d := KeyAffordance.empty()
		KeyAffordance.merge(d, wide["demand"])
		for span in spans:
			if int(span["start"]) > end or int(span["end"]) < start:
				continue
			KeyAffordance.merge(d, span["demand"])
		for frame in editable_frames:
			if int(frame) >= start and int(frame) <= end:
				d["text"] = true
				d["asks"] = true
				break

		var shape: int = KeyAffordance.classify(d)
		out["scenes"] = int(out["scenes"]) + 1
		out["shapes"][shape] = int(out["shapes"][shape]) + 1
		if shape == KeyAffordance.Shape.NONE:
			continue
		any_demand = true
		var actions: int = (KeyAffordance.actions_of(d) as Array).size()
		out["actions"][actions] = int((out["actions"] as Dictionary).get(actions, 0)) + 1
		var listed := _key_list(d)
		out["detail"].append({
			"movie": relative, "scene": scene["name"], "start": start, "end": end,
			"shape": shape, "keys": listed,
		})
		out["rows"].append("%s,%s,%s,%d,%d,%s,%s" % [
			str(out["root"]).get_file(), relative, _csv(str(scene["name"])), start, end,
			KeyAffordance.SHAPE_NAMES[shape], _csv(listed),
		])
	if any_demand:
		out["movies_with_demand"] = int(out["movies_with_demand"]) + 1
	table.close()


## The marker-delimited spans of a movie, as `{name, start, end}`, covering every
## frame exactly once.
##
## Frames before the first marker are their own scene: a movie whose first marker
## sits at frame 30 still plays frames 0-29, and a script attached there is demand
## on a scene that would otherwise not exist. Unnamed markers **do** open a scene --
## they are how an author marks a frame only the score reaches (2,236 of Rating's
## 4,220 entries), and merging them into the previous named one would fold two
## different rooms' key demand together.
func _scenes(labels: Labels, frame_count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if frame_count <= 0:
		return out
	var starts: Array[int] = []
	var names: Array[String] = []
	for marker in labels.markers:
		var at := int(marker["frame"])
		if at < 0 or at >= frame_count:
			continue
		if not starts.is_empty() and starts[starts.size() - 1] == at:
			# Two markers on one frame is one scene with two names; the first wins,
			# which is what `labels` does for a duplicate name.
			continue
		starts.append(at)
		names.append(str(marker["name"]) if str(marker["name"]) != "" else "<unnamed>")
	if starts.is_empty() or starts[0] > 0:
		starts.insert(0, 0)
		names.insert(0, "<before the first marker>")
	for i in starts.size():
		var end := (starts[i + 1] - 1) if i + 1 < starts.size() else frame_count - 1
		out.append({"name": names[i], "start": starts[i], "end": end})
	return out


## Which frames hold a sprite naming one of the movie's editable field members.
##
## Read off the raw channel buffer rather than through `score.frame()`: the member
## number is two bytes at record offset 6, and the decode `frame()` performs builds
## a dictionary per sprite per frame, which is the cost this walk exists to avoid.
## Same replay either way -- only the decode is skipped, which is the argument
## `director_score.tempo_at` already makes for itself.
##
## Cast library is read beside it, because a field numbered 12 in a shared cast and
## a bitmap numbered 12 in the internal one are different members and the pair is
## what tells them apart.
func _editable_frames(score: Score, editable: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for i in score.frame_count:
		var buffer := score.channel_buffer(i)
		for channel in range(1, score.channels_displayed + 1):
			var at := Score.SPRITE_RECORD_SIZE * (channel + Score.CHANNEL_BIAS)
			if at + Score.SPRITE_RECORD_SIZE > buffer.size():
				break
			var member := (buffer[at + 6] << 8) | buffer[at + 7]
			if member == 0:
				continue
			var lib := (buffer[at + 4] << 8) | buffer[at + 5]
			if lib == Score.OWN_CAST_LIB or lib == 0:
				lib = 1
			if editable.has("%d:%d" % [lib, member]):
				out[i] = true
				break
	return out


## The keys a scene needs, as a human reads them: one entry per action, with the
## action's alternates joined by `/`. The same grouping the census counts and the
## same one the overlay draws, through the same function, so the printout and the
## number cannot disagree about what a scene needs.
func _key_list(d: Dictionary) -> String:
	var out: Array[String] = []
	for action in KeyAffordance.actions_of(d):
		out.append(KeyAffordance.label_of(action))
	out.sort()
	if out.is_empty():
		return "(any key)" if not bool(d.get("text", false)) else "(typed)"
	return " ".join(out)


func _csv(text: String) -> String:
	return "\"%s\"" % text.replace("\"", "\"\"")


func _print_root(report: Dictionary, show_scenes: bool) -> void:
	print("")
	print("=== %s ===" % report["root"])
	print("movies     : %d  (%d with key demand, %d casts skipped)" % [
		report["movies"], report["movies_with_demand"], report["casts_skipped"]])
	print("scenes     : %d marker-delimited spans" % report["scenes"])
	print("dynamic    : %d movie(s) install a keyDownScript/keyUpScript at run time" % [
		report["dynamic_movies"]])
	_print_shapes(report["shapes"])
	_print_actions(report["actions"])
	if show_scenes:
		print("")
		print("  scenes that need a key")
		for row in report["detail"]:
			print("    %-28s %-24s %5d-%-5d %-11s %s" % [
				row["movie"], row["scene"], row["start"], row["end"],
				KeyAffordance.SHAPE_NAMES[row["shape"]], row["keys"]])


func _print_shapes(shapes: Dictionary) -> void:
	var total := 0
	for shape in shapes:
		total += int(shapes[shape])
	if total == 0:
		return
	print("")
	for shape in KeyAffordance.Shape.values():
		var n := int(shapes.get(shape, 0))
		var share := 100.0 * float(n) / float(total)
		print("  %-11s %6d  %5.1f%%  %s" % [
			KeyAffordance.SHAPE_NAMES[shape], n, share, "#".repeat(int(round(share / 2.0)))])
	print("  %-11s %6d" % ["total", total])


## How many buttons an overlay would draw, which is the number the design decision
## actually turns on. A census of *shapes* can hide it -- "a few keys" covers one
## button and six -- and one button is a tap anywhere while six is a row.
func _print_actions(actions: Dictionary) -> void:
	if actions.is_empty():
		return
	var counts: Array = actions.keys()
	counts.sort()
	print("")
	print("  buttons an overlay would draw, over the scenes that need a key")
	for n in counts:
		print("    %2d %s %d" % [int(n), "action " if int(n) == 1 else "actions", int(actions[n])])
