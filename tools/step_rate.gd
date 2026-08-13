extends SceneTree
## Does the playhead take the number of score steps a second its own movie asks
## for?
##
##   godot --headless --audio-driver Dummy --path . --script tools/step_rate.gd -- --root piposh2
##   godot --headless --audio-driver Dummy --path . --script tools/step_rate.gd -- --root rating --limit 8
##   godot --headless --audio-driver Dummy --path . --script tools/step_rate.gd -- --root piposh --hz 30
##
## `tools/movie_tempo.gd` answers the other half of this question and only that
## half: it replays every score through a real `FrameClock` and asserts the
## **rate the clock settles on** is the one the movie's data names. It advances no
## time at all, deliberately, so a clock that resolved 8 fps perfectly and then
## stepped twice as often would pass it untouched -- which is exactly the bug
## `bugs.md` 86 was filed as and exactly the bug it turned out not to be. What is
## measured here is the *rate*: score steps divided by the seconds they took, off
## real awaited frames, against the rate the same clock says the movie asked for.
##
## **Why it must be real frames.** A synthetic `for i in N: tick(1.0/60)` loop
## measures the arithmetic in `FrameClock.tick` and nothing else -- it never
## advances the audio server, so every `soundBusy` guard holds for ever
## (AGENTS.md, and `bugs.md` 22 twice), and more to the point here it never pays
## for a decode, a dispatch or a paint. The whole of what this tool is for is what
## happens when a rendered tick costs more than a score step is worth, and a
## synthetic delta is the one thing that cannot express it.
##
## **`Engine.max_fps` is set on purpose.** Headless Godot renders uncapped, at
## several hundred frames a second on a warm movie, which is not a display any
## player has and is not the machine the ceiling below is about. `--hz` names the
## display being simulated and defaults to 60.
##
## **The ceiling, and why it is not a port limitation.** Director takes at most
## one score step per `Score::update` and calls that once per turn of the
## projector's main loop (`score.cpp:640-711` through `director.cpp:370-405`),
## re-arming `_nextFrameTime` to `now + 1000/rate` each time. So a movie whose
## tempo is above the loop's own rate simply does not reach it -- the excess is
## dropped, never banked -- and the same is true here with the rendered tick in
## place of the loop turn. `min(stated, hz)` is therefore the expectation and not
## a tolerance granted to the port. Itamar Park's arcade states 80 fps and cannot
## have it on a 60 Hz display, in Director or here.
##
## `_ticks` is the counter, and it is the right one: it is incremented once per
## step the clock granted whether or not the playhead was *held*, which is the
## movie's own clock rather than the playhead's (`frame_loop.gd:tick`). A room
## standing still on `go to the frame` is still being stepped at its tempo, and a
## measurement that counted frame changes instead would report every park in the
## corpus as a stopped clock.
##
## **A movie that takes no step at all is reported and not asserted**, and there
## is a real one: `piposh2`'s `PIP2DATA/SAVELOAD.dir`, opened through
## `lingo_go_movie` the way this tool and `liveness_sweep.gd` open every movie,
## parks with `_ticks` frozen and nothing holding, nothing paused and nothing
## stopped -- 0.0 to 1.5 steps/s against its stated 15. Every movie of
## `test-games/itamar-park` does the same, while booting the same container
## directly with `--file` plays it. That is a `go to movie` finding rather than a
## clock one -- it read the same before the clock was changed -- so the band below
## skips anything under `MIN_STEPS` rather than failing on it, and the row is
## still printed so the next reader sees the zero instead of a corpus that looks
## uniformly healthy.
##
## Title-agnostic: every rate compared against comes off the movie's own config
## chunk through the clock, and no movie is named here.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")

## Real seconds to watch each movie for. Long enough that a movie at 4 fps counts
## more than a handful of steps -- the rate of a 12-step sample is worth nothing
## -- and short enough that a corpus of sixteen movies is under a minute.
const WATCH_SECONDS := 2.0
## Frames to let a movie settle after `go to movie` before the stopwatch starts.
## The first frames of a movie pay for its artwork and its `startMovie`, which is
## real time the movie spends and is not the rate anything runs at afterwards.
const SETTLE_FRAMES := 45
## The display being simulated, unless `--hz` names another.
const DISPLAY_HZ := 60

## How far a measured rate may sit from the rate expected of it, as a fraction.
##
## Not a fudge for the arithmetic, which is exact: the clock re-arms to a fixed
## period and cannot drift. It is the boundary between the stopwatch and the
## steps. A 2-second watch at 8 fps is 16 steps, and the first and last of them
## land either side of the boundary depending on where in a period the watch
## started, so 15 or 17 is the honest range -- 6%. The band has to be wider than
## that and narrower than the thing it must catch, which is the 2x of a clock
## that banks time and the 4x-7x of one that does not.
const TOLERANCE := 0.20
## Under this many steps a rate is arithmetic on noise, so it is reported and not
## asserted. A movie that sat on a wait-for-click for the whole watch is the case:
## its clock ran, so `_ticks` moved, but a movie that opens straight into a
## `pause` moves it not at all.
const MIN_STEPS := 8


func _movies(paths, only: String, limit: int) -> Array[String]:
	var out: Array[String] = []
	for entry in paths.containers():
		if ContainerName.CAST.has(str(entry).get_extension().to_lower()):
			continue
		if only != "" and not str(entry).to_lower().contains(only):
			continue
		out.append(str(entry))
		if limit > 0 and out.size() >= limit:
			break
	return out


## Open one movie, let it settle, and time its steps.
##
## The clock is read *after* the watch rather than before it: a movie whose score
## writes a tempo does so on a frame, and the rate in force at the end of two
## seconds of play is the rate those two seconds were mostly paced at. Where the
## two differ the movie changed tempo mid-watch, which is reported as a spread
## rather than silently averaged -- see `rates`.
func _watch(preview: Node, movie: String, seconds: float) -> Dictionary:
	var host = preview.get("_host")
	if host != null:
		host.stopped = false
		host.playback_paused = false
	preview.set_process(true)
	var windows: Dictionary = preview.get("_windows")
	if windows != null:
		for key in windows.keys():
			preview.call("lingo_forget_window", str(key), true)
	preview.call("lingo_go_movie", movie, null)
	for _i in SETTLE_FRAMES:
		await process_frame
	if preview.get("_score") == null:
		return {"opened": false}

	var clock = preview.get("_clock")
	var rates: Dictionary = {}
	var holds: Dictionary = {}
	var started := Time.get_ticks_usec()
	var first := int(preview.get("_ticks"))
	var frames := 0
	while (Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		await process_frame
		frames += 1
		rates[float(clock.fps)] = int(rates.get(float(clock.fps), 0)) + 1
		# Everything that legitimately stops the playhead, sampled per rendered
		# frame rather than read once at the end. A movie that `pause`s for the
		# first second and resumes for the second reads as unpaused afterwards and
		# as a clock running at half its tempo, which is the wrong finding and the
		# one this column exists to prevent.
		var why := str(clock.call("hold_reason"))
		if why != "":
			holds[why] = int(holds.get(why, 0)) + 1
		if host != null and bool(host.playback_paused):
			holds["paused"] = int(holds.get("paused", 0)) + 1
		if host != null and bool(host.stopped):
			holds["stopped"] = int(holds.get("stopped", 0)) + 1
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	var steps := int(preview.get("_ticks")) - first
	# The rate the *majority* of the watch ran at, not the last one seen. A movie
	# that spends 90% of two seconds at 8 fps and its last frame at 30 asked for 8.
	var dominant := float(clock.fps)
	var best := 0
	for rate in rates:
		if int(rates[rate]) > best:
			best = int(rates[rate])
			dominant = float(rate)
	return {
		"opened": true,
		"movie": preview.call("movie_name"),
		"steps": steps,
		"seconds": elapsed,
		"frames": frames,
		"stated": float(clock.movie_default_fps),
		"asked": dominant,
		"rates": rates.keys(),
		"holds": holds,
		# Both of the two states in which a movie legitimately takes no step at
		# all, reported rather than silently producing a rate of zero. A movie that
		# `halt`ed and a movie that `pause`d look identical from the tick counter,
		# and neither is a clock that failed to run.
		"paused": host != null and bool(host.playback_paused),
		"stopped": host != null and bool(host.stopped),
		"frame": int(preview.get("_index")),
	}


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths = Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var hz := Args.number(args, "hz", DISPLAY_HZ)
	if hz > 0:
		Engine.max_fps = hz
	var seconds := float(Args.number(args, "seconds", int(WATCH_SECONDS)))
	if seconds <= 0.0:
		seconds = WATCH_SECONDS
	var movies := _movies(paths, Args.text(args, "only", "").to_lower(),
		Args.number(args, "limit", 0))

	var case := "%s: the playhead steps at the rate its movie asks for" % paths.root.get_file()
	h.begin(case)
	if not h.check("the corpus holds movies to time", not movies.is_empty(),
			"%d movie(s)" % movies.size()):
		h.complete(case)
		quit(h.finish("score steps per second against each movie's own tempo"))
		return

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	# `_ticks` is this file's unit and it is not on `tools/preview_surface.gd`'s
	# asserted list, so a rename makes `get()` answer null, `int(null)` answer 0,
	# every rate read 0.0/s and the whole table report a stopped engine. The same
	# guard `liveness_sweep.gd` carries, for the same field and the same reason.
	if not h.check("the movie's own tick counter is readable",
			preview.get("_ticks") != null):
		h.complete(case)
		quit(h.finish("score steps per second against each movie's own tempo"))
		return

	print("")
	print("root    : %s" % paths.root)
	print("display : %d Hz (Engine.max_fps), %.1f s per movie" % [hz, seconds])
	print("")
	print("%-22s %7s %7s %7s %8s %8s %6s  %s" % [
		"movie", "stated", "asked", "ceiling", "steps/s", "ticks/s", "ratio", "held"])

	var rows: Array[Dictionary] = []
	var wrong: Array[String] = []
	var judged := 0
	for movie in movies:
		var seen: Dictionary = await _watch(preview, movie, seconds)
		if not bool(seen.get("opened", false)):
			print("%-22s   (no score loaded)" % movie.get_file())
			continue
		var stated := float(seen["stated"])
		var asked := float(seen["asked"])
		var ceiling := minf(asked, float(hz)) if hz > 0 else asked
		var rate := float(seen["steps"]) / maxf(float(seen["seconds"]), 0.001)
		var ticks := float(seen["frames"]) / maxf(float(seen["seconds"]), 0.001)
		var ratio := rate / maxf(ceiling, 0.001)
		var held := ""
		for why in (seen["holds"] as Dictionary):
			held += "%s %d " % [str(why), int((seen["holds"] as Dictionary)[why])]
		held += "f%d" % int(seen["frame"])
		print("%-22s %7.0f %7.0f %7.0f %8.1f %8.1f %6.2f  %s" % [
			str(seen["movie"]).get_file(), stated, asked, ceiling, rate, ticks,
			ratio, held.strip_edges()])
		rows.append(seen)
		if int(seen["steps"]) < MIN_STEPS:
			continue
		judged += 1
		if absf(ratio - 1.0) > TOLERANCE:
			wrong.append("%s asks %.0f fps on a %d Hz display, steps %.1f/s (%.2fx)"
				% [str(seen["movie"]).get_file(), asked, hz, rate, ratio])

	print("")
	h.check("a movie was opened and timed", not rows.is_empty(),
		"%d of %d" % [rows.size(), movies.size()])
	# The one assertion, and the reason the ceiling is in the table beside the
	# stated rate: a movie may not run faster than its own tempo *or* than the
	# display, and both halves are one claim because the clock re-arms absolutely.
	# A clock that banked the time it lost fails this in both directions at once
	# -- fast on a warm movie whose tempo is above the display, slow on a cold one
	# -- which is why one band catches both.
	h.check("every timed movie stepped at min(its own tempo, the display) +-%d%%"
			% int(TOLERANCE * 100.0),
		wrong.is_empty(), "; ".join(wrong.slice(0, 4)))
	h.check("enough movies stepped often enough to be judged", judged > 0,
		"%d of %d timed" % [judged, rows.size()])
	h.complete(case)
	quit(h.finish("score steps per second against each movie's own tempo"))
