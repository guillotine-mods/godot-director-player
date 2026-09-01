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

## 141. Piposh Dream's fritz duel flickers for about a second when it moves between screens

**Status:** OPEN · **Area:** `games/piposh-dream/fritz2.dir` · reported by QA
2026-08-28, the second half of a report whose first half is closed

The report was two sentences and they turned out to be two different things:

> When fighting - sometimes Fritz character image would change to one of the
> enemies for a split second.
> When moving between screens - the screen flickers for a second and resumes.

**The first is fixed** and was fixed about ten hours after it was filed, by
`94038ec5` -- `strata2` depth-sorts the four fighters by moving members through a
Lingo variable, and `the member of sprite` was handing back a bare slot number
where the write had taken a packed reference, so a fighter whose artwork lived in
library 2 was re-seated as library 1's member of the same number. "Sometimes, on
being hit" is exactly when the sort fires.

**The second is not obviously covered by it** and has no diagnosis yet. Worth
ruling out first, because both were plausible and one has since been fixed for
other reasons: the stage colour was `Color.BLACK` unconditionally until
2026-08-29, so any moment where the movie had cleared its sprites but not yet
drawn the next screen showed black regardless of what the movie asked for. That
is a "flicker for a second and resumes" shape. `fritz1`-`fritz3` state their
stage colour as a **palette index** (255) rather than an RGB, which is the one
arm of `director_config.gd:_read_stage_colour` that this corpus exercises only
here -- so it is both the likely cause and the least-tested path.


---

## 142. FIXED. `sprite(a).within(b)` answered 0 where `sprite a within b` answered 1, so Somi's bullets were destroyed on the frame after they were fired

**Status:** FIXED · **Area:** `lingo/lingo_interpreter.gd:_call` · found 2026-08-30
after the owner played the build and said the bullets were still missing

**The previous fix was necessary and not sufficient, and the harness said it was
done.** `bugs-closed` 143's list-equality fix let the gun *find* a free bullet;
this is why the bullet then vanished. `tools/west_shoot.gd` asserted only that a
bullet appeared at some point during the press -- "peak >= 1" -- which a bullet
that lives exactly one frame satisfies. It was green while the level was
unplayable, and it took a person playing it to find that out.

**Director spells the collision tests two ways and this port answered them
differently.** `sprite a within b` is D4's operator and reaches `_binary`, which
routes it to the host. `sprite(a).within(b)` is D5's dot notation for the same
opcode; it compiles to `objcall`, which `lscr_lower.gd` lowers to a call, and the
interpreter's dot arm excludes `sprite_ref` and `member_ref` receivers from every
dispatch it has and falls through to `return _eval(callee, frame)` -- a **property
read** of a property no sprite has. It answered 0, and the arguments were never
evaluated. Measured on `WEST1.dir` frame 351, same two channels, same frame:

    sprite 50 within 66        -> 1
    sprite(50).within(66)      -> 0
    sprite 50 intersects 66    -> 1
    sprite(50).intersects(66)  -> 0

`WEST1.dir`'s game loop recycles a bullet with `if not sprite(getAt(bltsprite,
i)).within(66)`, so every bullet was destroyed one frame after it was fired --
the sound, the firing pose and the cooldown all ran and nothing reached the
street. Two lines further down, `sprite(...).intersects(...)` is how a bullet hits
an enemy, so nothing could be shot either. Both are the method spelling.

**Fixed** with a named set of the two sprite methods that take an argument, so a
`sprite_ref` receiver with arguments dispatches to the host exactly as the
operator does. Director defines no other sprite method of this shape; everything
else `sprite(n).x` names is a property, and those still take the property read.

Before: the bullet's list went `[50]` then `[]` on the next frame. After: alive on
24 of 24 frames, travelling 460 -> 480 -> 500 -> 540 -> 580.

**`tools/west_shoot.gd` now asserts the bullet travels** -- that it is alive
several frames later *and* that its position changed -- and asserts the two
spellings agree, which is the engine property underneath. The old check passes
against the broken engine; both new ones fail against it.

`gate.sh key_overlay west_shoot snapshot_check key_chain key_polling
keyboard_check touch_input`: all 7 passed.

---

## 143. FIXED. The touch controls may never have switched on on Android, because the only platform test was a feature tag nothing had read on a device

**Status:** FIXED · **Area:** `scenes/preview/key_affordance.gd:enabled` · found
2026-08-30 from an owner report: `rating` on Android showed no on-screen controls

**The overlay's own logic is sound and was measured so.** `tools/key_overlay.gd`
proves that on `rating/arcade1.dir` frame 63 it offers **three stick directions
and one button**, that driving the stick sends `the keyCode` 126, and that tapping
the button sends 53 and holds nothing -- 15 checks. So the question was never
whether it can build the right controls; it is whether it was ever switched on.

`enabled()` rested on `OS.has_feature("mobile")` (plus a mouseless-touchscreen
fallback). That tag is false on Windows, which is right, and **nothing here has
ever read it on a phone** -- `docs/MOBILE.md`'s "Not verified" list already says
as much about the neighbouring `FEATURE_MOUSE`. `project.godot` also sets
`renderer/rendering_method="mobile"`, which is the sort of thing that makes a tag
spelled `mobile` worth not depending on alone.

**Fixed** by putting `OS.get_name()` first in the disjunction, against `Android`
and `iOS`. It is the platform rather than a feature tag, it needs no
DisplayServer, and no project setting can move it. Additive, like the clause
beside it: being wrong here costs a visible control on a desktop, and being wrong
the other way costs an unplayable game on a phone.

**Not confirmed on a device, and deliberately not claimed to be.** This removes a
dependency that could not be checked from here; it does not prove the tag was the
cause. The other candidate is that the tester was on one of the 88.9% of scenes
that need no key, where showing nothing is correct -- and a screenshot cannot tell
the two apart.

**So the snapshot now answers it.** `snapshot.gd` gained a `platform` line
carrying `OS.get_name()`, whether the overlay is on, and what the current frame
demanded. A report saying "touch overlay off" and one saying "touch overlay on,
0 stick + 0 button(s)" send a reader to two different places, and the next device
test settles this without another round trip.
