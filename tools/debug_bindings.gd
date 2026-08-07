extends SceneTree
## Do the preview's own keys stay out of the game's way, and does the config
## actually decide them?
##
##   godot --headless --script tools/debug_bindings.gd
##
## The preview shares a keyboard with the movie. Director gave the movie all of
## it -- `the key` is a character and `the keyCode` a physical key, and a title
## may test either for anything -- so a preview binding on a key a game can want
## is not a conflict that reports itself. The game's handler runs, *and* the
## preview does its thing, and the player sees the game misbehaving.
##
## The arrows were the live case: the step was on LEFT/RIGHT and this corpus
## routes 30-odd sites through the arrow key codes, so playing with the keyboard
## meant fighting the debugger. `R`, `B`, `M`, `L` and `F` were plain letters and
## `ESCAPE` quit the process, which Director also has a key code for.
##
## So: every binding is an F-key, none of them is a key `director_keys.gd` says
## the corpus tests, and all of them come from `director_game.cfg`.

const Harness := preload("res://tools/lib/harness.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const Keys := preload("res://director/director_keys.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")

## What `reference/lingo/` is measured to test, from the sweep recorded at the
## top of `director/director_keys.gd`: space, the four arrows, and three letters.
## A preview binding on any of these is a binding on a key the game is using.
const CLAIMED_BY_SCRIPTS := [
	Keys.SPACE, Keys.LEFT, Keys.RIGHT, Keys.UP, Keys.DOWN, 2, 13, 14,
]


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _init() -> void:
	var h := Harness.new()
	DebugKeys.load_config()
	var bound := DebugKeys.bindings()

	h.begin("every preview command has a key")
	for command in DebugKeys.DEFAULTS:
		h.check("%s is bound" % command, bound.has(command),
			str(bound.get(command, "unbound")))
	h.complete("every preview command has a key")

	h.begin("no preview key is one a game can reach for")
	for command in bound:
		var name := str(bound[command])
		var code := OS.find_keycode_from_string(name)
		h.check("%s is on an F-key (%s)" % [command, name],
			code >= KEY_F1 and code <= KEY_F12)
		# The stronger statement, and the one that is measured rather than
		# assumed: not a key any script in the corpus is known to test.
		h.check("%s is not a key the corpus tests" % command,
			not CLAIMED_BY_SCRIPTS.has(Keys.code_for(_key(code))),
			"mac code %d" % Keys.code_for(_key(code)))
	h.complete("no preview key is one a game can reach for")

	h.begin("the keys the game lost are the game's again")
	for code in [KEY_LEFT, KEY_RIGHT, KEY_R, KEY_B, KEY_M, KEY_L, KEY_F, KEY_ESCAPE]:
		h.check("%s runs no preview command" % OS.get_keycode_string(code),
			DebugKeys.command_for(code) == "",
			DebugKeys.command_for(code))
	h.complete("the keys the game lost are the game's again")

	# The map has to come out of the file, not out of the defaults that happen to
	# match it. A config the engine ignores is worse than none: it says the key
	# moved and nothing did.
	var written := "user://debug_bindings_test.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("debug", "pause", "F9")
	cfg.set_value("debug", "report", "")
	cfg.save(written)

	h.begin("the config decides, not the defaults")
	DebugKeys.load_config(written)
	h.check("a moved command is on the key the file names",
		DebugKeys.command_for(KEY_F9) == "pause", DebugKeys.command_for(KEY_F9))
	h.check("and no longer on the one it shipped on",
		DebugKeys.command_for(KEY_F10) == "", DebugKeys.command_for(KEY_F10))
	# Unbinding is the only way to hand a key back for good, so it has to be
	# distinguishable from saying nothing -- which means "whatever ships".
	h.check("an empty value unbinds rather than resets",
		DebugKeys.key_name("report") == "", DebugKeys.key_name("report"))
	h.check("a command the file says nothing about keeps its default",
		DebugKeys.command_for(KEY_F1) == "boxes", DebugKeys.command_for(KEY_F1))
	h.complete("the config decides, not the defaults")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
	DebugKeys.load_config()

	# The keys have to actually fire, and for most of this game they did not. A
	# `keyDownScript` is installed once and then receives every key, and
	# `_dispatch_key` reports every one of them as claimed -- including the ones
	# the handler ignores. `fromnow` acts on key code 49 and on nothing else and
	# still answers claimed for the rest. So while a movie had one installed,
	# which is 46 scripts here, not a single preview binding ran: the pause had
	# been dead since it moved to F10 and it looked like a key somebody
	# misremembered. Asserted through the real preview against a real movie,
	# because that is the only place the `keyDownScript` exists.
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	var installed := ""
	for _i in 400:
		preview.call("_advance")
		var host = preview.get("_host")
		if host != null and str(host.key_down_script) != "":
			installed = str(host.key_down_script)
			break

	h.begin("a binding still fires under a movie-wide key handler")
	h.check("the movie installed one", installed != "", installed)
	var boxes: bool = preview.get("_show_boxes")
	InputRouter.key_event(preview, _key(
		OS.find_keycode_from_string(DebugKeys.key_name("boxes"))))
	h.check("the binding ran anyway", bool(preview.get("_show_boxes")) != boxes,
		"keyDownScript '%s' claims every key" % installed)
	# And the movie was still offered it, because withholding a key from a
	# `keyDownScript` would be a preview the game behaves differently under.
	h.check("and the movie was still offered the key",
		(preview.get("_sent") as Dictionary).has("keyDownScript:%s" % installed),
		JSON.stringify(preview.get("_sent")))
	h.complete("a binding still fires under a movie-wide key handler")

	print("")
	print("bindings: %s" % JSON.stringify(DebugKeys.bindings()))
	quit(h.finish("the preview's keyboard bindings"))
