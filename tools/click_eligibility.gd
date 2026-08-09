extends SceneTree
## Which channels answer a click, on every frame of every movie in a corpus.
##
##   godot --headless --script tools/click_eligibility.gd -- --root piposh2 --out before.txt
##   godot --headless --script tools/click_eligibility.gd -- --root rating  --out after.txt
##   diff before.txt after.txt
##
## `tools/hotspots.gd` answers the same question for one frame and prints why.
## This one answers it for a whole title and prints nothing but the answer,
## because its purpose is to be **run twice and diffed**.
##
## Eligibility (§4.3) is the filter inside the click descent, so widening it does
## not just make more sprites clickable -- it makes them **absorb** clicks that
## used to fall through to whatever is behind them (§4.2). A change here cannot be
## judged by whether the thing you were testing now works: the cost is somewhere
## else on the stage, on a frame nobody opened. So the deliverable of any such
## change is this file's output before it and after it, compared row by row.
##
## Two sections, and the second exists because a row-by-row diff of the first is
## unreadable at the scale a widening produces:
##
##   `frame` rows -- one per frame, the eligible channels in order. This is the
##   diff that matters; a changed row is a frame whose click routing moved.
##   `sprite` rows -- one per distinct (channel, member, size) that is eligible
##   anywhere in the movie, with the frame span it covers. This is what you read
##   by hand afterwards, because it is where a 640x400 backdrop that has just
##   become a click target is visible as a 640x400 backdrop.
##
## **A cold score read, not a playthrough.** The movie is loaded and its casts
## compiled, and then nothing runs: no `startMouse`, no frame script, no puppet
## state. So `moveable` is the score's authored bit and not one a Lingo write
## added. That understates eligibility a little, identically in both runs, which
## is what a differential measurement needs -- a playthrough would visit a
## different set of frames each time it was run and the diff would be noise.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const Boot := preload("res://scenes/preview/boot.gd")


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


## The behaviour attachments for one channel, indexed for the sweep.
##
## `Scripts.for_sprite` walks every interval in the score for every question,
## which is the right shape for one click and the wrong shape for 800,000 of
## them. This is the same data grouped by channel once per movie, and it is used
## only to build the memo key -- the verdict itself still comes from the preview,
## so the harness cannot answer differently from the player.
func _intervals_by_channel(score) -> Dictionary:
	var out: Dictionary = {}
	for interval in score.intervals():
		if str(interval["kind"]) != "sprite":
			continue
		var channel := int(interval["channel"])
		if not out.has(channel):
			out[channel] = []
		(out[channel] as Array).append(interval)
	return out


func _interval_key(by_channel: Dictionary, channel: int, frame: int) -> String:
	for value in by_channel.get(channel, []):
		var interval: Dictionary = value
		if frame < int(interval["start"]) or frame > int(interval["end"]):
			continue
		return "%d:%d" % [int(interval["script_cast_lib"]), int(interval["script_member"])]
	return "-"


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var targets: Array[String] = []
	var one := Args.text(args, "file", "")
	if one != "":
		var resolved: String = paths.resolve(one)
		if resolved == "":
			print("no such container: %s" % one)
			quit(1)
			return
		targets.append(resolved)
	else:
		_walk(paths.root, targets)
		targets.sort()

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	preview.set_process(false)
	preview.set_process_input(false)
	preview._paths = paths

	var lines := PackedStringArray()
	var movies := 0
	var frames := 0
	var records := 0
	var eligible_records := 0
	var eligible_frames := 0
	var intervals_resolved := 0
	var intervals_unresolved := 0
	var unresolved_kinds: Dictionary = {}
	var started := Time.get_ticks_msec()

	for path in targets:
		if not preview._load_container(path):
			continue
		var score = preview.get("_score")
		if score == null or int(score.frame_count) <= 0:
			continue
		preview._lib_keys.clear()
		Boot.start_lingo(preview, path)
		var name := path.get_file()
		movies += 1
		# The behaviour attachments, and whether they are behaviours at all.
		#
		# §4.3's D6+ clause is a test on the attachment list, so the list's
		# quality *is* the clause's accuracy, and this port's list is not clean:
		# some attachments name a bitmap or a film loop, neither of which can be
		# a behaviour. The giveaway is the member type, and that is what this
		# counts. `interaction.gd:behaviour_scripts` requires the lookup to
		# succeed because of these, and cites these numbers.
		#
		# This used to say the pairing handed a span somebody else's behaviour
		# entry. It does not -- `director_score.gd:parse` carries the three
		# measurements that killed that -- so the count below is a count of
		# attachments Director's own data made, and the open question is what
		# they mean rather than where they came from.
		for interval in score.intervals():
			if str(interval["kind"]) != "sprite":
				continue
			var lib := int(interval["script_cast_lib"])
			var script: Dictionary = preview.call("_script_in_lib",
				lib, int(interval["script_member"]))
			if not script.is_empty():
				intervals_resolved += 1
				continue
			intervals_unresolved += 1
			var named: Dictionary = preview._table.get_member(
				1 if lib <= 0 or lib == 0xFFFF else lib, int(interval["script_member"]))
			var kind := str(named.get("type_name", "<no member>"))
			unresolved_kinds[kind] = int(unresolved_kinds.get(kind, 0)) + 1
		var by_channel := _intervals_by_channel(score)
		# channel -> what the verdict was, keyed by everything the verdict reads.
		var memo: Dictionary = {}
		# "ch|lib:id|WxH" -> [first frame, last frame] over the eligible frames.
		var spans: Dictionary = {}
		for index in int(score.frame_count):
			preview._index = index
			frames += 1
			var hits := PackedStringArray()
			for value in score.frame(index).get("sprites", []):
				var sprite: Dictionary = value
				records += 1
				var channel := int(sprite["channel"])
				var lib := int(sprite["cast_lib"])
				var member := int(sprite["cast_id"])
				var key := "%d|%d:%d|%d|%s" % [
					channel, lib, member, int(bool(sprite.get("moveable", false))),
					_interval_key(by_channel, channel, index),
				]
				var verdict: bool
				if memo.has(key):
					verdict = bool(memo[key])
				else:
					verdict = bool(preview.call("_responds_to_mouse", sprite))
					memo[key] = verdict
				if not verdict:
					continue
				eligible_records += 1
				hits.append(str(channel))
				var span_key := "%3d %d:%-5d %4dx%-4d" % [
					channel, lib, member,
					int(sprite["width"]), int(sprite["height"]),
				]
				if spans.has(span_key):
					(spans[span_key] as Array)[1] = index
					(spans[span_key] as Array)[2] = int((spans[span_key] as Array)[2]) + 1
				else:
					spans[span_key] = [index, index, 1]
			if hits.size() > 0:
				eligible_frames += 1
			lines.append("frame  %-16s %5d  %s" % [name, index, " ".join(hits)])
		var span_keys: Array = spans.keys()
		span_keys.sort()
		for span_key in span_keys:
			var span: Array = spans[span_key]
			lines.append("sprite %-16s %s  frames %d-%d (%d)" % [
				name, str(span_key), int(span[0]), int(span[1]), int(span[2])])
		preview._table.close()
		preview._movie.close()

	var out_path := Args.text(args, "out", "")
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			print("cannot write %s" % out_path)
			quit(1)
			return
		for line in lines:
			f.store_line(line)
		f.close()

	print("")
	print("corpus %s" % paths.root)
	print("  %d movies, %d frames, %d sprite records in %.1f s" % [
		movies, frames, records, (Time.get_ticks_msec() - started) / 1000.0])
	print("  %d sprite records answer a click (%.2f%%)" % [
		eligible_records, 100.0 * float(eligible_records) / maxf(records, 1)])
	print("  %d of %d frames have at least one (%.2f%%)" % [
		eligible_frames, frames, 100.0 * float(eligible_frames) / maxf(frames, 1)])
	print("  sprite intervals: %d resolve to a script, %d do not %s" % [
		intervals_resolved, intervals_unresolved,
		"(by the member type the score names: %s)" % str(unresolved_kinds)
			if intervals_unresolved > 0 else ""])
	if out_path != "":
		print("  %d rows -> %s" % [lines.size(), out_path])

	# Not "some sprite must be eligible": that is not a property of Director and
	# it is false of real frames (`tools/hotspots.gd` says why). What is worth
	# asserting is that the sweep actually read the corpus, because a harness
	# that reaches into the preview by name reports zero rather than failing when
	# a field moves out from under it.
	var h := Harness.new()
	h.begin("the sweep read the corpus")
	h.check("at least one movie loaded", movies > 0, "%d movies" % movies)
	h.check("at least one frame walked", frames > 0, "%d frames" % frames)
	h.check("at least one sprite record classified", records > 0, "%d records" % records)
	h.complete("the sweep read the corpus")
	quit(h.finish("click eligibility across the corpus"))
