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
## So: no binding types a character, none of them is a key any title is measured
## to test, and all of them come from `director_game.cfg`.
##
## The first of those used to read "every binding is an F-key", and that band has
## now run out -- twelve keys, F10 is Rating's, eleven commands, and
## `fast_forward` made twelve. The band was only ever a proxy for "types no
## character", which is the property that actually protects the player, so that
## is what is asserted; PageDown satisfies it exactly as F5 does. The half that
## caught F10 is the measured sweep, and it is unchanged.
##
## **The chords are measured the same way rather than assumed to inherit.** Five
## commands sit on Shift+F-keys. A Mac key code carries no modifier, so Shift+F1
## has F1's code and the sweep below reaches the same verdict about it -- but
## reaching it by measurement is the whole point of this file, and "it obviously
## inherits" is the shape of the reasoning that put the pause on F10. The chord
## half that is *not* inherited is the dispatch: a preview matching on the bare
## keycode would run `step_back` on Shift+F5 and never reach the chord at all,
## which is asserted here as "the two are different commands".
##
## **And then the whole layer got a switch.** `[debug] enabled` turns every
## binding, every overlay and the report at exit off in one place, so a shipped
## build is a Director player and nothing else. Off is asserted as *no keycode is
## claimed by the preview at all* -- strictly stronger than the band test, since
## a key nothing is bound to cannot collide with anything.

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
## A keypress carrying whatever modifiers the *name* of the binding asked for.
##
## `OS.find_keycode_from_string("Shift+F5")` answers `KEY_MASK_SHIFT | KEY_F5`,
## and that number is not a keycode: assigning it to `event.keycode` makes
## `director_keys.gd` look up a Mac code for a value no key has and answer -1, so
## every measurement about a chord would quietly pass by measuring nothing. The
## mask is therefore split back out into the event's own modifier flags and the
## bare key goes in `keycode`, which is what the OS delivers.
func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = (code & KEY_CODE_MASK) as Key
	event.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	event.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	event.alt_pressed = (code & KEY_MASK_ALT) != 0
	event.meta_pressed = (code & KEY_MASK_META) != 0
	event.pressed = true
	var bare := int(event.keycode)
	if bare >= 32 and bare <= 126:
		event.unicode = String.chr(bare).to_lower().unicode_at(0)
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

	# **The band was a proxy and it has run out.** Twelve F-keys, F10 is Rating's
	# at 48 sites, and the other eleven commands filled the rest -- so the twelfth
	# command, `fast_forward`, had nowhere in the band to go. What the band was
	# ever protecting is that a preview key types no *character*: a binding on a
	# letter runs the game's handler and the preview's command at once, and what
	# the player sees is the game misbehaving. That is the property asserted here,
	# and it is strictly stronger than "F1 to F12" -- every F-key satisfies it,
	# and so do PageUp/PageDown/Insert, which the band excluded for no reason it
	# could state.
	#
	# The other half of the old check -- "and no title reaches for it" -- is the
	# measured sweep below, which is where F10 was actually caught. Restating the
	# band here would only have re-encoded the habit that missed it.
	h.begin("no preview key types a character")
	for command in bound:
		var name := str(bound[command])
		var code := OS.find_keycode_from_string(name)
		var typed := Keys.char_for(_key(code))
		h.check("%s (%s) types nothing" % [command, name], typed == "",
			"types '%s'" % typed)
	h.complete("no preview key types a character")

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
	# The chords, as a dispatch question rather than a collision one. The sweep
	# above has already measured them against every title -- they are in `bound`
	# like everything else -- so what is left is the half that was actually broken:
	# a chord and its bare key are two bindings, and a router that matches on
	# `event.keycode` collapses them into one.
	h.begin("a chord is a different binding from the key underneath it")
	var chords := 0
	for command in bound:
		var name := str(bound[command])
		if not name.contains("+"):
			continue
		chords += 1
		var chord := OS.find_keycode_from_string(name)
		h.check("%s: %s round-trips through the parser" % [command, name],
			OS.get_keycode_string(chord) == name, OS.get_keycode_string(chord))
		h.check("%s: the chord resolves to it" % name,
			DebugKeys.command_for(chord) == command, DebugKeys.command_for(chord))
		var bare := chord & KEY_CODE_MASK
		h.check("%s: and does not answer for plain %s"
			% [name, OS.get_keycode_string(bare)],
			DebugKeys.command_for(bare) != command, DebugKeys.command_for(bare))
		# The event's own view of itself, which is what `input_router.gd` matches
		# on. If these two numbers ever disagree the map is unreachable.
		h.check("%s: an event of it reports the same code" % name,
			_key(chord).get_keycode_with_modifiers() == chord,
			str(_key(chord).get_keycode_with_modifiers()))
	h.check("there are chords to check (%d)" % chords, chords > 0)
	h.complete("a chord is a different binding from the key underneath it")

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
	cfg.set_value("debug", "fast_forward_fps", 24)
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
	# The section carries numbers as well as keys now, and the fast-forward rate
	# is one: "make the F9 fps configurable from the cfg" was the request, so a
	# rate the file names and the engine ignores is the failure to catch.
	h.check("a `[debug]` number comes out of the file",
		is_equal_approx(DebugKeys.number("fast_forward_fps"), 24.0),
		"%.1f" % DebugKeys.number("fast_forward_fps"))
	# 0 fps is a stopped movie, which reads as the toggle having hung the player,
	# so a nonsense value falls back rather than being honoured.
	cfg.set_value("debug", "fast_forward_fps", 0)
	cfg.save(written)
	DebugKeys.load_config(written)
	h.check("and a value that would stop the movie falls back to the default",
		is_equal_approx(DebugKeys.number("fast_forward_fps"),
			float(DebugKeys.SETTINGS["fast_forward_fps"])),
		"%.1f" % DebugKeys.number("fast_forward_fps"))
	h.complete("the config decides, not the defaults")

	# The master switch. Off has to mean *nothing is claimed*, which is a stronger
	# statement than anything above it: a key no command sits on cannot collide
	# with a title, cannot eat a character, and cannot be a hotspot outline drawn
	# over somebody's game. This is what a shipped build looks like.
	cfg.clear()
	cfg.set_value("debug", "enabled", "false")
	cfg.save(written)

	h.begin("with the layer off the preview claims no key at all")
	DebugKeys.load_config(written)
	h.check("`enabled` reads false", not DebugKeys.enabled())
	h.check("no binding is reported", DebugKeys.bindings().is_empty(),
		JSON.stringify(DebugKeys.bindings()))
	var claimed: Array[String] = []
	# Every key the map could possibly hold, plus the chords: the twelve F-keys
	# with and without shift, and the one binding outside the band.
	for code in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8,
			KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_PAGEDOWN, KEY_PAGEUP]:
		for chord in [int(code), KEY_MASK_SHIFT | int(code)]:
			if DebugKeys.command_for(chord) != "":
				claimed.append("%s -> %s" % [
					OS.get_keycode_string(chord), DebugKeys.command_for(chord)])
	h.check("and none of the keys it ships on runs anything",
		claimed.is_empty(), ", ".join(claimed))
	h.check("naming a command still reports it as unbound",
		DebugKeys.key_name("quick_save") == "", DebugKeys.key_name("quick_save"))
	h.complete("with the layer off the preview claims no key at all")

	# ...and back on, deliberately, because a QA build shipped *with* the tools is
	# a thing the switch has to be able to say. A one-way switch would be half a
	# feature.
	cfg.set_value("debug", "enabled", "true")
	cfg.save(written)
	h.begin("and `true` turns it back on, which is what a QA build asks for")
	DebugKeys.load_config(written)
	h.check("`enabled` reads true", DebugKeys.enabled())
	h.check("the bindings are back", DebugKeys.bindings().size() == DebugKeys.DEFAULTS.size(),
		"%d of %d" % [DebugKeys.bindings().size(), DebugKeys.DEFAULTS.size()])
	h.complete("and `true` turns it back on, which is what a QA build asks for")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
	DebugKeys.load_config()
	h.begin("the shipped config leaves the choice to the build")
	# `auto` in the tracked file is the design and not an accident: this file is
	# what an export ships, so a `true` here would put the debug layer in every
	# build unless somebody remembered to edit it.
	var shipped := ConfigFile.new()
	shipped.load(DebugKeys.CONFIG_PATH)
	h.check("director_game.cfg says `auto`",
		str(shipped.get_value("debug", "enabled", "")).to_lower() == DebugKeys.AUTO,
		str(shipped.get_value("debug", "enabled", "<missing>")))
	# And running from source keeps the tools, or every harness below this line
	# would be measuring an empty map.
	h.check("which leaves them on when running from source", DebugKeys.enabled())
	# `enabled_for()` is `launcher.gd`'s door onto this same resolution, called
	# with the tracked config directly instead of through `load_config`'s
	# cached `_switch`. `auto` is exactly the case two independent parsers
	# answered differently before this fix -- `launcher.gd` had its own copy
	# that never asked `OS.has_feature("editor")` -- so `auto` is where a
	# regression would show again.
	h.check("and `enabled_for()` on the tracked config agrees with `enabled()`",
		DebugKeys.enabled_for(shipped) == DebugKeys.enabled(),
		"enabled_for=%s enabled=%s" % [DebugKeys.enabled_for(shipped), DebugKeys.enabled()])
	# The two argv spellings, `--debug-ui=on` and `--debug-ui on`, are the
	# escape hatch out of a Developer tab that `[debug] enabled` has switched
	# off -- so it is not enough for `resolve_switch()`'s loop to look, by
	# reading, like it treats them alike; a gate has to see them actually
	# agree. `OS.get_cmdline_user_args()` cannot be changed mid-process, so
	# `resolve_switch()` takes the args it reads as a defaulted parameter, and
	# this hands both spellings in directly rather than relying on however
	# this process happened to be launched.
	var off_cfg := ConfigFile.new()
	off_cfg.set_value("debug", "enabled", "false")
	for word in ["on", "off"]:
		var space_form := DebugKeys.resolve_switch(off_cfg, true, ["--debug-ui", word])
		var equals_form := DebugKeys.resolve_switch(off_cfg, true, ["--debug-ui=%s" % word])
		var wanted: String = DebugKeys.ON if word == "on" else DebugKeys.OFF
		h.check("`--debug-ui %s` and `--debug-ui=%s` agree" % [word, word],
			space_form == wanted and equals_form == wanted,
			"space=%s equals=%s wanted=%s" % [space_form, equals_form, wanted])
	# With no flag at all, the config's own `false` must be what answers --
	# otherwise the checks above could be passing because the config already
	# agrees with the flag, not because the flag is doing anything.
	h.check("and with no flag the config alone decides",
		DebugKeys.resolve_switch(off_cfg, true, []) == DebugKeys.OFF,
		DebugKeys.resolve_switch(off_cfg, true, []))
	# An unrecognised flag value must not silently strip the debug layer, same
	# as an unrecognised config value -- it falls back to `auto` rather than
	# `off`.
	h.check("and a flag value nobody recognises falls back to `auto`",
		DebugKeys.resolve_switch(off_cfg, true, ["--debug-ui=sideways"]) == DebugKeys.AUTO,
		DebugKeys.resolve_switch(off_cfg, true, ["--debug-ui=sideways"]))
	h.complete("the shipped config leaves the choice to the build")

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
