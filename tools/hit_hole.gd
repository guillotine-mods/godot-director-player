extends SceneTree
## §4.2's third answer: a Hole aborts the descent, and Outside does not.
##
##   godot --headless --audio-driver Dummy --path . --script tools/hit_hole.gd -- \
##     --file PIP2DATA/SAVELOAD.dir
##   godot --headless --audio-driver Dummy --path . --script tools/hit_hole.gd -- \
##     --root piposh --scan
##
##   --file PATH   the movie to assert against (default: the root's boot movie)
##   --scan        walk every container of the root and print the sites it finds
##   --frames N    how many frames of the movie to scan for a site (default 400)
##
## ## What this asserts, and why "it returns three values" would not be worth
## running
##
## `Interaction.is_mouse_in` answering a third enum value proves nothing: the
## question is whether a **click reaches a different sprite**. So this drives the
## real player on a real movie, finds a real text sprite whose rect is big enough
## to carry a scrollbar, picks a point inside that scrollbar, and asserts the two
## readings *disagree there*:
##
##   the member as its author wrote it   -> the descent answers the field's own
##                                          channel N
##   the same member as a scrolling box  -> the descent answers 0, and neither N
##                                          nor the sprite BENEATH N is reachable
##                                          at that point
##
## The last clause is the one that separates a Hole from an ordinary miss, and it
## needs a real frame to have any content: a miss continues the descent, so if a
## sprite covers the same point underneath, reading the Hole as a miss answers
## *that* channel. Measured on `PIP2DATA/SAVELOAD.dir` frame 44: the field is
## channel 6 and channel 4 covers the same point, so the three readings give
## three different answers -- 6 with no Hole at all, 4 with a Hole read as a
## miss, and 0 with the reference's `break`.
##
## Every channel number here is read from the engine rather than written down,
## because a hard-coded channel is a title-specific fact and this file may not
## carry one.
##
## Three more points guard the *shape* of the strip rather than its existence,
## and each is false for a rule written slightly wrong:
##
##   one pixel left of the strip   not a Hole -- the strip is `bRight` wide and
##                                 not "the right half"
##   the top `bTop` rows of it     not a Hole -- `isInScrollBar` answers
##                                 `kBorderBorder` there, which `isWithin` does
##                                 not turn into one
##   the bottom `bBottom` rows     the same, at the other end
##
## Without those a rule that holed the whole right edge, or the whole rect, would
## pass the first two checks.
##
## ## The one thing that is synthesised, and what it is
##
## **The movie, the sprite, the geometry, the cast and the descent are all real.**
## What this writes is one byte of one member: `text_type`, `the boxType of
## member`, the author's choice between Adjust to Fit / Scrolling / Fixed / Limit
## in Director's own Field dialog. It has to be written because **0 members of
## box type `scroll` exist in any of the eight roots** -- measured by
## `tools/hole_survey.gd`, which also counts 6,312 `adjust`, 93 `fixed` and 82
## `limit`. A Hole is unreachable on this corpus for the same reason Mask ink and
## ten of the twelve matte inks are: nothing here authored one. Saying so and
## driving the mechanism from a real sprite is the honest state; asserting over
## the 0 and calling it covered is not.
##
## Nothing under `games/` is touched. The write lands on the in-memory member
## dictionary `DirectorCast` caches for this session and is put back before the
## run ends.
##
## Title-agnostic: it names no movie, no channel and no member, and the site it
## asserts about is whichever one the scan finds first.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const Paths := preload("res://director/director_paths.gd")

## `the boxType of member`, the four Director offers. `sprite_geometry.gd` holds
## the same four and this file needs only the one it writes, so it is named here
## rather than reaching across for a constant whose module is about sizing.
const BOX_SCROLL := 1

const TEXT_TYPES := [3, 7]


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var paths := Paths.new()
	paths.load_config()
	var only := Args.text(args, "file", "")
	if only != "":
		var resolved: String = paths.resolve(only)
		if resolved == "" or not preview.call("_load_container", resolved):
			print("no such container: %s" % only)
			h.begin("the movie opened")
			h.check("--file names a container of this root", false, only)
			quit(h.finish("the hit test's third answer"))
			return
		await process_frame

	if Args.flag(args, "scan"):
		await _scan(preview, paths, Args.number(args, "frames", 400))
		quit(0)
		return

	var site := await _find_site(preview, Args.number(args, "frames", 400))
	print("movie   : %s" % str(preview.call("movie_name")))
	if site.is_empty():
		# A movie with no big-enough text sprite asserts nothing about the Hole
		# and **says so** rather than closing a case it never ran. That is the
		# `video_fallback` shape `AGENTS.md` names: a harness that found nothing
		# reports finding nothing, and the gate entry that points at such a movie
		# is the bug rather than the run.
		print("no text sprite in the first %d frame(s) is large enough for a"
			% Args.number(args, "frames", 400)
			+ " scrollbar strip, so there is no site to assert about")
		h.begin("a site to assert about")
		h.check("the movie has a text sprite with a scrollbar-sized rect", false,
			"try --scan over the root to find one")
		h.complete("a site to assert about")
		quit(h.finish("the hit test's third answer"))
		return

	var frame := int(site["frame"])
	var channel := int(site["channel"])
	var lib := int(site["cast_lib"])
	var id := int(site["cast_id"])
	var at: Vector2 = site["at"]
	var rect: Rect2 = site["rect"]
	var authored := int(site["box"])
	print("site    : frame %d, channel %d, member %d:%d, rect (%d,%d) %dx%d, boxType %d"
		% [frame, channel, lib, id, int(rect.position.x), int(rect.position.y),
			int(rect.size.x), int(rect.size.y), authored])
	print("probe   : (%d,%d), inside the scrollbar strip of that rect" % [at.x, at.y])

	# `getSpriteIDFromPos`, the descent with **no** eligibility filter, is what the
	# assertions below are asked of, and the choice is forced rather than
	# convenient. `getMouseSpriteIDFromPos` -- the click descent -- answers 0
	# under every big text sprite in every one of these titles, because a field is
	# a caption and neither it nor the backdrop it sits on carries a mouse
	# handler: measured by `--scan`, which finds sites in `piposh` and `piposh2`
	# and reports `descent -> 0` for every one of them. Two zeros cannot disagree,
	# so a check written on that query would pass with the Hole implemented, with
	# it reverted, and with it implemented backwards. The unfiltered query has no
	# such floor: every sprite the pointer is over answers it, so "the search
	# aborted" and "the search carried on" are visibly different answers.
	#
	# It is still the same three-way loop -- `Interaction.is_mouse_in` -- and the
	# click descent shares it, so what is proved here is proved for both. The
	# filtered query is checked below as well, where the frame gives it anything
	# to say.
	var sprites: Array = preview.call("frame_sprites")
	var table = preview.get("_table")
	var pixels: bool = preview.get("_hit_pixels")
	var answered := Interaction.sprite_at(preview, at, sprites, pixels, table)
	h.begin("the authored member is not a Hole")
	# The guard on 10,495 records. `TextCastMember::isWithin` calls
	# `isInScrollBar` without asking whether the widget has a scrollbar, and taken
	# literally that puts a click-swallowing strip down the right edge of every
	# field in this corpus bigger than 17x34 -- none of which is a scrolling box
	# and none of which draws a scrollbar. This check is what fails if that
	# literal reading is ever restored, and it is asserted on the movie's own
	# unmodified member.
	h.check("a point in the strip of a non-scrolling field still answers a sprite",
		answered == channel,
		"channel %d, wanted the field's own %d" % [answered, channel])
	h.complete("the authored member is not a Hole")

	# What a Hole read as an ordinary miss would answer instead: the highest
	# sprite *below* the field whose rect covers the same point. This is the whole
	# difference the entry is about -- with it, `holed == 0` is not merely "the
	# field stopped answering", it is "the sprite the descent would have carried
	# on to is unreachable".
	var beneath := _beneath(preview, at, channel)

	var cast = table.cast_for(lib)
	var member: Dictionary = cast.member(id)
	member["text_type"] = BOX_SCROLL
	# The member's box type feeds `drawn_size`, so the sprite may be a different
	# size now (`sprite_geometry.gd:_field_size`: scroll takes the MAX arm and
	# adjust the laid-out one). The probe point is only meaningful if it is inside
	# *both* rects, which is what makes "the answer changed" a statement about the
	# rule rather than about the geometry moving out from under it.
	sprites = preview.call("frame_sprites")
	var scroll_rect: Rect2 = _rect_of(preview, channel)
	h.begin("the probe point is in both readings of the sprite")
	h.check("the point the answer changed at is inside the sprite either way",
		scroll_rect.has_point(at) and rect.has_point(at),
		"authored (%d,%d) %dx%d, scrolling (%d,%d) %dx%d" % [
			int(rect.position.x), int(rect.position.y),
			int(rect.size.x), int(rect.size.y),
			int(scroll_rect.position.x), int(scroll_rect.position.y),
			int(scroll_rect.size.x), int(scroll_rect.size.y)])
	h.complete("the probe point is in both readings of the sprite")

	var holed := Interaction.sprite_at(preview, at, sprites, pixels, table)
	h.begin("a Hole aborts the descent")
	h.check("the same point now answers nothing at all", holed == 0,
		"channel %d, was %d" % [holed, answered])
	h.check("the sprite the point used to reach is unreachable there",
		holed != answered, "%d -> %d" % [answered, holed])
	# The half that separates Hole from Outside. An Outside continues the descent,
	# so if there is a sprite under the field at this point, reading the Hole as a
	# miss answers *that* channel rather than 0.
	if beneath > 0:
		h.check("the sprite BENEATH the field is not reached either, so this is"
			+ " an abort and not a miss", holed == 0,
			"channel %d covers the same point and answers nothing" % beneath)
	else:
		h.check("no sprite lies under the field at this point, so abort and miss"
			+ " cannot be told apart here", true,
			"the check above is the whole of what this frame can say")
	h.complete("a Hole aborts the descent")

	# Three shape checks. Each is the same point one step outside the strip, and
	# each is false for a plausible mis-transcription of `isInScrollBar`: a rule
	# that holed the right half, the whole rect, or the strip including the two
	# corners it excludes.
	var left := Vector2(scroll_rect.end.x - Interaction.SCROLLBAR_BORDER - 1, at.y)
	var top := Vector2(at.x, scroll_rect.position.y + Interaction.SCROLLBAR_BORDER - 1)
	var bottom := Vector2(at.x, scroll_rect.end.y - 1)
	var at_left := Interaction.sprite_at(preview, left, sprites, pixels, table)
	var at_top := Interaction.sprite_at(preview, top, sprites, pixels, table)
	var at_bottom := Interaction.sprite_at(preview, bottom, sprites, pixels, table)
	h.begin("the strip is the reference's rectangle and not the right edge")
	h.check("one pixel left of the strip is not a Hole", at_left == channel,
		"(%d,%d) -> %d" % [left.x, left.y, at_left])
	h.check("the top corner of the strip is kBorderBorder, not a Hole",
		at_top == channel, "(%d,%d) -> %d" % [top.x, top.y, at_top])
	h.check("the bottom corner of the strip is kBorderBorder, not a Hole",
		at_bottom == channel, "(%d,%d) -> %d" % [bottom.x, bottom.y, at_bottom])
	h.complete("the strip is the reference's rectangle and not the right edge")

	# The click descent, on the same points. It is the query that decides which
	# sprite a mouseDown reaches, so a run that only exercised the unfiltered one
	# would leave the thing players notice unasserted -- but on a frame where
	# nothing under the pointer is eligible it can only say 0, and saying that out
	# loud is better than a check that cannot fail.
	var clicked := int(preview.call("_channel_at", at))
	var clicked_left := int(preview.call("_channel_at", left))
	h.begin("the click descent takes the same three answers")
	if clicked_left > 0:
		h.check("a click one pixel left of the strip reaches a sprite and a click"
			+ " inside it reaches none", clicked == 0,
			"left -> %d, strip -> %d" % [clicked_left, clicked])
	else:
		h.check("nothing under this point is eligible, so the click descent"
			+ " answers 0 either side of the strip",
			clicked == 0 and clicked_left == 0,
			"left -> %d, strip -> %d" % [clicked_left, clicked])
	h.complete("the click descent takes the same three answers")

	member["text_type"] = authored
	h.begin("the member is put back")
	h.check("the authored box type is restored",
		int(cast.member(id).get("text_type", -1)) == authored,
		"boxType %d" % int(cast.member(id).get("text_type", -1)))
	h.complete("the member is put back")

	quit(h.finish("the hit test's third answer, on a real sprite"))



## Is any channel above `below` covering this point?
##
## The site-picking half of "the field is what answers here", asked of the rects
## alone. See `_find_site` for why it may not be asked of the descent.
func _covered_above(preview: Node, at: Vector2, below: int) -> bool:
	for raw_value in preview.call("frame_sprites"):
		var raw: Dictionary = raw_value
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty() or int(live["channel"]) <= below:
			continue
		var rect: Rect2 = preview.call("_sprite_rect", live)
		if rect.has_point(at):
			return true
	return false


## The highest channel below `above` whose rect covers the point.
##
## What the descent would answer if a Hole were read as an ordinary miss. Asked
## of the geometry alone rather than through `is_mouse_in`, because the point of
## it is to name the sprite the *broken* reading would reach, and running it
## through the code under test would let that code decide there is nothing there.
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
		var rect: Rect2 = preview.call("_sprite_rect", live)
		if rect.has_point(at):
			best = channel
	return best


## The sprite's stage rect as the engine currently reads it.
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


## The first frame and channel where a text sprite carries a scrollbar strip and
## **is itself what the unfiltered descent answers** at a point inside that strip.
##
## Both halves matter. A text sprite too small for a strip has no scrollbar
## geometry to test at all; one that some higher channel covers at the probe point
## is not the sprite whose answer would change, so asserting about it would be
## asserting about the sprite on top of it.
##
## `require_own` is relaxed by `--scan`, which reports what it finds rather than
## picking something to assert on -- a survey that silently skipped the sites it
## could not use would make the corpus look emptier than it is.
func _find_site(preview: Node, frames: int, require_own := true) -> Dictionary:
	var score = preview.get("_score")
	var table = preview.get("_table")
	if score == null or table == null:
		return {}
	var pixels: bool = preview.get("_hit_pixels")
	for frame in mini(frames, int(score.frame_count)):
		preview.set("_index", frame)
		var sprites: Array = preview.call("frame_sprites")
		for raw_value in sprites:
			var raw: Dictionary = raw_value
			var live: Dictionary = preview.call("_effective", raw)
			if live.is_empty():
				continue
			var m: Dictionary = table.get_member(
				int(live["cast_lib"]), int(live["cast_id"]))
			if m.is_empty() or not TEXT_TYPES.has(int(m.get("type", 0))):
				continue
			var rect: Rect2 = preview.call("_sprite_rect", live)
			if not Interaction.scrollbar_strip_exists(rect.size):
				continue
			var at := _strip_point(rect)
			# **Chosen by geometry, not by asking the code under test.** An
			# earlier version required `sprite_at` to answer this channel, which
			# made a broken Hole rule *disqualify its own subject*: with the
			# scrollbar guard removed the field Holes at the probe point, the
			# site was rejected, and the run failed with "no site to assert
			# about" instead of with the check that was actually wrong. A harness
			# whose subject is picked by the thing it is testing cannot report
			# what went wrong.
			if require_own and _covered_above(preview, at, int(live["channel"])):
				continue
			var answered := Interaction.sprite_at(preview, at, sprites, pixels, table)
			return {
				"frame": frame, "channel": int(live["channel"]),
				"cast_lib": int(live["cast_lib"]), "cast_id": int(live["cast_id"]),
				"at": at, "rect": rect, "box": int(m.get("text_type", 0)),
				"answered": answered,
				"clicked": int(preview.call("_channel_at", at)),
			}
	return {}


## The middle of the strip's upper arm: inside `bRight`, below `bTop`, above the
## half-height split. Chosen there rather than at an edge so that an off-by-one
## in either direction still lands inside, and so the three shape checks above
## have somewhere to be wrong.
static func _strip_point(rect: Rect2) -> Vector2:
	return Vector2(
		rect.end.x - float(Interaction.SCROLLBAR_BORDER) / 2.0,
		rect.position.y + float(Interaction.SCROLLBAR_BORDER)
			+ (rect.size.y - float(Interaction.SCROLLBAR_BORDER * 2)) / 4.0).floor()


## Every container of the root, and the sites in each. Prints; asserts nothing.
func _scan(preview: Node, paths, frames: int) -> void:
	var targets: Array[String] = []
	_walk(paths.root, targets)
	targets.sort()
	print("%-28s %s" % ["container", "first site (frame, channel, member, rect, boxType)"])
	for path in targets:
		if not preview.call("_load_container", path):
			continue
		await process_frame
		var site := await _find_site(preview, frames, false)
		if site.is_empty():
			continue
		var rect: Rect2 = site["rect"]
		print("SITE %-24s frame %-5d ch %-3d %d:%-4d (%d,%d) %dx%d  box %d  unfiltered -> %d  click -> %d" % [
			path.get_file(), int(site["frame"]), int(site["channel"]),
			int(site["cast_lib"]), int(site["cast_id"]),
			int(rect.position.x), int(rect.position.y),
			int(rect.size.x), int(rect.size.y), int(site["box"]),
			int(site["answered"]), int(site["clicked"])])


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)
