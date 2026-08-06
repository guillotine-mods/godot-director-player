# Known bugs and open engine gaps

One entry per issue, worst first. Each carries the evidence it was found with, so
the next session can confirm it still reproduces before working on it rather than
trusting this file.

Numbers here were measured on the commit that added the entry. Re-run the tool
named in the entry before acting on a figure. Agreement with the lifted export
falls as the port gets more faithful, so a moved number is not automatically a
regression: see `.claude/skills/porting-fidelity-verification/SKILL.md`.

---

## 22. Finishing the cliff meeting restarted the day, because `go(<marker>, <movie>)` dropped its marker

**Status:** FIXED · **Area:** interpreter host, `_go` · **general, not one movie** ·
the dialogue prompt was never the bug

Kept here rather than moved to Closed, and kept at this number: `AGENTS.md`,
`tools/lib/driver.gd`, `tools/probe.gd` and `tools/cliff_meeting.gd` all cite
"bugs.md 22" for the real-time lesson in 2 below, and the MURDER1 decompilation
gap at the end of the entry is still open.

Reported three times from play. The third report — "when the scene ends it
teleports you back to the beach entrance and you have to do the whole thing
again, in an endless loop" — was accurate, and the two earlier verdicts on this
entry were both wrong about *where* the loop was. It is not at the prompt. It is
at the handover, one frame past where the harness stopped looking.

**Root cause.** `MURDER1 BehaviorScript 45`'s `on exitFrame` marks the meeting
done and hands the player back to the room they left:

```lingo
put "done" into item 1 of meetings
newsyz = 9
nextroomdata = "clif2,91,336"
go("clif2", "day1.dir")
```

`_go` in `lingo/lingo_host.gd` read that first argument as a frame number:
`goto_movie("day1", LingoValue.to_int("clif2"))`, which is `goto_movie("day1", 0)`
— frame 1. DAY1 frame 1 carries `BehaviorScript 56 - init all`, whose `on
exitFrame` resets `meetings` to `"murder1,hatday1,…"` when `globalday = 1`,
empties `objectsfield` line by line, sets `nof = "shore2"` and ends on
`go("shore2")`. So finishing the meeting reset the day's progress, took the
player's inventory and put them at the beach entrance with the murder pending
again — and walking back to the cliff fires `peoplefunk` → MURDER1 once more, for
ever. Authentic behaviour for frame 1, which is where EXODUS starts a new day; the
bug is arriving there.

Measured with the same harness either side of the one-branch change:

| | before | after |
|---|---|---|
| lands at | `DAY1:0` — frame 1, no label | `DAY1:1913`, `clif2go` |
| 30 s later, untouched | `shore2go` | `clif2go` |
| `meetings` | reset to `murder1,…` | `done,…` |
| the item carried in | wiped | still there |
| walking back to `clif2` | MURDER1 again | stays in DAY1 |

**The fix is general, which is the point.** `go`'s first argument is a frame *or* a
marker, and the corpus splits cleanly. Sweeping every `go`/`play` call's argument
shapes in `data/lingo/*/*.json`:

| shape | count | means |
|---|---|---|
| `go(<marker>, "<movie>.dxr")` | **58** | put the player back at that room |
| `go(<frame>, "<movie>.dxr")` | 50 | start that movie from the top |
| `go(<marker>, <expr>)` | 10 | same, with `the moviePath &` prefixed |
| `go(<expr>, <expr>)` | 5 | both computed — `whatodoeveryframe`'s `go(item 2 of ifmovie, item 3 of ifmovie)`, the general walk-into-another-movie handover |

The 58 cover 34 distinct `(marker, movie)` pairs, every one of which resolves in
its destination's `labels`: `HATDAY1 → gate`, `ARCADE1 → arcade`,
`TENNIS → exitforest2b4`, `SLEEP1 → newmorning`. All of them, plus the 10 and the
marker cases among the 5, landed on frame 1 of the destination. Only MURDER1's has
been driven end to end, so the rest are a prediction no harness covers yet — the
`go(item 2 of ifmovie, item 3 of ifmovie)` one especially, since it is not one
scene but the general form. The 50 keep the path they had, EXODUS's
`go(1, "day1.dir")` among them, which is the legitimate day start.
`LingoValue.to_str(first).is_valid_int()` is the discriminator, and the sweep is
cheap to redo.

**Why a passing harness did not see it.** `tools/cliff_meeting.gd` ran with
`until_movie_change: true` and then asserted `movie == DAY1`. Which movie is
loaded is not where the player is standing — DAY1 frame 1 *is* DAY1 — and the
reset happened in the seconds after the assertion. It now asserts the landing
label, that the label still holds 30 s later with nothing clicked, that `meetings`
and the inventory survive, and that walking back into the room does not replay the
meeting. That last check is the loop's closing edge, and nothing had ever driven
it.

**This is entry 23 in reverse, and the pairing is the useful part.** Frame 846's
`frame_script` is that same `BehaviorScript 45`, and the exporter lifted its
destination correctly: `{kind: movie, value: "day1", label: "clif2"}`. So the
export held the right answer, the interpreter ran the script, navigated, and
`game_step`'s `lingo.host.navigated` check handed it the win. Neither source
is authoritative: 23 is the export overriding a script that decided not to move,
this is a script overriding an export that knew where to go. When the two disagree,
the disagreement itself is the bug report.

Reproduce: `godot --headless --script tools/cliff_meeting.gd` (~3 min; real time
is load-bearing, see 2 below).

**Regression check.** `tools/lingo_walk_diff.gd` is byte-identical either side —
`identical outcome: 85/117`, the same 32 differing rows in the same order — so the
change moves nothing in the walk cases. Read that as a regression check and not as
confirmation: the differ clicks a hotspot and runs 260 synthetic ticks, which never
reaches a cross-movie handover, so it cannot see the path that changed. The
pass/fail set also stays green: `smoke`, `puppet_visibility`, `room_names`,
`collectables` (22), `cursors` (44), `sprite_channels`, `sprite_stretch`,
`film_loop_stretch`.

### The prompt itself is authentic — this part of the entry stands

**MURDER1 stalls at frames 489-508, and that span is a dialogue prompt.** Frame
508's exported nav is `{kind: marker, rel: 0, offset: 0}` — Director's
`go to marker(0)` — which resolves to 489, so the last twenty frames cycle. There
is a second one at 676-695. Both are wait-for-click loops and both are authentic:
the score offers three subtitle lines on channels 41/42/43, each carrying its own
`mouseUp` handler (`CastScript 31/32/33` → `go("choose1a")`, `37/38/39` →
`go("choose2a")`), and the playhead waits until one is clicked. The player has to
pick a line. Nothing advances on its own, by design.

**Measured end to end.** Entering DAY1 at `clif2` with `murder1` pending fires
the meeting; clicking one line at each of the two prompts leaves MURDER1 after
146 s and marks the meeting done. So the scene does complete and the prompt is not
a stall: the earlier **PROGRESSION BLOCKER** verdict on the prompt was wrong. What
that measurement then read as "and returns to the cliff" was the *movie* name, not
the frame — see the root cause above.

**The port renders the prompt and the hotspots sit on it.** The three lines draw
in the subtitle panel, `clickable_sprites()` offers all three, and a screenshot
taken with `AppSettings.show_hotspot_hints` on puts the outlines tightly around
the drawn text. `perform_click` on a line reaches frame 549 (`choose1a`), and the
live path — `InputRouter` → `MoviePlayer._on_stage_click` → `runtime.perform_click`
— is the same call. There is no cursor change over the lines, but that is faithful
too: MURDER1's `MovieScript 47` is `on cursorfunk / end`, an empty stub.

**Four claims in earlier versions of this entry were wrong.** They are recorded
because each one cost a session, and the fourth is the expensive one: *"the scene
completes, therefore this is NOT A BUG."* The player's report was about what
happens after the scene completes, and the entry answered a question they had not
asked. "Not a bug" needs more evidence than a bug does, and the evidence offered
here stopped at the movie change.

1. *"The port is missing frame script 119 and that is why nothing breaks the
   loop."* Scripts 119 and 120 are the mouth-flap-while-speaking loops, and their
   semantics are already in the exported nav: `guard_channel 1, guard_when idle`
   plus, on 120, `busy_nav {rel: 0, offset: 1}` to replay the segment while the
   line plays. 116 and 117 are the choice wait loop, also exported. The
   decompilation gap below is real, but it is not what stalls the scene.

2. *"Sampled every 200 ticks the playhead reads 33, 38, 44, 25, 30, 36 — cycling
   forever."* **That measurement is an artifact of the harness, not behaviour.** A
   tight `for i in N: rt.tick(0.016)` loop advances the runtime's clock but not
   the audio server's, so the WAV never progresses, `soundBusy(1)` never goes
   idle, and every speech guard holds for ever. Awaiting `process_frame` between
   ticks walks straight through. **Any guard that reads a real-time subsystem has
   to be exercised in real time**; a synthetic delta makes the engine and the
   subsystem disagree about how much time passed, and the resulting stall is
   indistinguishable from a logic bug.

3. *"Headless has no audio device, so `soundBusy` is always false."* This was in
   the docstring of `tools/_stuck.gd`, since promoted to `tools/probe.gd` with the
   claim corrected and the real-time loop made the default. The Dummy driver does advance
   playback, at roughly 0.35x real time: `TOF1.wav` reports `length 6.68`, and
   `get_playback_position()` climbs 0 → 2.33 over 400 process frames.

**The decompilation gap is real and stays open, but it is not this.** MURDER1's
frame scripts 116, 117, 119, 120 and 424 resolve to nothing, and
`toolcache/chunks/MURDER1/MURDER1/chunks/` holds 33 `Lscr-*.bin` chunks, so the
Lingo is in the binary and the decompiler emitted one cast out of five. What that
costs in practice is entry 23: where a frame script *is* present, the export's
lossy copy of it can still win. Source for a re-run:
`originals/recovery/web-alpha/PIP2DATA/MURDER1.DXR`; ProjectorRays is not
installed here.

---

## 25. Skipping the opening entered DAY1 past its init region, so Piposh had no walk cycle and no spawn point

**Status:** FIXED for the three skip doors · **Area:** skip routing ·
F6 warp and the save editor can still do it, see the end

Reported from play: *"I pressed skip scene, and when I wanted to step off the
beach Piposh walked to the other side; on the next screen there was no character,
only a background."* One cause for both halves.

DAY1's globals are seeded by `BehaviorScript 56 - init all`, which sits on **frame
1**: `egozh = 600`, `egozv = 325`, `syz = 7`, `whatodo = "stand"`,
`nextroomdata = "000"`, `ifmovie = "0,0"`, and the inventory channels puppeted.
`whatodoeveryframe` then walks Piposh toward `egozh`/`egozv` and builds his member
name as `"walkleft" & syz & x`. Enter DAY1 anywhere past frame 1 and none of that
is set: he walks toward **0,0** — the far corner — and the next room places him
off-stage, which is the missing character.

Three doors entered DAY1 past frame 1, none of which the original has:

| door | landed | `egozh`/`egozv` |
|---|---|---|
| dev bar **Skip scene** in the opening | `DAY1:39` `shore2go` | `0,0` |
| dev bar **Skip scene** at the menu | `DAY1:39` `shore2go` | `0,0` |
| **Esc** during EXODUS | `DAY1:39` `shore2go` | `0,0` |

All three now use the movie's own ending instead of an invented destination, and
every route into a hub passes through the hub's frame 1 again:

* **EXODUS** declares its ending in the score — frame 447 is
  `{kind: movie, value: day1, frame: 1}` — so `skip_current` calls `_on_movie_end()`
  and lets `hub_return` read it. It used to invent `{"label": "shore2"}`: the right
  room, past the init region. Deleting a literal in favour of the export.
* **The title** is the one movie with *no* ending nav anywhere in its export, which
  is why `_on_movie_end` fell through `hub_return` and `go_back` to
  `goto_movie(current_hub())` and the boot frame. Its real endings are its menu,
  and from the menu, New Game — so `dev_skip_scene` now takes them one at a time.

After: the opening skip lands on `mainmenu`; a second press goes to EXODUS; a
third reaches DAY1 with `egozh=600, egozv=325, nextroomdata=000, ifmovie=0,0`.
Reproduce either side with `tools/_devskip_probe.gd` (scratch, deleted — the A/B is
in the commit message).

**Seeding was tried first and is the wrong shape.** Running the hub's frame-1
handler on any cold entry — so a labelled entry could seed itself — broke **9**
green checks: `cursors` ("an occupied slot gets the hand", 4 movies) and `smoke`
("collectable hidden when masor held", "handbag visible before the murder is
done", and two more). `init all` *empties `objectsfield` and resets `meetings`*, so
seeding wipes whatever state the caller had set up. That is entry 22's bug
re-introduced at the other end. **Do not add an init-seeding path; route the entry
through frame 1 instead.**

**Still open, and left open on purpose.** `F6` warp and the save editor's **Apply**
both call `goto_movie(movie, label)`, so from a cold boot they can still drop the
player into a hub at a room marker with the same unset globals. The workaround is
to start a game first, then warp. Whether they should instead auto-start one —
which would mean either a seeding path (rejected above) or a two-step "run the
init region, then jump" — is **an open decision, not a pending task**: deferred
deliberately after the fix above, because both options add a mechanism the
original does not have, and the dev tools' docstrings already say they do not
replay the walk that would normally get you there.

---

## 24. Every room entry skips the room's own entry frames

**Status:** open, deliberately not fixed · **Area:** label resolution ·
found while fixing 22, not caused by it

`resolve_label(name, prefer_go)` swaps `<room>` for `<room>go` whenever the "go"
variant exists, and both `goto_movie`'s `label` option and `_on_puppet_arrived`
pass `true`. **The original does not do that.** `whatodoeveryframe` ends a walk
with `go(item 1 of nextroomdata)` — the bare marker — and `go("clif2","day1.dir")`
likewise names `clif2`. In DAY1, `clif2` is frame 1911 and `clif2go` is 1913, and
the two frames between them are the room's own entry work:

* `BehaviorScript 83 - b4 bk's` (`on enterFrame`) sets `nof` from channel 1's
  member name, sets `whereami = label(0)`, and places sprite 30 at `egozh`/`egozv`
* `BehaviorScript 359` (`on exitFrame`) starts the room's ambience —
  `sound playFile 2, effectspath & "clif1.aif"`

Entering at `<room>go` runs neither, in every room, on every arrival.

**It appears to cost nothing, and the reason is the score's own repair.** The
handover scripts also set `nextroomdata`, and the idle script the port *does* run —
`BehaviorScript 55` → `whatodoeveryframe` — reacts to a `nextroomdata` other than
`"000"` by doing `go(item 1 of nextroomdata)` itself, walking into the entry frames
a step late. Measured: `tools/room_names.gd` enters every room through exactly this
path and reports **0 rooms without a `nof` and 0 wrong** across DAY1 (32), NIGHT1
(35) and HOTEL1 (10) — and `nof` is set in the skipped handler, so it is being set
somewhere. That figure was taken *before* entry 25 was investigated and does not
depend on it: 25's fix changed skip routing only, not `goto_movie`, so
`room_names.gd` still enters rooms the same way. Re-read it if `goto_movie` ever
gains an init-seeding path — the abandoned attempt in 25 would have made this
number measure `init all` instead of the score's repair.

What is not established is the case where `nextroomdata` is already `"000"` on
arrival, when nothing re-enters the entry frames: `whereami` then stays whatever
the last room set it to, and stale `whereami` is the failure 640285b9 describes,
with 114 scripts gating a hotspot on it. Left open rather than fixed because a
change to `prefer_go` touches every room entry in the game and needs the
row-by-row read of `tools/lingo_walk_diff.gd` that entry 23 also asks for — not
because the mismatch with the original is in doubt.

**Unrelated trap found the same way:** `godot --headless --script` **exits 0 on a
parse error**. A harness that fails to compile looks like a harness that passed if
you read `$?` instead of the output.

---

## 23. An interpreted `exitFrame` that decides *not* to navigate is overridden by the export

**Status:** open · **Area:** interpreter host / score runner · **general, not one movie**

`game_step` dispatches the frame's own `on exitFrame`, and honours it only when it
navigated or held:

```gdscript
if lingo.dispatch_frame_event("exitFrame", frame_index):
    if lingo.host.navigated or lingo.host.held:
        return
```

Everything else falls through to the exported nav. But **"the script ran and chose
to go nowhere" is a decision, not an absence of one**, and the exported nav is a
lossy summary of that same script with its conditions stripped. So when a handler
navigates conditionally, the port runs the condition, gets `false`, and then jumps
anyway.

MURDER1 frame 789 is the measured case. `BehaviorScript 41` is present and
decompiled:

```lingo
on exitFrame
  global pptcount, tlkpath
  if pptcount = "1" then
    go("moreof")
    sound playFile 1, tlkpath & "tof11.aif"
  end if
end
```

`pptcount` is set to 1 by exactly one script — `CastScript 38`, the middle option
at the *later* `choose2` prompt — so on any other path the handler must fall
through to frame 790 and the scene skips the "more of" branch. The export wrote
frame 789's nav as an unconditional `{kind: label, value: "moreof"}`.

Measured with `tools/_ppt_probe.gd` (scratch, deleted; the transcript is the
evidence):

```
frame 789 script resolves to: BehaviorScript 41
  handlers: ["exitFrame"]
dispatch_frame_event('exitFrame', 789) handled=true  navigated=false  held=false
after one step -> frame 850 label=moreof
```

`handled=true, navigated=false` is the script correctly declining, and the port
went to 850 regardless. Every player therefore sees the optional branch, on every
path through the scene.

**Do not just suppress the export when a script ran — the blast radius is
measured and it is large.** Counting every frame that carries both a
`frame_script` resolving to a movie-local script with an `on exitFrame` and a
non-null exported nav:

| frame's `on exitFrame` | frames |
|---|---|
| navigates **conditionally** (`if` … `go`) | **2,441** |
| navigates unconditionally | 984 |
| never navigates | 4,426 |
| no script resolves at all (export is the only source) | 33,307 |

The 2,441 are the frames this rule change would alter, across **156** distinct
`(movie, script)` pairs — among them `DAY1 BehaviorScript 56 - init all`, every
`gameover` / `end` branch in ARCADE1 and ARCADE2, and the marker-0 hold scripts.
The failure mode is a frame whose handler the interpreter runs but whose `go` it
cannot execute: today the export catches it, and after the change that frame stops
dead. With 33,307 frames having no script at all, the export is load-bearing and
cannot simply lose to the interpreter.

So the fix is not one condition. It needs `tools/lingo_walk_diff.gd` and
`tools/lingo_frames.gd` run either side of it, and the conditional cases read
rather than counted. The count above comes from a static sweep of the handler ASTs
in `data/lingo/*/[cast].json` against the `frame_script` and `nav` fields in
`assets/render_model/*/frames.json` — cheap to redo, and worth redoing before
acting on the figure.

**`MAX_GUARD_HOLD_MS` is dead code in the same function.** `held` is
`_time_ms - frame_entered_ms`, and every branch out of the soundBusy guard —
`busy_nav`'s `enter_frame`, and `_advance_or_hold` — calls `enter_frame`, which
resets `frame_entered_ms`. `held` can never exceed one frame, so the 20-second
timeout has never fired. It matters if a guard ever waits on a sound that does not
start; today `AudioDirector.sound_busy` returns false for a failed channel, so
nothing reaches it.

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

~~Blocked on 1~~ — **no longer blocked, and this is now the highest-value open
entry.** The blocker was that `whatodoeveryframe` drives Piposh entirely through
`the memberNum of sprite 30` and `the locH / locV of sprite 30`, which the
renderer ignored. Entry 1 is closed, so those writes land: booting DAY1 `@field`
and writing `loc_h` / `loc_v` on channel 30 reads back through
`effective_sprite(30)`, and `has_handler("whatodoeveryframe")` is true, as it is
for `peoplefunk`, `peoplecont`, `cursorfunk` and `displayobject`.

**What it now also costs to leave open.** `whatodoeveryframe` is where the
original calls `peoplefunk()` — three times, once per transition shape. The port
never runs it, so it substitutes `GameState.people_funk`, which reproduces only
the meeting-routing half of that handler. The dropped half places the wandering
characters, and its absence is entry 21: every guest in `field`, `tennis`,
`edge1`, `veranda`, `dwarfs` and `exitforest3` is on screen twice. Running this
script fixes 21 as a side effect and retires `meeting_triggers` with it.

Doing it needs `init all`'s globals to exist first — `inexits` at minimum, see
entries 9 and 13 — and needs the 117-hotspot walk diff measured before and after,
because this replaces the walk state machine wholesale. Read
`porting-fidelity-verification` before reading those numbers.

**Baseline for that comparison, measured 2026-08-06 at `176f08ca`**, so the next
attempt can attribute rather than re-derive: `tools/lingo_walk_diff.gd` reports
117 walk cases across 3 movies, **identical outcome 85/117**, 19 of the
differences `[wrong-room]`. All nine pass/fail harnesses green at that commit:
`smoke`, `puppet_visibility`, `sprite_channels`, `room_names`, `collectables`,
`cursors`, `sprite_stretch`, `film_loop_stretch`, `verify_film_loops`. Do not
copy these numbers forward without re-running them — stale figures pasted into
prose have already cost this project a session.

An attempt was made and stopped short; what it established, and what it ruled
out, is in entry 21 rather than here, because the block is in invoking the
handlers at all.

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

**Status:** CLOSED — the guard measured the wrong quantity, see the Closed
section · **Area:** assets / renderer · **See also:** 15

This entry began as the report now filed as 15, and was rewritten into a
film-loop entry when that fix was believed to have closed it. It had not been
confirmed with the reporter, and it had not: the loops resolved, and then their
children resolved against the wrong cast library. 15 is now closed by that second
fix. What is left here is one loop that still does not parse at all.

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

The last member was DAY1's 309, `loshuaa`, on channel 19 for 80 sprites. Its
`SCVW-1800` tripped "channel data exceeds D7 limit" in
`tools/director_film_loops.py` and the loop was skipped. **The D7 constants were
not the cause and did not need re-deriving** — the guard compared two different
quantities. See the Closed entry. The registry now carries 498 loops and
`get_film_loop(1, 309)` returns 161 frames on channels 20, 21 and 22.

Reproduce: `goto_movie("MURDER1")` then `loader.get_film_loop(1, 5)` resolves to 7
frames; `goto_movie("DAY1")` then `get_film_loop(1, 309)` gives 161 frames where
it gave `{}`. The "168x279" this line used to quote for the MURDER1 control is
wrong and predates the film-loop child fix: that child's rect is 108x273, which is
what the Closed entry for 15 also records. The control's frame count, 7, is the
part worth checking.

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

## 14. Art draws stretched on one axis. The dropped stretch flag, at three levels.

**Status:** the score-side half is CLOSED — the stretch flag, see the Closed
section. The **film-loop-child** half is CLOSED — the same flag one level down,
also in the Closed section, and it is what the "scratching" on DAY1's `field`,
`edge1` and `veranda` was. The **strtgame flags** half is CLOSED — its score was
being looked for under a directory name nothing is filed under, see the Closed
section, and recovering it is what the opening video's smeared head was. What
remains open is a **suspicion only**, recorded below and no longer supported by
the evidence this entry was arguing from. · **Area:** assets and score

**A loop's children were the third cause and are now fixed.** The report that
reopened this was four screenshots of DAY1 `@field`, `@edge1` and `@veranda` —
rooms whose guests are `wonder` film loops — with a character intermittently
drawn at double size and others smeared on one axis. A loop's children are sprite
records in the same 48-byte format as the movie's score, so the same flag governs
them, and `tools/director_film_loops.py` was masking it off exactly as the
upstream exporter did for the main score. See the Closed entry; the counts below
are unaffected, because they read `frames.json`, which holds main-score records
only.

Reported twice from play: art "scratching over too much". The clearest instance is
the raft in the opening, where the bearded man's head is smeared horizontally
across the sky.

**Read the Closed entry first.** The score's stored width and height are only the
drawn rect when the sprite's stretch flag is set, and that flag was being dropped on
export. The 979 sprites now split **two** ways on it, with the third group gone:
**932** are the residue and are no longer drawn that way (ALLIN 839, DAGI 51,
INVESTIG 34, strtgame 7, MORN3 1) and **47** carry the flag, so Director really
does stretch them and they were never bugs at all (SEA1 32, NIGHT1 6, ARCADE2 5,
CHESS 4). The "flags unread" category is empty. The reproduce block below prints
this.

That head is `strtgame` member 26, channel 15, frames 122-128, and **all 7 of its
records have the stretch flag clear**. Director therefore ignores the score's
135x34 and draws the member at its own size, which is exactly what the port now
does. The smear was the dropped flag, the same cause as the other two halves — not
a member whose geometry is wrong.

**The three signals this entry used to argue the opposite do not survive
measurement.** Recorded because they looked conclusive:

- the registration point (68, 17) on a 45-wide bitmap does sit outside the image,
  with 68 half of 135. This one still has no innocent explanation and is the whole
  of what keeps the suspicion alive;
- `BITD-2774` PackBits-decoding to 13,568 rather than the 1,564 that stride 46 x 34
  implies proves nothing. **Member 25, this entry's own control, does the same** —
  988 declared against 16,536 decoded — and so do **388 of strtgame's 390** 8-bit
  members. Decoding to a target instead shows member 26's image is a clean prefix
  of 194 bytes in a 3,293-byte chunk. The overrun is a payload-boundary problem
  across strtgame's whole dump, not a fact about this member. For contrast, DAY1
  decodes 440 of 452 members exactly and MURDER1 24 of 24;
- "its `CASt` rect nonetheless reads 45x34" is not a disagreement. 45x34 is the
  declared geometry; that it is declared is not evidence against it.

Anyone picking this up should settle strtgame's chunk boundaries first — only
**17 of 195** 8-bit members reach their declared size as a clean prefix — because
no claim about one member's geometry can be made on top of a dump that is wrong
movie-wide. The visible symptom is fixed either way.

Corpus-wide, searching for the signature — one axis stretched more than 1.8x while
the other stays within 5% of natural — finds **979 sprites in 9 movies**:

| movie | sprites | example |
|---|---|---|
| ALLIN | 839 | `1:1` 640x441 -> 1280x441 |
| DAGI | 51 | `1:13` 129x19 -> 129x35 |
| INVESTIG | 34 | `1:76` 186x13 -> 368x13 |
| SEA1 | 32 | `1:245` 56x12 -> 109x12 |
| strtgame | 7 | `1:26` 45x34 -> 135x34 |
| NIGHT1 | 6 | `1:371` 6x174 -> 6x325 |
| ARCADE2 | 5 | `1:103` 34x10 -> 68x10 |
| CHESS | 4 | `1:21` 60x27 -> 117x26 |
| MORN3 | 1 | `1:10` 136x13 -> 335x13 |

**These are not all the same bug.** The first draft of this entry generalised the
strtgame finding to all nine movies, on the strength of the ratio being close to
2x, and that was wrong. Checking the other movies' `CASt` chunks:

| member | members.json | CASt rect | stride | depth |
|---|---|---|---|---|
| ALLIN `1:1` | 640x441 | 640x441 | 640 | 8 |
| INVESTIG `1:76` | 186x13 | 186x13 | 186 | 8 |
| SEA1 `1:245` | 56x12 | 56x12 | 56 | 8 |
| DAGI `1:13` | 129x19 | 129x19 | 130 | 8 |
| CHESS `1:21` | 60x27 | 60x27 | 60 | 8 |

Every one of those agrees with the container exactly, so their member geometry is
right and the stretch comes from the score's sprite rect instead. strtgame member
26 is the only one measured so far where the member itself is inconsistent. Two
different causes wearing the same symptom.

**The score-side group was the score's rect being read as an instruction.** The
theory recorded here was that ALLIN's `(-641, -12)` at `1280x441` looked like "a
left coordinate and a width derived from each other wrongly". It was not: the
score really does store 1280, and Director really does ignore it, because the
sprite's stretch flag is clear. That is the Closed entry below.

A 4-bit-read-as-8-bit theory was tested and rejected: every member above reports
depth 8 with stride equal to width.

**`strtgame`'s flags were never blocked on endianness.** This entry claimed both
halves were stuck behind `tools/dump_movie_chunks.py` refusing XFIR containers, so
that "there are no chunks to re-derive from" and "fixing the little-endian reader
unblocks both". Both statements were wrong. `strtgame` has had a complete
ProjectorRays dump the whole time — 1,019 chunks including the score — filed under
`STRT_CHUNKS/strtgame/chunks`, and `dump_movie_chunks.py` says so in the very
comment explaining the refusal. `generate_sprite_stretch.py` simply looked for it
at `<root>/<movie>/<movie>/chunks` and missed it, then recorded the miss as `no
chunk dump for VWSC-3148.bin` — a missing file, which is what the entry read as
"could not be recovered". See the Closed entry.

**Ruled out: endianness as the cause of the other eight movies.** The first theory
was that little-endian containers were being mis-read, because `strtgame.dxr` is
XFIR. Only two files in the whole corpus are — `strtgame.dxr` and `MASTER.CST` —
and every other affected movie is big-endian. Recorded because it is a
plausible-looking dead end. It did not block `strtgame` either, contrary to what
this entry used to say. The XFIR reader's own disagreement with ProjectorRays —
441 of 912 chunks, same offsets, different payload boundaries — is a separate,
still-unretested fact, and is not the same claim as "there are no chunks".

Not the same bug as entry 11. That one is 1-bit members read as 8-bit and is fixed.

Reproduce. Note what this counts: it reads `frames.json`, which still holds the
rect the exporter wrote, so it still reports 979 — the sprites are no longer drawn
that way, and `tools/sprite_stretch.gd` is the check for that. What changed is the
split. Every row now lands in `stretched, correct` or `residue, now ignored`, and
a row in `flags unread` would mean a movie's score has stopped verifying:

```
python3 - <<'EOF'
import json, glob, os, collections
stretch=json.load(open('assets/render_model/sprite_stretch.json'))['movies']
hits=collections.Counter()
for p in sorted(glob.glob('assets/render_model/*/frames.json')):
    m=os.path.basename(os.path.dirname(p))
    fr=json.load(open(p)); me=json.load(open(f'assets/render_model/{m}/members.json'))['members']
    flags=stretch.get(m, {}).get('frames')
    for i,f in enumerate(fr.get('frames',[])):
        for s in f.get('sprites',[]):
            mm=me.get(f"{s.get('cast_lib',1)}:{s.get('cast_id')}")
            if not (mm and s.get('has_image')): continue
            mw,mh,sw,sh=mm.get('width'),mm.get('height'),s.get('width'),s.get('height')
            if not all((mw,mh,sw,sh)): continue
            rw,rh=sw/mw,sh/mh
            if not ((abs(rh-1)<0.05 and rw>1.8) or (abs(rw-1)<0.05 and rh>1.8)): continue
            if flags is None: hits[(m,'flags unread')]+=1
            elif s['channel'] in flags.get(str(i),[]): hits[(m,'stretched, correct')]+=1
            else: hits[(m,'residue, now ignored')]+=1
print(sum(hits.values()), hits.most_common())
EOF
```

The stage-clipping fix and the film-loop fix were both landed against this report
and neither addressed it. They fixed real but different defects.

---

## 15. A character is missing or flickering while it moves within a room

**Status:** CLOSED — the film-loop child cast library, see the Closed section ·
**Area:** assets / renderer

Reported: characters that should animate while moving around inside a room are
missing, and the one clearest case flickers rather than being absent outright.
Reported as worst "on the cliff between Tofi and Gondolin", and still present after
entry 12's fix, which is why this entry outlived it.

The room was MURDER1 after all, and entry 12's fix was necessary but not
sufficient. It made the loops in the movie's own cast *resolve*; their children
still resolved against the wrong cast library, so the frames the loops play were
either missing or a stranger's bitmap. The cause is in the Closed section.

The reporter's two symptoms were the two halves of the same defect. Goldolin is
absent for the 11 frames from 108 where channel 3 holds loop `goldolin left`,
whose children are goldolin members 63-69: none resolved, so she vanished and
came back, which is the flicker. And "at the beginning Tofi's mouth appears but he
does not" is frames 5-18: channel 11 carries tofi member 34, the mouth, as a
plain score sprite, which drew, while channel 9 carries loop `tofi right`, whose
child is tofi member 4, the body, which did not. A floating mouth over Goldolin.

What was ruled out along the way, all still true and all still worth not
re-checking:

- **Not the transition spans being skipped.** They play: walking `edge1go` to
  `gatego` visits frames 237..338, covering `gatefromedge1` at 324.
- **Not the puppet's size.** Channel 30 draws at the member's natural size in 1290
  of 1290 room sprites, which is what the score does.
- **Not ink coverage.** The only unhandled inks are 0, which is Copy and correctly
  opaque, and 32 at 948 sprites.
- **Not film loops failing to advance**, at least where they resolve: MURDER1 1 of
  1 film-loop channels advances over 60 ticks, RUNAWAY 3 of 3, SHUFFLE 2 of 2.
- **Not the sprite stretch flag**, checked because the fix for 14's score-side half
  moved 22,806 sprite rects and many of them are character members: `fat` 3,491,
  `hatuli` 3,414, `rinati` 3,008, `hezi` 586. But almost all of those are in the
  ENDMOVI cutscenes, and the two characters actually named in the report are the two
  it barely touches — `tofi` 20 records, `goldolin` none. Their in-room animation
  runs through film loops, which that fix deliberately leaves alone. Independently
  confirmed by this fix: every one of the 2,145 external children has a rect exactly
  equal to its member's own size, so no stretch question arises on them.

**History worth keeping:** this entry was twice believed closed by a fix that had
not been confirmed with the reporter — once when it was rewritten into entry 12,
and the ruled-out list above is what that cost. It is closed now on a
screenshot A/B of the two frames the reporter described, not on a resolve count.

---

## 16. `the number of member X of castLib Y` drops the library

**Status:** open, worked around in one place · **Area:** interpreter host

`LingoHost.member_number()` resolves the name through the cast search order and
returns a bare integer, so the library the script named is lost. Writing that
integer to `the memberNum of sprite N` then keeps whichever library the sprite
already had, which for an empty channel defaults to 1, the movie's own cast.

Seen twice while wiring cursors. `cursorfunk` does

    set the memberNum of sprite 93 to the number of member ("day" & globalday) of castLib "master"

and `displayobject` does the same with `member "object0" of castLib "master"`.
Run against an empty channel both resolved master's member into the movie's
internal cast, and MURDER1, HATDAY1 and GOLDDEAD warned "Missing cast member ...
linked cast internal, member 9" on every load. `_run_cursor_funk()` gates
`displayobject` to hubs to avoid it, which is a workaround at one call site, not
a fix.

1064 sites in the corpus use `of castLib`, so this is not a two-handler problem.

The fix is the same one `the castNum` already has: return a packed reference
(`_pack_member`) so the library survives the assignment. The risk is that
`the number of member ...` results are also compared and used in arithmetic, and
a packed value is a large integer, so every consumer has to be checked first.
That is why it was not done alongside the cursor work.

Reproduce: `goto_movie` any non-hub movie with an empty channel 103 after
removing the `context.is_hub` gate in `_run_cursor_funk()`, and watch for the
missing-member warning.

---

## 17. 478 of the registry's 497 film loops are unverified

**Status:** open · **Area:** verification

`tools/verify_film_loops.gd` walks a hardcoded `CASES` list, now 19 loops: 13 in
seven shared casts, plus 6 added with the child-cast fix that also pin which cast a
named child comes from and its size there. It predates internal-cast film loops,
which took the registry from 295 loops in 21 casts to 497 in 60, and it still
enumerates none of them.

So the harness that gates film loops covers 3.8% of them. A film loop that resolves
to a rectangle of nothing, or to children whose textures are missing, would not fail
any check in the repo unless it is one of the 19.

Two sweeps written for the child-cast fix show what enumeration would buy and are
the shape to keep: every film-loop child any score plays resolves to a bitmap
(7,843 of 7,843), and every sprite and child in MURDER1's 884 frames does too. Both
were throwaway scripts. The fix is to enumerate `cast_registry.json` rather than a
literal list, keep the per-loop assertion it already makes, and report the count so
a drop in coverage is visible.

Reproduce: `godot --headless --script tools/verify_film_loops.gd` prints 19
against `python3 -c "import json;c=json.load(open('assets/render_model/cast_registry.json'))['casts'];print(sum(len(v.get('film_loops',{})) for v in c.values() if isinstance(v,dict)))"`.

---

## 18. The gamepad cursor is drawn by code that has never run

**Status:** open, untested rather than known-broken · **Area:** input / renderer

The mouse gets a hardware cursor. The gamepad pointer is somewhere else on the
stage than the OS pointer, so `MoviePlayer.draw_current_frame()` draws the same
composed cursor at `InputRouter.virtual_cursor` instead, and
`_update_virtual_cursor_visual()` hides the plain block while it does.

Neither branch has ever executed. Every check on the cursor work drove the mouse
path: the harness calls `cursor_at` directly, and the scene probes called
`_apply_cursor` without touching `using_gamepad`. The code parses and the game
boots, which is all that is established.

Two things to look at when someone first plays with a controller: whether
`_apply_cursor` installing a hardware cursor while on the gamepad path leaves a
stray OS cursor wherever the physical mouse happens to sit, and whether the drawn
cursor lands on the hotspot or half a cursor away from it.

---

## 19. The cursor never scales at the most common window sizes

**Status:** open, cosmetic · **Area:** renderer

`MoviePlayer._apply_cursor()` scales the cursor with
`maxi(1, int(floor(_stage_scale())))`. Director cursors here are 13x17 to 17x17,
authored for a 640x480 screen, so at a stage scale of 1.5 — which is what a
default window gives — `floor` yields 1 and the cursor is drawn at native size
against artwork that is half again as large. It only doubles once the window is
big enough for scale 2.

Flooring is deliberate: rounding 1.5 up would draw the cursor larger than the art
around it. The result is still that the cursor is visibly small at the size most
people will play at, and it steps rather than tracking the stage.

Reproduce: run the game at the default window size, hover the floor in DAY1, and
compare the cursor against the artwork it sits on. `_stage_scale()` reports 1.5.

---

## 21. Every wandering character is on screen twice, because only half of `peoplefunk` is ported

**Status:** open · **Area:** interpreter host / score runner

Reported from play as "bugs in the scenes of characters that appear multiple
times", with screenshots of DAY1 `@field`, `@edge1` and `@veranda`. It was first
mistaken for authentic crowd art — the two loops in `@veranda` really do name the
same member — and that reading was wrong. The **member names** settle it:

| room | channels | loops | names |
|---|---|---|---|
| `field` | 18 / 21 | wonder 98 / 94 | `arinlop1` / `brinlop1` |
| `field` | 19 / 20 | wonder 22 / 47 | `apatlop1` / `bpatlop1` |
| `edge1` | 18 / 20 | wonder 150 / 175 | `amoglop1` / `bmoglop1` |
| `veranda` | 18 / 20 | wonder 196 / 201 | `atoflop1` / `btoflop1` |

Each room carries an `a` and a `b` loop of **one** character — Rinati, Pat,
Mogul, Tofi — at two positions. The original shows one of each pair; the port
draws both, so every one of these characters appears twice.

**The original picks with a counter.** `WONDER/MovieScript 246` is `peoplefunk`,
and after its meeting-routing chain it does:

```
repeat with i = 18 to 21
  puppetSprite(i, 0)
end repeat
if item 1 of nextroomdata = "field" then peoplecont(1)
  else if ... "tennis" then peoplecont(2)
  else if ... "edge1"  then peoplecont(3)   -- but on day 3, hide 18 and 20 outright
  else if ... "veranda" then peoplecont(4)
  else if ... "dwarfs" then dwarfscont(8) / dwarfscont(9)
  else if ... "exitforest3" then dwarfscont2(10)
```

and `peoplecont(i)` advances `item i of inexits` 1..10, wrapping, then shows one
pair and hides the other:

```
if x > 5 then  18,19 invisible; 20,21 visible
else           18,19 visible;   20,21 invisible
```

So the guests move around the estate as you re-enter rooms. The talk behaviours
read that state back — `BehaviorScript 290` and `291` both branch on
`if sprite(18).visible = 1`, and `BehaviorScript 249` picks `xxx = "a"` or `"b"`
with the channel numbers to match — so with nothing hidden they also take the
wrong branch and drive the wrong sprite.

**Two things are missing, and the second is an old friend.**

1. `DirectorRuntime._try_people_funk` calls `GameState.people_funk`, which is a
   `meeting_triggers` table lookup and nothing else. It reproduces only the
   routing chain at the top of the original handler; the `puppetSprite` /
   `peoplecont` half below it has no port at all.
2. `inexits` is never set. `init all` seeds it as `"0,0,0,0,0,0,0,0,0,0"` and
   `init all` never runs — that is entries 9 and 13, biting a third time. Even if
   `peoplecont` were called, `value(item i of inexits)` has nothing to read.

Not a rendering bug: the interpreter has both handlers loaded and sprite writes
do reach the stage (entry 1 is closed, `tools/sprite_channels.gd` covers it).

Reproduce — all four channels present and none hidden, with both globals unset:

```
godot --headless --script - <<'EOF'
extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
    var r: RefCounted = load("res://director/director_runtime.gd").new()
    r.boot(); r.goto_movie("DAY1", null, {"label": "field"}); r.running = false
    print("peoplefunk=%s peoplecont=%s inexits=%s" % [
        r.lingo.interpreter.has_handler("peoplefunk"),
        r.lingo.interpreter.has_handler("peoplecont"),
        str(r.lingo.interpreter.globals.get("inexits", "<unset>"))])
    for c in [18, 19, 20, 21]:
        print("ch%d hidden=%s" % [c, r.is_channel_hidden(c)])
    quit(0)
EOF
```

Observed: `peoplefunk=true peoplecont=true inexits=<unset>`, and all four
`hidden=false`.

Not the same bug as 14's film-loop half, which was found in the same rooms in the
same pass. That one drew these characters at the wrong size; this one draws twice
as many of them as there should be.

**Attempted and not finished — the handlers resolve but invoking them does
nothing.** This is the next thing to chase, and it is narrower than where this
entry started. Booting DAY1, seeding the globals `init all` would have left, and
calling the handlers straight off the interpreter changes no observable state:

| call | `inexits` after | channels 18-21 |
|---|---|---|
| `call_handler("peoplefunk")` | `0,0,0,0,0,0,0,0,0,0` | all shown |
| `call_handler("peoplecont", [1])` | `0,0,0,0,0,0,0,0,0,0` | all shown |
| `call_handler("whatodoeveryframe")` | `0,0,0,0,0,0,0,0,0,0` | all shown |

`peoplecont(1)` on `inexits = "0,0,…"` must leave `1,0,0,…` and hide 20 and 21.
It leaves both untouched, so the body is not running — the handler is not merely
taking a branch that skips the writes.

Ruled out on the way, so they do not get re-checked:

- **The handler is missing.** `has_handler` is true for `whatodoeveryframe`,
  `peoplefunk`, `peoplecont`, `cursorfunk` and `displayobject`.
- **Chunk assignment is unimplemented.** `put x into item i of inexits` has a
  path: `_assign_chunk` at `lingo_interpreter.gd:408`.
- **The `global` declaration wipes the seeded value.** It is guarded by
  `if not globals.has(key)` at `lingo_interpreter.gd:234`, and keys are
  lowercased, which is what the probe wrote.
- **Sprite writes cannot reach the stage.** Entry 1 is closed and
  `tools/sprite_channels.gd` passes.

Two candidates not yet separated: `call_handler` outside a frame dispatch may not
establish whatever scope the body needs, or `sprite(N).visible` for a channel
other than 30 may not land where `is_channel_hidden` reads. Test the second
first — it is one assertion — because if it is true then the body may have been
running all along and `inexits` is a separate defect.

**The fix is entry 2, not a patch here.** The original calls `peoplefunk()` from
`whatodoeveryframe` and nowhere else, so there is no engine-level place to put
this that does not amount to teaching the engine that `field` is slot 1 and that
channels 18-21 hold guests — which is the standing rule in `AGENTS.md` broken in
the same shape that caused the bug. `whatodoeveryframe` is runnable now that
entry 1 is closed; running it fixes this one for free and retires
`GameState.people_funk` at the same time. Deliberately **not** patched natively.

---

## 20. `wonder.cst` has a degenerate `ccl `, so 98 film-loop children draw nothing

**Status:** open · **Area:** assets / cast registry

`tools/generate_cast_registry.py` prints `2145 resolved, 98 dropped as
unresolvable`, and **all 98 are WONDER's**. Every other cast in the corpus
resolves every child.

The cause is in the container. `ccl -3333.bin` is 18 bytes — header, `count = 1`,
offsets `[0, 4]`, then `00 01 00 00` — so its single entry is a **zero-length
path**. Compare MURDER1's, which is 131 bytes and holds three real paths
(`macintosh hd:pip2 full:tofi.cst` and so on). `parse_ccl` therefore answers
`['']`, `resolve_cast('')` answers `""`, and `_frame_sprites` refuses every child
whose `cast_index` is 0 rather than let it fall back on the owning cast — that
refusal is deliberate and correct, because the fallback draws a stranger's bitmap
(see the Closed entry for 15). The children are simply invisible instead.

They are only two distinct members, but neither is small and one is on screen a
lot:

| member | size | channel | records |
|---|---|---|---|
| 983 | 153x197 | 10 | 74 |
| 222 | 70x51 | 17 | 24 |

**Which cast they belong to is not yet known, and the usual method fails here.**
Sizing the children against every registered cast is what identified `tofi` and
`goldolin` for MURDER1; it finds nothing this time. Member 983 exists in **no**
registered cast at any size — only `sea1` even reaches that far, at 1033 — and no
member anywhere in the corpus is 153x197 or 70x51. So the referenced cast is
plausibly one that was never exported, which would make this an extraction gap
rather than a parsing one. WONDER is the crowd cast for DAY1, NIGHT1 and SEA1, so
whatever is missing is missing from the three biggest hubs.

Not the same bug as 14's film-loop half. That one drew children at the wrong
size; this one does not draw them at all, and the two were found in the same pass
over the same rooms.

Reproduce:

```
python3 tools/generate_cast_registry.py    # "98 dropped as unresolvable"
python3 -c "
import sys; sys.path.insert(0,'tools')
from pathlib import Path
import director_film_loops as dfl
root = Path.home()/'Projects/_private_projects/piposh2-toolcache/chunks'
print(dfl.parse_ccl(root/'WONDER/WONDER/chunks'))    # ['']
"
```

---

## Closed

- **A movie's chunk dump was looked for under the wrong directory name** (part of
  14). `generate_sprite_stretch.py` built its path as `<root>/<movie>/<movie>/
  chunks`, but a dump's outer and inner directory names are not always the same:
  `strtgame`'s is filed under `STRT_CHUNKS/strtgame/chunks`. So the one movie whose
  stretch flags mattered most was the one movie the lookup could not find, and it
  reported the miss as `no chunk dump for VWSC-3148.bin`. Read as "no dump exists",
  that became entry 14's claim that recovering strtgame's flags was blocked on
  little-endian container support. It was blocked on a directory name.

  `dump_movie_chunks.py` already keys dumps by the **inner** directory for exactly
  this reason, and its comment names `STRT_CHUNKS` as the case. That keying is now
  shared: `chunk_dirs()` globs `*/*/chunks` and keys on `parts[-2]`.

  The reading it unblocked verifies as strictly as every other movie, which is why
  it can be trusted rather than merely accepted: 1,375 score frames against 1,375
  exported frames, **11,863 sprite records compared field by field with 0
  mismatches** across `cast_lib`, `cast_id`, `width`, `height`, `loc_h` and
  `loc_v`. 293 records carry the stretch flag. `strtgame` is no longer in
  `sprite_stretch.gd`'s "no recovered flags" list, the verified count went 69 to
  70, and the 7 sprites entry 14 was still chasing moved from "flags unread" to
  "residue, now ignored" — Director ignores those rects, so member 26 draws at its
  own 45x34 and the opening video's smeared head is the flag, not the member.

- **A film loop's size guard measured the whole stream against one frame's buffer**
  (was 12). `parse_scvw` read the third word of the `SCVW` list header as a channel
  data length and refused the resource when it exceeded `MAX_D7_CHANNEL_DATA`, the
  288 + 48 x 200 capacity of a single frame's channel buffer. That word is not a
  buffer size: it is the byte length of the whole frame-data region. It equals
  `len(data) - (index_start + list_size * 4)` for **287 of 287** `SCVW` chunks in
  the corpus, exactly, which is what identifies it.

  So the guard grew with the *length of the loop* and had nothing to do with how
  many channels a frame touches. Only one loop in the corpus was long enough to
  cross the line — DAY1's 309, `loshuaa`, declaring 13,184 against the 9,888
  ceiling. Its deltas in fact reach byte **1,344** of that 9,888 buffer, using 22
  sprite channels of the 200 allowed, so the D7 constants were right the whole
  time and re-deriving them, which this entry previously called for, would have
  found nothing wrong.

  The parse was never in doubt either. Every loop measured, working ones included,
  terminates with the frame-data stream exactly exhausted (`consumed ==
  inner_stream_size`), and `frames != list_size` is normal throughout — DAY1's
  `SCVW-1777` yields 20 frames from a `list_size` of 16, SEA1's `SCVW-5694` yields
  27 from 256. 1800 behaves like all of them: 161 frames, stream exhausted.

  The bound that does matter was already there and is untouched — each channel
  delta is checked against the real buffer before it is written. What replaced the
  guard is the sanity check the header supports: the frame-data region must fit
  inside the resource. The registry went from 497 loops to 498, the diff is pure
  insertion with nothing existing altered, and `verify_film_loops`,
  `sprite_stretch` and `film_loop_stretch` all still pass.

- **A film loop's frames were looked for in the wrong cast library** (was 15).
  A loop's children are usually members of the cast the loop itself lives in, and
  `_draw_film_loop` assumed always: it resolved every child against the loop's owning
  cast. MURDER1 keeps `tofi right`, `goldolin left` and `hezi right + angry` in its
  own cast while the frames they play are members of `tofi.cst`, `goldolin.cst` and
  `hezi.cst`, so the children resolved to whatever the movie's own cast happened to
  have at that number — nothing at all for most, and MURDER1's own member 4, a
  533x17 strip, for the rest, stretched into the child's 108x273 rect as a green
  smear. Both characters on the cliff were drawn from those loops.

  A loop's mini-score does say which library, at offset 4 of the 48-byte sprite
  record, the same place the movie's own score keeps it. `0xFFFF` is the owning cast,
  as in the main score. What differs is that a number there is **not** a cast-library
  index: it is a zero-based index into the file's `ccl ` chunk, an ordered list of the
  cast paths its loops reference, which is a different order. MURDER1's libraries run
  internal, goldolin, hezi, tofi; its `ccl ` runs tofi, goldolin, hezi.

  Read off the containers, not recalled: `ccl [raw]` predicts the cast for all
  **2,145** external children in the corpus, and the member is present in the named
  cast for every one of them — 0 out of range, 0 absent. The parse agrees with a byte
  scan of the same chunk in 29 of 31 dumps, the two exceptions being the chunks whose
  single entry is a genuinely empty path. The negative control holds too: the 9
  cast-only exports have no `ccl ` and emit nothing but `0xFFFF`.

  `tools/director_film_loops.py` now resolves the index to the cast's registered
  name and `generate_cast_registry.py` writes it on the child as `cast`, checking
  against the built registry that the name can answer for the member. A child that
  cannot be resolved is dropped and counted rather than left to fall back on the
  owner, because that fallback is this bug. **98 are dropped**, all in WONDER, whose
  `ccl ` holds one empty path; their members (222 at 70x51 and 983 at 153x197) are in
  no cast in the corpus, so there is nothing yet to point them at.

  Of those 2,145 children, **1,529 previously drew a real but unrelated member of
  the owning cast** and 616 drew nothing, so most of this was wrong art rather than
  absent art — which is why it read as flicker. Counting only the loops a score
  actually plays, 592 of 7,917 children came out blank before and 0 of 7,843 do now,
  across 21 movies (ALLIN 111, SEA1 74, MURDER1 62, SAMNIGHT 59, MORN3 44, …). The 74
  fewer are SEA1's `wonder` loop 673 shedding the unresolvable children described
  above; they drew nothing before and are simply no longer claimed.

  Every sprite and every film-loop child in MURDER1's 884 frames now resolves to a
  bitmap: 5,378 plain sprites and 1,534 children, 0 blank. `lingo_converge`,
  `lingo_frames`, `verify_1bit_members`, `check_cast_coverage` and
  `generate_sprite_stretch --check` are byte-identical across the change, and
  `lingo_walk_diff` differs only in Godot's exit-time leak counters.

  Covered by `tools/verify_film_loops.gd` in two ways, and the difference matters.
  Its 6 added `CASES` assert which cast a named child comes from and its size
  there — but that check resolves the child itself, so it gates the **exported
  data** and passes with the renderer reverted. Its `COMPOSITIONS` list gates the
  **renderer**: `MoviePlayer.film_loop_draw_commands()` was split out of
  `_draw_film_loop` so a loop's composition can be asserted without a window, and
  the harness runs it on the two frames the cliff was reported on. Revert the child
  cast lookup in the renderer alone and all three go red with the wrong members
  named — `["murder1:4"]` for Tofi's body, `[]` for Goldolin — which is the check
  the data assertion could not make. The split is behaviour-neutral: the five
  MURDER1 frames render byte-identical PNGs across it.

- **A film loop's children drew scaled to a rect Director ignores** (the
  film-loop half of 14). The entry below fixed this for the movie's own score and
  said in passing that film loops were untouched. That was true and it was the
  gap: a loop's children are sprite records in the same 48-byte format, carrying
  the same **stretch** flag at bit `0x80` of the ink byte, and
  `tools/director_film_loops.py` masked the byte to its low 6 bits for the ink and
  dropped the flag with it — the identical loss, one level down, in a second
  reader written months apart from the first. `MoviePlayer.film_loop_draw_commands`
  then scaled every child into its recorded rect.

  Of the corpus's 13,694 children, 13,596 resolve to a member. **2,053 carry the
  flag** and Director really does scale them; 11,308 have it clear with a rect
  already equal to their member, so nothing changes; and **235 have it clear and
  disagree**, which is the bug. By cast: `wonder` 130, `tennis` 55, `master` 16,
  `investig` 10, `endmovi1` 7, `gardug` 6, `samnight` 6, `arcade2` 3, `ishurun` 2.

  **The separation is perfect, which is what identifies the bit.** Of the 2,053
  flagged children, **zero** have a rect equal to their member's natural size —
  the same argument the main-score entry below rests on, run on the child
  population. So bit 0x80 is the stretch flag here too, and the 235 are provably
  the whole of the residue rather than however many happened to be noticed.

  `wonder` holds the worst: member 27 is 101x144 and its record says 203x289, so
  DAY1 `@field` channel 20 drew a guest at double size on 6 of the loop's 24
  frames — the giant black dress in the report — and normally on the other 18.
  The one-axis cases are the "scratching": `wonder` 59 at 84x159 recorded 97x159.

  Per reported room, child records whose drawn rect changed: `@field` **54 of
  242**, `@edge1` **17 of 166**, `@veranda` **16 of 154**. All three move, but
  only `field` carries a blow-up big enough to read as a different bug — its
  worst is 2.01x against 1.16x on `edge1` and 1.15x on `veranda`, which are
  smears rather than giants. `edge1`'s other loop, `wonder` 175, is a zoom with
  every child flagged and is deliberately left alone.

  **This does not touch the opening video.** `strtgame` contributes 0 of the 235,
  so the smeared head there is still 14's member-side half, blocked on the XFIR
  little-endian reader.

  The flag is written on the child as `stretch` and only where set, so its absence
  means "draw the member at its own size". Regenerating `cast_registry.json` over
  the fix leaves the file **identical once `stretch` is stripped**, which is how
  the change was attributed.

  Covered by `tools/film_loop_stretch.gd`. Its fourth case is a **negative
  control** and is the reason the harness is worth having: `wonder` loop 175 is a
  zoom, every child flagged, its members recorded at ~88% of natural size. A "fix"
  that simply stopped honouring the recorded rect would pass all three positive
  cases and silently un-animate the zoom. Reverting the renderer alone turns the
  three positives red with the stored rect named in each failure and leaves the
  control green.

  Both position and size are asserted. A child is anchored on its registration
  point, so changing the drawn size moves the top-left with it, and size alone is
  the weaker claim: the giant goes from 203x289 at `(362.91, -159.00)` to 101x144
  at `(372.00, -14.00)`, and the guest on the bench from 101x144 at
  `(-12.25, 95.25)` to 142x192 at `(-16.00, 45.00)`.

- **Art drew scaled to a rect Director ignores** (the score-side half of 14).
  A Director sprite draws its member at the member's own size, anchored on the
  member's registration point. The width and height in the score are the drawn rect
  only when the sprite's **stretch** flag — bit `0x80` of the sprite record's ink
  byte — is set. With it clear they are authoring residue: the last size the channel
  was dragged to, or the size of a member that used to be there. The upstream
  exporter masks the ink byte to its low 6 bits, dropping the flag, and writes the
  residue into `frames.json` regardless, so the port scaled 22,806 sprite records
  into a rect the original never draws.

  Three independent measurements say that is the flag, two of them on populations
  not used to find it. Of 437,926 sprite records whose rect already equals the
  member's natural size, **zero** carry the bit; 12,265 records differ from their
  member and carry it. On film loops, which the fix does not touch: all 37,329
  records with the bit clear have a rect exactly equal to the loop's own initial
  rect, and all 1,295 with it set differ. And in ALLIN, channel 1 holds the same
  member at the same registration point for all 1438 frames with a stored width of
  1280 on 835 of them, 640 on 259 and 639 on 337, the member being 640 wide — so the
  backdrop popped between the hotel room and its right half at double size as the
  playhead stepped, and the 640 frames are what the fixed 1280 frames now look like.
  That within-movie A/B is the cheapest way to see it: render frame 718 and frame 0.

  `tools/generate_sprite_stretch.py` recovers the flags from the containers into
  `assets/render_model/sprite_stretch.json`, verifying each movie's score against
  `frames.json` field by field and refusing the movie outright if it does not
  reproduce the export. `RenderModelLoader._resolve_sprite_rects()` applies them
  once per movie load, so the channel array, drawing, hit-testing and any script
  reading the sprite all see one rect. Covered by `tools/sprite_stretch.gd`.

  Three things to know. **16 movies have no recovered flags and keep the exported
  rects**; only `strtgame` matters, and it is entry 14's remaining work. **820 of
  the moved rects belong to sprites with click data** (477 smaller, 343 larger),
  which is intended — Director hit-tests the sprite it drew — and `lingo_walk_diff`,
  `lingo_converge` and `lingo_frames` are row-for-row identical across it. And
  `data/walk_doorways.json` derives its walk targets from these rects offline, from
  `frames.json`, which still holds the residue: checked, and 1 of its 77 overrides
  sits on a channel whose rect moved, that one sourced from `reciprocity` rather
  than a hotspot centre. Regenerating it would have to apply the flags first.

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
