# Director engine (Godot)

Native Godot score runner for Piposh 2, using `assets/render_model` (frames / members / BMPs) plus `assets/audio`.

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
- `assets/render_model/cast_registry.json` is generated data owned by
  `tools/generate_cast_registry.py`. Movie-local `members.json` entries win;
  missing linked members resolve through the movie's `cast_libs` name and the
  registry's canonical standalone export bitmap path.
- Linked names are collected from `cast_libs`; the corresponding canonical
  standalone exports provide the registry metadata and bitmaps. Regenerate it
  after render-model exports change: `python3 tools/generate_cast_registry.py`.
- When raw Director chunk dumps are available, that generator also exports
  `film_loops` SCVW mini-scores into each matching canonical cast in
  `cast_registry.json`. Its `--chunks-root` option defaults to the sibling
  `../Piposh2-Web-Alpha/decompiled_chunks` research tree; supply another dump
  root with `python3 tools/generate_cast_registry.py --chunks-root <path>`.
- At runtime, a linked film-loop parent resolves its child bitmap members from
  that canonical registry cast. The loop cursor advances once per entered main
  score frame, resets independently when a channel's member changes, and is
  cleared when a new movie loads. The renderer expands the selected mini-score
  frame's children in channel order and applies Director Scale semantics:
  each child draw width and height are its own dimensions scaled by the parent
  rectangle's X/Y scale relative to the loop's initial rectangle.

## Controls

F1 debug · F5 save editor · F10 settings · H hint · Esc skip intro/minigame

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

## Still open

- Talk trees / lip-sync
- Day 2 room content: MORN2, MORN3, DTCDAY2, MENADAY2, HATDAY2/3, HATSIKUM and
  INVESTIG have no triggers yet
- 222 cast members that resolve to neither bitmap nor film loop
  (`tools/check_cast_coverage.py`)

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
- `data/inventory_drops.json` holds the rules, one Lingo citation each, read by
  `director/inventory_drops.gd`. Rules are tried in order, first match wins.
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
