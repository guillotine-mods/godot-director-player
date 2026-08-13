extends SceneTree
## The fast-forward toggle: one key runs the movie at a rate the config names,
## the next hands it back to the score.
##
##   godot --headless --path . --script tools/fast_forward.gd
##   godot --path . --script tools/fast_forward.gd
##   godot --headless --path . --script tools/fast_forward.gd -- --root rating
##
## **Run it windowed for the last section.** The rate and the toggle are asserted
## headlessly by driving `_process` with a fixed delta and counting score ticks;
## that the *key* reaches the toggle at all needs a window with keyboard focus,
## which headless Godot does not have.
##
## **Why the key is PageDown and not F9.** The request was "make F9 set the
## framerate to something really fast, like 60fps, then another press is back to
## normal". F9 is the pause now, and the pause is on F9 because it had to come
## off F10 -- Rating tests `the keyCode = 109` at 48 sites, which is F10, and the
## handler that reads it is the one that leaves a timed scene. That fills the
## band: twelve F-keys, one of them Rating's, eleven commands already on the
## rest. So the key was measured rather than guessed. Over every root under
## `games/`, `tools/lib/key_sites.gd` finds the tested Mac codes to be
##
##   0 1 2 4 7 11 12 13 14 15 18-28 32 36 37 38 45 46 49 51 53 109 123-126
##
## PageDown is 121, which is in none of it, and it types no character, which is
## what the F-key band was ever a proxy for. `tools/debug_bindings.gd` asserts
## both of those against the games; this file asserts what the key then does.
##
## **What the rate scales, and what it cannot.** The frames and the *holds*: a
## tempo delay and a transition are counted down off the same delta, and a fast
## forward that ran the frames faster while sitting out every two-second delay
## would barely be faster -- this corpus spends 74 s in tempo delays across
## thirty-six frames. Sound is the exception and cannot be otherwise, because the
## mixer runs on the audio server's clock; a `soundBusy` wait still takes as long
## as the sound does. That asymmetry is asserted below rather than left implied.
##
## Title-agnostic: the rate the movie runs at without the toggle is read off the
## clock rather than assumed.

const Harness := preload("res://tools/lib/harness.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")

## Real seconds of `_process` to drive per measurement, and the engine frame rate
## to pretend they arrived at. One second is enough to separate 8 fps from 60 and
## short enough that a harness is not a stopwatch.
const SECONDS := 1.0
const ENGINE_HZ := 60.0

## How far a measured tick count may sit from the rate asked for.
##
## The clock carries the time left before the next step across ticks (`_due_in`)
## and a measurement inherits whatever the boot frames left in it, so the first
## and last step of a second can land either side of the boundary. Three,
## measured: a movie at 8 fps counts 7 or 8 depending on where the second starts.
## Anything wider than that is the rate not being applied, and the gap this has
## to discriminate is 8 against 60.
##
## **60 is the ceiling and not a coincidence**, which is why this drives
## `_process` at exactly `ENGINE_HZ`. The clock takes one score step per tick and
## drops the rest, as `Score::update` does, so a fast-forward configured above
## the engine's own frame rate is silently clamped to it -- and the check below
## that the toggle is "faster" is the one that would notice a config asking for
## 200. See `FrameClock.tick`.
const TOLERANCE := 3


## Score ticks over `SECONDS` of engine time, driving the preview's own
## `_process`. Awaiting real frames would measure the machine rather than the
## clock, and a synthetic loop is legitimate *here* precisely because the thing
## under test is the arithmetic between a real delta and a score step.
##
## **The preloader is stood down for the count, and that is not a fudge.** It
## reports the time it spent decoding to `director_frame_clock.gd:discount`,
## which subtracts it from the debt so a movie does not owe catch-up steps for
## time Director would have spent preloading. That is right on a real frame and
## is pure noise here: the decode is wall-clock work the loop's synthetic deltas
## never accounted for, so it silently removes steps in proportion to how busy
## the machine is. Measured with it in: 6 ticks where the movie's 8 fps says 8,
## varying run to run. The subject is the arithmetic between a delta and a step,
## and this is the one thing in the tick that is not it.
func _ticks_over_a_second(preview: Node) -> int:
	var preloader = preview.get("_preloader")
	preview.set("_preloader", null)
	var before := int(preview.get("_ticks"))
	for _i in int(ENGINE_HZ * SECONDS):
		preview.call("_process", 1.0 / ENGINE_HZ)
	preview.set("_preloader", preloader)
	return int(preview.get("_ticks")) - before


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _init() -> void:
	var h := Harness.new()
	var windowed := DisplayServer.get_name() != "headless"
	DebugKeys.load_config()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var clock = preview.get("_clock")
	var bound := DebugKeys.key_name("fast_forward")
	var configured := DebugKeys.number("fast_forward_fps")
	print("%s, fast_forward on %s at %.0f fps, movie runs at %.0f fps" % [
		str(preview.call("movie_name")), bound, configured, float(clock.fps)])

	h.begin("the command is bound and its rate comes from the config")
	h.check("`fast_forward` has a key", bound != "", bound)
	h.check("and a rate above zero, or the toggle would stop the movie",
		configured > 0.0, "%.1f" % configured)
	h.check("it starts off", float(preview.get("_fast_forward_fps")) == 0.0,
		str(preview.get("_fast_forward_fps")))
	h.complete("the command is bound and its rate comes from the config")

	# The movie's own rate first, as the control. Without it "60 ticks happened"
	# says nothing -- a movie authored at 60 fps would satisfy it untouched.
	var scored := float(clock.fps)
	var normal := _ticks_over_a_second(preview)

	h.begin("the toggle runs the movie at the configured rate")
	InputRouter.debug_key(preview, OS.find_keycode_from_string(bound))
	h.check("one press turns it on",
		is_equal_approx(float(preview.get("_fast_forward_fps")), configured),
		str(preview.get("_fast_forward_fps")))
	var fast := _ticks_over_a_second(preview)
	h.check("the score stepped at the movie's own rate before it (%.0f fps)" % scored,
		absi(normal - int(round(scored))) <= TOLERANCE,
		"%d ticks in %.0fs" % [normal, SECONDS])
	h.check("and at the configured rate after it (%.0f fps)" % configured,
		absi(fast - int(round(configured))) <= TOLERANCE,
		"%d ticks in %.0fs" % [fast, SECONDS])
	# The claim is "faster", and it has to survive a movie whose own rate is
	# already high: on a title authored at 60 the two counts would agree and both
	# checks above would still pass.
	h.check("which is faster, or the toggle is doing nothing here",
		fast > normal or is_equal_approx(scored, configured),
		"%d vs %d ticks" % [fast, normal])
	h.complete("the toggle runs the movie at the configured rate")

	h.begin("a second press hands the movie back to its score")
	InputRouter.debug_key(preview, OS.find_keycode_from_string(bound))
	h.check("the toggle is off", float(preview.get("_fast_forward_fps")) == 0.0,
		str(preview.get("_fast_forward_fps")))
	var again := _ticks_over_a_second(preview)
	h.check("and the score is back at %.0f fps" % scored,
		absi(again - int(round(scored))) <= TOLERANCE,
		"%d ticks in %.0fs" % [again, SECONDS])
	# The score's own rate must be untouched by all of this. Forcing the number
	# into `director_frame_clock.gd:fps` would have worked until the next frame
	# carrying a tempo cell overwrote it, and the toggle would then switch itself
	# off in the middle of a movie -- so the rate is applied to the *delta* and
	# the clock never hears about it.
	h.check("`the frameRate` the score asked for was never overwritten",
		is_equal_approx(float(clock.fps), scored),
		"%.1f, was %.1f" % [float(clock.fps), scored])
	h.complete("a second press hands the movie back to its score")

	# The rate is a `[debug]` value, which was the second half of the request:
	# "make the fps configurable from the cfg". A number the file names and the
	# engine ignores is the failure to catch, and it is invisible at the default.
	var written := "user://fast_forward_test.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("debug", "fast_forward_fps", 30)
	cfg.save(written)
	DebugKeys.load_config(written)

	h.begin("the rate is the config's, not a constant")
	InputRouter.debug_key(preview, OS.find_keycode_from_string(
		DebugKeys.key_name("fast_forward")))
	h.check("the toggle took the file's number",
		is_equal_approx(float(preview.get("_fast_forward_fps")), 30.0),
		str(preview.get("_fast_forward_fps")))
	var at_thirty := _ticks_over_a_second(preview)
	h.check("and the movie ran at it", absi(at_thirty - 30) <= TOLERANCE,
		"%d ticks in %.0fs" % [at_thirty, SECONDS])
	InputRouter.debug_key(preview, OS.find_keycode_from_string(
		DebugKeys.key_name("fast_forward")))
	h.complete("the rate is the config's, not a constant")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
	DebugKeys.load_config()

	# ------------------------------------------------------------- the wiring
	# Everything above went in through `InputRouter.debug_key`, which is the
	# preview's own dispatch and not a keyboard. That the *key* gets there is the
	# `_input` -> `key_event` -> `debug_key` path, and it needs keyboard focus.
	if windowed:
		var window := preview.get_window()
		window.grab_focus()
		DisplayServer.window_move_to_foreground()
		await process_frame
		h.begin("the key reaches the toggle through `_input`")
		Input.parse_input_event(_key(OS.find_keycode_from_string(bound) as Key))
		await process_frame
		h.check("%s turned it on" % bound,
			float(preview.get("_fast_forward_fps")) > 0.0,
			str(preview.get("_fast_forward_fps")))
		# The control, and this harness needs one as much as any: a key that
		# toggles nothing must leave it alone, or "the field changed" is
		# satisfied by anything at all reaching `debug_key`. F10 is the right
		# control because it is deliberately unbound -- it is Rating's.
		Input.parse_input_event(_key(KEY_F10))
		await process_frame
		h.check("and an unbound key left it alone",
			float(preview.get("_fast_forward_fps")) > 0.0,
			str(preview.get("_fast_forward_fps")))
		Input.parse_input_event(_key(OS.find_keycode_from_string(bound) as Key))
		await process_frame
		h.check("a second press turned it off",
			float(preview.get("_fast_forward_fps")) == 0.0,
			str(preview.get("_fast_forward_fps")))
		# A release must not toggle it back: `preview/input_router.gd` offers the
		# release to the movie and never to the bindings, and a binding that ran
		# on both halves would undo itself before the key was let go.
		Input.parse_input_event(_key(OS.find_keycode_from_string(bound) as Key))
		await process_frame
		Input.parse_input_event(_key(OS.find_keycode_from_string(bound) as Key, false))
		await process_frame
		h.check("and the release of a press did not undo it",
			float(preview.get("_fast_forward_fps")) > 0.0,
			str(preview.get("_fast_forward_fps")))
		h.complete("the key reaches the toggle through `_input`")
	else:
		print("")
		print("headless: the `_input` wiring is unasserted -- rerun without --headless")

	quit(h.finish("the fast-forward toggle"))
