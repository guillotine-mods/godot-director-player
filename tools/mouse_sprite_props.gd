extends SceneTree
## `the rollOver`, `the mouseCast` and `the mouseMember` read `getSpriteIDFromPos`.
##
##   godot --headless --audio-driver Dummy --path . --script tools/mouse_sprite_props.gd
##   godot --headless --audio-driver Dummy --path . --script tools/mouse_sprite_props.gd -- \
##     --file PIP2DATA/DAY1.dir
##
##   --file PATH    the movie to assert against (default: the root's boot movie)
##   --frames N     how many frames to scan for a site (default 400)
##
## ## The distinction, and why "it answers an integer" would not be worth running
##
## Director has **three** descents down the sprite stack and this port has all
## three. They differ in one line each and answer differently on the same point:
##
##   `getSpriteIDFromPos`         `Interaction.sprite_at`     no filter, ink-aware
##   `getMouseSpriteIDFromPos`    `Interaction.channel_at`    + can it answer a
##                                                            mouse message (§4.3)
##   `getRollOverSpriteIDFromPos` `Interaction.rollover_channel`  bare rect over
##                                                            the SCORE's geometry
##
## `lingo-the.cpp` reads the **first** for all three of these properties
## (`:848` mouseCast, `:901` mouseMember, `:1035` rollOver). This port read the
## **third** for all three, which is a different question: it ignores matte
## transparency, ignores the scrollbar Hole, and measures a sprite a script has
## moved at the rectangle the score gave it rather than where it is. So the
## assertions below are not "the property answers a number" -- they are "the
## property answers a **different** number from the one it used to, at a point
## where the reference says the two descents part company, and the number it
## answers now is the one `getSpriteIDFromPos` gives".
##
## `rollOver()` the builtin keeps the third descent, and that is asserted here
## too. §4.5: the builtin *is* `getRollOverSpriteIDFromPos`, 94 corpus sites poll
## it from `exitFrame` to swap a button's artwork, and measuring the swapped
## artwork would feed the answer back into the question. The two spellings are two
## functions; a change that made them agree would be a regression wearing the
## shape of a cleanup, so a check that they still disagree is part of the fix.
##
## ## The two answers for "over nothing"
##
## `the mouseCast` is **0** and `the mouseMember` is **VOID**, and the asymmetry
## is the reference's (`lingo-the.cpp:844-908`). This port answered **-1** for
## both. -1 is not a Director value at all: `voidP(the mouseMember)` -- the guard
## the property exists to be read through -- is false for it, so a movie asking
## "is the pointer over anything" is told yes and then hands -1 to `member()`.
##
## ## The number itself
##
## `the mouseCast` is `_castId.toMultiplex()`: the packed (library, slot)
## reference, `members.gd:pack_ref` here and the same arithmetic
## (`types.h:451-455`). This port answered `membernum`, the bare per-library slot,
## which resolves in library 1 for a sprite drawn from any other cast. That is the
## ship-map failure of `docs/bugs-closed.md` by another route, and it is silent:
## a bare slot is a perfectly plausible number.
##
## Title-agnostic: every movie, frame, channel and member here is found.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const Members := preload("res://scenes/preview/members.gd")
const Ink := preload("res://director/director_ink.gd")
const Paths := preload("res://director/director_paths.gd")


## Put the pointer somewhere the engine will believe.
##
## Headless there is no OS cursor, so `_pointer_from_events` is true and
## `note_pointer` is the whole of it. `tools/hilite.gd` carries the argument for
## the windowed half and this follows it: a harness that only ever called
## `note_pointer` would measure wherever the developer left their mouse.
func _point_at(preview: Node, at: Vector2) -> void:
	preview.call("note_pointer", at)
	if bool(preview.get("_pointer_from_events")):
		return
	Input.warp_mouse(at * preview.get("scale").x)
	await process_frame
	await process_frame


## A point where the rect descent and the ink-aware one part company.
##
## Generated from the matte, because that is the difference this corpus can
## express: 0 members of box type `scroll` exist in any of the eight roots
## (`tools/hole_survey.gd`), so no title in reach can author the Hole, and a
## script that has moved a sprite is a difference that depends on the movie having
## run. A transparent pixel of a Matte bitmap is authored art and is everywhere.
##
## The sprite has to be the **topmost** rect at the point, or `rollover_channel`
## would answer something above it and the site would be about that instead.
func _find_site(preview: Node, frames: int) -> Dictionary:
	var score = preview.get("_score")
	var table = preview.get("_table")
	if score == null or table == null:
		return {}
	var pixels: bool = preview.get("_hit_pixels")
	var stage := Rect2(Vector2.ZERO, preview.call("stage_size") as Vector2)
	# **Ranked, not first-found.** Every point where the two descents differ
	# proves the binding moved, but they do not all prove the same amount: a
	# difference that lands on 0 says the search fell off the bottom, where one
	# that lands on another channel says the pointer is over a *different sprite*
	# than the old rule named -- and only the second gives `the mouseCast` and
	# `the mouseMember` a member to be right or wrong about. A sprite from a
	# linked cast is better again, because that is the one case where the packed
	# reference and the bare slot are different numbers.
	var best: Dictionary = {}
	var best_rank := 0
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
			if not Ink.hits_per_pixel(int(live["ink"]), int(member.get("type", 0))):
				continue
			var rect: Rect2 = preview.call("_sprite_rect", live)
			if rect.size.x <= 0 or rect.size.y <= 0:
				continue
			for y in range(int(rect.position.y), int(rect.end.y)):
				for x in range(int(rect.position.x), int(rect.end.x)):
					var at := Vector2(x, y)
					if not stage.has_point(at):
						continue
					if bool(preview.call("_opaque_at", live, at)):
						continue
					var rolled := Interaction.rollover_channel(preview, at, sprites)
					if rolled != int(live["channel"]):
						continue
					var seen := Interaction.sprite_at(
						preview, at, sprites, pixels, table)
					if seen == rolled:
						continue
					var rank := 1
					if seen > 0:
						rank = 3 if _lib_of(preview, seen) > 1 else 2
					if rank <= best_rank:
						continue
					best = {
						"frame": frame, "at": at, "rolled": rolled, "seen": seen,
						"rect": rect, "channel": int(live["channel"]), "rank": rank,
					}
					best_rank = rank
					if rank >= 3:
						preview.set("_index", frame)
						return best
	if not best.is_empty():
		# The frame the site was found on, restored: the scan walked past it and
		# every question asked about the site afterwards reads `frame_sprites()`.
		preview.set("_index", int(best["frame"]))
	return best


## Which cast library a channel is drawing from on the current frame.
func _lib_of(preview: Node, channel: int) -> int:
	for raw_value in preview.call("frame_sprites"):
		var raw: Dictionary = raw_value
		if int(raw["channel"]) != channel:
			continue
		var live: Dictionary = preview.call("_effective", raw)
		return 1 if live.is_empty() else int(live.get("cast_lib", 1))
	return 1


## A point the whole stage is empty at, for the "over nothing" pair.
##
## Searched rather than assumed: a room whose backdrop fills the stage has no such
## point inside it, and a point outside the stage is one the pointer can genuinely
## be at -- Director answers those two the same way, which is the whole of what is
## being asserted.
func _find_empty(preview: Node) -> Vector2:
	var table = preview.get("_table")
	var pixels: bool = preview.get("_hit_pixels")
	var sprites: Array = preview.call("frame_sprites")
	var size: Vector2 = preview.call("stage_size")
	var probes: Array = [
		Vector2(-8, -8), Vector2(size.x + 8, size.y + 8),
		Vector2(0, 0), Vector2(size.x - 1, size.y - 1),
	]
	for probe_value in probes:
		var probe: Vector2 = probe_value
		if Interaction.sprite_at(preview, probe, sprites, pixels, table) == 0:
			return probe
	return Vector2(-8, -8)


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
			h.begin("the movie opened")
			h.check("--file names a container of this root", false, only)
			quit(h.finish("the three sprite-under-the-pointer properties"))
			return
		await process_frame

	var host: Object = preview.get("_host")
	var table = preview.get("_table")
	var pixels: bool = preview.get("_hit_pixels")
	print("movie   : %s" % str(preview.call("movie_name")))

	# ------------------------------------------------------------ the rollOver
	var site := _find_site(preview, Args.number(args, "frames", 400))
	h.begin("`the rollOver` reads getSpriteIDFromPos, not the rect descent")
	if site.is_empty():
		# The honest shape: a movie with no matte sprite has no point where the
		# two descents can disagree, and saying so beats a check that cannot fail.
		h.check("this movie has a point where the two descents disagree", false,
			"no Matte-inked sprite with a transparent pixel is the topmost rect"
			+ " anywhere in the frames scanned; try --file")
		h.complete("`the rollOver` reads getSpriteIDFromPos, not the rect descent")
	else:
		var at: Vector2 = site["at"]
		print("site    : frame %d, (%d,%d): rect descent -> ch%d, ink-aware -> ch%d"
			% [int(site["frame"]), at.x, at.y, int(site["rolled"]), int(site["seen"])])
		await _point_at(preview, at)
		# `track_rollover` is what maintains the channel the builtin answers from,
		# and it is driven by motion in the real player. Without it the builtin
		# would answer about wherever the pointer last was and the comparison
		# below would be against stale state rather than against the other rule.
		preview.call("track_rollover", at)
		var prop: int = int(host.call("get_system_prop", "rollover"))
		var builtin: int = int(host.call("call_builtin", "rollover", []))
		h.check("the property answers the ink-aware descent",
			prop == int(site["seen"]),
			"the rollOver -> %d, getSpriteIDFromPos -> %d" % [prop, int(site["seen"])])
		h.check("and not the rect descent it used to answer",
			prop != int(site["rolled"]),
			"the rollOver -> %d, getRollOverSpriteIDFromPos -> %d" % [
				prop, int(site["rolled"])])
		h.check("the builtin keeps the rect descent, so the two spellings stay"
			+ " two functions", builtin == int(site["rolled"]),
			"rollOver() -> %d, wanted %d" % [builtin, int(site["rolled"])])
		h.complete("`the rollOver` reads getSpriteIDFromPos, not the rect descent")

		# ------------------------------------------- the member, at the same point
		h.begin("`the mouseCast` and `the mouseMember` name the same sprite")
		var seen := int(site["seen"])
		var sprites: Array = preview.call("frame_sprites")
		var live: Dictionary = {}
		for raw_value in sprites:
			var raw: Dictionary = raw_value
			if int(raw["channel"]) != seen:
				continue
			live = preview.call("_effective", raw)
			break
		var lib := int(live.get("cast_lib", 1))
		var slot := int(live.get("cast_id", 0))
		var packed := Members.pack_ref(lib, slot)
		var mouse_cast: Variant = host.call("get_system_prop", "mousecast")
		var mouse_member: Variant = host.call("get_system_prop", "mousemember")
		print("member  : ch%d is %d:%d, packed %d, bare slot %d"
			% [seen, lib, slot, packed, slot])
		h.check("`the mouseCast` is the sprite the ink-aware descent answered",
			int(mouse_cast) == packed,
			"the mouseCast -> %s, pack_ref(%d, %d) -> %d" % [
				str(mouse_cast), lib, slot, packed])
		# The half that is invisible on library 1 and wrong everywhere else. Only
		# assertable where the sprite came from a linked cast, so it says which
		# case it is in rather than passing quietly on a movie that cannot show it.
		if lib > 1:
			h.check("and is the packed reference, not the bare per-library slot",
				int(mouse_cast) != slot,
				"the mouseCast -> %s, bare slot is %d" % [str(mouse_cast), slot])
		else:
			h.check("this sprite is in library 1, where the packed reference and"
				+ " the bare slot are the same number", packed == slot,
				"nothing here can tell them apart")
		h.check("`the mouseMember` is a reference `member()` resolves back to the"
			+ " same sprite's member", mouse_member != null
				and str(Members.resolve_ref(mouse_member, "", table)) == str([lib, slot]),
			"the mouseMember -> %s resolves to %s, wanted %s" % [
				str(mouse_member),
				str(Members.resolve_ref(mouse_member, "", table)) \
					if mouse_member != null else "VOID",
				str([lib, slot])])
		h.complete("`the mouseCast` and `the mouseMember` name the same sprite")

	# ------------------------------------------------------------ over nothing
	var empty := _find_empty(preview)
	await _point_at(preview, empty)
	preview.call("track_rollover", empty)
	var sprites_now: Array = preview.call("frame_sprites")
	var under := Interaction.sprite_at(preview, empty, sprites_now, pixels, table)
	h.begin("over nothing, the two properties answer 0 and VOID")
	h.check("the probe point really is over nothing", under == 0,
		"getSpriteIDFromPos -> %d at (%d,%d)" % [under, empty.x, empty.y])
	var nothing_cast: Variant = host.call("get_system_prop", "mousecast")
	var nothing_member: Variant = host.call("get_system_prop", "mousemember")
	h.check("`the mouseCast` is 0", typeof(nothing_cast) == TYPE_INT
		and int(nothing_cast) == 0, "answered %s" % str(nothing_cast))
	# The check that fails on the -1 this port used to answer. Written as "is
	# VOID" and not "is falsy": -1, 0 and VOID are three different answers and
	# only one of them satisfies the `voidP` guard a movie writes here.
	h.check("`the mouseMember` is VOID", nothing_member == null,
		"answered %s (VOID is the only value `voidP` is true for)"
			% str(nothing_member))
	h.check("neither answers -1", str(nothing_cast) != "-1"
		and str(nothing_member) != "-1",
		"mouseCast %s, mouseMember %s" % [str(nothing_cast), str(nothing_member)])
	h.complete("over nothing, the two properties answer 0 and VOID")

	quit(h.finish("the three sprite-under-the-pointer properties"))
