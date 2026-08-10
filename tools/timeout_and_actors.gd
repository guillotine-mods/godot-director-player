extends SceneTree
## The per-frame callouts and the timeout clock, driven through the real player.
##
##   godot --headless --path . --script tools/timeout_and_actors.gd -- --root piposh2
##
## Four Director features that had no implementation at all until now, and one
## that had a store nothing read:
##
##   `the perFrameHook`   an object sent `stepFrame` once per frame
##   `the actorList`      a list of objects sent `stepFrame` once per frame
##   the timeout family   `the timeoutLength` ticks of no player activity raise
##                        a `timeOut` event, answered by `the timeoutScript`
##   `the updateLock`     suppresses the stage repaint while it is set
##   `the timeoutKeyDown` was **stored and consumed by nothing** -- §19 recorded
##                        it `inert`, and this is what makes it live
##
## **What goes red if any of it is reverted.** Every case counts something a
## movie can see rather than reading a property back:
##
##   the hook / the list   a handler that increments a global. Reverted, the
##                         frame loop never calls out and the counter stays 0
##                         while the playhead demonstrably moves -- which is the
##                         second half of each check, so a movie that simply
##                         stopped stepping cannot pass by leaving both at 0.
##   the timeout           a `timeoutScript` that sets a global. Reverted, the
##                         event never fires however long the clock is left.
##   the reset switches    the same clock, with a synthetic key event in
##                         between. Reverted, `the timeoutLapsed` keeps counting
##                         through the keypress.
##   `the updateLock`      `updateStage`'s own repaint counter. Reverted, the
##                         count moves while the lock is set.
##
## Title-agnostic: it installs its own Lingo and asserts about the frame loop,
## never about a room.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const LingoObject := preload("res://lingo/lingo_object.gd")

## One actor. `stepFrame` is the message Director sends; the counter is a global
## so the harness can read it without reaching into the object.
const ACTOR := """
property pName

on new me, who
  pName = who
  return me
end

on stepFrame me
  global steps
  put steps & pName into steps
end
"""


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame

	var lingo_host = preview.get("_host")
	var interp = preview.get("_interpreter")

	h.begin("the player booted with an interpreter")
	h.check("a movie is loaded", preview.get("_score") != null)
	h.check("the interpreter is there", interp != null)
	h.complete("the player booted with an interpreter")
	if lingo_host == null or interp == null or preview.get("_score") == null:
		preview.queue_free()
		quit(h.finish("the per-frame callouts and the timeout clock"))
		return

	var compiler := Compiler.new()
	var actor_ast: Dictionary = compiler.compile_source(ACTOR, "actor")

	# ------------------------------------------------------- Director's defaults
	var title := "the timeout properties start at Director's own defaults"
	h.begin(title)
	h.check("`the timeoutLength` is 10800 ticks (movie.cpp:90)",
		int(lingo_host.get_system_prop("timeoutlength")) == 10800,
		str(lingo_host.get_system_prop("timeoutlength")))
	h.check("`the timeoutKeyDown` and `the timeoutMouse` are on, `the timeoutPlay` off",
		int(lingo_host.get_system_prop("timeoutkeydown")) == 1
			and int(lingo_host.get_system_prop("timeoutmouse")) == 1
			and int(lingo_host.get_system_prop("timeoutplay")) == 0,
		"%s/%s/%s" % [lingo_host.get_system_prop("timeoutkeydown"),
			lingo_host.get_system_prop("timeoutmouse"),
			lingo_host.get_system_prop("timeoutplay")])
	h.check("`the actorList` starts empty and `the perFrameHook` is VOID",
		(lingo_host.get_system_prop("actorlist") as Array).is_empty()
			and lingo_host.get_system_prop("perframehook") == null)
	h.complete(title)

	# ------------------------------------------------------------ `stepFrame`
	title = "`the perFrameHook` and `the actorList` are sent `stepFrame` per frame"
	h.begin(title)
	var hook: Variant = _make(interp, actor_ast, "H")
	var one: Variant = _make(interp, actor_ast, "1")
	var two: Variant = _make(interp, actor_ast, "2")
	h.check("three actors were built",
		LingoObject.is_object(hook) and LingoObject.is_object(one)
			and LingoObject.is_object(two))
	lingo_host.set_system_prop("perframehook", hook)
	lingo_host.set_system_prop("actorlist", [one, two])
	interp.globals["steps"] = ""
	var moved := await _step(preview, 3)
	var trail := str(interp.globals.get("steps", ""))
	# The hook first, then the list in order -- `score.cpp`'s own ordering, and
	# the reason the trail records letters rather than a count.
	h.check("the playhead actually moved, so the callout had a chance to happen",
		moved > 0, "%d step(s)" % moved)
	h.check("every stepped frame sent hook-then-list, in order",
		trail != "" and trail.length() % 3 == 0 and trail.begins_with("H12"),
		JSON.stringify(trail))
	h.check("one round of messages per step, not one per engine tick",
		trail.length() / 3 == moved, "%d round(s) for %d step(s)" % [trail.length() / 3, moved])
	h.complete(title)

	title = "an emptied actorList and a cleared hook stop being messaged"
	h.begin(title)
	lingo_host.set_system_prop("perframehook", 0)
	lingo_host.set_system_prop("actorlist", [])
	interp.globals["steps"] = ""
	var after := await _step(preview, 3)
	h.check("the playhead still moved", after > 0, "%d step(s)" % after)
	h.check("and nothing was stepped",
		str(interp.globals.get("steps", "")) == "",
		JSON.stringify(interp.globals.get("steps", "")))
	h.complete(title)

	# --------------------------------------------------------- the timeout clock
	title = "a lapsed timeout raises `timeOut`, and `the timeoutScript` answers it"
	h.begin(title)
	interp.globals["fired"] = 0
	lingo_host.set_system_prop("timeoutscript", "settimeoutmark")
	# A movie handler to name, installed the way a movie would: the bare-word
	# form of `the timeoutScript` resolves to a handler the movie declares, so
	# one is compiled into the running interpreter's movie scripts.
	var mark := compiler.compile_source(
		"on setTimeoutMark\n  global fired\n  fired = fired + 1\nend\n", "MovieScript timeoutmark")
	interp.load_bundle({"cast": "harness", "scripts": {"MovieScript 1": mark}})
	h.check("the handler is reachable by name", bool(interp.has_handler("settimeoutmark")))
	lingo_host.set_system_prop("timeoutlength", 1)
	lingo_host.set_system_prop("timeoutlapsed", 600)
	await _step(preview, 2)
	h.check("the event fired", int(interp.globals.get("fired", 0)) > 0,
		"fired %s" % str(interp.globals.get("fired", 0)))
	h.check("firing reset the clock rather than firing every tick for ever",
		int(lingo_host.get_system_prop("timeoutlapsed")) < 60,
		"lapsed %s ticks" % str(lingo_host.get_system_prop("timeoutlapsed")))
	h.complete(title)

	title = "a length of 0 disables the clock"
	h.begin(title)
	lingo_host.set_system_prop("timeoutlength", 0)
	lingo_host.set_system_prop("timeoutlapsed", 600)
	interp.globals["fired"] = 0
	await _step(preview, 3)
	h.check("nothing fired", int(interp.globals.get("fired", 0)) == 0,
		str(interp.globals.get("fired", 0)))
	h.complete(title)

	# ------------------------------------------------- what resets the clock
	title = "`the timeoutKeyDown` decides whether a keypress resets the clock"
	h.begin(title)
	lingo_host.set_system_prop("timeoutlength", 10800)
	lingo_host.set_system_prop("timeoutkeydown", 1)
	lingo_host.set_system_prop("timeoutlapsed", 600)
	var before_key := int(lingo_host.get_system_prop("timeoutlapsed"))
	preview._input(_key_event())
	var after_key := int(lingo_host.get_system_prop("timeoutlapsed"))
	h.check("with it on, a key press restarts the clock",
		before_key >= 500 and after_key < 60, "%d -> %d ticks" % [before_key, after_key])
	lingo_host.set_system_prop("timeoutkeydown", 0)
	lingo_host.set_system_prop("timeoutlapsed", 600)
	preview._input(_key_event())
	var held := int(lingo_host.get_system_prop("timeoutlapsed"))
	h.check("with it off, the same key press does not",
		held >= 500, "%d ticks" % held)
	h.complete(title)

	title = "`the timeoutMouse` decides whether a click resets the clock"
	h.begin(title)
	lingo_host.set_system_prop("timeoutmouse", 1)
	lingo_host.set_system_prop("timeoutlapsed", 600)
	preview.call("_press_click", Vector2(4, 4), false)
	var after_click := int(lingo_host.get_system_prop("timeoutlapsed"))
	h.check("with it on, a press restarts the clock", after_click < 60,
		"%d ticks" % after_click)
	lingo_host.set_system_prop("timeoutmouse", 0)
	lingo_host.set_system_prop("timeoutlapsed", 600)
	preview.call("_press_click", Vector2(4, 4), false)
	var still := int(lingo_host.get_system_prop("timeoutlapsed"))
	h.check("with it off, the same press does not", still >= 500, "%d ticks" % still)
	h.complete(title)

	# ------------------------------------------------------------ `the updateLock`
	title = "`the updateLock` suppresses the stage repaint"
	h.begin(title)
	lingo_host.set_system_prop("updatelock", 0)
	var painted_before := int(preview.get("_repaints"))
	h.check("`updateStage` paints while the lock is clear",
		bool(preview.call("repaint_now")) and int(preview.get("_repaints")) == painted_before + 1,
		"%d -> %d" % [painted_before, int(preview.get("_repaints"))])
	lingo_host.set_system_prop("updatelock", 1)
	var locked_at := int(preview.get("_repaints"))
	var painted: bool = preview.call("repaint_now")
	h.check("and does not while it is set",
		not painted and int(preview.get("_repaints")) == locked_at,
		"%d -> %d" % [locked_at, int(preview.get("_repaints"))])
	h.check("the property reads back what was written",
		int(lingo_host.get_system_prop("updatelock")) == 1)
	lingo_host.set_system_prop("updatelock", 0)
	h.check("clearing it paints again", bool(preview.call("repaint_now")))
	h.complete(title)

	preview.queue_free()
	quit(h.finish("the per-frame callouts, the timeout clock and the update lock"))


## One instance of the fixture actor, built through the language rather than
## through GDScript -- `new` is the thing under test everywhere else and the
## objects here have to be the same shape a movie's would be.
func _make(interp, ast: Dictionary, name: String) -> Variant:
	# The fixture script is handed straight in: `make_object` takes an AST as well
	# as a reference, which is what lets a harness build one without a cast --
	# and it is the same code path `new(script "x")` takes, so what is built here
	# is what a movie would have built.
	return interp.make_object(ast, [name])


## Step the movie by awaiting real frames until the playhead has moved `want`
## times, or a ceiling is reached. Real frames because a synthetic tick loop
## advances the runtime's clock and not the audio server's (`AGENTS.md`), and
## because the callout under test is in the frame loop rather than in a function
## a harness could call.
func _step(preview: Node, want: int) -> int:
	var start: int = int(preview.call("current_frame"))
	var seen := 0
	var last := start
	for _i in 400:
		await process_frame
		var now: int = int(preview.call("current_frame"))
		if now != last:
			seen += 1
			last = now
		if seen >= want:
			break
	return seen


## A synthetic key-down, the shape `preview/input_router.gd` routes.
func _key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.unicode = 97
	event.pressed = true
	return event
