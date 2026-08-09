extends SceneTree
## Does the preview run a frame the way Director does?
##
##   godot --headless --path . --script tools/frame_events.gd -- --file PIP2DATA/DAY1.dir
##
## Two things, both from `docs/DIRECTOR_ENGINE.md` §6.1 and §9-10.
##
## **The order.** `exitFrame` belongs to the frame being *left* and runs at the
## top of the step that leaves it, with the playhead advance and the redraw after
## it and `enterFrame` after those. The preview used to fire `prepareFrame`,
## `enterFrame` and `exitFrame` back to back on one frame and then advance, which
## runs both halves of the "set up in enterFrame, tear down in exitFrame" idiom
## against the same rendered state. This drives the real preview node and asserts
## the property directly: the frame each step says it exited must be the frame the
## step before it said it was on.
##
## **The time.** A tempo delay, a wait-for-click and a transition all stop the
## playhead, and the port took none of them. The clock cases below are run on
## `director/director_frame_clock.gd` in isolation because a wait is a *state
## polled every tick* — a harness that drove it through the scene would be
## measuring Godot's frame pacing rather than the rule.
##
## Corpus-aware on purpose: `tools/lib/` may not know which game is loaded, but a
## harness that asserts nothing about the movie in front of it is a tautology.
## The DAY1 case is named as such and skipped for any other movie.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Clock := preload("res://director/director_frame_clock.gd")
const Transition := preload("res://director/director_transition.gd")
## Loaded rather than preloaded. `preload`ing the compiler at the top of this file
## puts it ahead of `scenes/director_preview.gd` in the resolution order and the
## preview's own `preload` of `preview_lingo_host.gd` then fails to resolve, taking
## the whole scene with it -- a parse error in a file this harness does not touch.
const COMPILER_PATH := "res://lingo/compile/lingo_compiler.gd"

## Long enough to leave the opening frame, cross a `go` and settle into a room
## that holds itself, which is where the ordering has to keep working.
const STEPS := 24
## One 60 Hz tick, the unit the clock is driven in below.
const TICK := 1.0 / 60.0


## Real time, a tick at a time, until the clock stops holding the playhead or the
## budget runs out. Returns the milliseconds it took, so a hold can be measured
## rather than merely observed to end.
func _run_until_free(clock, budget_ms: float) -> float:
	var spent := 0.0
	while clock.playhead_held() and spent < budget_ms:
		clock.tick(TICK)
		spent += TICK * 1000.0
	return spent


func _clock_cases(h) -> void:
	h.begin("a tempo delay holds the playhead for its duration")
	var clock = Clock.new()
	clock.enter_frame({"fps": 15.0, "delay_ms": 500, "wait_click": false})
	h.check("the delay arms the hold", clock.playhead_held(), clock.status())
	var spent := _run_until_free(clock, 2000.0)
	# A tick is 16.7 ms, so the hold ends on the first tick at or past 500 ms.
	h.check("it lasts about as long as it asked for",
		spent >= 500.0 and spent < 520.0, "%.1f ms" % spent)
	h.check("and then lets the playhead go", not clock.playhead_held(), clock.status())
	h.complete("a tempo delay holds the playhead for its duration")

	h.begin("a wait-for-click holds until a click and not until a timer")
	var waiting = Clock.new()
	waiting.enter_frame({"fps": 15.0, "delay_ms": 0, "wait_click": true})
	h.check("the wait arms", waiting.playhead_held(), waiting.status())
	var waited := _run_until_free(waiting, 5000.0)
	h.check("no amount of time releases it", waiting.playhead_held(),
		"still held after %.0f ms" % waited)
	waiting.clicked()
	h.check("a click does", not waiting.playhead_held(), waiting.status())
	h.complete("a wait-for-click holds until a click and not until a timer")

	# §9.2. Without this a script that navigates out of a waiting frame is made to
	# serve the rest of the wait on the frame it has already left.
	h.begin("a queued `go to` cancels every wait")
	var jumped = Clock.new()
	jumped.enter_frame({"fps": 15.0, "delay_ms": 3000, "wait_click": true})
	h.check("both a delay and a click wait are armed", jumped.playhead_held())
	jumped.release()
	h.check("the jump clears them", not jumped.playhead_held(), jumped.status())
	h.complete("a queued `go to` cancels every wait")

	# The movie's clock and the playhead's are not the same clock: a character
	# talking on a wait-for-click frame must keep animating while the frame waits.
	h.begin("the movie clock keeps ticking while the playhead is held")
	var ticking = Clock.new()
	ticking.enter_frame({"fps": 15.0, "delay_ms": 1000, "wait_click": false})
	var ticks := 0
	for _i in 30:
		ticks += ticking.tick(TICK)
	h.check("ticks accrue through the hold", ticks > 0, "%d tick(s) in 500 ms" % ticks)
	h.check("but the playhead is still held", ticking.playhead_held(), ticking.status())
	h.complete("the movie clock keeps ticking while the playhead is held")

	# A stall must not be replayed as a burst of frames the moment it ends: seven
	# steps of a walk state machine in one paint is a teleport.
	h.begin("a long stall is not owed back all at once")
	var stalled = Clock.new()
	stalled.enter_frame({"fps": 15.0, "delay_ms": 0, "wait_click": false})
	var burst := stalled.tick(2.0)
	h.check("a two-second stall yields at most the cap",
		burst <= Clock.MAX_CATCHUP_STEPS, "%d steps" % burst)
	h.complete("a long stall is not owed back all at once")

	_puppet_tempo_cases(h)
	_video_wait_cases(h)
	_hold_arithmetic_cases(h)


## §9.1's puppet tempo: what it overrides, and what takes the wheel back.
##
## Every case here is unexercised by both corpora -- no script in any of the six
## titles calls `puppetTempo` -- so this is the whole of the rule's cover. The
## frames are built rather than found for that reason, and they are built as the
## score would hand them over: a `tempo` cell and its operand, decoded by the
## clock rather than pre-digested here, or the rule would be asserted against a
## restatement of itself.
func _puppet_tempo_cases(h) -> void:
	h.begin("a puppet tempo overrides the score's, and the score takes it back")
	var clock = Clock.new()
	clock.movie_file_version = Clock.FILE_VERSION_D6
	clock.movie_default_fps = 8.0
	clock.reset()
	# A frame with no tempo of its own: the movie plays at the rate it states.
	clock.enter_frame({"tempo": 0, "tempo_cue": 0})
	h.check("with no tempo anywhere the movie plays at its stated rate",
		is_equal_approx(clock.fps, 8.0), clock.status())

	clock.set_puppet_tempo(30)
	h.check("a puppet tempo takes effect at the call, not at the next frame",
		is_equal_approx(clock.fps, 30.0), clock.status())
	clock.enter_frame({"tempo": 0, "tempo_cue": 0})
	clock.enter_frame({"tempo": 0, "tempo_cue": 0})
	# The reference assigns its `_lastTempo` *after* substituting the puppet, so
	# the frame after the one the puppet applied on finds the score's tempo
	# different from the puppet's and cancels it. That makes every puppet tempo
	# exactly one frame long, which is neither §9.1 nor the verb Macromedia
	# documented. Two frames are stepped here because one would pass either way.
	h.check("it survives frames the score writes no tempo on",
		is_equal_approx(clock.fps, 30.0) and clock.puppet_tempo() == 30, clock.status())

	# §9.1's first release condition: the score writes a tempo.
	clock.enter_frame({"tempo": 246, "tempo_cue": 12})
	h.check("a tempo cell cancels the puppet", clock.puppet_tempo() == 0, clock.status())
	h.check("and the rate is the cell's, not the puppet's",
		is_equal_approx(clock.fps, 12.0), clock.status())
	clock.enter_frame({"tempo": 0, "tempo_cue": 0})
	h.check("the cancelled puppet does not come back",
		is_equal_approx(clock.fps, 12.0) and clock.puppet_tempo() == 0, clock.status())

	# Handing it back is not a rate change: Director leaves the rate where it is
	# until something names a new one.
	clock.set_puppet_tempo(24)
	h.check("a second puppet tempo takes hold", is_equal_approx(clock.fps, 24.0))
	clock.set_puppet_tempo(0)
	h.check("`puppetTempo 0` stops overriding without restoring a rate",
		clock.puppet_tempo() == 0 and is_equal_approx(clock.fps, 24.0), clock.status())
	h.complete("a puppet tempo overrides the score's, and the score takes it back")

	# The numbering the *argument* is read in. It is not the movie's: a
	# `puppetTempo` value never came out of a score cell, and reading a D6 movie's
	# `puppetTempo 30` in the D6 cell numbering makes it a wait for the digital
	# video in channel 30 -- which is what the reference does, and which leaves
	# the verb doing nothing at all in any movie this port can open.
	h.begin("a puppetTempo argument is read in the verb's numbering, not the file's")
	var d6 = Clock.new()
	d6.movie_file_version = Clock.FILE_VERSION_D6
	d6.reset()
	d6.set_puppet_tempo(30)
	h.check("30 is thirty frames per second in a D6 movie",
		is_equal_approx(d6.fps, 30.0) and d6.waiting_video() == 0, d6.status())
	var clicky = Clock.new()
	clicky.movie_file_version = Clock.FILE_VERSION_D6
	clicky.reset()
	clicky.set_puppet_tempo(128)
	h.check("128 waits for a click, as the tempo channel's own 128 does",
		clicky.waiting_click() and clicky.playhead_held(), clicky.status())
	var slow = Clock.new()
	slow.movie_file_version = Clock.FILE_VERSION_D6
	slow.reset()
	slow.set_puppet_tempo(254)
	h.check("254 delays two seconds", slow.playhead_held(), slow.status())
	var lasted := _run_until_free(slow, 4000.0)
	h.check("and lasts about two seconds", lasted >= 2000.0 and lasted < 2040.0,
		"%.1f ms" % lasted)
	h.complete("a puppetTempo argument is read in the verb's numbering, not the file's")

	# Setting a tempo is not a way out of a wait. The reference's
	# `updateNextFrameTime` only ever *sets* a wait flag; the flags go down when
	# their own condition is met, so a script raising the frame rate on a frame
	# that is waiting for a click leaves it waiting for a click.
	h.begin("a puppet tempo does not cancel the wait the frame is already holding")
	var held = Clock.new()
	held.movie_file_version = Clock.FILE_VERSION_D6
	held.reset()
	held.enter_frame({"tempo": 248, "tempo_cue": 0})
	h.check("the frame waits for a click", held.waiting_click(), held.status())
	held.set_puppet_tempo(30)
	h.check("a puppet tempo takes the rate", is_equal_approx(held.fps, 30.0))
	h.check("and leaves the wait standing", held.waiting_click() and held.playhead_held(),
		held.status())
	held.clicked()
	h.check("the click is still what releases it", not held.playhead_held(), held.status())
	h.complete("a puppet tempo does not cancel the wait the frame is already holding")


## §9.1's wait-for-video, and the only two answers a port with no decoder can
## give: hold for ever, or treat the video as already finished. The second is the
## one Director gives for a channel holding no video, so it is also the right
## thing to degrade to.
func _video_wait_cases(h) -> void:
	h.begin("a wait-for-video holds only while something says the video is playing")
	# D6: any cell that is not one of the five codes numbers a sprite channel.
	var clock = Clock.new()
	clock.movie_file_version = Clock.FILE_VERSION_D6
	clock.reset()
	# The probe goes on **before** anything asks the clock a question, and the
	# order is the rule rather than tidiness: every query that can report a hold
	# also releases a video wait the probe does not vouch for, so a `status()` in
	# a check's own detail string is enough to clear it. That is the degrade
	# working, and it fails this case if the probe arrives second.
	# A dictionary rather than a bool, because a GDScript lambda captures a local
	# **by value** at the moment it is written: a captured `var playing := true`
	# stays true however the harness reassigns it, and the case then passes the
	# two checks that want a held playhead and fails only the release.
	var video := {"playing": true}
	clock.video_probe = func(_channel: int) -> bool: return bool(video["playing"])
	clock.enter_frame({"tempo": 7, "tempo_cue": 0})
	h.check("a D6 cell of 7 arms a wait on channel 7", clock.waiting_video() == 7,
		clock.status())
	h.check("it holds while the video is playing", clock.playhead_held(), clock.status())
	h.check("and no amount of time releases it",
		_run_until_free(clock, 3000.0) >= 3000.0, clock.status())
	video["playing"] = false
	h.check("the video finishing releases it", not clock.playhead_held(), clock.status())

	# The degrade, which is the case this port is actually in today.
	var bare = Clock.new()
	bare.movie_file_version = Clock.FILE_VERSION_D6
	bare.reset()
	bare.enter_frame({"tempo": 7, "tempo_cue": 0})
	h.check("with no decoder behind it the wait releases at once",
		not bare.playhead_held(), bare.status())
	h.check("and the channel is cleared rather than left armed",
		bare.waiting_video() == 0, bare.status())

	# Pre-D6, where the video band is 136..195 and the channel is biased by 135.
	var old = Clock.new()
	old.movie_file_version = Clock.FILE_VERSION_D6 - 1
	old.reset()
	old.enter_frame({"tempo": 138, "tempo_cue": 0})
	h.check("a pre-D6 cell of 138 arms a wait on channel 3",
		old.waiting_video() == 3, old.status())

	# §9.2: a queued `go to` cancels every wait, and a video wait is one.
	var jumped = Clock.new()
	jumped.movie_file_version = Clock.FILE_VERSION_D6
	jumped.reset()
	jumped.video_probe = func(_channel: int) -> bool: return true
	jumped.enter_frame({"tempo": 7, "tempo_cue": 0})
	h.check("a video wait holds a jumping frame first", jumped.playhead_held())
	jumped.release()
	h.check("and a queued `go to` cancels it",
		not jumped.playhead_held() and jumped.waiting_video() == 0, jumped.status())
	h.complete("a wait-for-video holds only while something says the video is playing")


## How two holds on one frame add up, and which of them `holding_transition`
## reports. Both were wrong in the same place: one counter cannot answer both
## "how long is the playhead held" and "is the frame still arriving".
func _hold_arithmetic_cases(h) -> void:
	h.begin("a transition and a tempo delay are consecutive, not concurrent")
	var clock = Clock.new()
	clock.enter_frame({"fps": 15.0, "delay_ms": 2000})
	clock.hold(500.0, Clock.REASON_TRANSITION)
	# Director plays the wipe inside the render and computes the next frame's due
	# time when it has finished, so the delay begins where the transition ends.
	var spent := _run_until_free(clock, 6000.0)
	h.check("the frame is held for both of them",
		spent >= 2500.0 and spent < 2540.0, "%.1f ms" % spent)
	h.complete("a transition and a tempo delay are consecutive, not concurrent")

	h.begin("`holding_transition` reports the transition, not the longest hold")
	var both = Clock.new()
	both.enter_frame({"fps": 15.0, "delay_ms": 2000})
	both.hold(500.0, Clock.REASON_TRANSITION)
	h.check("a wipe under a longer delay still reads as a transition",
		both.holding_transition(), both.status())
	# `_enter_frame_or_defer` asks this to decide whether `enterFrame` may run
	# yet, so a wipe it cannot see is a handler running over a frame that is
	# still arriving.
	var wiping := 0.0
	while both.holding_transition() and wiping < 3000.0:
		both.tick(TICK)
		wiping += TICK * 1000.0
	h.check("and stops reading as one when the wipe is over, not when the hold is",
		wiping >= 500.0 and wiping < 540.0 and both.playhead_held(),
		"%.1f ms, %s" % [wiping, both.status()])
	h.complete("`holding_transition` reports the transition, not the longest hold")

	h.begin("aborting a colour cycle drops its hold and nothing else")
	var mixed = Clock.new()
	mixed.movie_file_version = Clock.FILE_VERSION_D6
	mixed.reset()
	# A frame waiting on sound channel 1 that is also running a palette effect.
	mixed.enter_frame({"tempo": 255, "tempo_cue": -1})
	mixed.hold(900.0, Clock.REASON_PALETTE)
	mixed.release_hold(Clock.REASON_PALETTE)
	h.check("the cycle's hold goes", int(mixed.waiting_sound()["channel"]) == 1
		and mixed.playhead_held(), mixed.status())
	h.check("and the wait for the sound stays",
		mixed.hold_reason() == "wait for sound 1", mixed.hold_reason())
	h.complete("aborting a colour cycle drops its hold and nothing else")


func _transition_cases(h, paths) -> void:
	# The three sources of §10, in priority order. Sources 1 and 3 are checked
	# here because nothing in this corpus reaches them: no script calls
	# `puppetTransition`, so without this the rule "a scripted transition beats
	# the frame's own" would be written down and never run.
	h.begin("the three transition sources resolve in priority order")
	var puppet := {"transition_type": 1, "duration_ms": 250.0, "chunk_size": 16}
	var frame := {"transition_type": 11, "duration_ms": 700.0, "chunk_size": 16}
	h.check("a puppet transition beats the frame's own",
		int(Transition.resolve(puppet, frame).get("transition_type", 0)) == 1)
	h.check("the frame's own applies when there is no puppet",
		int(Transition.resolve({}, frame).get("transition_type", 0)) == 11)
	h.check("neither means no transition, not a zero-length one",
		not Transition.is_transition(Transition.resolve({}, {})))
	h.check("a hold is never shorter than the duration asked for",
		Transition.hold_ms(frame) >= 700.0, "%.1f ms" % Transition.hold_ms(frame))
	h.complete("the three transition sources resolve in priority order")

	# Read out of the containers rather than restated: the six-byte member layout
	# in `director/director_transition.gd` is a reading of three records, and a
	# reading is the kind of thing that stops being true when a decoder changes.
	h.begin("every transition this corpus plays decodes to a real duration")
	var found := 0
	var total_ms := 0.0
	var dir := DirAccess.open(paths.root.path_join("PIP2DATA"))
	var names: PackedStringArray = dir.get_files() if dir != null else PackedStringArray()
	for entry in names:
		if not Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			continue
		var file := ContainerFile.new()
		if not file.open(paths.root.path_join("PIP2DATA").path_join(entry)):
			continue
		var vwsc: Array = file.ids_of("VWSC")
		if vwsc.is_empty():
			file.close()
			continue
		var score := Score.new()
		if not score.parse(file.read_chunk(int(vwsc[0]))):
			file.close()
			continue
		var table := CastTable.new()
		table.open(file, paths)
		for i in score.frame_count:
			var record: Dictionary = score.frame(i)
			var number := int(record.get("transition_member", 0))
			if number <= 0:
				continue
			var cast = table.cast_for(int(record.get("transition_lib", 1)))
			var member: Dictionary = cast.member(number) if cast != null else {}
			if Transition.is_transition(member):
				found += 1
				total_ms += Transition.hold_ms(member)
		table.close()
		file.close()
	# Five, at the time of writing (`tools/transition_survey.gd`). Asserted as
	# "some, and every one of them times" rather than as "exactly five": the
	# count is a property of the game's data and would make this fail on a
	# re-extraction that found one more, which teaches nothing.
	h.check("the movies do play transitions", found > 0, "%d frame(s)" % found)
	h.check("and every one carries a duration to spend",
		found == 0 or total_ms > 0.0, "%.1f s in total" % (total_ms / 1000.0))
	h.complete("every transition this corpus plays decodes to a real duration")


## A step whose `exitFrame` opens another movie enters that movie's frame **once**.
##
## `Score::update` returns at `score.cpp:696-698` — "the exitFrame event handler may
## have stopped this movie" — and again at `:722-724`, both before the playhead is
## resolved, so a `go to movie` from an `exitFrame` handler contributes no
## `updateCurrentFrame`, no `renderFrame` and no `enterFrame` to the step it was
## issued in. The arriving movie enters its own first frame, and that is the only
## entry there is.
##
## This port opens the container inside the `go to movie` call rather than queueing
## it, so the arriving movie has already entered its first frame by the time the
## dispatch returns — and without the guard the tail of the step ran straight over
## the top of it. Measured on `DAY1.dir` frame 729, whose whole frame script is
## `on exitFrame / go(1, "air1.dir")`: one step, **two** `enterFrame`s for AIR1's
## opening frame against one `prepareFrame`. A room's `on enterFrame` is where this
## corpus establishes visibility, cursors and character placement, so running it
## twice on arrival is not a duplicate log line.
##
## Built rather than found, so the case does not depend on which movie is pinned: a
## frame with no frame script of its own is chosen (the movie-script fallback then
## answers `exitFrame`), and the destination is the movie already playing, which
## still replaces the score object and keeps the harness title-agnostic.
func _movie_change_enters_once(h: Harness, preview: Node) -> void:
	var case_name := "a step that changes movie enters the arriving frame once"
	h.begin(case_name)
	var score = preview.get("_score")
	var bare := -1
	for i in score.frame_count:
		if (preview.call("_frame_script", i) as Dictionary).is_empty():
			bare = i
			break
	if not h.check("the movie has a frame with no frame script to hang the probe on",
			bare >= 0, "every frame of %s carries one" % preview.call("movie_name")):
		h.complete(case_name)
		return

	var compiler = load(COMPILER_PATH).new()
	var hop: Dictionary = compiler.compile_source("""
on exitFrame
  go to movie "%s"
end
""" % str(preview.call("movie_name")), "MovieScript 9101")
	if not h.check("the probe compiles", not hop.is_empty(), compiler.error):
		h.complete(case_name)
		return
	preview.get("_interpreter").load_bundle(
		{"movie": "PROBE", "cast": "probe", "scripts": {"MovieScript 9101": hop}})

	preview.set("_index", bare)
	preview.set("_jump_queued", false)
	preview.set("_exit_frame_called", false)
	var sent: Dictionary = preview.get("_sent")
	var enters := int(sent.get("enterFrame", 0))
	var prepares := int(sent.get("prepareFrame", 0))
	var was: String = str(preview.call("movie_name"))
	var before_score = preview.get("_score")
	preview.call("_advance")
	var entered := int(sent.get("enterFrame", 0)) - enters
	var prepared := int(sent.get("prepareFrame", 0)) - prepares

	# The movie has to have actually been replaced, or the counts below are about a
	# step that never changed movie and every one of them passes for free.
	if not h.check("the step did change movie", preview.get("_score") != before_score,
			"still on %s" % was):
		h.complete(case_name)
		return
	h.check("exactly one `enterFrame` for the arriving frame", entered == 1,
		"%d dispatched in one step" % entered)
	h.check("and exactly one `prepareFrame` beside it", prepared == 1,
		"%d dispatched in one step" % prepared)
	h.complete(case_name)


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	_clock_cases(h)
	_transition_cases(h, paths)

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	if scene == null:
		print("no preview scene")
		quit(1)
		return
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var started: int = int(preview.call("current_frame"))
	var steps: Array[Dictionary] = []
	for _i in STEPS:
		steps.append(preview.call("_advance"))

	# The whole of §6.1's correction, in one line: the frame a step exits is the
	# frame the step before it was on. Before the reorder every step exited the
	# frame it had just entered, so this compared each frame against itself.
	h.begin("exitFrame runs at the top of the step that leaves the frame")
	var wrong: Array[String] = []
	for k in range(1, steps.size()):
		var exited := int(steps[k]["exited"])
		var previous := int(steps[k - 1]["frame"])
		if exited != previous:
			wrong.append("step %d exited f%d, step %d was on f%d" % [
				k, exited, k - 1, previous
			])
	h.check("every step exits the frame the one before it was on", wrong.is_empty(),
		"; ".join(wrong.slice(0, 4)))

	# The frame a movie *starts* on is not an exception. DAY1's opening frame
	# script `init all` is an `on exitFrame` handler: it puppets channel 30 and
	# 103-110, hides sprites 6, 15 and 33, sets `egozh`/`egozv`/`syz`/`whatodo`
	# and ends with `go("shore2")`. If the first step does not exit frame 0, the
	# room draws with none of that done and the fault reads as missing art.
	h.check("the first step exits the frame the movie opened on",
		int(steps[0]["exited"]) == started,
		"exited f%d, opened on f%d" % [int(steps[0]["exited"]), started])

	var sent: Dictionary = preview.get("_sent")
	# One per step, plus none from the boot sequence, which sends prepareMovie and
	# startMovie and then enters the opening frame.
	h.check("exactly one exitFrame per step", int(sent.get("exitFrame", 0)) == STEPS,
		"%d dispatches over %d steps" % [int(sent.get("exitFrame", 0)), STEPS])
	# **One more than the steps**, and the extra one is the boot's. Entering a frame
	# means `prepareFrame` *and* `enterFrame` — `score.cpp:772-779` and `:827-831`
	# are both in the update that follows `startPlay` — so the opening frame of a
	# movie has one of each, exactly like the frame every step below it enters. This
	# line read `== STEPS` for as long as `preview/boot.gd` sent only the second
	# half of the pair.
	h.check("exactly one prepareFrame per step, and one for the frame the movie opened on",
		int(sent.get("prepareFrame", 0)) == STEPS + 1, str(sent))
	h.complete("exitFrame runs at the top of the step that leaves the frame")

	# `marker()` takes two argument types and answers two different questions,
	# and only one of them used to work.
	#
	# A **number** is playhead-relative and `LINGO_SURFACE.md` §1.5 is emphatic
	# about it, because a port that resolved every `marker()` by name collapsed
	# `strtgame`'s 49 markers onto the first. A **string** is a marker name, and
	# the corpus says so in literals rather than by inference: `marker("mainroom")`
	# 11 times in Piposh 1, plus `marker("doc6")`, `marker("dars6")`,
	# `marker("all6")`, and eight more in Piposh 2 from `marker("stg1go")` to
	# `marker("hezanswer")`. Coerced to 0 they all became "the marker at or before
	# the playhead", which is wherever the movie happened to be parked.
	#
	# What that cost: the ship map hands the player back with `go(marker(nof))`,
	# `nof` being a deck code like "dl1", so choosing a spot on the map returned
	# the player to an unrelated room -- measured, DAY1 -> ROULLETE.dir.
	#
	# Title-agnostic: the name comes out of the movie's own label table, and a
	# marker that is *not* the one the playhead is sitting on is chosen on
	# purpose, because against the current marker both readings agree and the
	# check would pass while broken.
	h.begin("marker() resolves a name by name and a number by position")
	var labels = preview.get("_labels")
	var host_for_marker = preview.get("_host")
	var named := ""
	var named_frame := 0
	if labels != null and host_for_marker != null:
		var here: int = int(preview.call("lingo_marker", 0))
		for key in (labels.labels as Dictionary):
			var frame_of := int((labels.labels as Dictionary)[key])
			# Frame 0 is excluded, and not for tidiness: an unknown name answers
			# 0 too, so a marker sitting on frame 0 makes the check pass whether
			# the lookup worked or not. The assertion has to be able to fail.
			if frame_of > 0 and frame_of != here and str(key).strip_edges() != "":
				named = str(key)
				named_frame = frame_of
				break
	if named == "":
		print("   no marker away from the playhead in this movie; nothing to ask")
	else:
		h.check("a marker name answers that marker's frame",
			int(host_for_marker.call_builtin("marker", [named])) == named_frame,
			"marker(%s) -> %s, label says %d" % [
				JSON.stringify(named),
				str(host_for_marker.call_builtin("marker", [named])), named_frame])
		# The other half, and the one §1.5 warns about: a number must stay
		# playhead-relative rather than being looked up as a name.
		h.check("a number stays playhead-relative",
			int(host_for_marker.call_builtin("marker", [0]))
				== int(preview.call("lingo_marker", 0)),
			"marker(0) -> %s" % str(host_for_marker.call_builtin("marker", [0])))
		# A numeric string is a number, not a name, or every `marker(x)` a script
		# built by concatenation would change meaning.
		h.check("a numeric string is read as a number",
			int(host_for_marker.call_builtin("marker", ["0"]))
				== int(preview.call("lingo_marker", 0)),
			"marker(\"0\") -> %s" % str(host_for_marker.call_builtin("marker", ["0"])))
	h.complete("marker() resolves a name by name and a number by position")

	# Corpus-specific, and skipped rather than guessed at for any other movie.
	var movie := str(preview.call("movie_name")).to_upper()
	if movie.begins_with("DAY1"):
		h.begin("DAY1's opening exitFrame runs and navigates")
		var host = preview.get("_host")
		var reached: Dictionary = host.reached if host != null else {}
		h.check("`init all` reached `go`", int(reached.get("go", 0)) > 0,
			JSON.stringify(reached))
		h.check("the playhead left the opening frame",
			int(steps[0]["frame"]) != started,
			"frame %d" % int(steps[0]["frame"]))
		h.check("channels were puppeted on the way out",
			int(reached.get("puppetsprite", 0)) > 0, JSON.stringify(reached))
		h.complete("DAY1's opening exitFrame runs and navigates")

	_movie_change_enters_once(h, preview)

	# The glue between the decode above and the clock: landing on a frame that
	# names a transition member has to hold the playhead, and let it go again.
	# Reached through `go to movie` because the scene takes its movie from the
	# command line and this run's is already spoken for; the three movies that
	# carry a transition are named here rather than in the engine, which may not
	# know they exist.
	h.begin("landing on a transition frame holds the playhead, then releases it")
	var clock = preview.get("_clock")
	preview.call("lingo_go_movie", "CHESS.dir", 92)
	h.check("the playhead reached the frame with the transition on it",
		int(preview.call("current_frame")) == 91,
		"frame %d of %s" % [int(preview.call("current_frame")), preview.call("movie_name")])
	h.check("it is held, and held for the transition",
		clock.playhead_held() and clock.hold_reason() == "transition", clock.status())
	h.check("`enterFrame` is owed until the transition finishes",
		preview.get("_pending_enter") != null)
	var held := _run_until_free(clock, 3000.0)
	# The member says 600 ms; the hold is rounded up to a whole 1/60 s step.
	h.check("for about as long as the member asks for",
		held >= 600.0 and held < 640.0, "%.1f ms" % held)
	h.complete("landing on a transition frame holds the playhead, then releases it")

	print("")
	print("steps: %s" % JSON.stringify(steps.slice(0, 8)))
	print("clock: %s" % preview.get("_clock").status())
	quit(h.finish("frame event ordering and the movie clock"))
