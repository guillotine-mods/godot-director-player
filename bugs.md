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

## 139. Three numbers in `docs/bugs-closed.md` name two different entries each, so a citation like "`bugs.md` 107" is ambiguous

**Status:** OPEN · **Area:** `docs/bugs-closed.md` · found 2026-08-28 while closing
138, after discovering that **two of the collisions were mine**

`133` and `134` were already taken on 2026-08-22 (the `play`-interlude return frame
and the pool's music) when entries filed on 2026-08-27 reused both. Those two are
**fixed**: the suitcase is now `137` and the `wait_frames` flake `138`, with the
five code comments that cited them updated. `e1753693`'s message still says 133,
which cannot be changed, so the closed entry says so at the site.

Three collisions remain and are **not** being renumbered:

| n | | |
|---|---|---|
| 25 | `:1764` skipping the opening entered DAY1 past its init region | `:8189` a cold F6 warp lands in a hub with unset globals |
| 88 | `:3386` Magic Hat's menu froze 16 s on a Lingo loop | `:7758` `GetLng()`/`SetLng()` are absent game data |
| 107 | `:6790` `the memberNum of sprite` answered a packed reference | `:7236` `moveToFront`/`moveToBack` are unbound |

**Renumbering these would cost more than the ambiguity does.** Both members of each
pair are closed, and their numbers are cited from code comments *and* from commit
messages, which cannot be rewritten. Moving one side silently invalidates every
citation that already resolved correctly for a reader who had the right entry in
hand.

What is worth doing is making the collision impossible to repeat, since it happened
twice in one day between two sessions allocating numbers in parallel: the next
number is `max()` over **both** files, and nothing checks that. A `check.sh` clause
that reads both files and reports a reused number would have caught all five.

**Counted correctly, which is the reason this entry is small.** A naive
`grep '^## [0-9]'` reports twelve, because entry bodies use `## 1.`/`## 2.` as
numbered sub-headings and some fenced traces begin with `#`. Requiring a
`**Status:**` line within six lines of the heading separates real entries from both,
and takes it from twelve to three.


---

## 140. Piposh Dream's Hatuli level enters a screen from the wrong side, and a player on the yellow rail cannot jump off it

**Status:** OPEN · **Area:** `games/piposh-dream/hatul2.dir`, mechanism not yet
established · reported by QA 2026-08-28 with a snapshot at frame 323 of 1283,
marker `stage3`

Two symptoms in one report, and they may or may not be one bug:

> When entering this screen we enter from the right and not the left side.
> Another issue is that when we're up on the yellow rail, we can't jump off to
> the mountain side - only to fall and die.

**What is established.** The level moves between screens in two handlers that are
mirror images, `wlkleftintersects` and `wlkrightintersects` (`1:` scripts around
byte 176 and 1206). Each is guarded by a collision against a thin vertical strip:

    on wlkleftintersects  ... if sprite 15 intersects 6 then ... stage = stage - 1
    on wlkrightintersects ... if sprite 15 intersects 5 then ... stage = stage + 1

and each then seats the player at a hard-coded position per stage. **Backward
places them on the right** (`locH` 640, 600, 620, 580, 560, 630, 535) and
**forward on the left** (`locH` 10, 0, -30, 100). So "entered from the right"
means the *backward* handler ran, which also decrements `stage` -- the player
should have noticed going back a screen, and the report does not say they did.
That is the first thing to pin down, and it needs the level played rather than
read.

At frame 323 the trigger channels are ch5 `(629,163) 11x268` on the right and
ch6 `(-15,46) 22x346` on the left, so the two are far apart and a collision test
that is merely imprecise would not confuse them.

**Both handlers also write `set the constraint of sprite 15 to 2`, and channel 2
carries a 639x403 box at that frame** -- the playable area. That is worth naming
because `docs/bugs-closed.md`'s constraint work landed a `last_occupied` fallback
on 2026-08-29 which makes a constraint naming a *momentarily* empty channel keep
its last box. Channel 2 is occupied here, so that change is not implicated at
frame 323 -- but the rail symptom is a vertical-movement complaint against a
level that constrains vertical movement, and the two want checking together.

**Not reproduced headlessly yet.** Both symptoms need the player walked into a
trigger strip and then jumped, which no existing harness does for this level;
`west_shoot.gd`'s shape -- drive the real key handlers, then read the movie's own
globals -- is the one to copy.

---

---

---

---

## 145. Piposh Dream overruns the decode-step ceiling on several movies, and the vector rasteriser adds about 15 ms of it

**Status:** OPEN · **Area:** `director/director_vector_shape.gd`,
`director/director_bitmap.gd:_blit_8` · found 2026-08-30 while fixing 141

Measured with `tools/decode_stall.gd`, ceiling 60 ms:

| movie | worst step | vector art |
|---|---|---|
| `WEST1.dir` | 62.1 ms | none |
| `plane2.dir` | 74.3 ms | yes |
| `plane3.dir` | 79.4 ms | yes |

**The baseline is the story and the vector cost is the smaller half.** A movie
with no vector members at all is already 2 ms over, so this is mostly `_blit_8`
being a GDScript loop, and the ~15 ms difference on the two flying levels is
`_fill`/`_stroke` scan-converting paths the same way.

Not a regression against a working state -- before 2026-08-29 those two movies
drew no vector art at all and were a black stage. Worth fixing, not worth undoing.

The obvious first move is a **member-level raster cache**: `sprite_art.texture_for`
caches by drawn size, so a vector member placed at several sizes is rasterised
once per size when the path only needs flattening once per member. It is not done
here because the cache would have to be keyed by container as well as by member
number -- ids repeat across movies -- and that wants doing deliberately rather
than at the end of a session.

`decode_stall` is gated only on `piposh2` and on `fritz2.dir`; adding the rest
would gate the project on a number no change in this session can move.
