extends RefCounted
## The tracked `director_game.cfg`, with this machine's overlay on top.
##
##   const GameConfig := preload("res://director/game_config.gd")
##   var cfg := GameConfig.merged()
##   cfg.get_value("game", "root", "")
##
## `director_game.cfg` is tracked, and it is also a working file: `root` and
## `boot_movie` get pointed at whichever title is under the microscope, so every
## session that looks at a second game carries a diff nobody wants to commit.
## `user://director_game.local.cfg` is that edit, per machine, outside the
## checkout -- untracked by construction rather than by a `.gitignore` line.
##
## **One merge point, because there were four readers.** `director_paths.gd`,
## `director_codepage.gd`, `scenes/preview/boot.gd` and `scenes/preview/
## debug_keys.gd` each did their own `ConfigFile.load` on the tracked file. An
## overlay taught to four readers is four chances for them to disagree, and this
## repository has already paid that bill once: `director_paths.gd` records that
## applying `--root` in `preview/boot.gd` alone moved the movies and left
## `AudioDirector` -- which calls `load_config()` for itself -- indexing its
## sounds against the old root, so the game ran silent.
##
## In `director/` and not `scenes/` for the same reason: `AudioDirector` is an
## autoload and `DirectorCodepage` is engine code, and neither may depend on the
## preview.
##
## Command-line flags are *not* resolved here. They stay in the reader that owns
## them -- `--root` and `--boot` in `DirectorPaths`, `--codepage` in
## `DirectorCodepage`, `--debug-ui` in `DebugKeys` -- and are applied on top of
## the merged answer. `gate.sh` pins its corpus with `--root piposh2 --boot
## strtgame.dir`, and that has to keep beating everything below it.

## The tracked file. Never written by this port: it is what an export ships, and
## it is edited by hand by whoever is changing a shipped default.
const TRACKED_PATH := "res://director_game.cfg"

## The machine-local overlay. `user://` rather than a gitignored file beside the
## checkout because Android is the only export preset, and there `res://` is
## inside the APK and cannot be written at all.
const OVERLAY_PATH := "user://director_game.local.cfg"

static var _merged: Dictionary = {}
static var _tracked: Dictionary = {}
static var _present: Dictionary = {}


## Whether the overlay is consulted at all in this process.
##
## **No, when there is no display server**, which is every gate harness, every
## child process one of them spawns, and every ad-hoc `godot --headless --script
## tools/x.gd`. The overlay is one file per machine shared by every process on
## it, and a harness reading a human's copy is the same failure `gate.sh` removed
## when it stopped rewriting the `root` line: two runs at once had each other's
## corpus swapped out mid-run and reported another title's movies as this one's
## regressions.
##
## A `--no-local` flag on the runner was the alternative and is worse: a run that
## forgets it reads the overlay silently, and there is no flag at all on the
## ad-hoc invocations. Keying on the display server cannot be forgotten.
static func overlay_applies() -> bool:
	return DisplayServer.get_name() != "headless"


## The tracked file with the overlay laid over it, key by key.
##
## `overlay_path` is the harness seam and nothing else: `""` means "the real
## overlay, if `overlay_applies()`", which is what every production caller
## passes. A harness that has just written two files names them both, the way
## `tools/debug_bindings.gd` already hands `DebugKeys.load_config` a file it
## wrote. An explicit path is applied whether or not there is a display, because
## a test of the merge that could not run headless could not run in the gate.
##
## The result is a fresh `ConfigFile`, so a caller may read it with the ordinary
## API -- `get_value`, `has_section`, `get_section_keys` -- and the four readers
## this replaces changed by one line each.
static func merged(tracked_path := TRACKED_PATH, overlay_path := "") -> ConfigFile:
	var key := tracked_path + "|" + overlay_path
	if not _merged.has(key):
		_build(tracked_path, overlay_path, key)
	return _merged[key]


## The tracked file alone, with no overlay under any circumstances.
##
## One caller, and it is deliberate: the launcher decides whether to show its
## developer tab from *this* rather than from `merged`. `[debug] enabled` is
## editable in that tab, so a tab whose visibility read the merged value would
## close the door behind itself -- set it false and the control that would set it
## back is gone. `--debug-ui on` recovers that on a desktop; Android has no
## command line and is the only export preset, so there the recovery is
## clear-app-data.
static func tracked(tracked_path := TRACKED_PATH) -> ConfigFile:
	if not _tracked.has(tracked_path):
		_build(tracked_path, "", tracked_path + "|")
	return _tracked[tracked_path]


## Whether the tracked file was there and parsed. Callers that treat a missing
## config as a setup problem rather than a default need to tell the two apart.
static func exists(tracked_path := TRACKED_PATH) -> bool:
	if not _present.has(tracked_path):
		_build(tracked_path, "", tracked_path + "|")
	return bool(_present[tracked_path])


## Drop every cached read. Called after the launcher writes the overlay, and by
## any harness that has just written a file it is about to read back.
static func invalidate() -> void:
	_merged = {}
	_tracked = {}
	_present = {}


## Replace the overlay with `cfg`. The only writer of `OVERLAY_PATH`, and it
## never touches the tracked file.
static func write_overlay(cfg: ConfigFile) -> bool:
	var ok := cfg.save(OVERLAY_PATH) == OK
	invalidate()
	return ok


## The overlay as it stands, or an empty `ConfigFile` when it is absent or
## unreadable. The launcher reads this to seed its controls, edits it, and hands
## it back to `write_overlay`.
static func overlay() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(OVERLAY_PATH)
	return cfg


static func _build(tracked_path: String, overlay_path: String, key: String) -> void:
	var base := ConfigFile.new()
	_present[tracked_path] = base.load(tracked_path) == OK
	_tracked[tracked_path] = base

	var out := ConfigFile.new()
	_copy(base, out)
	var wanted := overlay_path
	if wanted == "":
		wanted = OVERLAY_PATH if overlay_applies() else ""
	if wanted != "":
		var over := ConfigFile.new()
		# A malformed overlay is ignored, not fatal. It is a file a human edits;
		# a typo in it must not stop the game booting, and the tracked answers
		# below it are a working configuration by definition.
		if over.load(wanted) == OK:
			_copy(over, out)
	_merged[key] = out


static func _copy(from: ConfigFile, to: ConfigFile) -> void:
	for section in from.get_sections():
		for name in from.get_section_keys(section):
			to.set_value(section, name, from.get_value(section, name))
