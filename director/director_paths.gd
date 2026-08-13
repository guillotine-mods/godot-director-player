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
## Where titles live when the export packaged them. `games_dir()` is what to
## ask; this is only the packaged half of its answer.
const GAMES_DIR := "res://games"
const ContainerName := preload("res://director/director_container.gd")
const GameConfig := preload("res://director/game_config.gd")

## Every extension that names a Director container. The list, and the rule that
## `.dxr` and `.dir` are one movie, belong to `director_container.gd` -- this
## used to carry its own copy alongside an identical one in `lingo_value.gd`,
## which is how one rule becomes two that disagree.
const CONTAINER_EXTENSIONS := ContainerName.ALL

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
	if not GameConfig.exists(config_path):
		return false
	var cfg := GameConfig.merged(config_path)
	root = str(cfg.get_value("game", "root", ""))
	boot_movie = str(cfg.get_value("game", "boot_movie", ""))
	root = _override_root(root)
	root = beside_the_executable(root)
	boot_movie = _override_boot(boot_movie)
	return root != "" and boot_movie != ""


## Where the games are, whether they were packaged or shipped beside the binary.
##
## `res://games` when the export carries them, and `<folder holding the
## executable>/games` when it does not. **One answer, because two would be a bug
## waiting**: the launcher lists titles through `KeySites.roots()` and the engine
## opens one through `load_config`, and a build where those disagree shows a menu
## of games that cannot be opened, or opens a game the menu never offered.
##
## In the editor `res://` globalises to the project folder, where `games/` is, so
## this returns the packaged answer and nothing about a development run or any of
## the 62 harnesses changes.
## **Tested by what is in it, not by whether it is there.** `res://games` reports
## as existing inside a `.pck` that contains no game at all -- measured: a desktop
## build whose filter packages only `director_game.cfg` still answers true to
## `dir_exists_absolute("res://games")`, so an existence test picks the packaged
## branch and every title then fails to open with its own folder sitting beside
## the binary. A directory holding no title is not where the games are.
static func games_dir() -> String:
	# In the editor -- and in every `--script` harness run, which is the same
	# feature -- `res://games` is the real folder and there is nothing to decide.
	# Answering the absolute path there would change the `root` string that saves
	# stamp and harnesses compare, for no gain.
	if OS.has_feature("editor"):
		return GAMES_DIR
	# In an export, `res://` cannot be trusted to describe a folder shipped beside
	# the binary. Measured on a Windows build whose pck carries no game: the pck's
	# `res://games` answers `dir_exists_absolute` true *and* lists the loose
	# `rating` directory through `get_directories()`, while `get_files()` inside it
	# returns nothing -- so a check on either existence or subdirectories picks the
	# packaged branch and the container index comes back empty. The absolute path
	# has no such split, so it is asked first and `res://` is the fallback for a
	# build that really did package its games.
	var loose := OS.get_executable_path().get_base_dir().path_join("games")
	return loose if _holds_a_title(loose) else GAMES_DIR


## A directory with at least one title in it. Directories rather than files,
## because a game root is a folder and an empty `games/` is not an answer.
static func _holds_a_title(where: String) -> bool:
	var dir := DirAccess.open(where)
	return dir != null and not dir.get_directories().is_empty()


## The same rule applied to a root that already names a title.
##
## **Why ship the games outside the package at all.** Packaging 3.2 GB of
## containers into the `.pck` makes the games part of the binary: adding a title
## is a rebuild, and the download is one file that must be replaced whole. Beside
## the executable they are ordinary folders -- drop one in, it appears in the
## launcher.
##
## It also decides whether the movies can *save*. These games save by rewriting
## their own container in place (`saveMovie` -> `HEZSAVE.DIR`, `EGOZSAVE.DIR`,
## `Saves.dir`), and a `.pck` is read-only at runtime. Loose on disk they are
## writable, so a saved game works on desktop exactly as it does from source.
##
## Android is the platform this cannot help: there is no folder beside an APK, so
## `res://` stays and the games ride inside the package -- which is why the
## Android preset still filters them in and the desktop one does not. Making the
## games writable there means copying them to `user://`, which is filed on the
## board rather than guessed at here.
## Rewritten against `games_dir()` rather than tested independently, for the same
## reason the launcher's enumeration goes through it: two functions each deciding
## where the games are is how a menu comes to offer a title the engine cannot
## open.
static func beside_the_executable(wanted: String) -> String:
	if wanted == "" or not wanted.begins_with(GAMES_DIR + "/"):
		return wanted
	var games := games_dir()
	if games == GAMES_DIR:
		return wanted
	return games.path_join(wanted.trim_prefix(GAMES_DIR + "/"))


## `--root <name>` on the command line beats the config, for every reader.
##
## This is applied *here*, in the one place the root is read, and not at the one
## call site that happens to want it. `AudioDirector` is an autoload that builds
## its own sound index by calling `load_config()` itself, so an override applied
## only in `preview/boot.gd` moved the movies and left the sounds indexed against
## whatever the config still said -- every lookup missed and the game ran silent.
## The same would be true of any harness, and of anything added later that asks
## the config where the game is. One root, one place, or the parts disagree.
##
## A bare name means a folder under `games/`; a full `res://` path is taken as
## given, so a title stored elsewhere works too. A name that does not exist is
## left to the caller to report -- `resolve` will find nothing and say so with
## the path in hand, which is a better message than one from down here.
##
## **`--save` supplies a root too**, and it is honoured here for exactly the same
## reason `--root` is. A save state carries the game it was taken in, so
##
##     godot --path . -- --save saves/piposh2/beach_bug.json
##
## is meant to be sufficient on its own; if that root were applied in
## `preview/boot.gd` instead, `AudioDirector` -- which calls `load_config()`
## itself -- would index its sounds against whatever the config still said and
## the title would run silent. `--root` beats it, so a save can be forced open
## against another corpus deliberately.
static func _override_root(from_config: String) -> String:
	var wanted := _flag("--root")
	if wanted == "":
		var save := _flag("--save")
		if save != "":
			wanted = _root_from_save(save)
	if wanted == "":
		return from_config
	if wanted.begins_with("res://"):
		return wanted
	return GAMES_DIR.path_join(wanted)


## `--boot <container>` on the command line beats the config, for every reader.
##
## The same argument as `--override_root` above, and it exists because half of that
## argument was implemented. `--root` moved the corpus and left the boot movie
## naming a container from the *previous* title, so pinning a root was only ever
## half a pin: `gate.sh` passes `--root piposh2` while the tracked config carries
## `boot_movie = "mainmenu.dir"` (a `rating` container, committed in `399feaaa` as
## a working config), and every harness that does not name its own `--file` fell
## back to a boot movie that does not exist under the pinned root. They do not
## fail -- they load no score and assert over nothing, which is the dark-harness
## failure `gate.sh` warns about two screens further down.
##
## So the rule is the file's own: one question, one place. A reader that honours
## `--root` and not `--boot` disagrees with itself about which title it is running.
static func _override_boot(from_config: String) -> String:
	var wanted := _flag("--boot")
	if wanted == "":
		return from_config
	return wanted


## `--name value` or `--name=value` from the user args, "" when absent.
static func _flag(name: String) -> String:
	var wanted := ""
	var expecting := false
	for arg in OS.get_cmdline_user_args():
		if expecting:
			wanted = arg
			expecting = false
		elif arg.begins_with(name + "="):
			wanted = arg.substr(name.length() + 1)
		elif arg == name:
			expecting = true
	return wanted.strip_edges()


## The game root stamped into a save file.
##
## Read here, by hand, rather than through `scenes/preview/save_files.gd`, which
## is the file that *writes* these two keys. That is a layering choice with a
## cost, and the cost is named so it stays paid: `director/` is the engine and
## must not depend on the preview -- this function is reached from
## `AudioDirector`'s own `load_config()`, before any preview exists -- so the two
## key names `stamp` and `root` are the one thing duplicated across the boundary.
## `tools/save_state.gd` asserts that what this reads out of a real save is what
## `SaveFiles.stamp()` wrote into it, so the pair cannot drift silently; it then
## boots a second process on `--save` alone and checks that a *fresh* `Paths`
## there sees the save's root, which is the question `AudioDirector` asks.
##
## A save that cannot be read answers "", which leaves the configured root in
## place; `preview/boot.gd` is where the unreadable file is reported, with the
## path in hand.
static func _root_from_save(path: String) -> String:
	var resolved := path
	if not FileAccess.file_exists(resolved):
		resolved = ProjectSettings.globalize_path("res://").path_join(path)
	if not FileAccess.file_exists(resolved):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var stamped: Variant = (parsed as Dictionary).get("stamp", {})
	if typeof(stamped) != TYPE_DICTIONARY:
		return ""
	return str((stamped as Dictionary).get("root", ""))


## Absolute path of the movie the game starts from, or "" if it is not there.
func boot_path() -> String:
	return resolve(boot_movie, root)


## Every container under the root, as the root-relative paths `resolve` accepts,
## sorted. For anything that has to *offer* the movies rather than look one up --
## the preview's container picker, a survey tool listing what a title ships.
##
## Out of the same index resolution uses, rather than a second walk. A second
## walk is a second copy of the rule about which extensions name a container and
## which directories are searched, and the two would disagree the first time
## either changed -- which is the same reason `CONTAINER_EXTENSIONS` is one list
## in `director_container.gd` and not one per caller.
##
## The keys are already lower-cased, and that is what `resolve` matches on, so a
## name handed straight back to it resolves to the file it came from -- including
## the subdirectory, which is what tells this game's two `MASTER.CST` apart.
func containers() -> Array[String]:
	_build_index()
	var out: Array[String] = []
	for relative in _index:
		out.append(str(relative))
	out.sort()
	return out


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
	# The spelling the caller used wins if it exists; only then are the other
	# packagings of the same container tried, so a game that ships both a `.dir`
	# and a `.dxr` of one movie still gets the one it asked for.
	for spelling in ContainerName.spellings(wanted):
		var hit := _lookup(spelling, from_dir)
		if hit != "":
			return hit
	return ""


func _lookup(wanted: String, from_dir: String) -> String:
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
		# at the root and under PIP2DATA, and they are not the same file.
		#
		# The directory decides, and it is reached here rather than earlier
		# because a linked cast names itself by its authoring path —
		# `macintosh hd:pip2 full:master.cst` — which matches no directory that
		# still exists. Only the filename survives, so the movie asking is the
		# only thing left that can say which copy it meant.
		if hits.size() > 1 and from_dir != "":
			for hit in hits:
				if str(hit).get_base_dir() == from_dir:
					return hit
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
	var out := _drop_root_prefix(name.strip_edges())
	out = out.replace("\\", "/").replace(":", "/")
	while out.begins_with("@/") or out.begins_with("/"):
		out = out.substr(out.find("/") + 1)
	return out


## A reference that already names the game root drops it and becomes root-relative.
##
## **The engine hands the movie absolute paths, and the movie hands them back.**
## `the moviePath` and `the pathName` both answer `preview.movie_path()`, which is
## a `res://` path, and Lingo concatenates onto it: `go(1, the moviePath &
## "tennis.dir")` is written 8 times in `reference/lingo/`, and Magic Hat's
## `utils.cst` stores the same string in `gCDpath` whenever the ini's `CDPATH=` is
## blank -- which the recovered `magichat.ini` blanks deliberately -- so
## `CDpath() & DirChar() & "magichat"` measures as
## `res://test-games/itamar-magichat/\magichat`.
##
## Without this those still resolved, and that is the danger rather than the
## reassurance: `_strip_decoration` turns the `:` of `res://` into a separator, so
## the whole absolute path became a tail no index key could match and the answer
## came out of `_by_name`, the **bare filename** last resort. That resort exists
## for linked casts naming an authoring path that no longer exists
## (`macintosh hd:pip2 full:master.cst`), where the filename is genuinely all that
## survives; reaching it with a path that is exactly right is how `MASTER.CST` at
## the root and `MASTER.CST` under `PIP2DATA` become a coin toss with a
## `push_warning` on it. Dropping the prefix first makes the fully-qualified case
## resolve through `_index` on its own key, which is the one lookup that cannot
## pick the wrong copy.
##
## **This is the port's `findAbsolutePath`, and the reference puts it first for
## the same reason.** `util.cpp:findPath` tries `findAbsolutePath(testPath)`
## before it searches the current folder, the game root or any search path -- a
## reference that already says where it is is not a partial match to be fuzzed.
##
## **The ambiguity half is unverified against this corpus and implemented anyway.**
## Five of the eight roots ship a duplicated container basename
## (`master.cst` in `piposh`, `piposh-en`, `piposh-ru`, `piposh2`; `texts.cst` in
## two of those; `same.cst` in `itamar-magichat`), and every one of them is a
## *cast*, while the fully-qualified references measured today (`the moviePath &
## "<movie>"`, 8 sites in `reference/lingo/`) all name movies that are unique. So
## no shipped title currently resolves the wrong copy. The path that would --
## `SetCastsFileName`'s `castLib(N).fileName = ConvertToPath(str)`, where
## `ConvertToPath` expands `CD$` to exactly the engine path this function strips
## -- is one `[CAST]` section in one ini away, and is dead only because the
## recovered `magichat.ini` has no such section.
##
## Case-insensitive and separator-insensitive for the same reason the index is:
## the caller's spelling comes from a Lingo string built out of `DirChar()`, so it
## may well arrive with backslashes where `root` has forward ones. A name that
## does not begin with the root is returned untouched, so every relative reference
## -- which is nearly all of them -- reaches the rest of the pipeline unchanged.
func _drop_root_prefix(name: String) -> String:
	if root == "":
		return name
	var base := root.replace("\\", "/").trim_suffix("/").to_lower()
	var probe := name.replace("\\", "/").to_lower()
	if not probe.begins_with(base + "/"):
		return name
	return name.substr(base.length() + 1)
