extends RefCounted
## The **BuddyAPI Xtra** (Gary Smith), as a movie reaches it (§7.3, §19).
##
## ## Why it is here
##
## `test-games/itamar-magichat` is blocked on it and on nothing else. Its
## `ReadConfigLine` is `baReadIni(section, key, EMPTY, gIniFileName)`; unbound,
## the interpreter answers the integer `0`, so the movie's own
## `if tmp = EMPTY then tmp = "intro"` fallback never fires, `#startFrame`
## becomes `0`, and `BehaviorScript 2`'s `go(GlobalInfo(#startFrame))` jumps the
## playhead to the frame it is already on, for ever. That is `bugs.md` 78, and
## it is the reason this file returns a **string** from `baReadIni` and why the
## harness asserts the type rather than the value alone: a movie testing
## `= EMPTY` cannot be handed an integer.
##
## BuddyAPI is a third-party Xtra that hands a Director movie the parts of
## Windows Director never had -- ini files, the registry, the filesystem, window
## handles, the shell. Titles lean on it heavily, which is why this is written
## rather than stubbed, and why the names that are **not** here are enumerated at
## the bottom of this header with a reason each. An absent name is reported by
## the interpreter's unbound-name diagnostic; a name bound to something that
## answers and does nothing is the state this port has shipped as a user-visible
## bug five times, and `baReadIni` answering `0` is the sixth.
##
## ## The shape: builtins, not methods
##
## Unlike FileIO, BuddyAPI's surface is **global**. A movie writes
## `baReadIni(...)` bare, with no instance in front of it -- which is what the
## reference does too (`budapi.cpp` registers every `ba*` name with `HBLTIN` and
## gives the Xtra object itself only `new` and `name`), and what all 46 call
## sites in `itamar-magichat` do. So the arms live in
## `scenes/preview_lingo_host.gd:call_builtin` and route here, and the entry this
## file adds to `xtras_loaded` exists so that `the xtras` and `xtra("BudAPI")`
## agree with the rest of the player about what is loaded. The instance answers
## `name` and nothing else, deliberately: giving it the `ba*` names as methods
## would make `respondsTo` claim a surface the real Xtra does not have.
##
## ## Paths and writes
##
## Both go through `lingo_fileio.gd`, which is not sharing for its own sake:
## these are the same 1997 paths, built the same way by the same authoring house
## (`the pathName & "DATA\\magichat.ini"`), and they resolve by
## case-insensitive tail match against an index of the game root because
## `FileAccess.file_exists` is case-insensitive on Windows and hands back the
## *requested* spelling -- a bug fixed in 91a84057 that must not be reintroduced
## one file over. Folders resolve through the same walk
## (`FileIO.resolve_folder`).
##
## Writes obey the same two guards, in the same order and for the same reasons:
## refused outside the game root always, and refused in a headless run without
## `--allow-writes`, because the corpus is a set of git submodules that every
## measurement in `tools/` is taken against and a movie calls `baWriteIni` from
## its own Lingo without any tool asking for it.
##
## **BuddyAPI has no `status` channel.** FileIO's whole interface is a code left
## behind for the next call to read; BuddyAPI answers 1 or 0 in the return value
## and that is all a script gets. A refused write therefore answers 0 *and* is
## reported through the host's diagnostics, so the reason does not vanish.
##
## ## The ini reader
##
## Windows' `GetPrivateProfileString`, which is what the real Xtra calls:
## sections and keys match case-insensitively, `;` opens a comment, whitespace
## around the key and the value is stripped, and a value wrapped in matching
## single or double quotes has them removed. Absent section, absent key or absent
## file all answer the caller's `Default`.
##
## `baWriteIni` is a read-modify-write of the whole file that keeps every other
## line as it stands -- comments, blank lines, key spelling and the file's own
## line ending. `magichat.ini` is a hand-written file with a long explanatory
## block in it, and a writer that reformatted it would destroy the very thing the
## movie's `FindLine` scan depends on.
##
## `baFlushIni` is the *commit*. Parsed documents are cached here -- 34 read
## sites, and `ReadAllMenusFile` alone reads one 94-line file once per menu
## button -- so the cache is what a flush flushes: it re-commits anything a
## failed write left pending and drops the parse, so the next read comes off the
## disk again. Writes are committed eagerly as well, because a title that never
## flushes must not lose its save; the flush is what *reports* whether the file
## is on disk.
##
## ## What is deliberately absent, and why
##
## Left unbound, so the interpreter reports each by name if a title reaches it,
## rather than answering something invented:
##
##   `baVersion`, `baSysFolder`, `baCpuInfo`, `baMemoryInfo`, `baScreenInfo`,
##   `baDiskInfo`, `baPrinterInfo`, `baFileAttributes`, `baFileDate`,
##   `baFileAge`, `baFileVersion`, `baShortFileName`
##                 each takes an *InfoType* or *format* string whose accepted
##                 values and answer format are not in any source available here.
##                 Guessing one produces a plausible string a movie will then
##                 branch on, which is worse than a reported gap.
##   `baRunProgram`, `baShell`, `baOpenFile`, `baPrintFile`, `baExitWindows`,
##   `baSetDisplay`, `baSetWallpaper`, `baSetScreenSaver`, `baInstallFont`,
##   `baSetSystemTime`, `baCreatePMIcon` and the rest of the Program Manager set
##                 these change the machine, launch programs or shut Windows
##                 down. A movie in a player does not get to do that silently.
##                 `baOpenURL` is the one of this family that *is* bound, because
##                 the corpus calls it -- and it declines and reports rather than
##                 opening a browser.
##   the registry set (`baReadRegString` and the six beside it), the window set
##   (`baFindWindow`, `baSendMsg`, `baWinHandle` …), the Program Manager set
##                 there is no registry, no HWND and no Start Menu to answer
##                 about. The reference stubs all of these too.
##   `baSleep`     would block the player's own frame loop, which is not what a
##                 movie asking the OS to sleep expects to happen to it.
##   `baMsgBox`    answers *which button was pressed*, and a movie branches on
##                 the number. The mapping from BuddyAPI's `Buttons` string to
##                 that number is not sourceable here.
##   `baKeyIsDown`, `baKeyBeenPressed`
##                 take a Windows virtual-key code. Director's own `the keyCode`
##                 is a Mac code and this port's keyboard is built on it; a
##                 mapping written from guesswork would answer for the wrong key.
##   `baCopyXFiles`, `baXCopy`, `baDeleteXFiles`, `baXDelete`,
##   `baFindFirstFile`/`baFindNextFile`/`baFindClose`
##                 well-defined and unbuilt rather than unsourceable: the bulk
##                 and iterator forms of file operations that are here singly.
##                 `docs/ENGINE_TODO.md` carries them.
##   `baPlatform`, `baDiskSpace`
##                 **not BuddyAPI names at all.** The published API has
##                 `baDiskInfo` and nothing called either of these; binding them
##                 would invent a surface rather than port one.
##
## Read for behaviour from `reference/scummvm/lingo/xtras/b/budapi.cpp`, whose
## header block is the published API listing and whose `m_baReadIni` is the only
## body in that file this one agrees with in substance; no code is copied.

const LingoValue := preload("res://lingo/lingo_value.gd")
const FileIO := preload("res://lingo/lingo_fileio.gd")
const MovieSave := preload("res://scenes/preview/movie_save.gd")

## What `xtra("BudAPI")` answers questions about. The real Xtra object carries
## `new` and the `name` property and no operations at all -- every `ba*` name is
## a global builtin -- so this is the whole of the instance surface.
const METHODS := ["new", "name"]

## The Xtra's registered name, as the reference records it (`budapi.cpp`'s
## `xlibName`). `preview_lingo_host.gd:xtra_key` strips the platform extension
## and the Mac path in front of it, so `Macintosh HD:Xtras:BudAPI.x32` and
## `budapi` both find this one. It does **not** strip the `32` of the Win32
## build's file name, so `xtra("budapi32")` reports as an Xtra this player does
## not have -- which is a lookup nothing in the corpus makes, and is the honest
## answer rather than a suffix rule invented here that would also fold
## `xtra("Flash32")` into `xtra("Flash")`.
const XTRA_NAME := "BudAPI"

## Set by `lingo_xtra.gd` on every instance it makes.
var host: Object = null


# ------------------------------------------------------------------ the protocol


func lingo_responds_to(method: String) -> bool:
	return METHODS.has(method.to_lower())


func lingo_message_list() -> Array:
	return METHODS.duplicate()


func lingo_perform(method: String, _args: Array) -> Array:
	match method.to_lower():
		"new":
			return [self]
		"name":
			return [XTRA_NAME]
	return []


func _to_string() -> String:
	return "<BudAPI>"


# ================================================================== ini files
#
# The three the corpus is blocked on. Every one of them takes the ini file as
# its *last* argument, which is BuddyAPI's own ordering and the opposite of
# FileIO's.


## `baReadIni(Section, Keyname, Default, IniFile)` -- the value, or `Default`.
##
## **Always a String.** `bugs.md` 78 is the whole reason this file exists and it
## was an integer `0` reaching a script that tested `= EMPTY`.
static func read_ini(host_object: Object, args: Array) -> String:
	var section := _arg(args, 0)
	var key := _arg(args, 1)
	var fallback := _arg(args, 2)
	var file := _arg(args, 3)
	if key == "":
		return fallback
	var path := FileIO.resolve(host_object, file)
	if path == "":
		# No such file -- including the case this port meets first, where the
		# movie never ran the handler that sets its ini path and hands over VOID.
		# Director's Xtra answers the caller's default for a missing file, and
		# that default is what unsticks `magichat`: its own `"intro"` fallback.
		return fallback
	var lines := _document(path)
	var want_section := section.to_lower()
	var want_key := key.to_lower()
	var in_section := section == ""
	for raw in lines:
		var line := str(raw).strip_edges()
		if line == "" or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			in_section = line.substr(1, line.length() - 2).strip_edges().to_lower() \
				== want_section
			continue
		if not in_section:
			continue
		var split := line.find("=")
		if split < 0:
			continue
		if line.substr(0, split).strip_edges().to_lower() != want_key:
			continue
		return _unquote(line.substr(split + 1).strip_edges())
	return fallback


## `baWriteIni(Section, Keyname, Value, IniFile)` -- 1 when the value is stored
## and on disk, 0 when the write was refused or failed.
##
## Read-modify-write of the whole file, keeping every other line exactly as it
## stands. The alternative -- rewriting the file from a parsed model -- loses
## comments, and `magichat.ini`'s comments are load-bearing for the movie's own
## `FindLine` scan.
static func write_ini(host_object: Object, args: Array) -> int:
	var section := _arg(args, 0)
	var key := _arg(args, 1)
	var value := _arg(args, 2)
	var file := _arg(args, 3)
	if key == "" or file == "":
		return 0
	var path := FileIO.resolve(host_object, file)
	var creating := path == ""
	if creating:
		path = FileIO.writable_target(host_object, file)
	if path == "" or not _may_write(host_object, path, "baWriteIni"):
		return 0
	var lines := _document(path) if not creating else PackedStringArray()
	_set_key(lines, section, key, value)
	_docs[path] = {"lines": lines, "eol": _eol_of(path), "pending": true}
	if not _commit(path):
		_report(host_object, "baWriteIni could not write \"%s\"" % path)
		return 0
	if creating:
		# The resolver's index is built once per root, so a file this call has
		# just created is invisible to the next `baReadIni` until it is recorded.
		# **Recorded rather than rebuilt**: a rebuild cannot see it either, for
		# the reason `FileIO.note_file` gives at length.
		FileIO.note_file(path, true)
	return 1


## `baFlushIni(IniFile)` -- commit, and drop the cached parse.
##
## Not a no-op and not a formality. Writes above are committed eagerly, because
## a title that writes and never flushes must not lose its save -- so what is
## left for this call is the two things a flush is actually for: re-commit
## anything a failed write left pending, and forget the parsed document so the
## next `baReadIni` reads the disk rather than this process's memory. It answers
## 1 only when the named file is on disk with nothing pending against it.
static func flush_ini(host_object: Object, args: Array) -> int:
	var file := _arg(args, 0)
	var path := FileIO.resolve(host_object, file)
	if path == "":
		return 0
	var held: Variant = _docs.get(path, null)
	if held != null and bool((held as Dictionary).get("pending", false)):
		if not _may_write(host_object, path, "baFlushIni") or not _commit(path):
			return 0
	_docs.erase(path)
	return 1 if FileAccess.file_exists(path) else 0


# ==================================================================== the files


## `baFileExists(FileName)` -- 1 or 0.
static func file_exists(host_object: Object, args: Array) -> int:
	return 1 if FileIO.resolve(host_object, _arg(args, 0)) != "" else 0


## `baFileSize(FileName)` -- the size in bytes, or **-1** when the file is not
## there. The one return value in BuddyAPI's own published listing that is
## written out rather than left to the convention.
static func file_size(host_object: Object, args: Array) -> int:
	var path := FileIO.resolve(host_object, _arg(args, 0))
	if path == "":
		return -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var size := int(f.get_length())
	f.close()
	return size


## `baDeleteFile(FileName)` -- 1 on success.
static func delete_file(host_object: Object, args: Array) -> int:
	var path := FileIO.resolve(host_object, _arg(args, 0))
	if path == "" or not _may_write(host_object, path, "baDeleteFile"):
		return 0
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		return 0
	_docs.erase(path)
	FileIO.note_file(path, false)
	return 1


## `baCopyFile(SrcFile, DestFile, Overwrite)` -- 1 when the copy happened.
##
## `Overwrite` is `"Always"`, `"Never"` or `"IfNewer"` in the published API;
## `"IfOlder"` is accepted as its mirror, and any other spelling -- including the
## empty string -- is read as `"Always"`, which is what the corpus's own
## `baCopyFile(src, dest, "Always")` asks for. **Unverified against the real
## Xtra**: the API listing names the argument and not its accepted values.
static func copy_file(host_object: Object, args: Array) -> int:
	var source := FileIO.resolve(host_object, _arg(args, 0))
	if source == "":
		return 0
	var wanted := _arg(args, 1)
	var target := FileIO.resolve(host_object, wanted)
	var existing := target != ""
	if not existing:
		target = FileIO.writable_target(host_object, wanted)
	if target == "" or not _may_write(host_object, target, "baCopyFile"):
		return 0
	if existing and not _overwrite_allowed(_arg(args, 2), source, target):
		return 0
	var err := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(target))
	if err != OK:
		_report(host_object, "baCopyFile failed: %s -> %s" % [source, target])
		return 0
	_docs.erase(target)
	FileIO.note_file(target, true)
	return 1


## `baRenameFile(FileName, NewName)` -- 1 on success. Windows' rename, so it
## refuses rather than replaces when the new name is taken.
static func rename_file(host_object: Object, args: Array) -> int:
	var source := FileIO.resolve(host_object, _arg(args, 0))
	if source == "":
		return 0
	var wanted := _arg(args, 1)
	if FileIO.resolve(host_object, wanted) != "":
		return 0
	var target := FileIO.writable_target(host_object, wanted)
	if target == "" or not _may_write(host_object, source, "baRenameFile") \
			or not _may_write(host_object, target, "baRenameFile"):
		return 0
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(target))
	if err != OK:
		return 0
	_docs.erase(source)
	FileIO.note_file(source, false)
	FileIO.note_file(target, true)
	return 1


## `baFileList(Folder, Pattern)` -- the file names in `Folder` matching
## `Pattern`, as a Lingo list of strings.
##
## Names only, not paths, which is what the Xtra answers and what makes the
## usual `repeat with f in baFileList(dir, "*.txt")` loop concatenate correctly.
## The pattern is a DOS wildcard; `*` and `?` are matched case-insensitively and
## an empty pattern means everything.
static func file_list(host_object: Object, args: Array) -> Array:
	var folder := FileIO.resolve_folder(host_object, _arg(args, 0))
	if folder == "":
		return []
	var dir := FileIO.open_dir(folder)
	if dir == null:
		return []
	var pattern := _arg(args, 1)
	var out: Array = []
	for name in dir.get_files():
		if _matches(str(name), pattern):
			out.append(str(name))
	out.sort()
	return out


## `baFolderList(Folder)` -- the sub-folder names, as a Lingo list of strings.
static func folder_list(host_object: Object, args: Array) -> Array:
	var folder := FileIO.resolve_folder(host_object, _arg(args, 0))
	if folder == "":
		return []
	var dir := FileIO.open_dir(folder)
	if dir == null:
		return []
	var out: Array = []
	for name in dir.get_directories():
		out.append(str(name))
	out.sort()
	return out


## `baFolderExists(DirName)` -- 1 or 0.
static func folder_exists(host_object: Object, args: Array) -> int:
	var name := _arg(args, 0)
	if name.strip_edges() == "":
		return 0
	return 1 if FileIO.resolve_folder(host_object, name) != "" else 0


## `baCreateFolder(DirName)` -- 1 on success.
##
## One level, under the game root, named by its last element -- the same rule
## `FileIO.writable_target` applies to a file, and for the same reason: a 1997
## path names a directory tree that is not here, and building it to satisfy the
## request is not this port's job.
##
## The published listing gives no return value for this call; 1-on-success is
## BuddyAPI's convention everywhere it *is* written down, and is unverified.
static func create_folder(host_object: Object, args: Array) -> int:
	var name := _arg(args, 0)
	if FileIO.resolve_folder(host_object, name) != "":
		# Already there. Windows' CreateDirectory fails in this case, and the
		# Xtra reports the failure rather than success.
		return 0
	var target := _folder_target(host_object, name)
	if target == "" or not _may_write(host_object, target, "baCreateFolder"):
		return 0
	if DirAccess.make_dir_absolute(ProjectSettings.globalize_path(target)) != OK:
		return 0
	FileIO.note_folder(target, true)
	return 1


## `baDeleteFolder(DirName)` -- 1 on success. **Empty folders only**, which is
## the published behaviour ("deletes dirname if empty") and is also the only
## version of this call a player should have: a recursive delete driven by a
## path a movie built is how a corpus disappears.
static func delete_folder(host_object: Object, args: Array) -> int:
	var target := FileIO.resolve_folder(host_object, _arg(args, 0))
	if target == "" or target == FileIO.game_root(host_object):
		return 0
	if not _may_write(host_object, target, "baDeleteFolder"):
		return 0
	var dir := FileIO.open_dir(target)
	if dir == null or dir.get_files().size() > 0 or dir.get_directories().size() > 0:
		return 0
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) != OK:
		return 0
	FileIO.note_folder(target, false)
	return 1


# ===================================================================== the shell


## `baOpenURL(FileName, State)` -- **declined, and said so.**
##
## Not an oversight and not a stub. The call hands the host operating system a
## URL a *movie* chose and asks it to open a browser; `itamar-magichat` reaches
## it three times, twice with `ReadConfigLine("globals", "before")` -- a string
## out of a configuration file that this player will happily read from anywhere
## under the game root. A Director player that silently opens whatever comes out
## of that is a Director player nobody should run an unfamiliar CD in.
##
## So it answers 0, which is BuddyAPI's own "this did not happen", and reports
## the URL through the diagnostics so the decision is visible rather than silent.
## If this is ever wanted, it belongs behind an explicit opt-in on the command
## line beside `--allow-writes`, not on by default.
static func open_url(host_object: Object, args: Array) -> int:
	_report(host_object, "baOpenURL declined: %s" % _arg(args, 0))
	return 0


# ==================================================================== the writes


## Both guards, in `lingo_fileio.gd`'s order and for its reasons: the root test
## is about the path and holds whatever the run allows, the run test is about
## this process. Reported rather than merely refused, because BuddyAPI has no
## `status` channel for the reason to arrive through.
static func _may_write(host_object: Object, path: String, who: String) -> bool:
	if not FileIO.under_root(host_object, path):
		_report(host_object, "%s refused: \"%s\" is outside the game root" % [who, path])
		return false
	if not MovieSave.writes_allowed():
		_report(host_object,
			"%s refused: writes are off (headless without --allow-writes)" % who)
		return false
	return true


## Where a new folder goes: the game root joined with the requested name's last
## element, or the literal path when this engine could open it on its own.
static func _folder_target(host_object: Object, name: String) -> String:
	var wanted := FileIO.normalise(name).trim_suffix("/")
	if wanted.begins_with("res://") or wanted.begins_with("user://"):
		return wanted
	var bare := wanted.get_file()
	if bare == "" or bare == "." or bare == "..":
		return ""
	var root := FileIO.game_root(host_object)
	return bare if root == "" else "%s/%s" % [root, bare]


static func _overwrite_allowed(mode: String, source: String, target: String) -> bool:
	match mode.strip_edges().to_lower():
		"never":
			return false
		"ifnewer":
			return _modified(source) > _modified(target)
		"ifolder":
			return _modified(source) < _modified(target)
	return true


static func _modified(path: String) -> int:
	return int(FileAccess.get_modified_time(ProjectSettings.globalize_path(path)))


## A DOS wildcard, case-insensitively. `""` and `"*.*"` both mean everything --
## the second because that is what it means to a 1997 script, whatever a strict
## reading of the glob would do with a name that has no dot in it.
static func _matches(name: String, pattern: String) -> bool:
	var glob := pattern.strip_edges()
	if glob == "" or glob == "*" or glob == "*.*":
		return true
	return name.matchn(glob)


# ================================================================ the documents
#
# One parsed file per path, so the 34 read sites over a 94-line menu file are one
# read. `baFlushIni` is what drops an entry; nothing else may, or a movie that
# wrote and re-read in the same handler would see the old value.

## path -> `{"lines": PackedStringArray, "eol": String, "pending": bool}`
static var _docs: Dictionary = {}


## The file's lines, from the cache or from disk. Line endings are split on all
## three spellings, because these files are hand-edited on both platforms.
static func _document(path: String) -> PackedStringArray:
	var held: Variant = _docs.get(path, null)
	if held != null:
		return (held as Dictionary)["lines"]
	var text := ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
		f.close()
	var eol := "\r\n" if text.contains("\r\n") else "\n"
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	_docs[path] = {"lines": lines, "eol": eol, "pending": false}
	return lines


static func _eol_of(path: String) -> String:
	var held: Variant = _docs.get(path, null)
	return str((held as Dictionary)["eol"]) if held != null else "\n"


static func _commit(path: String) -> bool:
	var held: Variant = _docs.get(path, null)
	if held == null:
		return true
	var doc: Dictionary = held
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(str(doc["eol"]).join(doc["lines"] as PackedStringArray))
	f.close()
	doc["pending"] = false
	return true


## Set `key` in `section`, in place, keeping everything else.
##
## Three cases, and the third is the one Windows' own writer has: an absent
## section is appended to the end of the file rather than inserted anywhere
## clever.
static func _set_key(lines: PackedStringArray, section: String, key: String,
		value: String) -> void:
	var want_section := section.to_lower()
	var want_key := key.to_lower()
	var in_section := section == ""
	var section_seen := in_section
	var last_in_section := -1
	for i in lines.size():
		var line := str(lines[i]).strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			if in_section:
				break
			in_section = line.substr(1, line.length() - 2).strip_edges().to_lower() \
				== want_section
			section_seen = section_seen or in_section
			if in_section:
				last_in_section = i
			continue
		if not in_section:
			continue
		if line != "":
			last_in_section = i
		if line.begins_with(";"):
			continue
		var split := line.find("=")
		if split < 0:
			continue
		if line.substr(0, split).strip_edges().to_lower() == want_key:
			# The author's own spelling of the key is kept; only the value moves.
			lines[i] = "%s=%s" % [line.substr(0, split).strip_edges(), value]
			return
	var entry := "%s=%s" % [key, value]
	if section_seen and last_in_section >= 0:
		lines.insert(last_in_section + 1, entry)
		return
	if not section_seen and section != "":
		if lines.size() > 0 and str(lines[lines.size() - 1]).strip_edges() != "":
			lines.append("")
		lines.append("[%s]" % section)
	lines.append(entry)


## Windows strips one matching pair of quotes from a value and nothing else.
static func _unquote(value: String) -> String:
	if value.length() >= 2:
		var first := value[0]
		if (first == "\"" or first == "'") and value[value.length() - 1] == first:
			return value.substr(1, value.length() - 2)
	return value


# ------------------------------------------------------------------- plumbing


static func _arg(args: Array, at: int) -> String:
	return LingoValue.to_str(args[at]) if at < args.size() else ""


## Named in the diagnostics the way an unbound builtin is, so a refusal is
## visible in the same report a gap would be. Dropped when there is no host,
## which is only the case in a harness that drove this class directly.
static func _report(host_object: Object, what: String) -> void:
	if host_object != null and host_object.has_method("report_xtra"):
		host_object.call("report_xtra", what)


## Forget every cached document. For a harness that writes a file behind this
## class's back and then reads it through Lingo.
static func forget_documents() -> void:
	_docs.clear()
