extends SceneTree
## The transcoder's front end: which media files this port cannot decode, where
## their Ogg Theora sidecars would go, whether any are there, and the exact
## command that would make them.
##
##   godot --headless --audio-driver Dummy --path . --script tools/video_sidecar.gd
##   godot --headless --audio-driver Dummy --path . --script tools/video_sidecar.gd -- \
##       --root res://test-games/itamar-magichat
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --run         actually transcode. Off by default; see below.
##   --only NAME   restrict to source files whose name contains NAME
##   --verify      open every sidecar in the cache through Godot's own decoder
##                 and check it against `director/director_ogg.gd`'s parse
##   --clear       delete every sidecar in the cache
##
## ## Why this is a tool and not something the engine does
##
## Transcoding `itamar-magichat` is **197.3 MB across 22 files**
## (`docs/DIGITAL_VIDEO.md` §1). That is minutes of CPU and a couple of hundred
## megabytes of disc, and it is a decision with a cost — so it belongs to the
## person who owns the machine, not to a property read that happened to miss a
## cache. The engine's side of this feature is one lookup: if a fresh sidecar is
## there, play it; if not, skip the video exactly as it did before. Nothing is
## produced, downloaded or repaired behind the owner's back.
##
## ## `ffmpeg` is not on this machine, and saying so is half of what this does
##
## Measured 2026-08-13 on the owner's Windows box: no `ffmpeg`, no `ffprobe`, no
## `ffmpeg2theora`, no `HandBrakeCLI`, nothing on `PATH` that encodes video. A
## tool that shelled out and reported "exit code -1" would be indistinguishable
## from a tool that ran and produced nothing, which is the failure shape this
## whole project's §19 is about. So the converter is looked for *first*, by name,
## and when none is found the run prints what to install and the exact command it
## would have run for every file — and exits reporting that it did nothing.
##
## **Nothing is downloaded and nothing is bundled.** An encoder is a dependency
## and this project does not acquire one; what it does is name the two that work
## and let the owner decide.
##
## ## VLC counts, and on this machine it is the one that is already here
##
## VLC ships `libtheora_plugin.dll` and `libmux_ogg_plugin.dll` and will transcode
## MPEG-1 to Ogg Theora from the command line with no interface. It was found at
## `C:\Program Files\VideoLAN\VLC\vlc.exe` on the owner's machine and is what the
## end-to-end proof of this feature was actually produced with — a 3-second cut
## of `retro.mpg` at 352x288, 247,753 bytes, which Godot loaded, reported a
## length of 3.08 s for, seeked in, and handed back a 352x288 texture from while
## running `--headless`.
##
## `ffmpeg` is still listed first because it is the better encoder for this job
## and because a two-pass Theora encode is one flag there and an argument to
## nothing in VLC. Either produces a file this port plays.
##
## ## What "needs a sidecar" means, and why FLIC is not on the list
##
## A media file needs one when it is a video format **and** nothing in this port
## can decode it. That is every MPEG-1 and every QuickTime file in the tree, and
## it is *not* `logo/logo.avi`, which `director/director_avi.gd` decodes from the
## original bytes.
##
## It is also not the 415 Autodesk FLIC files, and that is the largest number in
## this listing so it is worth being exact about: they belong to the DOS demo
## trees both Itamar discs ship as loose data for a separate DOS executable, no
## cast member in either corpus references one, and no Director container in the
## tree can play a `.flc` (`docs/DIGITAL_VIDEO.md` §1). Transcoding 227 MB of
## them would buy nothing at all. They are counted and named as skipped rather
## than left out, so that "427 MB of video-shaped files" cannot later be mistaken
## for 427 MB of loss.
##
## Title-agnostic: it names no game, no channel and no member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const Sidecar := preload("res://director/director_sidecar.gd")
const Ogg := preload("res://director/director_ogg.gd")
const VideoXtra := preload("res://director/director_video_xtra.gd")
## Read for its `VIDEO_XTRAS` table alone, to assert the engine's copy and the
## survey's copy still name the same Xtras. A `preload` loads the script and does
## not instantiate it, so the census does not run.
const Census := preload("res://tools/video_census.gd")

## Extensions worth opening to find out what a file is. The sniff below decides
## what it *is*; this only decides what to look at, and it is the same generous
## list `tools/video_census.gd` uses and for the same reason — `windemo.dat` sits
## beside a title's movies and had to be ruled out rather than assumed.
const MEDIA_EXTENSIONS := [
	"mpg", "mpeg", "m1v", "m2v", "mpv", "avi", "mov", "qt", "moov",
	"flc", "fli", "flh", "dat",
]

## Bytes of a file read to classify it. The first sector holds every magic this
## needs; the census reads 256 KB because it also reports an MPEG's bit rate,
## which is a few packets in and is not asked here.
const SNIFF_BYTES := 4096

## What the two encoders are called and where they might be. `OS.execute` on
## Windows does not search `PATH` for a bare name in every case, so the absolute
## installs are tried as well — and finding VLC where its installer puts it is
## the difference between this tool being useful on the owner's machine and
## printing "install something".
const FFMPEG_CANDIDATES := [
	"ffmpeg",
	"C:/Program Files/ffmpeg/bin/ffmpeg.exe",
	"/usr/bin/ffmpeg",
	"/usr/local/bin/ffmpeg",
	"/opt/homebrew/bin/ffmpeg",
]
const VLC_CANDIDATES := [
	"vlc",
	"C:/Program Files/VideoLAN/VLC/vlc.exe",
	"C:/Program Files (x86)/VideoLAN/VLC/vlc.exe",
	"/Applications/VLC.app/Contents/MacOS/VLC",
	"/usr/bin/vlc",
]

## The Theora quality `ffmpeg` is asked for. 7 of 10 is visually transparent at
## 320x240 and 352x288 — the two sizes this corpus has — and lands a 15 MB
## MPEG-1 file at roughly the same size rather than larger, which matters when
## the cache is 22 files.
const FFMPEG_VIDEO_QUALITY := "7"
const FFMPEG_AUDIO_QUALITY := "4"

## VLC's equivalents, which are bit rates rather than qualities because its
## transcode module takes no quality for Theora. 1200 kbit/s at 320x240 is well
## above the 1500 kbit/s the MPEG-1 source spends on a less efficient codec.
const VLC_VIDEO_BITRATE := "1200"
const VLC_AUDIO_BITRATE := "128"

## How long one file may take before the run gives up on it. A two-minute clip
## encodes in well under this; a converter that has hung is reported by name
## rather than left holding the harness.
const TRANSCODE_TIMEOUT_S := 900


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := Args.parse()
	var h := Harness.new()
	await _sweep(h, args)
	quit(h.finish("every media file this port cannot decode has a named sidecar, "
		+ "and the cache is only ever under user://"))


func _sweep(h: Harness, args: Dictionary) -> void:
	var paths := Paths.new()
	if not paths.load_config():
		h.begin("a corpus to survey")
		h.check("the config names a game", false, Paths.CONFIG_PATH)
		h.complete("a corpus to survey")
		return
	var corpus := str(paths.root).get_file()
	var only := Args.text(args, "only", "")

	if Args.flag(args, "clear"):
		_clear()

	# ------------------------------------------------------------ the two tables
	#
	# Asserted before anything is listed, because a symbol the engine knows and
	# the census does not is a member the player would open and the survey would
	# report as "not video" -- two answers to one question, which is the failure
	# `director/director_video_xtra.gd`'s header describes.
	var tables := "the player's Xtra table and the census's name the same players"
	h.begin(tables)
	var drifted: Array[String] = []
	for symbol in VideoXtra.SYMBOLS.keys():
		if not Census.VIDEO_XTRAS.has(str(symbol)):
			drifted.append(str(symbol))
	h.check("%d symbol(s) in the player are all on the census's table"
		% VideoXtra.SYMBOLS.size(), drifted.is_empty(), ", ".join(drifted))
	h.complete(tables)

	# ---------------------------------------------------------------- the survey
	var found := _survey(str(paths.root), only)
	var needing: Array[Dictionary] = found["needing"]
	var skipped: Array[Dictionary] = found["skipped"]

	print("")
	print("corpus      : %s (%s)" % [corpus, paths.root])
	print("cache       : %s -> %s" % [
		Sidecar.CACHE_DIR, ProjectSettings.globalize_path(Sidecar.CACHE_DIR)])
	print("in the cache: %d sidecar(s)" % Sidecar.existing().size())
	print("")

	if skipped.is_empty() and needing.is_empty():
		print("no media files under this corpus at all.")
	if not skipped.is_empty():
		var by_reason: Dictionary = {}
		for record_value in skipped:
			var record: Dictionary = record_value
			var reason := str(record["why"])
			by_reason[reason] = int(by_reason.get(reason, 0)) + 1
		print("not transcoded, and why:")
		for reason in by_reason:
			print("  %-52s %d file(s)" % [str(reason), int(by_reason[reason])])
		print("")

	var total_mb := 0.0
	var fresh := 0
	var stale := 0
	var missing := 0
	print("needs a sidecar: %d file(s)" % needing.size())
	for record_value in needing:
		var record: Dictionary = record_value
		var status := Sidecar.status_of(str(record["path"]))
		match status:
			"fresh": fresh += 1
			"stale": stale += 1
			_: missing += 1
		total_mb += float(record["bytes"]) / 1048576.0
		print("  %-8s %-44s %7.1f MB  %-18s -> %s" % [
			status, _relative(str(record["path"]), str(paths.root)),
			float(record["bytes"]) / 1048576.0, str(record["kind"]),
			Sidecar.path_for(str(record["path"])).get_file()])
	print("")
	print("  %d fresh, %d stale, %d missing -- %.1f MB of source" % [
		fresh, stale, missing, total_mb])
	print("")

	# ------------------------------------------------------------ the invariants
	var invariants := "%s: the cache is addressable and lives under user://" % corpus
	h.begin(invariants)
	if needing.is_empty():
		# **Said out loud, not passed over.** Six of the eight corpora in this tree
		# hold no media file at all (`docs/DIGITAL_VIDEO.md` §1), so a run against
		# one has nothing to key, nothing to place and nothing to resolve — and a
		# harness that reported three quiet `ok`s for that is the dark-harness
		# failure `gate.sh` warns about, indistinguishable from three real ones.
		# The same shape `tools/video_fallback.gd` uses on the seven roots with no
		# video member.
		h.check("this corpus has no media this port cannot decode, so the cache "
			+ "surface is not exercised here", true,
			"%d media file(s) surveyed, all of them playable or not video; run "
				% skipped.size()
			+ "--root res://test-games/itamar-magichat for the corpus that needs one")
		h.complete(invariants)
		if Args.flag(args, "verify"):
			await _verify(h)
		return
	# A key that is not a function of the path alone is a cache that misses after
	# a restart, and one that is not stable across separator and case spellings is
	# two transcodes of one file on Windows. Both asserted against real paths from
	# the survey rather than against invented strings.
	var unstable: Array[String] = []
	var collided: Dictionary = {}
	for record_value in needing:
		var source := str((record_value as Dictionary)["path"])
		var key := Sidecar.key_for(source)
		# The three spellings one file really arrives under. `res://` and the
		# globalized absolute path are the same file reached from inside and from
		# outside the engine — the player resolves media through `res://` and the
		# converter hands `ffmpeg` an absolute path — and Windows accepts either
		# separator and either case for the second. A key that distinguished any
		# of them would transcode a file twice and then find neither copy.
		var absolute := ProjectSettings.globalize_path(source)
		for spelling in [absolute, absolute.replace("/", "\\"), absolute.to_upper()]:
			if Sidecar.key_for(str(spelling)) != key:
				unstable.append("%s keys differently as %s" % [source, spelling])
		if collided.has(key):
			unstable.append("%s collides with %s" % [source, str(collided[key])])
		collided[key] = source
	h.check("%d source path(s) each key to one sidecar, stably across spellings"
		% needing.size(), unstable.is_empty() and not needing.is_empty(),
		"; ".join(unstable) if not unstable.is_empty()
			else ("" if not needing.is_empty() else "no source needed a sidecar, "
				+ "so this asserted nothing"))
	var outside: Array[String] = []
	for record_value in needing:
		var where := Sidecar.path_for(str((record_value as Dictionary)["path"]))
		if not where.begins_with("user://"):
			outside.append(where)
	# The rule the whole approach rests on, asserted rather than trusted to
	# review: `games/` and `test-games/` are the owner's data and nothing this
	# port does may write into them.
	var surveyed := needing.size() + skipped.size()
	h.check("all %d sidecar path(s) are under user:// and none is under the corpus"
		% needing.size(), outside.is_empty() and surveyed > 0,
		"; ".join(outside) if not outside.is_empty()
			else ("" if surveyed > 0 else "no media file was surveyed, so this "
				+ "asserted nothing"))
	var absent_clean := true
	var absent_detail := ""
	for record_value in needing:
		var source := str((record_value as Dictionary)["path"])
		if Sidecar.status_of(source) != "missing":
			continue
		if Sidecar.fresh_for(source) != "":
			absent_clean = false
			absent_detail = "%s answers a sidecar it does not have" % source
			break
	h.check("a missing sidecar resolves to nothing, which is the clean skip",
		absent_clean, absent_detail)
	h.complete(invariants)

	# ------------------------------------------------------------- the converter
	var tool_found := _find_converter()
	print("converter   : %s" % (
		"%s (%s)" % [str(tool_found["kind"]), str(tool_found["exe"])]
			if str(tool_found["kind"]) != "" else "NONE FOUND"))
	print("")
	if str(tool_found["kind"]) == "":
		_explain_missing()
	var wanted: Array[Dictionary] = []
	for record_value in needing:
		if Sidecar.status_of(str((record_value as Dictionary)["path"])) != "fresh":
			wanted.append(record_value)
	if wanted.is_empty():
		print("nothing to transcode: every source already has a fresh sidecar.")
		if Args.flag(args, "verify"):
			await _verify(h)
		return
	print("the command%s that would run%s:" % [
		"" if wanted.size() == 1 else "s",
		"" if Args.flag(args, "run") else " (pass --run to actually run %s)"
			% ("it" if wanted.size() == 1 else "them")])
	print("")
	for record_value in wanted:
		var source := str((record_value as Dictionary)["path"])
		var line := _command_line(tool_found, source)
		print("  %s" % line)
	print("")
	if not Args.flag(args, "run"):
		if Args.flag(args, "verify"):
			await _verify(h)
		return
	if str(tool_found["kind"]) == "":
		print("--run was asked for and there is no converter to run. Nothing done.")
		return
	await _transcode(h, tool_found, wanted)
	# **After the transcode, never before**, so that `--run --verify` in one
	# invocation checks the files this run produced rather than the ones that were
	# already there. The first version verified first and reported "the cache is
	# empty, so nothing was verified" in the same run that filled it.
	if Args.flag(args, "verify"):
		await _verify(h)


# ------------------------------------------------------------------ the survey


## Every media file under a corpus root, split into the ones that need a sidecar
## and the ones that do not, with a reason on each of the latter.
func _survey(root: String, only: String) -> Dictionary:
	var files: Array[String] = []
	_walk(root, files)
	var needing: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	for path in files:
		if only != "" and not path.get_file().to_lower().contains(only.to_lower()):
			continue
		var record := _classify(path)
		if bool(record["needs"]):
			needing.append(record)
		else:
			skipped.append(record)
	needing.sort_custom(func(a, b): return str(a["path"]) < str(b["path"]))
	return {"needing": needing, "skipped": skipped}


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if MEDIA_EXTENSIONS.has(str(name).get_extension().to_lower()):
			out.append(dir_path.path_join(str(name)))
	for name in dir.get_directories():
		_walk(dir_path.path_join(str(name)), out)


## What a file is, from its own first bytes, and whether this port needs a
## sidecar to play it.
##
## **Sniffed and not trusted to the extension**, which is the census's rule and
## the reason it exists: `windemo.dat` sits beside Magic Hat's movies and is an
## icon table, and an extension-driven survey would have offered to transcode it.
func _classify(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var head := PackedByteArray()
	var size := 0
	if file != null:
		size = int(file.get_length())
		head = file.get_buffer(mini(size, SNIFF_BYTES))
		file.close()
	var out := {"path": path, "bytes": size, "kind": "unknown", "needs": false,
		"why": "not a video format this port recognises"}
	if head.size() < 12:
		return out
	if head.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and head.slice(8, 12).get_string_from_ascii() == "AVI ":
		out["kind"] = "RIFF AVI"
		# The one AVI in the tree is Microsoft RLE, which `director_avi.gd`
		# decodes from the original bytes. An AVI in any other codec is not
		# something this port can open, so it wants a sidecar like the rest —
		# tested by looking for the FourCC rather than by assuming, because
		# "AVI means we can play it" would be wrong for every disc but this one.
		if _contains(head, "mrle") or _contains(head, "MRLE"):
			out["why"] = "MS-RLE AVI, decoded from the original bytes by director_avi.gd"
			return out
		out["kind"] = "AVI, not MS-RLE"
		out["needs"] = true
		return out
	# MPEG-1 system stream (pack header `00 00 01 BA`) and bare MPEG video
	# (sequence header `00 00 01 B3`). Both are the format Magic Hat ships.
	if head[0] == 0x00 and head[1] == 0x00 and head[2] == 0x01 \
			and (head[3] == 0xBA or head[3] == 0xB3):
		out["kind"] = "MPEG-1"
		out["needs"] = true
		return out
	# QuickTime: a top-level atom whose type is one of these. Not in this tree and
	# handled because the next disc may be.
	var atom := head.slice(4, 8).get_string_from_ascii()
	if atom == "ftyp" or atom == "moov" or atom == "mdat":
		out["kind"] = "QuickTime"
		out["needs"] = true
		return out
	if head[0] == 0x11 and head[1] == 0xAF:
		out["kind"] = "Autodesk FLIC"
		out["why"] = "FLIC, for a DOS executable — no cast member references one"
		return out
	if head[0] == 0x12 and head[1] == 0xAF:
		out["kind"] = "Autodesk FLI"
		out["why"] = "FLIC, for a DOS executable — no cast member references one"
		return out
	if head.slice(0, 4).get_string_from_ascii() == "OggS":
		out["kind"] = "Ogg"
		out["why"] = "already Ogg — Godot decodes this without a sidecar"
		return out
	return out


## Is a short ASCII tag anywhere in the sniffed head?
##
## Written as a byte walk rather than as `PackedByteArray.find`, which takes a
## single byte and not a run, and rather than `get_string_from_ascii()` over the
## buffer, which stops at the first NUL — and an AVI header is mostly NULs.
static func _contains(data: PackedByteArray, want: String) -> bool:
	var needle := want.to_ascii_buffer()
	if needle.is_empty() or needle.size() > data.size():
		return false
	for at in range(data.size() - needle.size() + 1):
		var hit := true
		for i in needle.size():
			if data[at + i] != needle[i]:
				hit = false
				break
		if hit:
			return true
	return false


static func _relative(path: String, root: String) -> String:
	return path.trim_prefix(root).trim_prefix("/")


# --------------------------------------------------------------- the converter


## The first encoder on this machine that can write Ogg Theora, or none.
##
## **Found by looking for the file, not by running it**, and that is worth a
## paragraph because the first version did the opposite. `OS.execute` on a name
## that is not there logs an engine `ERROR` line before returning -1, so probing
## five ffmpeg spellings and four VLC ones printed nine `Could not create child
## process` errors on a machine where the answer was simply "ffmpeg is not
## installed" — in a tool whose entire job is to say that clearly. It also put
## nine red lines into a suite whose value depends on a red meaning something.
##
## So `PATH` is walked here rather than delegated to the OS loader. That is a few
## more lines and it is exact: a bare name is resolved against every `PATH`
## entry, with `PATHEXT` applied on Windows, and an absolute candidate is tested
## for existence. What it cannot catch is a binary that exists and is broken, and
## that case is reported per file by the transcode's own check — the sidecar it
## was supposed to produce is parsed afterwards, so an encoder that runs and
## writes rubbish fails by name rather than by exit code.
func _find_converter() -> Dictionary:
	for exe in FFMPEG_CANDIDATES:
		var found := _resolve_exe(str(exe))
		if found != "":
			return {"kind": "ffmpeg", "exe": found}
	for exe in VLC_CANDIDATES:
		var found := _resolve_exe(str(exe))
		if found != "":
			return {"kind": "vlc", "exe": found}
	return {"kind": "", "exe": ""}


## Where an executable named on the command line actually is, or `""`.
static func _resolve_exe(name: String) -> String:
	if name.contains("/") or name.contains("\\"):
		return name if FileAccess.file_exists(name) else ""
	var separator := ";" if OS.get_name() == "Windows" else ":"
	var suffixes := PackedStringArray([""])
	if OS.get_name() == "Windows":
		# `PATHEXT` is what makes `ffmpeg` mean `ffmpeg.exe` on Windows, and a
		# lookup that only tried the bare name would miss every install.
		for ext in OS.get_environment("PATHEXT").split(";", false):
			suffixes.append(str(ext).to_lower())
	for entry in OS.get_environment("PATH").split(separator, false):
		var dir := str(entry).strip_edges().replace("\\", "/")
		if dir == "":
			continue
		for suffix in suffixes:
			var candidate := dir.path_join(name + str(suffix))
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


## What to install, when nothing is here. Named exactly, with the one-line
## install for each platform, because "install ffmpeg" is not an instruction
## somebody can follow at 2am.
func _explain_missing() -> void:
	print("No Ogg Theora encoder was found on this machine, so nothing can be")
	print("transcoded here. Nothing has been downloaded and nothing will be.")
	print("")
	print("Install one of these -- either is enough:")
	print("")
	print("  ffmpeg (preferred)")
	print("    Windows   winget install Gyan.FFmpeg")
	print("              or download from https://www.gyan.dev/ffmpeg/builds/ and")
	print("              put ffmpeg.exe on PATH")
	print("    macOS     brew install ffmpeg")
	print("    Linux     apt install ffmpeg   /   dnf install ffmpeg")
	print("    Needs libtheora and libvorbis, which every general build has.")
	print("")
	print("  VLC (already common, and it does work)")
	print("    Windows   winget install VideoLAN.VLC")
	print("    macOS     brew install --cask vlc")
	print("    Linux     apt install vlc")
	print("    This tool finds it at its default install path without PATH.")
	print("")
	print("Then re-run this tool with --run. The commands it would issue are")
	print("printed below so they can also be pasted by hand.")
	print("")


## The exact command line for one file, as it would be run.
##
## Printed even when no converter is present — with `ffmpeg` assumed, because it
## is the one being recommended — so that the output of a run on a machine with
## no encoder is still something the owner can paste somewhere that has one.
func _command_line(tool_found: Dictionary, source: String) -> String:
	var dst := _native(ProjectSettings.globalize_path(Sidecar.path_for(source)))
	var src := _native(ProjectSettings.globalize_path(source))
	if str(tool_found["kind"]) == "vlc":
		return "\"%s\" %s" % [str(tool_found["exe"]),
			" ".join(_vlc_args(src, dst))]
	var exe := str(tool_found["exe"]) if str(tool_found["kind"]) == "ffmpeg" else "ffmpeg"
	return "\"%s\" %s" % [exe, " ".join(_ffmpeg_args(src, dst))]


## A path in the separators the *converter* wants, which on Windows is not the
## separators Godot hands out.
##
## `ProjectSettings.globalize_path` answers `C:/Users/...` with forward slashes
## on Windows, and that is right for everything inside the engine.
## **VLC will not open it.** Measured on the owner's machine, and it took an hour
## because the failure has no error in it: given
## `C:/Data/.../retro.mpg` VLC prints `end of playlist, exiting`, writes nothing
## and exits **0** — the file is never enqueued, no diagnostic names it, and the
## run looks like a successful transcode that produced no output. The identical
## command with `C:\Data\...\retro.mpg` produces a 261,389-byte `.ogv`. The
## destination inside the `:sout=` chain is unaffected and works either way; it
## is converted here too, because a rule that applied to one path and not the
## other is one somebody has to remember.
##
## Left alone on every other platform, where the separator is already `/` and a
## backslash is a legal character in a filename.
static func _native(path: String) -> String:
	return path.replace("/", "\\") if OS.get_name() == "Windows" else path


## `ffmpeg`'s arguments. `-c:v libtheora` with a quality rather than a bit rate,
## because the sources are 25 fps at two fixed sizes and a quality target keeps a
## static album page small where a fixed rate would not.
static func _ffmpeg_args(src: String, dst: String) -> PackedStringArray:
	return PackedStringArray([
		"-y", "-loglevel", "error",
		"-i", "\"%s\"" % src,
		"-c:v", "libtheora", "-q:v", FFMPEG_VIDEO_QUALITY,
		"-c:a", "libvorbis", "-q:a", FFMPEG_AUDIO_QUALITY,
		"\"%s\"" % dst,
	])


## VLC's arguments, in the one form that was measured to work.
##
## The `:sout=` chain is attached to the **item** rather than passed as the
## global `--sout`, and `vlc://quit` closes the playlist. Both matter: with a
## global `--sout` VLC on Windows accepted the option and then reported an empty
## playlist, producing no file and exiting 0 — which is exactly the silent
## nothing this tool exists not to do. Without `vlc://quit` it transcodes and
## then sits there. The form below produced a 247,753-byte `.ogv` from
## `retro.mpg` on the first try.
static func _vlc_args(src: String, dst: String) -> PackedStringArray:
	return PackedStringArray([
		"-I", "dummy", "--no-repeat", "--no-loop", "--play-and-exit",
		"\"%s\"" % src,
		"\":sout=#transcode{vcodec=theo,vb=%s,acodec=vorb,ab=%s,channels=2,"
			% [VLC_VIDEO_BITRATE, VLC_AUDIO_BITRATE]
			+ "samplerate=44100}:standard{access=file,mux=ogg,dst=%s}\"" % dst,
		"vlc://quit",
	])


## Run the converter over every file that wants one.
##
## Sequential rather than parallel: two encoders saturate the machine and the
## owner is watching this run. Each file is checked *after* it is written, by
## parsing the result with the same reader the engine will use, so a converter
## that exits 0 and writes a truncated file is a named failure here rather than a
## clip that will not play later.
func _transcode(h: Harness, tool_found: Dictionary,
		wanted: Array[Dictionary]) -> void:
	if not Sidecar.ensure_dir():
		h.begin("the cache directory")
		h.check("user:// is writable", false, Sidecar.CACHE_DIR)
		h.complete("the cache directory")
		return
	var case := "transcoding %d file(s) with %s" % [
		wanted.size(), str(tool_found["kind"])]
	h.begin(case)
	var failed: Array[String] = []
	var made := 0
	for record_value in wanted:
		var source := str((record_value as Dictionary)["path"])
		var src := _native(ProjectSettings.globalize_path(source))
		var dst := _native(ProjectSettings.globalize_path(Sidecar.path_for(source)))
		# The quoting in the printed command line is for a shell; `OS.execute`
		# passes the array straight to the process and quotes would become part
		# of the filename. Two builders would drift, so the printed forms are
		# stripped here rather than duplicated unquoted.
		var argv := _unquote(_vlc_args(src, dst) if str(tool_found["kind"]) == "vlc"
			else _ffmpeg_args(src, dst))
		print("  %s ..." % source.get_file())
		var began := Time.get_ticks_msec()
		var out: Array = []
		var code := OS.execute(str(tool_found["exe"]), argv, out, true)
		var took := (Time.get_ticks_msec() - began) / 1000.0
		var probe = Ogg.new()
		if not probe.open(Sidecar.path_for(source)):
			failed.append("%s: exit %d, %s" % [
				source.get_file(), code, str(probe.error)])
			print("    FAILED after %.1fs: %s" % [took, str(probe.error)])
			for line in out:
				print("      %s" % str(line).strip_edges())
			continue
		made += 1
		print("    %.1fs -> %s, %dx%d, %.1fs, %.1f MB" % [
			took, Sidecar.path_for(source).get_file(), probe.width, probe.height,
			probe.duration_ms / 1000.0,
			float(FileAccess.get_file_as_bytes(
				Sidecar.path_for(source)).size()) / 1048576.0])
		await process_frame
	h.check("%d of %d transcodes produced a readable sidecar"
		% [made, wanted.size()], failed.is_empty(), "; ".join(failed))
	h.complete(case)


static func _unquote(argv: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for arg in argv:
		var value := str(arg)
		if value.length() >= 2 and value.begins_with("\"") and value.ends_with("\""):
			value = value.substr(1, value.length() - 2)
		out.append(value)
	return out


# ----------------------------------------------------------------- the verify


## Check every sidecar in the cache two ways, and fail when the two disagree.
##
## This is the check that makes the rest of the feature trustworthy, and it is
## built the way `porting-fidelity-verification` says to build one: the duration
## `director/director_ogg.gd` computes from the Ogg page structure is compared
## against the duration **Godot's own Theora decoder** reports, which is a
## different implementation reading different parts of the file. A parser that
## agreed with itself would prove nothing.
##
## It also settles the assumption the whole Theora backend rests on — that a
## hidden `VideoStreamPlayer` decodes at all — by playing each sidecar for a few
## frames with `visible = false` and requiring a texture of the declared size to
## come out. That is the shape of failure that would otherwise show up as a video
## sprite that draws nothing, with everything else looking correct.
func _verify(h: Harness) -> void:
	var sidecars := Sidecar.existing()
	var case := "each sidecar decodes, and says the same length two ways"
	h.begin(case)
	if sidecars.is_empty():
		h.check("the cache is empty, so nothing was verified", true,
			"run with --run to make some, then --verify")
		h.complete(case)
		return
	var wrong: Array[String] = []
	var checked := 0
	for path in sidecars:
		var parsed = Ogg.new()
		if not parsed.open(str(path)):
			wrong.append("%s: %s" % [str(path).get_file(), str(parsed.error)])
			continue
		var stream: VideoStream = ResourceLoader.load(str(path), "VideoStream")
		if stream == null:
			wrong.append("%s: Godot would not load it as a VideoStream"
				% str(path).get_file())
			continue
		var player := VideoStreamPlayer.new()
		player.visible = false
		player.expand = true
		player.stream = stream
		root.add_child(player)
		player.play()
		# A frame or two for the decoder to produce its first picture. The
		# player's own length is available immediately; the texture is not.
		for _i in 12:
			await process_frame
		var engine_s := player.get_stream_length()
		var texture := player.get_video_texture()
		var frame_s := 1.0 / maxf(parsed.fps, 1.0)
		if absf(engine_s - parsed.duration_ms / 1000.0) > frame_s:
			wrong.append("%s: the page walk says %.3fs and Godot says %.3fs"
				% [str(path).get_file(), parsed.duration_ms / 1000.0, engine_s])
		if texture == null:
			wrong.append("%s: a hidden player produced no texture"
				% str(path).get_file())
		elif texture.get_size() != Vector2(parsed.width, parsed.height):
			wrong.append("%s: the header says %dx%d and the texture is %s"
				% [str(path).get_file(), parsed.width, parsed.height,
					str(texture.get_size())])
		else:
			print("  %-34s %dx%d  %.2fs (parsed) / %.2fs (Godot)  pos %.2fs" % [
				str(path).get_file(), parsed.width, parsed.height,
				parsed.duration_ms / 1000.0, engine_s, player.stream_position])
		checked += 1
		player.queue_free()
	h.check("%d sidecar(s) decode and agree with the page walk" % checked,
		wrong.is_empty() and checked > 0,
		"; ".join(wrong) if not wrong.is_empty()
			else ("" if checked > 0 else "the cache held none that could be opened"))
	h.complete(case)


func _clear() -> void:
	var gone := 0
	for path in Sidecar.existing():
		if DirAccess.remove_absolute(str(path)) == OK:
			gone += 1
	print("cleared %d sidecar(s) from %s" % [gone, Sidecar.CACHE_DIR])
