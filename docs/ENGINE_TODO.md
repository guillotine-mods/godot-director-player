# Known engine gaps, not yet implemented

Behaviour the reference describes and this port does not have. Every entry was
verified against ScummVM's Director engine and, where noted, against this repo's
own working renderer; the full descriptions are in
[`DIRECTOR_ENGINE.md`](DIRECTOR_ENGINE.md) and [`LINGO_SURFACE.md`](LINGO_SURFACE.md).

This is a work queue, not a bug list — nothing here is a mystery. Each item says
what Director does, what happens without it, and where the change goes. Ordered
by how visible the absence is.

## Placement

**Withdrawn: "a cast swap must shift the start point by the bbox delta."** This
was listed here as a gap, implemented, and it corrupted every animation in the
game. The claim was that Director captures the bounding box before a member
change and shifts the start point by the difference so a new registration offset
does not move the sprite. No such rule appears anywhere in `DIRECTOR_ENGINE.md`'s
placement chapter, which is the deeper reading — the sprite's own start point is
authoritative on every frame, and for a non-puppet channel the score's start
point is copied in wholesale.

The reason it is destructive rather than merely useless: the score changes
members on a channel constantly, because that is how a walk cycle is authored,
and it supplies its own `loc` for each of those members. The correction was being
added to a position that was already right, and accumulating.
`tools/nudge_drift.gd` replays the real score and measures it — 451px of drift on
one DAY1 channel, 9 of 17 channels displaced; 12 of 13 on EXODUS. Kept runnable
as the evidence.

**Done: a genuine member change resets a film loop's frame counter to 1.** The
counter is channel state, not member state, so two sprites showing the same loop
animate independently. `scenes/director_preview.gd` `_note_member`.

**Done: one placement rule, not two.** The renderer scaled the registration
offset by the drawn size and the hit test took it raw, so a resized sprite was
clickable somewhere it was not drawn. `_stage_rect` is now the single rule, used
by the renderer, the hit test, `rollOver` and the debug boxes.

**Done: a sprite is drawn at its own size, not its member's.** The preview
honoured the score's rect only when the stretch flag was set, treating it as
authoring residue otherwise. That rule is right for a film loop's *children* —
`tools/film_loop_stretch.gd` separates those two populations cleanly on the flag
— and wrong for the main score, where §1.2 says the sprite's own width and height
always win and the member's size enters only as the denominator when scaling the
registration offset.

`tools/drawn_size.gd` settles it against the export. The new rule reproduces the
export's top-left for 95% of EXODUS's sprites, 98% of STRTGAME's and 99.8% of
DAY1's; the old rule scored 2,762 of 3,172 on EXODUS — which is *exactly* the
number of sprites whose score rect already equalled their member's size. It only
ever landed where the question did not arise. Worst single miss 136px on
STRTGAME, 55px on DAY1.

The two rules now live at their own call sites rather than as a branch in the
shared path: `_drawn_size` is the main score's, `_child_sprite` is the film
loop's. The texture cache key gained the drawn size with it, since one member
legitimately appears at several sizes in a movie.

**`setCast` overwrites width and height from the member only when `stretch` is
clear.** Still open, and smaller than it looked: `stretch` does not mean "is
resized", it means "the author resized this deliberately", and all it governs is
whether a cast swap may reset the size back to the member's natural one. The
preview has no reset-on-swap path at all — it takes width and height from the
score record every frame — so there is nothing yet for the flag to protect.
`director/sprite_channel.gd:110-126` already implements the real rule correctly.

**Flip is in the data and is not decoded.** Horizontal and vertical flip live in
the sprite record's thickness byte (`0x20`, `0x40`), along with the has-blend
flag (`0x10`) and the thickness itself. `director/director_score.gd` `_snapshot`
reads bytes 1, 2, 3, 12, 14, 16, 18 and never touches byte 4, so all of it is
dropped. ScummVM parses the byte and never applies the flip anywhere in its
render path, so it is not a specification for how flip interacts with
registration or hit testing — the reasoned reading is that flip mirrors the image
within the sprite's rect, leaving the rect, the position and the hit rectangle
unchanged. Worth checking early: if the original mirrors walk-cycle art rather
than shipping left and right versions, ignoring this makes characters face the
wrong way.

**Colourisation is decoded and dropped.** `director_score.gd:248-249` reads
`fore_color` and `back_color` and nothing consumes them. When they differ from
black and white, Director repaints the image's black pixels `foreColor` and its
white pixels `backColor` — which is how one 1-bit member appears in a dozen
colours without a dozen bitmaps existing. A movie that recolours 1-bit art
currently renders monochrome, which is wrong without looking broken. Both colours
have to join the texture cache key.

**Rotation and skew do not exist in D4.** Stated so it stops being a suspect:
they are D7-only sprite fields. Anything that looks rotated in this game is
pre-rendered art or a film loop.

## Mouse

**`moveableSprite` drag.** Eligibility is implemented — a moveable sprite is
clickable with no script — but the drag itself is not: mouse-down should record
the dragged channel and the offset from the click to the sprite's position, and
every mouse-move should set the position to offset plus mouse. The drag ends on
mouse-up or when the sprite stops being moveable. Nothing in this game is known
to need it yet; anything with a slider or a draggable inventory will.

**`the constraint of sprite`.** A dragged position is clamped into the constraint
channel's bounding box before being stored. It clamps the position *point*, not
the sprite rect, so a sprite can legitimately hang outside the constraint box by
its registration offset.

**A hole aborts the hit descent.** Only text cast members return one, and only
over a scrollbar arrow. Irrelevant until text members render.

## Keyboard and text

**Editable text.** Effective editability is the sprite's flag OR the cast
member's — either alone is enough. The first editable sprite becomes the focused
widget, and `keyDown`/`keyUp` are routed to the sprite owning that focus rather
than to the sprite under the mouse. None of this exists here, and no keyboard
handling exists at all.

## Cursor

**Wait-for-click forces its own cursor.** While the score waits for a click,
Director overrides everything with an alternating up/down pair, toggling once a
second, and skips channel and global resolution entirely.

**Windows before D5 ignores custom hotspots** and always uses (8,8). If this
build should behave as the Windows original did, that is correct for every cursor
in the game — worth testing, because it would explain any systematic sense of the
cursor pointing slightly off.

## Lingo

**`and` and `or` do not short-circuit in Director.** Single opcodes, both
operands always evaluated. `lingo/lingo_interpreter.gd` short-circuits, which is
a live divergence rather than a missing feature: a right-hand side with a side
effect runs there and not here.

**Two answers to one question.** `lingo/lingo_builtins.gd` and the interpreter's
own inline `match` disagree on `getAt`, `abs` and `value` — `getAt` past the end
answers 0 inline and VOID in the module. The inline ones are matched first, so
the module never sees them.

**Three designator gaps**, all the shape the `sound N` fix already solved — a
designator suffix parsed as an ignorable modifier and dropped: `go to frame E of
movie F` loses the movie (6 scripts), `field (E) of castLib N` loses the library
(4), `the <prop> of window "x"` cannot be assigned (2). And `when <event> then`
(1 script) misparses into two junk statements.

## Not investigated

The subsystem sweep is still running. Transitions, palette effects, trails,
blends, sound cue points, video, text and shape rendering, windows and
Movie-In-A-Window, timers and idle handling, and double-click semantics have not
been assessed at all. Absence from this file means unexamined, not absent from
Director.
