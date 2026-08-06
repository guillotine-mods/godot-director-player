extends SceneTree
## Compile the Lingo inside a container and report the fraction that parses.
##
##   godot --headless --script tools/lingo_parse.gd -- --file PIP2DATA/DAY1.DIR
##   godot --headless --script tools/lingo_parse.gd -- --file MASTER.CST --member 77 --dump
##
## A hard fraction, never "most". A script that fails to parse is a handler the
## game will not run, and the ones that matter here are not evenly distributed:
## MASTER.CST holds the globals and the inventory HUD, so 40 scripts failing
## there is worse than 40 failing across forty rooms.
##
## Parsing is the expensive half of compiling, and per-movie compile time is what
## decides whether ASTs can be built on a room change or have to be cached, so
## the timing is reported alongside rather than as an afterthought.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		quit(1)
		return

	var wanted := Args.text(args, "file", paths.boot_movie)
	var path: String = paths.resolve(wanted)
	if path == "":
		print("no such container under %s: %s" % [paths.root, wanted])
		quit(1)
		return

	var f := ContainerFile.new()
	if not f.open(path):
		print("%s: %s" % [path, f.error])
		quit(1)
		return
	var cast := Cast.new()
	if not cast.open(f):
		print("%s: %s" % [path, cast.error])
		quit(1)
		return

	var only := Args.number(args, "member", 0)
	var dump := Args.flag(args, "dump")
	var compiler := Compiler.new()
	var scripts := 0
	var compiled := 0
	var handlers := 0
	var characters := 0
	var failures: Array[String] = []
	var started := Time.get_ticks_usec()

	h.begin("every script in the container compiles")
	for number in cast.member_numbers():
		if only > 0 and number != only:
			continue
		var m: Dictionary = cast.member(number)
		var source := str(m.get("source", ""))
		if source.strip_edges() == "":
			continue
		scripts += 1
		characters += source.length()
		var key := Compiler.script_key(m, number)
		var ast := compiler.compile_source(source, key)
		if ast.is_empty():
			failures.append("%s: line %d: %s" % [key, compiler.error_line, compiler.error])
			continue
		compiled += 1
		handlers += (ast.get("handlers", []) as Array).size()
		if dump:
			print("")
			print("--- %s" % key)
			print(JSON.stringify(ast, "  ", false))
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0

	h.check("%d of %d script(s) compiled" % [compiled, scripts], failures.is_empty(),
		"" if failures.is_empty() else "%d failed" % failures.size())
	for line in failures.slice(0, 15):
		print("     %s" % line)
	if failures.size() > 15:
		print("     ... and %d more" % (failures.size() - 15))
	h.check("the container carries Lingo at all", scripts > 0, "%d script(s)" % scripts)
	h.complete("every script in the container compiles")

	print("")
	print("%s" % path)
	print("scripts    : %d" % scripts)
	print("handlers   : %d" % handlers)
	print("source     : %d characters" % characters)
	print("elapsed    : %.1f ms  (%.2f ms/script)" % [elapsed, elapsed / maxi(scripts, 1)])
	f.close()
	quit(h.finish("the compiler reads this game's own Lingo"))
