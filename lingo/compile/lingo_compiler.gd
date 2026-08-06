class_name LingoCompiler
extends RefCounted
## Lingo source to the AST the interpreter runs. The only entry point.
##
## Everything else in `lingo/compile/` is reachable through this: callers give it
## text and a script name and get back the same Dictionary shape
## `tools/lingo_compile.py --emit` writes into `data/lingo/`, so the interpreter
## cannot tell which compiler produced it. That is the whole design goal — the
## Python is being retired, and the only way to retire it safely is for the two
## to be indistinguishable to the thing that consumes them.

const Lexer := preload("res://lingo/compile/lingo_lexer.gd")
const Parser := preload("res://lingo/compile/lingo_parser.gd")

var error := ""
var error_line := 0


## `{}` on failure, with the reason in `error` and the source line in
## `error_line`. A script that fails to compile is a handler the game will not
## run, so callers should report the count rather than skipping quietly.
func compile_source(source: String, script_name: String) -> Dictionary:
	error = ""
	error_line = 0

	var lexer := Lexer.new()
	if not lexer.tokenize(source):
		error = lexer.error
		error_line = lexer.error_line
		return {}

	var parser := Parser.new()
	var ast := parser.parse(lexer, script_name)
	if parser.error != "":
		error = parser.error
		error_line = parser.error_line
		return {}
	return ast


## Every script-bearing member of one cast, as the bundle
## `LingoInterpreter.load_bundle` expects: `{movie, cast, scripts}`.
##
## Script keys reproduce ProjectorRays' naming, because
## `lingo_interpreter.find_script_by_member` parses that string and `load_bundle`
## keys movie scripts off a `moviescript` prefix. The convention: a type-11
## member is a `BehaviorScript` when its specific block says 1 and a
## `MovieScript` when it says 3; any other member carrying script text is a
## `CastScript`; a named member appends " - <name>".
func compile_cast(cast, movie_name: String, cast_name: String) -> Dictionary:
	var scripts: Dictionary = {}
	var failures: Array = []
	for number in cast.member_numbers():
		var m: Dictionary = cast.member(number)
		var source := str(m.get("source", ""))
		if source.strip_edges() == "":
			continue
		var key := script_key(m, number)
		var ast := compile_source(source, key)
		if ast.is_empty():
			failures.append("%s: line %d: %s" % [key, error_line, error])
			continue
		scripts[key] = ast
	error = "; ".join(failures) if not failures.is_empty() else ""
	return {"movie": movie_name, "cast": cast_name, "scripts": scripts}


static func script_key(member: Dictionary, number: int) -> String:
	var kind := "CastScript"
	if int(member.get("type", 0)) == 11:
		kind = "MovieScript" if int(member.get("script_type", 1)) == 3 else "BehaviorScript"
	var key := "%s %d" % [kind, number]
	var name := str(member.get("name", ""))
	if name != "":
		key += " - %s" % name
	return key
