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
## Copied from `tools/debug_bindings.gd:77-88` rather than reinvented, so the
## launcher asks the question in exactly the shape the gate asks it. `keycode`
## is masked with `KEY_CODE_MASK`, which drops the modifier: Mac key codes carry
## none, so a chord's risk against a title is exactly its base key's -- Shift+F1
## is as safe as F1, which the gate measures rather than assumes.
##
## `unicode` is set from the bare keycode for printable ASCII, exactly as
## `debug_bindings.gd`'s own `_key` does. `Keys.char_for` reads `unicode` first,
## so without it every letter and Space would answer "" and `typed_in` would
## refuse nothing -- which is the `S` case the second half of the rule exists
## to catch.
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
	var bare := int(event.keycode)
	if bare >= 32 and bare <= 126:
		event.unicode = String.chr(bare).to_lower().unicode_at(0)
	return event
