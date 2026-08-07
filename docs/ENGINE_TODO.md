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

**`play` does not suspend the handler that called it — the widest divergence in
this engine, and it is measured.** §8.2. `Lingo::func_play` sets `_freezePlay`
after branching, and `Window::freezeLingoPlayState` stashes the *running* handler
in a buffer of its own, separate from the ordinary frozen states. The rest of
that handler does not run. It is requeued as the first frozen state when `play
done` executes or the playhead reaches the end of the movie, and only then do its
remaining statements run. ScummVM's own comment above `freezeLingoPlayState` says
exactly this.

This port runs the handler straight through, so the statement after `play frame`
executes immediately — and when that statement is a `go`, it overwrites the
branch `play` just set. The played segment never runs and the play stack is left
holding an entry nobody will pop.

Measured, in the title that reports the symptom. `BATZEGOZ.dir`'s dialogue
options are `BehaviorScript 39`-`40` and eleven near-copies:

    on mouseUp
      sound playFile 1, soundspath & "egoz1.aif"
      play frame "egozspeak1"      -- Director suspends the handler HERE
      go("batz2a")                 -- ...and runs this at `play done`

`egozspeak1` is the talking animation, and its own `on exitFrame` is `if not
soundBusy(1) then go(marker(1))` — it holds until the line has finished. Reproduce:

    godot --headless --script tools/click_trace.gd -- \
        --root rating --file BATZEGOZ.dir --marker Egoz1 --channel 11

    f196 play ch1 egoz1.aif      the mouseUp starts the line
    f216 play ch1 batz3.aif      Batz2A is entered next tick and replaces it
    play stack : 1 entry(s)      the `play` branch that was thrown away

The playhead goes `Egoz1+2` → `Batz2A` in one step, skipping frame 206
(`egozspeak1`) entirely, and the next room's own line takes channel 1 about one
frame later. That is the reported "the character starts speaking and then stops
after something very very quick", and it is not a mouse fault: the click routes
correctly and the right handler runs.

**922 of Rating's 1,075 `play frame` sites carry Lingo after them** — 516 of
those a `go`, 272 a `sound` — across EGOZEND, EGOZROO1/2, EGOZROOM, PHONE,
MOVIEND, Panel, BLABOMB, NIGHT1 and 20 more. Piposh 2 has 121 of 160, 10 of them
a `go`. The 153 sites where `play frame` is the last statement in its block are
the ones that behave identically either way, and they are why some dialogs look
fine.

*What has to change with it.* This is **not** a `play` fix. Director suspends
*any* handler at a `go` too — `Lingo::func_goto` sets `_freezeState` — and
resumes it after the next frame is entered; `play` differs only in using a
separate buffer with a different resume trigger. So the two are one mechanism and
have to land together, or `play` grows a bespoke path that `go` contradicts.
Doing only the first half — abandoning the handler at `play` — is worse than the
current behaviour: the trailing `go` never runs at all, `play done` returns to
the dialog frame, and the conversation loops. What it needs is the interpreter
able to suspend a handler mid-block and resume it, which
`lingo/lingo_interpreter.gd:_exec_block` cannot currently do, plus a resume point
in `director_preview.gd:lingo_play_done` and one at frame entry. Nothing in
`preview/interaction.gd` is involved.

**Tempo: the pre-D6 numbering is implemented but unexercised.** §9.1.
`director/director_frame_clock.gd:rate_from_tempo` reads the tempo cell under
both conventions and chooses by the movie's file version -- but
`director_score.gd` decodes the D6/D7 main-channel layout only, so a D4 or D5
score does not parse and the older branch has no input. The collision is the
reason it has to branch on version and not on value: 246/247/248 mean "set rate
/ delay / wait-click" from D6 and "delay ten / nine / eight seconds" before it.
`FrameClock.movie_file_version` is consequently never set to anything but its
D6 default.

**Tempo: the one-shot meanings are decoded without a version.** §9.1.
`director_score.gd` applies the D6 numbering unconditionally, so a D6 movie's
cells 134 and 135 -- digital-video waits in the reference -- are read as
sound-channel waits, and a pre-D6 movie's delay band (`256 - cell` seconds, taken
from the cell itself with no operand) and its click wait at 128 are not read at
all. No container in either corpus writes any of them.

**Tempo: the video waits.** §9.1. Neither pre-D6's `136 ... 135 + channelCount`
nor D6's "any other value is a video wait" is implemented, and there is no
digital video to wait on.

**`puppetTempo` is bound inert.** §9.1 gives it precedence over the score's
tempo until the score writes one or the effective tempo changes.
`scenes/preview_lingo_host.gd` lists `puppettempo` among the no-ops, so a script
that sets it changes nothing and `FrameClock` has no puppet rate to hold.

**`play` and `go` suspend a handler, with three residues.** §6.1/§9.4. Both now
capture the caller's position and resume it -- a `go` at the end of the step that
entered the destination, a `play` at `play done`. What is left: a `tell` body
cannot suspend; unwinding is statement-granular, so a suspend inside a compound
expression resumes at the statement rather than mid-expression; and reaching the
end of a score does not thaw a parked `play`.

**The event chain is resolved lazily, not queued.** §6.3/§8.2. Director decides
the whole chain before running any of it; this resolves each tier as it reaches
it. Two consequences: a `mouseDown` handler that swaps a member changes what the
*next* element of the same chain resolves to, where Director had already decided;
and `pass` / `dontPassEvent` are honoured only on the key chain -- the mouse
tiers still stop at the first handler that answers, so writing the flag from a
mouse handler is inert. The key half is done, including pass-by-default.

**Modifier keys are read live, not latched.** §8.3. `the shiftDown`,
`optionDown`, `commandDown` and `controlDown` ask the keyboard now rather than
reporting the modifier word that came with the keystroke, so a script asking
between events gets the wrong answer. `the timeoutKeyDown` is unbound.

**`LingoInterpreter.reset_steps()` has no callers.** `_steps` accumulates for the
life of a session against `MAX_STEPS`, so a long enough session eventually aborts
every handler with "step budget exhausted". Pre-existing; nothing has run long
enough to hit it.

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

**A right click latches nothing.** §15. The reference's mouse-down block runs at
the primary tier for `rightMouseDown` exactly as for `mouseDown`, and it latches
five things together: the empty-stage beep, the hilite channel, "the press was in
*a* button", the drag channel and grab offset for a moveable sprite, and the cast
id / script id / immediate flag the mouse-up resolves against. `the clickOn` is
written by `rightMouseDown` and `rightMouseUp` too. `Interaction.right_button`
does none of it and says so deliberately.

*What has to change with it.* All five, or none. Taking `the clickOn` alone gives
a right click the power to rename the sprite a left drag is in the middle of,
with no drag of its own to justify it — the same shape of half-a-rule that the
`the clickOn`-on-mouse-up entry above records. 0 `rightMouseDown` or
`rightMouseUp` handlers exist in either corpus, so this is unexercised as well as
unfixed, and it should be built as one block when it is built.

**The hit test has no Hole.** §4.2. `isMouseIn` returns three values and
`Interaction.channel_at` models two: a miss and an ineligible sprite both
continue the descent, and there is no result that *aborts* it. The only producer
of a Hole is a text member whose point is over its scrollbar arrows — a scrollbar
swallows the click without being a target. This port draws no scrollbars, so
nothing can produce one today; §4.2 still says to write the loop with three
results, because adding scrolling fields later silently changes click routing
everywhere rather than in the fields.

**Cast-script targeting on mouse-up.** §15. The member under the mouse at the
*start of the mouse-down chain* holds the `mouseUp`, so a `mouseDown` handler
that swaps the member still leaves the **old** member answering. The latching
half is done — `director_preview.gd:_click_script` holds the script the press
resolved, and `_press_channel` the channel — but it keys on the script, not on
the member, so a swap that changes which member a channel displays is not
modelled.

**`pass` / `dontPassEvent` propagation, and the tiers below the first.** §8.2.
The five tiers exist and run in order, but the chain is resolved lazily and stops
at the first handler that answers. Director queues the *whole* chain up front and
re-resolves each element's target at execution time, which is why a `go` inside a
`mouseUp` handler does not cancel the handlers below it — they are already queued
and run against a score the `go` has changed.

Two concrete costs, and neither is hypothetical:

- **A sprite behaviour and its member's cast script are alternatives here and
  cumulative in Director.** `interaction.gd:script_for_click` takes the sprite's
  behaviour *or*, only if there is none, the member's cast script — so a
  behaviour that exists but declares no `mouseUp` shadows a cast script that does.
- **`pass` is dropped.** It is bound inert in `preview_lingo_host.gd`'s `IGNORED`
  list, which was equivalent only while nothing ran after the first handler.
  6 sites in the Piposh 2 corpus, and the decompile hides them: ProjectorRays
  renders bare `pass` as `pass()` and `dontPassEvent` as `dont(pass)`, so a
  token search for either finds 0. The two real `pass` sites are
  `ISLAND2/External/BehaviorScript 325` — `on mouseUp / pass() / end`, a sprite
  whose entire purpose is to hand the click to the tier below, and which in this
  port is therefore a dead zone — and `SAVELOAD/Internal/BehaviorScript 20`, the
  save-slot selector, which does real work and then falls through. The four
  dont-pass sites (`FIGTBRJ 153`, `HEZSAVE MovieScript 209`, `AIR1 430`,
  `FIGTAIR 60`) are accidentally correct, because this port already stops.

*What has to change with it.* Queueing the chain means `pass`/`dontPassEvent`
must set a flag the dispatcher reads, and those two builtins live in
`preview_lingo_host.gd`; the queue itself replaces `Interaction.script_for_click`
and `Scripts.dispatch`; and the tier defaults must be primary=pass, everything
else=consume, which is the classic Director bug to get inverted. Landing the
queue without the flag makes every sprite behaviour leak its event to the frame
and movie scripts — the opposite failure, and a louder one.

**`the mouseDownScript` / `the mouseUpScript` hold a handler name, not source.**
§6.3 tier 1. Director's value is a *string of Lingo* compiled on assignment;
this port has no runtime compile-a-string path, so it stores a name — the same
shortcut `the keyDownScript` has always taken, and the reason it has held is that
every site in this corpus sets that one to a name (`fromnow`, `gomenu`). Nothing
sets either mouse property, so the divergence is unexercised as well as unfixed.

**Seven mouse properties read something other than what the reference reads.**
§4.5, §15. All seven are one-line changes in `scenes/preview_lingo_host.gd`'s
`get_system_prop`, all are independent of each other and of the hit test, and all
are measured at 0 corpus sites — so they are a batch to be done together and last,
not a risk to be weighed one at a time. `tools/mouse_events.gd` already walks the
property list and would gain a check per row.

| Property | Reference | This port |
| --- | --- | --- |
| `the doubleClick` | the last two press times within **25 ticks** (~417 ms), evaluated on read | a boolean latched at the press, 500 ms |
| `the mouseDown` / `the mouseUp` | **left or right** button | left only |
| `the stillDown` | the window manager's tracked down-state, which a `repeat while` inside a handler is written against | the same read as `the mouseDown` |
| `the lastEvent` | ticks since the last mouse move, click **or key** | the smaller of click and roll; keys are not stamped |
| `the lastKey` | ticks since the last key | unbound, reads VOID |
| `the mouseCast` / `the mouseMember` | `getSpriteIDFromPos` — the ink-aware hit test; `0` and VOID respectively for "over nothing"; `mouseMember` is a member *reference*, not a number | the rollover channel, `-1` for both, a number for both |
| `the mouseChar` / `mouseWord` / `mouseLine` / `mouseItem` (D3) | the character, word, line or item of the text member under the pointer | unbound, read VOID |

Two engine behaviours in the same class, neither of them a property: **`the
beepOn`** makes a mouse-down on empty stage beep, and is not implemented; and
§15's **button hilite flip** — on mouse-up, if the last mouse-*down* was inside
*any* button, the button under the mouse-up inverts its hilite — is not either.
`preview/hilite.gd` implements the press-and-hold inversion and not this.

**Eligibility is the D4/D5 rule and every movie in both titles is D7.** §4.3.
`respondsToMouse` tests its clauses in order and the **D6+ clause comes before
the handler search**: from D6 on, a sprite with any behaviour attached is a click
target whatever that behaviour declares. `Interaction.responds_to_mouse`
implements moveable, button, and a search for `mouseDown`/`mouseUp` in the
behaviour and in the member's cast script, so on this corpus it is *narrower*
than the reference by exactly "every sprite whose behaviour declares no mouse
handler". Two further clauses are missing as well: a **movie** cast member with
scripts enabled, and the D3-style **generic** (scopeless) score script.

Visible in Rating, and it is the dialogue itself:

    godot --headless --script tools/hotspots.gd -- \
        --root rating --file BATZEGOZ.dir --marker Egoz1

    11  1:20  (194,388) 250x28   no   behaviour declares no mouse handler
    12  1:21  (235,423) 211x30   no   behaviour declares no mouse handler
    13  1:22  (221,463) 225x12   no   behaviour declares no mouse handler
    2 of 16 sprites can answer a click

Those three are the three dialogue options. In D7 all three answer the mouse;
here none of them does, and the click reaches them only because
`script_for_click` falls back to the frame script. The version is settled
evidence, not a guess — `openspec/changes/director-playback-machine/
director-version.md` measures config version `0x57E` on every movie played.

*What has to change with it.* **This is a hit-test change and is the highest-risk
item in this file.** Widening eligibility makes previously transparent sprites
absorb clicks, and §4.2 is explicit that an ineligible sprite does not block what
is under it — so a room backdrop that happens to carry an `exitFrame` behaviour
would start eating every click on the stage. Three things move together: the
eligibility predicate, a **corpus measurement taken before and after** with
`tools/hotspots.gd` over every frame of both titles compared row by row (not by
total — see `porting-fidelity-verification`), and the D6+ multi-behaviour entry
below, because "has behaviours" and "has *a* behaviour" are the same question
asked of two different data structures.

**D6+ sprites carry a list of behaviours; this port resolves one.** §8.2. From D6
a channel holds `_scriptInstanceList`, and `queueEvent` pushes one sprite-tier
element **per behaviour**, passing through for all but the last so every one gets
a chance at the event. `Scripts.for_sprite` answers a single script per channel,
chosen by the narrowest covering interval. A sprite carrying a rollover behaviour
and a click behaviour therefore loses one of them, which is the likeliest reason
Rating's option sprites above report a behaviour that declares no mouse handler.
Pairs with the eligibility entry: the D6+ arm of `respondsToMouse` is a test on
this same list, so implementing either alone leaves the two disagreeing about
what a sprite's behaviours are.

**`mouseEnter` / `mouseLeave` / `mouseWithin` are driven off the wrong channel
and stop one tier too early.** §4.5, §8.2. The reference raises all three from
`getMouseSpriteIDFromPos` — the *eligibility-filtered*, ink-aware hit test, which
is this port's `_hover_channel` — and this port raises them from
`_rollover_channel`, the pure rect test. It also confines them to sprite
behaviours; the reference lets them fall through to the cast script, the frame
script and the movie scripts, in every version. Only `mouseUpOutSide`,
`beginSprite`, `endSprite` and `prepareFrame` stop at the sprite tier, and only
from D6. Two smaller clauses are absent as well: in D5 these three fire **only
while a mouse button is held**, and `mouseEnter`/`mouseLeave` are additionally
raised around a D5 press and release.

*What has to change with it.* Switching to `_hover_channel` needs it recomputed
**per tick** as well as per motion — `track_rollover` already is, `_hover_channel`
is only updated from `mouse_motion`, so a sprite moving under a stationary cursor
or a touchscreen tap would stop generating crossings. And it costs something: an
eligibility-filtered channel means a sprite whose behaviour declares *only*
`mouseEnter` never receives it, because `responds_to_mouse` does not look for
that handler. That is authentic — the reference has the same trap — but it is a
regression in the direction of doing less, so it should land together with the
D6+ eligibility clause above, which is what makes such a sprite eligible again.
Propagating past the sprite tier is separate again and needs the queued chain.
**0 sites in either corpus declare any of the three**, so nothing here is
verifiable against this data; `rollOver(n)` polled from `exitFrame` is the only
hover mechanism either title uses (94 sites, 28 files, 14 titles).

**The three rollover queries are two.** §4.5. `rollOver(n)` and `rollOver()` are
both answered by `Interaction.rollover_channel`, which is right for the builtin
in both forms; `the rollOver` as a **property** is a different query in Director —
the ink-aware hit test with no eligibility filter — and is unbound here, so it
reads VOID. 0 sites, in a corpus that writes every one of its 94 rollovers as the
function. Two further clauses: `rollOver(n)` is measured against the **score's**
geometry rather than the live channel's, deliberately (a menu that swaps art
because the rollover is true feeds its own answer back into the question), so a
sprite a script has *moved* rolls over at its old rectangle; and the D4-and-below
`getRollOverBbox` cache — a blanked channel keeps rolling over its last non-empty
box — is absent, which no D5+ title can reach and a D4 one would.

*What has to change with it.* Binding `the rollOver` means binding it to
`_hover_channel`-without-the-filter, which is a **third** channel this port does
not maintain; and moving `rollOver(n)` to live geometry means moving
`rollover_channel` with it, or `rollOver()` and `rollOver(n)` answer about
different rectangles — which the module's own comment argues is worse than either
being wrong on its own.

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
