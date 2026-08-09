extends SceneTree
## Six roots on disc become four entries, and one of them carries three.
##
##   godot --headless --path . --script tools/title_list.gd
##
## `tools/title_mapping.gd` asserts the *config* agrees with the disc. This
## asserts what the launcher builds out of it: the grouping, the preselected
## root, and the flag composition. The scene turns these rows into buttons and
## does nothing else, which is why the rows are the part worth a gate.
##
## Title-agnostic in its rules and not in its numbers: it asserts that a title
## covering several roots groups and preselects, without naming which title that
## is, so a corpus that gains a localisation does not fail here.

const Harness := preload("res://tools/lib/harness.gd")
const TitleList := preload("res://scenes/launcher/title_list.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")


func _init() -> void:
	var h := Harness.new()
	var entries := TitleList.build()
	var roots := KeySites.roots()

	var case := "every root on disc appears exactly once"
	h.begin(case)
	if not h.check("there are roots and entries to check",
			not roots.is_empty() and not entries.is_empty(),
			"%d root(s), %d entry(s)" % [roots.size(), entries.size()]):
		h.complete(case)
		quit(h.finish("the launcher's game list"))
		return
	var seen: Array[String] = []
	for entry in entries:
		for row in entry["roots"]:
			seen.append(str((row as Dictionary)["root"]))
	h.check("no root is lost or duplicated", seen.size() == roots.size(),
		"%d listed for %d on disc" % [seen.size(), roots.size()])
	var missing: Array[String] = []
	for root in roots:
		if not seen.has(str(root)):
			missing.append(str(root))
	h.check("and every one of them is a root that exists",
		missing.is_empty(), ", ".join(missing))
	h.check("there are fewer entries than roots, so something grouped",
		entries.size() < roots.size(),
		"%d entry(s) for %d root(s)" % [entries.size(), roots.size()])
	h.complete(case)

	case = "a title covering several roots preselects exactly one"
	h.begin(case)
	var grouped := 0
	var wrong: Array[String] = []
	for entry in entries:
		var members: Array = entry["roots"]
		if members.size() < 2:
			continue
		grouped += 1
		var chosen: Dictionary = TitleList.default_root(entry)
		if not bool(chosen.get("default", false)):
			wrong.append("%s: default_root picked %s, which is not the default"
				% [str(entry["title"]), str(chosen.get("name", "?"))])
		for row in members:
			if TitleList.flag_emoji(str((row as Dictionary).get("flag", ""))) == "":
				wrong.append("%s: %s has no usable flag"
					% [str(entry["title"]), str((row as Dictionary).get("name", "?"))])
	h.check("there is a grouped title to check", grouped > 0,
		"%d grouped title(s)" % grouped)
	h.check("each preselects its default and every member composes a flag",
		wrong.is_empty(), "; ".join(wrong))
	h.complete(case)

	case = "a country code becomes a flag, and nothing else does"
	h.begin(case)
	h.check("il composes two code points", TitleList.flag_emoji("il").length() == 2,
		TitleList.flag_emoji("il"))
	h.check("and is not the letters themselves", TitleList.flag_emoji("il") != "il")
	h.check("case does not matter", TitleList.flag_emoji("IL") == TitleList.flag_emoji("il"))
	h.check("a one-letter code composes nothing", TitleList.flag_emoji("i") == "")
	h.check("a three-letter code composes nothing", TitleList.flag_emoji("isr") == "")
	h.check("a digit composes nothing", TitleList.flag_emoji("i1") == "")
	h.complete(case)

	print("")
	for entry in entries:
		var names: Array[String] = []
		for row in entry["roots"]:
			names.append(str((row as Dictionary)["name"]))
		print("  %-16s %s" % [str(entry["title"]), ", ".join(names)])
	quit(h.finish("the launcher's game list"))
