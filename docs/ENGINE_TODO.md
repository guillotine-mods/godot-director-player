# Known engine gaps, not yet implemented

Behaviour the reference describes and this port does not have. Every entry was
verified against ScummVM's Director engine and, where noted, against this repo's
own working renderer; the full descriptions are in
[`DIRECTOR_ENGINE.md`](DIRECTOR_ENGINE.md) and [`LINGO_SURFACE.md`](LINGO_SURFACE.md).

This is a work queue, not a bug list — nothing here is a mystery. Each item says
what Director does, what happens without it, and where the change goes. Ordered
by how visible the absence is.


## What is genuinely still missing

Corrected against the code on 2026-08-06, after the windows, palette, trails,
sound and preload work landed, and re-checked on 2026-08-07 after the player was
split into `scenes/preview/`. `DIRECTOR_ENGINE.md` §17 is the full table; this is
the short list of what has no implementation at all.

**Editable text, focus, caret and selection.** §8.4. Effective editability is
the sprite's flag OR the member's, the first editable sprite takes focus, and
`keyDown`/`keyUp` route to the focused sprite rather than the one under the
mouse. Keyboard input itself is done; this is the widget half.

**Hilite on click.** §4.6. `shouldHilite()` needs `isActive()` and requires not
moveable and not puppet; for a bitmap it is driven by the member's auto-hilite
info flag, falling back to Matte ink. The inversion is a masked XOR through the
sprite's matte, so an irregular sprite inverts its silhouette rather than its
box. This is the feedback that tells a player a click landed.

**Digital video.** §13. No decoder, no sync, no `the movieRate`.

**Wait-for-video tempo.** §9. The tempo cell never holds one in this corpus,
which is a reason to build it last and not a reason to skip it.

**`the constraint of sprite`.** §7.6. A dragged position is clamped into the
constraint channel's bounding box before being stored -- it clamps the position
*point*, not the rect, so a sprite may legitimately hang outside the box by its
registration offset. Drag itself is done.

**Mask ink (9).** §2.6. Uses the *next* cast member as a 1-bit mask. No member
in this corpus carries it; it currently falls through to Matte.

**`mouseUpOutSide` and the D6 mouse events.** §8.1. `mouseEnter`, `mouseLeave`,
`mouseWithin` and `mouseUpOutSide` do not exist here. The consequence that is
already load-bearing is the last one: Director sends a sprite `mouseUp` only if
the button came up over the sprite that took the `mouseDown`, and
`mouseUpOutSide` otherwise, whereas `preview/interaction.gd:release` sends
`mouseUp` to the press's recipient unconditionally. A drag is unaffected — a
moveable sprite is under the cursor by construction, so the two rules agree —
but a press-here-release-there click over-delivers.

Two neighbouring rules from §15 are unimplemented for the same reason and are
worth reading together with it: **`the clickOn` updates on mouse-up too**, when
the release was over a sprite (this port latches it on the mouse-down only), and
**cast-script targeting on mouse-up** uses the member under the mouse at the
start of the mouse-down chain, so a `mouseDown` handler that swaps the member
still leaves the *old* member holding the `mouseUp`. The latching half of the
second one is now done — `director_preview.gd:_click_script` holds the script the
press resolved — but it keys on the script, not on the member.

**Mouse primary handlers and `pass` propagation.** §6.3. `when <event> then`
installs and fires at tier 1 for keys; the mouse tiers and real `pass` /
`dontPassEvent` propagation need the hierarchy to queue the whole chain rather
than stopping at the first handler that answers.

**Dirty rects.** §6.3. Acceptable to omit, but it forecloses
destination-reading inks and leaves one known trails divergence: a sprite in
front of an old mark that has not moved should occlude it and does not.

**Score recording.** Rarely needed.

## Built but never compared against Director running

Worth separating from the above, because these are implementations rather than
gaps -- and an unverified implementation is an honest state, not a missing one.

- **Palette** cycling and fades, on a corpus that cycles 0 times. Five built-in
  tables (Rainbow, Pastels, Vivid, NTSC, Metallic) are authored data with no
  generating rule: the engine warns by name and substitutes system Mac rather
  than inventing them. Lifting them from a Director install is the fix.
- **Trails**, on a corpus where 0 of 816,318 records set the flag.
- **Score sound channels, `snd ` decoding, cue points and fades** -- no cast in
  this game holds a sound member, so all of it is proved against synthesised
  bytes only.
- **Flip** is decoded and applied -- `scenes/preview/sprite_art.gd` mirrors the
  draw with a negative extent and mirrors the hit-test sample with it, so the
  clickable pixels are not the mirror image of the visible ones. Unverified
  because 0 of Piposh 2's 816,318 sprite records and 0 of Piposh 1's 1,886,362
  set either bit; `tools/sprite_flip.gd` drives it from a synthetic record.
- **Rounded-rect, oval and line shapes** are drawn by `director/director_shape.gd`.
  Of the corpus's 169 shape members, 167 are plain rectangles and 2 are rounded
  rectangles; no member is an oval or a line, so those two are the unexercised
  pair. Director stores no corner radius, so the rounded inset is chosen to look
  like QuickDraw's default rather than decoded -- that is the part to check first
  against Director running.

## The rule that governs this list

A measured zero is a reason to build something *last* and to mark it unverified.
It is never a reason not to build it -- see `AGENTS.md`, "Build Director, not
this game". Several entries above were closed the wrong way once already and had
to be reopened.

An entry is closed when the reference section it names is implemented, not when
the current game stops misbehaving -- see `AGENTS.md`, "The reference documents
are the specification". Closing one is part of landing the change, because this
list is only worth reading if it is true: two entries above described the code as
it was several commits earlier, and both understated what was already built.
