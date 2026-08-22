extends SceneTree
## Where a looping room's playhead goes back to, against what its score says.
##
##   godot --headless --audio-driver Dummy --path . --script tools/frame_reentry.gd -- \
##     --root piposh --file PIPDATA/CANON.dir --label game6
##   ... --score-only --from 344 --to 392
##
##   --file C        container (default: the configured boot movie)
##   --label L       the marker whose span to drive and watch
##   --from/--to N   the 1-based frame range to print the score of
##   --ticks N       awaited frames to watch after arriving (default 1400)
##   --loop-to N     the 1-based frame the loop must go back to. Without it the
##                   two arms below both derive their branch from the measured
##                   target, so a loop that moved by one frame passes on the other
##                   arm -- see the comment beside the check
##   --score-only    print the score's own answer and drive nothing
##
## ## Why this exists: `bugs.md` 45
##
## That entry ends on one question -- *"the round's entry frame re-runs and resets
## `allshipscounter` before the hit's 20 counts down; is that re-entry faithful?"*
## -- and it is a question about the engine that only the score and the playhead
## together can answer. A port that loops to the wrong frame and a movie that
## loops to that frame on purpose leave the same trace, so a trace alone proves
## nothing and the score alone cannot say what the port did with it.
##
## **The reference's rule, and it is not the one the entry expected.**
## `Score::update` sends `exitFrame`, `prepareFrame`, `enterFrame` and the sprite
## behaviours on **every** update cycle (`score.cpp:668-830`). The frame-change
## condition the entry names -- `if (_curFrameNumber != nextFrameNumberToLoad)` in
## `updateCurrentFrame` (`score.cpp:497-527`) -- gates `loadFrame` and the sprite
## reload and nothing else; the `else` arm right below it re-runs `updateSprites`
## for the same-frame case and no handler dispatch is inside either branch. So a
## held frame re-runs its `enterFrame` every tick in Director, and "did the frame
## number change" is a question about channel data, never about handlers.
##
## ## What that answers, measured on Piposh 1's cannon round, 2026-08-15
##
## `--score-only --from 344 --to 392`, in 1-based Lingo frame numbers:
##
##     348           game5's span ends, member 27  -- on exitFrame go(marker(0) + 1)
##     349  game6    member 640                    -- on enterFrame, the round's setup
##     350..384      member 641, one span          -- on exitFrame, the round itself
##     385           member 27                     -- on exitFrame go(marker(0) + 1)
##
## **The marker `game6` is frame 349, and it *is* the setup frame.** So
## `marker(0)` from frame 385 is 349 and `go(marker(0) + 1)` is `go(350)` -- the
## first frame of the round's own span, one past the setup. The loop is 350..385
## and it never touches 349 again. That is Director's ordinary idiom: the marker
## frame sets the room up once and the room loops to marker + 1.
##
## Driven, 1400 awaited frames: the playhead visits 349 **once**, then runs
## 350..385 seven times, and `lingo ran` reports `enterFrame: 1` against
## `exitFrame: 114`. Member 640 runs once per entry into the round and the loop
## re-runs nothing.
##
## **So `bugs.md` 45's premise is false and the entry does not close as
## unreachable.** Nothing resets `allshipscounter` between passes, the hit's
## countdown of 20 reaches 1 inside a single 35-frame pass, and the unpaired
## `-164` fires: `tools/cannon_sub_drift.gd --ticks 400` puts channel 10's top at
## **-102** and leaves it there for the rest of the round. The drift is real,
## reachable, and entirely the movie's own arithmetic -- member 641's surface
## branch subtracts whenever the counter reaches 1 and does not ask which of the
## two things wrote it. There is no engine defect behind it and nothing here to
## fix.
##
## Title-agnostic: it names no game, no handler and no global. Both halves are
## driven from the label on the command line, and every assertion is derived from
## the score in front of it.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")
const FrameLoop := preload("res://scenes/preview/frame_loop.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config(Paths.CONFIG_PATH, Args.text(args, "root", "")):
		print("no game configured")
		quit(1)
		return
	var file := Args.text(args, "file", paths.boot_movie)
	var path: String = paths.resolve(file)
	var f := ContainerFile.new()
	if not f.open(path):
		print("no such container: %s" % file)
		quit(1)
		return
	var vwsc: Array = f.ids_of("VWSC")
	if vwsc.is_empty():
		print("%s has no score: it is a cast, not a playable movie" % file)
		f.close()
		quit(1)
		return
	var score := Score.new()
	score.parse(f.read_chunk(int(vwsc[0])))
	var labels := Labels.new()
	var vwlb: Array = f.ids_of("VWLB")
	if not vwlb.is_empty():
		labels.parse(f.read_chunk(int(vwlb[0])))
	f.close()

	var label := Args.text(args, "label", "")
	# `Labels` keys its map by the **0-based index**, and every frame number in
	# this file's output is 1-based because that is the space a Lingo script's
	# `go` and `marker` work in. The two are one apart and the conversion is the
	# single easiest thing to get wrong here: read the marker as 348 rather than
	# 349 and `go(marker(0) + 1)` appears to return to the setup frame, which is
	# exactly the reading `bugs.md` 45 was written from.
	var marker_index := int(labels.labels.get(label.to_lower(), -1)) if label != "" else -1
	var marker_frame := marker_index + 1 if marker_index >= 0 else -1
	var from := Args.number(args, "from", maxi(1, marker_frame - 5) if marker_frame > 0 else 1)
	var to := Args.number(args, "to", marker_frame + 44 if marker_frame > 0 else 40)
	_print_score(score, labels, file, from, to)

	if Args.flag(args, "score-only"):
		quit(0)
		return
	if label == "":
		print("note: no --label given, so nothing is driven and nothing is asserted")
		quit(0)
		return
	if marker_frame < 0:
		print("no label %s in %s; have: %s" % [label, file, ", ".join(labels.labels.keys())])
		quit(1)
		return

	await _drive(h, args, file, label, marker_frame, score, labels)
	quit(h.finish("where a looping room's playhead goes, against what its score says"))


## The frame script and behaviour span of every frame in the range, 1-based.
##
## `main` is the score's own script slot on the frame record; `behaviour` is the
## interval entry covering it, which is where almost every frame script in this
## corpus actually lives (`preview/scripts.gd:for_frame`). Both are printed
## because a frame with one and not the other is normal, and which of the two a
## room's loop lives in is the first thing a reader here needs.
func _print_score(score, labels, file: String, from: int, to: int) -> void:
	print("frames %d..%d of %s (1-based)" % [from, to, file])
	for i in range(maxi(1, from), mini(to, score.frame_count) + 1):
		var index := i - 1
		var frame: Dictionary = score.frame(index)
		var spans: Dictionary = FrameLoop.sprite_behaviours_at(score, index)
		var behaviour := ""
		if spans.has(0):
			var spec: Array = spans[0]
			behaviour = "[%d..%d] member %d" % [int(spec[0]) + 1, int(spec[1]) + 1, int(spec[3])]
		print("  %4d %-14s main %-6s behaviour %s" % [
			i, labels.marker_at(index), str(frame.get("frame_script")), behaviour])


## Drive the real player into the label and record every frame the playhead
## stands on, in order.
##
## Sampled off real awaited frames rather than off a synthetic tick loop, for the
## reason `AGENTS.md` gives: rooms in this corpus poll `soundBusy`, and a loop
## that advances the runtime's clock and not the audio server's holds for ever.
func _drive(h: Harness, args: Dictionary, file: String, label: String,
		marker_frame: int, score, labels) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", file, null)
	for _i in 12:
		await process_frame
	preview.call("lingo_go_label", label)

	# **Watching stops when the room is left, and that is not tidiness.** A round
	# that ends -- Piposh 1's cannon round loses on its ninth hit and `go`es to
	# `looseship` -- goes on looping somewhere else, and those passes have a
	# different `go` in a different script. Folded into one trace they read as one
	# loop with three destinations, which is precisely the symptom this harness
	# exists to detect and would then report on every run. The span is the label's
	# own: from its marker to the frame before the next one.
	var span_end: int = score.frame_count
	for marker in labels.markers:
		var at := int((marker as Dictionary)["frame"]) + 1
		if at > marker_frame and at - 1 < span_end:
			span_end = at - 1
	print("")
	print("watching frames %d..%d, the label's own span" % [marker_frame, span_end])

	var ticks := Args.number(args, "ticks", 1400)
	var visits: Dictionary = {}
	var entries: Dictionary = {}
	var back_jumps: Dictionary = {}
	var order: Array[int] = []
	var last := -1
	var left := false
	for _t in ticks:
		await process_frame
		var index := int(preview.get("_index"))
		if index + 1 < marker_frame or index + 1 > span_end:
			left = true
			break
		visits[index] = int(visits.get(index, 0)) + 1
		if index != last:
			# **Entries, not samples.** A frame the playhead sits on for eleven
			# awaited frames has one entry and eleven samples, and only the entry
			# count answers "did this frame's `enterFrame` run again".
			entries[index] = int(entries.get(index, 0)) + 1
			if last >= 0 and index < last:
				back_jumps[index] = int(back_jumps.get(index, 0)) + 1
			order.append(index + 1)
			last = index
	print("")
	print("frames the playhead stood on, in order (1-based):")
	print("  %s" % str(order.slice(0, 120)))
	if order.size() > 120:
		print("  ... and %d more" % (order.size() - 120))
	print("entries per frame (1-based, samples in brackets):")
	var seen: Array = visits.keys()
	seen.sort()
	for index in seen:
		print("  frame %4d  x %d  [%d]" % [
			int(index) + 1, int(entries.get(index, 0)), int(visits[index])])

	var case := "%s @%s: where the loop goes back to" % [file, label]
	h.begin(case)
	if not h.check("the playhead reached the label's frame or later",
			not order.is_empty() and order[0] >= marker_frame,
			"first frame %s, marker at %d" % [
				str(order[0]) if not order.is_empty() else "none", marker_frame]):
		h.complete(case)
		return
	var targets: Array = back_jumps.keys()
	targets.sort()
	var shown: Array[String] = []
	for index in targets:
		shown.append("%d x%d" % [int(index) + 1, int(back_jumps[index])])
	print("")
	print("back-jump targets: %s" % ("none" if shown.is_empty() else ", ".join(shown)))
	if not h.check("the room loops rather than running off the end of its span",
			not targets.is_empty(), "%d back-jump(s) in %d tick(s), left the span: %s" % [
				targets.size(), ticks, str(left)]):
		h.complete(case)
		return
	# **One loop has one destination.** A room whose `go` resolves differently on
	# different passes is the shape `bugs.md` 45 suspected, and it is visible here
	# without knowing anything about the movie: the same statement on the same
	# frame must send the playhead to the same place every time.
	h.check("every pass of the loop goes back to the same frame", targets.size() == 1,
		"targets %s" % str(shown))
	var loop_target: int = int(targets[0]) + 1
	# **`--loop-to N` pins the frame, and without it nothing here does.** The two
	# arms below both read `loop_target` and then assert against the marker frame,
	# so a loop that moved by one frame would swap which arm runs and pass on the
	# other one -- and a one-frame move is the whole of what `marker(0)` and `go`
	# can get wrong. `docs/bugs-closed.md` 134 is the report that shape produces:
	# an ambient `if not soundBusy(2) then sound playFile 2, X` on `marker + 1`
	# repeats or does not repeat entirely according to whether the loop returns to
	# `marker + 1` or `marker + 2`, and the player hears a room that has music or
	# a room that goes silent after one play. The number is the caller's, like
	# `--label`, so nothing about a game is written down here.
	var expected := int(Args.number(args, "loop-to", 0))
	if expected > 0:
		h.check("the loop returns to the frame it is expected to",
			loop_target == expected, "returns to %d, expected %d" % [loop_target, expected])
	# The entry's actual question, and the assertion its premise fails: a frame
	# the loop does not return to is entered once, however many passes there are.
	# Derived from the trace rather than written down -- the marker frame is
	# whichever the label names, and whether the loop returns to it is what the
	# score decides.
	if loop_target == marker_frame:
		print("note: this room's loop returns to its own marker frame, so its setup does re-run")
		h.check("and it re-runs on every pass",
			int(entries.get(marker_frame - 1, 0)) >= int(back_jumps[targets[0]]),
			"marker frame %d entered %d time(s), %d back-jump(s)" % [
				marker_frame, int(entries.get(marker_frame - 1, 0)),
				int(back_jumps[targets[0]])])
	else:
		h.check("a frame before the loop's target is entered once and not per pass",
			int(entries.get(marker_frame - 1, 0)) <= 1,
			"marker frame %d entered %d time(s) over %d pass(es), loop returns to %d" % [
				marker_frame, int(entries.get(marker_frame - 1, 0)),
				int(back_jumps[targets[0]]), loop_target])
	h.complete(case)
