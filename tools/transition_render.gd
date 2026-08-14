extends SceneTree
## Does a transition *draw*, and does it draw the thing its name says?
##
##   godot --headless --audio-driver Dummy --script tools/transition_render.gd
##
## `director/director_transition.gd` names all 52 Director transition types and,
## until the change this file arrived with, drew none of them: the port resolved
## the member, computed the duration and held the playhead, and the frame then
## cut. This asserts the other half.
##
## ## Why the assertions are about direction and not about change
##
## The cheap version of this harness renders a transition halfway and checks that
## the result differs from both endpoints. **That check passes for every
## algorithm in the table, including the wrong one**: a push-left, a dissolve and
## a venetian blind all differ from both frames at 50%, so a dispatch that sent
## every type to the same routine would be green. So the frames here are built to
## carry their own coordinates — the departing frame's red channel encodes `x` and
## its green channel encodes `y` — and each case asserts *where a given pixel of
## the departing frame ended up*:
##
##   a push-left moves it left by exactly the step distance;
##   a wipe leaves it where it was and replaces a growing band;
##   a cover leaves it where it was while the arriving frame slides over it;
##   a reveal moves it and puts the arriving frame in what it vacated;
##   a dissolve leaves it where it was and replaces a scatter, which is the one
##     of the five that puts both pictures inside an 8x8 window.
##
## Read the other way round: each case's assertion is false for the other four.
##
## ## Two things every type is held to
##
## **Step 0 is the departing frame exactly and the last step is the arriving
## frame exactly.** For the dissolve families that is the strongest statement
## available about the shift register — it visits every cell of the grid once, so
## a register with the wrong tap word leaves cells undrawn and the last step is
## not the arriving frame. For everything else it is what makes a transition a
## transition rather than a fade to something else.
##
## **The play is stepped by the hold that already exists.** The last case boots
## the real player, arms a `puppetTransition`, and asserts that the step index
## rises through the hold and stands at exactly `steps` on the tick the hold
## releases — not before it, which would run the movie's scripts early, and not
## after, which is the timing bug `hold_ms` exists to prevent.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Transition := preload("res://director/director_transition.gd")

## Small on purpose. Every algorithm's arithmetic is in proportions of the clip,
## so a 96x72 stage exercises the same branches as a 640x480 one and a run over
## all 52 types costs seconds instead of minutes.
const W := 96
const H := 72


func _init() -> void:
	Args.parse()
	var h := Harness.new()
	_decodes_the_member(h)
	_every_type_builds(h)
	_endpoints_are_exact(h)
	_push_moves_the_old_frame(h)
	_wipe_does_not(h)
	_cover_and_reveal_differ(h)
	_dissolve_scatters(h)
	_blinds_are_stripes(h)
	_change_area_confines_it(h)
	await _steps_inside_the_hold(h)
	quit(h.finish("transition drawing, direction by direction"))


## The departing frame carries its own coordinates: red is `x`, green is `y`.
## That is what lets a case say "this pixel came from there" instead of "this
## pixel changed".
static func _departing() -> Image:
	var image := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			image.set_pixel(x, y, Color8(x * 2 + 1, y * 3 + 1, 0, 255))
	return image


## The arriving frame is the one colour the departing frame can never hold: blue
## is zero everywhere above, so one channel test says which picture a pixel is.
static func _arriving() -> Image:
	var image := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	image.fill(Color8(0, 0, 255, 255))
	return image


static func _is_arriving(image: Image, x: int, y: int) -> bool:
	return image.get_pixel(x, y).b8 > 128


## Which pixel of the departing frame this one is, or `(-1, -1)` when it is not
## from the departing frame at all.
static func _origin(image: Image, x: int, y: int) -> Vector2i:
	var c := image.get_pixel(x, y)
	if c.b8 > 128:
		return Vector2i(-1, -1)
	return Vector2i((c.r8 - 1) / 2, (c.g8 - 1) / 3)


static func _arriving_fraction(image: Image) -> float:
	var count := 0
	for y in H:
		for x in W:
			if _is_arriving(image, x, y):
				count += 1
	return float(count) / float(W * H)


static func _play(type_code: int, chunk: int, ms: int, changed_area: int = 0) -> Transition.Play:
	return Transition.Play.new({
		"transition_type": type_code,
		"chunk_size": chunk,
		"duration_ms": float(ms),
		"change_area": changed_area,
	}, Vector2i(W, H), _departing(), _arriving())


static func _same(a: Image, b: Image) -> bool:
	return a != null and b != null and a.get_data() == b.get_data()


## The 6-byte block, against the field order the reference reads it in.
func _decodes_the_member(h) -> void:
	h.begin("the transition member's 6 bytes decode as the reference reads them")
	# CHESS 199's own record, which is the one the old comment in
	# `director_transition.gd` guessed the last two fields of.
	var chess := Transition.decode_member(
		PackedByteArray([0x00, 0x08, 0x34, 0x02, 0x02, 0x58]))
	h.check("chunk size is byte 1", int(chess.get("chunk_size", 0)) == 8,
		str(chess.get("chunk_size", 0)))
	h.check("type is byte 2", int(chess.get("transition_type", 0)) == 52,
		str(chess.get("transition_type", 0)))
	h.check("flags is byte 3, not byte 0", int(chess.get("flags", -1)) == 2,
		str(chess.get("flags", -1)))
	# `castmember/transition.cpp`: `_area = !(_flags & 1)`. Byte 3 is 2 in every
	# transition member of every root, so this is a changed-area transition and
	# the old reading of byte 3 as the area selector would have said 2.
	h.check("change area is bit 0 of the flags, inverted",
		int(chess.get("change_area", -1)) == 1, str(chess.get("change_area", -1)))
	h.check("duration is the big-endian tail",
		absf(float(chess.get("duration_ms", 0.0)) - 600.0) < 0.5,
		str(chess.get("duration_ms", 0.0)))
	h.check("a short record decodes to nothing",
		Transition.decode_member(PackedByteArray([0, 1, 2])).is_empty())
	# `playTransition` clamps up to 250 ms; `initTransParams` resets the two fast
	# dissolves down to it. Both are what the playhead is held for.
	h.check("a sub-quarter-second duration is held for a quarter second",
		Transition.hold_ms({"transition_type": 1, "duration_ms": 40.0}) == 250.0,
		"%.0f ms" % Transition.hold_ms({"transition_type": 1, "duration_ms": 40.0}))
	h.check("`dissolve bits fast` plays for 250 ms however long the file says",
		Transition.hold_ms({"transition_type": 50, "duration_ms": 4000.0}) == 250.0,
		"%.0f ms" % Transition.hold_ms({"transition_type": 50, "duration_ms": 4000.0}))
	h.complete("the transition member's 6 bytes decode as the reference reads them")


## Every numbered type resolves to an algorithm and produces a real step count.
## The point is coverage rather than pixels: a type that fell through the
## dispatch would report zero steps or degrade to a cut, and would then quietly
## be a cut for ever.
func _every_type_builds(h) -> void:
	h.begin("all 52 types dispatch to an algorithm and step more than once")
	var cut: Array[int] = []
	var single: Array[int] = []
	# **Chunk 2, and the chunk matters to what this can assert.** A blind's step
	# count is the strip height divided by the chunk (`initTransParams`,
	# `kTransDirBlindsH`), and twelve blinds across a 72-pixel test stage are six
	# pixels each -- so types 37 and 49 legitimately take *one* step at the chunk
	# 8 the corpus's own members carry, and asserting more than one at that chunk
	# would be asserting something about the size of the stage this file made up.
	# At chunk 2 every type in the table has somewhere to go.
	for type_code in range(1, 53):
		var play := _play(type_code, 2, 1000)
		if play.degraded != "":
			cut.append(type_code)
			continue
		if play.steps < 2:
			single.append(type_code)
	h.check("none degrades to a cut", cut.is_empty(), str(cut))
	h.check("none collapses to a single step", single.is_empty(), str(single))
	h.check("type 0 is `none` and draws nothing",
		_same(_play(0, 2, 1000).surface, _departing()))
	h.check("a type outside the table is a cut, not a crash",
		_play(99, 2, 1000).degraded != "")
	# And the corpus's own chunk, which is what the two members of CHESS and
	# `strtgame.dir` carry, over the same 52.
	var coarse: Array[int] = []
	for type_code in range(1, 53):
		if _play(type_code, 8, 1000).steps < 1:
			coarse.append(type_code)
	h.check("and at the chunk size the corpus uses", coarse.is_empty(), str(coarse))
	h.complete("all 52 types dispatch to an algorithm and step more than once")


## The two endpoints, for every type. See the header: for the dissolves this is
## the shift register's correctness and not a formality.
func _endpoints_are_exact(h) -> void:
	h.begin("every type starts on the departing frame and ends on the arriving one")
	var wrong_start: Array[int] = []
	var wrong_end: Array[int] = []
	var never_moved: Array[int] = []
	var departing := _departing()
	var arriving := _arriving()
	for type_code in range(1, 53):
		var play := _play(type_code, 2, 1000)
		if play.degraded != "":
			continue
		if not _same(play.surface, departing):
			wrong_start.append(type_code)
		# Halfway, which is where a dispatch that ran the wrong algorithm would
		# still be somewhere between the two frames -- so this is the weak half of
		# the case and the direction cases below are the strong one.
		play.advance_to(maxi(1, play.steps / 2))
		if _same(play.surface, departing) or _same(play.surface, arriving):
			never_moved.append(type_code)
		play.advance_to(play.steps)
		if not _same(play.surface, arriving):
			wrong_end.append(type_code)
	h.check("step 0 is the departing frame", wrong_start.is_empty(), str(wrong_start))
	h.check("mid-span is neither frame", never_moved.is_empty(), str(never_moved))
	h.check("the last step is the arriving frame exactly",
		wrong_end.is_empty(), str(wrong_end))
	h.complete("every type starts on the departing frame and ends on the arriving one")


## Push (11-14): the departing frame *slides*, and the arriving one slides in
## behind it. The assertion is on where a named pixel went, which is false for
## every other family.
func _push_moves_the_old_frame(h) -> void:
	h.begin("a push slides the departing frame by the step distance")
	var play := _play(11, 8, 1000)
	var mid := maxi(1, play.steps / 2)
	play.advance_to(mid)
	var d := play.x_step * mid / Transition.TSTEP_FRAC
	h.check("it has moved a measurable distance", d > 4 and d < W - 4, "%d px" % d)
	var sample_y := H / 2
	# The pixel now at x came from x + d: the departing frame moved left.
	var moved := _origin(play.surface, 2, sample_y)
	h.check("the pixel at the left edge came from `d` pixels to its right",
		moved == Vector2i(2 + d, sample_y), "%s, expected (%d,%d)" % [
			str(moved), 2 + d, sample_y])
	h.check("it is not where a wipe would have left it",
		moved != Vector2i(2, sample_y))
	h.check("the arriving frame occupies the band it vacated",
		_is_arriving(play.surface, W - 2, sample_y))
	# Push right is the mirror, and asserting it separately is what stops a
	# dispatch that sent both to one direction from passing.
	var back := _play(12, 8, 1000)
	var mid_back := maxi(1, back.steps / 2)
	back.advance_to(mid_back)
	var db := back.x_step * mid_back / Transition.TSTEP_FRAC
	var moved_back := _origin(back.surface, W - 3, sample_y)
	h.check("push right moves it the other way",
		moved_back == Vector2i(W - 3 - db, sample_y), "%s, expected (%d,%d)" % [
			str(moved_back), W - 3 - db, sample_y])
	h.complete("a push slides the departing frame by the step distance")


## Wipe (1-4): nothing moves. A growing band of the arriving frame replaces the
## departing one in place, and the pixel outside the band is exactly where it
## started -- which is the assertion a push fails.
func _wipe_does_not(h) -> void:
	h.begin("a wipe replaces a growing band and moves nothing")
	var play := _play(1, 8, 1000)
	var mid := maxi(1, play.steps / 2)
	play.advance_to(mid)
	var d := play.x_step * mid / Transition.TSTEP_FRAC
	var sample_y := H / 2
	h.check("the band that has arrived is the arriving frame",
		_is_arriving(play.surface, maxi(0, d - 2), sample_y))
	h.check("the rest is the departing frame, unmoved",
		_origin(play.surface, mini(W - 1, d + 4), sample_y)
			== Vector2i(mini(W - 1, d + 4), sample_y))
	h.check("the band grows from the left for `wipe right`",
		not _is_arriving(play.surface, W - 1, sample_y))
	var left := _play(2, 8, 1000)
	left.advance_to(maxi(1, left.steps / 2))
	h.check("and from the right for `wipe left`",
		_is_arriving(left.surface, W - 1, sample_y)
			and not _is_arriving(left.surface, 0, sample_y))
	var down := _play(3, 8, 1000)
	down.advance_to(maxi(1, down.steps / 2))
	h.check("`wipe down` runs on the other axis",
		_is_arriving(down.surface, W / 2, 0)
			and not _is_arriving(down.surface, W / 2, H - 1))
	# Centre-out and edges-in are the same family read from the middle.
	var centre := _play(5, 8, 1000)
	centre.advance_to(maxi(1, centre.steps / 2))
	h.check("`centre out horizontal` opens from the middle",
		_is_arriving(centre.surface, W / 2, sample_y)
			and not _is_arriving(centre.surface, 0, sample_y)
			and not _is_arriving(centre.surface, W - 1, sample_y))
	var edges := _play(6, 8, 1000)
	edges.advance_to(maxi(1, edges.steps / 2))
	h.check("`edges in horizontal` closes onto it",
		not _is_arriving(edges.surface, W / 2, sample_y)
			and _is_arriving(edges.surface, 0, sample_y)
			and _is_arriving(edges.surface, W - 1, sample_y))
	h.complete("a wipe replaces a growing band and moves nothing")


## Cover and reveal are the two families that look alike on a still frame and are
## opposites in motion: under a cover the departing frame stays put and the
## arriving one slides over it; under a reveal the departing frame slides away
## and the arriving one is already behind it.
func _cover_and_reveal_differ(h) -> void:
	h.begin("a cover holds the departing frame still, a reveal slides it away")
	var cover := _play(29, 8, 1000)
	var mid := maxi(1, cover.steps / 2)
	cover.advance_to(mid)
	var sample_x := W / 2
	h.check("under `cover down` the arriving frame is at the top",
		_is_arriving(cover.surface, sample_x, 1))
	h.check("and the departing frame below it has not moved",
		_origin(cover.surface, sample_x, H - 2) == Vector2i(sample_x, H - 2),
		str(_origin(cover.surface, sample_x, H - 2)))
	var reveal := _play(15, 8, 1000)
	var rmid := maxi(1, reveal.steps / 2)
	reveal.advance_to(rmid)
	var dy := reveal.y_step * rmid / Transition.TSTEP_FRAC
	h.check("under `reveal up` the departing frame has moved up by the step distance",
		_origin(reveal.surface, sample_x, 1) == Vector2i(sample_x, 1 + dy),
		"%s, expected (%d,%d)" % [
			str(_origin(reveal.surface, sample_x, 1)), sample_x, 1 + dy])
	h.check("and the arriving frame fills what it vacated",
		_is_arriving(reveal.surface, sample_x, H - 2))
	h.check("which is not what the cover did",
		_origin(cover.surface, sample_x, H - 2)
			!= _origin(reveal.surface, sample_x, H - 2))
	h.complete("a cover holds the departing frame still, a reveal slides it away")


## Dissolve (23-28, 50-52): the one family that puts both pictures inside the
## same 8x8 window. Everything else in the table has a moving boundary, so any
## small window away from that boundary holds one picture or the other.
func _dissolve_scatters(h) -> void:
	h.begin("a dissolve interleaves the two frames rather than sweeping between them")
	# Type 51 with chunk 1, which is what `piposh-en`/`piposh-ru` `strtgame.dir`
	# actually plays.
	var play := _play(51, 1, 350)
	var mid := maxi(1, play.steps / 2)
	play.advance_to(mid)
	var mixed := 0
	for by in range(0, H - 8, 8):
		for bx in range(0, W - 8, 8):
			var new_here := false
			var old_here := false
			for y in range(by, by + 8):
				for x in range(bx, bx + 8):
					if _is_arriving(play.surface, x, y):
						new_here = true
					else:
						old_here = true
			if new_here and old_here:
				mixed += 1
	var blocks := ((H - 8) / 8) * ((W - 8) / 8)
	h.check("nearly every 8x8 window holds both pictures",
		mixed > blocks * 3 / 4, "%d of %d windows" % [mixed, blocks])
	h.check("the departing pixels are still at their own coordinates",
		_origin_intact(play.surface))
	var fraction := _arriving_fraction(play.surface)
	h.check("about half of it has arrived halfway through",
		fraction > 0.25 and fraction < 0.75, "%.2f" % fraction)
	# A wipe at the same point fails the window test, which is what makes the
	# window test worth making.
	var wipe := _play(1, 1, 350)
	wipe.advance_to(maxi(1, wipe.steps / 2))
	var wipe_mixed := 0
	for by in range(0, H - 8, 8):
		for bx in range(0, W - 8, 8):
			var new_here := false
			var old_here := false
			for y in range(by, by + 8):
				for x in range(bx, bx + 8):
					if _is_arriving(wipe.surface, x, y):
						new_here = true
					else:
						old_here = true
			if new_here and old_here:
				wipe_mixed += 1
	h.check("a wipe at the same point mixes at most one column of windows",
		wipe_mixed <= (H - 8) / 8, "%d windows" % wipe_mixed)
	# `random rows` is the same loop with a row-shaped cell, and asserting it
	# separately is what keeps the cell arithmetic from collapsing to one shape.
	var rows := _play(27, 4, 1000)
	rows.advance_to(maxi(1, rows.steps / 2))
	h.check("`random rows` arrives in whole rows",
		_rows_are_uniform(rows.surface))
	h.complete("a dissolve interleaves the two frames rather than sweeping between them")


static func _origin_intact(image: Image) -> bool:
	for y in range(0, H, 5):
		for x in range(0, W, 5):
			if _is_arriving(image, x, y):
				continue
			if _origin(image, x, y) != Vector2i(x, y):
				return false
	return true


## Every row is either wholly arrived or wholly not, which is what distinguishes
## `random rows` from a pixel dissolve.
static func _rows_are_uniform(image: Image) -> bool:
	for y in H:
		var first := _is_arriving(image, 0, y)
		for x in range(1, W):
			if _is_arriving(image, x, y) != first:
				return false
	return true


## Venetian and vertical blinds: twelve bands opening at once, which shows up as
## many alternations down a column where a wipe has exactly one.
func _blinds_are_stripes(h) -> void:
	h.begin("blinds open as bands, strips build as strips")
	var play := _play(37, 4, 1000)
	play.advance_to(maxi(1, play.steps / 2))
	var runs := 0
	var last := _is_arriving(play.surface, W / 2, 0)
	for y in range(1, H):
		var now := _is_arriving(play.surface, W / 2, y)
		if now != last:
			runs += 1
			last = now
	h.check("a venetian blind alternates many times down a column",
		runs >= 6, "%d alternations" % runs)
	var vertical := _play(49, 4, 1000)
	vertical.advance_to(maxi(1, vertical.steps / 2))
	var vruns := 0
	var vlast := _is_arriving(vertical.surface, 0, H / 2)
	for x in range(1, W):
		var now := _is_arriving(vertical.surface, x, H / 2)
		if now != vlast:
			vruns += 1
			vlast = now
	h.check("vertical blinds alternate across a row instead",
		vruns >= 6, "%d alternations" % vruns)
	# The strip builds and the checkerboard share `transMultiPass`; they are held
	# to arriving monotonically, which a rect list computed from the wrong step
	# index does not.
	var falling: Array[int] = []
	for type_code in [38, 39, 41, 43, 45]:
		var strips := _play(type_code, 4, 1000)
		var seen := 0.0
		for step in range(1, strips.steps + 1):
			strips.advance_to(step)
			var now := _arriving_fraction(strips.surface)
			if now < seen - 0.001:
				falling.append(type_code)
				break
			seen = now
	h.check("the strip builds and the checkerboard only ever add",
		falling.is_empty(), str(falling))
	h.complete("blinds open as bands, strips build as strips")


## `area` selects the changed rectangle rather than the whole stage, and the
## reference rounds its size up to even because the centre-out family halves it.
func _change_area_confines_it(h) -> void:
	h.begin("a changed-area transition plays inside the rectangle that changed")
	var departing := _departing()
	var arriving := _departing()
	# One 21x11 island of difference, deliberately odd in both dimensions.
	for y in range(20, 31):
		for x in range(30, 51):
			arriving.set_pixel(x, y, Color8(0, 0, 255, 255))
	var play := Transition.Play.new({
		"transition_type": 1, "chunk_size": 2, "duration_ms": 1000.0,
		"change_area": 1,
	}, Vector2i(W, H), departing, arriving)
	h.check("the clip is the rectangle that changed",
		play.clip.position == Vector2i(30, 20), str(play.clip))
	h.check("its odd size is rounded up to even",
		play.clip.size == Vector2i(22, 12), str(play.clip.size))
	play.advance_to(maxi(1, play.steps / 2))
	h.check("nothing outside the clip is touched",
		_origin(play.surface, 5, 5) == Vector2i(5, 5)
			and _origin(play.surface, W - 5, H - 5) == Vector2i(W - 5, H - 5))
	h.check("something inside it has", _is_arriving(play.surface, 31, 25))
	# A frame that changed nothing is a legitimate authoring case, not an error:
	# `playTransition` aborts on a zero-sized clip rect and the playhead is still
	# held for the duration.
	var still := Transition.Play.new({
		"transition_type": 1, "chunk_size": 2, "duration_ms": 1000.0,
		"change_area": 1,
	}, Vector2i(W, H), departing, _departing())
	h.check("an unchanged frame degrades to a cut rather than dividing by zero",
		still.degraded != "" and still.steps >= 1, still.degraded)
	h.complete("a changed-area transition plays inside the rectangle that changed")


## The wiring: the play is stepped *by* the hold the clock is already running,
## and lands on its last step exactly when the hold releases.
##
## Headless there is no framebuffer to capture the two frames from
## (`preview/snapshot.gd:grab`), so the play degrades to a cut and draws nothing
## -- and it still counts its steps, which is what this case reads. That is the
## honest limit of what a gate can assert here: the arithmetic that decides *when*
## a step happens is covered, the pixels are covered by every case above, and the
## join between them is exercised only on a machine with a screen.
func _steps_inside_the_hold(h) -> void:
	h.begin("the play advances through the hold and lands on its last step")
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	# 1000 ms of `wipe right`, armed the one way a script can arm one. The
	# duration argument is in quarter-seconds -- see `lingo_puppet_transition`.
	preview.lingo_puppet_transition([1, 8, 4, 0])
	preview.call("_begin_transition", {})
	var clock = preview.get("_clock")
	var play = preview.get("_transition_play")
	h.check("arming a puppet transition starts a play", play != null)
	if play == null:
		h.complete("the play advances through the hold and lands on its last step")
		preview.queue_free()
		return
	h.check("the clock is holding for the transition specifically",
		bool(clock.call("holding_transition")), str(clock.call("status")))
	var steps: int = play.steps
	h.check("it has more than one step to take", steps > 1, "%d steps" % steps)
	var midway := -1
	var guard := 0
	# Real awaited frames, never a synthetic tick loop -- `AGENTS.md` "Fixing
	# something", and the reason is that the clock this is measuring runs on them.
	while bool(clock.call("holding_transition")) and guard < 600:
		guard += 1
		await process_frame
		if midway < 0 and int(play.applied) > 0 and int(play.applied) < steps:
			midway = int(play.applied)
	h.check("it was part-way through while the hold was running",
		midway > 0 and midway < steps, "step %d of %d" % [midway, steps])
	h.check("it is on its last step when the hold releases",
		int(play.applied) == steps, "step %d of %d" % [int(play.applied), steps])
	h.check("the hold really did release", guard < 600, "%d frames" % guard)
	h.check("and the play is dropped once it has",
		preview.get("_transition_play") == null)
	preview.queue_free()
	h.complete("the play advances through the hold and lands on its last step")
