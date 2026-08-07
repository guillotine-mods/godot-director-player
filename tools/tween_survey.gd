extends SceneTree
## What a tweened sprite span actually contains.
##
##   godot --headless --script tools/tween_survey.gd -- --all
##   godot --headless --script tools/tween_survey.gd -- --file PIPDATA/OPENING.dir
##   godot --headless --script tools/tween_survey.gd -- --all --worst 20
##
## The question. Bit 0x80 of the thickness byte marks a sprite as tweened, and
## nothing in this port consumes it. Whether anything *should* depends on one
## fact nobody had measured: does Director's score store a value for every frame
## of a tweened span — in which case the tween is already baked into the data and
## a player that replays the records verbatim is correct — or does it store only
## the keyframes and expect the player to interpolate?
##
## The two are distinguishable without a running Director. If tweens are baked,
## the frames inside a span carry a value change almost every frame. If they are
## keyframes, a span holds a handful of writes with long stretches of nothing
## between them, and a player that does not interpolate shows a step where
## Director showed a slide.
##
## Spans are grouped by the sprite-list index in the record, not guessed at from
## where the member changes. That index names an entry of the same `VWSC` whose
## first two fields are the span's first and last frame — so the grouping is the
## file's own, and a span that changes member halfway through stays one span.
##
## What it prints, per corpus and per movie: how many spans carry the tweened bit
## at all, how many of their frames change position or size, and the longest runs
## of frames inside a tweened span during which nothing was written. That last
## number is the one that matters: it is how long a sprite would sit at a stale
## value before snapping, if interpolation is what is missing.
##
## Title-agnostic: it names no movie, channel or member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")

## Span counters. Members rather than locals because `_close` is called from
## three sites and GDScript has no out-parameter for an int.
var _spans := 0
var _tweened_spans := 0
var _tweened_frames := 0
var _tweened_changes := 0
## Longest run of unchanged frames inside a tweened span, bucketed by power of
## two: the exact number is noise, the order of magnitude is the answer.
var _holds: Dictionary = {}
var _worst: Array[Dictionary] = []


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
	var tweened_records := 0

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
		movies += 1
		var movie := path.get_file()

		# channel -> {idx, tweened, frames, changes, longest_hold, hold, last}
		var open_spans: Dictionary = {}
		for i in score.frame_count:
			var present: Dictionary = {}
			for sprite_value in score.frame(i).get("sprites", []):
				var sprite: Dictionary = sprite_value
				records += 1
				var channel := int(sprite["channel"])
				present[channel] = true
				if bool(sprite["tweened"]):
					tweened_records += 1
				var idx := int(sprite["sprite_list_idx"])
				var span: Dictionary = open_spans.get(channel, {})
				if span.is_empty() or int(span["idx"]) != idx:
					if not span.is_empty():
						_close(span)
					span = {
						"movie": movie, "channel": channel, "idx": idx,
						"start": i, "frames": 0, "changes": 0,
						"tweened": false, "hold": 0, "longest_hold": 0,
						"last": "",
					}
					open_spans[channel] = span
				var shape := "%d,%d,%d,%d,%d" % [
					int(sprite["loc_h"]), int(sprite["loc_v"]),
					int(sprite["width"]), int(sprite["height"]),
					int(sprite["cast_id"]),
				]
				span["frames"] = int(span["frames"]) + 1
				if bool(sprite["tweened"]):
					span["tweened"] = true
				if str(span["last"]) != "" and shape != str(span["last"]):
					span["changes"] = int(span["changes"]) + 1
					span["longest_hold"] = maxi(int(span["longest_hold"]),
						int(span["hold"]))
					span["hold"] = 0
				else:
					span["hold"] = int(span["hold"]) + 1
				span["last"] = shape
				span["end"] = i
			for channel in open_spans.keys():
				if present.has(channel):
					continue
				_close(open_spans[channel])
				open_spans.erase(channel)
		for channel in open_spans.keys():
			_close(open_spans[channel])
		f.close()

	print("%d movie(s), %d sprite records, %d carry the tweened bit (%.1f%%)" % [
		movies, records, tweened_records,
		100.0 * tweened_records / maxi(records, 1),
	])
	print("%d sprite spans, %d of them tweened" % [_spans, _tweened_spans])
	print("")
	print("inside a tweened span: %d frames, %d of which change loc/size/member"
		% [_tweened_frames, _tweened_changes]
		+ " (%.1f%%)" % (100.0 * _tweened_changes / maxi(_tweened_frames, 1)))
	print("")
	print("longest run of unchanged frames inside a tweened span:")
	var keys: Array = _holds.keys()
	keys.sort()
	for k in keys:
		print("  %4d frame(s) held  %6d span(s)" % [int(k), int(_holds[k])])
	if not _worst.is_empty():
		_worst.sort_custom(func(a, b): return int(a["hold"]) > int(b["hold"]))
		print("")
		print("tweened spans that hold one value longest:")
		for row in _worst.slice(0, worst_limit):
			print("  %-16s ch%-4d frames %d-%d  %d change(s)  holds %d frame(s)" % [
				str(row["movie"]), int(row["channel"]), int(row["start"]),
				int(row["end"]), int(row["changes"]), int(row["hold"]),
			])

	var h := Harness.new()
	h.begin("the survey ran")
	h.check("read at least one score", movies > 0, "%d movies" % movies)
	h.check("grouped records into spans", _spans > 0, "%d spans" % _spans)
	h.complete("the survey ran")
	quit(h.finish("what a tweened span contains"))


## Score one finished span into the survey's counters.
func _close(span: Dictionary) -> void:
	_spans += 1
	var longest: int = maxi(int(span["longest_hold"]), int(span["hold"]))
	if not bool(span["tweened"]):
		return
	_tweened_spans += 1
	_tweened_frames += int(span["frames"])
	_tweened_changes += int(span["changes"])
	var bucket := 1
	while bucket * 2 <= longest:
		bucket *= 2
	_holds[bucket] = int(_holds.get(bucket, 0)) + 1
	_worst.append({
		"movie": span["movie"], "channel": span["channel"],
		"start": span["start"], "end": span.get("end", span["start"]),
		"changes": span["changes"], "hold": longest,
	})
