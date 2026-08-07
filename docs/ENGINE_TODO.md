# Known engine gaps, not yet implemented

Behaviour the reference describes and this port does not have. The full
descriptions are in [`DIRECTOR_ENGINE.md`](DIRECTOR_ENGINE.md) and
[`LINGO_SURFACE.md`](LINGO_SURFACE.md).

Entries were verified against ScummVM's Director engine and, where noted, against
"this repo's own working renderer" — which meant `movie_player.gd` /
`render_model_loader.gd`, drawing from a pre-decoded export. **That renderer has
been deleted.** A note here saying the two agreed is still evidence about
Director, and is not a statement about the live code; several such notes turned
out not to hold once checked against `scenes/preview/`. Two cost real debugging
time: `intersects` was listed as implemented while only the retired host bound
it, so every inventory drop in every title silently evaluated to nothing.

This is a work queue, not a bug list — nothing here is a mystery. Each item says
what Director does, what happens without it, and where the change goes. Ordered
by how visible the absence is.


## What is genuinely still missing

Corrected against the code on 2026-08-06, after the windows, palette, trails,
sound and preload work landed, and re-checked on 2026-08-07 after the player was
split into `scenes/preview/`. `DIRECTOR_ENGINE.md` §17 is the full table; this is
the short list of what has no implementation at all.

**Digital video.** §13. No decoder, no sync, no `the movieRate`.

**Wait-for-video tempo.** §9. The tempo cell never holds one in this corpus,
which is a reason to build it last and not a reason to skip it.

**Mask ink (9).** §2.6. Uses the *next* cast member as a 1-bit mask. No member
in this corpus carries it; it currently falls through to Matte.

**`the clickOn` on mouse-up -- deliberately NOT implemented.** §15. Director
updates `the clickOn` again on mouse-up when the release was over a sprite; this
port latches it on the mouse-down and leaves it there. It was implemented once
today and reverted the same day, because taking that rule without its other half
is worse than taking neither.

The two halves: ScummVM resets `_lastClickedSpriteId` from the sprite under the
release **and** delivers the mouse-up to that sprite. This port delivers to the
sprite that took the press (`mouseUp` / `mouseUpOutSide`). With only the first
half, one dispatch gives two answers to "which sprite is this about" -- and the
corpus's inventory drop reads `the clickOn` inside its `mouseUp`:

    set the locH of sprite the clickOn to objectxx

All eight inventory slots carry the same behaviour, so releasing one slot along
the bar wrote the dragged item's home coordinates onto the *neighbouring* slot.
The item stranded mid-bar and an empty marker teleported into its place. Eleven
near-copies of that handler exist across the corpus.

Closing this properly means changing mouse-up delivery too, and that is the
thing that took longest to get right -- see the entry above.

**Cast-script targeting on mouse-up.** §15. The member under the mouse at the
*start of the mouse-down chain* holds the `mouseUp`, so a `mouseDown` handler
that swaps the member still leaves the **old** member answering. The latching
half is done — `director_preview.gd:_click_script` holds the script the press
resolved, and `_press_channel` the channel — but it keys on the script, not on
the member, so a swap that changes which member a channel displays is not
modelled.

**`pass` / `dontPassEvent` propagation.** §6.3, §6.4. The five tiers exist and
run in order, but the chain is resolved lazily and stops at the first handler
that answers. Director queues the *whole* chain up front, which is why a `go`
inside a `mouseUp` handler does not cancel the handlers below it — they are
already queued and run against a score the `go` has changed. `dontPassEvent` is
accepted and ignored, so a primary handler cannot currently stop the message.
Getting the default inverted is the classic Director bug and this port has it in
the safe direction: everything runs.

**`the mouseDownScript` / `the mouseUpScript` hold a handler name, not source.**
§6.3 tier 1. Director's value is a *string of Lingo* compiled on assignment;
this port has no runtime compile-a-string path, so it stores a name — the same
shortcut `the keyDownScript` has always taken, and the reason it has held is that
every site in this corpus sets that one to a name (`fromnow`, `gomenu`). Nothing
sets either mouse property, so the divergence is unexercised as well as unfixed.

**`mouseEnter` / `mouseLeave` fire off the rollover channel, which is right, and
the eligibility trap in §4.3 is not modelled for them.** A sprite whose script
declares *only* `mouseEnter` is correctly not a click target; it is also not
reported by `Interaction.responds_to_mouse`, which searches for `mouseDown` /
`mouseUp` only. D6+ adds "the sprite has behaviours" to eligibility, which would
change the hit test, and the hit test is the thing that took longest to get
right. Left alone deliberately.

**`saveMovie` writes fields and nothing else.** `saveMovie` is implemented
(`director/director_writer.gd`) and writes a real container this engine reopens,
but the only chunks it re-emits are the `STXT` payloads of field members whose
text a script changed. Director saved the whole movie. Three specific holes, in
the order they will be missed: a member's cast entry is not updated when its
text changes, so cached metrics go stale; a rewritten chunk that grew leaves its
old bytes unreferenced rather than adding them to the container's `free` list,
so a repeatedly-saved file grows; and `save castLib` is not bound at all, so a
movie that keeps state in a *linked* cast cannot persist it. The corpus here
needs none of the three — `HEZSAVE.DIR` stores everything in its own internal
cast — which is a reason to have built the rest first and not a reason to close
this.

**Dirty rects.** §6.3. Acceptable to omit, but it forecloses
destination-reading inks and leaves one known trails divergence: a sprite in
front of an old mark that has not moved should occlude it and does not.

**Score recording.** Rarely needed.

## Mobile

[`MOBILE.md`](MOBILE.md) is the standing document. Its input section is now
measured rather than reasoned — `tools/touch_input.gd` drives real
`InputEventScreenTouch` events through `_input` — and it carries **one open
decision that is not an engineering task**: `rollOver` menus have no touch
equivalent, this title's menu is built on one, and the three options each cost
something. Nothing should be built for it until that is chosen.

Two engine consequences recorded there rather than here, because they are
platform facts and not gaps: `Input.set_custom_mouse_cursor` cannot show anything
on Android or iOS, so the whole of `preview/cursor.gd` is invisible on a phone
(and still runs, which is worth short-circuiting); and every `[debug]` binding is
an F-key, so none of them is reachable without a keyboard.


## Built but never compared against Director running

Worth separating from the above, because these are implementations rather than
gaps -- and an unverified implementation is an honest state, not a missing one.

- **Palette** cycling and fades, on a corpus that cycles 0 times. Five built-in
  tables (Rainbow, Pastels, Vivid, NTSC, Metallic) are authored data with no
  generating rule: the engine warns by name and substitutes system Mac rather
  than inventing them. Lifting them from a Director install is the fix.
- **Hilite on click.** §4.6, implemented clause for clause in
  `scenes/preview/hilite.gd`: `isActive()` presence-only, not moveable, not
  puppet, bitmaps only, the member's Auto Hilite info flag with "ink is Matte"
  as the no-cast-info fallback. The inversion is a masked XOR through the matte
  -- the inverted copy carries the source alpha and is drawn *instead of* the
  artwork, so an irregular sprite inverts its silhouette rather than its box. On
  at mouse-down, off when the pointer leaves by the ink-aware test, on again on
  re-entry, off at mouse-up.

  **0 cast members carry the flag in any of the three titles** -- 73,994 +
  282,995 + 75,000 (`tools/hilite_survey.gd`) -- and Piposh 2 cannot reach the
  fallback arm either, since every one of its members has an info block. These
  games swap members instead. So `tools/hilite.gd` drives it from a parsed
  member, the way `tools/trails.gd` does.

  The flag had never been decoded: it is bit 1 of the word at offset 12 of the
  cast info block, which `director_cast.gd:_parse_info` skipped. Two
  corroborations that offset 12 really is the flag word rather than a plausible
  guess -- Piposh 1's only non-zero value is `0x10` on 17 members, every one of
  them a *sound*, which is exactly where the reference reads a sound's looping
  bit; Piposh 2's is `0x40` on 32 bitmaps and 1 shape.

  Two deliberate divergences: hilite follows the channel the press latched
  rather than re-resolving under the pointer, and where an ink keys more than
  the matte does, the destination behind the holes is not inverted -- the same
  limit dirty rects already impose.

- **Editable text, focus, caret and selection.** §8.4/§7.7, in
  `scenes/preview/text_focus.gd`: `sprite OR member` editability,
  first-editable-claims-focus and keeps it while the cast id holds, movie-level
  `selStart`/`selEnd`, caret, selection, insertion, deletion, arrows, Home/End,
  Enter, auto-tab, click-to-caret, drag-to-select, and the typed text pushed back
  to the member through the same store `put x into field` writes. §8.3 routes
  `keyDown` to the focused sprite, channel 0 to the frame otherwise.

  Drag-to-select landed after the rest and is worth its own sentence, because
  its absence had the shape this file exists to prevent: the caret could be
  *placed* with the mouse and nothing could be *selected* with it, which reads
  as "the save screen is a bit awkward" rather than as a missing feature. The
  press anchors `_sel_start`, motion drags `_sel_end` (`TextFocus.drag`, called
  from `director_preview._input` ahead of the router), and the release ends it.
  It does not consume the motion: §7.6's moveable sprite uses the same button.

  **The member half was the whole feature and had never been decoded.** 0 of
  3,550,111 sprite records across the three titles set the score's editable bit;
  every editable field in all of them comes from byte 25 bit 0 of the text
  member's specific block (`director_cast.gd`) -- 1 member in Piposh 2
  (`SAVELOAD.dir`'s `save1`), 9 in Piposh 1, 0 in Rating. A wrong byte offset
  does not land on the save screen of three separate builds.

  Unverified against Director running: auto-tab (no member in any corpus sets
  the bit), the sprite-side editable flag (no record sets it), and Director's
  suppress-on-`keyDown` rule (no script in either corpus declares one). **One
  clause of §7.7 left open**: auto-expanding boxes do not push their laid-out
  size back onto the sprite.

- **`the constraint of sprite`.** §7.6, in `Interaction.constrain` /
  `constraint_box`, applied from `director_preview._write_position`. It clamps
  the position **point**, not the rect, so a sprite legitimately hangs outside
  the box by its registration offset -- measured at 320px of overhang on Piposh
  2 and 22px on SHUFFLE, which is what the harness discriminates on. Constraint
  0 is unconstrained and is the fast path.

  **Not a drag feature**, which is the thing to know before touching it. The
  clamp is on the position write, so a script's own `locH`/`locV` is clamped
  too. SHUFFLE proves it is not merely defensive: sprite 7 is constrained and
  nothing ever makes it moveable.

  Stored as **channel state**, like `the cursor of sprite`, not as a puppet
  override -- and that is settled by the corpus rather than by taste. All 10
  writes are `set the constraint of sprite N to 2` followed immediately by
  `go(marker(1))`, and `sprite_state.effective` discards a channel's overrides
  when the score moves it to another member, so an override-backed constraint
  would have been thrown away on arrival every time.

  The score record has no constraint field: bytes 36-47 hold one distinct value,
  `0x00`, across all 816,318 occupied records in Piposh 2 and all 1,886,362 in
  Piposh 1 (`tools/sprite_record_bytes.gd --all`). The 10 Lingo sites are all in
  SHUFFLE -- the shuffleboard puck fenced to the board. One stated divergence: a
  constraint naming an empty or hidden channel is treated as unconstrained,
  where the literal reference would ask an empty channel for a bounding box and
  teleport the sprite to (0,0).

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
