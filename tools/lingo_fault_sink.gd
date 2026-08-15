extends SceneTree
## Can anything outside the interpreter answer "did a script fault while that room
## ran"? `bugs.md` 59.
##
##   godot --headless --path . --script tools/lingo_fault_sink.gd -- --root piposh2 --boot strtgame.dir
##
## `LingoInterpreter._fail` is where every runtime fault the interpreter can name
## lands -- step budget exhausted, a repeat that did not terminate, handler
## recursion too deep, an unknown statement, a target with no assign arm. They go
## into `errors`, and `reset_steps` clears `errors` at the **start of every
## dispatch**: `preview/scripts.gd:dispatch`, `preview/event_chain.gd:run` and the
## thaw. One score step dispatches `idle`, `exitFrame`, `prepareFrame` and
## `enterFrame` back to back inside a single process frame, so a fault raised in
## any of them but the last was gone before anything outside the interpreter could
## look -- and a handler cut off half-way by the step budget left the room in a
## state nobody could attribute afterwards.
##
## Half the sink already existed and is not what this asserts: `reset_steps`
## drains to `print` against a `_reported` set that survives the dispatch, so a
## fault is at least in the run's *output*. **A harness cannot assert on stdout**,
## which is why `tools/liveness_sweep.gd` polls `errors` once a process frame and
## still cannot promise it caught them all. What this asserts is the half that was
## missing: a number and a list that outlive the dispatch.
##
## The shape of every check below is a **delta**, never an absolute. The preview
## boots a real movie whose own scripts may legitimately fault before this file
## gets a look in, and a harness that demanded zero would be asserting that the
## corpus is clean rather than that the sink works.
##
## Title-agnostic: the faulting handler is compiled here, so nothing depends on
## the loaded movie containing a bug.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")


func _init() -> void:
	var _args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var interp = preview.get("_interpreter")

	var case := "a runtime fault outlives the dispatch that raised it"
	h.begin(case)
	if interp == null:
		h.check("the interpreter is attached", false)
		h.complete(case)
		quit(h.finish("the Lingo fault sink"))
		return

	var compiler := Compiler.new()
	# Unbounded self-recursion: the one fault that needs no host, no member and no
	# corpus, and that `_fail` names in as many words
	# (`lingo_interpreter.gd:604`). Whether the depth guard or the step budget
	# catches it first does not matter -- both end in `_fail`, which is the thing
	# under test.
	var faulty: Dictionary = compiler.compile_source(
		"on sinkprobe\n  sinkprobe\nend\n", "FaultSinkProbe")
	var clean: Dictionary = compiler.compile_source(
		"on sinkclean\n  return 1\nend\n", "FaultSinkProbe")
	h.check("the probes compile", not faulty.is_empty() and not clean.is_empty(),
		compiler.error)
	if faulty.is_empty() or clean.is_empty():
		h.complete(case)
		quit(h.finish("the Lingo fault sink"))
		return

	# A dispatch that does not fault must not move the counter, or "42 faults this
	# session" means nothing. Through `reset_steps` first, so this measures a whole
	# dispatch the way the player's path does.
	interp.reset_steps()
	var before := int(interp.error_total)
	interp.call_handler("sinkclean", [], clean)
	h.check("a handler that runs clean raises nothing",
		int(interp.error_total) == before,
		"%d -> %d" % [before, int(interp.error_total)])

	interp.reset_steps()
	interp.call_handler("sinkprobe", [], faulty)
	h.check("the faulting handler is reported while its dispatch is current",
		not interp.errors.is_empty(), "errors %d" % interp.errors.size())
	var raised := int(interp.error_total)
	h.check("and the session counter moved", raised > before,
		"%d -> %d" % [before, raised])

	# **The whole of the bug, in one line.** This is the next dispatch beginning:
	# `preview/scripts.gd:dispatch` calls exactly this before it runs anything, and
	# before the fix it took the only record of the fault with it.
	interp.reset_steps()
	h.check("the next dispatch clears the per-dispatch list, as Director's does",
		interp.errors.is_empty(), "errors %d" % interp.errors.size())
	h.check("but the session counter survives it",
		int(interp.error_total) == raised,
		"%d, wanted %d" % [int(interp.error_total), raised])
	var faults: PackedStringArray = interp.session_faults()
	var named := false
	for message in faults:
		if str(message).contains("sinkprobe"):
			named = true
	h.check("and the fault is still nameable, with where it happened", named,
		"%d distinct fault(s): %s" % [faults.size(), ", ".join(faults)])

	# A second dispatch's worth of the same fault must count again: a frame script
	# that fails on every `exitFrame` is fifteen faults a second, and a sink that
	# deduplicated the *count* as well as the message would report it as one.
	var twice := int(interp.error_total)
	interp.reset_steps()
	interp.call_handler("sinkprobe", [], faulty)
	h.check("a fault raised again counts again",
		int(interp.error_total) > twice,
		"%d -> %d" % [twice, int(interp.error_total)])
	h.complete(case)

	preview.queue_free()
	await process_frame
	quit(h.finish("the Lingo fault sink"))
