extends SceneTree
## Which argument of `go` is the movie, and does the name have to be spelled out?
##
##   godot --headless --audio-driver Dummy --path . --script tools/go_movie_arg.gd
##   godot --headless --audio-driver Dummy --path . --script tools/go_movie_arg.gd -- \
##       --root res://test-games/itamar-magichat --boot magichat.dir
##
## **Director decides by position and type, not by spelling.**
## `reference/scummvm/lingo-builtins.cpp:b_go` pops the last argument first and
## branches on its type: a STRING there is the movie and what is left is the
## frame; an INT there means the first argument is the frame and the rest is
## discarded. The name is handed to `Window::setNextMovie` raw, and
## `util.cpp:findMoviePath` supplies the extensions itself -- so **a movie name
## with no extension at all is an ordinary, resolvable `go` argument.**
##
## The port used to recognise the movie only by its extension or by the literal
## word `movie`, and that is a strictly narrower rule that the corpus reaches
## past. Magic Hat's `logo/logo.dir` frame 6 is
##
##     go(1, GetMoviePath(CDpath() & DirChar() & "magichat"))
##
## and `GetMoviePath` (the movie's own handler, `utils.cst`) returns its argument
## unchanged when the ini names no `[MOVIE]` section, so the second argument is a
## bare path. Nothing looked like a container, so it was dropped and the statement
## degraded to `go(1)`: the playhead ran to frame 6 and then back to frame 1 of
## the logo, replaying the ten-second logo for ever (`bugs.md` 95). The fault was
## never in path resolution -- `resolve` was never reached with the name.
##
## Title-agnostic. Nothing here names a movie: the destination is taken from the
## container index, and a corpus with fewer than two movies says so and asserts
## nothing rather than passing over nothing.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Score steps to let the arriving movie settle before the name is read back.
## One is enough -- `lingo_go_movie` swaps the container synchronously -- but the
## movie is stepped so the arrival is the one the player would see.
const SETTLE := 2


func _run_lingo(preview: Node, source: String) -> String:
	var interp = preview.get("_interpreter")
	var errors: Array = []
	var compiled = interp.compile_statements(source, "go_movie_arg", errors)
	if not errors.is_empty():
		return "compile: %s" % str(errors)
	interp.errors.clear()
	interp.run_compiled(compiled)
	for i in SETTLE:
		preview.call("_advance")
	return ""


func _playing(preview: Node) -> String:
	return str(preview.call("movie_name")).to_lower()


## A movie under the root that is not the one playing, preferring one in another
## directory so that the "beside the movie that named it" branch of `resolve` is
## not what makes the jump work.
func _elsewhere(preview: Node) -> String:
	var paths = preview.get("_paths")
	var here := str(preview.get("_movie").path).get_file().to_lower()
	var fallback := ""
	for relative in paths.containers():
		var name := str(relative)
		if not ["dir", "dxr", "dcr"].has(name.get_extension().to_lower()):
			continue
		if name.get_file() == here:
			continue
		if name.get_base_dir() == "":
			return name
		if fallback == "":
			fallback = name
	return fallback


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	var case := "`go` finds the movie by position, whatever the name is spelled like"
	h.begin(case)
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var loaded: bool = preview.get("_score") != null and preview.get("_movie") != null
	if not h.check("a movie is playing to jump from", loaded,
			"" if loaded else "the preview did not reach a movie"):
		h.complete(case)
		quit(h.finish("the movie argument of `go`"))
		return

	var target := _elsewhere(preview)
	if target == "":
		# Not a pass and not a failure: a corpus with one movie cannot express the
		# question. Said out loud, because a harness that quietly asserts nothing
		# is the one that reports green for years (`bugs.md` 33).
		print("   only one movie under %s: nothing to jump to" % str(preview.get("_paths").root))
		h.check("the corpus holds a second movie to jump to", false,
			"one movie under the root")
		h.complete(case)
		quit(h.finish("the movie argument of `go`"))
		return

	var home := _playing(preview)
	var wanted := target.get_file().to_lower()
	var bare := target.get_basename()
	print("   from %s, jumping to %s" % [home, target])

	# The control: the spelling that already worked, so a failure below is about
	# the extension and not about the jump.
	var err := _run_lingo(preview, 'go(1, "%s")' % target)
	h.check("`go(1, \"<name>.dir\")` reaches the movie", err == "" and _playing(preview) == wanted,
		err if err != "" else "playing %s" % _playing(preview))

	# The case `bugs.md` 95 is: the second argument is a String, so it is the
	# movie, even though nothing about it looks like a container.
	preview.call("lingo_go_movie", home, null)
	await process_frame
	err = _run_lingo(preview, 'go(1, "%s")' % bare)
	h.check("`go(1, \"<name>\")` with no extension reaches the same movie",
		err == "" and _playing(preview) == wanted,
		err if err != "" else "playing %s" % _playing(preview))

	# The same argument built the way the corpus builds it -- out of a path the
	# *engine* handed the movie. `the moviePath` answers a `res://` path here, and
	# `utils.cst` stores exactly that in `gCDpath` when the ini blanks `CDPATH=`,
	# so this is the shape Magic Hat's `CDpath() & DirChar() & "magichat"` takes.
	preview.call("lingo_go_movie", home, null)
	await process_frame
	err = _run_lingo(preview, 'go(1, the moviePath & "%s")' % bare.get_file())
	h.check("`go(1, the moviePath & \"<name>\")` reaches it too",
		err == "" and _playing(preview) == wanted,
		err if err != "" else "playing %s" % _playing(preview))

	# And the refusal. `func_goto` returns the moment `setNextMovie` fails, before
	# it touches the playhead, so a `go` naming a movie that is not there is not a
	# jump to the frame either -- it is a statement that does not happen.
	preview.call("lingo_go_movie", target, null)
	await process_frame
	for i in 4:
		preview.call("_advance")
	var before := int(preview.get("_index"))
	err = _run_lingo(preview, 'go(1, "no such movie as this one")')
	h.check("a `go` naming a movie that is not there moves nothing",
		err == "" and _playing(preview) == wanted and int(preview.get("_index")) >= before,
		err if err != "" else "playing %s f%d, was f%d" % [
			_playing(preview), int(preview.get("_index")), before])

	h.complete(case)
	quit(h.finish("the movie argument of `go`"))
