extends RefCounted
## Director's ink rules: what a sprite's ink does to its pixels, and to clicks.
##
## Title-agnostic. Nothing here knows what game is loaded.
##
## The one thing to carry away before reading further: **render and hit test are
## different tables, and the asymmetry is deliberate.** Only Matte hit-tests per
## pixel. Background Transparent renders per-pixel and hit-tests as a full
## rectangle. A port that makes every transparent-looking ink per-pixel lets
## clicks fall through backdrops that should catch them; one that makes
## everything rectangular lets irregular matte sprites steal clicks. Both
## mistakes were made here before the tables were separated.
##
## What this corpus actually uses, from `tools/ink_survey.gd` over 816,318 sprite
## records in 61 movies:
##
##   36 Background Transparent  554,242   67.90%
##    8 Matte                   172,184   21.09%
##    0 Copy                     88,095   10.79%
##   32 Blend                     1,765    0.22%
##    1 Transparent                  32    0.00%
##
## Nothing else appears at all — no Mask (9), no arithmetic inks, no Reverse.
## So the four that matter are implemented properly and everything else falls
## through to Copy, which is the fallback the reference recommends: mapping
## unknown inks to Background Transparent instead would key out artwork.

## Director's ink numbers. 10-31 are unused by the format itself.
const COPY := 0
const TRANSPARENT := 1
const REVERSE := 2
const GHOST := 3
const NOT_COPY := 4
const NOT_TRANSPARENT := 5
const NOT_REVERSE := 6
const NOT_GHOST := 7
const MATTE := 8
const MASK := 9
const BLEND := 32
const ADD_PIN := 33
const ADD := 34
const SUB_PIN := 35
const BACKGND_TRANS := 36
const LIGHT := 37
const SUB := 38
const DARK := 39

## The ink field is the low six bits of the ink byte; 0x40 is trails and 0x80 is
## stretch. `director_score.gd` masks at decode, so a sprite dictionary already
## carries a clean number — this exists for anything reading a raw byte.
const INK_MASK := 0x3F

## How a sprite's pixels are keyed. Deliberately three cases and not eighteen:
## the fallback chain in Director's own blitter is Blend -> Matte -> Copy, and a
## port that implements Copy, Background Transparent and Matte correctly and maps
## the rest to Copy is reproducing that chain rather than approximating it.
## Plain constants rather than an enum: GDScript cannot reconcile an enum type
## across a `preload`ed script that has no `class_name`, and every consumer here
## reaches this file that way.
const KEY_NONE := 0   ## Copy: every pixel is drawn.
const KEY_PAPER := 1  ## Background Transparent: every pixel equal to backColor goes.
const KEY_MATTE := 2  ## Only the paper a flood fill reaches from the border goes.


## Which keying an ink asks for.
##
## Blend is grouped with Matte because Director's blend path returns *before* the
## ink switch and behaves as Matte regardless of the ink it nominally carries.
static func key_for(ink: int) -> int:
	match ink & INK_MASK:
		MATTE, MASK, BLEND:
			return KEY_MATTE
		# Transparent is here rather than under Copy because in 8-bit index space
		# its bitwise-OR against a white paper of index 0 leaves the destination
		# untouched, which is the same observable result as keying the paper.
		TRANSPARENT, BACKGND_TRANS:
			return KEY_PAPER
	return KEY_NONE


## Does a click land on this sprite only where it has pixels?
##
## Only Matte. This is the whole asymmetry, and it is the single rule most worth
## not "tidying up" later: Background Transparent is 68% of this corpus and every
## one of those sprites catches clicks across its full rectangle.
static func hits_per_pixel(ink: int) -> bool:
	return (ink & INK_MASK) == MATTE


## The alpha a sprite draws at, 0.0 to 1.0.
##
## The stored amount is Director's `the blend of sprite`, a **percentage**, not a
## 0-255 byte. `tools/ink_survey.gd` settles that: across the corpus the values
## observed run 21 to 98 and never approach 255. 100 is fully opaque.
##
## A sprite is blended when its ink is Blend or when the has-blend flag in the
## thickness byte is set. That flag is never set anywhere in this corpus, but it
## is honoured because the two are alternative sources for the same field.
static func blend_alpha(sprite: Dictionary) -> float:
	var ink := int(sprite.get("ink", 0)) & INK_MASK
	if ink != BLEND and not bool(sprite.get("has_blend", false)):
		return 1.0
	var amount := int(sprite.get("blend_amount", 0))
	if amount <= 0:
		# Blend with no factor degrades to plain Matte, which is already what
		# `key_for` returns. Drawing it at zero alpha would make it vanish.
		return 1.0
	return clampf(float(amount) / 100.0, 0.0, 1.0)


## Key out every pixel exactly equal to the paper colour.
##
## Exact, not near-enough. Director compares palette indices, and an 8-bit image
## decoded through the same palette reproduces the paper's RGB exactly, so a
## tolerance buys nothing and costs real artwork: near-white pixels Director
## would have kept get eaten. Where a tolerance genuinely helps is scanned or
## resampled art, and there the paper is a *mix* of indices that Director would
## not have keyed either.
static func key_paper(image: Image, paper: Color) -> int:
	var dropped := 0
	var w := image.get_width()
	var h := image.get_height()
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if c.r8 == paper.r8 and c.g8 == paper.g8 and c.b8 == paper.b8:
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
				dropped += 1
	return dropped


## Build Director's matte and apply it. Returns false when there is no matte.
##
## Matte is a *mask*, not a colour test, and the difference is visible: a donut
## with a white hole keeps its hole under Matte and loses it under Background
## Transparent. That is why this needs a flood fill and `key_paper` does not.
##
## Three rules that are easy to get wrong and are each load-bearing:
##
## 1. **The paper colour is found by scanning the whole border ring** for an
##    exactly-white pixel — all four edges, not the corners and not pixel (0,0).
##    A member whose top-left corner happens to be artwork keys the wrong colour
##    and the sprite then draws as an opaque rectangle that swallows every click
##    inside it.
## 2. **If no white is found anywhere on the border, no matte is built at all.**
##    The member is flagged as having none and the sprite renders and hit-tests
##    as a solid rectangle. This is a real Director behaviour and not an error
##    path — it is how a solid-edged bitmap stays solid — and without it a port
##    floods from whatever colour it happened to sample and produces garbage.
## 3. **Four-connected, and the colour test is exact.** No tolerance.
##
## The frontier is an explicit stack rather than recursion: a 640x480 backdrop
## would be hundreds of thousands of frames deep and GDScript has no catchable
## stack limit.
static func key_matte(image: Image) -> bool:
	var w := image.get_width()
	var h := image.get_height()
	if w <= 0 or h <= 0:
		return false
	if not _border_has_white(image):
		return false

	var white := Color(1, 1, 1, 1)
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))

	var seen := {}
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var at := p.y * w + p.x
		if seen.has(at):
			continue
		seen[at] = true
		var c := image.get_pixel(p.x, p.y)
		if c.a <= 0.0:
			continue
		if c.r8 != white.r8 or c.g8 != white.g8 or c.b8 != white.b8:
			continue
		image.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))
	return true


## Is there an exactly-white pixel anywhere on the border ring?
static func _border_has_white(image: Image) -> bool:
	var w := image.get_width()
	var h := image.get_height()
	for x in w:
		if _is_white(image, x, 0) or _is_white(image, x, h - 1):
			return true
	for y in h:
		if _is_white(image, 0, y) or _is_white(image, w - 1, y):
			return true
	return false


static func _is_white(image: Image, x: int, y: int) -> bool:
	var c := image.get_pixel(x, y)
	return c.a > 0.0 and c.r8 == 255 and c.g8 == 255 and c.b8 == 255


## The RGB a palette index names. Director's 8-bit convention is inverted from
## the intuitive one: **white is index 0 and black is index 255**, which the
## corpus confirms — the default foreColor (black) is stored as 255 in 94% of
## records and the default backColor (white) as 0 in 99.9%.
static func colour_of(palette: PackedByteArray, index: int) -> Color:
	if index < 0 or index * 3 + 2 >= palette.size():
		return Color(1, 1, 1, 1)
	return Color8(palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2])
