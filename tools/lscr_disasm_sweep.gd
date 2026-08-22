extends SceneTree
## Does the bytecode stream stay in sync, over every compiled handler in a corpus?
##
##   godot --headless --path . --script tools/lscr_disasm_sweep.gd
##   godot --headless --path . --script tools/lscr_disasm_sweep.gd -- --all --histogram
##   godot --headless --path . --script tools/lscr_disasm_sweep.gd -- --root rating --verbose
##
## `lingo/compile/lscr_disasm.gd` decodes an opcode byte into an operation and an
## operand width by arithmetic. There is no framing, no length prefix and no
## terminator: **one instruction sized wrong desynchronises the rest of the
## handler**, and a desynchronised stream does not stop -- it keeps emitting
## plausible small operands off the wrong byte boundaries until it runs out.
## `docs/LSCR_FORMAT.md` section 4.2 records exactly that happening and producing
## an answer that looked reasonable enough to be written down.
##
## Three properties catch it, and none of them needs to know what the program
## means:
##
## 1. **The instructions cover the handler exactly.** `compiledLength` is stated
##    in the handler record, and the decode must end on it, not one byte short
##    and not past it. A single mis-sized instruction shifts every later one and
##    almost always lands off the end.
## 2. **Every jump target is an instruction boundary.** `jmp`, `jmpifz` and
##    `endrepeat` compute `pos + operand` in handler-relative bytes, and a
##    correctly-decoded stream can only branch to the start of an instruction.
##    This is the strong one: it is thousands of independent constraints per
##    corpus, each testing the sizes of every instruction between the branch and
##    its target.
## 3. **The last instruction of a handler is a return.** Every handler ends
##    `ret` (0x01) or `retfactory` (0x02); a stream that ends anywhere else did
##    not end where the record said it would.
##
## The histogram is the other half of the value and is a survey rather than an
## assertion: it says which opcodes this corpus actually exercises, so a claim
## that some arm is covered can be checked instead of assumed. Per `AGENTS.md`,
## a zero in it is a fact about the roots it was run over -- which is why the
## report names them.
##
## Title-agnostic. `--all` sweeps every root under `games/`.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Paths := preload("res://director/director_paths.gd")
const Lscr := preload("res://director/director_lscr.gd")
const Disasm := preload("res://lingo/compile/lscr_disasm.gd")

const SHOWN := 8
## The three branch opcodes, whose operand is a byte delta from their own
## position. `endrepeat` has already been negated by the disassembler.
const BRANCHES := {0x53: true, 0x54: true, 0x55: true}

var _truncated: Array[String] = []
var _uncovered: Array[String] = []
var _bad_target: Array[String] = []
var _no_return: Array[String] = []
var _histogram: Dictionary = {}


func _init() -> void:
	var args := Args.parse()
	var verbose := Args.flag(args, "verbose")
	var h := Harness.new()

	var roots: Array[String] = []
	if Args.flag(args, "all"):
		var dir := DirAccess.open(Paths.games_dir())
		if dir != null:
			for sub in dir.get_directories():
				roots.append(sub)
		roots.sort()
	else:
		var paths := Paths.new()
		if not paths.load_config():
			print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
			quit(1)
			return
		roots.append(paths.root.get_file())

	var handlers := 0
	var instructions := 0
	var branches := 0
	var started := Time.get_ticks_msec()

	for root_name in roots:
		var root := Paths.games_dir().path_join(root_name)
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		for path in files:
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var reader := Lscr.new()
			if not reader.open(f):
				f.close()
				continue
			for script_id in reader.live_scripts().values():
				var decoded: Dictionary = reader.read_script(int(script_id))
				if decoded.is_empty():
					continue
				for handler in decoded["handlers"]:
					var counted := _sweep(handler, decoded, path)
					handlers += 1
					instructions += int(counted["instructions"])
					branches += int(counted["branches"])
			f.close()

	print("roots: %s" % ", ".join(roots))
	print("  handlers disassembled : %d" % handlers)
	print("  instructions          : %d" % instructions)
	print("  branch instructions   : %d" % branches)
	print("  distinct opcodes      : %d" % _histogram.size())
	print("  elapsed               : %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if Args.flag(args, "histogram"):
		_print_histogram()

	h.begin("compiled Lingo disassembles without desynchronising")
	h.check("no handler's instruction stream runs out of bytes",
		_truncated.is_empty(), "%d handler(s)" % _truncated.size())
	_report(_truncated, verbose)
	h.check("every handler's instructions cover its stated compiledLength exactly",
		_uncovered.is_empty(), "%d handler(s)" % _uncovered.size())
	_report(_uncovered, verbose)
	h.check("every jump target lands on an instruction boundary",
		_bad_target.is_empty(), "%d branch(es)" % _bad_target.size())
	_report(_bad_target, verbose)
	h.check("every handler ends on a return", _no_return.is_empty(),
		"%d handler(s)" % _no_return.size())
	_report(_no_return, verbose)
	# Both guards against a green run over nothing, and they are separate facts:
	# a corpus could carry handlers and no branch at all, in which case the check
	# that matters most above passed over an empty set.
	h.check("there were handlers to disassemble", handlers > 0, "%d" % handlers)
	h.check("there were branches to resolve", branches > 0, "%d" % branches)
	h.complete("compiled Lingo disassembles without desynchronising")
	quit(h.finish("the size-class rule holds across every compiled handler in the corpus"))


func _sweep(handler: Dictionary, decoded: Dictionary, path: String) -> Dictionary:
	var code: PackedByteArray = handler["code"]
	var where := "%s chunk %d %s" % [
		path.get_file(), int(decoded["chunk_id"]), str(handler["name"])]
	var result: Dictionary = Disasm.decode(code)
	var listing: Array = result["instructions"]
	if str(result["error"]) != "":
		_truncated.append("%s: %s" % [where, str(result["error"])])
	var branches := 0
	for ins in listing:
		var op := int(ins["op"])
		_histogram[op] = int(_histogram.get(op, 0)) + 1
		if BRANCHES.has(op):
			branches += 1
	if listing.is_empty():
		# A zero-length handler is not a decode failure -- `MASTER.CST`'s
		# `jokesfunk` is one byte of `ret` and an empty one is possible -- but it
		# also cannot end on a return, so it is excluded from that check rather
		# than counted as failing it.
		if not code.is_empty():
			_uncovered.append("%s: %d byte(s) decoded to no instruction" % [where, code.size()])
		return {"instructions": 0, "branches": 0}

	var last: Dictionary = listing[listing.size() - 1]
	var covered := int(last["pos"]) + int(last["size"])
	if covered != code.size():
		_uncovered.append("%s: %d instruction(s) cover %d of %d bytes" % [
			where, listing.size(), covered, code.size()])
	elif int(last["op"]) != 0x01 and int(last["op"]) != 0x02:
		_no_return.append("%s: ends on %s, not a return" % [where, str(last["name"])])

	var boundaries: Dictionary = Disasm.positions(listing)
	for ins in listing:
		if not BRANCHES.has(int(ins["op"])):
			continue
		# `target = (byte position of the opcode) + operand`, in handler-relative
		# bytes. **Not** ScummVM's rule: it computes in instruction-index space
		# because it re-emits into its own array where one slot is one word.
		# Working on raw bytes, the byte rule is the one that closes -- and
		# `docs/LSCR_FORMAT.md` section 6 pins it on three independent jumps.
		var target := int(ins["pos"]) + int(ins["operand"])
		# The end of the handler is a legal target: a forward jump over the last
		# statement lands one past the final instruction.
		if target == code.size():
			continue
		if not boundaries.has(target):
			_bad_target.append("%s: %s at %d targets %d, not an instruction boundary" % [
				where, str(ins["name"]), int(ins["pos"]), target])
	return {"instructions": listing.size(), "branches": branches}


func _print_histogram() -> void:
	var keys: Array = _histogram.keys()
	keys.sort()
	print("  opcode histogram (canonical opcode, name, count):")
	for op in keys:
		print("      0x%02x  %-18s %d" % [
			int(op), str(Disasm.NAMES.get(int(op), "unknown")), int(_histogram[op])])
	var missing: Array = []
	for op in Disasm.NAMES:
		if not _histogram.has(op):
			missing.append("0x%02x %s" % [int(op), str(Disasm.NAMES[op])])
	print("  named but not exercised by these roots: %s" % (
		", ".join(missing) if not missing.is_empty() else "none"))


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
