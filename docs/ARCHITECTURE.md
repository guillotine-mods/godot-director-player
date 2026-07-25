# Architecture notes

## Data pipeline (upstream)

```
PIP2DATA/*.DXR
  → ProjectorRays chunk dump
  → decode BITD → BMP
  → export VWSC → frames.json + members.json
  → reports/render_model/<movie>/
```

Godot loads that JSON/BMP set directly (same as `web-prototype/main.js`).

## Runtime loop

1. `RenderModelLoader` parses movie `frames.json` / `members.json`
2. `MoviePlayer` advances the playhead at score FPS
3. `StageCanvas._draw` composites sprites (matte ink flood-fill for transparent casts)
4. Clicks resolve `sprite.on_click.nav` → label jump or `goto_movie`
5. `GameState` owns adventure globals; Save Editor reads/writes the same dict

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
  "note": "optional",
  "saved_at": "..."
}
```

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
- `GameState.MEETING_TRIGGERS` — room/day/hub/phase meeting table (Day 1 only so far)
- `data/movie_context.json` — hubs and transition destinations
- `InputRouter` — single place to extend remapping / accessibility
