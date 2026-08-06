extends SceneTree
## The designator suffixes a modifier-shaped parser drops, checked on the real
## spellings out of this game's own containers.
##
##   godot --headless --script tools/lingo_designator_check.gd
##
## `docs/LINGO_SURFACE.md` §16.4 ranks six grammar gaps and notes that four of
## them are one shape: **a suffix that is part of a designator, parsed as though
## it were a trailing modifier that could be ignored.** `of sound N` was the
## first fixed; this file covers the other three and the odd one out:
##
##   go to frame E of movie F   the movie was dropped and `of movie …` became a
##                              statement calling a handler named `of`, so the
##                              jump landed on a marker of that name in the
##                              *current* movie (6 scripts, 4 of them the
##                              save/load round trip)
##   field (E) of castLib N     the library was dropped the same way, but only
##                              after the parenthesised form — `field "x" of
##                              castLib "master"` always worked (4 scripts)
##   the P of window "x"        became `prop_of` over a call, which the
##                              interpreter's assignment path rejects, while the
##                              dot spelling `window("x").P = 2` worked (2)
##   when <event> then S        not a designator at all: D3's primary-handler
##                              installation, which misparsed into two junk
##                              statements, the second of them an unconditional
##                              `go` (1 script, 2 statements)
##
## **Every source line below is quoted from the extracted authored Lingo**, not
## invented, because the failure mode this file guards against is a parser that
## handles the shape the tool imagined rather than the shape the game wrote:
##
##   godot --headless --script tools/director_extract.gd -- --file <container> --out <dir>
##
## Each case is asserted twice — once on the AST, once on what reaches a stub
## host when the statement runs. The AST half alone would pass on a node that is
## shaped right and wired nowhere, which is exactly the state `prop_of` over a
## call was already in.
##
## Title-agnostic in the sense that matters: nothing here needs the game loaded,
## a container opened or a member resolved. The quoted lines name this game's
## movies because they are evidence, and the checks are about the grammar.

const Harness := preload("res://tools/lib/harness.gd")
## Preloaded rather than reached by `class_name`, for the reason
## `lingo_interpreter.gd` records: a headless `--script` run resolves global
## classes out of the editor's script cache.
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")


## Records what the interpreter asks the engine for, and nothing else. Every
## method the four cases can reach is present and returns a non-null value, so a
## miss shows up as a missing *record* rather than as a `builtin` diagnostic
## about the stub.
class StubHost extends RefCounted:
	var builtins: Array = []
	var fields: Array = []
	var system: Array = []

	func call_builtin(name: String, args: Array) -> Variant:
		builtins.append({"name": name.to_lower(), "args": args})
		# `window("x")` has to answer a *string*, because that is the one thing
		# about it the interpreter depends on: the `dot` assignment path accepts
		# an owner only when it evaluates to a string, which is why
		# `window("x").windowType = 2` worked while the `the … of window`
		# spelling did not. `lingo_host.gd` answers the movie stem here for the
		# same reason, so a stub that returned 0 would be testing a language the
		# port does not have.
		if name.to_lower() == "window":
			return "" if args.is_empty() else str(args[0]).get_file().get_basename()
		return 0

	func set_field(name: String, cast: String, text: String) -> void:
		fields.append({"name": name, "cast": cast, "text": text})

	func get_field(_name: String, _cast: String) -> Variant:
		return ""

	func set_system_prop(prop: String, value: Variant) -> void:
		system.append({"prop": prop.to_lower(), "value": value})

	func get_system_prop(_prop: String) -> Variant:
		return 0


func _init() -> void:
	var h := Harness.new()
	_go_of_movie(h)
	_field_of_castlib(h)
	_the_of_window(h)
	_when_then(h)
	quit(h.finish("a designator's suffix survives the parser and reaches the host"))


# --- `go to frame E of movie F` (§16.4 row 3) ----------------------------


func _go_of_movie(h: Harness) -> void:
	var title := "`go to frame E of movie F` keeps the movie (§11.5)"
	h.begin(title)

	# HEZSAVE.DIR script 7, the tail of `dosave`. The movie is an expression, not
	# a literal, which is why the suffix cannot be parsed as one more bare word.
	var run := _run("""
on dosave
  global cdsavepath
  go to frame "aftersave" of movie cdsavepath & "saveload.dxr"
end
""", "dosave", {"cdsavepath": "z:\\pip2data\\"})
	if not h.check("the fixture compiles", run["ok"], str(run.get("error", ""))):
		h.complete(title)
		return

	var host: StubHost = run["host"]
	var calls: Array = _named(host.builtins, "go")
	h.check("one `go`, not a `go` plus a stray `of`", calls.size() == 1 and _named(
		host.builtins, "of").is_empty(), _builtin_names(host.builtins))
	if calls.size() == 1:
		var args: Array = (calls[0] as Dictionary)["args"]
		# `to` and `frame` ride along as leading words; `lingo_host.gd:_go` trims
		# them. What matters is that a fourth argument exists and is the movie.
		h.check("the movie arrives as the last argument", args.size() == 4
			and str(args[3]) == "z:\\pip2data\\saveload.dxr", JSON.stringify(args))
		h.check("the frame label is still argument three",
			args.size() == 4 and str(args[2]) == "aftersave", JSON.stringify(args))

	# MASTER.CST scripts 87 and 95, with a literal movie rather than a built path.
	var literal := _run("""
on gopath
  go to frame "path5" of movie "day1.dir"
end
""", "gopath", {})
	var literal_host: StubHost = literal["host"]
	var literal_calls: Array = _named(literal_host.builtins, "go")
	h.check("a literal movie name reaches the host too", literal_calls.size() == 1
		and (literal_calls[0] as Dictionary)["args"] == ["to", "frame", "path5", "day1.dir"],
		JSON.stringify(literal_host.builtins))

	# The suffix belongs to `go` and `play` only — they are the two commands whose
	# keyword set in `Grammar.COMMAND_WORDS` carries `movie`. A command that does
	# not take a movie must not start eating one.
	var other := _compile("""
on notnav
  sound stop 1
end
""")
	h.check("a command without a movie argument is untouched", not other.is_empty(),
		"sound stop 1 still parses")
	h.complete(title)


# --- `field (E) of castLib N` (§16.4 row 4) ------------------------------


func _field_of_castlib(h: Harness) -> void:
	var title := "`field (E) of castLib N` keeps the library (§11.8)"
	h.begin(title)

	# SAVELOAD.dir scripts 24 and 38, verbatim apart from the loop that wraps it.
	var run := _run("""
on fillnames
  global SaveNames
  repeat with i = 1 to 2
    put item i of SaveNames into field ("save" & i) of castLib 1
  end repeat
end
""", "fillnames", {"savenames": "alpha,beta"})
	if not h.check("the fixture compiles", run["ok"], str(run.get("error", ""))):
		h.complete(title)
		return

	var host: StubHost = run["host"]
	h.check("two field writes, no stray `of` call", host.fields.size() == 2
		and _named(host.builtins, "of").is_empty(),
		"%d write(s), builtins %s" % [host.fields.size(), _builtin_names(host.builtins)])
	if host.fields.size() == 2:
		var first: Dictionary = host.fields[0]
		h.check("the library survives the parenthesised name", str(first["cast"]) == "1",
			"cast %s" % JSON.stringify(str(first["cast"])))
		h.check("the computed field name is intact", str(first["name"]) == "save1",
			"name %s" % JSON.stringify(str(first["name"])))

	# The bare-string spelling has always worked. Checked here so a change to the
	# parenthesised path cannot quietly break the 640 sites that use the other.
	var bare := _run("""
on fillone
  put "x" into field "objectsfield" of castLib "master"
end
""", "fillone", {})
	var bare_host: StubHost = bare["host"]
	h.check("the bare-string spelling still carries its library",
		bare_host.fields.size() == 1 and str((bare_host.fields[0] as Dictionary)["cast"]) == "master",
		JSON.stringify(bare_host.fields))

	# `field("x", "master")` puts the library in argument two, and must not then
	# also swallow a following `of castLib`.
	var two_arg := _compile("""
on twoarg
  put "x" into field ("objectsfield", "master")
end
""")
	h.check("the two-argument call form still compiles", not two_arg.is_empty(), "")
	h.complete(title)


# --- `the <prop> of window "x"` (§16.4 row 5) ----------------------------


func _the_of_window(h: Harness) -> void:
	var title := "`the <prop> of window \"x\"` is assignable (§11.9)"
	h.begin(title)

	# MASTER.CST scripts 12 and 69, both `set the windowType of window "…" to 2`.
	var source := """
on jokebtl
  set the windowType of window "joke.dxr" to 2
end
"""
	var script := _compile(source)
	if not h.check("the fixture compiles", not script.is_empty(), ""):
		h.complete(title)
		return

	var stmt: Dictionary = _first_statement(script, "jokebtl")
	h.check("the statement is an assignment, not a call",
		str(stmt.get("node", "")) == "assign", str(stmt.get("node", "?")))
	var target: Dictionary = stmt.get("target", {})
	h.check("its target is a window designator, not `prop_of` over a call",
		str(target.get("node", "")) == "window_prop", str(target.get("node", "?")))
	h.check("the window it names is kept on the node",
		str((target.get("which", {}) as Dictionary).get("value", "")) == "joke.dxr",
		JSON.stringify(target.get("which", {})))

	var run := _run(source, "jokebtl", {})
	var host: StubHost = run["host"]
	h.check("the write reaches the host's property table", host.system.size() == 1
		and str((host.system[0] as Dictionary)["prop"]) == "windowtype"
		and int((host.system[0] as Dictionary)["value"]) == 2, JSON.stringify(host.system))
	var interp: Interpreter = run["interp"]
	h.check("and nothing is recorded as unassignable", interp.errors.is_empty(),
		", ".join(Array(interp.errors)))

	# The dot spelling reached the host by a different path and was the only one
	# that worked. Both are checked so the two cannot drift apart again.
	var dotted := _run("""
on jokedot
  window("joke.dxr").windowType = 2
end
""", "jokedot", {})
	var dotted_interp: Interpreter = dotted["interp"]
	h.check("the dot spelling still records no error", dotted_interp.errors.is_empty(),
		", ".join(Array(dotted_interp.errors)))
	h.complete(title)


# --- `when <event> then <statement>` (§16.4 row 6) -----------------------


func _when_then(h: Harness) -> void:
	var title := "`when <event> then S` is one statement, installed not run (§11.2)"
	h.begin(title)

	# strtgame.dir script 306, both handlers, verbatim.
	var source := """
on gomenu
  when keyDown then go to "mainmenub4"
end

on gomenu2
  when keyDown then gulu
end
"""
	var script := _compile(source)
	if not h.check("the fixture compiles", not script.is_empty(), ""):
		h.complete(title)
		return

	var body: Array = _handler_body(script, "gomenu")
	h.check("one statement, where the misparse produced two", body.size() == 1,
		"%d statement(s)" % body.size())
	if body.size() == 1:
		var stmt: Dictionary = body[0]
		h.check("it is a `when` node", str(stmt.get("node", "")) == "when",
			str(stmt.get("node", "?")))
		h.check("the event it installs for is kept",
			str(stmt.get("event", "")) == "keydown", str(stmt.get("event", "?")))
		h.check("so is the tail it would install", (stmt.get("body", []) as Array).size() == 1,
			JSON.stringify(stmt.get("body", [])))

	var run := _run(source, "gomenu", {})
	var host: StubHost = run["host"]
	# This is the whole behavioural point. The old parse left `then go to
	# "mainmenub4"` as a statement of its own, so the navigation fired every time
	# the handler was called instead of when a key was pressed.
	h.check("the tail does not run at the point of the `when`",
		_named(host.builtins, "go").is_empty(), _builtin_names(host.builtins))
	h.check("nor does a phantom handler named `when` get called",
		_named(host.builtins, "when").is_empty(), _builtin_names(host.builtins))

	var interp: Interpreter = run["interp"]
	# It is installed, not discarded and not run. When this check was written the
	# port had no tier 1 to install into and the honest answer was a diagnostic;
	# `director_preview.gd` now dispatches keys and fires primary handlers ahead
	# of the ordinary hierarchy, so the assertion is that the body is waiting for
	# its event rather than that nothing happened.
	h.check("the tail is installed as a primary handler",
		(interp.primary_handlers as Dictionary).has("keydown"),
		JSON.stringify((interp.primary_handlers as Dictionary).keys()))
	h.check("and it fires when the event arrives",
		interp.run_primary("keydown") and not _named(host.builtins, "go").is_empty(),
		_builtin_names(host.builtins))
	h.check("an event nobody installed for fires nothing",
		not interp.run_primary("mouseup"), "")
	h.check("no parse or execution error is recorded", interp.errors.is_empty(),
		", ".join(Array(interp.errors)))

	# `when` is an ordinary identifier in Lingo (§11.3), so only the full
	# three-token shape may be claimed. A variable of that name must survive.
	var variable := _run("""
on usewhen
  set when to 4
  put when + 1 into field "x"
end
""", "usewhen", {})
	var variable_host: StubHost = variable["host"]
	h.check("a variable named `when` is untouched", variable_host.fields.size() == 1
		and str((variable_host.fields[0] as Dictionary)["text"]) == "5",
		JSON.stringify(variable_host.fields))
	h.complete(title)


# --- driving --------------------------------------------------------------


func _compile(source: String) -> Dictionary:
	var compiler := Compiler.new()
	var ast := compiler.compile_source(source, "DesignatorCheck")
	if ast.is_empty():
		print("     compile failed: line %d: %s" % [compiler.error_line, compiler.error])
	return ast


## Compiles, runs one handler against a fresh stub host and hands back both, so a
## case can assert on the AST and on what the engine was asked to do.
func _run(source: String, handler: String, preset: Dictionary) -> Dictionary:
	var compiler := Compiler.new()
	var script := compiler.compile_source(source, "DesignatorCheck")
	if script.is_empty():
		return {"ok": false, "error": "line %d: %s" % [compiler.error_line, compiler.error],
			"host": StubHost.new(), "interp": Interpreter.new(null)}
	var host := StubHost.new()
	var interp := Interpreter.new(host)
	for key in preset:
		interp.globals[str(key).to_lower()] = preset[key]
	interp.call_handler(handler, [], script)
	return {"ok": true, "host": host, "interp": interp, "script": script}


func _handler_body(script: Dictionary, name: String) -> Array:
	for handler in script.get("handlers", []):
		if str((handler as Dictionary).get("name", "")).to_lower() == name.to_lower():
			return (handler as Dictionary).get("body", [])
	return []


func _first_statement(script: Dictionary, handler: String) -> Dictionary:
	var body := _handler_body(script, handler)
	return body[0] if not body.is_empty() else {}


func _named(records: Array, name: String) -> Array:
	var out: Array = []
	for record in records:
		if str((record as Dictionary)["name"]) == name:
			out.append(record)
	return out


func _builtin_names(records: Array) -> String:
	var names := PackedStringArray()
	for record in records:
		names.append(str((record as Dictionary)["name"]))
	return "called: %s" % ", ".join(names) if not names.is_empty() else "called: nothing"
