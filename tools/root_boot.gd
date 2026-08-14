extends SceneTree
## Every title boots, and `--root <name>` alone is enough to boot it.
##
##   godot --headless --audio-driver Dummy --path . --script tools/root_boot.gd
##   godot --headless --audio-driver Dummy --path . --script tools/root_boot.gd -- --root rating
##
## ## What this is for
##
## `--root` moves the corpus. `[game] boot_movie` in `director_game.cfg`
## describes the root `[game] root` names and nothing else, so carrying it across
## a `--root` points the engine at a container of the *previous* title. Nothing
## crashes at that point -- the boot movie simply is not there, the preview holds
## no movie, and the very next `go to movie` dereferences a null one and raises
##
##     Invalid access to property 'path' on a base object of type 'Nil'
##
## which is a sentence about GDScript and not about the game. `bugs.md` 111
## measured five of `rating`'s minigames as `no-open` through exactly that route
## and **not one of them was broken**; `bugs.md` 51 is the same trap costing
## `gate.sh` a whole suite of harnesses that loaded no score and asserted over
## nothing. Both are configuration reaching the reader as a symptom.
##
## `DirectorPaths.load_config` now takes the boot movie from `[root.<name>] boot`
## whenever the command line names a root, which is the same mapping the launcher
## has always read through `scenes/launcher/title_list.gd`. This asserts the two
## halves of that:
##
##  1. **Every root under `games/` boots**, checked by pairing each root with its
##     own configured boot movie and resolving it. That is the invariant a title
##     added to the repository has to satisfy, and it is checked for all of them
##     in one process rather than for whichever one the config points at -- see
##     AGENTS.md on measured zeros, which is the same mistake one root down.
##  2. **`--root <name>` on its own reaches the same answer**, checked through a
##     real `load_config()` in a process that was actually given the flag. Half 1
##     can pass while half 2 fails, because half 1 reads the config directly and
##     half 2 goes through the override path that had the bug.
##
## ## Why it asserts the config as well as the code
##
## A root whose `[root.*]` section names a container that is not in it is a
## misconfiguration this engine cannot recover from, and it is invisible until
## somebody launches that title. `tools/title_mapping.gd` already asserts that
## the sections and the directories match; this asserts that the `boot` inside
## each section names a movie that is there. Between them the config cannot say
## a title exists and leave it unopenable.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const GameConfig := preload("res://director/game_config.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const ContainerName := preload("res://director/director_container.gd")


func _init() -> void:
	var h := Harness.new()
	var cfg := GameConfig.merged(Paths.CONFIG_PATH)

	# --- 1. every root under `games/` boots on the override path --------------
	#
	# **Through `load_config(_, <root>)`, not by setting the two fields.** The
	# seam runs the same code `--root` runs, per-root boot lookup included, so
	# this loop is the override path exercised six times in one process. Setting
	# `root` and `boot_movie` by hand would test the *mapping* and skip the
	# resolution that had the bug — which is exactly how a bare run of this
	# harness passed with `bugs.md` 111 present, because the one root a process
	# can be started with was the configured one.
	h.begin("every title under games/ names a boot movie that is in it")
	var roots: Array[String] = KeySites.roots()
	var missing: Array[String] = []
	var unmapped: Array[String] = []
	var report: Array[String] = []
	for where in roots:
		var name := where.get_file()
		if str(cfg.get_value("root.%s" % name, "boot", "")) == "":
			unmapped.append(name)
			continue
		var probe := Paths.new()
		if not probe.load_config(Paths.CONFIG_PATH, name):
			missing.append("%s -> %s" % [name, probe.error])
			continue
		var resolved := probe.boot_path()
		report.append("%-14s %-16s %s" % [
			name, probe.boot_movie, resolved if resolved != "" else "NOT FOUND"])
		if resolved == "":
			missing.append(probe.error if probe.error != "" else "%s -> %s" % [
				name, probe.boot_movie])
		elif not ContainerName.MOVIE.has(resolved.get_extension().to_lower()):
			# A cast has no score and cannot boot. Cheap, and it is the failure
			# a typo in the mapping produces most often, because the two file
			# families sit in the same directory under the same stem.
			missing.append("%s -> %s is not a movie" % [name, probe.boot_movie])
	for line in report:
		print("  %s" % line)
	h.check("at least one root was found", not roots.is_empty(),
		"%d root(s) under %s" % [roots.size(), Paths.games_dir()])
	h.check("every root has a [root.<name>] boot", unmapped.is_empty(),
		", ".join(unmapped))
	h.check("and --root <name> reaches a boot movie that is in it", missing.is_empty(),
		"; ".join(missing))
	h.complete("every title under games/ names a boot movie that is in it")

	# --- 2. the flag reaches the same answer ----------------------------------
	#
	# This is the half `bugs.md` 111 is about. `load_config()` reads the command
	# line itself, so what is asserted here is a property of *this process's*
	# arguments: run bare it asserts the configured root boots, and run with
	# `--root <name>` it asserts that root boots on the flag alone.
	h.begin("--root on its own is enough to boot a title")
	var paths := Paths.new()
	var loaded := paths.load_config()
	h.check("the config loads", loaded, paths.error)
	if loaded:
		print("  root %s boots %s" % [paths.root, paths.boot_movie])
		h.check("the configured pair opens a container", paths.boot_resolves(),
			paths.error if paths.error != "" else "%s in %s" % [paths.boot_movie, paths.root])
		# The message is asserted, not only the verdict. A refusal that does not
		# say which root and which movie sends the reader to the wrong question,
		# which is the cost `bugs.md` 111 actually records -- the crash was
		# cheap, the two sessions spent on "five minigames are broken" were not.
		if not paths.boot_resolves():
			h.check("and the refusal names both the root and the movie",
				paths.error.contains(paths.root) and paths.error.contains(paths.boot_movie),
				paths.error)
	h.complete("--root on its own is enough to boot a title")

	quit(h.finish("every root boots, and --root alone is enough"))
