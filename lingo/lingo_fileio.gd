extends RefCounted
## The **FileIO Xtra** — Director's file access, as `new(xtra("FileIO"))` gives
## it to a movie (§7.3).
##
## Not one of the 130 names by itself, and worth more than most of them: two
## unfamiliar titles pointed at this engine are blocked on it *at startup*, both
## in the same way. `itamar-park`'s `InitProgram` opens `safari.ini`, reads it
## into a field and parses `[PATH]` … `[END]` out of it to fill `the searchPaths`
## and choose a language; with no FileIO the field is empty, the `[ENDINI]` test
## fails and the game alerts and stops before its first room.
## `itamar-magichat`'s movie scripts carry `fileexist`, `loadfiletofield`,
## `copyfile`, `deletefile` and `externalfileok`, and it parks on a black
## backdrop. Neither is a Lingo problem: both decompile, parse and compile
## cleanly, and the one missing capability is this.
##
## ## What a caller sees
##
## Every method takes the instance as its first argument -- `openFile(myFile,
## path, 1)` -- because that is how Director spells a method call on an Xtra
## instance, and `myFile.openFile(path, 1)` is the same statement. Both reach
## here through `lingo_interpreter.gd`'s native-object dispatch; neither is a
## builtin and neither may be shadowed by one.
##
## **`status` is the interface, not the return value.** Almost every method
## answers VOID and leaves a code behind, and scripts are written
## `openFile(f, p, 1)` / `if status(f) = 0 then …`. So a wrong code is worse than
## no binding at all: the movie takes a branch nobody wrote. The codes here are
## Mac OS's, which is what the Xtra reports on both platforms -- `-43` file not
## found, `-38` file not open, `-37` bad file name, `-48` duplicate, `-33`
## directory full -- and every method that cannot do its job sets one rather than
## leaving the last one standing.
##
## ## Reading
##
## Paths are resolved through the engine's own layer rather than opened
## literally, and that is what makes a 1997 path work at all: these movies build
## `the pathName & "DATA\\safari.ini"`, rewrite `\` to the platform separator,
## and hand over something that names a directory nobody has any more. `resolve`
## below does what `DirectorPaths` does for containers -- case-insensitive
## matching on the *tail* of the path, against an index of everything under the
## game root -- and then falls back to `the searchPaths`. It is a second index
## rather than a call into that one because `DirectorPaths` indexes containers
## only, and FileIO's whole subject is the files that are not containers.
##
## ## Writing
##
## **Refused in a headless run without `--allow-writes`**, which is
## `preview/movie_save.gd:writes_allowed` exactly and for the same reason: the
## corpus is a set of git submodules that every measurement in `tools/` is taken
## against, and a movie calls `createFile` from its own Lingo without any tool
## asking for it. A refused write sets `-45` (file locked), which is a code the
## Xtra really does report and which a script can branch on, rather than
## pretending the write happened.
##
## **And never outside the game root.** A resolved write target that is not under
## the root is refused with `-37`, whatever the movie asked for. `../` is what
## that guard is for.

const LingoValue := preload("res://lingo/lingo_value.gd")

# ------------------------------------------------------------- the error codes
#
# Mac OS's, because that is what the Xtra reports on Windows too. Named rather
# than written as numbers at the site, because the whole interface is these
# values and a script branches on them.

const OK := 0
## `fnfErr` -- no such file.
const NOT_FOUND := -43
## `fnOpnErr` -- an operation on a file that is not open.
const NOT_OPEN := -38
## `bdNamErr` -- a name this port will not accept, including one that resolves
## outside the game root.
const BAD_NAME := -37
## `dupFNErr` -- `createFile` on a name that is already there.
const DUPLICATE := -48
## `opWrErr` -- already open. `openFile` on an instance that has a file.
const ALREADY_OPEN := -49
## `fLckdErr` -- locked. What a refused write answers, which is the honest
## reading of "this player will not write here".
const LOCKED := -45
## `ioErr` -- the write or read failed at the filesystem.
const IO_ERROR := -36
## `paramErr` -- an argument Director would have rejected.
const PARAM_ERROR := -50

## Director's own message table, as `error(obj, code)` answers it.
const MESSAGES := {
	0: "OK",
	-33: "Directory full",
	-34: "Volume full",
	-35: "Volume not found",
	-36: "I/O Error",
	-37: "Bad file name",
	-38: "File not open",
	-42: "Too many files open",
	-43: "File not found",
	-45: "File is locked or read-only",
	-48: "Duplicate file name",
	-49: "File already open",
	-50: "Parameter error",
	-56: "No such drive",
	-120: "Directory not found",
}

## Modes `openFile` takes: 0 read/write, 1 read, 2 write.
const MODE_READ_WRITE := 0
const MODE_READ := 1
const MODE_WRITE := 2

## Every method this instance answers, in the spelling a script uses. Read by
## `respondsTo` and `messageList`, and it is the *same* list the dispatcher
## consults -- §7.3 is explicit that a script probes with `respondsTo` before
## calling, so a list that disagreed with the dispatch would be worse than none.
const METHODS := [
	"new", "openfile", "closefile", "createfile", "delete",
	"readfile", "readline", "readword", "readchar", "readtoken",
	"writestring", "writereturn",
	"getlength", "getposition", "setposition",
	"filename", "status", "error", "version",
]

## The preview's Lingo host, for the paths and the write guard. Null in a
## harness that builds the Xtra on its own; every method survives that and the
## resolver falls back to the literal path.
var host: Object = null

## The open file's contents, as text, and where in it the read cursor is.
##
## **The whole file is held rather than a `FileAccess` kept open**, and that is a
## decision rather than a shortcut. Director's FileIO reads and writes through
## one cursor over one file, and `readLine`/`readWord`/`readChar` are defined in
## *characters* -- a byte cursor would put `getPosition` and `setPosition` in a
## different unit from the reads, which is exactly the kind of divergence a
## script that seeks and then reads cannot see. These are `.ini` and `.txt`
## files of a few kilobytes.
var _text := ""
var _at := 0
## Where the open file is on disk, resolved. "" when nothing is open.
var _path := ""
## What the movie asked for, which is what `fileName` answers -- Director hands
## back the full path it opened, so this is the resolved one.
var _mode := MODE_READ
var _open := false
## Set by every method, read by `status`. Director's contract, and the reason
## this is a field rather than a return value.
var _status := OK
## Whether anything was written since the file was opened, so `closeFile` only
## touches the disk when it has to.
var _dirty := false


# ------------------------------------------------------------------ the protocol


func lingo_responds_to(method: String) -> bool:
	return METHODS.has(method.to_lower())


func lingo_message_list() -> Array:
	return METHODS.duplicate()


## `[]` for "not mine", `[value]` for "handled". The one-element Array is what
## lets a method answer VOID and still be distinguishable from a name this Xtra
## does not have.
func lingo_perform(method: String, args: Array) -> Array:
	match method.to_lower():
		"new":
			# `new(obj)` on an existing instance is Director's re-init.
			_close_silently()
			_status = OK
			return [self]
		"openfile":
			return [_open_file(_arg_str(args, 0), _arg_int(args, 1, MODE_READ))]
		"createfile":
			return [_create_file(_arg_str(args, 0))]
		"closefile":
			return [_close_file()]
		"delete":
			return [_delete()]
		"readfile":
			return [_read_rest()]
		"readline":
			return [_read_line()]
		"readword":
			return [_read_word()]
		"readchar":
			return [_read_char()]
		"readtoken":
			return [_read_token(_arg_str(args, 0), _arg_str(args, 1))]
		"writestring":
			return [_write(_arg_str(args, 0))]
		"writereturn":
			return [_write("\n")]
		"getlength":
			if not _open:
				_status = NOT_OPEN
				return [0]
			_status = OK
			return [_text.length()]
		"getposition":
			if not _open:
				_status = NOT_OPEN
				return [0]
			_status = OK
			return [_at]
		"setposition":
			if not _open:
				_status = NOT_OPEN
				return [null]
			_at = clampi(_arg_int(args, 0, 0), 0, _text.length())
			_status = OK
			return [null]
		"filename":
			# Director answers the full path of the open file, and "" for none.
			# `status` is deliberately *not* set here: a script asks this to build
			# a message after a failure, and clearing the code it is about to
			# report would be the wrong help.
			return [_path]
		"status":
			return [_status]
		"error":
			return [message_for(_arg_int(args, 0, _status))]
		"version":
			# The Xtra's own version string. 7.0 is what a D7-era FileIO answers;
			# nothing can check it against a real one here, and a movie that
			# branches on it gets a plausible modern answer rather than 0.
			return ["7.0"]
	return []


## `error(obj, code)`. Public because the code table is the interface and a
## harness asserting a failure should name it the way a movie would.
static func message_for(code: int) -> String:
	return str(MESSAGES.get(code, "Unknown error %d" % code))


# ------------------------------------------------------------------- the files


func _open_file(name: String, mode: int) -> Variant:
	if _open:
		_status = ALREADY_OPEN
		return null
	if name.strip_edges() == "":
		_status = BAD_NAME
		return null
	var wants_write := mode == MODE_WRITE or mode == MODE_READ_WRITE
	var found := resolve(host, name)
	if found == "":
		if not wants_write:
			_status = NOT_FOUND
			return null
		# Write or read/write on a name that is not there: Director creates it.
		return _create_file(name)
	if wants_write and not _writable(found):
		return null
	_path = found
	_mode = mode
	_text = _read_whole(found)
	_at = 0
	_open = true
	_dirty = false
	_status = OK
	return null


func _create_file(name: String) -> Variant:
	if _open:
		_status = ALREADY_OPEN
		return null
	if name.strip_edges() == "":
		_status = BAD_NAME
		return null
	if resolve(host, name) != "":
		_status = DUPLICATE
		return null
	var target := writable_target(host, name)
	if target == "":
		_status = BAD_NAME
		return null
	if not _writable(target):
		return null
	_path = target
	_mode = MODE_READ_WRITE
	_text = ""
	_at = 0
	_open = true
	_dirty = true
	_status = OK
	return null


func _close_file() -> Variant:
	if not _open:
		_status = NOT_OPEN
		return null
	if _dirty and not _flush():
		return null
	_close_silently()
	_status = OK
	return null


func _delete() -> Variant:
	if not _open:
		_status = NOT_OPEN
		return null
	if not _writable(_path):
		return null
	var absolute := ProjectSettings.globalize_path(_path)
	var err := DirAccess.remove_absolute(absolute)
	_close_silently()
	_status = OK if err == OK else IO_ERROR
	return null


func _close_silently() -> void:
	_open = false
	_dirty = false
	_text = ""
	_at = 0
	_path = ""


## Write the held text back. False when it failed, with `_status` already set.
func _flush() -> bool:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		_status = IO_ERROR
		return false
	f.store_string(_text)
	f.close()
	_dirty = false
	return true


# -------------------------------------------------------------------- the reads
#
# All of them are refused on a file opened for writing only, which is Director's
# rule and is the difference between an empty string and an error a script can
# see.


func _read_rest() -> String:
	if not _readable():
		return ""
	var out := _text.substr(_at)
	_at = _text.length()
	_status = OK
	return out


## Up to and including the next line break. Director's FileIO returns the
## RETURN with the line, which is what makes `readLine` in a loop reassemble the
## file exactly; the port's own line separator is "\n" (`LingoValue.split_lines`
## accepts all three and joins with that), so that is what is returned.
func _read_line() -> String:
	if not _readable():
		return ""
	var stop := _text.find("\n", _at)
	var out := ""
	if stop < 0:
		out = _text.substr(_at)
		_at = _text.length()
	else:
		out = _text.substr(_at, stop - _at + 1)
		_at = stop + 1
	_status = OK
	return out


func _read_word() -> String:
	if not _readable():
		return ""
	while _at < _text.length() and _is_space(_text[_at]):
		_at += 1
	var from := _at
	while _at < _text.length() and not _is_space(_text[_at]):
		_at += 1
	_status = OK
	return _text.substr(from, _at - from)


func _read_char() -> String:
	if not _readable():
		return ""
	if _at >= _text.length():
		_status = OK
		return ""
	var out := _text[_at]
	_at += 1
	_status = OK
	return out


## `readToken(obj, skip, break)`: skip any character in `skip`, then read until
## a character in `break`. The break character is consumed and not returned,
## which is the Xtra's own behaviour and what makes a token loop terminate.
func _read_token(skip: String, brk: String) -> String:
	if not _readable():
		return ""
	while _at < _text.length() and skip.contains(_text[_at]):
		_at += 1
	var from := _at
	while _at < _text.length() and not brk.contains(_text[_at]):
		_at += 1
	var out := _text.substr(from, _at - from)
	if _at < _text.length():
		_at += 1
	_status = OK
	return out


func _write(text: String) -> Variant:
	if not _open:
		_status = NOT_OPEN
		return null
	if _mode == MODE_READ:
		# Director reports a write to a read-only handle rather than dropping it.
		_status = LOCKED
		return null
	if not _writable(_path):
		return null
	# At the cursor, overwriting what is there -- FileIO has one cursor for both
	# directions and `writeString` is not an append.
	var head := _text.substr(0, _at)
	var tail_at := mini(_at + text.length(), _text.length())
	_text = head + text + _text.substr(tail_at)
	_at += text.length()
	_dirty = true
	_status = OK
	return null


func _readable() -> bool:
	if not _open:
		_status = NOT_OPEN
		return false
	if _mode == MODE_WRITE:
		_status = LOCKED
		return false
	return true


static func _is_space(c: String) -> bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"


## The file's text, with line endings normalised to "\n".
##
## Director hands back the bytes and its own line separator is CR; this port's
## chunk machinery accepts all three and joins with "\n"
## (`LingoValue.split_lines`), so a file read here and put into a field has to
## arrive in that spelling or `line 3 of field "x"` counts the file as one line.
static func _read_whole(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var raw := f.get_as_text()
	f.close()
	return raw.replace("\r\n", "\n").replace("\r", "\n")


# ------------------------------------------------------------------- the paths


## Whether this player may write to `path` at all, setting `_status` when not.
##
## Two guards, different questions, and the **target** is asked about first. The
## root test is about the path: a movie that builds
## `the pathName & "..\\..\\something"` must not reach outside the game, and that
## is a bad name rather than a lock, whatever the run allows.
## `MovieSave.writes_allowed` is about the *run* -- a headless harness must not
## modify the corpus it measures, which is six git submodules -- and answers
## `-45`, a real Xtra code meaning locked. Asking the run first made every
## out-of-root write report as locked in a gate run and as a bad name in a real
## session, which is one statement giving two answers.
func _writable(path: String) -> bool:
	if not under_root(host, path):
		_status = BAD_NAME
		return false
	if not MovieSave.writes_allowed():
		_status = LOCKED
		return false
	return true


const MovieSave := preload("res://scenes/preview/movie_save.gd")


## Where the game's files are, or "" when there is no host to ask.
static func game_root(host_object: Object) -> String:
	if host_object == null:
		return ""
	var preview = host_object.get("preview")
	if preview == null:
		return ""
	var paths = preview.get("_paths")
	if paths == null:
		return ""
	return str(paths.root).trim_suffix("/")


static func under_root(host_object: Object, path: String) -> bool:
	var root := game_root(host_object)
	if root == "":
		# No host: a harness driving the Xtra directly. It has already chosen the
		# path it is handing over, so there is nothing to protect it from.
		return true
	return path.begins_with(root + "/")


## Director's path spelling, normalised. `\` is Windows, `:` is the Mac's, and
## these movies rewrite one into the other at run time from `the itemDelimiter`;
## both become `/` here, which is what every path in this engine uses.
##
## **Godot's own schemes are protected**, and that is not a detail: `res://` and
## `user://` contain a colon, so a blind `:` -> `/` turns `user://x.ini` into
## `user///x.ini` and every read of a path this port produced itself fails with
## "file not found". Measured exactly that way -- the harness's own fixture, read
## back through Lingo, answered -43.
static func normalise(path: String) -> String:
	var text := path.strip_edges()
	for scheme in ["res://", "user://"]:
		if text.begins_with(scheme):
			return scheme + text.substr(scheme.length()).replace("\\", "/").replace(":", "/")
	return text.replace("\\", "/").replace(":", "/")


## An existing file for `name`, or "".
##
## Three tries, widest last, and the order is the reason this resolves a 1997
## path at all:
##
##   1. the path as given, if it exists -- an absolute `res://` or `user://` one
##      from a harness, or a name that happens to be right
##   2. the tail of the path, matched case-insensitively against every file under
##      the game root. A movie's `the pathName & "DATA\\safari.ini"` carries a
##      directory that no longer exists in front of a tail that does.
##   3. the same tail under each entry of `the searchPaths`, which is where
##      `itamar-park` puts its own media directories once it has read its ini.
##
## Case-insensitive on the *tail* rather than `FileAccess.file_exists` on the
## whole thing, for the reason `DirectorPaths.resolve` gives at its own: that
## call is case-insensitive on Windows and not on Linux or Android, so building
## the path from the caller's spelling "works" on the desktop and hands back a
## name the phone cannot open.
static func resolve(host_object: Object, name: String) -> String:
	var wanted := normalise(name)
	if wanted == "":
		return ""
	# **`FileAccess.file_exists` is case-insensitive on Windows, and that makes it
	# the wrong first question.** Asked for `arcade.ini` where the file is
	# `Arcade.ini`, it answers true, and this returned the *requested* spelling --
	# so the engine opened a path that does not exist as written. Godot says so
	# itself: "Case mismatch opening requested file … This file will not open when
	# exported to other case-sensitive platforms." Which is the whole problem: it
	# works here and fails on Android and Linux, and the failure is a title that
	# reads no config and hangs on a frame rather than an error anyone can see.
	#
	# The index below is built from the names the filesystem actually reports, so
	# it gives back the real spelling. It is consulted **first, for everything** --
	# including `res://`, which is where a game root lives and therefore exactly
	# where the mis-cased answer came from. Exempting the scheme was the first
	# attempt at this and changed nothing for that reason.
	var index := _index_for(game_root(host_object))
	var tail := wanted.to_lower()
	while tail != "":
		if index.has(tail):
			return str(index[tail])
		var cut := tail.find("/")
		if cut < 0:
			break
		tail = tail.substr(cut + 1)
	# Last, not first: an absolute path outside the game root -- a harness naming
	# a scratch file, or a title reaching for something beside the executable --
	# has no index to be found in, and the literal test is the only answer left.
	# Reaching it means the index already failed, so it can no longer shadow a
	# correctly-cased hit with a mis-cased one.
	if FileAccess.file_exists(wanted):
		return wanted
	return ""


## Where a write should go for `name`: an existing file if there is one,
## otherwise the game root joined with the name's last element.
##
## The *filename only*, deliberately. A movie naming a directory that does not
## exist here would otherwise have its file written nowhere, and creating the
## 1997 directory tree to satisfy it is not this port's job.
static func writable_target(host_object: Object, name: String) -> String:
	var found := resolve(host_object, name)
	if found != "":
		return found
	var wanted := normalise(name)
	# **A path this engine could open on its own is taken literally**, and that
	# is what keeps the root guard from being dead code. Folding every request
	# into the game root -- which the first version did -- meant `user://x` became
	# `<root>/x`, so nothing could ever be *outside* the root and the `-37` arm
	# could not fire. A guard that cannot fire is the shape this whole port keeps
	# being bitten by.
	if wanted.begins_with("res://") or wanted.begins_with("user://"):
		return wanted
	var root := game_root(host_object)
	var bare := wanted.get_file()
	if bare == "" or bare == "." or bare == "..":
		return ""
	if root == "":
		return bare
	# A 1997 relative path names a directory tree that is not here. The file goes
	# to the game root under its own name rather than nowhere; creating the
	# authored directory tree to satisfy it is not this port's job.
	return "%s/%s" % [root, bare]


## Every file under a root, keyed by lower-cased relative path. Built once per
## root and cached, because a directory walk is the expensive part and the tree
## does not change while the movie runs.
##
## Its own index rather than `DirectorPaths`'s, because that one holds
## *containers* -- `.dir`, `.cst` and their packagings -- and FileIO's whole
## subject is the files that are not containers.
static var _indexes: Dictionary = {}


static func _index_for(root: String) -> Dictionary:
	if root == "":
		return {}
	if _indexes.has(root):
		return _indexes[root]
	var index: Dictionary = {}
	_scan(root, "", index)
	_indexes[root] = index
	return index


static func _scan(dir_path: String, prefix: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		into[(prefix + str(file_name)).to_lower()] = "%s/%s" % [dir_path, file_name]
	for sub in dir.get_directories():
		_scan("%s/%s" % [dir_path, sub], "%s%s/" % [prefix, sub], into)


## Forget the cached index. A harness that writes a file and then looks for it
## needs this, and so does anything that changes the root.
static func forget_index() -> void:
	_indexes.clear()


# ------------------------------------------------------------------- arguments


static func _arg_str(args: Array, at: int) -> String:
	return LingoValue.to_str(args[at]) if at < args.size() else ""


static func _arg_int(args: Array, at: int, fallback: int) -> int:
	return LingoValue.to_int(args[at]) if at < args.size() else fallback


func _to_string() -> String:
	return "<FileIO %s>" % (_path if _open else "closed")
