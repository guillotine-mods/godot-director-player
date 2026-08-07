# Piposh 2 — Godot Port

Godot **4.7** port of **Piposh 2** (Macromedia Director / DXR), driven by decoded `render_model` data plus WAV audio.

**Project overview:** [`docs/PROJECT.md`](docs/PROJECT.md)  
**Engine loop:** [`docs/ENGINE.md`](docs/ENGINE.md) · **Save format, widescreen, hooks:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)  
**Android install:** [`docs/ANDROID.md`](docs/ANDROID.md) · **What mobile imposes on the design:** [`docs/MOBILE.md`](docs/MOBILE.md)  
**Known bugs:** [`bugs.md`](bugs.md) · **Fixed ones:** [`docs/bugs-closed.md`](docs/bugs-closed.md) · **Working on it:** [`AGENTS.md`](AGENTS.md)

## What this is

Piposh 2 is an Israeli point-and-click adventure shipped as a Macromedia Director
projector. Each room is a Director *movie*: a score of frames, a cast of bitmaps
and sounds, and Lingo scripts attached to sprites, cast members, frames and the
movie itself.

This repo does not wrap the original player. It runs the decoded score in a native
Godot runtime, and runs the original Lingo through an interpreter written here.
The score data and art come in as JSON plus BMP under `assets/render_model/`, the
original scripts are compiled to ASTs under `data/lingo/`, and the runtime steps
them the way Director's tempo clock did.

Boot path: `strtgame` → New Game → `EXODUS` → `DAY1`. Load Game → `SAVELOAD` (JSON slots).

## Repository layout

| Path | What lives there |
|------|------------------|
| `director/` | The score runner: tempo clock, sprite channels, renderer, navigation, puppet walk |
| `lingo/` | The Lingo interpreter, its Director bindings, and Director's message hierarchy |
| `autoload/` | Godot singletons: game state, audio, input, settings |
| `scenes/`, `ui/` | Entry scene, debug HUD, save editor, settings panel |
| `tools/` | Verification harnesses (GDScript), data tools (Python), installer extraction (Docker + Wine) |
| `data/` | Compiled Lingo ASTs, generated lookup tables, hand-authored scaffolding |
| `assets/` | Decoded Director movies and audio. Mirrored in, not authored here |
| `reference/` | The decompiled original: Lingo source, Director text chunks, ScummVM sources |
| `docs/` | Architecture and process notes, plus design docs and plans under `docs/superpowers/` |
| `openspec/` | Spec-driven change artifacts for in-flight work (`openspec/changes/`) |
| `.claude/`, `.codex/` | Skills and slash commands, kept in sync so both agents see the same thing |
| `bugs.md` | Open defects with reproductions. Closed ones in `docs/bugs-closed.md` |

Not committed, but present after a real run: `.godot/` (editor cache, see below),
`.traces/` (ScummVM trace logs from `tools/capture_scummvm_trace.sh`),
`reference/scummvm/` (fetched GPL sources, read for the model and never vendored),
and `.claude/worktrees/` (agent checkouts).

## Engine and game

`AGENTS.md` states the rule that the engine must be agnostic to the game. This is
what the code actually looks like today, on three tiers.

**Portable as written.** Nothing in these knows which title is loaded, so they
transfer to another Director port unchanged:

| File | Role |
|------|------|
| `tools/lingo_compile.py` | Lingo lexer, parser and AST emitter |
| `lingo/lingo_interpreter.gd` | AST walker: scopes, chunk expressions, repeat forms |
| `lingo/lingo_value.gd` | Lingo's value coercion rules |
| `lingo/lingo_engine.gd` | Which script receives a message, in which order |
| `lingo/lingo_diagnostics.gd`, `lingo/lingo_trace.gd` | Dispatch tracing (the env var names carry the title) |
| `director/sprite_channel.gd` | One live channel: score sprite versus puppet state |
| `director/stage_canvas.gd` | Stage compositing surface |
| `director/nav_actions.gd` | Resolve `label` / `movie` / `walk` / `marker` / `hold` / `quit` |
| `autoload/audio_director.gd` | Director's sound channels: `playFile`, `soundBusy`, volume, `soundLevel`, fades, cue points |
| `director/score_sound.gd`, `director/director_sound.gd` | The score's own sound channels, and a sound cast member decoded to a stream |
| `autoload/input_router.gd` | Mouse and gamepad virtual cursor |
| `tools/lib/harness.gd`, `driver.gd`, `args.gd` | Headless boot, step, click, assert |

**The seam.** The structure transfers, the contents are per-title. Expect to
rewrite the constants, not the file:

| File | What is title-specific in it |
|------|------------------------------|
| `lingo/lingo_host.gd` | Bindings are game-shaped by design; `objectsfield` and the `meetings` / `globalday` globals are named in code |
| `director/render_model_loader.gd` | A `strtgame` branch and a `DAY1` bitmap fallback path |
| `director/movie_player.gd` | `STRTGAME_MENU_HOVER`, and the title movie it boots into |
| `director/puppet_controller.gd` | Generic walk state machine over a `PIPOSH_BY_SYZ` art table |
| `director/inventory_drag.gd`, `inventory_drops.gd` | Director's drag model, driven by `data/inventory_drops.json` |
| `autoload/app_settings.gd` | Config filename and the dev warp default |
| `tools/lib/game_hooks.gd` | The one file in `tools/lib/` that is rewritten per title, on purpose |

**Title-specific.** `autoload/game_state.gd` (inventory, day, meetings, save
slots), `director/movie_context.gd` (hubs, phase transitions, walk doorways),
`ui/`, `scenes/`, and everything under `data/`, `assets/` and `reference/`.

Three calls here are contestable, so they are stated rather than smoothed:

- **`director/director_runtime.gd` is where the rule and the code disagree.** It is
  the largest file in the port and its score loop is the engine core, but it also
  carries `MOVIE_ALIASES`, `BOOT_MOVIES`, the `HEZSAVE` / `SAVELOAD` / `MAP`
  routing and the `EXODUS` intro skips. The clock and the routing are not
  separated, and nothing currently tracks separating them.
- **`lingo_host.gd`'s hits are expected, not debt.** `director-port-architecture`
  puts the host on the reusable side precisely because every port needs one, while
  each title binds a different subset.
- **`puppet_controller.gd` is a generic machine with a game-shaped table.** The
  walk states are Director's; the art pack per `syz` value is Piposh 2's.

Native stage is **640×480**. Widescreen modes letterbox a target aspect, then fit
the stage (optional edge-hotspot expansion).

## Where the data comes from

```
assets/render_model/     Director movies (frames.json, members.json, bitmaps/)
assets/audio/sounds/     Game WAVs (indexed by stem)
assets/audio/fx/         Shared FX WAVs
assets/inventory_items.json
```

`assets/` is the bulk of the checkout. The tree does not show which directories
are safe to hand-edit, and most are not:

| Path | Origin |
|------|--------|
| `assets/render_model/`, `assets/audio/` | Mirrored from the upstream decode machine, see `assets/SOURCE.txt`. Loaded from source files at runtime, no Godot import step |
| `reference/lingo/`, `reference/chunks/` | Merged from two independent ProjectorRays runs over the original DXRs. The source of truth for every behavioural question |
| `reference/scummvm/` | Fetched by `tools/fetch_scummvm_reference.sh`. GPL, read for the model only |
| `data/lingo/` | Generated: ASTs from `tools/lingo_compile.py`, plus `attach.json` (`lingo_attach.py --emit`), `sprite_scripts.json` (`dump_sprite_scripts.py`), `fields.json` and `member_names.json` (`dump_fields.py`) |
| `data/lingo_vocabulary.json` | Generated by `tools/generate_lingo_vocabulary.py`; `--check` fails if it is stale |
| `data/movie_context.json`, `data/walk_doorways.json`, `data/inventory_drops.json` | Hand-authored, one citation per rule. Scaffolding with a retirement plan: prefer the Lingo over the guess |
| `data/declared_divergences.json` | Hand-authored: where this port deliberately differs from ScummVM's Director engine, so `tools/oracle_diff.py` reports it as expected |

Recovering the originals from the Windows installer is
[`docs/EXTRACT_FROM_INSTALLER.md`](docs/EXTRACT_FROM_INSTALLER.md), automated by
`tools/extract_piposh2_data/run.sh` under Wine in a container. Provenance details
are in [`reference/README.md`](reference/README.md).

## Open in Godot

1. Install [Godot 4.7+](https://godotengine.org/download)
2. Open `project.godot`
3. Press **F5**

On a fresh checkout, **open the editor once before running anything headless.**
`.godot/` is gitignored, and `global_script_class_cache.cfg` inside it is what
makes `class_name` scripts resolvable. Without it, `godot --headless --script`
fails with `Could not find type "InventoryDrag"` in a file you did not touch.

## Verification tools

There is no test suite. What remains are measurement tools, each printing a
number rather than pass/fail:

```
godot --headless --script tools/smoke.gd            # the first minute of play, pass/fail
python3 tools/lingo_compile.py                      # 3349/3349 scripts parse
python3 tools/check_cast_coverage.py                # every referenced cast member resolves
python3 tools/dump_sprite_scripts.py                # sprite -> script attachment
python3 tools/dump_fields.py                        # Director fields + member names
python3 tools/add_cast_script_names.py              # linked-cast member names
godot --headless --script tools/verify_film_loops.gd # film loops resolve to children
godot --headless --script tools/collectables.gd     # shells/bottles reveal, stay, take, pass/fail
godot --headless --script tools/room_names.gd       # `nof` resolves to the room, pass/fail
godot --headless --script tools/sprite_channels.gd  # Lingo sprite writes reach the stage, pass/fail
godot --headless --script tools/sprite_stretch.gd   # a sprite draws at its member's size, pass/fail
godot --headless --script tools/film_loop_stretch.gd # a film-loop child draws at its member's size, pass/fail
godot --headless --script tools/film_loop_cast.gd   # a film-loop child draws out of the cast its own container named, whole corpus, pass/fail
godot --headless --script tools/drawn_size_stability.gd # no unstretched sprite resizes while its picture and its place hold still, whole corpus, pass/fail
godot --headless --script tools/cursors.gd          # cursorfunk's cursor per channel, pass/fail
godot --headless --script tools/cursor_preview.gd -- --file PIP2DATA/MAP.DIR  # the same cursors in the container-reading preview, pass/fail
godot --headless --script tools/cliff_meeting.gd    # MURDER1 through both dialogue prompts, pass/fail (minutes, real time)
python3 tools/verify_1bit_members.py                # 1-bit members match their CASt rect, pass/fail
python3 tools/repair_1bit_members.py                # re-decode 1-bit members from the raw chunks
python3 tools/generate_sprite_stretch.py            # recover the sprite stretch flags from the containers
python3 tools/generate_sprite_stretch.py --check    # sprite_stretch.json still matches them, pass/fail
python3 tools/dump_movie_chunks.py --verify         # container reader vs the ProjectorRays dumps, pass/fail
python3 tools/dump_movie_chunks.py --out <dir>      # dump chunks straight from the .DXR originals
godot --headless --script tools/puppet_visibility.gd # sprite 30 across a transition, pass/fail
godot --headless --script tools/lingo_converge.gd   # interpreted clicks vs the export
godot --headless --script tools/lingo_walk_diff.gd  # walk outcomes, flag off vs on
godot --headless --script tools/lingo_frames.gd     # interpreted exitFrame vs the score runner
godot --headless --script tools/probe.gd -- --movie X --label Y --seconds N  # where the playhead goes
godot --headless --script tools/frame_events.gd -- --file PIP2DATA/DAY1.dir  # exitFrame at the top of the next step, and the clock, pass/fail
godot --headless --script tools/movie_churn.gd     # the stage and a window each settle on a movie rather than cycling, pass/fail
godot --headless --script tools/transition_survey.gd -- --all  # transitions, delays and waits the score asks for
godot --headless --script tools/draw_survey.gd -- --all  # sprite records by the cast type they name, and which would colourise
godot --headless --script tools/sprite_record_bytes.gd -- --all  # what each of the 48 bytes of a sprite record holds, pass/fail
godot --headless --script tools/sprite_size_survey.gd -- --all  # score rect versus the member's natural size, and rects that change mid-span
godot --headless --script tools/tween_survey.gd -- --all  # whether a tweened span carries a value per frame or only keyframes
godot --script tools/sprite_flip.gd -- --file PIPDATA/OPENING.dir  # a flipped sprite is mirrored inside its own rect, pass/fail — NOT --headless
godot --headless --script tools/text_and_shapes.gd -- --file PIP2DATA/DAY1.dir  # fields draw text, invisible shapes stay clickable, pass/fail
godot --headless --script tools/palette_survey.gd -- --all  # what names a palette: CLUT chunks, palette members, clut ids, the score channel
godot --headless --script tools/aiff_check.gd       # every .aif decodes, and none carries a reachable cue point, pass/fail
godot --headless --script tools/audio_index.gd      # the sounds the game names resolve and load, pass/fail
godot --headless --script tools/sound_state.gd      # soundBusy, volume and soundLevel as a script sees them, pass/fail
godot --headless --script tools/sound_survey.gd -- --all  # whether the score itself ever plays a sound, pass/fail
godot --headless --script tools/score_sound_check.gd # score sound channels, cue points, fades and sound members, on synthesised fixtures, pass/fail
godot --headless --script tools/palette_cycle.gd -- --file strtgame.dir  # palette tables, CLUT, cycling, fades, resolution order, pass/fail
godot --script tools/stage_clip.gd -- --file strtgame.dir  # sprites are cut at the stage edge, pass/fail — NOT --headless
godot --script tools/trails.gd -- --file PIP2DATA/DAY1.dir  # a trails sprite is not erased between frames, pass/fail — NOT --headless
```

`sprite_record_bytes.gd` is the one to reach for when a sprite field looks
wrong. It prints, for every byte of the record, how many distinct values it ever
takes — which is how the flags byte and the blend amount were found to be read
from offsets already occupied by the cast lib and the width, so flip, blend and
tweened had all been counted as zero for reasons that had nothing to do with the
data. It asserts, rather than assuming, that no two decoded fields share a byte.

`stage_clip.gd`, `trails.gd` and `sprite_flip.gd` are the tools here that want to
run **without** `--headless`. Their other cases work either way, but the ones that
matter read the framebuffer back, and headless Godot paints nothing to read. Both
caught a renderer change that every headless check passed over: the stage clip
was armed once at startup and Godot reset it on the next repaint, and the trail
layer was painted underneath the frame's sprites, where any backdrop hides it. If
you write a renderer harness, assume the headless half is not enough.

`palette_cycle.gd`, `sprite_flip.gd` and much of `trails.gd` are **synthetic on
purpose**, and say so: Piposh 2 switches colour cycling on 0 times in 61,371
frames, and neither title sets the trails bit or either flip bit in 2.7 million
sprite records between them, so there is no authored data to assert against. Both features are Director's, so both are built and driven from
hand-made records — see "Build Director, not this game" in `AGENTS.md`.

The Lingo compiler and interpreter have their own set, all pass/fail, all
checked against `docs/LINGO_SURFACE.md`:

```
godot --headless --script tools/lingo_parse.gd -- --file PIP2DATA/DAY1.DIR   # every script in a container compiles
godot --headless --script tools/lingo_compile_check.gd -- --file PIP2DATA/DAY1.DIR  # ASTs against the committed ones
godot --headless --script tools/lingo_builtins_check.gd     # the engine-free builtins, §1
godot --headless --script tools/lingo_logic_check.gd        # `and`/`or` evaluate both operands, §13/§17
godot --headless --script tools/lingo_designator_check.gd   # designator suffixes survive the parser, §16.4
```

`lingo_compile_check.gd` is the regression gate for any parser change. It fails
today on an int-versus-float difference in every numeric literal — `JSON.parse_string`
widens the committed ASTs — so read the `by reason` tally rather than the verdict:
`type` differences are the baseline and anything under `value`, `missing` or
`extra` is structural. A parser change that is meant to be behaviour-neutral
must leave that structural count where it found it.

`probe.gd` is the general one: point it at any room and it reports where the score
went, what it repeated and where it stopped. `--click-prompts` plays a dialogue
prompt the way a player would. Reach for it before writing another one-off
harness — that is what `tools/lib/` exists to make cheap.

`smoke.gd`, `puppet_visibility.gd`, `collectables.gd`, `room_names.gd`,
`sprite_channels.gd`, `sprite_stretch.gd`, `film_loop_stretch.gd`, `cursors.gd`,
`cursor_preview.gd`, `keyboard_check.gd`, `frame_events.gd`, `movie_churn.gd`,
`text_and_shapes.gd`,
`stage_clip.gd`, `trails.gd`, `palette_cycle.gd`, `sprite_flip.gd`,
`sprite_record_bytes.gd`, `sprite_size_survey.gd`, `tween_survey.gd`,
`drawn_size_stability.gd`,
`aiff_check.gd`, `audio_index.gd`, `sound_state.gd`,
`sound_survey.gd`,
`verify_1bit_members.py` and `generate_sprite_stretch.py --check` are the
pass/fail ones, alongside the whole Lingo block above. Read
`.claude/skills/porting-fidelity-verification/SKILL.md` before trusting any of the
others: agreement with the lifted export falls as the port becomes more faithful,
so those numbers are not higher-is-better.

Writing a `--script` tool: autoloads are not compile-time globals, because the
script loads before the tree exists, so reach them with
`root.get_node("GameState")`.

## Skills

`.claude/skills/` carries what this port cost to learn, written to be reused for
another Director title:

| skill | when |
|-------|------|
| `director-data-recovery` | extracting from installers and chunk dumps; read the version warning before copying an offset |
| `director-lingo-semantics` | interpreting or debugging Lingo; a handler runs but does nothing |
| `director-port-architecture` | structuring the port, deciding what to interpret versus lift |
| `porting-fidelity-verification` | reading any metric here, or before flipping a behaviour flag |

## Controls

| Input | Action |
|-------|--------|
| Mouse | Hover + click hotspots |
| Gamepad stick / D-pad | Move virtual cursor |
| Gamepad A / Enter | Click at cursor |
| **F1** | Debug HUD (hidden until pressed) |
| **F5** | Save editor |
| **F6** / **Shift+F6** | Warp to the bookmarked room / bookmark the current one (dev mode) |
| **F10** | Display / QoL settings |
| **H** | Hotspot hint |
| **Esc** | Skip intro / minigame (if enabled) |

## Working now

- Score tempo, clicks, puppet walk, meetings (`people_funk`)
- Audio channels + `soundBusy` guards
- Save/load JSON slots (F5 + in-game SAVELOAD/HEZSAVE)
- BMP matte / transparent inks (export-safe buffer decode)
