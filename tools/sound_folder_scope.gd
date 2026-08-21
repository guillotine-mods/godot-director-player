extends SceneTree
## A sound request may lose the segments in front of the folder it names. It may
## not lose the folder.
##
##   godot --headless --path . --script tools/sound_folder_scope.gd
##   godot --headless --path . --script tools/sound_folder_scope.gd -- --root piposh-dream
##
## **Why this is one rule and not a list of names.** `audio_director.gd` matches a
## request at both ends, and the two ends are not symmetric. Leading segments go
## because the request carries a prefix this engine cannot see -- a CD drive
## letter, `the moviePath` of the machine it was authored on, a
## `soundspathstart` written by a movie this entry never passed through -- so
## dropping them is the only way an absolute path from 1997 is answerable at all.
## The trailing folder is the opposite: it is the thing the script went to the
## trouble of composing, and Director plays nothing for a path that is not
## there. It never answers `dream3\149` out of `dream1`.
##
## That is the same wrong-take-of-a-line failure `_resolve_normalised`'s own
## header is about, reached from the other side, and it is worse than a silence
## because a sound plays: a day-3 line answered with day 1's take sounds like
## authored content. Five of them were audible in one `piposh-dream` sweep and two
## more were resolving to another day's folder with nothing printed at all.
##
## **What is asserted, and why it is a structural claim rather than a list.** The
## subject is whatever sound the root happens to carry at least one folder deep,
## and the folder used as the counter-example is another real folder on the same
## disc that does not hold that filename. So the checks below are true of any
## Director corpus and name none of this one: a request keeps its folder, a
## request whose folder does not hold the file **misses**, and a request that is a
## bare filename still resolves, because that is the shortest legal tail and not a
## reduction.
##
## The refusal is asserted through the player-visible route -- `sound playFile`,
## the miss ledger, `soundBusy` -- and not through `resolve_path` alone. A
## resolver that returned `""` while `_fail` was never reached would leave the
## channel playing the previous sound and `soundBusy` answering for it, which is
## the unrecoverable wait `_fail`'s own header is about; and a refusal nothing
## collects is `bugs.md` 68 again, where the only trace was a `warn` line in a log
## nobody reads.
##
## Title-agnostic: the subject and both folders are found by walking whatever root
## this is pointed at.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")

## Enough of a file to see a container tag, and the form type at offset 8.
const TAG_BYTES := 12
## Extensions that name a sound on a disc that has extensions at all. A Mac disc
## has none, which is why the tag sniff below exists beside this.
const NAMED := ["wav", "ogg", "mp3", "aif", "aiff"]

## A folder and a filename no disc can hold, with a marker in them so a root that
## somehow did carry one would be obvious rather than confusing.
const ABSENT_FOLDER := "no-such-folder-9b7e14"
const ABSENT_FILE := "no-such-sound-9b7e14.aif"

## The channel the ledger cases play on. Any channel; nothing here is about the
## number.
const CHANNEL := 6


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	# An autoload is not on the tree during `_init`. No movie: the subject is the
	# mixer, and it indexes the root by itself -- which also means this runs
	# against a `--root` whose boot movie belongs to another title.
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if audio == null:
		print("no AudioDirector; this has to run in the project, not standalone")
		quit(1)
		return
	var paths := Paths.new()
	paths.load_config()
	print("root: %s" % paths.root)

	# Read from the disc rather than from the index. Asking `AudioDirector` which
	# files it holds and then asserting how it resolves them shares one reading
	# between both sides of the comparison, which is the tautology
	# `audio_coverage.gd`'s header is about; the tag sniff here is this tool's own.
	var files: Array[String] = []
	_walk(str(paths.root), "", files)

	var subject := _subject(files)
	var case := "the root carries a sound inside a folder"
	h.begin(case)
	h.check("one was found, so the checks below have a subject",
		not subject.is_empty(), str(subject.get("relative", "")))
	if subject.is_empty():
		h.complete(case)
		quit(h.finish("folder scope under %s" % str(paths.root).get_file()))
		return
	var folder := str(subject["folder"])
	var file_name := str(subject["file"])
	var relative := str(subject["relative"])
	print("subject : %s" % relative)
	h.complete(case)

	var expected := str(audio.call("resolve_path", relative))

	# ------------------------------------------------- the folder still decides
	case = "the request keeps the folder it names"
	h.begin(case)
	h.check("the subject's own path resolves", expected != "", expected)
	# The control for the whole file: leading segments are still dropped, so the
	# rule below is a bound on the trailing end and not "whole paths only". This
	# is the shape a script builds from `the moviePath` on a Mac.
	var prefixed := "Macintosh HD:%s" % relative.replace("/", ":")
	h.check("a prefix the engine cannot see is still dropped",
		str(audio.call("resolve_path", prefixed)) == expected,
		"'%s' -> '%s'" % [prefixed, str(audio.call("resolve_path", prefixed))])
	# And the shortest legal tail. A bare filename is what every entry that skips
	# a drive probe composes, it is legal Director, and it is the one form this
	# rule must not touch.
	h.check("a bare filename is still answered",
		str(audio.call("resolve_path", file_name)) != "",
		"'%s' -> '%s'" % [file_name, str(audio.call("resolve_path", file_name))])
	h.complete(case)

	# ------------------------------------- a folder that does not hold the file
	var other := _other_folder(files, folder, file_name)
	case = "a folder that does not hold the file is a miss, not a sibling's take"
	h.begin(case)
	if other == "":
		# Says so rather than passing quietly: this is the check the rule exists
		# for, and a root that cannot express it must not read as having passed it.
		h.check("this root has no second sound folder to ask with", false,
			"walked %d sound file(s) under %s" % [files.size(), paths.root])
	else:
		for spelled in [
			"%s/%s" % [other, file_name],
			("%s/%s" % [other, file_name]).replace("/", "\\"),
			("%s/%s" % [other, file_name]).replace("/", ":"),
		]:
			h.check("`%s` names a real folder that has no such file, so it misses"
				% spelled,
				str(audio.call("resolve_path", spelled)) == "",
				"-> '%s'" % str(audio.call("resolve_path", spelled)))
	# The same claim where the folder does not exist at all, which needs no second
	# folder and so holds on every root.
	for spelled in [
		"%s/%s" % [ABSENT_FOLDER, file_name],
		# Leading segments that match nothing are dropped one at a time, and the
		# refused one is the last: a deep request must not fall through to the
		# filename either.
		"d:/whatever/%s/%s" % [ABSENT_FOLDER, file_name],
	]:
		h.check("`%s` misses rather than falling through to the filename" % spelled,
			str(audio.call("resolve_path", spelled)) == "",
			"-> '%s'" % str(audio.call("resolve_path", spelled)))
	h.complete(case)

	# ------------------------------------------- and the refusal is *reported*
	case = "the refusal reaches the same ledger an absent file reaches"
	h.begin(case)
	var refused := ("%s/%s" % [other if other != "" else ABSENT_FOLDER, file_name]).to_lower()
	var absent := ("%s/%s" % [ABSENT_FOLDER, ABSENT_FILE]).to_lower()
	audio.call("clear_misses")
	audio.call("play_file", CHANNEL, absent)
	audio.call("play_file", CHANNEL, refused)
	var why: Dictionary = {}
	for entry_value in audio.call("misses"):
		var entry: Dictionary = entry_value
		why[str(entry["request"])] = str(entry["why"])
	h.check("the refusal was recorded, beside the ordinary absent file",
		why.has(refused) and why.has(absent),
		", ".join(PackedStringArray(why.keys())))
	var report := str(audio.call("miss_report"))
	h.check("the report names the request the script made",
		report.to_lower().contains(refused), report)
	# `push_warning` is not a reporting channel here -- nothing in this repo reads
	# one -- so the distinction between "the disc does not have this path" and
	# "the disc has this filename, under a folder the script did not name" has to
	# be in the ledger line or it is nowhere. Compared by substituting one request
	# into the other's line rather than against a literal sentence, so this asserts
	# the two are *distinguishable* without pinning the wording.
	h.check("and the two are distinguishable, not one sentence twice",
		str(why.get(refused, "")) != str(why.get(absent, "")).replace(absent, refused),
		"%s / %s" % [str(why.get(refused, "")), str(why.get(absent, ""))])
	# The other half of `_fail`, re-asserted because it is the same function: a
	# channel that answers busy for a sound that never started is a wait nothing
	# in the movie can end.
	h.check("the channel is not busy for a sound that never started",
		not bool(audio.call("sound_busy", CHANNEL)), "soundBusy(%d)" % CHANNEL)
	h.complete(case)

	# ------------------------------------------------------------ the control
	case = "the ledger is not saying yes to everything"
	h.begin(case)
	audio.call("clear_misses")
	audio.call("play_file", CHANNEL, relative)
	h.check("the subject's own path plays without being recorded as a miss",
		int(audio.call("miss_count")) == 0,
		"%d miss(es): %s" % [int(audio.call("miss_count")),
			str(audio.call("miss_report"))])
	audio.call("stop_channel", CHANNEL)
	h.complete(case)

	print("")
	print("%s -> %s" % [relative, expected])
	quit(h.finish("folder scope under %s" % str(paths.root).get_file()))


## The first sound at least one folder deep, preferring one whose filename another
## folder also carries.
##
## That preference is the whole point: a filename that appears under two folders
## is the case where dropping the folder plays the wrong take rather than merely
## the wrong file, and this corpus is full of them -- 315 of Piposh 2's 3,142
## sounds share a filename and none share a folder and a filename. Where a root
## has no such pair the first deep sound is still a valid subject; the refusal is
## a fact about the request, not about how many takes exist.
func _subject(files: Array[String]) -> Dictionary:
	var by_stem: Dictionary = {}
	for relative in files:
		if not relative.contains("/"):
			continue
		var stem := relative.get_file().get_basename()
		if by_stem.has(stem):
			by_stem[stem] = int(by_stem[stem]) + 1
		else:
			by_stem[stem] = 1
	var fallback := ""
	for relative in files:
		if not relative.contains("/"):
			continue
		if fallback == "":
			fallback = relative
		if int(by_stem.get(relative.get_file().get_basename(), 1)) > 1:
			return _describe(relative)
	if fallback == "":
		return {}
	return _describe(fallback)


func _describe(relative: String) -> Dictionary:
	return {
		"relative": relative,
		"folder": relative.get_base_dir(),
		"file": relative.get_file(),
	}


## A real folder on this disc, holding sounds, that does not hold `file_name`.
##
## **Its last segment is what has to be clean, not its whole path.** The tail
## index is keyed on every suffix of a path, so a request naming
## `elsewhere/dream1/337` is answered by `dream1/337` -- correctly, that is a
## folder-qualified match. A counter-example whose own basename happens to hold
## the subject somewhere else on the disc would therefore resolve, and the check
## would be measuring the wrong thing.
func _other_folder(files: Array[String], folder: String, file_name: String) -> String:
	var stem := file_name.get_basename().to_lower()
	# basename of a folder -> the stems any folder of that name holds.
	var held: Dictionary = {}
	var folders: Array[String] = []
	for relative in files:
		if not relative.contains("/"):
			continue
		var dir := relative.get_base_dir()
		if not folders.has(dir):
			folders.append(dir)
		var leaf := dir.get_file().to_lower()
		if not held.has(leaf):
			held[leaf] = {}
		(held[leaf] as Dictionary)[relative.get_file().get_basename().to_lower()] = true
	for dir in folders:
		if dir == folder:
			continue
		if (held.get(dir.get_file().to_lower(), {}) as Dictionary).has(stem):
			continue
		return dir
	return ""


## Every file under `at` whose bytes say it is a sound, as a root-relative path.
func _walk(base: String, at: String, out: Array[String]) -> void:
	var here := base if at == "" else base.path_join(at)
	var dir := DirAccess.open(here)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var relative := name if at == "" else at.path_join(name)
			if dir.current_is_dir():
				_walk(base, relative, out)
			elif NAMED.has(name.get_extension().to_lower()) \
					or _is_sound(here.path_join(name)):
				out.append(relative.to_lower())
		name = dir.get_next()
	dir.list_dir_end()


## This tool's own reading of a container tag, for `audio_coverage.gd`'s reason:
## a Mac file has no extension, so a name-shaped test finds a tenth of
## `piposh-dream`'s audio, and the engine's own answer cannot be both sides of
## the comparison.
static func _is_sound(full: String) -> bool:
	var file := FileAccess.open(full, FileAccess.READ)
	if file == null:
		return false
	var head := file.get_buffer(TAG_BYTES)
	file.close()
	if head.size() < 4:
		return false
	var tag := head.slice(0, 4).get_string_from_ascii()
	if tag == "FORM" or tag == "RIFF":
		if head.size() < TAG_BYTES:
			return false
		return head.slice(8, TAG_BYTES).get_string_from_ascii() in ["AIFF", "AIFC", "WAVE"]
	if tag == "OggS":
		return true
	if head.slice(0, 3).get_string_from_ascii() == "ID3":
		return true
	return head[0] == 0xFF and (head[1] & 0xE0) == 0xE0
