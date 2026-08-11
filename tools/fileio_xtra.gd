extends SceneTree
## The FileIO Xtra, driven from Lingo through the real player (§7.3).
##
##   godot --headless --path . --script tools/fileio_xtra.gd
##   godot --headless --path . --script tools/fileio_xtra.gd -- --root res://test-games/itamar-park
##
## **Why this is worth more than a dozen names.** Two unfamiliar Director titles
## pointed at this engine stop at startup without FileIO, both while reading a
## configuration file, and neither has a Lingo problem: they decompile, parse,
## compile and load. `itamar-park` reads `safari.ini` into a field and parses
## `[PATH]` … `[ENDINI]` out of it to fill `the searchPaths`; with an empty field
## it alerts and stops before its first room.
##
## **What goes red if the binding is reverted**, case by case:
##
##   the registry   `xtra("FileIO")` answers VOID, so `new` has nothing to make
##                  and every later case fails on the object rather than on the
##                  file.
##   the reads      the fixture is written by this harness with `FileAccess` and
##                  read back through **Lingo**, so a broken read answers "" and
##                  every content check fails on a string it can print. The
##                  fixture holds three lines of known text and a known length,
##                  so a partial read is caught as well as a missing one.
##   `status`       every failure case asserts the **code**, not merely that
##                  something went wrong. Director's contract is that scripts
##                  branch on `status(obj) = 0`, so a plausible-looking wrong
##                  code is worse than no binding, and a harness that only
##                  checked "not 0" would not see one.
##   the write guard a headless run must not be able to create or truncate a file
##                  in a corpus that is six git submodules. Both halves are
##                  asserted: the refusal *and* that no file appeared.
##
## The fixture lives under `user://` so the harness needs no title and writes
## nothing into `games/`. The last case is the only one that needs a real movie,
## and it is skipped with a named reason when `test-games/` is not checked out --
## that tree is untracked, so a gate entry may not depend on it.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const FileIO := preload("res://lingo/lingo_fileio.gd")
const LingoXtra := preload("res://lingo/lingo_xtra.gd")
const MovieSave := preload("res://scenes/preview/movie_save.gd")

## Where the fixture goes. Under `user://` because the harness must not write
## into a game root, which is the very thing the write guard protects.
const FIXTURE := "user://fileio_fixture.ini"
const FIXTURE_TEXT := "[globals]\nlanguage = hebrew\n[ENDINI]\n"

## The Lingo that drives it. Written in the flat D3 spelling -- `openFile(f, p,
## 1)` -- because that is the spelling both blocked titles use and the one that
## needs the interpreter's native-object dispatch; one case below uses the dot
## spelling to prove the two reach the same place.
const SOURCE := """
on makeIO
  return new(xtra("FileIO"))
end

on openIt f, path
  openFile(f, path, 1)
  return status(f)
end

on wholeFile f
  return readFile(f)
end

on firstLine f
  return readLine(f)
end

on oneWord f
  return readWord(f)
end

on oneChar f
  return readChar(f)
end

on lengthOf f
  return getLength(f)
end

on whereAmI f
  return getPosition(f)
end

on seekTo f, at
  setPosition(f, at)
  return status(f)
end

on nameOf f
  return fileName(f)
end

on shut f
  closeFile(f)
  return status(f)
end

on makeFile f, path
  createFile(f, path)
  return status(f)
end

on dotOpen f, path
  f.openFile(path, 1)
  return f.status()
end

on messageFor f, code
  return error(f, code)
end

on typeOf f
  return ilk(f)
end

on isObject f
  return objectP(f)
end

on isVoid f
  return voidP(f)
end
"""


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	# The fixture, written with `FileAccess` rather than through the Xtra: the
	# reads are what is under test, and a fixture written by the thing being
	# tested would pass on a FileIO that could neither read nor write.
	var seed := FileAccess.open(FIXTURE, FileAccess.WRITE)
	if seed != null:
		seed.store_string(FIXTURE_TEXT)
		seed.close()
	FileIO.forget_index()

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var lingo_host = preview.get("_host")
	var interp = preview.get("_interpreter")

	var compiler := Compiler.new()
	var driver: Dictionary = compiler.compile_source(SOURCE, "fileio")

	h.begin("the fixture is in place and the player booted")
	h.check("the driver Lingo compiles", not driver.is_empty(),
		"" if not driver.is_empty() else "line %d: %s" % [compiler.error_line, compiler.error])
	h.check("the fixture was written", FileAccess.file_exists(FIXTURE))
	h.check("the player has an interpreter and a host",
		interp != null and lingo_host != null)
	h.complete("the fixture is in place and the player booted")
	if driver.is_empty() or interp == null or lingo_host == null:
		preview.queue_free()
		quit(h.finish("the FileIO Xtra"))
		return

	# ------------------------------------------------------------- the registry
	var title := "the Xtra is registered and `xtra(...)` finds it"
	h.begin(title)
	var listed: Variant = lingo_host.get_system_prop("xtras")
	# The registry, whole. Asserted against the host's own list rather than
	# against a number written here: this said "exactly one Xtra" until BudAPI
	# joined FileIO in it, and a count in a harness is a second copy of a fact
	# that lives in `xtras_loaded`. What matters to *this* file is that FileIO is
	# still the entry `xtra(1)` answers, because the index lookup below is
	# checked against it.
	h.check("`the xtras` is the host's registry, and FileIO is the first entry",
		typeof(listed) == TYPE_ARRAY
			and (listed as Array).size() == lingo_host.xtras_loaded.size()
			and (listed as Array).size() >= 1
			and str((lingo_host.xtras_loaded[0] as Dictionary)["name"]) == "FileIO",
		JSON.stringify(listed))
	# §7.3's normalisation on both sides: the same library named three ways is
	# one Xtra, and this is the lookup rather than the key function.
	var by_name: Variant = lingo_host.call_builtin("xtra", ["FileIO"])
	var by_path: Variant = lingo_host.call_builtin("xtra", ["Macintosh HD:Xtras:FileIO.x32"])
	var by_index: Variant = lingo_host.call_builtin("xtra", [1])
	h.check("a name, a decorated name and the index all answer the same Xtra",
		by_name != null and by_name == by_path and by_name == by_index,
		"%s / %s / %s" % [str(by_name), str(by_path), str(by_index)])
	h.check("an Xtra this player does not have still answers VOID",
		lingo_host.call_builtin("xtra", ["QuickDraw3D"]) == null)
	h.complete(title)

	title = "`new(xtra(\"FileIO\"))` makes an instance, and it is not the Xtra"
	h.begin(title)
	var f: Variant = interp.call_handler("makeIO", [], driver)
	h.check("an instance came back", LingoXtra.is_native(f), str(f))
	h.check("and it is a different object from the Xtra itself", f != by_name)
	h.check("a second instance is a third object",
		interp.call_handler("makeIO", [], driver) != f,
		"one shared handle would give every movie one file")
	h.check("it answers `respondsTo`'s question for a method it has and one it does not",
		f != null and bool((f as Object).call("lingo_responds_to", "openFile"))
			and not bool((f as Object).call("lingo_responds_to", "displaySave")))
	# **The instance in front of a call must not swallow the call.** `objectP(f)`,
	# `ilk(f)` and `voidP(f)` take an object as their first argument and are none
	# of the object's business; a dispatcher that claimed every such call because
	# the first argument was native answered VOID for all three, which is the
	# "bound and does nothing" shape §19 exists to catch. The object gets first
	# refusal and the ordinary dispatch continues behind it.
	var kind := str(interp.call_handler("typeOf", [f], driver))
	var is_obj := int(interp.call_handler("isObject", [f], driver))
	var is_void := int(interp.call_handler("isVoid", [f], driver))
	h.check("a builtin that takes an object as its first argument still reaches it",
		is_obj == 1 and kind == "object" and is_void == 0,
		"objectP %d / ilk %s / voidP %d" % [is_obj, kind, is_void])
	h.complete(title)
	if not LingoXtra.is_native(f):
		preview.queue_free()
		quit(h.finish("the FileIO Xtra"))
		return

	# ---------------------------------------------------------------- the reads
	title = "opening and reading a real file, through Lingo"
	h.begin(title)
	# **Each call is made once and stored.** Every read moves the shared cursor,
	# so a check that calls the handler for its condition and again for its detail
	# reads twice and reports the second answer against the first verdict -- which
	# is how the first version of this file passed `readLine` while leaving the
	# file positioned two lines on and failing everything after it.
	var opened := int(interp.call_handler("openIt", [f, FIXTURE], driver))
	h.check("`openFile(f, path, 1)` reports status 0", opened == FileIO.OK, str(opened))
	var length := int(interp.call_handler("lengthOf", [f], driver))
	h.check("`getLength` is the fixture's own length", length == FIXTURE_TEXT.length(),
		"%d, wanted %d" % [length, FIXTURE_TEXT.length()])
	var named := str(interp.call_handler("nameOf", [f], driver))
	h.check("`fileName` answers the path it opened", named == FIXTURE, named)
	# The cursor is shared by every read, which is the whole of FileIO's model, so
	# these four run in order and each depends on where the last one left it.
	var line1 := str(interp.call_handler("firstLine", [f], driver))
	h.check("`readLine` answers the first line *with* its return",
		line1 == "[globals]\n", JSON.stringify(line1))
	var word := str(interp.call_handler("oneWord", [f], driver))
	h.check("`readWord` takes the next word and leaves the cursor after it",
		word == "language", JSON.stringify(word))
	var ch := str(interp.call_handler("oneChar", [f], driver))
	h.check("`readChar` takes one character", ch == " ", JSON.stringify(ch))
	var rest := str(interp.call_handler("wholeFile", [f], driver))
	h.check("`readFile` answers the *rest*, not the whole file",
		rest == "= hebrew\n[ENDINI]\n", JSON.stringify(rest))
	var at := int(interp.call_handler("whereAmI", [f], driver))
	h.check("and the cursor is now at the end", at == FIXTURE_TEXT.length(),
		"%d of %d" % [at, FIXTURE_TEXT.length()])
	var sought := int(interp.call_handler("seekTo", [f, 0], driver))
	var whole := str(interp.call_handler("wholeFile", [f], driver))
	h.check("`setPosition` rewinds it, and a read starts there again",
		sought == FileIO.OK and whole == FIXTURE_TEXT,
		"a seek and a read in different units is the divergence a script cannot see")
	var closed := int(interp.call_handler("shut", [f], driver))
	var after_close := str(interp.call_handler("nameOf", [f], driver))
	h.check("`closeFile` reports 0 and clears the name",
		closed == FileIO.OK and after_close == "",
		"%d / %s" % [closed, JSON.stringify(after_close)])
	h.complete(title)

	title = "the dot spelling and the flat spelling are one statement"
	h.begin(title)
	var g: Variant = interp.call_handler("makeIO", [], driver)
	var dotted := int(interp.call_handler("dotOpen", [g, FIXTURE], driver))
	h.check("`f.openFile(path, 1)` reports the same status",
		dotted == FileIO.OK, str(dotted))
	interp.call_handler("shut", [g], driver)
	h.complete(title)

	# -------------------------------------------------------------- the failures
	#
	# The codes, not "something went wrong": a script branches on the number.
	title = "every failure sets the code Director sets"
	h.begin(title)
	var missing: Variant = interp.call_handler("makeIO", [], driver)
	var gone := int(interp.call_handler("openIt", [missing, "user://no_such_file.zzz"], driver))
	h.check("a file that is not there is -43, file not found",
		gone == FileIO.NOT_FOUND, str(gone))
	var read_shut := str(interp.call_handler("wholeFile", [missing], driver))
	var shut_code := _status(interp, driver, missing)
	h.check("a read on a handle that was never opened is -38, file not open",
		read_shut == "" and shut_code == FileIO.NOT_OPEN,
		"%s / %d" % [JSON.stringify(read_shut), shut_code])
	var twice: Variant = interp.call_handler("makeIO", [], driver)
	interp.call_handler("openIt", [twice, FIXTURE], driver)
	var again := int(interp.call_handler("openIt", [twice, FIXTURE], driver))
	h.check("opening a second file on an open handle is -49, already open",
		again == FileIO.ALREADY_OPEN, str(again))
	interp.call_handler("shut", [twice], driver)
	var blank := int(interp.call_handler("openIt", [missing, ""], driver))
	h.check("an empty name is -37, bad file name", blank == FileIO.BAD_NAME, str(blank))
	var text := str(interp.call_handler("messageFor", [missing, FileIO.NOT_FOUND], driver))
	h.check("`error(f, code)` names the code rather than answering a number",
		text == "File not found", text)
	h.complete(title)

	# ------------------------------------------------------------ the write guard
	title = "a headless run cannot create a file in the game root"
	h.begin(title)
	var root_dir := FileIO.game_root(lingo_host)
	h.check("the harness knows where the game root is", root_dir != "", root_dir)
	var victim := "%s/fileio_should_not_exist.txt" % root_dir
	var writer: Variant = interp.call_handler("makeIO", [], driver)
	var code := int(interp.call_handler("makeFile", [writer, victim], driver))
	if MovieSave.writes_allowed():
		# `--allow-writes`, or a run with a display. The guard is not the subject
		# then, and saying so is better than asserting the opposite of the rule.
		h.check("writes are allowed in this run, so the refusal is not asserted",
			true, "run headless without --allow-writes to exercise the guard")
		if code == FileIO.OK:
			interp.call_handler("shut", [writer], driver)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(victim))
	else:
		h.check("`createFile` is refused with -45, locked", code == FileIO.LOCKED,
			"got %d (%s)" % [code, FileIO.message_for(code)])
	h.check("and no file appeared either way", not FileAccess.file_exists(victim),
		victim)
	# The other guard, and it is a different question: a path that resolves
	# outside the game root is refused whatever the run allows.
	var outside: Variant = interp.call_handler("makeIO", [], driver)
	var escape := int(interp.call_handler("makeFile", [outside, "user://escaped.txt"], driver))
	h.check("a target outside the game root is -37, bad file name",
		escape == FileIO.BAD_NAME, "%d (%s)" % [escape, FileIO.message_for(escape)])
	h.check("and nothing was written there", not FileAccess.file_exists("user://escaped.txt"))
	h.complete(title)

	# ------------------------------------------------- a 1997 path, if there is one
	title = "a path a 1997 movie would build resolves against the game root"
	h.begin(title)
	# Only when the *booted root* is that title: `resolve` matches against the
	# index of the running game, so asking it about another title's file from a
	# `piposh2` run is a question with no right answer.
	var ini := "res://test-games/itamar-park/safari.ini"
	if not FileAccess.file_exists(ini) or not root_dir.ends_with("itamar-park"):
		h.check("skipped: not booted against test-games/itamar-park", true,
			"that tree is untracked, so this case cannot be a gate dependency; "
			+ "run with --root res://test-games/itamar-park to exercise it")
	else:
		# The movie builds `the pathName & "safari.ini"` and rewrites `\` to the
		# platform separator; the directory it names has not existed since 1997.
		# What has to work is the *tail* match, case-insensitively.
		var found := FileIO.resolve(lingo_host, "C:\\COMPEDIA\\PARK\\SAFARI.INI")
		h.check("a Windows path with the wrong case and a dead directory resolves",
			found.to_lower().ends_with("safari.ini"), found)
	h.complete(title)

	preview.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	quit(h.finish("the FileIO Xtra: registry, reads, status codes and the write guard"))


## `status(f)` without going through a handler that also does something, so a
## failure's code can be read straight after the call that caused it.
func _status(interp, driver: Dictionary, f: Variant) -> int:
	var probe := Compiler.new().compile_source(
		"on justStatus f\n  return status(f)\nend\n", "status")
	return int(interp.call_handler("justStatus", [f], probe))
