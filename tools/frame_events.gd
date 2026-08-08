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
	# One per step, plus none from the boot sequence, which sends prepareMovie,
	# startMovie and enterFrame only.
	h.check("exactly one exitFrame per step", int(sent.get("exitFrame", 0)) == STEPS,
		"%d dispatches over %d steps" % [int(sent.get("exitFrame", 0)), STEPS])
	h.check("exactly one prepareFrame per step",
		int(sent.get("prepareFrame", 0)) == STEPS, str(sent))
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
