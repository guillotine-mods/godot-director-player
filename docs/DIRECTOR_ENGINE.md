# The non-Lingo half of the Director engine

`docs/LINGO_SURFACE.md` documents the language: handlers, properties, the
built-in function surface. This document is everything underneath it — the part
that runs whether or not the movie has a single line of script.

The reference is ScummVM's `engines/director`, read at master. It is GPL, so
nothing here is copied from it: this is a description of behaviour written from
reading the implementation.

**A warning about the agreement notes below.** Where this document says ScummVM
and "this port's working renderer" agree, and calls that **settled**, the
renderer it means is `director/movie_player.gd` / `sprite_channel.gd` /
`render_model_loader.gd` — which has since been **retired**. It drew from a
pre-decoded JSON and BMP export under `assets/render_model/`, and that export no
longer exists. The live renderer is `scenes/director_preview.gd` and the modules
in `scenes/preview/`, which read the original containers at runtime.

Those agreement notes are still evidence — two independent implementations
reaching the same reading is worth something regardless of which one is now
running. But they are **not** a statement about the current code, and several
have already been found not to hold in it. Treat "settled" as "settled about
Director", never as "already correct here", and check the live path before
relying on one.

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
recomputed x/y as `loc − reg`, which normalised the whole problem away for that
renderer. That renderer and that loader are deleted; the live engine reads the
rect from the score record and treats it as residue unless the author stretched
it (`tools/drawn_size_stability.gd`).

**Text was excepted from that for a while, and should not have been.** The
exception list in `sprite.cpp:setCast` is not a list of types whose score rect
wins — it is a list of types the *reset* skips, and for text the widget then
overwrites the size anyway. A port that takes the first half without the second
lands on the score's stored rect, which is the one value the two clauses above
agree Director never shows. `scenes/preview/sprite_geometry.gd`'s
`KEEPS_ITS_OWN_SIZE` is shape-only for that reason; a field resolves to its
member's `initialRect` unless stretched or resized by a script.

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

The thickness byte is at **offset 22** of the 48-byte D7 record, and the blend
amount at 21 -- not at 4 and 19, where this port read them until
`tools/sprite_record_bytes.gd` measured the record byte by byte. Offsets 4 and 19
are the high half of the cast lib and the low half of the width, both of which
the same decoder already reads, so every flag taken from them was structurally
zero. Every "0 of 816,318" quoted for flip, blend and tweened below was that
artefact. Re-measured from byte 22: flip really is 0 in both corpora, has-blend
is 1,818 in Piposh 2 and 11,512 in Piposh 1, and **tweened is 600,968 and
1,326,064** -- 74% and 70% of all records.

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

*This port:* **done.** `director/director_score.gd:_snapshot` decodes byte 22
and `scenes/director_preview.gd:_draw_sprite_texture` mirrors the artwork inside
the sprite's rect, leaving the rect -- and therefore the placement and the hit
rectangle -- alone; `_opaque_at` mirrors its sample point to match, so the
clickable pixels travel with the artwork. `tools/sprite_flip.gd` asserts both,
and its pixel case reads the framebuffer: a first attempt moved the rect's origin
to the far edge as well as negating its width, which is a double flip, and every
headless check passed while the sprite drew one width to the right. Godot's
`draw_texture_rect` negates the size and keeps the position.

Still unverified against Director, because nothing authored sets the bits.

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

Four, not three, and the fourth is the one that gets collapsed into another by
mistake. All of them descend the channels the same way (§4.2); they differ only
in the filter and in whether the geometry is the live bbox or the rollOver bbox.

| Query | Geometry | Extra filter | Reached by |
| --- | --- | --- | --- |
| `getSpriteIDFromPos` | `isMouseIn`, ink-aware | none | `the rollOver`, `the mouseCast`, `the mouseMember`, `the mouseChar`/`Word`/`Line`/`Item` |
| `getMouseSpriteIDFromPos` | `isMouseIn`, ink-aware | `respondsToMouse()` | click routing **D4+**; `mouseEnter` / `mouseLeave` / `mouseWithin` |
| `getActiveSpriteIDFromPos` | `isMouseIn`, ink-aware | `isActive()` | click routing, D3 and below |
| `getRollOverSpriteIDFromPos` | rollOver bbox, plain rect (§4.5) | none | the `rollOver()` **builtin** with no argument or 0, D5+ |

The version split happens once, at the event entry point.

**Piposh 2 is D7, not D4.** Every movie and cast it plays carries config version
`0x57E`, which is `humanVersion()` 700, a `VERS` chunk of 7.0, `frames_version`
13 and 48-byte sprite records; `openspec/changes/director-playback-machine/
director-version.md` has the measurement. `respondsToMouse` is still the rule —
it is the D4-and-later one — but the **D6+ clause inside it applies as well**,
and that clause is much wider than the handler search (§4.3). The 8.5 ScummVM
reports for this title is the *projector's* version and describes no movie.

Two rows of that table are collapsed into one in this port and it is worth
naming which. `the rollOver` and the `rollOver()` builtin are **different
queries** — the property samples the artwork and aborts on a Hole, the builtin is
a plain rect over the rollOver bbox — and `mouseEnter`/`mouseLeave`/`mouseWithin`
are driven by the *eligibility-filtered* query rather than by either. See §4.5.

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

They are tested in that order, and the order matters because **the D6+ clause
short-circuits the handler search entirely.** From D6 on, a sprite with any
behaviour attached is a click target whatever that behaviour declares — an
`exitFrame`-only behaviour absorbs clicks. The handler search below it is the
D4/D5 rule and is dead code on a D6+ movie.

Two traps in the D4/D5 arm. It is **not enough that the script id is non-zero** —
the handler must exist in the compiled script, so a sprite whose script only
defines `mouseEnter` is not a click target. And **moveable alone qualifies**,
with no script at all.

The **generic handler** clause is the D3-style scopeless sprite script: a score
script whose Lingo is bare statements rather than an `on <event>` block. It
counts as a mouse handler for eligibility, and §8.2 says when it actually runs
(mouse-down if the sprite is immediate, mouse-up otherwise).

*This port:* `preview/interaction.gd:eligibility_reason` implements all six
clauses in the reference's order and answers **which one fired**;
`responds_to_mouse` is that function returning non-empty. One implementation
for the predicate and the explanation, because the hit test filters on the
first and every debugging tool prints the second, and this module has already
watched the overlay and the descent diverge once over `hits_per_pixel`'s
arguments.

The D6+ arm is gated on the **movie's own** config version against
`kFileVer600` (`0x4C2`). The reference asks a global — the engine is told once
which Director it is emulating — and per-movie is the closer answer available
here, because a title can mix formats: Piposh 1 ships `STRTGAME.dir` with
48-byte sprite records and 94 room movies with 24-byte ones. A movie with no
config chunk reads 0 and takes the narrower arm.

**The D6+ arm tests the behaviour list after resolution, and that is a
deliberate divergence.** The reference tests `_behaviors.size()` — the
attachment — and taken literally here it is a false positive of exactly the
kind §4.2 warns about, because this port's attachment list is not clean.
`director_score.gd:_read_interval` pairs a span's info entry with the next
non-empty 8-byte `VWSC` entry rather than indexing by the `sprite_list_idx`
the sprite record already carries and the reference indexes by, so a span whose
own behaviour entry is empty can be handed one belonging to something else.
Measured by `tools/click_eligibility.gd`: 279 of 2,678 sprite intervals in
Piposh 2, 654 of 6,197 in Piposh 1 and 500 of 5,365 in Rating fail to resolve,
and all but 45 of those name a bitmap, a film loop or a shape — none of which
can be a behaviour. Taken literally the clause made `AIR1.dir` channel 1, a
640x400 Copy-ink backdrop over the whole stage, a click target on 144 frames on
the strength of an attachment naming a bitmap. Requiring the lookup drops 118
of the 188 (movie, channel) pairs and four of the five over 640x400. It also
drops the 45 that name a real script member this port cannot resolve or
compile, which is narrower than Director and errs toward letting the click fall
through — §4.2's own default.

Two clauses are implemented and **unexercised**: a movie member with scripts
enabled (`director_cast.gd` does not decode the flag, so it reads enabled), and
the generic scopeless score script (the parser keeps its bare statements in
`body`). 0 of the 51,350 members across the three corpora is of type `movie`,
and 0 is of type `button` either — so clause 2 has never fired on any title
this engine has been pointed at.

**Widening eligibility is what makes a sprite absorb a click, not merely answer
one**, so `preview/interaction.gd:script_for_click` now skips a tier whose
script cannot answer the message being sent. Every sprite the D6+ clause newly
makes eligible carries a behaviour declaring no mouse handler *by construction*,
and this port dispatches to one script with a movie fallback behind it — so
without that rule each one would have become a dead patch of stage, the
complaint this clause exists to fix arriving from the other side. It is not
§6.3's queue: `pass` and `dontPassEvent` are still unbound, and a behaviour
declaring `mouseDown` and not `mouseUp` still takes both messages.

`isActive()` is the looser D3 rule: moveable, or a button, or a score script
*exists*, or a cast script *exists* — presence only, no handler inspection.

### 4.4 Ink participation

`isMouseIn`: not `_visible` → No; else compute the bbox (§1.1); else delegate to
`cast->isWithin(bbox, pos, ink)`, or a plain rect test if there is no member.

Per type: bitmap does rect-then-matte-if-ink-is-Matte; text does rect plus the
scrollbar Hole; everything else is a rect. See §2.1 for the full table.

### 4.5 rollOver is looser — and is three different things

"Rollover" names three queries in Director and they do not agree. Getting them
into one function is the single easiest mistake in this area, and it shows up as
a menu whose highlight and whose click disagree about which button is live.

- **`rollOver(n)`, the builtin with an argument** → `checkSpriteRollOver`: does
  channel `n`'s **rollOver bbox** contain the pointer. A pure rect test — no
  matte, no eligibility, no visibility check.
- **`rollOver()` / `rollOver(0)`, the builtin with none** →
  `getRollOverSpriteIDFromPos`: the same rect test descended over every channel,
  answering a channel number. **D5+ only** — in D4 and below `rollOver(0)` is a
  Lingo error, not 0.
- **`the rollOver`, the property** → `getSpriteIDFromPos`: the *ink-aware* hit
  test of §4.4, matte and Hole included, with **no** eligibility filter. It is
  not the same answer as the builtin with no argument, and neither is a typo for
  the other. `the mouseCast`, `the mouseMember` and the D3 `the mouseChar` /
  `mouseWord` / `mouseLine` / `mouseItem` all read this same query.

`getRollOverBbox()` is the live bbox from D5 on. In **D4 and below** it returns
the *last non-empty* bbox when the channel's cast id is currently 0 — a sprite
the score has blanked still rolls over its old rectangle — and that cache is
refreshed at every frame change for every channel with a non-zero cast id.

**`mouseEnter`, `mouseLeave` and `mouseWithin` are not rollover queries at all.**
They are driven by `getMouseSpriteIDFromPos`, the *eligibility-filtered* hit
test, so a backdrop with no mouse handler is rolled over and never entered. §8.1
has when they fire.

*This port:* `preview/interaction.gd:rollover_channel` is one pure-rect descent
answering the builtin in both its forms, measured against the **score's**
geometry rather than the live channel's — see the function's own comment for why
the live rect feeds a menu's highlight back into its own rollover test. `the
rollOver` as a property is **bound to that same descent**, which is the wrong one
of the two — it should be the ink-aware hit test with no eligibility filter, a
third channel this port does not maintain. It is not unbound and it does not read
VOID; this line said so, and §19's `live` row for it disagreed. The hover messages are driven
off the rollover channel rather than the filtered one. All three are recorded in
`ENGINE_TODO.md` with what has to change alongside each.

### 4.6 Hilite

`shouldHilite()` requires `isActive()`, and requires **not** moveable and
**not** puppet. For a bitmap in D3+ it is driven by the member's **auto-hilite**
info flag, falling back to "ink is Matte" when there is no cast info. QuickDraw
shapes hilite when ink is Matte. The inversion is a masked XOR of the
destination through the sprite's matte, so an irregular sprite inverts its
silhouette, not its box.

*This port:* hilite is implemented clause for clause in `scenes/preview/hilite.gd`
— see `ENGINE_TODO.md`'s "Built but never compared against Director running" for
what it does and its two stated divergences. The **button** flip in §15 is a
different rule and is not implemented. The eligibility and the descent are
`preview/interaction.gd:responds_to_mouse` / `channel_at`; the rollOver bbox cache
is absent. The three paragraphs that stood here cited
`director/director_runtime.gd` and line numbers in the retired renderer, both
deleted.

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

*This port:* `scenes/preview/channel.gd` is the `Channel`/`Sprite` pair, and
`scenes/preview/sprite_state.gd` is the six questions the player node asks it.
`Channel.release` skips a channel carrying `_puppet`, and `with_puppets` is the
other half: for a port that draws from the score's per-frame sprite list rather
than from a live channel table, "the reconcile is skipped" has to mean **the
channel keeps what it was frozen with and the score's record for it is dropped —
whether or not there is one**. It still skips the script-id copy; add it if
frame-scoped sprite scripts ever matter. (`director/sprite_channel.gd`, cited
here before, was the retired renderer and is gone.)

This paragraph asserted only the empty-record half until CHESS's name wheel found
the other one, and the omission is worth keeping written down because of how well
it hides. A puppet is frozen exactly on the frames the score was not going to
write anyway, so every test of the rule passes while half of it is missing; the
wheel's two spins differ only in whether the frame they land on happens to carry
a record for the puppeted channel. `tools/puppet_freeze.gd` is the harness that
asks the other question, because `puppet_persists` structurally cannot.

**The visible consequence, which reads as a layering bug and is not one.** A
channel is emptied by the score *writing* an empty record into it, and that write
is exactly what `_puppet` blocks — there is no separate "clear the channel" path
in `Score::updateSprites` for it to reach by. So a clip that drops both a
foreground layer and the puppeted player standing behind it drops one of them:
the layer goes, the player stays, and the player is drawn unoccluded. Reported
twice from play against DAY1's `dwarfs`; measured, authentic, `bugs.md` 48.

### 5.3 Per-field auto-puppet (D6+)

D6 auto-puppets individual properties on write, without setting the whole-sprite
flag. `replaceFrom` guards each field with both its copy-back bit and its
auto-puppet bit. Auto-puppet is **released** when the score itself writes that
property — checked every frame change against the incoming mask, with height and
width released by a *cast id* write as well as by an explicit size write.
Inert below D6, but the shape matters: it is the same "block the score per field"
idea that whole-sprite puppet does coarsely.

**"The score writes that property" is an event, not a value.** The mask is the
set of fields *this frame's delta touched*; a score that rewrites a channel with
the member it already had has still written it, and still releases. Nothing
anywhere compares the old value with the new one.

*This port:* `scenes/preview/channel.gd:release`, driven by
`director/director_score.gd:writes_between` — which answers the same question the
mask does, out of the same delta byte ranges, for the walk between two frames.
The release table is not written out separately: `channel.gd:FIELDS` describes
each property once, and the `released_by` column of that row *is*
`Sprite::releaseAutoPuppet`'s entry for it. A property described in one direction
and not the other is what produced five of this port's bug reports, so the merge,
the release and the read-back are one table read three ways.
`scenes/preview/frame_loop.gd:sync_frame_entry` calls it, once per frame change,
before the new frame's scripts run; that is the port's equivalent of the
`if (_curFrameNumber != nextFrameNumberToLoad)` the reference hangs it on, and
every path that moves the playhead goes through it. `visible` is deliberately not
released; it is channel state, not a score field.

It was a **value comparison** — "the member the override was taken against is not
the one the score now holds" — until bugs.md 47, and that is right whenever a
clip changes the member and silent whenever it does not: click the dwarf at
`exitforest3` and both the room and `dnzclicktalk` put `adnzlop1` on channel 18,
so the mouth kept moving for the rest of the movie. bugs.md 36's `membernum`
exemption was the other half of the same rule and is also gone.

The release being an event rather than a read also retires `effective`'s `peek`
flag: a pure read can be asked about a frame the playhead has not reached, which
is what `director_preloader.gd` does 24 frames ahead every step.

### 5.4 Hand-written persistence rules

Three fields ignore the mask: **editable** is preserved if the cast id did not
change; **immediate** is always preserved; **width/height** are copied when the
score writes a **cast id**, even without a size write, because changing member
implies re-fitting.

### 5.5 What resets it

`reset()` clears the puppet flag (movie load). Auto-puppet is released per
property by the score. **Nothing in the frame loop clears whole-sprite puppet
implicitly** — it survives frame jumps and `go to`, and dies only when the movie
changes and channels are rebuilt.

**Turning the flag off in Lingo reverts at the call, not on the next frame**, and
this paragraph used to say the opposite. `LB::b_puppetSprite` clears `_puppet`
and then, if the sprite *was* puppeted, runs
`chan->setClean(_currentFrame->_sprites[N])` immediately — and the mask on that
record is `kSCBNoMask`, every bit set, because `updateSprites` resets all of them
at the end of every render cycle. So `replaceFrom` copies the whole record there
and then. The revert is synchronous with the statement.

**`setClean` declines the revert entirely if any per-field auto-puppet survives**,
which is the one thing here that is genuinely finer than a flag: its first branch
copies only the script id when `_puppet || _autoPuppet` is set. Bits set *during*
the whole-sprite claim cannot be among them — `setAutoPuppet` returns without
doing anything while `_puppet` is set — so this is only about a property written
*before* `puppetSprite N, TRUE` and never written by the score since.

*This port diverges there and only there:* `channel.gd:set_puppet` clears every
sprite field on the FALSE, so a pre-existing auto-puppet is dropped where Director
would keep it *and* would keep the rest of the sprite with it. Unimplemented
rather than unnoticed: it needs the channel to remember which of its fields were
auto-puppeted before the claim, for a case with **0 sites** in this corpus, and
the behaviour it buys is that one stale property blocks the whole revert.

What matches: `puppetSprite N, FALSE` returns the *sprite* and leaves the
*channel* — the hide, the constraint and the cursor are not in the object
`setClean` replaces. And nothing clears a whole-sprite puppet implicitly —
`preview/movie_session.gd:forget_previous` is the only place `_overrides` is
cleared and it runs on a **movie** change, not on a room change, so a puppet set
in a movie's `init all` survives every `go` inside that movie. It has to: DAY1
puppets the player in `init all` on frame 0 and never touches it again across
2,783 frames.

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

1. **Input events** dispatched from the queue, unless a jump is pending *or any
   Lingo state is frozen*.
2. **idle**.
3. (D6+) `mouseWithin`, sound cue points.
4. **Sound fades** stepped.
5. **timeout** check, independent of the frame delay.
6. **Wait check** — clock, wait-for-click, wait-for-sound, wait-for-video. If
   waiting, the update ends here; video still gets a widget update and a render.
7. **exitFrame** for the frame being left — *not* if it is being left by a
   `go to`, *not* if playback is paused, and *not* if it has already been sent for
   this frame (`_exitFrameCalled`). The last two are what make `pause` work: see
   the note under step 10.
8. `the delay` check.
9. Expiring behaviours killed — **not while paused**, so a paused frame keeps the
   behaviours attached to it, and the click that resumes the movie still has
   something to land on.
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

**Steps 1-3 are `Score::step` and steps 4-18 are `Score::update`, and the split is
a cadence and not a tidy-up.** `Window::step` calls `Score::step` from the
projector's main loop, which turns over roughly every 10 ms
(`director.cpp:370-405`); `Score::update` is where the frame clock is consulted
(step 6) and where the update ends when the playhead is not due to move. So
**`idle` runs at the engine's rate, many times per score frame**, before the clock
is asked anything and whatever the clock then says — and it keeps running while
Director's `pause` holds the playhead, because `Score::step` reads
`_playbackPaused` nowhere. Its only early exits are the projector's own
`kPlayPaused` and `kPlayStopped`. A port that sends `idle` from inside the score
step has it at a tenth of the rate and loses it entirely on the first `pause`.

*This port:* `frame_loop.gd:tick` sends it, `frame_loop.gd:send_idle` carries the
argument, and `tools/idle_clock.gd` asserts both the cadence and the pause.

**Reaching the end of the score is the second return from a `play`.** Step 10
pops the movie stack when `nextFrameNumberToLoad >= getFramesNum()`
(`score.cpp:462-487`) *before* wrapping to frame 1, requeues the parked play state
(`:474-476`, and `window.cpp:683-684` when the return crosses containers), and
resumes the caller there. Only `play` pushes that stack, so the branch is exactly
"an interlude ran to the end of its score instead of saying `play done`", and it is
the only thing that can ever wake a handler parked by such a `play`. A port with
only the `play done` half wraps to frame 1, plays the interlude again from the top,
and leaves the caller parked for ever.

*This port:* `frame_loop.gd:advance` and `director_preview.gd:_return_from_play_stack`,
with `tools/play_suspends.gd`'s "an interlude that runs off the end of its score
returns to its caller".

Compressed: **sprite state is updated from the score first, then the frame time
is computed, then the frame is drawn, and `enterFrame` runs after the draw.**
ScummVM cites *Lingo in a Nutshell*: the window is drawn between `prepareFrame`
and `enterFrame`. `exitFrame` for frame N runs at the *start* of the tick that
advances past it, not at the end of N's own tick.

A port running `enterFrame` before the draw shows one frame of lag on everything
it changes. A port running `exitFrame` and `enterFrame` in the same tick runs
both against the same rendered state, which breaks the standard "set up in
enterFrame, tear down in exitFrame" idiom.

**Where `pause` takes effect, and why it is step 10 and not step 1.** `pause`
names no destination, so unlike `go` it cannot be implemented by writing the next
frame number. It sets a flag, and every step from 9 onwards tests that flag —
crucially step 10, where `nextFrameNumberToLoad` starts at the *current* frame and
only the unpaused arm moves it. Since `pause` is almost always called from the
`exitFrame` handler at step 7, a port that tests the flag only at the top of a tick
has already decided to advance by the time it is set, and parks the playhead one
frame past the frame that paused. That is `docs/bugs-closed.md` 52, and it made a
room of Rating unfinishable because the behaviour that lifts the pause was attached
to the pausing frame alone. `_exitFrameCalled` at step 7 is the other half: without
it the resumed step re-runs the handler that paused, which pauses again.

*This port:* both, in `scenes/preview/frame_loop.gd:advance`, with the latch on the
node at `director_preview.gd:_exit_frame_called` and cleared beside `enterFrame` as
the reference clears it. `tools/pause_holds.gd` is the gate entry.

**`play done` needs the latch for a third reason, and it is the one that bites.**
The reference's "not if it is being left by a `go to`" is `_skipFrameAdvance`, and
`func_goto` raises it for *every* jump — including the one `play done` performs to
get back (`score.cpp:669-671`). A port that models that flag as "suppress the
`exitFrame` of the step the jump was queued in" covers an ordinary `go` and misses
this case, because the frame `play done` returns to is not being *left*: it is
being resumed. Its `exitFrame` ran before the `play`, and that handler is parked
inside it. Entering it again and dispatching a fresh `exitFrame` does not repeat a
side effect, it restarts the caller — which reaches the same `play` and never
returns. So the return keeps the latch raised across the entry it lands on
(`director_preview.gd:lingo_play_done`). Piposh Dream's save screen is the movie
that shows it: `ques.dir` 803 fetches six save names out of `saves.dir` with a
two-frame `play`, and the restart alternated the panel with that movie's empty
frames for as long as the screen was open.

**And the reference does not need the latch for that case at all**, which is worth
saying here because the two mechanisms are not interchangeable: `func_play` records
the return frame as `getCurrentFrameNum() + 1` when the `play` came from a script
that is not attached to a sprite channel — a frame script or a movie script
(`lingo-funcs.cpp:207-213`). It lands *past* the caller's frame, so there is
nothing to re-enter and nothing to suppress. This port lands on the frame and
suppresses; the outcomes agree, the observable behaviour does not, and `bugs.md`
54 carries the difference and what taking the reference's spelling would cost.

**A handler that opens another movie ends the step.** `Score::update` returns at
`score.cpp:696-698` — "the exitFrame event handler may have stopped this movie" —
and at `:722-724`, both before step 10, so a `go to movie` from `exitFrame`
contributes no playhead move, no `prepareFrame`, no draw and no `enterFrame` to the
step it was issued in. The arriving movie enters its own first frame, once. A port
that opens the container inside the call rather than queueing it must test for this
explicitly or the tail of the step enters the new movie's frame a second time
(`frame_loop.gd:movie_gone`; measured at two `enterFrame`s against one
`prepareFrame` on `DAY1.dir` 729, whose whole frame script is
`on exitFrame / go(1, "air1.dir")`).

Almost every step checks whether a script **froze** and bails out of the rest of
the tick. That is how Director makes blocking Lingo work without threads (§9.4),
and step 18 is where what froze gets to finish. `play` and `go` are what freeze,
so a handler that calls either does not run its next statement until a later tick
— which is not a detail of the tick order but the semantics of both verbs. §9.4
has the mechanism and what this port does about it.

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

The immediate-mode half of that structural point is now true here too, and it
had to become true: `updateStage` is Director rendering the window from inside a
handler, and a paint that can only happen in Godot's `NOTIFICATION_DRAW` cannot
be asked for. Every draw in the player goes through
`director/director_paint.gd`, which issues commands to a node's canvas item
through `RenderingServer` rather than through `CanvasItem.draw_*`, so
`director_preview.gd:_paint()` runs from Godot's `_draw` and from
`repaint_now()` alike. What is still missing against §6.3 is the dirty
rectangles: a synchronous repaint composites the whole frame, where Director
re-renders only the regions a channel occupied and now occupies.

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

*This port:* it used to have none of it; it now has §8.1-§8.4 bar the arrow-key
substitution in §8.3 and `pass`/`dontPassEvent` in §8.2, both noted where they
belong below. Keys arrive through `scenes/director_preview.gd:_dispatch_key`
(routed by `preview/input_router.gd`), the widget half is
`scenes/preview/text_focus.gd`, and `tools/editable_text.gd` drives real
`InputEventKey`s through it and reads the framebuffer back.

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

**Where each mouse message comes from**, which the names do not say and which is
where a port invents behaviour without noticing:

| Message | Raised by | Target |
| --- | --- | --- |
| `mouseDown` / `rightMouseDown` | the button going down | `getMouseSpriteIDFromPos` at the press |
| `mouseUp` / `rightMouseUp` | the button coming up | **D4+**: `getMouseSpriteIDFromPos` at the *release*. Before D4: the sprite that took the press |
| `mouseEnter` / `mouseLeave` | pointer **motion**, when the filtered channel changes | the channel entered / the one left |
| `mouseWithin` | the **frame tick**, once per tick | the channel currently under the pointer |
| `mouseUpOutSide` | the **next mouse-down**, when the sprite under it differs from `the clickOn` | the previously clicked sprite |

Three consequences worth stating on their own. `mouseEnter`/`mouseLeave` and
`mouseWithin` are **D5-gated on the button being held** — in D5 they are raised
only while a mouse button is down, and only from D6 do they fire with the button
up. `mouseUpOutSide` is **not raised by the release**: nothing happens when the
player slides off a control and lets go, and the message arrives on the *next*
press, by which time the `mouseUp` for that release has already gone to whatever
was under it. And a right click in D5+ raises **only** the right-hand pair — not
`mouseDown`/`mouseUp` as well — but it does everything else the left button's
press does, including latching `the clickOn`, starting a drag on a moveable
sprite, and setting the hilite.

*This port:* two of that triple are the reference's now and the third is not.
`mouseUp` goes to the sprite under the **release**
(`director_preview.gd:_release_click` builds the chain from `_channel_at(at)`)
and `the clickOn` is rewritten from that same sprite when it answered non-zero
(`interaction.gd:release`) — the two together, because either alone makes one
dispatch give two answers to which sprite it is about. What remains different is
`mouseUpOutSide`: a release outside the sprite that was pressed raises it **on
the release**, to that sprite, and dispatches no `mouseUp` at all, where the
reference raises the `mouseUp` to whatever is under the release and defers
`mouseUpOutSide` to the next press. It stays coherent — the rewrite happens only
on the arm that dispatches `mouseUp`, so `the clickOn` names the recipient during
both messages — and it is the gesture the message pair exists for: sliding off a
control before letting go is how a player backs out of a mis-aimed press, and
Director's own documentation describes the message as firing on that release.
§15 and `ENGINE_TODO.md` have what closing the last one would cost.

The right button does everything the left one's press does bar the two things
that are the *player's* click rather than *a* click — the wait-for-click release
and the palette-cycle abort — and bar `the mouseDownScript`/`mouseUpScript`,
which Director files under the left events (§6.3). `interaction.gd:latch_press`
is that block, once, for both buttons.

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
  *This port:* the four Lingo-settable ones hold source and compile it in the
  property's setter (`preview_lingo_host.gd:_compile_primary`), and
  `preview/event_chain.gd:run_primary_script` runs the result for the mouse and
  the keyboard alike. What runs is the compiled script's **scopeless** part,
  which is what the reference runs: `setPrimaryEventHandler` files the string
  under `kEventScript` and `resolveScriptEvent` then rewrites the event to
  `kEventGeneric`, so an `on <event>` block written inside the string is never
  reached. `rightMouseDown`/`rightMouseUp` have primary slots and no property
  that can fill one; `timeout` has neither, because the timeout clock is
  unbuilt.
- **Sprite script** runs only when the event resolved to a sprite.
- **The whole chain is queued before any of it runs**, and each element then
  re-resolves its own target at execution time against the score *as it is when
  that element runs*. That is why a `go` inside a `mouseUp` handler does not
  cancel the handlers below it — they were queued before the `go` and run
  against the score the `go` has already changed. It is also why a `mouseDown`
  handler that swaps a sprite's member changes which cast script the *next*
  element of the same chain resolves to.
- **`pass` and `dontPassEvent` are one flag, not two mechanisms.** Before each
  element runs, the flag is set to that element's default — true for a primary
  handler, false for everything else. `pass` sets it true, `dontPassEvent` sets
  it false. The next element of the same event id is skipped if the flag is
  false *and* the previous element actually found a script; an element that
  resolved to no script does not count as having consumed anything.
- **Which events stop at the sprite tier.** Only `mouseUpOutSide`,
  `beginSprite`, `endSprite` and `prepareFrame`, and only from D6. Everything
  else — `mouseEnter`, `mouseLeave`, `mouseWithin` included — falls through to
  the cast script, then the frame script, then the movie scripts, in every
  version. A `mouseWithin` reaching a movie script once per tick is Director
  working correctly.
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

*This port:* the focus routing is `director_preview.gd:_dispatch_key`, which asks
`preview/text_focus.gd` who owns the widget and falls back to the frame script
with channel 0. **The arrow substitution is implemented** --
`director/director_keys.gd:char_for` answers characters 28-31 for the four
arrows, matching Director, and `the keyCode` reports 123-126. 30+ sites in this corpus navigate by arrow and every one of
them tests `the keyCode`, so the divergence is unexercised here and is still a
divergence.

**Modifier keys do not generate keyDown events** — shift, control, option/alt and
command/super are recorded into a flag word and return without dispatching.
`the commandDown`, `optionDown`, `shiftDown` and `controlDown` read that same
word and are **independent booleans**; they combine by being read separately, not
by being encoded into `the keyCode`. On Mac in D5+, control-click is optionally
emulated as a right click. A key event also refreshes the timeout clock when
`the timeoutKeyDown` is set.

*This port:* the word is `preview_lingo_host.gd:key_flags`, written by
`preview/input_router.gd:note_modifiers` from the event's own modifier state on
the way past — in the key-down arm and the key-up arm and nowhere else, which is
where the reference writes `_keyFlags` — and a modifier key returns from
`key_event` without dispatching. The four properties read that word. They used to
ask `Input.is_key_pressed` at the moment of the read, which answers about the OS
keyboard rather than about the event being handled: a chord released while the
handler ran read as never held, and a synthesised key event could not set them at
all. `the timeoutKeyDown` is bound and stored; there is no timeout clock for it
to refresh yet, so it is `inert` in §19's sense and `ENGINE_TODO.md` says so.
Control-click emulation is not implemented — this is not a Mac build, and Godot
delivers a real right button.

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

*This port:* `scenes/preview/text_focus.gd`, with the state on the preview node
(`_focus_channel`, `_sel_start`, `_sel_end`, `_member_editable`) and the caret
and selection painted by `preview/text_art.gd` off geometry from
`director/director_text.gd`. Focus is re-arbitrated from `_draw`, which is
literally this section's "pushed into the widget every frame" and also what makes
a paused harness and a running player agree. Insertion, deletion, arrow and
shift-arrow movement, Home/End, Enter, click-to-caret and auto-tab are all there;
typed text goes back to the member through the same `lingo_set_field` a script's
`put x into field` uses, so `field("save1")` reads what the player typed.

**Effective editability is `sprite editable OR member editable`, and the member
half is the one that matters**: 0 of Piposh 2's 816,318 sprite records set the
score's own bit, 0 of Piposh 1's 1,886,362 and 0 of Rating's 847,431, while
`director_cast.gd` byte 25 bit 0 finds 1, 9 and 0 editable members respectively —
`SAVELOAD.dir`'s `save1`, Piposh 1's `Mainmenu`/`Arcade`/`Roullete`/`Caproom`/
`Zuzroom`. A port that read only the score's half measures zero and concludes the
feature is unexercised.

Two things this deliberately does not do. **Auto-expanding dimensions do not flow
back to the sprite** — that needs the size change to reach `sprite_geometry.gd`
and `tools/text_and_shapes.gd` currently asserts the opposite, so it is a change
with its own evidence. And the caret is drawn as a bar with a translucent
selection bar behind the glyphs rather than as Director's destination inversion,
for the same reason §13 gives: there is no destination surface to read.

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

*This port:* `director/director_score.gd:tempo_waits` decodes the delay, the
click wait, the sound waits and the video waits, in both numberings, chosen by
the movie's file version and never by the value;
`director/director_frame_clock.gd` resolves which instruction is in force —
the frame's cell, the carried-forward cell, or a `puppetTempo` — and is what
stops the playhead for it. A sound wait is released by `preview/sound.gd`'s
once-a-tick pass and a video wait by `FrameClock.video_probe`, which nothing
installs yet, so a video wait behaves as a video that has already finished. The
puppet's argument is read in the pre-D6 numbering whatever the movie is, because
it never came out of a score cell; the reference reads it in the movie's, which
turns `puppetTempo 30` into a video wait in every D6 file.

**The sound wait is not unexercised, and the sentence that said so was counting
one title.** Piposh 2's 86 containers write only 246, 247 and 248 across their
61,371 frames — 129 rates, 36 delays, 24 click waits — which is where "no sound
or video wait to miss" came from. *Rating*'s 118 containers write 414 rates, 160
delays, 214 click waits **and 276 sound waits**, 259 of them on channel 1 and 17
on channel 2. So a wait the engine had no cover for is on 276 frames of a title
this port is meant to run, and the only reason it never showed was that the
number was measured on the other corpus. Video waits remain at zero in both. The
delay operand is
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

A handler freezes at `play` and at `go`, and the two use different buffers
because they thaw on different events: `freezeLingoState` pushes onto the
ordinary stack, resumed at step 18 of the next tick; `freezeLingoPlayState` puts
the handler in a slot of its own, resumed when `play done` runs
(`requeueLingoPlayState` moves it to the bottom of the ordinary stack) or the
playhead reaches the end of the movie. `play done` itself does not freeze — the
`_playDone` flag suppresses the `_freezeState` its internal `func_goto` would
otherwise set — so the handler that wrote it runs on. `func_gotoloop`,
`func_gotonext` and `func_gotoprevious` do not freeze at all; only `func_goto`
does.

*This port:* implemented. `lingo/lingo_interpreter.gd` cannot be paused
mid-statement, so it captures a **chain of block positions** on the way out —
for each statement list, the index after the statement that suspended, plus the
counter and bounds of each enclosing `repeat`, plus a marker at each handler
boundary so a later `return` unwinds to the right place. `resume_chain` replays
it from the inside out. The chains are held by `scenes/director_preview.gd`
rather than by the interpreter, because `go to movie` builds a new interpreter
inside the call that froze the handler; Director keeps them on the window for the
same reason. `_advance` thaws at the end of each step, except when `enterFrame`
was what froze — the reference bails out of the tick there, because the frame the
`go` chose has not been entered yet. Freezing is *declined* past eight parked
handlers, which is the pre-suspension behaviour rather than an unbounded queue.
Two gaps remain: a `tell` body may not suspend (the chain would belong to the
other movie's interpreter), and the unwinding is statement-granular, so a `play`
reached from inside an expression lets the rest of that one statement run. Both
are reported. `tools/play_suspends.gd` is the harness and
`tools/suspend_survey.gd` counts the exposure per title.

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

*This port:* **built** — the resolution order, the puppet override, the `CLUT`
reader, colour cycling in both forms and the fades.
`director/director_palette.gd` holds the tables and the pure transforms,
`director/director_palette_state.gd` the state, and
`scenes/director_preview.gd:_begin_palette` the wiring.

What the corpus can prove about it is almost nothing, and that is worth stating
before the design. `tools/palette_survey.gd` counts all four places a palette can
be named, over 86 containers, 61,371 frames and 11,520 bitmap members:

| where a palette is named | count |
| --- | --- |
| `CLUT` chunks | **0** |
| palette cast members (type 4) | **0** |
| bitmap members whose clut id is not system Mac | **0** of 11,520 |
| score frames naming a palette other than system Mac | **0** of 61,371 |
| frames with colour cycling switched on | **0** of 61,371 |
| `palette` in `reference/lingo/` (so `puppetPalette` too) | **0** |

So this is built from the reference and **unverified against this corpus**, which
is an honest state and not the same as absent — the engine has to run other
titles. `tools/palette_cycle.gd` asserts it against hand-built records, labelled
as synthetic, and against the one real frame that carries anything.

Two corrections fell out of the survey. `director_palette.gd`'s header said every
bitmap carries **clut id 0**; the id is **-1**, Director's number for the system
Mac built-in, in all 11,520 — and `builtin()` only warned above zero, so it could
never have fired on either value.

The score's palette channel *is* written, on 267 frames, and is decoded in
`director/director_score.gd:_palette_record`, where the 48-byte record's layout
is written down against the six distinct records that exist. 262 of the 267 name
system Mac with every effect byte zero. Five carry effect bytes and exactly one
carries non-zero flags: `strtgame` f38, flags 0x60, a one-step fade to black,
which the running preview now honours as a 50 ms hold on that frame.

**The one thing still missing is data, not engine.** Rainbow, Pastels, Vivid,
NTSC and Metallic are hand-authored 768-byte tables with no generating rule to
recover; System Mac and Grayscale are generated because their structure *is* the
definition. `builtin()` dispatches on the id, loads the rest from
`data/director_palettes.json` if a title supplies it, and otherwise warns by name
and substitutes system Mac rather than inventing a table — `can_build()` is how a
caller tells "resolved" from "substituted" without reading a log. Filling that
file is a lift from a Director installation, not a reconstruction by eye.

**The cost an RGB renderer pays**, which Director does not: an indexed member is
decoded *through* the table, so a palette switch invalidates every cached
texture. Director swaps a CLUT and the same pixels mean new colours. It costs
nothing until something switches, and a cycle that steps 30 times a second will
re-decode the stage 30 times a second.

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

*This port:* all of §12 is built. Almost none of it is verified against this
corpus, and the two halves of that sentence are separate facts.

**Built.** `director/director_score.gd:_sound_channels` decodes the two score
sound channels (main-channel records 3 and 4, `castLib` at +0 and member at +2 --
the same pairing the frame script, transition and palette records use);
`director/score_sound.gd` holds restart-on-change and `puppetSound` ownership;
`director/director_sound.gd` turns a sound cast member into a stream from a Mac
`snd ` resource, an embedded AIFF or an embedded WAV; `autoload/audio_director.gd`
carries per-channel volume, `the soundLevel`, fades and cue points; and
`director_frame_clock.gd` holds the playhead for a wait-for-sound or wait-for-cue
tempo. Sounds start before the frame's transition rather than after it.

**Unverified, and here is what the corpus can and cannot say.** This game's 86
containers hold 15,297 cast members and **none is of type `sound`**, so no frame
can name one; neither sound channel is written in any of its 61,371 frames; and
its tempo cell holds only 246, 247 and 248 across all 61 scores, never D6's
255/254 or D5's 135/134. So the score-sound path, the member decoder and the
wait-for-sound tempo never execute here. `tools/sound_survey.gd` measures all
three; `tools/score_sound_check.gd` drives them against synthesised fixtures,
which proves the implementation and says nothing about the game. The one thing
no harness can settle until a title ships score sound is **which of records 3
and 4 is channel 1** -- they are taken in address order.

**Cue points do not exist in the audio either**, and the obvious check gets the
right answer for the wrong reason: 168 of the 3,141 `.aif` files carry a `MARK`
chunk and every one declares two markers. None of the 336 sits at a position
inside its own audio -- they are eleven repeated byte patterns with empty names,
at 0x53540000 and 0x007f007f, file after file. Authoring residue.
`tools/aiff_check.gd` asserts on the positions for that reason.

**What the scripts do reach**, counted over `reference/lingo/`: **2,515
`sound playFile`** over channels 1 (2,196), 2 (201), 3 (100) and 4 (18);
**69 `sound stop`**; **245 `soundBusy`**; **67 lines naming
`the volume of sound N`**, 66 writes and 2 reads; **14 `the soundLevel`**, 7 each
way, all in one options screen. `puppetSound`, `sound close`, `sound fadeIn`,
`sound fadeOut`, `cuePoint` and `soundEnabled` are written **nowhere**.

**Headless playback is faithful**, which is not obvious and was measured before
being relied on: Godot's `Dummy` audio driver still mixes on a real clock, so a
sound started headless advances and clears `playing` at the end of the stream --
3,340 ms of wall clock for a 3,376 ms sound. `soundBusy` therefore answers
truthfully in a harness. The catch is the deleted `tools/lib/driver.gd`'s, and it still applies: real frames must
be *awaited*, because a synthetic tick loop advances the runtime's clock and not
the audio server's, and then every wait holds for ever (bugs.md 22).

One knowing deviation: `sound playFile` of the file already playing on a channel
does **not** restart it. Director restarts unconditionally, but the older
renderer replays a frame's sounds on every frame entry and a hold loop re-enters
the same frame every tick. It costs nothing here -- of the 2,515 `playFile`
statements, 11 sit in a handler that also holds the playhead, 9 of those behind a
`soundBusy` guard, and the other 2 are gated on `the mouseDown` and jump away.

**A `playFile` that cannot start still takes the channel**, which is the half of
`soundBusy` a movie depends on and cannot check for itself. Director claims the
channel before it opens the file, so a name the disc does not hold leaves the
channel *empty* rather than still playing what was there: the player is stopped,
the channel reads not busy, and a `soundBusy` poll placed after the `playFile`
releases. Leaving the previous sound in place instead is the difference between a
scene that is silent and a scene that never ends, because the poll would be
waiting on a sound the script had already replaced. Same treatment for a request
that names an empty string, and for a file that resolves but will not decode.
`tools/sound_wait.gd` asserts all three, plus the floor they rest on -- a channel
nothing has played is not busy, and one a sound was started on is.

**The file name is a path and the folder in it is meaning**, matched as a suffix
at both ends. A script builds the request by concatenating globals, so it can
carry segments the engine cannot see -- `the moviePath` of the authoring machine,
a CD drive letter -- and it can equally be *missing* one the disc has, because
the global that supplied it was set by a movie this entry never passed through.
This corpus does both: `soundspath` is `soundspathstart & "days" & "\"` and
`soundspathstart` is written only by `strtgame`'s drive probe. Matching the whole
path, then progressively shorter heads of it, then progressively shorter tails,
is what makes `days\d1prom1.aif` find `SOUNDS/DAYS/D1PROM1.AIF` rather than the
same filename under `SOUNDS/S_DAY1/`. Falling straight from the whole path to the
bare filename is what it used to do, and 315 of this corpus's 3,142 sounds share
a filename with another -- 0 once one folder is kept.

---

## 13. Trails, blend, video, text, shapes

**Trails** — no erase of the old bbox, and the repaint starts *at* the trails
channel rather than clearing to the stage colour. In an immediate-mode Godot
renderer the equivalent is an accumulation buffer that is not cleared, with
non-trail sprites drawn over a cleared copy; it does not fall out for free.

*This port:* **built**, in `scenes/director_preview.gd:_settle_trails`, and
unexercised by this corpus — `tools/ink_survey.gd` counts **0 of 816,318 sprite
records** setting trails (0x40), against 86,845 setting stretch (0x80) out of the
same byte. Reachable from Lingo through `the trails of sprite`, which is how
`tools/trails.gd` drives it and how a movie would.

The accumulation layer is §13's own suggestion, and **the layering is the whole
problem**. Painting it *under* the frame's sprites is the obvious reading of
"the repaint starts at the trails channel", and it makes trails invisible in any
movie with a backdrop: the backdrop is a sprite, it is drawn after the layer, and
it covers every mark. That version passed every headless check while nothing
reached the screen; reading the framebuffer back is what caught it.

What Director does is repaint **dirty rectangles only**, so the port reproduces
the dirtiness rather than the ordering: a channel that moved or swapped member
clears the layer at both the rectangle it left and the one it arrived at — which
is how a non-trails sprite wipes a trail it crosses — a **trails** channel does
not clear the one it left, and a channel that did not change clears nothing,
which is why a static backdrop does not wipe the stage every frame. The layer is
then drawn over the frame. Which flag decides is the current one, not the one the
channel carried when it painted: switching trails off makes a sprite erase behind
itself again immediately, including the mark from its previous move.

The divergence that leaves: a sprite genuinely in front of an old mark that did
*not* move should occlude it and does not. Closing that means real dirty rects
and a persistent composite surface (§16.25), not a patch here.

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
**member**. **Legible text in roughly the right place at roughly the right size,
and not period-accurate glyph rendering**: the font id is carried and unresolved
(no font table here), so the typeface and therefore the advance widths are
Godot's fallback and a caption does not land pixel-for-pixel where Director put
it. No character-box/glyph mask distinction and no scrolling. The box was the
*score's* until Piposh 1's money was found 17px left of centre in every room:
`GlobalMoney` is a 102×19 centred member the score records as 68×32, the same
residue three of its neighbours on the top bar carry, so the amount was centred
in a box 34px too narrow across 33,686 of that game's 82,323 field sprite
records. §1.2 has the rule and `scenes/preview/sprite_geometry.gd:drawn_size` the
change. What is still missing is the *expanding* half: a field clamps to its
`initialRect` and never grows to the laid-out height, so text that overflows its
authored box clips instead of pushing the box open. Measured over all six roots,
that costs a laid-out line in 11 sprite records naming two members, and on one of
those two the line lost is a trailing empty one. Editing
*is* now there (§8.4, `scenes/preview/text_focus.gd`): caret, selection,
`the selStart`/`selEnd`, click-to-caret and focus arbitration, with the caret and
the selection painted by `preview/text_art.gd` and the character-to-pixel mapping
in `director_text.gd:layout`. `put x into field` now reaches the drawn text
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
- **`the beepOn`** makes a click on empty stage beep. It is **off by default**,
  and it gates that one click and nothing else: `LB::b_beep` calls `func_beep`
  without asking, so a script's own `beep()` sounds either way. *This port:*
  implemented in `preview/interaction.gd:latch_press`. It used to gate the `beep`
  builtin instead — which is why the default read `true`, the only value that
  made 154 corpus `beep()` calls audible.
- **Button hilite has a genuinely strange rule**: on mouse-up, if the last
  mouse-*down* was in *any* button, the button under the mouse-up flips its
  hilite. ScummVM notes this makes no sense and does it anyway. *This port:* so
  does `interaction.gd:latch_release`, off `_mouse_down_in_button`. Unexercised —
  0 of the 51,350 members across the three corpora is of type `button`.
- **`the clickOn`** updates on mouse-down always, on mouse-up only when the
  release was over a sprite. *This port:* implemented, **together with its other
  half** — the mouse-up chain is built from the sprite under the release, because
  the clause is coherent only when the property and the recipient name one
  sprite. See `preview/interaction.gd:release` for why the corpus's inventory
  idiom survives it (every drop target it names is a *lower* channel than the
  slot being dragged, so the dragged sprite answers for itself) and for the one
  arm that still diverges, which is `mouseUpOutSide`'s.
- **Immediate sprites** invert the ordering: the script runs on mouse-down and a
  paired mouse-up is synthesised immediately after. Before D4, mouse-up goes to
  the sprite that was *pressed*; from D4, to the sprite under the *release*.
  `the immediate of sprite` is **not a score field** — nothing in the sprite
  record carries it and it survives a frame change untouched, so the only thing
  that ever sets it is the `immediateSprite` builtin. 0 sites in this corpus.
- **The mouse-down block runs once per click, at the primary tier, and it is
  where five separate things are latched**: the beep on an empty-stage click,
  the hilite channel, "the press was in *a* button", the drag channel and grab
  offset for a moveable sprite, and the cast id / script id / immediate flag the
  mouse-up will resolve against. It runs for `rightMouseDown` as well as
  `mouseDown`. Reproducing any one of them without the others is what makes a
  right click and a left click disagree about what a click *is*. *This port:*
  `preview/interaction.gd:latch_press`, one function, called by both buttons
  through `director_preview.gd:_press_click`, with `latch_release` as its mirror.
  Four of the five are there; the fifth's *immediate* flag is not, because
  `the immediate of sprite` is unbound (see the bullet above) — the cast id and
  the script id are, as `_press_member` and the queued chain.
- **`the doubleClick` is derived, not latched**: the engine keeps the last two
  press timestamps and answers "were they within 25 ticks" — about 417 ms — each
  time the property is read. A third press retires the first.
- **Cast script targeting on mouse-up** uses the member under the mouse at the
  *beginning of the mouse-down chain*, not the current one — so a mouseDown
  handler can swap the member and the *old* member still gets the mouseUp.

---

# PART III — GAPS

## 16. Prioritised gap list

> **This section's "Both" is no longer a usable verdict.** It meant "ScummVM and
> this port's *other* renderer agree" — and that other renderer has been deleted,
> so half of every "Both" is now unreadable. Worse, several entries below were
> written against a preview that has since fixed them: **16.3 says the preview has
> no cursor resolution at all**, and `cursor_preview` is green in `gate.sh` today.
> Re-check each entry against the live engine before acting on it; the entries are
> still a useful list of *questions*, and are no longer a list of open gaps.

"Both" = ScummVM and this port's retired renderer agreed. "Differ" = the two
references disagree and the gap needs deciding.

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
`director/director_runtime.gd:1500-1518` was the working implementation and
matched Director's shape; it is deleted, so read it out of git history rather
than the tree. **This entry is stale — the preview resolves cursors today and
`tools/cursor_preview.gd` passes in `gate.sh`.** *Historical change:* add §7.4's resolution to the mouse-move
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

**16.12 No flip. (Neither side.)** §1.8. **Done** in the preview --
`director_score.gd` reads byte 22 and `director_preview.gd:_draw_sprite_texture`
mirrors within the rect, asserted at pixel level by `tools/sprite_flip.gd`. Both
corpora set the bits 0 times, so it is built from the reference and labelled
unverified. The byte it is read from was wrong until now, and that mattered far
beyond flip: see §1.8.

**16.13 Palette hardcoded to system Mac. (Both.)** §11. **Done**, and it was
nearly closed the wrong way: the corpus names no palette but system Mac and
switches cycling on zero times, which is a reason to build this second rather
than a reason not to build it. Resolution order, `puppetPalette`, the `CLUT`
reader, cycling in both forms and the fades are in
`director/director_palette_state.gd`; the tables and transforms in
`director/director_palette.gd`; `tools/palette_cycle.gd` asserts them, synthetic
cases labelled as such. What remains is **data**: five built-in tables that have
no generating rule, loaded from `data/director_palettes.json` when a title
supplies one and warned about by name when it does not.

**16.14 No sprite trails. (Neither.)** §13. **Done** —
`scenes/director_preview.gd:_settle_trails`, driven from `the trails of sprite`
and asserted by `tools/trails.gd` at pixel level. Same story: 0 of 816,318
records set the flag, and the feature is Director's rather than this game's. The
first attempt drew the accumulation layer under the frame, which is invisible
behind any backdrop and passed every headless check anyway.

**16.15 No blend/alpha. (Neither.)** §2.7. **Done, and it was actively wrong
in between.** `director_ink.gd:blend_alpha` read record offset 19 -- the low half
of the *width* -- and divided it by 100 as if it were a percentage, so a
Blend-ink sprite drew at `(width % 256) / 100` alpha: opaque whenever that landed
above 99, an arbitrary translucency whenever it did not, and changing whenever
the sprite was resized. The amount is byte 21 and it is **inverted**:
`the blend of sprite` is 0-100 and the stored byte is `(100 - blend) * 255 / 100`,
so 0 is opaque and 255 invisible. Piposh 2's records take exactly the eleven
values `round(255 * n / 10)`, which is what settled it from the data as well as
from the reference. 1,765 Piposh 2 records reach this; Piposh 1 has no Blend ink
at all.

### Tier 3 — completeness

**16.16 The score's own `moveable` bit was unreadable; `the constraint of
sprite` is still missing.** §7.6. The drag existed but was reachable only through
`the moveableSprite of sprite`, because the score's flag lives in the colour-code
byte at record offset 20 and nothing decoded it. It is decoded now and merged
into the sprite the renderer and the hit test see, the same way trails is, so a
sprite the author ticked "Moveable" on in the Score window is draggable and
click-eligible. 744 of Piposh 1's records set it and none of Piposh 2's, which is
why nothing missed it until a second title was loaded.

`the constraint of sprite` is **done** -- `Interaction.constrain`, applied from
`director_preview._write_position`, so it clamps a script's own `locH`/`locV`
write as well as a drag. It clamps the position *point*, not the rect. Stored as
channel state rather than as a puppet override, because all 10 corpus sites set
it immediately before a `go`, and an override would be discarded on arrival.
**16.17 No editable text, focus, caret or selection.** §8.4. **Done** --
`scenes/preview/text_focus.gd`, asserted windowed by `tools/editable_text.gd`
(real `InputEventKey`s through `Input.parse_input_event`, and the framebuffer
read back over the field's own rectangle). The measurement that decided how to
build it: **0 of 3,550,111 sprite records across Piposh 2, Piposh 1 and Rating
set the score's editable bit**, so the whole of `sprite OR member` rests on the
member half, which nothing decoded. `SAVELOAD.dir`'s `save1` is the one editable
member in Piposh 2, and `member("saveN").editable = <n>` in four of its
behaviours is how the save screen chooses which slot is typeable. Auto-expanding
dimensions flowing back to the sprite is the one clause of §7.7 left open.
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

> **Re-graded after the retired renderer was deleted.** This table used to grade two
> renderers side by side and called the dead one "the working renderer", which is
> now exactly backwards. Rows that said "done in the working renderer" or "done on
> both sides" have had the dead half removed; where the *only* implementation was
> the dead one, the row now reads **gone** and is a real hole, not a done item.
> `movie_player.gd`, `sprite_channel.gd`, `render_model_loader.gd`,
> `director_runtime.gd`, `lingo_host.gd`, `lingo_engine.gd` and
> `tools/sound_state.gd` are all deleted; any surviving citation of them is
> historical.

| Subsystem | This port | Where |
| --- | --- | --- |
| Sprite placement / registration / scaling | **wrong hit rect** — the renderer that had this right is deleted | `director_preview.gd:1007-1013` |
| Stretch semantics | **done**: the score rect is residue unless the author stretched it | `director_preview.gd`; `tools/drawn_size_stability.gd` |
| Flip | **done, unverified**: mirrored within the rect, hit test mirrored to match; 0 of 816,318 and 0 of 1,886,362 records set either bit | `director_score.gd:_snapshot`; `director_preview.gd:_draw_sprite_texture`; `tools/sprite_flip.gd` |
| Sprite record layout | **done**: all 48 bytes of the D7 record accounted for, and no two decoded fields share one | `director_score.gd`; `tools/sprite_record_bytes.gd` |
| Tweening | **decoded, deliberately not consumed**: 88,197 tweened spans in Piposh 1, some changing every frame and some holding one value for 4,255 frames, so the flag is a Score-window attribute and the frame stream already carries the result | `director_score.gd:_snapshot`; `tools/tween_survey.gd` |
| Rotation / skew | n/a below D7; ScummVM does not implement it either | — |
| Film loop compositing | **done** (one dialect now; the second was the retired renderer's) | `director_preview.gd:784-826`; `tools/film_loop_cast.gd` |
| Mouse hit test | **done**: eligibility inside the descent *and* per-pixel for Matte only | `director_preview.gd:_channel_at`; `tools/hotspots.gd` |
| Cursor compositing | **gone** — the only implementation was `render_model_loader.gd:847-911`, deleted. `scenes/preview/cursor.gd` resolves a cursor but the compositing rules are unre-verified | `scenes/preview/cursor.gd` |
| Cursor resolution | **done** | `director_preview.gd:_resolve_cursor`; `tools/cursor_preview.gd` |
| Puppet | **partial**: per-field, no copy-back mask. The whole-sprite dialect went with `sprite_channel.gd` | `director_preview.gd:911-941` |
| Ink | **done** for the five inks this format uses, everything else falls through to Copy per the reference's own fallback chain; colourisation in the preview only | `director_ink.gd` |
| Matte flood fill | **done**: whole border ring, exact match, and the no-white-no-matte rule | `director_ink.gd:key_matte` |
| Visibility | **partial**, and now unharnessed: `tools/puppet_visibility.gd` covered it and was deleted with the renderer it drove. `tools/puppet_persists.gd` drives the release rule directly since the channel model landed | `scenes/preview/channel.gd` |
| Frame ordering | **done** (§16.6) | `director_preview.gd:_advance`; `tools/frame_events.gd` |
| Tempo: fps, delay, wait-for-click | **decoded** in the score, **honoured** | `director_score.gd`; `director_frame_clock.gd` |
| Tempo: wait-for-sound | **done, unverified** — no frame in this corpus writes one: the tempo cell holds only 246, 247 or 248 over 61,371 frames | `director_frame_clock.gd`; `tools/sound_survey.gd` |
| Tempo: wait-for-video | **nothing** | — |
| Transitions | **timed**, not drawn: 5 frames and 4.0 s corpus-wide | `director_transition.gd`; `director_frame_clock.gd` |
| Palette resolution / cycling / fades | **done, unverified**: resolution order, cycling, fades and a CLUT reader, on a corpus that cycles 0 times; five built-in tables are authored data this port does not have | `director_palette_state.gd`; `director_palette.gd` |
| Trails | **done, unverified**: accumulation layer driven by per-channel dirtiness, on a corpus where 0 of 816,318 records set the flag | `director_preview.gd:_settle_trails`; `tools/trails.gd` |
| Blend / alpha | **done**: ink 32 and the has-blend flag, amount is an inverted 0-255 byte at record offset 21 | `director_ink.gd:blend_alpha`; `director_score.gd:_snapshot` |
| Moveable / drag / constraint | **done**: drag reachable from the score's own flag as well as from Lingo; `the constraint of sprite` clamps the position point on every position write, not only on a drag | `preview/interaction.gd:constrain`; `director_preview.gd:_write_position`; `tools/sprite_drag.gd` |
| Editable text / focus / selection | **done** bar auto-expanding size push-back: `sprite OR member` editability, first-editable-claims-focus, movie-level `selStart`/`selEnd`, caret, selection, click-to-caret, auto-tab | `preview/text_focus.gd`; `director_text.gd:layout`; `tools/editable_text.gd` |
| Keyboard, modifiers, key events | **done**: `the keyDownScript`, `the keyCode`, `the key` (both **persist** after the event, which is what lets a frame poll them from its own `exitFrame` -- the idiom Rating is built on), the arrow substitution to characters 28-31, the full Mac virtual key map, and §8.3 focus routing. `the keyUpScript` and modifier carrying are not done | `director_keys.gd`; `director_preview.gd:_dispatch_key`; `preview/text_focus.gd` |
| Primary handlers, pass/dontPassEvent | **partial**: `when <event> then` installs and fires at tier 1 for keys; mouse tiers and `pass` propagation not | `lingo_interpreter.gd:run_primary` |
| Event hierarchy | **partial**: sprite → cast → frame → movie | `director_preview.gd:728-740` |
| Hilite on click | **nothing** | — |
| Score sound channels, restart-on-change | **done, unverified**: decoded and driven, but no cast in this game holds a `sound` member and no frame writes either channel, so the path never executes here | `director_score.gd:_sound_channels`; `score_sound.gd`; `tools/score_sound_check.gd` |
| Lingo sound: playFile, stop, close, fadeIn/Out, soundBusy, volume, soundLevel | **done**, and now **unharnessed** — `tools/sound_state.gd` was the coverage and is deleted. The first two are 2,515 + 69 sites, the rest 245 + 67 + 14, and the fades 0. `soundBusy` is faithful headless | `autoload/audio_director.gd`; `scenes/preview/sound.gd` |
| Sound cue points, `cuePassed`, wait-for-cue | **done, unverified**: 0 of 336 markers in this game's 3,141 files lie inside their own audio and no script or tempo cell reads one, so nothing here fires | `aiff_loader.gd:cue_points`; `director_frame_clock.gd`; `tools/aiff_check.gd` |
| Sound cast members (`snd `, embedded AIFF/WAV) | **done, unverified**: no container in this game holds one | `director/director_sound.gd`; `tools/score_sound_check.gd` |
| Sound fades, `puppetSound`, `sound close` | **done, unverified**: written nowhere in this corpus | `audio_director.gd:step_fades`; `director_preview.gd:lingo_puppet_sound` |
| Digital video | **nothing** | — |
| Text / field rendering | **partial**: legible, not period-accurate; editable now, with a caret and a selection. No character-box/glyph mask split, no scrolling | `director_text.gd`; `preview/text_art.gd`; `director_preview.gd:_draw_text` |
| Shapes | **partial**: rect and rounded rect measured, oval and line unverified | `director_shape.gd` |
| Windows / MIAW / embedded movies | **done**: open, close, forget, `tell`, window properties, geometry, click routing to the topmost window | `director_preview.gd:lingo_open_window`; `tools/window_preview.gd` |
| Movie stack | **partial** | `director_preview.gd:1143` |
| Labels | **done** | `director_labels.gd` |
| Stage clipping | **done** on both sides. 16.1% of sprite records reach past 640x480 | `director_preview.gd:_clip_to_stage` |
| Preloading | **done**: lookahead decode, time-boxed. Worst single step on strtgame fell from 145.7 ms to 0.45 ms | `director_preloader.gd`; `tools/decode_stall.gd` |
| Container packaging (`.dxr` = `.dir`) | **done**: one rule, used by path resolution and by Lingo `=`, `<>`, ordering, `case`, `contains`, `starts` | `director_container.gd` |
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
  attribute byte, but it needs testing against the original. It is now
  *implemented* on that reading and asserted at pixel level, which makes it a
  testable divergence rather than an absence.
- **What the tweened flag is for, beyond the Score window.** Measured: it cannot
  be an instruction to interpolate, because tweened spans exist that hold one
  value for thousands of frames (`tools/tween_survey.gd`). What is *not* settled
  is whether Director uses it for anything else -- the reference only masks it out
  of the dirty test. Nothing here consumes it.
- **The sprite-list index at record offset 8.** It names an entry of the same
  `VWSC`, whose first three fields are the span's first frame, last frame and
  sprite number; that much was confirmed against four spans of one movie and is
  what `tools/tween_survey.gd` groups on. The rest of those entries -- a constant
  `0x00010000`, a constant `0x618d`, and a tail counting 1 to 10 followed by the
  span's length -- is unread and nothing depends on it. The reference reads the
  index and uses it for nothing.
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
- **The palette record's first/last colour transform.** The bytes are stored
  offset — 0x7f reads as index 255 — but all five records in the corpus that
  carry them have first equal to last, so nothing here distinguishes that
  transform from any other. `director_score.gd:_palette_record` stores them raw
  and says so rather than un-applying a guess.
- **The whole of §11 and §13, against the original.** Both are built and both are
  driven entirely by synthetic cases, because the corpus switches cycling on 0
  times, names no palette but system Mac, and sets the trails bit 0 times. The
  rules come from the reference; nothing has been compared to Director running.
  `strtgame` f38's one-step fade to black is the single piece of real authored
  data either subsystem has, and whether it is even visible in the original —
  frame count 1, and the next frame zeroes the channel — was not checked.
- **The five built-in palette tables.** Rainbow, Pastels, Vivid, NTSC and
  Metallic have no table here and no way to derive one; `builtin()` warns and
  substitutes system Mac. Grayscale *is* generated, as a linear ramp, and whether
  Director's own is exactly `255 - i` on every entry is unchecked.
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
