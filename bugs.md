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

## 45. A hit on a Piposh 1 submarine lifts it 122px, so after two it is clipped off the top of the stage

> **Narrowed 2026-08-14, and the answer is not the one the entry expected.**
> `CANON.dir` member 641 had never existed as text in this tree; extracted, it
> confirms the mechanism exactly — the dive branch is gated on `value(item)=0` and
> writes `put 14`; the surface branch fires at `=1` and subtracts 122 (sprite 12)
> or 164 (sprites 10, 11) **unconditionally**; and member 642's `movecannon4`
> writes `put 20 into item i - 16 of allshipscounter` in *all four* hit stages,
> where the entry quotes only one. One global, two purposes, both in the movie's
> own script. **So if a hit-armed countdown ever reached 1, the original would
> lift the sub too.**
>
> It does not reach 1 here. `tools/cannon_sub_drift.gd` lands a shell through the
> real key path and watches all three subs for 220 frames: every dive/surface pair
> is balanced (+164/-164, +122/-122), no sub leaves the stage, and `allships` is
> back at `live,live,live` at the end — which only member 640's `enterFrame`
> writes. **The round's entry frame re-runs and resets `allshipscounter` before
> the hit's 20 counts down.**
>
> **Next step, and it decides the entry:** is that re-entry faithful? If it is,
> this closes as unreachable. If the port is looping the entry frame where
> Director holds, *that* is the real bug and it is masking this one.

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

## 82. Cast type 15 (`kCastXtra`) members are skipped by the renderer entirely, and Magic Hat's `yes`/`no` buttons and its intro video are six of them

> **Re-measured 2026-08-14: the headline is retracted and the entry narrows to
> eleven members.** The three decode complaints are fixed (`TYPE_NAMES` names 15
> `xtra`, `_parse_specific` has an arm, `_apply_xtra_rect` supplies geometry), and
> "not counted as missing art" is answered by `sprite_art.gd:decline_reason`,
> which now names the *symbol* (`bugs.md` 110). All six named members resolve
> since `226ac4af`.
>
> **And the reference draws none of the six either.**
> `tools/xtra_members.gd --roots res://test-games/itamar-magichat --list` gives
> their symbols: `no`/`yes` and `title1`/`title2` are **`flash`**;
> `IntroRetroVideo`/`magicvideo` are **`VisibleLightOnStageMedia`**. ScummVM's
> `castmember/xtra.cpp:41-47` registers exactly four — `cursor`,
> `quickTimeMedia`, `text`, `font` — and everything else falls through
> `XtraCastMember::promote` to `CastMember::createWidget` returning `nullptr`. By
> this project's own stated rule that is *correct behaviour*, so "two members a
> player is meant to click, and this port cannot draw either" is withdrawn.
>
> Corpus-wide, 566 Xtra members across 8 roots: `flash` 253, `animGif` 206,
> `vectorShape` 94, `text` 11, `VisibleLightOnStageMedia` 2. **555 of 566 are
> unregistered in the reference.** The genuine gap is the remaining **11**, symbol
> `text`, the one the reference promotes to `TextXtra` — and they are in the
> shipped titles rather than the test corpus: `piposh SLOTMACH.dir #83 credit`,
> `piposh-en`/`piposh-ru Slotmach.dir #83`, `piposh-dream MAZE1/MAZE2/maze3 #15`,
> `piposh2 HEZSAVE.DIR #118`, `AIR1.dir #118`, `MAP.dir #12` and `#17`,
> `rating ARCADE1.dir #136`. All carry no `xtraRect` (0x0), and promoting them is
> not free: `director_cast.gd:232` already records `SLOTMACH.dir` #83 `credit`
> colliding with `field "credit"`. It wants its own measurement first.

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

## 83. The score's per-sprite behaviour parameters are never applied, so a behaviour runs with its properties declared and unset

**Status:** OPEN, and narrowed to one third of what it was ·
**Area:** `director/director_score.gd:_read_interval`, the `initializerIndex` /
`getSpriteDetailsStream` half

**Re-verified 2026-08-14 and two of the three original claims are dead**, which
is why the title changed. This used to read "a sprite behaviour is dispatched as
a plain script with `me = null`, so its `property` names have nowhere to live and
the score's per-sprite initialiser is never applied".

* **`me = null`: closed.** `038b79a4` made every message to a behaviour arrive on
  an instance. `behaviour_me --root res://test-games/itamar-magichat --file
  magichat.dir` is 19 checks, 0 failed.
* **"a script-level `property` line is collected and then dropped": closed, and
  the entry never said so.** `behaviour_instance` builds a `LingoObject` whose
  `_init` seeds `props` from `script["properties"]`. Measured on this entry's own
  example: `properties (AST): ["prGotoFrame"]` becomes
  `instance props: ["prgotoframe", "spritenum"]`.
* **`initializerIndex`: open, and untouched.** `grep -rn
  'initializerIndex\|getSpriteDetailsStream'` over `director/ lingo/ scenes/
  tools/` finds only the docstring at `director_score.gd:911`.

So the failure *shape* the entry describes is also wrong now: `go(prGotoFrame)`
still reaches VOID, but through a **declared, unassigned property** rather than
through an unbound builtin, and the diagnosis a reader would form from the old
text would send them to `lingo_interpreter.gd`, where there is no longer anything
to fix.

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
