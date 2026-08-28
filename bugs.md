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

## 134. `wait_frames` picks its cursor probe from whatever sprite the movie has drifted to, so it fails about half the time

**Status:** OPEN · **Area:** `tools/wait_frames.gd:_cursor_case` · found
2026-08-27 while gating unrelated work, and **measured at HEAD before anything was
blamed on it**

Six runs each way, identical command line:

```
with the day's changes:   PASS FAIL PASS FAIL PASS FAIL   (3 of 6)
with them reverted:       FAIL FAIL FAIL PASS FAIL PASS   (2 of 6)
```

so it is inert to the change that was in flight when it was noticed, and it was
already flaking before it. It fails on `a sprite under the probe names a cursor of
its own (probe (8.0, 8.0))`.

`_cursor_case` takes its probe from whatever sprite happens to be on the frame the
movie has reached by then. That is the **fixed-frame-count** shape `play_suspends`
already cost this project once and `docs/bugs-closed.md` 119 cost it a second time
— a window measured in something other than the movie's own events. The fix is
119's: wait on the movie's own event rather than a tick or wall-clock budget, and
re-read the subject at the moment of the assertion rather than capturing it.

**A gate entry that fails one run in two does the same damage as a standing red**,
because it teaches everyone to re-run rather than read.
