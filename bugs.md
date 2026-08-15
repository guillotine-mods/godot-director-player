# Known bugs and open engine gaps

One entry per issue, worst first. Each carries the evidence it was found with, so
the next session can confirm it still reproduces before working on it rather than
trusting this file.

Numbers here were measured on the commit that added the entry. Re-run the tool
named in the entry before acting on a figure. Agreement with the lifted export
falls as the port gets more faithful, so a moved number is not automatically a
regression: see `.claude/skills/porting-fidelity-verification/SKILL.md`.

Resolved entries live in [`docs/bugs-closed.md`](docs/bugs-closed.md), under the
numbers they were filed with, because source comments cite them. Entry 25 appears
in both files: the fixed half is there, the remainder is here.

## The 2026-08-14 sweep, and what it says about reading this file

**All 66 entries were re-checked against the tree at `85b06dd3`, and 38 of them no
longer described it.** (Re-confirmed at `ecc6d070`, which landed mid-sweep and
touches only `scenes/preview/channel.gd` and one harness.) They are now in `docs/bugs-closed.md` in two sections: 20
whose defect was fixed and whose entry was never moved, and 18 whose *subject was
deleted* with the retired renderer and which therefore cannot be re-measured at
all. Seven more were narrowed in place, and one — 100 — was answered from the
reference and reclassified as not a bug. What is left below is 16 open entries,
7 narrowed ones and 4 not-a-bug signposts, one fewer than the sweep left because
106 has since been fixed and moved.

Two rules came out of it, and both are cheaper to follow than to rediscover:

- **A `**Status:**` line is not evidence.** Entries are written when a defect is
  found and are not reliably closed when it is fixed. 34 was fixed the day after it
  was filed and sat open for six days, during which 100 was filed *citing 34's open
  half* as the question it needed answered.
- **A commit subject is not evidence either.** In this repository a commit titled
  `bugs.md <n>: <restatement>` **files** an entry; it does not fix it. The two
  newest such commits name 105 and 106 and both are open below. Read the diff body,
  or the code at the path in the entry's own **Area** line.

**Three numbers are reused by unrelated entries, so a citation to one of these is
ambiguous and needs its title to disambiguate.** Found by an audit over both
files; recorded rather than renumbered, because source comments cite these numbers
and renumbering breaks that contract worse than the collision does. The sweep put
both halves of 33 and 34 in the closed file, so all three rows now read "closed"
on both sides and a bare citation resolves to two entries in one file.

| number | one entry | the other |
|---|---|---|
| 33 | closed: `gate.sh`'s `editable_text` asserts nothing | closed: `go to frame X of movie Y` read its own command word |
| 34 | closed: `the visible of sprite N` on an empty channel | closed: film-loop children drew from the wrong cast |
| 41 | closed: `member (<expr>) of castLib X` drops the library (`66baa6a5`) | closed: `play_suspends` flakes about half its runs (`b8466abb`) |

> **Some "Reproduce:" lines below still name tools that no longer exist.** The
> retired renderer and the ~24 harnesses that drove it were deleted; every command
> naming `smoke.gd`, `probe.gd`, `cursors.gd`, `room_names.gd`,
> `sprite_channels.gd`, `sprite_stretch.gd`, `film_loop_stretch.gd`,
> `verify_film_loops.gd`, `collectables.gd`, `cliff_meeting.gd`,
> `wandering_characters.gd`, `puppet_visibility.gd`, `lingo_converge.gd`,
> `lingo_frames.gd`, `lingo_walk_diff.gd`, `lingo_handler_scope.gd`,
> `sound_state.gd`, `check_surface_coverage.gd`, `score_diff.gd`, `place_diff.gd`,
> `member_diff.gd` or `tools/lib/driver.gd` will not run, and neither will anything
> reading `assets/render_model/` — that directory is deleted, and `data/` now holds
> only `director_palettes.json`.
>
> The 18 entries whose *whole subject* was one of those deletions are closed. What
> remains here is the weaker case: an entry whose observation is about live code and
> whose *command* is gone. Re-proving it against the live player is the first step
> on any of them.

---

## Coverage debt — harnesses deleted with the retired renderer

These asserted rules that still matter, through an engine that no longer exists.
Nothing replaced them. Listed worst first, so that "we have no coverage of X" is
written down rather than remembered.

| Was | Asserted | Live equivalent |
|---|---|---|
| `tools/smoke.gd` | The first minute of play, end to end: menu, new game, opening sequence advances rather than loops, an item is picked up *and* leaves the room | **none.** `gate.sh` tests mechanisms one at a time and nothing walks a playthrough. The biggest hole |
| `tools/check_surface_coverage.gd` | Which Lingo names the host actually binds, against `docs/LINGO_SURFACE.md` | **none.** This is the tool that would have caught the `intersects` hole and could not, because it audited the retired host. Rebuilding it against `scenes/preview_lingo_host.gd` is the highest-value port on this list |
| `tools/probe.gd` | Not pass/fail: where the playhead went, what it repeated, where it stopped, in real time | **partly.** `tools/liveness_sweep.gd` records `(movie, frame, sprites drawn, what is holding)` per score tick off real awaited frames, and prints the state set and the holds for every movie of a corpus. It is a sweep and not an interactive probe: no `--marker`, no stepping, no arbitrary breakpoint, and it drives clicks only with `--click`. "Where did the playhead go in *this* situation" still has no tool |
| `tools/sprite_channels.gd` | A Lingo sprite write reaches the stage — not that a setter and getter agree | **none.** `preview_surface` proves the surface resolves, not that a write is consumed. This is the exact shape of the `moveableSprite` bug |
| `tools/lingo_handler_scope.gd` | Which script receives a message, in which order | **none.** `scenes/preview/scripts.gd` is unharnessed |
| `tools/sound_state.gd` | `soundBusy`, volume and `soundLevel` as a script sees them | **none.** `scenes/preview/sound.gd` is unharnessed |
| `tools/puppet_visibility.gd` | A puppeted sprite's visibility survives a transition | **none** |
| `tools/room_names.gd` | `nof` resolves to the room, and no two rooms share a key | **none.** It also printed "0 failure(s)" over 0 rooms, so it had stopped asserting anything long before it was deleted |
| `tools/collectables.gd`, `cliff_meeting.gd`, `wandering_characters.gd` | Scenario coverage: items reveal/stay/take, a dialogue runs to its end, guests are placed once | **none** |
| `tools/cursors.gd` | cursorfunk's cursor per channel | `tools/cursor_preview.gd`, in `gate.sh`, green |
| `tools/sprite_stretch.gd` | A sprite draws at its member's size | `tools/drawn_size_stability.gd`, in `gate.sh`, green |
| `tools/verify_film_loops.gd`, `film_loop_stretch.gd` | Film loops resolve to children, at the child's size | `tools/film_loop_cast.gd`, in `gate.sh`, green — the size half is not covered |
| `tools/score_diff.gd`, `place_diff.gd`, `member_diff.gd` | The container reader against the exported JSON | `tools/container_equality_check.gd`, in `gate.sh`, green, against the ProjectorRays dumps instead. The export oracle is gone for good |
| `tools/lingo_converge.gd`, `lingo_frames.gd`, `lingo_walk_diff.gd` | Interpreted clicks / frames / walks against the export | **unportable** — the oracle was the export |

Separately: **`tools/lingo_compile_check.gd` still exists and reports `PASS` over
nothing.** Its oracle was `data/lingo/`, deleted; it prints
`containers with no bundle under res://data/lingo (1)` and then
`PASS (11 checks, 0 failed)`. `README.md` called it "the regression gate for any
parser change". It was left in the tree because it gates the parser rather than
the renderer and comes back if `data/lingo/` does, but its green means nothing
today.

---

## 46. Piposh 1's ship is silent because `games/piposh` has no `PIPDATA/FX` tree at all

**Narrowed 2026-08-14: the Hebrew half is closed and only `piposh-ru` is left.**
`find games/<root> -ipath '*fx*' -iname '*.aif' | wc -l` now answers **126 for
`games/piposh`**, the same count as `piposh-en`, so the deck music and the 116
effect filenames below have files behind them and the ship is not silent any more.
`piposh-dream` has 159. **`games/piposh-ru` still answers 0**, composing the
identical path from its own `master.cst` — so everything below still holds, for
that one root. The heading is wrong about which root and is left as filed so the
`git log` of the submodule bump stays findable.

That also settles the "whose gap is it" paragraph one way: a root that was missing
the tree got it back from the disc, so this is an extraction gap and not a disc
that shipped without it. `piposh-ru` needs the same treatment and nobody has done
it.

**Status:** OPEN, and **not an engine fault** — the port composes the request
correctly and plays it the moment the file exists. Reported from play as "the
background music on the ship doesn't work". · **Area:** the `games/piposh`
submodule's contents, not this repo's code.

Every deck room's `exitFrame` is the same handler (`PIPDATA/DAY1.dir`, and
DAY2-DAY5 identically):

```lingo
on exitFrame
  global effectspath2, whichmus
  whatodoeveryframe()
  if not soundBusy(2) then
    set the mouseDownScript to EMPTY
    sound playFile 2, effectspath2 & whichmus
  end if
```

`effectspath2` is `the moviePath & "fx" & y & "fxmus" & y` (`MASTER.CST`), so the
music is a per-frame re-request against `PIPDATA/FX/FXMUS/`. **That folder does
not exist under `games/piposh`**, nor does its parent `PIPDATA/FX`. Neither does
it under `games/piposh-ru`. `games/piposh-en` has both: 126 files, 35 of them the
music.

Measured, same movie both ways, on real frames:

```
godot --headless --path . --script tools/music_requests.gd -- --root piposh    --movie PIPDATA/DAY1.dir
godot --headless --path . --script tools/music_requests.gd -- --root piposh-en --movie pipdata/DAY1.dir
```

```
piposh     SILENT  res://games/piposh/pipdata/fx\fxmus\dbsndlow.aif
                   resolves to <nothing on disc>        channel 2 audible on   0 of 400 frames
piposh-en  PLAYS   res://games/piposh-en/pipdata/fx\fxmus\dbsndlow.aif
                   resolves to .../FX/FXMUS/DBSNDLOW.AIF  channel 2 audible on 371 of 400 frames
```

Both roots reach the deck with identical globals — `whichmus = dbsndlow.aif`,
`effectspath = <root>/PIPDATA/fx\` — so the only variable is whether the file is
on disc. Confirmed in the other direction too: dropping the single file
`DBSNDLOW.AIF` into `games/piposh/PIPDATA/FX/FXMUS/` takes the Hebrew deck from
0/400 to **372/400** audible frames. (Copied for the measurement and removed
again; the submodule is untouched.)

**The scope is far wider than the music.** `effectspath` is the same tree one
level up, and the Hebrew containers ask it for **116 distinct filenames** — door
handles, footsteps, locks, hits — of which **110 exist in `piposh-en`'s `FX/`**.
So every sound effect on the ship is silent for the same reason, and the 18
background tracks (`arcade arcade2 bath dbsnd dbsndlow downdeck foodroom justeng
loby lolo lowdeck movie stimoff stimon stopstim strtstim topdeck ware`) are the
audible half of one gap. The six the English disc does not hold either
(`boing detective dream pipaaa robot shirt`) are a separate question.

**What is not settled: whose gap it is.** The Hebrew movie *composes* the path, so
the folder existed when the game was authored — that was the argument for calling
it an extraction defect in the `guillotine-mods/piposh` submodule. Against it:
`piposh-ru` composes the identical path (`master.cst`:
`put the moviepath & "fx" & y & "fxmus" & y into effectspath2`, nine containers
naming `fxmus`, `pipdata/Day1.dir` running the same `playFile 2, effectspath2 &
whichmus` loop over the same `bath/justeng/lolo/ware/stimon/stimoff` names) and is
missing the tree too. Two of three localisations losing the same folder while
asking for it is as consistent with one faulty extraction pipeline as with a disc
that shipped without it. `games/piposh` holds no installer archive to re-extract
from, so settling this needs the original media.

**Do not "fix" this in engine code.** A fallback that reaches into another root
for a missing file would make every future data gap invisible, which is the state
`audio_director.gd`'s `Audio miss` logging exists to prevent. The two honest repairs are re-extracting the disc, or copying
`piposh-en/pipdata/FX` into the Hebrew and Russian roots as a deliberate,
recorded substitution. If the substitution is taken, the files have to be
listened to first: nothing here has been played back. `LOLO.AIF` is 5.6 MB and
shares its name with a character who has her own cast and three day-movies, which
is not the size or the naming of a wordless loop, so at least some of the 35 are
likely to carry English voice.

**The same probe on the other roots.**

```
godot --headless --path . --script tools/music_requests.gd -- --root piposh-dream --movie Hquest.dir
```

`piposh-dream` has the identical shape at a much smaller scale: `Hquest.dir` runs
`if not soundBusy(2) or (whichsnd <> "sea") then sound playFile 2, effectspath &
"sea.aif"`, and no `sea.aif` exists anywhere under `games/piposh-dream` — 0 of 400
frames audible. (That run entered `Hquest.dir` cold, so `effectspath` was still
empty and the request went out as the bare name; it fails the same way either
way, because `resolve_path` tail-matches a filename under any folder and there is
no `sea.aif` under any.) Across that root, 19 of the 116 filenames its containers ask
`effectspath` for have no file: `1234 bish crash drill findjoke handle jaquasi jmp
kick machak move nofound openbag sea sissy soja stage water yanki`. Some of those
are near-miss spellings rather than absences — the disc holds `JAQAUSI.AIF` for a
request of `jaquasi.aif`, and `DRILL.WAV` for a request of `drill.aif` — and
separating the two is the work that entry has not had.

**Why the log says it dozens of times.** `audio_director.gd:321` short-circuits a
repeat request only when the previous request matches *and* the channel is
actually playing. A failed request writes `_channel_file` but starts nothing, so
the guard falls through on every re-entry and `_fail` logs unconditionally. The
count measures how long the room held the playhead, not how many distinct faults
there were. `_fail` stopping the channel is load-bearing for `soundBusy` and must
not be touched; the cheap quieting fix is to log once per `(channel, request)`
until the request changes. Not done — it would hide this entry's symptom while
the data is still absent.

---

## 45. A hit on a Piposh 1 submarine lifts it 122px, so after two it is clipped off the top of the stage

**Status:** OPEN · **Area:** `PIPDATA/CANON.dir` game6, `allshipscounter` ·
reported from play with a snapshot: frame 373, 51 degrees, score -53, the large
submarine jammed against the top of the stage and drawn over the HUD panels.

**Newly reachable, which is why nobody has seen it before.** This path needs a
shot to register, and until entry 43's fix landed no shot in the cannon game ever
did. `sub1hit1`..`sub3hit4`, the sub-hiding and channel 39's shared damage
display had never once executed in this port.

**The mechanism.** game6's `exitFrame` (member 641) dives and surfaces each
submarine in a pair that is meant to cancel:

```lingo
if value(item i - 9 of allshipscounter) = 0 then
  ...dive:    set the locV of sprite 12 to the locV of sprite 12 + 122
  put 14 into item i - 9 of allshipscounter
  next repeat
end if
put value(item i - 9 of allshipscounter) - 1 into item i - 9 of allshipscounter
if value(item i - 9 of allshipscounter) = 1 then
  ...surface: set the locV of sprite 12 to the locV of sprite 12 - 122
```

`movecannon4`'s hit branch writes the **same counter** for a different purpose:

```lingo
put "hit2" into item i - 16 of allships
put 20 into item i - 16 of allshipscounter     -- no dive ran
```

So a hit arms the countdown from 20, it ticks to 1, and the *surface* half fires
alone -- `-122` for the big sub (sprite 12), `-164` for the two small ones
(sprites 10 and 11) -- with no matching `+122` before it. Each hit lifts that
submarine permanently. Two hits puts it off the top of a 480px stage.

**What is confirmed:** the precondition. Driving game6 through the real key path,
a landed shot leaves `allships = live,live,hit1` and `allshipscounter = 0,0,20`
-- the counter armed by a *hit* rather than by a dive, with the sub hidden
(`the visible of sprite 12` = 0, which is the hit branch's own doing).

**What is not confirmed:** the `-122` actually landing at the end of that
countdown. The probe watched 40 ticks and the counter needs ~20 `exitFrame`s to
reach 1. That is the next step and it is mechanical: extend the tick budget and
print `the locV of sprite 12` each frame across the whole countdown.

**The question that decides the fix, and it must be answered before any code
changes.** `allshipscounter` is doing double duty *in the movie's own script* --
dive timer and hit timer -- so the drift may be the original's own quirk, in
which case a faithful port reproduces it and the entry closes as "not ours".
Check against the original before touching anything: if real Director also lifts
the sub, this is not a bug in the engine. If it does not, something in the port
is letting the two uses of that counter share state they should not, and the fix
is engine-level -- **not** a patch to this game's script, per `AGENTS.md`.

Reproduce:

```
godot --headless --script tools/cannon_hit.gd -- --root piposh --label game6
# then watch `the locV of sprite 12` for 30+ ticks after the hit
```

Related: entry 43's fix is what made this reachable. `tools/cannon_hit.gd` still
drives `movecannon` through `call_handler` rather than the keyboard, so it proves
the Lingo and not the key path -- worth switching over while working here.

---

## 36. Every one of DAY1's nine talk clips is an inescapable two-frame loop when the movie was entered without `globalday`

**Status:** open · **Area:** movie entry / cold globals · **not the film loop and
not `play`/`play done`** · reported from play twice, as two different symptoms

Two reports, one fault:

| snapshot | click | parked on | what the player saw |
|---|---|---|---|
| DAY1 f2686 of 2783 | f959 ch18 `BehaviorScript 644` | 2685 ↔ 2686 (`tofclicktalk`) | "the mouth loop keeps going and never stops" |
| DAY1 f2614 of 2783 | f1562 ch18 `BehaviorScript 642` | 2613 ↔ 2614 (`dnzclicktalk`) | "my click makes my character disappear" |

**The mechanism.** DAY1's tail holds nine `<character>clicktalk` clips, from
`bonclicktalk` to `hezfldclicktalk`, ending at the last frame 2783. Each is one
preamble frame followed by a `soundBusy` loop whose body is `BehaviorScript 250`:

```
on exitFrame
  if not soundBusy(1) then
    go(marker(0))
  end if
end
```

Its only exit is the preamble frame having started a sound. That frame —
`BehaviorScript 291` for `tofclicktalk`, `281` for `dnzclicktalk`, and one for
each of the rest — looks its line up in the `master` cast's `clickoncharacter`
field by the key `usfulobject = "tofday" & globalday`. With `globalday` VOID the
key is `"tofday"`, no line of the field matches, `r` stays `"not"`, and the
handler falls out without reaching `sound playFile`. So `soundBusy(1)` is never
true, `250` bounces the playhead back to the marker every step, the preamble runs
and does nothing every step, and the two frames trade places until the player
quits.

**Both symptoms follow from the park, and neither is a second bug.** The mouth
keeps moving because a film loop advances on the *movie's* clock and not the
playhead's — deliberate, `film_loop_view.gd:draw`, and the reason a character can
keep talking while the score holds still. Traced at `tofclicktalk`, channels 18
and 20 hold `atofspk1`/`btofspk1`; at `dnzclicktalk`, `adnzlop1`/`bdnzlop1`. The
character disappears in the second case and not the first because the *score*
differs: DAY1 f2686 carries a channel 30 (`standright9`), and f2613 carries no
channel 30 at all. The clip's own restore —
`set the memberNum of sprite 30 to the number of member ("standleft" & syz)`,
then `go(lastmark)` — is on the exit path that is never reached.

**Ruled out, with the trace rather than by argument.** `_play_stack` is empty for
the whole park *and no `play` is executed on this path at all*. DAY1's tail is
two different mechanisms and only one of them is `play`: the `*mov*` segments
(`chocomov` 2739, `fuelmov` 2756, and the last frame 2783) are entered by
`play frame who` and end on `play done`, which is `docs/bugs-closed.md` 32's
subject; the nine `clicktalk` clips are entered by `go("<char>clicktalk")` from
the sprite behaviour and end on `go(lastmark)`. Both of the reports here are in
the second half. The `play frame who` inside `291`/`281` is on the
`who contains "mov"` branch, which is downstream of the field lookup that failed,
so it is never reached either. The clock names no hold for a single tick of it —
`hold_reason()` is `""` throughout, so it is not a tempo delay, a transition, a
wait-for-click or a wait-for-sound, and `sound.gd:pump` has nothing to release.
`Scripts.for_frame` resolves correctly: 250 and 291 are the scripts that run.
The engine is reproducing the movie faithfully; Director parks here too.

**`globalday` is VOID exactly when DAY1 was not entered through `EXODUS`.**
`EXODUS/master/BehaviorScript 46` sets `globalday = 1`; DAY1's own
`BehaviorScript 56 - init all` reads it and never writes it, and its
`if globalday = 1` block is where `meetings` and `soundspath` come from. So the
F12 container picker, `--file`, and F6 warp all open DAY1 into a state where
every character in the game is a trap. This is the player-visible half of
entry 25 and of `tools/boot_state.gd`'s standing red check "every global the next
room reads is set" — the safety net was already on the floor, reporting the
cause, and nothing connected it to the symptom.

Reproduce, and the one-line proof of the cause:

```bash
# parks: 2685 <-> 2686 for ever, no sound, no hold
godot --headless --path . --script tools/playhead_escape.gd -- --cold
# passes: the same click through the boot chain plays the clip and returns
godot --headless --path . --script tools/playhead_escape.gd
```

**What to change.** Not the clip, not the loop and not the film loop. The engine
may not invent a movie's globals — Director does not, and entry 25 records that
seeding `init all` on a cold entry was tried and broke nine green checks. The
decision is the one entry 25 leaves open, now with a second, worse consequence
attached: a debug entry point that drops the player into a hub mid-game either
routes through the chain that establishes the day, or says that it has not.

### Correction: everything above was measured on a cold entry, and only there

The heading and the `--cold` reproduction stand. The sentence **"every character
in the game is a trap"** does not, and neither does any reading of this entry
that expects the trap in normal play. Driven through the real chain — the same
click, the same clip, `EXODUS -> DAY1` and `EXODUS -> MURDER1 -> DAY1` — every
one of them *works*, and here is a clip finishing:

```
== click 1 at f965                          usfultalking=null usfulline=null
   -> f2685                                 (tofclicktalk)
  t85   f2685  busy=false                   usfultalking=1
  t87   f2686  busy=true  days\d1prom1.aif  usfultalking=2 usfulline=17
  t138  f2685  busy=false days\d1prom1.aif  usfultalking=2
  t139  f2686  busy=true  days\d1prom2.aif  usfultalking=3
  t173  f2685  busy=false days\d1prom2.aif  usfultalking=3
  t174  LEFT the clip at f942               (veranda)
```

`globalday` is 1 the whole way, the key is `tofday1`, and line 17 of
`clickoncharacter` is `tofday1,0,pip,tofspk1`. Measured the same way at `field`
(rin, `a1prom1`), `edge1` (mog, `mogday12`) and `exitforest3` (dnz, `j1prom1`
through `j1prom6`, seven passes): all four exit to their `lastmark`.

**Two things this entry made it easy to believe, and both are wrong.**

**`tofspk1` is not a sound file, and no engine ever asks for one.** The third
item of a talk-order line is a *cast member name*: `BehaviorScript 291` line 74
is `set the memberNum of sprite rin to the number of member (xxx & who) of
castLib "wonder"`, with `xxx` "a" or "b" — so `tofspk1` becomes `atofspk1` /
`btofspk1`, the talking loop, which `docs/bugs-closed.md` 21 names from the other side. The
sound is a separate concatenation two branches earlier,
`soundspath & "d" & globalday & "prom" & usfultalking & ".aif"` and
`soundspath & "tofsay" & random(3) + vcv & ".aif"`. `find games/piposh2 -iname
"*tofspk*"` returning nothing is therefore not evidence of anything. The talk
order says *who animates*, not *what plays*.

**The loop is not open-ended.** Every branch of the preamble that plays a sound
also does `usfultalking = usfultalking + 1`, and the `else` arm exits as soon as
`the number of items in line usfulline - 2` is below it. So the clip terminates
after one pass per talk-order item *whatever the sounds do* — a `playFile` that
finds nothing simply makes it silent and quick. **The only way in is
`r = "not"`**: the day key absent from the table. Nothing else traps.

**Which leaves exactly two ways to get `r = "not"`, and the second is new.**

1. `globalday` VOID — the cold entry above, unchanged and still open.
2. **`hatday<n>` is not in the table for any day.** `clickoncharacter` holds 21
   lines, `bon`/`lil`/`dnz`/`mog`/`rin`/`tof`/`ish` × days 1–3, and no `hatday`
   line at all — while `BehaviorScript 289` (`lastmark = "tennis"`, clip
   `hatclicktalk` at 2649) keys on `"hatday" & globalday`. That trap needs no
   cold entry and no missing global; it is in the shipped data. **Not proved
   reachable**: at `tennis` the sprite is on channels 18 and 20 (both
   `ahatlop1` — `docs/bugs-closed.md` 21 again) and the click was not answered on the frame the
   harness clicks, so Hat's talk may simply be cut content that no behaviour
   dispatches to. Worth ten minutes with `tools/playhead_escape.gd --label
   tennis` before anyone chases the tof/dnz clips again.

**And there is a second family with the identical shape**, which this entry never
mentioned and which any detector has to cover too. Alongside the nine
`<char>clicktalk` clips there are six `<room>talk` clips — `fieldtalk` 2067,
`tennistalk` 2085, `edge1talk` 2103, `verandatalk` 2121, `exitforest3talk` 2139,
`dwarfs1talk`/`dwarfs2talk` — reached from `objecttalktime` (showing an object to
a character) rather than from a click, and driven by `talkproc init, fieldname,
lastmark` in `DAY1/wonder/MovieScript 248`. It is the same handler written once:
look `usfulobject` up in a `master` field, play, increment, and `go(lastmark)`
when the items run out. It reads a *different* field per character (`tof-ans`,
`hat-ans`, `pat-rin-ans`) and a different sound global (`objtlkpath`, the same
one segment short), and it has the same single trap condition — the key absent
from the table. Whatever answers this entry must answer both.

**Ruled out with measurement, so it does not get re-derived.** The sound path was
never the fault. `days\d1prom1.aif` resolves, plays, and holds `soundBusy(1)` for
about fifty score ticks. `soundspath` *is* one segment short —
`MASTER/External/MovieScript 130` builds it as `soundspathstart & "days" & "\"`
and `soundspathstart` is written only by `strtgame`'s CD-drive probe
(`ROOT/strtgame/BehaviorScript 110`), which no entry short of a full boot passes
through — but that is a **wrong-take** bug, not a hang, and it is fixed:
`autoload/audio_director.gd` now matches a request as a *tail* of a path on disc,
which takes this corpus from 315 ambiguous filenames to 0. `tools/sound_wait.gd`
covers it, together with the rule underneath this whole entry: a `playFile` that
cannot start must leave the channel **not busy**, or a `soundBusy` poll is a wait
for something that can never happen.

### Second correction: the two player reports were never this entry at all

The correction above proved the clips *finish* in normal play and then stopped,
leaving the two symptoms attributed to a park that the same measurement had just
ruled out. Four save states taken from real play — `saves/piposh2/tofi_bug.json`,
`shlomit_hezi_gone.json`, `shlomit_hezi_gone_2.json`, `dward_hezi_gone.json`, all
with `globalday = 1` and every lookup resolving — say what they actually were.
**One fault, in the puppet model, with nothing to do with `play`, the film loop,
`marker(n)`, the clock or the sound.** Fixed; see `preview/sprite_state.gd`.

Director has **two** kinds of puppet (`docs/DIRECTOR_ENGINE.md` §5.2, §5.3, §5.5)
and this port had one, so it was simultaneously too sticky and not sticky enough.

**"His mouth keeps moving even after everything is done playing."** Traced from
`tofi_bug.json`, clicking Tofi at (498,171): the clip runs correctly — Hezi's
line, then Tofi's, `usfultalking` 1→2→3 — and exits to `veranda` on tick 89,
exactly as it should. What was left behind is channel 18. `BehaviorScript 291`
does `set the memberNum of sprite rin to (xxx & who)`, which auto-puppets *that
one property*; the score's channel 18 is `atofspk1` inside the clip and
`atoflop1` at the veranda, so the write is released the moment the playhead
leaves. `sprite_state.gd:effective` exempted `membernum` from that release, so
Tofi went on standing in the veranda animating `btofspk1` — his talking loop —
for the rest of the movie. The film loop was doing exactly what it should with
the member it had been given, which is why every earlier reading of this looked
at `film_loop_view.gd` and found nothing wrong.

**"Hezi is disappearing during the animation, then appearing again."** All three
saves, one cause, and it is not three: the score of `lilout1` (2514-2522),
`lilclicktalk` (2595-2611) and `dnzclicktalk` (2613-2629) **carries no channel 30
on any of those frames**, and DAY1's `init all` does `puppetSprite(30, 1)`. In
Director a whole-sprite puppet is not reconciled from the score at all, so the
player stays put; this port drew from `_score.frame(_index).sprites`, so the
channel simply was not on the frame. The sentence above — "the clip's own restore
is on the exit path that is never reached" — is wrong twice over: the exit path
*is* reached, and the restore is not what puts Hezi back. `tofclicktalk` carries
a channel 30 and that is the whole reason the same fault was filed as two
unrelated bugs. It is also why "sound is playing well" was the decisive clue.

**A third fault, found on the way and fixed with them.** `director_preloader.gd`
walks 24 frames ahead of the playhead every step and was calling `_effective` on
those frames' records — a read that *mutates*, because the auto-puppet release is
recorded there. Any later frame holding a different member on a channel released
that channel's live puppet, so a member a script had just written survived
exactly one tick: measured on channel 18 at `tofclicktalk`, `atofspk1` ↔ the
script's write, alternating every step. `effective` now takes `peek`, which
answers the same question without recording, and the preloader asks that.

**What is still open here is the heading**, unchanged: a cold entry that skips
`EXODUS` leaves `globalday` VOID, `r` stays `"not"`, and the clip parks. So does
the `hatday<n>` gap in the shipped table, still unproved reachable. Neither was
what the player was reporting.

Covered by `tools/puppet_persists.gd` (`gate.sh puppet_persists`). It drives the
boot chain to two rooms, writes a state at each, reloads it into a *fresh*
preview and clicks: `exitforest3` into `dnzclicktalk`, where the score drops the
puppeted channel, and `veranda` into `tofclicktalk`, where it moves the
un-puppeted one. Each room prints which of the two halves it actually proved
rather than passing on the one it cannot see. The states are built rather than
committed — `saves/` is gitignored because a save carries the movie's own field
text — and going through one is also the only check that the puppet claim
survives `capture`/`restore`, since it lives *inside* `_overrides` and
`tools/save_state.gd` only asserts that `_overrides` itself is carried.

Reproduce either report from the user's own states, once they are re-taken on a
build that records the claim:

```bash
godot --path . -- --save saves/piposh2/tofi_bug.json          # click Tofi
godot --path . -- --save saves/piposh2/dward_hezi_gone.json   # click Dnz
```

**The four saves in the report predate the fix and will not show it.** They were
written before `puppetSprite` recorded anything a save could carry, so their
`_overrides` name no puppet at all and channel 30 still vanishes when they are
loaded. That is a property of those files, not of the engine; a state taken now
carries the claim, which is what `puppet_persists` asserts.

---

## 25. A cold F6 warp or save-editor Apply still drops the player into a hub with unset globals

**Status:** open decision, not a pending task · **Area:** dev tools / skip routing ·
the three skip doors are fixed, see `docs/bugs-closed.md` 25

DAY1's globals are seeded by `BehaviorScript 56 - init all` on **frame 1**:
`egozh = 600`, `egozv = 325`, `syz = 7`, `whatodo = "stand"`,
`nextroomdata = "000"`, `ifmovie = "0,0"`, and the inventory channels puppeted.
Enter a hub past frame 1 and none of it is set, so Piposh walks toward 0,0 and the
next room places him off-stage.

`F6` warp and the save editor's **Apply** both call `goto_movie(movie, label)`, so
from a cold boot they can still do exactly that. The workaround is to start a game
first and then warp, and both tools' docstrings already say they do not replay the
walk that would normally get you there.

Left open deliberately rather than filed as work. The two ways to close it are a
seeding path or a two-step "run the init region, then jump", and both add a
mechanism the original does not have. **Seeding was tried and is the wrong shape:**
running the hub's frame-1 handler on any cold entry broke 9 green checks, because
`init all` empties `objectsfield` and resets `meetings`, so it wipes whatever state
the caller had set up. Do not add an init-seeding path; route the entry through
frame 1 instead. The decision to make is whether these two dev tools should
auto-start a game, not how to seed.

---

## 28. The preview's cursor hotspot rule is unverified

**Status:** open, cosmetic · **Area:** preview renderer ·
found while fixing the preview's custom cursors

**This entry was filed with two halves and only one is still open.** The scale
half — the composed image handed to `Input.set_custom_mouse_cursor` at its native
16x16 while the stage around it drew at 1.5 — was fixed by `ff066de6` and is in
`docs/bugs-closed.md` under 19 and 28. What follows is the remainder.

`_cursor_image` takes the hotspot from the data member's
registration point and recentres it to (8,8) only when it falls outside the 16x16
crop, which is `docs/DIRECTOR_ENGINE.md` 7.3 rule 1. Rule 2 of the same section
says **Windows Director before D5 ignores custom hotspots entirely and always
uses (8,8)**. This game's containers are D4 and the original shipped on Windows,
so (8,8) may be right for every cursor here. Measured for MAP's pair: `able1` has
a registration point of (10,9), so the two rules differ by (2,1) — small enough
that nobody would notice it and large enough to make every click land off by a
couple of pixels from where the cursor points. Not resolved either way: deciding
it needs a source on what the original build did, not a preference.

---

## 30. Sprite colours that D7 stores as true RGB are read as palette indices

**Status:** open · **Area:** score decoder / renderer ·
found while measuring the sprite record byte by byte

Bits 0x10 and 0x20 of the sprite record's colour-code byte (offset 20) say that
the sprite's fore or back colour is a **true colour** carried in bytes 24-27 —
byte 2 and byte 3 being the red components, 24/26 the green and blue of the fore
colour, 25/27 of the back — rather than an index into the movie's palette. The
port reads bytes 2 and 3 as indices unconditionally, so those sprites take
whatever the palette happens to hold at that index.

Measured, on the corpora as they stand:

```
$ godot --headless --script tools/sprite_record_bytes.gd -- --all   # Piposh 2
  20         9    0x00:746048 0x01:7470 0x02:51929 0x03:2830 0x04:2149
                  0x05:4753 0x10:15 0x20:635 0x30:489
  24        20    0x00..0xff
  25        35    0x00..0xff
  26        16    0x00..0xff
  27        24    0x00..0xff
```

So **1,124 of Piposh 2's 816,318 records** carry the back-colour bit and **504**
the fore-colour bit, and bytes 24-27 genuinely vary. Piposh 1 sets neither bit
and leaves 24-27 zero across all 1,886,362 of its records, so it cannot be used
to check a fix.

It matters more than a wrong tint would suggest: the back colour is what
Background Transparent keys against (§2.1), so a record whose paper is an RGB
that the port resolves as index 255 keys out the wrong pixels entirely.

The reference is no help and no excuse. `frame.cpp:readSpriteDataD7` parses all
four bytes and `sprite.cpp:replaceFrom` copies them, and **nothing in ScummVM
ever reads them again** — the same shape as flip before §1.8 was implemented.

Not fixed here because it needs the colour to stop being an index all the way
through `director_ink.gd` and the texture cache key, and because the only corpus
that exercises it is the one this port already renders acceptably — which makes
it exactly the kind of change that wants its own before-and-after measurement.

---

## 38. Piposh 1 English "stuck on the logo" does not reproduce, and the CD-drive probe it points at was dead for a different reason

**Narrowed 2026-08-14.** The half of this entry that was a fix is a fix: the
`set the searchpath = […]` spelling compiles, and the 27 dead probe scripts run.
What is left is a player report that **does not reproduce and never has** — which
is not the same as fixed, and is why this stays here rather than moving to the
closed file. `piposh-en` still fails 14 of 9,422 scripts, but they are not
`strtgame.dir`'s probe frames; that residue is entry 39's. Nothing to do until
somebody reproduces it and captures the F3 report this entry asks for.

**Status:** open (the symptom), partly closed (what was found underneath) ·
**Area:** `games/piposh-en` boot, `strtgame.dir` · reported from play as "the
game gets stuck on the logo; pressing SKIP moves on to a disc message, and from
there the right-hand button reaches the main menu"

**The symptom does not reproduce on this commit**, headless or windowed. Boot
`piposh-en` and the playhead runs f0 → the CD probe at `option1` → f2 (the
guillotine logo) → f86 `oliver` → the intro comic → `mainscreen` at f608, and
idles on the menu. It takes **95 s** to get there, against **68 s** for the
Hebrew build of the same title, and both are authentic: the intro is a long
comic with music under it and the movie states 8 fps. A player who does not sit
through it reads that as stuck, and that is the most likely reading of the
report, but it is a reading and not a measurement.

```
godot --headless --path . --script tools/movie_churn.gd -- --root piposh-en --window-off --steps 600
```

**The other two thirds of the report are fully explained, and place the
reporter.** SKIP is the *preview's* affordance, not a button the movie has:
`skip_to_end` walked to the next marker (`docs/bugs-closed.md` 32 and 37;
SKIP no longer navigates at all). `strtgame.dir`'s
marker list ends with `option1`..`option26`, `maybondisk`, `inserta` and `cont`
— the CD-drive probe — and frame 1347 `inserta` renders as **"Please Insert CD
and click OK"** with `Quit` on the left and a yellow `Ooooooooooo K !` on the
right, whose script goes to `cont` and from there back to f2. So "SKIP → a disc
message → the right-hand button → the main menu" is SKIP walking into the probe
region, exactly as `docs/bugs-closed.md` 37 describes it doing on `rating`. It says the reporter
was on an early frame of `strtgame.dir`; it does not say why.

**What was found underneath, and is fixed.** Every one of those probe frames ran
a script that did not compile. `set the searchpath = [...]` — Director accepts
`=` where the parser demanded `to` — killed **27 of `strtgame.dir`'s 75
scripts**, which is the whole of `option1`..`option26`. A script that does not
compile is a handler that never runs and nothing at run time says so: the probe
frames fell through on the score's own step and the movie carried on with
`cdsavepath`, `soundspathstart`, `gWinDriveLetter` and `whichins` never set. The
Hebrew and Russian builds spell every `set` with `to`, so no amount of playing
the corpus this port was built on would have shown it.
`tools/script_compile_check.gd` is the harness that does, and it is what to run
first the next time a localisation misbehaves.

**What to capture if it still reproduces.** The F3 report on the stuck frame:
which movie, which frame, and what the clock says is holding it. Everything
above is consistent with the playhead being parked somewhere in f0-f5 or in the
probe region, and nothing measured here parks it in either.

---

## 39. One script in two roots still does not compile, and it may be malformed rather than unparsed

**Status:** open · **Area:** `lingo/compile/lingo_parser.gd` · found by
`tools/script_compile_check.gd`, which is why it is a number and not an
impression

**Re-measured 2026-08-14 at `02844f93`, after the two parser fixes that commit
carries. Four roots are green and the remainder is one script**, so the table and
the diagnosis below are both replaced rather than annotated:

| root | compiled | before the fix | before that |
|---|---|---|---|
| `piposh2` | **3,307 of 3,307** | 3,307 | 3,307 |
| `piposh` | **8,754 of 8,754** | 8,742 | 8,738 |
| `piposh-dream` | **1,746 of 1,746** | 1,746 | 1,725 |
| `rating` | **5,441 of 5,441** | 5,440 | 5,437 |
| `piposh-en` | 9,420 of 9,422 | 9,408 | 9,406 |
| `piposh-ru` | 9,724 of 9,726 | 9,712 | 9,710 |

The two defects that closed the rest were both in `end`-swallowing. A one-line
`if x then <stmt>` consumed a following `end if` that belonged to an enclosing
block, so the handler ran off the end of its own source and reported `expected
end` at the last line -- pointing nowhere near the cause, which is why the five
CLOCK SCRIPTs stayed undiagnosed through several passes. And `end` only swallowed
a trailing word when it matched the handler name, so `on idle / ClockScript1 /
end if` was dropped. Both are in `02844f93`; the visible consequence was Piposh
1's in-game clock never advancing, which had been reported as an Android bug.

The recovered Itamar corpora move with them: `magichat.dir` is 124 of 124, and
what is left there is `hats.dir` 111 of 112 and `torfim.dir` 64 of 65, neither
re-read since the numbers moved.

**What remains is one script, in two roots, and it may not be a parser bug at
all.** `Texts.cst CastScript 98 - day4doc2` in `piposh-en` and `piposh-ru`, "line
5: expected end", counted twice in each because the cast is reached twice. It is
an `on mouseUp` with **no `end` at all** -- the member's source stops after
`go to frame "doc1b"`. So the question is not how to parse it but whether
Director closes an unterminated final handler at EOF, and nobody has measured
that. Guessing either way silently changes what every malformed script in the
corpus does, so it stays open until it is answered from the reference.

The Hebrew build is unaffected. The cost of the remaining two is that one click
in the day-4 doctor dialogue is dead in both localisations.

```
godot --headless --path . --script tools/script_compile_check.gd -- --root piposh-en --verbose
```

---

## 48. Hezi is drawn in front of the foreground layer that hides him, and the original does this too

**Status:** **not a bug — measured, and closed as authentic.** Written down so it
is not reported a third time. · **Area:** whole-sprite puppets vs. score
occupancy · reported from play against `saves/piposh2/shlomit_hezi_gone.json`
with "it might be from the original but i really don't think so"

**The report.** In `dwarfs` the player character stands behind a foreground
layer that covers him from the knee down. Click through to the clip and he is
drawn in front of it instead.

**What the score holds.** In the room (DAY1 frames 1485-1487) channel 30 carries
Hezi (`1:30 standleft9`) and channel 31 carries a 613x158 foreground band
(`4:99`, rect `0,243 613x158`). 31 is the higher channel, so it paints over him.
At the clip the playhead reaches — 2514 onward — **both records are zero**:
`type=0 0:0 0x0` on each, which is `kInactiveSprite` and an empty member. So the
movie did not merely stop mentioning those channels, it **wrote them empty** —
the score is a delta stream, `director_score.gd:writes_between` is what says
which frame wrote what, and both channels are written to zero on the way in.

DAY1's `init all` does `puppetSprite` on `[93, 30, 23, 15, 33, 6, 100, 17,
103-110]`. **31 is not in that list.** So the clear reaches channel 31 and is
blocked on channel 30, and the layer goes while Hezi stays.

**The engine is right, and this is which function says so.** The question is
whether Director skips the *whole* channel update for a puppet — leaving what it
held, drawn — or only the property copy, with occupancy still following the
score. It is the whole update, along a chain with no branch in it:

- `Score::updateSprites` is the only thing that reconciles a live channel from
  the score, and it has **no clear path**: the single write is
  `channel->setClean(nextSprite)`, where `nextSprite` is the frame's decoded
  record and "empty" is expressed as a zero member inside it.
- `Channel::setClean` takes the `_sprite->_puppet || _sprite->_autoPuppet` branch
  and copies **only** the script id. `replaceSprite` is not called.
- `Sprite::replaceFrom` returns immediately while `_puppet` is set, after copying
  the script id, the behaviours and the sprite-list index.
- Occupancy lives in the *live* sprite's `_spriteType`/`_castId`, and the only
  code that ever changes them is inside the region `_puppet` returns before.
  `Channel::isEmpty()` — the render loop's own test — reads `_spriteType` off
  that live sprite, never off the frame record.

So a clear cannot reach a puppeted channel, in the reference or in Director. The
rule is applied identically to all 48 channels here; **the asymmetry is the
movie's**, and 1997 drew this frame the same way. `tools/puppet_persists.gd`
holds both halves of it at `exitforest3`: the score drops `[30]` and keeps it,
and `[2, 8, 9, 12, 13, 15, 31]` go with the score.

**What would make this a real report.** Not "he is in front of the tree" — that
follows from the data. It would have to be that the *clip* is not the frame the
game means to be on, i.e. that the click should never have got there. Nothing in
the trace suggests that: the clip runs, plays its line and returns.

Reproduce, and read the line beginning "the score dropped", which prints both
halves side by side:

```bash
godot --headless --path . --script tools/puppet_persists.gd -- \
    --root piposh2 --label exitforest3
```

That check is in `gate.sh` deliberately. A survey nobody runs rots, and "an
un-puppeted channel the score dropped is gone" is the invariant that would break
first if somebody tried to answer this report by making the puppet carry more.

---

## 49. The port's "is this channel occupied" test is not the reference's, and nobody has measured where they disagree

**Status:** open, **unmeasured** · **Area:** `director/director_score.gd:_snapshot`
· found while answering entry 48, not the cause of it

**Narrowed 2026-08-14 by 94's fix.** The size half of the divergence is gone:
`_snapshot`'s test is now `cast_id <= 0` alone, so "a record with a live sprite
type, a member and a zero rect" — the case that cost Itamar Park its arcade — is a
sprite here as it is in the reference. What is left is the one real disagreement,
and it is narrower and easier to survey than when this was filed: the port asks
about the **cast id** and `Channel::isEmpty()` asks about the **sprite-type byte**
at offset 0. The two still differ on a record with a type of 0 and a nonzero
member. The survey below is still unwritten.

The paragraph that follows is as filed, and its first sentence is now history:

`_snapshot` treats a channel as occupied when `cast_id > 0 and width > 0 and
height > 0`, with a comment recording why: hundreds of thousands of records carry
a sprite-type byte and no member.

The reference asks a different question. `Channel::isEmpty()` is
`_spriteType == kInactiveSprite` — offset 0 of the record, and *only* that byte —
and it is what the render loop tests (`Window`'s two `!channel->isEmpty()`
guards). A record with a live sprite type, a member and a zero rect is a sprite
there and is not one here; a record with a type of 0 and a nonzero member is the
reverse.

**Not the cause of entry 48**, and that is measured rather than assumed: at DAY1
2510-2520 the two channels in question read `type=0 0:0 0x0`, so both tests agree
that they are empty and the answer there does not turn on this.

It is worth measuring before it is worth changing, because the port's test was
chosen against the corpus and the reference's was not. The survey nobody has
written: across all six titles, count the records where the two disagree, split by
which way. A count near zero closes this; a large one in either direction means
some channel somewhere is drawn that should not be, or the reverse, and neither
would look like a decode bug from the player's chair.

---

## 59. A Lingo runtime error survives only until the next dispatch, so nothing can observe one during play

**Status:** open · **Area:** `lingo/lingo_interpreter.gd`

`LingoInterpreter._fail` is where every runtime fault the interpreter can name
lands: "step budget exhausted", "repeat while did not terminate", "handler
recursion too deep at X", "unknown statement", "cannot assign to X". They go into
`errors`, a `PackedStringArray` capped at 50.

`reset_steps()` clears it, and `reset_steps` is called at the **start of every
dispatch** — `preview/scripts.gd:dispatch`, `preview/event_chain.gd:run` and the
thaw. One score step dispatches `idle`, `exitFrame`, `prepareFrame` and
`enterFrame` back to back, all inside one process frame, so an error raised in
any of them but the last is gone before anything outside the interpreter can read
it. The only reader in the whole port is `preview/debug_report.gd`, which prints
whatever happens to be there when the report key is pressed.

So the port has no way to answer "did any script fault while that room ran". A
handler cut off half-way by the step budget leaves the room in a state nobody can
attribute later, which is the same class of failure as a harness that reads null
and reports zero.

`tools/liveness_sweep.gd` polls `errors` once per process frame and accumulates
what it finds, which is the best that can be done from outside: a `lingo` finding
from it is real, and **a clean sweep is not evidence that nothing faulted.**

The fix is a sink that outlives a dispatch — the shape `LingoDiagnostics` already
has for unbound names, which deliberately survives `reset_steps` and accumulates
over a session. `errors` wants the same treatment, or a counter beside it, so
that "42 runtime faults this session" is a number a harness can assert on.

**Narrowed 2026-08-14: half of that sink exists.** `reset_steps` now calls
`_drain_errors()` before `errors.clear()`, and `_drain_errors` prints each *unique*
message once per session against a `_reported` dictionary that survives the
dispatch. So a fault two dispatches ago is no longer silent — it is in the run's
output. What is still missing is the assertable half: nothing counts them, so a
harness cannot say "this room ran clean" and `tools/liveness_sweep.gd` is still
polling `errors` once a process frame and still cannot promise it caught them all.

**Reproduce:** read `lingo/lingo_interpreter.gd:698-708` (`reset_steps`) beside
`:1634` (`_fail`) and `scenes/preview/scripts.gd:75`. Then run any movie and note
that no tool in `tools/` can report a fault that happened two dispatches ago.

---

## 60. A tempo delay on a self-holding frame is armed once; the reference re-arms it on every step

**Status:** open · **Area:** `scenes/preview/frame_loop.gd:sync_frame_entry`, `director/director_frame_clock.gd:enter_frame`, `score.cpp:640-712`

`Score::update` calls `updateCurrentFrame()` and then `updateNextFrameTime()`
**every update cycle**, not only when the frame number changes. A room holding
itself with `go to the frame` sets `_nextFrame` to the frame it is already on, so
`updateCurrentFrame` takes its else-arm and does nothing -- and
`updateNextFrameTime` still runs, reads the same tempo cell, and re-arms the same
delay. A frame carrying a two-second delay and holding itself therefore steps
once every two seconds, for ever, in Director.

This port arms the tempo on a genuine frame *change* only: `sync_frame_entry`
returns early when `_index == _entered_index`, so the delay is armed once, runs
out, and the room then steps at the movie's frame rate -- 15 or 8 times a second
against Director's once every two seconds. The frames are there: Piposh 2 carries
36 delay frames totalling 74.0 s and 23 of them carry a frame script; *Rating*
carries 160 totalling 439.0 s.

The early return is deliberate and its comment says why -- "re-arming a two-second
delay from there would hold it for ever rather than for two seconds" -- and that
reasoning is wrong in a way worth recording: re-arming does not hold the frame for
ever, it *re-delays* it, which is exactly the behaviour above. What the comment
describes would only happen if the delay were re-armed without the playhead ever
being allowed to step, which is not what the reference does.

Not changed here because it is not a one-line move. Arming the tempo per step
means the transition must **not** move with it (a wipe re-armed every step never
finishes), so the two would have to be split out of `sync_frame_entry`, and
`enter_frame` would have to become idempotent for the click and sound waits or a
frame released by a click would re-arm its own wait on the next step. That is a
change to the tick's shape and wants measuring against `idle_clock`,
`pause_holds`, `playhead_escape` and `frame_events` together.

**Reproduce:** read `reference/scummvm/score.cpp:640-712` beside
`scenes/preview/frame_loop.gd:sync_frame_entry`. For the exposure,
`godot --headless --path . --script tools/transition_survey.gd -- --root piposh2`
prints the delay frames and their total.

---

## 61. The click that releases a wait-for-click is delivered to the movie as well; the reference consumes it

**Status:** open · **Area:** `scenes/director_preview.gd:route_press`, `scenes/preview/interaction.gd`, `events.cpp:250-262`

`Movie::processEvent` handles the mouse-down in one `if`/`else`:

```
if (sc->_waitForClick) { sc->_waitForClick = false; sc->renderCursor(pos, true); }
else                   { ...latch the press, build the chain, dispatch mouseDown... }
```

So on a wait-for-click frame the press does one thing and one thing only: it ends
the wait. No `mouseDown` is dispatched, `the clickOn` is not rewritten, no drag
starts, and no sprite is hilited. This port releases the wait in `route_press` and
then carries straight on into `latch_press` and the mouse-down chain, so the click
that ends the wait is also a click on whatever sprite was under it.

Piposh 2 has 24 wait-for-click frames and *Rating* has 214, so the divergence is
reachable; whether it is *visible* depends on whether those frames also carry a
clickable sprite, which is not measured here.

Not changed here because it is a change to the input path rather than to the
clock, and it inverts the order two other rules depend on: §15's latch block is
documented as running for either button and on every press, and
`preview/interaction.gd` is where that decision lives.

**Reproduce:** read `reference/scummvm/events.cpp:250-262` beside
`scenes/director_preview.gd:route_press`.

---

## 62. A wait-for-click frame shows no alternating cursor, so a waiting movie looks like a stopped one

**Status:** open · **Area:** `scenes/preview/cursor.gd`, `director/director_frame_clock.gd:waiting_click`, `score.cpp:400-424` and `:1444-1458`

§9.2: while `_waitForClick` is set, `Score::isWaitingForNextFrame` flips
`_waitForClickCursor` once a second and re-renders the cursor, and
`Score::renderCursor` returns the built-in mouse-up or mouse-down arrow for that
flag *before* it consults any sprite. It is the only feedback a wait-for-click
frame gives, and without it the movie is indistinguishable from one that has
hung -- which is what a player sees on 24 frames of Piposh 2 and 214 of *Rating*.

The clock half is there: `FrameClock.waiting_click()` answers the question and was
added for this. What is missing is the cursor path taking it, with the 1000 ms
alternation and the precedence over the sprite cursor (§7.4).

**Reproduce:** read `reference/scummvm/score.cpp:400-424` and `:1444-1458` beside
`scenes/preview/cursor.gd`.

---

## 68. Three sounds Rating asks for are not in the shipped tree, so the arcade, the Bonds game and the break-in open silent

**Status:** open, data · **Area:** `games/rating/SOUNDS/` · found by
`tools/qa_walk.gd --sweep` over all 81 movies

`AudioDirector._fail` logs `Audio miss` at `warn` and nothing collects it, which
`autoload/audio_director.gd:167` says in as many words -- "the movies asking for
it got `Audio miss: dream2\1` in a log nobody reads". Sweeping the corpus with
the warnings collected, Rating asks for three files it does not ship:

| request | folder that resolved | what is in it |
|---|---|---|
| `sounds\arcade1\startmus.aif` | `SOUNDS/ARCADE1/` | 20 files incl. `GAMEMUS.AIF`, no `STARTMUS` |
| `sounds\bonds\midgame.aif` | `SOUNDS/BONDS/` | 22 files incl. `BONDMUS.AIF`, no `MIDGAME` |
| `sounds\brakein\brakemus.aif` | `SOUNDS/BRAKEIN/` | 23 files incl. `BRAKEIN.AIF`, no `BRAKEMUS` |

**The folder resolved and the file is not in it**, which is what separates this
from a resolver bug: the sibling files in each of those three directories load
and play. No `.aif` anywhere under `games/rating` carries any of the three
basenames, in any case, so they are absent from the tree rather than missed by
the search path.

**One name is not as absent as this entry first said**, and the correction is
the interesting part. `find games/rating -iname "*midgame*"` does not return
nothing: it returns `MIDGAME.dir` and a whole `SOUNDS/MIDGAME/` directory of
nine `.aif` files. Neither is a file named `MIDGAME.AIF`, so the conclusion
stands, but a request for `sounds\bonds\midgame.aif` sitting next to a
`SOUNDS/MIDGAME/` folder is worth one look at whether the movie meant a folder
before this is written off as missing data.

Same class as entry 46 (`games/piposh` shipping no `PIPDATA/FX` tree at all) and
the `piposh-ru` note beside it: a gap in the data this repository was given, not
a fault in the engine reading it.

**What no data here proves:** whether the original CD shipped these three. There
is one copy of Rating under `games/`, so unlike Piposh there is no second
localisation to difference against, and that is the measurement that would settle
it.

Reproduce:

```
godot --headless --path . --script tools/qa_walk.gd -- --root rating --sweep --ticks 150
```

---

## 70. `MAINMENU-old.dir` parks blank at `option1`, and nothing in Rating can reach it

**Status:** not a bug, recorded so the next sweep does not chase it ·
**Area:** `games/rating/MAINMENU-old.dir`

`tools/qa_walk.gd --sweep` reports one stage that stays empty once transient
opening frames are excluded: `MAINMENU-old.dir` frame 651-652, inside marker
`option1`, nothing drawn and no hold to explain it, for as long as it is watched.

It is unreachable. Rating boots `MAINMENU.dir`; a byte search for the string
`mainmenu-old` over every `.dir` and `.cst` in `games/rating` -- the Lingo source
lives in the `CASt` records, so a `go to movie` naming it would be found -- has
**no hits**. Nothing navigates to this container, and `DirectorPaths.containers()`
only lists it because it is a file in the folder.

So it is authoring residue shipped beside the movie that replaced it, and its
dead region is not a state a player can be in.

**Why this is written down rather than dropped:** `AGENTS.md` requires more
evidence for "not a bug" than for a bug, because it is the verdict that stops
work -- and this one will be re-reported by every future `--sweep` of Rating.
Without the entry the next session re-runs the same investigation.

Reproduce:

```
godot --headless --path . --script tools/qa_walk.gd -- --root rating --sweep --ticks 150
for f in games/rating/*.dir games/rating/*.cst; do LC_ALL=C grep -qai "mainmenu-old" "$f" && echo "$f"; done
```

---

## 80. An expanding field still clips, because no path pushes its laid-out height back onto the sprite

**Status:** open, and it is the **remaining half** of `DIRECTOR_ENGINE.md` §1.2 ·
**Area:** `scenes/preview/sprite_geometry.gd:_field_size`,
`director/director_text.gd:152`, `scenes/preview/text_art.gd:paint` · found
verifying monday 12752286416

`castmember/text.cpp:createWidget` sizes a field's widget from the score's rect —
`sprite.cpp:627-632` skips `kCastText` when it resets a sprite's dimensions, so
that rect survives as the bbox — and then `channel.cpp:774-779` writes the widget's
size back onto the sprite. Three box types, three rules:

```
adjust(0)           MIN(bbox, initialRect), then the widget may expand
fixed(2)/scroll(1)  MAX(bbox, MAX(initialRect, maxHeight)), never expands
limit(3)            bbox unchanged, then the widget may expand
```

**The fixed and scrolling arm is implemented** (this entry's commit); the two arms
that expand are not, because the port has nowhere to push a laid-out height back
to. `director_text.gd:152` returns on the first line whose top reaches the box
bottom, so overflow clips, and `text_art.paint` draws into the rect it is handed
without reporting what it laid out.

**The two halves cannot land separately, and that is the finding.** `createWidget`'s
own comment is "for mactext, we can expand now, but we can't shrink", and
`createWindowOrWidget` hands it a `maxWidth` of the member's width plus borders to
expand into — so the MIN is a *starting* size, not an answer. Implementing it alone
clamps every expanding field to whatever the score last left on the channel:
measured over `piposh`, **5,677 of 12,622 `adjust` records would draw smaller than
they do today**, and the clearest one is `GlobalMoney`, the 102x19 member every room
records as 68x32 residue — which is exactly the regression `9d1b23d2` fixed.

What is actually lost today: **16 sprite records over two members**, `save2`
(`limit`, where the line dropped is a trailing empty one) and `memo21`. So the
player-visible cost is small; the reason to do it is that `text_focus.gd` now makes
fields editable, and typing past the box in `CAPROOM.dir`'s `memowrite` (`fixed`,
277x85) clips with no growth. **Unverified:** no probe measures text Lingo writes at
runtime.

The vehicle would need to be a new one. `size_from_script`
(`scenes/preview/channel.gd:429`) is the only existing path that makes a size stick,
and it means "a script resized this" — a field growing because its text got longer
is a different cause and conflating them would make `drawn_size` unable to tell them
apart.

Reproduce:

```
godot --headless --path . --script tools/text_and_shapes.gd -- --root piposh --file PIPDATA/CAPROOM.dir
godot --headless --path . --script tools/text_and_shapes.gd -- --root piposh --file PIPDATA/MAINMENU.dir
```

`memowrite` reports `1 lines, 14pt, box (7,383) 277x85`; a `save2` box reads 19px
tall against a member whose stored `text_height` is 38.

---

## 75. Three field references name a cast library their movie does not have, and the port answers them where the reference would not

**Status:** open, **deliberate**, and the deviation is at the call site ·
**Area:** `scenes/director_preview.gd:_resolve_field`,
`scenes/preview/members.gd:library_named` · found while closing
`docs/bugs-closed.md` 53/35

`Movie::getCastLibIDByName` is an exact case-insensitive match against the names a
movie's `MCsL` gave its libraries and answers -1 for anything else
(`reference/scummvm/movie.cpp:692-699`); `getCastMemberIDByNameAndType` then warns
`Unknown castLib` and finds nothing. This port instead falls back to the
unqualified walk when the clause names no library that exists.

Three references in the corpus land on that path, and they are the reason it is
there. Measured with
`godot --headless --path . --script tools/field_designator.gd -- --root <r> --survey`:

| root | reference | the movie's own libraries |
|---|---|---|
| piposh, piposh-en, piposh-ru | `mainmenu.dir`: `field "globalmoney" of castLib "master.cst"` | `Internal`, `master` |
| piposh, piposh-en, piposh-ru | `mainmenu.dir`: `field "afganifield" of castLib "master.cst"` | `Internal`, `master` |
| piposh-dream (10 movies) | `field "timebasebackup" of castLib "panel.cst"` | no `panel.cst` loaded |

Both spellings of the same file are in use across Piposh 1 — the corpus names its
linked casts `master` and `master.cst`, `zoom1` and `zoom1.cst`, `pirats` and
`pirats.cst`, per movie — so the author's one spelling matches in some rooms and
not in others. Following the reference exactly would blank the money on Piposh 1's
slot machine, a field the original draws, so the walk is kept and written down
rather than taken silently.

**What would settle it**, in order of what it would cost: read the `MCsL` name and
path of every library of every movie in Piposh 1 and see whether the *path*
basename is what the script is spelling (in which case Director may match on the
file and this port should too, which would be a fix rather than a deviation); or
run the original under a Director projector and watch that field.

The `piposh-dream` ten are a different case wearing the same clothes: neither
resolution finds `timebasebackup` there, qualified or not, so those ten reads
answer `""` today and would answer `""` under the reference. `checkroom` reads
`line TIMEKEEPER of field "timebasebackup"` to decide where the player is sent,
which makes this worth its own look — it is filed here because the survey found
it and not because it has been traced.

---

## 76. `field("x").prop` — the dot spelling of a field property — resolves a member named after the field's *text*

**Status:** open, unexercised · **Area:** `lingo/lingo_interpreter.gd`'s `dot`
arms · found while closing `docs/bugs-closed.md` 53/35, and **not** fixed with it

The designator spelling `the <prop> of field "x"` now reaches
`get_field_prop`/`set_field_prop`. The dot spelling does not: `_eval`'s `dot` arm
tests the owner node for `sprite_ref` and `member_ref` and has no `field` case, so
`field("x").textSize` evaluates the owner — which yields the field's **text** —
and then asks `get_member_prop` for a member of that name. `field("x").text = y`
takes the same route through `_assign`.

0 sites in any of the six titles use it, which is why it is filed rather than
fixed in the same change: the fix is one more arm beside the two that are there,
and it wants the same harness case as the designator spelling
(`tools/field_designator.gd`) rather than a new file.

---

## 74. Eight rows of Piposh 1's piano keyboard draw differently in the player and in `director_render.gd`

`docs/bugs-closed.md` 73 removed the diagnostic's own crude keying rule, and with
that gone the player and `tools/director_render.gd` agree on **0.30% of the stage
below the HUD** on `PIANO.dir` frame 37, and on **0.00%** of the book. What did
not close is the eight rows the original report was about: **y466-474, x8-259,
where 13.3% of the pixels still differ.** Stable across frames 37 and 39, so it is
not a frame mismatch.

This is the mottled line under the left half of the keyboard. Where they differ,
the renderer produces exact palette entries -- `(170,170,170)`, `(153,153,102)`,
`(102,102,102)` -- and the player produces values that are in the palette's gaps,
`(181,181,181)`, `(217,217,217)`, `(209,209,187)`. A value no palette entry holds
came from combining two, so **the player is blending where the renderer is not**,
and 0.3% of the sampled 2x blocks have two different columns inside one stage
pixel, which under nearest filtering at an exact 2.000 scale should be none.
Nearest is configured twice over -- `project.godot`
`textures/canvas_textures/default_texture_filter=0` and `boot.gd` setting
`TEXTURE_FILTER_NEAREST` on the host -- so the blend is coming from somewhere
those two do not cover. That is the thread to pull.

**What is already ruled out.** `key_matte` on member 2 (`noclid1`) is clean: 79.6%
opaque, border removed, interior paper correctly kept, so it is not a matte leak.
Dashing is genuinely *present in the inputs* -- member 2 has a solid dark row at
its own local y55, a part-toned row at y54 and a dashed row at y56 -- and the key
sprites overlap about 12px with each sitting one pixel lower going left, so some
of the appearance is authentic whatever this turns out to be. Which is why this is
still open rather than filed as authentic: an explanation of how it *could* be
authentic is not the evidence `AGENTS.md` wants for the verdict that stops work.

**Measuring this at all needs care, and getting it wrong cost a session.** A
window capture is only comparable at an *integer* stage scale, and the window size
that gives one is not the stage size: the stage takes 75% of the window's width,
so `--stage 854,640` yields 641x480, a fractional 1.0016, and comparing that
against a 640x480 render reports 38% of the stage differing -- all of it the
capture, none of it the renderer. `--stage 1707,1280` yields exactly 1280x960;
sample the top-left of each 2x2 block. Always check the content bounding box
first.

Reproduce:

```
godot --path . --script tools/scene_probe.gd -- --root piposh --movie PIANO.dir \
    --frame 37 --settle 2 --ticks 0 --hold --stage 1707,1280 --quiet --out /tmp/prev.png
godot --headless --path . --script tools/director_render.gd -- --root piposh \
    --file PIPDATA/PIANO.dir --frame 37 --out /tmp/rend.png
```

`/tmp/prev.png`'s stage sits at (213,160) at scale 2. The three rulings about this
room that *are* closed are `docs/bugs-closed.md` 72.

---

## 82. Cast type 15 (`kCastXtra`) members are skipped by the renderer entirely, and Magic Hat's `yes`/`no` buttons and its intro video are six of them

**Status:** open · **Area:** `director/director_cast.gd` (`TYPE_NAMES`,
`_parse_cast`), `scenes/preview/sprite_art.gd:texture_for` · found while reading
`test-games/itamar-magichat` for 79

**Narrowed 2026-08-14: the decode is done and the draw is not.** Two of the three
places below are fixed — `TYPE_NAMES` names 15 `xtra`, and `_parse_specific` has an
arm for it that reads the symbol and payload the way
`castmember/xtra.cpp:XtraCastMember()` does, with `_apply_xtra_rect` for the
geometry that is not in that block. **The third is unchanged and it is the one that
costs**: 15 is still absent from `DRAWING_TYPES`, so a type-15 sprite that draws
nothing is still not counted as missing art, and `sprite_art.gd:texture_for` still
returns null for anything that is not a bitmap or a shape. The 253 Flash and 206
animated-GIF members, the 94 `vectorShape` and the 11 `text` members still draw
nothing, and that is the whole of what is left here — the video half is settled and
84 is closed.

Type 15 is unknown to the cast layer in three separate places, and the third is
the one that hides the first two:

- `TYPE_NAMES` stops at 14, so the member's `type_name` comes back from the
  `"type%d"` fallback as `"type15"`.
- `_parse_cast` has no arm for it, so width, height and registration stay 0 —
  the same shape as 81.
- `DRAWING_TYPES` therefore does not contain it, so `"drawing"` is false. That
  flag is what the port uses to say "a sprite whose member is one of these and
  does not resolve is **missing art**", so the one check that would report a
  silently blank sprite is switched off for exactly the type that always is one.

`sprite_art.gd:texture_for` returns null for any type that is not bitmap or
shape. So a type-15 sprite draws nothing, is not counted as missing, and leaves
nothing on the clock.

**Six of them in `test-games/itamar-magichat`**, measured with
`tools/director_extract.gd` (`--root res://test-games/itamar-magichat --file
<cast> --out <dir>`, then `members.txt`):

```
same.cst    66  no
same.cst    67  yes
same.cst   178  IntroRetroVideo
album.cst  210  magicvideo
lng.cst    148  title1
lng.cst    149  title2
```

`no` and `yes` are the title's confirm and cancel buttons — two members a player
is meant to click, and this port cannot draw either.

**Six was a first-`CAS*` walk's answer and the real number is 566 across the
tree.** `tools/member_type_census.gd` counts `CASt` chunks rather than `CAS*`
slots and reports **454 type-15 members in `itamar-magichat` alone** — 412 of them
in a second cast library of `witch.dir` that a first-`CAS*` walk never opens —
plus 97 in `piposh-dream`, 7 in `itamar-park`, 4 in `piposh2` and 1 each in
`piposh`, `piposh-en`, `piposh-ru` and `rating`. So the type is not a Magic Hat
curiosity: it is 566 members over 677 containers, and this entry's "renderer skips
it entirely" applies to all of them.

What they *are* is five symbols, measured by `tools/xtra_members.gd` over all
eight roots:

```
flash                     253      animGif / animgif   206
vectorShape                94      text                 11
VisibleLightOnStageMedia    2
```

Only the last two members are video, and both are Magic Hat's. **The 253 Flash and
206 animated-GIF members are the bulk of what this entry costs**, and they are not
a decoder problem in the sense the paragraphs below describe — they are moving
pictures in formats a port could reasonably decode, and `itamar-magichat` scores
151 of them. The `yes`/`no` buttons, the 94 `vectorShape` members and the 11 `text`
members need no decoder at all.

**What it costs on the intro, end to end.** `magichat.dir`'s
`BehaviorScript 134 - video intro retro loop` is the movie's own handler for
"has the video finished":

```lingo
property prFrameStep
on exitFrame me
  ...
  if sprite(1).getplaybackevent <> 1 then
    QuitIntroRetro(1, 1)
  else
    go(the frame)
  end if
end
```

and `QuitIntroRetro` (movie script `game utils`) is `sprite(spr).stop()` followed
by `go(the frame + FrameStep)`. Sprite 1 holds `IntroRetroVideo`, an Xtra member;
`getPlaybackEvent` is an Xtra sprite method and is bound nowhere in this port
(`grep -rn "getPlaybackEvent" --include="*.gd" .` returns nothing), so it can
never answer 1 and the movie takes its own abort path **on every tick**, stepping
one frame at a time through the intro region rather than playing it. Nothing is
broken in that handler: it is the movie's own fallback working exactly as
authored, against a video that is not there. **Which frames it walks is a
separate question from whether it is reached at all** — see 79 for the boot path,
and re-measure that before quoting a frame range from it.

`docs/LINGO_SURFACE.md` already lists the two member properties Director gives an
Xtra member (`interface`, `mediaBusy`); neither is bound either. **Not the same
mechanism as 84** — an Xtra member is not a digital video, and the two fail
differently.

**Re-measured 2026-08-12, and the verdict on "can anything better be done" is
no, not in this engine today.** Three things were checked rather than reasoned:

- The abort path is not a hang. A windowed run reaches the main menu (frame 23)
  within a few seconds of boot, so the intro region is walked and left. `VOID <>
  1` is true, which is the arm that leaves; a binding that answered 1 would be
  strictly worse, because `go(the frame)` is the other arm and that one never
  ends.
- `IntroRetroVideo` and `magicvideo` are **MPEG-1 players**, not Flash or
  QuickTime. `init intro` sets
  `member("IntroRetroVideo").mediaFilename = the moviePath & Language() &
  "\mainmenu\intro.mpg"`, and the title ships
  `heb/album/magic1.mpg` ... `magic10.mpg` beside it.
- Godot 4.7 ships exactly one video decoder, Ogg Theora. There is no MPEG-1 path
  to bind `play()`/`getPlaybackEvent` to, so a faithful implementation of the
  Xtra surface would still show a black rectangle. Transcoding the title's own
  `.mpg` files is not an option: `games/` and `test-games/` are the owner's data
  and the engine reads the original containers.

So what is left here is a *decoder*, not a binding, and the binding is only worth
building once there is something behind it. The `yes`/`no` buttons in `same.cst`
are the separable half and do not need one.

### The video half is settled and the answer is written down — 2026-08-12

**`docs/DIGITAL_VIDEO.md` is the costed decision** and it supersedes the three
bullets above as the place to look. What it adds over them:

- **The census is complete.** `tools/video_census.gd` walks all eight corpora, all
  677 containers, and classifies every media file on disc by its own magic bytes.
  **Four members in the tree play video** — `logo.dir` #27 `prelogo` and #28 `logo`
  (type 10), `same.cst` #178 `IntroRetroVideo` and `album.cst` #210 `magicvideo`
  (`VisibleLightOnStageMedia`) — and all four are `itamar-magichat`'s. **The six
  shipped Piposh titles hold 0 video members, 0 video sprites and 0 bytes of video
  media**, so none of this costs them anything.
- **The two `.mpg` encodes match the two Xtra members' own rects exactly.**
  `IntroRetroVideo` is 352x288 and `heb/mainmenu/{intro,retro}.mpg` are 352x288 at
  25 fps; `magicvideo` is 320x240 and the twenty `heb/album/*.mpg` are 320x240 at
  25 fps. Two different parts of the container agreeing on the same pair of numbers
  is what turns "these members play those files" from a reading of the Lingo into a
  measurement.
- **A third site was missing from this entry.** Beside `sprite(1)`'s intro there is
  `BehaviorScript 38 - video loop` polling **`sprite(25).getPlaybackEvent`** for the
  **album**: `AlbumMenuObject.MenuMouseUp` sets `member("MagicVideo").mediaFilename`
  to `album\magic<page>.mpg` or `album\solution<page>.mpg` and jumps to the `video`
  marker. Twenty clips, ten pages × (magic, solution), and they are the album's
  actual content. Its fallback arm is `sprite(25).stop()` / `go(the frame + 1)` —
  a clean skip, like the intro's.
- **The reference does not implement this Xtra either.** ScummVM's
  `castmember/xtra.cpp:xtraCastMemberProtos` promotes exactly one symbol into a
  `DigitalVideoCastMember` and it is `quickTimeMedia`;
  `VisibleLightOnStageMedia` is not in the table, so it falls through to
  `CastMember::createWidget` returning `nullptr` (805f259a).
- **Nothing hangs, and that is now asserted rather than observed once.**
  `tools/video_fallback.gd` drives the playhead **onto** each of the three video
  frames — which is the only way to reach the intro, since `magichat.ini` in this
  tree says `startframe=mainmenu` and a normal boot never goes near it — and
  watches it leave. All three leave; all eight roots pass.

The rest of this entry — type 15 unknown to `TYPE_NAMES`, no arm in
`_parse_cast`, absent from `DRAWING_TYPES`, `texture_for` returning null — is
unchanged and is still the bug. **It is also the larger half**, because 459 of the
566 type-15 members are Flash and animated GIF rather than video, and those need no
MPEG decoder.

---

## 83. A sprite behaviour is dispatched as a plain script with `me = null`, so its `property` names have nowhere to live and the score's per-sprite initialiser is never applied

**Status:** open · **Area:** `lingo/lingo_interpreter.gd:_invoke` and its
`"property"` arm, `director/director_score.gd:_read_interval`

**Narrowed 2026-08-14: the `me` half is closed and the parameters half is not.**
`038b79a4` made a behaviour an instance for every message, so the premise of the
first half of this entry — "a behaviour this port reaches as a *script* rather than
as an instance" — is no longer true and a script-level `property` has an object to
live on. See 93, now closed. **Point 2 is untouched.** `initializerIndex` is read
by nothing in `director/`; `grep -rn 'initializerIndex\|getSpriteDetailsStream'`
finds only the docstring at `director_score.gd:911` saying so. `magichat.dir`'s
`BehaviorScript 135` still goes to VOID, because `prGotoFrame`'s value is in the
score's initialiser stream and nothing opens it.

The port says this about itself, in `_invoke`'s docstring: "`me` is the script
object the message was delivered to, or null for every other dispatch there is —
a frame script, a movie handler, **a behaviour this port reaches as a *script*
rather than as an instance**." The `property` statement arm then takes the
documented consequence, which its own comment calls "a divergence and it is
deliberate": with no `me` it declares a **global** instead of an instance
variable, because there is no object to hang one on.

That fallback covers a `property` written *inside a handler body*. Two things it
does not cover:

**1. A script-level `property` line is collected and then dropped.**
`lingo_parser.gd` gathers the declarations outside any handler into
`script["properties"]`, and the only reader of that key is
`lingo_object.gd:_init`, which seeds `props` for an object built by `new`. A
behaviour never becomes one, so the name is declared nowhere at all — not as an
instance variable, not as a global. `_read_var` then reaches its last arm, where
"an unknown bare identifier is a parameterless handler call in Lingo", and the
name is answered as an unbound builtin: the same failure shape
`docs/bugs-closed.md` 78 traces from `baReadIni`, arriving by a different route
and with nothing in the trace to say it was a property.

**2. The behaviour's authored parameters are decoded and never applied.**
`director_score.gd:_read_interval` says so: the behaviour element's second half
is `initializerIndex`, "an entry index holding the behaviour's authored
parameters", and "**Nothing reads the parameters yet**; a title that authors them
is what will need `getSpriteDetailsStream(initializerIndex)`". The same docstring
records why this has cost nothing so far — the index is 0 in all 14,903 elements
of Piposh 2 — which is a fact about Piposh 2 and not about Director.

**`itamar-magichat` is a title that authors them**, and it is the whole pattern in
one script (`BehaviorScript 135 - end video`):

```lingo
property prGotoFrame

on exitFrame me
  go(prGotoFrame)
end

on getPropertyDescriptionList
  description = [:]
  addProp(description, #prGotoFrame, [#default: EMPTY, #format: #string, #comment: "gotoFrame"])
  return description
end
```

`getPropertyDescriptionList` is Director's declaration of *which* parameters the
author is offered in the score, and the score is where the answer lives — e.g.
`[#prGotoFrame: "mainmenu"]`. The handler is one statement long and every bit of
what it does is in a value this port never reads, so `go(prGotoFrame)` goes to
VOID. `BehaviorScript 134` (see 82) is the same shape with `prFrameStep`.

Reproduce: extract `magichat.dir`'s scripts with `tools/director_extract.gd` and
read 134 and 135; the parameters they name are in the score's initialiser stream
and nothing in `director/` opens it.

---

## 88. `GetLng()` / `SetLng()` are absent game data in Magic Hat, not a cast that failed to load — nothing to fix in the engine

**Status:** not a bug, recorded so the next reader does not re-derive it ·
**Area:** none · found while fixing 87

`test-games/itamar-magichat` reports `builtins unbound : {"getlng":1}` on every
boot, and `lng.cst` sitting unopened in the folder is the obvious suspect. It is
not the cause, and the arithmetic that made it look like one — "only 4 of its 7
casts load" — is counting two different things.

**Every cast library the movie declares opens.** `magichat.dir`'s `MCsL` names
eight, and all eight resolve and index:

```
lib 1  Internal  (embedded)   135 members
lib 2  utils     utils.cst     51
lib 3  objects   objects.cst   23
lib 4  cards     cards.cst     98
lib 5  album     album.cst    935
lib 6  same      same.cst     195
lib 7  code      code.cst      22
lib 8  lng       lng.cst      211
```

`tools/director_containers.gd --root res://test-games/itamar-magichat` opens all
sixteen containers in the title, and its one FAIL is only that the tracked
config's `strtgame.dir` is not this title's boot movie.

**Four of the eight carry Lingo, and that is the "4 of 7".** `cards`, `album`,
`same` and `lng` hold no `Lscr` chunks at all — `lng.cst`'s 211 members are
tooltip *bitmaps* (`bmain1_tt`, `blogin1_tt`, `balbum1_tt` …), which is what a
localisation cast in this title is. So `lingo: 77 script(s) across 4 cast(s)` is
the complete and correct count, not a shortfall.

**`GetLng` is defined in none of the sixteen containers.** Extracted every one of
them with `tools/director_extract.gd` and searched the lot:

```
grep -rn 'on GetLng\|on SetLng' <every extracted scripts/ dir>   # no matches
grep -rn 'GetLng\|SetLng'       <the same>                        # one file
```

The one file is `magichat.dir` member 87, `LogInMenuObject`, which calls
`GetLng()` once in `on new` and `SetLng(prDefaultLng)` once on the way out. Both
are on the login screen and nowhere else. `utils.cst`'s `language` script has
`Language()` and `ChangeLanguage()`, which are the handlers the rest of the title
actually uses, so `GetLng`/`SetLng` are a third spelling with no implementation
behind them — supplied by an Xtra or by a shell movie that this copy of the title
does not carry, or simply left dangling by the authors.

Director would have raised "Handler not defined" at the same call. The engine's
`builtins unbound` line is therefore accurate reporting and not a port fault, and
there is nothing here to bind.

---

## 100. Piposh Dream's `doc` minigame ends before it throws anything, because a hit registers on the first pass against a channel its own init never claimed

**Status:** **not an engine bug — concluded 2026-08-14 from the reference**, and
kept here for the same reason as 48 and 70: it will be re-reported by every future
`--play` of that movie. · **Area:** `COMEIN.dir` script `1:193` versus
`1:147`/`1:181` · found by `tools/puppet_members.gd --play doc`

**The question this entry refused to answer without the reference has an answer,
and it kills the engine reading.** In ScummVM `the visible of sprite N` reads
`channel->_visible` (`lingo/lingo-the.cpp:1809`), which is a `Channel` field set
`true` in the constructor (`channel.cpp:63`) and written in exactly two other
places: the copy constructor (`:99`) and the Lingo setter (`lingo-the.cpp:2135`).
**No score path touches it** — neither `setClean` nor `replaceFrom` writes
`_visible`. So Director answers TRUE for a channel the score placed and no script
puppeted, which is what this port answers. The two readings below collapse to one:
`1:193` omits the `puppetSprite(3, 1)` and `sprite(3).visible = 0` that its five
siblings carry, and the original ends this minigame early too.

**Do not close it by citing `bugs.md` 34.** This entry cites 34's "open half" and
that citation is doubly wrong: 34 was already fixed when this was filed (08-08,
five days before), and 34 argues only the **empty**-channel case while channel 3
here is *occupied*. Those are different arms of `Channel.read`. The reference above
is what settles the occupied case, and it is the evidence `AGENTS.md` wants before
a "not a bug" verdict stops work.

**What would reopen it:** a measurement that the *click* should never have reached
`return2` in the first place, or a Director projector run of `COMEIN.dir` showing
`doc` playing to its end. Neither has been done.

`COMEIN.dir` holds one minigame per character and five of the six play. `doc`
(`return2`, f295) is entered correctly — walked into, not jumped to; its init runs,
`puppetSprite` is reached 8 times and `keyUpScript:dockeys` fires — and then channels
27, 28 and 29 are **never dressed** with `187`/`188`/`189` over 20,000 process
frames. Nothing is ever thrown.

The playhead says why. It walks f293..f308 and jumps straight to **f315 `y2`**, which
is the branch `1:195` takes only on

```lingo
((sprite(27).visible = 1) or (sprite(3).visible = 1)) and (sprite(5).visible = 1)
```

Channel 27 was never dressed, so the term that read true is `sprite(3)`: a hit
registers at `plantcounter = 7` on the very first pass and the scene leaves for
`docend` before a spear exists.

**Two anomalies sit under it, both unique to `1:193` among the six inits**, which is
what makes it a lead rather than a coincidence. It omits the `puppetSprite(3, 1)`,
`puppetSprite(4, 1)` and `sprite(3).visible = 0` that `1:147` (hat) and `1:181` (poz)
all carry — while its own handlers go on to dress channels 3 and 4 exactly as theirs
do — and it is the only one of the six written `on enterFrame` rather than
`on exitFrame`.

**Not concluded, on the rule that "not a bug" needs more evidence than a bug does,
which cuts the same way in reverse.** Two readings are live: an authoring slip in a
1997 container, or this port answering `the visible of sprite 3` where Director
answered otherwise for a channel no `puppetSprite` claimed. The score does place
member 187 on channel 3 from f295, so the sprite is *there* — but a score record
carries no visible bit at all (visibility is `preview/channel.gd`'s runtime concept),
so the score cannot settle it. Settling it needs the reference: what Director returns
for `the visible of sprite N` on a channel the score placed and no script puppeted.
`bugs.md` 34's open half is the same question from the other end.

Reproduce:

```
godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream --file COMEIN.dir --play doc
```

The survey's static half flags it mechanically without playing anything: `doc`'s line
reads `handlers also dress [3, 4], unclaimed`, uniquely among the six scenes. That
comparison of claimed-versus-dressed channels was added to keep a docstring honest
and surfaced this as a side effect, which is the argument for printing both numbers
rather than the one the tool was written for.

---

## 103. `start_lingo` clears the script casts but not the library keys, so a movie inherits the previous movie's cast-library names

**Status:** OPEN, no symptom measured · **Area:** `scenes/preview/boot.gd:start_lingo`
· found while tracing entry 102's cast resolution

`boot.gd:start_lingo` clears `_script_casts` (`:282`) and does not clear
`_lib_keys` (`:321`). So entering `eat.dir` from `dinner1.dir` leaves
`{2: "DINNER1/doc", 3: "DINNER1/hezi", 5, 7, 8, 10, 13: …}` alive under a movie
whose only library is 1. A script naming `castLib 7` there would resolve into the
movie the playhead has left.

**The evidence that this is real rather than theoretical is that two harnesses work
around it**: `tools/click_eligibility.gd:127` and `tools/click_chain.gd:469` both
call `_lib_keys.clear()` themselves before measuring. A tool clearing engine state
by hand is a statement that the engine did not.

No player-visible symptom has been measured, and that is why it is filed rather
than fixed: library 1 *is* re-keyed on every movie load (verified live —
`lib_keys={1: "EAT/internal", 2: "DINNER1/doc", …}` after the real
`dinner1.dir → eat.dir` handover), and library 1 is what this corpus's scripts
actually name. So the stale entries are unreachable in the six titles as authored,
and the bug is a loaded gun rather than a wound. It is one line beside the existing
`clear()`, and the reason to do it deliberately rather than casually is that
`bugs.md` 34's whole family — a member number resolving in the wrong library returns
a stranger rather than nothing — is what stale keys would produce.

Reproduce the state:

```
godot --headless --path . --script tools/click_chain.gd -- --root piposh-dream --file dinner1.dir
```

and read `_lib_keys` after the handover to `eat.dir`, with that tool's own
`_lib_keys.clear()` at `:469` removed.



---

## 118. A Movie-In-A-Window smaller than the stage would hand a transition two differently-sized pictures

**Status:** OPEN · **Area:** `scenes/preview/frame_loop.gd:begin_transition`,
`scenes/director_preview.gd:_grab_stage` · **latent — no corpus can express it
today** · found 2026-08-14 while fixing 117, and deliberately not folded into it

The two frames a transition composites and the play that composites them are
sized by three different questions, and only one of them asks the window:

* `paint_capture` is sized `window_size()` (`director_preview.gd:1758`);
* `_grab_stage`'s framebuffer arm crops and resizes to `stage_size()`;
* `frame_loop.gd:begin_transition` builds `Transition.Play` at `stage_size()`.

In all six shipped corpora and both Itamar corpora those are equal, so nothing
disagrees and nothing can be measured. **A Movie-In-A-Window smaller than the
stage would hand the headless path a window-sized departing frame to a
stage-sized play**, and the desktop path a stage-sized crop of a window that is
not the stage.

Not folded into 117 because it is a different subject with a different fix: 117
was a transform missing from a crop, and this is three call sites that should all
be asking the same question and are not. Fixing it needs a decision about *which*
question is right — Director composites a transition over the window the frame
change happened in, so `window_size()` is the likely answer, and `stage_size()`
being correct everywhere today is a property of this corpus rather than of the
engine.

**No harness can currently fail on this**, which is exactly why it is written
down rather than left to be rediscovered: `tools/window_preview.gd` opens the two
`piposh2` windows and both are stage-sized. A fixture would have to be
synthesised, and the honest first step is to say in `begin_transition` which size
it means and why.
