extends SceneTree
## Where a name written by a handler actually lands.
##
##   godot --headless --script tools/lingo_scope_check.gd
##
## Three assertions, and each one covers a way a statement could run to
## completion and leave nothing behind — the failure mode that has no error, no
## stack and no symptom until something downstream reads VOID.
##
## 1. **A `global` written outside a handler declares the name for every handler
##    in that script** (`docs/LINGO_SURFACE.md` §7). The parser has always
##    collected those into `script["globals"]`; nothing read it, so a handler
##    whose only declaration was the script-level one treated the name as an
##    ordinary local and its assignment died with the frame.
##
## 2. **`myList.setaProp(#k, v)` is `setaProp(myList, #k, v)`** — D5's dot
##    spelling of a list command (§1.3, §5). Without it the dot form fell
##    through to the property *read*, which answers VOID and mutates nothing.
##
## 3. **`go(VOID)` navigates nowhere.** The reference's `func_goto` returns on a
##    VOID destination before it sets the skip-advance and freeze flags, so the
##    statement is not a jump to frame 0 — it is a jump that does not happen.
##
## The three met in `itamar-magichat`, which is why they are one file. Its
## `on startMovie` declares `global gFirstRun` at script level and fills the
## movie's configuration list with `gGlobalInfo.setaProp(...)`; both writes
## vanished, `GlobalInfo(#startFrame)` answered VOID, and the frame behaviour's
## `go(JumpFrame)` re-entered frame 0 on every tick for ever, with nothing on
## the clock, no error and a black stage.
##
## Cases 1 and 2 are title-agnostic: the Lingo below is written for this file and
## names nothing in any game. Case 3 boots whichever movie the config or `--root`
## points at and asserts only that a VOID destination moves nothing.

const Harness := preload("res://tools/lib/harness.gd")
## Preloaded rather than reached by `class_name`: a headless `--script` run
## resolves global classes out of the editor's script cache, and a class added
## since the last editor session fails there in a file nobody touched.
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")

## Script-level declarations, then handlers that never repeat them. `gCounter`
## is incremented rather than assigned so a port that reads the global and writes
## a local — the exact shape of the bug — is separated from one that does neither.
const SCOPED := """
global gShared, gCounter

on writeShared
  gShared = "kept"
end

on readShared
  return gShared
end

on bumpCounter
  gCounter = gCounter + 1
end

on writeLocal
  gPrivate = "lost"
  return gPrivate
end

on declaredInHandler
  global gInHandler
  gInHandler = "also kept"
end
"""

## The dot spellings, each written so the *receiver* has to change for the answer
## to be right — asserting the return value alone would pass on a port that
## copied the list.
const DOTTED := """
global gProps, gLine

on buildProps
  gProps = [:]
  gProps.setaProp(#alpha, 1)
  gProps.setaProp(#beta, 2)
  gProps.addProp(#gamma, 3)
end

on countProps
  return gProps.count()
end

on readProp
  return gProps.getaProp(#beta)
end

on dropProp
  gProps.deleteProp(#alpha)
end

on buildLine
  gLine = [1, 2]
  gLine.append(3)
  gLine.setAt(1, 9)
end

on readLine
  return gLine.getAt(1)
end

on notACommand
  return gProps.noSuchListCommand(1)
end
"""


func _init() -> void:
	var h := Harness.new()
	var compiler := Compiler.new()

	var scoped := compiler.compile_source(SCOPED, "ScopeCheck")
	var dotted := compiler.compile_source(DOTTED, "DotCheck")
	h.begin("the fixture compiles")
	h.check("the script-level fixture parses", not scoped.is_empty(),
		"" if scoped.is_empty() else "%d global(s) declared" % (scoped.get("globals", []) as Array).size())
	h.check("the dot-notation fixture parses", not dotted.is_empty(),
		"" if dotted.is_empty() else "%d handler(s)" % (dotted.get("handlers", []) as Array).size())
	h.complete("the fixture compiles")
	if scoped.is_empty() or dotted.is_empty():
		print("     line %d: %s" % [compiler.error_line, compiler.error])
		quit(h.finish("Lingo name scope"))
		return

	_script_level_globals(h, scoped)
	_dot_list_commands(h, dotted)
	await _go_void(h)

	quit(h.finish("Lingo name scope"))


## §7. The declaration is lexically outside the handler and binds inside it.
func _script_level_globals(h: Harness, script: Dictionary) -> void:
	var title := "a script-level `global` binds in every handler of the script (§7)"
	h.begin(title)

	var interp = Interpreter.new(null)
	interp.call_handler("writeShared", [], script)
	h.check("the assignment reached the movie's globals",
		str(interp.globals.get("gshared", "<unset>")) == "kept",
		"gShared = %s" % _show(interp.globals.get("gshared", null)))
	h.check("another handler of the same script reads it back",
		str(interp.call_handler("readShared", [], script)) == "kept",
		_show(interp.call_handler("readShared", [], script)))

	# Read-modify-write across two calls. A port that resolves the read to the
	# global and the write to a local answers 1 every time.
	interp.call_handler("bumpCounter", [], script)
	interp.call_handler("bumpCounter", [], script)
	h.check("a declared global accumulates across calls",
		_is_int(interp.globals.get("gcounter", null), 2),
		_show(interp.globals.get("gcounter", null)))

	# The other half: an *undeclared* name is still a local, or the fix has made
	# every assignment in the movie global.
	interp.call_handler("writeLocal", [], script)
	h.check("an undeclared name stays local to its handler",
		not interp.globals.has("gprivate"),
		"globals: %s" % str(interp.globals.keys()))

	# The in-handler spelling is the one that already worked; it must keep working.
	interp.call_handler("declaredInHandler", [], script)
	h.check("`global` inside a handler still binds",
		str(interp.globals.get("ginhandler", "<unset>")) == "also kept",
		_show(interp.globals.get("ginhandler", null)))
	h.complete(title)


## §1.3 and §5. `list.command(args)` and `command(list, args)` are one statement.
func _dot_list_commands(h: Harness, script: Dictionary) -> void:
	var title := "`list.command(...)` mutates the list, not a copy (§1.3, §5)"
	h.begin(title)

	var interp = Interpreter.new(null)
	interp.call_handler("buildProps", [], script)
	var props: Variant = interp.globals.get("gprops", null)
	h.check("the property list itself gained the pairs",
		typeof(props) == TYPE_DICTIONARY and (props as Dictionary).size() == 3,
		_show(props))
	h.check("`.count()` answers over the receiver",
		_is_int(interp.call_handler("countProps", [], script), 3),
		_show(interp.call_handler("countProps", [], script)))
	h.check("`.getaProp(#beta)` reads the value back",
		_is_int(interp.call_handler("readProp", [], script), 2),
		_show(interp.call_handler("readProp", [], script)))
	interp.call_handler("dropProp", [], script)
	props = interp.globals.get("gprops", null)
	h.check("`.deleteProp(#alpha)` removed it from the receiver",
		typeof(props) == TYPE_DICTIONARY and not (props as Dictionary).has("alpha"),
		_show(props))

	interp.call_handler("buildLine", [], script)
	var line: Variant = interp.globals.get("gline", null)
	h.check("`.append` and `.setAt` reach a linear list",
		typeof(line) == TYPE_ARRAY and (line as Array) == [9, 2, 3],
		_show(line))
	h.check("`.getAt(1)` answers the element",
		_is_int(interp.call_handler("readLine", [], script), 9),
		_show(interp.call_handler("readLine", [], script)))

	# A name no list command owns must still fall through to the property read
	# rather than being swallowed, or the arm has claimed the whole dot surface.
	h.check("a name that is not a list command is not claimed",
		interp.call_handler("notACommand", [], script) == null,
		_show(interp.call_handler("notACommand", [], script)))
	h.complete(title)


## `func_goto` with a VOID destination returns before it freezes anything.
func _go_void(h: Harness) -> void:
	var title := "`go(VOID)` moves the playhead nowhere and does not hold"
	h.begin(title)

	var preview: Node = (load("res://scenes/director_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await process_frame
	var host = preview.get("_host")
	if host == null:
		h.check("the player stood up with a Lingo host", false, "no host")
		h.complete(title)
		return

	# Somewhere other than frame 0, so "did not move" and "went to frame 0"
	# cannot look the same. Any frame will do; which one is the movie's business.
	for i in 8:
		preview.call("_advance")
		await process_frame
	var before := int(preview.get("_index"))
	preview.set("_held", false)
	preview.set("_jump_queued", false)

	host.call("call_builtin", "go", [null])
	h.check("the playhead did not move", int(preview.get("_index")) == before,
		"frame %d -> %d" % [before, int(preview.get("_index"))])
	h.check("no jump was queued", not bool(preview.get("_jump_queued")))
	h.check("the score was not frozen", not bool(preview.get("_held")))

	# And the diagnostic exists, because a destination that evaluated to nothing
	# is a movie-side gap somebody has to be able to find.
	var sink = preview.get("_interpreter").diagnostics
	var reported := false
	for entry in (sink.entries() as Array):
		if str((entry as Dictionary).get("name", "")).begins_with("go: destination"):
			reported = true
	h.check("the VOID destination was reported", reported,
		"%d diagnostic(s)" % int(sink.count()))
	h.complete(title)


## Type-strict, for the reason `tools/lingo_logic_check.gd` gives: a boolean and
## the integer 1 are the same condition and different values.
func _is_int(value: Variant, want: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) == want


func _show(value: Variant) -> String:
	if value == null:
		return "VOID"
	return "%s %s" % [type_string(typeof(value)), str(value)]
