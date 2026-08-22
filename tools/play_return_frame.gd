extends SceneTree
## An interlude in another movie returns to the frame that called it, and to no
## other frame of it.
##
##   godot --headless --path . --script tools/play_return_frame.gd -- --root rating
##   godot --headless --path . --script tools/play_return_frame.gd -- --root piposh-dream
##   godot --headless --path . --script tools/play_return_frame.gd -- --root rating --only manaegoz.dir
##
## `play frame X of movie Y` and the `play done` that answers it are one `goto`
## each in the reference: `Lingo::func_play` pushes `{movie, frameI}` and hands
## the pop straight to `func_goto(frameI, movie)` (`lingo-funcs.cpp:181-194`).
## The *frame travels with the movie* -- `func_goto` writes it into
## `_nextMovie.frameI` (`:107-112`) and the caller arrives standing on it.
##
## This port loads the movie synchronously instead, and a `go to movie` with no
## destination starts at frame 0 like any other: `MovieSession.adopt` zeroes
## `_index`, and `lingo_go_movie` then sends `prepareFrame` and `enterFrame` for
## whatever frame that is. So a return that named the movie and *not* the frame
## entered the caller's **frame 0** -- ran its `on enterFrame`, its score sound,
## its palette and its transition -- and only then moved the playhead to the
## return address. `docs/bugs-closed.md` 133: Rating's save/load office is `MANAEGOZ.dir`,
## whose frame 0 opens the scene with `sound playFile 1, soundspath &
## "Mena1.aif"`, so every open of the save list and every open of the load list
## replayed the manager's greeting over the line that was already playing. QA
## reported it as "the same clip from the start of the conversation, every time".
##
## The invariant is one sentence and it is not about sound: **the only frame of
## the caller that a return enters is the frame the return addresses.** Any
## other frame entered is that frame's whole entry -- scripts, sound, palette,
## transition -- run in a room the player is not in.
##
## ## What it drives, and why it discovers rather than lists
##
## The sites are found, not named: every frame of every container under the root
## whose *frame script* holds a `play ... of movie ...`, which is the placement a
## harness can stand on. A sprite behaviour that does the same thing needs the
## click that fires it and is counted and printed rather than driven, so the
## number this prints says what it left alone.
##
## Frame scripts only is a real restriction and it is worth knowing how much it
## covers: over all six roots, `tools/script_placement.gd -- --match 'play
## +(frame +)?[^\n]*of +movie' --all` finds 20 score-placed sites, **5** of them
## frame scripts -- `rating`'s `manaegoz.dir` f156 and f302, and
## `piposh-dream`'s `mainmenu.dir` f108, `ques.dir` f803 and `strtgame.dir`
## f823. The other 15 are sprite behaviours: Rating's six locked doors in each
## of `navigat2.dir` and `navigat3.dir`, and the save and load buttons of the
## office itself. All 20 take the same return, so the five that can be stood on
## are a sample of one mechanism and not five separate cases.
##
## A root with no such site asserts that it was swept and passes -- `piposh2`,
## the configured corpus, is exactly that and is why this reads as a "measured
## zero" if the root is not named. `--only <container>` narrows to one.
##
## Title-agnostic: no container, frame or movie name appears below.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")

## `play`, optionally `frame <something>`, then `of movie`. Case-insensitive, and
## deliberately loose about what sits between: the movie is as often built out of
## a global (`installpath & "saves.dir"`) as written as a literal.
const CROSS_MOVIE := "(?i)\\bplay\\b[^\\n]*?\\bof\\s+movie\\b"

## Ticks allowed for one site: enough for the interlude to be entered, run its
## own frames and come back. Measured at 2 to 3 ticks for `rating`'s two and 12
## to 14 for `piposh-dream`'s three, which is the interlude's own frame count and
## tempo rather than anything about the return. The ceiling is for a site that
## never returns -- a failure, not something to wait out.
const PATIENCE := 120


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var paths = preview.get("_paths")
	if paths == null:
		h.check("a game is configured", false, "no paths")
		quit(h.finish("a cross-movie interlude returns to its caller's frame"))
		return

	var only := Args.text(args, "only", "").to_lower()
	var found: Array = _sites(paths, only)
	var root_name := str(paths.root).get_file()

	# Printed before the driving, so a run that dies part way through still says
	# what it was going to do -- and so a root that yields nothing says that it
	# looked rather than leaving a silent pass.
	# `_opened` counts movies that yielded both a score and a cast, which is fewer
	# than the containers on disc: a `.cst` is not walked at all and a `.dir` with
	# no `VWSC` places nothing. Named as what it counted, per `AGENTS.md` on a
	# number that reads as a corpus measurement.
	print("root %s: %d movie(s) with a score, %d frame-script site(s), %d sprite-behaviour site(s) left alone"
		% [root_name, _opened, found.size(), _sprite_sites])
	for skipped in _unreadable:
		print("   unreadable %s" % skipped)
	print("")

	# The sweep itself is asserted, for `label_index`'s reason: a root whose
	# containers all failed to open would otherwise be the cleanest of the six.
	h.begin("%s: swept" % root_name)
	h.check("%s: the sweep reached its movies" % root_name, _opened > 0,
		"%d read, %d unreadable" % [_opened, _unreadable.size()])
	h.complete("%s: swept" % root_name)

	for site_value in found:
		var site: Dictionary = site_value
		await _drive(preview, h, site)

	quit(h.finish("a cross-movie interlude returns to its caller's frame and enters no other"))


var _opened := 0
var _sprite_sites := 0
var _unreadable: Array[String] = []


## Every frame whose own frame script holds a cross-movie `play`, per container.
##
## The score names the library as well as the member (`preview/scripts.gd:171`),
## so the member is resolved in the library the score named rather than by number
## -- a frame script number alone matches whichever linked cast answers first,
## and this corpus links the same numbers in four casts.
func _sites(paths, only: String) -> Array:
	var out: Array = []
	var files := PackedStringArray()
	_collect(str(paths.root), files)
	files.sort()
	var pattern := RegEx.new()
	pattern.compile(CROSS_MOVIE)
	for path in files:
		var rel := str(path).get_file()
		if only != "" and rel.to_lower() != only:
			continue
		var f := ContainerFile.new()
		if not f.open(path):
			_unreadable.append("%s: %s" % [rel, f.error])
			continue
		var ids: Array = f.ids_of("VWSC")
		if ids.is_empty():
			f.close()
			continue
		var score = Score.new()
		if not score.parse(f.read_chunk(ids[0])):
			_unreadable.append("%s: %s" % [rel, score.error])
			f.close()
			continue
		var table = CastTable.new()
		if not table.open(f, paths):
			_unreadable.append("%s: no cast" % rel)
			f.close()
			continue
		_opened += 1
		# One reading of each member, because a frame script covers a span of
		# frames and every frame of the span names the same member.
		var verdict: Dictionary = {}
		for index in score.frame_count:
			var frame: Dictionary = score.frame(index)
			var member = frame.get("frame_script")
			if member == null:
				continue
			var lib := int(frame.get("frame_script_lib", 1))
			var key := "%d:%d" % [lib, int(member)]
			if not verdict.has(key):
				verdict[key] = _matches(table, lib, int(member), pattern)
			if not bool(verdict[key]):
				continue
			# The *first* frame of the span, not every frame of it: the whole span
			# runs the same handler, so standing on each in turn would drive one
			# site many times and say nothing new.
			if not out.is_empty():
				var last: Dictionary = out[-1]
				if str(last["file"]) == rel and str(last["key"]) == key \
						and int(last["frame"]) == index - 1:
					out[-1]["frame"] = index
					out[-1]["from"] = int(last["from"])
					continue
			out.append({"file": rel, "frame": index, "from": index, "key": key})
		# Counted, not driven: a behaviour needs the click that fires it, and this
		# number is what says how much of the mechanism went undriven.
		_sprite_sites += _sprite_placements(score, table, pattern)
		table.close()
		f.close()
	# `from` is the frame to stand on; collapse the span record into it.
	var sites: Array = []
	for entry_value in out:
		var entry: Dictionary = entry_value
		sites.append({"file": str(entry["file"]), "frame": int(entry["from"])})
	return sites


func _matches(table, lib: int, member: int, pattern: RegEx) -> bool:
	var cast = table.cast_for(lib)
	if cast == null:
		return false
	var m: Dictionary = cast.member(member)
	var src := str(m.get("source", ""))
	if src.is_empty():
		return false
	return pattern.search(src) != null


## Sprite behaviours that hold the same statement, counted once per span.
func _sprite_placements(score, table, pattern: RegEx) -> int:
	var count := 0
	var seen: Dictionary = {}
	for interval_value in score.intervals():
		var interval: Dictionary = interval_value
		if str(interval["kind"]) == "frame":
			continue
		var lib := int(interval.get("script_cast_lib", 1))
		var member := int(interval.get("script_member", 0))
		if member <= 0:
			continue
		var key := "%d:%d" % [lib, member]
		if not seen.has(key):
			seen[key] = _matches(table, lib, member, pattern)
		if bool(seen[key]):
			count += 1
	return count


## One site: stand on the frame, let its `exitFrame` play the interlude, and watch
## the playhead until the caller's container is back.
##
## The two readings are taken on the same tick and are the whole assertion.
## `current_frame` is where the playhead *is*; `_entered_index` is the last frame
## an entry was sent for. They agree on every ordinary step, and the return that
## crossed a container boundary without carrying its frame is exactly where they
## do not.
func _drive(preview: Node, h: Harness, site: Dictionary) -> void:
	var file := str(site["file"])
	var frame := int(site["frame"])
	var case_name := "%s f%d" % [file, frame]
	h.begin(case_name)

	preview.call("lingo_go_movie", file, null)
	for _i in 8:
		await process_frame
	if str(preview.call("movie_name")).to_lower() != file.to_lower():
		h.check("%s: the caller opens" % case_name, false,
			"opened %s" % str(preview.call("movie_name")))
		h.complete(case_name)
		return

	preview.set("_index", frame)
	var left := ""
	var returned := -1
	var entered := -1
	var ticks := 0
	for i in PATIENCE:
		await process_frame
		ticks = i + 1
		var here := str(preview.call("movie_name"))
		if left == "":
			if here.to_lower() != file.to_lower():
				left = here
			continue
		if here.to_lower() != file.to_lower():
			continue
		# The tick the caller is back on, read before another step can enter the
		# return frame and paper over an entry that went somewhere else.
		returned = int(preview.call("current_frame"))
		entered = int(preview.get("_entered_index"))
		break

	if not h.check("%s: the interlude is entered" % case_name, left != "",
			"left for %s" % left if left != "" else
			"the movie never changed in %d tick(s)" % ticks):
		h.complete(case_name)
		return
	if not h.check("%s: the interlude returns" % case_name, returned >= 0,
			"after %d tick(s)" % ticks if returned >= 0 else
			"still in %s after %d tick(s)" % [left, ticks]):
		h.complete(case_name)
		return
	# `play` from a frame script records the frame *after* the caller's
	# (`lingo-funcs.cpp:211-212`, `docs/bugs-closed.md` 54), which is what makes the
	# expected address arithmetic rather than a reading of the stack.
	h.check("%s: returns past the frame that called it" % case_name,
		returned == frame + 1, "f%d, expected f%d" % [returned, frame + 1])
	h.check("%s: enters no other frame of the caller" % case_name,
		entered == returned,
		"entered f%d" % entered if entered == returned else
		"playhead f%d, but the last frame entered was f%d" % [returned, entered])
	print("   %-16s left for %-16s came back to f%d, entered f%d, %d tick(s)"
		% [case_name, left, returned, entered, ticks])
	h.complete(case_name)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.get_extension().to_lower() in ["dir", "dxr"]:
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
