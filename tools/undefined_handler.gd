extends SceneTree
## A call to a handler nothing defines: is it told apart from a builtin this port
## has not bound, and does it say so where a run can see it? `bugs.md` 123.
##
##   godot --headless --path . --script tools/undefined_handler.gd
##
## Two names reach `lingo_interpreter.gd:_call`'s fall-through and mean opposite
## things. **A builtin the port has not bound** is a hole on our side: the
## reference resolves it out of one of its four name tables and returns normally,
## so it has to keep answering here or a gap in our table becomes a gap in the
## movie. **A handler the movie does not define** is the movie's own, and the
## reference ends it with `lingoError("Call to undefined handler '%s'...")`
## (`reference/scummvm/lingo/lingo-code.cpp:1770`), which sets `_abort` --
## `Lingo::execute`'s loop condition, and the flag whose epilogue pops *every*
## frame on the callstack (`lingo.cpp:634`, `742-748`). Before this the two were
## one report and one answer of 0, and 0 is indistinguishable from a handler that
## returned 0.
##
## What is asserted here is the **split**, not an abort. The port still runs the
## statement after the call, deliberately: two of the 19 undefined call sites in
## the six shipped roots are `gotoNetPage`, which Director answers and the
## reference does not implement at all, so aborting on "the reference has no
## table entry" would truncate a handler because of a hole in ScummVM. So "the
## statement after it still runs" asserts the *current* behaviour on purpose -- if
## a later change turns the abort on, that check must be edited rather than
## quietly satisfied, and it was confirmed to go red against an interpreter with
## `_aborting = true` added at the fall-through.
##
## The last case is the other half, and it is why the abort would be one line: it
## proves `_aborting` already does what `_abort` does, including through a
## *nested* call. That is the property the reference's epilogue provides and the
## one a fidelity claim about aborting would rest on, so it is worth a check of
## its own whether or not the flag is ever set from `_call`.
##
## Title-agnostic: every probe is compiled here, so nothing depends on the loaded
## movie defining, or failing to define, anything.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Diagnostics := preload("res://lingo/lingo_diagnostics.gd")
const RefNames := preload("res://lingo/lingo_reference_names.gd")

## A name no title declares and no table holds. Deliberately not a plausible
## builtin: the point of the probe is the unambiguous half.
const NO_SUCH := "nosuchhandlerxyzzy"

## Names the reference *does* hold, so a table that lost a row says which one.
##
## The first three are the load-bearing ones `bugs.md` 123 names: `getPref`
## answers VOID for a preference never written, and `externalParamName` /
## `externalParamValue` answer VOID past the end of the list, which is how a movie
## knows the loop is over. If any of the three were ever classified as an
## undefined handler, a future abort would fire on the ordinary end of a loop.
const KNOWN := ["getpref", "externalparamname", "externalparamvalue",
	"mouseh", "marker", "soundbusy", "abort"]

## Names the reference does **not** hold, which is the half that decides.
##
## `gotoNetPage` is the measured counter-example and the reason the abort stays
## off: real Director NetLingo, and absent from the whole of
## `reference/scummvm/lingo/` -- no `netpage`, `netDone` or `getNetText` anywhere
## in it. Two call sites, in `piposh-en` and `piposh-dream`. `mraker` is
## `rating`'s own typo for `marker` -- `go(mraker(1))` on the line above
## `go(marker(0))`, twice -- and is what a *correct* abort would fire on. Both
## being in this list at once is the whole argument: the discriminator cannot tell
## them apart, because it is a statement about ScummVM's coverage and not about
## Director's language.
const NOT_KNOWN := ["gotonetpage", "mraker", NO_SUCH]

## Names in the reference's tables that this port is expected *not* to bind, so
## the "a hole on our side still answers" check has something to be about.
##
## Chosen for having no effect if they are bound: three are queries and
## `showXlib` prints a list. Anything that writes -- `beginRecording`,
## `openResFile`, `save` -- is not a candidate however good a probe it would make,
## because the harness boots a real movie.
##
## The list will rot the day the port binds all four, and the check says so out
## loud rather than passing: "at least one probe actually reached the
## fall-through" fails, which is the honest report that this case no longer proves
## anything and needs a new name.
const HOLE_PROBES := ["xfactorylist", "idleloaddone", "showxlib", "showresfile"]


func _init() -> void:
	var _args := Args.parse()
	var h := Harness.new()

	# The reference's four tables, asked directly. No preview and no movie needed:
	# this is a statement about `reference/scummvm/`, and it is the input every
	# check below depends on.
	var case := "the reference's own name tables"
	h.begin(case)
	var missing: Array = []
	for name in KNOWN:
		if not RefNames.knows(str(name)):
			missing.append(str(name))
	h.check("every name the reference resolves is in the table",
		missing.is_empty(), "missing: %s" % ", ".join(PackedStringArray(missing)))
	var spurious: Array = []
	for name in NOT_KNOWN:
		if RefNames.knows(str(name)):
			spurious.append(str(name))
	h.check("and no name it aborts on is", spurious.is_empty(),
		"present: %s" % ", ".join(PackedStringArray(spurious)))
	# A floor and not the exact 360, because the number moves whenever
	# `reference/scummvm/` does and an equality here would read as "the table
	# broke" when what happened is that the reference gained a builtin. What it
	# is for is the failure mode that matters: a table gutted to a handful, or an
	# extraction that silently matched nothing, which would classify most of the
	# corpus as undefined handlers.
	h.check("the table is the whole of the four tables, not a sample",
		RefNames.KNOWN.size() > 300,
		"%d name(s); 360 when derived, and a rise means the reference moved"
			% RefNames.KNOWN.size())
	h.complete(case)

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var interp = preview.get("_interpreter")
	if interp == null:
		h.begin("the interpreter is attached")
		h.check("the interpreter is attached", false)
		h.complete("the interpreter is attached")
		quit(h.finish("an undefined handler call"))
		return

	var compiler := Compiler.new()
	# `return 7` *after* the call is the whole experiment: it is the statement
	# Director does not reach.
	var known_calls := ""
	for name in HOLE_PROBES:
		known_calls += "  %s(1)\n" % str(name)
	var probes: Dictionary = compiler.compile_source(
		"on undefprobe\n  %s()\n  return 7\nend\n" % NO_SUCH
		+ "on knownprobe\n%s  return 7\nend\n" % known_calls
		+ "on abortouter\n  abortinner()\n  return 7\nend\n"
		+ "on abortinner\n  abort\nend\n",
		"UndefinedHandlerProbe")
	case = "the probes compile"
	h.begin(case)
	h.check("the probes compile", not probes.is_empty(), compiler.error)
	h.complete(case)
	if probes.is_empty():
		preview.queue_free()
		await process_frame
		quit(h.finish("an undefined handler call"))
		return

	case = "a call to a handler nothing defines"
	h.begin(case)
	interp.diagnostics.clear()
	interp.reset_steps()
	var answer: Variant = interp.call_handler("undefprobe", [], probes)
	var undefined: PackedStringArray = interp.diagnostics.names_in(
		Diagnostics.UNDEFINED_HANDLER)
	var builtins: PackedStringArray = interp.diagnostics.names_in(Diagnostics.BUILTIN)
	h.check("is recorded as an undefined handler", undefined.has(NO_SUCH),
		"undefined_handler: %s" % ", ".join(undefined))
	# The half that makes the first one worth having. Reported as a missing
	# *binding* it joins the port's work list, where 19 corpus sites would sit
	# among the real gaps and the F3 report's `builtins unbound` line could not be
	# read as a list of anything.
	h.check("and not as a binding the port owes", not builtins.has(NO_SUCH),
		"builtin: %s" % ", ".join(builtins))
	# **Deliberate, and the entry's open half.** Director's `_abort` would have
	# dropped this statement and every caller's. See the header.
	h.check("the statement after it still runs, as this port has decided for now",
		_is_seven(answer), "returned %s" % str(answer))
	# On the player's path, which the sink is not. Asked **after** the next
	# `reset_steps`, because that is where `_drain_errors` runs: the fault is in
	# `errors` while its own dispatch is current and reaches `print` and
	# `_reported` only when the following dispatch begins. Asking before it does
	# reads an empty list and says the print never happened, which is how the
	# first version of this check failed against a working engine.
	interp.reset_steps()
	var named := false
	for message in interp.session_faults():
		if str(message).contains(NO_SUCH):
			named = true
	h.check("and a run says so out loud, not only the sink", named,
		"faults: %s" % ", ".join(interp.session_faults()))
	h.complete(case)

	case = "a builtin the reference knows and this port has not bound"
	h.begin(case)
	interp.diagnostics.clear()
	interp.reset_steps()
	answer = interp.call_handler("knownprobe", [], probes)
	undefined = interp.diagnostics.names_in(Diagnostics.UNDEFINED_HANDLER)
	builtins = interp.diagnostics.names_in(Diagnostics.BUILTIN)
	# **The check that makes the two above worth anything, and it has to be shown
	# to be live.** The first version of this case called `getPref`, which the host
	# *does* bind -- so the call never reached the fall-through, nothing was
	# classified at all, and "is never filed as an undefined handler" passed
	# against an engine that had never been asked the question. That is exactly the
	# shape `porting-fidelity-verification` is about, and the fix is to assert the
	# probe arrived.
	var reached: Array = []
	for name in HOLE_PROBES:
		if builtins.has(str(name)):
			reached.append(str(name))
	h.check("at least one probe actually reached the fall-through",
		not reached.is_empty(),
		"of %s, reached: %s" % [", ".join(HOLE_PROBES),
			", ".join(PackedStringArray(reached))])
	# Each is in the reference's builtin table, so however this port answers it,
	# it must never be filed as a handler the movie failed to define -- that is the
	# classification a future abort would act on, and a hole in our table is not
	# the movie's fault.
	var misfiled: Array = []
	for name in HOLE_PROBES:
		if undefined.has(str(name)):
			misfiled.append(str(name))
	h.check("and no name the reference knows is filed as an undefined handler",
		misfiled.is_empty(), "misfiled: %s" % ", ".join(PackedStringArray(misfiled)))
	h.check("and the handler around them runs to its end",
		_is_seven(answer), "returned %s" % str(answer))
	h.complete(case)

	case = "abort unwinds the caller too, which is what the reference's flag does"
	h.begin(case)
	interp.reset_steps()
	answer = interp.call_handler("abortouter", [], probes)
	# `Lingo::execute`'s epilogue pops the whole callstack, so `abortouter`'s
	# `return 7` is not reached either. If this ever answers 7, the abort this port
	# already implements is one handler deep and the fidelity claim in `_call`'s
	# comment is wrong.
	h.check("a nested abort stops the handler that called it",
		not _is_seven(answer), "returned %s" % str(answer))
	h.complete(case)

	# Left in the sink on purpose, so the exit report below prints its
	# `undefined handlers:` line and this run exercises the one place on the
	# player's path that reads the category. `lingo_fault_sink.gd` says why it is
	# not a check: a harness cannot assert on stdout, and the line is a print.
	interp.reset_steps()
	interp.call_handler("undefprobe", [], probes)

	preview.queue_free()
	await process_frame
	quit(h.finish("an undefined handler call is told apart and reported"))


## Did the handler reach its `return 7`?
##
## Written out rather than as `int(answer) == 7` because **an aborted handler
## answers VOID and `int(null)` is not a cast, it is a runtime error** -- which
## ends `_init` before `quit()` and leaves the harness hanging rather than
## failing. Cost ten minutes of a held Godot lock to a check that was reporting
## the truth.
static func _is_seven(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) == 7
