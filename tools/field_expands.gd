extends SceneTree
## Does a field that outgrows its box grow, and does it then stay put? §1.2.
##
##   godot --headless --audio-driver Dummy --path . --script tools/field_expands.gd
##   godot --headless --audio-driver Dummy --path . --script tools/field_expands.gd -- --file PIP2DATA/SAVELOAD.dir
##   godot --headless --audio-driver Dummy --path . --script tools/field_expands.gd -- --root piposh --file PIPDATA/CAPROOM.dir
##
## `bugs.md` 80. Director sizes a field's widget from its box type and then writes
## the widget's dimensions back onto the sprite (`channel.cpp:774-779`, re-applied
## by `585-591` for every box type `getFixDims()` does not cover). This port laid
## the text out and told the sprite nothing, so an `adjust` or `limit` field whose
## text outgrew the member's rect clipped at the bottom edge and said nothing about
## it -- `director_text.layout` returns on the first line past the box bottom, so
## there is no error, no warning and no second symptom. A save slot silently lost
## its second line; a player typing into an editable field typed off the end of the
## world.
##
## Three things are asserted, and the third is the one that makes the other two
## safe to have.
##
## **It grew, and every line reached the canvas.** Driven by writing a string
## through `set the text of member`, which is the same store a player's typing and
## a script's `put ... into field` both land in, so the subject is the *runtime*
## text rather than anything a score carries. The check is against `_text_drawn`'s
## own line count, not against the box: a box that grew and a paint that still
## clipped would satisfy any assertion phrased in pixels.
##
## **A fixed or scrolling field did not grow.** `createWidget` passes
## `fixDims = (fixed || scrolling)` and `channel.cpp:587` re-pushes the widget's
## dimensions only when `!getFixDims()`, so those two are sized once and never
## again. Without this half, "fields grow" would be indistinguishable from "the box
## rule stopped applying", and the fixed arm -- the half of §1.2 that was already
## implemented -- would have no guard on it at all.
##
## **And it is a fixed point.** A laid-out size that feeds back into the layout
## that produced it is how this whole class of feature diverges: `limit` leaves the
## sprite's bbox alone, so a height stored onto the record would be laid out again,
## grow again, and grow without bound; `adjust`'s `MIN(bbox, initialRect)` would
## ratchet the other way and pin a field at whatever the last frame left. The port
## answers this by *deriving* the size rather than storing it -- every input to
## `sprite_geometry.drawn_size` is stable across a re-read -- and the assertion here
## is the one that would catch anybody quietly reintroducing the store: the drawn
## size is fed back into the record's own `width`/`height` and re-asked eight times,
## and it has to be the same answer every time.
##
## Title-agnostic: it names no movie, channel or member, and finds its own subject
## by walking the score for a field of each box class. A corpus that has none of a
## class says so and asserts nothing about it, which is the shape
## `tools/video_fallback.gd` and `sprite_lifetime`'s fourth case use.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Text := preload("res://director/director_text.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")

## Director's box types, from byte 3 of the field's specific block.
const BOX_ADJUST := 0
const BOX_SCROLL := 1
const BOX_FIXED := 2
const BOX_LIMIT := 3
const BOX_NAMES := {0: "adjust", 1: "scroll", 2: "fixed", 3: "limit"}

## The string written into the subject. Long enough to need several lines in any
## field this corpus has -- the widest is under 300px and this is ~340 characters
## at 12pt -- and carrying its own newlines so that a member with `word_wrap` off
## still overflows. A sentinel no authored field holds, for the same reason
## `text_and_shapes.gd` uses one: the movie's own scripts may put their value back.
const OVERFLOW := "9182736450 the quick brown fox jumps over the lazy dog\n" \
	+ "and again the quick brown fox jumps over the lazy dog\n" \
	+ "and once more the quick brown fox jumps over the lazy dog\n" \
	+ "and a fourth time the quick brown fox jumps over the lazy dog\n" \
	+ "and a fifth time the quick brown fox jumps over the lazy dog\n" \
	+ "and a sixth time the quick brown fox jumps over the lazy dog"


## A member reference `set_member_prop` accepts: its name where it has one, its
## number otherwise. Fields in this corpus are named, but a port is not entitled
## to assume the next title's are.
func _ref(member: Dictionary) -> Variant:
	var name := str(member.get("name", ""))
	return name if name != "" else int(member.get("cast_id", 0))


## Every field sprite in the score, grouped into the two box classes and keyed by
## `(member, channel)` so one candidate stands for the run it belongs to.
##
## Walked over the whole score rather than taken from one frame: which frame holds
## which kind of field is a property of the movie, and a movie may carry only one
## of the two classes.
func _candidates(preview: Node) -> Dictionary:
	var score = preview.get("_score")
	var table = preview.get("_table")
	var out := {"expanding": [], "fixed": []}
	var seen := {}
	for i in score.frame_count:
		for raw in score.frame(i).get("sprites", []):
			var sprite: Dictionary = raw
			var member: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if member.is_empty() or int(member.get("type", 0)) != Ink.TYPE_FIELD:
				continue
			if int(member.get("width", 0)) <= 0 or int(member.get("height", 0)) <= 0:
				continue
			# A stretched sprite is the author saying "I resized this deliberately"
			# and keeps the score's rect through every box type, so it cannot say
			# anything about the box rule either way.
			if bool(sprite.get("stretch", false)):
				continue
			var key := "%d:%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"]),
				int(sprite["channel"])]
			if seen.has(key):
				continue
			seen[key] = true
			var box := int(member.get("text_type", BOX_ADJUST))
			var group := "fixed" if box in [BOX_FIXED, BOX_SCROLL] else "expanding"
			(out[group] as Array).append(
				{"frame": i, "sprite": sprite, "member": member, "box": box})
	return out


## The first candidate that actually reaches the paint, with what it laid out.
##
## **Being in the score is not the same as being drawn**, and picking the first
## record and asserting it painted is how this harness first failed: `CAPROOM.dir`
## carries a field on channel 108 of a frame whose visible sprites stop long
## before it. A subject that never reaches `_text_drawn` proves nothing about the
## box rule, so it is skipped rather than failed -- and running out of candidates
## is what gets reported, once, by the caller.
func _first_painted(preview: Node, candidates: Array) -> Dictionary:
	for entry in candidates:
		var laid: Dictionary = await _repaint(preview, entry)
		if not laid.is_empty():
			return {"subject": entry, "laid": laid}
	return {}


## Repaint the frame a subject is on and hand back what the field laid out.
func _repaint(preview: Node, subject: Dictionary) -> Dictionary:
	preview.set("_index", int(subject["frame"]))
	preview.call("queue_redraw")
	await process_frame
	return (preview.get("_text_drawn") as Dictionary).get(
		int((subject["sprite"] as Dictionary)["channel"]), {})


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var wanted := Args.text(args, "file", "")
	if wanted != "":
		preview.call("lingo_go_movie", wanted, null)
		await process_frame
	# Paused for the whole run, for the reason `text_and_shapes.gd` gives: the
	# playhead is set directly, and an unpaused preview would run the frame's own
	# scripts during the awaited paint and put the movie's value back over the
	# sentinel.
	preview.set("_paused", true)

	var score = preview.get("_score")
	var host = preview.get("_host")
	if score == null:
		print("no score loaded")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))
	var candidates := _candidates(preview)
	print("%s: %d expanding and %d fixed/scrolling field sprite(s) in the score" % [
		movie, (candidates["expanding"] as Array).size(),
		(candidates["fixed"] as Array).size()])

	# ------------------------------------------------ the expanding box types
	var found: Dictionary = await _first_painted(preview, candidates["expanding"])
	if not found.is_empty():
		var subject: Dictionary = found["subject"]
		var member: Dictionary = subject["member"]
		var channel := int((subject["sprite"] as Dictionary)["channel"])
		var natural := Vector2(float(member.get("width", 0)), float(member.get("height", 0)))
		h.begin("an %s field grows to the text it is given and draws all of it"
			% str(BOX_NAMES.get(int(subject["box"]), int(subject["box"]))))
		var before: Dictionary = found["laid"]
		h.check("the field reached the paint before anything was written to it",
			not before.is_empty(), "ch%d on f%d" % [channel, int(subject["frame"])])
		host.call("set_member_prop", _ref(member), "", "text", OVERFLOW)
		var after: Dictionary = await _repaint(preview, subject)
		h.check("and again after", not after.is_empty(), "ch%d" % channel)
		if not after.is_empty():
			var rect: Rect2 = after["rect"]
			var style: Dictionary = Text.style_of(member)
			# What the string needs, measured by the layout engine with the clip
			# lifted. Asserted against the *line count that was drawn* rather than
			# against the box, because a box that grew while the paint still
			# stopped early is the exact failure this file exists to catch and it
			# is invisible in pixels.
			var needs: int = Text.layout(
				Rect2(Vector2.ZERO, Vector2(natural.x, INF)), OVERFLOW, style).size()
			print("   ch%-4d %-16s %s  %dx%d member, box %s, %d lines needed, %d drawn" % [
				channel, str(member.get("name", "")),
				str(BOX_NAMES.get(int(subject["box"]), int(subject["box"]))),
				int(natural.x), int(natural.y), str(rect.size), needs, int(after["lines"])])
			h.check("the string needs more lines than the member's own box holds",
				needs > int(natural.y / maxf(1.0, float(style.get("line_height", 16)))),
				"%d lines at %spx in a %dpx box" % [
					needs, str(style.get("line_height", 16)), int(natural.y)])
			h.check("the box grew past the member's own height",
				rect.size.y > natural.y, "%s against a %dx%d member" % [
					str(rect.size), int(natural.x), int(natural.y)])
			h.check("it grew to exactly what the text lays out to",
				int(rect.size.y) == int(maxf(natural.y,
					Text.laid_out_height(natural.x, OVERFLOW, style))),
				"%d high, text lays out to %d" % [int(rect.size.y),
					int(Text.laid_out_height(natural.x, OVERFLOW, style))])
			# Director's Adjust to Fit grows a field vertically; the author's width
			# is the wrapping width and `createWindowOrWidget` hands MacText the
			# member's own width as its `maxWidth`. A rule that grew the width too
			# would rewrap the text and change the answer it was derived from.
			h.check("and its width did not move", int(rect.size.x) == int(natural.x),
				"%d wide, member is %d" % [int(rect.size.x), int(natural.x)])
			h.check("every line of the text reached the canvas",
				int(after["lines"]) == needs,
				"%d of %d drawn" % [int(after["lines"]), needs])
			h.check("and the text that was drawn is the one that was written",
				str(after["text"]) == OVERFLOW)
		h.complete("an %s field grows to the text it is given and draws all of it"
			% str(BOX_NAMES.get(int(subject["box"]), int(subject["box"]))))

		# ------------------------------------------------------- the fixed point
		# The assertion that keeps the feature from being a runaway. Two forms,
		# because they fail differently: painting the same frame twice must give
		# the same box, and feeding the answer back into the record it was derived
		# from must not move it.
		h.begin("a field laid out twice reports the same size the second time")
		var once: Dictionary = await _repaint(preview, subject)
		var twice: Dictionary = await _repaint(preview, subject)
		h.check("two paints of the same frame lay out the same box",
			not once.is_empty() and not twice.is_empty()
			and (once["rect"] as Rect2).size == (twice["rect"] as Rect2).size,
			"%s then %s" % [str((once.get("rect", Rect2()) as Rect2).size),
				str((twice.get("rect", Rect2()) as Rect2).size)])
		# The live record, stamped with the runtime text by `_effective` -- which
		# is the vehicle under test. Sizing it here rather than reading `rect`
		# again is what proves the stamp survives the funnel every caller uses.
		var live: Dictionary = preview.call("_effective", subject["sprite"], true)
		h.check("the effective sprite carries the runtime text the sizing rule needs",
			str(live.get(Geometry.FIELD_TEXT, "")) == OVERFLOW,
			"%d chars stamped" % str(live.get(Geometry.FIELD_TEXT, "")).length())
		var seen: Array[Vector2] = []
		var fed: Dictionary = live.duplicate()
		for _step in 8:
			var size: Vector2 = Geometry.drawn_size(fed, member)
			if seen.is_empty() or seen[seen.size() - 1] != size:
				seen.append(size)
			# The write-back Director does onto the sprite. The port derives the
			# size instead of storing it, so this must be a no-op; a version that
			# stored it would grow on every pass for `limit` and shrink for
			# `adjust`, and eight passes is enough to see either.
			fed["width"] = int(size.x)
			fed["height"] = int(size.y)
		h.check("feeding the drawn size back into the record does not move it",
			seen.size() == 1, "settled on %s" % str(seen))
		h.check("and the size it settles on is the one that was painted",
			not twice.is_empty() and seen.size() > 0
			and seen[0] == (twice["rect"] as Rect2).size,
			"%s against %s" % [str(seen), str((twice.get("rect", Rect2()) as Rect2).size)])
		h.complete("a field laid out twice reports the same size the second time")
	else:
		print("   no adjust or limit field paints on this stage; that arm asserts nothing")

	# ------------------------------------------------- the box types that do not
	var held: Dictionary = await _first_painted(preview, candidates["fixed"])
	if not held.is_empty():
		var subject: Dictionary = held["subject"]
		var member: Dictionary = subject["member"]
		var channel := int((subject["sprite"] as Dictionary)["channel"])
		h.begin("a %s field is sized once and does not grow for anything"
			% str(BOX_NAMES.get(int(subject["box"]), int(subject["box"]))))
		var before: Dictionary = held["laid"]
		h.check("it reached the paint", not before.is_empty(), "ch%d" % channel)
		host.call("set_member_prop", _ref(member), "", "text", OVERFLOW)
		var after: Dictionary = await _repaint(preview, subject)
		if not before.is_empty() and not after.is_empty():
			var was: Rect2 = before["rect"]
			var now: Rect2 = after["rect"]
			print("   ch%-4d %-16s %s  %s before, %s after a %d-character write" % [
				channel, str(member.get("name", "")),
				str(BOX_NAMES.get(int(subject["box"]), int(subject["box"]))),
				str(was.size), str(now.size), OVERFLOW.length()])
			h.check("the box is exactly what it was before the write",
				was.size == now.size, "%s -> %s" % [str(was.size), str(now.size)])
			# And the other half of `fixDims`: what does not fit is clipped, which
			# is what a fixed box means and is not a defect to be fixed later.
			h.check("the text past the bottom edge is clipped rather than shown",
				int(after["lines"]) * int(Text.style_of(member).get("line_height", 16))
					<= int(now.size.y) + int(Text.style_of(member).get("line_height", 16)),
				"%d lines in %dpx" % [int(after["lines"]), int(now.size.y)])
		h.complete("a %s field is sized once and does not grow for anything"
			% str(BOX_NAMES.get(int(subject["box"]), int(subject["box"]))))
	else:
		print("   no fixed or scrolling field paints on this stage; that arm asserts nothing")

	print("")
	quit(h.finish("expanding field boxes in %s" % movie))
