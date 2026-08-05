# Known bugs and open engine gaps

One entry per issue, worst first. Each carries the evidence it was found with, so
the next session can confirm it still reproduces before working on it rather than
trusting this file.

Numbers here were measured on the commit that added the entry. Re-run the tool
named in the entry before acting on a figure. Agreement with the lifted export
falls as the port gets more faithful, so a moved number is not automatically a
regression: see `.claude/skills/porting-fidelity-verification/SKILL.md`.

---

## 1. Interpreted sprite property writes never reach the renderer

**Status:** CLOSED — `SpriteChannel`, see the Closed section · **Area:** renderer / interpreter host

`LingoHost.set_sprite_prop()` writes every `set the <prop> of sprite N` into its
`puppet` override dictionary, and nothing outside `lingo_host.gd` ever reads that
dictionary. `MoviePlayer.draw_current_frame()` takes member, position and size
straight from the score frame. Only `visible` reaches the stage, because it is
forwarded separately to `DirectorRuntime.set_channel_visible()`.

Corpus counts of sprite property writes in the compiled scripts:

| property | writes | reaches the stage |
|---|---|---|
| `memberNum` | 624 | no |
| `visible` | 406 | yes |
| `locV` | 397 | no |
| `locH` | 347 | no |
| `cursor` | 155 | no |
| `moveableSprite` | 15 | no |
| `constraint` | 10 | no |

That is 1548 of 1954 writes with no effect on what is drawn. Any original
animation driven by Lingo rather than by the score is therefore dead: ARCADE2
puppets sprites 7 and 40 and moves them, MIROLO drives a row of channels,
FIGTBRJ sets `the memberNum of sprite 30`. The `puppetSprite N, 1` calls are
already tracked in `LingoHost.puppeted` (288 call sites), so the state needed to
know which channel Lingo owns is present and unused.

The fix is one effective-sprite resolution the renderer reads through: score
frame first, puppet overrides on top, visibility last. It replaces the current
special cases for channel 30 and the inventory slots rather than adding to them.

**Reproduce:** `grep -rn "set_sprite_prop" lingo/lingo_host.gd`, then confirm no
consumer: `grep -rn "host.puppet" director/ ui/` returns nothing.

---

## 2. `whatodoeveryframe` is reimplemented natively, not run

**Status:** open · **Area:** puppet

`PuppetController` is a hand-written version of the original's walk state machine.
It reads the original's globals (`ifmovie`, `nextroomdata`, `egozh`, `egozv`,
`whatodo`, `syz`) but decides everything itself, so each of the original's lines
that the port needs has to be copied across by hand. The room-transition hide
(`sprite(30).visible = 0`) is the most recent example, and every one of these is a
place the copy can drift from the script.

Blocked on 1: `whatodoeveryframe` drives Piposh entirely through
`the memberNum of sprite 30` and `the locH/locV of sprite 30`, which is exactly
what the renderer ignores today. Fix 1 and this script becomes runnable.

---

## 3. `_lingo_hidden` is never cleared on a movie change

**Status:** CLOSED — channels are cleared on movie load, see the Closed section · **Area:** score runner

`DirectorRuntime._mark_movie_loaded()` clears the timing accumulator, the pending
transition and the film-loop cursors. It does not clear `_lingo_hidden`, and
`enter_frame()` only replaces `_hidden_channels`. A `sprite(N).visible = 0` in one
movie therefore keeps channel N hidden in the next movie, where that channel is
unrelated artwork.

Not simply "clear it on load": DAY1's `init all` hides sprites 6, 15 and 33 once,
on its init frame, and a return into DAY1 from SEA1 lands at `shore2downdeck`
rather than that frame. Clearing without replaying those hides would show three
sprites that should be hidden. Needs a decision about what a movie load resets,
which is the same question 1 answers for the override table.

Channel 30 is not affected: it routes to `PuppetController.visible` instead.

---

## 4. Two exits stop working when clicks are interpreted

**Status:** open · **Area:** interpreter / walk

`DAY1 @edge2go ch10` and `NIGHT1 @edge2go ch10` walk to `edge1go` with
`use_lingo_clicks` off and do not walk at all with it on. Present before the
current session's changes; confirmed by running the harness against a clean
checkout.

**Reproduce:** `godot --headless --script tools/lingo_walk_diff.gd`, rows tagged
`[no-walk]`.

---

## 5. Nineteen walks reach a different room than the export

**Status:** open · **Area:** interpreter / walk · **Related:** 9

Most are HOTEL1, where the export is the weaker of the two references:
`movie_context.json` has 23 unmapped transitions there and no verified ones, and
its destinations repeat per channel across unrelated rooms. Some of the 19 are
likely the interpreter being right and the export wrong. Each row needs reading
against the original handler before it is called a bug.

**Reproduce:** `tools/lingo_walk_diff.gd`, rows tagged `[wrong-room]`.

---

## 6. SEA1 and AIR1 stall under interpreted frames

**Status:** open · **Area:** interpreter / frames

With `use_lingo_frames` off, SEA1 visits 24 distinct frames over 220 ticks and
AIR1 visits 34. With it on, SEA1 sits on frame 3 for the whole run and AIR1 stays
between 3 and 29. Agreement with the score runner is 0/220 ticks for both, against
220/220 for DAY1, NIGHT1 and HOTEL1.

**Reproduce:** `godot --headless --script tools/lingo_frames.gd`.

---

## 7. Two clicks produce no navigation or sound under the interpreter

**Status:** open · **Area:** interpreter / clicks

`SEA1 ch9 frame 1234` and `AIR1 ch8 frame 707`: the export carries a destination
and a sound list, the interpreted handler produces neither. These are the only two
outright disagreements in the convergence run, so they are small and specific
enough to read end to end.

**Reproduce:** `godot --headless --script tools/lingo_converge.gd`, lines tagged
`differ`.

---

## 8. Both `movie_context.json` and `walk_doorways.json` paths are still live

**Status:** open · **Area:** scaffolding retirement · **Related:** 5

The transition destinations now have a Lingo answer: `BehaviorScript 207` reads
`item 1 of nextroomdata`, and the native redirect only runs when that script does
not. The rest of the tables have no Lingo answer yet: hub membership, meeting
triggers, phase transitions, day advance, per-hotspot walk doorways. Every one is
a guess that will eventually contradict the scripts, and the HOTEL1 and NIGHT1
rows are marked inferred rather than verified in the data file itself.

Retire in the order they become redundant, and delete rather than leave both
paths live.

---

## 9. Convergence is measured on 5 of 61 movies

**Status:** open · **Area:** verification

`lingo_converge.gd` and `lingo_frames.gd` cover DAY1, NIGHT1, HOTEL1, SEA1 and
AIR1. Nothing measures the other 56, including every minigame and meeting movie.
An engine change can only be checked against the five.

---

## 10. A taken bottle is back on the shelf after the joke closes

**Status:** open · **Area:** Movie-In-A-Window / score runner

`CastScript 69` hides the bottle with `sprite(the clickOn).visible = 0` and then
opens `joke.dxr`. Director floats that over a DAY1 that never unloads, so the hide
survives. The port has one stage: it pushes DAY1 on the route stack, loads JOKE, and
`_mark_movie_loaded()` clears the channels — the hide with them.

Coming back should not matter, because `go_back` re-enters `swinggo` and the entry
replay runs `b4 bk's`, which blanks channels 15, 17 and 33. Measured, it runs and the
blank does not stick:

    entry:        frame 1860 label=swinggo  hidden15=true   ch15.visible=false
    after forget: frame 1860 label=swinggo  hidden15=false  ch15.visible=true

Same frame, same replay, opposite outcome, so something after the replay puts it
back on the return path only. Not chased further; the reveal work it turned up in
was a different defect.

In practice the bottle cannot be taken twice — `jokefield` has the room, so
`searchfunk` answers "wasalready" and will not re-reveal it — but it is on screen
when it should not be.

**Reproduce:** `godot --headless --script tools/collectables.gd` covers everything
up to the return; the assertion for this was removed rather than left failing.

---

## Closed

- **An uncovered shell or bottle vanished after one frame.**
  `_run_skipped_entry_scripts()` replayed the room's entry frames on every entry into
  a `*go` frame. The room loop is `go(marker(0))`, which throws the playhead from
  anywhere in the idle span back to the `*go` frame, so by frame number every
  iteration looked like an arrival; each replay re-ran `b4 bk's` and its
  `set the visible of sprite 15 to 0`. Arrival is now decided by the marker.
  Covered by `tools/collectables.gd`.
- **A second joke was drawn on the page.** The puppet was drawn over every movie, at
  `cast_lib 1` plus whatever member `PuppetController` held, resolved against the new
  movie's own internal cast. JOKE's member 29 is the joke bitmap `joke33`, and Piposh's
  syz-9 stand member is 29, so on the beach his sprite came out as a second joke at his
  stage position. Other sizes and the walk frames land on members 31-54, which in JOKE
  are more jokes, so it changed from room to room. Piposh is channel 30 of his own
  movie; a Movie In A Window has its own channels and JOKE never mentions 30, so there
  is nothing to draw there.
- **The joke picture was never drawn.** JOKE parks channel 3 on `jokepfff`, a 1x1
  placeholder at (318, 199); the Lingo swaps in a 214x120 joke with its own
  registration point. With member writes reaching the channel it now lands at
  (133, 67) at full size. This is what made the joke text look off-centre and
  partly cut off.
- **Interpreted sprite property writes never reached the renderer** (was 1).
  `SpriteChannel` is Director's live channel array; drawing and hit-testing read it.
- **`_lingo_hidden` leaked across movies** (was 3). Channels belong to the movie and
  are cleared on load, which drops the previous movie's puppet ownership, its hides
  and its film-loop cursors together.
- **Shells and bottles recorded against the wrong room.** `the castNum` dropped the
  cast library, so `member(...)` resolved in the movie's own cast: DAY1's sprite 1 is
  `island:10` (`shore2`) while DAY1's own member 10 is the cursor `wlkcur1`. 25 of 32
  rooms answered with a cursor name and 7 with the empty string, and `nof` is the key
  `shellfield` and `jokefield` are written under, so one shell taken in any of those
  7 marked all of them collected. Covered by `tools/room_names.gd`.

- **Piposh drawn twice across a room transition.** The canned transition animation
  draws him in a low channel while the puppet drew unconditionally. `the visible of
  sprite 30` is now a real property (`PuppetController.visible`), hidden on the
  original's own `ifmovie` condition and restored by `BehaviorScript 207`.
  Covered by `tools/puppet_visibility.gd`.
- **`LingoHost.navigated` was never raised**, so every interpreted `go` was
  overridden by the exported fallthrough one step later.
- **`_try_transition_redirect` ran before `exitFrame` dispatch**, answering from
  `movie_context.json` a question `BehaviorScript 207` answers from the script's
  own globals. It is now the fallback.
- **Not a bug: the "undispatched event classes".** `docs/ENGINE.md` listed
  `keyDown`, `startMovie`, `stopMovie` and `idle` as never dispatched. The corpus
  contains no `stopMovie`, `idle`, `mouseEnter` or `mouseLeave` handler at all; its
  only handler classes are `exitFrame` (2504), `mouseUp` (721), `mouseDown` (40)
  and `enterFrame` (33), and all four are dispatched. `keyDown` works through
  `the keyDownScript`, which `LingoHost` honours and `DirectorRuntime` routes
  keypresses into. Nothing to do; the doc line was stale.
