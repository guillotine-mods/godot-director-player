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
const StagePaint := preload("res://scenes/preview/stage_paint.gd")

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
	await _crop_follows_the_stretch(h)
	await _steps_inside_the_hold(h)
	await _composites_a_real_movie(h)
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


## ## The crop `_grab_stage` takes is in render-target pixels
##
## `bugs.md` 117, headless. The case below this one (`_two_backends_agree`) is
## the end-to-end statement of the same thing and it can only run on a machine
## with a screen, which meant the defect went unguarded for as long as it
## existed: the gate is headless, headless reads the offscreen surface, and the
## framebuffer arm was never asked anything.
##
## This asks it the one question a machine with no framebuffer can still answer,
## because it is a question about **transforms rather than pixels**. Godot's
## `canvas_items` stretch splits the two apart: the render target is the window,
## the 2D coordinate space is the content-scale size, and the viewport carries a
## stretch transform between them that `get_global_transform_with_canvas()` does
## not include. A `SubViewport` with `size_2d_override_stretch` reproduces that
## split exactly and costs nothing to render, so the arithmetic can be driven at
## the real numbers on any display server.
##
## **The numbers are the ones the entry was measured at** — a 2880x1690 window
## whose 2D space is 1280x751, a 640x480 stage letterboxed into it at
## `1.564583` from `(139, 0)`. With the fix reverted the answer is
## `(139, 0, 1001, 751)`, the top-left ninth of a 2880x1690 image; with it,
## `(312, 0, 2252, 1690)`, which is the letterboxed stage edge to edge. Two
## pixels of slack, and they are for one named thing rather than for comfort:
## `Node2D.scale` is float32, so `1001.33 x 2.25` comes back `2252.99` and
## truncates one short of the exact 2253.
##
## The second half is the control that keeps the first from being a licence to
## multiply by anything: with no stretch the region must be **unchanged**, which
## is what makes this safe for headless, for a window at the base resolution and
## for `stretch/mode="disabled"`.
func _crop_follows_the_stretch(h) -> void:
	h.begin("the framebuffer crop is taken in the space the frame was rendered in")
	# The window, and the 2D space Godot leaves the canvas in underneath it.
	var target := Vector2i(2880, 1690)
	var canvas := Vector2i(1280, 751)
	var stretched := _stretched_viewport(target, canvas)
	var flat := _stretched_viewport(canvas, Vector2i.ZERO)
	root.add_child(stretched)
	root.add_child(flat)
	await process_frame
	# Placed the way `director_preview.gd:_fit_to_window` places the stage: the
	# largest whole-aspect fit, floored to a whole pixel. Computed rather than
	# quoted so that a change to that rule shows up here as a moved rectangle
	# instead of as a passing test of a stale constant.
	var stage := Vector2i(640, 480)
	var factor := minf(float(canvas.x) / stage.x, float(canvas.y) / stage.y)
	var node := _placed_node(factor,
		((Vector2(canvas) - Vector2(stage) * factor) * 0.5).floor())
	stretched.add_child(node)
	var flat_node := _placed_node(factor, node.position)
	flat.add_child(flat_node)
	await process_frame
	var local := Rect2(Vector2.ZERO, Vector2(stage))
	h.check("the viewport's stretch is the ratio of the two, and is not identity",
		stretched.get_final_transform().get_scale().is_equal_approx(
			Vector2(float(target.x) / canvas.x, float(target.y) / canvas.y)),
		str(stretched.get_final_transform()))
	# What the node alone says, which is what the arm used to crop with. Kept in
	# the failure message so a red says *which* of the two spaces it landed in
	# rather than only that it is wrong.
	var canvas_only := StagePaint.render_target_region(
		node.get_global_transform_with_canvas() * local, Transform2D(), target)
	var region := StagePaint.framebuffer_region(node, local, target)
	h.check("the crop is the letterboxed stage in render-target pixels",
		_rect_near(region, Rect2i(312, 0, 2253, 1690), 2),
		"%s (the node's own transform alone answers %s)" % [region, canvas_only])
	h.check("so it spans the full height of the render target, which is the axis"
		+ " the letterbox does not pad",
		absi(region.size.y - target.y) <= 2, "%d of %d" % [region.size.y, target.y])
	h.check("and the pre-fix answer really is the wrong picture, not a rounding"
		+ " difference", not _rect_near(canvas_only, region, 8), str(canvas_only))
	h.check("with no stretch the region is the node's own rectangle, unchanged",
		StagePaint.framebuffer_region(flat_node, local, canvas) == canvas_only,
		"%s vs %s" % [StagePaint.framebuffer_region(flat_node, local, canvas),
			canvas_only])
	stretched.queue_free()
	flat.queue_free()
	h.complete("the framebuffer crop is taken in the space the frame was rendered in")


## A viewport whose render target and 2D space differ, which is what
## `window/stretch/mode="canvas_items"` does to the root one. `override` of zero
## means no split at all, for the control.
func _stretched_viewport(size: Vector2i, override: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	# Nothing is drawn into it -- every assertion is about transforms -- and a
	# render target that never updates is what makes this free on a real GPU as
	# well as on the dummy one.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if override != Vector2i.ZERO:
		viewport.size_2d_override = override
		viewport.size_2d_override_stretch = true
	return viewport


func _placed_node(factor: float, at: Vector2) -> Node2D:
	var node := Node2D.new()
	node.position = at
	node.scale = Vector2(factor, factor)
	return node


func _rect_near(a: Rect2i, b: Rect2i, slack: int) -> bool:
	return absi(a.position.x - b.position.x) <= slack \
		and absi(a.position.y - b.position.y) <= slack \
		and absi(a.size.x - b.size.x) <= slack \
		and absi(a.size.y - b.size.y) <= slack


## The wiring: the play is stepped *by* the hold the clock is already running,
## and lands on its last step exactly when the hold releases.
##
## This used to be the *only* case that booted the player, and it had to say that
## headless there was no framebuffer to capture the two frames from, so the play
## degraded to a cut and only its step arithmetic could be read. That is no longer
## true -- `director_preview.gd:paint_capture` composes the frame on the CPU
## through the same four primitives -- and the two cases below are what the gate
## can assert now that it is not.
func _steps_inside_the_hold(h) -> void:
	h.begin("the play advances through the hold and lands on its last step")
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	# A gate run is always headless, where the surface arms itself. Run by hand on
	# a machine with a screen it does not -- a build with a framebuffer reads that
	# instead and composing a second copy of every frame on the CPU for it would be
	# pure cost -- so the cases below force it on rather than asserting differently
	# on the two, which is how a harness ends up measuring the display server.
	_arm_surface(preview)
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
	# **The join, and the check that fails outright with `paint_capture` removed.**
	# This is the movie's own arming path -- `puppetTransition` through
	# `_begin_transition` through the clock -- and before there was an offscreen
	# surface it produced a play with no frames in it on every headless run. That
	# is what "the port has never composited a real frame" meant, and it is one
	# boolean.
	h.check("the play has both frames of the real movie rather than degrading to a cut",
		str(play.degraded) == "", str(play.degraded))
	# Both frames are the movie's pixels rather than a blank stage. Deliberately
	# *not* "the two differ": a `puppetTransition` armed here is armed on a
	# standing playhead, so the departing and arriving frames are two paints of
	# the same frame and are equal by construction. The real-movie case below is
	# the one that composes two different frames.
	h.check("and both of them are the movie's own pixels",
		play.before != null and play.after != null
			and not _uniform(play.before, Rect2i(Vector2i.ZERO, play.before.get_size())),
		"%s" % (str(play.before.get_size()) if play.before != null else "null"))
	var midway := -1
	var guard := 0
	# **`stage_paint.gd:draw_transition` asserted from the outside.** The play
	# holding a composite and the composite being on the stage are two different
	# claims, and only the second is what a player sees. Sampled once, part-way
	# through, by forcing a paint and comparing the offscreen surface against the
	# play's own -- `draw_transition` blits it 1:1 over the movie's rect, so the
	# two are equal wherever nothing is drawn on top.
	#
	# The band excludes the SKIP button (y 8..30) and the HUD line (the last 30
	# rows), which `draw_overlays` paints *after* the composite and which exist for
	# us rather than for the movie.
	var on_stage := false
	var stage_note := "never sampled"
	var band := Rect2i(0, 40, W, H)
	var stage: Vector2i = preview.call("stage_size")
	if stage.y > 80:
		band = Rect2i(0, 40, stage.x, stage.y - 70)
	# Real awaited frames, never a synthetic tick loop -- `AGENTS.md` "Fixing
	# something", and the reason is that the clock this is measuring runs on them.
	while bool(clock.call("holding_transition")) and guard < 600:
		guard += 1
		await process_frame
		if midway < 0 and int(play.applied) > 0 and int(play.applied) < steps:
			midway = int(play.applied)
			preview.call("repaint_now")
			var surface = preview.get("paint_capture")
			if surface == null:
				stage_note = "no offscreen surface to read the stage back from"
			else:
				on_stage = _same_region(surface.snapshot(), play.surface, band)
				stage_note = "step %d of %d over %s" % [midway, steps, str(band)]
	h.check("it was part-way through while the hold was running",
		midway > 0 and midway < steps, "step %d of %d" % [midway, steps])
	h.check("the composite the play holds also reached the stage",
		on_stage, stage_note)
	h.check("it is on its last step when the hold releases",
		int(play.applied) == steps, "step %d of %d" % [int(play.applied), steps])
	h.check("the hold really did release", guard < 600, "%d frames" % guard)
	h.check("and the play is dropped once it has",
		preview.get("_transition_play") == null)
	# Here rather than in the real-movie case because this one runs on every
	# entry: the case below returns early on a movie that declares no score
	# transition, and this question is about the painter rather than about
	# transitions at all.
	_two_backends_agree(h, preview)
	preview.queue_free()
	h.complete("the play advances through the hold and lands on its last step")


# ---------------------------------------------------------------------------
# Real frames of a real movie
#
# Everything above this line runs on two images this file made up. That covered
# the algorithms and covered them well, and it could not say one thing: that the
# compositor is ever handed two frames of an actual Director movie. It was not --
# `_grab_stage` read the framebuffer, headless Godot has none, and so every gate
# run since the drawing landed created the play, held the playhead for its
# duration and drew a cut. The cases below are the join, and they fail with
# `paint_capture` removed for exactly that reason: `Play.degraded` comes back
# `"no frames to compose"` and there is nothing to assert against.
# ---------------------------------------------------------------------------


## Which picture a pixel came from. **The whole method of the synthetic cases,
## carried onto frames nobody authored for the purpose.**
##
## Those frames encoded their own coordinates, so `_origin` could say "this pixel
## came from there". A real movie's frames encode nothing, and the two of them
## agree over most of the stage -- a transition usually changes part of a picture.
## So a pixel is only evidence where the two endpoints *differ*, and there it is
## conclusive: the composite either holds the departing value or the arriving one.
##
##   1  the arriving frame
##  -1  the departing frame
##   0  the two frames agree here, so this pixel says nothing
##   2  neither -- a colour no endpoint holds, which is a blend or a resample and
##      is a failure, because a Director transition only ever chooses between two
##      pictures (`transitions.cpp`; nothing in the table interpolates)
static func _source_at(surface: Image, departing: Image, arriving: Image,
		x: int, y: int) -> int:
	var was := departing.get_pixel(x, y)
	var now := arriving.get_pixel(x, y)
	if was == now:
		return 0
	var here := surface.get_pixel(x, y)
	if here == now:
		return 1
	if here == was:
		return -1
	return 2


## `{decided, arrived, alien}` over a grid inside `area`, at `step` pixels.
##
## Subsampled rather than exhaustive: a 640x480 stage is 307,200 `get_pixel`
## calls per sample point and this case takes several per transition, which is
## minutes rather than seconds. Every count below is therefore a count of samples
## and the checks are written as proportions of `decided`.
static func _census(surface: Image, departing: Image, arriving: Image,
		area: Rect2i, step: int = 3) -> Dictionary:
	var decided := 0
	var arrived := 0
	var alien := 0
	var y := area.position.y
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			match _source_at(surface, departing, arriving, x, y):
				1:
					decided += 1
					arrived += 1
				-1:
					decided += 1
				2:
					decided += 1
					alien += 1
			x += step
		y += step
	return {"decided": decided, "arrived": arrived, "alien": alien}


## How many 8x8 windows hold both pictures at once, over windows that have enough
## discriminating pixels to answer. The dissolve family's own signature, and the
## one every sweeping algorithm fails away from its moving boundary.
static func _mixed_windows(surface: Image, departing: Image, arriving: Image,
		area: Rect2i, cap: int = 240) -> Dictionary:
	var mixed := 0
	var usable := 0
	var y := area.position.y
	while y + 8 <= area.end.y and usable < cap:
		var x := area.position.x
		while x + 8 <= area.end.x and usable < cap:
			var old_here := false
			var new_here := false
			var decided := 0
			for dy in 8:
				for dx in 8:
					match _source_at(surface, departing, arriving, x + dx, y + dy):
						1:
							new_here = true
							decided += 1
						-1:
							old_here = true
							decided += 1
			# A window the two frames agree across cannot say anything about
			# scatter, and counting it either way is how this test stops
			# discriminating. Eight of sixty-four is the floor: two consecutive
			# frames of a real movie agree over most of the stage, so a higher one
			# throws away the windows that carry the answer.
			if decided >= 8:
				usable += 1
				if old_here and new_here:
					mixed += 1
			x += 8
		y += 8
	return {"mixed": mixed, "usable": usable}


static func _uniform(image: Image, area: Rect2i) -> bool:
	if image == null:
		return true
	var first := image.get_pixel(area.position.x, area.position.y)
	var y := area.position.y
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			if image.get_pixel(x, y) != first:
				return false
			x += 7
		y += 7
	return true


## The one this whole change exists for: the movie's own transition record, the
## movie's own two frames, and the composite asserted in the direction the type
## specifies.
##
## **Driven by arming the frame's own transition rather than by waiting for the
## score to reach it**, which is deterministic and uses no less of the real
## thing: `_begin_transition` is the engine's own entry point, the record comes
## out of the score, and the two frames are two real paints of two real frames of
## the movie. Waiting instead would make the case a race against a 2,000 ms hold
## and would assert the same pixels.
##
## `EGOZROO1.dir` is the richest site in the corpus -- five transitions at 2,000 ms
## each, types 26, 28, 25, 51 and 24 -- and every one of the twelve types the six
## shipped roots play is in the dissolve family, so the dissolve signature is what
## a real frame can be held to. The wipe run at the bottom of the case is the
## control that keeps that from being a tautology: the *same two real frames*,
## composed by a sweeping algorithm, must fail the window test the dissolve passes.
func _composites_a_real_movie(h) -> void:
	var case := "a real movie's own transition composites its own two frames"
	h.begin(case)
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	_arm_surface(preview)
	var score = preview.get("_score")
	if not h.check("the movie loaded a score", score != null
			and int(score.frame_count) > 1,
			"%d frame(s)" % (int(score.frame_count) if score != null else -1)):
		h.complete(case)
		preview.queue_free()
		return
	h.check("the painter armed an offscreen surface",
		preview.get("paint_capture") != null,
		"display server %s" % DisplayServer.get_name())

	# Every frame of this movie that names a transition member. Collected rather
	# than assumed so the case says out loud when it is pointed at a movie with
	# none, instead of asserting nothing and passing.
	var armed: Array[int] = []
	for index in range(1, int(score.frame_count)):
		if int(score.frame(index).get("transition_member", 0)) > 0:
			armed.append(index)
	if armed.is_empty():
		# **Said out loud and asserted over, rather than failed.** Not every movie
		# has a score transition -- `GATE_ROOT`'s own boot movie, `strtgame.dir`,
		# has 0 across 1,375 frames, and its two transition members are reached
		# some other way. Failing here would be `gate.sh`'s own "asserting against
		# an absent fixture" mistake, which turns a data gap into a red. The
		# entry that carries this case is the one that names `rating`; the puppet
		# case above already asserted the composite on whatever movie this is.
		h.check("this movie declares no score transition, so there is nothing here"
			+ " to compose (the `rating` entry is the one that does)",
			true, "0 of %d frame(s)" % int(score.frame_count))
		h.complete(case)
		preview.queue_free()
		return
	h.check("the movie declares at least one transition", true,
		"%d frame(s) of %d" % [armed.size(), int(score.frame_count)])

	# Every candidate is armed and the **widest** one kept, which is not a
	# convenience. Every transition member in the corpus carries flags byte 2, so
	# `area = !(flags & 1)` is 1 and the play is confined to the rectangle that
	# changed -- and most of these frames change a caption or a button, so the
	# first candidate on `EGOZROO1.dir` composes over an 8x10 clip. That is a
	# correct transition and it is four discriminating pixels, which is not enough
	# to tell a dissolve from a wipe. The distribution is printed either way, so a
	# movie whose transitions are all small says so rather than looking thin.
	#
	# A transition over a frame that changed nothing degrades to a cut by the
	# reference's own rule (`_change_area_confines_it`) and is not a failure.
	var play = null
	var chosen := -1
	var clips: Array[String] = []
	for index in armed:
		preview.set("_index", maxi(0, index - 1))
		preview.call("repaint_now")
		preview.set("_index", index)
		preview.call("_begin_transition", score.frame(index))
		var candidate = preview.get("_transition_play")
		if candidate == null or str(candidate.degraded) != "" or candidate.steps < 2:
			clips.append("f%d cut" % index)
			continue
		var box: Rect2i = candidate.clip
		clips.append("f%d t%d %dx%d" % [index, int(candidate.type), box.size.x, box.size.y])
		if play == null or box.size.x * box.size.y > int(play.clip.size.x) * int(play.clip.size.y):
			play = candidate
			chosen = index
	if not h.check("one of them composes two frames that differ",
			play != null, "%d candidate frame(s): %s" % [armed.size(), str(clips)]):
		h.complete(case)
		preview.queue_free()
		return

	var departing: Image = play.before
	var arriving: Image = play.after
	var area: Rect2i = play.clip
	h.check("frame %d armed type %d over %d step(s)" % [
		chosen, int(play.type), int(play.steps)], true,
		"%.0f ms, chunk %d, clip %s" % [play.duration, int(play.chunk_size), str(area)])
	# Anti-vacuity, and it is the assertion that fails with `paint_capture`
	# reverted rather than merely reading differently: with no offscreen surface
	# both frames are null, the play degrades and the case has already returned
	# above. With the surface but a painter that drew nothing into it, both frames
	# are the opaque black `Surface.begin` fills with, and these two checks are
	# what catch that.
	h.check("the departing frame is a picture and not a blank stage",
		not _uniform(departing, area))
	h.check("the arriving frame is a picture too", not _uniform(arriving, area))
	# A proportion of the clip rather than a flat count, because the clip is the
	# rectangle the movie changed and the movie decides how big that is. Flat was
	# wrong: `EGOZROO1.dir`'s widest is 640x108 and its narrowest is 8x10, and a
	# threshold that suits one is either unmeetable or vacuous on the other.
	var sampled := int(ceilf(area.size.x / 3.0)) * int(ceilf(area.size.y / 3.0))
	var start := _census(departing, departing, arriving, area)
	# Absolute and proportional, and the absolute one is what carries it: two
	# consecutive frames of a real movie share most of their picture -- 2,819 of
	# 32,604 samples on `EGOZROO1.dir` frame 227, which is 8.6% and is thousands
	# of pixels. A quarter-of-the-clip threshold read as a failure on a frame that
	# is perfectly readable.
	h.check("the two frames disagree over enough of the clip to read",
		int(start["decided"]) > 200 and int(start["decided"]) * 50 > sampled,
		"%d of %d sample(s)" % [int(start["decided"]), sampled])

	var stage: Vector2i = preview.call("stage_size")
	var spec := {
		"transition_type": int(play.type), "chunk_size": int(play.chunk_size),
		"duration_ms": play.duration, "change_area": 1 if play.area else 0,
	}
	h.check("step 0 is the departing frame exactly",
		_same(play.surface, departing))
	var mid := maxi(1, int(play.steps) / 2)
	play.advance_to(mid)
	var half := _census(play.surface, departing, arriving, area)
	h.check("halfway, no pixel holds a colour neither frame holds",
		int(half["alien"]) == 0, "%d of %d" % [int(half["alien"]), int(half["decided"])])
	var fraction := float(half["arrived"]) / maxf(1.0, float(half["decided"]))
	h.check("halfway, both pictures are on the stage",
		fraction > 0.15 and fraction < 0.85, "%.2f arrived" % fraction)
	# The direction assertion, on this play, before any step index is passed. Both
	# controls below get their **own** play for the same reason: `advance_to` is
	# incremental -- the dissolve families walk a shift register forward and
	# cannot be rewound -- so asking one play for step 32 after step 64 answers
	# with step 64 and the case silently measures the arriving frame. That mistake
	# reported `0 of 240 windows` for a dissolve that scatters perfectly.
	var scatter := _mixed_windows(play.surface, departing, arriving, area)
	h.check("the dissolve scatters both pictures through most 8x8 windows",
		int(scatter["usable"]) > 8
			and int(scatter["mixed"]) * 2 > int(scatter["usable"]),
		"%d of %d window(s)" % [int(scatter["mixed"]), int(scatter["usable"])])
	# The control that stops the line above from being a tautology: the **same two
	# real frames**, composed by a sweeping algorithm instead, must fail the test
	# the dissolve passes.
	var wipe := Transition.Play.new({
		"transition_type": 1, "chunk_size": int(play.chunk_size),
		"duration_ms": play.duration, "change_area": 1 if play.area else 0,
	}, stage, departing, arriving)
	wipe.advance_to(maxi(1, wipe.steps / 2))
	var swept := _mixed_windows(wipe.surface, departing, arriving, area)
	h.check("a wipe over the same two frames does not",
		int(swept["mixed"]) * 4 < int(swept["usable"]) or int(swept["usable"]) < 8,
		"%d of %d window(s)" % [int(swept["mixed"]), int(swept["usable"])])

	# Monotone, on its own play walked one step at a time from the beginning.
	var rise = Transition.Play.new(spec, stage, departing, arriving)
	var falling := -1
	var seen := 0.0
	for step in range(1, int(rise.steps) + 1):
		rise.advance_to(step)
		var now := float(_census(rise.surface, departing, arriving, area, 9)["arrived"])
		if now < seen - 0.5:
			falling = step
			break
		seen = now
	h.check("it only ever adds arriving pixels", falling < 0, "fell at step %d" % falling)
	h.check("the last step is the arriving frame exactly",
		_same(rise.surface, arriving))
	preview.set("_transition_play", null)
	preview.queue_free()
	h.complete(case)


## The one thing a gate run cannot ask: does the offscreen surface hold what the
## screen holds?
##
## The surface is not a second painter -- it is a second backend of the same four
## primitives, fed the same arguments in the same order by the same `_paint` -- so
## the only place the two can disagree is inside `director_paint.gd`, and two are
## known and counted there. But "cannot disagree by construction" is the argument
## `AGENTS.md` says to distrust, so the comparison is written down and run where
## it can be.
##
## **Headless it says so and asserts nothing**, which is the shape `gate.sh`
## records as the one that stayed green when a corpus was missing: asserting
## against an absent framebuffer is how a data gap becomes a red. Run the harness
## without `--headless` on a machine with a screen to get the number.
## Arm the offscreen surface whatever the display server is.
static func _arm_surface(preview: Node) -> void:
	preview.call("force_paint_capture", true)
	preview.call("repaint_now")


## ## This was red on a desktop run, and the red was `bugs.md` 117
##
## It compares blurred rather than exact, because the framebuffer arm crops the
## letterboxed viewport and resizes it back to Director's pixels with
## `INTERPOLATE_NEAREST` at whatever non-integral scale the window is -- so
## "differs exactly" is the expected answer for any detailed artwork and always
## was. Blurring both to a 64x48 thumbnail throws that away and keeps the question
## worth asking: are these the same picture, laid out the same way?
##
## **They were not**, and this is the measurement either side of the fix, both on
## 4.7.1 on Windows against `rating`'s `EGOZROO1.dir` frame 227, window 2880x1690,
## stage 640x480, by hand without `--headless`:
##
##   before  mean channel drift **106.9/255** blurred, 67,027 of 76,800 samples
##           differ exactly -- the offscreen surface held the whole frame (room,
##           television, three lines of Hebrew, the HUD) and the framebuffer answer
##           was the **top-left corner of the stage with the letterbox still in
##           it**, magnified to fill 640x480
##   after   mean channel drift **0.2/255**, 585 of 76,800 -- which is the
##           `INTERPOLATE_NEAREST` downscale and the 3 approximated text
##           primitives, i.e. the residue this case was always going to have
##
## The cause was one missing transform and not the arithmetic around it.
## `get_global_transform_with_canvas()` answers `scale 1.5646, origin (139, 0)`,
## and that rectangle is *correct in the viewport's 2D space*, which
## `window/stretch/mode="canvas_items"` leaves at 1280x751 while the render target
## `get_image()` returns is the 2880x1690 window. The stretch between them --
## `2880/1280 = 2.25`, `1690/751 = 2.250333` -- lives on the viewport as
## `get_final_transform()` and was not in the crop.
## `preview/stage_paint.gd:framebuffer_region` carries the full account, and
## `_crop_follows_the_stretch` above is the headless guard: this case needs a
## screen, so for as long as it was the only one asking, the gate could not see
## the defect at all.
##
## Still: do not "fix" a future red here by loosening the threshold.
static func _two_backends_agree(h, preview: Node) -> void:
	if DisplayServer.get_name() == "headless":
		h.check("the two paint backends can only be compared with a screen"
			+ " (run without --headless for the number)", true,
			"display server headless")
		return
	preview.call("force_paint_capture", true)
	preview.call("repaint_now")
	var surface = preview.get("paint_capture")
	if surface == null:
		h.check("forcing the surface on with a screen armed one", false)
		return
	var offscreen: Image = surface.snapshot()
	var approximated := int(surface.approximated)
	# And the framebuffer, through the path a build with a screen actually uses.
	preview.call("force_paint_capture", false)
	preview.call("repaint_now")
	var framebuffer: Image = preview.call("_grab_stage")
	if framebuffer == null or framebuffer.get_size() != offscreen.get_size():
		h.check("the framebuffer path answered at the same size", false,
			"%s vs %s" % [
				str(framebuffer.get_size()) if framebuffer != null else "null",
				str(offscreen.get_size())])
		preview.call("force_paint_capture", true)
		return
	var size := offscreen.get_size()
	var differing := 0
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			if offscreen.get_pixel(x, y) != framebuffer.get_pixel(x, y):
				differing += 1
	var samples := int(ceilf(size.x / 2.0)) * int(ceilf(size.y / 2.0))
	# Compared **blurred down**, for the reason in the docstring: an exact
	# comparison is a measurement of the framebuffer arm's nearest-neighbour
	# downscale and not of either painter. Averaging both to a 64x48 thumbnail
	# throws that away and keeps what the assertion is actually about -- that the
	# two are the same picture, laid out the same way, in the same colours.
	var a_small := Image.create_from_data(size.x, size.y, false,
		Image.FORMAT_RGBA8, offscreen.get_data())
	var b_small := Image.create_from_data(size.x, size.y, false,
		Image.FORMAT_RGBA8, framebuffer.get_data())
	a_small.resize(64, 48, Image.INTERPOLATE_BILINEAR)
	b_small.resize(64, 48, Image.INTERPOLATE_BILINEAR)
	var drift := 0.0
	for y in 48:
		for x in 64:
			var a := a_small.get_pixel(x, y)
			var b := b_small.get_pixel(x, y)
			drift += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := drift * 255.0 / (64.0 * 48.0 * 3.0)
	h.check("the offscreen surface and the framebuffer are the same picture"
		+ " (red here means `_grab_stage`'s framebuffer arm, not the surface"
		+ " -- read this case's docstring before touching anything)",
		mean < 24.0, "mean channel drift %.1f/255 blurred to 64x48"
			% mean
			+ ", %d of %d sample(s) differ exactly" % [differing, samples]
			+ ", %d approximated primitive(s)" % approximated)
	preview.call("force_paint_capture", true)


## Do two whole images agree over one rectangle? Row by row as byte ranges, which
## is one native comparison per row rather than a `get_pixel` per pixel.
static func _same_region(a: Image, b: Image, area: Rect2i) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	var width := a.get_width()
	var pa := a.get_data()
	var pb := b.get_data()
	var left := area.position.x * 4
	var right := area.end.x * 4
	for y in range(area.position.y, area.end.y):
		var row := y * width * 4
		if pa.slice(row + left, row + right) != pb.slice(row + left, row + right):
			return false
	return true
