# The non-Lingo half of the Director engine

`docs/LINGO_SURFACE.md` documents the language: handlers, properties, the
built-in function surface. This document is everything underneath it — the part
that runs whether or not the movie has a single line of script.

The reference is ScummVM's `engines/director`, read at master. It is GPL, so
nothing here is copied from it: this is a description of behaviour written from
reading the implementation. Where ScummVM and this port's working renderer
(`director/movie_player.gd`, `sprite_channel.gd`, `render_model_loader.gd`)
agree, that is called out explicitly and should be treated as **settled** —
stop second-guessing it. Where they differ, that is called out too.

**Reading order.** Part I is the visual core — where a sprite lands, how big it
is, what of it is transparent, and whether it appears at all. Nearly every
visible defect traces to one of those four. Part II is everything else the
engine does. Part III is the prioritised gap list and the inventory table.

---

## 0. The one-paragraph model

A Director movie is a **score**: a fixed array of *channels*, each holding one
*sprite* per frame. At runtime the engine keeps ONE persistent array of live
channels, not one per frame. Playing a frame does not build a scene — it
applies the score's frame data as a **delta** onto the live channels, and any
channel a script has claimed refuses part or all of that delta. Most porting
bugs come from implementing that sentence as "rebuild the scene from this
frame's data".

---

# PART I — THE VISUAL CORE

## 1. Positioning and size

### 1.1 The single placement rule

There is exactly one placement function and every cast type goes through it
(`sprite.cpp`, `Sprite::getBbox`, calling `CastMember::getBbox`):

```
regOffset = member.registrationOffset(sprite.width, sprite.height)
bbox      = Rect(sprite.width, sprite.height) with its origin moved to (-regOffset)
bbox      = bbox translated by sprite.startPoint
```

**Screen top-left = startPoint − registrationOffset. Size = the sprite's width
and height.**

`startPoint` is `the locH`/`the locV`. It is *not* the top-left; it is where the
member's registration point is pinned on the stage. For bitmaps the authoring
default registration point is the dead centre of the image, so treating locH/locV
as a top-left displaces almost every sprite by half its size.

The same function serves drawing, hit testing, rollOver, matte generation, mask
alignment and widget creation. **There is one rect.** That is the single most
important structural fact in this section: any port with two rect computations
will eventually have them disagree.

*This port:* `director/movie_player.gd:187-199`
(`_registry_score_stage_position`) implements exactly this expression and
**agrees with ScummVM** — settled. `director/render_model_loader.gd:314-315`
bakes the same thing into the resolved rects at load. But
`scenes/director_preview.gd` has **two** rules: `_scaled_reg` at `:840-849` for
drawing and `_sprite_rect` at `:1007-1013` for hit testing, and they disagree
(§1.7).

### 1.2 Which field is authoritative

In order of authority for the **drawn rect**:

1. **The sprite's own width and height** always win. `getBbox` uses them and
   nothing else. The score's stored rect *is* the sprite's width/height — they
   are the same thing, read from the frame record.
2. **The member's natural size** never directly sets the drawn rect. It enters
   in exactly two places: (a) as the denominator when scaling the registration
   offset (§1.4), and (b) when a cast swap *overwrites* the sprite's width and
   height (§1.3).
3. **The member's `initialRect` origin** enters only through the registration
   offset, which is expressed relative to it.

So when the score's rect and the member's natural size disagree, **the score's
rect wins for the drawn size**, and the member's size still governs how the
registration offset is scaled. This is not a contradiction: the sprite is drawn
at the score's size, and the anchor point within it is placed proportionally.

Two exceptions where the widget overrides the sprite:

- **Text** members push their laid-out width and height *back onto the sprite*
  after the widget lays out, when the text auto-expands. The sprite's stored
  size is overwritten by the widget's. Fixed-dimension fields clamp to the
  member's `initialRect` instead of expanding.
- **Buttons** are constructed at the **member's** `initialRect` width and height,
  using only the bbox's top-left for position. A button sprite stretched in the
  score does **not** draw stretched. This is a real and surprising rule.

*This port:* `director/render_model_loader.gd:229-317` resolves every
unstretched sprite's rect to the member's natural size at load time and
recomputes x/y as `loc − reg`, which normalises the whole problem away for the
working renderer. That is a legitimate strategy and it agrees with ScummVM's
outcome. It does mean the port has no live notion of "the score said one size
and the member is another".

### 1.3 What the stretch flag actually changes

The stretch flag is **bit 0x80 of the ink byte** in the D4 sprite record
(`frame.cpp`, `readSpriteDataD4`; trails is 0x40 and the ink is the low 6 bits).
`director/director_score.gd:21-23` decodes all three correctly.

Stretch does **not** change the drawn size — the drawn size is always the
sprite's width/height, stretched or not. Stretch does **not** change the
registration scaling either; that is driven purely by drawn-versus-natural size
and happens whether or not the flag is set.

What stretch actually changes is **who is allowed to overwrite the sprite's
width and height**:

- On a **cast member swap**, the sprite's width and height are replaced with the
  new member's natural size **only if stretch is clear**. With stretch set, the
  custom dimensions survive the swap. This exists because puppet code routinely
  sets the size first and then the `castNum`, and expects its size to stick.
- Turning stretch **off** explicitly resets the sprite's width and height to the
  member's natural size, and marks the channel dirty.
- Stretch gates the size half of the **dirty test**: a non-stretched sprite's
  width/height changes do not by themselves force a redraw.
- Stretch selects the scaling branch in **film loop** compositing (§1.6).

So the honest summary: **stretch is a "the author has deliberately resized this"
flag, and its effect is to protect the sprite's size from being reset.**

*This port:* `director/sprite_channel.gd:110` captures `stretched` before the
member swap and `:121-126` skips the resize when set — this **agrees with
ScummVM**. Settled. `director/render_model_loader.gd:281-285` uses the same flag
to exempt sprites from rect resolution.

One ScummVM wart worth knowing: `Sprite::getBbox` takes an `unstretched`
parameter, `Channel::replaceWidget` passes `true` to it with a comment about
always using unstretched dimensions — and **the parameter is never read in the
function body**. It is dead. Do not implement it.

### 1.4 Registration offset per cast type, and its scaling

| Cast type | Registration offset |
| --- | --- |
| base / **shape** / **text** / button / anything unspecialised | `(0, 0)` — startPoint is the top-left |
| **bitmap** | `(regX − initialRect.left, regY − initialRect.top)` |
| **film loop** | `(initialRect.width()/2, initialRect.height()/2)` — the centre |
| digital video | `(0, 0)` |

The bitmap subtraction is mandatory. `regX`/`regY` are stored in the Director
editor's virtual canvas coordinates and `initialRect` says where the image sits
on that canvas; raw `regX`/`regY` is correct only when `initialRect.topLeft` is
`(0,0)`. When it is not, every instance of that member is displaced by the
canvas origin — a silent, per-member constant offset that looks exactly like
"some art is placed wrong and some isn't".

**The offset is scaled** whenever the drawn size differs from the member's
natural size. `getBbox` always calls the sized overload, which returns:

```
offset.x * currentWidth  / max(1, initialRect.width())
offset.y * currentHeight / max(1, initialRect.height())
```

A port that applies the unscaled offset to a scaled sprite is wrong by
`(1 − scale) × regOffset` — zero at natural size, growing with the scale. It
reads as the sprite "wandering" rather than as a constant offset, which is why
it gets misdiagnosed as an animation bug. The `max(1, ...)` guard means a member
with a degenerate initial rect gets its offset multiplied by the full drawn size
rather than dividing by zero.

For film loops the sized overload is `(currentWidth/2, currentHeight/2)` —
still the centre, so loops stay self-consistent under scaling.

*This port:* `director/movie_player.gd:192-198` and
`scenes/director_preview.gd:841-849` both implement the proportional scaling
with a **centre fallback** when the member carries no registration point.
ScummVM's fallback is `(0,0)`, not the centre — but ScummVM never has a missing
registration point for a bitmap, because `regX`/`regY` are always read from the
record. The centre fallback is a reasonable choice for members this port failed
to parse; it is a divergence, but a defensive one. Flag it rather than change it.

`director/director_cast.gd:260-269` computes `reg_offset_* = reg − initialRect
origin` — **agrees with ScummVM**. Settled.

### 1.5 The inverse: setting a rect

`Sprite::setBbox` (what `the rect of sprite` writes) sets width and height from
the rect, then back-computes `startPoint = rect.topLeft − memberBbox.topLeft`
using the **new** dimensions — so the registration offset is re-scaled for the
new size before the anchor is derived. It then collapses width and height to
zero together if either goes non-positive.

A port that implements `set the rect of sprite` by storing a top-left will drift
as soon as the sprite is also scaled.

*This port:* `director/sprite_channel.gd:86-97` (`set_loc`) moves the box by the
**delta** rather than re-deriving from the registration point, which preserves
the offset correctly and is equivalent for a pure move. But `set_size` at
`:133-139` writes width/height **without** re-deriving x/y, so a script that
sets the size after the position leaves the anchor stale. That is a real
divergence from `setBbox`. *Change:* in `director/sprite_channel.gd:133-139`,
after writing width/height, recompute x/y from the stored registration point
using the new size.

### 1.6 Film loops: anchor, size, and child placement

A film loop's `initialRect` is the **union bounding box of the loop's contents
in the loop's own score coordinate space**. It is simultaneously the loop's
natural size and the origin its children are measured against.

Compositing a loop (`castmember/filmloop.cpp`, `getSubChannels`) re-bases every
child:

```
childStartPoint' = childStartPoint − loopInitialRect.topLeft + channelBbox.topLeft
```

and then each child goes through the **normal** rule of §1.1 with its *own*
member's registration offset. **Two subtractions**: the loop's initialRect
origin, then the child's registration offset. The loop's own registration
offset (the centre) was already consumed in computing `channelBbox`.

A port that treats a loop's startPoint as a top-left is off by half the loop
size; one that forgets `initialRect.topLeft` is off by the authoring origin; one
that does both is off by their sum, which is why loop misplacement usually reads
as an arbitrary constant rather than an obvious centring error.

When the loop is drawn at a non-natural size, children are scaled per axis by
`bbox / initialRect` **and** — in ScummVM — each child's width and height are
set to the whole widget rect with stretch forced on. That last part is almost
certainly a ScummVM approximation, not authentic Director (§18).

The loop's frame counter is **channel** state, not member state: two sprites
showing the same loop animate independently. A genuine member change resets it
to 1.

*This port:* `director/movie_player.gd:333-342` scales the child position by
`stage_scale` and applies the child's own scaled registration offset —
**agrees with ScummVM**. `scenes/director_preview.gd:822-826` does **neither**:
no scale multiply, and a zero registration fallback instead of the centre. That
is a divergence between the two halves of this port, and ScummVM sides with
`movie_player`.

`director/director_cast.gd:271-289` deliberately writes **no** registration
offset for a loop, with a comment that centring "was a guess and it is wrong",
matching only 19-27% of records — while both renderers centre anyway. This is a
genuine unresolved conflict. Note the two claims are about different things:
ScummVM describes runtime placement; the comment describes agreement with
exported records. Also note ScummVM centres on the **loop's initialRect** size
while `movie_player.gd:223-224` centres on the **sprite record's** width/height,
preferring the member only as a fallback — those diverge exactly when the sprite
is stretched. Settle it by testing placement on screen.

### 1.7 The port's two-rect problem

`scenes/director_preview.gd` computes the drawn top-left with `_scaled_reg`
(`:840-849`: proportional scaling, centre fallback) and the hit rectangle with
`_sprite_rect` (`:1007-1013`: raw offset, **zero** fallback, no scaling). For a
stretched sprite, or any member without a registration point, the clickable
region is not where the sprite is. `lingo_rollover` at `:1037-1048` uses the
same wrong rect.

*Change:* make `_sprite_rect` call `_scaled_reg`. One rect, as in ScummVM.

### 1.8 Flip: the flags exist and ScummVM does not implement them

Horizontal and vertical flip live in the **thickness byte** of the sprite
record: `0x0F` is the line thickness, `0x10` means "has blend", **`0x20` is flip
horizontal, `0x40` is flip vertical**, `0x80` marks the sprite as tweened.

ScummVM parses that byte, copies it between sprites, compares it in the dirty
test — and **never applies the flip anywhere in the render path**. Searching the
whole engine for the flip constants finds only their definition. So:

- Director itself supports sprite flip.
- ScummVM does not, and is not a usable spec for how flip interacts with
  registration offsets or hit testing.
- By construction, since flip is not applied to the bbox in ScummVM, it cannot
  be affecting the hit test there either.

**What a correct implementation almost certainly does** (reasoned, not verified):
flip mirrors the *image within the sprite's rect*, leaving the rect — and
therefore the registration-derived position and the hit rectangle — unchanged.
That is the only interpretation consistent with the flip living in a rendering
attribute byte rather than in the geometry fields. It means the registration
*point* effectively moves relative to the artwork, which is the visible
consequence: an off-centre character flipped horizontally appears to shift.

*This port:* the thickness byte is not decoded at all in
`director/director_score.gd` — there is no flip, no blend flag, no thickness.
*Change:* decode byte 4 of the sprite record in
`director/director_score.gd:_snapshot` alongside the ink byte, and expose
`flip_h`/`flip_v`. Rendering is then a negative scale on the destination rect
about its own centre. **Worth checking early:** if the original flips walk-cycle
art rather than shipping mirrored art, ignoring the flag makes characters face
the wrong way, and that would present exactly as "walk cycles are wrong".

### 1.9 Rotation and skew: D7 only, and unimplemented

`_angleRot` and `_angleSkew` exist on the sprite and are read from the frame
record **only in the D7+ sprite parser** (`frame.cpp`, around the D7 read).
They are stored, copied and written back on save, and **never used in
rendering**.

Plainly:

- **D4 has no sprite rotation or skew at all.** Neither does D5 or D6 at the
  score level. A D4 title cannot rotate a sprite; anything that looks rotated is
  pre-rendered art or a film loop.
- **D7 stores rotation and skew per sprite**, and ScummVM does not render them.
- A port targeting D4 can ignore this entirely. A port targeting D7 must
  implement it from documentation, not from ScummVM.

### 1.10 Rounding and sub-pixel

Director is integer throughout. The sprite record stores 16-bit integers for
position and size. Every derived quantity is integer arithmetic:

- the scaled registration offset is an integer multiply-then-divide, i.e.
  **truncation toward zero**, not rounding — and for a negative offset that
  truncates *upward*;
- the film loop centre is integer division;
- film loop child positions are computed in float and then **assigned to
  int16**, i.e. truncated.

There is no sub-pixel positioning anywhere.

The critical property is not the rounding mode but that **drawing and hit
testing use the same function**, so they round identically. A port that draws
in floats and hit-tests on a rounded rect introduces a one-pixel disagreement at
the edges that shows up as "the very edge of the button doesn't work".

*This port:* both renderers compute in floats and draw in floats
(`director/movie_player.gd:554-557`, `scenes/director_preview.gd:603-617`).
`director/movie_player.gd:230` does `floor()` the film loop parent origin, which
matches integer division for positive values. *Change (low priority, but real):*
floor the computed top-left once, and derive the hit rect from the same floored
value.

---

## 2. Ink, matte and transparency

### 2.1 The ink numbers

`types.h`, `enum InkType`. Numbers 10-31 are unused.

| # | Ink | Render | Hit test |
| --- | --- | --- | --- |
| 0 | Copy | source through, or colourised (§2.3) | rect |
| 1 | Transparent | black→fore, else keep dst; or bitwise OR | rect |
| 2 | Reverse | XOR dst with src; or key on backColor | rect |
| 3 | Ghost | black→backColor, else keep dst | rect |
| 4 | Not Copy | inverted source, or fore/back swapped | rect |
| 5 | Not Transparent | white→fore, else keep dst; or OR with inverse | rect |
| 6 | Not Reverse | see §2.4 | rect |
| 7 | Not Ghost | white→backColor, else keep dst | rect |
| 8 | **Matte** | masked by flood-fill mask, survivors as Copy | **per pixel** |
| 9 | **Mask** | masked by the *next cast member* (§2.6) | rect |
| 32 | Blend | alpha lerp; degrades to Matte with no factor | rect |
| 33 | Add Pin | arithmetic, clamped | rect |
| 34 | Add | arithmetic, wrapping | rect |
| 35 | Sub Pin | arithmetic, clamped | rect |
| 36 | **Background Transparent** | key out the sprite's backColor | **rect** |
| 37 | Light | arithmetic | rect |
| 38 | Sub | arithmetic | rect |
| 39 | Dark | arithmetic | rect |

**Render and hit test are different tables and that asymmetry is deliberate.**
Only ink 8 (Matte) hit-tests per pixel. Background Transparent renders per-pixel
and hit-tests as a full rectangle. A port that makes every transparent-looking
ink per-pixel lets clicks fall through backdrops that should catch them; one
that makes everything rectangular lets irregular matte sprites steal clicks.

*This port:* `director/render_model_loader.gd:23-25` classifies inks 8 and 9 as
Matte and 1, 36, 39 as Background — note that puts Transparent (1) and Dark (39)
in the background-key bucket, which is an approximation, and Mask (9) in the
matte bucket, which is wrong in kind (§2.6) though harmless if no member uses
it. The reasoning at `:12-19` — ink 36 dominates the corpus and treating it as
Matte left white patches — is sound and is exactly the distinction in §2.5.

`director/render_model_loader.gd:829` masks the ink with `& 0x3f` before the
lookup. `scenes/director_preview.gd:673-676` does **not**, so any sprite with
the trails (0x40) or stretch (0x80) bit set is misclassified and renders opaque.
*Change:* mask before the lookup in `_texture_for`.

### 2.2 The colour vocabulary

In 8-bit CLUT mode Director's convention is inverted from the intuitive one:
**white is palette index 0, black is palette index 255**. ScummVM returns those
indices literally rather than searching the palette, because a palette can hold
several entries that are also white or black and the ink rules key on the exact
index.

Each sprite carries a **foreColor** and a **backColor**, both defaulting to
white, both read from the *member* rather than the sprite for text and buttons.
These are the sprite's colours, not the image's.

*This port:* `director/director_palette.gd:20-21` defines paper as index 0 and
ink as 255, and `:39-61` builds the cube descending so entry 0 is exactly white
and writes black explicitly at 255 — **agrees with ScummVM**. Settled. The note
at `:14-15` about assuming the cube alone put black at 215 is the same trap
ScummVM avoids by returning the index literally.

`director/director_score.gd:248-249` decodes the sprite's fore and back colour
and **nothing consumes them** — see §2.3.

### 2.3 applyColor: every ink has two modes

Before any pixel is touched, `setApplyColor` chooses between Director's two
rendering modes:

- **default** — use the full range of colours in the image;
- **applyColor** — reduce the image to a combination of the sprite's current
  foreground and background colour.

The switch:

- Matte, Mask, Copy, Not Copy → applyColor when `foreColor != black` **or**
  `backColor != white`;
- Transparent, Not Transparent, Background Transparent, Ghost, Not Ghost →
  applyColor when **not** (`foreColor == black` **and** `backColor == white`);
- everything else → never.

Practically: **a sprite with default colours renders its bitmap unmodified; a
sprite with non-default colours has its black pixels repainted foreColor and its
white pixels repainted backColor.** This is Director's colourisation mechanism,
and it is why one 1-bit cast member appears in a dozen colours across a movie
without a dozen bitmaps existing.

Text and button sprites disable applyColor at blit time and colourise in a
preprocessing step instead.

One thing worth noticing about the switch above: the two clauses are the same
condition written two ways — "fore != black **or** back != white" and "**not**
(fore == black **and** back == white)" are equivalent. So nothing distinguishes
the two ink groups except membership; every ink outside both lists never applies
colour.

*This port:* the container-reading preview implements it —
`director/director_ink.gd:applies_colour` / `apply_colour`, called from
`scenes/director_preview.gd:_texture_for` **after** keying rather than before,
because a matte is flooded from white and repainting the whites first leaves the
flood nothing to match. The cache key carries both colours. Colourisation is
applied to a decoded RGBA image and leaves every pixel that is neither pure black
nor pure white alone — the conservative half of the reference's Copy rule, which
would otherwise punch holes.
`director/render_model_loader.gd:_apply_transparency`, the other renderer, still
drops the colours.

**How much this is worth, measured** (`tools/draw_survey.gd -- --all`, 816,318
sprite records in 61 movies): 50,714 records carry non-default colours on an ink
that admits applyColor, and **50,063 of them name shape members**, which are
painted by the shape primitives instead (§13) and never reach this code. Only
**651 records — 7 distinct sprites — are bitmaps**, and **no field sprite in the
corpus has non-default colours at all**. Colourisation and text rendering look
like one piece of work and are not.

### 2.4 The inks at pixel level

`src` is the source pixel, `dst` the destination.

- **Copy** — applyColor off: write `src`. On: black→fore, white→back, **and
  every other pixel is left as the destination**. That last clause surprises
  people: a colourised Copy of multi-colour art punches holes.
- **Matte**, **Mask**, **Blend** (no factor) all fall through to the Copy code.
  Matte is not a per-pixel colour test at all (§2.5).
- **Background Transparent** — the paper colour is the **sprite's backColor**;
  a pixel equal to it leaves the destination, anything else is copied. **1-bit
  images are special-cased**: the comparison is against *black* and the result is
  *foreColor*, with backColor ignored entirely. If a mask is present the pixel is
  copied unconditionally.
- **Not Copy** — with applyColor: black→back, white→fore (the swap), others pass
  through. Without: the source colour is inverted channel-wise and re-matched to
  the palette. In 32-bit the applyColor branch degenerates to a plain copy.
- **Transparent** — with applyColor or a 1-bit image: black→fore, else keep
  destination. Otherwise a genuine bitwise **OR** of destination with source in
  8-bit (which is what makes white transparent in a 1-bit context), and an
  **AND** in 32-bit.
- **Not Transparent** — as Transparent, keyed on white, OR-with-inverse.
- **Reverse** — 8-bit **XOR** of destination with source for 1-bit/applyColor/
  shape cases; otherwise "pixel equal to backColor leaves the destination".
- **Ghost** — black→backColor, else keep destination. **Not Ghost** —
  white→backColor.
- **Add / Add Pin / Sub / Sub Pin / Light / Dark** — arithmetic in decomposed
  RGB, re-matched to the palette; Pin variants clamp rather than wrap.

The **fallback chain** matters more than the exotic inks: Blend degrades to
Matte, Matte and Mask degrade to Copy, and default colours degrade to a plain
blit. Implementing Copy + Background Transparent + Matte correctly and mapping
everything else to **Copy** is a defensible strategy. Mapping the remainder to
Background Transparent is not — it will key out artwork.

**Depth:** 1-bit images get their own branches in Background Transparent,
Transparent and Reverse, and are exempted from matte generation for every ink
except Matte itself (a 1-bit Copy sprite additionally has its blend amount forced
to zero, because 1-bit images do not blend the way 8-bit ones do). 8-bit is the
palette-index path described above. 16- and 32-bit take the RGB paths, where
several inks behave differently (Not Copy, Transparent, Not Transparent all
diverge). A port that decodes everything to RGBA8 before compositing is
effectively always on the "higher depth" path and must decide deliberately which
version of each ink to reproduce — the 8-bit palette-index semantics are the
ones a D4 title was authored against.

### 2.5 How the matte mask is built

Matte is a **mask**, not a colour test. `Channel::getMask` produces a
one-byte-per-pixel mask and the blit loop **skips** masked-out pixels; survivors
take the Copy path.

Construction (`castmember/bitmap.cpp`, `createMatte`):

1. The member's image is stretched into a scratch surface **at the channel's
   current bbox size**. The matte is therefore size-specific, not a property of
   the member alone.
2. **The paper colour is found by scanning only the border ring** — every pixel
   of the four edges, skipping the interior — for a palette entry whose RGB is
   exactly `0xFF,0xFF,0xFF`. It matches on the **RGB value** and then uses the
   **palette index** it found for the fill. In non-CLUT modes it is simply white.
3. **If no white is found on the border, no matte is built at all**, the member
   is flagged as having none, and the sprite renders and hit-tests as a solid
   rectangle. This is a real behaviour, not an error path.
4. A flood fill is seeded from **every pixel of all four borders** — the whole
   perimeter, not just the corners.
5. **Connectivity is four-way** and **the colour test is exact — there is no
   tolerance.** A dithered or resampled background will not flood and the matte
   will come out nearly solid.
6. The result is inverted into Director's mask convention: **0x00 transparent,
   0xFF opaque.**

Because the fill can only reach from the outside, **white pixels enclosed by
coloured pixels stay opaque**. That is the entire difference between Matte and
Background Transparent: a donut with a white hole keeps its hole under Matte and
loses it under Background Transparent. It is also why Matte needs a flood fill
rather than a colour key.

**Caching:** the matte is cached on the **cast member**, and regenerated
whenever the requested bbox size differs from the cached mask's size. A sprite
that animates its scale therefore triggers a full flood fill per size change.

Which inks need a matte: Matte, Not Copy, Not Transparent, Not Reverse, Not
Ghost, Blend, Add, Add Pin, Sub, Sub Pin, Light, Dark — plus Copy when the sprite
has a blend factor.

*This port:* `director/render_model_loader.gd:765-794` seeds every border pixel
(agrees), uses four-connected expansion with an explicit stack (agrees), and
caches per member **keyed by transparency mode** at `:642-645` (a refinement
ScummVM lacks, and a good one). It diverges on the paper colour: it starts from
pure white and **adds each near-white corner** (`:770-774`), and matches with a
**tolerance of 14/255** (`:26`, `:815-821`). ScummVM scans the whole border and
matches exactly.

`scenes/director_preview.gd:1383` is worse: it takes the paper colour from
**pixel (0,0) alone**, then accepts near-paper *or* near-white (`:1406-1416`).
A member whose top-left corner is artwork keys the wrong colour.

*Changes, in order:* (1) in `scenes/director_preview.gd:_key_matte`, replace the
single-pixel sample with the loader's corner voting at minimum, ideally a full
border scan; (2) in both, add the **"no white on the border → no matte, render
as a rectangle"** rule, which is currently missing everywhere and silently
produces a garbage mask for art with no white edge; (3) consider tightening the
tolerance toward exact, since 14/255 will eat near-white artwork that Director
would have kept.

### 2.6 Mask ink is a different mechanism entirely

Ink 9 uses **the next cast member by number** (`castId + 1`) as a 1-bit mask
bitmap. That member must exist and must be 1-bit. The mask is composited into a
surface the size of the channel, aligned by registration offset and clipped.

This is a genuine authoring idiom. A port that ignores it will render the mask
member as a stray sprite somewhere in the cast, or drop the masked sprite.

*This port:* `director/render_model_loader.gd:23` lumps ink 9 in with Matte.
Harmless if nothing uses it; wrong in kind if anything does. Worth a grep of the
score data for ink 9 before deciding.

### 2.7 Blend and alpha

A blend factor comes from either the ink being Blend (32) or the **has-blend
flag (0x10) in the thickness byte**. The blend path lerps source and destination
in decomposed RGB and **returns before the ink switch**, so blending ignores
colourisation and behaves as Matte regardless of the nominal ink. Blend amount is
a normal delta-copied sprite field.

Blend is D5-era and later in practice; a D4 title will rarely use it. It is not
D7-specific.

*This port:* the blend amount and the thickness byte are not decoded at all
(`director/director_score.gd` reads bytes 1, 2, 3, 12, 14, 16, 18 but not 4 or
19). *Change:* decode byte 4 (thickness/flags) and byte 19 (blend amount) in
`_snapshot`.

---

## 3. Visibility: every way a sprite fails to appear

Ordered by how easy each is to miss. The column that matters is whether it also
suppresses the **hit test**, because a sprite that is invisible but still
clickable is one of the nastiest bugs to diagnose.

| Cause | Drawn? | Hit-tested? |
| --- | --- | --- |
| channel `_visible` false (`the visible of sprite`) | no | **no** — `isMouseIn` returns No first thing |
| `_hideFromStage` (debugger only) | no | **YES, still clickable** |
| width or height ≤ 0 | no | no — empty rect |
| sprite type is Inactive (0) | no | rect test still runs if the rect is non-empty |
| **cast member missing / unresolvable** | no | **YES, still clickable** |
| **sprite type and cast type disagree** | no | **YES, still clickable** |
| ink transparency (Background Transparent, Copy of white art) | pixels invisible | **YES — rect test** |
| Matte ink, transparent pixel | pixel invisible | no, at that pixel |
| blend factor 0 with Blend ink | invisible | yes |
| behind an opaque higher channel | occluded | the higher sprite is found first *only if it is eligible* (§4) |
| palette makes the colours equal the background | invisible | yes |
| during a transition | partially composited | n/a, events are pumped |

The three "YES, still clickable" rows are the important ones:

- **`_hideFromStage`** is checked in `renderChannel` but not in `isMouseIn`. In
  ScummVM it is a debugger affordance, so it does not matter there — but a port
  that reuses a "hidden" flag for game logic will get invisible click targets.
  Keep `visible` and any debug-hide flag distinct, and make game-level hiding use
  `visible`.
- **A missing cast member** produces no surface and therefore no pixels, but the
  sprite's width, height and startPoint are still whatever the score said, so the
  bbox is real and the rect test passes. In Director this is how a sprite
  "disappears" without becoming click-through.
- **Sprite/cast type mismatch** (`checkSpriteType`) makes the sprite render as
  fully transparent — deliberately, as a compatibility behaviour for movies with
  bad data — while leaving it clickable.

Zero-size deserves its own note: the D4 sprite parser **collapses width and
height to zero together** if either is non-positive, explicitly because removed
sprites leave garbage in the channel. `Sprite::setBbox` does the same. So
"either dimension is zero" and "both are zero" are the same state, and a port
should normalise the same way rather than carrying a 0×40 rect around.

*This port:* `director/director_score.gd:230` treats `cast_id <= 0 or width <= 0
or height <= 0` as unoccupied, which folds the collapse and the missing-member
case together — reasonable, and it means missing members are *not* clickable
here, a deliberate divergence from Director that is almost certainly the better
behaviour for a preview.

`director/sprite_channel.gd:37` keeps `visible` as channel state surviving frame
entry — **agrees with ScummVM**. Settled.
`director/director_runtime.gd:1426-1427` skips hidden channels in click
eligibility, and `:1506-1507` in cursor resolution. `scenes/director_preview.gd`
has no visibility concept in `_channel_at` at all (`:966-976`).

---

# PART II — THE REST OF THE ENGINE

## 4. Mouse hit testing

### 4.1 Three different queries

| Query | Extra filter | Used for |
| --- | --- | --- |
| `getSpriteIDFromPos` | none | raw "what is under the pointer" |
| `getMouseSpriteIDFromPos` | `respondsToMouse()` | click and hover routing, **D4+** |
| `getActiveSpriteIDFromPos` | `isActive()` | click and hover routing, D3 and below |
| `getRollOverSpriteIDFromPos` | rollOver bbox (§4.5) | `the rollOver` |

The version split happens once, at the event entry point. Piposh 2 is D4-era, so
`respondsToMouse` is the rule.

### 4.2 The search, exactly

Descend channels from **highest index to 0** — channel number is paint order.
For each, `isMouseIn(pos)` returns one of three values:

- **Yes, and the eligibility predicate passes** → return it. Done.
- **Yes, but the predicate fails** → **keep descending.** The sprite does not
  absorb the click.
- **Hole** → **abort the entire search**, return 0.

Falling off the bottom returns 0.

The middle case is the whole answer to "the preview picks the backdrop". **An
ineligible sprite is transparent to the mouse no matter how opaque it is.** A
full-screen backdrop with no script does not block the button under it.

`kCollisionHole` comes from exactly one place: a **text** member returns it when
the point is over its scrollbar arrows, so a scrollbar swallows the click without
being a target. Nothing else produces it. Even with no text fields, write the
loop with the three-way result — otherwise adding fields later silently changes
click routing.

### 4.3 Eligibility

`respondsToMouse()` is true if **any** of: the sprite is **moveable**; the
member is a **button**; the member is a **movie** with scripts enabled; (D6+)
the sprite has behaviours; a **score script** on the sprite's script id
*contains* a `mouseDown`, `mouseUp` or generic handler; a **cast script** for the
cast id *contains* `mouseDown` or `mouseUp`.

Two traps. It is **not enough that the script id is non-zero** — the handler must
exist in the compiled script, so a sprite whose script only defines `mouseEnter`
is not a click target. And **moveable alone qualifies**, with no script at all.

`isActive()` is the looser D3 rule: moveable, or a button, or a score script
*exists*, or a cast script *exists* — presence only, no handler inspection.

### 4.4 Ink participation

`isMouseIn`: not `_visible` → No; else compute the bbox (§1.1); else delegate to
`cast->isWithin(bbox, pos, ink)`, or a plain rect test if there is no member.

Per type: bitmap does rect-then-matte-if-ink-is-Matte; text does rect plus the
scrollbar Hole; everything else is a rect. See §2.1 for the full table.

### 4.5 rollOver is looser

`the rollOver` uses `getRollOverBbox()`, which in **D4 and below** returns the
*last non-empty* bbox when the channel's cast id is currently 0 — a sprite the
score has blanked still rolls over its old rectangle. That cache is refreshed
every frame change for every channel with a non-zero cast id, pre-D5 only. D5+
uses the live bbox. `checkSpriteRollOver` is a pure rect test — no matte, no
eligibility.

### 4.6 Hilite

`shouldHilite()` requires `isActive()`, and requires **not** moveable and
**not** puppet. For a bitmap in D3+ it is driven by the member's **auto-hilite**
info flag, falling back to "ink is Matte" when there is no cast info. QuickDraw
shapes hilite when ink is Matte. The inversion is a masked XOR of the
destination through the sprite's matte, so an irregular sprite inverts its
silhouette, not its box.

*This port:* `director/director_runtime.gd:1426-1447` implements eligibility and
`:1080-1083` a first-hit rect test with no per-pixel stage.
`scenes/director_preview.gd:966-976` is the inverse: per-pixel, no eligibility,
and its comment at `:959-964` already names the gap. Neither has hilite or the
rollOver cache. See §17.1.

---

## 5. Puppet state

### 5.1 The score applies a delta

One persistent `Channel` per score channel, each owning a live `Sprite`. Each
frame, `Score::updateSprites` calls `Channel::setClean(nextSprite)`, which funnels
into `Sprite::replaceFrom`.

`replaceFrom` does **not** copy the whole sprite. Each field is copied only if
its bit is set in the incoming sprite's **copy-back mask** — a bitfield built
while *parsing* the frame's delta record, recording which fields the score
actually wrote this frame. Untouched fields keep their live values. Afterwards
every frame sprite's mask is reset to "all bits", so a later full re-read behaves
like a full copy.

**Consequence here:** an export storing a complete sprite record per frame has
thrown the delta away. Replaying it as a full assignment is usually
indistinguishable — a tweened sprite does have all its fields written — but it is
exactly wrong for a channel a script has written, and for `puppetSprite N, FALSE`.

### 5.2 Whole-sprite puppet

If `_puppet` is set, `replaceFrom` copies **the script id, the behaviour list and
the sprite-info record, then returns**. Nothing else. Cast member, position,
size, ink, colours, moveable, blend — all preserved from the live channel.

So: it preserves *everything visual* and re-reads only *script attachment*. That
is not an accident; it is how a puppeted sprite still picks up per-frame
behaviour from the score.

*This port:* `director/sprite_channel.gd:58-59` and `:66-67` skip the whole
reconcile when puppeted — **agrees with ScummVM in outcome**, though it also
skips the script-id copy. Settled enough; add the script-id copy if frame-scoped
sprite scripts ever matter.

### 5.3 Per-field auto-puppet (D6+)

D6 auto-puppets individual properties on write, without setting the whole-sprite
flag. `replaceFrom` guards each field with both its copy-back bit and its
auto-puppet bit. Auto-puppet is **released** when the score itself writes that
property — checked every frame change against the incoming mask, with height and
width released by a *cast id* write as well as by an explicit size write.
Inert below D6, but the shape matters: it is the same "block the score per field"
idea that whole-sprite puppet does coarsely.

*This port:* `scenes/director_preview.gd:911-941` implements per-field overrides
with a staleness reset keyed on the cast id — closer to D6 auto-puppet than to D4
whole-sprite puppet. `director/sprite_channel.gd:18-24` explicitly declines
implicit puppeting. The two halves disagree about what puppeting means.

### 5.4 Hand-written persistence rules

Three fields ignore the mask: **editable** is preserved if the cast id did not
change; **immediate** is always preserved; **width/height** are copied when the
score writes a **cast id**, even without a size write, because changing member
implies re-fitting.

### 5.5 What resets it

`reset()` clears the puppet flag (movie load). Turning the flag off in Lingo
restores nothing itself — it stops blocking, and the next frame's delta flows in;
because the masks were reset to "all bits", that first frame copies everything,
which is the intended "revert to the score". Auto-puppet is released per property
by the score. **Nothing in the frame loop clears whole-sprite puppet
implicitly** — it survives frame jumps and `go to`, and dies only when the movie
changes and channels are rebuilt.

*This port diverges:* `scenes/director_preview.gd:1317-1318` **discards** the
overrides on `puppetSprite N, FALSE`, and `:1073-1074` / `:1143` clear all
overrides on room and movie change. `director/sprite_channel.gd:71-74` keeps the
contents until the next reconcile, which matches Director. The preview's discard
is observably different: Director reverts on the *next frame's delta*, not
instantly.

### 5.6 The dirty test is puppet-aware

`isDirty` compares live against incoming — **only for non-puppet channels**. For
a puppeted channel the comparison is skipped and the dirty flag must be set by
whatever wrote the sprite. A port that computes "did anything change" by diffing
frame data will never redraw a puppeted sprite a script moved. Position is
excluded for *moveable* sprites; size counts only when stretched.

---

## 6. Frame and render ordering

### 6.1 The tick

`Score::step` then `Score::update`:

1. **Input events** dispatched from the queue, unless a jump is pending.
2. **idle**.
3. (D6+) `mouseWithin`, sound cue points.
4. **Sound fades** stepped.
5. **timeout** check, independent of the frame delay.
6. **Wait check** — clock, wait-for-click, wait-for-sound, wait-for-video. If
   waiting, the update ends here; video still gets a widget update and a render.
7. **exitFrame** for the frame being left — *not* if it is being left by a
   `go to`.
8. `the delay` check.
9. Expiring behaviours killed.
10. **`updateCurrentFrame`** — resolve the next frame number, cache rollOver
    bboxes (pre-D5), **load the frame**, release auto-puppets, and
    **`updateSprites`** to apply the delta and flag channels for drawing.
11. **`updateNextFrameTime`** — decode the tempo channel (§10.1).
12. **perFrameHook**, and D5+ `stepFrame` to the actorList — *unless* this frame
    has a transition, in which case it runs once per transition subframe.
13. (D6+) **prepareFrame**.
14. **`renderFrame`** — the draw (§6.2).
15. **stepMovie** (D3, or D4+ with outdated-Lingo compatibility).
16. **enterFrame**.
17. **Immediate sprite scripts**.
18. Frozen-script resumption.

Compressed: **sprite state is updated from the score first, then the frame time
is computed, then the frame is drawn, and `enterFrame` runs after the draw.**
ScummVM cites *Lingo in a Nutshell*: the window is drawn between `prepareFrame`
and `enterFrame`. `exitFrame` for frame N runs at the *start* of the tick that
advances past it, not at the end of N's own tick.

A port running `enterFrame` before the draw shows one frame of lag on everything
it changes. A port running `exitFrame` and `enterFrame` in the same tick runs
both against the same rendered state, which breaks the standard "set up in
enterFrame, tear down in exitFrame" idiom.

Almost every step checks whether a script **froze** and bails out of the rest of
the tick. That is how Director makes blocking Lingo work without threads
(§10.4).

### 6.2 renderFrame

Sound channels start first (in parallel with any transition). Then exactly one
of: transition skipped → increment film loops, render; playback paused → update
sprites, increment loops, render; a transition applies → play it, which renders
itself; otherwise → pre-palette-cycle, set palette, update sprites, **increment
film loops**, render, then the palette cycle. Finally queued sound and a cursor
refresh if flagged.

**Film loops advance inside the render step**, immediately before the window
render, and not while playback is paused. In **D4 a loop freezes while an
explicit jump holds the playhead on one frame** — a natural single-frame loop
still advances it. D5+ always animate. Movie cast members always step.

### 6.3 Window::render and dirty rects

Channels are walked in **ascending** order. For each flagged `_needsDraw`:
re-render the region it occupied **last** frame (unless it was a trails sprite),
re-render the region it occupies **now**, clear the flag, record the new bbox.

"Re-render a region" collects every channel intersecting that rectangle, moves
direct-to-stage video to the end, fills with the **stage colour**, then ink-blits
each intersecting channel in ascending order, clipped. Film loop and embedded
movie sub-channels expand inline at the parent's position in the order.

**Trails** invert the first step: no erase, and the composite starts *at* the
trails channel rather than filling the background, so everything below stays.
That is the whole mechanism.

The structural point for a retained-scene-graph port: Director is an
**immediate-mode painter with explicit dirty rectangles**, and trails,
direct-to-stage video and destination-reading inks (Reverse, Transparent's
bitwise mode, Add/Sub) only make sense in that model.

*This port:* `director/director_runtime.gd` splits exitFrame (top of `game_step`)
from enterFrame (inside `enter_frame`), which is right in shape but has no
`prepareFrame` or `stepFrame`. `scenes/director_preview.gd:515-517` fires
`prepareFrame`, `enterFrame` and `exitFrame` back to back on one frame, then
advances — see §17.5. Both redraw everything every frame with no dirty rects,
which is the right trade in Godot but forecloses destination-reading inks.

---

## 7. Cursor

### 7.1 Built-in numbers

| N | Cursor |
| --- | --- |
| −1, 0 | arrow (the default) |
| 1 | I-beam |
| 2 | crosshair |
| 3 | crossbar / thick plus |
| 4 | watch |
| 200 | blank — hidden |

Any other integer is a **resource id**, looked up as `CURS` or `CRSR` in the
current cast's archive, then every open resource file, then (Mac only) the main
archive. Failing that, the value is masked to its low 7 bits and retried as a
built-in, so a bad id degrades to a visible cursor. Windows before D5 does not
attempt resource cursors at all.

**"Empty" is a distinct state**: a cursor counts as empty when its resource id
is the integer 0 and not a list. That is what lets a channel fall through to the
global cursor. `cursor 0` means "clear", not "arrow explicitly".

### 7.2 Custom cursors from cast members

A **list of one or two cast member references, in the order `[data, mask]`**.
Element 0 is the image, element 1 the mask. Both must be **bitmap** members; a
non-bitmap data member aborts the assignment, a non-bitmap mask is ignored and a
maskless cursor is built. One element is legal.

### 7.3 Compositing and hotspot

Fixed **16×16 cropped from the top-left**; larger members are cropped, smaller
padded transparent. Per pixel: outside bounds → transparent; mask pixel
**black** → opaque, colour from the data member (black→black, white→white); mask
pixel **white** → transparent; no mask → all in-bounds pixels opaque. So the
**mask member's black region is the visible silhouette**.

*This port:* `director/render_model_loader.gd:847-911` does exactly this —
**agrees with ScummVM**. Settled; do not change it.

**Hotspot** comes from the *data* member's registration point as
`(regX − initialRect.left, regY − initialRect.top)` — the §1.4 expression, not
raw regX/regY. Two rules missing at `:901-904`:

1. A hotspot **outside** the 16×16 crop is **recentred to (8,8)**. The port only
   falls back to the centre when the registration point is *absent*.
2. **Windows Director before D5 ignores custom hotspots entirely** and always
   uses (8,8). If this build targets the Windows original that may be correct for
   every cursor, and would explain any systematic "the cursor points slightly
   off" feel.

### 7.4 Precedence

No cursor channel exists. Two sources, resolved in `Score::renderCursor`:

1. **Wait-for-click overrides everything** — the cursor is forced to an
   alternating up/down "click me" pair toggling once per second.
2. Otherwise **descend channels highest to 0**; take the first where the point is
   inside (same three-way result, Hole aborts) **and** the cursor is non-empty.
3. Otherwise the score's **global default cursor**, set by the `cursor` builtin.

Sprite beats global; higher channel beats lower; an empty channel is skipped.
Note the descent does **not** filter on `respondsToMouse` — a non-clickable
sprite with a cursor still changes it. Cursor eligibility and click eligibility
are different tests over the same stack.

### 7.5 Lifetime and cadence

`the cursor of sprite N` lives on the **channel**, not the score sprite, and is
not part of the frame delta — it survives frame changes, cast swaps and score
updates, exactly like `the visible of sprite`.
`director/sprite_channel.gd:42` already models it that way. **Agrees.**

**The cursor is not recomputed per frame.** Only on: every mouse move;
mouse-up; the cursor entering the window (forced); a new movie starting
(forced); and when a "cursor dirty" flag is set, checked at the end of each
rendered frame. Even then it is pushed to the OS only if it **differs** from the
displayed one, compared by (type, resource id).

So if the member under a **stationary** cursor changes, **nothing happens** until
the mouse moves or the dirty flag is set.

### 7.6 Moveable sprites and drag

`_moveable` is a delta-copied field written together with `editable` and the
colour code under one mask bit (byte 18 of the D4 record: 0x40 editable, 0x80
moveable). Effects: it makes the sprite click-eligible on its own; mouse-down
records the dragged channel and the click-to-position offset, and every
mouse-move sets position to `offset + mouse` and marks dirty, ending on mouse-up
or when the sprite stops being moveable; moveable sprites are excluded from the
position half of the dirty test; moveable suppresses hilite; and
`Channel::setPosition` applies **`the constraint of sprite`**, clamping the new
position into the constraint channel's rollOver bbox. It clamps the *position
point*, not the rect, so a sprite can overhang the constraint by its registration
offset. That is how sliders and drag-in-a-tray are authored.

### 7.7 Editable sprites

Effective editability is `sprite editable OR member editable`. Preserved across a
frame when the cast id is unchanged. The **first** editable text sprite becomes
the active widget unless one already holds focus. Auto-expanding text pushes the
widget's size back onto the sprite and marks dirty, which is why text sprites are
excluded from the dimension-change test elsewhere.

---

## 8. Keyboard, focus and the event hierarchy

This port has none of it.

### 8.1 The event vocabulary

Movie: `prepareMovie` (D6), `startMovie`, `stepMovie`, `stopMovie` (D3),
`startUp`. Sprite lifetime: `beginSprite`, `endSprite` (D6). Frame:
`enterFrame` (D4), `prepareFrame` (D6), `idle` (D3), `stepFrame` (D5),
`exitFrame` (D4). Window: `activateWindow`, `deactivateWindow`, `moveWindow`,
`resizeWindow`, `openWindow`, `closeWindow`, `zoomWindow` (D5). Input:
`keyUp` (D4), `keyDown` (D2 as a when-clause, D4 as a handler), `mouseUp` /
`mouseDown` (D2 when, D3 handler), `rightMouseDown` / `rightMouseUp` (D5),
`mouseEnter` / `mouseLeave` (D5/D6), `mouseUpOutSide` (D6), `mouseWithin`
(D5/D6). Other: `timeout`, `cuePassed` (D6).

### 8.2 The hierarchy

In **D4+** an event is queued as a *sequence* of candidates in precedence order
and the first that handles it consumes the event, unless it calls `pass`:

**primary handler → sprite script → cast member script → frame script → movie
scripts.**

- **Primary handlers** exist only for `mouseDown`, `mouseUp`, `rightMouseDown`,
  `rightMouseUp`, `keyDown`, `keyUp` and `timeout`. They are set from Lingo as
  `the mouseDownScript`, `the keyDownScript` and so on: the value is a **string
  of Lingo source**, compiled and registered under a synthetic slot keyed by
  event type. The crucial difference from a normal handler is the default —
  **a primary handler passes the event on by default** and must call
  `dontPassEvent` to stop it, while every other level consumes by default and
  must call `pass` to continue. Getting this inverted is the classic bug.
- **Sprite script** runs only when the event resolved to a sprite.
- **Frame script** — per the D4 docs, `enterFrame`, `exitFrame`, `idle` and
  `timeout` go to the frame script then a movie script; with no frame script the
  message goes straight to movie scripts.
- **Movie scripts** are searched in cast-window order, then the shared cast;
  first one containing the handler wins.

With the event **not** over a sprite, the sprite and cast levels are skipped and
the message starts at the frame script.

**D3 and below have no passing**: `mouseUp`/`mouseDown` go to sprite then cast;
`exitFrame` to the frame; `idle`/`startMovie`/`stepMovie`/`stopMovie` to movie
scripts; `keyUp`/`keyDown`/`timeout` are handled *only* by the primary handler.

### 8.3 Keyboard routing

`keyDown`/`keyUp` are dispatched with the channel id of **the sprite owning the
active widget**, not the sprite under the mouse. With no focus the channel is 0
and the message starts at the frame script. So keyboard reaches a sprite script
only for a focused editable field.

`the key` is the ASCII character; `the keyCode` the platform key code. Arrow keys
are special-cased into `the key` as characters 28 (left), 29 (right), 30 (up),
31 (down) — a real quirk, since most non-letter keys do not affect `the key`.

**Modifier keys do not generate keyDown events** — shift, control, option/alt and
command/super are recorded into a flag word and return without dispatching.
`the commandDown`, `optionDown`, `shiftDown` and `controlDown` read that same
word and are **independent booleans**; they combine by being read separately, not
by being encoded into `the keyCode`. On Mac in D5+, control-click is optionally
emulated as a right click. A key event also refreshes the timeout clock when
`the timeoutKeyDown` is set.

### 8.4 Editable fields, focus and selection

Focus is the window manager's "active widget". `setEditable` claims it **only if
no editable widget already holds it**, so the first editable field in channel
order wins. `the selStart` and `the selEnd` are **movie-level**, not per-field:
the movie's range is pushed into the widget of any editable text sprite every
frame. That is why setting `the selStart` before focusing a different field
behaves oddly in real Director.

Typing, caret, Enter and Tab are handled inside the shared Mac text widget, so
ScummVM is not a good spec for them. What the Director layer contributes is
focus arbitration, the selection round-trip, pushing changed text back to the
cast member, and auto-expanding dimensions flowing back to the sprite.

### 8.5 Keyboard in the score

Nothing in the score is keyboard-driven. Wait-for-click is satisfied by a mouse
click, not a key. There is no key channel.

### 8.6 What to build, in dependency order

1. Modifier flag word plus `the key` / `the keyCode` including the arrow
   substitutions. Cheap, and several games poll these from `idle` without ever
   using a handler.
2. `keyDown`/`keyUp` through the hierarchy with channel 0 when unfocused. Enables
   dialogue skipping and cheat keys.
3. Primary handlers with **pass-by-default**, plus `pass` / `dontPassEvent` for
   the rest.
4. Editable field focus, caret and selection. Largest, least often needed.

---

## 9. Timing, waits, idle and timers

### 9.1 The frame clock

The tempo channel is one byte, reinterpreted by range (D5 and below):

- **1 … 120** — frames per second.
- **≥ 256 − maxDelay** — a delay of `256 − tempo` seconds. `maxDelay` is 120 for
  D2, **95 for D3** (higher values became video waits), 60 for D4/D5.
- **128** — wait for a mouse click.
- **135** / **134** — wait for sound channel 1 / 2.
- **136 … 135 + channelCount** — wait for the video in that channel.

D6 renumbered everything: 255/254 sound waits with a cue point, 248 wait-for-
click, 247 delay, 246 FPS, anything else a video wait — with the value in a
separate cue-point field.

With no tempo, the previous rate carries forward. A **puppet tempo** overrides
the score's but is cancelled the moment the score writes a tempo or the effective
tempo changes.

*This port:* `director/director_score.gd` carries FPS forward and decodes delay
and wait-for-click; `director/director_frame_clock.gd` is what stops the playhead
for them. Sound and video waits are absent, and nothing in this corpus asks for
one: across all 61 containers the tempo byte only ever holds 246, 247 or 248 —
the D6 numbering, not D5's — so every tempo written is a frame rate, a delay or a
wait-for-click and there is no sound or video wait to miss. The delay operand is
read as **whole seconds**: `strtgame.dir` writes 1 and 2 there, which is 1 s and
2 s under that reading and 17 ms and 33 ms under a tick reading, and nobody
authors a 17 ms pause.

### 9.2 Waits are a state, not a sleep

`isWaitingForNextFrame` is polled every tick. A pending **`go to` cancels every
wait** — sound, click and video waits all release if a jump is queued, which is
how a script escapes a wait-for-click frame. During a wait, **video keeps playing
and the window keeps rendering**. Wait-for-click also drives the alternating
cursor and is cleared by the mouse-down handler, not by the score.

`the delay` is separate and **latched**: only the first `delay` in a run of
`exitFrame` iterations takes effect, because the score loops on `exitFrame` and
would otherwise re-arm it every pass.

### 9.3 Idle and timeouts

`idle` fires once per tick, before the frame update. In D5+ `mouseWithin` is
generated alongside it (D5 only while a button is held; D6 always).

`the timeoutLength` defaults to 10800 ticks (3 minutes) and is checked
**independently of the frame delay**, so it fires even on a waiting frame. Reset
by mouse-down when `the timeoutMouse` is set, by key-down when
`the timeoutKeyDown` is set, and every frame when `the timeoutPlay` is set.
`timeout` is a primary-handler event. The tick base is the Mac 1/60-second tick,
which is also the unit of `the timer` and `startTimer`.

### 9.4 Recursion and frozen scripts

ScummVM counts "frozen" Lingo states and checks after almost every dispatch
point, bailing out of the tick if a handler froze. D4 and below allow unbounded
recursion through the per-frame hook; D4+ stop at depth 2 and force a thaw; 64 is
treated as runaway. A port with a synchronous interpreter needs an equivalent, or
a `go to` from `enterFrame` runs two frames' handlers in one tick.

---

## 10. Transitions

Three sources, in order: a **puppet transition** from Lingo (one-shot, consumed);
the frame's **transition type** with duration, area and chunk size; or a
**transition cast member** supplying the same parameters.

About 50 numbered types mapping to 13 algorithms — wipe, reveal, cover, push,
centre-out, edges-in, strips, blinds, checkerboard, boxy, random lines, dissolve,
zoom — each with a direction. Duration is in milliseconds and the step count is
capped at `duration × 60 / 1000`, one step per tick. **Chunk size** controls
step coarseness; **area** selects whole-stage versus changed-rectangle.

The transition renders the *new* frame progressively over the *old*. During one,
the per-frame hook fires once per **subframe** instead of once per frame, which
is why the normal call site is skipped when a transition is present.

**Minimum viable set:** wipes (4 directions), dissolve (pixel and boxy), covers
and reveals, centre-out/edges-in. Degrade the rest to a **cut**, not to a
wrong-direction wipe — a cut reads as a stylistic choice, a wrong wipe reads as a
bug. The thing that must not be skipped is the **time**: a transition consumes
its duration and scripts time against it, so rendering transitions instantly runs
the following frames early.

*This port:* the **time**, in full; the **drawing**, not at all — a transition
cuts. `director/director_transition.gd` decodes the transition cast member and
resolves the three sources in the order above; `director/director_frame_clock.gd`
holds the playhead for the duration, and the frame's `enterFrame` is deferred to
the end of it because §6.2 puts the transition inside `renderFrame`. Events keep
being pumped throughout, because the hold is a state polled per tick and Godot's
input is untouched by it. See §16.7 for what the corpus actually asks for, which
is five frames and four seconds.

---

## 11. Palette

**Resolution order** (`setLastPalette`): the frame's palette channel id if that
palette is actually loaded; else the **score-cached** id; else the **movie
default**. Director tolerates references to palettes of long-deleted members,
which is why every step re-checks existence. A **puppet palette** short-circuits
all of it. The switch is immediate when colour cycling is active or the id came
from the cache (meaning the score was jumped into); otherwise it is staged for
the transition machinery.

**Effects.** The palette channel carries a first and last colour index, a speed
in FPS, a cycle count, and flags for **colour cycling**, **over time** and
**auto-reverse**.

- **Colour cycling** rotates entries between first and last. With *over time*,
  one step per frame transition. Without, **the entire cycle runs inside one
  frame transition** as a blocking loop that steps, redraws, pumps events and
  sleeps to hit the speed; a click aborts it and restores the palette.
- **Auto-reverse** runs it backwards afterwards.
- Cycling state is keyed by palette **id only**, so changing cycle configuration
  on the same palette keeps the mutated offset rather than resetting — authentic.
- Speed 30 is unbounded (10 ms floor).
- Without cycling, the channel does a **fade** between old and new palettes over
  a number of steps, with pre- and post-frame variants.

**Why it matters even for an RGB renderer:** if textures are baked at load, the
whole mechanism is a no-op. That is an acceptable trade but it must be a
*decision* — a game that fades to black through the palette will not fade, and
one that animates water or fire by cycling will be static. The cheap partial is
a per-frame recolour of the affected members for the index range concerned.

*This port:* `director/director_palette.gd:30-33` warns and falls back for any
non-zero clut id; there is no `CLUT` reader. `scenes/director_preview.gd:162`
uses one global palette. Inert for a corpus where every member carries clut 0.

---

## 12. Sound

- **Two score sound channels** plus puppet channels above them; the frame's main
  channel carries a member id per channel.
- A channel restarts only if its member **changed** — D6 compares against the
  previous frame explicitly, earlier versions restart more eagerly. Restarting
  every frame stutters a looping sound; never restarting misses re-triggers of
  the same sound.
- Sounds start **in parallel with a transition**, before it plays.
- **Fades** step once per tick from the top of the update, ahead of everything
  else, and also inside the blocking palette-cycle loop.
- **Cue points** are D6+; wait-for-cue tempo values carry an index where −1 is
  "next" and −2 is "end".
- **Film loops carry their own sound assignments per loop frame**, queryable from
  the host channel — a second, independent source of sound events.
- `soundBusy` is what wait-for-sound polls.

---

## 13. Trails, blend, video, text, shapes

**Trails** — no erase of the old bbox, and the repaint starts *at* the trails
channel rather than clearing to the stage colour. In an immediate-mode Godot
renderer the equivalent is an accumulation buffer that is not cleared, with
non-trail sprites drawn over a cleared copy; it does not fall out for free.
`director/director_score.gd:246` decodes the flag and nothing consumes it.

**Blend** — §2.7.

**Digital video** — channel-level movie time, rate, start and stop time.
**Direct-to-stage** video bypasses the compositor: those channels move to the
**end** of the paint order for their rectangle and count as trails. Start/stop is
driven by member identity changes on the channel. A video the score sizes to
**0×0 is kept at 0×0** — that is the idiom for an invisible audio/timing clock,
and "fixing" it pops a video onto the screen. Video channels force a render every
tick even while waiting.

**Text and fields** — render through a widget; the sprite's size comes *from the
widget* after layout. Two different mask surfaces by ink: a **character box**
mask for the Matte family and arithmetic inks, a **glyph** mask for the
transparent/reverse/ghost family. Colourisation is preprocessed rather than
blitted. Scrollbars are the only producer of the hit-test Hole (§4.2).
`the selStart`/`selEnd` are movie-global (§8.4).

*This port:* the preview draws fields — `director/director_text.gd`, called from
`scenes/director_preview.gd:_draw_text`, with the member's own point size,
colour, slant and alignment out of its `STXT` style run and its box out of the
score. **Legible text in roughly the right place at roughly the right size, and
not period-accurate glyph rendering**: the font id is carried and unresolved (no
font table here), so the typeface and therefore the advance widths are Godot's
fallback and a caption does not land pixel-for-pixel where Director put it. No
widget, no character-box/glyph mask distinction, no scrolling, no editing, and no
push of the laid-out size back onto the sprite (§1.2) — the score's size is used
as authored. `put x into field` now reaches the drawn text
(`director_preview.gd:lingo_set_field`), which it did not before: the host's
setter was a no-op, so a HUD would have shown its authored placeholder for ever.

Measured, over the corpus's 321 field members: exactly **one style run each**, so
one style per field; point size 12 in 292 of them; alignment left in 308 and
centre in 13; colour black in 308. Every one of the 11,525 field sprite records
uses Background Transparent and the default foreColor. **Buttons (type 7) and
rich text (type 12) do not occur in this corpus at all**, so §1.2's
"buttons draw at the member's `initialRect`" rule is unexercised and
unimplemented.

**Shapes (QuickDraw)** — sprite types 2-6 and 12-15 are drawn by primitives, not
bitmaps: rectangle, rounded rectangle, oval, two line directions, outlined
variants, thick line. From D3 a **shape cast member** carries its own shape type
and fill flag which override the sprite type. Shapes carry a **pattern** and a
line thickness; for outlined shapes thickness 1 means invisible, so the stored
value is decremented. Patterns 57-64 are **tiles** from the movie's tile table
with built-in fallbacks. Shapes get their own matte by drawing the filled shape
into a scratch surface and flood-filling from the border — the same algorithm as
§2.5 — which is what makes an oval hit-test as an oval. Shapes are colourised by
the primitives, not the ink pass.

*This port:* `director/director_shape.gd`, reached through
`director_preview.gd:_texture_for`. Rectangle and rounded rectangle are drawn
from measured data; oval and line are written from the reference and are
unverified, because no member in this corpus is either. The fill and the outline
take the **sprite's** foreColor; the paper is left transparent rather than
painted, and a shape image is returned already keyed (no ink pass runs over it).
Patterns are not implemented and a patterned shape comes out solid.

**The thickness rule is the whole story here, measured.** 162 of the corpus's 169
shape members are unfilled rectangles with a stored line thickness of 1 — an
outline zero pixels wide, which draws nothing — and they account for **60,100 of
the 60,914 shape sprite records**. They are the game's invisible hotspots: a
rectangle over the scenery with a behaviour attached, named `to clif2` or
`dwarf_well`. So the port returns *nothing* for them rather than a transparent
image, and above all does not paint the paper: filling the rect with the sprite's
backColor before keying would be invisible under Background Transparent and would
put an opaque white rectangle on screen for each of the 8,302 shape records that
use Copy. Every one of the 60,914 records carries sprite type 16 (cast member),
so the member's own kind always decides and the sprite record's type never does.

One divergence taken deliberately: **a matte-inked shape hit-tests as its
rectangle, not per pixel.** A matte is flooded in from the border of a bitmap's
*image* and a shape has none. 452 shape records carry Matte, every member they
name is one of the invisible rectangles above, and a per-pixel test against
nothing rejects every click — the doors stop working. The reference's claim that
shapes build their own matte from the filled shape is not reproduced, and would
be wrong here for exactly that reason.

---

## 14. Windows, stage and Movie-In-A-Window

The stage is a window like any other, owning the stage colour, the dirty rect
list, the composite surface and the current movie. **Stage colour** is what every
non-trails repaint fills with, and changing it marks everything dirty; it is not
black by default.

A movie can open further windows each running a movie — Movie-In-A-Window — with
its own score, Lingo state and frozen-state stack; Lingo state is explicitly
moved between windows on a switch. Window events are D5+. A **modal** window
blocks its parent.

An **embedded** movie (a movie cast member) never renders to the shared window
and its channels never create widgets; the host composites it through the
sub-channel mechanism at the host sprite's position — the same path film loops
use. A port that lets an embedded movie draw itself paints it at its own native
origin, ignoring the host sprite.

A movie can push the current movie onto a **movie stack** and return to it,
including the resume frame. Reaching the end of a movie pops the stack if
non-empty, and otherwise **wraps to frame 1** — it does not stop.

---

## 15. Other engine behaviours

- **Labels** are a sorted name→frame list with next/previous navigation and a
  tracked current label.
- **Score recording** (`beginRecording`/`endRecording`) writes sprite state back
  into the score; a game can build animation at runtime.
- **Cast erase and reload**: an erased member is dropped and both the current and
  next sprite re-resolve their pointers mid-update; a member whose filename
  changed is flagged for reload.
- **`the beepOn`** makes a click on empty stage beep.
- **Button hilite has a genuinely strange rule**: on mouse-up, if the last
  mouse-*down* was in *any* button, the button under the mouse-up flips its
  hilite. ScummVM notes this makes no sense and does it anyway.
- **`the clickOn`** updates on mouse-down always, on mouse-up only when the
  release was over a sprite.
- **Immediate sprites** invert the ordering: the script runs on mouse-down and a
  paired mouse-up is synthesised immediately after. Before D4, mouse-up goes to
  the sprite that was *pressed*; from D4, to the sprite under the *release*.
- **Cast script targeting on mouse-up** uses the member under the mouse at the
  *beginning of the mouse-down chain*, not the current one — so a mouseDown
  handler can swap the member and the *old* member still gets the mouseUp.

---

# PART III — GAPS

## 16. Prioritised gap list

"Both" = ScummVM and this port's working renderer agree, so it is settled and
the only question is why the preview differs. "Differ" = the two references
disagree and the gap needs deciding.

### Tier 1 — breaks a playthrough

**16.1 The preview has no mouse eligibility filter. (Both.)**
`scenes/director_preview.gd:966-976` returns the first sprite whose rect contains
the point, with no `respondsToMouse` equivalent. Its own comment at `:959-964`
names the gap. The working side has it at
`director/director_runtime.gd:1426-1447`.
*Change:* in `_channel_at`, evaluate eligibility after containment and
**continue the loop** when it fails. Eligibility = a behaviour script for this
channel/frame, or a cast member script, or a button, or moveable. Keep the
per-pixel test as an additional filter for **matte-inked sprites only** (§2.1),
not as the eligibility test.

**16.2 The preview's hit rect and draw rect use different anchoring. (Both.)**
§1.7. *Change:* make `_sprite_rect` (`:1007-1013`) call `_scaled_reg`
(`:840-849`).

**16.3 The preview has no cursor resolution at all. (Both.)**
No default cursor, no per-channel cursor, no call site.
`director/director_runtime.gd:1500-1518` is the working implementation and it
matches Director's shape. *Change:* add §7.4's resolution to the mouse-move
branch at `scenes/director_preview.gd:525-574`, plus a movie-global default the
`cursor` builtin writes. Store per-channel cursor state with the same lifetime as
`visible` — **not** in `_overrides`, which is cleared on room change (`:1073-1074`)
and movie change (`:1143`).

**16.4 Colourisation: done in the preview, still missing in the working
renderer.** §2.3. `director/director_ink.gd:applies_colour` / `apply_colour`,
applied in `director_preview.gd:_texture_for` after keying;
`director/render_model_loader.gd` still drops the colours. **Also: this was
mis-scoped as a Tier 1 gap.** Only 651 sprite records on 7 distinct bitmap
sprites reach it in the whole corpus. The 50,063 records that made it look large
name *shape* members, which the shape primitives colour instead — see §13.

**16.5 Keyboard is entirely absent. (Neither side.)** §8. Survivable for Piposh 2,
not for a Director engine — dialogue skipping, name entry, cheat keys and menu
navigation all live here.

**16.6 `prepareFrame`/`enterFrame`/`exitFrame` all fire in one step in the
preview. (Differ.)** §6.1. **Done** in `scenes/director_preview.gd:_advance`:
`exitFrame` is dispatched for the frame being left at the top of the step, then
the playhead advance, then `prepareFrame`, then the redraw, then `enterFrame`.
`_advance` returns `{exited, frame}` so the ordering can be asserted rather than
inferred; `tools/frame_events.gd` checks that every step exits the frame the step
before it was on, including the first step of a movie. One divergence remains and
is not cheap to remove: Godot paints at the end of the process frame rather than
where `renderFrame` sits, so what `enterFrame` writes lands in the same painted
frame instead of the next one.

**16.7 Nothing implements transitions. (Neither side.)** §10. **Partly done**, and
the measurement is the point. `tools/transition_survey.gd` over all 61 containers
(61,371 frames) finds **3** transition cast members, **5** frames that name one,
**2** distinct types (11 push left ×4, 52 dissolve bits ×1), durations of 600/700/
1000 ms, and **4.0 s** of transition in the whole game; `reference/lingo/` calls
`puppetTransition` **zero** times. So the time is implemented in full —
`director/director_transition.gd` decodes the member, resolves §10's three
sources in order, and `director/director_frame_clock.gd` holds the playhead for
the duration with `enterFrame` deferred to the end of it — and the *drawing* is
deliberately a cut, per §10's own advice, rather than thirteen algorithms for
five frames.

Measured alongside it, and much larger: the tempo channel's **delays** and
**wait-for-click** frames, which the preview also took no time over. The corpus
has 36 delay frames worth **74.0 s** and 24 wait-for-click frames; `strtgame.dir`
alone has 23 delays worth 46.0 s. Both are now honoured
(`director/director_frame_clock.gd`), which is a far bigger change to pacing than
the transitions were.

### Tier 2 — breaks scenes

**16.8 Film loop child placement disagrees between the two halves. (Differ.)**
`scenes/director_preview.gd:822-826` is unscaled with a zero registration
fallback; `director/movie_player.gd:329-342` scales and centres. **ScummVM sides
with `movie_player`** (§1.6).

**16.9 The film loop registration point is unresolved inside this port.
(Differ.)** `director/director_cast.gd:271-289` writes none;
both renderers centre anyway. §1.6 — settle by testing placement on screen, and
note ScummVM centres on the loop's `initialRect` while `movie_player.gd:223-224`
prefers the sprite record's size.

**16.10 Ink codes compared unmasked in the preview. (Both.)**
`scenes/director_preview.gd:673-676` versus
`director/render_model_loader.gd:829`. Any sprite with trails or stretch set is
misclassified. *Change:* mask with `& 0x3f` before the lookup.

**16.11 Matte paper colour sampled from pixel (0,0) in the preview. (Differ.)**
§2.5. Also: **neither side implements "no white on the border → no matte"**, and
both use a 14/255 tolerance where Director matches exactly.

**16.12 No flip. (Neither side.)** §1.8. The thickness byte is not decoded at
all. *Change:* decode byte 4 in `director/director_score.gd:_snapshot`. **Check
early** — if the original mirrors walk-cycle art, this presents as "walk cycles
are wrong".

**16.13 Palette hardcoded to system Mac. (Both.)** §11.
`director/director_palette.gd:30-33`.

**16.14 No sprite trails. (Neither.)** §13. Flag decoded at
`director/director_score.gd:246`, unused.

**16.15 No blend/alpha. (Neither.)** §2.7. Bytes 4 and 19 undecoded.

### Tier 3 — completeness

**16.16 No `moveable` drag or `the constraint of sprite`.** §7.6. Flag stored at
`director/sprite_channel.gd:40`, unused.
**16.17 No editable text, focus, caret or selection.** §8.4.
**16.18 No hilite-on-click.** §4.6.
**16.19 `set_size` does not re-derive the anchor.** §1.5,
`director/sprite_channel.gd:133-139`.
**16.20 No `beginSprite`/`endSprite`, `stepFrame`, `prepareMovie`, `idle`
cadence, `timeout`.** §8.1, §9.3. Deliberately still nothing, on a count of the
handlers in `reference/lingo/`: `on exitFrame` 2504, `on enterFrame` 33,
`on prepareFrame` 0, `on beginSprite` 0, `on endSprite` 0, `on stepFrame` 0,
`on timeout` 0, `on stepMovie` 0, `on idle` **1** — and that one is
`on idle / dontPassEvent() / end`. `the timeoutLength`, `timeoutMouse`,
`timeoutKeyDown`, `timeoutPlay`, `startTimer`, `the timer` and `the ticks` appear
**zero** times between them. For this title every one of these would be dead
code; for another title they are the cheapest things on this list to add, and
§9.3 has the semantics.
**16.21 No digital video or Movie-In-A-Window.** §13, §14. Shapes and field text
*are* now drawn in the preview (§13) and still are not in
`director/render_model_loader.gd`. Text is legible, not period-accurate; buttons
and rich text remain unimplemented and do not occur in this corpus.
**16.22 No rollOver bbox cache (D4 blank-sprite rule).** §4.5.
**16.23 Mask ink (9) treated as Matte.** §2.6.
**16.24 Float positions where Director truncates.** §1.10.
**16.25 No dirty rects.** §6.3 — acceptable, but it forecloses
destination-reading inks.

---

## 17. Subsystem inventory

| Subsystem | This port | Where |
| --- | --- | --- |
| Sprite placement / registration / scaling | **done** in the working renderer; **wrong hit rect** in the preview | `movie_player.gd:187-199`; `director_preview.gd:1007-1013` |
| Stretch semantics | **done** | `sprite_channel.gd:110-126` |
| Flip | **nothing** (byte undecoded) | — |
| Rotation / skew | n/a below D7; ScummVM does not implement it either | — |
| Film loop compositing | **done, two dialects** | `movie_player.gd:247-349`; `director_preview.gd:784-826` |
| Mouse hit test | **partial**: eligibility on one side, per-pixel on the other, never both | `director_runtime.gd:1426-1447`; `director_preview.gd:966-976` |
| Cursor compositing | **done** | `render_model_loader.gd:847-911` |
| Cursor resolution | **partial**: working side only, **nothing in the preview** | `director_runtime.gd:1500-1518` |
| Puppet | **partial**: whole-sprite on one side, per-field on the other, no copy-back mask | `sprite_channel.gd:55-74`; `director_preview.gd:911-941` |
| Ink | **partial**: Copy / BackgroundTrans / Matte; colourisation in the preview only | `render_model_loader.gd:828-844`; `director_ink.gd:applies_colour` |
| Matte flood fill | **partial**: different paper sampling, tolerant match, no no-matte rule | `render_model_loader.gd:765-794`; `director_preview.gd:1374-1422` |
| Visibility | **partial** | `sprite_channel.gd:37`; `director_runtime.gd:1426-1427` |
| Frame ordering | **done** in the preview (§16.6); **partial** in the runtime | `director_preview.gd:_advance` |
| Tempo: fps, delay, wait-for-click | **decoded** in the score, **honoured** by both renderers | `director_score.gd`; `director_frame_clock.gd`; `director_runtime.gd:276-281` |
| Tempo: wait-for-sound, wait-for-video | **nothing** — and no frame in the corpus writes one | — |
| Transitions | **timed**, not drawn: 5 frames and 4.0 s corpus-wide | `director_transition.gd`; `director_frame_clock.gd` |
| Palette resolution / cycling / fades | **nothing** | `director_palette.gd:30-33` |
| Trails | **nothing** (flag decoded) | `director_score.gd:246` |
| Blend / alpha | **nothing** | — |
| Moveable / drag / constraint | **nothing** (flag stored) | `sprite_channel.gd:40` |
| Editable text / focus / selection | **nothing** | — |
| Keyboard, modifiers, key events | **nothing** | — |
| Primary handlers, pass/dontPassEvent | **nothing** | — |
| Event hierarchy | **partial**: sprite → cast → frame → movie | `director_preview.gd:728-740` |
| Hilite on click | **nothing** | — |
| Sound channels, restart-on-change | **partial** | `director_runtime.gd` |
| Sound cue points, fades | **nothing** | — |
| Digital video | **nothing** | — |
| Text / field rendering | **partial**: legible, not period-accurate; preview only | `director_text.gd`; `director_preview.gd:_draw_text` |
| Shapes | **partial**: rect and rounded rect measured, oval and line unverified; preview only | `director_shape.gd` |
| Windows / MIAW / embedded movies | **nothing** | — |
| Movie stack | **partial** | `director_preview.gd:1143` |
| Labels | **done** | `director_labels.gd` |
| Stage clipping | **done** on the working side, **absent in the preview** | `movie_player.gd:43-44` |
| Dirty rects | **nothing** — acceptable | — |
| Score recording | **nothing** — rarely needed | — |

---

## 18. Not verified

- **What sets the cursor-dirty flag.** Only cleared in `score.cpp`; the setter is
  in `lingo/`, unread. Assume the `cursor` and `the cursor of sprite` setters set
  it; if implementing, also set it on a cast swap on a channel with a cursor.
- **Film loop sub-sprite sizing under scale.** ScummVM sets *every* child's size
  to the whole widget rect and forces stretch. That looks like an approximation,
  not authentic Director. Low confidence.
- **How flip interacts with registration and hit testing.** ScummVM never applies
  flip, so §1.8's "mirrors within the rect, rect unchanged" is **reasoned, not
  verified**. It is the only reading consistent with flip living in a rendering
  attribute byte, but it needs testing against the original.
- **Whether the Windows pre-D5 "ignore cursor hotspots" rule is authentic
  Director or a ScummVM workaround.** The ScummVM comment is itself a question.
- **Whether this port's film loop centring is right** — §16.9 is a genuine
  conflict between ScummVM's runtime rule and this port's record-matching
  evidence, and nothing was run to settle it.
- **Text widget internals** — typing, caret, Enter/Tab — come from ScummVM's
  shared Mac GUI, not the Director engine. Only focus arbitration and the
  selection round-trip were read.
- **Transition behaviour during input** — whether events are pumped mid-transition
  the way they are mid-palette-cycle was not read.
- **Two bytes of the D5 frame's transition record.** The record at main-channel
  offset 96 decodes as `[96-97] cast lib, [98-99] member`, and 100-101 is zero on
  every one of the five frames that use it — but **102-103 is not**, and holds
  0x132c, 0x69ba, 0x69b4, 0x402c, 0x406b. Two of those differ between adjacent
  frames naming the *same* member, so it is not a parameter of the transition.
  Nothing reads it and nothing depends on it.
- **Which of the transition member's bytes 0 and 3 is the flags byte and which is
  the change area.** Byte 0 is 0 and byte 3 is 2 in all three members in this
  corpus, so a constant column cannot tell them apart. Both are carried through
  unread.
- **Whether `enterFrame` really is deferred past a transition.** §6.2 puts the
  transition inside `renderFrame` and §6.1 puts `enterFrame` after it, which is
  the reading implemented; ScummVM's own `playTransition` was not read line by
  line to confirm no `enterFrame` is dispatched inside it.
- **Sound restart semantics below D6** were read only in outline.
- **The exact D6 tempo cue-point encoding** was read but not reasoned about.
- **`the timer` / `startTimer`** are described from the tick base and the timeout
  code; the builtins are in `lingo/`.
- **Nothing here was executed.** No harness was run, no frame rendered, no number
  measured. Every claim about ScummVM is from reading source; every claim about
  this port is from reading source and a structural survey, not from observed
  behaviour. In particular, none of the "agrees / settled" verdicts were
  confirmed by running both implementations against the same input — they are
  agreements of *code*, which per `AGENTS.md` is weaker evidence than a
  measurement.

---

## 19. Files read, and files skipped

**Read in full or in the relevant part** (ScummVM `engines/director` at master):
`sprite.cpp`, `sprite.h`, `channel.cpp`, `channel.h`, `score.cpp` (play loop,
frame update, tempo, cursor, sprite-at-pos, palette cycling, film loops),
`window.cpp` (render, renderChannel, inkBlitFrom, invertChannel),
`graphics.cpp` (ink pixel functions, applyColor, blit surface, colour
constants), `cursor.cpp`, `cursor.h`, `events.cpp`,
`castmember/castmember.cpp`, `castmember/castmember.h`,
`castmember/bitmap.cpp` (registration, matte, isWithin),
`castmember/filmloop.cpp`, `castmember/text.cpp` (isWithin, widget sizing),
`types.h` (ink, sprite type, collision, transition enums),
`frame.cpp` (the D4 sprite record layout and every copy-back mask site),
`transitions.cpp` (type and algorithm tables).

**Fetched and consulted more briefly**: `castmember/shape.cpp`,
`castmember/digitalvideo.cpp`, `castmember/transition.cpp`,
`castmember/palette.cpp`, `cast.cpp`, `cast.h`, `movie.cpp`, `movie.h`,
`score.h`, `frame.h`, `window.h`, `images.cpp`, `picture.cpp`,
`graphics-data.h`, `spriteinfo.h`, `util.h`, `director.h`, `types.cpp`.

**One deliberate exception to the "skip lingo/" rule**: `lingo/lingo-events.cpp`
was read for §8.2. The event hierarchy, the primary-handler pass semantics and
the sprite/cast/frame/movie precedence are engine behaviour, not language
surface, and are documented nowhere else in the tree.

**Skipped, and why**: the rest of `lingo/` (the language surface, covered by
`docs/LINGO_SURFACE.md`); all of `xlibs/` and `lingo/xtras-cast/` (per-title
external code, not engine behaviour, with the single exception of the Cursor
Asset Xtra reference in §7.2 which surfaced through `cursor.cpp`); `debugger/`
and `debugger.cpp` (developer tooling); `detection*.{cpp,h}` and
`game-quirks.cpp` (per-title identification and workarounds); `archive*.cpp`,
`resource.cpp`, `stxt.cpp`, `rte.cpp` (container parsing — this port has its own
readers and `docs/ENGINE.md` covers the format); `tests.cpp`, `fonts.cpp`,
`metaengine.cpp`, `credits.pl`, `module.mk`, `POTFILES`, `configure.engine`
(build and housekeeping); and the `writeCastData` / `writeVWSCResource` /
`archive-save.cpp` save paths throughout (this port does not write Director
files).
