extends SceneTree
## A film loop whose child is itself a film loop draws the inner loop's artwork.
##
##   godot --headless --path . --script tools/film_loop_nesting.gd -- --root piposh-dream
##
##   --root R     the corpus (default the config's)
##   --file F     the container to play (default COMEIN.dir)
##   --index N    the frame to land on before walking in (default 720)
##   --ticks N    process frames to play for at most (default 12000)
##
## Runs headless, which `gate.sh` requires of every entry, and paint runs headless
## in this engine -- `tools/film_loop_restart.gd`'s docstring carries the
## measurement that says so, and this harness reads the same painter records.
##
## ## What the number means
##
## `scenes/preview/film_loop_view.gd` drew a loop's children by asking
## `host._texture_for` for each one, and that path is bitmap-and-shape only: a
## type-2 child answered null, was tallied `"child has no art"`, and the whole
## inner loop was skipped. Director nests (DIRECTOR_ENGINE.md §1.6, §6.3), so that
## was a hole rather than a limitation, and the player-visible shape of it is a
## game with none of its projectiles in it.
##
## The census this was measured against: over all six roots, exactly **10 nested
## sites in 2 titles** -- three in `piposh-dream/comein.dir`, one in its
## `hatul1.dir`, one in its `show.dir` and five in `rating/blatack1.dir`. `piposh`,
## `piposh-en`, `piposh-ru` and `piposh2` have none, the deepest nesting anywhere is
## 2, and nothing nests itself. So this is the only kind of site there is to test,
## and `GATE_ROOT` cannot express it at all -- hence the entry names its own root.
##
## ## Why this container, and how it is entered
##
## `COMEIN.dir` holds `piposh-dream`'s six minigames, one per character, and
## Hatuli's is the projectile game: three 21-frame `looping=false` ball loops
## (`1:156`..`1:158`) each nesting the 8-frame `looping=true` `stone` (`1:167`),
## whose own eight children are the bitmaps that are the picture on screen. It is
## the cheapest played nested site of the ten -- `show.dir` and `hatul1.dir` both
## hold on a `soundBusy` gate in their opening speech before their nested loop is
## ever placed (`sndbusy1` on channel 1, measured stuck at f2..f10 of `hatul1`), and
## `rating/blatack1.dir` places its five `grnd` loops from a script rather than from
## the score, so reaching them means landing a hit in a fight.
##
## **The movie is walked into, not jumped into**, and the reason is budget rather
## than correctness. An earlier version of this note claimed landing on the game's
## own init marker produced "a convincing dead screen with nothing drawn at all",
## with figures beside it; measured, that is false. `--index 722` -- whose first
## played frame is f723, `return5` -- reaches a nested loop and passes 3 of 3 too.
## What it costs is margin: it spent **2786 process frames** against **621** from
## f720, which under this file's original 3000 default was one slow machine away
## from a FAIL -- not a `gate.sh` TIMEOUT, which is that file's 900s wall ceiling:
## a run out of `--ticks` simply never sees the key and reports the assertion red.
## So the playhead is put down at f720, *inside* the
## speech that precedes the game, and the movie then runs f722 (member 404), f723
## (`return5`) and f724 (`w1`, the throw) itself. The game is a loop over f724..f753
## that throws one ball per pass, so it keeps offering nested children for as long
## as the harness watches; the run stops as soon as the invariant is observed rather
## than playing a fixed window, which is what makes it insensitive to how many
## passes a loaded machine gets through.
##
## ## What is asserted
##
## That **leaf artwork from inside a nested loop reaches the painter**. Not that a
## tally key exists: a counter that reads zero before the fix only because the key
## had not been invented yet asserts that this code ran, and nothing about the
## engine. Before the fix the inner loop is skipped whole, so its own children are
## never asked for -- so the honest 0-to-non-zero measurement is that a member
## reachable **only** through a nested loop appears in the node's `_textures` cache,
## which is the painter asking the cast to decode it.
##
## Measured: **0 of `stone`'s eight frames before, all 8 after.** That pair comes
## from a window played out to the end of the game, not from this harness, which
## breaks at the first key it sees and so prints one -- the assertion here is
## 0-versus-at-least-1, and the eight are what the fix is worth.
##
## "Only through a nested loop" is derived rather than asserted. The container's
## loops are walked into a graph, the loops that are nobody's child are its roots,
## and a member is claimed here only if every route to it from a root is two levels
## deep or more *and* the score never places it directly. For `COMEIN` that is
## exactly `1:159`..`1:166`, and `1:167` itself is excluded because it is a child.
##
## ## And that it arrives at the right *size*, which was a second bug
##
## Reaching the painter is not the same as being drawn correctly, and the gap between
## the two was `docs/bugs-closed.md` 99: the ball loops `1:156`..`1:158` shrink their
## `stone` child across the throw -- the score's own records take it 72x72, 69x69,
## 52x53, 20x21 over 21 frames -- and `nested_scale` turned that into a shrinking
## factor for the stone's own eight bitmaps, which `Geometry.drawn_size` then threw
## away because their records carry no stretch flag. The stone's *position* scaled
## and its pixels never did. A player reported it as the balls in Hatuli's game not
## shrinking as they fly, and this harness was green throughout, because it only ever
## asked whether the artwork appeared.
##
## So the size is asserted too, and the observable is already in the cache: the
## node's `_textures` is keyed by `Geometry.texture_key`, which carries the drawn
## size, so **one leaf member under two or more distinct sizes** is the fix and one
## size for all of them is the bug. Nothing here computes an expected size -- that
## would be this file re-deriving the arithmetic it is checking -- it asserts only
## that the size is not constant across a throw, which is the player-visible claim
## and cannot be satisfied by a loop that ignores its parent's squeeze.
##
## Two distinct sizes and not more, deliberately: the run breaks at the first leaf
## that has two, so what it costs is bounded by the first shrink rather than by the
## whole throw. Measured on `--root piposh-dream`, `1:159` comes back **69x64 and
## 66x61** after 1,343 of the 12,000 process frames, over score frames f721..f753.
##
## The negative control is the fix reverted, and it fails **on this check alone**
## with the two above it still green -- the useful shape, because it says the
## artwork was arriving all along and only its size was wrong. It is also not a
## budget failure, which is the reading a FAIL on a played harness always has to
## rule out: that run played its whole 12,000 frames and got **more** score frames
## than the passing one, 49 over f722..f771 against 33, and still reports one size
## for every one of the eight leaves. More opportunity, no shrink.
##
## Both halves of the fix have to come out for the control, and not because either
## is optional: `film_loop_view.child_sprite` names
## `Geometry.SIZE_COMPUTED`, so reverting `sprite_geometry.gd` alone is a parse
## error in `_init` and reports as a run with no output rather than as a FAIL --
## the same trap `DEPTH_CAP` below is written the way it is to avoid.
##
## Where the slack is, on a check whose evidence arrives at the *end* of a pass: the
## game throws one ball per pass over f724..f753 and the texture cache accumulates
## across passes, so a machine slow enough to get fewer score frames per process
## frame still collects sizes -- it collects them over more passes. And the failure
## line prints every leaf with every size it was seen at, so a run that genuinely
## ran out is told from a run that saw a constant size by reading it.
##
## Beside it, and in the style of `tools/film_loop_scale.gd`'s population guard --
## "0 wrong is also what a check with nothing left to look at prints" -- the run
## asserts that a loop with a film-loop child really was painted. That guard reads
## the painter's own parse cache and holds with the fix and without it, so a run
## that never reached the game fails as a run that proved nothing rather than
## passing over an empty set.
##
## Title-agnostic in its rule and not in its fixture, which is the split
## `film_loop_restart.gd` makes: the graph walk names no member, and the container
## and the frame to land on are this corpus's.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")

const LOOP_TYPE := 2
## How deep the census walk goes, mirroring `film_loop_view.gd:MAX_DEPTH`.
##
## Its own constant rather than a read of the painter's, so that this harness
## compiles and runs against a tree *without* the recursion in it. That is not
## tidiness: the negative control for this whole change is running this file with
## `film_loop_view.gd` reverted, and reading `FilmLoopView.MAX_DEPTH` there is a
## parse error in `_init` before the first assertion -- which reports as a run that
## produced no output, not as the FAIL that proves the fix does something.
const DEPTH_CAP := 5
## The container with the cheapest played nested site, and the frame to land on.
## f720 is inside the speech before Hatuli's game; the movie walks itself through
## f723 `return5`, which is the init marker landing on directly would skip.
const MOVIE := "COMEIN.dir"
const ENTER_AT := 720


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	var paths = Paths.new()
	if not paths.load_config():
		print("FAIL  no game configured")
		quit(1)
		return
	var rel := Args.text(args, "file", MOVIE)

	# The census is read off the disc rather than off the run, so what the run is
	# asked for is decided before it starts and cannot be shaped by what it drew.
	var census := _census(paths, rel)
	if census.is_empty():
		print("FAIL  cannot read %s under %s" % [rel, paths.root])
		quit(1)
		return
	var parents: Dictionary = census["parents"]
	var only: Array = census["only_nested"]
	print("nested parents : %s" % str(parents.keys()))
	print("only nested    : %s" % str(only))

	h.begin("a nested film loop's artwork reaches the painter")
	# Asserted first, because everything below it is a claim about this set. A
	# container with no nested loop in it makes the two checks after this one pass
	# over nothing at all, which is the failure `gate.sh`'s EMPTY guard catches one
	# level up and cannot catch here -- the checks would be present and vacuous.
	h.check("%s holds a film loop whose child is a film loop" % rel,
		not parents.is_empty() and not only.is_empty(),
		"%d nesting loop(s), %d member(s) reachable only inside one"
			% [parents.size(), only.size()])

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", rel, null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("FAIL  no score loaded for %s" % rel)
		quit(1)
		return
	preview.set("_index", Args.number(args, "index", ENTER_AT))
	for i in 8:
		await process_frame

	var painted := ""     # the first nesting loop the painter parsed
	var decoded := ""     # the first inner-loop-only member it asked to decode
	var sizes: Dictionary = {}  # "lib:id" -> {"WxH": true} every size it decoded at
	var frames: Dictionary = {}
	# 12000 rather than 3000, and it costs nothing on the happy path because the loop
	# below breaks on the condition rather than playing the budget out: this entry
	# measured 621 frames from f720. It is a ceiling for a loaded machine, not a
	# driver. Score frames advance on real time -- tempo waits and `soundBusy` --
	# so a machine with several Godot runs on it burns more process frames per score
	# frame, and a budget tight enough to matter is the `play_suspends` failure
	# `gate.sh`'s header records: a fixed frame count standing in for a condition.
	var ticks := Args.number(args, "ticks", 12000)
	var spent := 0
	for tick in ticks:
		await process_frame
		spent = tick + 1
		frames[int(preview.call("current_frame"))] = true
		if painted == "":
			for key in preview.get("_loops") as Dictionary:
				if parents.has(str(key)):
					painted = str(key)
					break
		# Every size each leaf member was decoded at, not just the first key seen. The
		# cache is keyed by `Geometry.texture_key`, whose fourth field is the drawn
		# size, so one leaf member appearing under several keys *is* the observation --
		# see `_shrinking` and the header.
		for key in preview.get("_textures") as Dictionary:
			for member in only:
				if not str(key).begins_with("%s:" % str(member)):
					continue
				if decoded == "":
					decoded = str(key)
				var parts: PackedStringArray = str(key).split(":")
				if parts.size() > 3:
					if not sizes.has(str(member)):
						sizes[str(member)] = {}
					(sizes[str(member)] as Dictionary)[parts[3]] = true
		# Stopped on the answer rather than after a fixed window. The game throws one
		# ball per pass over f724..f753, so how many passes a run gets through varies
		# with the machine; waiting for the invariant turns that into a difference in
		# how long the run takes instead of a difference in what it finds.
		if painted != "" and decoded != "" and not _shrinking(sizes).is_empty():
			break

	var visited: Array = frames.keys()
	visited.sort()

	h.check("the painter reached a film loop that has a film-loop child",
		painted != "",
		"%s" % painted if painted != "" else "none of %s over %d frame(s) f%s..f%s"
			% [str(parents.keys()), visited.size(),
				str(visited[0]) if visited.size() > 0 else "?",
				str(visited[-1]) if visited.size() > 0 else "?"])
	h.check("artwork from inside the nested loop was asked of the cast",
		decoded != "",
		"%s" % decoded if decoded != "" else
			"no key for any of %s in the texture cache" % str(only))
	var shrank: Array = _shrinking(sizes)
	h.check("the nested loop's leaf artwork is drawn at more than one size, so the"
		+ " squeeze on the loop above reaches the pixels",
		not shrank.is_empty(),
		"%s" % ", ".join(shrank) if not shrank.is_empty()
			else "every leaf held one size: %s" % _sizes_line(sizes))
	h.complete("a nested film loop's artwork reaches the painter")

	print("")
	print("played     : %d process frame(s) of %d, %d frame(s) f%s..f%s" % [
		spent, ticks, visited.size(),
		str(visited[0]) if visited.size() > 0 else "?",
		str(visited[-1]) if visited.size() > 0 else "?"])
	print("leaf sizes : %s" % _sizes_line(sizes))
	var stats: Dictionary = preview.get("_loop_stats")
	var keys: Array = stats.keys()
	keys.sort()
	for key in keys:
		print("loop tally : %-38s %d" % [key, int(stats[key])])
	quit(h.finish("a film loop nested in a film loop is drawn"))


## Every leaf member the painter decoded at more than one size, largest first, as
## `"1:159 69x64 -> 17x16"` -- the observation that the squeeze reached the pixels.
##
## The comparison is by area rather than per axis because the two axes shrink
## together here and one number reads as a shrink where two read as a table. A
## member is claimed only on **two distinct sizes**, which is what the assertion
## turns on; the arrow is presentation.
func _shrinking(sizes: Dictionary) -> Array:
	var out: Array = []
	var members: Array = sizes.keys()
	members.sort()
	for member in members:
		var seen: Array = (sizes[member] as Dictionary).keys()
		if seen.size() < 2:
			continue
		seen.sort_custom(func(a, b): return _area(str(a)) > _area(str(b)))
		out.append("%s %s -> %s" % [str(member), str(seen[0]), str(seen[-1])])
	return out


## `WxH` as an area, for ordering. 0 for anything that does not parse, which cannot
## happen for a key this file built the string from and is not worth a branch above.
func _area(size: String) -> int:
	var parts: PackedStringArray = size.split("x")
	if parts.size() != 2:
		return 0
	return int(parts[0]) * int(parts[1])


## Every leaf and every size it was decoded at, printed whether the run passed or
## failed. On a failure it is the evidence -- one size per member is exactly what a
## leaf drawn at a constant size looks like -- and on a pass it is the record of how
## far the ball actually got before the loop broke.
func _sizes_line(sizes: Dictionary) -> String:
	var members: Array = sizes.keys()
	members.sort()
	var parts: Array = []
	for member in members:
		var seen: Array = (sizes[member] as Dictionary).keys()
		seen.sort_custom(func(a, b): return _area(str(a)) > _area(str(b)))
		parts.append("%s[%s]" % [str(member), ",".join(seen)])
	return "none" if parts.is_empty() else " ".join(parts)


## The container's nesting, read off the disc.
##
##   parents      "lib:id" of every loop that has a film-loop child
##   only_nested  "lib:id" of every member with no route to the stage that does
##                not pass through a nested loop
##
## The second is the one that needs care, and the naive reading of it is wrong: a
## sweep over the casts walks the *inner* loop as a member in its own right too, so
## taking "every depth-1 child of every loop" as the members reachable without
## nesting excludes the inner loop's own children and leaves the set empty. Measured
## on `COMEIN`: the naive form answers 0, and the graph form answers `1:159`..`1:166`.
##
## So the loops are walked as a graph instead. A loop that is nobody's child is a
## root -- it can only arrive on a channel, from the score or from a script -- and
## the depth of a member is the shortest route to it from any root. Depth 1 is a
## loop's own child and needs no recursion to draw; depth 2 or more needs it. A
## member the score places directly is excluded whatever its depth, because the main
## score reaches it without any of this.
func _census(paths, rel: String) -> Dictionary:
	var f := ContainerFile.new()
	if not f.open(paths.resolve(rel)):
		return {}
	var table = CastTable.new()
	if not table.open(f, paths):
		f.close()
		return {}

	var kids: Dictionary = {}     # "lib:id" of a loop -> its distinct children
	var parents: Dictionary = {}  # "lib:id" of a loop with a film-loop child
	var is_child: Dictionary = {} # "lib:id" that some loop draws
	for n in table.cast_libs:
		var lib := int(n)
		var cast = table.cast_for(lib)
		if cast == null:
			continue
		for number in range(1, cast.member_count + 2):
			var m: Dictionary = cast.member(number)
			if m.is_empty() or int(m.get("type", 0)) != LOOP_TYPE:
				continue
			# Through the preview's own entry point, so the graph is the one the
			# painter walks rather than a second reading written here.
			var loop = FilmLoopView.open_loop(lib, m, table)
			if loop == null:
				continue
			var key := "%d:%d" % [lib, number]
			var mine: Dictionary = {}
			for i in loop.frame_count:
				for kid in loop.children(i):
					var kid_lib: int = FilmLoopView.child_lib(kid, lib, table)
					if kid_lib < 0:
						continue
					var kid_key := "%d:%d" % [kid_lib, int(kid["cast_id"])]
					mine[kid_key] = true
					is_child[kid_key] = true
					var cm: Dictionary = table.get_member(kid_lib, int(kid["cast_id"]))
					if int(cm.get("type", 0)) == LOOP_TYPE:
						parents[key] = true
			kids[key] = mine

	var placed: Dictionary = {}
	var vwsc: Array = f.ids_of("VWSC")
	if not vwsc.is_empty():
		var score := Score.new()
		if score.parse(f.read_chunk(vwsc[0])):
			for i in score.frame_count:
				for sprite in score.frame(i).get("sprites", []):
					placed["%d:%d" % [
						int(sprite["cast_lib"]), int(sprite["cast_id"])]] = true

	# Shortest route from a root, breadth first. Depth is capped at `DEPTH_CAP`, the
	# painter's own cap written out here, so a loop that contains itself terminates
	# here the same way it terminates there.
	var depth: Dictionary = {}
	var wave: Array[String] = []
	for key in kids:
		if not is_child.has(key):
			wave.append(str(key))
			depth[str(key)] = 0
	var level := 0
	while not wave.is_empty() and level <= DEPTH_CAP:
		var next: Array[String] = []
		for key in wave:
			for kid_key in kids.get(key, {}) as Dictionary:
				if depth.has(str(kid_key)):
					continue
				depth[str(kid_key)] = level + 1
				next.append(str(kid_key))
		wave = next
		level += 1

	var only: Array[String] = []
	for key in depth:
		if int(depth[key]) >= 2 and not placed.has(str(key)):
			only.append(str(key))
	only.sort()

	f.close()
	table.close()
	return {"parents": parents, "only_nested": only}
