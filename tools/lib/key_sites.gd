extends RefCounted
## Which keys a Director title's own scripts reach for, measured from the title.
##
##   const KeySites := preload("res://tools/lib/key_sites.gd")
##   var sites := KeySites.for_root("res://games/rating")
##   sites.codes.has(109)   # -> true; `the keyCode = 109` is tested 48 times
##
## The preview shares a keyboard with the movie, so "is this key free" is a
## question about the *game*, and the only honest answer comes from reading its
## scripts. It used to be answered from a list someone swept out of
## `reference/lingo/` once and wrote into a constant -- and `reference/lingo/`
## holds Piposh 2 and nothing else, so the answer was right for one title out of
## six. Rating tests `the keyCode = 109` at 48 sites; 109 is F10, which is where
## the preview's pause binding sat, chosen from a band that list said was empty.
##
## So the measurement is a function of the root rather than a transcript of one.
## `tools/debug_bindings.gd` runs it over **every** game under `games/`, because
## a binding is safe or unsafe for the whole engine and not for whichever title
## the config happens to be pointed at.
##
## The Lingo source lives in the `CASt` member records, not in `Lscr` -- see
## `tools/director_peek.gd`. Reading it is a cast parse per container, which is
## seconds per title; nothing here is on a runtime path.

const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Paths := preload("res://director/director_paths.gd")

## Where the games live. One entry per directory, which is what `--root` names.
const GAMES_DIR := "res://games"

## How a script can ask for the keyboard at all, as label -> pattern. Matched
## against lower-cased source, so the patterns are lower-case. Deliberately loose
## about whitespace: this is what an author typed, not something normalised.
##
## `the key` has to refuse `the keyCode`, `the keyDownScript` and the rest, which
## is what the negative lookahead is for.
const ASKS := {
	"on keyDown": "(?m)^\\s*on\\s+keydown\\b",
	"on keyUp": "(?m)^\\s*on\\s+keyup\\b",
	"the keyDownScript": "the\\s+keydownscript",
	"the keyUpScript": "the\\s+keyupscript",
	"when keyDown then": "when\\s+keydown\\s+then",
	"when keyUp then": "when\\s+keyup\\s+then",
	"the key": "the\\s+key\\s*(?![a-z])",
	"the keyCode": "the\\s+keycode",
	"dontPassEvent": "dontpassevent",
}

## `the key = "x"` -- the character a script compares against, which is a key the
## player has to be able to type.
const CHAR_PATTERN := "the\\s+key\\s*(?![a-z])\\s*=\\s*\"([^\"]*)\""

## `the keyCode = 109`, quoted or not. Director stringifies the comparison in
## about half these scripts and not in the other half.
const CODE_PATTERN := "the\\s+keycode\\s*=\\s*\"?(\\d+)\"?"


## Every game root under `games/`, as `res://games/<name>` paths, sorted.
##
## Discovered rather than listed, so a title added to the repository is measured
## without anything here being edited -- which is the whole failure this replaces.
static func roots() -> Array[String]:
	var out: Array[String] = []
	# Through `DirectorPaths`, so the launcher lists exactly the titles the
	# engine can open: in an export that ships its games beside the binary
	# rather than inside the `.pck`, `res://games` does not exist and a menu
	# built from it would be empty.
	var games: String = DirectorPaths.games_dir()
	var dir := DirAccess.open(games)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append(games.path_join(sub))
	out.sort()
	return out


## What one title tests, as:
##
##   {
##     "root": "res://games/rating",
##     "containers": 118,
##     "asks":  {"the keyCode": 226, ...},          label -> how many sites
##     "codes": {109: ["arcade1.dir #270 NORMKEYS1", ...]},  Mac code -> sites
##     "chars": {"h": ["batzegoz.dir #6", ...]},             character -> sites
##   }
##
## `only` restricts the scan to one container, for looking at a single movie.
static func for_root(root: String, only: String = "") -> Dictionary:
	var paths := Paths.new()
	paths.root = root
	var wanted: Array = [only] if only != "" else paths.containers()

	var asks: Dictionary = {}
	for label in ASKS:
		var re := RegEx.new()
		re.compile(str(ASKS[label]))
		asks[label] = re
	var char_re := RegEx.new()
	char_re.compile(CHAR_PATTERN)
	var code_re := RegEx.new()
	code_re.compile(CODE_PATTERN)

	var out := {
		"root": root, "containers": 0,
		"asks": {}, "codes": {}, "chars": {}, "lines": {},
	}
	for relative in wanted:
		var path := paths.resolve(str(relative))
		if path == "":
			continue
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var cast := Cast.new()
		if not cast.open(f):
			f.close()
			continue
		out["containers"] = int(out["containers"]) + 1
		for number in cast.member_numbers():
			var m: Dictionary = cast.member(number)
			var source := str(m.get("source", ""))
			if source.strip_edges() == "":
				continue
			var lowered := source.to_lower()
			var where := "%s #%d %s" % [relative, number, m.get("name", "")]
			for label in asks:
				var re: RegEx = asks[label]
				var found := re.search_all(lowered)
				if found.is_empty():
					continue
				out["asks"][label] = int((out["asks"] as Dictionary).get(label, 0)) + found.size()
				var lines: Array = (out["lines"] as Dictionary).get(label, [])
				for hit in found:
					lines.append("%s | %s" % [where, line_at(source, hit.get_start())])
				out["lines"][label] = lines
			for hit in char_re.search_all(lowered):
				_add(out["chars"], hit.get_string(1), where)
			for hit in code_re.search_all(lowered):
				_add(out["codes"], int(hit.get_string(1)), where)
		f.close()
	return out


## The whole source line a match landed in, so a hit reads as Lingo rather than
## as a byte offset.
static func line_at(source: String, offset: int) -> String:
	var start := source.rfind("\n", offset) + 1
	var end := source.find("\n", offset)
	if end < 0:
		end = source.length()
	return source.substr(start, end - start).strip_edges()


static func _add(into: Dictionary, key: Variant, site: String) -> void:
	var seen: Array = into.get(key, [])
	seen.append(site)
	into[key] = seen
