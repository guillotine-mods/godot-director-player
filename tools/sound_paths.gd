extends SceneTree
## A sound request is a **path**, and the byte between its segments is not
## information. Colon, backslash and slash must all reach the same file.
##
##   godot --headless --path . --script tools/sound_paths.gd
##   godot --headless --path . --script tools/sound_paths.gd -- --root rating
##
## **Why this is one rule and not two.** Director ran on the Mac first, and the
## Mac's path separator is the colon: `the moviePath` answers `HD:Rating:` there,
## so a script concatenating onto it builds `HD:Rating:sounds:batzegoz:f1.aif`.
## The Windows player wrote backslashes. Both spellings are in this corpus and
## `BATZEGOZ.dir` has both within four members of each other -- members 6, 7 and
## 8 do `soundspath & "h.aif"` against a `soundspath` built with backslashes, and
## member 81 does `the moviePath & "sounds:batzegoz:f1.aif"`. A port that folds
## one and not the other is right about whichever platform the author who wrote
## that line was sitting at.
##
## `director_paths.gd:_strip_decoration` normalises colons for *containers*. The
## sound path never goes through it, and does not need to: the fold belongs where
## the request is resolved, which is `audio_director.gd:_normalise`, applied to
## the request and to every file on disc so both sides are in one alphabet.
##
## **What this cannot assert, and says instead.** A miss is not always a bug.
## Rating asks for `sounds:batzegoz:f1.aif` and for `arcade1\startmus.aif`, and
## neither file exists anywhere under `games/rating` -- 2,618 `.aif` files and no
## `f1` and no `startmus` among them, while the sibling handlers' `h.aif`,
## `j.aif` and `q.aif` are all present. So those two are the disc's gap and not
## the resolver's, and the check that would catch a resolver regression is the
## *equivalence* below rather than a list of names that must resolve. The absent
## ones are printed at the end so the count is visible rather than folded away.
##
## Title-agnostic: the subject is found by walking the root, not named.

const Harness := preload("res://tools/lib/harness.gd")
const Paths := preload("res://director/director_paths.gd")

## Sound extensions the index accepts, so the subject is picked the same way the
## index built its keys. Restated rather than imported because `audio_director`
## keeps it inline; a drift here shows up as "no subject found", which fails.
const SOUND_EXTENSIONS := ["wav", "ogg", "mp3", "aif"]


## The first file at least two folders deep under `root`, as a root-relative
## path. Two deep because a one-segment request cannot tell a folder-aware
## resolver from a filename-only one -- which is the bug the folder work closed.
func _subject(root: String, at: String = "") -> String:
	var here := root if at == "" else root.path_join(at)
	var dir := DirAccess.open(here)
	if dir == null:
		return ""
	var sub_dirs: Array = []
	for name in dir.get_files():
		if name.get_extension().to_lower() in SOUND_EXTENSIONS \
				and at.split("/", false).size() >= 2:
			return at.path_join(name)
	for name in dir.get_directories():
		if name.begins_with("."):
			continue
		sub_dirs.append(name)
	sub_dirs.sort()
	for name in sub_dirs:
		var found := _subject(root, at.path_join(name) if at != "" else str(name))
		if found != "":
			return found
	return ""


func _init() -> void:
	var h := Harness.new()

	# The mixer, not the player. `AudioDirector` is an autoload and it indexes the
	# root by itself, so nothing here needs a movie -- which also means this runs
	# against a `--root` whose boot movie is another title's and does not exist.
	# One frame, because an autoload is not on the tree during `_init`.
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	var paths := Paths.new()
	paths.load_config()
	if audio == null:
		print("no AudioDirector; this has to run in the project, not standalone")
		quit(1)
		return

	var relative := _subject(paths.root)
	print("root    : %s" % paths.root)
	print("subject : %s" % (relative if relative != "" else "(none found)"))

	h.begin("the root carries a sound at least two folders deep")
	h.check("one was found, so the checks below have a subject", relative != "",
		relative)
	if relative == "":
		h.complete("the root carries a sound at least two folders deep")
		quit(h.finish("sound path separators under %s" % str(paths.root).get_file()))
		return
	h.complete("the root carries a sound at least two folders deep")

	var slashed := relative.to_lower()
	var expected := str(audio.call("resolve_path", slashed))

	h.begin("colon, backslash and slash are one request")
	h.check("the slash form resolves at all", expected != "", expected)
	for form in [
		["Mac colon", slashed.replace("/", ":")],
		["Windows backslash", slashed.replace("/", "\\")],
		# The whole thing a script builds: `the moviePath & <path>`, with the
		# separator the author's platform used. This is the literal shape of
		# `BATZEGOZ.dir` member 81.
		["moviePath & colon", "%s:%s" % [paths.root, slashed.replace("/", ":")]],
		["moviePath & backslash", "%s\\%s" % [paths.root, slashed.replace("/", "\\")]],
		# A prefix the engine cannot see: the volume the movie was authored on.
		# Leading segments are dropped until something matches, and that is what
		# makes an absolute Mac path answerable at all.
		["a Mac volume in front", "Macintosh HD:%s" % slashed.replace("/", ":")],
	]:
		var got := str(audio.call("resolve_path", str(form[1])))
		h.check("%s reaches the same file" % str(form[0]), got == expected,
			"'%s' -> '%s'" % [str(form[1]), got])
	h.complete("colon, backslash and slash are one request")

	# The folder in a request is meaning, so the equivalence above must not be
	# the trivial one where everything resolves to the same file anyway. The
	# control is a request naming a folder that does not exist: it must miss,
	# whatever separator it is spelled with, or the resolver is matching on the
	# filename and the checks above measured nothing.
	h.begin("...and the folder in the request still decides")
	var bogus := "nosuchfolder/%s" % relative.get_file().to_lower()
	for separator in ["/", ":", "\\"]:
		var spelled := bogus.replace("/", separator)
		var got := str(audio.call("resolve_path", spelled))
		# **The paragraph above said "it must miss" and the assertion under it
		# checked that the three spellings agreed -- which they did, by all three
		# resolving to the subject through the bare-filename tail.** So the
		# control could not fail: a resolver ignoring folders outright passed it
		# exactly as loudly as one honouring them, which is the shape
		# `porting-fidelity-verification` is about, and it sat one line under a
		# comment stating the stronger claim. The request's own trailing folder is
		# no longer dropped (`audio_director.gd:_request_tails`), so what is
		# asserted here is now what is written above it.
		h.check("`%s` names no folder on the disc, so it misses" % spelled,
			got == "", "'%s'" % got)
	# The real discriminator: two files sharing a filename under different
	# folders must stay two files. Skipped, loudly, where the root has no such
	# pair -- 315 of Piposh 2's 3,142 sounds share a filename and 0 share a
	# folder and a filename, so this is the common case rather than a contrived
	# one.
	var pair := _shared_name_pair(paths.root)
	if pair.is_empty():
		print("no two files under this root share a filename; the folder check is skipped")
	else:
		for form in [pair[0], str(pair[0]).replace("/", ":"), str(pair[0]).replace("/", "\\")]:
			h.check("`%s` is not the same file as `%s`" % [form, pair[1]],
				str(audio.call("resolve_path", str(form)))
					!= str(audio.call("resolve_path", str(pair[1]))),
				str(audio.call("resolve_path", str(form))))
	h.complete("...and the folder in the request still decides")

	print("")
	print("%s -> %s" % [slashed, expected])
	quit(h.finish("sound path separators under %s" % str(paths.root).get_file()))


## Two root-relative paths that share a filename and differ in folder, or `[]`.
## The pair the folder rule is *for*: this corpus keeps the same actor's lines
## under several folders, and matching on the filename played the wrong take.
func _shared_name_pair(from_root: String) -> Array:
	var by_name: Dictionary = {}
	var stack: Array = [""]
	while not stack.is_empty():
		var at := str(stack.pop_back())
		var here := from_root if at == "" else from_root.path_join(at)
		var dir := DirAccess.open(here)
		if dir == null:
			continue
		for name in dir.get_files():
			if not name.get_extension().to_lower() in SOUND_EXTENSIONS:
				continue
			var key := name.to_lower()
			var relative := (at.path_join(name) if at != "" else str(name)).to_lower()
			if by_name.has(key):
				return [str(by_name[key]), relative]
			by_name[key] = relative
		for name in dir.get_directories():
			if not name.begins_with("."):
				stack.append(at.path_join(name) if at != "" else str(name))
	return []
