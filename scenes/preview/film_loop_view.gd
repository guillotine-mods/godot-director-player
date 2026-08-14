extends RefCounted
## Film loops: a mini-score inside a cast member, drawn as one sprite.
##
## A loop occupies a single channel on the stage and layers where the score put
## it, but inside itself it has its own channels, its own frames and its own
## clock. Children stack among themselves by their mini-score channel, and a child
## may itself be a film loop -- `paint_loop` is the recursion, and its docstring
## carries which frame a nested loop is shown at and why.
##
## Nearly all of this module is placement arithmetic, and that is the part worth
## isolating, because getting it wrong does not fail -- it draws the animation
## somewhere plausible and slightly wrong. `place_child` documents the two
## subtractions and what forgetting either one looks like on screen.
##
## `draw` takes the preview node as `host` and calls back into it for artwork and
## painting. That inversion is deliberate rather than lazy: the texture cache and
## the canvas belong to the node, and a loop's children go through exactly the
## same decode and blit path as any other sprite. Duplicating that path here is
## what would let a child drift out of step with the stage.

const Ink := preload("res://director/director_ink.gd")
const FilmLoop := preload("res://director/director_film_loop.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")


## The movie's cast-library number for a child's named cast, or the loop's own.
static func child_lib(child: Dictionary, owner_lib: int, table) -> int:
	var name := str(child["cast_name"])
	if name == "":
		return owner_lib
	# **A library's name and its file path need not agree, and this used to match
	# only the name.** `DirectorCastTable.lib_for_cast_entry` is the engine's one
	# copy of the rule -- declared path, then resolved path, then name, by exact
	# stem equality -- and this function carried a second copy that skipped the
	# first two. `piposh-dream/meet5.dir` links
	# `macintosh hd:arcade:origina:psyco2.cst` under the *name* `psyco`, so its
	# `ccl` stem `psyco2` matched nothing and children 89-93 of `Internal:37` fell
	# back to the loop's own cast; the same movie does it again with `chor2.cst`
	# as `chor`. `bugs.md` 109. Two copies of one rule is how they drifted, so
	# there is now one.
	var found: int = table.lib_for_cast_entry(name)
	if found >= 0:
		return found
	# Unresolvable, which for a converted file is the normal case rather than the
	# exception: DAY1's `ccl ` holds a single local path that names none of its
	# five libraries.
	#
	# The loop's own library is the answer, not a guess at the name. A film
	# loop's children live in the cast the loop lives in, and that is knowledge
	# the container gives us directly. Guessing from the name is actively worse
	# than dropping the child: matching `won` as a prefix of `wonder` resolved
	# master's loops 2:57 and 2:59 into the *wonder* cast, where the same member
	# numbers name unrelated art -- so the loops drew, with somebody else's
	# pictures in them. A missing asset is a bug you can see; a plausible wrong
	# one is a bug you argue about.
	return owner_lib


## The loop's mini-score, read against **its own container's** `ccl ` list.
##
## Not the playing movie's. A film loop is a cast member, so a loop in a linked
## cast indexes the list in that cast file — usually absent, which says its
## children name no cast but its own. Handing it the movie's list instead
## resolved MURDER1's `MASTER:invright` and `HEZI:hezr` children into `tofi`,
## because tofi is MURDER1's own first entry. `DirectorCastTable.cast_list_for`
## holds the rule and the evidence.
static func open_loop(lib: int, member: Dictionary, table):
	var chunk_id := int(member.get("data_chunk_id", -1))
	if chunk_id < 0:
		return null
	var f = table.file_for(lib)
	if f == null:
		return null
	var loop = FilmLoop.new()
	var ccl: PackedStringArray = table.cast_list_for(lib)
	if not loop.parse(f.read_chunk(chunk_id), ccl, bool(member.get("looping", true))):
		return null
	return loop


## A film-loop child as a sprite record the rest of the renderer understands.
##
## The size rule here is the same one the main score gets, and always was the
## right one. `tools/film_loop_stretch.gd` separated the two populations on the
## flag -- **that tool is deleted**, with the rest of the retired renderer's
## harnesses, so the figure below is a record rather than something to re-run:
## of the 2,053 children carrying it, **zero** have a rect equal to their
## member's natural size, so with the flag clear the recorded rect really is
## authoring residue and the child draws at its member's size. This used to carry
## a note that the main score behaved oppositely and deliberately; it did not --
## the main score was reading residue, which is bugs.md 31, now closed.
##
## The resolution still happens here rather than by calling `drawn_size`, because
## a child arrives as a loop record and not as a sprite record: it has no member
## dictionary of its own until the caller resolves one, and it has no cast type to
## except on.
##
## **That population argument is about which rect to start from, and it was
## quietly doing a second job it cannot do.** It says the *recorded* rect is
## residue when the flag is clear, which is a fact about the disc — and the size
## this function returns after a squeeze is not on the disc, it is arithmetic done
## here. `Geometry.drawn_size` was asking the flag about that computed rect too and
## therefore answering the member's natural size for every unflagged child, so the
## scale below reached the child's *position* and never its pixels: a stone thrown
## in perspective at a constant 69x64, which is `bugs.md` 99 and what a player
## reported as the balls in Hatuli's game not shrinking. The record now carries
## `Geometry.SIZE_COMPUTED` to say which of the two rects it is holding, and that
## key's own docstring carries why it is not spelled `size_from_script`.
##
## `scale` is the loop's own squeeze (`child_scale`), and it applies after that
## resolution rather than instead of it: a child is sized by its own rule first
## and then shrunk with everything else in the loop. A scaled size is clamped to
## one pixel rather than allowed to reach zero, because a zero-sized decode is an
## error and Director's answer here is unknown — ScummVM does not scale child
## sizes at all (DIRECTOR_ENGINE.md §18), so there is nothing to copy. The clamp
## is also why a marked record always states at least 1x1, which is what keeps
## `drawn_size`'s degenerate-rect guards from reaching one.
##
## At `Vector2.ONE` the marker is false and every value in the record is what it
## has always been, so a loop drawn at its own size is untouched by all of this —
## the identity case `child_scale` and `nested_scale` both return exactly.
static func child_sprite(child: Dictionary, lib: int, member: Dictionary,
		scale := Vector2.ONE) -> Dictionary:
	var w := int(member.get("width", 0))
	var h := int(member.get("height", 0))
	if bool(child["stretch"]) and int(child["width"]) > 0 and int(child["height"]) > 0:
		w = int(child["width"])
		h = int(child["height"])
	var computed := scale != Vector2.ONE
	if computed:
		w = maxi(1, int(w * scale.x))
		h = maxi(1, int(h * scale.y))
	# The rendering attributes come across too. `texture_for` keys on the ink and
	# the colours, `blend_alpha` reads the blend pair and the blit reads the flip
	# bits; a child stripped of them draws by the loop's rules instead of its own,
	# and nothing says a half is missing.
	return {
		"cast_lib": lib, "cast_id": int(child["cast_id"]),
		"ink": int(child["ink"]), "stretch": bool(child["stretch"]),
		"width": w, "height": h,
		# Only when the size really was computed, so a loop drawn at its own size
		# still produces exactly the record it always did -- see the docstring.
		Geometry.SIZE_COMPUTED: computed,
		"flip_h": bool(child.get("flip_h", false)),
		"flip_v": bool(child.get("flip_v", false)),
		"has_blend": bool(child.get("has_blend", false)),
		"blend_amount": int(child.get("blend_amount", 0)),
	}


## The loop's own top-left on the stage.
##
## Its registration point is the centre of its rect, so `loc - half the drawn
## size` -- the scaled form of the same rule every other cast type uses.
##
## The drawn size comes from `Geometry.drawn_size`, not from the sprite record,
## for the reason the module docstring in `sprite_geometry.gd` gives: there is one
## rect. Reading the record here while the hit test read the resolved size put a
## loop's artwork somewhere its own clickable box was not, by half the difference
## between the score's residue rect and the member's own.
static func stage_origin(sprite: Dictionary, member: Dictionary) -> Vector2:
	var drawn := Geometry.drawn_size(sprite, member)
	return Vector2(
		float(sprite["loc_h"]) - floor(drawn.x * 0.5),
		float(sprite["loc_v"]) - floor(drawn.y * 0.5)
	)


## Where the loop's own coordinate space starts.
##
## A child's loc is its registration point inside that space, which the loop's
## rect anchors -- not a top-left on the stage. Adding it to the sprite's
## position, as the first version did, places every child by however far the
## loop's rect happens to sit from the origin, which is why the animations that
## had never drawn before appeared in the wrong place.
static func loop_origin(member: Dictionary) -> Vector2:
	var rect: Dictionary = member.get("initial_rect", {})
	return Vector2(int(rect.get("left", 0)), int(rect.get("top", 0)))


## How far the loop's contents are squeezed to fit the sprite, per axis.
##
## A loop's `initialRect` is the union bounding box of its own contents, so it is
## simultaneously the loop's natural size and the space its children are measured
## in (§1.6). Draw the sprite at any other size and **everything inside scales by
## `drawn / natural`** — the child positions and the children themselves. Nothing
## here did, which is bugs.md 16.8 as the surviving renderer inherited it, and it
## is not a subtle offset: a squeezed loop drew its children at full size in the
## loop's own authored coordinates, so the animation appeared wherever it had been
## authored rather than where the sprite is.
##
## `PIPDATA/DISKSHOT.dir` is the instance that found it. The clay pigeons are one
## 72x16 member on channels 24-45, each sprite stretched down to about 26x7 to sit
## far away in the sky; clicking one swaps its member to the `diskblow` film loop,
## whose rect is 287x279 and whose single child sits at (320,240) — the middle of
## the stage, which is where Piposh is standing. Unscaled, that put a full-size
## explosion over the player instead of a small one on the disk. Scaled, the
## child's start point lands within a pixel of the disk's own.
##
## The identity case returns `Vector2.ONE` exactly, so a loop drawn at its natural
## size goes through the arithmetic it always did rather than through a multiply
## by a computed 1.0.
static func child_scale(sprite: Dictionary, member: Dictionary) -> Vector2:
	var natural := Vector2(int(member.get("width", 0)), int(member.get("height", 0)))
	if natural.x <= 0.0 or natural.y <= 0.0:
		return Vector2.ONE
	var drawn := Geometry.drawn_size(sprite, member)
	if drawn == natural:
		return Vector2.ONE
	return Vector2(drawn.x / natural.x, drawn.y / natural.y)


## Where one child's artwork goes.
##
## Two subtractions, not one. A child's own start point is first made relative to
## the loop's rect origin, then placed at where the loop landed on the stage --
## and only then does the child's own registration offset come off, by the same
## rule as any other sprite. Forgetting either subtraction gives a constant
## offset: the loop's rect origin, or half the loop's size.
##
## `scale` is the loop's squeeze (`child_scale`) and it multiplies the *offset
## inside the loop*, never the loop's landing point: the origin is already on the
## stage, and scaling it too would move the sprite instead of its contents.
##
## The child's registration offset arrives already scaled and is not touched here.
## That is a change of route rather than of rule: the caller derives it from the
## child's **drawn** size through `Geometry.scaled_reg`, and `child_sprite` now
## shrinks that size by the same factor, so the offset follows the artwork without
## this function knowing about it. The note this replaces said the offset was
## deliberately unscaled, "reverted on evidence, not theory" -- and it was right
## for the code it described, because scaling the offset while leaving the
## position at authored coordinates moves a child further from where it belongs.
## Scaling both is what makes either correct.
static func place_child(origin: Vector2, space: Vector2, child: Dictionary,
		child_reg: Vector2, scale := Vector2.ONE) -> Vector2:
	var at := Vector2(float(child["loc_h"]), float(child["loc_v"]))
	return origin + (at - space) * scale - child_reg


## How far a nested loop's own content scale is derived, when the loop is drawn as
## another loop's child.
##
## This takes the ratio from the size the child is really drawn at, and asks the
## record for nothing else. **`child_scale` could not be used here, and the reason
## it could not was `bugs.md` 99 rather than a limitation of nesting**: it asks
## `Geometry.drawn_size`, which ignored any size that was not the member's own
## unless the record carried the stretch flag, and a film-loop child does not carry
## it in the general case -- of the 2,053 children in this corpus that do, none has
## a rect equal to its member's natural size. So a nested loop drawn 18x18 out of a
## 72x72 member had `drawn_size` answer 72x72 and `child_scale` therefore return
## `Vector2.ONE`, dropping the parent's squeeze for every grandchild.
##
## That miss is fixed (`docs/bugs-closed.md` 99): `child_sprite` marks a computed
## size with `Geometry.SIZE_COMPUTED` and `drawn_size` honours it, so
## `child_scale(record, member)` would now answer exactly what this function does
## for every record `paint_loop` hands it -- with the marker set `drawn_size`
## returns the record's own size, and without it both sides are the natural size and
## both return `Vector2.ONE`. **The two are not merged**, and that is a decision
## rather than an omission: this one is a function of a size, which is what the
## recursion has, while `child_scale` is a function of a *sprite* record with a
## `loc_h`, a channel and a member reference that a nested loop has no equivalent
## of. Folding them would mean synthesising a fake sprite record per level to ask
## the question with, which is more machinery than the four lines it would delete.
## What the equivalence *does* buy is that the two rules can no longer disagree
## about a squeeze, which is the drift `sprite_geometry.gd`'s module docstring is
## about, and it is worth re-checking here if either ever grows a third branch.
##
## Load-bearing at both sizes, which is worth stating because "compose the squeeze"
## sounds like it only matters to a squeezed loop. Measured by replacing this call
## with `Vector2.ONE` -- exactly what `child_scale` would answer for an unflagged
## loop child -- and running `tools/film_loop_scale.gd -- --root piposh-dream`:
## **3,764 of 4,044 grandchildren leave their box**, and 280 of those fail at the
## parent's *natural* size too, because a nested loop's own record carries a rect of
## its own and is routinely drawn at a size that is not the member's.
##
## `drawn` is `child_sprite`'s own answer, which is what `tools/film_loop_scale.gd`
## already treats as the authoritative drawn size of a loop's child. So the
## composition is exact rather than approximate: `child_sprite` returns
## `(natural or the child's own rect) * parent_scale`, and dividing that by the
## nested member's natural size folds the parent's squeeze in exactly once -- with
## the child's own stretch, when it carries one, multiplied on top of it.
##
## The identity case returns `Vector2.ONE` exactly, the same care `child_scale`
## takes and for the same reason: an unsqueezed nested loop must go through the
## arithmetic it always did rather than through a multiply by a computed 1.0.
static func nested_scale(drawn: Vector2, member: Dictionary) -> Vector2:
	var natural := Vector2(int(member.get("width", 0)), int(member.get("height", 0)))
	if natural.x <= 0.0 or natural.y <= 0.0:
		return Vector2.ONE
	if drawn == natural:
		return Vector2.ONE
	return Vector2(drawn.x / natural.x, drawn.y / natural.y)


## How deep the painter will descend into nested loops before it gives up.
##
## A guard against a loop that contains itself, which the container format permits
## and nothing in it forbids: `paint_loop` would otherwise recurse until the stack
## goes, and the `loops` cache does not save it -- the cache stops the *parse* from
## repeating, not the descent. **Breadth is the real cost, not depth**: ten
## loop-children each with ten loop-children is a hundred paints at depth 2, so a
## generous depth cap is cheap and a cap on the total is what would actually bound
## the work.
##
## The guard is `depth > MAX_DEPTH` and `depth` starts at 0, so this paints depths
## 0..5 -- **six levels**, not five. The corpus's own maximum is 2
## (`tools/film_loop_nesting.gd` records the census), so that is four levels more
## than anything here needs, and still a bound.
const MAX_DEPTH := 5


## Draw a film-loop sprite by drawing its children. False when the member is not
## a film loop, so the caller falls through to the bitmap path.
##
## True for a loop whether or not anything came out, which is the same contract
## `director_preview.gd:_draw_text` states: the sprite *is* a film loop, and
## falling through would only ask the cast for bitmap artwork a type-2 member does
## not have.
static func draw(host, sprite: Dictionary, table, loops: Dictionary,
		ticks: int, loop_start: Dictionary) -> bool:
	var lib := int(sprite["cast_lib"])
	var id := int(sprite["cast_id"])
	var m: Dictionary = table.get_member(lib, id)
	if m.is_empty() or int(m.get("type", 0)) != 2:
		return false

	# Counted from when this loop arrived on the channel, not from the movie
	# clock: a loop entered a second time starts at its first frame rather than
	# resuming wherever the previous one left off.
	var since := maxi(0, ticks - int(loop_start.get(int(sprite["channel"]), 0)))
	paint_loop(host, lib, id, m, stage_origin(sprite, m), child_scale(sprite, m),
		table, loops, since, Ink.blend_alpha(sprite), 0)
	return true


## One loop, painted at a known place on the stage -- and its loop children with it.
##
## Director nests: a film loop's child may itself be a film loop, and the child's
## whole mini-score expands inline at the parent's position in the parent's order
## (DIRECTOR_ENGINE.md §1.6, §6.3). Nothing here descended before, so a nested loop
## was skipped whole and tallied `"child has no art"` -- `host._texture_for` is
## bitmap-and-shape only and answers null for a type-2 member.
##
## Measured in `piposh-dream`'s `COMEIN.dir`, on Hatuli's projectile game entered at
## f720, over a window bounded at **30 top-level loop paints** -- `"loop drawn"` at
## depth 0 is the one tally that counts the same thing with this recursion and
## without it, where a window counted in process frames does not, because the two
## states do different work per frame. Before: `child drawn 11`, `child has no art
## 19`, and **all 19 were member `1:167`**, the `stone` loop itself. After:
## `child drawn 30`, `child has no art 0`, `nested loop drawn 28`.
##
## So the residue is 0 rather than small, and the 1x1 blank `1:168` that a nested
## loop's siblings also carry is **not** a source of it: it drew 9 times in the
## pre-fix window and reaches the texture cache like any other bitmap. The hole was
## the type-2 child and only ever the type-2 child. The window does not hold the
## ball loop's own frame fixed, though -- it bounds how much top-level painting
## happens, not which of the 21 frames each paint sees -- so which *bitmap* siblings
## come up varies between the two runs and only the `1:167` column is a like-for-like
## comparison. The player-visible symptom was that the game has no projectiles in it.
##
## Everything the recursion needs is a parameter and nothing is a field on the
## preview node, deliberately: a new `_` field there would have to be classified in
## `preview/save_state.gd`'s `ACCOUNTED` manifest, carried through
## `preview/movie_session.gd` and asserted in `tools/preview_surface.gd`, and none
## of those has anything to say about a value that does not outlive one paint. The
## one thing that *is* shared is the `loops` parse cache, keyed `"lib:id"`, which is
## also what makes a self-nesting loop hit the cache rather than re-parse per level.
##
## `origin` is the loop's top-left on the stage, threaded in rather than re-derived.
## The top level computes it with `stage_origin`; each recursive call computes it
## with the same `place_child` expression a bitmap child gets. One placement path
## and no second derivation, which is the whole point of the shape: a nested loop
## placed by a rule of its own would drift from its siblings the first time either
## rule changed.
##
## ## Which frame a nested loop is on
##
## `counter` is the parent's **already-wrapped** frame index, not the parent's raw
## `ticks - loop_start[channel]`. A nested loop has no channel, so it has no
## `_loop_start` entry and no counter of its own; it takes its parent's frame index
## and wraps that again by its own `frame_count` and its own `looping` flag
## (`director_film_loop.gd:frame_index`).
##
## **The corpus's own `looping` flags decide it**, and they decide it the same way at
## both sites that have one. COMEIN's ball loops are `looping=false` over 21 frames
## nesting a `looping=true` `stone` over 8: pass the raw counter down and the stone
## goes on spinning for ever after the ball has clamped on its last frame, which is a
## landed stone still rotating. `rating/blatack1.dir`'s `grnd2`..`grnd5` are the
## mirror -- `looping=true` over 16 frames nesting a `looping=false` `explode1` over
## 17 -- and with the raw counter the explosion freezes on its last frame after one
## cycle while the ground animation keeps going. The wrapped reading is right at
## both; the raw reading is wrong at both.
##
## The reference agrees in shape rather than in code: `getSubChannels(bbox, frame)`
## is a pure function of `frame`, so what a film loop shows at frame N is a function
## of N alone, and extended recursively the frame a nested loop expands at is the
## parent's own frame index. It also makes "a non-looping loop holds on its last
## frame" mean the whole composite holds, which is what holding ought to mean.
##
## **This is reference-derived and unverified against real Director**, because
## ScummVM does not implement nesting at all and so cannot be asked. `window.cpp:218`
## expands sub-channels exactly one level and blits each without ever asking
## `hasSubChannels()`; `score.cpp:952` advances `_filmLoopFrame` only over main-score
## channels, and `getSubChannels` builds every sub-channel as a fresh `Channel` whose
## `_filmLoopFrame` is 0 (`channel.cpp:61`). So a nested loop there would freeze on
## its own frame 0 even if it were expanded, and there is no answer in it to copy.
##
## ## The tallies
##
## Depth 0 keeps every existing key unchanged, so numbers recorded before this
## function existed stay comparable; depth 1 and below take a `"nested "` prefix.
## The two leaf keys are shared at every depth on purpose: `"child drawn"` and
## `"child has no art"` are facts about a leaf rather than about a level, and
## `"child drawn"` rising is what this change landing looks like.
static func paint_loop(host, lib: int, id: int, member: Dictionary, origin: Vector2,
		scale: Vector2, table, loops: Dictionary, counter: int, alpha: float,
		depth: int) -> void:
	if depth > MAX_DEPTH:
		# Reported rather than returned quietly. This module's whole ethos is that
		# nothing should be able to say a half is missing without saying so, and a
		# silent cap is exactly that: the art stops appearing and the report is clean.
		host._tally_loop("nested loop past depth %d" % MAX_DEPTH)
		return

	var key := "%d:%d" % [lib, id]
	if not loops.has(key):
		loops[key] = open_loop(lib, member, table)
	var loop = loops[key]
	if loop == null:
		host._tally_loop(_tag(depth, "loop unparsed"))
		return # a film loop that will not parse still draws no bitmap
	host._tally_loop(_tag(depth, "loop drawn"))

	var space := loop_origin(member)
	var index: int = loop.frame_index(counter)
	var kids: Array = loop.children(index)
	host._tally_loop(_tag(depth, "children offered"))
	if kids.is_empty():
		host._tally_loop(_tag(depth, "loop has no children this tick"))
	for child in kids:
		var kid_lib := child_lib(child, lib, table)
		if kid_lib < 0:
			host._tally_loop(_tag(depth, "child unresolved cast=%s" % str(child["cast_name"])))
			continue
		var cm: Dictionary = table.get_member(kid_lib, int(child["cast_id"]))
		# A child carries its own ink and its own blend, and the loop's alpha
		# multiplies through: a blended loop dims everything inside it, and with a
		# nested loop that composes per level rather than only over the two.
		var kid_alpha := alpha * Ink.blend_alpha(child)
		if int(cm.get("type", 0)) == 2:
			var record := child_sprite(child, kid_lib, cm, scale)
			var size := Vector2(int(record["width"]), int(record["height"]))
			# `kid_lib`, never `lib`. A nested loop's children index the **nested
			# loop's own container's** `ccl ` list, and `open_loop` takes that list
			# from the library it is handed; handing it the parent's is the failure
			# `director/director_film_loop.gd`'s docstring is built around -- a real
			# member out of an unrelated cast, drawn, with nothing reporting it.
			paint_loop(host, kid_lib, int(child["cast_id"]), cm,
				place_child(origin, space, child, Geometry.scaled_reg(cm, size), scale),
				nested_scale(size, cm), table, loops, index, kid_alpha, depth + 1)
			continue
		var record := child_sprite(child, kid_lib, cm, scale)
		var texture: Texture2D = host._texture_for(record)
		if texture == null:
			# The count that has always been printed, kept exactly so a figure
			# quoted in an older commit still means what it said.
			host._tally_loop("child has no art")
			# And **why**, which is `bugs.md` 110 and the whole of what was
			# missing. "No art" was one bucket holding two unrelated things: a
			# member whose artwork failed to decode, which is a defect, and a
			# member type this renderer is *right* not to draw, which is not.
			# `plane1.dir`'s eight are all the second -- `vectorShape` Xtras --
			# and there was nothing in the report able to say so, so the number
			# read as eight broken animations for as long as it stood.
			# `sprite_art.gd:decline_reason` carries the decode and the argument.
			var reason: String = SpriteArt.decline_reason(record, table)
			host._tally_loop("child not drawn: "
				+ (reason if reason != "" else "artwork did not decode"))
			continue
		host._tally_loop("child drawn")
		host._draw_sprite_texture(
			texture,
			place_child(origin, space, child,
				Geometry.scaled_reg(cm, texture.get_size()), scale),
			child,
			Color(1, 1, 1, kid_alpha)
		)


## A tally key, told apart by level. Depth 0's keys are the ones this module has
## always printed, so a figure quoted in an older commit still means what it said.
static func _tag(depth: int, key: String) -> String:
	return key if depth == 0 else "nested " + key
