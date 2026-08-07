# Director engine (Godot) — **RETIRED. This document describes deleted code.**

> **Do not use this as a description of the engine.** Every module named below —
> `director/director_runtime.gd`, `movie_context.gd`, `nav_actions.gd`,
> `puppet_controller.gd`, `render_model_loader.gd`, `movie_player.gd`,
> `sprite_channel.gd`, `lingo/lingo_host.gd`, `lingo/lingo_engine.gd` — has been
> **deleted**, along with the `assets/render_model` and `data/` export it read
> and the `scenes/main.tscn` that reached it. Every "Covered by `tools/…`" line
> cites a harness that was deleted with it.
>
> The engine now reads the original `.dir`/`.cst` containers at runtime. For how
> it works, read **`scenes/preview/README.md`** (which file your bug is in),
> `docs/DIRECTOR_ENGINE.md` (the specification) and `docs/LINGO_SURFACE.md`.
>
> This file is kept because its *observations about Director* — the tempo rules,
> the walk model, the ink and matte behaviour, the transition timing — were
> expensive to work out and are still true of Director. Read it for those, and
> for nothing about this repository's current code.

Native Godot score runner for Piposh 2, using `assets/render_model` (frames / members / BMPs) plus `assets/audio`. **All of the following is historical.**

## Modules

| File | Role |
|------|------|
| `director/director_runtime.gd` | Tempo clock, `game_step`, `goto_movie`, clicks, save/load intercept |
| `director/movie_context.gd` | Hubs, end-of-movie routing, transition destinations, walk doorways, playability |
| `director/nav_actions.gd` | Resolve `label` / `movie` / `walk` / `marker` / `hold` / `quit` |
| `director/puppet_controller.gd` | Channel 30 Piposh stand/walk + room arrive |
| `director/render_model_loader.gd` | JSON + BMP via `Image.load`, matte / transparent inks, local-first linked-cast lookup |
| `director/movie_player.gd` | Stage view, widescreen transform, draw + input shell |
| `autoload/audio_director.gd` | Multi-channel `playFile` / `soundBusy` (runtime WAV) |
| `autoload/game_state.gd` | Inventory, day, meetings, JSON save slots |

## Game loop (`DirectorRuntime.tick` → `game_step`)

1. If puppet `whatodo == walktime` → step walk (score frozen)
2. Else if `wait_click` → hold
3. Else if `delay_ms` not elapsed → hold
4. Else `soundBusy` guard (`guard_channel` / `guard_when` / `busy_nav`)
5. Else resolve frame `nav`:
   - `hold` → stay
   - `frame` / `marker` / `label` → `enter_frame`
   - `movie` → `goto_movie` (HEZSAVE intercepted)
   - `quit` on SAVELOAD/MAP → `go_back` (not app quit)
   - none → advance playhead (+1), or movie-end handler

## Movie context

The score says where a frame goes; it does not say where a *movie* sits in the
game. Hub membership, end-of-movie routing and walk-transition destinations
lived in Lingo movie scripts, so `MovieContext` supplies them, reading
`data/movie_context.json` (kept outside `assets/`, which is `robocopy /MIR`
mirrored).

The three hubs are `DAY1`, `HOTEL1` and `NIGHT1`. A movie that runs off the end
of its score resolves, in order:

1. Its own declared hub return — the single distinct hub-targeting cross-movie
   nav it exports (`SEA1` → `day1 @shore2downdeck`, `ARCADE2` → `hotel1 @arcade`).
   The caller is deliberately *not* tried first: `DAY1` frame 153 is `movie sea1`,
   so returning `SEA1` to its caller would re-enter the frame that launched it.
2. The caller on `route_stack`. This is `JOKE`'s path — it exports no return nav
   and used to freeze on its last frame.
3. The current hub.

Hubs are excluded and hold on their final frame. Fourteen exports carry zero
frames (`.CST` cast libraries emitted as movies); `goto_movie` refuses them.

Walk transitions ending on `frame_script 207` need an explicit destination or
the score falls into the adjacent reverse animation. The table is shared across
movies, so the verified Day 1 destinations also cover 19 of `NIGHT1`'s 27
transitions. Unmapped labels log a warning instead of reversing silently; see
`unmapped_transitions` in the data file for the open list.

## Walk doorways

A `walk` nav's `walk_to` and `arrive_at` are stored in the export **once per
destination label**, not per hotspot: across all 90 movies no label carries two
distinct pairs. Every exit into the same room therefore reuses one room's
coordinates, and all but one of them sends Piposh away from the hotspot that was
clicked and then puts him down on the wrong side of the next room. `path1` and
`path3` sit on opposite sides of `path2` and both carried `path3`'s pair.

`data/walk_doorways.json` restores the per-hotspot values, recovered from the
export using the original's own model: a doorway is a place, so the spot Piposh
walks to in room S on his way to D is the spot he stands on when he arrives in S
from D. Identifying which room supplied a label's pair fills both directions of
that edge and re-derives its other hotspots. `DirectorRuntime._apply_walk_override`
swaps the values in at click time; unlisted hotspots keep the exported nav.

Exits the reciprocity pass cannot reach, because both labels' pairs were claimed
by other edges, fall back to standing Piposh in the middle of the exit he
clicked, taking only the ground height from the room's `walk_here` band. That
corrects direction but not arrival, so those rooms can still put him down on the
wrong side.

The 212 same-movie walk hotspots divide into four disjoint groups: 52 whose
exported `walk_to` already sits on the hotspot that is clicked, 55 confirmed as
the canonical hotspot so the exported pair is their own, 77 corrected, and 28
with no surviving information. Those 28 at least walk in the right column, so
direction is plausible, but neither point is verified. Most are blocked on
`unmapped_transitions`: fill a destination in and re-run
`tools/rebuild_doorways.py` and the reciprocity pass picks up the new reverse
edge. The durable fix is the export emitting nav per hotspot.

The score clock executes at most three catch-up steps per Godot process tick. Long render or asset-loading stalls discard excess whole-step backlog, preventing cutscenes from fast-forwarding. A movie change ends catch-up so the destination movie starts with a fresh timing accumulator.

## Audio

Frame `sounds` and click `on_click.sounds` call `AudioDirector.play_file`. WAVs under `assets/audio/sounds` and `assets/audio/fx` are indexed by stem and decoded at runtime (no editor import required).

## Save / load

- JSON slots in `user://saves/slot_XX.json` (F5 Save Editor).
- In-game SAVELOAD → `hezsave` labels map to slots:
  - `fillnames` / `dosave` → save slot 1
  - `fillnames2` / `doload` → load slot 1 + restore movie/label
- Overlay quit closes SAVELOAD via route stack.

## Graphics

- BMPs loaded via `FileAccess` + `load_bmp_from_buffer` (export-safe; ignores broken `importer="keep"` stubs).
- Ink decides how the paper colour is keyed out (masked with `ink & 0x3f`).
  Director treats these two differently and it shows:
  - **8, 9** (Matte, Mask) — flood-fill near-white paper inward from the bitmap
    edge. White enclosed by artwork stays opaque, which is correct for Matte.
  - **1, 36, 39** (Transparent, Background Transparent) — key every
    paper-coloured pixel, interior pockets included.
  Ink 36 dominates this game (~49k sprite records in DAY1 against ~15k for
  ink 8) and is what characters use, so applying the edge fill to it left white
  patches: 105 of 150 sampled `wonder` character sprites carry white the fill
  cannot reach, up to 1023 pixels on one. The puppet and inventory icons always
  use the background key.
- Textures cache per (member, mode); the same member can be opaque in one room
  and keyed in another.
- Sprites drawn low→high channel; inventory icons use reg-point on slot center.
- A sprite draws its member at the **member's own size**, anchored on the member's
  registration point, unless the score marks the sprite as stretched. The width and
  height in the score are the drawn rect only in the stretched case; with the flag
  clear they are authoring residue — the last size the channel was dragged to, or
  the size of a member that used to be there. The upstream exporter masks the ink
  byte to its low 6 bits and drops the flag with it, so it is recovered from the
  containers into `assets/render_model/sprite_stretch.json` by
  `tools/generate_sprite_stretch.py` and applied once per movie load in
  `RenderModelLoader._resolve_sprite_rects()`. A movie absent from that file keeps
  the rects the exporter wrote.
- `assets/render_model/cast_registry.json` is generated data owned by
  `tools/generate_cast_registry.py`. Movie-local `members.json` entries win;
  missing linked members resolve through the movie's `cast_libs` name and the
  registry's canonical standalone export bitmap path.
- Linked names are collected from `cast_libs`; the corresponding canonical
  standalone exports provide the registry metadata and bitmaps. Regenerate it
  after render-model exports change: `python3 tools/generate_cast_registry.py`.
- When raw Director chunk dumps are available, that generator also exports
  `film_loops` SCVW mini-scores into each matching canonical cast in
  `cast_registry.json`. Its `--chunks-root` option defaults to
  `~/Projects/_private_projects/piposh2-toolcache/chunks`; supply another dump
  root with `python3 tools/generate_cast_registry.py --chunks-root <path>`.
  Without it the generator carries forward what the previous run recovered rather
  than dropping it, so a regeneration on a machine with no dump is safe.
- A film loop's children are not always members of the cast the loop lives in. The
  mini-score names the library at offset 4 of each sprite record, `0xFFFF` for the
  owning cast, and any other value is a zero-based index into the file's `ccl `
  chunk — an ordered list of the cast paths its loops reference, in a different
  order from the movie's cast libraries. The generator resolves that index to the
  cast's registered name and writes it on the child as `cast`; the runtime reads
  `cast` and falls back on the owning cast only when it is absent. Without this,
  MURDER1's cliff characters, whose loops live in the movie's own cast but play
  members of `tofi.cst` and `goldolin.cst`, drew a stranger's bitmap or nothing.
- At runtime, a film-loop parent resolves each child bitmap member from the
  registry cast the child names. The loop cursor advances once per entered main
  score frame, resets independently when a channel's member changes, and is
  cleared when a new movie loads. The renderer expands the selected mini-score
  frame's children in channel order and applies Director Scale semantics: each
  child draws at its **member's** own size, scaled by the parent rectangle's X/Y
  scale relative to the loop's initial rectangle, and anchored on the member's
  registration point.
- A child's stored width and height are the drawn rect only when its own stretch
  flag is set, exactly as for a sprite in the movie's score — a loop's children
  are sprite records in the same 48-byte format. `director_film_loops.py` masked
  the ink byte to its low 6 bits and dropped bit 0x80 with it, the same loss
  `generate_sprite_stretch.py` undoes for the main score, so every child was
  scaled into a rect Director ignores. It is now written on the child as
  `stretch` and only where set: 2,053 of the corpus's 13,694 children carry it,
  and 235 of the rest disagree with their member, `wonder` member 27 worst at
  101x144 stored as 203x289. Covered by `tools/film_loop_stretch.gd`, whose
  flagged case is the negative control.

## Controls

F1 debug · F5 save editor · F6 warp (⇧ set) · F10 settings · H hint · Esc skip intro/minigame

The HUD starts hidden; F1 brings it up. F6 jumps straight to the room stored in
`AppSettings.dev_warp_movie`/`dev_warp_label`, and Shift+F6 stores the room you are
in. It is a dev aid gated on `dev_mode`, and it moves the playhead only: `globalday`,
inventory and the route stack are unchanged, so use the save editor for state.

## Progression spine

`data/movie_context.json` carries the rules that let the game advance, none of
which are in the score:

- `meeting_triggers` — which meeting fires in which room, per hub and day
- `phase_transitions` — when a hub hands over (DAY1 → NIGHT1 once day 1's seven
  meetings are done). One-shot, flagged in `story_flags`, because NIGHT1
  declares a route back to `day1 @fort` and would otherwise bounce forever
- `day_advance` — arriving at `HOTEL1 @newmorning` turns the day over, matching
  SLEEP1/SLEEP2's exported return

Only the four original DAY1 rows are verified behaviour. The HOTEL1 and NIGHT1
rows and both transitions are **inferred**, each carrying a `confidence` note.
They exist so the game is completable; the Lingo replaces them wholesale.

## Clicks run from the Lingo

`use_lingo_clicks` defaults on. Three things had to be true together, and fixing
any one alone measured identically, which is worth knowing before touching this:

- **`enterFrame` is dispatched.** The rooms announce themselves with
  `whereami = label(0)` from an `on enterFrame`, and 138 `mouseUp` handlers gate
  their real behaviour on `whereami`. Only `exitFrame` used to reach the
  interpreter, so every gate was false and every hotspot took a dead branch.
- **Room-entry frames are not skipped.** Jumping to a room's `*go` frame skips
  the frame the announcement sits on: HOTEL1 runs it at 436 and `arcadego` is
  437. Running `enterFrame` on the arrival frame does not substitute, because
  `label(0)` there resolves to `arcadego` while the hotspots compare against
  `label("arcade")`. `_run_skipped_entry_scripts()` replays the span.
- **Linked casts have their own script namespace.** Bundles were keyed by the
  ProjectorRays subdirectory, and eleven casts use `External`, so they shared
  one namespace and the last load won. DAY1 asking island2 for member 59 got
  MASTER's `invleft` instead of `to forest1`.

Walk outcomes over 117 hotspots in DAY1, NIGHT1 and HOTEL1, flag off against on
(`tools/lingo_walk_diff.gd`): identical 85, facing-only 11, wrong room 19, clicks
that no longer walk 2. Re-measure rather than trusting this line; an earlier
edition of it quoted 89/10/18/0, which no run since reproduces.

Most of the 19 are HOTEL1, where the export is the weaker reference:
`movie_context.json` has 23 unmapped transitions there and zero verified ones,
and its destinations repeat per channel across unrelated rooms.

## The interpreter decides navigation, then the tables

`game_step` dispatches `exitFrame` first and consults the exported nav and
`MovieContext` only when no script navigated or held. Two things had to be true
for that order to mean anything:

- **`LingoHost.navigated` was never set.** It was cleared on every dispatch and
  assigned `false` on the failure paths, and nothing ever raised it. So the
  runtime's "a script decided where to go" test could never fire, and every
  interpreted `go` was followed by the exported fallthrough: `BehaviorScript 207`
  sent DAY1 to `lighthouse` at frame 441 and `_advance_or_hold()` immediately
  moved it to 442. `_enter()` now raises it, and keeps it distinct from `held`,
  which is what `go to the frame` sets.
- **The redirect ran before the dispatch.** `_try_transition_redirect` intercepted
  every frame carrying `frame_script 207` and answered "where does this transition
  go" out of `movie_context.json`. The original script answers the same question
  from `item 1 of nextroomdata`, which the room's own `mouseUp` handler wrote, and
  it also carries `set the visible of sprite 30 to 1`. Both now come from the
  Lingo; the redirect is the fallback for movies where that script does not run,
  and stands in for the whole handler, visibility line included.

This is the first of `movie_context.json`'s tables to become answerable from the
scripts. It is not deleted: it still serves the un-interpreted path.

## Piposh is sprite 30, and sprite 30 can be invisible

Every hub's `init all` runs `puppetSprite(30, 1)`, so Lingo owns the channel and
`visible` is its only off switch. The original uses it to keep exactly one Piposh
on screen: a room transition is a canned animation that draws him itself in a low
channel — DAY1's `edge2up` runs him up channel 3 for frames 406-421 while channel
30 still holds a sprite — so `whatodoeveryframe` hides sprite 30 when it hands the
playhead to one, and `BehaviorScript 207` turns it back on at the end.

`PuppetController.visible` is that property, and `is_channel_hidden(30)` /
`set_channel_visible(30, …)` route to it, so an interpreted
`set the visible of sprite 30 to 1` reaches it from SEA1's and AIR1's room scripts
as well. The hide fires on the condition the original uses, `ifmovie` item 1 = "1",
which `LingoHost._ifmovie_label()` already reads. Without it the canned animation
and the standing puppet both draw and Piposh appears twice, before or after he
walks into frame.

Deriving that condition from the score instead does not work: a
"span ends in `frame_script 207`" test misses 35 of the 104 `ifmovie` transitions,
because chains like `edge3up` → `lighthouseleft` reach their 207 only at the end.

## Entry scripts replay on arrival, once

Jumping straight to a room's `*go` frame skips the frames the score would have
played on the way in, so `_run_skipped_entry_scripts()` runs their handlers where
they sit. It must do that **only on arrival from outside the room**, and "outside"
means a different marker, not a frame number outside the entry span.

The room's own loop is `go(marker(0))`, which throws the playhead from anywhere in
the idle span back to the `*go` frame: 266 → 239 at DAY1's gate, where `gatego` runs
239 to 269 and `gatetoshore` starts at 270. By frame number every one of those looks
like an arrival. Replaying there re-runs `b4 bk's`, whose `set the visible of sprite
15 to 0` (and 17, and 33) are the collectable channels, so a shell `searchfunk` had
just uncovered was blanked again on the next frame the room ran — visible for a
single frame at `gatego`, and the same for the bottle at `swinggo`. Script 286's
conditional restore does not bring it back: it only ever shows what the player does
*not* already hold.

Arriving from the base label is not an arrival either. Those frames just played,
which is the case this function exists to compensate for when they do not.

`tools/collectables.gd` covers the whole sequence for a shell and a bottle: hidden on
entry, uncovered by searching, still uncovered while the room runs, hidden again when
taken, and the room written into `shellfield` / `jokefield`.

## A member reference carries its cast library

`the castNum of sprite N` and `the member of sprite N` return the member packed
with its library; `the memberNum` stays the per-library number, paired with
`the castLibNum`. One-argument `member()` unpacks the first form and resolves it in
that library alone.

Both forms are needed, and the corpus shows why. `nof = member(the castNum of
sprite 1).name` is how all 18 room-entry scripts name the room, and sprite 1 is the
background from a linked cast — `island:10`, named `shore2`, where DAY1's own member
10 is the cursor `wlkcur1`. Resolving without the library answered 25 of DAY1's 32
rooms with a cursor name and the other 7 with nothing. Meanwhile
`whatodoeveryframe` reads `member(the memberNum of sprite 30).name` to decide which
walk cycle is running, and that works precisely because sprite 30 is cast library 1,
where the two numberings coincide. Packing `the memberNum` too would break it.

`nof` is the key the collectables are recorded under, so those seven rooms shared
one: taking a shell in any of them marked all seven collected, and `searchfunk`
never revealed another.

The packing constant is the port's own. Director packs the pair as well, but the
export carries no per-library slot offsets, so its encoding cannot be recovered from
anything here. It does not need to be: the integer is produced and consumed inside
one expression by `lingo_host.gd`, never stored, compared or arithmetic'd, so only
the round trip has to hold. `tools/room_names.gd` asserts the result against the
score for every room in DAY1, NIGHT1 and HOTEL1.

Rooms do share a key, in the original too: HOTEL1's rooms A, B, C and the bathroom
all score `hotel:6` in sprite 1, and NIGHT1 carries two distinct members both named
`path4`. That is the game's own behaviour and the harness reports it rather than
failing on it.

## Still open

- Talk trees / lip-sync
- Day 2 room content: MORN2, MORN3, DTCDAY2, MENADAY2, HATDAY2/3, HATSIKUM and
  INVESTIG have no triggers yet
- Interpreted `memberNum` / `locH` / `locV` writes never reach the renderer, so
  any Lingo-driven animation is dead. See `bugs.md` 1.
- Retirement of `movie_context.json` and `walk_doorways.json`: only the transition
  destinations have a Lingo answer, and both paths are still live
- `whatodoeveryframe` is still native. `PuppetController` reads `ifmovie` and
  `nextroomdata` but reimplements the walk itself, so its `sprite(30).visible = 0`
  is a port-side copy of the original's line rather than the line running
- Convergence measured on 5 of 61 movies
Closed: the 222 unresolvable cast members. 13 were genuinely missing film loops,
now recovered; 149 are Director shapes, which are the game's invisible hotspots
and correctly draw nothing; 59 were behind a cast-lib name alias; 1 is a text
member. `tools/check_cast_coverage.py` exits 0 and reports per category.

## Inventory drag-and-drop

Inventory is drag-and-drop. There is no selection state in the original.

`reference/lingo/MASTER/External/MovieScript 80 - displayobject.ls` puppets
sprites 103-110 from `objectsfield` lines 1-8 (`line i - 102`). An occupied slot
gets `moveableSprite = 1` and a `hand1`/`hand2` cursor; an empty slot gets member
`object0` and no drag.

The ten `BehaviorScript {52, 93, 94, 97, 108, 110, 111, 128, 129, 135}.ls`
handlers resolve the drop. `mouseDown` stores the slot's home position in
`objectxx`/`objectyy`; `mouseUp` tests `sprite the clickOn intersects <target>`
and then writes the home position back **unconditionally**. So an invalid target
needs no failure branch: nothing intersects, the icon springs home, and nothing
plays. Item consumption is always a mutation of `objectsfield`, never a sprite
position, so the snap-back is independent of whether the puzzle succeeded.

In the port:

- `director/inventory_drag.gd` holds the icon in flight. Its rect is the item's
  own bitmap, not the slot's score rect, because `displayobject` sets the slot's
  `memberNum` to the item and `intersects` measures that.
- The drop rules were a hand-authored table in `data/inventory_drops.json`, read
  by `director/inventory_drops.gd`. **Both are gone**, along with the rest of the
  pre-decoded export. They were also dead before they were deleted: the item to
  cast-member mapping came from a catalog that was always empty, so every rule
  failed its lookup and `apply_inventory_drop` returned false unconditionally.
  Reinstating this means running the original Lingo rather than re-authoring the
  table — the handlers are in `reference/lingo/`.
- `InputRouter` carries `stage_press` / `stage_drag` / `stage_release` alongside
  `stage_click`. Clicks still fire on press, so existing hotspots are unchanged.
- `DirectorRuntime.slot_sprite_at()` finds slots by channel rather than through
  `clickable_sprites()`, which filters out every sprite whose `on_click` carries
  no nav, inventory or sounds: that is all eight slot channels.
- Dropping on channel 100 examines the item: `pi<item>.aif` plus master member
  `piphead2` (55) for one frame, which is what the Lingo's single `updateStage()`
  before restoring `piphead1` (54) produces.

Two traps found while building this:

- The `master` cast library index differs per movie (DAY1 and NIGHT1 2, HOTEL1
  and AIR1 3, SEA1 4), so `master_cast_lib()` resolves it instead of assuming 2.
- `slot_channels` comes out of JSON as floats, and `Array.find()` will not match
  the int 103 against 103.0. That returned -1 for every slot, so before this
  change no item icon was drawn in any movie. `GameState.slot_channels()` now
  coerces once.

`hand1`/`hand2` decode to 5x6 and 8x8 pixels rather than the 1-bit 16x16 a
Director cursor cast pair needs, so `CURSOR_POINTING_HAND` stands in.

Scope note: of the screens carrying slot channels, only DAY1, NIGHT1, SEA1,
HOTEL1, AIR1 and SHUFFLE are real inventory HUDs. ARCADE1 and ARCADE2 score
channels 103, 106 and 108 on 20 frames with no channel 100 at all, so they have
no HUD bar and no examine target; drag there finds nothing to intersect. Five
further movies (DTCDAY2, GOLDDEAD, ISHDAY1, MIROLO, TOFIRCPT) carry the eight
channels on a single stray frame each.
