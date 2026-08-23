extends SceneTree
## `Score::renderCursor`'s descent, against the rect-only one it replaced.
##
##   godot --headless --audio-driver Dummy --path . --script tools/cursor_descent.gd
##   godot --headless --audio-driver Dummy --path . --script tools/cursor_descent.gd -- \
##     --root piposh --survey
##   godot --headless --audio-driver Dummy --path . --script tools/cursor_descent.gd -- \
##     --survey --all
##
##   --survey        report every point in the corpus where the two descents
##                   disagree, instead of asserting
##   --all           survey every root under games/ and test-games/
##   --limit N       how many containers a survey opens per root (default 24)
##   --steps N       how many `_advance` steps to settle a movie (default 250)
##   --frames N      how many frames to scan for a text site (default 400)
##
## ## What is being compared
##
## `preview/cursor.gd:at` used to walk the sprite stack with its own geometry:
##
##     if not channel_cursors.has(channel): continue     # cursor first
##     if not rect.has_point(point): continue            # then a bare rect
##
## `score.cpp:1461-1470` walks it with `isMouseIn` and takes the cursor second,
## which differs in **three** ways at once -- per-pixel matte geometry, the Hole,
## and the order. `_old_at` below is that loop kept verbatim so the two can be run
## against each other on the same frame; it is the only copy of the retired rule
## left in the repository, and it is here because "the new one is green" says
## nothing about whether anything moved.
##
## ## Which of the three this corpus can show, measured rather than assumed
##
## **The matte arm is corpus-visible and is asserted on a real sprite.** `--survey`
## finds the sites: a channel carrying a `[data, mask]` cursor, drawn with Matte
## ink over a bitmap, and a point inside its rect where the artwork is
## transparent. The old descent answers that channel's cursor there; Director
## walks past it. The survey's numbers are printed by the run, so a reader can see
## whether the case it asserted on is one of many or the only one.
##
## **The Hole is not, and cannot be.** 0 members of box type `scroll` exist in any
## of the eight roots (`tools/hole_survey.gd`), so no title in reach can author
## one. This does what `tools/hit_hole.gd` does for the click descent and for the
## same reason: it writes **one authoring byte** -- `text_type`, `the boxType of
## member`, the author's own choice in Director's Field dialog -- to the in-memory
## member and puts it back before the run ends. Nothing under `games/` is touched.
##
## The Hole is worth two assertions and not one, because the old code failed it
## twice over:
##
##   *with a cursor on the field's own channel* -- the old descent answers the
##   field's cursor, the new one answers the global. That is the missing Hole.
##
##   *with no cursor on the field's channel at all* -- the old descent **skipped
##   the channel before testing the point**, so the field could not stop anything;
##   the descent carried on and answered the cursor of the hotspot underneath.
##   That is the inverted order, and it is the case that shows the two defects are
##   not one defect written twice: fixing the geometry alone would still answer
##   the hotspot's cursor here, because the loop would never have called
##   `isMouseIn` on a cursorless channel to find the Hole.
##
## Title-agnostic: no movie, channel or member is named. Every one is found.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Cursor := preload("res://scenes/preview/cursor.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const Ink := preload("res://director/director_ink.gd")
const ContainerName := preload("res://director/director_container.gd")
const Paths := preload("res://director/director_paths.gd")

## `the boxType of member`'s scrolling value, `kTextTypeScrolling` (`types.h:124`).
## Spelled here rather than reached across, exactly as `tools/hit_hole.gd` spells
## it: this file needs the one value it writes.
const BOX_SCROLL := 1

## A cursor pair no member number can collide with, for the synthetic half.
##
## The Hole cases need *a* non-empty cursor on a channel and never compose it --
## `at()` returns the stored value and `install` is never called -- so the pair
## only has to be distinguishable from the global cursor and from anything the
## movie assigned. Two numbers far outside any cast make a wrong answer read as
## itself in the failure text rather than as a plausible member.
const PROBE_CURSOR := [909001, 909002]


## The descent as `preview/cursor.gd:at` had it before `Score::renderCursor` was
## transcribed: cursor looked up first, bare rect, no Hole.
##
## Kept verbatim rather than described, because the entire value of this harness
## is that the two can be *run* against each other on one frame. A prose
## description of the old rule cannot be executed, and a check that only runs the
## new one proves the new one is self-consistent.
static func _old_pick(host, point: Vector2, sprites: Array,
		channel_cursors: Dictionary) -> int:
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = host._effective(sprites[i])
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		if not channel_cursors.has(channel):
			continue
		var candidate: Variant = channel_cursors[channel]
		if Cursor.is_empty(candidate):
			continue
		var rect: Rect2 = host._sprite_rect(sprite)
		if not rect.has_point(point):
			continue
		return channel
	return 0


## The cursor that descent answered, out of the channel it picked.
##
## Split in two only so a report can name *which* channel supplied the answer.
## "Old and new disagree here" is a fact about the whole stack, and without the
## channel there is no way to say which sprite stopped the retired search or why
## Director does not stop there -- which is the difference between evidence and
## an assertion that two functions return different things.
static func _old_at(host, point: Vector2, sprites: Array,
		channel_cursors: Dictionary, global_cursor: Variant) -> Variant:
	if host._clock != null and host._clock.waiting_click():
		return Cursor.WAIT_CLICK_DOWN if host._clock.waiting_click_cursor() \
			else Cursor.WAIT_CLICK_UP
	var picked := _old_pick(host, point, sprites, channel_cursors)
	return channel_cursors[picked] if picked > 0 else global_cursor


func _new_at(preview: Node, point: Vector2, sprites: Array,
		cursors: Dictionary, global_cursor: Variant) -> Variant:
	return Cursor.at(preview, point, sprites, cursors, global_cursor)


func _settle(preview: Node, steps: int) -> void:
	for i in steps:
		preview.call("_advance")


## Every movie container under a root, root-relative, in a stable order.
func _movies(dir_path: String, prefix: String = "") -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for entry in files:
		if ContainerName.MOVIE.has(entry.get_extension().to_lower()):
			out.append(prefix + entry)
	var subs := dir.get_directories()
	subs.sort()
	for sub in subs:
		out.append_array(_movies(dir_path.path_join(sub), prefix + sub + "/"))
	return out


## Every cursor-bearing sprite with a point where the two descents disagree.
##
## **Only a per-pixel ink can produce one on this corpus**, and the scan is
## arranged around that rather than brute-forcing the stage. The three
## differences are matte geometry, the Hole and the order; the corpus has 0
## members of box type `scroll` (`tools/hole_survey.gd`), so no Hole can arise
## here and the other two need `Ink.hits_per_pixel` to be true for the channel
## carrying the cursor. A channel that hit-tests as a whole rectangle answers
## identically under both rules by construction, so scanning it is 300,000
## descents to re-derive that.
##
## The transparent-pixel count is the size of the region whose answer changed and
## is measured with `_opaque_at` alone -- one cheap pass -- while the two descents
## are run only at candidate points, until one of them disagrees. A survey that
## ran both descents at every pixel of every rect does not finish.
func _differences(preview: Node, cursors: Dictionary) -> Array:
	var out: Array = []
	if cursors.is_empty():
		return out
	var sprites: Array = preview.call("frame_sprites")
	var table = preview.get("_table")
	var global_cursor: Variant = preview.get("_global_cursor")
	for raw_value in sprites:
		var raw: Dictionary = raw_value
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty():
			continue
		var channel := int(live["channel"])
		if not cursors.has(channel) or Cursor.is_empty(cursors[channel]):
			continue
		var rect: Rect2 = preview.call("_sprite_rect", live)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var member: Dictionary = table.get_member(
			int(live["cast_lib"]), int(live["cast_id"]))
		if not Ink.hits_per_pixel(int(live["ink"]), int(member.get("type", 0))):
			continue
		var found := {}
		var holes := 0
		for y in range(int(rect.position.y), int(rect.end.y)):
			for x in range(int(rect.position.x), int(rect.end.x)):
				var at := Vector2(x, y)
				if bool(preview.call("_opaque_at", live, at)):
					continue
				holes += 1
				if not found.is_empty():
					continue
				# **Only where the old descent stopped on THIS channel.** A
				# transparent pixel of a matte sprite is a candidate, but if some
				# higher channel with a cursor covers the same point the old
				# descent never reached this one, and attributing the difference
				# here would name the wrong sprite as its cause. The channel that
				# did stop the search is scanned on its own turn.
				if _old_pick(preview, at, sprites, cursors) != channel:
					continue
				var was: Variant = _old_at(
					preview, at, sprites, cursors, global_cursor)
				var now: Variant = _new_at(
					preview, at, sprites, cursors, global_cursor)
				if str(was) == str(now):
					continue
				found = {
					"channel": channel, "at": at,
					"cast_lib": int(live["cast_lib"]),
					"cast_id": int(live["cast_id"]),
					"name": str(member.get("name", "")),
					"ink": int(live["ink"]),
					"rect": rect,
					"was": was, "now": now,
				}
		if not found.is_empty():
			found["points"] = holes
			found["area"] = int(rect.size.x) * int(rect.size.y)
			out.append(found)
	return out


func _survey_root(root_path: String, preview: Node, limit: int, steps: int) -> Dictionary:
	var opened := 0
	var with_cursors := 0
	var sites: Array = []
	for candidate in _movies(root_path):
		if opened >= limit:
			break
		# `lingo_go_movie` and not `_load_container`: a container opened without
		# the movie's own `prepareMovie` / `startMovie` running has no scripts to
		# assign a cursor with, and a survey run that way measures 0 everywhere
		# and reads as "the corpus has none".
		preview.call("lingo_go_movie", str(candidate), null)
		if str(preview.call("movie_name")).to_lower() 				!= str(candidate).get_file().to_lower():
			continue
		opened += 1
		await process_frame
		_settle(preview, steps)
		var cursors: Dictionary = preview.get("_channel_cursors")
		if cursors.is_empty():
			continue
		with_cursors += 1
		for site in _differences(preview, cursors):
			var row: Dictionary = site
			row["movie"] = str(candidate)
			sites.append(row)
			print("  %-28s ch%-3d %d:%-5d %-16s ink %-2d  %d/%d px with no paint"
				% [str(candidate), int(row["channel"]), int(row["cast_lib"]),
					int(row["cast_id"]), str(row["name"]), int(row["ink"]),
					int(row["points"]), int(row["area"])])
			print("      first at (%d,%d): was %s, now %s"
				% [row["at"].x, row["at"].y, str(row["was"]), str(row["now"])])
	return {"opened": opened, "with_cursors": with_cursors, "sites": sites}


## The first frame and channel where a text sprite is big enough for a scrollbar
## strip and is the topmost sprite at a point inside that strip.
##
## The same site `tools/hit_hole.gd` looks for, and for the same reason: a strip
## some higher channel covers is not the strip whose answer would change.
func _find_text_site(preview: Node, frames: int, verbose := false) -> Dictionary:
	var score = preview.get("_score")
	var table = preview.get("_table")
	if score == null or table == null:
		return {}
	for frame in mini(frames, int(score.frame_count)):
		preview.set("_index", frame)
		var sprites: Array = preview.call("frame_sprites")
		for raw_value in sprites:
			var raw: Dictionary = raw_value
			var live: Dictionary = preview.call("_effective", raw)
			if live.is_empty():
				continue
			var member: Dictionary = table.get_member(
				int(live["cast_lib"]), int(live["cast_id"]))
			if member.is_empty():
				continue
			if not Interaction.TEXT_MEMBER_TYPES.has(int(member.get("type", 0))):
				continue
			var rect: Rect2 = preview.call("_sprite_rect", live)
			if not Interaction.scrollbar_strip_exists(rect.size):
				continue
			var at := Vector2(
				rect.end.x - float(Interaction.SCROLLBAR_BORDER) / 2.0,
				(rect.position.y + rect.end.y) / 2.0)
			if not Interaction.in_scrollbar(rect, at):
				continue
			# The field has to be the topmost sprite at the probe point, or the
			# assertions would be about whatever covers it.
			if _covered_above(preview, at, int(live["channel"])):
				if verbose:
					print("   f%-4d ch%-3d rejected: covered above at (%d,%d)"
						% [frame, int(live["channel"]), at.x, at.y])
				continue
			# And something must lie *under* it, so "the descent aborted" and
			# "the descent carried on" are visibly different answers.
			var beneath := _beneath(preview, at, int(live["channel"]))
			if beneath <= 0:
				if verbose:
					print("   f%-4d ch%-3d rejected: nothing underneath at (%d,%d)"
						% [frame, int(live["channel"]), at.x, at.y])
				continue
			return {
				"frame": frame, "channel": int(live["channel"]),
				"cast_lib": int(live["cast_lib"]), "cast_id": int(live["cast_id"]),
				"at": at, "rect": rect, "beneath": beneath,
				"box": int(member.get("text_type", 0)),
			}
	return {}


func _covered_above(preview: Node, at: Vector2, below: int) -> bool:
	for raw_value in preview.call("frame_sprites"):
		var raw: Dictionary = raw_value
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty() or int(live["channel"]) <= below:
			continue
		if preview.call("_sprite_rect", live).has_point(at):
			return true
	return false


func _beneath(preview: Node, at: Vector2, above: int) -> int:
	var best := 0
	for raw_value in preview.call("frame_sprites"):
		var raw: Dictionary = raw_value
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty():
			continue
		var channel := int(live["channel"])
		if channel >= above or channel <= best:
			continue
		if preview.call("_sprite_rect", live).has_point(at):
			best = channel
	return best


func _init() -> void:
	var args := Args.parse()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	if Args.flag(args, "survey"):
		await _survey(args, preview)
		quit(0)
		return

	var h := Harness.new()
	# The Hole first, and the order is load-bearing rather than tidy: it asserts
	# about the movie `--file` names, and the matte half **navigates** -- it hunts
	# the corpus for a movie that assigns a cursor pair, so by the time it is done
	# the player is somewhere else entirely.
	await _assert_hole(args, preview, h)
	await _assert_matte(args, preview, h)
	quit(h.finish("the cursor descent is `Score::renderCursor`"))


## ------------------------------------------------------------------- the survey
func _survey(args: Dictionary, preview: Node) -> void:
	var paths := Paths.new()
	paths.load_config()
	var roots: Array = []
	if Args.flag(args, "all"):
		for base in ["res://games", "res://test-games"]:
			var dir := DirAccess.open(base)
			if dir == null:
				continue
			var subs := dir.get_directories()
			subs.sort()
			for sub in subs:
				roots.append(base.path_join(sub))
	else:
		roots.append(str(paths.root))
	var total := 0
	var opened := 0
	var carrying := 0
	for root_path in roots:
		print("")
		print("== %s" % str(root_path))
		var run: Dictionary = await _survey_root(str(root_path), preview,
			Args.number(args, "limit", 24), Args.number(args, "steps", 250))
		opened += int(run["opened"])
		carrying += int(run["with_cursors"])
		total += (run["sites"] as Array).size()
		print("   %d container(s) opened, %d with a channel cursor, %d site(s)"
			% [int(run["opened"]), int(run["with_cursors"]),
				(run["sites"] as Array).size()])
	print("")
	print("%d root(s), %d container(s) opened, %d carrying a channel cursor,"
		% [roots.size(), opened, carrying]
		+ " %d sprite(s) where the two descents disagree" % total)


## ------------------------------------------------------ the matte, on real art
##
## The corpus-visible difference. A sprite whose ink hit-tests per pixel and which
## carries a cursor answers, under the old rule, everywhere inside its rectangle;
## under Director's it answers only where it has paint.
func _assert_matte(args: Dictionary, preview: Node, h: Harness) -> void:
	var steps := Args.number(args, "steps", 250)
	_settle(preview, steps)
	var cursors: Dictionary = preview.get("_channel_cursors")
	var sites: Array = _differences(preview, cursors)
	# The boot movie of a title is a splash screen and assigns no cursor, so the
	# movie is found rather than named -- the same search `tools/cursor_preview.gd`
	# makes, and for the same reason.
	if sites.is_empty():
		var paths = preview.get("_paths")
		var opened := 0
		for candidate in _movies(str(paths.root)):
			if opened >= Args.number(args, "limit", 24):
				break
			preview.call("lingo_go_movie", str(candidate), null)
			if str(preview.call("movie_name")).to_lower() 					!= str(candidate).get_file().to_lower():
				continue
			opened += 1
			await process_frame
			_settle(preview, steps)
			cursors = preview.get("_channel_cursors")
			sites = _differences(preview, cursors)
			if not sites.is_empty():
				break
		print("searched %d container(s) for a sprite the two descents disagree on"
			% opened)

	h.begin("the two descents answer different cursors on a real sprite")
	if sites.is_empty():
		# The honest `video_fallback` shape. A corpus with no such point is a
		# measurement, and it belongs in the output rather than behind a check
		# that cannot fail -- but it is a FAIL for the entry `gate.sh` names,
		# because that entry names a root this was measured to have one in.
		h.check("this root has a sprite whose cursor answer changed", false,
			"no channel with a cursor has a point where the old rect-only"
			+ " descent and `Score::renderCursor` disagree; run --survey --all")
		h.complete("the two descents answer different cursors on a real sprite")
		return
	var site: Dictionary = sites[0]
	var at: Vector2 = site["at"]
	var rect: Rect2 = site["rect"]
	print("movie   : %s" % str(preview.call("movie_name")))
	print("site    : ch%d %d:%d %s, ink %d, rect (%d,%d) %dx%d" % [
		int(site["channel"]), int(site["cast_lib"]), int(site["cast_id"]),
		str(site["name"]), int(site["ink"]),
		int(rect.position.x), int(rect.position.y),
		int(rect.size.x), int(rect.size.y)])
	print("probe   : (%d,%d)  old -> %s   new -> %s  (%d of %d px in the rect)" % [
		at.x, at.y, str(site["was"]), str(site["now"]),
		int(site["points"]), int(site["area"])])

	var sprites: Array = preview.call("frame_sprites")
	var table = preview.get("_table")
	var live: Dictionary = {}
	for raw_value in sprites:
		var raw: Dictionary = raw_value
		if int(raw["channel"]) != int(site["channel"]):
			continue
		live = preview.call("_effective", raw)
		break
	var member: Dictionary = table.get_member(
		int(site["cast_lib"]), int(site["cast_id"]))

	h.check("the point is inside the sprite's rectangle, so the old descent"
		+ " stopped there", rect.has_point(at),
		"(%d,%d) in (%d,%d) %dx%d" % [at.x, at.y,
			int(rect.position.x), int(rect.position.y),
			int(rect.size.x), int(rect.size.y)])
	h.check("the sprite's ink hit-tests per pixel",
		Ink.hits_per_pixel(int(site["ink"]), int(member.get("type", 0))),
		"ink %d over member type %d" % [
			int(site["ink"]), int(member.get("type", 0))])
	h.check("the artwork is transparent there, which is why Director walks past",
		not bool(preview.call("_opaque_at", live, at)),
		"`_opaque_at` says the sprite has paint at (%d,%d)" % [at.x, at.y])
	h.check("the old descent answered this channel's own cursor",
		str(site["was"]) == str(cursors[int(site["channel"])]),
		"old answered %s, the channel carries %s" % [
			str(site["was"]), str(cursors[int(site["channel"])])])
	h.check("the reference's descent answers something else there",
		str(site["was"]) != str(site["now"]),
		"%s -> %s" % [str(site["was"]), str(site["now"])])
	# The other half of the same sprite. A rule that answered the global cursor
	# everywhere would pass every check above and be a different bug, so the
	# opaque part of the same artwork has to still answer the channel's pair.
	var solid := _opaque_point(preview, live, rect)
	if solid != Vector2(-1, -1):
		var global_cursor: Variant = preview.get("_global_cursor")
		h.check("where the same sprite has paint, its cursor still answers",
			str(Cursor.at(preview, solid, sprites, cursors, global_cursor))
				== str(cursors[int(site["channel"])]),
			"(%d,%d) -> %s" % [solid.x, solid.y,
				str(Cursor.at(preview, solid, sprites, cursors, global_cursor))])
	else:
		h.check("this sprite has no opaque pixel, so 'only where it has paint'"
			+ " cannot be checked from the other side", true,
			"the whole rect is transparent")
	h.complete("the two descents answer different cursors on a real sprite")


## A point where the sprite has paint **and nothing above it is in the way**.
##
## The second half is not tidiness. The check this feeds asserts that the
## channel's own cursor still answers where the artwork is solid, and a higher
## sprite covering that pixel would answer instead -- correctly -- turning a check
## about the matte into a check about whatever happens to be stacked on top.
func _opaque_point(preview: Node, live: Dictionary, rect: Rect2) -> Vector2:
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			var at := Vector2(x, y)
			if not bool(preview.call("_opaque_at", live, at)):
				continue
			if _covered_above(preview, at, int(live["channel"])):
				continue
			return at
	return Vector2(-1, -1)


## ------------------------------------------------------------------- the Hole
##
## Two assertions on one synthesised scrolling field: the Hole itself, and the
## order that made a cursorless field unable to produce one.
func _assert_hole(args: Dictionary, preview: Node, h: Harness) -> void:
	var paths := Paths.new()
	paths.load_config()
	var only := Args.text(args, "file", "")
	if only != "":
		var resolved: String = paths.resolve(only)
		if resolved != "":
			preview.call("_load_container", resolved)
			await process_frame

	var site := _find_text_site(preview, Args.number(args, "frames", 400),
		Args.flag(args, "verbose"))
	h.begin("a Hole ends the cursor descent")
	if site.is_empty():
		h.check("the movie has a text sprite with a scrollbar-sized rect over"
			+ " another sprite", false,
			"no site in %s; try --file" % str(preview.call("movie_name")))
		h.complete("a Hole ends the cursor descent")
		return
	var channel := int(site["channel"])
	var beneath := int(site["beneath"])
	var at: Vector2 = site["at"]
	print("")
	print("hole    : %s frame %d, field on ch%d over ch%d, probe (%d,%d)" % [
		str(preview.call("movie_name")), int(site["frame"]),
		channel, beneath, at.x, at.y])

	var table = preview.get("_table")
	var cast = table.cast_for(int(site["cast_lib"]))
	var member: Dictionary = cast.member(int(site["cast_id"]))
	var authored := int(site["box"])
	var global_cursor: Variant = preview.get("_global_cursor")

	# The channel underneath is the hotspot: it is what a player would be aiming
	# at, and its cursor is the one that must not show through the strip.
	var under_cursor := [PROBE_CURSOR[0] + 10, PROBE_CURSOR[1] + 10]
	var cursors: Dictionary = {beneath: under_cursor}

	# --- case 1: the field carries a cursor of its own. The missing Hole.
	cursors[channel] = PROBE_CURSOR
	var sprites: Array = preview.call("frame_sprites")
	var before_new: Variant = Cursor.at(preview, at, sprites, cursors, global_cursor)
	h.check("with the field authored as it ships, its own cursor answers",
		str(before_new) == str(PROBE_CURSOR),
		"answered %s" % str(before_new))
	member["text_type"] = BOX_SCROLL
	sprites = preview.call("frame_sprites")
	var strip_rect: Rect2 = _rect_of(preview, channel)
	h.check("the probe point is inside the sprite under both box types",
		strip_rect.has_point(at) and (site["rect"] as Rect2).has_point(at),
		"scrolling rect (%d,%d) %dx%d" % [
			int(strip_rect.position.x), int(strip_rect.position.y),
			int(strip_rect.size.x), int(strip_rect.size.y)])
	var old_holed: Variant = _old_at(preview, at, sprites, cursors, global_cursor)
	var new_holed: Variant = Cursor.at(preview, at, sprites, cursors, global_cursor)
	h.check("the retired descent still answers the field's own cursor there",
		str(old_holed) == str(PROBE_CURSOR),
		"old answered %s" % str(old_holed))
	h.check("the reference's descent answers the global cursor instead",
		str(new_holed) == str(global_cursor),
		"answered %s, global is %s" % [str(new_holed), str(global_cursor)])
	h.complete("a Hole ends the cursor descent")

	# --- case 2: the field carries NO cursor. The inverted order.
	h.begin("a Hole ends the descent even on a channel with no cursor")
	cursors.erase(channel)
	var old_bare: Variant = _old_at(preview, at, sprites, cursors, global_cursor)
	var new_bare: Variant = Cursor.at(preview, at, sprites, cursors, global_cursor)
	h.check("the retired descent skipped the cursorless field and answered the"
		+ " sprite underneath", str(old_bare) == str(under_cursor),
		"old answered %s, ch%d carries %s" % [
			str(old_bare), beneath, str(under_cursor)])
	h.check("the reference's descent tests the point first, finds the Hole, and"
		+ " answers the global cursor", str(new_bare) == str(global_cursor),
		"answered %s, global is %s" % [str(new_bare), str(global_cursor)])
	h.check("the two disagree, so testing the point before the cursor is not"
		+ " cosmetic", str(old_bare) != str(new_bare),
		"%s -> %s" % [str(old_bare), str(new_bare)])
	h.complete("a Hole ends the descent even on a channel with no cursor")

	member["text_type"] = authored
	h.begin("the member is put back")
	h.check("the authored box type is restored",
		int(cast.member(int(site["cast_id"])).get("text_type", -1)) == authored,
		"boxType %d" % int(cast.member(int(site["cast_id"])).get("text_type", -1)))
	h.complete("the member is put back")


func _rect_of(preview: Node, channel: int) -> Rect2:
	for raw_value in preview.call("frame_sprites"):
		var raw: Dictionary = raw_value
		if int(raw["channel"]) != channel:
			continue
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty():
			return Rect2()
		return preview.call("_sprite_rect", live)
	return Rect2()
