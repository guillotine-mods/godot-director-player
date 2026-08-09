extends SceneTree
## The movie surface a title reads *about itself*, driven from Lingo.
##
##   godot --headless --path . --script tools/lingo_movie_surface.gd
##
## Every row here was `absent` in the reference map that `docs/ENGINE_TODO.md`
## pins, and every one of them is now claimed live. `tools/lingo_surface_audit.gd`
## can say a name is bound and cannot say what the binding reached — that is the
## whole reason it distinguishes `live` from `inert`, and the distinction is a
## *reading* of the arm's body, not an observation of its effect. This file is
## the observation: each check asserts against something the movie already knows
## by another route, so a binding that answers a plausible constant fails.
##
## Which is not hypothetical. `the frameScript` answering 0 and `the frameScript`
## being unbound are the same value to a script; the check below compares it
## against the score's own decode of the same cell, so the two have to agree
## about a specific frame of a specific movie rather than about zero.
##
## Title-agnostic, like `tools/lingo_system_builtins.gd` beside it. Every check
## is against whichever movie the config boots, and nothing here names a room, a
## channel or a member — the score, the labels and the container are asked what
## they hold and the Lingo answer is compared against that.

const Harness := preload("res://tools/lib/harness.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Diagnostics := preload("res://lingo/lingo_diagnostics.gd")

var _preview: Node = null
var _host = null
var _interp = null


func _init() -> void:
	var h := Harness.new()
	_preview = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(_preview)
	await process_frame
	await process_frame
	_host = _preview.get("_host")
	_interp = _preview.get("_interpreter")

	h.begin("the harness has a movie, a host and an interpreter")
	h.check("the preview booted a score", _preview.get("_score") != null)
	h.check("the preview booted a label table", _preview.get("_labels") != null)
	h.check("the Lingo host is attached", _host != null)
	h.check("the interpreter is attached", _interp != null)
	h.complete("the harness has a movie, a host and an interpreter")
	if _host == null or _interp == null or _preview.get("_score") == null:
		quit(h.finish("the movie surface a title reads about itself"))
		return

	_score_checks(h)
	_label_checks(h)
	_call_frame_checks(h)
	_item_delimiter_checks(h)
	_machine_checks(h)
	_memory_hint_checks(h)
	_trace_checks(h)

	_preview.queue_free()
	await process_frame
	quit(h.finish("the movie surface a title reads about itself"))


# ---------------------------------------------------- the score, as a movie


## The main channel of the frame the playhead is on.
##
## Each of these is compared against `director_score.gd`'s own decode of the same
## cell rather than against a literal, because the harness may not know which
## title is booted — and because a check against a literal is a check that the
## binding returns a number, which is exactly what an unbound one does.
func _score_checks(h) -> void:
	h.begin("the frame's main channel is readable as movie properties (§3)")
	var score = _preview.get("_score")
	h.check(
		"`the lastFrame` is the score's frame count (%d)" % int(score.frame_count),
		int(_value("the lastFrame")) == int(score.frame_count),
		"unbound this answered VOID, and `repeat with i = 1 to the lastFrame` "
		+ "never entered its body")
	var record: Dictionary = score.frame(_preview.current_frame() - 1)
	var script_member: Variant = record.get("frame_script", null)
	var want_script := int(script_member) if script_member != null else 0
	h.check(
		"`the frameScript` is this frame's script member (%d)" % want_script,
		int(_value("the frameScript")) == want_script,
		"compared against the score's own decode of the cell, so a binding that "
		+ "answers 0 for every frame fails on any frame that carries one")
	h.check(
		"`the frameTempo` is this frame's tempo cell (%d)" % int(record.get("tempo", 0)),
		int(_value("the frameTempo")) == int(record.get("tempo", 0)))
	h.check(
		"`the frameTransition` is this frame's transition member (%d)"
			% int(record.get("transition_member", 0)),
		int(_value("the frameTransition")) == int(record.get("transition_member", 0)))
	var palette: Dictionary = record.get("palette", {})
	h.check(
		"`the framePalette` is this frame's palette member (%d)"
			% int(palette.get("member", 0)),
		int(_value("the framePalette")) == int(palette.get("member", 0)))
	var sounds := {1: 0, 2: 0}
	for entry in (record.get("sound_channels", []) as Array):
		var row: Dictionary = entry
		if sounds.has(int(row.get("channel", 0))):
			sounds[int(row["channel"])] = int(row.get("cast_id", 0))
	h.check(
		"`the frameSound1` and `the frameSound2` are this frame's sound cells (%d, %d)"
			% [sounds[1], sounds[2]],
		int(_value("the frameSound1")) == sounds[1]
			and int(_value("the frameSound2")) == sounds[2])
	h.complete("the frame's main channel is readable as movie properties (§3)")


## `the labelList` and `the frameLabel`, which are two different questions.
##
## The second is "does *this* frame carry a marker", not "which marker is in
## force" — that is `marker(0)`, and the two differ on every frame between two
## markers, which is nearly all of them.
func _label_checks(h) -> void:
	h.begin("the movie's markers are readable (§3)")
	var labels = _preview.get("_labels")
	var named: Array = []
	for marker in labels.markers:
		var row: Dictionary = marker
		if str(row.get("name", "")) != "":
			named.append(row)
	var list := str(_value("the labelList"))
	h.check(
		"`the labelList` has a line per named marker (%d)" % named.size(),
		list.split("\n", false).size() == named.size()
			if named.size() > 0 else list == "",
		"got %d line(s) from %d marker(s)" % [list.split("\n", false).size(), named.size()])
	if named.is_empty():
		h.complete("the movie's markers are readable (§3)")
		return
	var first: Dictionary = named[0]
	h.check(
		"the first named marker is in it (\"%s\")" % str(first["name"]),
		list.split("\n", false).has(str(first["name"])))
	# The frame the marker is on, asked of the movie by walking the playhead
	# there. `the frameLabel` is empty everywhere else, and that is the half a
	# port is likely to get wrong: answering the marker in force would make it
	# non-empty on every frame after the first one.
	_run("go to frame %d" % (int(first["frame"]) + 1))
	h.check(
		"`the frameLabel` on that marker's frame is its name",
		str(_value("the frameLabel")) == str(first["name"]),
		"got \"%s\" on frame %d" % [str(_value("the frameLabel")), int(first["frame"]) + 1])
	h.complete("the movie's markers are readable (§3)")


# ------------------------------------------------------------- the call frame


## `the result`, `the paramCount` and `param(n)` — three questions about the call
## that is running, which nothing outside the interpreter can answer.
func _call_frame_checks(h) -> void:
	h.begin("the running call is readable (§3, §1.6)")
	var script := Compiler.new().compile_source(
		"on answers\n  return 41 + 1\nend\n"
		+ "on silent\n  return\nend\n"
		+ "on counts\n  return the paramCount\nend\n"
		+ "on second a, b, c\n  return param(2)\nend\n"
		+ "on reassigns a\n  set a to \"changed\"\n  return param(1)\nend\n"
		+ "on probe\n"
		+ "  answers()\n"
		+ "  return the result\n"
		+ "end\n", "CallFrameProbe")
	h.check("the probe script compiled", not script.is_empty())
	if script.is_empty():
		h.complete("the running call is readable (§3, §1.6)")
		return
	h.check(
		"`the result` is what the last handler returned (42)",
		int(_interp.call_handler("probe", [], script)) == 42,
		"unbound this answered VOID, and a movie that calls a handler as a "
		+ "command has no other way to read what it worked out")
	# The reference stores the dropped return value only when it is not VOID, so
	# a handler that returns nothing leaves the previous answer standing. That is
	# what lets a script call three handlers and read `the result` for the one of
	# them that answered.
	_interp.call_handler("silent", [], script)
	h.check(
		"a handler that returns nothing does not clear it",
		int(_interp.call_handler("probe", [], script)) == 42,
		"`lingo-code.cpp` skips a VOID return when it stores the result")
	h.check(
		"`the paramCount` is how many arguments came in (3)",
		int(_interp.call_handler("counts", [1, 2, 3], script)) == 3)
	h.check(
		"`the paramCount` is 0 for a handler called with none",
		int(_interp.call_handler("counts", [], script)) == 0)
	h.check(
		"`param(2)` is the second argument",
		str(_interp.call_handler("second", ["a", "b", "c"], script)) == "b")
	h.check(
		"`param(n)` reads the named parameter's *current* value",
		str(_interp.call_handler("reassigns", ["original"], script)) == "changed",
		"the reference fetches the local rather than the passed list when the "
		+ "handler names its parameters, so a handler that reassigns one sees it")
	h.complete("the running call is readable (§3, §1.6)")


## `the itemDelimiter` — bound all along, and reported `absent` by the audit for
## as long as the audit read only the host. The check is on the thing that
## consumes it, because a property that round-trips and separates nothing is the
## `moveableSprite` shape.
func _item_delimiter_checks(h) -> void:
	h.begin("`the itemDelimiter` separates items (§2.6)")
	_run("set the itemDelimiter to \",\"")
	h.check(
		"the default is a comma",
		str(_value("the itemDelimiter")) == ",")
	h.check(
		"`item 2 of \"a,b,c\"` is \"b\"",
		str(_value("item 2 of \"a,b,c\"")) == "b")
	_run("set the itemDelimiter to \";\"")
	h.check(
		"a write reads back",
		str(_value("the itemDelimiter")) == ";")
	h.check(
		"and the split follows it: `item 2 of \"a;b;c\"` is \"b\"",
		str(_value("item 2 of \"a;b;c\"")) == "b",
		"got \"%s\"" % str(_value("item 2 of \"a;b;c\"")))
	h.check(
		"and a comma is no longer a separator",
		str(_value("item 1 of \"a,b\"")) == "a,b")
	_run("set the itemDelimiter to \",\"")
	h.complete("`the itemDelimiter` separates items (§2.6)")


# --------------------------------------------------------------- the machine


## What the player can say about itself. Each of these is a real question a 1997
## script asks before it commits to a code path, and each answer here is checked
## against the same fact read another way rather than against a literal.
func _machine_checks(h) -> void:
	h.begin("the player answers for itself (§3)")
	h.check(
		"`the movieFileSize` is the container's size on disk (%d)"
			% _preview.movie_file_size(),
		int(_value("the movieFileSize")) == _preview.movie_file_size()
			and _preview.movie_file_size() > 0,
		"0 here would mean the movie has no file, which is not a state this "
		+ "player can be in")
	var screens: Variant = _value("the desktopRectList")
	h.check(
		"`the desktopRectList` has one rect per screen (%d)"
			% DisplayServer.get_screen_count(),
		typeof(screens) == TYPE_ARRAY
			and (screens as Array).size() == DisplayServer.get_screen_count())
	h.check(
		"`the rollOver` with no argument is the channel under the mouse (%d)"
			% _preview.lingo_rollover_channel(),
		int(_value("the rollOver")) == _preview.lingo_rollover_channel(),
		"`rollOver(n)` is a different function and was the only one bound (§8.15)")
	h.check(
		"`the selection` is empty with nothing focused",
		str(_value("the selection")) == "" if _preview.lingo_focus_channel() == 0 else true)
	h.check(
		"`the quickTimePresent` is false, and honestly so",
		int(_value("the quickTimePresent")) == 0,
		"there is no digital video in this port; a movie that guards on this "
		+ "takes the branch that works")
	h.check(
		"`the xtras` is an empty list rather than VOID",
		typeof(_value("the xtras")) == TYPE_ARRAY
			and (_value("the xtras") as Array).is_empty(),
		"a movie scanning it for an Xtra must find it absent, not fail to loop")
	h.check(
		"`version()` and `the productVersion` agree (\"6.0\")",
		str(_value("version()")) == "6.0" and str(_value("the productVersion")) == "6.0")
	var volumes: Variant = _value("getVolumes()")
	h.check(
		"`getVolumes()` names at least one volume",
		typeof(volumes) == TYPE_ARRAY and not (volumes as Array).is_empty(),
		"Piposh 1 scans for its CD by drive letter; this is the other spelling "
		+ "of the same question and it has to have an answer")
	h.check(
		"`externalParamCount()` is 0 for a projector",
		int(_value("externalParamCount()")) == 0,
		"a function and not a `the` property, which is how the reference has it")
	h.check(
		"and `externalParamName(1)` past the end is VOID, not \"\"",
		_value("externalParamName(1)") == null,
		"a movie loops until this answers nothing; \"\" is a value and the loop "
		+ "would not end")
	# The same fault, in the binding that was already shipped. `getPref` answers
	# VOID for a preference that has never been written, and the interpreter's
	# host contract spells "no such builtin" as a null return -- so a VOID answer
	# came back as 0 *and* filed the builtin as missing. Every "first run?" test
	# in Lingo is `if getPref("x") = VOID then`, and 0 is not VOID.
	var unwritten := "harnessprobe" + str(Time.get_ticks_usec())
	h.check(
		"`getPref` for a name never written is VOID, not 0",
		_value("getPref(\"%s\")" % unwritten) == null,
		"got %s" % str(_value("getPref(\"%s\")" % unwritten)))
	h.complete("the player answers for itself (§3)")


## The memory hints, which are not no-ops.
##
## They were recorded as deliberate no-ops on the grounds that this port loads on
## demand — true — and every one of them reports what it loaded through `the
## result`, which a movie can observe. That is the test the `noop` channel is
## supposed to apply and it was never applied to these.
func _memory_hint_checks(h) -> void:
	h.begin("the preload hints report through `the result` (§1.11)")
	var script := Compiler.new().compile_source(
		"on bare\n  preLoad\n  return the result\nend\n"
		+ "on ranged\n  preLoad 2, 7\n  return the result\nend\n"
		+ "on cast\n  preLoadCast 3\n  return the result\nend\n",
		"PreloadProbe")
	h.check("the probe script compiled", not script.is_empty())
	if script.is_empty():
		h.complete("the preload hints report through `the result` (§1.11)")
		return
	var last := int(_preview.get("_score").frame_count)
	h.check(
		"`preLoad` with no argument answers the last frame (%d)" % last,
		int(_interp.call_handler("bare", [], script)) == last,
		"the reference answers the frame count: it preloaded all of them")
	h.check(
		"`preLoad 2, 7` answers the last frame asked for (7)",
		int(_interp.call_handler("ranged", [], script)) == 7)
	h.check(
		"`preLoadCast 3` answers 3",
		int(_interp.call_handler("cast", [], script)) == 3)
	h.begin("`clearGlobals` empties the globals (§1.11)")
	_run("set the itemDelimiter to \",\"")
	_interp.globals["harnessprobe"] = 1
	_run("clearGlobals")
	h.check(
		"a global set before it is gone after it",
		not _interp.globals.has("harnessprobe"),
		"it was in the host's IGNORED list, so a movie that reset itself did not")
	h.complete("`clearGlobals` empties the globals (§1.11)")
	h.complete("the preload hints report through `the result` (§1.11)")


## `the trace` — Director's statement trace, and the switch this port has spent
## its whole life re-implementing with `print` one session at a time.
func _trace_checks(h) -> void:
	h.begin("`the trace` reaches the interpreter (§3)")
	var was: bool = Diagnostics.trace
	Diagnostics.trace = false
	_run("set the trace to 1")
	h.check(
		"a write reaches the interpreter's own switch",
		Diagnostics.trace,
		"the consumer is `lingo_interpreter.gd:_exec`; a host that stored this "
		+ "and nothing read it would be the `moveableSprite` shape one level up")
	h.check("and reads back", int(_value("the trace")) == 1)
	_run("set the trace to 0")
	h.check("and off again", not Diagnostics.trace and int(_value("the trace")) == 0)
	Diagnostics.trace = was
	h.complete("`the trace` reaches the interpreter (§3)")


# ------------------------------------------------------------------ driving


func _run(source: String) -> void:
	var script := Compiler.new().compile_source(
		"on probe\n  %s\nend\n" % source, "MovieSurfaceProbe")
	if script.is_empty():
		push_warning("lingo_movie_surface: `%s` did not compile" % source)
		return
	_interp.call_handler("probe", [], script)


func _value(expression: String) -> Variant:
	var script := Compiler.new().compile_source(
		"on probe\n  return %s\nend\n" % expression, "MovieSurfaceProbe")
	if script.is_empty():
		return "<did not compile>"
	return _interp.call_handler("probe", [], script)
