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


## One entry per title, in release order. A title covering several roots
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
		var entry: Dictionary = out[int(index[title])]
		(entry["roots"] as Array).append(row)
		entry["order"] = _first(int(entry.get("order", 0)),
			int(config.get_value(section, "order", 0)))
	out.append_array(embeds(config))
	return sorted(out)


## The shelf, in the order the games came out.
##
## `order` is a rank and not a year: 1, 2, 3 rather than 1997, 1999, 2001. The
## shelf only ever needs to know which came first, no screen shows the number,
## and a rank is the one form of it nobody has to look up to write down or to
## check. A year would be a research task attached to every title added, and a
## wrong year would sort exactly as confidently as a right one.
##
## The order matters because the alternative is what `KeySites.roots()` hands
## over, which is sorted directory names -- so the third game led the shelf, and
## the 3D one trailed it for no better reason than being the only entry that is
## not a `games/` directory.
##
## A title with no `order` sorts after every ranked one rather than before them,
## among themselves in root order. Ranking from 1 means an unranked title reads
## as 0 and would otherwise lead the shelf: a title nobody has described yet
## would displace the one the series actually starts with. That is the same
## argument the `title` fallback above makes -- describe what is known -- with
## the failure pointing the other way.
##
## `sort_custom` is not documented as stable, so equal ranks tie-break on the
## entry's own position rather than on the comparator returning false. Without
## it a config that ranked two titles the same -- or ranked none of them, which
## is what this file did before the key existed -- could reshuffle the shelf
## between runs for no reason a player could see.
##
## The position is stamped onto each entry rather than looked up by title. A
## title is not a unique key here and this file is the reason why: `build`
## groups roots *by* title, and an `[embed.*]` naming the same title as a
## `[root.*]` produces two entries with one string between them. A map keyed by
## title would hand both of them the same position and the tie-break would
## quietly become arbitrary again -- the exact failure it is here to prevent,
## reintroduced by its own index.
static func sorted(entries: Array[Dictionary]) -> Array[Dictionary]:
	var out := entries.duplicate()
	for i in out.size():
		out[i]["was"] = i
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar := int(a.get("order", 0))
		var br := int(b.get("order", 0))
		if ar != br:
			# Unranked is not rank zero; it is "after every rank".
			if ar == 0 or br == 0:
				return br == 0
			return ar < br
		return int(a.get("was", 0)) < int(b.get("was", 0)))
	for entry in out:
		entry.erase("was")
	return out


## The lower of two ranks, ignoring the absent one.
##
## A title with several roots is one game with several editions -- Piposh has
## Hebrew, English and Russian discs -- and the shelf places the *game*, once.
## Every edition of one title should carry the same rank, so this normally has
## nothing to choose between; it exists so that a config which ranks only the
## Hebrew disc still places the title, instead of the answer depending on which
## edition sorted last by directory name.
static func _first(a: int, b: int) -> int:
	if a == 0:
		return b
	if b == 0:
		return a
	return mini(a, b)


## Titles that are Godot projects rather than Director corpora, from `[embed.*]`.
##
## They carry a `scene` where a disc title carries a `boot`, and the launcher
## branches on exactly that. Kept in the same row shape so the tiles, the
## selection path and `default_root` need no special case: the difference is one
## key, not a second kind of entry.
##
## **Offered only when the pack actually mounted.** A build can legitimately ship
## the Director titles alone -- narrowing `include_filter` is how one title
## ships instead of six -- and in that build the scene behind this tile does not
## exist. A tile that cannot launch is worse than no tile, so the absence is
## read at the source rather than assumed from the config.
##
## The mount is asked about through `ResourceLoader.exists()` on a path *inside*
## the pack, and never through `Piposh3DPack.mounted`. The two say the same
## thing, and only one of them can be said here: naming an autoload is a
## compile-time reference, autoloads register a frame into a `--script` run, and
## `tools/title_list.gd` is exactly such a run. The first version of this
## function named the autoload, and the harness did not fail -- it failed to
## *compile*, so `_init` never reached `quit()` and the gate sat on it until the
## 900s ceiling.
static func embeds(cfg: ConfigFile = null) -> Array[Dictionary]:
	var config := cfg if cfg != null else GameConfig.merged()
	var out: Array[Dictionary] = []
	for section in config.get_sections():
		if not str(section).begins_with("embed."):
			continue
		var scene := str(config.get_value(section, "scene", ""))
		if scene == "" or not ResourceLoader.exists(scene):
			continue
		var name := str(section).substr("embed.".length())
		out.append({
			"title": str(config.get_value(section, "title", name)),
			"order": int(config.get_value(section, "order", 0)),
			"roots": [{
				"name": name,
				"root": "res://titles/%s" % name,
				"boot": "",
				"scene": scene,
				"flag": str(config.get_value(section, "flag", "")),
				"default": true,
			}] as Array[Dictionary],
		})
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
