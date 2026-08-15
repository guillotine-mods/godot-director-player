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

## 75. Three field references name a cast library their movie does not have, and the port answers them where the reference would not

**Status:** open, **deliberate**, and now **narrowed** — the measurement this
entry asked for was taken on 2026-08-14 ·
**Area:** `scenes/director_preview.gd:_resolve_field`,

> **The two Piposh 1 references are spelling the linked cast's *file*, not a
> library that does not exist.** `tools/scratch/lib_names.gd` on
> `piposh/PIPDATA/MAINMENU.dir`: library 2 is
> `name=[master] path=[…\PIPDATA\master.cst]`, and the script says
> `castLib "master.cst"`. `members.gd:library_named` now matches the authored
> path's basename as a **third** pass — separators normalised the way
> `lib_for_cast_entry` does, extension kept so `master.dir` is not swallowed.
>
> That is **narrower** than what it replaces, which is the point: those two
> references used to fall through to `_resolve_field`'s unqualified walk, which
> can answer out of *any* library (`bugs.md` 34's family). They resolve to library
> 2 and nowhere else now.
>
> The deviation from the reference stands and is still deliberate — ScummVM keys
> `_castNames` by the `MCsL` name alone (`movie.cpp:247`, `:692-699`) and answers
> neither spelling. It is now a deviation that resolves *correctly* rather than
> *plausibly*, which is the distinction this entry was filed to keep.
>
> **The `piposh-dream` ten are untouched** and answer `""` under both readings, no
> `panel.cst` being loaded. `checkroom`'s
> `line TIMEKEEPER of field "timebasebackup"` is still untraced.

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

## 119. `behaviour_me` is a standing flake, and it has been one at HEAD

**Status:** OPEN · **Area:** `tools/behaviour_me.gd` · found 2026-08-15 while
gating unrelated work, and **measured at HEAD before anything was blamed on it**

It goes red intermittently. Sampled by repeated `bash gate.sh behaviour_me`:

* three unrelated files reverted to `HEAD`: **2 FAIL in 10 runs**
* with those files changed: **3 FAIL in 8 runs**

so it is inert to the change that was in flight when it was noticed, and it was
already flaking before it.

Always the same two checks — `and it is the instance the span holds` and
`a property written on that instance is readable from exitFrame` — with two
distinct `<offspring "BehaviorScript 55 - what to do everyframe" …>` objects.

**The mechanism is in the harness.** It reads the channel-0 cache entry, awaits 60
frames, and compares. If the playhead crosses a frame-interval boundary in
between, the span legitimately changes, and `endSprite`/`beginSprite` correctly
makes a **new** instance — so the harness compares an instance from before the
boundary against the right instance from after it and calls the engine wrong.

A gate entry that fails one run in four teaches everyone to re-run it, which is
the same damage as a standing red. Either pin the playhead for the span of the
comparison, or assert against the instance the span holds *at the moment of the
second read* rather than a captured reference.
