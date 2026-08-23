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

