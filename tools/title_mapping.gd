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
