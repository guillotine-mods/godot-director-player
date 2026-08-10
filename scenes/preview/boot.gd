extends RefCounted
## Standing a movie up: the stage from the command line, a window from the movie
## that asked for it, and the Lingo behind either.
##
## Both paths converge on the same state -- a loaded container with a score, a
## cast table and an interpreter -- and everything else in the preview assumes
## it. Splitting them here rather than branching inside one long `_ready` is what
## keeps that assumption true for both.
##
## The one thing worth reading twice is `start_lingo`'s handling of globals.
## **They are carried across a movie change and shared between the stage and its
## windows**, because they are session state rather than movie state. Director
## clears them on `clearGlobals` and on quitting, never on opening a window or
## changing movie, and this corpus is built on exactly that: `SAVELOAD` sets
## `nof`, `newsyz`, `egozh` and `nextroomdata` in its own handlers and then says
## `tell the stage / go(nof, "day1.dxr")`, and the room that arrives reads those
## globals to place the player. Rebuilding them per movie loses the save; the
## symptom is a room drawn from accumulated state showing the wrong thing, which
## looks like a rendering fault rather than a lost variable.

const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
const PreviewHost := preload("res://scenes/preview_lingo_host.gd")
const SaveState := preload("res://scenes/preview/save_state.gd")
const SaveFiles := preload("res://scenes/preview/save_files.gd")
const GameConfig := preload("res://director/game_config.gd")


## The stage: resolve the boot movie from the config and the command line, load
## it, and enter its first frame the way any other frame is entered.
##
## **`--save` replaces `--file`**, and mostly replaces the rest of the line too:
## a save carries the game it was taken in, the container that was playing and
## the frame it was on, so
##
##     godot --path . -- --save saves/piposh2/beach_bug.json
##
## is a complete instruction. The *root* half of that is resolved a layer down,
## in `DirectorPaths.load_config`, so that every reader of the root -- the sound
## index included -- sees the same game; only the movie, the frame and the state
## are resolved here, because they are the preview's business and nothing else's.
static func stage(host) -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		host._fail("no game configured: %s" % Paths.CONFIG_PATH)
		return

	# `--root <name>` beats the config, and is applied inside `load_config` so
	# every reader sees the same root -- `AudioDirector` builds its sound index
	# from its own `load_config()` call, so an override applied only here moved
	# the movies and left the sounds indexed against the config. The game ran
	# silent and nothing said why.
	print("game root: %s" % paths.root)

	# The save, if there is one, before the movie: it names the container to open.
	# Resolved against `paths` because a bare `--save beach_bug` means this game's
	# saves folder, and that folder is named after the root.
	host._paths = paths
	var save: Dictionary = {}
	var save_path := Args.text(args, "save")
	if save_path != "":
		var found := SaveFiles.resolve(host, save_path)
		if found == "":
			host._fail("no save at %s (looked in %s)" % [
				save_path, SaveFiles.directory(host)])
			return
		var got: Dictionary = SaveFiles.read(found)
		if str(got["error"]) != "":
			host._fail(str(got["error"]))
			return
		save = got["data"]
		var verdict: Dictionary = SaveFiles.check(host, save)
		if str(verdict["refuse"]) != "":
			host._fail("save refused: %s" % str(verdict["refuse"]))
			return
		if str(verdict["warn"]) != "":
			push_warning("save: %s" % str(verdict["warn"]))
			print("save WARNING: %s" % str(verdict["warn"]))
		host._last_save = found
		print("save: %s  (%s, commit %s)" % [found,
			str((save.get("stamp", {}) as Dictionary).get("at", "?")),
			str((save.get("stamp", {}) as Dictionary).get("commit", "?")).substr(0, 12)])

	var wanted := Args.text(args, "file", paths.boot_movie)
	# The save decides the container, and `--file` beside it is a contradiction
	# rather than a refinement -- so the save wins and says so, instead of opening
	# a movie the state does not describe.
	if not save.is_empty():
		if args.has("file") and str(save.get("movie", "")).to_lower() != wanted.to_lower():
			print("save: ignoring --file %s; the save names %s"
				% [wanted, str(save.get("movie", ""))])
		wanted = str(save.get("movie", wanted))
	var path: String = paths.resolve(wanted)
	if path == "":
		# Name what is actually there. Not every title boots `strtgame.dir` --
		# `rating` does not -- so `--root <game>` on its own dead-ends on the
		# configured boot movie, and "no such container" alone leaves the reader
		# guessing at a filename they cannot see.
		# Movies only -- a cast has no score and cannot boot -- and a handful of
		# them. `rating` has 113 containers at its root, and a list that long is
		# not a hint, it is a wall. Names that look like an entry point come
		# first, since that is what the reader is looking for.
		var found := PackedStringArray()
		var likely := PackedStringArray()
		var dir := DirAccess.open(paths.root)
		if dir != null:
			for entry in dir.get_files():
				if not ContainerName.MOVIE.has(entry.get_extension().to_lower()):
					continue
				var stem := entry.get_basename().to_lower()
				if stem.contains("start") or stem.contains("strt") \
						or stem.contains("main") or stem.contains("menu") \
						or stem.contains("intro"):
					likely.append(entry)
				else:
					found.append(entry)
		likely.sort()
		found.sort()
		var show := likely + found
		var hint := ""
		if not show.is_empty():
			hint = "  try --file with one of: %s%s" % [
				", ".join(show.slice(0, 8)),
				", ... (%d more)" % (show.size() - 8) if show.size() > 8 else "",
			]
		host._fail("no such container: %s in %s%s" % [wanted, paths.root, hint])
		return

	if not host._load_container(path):
		return

	var label := Args.text(args, "label")
	if label != "":
		host._index = int(host._labels.labels.get(label.to_lower(), 0))
	host._index = clampi(Args.number(args, "frame", host._index), 0,
		max(host._score.frame_count - 1, 0))

	# Pixel art: nearest filtering. A fractional scale factor makes some rows one
	# pixel taller than their neighbours, which reads as the art being wrong
	# rather than as the scaling being wrong.
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color.BLACK)
	host._aspect = str(GameConfig.merged(Paths.CONFIG_PATH).get_value(
		"display", "aspect", host._aspect)).to_lower()
	host._aspect = Args.text(args, "aspect", host._aspect).to_lower()
	# Only the stage fits itself to the OS window. A Movie-In-A-Window is a child
	# of the stage and already inherits its scale, so running this on one scales
	# it a second time -- at the default window that is 1.55 twice over, and the
	# joke popup arrives at nearly two and a half times its size. Its geometry
	# comes from `_apply_window_geometry` instead, which places it in *stage*
	# coordinates where it belongs.
	host.get_window().size_changed.connect(host._fit_to_window)
	host._fit_to_window()

	host._lingo_on = not Args.flag(args, "no-lingo")
	if host._lingo_on:
		start_lingo(host, path)
	host._audio = host.root_node("AudioDirector")
	# The frame the movie opens on is entered like any other: its tempo arms the
	# clock and its transition, if it has one, is played before anything runs on
	# it. Without this the first frame is paced by the default rate whatever the
	# score says, and the first step would re-enter it and re-arm the same delay.
	host._sync_frame_entry()
	if host._lingo_on and host._interpreter != null:
		# Director sends these once, before the first frame is drawn, and this is
		# where a movie's opening sound and its global setup live.
		host._dispatch("prepareMovie", {})
		host._dispatch("startMovie", {})
		# Then the frame entry, both halves of it. `Score::startPlay` stops at
		# `startMovie`; the `update()` that follows it broadcasts `prepareFrame`
		# (`score.cpp:772-779`) and sends `enterFrame` (`:827-831`) for the frame the
		# movie opened on, with only `_newMovieStarted` suppressing `idle` and
		# `exitFrame`. Sending one half of the pair here is how the two came to
		# disagree: every other frame entry in this port sends both.
		var opened: Dictionary = host._frame_script(host._index)
		host._dispatch("prepareFrame", opened)
		host._enter_frame_or_defer(opened)

	# **After `startMovie`, not before.** A movie's own opening handlers write the
	# globals the port carries -- `SAVELOAD` sets `nof`, `newsyz` and the rest --
	# so a state installed ahead of them would be overwritten by the very movie it
	# is meant to be reproducing. Restoring afterwards is also what makes a
	# `--save` boot and an in-session Shift+F6 land on the same state: both arrive
	# through a complete, ordinary movie start and then have the record put on top.
	if not save.is_empty():
		var failed: String = SaveState.restore(host, save)
		if failed != "":
			host._fail("save: %s" % failed)
			return
		SaveState.restore_windows(host, save)
		# No `_sync_frame_entry` here on purpose. The record says whether the frame
		# had been entered, and re-entering would re-arm its tempo and restart its
		# sound — see `save_state.gd:restore` on `_entered_index`.
		print("save: restored %s frame %d" % [host.movie_name(), host._index])

	host.get_window().title = "%s  -  %d frames" % [
		path.get_file(), host._score.frame_count]
	print("playing %s from frame %d of %d" % [
		path.get_file(), host._index, host._score.frame_count])
	host.queue_redraw()


## A window: stand up a movie another movie asked for.
##
## Loaded but not shown and not running -- `_process` is off until `open`, so the
## playhead does not move and `startMovie` has not been sent. That ordering is
## the corpus's, not a convenience. Every one of the 21 sites reads
##
##     window("x").windowType = 2
##     tell window("x") / set the centerStage to 1 / end tell
##     open(window("x"))
##
## and three of them also `go` to a label inside the `tell`, so the movie has to
## be addressable before it is opened and must not have advanced past the frame
## the `go` chose.
##
## Input is off as well. The stage routes clicks and keys to the front-most
## window explicitly, rather than letting Godot's own reverse-tree `_input` order
## decide, because that order is invisible in a headless harness and a click has
## to be assertable.
static func as_window(host) -> void:
	host._paths = host._stage_preview._paths
	host._aspect = host._stage_preview._aspect
	host._lingo_on = host._stage_preview._lingo_on
	host._audio = host.root_node("AudioDirector")
	# The debug outlines belong to whoever is looking at the stage, and a window
	# drawn over it should not add a second set.
	host._show_boxes = false
	host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	host.visible = false
	host.set_process(false)
	host.set_process_input(false)
	if not host._load_container(host._window_path):
		return
	if host._lingo_on:
		start_lingo(host, host._window_path)
		host._share_movie_state_with(host._stage_preview)
	print("window %s: %d frames" % [
		host._window_path.get_file(), host._score.frame_count])


## Compile every cast this movie can address and hand the scripts to a fresh
## interpreter, carrying the globals across.
##
## The interpreter's own dictionary is the one that matters. `owns_global` on the
## host answers "do I already hold this name", and nothing ever seeds the host's
## dictionary, so it is always false and every global lives in the interpreter's.
## Both are carried anyway, so that stops being load-bearing if the host ever
## does claim one.
static func start_lingo(host, path: String) -> void:
	var carried_globals: Dictionary = {}
	var carried_host_globals: Dictionary = {}
	if host._interpreter != null:
		carried_globals = host._interpreter.globals
	if host._host != null:
		carried_host_globals = host._host.globals

	var movie := path.get_file().get_basename().to_upper()
	host._interpreter = Interpreter.new()
	host._host = PreviewHost.new()
	host._host.preview = host
	host._interpreter.host = host._host
	host._interpreter.globals = carried_globals
	host._host.globals = carried_host_globals

	var compiler := Compiler.new()
	var started := Time.get_ticks_usec()
	var total := 0
	host._script_casts.clear()
	for lib in host._table.cast_libs:
		var cast = host._table.cast_for(int(lib))
		if cast == null:
			continue
		var entry: Dictionary = host._table.cast_libs[lib]
		var cast_name := str(entry.get("name", "")).to_lower()
		if cast_name == "" or int(lib) == 1:
			cast_name = "internal"
		var bundle: Dictionary = compiler.compile_cast(cast, movie, cast_name)
		var count := (bundle.get("scripts", {}) as Dictionary).size()
		# **A script that will not parse is dropped, and saying nothing about it is
		# the worst thing this boot does.** `compile_cast` has always collected the
		# failures into `compiler.error`; nothing read it, so a script vanished
		# whole -- with every handler in it -- and the only trace was those
		# handlers turning up later in `builtins unbound`, which reads like a
		# missing *feature* rather than a missing *file*.
		#
		# Itamar Park is what it cost: two syntax gaps took five scripts out of one
		# cast, and with them `openLevelsWindow`, `getFlag` and `setFlag`. The
		# level select never opened, the frame behind it holds with
		# `go(the frame)` as every room in every title does, and the movie sat
		# there for ever. No error, no hang, nothing on the clock -- a legitimate
		# wait for something deleted at compile time. Hours went into that, and
		# this line would have answered it in one boot.
		#
		# Printed rather than raised: a title with one bad script should still run
		# as far as it can, which is how the rest of this port treats a hole. It is
		# loud, it names the script and the line, and it is not behind the debug
		# switch -- a build that cannot compile part of the game is not a debug
		# question.
		if str(compiler.error) != "":
			push_warning("lingo: %s: %s" % [cast_name, compiler.error])
			print("lingo: %-10s SCRIPTS DROPPED -- %s" % [cast_name, compiler.error])
		if count == 0:
			continue
		host._interpreter.load_bundle(bundle, movie)
		# The movie's own cast is searched first, so it is listed first.
		var key := "%s/%s" % [movie, cast_name]
		host._lib_keys[int(lib)] = key
		if int(lib) == 1:
			host._script_casts.insert(0, key)
		else:
			host._script_casts.append(key)
		total += count
		print("lingo: %-10s %3d script(s)" % [cast_name, count])
	print("lingo: %d script(s) across %d cast(s) in %.0f ms" % [
		total, host._script_casts.size(),
		(Time.get_ticks_usec() - started) / 1000.0,
	])
	if host._script_casts.is_empty():
		print("lingo: nothing compiled; %s" % compiler.error)
