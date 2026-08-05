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

## 9. `init all`'s puppeting is lost on every movie change

**Status:** open · **Area:** score runner / Movie-In-A-Window

DAY1's `init all` runs `puppetSprite` on channels 30, 100 and 103-110, once, on frame
1. `_mark_movie_loaded()` clears the channels on every movie load, so one round trip
through the joke window drops all of it:

    after init all:            puppeted=[30, 100, 103, 104, 105, 106, 107, 108, 109, 110]
    after a JOKE round trip:   puppeted=[]

Clearing is right — channel N in the next movie is unrelated artwork — but Director
never unloads the parent movie for a Movie In A Window in the first place, so the
question does not arise there. The port returns mid-room without re-running `init all`,
so the score reclaims channels Lingo is supposed to own. Nothing depends on it today:
the puppet draw asks `score_uses_channel()` instead, and the inventory slots are drawn
from their own override. It will matter the moment a script drives one of those
channels after a round trip.

**Reproduce:** enter DAY1 at frame 1, tick, read `channels[103].puppet`; open and
forget the joke window; read it again.

---

## 10. Convergence is measured on 5 of 61 movies

**Status:** open · **Area:** verification

`lingo_converge.gd` and `lingo_frames.gd` cover DAY1, NIGHT1, HOTEL1, SEA1 and
AIR1. Nothing measures the other 56, including every minigame and meeting movie.
An engine change can only be checked against the five.

---

## 11. The upstream exporter decodes every 1-bit member as 8-bit

**Status:** open upstream, worked around here · **Area:** assets / export

Director's CASt chunk holds a `u16` pitch whose `0x8000` bit is the depth flag and
whose low 15 bits are the row stride, then a **signed** rect. The exporter records
that high byte as `bpp_marker`, ignores it, reads every member as 8 bits per pixel
and infers geometry from the decoded byte count. Correct for 8-bit members, wrong
for every 1-bit one: `wlkcur1` came out 5x6 pixels of colour noise instead of
13x17.

That exporter is not in any repo on this machine. `assets/SOURCE.txt` records the
assets as a robocopy from `E:\games\piposh2\reports\render_model\` on a Windows
box; `Piposh2-Port` is a separate migration effort whose `spike/bitd-export`
self-describes as disposable and emits a different format, and
`~/Projects/_private_projects/piposh2/` has no exporter either.

`tools/repair_1bit_members.py` re-decodes the affected members in place from the
raw chunks and `tools/verify_1bit_members.py` is the pass/fail check. **A future
re-export from the Windows toolchain will silently undo the repair** unless the
decoder is fixed there first, or the repair is re-run after syncing.

Reproduce:

```
python3 tools/verify_1bit_members.py     # PASS once repaired
python3 -c "import struct;b=open('/Users/yonatankarp-rudin/Projects/_private_projects/Piposh2-Port/originals/recovery/web-alpha/decompiled_chunks/DAY1/DAY1/chunks/CASt-51.bin','rb').read();t,c,s=struct.unpack_from('>III',b,0);p,=struct.unpack_from('>H',b,12+c);print('pitch',hex(p),'rect',struct.unpack_from('>hhhh',b,14+c))"
```

**134 members repaired, every one from its own chunks.** `tools/dump_movie_chunks.py`
reads the `.DXR`/`.CXT` containers directly, so the coverage gap that once forced
NIGHT1 to borrow its cursors by name is closed, and ENDMOVI4's `handcur1` and
`handcur2` — which appear in no other movie and so had no donor — are repaired too.
Nothing is borrowed any more.

Only `HEZSAVE` still has no chunks, and the port intercepts it for JSON saves
rather than running it.

Note that an unrepaired cursor does *not* degrade to the arrow. The size guard in
`cursor_image` catches only a wildly wrong decode; NIGHT1's members came out 5x6 to
24x26, all small enough to compose into a plausible-looking block of noise and
install as the cursor. Anything that regresses the decode will look like static,
not like a missing cursor.

---

## 12. One DAY1 film loop still does not parse

**Status:** almost closed · **Area:** assets / renderer

A movie's internal cast is now registered under the movie's name, so film loops
living there resolve. Before that, `get_film_loop` refused `cast_lib 1` outright
and `generate_cast_registry.py` collected only linked casts, so MURDER1's `tofi
right`, `goldolin left` and `tofi walking back` — members 5, 10 and 13 of its own
cast, used by the score on channels 9, 3 and 17 — could never be found, and the
characters never animated.

Corpus-wide there were 17,506 sprites across 49 of the 88 movies pointing at an
internal member with no bitmap, which is what a film loop looks like from
`members.json`. 21 internal casts now carry their loops.

The coverage half is closed. `tools/dump_movie_chunks.py` reads the containers
directly, so 84 of the 88 movies now have chunks and the registry carries 497 film
loops across 60 internal casts. **17,426 of those 17,506 sprites now resolve**, up
from none.

What is left is one member: DAY1's 309, `loshuaa`, on channel 19 for 80 sprites.
Its `SCVW-1800` trips "channel data exceeds D7 limit" in
`tools/director_film_loops.py`, so the loop is skipped rather than mis-parsed. The
D7 constants in that file (`MAIN_CHANNEL_SIZE = 288`, `SPRITE_CHANNEL_SIZE = 48`,
`MAX_D7_SPRITE_CHANNELS = 200`) are the thing to re-derive against this one chunk;
the recovery skill warns that score format is the part that moved most between
versions.

Reproduce: `goto_movie("MURDER1")` then `loader.get_film_loop(1, 5)` resolves to 7
frames at 168x279; `goto_movie("DAY1")` then `get_film_loop(1, 309)` returns `{}`.

---

## 13. `init all` never runs on movie entry

**Status:** open · **Area:** interpreter / score

Each hub's `init all` sits at the movie's frame 1 and the port jumps straight to a
room's `*go` frame, so it is never played. `DAY1/wonder/BehaviorScript 56` sets
`shelltoday`, `bath`, `dubi`, `mirror`, `inexits`, `wreck` and `firsttalk`, and
calls `cursorfunk()` and `peoplefunk()`. None of that happens; `GameState` supplies
its own new-game values instead, which is why the game plays at all.

`_run_cursor_funk()` calls the one handler cursors need, deliberately and no more:
running the rest here would reset that state over whatever a save had just
restored. Everything else `init all` does is still missing.

Reproduce: after `goto_movie("DAY1")`, every global above reads `<unset>` from
`runtime.lingo.interpreter.globals`.

---

---

## Closed

- **An uncovered shell or bottle vanished after one frame.**
  `_run_skipped_entry_scripts()` replayed the room's entry frames on every entry into
  a `*go` frame. The room loop is `go(marker(0))`, which throws the playhead from
  anywhere in the idle span back to the `*go` frame, so by frame number every
  iteration looked like an arrival; each replay re-ran `b4 bk's` and its
  `set the visible of sprite 15 to 0`. Arrival is now decided by the marker.
  Covered by `tools/collectables.gd`.
- **Every interpreted script died after a window, meeting or minigame.** `go_back`
  reloaded the movie but never called `lingo.prepare_movie()`, so the interpreter's
  current movie stayed on the one being left. `frame_script(1858)` then looked for
  member 83 in JOKE's casts, found nothing, and the room's entry scripts silently did
  not run — which left every collectable in the room on show, because the blanking in
  `b4 bk's` never executed, and left `whereami` stale so hotspots gated on it took
  their dead branches. This was `bugs.md` 10, and it was far wider than the bottle it
  was found through.
- **Piposh vanished for the length of every room transition.** The first version of
  the fix below tested whether the *current frame* has a channel 30. A transition span
  such as `edge3up` carries none for twelve frames while he walks through it. The test
  is now per movie, via `RenderModelLoader.score_uses_channel()`, which also does not
  depend on the puppet flag — `init all` sets that once and `channels.clear()` drops it
  on the next movie change.
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
