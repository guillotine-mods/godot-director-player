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
## The second thing to carry away: **the ink number does not decide the keying on
## its own.** `key_for` takes the sprite record and its member, because Director's
## own `Channel::getMask` reads the thickness byte's blend flag and the member's
## bit depth alongside the ink. Reading only the ink is right for the five inks
## this corpus is mostly made of and wrong for a class of 29,000 records; see
## `key_for` for the mechanism and `bugs.md` 50 for what it looked like on screen.
##
## What the ink *number* is, from `tools/ink_survey.gd` over 816,318 sprite
## records in Piposh 2's 61 movies:
##
##   36 Background Transparent  554,242   67.90%
##    8 Matte                   172,184   21.09%
##    0 Copy                     88,095   10.79%
##   32 Blend                     1,765    0.22%
##    1 Transparent                  32    0.00%
##
## Nothing else appears at all — no Mask (9), no arithmetic inks, no Reverse — and
## that holds across all three roots: 3,550,111 records in 241 scores carry only
## 0, 1, 8, 32 and 36. The ten arithmetic and Not- inks are implemented from the
## reference anyway and marked unverified where they land, because "0 uses in this
## corpus" is a fact about the corpus.
##
## **That last sentence used to be a fact about Piposh 2 wearing "this corpus" as
## a disguise**, which is the failure `AGENTS.md` names as this repository's most
## repeated. `tools/ink_survey.gd` walked the *configured* root under `--all` and
## nothing else, so every ink number ever printed from it -- including the zero
## for Mask that `ENGINE_TODO.md` recorded as "no member in this corpus" -- was
## one title. Re-measured over all eight roots after the tool was fixed:
## **8,079,420 sprite records in 491 scores across `games/` and `test-games/`,
## and 0 of them carry ink 9.** The zero survived; the sentence had not been
## entitled to it. The ink numbers that do appear across all eight are 0, 1, 8,
## 32, 36 and **41**, the last on 73 records -- and 41 sits at no position in
## Director's own table, which stops at 39 (`types.h`, `enum InkType`). It falls
## through every rule in this file to Copy, which is the honest answer for a
## number the format does not define; it is recorded here rather than explained
## because nobody has looked at those 73 records yet.
##
## The distribution is also why this file's one real defect hid for so long. Of
## those 88,095 Copy records in Piposh 2, only 209 carry the blend flag that makes
## Director matte them; in *Rating* it is 27,914 of 148,747. A port measured
## against one title and shipped against two is exactly where that gap shows.

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

## How a sprite's pixels are keyed. Three outcomes, and the thing to carry away is
## that **which one applies is not a function of the ink alone.** Director decides
## in `Channel::getMask` (`channel.cpp:188`) from the ink *and* the thickness
## byte's blend flag *and* the member's bit depth, and a port that reads only the
## ink number gets the common cases right and one whole class wrong.
##
## Plain constants rather than an enum: GDScript cannot reconcile an enum type
## across a `preload`ed script that has no `class_name`, and every consumer here
## reaches this file that way.
const KEY_NONE := 0   ## Copy: every pixel is drawn.
const KEY_PAPER := 1  ## Background Transparent: every pixel equal to backColor goes.
const KEY_MATTE := 2  ## Only the paper a flood fill reaches from the border goes.
## Mask: the *next cast member* is a 1-bit stencil over this sprite's artwork.
##
## Not a keying rule at all in the sense the other three are -- it looks at no
## pixel of this member. It is here because it is the fourth branch of the one
## decision `Channel::getMask` makes, and splitting it out into a second question
## asked somewhere else is how a renderer ends up asking about the ink twice and
## getting two answers (§2.6, `bugs.md` 50).
const KEY_MASK := 3


## The twelve inks Director builds a matte for on their ink number alone —
## `channel.cpp:192-203`, transcribed in its order.
##
## Two absences are deliberate and are not omissions here. **Reverse (2) and Ghost
## (3) are not in it**, so they fall through to Copy. **Mask (9) is not in it
## either**, and does not belong: `getMask`'s `else if` arm (`channel.cpp:228`)
## takes the *next cast member* as a separate 1-bit mask surface, which is a
## different mechanism from flooding this member's own paper. `key_for` used to
## answer `KEY_MATTE` for Mask, which was wrong in kind rather than by a degree
## (`bugs.md` 50), then answered `KEY_NONE`, which was Copy -- honest, and still
## not the mechanism. It answers `KEY_MASK` now and `apply_mask` is behind it.
##
## **Ten of these twelve are unverified against any data.** Over all three game
## roots — 3,550,111 sprite records in 241 scores — the only inks that ever appear
## are 0, 1, 8, 32 and 36, so 4, 5, 6, 7, 33, 34, 35, 37, 38 and 39 have zero
## records anywhere. They are implemented because Director has them: a corpus that
## cannot exercise something is a measurement about the corpus, not a licence to
## leave a hole that surfaces the first time another title loads.
const MATTE_INKS := [
	MATTE, NOT_COPY, NOT_TRANSPARENT, NOT_REVERSE, NOT_GHOST,
	BLEND, ADD_PIN, ADD, SUB_PIN, LIGHT, SUB, DARK,
]

## Director's QuickDraw shape *sprite types* (`types.h:157-170`), which are what
## `Sprite::isQDShape` tests (`sprite.cpp:189`) — the sprite-type byte, not the
## cast type. Every record in either corpus carries 16, `kCastMemberSprite`.
const QD_SHAPE_SPRITE_TYPES := [2, 3, 4, 5, 6, 12, 13, 14, 15]


## Which keying this sprite asks for, given the member it names.
##
## This takes the sprite record and the member rather than an ink number, and that
## is the whole point of it: Director's own decision reads three things and the ink
## is only one of them. `Channel::getMask` (`channel.cpp:188-226`) in order:
##
## 1. `needsMatte` if the ink is one of `MATTE_INKS`.
## 2. `needsMatte` if the sprite is blended *and* the amount is non-zero — the
##    blend flag in the thickness byte or Blend ink, either one.
## 3. `needsMatte` if the sprite is **not a QuickDraw shape, its ink is Copy, and
##    the thickness byte carries the blend flag** (`channel.cpp:206`). Note what
##    this clause does *not* test: the blend amount. A Copy sprite with the flag
##    set and an amount of 0 — fully opaque — still gets a matte.
## 4. A matte is only ever built for a **bitmap**; anything else gets none.
##
## Clause 3 is why this signature changed. `Rating`'s dialogue portraits carry
## exactly that combination — ink byte 0x00, thickness byte 0x10, blend amount 0 —
## and with keying decided from the ink alone they drew their own white paper as an
## opaque rectangle over the room (`bugs.md` 50). It is not a rare corner: 27,914
## of that title's 847,431 sprite records are Copy-with-blend, against 209 of
## Piposh 2's 816,318, which is why the port rendered one corpus acceptably for as
## long as it did.
static func key_for(sprite: Dictionary, member: Dictionary) -> int:
	var ink := int(sprite.get("ink", 0)) & INK_MASK
	var member_type := int(member.get("type", TYPE_BITMAP))
	if _needs_matte(sprite, ink):
		# Mattes are bitmap-only. A shape needs none — its primitives already draw
		# only what they draw — and a field has no image to flood. Both fall back to
		# drawing every pixel, which is what a null mask means in the reference.
		if member_type != TYPE_BITMAP:
			return KEY_NONE
		# The 1-bit exception (`channel.cpp:218-223`): a 1-bit member gets a matte
		# **only** under Matte ink proper. Under anything else in the list — Copy
		# with the blend flag included — the reference returns no mask at all and
		# the sprite draws solid.
		#
		# **No data in any corpus exercises this.** Of the records that reach a
		# matte-needing ink across all three roots, 0 name a 1-bit member: 0 under
		# Matte ink and 0 under the other eleven paths. It is here because it is
		# the rule, and because leaving it out is the failure that keys 1-bit art
		# Director leaves alone.
		if int(member.get("bits_per_pixel", 8)) == 1 and ink != MATTE:
			return KEY_NONE
		return KEY_MATTE
	# `channel.cpp:228`'s `else if`, and the `else if` is the whole shape of it:
	# Mask is reached **only when no matte was wanted**. A Mask-ink sprite that
	# also carries the blend flag with a non-zero amount takes the matte arm above
	# and never gets here, which is the reference's own precedence and not a
	# simplification. Nothing in any corpus can tell the two apart -- there are no
	# ink-9 records at all -- so the ordering is here because it is the reference's.
	if ink == MASK:
		return KEY_MASK
	# Transparent is here rather than under Copy because in 8-bit index space
	# its bitwise-OR against a white paper of index 0 leaves the destination
	# untouched, which is the same observable result as keying the paper.
	if ink == TRANSPARENT or ink == BACKGND_TRANS:
		return KEY_PAPER
	return KEY_NONE


## `Channel::getMask`'s `needsMatte`, the three clauses, before the cast type and
## the bit depth get a say. Split out so `key_for` reads as the reference's own
## two-step: decide whether a matte is wanted, then decide whether one can be had.
static func _needs_matte(sprite: Dictionary, ink: int) -> bool:
	if MATTE_INKS.has(ink):
		return true
	var has_blend := bool(sprite.get("has_blend", false))
	# `channel.cpp:204`. The stored amount is the raw byte, exactly as
	# `_blendAmount` is in the reference (`frame.cpp:1958`), so "non-zero" is the
	# same test in both — remembering that the byte is inverted, and 0 means
	# fully opaque rather than fully clear (`blend_alpha`).
	if (has_blend or ink == BLEND) and int(sprite.get("blend_amount", 0)) > 0:
		return true
	# `channel.cpp:206`. The amount is deliberately not consulted.
	if ink == COPY and has_blend \
			and not QD_SHAPE_SPRITE_TYPES.has(int(sprite.get("sprite_type", 0))):
		return true
	return false


## Does a click land on this sprite only where it has pixels?
##
## Only Matte, and only for a bitmap. This is the whole asymmetry, and it is the
## single rule most worth not "tidying up" later: Background Transparent is 68% of
## this corpus and every one of those sprites catches clicks across its full
## rectangle.
##
## **Mask (9) is the sharpest instance of the asymmetry now that it is built.** A
## Mask sprite is stencilled by another member's bits and can be invisible over
## most of its rect, and it still hit-tests as the **whole rectangle**:
## `BitmapCastMember::isWithin` (`castmember/bitmap.cpp:920-928`) tests
## `ink == kInkTypeMatte` and nothing else, and §2.1's table says rect for ink 9.
## So the picture and the hotspot legitimately disagree, exactly as they do for
## the Copy-with-blend case two paragraphs down. Routing the two through one
## predicate to make the hotspot overlay agree with the artwork is the mistake
## this whole docstring exists to prevent.
##
## **This deliberately disagrees with `key_for`, and the disagreement is the
## reference's.** `key_for` mattes a Copy sprite that carries the blend flag —
## `Channel::getMask` does — while this answers false for it, because
## `BitmapCastMember::isWithin` (`castmember/bitmap.cpp:920-928`) tests per pixel
## for `kInkTypeMatte` and nothing else, off the ink alone. So such a sprite draws
## through a matte and still catches clicks everywhere inside its box, including
## the parts that are now invisible. Run the hotspot outlines over `Rating`'s
## dialogue portrait and it will look like a bug: a green "whole rect" box around
## art with keyed-out corners. It is not. Routing both decisions through one
## predicate to make the picture tidy is the mistake this paragraph exists to
## prevent — it would hand every Copy-with-blend sprite a per-pixel hit test that
## Director never gave it.
##
## The cast-type half is the part that is easy to leave out. A matte is built by
## flooding the *member's image* in from the border, and only a bitmap has one; a
## shape has no image to flood, so a matte-inked shape hit-tests as its rectangle.
## Leaving it out is not a near-miss here, it is a dead hotspot: 452 of this
## corpus's shape sprite records carry Matte, every shape member they name is an
## unfilled rectangle with a stored line thickness of 1 — which Director draws as
## nothing — and a per-pixel test against nothing rejects every click. Their names
## are `to clif2`, `to stairs`, `to uplight`: they are the doors.
##
## `member_type` is the `CASt` type code, defaulting to bitmap so a caller that
## has only an ink number keeps the old answer.
static func hits_per_pixel(ink: int, member_type: int = TYPE_BITMAP) -> bool:
	return (ink & INK_MASK) == MATTE and member_type == TYPE_BITMAP


## Does `sprite A within B` compare mattes rather than boxes, for one operand?
##
## **This is deliberately not `hits_per_pixel`, and the difference is the
## reference's rather than an oversight here.** `LC::c_intersects` tests
## `_cast->_type == kCastBitmap` of each operand; `LC::c_within` tests
## `!isQDShape()` — the sprite-type byte (`sprite.cpp:189`), not the cast type. So
## a matte-inked *shape cast member* on a `kCastMemberSprite` record is compared as
## a matte by `within` and as a box by `intersects`, and there is nothing tidy
## about it. Two predicates because the reference has two; collapsing them would
## make the asymmetry invisible in the code, and the next reader would "fix" the
## port back to disagreeing with `c_within`.
##
## Measured over all six shipped roots by `tools/collision_ink.gd`: the sprite-type
## byte is **16 in all 8,057,628 records**, so on this data the clause reduces to
## the ink alone and `within` is the wider of the two tests. That is a fact about
## the corpus and not about Director -- a D3-era container with a QuickDraw shape
## *sprite* is exactly what the clause is for, and `director_score.gd` refuses the
## 24-byte record layout such a container would use.
static func mattes_for_within(ink: int, sprite_type: int) -> bool:
	return (ink & INK_MASK) == MATTE and not QD_SHAPE_SPRITE_TYPES.has(sprite_type)


## `CASt` type codes this file needs to tell apart. Plain ints for the same
## reason the keying constants are: an enum does not survive a `preload`.
const TYPE_BITMAP := 1
const TYPE_FIELD := 3
const TYPE_SHAPE := 8


## Does this sprite render in applyColor mode — its blacks repainted foreColor and
## its whites repainted backColor — rather than with the image's own colours?
##
## Director chooses before any pixel is touched (`setApplyColor`). The reference
## states the switch as two clauses over two groups of inks: "foreColor != black
## or backColor != white" for the Matte/Mask/Copy/Not-Copy group, and "not
## (foreColor == black and backColor == white)" for the transparent/ghost group.
## Those two clauses are the same condition written two ways, so what actually
## differs between the groups is nothing, and only membership of the list matters:
## every other ink — the arithmetic ones, Reverse, Blend — never applies colour.
##
## The indices are Director's inverted 8-bit convention, where black is 255 and
## white is 0 (2.2), so "default" means fore 255 and back 0.
static func applies_colour(ink: int, fore: int, back: int) -> bool:
	if fore == INDEX_BLACK and back == INDEX_WHITE:
		return false
	return APPLY_COLOR_INKS.has(ink & INK_MASK)


## The same switch asked of a whole sprite record, so that a record whose colour
## is a **true colour** rather than an index is answered about the colour.
##
## `applies_colour` above compares indices, and an index test cannot see a D7
## true colour at all: `(0,0,0)` fore and `(255,255,255)` back *is* the default
## pair, and its red bytes are 0 and 255, which as indices are the default pair
## **inverted**. So the index test said "not default, colourise" and
## `apply_colour` then swapped the artwork's black and white. Measured by
## `tools/sprite_rgb_colour.gd` over all eight roots: 32,875 records state
## `(0,0,0)` fore and all 57,152 back colours in the corpus are `(255,255,255)`,
## the overwhelming majority of them in `piposh-dream`. `bugs.md` 30.
##
## Callers with only two indices in hand keep using `applies_colour`; this is for
## anything holding the record, which is every renderer.
static func applies_colour_to(sprite: Dictionary, ink: int) -> bool:
	if is_default_colour(sprite):
		return false
	return APPLY_COLOR_INKS.has(ink & INK_MASK)


## Is this record's colour pair Director's default -- black ink on white paper --
## however the record chooses to say so?
##
## Two spellings of one fact, which is why this is a function and not a pair of
## comparisons at each call site: as palette indices the default is fore 255 and
## back 0 (the inverted 8-bit convention, 2.2), and as true colours it is fore
## `(0,0,0)` and back `(255,255,255)`. A sprite may state one half each way.
static func is_default_colour(sprite: Dictionary) -> bool:
	var fore_default := (
		_is_rgb(sprite.get(FORE_RGB_KEY), 0, 0, 0) if sprite.has(FORE_RGB_KEY)
		else int(sprite.get("fore_color", INDEX_BLACK)) == INDEX_BLACK)
	var back_default := (
		_is_rgb(sprite.get(BACK_RGB_KEY), 255, 255, 255) if sprite.has(BACK_RGB_KEY)
		else int(sprite.get("back_color", INDEX_WHITE)) == INDEX_WHITE)
	return fore_default and back_default


static func _is_rgb(value: Variant, r: int, g: int, b: int) -> bool:
	if not (value is Color):
		return false
	var c: Color = value
	return c.r8 == r and c.g8 == g and c.b8 == b


const INDEX_WHITE := 0
const INDEX_BLACK := 255
const APPLY_COLOR_INKS := [
	MATTE, MASK, COPY, NOT_COPY, TRANSPARENT, NOT_TRANSPARENT,
	BACKGND_TRANS, GHOST, NOT_GHOST,
]


## Repaint an image's black pixels `fore` and its white pixels `back`, in place.
## Returns how many pixels changed.
##
## This is Director's colourisation, and it is why one 1-bit cast member appears
## in a dozen colours across a movie without a dozen bitmaps existing. Every other
## pixel is left alone: the reference's Copy arm says a colourised copy of
## multi-colour art leaves non-black, non-white pixels as the *destination*, which
## is a hole rather than a colour, and punching holes through artwork is a worse
## failure than not colourising it. Leaving them is the conservative half of that
## rule and the only half that cannot make a sprite disappear.
##
## Exact matches only, for the reason `key_paper` gives: an 8-bit image decoded
## through the same palette reproduces black and white exactly, so a tolerance
## buys nothing and eats near-white artwork.
##
## Scope, measured: only 651 bitmap sprite records in this corpus reach here.
## Colourisation is not what makes this game's non-default colours numerous —
## 50,063 of those records name *shape* members, which are painted by the shape
## primitives instead (13) and never come through this function.
static func apply_colour(image: Image, fore: Color, back: Color) -> int:
	var changed := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if c.r8 == 0 and c.g8 == 0 and c.b8 == 0:
				image.set_pixel(x, y, Color(fore.r, fore.g, fore.b, c.a))
				changed += 1
			elif c.r8 == 255 and c.g8 == 255 and c.b8 == 255:
				image.set_pixel(x, y, Color(back.r, back.g, back.b, c.a))
				changed += 1
	return changed


## The alpha a sprite draws at, 0.0 to 1.0.
##
## The stored amount is a **0-255 byte holding the inverse** of Director's
## `the blend of sprite`, which is a 0-100 percentage. The setter writes
## `(100 - blend) * 255 / 100` and the getter reads `(255 - stored) * 100 / 255`,
## so **0 stored is fully opaque and 255 stored is invisible** — the opposite of
## what the number looks like.
##
## That is not read off the reference alone. Piposh 2's records take exactly
## eleven values in this byte — 0, 25, 51, 76, 102, 127, 153, 178, 204, 229,
## 255 — which is `round(255 * n / 10)` for n = 0..10, the ten-percent steps the
## authoring UI offers, on a 255 scale. A percentage stored directly could not
## produce 229 or 255 (`tools/sprite_record_bytes.gd`).
##
## This used to read the byte at record offset 19, which is the low half of the
## sprite's *width*, and divide it by 100. So every Blend-ink sprite drew at an
## alpha of `(width % 256) / 100` — opaque whenever that landed above 99 and an
## arbitrary translucency whenever it did not, changing whenever the sprite was
## resized. 1,765 records in Piposh 2 reach this; Piposh 1 has no Blend ink at
## all and no record with the has-blend flag, so it never showed there.
##
## A sprite is blended when its ink is Blend or when the has-blend flag in the
## thickness byte is set; the reference tests exactly that pair before it uses
## the amount at all (`channel.cpp:getPlotData`).
##
## `member` is the other half of the 1-bit exception `key_for` implements. The
## reference's mask path does two things to a 1-bit member drawn with Copy ink and
## the blend flag: it refuses the matte, and it **forces the blend amount to zero**
## on the way out (`channel.cpp:220-222`) — "1-bit images will not blend with
## kInkTypeCopy, whereas 8-bit images will", in its own words. So the sprite comes
## out opaque as well as unkeyed.
##
## Two honest caveats. **Nothing in any corpus reaches it**: 0 records across all
## three roots pair a 1-bit member with Copy, the blend flag and a non-zero amount,
## so this arm is implemented from the reference and unverified. And the parameter
## is **optional, and no caller passes it yet** — the four sites that ask for an
## alpha (`stage_paint.gd`, `film_loop_view.gd` twice, `text_art.gd`) have the
## member in hand but live outside the change that added this, so they still get
## the member-blind answer. Passing it is a one-line change at each and the rule is
## here waiting for it, which is a smaller lie than a rule that does not exist.
static func blend_alpha(sprite: Dictionary, member: Dictionary = {}) -> float:
	var ink := int(sprite.get("ink", 0)) & INK_MASK
	if ink != BLEND and not bool(sprite.get("has_blend", false)):
		return 1.0
	if ink == COPY and not member.is_empty() \
			and int(member.get("type", TYPE_BITMAP)) == TYPE_BITMAP \
			and int(member.get("bits_per_pixel", 8)) == 1:
		return 1.0
	var amount := clampi(int(sprite.get("blend_amount", 0)), 0, 255)
	return float(255 - amount) / 255.0


## A copy of `image` with every colour inverted and every alpha kept.
##
## This is the pixel half of hilite-on-click (§4.6). Director inverts the
## **destination** through the sprite's matte -- `Window::invertChannel` runs
## `_wm->inverter` over the composed surface for every pixel the matte lets
## through -- so what appears is the silhouette of the sprite in reverse video,
## which is the only feedback a Director title gives that a click has landed.
##
## Alpha is the mask. It is carried through untouched rather than inverted,
## because the keyed-out paper is exactly the region the matte excludes: under
## Matte ink the image's own alpha **is** the matte, so inverting the image and
## drawing it in place of the original reproduces the masked XOR exactly.
##
## **Where this diverges, and why it is not fixable here.** Under an ink that
## keys more than the matte does -- Background Transparent drops every paper
## pixel, including the ones enclosed by artwork that a matte keeps -- Director
## would invert whatever is *behind* the sprite in those holes, and this inverts
## nothing there. Reading the destination back needs a screen the renderer can
## sample mid-frame, which is the same thing §16.25 says the absence of dirty
## rects forecloses. It is unreachable from either corpus: the arm that admits a
## non-Matte ink is the Auto Hilite flag, and 0 of 73,994 Piposh 2 members and 0
## of Piposh 1's carry it (`tools/hilite_survey.gd`).
##
## Inverting in linear-free 8-bit terms -- 255 minus the channel -- because that
## is what `inverter` does to an index's RGB and what a period title was drawn
## against. A gamma-correct inversion would be a different picture.
static func invert(image: Image) -> Image:
	var out := Image.create_empty(
		image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			out.set_pixel(x, y, Color8(255 - c.r8, 255 - c.g8, 255 - c.b8, c.a8))
	return out


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


## Apply Mask ink (§2.6): a 1-bit stencil from the **next cast member**.
##
## `image` is the sprite's artwork at its drawn size and is modified in place;
## `bits` is `director_bitmap.gd:mask_bits`'s output for a `mask_w` x `mask_h`
## 1-bit member; `at` is where that member's top-left corner sits inside the
## image. Returns how many pixels the mask cleared.
##
## ## This is a different mechanism from every other ink, and the differences are
## the point
##
## Matte floods *this* member's own paper in from its border. Mask reads a
## *second member's bits* and cares nothing for this one's colours. `bugs.md` 50
## moved ink 9 out of the matte bucket for exactly that reason -- it was wrong in
## kind rather than by a degree -- and this is the mechanism that was missing
## behind it. What the sprite draws *through* the stencil is Copy
## (`graphics.cpp`'s ink switch has no Mask case; §2.4's fallback chain).
##
## ## Three rules, each from `channel.cpp:getMask`'s Mask arm and each easy to
## get backwards
##
## 1. **Alignment is by registration point, at the mask's natural size.** The
##    reference takes `bitmap->getBbox()` -- the mask member's rect moved so its
##    own registration point is the origin -- and translates it by the channel's
##    registration offset. So the two members' registration points coincide and
##    the mask is **not** scaled to the sprite: a stretched sprite gets a mask of
##    the mask member's own size. It is `getBbox()` with no arguments, where
##    `getBbox(w, h)` exists one line away in the same class and would have
##    scaled it.
## 2. **The surface is created at the channel's size and zeroed**, and only then
##    is the mask copied into it. Every pixel the mask member does not reach is
##    therefore 0, and 0 is hidden -- so a mask smaller than the sprite **crops**
##    the sprite to itself rather than leaving the remainder visible. Getting this
##    backwards is the difference between a stencil and a hole punch.
## 3. **Non-zero shows.** `inkBlitSurface` draws where the mask byte is non-zero
##    (`graphics.cpp:806`); `mask_bits` writes 255 for a set bit, which is what
##    `BITDDecoder`'s 1-bit case produces. `ENGINE_TODO.md` called the polarity
##    undecidable because no record in the corpus carries ink 9; it is undecidable
##    from the data and decided exactly by those two lines.
##
## **Unverified against any real sprite, because there is none.** 0 of 8,079,420
## sprite records across all eight roots carry ink 9 (`tools/ink_survey.gd --all`,
## 491 scores). Built because Director has it: `tools/mask_ink.gd` drives it from a
## real 1-bit member's real `BITD` bytes and a sprite record this port composes.
static func apply_mask(image: Image, bits: PackedByteArray, mask_w: int,
		mask_h: int, at: Vector2i) -> int:
	var cleared := 0
	var w := image.get_width()
	var h := image.get_height()
	if bits.size() < mask_w * mask_h:
		return 0
	for y in h:
		var my := y - at.y
		for x in w:
			var mx := x - at.x
			# Outside the mask member's own rect is outside the scratch surface's
			# copied region, which was zeroed at creation: hidden, not kept.
			var show := mx >= 0 and my >= 0 and mx < mask_w and my < mask_h \
				and bits[my * mask_w + mx] != 0
			if show:
				continue
			var c := image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
			cleared += 1
	return cleared


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


## Where a decoded true colour sits on a sprite record. The decoder's own names
## (`director_score.gd:FORE_RGB_KEY`), repeated here rather than imported,
## because this file is preloaded by the score reader's own callers and a cycle
## between the two would be a worse cost than two constants.
const FORE_RGB_KEY := "fore_rgb"
const BACK_RGB_KEY := "back_rgb"


## The sprite's ink colour, from whichever of the two things the record states.
##
## A D7 record may carry the colour itself instead of an index into the movie's
## palette (`frame.cpp:readSpriteDataD7`, colour-code bits `0x10`/`0x20`), and
## when it does the palette is not involved at all -- so this is not "look the
## index up more carefully", it is a different source. The reference parses those
## four bytes, copies them between sprites in `replaceFrom`, and then reads them
## nowhere, so it is no use as a specification for what to *do* with one; what a
## true colour means is not in doubt.
static func fore_colour(sprite: Dictionary, palette: PackedByteArray) -> Color:
	if sprite.get(FORE_RGB_KEY) is Color:
		return sprite[FORE_RGB_KEY]
	return colour_of(palette, int(sprite.get("fore_color", INDEX_BLACK)))


## The paper colour, same rule. This is the one that is not only a tint:
## Background Transparent keys every pixel equal to it (2.1, `key_paper`), so
## resolving it through the palette when the record did not mean an index keys
## out the wrong pixels rather than drawing the right ones in a wrong shade.
static func back_colour(sprite: Dictionary, palette: PackedByteArray) -> Color:
	if sprite.get(BACK_RGB_KEY) is Color:
		return sprite[BACK_RGB_KEY]
	return colour_of(palette, int(sprite.get("back_color", INDEX_WHITE)))
