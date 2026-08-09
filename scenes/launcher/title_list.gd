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
