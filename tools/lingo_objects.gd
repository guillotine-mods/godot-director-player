extends SceneTree
## §7.1's object model: parent scripts, `me`, ancestors, and the four messaging
## builtins `send` / `call` / `sendAncestor` / `callAncestor`.
##
##   godot --headless --path . --script tools/lingo_objects.gd
##
## **What would go red if the bindings were reverted**, case by case, because a
## harness that only inspects the shape a bug cannot appear in is worse than
## none:
##
##   `new`            reverted, the expression answers VOID, so every `me`
##                    below is VOID and the property cases fail on the value
##                    rather than on the object.
##   instance scope   reverted, `property` declares a **global**, so two
##                    instances of one script share one counter -- which is the
##                    case `two instances do not share` asserts by giving them
##                    different values and reading both back.
##   ancestors        reverted, an inherited handler is not found, so the
##                    message reaches nothing and the trail stays empty.
##   `callAncestor`   reverted, the child's own handler answers instead, and the
##                    trail says "child" where it must say "base".
##   the list form    reverted, only the first object in the list is messaged,
##                    so the trail is one letter short.
##
## Every case is written as an observable *effect* -- a trail string a handler
## appends to -- as well as a returned value, for the reason
## `tools/lingo_logic_check.gd` gives: asserting only the value lets an
## implementation that never ran the handler pass by answering the same zero.
##
## The last case leaves the language and drives the **real host**: `new(script
## "x")` is only useful if a `script(...)` reference resolves to a compiled
## script in the movie's own cast, and that resolution is `preview_lingo_host.gd
## :script_at` and nothing in this file. It boots the configured movie and asks
## for a script the score itself names.
##
## Title-agnostic: the Lingo below is written for this file and the last case
## takes whatever script the booted movie's score happens to attach.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
const LingoObject := preload("res://lingo/lingo_object.gd")
const Members := preload("res://scenes/preview/members.gd")
const Host := preload("res://scenes/preview_lingo_host.gd")


## The base of the two-level hierarchy. Declares one property and two handlers,
## one of which the child overrides and one of which it does not.
const BASE := """
property pWho, pCount

on new me, who
  pWho = who
  pCount = 0
  return me
end

on identify me
  global trail
  put trail & "base:" & pWho into trail
  return "base"
end

on bump me
  pCount = pCount + 1
  return pCount
end

on onlyHere me
  global trail
  put trail & "inherited" into trail
  return "inherited"
end
"""

## The child. `ancestor` is an ordinary property assigned in `new`, which is how
## Director spells inheritance and why this port keeps no separate field for it.
const CHILD = """
property ancestor, pTag

on new me, who, tag
  ancestor = new(script "base", who)
  pTag = tag
  return me
end

on identify me
  global trail
  put trail & "child:" & pTag into trail
  return "child"
end
"""

## A third, unrelated script, so the list form of `call` has two different
## recipients and a port that messages only the first is caught by the trail.
const OTHER := """
on identify me
  global trail
  put trail & "other" into trail
  return "other"
end

on notEverywhere me
  global trail
  put trail & "only-other" into trail
  return 1
end
"""

## A driver script: the Lingo that *uses* the objects, run in the same
## interpreter so that `new` and `call` are exercised from source rather than
## from GDScript.
const DRIVER := """
on makeOne who, tag
  return new(script "child", who, tag)
end

on askAncestor obj
  return callAncestor(#identify, obj)
end

on askDirect obj
  return call(#identify, obj)
end

on askBoth a, b
  return call(#identify, [a, b])
end

on askMissing obj
  return call(#noSuchHandler, obj)
end

on sendSpelling obj
  return send(#identify, obj)
end

on ancestorSpelling obj
  return sendAncestor(#identify, obj)
end

on inheritedReaches obj
  return call(#onlyHere, obj)
end

on bumpTwice obj
  call(#bump, obj)
  return call(#bump, obj)
end

on readTag obj
  return obj.pTag
end

on writeTag obj, value
  obj.pTag = value
  return obj.pTag
end

on dotMessage obj
  return obj.identify()
end
"""


## A host with exactly the two methods `new(script "x")` needs, and nothing else.
##
## Deliberately not a mock of the whole contract: the interpreter reports a
## missing host method, so a host that answered everything would hide a route
## this file has not thought about.
class ScriptHost extends RefCounted:
	var by_name: Dictionary = {}
	var order: Array[String] = []

	## `script("base")` -- the name is turned into an index into `order`, which
	## stands in for a member number. The packing does not matter here; what
	## matters is that the interpreter carries whatever this answers straight
	## back into `script_at`.
	func member_number(which: Variant, _cast: Variant) -> Variant:
		var wanted := str(which).to_lower()
		var at := order.find(wanted)
		return at + 1 if at >= 0 else 0

	func script_at(reference: Variant) -> Dictionary:
		var index := int(reference) - 1
		if index < 0 or index >= order.size():
			return {}
		return by_name.get(order[index], {})

	func add(script_name: String, ast: Dictionary) -> void:
		order.append(script_name)
		by_name[script_name] = ast


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	# ------------------------------------------------------------- the fixture
	var host := ScriptHost.new()
	var driver: Dictionary = {}
	h.begin("the fixture compiles")
	var compiled_all := true
	for spec in [["base", BASE], ["child", CHILD], ["other", OTHER]]:
		var pair: Array = spec
		var compiler := Compiler.new()
		var ast: Dictionary = compiler.compile_source(str(pair[1]), str(pair[0]))
		if ast.is_empty():
			compiled_all = false
			print("     %s line %d: %s" % [pair[0], compiler.error_line, compiler.error])
		host.add(str(pair[0]), ast)
	var driver_compiler := Compiler.new()
	driver = driver_compiler.compile_source(DRIVER, "driver")
	if driver.is_empty():
		compiled_all = false
		print("     driver line %d: %s" % [driver_compiler.error_line, driver_compiler.error])
	h.check("three parent scripts and a driver parse", compiled_all)
	# The property declarations are what the instance scope is seeded from, so an
	# empty list here would make every property case pass for the wrong reason.
	h.check("the base script declares its two properties",
		(host.by_name["base"].get("properties", []) as Array).size() == 2,
		JSON.stringify(host.by_name["base"].get("properties", [])))
	h.complete("the fixture compiles")
	if not compiled_all:
		quit(h.finish("§7.1 object messaging"))
		return

	# ------------------------------------------------------ construction and me
	var title := "`new` builds an object and its `new` handler runs with `me`"
	h.begin(title)
	var interp := _fresh(host)
	var one: Variant = interp.call_handler("makeOne", ["alpha", "A"], driver)
	h.check("the expression answers an object, not VOID",
		LingoObject.is_object(one), _show(one))
	if LingoObject.is_object(one):
		h.check("`me` was the object the handler wrote through",
			str((one as Object).call("get_slot", "ptag")) == "A",
			_show((one as Object).call("get_slot", "ptag")))
		h.check("the child's `new` built and stored an ancestor",
			LingoObject.is_object((one as Object).call("ancestor")),
			_show((one as Object).call("ancestor")))
		var base_obj: Variant = (one as Object).call("ancestor")
		h.check("the ancestor's own `new` ran with its argument",
			base_obj != null and str((base_obj as Object).call("get_slot", "pwho")) == "alpha",
			_show(null if base_obj == null else (base_obj as Object).call("get_slot", "pwho")))
	h.check("a `property` inside an object handler did not leak into the globals",
		not interp.globals.has("ptag") and not interp.globals.has("pwho"),
		JSON.stringify(interp.globals.keys()))
	h.complete(title)

	# ---------------------------------------------------- instances are separate
	title = "two instances of one script do not share their properties"
	h.begin(title)
	interp = _fresh(host)
	var a: Variant = interp.call_handler("makeOne", ["alpha", "A"], driver)
	var b: Variant = interp.call_handler("makeOne", ["beta", "B"], driver)
	h.check("both constructed", LingoObject.is_object(a) and LingoObject.is_object(b))
	if LingoObject.is_object(a) and LingoObject.is_object(b):
		h.check("the two tags differ",
			str((a as Object).call("get_slot", "ptag")) == "A"
				and str((b as Object).call("get_slot", "ptag")) == "B",
			"%s / %s" % [(a as Object).call("get_slot", "ptag"),
				(b as Object).call("get_slot", "ptag")])
		# The counter lives on each object's *ancestor*, so this is also the
		# through-the-chain write. Bumping one must not move the other.
		interp.call_handler("bumpTwice", [a], driver)
		var bumped: Variant = interp.call_handler("bumpTwice", [b], driver)
		var a_base: Variant = (a as Object).call("ancestor")
		var b_base: Variant = (b as Object).call("ancestor")
		h.check("each ancestor counted its own two bumps",
			LingoObject.is_object(a_base) and LingoObject.is_object(b_base)
				and int((a_base as Object).call("get_slot", "pcount")) == 2
				and int((b_base as Object).call("get_slot", "pcount")) == 2,
			"%s / %s" % [_show(a_base), _show(b_base)])
		h.check("the second bump answered 2, not 4", _is_int(bumped, 2), _show(bumped))
	h.complete(title)

	# ------------------------------------------------------------- `call`/`send`
	title = "`call` and `send` deliver to the object, the ancestor answers what it owns"
	h.begin(title)
	interp = _fresh(host)
	var obj: Variant = interp.call_handler("makeOne", ["gamma", "G"], driver)
	interp.globals["trail"] = ""
	var direct: Variant = interp.call_handler("askDirect", [obj], driver)
	h.check("`call(#identify, obj)` runs the child's own handler",
		str(interp.globals["trail"]) == "child:G", _show(interp.globals["trail"]))
	h.check("and answers what it returned", str(direct) == "child", _show(direct))

	interp.globals["trail"] = ""
	var sent: Variant = interp.call_handler("sendSpelling", [obj], driver)
	h.check("`send` is the same builtin under D4's name",
		str(interp.globals["trail"]) == "child:G" and str(sent) == "child",
		"%s / %s" % [_show(interp.globals["trail"]), _show(sent)])

	interp.globals["trail"] = ""
	var inherited: Variant = interp.call_handler("inheritedReaches", [obj], driver)
	h.check("a message the child does not declare reaches the ancestor",
		str(interp.globals["trail"]) == "inherited", _show(interp.globals["trail"]))
	h.check("and its answer comes back", str(inherited) == "inherited", _show(inherited))

	interp.globals["trail"] = ""
	var missing: Variant = interp.call_handler("askMissing", [obj], driver)
	h.check("a message nothing in the chain declares runs nothing and is VOID",
		missing == null and str(interp.globals["trail"]) == "",
		"%s / %s" % [_show(missing), _show(interp.globals["trail"])])
	h.complete(title)

	# -------------------------------------------------------------- ancestor-only
	title = "`callAncestor` skips the child's own handler"
	h.begin(title)
	interp = _fresh(host)
	obj = interp.call_handler("makeOne", ["delta", "D"], driver)
	interp.globals["trail"] = ""
	var up: Variant = interp.call_handler("askAncestor", [obj], driver)
	h.check("the ancestor's handler ran, not the child's",
		str(interp.globals["trail"]) == "base:delta", _show(interp.globals["trail"]))
	h.check("and answered", str(up) == "base", _show(up))
	interp.globals["trail"] = ""
	var up2: Variant = interp.call_handler("ancestorSpelling", [obj], driver)
	h.check("`sendAncestor` is the same builtin under D4's name",
		str(interp.globals["trail"]) == "base:delta" and str(up2) == "base",
		"%s / %s" % [_show(interp.globals["trail"]), _show(up2)])
	# The object with no ancestor is the case that would crash a naive walk.
	var lone: Variant = interp.call_handler("askAncestor",
		[_instance(interp, host, "other")], driver)
	h.check("an object with no ancestor answers VOID rather than failing",
		lone == null, _show(lone))
	h.complete(title)

	# ------------------------------------------------------------ the list form
	title = "`call` on a list messages every object in it"
	h.begin(title)
	interp = _fresh(host)
	var first: Variant = interp.call_handler("makeOne", ["eps", "E"], driver)
	var second: Variant = _instance(interp, host, "other")
	interp.globals["trail"] = ""
	var last: Variant = interp.call_handler("askBoth", [first, second], driver)
	h.check("both recipients ran, in list order",
		str(interp.globals["trail"]) == "child:Eother", _show(interp.globals["trail"]))
	h.check("the value is the last recipient's", str(last) == "other", _show(last))
	# An object in the list that does not answer is skipped rather than aborting
	# the broadcast -- the reference's `if (sym.type == VOIDSYM) continue`.
	interp.globals["trail"] = ""
	interp.call_handler("askBoth", [second, first], driver)
	h.check("order follows the list, not the objects",
		str(interp.globals["trail"]) == "otherchild:E", _show(interp.globals["trail"]))
	h.complete(title)

	# -------------------------------------------------------- properties outside
	title = "an object's properties are readable and writable from outside it"
	h.begin(title)
	interp = _fresh(host)
	obj = interp.call_handler("makeOne", ["zeta", "Z"], driver)
	h.check("`obj.pTag` reads the instance variable",
		str(interp.call_handler("readTag", [obj], driver)) == "Z",
		_show(interp.call_handler("readTag", [obj], driver)))
	h.check("`obj.pTag = x` writes it",
		str(interp.call_handler("writeTag", [obj, "Q"], driver)) == "Q",
		_show(interp.call_handler("writeTag", [obj, "Q"], driver)))
	interp.globals["trail"] = ""
	var dotted: Variant = interp.call_handler("dotMessage", [obj], driver)
	h.check("`obj.identify()` is a message, not a property read",
		str(interp.globals["trail"]).begins_with("child:") and str(dotted) == "child",
		"%s / %s" % [_show(interp.globals["trail"]), _show(dotted)])
	h.complete(title)

	# --------------------------------------------------- the real host resolves
	#
	# Everything above runs against a fixture host. This is the only case that
	# says `new(script "x")` can find a script in a real movie, which is the half
	# that lives in `preview_lingo_host.gd` and `director_preview.gd`.
	title = "the live host resolves a script reference to a compiled script"
	h.begin(title)
	# `--root` and `--boot` are read by `preview/boot.gd` off the command line
	# itself, so the preview needs no arguments from here -- which is what lets
	# `gate.sh` pin the corpus per process rather than by editing a shared config.
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var live := Host.new()
	live.preview = preview
	h.check("the host offers `script_at` at all", live.has_method("script_at"))
	var found := 0
	var checked := 0
	var score = preview.get("_score")
	if score != null:
		for interval in score.intervals():
			var entry: Dictionary = interval
			var member := int(entry.get("script_member", 0))
			if member <= 0 or checked >= 40:
				continue
			checked += 1
			var packed := Members.pack_ref(int(entry.get("script_cast_lib", 1)), member)
			var ast: Dictionary = live.script_at(packed)
			if not ast.is_empty() and not (ast.get("handlers", []) as Array).is_empty():
				found += 1
	h.check("at least one script the score attaches resolves through it",
		found > 0, "%d of %d attachments resolved" % [found, checked])
	h.check("a reference naming nothing answers an empty script, not a crash",
		live.script_at(999999).is_empty())
	preview.queue_free()
	h.complete(title)

	quit(h.finish("§7.1 object messaging: new, me, ancestors, call/send/callAncestor"))


## A fresh interpreter per case, wired to the fixture host. Fresh because `trail`
## is a global and a shared interpreter would let case order decide the answers.
func _fresh(host) -> LingoInterpreter:
	var interp := Interpreter.new(host)
	interp.globals["trail"] = ""
	return interp


## One instance of a fixture script, built the way the language builds it -- by
## running `new` through the interpreter -- rather than by calling into
## `lingo_object.gd` from GDScript, which would test the class and not the
## binding.
func _instance(interp, host, script_name: String) -> Variant:
	var source := "on make\n  return new(script \"%s\")\nend\n" % script_name
	var compiler := Compiler.new()
	var ast: Dictionary = compiler.compile_source(source, "make_%s" % script_name)
	return interp.call_handler("make", [], ast)


func _is_int(value: Variant, want: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) == want


func _show(value: Variant) -> String:
	if value == null:
		return "VOID"
	if value is Object:
		return str(value)
	return JSON.stringify(value)
