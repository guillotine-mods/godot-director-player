extends SceneTree
## How far does an abort unwind? `bugs.md` 123's second half.
##
##   godot --headless --audio-driver Dummy --path . --script tools/lingo_execute_boundary.gd
##
## `_aborting` is this port's `Lingo::_abort`, and the reference's flag is scoped
## to **one `Lingo::execute` call** -- it is that loop's condition, its epilogue
## pops every remaining `CFrame`, and the last line of the epilogue is
## `_abort = false` (`reference/scummvm/lingo/lingo.cpp:634`, `742-748`). The part
## that decides the shape of any fix is that `execute()` is **re-entrant**:
##
##   * `b_call` -- and `b_sendSprite` and `b_sendAllSprites` through it -- reaches
##     `callBehaviorHandler`, which records the callstack depth and calls
##     `execute(frame)` **once per recipient** (`lingo-builtins.cpp:1880-1892`,
##     `1915-1921`, `3470-3547`).
##   * `Lingo::processEvent` calls `execute()` around each queued element, and
##     `processEvents` walks the queue calling it (`lingo-events.cpp:723-786`,
##     `809`, `831`).
##
## So "the dispatch an abort ends" is one `execute()` and **not one event**: an
## abort inside `call(#msg, obj)` stops that message and the caller runs its next
## statement. This port had no such boundary at all -- `_broadcast` was an ordinary
## GDScript call and `scripts.gd:dispatch` an ordinary one too -- so setting the
## flag from `_call`'s fall-through would have unwound *further* than Director
## does, which is a worse bug than the divergence being fixed. That is why
## `bugs.md` 123 calls this its own piece of work and why it lands before the
## abort.
##
## **The flag does not mean "an error happened".** `LC::procret` sets the same one
## on the ordinary return from the outermost handler (`lingo-code.cpp:1901`,
## `1909`). It means "stop the loop", and a check written as though it were an
## error channel would assert the wrong control flow.
##
## The scope is opened at five places, all of them one of the two shapes above:
##
##   `lingo_interpreter.gd:_broadcast`            `b_call`, per recipient
##   `lingo_interpreter.gd:call_in_script`        `processEvent`, and so also
##                                                `frame_loop.gd:send_sprite_message`
##   `lingo_interpreter.gd:call_movie_handler`    `processEvent`, movie tier
##   `lingo_interpreter.gd:run_primary`           `processEvent`, tier 1
##   `lingo_interpreter.gd:resume_chain`          a thaw is a fresh `execute()`
##   `preview/scripts.gd:dispatch`                `processEvent`
##   `preview/event_chain.gd:run_primary_script`  `processEvent`, tier 1
##
## **Four of them are in the interpreter rather than at their callers on purpose.**
## One caller of `call_in_script` is `scenes/preview/frame_loop.gd`, which delivers
## `beginSprite` / `endSprite` / `stepFrame` -- the reference queues those through
## `Movie::processEvent(kEventBeginSprite, i)` (`lingo-events.cpp:866`, `992`) and
## runs them through `execute()` like any other element -- and a line written in
## `event_chain.gd` would not have covered it. The one that matters is
## `updateStage` inside a running handler: it re-enters the frame loop, so an abort
## in a `beginSprite` there would otherwise unwind the handler that called
## `updateStage`. `call_handler` deliberately has **no** scope, because it is also
## `_call`'s ordinary in-language handler call, where the reference has no
## `execute()` either.
##
## Every check here is driven through real Lingo on the real player, and each site
## was confirmed to red it: deleting the `begin_execute`/`end_execute` pair from
## `_broadcast` reds the two `call()` cases and the list case, from
## `scenes/preview/scripts.gd:dispatch` reds the dispatch case, and from
## `call_in_script` reds the event-chain case. The runs are quoted in the session
## report that landed this file.
##
## Title-agnostic: every probe is compiled here, so nothing depends on the loaded
## movie.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Scripts := preload("res://scenes/preview/scripts.gd")
const EventChain := preload("res://scenes/preview/event_chain.gd")

## A parent script whose message aborts, and one whose message does not.
##
## `gBoundaryCount` is bumped **before** the abort so the count says how many
## recipients were reached, which is the question `b_call`'s list arm answers:
## one `execute()` scope per element means the second object still gets the
## message after the first one aborted.
const OBJECT_SOURCE := """
on new me
  return me
end
on msgabort me
  gBoundaryCount = gBoundaryCount + 1
  abort
  gBoundaryCount = gBoundaryCount + 100
end
on msgquiet me
  gBoundaryCount = gBoundaryCount + 1
end
"""

## The callers. `return 7` after the `call` is the whole experiment in every case:
## it is the statement the reference reaches and a port with no boundary does not.
const PROBE_SOURCE = """
on outercall
  call(#msgabort, gBoundaryObj)
  gBoundaryAfter = 1
  return 7
end
on outerlist
  call(#msgabort, gBoundaryList)
  return 7
end
on outerplain
  innerabort()
  gBoundaryAfter = 1
  return 7
end
on innerabort
  abort
end
on dispatchabort
  gBoundaryCount = gBoundaryCount + 1
  abort
end
"""

## The **second** element of the chain, and its shape is the whole of that check.
##
## `_exec_from` tests `_aborting` *after* each statement, so an abort that leaked
## in from the element before does not stop this handler starting -- it stops it
## after its first statement. A probe whose only statement is the one being counted
## therefore passes whether or not the boundary exists, and the first version of
## this file did exactly that: it reused the aborting probe for both elements and
## stayed green with the boundary deleted from `event_chain.gd`. So the count here
## is the **second** statement, behind a no-op, and 11 versus 1 is the difference
## between a chain that closed the scope between elements and one that did not.
const CHAIN_SECOND_SOURCE = """
on dispatchabort
  nothing()
  gBoundaryCount = gBoundaryCount + 10
end
"""


func _init() -> void:
	var _args := Args.parse()
	var h := Harness.new()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var interp = preview.get("_interpreter")
	var lingo_host = preview.get("_host")
	var case := "the player is up with an interpreter on it"
	h.begin(case)
	h.check("the interpreter is attached", interp != null)
	h.complete(case)
	if interp == null:
		quit(h.finish("the execute() boundary"))
		return

	var compiler := Compiler.new()
	var object_ast: Dictionary = compiler.compile_source(
		OBJECT_SOURCE, "BoundaryObject")
	var probes: Dictionary = compiler.compile_source(PROBE_SOURCE, "BoundaryProbe")
	var chain_second: Dictionary = compiler.compile_source(
		CHAIN_SECOND_SOURCE, "BoundaryChainSecond")
	case = "the probes compile"
	h.begin(case)
	h.check("the probes compile", not object_ast.is_empty() and not probes.is_empty()
		and not chain_second.is_empty(), compiler.error)
	h.complete(case)
	if object_ast.is_empty() or probes.is_empty():
		preview.queue_free()
		await process_frame
		quit(h.finish("the execute() boundary"))
		return

	# --------------------------------------------------------------- the counter
	#
	# Asked first because everything below reads it, and because a leaked scope is
	# the failure mode that makes a *later* abort stop one level short -- which
	# would look like the abort not working rather than like a counter that drifted.
	case = "the scope counter itself"
	h.begin(case)
	h.check("no scope is open before anything runs",
		int(interp.execute_depth()) == 0, "depth %d" % int(interp.execute_depth()))
	var outer: int = interp.begin_execute()
	var inner: int = interp.begin_execute()
	h.check("nesting counts up", int(interp.execute_depth()) == 2,
		"depth %d" % int(interp.execute_depth()))
	interp.end_execute(inner)
	interp.end_execute(outer)
	h.check("and back down to nothing", int(interp.execute_depth()) == 0,
		"depth %d" % int(interp.execute_depth()))
	h.complete(case)

	var instance: Variant = interp.make_object(object_ast)
	var second: Variant = interp.make_object(object_ast)
	case = "the probe objects instantiate"
	h.begin(case)
	h.check("two script objects were built", instance != null and second != null)
	h.complete(case)
	if instance == null or second == null:
		preview.queue_free()
		await process_frame
		quit(h.finish("the execute() boundary"))
		return

	# ------------------------------------------------------ `call(#msg, object)`
	#
	# The reference's `b_call` -> `callBehaviorHandler` -> `execute(frame)`. This is
	# the case the whole file exists for.
	case = "an abort inside call(#msg, object) stops the message, not the caller"
	h.begin(case)
	interp.reset_steps()
	interp.globals["gboundarycount"] = 0
	interp.globals["gboundaryafter"] = 0
	interp.globals["gboundaryobj"] = instance
	var answer: Variant = interp.call_handler("outercall", [], probes)
	h.check("the message ran and aborted where it said it would",
		int(interp.globals.get("gboundarycount", -1)) == 1,
		"count %s; 101 would mean the abort did not stop the recipient at all"
			% str(interp.globals.get("gboundarycount", -1)))
	# The two halves of "the caller carries on", asked separately because a
	# `return 7` could be reached by a path that skipped the statement above it.
	h.check("and the caller ran its next statement",
		int(interp.globals.get("gboundaryafter", -1)) == 1,
		"gBoundaryAfter %s" % str(interp.globals.get("gboundaryafter", -1)))
	h.check("and returned normally, as the reference's caller does",
		_is_seven(answer), "returned %s" % str(answer))
	h.check("and no scope was leaked", int(interp.execute_depth()) == 0,
		"depth %d" % int(interp.execute_depth()))
	h.complete(case)

	# ------------------------------------------------------- `call(#msg, [a, b])`
	#
	# `b_call`'s list arm calls `callBehaviorHandler` **per element**
	# (`lingo-builtins.cpp:1915-1921`), so each recipient gets its own `execute()`
	# and the first one aborting cannot swallow the second. A single scope around
	# the whole broadcast would pass every check above and fail this one, which is
	# why it is here.
	case = "and one scope per recipient, which is what the list arm does"
	h.begin(case)
	interp.reset_steps()
	interp.globals["gboundarycount"] = 0
	interp.globals["gboundarylist"] = [instance, second]
	answer = interp.call_handler("outerlist", [], probes)
	h.check("both objects in the list were messaged",
		int(interp.globals.get("gboundarycount", -1)) == 2,
		"count %s; 1 means the first object's abort ended the broadcast"
			% str(interp.globals.get("gboundarycount", -1)))
	h.check("and the caller still returned normally",
		_is_seven(answer), "returned %s" % str(answer))
	h.complete(case)

	# ------------------------------------------------------- the opposite error
	#
	# A boundary that swallowed *every* abort would pass everything above and be
	# wrong: an ordinary handler call is `LC::call` with no `execute()` around it,
	# so `abort` inside one unwinds the caller and every caller above it. This is
	# the check that stops the fix over-reaching, and it is the property
	# `tools/undefined_handler.gd` already relies on.
	case = "an ordinary nested call is not a boundary and still unwinds"
	h.begin(case)
	interp.reset_steps()
	interp.globals["gboundaryafter"] = 0
	answer = interp.call_handler("outerplain", [], probes)
	h.check("the caller's next statement did not run",
		int(interp.globals.get("gboundaryafter", -1)) == 0,
		"gBoundaryAfter %s" % str(interp.globals.get("gboundaryafter", -1)))
	h.check("and it did not return its value either",
		not _is_seven(answer), "returned %s" % str(answer))
	h.complete(case)

	# ------------------------------------------------------------ a dispatch
	#
	# `Lingo::processEvent`'s `execute()`, and the path `sendSprite` /
	# `sendAllSprites` re-enter through: `preview_lingo_host.gd` calls
	# `preview._dispatch` per channel, which is `scripts.gd:dispatch`. What is
	# asserted is that the scope closed -- an abort left standing here would be
	# tested by the *caller's* next statement, which is a behaviour halfway through
	# a broadcast.
	case = "a dispatch is a boundary, which is how sendAllSprites survives one"
	h.begin(case)
	interp.reset_steps()
	interp.globals["gboundarycount"] = 0
	Scripts.dispatch(preview, interp, "dispatchabort", probes)
	h.check("the dispatched handler ran and aborted",
		int(interp.globals.get("gboundarycount", -1)) == 1,
		"count %s" % str(interp.globals.get("gboundarycount", -1)))
	h.check("and the abort did not outlive the dispatch",
		not bool(interp.get("_aborting")),
		"_aborting is still set, so the next statement in whatever called "
		+ "sendAllSprites would be dropped")
	h.check("and no scope was leaked", int(interp.execute_depth()) == 0,
		"depth %d" % int(interp.execute_depth()))
	h.complete(case)

	# -------------------------------------------------------- an event chain
	#
	# `processEvents` calls `processEvent` -- and so `execute()` -- per queued
	# element (`lingo-events.cpp:723-786`), so an aborting behaviour does not
	# swallow the frame script's turn at the same click. What stops a chain is the
	# pass flag, and conflating the two would make an undefined-handler call behave
	# like a `stopEvent` nobody wrote.
	case = "and so is each element of an event chain"
	h.begin(case)
	interp.reset_steps()
	interp.globals["gboundarycount"] = 0
	if lingo_host != null:
		lingo_host.pass_event = true
	var ran: int = EventChain.run(preview, interp, "dispatchabort", [
		EventChain.element("cast", probes, true),
		EventChain.element("frame", chain_second, true),
	])
	h.check("the second element ran past its first statement, which an abort "
			+ "leaked from the first would have stopped",
		int(interp.globals.get("gboundarycount", -1)) == 11,
		"count %s over %d element(s) reported run; 1 means the abort survived the "
			% [str(interp.globals.get("gboundarycount", -1)), ran]
			+ "element boundary and truncated the next tier")
	h.check("and the abort did not outlive the chain either",
		not bool(interp.get("_aborting")), "_aborting is still set")
	h.check("and no scope was leaked", int(interp.execute_depth()) == 0,
		"depth %d" % int(interp.execute_depth()))
	h.complete(case)

	preview.queue_free()
	await process_frame
	quit(h.finish("an abort unwinds to the nearest execute() and no further"))


## Did the handler reach its `return 7`?
##
## Written out rather than as `int(answer) == 7` for the reason
## `tools/undefined_handler.gd` gives at its own copy: **an aborted handler answers
## VOID and `int(null)` is a runtime error, not a cast** -- which ends `_init`
## before `quit()` and leaves the harness hanging rather than failing.
static func _is_seven(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) == 7
