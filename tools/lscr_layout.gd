extends SceneTree
## Does the compiled-Lingo chunk layout decode, and does it agree with the source
## text sitting beside it?
##
##   godot --headless --path . --script tools/lscr_layout.gd
##   godot --headless --path . --script tools/lscr_layout.gd -- --root piposh-en
##   godot --headless --path . --script tools/lscr_layout.gd -- --all --verbose
##
## `director/director_lscr.gd` reads `Lnam`, `Lctx` and the `Lscr` header,
## literal table and handler records. Every one of those is a fixed-shape table,
## so the way it fails is **silently**: a stride off by four still produces
## numbers, and a desynced handler table emits plausible-looking small operands
## that a disassembler will happily turn into instructions. `docs/LSCR_FORMAT.md`
## section 4.2 records that exact failure happening while the document was being
## written.
##
## So this harness does not check the reader against itself. It checks it against
## a source outside the pipeline, which is `AGENTS.md`'s rule for any decode:
##
## 1. **The handler count and the handler names must match the member's own
##    source text.** 38,396 members in this corpus carry *both* a compiled script
##    and the Lingo it was compiled from, and the source is not something the
##    decoder can influence -- it comes out of a different item of a different
##    block of the cast member. A wrong `Lctx` index, a wrong `Lnam`, a wrong
##    handler stride or a wrong `handlersOffset` each break this and they break
##    it loudly.
## 2. **The record chain must close.** `argumentOffset == compiledOffset +
##    compiledLength`, `localsOffset == argumentOffset + argumentCount * 2`, and
##    consecutive records abutting through the line table. These are internal, so
##    they are weaker evidence than (1) -- but they are the only evidence
##    available for a *protected* movie, which is the case this whole decoder
##    exists for, so they are asserted in their own right.
## 3. **The detected sizes must agree with the version-derived ones** wherever
##    the container states a version. `director_lscr.gd` derives the literal
##    stride, the handler stride and the operand divisor from each chunk's own
##    arithmetic, because an external cast has no config chunk to state a
##    version. That derivation has to be checked where a version does exist, or
##    it is an unfalsifiable guess that happens to be applied everywhere.
##
## The three together are what make the mmap-order fallback for a container with
## no `Lctx` (`MASTER.CST`, 40 scripts) checkable at all: check (1) runs on it
## member by member, which `docs/LSCR_FORMAT.md` section 2 asks for and could not
## do by hand.
##
## Title-agnostic. `--all` sweeps every root under `games/`.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Lscr := preload("res://director/director_lscr.gd")

const SHOWN := 8

var _name_mismatch: Array[String] = []
var _chain_broken: Array[String] = []
var _size_disagreed: Array[String] = []


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

	var containers := 0
	var with_lingo := 0
	var fallback := 0
	var scripts := 0
	var handlers := 0
	var compared := 0
	var started := Time.get_ticks_msec()

	for root_name in roots:
		var root := Paths.games_dir().path_join(root_name)
		var files: Array[String] = []
		_walk(root, files)
		files.sort()
		for path in files:
			containers += 1
			var f := ContainerFile.new()
			if not f.open(path):
				continue
			var reader := Lscr.new()
			if not reader.open(f):
				f.close()
				continue
			with_lingo += 1
			if reader.mmap_fallback:
				fallback += 1
			_check_sizes(reader, path)
			var cast := Cast.new()
			var have_cast := cast.open(f)
			var live: Dictionary = reader.live_scripts()
			for script_id in live:
				var decoded: Dictionary = reader.read_script(int(live[script_id]))
				if decoded.is_empty():
					continue
				scripts += 1
				handlers += (decoded["handlers"] as Array).size()
				_check_chain(decoded, path)
			if have_cast:
				compared += _compare_to_source(reader, cast, path)
			f.close()

	print("roots: %s" % ", ".join(roots))
	print("  containers            : %d  (%d carry compiled Lingo)" % [containers, with_lingo])
	print("  no Lctx (mmap order)  : %d" % fallback)
	print("  Lscr chunks decoded   : %d" % scripts)
	print("  handler records       : %d" % handlers)
	print("  members with both     : %d  (bytecode and source text)" % compared)
	print("  elapsed               : %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))

	h.begin("the compiled-Lingo chunk layout decodes")
	h.check("every decoded handler table matches the member's own source text",
		_name_mismatch.is_empty(), "%d member(s) disagree" % _name_mismatch.size())
	_report(_name_mismatch, verbose)
	h.check("every handler record's offset chain closes",
		_chain_broken.is_empty(), "%d record(s) broken" % _chain_broken.size())
	_report(_chain_broken, verbose)
	h.check("detected sizes agree with the stated file version",
		_size_disagreed.is_empty(), "%d container(s) disagree" % _size_disagreed.size())
	_report(_size_disagreed, verbose)
	# The guard against a green run over nothing. A root with no compiled Lingo
	# would otherwise pass three checks it never ran -- and the whole point of
	# this decoder is the container whose *source* is missing, so "there was
	# bytecode" and "there was something to compare it against" are separate
	# facts and both are worth stating.
	h.check("there was compiled Lingo to decode", scripts > 0, "%d script(s)" % scripts)
	h.check("there were members carrying both forms", compared > 0, "%d member(s)" % compared)
	h.complete("the compiled-Lingo chunk layout decodes")
	quit(h.finish("Lnam, Lctx and the Lscr tables read the same program the source text does"))


## The check that comes from outside the decoder: a member carrying both forms
## must yield the same handlers either way.
##
## Only members that have both are compared, and the count is reported, because a
## member with no source text is the case this decoder exists for and cannot be
## checked this way at all.
func _compare_to_source(reader, cast, path: String) -> int:
	var compared := 0
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
		var decoded: Dictionary = reader.read_script(chunk)
		if decoded.is_empty():
			continue
		compared += 1
		var want := _declared_handlers(source)
		var got := PackedStringArray()
		for handler in decoded["handlers"]:
			got.append(str(handler["name"]).to_lower())
		# An **event script** (`kScriptFlagEventScript`) has an unnamed handler 0
		# holding top-level Lingo that was never introduced by an `on` line, so
		# the source has one fewer declaration than the chunk has handlers. That
		# is a real shape, not a mismatch, and it is dropped from the comparison
		# rather than allowed to fail it.
		if bool(decoded["is_event_script"]) and got.size() > 0 and got[0] == "":
			got.remove_at(0)
		if _sorted(want) != _sorted(got):
			_name_mismatch.append("%s member %d: source declares [%s], chunk %d holds [%s]" % [
				path.get_file(), number, ", ".join(want), chunk, ", ".join(got)])
	return compared


## The handler names a Lingo source text declares, lowercased.
##
## Deliberately a scanner rather than the real parser: the real parser is the
## thing the *next* harness compares against, and using it here would make a
## parser bug look like a decoder bug. Comments are stripped first because `-- on
## mouseUp` appears in this corpus and would otherwise be counted.
static func _declared_handlers(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw_line in source.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var line := _strip_comment(str(raw_line)).strip_edges()
		if line == "":
			continue
		var words := line.split(" ", false)
		if words.size() < 2:
			continue
		var head := str(words[0]).to_lower()
		if head != "on" and head != "factory" and head != "method":
			continue
		var name := str(words[1]).to_lower()
		# `on mouseUp me` and `on mouseUp(me)` both declare `mouseup`.
		var paren := name.find("(")
		if paren >= 0:
			name = name.substr(0, paren)
		if name != "":
			out.append(name)
	return out


## `--` starts a comment except inside a string literal.
static func _strip_comment(line: String) -> String:
	var in_string := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\"":
			in_string = not in_string
		elif not in_string and c == "-" and i + 1 < line.length() and line[i + 1] == "-":
			return line.substr(0, i)
		i += 1
	return line


static func _sorted(a: PackedStringArray) -> Array:
	var out: Array = []
	for s in a:
		out.append(s)
	out.sort()
	return out


func _check_chain(decoded: Dictionary, path: String) -> void:
	# Reconstructed from what the reader kept rather than re-read from the bytes,
	# so this asserts the records the rest of the port will actually use. A check
	# that re-derived the offsets would be agreeing with its own arithmetic,
	# which is the shape `porting-fidelity-verification` warns about.
	var previous := -1
	for handler in decoded["handlers"]:
		var code: PackedByteArray = handler["code"]
		var at := int(handler["code_offset"])
		var where := "%s chunk %d handler %s" % [
			path.get_file(), int(decoded["chunk_id"]), str(handler["name"])]
		if code.is_empty() and at == 0:
			_chain_broken.append("%s: no bytecode at all" % where)
			continue
		# A handler's five regions abut in this order: bytecode, argument name
		# indices, local name indices, global name indices, line table. Each is
		# an independent constraint on the stride the record was read at, which
		# is what makes them worth asserting one at a time rather than as one
		# pass/fail: a record read four bytes wrong fails a different one of them
		# depending on which field crossed the boundary.
		var arg_at := int(handler["arg_offset"])
		var local_at := int(handler["local_offset"])
		var global_at := int(handler["global_offset"])
		var line_at := int(handler["line_offset"])
		var args: PackedStringArray = handler["args"]
		var locals: PackedStringArray = handler["locals"]
		if not _abuts(arg_at, at + code.size()):
			_chain_broken.append("%s: arguments at %d, bytecode ends at %d" % [
				where, arg_at, at + code.size()])
		elif local_at != arg_at + args.size() * 2:
			_chain_broken.append("%s: locals at %d, %d argument(s) end at %d" % [
				where, local_at, args.size(), arg_at + args.size() * 2])
		elif global_at < local_at + locals.size() * 2:
			_chain_broken.append("%s: globals at %d, %d local(s) end at %d" % [
				where, global_at, locals.size(), local_at + locals.size() * 2])
		elif line_at < global_at:
			_chain_broken.append("%s: line table at %d, before the globals at %d" % [
				where, line_at, global_at])
		# And consecutive records abut through the line table: the next
		# handler's bytecode starts where the previous handler's line table
		# ended, or one byte later for 2-byte alignment. **This is the rule that
		# discriminates 42 from 46** -- `DAY1.dir`'s five multi-handler scripts
		# close 5 of 5 at 46 and 0 of 5 at 42 -- so it is the one worth naming.
		if previous >= 0 and not _abuts(at, previous):
			_chain_broken.append("%s: bytecode starts at %d, previous line table ends at %d" % [
				where, at, previous])
		previous = line_at + int(handler["line_count"])


## Every table inside a handler record starts on a **2-byte boundary**, so a
## region whose predecessor ended on an odd byte begins one byte later.
##
## MEASURED, and it is the reason this check first reported 17,830 broken records
## against a decode that had already matched 38,396 members' source text
## handler-for-handler: an odd `compiledLength` is the common case, so
## `argumentOffset == compiledOffset + compiledLength` holds only up to the pad.
## `docs/LSCR_FORMAT.md` states the tolerance for the record-to-record rule and
## not for the three inside a record; it applies to all four.
static func _abuts(at: int, want: int) -> bool:
	return at == want or at == want + 1


func _check_sizes(reader, path: String) -> void:
	if reader.raw_version <= 0:
		return
	var want: Dictionary = Lscr.sizes_for(reader.human)
	for script_id in reader.live_scripts().values():
		var decoded: Dictionary = reader.read_script(int(script_id))
		if decoded.is_empty():
			continue
		# A chunk with no handler and no literal cannot reveal a stride, so its
		# detection falls back on the version and agreeing proves nothing. Skip
		# rather than counting a tautology as evidence.
		if (decoded["handlers"] as Array).is_empty() and (decoded["literals"] as Array).is_empty():
			continue
		if int(decoded["handler_stride"]) != int(want["handler"]) \
				or int(decoded["divisor"]) != int(want["divisor"]):
			_size_disagreed.append(
				"%s chunk %d: version 0x%X (%d) wants handler %d / divisor %d, detected %d / %d" % [
					path.get_file(), int(decoded["chunk_id"]), reader.raw_version, reader.human,
					int(want["handler"]), int(want["divisor"]),
					int(decoded["handler_stride"]), int(decoded["divisor"])])
			return


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
