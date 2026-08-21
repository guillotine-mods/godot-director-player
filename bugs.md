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

## 121. Nobody has watched Piposh Dream tick its own day-completion checklist, and a cold-entry probe will report it broken when it is not

**Status:** open, unmeasured · **Area:** `mainmenu.dir`'s seven-slot hub, and whether
an interpreter global survives `go movie` · raised 2026-08-21 while closing the
2026-08-14 day-2 sweep's follow-ups

Piposh Dream gates a day on a seven-item checklist. `mainmenu.dir` frames 1..27 carry
one hotspot behaviour per slot, each composing its target from the global `globalday`
(`"hex" & globalday & ".dxr"` and so on). Finishing a game writes `put "done" into
item N of advancekeeper`. `1:13` on f0 hides slot i when item i reads `done`, and
`1:15` on f27 advances the day and routes to the next dinner once all seven do.

**None of that has ever been observed running.** The seven day-2 frames that write the
checklist were derived by scanning every cast member of every container for the write
and resolving the writing member back to the frames whose coverage runs it:

| item | container | frame |
|---|---|---|
| 1 | `show.dir` `6:62` | f2377 |
| 2 | `hex2.dir` `1:138` | f344 (and f688) |
| 3 | `hatul2.dir` `1:148` | f768 |
| 4 | `MAZE2.dir` `1:223` | f303 |
| 5 | `plane2.dir` `1:181` | f1782 |
| 6 | `WEST2.dir` `1:256` | f543 |
| 7 | `fritz2.dir` `1:463` | f853 |

Derived from container text, every one. The sweep drove six day-2 games with synthetic
input and reached exactly one outcome — `MAZE2`'s `loose` at f308 under `--ff 240` —
and that run did **not** reach f303. So "day 2 can be completed" rests on no
measurement at all.

**Why it matters more than a coverage gap.** If a write does not land, or does not
survive the trip back to the hub, a player can beat all seven games and the day never
advances. That failure is invisible in every report written so far, because it looks
exactly like "the harness is not good enough at the game to win it".

**The specific untested mechanism is narrow.** `advancekeeper` must survive two movie
changes: hub to game and back. Nothing in `gate.sh`'s `ALL` asserts that an
interpreter global survives `go movie` — `new_game_reset` is about Director *fields*
and about resetting them, and `go_movie_arg` is about which argument of `go` names the
movie, not about state outliving the call.

**The trap, which is why this entry exists instead of a quick probe.** The obvious
approach — enter the container and put the playhead on the writing frame — produces a
**false negative**. A landing skips the movie's own init: measured on
`hatul2.dir --play "stage8water@f982"`, where the landing skips `newgame` at f179, so
`hatmen` is never assigned and a script takes its `go("gameover")` branch (`f204444d`).
Applied here, a cold entry to `hex2.dir` f344 leaves `advancekeeper` VOID, and **a VOID
global aborts the handler rather than reading as empty**, so the write cannot land and
the probe reports the checklist broken about a game that is fine.

**What to do instead**, and it is one gate entry over one game rather than a sweep.
Take the authored path for the globals: `dinner2.dir` f4411 sets `globalday = 2` and
resets `advancekeeper` itself, then walks to the hub unaided in about 15 process
frames. Click ch5. Let `hex2.dir` load. *Then* place the playhead on f344, read
`advancekeeper` back, return to the hub and assert `1:13` hides slot 2. `hex2` is the
right single case because item 2 has two write frames, f344 and f688.

Two prohibitions belong in that harness: never enter the checklist frame cold, and
never write `advancekeeper` from the harness — the first gives the false negative
above and the second makes the assertion a tautology.

The capability it needs is the **warm entry** the day-2 sweep invented and never
landed: the authored path for the globals, then the scene's own derived landing. As a
flag on `puppet_members` it is `--via <hub movie>:<channel>` plus the existing landing
derivation; the blocker is that `_play` breaks out of its sampling loop the moment
`movie_name()` changes, so the hub click has to happen before that loop is entered.

Reproducing the gap as it stands — the frames exist, nothing has run them:

    godot --headless --path . --script tools/puppet_members.gd -- \
        --root piposh-dream --file hex2.dir

`tools/day_checklist.gd` is an untracked work-in-progress start on this, left in the
tree deliberately.

**Not to be confused with criterion 4, and do not reopen that as a defect.** The
sweep's "an outcome is reachable" criterion is not reachable by synthetic input for
these games: the driver cycles a scene's derived keys, which does not solve a maze, a
platformer or a duel. Five `YES (1-3)` rows mean the other three criteria held, not
that anything is broken. Fast-forward does not change this — presses are spaced by
score ticks, so `--ff` multiplies the input rate too (998 presses against 55 over the
same 3,000 process frames), and an ff result says "reachable", never "a human would
reach it".

---

## 123. A call to a handler nothing defines returns 0 and the rest of the handler runs; the reference aborts it

**Status:** open · **Area:** `lingo/lingo_interpreter.gd:_call` · found 2026-08-21 while
refuting a day-3 finding that turned on what an undefined call does

`LC::call` in the reference ends an undefined call by aborting:

    g_lingo->lingoError("Call to undefined handler '%s'. Dropping %d stack items",
                        funcSym.name->c_str(), nargs);

and `lingoError` (`reference/scummvm/lingo/lingo.cpp:792`) sets **`_abort = true`** — it
also calls `error()` under `kDebugLingoStrict`, but the plain path aborts. So in the
reference, **no statement after an undefined call runs.**

This port falls through every resolution arm — native handlers, `new`, user handlers,
`_own_builtin`, the engine-free builtins, the host — and then:

    		report(LingoDiagnostics.BUILTIN, name)
    	return result if result != null else 0

The call yields **0** and the enclosing handler continues to its end. This file's own
comment at `lingo_interpreter.gd:2836` already calls the silent-drop shape "the state
§19 calls the worst one".

**What a player sees: nothing.** The diagnostics sink is read by six harnesses
(`lingo_local_diagnosis`, `lingo_scope_check`, `property_surface`,
`lingo_surface_audit`, `lingo_movie_surface`, `buddyapi_xtra`) and by **nothing on the
player's path** — `debug_report.gd` does not read it. The name does reach the F3/exit
report's `builtins unbound` line through `preview_lingo_host`, and
`scenes/preview/boot.gd:322` names that symptom, but a running game gives no sign.

**Why it matters beyond fidelity.** The difference is not the return value, it is the
statements after it. A movie whose author relied on an abort — a guard clause calling a
handler that exists only in some containers, for instance — gets its whole handler body
executed here where Director stopped at the call. That is a behavioural divergence with
no upper bound on its effects, and it is silent in both directions: nothing warns, and
the 0 is indistinguishable from a handler that returned 0.

**Reproducing it** is the awkward part and is why this is filed rather than fixed. No
container in the corpus is currently known to make an undefined call — the day-3 finding
that prompted this (`hatul2.dir` calling `wlkleftintersects()` with nothing defining it)
turned out to be **false**: `hatul2` defines it in its own internal cast at `1:10`, and a
played run of the arm that calls it leaves `builtins unbound` empty after 46 `exitFrame`
dispatches. So the divergence is established from the two implementations rather than
from a movie that trips it, and the fix needs a synthetic case:

    godot --headless --path . --script tools/puppet_members.gd -- \
        --root piposh-dream --file hatul2.dir --play stage4 --ticks 6000

prints `builtins unbound : {}` today, which is the negative control — the tally an
undefined call would appear in.

**Before changing it**, note what the current behaviour is load-bearing for. The comment
above the fall-through records that `externalParamName` and `externalParamValue` answer
VOID past the end of a list and that "all three came back as 0 *and* reported themselves
missing" — so some callers depend on a value coming back rather than on an abort.
Aborting unconditionally would need those cases separated first, which is why this is an
entry and not a one-line change.

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

