# The non-Lingo half of the Director engine

`docs/LINGO_SURFACE.md` documents the language: handlers, properties, the
built-in function surface. This document is everything underneath it — the part
that runs whether or not the movie has a single line of script. Sprite
placement, the ink model, mouse hit testing, the puppet/score delta protocol,
the frame clock, transitions, palettes, film loops.

The reference is ScummVM's `engines/director`, read at master. It is GPL, so
nothing here is copied from it: this is a description of behaviour, written from
reading the implementation, in the same sense that a spec is not a
transcription. Where ScummVM and this port's working renderer agree, that is
treated as settled Director behaviour. Where they differ, that is called out.

**Status: in progress.** Sections are being appended as the source is read.
The ScummVM behavioural model lands first because it is the durable half; the
cross-reference against this port follows.

---

## 0. The one-paragraph model

A Director movie is a **score**: a fixed array of *channels*, each of which
holds one *sprite* per frame. At runtime the engine keeps ONE persistent array
of live channels, not one per frame. Playing a frame does not build a new
scene — it applies the score's frame data as a **delta** onto the live
channels, and any channel a script has claimed (puppeted) refuses part or all
of that delta. Everything that goes wrong in a Director port goes wrong because
that sentence was implemented as "rebuild the scene from this frame's data".

---

## 1. Mouse hit testing

**This is the answer to "the preview picks the backdrop instead of the button".**

### 1.1 There are three different "sprite under the cursor" queries

ScummVM exposes three, and they are not interchangeable
(`score.cpp`, `Score::getSpriteIDFromPos` / `getMouseSpriteIDFromPos` /
`getActiveSpriteIDFromPos`):

| Query | Extra filter | Used for |
| --- | --- | --- |
| `getSpriteIDFromPos` | none | raw "what is under the pointer" |
| `getMouseSpriteIDFromPos` | `sprite->respondsToMouse()` | click and hover routing, D4+ |
| `getActiveSpriteIDFromPos` | `sprite->isActive()` | click and hover routing, D3 and below |
| `getRollOverSpriteIDFromPos` | rollOver bbox, see §1.5 | `the rollOver` |

The version split is made once, at the event entry point
(`events.cpp`, `Movie::processSysEvent`): below D4 use the `isActive` variant,
D4 and above use the `respondsToMouse` variant. Piposh 2 is D4-era, so
`respondsToMouse` is the rule that matters here.

### 1.2 The search, exactly

Iterate channels from the **highest index down to 0** — topmost first, because
channel number is the paint order. For each channel evaluate `isMouseIn(pos)`,
which returns one of three values, and act on it:

- **Yes, and the eligibility predicate passes** → return this channel. Done.
- **Yes, but the predicate fails** → *keep going down*. The sprite does not
  absorb the click.
- **Hole** → **abort the entire search** and return 0 ("no sprite").

Falling off the bottom also returns 0.

That middle case is the bug. A naive implementation walks down, finds the
first sprite whose rectangle contains the point, and returns it — then
discovers it is not clickable and reports "nothing here", or worse, treats the
backdrop as the click target. Director does not do that. **An ineligible
sprite is transparent to the mouse regardless of how opaque it is on screen.**
A full-screen backdrop with no script sitting on top of a button is not a
blocker; the search passes straight through it and finds the button.

`kCollisionHole` is the only thing that stops the descent early, and only one
cast type produces it: a **text** member returns Hole when the point is over
its scrollbar arrows (`castmember/text.cpp`, `TextCastMember::isWithin`). The
intent is that a scrollbar swallows the click without being a click target.
Nothing else in the engine ever returns it. If the port has no text
scrollbars, Hole can be ignored — but the shape of the loop should still be
written with the three-way result, because otherwise adding fields later
silently changes click routing.

### 1.3 What makes a sprite eligible

`respondsToMouse()` (`sprite.cpp`) is true if **any** of:

- the sprite is **moveable** (drag-and-drop sprites are always click targets);
- the cast member is a **button**;
- the cast member is a **movie** whose scripts are enabled;
- (D6+ only) the sprite has behaviors attached;
- a **score script** is attached to the sprite's script id, *and that script
  context actually contains* a `mouseDown`, `mouseUp`, or generic handler;
- a **cast script** exists for the sprite's cast id *containing* `mouseDown`
  or `mouseUp`.

Otherwise false.

Two things a naive port gets wrong here. First, it is not enough that the
sprite has a non-zero script id — the handler must exist in the compiled
script. A sprite carrying a script that only defines `mouseEnter` is **not**
a click target. Second, `moveable` alone qualifies: a draggable sprite with no
script at all still takes the click.

`isActive()` is the older D3 rule and is deliberately looser: moveable, or a
button, or *a score script exists*, or *a cast script exists* — presence only,
no handler inspection. Worth implementing both if the port will ever load a D3
movie, because the difference is observable.

### 1.4 Does ink participate? Partly — and asymmetrically

`Channel::isMouseIn` (`channel.cpp`):

1. If the channel is not `_visible`, return No immediately. (`_visible` is the
   channel's own flag, driven by `the visible of sprite`. It is distinct from
   `_hideFromStage`, which is a debugger-only affordance.)
2. Compute the channel bbox — see §2, this is registration-adjusted.
3. If the sprite has a cast member, delegate to
   `cast->isWithin(bbox, pos, ink)`. Otherwise a plain rect containment test.

`isWithin` per type:

- **base / shape / anything unspecialised**: rect containment. That is all.
- **bitmap** (`castmember/bitmap.cpp`): rect containment first — miss means No.
  Then, **if and only if the ink is Matte**, sample the member's matte mask at
  `pos - bbox.topLeft`; a transparent pixel there means No.
- **text**: rect containment, plus the scrollbar Hole case.

So: **Matte ink hit-tests per pixel. Every other ink, including Background
Transparent, hit-tests as a rectangle.** This asymmetry is real and it is the
single most commonly mis-ported detail in this area, in both directions. A
port that makes every transparent-looking sprite per-pixel will let clicks fall
through backdrops that should have caught them; a port that makes everything
rectangular will let a matte-inked irregular sprite steal clicks from its
neighbours. Background Transparent renders per-pixel and hit-tests as a box —
that is not a bug in Director, it is the design.

The matte used for hit testing is the *same* cached matte used for rendering
and for `sprite...intersects`, and it is built at the channel's *current* size
(§4.4), so a scaled sprite hit-tests against a matte regenerated at the scaled
size.

### 1.5 rollOver is a separate, looser test

`the rollOver` uses `Channel::getRollOverBbox()`, which in **D4 and below**
returns the *last non-empty* bounding box when the channel's cast id is
currently 0 — i.e. a sprite the score has blanked still rolls over its old
rectangle. That cached rect is refreshed in `Score::updateCurrentFrame` on
every frame change, for every channel whose cast id is non-zero, and only for
pre-D5 movies. It is a compatibility wart, but games depend on it. D5+ just
uses the live bbox.

`Score::checkSpriteRollOver` is a pure rect test — no matte, no eligibility.

### 1.6 Hilite

`Sprite::shouldHilite()` decides whether a click visually inverts the sprite:
requires `isActive()`, and requires **not** moveable and **not** puppet. For a
bitmap member in D3+ it is driven by the member's **auto-hilite** info flag; if
there is no cast info (common in D3) it falls back to "ink is Matte". QuickDraw
shapes hilite when ink is Matte. The inversion itself is a masked XOR of the
destination through the sprite's matte (`window.cpp`, `Window::invertChannel`),
so an irregular sprite inverts its silhouette, not its box.

---

## 2. Sprite placement and registration points

**This is the answer to "film loops and walk-cycle sprites land in the wrong
place".**

### 2.1 The universal rule

There is exactly one placement path, and every cast type goes through it
(`sprite.cpp`, `Sprite::getBbox`, via `CastMember::getBbox`):

```
regOffset = castMember.registrationOffset(spriteWidth, spriteHeight)
bbox      = Rect(spriteWidth, spriteHeight) moved so its origin is at (-regOffset)
bbox      = bbox translated by sprite.startPoint
```

In plain terms: **screen top-left = startPoint − registrationOffset**.

`startPoint` is what Lingo calls `the locH`/`the locV` of the sprite. It is
**not** the top-left corner. It is the position on the stage where the cast
member's registration point is pinned. A port that treats locH/locV as a
top-left is wrong by the registration offset for every sprite whose offset is
non-zero — which, for bitmaps, is nearly all of them, since the Director
authoring default is the dead centre of the image.

The inverse operation matters too. `Sprite::setBbox` (which is what
`the rect of sprite` writes) sets width and height from the rect, then
back-computes `startPoint = rect.topLeft − bbox.topLeft` using the *new*
dimensions. It also collapses width and height to zero together if either goes
non-positive. If the port implements `set the rect of sprite` by writing a
top-left, it will drift the moment the sprite is also scaled.

### 2.2 Registration offset per cast type

| Cast type | Registration offset | Effect |
| --- | --- | --- |
| base / shape / text | `(0, 0)` | startPoint *is* the top-left |
| **bitmap** | `(regX − initialRect.left, regY − initialRect.top)` | usually the image centre |
| **film loop** | `(initialRect.width()/2, initialRect.height()/2)` | always the centre |
| digital video | base `(0,0)` | top-left |

The bitmap subtraction is not optional. `regX`/`regY` are stored in the
Director *editor's* virtual canvas coordinates, and `initialRect` says where
the image sits on that canvas. Using raw `regX`/`regY` is correct only when
`initialRect.topLeft` happens to be `(0,0)`. When it is not — which happens
routinely for images edited on a scrolling canvas — every instance of that
member is offset by the canvas origin. This is a silent, per-member, constant
displacement, and it looks exactly like "some art is placed wrong and some
isn't".

### 2.3 The offset is SCALED when the drawn size differs from natural size

There are two overloads of the registration offset. The plain one returns the
raw value. The sized one, given the sprite's current drawn width and height,
returns (`castmember/bitmap.cpp`):

```
offset.x * currentWidth  / initialRect.width()
offset.y * currentHeight / initialRect.height()
```

and `Sprite::getBbox` always calls the **sized** overload, passing the sprite's
current width and height.

So the registration offset is rescaled proportionally with the sprite. This is
the likely cause of walk-cycle sprites drifting: a port that applies the
unscaled offset to a scaled sprite is wrong by `(1 − scale) × regOffset`, which
is zero at natural size and grows with the scale error. It does not look like a
constant offset bug, it looks like the sprite "wanders", which is why it gets
misdiagnosed as an animation problem.

For film loops the sized overload is `(currentWidth/2, currentHeight/2)` —
still the centre, so film loops stay self-consistent under scaling.

Note the division guards against a zero-width `initialRect` by clamping the
denominator to 1. A member with a degenerate initial rect therefore gets its
offset multiplied by the full drawn size rather than producing a divide fault —
worth matching, because it is the difference between a wrong sprite and a
crash.

### 2.4 What a film loop uses as its anchor and its size

A film loop cast member's `initialRect` is the **union bounding box of the
loop's contents in the loop's own score coordinate space**. It serves as both:

- the loop's **natural size**, and
- the **origin** that sub-sprite positions are measured against.

Compositing a loop (`castmember/filmloop.cpp`, `getSubChannels`) re-bases every
sub-sprite:

```
subStartPoint' = subStartPoint − filmLoopInitialRect.topLeft + channelBbox.topLeft
```

and then each sub-sprite goes through the **normal** placement rule of §2.1
using its *own* cast member's registration offset. Two subtractions, not one:
the loop's initialRect origin, then the sub-member's registration offset. The
loop's own registration offset (the centre) has already been consumed in
computing `channelBbox`.

A port that treats a film loop's startPoint as a top-left is off by half the
loop size. A port that forgets to subtract `initialRect.topLeft` is off by the
loop's authoring origin. A port that does both is off by their sum, which is
why film loop misplacement usually reads as an arbitrary constant rather than
an obvious "it's centred instead of cornered".

When the loop is drawn at a size other than its natural size, ScummVM scales
sub-sprite positions per axis by `bbox / initialRect`, sets **each** sub-sprite's
width and height to the whole widget rect, and forces the stretch flag. That
last part is almost certainly a ScummVM approximation rather than authentic
Director behaviour — see §Not verified.

The film loop channel also carries its own frame counter, `_filmLoopFrame`,
which is state of the *channel*, not of the member. Two sprites showing the
same loop animate independently.

### 2.5 Cast member swap: position is preserved, not recomputed

`Channel::setCast` (`channel.cpp`) captures the bbox **before** the swap, does
the swap, and then — **only if the new member is a film loop** — adjusts
`startPoint` by `oldBbox.topLeft − newBbox.topLeft`, so the sprite does not
visually jump when the registration offset changes shape. It also resets
`_filmLoopFrame` to 1 on a genuine member change, and restarts a digital video.

Dimension handling on swap is subtle and worth copying exactly
(`Sprite::setCast`): the sprite's width and height are replaced with the new
member's natural size **only when the sprite's `stretch` flag is clear**. In
puppet mode a script routinely sets the dimensions first and *then* the
`castNum`, and expects its dimensions to survive. Digital video is special-cased
further: a member sized to 0×0 by the score is left at 0×0 rather than forced to
native size, because that is the idiom for an invisible timing clock.

`Sprite::setCast` also re-derives the *sprite type* from the member type in
D4+ (bitmap → bitmap sprite, text → text sprite, button → button/checkbox/radio
by the member's button type). If the sprite type and the cast type disagree,
`checkSpriteType()` fails and **the sprite is not drawn at all** — it is treated
as fully transparent rather than as an error. That is a real compatibility
behaviour, not a ScummVM safety net.

---

## 3. Puppet state: what the score preserves and what it re-reads

### 3.1 The score applies a delta, not a snapshot

This is the central mechanism and it is easy to miss when working from an
exported per-frame snapshot.

The runtime holds one persistent `Channel` per score channel, each owning a
live `Sprite`. Playing a frame calls `Score::updateSprites`, which for every
channel calls `Channel::setClean(nextSprite)` where `nextSprite` is the score's
sprite for the new frame. That funnels into `Sprite::replaceFrom`.

`replaceFrom` does **not** copy the whole sprite. Each field is copied only if
the corresponding bit is set in `nextSprite`'s **copy-back mask** — a bitfield
built while *parsing* the frame's delta record (`frame.cpp`, many sites), which
records which fields the score actually wrote on this frame. Fields the score
did not touch keep their live values.

After the pass, `updateSprites` resets every frame sprite's copy-back mask to
"all bits" so that a subsequent full re-read behaves like a full copy.

**Consequence for this port:** an export that stores a complete sprite record
per frame has thrown the delta information away. Replaying it as a full
assignment per frame is *usually* indistinguishable — because a tweened sprite
does have all its fields written — but it is exactly wrong for a channel that a
script has written to, and for `puppetSprite N, FALSE` semantics.

### 3.2 Whole-sprite puppet

If the live sprite's `_puppet` flag is set, `replaceFrom` copies **the script
id, the behavior list and the sprite-info record, and then returns**. Nothing
else. Cast member, position, size, ink, colours, moveable, blend — all
preserved from the live channel. The score is, for that channel, ignored.

So the precise answer to "what does the score preserve versus re-read for a
puppeted channel": it preserves *everything visual* and re-reads only *script
attachment*. That last part is not an accident — a puppeted sprite still picks
up the score's script assignment for the frame, which is how a puppeted sprite
can be given per-frame behaviour.

`Channel::setClean` short-circuits earlier for the same reason: for a puppeted
(or auto-puppeted) channel it assigns only the script id and skips
`replaceSprite` entirely.

### 3.3 Per-field auto-puppet (D6+)

D6 added implicit per-property puppeting: setting `the ink of sprite`,
`the locH`, `the member`, etc. auto-puppets *that property alone*, without
setting the whole-sprite puppet flag. `replaceFrom` therefore guards each field
with both its copy-back bit and its auto-puppet bit.

Auto-puppet is **released** when the score itself writes that property.
`Score::updateCurrentFrame` calls `releaseAutoPuppet` for every channel on every
frame change, passing the incoming frame's copy-back mask; each auto-puppet
property is cleared if the score wrote any of the fields it covers. Note that
height and width are released by a *cast id* write as well as by an explicit
size write.

Auto-puppet setters are no-ops below D6, and are also suppressed while the
whole-sprite puppet flag is on.

For a D4 title this whole subsystem is inert — but the *shape* of it matters,
because it is the same "block the score per field" idea that whole-sprite
puppet implements coarsely.

### 3.4 Fields with hand-written persistence rules

Three fields do not follow the mask:

- **editable** is preserved across the frame if the cast id is unchanged, and
  taken from the score if the cast id changed.
- **immediate** is always preserved from the live sprite.
- **width/height** are copied when the score writes a **cast id**, even if it
  does not write width or height. The comment in ScummVM cites a real title
  that depends on this. The reasoning: changing member implies re-fitting to the
  new member's size.

### 3.5 What resets puppet state

- `Sprite::reset()` clears `_puppet` — used when a sprite record is
  reinitialised, i.e. movie load.
- Turning the puppet flag off in Lingo does not itself restore anything; it
  simply stops blocking, and the *next* frame's delta flows in. Because the
  copy-back masks were reset to "all bits" at the end of the previous
  `updateSprites`, the first frame after un-puppeting copies everything — which
  is the intended "revert to the score" behaviour.
- Auto-puppet is released per property by the score writing that property, as
  in §3.3.
- Nothing in the frame loop clears whole-sprite puppet implicitly. A puppeted
  sprite stays puppeted across frame jumps and across `go to frame`. It does
  **not** survive a movie change, because the sprites are rebuilt.

### 3.6 The dirty test is puppet-aware

`Channel::isDirty` compares the live sprite against the incoming one to decide
whether a re-render is needed — but **only for non-puppet, non-auto-puppet
channels**. For a puppeted channel the comparison is skipped entirely and the
dirty flag has to be set explicitly by whatever wrote the sprite. A port that
computes "did anything change" by diffing frame data will simply never redraw a
puppeted sprite that a script moved. Position changes are excluded from the
dirty test for *moveable* sprites (they are being dragged, and dragging sets
dirty itself), and size changes only count when the sprite is stretched.

---

## 4. Ink rendering

### 4.1 The colour vocabulary

In 8-bit (CLUT) mode Director's palette convention is inverted from what most
people expect: **white is palette index 0 and black is palette index 255**
(`graphics.cpp`, `getColorWhite` / `getColorBlack`). ScummVM returns those
indices literally rather than searching the palette, precisely because a
palette can contain several entries that are also white or black and the ink
rules key off the exact index.

Each sprite carries a **foreColor** and a **backColor**. They default to white
on reset, and for text and button members they are read from the *member*
rather than the sprite. These are the sprite's colours, not the image's.

### 4.2 applyColor: the two rendering modes of every ink

Before any pixel is touched, `setApplyColor` decides between Director's two
rendering modes for the ink:

- **default** — use the full range of colours in the image;
- **applyColor** — reduce the image to some combination of the sprite's
  current foreground and background colour.

The switch is:

- Matte, Mask, Copy, NotCopy: applyColor when `foreColor != black` **or**
  `backColor != white`;
- Transparent, NotTransparent, Background Transparent, Ghost, NotGhost:
  applyColor when **not** (`foreColor == black` **and** `backColor == white`);
- everything else: never.

The two conditions are logically the same statement written two ways, but the
grouping differs and it is worth reproducing rather than "simplifying".

The practical meaning: **a sprite whose fore/back colours are the defaults
renders its bitmap unmodified. A sprite with non-default colours gets its
black pixels repainted foreColor and its white pixels repainted backColor.**
This is Director's colourisation mechanism, and it is why the same 1-bit cast
member appears in a dozen colours across a movie without a dozen bitmaps
existing. A port that ignores fore/back colour will render every one of those
in black and white and the art will look "wrong but not obviously broken".

Text and button sprites disable applyColor at blit time regardless
(`inkBlitSurface`), with colourisation handled earlier in a preprocessing step.

### 4.3 The individual inks

Applied per pixel, `src` being the source pixel and `dst` the destination
(`graphics.cpp`):

- **Copy** — with applyColor off, write `src` straight through. With
  applyColor on: black → foreColor, white → backColor, everything else is
  **left as the destination** (not the source). That last clause surprises
  people; a colourised Copy of a multi-colour image punches holes.
- **Matte** and **Mask** fall through to the same code as Copy. Matte is not
  implemented as a per-pixel ink test at all — see §4.4.
- **Blend** also falls through to Copy when there is no blend factor; with a
  blend factor the alpha path (§4.5) runs first and returns.
- **Background Transparent** — the paper colour is the **sprite's backColor**.
  A pixel equal to backColor leaves the destination alone; anything else is
  copied. Special case for **1-bit images**: the comparison is against *black*
  and the result is *foreColor*, and backColor is ignored entirely. If a mask
  is present the pixel is copied unconditionally, because transparency is
  already handled by the mask.
- **NotCopy** — with applyColor, black → backColor and white → foreColor
  (the swap), other pixels pass through. Without applyColor, the source colour
  is inverted channel-wise and re-matched to the palette.
- **Transparent** — with applyColor or a 1-bit image, black → foreColor and
  everything else leaves the destination. Otherwise it is a genuine bitwise
  **OR** of destination with source in 8-bit (which is what makes white
  transparent in a 1-bit context), and an **AND** in 32-bit.
- **NotTransparent** — as Transparent but keyed on white, and OR-with-inverse
  in the bitwise path.
- **Reverse** — 8-bit bitwise **XOR** of destination with source in the
  1-bit/applyColor/shape case; otherwise "pixel equal to backColor leaves the
  destination".
- **Ghost** — black → backColor, everything else leaves the destination.
  **NotGhost** — white → backColor.
- **Add / AddPin / Sub / SubPin / Light / Dark** — arithmetic inks, done in
  decomposed RGB and re-matched to the palette; Pin variants clamp instead of
  wrapping.

The reason to enumerate these even if a port only implements three is that the
*fallbacks* matter: Blend degrades to Matte, Matte and Mask degrade to Copy,
and a sprite whose colours are default degrades to a plain blit. Implementing
Copy + Background Transparent + Matte correctly, and mapping everything else to
Copy, is a defensible port strategy — mapping everything else to *Background
Transparent* is not.

### 4.4 Matte is a mask, and where the flood fill seeds from

Matte is not a per-pixel comparison. `Channel::getMask` builds (or fetches) a
1-byte-per-pixel mask and the blit loop simply **skips** pixels the mask marks
out; the surviving pixels go through the Copy path.

The mask itself (`castmember/bitmap.cpp`, `createMatte`):

1. The member's image is stretched into a temporary surface **at the channel's
   current bbox size** — so the matte is size-specific, not a property of the
   member alone.
2. The **paper colour is found by scanning the corners and edges only** for a
   palette entry whose RGB is exactly `0xFF,0xFF,0xFF`. Only the border ring is
   scanned; the interior is skipped. In non-CLUT modes it is simply "white".
   If no white is found anywhere on the border, **no matte is built at all**
   and the member is flagged as having none — the sprite then renders and
   hit-tests as a solid rectangle.
3. A flood fill is seeded from **every pixel of all four borders** — the entire
   perimeter, not just the four corners — and fills the region matching the
   paper colour.
4. **Tolerance is exact.** The fill matches the paper colour index exactly;
   there is no tolerance parameter. A JPEG-ish or dithered background will not
   flood, and the matte will be nearly solid.
5. The result is inverted into Director's mask convention: **0x00 where
   transparent, 0xFF where opaque**.

Point 3 is what "matte" means and why it differs from background-transparent:
white pixels *enclosed* by coloured pixels are **not** transparent, because the
fill cannot reach them. A donut with a white hole keeps its hole opaque under
Matte and loses it under Background Transparent. That is the entire difference
between the two inks, and it is also why Matte needs a flood fill rather than a
colour key.

The matte is cached on the cast member and **regenerated whenever the requested
bbox size differs from the cached mask's size**. For a sprite that animates its
scale, that is a full flood fill per size change — worth knowing before
building the same thing.

`Channel::getMask` also decides *when* a matte is needed at all: Matte,
NotCopy, NotTransparent, NotReverse, NotGhost, Blend, Add/AddPin, Sub/SubPin,
Light, Dark all need one, as does Copy when the sprite has a blend factor.
1-bit images are exempted from the matte for every ink except Matte itself
(and a 1-bit Copy sprite has its blend amount forced to zero, because 1-bit
images do not blend the way 8-bit ones do).

### 4.5 Mask ink is a *different* mechanism

Ink type Mask uses **the next cast member by number** (cast id + 1) as a 1-bit
mask bitmap. That member must exist and must be 1-bit. The mask is composited
into a surface the size of the channel, aligned by registration offset, and
clipped. This is a real authoring idiom and a port that ignores it will render
the mask member as a stray sprite or drop the sprite entirely.

### 4.6 Blend / alpha

If the sprite has a blend factor (either the ink is Blend or the thickness byte
carries the has-blend flag), the pixel is linearly interpolated between source
and destination in decomposed RGB and re-matched to the palette — and this path
**returns before the ink switch**, so blending ignores colourisation and
behaves as Matte. Blend amount lives on the sprite and is delta-copied like any
other field.

### 4.7 The fast path

When there is no colourisation, no blend, no shape and no mask, and the ink is
Copy, ScummVM uses a straight surface blit. Everything else is the per-pixel
loop. This is worth reproducing structurally in any port: the overwhelming
majority of sprites in a typical movie qualify for the fast path, and the
per-pixel loop only has to be fast enough for the rest.

---

## 5. Frame and render ordering within one tick

### 5.1 The tick

`Score::step` then `Score::update` (`score.cpp`). In order:

1. **Input events** are dispatched from the queue (mouseDown/mouseUp and the
   handlers they invoke), unless a jump is pending.
2. **idle** event, unless suppressed.
3. (D6+) `mouseWithin` for the hovered sprite; sound cue points.
4. **Sound fades** are stepped.
5. **timeout** event, checked against the tick clock independently of the frame
   delay.
6. **Wait check.** If the frame is not due yet — clock, or wait-for-click, or
   wait-for-sound-channel, or wait-for-video — the update ends here. Video
   playback still gets a widget update and a render so video keeps moving during
   the wait. Frozen scripts get a chance to resume.
7. **exitFrame** for the frame being left — but *not* if the frame is being
   left because of a `go to` (the engine records that a jump set the next
   frame and skips exitFrame in that case).
8. Delay check (`the delay`), which also short-circuits.
9. Expiring behaviors are killed.
10. **`updateCurrentFrame`** — this is where the playhead actually moves:
    resolve the next frame number (explicit jump, or +1, or wrap/end-of-movie
    handling with the movie stack), cache rollOver bboxes for D4-and-below,
    **load the frame data**, release auto-puppets against the new frame's
    copy-back mask, and call **`updateSprites`** which applies the delta to the
    live channels and flags them for drawing.
11. **`updateNextFrameTime`** — decode the tempo channel and set the deadline
    or the wait condition (§6.1).
12. **perFrameHook** (and, D5+, `stepFrame` to the actorList) — *unless* this
    frame has a transition, in which case it runs once per transition subframe
    instead.
13. (D6+) **prepareFrame** broadcast.
14. **`renderFrame`** — the actual drawing (§5.2).
15. **stepMovie** (D3, or D4+ with outdated-Lingo compatibility on).
16. **enterFrame**.
17. **Immediate sprite scripts** for the frame.
18. Frozen-script resumption.

So the ordering answer, compressed: **sprite state is updated from the score
first, then the frame time is computed, then the frame is drawn, and
`enterFrame` runs *after* the draw.** ScummVM cites *Lingo in a Nutshell* for
the placement: the window is drawn between `prepareFrame` and `enterFrame`.
`exitFrame` for frame N runs at the *start* of the tick that will advance past
it, not at the end of frame N's own tick.

A port that runs `enterFrame` before drawing will show one frame of lag on
anything `enterFrame` changes, and a port that runs `exitFrame` at the end of
the same tick as `enterFrame` will run both handlers against the same rendered
state, which is observably wrong for the common "set up in enterFrame, tear
down in exitFrame" idiom.

Almost every step above checks whether a script *froze* (blocked on a `go to`,
an alert, a nested movie) and bails out of the rest of the tick if so. That
"frozen state count" mechanism is how Director makes blocking Lingo work
without a real thread, and a port with a re-entrant interpreter needs an
equivalent or it will run two frames' worth of handlers for one frame.

### 5.2 renderFrame

1. Sound channels are started (in parallel with any transition).
2. Then exactly one of:
   - transition skipped → increment film loops, render;
   - playback paused → update sprites, increment film loops, render;
   - a transition applies → play it (§7), which does its own rendering;
   - otherwise → pre-palette-cycle, set the palette, update sprites,
     **increment film loops**, render, then the palette cycle.
3. Queued sound, then a cursor refresh if flagged.

Note **film loop advancement happens inside the render step**, right before
the window render, and it is skipped while playback is paused. In D4 a film
loop also **freezes while an explicit jump holds the playhead on one frame** —
a natural single-frame loop still advances it. D5+ always animate. Movie cast
members are independent and always step.

### 5.3 Window::render — the dirty-rect strategy

`Window::render` walks channels **in ascending order** (paint order) and, for
each channel flagged `_needsDraw`:

1. Re-render the region it occupied **last** frame (`_lastRenderedBbox`),
   unless it was a trails sprite;
2. re-render the region it occupies **now**;
3. clear the flag and record the new bbox and trail state.

"Re-render a region" (`renderChannel`) means: collect every channel whose bbox
intersects that rectangle, move direct-to-stage video layers to the end, fill
the rectangle with the **stage colour**, and then ink-blit each intersecting
channel in ascending channel order, clipped to the rectangle. Sub-channels
(film loops, embedded movies) are expanded inline at their parent's position in
the order.

**Trails** invert step 1: a trails sprite does not erase its old position, and
`renderChannel` starts the redraw *at* the trails channel rather than filling
the background — so everything below it stays on screen. This is how Director's
trails work and there is no other machinery behind it.

The accumulated rectangles are merged and only those get pushed to the screen.
If nothing is dirty and no video is playing, the render is skipped entirely.

The important structural point for a port built on a retained scene graph:
Director's model is an **immediate-mode painter with explicit dirty
rectangles**, and several behaviours (trails, direct-to-stage video, ink
against the destination) only make sense in that model. Inks like Reverse,
Transparent and Add read the destination pixel — they are not expressible as a
per-sprite texture with a blend mode unless the compositor is ordered and
readable.

---

---

## 6. Prioritised gap list

Ordered by how much of a Director game each affects. "Both" means ScummVM and
this port's working renderer agree, so the behaviour is settled and the only
question is why the preview differs. "Differ" means the two references disagree
and the gap needs deciding, not just implementing.

### Tier 1 — breaks a playthrough

**6.1 The preview has no mouse eligibility filter. (Both.)**
`scenes/director_preview.gd:966-976` descends channels and returns the first
sprite whose rect (optionally, alpha) contains the point. There is no
`respondsToMouse` equivalent — no check for a script, a behaviour, a button, or
`moveable`. The comment at `scenes/director_preview.gd:959-964` already
identifies this and uses the per-pixel test as a stand-in, which it is not: a
backdrop is opaque where the button is. The working side has the filter at
`director/director_runtime.gd:1426-1447`.
*Change:* in `_channel_at`, after the containment test, evaluate eligibility and
**continue the loop** when it fails rather than returning. Eligibility = the
sprite has a behaviour script for this channel/frame, or its cast member has a
script, or it is a button, or it is moveable. Keep the existing per-pixel test
as an additional filter for matte-inked sprites only (§1.4), not as the
eligibility test.

**6.2 The preview has no cursor resolution at all. (Both.)**
There is no cursor code in `scenes/director_preview.gd` — no default cursor, no
per-channel cursor, no call site. `director/director_runtime.gd:1500-1518`
(`cursor_at`) is the working implementation and it matches Director's shape:
descend channels, skip empty and hidden ones, first channel with a valid cursor
pair wins, otherwise fall through.
*Change:* add the resolution described in §7.4 to the mouse-move branch of
`scenes/director_preview.gd:525-574`, plus a movie-global default cursor that
the `cursor` builtin writes. Store per-channel cursor state with the same
lifetime as `visible` — **not** in `_overrides`, which is cleared on room change
at `scenes/director_preview.gd:1073-1074` and on movie change at `:1143`.
Cursor state must survive both.

**6.3 The preview's hit rect and its draw rect use different anchoring rules.
(Both — the port's own working renderer already agrees with ScummVM.)**
`scenes/director_preview.gd:840-849` (`_scaled_reg`, used for drawing) scales
the registration offset by drawn-vs-natural size and falls back to the member
centre. `scenes/director_preview.gd:1007-1013` (`_sprite_rect`, used for hit
testing *and* rollOver) uses the raw offset with a **zero** fallback and no
scaling. For any stretched sprite, or any member with no registration point,
the clickable rectangle is not where the sprite is drawn. ScummVM has exactly
one bbox function used by drawing, hit testing, rollOver and masks
(§2.1); `director/movie_player.gd:187-199` matches it.
*Change:* make `_sprite_rect` call `_scaled_reg`. There must be one rect.

**6.4 Keyboard is entirely absent. (Neither side has it.)**
No `keyDown`/`keyUp` dispatch, no `the key`/`the keyCode`, no modifier state, no
editable-field focus. See §8. For Piposh 2 this may be survivable; for a
Director engine it is not — dialogue skipping, name entry, cheat keys and menu
navigation all live here, and a game that requires typing a name is unplayable.
*Change:* §8.6 lists the concrete pieces.

**6.5 `prepareFrame`/`enterFrame`/`exitFrame` all fire in one step in the
preview. (Differ from ScummVM; the working runtime is closer but also wrong.)**
`scenes/director_preview.gd:515-517` dispatches all three back to back on the
same frame, then advances. Director fires `exitFrame` for frame N at the
*start* of the tick that leaves it, and `enterFrame` for frame N+1 *after* that
frame has been drawn (§5.1). Running all three against one un-redrawn state
breaks the standard "set up in enterFrame, tear down in exitFrame" idiom and
makes `go to` inside `exitFrame` behave differently from the original.
`director/director_runtime.gd` splits them (exitFrame at the top of `game_step`,
enterFrame inside `enter_frame`) which is right in shape, but it has no
`prepareFrame` and no `stepFrame` at all.
*Change:* in `scenes/director_preview.gd:505-523`, move `exitFrame` to the top
of the *next* step, and move the frame advance and the redraw between
`prepareFrame` and `enterFrame`.

**6.6 Nothing implements transitions. (Neither side.)**
See §10. A movie with a transition in the frame's main channel currently cuts.
Director has ~50 transition types and they are used constantly for room
changes. Missing transitions do not break logic, but they make every scene
change look wrong, and — more seriously — a transition consumes real time that
scripts may be timing against.
*Change:* §10.3 gives the minimum viable set.

### Tier 2 — breaks scenes, not playthroughs

**6.7 Film loop child placement disagrees between the preview and the working
renderer. (Differ.)** `scenes/director_preview.gd:822-826` places children
unscaled with a **zero** registration fallback;
`director/movie_player.gd:329-342` scales by `stage_scale` and falls back to the
member centre. ScummVM agrees with `movie_player` (§2.4). The preview's comment
at `:817-821` records this as a deliberate revert on evidence, so the evidence
needs re-examining rather than the code being flipped blind — but ScummVM is
unambiguous that both the scale and the child's own registration offset apply.

**6.8 The film loop registration point is unresolved inside this port.
(Differ.)** `director/director_cast.gd:271-289` deliberately writes **no**
`reg_offset` for a film loop — the comment at `:281-288` says centring "was a
guess and it is wrong", matching only 19-27% of records — while
`director/movie_player.gd:217-230` and `scenes/director_preview.gd:784-789` both
centre anyway. ScummVM is explicit that a film loop's registration offset is the
centre of its `initialRect`, and that the sized overload is
`(currentWidth/2, currentHeight/2)`. The two claims are about different things:
ScummVM describes runtime placement; the cast comment describes agreement with
exported records. Resolve it by testing placement on screen, not by matching
records, and note that ScummVM centres on the **loop's `initialRect`** size
while `movie_player` centres on the **sprite record's** width/height — those
diverge exactly when the sprite is stretched.

**6.9 Ink codes are compared unmasked in the preview. (Both — the loader is
right.)** `scenes/director_preview.gd:673-676` compares the raw ink value;
`director/render_model_loader.gd:829` masks with `& 0x3f` first, and
`director/director_score.gd:23` defines that mask because the top two bits are
the trails and stretch flags. Any sprite with trails or stretch set is
currently mis-classified in the preview and renders opaque.
*Change:* mask before the lookup in `_texture_for`.

**6.10 Matte paper colour is sampled from pixel (0,0) in the preview.
(Differ; neither matches ScummVM exactly.)**
`scenes/director_preview.gd:1383` takes the paper colour from the top-left
pixel. `director/render_model_loader.gd:770-774` votes across all four corners
plus pure white. ScummVM scans the **entire border ring** for an exactly-white
palette entry and, finding none, **builds no matte at all** so the sprite stays
a solid rectangle (§4.4). The preview's single-pixel sample fails whenever the
top-left corner happens to be artwork. Note also that ScummVM's match is
**exact**, with no tolerance; both sides here use a tolerance of 14/255, which
is more forgiving than Director and will eat near-white artwork.

**6.11 Palette is hardcoded to system Mac. (Both — same gap.)**
`director/director_palette.gd:30-33` warns and falls back for any non-zero clut
id; there is no `CLUT` reader. `scenes/director_preview.gd:162` uses one global
palette for the whole movie. Director resolves the palette per frame from the
palette channel, with a score-cached fallback and a movie default (§11). For a
title whose members all carry clut 0 this is inert; for a Director engine it is
a hole, and it also disables palette cycling entirely.

**6.12 No sprite trails. (Neither side.)** `director/director_score.gd:246`
decodes the trails flag and nothing consumes it. Trails are cheap to add in an
immediate-mode renderer (§13.1) and a movie that uses them looks catastrophically
wrong without them — every trail sprite leaves nothing behind.

**6.13 No blend/alpha on sprites. (Neither side.)** The blend amount is not
decoded in `director/director_score.gd`. Pre-D5 movies rarely use it; D5+ do.

### Tier 3 — completeness

**6.14 No `moveable` drag.** `director/sprite_channel.gd:40` stores the flag;
nothing acts on it. Director drags the sprite with the mouse and clamps to
`the constraint of sprite` (§7.6). Piposh 2 has its own inventory drag
(`director/inventory_drag.gd`), so this is a general-engine gap.

**6.15 No editable text / focus / caret.** §8.4.

**6.16 No hilite-on-click.** §1.6. Buttons and matte-inked sprites should
invert while held.

**6.17 No `beginSprite`/`endSprite`, `stepFrame`, `prepareMovie`, `idle`
cadence, `timeout`.** §8.1 and §9.

**6.18 No shapes, no text rendering, no digital video, no Movie-In-A-Window.**
§13, §14.

**6.19 No dirty-rect strategy.** Both sides redraw everything each frame. That
is fine for correctness and it is the right trade in Godot — but it means
destination-reading inks (Reverse, Transparent's bitwise mode, Add/Sub) cannot
be expressed, and trails need explicit modelling rather than falling out for
free (§5.3).

---

## 7. Cursor

### 7.1 Built-in cursor numbers

`cursor N` (`cursor.cpp`, `Cursor::readBuiltinType`):

| N | Cursor |
| --- | --- |
| −1, 0 | arrow (the default) |
| 1 | I-beam |
| 2 | crosshair |
| 3 | crossbar / thick plus |
| 4 | watch (busy) |
| 200 | blank — the cursor is hidden |

Any **other** integer is not a built-in. It is a resource id, looked up as a
`CURS` or `CRSR` resource in the current cast's archive, then every open
resource file, then (Mac only) the main archive. If nothing matches, the value
is masked to its low 7 bits and retried as a built-in — so a bad id degrades to
a visible cursor rather than to nothing. On Windows before D5 ScummVM does not
attempt resource cursors at all and uses the arrow.

**"Empty" is a distinct state.** A cursor counts as empty when its resource id
is the integer 0 and is not a list. That is what lets a channel fall through to
the global cursor. `cursor 0` means "clear", not "arrow explicitly" — the
distinction matters because a cleared channel is skipped in the descent while an
explicitly-set arrow would stop it.

### 7.2 Custom cursors from cast members

The value is a **list of one or two cast member references, in the order
`[data, mask]`** (`Cursor::readFromCast`). Element 0 is the image; element 1, if
present, is the mask. Both must be **bitmap** members. A non-bitmap data member
aborts the whole assignment; a non-bitmap mask is ignored and a maskless cursor
is built. A one-element list is legal.

(D6+ also accepts a bare member reference naming a Cursor Asset Xtra member,
which resolves internally to the same pair. Not relevant below D6.)

### 7.3 How the pair composites, and where the hotspot comes from

Fixed **16×16, cropped from the top-left** of the members. Larger members are
cropped, smaller ones padded with transparency. Per pixel:

- outside the data or mask bounds → transparent;
- mask pixel is **black** (the ink value in Director's 1-bit convention) →
  opaque, and the colour comes from the data member: data black → black, data
  white → white;
- mask pixel is **white** → transparent;
- no mask at all → every in-bounds pixel is opaque.

So the **mask member's black region is the visible silhouette**. This port's
`director/render_model_loader.gd:847-911` (`cursor_image`) implements exactly
this — mask white → alpha 0, data dark → black, data light → white. ScummVM and
the working renderer agree; treat the compositing as settled.

**Hotspot** comes from the *data* member's registration point, as
`(regX − initialRect.left, regY − initialRect.top)` — the same expression as
normal bitmap placement (§2.2), not raw `regX`/`regY`. Two rules this port is
missing at `director/render_model_loader.gd:901-904`:

1. If the hotspot lands **outside** the 16×16 crop, it is **recentred to
   (8,8)**. The port only falls back to the centre when the registration point
   is *absent*, not when it is out of range.
2. **Director on Windows before D5 ignores custom hotspots entirely** and always
   uses (8,8). If this build targets the Windows original, that may be correct
   for every cursor in the game — and it would explain any systematic "the
   cursor points slightly off" feel.

The port's 32-pixel sanity gate (`:881-883`) has no ScummVM equivalent but is
harmless, since anything above 16 is cropped anyway.

### 7.4 Precedence and resolution

There is no cursor channel in the score. Two sources, resolved in
`Score::renderCursor` (`score.cpp`):

1. **Wait-for-click overrides everything.** While the score is waiting for a
   click (§9.2), the cursor is forced to an alternating "click me" up/down pair
   that toggles once per second. Nothing below applies.
2. Otherwise **descend channels from highest to 0**. Take the first channel
   where the point is inside — the same three-way `isMouseIn` result as click
   routing, with Hole aborting the descent — **and** whose cursor is non-empty.
3. If none supplied one, use the score's **global default cursor**, which is
   what the `cursor` builtin sets.

Sprite cursor beats global; higher channel beats lower; a channel with no
cursor is skipped rather than blocking. Note the descent does **not** filter on
`respondsToMouse` — a non-clickable sprite with a cursor set still changes the
cursor. Cursor eligibility and click eligibility are different tests over the
same channel stack, and conflating them is a subtle bug: a decorative sprite
that should change the cursor stops doing so.

### 7.5 Lifetime and reapply cadence

`the cursor of sprite N` lives on the **channel**, not on the score sprite. It
is not part of the frame delta, so it survives frame changes, cast swaps and
score updates — exactly like `the visible of sprite`. This port already models
it that way (`director/sprite_channel.gd:42`, alongside `visible` at `:37`),
which is correct. Nothing in the frame loop clears it; it persists until
overwritten or until the movie changes and channels are rebuilt.

**The cursor is not recomputed per frame.** It is resolved only on: every mouse
move; mouse-button-up; the cursor entering the window (forced); a new movie
starting (forced); and when a "cursor dirty" flag is set, checked at the end of
each rendered frame. Even then it is only pushed to the OS if the resolved
cursor **differs** from the displayed one, compared by (type, resource id)
rather than by pixels. Forced refreshes bypass the comparison.

Consequence, and the direct answer to "what if the member under a stationary
cursor changes": **nothing happens** until the mouse moves or the dirty flag is
set. There is no per-frame re-resolution. A port that re-resolves every frame is
not wrong-looking, but it is doing work Director does not, and it will mask
missing dirty-flag calls.

### 7.6 Moveable sprites and drag

`_moveable` is a normal delta-copied field; the score writes it together with
`editable` and the colour code under one mask bit. Effects:

- it makes the sprite **click-eligible on its own** — a moveable sprite with no
  script at all passes `respondsToMouse`;
- on mouse-down over a moveable sprite the engine records the channel as the
  dragged channel and the offset from the click to the sprite's position; every
  mouse-move sets position to `offset + mouse` and marks the channel dirty. The
  drag ends on mouse-up, or as soon as the sprite stops being moveable;
- moveable sprites are **excluded from the position half of the dirty test**;
- moveable **suppresses hilite**;
- `Channel::setPosition` applies **`the constraint of sprite`**: with a non-zero
  constraint, the new position is clamped into the constraint channel's rollOver
  bbox before being stored. It clamps the *position point*, not the sprite rect,
  so a sprite can overhang the constraint rect by its registration offset. This
  is how sliders and drag-within-a-tray are authored.

### 7.7 Editable sprites

Effective editability is `sprite editable OR cast member editable` — either
suffices. It is preserved across a frame when the cast id is unchanged and
re-read from the score when it changed. The **first** editable text sprite
encountered becomes the window manager's active widget unless an editable widget
already holds focus. Auto-expanding text pushes the widget's dimensions back
onto the sprite each frame and marks the channel dirty, which is why text
sprites are excluded from the "dimensions changed" test everywhere else.

---

## 8. Keyboard, focus, and the event hierarchy

This port has none of this. It is the largest single hole for a general Director
engine.

### 8.1 The full event vocabulary

Engine-generated events, with the version each appeared in
(`lingo/lingo-events.cpp`):

- movie: `prepareMovie` (D6), `startMovie` (D3), `stepMovie` (D3),
  `stopMovie` (D3), `startUp`
- sprite lifetime: `beginSprite`, `endSprite` (D6)
- frame: `enterFrame` (D4), `prepareFrame` (D6), `idle` (D3), `stepFrame` (D5),
  `exitFrame` (D4)
- window: `activateWindow`, `deactivateWindow`, `moveWindow`, `resizeWindow`,
  `openWindow`, `closeWindow`, `zoomWindow` (all D5)
- input: `keyUp` (D4), `keyDown` (D2 as a "when" clause, D4 as a handler),
  `mouseUp`/`mouseDown` (D2 when, D3 handler),
  `rightMouseDown`/`rightMouseUp` (D5), `mouseEnter`/`mouseLeave` (D5/D6),
  `mouseUpOutSide` (D6), `mouseWithin` (D5/D6)
- other: `timeout` (D2 as a when clause), `cuePassed` (D6)

### 8.2 The message hierarchy

For **D4 and above**, an event is queued as a *sequence* of candidate handlers
in precedence order, and the first one that actually handles it consumes the
event — unless the handler calls `pass`, which lets the next candidate run.
The order is:

**primary handler → sprite script → cast member script → frame script → movie
scripts.**

- **Primary handlers** exist only for `mouseDown`, `mouseUp`,
  `rightMouseDown`, `rightMouseUp`, `keyDown`, `keyUp` and `timeout`. They are
  set from Lingo as `the mouseDownScript`, `the keyDownScript` and so on: the
  value is a **string of Lingo source**, which is compiled and registered under
  a synthetic script slot keyed by the event type. The crucial difference from a
  normal handler is the default: **a primary handler passes the event on by
  default**, and must call `dontPassEvent` to stop it. Every other level in the
  hierarchy consumes by default and must call `pass` to continue. Getting this
  inverted is the classic primary-handler bug.
- **Sprite script** is the score script attached to the sprite's script id, and
  it only runs if `channelId` is non-zero, i.e. the event resolved to a sprite.
- **Cast script** is the script on the cast member.
- **Frame script** is the score script in the frame's script channel. Per the D4
  docs: `enterFrame`, `exitFrame`, `idle` and `timeout` go to the frame script
  and then to a movie script; if the frame has no script the message goes
  straight to movie scripts.
- **Movie scripts** are searched in cast-window order, then the shared cast.
  The first one containing a handler for the event wins.

When the event did **not** occur over a sprite, the sprite and cast levels are
skipped entirely and the message starts at the frame script.

**D3 and below have no passing at all**: each event goes to one specific object
class. `mouseUp`/`mouseDown` go to sprite then cast; `exitFrame` goes to the
frame; `idle`, `startMovie`, `stepMovie`, `stopMovie` go to movie scripts;
`keyUp`/`keyDown`/`timeout` are handled *only* by the primary handler.

### 8.3 Keyboard routing specifically

`keyDown` and `keyUp` are dispatched with the channel id of **the sprite owning
the currently active widget** — not the sprite under the mouse. If nothing is
focused, the channel is 0 and the message starts at the frame script. So
keyboard reaches a sprite script only when that sprite is an editable text
field with focus.

`the key` is the ASCII character of the last key event; `the keyCode` is the
platform key code. Arrow keys are special-cased into `the key` as characters
28 (left), 29 (right), 30 (up), 31 (down) — a real Director quirk, because most
non-letter keys do not affect `the key` at all.

**Modifier keys do not generate keyDown events.** Shift, control, option/alt and
the command/super keys are recorded into the modifier flags and return without
dispatching. `the commandDown`, `the optionDown`, `the shiftDown` and
`the controlDown` all read from that same flag word and are independent
booleans — they combine by being read separately, not by being encoded into
`the keyCode`. On Mac, control-click is optionally emulated as a right click in
D5+.

A key event also refreshes the timeout clock when `the timeoutKeyDown` is set.

### 8.4 Editable fields, focus and selection

Focus is the window manager's "active widget". `Channel::setEditable` makes a
text sprite's widget editable and, when it becomes editable, claims the active
widget **only if no editable widget already holds it** — so the first editable
field in channel order wins and later ones do not steal focus. Keyboard events
then route to whichever channel owns that widget.

`the selStart` and `the selEnd` are **movie-level** properties, not per-field:
`Channel::updateGlobalAttr` pushes the movie's selection range into the widget
of any editable text sprite every frame. So the selection is global state
applied to whichever field is current, which is why setting `the selStart`
before focusing a different field behaves oddly in real Director.

Typing, caret movement, Enter and Tab are handled inside the shared Mac text
widget rather than in the Director engine, so ScummVM is not a good spec for
them. What the Director layer contributes is: focus arbitration, the selection
range round-trip, pushing the widget's text back to the cast member when it
changes (`updateFromWidget`), and auto-expanding dimensions flowing back to the
sprite.

### 8.5 Keyboard in the score

Nothing in the score is keyboard-driven except the **wait-for-click** tempo
value, which any mouse click satisfies (§9.2) — not a key. There is no key
channel. Keyboard reaches a movie only through handlers.

### 8.6 What to build here

In dependency order:
1. Modifier flag word plus `the key` / `the keyCode` (including the arrow-key
   character substitutions). Cheap, and several games poll these from `idle`
   without ever using a `keyDown` handler.
2. `keyDown`/`keyUp` dispatch through the hierarchy, with channel 0 when nothing
   is focused. That alone enables dialogue skipping and cheat keys.
3. Primary event handlers with **pass-by-default** semantics, and `pass` /
   `dontPassEvent` for the rest of the hierarchy.
4. Editable field focus, caret and selection. Largest, least often needed.

---

## 9. Timing, waits, idle and timers

### 9.1 The frame clock

The tempo channel value is a single byte, reinterpreted by range (D5 and below,
`Score::updateNextFrameTime`):

- **1 … 120** — frames per second.
- **≥ 256 − maxDelay** — a delay in seconds, computed as `256 − tempo`. The
  `maxDelay` is 120 for D2, 95 for D3 (values above 95 became video waits) and
  60 for D4/D5.
- **128** — wait for a mouse click.
- **135** — wait for sound channel 1; **134** — wait for sound channel 2.
- **136 … 135 + channelCount** — wait for the digital video in that channel.

D6 renumbered all of it: 255/254 are sound-channel waits with a cue point, 248
is wait-for-click, 247 is a delay, 246 is FPS, and anything else is a video
wait — with the actual value carried in a separate tempo cue-point field.

If the frame has no tempo, the previous frame rate carries forward. A **puppet
tempo** overrides the score's, but is itself cancelled the moment the score
writes a tempo or the effective tempo changes.

### 9.2 Waits are a state, not a sleep

`isWaitingForNextFrame` is polled every tick and returns "keep waiting" while
any of the wait conditions holds. Crucially:

- a pending **`go to`** cancels every wait — sound, click and video waits all
  check "are we jumping?" and release if so. This is how a script escapes a
  `wait for click` frame;
- during a wait, **video keeps playing and the window keeps rendering**;
- the wait-for-click state also drives the alternating click cursor (§7.4), and
  is cleared by the mouse-down handler itself, not by the score;
- `the delay` is separate from the tempo wait and is **latched**: only the first
  `delay` call in a run of `exitFrame` iterations takes effect, because the
  score loops on `exitFrame` and would otherwise re-arm it every pass.

### 9.3 Idle and timeouts

`idle` is dispatched once per tick, before the frame update, and is suppressed
for a tick after certain jumps. In D5+ `mouseWithin` is generated alongside it
for the hovered sprite (D5 only while a button is held; D6 always).

`the timeoutLength` defaults to 10800 ticks (3 minutes). The timeout clock is
checked **independently of the frame delay**, so it fires even on a frame that
is waiting. It is reset by mouse-down when `the timeoutMouse` is set, by
key-down when `the timeoutKeyDown` is set, and every frame when
`the timeoutPlay` is set. `timeout` is a primary-handler event.

The tick base is the classic Mac 1/60-second tick, and `the timer` /
`startTimer` are expressed in those ticks.

### 9.4 Recursion and frozen scripts

Because Lingo can block (`go to`, alerts, nested movies), ScummVM maintains a
count of "frozen" Lingo states and checks it after almost every dispatch point
in the tick, bailing out of the remainder of the frame if a handler froze. D4
and below allow unbounded recursion through the per-frame hook; D4+ stop at a
recursion depth of 2 and force a thaw; a count of 64 is treated as runaway.

A port with a synchronous interpreter needs an equivalent guard, or a script
that calls `go to` from `enterFrame` will run two frames' handlers in one tick.

---

## 10. Transitions

### 10.1 Where a transition comes from

Three sources, checked in order (`Score::renderTransition`):

1. a **puppet transition** set from Lingo (one-shot; consumed and cleared);
2. the frame's **transition type** in the main channel, with its duration, area
   and chunk size;
3. a **transition cast member** referenced by the frame, which supplies the same
   parameters from the member.

### 10.2 What a transition is

About 50 numbered types, each mapping to one of 13 algorithms — wipe, reveal,
cover, push, centre-out, edges-in, strips, blinds, checkerboard, boxy, random
lines, dissolve, zoom — plus a direction (horizontal, vertical, both,
dissolve). Duration is in milliseconds and the step count is capped at
`duration × 60 / 1000`, i.e. one step per tick. **Chunk size** controls how
coarse each step is, and **area** selects whether the transition applies to the
whole stage or only the changed rectangle.

The transition renders the *new* frame progressively over the *old* one. During
a transition the per-frame hook is called once per **subframe** rather than once
for the frame — which is why the normal call site is skipped when a transition
is present.

### 10.3 Minimum viable set

If implementing a subset, the ones that appear constantly in real titles are:
wipes (4 directions), dissolve (pixel and boxy), covers and reveals, and
centre-out/edges-in. Everything else can degrade to a wipe of the same
direction, or to a cut. Degrading to a **cut** is safer than degrading to the
wrong direction, because a wrong-direction wipe reads as a bug while a cut reads
as a stylistic choice.

The thing that must not be skipped is the **time**: a transition takes its
duration, and scripts time against it. A port that renders transitions
instantly will run the following frames early.

---

## 11. Palette

### 11.1 Resolving the palette for a frame

`Score::setLastPalette`, in order: the frame's palette channel id, if the engine
actually has that palette loaded; otherwise the **score-cached** palette id
(what the palette would be given the frames before this one); otherwise the
**movie default** palette. Director tolerates references to palettes belonging
to long-deleted cast members, which is why every step re-checks existence rather
than trusting the id.

A **puppet palette** short-circuits all of it.

The palette is switched immediately when either colour cycling is active or the
resolved id came from the cache (meaning the score was jumped into) — otherwise
the change is staged for the transition machinery.

### 11.2 Palette effects

The palette channel carries: a first and last colour index, a speed in FPS, a
cycle count, and flags for **colour cycling**, **over time**, and
**auto-reverse**.

- **Colour cycling** rotates palette entries between first and last. With
  *over time*, one step per frame transition. Without, the **entire cycle runs
  inside one frame transition** — a blocking loop that steps the palette,
  redraws, pumps events, and sleeps to hit the requested speed. A click aborts
  it and restores the palette.
- **Auto-reverse** runs the cycle backwards afterwards.
- Cycling state is keyed by palette **id only**, so switching cycle
  configurations on the same palette keeps the mutated offset rather than
  resetting — an authentic quirk.
- Speed 30 is treated as unbounded (a 10 ms floor).
- Without cycling, the palette channel does a **fade** between the old and new
  palettes over a number of steps, with pre-frame and post-frame variants
  depending on flags.

### 11.3 Why this matters even for a modern renderer

If the port renders through RGB textures baked at load time, palette effects are
invisible — the whole mechanism is a no-op. That is an acceptable trade, but it
must be a *decision*: a game that fades to black through the palette will simply
not fade, and a game that animates water or fire by cycling will be static. The
cheap partial is to implement cycling as a per-frame recolour of the affected
members' textures for the index range concerned.

---

## 12. Sound

- **Two score sound channels** (plus puppet channels above them). The frame's
  main channel carries a cast member id per sound channel.
- On a frame change, a sound channel restarts only if its member **changed** —
  and even then, D6 compares against the previous frame explicitly while earlier
  versions restart more eagerly. A port that restarts a looping sound every
  frame will stutter; a port that never restarts will miss re-triggers of the
  same sound.
- Sounds start **in parallel with a transition**, before the transition is
  played, not after.
- **Fades** are stepped once per tick from the top of `Score::update`, ahead of
  everything else, and are also stepped inside the blocking palette-cycle loop
  so a fade continues through a cycle.
- **Cue points** are D6+; `cuePassed` is dispatched from the idle path.
  Wait-for-sound-cue tempo values carry a cue index where −1 means "next" and
  −2 means "end".
- Film loops carry their **own** sound channel assignments per loop frame, which
  the host channel can query. A film loop with sound is therefore a second
  source of sound events independent of the score.
- `soundBusy` is what wait-for-sound-channel polls.

---

## 13. Sprite features, video, text and shapes

### 13.1 Trails

A trails sprite is not erased before being redrawn: the engine skips the
"repaint the old bbox" step, and when repainting the current region it starts
the composite **at the trails channel** rather than clearing to the stage
colour, so everything below stays. That is the whole mechanism. In a
retained/immediate Godot renderer the equivalent is an accumulation buffer that
is not cleared, with non-trail sprites drawn over a cleared copy — it does not
fall out for free the way it does in a dirty-rect painter.
`director/director_score.gd:246` already decodes the flag.

### 13.2 Blend

Blend amount lives on the sprite, delta-copied like any other field, and is
signalled either by the ink being Blend or by a flag in the thickness byte. The
blend path pre-empts the ink switch entirely, so a blended sprite composites as
Matte regardless of its nominal ink and ignores colourisation (§4.6).

### 13.3 Digital video

- A video sprite has a channel-level movie time, rate, start and stop time.
- **Direct-to-stage** video bypasses the compositor: such channels are moved to
  the **end** of the paint order for their rectangle, and they count as trails
  (their old position is not erased).
- Starting/stopping is driven by cast-member identity changes on the channel:
  swapping in a different video member rewinds and starts it; swapping out
  stops, seeks to zero and detaches.
- A video the score sizes to **0×0** is deliberately kept at 0×0 rather than
  forced to native size — that is the idiom for an invisible audio/timing clock,
  and a port that "fixes" the zero size will pop a video onto the screen.
- Video channels force a render every tick even while the score is waiting.

### 13.4 Text and fields

- Text members render through a widget; the sprite's width/height are taken
  **from the widget** after layout, not from the score, and auto-expanding text
  writes its size back to the sprite.
- Text uses two different mask surfaces depending on ink: a **character box**
  mask for the Matte-family and arithmetic inks, and a **glyph** mask for the
  transparent/reverse/ghost family. Colourisation for text is done in a
  preprocessing step rather than in the blit.
- Scrollbars belong to the field and are the only producer of the
  hit-test Hole result (§1.2).
- `the selStart`/`selEnd` are movie-global (§8.4).

### 13.5 Shapes (QuickDraw)

- Sprite types 1–8 plus thick line are QuickDraw shapes drawn by primitives, not
  from a bitmap: rectangle, rounded rectangle, oval, two line directions, and
  outlined variants. From D3 a **shape cast member** carries its own shape type
  and fill flag, which override the sprite type.
- Shapes carry a **pattern** (from a built-in pattern table) and a line
  thickness; for outlined shapes a thickness of 1 means invisible, so the stored
  value is decremented before use.
- Patterns 57–64 are **tiles**, which come from the movie's tile table and fall
  back to built-in tiles.
- Shapes get their own matte, built by drawing the filled shape into a scratch
  surface and flood-filling from the border — the same algorithm as a bitmap
  matte (§4.4) but with the shape as the source. This is what makes an oval
  shape hit-test as an oval.
- Shapes are colourised by the drawing primitives rather than by the ink pass.

---

## 14. Windows, stage and Movie-In-A-Window

- The stage is a window like any other. `Window` owns the stage colour, the
  dirty rect list, the composite surface, and the current movie.
- **Stage colour** is what every non-trails repaint fills with, and changing it
  marks everything dirty. It is *not* black by default.
- A movie can open further windows and run a movie in each — Movie-In-A-Window.
  Each window has its own score, its own Lingo state, and its own frozen-state
  stack, and Lingo state is explicitly moved between windows on a switch. Window
  events (`openWindow`, `closeWindow`, `activateWindow`, `moveWindow`,
  `resizeWindow`, `zoomWindow`) are D5+.
- An **embedded** movie (a movie cast member) is special: it never renders to
  the shared window and its channels never create widgets. The host composites
  it through the sub-channel mechanism at the host sprite's position — the same
  path film loops use. A port that lets an embedded movie draw itself will paint
  it at its own native origin, ignoring where the host sprite is.
- `the stageRect`, window movement, modality, titles and borders are all window
  properties. A **modal** window blocks the parent.
- A movie can push the current movie onto a **movie stack** and return to it,
  including the frame to resume at — that is how "go to movie, then come back"
  works, and reaching the end of a movie pops the stack rather than looping if
  the stack is non-empty.

---

## 15. Other engine behaviours worth knowing

- **End of movie**: reaching past the last frame pops the movie stack if there
  is one, otherwise **wraps to frame 1**. It does not stop.
- **Labels** are a sorted list mapping names to frame numbers, with
  next/previous label navigation and a "current label" tracked as the playhead
  moves.
- **Score recording** (`beginRecording`/`endRecording`) writes sprite state back
  into the score. ScummVM implements the score writers; the mechanism exists and
  a game can use it to build animation at runtime.
- **Cast member erase and reload**: a member flagged erased is dropped and both
  the current and next sprite re-resolve their cast pointers mid-update. A
  member whose filename changed is flagged for reload.
- **Sprite type versus cast type mismatch** makes the sprite invisible rather
  than an error (§2.5).
- **`the beepOn`** makes a click on empty stage beep.
- **Button hilite has a genuinely strange rule**: on mouse-up, if the last
  mouse-*down* was in *any* button, the button under the mouse-up flips its
  hilite. ScummVM notes this makes no sense and does it anyway because Director
  does.
- **`the clickOn`** is the last clicked sprite, updated on mouse-down always and
  on mouse-up only when the release was over a sprite.
- **Immediate sprites** invert the mouseDown/mouseUp ordering: an immediate
  sprite's script runs on mouse-down, and the engine synthesises a paired
  mouse-up event immediately after. Before D4, mouse-up goes to the sprite that
  was *pressed*; from D4 it goes to the sprite under the release.
- **Cast script targeting on mouse-up** uses the cast member that was under the
  mouse at the *beginning of the mouse-down chain*, not the current one — so a
  mouseDown handler can swap the member and the *old* member still gets the
  mouseUp.

---

## 16. What this port has, subsystem by subsystem

| Subsystem | ScummVM | This port | Where |
| --- | --- | --- | --- |
| Sprite placement / registration | full, scaled | **done** in the working renderer, **wrong in the preview's hit rect** | `movie_player.gd:187-199`; `director_preview.gd:1007-1013` |
| Film loop compositing | full | **done, two dialects** | `movie_player.gd:247-349`; `director_preview.gd:784-826` |
| Mouse hit test | descend + eligibility + matte | **partial**: working side has eligibility, no per-pixel; preview has per-pixel, no eligibility | `director_runtime.gd:1426-1447`, `:1080-1083`; `director_preview.gd:966-976` |
| Cursor | full | **partial**: compositing done, resolution only on the working side, **nothing in the preview** | `render_model_loader.gd:847-911`; `director_runtime.gd:1500-1518` |
| Puppet | whole-sprite + per-field + delta mask | **partial**: whole-sprite on the working side, per-field ad hoc in the preview, no copy-back mask anywhere | `sprite_channel.gd:55-74`; `director_preview.gd:911-941` |
| Ink | ~18 inks, colourisation, mask ink | **partial**: Copy / BackgroundTrans / Matte only, no fore/back colourisation | `render_model_loader.gd:828-844` |
| Matte flood fill | border ring, exact match, no-white → no matte | **partial**: different paper sampling, tolerant match | `render_model_loader.gd:765-794`; `director_preview.gd:1374-1422` |
| Frame ordering | prepare/enter/exit split around the draw | **partial** | `director_runtime.gd` split; `director_preview.gd:515-517` collapsed |
| Tempo: fps | yes | **done** | `director_score.gd:161-163` |
| Tempo: delay, wait-for-click | yes | **done** | `director_score.gd:252-253` |
| Tempo: wait-for-sound, wait-for-video | yes | **nothing** | — |
| Transitions | ~50 types | **nothing** | — |
| Palette resolution / cycling / fades | full | **nothing**; one hardcoded palette | `director_palette.gd:30-33` |
| Trails | yes | **nothing** (flag decoded, unused) | `director_score.gd:246` |
| Blend / alpha | yes | **nothing** (not decoded) | — |
| Moveable / drag / constraint | yes | **nothing** (flag stored, unused) | `sprite_channel.gd:40` |
| Editable text / focus / selection | yes | **nothing** | — |
| Keyboard, modifiers, key events | full | **nothing** | — |
| Primary event handlers, pass/dontPassEvent | yes | **nothing** | — |
| Event hierarchy | 5 levels, version-dependent | **partial**: preview does sprite → cast → frame → movie | `director_preview.gd:728-740` |
| Hilite on click | yes | **nothing** | — |
| Sound channels 1-2, restart-on-change | yes | **partial** | `director_runtime.gd` frame sounds |
| Sound cue points, fades | yes | **nothing** | — |
| Digital video | full | **nothing** | — |
| Text / field rendering | full | **nothing** (non-bitmaps produce no texture) | `director_preview.gd:653` |
| Shapes | full | **nothing** | — |
| Windows / MIAW / embedded movies | full | **nothing** | — |
| Movie stack, go-to-movie-and-return | yes | **partial** | `director_preview.gd:1143` |
| Labels | yes | **done** | `director_labels.gd` |
| Stage clipping | yes | **done** on the working side, **absent in the preview** | `movie_player.gd:43-44` |
| Dirty rects | yes | **nothing** (full redraw) — acceptable | — |
| Score recording | yes | **nothing** — rarely needed | — |

---

## 17. Not verified

Things stated above that were inferred rather than read, or read but not
cross-checked against real behaviour:

- **What sets the cursor-dirty flag.** The flag is only cleared in `score.cpp`;
  the setter is in `lingo/`, which was not read. I assume the `cursor` and
  `the cursor of sprite` setters set it. If implementing, set it from both plus
  a cast swap on a channel with a cursor.
- **Film loop sub-sprite sizing under scale.** ScummVM sets *every* sub-sprite's
  width and height to the whole widget rect and forces stretch. That looks like
  an approximation rather than authentic Director; I have not confirmed it
  against a real title. Treat it as low confidence.
- **Whether the Windows pre-D5 "ignore cursor hotspots" rule is authentic
  Director or a ScummVM workaround.** The ScummVM comment is itself phrased as a
  question.
- **Text widget internals** — typing, caret, Enter/Tab — come from ScummVM's
  shared Mac GUI, not from the Director engine, so ScummVM is not a reliable
  spec for them. Only the focus arbitration and selection round-trip described
  in §8.4 were read.
- **The exact D6 tempo cue-point encoding** was read but not reasoned about;
  irrelevant below D6.
- **Whether this port's film loop centring is right** — §6.8 is a genuine
  conflict between ScummVM's runtime rule and this port's record-matching
  evidence, and I did not run anything to settle it.
- **Sound restart semantics below D6** were read only in outline.
- **`the timer` / `startTimer`** are described from the tick base and the
  timeout code; the builtins themselves are in `lingo/`.
- **Nothing here was executed.** No harness was run, no frame was rendered, no
  number in this document was measured. Every claim about ScummVM is from
  reading source; every claim about this port is from reading source and from
  the structural survey, not from observed behaviour.

---

## 18. Files read, and files skipped

**Read in full or in the relevant part** (ScummVM `engines/director` at master):
`sprite.cpp`, `sprite.h`, `channel.cpp`, `channel.h`, `score.cpp` (play loop,
frame update, tempo, cursor, sprite-at-pos, palette cycling, film loops),
`window.cpp` (render, renderChannel, inkBlitFrom, invertChannel),
`graphics.cpp` (ink pixel functions, applyColor, blit surface, colour
constants), `cursor.cpp`, `cursor.h`, `events.cpp`,
`castmember/castmember.cpp`, `castmember/castmember.h`,
`castmember/bitmap.cpp` (registration, matte, isWithin),
`castmember/filmloop.cpp`, `castmember/text.cpp` (isWithin only), `types.h`
(collision, transition and ink enums), `frame.cpp` (copy-back mask sites),
`transitions.cpp` (type and algorithm tables).

**Fetched and consulted more briefly**: `castmember/shape.cpp`,
`castmember/digitalvideo.cpp`, `castmember/transition.cpp`,
`castmember/palette.cpp`, `cast.cpp`, `cast.h`, `movie.cpp`, `movie.h`,
`score.h`, `frame.h`, `window.h`, `images.cpp`, `picture.cpp`,
`graphics-data.h`, `spriteinfo.h`, `util.h`, `director.h`, `types.cpp`.

**One deliberate exception to the "skip lingo/" rule**: `lingo/lingo-events.cpp`
was read for §8.2. The event hierarchy, the primary-handler pass semantics and
the sprite/cast/frame/movie precedence are engine behaviour, not language
surface, and they are not described anywhere else in the tree.

**Skipped, and why**: the rest of `lingo/` (the language surface, already
covered by `docs/LINGO_SURFACE.md`); all of `xlibs/` and `lingo/xtras-cast/`
(per-title external code, not engine behaviour, with the single exception of the
Cursor Asset Xtra reference in §7.2 which surfaced through `cursor.cpp`);
`debugger/` and `debugger.cpp` (developer tooling); `detection*.{cpp,h}` and
`game-quirks.cpp` (per-title identification and workarounds); `archive*.cpp`,
`resource.cpp`, `stxt.cpp`, `rte.cpp` (container parsing — this port has its own
readers and `docs/ENGINE.md` covers the format); `tests.cpp`, `fonts.cpp`,
`metaengine.cpp`, `credits.pl`, `module.mk`, `POTFILES`, `configure.engine`
(build and housekeeping); the `writeCastData`/`writeVWSCResource`/
`archive-save.cpp` save paths throughout (this port does not write Director
files).
