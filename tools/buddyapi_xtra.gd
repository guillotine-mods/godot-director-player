extends SceneTree
## The BuddyAPI Xtra, driven from Lingo through the real player (§7.3, §19).
##
##   godot --headless --path . --script tools/buddyapi_xtra.gd
##   godot --headless --path . --script tools/buddyapi_xtra.gd -- --allow-writes
##
## **What goes red if the binding is reverted**, case by case, because a harness
## whose failure mode is "some number moved" is one nobody can act on:
##
##   the shape        `baReadIni` unbound answers the *integer* 0
##                    (`lingo_interpreter.gd:_call`), and that is `bugs.md` 78
##                    exactly: `itamar-magichat`'s `if tmp = EMPTY` is then false,
##                    its own `"intro"` fallback is skipped, `#startFrame` becomes
##                    0 and the playhead never leaves frame 0. The first block
##                    below asserts the *type* through `ilk()` and the `= EMPTY`
##                    test through Lingo, so an integer answer fails on the thing
##                    the movie actually does with it rather than on a value.
##   the reads        the fixture is written by this harness with `FileAccess` and
##                    read back through **Lingo**. Case, quoting, comments,
##                    section scoping and the missing-key default are each a
##                    separate check against known text, so a parser that
##                    returned the whole line, or the right line from the wrong
##                    section, is caught rather than averaged out.
##   `baFlushIni`     is the one call here whose effect is invisible from a single
##                    read. The file is changed on disk *behind* the cache and
##                    the same read is made again: it must still answer the old
##                    value, and must answer the new one after the flush. A
##                    `baFlushIni` bound to `return 1` fails that pair, which is
##                    the point -- it is the name most likely to be quietly
##                    turned into a no-op.
##   the write guard  a headless run must not be able to write into a corpus that
##                    is six git submodules. Both halves are asserted -- the
##                    refusal *and* that no file appeared -- and the out-of-root
##                    refusal is asserted whatever the run allows, because that
##                    guard is about the path rather than about the process.
##   `baOpenURL`      must answer 0 **and** leave a report. A player that opens a
##                    browser because a movie read a URL out of a configuration
##                    file is the failure this check exists to prevent, and a
##                    silent decline is the one that stops being noticed.
##
## Given `--allow-writes` the write half runs for real, in the game root, and
## puts everything back -- the same bargain `tools/save_movie.gd` makes and for
## the same reason: the only place this player is allowed to write is the place a
## harness least wants to leave litter, so the harness deletes what it made and
## asserts that the deletion worked.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const BuddyAPI := preload("res://lingo/lingo_buddyapi.gd")
const FileIO := preload("res://lingo/lingo_fileio.gd")
const LingoXtra := preload("res://lingo/lingo_xtra.gd")
const MovieSave := preload("res://scenes/preview/movie_save.gd")

## Under `user://`, so the read half needs no title and writes nothing into a
## game root. Reads are not guarded; writes are, which is why the write half
## needs a different location and its own opt-in.
const FIXTURE := "user://buddyapi_fixture.ini"
const FIXTURE_TEXT := """; a comment line, which the reader must skip
[globals]
language = hebrew
StartFrame=mainmenu
quoted = "with spaces"

[PATH]
language = not this one
[END]
"""
## The same file after something else has changed it. Only `flushed` moves, so a
## read that answers `after` proves the cache was dropped and nothing else.
const FIXTURE_REWRITTEN := """[globals]
language = hebrew
StartFrame=after
quoted = "with spaces"
"""

## What a write test makes and unmakes. Named so that a run that dies half way
## leaves something obviously not part of the game.
const PROBE_INI := "buddyapi_probe_delete_me.ini"
const PROBE_COPY := "buddyapi_probe_copy_delete_me.ini"
const PROBE_DIR := "buddyapi_probe_folder_delete_me"

## The driver. Flat calls with no instance in front of them, because that is
## BuddyAPI's whole calling convention (`lingo/lingo_buddyapi.gd`) and the one
## all 46 sites in `itamar-magichat` use.
const SOURCE := """
on readIni section, key, dflt, file
  return baReadIni(section, key, dflt, file)
end

on readIniKind section, key, dflt, file
  return ilk(baReadIni(section, key, dflt, file))
end

on readsAsEmpty section, key, file
  tmp = baReadIni(section, key, EMPTY, file)
  if tmp = EMPTY then
    return 1
  end if
  return 0
end

on startFrameLikeMagichat file
  -- MovieScript 1 - start movie, verbatim in shape
  tmp = baReadIni("globals", "startframe", EMPTY, file)
  if tmp = EMPTY then
    tmp = "intro"
  end if
  return tmp
end

on writeIni section, key, value, file
  return baWriteIni(section, key, value, file)
end

on flushIni file
  return baFlushIni(file)
end

on fileThere name
  return baFileExists(name)
end

on sizeOf name
  return baFileSize(name)
end

on folderThere name
  return baFolderExists(name)
end

on filesIn folder, pattern
  return baFileList(folder, pattern)
end

on foldersIn folder
  return baFolderList(folder)
end

on makeFolder name
  return baCreateFolder(name)
end

on dropFolder name
  return baDeleteFolder(name)
end

on copyOne src, dest, mode
  return baCopyFile(src, dest, mode)
end

on dropFile name
  return baDeleteFile(name)
end

on renameOne src, dest
  return baRenameFile(src, dest)
end

on openTheURL url
  return baOpenURL(url, "maximised")
end

on theXtra name
  return xtra(name)
end

on newXtra name
  return new(xtra(name))
end
"""


func _init() -> void:
	var _args := Args.parse()
	var h := Harness.new()

	_seed(FIXTURE_TEXT)

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var lingo_host = preview.get("_host")
	var interp = preview.get("_interpreter")

	var compiler := Compiler.new()
	var driver: Dictionary = compiler.compile_source(SOURCE, "buddyapi")

	h.begin("the fixture is in place and the player booted")
	h.check("the driver Lingo compiles", not driver.is_empty(),
		"" if not driver.is_empty() else "line %d: %s" % [compiler.error_line, compiler.error])
	h.check("the fixture was written", FileAccess.file_exists(FIXTURE))
	h.check("the player has an interpreter and a host",
		interp != null and lingo_host != null)
	h.complete("the fixture is in place and the player booted")
	if driver.is_empty() or interp == null or lingo_host == null:
		preview.queue_free()
		quit(h.finish("the BuddyAPI Xtra"))
		return

	# ------------------------------------------------------------- the registry
	var title := "BudAPI is in the registry `the xtras` reads"
	h.begin(title)
	var listed: Variant = lingo_host.get_system_prop("xtras")
	var names: Array = []
	for entry in lingo_host.xtras_loaded:
		names.append(str((entry as Dictionary)["name"]))
	h.check("`the xtras` and the registry are one list, and BudAPI is in it",
		typeof(listed) == TYPE_ARRAY
			and (listed as Array).size() == lingo_host.xtras_loaded.size()
			and names.has(BuddyAPI.XTRA_NAME),
		JSON.stringify(names))
	var by_name: Variant = interp.call_handler("theXtra", ["BudAPI"], driver)
	var by_path: Variant = interp.call_handler(
		"theXtra", ["Macintosh HD:Xtras:BudAPI.x32"], driver)
	h.check("a name and a decorated name answer the same Xtra",
		by_name != null and by_name == by_path,
		"%s / %s" % [str(by_name), str(by_path)])
	var instance: Variant = interp.call_handler("newXtra", ["budapi"], driver)
	h.check("`new(xtra(\"budapi\"))` answers an instance that is not the Xtra",
		LingoXtra.is_native(instance) and instance != by_name, str(instance))
	# The instance surface is `name` and nothing else, deliberately: every `ba*`
	# name is a global builtin, and an instance that claimed them through
	# `respondsTo` would be describing an Xtra that does not exist.
	h.check("the instance answers `name` and does not claim the ba* names",
		instance != null
			and bool((instance as Object).call("lingo_responds_to", "name"))
			and not bool((instance as Object).call("lingo_responds_to", "baReadIni")),
		"BuddyAPI's surface is global; see budapi.cpp's xlibMethods")
	h.complete(title)

	# ------------------------------------------------------- bugs.md 78's shape
	title = "`baReadIni` answers a string, and EMPTY when there is no file"
	h.begin(title)
	# The exact call `ReadConfigLine` makes with the ini path the movie never
	# set, which is VOID. Unbound, this answered the integer 0.
	var kind := str(interp.call_handler(
		"readIniKind", ["globals", "startframe", null, null], driver))
	h.check("`ilk(baReadIni(...))` is #string even when nothing was found",
		kind == "string", kind)
	var empty_for_void := int(interp.call_handler(
		"readsAsEmpty", ["globals", "startframe", null], driver))
	h.check("`tmp = EMPTY` is TRUE for a file the movie never named",
		empty_for_void == 1,
		"this is bugs.md 78: an integer 0 here skips the movie's own fallback "
			+ "and #startFrame becomes 0, so the playhead never leaves frame 0")
	var start_frame := str(interp.call_handler(
		"startFrameLikeMagichat", [null], driver))
	h.check("magichat's own startMovie shape reaches its \"intro\" fallback",
		start_frame == "intro", start_frame)
	h.check("and `baReadIni` is not reported as an unbound builtin",
		not (lingo_host.unbound as Dictionary).has("bareadini"),
		JSON.stringify(lingo_host.unbound))
	h.complete(title)

	# ---------------------------------------------------------------- the reads
	title = "reading a real ini file, through Lingo"
	h.begin(title)
	var value := str(interp.call_handler(
		"readIni", ["globals", "startframe", "MISSED", FIXTURE], driver))
	h.check("a key answers its value", value == "mainmenu", value)
	var cased := str(interp.call_handler(
		"readIni", ["GLOBALS", "LANGUAGE", "MISSED", FIXTURE], driver))
	h.check("section and key match case-insensitively, as Windows' own reader does",
		cased == "hebrew", cased)
	var quoted := str(interp.call_handler(
		"readIni", ["globals", "quoted", "MISSED", FIXTURE], driver))
	h.check("one matching pair of quotes is stripped and the spaces inside kept",
		quoted == "with spaces", JSON.stringify(quoted))
	var scoped := str(interp.call_handler(
		"readIni", ["PATH", "language", "MISSED", FIXTURE], driver))
	h.check("the same key in another section is a different value",
		scoped == "not this one", JSON.stringify(scoped))
	var absent_key := str(interp.call_handler(
		"readIni", ["globals", "nosuchkey", "FALLBACK", FIXTURE], driver))
	h.check("a missing key answers the caller's Default", absent_key == "FALLBACK",
		absent_key)
	var absent_section := str(interp.call_handler(
		"readIni", ["nosuchsection", "language", "FALLBACK", FIXTURE], driver))
	h.check("a missing section answers the caller's Default",
		absent_section == "FALLBACK", absent_section)
	var absent_file := str(interp.call_handler(
		"readIni", ["globals", "language", "FALLBACK", "user://no_such.ini"], driver))
	h.check("a missing file answers the caller's Default", absent_file == "FALLBACK",
		absent_file)
	h.complete(title)

	# ---------------------------------------------------- `baFlushIni` is a commit
	title = "`baFlushIni` drops the cached parse, so the next read sees the disk"
	h.begin(title)
	# Written **without** clearing anything, which is the whole point: this is
	# something else changing the file under a running movie.
	_write(FIXTURE, FIXTURE_REWRITTEN)
	var stale := str(interp.call_handler(
		"readIni", ["globals", "startframe", "MISSED", FIXTURE], driver))
	h.check("a file changed behind the cache still reads as it was",
		stale == "mainmenu",
		"if this is \"after\", nothing is cached and the flush below proves nothing")
	var flushed := int(interp.call_handler("flushIni", [FIXTURE], driver))
	var fresh := str(interp.call_handler(
		"readIni", ["globals", "startframe", "MISSED", FIXTURE], driver))
	h.check("and reads the disk again after the flush",
		flushed == 1 and fresh == "after", "%d / %s" % [flushed, fresh])
	var flush_missing := int(interp.call_handler(
		"flushIni", ["user://no_such.ini"], driver))
	h.check("flushing a file that is not there answers 0", flush_missing == 0,
		str(flush_missing))
	h.complete(title)

	# ------------------------------------------------------- the file questions
	title = "the file and folder questions answer about the real game root"
	h.begin(title)
	var root_dir := FileIO.game_root(lingo_host)
	h.check("the harness knows where the game root is", root_dir != "", root_dir)
	h.check("`baFileExists` finds the fixture and not a name beside it",
		int(interp.call_handler("fileThere", [FIXTURE], driver)) == 1
			and int(interp.call_handler("fileThere", ["user://no_such.ini"], driver)) == 0)
	var size := int(interp.call_handler("sizeOf", [FIXTURE], driver))
	h.check("`baFileSize` is the fixture's own length, and -1 for a missing file",
		size == FIXTURE_REWRITTEN.length()
			and int(interp.call_handler("sizeOf", ["user://no_such.ini"], driver)) == -1,
		"%d, wanted %d" % [size, FIXTURE_REWRITTEN.length()])
	h.check("`baFolderExists` finds the game root and not a name beside it",
		int(interp.call_handler("folderThere", [root_dir], driver)) == 1
			and int(interp.call_handler("folderThere", ["no_such_folder_here"], driver)) == 0)
	var files: Variant = interp.call_handler("filesIn", [root_dir, "*"], driver)
	h.check("`baFileList` answers a list of bare names, not paths",
		typeof(files) == TYPE_ARRAY and (files as Array).size() > 0
			and not str((files as Array)[0]).contains("/"),
		JSON.stringify((files as Array).slice(0, 4) if typeof(files) == TYPE_ARRAY else files))
	# The pattern has to *narrow*, or a `repeat with f in baFileList(dir, "*.txt")`
	# loop over every file in the folder looks like a working filter.
	var narrowed: Variant = interp.call_handler(
		"filesIn", [root_dir, "*.no_such_extension"], driver)
	h.check("and the pattern narrows it",
		typeof(narrowed) == TYPE_ARRAY and (narrowed as Array).is_empty(),
		JSON.stringify(narrowed))
	var folders: Variant = interp.call_handler("foldersIn", [root_dir], driver)
	h.check("`baFolderList` answers the sub-folders of a folder that has some",
		typeof(folders) == TYPE_ARRAY and (folders as Array).size() > 0,
		JSON.stringify(folders))
	h.complete(title)

	# --------------------------------------------------------------- `baOpenURL`
	title = "`baOpenURL` declines and says so"
	h.begin(title)
	var before := int(interp.diagnostics.count()) if interp.diagnostics != null else -1
	var opened := int(interp.call_handler(
		"openTheURL", ["http://example.invalid/whatever"], driver))
	var after := int(interp.diagnostics.count()) if interp.diagnostics != null else -1
	h.check("it answers 0 -- BuddyAPI's own \"this did not happen\"", opened == 0,
		str(opened))
	h.check("and the decline reaches the diagnostics rather than nowhere",
		before >= 0 and after > before,
		"a silent decline is the one that stops being noticed; %d -> %d"
			% [before, after])
	h.complete(title)

	# ------------------------------------------------------------ the write guard
	#
	# The out-of-root refusal is asserted whatever the run allows, because that
	# guard is about the *path*. The headless refusal and the real round trip are
	# the two halves of the same question about the *process*, and exactly one of
	# them can be true in any one run.
	title = "writes obey the game root always and the run's own permission"
	h.begin(title)
	var outside := int(interp.call_handler(
		"writeIni", ["globals", "k", "v", "user://buddyapi_escaped.ini"], driver))
	h.check("a target outside the game root is refused, whatever the run allows",
		outside == 0, str(outside))
	h.check("and nothing was written there",
		not FileAccess.file_exists("user://buddyapi_escaped.ini"))

	var probe := "%s/%s" % [root_dir, PROBE_INI]
	if not MovieSave.writes_allowed():
		var refused := int(interp.call_handler(
			"writeIni", ["globals", "startframe", "written", probe], driver))
		h.check("`baWriteIni` into the game root is refused headless", refused == 0,
			str(refused))
		h.check("and no file appeared", not FileAccess.file_exists(probe), probe)
		h.check("skipped: the round trip needs --allow-writes", true,
			"run with --allow-writes to exercise the write half for real")
	else:
		_round_trip(h, interp, driver, root_dir, probe)
	h.complete(title)

	preview.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	quit(h.finish(
		"the BuddyAPI Xtra: the registry, the ini reader, the flush, "
			+ "the file questions, the declined URL and the write guard"))


## The write half, for real, in the game root, put back afterwards.
##
## Every call here is one a movie makes, in the order it makes them, and the
## last two checks are the ones that matter to anybody but this harness: the
## file is gone and the folder is gone.
func _round_trip(h, interp, driver: Dictionary, root_dir: String,
		probe: String) -> void:
	var wrote := int(interp.call_handler(
		"writeIni", ["globals", "startframe", "written", probe], driver))
	var flushed := int(interp.call_handler("flushIni", [probe], driver))
	h.check("`baWriteIni` then `baFlushIni` both report success",
		wrote == 1 and flushed == 1, "%d / %d" % [wrote, flushed])
	var read_back := str(interp.call_handler(
		"readIni", ["globals", "startframe", "MISSED", probe], driver))
	h.check("and the value is on disk and reads back through Lingo",
		read_back == "written" and FileAccess.file_exists(probe),
		JSON.stringify(read_back))
	# A second key in the same section, so the writer's insert path is covered
	# and not only its replace path.
	interp.call_handler("writeIni", ["globals", "second", "two", probe], driver)
	interp.call_handler("flushIni", [probe], driver)
	var both := "%s/%s" % [
		str(interp.call_handler("readIni", ["globals", "startframe", "?", probe], driver)),
		str(interp.call_handler("readIni", ["globals", "second", "?", probe], driver))]
	h.check("a second key joins the first rather than replacing it",
		both == "written/two", both)

	var copy_target := "%s/%s" % [root_dir, PROBE_COPY]
	h.check("`baCopyFile` copies, and the copy is found by `baFileExists`",
		int(interp.call_handler("copyOne", [probe, copy_target, "Always"], driver)) == 1
			and int(interp.call_handler("fileThere", [PROBE_COPY], driver)) == 1)
	h.check("`baCopyFile` with \"Never\" refuses to overwrite what is there",
		int(interp.call_handler("copyOne", [probe, copy_target, "Never"], driver)) == 0)

	var made := int(interp.call_handler("makeFolder", [PROBE_DIR], driver))
	h.check("`baCreateFolder` creates it, and `baFolderExists` then finds it",
		made == 1 and int(interp.call_handler("folderThere", [PROBE_DIR], driver)) == 1,
		str(made))
	h.check("and creating it a second time reports the failure rather than success",
		int(interp.call_handler("makeFolder", [PROBE_DIR], driver)) == 0)
	h.check("`baDeleteFolder` removes an empty one",
		int(interp.call_handler("dropFolder", [PROBE_DIR], driver)) == 1
			and int(interp.call_handler("folderThere", [PROBE_DIR], driver)) == 0)

	h.check("`baDeleteFile` removes both probes and nothing is left behind",
		int(interp.call_handler("dropFile", [probe], driver)) == 1
			and int(interp.call_handler("dropFile", [copy_target], driver)) == 1
			and not FileAccess.file_exists(probe)
			and not FileAccess.file_exists(copy_target),
		"%s / %s" % [probe, copy_target])


## Put the fixture on disk and forget everything cached about it, so a read
## after this comes from the bytes just written.
func _seed(text: String) -> void:
	_write(FIXTURE, text)
	FileIO.forget_index()
	BuddyAPI.forget_documents()


## The bytes and nothing else. Used on its own where the subject *is* what the
## player does with a file that changed behind it.
func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
