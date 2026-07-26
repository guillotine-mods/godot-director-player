# Piposh 2 — Godot Port

Godot **4.7** port of **Piposh 2** (Macromedia Director / DXR), driven by decoded `render_model` data plus WAV audio.

**Project overview:** [`docs/PROJECT.md`](docs/PROJECT.md)  
**Engine loop:** [`docs/ENGINE.md`](docs/ENGINE.md) · **Android:** [`docs/ANDROID.md`](docs/ANDROID.md)

## Open in Godot

1. Install [Godot 4.7+](https://godotengine.org/download)
2. Open `project.godot`
3. Press **F5**

On a fresh checkout, **open the editor once before running anything headless.**
`.godot/` is gitignored, and `global_script_class_cache.cfg` inside it is what
makes `class_name` scripts resolvable. Without it, `godot --headless --script`
fails with `Could not find type "InventoryDrag"` in a file you did not touch, and
every suite goes down with it.

## Verification tools

There is no test suite. What remains are measurement tools, each printing a
number rather than pass/fail:

```
python3 tools/lingo_compile.py                      # 3349/3349 scripts parse
python3 tools/dump_sprite_scripts.py                # sprite -> script attachment
python3 tools/dump_fields.py                        # Director fields + member names
godot --headless --script tools/lingo_converge.gd   # interpreted clicks vs the export
godot --headless --script tools/lingo_frames.gd     # interpreted exitFrame vs the score runner
```

Writing a `--script` tool: autoloads are not compile-time globals, because the
script loads before the tree exists, so reach them with
`root.get_node("GameState")`.

Boot: `strtgame` → New Game → `EXODUS` → `DAY1`. Load Game → `SAVELOAD` (JSON slots).

## Controls

| Input | Action |
|-------|--------|
| Mouse | Hover + click hotspots |
| Gamepad stick / D-pad | Move virtual cursor |
| Gamepad A / Enter | Click at cursor |
| **F1** | Debug HUD |
| **F5** | Save editor |
| **F10** | Display / QoL settings |
| **H** | Hotspot hint |
| **Esc** | Skip intro / minigame (if enabled) |

## Assets

```
assets/render_model/     Director movies (frames.json, members.json, BMPs)
assets/audio/sounds/     Game WAVs (indexed by stem)
assets/audio/fx/         Shared FX WAVs
assets/inventory_items.json
```

Full tree is large (~1.7 GB). Runtime loads BMPs/WAVs from source files (no Godot import required).

## Architecture

| Path | Role |
|------|------|
| `autoload/game_state.gd` | Inventory, day, meetings, JSON saves |
| `autoload/audio_director.gd` | Multi-channel playFile / soundBusy |
| `autoload/app_settings.gd` | Aspect / upscale / QoL |
| `autoload/input_router.gd` | Mouse + gamepad cursor |
| `director/director_runtime.gd` | Score loop, nav, save intercept |
| `director/render_model_loader.gd` | BMP + matte / transparent inks |
| `director/movie_player.gd` | Stage view + draw + input |
| `ui/save_editor.gd` | Dev save editor |

Native stage is **640×480**. Widescreen modes letterbox a target aspect, then fit the stage (optional edge-hotspot expansion).

## Working now

- Score tempo, clicks, puppet walk, meetings (`people_funk`)
- Audio channels + `soundBusy` guards
- Save/load JSON slots (F5 + in-game SAVELOAD/HEZSAVE)
- BMP matte / transparent inks (export-safe buffer decode)
