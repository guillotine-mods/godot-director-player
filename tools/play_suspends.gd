extends SceneTree
## `play` and `go` suspend the handler that called them, and something resumes it.
##
##   godot --headless --path . --script tools/play_suspends.gd
##   godot --headless --path . --script tools/play_suspends.gd -- \
##       --dialogue --root rating --file BATZEGOZ.dir --marker Egoz1 --channel 11
##
## Director does not run the rest of a handler that calls `play` or `go`
## (`DIRECTOR_ENGINE.md` §6.1 step 18, §9.4). It stashes the running handler and
## requeues it: a `go` resumes once the frame it chose has been entered, a `play`
## resumes at `play done`. The port ran the tail at the call, so Rating's dialogue
## idiom
##
##     sound playFile 1, soundspath & "egoz1.aif"
##     play frame "egozspeak1"
##     go("batz2a")
##
## overwrote the branch `play` had just set: the talking loop was skipped and the
## line of speech stopped a frame after it started.
##
## **This harness exists because the half-fix is worse than the bug.** Suspending
## without resuming loses the trailing `go` entirely, `play done` returns to the
## dialog frame, and the conversation cannot be left. So every check below comes
## in a pair — what did *not* run at the call, and what *did* run at the resume —
## and neither half passes alone.
##
## Two parts, and the split is deliberate:
##
##   - **the interpreter, against a stub host.** Title-agnostic and exact: the
##     five shapes a suspension has to unwind through (statement tail, `if`,
##     `repeat`, a called handler, and a `play` that is the last statement of its
##     handler) with the resumed statements named. The last of those five is the
##     regression surface — 166 of Rating's 1,239 `play` sites and 48 of Piposh
##     2's 183 are the final statement of their handler, and suspending must
##     leave them doing exactly what they did before.
##   - **the player.** That the frozen queue *drains*: a room holding on
##     `go to the frame` freezes a handler every single step, and one that is not
##     resumed is a handler the movie is waiting on for ever. This is the
##     invariant `movie_churn` and `playhead_escape` would only catch after the
##     movie had already stopped.
##
## `--dialogue` drives the real thing, which needs Rating and so is not in the
## gate: it clicks a dialogue option, watches the playhead reach the talking
## loop, holds there until the sound ends, and asserts it then follows the
## trailing `go` rather than the score's own next marker.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")

## Every shape a suspension has to unwind through, in one script so that the
## compiler and the interpreter see them the way a cast does.
const SOURCE := """
on tailonly
  note("before")
  play frame "x"
end

on trailing
  note("before")
  play frame "x"
  note("after")
end

on nested
  if 1 = 1 then
    note("before")
    play frame "x"
  end if
  note("after")
end

on looped
  repeat with i = 1 to 2
    play frame "x"
    note("body" & i)
  end repeat
  note("done")
end

on callee
  play frame "x"
  note("callee-tail")
end

on caller
  callee()
  note("caller-tail")
end

on gofreeze
  go("somewhere")
  note("after-go")
end
"""


## The smallest host that can freeze: it records what ran and asks for the
## suspension the two verbs ask for. No `park_lingo_state`, so the interpreter
## keeps the chains itself — which is also the check that it still can.
class StubHost:
	extends RefCounted

	var notes: Array[String] = []
	var request := ""

	func call_builtin(name: String, args: Array) -> Variant:
		match name.to_lower():
			"note":
				notes.append(str(args[0]) if not args.is_empty() else "")
				return 0
			"play":
				if not args.is_empty() and str(args[0]).to_lower() == "done":
					return 0
				request = "play"
				return 0
			"go":
				request = "go"
				return 0
		return null

	func take_suspend_request() -> String:
		var kind := request
		request = ""
		return kind


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	_interpreter_checks(h)
	if Args.flag(args, "dialogue"):
		await _dialogue_check(h, args)
	else:
		await _drain_check(h, args)
	quit(h.finish("play and go suspend their handler, and it is resumed"))


# ------------------------------------------------------------ the interpreter


func _interpreter_checks(h: Harness) -> void:
	var compiler := Compiler.new()
	var ast := compiler.compile_source(SOURCE, "MovieScript 1")
	h.begin("the shapes compile")
	if not h.check("the suspension fixtures compile", not ast.is_empty(), compiler.error):
		return
	h.complete("the shapes compile")

	# `play` as the last statement of its handler: the population that must not
	# move. 166 sites in Rating, 48 in Piposh 2 (`tools/suspend_survey.gd`).
	h.begin("a tail play changes nothing")
	var tail := _run(ast, "tailonly")
	h.check("a `play` with nothing after it runs the same statements",
		str(tail[0].notes) == '["before"]', str(tail[0].notes))
	_drain(tail[1], tail[0])
	h.check("and resuming it adds none",
		str(tail[0].notes) == '["before"]', str(tail[0].notes))
	h.complete("a tail play changes nothing")

	h.begin("a trailing statement is deferred, not dropped")
	var run := _run(ast, "trailing")
	h.check("the statement after `play frame` does not run at the call",
		str(run[0].notes) == '["before"]', str(run[0].notes))
	h.check("and the handler is parked rather than finished",
		run[1].has_frozen_state() == false and run[1].requeue_play_state(),
		"nothing was parked in the play buffer")
	run[1].thaw()
	h.check("`play done` runs it",
		str(run[0].notes) == '["before", "after"]', str(run[0].notes))
	h.complete("a trailing statement is deferred, not dropped")

	h.begin("the suspend unwinds out of an if")
	var branch := _run(ast, "nested")
	h.check("the statement after the `end if` does not run at the call",
		str(branch[0].notes) == '["before"]', str(branch[0].notes))
	_drain(branch[1], branch[0])
	h.check("and does run on the resume",
		str(branch[0].notes) == '["before", "after"]', str(branch[0].notes))
	h.complete("the suspend unwinds out of an if")

	h.begin("a repeat carries on from where it stopped")
	var loop := _run(ast, "looped")
	h.check("no pass of the body completes at the call",
		str(loop[0].notes) == "[]", str(loop[0].notes))
	_drain(loop[1], loop[0])
	# Two passes and then the statement after the loop: the counter has to survive
	# the join, or the loop restarts and `body1` appears twice.
	h.check("both passes and the statement after the loop run, in order",
		str(loop[0].notes) == '["body1", "body2", "done"]', str(loop[0].notes))
	h.complete("a repeat carries on from where it stopped")

	h.begin("the suspend unwinds out of a called handler")
	var nestedcall := _run(ast, "caller")
	h.check("neither the callee's tail nor the caller's runs at the call",
		str(nestedcall[0].notes) == "[]", str(nestedcall[0].notes))
	_drain(nestedcall[1], nestedcall[0])
	h.check("both run on the resume, callee first",
		str(nestedcall[0].notes) == '["callee-tail", "caller-tail"]',
		str(nestedcall[0].notes))
	h.complete("the suspend unwinds out of a called handler")

	# `go` freezes into the ordinary queue, not the play buffer: it is resumed by
	# the next frame rather than by `play done`, and putting it in the wrong
	# buffer is a handler that waits for a `play done` that will never come.
	h.begin("go freezes into the frame queue")
	var jump := _run(ast, "gofreeze")
	h.check("the statement after `go` does not run at the call",
		str(jump[0].notes) == "[]", str(jump[0].notes))
	h.check("and it is queued for the next frame, not for `play done`",
		jump[1].has_frozen_state() and not jump[1].requeue_play_state(),
		"nothing in the frame queue")
	jump[1].thaw()
	h.check("entering the next frame runs it",
		str(jump[0].notes) == '["after-go"]', str(jump[0].notes))
	h.complete("go freezes into the frame queue")


## `[host, interpreter]` after one dispatch of `name`.
func _run(ast: Dictionary, name: String) -> Array:
	var host := StubHost.new()
	var interpreter = Interpreter.new(host)
	interpreter.load_bundle({"movie": "T", "cast": "t", "scripts": {"MovieScript 1": ast}})
	interpreter.call_handler(name)
	return [host, interpreter]


## Requeue and thaw until nothing more is waiting, the way the frame loop does
## one step at a time. Bounded, because a chain that re-freezes for ever is the
## hang this whole mechanism exists to avoid and a harness must not reproduce it.
func _drain(interpreter, _host) -> void:
	for _i in 16:
		interpreter.requeue_play_state()
		if not interpreter.thaw():
			return


# ---------------------------------------------------------------- the player


## Nothing may be left parked once the movie has settled.
##
## Every room in both corpora holds on `go to the frame`, which freezes a handler
## on every single step; a queue that grows instead of draining is a movie whose
## handlers are all waiting on a resume nobody sends. The count is read at rest
## rather than sampled mid-step, because one parked handler *is* the normal state
## between a `go` and the frame it chose.
func _drain_check(h: Harness, args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	# A handler of our own, loaded into the movie now playing and dispatched
	# through the real host. Written rather than found, because *which* corpus is
	# pinned decides whether a real one is reachable: 900 steps of either title's
	# boot movie reach `go` at most once -- both open on a run of tempo delays --
	# so a check that waits for the score to freeze something passes over an empty
	# set, which is the failure `gate.sh`'s own zero-check guard exists for.
	h.begin("the player suspends and resumes a real handler")
	var compiler := Compiler.new()
	var probe := compiler.compile_source("""
on suspendprobe
  global gsuspendprobe
  put "before" into gsuspendprobe
  go to the frame
  put "after" into gsuspendprobe
end
""", "MovieScript 9001")
	if not h.check("the probe compiles", not probe.is_empty(), compiler.error):
		return
	var interpreter = preview.get("_interpreter")
	interpreter.load_bundle(
		{"movie": "PROBE", "cast": "probe", "scripts": {"MovieScript 9001": probe}})
	interpreter.call_handler("suspendprobe")

	h.check("`go to the frame` stops the handler where it stands",
		str(interpreter.globals.get("gsuspendprobe", "")) == "before",
		str(interpreter.globals.get("gsuspendprobe", "<unset>")))
	h.check("and the handler is parked on the preview, not lost",
		(preview.get("_frozen_lingo") as Array).size() == 1,
		"%d parked" % (preview.get("_frozen_lingo") as Array).size())
	# Two frames: the step that enters the frame the `go` chose, and the thaw at
	# the end of it (§6.1 step 18).
	for i in 4:
		await process_frame
	h.check("the next step runs the rest of it",
		str(interpreter.globals.get("gsuspendprobe", "")) == "after",
		str(interpreter.globals.get("gsuspendprobe", "<unset>")))
	h.check("and the queue is empty again",
		(preview.get("_frozen_lingo") as Array).is_empty(),
		"%d still parked" % (preview.get("_frozen_lingo") as Array).size())
	h.complete("the player suspends and resumes a real handler")

	# Then the movie itself, for as long as the caller cares to watch: whatever
	# the score freezes has to drain too, or the room is waiting on a resume
	# nobody sends. This is what `movie_churn` and `playhead_escape` would only
	# catch after the movie had already stopped.
	var label := Args.text(args, "label", "")
	if label != "":
		var labels = preview.get("_labels")
		preview.set("_index", int(labels.labels.get(label.to_lower(), 0)))
		for i in 8:
			await process_frame
	var steps := Args.number(args, "steps", 600)
	var worst := 0
	for i in steps:
		await process_frame
		worst = maxi(worst, (preview.get("_frozen_lingo") as Array).size())

	h.begin("the frozen queue drains")
	var parked: Array = preview.get("_frozen_lingo")
	h.check("no handler is left parked once the movie is at rest",
		parked.is_empty(), "%d still parked" % parked.size())
	# The cap is 8 and the request is declined above it, so a run that comes near
	# it is one where handlers are about to stop being suspended at all -- the old
	# behaviour creeping back without anything failing.
	h.check("the queue never came near its cap", worst <= 2,
		"peaked at %d over %d parked in all" % [worst, int(preview.get("_frozen_parked"))])
	h.check("nothing is waiting on a `play done` that will not come",
		(preview.get("_frozen_play") as Array).is_empty(),
		"a handler is parked in the play buffer")
	h.complete("the frozen queue drains")

	await _play_off_the_end(h, preview, compiler)

	# The riskiest path in the whole design, and the reason the chains are held by
	# the preview rather than by the interpreter: `go to movie` builds a *new*
	# interpreter inside the very call that froze the handler, so a chain the
	# interpreter owned would be destroyed by the statement that created it. The
	# destination is the movie already playing, which keeps this title-agnostic
	# and still replaces the object.
	h.begin("a handler frozen by `go to movie` outlives the interpreter")
	var hop := compiler.compile_source("""
on suspendhop
  global gsuspendhop
  put "before" into gsuspendhop
  go to movie "%s"
  put "after" into gsuspendhop
end
""" % str(preview.call("movie_name")), "MovieScript 9002")
	if not h.check("the movie-hop probe compiles", not hop.is_empty(), compiler.error):
		return
	var before = preview.get("_interpreter")
	before.load_bundle(
		{"movie": "PROBE", "cast": "probe", "scripts": {"MovieScript 9002": hop}})
	before.call_handler("suspendhop")
	var after = preview.get("_interpreter")
	h.check("the movie change did replace the interpreter", after != before,
		"the same object came back, so this proves nothing")
	for i in 6:
		await process_frame
	h.check("and the rest of the handler still ran",
		str(after.globals.get("gsuspendhop", "")) == "after",
		str(after.globals.get("gsuspendhop", "<unset>")))
	h.complete("a handler frozen by `go to movie` outlives the interpreter")


# -------------------------------------------------------------- the real thing


## The reported bug, end to end: click a dialogue option and follow the playhead.
##
## Three things have to be true together, and each one alone is a state the bug
## also produces: the talking loop is *entered*, it is *held* for the length of
## the line, and the handler's trailing `go` is what leaves it.
func _dialogue_check(h: Harness, args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var labels = preview.get("_labels")
	_check_marker_index(h, preview, labels)

	var speak := Args.text(args, "speak", "egozspeak1").to_lower()
	var destination := Args.text(args, "destination", "batz2a").to_lower()
	var start := int(labels.labels.get(Args.text(args, "marker", "Egoz1").to_lower(), 0))
	preview.set("_index", start)
	for i in 4:
		await process_frame
	preview.set("_paused", true)

	var channel := Args.number(args, "channel", 11)
	var at := _centre_of(preview, channel)
	preview.call("route_press", at)
	preview.call("route_release", at)
	preview.set("_paused", false)

	var speak_frame := int(labels.labels.get(speak, -1))
	var want := int(labels.labels.get(destination, -1))
	var inside := 0
	var reached_speak := false
	var reached_destination := false
	for i in Args.number(args, "ticks", 900):
		await process_frame
		var now := int(preview.call("current_frame"))
		if str(labels.marker_at(now)).to_lower() == speak:
			reached_speak = true
			inside += 1
		if reached_speak and now >= want and str(labels.marker_at(now)).to_lower() == destination:
			reached_destination = true
			break

	h.begin("the dialogue plays its line and then leaves")
	# The details say what happened rather than what should have: `Harness.check`
	# prints them either way, and "never reached X" beside an `ok` reads as a
	# contradiction.
	h.check("the click enters the talking loop rather than skipping it",
		reached_speak, "%s at frame %d %s" % [
			speak, speak_frame, "entered" if reached_speak else "NEVER ENTERED"])
	# 40 samples is several seconds of speech at any tempo in either corpus; the
	# bug produced one or two, which is the "very quick" in the report.
	h.check("and holds there for the length of the line",
		inside > 40, "%d samples inside %s" % [inside, speak])
	h.check("the handler's trailing `go` is what leaves it",
		reached_destination, "%s %s" % [
			destination, "reached" if reached_destination else "NEVER REACHED"])
	h.check("and nothing is left parked afterwards",
		(preview.get("_frozen_play") as Array).is_empty()
			and (preview.get("_play_stack") as Array).is_empty(),
		"play buffer %d, play stack %d" % [
			(preview.get("_frozen_play") as Array).size(),
			(preview.get("_play_stack") as Array).size()])
	h.complete("the dialogue plays its line and then leaves")


## The *other* return from an interlude: the one nobody writes `play done` for.
##
## `score.cpp:462-487` pops the movie stack when the playhead runs off the end of a
## score, ahead of the wrap back to frame 1, and requeues the parked play state on
## the way past (`:474-476`). That path exists precisely so a cut scene which simply
## *ends* still hands control back — and a port with only the `play done` half has a
## handler parked in the play buffer with nothing left in the engine that can wake
## it. `ENGINE_TODO.md` carried it as the first of the three residues of the
## suspension mechanism, and it is the same shape of hang as the one that made
## Piposh Dream's save screen unusable.
##
## **Why the case cannot be found in a movie and has to be built.** An interlude
## that runs off the end of its score is authored, not incidental, and neither
## corpus reaches one under a headless drive inside a bounded number of steps: every
## room holds itself with `go to the frame`, so the playhead never arrives at the
## last frame on its own. So the handler is compiled here — like `suspendprobe`
## above — and pointed at the last frame of whatever movie is loaded, which keeps it
## title-agnostic.
##
## **What it would fail on.** The three states the bug produces, each asserted
## separately because each one alone is also a state a *different* mistake produces:
## the tail of the caller never runs (the parked handler was never requeued); the
## play stack is still occupied (the pop never happened); and the playhead is
## somewhere other than where `play` was issued (it wrapped to frame 0 and started
## the movie again, which is the pre-fix behaviour exactly).
func _play_off_the_end(h: Harness, preview: Node, compiler) -> void:
	var case_name := "an interlude that runs off the end of its score returns to its caller"
	h.begin(case_name)
	var score = preview.get("_score")
	var last := int(score.frame_count)
	var probe: Dictionary = compiler.compile_source("""
on playoffend
  global gplayoffend
  put "before" into gplayoffend
  play frame %d
  put "after" into gplayoffend
end
""" % last, "MovieScript 9003")
	if not h.check("the off-the-end probe compiles", not probe.is_empty(), compiler.error):
		h.complete(case_name)
		return
	var interpreter = preview.get("_interpreter")
	interpreter.load_bundle(
		{"movie": "PROBE", "cast": "probe", "scripts": {"MovieScript 9003": probe}})

	# The debug pause, so the only thing moving the playhead is this function's own
	# `_advance` calls: a real tick would spend the score's tempo on frames that have
	# nothing to do with the question.
	preview.set("_paused", true)
	await process_frame
	var from := int(preview.call("current_frame"))
	interpreter.call_handler("playoffend")

	h.check("`play frame` stops the caller where it stands",
		str(interpreter.globals.get("gplayoffend", "")) == "before",
		str(interpreter.globals.get("gplayoffend", "<unset>")))
	h.check("the caller is parked in the play buffer",
		not (preview.get("_frozen_play") as Array).is_empty(),
		"nothing parked; the play stack holds %d" % (preview.get("_play_stack") as Array).size())
	h.check("and the playhead went to the last frame of the score",
		int(preview.call("current_frame")) == last - 1,
		"frame %d of %d" % [int(preview.call("current_frame")), last - 1])

	# Two steps. The first consumes the queued jump — a `go` of any form sends no
	# `exitFrame` for the frame it is leaving — and enters the last frame; the second
	# is the one that advances past the end.
	preview.call("_advance")
	await process_frame

	# **The last frame's own `exitFrame` is silenced for the step that wraps, and
	# that is isolation rather than convenience.** Measured: `strtgame.dir`'s frame
	# 1374 carries a script that jumps to 1347, so the playhead never reaches the end
	# and the case cannot be asked at all — a harness that stopped there would be
	# green in every movie whose final frame happens to navigate, which is most of
	# them, while never once exercising the wrap. `_exit_frame_called` is Director's
	# own "this frame has already been exited" latch (`score.cpp:672`) and is
	# reachable in play — it is what a frame resumed after a `pause` stands in — so
	# raising it here asks the engine a question it can answer rather than one about
	# whichever script the score happens to hang off its last frame.
	preview.set("_exit_frame_called", true)
	preview.call("_advance")
	await process_frame
	preview.set("_paused", false)

	h.check("the play stack is popped rather than the score wrapping to frame 0",
		(preview.get("_play_stack") as Array).is_empty(),
		"%d entry(s) still on the stack, playhead on %d" % [
			(preview.get("_play_stack") as Array).size(),
			int(preview.call("current_frame"))])
	h.check("the playhead is back where `play` was issued",
		int(preview.call("current_frame")) == from,
		"frame %d, `play` was issued from %d" % [int(preview.call("current_frame")), from])
	h.check("nothing is left parked in the play buffer",
		(preview.get("_frozen_play") as Array).is_empty(),
		"a handler is still waiting for a `play done` that will never come")
	h.check("and the statement after `play frame` ran",
		str(interpreter.globals.get("gplayoffend", "")) == "after",
		str(interpreter.globals.get("gplayoffend", "<unset>")))
	h.complete(case_name)


func _centre_of(preview: Node, channel: int) -> Vector2:
	var score = preview.get("_score")
	var sprites: Array = score.frame(int(preview.call("current_frame"))).get("sprites", [])
	for sprite in sprites:
		var effective: Dictionary = preview.call("_effective", sprite)
		if not effective.is_empty() and int(effective["channel"]) == channel:
			return (preview.call("_sprite_rect", effective) as Rect2).get_center()
	return Vector2.ZERO


## The dialogue below cannot leave its talking loop unless `marker(n)` counts the
## way Director counts, so the marker index is a precondition of the case and is
## asserted as one: the movie's own `VWLB` header declares how many entries it
## has, and the reader must have kept that many.
##
## **This used to repair the array instead of checking it**, and that is the
## failure this docstring exists to prevent a second time. `director_labels.gd`
## dropped every entry with an empty name; BATZEGOZ's `play done` sits on an
## unnamed marker between `egozspeak1` and `Batz2A`, so `go(marker(1))` counted
## past it, `play done` never ran, the parked handler was never resumed, and all
## three dialogue options arrived at the first one's destination. This function
## re-parsed the chunk and put the entries back before asserting anything — with a
## docstring conceding it and a `NOTE:` printed at runtime — so the case passed
## against an array the player never gets, and it kept passing after commit
## 641d1d47's fix turned out to be inert. A harness that repairs its own subject
## reports on a movie that does not exist.
##
## Checking costs the same and fails instead, which is the only difference that
## matters. `tools/label_index.gd` makes the same assertion over every container
## in every root; this one keeps it beside the behaviour that depends on it, so a
## regression here says *why* the dialogue broke rather than only that it did.
func _check_marker_index(h: Harness, preview: Node, labels) -> void:
	var container = preview.get("_movie")
	var ids: Array = container.ids_of("VWLB")
	if not h.check("the movie has a marker table", not ids.is_empty()):
		return
	var payload: PackedByteArray = container.read_chunk(ids[0])
	if not h.check("its marker table is readable", payload.size() >= 2,
			"%d byte(s)" % payload.size()):
		return
	# Big-endian, like `DirectorLabels._u16`: `read_chunk` hands back the payload
	# untouched, and `VWLB`'s u16s are big-endian even inside a little-endian XFIR
	# container.
	var declared := (payload[0] << 8) | payload[1]
	var unnamed := 0
	for marker in labels.markers:
		if str(marker["name"]) == "":
			unnamed += 1
	h.check("`marker(n)` counts every entry the chunk declares, named or not",
		labels.markers.size() == declared,
		"chunk declares %d, reader kept %d, %d unnamed" % [
			declared, labels.markers.size(), unnamed])
