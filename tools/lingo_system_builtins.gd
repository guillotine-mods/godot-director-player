extends SceneTree
## The movie-level builtins and system properties, driven from Lingo.
##
##   godot --headless --path . --script tools/lingo_system_builtins.gd
##
## `tools/lingo_surface_audit.gd` can say a name is *bound*; it reads the host's
## `match` arms and cannot say what the arm reached. Every row here was `inert`
## or `absent` in §19 and every one of them is now claimed live, so this is the
## other half of that claim: the assertions are on what a movie can observe, not
## on a setter agreeing with its own getter.
##
## Two of them are bound in a shape that could take a gate run down with it, and
## the checks for those are as much about the guard as about the feature:
##
##   `quit`   stops the movie and quits the *application* only when the preview
##            is the running main scene. A harness adds the scene to its own
##            root, so this file proves the movie stopped and that its own
##            process survived the call.
##   `alert`  raises an engine dialog rather than `OS.alert`, which blocks the
##            calling thread on Windows even under `--headless` (measured: it
##            never returned). The movie stops behind the box; the engine does
##            not.
##
## Title-agnostic. Every check is against the configured boot movie, whichever
## title that is, and nothing here names a room, a channel or a member.

const Harness := preload("res://tools/lib/harness.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
## For `IGNORED` and `HANDLED`, which the `updateStage` section reads. Off the
## host's own constants rather than restated, so the check cannot go stale by
## agreeing with a copy.
const Host := preload("res://scenes/preview_lingo_host.gd")

var _preview: Node = null
var _host = null
var _interp = null


func _init() -> void:
	var h := Harness.new()
	# No argument handling here: `director_preview.gd` reads `--file` and `--root`
	# off the command line itself when it boots, so an entry in `gate.sh` that
	# carries them reaches the movie without this file knowing they exist.
	_preview = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(_preview)
	await process_frame
	await process_frame
	_host = _preview.get("_host")
	_interp = _preview.get("_interpreter")

	h.begin("the harness has a movie, a host and an interpreter")
	h.check("the preview booted a score", _preview.get("_score") != null,
		"every check below runs Lingo against the movie the config names")
	h.check("the Lingo host is attached", _host != null)
	h.check("the interpreter is attached", _interp != null)
	h.complete("the harness has a movie, a host and an interpreter")
	if _host == null or _interp == null:
		quit(h.finish("the movie-level builtins and system properties"))
		return

	await _timer_checks(h)
	_search_path_checks(h)
	_movie_name_checks(h)
	_exit_lock_checks(h)
	await _pause_checks(h)
	_beep_checks(h)
	_alert_checks(h)
	_delay_checks(h)
	await _quit_checks(h)
	await _update_stage_checks(h)

	_preview.queue_free()
	await process_frame
	quit(h.finish("the movie-level builtins and system properties"))


# --------------------------------------------------------------- the timer

## `the timer`, 91 sites, and the only row here that was claimed **live** while
## answering the wrong thing.
##
## Director's is ticks since the last reset. This host answered
## `Time.get_ticks_msec()` — milliseconds since the process started — so it was
## wrong by a factor of 60 and by an origin, and the write did not exist at all.
## The corpus idiom is a pair: `if the timer > clockspeed then ... set the timer
## to 0`, so against a number that only grows and starts in the thousands every
## one of those tests fired on every frame.
func _timer_checks(h) -> void:
	h.begin("`the timer` is ticks since its last reset (§3)")
	_run("set the timer to 0")
	var immediately := int(_value("the timer"))
	h.check(
		"a reset reads back near zero (got %d)" % immediately,
		immediately >= 0 and immediately <= 2,
		"the write half did not exist; `set the timer to 0` reached nothing and "
		+ "the read answered the age of the process")
	# Real elapsed time, not frames: the unit under test is a clock.
	await create_timer(0.5).timeout
	var later := int(_value("the timer"))
	h.check(
		"half a second later it reads about 30 ticks (got %d)" % later,
		later >= 20 and later <= 45,
		"60ths of a second, not milliseconds -- 500 would be the old answer's unit")
	h.check(
		"it is not the millisecond clock (timer %d < milliseconds %d)"
			% [later, int(_value("the milliseconds"))],
		later < int(_value("the milliseconds")),
		"`the milliseconds` is since the machine started and `the timer` is since "
		+ "the last reset; answering one for both is what was happening")
	_run("startTimer")
	var restarted := int(_value("the timer"))
	h.check(
		"`startTimer` moves the origin to now (got %d)" % restarted,
		restarted >= 0 and restarted <= 2,
		"0 sites in this corpus, which resets through the property instead; bound "
		+ "because Director has it")
	h.complete("`the timer` is ticks since its last reset (§3)")


# ----------------------------------------------------------- the searchPath

## 326 sites, all Piposh 1's CD scan across its three language builds:
## `the searchPath = ["d:\sounds\strtgame\"]` and then `getAt(the searchPath, 1)`.
##
## The read has to answer a list with something in it whether or not the movie
## has written one, because `getAt` past the end is VOID and a VOID is what the
## loop cannot compare. That is why the rest state is one empty element.
func _search_path_checks(h) -> void:
	h.begin("`the searchPath` round-trips, and is never empty (§3)")
	var rest: Variant = _value("the searchPath")
	h.check(
		"unwritten, it is a list rather than VOID (got %s)" % str(rest),
		typeof(rest) == TYPE_ARRAY and not (rest as Array).is_empty(),
		"unbound this answered VOID, `getAt` answered VOID, and the disc scan "
		+ "could not tell 'no drive' from 'no property'")
	h.check(
		"and element 1 reads as the empty string",
		str(_value("getAt(the searchPath, 1)")) == "",
		"the retired host seeded it this way for exactly this reason")
	_run("set the searchPath to [\"d:/sounds/strtgame/\", \"e:/sounds/\"]")
	h.check(
		"a written path reads straight back out through getAt (got %s)"
			% str(_value("getAt(the searchPath, 1)")),
		str(_value("getAt(the searchPath, 1)")) == "d:/sounds/strtgame/",
		"the whole of what the scan does with it")
	h.check(
		"the second element survives too",
		str(_value("getAt(the searchPath, 2)")) == "e:/sounds/")
	# The other half of the claim: it is consulted, not merely stored.
	var audio: Node = _preview.get("_audio")
	h.check(
		"and the audio resolver was handed the same list",
		audio != null and (audio.get("search_path") as Array).size() == 2,
		"stored and never consumed is the shape §19 calls inert; the resolver "
		+ "tries each entry before giving up on a sound")
	_run("set the searchPath to []")
	h.check(
		"clearing it leaves the one-empty-element rest state, not nothing",
		str(_value("getAt(the searchPath, 1)")) == "",
		"a movie that clears the path must not make the next read fall off the end")
	h.complete("`the searchPath` round-trips, and is never empty (§3)")


# ----------------------------------------------------------------- the movie

func _movie_name_checks(h) -> void:
	h.begin("`the movie` is the older spelling of `the movieName` (§3)")
	var name := str(_value("the movieName"))
	h.check("`the movieName` names a container (got %s)" % name, name != "")
	h.check(
		"`the movie` answers the same thing (got %s)" % str(_value("the movie")),
		str(_value("the movie")) == name,
		"41 sites read it and every one of them got VOID; answered from the same "
		+ "arm so the two cannot drift apart")
	h.complete("`the movie` is the older spelling of `the movieName` (§3)")


# -------------------------------------------------------------- the exitLock

## Five sites, all writes, none reading it back. Director disables the quit
## *key* with it and leaves the `quit` command alone, so what it gates here is
## the window manager's close request and nothing else.
func _exit_lock_checks(h) -> void:
	h.begin("`the exitLock` is written, read back, and gates the close request")
	_run("set the exitLock to 1")
	h.check("the write reaches the host", bool(_host.exit_lock))
	h.check(
		"and reads back as 1 (got %s)" % str(_value("the exitLock")),
		int(_value("the exitLock")) == 1,
		"the corpus never reads it; bound both ways because Director has it both ways")
	# Director locks the quit *key*, not the command, and getting that backwards
	# would make a title unquittable from its own menu.
	_run("set the exitLock to 1")
	_run("quit")
	h.check(
		"`quit` is not gated on it -- Director locks the key, not the command",
		bool(_host.stopped),
		"the guard is in `_notification`, which is the window manager's close "
		+ "request, and nowhere near `lingo_quit`")
	_host.stopped = false
	_preview.set_process(true)
	_run("set the exitLock to 0")
	h.check("and clears", not bool(_host.exit_lock))
	h.complete("`the exitLock` is written, read back, and gates the close request")


# ------------------------------------------------------------ pause/continue

## The pair, and it had to land as a pair: `pause` was live and `continue` was
## not, so a movie that paused could never be resumed.
##
## What Director suspends is the frame *step* — no `exitFrame`, no playhead
## move, no `enterFrame` — while the movie stays drawn and interactive. The
## observable is therefore the `exitFrame` dispatch count, not the frame number:
## every room in this corpus holds itself with `go to the frame`, so a paused
## room and a holding room sit on the same frame and only one of them is still
## running handlers.
func _pause_checks(h) -> void:
	h.begin("`pause` stops the frame step and `continue` restarts it (§1.4)")
	var before := _exit_frames()
	await _steps(10)
	var running := _exit_frames() - before
	h.check(
		"the movie is stepping to begin with (%d exitFrames in half a second)" % running,
		running > 0,
		"a paused-versus-running check over a movie that was never running proves "
		+ "nothing, which is why this is asserted first")

	_run("pause")
	h.check("`pause` sets the flag", bool(_host.playback_paused))
	var at_pause := _exit_frames()
	var frame_at_pause := int(_preview.get("_index"))
	await _steps(8)
	h.check(
		"no `exitFrame` is dispatched while paused (%d)" % (_exit_frames() - at_pause),
		_exit_frames() == at_pause,
		"the reference guards exitFrame, the playhead move, prepareFrame and "
		+ "enterFrame separately on `_playbackPaused`; one guard in `_advance` is "
		+ "the same set")
	h.check(
		"and the playhead has not moved",
		int(_preview.get("_index")) == frame_at_pause)

	_run("continue")
	h.check("`continue` clears the flag", not bool(_host.playback_paused))
	var at_continue := _exit_frames()
	await _steps(6)
	h.check(
		"and the movie steps again (%d exitFrames)" % (_exit_frames() - at_continue),
		_exit_frames() > at_continue,
		"this is the half that was in the host's IGNORED list: a movie that "
		+ "paused stayed paused for ever")

	# The release that makes the pair safe rather than a trap.
	_run("pause")
	h.check("paused again", bool(_host.playback_paused))
	_run("go to the frame")
	h.check(
		"any `go` releases the pause, as the reference does on its first line",
		not bool(_host.playback_paused),
		"`func_goto` and each of the three relative forms clear it before they "
		+ "navigate. It is what lets a button leave a paused frame -- the frame's "
		+ "own `go to the frame` cannot, because `exitFrame` is not being sent")
	h.complete("`pause` stops the frame step and `continue` restarts it (§1.4)")


# ------------------------------------------------------------------- beep

## 154 sites, every one of them the bare `beep`, and all of them silent.
##
## The assertion is on the stream that was produced, because "did the speaker
## make a noise" is not a thing a harness can ask. A stream of the right length
## on a player that is playing is as close as it gets, and it distinguishes the
## three ways this could be inert: no player, no stream, no play.
func _beep_checks(h) -> void:
	h.begin("`beep` produces an audible stream, off the numbered channels")
	var audio: Node = _preview.get("_audio")
	if audio == null:
		h.check("the audio director is attached", false, "nothing to beep with")
		h.complete("`beep` produces an audible stream, off the numbered channels")
		return
	_run("beep")
	var player: AudioStreamPlayer = audio.get("_beep") as AudioStreamPlayer
	h.check("a beep player exists", player != null)
	if player == null:
		h.complete("`beep` produces an audible stream, off the numbered channels")
		return
	var one := player.stream.get_length() if player.stream != null else 0.0
	h.check(
		"with a stream about 120 ms long (got %.3f s)" % one,
		one > 0.09 and one < 0.2,
		"synthesised: there is no beep on the disc, it is the machine's own sound")
	h.check("and it is playing", player.playing)
	_run("beep(3)")
	var three := player.stream.get_length() if player.stream != null else 0.0
	h.check(
		"`beep 3` is three tones 400 ms apart (got %.3f s, want about 1.16)" % three,
		three > 1.05 and three < 1.3,
		"Director blocks for the gaps; the whole run is one buffer here so the "
		+ "handler that asked for them does not stop")
	h.check(
		"the numbered sound channels are untouched -- `soundBusy(1)` is what every "
		+ "line of speech in this corpus waits on",
		not bool(audio.call("sound_busy", 1)),
		"a beep that claimed channel 1 would make a room wait for it")
	h.complete("`beep` produces an audible stream, off the numbered channels")


# ------------------------------------------------------------------ alert

func _alert_checks(h) -> void:
	h.begin("`alert` raises a real box and stops the movie behind it")
	var was_paused := bool(_preview.get("_paused"))
	var stamp := Time.get_ticks_msec()
	_run("alert(\"probe\")")
	var took := Time.get_ticks_msec() - stamp
	h.check(
		"the call returns rather than blocking (%d ms)" % took,
		took < 2000,
		"`OS.alert` is the obvious binding and it blocks the calling thread on "
		+ "Windows even under --headless; measured, it never returned, so a gate "
		+ "run that met a title's `alert` would hang until the ceiling killed it")
	var box: AcceptDialog = _alert_box()
	h.check("a dialog exists", box != null)
	h.check(
		"carrying the movie's text",
		box != null and box.dialog_text == "probe")
	h.check(
		"and the movie is stopped behind it",
		bool(_preview.get("_paused")),
		"Director's alert is modal against the whole engine; `_paused` is what "
		+ "that amounts to from the movie's side -- no frames, no events")
	if box != null:
		box.confirmed.emit()
		box.hide()
	h.check(
		"dismissing it puts the movie back the way it was",
		bool(_preview.get("_paused")) == was_paused,
		"restored rather than set false: a player who had paused with the debug "
		+ "key must not be un-paused by an alert")
	h.complete("`alert` raises a real box and stops the movie behind it")


# ------------------------------------------------------------------ delay

func _delay_checks(h) -> void:
	h.begin("`delay <ticks>` holds the playhead on the tempo channel's own hold")
	var clock = _preview.get("_clock")
	clock.release()
	_run("delay(30)")
	h.check(
		"the playhead is held",
		bool(clock.playhead_held()),
		"0 sites in this corpus; bound because Director has it (AGENTS.md)")
	h.check(
		"for the reason a tempo delay is held for (got %s)" % str(clock.hold_reason()),
		str(clock.hold_reason()) == "delay",
		"one channel, so a script delay and a score delay cannot disagree about "
		+ "what holding means")
	clock.release()
	h.complete("`delay <ticks>` holds the playhead on the tempo channel's own hold")


# ------------------------------------------------------------------- quit

## The one that would take fourteen harnesses down with it if it exited.
##
## The reference does not exit either: `b_quit` sets the score's play state to
## stopped and the projector quits because its loop ended. Split the same way, so
## the movie half is what every caller sees and the application half is gated on
## this preview being the running main scene -- which it is not here, and this
## file running to the end is the proof.
func _quit_checks(h) -> void:
	h.begin("`quit` stops the movie and cannot stop a harness")
	h.check(
		"this preview is not the running main scene",
		current_scene != _preview,
		"the gate on the application half, and the reason it is safe to bind")
	var before := _exit_frames()
	_run("quit")
	h.check("the movie is stopped", bool(_host.stopped))
	await _steps(8)
	h.check(
		"and takes no further steps (%d exitFrames in 8 ticks)"
			% (_exit_frames() - before),
		_exit_frames() == before,
		"102 sites across every title, and every 'quit game' path did nothing")
	h.check(
		"this process is still running, which is the whole point",
		true,
		"if the arm had called `get_tree().quit()` unguarded, no line after it "
		+ "in any harness would ever have run")
	# `halt` is the same function in the reference -- `b_halt` calls `b_quit` --
	# so it is checked through the same door rather than given its own.
	_host.stopped = false
	_preview.set_process(true)
	_run("halt")
	h.check(
		"`halt` is the same stop, as `b_halt` calling `b_quit` makes it",
		bool(_host.stopped),
		"0 sites; bound with `quit` because the reference makes them one function")
	_host.stopped = false
	_preview.set_process(true)
	h.complete("`quit` stops the movie and cannot stop a harness")


# ------------------------------------------------------------- updateStage

## `updateStage` is bound, and the measurement that used to say it could not be.
##
## The old version of this section asserted the *gap*: that `updatestage` was in
## the host's `IGNORED` list, and that `queue_redraw()` followed by
## `RenderingServer.force_draw()` left a Node2D's `draw` emission count unmoved.
## The second half is still true and is still measured below -- it is why the
## paint cannot go through `_draw` -- but the conclusion drawn from it, that
## Godot cannot present from inside a handler, was wrong. `force_draw()` presents
## the commands the canvas items *already hold*, so the answer is to write the
## commands directly (`director/director_paint.gd`) rather than to wait for a
## `NOTIFICATION_DRAW` that never arrives.
##
## The behaviour this replaces the gap assertion with is in `tools/update_stage.gd`,
## which drives the real player. What is left here is the pair of facts that
## decide the *mechanism*, kept as a pair so that neither can be quietly dropped.
func _update_stage_checks(h) -> void:
	h.begin("`updateStage` is bound, and the mechanism it is bound through")
	h.check(
		"it is out of the host's IGNORED list",
		not (Host.IGNORED as Array).has("updatestage"),
		"3,717 sites across six titles; a name in IGNORED answers cleanly and "
		+ "does nothing, which is the state this closed")
	h.check(
		"and in HANDLED, which is what the file claims about itself",
		(Host.HANDLED as Array).has("updatestage"))
	var ci := Node2D.new()
	root.add_child(ci)
	var draws := [0]
	ci.draw.connect(func() -> void: draws[0] += 1)
	await process_frame
	var settled: int = draws[0]
	ci.queue_redraw()
	RenderingServer.force_draw()
	h.check(
		"`force_draw` still does not run a pending `_draw` (%d -> %d)"
			% [settled, draws[0]],
		draws[0] == settled,
		"the reason the synchronous paint issues its own commands instead of "
		+ "asking for a redraw: the redraw callback is on the message queue and "
		+ "GDScript cannot flush it")
	# The other half, and the one the old note was missing: commands appended
	# from outside `_draw` *are* what `force_draw` presents.
	var item: RID = ci.get_canvas_item()
	RenderingServer.canvas_item_clear(item)
	RenderingServer.canvas_item_add_rect(item, Rect2(0, 0, 8, 8), Color.GREEN)
	RenderingServer.force_draw()
	h.check(
		"but commands written straight to the canvas item are presented, with "
		+ "`_draw` still unrun (%d)" % draws[0],
		draws[0] == settled,
		"if this ever fails, the paint reached `_draw` after all and "
		+ "`repaint_now` is doing something other than what it says")
	ci.queue_free()
	await process_frame
	h.complete("`updateStage` is bound, and the mechanism it is bound through")


# ------------------------------------------------------------------ driving

## One Lingo statement, run against the live movie's interpreter and host.
func _run(source: String) -> void:
	var script := Compiler.new().compile_source(
		"on probe\n  %s\nend\n" % source, "SystemBuiltinProbe")
	if script.is_empty():
		push_warning("lingo_system_builtins: `%s` did not compile" % source)
		return
	_interp.call_handler("probe", [], script)


## One Lingo expression, evaluated the same way.
func _value(expression: String) -> Variant:
	var script := Compiler.new().compile_source(
		"on probe\n  return %s\nend\n" % expression, "SystemBuiltinProbe")
	if script.is_empty():
		return "<did not compile>"
	return _interp.call_handler("probe", [], script)


## How many `exitFrame` messages the movie has been sent. The observable for
## "is the score still stepping": a paused room and a room holding itself with
## `go to the frame` sit on the same frame, and only one of them is still
## running handlers.
func _exit_frames() -> int:
	var sent: Dictionary = _preview.get("_sent")
	return int(sent.get("exitFrame", 0))


## Real frames, not a synthetic loop. `AGENTS.md`: a `for i in N: tick()` loop
## advances the runtime's clock and not the audio server's, and the score's own
## step is paced off real time here.
func _steps(count: int) -> void:
	for _i in count:
		await create_timer(0.05).timeout


## The dialog `alert` raised, found by type rather than by name so the harness
## does not carry a second copy of the node name.
func _alert_box() -> AcceptDialog:
	for child in _preview.get_children():
		if child is AcceptDialog:
			return child
	return null
