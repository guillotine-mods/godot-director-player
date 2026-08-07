extends RefCounted
## Film loops: a mini-score inside a cast member, drawn as one sprite.
##
## A loop occupies a single channel on the stage and layers where the score put
## it, but inside itself it has its own channels, its own frames and its own
## clock. Children stack among themselves by their mini-score channel.
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


## The movie's cast-library number for a child's named cast, or the loop's own.
static func child_lib(child: Dictionary, owner_lib: int, table) -> int:
	var name := str(child["cast_name"])
	if name == "":
		return owner_lib
	# A `ccl ` entry is the cast's authoring path, in whichever separator the
	# machine that saved the movie used: Mac colon form in the 1997 originals, a
	# Windows path in a file that has been through a converter. Only the filename
	# is of any use, so both separators are normalised before it is taken.
	var stem := name.replace(":", "/").replace("\\", "/").get_file().get_basename().to_lower()
	for number in table.cast_libs:
		if str(table.cast_libs[number].get("name", "")).to_lower() == stem:
			return int(number)
	# Unresolvable, which for a converted file is the normal case rather than the
	# exception: DAY1's `ccl ` holds a single truncated local path
	# (`...\PIP2DATA\won`) that names none of its five libraries.
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


static func open_loop(lib: int, member: Dictionary, table, ccl: PackedStringArray):
	var chunk_id := int(member.get("data_chunk_id", -1))
	if chunk_id < 0:
		return null
	var f = table.file_for(lib)
	if f == null:
		return null
	var loop = FilmLoop.new()
	if not loop.parse(f.read_chunk(chunk_id), ccl, bool(member.get("looping", true))):
		return null
	return loop


## A film-loop child as a sprite record the rest of the renderer understands.
##
## The size rule here is the opposite of the main score's, and deliberately so.
## `tools/film_loop_stretch.gd` separates the two populations on the flag: of the
## 2,053 children carrying it, **zero** have a rect equal to their member's
## natural size, so with the flag clear the recorded rect really is authoring
## residue and the child draws at its member's size. The main score does not
## behave that way -- see `sprite_geometry.drawn_size` -- so the resolution
## happens here, before the shared path sees it, rather than as a branch inside
## it.
static func child_sprite(child: Dictionary, lib: int, member: Dictionary) -> Dictionary:
	var w := int(member.get("width", 0))
	var h := int(member.get("height", 0))
	if bool(child["stretch"]) and int(child["width"]) > 0 and int(child["height"]) > 0:
		w = int(child["width"])
		h = int(child["height"])
	# The rendering attributes come across too. `texture_for` keys on the ink and
	# the colours, `blend_alpha` reads the blend pair and the blit reads the flip
	# bits; a child stripped of them draws by the loop's rules instead of its own,
	# and nothing says a half is missing.
	return {
		"cast_lib": lib, "cast_id": int(child["cast_id"]),
		"ink": int(child["ink"]), "stretch": bool(child["stretch"]),
		"width": w, "height": h,
		"flip_h": bool(child.get("flip_h", false)),
		"flip_v": bool(child.get("flip_v", false)),
		"has_blend": bool(child.get("has_blend", false)),
		"blend_amount": int(child.get("blend_amount", 0)),
	}


## The loop's own top-left on the stage.
##
## Its registration point is the centre of its rect, so `loc - half the drawn
## size` -- the scaled form of the same rule every other cast type uses.
static func stage_origin(sprite: Dictionary, member: Dictionary) -> Vector2:
	var parent_w := float(sprite.get("width", member.get("width", 0)))
	var parent_h := float(sprite.get("height", member.get("height", 0)))
	return Vector2(
		float(sprite["loc_h"]) - floor(parent_w * 0.5),
		float(sprite["loc_v"]) - floor(parent_h * 0.5)
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


## Where one child's artwork goes.
##
## Two subtractions, not one. A child's own start point is first made relative to
## the loop's rect origin, then placed at where the loop landed on the stage --
## and only then does the child's own registration offset come off, by the same
## rule as any other sprite. Forgetting either subtraction gives a constant
## offset: the loop's rect origin, or half the loop's size.
##
## The child's registration offset is deliberately NOT scaled by the stretch
## factor -- which is what the stage path does for a stretched sprite. Scaling it
## here measurably moved the animations further from where they belong, so a
## loop's children anchor in the loop's own coordinate space rather than in the
## drawn one. Reverted on evidence, not theory; the stage path keeps its scaling.
static func place_child(origin: Vector2, space: Vector2, child: Dictionary,
		child_reg: Vector2) -> Vector2:
	var at := Vector2(float(child["loc_h"]), float(child["loc_v"]))
	return origin + (at - space) - child_reg


## Draw a film-loop sprite by drawing its children. False when the member is not
## a film loop, so the caller falls through to the bitmap path.
static func draw(host, sprite: Dictionary, table, loops: Dictionary,
		ccl: PackedStringArray, ticks: int, loop_start: Dictionary) -> bool:
	var lib := int(sprite["cast_lib"])
	var id := int(sprite["cast_id"])
	var m: Dictionary = table.get_member(lib, id)
	if m.is_empty() or int(m.get("type", 0)) != 2:
		return false

	var key := "%d:%d" % [lib, id]
	if not loops.has(key):
		loops[key] = open_loop(lib, m, table, ccl)
	var loop = loops[key]
	if loop == null:
		host._tally_loop("loop unparsed")
		return true # a film loop that will not parse still draws no bitmap
	host._tally_loop("loop drawn")

	var origin := stage_origin(sprite, m)
	var space := loop_origin(m)

	# Counted from when this loop arrived on the channel, not from the movie
	# clock: a loop entered a second time starts at its first frame rather than
	# resuming wherever the previous one left off.
	var since := maxi(0, ticks - int(loop_start.get(int(sprite["channel"]), 0)))
	var kids: Array = loop.children(since)
	host._tally_loop("children offered")
	if kids.is_empty():
		host._tally_loop("loop has no children this tick")
	for child in kids:
		var kid_lib := child_lib(child, lib, table)
		if kid_lib < 0:
			host._tally_loop("child unresolved cast=%s" % str(child["cast_name"]))
			continue
		var cm: Dictionary = table.get_member(kid_lib, int(child["cast_id"]))
		var texture: Texture2D = host._texture_for(child_sprite(child, kid_lib, cm))
		if texture == null:
			host._tally_loop("child has no art")
			continue
		host._tally_loop("child drawn")
		# A child carries its own ink and its own blend, and the loop's alpha
		# multiplies through: a blended loop dims everything inside it.
		host._draw_sprite_texture(
			texture,
			place_child(origin, space, child,
				Geometry.scaled_reg(cm, texture.get_size())),
			child,
			Color(1, 1, 1, Ink.blend_alpha(child) * Ink.blend_alpha(sprite))
		)
	return true
