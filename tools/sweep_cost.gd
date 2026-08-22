extends SceneTree
## Where does `liveness_sweep`'s wall clock go? Measured, not guessed.
##
##   godot --headless --audio-driver Dummy --path . --script tools/sweep_cost.gd -- \
##       --root piposh-dream --limit 12 --cap-ms 20000
##   godot --headless --audio-driver Dummy --path . --script tools/sweep_cost.gd -- \
##       --root piposh-dream --limit 4 --ff 120 --speech 8
##
## `bugs.md` 128's open half is that `WATCH_CAP_MS` now binds, so two thirds of
## `piposh-dream` never runs `--window` judgeable ticks together. Before raising
## the ceiling (which multiplies a corpus cost already at 2.5x) this asks what the
## ceiling is actually being spent on, split four ways:
##
##   engine   wall time inside `await process_frame` -- the preview's `_process`,
##            the paint, the decode, the servers
##   sample   wall time in the sampler's own per-tick questions
##   held     score ticks the sweep watched and could not charge (a hold)
##   idle     process frames that produced no score tick at all
##
## The last one is the one no existing number can express: `coverage` counts
## sampled ticks over ticks run and `depth` counts unexcused ticks, and neither
## says how many *frames* the harness burned to get them.
##
## Prints one row per movie plus a corpus total. **Not pass/fail**, and nothing in
## `gate.sh` runs it: it is a survey, so it prints numbers that are not
## higher-is-better and it is on whoever runs it to say what they were measured on
## (`porting-fidelity-verification`). It sits in `tools/` rather than in
## `tools/scratch/`, which is gitignored, because the question it answers is the
## one `bugs.md` 128 will be asked again -- *what is the sweep's wall clock going
## into now?* -- and a method that has to be rewritten each time gets answered
## from memory instead.
##
## **One trap this file fell into on its first run, kept because it is the shape
## `scenes/preview/README.md` warns about**: `_start_lingo` builds a **new**
## `_host` per movie, so a `reached["soundbusy"]` counter read off the host
## fetched *before* `lingo_go_movie` never moves. That reported **zero** sound
## holds over twelve movies the sweep says are held on speech for 98% of their
## ticks -- a harness reading a dead object and calling the game clean. The host
## is fetched after the jump now.

const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")

const SOUND_CHANNELS := 8


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return
	var only := Args.text(args, "only", "").to_lower()
	var limit := Args.number(args, "limit", 0)
	var cap_ms := Args.number(args, "cap-ms", 20000)
	var settle := Args.number(args, "settle", 24)
	var ff := float(Args.number(args, "ff", 30))
	var paint := not Args.flag(args, "no-paint")
	# The one hold `--ff` cannot scale: the mixer runs on the audio server's clock,
	# so a four-second line of speech costs four seconds of ceiling however fast
	# the score is told to run. `AudioServer.playback_speed_scale` is the audio
	# server's own multiplier on every stream it mixes, so a poll of `soundBusy`
	# retires proportionally sooner and every cue point inside the sound passes
	# sooner in wall clock and at the same place in the sound.
	var speech := float(Args.number(args, "speech", 1))
	AudioServer.playback_speed_scale = maxf(speech, 0.01)

	var movies: Array[String] = []
	for entry in paths.containers():
		if ContainerName.CAST.has(str(entry).get_extension().to_lower()):
			continue
		if only != "" and not str(entry).to_lower().contains(only):
			continue
		movies.append(str(entry))
	if limit > 0:
		movies = movies.slice(0, limit) as Array[String]

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	preview.set("_fast_forward_fps", ff)

	print("")
	print("root   : %s" % paths.root)
	print("movies : %d, cap %d ms each, ff %.0f, speech x%.0f, paint %s" % [
		movies.size(), cap_ms, ff, speech, "on" if paint else "OFF"])
	print("")
	print("%-24s %6s %6s %6s %6s %7s %7s %7s %7s  %s" % [
		"movie", "open_s", "watch_s", "frames", "ticks", "judged",
		"held", "engine%", "proc%", "top hold"])

	var t_open := 0
	var t_watch := 0
	var t_frames := 0
	var t_ticks := 0
	var t_judged := 0
	var t_held := 0
	var t_engine := 0
	var t_skipped := 0
	var t_proc := 0.0
	var holds_all: Dictionary = {}

	for movie in movies:
		# Fetched *before* the jump only to clear the last movie's stop/pause. The
		# host that matters is the one `lingo_go_movie` installs, and reading
		# `reached` off the pre-jump object is why this file's first run reported
		# zero sound holds over twelve movies the sweep says are held on speech for
		# 98% of their ticks: `_start_lingo` builds a new host per movie, so the
		# counter being polled was a dead one that never moved.
		var host = preview.get("_host")
		if host != null:
			host.stopped = false
			host.playback_paused = false
		preview.set_process(true)
		var opening := Time.get_ticks_msec()
		preview.call("lingo_go_movie", movie, null)
		for _i in 8:
			await process_frame
		if preview.get("_score") == null:
			print("%-24s  no score" % movie.get_file())
			continue
		# settle
		var until := int(preview.get("_ticks")) + settle
		var s0 := Time.get_ticks_msec()
		while int(preview.get("_ticks")) < until and Time.get_ticks_msec() - s0 < 8000:
			await process_frame
		var open_ms := Time.get_ticks_msec() - opening

		host = preview.get("_host")
		var start := Time.get_ticks_msec()
		var began := int(preview.get("_ticks"))
		var last := began
		var frames := 0
		var skipped := 0
		var judged := 0
		var held := 0
		var engine_us := 0
		var sample_us := 0
		var proc_s := 0.0
		var holds: Dictionary = {}
		var polls := 0 if host == null \
			else int((host.reached as Dictionary).get("soundbusy", 0))
		while Time.get_ticks_msec() - start < cap_ms:
			var a0 := Time.get_ticks_usec()
			await process_frame
			engine_us += Time.get_ticks_usec() - a0
			proc_s += float(Performance.get_monitor(Performance.TIME_PROCESS))
			frames += 1
			var now := int(preview.get("_ticks"))
			if now == last:
				continue
			if now - last > 1:
				skipped += now - last - 1
			last = now
			var b0 := Time.get_ticks_usec()
			var asked := 0 if host == null \
				else int((host.reached as Dictionary).get("soundbusy", 0))
			var reason := _hold(preview, audio, host, asked - polls)
			polls = asked
			var drawn := 0
			for raw in preview.call("frame_sprites"):
				if not (preview.call("_effective", raw) as Dictionary).is_empty():
					drawn += 1
			sample_us += Time.get_ticks_usec() - b0
			if reason == "":
				judged += 1
			else:
				held += 1
				holds[reason] = int(holds.get(reason, 0)) + 1
				holds_all[reason] = int(holds_all.get(reason, 0)) + 1
		var watch_ms := Time.get_ticks_msec() - start
		var ticks := int(preview.get("_ticks")) - began
		var top := ""
		var best := 0
		for k in holds.keys():
			if int(holds[k]) > best:
				best = int(holds[k])
				top = "%s x%d" % [str(k), best]
		t_skipped += skipped
		print("%-24s %6.1f %6.1f %6d %6d %7d %7d %6.0f%% %6.0f%%  %s" % [
			movie.get_file(), open_ms / 1000.0, watch_ms / 1000.0, frames, ticks,
			judged, held,
			100.0 * float(engine_us) / maxf(1.0, float(watch_ms) * 1000.0),
			100.0 * proc_s * 1000.0 / maxf(1.0, float(watch_ms)),
			top])
		t_open += open_ms
		t_watch += watch_ms
		t_frames += frames
		t_ticks += ticks
		t_judged += judged
		t_held += held
		t_engine += engine_us
		t_proc += proc_s

	print("")
	print("totals : open %.1f s, watch %.1f s, %d frames, %d ticks, %d judged, %d held" % [
		t_open / 1000.0, t_watch / 1000.0, t_frames, t_ticks, t_judged, t_held])
	print("skipped: %d tick(s) never sampled (%.1f%% of ticks run)" % [
		t_skipped, 100.0 * t_skipped / maxf(1.0, float(t_ticks))])
	print("rates  : %.1f frame/s, %.2f tick/s, %.2f tick/frame, %.1f ms/frame" % [
		1000.0 * t_frames / maxf(1.0, float(t_watch)),
		1000.0 * t_ticks / maxf(1.0, float(t_watch)),
		float(t_ticks) / maxf(1.0, float(t_frames)),
		float(t_watch) / maxf(1.0, float(t_frames))])
	print("split  : engine %.0f%% of watch, _process %.0f%% of watch" % [
		100.0 * float(t_engine) / maxf(1.0, float(t_watch) * 1000.0),
		100.0 * t_proc * 1000.0 / maxf(1.0, float(t_watch))])
	var pairs: Array = []
	for k in holds_all.keys():
		pairs.append([str(k), int(holds_all[k])])
	pairs.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	print("holds  : %s" % ", ".join(pairs.map(func(p): return "%s %d" % [p[0], p[1]])))
	quit(0)


func _hold(preview: Node, audio: Node, host, polls: int) -> String:
	var clock = preview.get("_clock")
	var reason := "" if clock == null else str(clock.hold_reason())
	if host != null and bool(host.playback_paused):
		return "pause"
	if host != null and bool(host.stopped):
		return "halted"
	if reason != "":
		return reason
	if polls > 0 and audio != null:
		for channel in range(1, SOUND_CHANNELS + 1):
			if bool(audio.call("sound_busy", channel)):
				return "wait for sound"
	return ""
