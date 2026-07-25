# Director engine (Godot)

Native Godot score runner for Piposh 2, using `assets/render_model` (frames / members / BMPs) plus `assets/audio`.

## Modules

| File | Role |
|------|------|
| `director/director_runtime.gd` | Tempo clock, `game_step`, `goto_movie`, clicks, save/load intercept |
| `director/movie_context.gd` | Hubs, end-of-movie routing, transition destinations, playability |
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
- Transparent inks: 1, 8, 9, 36, 39 (masked with `ink & 0x3f`).
- Matte: edge flood-fill of near-white paper.
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

## Still open

- Talk trees / lip-sync
- Full meeting / dialogue branching beyond `people_funk` triggers
