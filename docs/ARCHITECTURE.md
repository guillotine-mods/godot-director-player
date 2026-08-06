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

That output is mirrored into `assets/render_model/` and loaded from the source
files at runtime, with no Godot import step. Recovering `PIP2DATA` from the
installer is [`EXTRACT_FROM_INSTALLER.md`](EXTRACT_FROM_INSTALLER.md).

## Save format (`user://saves/slot_XX.json`)

```json
{
  "version": 1,
  "globalday": 1,
  "meetings": ["murder1", "hatday1", "..."],
  "objects_field": ["shovel", "empty", "..."],
  "current_movie": "DAY1",
  "current_label": "shore2",
  "current_frame": 120,
  "whichsnd": "sea",
  "current_hub": "DAY1",
  "story_flags": ["..."],
  "route_stack": [],
  "note": "optional",
  "saved_at": "..."
}
```

`GameState.to_dict` writes everything but `note` and `saved_at`, which the slot
writer stamps on.

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
- `GameState.MINIGAME_MOVIES` — Esc skip targets
- `data/movie_context.json` — hubs, transition destinations, sprite gates, and
  the whole inferred progression spine (meeting triggers, phase transitions,
  day advance). `GameState` receives the trigger table from `MovieContext` at
  boot rather than holding its own copy.
- `InputRouter` — single place to extend remapping / accessibility
