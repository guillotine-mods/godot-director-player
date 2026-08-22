# Architecture notes

The pieces that have no home in `ENGINE.md`: the save file, the widescreen modes
and the settings hooks. For the repository layout and which modules are reusable,
see [`../README.md`](../README.md). For the runtime loop, see
[`ENGINE.md`](ENGINE.md).

## Data pipeline (upstream)

```
PIP2DATA/*.DXR
  → ProjectorRays chunk dump
  → decode BITD → BMP
  → export VWSC → frames.json + members.json
  → reports/render_model/<movie>/
```

That output *was* mirrored into `assets/render_model/` and loaded from the source
files at runtime, with no Godot import step. Recovering `PIP2DATA` from the
installer is [`EXTRACT_FROM_INSTALLER.md`](EXTRACT_FROM_INSTALLER.md).

## Save format

**Not here, and not `GameState`'s any more.** This section used to document a
`user://saves/slot_XX.json` written by `GameState.to_dict` — a Piposh 2 record of
day, meetings, an eight-slot inventory, hub and `whichsnd`. That whole model was
the retired renderer's, was referenced only from the file that declared it, and
is deleted (`bugs.md` 127). No save file has that shape.

The live save is an emulator-style save state of the whole session, and it lives
where the player half does: `scenes/preview/save_state.gd` is the format and the
`ACCOUNTED` table that keeps it honest, `scenes/preview/save_files.gd` is the
paths (`res://saves/<game>/`, falling back to `user://saves/<game>/` when the
checkout is read-only) and the quick-save, and `scenes/preview/movie_save.gd` is
Director's own `saveMovie`. Read `save_state.gd`'s header rather than a copy of
its field list here; the last copy outlived its subject.

## Widescreen test modes

| Mode | Behavior |
|------|----------|
| `NATIVE_4_3` | Fit 4:3 stage, black bars |
| `WIDE_16_9` | Letterbox window to 16:9 usable area, then fit stage |
| `ULTRA_21_9` | Same for 21:9 |
| `STRETCH_FILL` | Distort stage to window |

`expand_edge_hotspots` grows thin left/right/top/bottom exit strips into the gutters so room exits remain clickable on ultrawide — mirrors the web player's edge expansion.

## Enhancement hooks

- `AppSettings.upscale_mode` — scale factor + filter
- `AppSettings.test_mode_enhanced_graphics` — switch to smooth filtering; later: alternate texture root
- ~~`GameState.MINIGAME_MOVIES`~~ and ~~`AppSettings.allow_minigame_skip`~~ —
  **both gone, and the second is not a hook waiting to be wired: the feature is
  ruled out** (`bugs.md` 127, then 129). `MINIGAME_MOVIES` went with the rest of
  `GameState`'s model. The flag outlived it as a toggle with no effect — the
  launcher offered the checkbox, `director_game.cfg` persisted `qol/minigame_skip`
  and nothing read either. Its reader had been the retired renderer: at
  `b04e5596`, `director/director_runtime.gd:704` tested the flag and `:718` called
  `GameState.is_minigame_movie` fourteen lines later in the same Esc-skip path,
  and both went at `cb7fe815`.
  It was removed rather than reimplemented because the general form of the
  question has no answer. Deciding "is this a skippable minigame, and where does
  skipping land" from the movie means reading a `VWLB`, and
  `scenes/director_preview.gd`'s comment on `skip_release` is the record of that
  attempt: a marker labels a position, nothing says which positions are scenes,
  and the marker walk cost four reports (`bugs.md` 32, 37, 96 and
  `docs/bugs-closed.md` 42) before it was deleted. A per-title list of minigame
  movies is what `AGENTS.md` forbids and what 127 was about. The `skip_minigame`
  input action and `InputRouter.skip_requested` went with the flag; what a debug
  build has instead is `skip_release`, which drops the frame's holds and cuts the
  voice and moves the playhead nowhere.
- ~~`data/movie_context.json`~~ — **gone.** It held hubs, transition
  destinations, sprite gates and an inferred progression spine, and `GameState`
  took its trigger table from `MovieContext` at boot. Both the file and
  `MovieContext` are deleted; the engine reads the movie's own scripts instead,
  which is what `AGENTS.md` asks for.
- `InputRouter` — single place to extend remapping / accessibility
