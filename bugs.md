# Known bugs and open engine gaps

One entry per issue, worst first. Each carries the evidence it was found with, so
the next session can confirm it still reproduces before working on it rather than
trusting this file.

Numbers here were measured on the commit that added the entry. Re-run the tool
named in the entry before acting on a figure. Agreement with the lifted export
falls as the port gets more faithful, so a moved number is not automatically a
regression: see `.claude/skills/porting-fidelity-verification/SKILL.md`.

Resolved entries live in [`docs/bugs-closed.md`](docs/bugs-closed.md), under the
numbers they were filed with, because source comments cite them. Entries 14, 22
and 25 appear in both files: the fixed half is there, the remainder is here.

**Three numbers are reused by unrelated entries, so a citation to one of these is
ambiguous and needs its title to disambiguate.** Found by an audit over both
files; recorded rather than renumbered, because source comments cite these numbers
and renumbering breaks that contract worse than the collision does.

| number | one entry | the other |
|---|---|---|
| 33 | here: `gate.sh`'s `editable_text` asserts nothing | closed: `go to frame X of movie Y` read its own command word |
| 34 | here: `the visible of sprite N` on an empty channel | closed: film-loop children drew from the wrong cast |
| 41 | here: `member (<expr>) of castLib X` drops the library | here, further down: `play_suspends` flakes about half its runs |

> **Many "Reproduce:" lines below name tools that no longer exist.** The retired
> renderer and the ~24 harnesses that drove it were deleted; every command naming
> `smoke.gd`, `probe.gd`, `cursors.gd`, `room_names.gd`, `sprite_channels.gd`,
> `sprite_stretch.gd`, `film_loop_stretch.gd`, `verify_film_loops.gd`,
> `collectables.gd`, `cliff_meeting.gd`, `wandering_characters.gd`,
> `puppet_visibility.gd`, `lingo_converge.gd`, `lingo_frames.gd`,
> `lingo_walk_diff.gd`, `lingo_handler_scope.gd`, `sound_state.gd`,
> `check_surface_coverage.gd`, `score_diff.gd`, `place_diff.gd`, `member_diff.gd`
> or `tools/lib/driver.gd` will not run, and so will anything reading
> `assets/render_model/` or `data/` — both directories are deleted. The
> *observation* in each entry may still be true; the command proving it is gone,
> and re-proving it against the live player is the first step on any of them.
>
> **Entries 18 and 19 are about `MoviePlayer`, which is deleted**, and entry 8
> asks for `movie_context.json` / `walk_doorways.json` to be retired, which has
> happened. Those three are candidates for closing outright rather than fixing.
> Entry 2's subject, `PuppetController`, is also deleted — the underlying
> question (does the port reimplement a walk state machine the movie's own
> scripts already answer?) survives the file.

---

## Coverage debt — harnesses deleted with the retired renderer

These asserted rules that still matter, through an engine that no longer exists.
Nothing replaced them. Listed worst first, so that "we have no coverage of X" is
written down rather than remembered.

| Was | Asserted | Live equivalent |
|---|---|---|
| `tools/smoke.gd` | The first minute of play, end to end: menu, new game, opening sequence advances rather than loops, an item is picked up *and* leaves the room | **none.** `gate.sh` tests mechanisms one at a time and nothing walks a playthrough. The biggest hole |
| `tools/check_surface_coverage.gd` | Which Lingo names the host actually binds, against `docs/LINGO_SURFACE.md` | **none.** This is the tool that would have caught the `intersects` hole and could not, because it audited the retired host. Rebuilding it against `scenes/preview_lingo_host.gd` is the highest-value port on this list |
| `tools/probe.gd` | Not pass/fail: where the playhead went, what it repeated, where it stopped, in real time | **none.** `AGENTS.md` told every session to reach for this first |
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

## 44. The ship map's figure vanishes whenever `nof` is empty or four characters long

**Status:** OPEN, and **not** the `intersects` question it was briefly filed as.
Reported from play as "the Piposh figure on the ship in the menu vanished".

`PIPDATA/MAINMENU.dir` member 43 is the map's `enterFrame`, and its whole body is
inside one test:

```lingo
if the number of chars in nof < 4 then
  ...place the figure on a deck zone, leave it visible...
else
  set the visible of sprite 20 to 0
end if
```

Every legitimate value of `nof` is two or three characters -- `dl1`, `ul5`, `t4`,
`df`, `db`, `uf`, `ub`. So the figure disappearing means `nof` arrived **empty or
long**, and the map is behaving correctly about a value someone else got wrong.
`nof` is set in the deck movies by `set nof to the name of member the castNum of
sprite 1`, which is exactly what entry 39 was: a dropped cast library made `nof`
read `walkright1` (ten characters) instead of `dl1`, and the figure went with it.

**Also load-bearing: `enterFrame` reads `nof` once, on entry, and never re-runs.**
Setting `nof` after the map has opened does nothing at all -- measured, and it is
what made this look unreproducible at first. Any harness for this must set the
global *before* `lingo_go_movie`.

Reproduce, both directions:

```
nof set before the map opens        figure visible=1, placed on the right zone
nof unset / four or more chars      figure visible=0, and no placement runs
```

**What to find out:** which path into the map leaves `nof` bad. Entry 39's fix
covers `the castNum of sprite`; something else is still reaching the map with an
empty or long `nof`, and the deck movie that does it has not been identified. A
`play`-and-return that skips the deck movie's own `enterFrame` is the first
suspect, since that handler is where `nof` is set.

---

## 41. `member (<expr>) of castLib X` drops the library, and with it every joke and every collectable card in Piposh 1

**Status:** open · **Area:** `lingo/compile/lingo_parser.gd` · **the fourth
instance of one shape**, and the first three each cost a player bug too ·
reported from play as *"the binoculars vanish when the deck chair collapses"*

Reproduce, on the tree as it stands:

```
godot --headless --path . --script tools/parse_residue.gd -- --root piposh
```

`FAIL  piposh: no compiled statement calls a clause keyword (12 in 8754 script(s))`,
all twelve on `MASTER.CST` member 31, lines 4 and 75 — `jokesfunk` and
`cardsfunk`, the two handlers Piposh 1 runs on **every** room entry. Both
localisations report the same two lines; Piposh 2 has the identical line in its
own `MASTER.CST` member 12 and is clean only because it is commented out.

**The mechanism.** `_parse_the`'s `member` arm has two branches and only one of
them looks for the trailing clause:

```gdscript
if _at_op("("):
    var args := _parse_call_args()
    mwhich = args[0] if args.size() > 0 else {"node": "num", "value": 0}
    mcast = args[1] if args.size() > 1 else null        # <-- no fallback
else:
    mwhich = _parse_expr(Grammar.BINARY_LEVELS.size() - 1)
    mcast = _parse_optional_castlib()
```

The other three sites that parse the same designator —
`lingo_parser.gd:752` (`field (…)`), `:777` (`member (…)` as a reference) and
`:975` (`the number of member (…)`) — all read
`args[1] if args.size() > 1 else _parse_optional_castlib()`, and each of those
lines was added by a bug report. This one was missed. **The fix is that same
expression, on the `mcast` line of the `the <prop> of member (…)` arm.**

**Why nothing reports it.** The expression is still valid without the clause, so
the statement compiles; the words left over become statements of their own. From
`tools/scratch`, the AST of

```
put the name of member (the membernum of sprite 1) of castlib "decks" into x
```

is a `put_echo` with no target, then a bare `of`, then `castlib("decks")`, then
`into(x)`. `x` is therefore never assigned, and the four later mentions of `x` in
`jokesfunk` compile to calls to a handler named `x` that answers VOID. So `y` is
VOID, `char y of x` is empty, `value("")` is 0, `item 0 of globaljokes` matches
neither `"0"` nor `"on"`, and the handler falls into its final `else`:
`set the visible of sprite 17 to 0`. Every time. `script_compile_check.gd` sees
a script that compiled and says so.

**The player-visible half.** Piposh 1's rooms each hide one gag on channel 17 and
one collectable card on channel 19, revealed by `globaljokes` / `globalcards` and
restored on entry by `jokesfunk` / `cardsfunk`. In DAY1's `dl1` — the deck
outside the cabin door, and the room the report names — channel 17 is member
`1:156`, a pair of binoculars. Clicking the deck chair runs `dl1chair` (frames
66-80), whose frame script at 70 (`BehaviorScript 158`) plays the chair
collapsing, sets `item 1 of globaljokes` to `"on"` and animates the binoculars
falling onto the deck on channel 16. Measured over the whole clip: `globaljokes`
does become `on,0,0,0,0` and channel 16 does draw members 150→156, so the gag
runs. Then the playhead returns to `dl1` (frame 3), `BehaviorScript 21` calls
`jokesfunk()`, the branch above fires, and **channel 17's override stays
`{"visible": 0}` for the rest of the movie.** The binoculars are gone.

`BehaviorScript 158` gets the same value out of the same cast because it spells
the designator *without* the parentheses — `the name of member the memberNum of
sprite 1 of castLib "decks"` — which is why the gag can fire at all and only its
restoration is lost.

Proof that the parse is the whole of it, at `dl1go` with
`globaljokes = "on,0,0,0,0"`:

| handler called | channel 17 after |
|---|---|
| `jokesfunk`, as authored | `{"_member": 156, "visible": 0}` |
| the same body with the parentheses removed | `{"_member": 156, "visible": 1}` |

**Scope.** Every joke and every collectable card in Piposh 1, Piposh 1 English
and Piposh 1 Russian, in every room, on every day — 5 jokes and 5 cards per day
by `globaljokes`/`globalcards`, none of which can ever be seen a second time.
`piposh2`, `piposh-dream` and `rating` report 0.

**Not the same fault as the up-staircase** reported alongside it from the same
room, which was `preview/interaction.gd:script_for_click` handing the click to a
behaviour that declares no mouse handler. Two reports, one room, two causes.

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
`btofspk1`, the talking loop, which entry 21 above names from the other side. The
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
   `ahatlop1` — entry 21 again) and the click was not answered on the frame the
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

## 35. `field "x" of castLib Y` drops the library

**Status:** open · **Area:** Lingo host, fields · `scenes/director_preview.gd:lingo_field`

`lingo_field(name, _cast)` and `lingo_set_field(name, _cast, text)` take the cast
the script named and ignore it — the parameter is spelled `_cast`. Both then go
through `_resolve_field`, which asks `Members.resolve_ref(name, "")`: the
unnamed-cast path, which searches every library in number order and takes the
first field of that name. An explicit `of castLib` in the script is discarded, so
a movie with the same field name in two libraries reads and writes the wrong one.
Same class as `docs/bugs-closed.md` 34 and 29: the library is part of the answer.

Not currently visible, and that is the whole reason it is filed rather than
fixed on suspicion. Found while measuring `resolve_ref` for 34. Across all 61
movies, 1,081 member names exist in more than one library, and **four** of them
are named by a script:

| movie | name | libraries |
|---|---|---|
| `air1` | `jokefield` | Internal(1):201, master(3):122 |
| `chess` | `fuel` | Internal(1):135, master(3):27 |
| `hotel1` | `mirror` | Internal(1):364, island2(5):240 |
| `night1` | `jokefield` | Internal(1):225, master(2):122 |

None of the four is reached through a qualified `field` reference: `fuel` and
`mirror` are `member(...)` references, and `jokefield` goes through
`TextArt.resolve`, which re-walks the libraries preferring an actual field. The
one qualified field reference in the corpus is SAVELOAD's
`field "plane" of castLib 2`, and `plane` is unique in SAVELOAD, so the dropped
library and the right library are the same one.

So the corpus does not exercise it. Build it anyway — the reference says a field
reference carries a cast and this engine is meant to run other titles.

Reproduce:

```
grep -rn 'field "[^"]*" of castLib' reference/lingo --include=*.ls
```

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
do reach the stage (`docs/bugs-closed.md` 1 is closed, `tools/sprite_channels.gd`
covers it).

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

`tools/wandering_characters.gd` is the pass/fail form of the same question and
asserts the player-visible invariant, how many of each pair are drawn, rather than
that `inexits` and a getter agree. It is **uncommitted and unverified** at the time
of writing: run it before trusting either its red or its green.

Not the same bug as `docs/bugs-closed.md` 14's film-loop half, found in the same rooms in the
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
`docs/bugs-closed.md` 1 is closed; running it fixes this one for free and retires
`GameState.people_funk` at the same time. Deliberately **not** patched natively.

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
(see `docs/bugs-closed.md` 15). The children are simply invisible instead.

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

Not the same bug as `docs/bugs-closed.md` 14's film-loop half. That one drew children at the wrong
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

## 6. SEA1 and AIR1 stall under interpreted frames

**Status:** open · **Area:** interpreter / frames

With `use_lingo_frames` off, SEA1 visits 24 distinct frames over 220 ticks and
AIR1 visits 34. With it on, SEA1 sits on frame 3 for the whole run and AIR1 stays
between 3 and 29. Agreement with the score runner is 0/220 ticks for both, against
220/220 for DAY1, NIGHT1 and HOTEL1.

**Reproduce:** `godot --headless --script tools/lingo_frames.gd`.

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

## 7. Two clicks produce no navigation or sound under the interpreter

**Status:** open · **Area:** interpreter / clicks

`SEA1 ch9 frame 1234` and `AIR1 ch8 frame 707`: the export carries a destination
and a sound list, the interpreted handler produces neither. These are the only two
outright disagreements in the convergence run, so they are small and specific
enough to read end to end.

**Reproduce:** `godot --headless --script tools/lingo_converge.gd`, lines tagged
`differ`.

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
somewhere. That figure was taken *before* 25's skip routing was investigated and does not
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

## 14. `strtgame`'s chunk dump does not reach its members' declared sizes

**Status:** open, suspicion only · **Area:** assets ·
all three drawing defects this entry carried are fixed, see `docs/bugs-closed.md` 14

The visible symptom this entry was filed for, the bearded man's head smeared
horizontally across the sky in the opening raft video, is fixed and was the dropped
stretch flag. What is left is a measurement about the dump underneath it that has
no innocent explanation yet.

Only **17 of `strtgame`'s 195** 8-bit members reach their declared size as a clean
prefix of their chunk. Member 26, the head, decodes to a clean prefix of 194 bytes
in a 3,293-byte chunk against a declared 46 x 34. For contrast, DAY1 decodes 440 of
452 members exactly and MURDER1 24 of 24. That is a payload-boundary problem across
the whole of `strtgame`'s dump, not a fact about one member.

One signal keeps the member-side suspicion alive on its own: member 26's
registration point is **(68, 17) on a 45-wide bitmap**, so it sits outside the
image, and 68 is half of 135, the width the score stored and Director ignores.

Two readings were tried and do not survive measurement, so they do not get
re-checked. `BITD-2774` decoding past its declared size proves nothing: member 25,
this entry's own control, does the same, and so do 388 of `strtgame`'s 390 8-bit
members. And the `CASt` rect reading 45x34 is not a disagreement; that a geometry
is declared is not evidence against it.

Anyone picking this up settles the chunk boundaries first. No claim about one
member's geometry can be made on top of a dump that is wrong movie-wide.
The XFIR reader's own disagreement with ProjectorRays, 441 of 912 chunks at the same
offsets with different payload boundaries, is a separate and still-untested fact,
and is not the same claim as "there are no chunks": `strtgame` has had a complete
1,019-chunk ProjectorRays dump the whole time.

---

## 22. MURDER1's Lingo is in the binary and the decompiler emitted one cast of five

**Status:** open · **Area:** assets / decompilation ·
the navigation defect this number carried is fixed, see `docs/bugs-closed.md` 22

MURDER1's frame scripts 116, 117, 119, 120 and 424 resolve to nothing, while
`toolcache/chunks/MURDER1/MURDER1/chunks/` holds 33 `Lscr-*.bin` chunks. The Lingo
is in the container; the decompiler emitted one cast out of five.

What the gap costs is entry 23. Where a frame script is present, the export's lossy
copy of it can still win; where no script resolves at all, the export decides alone
and there is nothing to disagree with it. 116 and 117 are the choice wait loop and
119 and 120 the mouth-flap-while-speaking loops, and those four happen to have
their semantics in the exported nav already, which is why the scene plays. Nothing
establishes that the other chunks are as harmless.

Source for a re-run: `originals/recovery/web-alpha/PIP2DATA/MURDER1.DXR`.
ProjectorRays is not installed on this machine, which is the whole of what blocks
this.

**Why the number is still cited.** `AGENTS.md`, `tools/lib/driver.gd`,
`tools/probe.gd`, `tools/cliff_meeting.gd` and `autoload/app_settings.gd` all point
at "bugs.md 22" for the real-time lesson: a synthetic `for i in N: tick()` loop
advances the runtime's clock and not the audio server's, so every `soundBusy` guard
holds for ever and any scene with speech in it looks stuck. That account is in
`docs/bugs-closed.md` 22.

---

## 10. Convergence is measured on 5 of 61 movies

**Status:** open · **Area:** verification

`lingo_converge.gd` and `lingo_frames.gd` cover DAY1, NIGHT1, HOTEL1, SEA1 and
AIR1. Nothing measures the other 56, including every minigame and meeting movie.
An engine change can only be checked against the five.

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

**`walk_doorways.json` is next and is now redundant on the path the game runs.**
Fixing `walkonby` to read all three items of `nextroomdata` gave every interpreted
room exit the arrival point its own hotspot script authors, so no interpreted exit
consults the table any more; only the export-driven `start_walk` still does. See
`docs/bugs-closed.md` 26, which also records why the table's premise was wrong in a
useful way: it reverse-engineered per-edge coordinates from the score by reciprocity
and got close, `(30,328)` against the script's `(33,291)` and `(326,371)` against
`(344,375)`, while the real numbers were in the Lingo the whole time.

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

## 28. The preview's cursor never scales with the stage, and its hotspot rule is unverified

**Status:** open, cosmetic · **Area:** preview renderer ·
found while fixing the preview's custom cursors

Two things about how a composed cursor lands on screen in
`scenes/director_preview.gd`, neither of which stops a cursor appearing now that
it appears at all.

**Scale.** `lingo_set_cursor` hands `Input.set_custom_mouse_cursor` the composed
image at its native 16x16 and nothing else. The preview draws the 640x480 stage
through `_fit_to_window`, which at the project's default 1280x720 window and the
`native_4_3` aspect picks `min(1280/640, 720/480)` = **1.5**, so every piece of
artwork is half again as large as the cursor sitting on it. This is bugs.md 19
for the other renderer, one step worse: `MoviePlayer._apply_cursor` at least
scales in integer steps, and this does not scale at all.

Reproduce: run
`godot --path . res://scenes/director_preview.tscn -- --file PIP2DATA/MAP.DIR`,
hover any of channels 3-14 on the map, and compare the 16x16 cursor against the
map art around it.

**Hotspot.** `_cursor_image` takes the hotspot from the data member's
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

## 32. The SKIP button parks the playhead on a frame the movie can never leave, and that is the cursor "never coming back"

**Status:** open · **Area:** preview, `skip_to_end` · **not the cursor path** ·
**see also `docs/bugs-closed.md` 42**, which is the same button failing for a
third reason — it left the voice playing, so piposh's `soundBusy(1)` talk gate
re-armed at the destination. That half is fixed; the mis-landing below is not,
and 42's fix does not change where SKIP lands ·
reported from play as "after MURDER1 the cursor reverts to the arrow and never
returns"; reproduced once the missing step arrived — **the player presses SKIP**

The cursor is not broken. `docs/bugs-closed.md` 29 and the cursor harness cover
that path end to end, and it is correct: measured across all 61 movies, every
assigned pair composes; `MovieSession.forget_previous` clears `_channel_cursors`
on a movie change; and playing MURDER1 to its own `go("clif2", "day1.dir")` lands
in DAY1 with nine channels armed and all three on-stage sprites arbitrating
correctly. None of that is what the player does. They press SKIP.

**A Director movie's last frame is not its ending.** A movie is a strip of
independently labelled segments and the last frame is only the last segment's
last frame. `skip_to_end` moves the playhead there and nothing else, on the
premise that the end of the file is the end of the scene. Measured, that premise
is false in both of the movies this report touches, in two different ways:

| movie | last frame | its `exitFrame` | effect |
|---|---|---|---|
| MURDER1 | 883 | `go("conect2")`, and `conect2` is frame **790** | jumps *backwards* into the tail being skipped |
| MAP | 80 | — | next frame entered is **45** |
| DAY1 | 2783 | `play "done"` | subroutine return with nothing on the stack |

So: SKIP during MURDER1 lands on 883, which immediately sends the playhead back
to 790 and replays the last 94 frames. From the player's chair SKIP did nothing,
so they press it again — and whichever press lands after MURDER1 has already
handed off to DAY1 skips **DAY1**, the hub movie that holds every room of day one
in 2,784 frames. Its last frame is the tail of one of the `play`-called talk
clips at 2595-2783, and its `exitFrame` is `play done`. `lingo_play_done`
(`scenes/director_preview.gd:1621`) finds `_play_stack` empty and returns without
moving anything; it is also the last frame, so the score's own advance has nowhere
to go either. **The playhead never moves again.**

The cursor then behaves exactly as it should and looks broken:
`_channel_cursors` still holds all nine pairs the room assigned, but none of
those channels has a sprite on frame 2783, so the descent correctly falls through
to the global cursor — 0, the arrow — at every point on the stage, for ever.
Moving the mouse does recompute (`input_router.gd:mouse_motion` ->
`_resolve_cursor`); it recomputes to the arrow.

**The stale-window lead from the previous pass is dead.** `Windows.at` skips any
window whose `_window_shown` is false and `lingo_forget_window` erases destroyed
ones, so a hidden or freed window cannot capture the stage's recompute. `_windows`
was empty at every sampled step of both reproductions. Windows surviving a
`go to movie` is correct Director behaviour and is not this.

Reproduce, and note that MAP loops back too but keeps its cursor, because MAP's
cursor-bearing channels *are* on the frames it lands among — which is the whole
mechanism in one contrast:

```
$ godot --headless --script tools/skip_state.gd -- --file PIP2DATA/DAY1.DIR
   DAY1.dir  f46 -> skip -> f2783 -> f2783 -> f2783
   cursor at the stage centre: [16, 17] -> 0, 9 channel(s) still recorded
FAIL  DAY1.dir: the movie can still move after SKIP  (parked on DAY1.dir f2783)

$ godot --headless --script tools/skip_state.gd -- --file PIP2DATA/MURDER1.DIR
   MURDER1.dir  f34 -> skip -> f883 -> f790 -> f828
FAIL  MURDER1.dir: the last frame is an ending, not a jump back

$ godot --headless --script tools/skip_state.gd -- --file PIP2DATA/MAP.DIR
   MAP.dir  f34 -> skip -> f80 -> f45 -> f47
   cursor at the stage centre: [14, 15] -> [14, 15], 12 channel(s) still recorded
```

`tools/skip_state.gd` is title-agnostic and not in `gate.sh`: it is red on this
corpus by design, because it asserts the property SKIP needs and does not have.
`--all` sweeps every container under the game root.

**What to change, and what not to.** Director has no skip, so there is nothing to
be faithful to and this is a judgement about a debug affordance rather than an
engine gap. Two candidate shapes, and the obvious one is wrong:

- **Wrong: run the intervening frame scripts instead of jumping over them.** For a
  linear cutscene that is what is wanted; for DAY1 it would run the whole rest of
  the movie — dozens of unrelated rooms, every `go`, every sound — because the
  frames between here and the end are not "the rest of this scene".
- **Right: stop jumping the playhead at all.** What the player means by SKIP is
  "stop waiting", not "go to the end of the file". Releasing whatever the current
  frame is holding on — the wait, the sound — and letting the movie's own scripts
  drive to their own exit walks MURDER1 to its `go("clif2", "day1.dir")` and does
  nothing harmful in DAY1. `_clock.release()` already exists and is what the jump
  currently does *in addition to* the damage.

Both live in `skip_to_end` (`scenes/director_preview.gd:1035`), and the SKIP
hit-test is in `input_router.gd:mouse_button`. Neither is in this change.

---

## 33. `gate.sh`'s `editable_text` entry asserts nothing, and reports PASS

`tools/editable_text.gd` finds its own subject: the first frame carrying a field
sprite. Run with no arguments it opens the configured boot movie, and this
title's boot movie is `strtgame.dir`, which has no field sprite anywhere. The
harness says so and exits **passing with zero checks**:

```
$ godot --headless --path . --script tools/editable_text.gd
strtgame.dir has no field sprite anywhere; nothing to type into

PASS  editable text in strtgame.dir (0 checks, 0 failed)
```

`gate.sh` runs every harness with no arguments, so the gate entry that covers
§8.4 has never asserted anything on this corpus. Pointed at the movie the feature
is *for* it asserts 43:

```
$ godot --path . --script tools/editable_text.gd -- --file PIP2DATA/SAVELOAD.dir
PASS  editable text, focus, caret and selection in SAVELOAD.dir (43 checks, 0 failed)
```

This is the exact failure mode `scenes/preview/README.md` warns about in another
context — a harness that reads nothing reports zero rather than failing, and the
safety net goes dark without going red. It is filed rather than fixed because the
fix is a choice: either the harness scans for a container with an editable field
the way `tools/save_movie.gd` does, or `gate.sh` grows per-harness arguments, and
`gate.sh` is not this change's to edit.

---

## 34. `the visible of sprite N` answers FALSE for an empty channel, and that is why the main menu's Load button does nothing

**Symptom, from the player's chair:** on the main menu, clicking Load does
nothing at all — no window, no sound, no cursor change. It looks like "there is
no save to load". It is not: the button never runs.

`ROOT/strtgame/BehaviorScript 369.ls` is the menu's Load button, and its entire
body is inside one guard:

```lingo
on mouseUp
  global soundspath, effectspath, movienamekeeper, stopornot, cdsavepath
  if sprite(30).visible = 1 then
    ...
    open(window(cdsavepath & "saveload.dxr"))
    ...
  end if
end
```

The guard is a copy of the in-game menu handlers (`DAY1/wonder/BehaviorScript
312.ls` and its siblings), where channel 30 is the walking player character and
the test means "not mid-cutscene". On the *main menu* there is no player:

```
strtgame.dir: channel 30 occupied in 0 of 1375 frames
engine answers sprite(30).visible = 0 on frame 0
```

**In Director a sprite channel's `visible` is a channel property that defaults to
TRUE**, whether or not the channel holds a member — an empty channel is a visible
channel with nothing in it. The guard therefore passed in 1997 and the button
worked. This port answers 0 for a channel with no sprite record, so the guard
fails and the handler returns having done nothing.

Reproduce:

```gdscript
# any harness, after booting strtgame
preview.call("lingo_sprite_prop", 30, "visible")   # -> 0, wants 1
```

**Where the fix goes:** `scenes/preview/sprite_props.gd`, the `visible` read. It
has to distinguish "the channel is empty" from "a script set `visible` to 0", and
answer TRUE for the first. Worth checking the same question for the other channel
properties that have a meaningful default on an empty channel (`locH`/`locV`,
`ink`, `blend`) rather than fixing one and leaving the class.

Not fixed here because `sprite_props.gd` was being edited by another change at the
time. The three observations it explains — Load doing nothing on the menu, and
the two save-related ones — are otherwise unrelated: the save half was
`saveMovie` bound inert and is fixed.

---

## 37. SKIP walks off the end of `rating`'s main menu into a subroutine region, and the movie restarts its own opening

**Status:** open · **Area:** preview, `skip_to_end` · a second failure mode of
the same affordance as entry 32, through the marker walk rather than the
last-frame fallback · reported from play as "when the game starts, if I press
different places it jumps back and forth — just on this game"

`skip_to_end` walks to the **next marker** and falls back to the last frame only
when there is none. Entry 32 is about that fallback. This is about the walk
itself: **a marker is not a scene.** A Director movie routinely parks
subroutine segments after its playable strip, entered by name with `go("x")` and
left with a jump back to the top, and the marker list cannot tell those apart
from the next scene.

`rating`'s boot movie is `MAINMENU.dir`, not `strtgame.dir`. Its markers are

```
    3 hedartzi   14 guilotine   46 oliver   504 mainscreen
  587 option1   594 option2   601 option3   609 option4   614 option5   621 option6
```

The playable strip is 0-521: a 449-frame opening (`53..501`, frame script member
7, `on exitFrame / if the mouseDown then go("mainscreen")`) and then the menu,
which idles on 504-521 because frame 521 runs `go(marker(0))`. `option1`..
`option6` are **not scenes**. They are the CD drive-letter probe — six frames
that each set `the searchPath` to one drive, `playFile` a known clip, and either
record the letter or `go` to the next option — and every one of them ends on a
frame whose script (member 88) is `on exitFrame / go(2)`. Nothing in the movie
ever enters them; they are reachable only by jumping into them.

So SKIP pressed on the menu lands on `option1`, the probe runs, `go(2)` fires,
and the playhead is back at **frame 2 — the start of the opening the player was
trying to skip.** Pressing SKIP again walks 14 → 46 → 504 → 587 → 2 again. That
is the reported "jumps back and forth", and it is a closed cycle:

```
$ godot --path . --script <a harness that presses SKIP and traces>
SKIP 0: MAINMENU.dir f10  -> landed f14  -> f25   trail [14 … 25]
SKIP 1: MAINMENU.dir f25  -> landed f46  -> f47   trail [46, 47]
SKIP 2: MAINMENU.dir f47  -> landed f504 -> f511  trail [504 … 511]
SKIP 3: MAINMENU.dir f511 -> landed f587 -> f3    trail [587, 588, 589, 590, 2, 3]
SKIP 4: MAINMENU.dir f3   -> landed f14  -> f26   ... and round again
```

Reproduce the shape without a harness — this is the score, and it is enough:

```
$ godot --headless --path . --script tools/director_frames.gd -- \
      --root rating --file MAINMENU.dir
markers    : 10, labels 10
     504  mainscreen
     587  option1        <- SKIP's next marker from the menu
```

`tools/skip_state.gd` passes on this movie and is not wrong to: it skips from
f250, which is inside the opening, so the next marker is `mainscreen` and that is
a real destination. The trap is only reachable from the *last* playable segment,
which is exactly where a player who wants to skip is standing. Extending
`skip_state` to press SKIP repeatedly until the marker list is exhausted would
catch it, and would also catch entry 32's cases; that is the check this entry
wants and does not have.

**Why it is filed and not fixed.** Entry 32 already argues the shape of the
answer — SKIP should stop teleporting the playhead and instead release what the
current frame is holding on and let the movie's own scripts drive — and this
movie is the strongest case for it yet, because *the movie has its own skip*:
`if the mouseDown then go("mainscreen")` covers all 449 frames of the opening.
That one works now (see the commit that added `tools/mouse_poll.gd`), so a player
on this title no longer needs the button. There is no title-agnostic rule that
can tell `option1` from `mainscreen` by looking at the marker list, which is the
whole reason the marker walk cannot be patched into correctness.

Two things found alongside, both only reachable through this trap and both real:

- The probe concludes the CD is on **D:**. `sound playFile 1, "d:\sounds\start\egozcold.aif"`
  resolves — the last-resort bare-filename lookup finds
  `games/rating/sounds/start/EGOZCOLD.AIF` — so `soundBusy(1)` is true and the
  movie sets `gWinDriveLetter` to `d` and `soundspathstart` to `d:\sounds\`. An
  absolute path naming a drive that does not exist should not resolve to a file
  beside the movie.
- `soundspathstart` reads empty in `ARRIVEL` after the menu's Play button, so its
  sounds are requested as `start\story.aif` rather than under the game root,
  while the same global was correct in `MAINMENU` a moment earlier. Not
  investigated; `tools/globals_survive.gd` is the tool for it.

---

## 38. Piposh 1 English "stuck on the logo" does not reproduce, and the CD-drive probe it points at was dead for a different reason

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
`skip_to_end` walks to the next marker (entries 32 and 37). `strtgame.dir`'s
marker list ends with `option1`..`option26`, `maybondisk`, `inserta` and `cont`
— the CD-drive probe — and frame 1347 `inserta` renders as **"Please Insert CD
and click OK"** with `Quit` on the left and a yellow `Ooooooooooo K !` on the
right, whose script goes to `cont` and from there back to f2. So "SKIP → a disc
message → the right-hand button → the main menu" is SKIP walking into the probe
region, exactly as entry 37 describes it doing on `rating`. It says the reporter
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

## 39. Every title except Piposh 2 still has scripts that do not compile

**Status:** open · **Area:** `lingo/compile/lingo_parser.gd` · found by
`tools/script_compile_check.gd`, which is why it is a number and not an
impression

| root | compiled |
|---|---|
| `piposh2` | 3,307 of 3,307 |
| `piposh` | 8,738 of 8,754 |
| `piposh-en` | 9,406 of 9,422 |
| `piposh-ru` | 9,710 of 9,726 |
| `rating` | 5,437 of 5,441 |
| `piposh-dream` | 1,725 of 1,746 |

Piposh 2 is the corpus this parser was written against, which is exactly why its
green says nothing about the language. Each Piposh 1 localisation fails 16 and
they are not the same 16 — the shared ones are `MASTER.CST`'s five CLOCK SCRIPTs
and `MovieScript 34`, plus `POOLWAR` 66 and `ROULLETE` 149:

```
godot --headless --path . --script tools/script_compile_check.gd -- --root piposh --verbose
```

Two spellings account for most of them, and both are ordinary Lingo:

- `set the editable of member ("save" & i - 27) of castLib 1 to 0`
  (`MAINMENU.dir` 112 and 145 in `piposh`, `MANAEGOZ.dir` 99 and 109 in
  `rating`) reports "set needs `to`", so the target parse is swallowing the `to`
  rather than the `=` this time. That is the save/load screen's field enabling,
  so entry 34's neighbourhood.
- `expected end` at the last line of five near-identical CLOCK SCRIPTs, and
  `unexpected "\n"` in eleven more across `piposh-dream` and `rating`. Not
  diagnosed.

Nothing here is title-specific: they are language surface this parser does not
have yet, and every one is a handler that silently does not run.

---

## 40. Unnamed markers are dropped, so `marker(n)` cannot count to a `play done` frame

**Status:** fixed in the working tree, **not yet gated** · **Area:**
`director/director_labels.gd` · found while landing `play`/`go` suspension, and it
is the other half of the same dialogue

**This entry was open for one commit longer than anybody believed, and that is the
part worth keeping.** It was filed with the diagnosis correct and the fix printed
below. Commit 641d1d47 ("labels: an unnamed marker still counts, so `marker(n)`
stops skipping past it") landed that printed fix, said in its message that the
dialogue was repaired, and **was inert**: it moved `markers.append` above the
`if name == "": continue` and taught `marker_at` to prefer named markers, but left
the range guard four lines higher —

```gdscript
if start < text_base or stop > payload.size() or stop <= start:
    continue
```

— and `stop <= start` is true for a zero-length name, so control never reached the
append that commit had just moved. The file then carried a comment reading "An
unnamed marker is kept, and that is not tidiness" directly beneath a guard that
dropped them, and a class docstring still insisting they "must be dropped, or
every later marker's index shifts", which is exactly backwards. Two independent
readings of the same file disagreed and nothing arbitrated.

**Nothing caught it, because the only harness that could had repaired its own
subject.** `tools/play_suspends.gd:_restore_unnamed_markers` re-parsed the VWLB
chunk, overwrote `labels.markers` with the full list, and early-returned when the
counts already agreed — so `--dialogue` asserted against an array the player never
gets, passed before the fix, and passed identically after it. Its docstring
conceded this ("Put back here rather than fixed here … `bugs.md` carries it"),
which is honest and still useless: a green run proved nothing either way. It is
now `_check_marker_index`, which asserts the count and fails instead of repairing.

The lesson generalises past this bug: a decoder's output size is an *invariant*,
and the only trustworthy witness to it is the container's own header. That is what
`tools/label_index.gd` now checks over every container in every root, and it is
what would have gone red the day 641d1d47 landed.

`DirectorLabels.parse` dropped every VWLB entry whose name is empty. The reference
keeps them: `Score::loadLabels` inserts one `Label` per entry regardless of name,
and `getNextLabelNumber` walks the whole array — so **`marker(1)` counts unnamed
markers and this port's did not.** An unnamed marker is not decoration. It is
how a Director author marks a frame that only the score needs to reach, and it is
not rare: **2,236 of Rating's 4,220 entries**, 59 of `piposh-dream`'s 2,732, and
12 of Piposh 2's 3,019 — so the gate's own corpus carries them too.

Rating's `BATZEGOZ.dir` is the case that found it. Its VWLB has 28 entries and
nine of them are unnamed, one at 0-based frame 214:

```
godot --headless --path . --script tools/label_index.gd -- --file BATZEGOZ.dir --list
```

lists them, and printed 19 of 28 before the fix:

```
    13  frame   207  egozspeak1
    14  frame   214  <unnamed>
    15  frame   216  Batz2A
```

Frame 214 is `BehaviorScript 36`, whose whole body is `on exitFrame / play done /
end`, and it sits between `egozspeak1` (207) and `Batz2A` (216). The talking loop
at 207-213 leaves with `go(marker(1))`. With the unnamed marker kept that is
frame 214, `play done` runs, and the mouseUp that called `play frame
"egozspeak1"` is resumed so that its own trailing `go` picks the room. With it
dropped, `marker(1)` is 216 and **frame 214 is unreachable**: `play done` never
runs anywhere in this movie, and all three of Egoz1's dialogue options arrive at
the first one's destination.

Measured, clicking the three options in turn (`tools/scratch` is gone; the same
walk is what `--dialogue` asserts):

| option | script | markers as parsed | markers with the unnamed ones kept |
|---|---|---|---|
| channel 11 | `go("batz2a")` | Batz2A | Batz2A |
| channel 12 | `go("batz2b")` | Batz2A | Batz2b |
| channel 13 | `go("batz2c")` | Batz2A | batz2c |

so the visible symptom is *a dialogue that answers every option with the same
reply*, and it is one line away.

The fix is not simply to stop dropping them, because `marker_at` is the reason
they were dropped in the first place — a frame inside an unnamed marker's span
must still report the last *named* one, or "which room am I in" answers blank.
**Nor is it `stop < start`**, which is the one-character version and leaves the
sibling clause (`stop > payload.size()`) able to renumber the index space the same
way for the next container that needs it. The rule the loop enforces is now stated
as the rule: *an entry is never dropped; only its name can be unreadable*, so a
bad range costs the name and never the position. Both halves:

```gdscript
        var name := ""
        if stop > start and start >= text_base and stop <= payload.size():
            name = Codepage.decode(payload.slice(start, stop)).strip_edges()
        var zero_based := frame - 1
        markers.append({"frame": zero_based, "name": name})
        if name == "":
            continue
        var key := name.to_lower()
        if not labels.has(key):
            labels[key] = zero_based
```

The earlier revision of this entry printed that block without the guard folded
into it, keeping the `continue` above — which is the shape that shipped inert. The
`continue` has to go, not move.

```gdscript
func marker_at(frame: int) -> String:
    var found := ""
    for marker in markers:
        if int(marker["frame"]) > frame:
            break
        if str(marker["name"]) != "":
            found = str(marker["name"])
    return found
```

**Keeping the entries moves `marker(0)` as well as `marker(1)`, and that is the
risk surface rather than a footnote.** A hold loop inside an unnamed marker's span
now returns to the unnamed marker rather than to the named room. It is
Director-correct — `Score::getCurrentLabelNumber` (`score.cpp:238`) scans every
entry, named or not — but it is a live behaviour change at 2,236 sites in Rating
alone. BATZEGOZ has unnamed markers at 330, 335, 336, 367 and 369 inside
`batz2c`'s span, and members 5, 19, 80, 84 and 123 all call `go(marker(0))`.

Every reader of `markers`, and what the change does to each:

| reader | effect |
|---|---|
| `director_preview.gd:lingo_marker` | the fix. Counts entries, as Director does |
| `lingo_go_next` / `go next` | correct now; `gotoNext` counts unnamed ones too |
| `tools/mouse_poll.gd:133` | **more** correct — its own comment says the handlers it drives end in `go(marker(1))` |
| `tools/click_trace.gd:_where` | already skipped empty names in advance of this |
| `hotspots.gd`, `click_trace.gd:_target_frame` | match by name, so `""` never matches a request |
| `tools/builtin_load.gd:277` | bounds a room's span by "the next marker", which can now be an unnamed one. In the gate — watch it |
| `director_preview.gd:1820` (**SKIP**) | jumps to the next marker ahead, so SKIP now stops on unnamed markers as well. Left alone deliberately: SKIP is a debug affordance with no Director semantics to be correct against, it has its own open entry (32), and "an unnamed marker is not a scene" is the same argument `marker_at` already makes. Wants a decision, not a silent change |

## 51. `gate.sh` pinned the root and not the boot movie, so most of the suite booted nothing and asserted over it

**Status:** FIXED (tooling) · **Area:** `director/director_paths.gd:load_config`,
`gate.sh:36-44`, and the three child-spawning harnesses · found while trying to
verify `bugs.md` 40 and 50 against the recorded baseline, which turned out not to
be reachable from the tracked config

`gate.sh` pins the corpus so that a run against another title does not read as
regressions that are really different movies. It passed `--root piposh2` and
nothing else. **The boot movie still came from `director_game.cfg`**, and
`399feaaa` pointed that at `rating`'s `mainmenu.dir` — a working config, per its
own commit message. So every `ALL` entry that does not name its own `--file`
resolved a `rating` container under `piposh2`, found nothing, and ran on:

```
$ godot --headless --path . --script tools/text_and_shapes.gd -- --root piposh2
ERROR: no such container: mainmenu.dir in res://games/piposh2
        try --file with one of: strtgame.dir, HEZSAVE.DIR
no score loaded
```

**They do not fail — they load no score and assert over nothing.** That is the
dark-harness failure `gate.sh` warns about in its own EMPTY guard, arriving
through the corpus pin rather than through an empty result set.

The fix is the rule the file already argued for one question at a time: an
override belongs in the one place the value is read, or the parts disagree about
which title they are running. `_override_root` had that argument written out and
`boot_movie` had no override at all, so pinning a root was half a pin.
`_override_boot` honours `--boot`, `gate.sh` passes `GATE_BOOT` (default
`strtgame.dir`, the boot movie of both roots the list names) alongside `--root`.

**The same hole a second time, in the child processes.** `save_state`,
`save_movie` and `text_codepage` each spawn a second Godot and each forwarded
`--root` under a comment reading "a parent pinned to one corpus and a child told
nothing are two different games". The boot movie has exactly that property, and
`save_state` was the proof: its child died on `mainmenu.dir`, and the harness
reported it as `the saving process exits cleanly (exit 1)` — 89 checks with one
failure that named the parent. Forwarding `--boot` too takes it to 132 checks, 0
failed. **The check count is the tell**: a harness whose child booted nothing
still reported 89 checks, so the number to watch is not pass-versus-fail but how
much a green run actually asserted.

Reproduce (before the fix): `godot --headless --path . --script
tools/text_and_shapes.gd -- --root piposh2` → `no score loaded`, no verdict.
After: `--root piposh2 --boot strtgame.dir` → PASS, 10 checks.

## 41. `play_suspends` fails about half its runs on one assertion, so the gate's set is not reproducible

**Status:** open · **Area:** `tools/play_suspends.gd:351` · found by the first
full-suite run on macOS, which is also the first one anybody diffed run-to-run

`bash gate.sh play_suspends` twice in a row, same binary, same corpus, prints
PASS then FAIL. Four bare runs:

```
for i in 1 2 3 4; do
  godot --headless --path . --script tools/play_suspends.gd -- --root piposh2 \
    2>&1 | grep -E '^(PASS|FAIL)' | tail -1
done
```

```
FAIL  ... (26 checks, 1 failed)
FAIL  ... (26 checks, 1 failed)
PASS  ... (26 checks, 0 failed)
PASS  ... (26 checks, 0 failed)
```

26 checks every time, so this is not a harness that lost its subject and not a
corpus that resolved differently. One assertion moves: **"and the rest of the
handler still ran"**, which reports `before` when it fails and `after` when it
passes.

The case is `a handler frozen by 'go to movie' outlives the interpreter`. It
calls `suspendhop`, whose body hops to another movie mid-handler, and then waits

```gdscript
	for i in 6:
		await process_frame
```

before asserting that the trailing `put "after" into gsuspendhop` ran. Six
frames is a fixed budget spent waiting for a *container to load off disk* and
the suspended handler to be resumed on the new interpreter. When the load takes
longer than six frames the assertion reads the global before the resume writes
it, and the harness reports the engine as broken.

So the fix is in the harness, not the engine: wait for the condition — the
interpreter to have resumed, with a frame ceiling that fails loudly — instead of
counting frames and hoping. Until then the gate's recorded set is not
reproducible, and a session that runs the suite twice will attribute the
difference to whatever it changed in between.

Not caused by the corpus pinning moving from `director_game.cfg` to `--root`:
both mechanisms resolve the same root, and the 26-check count is identical
either way.

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

## 50. Egoz's face draws inside a white rectangle: Copy ink with the blend flag never gets its matte

**Status:** FIXED (engine) · **Area:** `director/director_ink.gd` keying predicate ·
reported from play as "when egoz speaks his image has the white background, it
should be ignored" · found from a snapshot, root-caused from the container bytes,
covered by `tools/ink_blend_matte.gd`

**Director does not decide a sprite's keying from its ink number.**
`Channel::getMask` (`reference/scummvm/channel.cpp:188-226`) reads the ink, the
thickness byte's blend flag and the member's bit depth together. `key_for` read
the ink alone, so the one combination where those disagree fell through to "draw
every pixel":

```cpp
// reference/scummvm/channel.cpp:206
if (!_sprite->isQDShape() && _sprite->_ink == kInkTypeCopy && _sprite->_thickness & kTHasBlend)
    needsMatte = true;
```

Note what that clause does *not* test: the blend **amount**. A Copy sprite with
the flag set and an amount of 0 — fully opaque — still gets a matte, and the mask
reaches the blit at `window.cpp:465` → `graphics.cpp:797`, where a pixel is drawn
only where `msk && (*msk++)`.

The sprite, from the score rather than from the screenshot. `BATZEGOZ.dir` frame
209, marker `egozspeak1`, **channel 41**, `Panel.cst` member 23 — an 8-bit bitmap
101x135, reg (50,67). Its record, and the resting member two frames earlier:

```
f205 ch41: 10 08 ff 00  00 04 00 03  00 00 00 18  01 a3 02 43  00 87 00 65  00 00 80 00
f209 ch41: 10 00 ff 00  00 04 00 17  00 00 04 fb  01 a3 02 43  00 87 00 65  00 00 10 00
                ^^                ^^                                            ^^
              ink byte         member                                      thickness byte
```

Ink byte `0x00`, thickness byte `0x10` = `kTHasBlend` (`sprite.h:61`), blend
amount `0x00`. The decoder was right about every byte; the keying rule was wrong
about what they mean together. Channel 41 is Egoz — it draws from the shared
`Panel.cst` while the central figure is channels 2-5 from `Batz.cst`, and it
changes member in exactly one of the movie's 19 segments, stepping `Panel.cst`
22-28 one frame each through `egozspeak1` and parking on member 3 at ink 8
everywhere else.

**Ink dispatch was working in the same frame**, which is what ruled out the two
likelier-sounding causes. Frame 209 carries 4 sprites at ink 8 (channels 3, 4, 5,
40) and 5 at ink 36 (channels 2, 45, 46, 47, 48), and all nine key correctly:
Batz's head, eyes and mouth matte over his body, and the gold picture frame
`4:1` mattes around its own tilted outline on the channel *behind* the portrait.
So this was neither `backColor` resolution nor the wrong member being drawn.

### Why it surfaced on the second title

| root | scores | sprite records | ink 0 + `kTHasBlend` | share of that root's Copy records |
|---|---|---|---|---|
| `games/rating` | 81 | 847,431 | **27,914** | 18.8% of 148,747 |
| `games/piposh2` | 61 | 816,318 | 209 | 0.2% of 88,095 |
| `games/piposh` | 99 | 1,886,362 | 1,143 | 0.5% of 222,506 |

Two orders of magnitude more common in the title the port was not built on. In
Rating that is 883 distinct (container, member) pairs, every one a multi-bit
bitmap. This is the general defect surfacing the first time another title loads,
which is the failure `AGENTS.md`'s "build Director, not this game" describes.

### The fix

`key_for(sprite, member)` is now the reference's predicate rather than a lookup on
the ink: all twelve `needsMatte` inks (`channel.cpp:192-203`), the blended-and-
non-zero clause, the Copy-with-flag clause, bitmap-only, and the 1-bit exception
(`channel.cpp:218-223` — a 1-bit member gets a matte only under Matte ink proper,
and under Copy its blend amount is additionally forced to 0). Mask (9) moved
*off* matte keying: `getMask`'s `else if` arm takes the next cast member as a
separate 1-bit mask, which is a different mechanism, and the old code answering
`KEY_MATTE` for it was wrong in kind.

`texture_key` gained the has-blend flag (`sprite_geometry.gd`). Not housekeeping:
the flag now changes which pixels survive the decode, and `BATZEGOZ.dir` holds a
live collision — members `1:20` and `1:23` carry the flag while `1:21` and `1:22`
do not, all four are baked lines of the same dialogue balloon, and all four are
drawn Copy at one size.

**`hits_per_pixel` deliberately still answers false for these sprites.**
`BitmapCastMember::isWithin` (`castmember/bitmap.cpp:920-928`) tests per pixel for
`kInkTypeMatte` and nothing else, off the ink alone, so Director mattes this
sprite for drawing and still hits it across its whole box. Run the F1 outlines
over Egoz's portrait and it reads as a bug — a green "whole rect" box around art
with keyed-out corners. It is not one, and the comment at `hits_per_pixel` says
so; routing both decisions through one predicate is the tidy-up to refuse.

### Reproduce

```bash
godot --headless --path . --script tools/ink_blend_matte.gd -- --file BATZEGOZ.dir
godot --headless --path . --script tools/matte_survey.gd -- --file BATZEGOZ.dir
```

The first steps into `egozspeak1`, finds the Copy-with-blend sprite without being
told which channel it is on, and asserts the corners are keyed, the face is not,
the 190 pixels of enclosed white — the whites of the eyes — survive where paper
keying would eat them, clearing the flag brings the white rectangle back, and
`hits_per_pixel` still answers false. The second's third census, "records ScummVM
mattes and this port does not", reads 0.

### What no data proves

The ten arithmetic and Not- inks, and both halves of the 1-bit exception. Across
all three roots the only inks that appear are 0, 1, 8, 32 and 36, and **0 records
pair a 1-bit member with any matte-needing ink** — 0 under Matte and 0 under the
other eleven paths. Implemented from the reference and marked unverified at each
site. The blend-amount half of the 1-bit rule is in `blend_alpha` behind an
optional `member` argument that **no caller passes yet**: the four sites that ask
for an alpha (`stage_paint.gd`, `film_loop_view.gd` twice, `text_art.gd`) were
outside this change's file set, so they still get the member-blind answer. One
line each to wire up, and 0 corpus records reach it either way.

---

## 53. `field "x"` resolves by name across every cast, and the library the script named is thrown away

**Status:** open · **Area:** `scenes/director_preview.gd`

`lingo_field(name, _cast)` and `lingo_set_field(name, _cast, text)`
(`scenes/director_preview.gd:3199`, `:3206`) take the cast library the script
named and discard it — the parameter is spelled `_cast`. Both forward to
`_resolve_field(name)`, which asks `TextArt.resolve` for whichever library answers
first.

Found while tracing `docs/bugs-closed.md` 52. Rating's pickup writes
`field "inventorylist" of castLib "panel.cst"`, and the write does land on the
right member — `_resolve_field("inventorylist")` answers `[7, 147]`, `panel.cst`
member 147 — because the name happens to be unique across the five casts
`BLAEGOZ.dir` loads. That is luck, not resolution.

The library being part of the answer is a rule this port has already been bitten by
twice and has written down twice: `preview/members.gd` carries it ("the library is
part of the answer, not a hint"), and `lingo_set_member_prop`'s own comment says
the same thing about `set the text of member 12 of castLib 2` — which *does*
resolve by reference, one function below the two that do not. So the fix is to
route these two through `_resolve_member_ref(name, cast)` like their neighbour,
not to invent anything.

Not fixed alongside 52 deliberately: it is a separate defect with a separate
failure mode, and 52's change had no reason to touch field resolution.

**Unmeasured:** whether any container in any of the six roots actually ships two
same-named fields in two casts one movie loads. `field` names are written by
scripts rather than by the score, so the survey is a grep of the compiled sources
against the cast tables per movie, and nobody has run it. Until it has been run,
this is a hole with an unknown blast radius rather than a known wrong answer.
