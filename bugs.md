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
| 41 | closed: `member (<expr>) of castLib X` drops the library (`66baa6a5`) | closed: `play_suspends` flakes about half its runs (`b8466abb`) |

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
> **Entry 18 is about `MoviePlayer`, which is deleted**, and entry 8
> asks for `movie_context.json` / `walk_doorways.json` to be retired, which has
> happened. Both are candidates for closing outright rather than fixing. Entry 19
> was the third of them and has been closed rather than left standing:
> `grep -rn "MoviePlayer\|_apply_cursor" --include="*.gd" .` returns nothing at
> HEAD, so it named no code at all, and the question underneath it — does the
> cursor grow with the stage — has a live answer in `docs/bugs-closed.md` 19
> and 28.
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

## 77. Director's two Windows system palettes have no table, so 1,126 bitmap members draw in the wrong colours

**Status:** OPEN. Data, not engine — the dispatch, the resolution order and the
per-member choice are all built and asserted (`tools/palette_members.gd`); what
is missing is 768 bytes per table.

`director/director_palette.gd` generates System Mac and Grayscale because their
structure *is* their definition, and loads the rest from
`data/director_palettes.json`, which this tree does not ship. Anything naming one
of the others is warned about by name and substituted with system Mac. That was
theoretical until a title asked for one:

| root | movies stating -102 as their default | bitmap members naming -102 |
|---|---|---|
| `test-games/itamar-magichat` | 16 of 16 | 881 of 1,054 |
| `test-games/itamar-park` | 2 of 3 | 1 |
| `games/piposh-ru` | 0 | 129 |
| `games/piposh-en` | 0 | 108 |
| `games/piposh-dream` | 0 | 7 |

-102 is the Windows D5 system palette. `itamar-magichat` is the bad case by a
distance: five sixths of its artwork is indexed against a table nobody has, and
every pixel of it comes out of the 6x6x6 web cube instead. The Piposh members are
a handful of odds and ends and the six titles were pixel-identical before and
after the substitution either way, so nothing there regressed — but nothing there
is right either.

**Reproduce:**

```
godot --headless --script tools/palette_members.gd -- --root res://test-games/itamar-magichat
godot --headless --script tools/palette_survey.gd -- --root res://test-games/itamar-park --all
```

The survey's one failing check is `ChapTrfm.dir member 65 -> -102`.

**Fix:** lift both Windows tables (and Rainbow, Pastels, Vivid, NTSC, Metallic
while there) out of a Director installation or an implementation that carries
them, into `data/director_palettes.json` — the format is documented on
`DirectorPalette.PALETTE_DATA`, 1,536 hex characters per id. Do not reconstruct
them by eye: a palette that is nearly right is indistinguishable from artwork
that is nearly right, and the two get confused for weeks.

---

## 57. A whole-sprite puppet does not stop the score, so CHESS's second wheel plays one name and shows another

**Status:** OPEN in the tree, **root cause found and the fix measured**; the one
hunk that closes it is in a file two other sessions were live in tonight and is
written out below rather than applied. · **Area:**
`scenes/preview/sprite_state.gd:with_puppets`. · Reported from play as *"the
wheel, when I press it, plays the wrong sound on what lands there — the first
spin is right, the second is wrong, every time I tried."*

**Reproduce:**

```bash
godot --headless --path . --script tools/puppet_freeze.gd -- --root piposh2 --boot strtgame.dir
```

### The rule

`docs/DIRECTOR_ENGINE.md` §5.2. `Sprite::replaceFrom` copies the script
attachment and **returns** while `_puppet` is set, so from the claim onward the
score never writes that channel again — not its member, not its position, not its
size, and not its emptiness.

This port implements the *emptiness* half and only that half. `with_puppets`
carries a puppeted channel through frames whose score record for it is empty, and
on every frame where the score *does* carry a record it takes it:

```gdscript
		if not here.is_empty():
			channel.note_score(here)
			continue
```

So a puppeted channel is frozen exactly where the score was going to leave it
alone anyway, and follows the score everywhere else — which is the opposite of the
rule. `tools/puppet_persists.gd` is green throughout, because the only frames it
looks at are the frames where the score has let go.

### What the player hears

CHESS spins a name-wheel twice. Both runs are the same seven members on channel 8
put there by the score, and the same frame script over them
(`reference/lingo/CHESS/master/BehaviorScript 82.ls`, and 81, 86, 87):

```lingo
on exitFrame
  global soundspath, ches1
  if the mouseDown then
    repeat with i = 8 to 15
      puppetSprite(i, 1)
    end repeat
    sound playFile 1, soundspath & "art" & member(the memberNum of sprite 8).name & ".aif"
    ches1 = member(the memberNum of sprite 8).name
    go(marker(1))
  end if
end
```

The click freezes the wheel and names the sound from the member it froze, so **the
sound and the picture are one claim read twice**. Frames 138-144 are the first run
and 175-181 the second, identical but for where `marker(1)` lands: 145 carries no
channel 8 in the score, and 182 carries `jos`.

Every landing of both runs, clicked one frame at a time:

```
   f138: click froze pat    stage kept pat    sound artpat.aif
   ...                                                                  7 of 7 agree
   f175: click froze pat    stage kept jos    sound artpat.aif   <-- DIVERGED
   f176: click froze suz    stage kept jos    sound artsuz.aif   <-- DIVERGED
   f177: click froze map    stage kept jos    sound artmap.aif   <-- DIVERGED
   f178: click froze mrf    stage kept jos    sound artmrf.aif   <-- DIVERGED
   f179: click froze rin    stage kept jos    sound artrin.aif   <-- DIVERGED
   f180: click froze hez    stage kept jos    sound arthez.aif   <-- DIVERGED
   f181: click froze jos    stage kept jos    sound artjos.aif           1 of 7 agree
```

Six of the second run's seven landings show `jos` whatever was clicked, and the
seventh agrees only because `jos` is what the score writes. `the memberNum of
sprite 8` diverges with the stage, so `ches2` — which places the piece on the
board and picks its info card at `strtgame` — is the *sound's* answer while the
player saw the other one.

The timer, `random()`, the sound channels and marker arithmetic were all ruled out
by this trace: the `playFile` request is correct on every landing of both runs.

### The fix, measured but not applied

Two hunks, and **neither works without the other** — measured both ways. The claim
side is in `scenes/director_preview.gd:lingo_puppet_sprite` and is in the tree: it
takes a copy of the channel as the puppet claims it, because a port that rebuilds
channels from the score has nothing else to freeze. The score side is
`with_puppets`, below, and drops the score's record for a claimed channel instead
of adopting it.

```gdscript
static func with_puppets(sprites: Array, overrides: Dictionary) -> Array:
	var frozen: Dictionary = {}
	for number in overrides:
		var channel: Channel = Channel.at(int(number), overrides)
		if channel.is_puppet():
			frozen[channel.number] = channel.carried()
	if frozen.is_empty():
		return sprites
	# Channel order is depth order, and every caller relies on it: the hit test
	# descends from the end of this array and the painter walks it forwards.
	var out: Array[Dictionary] = []
	for value in sprites:
		var sprite: Dictionary = value
		if not frozen.has(int(sprite["channel"])):
			out.append(sprite)
	for number in frozen:
		var kept: Dictionary = frozen[number]
		if not kept.is_empty():
			out.append(kept)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["channel"]) < int(b["channel"]))
	return out
```

`Channel.note_score` has no caller left afterwards; the key it writes is written
once, at the claim.

With both hunks in, `tools/puppet_freeze.gd` is 14 of 14 landings green, and
`check.sh` plus `sound_wait sound_paths movie_tempo frame_events play_suspends
playhead_escape mouse_poll puppet_persists hilite trails sprite_drag
click_eligibility click_chain hotspots skip_state` are 15 of 15 PASS, unchanged
from the same list measured before it. `save_state` fails either way on an
unrelated unclassified field (`_member_hilite`).

### What this leaves

`docs/DIRECTOR_ENGINE.md` §5.2 still says the port's half-rule *is* the rule —
"a puppeted channel stays on the frame when the score's record for it is empty,
which is what the reconcile is skipped means for a port that draws from the
score's per-frame sprite list". It is not what it means, and that sentence is why
the other half was never written. Correct it with the hunk.

`tools/puppet_freeze.gd` is not in `gate.sh`'s `ALL`; add it when the hunk lands.

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

## 54. `play done` returns to the frame the `play` was on; the reference returns to the one after it when the `play` came from a frame script

**Status:** fixed · `lingo_play_push` records `_index + 1` when `current_sprite_num` is 0 -- the channel of the running chain element, which is the reference's `currentChannelId`. The latch it replaces is gone: taking `frameI++` means taking it instead of, not beside. Re-measured on the screen the latch was measured on (`piposh-dream` `fritz_room.json`, click 25,12): no ping-pong, 23 sprites, all six save slots clickable, and the panel reached one step sooner, which is what landing past the caller's frame looks like.

`Lingo::func_play` records where to come back to as

```
ref.frameI = getScore()->getCurrentFrameNum();
// if we are issuing play command from script channel script. then play done should return to next frame
if (_state->currentChannelId == 0)
    ref.frameI++;
```

`currentChannelId == 0` is "this script is not attached to a sprite channel" — a
frame script or a movie script. So in the reference a `play` written in a frame's
`on exitFrame` returns the playhead to **frame + 1**, and only a `play` from a
sprite behaviour returns to the frame itself. `lingo_play_push` records `_index`
in both cases.

That single line is why the reference never has to re-enter the caller's frame:
it lands past it, `Score::update` clears `_exitFrameCalled` beside the
`enterFrame` it then sends (`score.cpp:827-828`), and the caller's `exitFrame` —
the handler that wrote the `play` — is never dispatched a second time.

This port arrives at the same *outcome* by a different mechanism: `play done`
re-enters the caller's frame and carries `_exit_frame_called` across the entry so
that frame's `exitFrame` is suppressed once (commit 70c88e83, and now
`_pop_play_stack`). Both stop the interlude from restarting its caller. They are
not the same behaviour, and where they differ is visible:

* the port re-runs the caller frame's `on enterFrame`, and re-arms that frame's
  score sound, its palette and its transition through `sync_frame_entry`; the
  reference does none of those because it never returns to the frame;
* the port then leaves the frame *without* an `exitFrame`, so anything a room does
  on the way out of that frame is skipped once per interlude.

**Not fixed here, deliberately.** Taking `frameI++` means taking it *instead of*
the latch, not beside it — with both, the entry on frame + 1 would swallow a real
`exitFrame`. That unpicks a recent, measured fix (Piposh Dream's `ques.dir` 803
save panel) and the case cannot be re-measured without driving that screen, which
needs `--root piposh-dream` and a click.

**There is a way to drive it now**, which is what that sentence was waiting for:

```
godot --headless --path . --script tools/liveness_sweep.gd -- \
    --root piposh-dream --boot STRTGAME.dir --only ques.dir --click --verbose
```

`--click` presses every eligible sprite of the frame the watch ended on and
watches where each one leads, and the sweep's `ping-pong` verdict is that exact
symptom: two containers trading places, nothing on the clock, one of them drawing
nothing. So a change to `lingo_play_push` has a detector to be measured with
rather than only reasoned about.

**It is a detector and not yet the reproduction, and the difference is measured
rather than assumed.** Run as written, the sweep opens `ques.dir` at its start,
the watch settles around frame 13, and the click phase never reaches 803 — 20
states, no finding, one click deep from wherever the opening left it. Frame 803
is a save panel several steps into the movie, so getting there wants a marker
jump or a click chain the sweep does not have. What the command above *does* give
is a rule that fires on the shape the moment a run reaches it, and
`tools/liveness_sweep.gd:_assert_rules` asserts that on a synthetic
`ques.dir:803(4) <-> Saves.dir:27(0)` window every time it runs.

Whoever picks this up: the port also has
no `currentChannelId`, and `exitFrame` is dispatched only to the frame script
(`frame_loop.gd:advance` passes `_frame_script(_index)`), so today every `play`
reached from an `exitFrame` is the channel-0 case.

**Reproduce:** read `lingo-funcs.cpp:207-213` beside `director_preview.gd`'s
`lingo_play_push` / `_pop_play_stack`. The behavioural difference shows on any
frame whose `exitFrame` calls `play` and which also has an `on enterFrame` or a
sound in its score sound channels.

## 55. A queued `go` cancels the tempo wait as well; the reference cancels only the sound, click and video waits

**Status:** fixed · `FrameClock.release` now clears the sound, click and video waits and leaves the clock alone; `release_all` is the everything version and `skip_to_end` is its one caller, because the SKIP button is a player abandoning the scene rather than a script navigating inside it. §9.2 and `tools/frame_events.gd` both asserted the old reading and are corrected.

`Score::isWaitingForNextFrame` computes `goingTo = _nextFrame && _nextFrame !=
_curFrameNumber` and consults it in **three** of its four arms:

```
if (_waitForChannel)           { if (active && !goingTo) keepWaiting = true; else _waitForChannel = 0; }
else if (_waitForClick)        { if (!goingTo) { ...; keepWaiting = true; } }
else if (_waitForVideoChannel) { if (active && rate && !goingTo) keepWaiting = true; else _waitForVideoChannel = 0; }
else if (millis < _nextFrameTime) keepWaiting = true;      // <- no goingTo
```

The last arm is the ordinary frame clock: the tempo channel's frame rate, and its
`256 - tempo` seconds delay. A pending jump does not shorten it. `the delay`'s own
timer is the same (`score.cpp:681-692`): a jump skips the frozen-script processing
inside the delay branch and does not end the delay.

This port releases all four together. `lingo_go_frame` calls `_clock.release()`
with the comment "a pending `go to` cancels every wait — sound, click and delay
alike (§9.2)", and `tools/frame_events.gd` asserts it as a rule
("a queued `go to` cancels every wait").

Only reachable from a `go` issued *outside* the step loop — a click, a key, an
`idle` handler — because a `go` from `exitFrame` runs after the wait has already
expired. On a frame carrying a two-second tempo delay, this port jumps on the
click and the reference serves out the delay first. This corpus spends 74.0 s in
tempo delays across thirty-six frames (`tools/transition_survey.gd`), so the
window is not narrow.

Not changed here because it is a documented rule with a harness behind it, and
flipping it is the owner's call rather than an audit's: §9.2 would have to be
rewritten and `frame_events`, `playhead_escape` and `sound_wait` re-measured.

**Also unfixed, same family, smaller:** `Score::step` refuses to dispatch queued
input events while a jump is pending or while any Lingo state is frozen
(`score.cpp:332-335`, `!_movie->_inputEventQueue.empty() &&
!_window->frozenLingoStateCount()`). This port delivers input from Godot's
`_input` the moment it arrives, with no such gate, so a click landing between a
`go` and the step that honours it is delivered where Director would have dropped
it.

**Reproduce:** read `score.cpp:400-441` beside `director/director_frame_clock.gd`
and `director_preview.gd:lingo_go_frame`.

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

**Reproduce:** read `lingo/lingo_interpreter.gd:698-708` (`reset_steps`) beside
`:1634` (`_fail`) and `scenes/preview/scripts.gd:75`. Then run any movie and note
that no tool in `tools/` can report a fault that happened two dispatches ago.

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

## 67. A bitmap member's palette is read from the D4 offset, so every clut id in the corpus is measured as the field next to it

**Status:** open · **Area:** `director/director_cast.gd:356`, `tools/palette_survey.gd`,
`scenes/preview/members.gd:243` · found while ruling the palette out of
`docs/bugs-closed.md` 66

`_parse_specific` reads a bitmap's palette from the specific block at **offset 24**:

```gdscript
out["palette_id"] = _be_i16(spec, 24) if spec.size() >= 26 else -1
```

That is the D4 layout. `castmember/bitmap.cpp` puts a second field in front of the
id from D5 on:

```cpp
int clutCastLib = -1;
if (version >= kFileVer500) {
    clutCastLib = stream.readSint16();   // offset 24
}
int clutId = stream.readSint16();        // offset 26 on D5+, 24 on D4
if (clutId <= 0)                         // builtin palette
    _clut = CastMemberID(clutId - 1, -1);
```

Every container in both corpora is D5 or later — `rating`'s config word is `0x073a`
— so the port has been reading `clutCastLib`. Measured over `MANAEGOZ.dir`,
`MANAGER.cst`, `HOTEL.cst`, `HOTEL2.cst` and `Panel.cst`, offset 24 is `-1` in all
941 bitmap members with a 28-byte specific block and offset 26 is `0` in all 941.

**Two errors, and they cancel.** The offset is wrong, and the `clutId - 1`
adjustment the reference applies is missing — Director stores the first built-in at
0 and counts down, while a *frame's* palette channel uses 0 for "no change" and
starts the built-ins at -1. Read correctly, `0` at offset 26 becomes
`kClutSystemMac`; read as it is now, `-1` at offset 24 is *labelled* system Mac by
`BUILTIN_NAMES` and happens to be the same answer. So the port draws the right
palette for the wrong reason, and would keep drawing it for a title that named a
different one.

**What this invalidates.** `tools/palette_survey.gd` reports "0 members name a
palette other than system Mac" across 86 containers and 11,520 bitmaps, and
`director/director_palette.gd`'s header cites that number as the reason system Mac
is the only verified table. The *conclusion* survives — offset 26 also reads system
Mac everywhere it was checked — but the measurement behind it does not, and the
sweep has to be re-run against the corrected offset before the header can go on
claiming it. `the palette of member` (`preview/members.gd:243`) answers from the
same field and is wrong by the same two steps.

Nothing in either corpus renders differently once this is fixed, which is exactly
why it is filed rather than folded into another change: it is a decode bug with no
symptom, and the first title that ships a Windows or custom palette is where it
stops being free.

**Reproduce:** for any bitmap member, slice the `CASt` specific block and print the
`i16` at 24 and at 26 beside `castmember/bitmap.cpp`'s D5 branch.


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

## 81. Cast type 12 (`richText`) has no arm in `_parse_cast`, so a rich-text member has no size and its sprite is drawn at the score's residue

**Status:** open, latent · **Area:** `director/director_cast.gd:_parse_cast` ·
**another agent is working on this right now**, so read the tree before starting

`_parse_cast`'s `match type_code` has arms for 1 (bitmap), 3 (field), 2 (film
loop), 8 (shape), 11 (script) and 14 (transition), and stops there. There is no
12. Every other field of the member dictionary is initialised before the match —
`width` and `height` at **0** — so a `richText` member is decoded as a member
with no dimensions and no registration point.

Two things downstream already have opinions about that, and neither is a guess:

- `TYPE_NAMES` *does* name 12 `richText` and `DRAWING_TYPES` *does* include it,
  so the cast layer marks the member as art the renderer is expected to draw
  (`"drawing": true`) and then hands over no geometry to draw it with. That
  combination exists for no other type.
- `scenes/preview/sprite_geometry.gd:drawn_size` reads a natural size of 0 on
  either axis as "a member this cast does not describe, or one whose geometry did
  not decode", and returns the sprite's own rect. That rect is the *score's*
  stored one, which this file and `docs/bugs-closed.md` both record as authoring
  residue rather than a size anybody authored — it is what put Piposh 1's money
  17px off-centre in 33,686 sprite records. So the one member type with no
  natural size to check the residue against is the one that gets handed it.

`scenes/preview/sprite_art.gd:texture_for` returns null for anything that is not
a bitmap or a shape, so nothing is drawn either way today; the geometry is what
will be wrong first when something is.

**Latent, and filed anyway.** `docs/DIRECTOR_ENGINE.md` records that buttons
(type 7) and rich text (type 12) "do not occur in this corpus at all", and no
member of `test-games/itamar-magichat`'s eight containers is one either — the
types found there are bitmap, field, sound, shape, script, palette, transition
and 15. Per `AGENTS.md`, 0 uses is not a reason for the arm to be missing; it is
the reason nothing has noticed.

Reproduce (there is nothing in the tree to point it at, which is the entry):
read `director_cast.gd`'s match, then `sprite_geometry.gd:drawn_size`, and follow
a `width` of 0 through both.

---

## 82. Cast type 15 (`kCastXtra`) members are skipped by the renderer entirely, and Magic Hat's `yes`/`no` buttons and its intro video are six of them

**Status:** open · **Area:** `director/director_cast.gd` (`TYPE_NAMES`,
`_parse_cast`), `scenes/preview/sprite_art.gd:texture_for` · found while reading
`test-games/itamar-magichat` for 79

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

---

## 83. A sprite behaviour is dispatched as a plain script with `me = null`, so its `property` names have nowhere to live and the score's per-sprite initialiser is never applied

**Status:** open · **Area:** `lingo/lingo_interpreter.gd:_invoke` and its
`"property"` arm, `director/director_score.gd:_read_interval`

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

## 84. Digital video (cast type 10) is unimplemented, so Magic Hat's logo movie plays nothing and then skips itself on its first tick

**Status:** open · **Area:** `scenes/preview/media.gd`,
`director/director_cast.gd`

`media.gd` states the gap plainly and correctly — there is no QuickTime or AVI
decoder in this port and Godot supplies none, so a `#digitalVideo` member answers
`the mediaReady` FALSE, a duration of 0, no cue points and no tracks, "which is
exactly what Director answers for a digital video whose file is missing or whose
codec is not installed". Nothing about that reasoning is wrong. What is now wrong
is the sentence beside it: "**no member in any of the six titles is a digital
video**, so there is nothing to measure a layout against". There is a seventh
title in the tree and it is built around two of them.

`test-games/itamar-magichat/logo/logo.dir`, all six members:

```
   1  script       start movie + quit logo
   2  script       run movie
   3  script       compedia logo
   4  script       Check avi
  27  digitalVideo prelogo
  28  digitalVideo logo
```

and the two scripts that are only about them:

```lingo
on enterFrame                      -- "compedia logo"
  global FilmLen
  FilmLen = member("logo").duration
  sprite(3).movieTime = 0
  sprite(3).movieRate = 1
end

on exitFrame                       -- "Check avi"
  global FilmLen
  if sprite(3).movieTime >= FilmLen then
    QuitFilm()                     -- go(the frame + 1)
  else
    go(the frame)
  end if
end
```

`the duration of member` is 0 for a member with no media, and `the movieTime` of
a sprite that is not playing stays where it was put — so `0 >= 0` is true on the
**first** `exitFrame`, `QuitFilm` runs, and the logo is left behind before a
frame of it could have been shown. The failure is not a hang and not an error; it
is the movie's own guard being satisfied by two zeroes.

The media is on disk beside the movie (`logo/logo.avi`, `prelogo.avi`) and
`startMovie` points the member at it explicitly —
`member("prelogo").fileName = "prelogo.avi"` — so nothing is missing here except
a decoder. `docs/ENGINE_TODO.md` carries the member's specific block as an open
item on the grounds that no member in the corpus is a digital video; these two
are the sample that argument was waiting for.

Reproduce:

```
godot --headless --path . --script tools/director_extract.gd -- \
    --root res://test-games/itamar-magichat --file logo/logo.dir --out <dir>
```

`members.txt` names both, and `scripts/` holds the four handlers above.

---

## 85. A channel the score does not carry never draws, however much a script writes to it — so Itamar Park's arcade runs with no food, no animals and no enemies

**Status:** FIXED for the draw, and the objects are on screen; **their vertical
position is a second gap and it is 94, not 89** · **Area:**
`preview/channel.gd:carried`, `preview/sprite_state.gd:with_puppets`

**Correction, and it undoes this entry's central measurement.** The claim below
that channels 20-23 are "never carried by the score" is an artifact of the tool
that measured it: `tools/scratch/chanscan.gd` reads `Score.frame()`, and
`_snapshot` drops any record that names a member and states a zero size. All
eighteen object channels *are* recorded, for 178 frames each, naming `ObjBlnk`
at `locH` -1000 and at the three row `locV` values 340, 210 and 110 — which is
the vertical position this entry left missing. See 90 for the bytes. The fix
below is still right and still needed, because a script may give a channel a
member the score never gave it; what is wrong is the reasoning that no record
existed to retain. `tools/scratch/rawchan.gd` prints the records `frame()` hides.

A script that gives a channel a member now makes that channel live, which is the
reference's rule and not a special case there: `_channels` holds one `Channel`
for every channel however few the frame carries, `Sprite::setCast` raises the
`kAPCast` auto-puppet (`sprite.h:41`, `channel.cpp:649`), and `setClean` then
refuses to replace the sprite from the score (`channel.cpp:534`). This port draws
the score's per-frame sprite list, so "keeps being" had to be spelled out, and it
had been spelled `is_puppet()` alone — the explicit half only.

**A member is what makes a channel live, not any write at all.** A script that
writes only a position to an empty channel has said nothing about what to draw
there, and inventing something would put a sprite on stage no title asked for. So
the test is the cast group of `FIELDS`, the same three rows the merge treats as
the cast swap.

Measured at `torfim.dir` frame 24 (`AntPlay`), the four sampled object channels
now appear in `frame_sprites()` with real rects where they previously appeared
only in `_overrides`:

```
ch20 1:60@(93,0)   ch21 1:60@(-341,0)   ch22 1:177@(-1003,-12)   ch23 1:175@(-1565,-12)
```

`tools/scratch/chanscan.gd` confirms why a synthesised base was needed rather
than a remembered record: channels 20-23 are **never carried by the score** in
that movie, so there is nothing to retain. The base is `Sprite`'s own constructed
state in the reference — no cast, ink 0, default colours, and a zero size that
the cast swap replaces with the member's natural one.

## 86. `play frame the frame` re-enters its frame four times per rendered tick, and the play stack grows by four entries a tick for as long as the movie runs

Itamar Park's arcade loop is `BehaviorScript 24 - play frame`:

```lingo
on exitFrame
  idle()
  KeepBackSoundGoing()
  play frame the frame
end
```

Director grows a stack here too — `Lingo::func_play` pushes one entry per call
(`lingo-funcs.cpp:212`) and nothing pops it until `play done` — so unbounded
growth is the movie's own design and not the finding. The finding is the **rate**:
`_play_stack` gains four entries per `process_frame`, so the frame's `exitFrame`
runs four times per rendered tick. Measured at `torfim.dir` frame 24 (`AntPlay`),
one entry per step:

```
step 470  play_stack=319
step 471  play_stack=323
step 472  play_stack=327
step 473  play_stack=331
```

The movie's tempo there is 80 fps against a 60 fps display, so at most two score
steps per rendered frame can be owed. The other two are the port re-entering the
frame within one step, and the arcade therefore runs at roughly twice the speed
the score asks for — which the title partly hides, because `calcStep` regulates
its scroll against `the ticks` rather than against the frame rate.

Not diagnosed further. The suspects are `lingo_go_frame`'s `_in_exit_frame`
branch, which writes `_index` directly and queues no jump, and
`frame_loop.advance`, which then does not know the frame was re-entered.

Reproduce: the command in entry 85, and read the `play_stack=` column.

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

## 90. `soundBusy` is paced by the audio device and not by the sound, so every speech wait in the corpus stretches by whatever the device is slow by

**Status:** open · **Area:** `autoload/audio_director.gd`

`sound_busy` is one line — `return player.playing` — and `playing` is retired by
the **audio server**, when its mix thread has consumed the stream. So the flag
measures the output device's throughput, not the sound's length. On hardware the
two are the same number to within a fraction of a percent, which is why this can
sit unnoticed: it looks like an identity rather than like a choice.

They come apart where there is no hardware. Measured on one 0.63s file
(`fx/bang`), by `tools/sound_rate.gd`:

```
   Windows runner    <= 1.00x real time   (passes a 1.0x tolerance)
   developer Mac        1.12x             (0.71s for 0.63s)
   macOS runner         2.09x             (1.32s for 0.63s, over 67 polls)
```

A movie cannot observe this as a sound that is slow, because it never asks how
long a sound is. It asks `soundBusy`, and this corpus's speech is built on
`BehaviorScript 250`'s shape:

```lingo
on exitFrame
  if soundBusy(1) then go(marker(0))
end
```

The talking animation loops back to its own marker for as long as the channel is
busy. So a `soundBusy` that runs at half speed does not make the speech slow — it
makes the **playhead** loop twice as many times, and the player watches a mouth
move for twice as long as the line it is speaking. Every frame budget downstream
of a speech wait is wrong by the same factor.

This is what `puppet_persists` had been failing on, on every macOS runner, while
passing on Windows and on a developer Mac. `exitforest3`'s `dnzclicktalk` returns
in 295 score ticks here and needs more than 400 there; with `--ticks 700` the
macOS runner passes. The harness was right and its budget was right: the two
machines' score-tick *rate* is identical (7.7/sec vs 7.8/sec), and the clip's
pacing per marker jump is 14 ticks on both. What differs is how many jumps the
wait takes — 27 markers in 400 ticks and still inside the clip, against 19 in the
295 it takes here.

Three things this was mistaken for first, each measured and none of them it:

- **a wall-clock guard.** The watch's `--watch-ms` was blamed and doubled; the
  failing run spent 52s of 480,000ms.
- **machine speed.** Score ticks are tempo-gated, so the rate is the same on any
  machine. The engine's *frame* rate is not the same — 11.3 process frames per
  score tick on the runner against 23.7 here — but nothing in the clip is paced
  by frames, and the `idle` tally that shows it is a red herring.
- **a missing audio device.** `--audio-driver Dummy` on the runner fails too, and
  Dummy passes here, so the driver is not the variable. The runner is slow with
  both.

The audio index is identical on both machines — 3142 files, 315 ambiguous tails —
so this is not a data gap and not a case-sensitivity difference in path
resolution.

`tools/sound_wait.gd` cannot catch it and is not wrong for that: it asserts that a
channel is busy if and only if a sound the script asked for is playing on it,
which is the *logic* of `soundBusy` and is correct on every machine. The clock is
a separate rule, and `tools/sound_rate.gd` is what asserts it.

The fix is a ceiling rather than a replacement: record the stream's own length
when `_start` plays it, and answer `player.playing and now < that`. Nothing
changes where the device is honest; a device that lags can no longer hold a
movie. Two details make it cheap here — nothing in this engine's audio path loops
a stream or touches `stream_paused`, and `_start` is the single funnel both
`play_file` and `play_stream` go through. `take_cues_passed` reads
`get_playback_position`, so on a slow device it would still lag behind a
wall-clock `soundBusy`; no script in the corpus names a cue point, so that is
recorded rather than solved.

Reproduce:

```
godot --headless --path . --script tools/sound_rate.gd -- --tolerance 1.0
gh workflow run nightly.yml --ref main \
    -f entries='sound_rate:--tolerance@1.0 puppet_persists:--label@exitforest3'
```

---

## 94. A score sprite record that names a member and states a zero size is dropped, so eighteen of Itamar Park's arcade channels lose the only vertical position they ever get

**Status:** open · **Area:** `director/director_score.gd:_snapshot`, the
occupancy test · found while closing 89, and **it is what 85 and 89 both
misattributed**

`_snapshot` decides whether a channel is occupied with

```gdscript
if cast_id <= 0 or width <= 0 or height <= 0:
    continue
```

The size half has no counterpart in the reference. `Frame` reads every channel's
record into `_sprites[]` and `Score` builds one `Channel` per channel whatever
the record says; the only emptiness test anywhere near the render walk is on the
**cast id** (`score.cpp`, `channel.cpp` @ ScummVM 805f259a). A record that names
a member and states a zero size is a sprite there, and it is a sprite that
carries a position.

**Itamar Park's arcade is built on exactly that record.** Channels 20-37 are
recorded in `torfim.dir` for 178 frames each, all naming member `1:60`
`ObjBlnk` — a deliberately 0x0 bitmap, the title's own device for "occupy this
channel and draw nothing" — at `locH` -1000 and at three `locV` values that
repeat down the channels:

```
ch20 10 24 ff 00 0001 003c 0000 07f4 0154 fc18 0000 0000 ...
                       ^cast 60   locV 0x0154=340  locH 0xfc18=-1000  w=h=0
ch21 ... locV 0x00d2 = 210
ch22 ... locV 0x006e = 110
ch23 340   ch24 210   ch25 110   ...  through ch37
```

340, 210 and 110 are the arcade's three ice rows, and they are the **only**
place the objects' vertical position exists. Nothing downstream needs changing to
use them: `docs/bugs-closed.md` 91 already made the auto-puppet merge prefer the
frame's own record over a synthesised one, so admitting the record is enough for
the script's `locH` to land on top of the score's `locV`. `MovieScript 6 - play handlers1`
writes `sprite(i + j).locH` and nothing else; `MovieScript 7`'s `ChangePlayer`
sets the *player's* `locV` from `gPlayerLocVList` and `MovieScript 10`'s
`setSubLevelNum` reads an object's `locV` back
(`sprite(kSubNumSpNum).locV = sprite(getFlag(#FlagOnStage)).locV - 55`), so the
score is where the rows are authored and a script consumes them. With the record
dropped, `sprite_state.with_puppets` synthesises a base at `locV` 0 and every
object draws straddling the top edge of the stage.

Measured, by removing the size half of the test and playing the level in
(`tools/scratch/parkarcade.gd`, same command as below). Before:

```
ch20 1:51  AntAnimA1 loc(-226,0)   rect(-349,-46 123x93)
ch21 1:60  ObjBlnk   loc(-480,0)   rect(-480,0 0x0)
ch22 1:174 AntFood4  loc(-1091,0)  rect(-1139,-15 48x30)
```

After:

```
ch20 1:173 AntFood3  loc(-139,340) rect(-189,328 50x25)
ch21 1:52  AntAnimA2 loc(-644,210) rect(-760,167 116x87)
ch22 1:177 AntFood7  loc(-1087,110) rect(-1137,98 50x25)
```

Channels 44, 53, 54, 55, 59 and 60 — `kBonus3SpNum`, `kCollisionSpNum`,
`kSubNumSpNum` and `kBonusScoreSpNum`, all of them script-driven and all of them
recorded as `ObjBlnk` — arrive with their authored positions in the same run.

**Why it is filed rather than fixed.** Removing the size half admits 4,506
records in `itamar-park` and **370 across the six shipped titles**
(`tools/scratch/zerosize.gd`, out of 8,057,628 member-bearing records), and
three of those groups name a member with real pixels, where `drawn_size` would
then draw the member's natural size on a channel that draws nothing today
(`tools/scratch/zerosize2.gd`):

```
piposh / -en / -ru  Hezroom.dir ch6   1:245  d6          0x0      x10 each
piposh-dream        hatul2/3 ch10,27,32  1:86            1x1      x3
piposh-dream        meet7.dir ch15    12:5               48x31    x135
piposh2             GOLDDEAD.dir ch1  1:3 a1             640x400  x26
rating              11 movies ch48    2:33 GlobalTime    79x24 field  x176
itamar-park         torfim.dir 25 channels  1:60 ObjBlnk 0x0      x4506
```

`GOLDDEAD.dir` ch1 is a full-stage bitmap on 26 frames and `rating`'s ch48 is
the `GlobalTime` field on 176 — both would newly appear, and whether they should
is a question about `sprite_geometry.drawn_size`'s fallback rather than about
this test. Nobody has looked at those three on screen. That is the work this
entry is asking for; the diagnosis above is complete and the blast radius is
measured.

**This corrects two earlier entries.** 85 says channels 20-23 are "never carried
by the score", and 89 says Park's objects sit at `locV` 0 because
`the regPoint of member` was read-only. Both are wrong and both were measured
through `Score.frame()`, which is the post-filter view — `tools/scratch/chanscan.gd`
reads it, so "NEVER carried by the score" is what it prints for any channel whose
records are all zero-sized. `tools/scratch/rawchan.gd` prints the bytes instead.
`defReg`, the handler 89 blamed, occurs **twice** in `torfim.dir` — once as
`on defReg` and once in its script's name table — and is called from nowhere;
its 28 members are already anchored right-middle in the file, so running it would
change nothing. `the regPoint of member` was a real gap and is fixed (89, now in
`docs/bugs-closed.md`), and fixing it moves none of these objects.

Reproduce:

```bash
godot --headless --audio-driver Dummy --path . --script tools/scratch/rawchan.gd -- \
    --root res://test-games/itamar-park --file torfim/torfim.dir --frame 24 --from 18 --to 40

godot --headless --audio-driver Dummy --path . --script tools/scratch/parkarcade.gd -- \
    --root res://test-games/itamar-park --file torfim/torfim.dir \
    --steps 3000 --clicks "play+10:11" --until antplay --from 18 --to 60
```

The first prints the records above. The second plays the level select in, clicks
level 1, and prints every object channel's member, `loc` and drawn rect once the
arcade is running; the `loc(...,0)` column is the bug.

---

## 93. A behaviour gets its instance from `beginSprite` and from a click, and from nothing else: `exitFrame`, `enterFrame` and `prepareFrame` still run against a bare script

**Status:** open · **Area:** `scenes/preview/scripts.gd:dispatch`,
`lingo/lingo_interpreter.gd:call_handler` · found while closing 87

`bugs.md` 87 made a behaviour an instance for the two messages it added, and
`scenes/preview/event_chain.gd` already did it for the mouse and key chain. The
frame events did not join in. `Scripts.dispatch` calls
`interpreter.call_handler(handler, [], script)` with the default channel 0, and
`call_handler` reads that as "not a behaviour" — so `on exitFrame me` in a
behaviour-channel script binds `me` to VOID, while `on beginSprite me` in the
script attached to the *same* score row binds it to a real object.

Director has no such split. A behaviour-channel script is one instance for the
life of its span and every message it receives arrives on that instance, which is
what makes the standard idiom work:

```lingo
property pSomething
on beginSprite me
  pSomething = ...
on exitFrame me
  if pSomething then ...
```

Here the property written in `beginSprite` is on an object `exitFrame` never sees.
Nothing in the six shipped titles is known to depend on it yet — this was found by
reading, not by a symptom — but it is the same defect `87` was, one message along,
and it is why `docs/ENGINE_TODO.md` still lists `the scriptInstanceList of sprite`
as `inert`.

**The fix is not "pass channel 0"**, and that is the whole difficulty.
`call_handler`'s channel-0 default is what stops a *movie* script and an ordinary
frame script from acquiring a `me` they have never had; `behaviour_instance` takes
an explicit `script_channel` flag for exactly that reason. What the dispatcher
needs is to know whether the script it is about to message is a behaviour-channel
script or a plain frame script, which `frame_loop.gd:sprite_behaviours_at` already
computes and `_begun_sprites` already records — so the join is available, and this
entry is the decision to make it deliberately rather than as a side effect of 87.

The same gap covers `sendSprite`/`sendAllSprites`, which still message a
behaviour's script directly (`docs/ENGINE_TODO.md`); after 87 those two and the
frame loop now disagree about what `me` is for the same sprite.

Reproduce by adding a case to `tools/sprite_lifetime.gd`: on any movie, run a
frame whose behaviour-channel script declares both `beginSprite` and `exitFrame`
and compare the object identity `me` binds to in each. `magichat.dir` frame 42's
`BehaviorScript 34 - album loop` declares `enterFrame`, `exitFrame`, `mouseUp` and
`endSprite`, which is four of the five doors in one script.
