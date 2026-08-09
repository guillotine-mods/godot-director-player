# Launcher Screen and Config Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the port a main screen that sets the game and its options, writing to an untracked per-machine overlay so `director_game.cfg` stops carrying a diff in every working tree.

**Architecture:** One merge point — `director/game_config.gd` — reads the tracked `res://director_game.cfg` and lays `user://director_game.local.cfg` over it, returning a merged `ConfigFile`. The four sites that load the config today ask it instead. The overlay is skipped when `DisplayServer.get_name() == "headless"`, so every gate harness measures the tracked file unchanged. A launcher scene becomes `main_scene` and writes the overlay.

**Tech Stack:** Godot 4.7.1 stable, GDScript. No third-party libraries, no new assets. Tests are `tools/*.gd` `SceneTree` harnesses run headless and listed in `gate.sh`'s `ALL`, using `tools/lib/harness.gd` and `tools/lib/args.gd`.

## Global Constraints

- Godot **4.7.1.stable**. `project.godot` declares `config/features=PackedStringArray("4.7", "Forward Plus")`.
- Engine code in `director/` must never depend on `scenes/`. `scenes/` may depend on `director/`. `AudioDirector` (an autoload) and `DirectorCodepage` both reach the config, which is why the merge point lives in `director/`.
- Tools use `const X := preload("res://...")`, never `class_name`. A headless `--script` run resolves global classes from the editor's script cache, and a class added since the last editor session is "not declared in the current scope" in a file nobody touched.
- Every new harness uses `tools/lib/harness.gd`'s `begin`/`check`/`complete`/`finish` pairing. A case left open at `finish` is a failure — that guard is why the file exists.
- A harness that asserts nothing is a failure, not a pass. `gate.sh` reports `EMPTY` for a run with 0 checks. Every harness must first assert its subject exists.
- CLI flags beat the overlay, which beats the tracked file. `gate.sh` pins with `--root piposh2 --boot strtgame.dir` and that must keep winning.
- Push directly to `main`. No branches, no PRs. `bash gate.sh` is the only gate.
- The recorded gate set is **62 pass / 0 fail** today. This plan adds three entries; the final recorded set is **65 pass / 0 fail** and `gate.sh`'s header comment must say so.
- Never write `res://director_game.cfg` from code. It is edited by hand, by whoever changes a shipped default.

---

### Task 1: `director/game_config.gd` — the merge point

**Files:**
- Create: `director/game_config.gd`
- Create: `tools/game_config.gd`
- Modify: `gate.sh:93` (the `ALL` list), `gate.sh:2-6` (the recorded count)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `GameConfig.TRACKED_PATH: String` — `"res://director_game.cfg"`
  - `GameConfig.OVERLAY_PATH: String` — `"user://director_game.local.cfg"`
  - `GameConfig.overlay_applies() -> bool`
  - `GameConfig.merged(tracked_path := TRACKED_PATH, overlay_path := "") -> ConfigFile`
  - `GameConfig.tracked(tracked_path := TRACKED_PATH) -> ConfigFile`
  - `GameConfig.exists(tracked_path := TRACKED_PATH) -> bool`
  - `GameConfig.invalidate() -> void`
  - `GameConfig.write_overlay(cfg: ConfigFile) -> bool`

- [ ] **Step 1: Write the failing harness**

Create `tools/game_config.gd`:

```gdscript
extends SceneTree
## The tracked config, the machine-local overlay, and which one wins.
##
##   godot --headless --path . --script tools/game_config.gd
##
## Four sites used to load `director_game.cfg` for themselves. They ask
## `director/game_config.gd` now, and this is what that file promises them: the
## overlay wins per key, a key it does not carry falls through to the tracked
## file, an absent or unreadable overlay changes nothing, and under `--headless`
## the real overlay is not consulted at all.
##
## That last one is what keeps the other 62 entries honest. The overlay is one
## file per machine, shared by every process on it, which is the same shape as
## the failure `gate.sh` removed when it stopped rewriting the `root` line: two
## runs at once had each other's corpus swapped out mid-run. Keying on the
## display server means a harness cannot read a human's overlay even by
## forgetting a flag, and neither can an ad-hoc `godot --headless --script` run.
##
## Title-agnostic: it writes its own files and names no game.

const Harness := preload("res://tools/lib/harness.gd")
const GameConfig := preload("res://director/game_config.gd")

const SCRATCH_TRACKED := "user://gate_game_config_tracked.cfg"
const SCRATCH_OVERLAY := "user://gate_game_config_overlay.cfg"
const SCRATCH_BROKEN := "user://gate_game_config_broken.cfg"


func _init() -> void:
	var h := Harness.new()
	_write(SCRATCH_TRACKED, "[game]\nroot = \"res://games/piposh2\"\nboot_movie = \"strtgame.dir\"\ncodepage = \"mac_hebrew\"\n\n[display]\naspect = \"native_4_3\"\n")
	_write(SCRATCH_OVERLAY, "[game]\nroot = \"res://games/rating\"\n")
	_write(SCRATCH_BROKEN, "this is not a config file\n[[[\n")

	var case := "the overlay wins per key and falls through for the rest"
	h.begin(case)
	GameConfig.invalidate()
	var merged := GameConfig.merged(SCRATCH_TRACKED, SCRATCH_OVERLAY)
	h.check("the overlay's root wins",
		str(merged.get_value("game", "root", "")) == "res://games/rating",
		str(merged.get_value("game", "root", "<missing>")))
	h.check("a key the overlay does not carry falls through",
		str(merged.get_value("game", "boot_movie", "")) == "strtgame.dir",
		str(merged.get_value("game", "boot_movie", "<missing>")))
	h.check("a whole section the overlay does not carry falls through",
		str(merged.get_value("display", "aspect", "")) == "native_4_3",
		str(merged.get_value("display", "aspect", "<missing>")))
	h.check("the tracked view is not touched by the overlay",
		str(GameConfig.tracked(SCRATCH_TRACKED).get_value("game", "root", "")) == "res://games/piposh2",
		str(GameConfig.tracked(SCRATCH_TRACKED).get_value("game", "root", "<missing>")))
	h.complete(case)

	case = "an absent or unreadable overlay changes nothing"
	h.begin(case)
	GameConfig.invalidate()
	var none := GameConfig.merged(SCRATCH_TRACKED, "user://gate_game_config_absent.cfg")
	h.check("an absent overlay leaves the tracked answer",
		str(none.get_value("game", "root", "")) == "res://games/piposh2",
		str(none.get_value("game", "root", "<missing>")))
	GameConfig.invalidate()
	var broken := GameConfig.merged(SCRATCH_TRACKED, SCRATCH_BROKEN)
	h.check("an unreadable overlay is ignored rather than fatal",
		str(broken.get_value("game", "root", "")) == "res://games/piposh2",
		str(broken.get_value("game", "root", "<missing>")))
	h.check("a missing tracked file reports absent",
		not GameConfig.exists("user://gate_game_config_nothing.cfg"))
	h.check("and a missing tracked file still answers the default",
		str(GameConfig.merged("user://gate_game_config_nothing.cfg", "").get_value(
			"game", "root", "fallback")) == "fallback")
	h.complete(case)

	# The rule the other 62 entries depend on. This process *is* headless, so
	# asking for the real overlay must not consult it -- asserted by writing one
	# that would be obvious if it were read.
	case = "under --headless the real overlay is not consulted"
	h.begin(case)
	h.check("this run is headless", DisplayServer.get_name() == "headless",
		DisplayServer.get_name())
	h.check("so the overlay does not apply", not GameConfig.overlay_applies())
	# **The real overlay belongs to whoever is sitting here**, and this is the
	# one gate entry that has to touch it -- the rule under test is about that
	# exact path, so a scratch file would assert nothing. It is read back first
	# and put back after: `bash gate.sh` is the command this repository tells
	# you to run constantly, and a gate that silently wipes your launcher
	# settings would be a worse bug than the one it is guarding.
	var had := FileAccess.file_exists(GameConfig.OVERLAY_PATH)
	var saved := FileAccess.get_file_as_string(GameConfig.OVERLAY_PATH) if had else ""
	var planted := ConfigFile.new()
	planted.set_value("game", "root", "res://games/should-never-be-read")
	planted.save(GameConfig.OVERLAY_PATH)
	GameConfig.invalidate()
	var real := GameConfig.merged(SCRATCH_TRACKED, "")
	h.check("a planted overlay is not read",
		str(real.get_value("game", "root", "")) == "res://games/piposh2",
		str(real.get_value("game", "root", "<missing>")))
	if had:
		_write(GameConfig.OVERLAY_PATH, saved)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameConfig.OVERLAY_PATH))
	h.check("the overlay this machine had is back as it was",
		FileAccess.file_exists(GameConfig.OVERLAY_PATH) == had
			and (not had or FileAccess.get_file_as_string(GameConfig.OVERLAY_PATH) == saved))
	h.complete(case)

	for path in [SCRATCH_TRACKED, SCRATCH_OVERLAY, SCRATCH_BROKEN]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameConfig.invalidate()
	quit(h.finish("the tracked config, the overlay, and which one wins"))


func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `godot --headless --path . --script tools/game_config.gd`

Expected: FAIL — `res://director/game_config.gd` does not exist, so the `preload` is a parse error. Find your Godot the way the gates do if `godot` is not on `PATH`: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --headless --path . --script tools/game_config.gd`.

- [ ] **Step 3: Write the implementation**

Create `director/game_config.gd`:

```gdscript
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --headless --path . --script tools/game_config.gd`

Expected: `PASS` with 12 checks and no `FAIL` lines. Then confirm by hand that your own overlay survived, if you had one — the file still there and unchanged after the run, which is what the last assertion also claims.

- [ ] **Step 5: Add it to the gate and correct the recorded count**

In `gate.sh`, add `game_config` to the front of the `ALL` string (line 93), right before `preview_surface`. Then change the header's recorded set from 62 to 63 — `gate.sh:2-6` says "over the 62 entries in ALL is **62 pass / 0 fail**". Its own comment warns that this line "said 54 entries for as long as it took the list to reach 61"; not updating it is the defect it describes.

- [ ] **Step 6: Run the whole gate**

Run: `bash gate.sh`

Expected: 63 lines, all `PASS`. No `TIMEOUT`, no `EMPTY`, no `ERROR`.

- [ ] **Step 7: Commit**

```bash
git add director/game_config.gd tools/game_config.gd gate.sh
git commit -m "config: one merge point for the tracked file and the machine-local overlay

Four sites load director_game.cfg for themselves today. This is the file
they will ask instead: tracked underneath, user://director_game.local.cfg
over the top, and nothing consulted at all when there is no display server
-- so every harness measures the tracked file without a flag anyone can
forget. Nothing reads it yet; the four readers move in the next commit.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Move the four readers onto the merge point

**Files:**
- Modify: `director/director_paths.gd:16` (add the preload), `:43-51` (`load_config`)
- Modify: `director/director_codepage.gd:370-378` (`_configured`)
- Modify: `scenes/preview/boot.gd:146-148`
- Modify: `scenes/preview/debug_keys.gd:252-292` (`load_config`), `:304` (`_resolve_switch`)

**Interfaces:**
- Consumes: `GameConfig.merged(tracked_path, overlay_path)`, `GameConfig.exists(tracked_path)` from Task 1.
- Produces: no new signatures. `DirectorPaths.load_config(config_path := CONFIG_PATH) -> bool` and `DebugKeys.load_config(config_path := CONFIG_PATH) -> void` keep their exact existing signatures — `tools/debug_bindings.gd:209` passes a written file to the second and must keep working.

**Why this is its own task:** it is the only change in the plan that can break the existing 62 harnesses, and with no overlay file present it must break nothing at all. A reviewer can reject it on `bash gate.sh` alone.

- [ ] **Step 1: Establish the baseline before touching anything**

Run: `bash gate.sh 2>&1 | tee /tmp/gate-before.txt` then `grep -c PASS /tmp/gate-before.txt`

Expected: 63. **Run this now, in this session, before editing any reader** — Step 6 diffs against this exact file, and Task 1's run does not count: a fresh session has no `/tmp/gate-before.txt`, and a stale one from another branch would make the comparison meaningless. This task's whole assertion is that the verdicts do not move.

- [ ] **Step 2: Move `DirectorPaths.load_config`**

In `director/director_paths.gd`, add beside the existing `ContainerName` preload at line 17:

```gdscript
const GameConfig := preload("res://director/game_config.gd")
```

Replace the body of `load_config` (lines 43-51) with:

```gdscript
func load_config(config_path: String = CONFIG_PATH) -> bool:
	if not GameConfig.exists(config_path):
		return false
	var cfg := GameConfig.merged(config_path)
	root = str(cfg.get_value("game", "root", ""))
	boot_movie = str(cfg.get_value("game", "boot_movie", ""))
	root = _override_root(root)
	boot_movie = _override_boot(boot_movie)
	return root != "" and boot_movie != ""
```

Leave `CONFIG_PATH`, `_override_root` and `_override_boot` exactly as they are. The flags still resolve here, on top of the merged answer, which is the whole point of the layering.

- [ ] **Step 3: Move `DirectorCodepage._configured`**

In `director/director_codepage.gd`, add the preload beside the other consts at the top of the file:

```gdscript
const GameConfig := preload("res://director/game_config.gd")
```

Replace the tail of `_configured` (the three lines that build a `ConfigFile`) with:

```gdscript
static func _configured() -> String:
	var override := _from_command_line()
	if override != "":
		return override
	return str(GameConfig.merged(CONFIG_PATH).get_value("game", "codepage", ""))
```

`_from_command_line` stays first: `--codepage` beats the overlay, exactly as `--root` does.

- [ ] **Step 4: Move `boot.gd`**

In `scenes/preview/boot.gd`, add the preload beside the existing ones at the top:

```gdscript
const GameConfig := preload("res://director/game_config.gd")
```

Replace lines 146-148:

```gdscript
	host._aspect = str(GameConfig.merged(Paths.CONFIG_PATH).get_value(
		"display", "aspect", host._aspect)).to_lower()
	host._aspect = Args.text(args, "aspect", host._aspect).to_lower()
```

The `var cfg := ConfigFile.new()` and its `if cfg.load(...) == OK` guard go away — `merged` on a missing file returns an empty `ConfigFile`, so the default falls through on its own.

- [ ] **Step 5: Move `DebugKeys.load_config`**

In `scenes/preview/debug_keys.gd`, add beside `CONFIG_PATH`:

```gdscript
const GameConfig := preload("res://director/game_config.gd")
```

In `load_config`, replace the two lines that build the `ConfigFile`:

```gdscript
	var cfg := GameConfig.merged(config_path)
	var has_file := GameConfig.exists(config_path)
```

Everything below them — the `SETTINGS` loop, the `DEFAULTS` loop, the three `push_warning` calls, the unknown-key sweep — is untouched, because `cfg` is still an ordinary `ConfigFile`. `_resolve_switch(cfg, has_file)` keeps its exact signature and body.

- [ ] **Step 6: Run the whole gate and compare**

Run: `bash gate.sh 2>&1 | tee /tmp/gate-after.txt` then `diff /tmp/gate-before.txt /tmp/gate-after.txt`

Expected: no differences beyond the `corpus:` and Godot-version banner lines. 63 `PASS`, 0 `FAIL`. **If any line changed verdict, stop and fix it before committing** — a moved reader that changes an answer is the failure this task exists to prevent.

- [ ] **Step 7: Commit**

```bash
git add director/director_paths.gd director/director_codepage.gd \
        scenes/preview/boot.gd scenes/preview/debug_keys.gd
git commit -m "config: the four readers ask the merge point instead of the file

director_paths, director_codepage, preview/boot and preview/debug_keys each
did their own ConfigFile.load on the tracked config. They ask game_config.gd
now. Flags stay where they were -- --root and --boot in DirectorPaths,
--codepage in DirectorCodepage, --debug-ui in DebugKeys -- resolved on top of
the merged answer, so gate.sh's pinning is untouched.

No behaviour change with no overlay present, which is what the unchanged
63/0 asserts.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The `[root.*]` title mapping and its gate

**Files:**
- Modify: `director_game.cfg` (append the sections and their comment)
- Create: `tools/title_mapping.gd`
- Modify: `gate.sh:93` (`ALL`), `gate.sh:2-6` (the count)

**Interfaces:**
- Consumes: `GameConfig.merged()` from Task 1; `KeySites.roots() -> Array[String]` from `tools/lib/key_sites.gd`; `DirectorPaths.resolve(name, from_dir) -> String`.
- Produces: the config schema later tasks read — for each directory `<name>` under `games/`, a section `[root.<name>]` with keys `title: String`, `boot: String`, optional `flag: String` (a two-letter lower-case country code), optional `default: bool`.

- [ ] **Step 1: Write the failing harness**

Create `tools/title_mapping.gd`:

```gdscript
extends SceneTree
## Every game on disc is described, and every description points at something.
##
##   godot --headless --path . --script tools/title_mapping.gd
##
## The launcher builds its game list from `[root.<name>]` sections in
## `director_game.cfg`: which title a root belongs to, which container it boots,
## and which flag stands for it. A root with no section cannot be offered
## properly, and a section naming a container that is not there offers a game
## that boots nothing -- which is the dark-harness failure `gate.sh` warns
## about, arriving as a menu entry instead of as a red line.
##
## **A mapping rather than a probe, because the probe is measurably wrong.** The
## obvious rule -- `mainmenu.dir` if it is there, else `strtgame.dir` -- picks
## the wrong container for `piposh-dream`, which ships *both* at its root and
## boots `strtgame.dir`. Three more titles carry a `MAINMENU.dir` one directory
## down, which any looser search finds. Six games, one heuristic, at least one
## wrong answer.
##
## In the config rather than in a `const` for the reason `gate.sh`'s header
## gives about the F10 collision: that was config and not code, and this is the
## same shape -- data about which titles exist, kept where a person adding a
## title will see it. This harness is what stops it being a comment somebody has
## to remember.
##
## Title-agnostic: it reads whatever is under `games/` and names no game.

const Harness := preload("res://tools/lib/harness.gd")
const GameConfig := preload("res://director/game_config.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const Paths := preload("res://director/director_paths.gd")

## `flag = "il"` becomes 🇮🇱: two ASCII letters offset into the regional
## indicator block. Composed rather than stored so the config carries a country
## code a person can read and not a pair of code points they cannot.
const REGIONAL_INDICATOR_A := 0x1F1E6


func _init() -> void:
	var h := Harness.new()
	var cfg := GameConfig.merged()
	var roots := KeySites.roots()

	var case := "every game on disc is described"
	h.begin(case)
	# The subject has to exist, or every assertion below passes over nothing.
	if not h.check("there are game roots to check", not roots.is_empty(),
			"%d root(s)" % roots.size()):
		h.complete(case)
		quit(h.finish("the title mapping"))
		return

	var titles: Dictionary = {}
	var missing: Array[String] = []
	var unbootable: Array[String] = []
	var bad_flags: Array[String] = []
	for root in roots:
		var name := str(root).get_file()
		var section := "root.%s" % name
		if not cfg.has_section(section):
			missing.append(name)
			continue
		var title := str(cfg.get_value(section, "title", ""))
		var boot := str(cfg.get_value(section, "boot", ""))
		var flag := str(cfg.get_value(section, "flag", ""))
		if title == "":
			missing.append("%s (no title)" % name)
			continue
		var paths := Paths.new()
		paths.root = root
		if boot == "" or paths.resolve(boot) == "":
			unbootable.append("%s: boot = %s" % [name, boot if boot != "" else "<missing>"])
		if flag != "" and not _is_country_code(flag):
			bad_flags.append("%s: flag = %s" % [name, flag])
		if not titles.has(title):
			titles[title] = []
		titles[title].append(name)

	h.check("every root under games/ has a [root.<name>] section",
		missing.is_empty(), ", ".join(missing))
	h.check("every section names a container that resolves under its root",
		unbootable.is_empty(), ", ".join(unbootable))
	h.check("every flag is a two-letter country code",
		bad_flags.is_empty(), ", ".join(bad_flags))
	h.complete(case)

	# A title covering more than one root becomes one entry with a flag row, and
	# the row needs exactly one flag preselected. Zero leaves the launcher
	# picking arbitrarily; two make the choice depend on iteration order, which
	# is the same fault `debug_keys.gd` reports for two commands on one key.
	case = "a title spanning several roots has exactly one default"
	h.begin(case)
	var grouped := 0
	var bad_defaults: Array[String] = []
	for title in titles:
		var members: Array = titles[title]
		if members.size() < 2:
			continue
		grouped += 1
		var defaults := 0
		for name in members:
			if bool(cfg.get_value("root.%s" % name, "default", false)):
				defaults += 1
		if defaults != 1:
			bad_defaults.append("%s: %d of %d" % [title, defaults, members.size()])
		for name in members:
			if str(cfg.get_value("root.%s" % name, "flag", "")) == "":
				bad_defaults.append("%s: %s carries no flag" % [title, name])
	h.check("there is a title spanning several roots to check", grouped > 0,
		"%d grouped title(s)" % grouped)
	h.check("each names exactly one default and every member carries a flag",
		bad_defaults.is_empty(), ", ".join(bad_defaults))
	h.complete(case)

	print("")
	var names: Array = titles.keys()
	names.sort()
	for title in names:
		print("  %-16s %s" % [title, ", ".join(titles[title])])
	quit(h.finish("the title mapping"))


static func _is_country_code(code: String) -> bool:
	if code.length() != 2:
		return false
	for i in 2:
		var point := code.to_lower().unicode_at(i)
		if point < "a".unicode_at(0) or point > "z".unicode_at(0):
			return false
	return true
```

- [ ] **Step 2: Run it to verify it fails**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --headless --path . --script tools/title_mapping.gd`

Expected: `FAIL` — "every root under games/ has a `[root.<name>]` section" lists all six, and the grouped-title case fails with `0 grouped title(s)`.

- [ ] **Step 3: Add the sections to `director_game.cfg`**

Append to the end of `director_game.cfg`:

```ini
; Which titles exist, and what the launcher needs to offer them.
;
; One section per directory under `games/`. `tools/title_mapping.gd` asserts
; that the two lists match, so a title added to the repository fails as a named
; regression rather than as a menu entry that boots nothing.
;
; `boot` is a mapping and not a probe because the probe is wrong. "mainmenu.dir
; if it is there, else strtgame.dir" picks the wrong container for
; `piposh-dream`, which ships both at its root and boots strtgame.dir; three
; more carry a MAINMENU.dir one directory down that any looser search finds.
; Names are matched case-insensitively by `DirectorPaths.resolve`, so the
; lower-case spellings here find `STRTGAME.dir` and `MAINMENU.dir` on disc.
;
; Roots sharing a `title` collapse into one entry in the game list with a row of
; flags under it, and `default = true` is the one preselected. `flag` is a
; country code; the launcher composes the two regional-indicator code points
; from it, so 🇮🇱 needs no image asset. A title with one root needs neither key.
;
; `[game] boot_movie` above still wins, as does `--boot`. This only answers
; "what does this root boot when nobody has said otherwise".

[root.piposh]
title = "Piposh"
boot = "strtgame.dir"
flag = "il"
default = true

[root.piposh-en]
title = "Piposh"
boot = "strtgame.dir"
flag = "us"

[root.piposh-ru]
title = "Piposh"
boot = "strtgame.dir"
flag = "ru"

[root.piposh2]
title = "Piposh 2"
boot = "strtgame.dir"

[root.piposh-dream]
title = "Piposh Dream"
boot = "strtgame.dir"

[root.rating]
title = "Rating"
boot = "mainmenu.dir"
```

- [ ] **Step 4: Run it to verify it passes**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --headless --path . --script tools/title_mapping.gd`

Expected: `PASS` with 6 checks, and a printed list ending `Piposh  piposh, piposh-en, piposh-ru`.

- [ ] **Step 5: Add to the gate, correct the count, run it**

Add `title_mapping` to `ALL` in `gate.sh:93` after `game_config`, and change the recorded set in the header from 63 to 64.

Run: `bash gate.sh`

Expected: 64 `PASS`, 0 `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add director_game.cfg tools/title_mapping.gd gate.sh
git commit -m "config: describe the six titles, and gate the description

One [root.<name>] section per directory under games/: which title it belongs
to, what it boots, which flag stands for it. A mapping rather than a probe
because the probe is wrong -- piposh-dream ships both mainmenu.dir and
STRTGAME.dir at its root and boots the second.

tools/title_mapping.gd asserts the config and the disc agree, so adding a
title fails as a red line instead of as a menu entry that boots nothing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The launcher scene, the Player tab, and `main_scene`

**Files:**
- Create: `scenes/launcher/launcher.tscn`, `scenes/launcher/launcher.gd`, `scenes/launcher/title_list.gd`
- Modify: `project.godot:19` (`run/main_scene`), `autoload/audio_director.gd` (add `reset_index`)

**Interfaces:**
- Consumes: `GameConfig.merged()`, `GameConfig.overlay()`, `GameConfig.write_overlay(cfg)` from Task 1; the `[root.*]` schema from Task 3; `KeySites.roots()`.
- Produces:
  - `TitleList.build() -> Array[Dictionary]` — one entry per title, each `{"title": String, "roots": Array[Dictionary]}` where a root is `{"name": String, "root": String, "boot": String, "flag": String, "default": bool}`. Roots keep the order `KeySites.roots()` gives, which is sorted.
  - `TitleList.flag_emoji(code: String) -> String` — `"il"` to `"🇮🇱"`, `""` for a code that is not two ASCII letters.
  - `Launcher.play()` — writes the overlay and calls `get_tree().change_scene_to_file("res://scenes/director_preview.tscn")`.

- [ ] **Step 1: Write `title_list.gd`, the part that has no UI in it**

Create `scenes/launcher/title_list.gd`:

```gdscript
extends RefCounted
## The launcher's game list, built from `[root.*]` and what is on disc.
##
## Separated from the scene because it is the half that can be measured: it
## takes a config and a list of directories and returns rows, and
## `tools/title_mapping.gd` already asserts the two agree. The scene turns rows
## into buttons and does nothing else.

const GameConfig := preload("res://director/game_config.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")

## `flag = "il"` becomes 🇮🇱. The regional indicators are the ASCII letters
## offset into their own block, so the config carries a country code a person
## can read rather than a pair of code points they cannot.
const REGIONAL_INDICATOR_A := 0x1F1E6


## One entry per title, in sorted-root order. A title covering several roots
## carries them all; the caller shows a flag row only when there is more than
## one.
static func build(cfg: ConfigFile = null) -> Array[Dictionary]:
	var config := cfg if cfg != null else GameConfig.merged()
	var out: Array[Dictionary] = []
	var index: Dictionary = {}
	for path in KeySites.roots():
		var name := str(path).get_file()
		var section := "root.%s" % name
		# A root with no section is still offered, under its directory name and
		# with no boot container. Guessing one is what produces a menu entry
		# that loads no score and asserts over nothing; saying so is honest, and
		# `tools/title_mapping.gd` means this state lasts as long as it takes to
		# describe the title.
		var title := str(config.get_value(section, "title", name))
		var row := {
			"name": name,
			"root": path,
			"boot": str(config.get_value(section, "boot", "")),
			"flag": str(config.get_value(section, "flag", "")),
			"default": bool(config.get_value(section, "default", false)),
		}
		if not index.has(title):
			index[title] = out.size()
			out.append({"title": title, "roots": [] as Array[Dictionary]})
		(out[int(index[title])]["roots"] as Array).append(row)
	return out


## The root a title opens on: the one marked `default`, else the first.
static func default_root(entry: Dictionary) -> Dictionary:
	var roots: Array = entry.get("roots", [])
	for row in roots:
		if bool((row as Dictionary).get("default", false)):
			return row
	return roots[0] if not roots.is_empty() else {}


static func flag_emoji(code: String) -> String:
	if code.length() != 2:
		return ""
	var out := ""
	for i in 2:
		var point := code.to_lower().unicode_at(i)
		if point < "a".unicode_at(0) or point > "z".unicode_at(0):
			return ""
		out += String.chr(REGIONAL_INDICATOR_A + point - "a".unicode_at(0))
	return out
```

- [ ] **Step 2: Write `launcher.gd`**

Create `scenes/launcher/launcher.gd`:

```gdscript
extends Control
## The screen that picks a game, before anything is loaded.
##
## It writes `user://director_game.local.cfg` and never the tracked file. That
## is the whole point: `director_game.cfg` is tracked, so a screen that edited
## it in place would produce exactly the merge conflicts it exists to remove --
## and in an export it could not, because `res://` is inside the PCK.
##
## **A run that names a game on the command line plays straight through.**
## `director_paths.gd` documents `godot --path . -- --save <file>` as sufficient
## on its own, and a menu in front of it breaks that. A bare run shows the menu,
## and an Android run -- which has no argv -- always does.

const GameConfig := preload("res://director/game_config.gd")
const TitleList := preload("res://scenes/launcher/title_list.gd")

const PREVIEW_SCENE := "res://scenes/director_preview.tscn"

## Emoji are not in the project's font. `Open Sans SemiBold` carries Hebrew and
## Cyrillic but no emoji block at all, measured with `has_char` on 4.7.1, so a
## flag label needs the platform's emoji font as a fallback. A platform whose
## emoji font declines regional-indicator pairs -- Windows does -- draws the two
## letters instead, which is `IL`, `US`, `RU`: the label a text-only design
## would have picked, so there is nothing to fall back to.
const EMOJI_FONTS := ["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"]

const ASPECTS := ["native_4_3", "wide_16_9", "ultra_21_9", "stretch_fill"]

@onready var _games: OptionButton = %Games
@onready var _flags: HBoxContainer = %Flags
@onready var _aspect: OptionButton = %Aspect
@onready var _play: Button = %Play

var _entries: Array[Dictionary] = []
var _root := ""
var _boot := ""


func _ready() -> void:
	if _named_on_command_line():
		_launch()
		return
	_entries = TitleList.build()
	_fill_games()
	_fill_aspect()
	_games.item_selected.connect(_on_game_selected)
	_play.pressed.connect(_on_play)
	if _entries.size() > 0:
		_on_game_selected(_games.selected)


## `--root`, `--boot` and `--save` each name a game, and each is meant to be
## sufficient without a menu.
func _named_on_command_line() -> bool:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		for flag in ["--root", "--boot", "--save"]:
			if text == flag or text.begins_with(flag + "="):
				return true
	return false


func _fill_games() -> void:
	_games.clear()
	for entry in _entries:
		_games.add_item(str(entry["title"]))
	# One game is not a choice. A single-title build shows no list at all, which
	# is what lets an Android export carry one game without a decision here.
	_games.visible = _entries.size() > 1
	_games.selected = 0


func _fill_aspect() -> void:
	_aspect.clear()
	for name in ASPECTS:
		_aspect.add_item(str(name).replace("_", " "))
	var current := str(GameConfig.merged().get_value("display", "aspect", "native_4_3"))
	_aspect.selected = maxi(ASPECTS.find(current), 0)


func _on_game_selected(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry := _entries[index]
	_build_flags(entry)
	_select_root(TitleList.default_root(entry))


## A row of flags, and only for a title that has more than one root. Piposh is
## the one title in six with localisations; the other three show nothing here.
func _build_flags(entry: Dictionary) -> void:
	for child in _flags.get_children():
		child.queue_free()
	var roots: Array = entry.get("roots", [])
	_flags.visible = roots.size() > 1
	if roots.size() < 2:
		return
	var group := ButtonGroup.new()
	for row in roots:
		var data := row as Dictionary
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = TitleList.flag_emoji(str(data.get("flag", "")))
		button.tooltip_text = str(data.get("name", ""))
		button.custom_minimum_size = Vector2(64, 64)
		button.add_theme_font_override("font", _emoji_font())
		button.add_theme_font_size_override("font_size", 32)
		button.button_pressed = bool(data.get("default", false))
		button.pressed.connect(_select_root.bind(data))
		_flags.add_child(button)


func _emoji_font() -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(EMOJI_FONTS)
	var base := FontVariation.new()
	base.base_font = ThemeDB.fallback_font
	base.fallbacks = [system] as Array[Font]
	return base


func _select_root(row: Dictionary) -> void:
	_root = str(row.get("root", ""))
	_boot = str(row.get("boot", ""))
	_refresh_play()


## The single owner of `Play`'s enabled state.
##
## One function and not two, because Task 6 adds a second reason to refuse --
## a binding that failed validation -- and two writers on one property means
## whichever ran last decides. That is the same fault `debug_keys.gd` reports
## for two commands on one key, in a place nothing would report it.
func _refresh_play() -> void:
	if _root == "":
		_play.disabled = true
		_play.text = "No game selected"
		return
	if _boot == "":
		_play.disabled = true
		_play.text = "No boot movie — set one in Developer"
		return
	_play.disabled = false
	_play.text = "Play"


func _on_play() -> void:
	var overlay := GameConfig.overlay()
	overlay.set_value("game", "root", _root)
	overlay.set_value("game", "boot_movie", _boot)
	overlay.set_value("display", "aspect", ASPECTS[maxi(_aspect.selected, 0)])
	GameConfig.write_overlay(overlay)
	_redrive_autoloads()
	_launch()


## Autoloads read the config once, at process start, and survive a scene change.
##
## **This is `director_paths.gd`'s `--root` lesson arriving through a new door.**
## That comment records what happens when the movies move and something that
## cached the old root does not: `AudioDirector` indexed its sounds against the
## previous title and every lookup missed, so the game ran silent. The launcher
## changes the root *after* every autoload has already started, which is the
## same situation reached a different way.
##
## `AudioDirector` happens to survive it today -- `audio_director.gd:96` defers
## the index to the first `resolve_path`, which is after the preview has loaded
## -- but that is an implementation detail of one file and `_indexed` is a
## one-shot latch, so anything that touches audio before Play would poison it.
## `AppSettings` does not survive it at all: its `_ready` calls `load_settings`
## eagerly.
##
## So both are re-driven explicitly rather than relying on which one is lazy.
## An autoload added later that caches config belongs on this list, and the fact
## that the list exists is what makes that a thing somebody can notice.
func _redrive_autoloads() -> void:
	AppSettings.load_settings()
	AudioDirector.reset_index()


func _launch() -> void:
	# Deferred rather than immediate. `_launch` is reached from `_ready` on the
	# command-line bypass path, and changing scene from inside the current
	# scene's `_ready` is the standard way to free a node that is mid-
	# initialisation.
	get_tree().change_scene_to_file.call_deferred(PREVIEW_SCENE)
```

- [ ] **Step 3: Build the scene**

Create `scenes/launcher/launcher.tscn` with this node tree, script `launcher.gd` on the root, and **Access as Unique Name** (the `%` prefix) set on `Games`, `Flags`, `Aspect` and `Play`:

```
Launcher (Control, anchors full rect, script launcher.gd)
└── Margin (MarginContainer, 32px on all four sides, anchors full rect)
    └── Tabs (TabContainer)
        └── Player (VBoxContainer, theme_override_constants/separation = 16)
            ├── GamesLabel (Label, text "Game")
            ├── Games (OptionButton, custom_minimum_size 0x56)      %
            ├── Flags (HBoxContainer, separation 16)                %
            ├── AspectLabel (Label, text "Aspect")
            ├── Aspect (OptionButton, custom_minimum_size 0x56)     %
            ├── Spacer (Control, size_flags_vertical = Expand)
            └── Play (Button, text "Play", custom_minimum_size 0x72) %
```

The 56px and 72px minimum heights are the touch sizing: Android is the export preset, and a default-height `OptionButton` is about 31px, which is under every finger-target guideline.

- [ ] **Step 4: Give `AudioDirector` a way to forget its index**

In `autoload/audio_director.gd`, beside `_ensure_index` (line 120):

```gdscript
## Drop the index so the next lookup rebuilds it against the current config.
##
## The launcher changes the root after this autoload has already started, and
## `_indexed` is a one-shot latch: without this, anything that had touched audio
## before Play would leave the index pointing at the previous title and every
## lookup would miss. That is the silent game `director_paths.gd` documents,
## reached through a different door.
func reset_index() -> void:
	_indexed = false
```

- [ ] **Step 5: Point `main_scene` at it**

In `project.godot`, change line 19:

```ini
run/main_scene="res://scenes/launcher/launcher.tscn"
```

This is safe to change and that was verified rather than assumed: `gate.sh:156` and `check.sh:16` both run `--script tools/<name>.gd`, and the three child processes spawned from inside harnesses (`save_state.gd:466`, `save_movie.gd:232`, `text_codepage.gd:461`) each pass `--headless --script`. Nothing in the repository boots the main scene.

- [ ] **Step 6: Verify the flag row renders, by eye**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --path .`

Expected: the launcher opens. The game dropdown lists **Piposh, Piposh 2, Piposh Dream, Rating** — four entries for six roots. Selecting **Piposh** shows three flag buttons; on macOS they are 🇮🇱 🇺🇸 🇷🇺 with the Israeli flag pressed. Selecting **Rating** hides the row.

- [ ] **Step 7: Verify a game *change* — not just a launch**

First check what the tracked config currently names: `grep '^root' director_game.cfg`. Then launch and pick **a different title**, and press Play.

Expected: that title loads **with sound**. This is the case that can fail and the one picking the already-configured game cannot: every autoload started before you pressed Play, and `AudioDirector` indexing against the previous root is the silent game `director_paths.gd:54-62` was written about. If it is silent, `reset_index` is not being called or is not being called before the first lookup.

- [ ] **Step 8: Verify the flag bypass**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --path . -- --root piposh2 --boot strtgame.dir`

Expected: no menu. Piposh 2 boots directly.

- [ ] **Step 9: Verify the overlay was written and the gate is untouched**

Run: `cat "$(. ./gate_env.sh; echo)$HOME/Library/Application Support/Godot/app_userdata/Godot Director Player/director_game.local.cfg"` — or on any platform, print `OS.get_user_data_dir()` from the running game.

Expected: a `[game]` section naming whichever root you pressed Play on, and a `[display] aspect`. Then `git status --short director_game.cfg` shows **no** modification: the tracked file was not written.

Run: `bash gate.sh`

Expected: 64 `PASS`, 0 `FAIL` — unchanged, because every harness is headless and skips the overlay you just wrote.

- [ ] **Step 10: Commit**

```bash
git add scenes/launcher project.godot autoload/audio_director.gd
git commit -m "launcher: a main screen that picks the game, writing the overlay

Four titles for six roots -- Piposh's three localisations collapse into one
entry with a flag row, IL default. The flags are emoji composed from the
config's country code with a SystemFont fallback: Open Sans SemiBold has
Hebrew and Cyrillic but no emoji block, measured on 4.7.1, and a platform
that declines regional-indicator pairs draws IL/US/RU, which is the label a
text design would have chosen anyway.

main_scene is safe to move: gate.sh, check.sh and all three child processes
run --script, so nothing in the repo boots it.

--root, --boot or --save on the line plays straight through, which keeps
`godot --path . -- --save <file>` sufficient on its own.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The Developer tab

**Files:**
- Modify: `scenes/launcher/launcher.tscn` (a second tab), `scenes/launcher/launcher.gd`

**Interfaces:**
- Consumes: `GameConfig.tracked()` and `GameConfig.overlay()` from Task 1; `DebugKeys.ON`/`OFF`/`AUTO` from `scenes/preview/debug_keys.gd`.
- Produces: `Launcher._developer_visible() -> bool` — reads the **tracked** switch plus `--debug-ui`, never the merged value.

- [ ] **Step 1: Add the visibility gate**

In `scenes/launcher/launcher.gd`, add the preload and the function:

```gdscript
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")

## Whether the developer tab is there at all.
##
## **From the tracked file, never from the merged value**, and that is a
## deliberate exception to `debug_keys.gd`'s one-answer-per-process rule. The
## tab contains the control that sets `[debug] enabled`, so a tab whose
## visibility read the overlay would close the door behind itself: set it false
## and the control that would set it back is gone. `--debug-ui on` recovers that
## on a desktop; Android has no command line and is the only export preset, so
## there the only way back would be clearing the app's data.
##
## The overlay may still turn the debug *layer* off -- the bindings, the boxes,
## the HUD. It just cannot hide its own door.
func _developer_visible() -> bool:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--debug-ui="):
			return text.substr(11).strip_edges().to_lower() in ["on", "true", "1", "yes"]
	var wanted := str(GameConfig.tracked().get_value("debug", "enabled", DebugKeys.AUTO))
	match wanted.strip_edges().to_lower():
		DebugKeys.OFF, "off", "0", "no":
			return false
		DebugKeys.ON, "on", "1", "yes":
			return true
	return OS.is_debug_build()
```

- [ ] **Step 2: Add the tab and its controls**

Add a second child to `Tabs` in `scenes/launcher/launcher.tscn`:

```
Developer (VBoxContainer, separation 16)
└── Scroll (ScrollContainer, size_flags_vertical = Expand)
    └── Fields (VBoxContainer, separation 16)
        ├── BootLabel (Label, text "Boot movie override")
        ├── Boot (LineEdit, custom_minimum_size 0x56)          %
        ├── CodepageLabel (Label, text "Codepage")
        ├── Codepage (OptionButton, custom_minimum_size 0x56)  %
        ├── DebugLabel (Label, text "Debug layer")
        └── Debug (OptionButton, custom_minimum_size 0x56)     %
```

In `_ready`, after `_fill_aspect()`:

```gdscript
	var tabs := %Tabs as TabContainer
	var developer := %Developer as Control
	developer.visible = _developer_visible()
	tabs.set_tab_hidden(developer.get_index(), not developer.visible)
	if developer.visible:
		_fill_developer()
```

And the filler, using the merged values because these are what the run will actually use:

```gdscript
const CODEPAGES = ["", "mac_hebrew", "windows_1255"]
const DEBUG_VALUES = [DebugKeys.AUTO, DebugKeys.ON, DebugKeys.OFF]

func _fill_developer() -> void:
	var cfg := GameConfig.merged()
	%Boot.text = str(cfg.get_value("game", "boot_movie", ""))
	%Boot.placeholder_text = "empty: whatever the chosen game boots"
	%Codepage.clear()
	for name in CODEPAGES:
		%Codepage.add_item("engine default (bytes as code points)" if name == "" else name)
	%Codepage.selected = maxi(CODEPAGES.find(str(cfg.get_value("game", "codepage", ""))), 0)
	%Debug.clear()
	for name in DEBUG_VALUES:
		%Debug.add_item(name)
	%Debug.selected = maxi(DEBUG_VALUES.find(
		str(cfg.get_value("debug", "enabled", DebugKeys.AUTO)).strip_edges().to_lower()), 0)
```

- [ ] **Step 3: Write these three into the overlay on Play**

In `_on_play`, before `GameConfig.write_overlay(overlay)`:

```gdscript
	if _developer_visible():
		# An empty boot override means "whatever the chosen game boots", which is
		# a different statement from the empty string: the key is removed rather
		# than written blank, or `DirectorPaths.load_config` reads "" and reports
		# no game configured.
		var override := str(%Boot.text).strip_edges()
		if override != "":
			overlay.set_value("game", "boot_movie", override)
		var codepage := str(CODEPAGES[maxi(%Codepage.selected, 0)])
		if codepage != "":
			overlay.set_value("game", "codepage", codepage)
		elif overlay.has_section_key("game", "codepage"):
			overlay.erase_section_key("game", "codepage")
		overlay.set_value("debug", "enabled", DEBUG_VALUES[maxi(%Debug.selected, 0)])
```

Note the ordering: `_on_play` already wrote `boot_movie` from the chosen title, so the override lands on top of it, which is the precedence the spec states.

- [ ] **Step 4: Verify the tab appears, and that it cannot lock you out**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --path .`

Expected: the Developer tab is present (this is a run from source, and the tracked file says `auto`). Set **Debug layer** to `false`, press Play, quit, and run again.

Expected: the Developer tab is **still there** — its visibility came from the tracked `auto`, not from the `false` you just wrote — while the debug layer itself is off (F1 draws no boxes, F12 opens no picker). Set it back to `auto` and confirm the keys return.

- [ ] **Step 5: Verify the gate is untouched**

Run: `bash gate.sh`

Expected: 64 `PASS`, 0 `FAIL`. The `debug_bindings` entry in particular must still pass — it re-reads `DebugKeys.CONFIG_PATH` with its own `ConfigFile` to assert the shipped value is `auto`, and the overlay you wrote is invisible to it twice over.

- [ ] **Step 6: Commit**

```bash
git add scenes/launcher
git commit -m "launcher: a developer tab, gated on the tracked switch

Boot override, codepage and the debug layer. Visibility reads the *tracked*
[debug] enabled plus --debug-ui and never the merged value: the tab holds the
control that sets it, so reading the overlay would let it close the door
behind itself -- and on Android, the only export preset, there is no command
line to reopen it with.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The keybinding editor and its three validators

**Files:**
- Create: `scenes/launcher/binding_rules.gd`, `tools/launcher_keys.gd`
- Modify: `scenes/launcher/launcher.tscn` (a bindings section in the Developer tab), `scenes/launcher/launcher.gd`
- Modify: `gate.sh:93` (`ALL`), `gate.sh:2-6` (the count)

**Interfaces:**
- Consumes: `DebugKeys.DEFAULTS: Dictionary`, `DebugKeys.SETTINGS: Dictionary`; `KeySites.for_root(root) -> Dictionary` (whose `"codes"` key is `{mac_code: Array}`) and `KeySites.roots()`.
- Produces:
  - `BindingRules.named(name: String) -> int` — the keycode, or `KEY_NONE`.
  - `BindingRules.collision(bindings: Dictionary, command: String, name: String) -> String` — the command already on that key, or `""`.
  - `BindingRules.measure() -> void` — reads every root's scripts once per process and caches both tables.
  - `BindingRules.tested_codes() -> Dictionary` — Mac code to the roots that test it.
  - `BindingRules.tested_chars() -> Dictionary` — lower-cased character to the roots that test it.
  - `BindingRules.claimed_by(name: String) -> Array[String]` — roots whose scripts test that **keyCode**, `[]` when free.
  - `BindingRules.typed_in(name: String) -> Array[String]` — roots whose scripts test the **character** that key types, `[]` when it types none or none test it.

**Both halves, not one.** `tools/debug_bindings.gd:145-155` asserts two rules per binding — the key is not a `keyCode` any title tests, *and* it types no character any title tests. `director_game.cfg:95-97` states the predicate the F-key band was only ever a proxy for in exactly those two clauses. A launcher enforcing only the first would happily accept `S`, which types a character this corpus tests.

- [ ] **Step 1: Write the failing harness**

Create `tools/launcher_keys.gd`:

```gdscript
extends SceneTree
## What the launcher refuses to store as a preview binding.
##
##   godot --headless --path . --script tools/launcher_keys.gd
##
## `DebugKeys.load_config` answers a bad binding with `push_warning`, and a
## warning in a log is not a UI. It is less than that here: the overlay is not
## read at all in a headless process, so **no gate ever sees what the launcher
## writes**. The checks have to be in the editor, and this is what asserts they
## are the same checks.
##
## The third is the one that matters and the one a constant gets wrong. The
## preview shares a keyboard with the movie, and Director gave the movie all of
## it, so "is this key free" is a question about the *games* -- answered by
## reading their scripts, over every root, exactly as `tools/debug_bindings.gd`
## does. `tools/lib/key_sites.gd` records what happened last time that answer
## lived in a list: it was swept from `reference/lingo/`, which holds one title
## of six, and put the pause on F10, which Rating tests at 48 sites.

const Harness := preload("res://tools/lib/harness.gd")
const BindingRules := preload("res://scenes/launcher/binding_rules.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")


func _init() -> void:
	var h := Harness.new()

	var case := "a name that is not a key is refused"
	h.begin(case)
	h.check("'F5' is a key", BindingRules.named("F5") != KEY_NONE)
	h.check("'Shift+F5' is a key", BindingRules.named("Shift+F5") != KEY_NONE)
	h.check("'Banana' is not", BindingRules.named("Banana") == KEY_NONE)
	h.check("'' is not", BindingRules.named("") == KEY_NONE)
	h.complete(case)

	case = "two commands on one key is refused"
	h.begin(case)
	var bindings := {"step_back": "F5", "step_forward": "F6"}
	h.check("F6 collides with step_forward",
		BindingRules.collision(bindings, "step_back", "F6") == "step_forward",
		BindingRules.collision(bindings, "step_back", "F6"))
	h.check("F7 collides with nothing",
		BindingRules.collision(bindings, "step_back", "F7") == "")
	# Rebinding a command to the key it already holds is not a collision with
	# itself, or no binding could ever be re-saved unchanged.
	h.check("a command does not collide with itself",
		BindingRules.collision(bindings, "step_back", "F5") == "")
	h.complete(case)

	case = "a key some title's scripts test is refused"
	h.begin(case)
	var tested := BindingRules.tested_codes()
	if not h.check("the corpus yields tested key codes", not tested.is_empty(),
			"%d code(s)" % tested.size()):
		h.complete(case)
		quit(h.finish("what the launcher refuses to bind"))
		return
	# F10 is Mac code 109 and Rating tests it at 48 sites. It is the reason the
	# pause is on F9, and it is the case a hand-written list got wrong.
	h.check("F10 is claimed", not BindingRules.claimed_by("F10").is_empty(),
		", ".join(BindingRules.claimed_by("F10")))
	h.check("Escape is claimed", not BindingRules.claimed_by("Escape").is_empty(),
		", ".join(BindingRules.claimed_by("Escape")))
	h.check("PageDown is free", BindingRules.claimed_by("PageDown").is_empty(),
		", ".join(BindingRules.claimed_by("PageDown")))
	h.complete(case)

	# The second half of the rule. `director_game.cfg` states the predicate as
	# "types no character *and* is a key no title is measured to test", and
	# `tools/debug_bindings.gd` asserts both per binding. A launcher checking
	# only the keyCode accepts a plain letter.
	case = "a key that types a character some title tests is refused"
	h.begin(case)
	var chars := BindingRules.tested_chars()
	if not h.check("the corpus yields tested characters", not chars.is_empty(),
			"%d character(s)" % chars.size()):
		h.complete(case)
		quit(h.finish("what the launcher refuses to bind"))
		return
	h.check("F9 types nothing", BindingRules.typed_in("F9").is_empty(),
		", ".join(BindingRules.typed_in("F9")))
	h.check("PageDown types nothing", BindingRules.typed_in("PageDown").is_empty(),
		", ".join(BindingRules.typed_in("PageDown")))
	# `fromnow` turns Space into "skip this line of speech" in 46 scripts, which
	# is why the pause moved off it long before the rest of the band existed.
	h.check("Space is claimed by what it types",
		not BindingRules.typed_in("Space").is_empty(),
		", ".join(BindingRules.typed_in("Space")))
	h.complete(case)

	# And the shipped map has to survive both halves, or the launcher would
	# refuse to store the bindings the port ships with.
	case = "every shipped binding passes the rules the launcher enforces"
	h.begin(case)
	var refused: Array[String] = []
	for command in DebugKeys.DEFAULTS:
		var name := str(DebugKeys.DEFAULTS[command])
		if name == "":
			continue
		if not BindingRules.claimed_by(name).is_empty():
			refused.append("%s on %s: keyCode tested by %s"
				% [command, name, ", ".join(BindingRules.claimed_by(name))])
		if not BindingRules.typed_in(name).is_empty():
			refused.append("%s on %s: types a character tested by %s"
				% [command, name, ", ".join(BindingRules.typed_in(name))])
	h.check("all %d shipped binding(s) pass" % DebugKeys.DEFAULTS.size(),
		refused.is_empty(), "; ".join(refused))
	h.complete(case)

	quit(h.finish("what the launcher refuses to bind"))
```

- [ ] **Step 2: Run it to verify it fails**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --headless --path . --script tools/launcher_keys.gd`

Expected: FAIL — `res://scenes/launcher/binding_rules.gd` does not exist, so the `preload` is a parse error.

- [ ] **Step 3: Write `binding_rules.gd`**

Create `scenes/launcher/binding_rules.gd`:

```gdscript
extends RefCounted
## The three things a preview binding has to be, asked before it is stored.
##
## In the launcher and not in `DebugKeys` because `DebugKeys` is the *reader*:
## by the time it warns, the value is already in a file. And with the overlay
## invisible to a headless process, nothing in `gate.sh` will ever look at what
## the launcher wrote -- so the editor is the last place these can be asked.
## `tools/launcher_keys.gd` asserts they are the same questions
## `tools/debug_bindings.gd` asks of the tracked file.

const KeySites := preload("res://tools/lib/key_sites.gd")
const Keys := preload("res://director/director_keys.gd")

static var _codes: Dictionary = {}
static var _chars: Dictionary = {}
static var _measured := false


## The keycode a name means, or `KEY_NONE`. Godot round-trips `"Shift+F5"` to
## `KEY_MASK_SHIFT | KEY_F5` and back, so the chords need nothing special.
static func named(name: String) -> int:
	var wanted := name.strip_edges()
	if wanted == "":
		return KEY_NONE
	return OS.find_keycode_from_string(wanted)


## The command already sitting on `name`, or `""`. A command does not collide
## with itself, or a map could never be saved unchanged.
##
## `debug_keys.gd` warns about this and then drops one of the two, and which one
## survives depends on iteration order -- so the command that silently never
## runs is not even stable between runs.
static func collision(bindings: Dictionary, command: String, name: String) -> String:
	var code := named(name)
	if code == KEY_NONE:
		return ""
	for other in bindings:
		if str(other) == command:
			continue
		if named(str(bindings[other])) == code:
			return str(other)
	return ""


## Read every root's scripts, once per process.
##
## Measured from the games rather than listed, because a binding is safe or
## unsafe for the whole engine and not for whichever title the config happens to
## be pointed at. A cast parse per container, seconds per title over six titles,
## so the caller shows a status line the first time the bindings section opens.
static func measure() -> void:
	if _measured:
		return
	_measured = true
	for root in KeySites.roots():
		var title := str(root).get_file()
		var sites: Dictionary = KeySites.for_root(str(root))
		for code in sites.get("codes", {}):
			var key := int(code)
			if not _codes.has(key):
				_codes[key] = [] as Array[String]
			(_codes[key] as Array).append(title)
		for typed in sites.get("chars", {}):
			var text := str(typed).to_lower()
			if not _chars.has(text):
				_chars[text] = [] as Array[String]
			(_chars[text] as Array).append(title)


static func tested_codes() -> Dictionary:
	measure()
	return _codes


static func tested_chars() -> Dictionary:
	measure()
	return _chars


## The roots that test `name` as a **keyCode**, `[]` when none do.
static func claimed_by(name: String) -> Array[String]:
	var event := _event(name)
	if event == null:
		return [] as Array[String]
	var mac := Keys.code_for(event)
	# -1 is `code_for`'s "unmapped", and 0 is the `A` key -- the distinction is
	# the reason it answers -1 rather than 0, so an unmapped key must not be
	# looked up as if it were a press of A.
	if mac < 0:
		return [] as Array[String]
	return tested_codes().get(mac, [] as Array[String])


## The roots that test the **character** `name` types, `[]` when it types none.
##
## The second half of the rule, and not optional: `director_game.cfg` states the
## predicate as "types no character and is a key no title is measured to test",
## and `tools/debug_bindings.gd` asserts both per binding. Checking only the
## keyCode accepts `S`, which types a character this corpus tests.
static func typed_in(name: String) -> Array[String]:
	var event := _event(name)
	if event == null:
		return [] as Array[String]
	var typed := Keys.char_for(event).to_lower()
	if typed == "":
		return [] as Array[String]
	return tested_chars().get(typed, [] as Array[String])


## The `InputEventKey` a name means, or `null`.
##
## Copied from `tools/debug_bindings.gd:77-85` rather than reinvented, so the
## launcher asks the question in exactly the shape the gate asks it. `keycode`
## is masked with `KEY_CODE_MASK`, which drops the modifier: Mac key codes carry
## none, so a chord's risk against a title is exactly its base key's -- Shift+F1
## is as safe as F1, which the gate measures rather than assumes.
static func _event(name: String) -> InputEventKey:
	var code := named(name)
	if code == KEY_NONE:
		return null
	var event := InputEventKey.new()
	event.keycode = (code & KEY_CODE_MASK) as Key
	event.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	event.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	event.alt_pressed = (code & KEY_MASK_ALT) != 0
	event.meta_pressed = (code & KEY_MASK_META) != 0
	event.pressed = true
	return event
```

`Keys.code_for(event)` and `Keys.char_for(event)` are the real signatures in `director/director_keys.gd:71` and `:91`, and `_event` is `tools/debug_bindings.gd:77-85`'s `_key` helper with the `null` case added. Nothing here needs looking up.

- [ ] **Step 4: Run it to verify it passes**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --headless --path . --script tools/launcher_keys.gd`

Expected: `PASS` with 18 checks. This one takes tens of seconds — it parses casts across all six titles.

- [ ] **Step 5: Add the bindings section to the Developer tab**

Append to `Fields` in `scenes/launcher/launcher.tscn`:

```
├── BindingsButton (Button, text "Edit preview keys…", custom_minimum_size 0x56)  %
├── BindingsStatus (Label, text "", autowrap_mode = Word)                          %
└── Bindings (VBoxContainer, visible = false)                                      %
```

In `launcher.gd`:

```gdscript
const BindingRules := preload("res://scenes/launcher/binding_rules.gd")

var _binding_fields: Dictionary = {}


func _on_bindings_pressed() -> void:
	if %Bindings.visible:
		return
	# The third check reads every title's scripts, which is seconds. Say so
	# before doing it rather than freezing a button with no explanation.
	%BindingsStatus.text = "Reading what the games test…"
	await get_tree().process_frame
	BindingRules.measure()
	%BindingsStatus.text = ""
	_build_bindings()
	%Bindings.visible = true
	%BindingsButton.disabled = true


func _build_bindings() -> void:
	var cfg := GameConfig.merged()
	for command in DebugKeys.DEFAULTS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(command)
		label.custom_minimum_size = Vector2(220, 0)
		var field := LineEdit.new()
		field.text = str(cfg.get_value("debug", command, DebugKeys.DEFAULTS[command]))
		field.custom_minimum_size = Vector2(180, 56)
		field.placeholder_text = "empty: unbound"
		field.text_changed.connect(_on_binding_changed.bind(str(command)))
		row.add_child(label)
		row.add_child(field)
		_binding_fields[str(command)] = field
		%Bindings.add_child(row)


## The three checks, in the order that gives the most useful message: a name
## that is not a key first, then the key that is already taken, then the key a
## game wants.
func _on_binding_changed(_text: String, command: String) -> void:
	var field := _binding_fields[command] as LineEdit
	var name := str(field.text).strip_edges()
	var problem := ""
	if name == "":
		problem = ""  # Unbinding is legal, and is how a game gets a key back.
	elif BindingRules.named(name) == KEY_NONE:
		problem = "'%s' is not a key name" % name
	else:
		var current: Dictionary = {}
		for other in _binding_fields:
			current[other] = str((_binding_fields[other] as LineEdit).text).strip_edges()
		var clash := BindingRules.collision(current, command, name)
		if clash != "":
			problem = "%s is already on %s" % [clash, name]
		else:
			var claimed := BindingRules.claimed_by(name)
			var typed := BindingRules.typed_in(name)
			if not claimed.is_empty():
				problem = "%s is a keyCode %s tests" % [name, ", ".join(claimed)]
			elif not typed.is_empty():
				problem = "%s types a character %s tests" % [name, ", ".join(typed)]
	field.modulate = Color.WHITE if problem == "" else Color(1.0, 0.55, 0.55)
	%BindingsStatus.text = problem
	_refresh_play()


Extend Task 4's `_refresh_play` — do not add a second writer — so a rejected binding cannot reach the overlay by pressing the other button. Insert this at the top of it, before the `_root` check:

```gdscript
	for command in _binding_fields:
		if (_binding_fields[command] as LineEdit).modulate != Color.WHITE:
			_play.disabled = true
			_play.text = "Fix the highlighted key first"
			return
```

Connect `%BindingsButton.pressed` to `_on_bindings_pressed` in `_ready`, inside the `if developer.visible:` branch.

In `_on_play`, inside the `if _developer_visible():` block, write the bindings:

```gdscript
		for command in _binding_fields:
			overlay.set_value("debug", str(command),
				str((_binding_fields[command] as LineEdit).text).strip_edges())
```

- [ ] **Step 6: Verify by eye**

Run: `. ./gate_env.sh && G=$(gate_find_godot) && "$G" --path .`

Expected: **Edit preview keys…** shows the status line, then fifteen rows. Type into `pause` and watch all three rules fire in turn: `Banana` — "'Banana' is not a key name"; `F1` — "boxes is already on F1"; `F10` — "F10 is a keyCode rating tests"; `S` — "S types a character … tests" (this is the check that only exists because both halves are implemented); `F9` — the field clears and Play returns. The field is red and Play disabled for every one of them.

- [ ] **Step 7: Add to the gate, correct the count, run it**

Add `launcher_keys` to `ALL` in `gate.sh:93`, and change the recorded set from 64 to 65.

Run: `bash gate.sh`

Expected: 65 `PASS`, 0 `FAIL`.

- [ ] **Step 8: Commit**

```bash
git add scenes/launcher tools/launcher_keys.gd gate.sh
git commit -m "launcher: rebind the preview keys, with the checks the gate can no longer make

The overlay is invisible to a headless process, so nothing in gate.sh will
ever see what the launcher writes. The rules move into the editor: a real key
name, no two commands on one key, no key any title tests as a keyCode, and no
key that types a character any title tests. The last two are the predicate
director_game.cfg states and debug_bindings asserts, both halves -- checking
only the keyCode accepts a plain letter. Measured from the games through
key_sites.gd rather than copied into a list, which is how the pause landed on
F10 and Rating tests 109 at 48 sites.

Seconds to measure, so it is computed once behind a status line.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Retire `AppSettings`' own file and its dead fields

**Files:**
- Modify: `autoload/app_settings.gd` (most of it)
- Modify: `scenes/launcher/launcher.tscn`, `scenes/launcher/launcher.gd` (a QoL section)
- Modify: `director_game.cfg` (documented defaults for the surviving keys)

**Interfaces:**
- Consumes: `GameConfig.merged()`, `GameConfig.OVERLAY_PATH` from Task 1.
- Produces: `AppSettings.controller_cursor_speed: float` keeps its name and type — `autoload/input_router.gd:40` reads it and is the only live consumer in the repository.

- [ ] **Step 1: Confirm the consumer list before deleting anything**

Run: `grep -rn "AppSettings\." --include="*.gd" . | grep -v "^./autoload/app_settings.gd"`

Expected: exactly one line, `autoload/input_router.gd:40`. **If it is more than that, stop** — a second consumer appeared since the spec was measured, and the deletions below have to be re-scoped around it.

- [ ] **Step 2: Rewrite `app_settings.gd`**

Replace `autoload/app_settings.gd` with:

```gdscript
extends Node
## The player-facing toggles, read from the same config layer as everything else.
##
## This used to own `user://player_settings.cfg` and a dozen fields, and exactly
## one of them was read anywhere: `controller_cursor_speed`, by
## `autoload/input_router.gd`. The rest were duplicates of live config keys
## (`aspect_mode` against `[display] aspect`, `dev_mode` against `[debug]
## enabled`) or documented orphans of a renderer that was deleted. Two names for
## one question is how a setting starts disagreeing with itself.
##
## **The values below are plumbing, and only `cursor_speed` reaches anything.**
## The rest are read, written and offered by the launcher, and nothing acts on
## them yet -- wiring each to the renderer or the input path is a separate piece
## of work per toggle. The launcher labels them as such, so the first report is
## not "hotspot hints is broken".

const GameConfig := preload("res://director/game_config.gd")

## The file this node used to own. Read once, for one value, then never again.
const RETIRED_PATH := "user://player_settings.cfg"

var upscale_mode: int = 1
var enhanced_graphics: bool = false
var expand_edge_hotspots: bool = true
var show_hotspot_hints: bool = false
var allow_minigame_skip: bool = true
var controller_cursor_speed: float = 420.0
var dev_warp_movie: String = "MURDER1"
var dev_warp_label: String = ""


func _ready() -> void:
	load_settings()


## Re-read every value from the config layer.
##
## Called at start, and again by the launcher after it writes the overlay. That
## second call is not optional: this node reads the config once at process
## start and survives the scene change into the movie, so without it the
## launcher's `cursor_speed` -- the one value here a live consumer reads -- would
## be the pre-launcher one for the whole session. `AudioDirector.reset_index`
## exists beside it for the same reason.
func load_settings() -> void:
	GameConfig.invalidate()
	var cfg := GameConfig.merged()
	upscale_mode = int(cfg.get_value("qol", "upscale_mode", upscale_mode))
	enhanced_graphics = bool(cfg.get_value("qol", "enhanced_graphics", enhanced_graphics))
	expand_edge_hotspots = bool(cfg.get_value("qol", "expand_edge_hotspots", expand_edge_hotspots))
	show_hotspot_hints = bool(cfg.get_value("qol", "hotspot_hints", show_hotspot_hints))
	allow_minigame_skip = bool(cfg.get_value("qol", "minigame_skip", allow_minigame_skip))
	controller_cursor_speed = float(cfg.get_value("qol", "cursor_speed", _migrated_speed()))
	dev_warp_movie = str(cfg.get_value("debug", "warp_movie", dev_warp_movie))
	dev_warp_label = str(cfg.get_value("debug", "warp_label", dev_warp_label))


## The one value with a live consumer, and the one an existing install already
## has on disc. Read out of the retired file when the new layer does not carry
## it; after that the overlay does and this is never consulted again. The old
## file is not deleted -- leaving it costs nothing, and removing a file nobody
## asked us to touch is not ours to do.
func _migrated_speed() -> float:
	var old := ConfigFile.new()
	if old.load(RETIRED_PATH) != OK:
		return controller_cursor_speed
	return float(old.get_value("input", "cursor_speed", controller_cursor_speed))


func stage_scale_factor() -> int:
	return clampi(upscale_mode, 1, 3)


func use_smooth_filter() -> bool:
	return enhanced_graphics
```

Everything else in the old file — `AspectMode`, `UpscaleMode`, `CONFIG_PATH`, `save_settings`, `notify_changed`, `show_press_marks`, `target_aspect`, `aspect_mode_name`, `upscale_mode_name`, `dev_mode`, `use_lingo_clicks`, `use_lingo_frames`, `show_debug_overlays`, `test_mode_enhanced_graphics`, the `settings_changed` signal — is deleted.

- [ ] **Step 3: Verify nothing else referenced what you deleted**

Run: `grep -rn "AppSettings" --include="*.gd" . | grep -v "^./autoload/app_settings.gd"` and `grep -rn "settings_changed\|show_press_marks\|target_aspect\|notify_changed" --include="*.gd" .`

Expected: only `input_router.gd:40` for the first; nothing at all for the second. Fix any hit before continuing.

- [ ] **Step 4: Document the defaults in the tracked config**

Append to `director_game.cfg`:

```ini
; Player-facing toggles.
;
; **Only `cursor_speed` reaches anything today.** The rest are carried through
; the config layer and offered by the launcher, and nothing acts on them yet:
; wiring each to the renderer or the input path is a separate piece of work per
; toggle, and the launcher says so beside them rather than pretending otherwise.
;
; They used to live in `user://player_settings.cfg`, owned by `AppSettings`,
; alongside a second `aspect_mode` that duplicated `[display] aspect` above and
; a `dev_mode` that duplicated `[debug] enabled`. Two names for one question is
; how a setting starts disagreeing with itself; the duplicates are gone and this
; is the one place left.
[qol]
upscale_mode = 1
enhanced_graphics = false
expand_edge_hotspots = true
hotspot_hints = false
minigame_skip = true
cursor_speed = 420.0
```

- [ ] **Step 5: Add the QoL section to the Developer tab**

Append to `Fields` in `scenes/launcher/launcher.tscn`:

```
├── QolHeading (Label, text "Quality of life — stored, not yet wired")
├── HotspotHints (CheckBox, text "Hotspot hints")        %
├── MinigameSkip (CheckBox, text "Allow minigame skip")  %
├── EdgeHotspots (CheckBox, text "Expand edge hotspots") %
├── EnhancedGraphics (CheckBox, text "Enhanced graphics")%
├── CursorSpeedLabel (Label, text "Controller cursor speed")
└── CursorSpeed (HSlider, min 60, max 1200, step 10, custom_minimum_size 0x56) %
```

In `_fill_developer`, seed them:

```gdscript
	%HotspotHints.button_pressed = bool(cfg.get_value("qol", "hotspot_hints", false))
	%MinigameSkip.button_pressed = bool(cfg.get_value("qol", "minigame_skip", true))
	%EdgeHotspots.button_pressed = bool(cfg.get_value("qol", "expand_edge_hotspots", true))
	%EnhancedGraphics.button_pressed = bool(cfg.get_value("qol", "enhanced_graphics", false))
	%CursorSpeed.value = float(cfg.get_value("qol", "cursor_speed", 420.0))
```

And in `_on_play`, inside the `if _developer_visible():` block:

```gdscript
		overlay.set_value("qol", "hotspot_hints", %HotspotHints.button_pressed)
		overlay.set_value("qol", "minigame_skip", %MinigameSkip.button_pressed)
		overlay.set_value("qol", "expand_edge_hotspots", %EdgeHotspots.button_pressed)
		overlay.set_value("qol", "enhanced_graphics", %EnhancedGraphics.button_pressed)
		overlay.set_value("qol", "cursor_speed", float(%CursorSpeed.value))
```

The heading is the important part: a control that stores a value and changes nothing on screen has to say so, or the first report is that it is broken.

- [ ] **Step 6: Verify the migration**

If you have a `user://player_settings.cfg` from an older run, confirm `AppSettings.controller_cursor_speed` still reports its value on a fresh launch before you have touched the slider. If you do not, write one:

```bash
cat > "$HOME/Library/Application Support/Godot/app_userdata/Godot Director Player/player_settings.cfg" <<'EOF'
[input]
cursor_speed=777.0
EOF
```

Then run the game and confirm the slider reads 777. Delete the overlay first if it already carries `cursor_speed`, or the migration correctly does not fire.

Then verify the value actually reaches its consumer **after** a launcher change, which is the half of this that can fail: move the slider to something obvious, press Play, and confirm `AppSettings.controller_cursor_speed` reports the new value from inside the running movie — the launcher's `_redrive_autoloads` calls `load_settings()` for exactly this. Without it the autoload is still holding what it read at process start, before you touched the slider.

- [ ] **Step 7: Run the whole gate**

Run: `bash gate.sh`

Expected: 65 `PASS`, 0 `FAIL`.

- [ ] **Step 8: Commit**

```bash
git add autoload/app_settings.gd director_game.cfg scenes/launcher
git commit -m "settings: one config layer, and the dead duplicates deleted

AppSettings had one live consumer in the whole repo -- cursor_speed, read by
input_router. aspect_mode duplicated [display] aspect; dev_mode and overlays
duplicated [debug] enabled; use_lingo_clicks/frames were documented orphans of
a renderer that is gone. All deleted rather than carried into a new schema.

The survivors move to [qol] and the launcher offers them under a heading
saying they are stored and not yet wired, because that is exactly what they
are. cursor_speed migrates once out of the retired user://player_settings.cfg.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task: the overlay and the merge point to Task 1; the four readers to Task 2; the gate-isolation rule to Task 1 (implementation and its assertion); the title mapping, flag emoji and their gate to Task 3; the launcher, Player tab, `main_scene` and the flag bypass to Task 4; the Developer tab and the tracked-file visibility gate to Task 5; the three validators and their harness to Task 6; the AppSettings deletions, schema move and migration to Task 7. The spec's "What this does not do" section needs no task by construction.

**Naming consistency.** `GameConfig.merged` / `tracked` / `exists` / `invalidate` / `write_overlay` / `overlay` are defined in Task 1 and used under those exact names in Tasks 2, 4, 5 and 7. `TitleList.build` / `default_root` / `flag_emoji` are defined in Task 4 and used only there. `BindingRules.named` / `collision` / `measure` / `tested_codes` / `tested_chars` / `claimed_by` / `typed_in` are defined in Task 6 and asserted under those names in the same task's harness and used under them in its UI. `Keys.code_for` and `Keys.char_for` are the real signatures at `director/director_keys.gd:71` and `:91`. `DebugKeys.load_config(config_path)` and `DirectorPaths.load_config(config_path)` keep their signatures exactly, which `tools/debug_bindings.gd:209` depends on.

**Three corrections made during review**, all from re-reading the code rather than from the draft:

1. **Stale autoloads across the scene change.** Autoloads read the config at process start and survive `change_scene_to_file`, so the launcher changes the root *after* they have already read the old one. `AppSettings._ready` calls `load_settings` eagerly and would have held the pre-launcher `cursor_speed` for the whole session. `AudioDirector` survives it only by accident — `audio_director.gd:96-106` defers its index to the first `resolve_path`, and `_indexed` is a one-shot latch that anything touching audio before Play would poison. Both are now re-driven explicitly in `_redrive_autoloads`, and Task 4 Step 7 verifies a game *change* rather than a launch, because picking the already-configured title is the one case that cannot fail. This is `director_paths.gd:54-62`'s silent game reached through a new door.
2. **The `game_config` harness clobbered the real overlay.** It has to write `user://director_game.local.cfg` — the rule under test is about that exact path — but the draft then deleted it. `bash gate.sh` is the command this repo runs constantly, so that would have wiped a human's launcher settings from the gate. It now reads the file back first and restores it, and asserts that it did.
3. **The first draft of Task 6 checked only that a key is not a `keyCode` some title tests.** `director_game.cfg:95-97` states the rule in two clauses and `tools/debug_bindings.gd:145-155` asserts both — the key must also type no character any title tests. Half the rule would have let the launcher accept a plain letter, which is the exact class of binding the F-key band exists to prevent. `typed_in` and its three assertions were added.

Two smaller ones folded in without ceremony: `_launch` defers `change_scene_to_file`, since the bypass path reaches it from inside `_ready`; and `_refresh_play` is the single owner of the Play button's state, because Task 6 adds a second reason to refuse it and two writers on one property means whichever ran last decides.

**Counts.** The gate's recorded set moves 62 → 63 (Task 1) → 64 (Task 3) → 65 (Task 6), and each of those tasks updates the header comment in the same commit as the `ALL` edit.

**Placeholder scan.** None remain. The one that survived the first draft — a guessed `DirectorKeys.mac_code` — was replaced with the real `Keys.code_for` / `Keys.char_for` pair after reading `director/director_keys.gd:71,91` and `tools/debug_bindings.gd:77-85`. Every scene-tree layout, config section and code block in this plan is literal.

**The two things that need a display server** and so cannot be gated: the launcher's layout, and the by-eye verification steps in Tasks 4-7. Each of those steps names exactly what to look at and what should happen, and the logic underneath them — the title list, the binding rules, the merge — is in `.gd` files with harnesses that do run headless.
