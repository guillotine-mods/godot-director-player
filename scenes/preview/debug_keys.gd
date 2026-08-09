extends RefCounted
## Which key does which preview command, read from `director_game.cfg`.
##
## **Every debug binding is an F-key, and that is a rule rather than a taste.**
## The preview shares a keyboard with the movie, and Director gave the movie all
## of it: `the key` is a character, `the keyCode` is a physical key, and a title
## may test either for anything. This corpus alone routes 30-odd sites through
## the arrows and three through plain letters. A preview binding on a key a game
## can want is not a conflict that shows up as an error -- the game's handler
## runs, *and* the playhead jumps, or the window goes fullscreen, and what the
## player sees is the game misbehaving.
##
## That is not hypothetical here. `LEFT`/`RIGHT` stepped the playhead, and the
## arrows are how this game's menu and map are driven, so playing it with the
## keyboard meant fighting the debugger. `R`, `B`, `M`, `L` and `F` were plain
## letters. `ESCAPE` quit the process outright, and Director's own `the keyCode`
## has a code for it (53), so a title that reads Escape could not.
##
## The F-keys are not sacred either -- `director_keys.gd` maps all twelve, so a
## script *can* claim one -- and **one of them was claimed**. The move to this
## band was justified by "no game in either corpus reaches for an F-key", swept
## by hand from `reference/lingo/`, which holds Piposh 2 alone. The engine runs
## six titles. `tools/key_script_survey.gd -- --all` reads all six and finds
## Rating testing `the keyCode = 109` at **48 sites** -- 109 is F10, which is
## where the pause sat. It is `normalkeysx` / `normalkeys2` / `normalkeys3` in
## `ARCADE1.dir`, the handler that leaves a timed scene, so in Rating the one key
## that gets a player out of a room also paused the preview.
##
## The pause is on F9 now and F10 is the spare. That is a measurement rather than
## a fresh guess: `tools/debug_bindings.gd` runs the same survey over every root
## under `games/` and fails if any binding lands on a key any title tests.
##
## F10 was already here for this exact reason: the pause used to be on space,
## which is the key `fromnow` turns into "skip this line of speech" in 46
## scripts, so the one key a player reaches for first paused the preview instead
## of doing anything. The rest of the map has now caught up with it.
##
## Configurable because the band being safe is a judgement about *these* titles.
## A game that wants F5 needs somewhere else to put the step, and an empty value
## unbinds a command entirely rather than moving it -- which is the only way to
## hand a key back for good.
##
## **And then the band ran out.** Twelve F-keys, one of them Rating's, eleven
## commands: the twelfth command has nowhere in the band to go. So `fast_forward`
## is the first binding outside it, and the rule it actually keeps is the one the
## band was only ever a proxy for -- *a preview key must type no character and
## must be a key no title is measured to test.* Measured over all six roots by
## `tools/lib/key_sites.gd`, the union of tested Mac codes is
##
##   0 1 2 4 7 11 12 13 14 15 18-28 32 36 37 38 45 46 49 51 53 109 123-126
##
## PageDown is Mac code 121, is in none of it, produces no character, and is not
## one of the keys `preview/text_focus.gd` gives to a focused field (which takes
## Up/Down/Home/End/Delete/Tab and would fight a binding on any of those). F10 --
## 109, Rating's, 48 sites -- stays unassigned.
##
## `tools/debug_bindings.gd` asserts that predicate rather than the band, over
## every root under `games/`, so the next command added is checked against the
## games instead of against a habit.
##
## ## The master switch
##
## **None of this ships by default.** `[debug] enabled` turns the whole preview
## layer on or off in one place -- every binding here, the hotspot outlines, the
## SKIP button, the HUD line, the toast, the container picker and the report at
## exit -- and `enabled()` is the single question all of them ask. One switch,
## because eleven independent ones is eleven chances to leave one on.
##
## Three values, and the third is the point:
##
##   * `true`  -- on. A QA build shipped *with* the tools is a deliberate act and
##     has to be sayable.
##   * `false` -- off, even running from source.
##   * `auto`  -- on when this is a run from source or a debug export, off in a
##     release export. **The default**, and the one the tracked config carries.
##
## `auto` rather than a plain default of `true` because `director_game.cfg` is a
## tracked file: whatever it says is what an export ships, so a config reading
## `enabled = true` would put the debug layer in every build unless somebody
## remembered to edit it, and "unless somebody remembers" is the failure mode
## this switch exists to remove. With `auto` the safe answer is the one you get
## by doing nothing, and the unsafe one has to be typed.
##
## `--debug-ui on|off` beats the file, for a single run.
##
## **The resolution lives here and nowhere else**, which is `DirectorPaths`'
## `--root` lesson applied: that override is resolved inside `load_config`
## because `AudioDirector` calls it too, and one applied at the single call site
## that wanted it moved the movies and left the sounds behind. Every reader of
## this switch asks `enabled()` and gets the same answer.

const CONFIG_PATH := "res://director_game.cfg"
const GameConfig := preload("res://director/game_config.gd")
const SECTION := "debug"

## The `[debug] enabled` values, and what each means. See the header.
const ON := "true"
const OFF := "false"
const AUTO := "auto"

## `[debug]` entries that are values rather than keys, with their defaults.
##
## Kept beside `DEFAULTS` because the section is validated against both: a name
## in neither is a typo and is reported, and without this a rate written into
## `[debug]` would be warned about as "no command called 'fast_forward_fps'".
##
## `fast_forward_fps` is the rate the fast-forward toggle forces (§9.1 is the
## rate the *score* asks for; this overrides it while the toggle is on). It is a
## setting rather than a constant because the request that produced it was
## "something really fast, like 60fps" -- an eyeballed number, and an eyeballed
## number belongs in the file the player can edit.
const SETTINGS := {
	"fast_forward_fps": 60.0,
}

## Command -> the key it ships on. Read when the config says nothing, and also
## the list of commands the config may name: a `[debug]` entry whose key is not
## one of these is a typo, and reported rather than ignored.
##
## **F10 is not free by taste, it is Rating's** -- 48 `the keyCode = 109` sites.
## The one spare F-key is a deliberate margin: filling the band exactly would
## leave the next command nowhere to go, and it now has to be a key no title
## tests, which is a shorter list than it looks.
## **The chords.** Five commands sit on Shift+F-keys, and that is a second band
## rather than a crowding of the first: the plain band was full at eleven, and
## `Shift+F5` and `F5` are different events, so the save/load set costs the game
## no key it did not already lose. `OS.find_keycode_from_string` round-trips
## `"Shift+F5"` to `KEY_MASK_SHIFT | KEY_F5` and `OS.get_keycode_string` back
## again, so the parser below needed nothing added -- but the *dispatch* did:
## `input_router.gd` matched on `event.keycode`, which drops the modifier, so
## before this Shift+F5 ran `step_back` and a chord binding could never have
## fired at all. It matches on `get_keycode_with_modifiers()` now.
##
## Mac key codes carry no modifier, so a chord's collision risk against a title
## is exactly its base key's -- Shift+F1 is as safe as F1, which is measured, and
## `tools/debug_bindings.gd` measures the chords the same way rather than
## assuming the inheritance.
const DEFAULTS := {
	"boxes": "F1",
	"hit_test": "F2",
	"report": "F3",
	"restart": "F4",
	"step_back": "F5",
	"step_forward": "F6",
	"fullscreen": "F7",
	"quit": "F8",
	"pause": "F9",
	"snapshot": "F11",
	"containers": "F12",
	# The one binding outside the F-key band, because the band is full and F10 is
	# Rating's. See the header for the measurement that chose it.
	"fast_forward": "PageDown",
	# The second binding outside the F-key band, and for the same reason the
	# first one is: twelve F-keys, F10 is Rating's, the other eleven are spoken
	# for. PageUp is Mac code 116, which is in none of the tested sets over all
	# six roots, types no character, and is not one of the keys a focused
	# editable field takes (Up, Down, Home, End, Delete, Tab). Its sibling
	# PageDown was chosen the same way. `tools/debug_bindings.gd` asserts that
	# against the games rather than against this comment.
	"collisions": "PageUp",
	# Save state. Shift+F1 is the odd one out -- it prints the globals and has
	# nothing to do with saving -- and it is here because it is the diagnostic
	# that answers "why did this save not reproduce": the globals are what a
	# restored session is mostly made of.
	"globals": "Shift+F1",
	"quick_save": "Shift+F5",
	"quick_load": "Shift+F6",
	"save_as": "Shift+F7",
	"load_file": "Shift+F8",
}

## Godot keycode -> command name. Built once; the config does not change while a
## movie is running. Static rather than node state on purpose: this is a reading
## of a file, not something a movie can alter, and `tools/preview_surface.gd`
## asserts what the harnesses reach for on the node.
static var _map: Dictionary = {}
static var _loaded := false
## The `SETTINGS` values as the config left them, filled by `load_config`.
static var _numbers: Dictionary = {}
## `ON`, `OFF` or `AUTO` as the config and the command line left it.
static var _switch := AUTO


## Is the preview's own layer there at all? See the header.
##
## Everything that exists only for us asks this: the key map below, the hotspot
## outlines, the SKIP button, the HUD, the toast, the container picker and the
## report printed at exit. A shipped build answers false and behaves as though
## none of it was ever written.
static func enabled() -> bool:
	if not _loaded:
		load_config()
	match _switch:
		ON:
			return true
		OFF:
			return false
	# `auto`. Running from source or from a debug export keeps the tools, because
	# losing them silently while developing is the other way to get this wrong.
	# A release export answers false.
	return OS.has_feature("editor") or OS.is_debug_build()


## The command a keypress runs, or "" when nothing is bound to it.
##
## `keycode` is the key **with its modifiers** — `InputEventKey`'s
## `get_keycode_with_modifiers()`, which is what `OS.find_keycode_from_string`
## produces for a name like `"Shift+F5"`. Matching on the bare keycode instead is
## what made every chord binding unreachable and made Shift+F5 run `step_back`.
static func command_for(keycode: int) -> String:
	if not enabled():
		return ""
	return str(_map.get(keycode, ""))


## The key a command is on, as a name to print. "" when it is unbound.
static func key_name(command: String) -> String:
	if not enabled():
		return ""
	for code in _map:
		if str(_map[code]) == command:
			return OS.get_keycode_string(code)
	return ""


## Every binding, command -> key name, in the order `DEFAULTS` declares them so a
## printed list reads the same every run. Empty when the layer is off, which is
## the whole of what "off" means: no keycode is claimed by the preview at all.
static func bindings() -> Dictionary:
	var out: Dictionary = {}
	if not enabled():
		return out
	for command in DEFAULTS:
		var name := key_name(command)
		if name != "":
			out[command] = name
	return out


## A `[debug]` setting that is a number rather than a key. Falls back to the
## shipped default, and refuses a value that is not positive: a fast-forward at
## 0 fps is a movie that stops, which reads as the toggle having hung the player.
static func number(name: String) -> float:
	if not _loaded:
		load_config()
	var value := float(_numbers.get(name, SETTINGS.get(name, 0.0)))
	return value if value > 0.0 else float(SETTINGS.get(name, 0.0))


## Re-read the config. Called on first use; exposed so a harness can point at a
## different file, and so a test that has just written one is not reading the
## previous run's answer.
static func load_config(config_path: String = CONFIG_PATH) -> void:
	_loaded = true
	_map = {}
	_numbers = {}
	# This function's own promise, above, predates `GameConfig`: a harness that
	# rewrites `config_path` and calls this again must see the new file, not the
	# merge point's cached answer for the same path.
	GameConfig.invalidate()
	var cfg := GameConfig.merged(config_path)
	var has_file := GameConfig.exists(config_path)
	_switch = _resolve_switch(cfg, has_file)
	for setting in SETTINGS:
		var value: Variant = SETTINGS[setting]
		if has_file:
			value = cfg.get_value(SECTION, setting, value)
		_numbers[setting] = float(value) if str(value).is_valid_float() else float(SETTINGS[setting])
	for command in DEFAULTS:
		var wanted := str(DEFAULTS[command])
		if has_file:
			wanted = str(cfg.get_value(SECTION, command, wanted))
		# An empty value unbinds the command. Not the same as omitting the line,
		# which means "whatever the engine ships": a game that needs F5 back has
		# to be able to say so and have nothing take its place.
		wanted = wanted.strip_edges()
		if wanted == "":
			continue
		var code := OS.find_keycode_from_string(wanted)
		if code == KEY_NONE:
			push_warning("director_game.cfg [%s] %s: '%s' is not a key name"
				% [SECTION, command, wanted])
			continue
		if _map.has(code):
			# Two commands on one key means one of them silently never runs, and
			# which one depends on iteration order. Say so rather than pick.
			push_warning("director_game.cfg [%s]: %s and %s are both on %s"
				% [SECTION, _map[code], command, wanted])
			continue
		_map[code] = command
	if not has_file:
		return
	for named in cfg.get_section_keys(SECTION) if cfg.has_section(SECTION) else []:
		if not DEFAULTS.has(named) and not SETTINGS.has(named) and named != "enabled":
			push_warning("director_game.cfg [%s]: no command called '%s'"
				% [SECTION, named])


## `--debug-ui on|off` beats `[debug] enabled`, which beats `auto`.
##
## Read here rather than at a call site, for the reason `DirectorPaths` gives
## about `--root`: one override applied in one of several readers is an override
## the other readers disagree with. Everything asks `enabled()`, `enabled()` asks
## this once, and there is one answer per process.
##
## An unrecognised value falls back to `auto` with a warning rather than to
## "off", because a typo that silently strips the whole debug layer reads as the
## build being broken.
static func _resolve_switch(cfg: ConfigFile, has_file: bool) -> String:
	var wanted := AUTO
	if has_file:
		wanted = str(cfg.get_value(SECTION, "enabled", AUTO)).strip_edges().to_lower()
	var expecting := false
	for arg in OS.get_cmdline_user_args():
		if expecting:
			wanted = str(arg).strip_edges().to_lower()
			expecting = false
		elif str(arg).begins_with("--debug-ui="):
			wanted = str(arg).substr(11).strip_edges().to_lower()
		elif str(arg) == "--debug-ui":
			expecting = true
	match wanted:
		"on", "true", "1", "yes":
			return ON
		"off", "false", "0", "no":
			return OFF
		AUTO, "":
			return AUTO
	push_warning("director_game.cfg [%s] enabled: '%s' is not true, false or auto"
		% [SECTION, wanted])
	return AUTO
