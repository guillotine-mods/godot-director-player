# Piposh 2 — Godot Port

## What this is

A **Godot 4.7** reimplementation of *Piposh 2*, the Israeli adventure game originally built in **Macromedia Director** (DXR projectors).

Instead of running the old Director player or the web/WASM prototype, this project plays the same decoded **score data** (frames, cast members, hotspots, navigation) inside a native Godot runtime. That makes it practical to add save editing, controllers, widescreen, QoL skips, and Android builds.

Upstream decode / research assets live in the separate Piposh 2 toolchain (render_model export from the DXRs). This repo is the **playable Godot client**.

## Goals

| Goal | Status |
|------|--------|
| Boot title → New Game → intro → Day 1 hub | Working |
| Click hotspots, walk puppet, room transitions | Working |
| Multi-channel audio + `soundBusy` score guards | Working |
| Save / load (JSON slots + in-game SAVELOAD) | Working |
| Transparent / matte BMP sprites | Working |
| Widescreen + upscale + gamepad cursor | Working |
| Android export path | Working (subset / full desktop assets) |
| Clicks driven by the original Lingo | Working (`use_lingo_clicks` on) |
| Talk trees / lip-sync / full dialogue | Not yet |
| Complete parity with every DXR edge case | Ongoing |

## How it works (short)

1. Each Director movie is exported as a folder under `assets/render_model/<MOVIE>/`:
   - `frames.json` — score playhead, sprites, nav, sounds, labels
   - `members.json` — cast member metadata + bitmap paths
   - `bitmaps/` — BMP cast art
2. `DirectorRuntime` advances the score like Director’s tempo clock (`game_step`).
3. Clicks resolve Lingo-derived `on_click.nav` intents (label / movie / walk / quit).
4. `AudioDirector` plays WAVs from `assets/audio/` and exposes `soundBusy` for guarded frames.
5. `GameState` holds inventory, day, meetings, and JSON saves under `user://saves/`.

Native stage size remains **640×480**. Widescreen modes letterbox a target aspect and fit the stage into it.

Deeper loop details: [`ENGINE.md`](ENGINE.md). Android notes: [`ANDROID.md`](ANDROID.md).

## Boot path

```
strtgame  (main menu)
   ├─ New Game → EXODUS → DAY1 (shore2)
   └─ Load Game → SAVELOAD → JSON slot load → restore movie/label
```

In-game SAVELOAD still references the old `hezsave` projector labels (`dosave` / `doload` / `fillnames`). The Godot runtime intercepts those and maps them to JSON save slots instead of launching an external app.

## Repository layout

```
autoload/          GameState, AudioDirector, InputRouter, AppSettings
director/          Score runner, loader, puppet, stage view
ui/                Save editor, settings, debug HUD
scenes/            main.tscn entry
assets/
  render_model/    Decoded Director movies (~85)
  audio/           WAV stems (sounds + fx)
docs/              Project + engine docs
scripts/           Install / utility scripts
```

## Requirements

- **Godot 4.7+** (developed on 4.7.1)
- Desktop: Windows / Linux / macOS with enough disk for assets (~1.7 GB with full movies + audio)
- Android (optional): export templates, JDK 17, device with USB debugging — see [`ANDROID.md`](ANDROID.md)

## Controls

| Input | Action |
|-------|--------|
| Mouse | Hover + click |
| Gamepad stick / D-pad | Virtual cursor |
| Gamepad A / Enter | Click |
| F1 | Debug HUD |
| F5 | Save editor |
| F10 | Display / QoL settings |
| H | Hotspot hint |
| Esc | Skip intro / minigame (when enabled) |

## Relationship to the web prototype

The earlier web/WASM player under the Piposh 2 research tree proved the render_model format and score semantics. This Godot port is the product direction: same data, native engine, tools, and shipping targets. Prefer fixing behavior here rather than extending the web alpha.

## License / content note

Game art, audio, and story content belong to their original rights holders. This repository is a technical port / preservation tooling project — redistribute assets only if you have the rights to do so.
