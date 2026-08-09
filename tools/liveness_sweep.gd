extends SceneTree
## Open every movie a title ships and ask whether a player could get out of it.
##
##   godot --headless --path . --script tools/liveness_sweep.gd
##   godot --headless --path . --script tools/liveness_sweep.gd -- --root piposh-dream
##   godot --headless --path . --script tools/liveness_sweep.gd -- --limit 12
##   godot --headless --path . --script tools/liveness_sweep.gd -- --only ques.dir --click
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --only S      visit only containers whose path contains S
##   --limit N     visit at most N containers, in sorted order (0 = all)
##   --budget-ms N stop starting new containers after N ms of wall clock (0 = none)
##   --ticks N     score ticks to watch each container for (default 120)
##   --window N    score ticks a verdict is read over (default 60)
##   --settle N    score ticks to let a container open in (default 24)
##   --click       after the watch, click each eligible sprite and watch again
##   --clicks N    how many hotspots to try per container (default 3)
##   --ff N        ceiling for the adaptive fast-forward rate (default 30)
##   --strict      make the low-confidence `trap` verdict a failure too
##   --verbose     print a line for every container, not only the findings
##
## ## Why this exists
##
## `gate.sh` tests mechanisms one at a time. Nothing walks the corpus asking the
## player's question -- *am I stuck?* -- and the bug that prompted this file is
## the proof: opening the save screen in `piposh-dream` made the playhead
## ping-pong for ever between `ques.dir` frame 803 (the panel, 4 sprites) and
## `Saves.dir` frame 27 (0 sprites, a black stage), because a `play done` return
## re-ran the caller's `exitFrame`, which contained the `play` that had parked it.
## The screen alternated with black for as long as it was open and was never
## clickable.
##
## Nothing in the gate could have caught that. `movie_churn` counts movie changes
## but only on the boot movie, driving `_advance` synthetically. `playhead_escape`
## watches a reachable set but only after one scripted click in one room of one
## title, and it reads `_index` alone -- a number that means nothing across a
## movie boundary. `skip_state` asserts the movie can still move, and a ping-pong
## moves every single step. **No harness had ever looked at a second container of
## a second title at all.**
##
## ## The hard part is not finding stuck movies, it is not crying wolf
##
## `go to the frame` is how every room in every one of these titles stands still.
## A room waiting for a click is a playhead that never moves, on a frame whose
## `exitFrame` jumps to itself, with nothing on the clock -- which is, read
## naively, indistinguishable from a hang. A detector that reports those reports
## 300 rooms and is worth less than nothing.
##
## Four things are treated as an *answer* to "why is the playhead not moving",
## and a tick that has any of them clears the window rather than annotating it,
## so a trap has to be `--window` **consecutive** unexplained score ticks:
##
##   * `FrameClock.hold_reason()` is non-empty -- a tempo delay, a transition, a
##     palette effect, the tempo channel's wait-for-click or wait-for-sound;
##   * the movie is **polling `soundBusy`** and a sound is in fact playing --
##     Director's wait-for-speech idiom, and the one `playhead_escape` names;
##   * Director's `pause` is in effect (`preview_lingo_host.playback_paused`), the
##     one hold that names no destination and stops the playhead outright;
##   * the movie called `quit`/`halt` (`stopped`), which is an ending, not a hang.
##
## **The `soundBusy` clause is a poll, not a mixer reading, and that distinction
## is the whole difference between a detector and a blank page.** "Some channel is
## busy" was the first rule, taken from `playhead_escape`, and measured against
## this corpus it excused *every tick of every movie*: these titles run background
## music, so a channel is busy from the first frame to the last and the sweep
## reported six movies as fully accounted for while looking at nothing. Director's
## own evidence that a movie is waiting for a sound is that it **asks** --
## `preview_lingo_host.reached["soundbusy"]` counts the calls -- so the excuse is
## granted for the ticks between two polls and not for a soundtrack.
##
## What is left after that is a playhead the engine cannot account for, and the
## verdicts below split it by **what is on the stage**, because that is the half
## `playhead_escape` does not look at and the half the reported bug lived in:
##
##   `parked`      one (movie, frame) for the whole window, and something is
##                 drawn on it. This is `go to the frame`. **Not a finding** --
##                 it is the single most common state in the corpus.
##   `blank-park`  the same, with **nothing drawn**. A black stage the playhead
##                 will not leave and no hold explains. There is no legitimate
##                 form of this.
##   `ping-pong`   two to four distinct states spanning **two or more movies**.
##                 The reported bug exactly. Two containers cannot be trading
##                 places for a reason the player is waiting on.
##   `blank-cycle` two to four distinct states in one movie, at least one of which
##                 draws nothing. The screen alternating with black.
##   `trap`        two to four distinct states in one movie, all of them drawn. The
##                 `playhead_escape` shape (DAY1's `<character>clicktalk` pair).
##                 **Low confidence and not a failure unless `--strict`**: a
##                 two-frame animation loop that a room holds itself in is the
##                 same shape and is legitimate. Reported so a human can look.
##   `sound-park`  the whole watch was excused by the `soundBusy` clause and the
##                 playhead never left four states. `reached` cannot say *which*
##                 channel was polled, so a loop waiting on a channel that never
##                 falls silent is excused for ever; this is that blind spot
##                 reported instead of hidden. **Not a failure** -- an
##                 uninterruptible cut scene is the same shape.
##
## Two more findings come from outside the playhead:
##
##   `lingo`       the interpreter recorded an error while the movie ran --
##                 "step budget exhausted", a repeat that did not terminate,
##                 handler recursion, an unknown statement. `LingoInterpreter`
##                 clears `errors` at the start of every dispatch, so nothing in
##                 the port had ever read them during play; they are polled here
##                 on every process frame and accumulated. **This one is
##                 lossy and the reason is worth knowing before trusting a clean
##                 run**: `reset_steps` clears the list at the *start* of a
##                 dispatch, and one score step dispatches `idle`, `exitFrame`,
##                 `prepareFrame` and `enterFrame` back to back inside a single
##                 process frame -- so an error raised in any but the last of them
##                 is gone before this can look. What survives is what the last
##                 dispatch of each process frame recorded. A `lingo` finding is
##                 therefore real; the absence of one is not proof. Making it
##                 sound needs a durable sink in the interpreter, which is
##                 `bugs.md` territory rather than this tool's.
##   `no-open`     `go to movie` did not land on the container, or it loaded no
##                 score.
##
## **A blank verdict is withheld while a Movie-In-A-Window is open**, because the
## window is a separate node with its own playhead and the stage underneath it is
## legitimately bare. That exemption is the one place this file can be talked out
## of a finding, and it is narrow on purpose.
##
## ## How it is driven, and what that costs
##
## Real awaited process frames, never a synthetic tick loop: a `for i in N: tick()`
## advances the runtime's clock and not the audio server's, so every `soundBusy`
## guard holds for ever and every scene with speech in it reads as stuck
## (`bugs.md` 22, diagnosed wrong twice, and the reason the sound clause above is
## an excuse rather than an assertion).
##
## Real frames at 8 fps are slow -- measured headless, 7 score ticks a second, so
## one container would take 20 s and a corpus three quarters of an hour. So the
## sweep runs with the **fast-forward toggle** (`--ff`, default 30), which scales
## the delta the clock is told about and therefore the frames *and the holds*
## together, leaving the score's own rate untouched.
##
## The ceiling on that is **aliasing**, and it is the sampler's own failure mode:
## two score ticks between two samples turn a period-2 ping-pong into a constant,
## and the detector then reports the shape it exists to find as a healthy park.
## `MAX_CATCHUP_STEPS` lets one process frame take four score steps, so a machine
## that falls behind aliases whatever `--ff` says. Rather than trust a number
## measured on one machine, every sample carries the **stride** it was taken at
## and a sample that skipped a tick *clears the window* exactly as a hold does --
## so aliasing can cost a finding and can never invent one. What it cannot do is
## go unnoticed: the coverage (contiguously sampled ticks over ticks watched) is
## printed and asserted, because a sweep that saw a third of the movie and
## reported it clean is the dark-harness failure with extra steps.
##
## Sound is the one thing fast-forward cannot scale -- the mixer runs on the audio
## server's clock -- so a `soundBusy` wait takes as long as the sound does however
## fast the score runs. That makes sound-excused ticks *over*-represented at high
## `--ff`, which can only hide a finding, never invent one.
##
## ## What this sweep does not cover
##
## Stated here rather than discovered later:
##
##   * **Containers are opened from the boot movie's session, not cold.** One
##     preview is booted and every container is reached with `lingo_go_movie`, the
##     same call the F12 picker makes. Globals the boot movie set are therefore in
##     scope, and globals a *room chain* would have set are not -- so a movie that
##     needs `globalday` still opens with it VOID. That is a real player path (the
##     picker) and it is not the only one; `playhead_escape --cold` documents the
##     same gap from the other end. `--via` is deliberately absent: making the
##     sweep walk each movie's own entry chain is the next tool, not this one.
##   * **State leaks between containers**, in visit order, because they share one
##     session. That is closer to play than a fresh boot per movie and it means a
##     finding is reproducible with `--only` *only if* the leak was not the cause.
##     Every finding therefore prints its own `--only` command, and one that does
##     not reproduce alone is itself a result worth having.
##   * **Only the stage playhead is watched.** A Movie-In-A-Window has its own,
##     and `movie_churn` is the only thing that looks at it.
##   * **Clicking is shallow.** `--click` presses eligible sprites one at a time
##     from the state the watch ended in, and never two in sequence, so a trap
##     three clicks deep into a dialogue is not reachable from here.
##   * **A movie that needs a keystroke is never woken.** `key_chain` and
##     `cannon_hit` drive keys; this drives none.
##   * **Nothing is asserted about what is drawn being *right*.** A frame that
##     draws fifteen sprites of the wrong artwork is `parked` and healthy here.
##   * **An art-heavy movie is watched for less movie than a light one, and a
##     loaded machine shortens every watch.** What bounds those movies is
##     `WATCH_CAP_MS` rather than `--ticks`: `piposh-dream`'s five `dinner` rooms
##     take 11-15 s to open and then fill the cap at about 3.3 score ticks a
##     second, against 30 on a light one. `--ff` does not fix it and neither does
##     standing the preloader down -- both measured, 95 to 101 ticks either way --
##     because the cost is the *paint*, not the decode-ahead.
##
##     Coverage stays honest, because what is sampled is sampled. What suffers is
##     the *window*: a watch that only ever reached 17 ticks cannot fill a
##     60-tick one, so no rule was ever read over that movie. The summary counts
##     those as `unjudged` and names them rather than letting them read as clean,
##     which is the difference between "we looked and it was fine" and "we did
##     not look". A run with many of them was measured on a busy machine and is a
##     run to repeat, not a result.
##
## Title-agnostic: the rules below know tempo holds, sound channels and sprite
## counts, and no movie, room, channel or member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")

## Score ticks watched per container, and the length of the window a verdict is
## read over. `WATCH` is two windows, so a trap has to be entered and *stayed in*
## rather than passed through on the way somewhere.
##
## `WINDOW` at 60 is 7.5 s of an 8 fps movie -- longer than any gap between two
## lines of speech in this corpus, and long enough that a room's own idle loop
## has come round. It is half `playhead_escape`'s 120 because that harness reads
## one room and this one reads a corpus; the trade is stated rather than hidden,
## and `--window 120` buys the stricter reading back at twice the runtime.
const WATCH := 120
const WINDOW := 60
## Score ticks a container is given to run its opening frame before it is judged.
## Every movie here starts with an `on exitFrame` that initialises the room and
## jumps; judging before that has run judges the wrong frame.
const SETTLE := 24
## The largest reachable set that still counts as a trap rather than as a movie
## going about its business. Three in `playhead_escape`, four here, because a
## cycle that crosses a movie boundary costs two states before it has done
## anything at all.
const CYCLE_MAX := 4
## Director has eight sound channels; this corpus uses four.
const SOUND_CHANNELS := 8
## The fast-forward rate the sweep runs at. See the header for why it is not
## higher: four score steps per tick is where sampling starts to alias.
const FF := 30.0
## The slowest the adaptive rate will go. Below every movie's authored rate in
## these corpora (8-15 fps), so at the floor the clock is asked for less than one
## score step per process frame however long a frame takes to paint.
const FF_FLOOR := 4.0
## Consecutive fully-sampled ticks before the rate is allowed back up.
const FF_RECOVER := 8
## The least of a container's watched ticks that has to be contiguously sampled
## for its verdict to mean anything. Half, because the windows are what matter
## and a run that keeps being broken by aliasing simply produces no window --
## which reads as "clean" and must therefore be reported as what it is.
const MIN_COVERAGE := 0.5
## Process frames given to `go to movie` before the arrival is judged.
const OPEN_FRAMES := 8
## Wall-clock ceilings, so one pathological container cannot eat the sweep.
##
## `CLICK_CAP_MS` is a third of the watch's, and `--click` shortens its tick
## budget to one window as well. Both are budget, not principle: the first watch
## has to be long enough to see a movie settle, while a click's watch only has to
## answer "did that leave the player somewhere they cannot get out of", which is
## exactly one window. Measured without them, on `piposh-dream`: `dinner1.dir`
## alone spent 30 s on its own watch and would have spent 90 s more on three
## clicks, which puts a 52-movie corpus past an hour and makes the flag one
## nobody runs.
const OPEN_CAP_MS := 8000
const WATCH_CAP_MS := 20000
const CLICK_CAP_MS := 12000
## Consecutive process frames without a score tick that end a watch early, and
## what has to be true for the short one to apply.
##
## A movie under Director's `pause` counts no score ticks at all
## (`frame_loop.gd:tick` skips the counter before the hold is even tested), so a
## watch that waits for a tick budget waits for ever on the one state the engine
## can explain perfectly well. `hezsave.dir` is the corpus's example: it pauses on
## frame 8, and before this the sweep spent 80 s of its ceiling on it and reported
## "no score ticks observed" -- the shape of a hang, printed for the one thing
## that certainly is not one.
##
## **The short count applies only while the movie is paused or halted**, because
## those are the only two things that stop the counter, and a bare frame count is
## wrong the moment the adaptive rate slows down: at the floor a score tick is
## several process frames apart by design, and a 30-frame cutoff ended the watch
## of every expensive movie after six ticks. `QUIET_STALL` is the backstop for
## anything neither of those explains, and is deliberately far larger.
const QUIET_FRAMES := 30
const QUIET_STALL := 900

## Verdicts, worst first. The number is the severity a finding is ranked by.
const SEVERITY := {
	"no-open": 5,
	"ping-pong": 4,
	"blank-park": 4,
	"blank-cycle": 3,
	"lingo": 2,
	"trap": 1,
	"sound-park": 1,
}
## Which of them fail the run. `trap` joins this under `--strict`; see the header.
const FAILING := ["no-open", "ping-pong", "blank-park", "blank-cycle", "lingo"]

## The `--ff` ceiling for this run. On the tool rather than threaded through,
## because `_watch` lowers the live rate as it goes and has to know what it is
## allowed back up to; reading it off the node instead would let one slow movie
## pin every movie after it at the floor.
var _ff := FF


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _sweep(h)
	quit(h.finish("every movie in the corpus is one a player could leave"))


## Returns whether it ran to a conclusion rather than whether the checks passed.
## A GDScript runtime error aborts this handler and leaves the case open, which
## `harness.gd` reports as FAIL rather than ending the run quietly.
func _sweep(h: Harness) -> bool:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		h.begin("a corpus to sweep")
		h.check("the config names a game", false)
		return true

	var only := Args.text(args, "only", "").to_lower()
	var limit := Args.number(args, "limit", 0)
	var budget_ms := Args.number(args, "budget-ms", 0)
	var ticks := Args.number(args, "ticks", WATCH)
	var window := Args.number(args, "window", WINDOW)
	var settle := Args.number(args, "settle", SETTLE)
	var clicking := Args.flag(args, "click")
	var clicks := Args.number(args, "clicks", 3)
	var strict := Args.flag(args, "strict")
	var verbose := Args.flag(args, "verbose")
	_ff = float(Args.number(args, "ff", int(FF)))

	# Movies only. A cast is a container and is in the index, and `go to movie` on
	# one loads no score -- the picker refuses them for the same reason.
	var movies: Array[String] = []
	for entry in paths.containers():
		if ContainerName.CAST.has(str(entry).get_extension().to_lower()):
			continue
		if only != "" and not str(entry).to_lower().contains(only):
			continue
		movies.append(str(entry))

	_assert_rules(h)

	var case := "%s: every movie is one a player could leave" % paths.root.get_file()
	h.begin(case)
	if not h.check("the corpus holds movies to sweep", not movies.is_empty(),
			"%d movie(s)%s" % [movies.size(), "" if only == "" else " matching '%s'" % only]):
		h.complete(case)
		return true

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if not h.check("AudioDirector is in the tree", audio != null):
		h.complete(case)
		return true
	# `_ticks` is this file's unit of time and it is not in
	# `tools/preview_surface.gd`'s asserted list, so a rename would make `get()`
	# answer null, `int(null)` answer 0, every window stay empty, and the whole
	# sweep report green over movies it never watched. That is the dark-harness
	# failure `scenes/preview/README.md` names; this is the guard against it.
	if not h.check("the movie's own tick counter is readable",
			preview.get("_ticks") != null):
		h.complete(case)
		return true
	preview.set("_fast_forward_fps", _ff)

	print("")
	print("root      : %s" % paths.root)
	print("movies    : %d" % movies.size())
	print("watch     : %d score ticks each, verdict over %d, settle %d, ff <= %.0f" % [
		ticks, window, settle, _ff])
	print("")

	var findings: Array[Dictionary] = []
	var visited := 0
	var skipped: Array[String] = []
	var started := Time.get_ticks_msec()
	var covered := 0.0
	var thin: Array[String] = []
	var unjudged: Array[String] = []

	for movie in movies:
		if limit > 0 and visited >= limit:
			skipped.append(movie)
			continue
		if budget_ms > 0 and Time.get_ticks_msec() - started >= budget_ms:
			skipped.append(movie)
			continue
		visited += 1
		var seen: Dictionary = await _visit(
			preview, audio, movie, settle, ticks, window)
		covered += float(seen.get("coverage", 1.0))
		if float(seen.get("coverage", 1.0)) < MIN_COVERAGE:
			thin.append("%s %d%%" % [movie.get_file(),
				int(round(float(seen["coverage"]) * 100.0))])
		# A movie whose watch never reached `window` samples was never judged by
		# any of the rules -- there was no window to read one over. It is not a
		# finding and it is not a clean bill of health either, and the difference
		# is only visible if it is counted.
		if int(seen.get("watched", 0)) < window and not _clock_stopped(preview):
			unjudged.append("%s %d/%d" % [
				movie.get_file(), int(seen.get("watched", 0)), window])
		if clicking and str(seen["verdict"]) == "":
			var poked: Dictionary = await _poke(
				preview, audio, movie, clicks, ticks, window)
			if str(poked.get("verdict", "")) != "":
				seen = poked
		if str(seen["verdict"]) != "":
			findings.append(seen)
		if verbose or str(seen["verdict"]) != "":
			print(_line(seen))

	# Coverage is the sampler's own honesty check. A verdict is only read over
	# consecutive *observed* ticks, so a run that keeps aliasing produces no window
	# at all and reports every movie clean -- which is indistinguishable from a
	# healthy corpus unless the number is on the page and asserted.
	# The *mean* alone, and not "no movie was thin". A per-movie threshold makes
	# this entry flake on a loaded machine -- one expensive room sampled badly is
	# the machine, not the engine -- while the mean falling below half means the
	# run as a whole did not see the movies it judged, which is a result.
	var mean := 1.0 if visited == 0 else covered / float(visited)
	h.check("the sampler saw the movies it judged (mean coverage %d%%)"
			% int(round(mean * 100.0)),
		mean >= MIN_COVERAGE,
		"lower --ff; thinnest: %s" % ", ".join(thin.slice(0, 6))
			if not thin.is_empty() else "")

	print("")
	print("visited   : %d of %d movie(s) in %.1f s" % [
		visited, movies.size(), (Time.get_ticks_msec() - started) / 1000.0])
	if not unjudged.is_empty():
		print("unjudged  : %d watched fewer than %d tick(s), so no window was read: %s%s" % [
			unjudged.size(), window, ", ".join(unjudged.slice(0, 6)),
			", ..." if unjudged.size() > 6 else ""])
	if not skipped.is_empty():
		# Logged rather than silently truncated: a sweep that covered a third of
		# the corpus and said "all clear" is worse than one that did not run.
		print("skipped   : %d (--limit/--budget-ms): %s%s" % [
			skipped.size(), ", ".join(skipped.slice(0, 6)),
			", ..." if skipped.size() > 6 else ""])
	print("")

	var failing: Array[Dictionary] = []
	for finding in findings:
		var verdict := str(finding["verdict"])
		if FAILING.has(verdict) or (strict and verdict == "trap"):
			failing.append(finding)
	if not findings.is_empty():
		print("findings, worst first:")
		findings.sort_custom(func(a, b):
			return int(SEVERITY.get(a["verdict"], 0)) > int(SEVERITY.get(b["verdict"], 0)))
		for finding in findings:
			print("  %-11s %s" % [str(finding["verdict"]), str(finding["movie"])])
			print("      %s" % str(finding["detail"]))
			print("      godot --headless --path . --script tools/liveness_sweep.gd -- \\")
			print("          --root %s --only %s%s" % [
				paths.root.get_file(), str(finding["movie"]).get_file(),
				" --click" if bool(finding.get("clicked", false)) else ""])
		print("")

	h.check("no movie is stuck, blank or trading places with another",
		failing.is_empty(),
		"%d finding(s) over %d movie(s)" % [failing.size(), visited])
	if not findings.is_empty() and failing.size() < findings.size():
		print("      (%d further low-confidence finding(s) above are reported and not"
			% (findings.size() - failing.size()))
		print("       asserted -- `trap` and `sound-park`; --strict fails on `trap`)")
	h.complete(case)
	return true


## The rules, against windows built by hand, before a movie is opened.
##
## **A detector whose positive path is never exercised is a dark harness**, and
## this one is the shape most at risk of it: on a healthy corpus every assertion
## below the sweep is "nothing was found", which passes identically whether the
## rules work or whether `_read_window` returns `{}` for everything. `gate.sh`
## has a whole paragraph about harnesses that pass over the empty set; this is
## that paragraph applied to a rule instead of to a subject.
##
## So each verdict is made to fire once from a synthetic window, and — as
## important — the three shapes that must *not* fire are checked too: a park with
## artwork on it (`go to the frame`, the most common state in the corpus), a bare
## stage under an open Movie-In-A-Window, and a playhead moving through more
## states than `CYCLE_MAX`. Costs milliseconds and needs no movie.
func _assert_rules(h: Harness) -> void:
	var name := "the rules fire on the shapes they are for, and on no others"
	h.begin(name)
	for expected in [
		["blank-park", _window_of([["a.dir", 1, 0]])],
		["", _window_of([["a.dir", 1, 7]])],
		["ping-pong", _window_of([["a.dir", 803, 4], ["b.dir", 27, 0]])],
		["ping-pong", _window_of([["a.dir", 803, 4], ["b.dir", 27, 9]])],
		["blank-cycle", _window_of([["a.dir", 5, 3], ["a.dir", 6, 0]])],
		["trap", _window_of([["a.dir", 5, 3], ["a.dir", 6, 4]])],
	]:
		var got := str(_read_window(expected[1]).get("verdict", ""))
		var ok := got == str(expected[0])
		h.check("a window of %s reads as `%s`" % [
				_shape(expected[1]),
				str(expected[0]) if str(expected[0]) != "" else "healthy"],
			ok, "" if ok else "got `%s`" % got)

	# The exemption, on its own, because it is the one place a finding can be
	# talked out of and the one most likely to be widened by accident.
	var under_window := _window_of([["a.dir", 1, 0]])
	for sample in under_window:
		(sample as Dictionary)["windowed"] = true
	h.check("a bare stage under an open window is not a blank park",
		_read_window(under_window).is_empty(),
		str(_read_window(under_window).get("verdict", "")))

	var roaming: Array = []
	for i in WINDOW:
		roaming.append({"movie": "a.dir", "frame": i, "drawn": 6, "hold": "",
			"stride": 1, "windowed": false})
	h.check("a playhead visiting more than %d state(s) is not a trap" % CYCLE_MAX,
		_read_window(roaming).is_empty(),
		str(_read_window(roaming).get("verdict", "")))

	# And the whole of the "do not cry wolf" property in one assertion: the same
	# two-frame ping-pong, with a hold on every tick, must produce no finding at
	# all -- because the window is cleared rather than annotated.
	var held: Array = []
	for i in WINDOW * 4:
		held.append({"movie": "a.dir" if i % 2 == 0 else "b.dir", "frame": 1,
			"drawn": 0, "hold": "wait for click", "stride": 1, "windowed": false})
	var excused := str(_judge("x.dir", {"errors": {}, "samples": held}, WINDOW)["verdict"])
	h.check("the same shape with a hold on every tick is not a finding",
		excused == "", excused)
	h.complete(name)


## `WINDOW` samples cycling through `states`, each `[movie, frame, drawn]`.
static func _window_of(states: Array) -> Array:
	var out: Array = []
	for i in WINDOW:
		var state: Array = states[i % states.size()]
		out.append({"movie": str(state[0]), "frame": int(state[1]),
			"drawn": int(state[2]), "hold": "", "stride": 1, "windowed": false})
	return out


## `a.dir:1(0) <-> b.dir:27(4)` for a synthetic window, for the check's name.
static func _shape(window: Array) -> String:
	var states: Dictionary = {}
	for sample_value in window:
		var sample: Dictionary = sample_value
		states["%s:%d" % [str(sample["movie"]), int(sample["frame"])]] = int(sample["drawn"])
	return _states(states)


## One line of the per-movie report.
static func _line(seen: Dictionary) -> String:
	var verdict := str(seen["verdict"])
	return "  %-11s %-26s %4.1fs+%4.1fs %3d%%  %s" % [
		"ok" if verdict == "" else verdict, str(seen["movie"]),
		int(seen.get("open_ms", 0)) / 1000.0, int(seen.get("watch_ms", 0)) / 1000.0,
		int(round(float(seen.get("coverage", 1.0)) * 100.0)), str(seen["detail"])]


## Open one container, let it settle, and watch it.
##
## `lingo_go_movie` is the engine's own `go to movie` and the F12 picker's call,
## so the container is entered the way the game enters one: `prepareMovie`,
## `startMovie`, the first frame's `prepareFrame` and `enterFrame`. Nothing here
## is a debug path.
func _visit(preview: Node, audio: Node, movie: String, settle: int, ticks: int,
		window: int) -> Dictionary:
	var opening := Time.get_ticks_msec()
	_reset_between(preview)
	preview.call("lingo_go_movie", movie, null)
	for _i in OPEN_FRAMES:
		await process_frame
	# Only the score is asserted, not the name. A movie that immediately hands off
	# to another has opened correctly -- the boot movie of every title does exactly
	# that -- so "did it stay?" is a question for the watch below, where the answer
	# is a state list rather than a boolean.
	if preview.get("_score") == null:
		var absent := _finding(movie, "no-open", "no score loaded after `go to movie`")
		absent["stride"] = 0
		return absent
	await _run_ticks(preview, settle, OPEN_CAP_MS)
	var watching := Time.get_ticks_msec()
	var trace: Dictionary = await _watch(preview, audio, ticks, WATCH_CAP_MS)
	var seen := _judge(movie, trace, window)
	seen["stride"] = int(trace["stride"])
	seen["coverage"] = coverage(trace)
	seen["watched"] = (trace["samples"] as Array).size()
	seen["open_ms"] = watching - opening
	seen["watch_ms"] = Time.get_ticks_msec() - watching
	return seen


## Score ticks this sampler actually saw, over score ticks the movie ran.
##
## A sample taken two ticks after the last one covers one tick and skipped one:
## whatever the playhead did in between is unobserved, and the window it belongs
## to is discarded. So coverage is the fraction of the watch a verdict could
## legitimately have been read over, and a low one is a measurement problem
## rather than a clean movie.
static func coverage(trace: Dictionary) -> float:
	var ran := int(trace.get("ticks", 0))
	if ran <= 0:
		return 1.0
	var seen := 0
	for sample_value in trace["samples"]:
		if int((sample_value as Dictionary)["stride"]) <= 1:
			seen += 1
	return minf(float(seen) / float(ran), 1.0)


## Click what the frame offers and watch what each click leads to.
##
## Where the interesting states are behind a hotspot -- a save panel, a dialogue,
## an inventory -- nothing above ever reaches them, and the bug this file was
## written from was *behind a click*. Eligibility is the engine's own
## (`_responds_to_mouse`), and the point clicked is scanned rather than taken from
## the rect's centre for the reason `pause_holds.gd:_reachable_point` gives: a
## sprite with a transparent middle answers nowhere near its centre.
##
## Each click starts from the state the last watch ended in and is not undone,
## so this is one click deep and says so in the header.
func _poke(preview: Node, audio: Node, movie: String, budget: int, ticks: int,
		window: int) -> Dictionary:
	var tried := 0
	for sprite_value in preview.call("frame_sprites"):
		if tried >= budget:
			break
		var raw: Dictionary = sprite_value
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty() or not bool(preview.call("_responds_to_mouse", sprite)):
			continue
		var channel := int(sprite["channel"])
		var at: Variant = _reachable_point(preview, sprite, channel)
		if at == null:
			continue
		tried += 1
		preview.call("route_press", at)
		preview.call("route_release", at)
		# The same tick budget as the first watch -- a window has to be able to
		# form, and `window` ticks exactly would be destroyed by a single held one
		# -- but a third of the wall clock, which is what actually bounds it.
		var trace: Dictionary = await _watch(preview, audio, ticks, CLICK_CAP_MS)
		var seen := _judge(movie, trace, window)
		seen["clicked"] = true
		seen["stride"] = int(trace["stride"])
		if str(seen["verdict"]) != "":
			seen["detail"] = "after clicking ch%d at (%d,%d): %s" % [
				channel, int((at as Vector2).x), int((at as Vector2).y),
				str(seen["detail"])]
			return seen
	return {"verdict": "", "movie": movie, "detail": "", "clicked": true, "stride": 0}


## A point the mouse can actually reach this sprite at, or null. The same scan
## `pause_holds.gd` uses, and for the same reason.
static func _reachable_point(preview: Node, sprite: Dictionary, channel: int) -> Variant:
	var rect: Rect2 = preview.call("_sprite_rect", sprite)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return null
	for iy in 5:
		for ix in 9:
			var at := rect.position + Vector2(
				rect.size.x * (ix + 0.5) / 9.0, rect.size.y * (iy + 0.5) / 5.0)
			if int(preview.call("_channel_at", at)) == channel:
				return at
	return null


## Hand the session back to a state the next container can be judged from.
##
## Three things survive a `go to movie` and would make the next verdict about the
## last movie: a `quit`/`halt` that stopped the process, a Director `pause` that
## nothing will lift because the frame that could be clicked is gone, and any
## Movie-In-A-Window left open. Globals are deliberately *not* reset -- see the
## header on what the sweep does and does not simulate.
func _reset_between(preview: Node) -> void:
	var host = preview.get("_host")
	if host != null:
		host.stopped = false
		host.playback_paused = false
	preview.set_process(true)
	var windows: Dictionary = preview.get("_windows")
	if windows != null:
		for key in windows.keys():
			preview.call("lingo_forget_window", str(key), true)


## The two states in which the score's own clock legitimately stops counting.
## Everything else that stops it is a stall this sweep wants to sit through and
## report, not one to give up on early.
static func _clock_stopped(preview: Node) -> bool:
	var host = preview.get("_host")
	return host != null and (bool(host.playback_paused) or bool(host.stopped))


## Let the movie run `count` of its *own* score ticks, up to `cap_ms` real ms, and
## give up early on a movie whose clock has stopped -- see `QUIET_FRAMES`.
func _run_ticks(preview: Node, count: int, cap_ms: int) -> void:
	var until := int(preview.get("_ticks")) + count
	var start := Time.get_ticks_msec()
	var last := int(preview.get("_ticks"))
	var quiet := 0
	while int(preview.get("_ticks")) < until and Time.get_ticks_msec() - start < cap_ms:
		await process_frame
		var now := int(preview.get("_ticks"))
		quiet = 0 if now != last else quiet + 1
		last = now
		if quiet >= (QUIET_FRAMES if _clock_stopped(preview) else QUIET_STALL):
			return


## Sample the playhead once per score tick for `budget` ticks.
##
## Real frames are awaited rather than ticked synthetically. That is load-bearing
## and not tidiness: a synthetic loop advances the runtime's clock and not the
## audio server's, so every sound stays busy for ever, every `soundBusy` guard
## holds, and every excuse this file grants would be granted to every trap it was
## built to find (`bugs.md` 22).
##
## The rate is **adaptive**, which is the only thing that makes the sweep usable
## on an art-heavy movie. A frame that spends 200 ms decoding a 2 MB backdrop
## leaves the clock owing three or four score steps, `MAX_CATCHUP_STEPS` pays all
## of them in one process frame, and the sampler sees one state where four
## happened. Measured before this existed: `piposh-dream`'s three `hatul` rooms
## came back at 0% coverage and were reported clean over a movie nobody had
## looked at. So the requested `--ff` is a *ceiling*: it is halved on any sample
## that skipped a tick and crept back up while none does, down to `FF_FLOOR`,
## which is below the rate every movie in these corpora is authored at and
## therefore asks the clock for less than one step per process frame.
##
## Returns `{samples, stride, errors, movies, ticks}`.
func _watch(preview: Node, audio: Node, budget: int, cap_ms: int) -> Dictionary:
	var samples: Array[Dictionary] = []
	var errors: Dictionary = {}
	var stride := 0
	var clock = preview.get("_clock")
	var host = preview.get("_host")
	var interpreter = preview.get("_interpreter")
	var start := Time.get_ticks_msec()
	var began := int(preview.get("_ticks"))
	var last := began
	var quiet := 0
	# How many times the movie has asked `soundBusy`. The delta between two
	# samples is what says "this movie is waiting for a sound" as against "this
	# movie has a soundtrack"; see the header.
	var polls := 0 if host == null \
		else int((host.reached as Dictionary).get("soundbusy", 0))
	var rate := _ff
	var clean := 0
	preview.set("_fast_forward_fps", rate)
	while int(preview.get("_ticks")) - began < budget \
			and Time.get_ticks_msec() - start < cap_ms:
		await process_frame
		# Polled every process frame rather than every score tick: the interpreter
		# clears `errors` at the start of every dispatch, so a failure recorded
		# between two ticks is gone by the next one.
		if interpreter != null:
			for message in interpreter.errors:
				errors[str(message)] = int(errors.get(str(message), 0)) + 1
		var now := int(preview.get("_ticks"))
		if now == last:
			quiet += 1
			# A clock that has stopped is either Director's `pause` or the movie
			# having halted, and both are answers rather than hangs. One sample is
			# still taken, so the report says which of them it was instead of
			# reporting the empty set as "nothing observed".
			if quiet >= (QUIET_FRAMES if _clock_stopped(preview) else QUIET_STALL):
				samples.append(_sample(preview, audio, clock, host, 1, polls))
				break
			continue
		quiet = 0
		var step := now - last
		stride = maxi(stride, step)
		last = now
		var asked := 0 if host == null \
			else int((host.reached as Dictionary).get("soundbusy", 0))
		samples.append(_sample(preview, audio, clock, host, step, asked - polls))
		polls = asked
		# The control loop. Down hard on any skipped tick, up gently while none
		# is skipped, so a movie that is only briefly expensive -- one cold
		# backdrop -- is not left crawling for the rest of its watch.
		if step > 1:
			rate = maxf(rate * 0.5, FF_FLOOR)
			clean = 0
			preview.set("_fast_forward_fps", rate)
		elif rate < _ff:
			clean += 1
			if clean >= FF_RECOVER:
				clean = 0
				rate = minf(rate * 1.5, _ff)
				preview.set("_fast_forward_fps", rate)
	var movies: Dictionary = {}
	for sample in samples:
		movies[str(sample["movie"])] = true
	return {"samples": samples, "stride": stride, "errors": errors,
		"movies": movies.keys(), "ticks": int(preview.get("_ticks")) - began}


## What the player is looking at, and whether anything can say why.
##
## **Only the drawn count, deliberately.** Eligibility was in here and is the
## single most expensive question the engine can be asked -- `_responds_to_mouse`
## reaches the hit-pixel path, and asking it of every sprite of every sample cost
## a factor of nine: the sweep ran at 6.5 score ticks a second where the
## fast-forward had asked for 60, and, worse, the process loop then fell so far
## behind the clock that `MAX_CATCHUP_STEPS` was taking four score steps between
## two samples. A period-2 ping-pong sampled every four steps reads as a
## *constant*, so the cost was not just slowness -- it blinded the detector to its
## own subject. The stride carried on every sample is what caught it, and that is
## why it is carried.
##
## Nothing is lost: no verdict reads eligibility. `--click` asks it once per
## container, where it belongs.
static func _sample(preview: Node, audio: Node, clock, host, stride: int,
		polls: int) -> Dictionary:
	var drawn := 0
	for raw in preview.call("frame_sprites"):
		# `{}` is a sprite a script has hidden: it is not on the stage, and counting
		# it would count a black screen as a populated one.
		if not (preview.call("_effective", raw) as Dictionary).is_empty():
			drawn += 1
	var reason := "" if clock == null else str(clock.hold_reason())
	if host != null and bool(host.playback_paused):
		reason = "pause"
	elif host != null and bool(host.stopped):
		reason = "halted"
	elif polls > 0:
		# The movie asked `soundBusy` since the last sample. It is only waiting if
		# something is in fact playing -- a poll that answers "no" is the tick the
		# room moves on, and excusing it would excuse the frame after the answer.
		for channel in range(1, SOUND_CHANNELS + 1):
			if bool(audio.call("sound_busy", channel)):
				reason = "wait for sound %d" % channel
				break
	var windows: Dictionary = preview.get("_windows")
	return {
		"movie": str(preview.call("movie_name")),
		"frame": int(preview.call("current_frame")),
		"drawn": drawn,
		"hold": reason,
		"stride": stride,
		"windowed": windows != null and not windows.is_empty(),
	}


## Turn a watch into a verdict.
##
## The window is *cleared* by an excused tick rather than annotated, so what is
## looked for is `window` consecutive score ticks the engine cannot account for.
## The worst window in the run wins, because a movie that settles into a trap
## after eight healthy seconds is still a movie the player cannot leave.
static func _judge(movie: String, trace: Dictionary, window: int) -> Dictionary:
	var errors: Dictionary = trace["errors"]
	var samples: Array = trace["samples"]
	var run: Array = []
	var worst: Dictionary = {}
	for sample_value in samples:
		var sample: Dictionary = sample_value
		# A hold is an answer, and a *skipped* tick is an unknown -- the playhead
		# moved somewhere this sampler never saw. Both break the run, because a
		# window is only evidence if it is `window` consecutive ticks that were
		# both watched and unexplained.
		if str(sample["hold"]) != "" or int(sample["stride"]) > 1:
			run.clear()
			continue
		run.append(sample)
		if run.size() < window:
			continue
		var found := _read_window(run.slice(run.size() - window))
		if not found.is_empty() and (worst.is_empty()
				or int(SEVERITY.get(found["verdict"], 0))
					> int(SEVERITY.get(worst["verdict"], 0))):
			worst = found
		run.remove_at(0)

	if not worst.is_empty():
		var seen := _finding(movie, str(worst["verdict"]), str(worst["detail"]))
		if not errors.is_empty():
			seen["detail"] = "%s; lingo: %s" % [seen["detail"], _errors(errors)]
		return seen
	# A Lingo error on a movie that is otherwise well behaved is still a finding:
	# "step budget exhausted" means a handler was cut off part-way, and what it
	# did not get to do is invisible until something else goes wrong.
	if not errors.is_empty():
		return _finding(movie, "lingo", _errors(errors))
	var stuck := _sound_park(samples, window)
	if stuck != "":
		return _finding(movie, "sound-park", stuck)
	return _finding(movie, "", _healthy(samples))


## The `soundBusy` clause's own blind spot, reported rather than left silent.
##
## The excuse is granted whenever the movie polls `soundBusy` and *some* channel
## is playing, and `reached` cannot say which channel was asked about. So a loop
## waiting on a channel that will never finish -- one carrying a looped
## soundtrack, say -- is excused for ever and the trap it is sitting in is
## invisible to every rule above. What that case still cannot hide is its own
## shape: a movie that spends a whole watch inside `CYCLE_MAX` states with the
## sound excuse covering every one of them is either waiting on a very long clip
## or is not waiting at all, and a human can tell in one listen.
##
## Reported at the lowest severity and never asserted, because the legitimate
## reading is real: an uninterruptible cut scene looks exactly like this.
static func _sound_park(samples: Array, window: int) -> String:
	if samples.size() < window:
		return ""
	var states: Dictionary = {}
	for sample_value in samples:
		var sample: Dictionary = sample_value
		if not str(sample["hold"]).begins_with("wait for sound"):
			return ""
		states["%s:%d" % [str(sample["movie"]).get_file(), int(sample["frame"])]] = \
			int(sample["drawn"])
	if states.size() > CYCLE_MAX:
		return ""
	return "waiting on sound for all %d watched tick(s) inside %d state(s): %s" % [
		samples.size(), states.size(), _states(states)]


static func _errors(errors: Dictionary) -> String:
	var out: Array[String] = []
	for message in errors:
		out.append("%s x%d" % [str(message), int(errors[message])])
	out.sort()
	return ", ".join(out.slice(0, 4))


## What a clean container looked like, so a `--verbose` line says something.
static func _healthy(samples: Array) -> String:
	if samples.is_empty():
		return "no score ticks observed"
	var states: Dictionary = {}
	var holds: Dictionary = {}
	var last: Dictionary = samples[-1]
	for sample_value in samples:
		var sample: Dictionary = sample_value
		states["%s:%d" % [str(sample["movie"]), int(sample["frame"])]] = true
		var reason := str(sample["hold"])
		if reason != "":
			holds[reason] = int(holds.get(reason, 0)) + 1
	var named: Array[String] = []
	for reason in holds:
		named.append("%s x%d" % [str(reason), int(holds[reason])])
	named.sort()
	return "%d state(s) over %d tick(s), ends on %s f%d with %d drawn%s" % [
		states.size(), samples.size(), str(last["movie"]).get_file(),
		int(last["frame"]), int(last["drawn"]),
		"" if named.is_empty() else ", held: %s" % ", ".join(named)]


## The rules, over one window of unexplained score ticks. `{}` is "nothing wrong".
static func _read_window(w: Array) -> Dictionary:
	var states: Dictionary = {}
	var movies: Dictionary = {}
	var blank: Dictionary = {}
	var windowed := false
	for sample_value in w:
		var sample: Dictionary = sample_value
		var key := "%s:%d" % [str(sample["movie"]).get_file(), int(sample["frame"])]
		states[key] = int(sample["drawn"])
		movies[str(sample["movie"]).get_file()] = true
		if int(sample["drawn"]) == 0:
			blank[key] = true
		if bool(sample["windowed"]):
			windowed = true
	var where := _states(states)
	# The one exemption. A Movie-In-A-Window has its own playhead and paints over
	# the stage, so a bare stage underneath one is not a black screen.
	if not blank.is_empty() and windowed:
		blank.clear()

	if states.size() == 1:
		if blank.is_empty():
			return {}
		return {"verdict": "blank-park",
			"detail": "parked on %s for %d tick(s) with nothing drawn and no hold"
				% [where, w.size()]}
	if states.size() > CYCLE_MAX:
		return {}
	if movies.size() >= 2:
		return {"verdict": "ping-pong",
			"detail": "%d movie(s) trading places for %d tick(s): %s"
				% [movies.size(), w.size(), where]}
	if not blank.is_empty():
		return {"verdict": "blank-cycle",
			"detail": "cycling for %d tick(s) through a frame with nothing drawn: %s"
				% [w.size(), where]}
	return {"verdict": "trap",
		"detail": "confined to %d state(s) for %d tick(s) with no hold: %s"
			% [states.size(), w.size(), where]}


## `movie:frame(drawn)` for each state, sorted, so two runs print the same line.
static func _states(states: Dictionary) -> String:
	var keys: Array = states.keys()
	keys.sort()
	var out: Array[String] = []
	for key in keys:
		out.append("%s(%d)" % [str(key), int(states[key])])
	return " <-> ".join(out)


static func _finding(movie: String, verdict: String, detail: String) -> Dictionary:
	return {"movie": movie, "verdict": verdict, "detail": detail}
