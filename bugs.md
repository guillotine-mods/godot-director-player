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
reference and reclassified as not a bug.

**What that sweep left below is deliberately not counted here any more.** The
sentence that used to end this paragraph said "16 open entries, 7 narrowed ones and
4 not-a-bug signposts" long after the file held two numbered entries, which is this
document's own rule about numbers in prose broken inside the paragraph that states
it. Entries are added and moved by different sessions and the count is stale the
next day. `grep -c '^## [0-9]' bugs.md docs/bugs-closed.md` answers it in the state
the tree is actually in.

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

## 123. NARROWED. The abort is not implementable from the call site, because the only discriminator available is a statement about ScummVM's coverage rather than about Director's language

**Status:** open as a divergence, **measured and made visible at `f3bbd036`**; the
control-flow change deliberately not made · **Area:**
`lingo/lingo_interpreter.gd:_call`, `lingo/lingo_reference_names.gd` · filed
2026-08-21, narrowed 2026-08-22

A call to a handler nothing defines: the reference aborts, this port returns
`result if result != null else 0` and the enclosing handler runs to its end. **The
difference is not the return value, it is the statements after it**, and it is silent
in both directions.

### What `_abort` actually unwinds — this entry understated it

Not just the statement after the call. `_abort` is `Lingo::execute`'s loop condition
*and* the flag whose epilogue pops **every remaining `CFrame`**
(`reference/scummvm/lingo/lingo.cpp:634`, `742-748`), so Director drops everything left
in every caller too. It is cleared at the end of whichever `execute()` saw it — not at a
frame boundary, not at the next event. And `LC::procret` sets the *same* flag on the
ordinary return from the outermost handler (`lingo-code.cpp:1901`, `1909`), so `_abort`
means **"stop the loop"**, not "an error happened".

**"The dispatch" is one `execute()` call and not one event**, which is the part that
decides the shape of any fix: `b_call`, `callBehaviorHandler` and `sendAllSprites` each
re-enter `execute(frame)` (`lingo-builtins.cpp:1891`, `3486`, `3545`), so an abort inside
`call(#msg, obj)` unwinds only as far as that builtin. **This port has no such boundary
at all**, so implementing the abort naively would unwind further than Director does.

### The measurement, and why it stops the fix rather than sizing it

`tools/undefined_calls.gd --all`, 651 containers over six roots: **91,737 call sites —
14,162 resolved by a handler, 77,556 held by the reference's four name tables, and 19 in
neither, across 7 distinct names.** Per root: piposh 0, piposh2 6, piposh-en 3,
piposh-ru 2, piposh-dream 3, rating 5.

Nineteen sites is small enough that an abort would not truncate the corpus, so the risk
this entry was written around is not what stops it. **What stops it is that one of the
seven names is `gotoNetPage`** (2 sites) — real Director NetLingo, and absent from all of
`reference/scummvm/lingo/`. So the discriminator available at the call site is
structurally a statement about *ScummVM's coverage of Director*, not about Director's
language, and one name in seven would abort a call the original resolved fine.

The mirror case is real and in the same measurement, which is what makes this a genuine
bind rather than a reason to relax: **`rating`'s `mraker`** (2 sites) is `go(mraker(1))`
sitting directly above a correct `go(marker(0))` — an authoring typo, exactly the case
the reference aborts and should. **Nothing at the call site separates it from
`gotoNetPage`.** This is also the reproducing case the entry said it lacked.

### What landed instead

Outcome: make the divergence **visible** without changing control flow. A new
`UNDEFINED_HANDLER` diagnostic category; `_call` splits on
`lingo/lingo_reference_names.gd` (360 names); the undefined case goes through `_fail` so
it prints; `scenes/preview/debug_report.gd` names it. **Reference-known names answer
exactly as before**, so `getPref`, `externalParamName` and `externalParamValue` — the
fall-through's load-bearing consumers — are untouched.

`tools/undefined_handler.gd` (12 checks, in `ALL`) asserts the split. Confirmed able to
fail: reporting `BUILTIN` at the fall-through reds two checks, `_aborting = true` there
reds the third. Its "port hole" case **first passed vacuously** on `getPref`, which the
host actually binds, so it never reached the fall-through; it now asserts a probe got
there first.

### The nineteen, read by hand, and where the divergence would actually bite

  * **`mraker`** (rating, 2) — the typo case above.
  * **`gotoNetPage`** (2) — the blocker above.
  * **`dont(pass)`** (5) — last statement in its handler, so an abort would be **inert**.
  * **`www` / `setmoviepath`** (8) — the jokes path, a shipped data gap.
  * **`displayobject` / `gamad`** (2) — and `displayobject()` **has two statements after
    it**, which makes this the one site in the corpus where the divergence changes what
    runs rather than only what is returned.

So of nineteen sites, the abort is inert at five, wrong at two, and consequential at
about two. That distribution is the argument against implementing it, more than the
count is.

### Three scope notes, so the next session does not re-derive them

**`_aborting` already exists and is otherwise an exact match** — `_exec_from` tests it
per statement and `reset_steps` clears it where a dispatch begins. What is missing is
only the nested-`execute()` boundary: `_broadcast` is an ordinary GDScript call, so the
three re-entering builtins have nothing to stop at.

**The fall-through's consumers are a class, not a list.** Beyond `getPref`,
`externalParamName` and `externalParamValue`, four more were found reaching it live just
by asking — `xFactoryList`, `idleLoadDone`, `showXlib`, `showResFile`. The class is
"every reference-known name this port has not bound yet", which is why the split is on
the reference table rather than on an enumeration.

**Bare-word statements are a separate, untouched half: 218 of them.** They go through a
`_read_var` path that has no abort in it at all, so nothing above applies to them and
nobody has looked.

### Honest coverage gap in what landed

**No corpus site fired at runtime in any run driven.** `liveness_sweep --only
NAVIGATE.dir --click` and `--only BATZROOM.dir --click` both stayed silent, because the
`mraker` arm sits behind `if not soundBusy(1)`. So the new `UNDEFINED_HANDLER` print is
exercised by the synthetic harness only — consistent with this entry's standing note that
no container is *known* to trip this at runtime, but it means the diagnostic itself has
never been seen firing on real data.

### What would settle it

A name table sourced from Director's own documented vocabulary rather than from
ScummVM's implemented subset. With that, `gotoNetPage` is known-and-unimplemented and
`mraker` is undefined, the two cases separate, and the abort becomes implementable —
with the `execute()`-boundary caveat above, which is its own piece of work.

## 128. PARTLY FIXED. The sweep's budget no longer pays for held ticks; its wall-clock ceiling now binds instead, and two thirds of Piposh Dream still cannot be judged

**Status:** budgeting half **FIXED at `8370533e`**; the ceiling half open ·
**Area:** `tools/liveness_sweep.gd`, `WATCH_CAP_MS` · filed and half-closed
2026-08-21

The entry as filed: the watch budget was spent in score ticks and a held tick cost
the same as a live one, so the sweep paid its whole watch for a hold it had already
excused, and `visited: 52 of 52` covered almost no gameplay. `--ticks` now buys
**unexcused** ticks only, through one predicate (`hold == "" and stride <= 1`) shared
by the budget, the run building and a new `_longest_run`.

**The control that should have been run before the entry was written, and was run
before the fix.** The same command at `--ff 8` — the movie's own rate — moves movies
held on *every* watched tick from 19 to 1 and distinct states summed over 52 watches
from 1,851 to 2,954, for 3.4x the wall clock. So the reading was right.

**What the fix bought, with the unit change stated because the denominator moved from
120 ticks to 550+:**

| | before | after |
|---|---|---|
| held on every watched tick | 19 | **0** |
| held on wait-for-sound at all | 42 | 42 |
| >= 83% of that movie's *own* ticks | 32 | 27 |
| clicks landed | 20 | 26 |
| `go` / `marker` / `sound` / `soundbusy` | 5/4/2/136 | **41/39/7/580** |
| cursors installed | 0 | **0** |
| wall clock | 379 s | 946 s |

`go` 5 -> 41 and `marker` 4 -> 39 is the sweep reaching the frames where rooms decide
things. **">= 100 of 120" from the original entry no longer means anything** and is
not comparable across the change; that is why the third row is a fraction.

### What is still open, and it is the same defect one layer out

`WATCH_CAP_MS` now binds where `--ticks` used to. On `piposh-dream`,
**`unjudged: 34 of 52`** and 28 of 52 watches hit the 20 s ceiling, depth mean 62 of
120 asked. So two thirds of the title still has no window any rule was read over —
the sweep now *says so*, which it did not before, and that is the whole of the
improvement in coverage honesty. Raising the cap is the obvious next move and it
multiplies a corpus cost that is already **2.5x** — `piposh-dream` 946 s against a
379 s baseline, both on one machine, which is the only ratio here worth quoting.
`piposh` ran 99 of 99 in 2,557 s and its 589 s "before" was measured on a different
machine, so **there is no 4.3x**: that figure appeared in an earlier draft of this
entry and in the report it came from, and it divides one machine's number by
another's. The absolute 2,557 s stands; the ratio does not.

The suite is not what pays: the `ALL` entry is `liveness_sweep:--limit@12` and it
went 72 s -> 92 s, 20 s on a 1,918 s run. Which is why the fix landed unconditionally
rather than behind a flag — a flag defaults one way and whichever way it defaults is
what everybody measures.

### Two of this entry's own numbers did not reproduce, and both readings were mine

Recorded because both are the shape this file's header warns about — a number that
reads as measured, carrying no note of what it was measured at.

**The clicks and held-movie figures were measured before `1e760a51`.** That commit
stopped a failed `playFile` from holding `soundBusy`, and `git log -S "is on the disc
elsewhere"` returns it and nothing else, so a run printing that diagnostic is
post-fix — the re-measured baseline prints it for **59 distinct requests** over
`piposh-dream`. Fifty-nine requests that used to resolve to a wrong take and *play*
now play nothing, so `soundBusy` is false where it was true: fewer held ticks, more
live ones, more eligible clicks. Direction and sign both match this entry's 46 -> 42
held and 9 -> 20 clicks. **Unproven**, only because the original run cannot be dated
from its text; the experiment that settles it is the same sweep at `1e760a51~1`, and
it wants a separate worktree (a `.godot` seed plus a pack build) rather than a
checkout of a tree two sessions share.

**The cursor reading's cause was wrong.** This entry said `cursors: 0` was
`cursorfunk()` living on frames the sweep never reached. `Hquest.dir` was **never
held** — 4 held ticks, ended on budget in 4.3 s, walked 30 states to f34 — and
cursors are still **0** after the fix. So the zero is not a depth problem and the
explanation offered here is refuted. Why a corpus containing `set the cursor of
sprite 2 to [3, 4]` installs no cursor is an open question and a separate one.

**Zero new findings** came out of the deeper watches, on `piposh-dream` or on
`piposh`. What is new is output rather than verdicts: the `depth` line, `unjudged`,
and `stalled: saves.dir`, which is Director's `pause` correctly named.

---

## 130. `hint` is skip's tractable sibling: bound to a key, emitted, connected to nothing — and unlike skip it is implementable

**Status:** open · **Area:** `autoload/input_router.gd:11` and `:53`, `project.godot`'s
`hint` action, and three disclosed-pending launcher toggles · found 2026-08-22 while
closing 129

`project.godot` binds `hint` to **H** (`physical_keycode: 72`) and joypad button 3,
`input_router.gd:53` emits `hint_requested`, and **nothing connects it** — the signal
appears three times, all inside the file that declares it. Identical shape to the
`skip_minigame` action that 129 removed.

**Written down because the obvious move is to delete it by analogy, and that would be
wrong.** Skip was removed because it is *impossible* in a title-agnostic engine:
`director_preview.gd`'s own comment on `skip_release` records the verdict — "a marker
labels a position, and nothing in a `VWLB` says which positions are scenes. No
title-agnostic rule can recover that" — bought with four reports (MURDER1 jumping
backwards, DAY1 parking the playhead at 32, Rating's drive-probe cycle at 37, COMEIN
landing past the frame that puppets its channels at 96).

**`hint` has no such problem.** The retired implementation
(`b04e5596:director/director_runtime.gd:725`) read
`clickable_sprites(loader.get_frame(frame_index))` and named the first — it asked the
**frame**, never the title. So it is answerable from the movie, which is exactly the
property skip lacks, and the live engine already computes that set for the cursor and
the click router. `hint` is a cheap option 1; skip was not an expensive one.

**Also open, and the only launcher controls left that do nothing:** `upscale_mode`,
`enhanced_graphics`, `expand_edge_hotspots` and `hotspot_hints` have no reader either —
only `controller_cursor_speed` reaches anything. Unlike 129's case these are *disclosed*:
`launcher.tscn`'s `QolHint` above the card says which toggles the engine reads, and
`app_settings.gd`'s header says why the disclosure exists ("so the first report is not
'hotspot hints is broken'"). So this is honest and not a defect — it is a list of what to
implement, and the disclosure has to be kept accurate as each lands.

`tools/launcher_surface.gd` now asserts every `CheckBox` under `AssistCard` is a name its
`SURFACE` table carries, which catches a control added without disclosure. It cannot
catch "a toggle nothing reads" without encoding which toggles are wired, so that class
stays uncovered.

---

## 131. `lingo_system_builtins` measures a fixed half-second window, so it reds under load — the flake shape `play_suspends` already cost this project

**Status:** open · **Area:** `tools/lingo_system_builtins.gd`, its first check · found
2026-08-22 in a whole-suite run

Its opening check, `the movie is stepping to begin with (N exitFrames in half a
second)`, measures a **fixed wall-clock window** — `_steps(10)` is ten
`create_timer(0.05)` awaits — and headless painting at a few score ticks a second can
put **0** dispatches inside it. Measured: **1 red in a 144-entry run** under load, and
3 of 3 passes run alone.

    bash gate.sh                                              # 1 red in 144, under load
    godot --headless --path . --script tools/lingo_system_builtins.gd   # passes alone

**This is the shape `AGENTS.md` says cost three sessions**, surviving at a second
harness. `bugs.md` 41's second half was `play_suspends` doing exactly this, and
`b8466abb` fixed it by replacing a six-frame budget with **a wait on the condition
under a ceiling** and tightening the assertion in the same commit. The same fix applies
here. Until it lands, a red on this entry means "the machine was busy", which is the
worst possible thing for an entry to mean — it is indistinguishable from a real
regression and it teaches the reader to re-run rather than to look.

## 132. `movie_churn` leaks an audio stream and its playback at exit

**Status:** open, cause not investigated · **Area:** `tools/movie_churn.gd`, or whatever
starts a sound during it · found 2026-08-22 while closing the exit-leak cycle

After `efde7406` removed the host/Xtra cycle, `movie_churn` still exits with **2 leaked
objects** — an `AudioStreamWAV` and its `AudioStreamPlaybackWAV`. No `ERROR` line
accompanies them, because neither has a resource path, so this is quieter than what
`efde7406` fixed and correspondingly easier to leave.

    godot --headless --verbose --path . --script tools/movie_churn.gd

**Cause deliberately not guessed.** "It exits mid-playback" is the obvious candidate and
it was not verified, so nothing is claimed. Two objects and no error line is a small
enough prize that measuring first is cheaper than fixing.

`tools/exit_leaks.gd` **would** go red on this if `GATE_ROOT` pointed at a title whose
first frames start a sound, which is noted beside its entry in `gate.sh`. So the guard
already exists and is simply aimed elsewhere — worth knowing before anyone concludes
the suite cannot see this class.

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
