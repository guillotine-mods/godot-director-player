extends SceneTree
## **The oracle.** Decode every compiled script that also carries its own source
## text, and compare the AST against the one the port's parser already produces.
##
##   godot --headless --path . --script tools/lscr_decode.gd
##   godot --headless --path . --script tools/lscr_decode.gd -- --all
##   godot --headless --path . --script tools/lscr_decode.gd -- --root piposh --verbose
##   godot --headless --path . --script tools/lscr_decode.gd -- --file PIP2DATA/BYAIR.cst --diff
##
## `docs/LSCR_FORMAT.md` section 8 establishes that decoding `Lscr` recovers **no
## behaviour at all** from the six titles under `games/`: every member that has
## code also has source text, so nothing in any of them starts working when this
## lands. Section 8's own conclusion from that is the reason this harness exists:
## *"A decoder that is wrong will not be noticed by playing the game."* There is
## no room that breaks, no handler that goes missing, no symptom. The only
## defence is the 38,396 members that carry **both** forms, each of which is a
## free self-checking test, and that is what runs here.
##
## ## What is compared, and the three things that cannot be
##
## Director's compiler is not a pretty-printer: it **normalises** as it compiles,
## and three of those normalisations are lossy. All three were found by measuring
## rather than by reasoning about the format, and the comparison states them
## rather than widening quietly to hide them:
##
## - **Command syntax is resolved at compile time.** `go to movie "x"` compiles
##   to `go(1, "x")`: the keywords are gone and a frame number has been
##   synthesised in their place, while the port's parser keeps `to` and `movie`
##   as string arguments. This one is reported as a **second, wider rate** rather
##   than folded into the first -- the relaxation replaces the entire argument
##   list of a call to one of the five callees in `Grammar.COMMAND_WORDS`, and
##   touches nothing else, so the gap between the two rates is exactly what it
##   costs.
## - **`put X into Y` and `set Y to X` are the same instruction.** Nibble 1 of
##   `put` (0x59). The parsed side's `put ... into ...` is rewritten to `assign`,
##   which is what `set` parses to and the only thing the compiled form can
##   express. `after` and `before` are untouched: those nibbles are distinct.
## - **`the memberNum of member "x"` and `member("x").memberNum` compile to
##   identical bytecode**, and this corpus contains the same title written both
##   ways -- `piposh` uses the first spelling, `piposh-en` and `piposh-ru` the
##   second, in the same handler of the same movie. Nothing normalises this,
##   because there is nothing to normalise *towards*: the decoder must pick one,
##   it picks the dot spelling because that is what the corpus mostly is, and the
##   divergence table below counts the handlers where the source said the other.
##
## Two smaller ones, both grepped rather than assumed. `command` on a `call` node
## records *syntax* and nothing reads it -- `tools/script_compile_check.gd` is its
## only consumer in the whole tree -- so it is dropped. Identifier **case** is
## dropped because Lingo is case-insensitive and the two sides record different
## spellings: `Lnam` stores a name once as first declared, the source text
## carries whatever each use was typed as, and `HEZSAVE.DIR`'s `dosave` calls
## `saveMovie` where the movie script declares `savemovie`.
##
## Line numbers are dropped on both sides. The compiled form carries a line table
## and the lowering reads it, but a handler's position within its member's source
## text is recorded **nowhere** in the container, so decoded line numbers are
## relative to the handler and parsed ones are absolute. Comparing them would
## fail 38,000 times over a difference that carries no information.
##
## ## The measurements
##
## 1. **Exact AST equality**, and the same again with command syntax set aside.
##    The headline pair; the numbers are in the comment on the checks.
## 2. **Control-flow shape** -- the multiset of `if` / `repeat_*` / `case` /
##    `tell` / `exit_repeat` / `next_repeat` nodes per handler. This is the one
##    that tests the jump structuring, which is the largest and riskiest part of
##    the lowering, and it is separate because a shape agreement with an
##    expression disagreement is a very different bug from the reverse.
## 3. **Literals and identifiers** -- the multisets of string literals, numeric
##    literals and called handler names, over the relaxed trees. Independent of
##    the control flow and of each other, so a divergence localises.
## 4. **Residue and underflow**, which unlike the rest have an expected value of
##    **zero** rather than a rate. Nothing may be built and left unconsumed, and
##    no opcode but `pop` may consume what was never pushed.
##
## And one survey rather than an assertion: the node types the mismatching
## handlers disagree about, tallied, so a reported rate says *where to look* and
## not only how far away it is. Every fix in the lowering after the first draft
## came off the top line of that table.
##
## `--diff` prints the first disagreeing handler's two trees and `--diff-node
## <kind>` picks the first that disagrees about a given node type, which is how a
## reported rate turns into a fix.
##
## Title-agnostic. `--all` sweeps every root under `games/`.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Lscr := preload("res://director/director_lscr.gd")
const Lower := preload("res://lingo/compile/lscr_lower.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Grammar := preload("res://lingo/compile/lingo_grammar.gd")

const SHOWN := 6
const CONTROL := {
	"if": true, "repeat_while": true, "repeat_with": true, "repeat_in": true,
	"repeat_forever": true, "case": true, "tell": true,
	"exit_repeat": true, "next_repeat": true,
}

var _total := 0
var _exact := 0
var _relaxed := 0
var _command_only := 0
var _shape_ok := 0
var _strings_ok := 0
var _numbers_ok := 0
var _calls_ok := 0
var _residue := 0
var _residue_kinds: Dictionary = {}
var _underflow_scripts: Array[String] = []
var _unknown := 0
var _unknown_ops: Dictionary = {}
var _shape_bad: Array[String] = []
var _string_bad: Array[String] = []
var _call_bad: Array[String] = []
var _divergence: Dictionary = {}
var _same_shape := 0
var _first_diff: Array = []
var _want_diff := false
var _diff_node := ""


func _init() -> void:
	var args := Args.parse()
	var verbose := Args.flag(args, "verbose")
	_want_diff = Args.flag(args, "diff")
	_diff_node = Args.text(args, "diff-node", "")
	if _diff_node != "":
		_want_diff = true
	var h := Harness.new()

	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var roots: Array[String] = []
	if Args.flag(args, "all"):
		var dir := DirAccess.open(Paths.games_dir())
		if dir != null:
			for sub in dir.get_directories():
				roots.append(sub)
		roots.sort()
	else:
		roots.append(paths.root.get_file())

	var only := Args.text(args, "file", "")
	var started := Time.get_ticks_msec()
	for root_name in roots:
		var files: Array[String] = []
		if only != "":
			var resolved := paths.resolve(only)
			if resolved == "":
				print("no such container: %s" % only)
				quit(1)
				return
			files.append(resolved)
		else:
			_walk(Paths.games_dir().path_join(root_name), files)
			files.sort()
		for path in files:
			_container(path)

	print("roots: %s" % ", ".join(roots))
	print("  handlers compared     : %d" % _total)
	if _total > 0:
		print("  exact AST match       : %d  (%.2f%%)" % [_exact, 100.0 * _exact / _total])
		print("  match, command syntax : %d  (%.2f%%)  [+%d that differ only inside a" % [
			_relaxed, 100.0 * _relaxed / _total, _command_only])
		print("                           go/play/open/close/sound command's arguments]")
		print("  control-flow shape    : %d  (%.2f%%)" % [_shape_ok, 100.0 * _shape_ok / _total])
		print("  string literals       : %d  (%.2f%%)" % [
			_strings_ok, 100.0 * _strings_ok / _total])
		print("  numeric literals      : %d  (%.2f%%)" % [
			_numbers_ok, 100.0 * _numbers_ok / _total])
		print("  called handler names  : %d  (%.2f%%)" % [_calls_ok, 100.0 * _calls_ok / _total])
	print("  stack residue         : %d" % _residue)
	print("  residue by node type  : %s" % str(_residue_kinds))
	print("  unknown_opcode nodes  : %d  %s" % [_unknown, _describe_unknown()])
	print("  elapsed               : %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	_print_divergence()
	if _want_diff and not _first_diff.is_empty():
		print("  first disagreement:")
		print("    %s" % str(_first_diff[0]))
		print("    decoded: %s" % JSON.stringify(_first_diff[1]))
		print("    parsed : %s" % JSON.stringify(_first_diff[2]))

	h.begin("compiled Lingo lowers to the AST the source text produces")
	# **Two exact assertions and four floors, and every number below is a
	# measurement rather than a target.** The floors are set just under the worst
	# root, so a change that lowers agreement reds this and a change that raises
	# it asks for the floor to be re-recorded. A rate rather than a count, because
	# the count moves with whichever corpus the entry names and the rate does not.
	#
	# Measured 2026-08-22 over all six roots under `games/`, 38,813 handlers that
	# carry both a compiled script and the source it was compiled from:
	#
	#   root           handlers  exact   +cmd    control  strings  callees
	#   piposh            8,810  84.61%  95.09%   99.97%   97.73%   99.93%
	#   piposh-dream      1,858  83.96%  88.21%   99.52%   94.35%   99.14%
	#   piposh-en         9,477  80.49%  96.25%   99.96%   97.91%   99.87%
	#   piposh-ru         9,782  79.55%  96.66%   99.96%   97.98%   99.89%
	#   piposh2           3,427  91.39%  96.35%   99.85%   99.21%   99.80%
	#   rating            5,459  73.02%  89.76%   99.95%   99.34%   99.78%
	#   all six          38,813  81.27%  94.80%   99.93%   98.03%   99.84%
	#
	# The gap between "exact" and "+cmd" is Director's compile-time command-syntax
	# resolution and nothing else -- 5,253 handlers of the 7,271 that are not
	# exact. Most of what remains is the other ambiguity the format cannot
	# resolve: `the memberNum of member "x"` and `member("x").memberNum` compile
	# to **identical bytecode**, and this corpus contains the same title written
	# both ways -- `piposh` uses the first spelling and `piposh-en`/`piposh-ru`
	# the second, in the same handler of the same movie. No decoder can tell them
	# apart, and the divergence table above the checks counts them.
	h.check("no opcode but `pop` ever underflows the value stack", _only_pop_underflows(),
		str(_residue_kinds) if not _residue_kinds.is_empty() else "clean")
	_report(_underflow_scripts, verbose)
	# `pop` is the exception because it is the one opcode whose whole job is to
	# discard, and a stack simulation that has already folded the discarded value
	# into a sub-tree has nothing left for it to drop. Everything else underflows
	# only if this file consumed an operand that was never pushed, which is a
	# lowering bug -- and it is zero across all six roots.
	h.check("no expression is built and then left unconsumed", _leftovers() == 0,
		"%d leftover(s)" % _leftovers())
	h.check("control flow is reconstructed", _rate(_shape_ok) >= 99.0,
		"%.2f%% (%d of %d)" % [_rate(_shape_ok), _shape_ok, _total])
	_report(_shape_bad, verbose)
	h.check("string literals are recovered", _rate(_strings_ok) >= 94.0,
		"%.2f%% (%d of %d)" % [_rate(_strings_ok), _strings_ok, _total])
	_report(_string_bad, verbose)
	h.check("called handler names are recovered", _rate(_calls_ok) >= 99.0,
		"%.2f%% (%d of %d)" % [_rate(_calls_ok), _calls_ok, _total])
	_report(_call_bad, verbose)
	h.check("whole trees match", _rate(_exact) >= 70.0,
		"%.2f%% exact, %.2f%% once command syntax is set aside" % [
			_rate(_exact), _rate(_relaxed)])
	# The guard against a green run over nothing. Six rates over an empty set are
	# six divisions by zero reported as passes.
	h.check("there were handlers carrying both forms", _total > 0, "%d" % _total)
	h.complete("compiled Lingo lowers to the AST the source text produces")
	quit(h.finish("the bytecode path and the source-text path agree on real scripts"))


func _rate(count: int) -> float:
	return 100.0 * count / maxi(_total, 1)


## True when every underflow this run saw came from `pop`.
func _only_pop_underflows() -> bool:
	for kind in _residue_kinds:
		if str(kind) != "underflow:pop":
			return false
	return true


## Expressions built and never consumed -- residue that is not an underflow.
func _leftovers() -> int:
	var total := 0
	for kind in _residue_kinds:
		if not str(kind).begins_with("underflow:"):
			total += int(_residue_kinds[kind])
	return total


func _container(path: String) -> void:
	var f := ContainerFile.new()
	if not f.open(path):
		return
	var reader := Lscr.new()
	if not reader.open(f):
		f.close()
		return
	var cast := Cast.new()
	if not cast.open(f):
		f.close()
		return
	var compiler := Compiler.new()
	var lower := Lower.new()
	for number in cast.member_numbers():
		var member: Dictionary = cast.member(number)
		var script_id := int(member.get("script_id", 0))
		if script_id <= 0:
			continue
		var source := str(member.get("source", ""))
		if source.strip_edges() == "":
			continue
		var chunk: int = reader.chunk_for_script_id(script_id)
		if chunk < 0:
			continue
		var script: Dictionary = reader.read_script(chunk)
		if script.is_empty():
			continue
		var key := Compiler.script_key(member, number)
		var parsed: Dictionary = compiler.compile_source(source, key)
		if parsed.is_empty():
			# A script the parser cannot read is not evidence about the decoder.
			# `tools/script_compile_check.gd` owns that failure and reporting it
			# twice would make one fault look like two.
			continue
		var decoded: Dictionary = lower.lower_script(reader, script, key)
		_unknown += lower.unknown
		for op in lower.unknown_ops:
			_unknown_ops[op] = int(_unknown_ops.get(op, 0)) + int(lower.unknown_ops[op])
		if lower.residue > 0:
			_residue += lower.residue
			_underflow_scripts.append("%s %s: %d residue %s" % [
				path.get_file(), key, lower.residue, str(lower.residue_nodes)])
			for kind in lower.residue_nodes:
				_residue_kinds[kind] = int(_residue_kinds.get(kind, 0)) 					+ int(lower.residue_nodes[kind])
		_compare(path, key, decoded, parsed)
	f.close()


func _compare(path: String, key: String, decoded: Dictionary, parsed: Dictionary) -> void:
	var by_name := {}
	for handler in parsed.get("handlers", []):
		by_name[str(handler.get("name", "")).to_lower()] = handler
	for handler in decoded.get("handlers", []):
		var name := str(handler.get("name", "")).to_lower()
		if not by_name.has(name):
			continue
		_total += 1
		var mine: Variant = _normalise(handler, false, false)
		var theirs: Variant = _normalise(by_name[name], true, false)
		var where := "%s %s / %s" % [path.get_file(), key, name]
		if mine == theirs:
			_exact += 1
			_relaxed += 1
		else:
			var mine_relaxed: Variant = _normalise(handler, false, true)
			var theirs_relaxed: Variant = _normalise(by_name[name], true, true)
			if mine_relaxed == theirs_relaxed:
				_relaxed += 1
				_command_only += 1
			else:
				_tally_divergence(mine_relaxed, theirs_relaxed)
				if _want_diff and _diff_node == "" and _first_diff.is_empty():
					_first_diff = [where, mine_relaxed, theirs_relaxed]
		# The three projections below run over the **relaxed** trees, because the
		# strict comparison above already reports the command-syntax gap once and
		# counting it again in every category would say the same thing four times.
		var mine_p: Variant = _normalise(handler, false, true)
		var theirs_p: Variant = _normalise(by_name[name], true, true)
		if _multiset(mine_p, "__control") == _multiset(theirs_p, "__control"):
			_shape_ok += 1
		else:
			_shape_bad.append("%s: decoded %s, parsed %s" % [
				where, str(_multiset(mine_p, "__control")), str(_multiset(theirs_p, "__control"))])
		if _multiset(mine_p, "str") == _multiset(theirs_p, "str"):
			_strings_ok += 1
		else:
			_string_bad.append("%s: %d decoded string(s) vs %d parsed" % [
				where, _count(mine_p, "str"), _count(theirs_p, "str")])
		if _multiset(mine_p, "num") == _multiset(theirs_p, "num"):
			_numbers_ok += 1
		if _multiset(mine_p, "__callee") == _multiset(theirs_p, "__callee"):
			_calls_ok += 1
		else:
			_call_bad.append("%s: decoded %s, parsed %s" % [
				where, str(_multiset(mine_p, "__callee")), str(_multiset(theirs_p, "__callee"))])


## Both trees, made comparable.
##
## `parsed` marks the side that came out of the port's parser, because exactly
## one normalisation applies to it alone: `put X into Y` is rewritten to
## `assign`, since nibble 1 of `put` (0x59) is *both* `put ... into` and `set ...
## to` and the compiled form cannot say which was written. That is a
## normalisation of the parsed tree towards the only thing the compiled one can
## express, and applying it to both sides would say nothing.
##
## `relax` is the second, wider measurement and is reported separately rather
## than folded into the first, because a comparison that has been widened until
## it agrees measures nothing -- which is what `porting-fidelity-verification` is
## about. It replaces the whole argument list of a call to one of the **five**
## command-syntax callees in `Grammar.COMMAND_WORDS` with a marker, because
## Director's compiler rewrote those arguments at compile time and neither tree
## can be turned into the other:
##
##     go to movie "x"   parses to   go("to", "movie", "x")
##                       compiles to go(1, "x")
##
## Five callees, and the relaxation touches nothing else -- not `sound playFile`,
## whose keyword *is* preserved as a symbol in the bytecode and must come back as
## a string (section 7.4's `str` versus `sym` trap), and not any other call in the
## language.
func _normalise(node: Variant, parsed: bool, relax: bool) -> Variant:
	if typeof(node) == TYPE_ARRAY:
		var out: Array = []
		for item in node:
			out.append(_normalise(item, parsed, relax))
		return out
	if typeof(node) != TYPE_DICTIONARY:
		return node
	var d: Dictionary = node
	var kind := str(d.get("node", ""))
	if parsed and kind == "put" and str(d.get("mode", "")) == "into":
		return {
			"node": "assign",
			"target": _normalise(d.get("target"), parsed, relax),
			"value": _normalise(d.get("value"), parsed, relax),
		}
	if parsed and kind == "call_stmt":
		# **A bare command statement parses to a `var` and compiles to a call.**
		# `pause` on a line of its own is `{"node": "var", "name": "pause"}` inside
		# a `call_stmt` -- the parser cannot tell a zero-argument command from a
		# variable read and leaves the interpreter to resolve it -- while the
		# bytecode says `pusharglistnoret 0; extcall pause`, which is
		# unambiguously a call. The compiled form is *more* specific, so the
		# parsed one is moved to it rather than the other way round: a lowering
		# that emitted a bare `var` would be throwing away something Director
		# recorded, which is the opposite of what this decoder is for.
		var inner: Dictionary = d.get("call", {})
		if str(inner.get("node", "")) == "var":
			return {"node": "call_stmt", "call": {
				"node": "call", "args": [],
				"callee": {"node": "var", "name": str(inner.get("name", "")).to_lower()}}}
	var out := {}
	for field in d:
		if field == "line":
			continue
		# **`command` records syntax, not semantics, and Director erased the
		# syntax.** The parser sets it on a command-form call and leaves it off a
		# parenthesised one; the bytecode's `pusharglistnoret` says only that the
		# result is discarded, which `call_stmt` already says. Grepped: the
		# interpreter never reads the field -- `tools/script_compile_check.gd` is
		# its only consumer in the whole tree, and that is a misparse detector on
		# the source path. Comparing it would fail on a flag nothing acts on.
		if field == "command":
			continue
		# **Lingo identifiers are case-insensitive and the two sides record
		# different spellings of them.** `Lnam` stores the name once, as first
		# declared, while the source text carries whatever each use was typed as;
		# `HEZSAVE.DIR`'s `dosave` calls `saveMovie` where the movie script
		# declares `savemovie`. The interpreter already lowercases every
		# identifier it looks up (`lingo_interpreter.gd` does it on `repeat with`,
		# on handler names and on variable names), so case is not information and
		# comparing it would fail on a difference nothing downstream can see.
		if field == "name" or field == "prop" or field == "unit" or field == "var":
			if typeof(d[field]) == TYPE_STRING:
				out[field] = str(d[field]).to_lower()
				continue
		if field == "names" or field == "params":
			var lowered: Array = []
			for entry in d[field]:
				lowered.append(str(entry).to_lower())
			out[field] = lowered
			continue
		out[field] = _normalise(d[field], parsed, relax)
	if relax and kind == "call":
		var callee: Dictionary = d.get("callee", {})
		if Grammar.COMMAND_WORDS.has(str(callee.get("name", "")).to_lower()):
			out["args"] = "<command syntax resolved at compile time>"
	return out


## A sorted multiset of one projection of a tree.
##
## `__control` is the control-flow node types, `__callee` the names of called
## handlers, and anything else is the `value` of every node of that type. Sorted,
## so two trees that hold the same literals in a different order still agree --
## which is deliberate: the order is decided by the expression structure and that
## is what check 1 is for.
func _multiset(node: Variant, want: String) -> Array:
	var out: Array = []
	_collect(node, want, out)
	out.sort_custom(func(a, b): return str(a) < str(b))
	return out


func _count(node: Variant, want: String) -> int:
	return _multiset(node, want).size()


func _collect(node: Variant, want: String, out: Array) -> void:
	if typeof(node) == TYPE_ARRAY:
		for item in node:
			_collect(item, want, out)
		return
	if typeof(node) != TYPE_DICTIONARY:
		return
	var d: Dictionary = node
	var kind := str(d.get("node", ""))
	if want == "__control":
		if CONTROL.has(kind):
			out.append(kind)
	elif want == "__callee":
		if kind == "call":
			var callee: Dictionary = d.get("callee", {})
			out.append(str(callee.get("name", "?")))
	elif kind == want:
		out.append(d.get("value"))
	for field in d:
		_collect(d[field], want, out)


## Which node types the two trees disagree about, tallied over every handler that
## did not match. Not an assertion -- a **pointer**, so a reported rate says where
## to look next instead of only how far away it is. Each entry is a node type and
## the signed count by which the decoded tree over- or under-produced it.
func _tally_divergence(mine: Variant, theirs: Variant) -> void:
	var counts: Dictionary = {}
	_tally(mine, counts, 1)
	_tally(theirs, counts, -1)
	var any := false
	for kind in counts:
		if int(counts[kind]) != 0:
			any = true
			break
	if not any:
		# Same node types on both sides, arranged or parameterised differently.
		# Counted apart because it is a completely different kind of fault from a
		# missing node type -- an operand order, a scalar field, a nesting.
		_same_shape += 1
		if _diff_node == "__same" and _first_diff.is_empty():
			_first_diff = ["(first handler whose node types all agree)", mine, theirs]
	for kind in counts:
		if int(counts[kind]) == 0:
			continue
		if kind == _diff_node and _first_diff.is_empty():
			_first_diff = ["(first handler diverging on %s)" % kind, mine, theirs]
		var row: Dictionary = _divergence.get(kind, {"handlers": 0, "net": 0})
		row["handlers"] = int(row["handlers"]) + 1
		row["net"] = int(row["net"]) + int(counts[kind])
		_divergence[kind] = row


func _tally(node: Variant, counts: Dictionary, sign: int) -> void:
	if typeof(node) == TYPE_ARRAY:
		for item in node:
			_tally(item, counts, sign)
		return
	if typeof(node) != TYPE_DICTIONARY:
		return
	var d: Dictionary = node
	if d.has("node"):
		var kind := str(d["node"])
		counts[kind] = int(counts.get(kind, 0)) + sign
	for field in d:
		_tally(d[field], counts, sign)


func _print_divergence() -> void:
	if _divergence.is_empty():
		return
	var rows: Array = _divergence.keys()
	rows.sort_custom(func(a, b): return int(_divergence[a]["handlers"]) > int(_divergence[b]["handlers"]))
	print("      (%d mismatching handler(s) have identical node types)" % _same_shape)
	print("  node types the mismatching handlers disagree about (handlers, net decoded - parsed):")
	for kind in rows:
		print("      %-14s %5d  %+d" % [kind, int(_divergence[kind]["handlers"]),
			int(_divergence[kind]["net"])])


func _describe_unknown() -> String:
	if _unknown_ops.is_empty():
		return ""
	var parts: Array = []
	var keys: Array = _unknown_ops.keys()
	keys.sort()
	for op in keys:
		parts.append("0x%02x x%d" % [int(op), int(_unknown_ops[op])])
	return "(" + ", ".join(parts) + ")"


static func _report(lines: Array[String], verbose: bool) -> void:
	var show: int = lines.size() if verbose else mini(SHOWN, lines.size())
	for i in show:
		print("      %s" % lines[i])
	if show < lines.size():
		print("      ... and %d more (pass --verbose)" % (lines.size() - show))


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
