# Director engine (Godot)

Native Godot score runner for Piposh 2, using `assets/render_model` (frames / members / BMPs) plus `assets/audio`.

## Modules

| File | Role |
|------|------|
| `director/director_runtime.gd` | Tempo clock, `game_step`, `goto_movie`, clicks, save/load intercept |
| `director/nav_actions.gd` | Resolve `label` / `movie` / `walk` / `marker` / `hold` / `quit` |
| `director/puppet_controller.gd` | Channel 30 Piposh stand/walk + room arrive |
| `director/render_model_loader.gd` | JSON + BMP via `Image.load`, matte / transparent inks |
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

## Controls

F1 debug · F5 save editor · F10 settings · H hint · Esc skip intro/minigame

## Still open

- Talk trees / lip-sync
- Full meeting / dialogue branching beyond `people_funk` triggers
