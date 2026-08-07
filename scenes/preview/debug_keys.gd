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
## script *can* claim one -- but the movie is offered every key first and the
## debug map only sees what it did not take (`director_preview.gd:_input`). An
## F-key is simply the band no game in either corpus reaches for.
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

const CONFIG_PATH := "res://director_game.cfg"
const SECTION := "debug"

## Command -> the key it ships on. Read when the config says nothing, and also
## the list of commands the config may name: a `[debug]` entry whose key is not
## one of these is a typo, and reported rather than ignored.
##
## F9, F11 and F12 are deliberately free. Filling the band exactly would leave the
## next command nowhere to go.
const DEFAULTS := {
	"boxes": "F1",
	"hit_test": "F2",
	"report": "F3",
	"restart": "F4",
	"step_back": "F5",
	"step_forward": "F6",
	"fullscreen": "F7",
	"quit": "F8",
	"pause": "F10",
}

## Godot keycode -> command name. Built once; the config does not change while a
## movie is running. Static rather than node state on purpose: this is a reading
## of a file, not something a movie can alter, and `tools/preview_surface.gd`
## asserts what the harnesses reach for on the node.
static var _map: Dictionary = {}
static var _loaded := false


## The command a keypress runs, or "" when nothing is bound to it.
static func command_for(keycode: int) -> String:
	if not _loaded:
		load_config()
	return str(_map.get(keycode, ""))


## The key a command is on, as a name to print. "" when it is unbound.
static func key_name(command: String) -> String:
	if not _loaded:
		load_config()
	for code in _map:
		if str(_map[code]) == command:
			return OS.get_keycode_string(code)
	return ""


## Every binding, command -> key name, in the order `DEFAULTS` declares them so a
## printed list reads the same every run.
static func bindings() -> Dictionary:
	var out: Dictionary = {}
	for command in DEFAULTS:
		var name := key_name(command)
		if name != "":
			out[command] = name
	return out


## Re-read the config. Called on first use; exposed so a harness can point at a
## different file, and so a test that has just written one is not reading the
## previous run's answer.
static func load_config(config_path: String = CONFIG_PATH) -> void:
	_loaded = true
	_map = {}
	var cfg := ConfigFile.new()
	var has_file := cfg.load(config_path) == OK
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
		if not DEFAULTS.has(named):
			push_warning("director_game.cfg [%s]: no command called '%s'"
				% [SECTION, named])
