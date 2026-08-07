extends SceneTree
## `and` and `or` evaluate both operands, always.
##
##   godot --headless --script tools/lingo_logic_check.gd
##
## `docs/LINGO_SURFACE.md` §2.3 says they short-circuit and §17 corrects it: they
## are single opcodes that pop two operands (§13), and the code generator emits
## no jump for either (§14). This port short-circuited until the change this file
## covers.
##
## Why it is worth a harness of its own rather than a line in a table. In Lingo a
## bare identifier that resolves to nothing else is a **parameterless handler
## call** — `lingo_interpreter.gd:_read_var` ends in exactly that fall-through,
## and §16.4 records 44 sites of `updateStage` alone reaching it. So an operand
## that reads like a variable can be `cursorfunk`, `talkproc` or `soundspath`,
## and a short-circuiting interpreter stops calling them without anything in the
## AST looking like a call. Asserting the *value* of `0 and x` proves nothing:
## both implementations answer 0. The only thing that separates them is whether
## the right side ran, so every case below is written as an observable effect
## with the answer checked alongside.
##
## Title-agnostic, like `tools/lingo_builtins_check.gd`. The Lingo below is
## written for this file and names nothing in any game.

const Harness := preload("res://tools/lib/harness.gd")
## Preloaded rather than reached by `class_name`: a headless `--script` run
## resolves global classes out of the editor's script cache, and a class added
## since the last editor session fails there in a file nobody touched.
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")

## One handler per case, each arranged so the right operand leaves a mark.
##
## `mark1`/`mark2` append to a global rather than counting, so the trace records
## *order* as well as arrival — §14 settles that evaluation is left, then right,
## then operate, and a port that evaluated right-first would pass a counting test.
const SOURCE := """
on mark1
  global trail
  put trail & "1" into trail
  return 1
end

on mark2
  global trail
  put trail & "2" into trail
  return 1
end

on markzero
  global trail
  put trail & "z" into trail
  return 0
end

on falseAnd
  return 0 and mark1()
end

on trueOr
  return 1 or mark1()
end

on trueAnd
  return 1 and mark1()
end

on falseOr
  return 0 and 0 or markzero()
end

on bothSides
  return mark1() and mark2()
end

on operandNotResult
  return 5 and 7
end

on orOperandNotResult
  return 0 or 7
end

on voidIsFalse
  return unsetglobalname and 1
end

on stringOperands
  return "abc" and 1
end
"""


func _init() -> void:
	var h := Harness.new()
	var compiler := Compiler.new()
	var script := compiler.compile_source(SOURCE, "LogicCheck")

	h.begin("the fixture compiles")
	h.check("the harness's own Lingo parses", not script.is_empty(),
		"" if script.is_empty() else "%d handler(s)" % (script.get("handlers", []) as Array).size())
	h.complete("the fixture compiles")
	if script.is_empty():
		print("     line %d: %s" % [compiler.error_line, compiler.error])
		quit(h.finish("`and` and `or` evaluate both operands"))
		return

	# --- the finding itself ------------------------------------------------

	var title := "both operands run, whatever the other answered (§13, §17)"
	h.begin(title)

	var a := _run(script, "falseAnd")
	h.check("`0 and mark1()` still calls mark1", str(a["trail"]) == "1",
		"trail %s" % JSON.stringify(str(a["trail"])))
	h.check("`0 and mark1()` is 0", _is_int(a["value"], 0), _show(a["value"]))

	var b := _run(script, "trueOr")
	h.check("`1 or mark1()` still calls mark1", str(b["trail"]) == "1",
		"trail %s" % JSON.stringify(str(b["trail"])))
	h.check("`1 or mark1()` is 1", _is_int(b["value"], 1), _show(b["value"]))

	h.complete(title)

	# --- order, and the cases a short-circuiting port also gets right -------

	title = "evaluation is left, then right, then operate (§14)"
	h.begin(title)
	var c := _run(script, "bothSides")
	h.check("`mark1() and mark2()` runs both, left first", str(c["trail"]) == "12",
		"trail %s" % JSON.stringify(str(c["trail"])))
	h.check("`mark1() and mark2()` is 1", _is_int(c["value"], 1), _show(c["value"]))

	var d := _run(script, "trueAnd")
	h.check("`1 and mark1()` calls mark1 (true either way)", str(d["trail"]) == "1",
		"trail %s" % JSON.stringify(str(d["trail"])))
	h.check("`1 and mark1()` is 1", _is_int(d["value"], 1), _show(d["value"]))

	# `and` binds tighter than `or` in this parser (§16.2 records the divergence
	# from ScummVM's one-level ranking), so this reads as `(0 and 0) or markzero()`
	# — a false left with a right that runs and answers 0.
	var e := _run(script, "falseOr")
	h.check("a false `or` still evaluates its right side", str(e["trail"]) == "z",
		"trail %s" % JSON.stringify(str(e["trail"])))
	h.check("`(0 and 0) or markzero()` is 0", _is_int(e["value"], 0), _show(e["value"]))
	h.complete(title)

	# --- the result is a truth value, not an operand ------------------------

	title = "the answer is the integer 0 or 1, never the operand (§13)"
	h.begin(title)
	var f := _run(script, "operandNotResult")
	h.check("`5 and 7` is 1, not 7", _is_int(f["value"], 1), _show(f["value"]))
	var g := _run(script, "orOperandNotResult")
	h.check("`0 or 7` is 1, not 7", _is_int(g["value"], 1), _show(g["value"]))
	var i := _run(script, "voidIsFalse")
	h.check("VOID and 1 is 0 (§2.8: VOID is false)", _is_int(i["value"], 0), _show(i["value"]))
	var j := _run(script, "stringOperands")
	h.check("a non-numeric string is false (§2.8)", _is_int(j["value"], 0), _show(j["value"]))
	h.complete(title)

	quit(h.finish("`and` and `or` evaluate both operands"))


## Runs one handler on a fresh interpreter with no host, and reports both the
## returned value and the trail the operands left. A fresh interpreter per case
## because `trail` is a global and a shared one would let case order decide the
## answers.
func _run(script: Dictionary, handler: String) -> Dictionary:
	var interp := Interpreter.new(null)
	interp.globals["trail"] = ""
	var value: Variant = interp.call_handler(handler, [], script)
	return {"value": value, "trail": interp.globals.get("trail", "")}


## Type-strict. A boolean `true` and the integer `1` are the same condition and
## different values: §13 says the opcode pushes an integer, and a port that
## pushes a GDScript bool puts a type into a field that `LingoValue.to_str`
## prints as "1" but that arithmetic and `ilk` would answer differently for.
func _is_int(value: Variant, want: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) == want


func _show(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "VOID"
		TYPE_BOOL: return "bool %s" % value
		TYPE_INT: return "int %d" % value
		TYPE_FLOAT: return "float %s" % value
		TYPE_STRING: return "String %s" % JSON.stringify(str(value))
		_: return str(value)
