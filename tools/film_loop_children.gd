extends SceneTree
## When a film-loop child draws nothing, does the report say **why**?
##
##   godot --headless --audio-driver Dummy --path . --script tools/film_loop_children.gd -- \
##       --root piposh-dream --boot plane1.dir
##
## ## The bug this exists for
##
## `bugs.md` 110: `piposh-dream`'s flyer tallied `{"child drawn": 29, "child has
## no art": 8, "children offered": 37}` in two independent runs, and eight
## children of a film loop drawing nothing reads as eight broken animations. It
## is not one bug at all -- it is one *bucket* holding two unrelated things.
##
## `preview/sprite_art.gd:texture_for` answers null both when a bitmap failed to
## decode, which is a defect, and when the member is a type it is *right* not to
## draw, which is not. All eight of `plane1.dir`'s are the second: film-loop
## children whose member is type 15 with the Xtra symbol `vectorShape`, Director 7
## vector art produced by a native Xtra that this port does not draw and that the
## reference's `castmember/` does not draw either. `tools/xtra_members.gd` states
## the rule -- *drawing nothing for an unregistered Xtra is correct behaviour; not
## knowing what the member is, is not* -- and the second half is what was broken.
##
## So this harness does not assert that eight becomes zero. It asserts that **no
## child is dropped without the report naming the member type that dropped it**,
## which is the thing that was actually missing and the thing that keeps the next
## real decode failure from hiding in the same number.
##
## ## Why there are two sources and not one
##
## The play's tally is the engine's own answer, and a harness that only read that
## would be asking the engine to mark its own work: a `decline_reason` that
## returned `"mystery"` for everything would satisfy "every miss is named". So the
## expected set is derived a second way, **off the cast and without the painter**
## -- every film loop in the movie is opened, every frame's children are resolved
## through the same `child_lib` the painter uses, and each child's member type is
## classified directly. The play then has to agree with a census it did not
## produce.
##
## ## What it looks like with the fix reverted
##
## Remove the `"child not drawn: ..."` tally from
## `preview/film_loop_view.gd:paint_loop` and the third case fails on its first
## check: `named 0 of 8 miss(es)`. The census case still passes, because the
## classifier is what it is measuring.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Ink := preload("res://director/director_ink.gd")

## The tally key `paint_loop` writes the reason under, and the one it has always
## written the bare count under. Spelled once here so a rename shows up as a
## failing harness rather than as a silently empty sum.
const NAMED_PREFIX := "child not drawn: "
const BARE_KEY := "child has no art"
const DREW_KEY := "child drawn"


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	var table = preview.get("_table")
	if h.check("the movie opened a cast table", table != null):
		_classifier_partitions_the_cast(h, table)
		var census := _census(table)
		_census_finds_the_population(h, census)
		_play_names_every_miss(h, preview, census,
			Args.number(args, "frames", 40))
	preview.queue_free()
	quit(h.finish("a film-loop child that draws nothing says which member type it was"))


## Every member of every cast, put through `decline_reason`, and the answer held
## to the rule the function states: empty exactly for the two types this renderer
## draws, and a named type for every other.
##
## Over the movie's own cast rather than a made-up member list, because the
## interesting inputs are the ones a 1997 authoring tool produced -- an Xtra with
## a symbol, a type this table has no name for -- and a synthetic dictionary
## cannot be wrong in those ways.
func _classifier_partitions_the_cast(h, table) -> void:
	var case := "the classifier answers for every member type in the cast"
	h.begin(case)
	var drawable := 0
	var declined := 0
	var wrong_side: Array[String] = []
	var unnamed: Array[String] = []
	var kinds: Dictionary = {}
	for lib_key in table.cast_libs.keys():
		var lib := int(lib_key)
		var cast = table.cast_for(lib)
		if cast == null:
			continue
		for number in cast.member_numbers():
			var id := int(number)
			var m: Dictionary = table.get_member(lib, id)
			if m.is_empty():
				continue
			var type_code := int(m.get("type", 0))
			var reason: String = SpriteArt.decline_reason(
				{"cast_lib": lib, "cast_id": id}, table)
			var draws := type_code == Ink.TYPE_BITMAP or type_code == Ink.TYPE_SHAPE
			if draws:
				drawable += 1
				if reason != "":
					wrong_side.append("%d:%d %s" % [lib, id, reason])
			else:
				declined += 1
				if reason == "":
					wrong_side.append("%d:%d type %d declined nothing" % [lib, id, type_code])
					continue
				# The reason has to carry the member's own word for its type, or it
				# is not telling anybody anything they could act on.
				if not reason.contains(str(m.get("type_name", "type%d" % type_code))):
					unnamed.append("%d:%d -> %s" % [lib, id, reason])
				kinds[reason] = int(kinds.get(reason, 0)) + 1
	h.check("the cast holds members this renderer draws", drawable > 0, str(drawable))
	h.check("and members it does not", declined > 0, str(declined))
	h.check("no member is on the wrong side of the rule",
		wrong_side.is_empty(), str(wrong_side.slice(0, 6)))
	h.check("every declined member is named by its own type",
		unnamed.is_empty(), str(unnamed.slice(0, 6)))
	h.check("the reasons the cast produces", true, str(kinds))
	# A member number nothing holds is the other arm, and it has to be told apart
	# from a type with no renderer: one is a broken reference, the other is not.
	var absent: String = SpriteArt.decline_reason(
		{"cast_lib": 1, "cast_id": 999999}, table)
	h.check("a member that is not in the cast says so",
		absent.contains("not in the cast"), absent)
	h.complete(case)


## Every film-loop child in the movie, classified off the cast. `reason -> count`.
##
## This is the painter's own resolution rule with the painting removed: the same
## `child_lib`, the same `child_sprite`, the same `decline_reason`. What it is not
## is the painter -- nothing here opens a texture cache or reaches the stage, so
## when the play agrees with it the agreement is between two derivations rather
## than between a number and itself.
##
## Nested loops are skipped rather than descended: `paint_loop` recurses into a
## type-2 child instead of asking for artwork, so a nested loop never reaches the
## miss tally at all and counting it here would predict a miss that cannot happen.
func _census(table) -> Dictionary:
	var out: Dictionary = {}
	for lib_key in table.cast_libs.keys():
		var lib := int(lib_key)
		var cast = table.cast_for(lib)
		if cast == null:
			continue
		for number in cast.member_numbers():
			var m: Dictionary = table.get_member(lib, int(number))
			if int(m.get("type", 0)) != 2:
				continue
			var loop = FilmLoopView.open_loop(lib, m, table)
			if loop == null:
				continue
			for index in range(maxi(0, int(loop.frame_count))):
				for child in loop.children(index):
					var kid_lib := FilmLoopView.child_lib(child, lib, table)
					if kid_lib < 0:
						continue
					var cm: Dictionary = table.get_member(kid_lib, int(child["cast_id"]))
					if int(cm.get("type", 0)) == 2:
						continue
					var record := FilmLoopView.child_sprite(child, kid_lib, cm)
					var reason: String = SpriteArt.decline_reason(record, table)
					if reason == "":
						continue
					out[reason] = int(out.get(reason, 0)) + 1
	return out


func _census_finds_the_population(h, census: Dictionary) -> void:
	var case := "the cast says which film-loop children can never draw"
	h.begin(case)
	var total := 0
	for reason in census:
		total += int(census[reason])
	h.check("the census ran and can be read", true,
		"%d undrawable child record(s): %s" % [total, str(census)])
	h.complete(case)


## Paint the frames that actually hold a film loop, and hold the tally to the
## census.
##
## **Driven by the playhead rather than by letting the movie run**, and that is
## the difference between a harness and a hope: `plane1.dir` boots on a menu and
## its flyer is several inputs deep, so 900 awaited ticks of it paint no film loop
## at all -- measured, `_loop_stats` came back `{}` -- and a case that read that
## would have asserted nothing while looking like it had. `bugs.md` 110's own
## repro drives it with `--keys`, which is a sequence of presses that has to keep
## working.
##
## So the frames are chosen from the score: every frame that places a type-2
## member, up to `frames`, painted directly. `_ticks` is stepped between paints
## because a loop's own frame index is `ticks - loop_start[channel]` -- without
## that every paint shows the loop's first frame and only the children on it, and
## `plane1.dir`'s longest loop is 106 frames.
func _play_names_every_miss(h, preview: Node, census: Dictionary,
		frames: int) -> void:
	var case := "every child the play dropped is named by its member type"
	h.begin(case)
	var score = preview.get("_score")
	var table = preview.get("_table")
	var found: Array[int] = []
	if score != null:
		for index in range(int(score.frame_count)):
			for sprite in score.frame(index).get("sprites", []):
				var m: Dictionary = table.get_member(
					int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0)))
				if int(m.get("type", 0)) == 2:
					found.append(index)
					break
	# Spread across the movie rather than the first `frames` of them, which is not
	# tidiness: a Director movie places its loops in runs, so the first forty
	# consecutive hits are usually forty paints of *one* loop and the sample says
	# nothing about the other fourteen.
	var holds_a_loop: Array[int] = []
	var stride := maxi(1, found.size() / maxi(1, frames))
	for at in range(0, found.size(), stride):
		holds_a_loop.append(found[at])
	h.check("the score places a film loop somewhere", not holds_a_loop.is_empty(),
		"%d frame(s) of %d that place one" % [holds_a_loop.size(), found.size()])
	var tick := 0
	for index in holds_a_loop:
		preview.set("_index", index)
		# Enough steps to walk a long loop past its first frame without walking
		# every frame of every loop in the movie, which is minutes.
		for step in 12:
			tick += 9
			preview.set("_ticks", tick)
			preview.call("repaint_now")
	var stats: Dictionary = preview.get("_loop_stats")
	if stats == null:
		stats = {}
	var drew := int(stats.get(DREW_KEY, 0))
	var missed := int(stats.get(BARE_KEY, 0))
	var named := 0
	var reasons: Dictionary = {}
	for key in stats:
		var text := str(key)
		if not text.begins_with(NAMED_PREFIX):
			continue
		var reason := text.substr(NAMED_PREFIX.length())
		reasons[reason] = int(stats[key])
		named += int(stats[key])
	h.check("the film-loop painter ran over %d frame(s) that place one"
		% holds_a_loop.size(), drew > 0 or missed > 0, str(stats))
	if drew == 0 and missed == 0:
		# The honest empty answer, stated rather than passed over: this movie
		# painted no film loop in the window, so there is nothing here to hold to
		# the census and the case says so instead of asserting over nothing.
		h.complete(case)
		return
	h.check("every miss is named", named == missed,
		"named %d of %d miss(es): %s" % [named, missed, str(reasons)])
	# And the names have to be names the *cast* also produces. A reason the census
	# never saw means the painter is classifying a child the cast says is
	# something else -- which is the resolution bug this would otherwise hide.
	var unexpected: Array[String] = []
	for reason in reasons:
		if not census.has(reason):
			unexpected.append(str(reason))
	h.check("and every name the play gave is one the cast predicts",
		unexpected.is_empty(), "%s not in %s" % [str(unexpected), str(census.keys())])
	# The finding of `bugs.md` 110 itself, asserted rather than described: on a
	# movie whose census predicts only undrawable *types*, no miss may be a decode
	# failure. If one ever is, this goes red and it is a real bug rather than this
	# one coming back.
	var decode_failures := int(reasons.get("artwork did not decode", 0))
	h.check("no miss is a decode failure that lost its own message",
		decode_failures == 0 or census.has("artwork did not decode"),
		"%d" % decode_failures)
	h.complete(case)
