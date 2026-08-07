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
## **And then it happened again, inside the fix.** The move to F-keys was
## justified by a list of "the keys the corpus tests" that had been swept by hand
## out of `reference/lingo/` -- which holds Piposh 2 and nothing else, while the
## engine runs six titles under `games/`. Rating tests `the keyCode = 109` at 48
## sites and 109 is **F10**, where the pause landed. A hand-written constant is
## exactly as good as the corpus whoever wrote it happened to have open, and this
## file carried one.
##
## So the corpus half is measured now, by `tools/lib/key_sites.gd`, over **every**
## root under `games/` rather than the one the config is pointed at -- a binding
## is safe or unsafe for the engine, not for whichever title is loaded. That
## sweep is the slow part of this harness and it is the point of it.
##
## So: every binding is an F-key, none of them is a key any title is measured to
## test, and all of them come from `director_game.cfg`.

const Harness := preload("res://tools/lib/harness.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const Keys := preload("res://director/director_keys.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")


## A keypress as the OS would deliver it -- **including the character**, which is
## the half a synthetic event usually forgets. `director_keys.gd:char_for` reads
## `unicode` first, so an event with only a keycode set answers `""` for every
## letter on the keyboard, and a check asking "does this binding type a character
## the game tests" would pass for `L` by measuring nothing. Godot's letter
## keycodes are their uppercase ASCII; unshifted, a key types the lowercase.
func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	if code >= 32 and code <= 126:
		event.unicode = String.chr(code).to_lower().unicode_at(0)
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

	h.begin("every preview key is in the F-key band")
	for command in bound:
		var name := str(bound[command])
		var code := OS.find_keycode_from_string(name)
		h.check("%s is on an F-key (%s)" % [command, name],
			code >= KEY_F1 and code <= KEY_F12)
	h.complete("every preview key is in the F-key band")

	# The band is a convention. This is the statement that actually protects the
	# player, and it is read out of the games rather than out of a constant: for
	# every title the engine can load, no binding sits on a key that title's own
	# scripts test -- by `the keyCode`, which is the physical key, or by
	# `the key`, which is the character.
	#
	# Both halves matter and they fail differently. A `the keyCode` collision is
	# what F10 was: the band looked empty because only one corpus had been read.
	# A `the key` collision cannot happen while every binding is an F-key -- an
	# F-key types no character -- so that arm is a guard on the day one is moved.
	h.begin("no preview key is one any title is measured to reach for")
	for root in KeySites.roots():
		var sites := KeySites.for_root(str(root))
		var title := str(root).get_file()
		h.check("%s: %d container(s) read, so this is a measurement"
			% [title, int(sites["containers"])], int(sites["containers"]) > 0)
		var codes: Dictionary = sites["codes"]
		var chars: Dictionary = sites["chars"]
		for command in bound:
			var name := str(bound[command])
			var keycode := OS.find_keycode_from_string(name)
			var mac := Keys.code_for(_key(keycode))
			h.check("%s: %s (%s) is not a keyCode %s tests" % [title, command, name, title],
				not codes.has(mac),
				"mac code %d, %d site(s), e.g. %s" % [
					mac, (codes.get(mac, []) as Array).size(),
					(codes.get(mac, ["-"]) as Array)[0],
				])
			var typed := Keys.char_for(_key(keycode)).to_lower()
			h.check("%s: %s (%s) types no character %s tests" % [title, command, name, title],
				typed == "" or not chars.has(typed),
				"'%s', %d site(s)" % [typed, (chars.get(typed, []) as Array).size()])
	h.complete("no preview key is one any title is measured to reach for")

	# Named one by one rather than derived, because each of these is a key some
	# title was measured to be using while the preview held it. A regression here
	# is a specific key going dark again, and it should say which.
	h.begin("the keys the game lost are the game's again")
	for code in [KEY_LEFT, KEY_RIGHT, KEY_R, KEY_B, KEY_M, KEY_L, KEY_F,
			KEY_ESCAPE, KEY_F10, KEY_SPACE]:
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
