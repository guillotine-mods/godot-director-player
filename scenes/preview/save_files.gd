extends RefCounted
## Where a save state lives on disk, what is stamped on it, and the two dialogs.
##
## `preview/save_state.gd` decides *what* a save contains. This decides where it
## goes, whether the file in front of you was written by this engine against this
## game, and how a name is asked for.
##
## ## Layout
##
##     saves/<game>/<name>.json      the state
##     saves/<game>/<name>.png       what the stage looked like
##
## `<game>` is the folder name under `games/`, so two titles cannot overwrite
## each other's quick-save, and `saves/` is gitignored — these are somebody's
## session of a game that is not ours to redistribute, the same reason
## `.snapshots/` is ignored.
##
## ## The stamp, and why it is not decoration
##
## A save is a pile of member numbers, channel numbers and frame indices, and
## every one of them is meaningless against the wrong game: member 14 of another
## title's cast is a real member showing the wrong thing, which reads as
## corruption rather than as a mismatch. So the game root is stamped and a
## mismatch is **refused**.
##
## The engine commit is stamped too and a mismatch **warns**, loudly, rather than
## refusing. That asymmetry is deliberate: the user of this feature is fixing
## bugs in the engine, so almost every save they load will have been written by a
## different commit than the one they are running — refusing would make the
## feature useless on its second day. What the stamp buys is that a save which
## reproduces differently is *explainable* instead of mysterious, which is the
## whole complaint it was added for.
##
## ## The PNG
##
## Written beside every save, through the same framebuffer read the F11 snapshot
## uses (`preview/snapshot.gd:save_png`). Headless Godot never paints, so there
## is nothing to capture there and the save is written without one rather than
## with a black rectangle that looks like a rendering bug.
##
## ## No auto-save
##
## There is none, on purpose, and this note is here so the next session does not
## add one as an obvious improvement. The request was explicit: manual only,
## quick-save and the dialog.

const Snapshot := preload("res://scenes/preview/snapshot.gd")
const SaveState := preload("res://scenes/preview/save_state.gd")

## The saves tree, inside the checkout. Gitignored.
const DIRECTORY := "res://saves"
## Where saves go when `res://` is read-only, which is every exported build. A
## debug build handed to QA can still save; it just saves somewhere writable.
const FALLBACK := "user://saves"
## The quick-save's name. One file per game, overwritten — not a rotating set,
## which was asked for explicitly.
const QUICK := "quicksave"
const EXTENSION := ".json"


# -------------------------------------------------------------------- paths

## `saves/<game>` for the game this preview is running, created if it is not
## there. Falls back to `user://` when the checkout cannot be written.
static func directory(host) -> String:
	var game := game_name(host)
	for base in [DIRECTORY, FALLBACK]:
		var path: String = base.path_join(game) if game != "" else base
		var real := ProjectSettings.globalize_path(path)
		if DirAccess.dir_exists_absolute(real):
			return path
		if DirAccess.make_dir_recursive_absolute(real) == OK:
			return path
	return FALLBACK


## The folder name under `games/`, which is what `<game>` means in the layout.
static func game_name(host) -> String:
	if host._paths == null:
		return ""
	return str(host._paths.root).trim_suffix("/").get_file()


static func quick_path(host) -> String:
	return directory(host).path_join(QUICK + EXTENSION)


static func png_for(save_path: String) -> String:
	return save_path.trim_suffix(EXTENSION) + ".png"


# ------------------------------------------------------------------ writing

## Capture and write. Returns `{"path":, "png":, "error":}`; `error` is "" on
## success.
##
## The record is captured **by the caller**, before this is reached, whenever a
## dialog stands between the keypress and the filename: the state that should be
## saved is the state the key was pressed on, not the state the movie has drifted
## into while somebody typed a name. `write_record` is that half.
static func save(host, path: String) -> Dictionary:
	return write_record(host, path, SaveState.capture(host), Snapshot.grab(host))


## `picture` is what the stage looked like when the state was captured, or null.
## Passed in rather than grabbed here for the same reason the record is: a dialog
## stands between the keypress and the filename on the save-as path, and the
## framebuffer has moved on by the time a name has been typed.
static func write_record(host, path: String, record: Dictionary,
		picture: Image) -> Dictionary:
	record["stamp"] = stamp(host)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"path": path, "png": "",
			"error": "cannot write %s: %s" % [
				path, error_string(FileAccess.get_open_error())],
		}
	# Indented, because a save is read by a person looking for why a bug did not
	# reproduce. The file is a few hundred KB either way.
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	var png := ""
	if picture != null and not picture.is_empty() \
			and picture.save_png(png_for(path)) == OK:
		png = png_for(path)
	return {"path": path, "png": png, "error": ""}


## What was running, and what built it. See the header.
static func stamp(host) -> Dictionary:
	return {
		"commit": engine_commit(),
		"godot": Engine.get_version_info().get("string", ""),
		"game": game_name(host),
		"root": str(host._paths.root) if host._paths != null else "",
		"movie": host.movie_name(),
		"frame": int(host._index),
		"at": Time.get_datetime_string_from_system(),
	}


## The engine commit, read out of `.git` rather than shelled out for.
##
## `git rev-parse HEAD` would need a subprocess, which is one more thing to fail
## on a machine without git on PATH — and the answer is three files away. `HEAD`
## is per-worktree; `refs/heads/*` and `packed-refs` are common to all of a
## repository's worktrees, which is why the lookup below reads `HEAD` from
## `_git_dir()` but resolves the ref itself through `_common_dir()`.
##
## "unknown" when there is no repository, which is every exported build. That is
## an honest answer: the stamp then says nothing rather than saying something
## wrong, and the load reports it as unknown instead of as a mismatch.
static func engine_commit() -> String:
	var git := _git_dir()
	if git == "":
		return "unknown"
	var head := FileAccess.get_file_as_string(git.path_join("HEAD")).strip_edges()
	if head == "":
		return "unknown"
	if not head.begins_with("ref:"):
		return head.substr(0, 40)
	var ref := head.substr(4).strip_edges()
	# The per-worktree directory first, then the common one. Git keeps `HEAD` and
	# a handful of refs (`refs/bisect/*`, `refs/worktree/*`) per worktree and
	# everything else — including `refs/heads/*` — in the common directory, so
	# asking in that order answers both without having to know which kind this is.
	for at in [git, _common_dir(git)]:
		var direct := FileAccess.get_file_as_string(str(at).path_join(ref)).strip_edges()
		if direct != "":
			return direct.substr(0, 40)
	# A ref that has been packed has no file of its own. `packed-refs` is common
	# only; reading both costs nothing and keeps the two loops the same shape.
	for at in [git, _common_dir(git)]:
		for line in FileAccess.get_file_as_string(str(at).path_join("packed-refs")).split("\n"):
			var row := str(line).strip_edges()
			if row.ends_with(" " + ref):
				return row.substr(0, 40)
	return "unknown"


## Where refs live, which is not where `HEAD` lives once there is a worktree.
##
## A linked worktree's gitdir holds `HEAD` and a `commondir` file naming the real
## repository directory, usually relative to the gitdir (`../..`). `refs/heads/*`
## and `packed-refs` are only ever there. Without this the ref lookup above
## searched an empty `refs/` and every save taken in a worktree was stamped
## "unknown" — the one state the mismatch warning at the top of this file cannot
## report.
##
## Returns `git` unchanged for an ordinary checkout, which has no `commondir`.
static func _common_dir(git: String) -> String:
	var pointer := FileAccess.get_file_as_string(git.path_join("commondir")).strip_edges()
	if pointer == "":
		return git
	if pointer.begins_with("/"):
		return pointer
	return git.path_join(pointer).simplify_path()


static func _git_dir() -> String:
	var at := ProjectSettings.globalize_path("res://").trim_suffix("/").path_join(".git")
	if DirAccess.dir_exists_absolute(at):
		return at
	# A worktree: `.git` is a file reading `gitdir: <path>`.
	var pointer := FileAccess.get_file_as_string(at).strip_edges()
	if pointer.begins_with("gitdir:"):
		return pointer.substr(7).strip_edges()
	return ""


# ------------------------------------------------------------------ reading

## Read one back. `{"data":, "error":}` — `data` is empty when `error` is not "".
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"data": {}, "error": "no save at %s" % path}
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {"data": {}, "error": "%s is empty" % path}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"data": {}, "error": "%s is not a save file" % path}
	return {"data": parsed, "error": ""}


## Is this save loadable here? `{"refuse":, "warn":}`, both "" when it is clean.
##
## Refused on the game, warned on the commit — see the header for why those two
## are not the same severity.
static func check(host, data: Dictionary) -> Dictionary:
	var stamped: Dictionary = data.get("stamp", {})
	var refuse := ""
	var warn := ""
	var want_game := str(stamped.get("game", ""))
	var have_game := game_name(host)
	if want_game != "" and have_game != "" and want_game.to_lower() != have_game.to_lower():
		refuse = ("this save is of %s and %s is running. Boot it directly instead:"
			+ "  godot --path . -- --save <file>") % [want_game, have_game]
	if int(data.get("version", 0)) != SaveState.VERSION:
		refuse = "save format %s, this engine reads %d" % [
			str(data.get("version", "?")), SaveState.VERSION]
	var want_commit := str(stamped.get("commit", ""))
	var have_commit := engine_commit()
	if want_commit == "" or want_commit == "unknown" or have_commit == "unknown":
		warn = "this save carries no engine commit, so a divergence cannot be explained"
	elif want_commit != have_commit:
		warn = "this save was written by %s and %s is running — a difference in what it reproduces is a difference in the engine" % [
			want_commit.substr(0, 12), have_commit.substr(0, 12)]
	return {"refuse": refuse, "warn": warn}


## A save named on the command line, resolved the way a person would write it: a
## path as given, else a bare name inside this game's saves folder.
static func resolve(host, wanted: String) -> String:
	var name := wanted.strip_edges()
	if name == "":
		return ""
	if FileAccess.file_exists(name):
		return name
	var absolute := ProjectSettings.globalize_path("res://").path_join(name)
	if FileAccess.file_exists(absolute):
		return absolute
	var bare: String = name if name.ends_with(EXTENSION) else name + EXTENSION
	var inside := directory(host).path_join(bare.get_file())
	if FileAccess.file_exists(inside):
		return inside
	return ""


# ------------------------------------------------------------------ dialogs

## Ask for a filename, then call `then` with the path chosen. "" is never passed:
## a cancelled dialog calls nothing.
##
## A `FileDialog` in Godot 4 is a `Window`, so it opens beside the stage rather
## than inside the letterboxing transform every child of the preview inherits —
## which is why it is parented to the tree root and not to the preview.
static func ask_where_to_save(host, then: Callable) -> void:
	var dialog := _dialog(host, FileDialog.FILE_MODE_SAVE_FILE, "Save state as")
	dialog.current_file = "state" + EXTENSION
	_show(host, dialog, then)


static func ask_what_to_load(host, then: Callable) -> void:
	_show(host, _dialog(host, FileDialog.FILE_MODE_OPEN_FILE, "Load state"), then)


static func _dialog(host, mode: int, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode as FileDialog.FileMode
	dialog.title = title
	dialog.filters = PackedStringArray(["*.json ; save state"])
	dialog.current_dir = ProjectSettings.globalize_path(directory(host))
	dialog.use_native_dialog = false
	return dialog


static func _show(host, dialog: FileDialog, then: Callable) -> void:
	var tree: SceneTree = host.get_tree()
	if tree == null:
		return
	tree.root.add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		then.call(path)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2i(900, 640))
