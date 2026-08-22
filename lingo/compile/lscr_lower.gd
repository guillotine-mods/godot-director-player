extends RefCounted
## Compiled Lingo bytecode to **the AST `lingo/lingo_interpreter.gd` already
## runs**. This is step 4 of `docs/LSCR_FORMAT.md`, and the choice it names.
##
## ## The choice: emit the port's AST, do not execute the bytecode
##
## There were two ways to make a decoded `Lscr` do something. Execute the
## bytecode directly on a new stack machine -- which is what ScummVM does, and is
## therefore closer to the reference -- or lower it into the Dictionary AST the
## existing interpreter consumes, which is what this file does. The argument for
## the second, in the order the reasons actually weigh:
##
## 1. **Only this one is testable against what the port already does.** 38,396
##    members in `games/` carry *both* source text and bytecode, and the port
##    already turns the source into an AST. Lowering to the same AST makes those
##    38,396 a differential test that runs in twenty seconds and compares two
##    data structures. A bytecode VM could only be compared by *running* both and
##    watching for a difference, on scripts whose whole purpose is side effects
##    -- sound, playhead, sprites, save files. `docs/LSCR_FORMAT.md` section 8
##    makes the point that nothing in this corpus *needs* the decoder, so nobody
##    would ever notice it being wrong by playing; the oracle is the only defence,
##    and this choice is what makes the oracle exist.
## 2. **The interpreter is the accumulated Lingo semantics of this port.** 3,171
##    lines of it, debugged against six titles: chunk expressions, `the`
##    properties, sprite and member references, factories, the fault sink, and --
##    the one that decides it -- `play`/`go` suspending a handler mid-statement
##    and resuming it (`ENGINE_TODO.md` section 6.1/9.4). A second execution engine
##    would have to reproduce all of that, and every divergence between the two
##    would be a bug in the path with **no corpus coverage at all**. Two
##    interpreters for one language is the "fix one channel" shape `AGENTS.md`
##    warns about, one level up.
## 3. **Accuracy to Director is not accuracy to ScummVM's implementation.**
##    Director's own compiler is deterministic: a movie's source text and its
##    bytecode are the same program, and Director shipped both from one compile.
##    ScummVM unifies on bytecode because *its* source-text path compiles to
##    bytecode too; this port unifies on the AST because its source-text path
##    parses to an AST. Reaching the same program by the port's own trusted path
##    is the faithful choice here, not the shortcut.
##
## What the choice costs is real and is recorded rather than smoothed over: the
## bytecode is a stack machine with `goto`, and the AST is a tree with structured
## control flow, so this file has to **reconstruct** expressions and blocks that
## Director's compiler destroyed. That reconstruction is the whole risk, it is
## about two thirds of this file, and `tools/lscr_decode.gd` exists to measure it.
##
## ## Two things Director's compiler erases, which no lowering can restore
##
## Both were found by measurement, not predicted, and they set the ceiling on
## what the differential test can ever report:
##
## - **Command syntax is resolved at compile time.** `go to movie "x"` compiles
##   to `go(1, "x")` -- the keywords `to` and `movie` are gone and a frame number
##   has been synthesised. The port's parser keeps the keywords as arguments
##   (`Grammar.COMMAND_WORDS` is that list), so the two ASTs cannot be equal even
##   though both call the same handler with the same meaning. The port's `go`
##   builtin already accepts the positional form -- that is `bugs.md` 95's fix --
##   so the decoded call runs correctly; it simply does not *look* like the parsed
##   one.
## - **`put X into Y` and `set Y to X` compile to the same instruction.** Nibble
##   1 of `put` (0x59) is both. The lowering emits `assign`, which is what the
##   port's parser emits for `set`; a member written with `put ... into` cannot be
##   recovered as a `put` node and does not need to be.
##
## And a third, found last and the largest of the three: **`the memberNum of
## member "x"` and `member("x").memberNum` compile to identical bytecode.** This
## corpus contains the same title written both ways -- `piposh` uses the first
## spelling, `piposh-en` and `piposh-ru` the second, in the same handler of the
## same movie -- so the two really do produce the same instructions and the
## decoder must simply pick one. It picks the dot form because the corpus
## measures that way; folding onto `sprite_prop`/`member_prop` instead was tried
## and made agreement five times worse.
##
## `tools/lscr_decode.gd` reports all three rather than quietly widening the
## comparison until it agrees. Measured over all six roots on 2026-08-22, 38,813
## handlers carrying both forms: **81.27% of trees identical, 94.80% once
## command syntax is set aside, 99.93% agreeing on control-flow shape, 99.84% on
## called handler names, 99.88% on numeric literals, 98.03% on string literals,
## and no opcode but `pop` ever underflowing the value stack.**
##
## ## Structure
##
## `lower_handler` runs two passes over one handler's instruction list:
##
## 1. **Loop discovery.** Every `endrepeat` (0x54) branches backwards to its own
##    loop head, so one scan gives every loop's extent before anything is
##    structured. Loops have to be known up front because the head is reached
##    long before the instruction that identifies it.
## 2. **A recursive walk over instruction ranges**, carrying a value stack.
##    Straight-line opcodes pop their operands off that stack and push the node
##    they build -- so `swap`, `peek` and `pop` need no AST counterpart, which is
##    the answer to `docs/LSCR_FORMAT.md` section 7.1. `jmpifz`, `jmp` and
##    `endrepeat` are consumed by the walker itself and become `if`, `repeat_*`,
##    `case`, `exit_repeat` and `next_repeat`.
##
## An opcode this file cannot lower emits `{"node": "unknown_opcode", ...}` and
## the walk continues. That is deliberate and section 7 asks for it: a handler
## that fails at one node is a handler you can still read and report, where a
## guess is a handler that runs and does the wrong thing.

const Disasm := preload("res://lingo/compile/lscr_disasm.gd")
const TheTable := preload("res://lingo/compile/lscr_the.gd")
const Grammar := preload("res://lingo/compile/lingo_grammar.gd")

## Binary opcodes, canonical -> the operator the `binary` node carries.
const BINARY := {
	0x04: "*", 0x05: "+", 0x06: "-", 0x07: "/", 0x08: "mod",
	0x0a: "&", 0x0b: "&&",
	0x0c: "<", 0x0d: "<=", 0x0e: "<>", 0x0f: "=", 0x10: ">", 0x11: ">=",
	0x12: "and", 0x13: "or",
	0x15: "contains", 0x16: "starts",
	0x19: "intersects", 0x1a: "within",
}
## `readChunkRef` pops eight values; these are the four chunk kinds it builds
## from them, **outermost first**, which is the order the reference applies them
## (`lingo-code.cpp:readChunkRef`: line, item, word, char).
const CHUNK_ORDER := ["line", "item", "word", "char"]

## How many `unknown_opcode` nodes the last lowering emitted, and what they were.
var unknown := 0
var unknown_ops: Dictionary = {}
## Value-stack residue: expressions built and never consumed. Non-zero means a
## statement shape this file does not recognise swallowed its operands, and it is
## the cheapest signal that something is missing.
var residue := 0
## What was left on the stack, by node type, so a residue count says *what* was
## dropped rather than only how much.
var residue_nodes: Dictionary = {}
var error := ""

var _reader = null
var _script: Dictionary = {}
var _handler: Dictionary = {}
var _divisor := 8
var _ins: Array = []
var _at: Dictionary = {}
var _stack: Array = []
var _line_starts: PackedInt32Array = PackedInt32Array()
## pos of loop head -> `{end_index, after_pos, head_index}`.
var _loops: Dictionary = {}
## Loop heads already consumed by the walker, so a nested re-entry does not
## rebuild the same loop.
var _loops_done: Dictionary = {}
## Loops we are inside, innermost last, for `exit repeat` / `next repeat`.
var _open_loops: Array = []
## The instruction being lowered, so an underflow can name the opcode that caused
## it rather than only the handler.
var _current := ""


## One `Lscr` chunk as the bundle shape `LingoInterpreter.load_bundle` expects
## from `LingoCompiler.compile_source`: `{script, handlers}`.
##
## `key` is the script key the source-text path would have produced --
## `LingoCompiler.script_key`. Callers that have a cast member should pass that,
## so a decoded script is reachable by the same name as a parsed one and nothing
## downstream can tell which produced it.
func lower_script(reader, script: Dictionary, key: String) -> Dictionary:
	unknown = 0
	unknown_ops.clear()
	residue = 0
	residue_nodes.clear()
	error = ""
	var handlers: Array = []
	for handler in script.get("handlers", []):
		handlers.append(lower_handler(reader, script, handler))
	return {"script": key, "handlers": handlers}


## One handler, as a `handler` node.
##
## A **factory** script (`kScriptFlagFactoryDef`) gets `me` as argument 0 where
## the record's own name index was invalid; `director_lscr.gd` has already done
## that, so nothing here needs to know. An **event script**
## (`kScriptFlagEventScript`) has an unnamed handler 0 carrying top-level Lingo
## that was never inside an `on` line; it is named for the generic event the way
## ScummVM names it, because the AST's top level is a list of handlers and has
## nowhere else to put loose statements.
func lower_handler(reader, script: Dictionary, handler: Dictionary) -> Dictionary:
	_reader = reader
	_script = script
	_handler = handler
	_divisor = int(script.get("divisor", 8))
	_stack.clear()
	_loops.clear()
	_loops_done.clear()
	_open_loops.clear()
	_line_starts = _line_table(handler)

	var decoded: Dictionary = Disasm.decode(handler.get("code", PackedByteArray()))
	_ins = decoded["instructions"]
	if str(decoded["error"]) != "":
		error = str(decoded["error"])
	_at = {}
	for i in _ins.size():
		_at[int(_ins[i]["pos"])] = i
	_find_loops()

	var name := str(handler.get("name", ""))
	if name == "":
		name = "genericEvent" if bool(script.get("is_event_script", false)) else "unnamed"
	var body: Array = []
	# The per-handler `global` list is where the declaration lives, and the
	# parser emits a node for it, so it is re-emitted here first -- that is what
	# makes a decoded handler's body start the way a parsed one does.
	var globals: PackedStringArray = handler.get("globals", PackedStringArray())
	if globals.size() > 0:
		var names: Array = []
		for g in globals:
			names.append(g)
		body.append({"node": "global", "names": names, "line": 1})
	body.append_array(_block(0, _ins.size()))
	for left in _stack:
		var kind := "?"
		if typeof(left) == TYPE_DICTIONARY:
			kind = str((left as Dictionary).get("node", "argc-marker"))
		residue_nodes[kind] = int(residue_nodes.get(kind, 0)) + 1
	residue += _stack.size()
	_stack.clear()

	var params: Array = []
	for a in handler.get("args", PackedStringArray()):
		params.append(a)
	return {
		"node": "handler", "name": name, "params": params, "body": body, "line": 1,
	}


# --- control flow ----------------------------------------------------------

## Every `endrepeat` branches backwards to the first instruction of its loop, so
## one scan finds every loop in the handler. Done up front because the walker
## reaches a loop's head long before it reaches the instruction that says it was
## one, and a backward branch discovered late cannot be un-emitted.
func _find_loops() -> void:
	for i in _ins.size():
		var ins: Dictionary = _ins[i]
		if int(ins["op"]) != 0x54:
			continue
		var head := int(ins["pos"]) + int(ins["operand"])
		if not _at.has(head):
			continue
		var loop := {
			"end_index": i,
			"head_index": int(_at[head]),
			"after_pos": int(ins["pos"]) + int(ins["size"]),
			"continue_index": -1,
			"continue_pos": head,
			"counter": "",
			"down": false,
		}
		_note_increment(loop, i)
		_loops[head] = loop


## `repeat with`'s counter step, which Director emits as the last four
## instructions of the loop body: `pushint 1`, `getlocal v`, `add`, `setlocal v`.
##
## Two things need it and both were found by measurement rather than reasoning
## about the format:
##
## - **`next repeat` branches to the step, not to the loop head.** MEASURED on
##   `piposh2/PIP2DATA/ARCADE2.dir` member 139, whose `next repeat` at byte 192
##   jumps to 209 -- exactly the `pushint 1` that begins the step, 8 bytes short
##   of the `endrepeat`. Without this the jump matches no open loop and the
##   statement is lost; that was 25 handlers in `piposh2` alone.
## - **The operand order tells `repeat with` from a hand-written `repeat while`.**
##   Director's step is `1 + v`; a source line reading `v = v + 1` compiles to
##   `v + 1`, the other way round. `AIR1.dir`'s `peopleinroom` is a
##   `repeat while` with its own increment and was being reported as a
##   `repeat with` until this was tightened to require the constant on the left.
func _note_increment(loop: Dictionary, end_index: int) -> void:
	if end_index < 4:
		return
	var push: Dictionary = _ins[end_index - 4]
	var load: Dictionary = _ins[end_index - 3]
	var add: Dictionary = _ins[end_index - 2]
	var store: Dictionary = _ins[end_index - 1]
	if int(load["op"]) not in [0x4b, 0x4c] or int(store["op"]) not in [0x51, 0x52]:
		return
	if int(load["operand"]) != int(store["operand"]):
		return
	# Two shapes, and the operand order is what tells each of them from a
	# hand-written increment in a `repeat while`:
	#
	#   repeat with v = a to b        pushint 1 / getlocal v / add     -> `1 + v`
	#   repeat with v = a down to b   getlocal v / pushint 1 / sub     -> `v - 1`
	#
	# A source line reading `v = v + 1` compiles to `v + 1`, the constant on the
	# right, which neither of these matches. `AIR1.dir`'s `peopleinroom` is
	# exactly that and was being reported as a `repeat with` until the order was
	# required.
	var down := false
	if int(add["op"]) == 0x05:
		if int(push["op"]) not in [0x41, 0x6e, 0x6f] or int(push["operand"]) != 1:
			return
	elif int(add["op"]) == 0x06:
		# `down to` swaps the two: the counter is loaded first and the 1 second,
		# so the four instructions are getlocal / pushint / sub / setlocal.
		if int(push["op"]) not in [0x4b, 0x4c] or int(push["operand"]) != int(store["operand"]):
			return
		if int(load["op"]) not in [0x41, 0x6e, 0x6f] or int(load["operand"]) != 1:
			return
		down = true
	else:
		return
	var counter_ins: Dictionary = push if down else load
	var which := "args" if int(counter_ins["op"]) == 0x4b else "locals"
	loop["continue_index"] = end_index - 4
	loop["continue_pos"] = int(push["pos"])
	loop["down"] = down
	loop["counter"] = _slot(which, int(counter_ins["operand"]), "var")


## Statements for the instruction range `[from, to)`, as indices.
func _block(from: int, to: int) -> Array:
	var out: Array = []
	var i := from
	while i < to and i < _ins.size():
		var ins: Dictionary = _ins[i]
		var pos := int(ins["pos"])
		var op := int(ins["op"])
		if _loops.has(pos) and not _loops_done.has(pos):
			i = _repeat(pos, out, to)
			continue
		match op:
			0x55:
				i = _if(i, to, out)
			0x1c:
				i = _tell(i, to, out)
			0x64:
				if int(ins["operand"]) == 0 and not _stack.is_empty():
					i = _case(i, to, out)
				else:
					i = _straight(i, out)
			0x53:
				i = _bare_jump(i, to, out)
			_:
				i = _straight(i, out)
	return out


## `jmpifz` -> `if`, with the `else` arm recognised by the unconditional jump
## that has to sit immediately before the false target.
##
## The shape is fixed: `<cond> jmpifz T ... jmp E  T: ... E:`. Without the
## trailing `jmp` there is no else arm. The one thing that can impersonate it is
## an `exit repeat` compiled as the last statement of a then-block, which is a
## `jmp` to the enclosing loop's exit -- so a jump whose target is an open loop's
## `after_pos` is never read as an else.
func _if(i: int, to: int, out: Array) -> int:
	var ins: Dictionary = _ins[i]
	var cond := _pop()
	var target := int(ins["pos"]) + int(ins["operand"])
	var t_index := int(_at.get(target, to))
	if t_index > to or t_index <= i:
		t_index = to
	var then_end := t_index
	var else_end := -1
	if t_index - 1 > i:
		var last: Dictionary = _ins[t_index - 1]
		if int(last["op"]) == 0x53:
			var escape := int(last["pos"]) + int(last["operand"])
			if escape > target and not _targets_open_loop(escape) and _at.has(escape):
				then_end = t_index - 1
				else_end = int(_at[escape])
			elif escape > target and escape == _end_pos(to) and not _targets_open_loop(escape):
				# A jump straight past the end of the enclosing range is still an
				# else arm; its target is the range's own end rather than an
				# instruction, which happens when the `if` is the last statement.
				then_end = t_index - 1
				else_end = to
	var then_body := _block(i + 1, then_end)
	# An empty array, not null: the parser's `if` with no `else` carries `[]` and
	# the interpreter executes `stmt.get("else", [])` either way, so null would be
	# a difference that means nothing and shows up on every second handler.
	var else_body: Array = []
	var next := t_index
	if else_end >= 0:
		else_body = _block(t_index, else_end)
		next = else_end
	out.append({
		"node": "if", "cond": cond, "then": then_body, "else": else_body,
		"line": _line_at(int(ins["pos"])),
	})
	return next


## `starttell` ... `endtell` -> `tell`. The target is on the stack when the
## block opens; the body is everything up to the matching `endtell`, nesting
## counted because `tell` can contain `tell`.
func _tell(i: int, to: int, out: Array) -> int:
	var target := _pop()
	var depth := 1
	var j := i + 1
	while j < to:
		var op := int(_ins[j]["op"])
		if op == 0x1c:
			depth += 1
		elif op == 0x1d:
			depth -= 1
			if depth == 0:
				break
		j += 1
	var body := _block(i + 1, mini(j, to))
	out.append({
		"node": "tell", "target": target, "body": body,
		"line": _line_at(int(_ins[i]["pos"])),
	})
	return j + 1


## The loop family. All three share one shape -- head, optional guard, body,
## `endrepeat` back to the head -- and are told apart by what the guard and the
## last statements of the body look like.
##
## `repeat with i = a to b` is the one that needs recognising rather than
## reading: Director compiles it to exactly `repeat while i <= b` plus an
## `i = 1 + i` at the bottom, with the initial `i = a` sitting *before* the loop
## head as an ordinary assignment. So the initialiser has already been emitted
## into the enclosing block by the time the loop is built, and rebuilding the
## `repeat_with` node means taking it back out of it. MEASURED on
## `piposh2/HEZSAVE.DIR` member 6, whose source is `repeat with i = 1 to 8`.
func _repeat(head_pos: int, out: Array, to: int) -> int:
	var loop: Dictionary = _loops[head_pos]
	_loops_done[head_pos] = true
	var head_index := int(loop["head_index"])
	var end_index := int(loop["end_index"])
	var after_pos := int(loop["after_pos"])
	var line := _line_at(head_pos)

	# The guard is the first `jmpifz` between the head and the `endrepeat` whose
	# false target is the instruction after the loop. A loop with none is
	# `repeat forever` and only `exit repeat` leaves it.
	var guard := -1
	for j in range(head_index, end_index):
		if int(_ins[j]["op"]) == 0x55 \
				and int(_ins[j]["pos"]) + int(_ins[j]["operand"]) == after_pos:
			guard = j
			break

	_open_loops.append({"after_pos": after_pos, "head_pos": head_pos,
		"continue_pos": int(loop["continue_pos"]),
		"end_pos": int(_ins[end_index]["pos"])})
	var node: Dictionary = {}
	if guard < 0:
		node = {"node": "repeat_forever", "body": _block(head_index, end_index), "line": line}
	else:
		var before := _stack.size()
		# The guard's condition is straight-line code; anything it emitted as a
		# *statement* is not part of a condition and is kept ahead of the loop.
		out.append_array(_block(head_index, guard))
		var cond := _pop() if _stack.size() > before else {}
		var counter := str(loop["counter"])
		var body_end := end_index
		var down := bool(loop["down"])
		var with_shape := counter != "" and _counts_to(cond, counter, down) 			and _initialises(out, counter)
		if with_shape:
			body_end = int(loop["continue_index"])
		var body := _block(guard + 1, body_end)
		if with_shape:
			var init: Dictionary = out.pop_back()
			node = {"node": "repeat_with", "var": counter, "from": init["value"],
				"to": cond.get("right", {}), "down": down, "body": body, "line": line}
		else:
			node = {"node": "repeat_while", "cond": cond, "body": body, "line": line}
	_open_loops.pop_back()
	out.append(node)
	return end_index + 1


## The guard of a `repeat with`: `<counter> <= <limit>`.
static func _counts_to(cond: Dictionary, counter: String, down: bool) -> bool:
	if cond.get("node", "") != "binary" or str(cond.get("op", "")) != (">=" if down else "<="):
		return false
	var left: Dictionary = cond.get("left", {})
	return left.get("node", "") == "var" and str(left.get("name", "")) == counter


## The `v = <from>` that Director emits **before** the loop head, and which the
## enclosing block has therefore already collected as an ordinary assignment.
## Rebuilding a `repeat_with` node means taking it back out, which is why this
## reaches into the caller's statement list.
static func _initialises(out: Array, counter: String) -> bool:
	if out.is_empty():
		return false
	var init: Dictionary = out[out.size() - 1]
	if init.get("node", "") != "assign":
		return false
	var target: Dictionary = init.get("target", {})
	return target.get("node", "") == "var" and str(target.get("name", "")) == counter


## `case <subject> of` -- an expression left on the stack, then one
## `peek 0 / <value> / eq / jmpifz` test per label, each branch ending in a jump
## to a shared `pop 1` that discards the subject.
##
## It is an if/else-if chain with the subject duplicated instead of re-evaluated,
## which is what `peek` is for, and recognising it is what keeps a decoded `case`
## from expanding into fourteen nested `if`s. MEASURED on
## `piposh/EXCHANGE.dir` member 44, a fourteen-label `case i of`.
func _case(i: int, to: int, out: Array) -> int:
	var subject := _pop()
	var branches: Array = []
	var default: Array = []
	var line := _line_at(int(_ins[i]["pos"]))
	var j := i
	var end := to
	var saw_escape := false
	while j < to and int(_ins[j]["op"]) == 0x64 and int(_ins[j]["operand"]) == 0:
		# `peek 0` duplicates the subject; the comparison consumes the copy.
		var before := _stack.size()
		_stack.append(subject)
		var test := j + 1
		var jump := -1
		while test < to:
			if int(_ins[test]["op"]) == 0x55:
				jump = test
				break
			test = _straight(test, out)
		if jump < 0:
			break
		var cond := _pop() if _stack.size() > before else {}
		var false_target := int(_ins[jump]["pos"]) + int(_ins[jump]["operand"])
		if not _at.has(false_target):
			break
		var false_index := int(_at[false_target])
		var body_end := false_index
		if false_index - 1 > jump and int(_ins[false_index - 1]["op"]) == 0x53:
			var escape := int(_ins[false_index - 1]["pos"]) + int(_ins[false_index - 1]["operand"])
			body_end = false_index - 1
			if _at.has(escape):
				end = int(_at[escape])
				saw_escape = true
		branches.append({
			"values": [cond.get("right", {})] if cond.get("node", "") == "binary" else [cond],
			"body": _block(jump + 1, body_end),
		})
		j = false_index
	# **A `case` whose last branch has nothing to skip emits no escape jump**, so
	# there is nothing to say where the statement ends -- and reading on lands the
	# whole rest of the handler in the `otherwise` arm and then underflows on the
	# `pop` that was meant to drop the subject. MEASURED: 193 underflows in
	# `piposh-dream` alone, every one of them a `pop`, and every one a
	# single-branch `case` with no `otherwise` (`hatul1.dir` member 7, byte 930).
	# With no escape seen, the case ends where the last test's false arm begins.
	if not saw_escape:
		end = j
	# Whatever is left between the last failed test and the shared exit is the
	# `otherwise` arm. `pop 1` at the exit is the subject being discarded and is
	# not a statement.
	if j < end:
		default = _block(j, end)
	var next := end
	if next < _ins.size() and int(_ins[next]["op"]) == 0x65:
		next += 1
	out.append({
		"node": "case", "subject": subject, "branches": branches,
		"default": default, "line": line,
	})
	return next


## A `jmp` the block walker meets on its own is a loop escape: forward past the
## enclosing loop is `exit repeat`, backward to its head or its `endrepeat` is
## `next repeat`. Anything else is a jump this file did not account for, and it
## is reported rather than dropped.
func _bare_jump(i: int, to: int, out: Array) -> int:
	var ins: Dictionary = _ins[i]
	var target := int(ins["pos"]) + int(ins["operand"])
	var line := _line_at(int(ins["pos"]))
	for k in range(_open_loops.size() - 1, -1, -1):
		var loop: Dictionary = _open_loops[k]
		if target == int(loop["after_pos"]):
			out.append({"node": "exit_repeat", "line": line})
			return i + 1
		if target == int(loop["head_pos"]) or target == int(loop["end_pos"]) \
				or target == int(loop["continue_pos"]):
			out.append({"node": "next_repeat", "line": line})
			return i + 1
	# A forward jump to the end of the range is the tail of a structure whose
	# head this walker consumed; it carries no statement of its own.
	if target >= _end_pos(to):
		return i + 1
	_note_unknown(0x53)
	out.append({"node": "unknown_opcode", "op": "jmp", "detail": "target %d" % target,
		"line": line})
	return i + 1


## A jump that leaves or restarts an enclosing loop, which must never be read as
## the `else` arm of an `if`. `exit repeat` and `next repeat` are both a bare
## `jmp` sitting exactly where an else-arm jump sits -- at the end of a
## then-block -- so without this an `if ... next repeat ... end if` grows an else
## containing the rest of the loop body.
func _targets_open_loop(pos: int) -> bool:
	for loop in _open_loops:
		if pos == int(loop["after_pos"]) or pos == int(loop["continue_pos"]) \
				or pos == int(loop["head_pos"]) or pos == int(loop["end_pos"]):
			return true
	return false


func _end_pos(to: int) -> int:
	if to < _ins.size():
		return int(_ins[to]["pos"])
	if _ins.is_empty():
		return 0
	var last: Dictionary = _ins[_ins.size() - 1]
	return int(last["pos"]) + int(last["size"])


# --- straight-line opcodes -------------------------------------------------

## One non-control instruction: pop what it consumes, push what it produces, or
## append the statement it is.
##
## The whole of `docs/LSCR_FORMAT.md` section 7.1 lives here: `swap`, `peek` and
## `pop` are stack machinery with no AST counterpart and never will have one,
## and simulating the stack with **nodes instead of values** is what dissolves
## them. They are three lines below and they are not a gap.
func _straight(i: int, out: Array) -> int:
	var ins: Dictionary = _ins[i]
	var op := int(ins["op"])
	var operand := int(ins["operand"])
	var pos := int(ins["pos"])
	var line := _line_at(pos)
	_current = str(ins["name"])

	if BINARY.has(op):
		var right := _pop()
		var left := _pop()
		_push({"node": "binary", "op": str(BINARY[op]), "left": left, "right": right,
			"line": line})
		return i + 1

	match op:
		0x01, 0x02:
			# **`return <expr>` has no opcode of its own**: the expression is
			# pushed and `ret` is executed with it still on the stack, which is
			# how the caller receives it. So a `ret` facing a non-empty stack is a
			# `return` and a `ret` facing an empty one is the end of the handler
			# -- or, mid-handler, a bare `exit`.
			#
			# MEASURED, and it was the whole of this file's stack residue: 195
			# unconsumed expressions across 15 scripts in the six roots, matching
			# exactly the 195 `return` nodes the parser produced and this file did
			# not. A leftover value is not noise; it is the statement nobody read.
			if not _stack.is_empty():
				out.append({"node": "return", "value": _pop(), "line": line})
			elif i < _ins.size() - 1:
				out.append({"node": "exit", "line": line})
			return i + 1
		0x03:
			_push({"node": "num", "value": 0, "line": line})
		0x41, 0x6e, 0x6f:
			_push({"node": "num", "value": operand, "line": line})
		0x71:
			# `pushfloat32`: the operand is the float's bits, not its value.
			_push({"node": "num", "value": _f32(operand), "line": line})
		0x09:
			_push({"node": "unary", "op": "-", "value": _pop(), "line": line})
		0x14:
			_push({"node": "unary", "op": "not", "value": _pop(), "line": line})
		0x42, 0x43:
			# The argument-count marker. `pusharglistnoret` (0x42) is what makes a
			# call a *command* -- its result is discarded -- and `pusharglist`
			# (0x43) means the value is used, so the `call` node stands alone as
			# an expression. That distinction is the only thing that says which,
			# and section 6 of the format notes it is easy to lose.
			_push({"__argc": operand, "command": op == 0x42})
		0x44:
			_push(_literal(operand, line))
		0x45:
			_push({"node": "sym", "value": _name(operand), "line": line})
		0x46:
			# A variable *reference*, which is a symbol standing for a name. It is
			# only ever consumed by `put`/`putchunk`/`deletechunk`/`objcallv4` as
			# the thing being assigned to, so it is carried as a `var`.
			_push({"node": "var", "name": _name(operand), "line": line})
		0x48, 0x49:
			_push({"node": "var", "name": _name(operand), "line": line})
		0x4a:
			# A property of `me`. The port's scope resolution treats a script
			# property as a plain name in scope, so a `var` is the right node --
			# section 5's own mapping.
			_push({"node": "var", "name": _name(operand), "line": line})
		0x4b:
			_push({"node": "var", "name": _slot("args", operand, "arg"), "line": line})
		0x4c:
			_push({"node": "var", "name": _slot("locals", operand, "var"), "line": line})
		0x4e, 0x4f, 0x50:
			out.append(_assign({"node": "var", "name": _name(operand), "line": line}, line))
		0x51:
			out.append(_assign(
				{"node": "var", "name": _slot("args", operand, "arg"), "line": line}, line))
		0x52:
			out.append(_assign(
				{"node": "var", "name": _slot("locals", operand, "var"), "line": line}, line))
		0x17:
			_push(_chunk_ref(_pop(), line))
		0x18:
			var hilited: Variant = _chunk_ref(_field_ref(_pop(), line), line)
			out.append({"node": "call_stmt", "line": line, "call": {
				"node": "call", "callee": {"node": "var", "name": "hilite", "line": line},
				"args": [hilited], "command": true, "line": line}})
		0x1b:
			_push(_field_ref(null, line))
		0x1d:
			pass # consumed by `_tell`
		0x1e:
			_push({"node": "list", "items": _args(), "line": line})
		0x1f:
			var flat := _args()
			var pairs: Array = []
			var k := 0
			while k + 1 < flat.size():
				pairs.append({"key": flat[k], "value": flat[k + 1]})
				k += 2
			_push({"node": "proplist", "pairs": pairs, "line": line})
		0x21:
			if _stack.size() >= 2:
				var a: Variant = _stack[_stack.size() - 1]
				_stack[_stack.size() - 1] = _stack[_stack.size() - 2]
				_stack[_stack.size() - 2] = a
		0x64:
			var depth := _stack.size() - 1 - operand
			_push(_stack[depth] if depth >= 0 and depth < _stack.size() else {})
		0x65:
			for _n in operand:
				_pop()
		0x56:
			var handlers: Array = _script.get("handlers", [])
			var callee := str(handlers[operand]["name"]) if operand < handlers.size() else "?"
			_call(callee, out, line)
		0x57, 0x63, 0x67:
			_call(_name(operand), out, line)
		0x58:
			# `objcallv4`: the handler name comes from a variable rather than from
			# `Lnam`. Only 26 instructions in six titles, and the reference
			# resolves it the same way -- `findVarV4` hands `LC::call` the name
			# the variable holds.
			var who := _var_target(operand & 0xF, line)
			var dynamic := str(who.get("name", "")) if who.get("node", "") == "var" else ""
			_call(dynamic if dynamic != "" else "?", out, line)
		0x59:
			out.append(_put(operand, false, line))
		0x5a:
			out.append(_put(operand, true, line))
		0x5b:
			var doomed: Variant = _chunk_ref(_var_target(operand & 0xF, line), line)
			out.append({"node": "delete_chunk", "target": doomed, "line": line})
		0x5c:
			_push(_the(operand, line))
		0x5d:
			out.append(_the_assign(operand, line))
		0x5f:
			_push(_prop_node(_name(operand), [_name(operand)], line))
		0x60:
			out.append(_assign(_prop_node(_name(operand), [_name(operand)], line), line))
		0x61, 0x70:
			_push(_object_prop(_pop(), _name(operand), line))
		0x62:
			var value := _pop()
			var object := _pop()
			out.append({"node": "assign", "line": line,
				"target": _object_prop(object, _name(operand), line), "value": value})
		0x66:
			_args() # the argc marker, which the reference expects to be zero
			_push(_prop_node(_name(operand), [_name(operand)], line))
		0x72:
			_push(_prop_node(_name(operand), [_name(operand)], line))
		_:
			# Everything left is `pushchunkvarref` (0x6d) and `newobj` (0x73) --
			# a factory instantiation, for which this port's 46 node types have no
			# counterpart at all (section 7.3) -- plus any opcode a later Director
			# added. An explicit node beats a guess: it keeps the rest of the
			# handler intact and it is greppable.
			_note_unknown(op)
			out.append({"node": "unknown_opcode", "op": str(ins["name"]),
				"detail": "operand %d" % operand, "line": line})
	return i + 1


func _assign(target: Dictionary, line: int) -> Dictionary:
	return {"node": "assign", "target": target, "value": _pop(), "line": line}


## `put` (0x59) and `putchunk` (0x5a). The operand packs the operation into the
## high nibble and the variable type into the low one.
##
## Nibble 1 is `put X into Y` **and** `set Y to X` -- Director compiles both to
## it -- so `assign` is emitted for both and the `put` node is reached only by
## nibbles 2 and 3, `after` and `before`. That collapse cannot be undone and
## `tools/lscr_decode.gd` normalises the source side to match rather than
## counting it as a difference.
func _put(operand: int, chunked: bool, line: int) -> Dictionary:
	var mode := (operand >> 4) & 0xF
	var target := _var_target(operand & 0xF, line)
	if chunked:
		target = _chunk_ref(target, line)
	var value := _pop()
	if mode == 1:
		return {"node": "assign", "target": target, "value": value, "line": line}
	if mode == 2 or mode == 3:
		return {"node": "put", "mode": "after" if mode == 2 else "before",
			"value": value, "target": target, "line": line}
	_note_unknown(0x59)
	return {"node": "unknown_opcode", "op": "put", "detail": "mode %d" % mode, "line": line}


## `findVarV4`'s variable-type nibble resolved to the node it names. Types 1, 2
## and 3 pop a symbol carrying the name; 4 and 5 pop the slot offset, which is
## divided by the same operand divisor as everything else; 6 is a field, which
## pops a cast-lib id first from D5 on.
func _var_target(var_type: int, line: int) -> Dictionary:
	match var_type:
		1, 2, 3:
			var id := _pop()
			var name := str(id.get("name", id.get("value", "")))
			return {"node": "var", "name": name, "line": line}
		4, 5:
			var slot := _pop()
			var index := int(slot.get("value", 0)) / maxi(_divisor, 1)
			var which := "args" if var_type == 4 else "locals"
			var names: PackedStringArray = _handler.get(which, PackedStringArray())
			var fallback := "%s_%d" % ["arg" if var_type == 4 else "var", index]
			return {"node": "var", "line": line,
				"name": names[index] if index >= 0 and index < names.size() else fallback}
		6:
			return _field_ref(null, line)
	_note_unknown(0x59)
	return {"node": "unknown_opcode", "op": "varType", "detail": str(var_type), "line": line}


## `field <member> of castLib <lib>`. The cast-lib id is a separate stack value
## from D5 on (`lingo-code.cpp:c_fieldref`), and this corpus is D7 throughout, so
## it is always popped. `already` is the member when the caller has it in hand.
func _field_ref(already, line: int) -> Dictionary:
	var cast: Variant = _optional_cast(_pop())
	var member: Variant = already if already != null else _pop()
	return {"node": "field", "name": member, "cast": cast, "line": line}


## The cast-library operand, or `null` when the source did not name one.
##
## **Director's compiler always emits a cast-library operand**, pushing zero when
## the source wrote none, because `c_fieldref` and `cb_v4theentitypush`
## unconditionally pop one from D5 on. The port's parser leaves `cast` null in
## that case (`_parse_optional_castlib` returns null), and `toCastMemberID`
## treats 0 the same way -- "no library named, search them in order". MEASURED as
## the largest remaining divergence in `piposh2` once the tables were right: 914
## surplus `num` nodes across 194 handlers, every one of them a zero standing
## where the source said nothing.
static func _optional_cast(node: Dictionary) -> Variant:
	if node.get("node", "") == "num" and int(node.get("value", -1)) == 0:
		return null
	return node


## `readChunkRef`'s eight values, applied outermost first.
##
## The compiler emits all four `first`/`last` pairs whether or not the source
## named them, with zero meaning "not this kind"; that is why a one-item chunk
## expression still costs eight pushes. Popped in the reference's own order --
## lastLine, firstLine, lastItem, firstItem, lastWord, firstWord, lastChar,
## firstChar -- and then wrapped line, item, word, char so the innermost chunk
## kind ends up outermost in the tree, which is how `char 3 of word 2 of x`
## reads.
func _chunk_ref(source: Variant, line: int) -> Variant:
	var last := {}
	var first := {}
	for kind in ["line", "item", "word", "char"]:
		last[kind] = _pop()
		first[kind] = _pop()
	var out: Variant = source
	for kind in CHUNK_ORDER:
		var start: Dictionary = first[kind]
		if start.get("node", "") == "num" and int(start.get("value", 0)) == 0:
			continue
		var stop: Variant = last[kind]
		if typeof(stop) == TYPE_DICTIONARY and stop.get("node", "") == "num" \
				and int(stop.get("value", 0)) == 0:
			stop = null
		out = {"node": "chunk", "kind": kind, "start": start, "stop": stop,
			"source": out, "line": line}
	return out


## `the <entity>` read (0x5c). The bank is the operand; the field selector is the
## first value on the stack; `lscr_the.gd` says what else to pop.
func _the(bank: int, line: int) -> Dictionary:
	var selector := _pop()
	var first_arg := int(selector.get("value", -1))
	var row: Dictionary = TheTable.row(bank, first_arg)
	if row.is_empty():
		_note_unknown(0x5c)
		return {"node": "unknown_opcode", "op": "the",
			"detail": "bank 0x%02x field %d" % [bank, first_arg], "line": line}
	var extra := _the_operands(row, line)
	return _the_node(bank, row, extra, line)


## `the <entity>` write (0x5d). The value is pushed **between** the id and the
## field selector (`cb_v4theentityassign` pops firstArg, then the value, then the
## id), which is the one ordering here that cannot be guessed from the read form.
func _the_assign(bank: int, line: int) -> Dictionary:
	var selector := _pop()
	var first_arg := int(selector.get("value", -1))
	var value := _pop()
	var row: Dictionary = TheTable.row(bank, first_arg)
	if row.is_empty():
		_note_unknown(0x5d)
		return {"node": "unknown_opcode", "op": "set the",
			"detail": "bank 0x%02x field %d" % [bank, first_arg], "line": line}
	var extra := _the_operands(row, line)
	return {"node": "assign", "target": _the_node(bank, row, extra, line), "value": value,
		"line": line}


## What the row's `argsType` pops besides the selector.
func _the_operands(row: Dictionary, line: int) -> Dictionary:
	var args := str(row.get("args", "none"))
	match args:
		"id":
			var id := _pop()
			# `the cast` and `the field` carry a cast-lib id under the member id
			# from D5 on. This corpus is D7 throughout.
			if str(row.get("entity", "")) in ["cast", "field", "member"]:
				return {"which": _pop(), "cast": _optional_cast(id)}
			return {"which": id}
		"string", "chunk":
			return {"which": _pop()}
		"menu":
			return {"which": _pop()}
		"menuitem":
			var item := _pop()
			return {"which": _pop(), "item": item}
	return {}


## Bank -> node, per `docs/LSCR_FORMAT.md` section 5.
##
## Banks 0x02 and 0x03 are the menus, for which this port has **no node at all**;
## they become `unknown_opcode` rather than something plausible, which is the
## whole of section 7.3's entry for them.
func _the_node(bank: int, row: Dictionary, extra: Dictionary, line: int) -> Dictionary:
	var entity := str(row.get("entity", ""))
	var field := str(row.get("field", ""))
	var which: Variant = extra.get("which", null)
	match bank:
		0x01:
			return {"node": "count", "unit": entity.trim_suffix("s"), "source": which,
				"line": line}
		0x02, 0x03:
			_note_unknown(0x5c)
			return {"node": "unknown_opcode", "op": "the menu",
				"detail": "%s %s" % [entity, field], "line": line}
		0x04:
			return {"node": "sound_prop", "prop": field, "which": which, "line": line}
		0x06:
			return {"node": "sprite_prop", "prop": field, "which": which, "line": line}
		0x09, 0x0d:
			# `the number of member "x"` is its own node in this port
			# (`member_number`), not a `member_prop` whose property happens to be
			# called `number` -- the interpreter resolves it to the member's cast
			# index rather than reading a property off the member. MEASURED as the
			# single largest expression divergence in `piposh2`: 238 handlers,
			# 676 nodes.
			if field == "number":
				return {"node": "member_number", "which": which,
					"cast": extra.get("cast", null), "line": line}
			return {"node": "member_prop", "prop": field, "which": which,
				"cast": extra.get("cast", null), "line": line}
		0x0a, 0x0c:
			return {"node": "member_prop", "prop": field, "which": which,
				"cast": extra.get("cast", null), "line": line}
		0x0b:
			return {"node": "field_prop", "prop": field, "name": which,
				"cast": extra.get("cast", null), "line": line}
	# Banks 0x00, 0x07 and 0x08 are movie and system properties. A row with a
	# field is an adjective form -- `the long time` -- which the parser carries in
	# `words`; the four `kTheLast` rows of bank 0x00 are `the last <chunk> of X`
	# and are a chunk expression instead.
	if bank == 0x00 and field == "last":
		return {"node": "chunk", "kind": entity.trim_suffix("s"),
			"start": {"node": "count", "unit": entity.trim_suffix("s"), "source": which,
				"line": line},
			"stop": null, "source": which, "line": line}
	if field == "number":
		return {"node": "count", "unit": entity, "source": which if which != null else {},
			"line": line}
	return _prop_node(entity, [field, entity] if field != "" else [entity], line)


## A bare `the <adjective> <prop>`.
##
## **`words` carries the whole phrase, the property word included** -- the parser
## builds it from every word of `the clickOn` and of `the long time`, so it is
## `["clickon"]` and `["long", "time"]`, not the adjectives alone. Reading it as
## "the adjectives" and emitting `[]` for a one-word property is wrong in exactly
## the common case, and the interpreter's `prop` arm reads `words` rather than
## `prop` for the multi-word forms.
static func _prop_node(prop: String, words: Array, line: int) -> Dictionary:
	var lowered: Array = []
	for word in words:
		lowered.append(str(word).to_lower())
	return {"node": "prop", "prop": prop, "words": lowered, "line": line}


## A call, wrapped in `call_stmt` when the argument marker said the result is
## discarded.
##
## Command syntax has already been resolved by Director's compiler, so the
## keywords the port's parser keeps as arguments are simply not here -- see the
## class comment. What *is* recoverable is section 7.4's `str` versus `sym`
## distinction: `sound playFile 1, x` pushes `playFile` as a symbol, and the
## parser emits it as a **string** because it is command syntax. Converting it
## back is a one-line lookup in `Grammar.COMMAND_WORDS`, and getting it wrong
## makes a handler that decodes cleanly and takes a different interpreter path.
func _call(callee: String, out: Array, line: int) -> void:
	var marker := _peek_marker()
	var args := _args()
	var keywords: Variant = Grammar.COMMAND_WORDS.get(callee.to_lower())
	if keywords != null and args.size() > 0:
		var head: Variant = args[0]
		if typeof(head) == TYPE_DICTIONARY and head.get("node", "") == "sym" \
				and (keywords as Dictionary).has(str(head.get("value", "")).to_lower()):
			args[0] = {"node": "str", "value": str(head["value"]), "line": line}
	var command := bool(marker.get("command", false))
	# `put x` with no `into` is Director's message-window echo, and the parser has
	# a node for it. It compiles to an ordinary call to `put`, which is the same
	# shape as any other command, so the name is the only thing that says so.
	if command and callee.to_lower() == "put" and args.size() == 1:
		out.append({"node": "put_echo", "value": args[0], "line": line})
		return
	var designator := _designator(callee, args, line)
	if not designator.is_empty() and not command:
		_push(designator)
		return
	var call := {"node": "call", "callee": {"node": "var", "name": callee, "line": line},
		"args": args, "command": command, "line": line}
	if command:
		out.append({"node": "call_stmt", "call": call, "line": line})
	else:
		_push(call)


## `getobjprop` / `setobjprop`, which is always a `dot`.
##
## **`sprite(39).visible` and `the visible of sprite 39` compile to the same two
## instructions** -- `sprite(39)` then `getobjprop visible` -- even though the
## property has a `the`-entity bank of its own and even though this port's parser
## keeps them apart, as `dot` and as `sprite_prop`. So the lowering has to pick
## one, and the corpus decides which: folding onto `sprite_prop`/`member_prop`
## was tried and **made agreement worse by a factor of five** -- 395 handlers
## disagreeing instead of 48, 941 surplus `sprite_prop` nodes instead of 196
## surplus `dot`. The dot spelling is what these titles are written in, so `dot`
## is what a decode of them should say. The residual is an ambiguity in the
## bytecode, not a gap in this file, and `tools/lscr_decode.gd` counts it.
static func _object_prop(target: Dictionary, prop: String, line: int) -> Dictionary:
	return {"node": "dot", "target": target, "prop": prop, "line": line}


## `member(...)`, `sprite(...)` and `field(...)` are **reference designators, not
## function calls**, and the bytecode cannot tell you so: all three compile to an
## ordinary `extcall`, because in Director they *are* built-in functions that
## return a reference.
##
## The port's parser has dedicated nodes for them -- `member_ref`, `sprite_ref`,
## `field` -- and `lingo_interpreter.gd` resolves those to real cast and sprite
## references, where a plain `call` would go through the builtin table instead.
## MEASURED: this is the largest single divergence in the corpus, 440 of 3,427
## handlers in `piposh2` alone, and it is the one place where the *reference's*
## reading (everything is a call) and this port's (a designator is a node) are
## genuinely different designs rather than two spellings.
##
## `{}` when the name is not one of the three, or the argument count does not fit
## -- a `member` with three arguments is not a designator and guessing would turn
## a script's own handler named `member` into a cast reference.
static func _designator(callee: String, args: Array, line: int) -> Dictionary:
	match callee.to_lower():
		"member":
			if args.size() == 1 or args.size() == 2:
				return {"node": "member_ref", "which": args[0],
					"cast": args[1] if args.size() > 1 else null, "line": line}
		"sprite":
			if args.size() == 1:
				return {"node": "sprite_ref", "which": args[0], "line": line}
		"field":
			if args.size() == 1 or args.size() == 2:
				return {"node": "field", "name": args[0],
					"cast": args[1] if args.size() > 1 else null, "line": line}
	return {}


# --- stack and table helpers -----------------------------------------------

func _push(node: Variant) -> void:
	_stack.append(node)


func _pop() -> Dictionary:
	if _stack.is_empty():
		residue_nodes["underflow:%s" % _current] = int(
			residue_nodes.get("underflow:%s" % _current, 0)) + 1
		# An underflow means a statement shape consumed more than the compiler
		# pushed, which is a bug in this file rather than in the data. An empty
		# node keeps the walk going so the rest of the handler is still readable,
		# and `residue` plus the harness report say it happened.
		residue += 1
		return {}
	var top: Variant = _stack.pop_back()
	return top if typeof(top) == TYPE_DICTIONARY else {}


## The argument-count marker without consuming it, for deciding `command`.
func _peek_marker() -> Dictionary:
	if _stack.is_empty():
		return {}
	var top: Variant = _stack[_stack.size() - 1]
	return top if typeof(top) == TYPE_DICTIONARY and top.has("__argc") else {}


## Pop the argument marker and the values it covers, bottom-first.
func _args() -> Array:
	var marker := _pop()
	if not marker.has("__argc"):
		# No marker means the shape was not what this file expected; the value is
		# put back rather than lost so the residue count sees it.
		if not marker.is_empty():
			_push(marker)
		return []
	var count := int(marker["__argc"])
	var out: Array = []
	for _i in count:
		out.push_front(_pop())
	return out


func _literal(operand: int, line: int) -> Dictionary:
	var literals: Array = _script.get("literals", [])
	var index := operand / maxi(_divisor, 1)
	if index < 0 or index >= literals.size():
		_note_unknown(0x44)
		return {"node": "unknown_opcode", "op": "pushcons",
			"detail": "literal %d of %d" % [index, literals.size()], "line": line}
	var literal: Dictionary = literals[index]
	match str(literal["type"]):
		"string":
			return {"node": "str", "value": str(literal["value"]), "line": line}
		"int", "float":
			return {"node": "num", "value": literal["value"], "line": line}
	_note_unknown(0x44)
	return {"node": "unknown_opcode", "op": "pushcons",
		"detail": "literal type %s" % str(literal["type"]), "line": line}


func _name(index: int) -> String:
	if _reader == null:
		return ""
	return _reader.name_at(index)


func _slot(which: String, operand: int, prefix: String) -> String:
	var names: PackedStringArray = _handler.get(which, PackedStringArray())
	var index := operand / maxi(_divisor, 1)
	if index >= 0 and index < names.size():
		return names[index]
	return "%s_%d" % [prefix, index]


func _note_unknown(op: int) -> void:
	unknown += 1
	unknown_ops[op] = int(unknown_ops.get(op, 0)) + 1


## Cumulative byte position at which each source line's code begins.
##
## Entry *i* of the line table is the byte count line *i* compiled to, so the
## running sums are the starts. Entry 0 is the first line **inside** the handler
## -- the `on <name>` line is not represented -- and the handler's position in the
## member's source text is not recorded anywhere, so these are **relative** line
## numbers, 1-based from the first line of the body. For a protected movie that
## is all there is; for a member that also carries source text they will not
## match the parser's absolute ones, which is why `tools/lscr_decode.gd` drops
## `line` before comparing.
static func _line_table(handler: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var running := 0
	for count in handler.get("lines", PackedByteArray()):
		out.append(running)
		running += int(count)
	return out


func _line_at(pos: int) -> int:
	var line := 1
	for i in _line_starts.size():
		if _line_starts[i] <= pos:
			line = i + 1
		else:
			break
	return line


static func _f32(bits: int) -> float:
	var raw := PackedByteArray([bits & 0xFF, (bits >> 8) & 0xFF, (bits >> 16) & 0xFF,
		(bits >> 24) & 0xFF])
	return raw.decode_float(0)
