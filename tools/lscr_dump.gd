extends SceneTree
## One compiled script, printed: header, tables, disassembly, and the source text
## beside it where the member carries both.
##
##   godot --headless --path . --script tools/lscr_dump.gd -- --file PIP2DATA/BYAIR.cst --member 61
##   godot --headless --path . --script tools/lscr_dump.gd -- --file MASTER.CST --script-id 1
##   godot --headless --path . --script tools/lscr_dump.gd -- --file X.dir --find "repeat with"
##   godot --headless --path . --script tools/lscr_dump.gd -- --root rating --find "case" --limit 2
##
## The survey tools (`lscr_layout`, `lscr_disasm_sweep`, `lscr_decode`) answer
## "does it hold over the corpus"; this answers "what does *this* one look like",
## which is the question you have when one of them goes red or when a construct
## has to be lowered and nobody has seen how Director compiles it.
##
## `--find <text>` is the useful mode: it searches every member's **source text**
## for a phrase and dumps the compiled form of the ones that match. That is how
## `repeat with`, `case` and `tell` were read off real data rather than guessed
## at -- the source says which construct you are looking at and the disassembly
## says what it became, on the same screen.
##
## A survey, not a gate. It asserts nothing and is not in `gate.sh`.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Lscr := preload("res://director/director_lscr.gd")
const Disasm := preload("res://lingo/compile/lscr_disasm.gd")


func _init() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var files: Array[String] = []
	var wanted := Args.text(args, "file", "")
	if wanted != "":
		var resolved := paths.resolve(wanted)
		if resolved == "":
			print("no such container: %s" % wanted)
			quit(1)
			return
		files.append(resolved)
	else:
		_walk(paths.root, files)
		files.sort()

	var find := Args.text(args, "find", "").to_lower()
	var want_member := Args.number(args, "member", -1)
	var want_script := Args.number(args, "script-id", -1)
	var limit := Args.number(args, "limit", 4 if find != "" else 1000000)
	var shown := 0

	for path in files:
		if shown >= limit:
			break
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var reader := Lscr.new()
		if not reader.open(f):
			f.close()
			continue
		var cast := Cast.new()
		var have_cast := cast.open(f)
		if want_script >= 0:
			shown += _dump(reader, path, want_script, reader.chunk_for_script_id(want_script), "")
			f.close()
			continue
		if not have_cast:
			f.close()
			continue
		for number in cast.member_numbers():
			if shown >= limit:
				break
			var member: Dictionary = cast.member(number)
			var script_id := int(member.get("script_id", 0))
			if script_id <= 0:
				continue
			if want_member >= 0 and number != want_member:
				continue
			var source := str(member.get("source", ""))
			if find != "" and not source.to_lower().contains(find):
				continue
			var chunk: int = reader.chunk_for_script_id(script_id)
			if chunk < 0:
				continue
			shown += _dump(reader, path, script_id, chunk, source, number)
		f.close()
	if shown == 0:
		print("nothing matched")
	quit(0)


func _dump(reader, path: String, script_id: int, chunk: int, source: String, member := -1) -> int:
	if chunk < 0:
		print("script_id %d resolves to no chunk" % script_id)
		return 0
	var s: Dictionary = reader.read_script(chunk)
	if s.is_empty():
		print("chunk %d: %s" % [chunk, reader.error])
		return 0
	print("")
	print("=== %s  member %d  script_id %d  -> chunk %d ===" % [
		path.get_file(), member, script_id, chunk])
	print("  version 0x%X (%d)   handler stride %d   literal stride %d   divisor %d%s" % [
		reader.raw_version, reader.human, int(s["handler_stride"]), int(s["literal_stride"]),
		int(s["divisor"]), "   [no Lctx: mmap order]" if reader.mmap_fallback else ""])
	print("  flags 0x%X%s%s   parent %d   factory %s" % [
		int(s["flags"]), "  FACTORY" if bool(s["is_factory"]) else "",
		"  EVENT" if bool(s["is_event_script"]) else "",
		int(s["parent_number"]), JSON.stringify(str(s["factory_name"]))])
	print("  properties: %s" % str(s["properties"]))
	print("  globals   : %s" % str(s["globals"]))
	print("  literals  :")
	var literals: Array = s["literals"]
	for i in literals.size():
		print("      %3d  %-7s %s" % [
			i, str(literals[i]["type"]), JSON.stringify(literals[i]["value"])])
	if source.strip_edges() != "":
		print("  source text:")
		var line_number := 0
		for line in source.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
			line_number += 1
			print("      %3d | %s" % [line_number, line])
	for handler in s["handlers"]:
		_dump_handler(reader, s, handler)
	return 1


func _dump_handler(reader, s: Dictionary, handler: Dictionary) -> void:
	var code: PackedByteArray = handler["code"]
	print("  --- on %s (%s) --- %d byte(s) at %d, %d line entries" % [
		str(handler["name"]), ", ".join(handler["args"]), code.size(),
		int(handler["code_offset"]), int(handler["line_count"])])
	if (handler["locals"] as PackedStringArray).size() > 0:
		print("      locals : %s" % str(handler["locals"]))
	if (handler["globals"] as PackedStringArray).size() > 0:
		print("      globals: %s" % str(handler["globals"]))
	var lines: PackedByteArray = handler["lines"]
	if not lines.is_empty():
		var sums := PackedInt32Array()
		var running := 0
		for b in lines:
			sums.append(running)
			running += b
		print("      lines  : %s (sum %d of %d)" % [str(sums), running, code.size()])
	var result: Dictionary = Disasm.decode(code)
	if str(result["error"]) != "":
		print("      DECODE ERROR: %s" % str(result["error"]))
	for ins in result["instructions"]:
		print("      %s%s" % [Disasm.text(ins), _annotate(reader, s, handler, ins)])


## The operand in human terms: which name, which literal, which target. Kept
## here and out of `lscr_disasm.gd`, which deliberately cannot see the script.
func _annotate(reader, s: Dictionary, handler: Dictionary, ins: Dictionary) -> String:
	var op := int(ins["op"])
	var operand := int(ins["operand"])
	var divisor := int(s["divisor"])
	match op:
		0x44:
			var index := operand / divisor
			var literals: Array = s["literals"]
			if index >= 0 and index < literals.size():
				return "   ; %s" % JSON.stringify(literals[index]["value"])
			return "   ; literal %d out of range" % index
		0x45, 0x46, 0x49, 0x48, 0x4f, 0x4e, 0x4a, 0x50, 0x57, 0x63, 0x67, 0x5f, 0x60, 0x61, \
		0x62, 0x66, 0x70, 0x72, 0x73:
			return "   ; %s" % reader.name_at(operand)
		0x4b, 0x51:
			var args: PackedStringArray = handler["args"]
			var i := operand / divisor
			return "   ; %s" % (args[i] if i >= 0 and i < args.size() else "arg?%d" % i)
		0x4c, 0x52:
			var locals: PackedStringArray = handler["locals"]
			var j := operand / divisor
			return "   ; %s" % (locals[j] if j >= 0 and j < locals.size() else "local?%d" % j)
		0x53, 0x54, 0x55:
			return "   -> %d" % (int(ins["pos"]) + operand)
		0x56:
			var handlers: Array = s["handlers"]
			if operand >= 0 and operand < handlers.size():
				return "   ; %s" % str(handlers[operand]["name"])
			return "   ; handler %d out of range" % operand
		0x59, 0x5a, 0x5b:
			return "   ; op %d, var type %d" % [(operand >> 4) & 0xF, operand & 0xF]
		0x5c, 0x5d:
			return "   ; bank 0x%02x" % operand
	return ""


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
