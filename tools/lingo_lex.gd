extends SceneTree
## Lex the Lingo inside a container and report what came out.
##
##   godot --headless --script tools/lingo_lex.gd -- --file PIP2DATA/DAY1.DIR
##   godot --headless --script tools/lingo_lex.gd -- --file MASTER.CST --member 77 --dump
##
## The lexer is the one layer whose failures are quiet: a bad token stream still
## parses into *something*, so this asserts the fraction of scripts that lex
## cleanly rather than reporting that it ran. The number to watch is scripts, not
## tokens — one script failing to lex is one handler the game will not run.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")
const Lexer := preload("res://lingo/compile/lingo_lexer.gd")


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
	var scripts := 0
	var lexed := 0
	var tokens := 0
	var characters := 0
	var failures: Array[String] = []
	var started := Time.get_ticks_usec()

	h.begin("every script in the container lexes")
	for number in cast.member_numbers():
		if only > 0 and number != only:
			continue
		var m: Dictionary = cast.member(number)
		var source := str(m.get("source", ""))
		if source.strip_edges() == "":
			continue
		scripts += 1
		characters += source.length()
		var lexer := Lexer.new()
		if not lexer.tokenize(source):
			failures.append("member %d (%s) line %d: %s" % [
				number, m.get("name", ""), lexer.error_line, lexer.error,
			])
			continue
		lexed += 1
		tokens += lexer.size()
		if dump:
			print("")
			print("--- member %d  %s  (%d tokens)" % [number, m.get("name", ""), lexer.size()])
			print(lexer.describe(60))
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0

	h.check("%d of %d script(s) lexed" % [lexed, scripts], failures.is_empty(),
		"" if failures.is_empty() else "%d failed" % failures.size())
	for line in failures.slice(0, 12):
		print("     %s" % line)
	h.check("the container carries Lingo at all", scripts > 0, "%d script(s)" % scripts)
	h.complete("every script in the container lexes")

	print("")
	print("%s" % path)
	print("scripts    : %d" % scripts)
	print("source     : %d characters" % characters)
	print("tokens     : %d" % tokens)
	print("elapsed    : %.1f ms  (%.2f ms/script)" % [elapsed, elapsed / max(scripts, 1)])
	f.close()
	quit(h.finish("the lexer reads this game's own Lingo"))
