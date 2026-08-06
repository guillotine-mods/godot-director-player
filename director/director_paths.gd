class_name DirectorPaths
extends RefCounted
## Where the game lives, and how one movie names another.
##
## The only thing configured about a title is which file boots it; everything
## after that is discovered. A movie that says `go(1, "day1.dir")` means the file
## beside itself, exactly as Director resolved it, so resolution is relative to
## the movie currently playing and only then falls back to the game root.
##
## Names are matched case-insensitively on purpose. The tree ships `MASTER.CST`,
## `strtgame.dir` and `HEZSAVE.DIR` in three different conventions while the
## Lingo spells them however the author typed them, and Windows hides the problem
## that Android would not: a case-sensitive filesystem turns a working desktop
## build into a game that cannot find its own boot movie.

const CONFIG_PATH := "res://director_game.cfg"
const CONTAINER_EXTENSIONS := ["dir", "cst", "dxr", "cxt"]

## Which game, and which file starts it. Empty until a config says otherwise:
## naming a title here would put one game's name in the engine, and the engine
## is meant to run any Director title. `director_game.cfg` ships per game.
var root: String = ""
var boot_movie: String = ""

## Lowercased path relative to `root` -> the real path, for every container
## found under the root. Built once, on first use.
var _index: Dictionary = {}
## Lowercased bare filename -> Array of real paths, the last-resort lookup.
var _by_name: Dictionary = {}
var _indexed := false


## Reads `director_game.cfg`. False means no game is configured, which is a
## setup problem to report rather than something to paper over with a default:
## a built-in fallback would be one title's name living in the engine, and would
## turn "the config is missing" into "the wrong game silently loaded".
func load_config(config_path: String = CONFIG_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return false
	root = str(cfg.get_value("game", "root", ""))
	boot_movie = str(cfg.get_value("game", "boot_movie", ""))
	return root != "" and boot_movie != ""


## Absolute path of the movie the game starts from, or "" if it is not there.
func boot_path() -> String:
	return resolve(boot_movie, root)


## Resolve a Director file reference the way the original did: beside the movie
## that named it, then at the game root, then anywhere under it. Returns "" when
## nothing matches, which is a missing file rather than an error to raise.
##
## Every answer comes out of the scanned index, so what is returned is always a
## real directory entry with the filesystem's own spelling. Building the path
## from the caller's spelling and testing `FileAccess.file_exists` looks
## equivalent and is not: that call is case-insensitive on Windows, so asking for
## `master.cst` "succeeds" and hands back a name no case-sensitive platform will
## open — the desktop build works and the Android one cannot find its own cast.
func resolve(name: String, from_dir: String = "") -> String:
	var wanted := _strip_decoration(name)
	if wanted == "":
		return ""
	_build_index()
	# A reference may carry its own subpath ("MOVIES:x.dir" once normalised), so
	# the whole tail is matched, not only the filename.
	var tail := wanted.to_lower()

	# Beside the movie that named it, then the root, then anywhere under it.
	if from_dir != "":
		var beside := (_relative_to_root(from_dir) + tail).to_lower()
		if _index.has(beside):
			return _index[beside]
	if _index.has(tail):
		return _index[tail]
	var bare := tail.get_file()
	if _by_name.has(bare):
		var hits: Array = _by_name[bare]
		# Two containers can share a filename: this game ships MASTER.CST twice,
		# at the root and under PIP2DATA, and they are not the same file. Picking
		# the first silently loads whichever the scan met first, so the ambiguity
		# is reported rather than resolved by luck.
		if hits.size() > 1:
			push_warning("%s is ambiguous: %s" % [bare, ", ".join(hits)])
		return hits[0]
	return ""


## A directory under the root, as the "" or "sub/" prefix the index is keyed by.
func _relative_to_root(dir_path: String) -> String:
	var normalised := dir_path.trim_suffix("/")
	var base := root.trim_suffix("/")
	if normalised == base:
		return ""
	if normalised.begins_with(base + "/"):
		return normalised.substr(base.length() + 1) + "/"
	return ""


## Every container under the root, indexed once. Directory walks are the
## expensive part of resolution and the tree does not change while running.
func _build_index() -> void:
	if _indexed:
		return
	_indexed = true
	_scan(root, "")


func _scan(dir_path: String, prefix: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if not CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			continue
		var rel := (prefix + entry).to_lower()
		var real := dir_path.path_join(entry)
		_index[rel] = real
		var bare := entry.to_lower()
		if not _by_name.has(bare):
			_by_name[bare] = []
		_by_name[bare].append(real)
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub), prefix + sub.to_lower() + "/")


## Director wrote paths with Mac colon separators and an `@:` prefix meaning
## "beside the movie". Both mean the same thing here, since resolution is
## already relative, so they are normalised away rather than interpreted.
func _strip_decoration(name: String) -> String:
	var out := name.strip_edges()
	out = out.replace("\\", "/").replace(":", "/")
	while out.begins_with("@/") or out.begins_with("/"):
		out = out.substr(out.find("/") + 1)
	return out
