# Known engine gaps, not yet implemented

Behaviour the reference describes and this port does not have. Every entry was
verified against ScummVM's Director engine and, where noted, against this repo's
own working renderer; the full descriptions are in
[`DIRECTOR_ENGINE.md`](DIRECTOR_ENGINE.md) and [`LINGO_SURFACE.md`](LINGO_SURFACE.md).

This is a work queue, not a bug list — nothing here is a mystery. Each item says
what Director does, what happens without it, and where the change goes. Ordered
by how visible the absence is.

## Placement

**A film loop's cast swap must not move the sprite.** When the member on a
channel changes, Director captures the bounding box before the swap and shifts
the sprite's start point by the difference, so a new registration offset does not
jump the sprite. Without it, a channel that swaps between loops of different
sizes moves every time it swaps — which reads as a character teleporting rather
than as a placement bug. `scenes/director_preview.gd`, wherever the member
override is applied.

**A genuine member change resets a film loop's frame counter to 1.** Ours keeps
counting from the movie clock, so a loop entered a second time starts wherever
the first one left off. `director/director_film_loop.gd`.

**`setCast` overwrites width and height from the member only when `stretch` is
clear.** In puppet mode a script may set the dimensions first and then the cast
number and expect its dimensions to survive. Ours always takes the member's
size. `scenes/director_preview.gd`.

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
