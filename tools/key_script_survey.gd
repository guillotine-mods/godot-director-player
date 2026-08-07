extends SceneTree
## Which keys does a title actually reach for, and how does it ask?
##
##   godot --headless --script tools/key_script_survey.gd -- --root rating
##   godot --headless --script tools/key_script_survey.gd -- --root rating --file BATZEGOZ.dir --show
##   godot --headless --script tools/key_script_survey.gd -- --all
##
## `director/director_keys.gd` and `tools/debug_bindings.gd` both used to carry a
## list of "the keys the corpus tests", swept by hand out of `reference/lingo/`
## -- which holds Piposh 2 and nothing else. The engine runs six titles. Rating
## tests `the keyCode = 109` at 48 sites, and 109 is **F10**, which is where the
## preview's pause binding sat, on a band that list said was empty.
##
## So this is the measurement, repeatable and per root. It reports, for a title:
##
##   * how the keyboard is asked for -- `on keyDown`, `the keyDownScript`,
##     `the keyUpScript`, `when keyDown then`, `the key`, `the keyCode`,
##     `dontPassEvent`
##   * every literal `the key = "x"` character, which is a key the player must be
##     able to type
##   * every literal `the keyCode = n` Mac code, resolved back to a key name
##
## `tools/debug_bindings.gd` runs the same scan as a gate. This one is for
## looking: `--show` prints the Lingo line each hit came from.
##
## Title-agnostic. Nothing here knows what a game is called.

const Args := preload("res://tools/lib/args.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const Keys := preload("res://director/director_keys.gd")
const Paths := preload("res://director/director_paths.gd")


func _init() -> void:
	var args := Args.parse()
	var show := Args.flag(args, "show")
	var only := Args.text(args, "file")

	var roots: Array = []
	if Args.flag(args, "all"):
		roots = KeySites.roots()
	else:
		var paths := Paths.new()
		if not paths.load_config():
			print("no game configured: %s must set [game] root" % Paths.CONFIG_PATH)
			quit(1)
			return
		roots = [paths.root]

	for root in roots:
		_report(KeySites.for_root(str(root), only), show)
	quit(0)


func _report(sites: Dictionary, show: bool) -> void:
	print("")
	print("root       : %s" % sites["root"])
	print("containers : %d scanned" % int(sites["containers"]))
	print("")
	print("how it asks")
	var asks: Dictionary = sites["asks"]
	for label in KeySites.ASKS:
		if not asks.has(label):
			continue
		print("  %-22s %d" % [label, asks[label]])
		if show:
			for line in (sites["lines"] as Dictionary).get(label, []):
				print("      %s" % line)
	if asks.is_empty():
		print("  (nothing in this title asks for the keyboard)")

	print("")
	print("`the key` literals -- every one is a character the player must be able to type")
	var chars: Dictionary = sites["chars"]
	for literal in _sorted(chars.keys()):
		var where: Array = chars[literal]
		print("  \"%s\"  %d site(s)   %s" % [literal, where.size(), where[0]])
	if chars.is_empty():
		print("  (none)")

	print("")
	print("`the keyCode` literals, as key names")
	var codes: Dictionary = sites["codes"]
	for code in _sorted(codes.keys()):
		var where2: Array = codes[code]
		print("  %-4d %-12s %d site(s)   %s" % [
			code, _key_name(int(code)), where2.size(), where2[0],
		])
	if codes.is_empty():
		print("  (none)")


## The Godot key whose Mac virtual code this is, as a printable name.
func _key_name(mac_code: int) -> String:
	for keycode in Keys.MAC_CODES:
		if int(Keys.MAC_CODES[keycode]) == mac_code:
			return OS.get_keycode_string(keycode)
	return "?"


func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out
