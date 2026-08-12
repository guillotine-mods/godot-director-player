extends SceneTree
## `the regPoint of member` is writable, and moving it moves the art.
##
##   godot --headless --audio-driver Dummy --path . --script tools/reg_point.gd
##   godot --headless --audio-driver Dummy --path . --script tools/reg_point.gd -- \
##       --root res://test-games/itamar-park --file torfim/torfim.dir
##
## Title-agnostic: it names no movie, channel or member. It takes whichever
## bitmap sprite the booted movie has on the frame it settles on, and asserts
## against *that* sprite's drawn rectangle.
##
## ## What this guards
##
## Director's `locH`/`locV` position a sprite's **registration point**, not its
## top-left corner (`DIRECTOR_ENGINE.md` §8.10), and the registration point
## belongs to the cast member. So one write re-anchors every sprite drawn from
## that member at once, which is why titles use it as a layout primitive:
## Itamar Park's `setRegPointToCorner(51, 78, 1, #right, #Middle)` walks 28
## members and re-anchors each to its right-middle edge in one statement.
##
## This port answered the property and could not store it (`bugs.md` 89). That is
## the worst shape a gap can have: the statement returns, the read answers the
## authored value, the movie carries on, and nothing anywhere says the layout it
## asked for did not happen.
##
## ## Why the assertion is the drawn rectangle and not the property
##
## A setter and a getter agreeing proves a dictionary. The invariant a player can
## see is that the *art moves*, so every check below writes through Lingo and
## measures `_sprite_rect` — the same call the painter, the hit test and
## `rollOver` all go through (`sprite_geometry.stage_rect`). A write that reached
## a store the painter does not read would pass a round-trip check and fail this
## one.
##
## ## The four things it asserts
##
##   moves          writing `point(x + dx, y + dy)` moves the drawn rect by
##                  exactly `(-dx, -dy)`, because the offset is subtracted from
##                  `loc` to reach the top-left corner
##   round trip     the property reads back what was written. This is the half
##                  that makes `member(i).regPoint = member(i).regPoint +
##                  point(dx, dy)` — Park's `addToRegPoint`, and the idiom any
##                  title nudging an anchor uses — move by `(dx, dy)` rather than
##                  by `(dx, dy)` plus the member's rect origin. 97,464 of the
##                  120,869 bitmap members in this corpus have a non-zero origin,
##                  so a read that answered the stored *offset* would break the
##                  nudge for four members in five
##   both spellings a `Vector2` from `point()` and a two-element `Array` from
##                  `the loc of sprite` are one Director type, and both must
##                  land. `LingoValue.components` is the single flattener and
##                  this is what says so
##   declines       a scalar is not a point. The reference warns and writes
##                  nothing (`BitmapCastMember::setField` @ ScummVM 805f259a),
##                  and coercing `n` to `(n, n)` would move every sprite drawn
##                  from the member somewhere no script asked for

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Frames to let the movie settle before looking for a sprite. Long enough for a
## boot movie to reach artwork, short enough not to be a play-through.
const SETTLE_FRAMES := 40


## Run one Lingo statement list against the booted movie, and answer the global
## it left behind. `null` when it did not compile.
func _eval(preview: Node, expression: String) -> Variant:
	var interp = preview.get("_interpreter")
	if interp == null:
		return null
	var errors: Array = []
	var code = interp.compile_statements(
		"global gRegProbe\ngRegProbe = (%s)" % expression, "reg_point", errors)
	if not errors.is_empty():
		return null
	interp.reset_steps()
	interp.run_compiled(code)
	for store in [interp.globals, preview.get("_host").globals]:
		for key in (store as Dictionary).keys():
			if str(key).to_lower() == "gregprobe":
				return (store as Dictionary)[key]
	return null


func _run(preview: Node, statements: String) -> void:
	var interp = preview.get("_interpreter")
	if interp == null:
		return
	var errors: Array = []
	var code = interp.compile_statements(statements, "reg_point", errors)
	if not errors.is_empty():
		push_error("reg_point: %s" % str(errors))
		return
	interp.reset_steps()
	interp.run_compiled(code)


## The drawn rectangle of one channel, through the placement rule the painter
## uses. `Rect2()` when the channel is not on the frame.
func _rect_of(preview: Node, channel: int) -> Rect2:
	for s in (preview.call("frame_sprites") as Array):
		var sprite: Dictionary = preview.call("_effective", s, true)
		if not sprite.is_empty() and int(sprite.get("channel", 0)) == channel:
			return preview.call("_sprite_rect", sprite)
	return Rect2()


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var preview: Node = (load("res://scenes/director_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	for i in SETTLE_FRAMES:
		await process_frame
	# **Stop the score before measuring anything.** Every check below compares a
	# drawn rectangle sampled before a write with one sampled after, across an
	# awaited frame -- and a movie that is still playing moves its own sprites in
	# between, so the comparison measures the score rather than the write. That is
	# not hypothetical: on `piposh-ru` the boot movie settles on frame 87 with an
	# animating channel 1, and the "a scalar writes nothing" check read
	# `(-71,-31) -> (-74,40)` and failed for a write that had correctly done
	# nothing. `_paused` is the debug key's own flag and `_advance` honours it, so
	# this is the same stillness a human gets by pressing pause.
	preview.set("_paused", true)
	await process_frame

	# A bitmap sprite with a real size, chosen from the frame rather than named.
	# Type 1 because the registration point is a bitmap's property in the
	# reference (`BitmapCastMember::getField`), and a member with no size cannot
	# show a displacement.
	var channel := 0
	var member := 0
	var lib := 0
	var origin := Vector2i.ZERO
	var table = preview.get("_table")
	for s in (preview.call("frame_sprites") as Array):
		var sprite: Dictionary = preview.call("_effective", s, true)
		if sprite.is_empty():
			continue
		var m: Dictionary = table.get_member(
			int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0)))
		if int(m.get("type", 0)) != 1:
			continue
		if int(m.get("width", 0)) <= 0 or int(m.get("height", 0)) <= 0:
			continue
		var box: Dictionary = m.get("initial_rect", {})
		var at := Vector2i(int(box.get("left", 0)), int(box.get("top", 0)))
		# **A non-zero rect origin is preferred, and the preference is the point
		# of the round-trip check.** The property is in the member's own
		# coordinates and the stored value is an offset from its top-left; the
		# two are the same number whenever the origin is (0,0), so a member at
		# the origin cannot tell a correct translation from no translation at
		# all. Four bitmap members in five in this corpus have one, so the search
		# almost always finds one -- and it falls back to any bitmap rather than
		# failing, because a harness that only runs on some corpora is a harness
		# nobody trusts on the others.
		if channel > 0 and at == Vector2i.ZERO:
			continue
		channel = int(sprite.get("channel", 0))
		lib = int(sprite.get("cast_lib", 0))
		member = int(sprite.get("cast_id", 0))
		origin = at
		if origin != Vector2i.ZERO:
			break

	var where := "%s, %d" % [str(member), lib]
	h.begin("a bitmap sprite is on the frame")
	# **Floored, so the run cannot pass by finding nothing.** Every check below is
	# about a sprite; with no sprite they would all be vacuous, which is the
	# "passing with 0 checks" failure `harness.gd` exists to make impossible.
	h.check("the booted movie draws a bitmap sprite to measure",
		channel > 0, "%s frame %d, ch%d %d:%d, rect origin %s" % [
			str(preview.call("movie_name")), int(preview.get("_index")),
			channel, lib, member, str(origin)])
	h.complete("a bitmap sprite is on the frame")
	if channel <= 0:
		quit(h.finish("the regPoint of member is writable"))
		return

	var start: Rect2 = _rect_of(preview, channel)
	var authored: Variant = _eval(preview, "member(%s).regPoint" % where)

	# ------------------------------------------------------------------ moves
	h.begin("a written regPoint moves the art")
	var dx := 17
	var dy := -23
	_run(preview, "member(%s).regPoint = member(%s).regPoint + point(%d, %d)"
		% [where, where, dx, dy])
	await process_frame
	var moved: Rect2 = _rect_of(preview, channel)
	h.check("the drawn rect moves by minus the anchor's own displacement",
		is_equal_approx(moved.position.x, start.position.x - dx)
			and is_equal_approx(moved.position.y, start.position.y - dy),
		"ch%d %d:%d  %s -> %s, wanted %s" % [channel, lib, member,
			str(start.position), str(moved.position),
			str(start.position - Vector2(dx, dy))])
	h.check("the size is untouched: an anchor is not a resize",
		is_equal_approx(moved.size.x, start.size.x)
			and is_equal_approx(moved.size.y, start.size.y),
		"%s -> %s" % [str(start.size), str(moved.size)])
	h.complete("a written regPoint moves the art")

	# ------------------------------------------------------------- round trip
	h.begin("the property reads back what was written")
	var after: Variant = _eval(preview, "member(%s).regPoint" % where)
	var want := [
		int(LingoValue.components(authored)[0]) + dx,
		int(LingoValue.components(authored)[1]) + dy,
	]
	var got: Array = LingoValue.components(after)
	h.check("regPoint + point(dx, dy) reads back as regPoint + (dx, dy)",
		got.size() >= 2 and int(got[0]) == want[0] and int(got[1]) == want[1],
		"authored %s, read %s, wanted %s" % [str(authored), str(after), str(want)])
	# The translation itself, stated rather than inferred: the property is in the
	# member's own coordinates and the store holds the offset from its top-left,
	# so the two differ by the rect origin. This is the check that would have gone
	# red for the reading this arm had before `write_prop` existed, and on this
	# corpus it is a real difference for 97,464 of 120,869 bitmap members.
	var stored: Dictionary = table.get_member(lib, member)
	h.check("the property is the member's own coordinate, not the stored offset",
		got.size() >= 2
			and int(got[0]) == int(stored.get("reg_offset_x", 0)) + origin.x
			and int(got[1]) == int(stored.get("reg_offset_y", 0)) + origin.y,
		"read %s, stored offset (%d,%d), rect origin %s" % [str(after),
			int(stored.get("reg_offset_x", 0)), int(stored.get("reg_offset_y", 0)),
			str(origin)])
	h.complete("the property reads back what was written")

	# ---------------------------------------------------------- both spellings
	h.begin("a point and a two-element list are one type")
	# `the loc of sprite` answers an `Array` and `point()` a `Vector2`; the same
	# displacement written through each has to land in the same place, or a
	# handler that anchors a member to another sprite's position diverges from
	# one that anchors it to a literal.
	_run(preview, "member(%s).regPoint = [%d, %d]" % [where, want[0], want[1]])
	await process_frame
	var by_list: Rect2 = _rect_of(preview, channel)
	h.check("the list spelling lands where the point spelling did",
		is_equal_approx(by_list.position.x, moved.position.x)
			and is_equal_approx(by_list.position.y, moved.position.y),
		"%s vs %s" % [str(by_list.position), str(moved.position)])
	h.complete("a point and a two-element list are one type")

	# --------------------------------------------------------------- declines
	h.begin("a scalar is declined rather than coerced")
	_run(preview, "member(%s).regPoint = 3" % where)
	await process_frame
	var after_scalar: Rect2 = _rect_of(preview, channel)
	h.check("a number writes nothing and the art does not move",
		is_equal_approx(after_scalar.position.x, by_list.position.x)
			and is_equal_approx(after_scalar.position.y, by_list.position.y),
		"%s -> %s" % [str(by_list.position), str(after_scalar.position)])
	h.complete("a scalar is declined rather than coerced")

	quit(h.finish("the regPoint of member is writable and moves every sprite drawn from it"))
