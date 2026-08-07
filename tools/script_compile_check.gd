extends SceneTree
## Does every script in the configured game compile, and did the parser read each
## command's own keywords as keywords?
##
##   godot --headless --path . --script tools/script_compile_check.gd
##   godot --headless --path . --script tools/script_compile_check.gd -- --root piposh-en
##   godot --headless --path . --script tools/script_compile_check.gd -- --verbose
##
## `tools/lingo_parse.gd` asks the first question of **one** container, which is
## the wrong scale for the failure it catches. **A script that does not compile is
## a handler that never runs, and nothing at run time says so.** There is no
## error, no warning and no missing-handler report: the frame's `exitFrame`
## simply does nothing, the playhead advances on the score's own step, and what
## the player sees is a button that does nothing or a scene that goes somewhere
## unrelated. It is only visible from outside, by asking the compiler.
##
## It found the bug it was written for by counting rather than by playing. Piposh
## 1 English lost **27 of `strtgame.dir`'s 75 scripts** to one unsupported
## spelling — `set the searchpath = [...]`, which Director accepts and this parser
## demanded `to` for. Those 27 are the whole `option1`..`option26` CD-drive probe,
## the frames that set `cdsavepath`, `soundspathstart`, `gWinDriveLetter` and
## `whichins` for the rest of the title. With them dead the game still boots,
## which is exactly why it went unnoticed: the probe frames fall through on the
## score's own step and the movie carries on with four globals unset. The Hebrew
## and Russian builds of the same title spell every `set` with `to` and lose
## nothing, so no amount of playing the corpus this port was built on would have
## shown it.
##
## The second question is narrower and has the same shape. Lingo has commands
## whose second word is a keyword rather than an expression — `go to movie x`,
## `sound playFile 1, x`, `open window w` — and `Grammar.COMMAND_WORDS` is the
## list. A keyword that ends up as a *callee* is a misparse, always: Lingo has no
## `movie()`, `frame()` or `window()` function for it to have been, and the
## command it belonged to has lost the word that said what its argument was.
## `go to movie (cdsavepath & "opening.dxr")` came out as `go("to", movie(<path>))`
## — nothing in the arguments looks like a movie, no `movie` keyword survives, and
## the host falls through to its marker branch, finds no marker of that name and
## parks the playhead on frame 0. That is the Start Game button of Piposh 1
## English, whose report was "the music plays and the scene never changes".
##
## Only a *command-form* call is inspected. `open(window("map.dxr"))` is a real
## Lingo reference function inside a real function call and appears 17 times in
## Piposh 2; counting it would make this harness fail on a corpus where nothing
## is wrong.
##
## **Meaningful on any title, and it says how many.** Both checks report the size
## of the set they ran over, so a container tree with no Lingo in it fails the
## third check rather than passing the first two over nothing.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Grammar := preload("res://lingo/compile/lingo_grammar.gd")

## How many of each failure to print before summarising. A corpus-wide sweep can
## report hundreds of one spelling, and eight is enough to see which spelling.
const SHOWN := 8

var _misparsed: Array[String] = []
var _where := ""


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var files: Array[String] = []
	_walk(paths.root, files)
	files.sort()

	var scripts := 0
	var carrying := 0
	var failures: Array[String] = []
	var started := Time.get_ticks_msec()

	for path in files:
		var f := ContainerFile.new()
		if not f.open(path):
			# Not this harness's question -- `tools/container_versions.gd` asks
			# whether every container opens, and two harnesses failing on one
			# unreadable file report one fault as two.
			continue
		var cast := Cast.new()
		if not cast.open(f):
			f.close()
			continue
		var compiler := Compiler.new()
		var here := 0
		for number in cast.member_numbers():
			var member: Dictionary = cast.member(number)
			var source := str(member.get("source", ""))
			if source.strip_edges() == "":
				continue
			scripts += 1
			here += 1
			var key := Compiler.script_key(member, number)
			var ast := compiler.compile_source(source, key)
			if ast.is_empty():
				failures.append("%s %s: line %d: %s" % [
					path.get_file(), key, compiler.error_line, compiler.error])
				continue
			_where = "%s %s" % [path.get_file(), key]
			_scan(ast, null)
		if here > 0:
			carrying += 1
		f.close()

	print("%s" % paths.root)
	print("  containers        : %d  (%d carry Lingo)" % [files.size(), carrying])
	print("  scripts compiled  : %d of %d" % [scripts - failures.size(), scripts])
	print("  elapsed           : %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))

	var verbose := Args.flag(args, "verbose")
	h.begin("the configured game's Lingo compiles")
	h.check("every script compiles", failures.is_empty(),
		"%d of %d failed" % [failures.size(), scripts])
	_report(failures, verbose)
	h.check("no command keyword was parsed as a function call", _misparsed.is_empty(),
		"%d statement(s)" % _misparsed.size())
	_report(_misparsed, verbose)
	# The guard against a green run over nothing: a root with no Lingo in it must
	# report that, not pass two checks it never ran. `gate.sh` refuses a harness
	# that passes with zero checks; this refuses one that passes with zero
	# subjects, which the check count alone cannot see.
	h.check("there was Lingo to compile", scripts > 0, "%d script(s)" % scripts)
	h.complete("the configured game's Lingo compiles")
	quit(h.finish("every handler in the configured game can actually run"))


static func _report(lines: Array[String], verbose: bool) -> void:
	var show: int = lines.size() if verbose else mini(SHOWN, lines.size())
	for i in show:
		print("      %s" % lines[i])
	if show < lines.size():
		print("      ... and %d more (pass --verbose)" % (lines.size() - show))


## Walk an AST looking for a command's own keyword standing where a callee goes.
##
## `keywords` is the set belonging to the command-form call this node is an
## argument of, or null anywhere else — which is what keeps a plain
## `open(window("map.dxr"))` out of the count. It is threaded down rather than
## re-derived at each node because the same word is only wrong *in that position*:
## `window` is a legitimate function everywhere else in the language.
func _scan(node: Variant, keywords: Variant) -> void:
	if typeof(node) == TYPE_ARRAY:
		for item in node:
			_scan(item, keywords)
		return
	if typeof(node) != TYPE_DICTIONARY:
		return
	var d: Dictionary = node
	if str(d.get("node", "")) != "call":
		for key in d:
			_scan(d[key], keywords)
		return
	var callee: Variant = d.get("callee")
	var name := ""
	if typeof(callee) == TYPE_DICTIONARY and str(callee.get("node", "")) == "var":
		name = str(callee.get("name", "")).to_lower()
	if keywords != null and (keywords as Dictionary).has(name):
		_misparsed.append("%s line %s: `%s` reads as a call, not as %s's keyword" % [
			_where, str(d.get("line", "?")), name, _command_owning(name)])
	var own: Variant = null
	if bool(d.get("command", false)):
		own = Grammar.COMMAND_WORDS.get(name)
	for a in d.get("args", []):
		_scan(a, own)


## Which command a keyword belongs to, for the message. Read off the grammar so
## the report cannot name a command the parser does not agree with.
static func _command_owning(word: String) -> String:
	var owners: Array[String] = []
	for command in Grammar.COMMAND_WORDS:
		if (Grammar.COMMAND_WORDS[command] as Dictionary).has(word):
			owners.append("`%s`" % command)
	return " or ".join(owners) if not owners.is_empty() else "any command"


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
