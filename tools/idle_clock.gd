extends SceneTree
## Director's `idle` event, and the clock a title hangs off it.
##
##   godot --headless --script tools/idle_clock.gd -- --root rating --boot NAVIGATE.dir
##   godot --headless --script tools/idle_clock.gd -- --root piposh2 --boot strtgame.dir
##
## `idle` is the gap between two frames. `score.cpp:336-338` sends it once per
## step from the interactivity block, and `lingo-events.cpp:552` queues it as a
## **movie** handler. The port sent it nowhere at all, which is not a gap a
## renderer test can see: nothing draws differently, no handler errors, and the
## `lingo dispatched` tally simply has no row for it.
##
## What it costs is a whole category of behaviour — anything a title does on a
## clock rather than on a frame. `rating` puts its entire story schedule there.
## `NAVIGATE.dir`, `BLAEGOZ.dir`, `BATZEGOZ.dir` and `HEZSAVE.dir` each carry
##
##     on idle
##       ClockScript()
##     end
##
## and `Panel.cst`'s `ClockScript` advances `GlobalSecond` and `GlobalHour` past
## a `the timer > clockspeed` guard, fires seventeen timed story events out of a
## `case h&s of`, and calls `checkroom` — which steps `TIMEKEEPER` and reads
## `item ITEMKEEPER of line TIMEKEEPER of field "timebasebackup"` to decide where
## the player is sent and which people are where.
##
## So the assertion below is not "an event was dispatched". It is that the
## title's own clock moves, measured on the globals the game reads: `idle` is
## what makes `GlobalSecond` advance, and `GlobalSecond` is what eventually
## reaches `checkroom`. A dispatch count could pass with the handler doing
## nothing; this cannot.
##
## `clockspeed` is set to 0 for the duration so `the timer > clockspeed` is true
## on every step. That is the movie's own global, set by `MAINMENU.dir` to 800
## in play, and driving it from here is the only synthesised thing in the run —
## waiting out 800 ticks per second of game time would take a quarter of an hour.
## It stays under 30 steps because `GlobalSecond = 30` is a `checkroom` boundary
## and `checkroom` can `go to movie`, which is a different subject.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	if preview.get("_score") == null:
		print("no score loaded — pass --root and --boot")
		quit(1)
		return

	var interpreter = preview.get("_interpreter")
	var sent: Dictionary = preview.get("_sent")

	# ------------------------------------------------------- the event is sent
	h.begin("`idle` is sent once per step, to the movie")
	var sent_before := int(sent.get("idle", 0))
	var steps_before := int(sent.get("prepareFrame", 0))
	for i in 4:
		preview.call("_advance")
		await process_frame
	var sent_after := int(sent.get("idle", 0))
	var steps_after := int(sent.get("prepareFrame", 0))
	h.check("`idle` is dispatched at all", sent_after > sent_before,
		"%d -> %d" % [sent_before, sent_after])
	# Against `prepareFrame` rather than against the loop count above, because the
	# frame clock takes steps of its own while this awaits real frames -- so the
	# number of steps is not the number of `_advance` calls, and pinning it to one
	# would be asserting the harness's timing. `prepareFrame` is the other
	# once-per-step event, so the two must move together.
	h.check("once per step, not once per frame script or once per sprite",
		sent_after - sent_before == steps_after - steps_before,
		"%d idle(s) over %d step(s)" % [
			sent_after - sent_before, steps_after - steps_before])
	h.complete("`idle` is sent once per step, to the movie")

	# ------------------------------------------------- and the movie answers it
	#
	# Only where the title has a handler for it. `piposh2`'s single `on idle` is
	# `HEZSAVE/master/MovieScript 209`, whose whole body is `dontPassEvent()`, so
	# a run pinned there asserts the dispatch and stops — which is the honest
	# thing for it to do rather than inventing a clock the title does not have.
	var ran: Dictionary = preview.get("_ran")
	if int(ran.get("idle", 0)) == 0:
		print("  no `on idle` handler in this movie — dispatch asserted, clock not")
		quit(h.finish("Director's `idle` event"))
		return

	h.begin("the movie's `on idle` drives its clock")
	h.check("the movie's `on idle` handler ran", int(ran.get("idle", 0)) > 0,
		"%d run(s)" % int(ran.get("idle", 0)))

	# `the timer > clockspeed` is the guard every tick of this clock passes
	# through. 0 makes it true on every step; the movie sets it to 800.
	interpreter.globals["clockspeed"] = 0
	var seconds_before := int(_num(interpreter.globals.get("globalsecond", 0)))
	var hour_before := int(_num(interpreter.globals.get("globalhour", 0)))
	for i in 12:
		preview.call("_advance")
		await process_frame
	var seconds_after := int(_num(interpreter.globals.get("globalsecond", 0)))

	h.check("`GlobalSecond` advanced, so `ClockScript` ran past its timer guard",
		seconds_after > seconds_before,
		"GlobalSecond %d -> %d over 12 step(s)" % [seconds_before, seconds_after])
	h.check("it advanced by steps rather than jumping the whole hour",
		seconds_after - seconds_before <= 12,
		"+%d" % (seconds_after - seconds_before))
	h.check("`GlobalHour` did not roll over before 60 seconds",
		int(_num(interpreter.globals.get("globalhour", 0))) == hour_before,
		"GlobalHour %d -> %s" % [hour_before, str(interpreter.globals.get("globalhour", 0))])

	# The field the HUD reads. `ClockScript` writes `h & ":" & s` into it every
	# tick, so a clock that moves and a clock the player can see are the same
	# question only if this moved too.
	var shown := str(preview.call("lingo_field", "GlobalTime", "panel.cst")).strip_edges()
	h.check("the on-screen clock field was written", shown.contains(":"),
		"field GlobalTime = '%s'" % shown)
	h.complete("the movie's `on idle` drives its clock")

	quit(h.finish("Director's `idle` event"))


static func _num(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return int(str(value).to_int())
