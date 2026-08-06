extends SceneTree
## `DirectorScore` against the exported `frames.json`, frame by frame.
##
##   godot --headless --script tools/score_diff.gd -- --file EXODUS.DIR
##   godot --headless --script tools/score_diff.gd -- --file MURDER1.DIR --report 20
##   godot --headless --script tools/score_diff.gd -- --file DAY1.DIR --frames 200
##   godot --headless --script tools/score_diff.gd -- --all
##
## One movie by default. `--all` sweeps the corpus and reads 188 MB of JSON, so
## it is opt-in for the reason `director_frames.gd` gives: a sweep that runs
## because an argument failed to parse is indistinguishable from a hang.
##
## `assets/render_model/<MOVIE>/frames.json` is the oracle. It is a decode of the
## same `VWSC` bytes by a separate pipeline (`tools/director_score.py`), it is
## what the shipping runtime draws from, and it is verified against the score
## chunk field by field before it is trusted (`tools/generate_sprite_stretch.py`).
## Where the two disagree, this reader is wrong.
##
## This proves the *reader*, never fidelity (AGENTS.md): reproducing the export
## says the container path agrees with the export, not that either agrees with
## Director. It is still the sharpest question available, because the export is
## the input the port currently renders correctly.
##
## Three things the oracle cannot answer flat out, and how each is handled:
##
## STRETCH. The exporter masks the ink byte to six bits, so `frames.json` carries
## no stretch flag at all — there is not one `"stretch"` key in the whole export.
## `assets/render_model/sprite_stretch.json` is the side-car that recovers it and
## is the only oracle for that bit. Both are consulted: if a re-export ever began
## emitting the key it would be compared rather than silently ignored, and a
## movie the side-car refused is reported as unanswerable instead of as a pass.
##
## CASE. `DirectorLabels` lowercases its label keys and the export does not, so
## label names AND marker names are compared case-insensitively. A name that
## differs only in case is therefore NOT reported by this tool.
##
## REPLAY PATH. `DirectorScore.frame()` materialises a frame lazily, from the
## nearest keyframe snapshot. A bug there shows up as a frame decoded correctly
## on one access pattern and not another, which a single sequential walk cannot
## see. So every movie is read three ways — sequentially, in shuffled order, and
## with the keyframe table emptied so `frame()` degrades to a full linear replay
## from frame 0 — and the three are compared against the export and against each
## other. Field offsets being wrong looks identical on all three passes; a
## replay bug does not.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")

const MODEL_ROOT := "res://assets/render_model"
const STRETCH_SIDECAR := "res://assets/render_model/sprite_stretch.json"

## Everything both sides read out of the same 48 bytes. Agreeing on the member
## but not on the rect would mean this reader is off by a field, so the whole
## record is compared and not only the parts a renderer happens to use.
const SPRITE_FIELDS := [
	"cast_lib", "cast_id", "loc_h", "loc_v", "width", "height",
	"ink", "sprite_type", "fore_color", "back_color",
]
const FRAME_FIELDS := ["frame_script", "tempo", "tempo_cue", "delay_ms", "wait_click", "fps"]
## What the exporter masked the ink byte with before writing it.
const INK_MASK := 0x3F
## Frames the random-access and linear-replay passes visit. Enough to catch a
## replay that is wrong on one path, cheap enough to run on every movie.
const SAMPLE_FRAMES := 96
## Fixed, so two runs sample the same frames and a divergence stays reproducible.
const SAMPLE_SEED := 20250806
## Divergences held in full. The count and the histogram are unbounded; the
## bodies are not, because a wrong offset produces one per sprite per frame.
const KEEP_DEFAULT := 8


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var side_car := _side_car()
	var limit := Args.number(args, "frames", 0)
	var sample := Args.number(args, "sample", SAMPLE_FRAMES)
	var keep := Args.number(args, "report", KEEP_DEFAULT)
	var h := Harness.new()

	if Args.flag(args, "all"):
		quit(_sweep(h, paths, side_car, limit, sample, keep))
		return

	var wanted := Args.text(args, "file", paths.boot_movie)
	var path = paths.resolve(wanted)
	if path == "":
		print("no such container under %s: %s" % [paths.root, wanted])
		quit(1)
		return

	var report := _diff_movie(path, side_car, limit, sample, keep)
	_print_report(report, keep)
	h.begin("%s: the score read from the container matches the export" % report["movie"])
	_check_report(h, report)
	h.complete("%s: the score read from the container matches the export" % report["movie"])
	quit(h.finish("the container's score reproduces the export the port renders from"))


# --- one movie ---------------------------------------------------------------


## Compares one container's score against its exported `frames.json`. Never
## raises: a movie with no score or no export is a fact about the corpus and
## comes back as a `skip`, not as a failure.
func _diff_movie(path: String, side_car: Dictionary, limit: int, sample_size: int, keep: int) -> Dictionary:
	var model := _model_dir(path)
	var report := {
		"movie": model.get_file() if model != "" else path.get_file().get_basename(),
		"path": path,
		"skip": "",
		"frames_read": 0,
		"frames_export": 0,
		"channels_displayed": 0,
		"sprites": 0,
		"diff": _new_diff(keep),
		"notes": [] as Array[String],
		"replay_checked": 0,
		"replay_mismatch": 0,
		"export_has_stretch": false,
		"side_car_has_movie": false,
		"labels_ok": true,
		"markers_ok": true,
		"parse_ms": 0.0,
		"compare_ms": 0.0,
	}
	if model == "":
		report["skip"] = "no exported frames.json"
		return report

	var f := ContainerFile.new()
	if not f.open(path):
		report["skip"] = f.error
		return report
	var vwsc: Array = f.ids_of("VWSC")
	if vwsc.is_empty():
		f.close()
		report["skip"] = "no VWSC: a cast, not a playable movie"
		return report

	var text := FileAccess.get_file_as_string(model.path_join("frames.json"))
	if text == "":
		f.close()
		report["skip"] = "frames.json is unreadable"
		return report
	# Cheaper and more exact than walking every sprite: if the substring is not
	# in the file, the exporter emitted no stretch flags anywhere in this movie.
	report["export_has_stretch"] = text.contains("\"stretch\"")
	var parsed = JSON.parse_string(text)
	text = ""
	if not (parsed is Dictionary):
		f.close()
		report["skip"] = "frames.json is not an object"
		return report
	var export_data: Dictionary = parsed
	var exported: Array = export_data.get("frames", [])
	report["frames_export"] = exported.size()

	# Which VWSC. The export names the chunk it was decoded from, so comparing a
	# different one would be comparing two movies and blaming the reader.
	var wanted_id := _chunk_id(str(export_data.get("score_chunk", "")))
	var chunk_id: int = int(vwsc[0])
	if wanted_id >= 0 and wanted_id != chunk_id:
		if vwsc.has(wanted_id):
			report["notes"].append(
				"the export decoded VWSC-%d; ids_of(\"VWSC\")[0] is %d" % [wanted_id, chunk_id]
			)
			chunk_id = wanted_id
		else:
			report["notes"].append(
				"the export names VWSC-%d, which this container does not have" % wanted_id
			)

	var started := Time.get_ticks_usec()
	var score := Score.new()
	var ok := score.parse(f.read_chunk(chunk_id))
	report["parse_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	if not ok:
		f.close()
		report["skip"] = score.error
		return report
	report["frames_read"] = score.frame_count
	report["channels_displayed"] = score.channels_displayed

	var labels := Labels.new()
	var vwlb: Array = f.ids_of("VWLB")
	if not vwlb.is_empty():
		labels.parse(f.read_chunk(vwlb[0]))
	f.close()

	var diff: Dictionary = report["diff"]
	_diff_labels(diff, report, labels, export_data)

	var stretch_frames: Dictionary = {}
	if side_car.has(report["movie"]):
		report["side_car_has_movie"] = true
		stretch_frames = side_car[report["movie"]].get("frames", {})

	var count: int = min(score.frame_count, exported.size())
	if limit > 0:
		count = min(count, limit)
	if score.frame_count != exported.size():
		_note(diff, -1, -1, "frame_count", exported.size(), score.frame_count, "header")

	# The sample is drawn before the sequential pass so that pass can keep the
	# frames the other two will re-derive, and compared like for like.
	var sample := _sample(count, sample_size)
	var held: Dictionary = {}

	started = Time.get_ticks_usec()

	# --- pass 1: sequentially, the way the runtime plays a movie -------------
	for i in count:
		var ours: Dictionary = score.frame(i)
		if sample.has(i):
			held[i] = ours
		report["sprites"] += _diff_frame(
			diff, report, i, ours, exported[i], stretch_frames, "seq"
		)

	# --- pass 2: the same frames out of order, the way a `go` does ------------
	for i in _shuffled(sample):
		_diff_frame(diff, report, i, score.frame(i), exported[i], stretch_frames, "random")

	# --- pass 3: keyframes off, so `frame()` replays from frame 0 ------------
	# Emptying the table is what makes `frame()` fall through to a fresh buffer
	# and apply every delta from 0. It is the same code path with the shortcut
	# removed, which is the only way to ask whether the shortcut is the problem.
	var saved: Dictionary = score._keyframes
	score._keyframes = {}
	score._cached_index = -1
	for i in _shuffled(sample):
		var linear: Dictionary = score.frame(i)
		_diff_frame(diff, report, i, linear, exported[i], stretch_frames, "linear")
		report["replay_checked"] += 1
		if not _frames_agree(held.get(i, {}), linear):
			report["replay_mismatch"] += 1
			_note(diff, i, -1, "keyframe_replay", "the linear replay", "the keyframe replay", "replay")
	score._keyframes = saved
	score._cached_index = -1

	report["compare_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return report


## One frame, every channel and every frame-level field. Returns how many sprite
## records were compared, so a movie that silently compares nothing is visible.
func _diff_frame(
	diff: Dictionary,
	report: Dictionary,
	index: int,
	ours: Dictionary,
	want: Dictionary,
	stretch_frames: Dictionary,
	via: String,
) -> int:
	var mine: Dictionary = {}
	for sprite in ours.get("sprites", []):
		mine[int(sprite["channel"])] = sprite
	var theirs: Dictionary = {}
	for sprite in want.get("sprites", []):
		theirs[int(sprite["channel"])] = sprite

	for channel in theirs:
		if not mine.has(channel):
			_note(diff, index, channel, "channel_missing", "occupied", "empty", via)
	for channel in mine:
		if not theirs.has(channel):
			_note(diff, index, channel, "channel_extra", "empty", "occupied", via)

	var compared := 0
	for channel in mine:
		if not theirs.has(channel):
			continue
		compared += 1
		var got: Dictionary = mine[channel]
		var expect: Dictionary = theirs[channel]
		for field in SPRITE_FIELDS:
			var wanted = expect.get(field, null)
			if field == "ink" and wanted != null:
				wanted = int(wanted) & INK_MASK
			if not _same(wanted, got.get(field, null)):
				_note(diff, index, channel, field, wanted, got.get(field, null), via)
		_diff_stretch(diff, report, index, channel, got, expect, stretch_frames, via)

	for field in FRAME_FIELDS:
		if not _same(want.get(field, null), ours.get(field, null)):
			_note(diff, index, -1, field, want.get(field, null), ours.get(field, null), via)
	return compared


## The stretch flag against both oracles, and against neither silently.
func _diff_stretch(
	diff: Dictionary,
	report: Dictionary,
	index: int,
	channel: int,
	got: Dictionary,
	expect: Dictionary,
	stretch_frames: Dictionary,
	via: String,
) -> void:
	var ours := bool(got.get("stretch", false))
	# The exporter masks the flag away, so a missing key means "not recorded",
	# not "false". Only a movie that carries the key anywhere can be read that
	# way, or every stretched sprite in the corpus would be a false divergence.
	if bool(report["export_has_stretch"]):
		if bool(expect.get("stretch", false)) != ours:
			_note(diff, index, channel, "stretch/frames.json",
				bool(expect.get("stretch", false)), ours, via)
	if not bool(report["side_car_has_movie"]):
		return
	var listed: Array = stretch_frames.get(str(index), [])
	var wanted := listed.has(channel) or listed.has(float(channel))
	if wanted != ours:
		_note(diff, index, channel, "stretch/sprite_stretch.json", wanted, ours, via)


## Labels and markers, compared case-insensitively because `DirectorLabels`
## lowercases its keys and the export does not.
func _diff_labels(diff: Dictionary, report: Dictionary, labels, export_data: Dictionary) -> void:
	var want_labels: Dictionary = {}
	for key in export_data.get("labels", {}):
		var lowered := str(key).to_lower()
		# First occurrence wins, which is what `DirectorLabels` does and what
		# Director did; two names differing only in case collapse to one here.
		if not want_labels.has(lowered):
			want_labels[lowered] = int(export_data["labels"][key])
	for key in want_labels:
		if not labels.labels.has(key):
			_note(diff, -1, -1, "label_missing", key, "absent", "labels")
			report["labels_ok"] = false
		elif int(labels.labels[key]) != int(want_labels[key]):
			_note(diff, -1, -1, "label_frame", "%s=%d" % [key, want_labels[key]],
				"%s=%d" % [key, int(labels.labels[key])], "labels")
			report["labels_ok"] = false
	for key in labels.labels:
		if not want_labels.has(key):
			_note(diff, -1, -1, "label_extra", "absent", key, "labels")
			report["labels_ok"] = false

	var want_markers: Array = export_data.get("markers", [])
	if want_markers.size() != labels.markers.size():
		_note(diff, -1, -1, "marker_count", want_markers.size(), labels.markers.size(), "labels")
		report["markers_ok"] = false
	for i in min(want_markers.size(), labels.markers.size()):
		var expect: Dictionary = want_markers[i]
		var got: Dictionary = labels.markers[i]
		if int(expect.get("frame", -1)) != int(got.get("frame", -2)):
			_note(diff, -1, i, "marker_frame",
				expect.get("frame", null), got.get("frame", null), "labels")
			report["markers_ok"] = false
		elif str(expect.get("name", "")).to_lower() != str(got.get("name", "")).to_lower():
			_note(diff, -1, i, "marker_name", expect.get("name", ""), got.get("name", ""), "labels")
			report["markers_ok"] = false


# --- the corpus --------------------------------------------------------------


func _sweep(h, paths, side_car: Dictionary, limit: int, sample: int, keep: int) -> int:
	var rows: Array[Dictionary] = []
	var skipped: Array[String] = []
	var started := Time.get_ticks_usec()

	for path in _find(paths.root):
		var report := _diff_movie(path, side_car, limit, sample, 2)
		if str(report["skip"]) != "":
			skipped.append("%-12s %s" % [report["movie"], report["skip"]])
			continue
		rows.append(report)

	var clean := 0
	var frames := 0
	var sprites := 0
	var replay_bad := 0
	for report in rows:
		frames += int(report["frames_read"])
		sprites += int(report["sprites"])
		replay_bad += int(report["replay_mismatch"])
		if int(report["diff"]["count"]) == 0:
			clean += 1

	# Sorted by how far in the reader survives. A movie that diverges at frame 0
	# and one that diverges at frame 200 are different bugs, and the ordering is
	# what makes that readable at a glance.
	rows.sort_custom(func(a, b): return _first_frame(a) < _first_frame(b))
	print("")
	print("movie         frames  sprites   diverge  first  field")
	for report in rows:
		var diff: Dictionary = report["diff"]
		var first: Dictionary = diff["first"]
		print("%-12s  %6d  %7d  %8d  %5s  %s" % [
			report["movie"], report["frames_read"], report["sprites"], int(diff["count"]),
			str(int(first["frame"])) if not first.is_empty() else "-",
			str(first["field"]) if not first.is_empty() else "",
		])

	if not skipped.is_empty():
		print("")
		print("skipped (%d):" % skipped.size())
		for line in skipped:
			print("  %s" % line)

	print("")
	print("movies     : %d compared, %d matching the export exactly" % [rows.size(), clean])
	print("frames     : %d" % frames)
	print("sprites    : %d records compared" % sprites)
	print("elapsed    : %.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))

	# The two the report is about are printed in full, whatever the sweep found.
	for report in rows:
		if str(report["movie"]).to_upper() in ["EXODUS", "MURDER1"]:
			print("")
			_print_report(report, keep)

	h.begin("every movie's score matches its export")
	h.check("movies were compared", rows.size() > 0, "%d" % rows.size())
	h.check("sprite records were compared", sprites > 0, "%d" % sprites)
	h.check("every movie matches the export", clean == rows.size(),
		"%d of %d diverge" % [rows.size() - clean, rows.size()])
	h.check("the keyframe replay agrees with a linear replay everywhere",
		replay_bad == 0, "%d frame(s) differ by access path" % replay_bad)
	h.complete("every movie's score matches its export")
	return h.finish("the container's score reproduces the export the port renders from")


# --- reporting ---------------------------------------------------------------


func _print_report(report: Dictionary, keep: int) -> void:
	print("%s  (%s)" % [report["movie"], report["path"]])
	if str(report["skip"]) != "":
		print("  skipped: %s" % report["skip"])
		return
	print("  frames     : %d read, %d exported  (%d channels displayed)" % [
		report["frames_read"], report["frames_export"], report["channels_displayed"],
	])
	print("  compared   : %d sprite records, parse %.0f ms, compare %.0f ms" % [
		report["sprites"], report["parse_ms"], report["compare_ms"],
	])
	for note in report["notes"]:
		print("  note       : %s" % note)
	if not bool(report["export_has_stretch"]):
		print("  note       : frames.json carries no \"stretch\" key; only the side-car can answer it")
	if not bool(report["side_car_has_movie"]):
		print("  note       : sprite_stretch.json has no entry for this movie; the flag is unchecked")

	var diff: Dictionary = report["diff"]
	var total: int = int(diff["count"])
	if total == 0:
		print("  divergences: none")
	else:
		var first: Dictionary = diff["first"]
		var depth := "before the first frame"
		if not first.is_empty() and int(first["frame"]) >= 0:
			var frames: int = max(1, int(report["frames_read"]))
			depth = "at frame %d of %d, %.1f%% in" % [
				int(first["frame"]), frames, 100.0 * float(first["frame"]) / float(frames),
			]
		print("  divergences: %d, first %s" % [total, depth])
		print("  by field   :")
		var histogram: Dictionary = diff["histogram"]
		var fields := histogram.keys()
		fields.sort_custom(func(a, b): return int(histogram[a]) > int(histogram[b]))
		for field in fields:
			print("      %8d  %s" % [int(histogram[field]), field])
		print("  by pass    :")
		var passes: Dictionary = diff["passes"]
		for via in passes:
			print("      %8d  %s" % [int(passes[via]), via])
		print("  first %d in full:" % min(keep, diff["kept"].size()))
		for row in diff["kept"]:
			print("      %s" % _describe(row))

	print("  replay     : %d sampled frame(s) built both ways, %d differ" % [
		report["replay_checked"], report["replay_mismatch"],
	])
	print("  labels     : %s   markers: %s  (names compared case-insensitively)" % [
		"match" if bool(report["labels_ok"]) else "DIFFER",
		"match" if bool(report["markers_ok"]) else "DIFFER",
	])


func _check_report(h, report: Dictionary) -> void:
	if str(report["skip"]) != "":
		h.check("%s has a score and an export to compare" % report["movie"], false, report["skip"])
		return
	var diff: Dictionary = report["diff"]
	h.check("frame count matches the export",
		int(report["frames_read"]) == int(report["frames_export"]),
		"%d read, %d exported" % [report["frames_read"], report["frames_export"]])
	h.check("sprite records were actually compared", int(report["sprites"]) > 0,
		"%d" % report["sprites"])
	h.check("every sprite field matches the export", int(diff["count"]) == 0,
		"%d divergence(s)" % int(diff["count"]))
	h.check("labels match the export", bool(report["labels_ok"]))
	h.check("markers match the export", bool(report["markers_ok"]))
	h.check("the keyframe replay agrees with a linear replay",
		int(report["replay_mismatch"]) == 0,
		"%d of %d sampled frame(s) differ" % [report["replay_mismatch"], report["replay_checked"]])


func _describe(row: Dictionary) -> String:
	var where := "frame %d" % int(row["frame"]) if int(row["frame"]) >= 0 else "movie"
	if int(row["channel"]) >= 0:
		where += " ch %d" % int(row["channel"])
	return "%-18s %-22s expected %s, got %s   [%s]" % [
		where, row["field"], _show(row["want"]), _show(row["got"]), row["via"],
	]


# --- plumbing ----------------------------------------------------------------


func _new_diff(keep: int) -> Dictionary:
	return {"count": 0, "histogram": {}, "passes": {}, "first": {}, "kept": [], "keep": max(0, keep)}


func _note(diff: Dictionary, frame: int, channel: int, field: String, want, got, via: String) -> void:
	diff["count"] = int(diff["count"]) + 1
	diff["histogram"][field] = int(diff["histogram"].get(field, 0)) + 1
	diff["passes"][via] = int(diff["passes"].get(via, 0)) + 1
	var row := {
		"frame": frame, "channel": channel, "field": field,
		"want": want, "got": got, "via": via,
	}
	# "First" is the earliest frame, not the first noticed: the passes run in a
	# fixed order but the random one visits frames out of order, and the whole
	# point of the number is how far in the reader survives.
	var first: Dictionary = diff["first"]
	if first.is_empty() or frame < int(first["frame"]):
		diff["first"] = row
	if diff["kept"].size() < int(diff["keep"]):
		diff["kept"].append(row)


## Whether two materialisations of the same frame are the same frame.
func _frames_agree(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() == b.is_empty()
	for field in FRAME_FIELDS:
		if not _same(a.get(field, null), b.get(field, null)):
			return false
	var left: Array = a.get("sprites", [])
	var right: Array = b.get("sprites", [])
	if left.size() != right.size():
		return false
	for i in left.size():
		if int(left[i]["channel"]) != int(right[i]["channel"]):
			return false
		for field in SPRITE_FIELDS:
			if not _same(left[i].get(field, null), right[i].get(field, null)):
				return false
		if bool(left[i].get("stretch", false)) != bool(right[i].get("stretch", false)):
			return false
	return true


## JSON numbers arrive as floats and `null` is a real value, so neither `==` nor
## `int()` is safe on its own: `int(null)` is 0, which reads as a match.
static func _same(want, got) -> bool:
	if want == null or got == null:
		return want == null and got == null
	if typeof(want) == TYPE_BOOL or typeof(got) == TYPE_BOOL:
		return bool(want) == bool(got)
	if typeof(want) == TYPE_STRING or typeof(got) == TYPE_STRING:
		return str(want) == str(got)
	return absf(float(want) - float(got)) < 0.001


static func _show(value) -> String:
	return "null" if value == null else str(value)


func _first_frame(report: Dictionary) -> int:
	var first: Dictionary = report["diff"]["first"]
	# A clean movie sorts last, which is the reading order that matters.
	return int(first["frame"]) if not first.is_empty() else 0x7FFFFFFF


## `min(size, count)` frame indices spread over the movie, plus the edges, so a
## reader that is right in the middle and wrong at the ends is still caught.
func _sample(count: int, size: int) -> Dictionary:
	var out: Dictionary = {}
	if count <= 0:
		return out
	var wanted: int = min(count, max(1, size))
	for i in wanted:
		out[(i * count) / wanted] = true
	out[0] = true
	out[count - 1] = true
	return out


## The sample in a fixed shuffled order, so a seek never follows its own frame.
func _shuffled(sample: Dictionary) -> Array:
	var out: Array = sample.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = SAMPLE_SEED
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = out[i]
		out[i] = out[j]
		out[j] = swap
	return out


func _side_car() -> Dictionary:
	var text := FileAccess.get_file_as_string(STRETCH_SIDECAR)
	if text == "":
		print("note: %s is missing; the stretch flag has no oracle this run" % STRETCH_SIDECAR)
		return {}
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		print("note: %s is not an object" % STRETCH_SIDECAR)
		return {}
	return parsed.get("movies", {})


## The export directory for a container. The tree spells `strtgame` lower-case
## and every other movie upper-case, so the name is matched rather than assumed.
func _model_dir(container_path: String) -> String:
	var base := container_path.get_file().get_basename()
	for candidate in [base, base.to_upper(), base.to_lower()]:
		var dir := MODEL_ROOT.path_join(candidate)
		if FileAccess.file_exists(dir.path_join("frames.json")):
			return dir
	return ""


## `VWSC-338.bin` -> 338, or -1 when the export names no chunk.
func _chunk_id(name: String) -> int:
	var parts := name.get_basename().split("-")
	if parts.size() < 2 or not parts[1].is_valid_int():
		return -1
	return int(parts[1])


func _find(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, out)
	out.sort()
	return out


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
