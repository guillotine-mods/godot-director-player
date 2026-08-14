extends SceneTree
## Which bucket an unresolved name lands in, and why the difference matters.
##
##   godot --headless --script tools/lingo_local_diagnosis.gd
##
## The interpreter files a name it could not resolve under one of two categories
## (`lingo/lingo_diagnostics.gd`):
##
##   `unset_variable`  the script's own local, read on a path that had not
##                     assigned it yet. The movie's business; nothing owed.
##   `unbound_name`    nothing in the port answers to it. A gap in this engine.
##
## **Only the second is a gap list, and it is only useful if the first stays out
## of it.** `itamar-park`'s boot reports three names that look like missing
## builtins and are not — `mynewtext`, `tmpsinglegame`, `garcadehiscorelist` —
## next to one that genuinely is: `movetofront`, which `docs/LINGO_SURFACE.md`
## §7.4 lists and this port does not bind. Three parts noise to one part signal is
## how a real gap goes unread for a year.
##
## `myNewText` is the one that was misfiled, and the reason is worth an assertion
## rather than a comment. `getDataLines` (`MovieScript 1 - Param Handlers`) builds
## the parsed `arcade.ini` up **entirely through chunk assignment**:
##
##     put myLine into line myLinesCounter of myNewText
##     myLength = the number of lines in myNewText
##
## The target's node is `chunk`, not `var`, so the scan that asks "does this
## handler assign this name anywhere" answered no and the read was filed as a
## name the port owes. It is the handler's own local, one statement earlier.
##
## Title-agnostic: the Lingo below is written for this file and names nothing in
## any game.

const Harness := preload("res://tools/lib/harness.gd")
## Preloaded rather than reached by `class_name`, for the reason
## `tools/lingo_scope_check.gd` gives at its own preload: a headless `--script`
## run resolves global classes out of the editor's script cache, and a class
## added since the last editor session fails there in a file nobody touched.
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
const Diagnostics := preload("res://lingo/lingo_diagnostics.gd")

## Each handler reads a name before assigning it, and the four differ only in the
## *shape* of the assignment that makes the name a local. `neverAssigned` is the
## control: nothing in the handler writes it, so it is the one read that really
## does resolve nowhere.
const FIXTURE := """
on chunkTarget
  before = the number of lines in myText
  put "a" into line 1 of myText
  return before
end

on nestedChunkTarget
  before = myDeep
  put "b" into char 1 of line 2 of myDeep
  return before
end

on indexTarget
  before = myList
  myList[1] = 5
  return before
end

on plainTarget
  before = myPlain
  myPlain = 7
  return before
end

on branchTarget
  if 0 then
    myBranch = 1
  end if
  return voidP(myBranch)
end

on neverAssigned
  return noSuchNameAnywhere
end
"""

## The handlers whose name must be filed as the script's own local, paired with
## the name each of them reads early.
const LOCALS := [
	["chunkTarget", "mytext"],
	["nestedChunkTarget", "mydeep"],
	["indexTarget", "mylist"],
	["plainTarget", "myplain"],
	["branchTarget", "mybranch"],
]


func _names(interp, category: String) -> Array:
	var out: Array = []
	for name in interp.diagnostics.names_in(category):
		out.append(str(name))
	return out


func _init() -> void:
	var h := Harness.new()
	var compiler := Compiler.new()
	var script := compiler.compile_source(FIXTURE, "LocalDiagnosis")

	var title := "the fixture compiles"
	h.begin(title)
	h.check("the fixture parses", not script.is_empty(),
		"" if script.is_empty() else "%d handler(s)" % (script.get("handlers", []) as Array).size())
	h.complete(title)
	if script.is_empty():
		print("     line %d: %s" % [compiler.error_line, compiler.error])
		quit(h.finish("Lingo local diagnosis"))
		return

	# One interpreter per handler so each assertion reads only its own handler's
	# report. Sharing one would let a later handler's entry satisfy an earlier
	# handler's check, which is the shape of assertion that cannot fail.
	title = "a name the handler assigns is its own local, whatever the target's shape"
	h.begin(title)
	for pair in LOCALS:
		var handler: String = str(pair[0])
		var name: String = str(pair[1])
		var interp = Interpreter.new(null)
		interp.call_handler(handler, [], script)
		var unset := _names(interp, Diagnostics.UNSET_VARIABLE)
		var unbound := _names(interp, Diagnostics.UNBOUND_NAME)
		h.check("%s: `%s` is filed as an unset local" % [handler, name],
			unset.has(name),
			"unset=%s unbound=%s" % [str(unset), str(unbound)])
		h.check("%s: `%s` is NOT filed as a name the port owes" % [handler, name],
			not unbound.has(name),
			"unbound=%s" % str(unbound))
	h.complete(title)

	# The control. Without it every assertion above is satisfied by an engine that
	# simply stopped filing anything under `unbound_name` -- which would empty the
	# gap list rather than clean it, and look identical in a diff.
	title = "a name nothing assigns is still reported as a gap"
	h.begin(title)
	var control = Interpreter.new(null)
	control.call_handler("neverAssigned", [], script)
	var control_unbound := _names(control, Diagnostics.UNBOUND_NAME)
	h.check("`nosuchnameanywhere` is filed as a name the port owes",
		control_unbound.has("nosuchnameanywhere"),
		"unbound=%s unset=%s" % [str(control_unbound),
			str(_names(control, Diagnostics.UNSET_VARIABLE))])
	h.complete(title)

	# The categories are a diagnostic and not a behaviour, so the other half of
	# the claim is that the *values* did not move with the classification.
	#
	# Asserted per handler against the answer Director gives, rather than against
	# a single "is it VOID-ish" predicate -- the first version of this block used
	# one and failed two of its own cases for being right: `the number of lines in
	# <VOID>` is 1, because an empty value is one empty line, and `voidP(x)` of an
	# unassigned name is 1 because that is what it is for. A predicate loose
	# enough to accept both would have accepted anything.
	title = "reading before assignment answers what it did"
	h.begin(title)
	var expected := {
		"chunkTarget": 1,           # `the number of lines in <VOID>`
		"nestedChunkTarget": null,  # the value itself
		"indexTarget": null,
		"plainTarget": null,
		"branchTarget": 1,          # `voidP(<unassigned>)`
	}
	for handler2 in expected.keys():
		var interp2 = Interpreter.new(null)
		var answer: Variant = interp2.call_handler(str(handler2), [], script)
		var want: Variant = expected[handler2]
		var right := (answer == null) if want == null \
			else (typeof(answer) == TYPE_INT and int(answer) == int(want))
		h.check("%s answers %s" % [handler2, "VOID" if want == null else str(want)],
			right, "%s %s" % [type_string(typeof(answer)), str(answer)])
	h.complete(title)

	quit(h.finish("Lingo local diagnosis"))
