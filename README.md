# Godot Director Player

Godot **4.7** general Macromedia Director engine, reading original `.dir`/`.cst`
containers at runtime. Title-agnostic: `director_game.cfg` names a folder under
`games/` and a boot movie, and the same engine runs whichever it is pointed at.
It was built on **Piposh 2**, which is still the corpus every gate is measured
against.

**Start here:** [`scenes/preview/README.md`](scenes/preview/README.md) — the player, and which file your bug is in.  
**The specification:** [`docs/DIRECTOR_ENGINE.md`](docs/DIRECTOR_ENGINE.md) (engine) · [`docs/LINGO_SURFACE.md`](docs/LINGO_SURFACE.md) (language) · [`docs/ENGINE_TODO.md`](docs/ENGINE_TODO.md) (the gap)  
**Retired, kept for history:** [`docs/PROJECT.md`](docs/PROJECT.md) and [`docs/ENGINE.md`](docs/ENGINE.md) describe the pre-decoded-export renderer that no longer exists. Read their headers first.  
**Save format, widescreen, hooks:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)  
**Android install:** [`docs/ANDROID.md`](docs/ANDROID.md) · **What mobile imposes on the design:** [`docs/MOBILE.md`](docs/MOBILE.md)  
**Known bugs:** [`bugs.md`](bugs.md) · **Fixed ones:** [`docs/bugs-closed.md`](docs/bugs-closed.md) · **Working on it:** [`AGENTS.md`](AGENTS.md)

## What this is

Piposh 2 is an Israeli point-and-click adventure shipped as a Macromedia Director
projector. Each room is a Director *movie*: a score of frames, a cast of bitmaps
and sounds, and Lingo scripts attached to sprites, cast members, frames and the
movie itself.

This repo does not wrap the original player. It opens the shipped `.dir`/`.cst`
containers, decodes the score, cast and Lingo out of them at runtime, and steps
them the way Director's tempo clock did.

It used to work from a pre-decoded export instead — JSON score data and extracted
BMPs under `assets/render_model/` and `data/`. Both directories, and the renderer
that read them, have been deleted. Anything you find that still describes that
pipeline is stale, and worth fixing where you find it.

Boot path: `strtgame` → New Game → `EXODUS` → `DAY1`. Load Game → `SAVELOAD` (JSON slots).

## Repository layout

| Path | What lives there |
|------|------------------|
| `director/` | The container reader: chunks, cast, score, palettes, film loops, transitions, tempo |
| `lingo/` | The Lingo compiler and interpreter, and Director's value semantics |
| `autoload/` | Godot singletons: game state, audio, input, settings |
| `scenes/` | `director_preview.tscn`, the player. `scenes/preview/` is the module split — **start at its README** |
| `games/` | The original containers, per title, as submodules. **Read-only** |
| `tools/` | Verification harnesses (GDScript), data tools (Python), installer extraction (Docker + Wine) |
| `reference/` | The decompiled original: Lingo source, Director text chunks, ScummVM sources |
| `docs/` | Architecture and process notes, plus design docs and plans under `docs/superpowers/` |
| `openspec/` | Spec-driven change artifacts for in-flight work (`openspec/changes/`) |
| `.claude/`, `.codex/` | Skills and slash commands, kept in sync so both agents see the same thing |
| `bugs.md` | Open defects with reproductions. Closed ones in `docs/bugs-closed.md` |

Not committed, but present after a real run: `.godot/` (editor cache, see below),
`.traces/` (ScummVM trace logs from `tools/capture_scummvm_trace.sh`),
`reference/scummvm/` (fetched GPL sources, read for the model and never vendored),
and `.claude/worktrees/` (agent checkouts).

## Clone the repository

The game repositories are Git submodules and are required. Clone this repository
with all nested submodules:

```bash
git clone --recurse-submodules <repository-url>
```

For an existing checkout, initialize every nested submodule and make subsequent
Git operations recurse into them automatically:

```bash
git submodule update --init --recursive
git config submodule.recurse true
```

Do not run the project from a checkout with uninitialized submodules.

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
| `lingo/lingo_diagnostics.gd` | What the runtime could not bind, deduplicated |
| `director/director_container.gd`, `director_file.gd`, `director_cast.gd`, `director_score.gd` | The container reader: chunks, cast libraries, score records |
| `director/director_bitmap.gd`, `director_shape.gd`, `director_text.gd`, `director_ink.gd`, `director_palette.gd` | Cast member kinds, inks and palettes |
| `director/director_film_loop.gd`, `director_transition.gd`, `director_frame_clock.gd`, `director_labels.gd` | Film loops, transitions, tempo, markers |
| `autoload/audio_director.gd` | Director's sound channels: `playFile`, `soundBusy`, volume, `soundLevel`, fades, cue points |
| `director/score_sound.gd`, `director/director_sound.gd` | The score's own sound channels, and a sound cast member decoded to a stream |
| `autoload/input_router.gd` | Mouse and gamepad virtual cursor |
| `tools/lib/harness.gd`, `args.gd` | Headless assert, command line |

**The seam.** The structure transfers, the contents are per-title. Expect to
rewrite the constants, not the file:

| File | What is title-specific in it |
|------|------------------------------|
| `scenes/preview_lingo_host.gd` | Bindings are game-shaped by design; every port needs a host and each title binds a different subset |
| `autoload/app_settings.gd` | Config filename and the dev warp default |
| `director_game.cfg` | Which folder under `games/` and which boot movie |

**Title-specific.** `autoload/game_state.gd` (inventory, day, meetings, save
slots) and everything under `games/` and `reference/`.

One call here is contestable, so it is stated rather than smoothed:

- **`scenes/director_preview.gd` is where the rule and the code disagree.** It is
  the largest file in the port; `scenes/preview/README.md` says what came out of
  it and what has not.

The retired renderer used to occupy most of this section — `director_runtime.gd`,
`render_model_loader.gd`, `movie_player.gd`, `lingo_host.gd`,
`puppet_controller.gd`, `inventory_drag.gd`, `movie_context.gd`,
`sprite_channel.gd`, `lingo_engine.gd`, `nav_actions.gd`, `stage_canvas.gd`,
`lingo_trace.gd`, `tools/lib/driver.gd`, `game_hooks.gd` and `ui/`. All deleted.
If you are reading a doc that grades any of them, the doc is stale.

Native stage is **640×480**. Widescreen modes letterbox a target aspect, then fit
the stage (optional edge-hotspot expansion).

## Where the data comes from

The engine reads the shipped containers directly. There is no decode step and no
Godot import step:

```
games/<title>/          The original .dir / .cst / .dxr containers, a submodule. READ-ONLY
director_game.cfg       Which folder under games/, and the boot movie
```

The tree does not show which directories are safe to hand-edit, and most are not:

| Path | Origin |
|------|--------|
| `games/` | The originals, per title, as git submodules. **Never modify anything under here** |
| `reference/lingo/`, `reference/chunks/` | Merged from two independent ProjectorRays runs over the original DXRs. The source of truth for every behavioural question |
| `reference/scummvm/` | Fetched by `tools/fetch_scummvm_reference.sh`. GPL, read for the model only |

`assets/` and `data/` are **gone.** They held a pre-decoded export — JSON score
data, extracted BMPs, compiled Lingo ASTs and hand-authored scaffolding — that
the retired renderer read instead of the containers. Several tools and docs still
name paths under them; those are stale, not missing files to restore.

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
fails with `Could not find type "DirectorContainer"` in a file you did not touch.

## Verification tools

There is no test suite.

**`bash gate.sh` is the authority.** Its `ALL` list is the set of harnesses that
actually run against the live player and are expected to pass: **23 pass, 1 fail**
(`boot_state`, long-standing). Anything below that is *not* in `ALL` is a survey
or a one-off — useful, but nothing runs it, so nothing notices when it rots. A
long run of tools listed here rotted exactly that way and was deleted; see
"Retired" at the end of this section.

```
bash gate.sh                                        # the whole suite, ~10 min
bash gate.sh hotspots trails                        # named harnesses only
bash check.sh                                       # fast structural gate: parses, surface resolves
```

The surveys and one-offs, each printing a number rather than a verdict:

```
python3 tools/lingo_compile.py                      # every script parses
python3 tools/check_cast_coverage.py                # every referenced cast member resolves
python3 tools/dump_sprite_scripts.py                # sprite -> script attachment
python3 tools/dump_fields.py                        # Director fields + member names
python3 tools/add_cast_script_names.py              # linked-cast member names
godot --headless --script tools/film_loop_cast.gd   # a film-loop child draws out of the cast its own container named, whole corpus, pass/fail
godot --headless --script tools/drawn_size_stability.gd # no unstretched sprite resizes while its picture and its place hold still, whole corpus, pass/fail
godot --headless --script tools/cursor_preview.gd -- --file PIP2DATA/MAP.DIR  # cursorfunk's cursor per channel, pass/fail
python3 tools/verify_1bit_members.py                # 1-bit members match their CASt rect, pass/fail
python3 tools/repair_1bit_members.py                # re-decode 1-bit members from the raw chunks
python3 tools/generate_sprite_stretch.py            # recover the sprite stretch flags from the containers
python3 tools/generate_sprite_stretch.py --check    # sprite_stretch.json still matches them, pass/fail
python3 tools/dump_movie_chunks.py --verify         # container reader vs the ProjectorRays dumps, pass/fail
python3 tools/dump_movie_chunks.py --out <dir>      # dump chunks straight from the .DXR originals
godot --headless --script tools/frame_events.gd -- --file PIP2DATA/DAY1.dir  # exitFrame at the top of the next step, and the clock, pass/fail
godot --headless --script tools/movie_churn.gd     # the stage and a window each settle on a movie rather than cycling, pass/fail
godot --headless --script tools/transition_survey.gd -- --all  # transitions, delays and waits the score asks for
godot --headless --script tools/draw_survey.gd -- --all  # sprite records by the cast type they name, and which would colourise
godot --headless --script tools/sprite_record_bytes.gd -- --all  # what each of the 48 bytes of a sprite record holds, pass/fail
godot --headless --script tools/sprite_size_survey.gd -- --all  # score rect versus the member's natural size, and rects that change mid-span
godot --headless --script tools/tween_survey.gd -- --all  # whether a tweened span carries a value per frame or only keyframes
godot --script tools/sprite_flip.gd -- --file PIPDATA/OPENING.dir  # a flipped sprite is mirrored inside its own rect, pass/fail — NOT --headless
godot --headless --script tools/text_and_shapes.gd -- --file PIP2DATA/DAY1.dir  # fields draw text, invisible shapes stay clickable, pass/fail
godot --script tools/editable_text.gd -- --file PIP2DATA/SAVELOAD.dir  # typing into a field: focus, caret, selection, drag-select, real keys, real pixels, pass/fail — NOT --headless
godot --headless --script tools/save_movie.gd       # `saveMovie` writes a container this engine reopens, and the save outlives the process that made it — runs a second Godot to prove it, pass/fail
godot --headless --script tools/palette_survey.gd -- --all  # what names a palette: CLUT chunks, palette members, clut ids, the score channel
godot --headless --script tools/aiff_check.gd       # every .aif decodes, and none carries a reachable cue point, pass/fail
godot --headless --script tools/audio_index.gd      # the sounds the game names resolve and load, pass/fail
godot --headless --script tools/sound_survey.gd -- --all  # whether the score itself ever plays a sound, pass/fail
godot --headless --script tools/score_sound_check.gd # score sound channels, cue points, fades and sound members, on synthesised fixtures, pass/fail
godot --headless --script tools/sound_wait.gd       # every way a `playFile` fails still leaves `soundBusy` answerable, and the folder in a request decides the take, pass/fail
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

`stage_clip.gd`, `trails.gd`, `sprite_flip.gd` and `editable_text.gd` are the
tools here that want to run **without** `--headless`. Their other cases work either way, but the ones that
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

`lingo_compile_check.gd` **cannot do its job right now, and reports PASS anyway.**
It diffs the compiler's output against ASTs committed under `data/lingo/`, which
was deleted; with no bundle to compare against it prints
`containers with no bundle under res://data/lingo (1)` and then
`PASS (11 checks, 0 failed)` over the empty set. Treat its green as no
information until either `data/lingo/` comes back or it is rebuilt to diff
against the container's own scripts. It is still the right *idea* for a parser
regression gate, which is why it is still here.

`cursor_preview.gd`, `keyboard_check.gd`, `frame_events.gd`, `movie_churn.gd`,
`text_and_shapes.gd`, `editable_text.gd`, `save_movie.gd`,
`stage_clip.gd`, `trails.gd`, `palette_cycle.gd`, `sprite_flip.gd`,
`sprite_record_bytes.gd`, `sprite_size_survey.gd`, `tween_survey.gd`,
`drawn_size_stability.gd`,
`aiff_check.gd`, `audio_index.gd`,
`sound_survey.gd`, `sound_wait.gd`,
`verify_1bit_members.py` and `generate_sprite_stretch.py --check` are the
pass/fail ones, alongside the whole Lingo block above. Read
`.claude/skills/porting-fidelity-verification/SKILL.md` before trusting any of the
others: agreement with the lifted export falls as the port becomes more faithful,
so those numbers are not higher-is-better.

Writing a `--script` tool: instantiate `scenes/director_preview.tscn`, add it to
`root`, and `await process_frame` — `tools/hotspots.gd` is the shortest example.
Autoloads are not compile-time globals, because the script loads before the tree
exists, so reach them with `root.get_node("GameState")`. And **await real
frames**: a synthetic `for i in N: tick()` loop advances the runtime's clock and
not the audio server's, so every `soundBusy` guard holds for ever and any scene
with speech in it looks stuck (bugs.md 22).

### Retired

These were listed here as runnable until they were deleted. All of them drove the
retired renderer (`DirectorRuntime`, `RenderModelLoader`, `MoviePlayer`) or diffed
against the deleted `assets/render_model/` export, so none could pass, and none
was in `gate.sh` to say so:

`smoke.gd`, `probe.gd`, `cursors.gd`, `room_names.gd`, `sprite_channels.gd`,
`sprite_stretch.gd`, `film_loop_stretch.gd`, `verify_film_loops.gd`,
`collectables.gd`, `cliff_meeting.gd`, `wandering_characters.gd`,
`puppet_visibility.gd`, `lingo_converge.gd`, `lingo_frames.gd`,
`lingo_walk_diff.gd`, `lingo_handler_scope.gd`, `sound_state.gd`,
`check_surface_coverage.gd`, `score_diff.gd`, `place_diff.gd`, `member_diff.gd`,
`shoot_film_loops.gd`, `tools/lib/driver.gd`, `tools/lib/game_hooks.gd`.

Three of them printed **green over an empty set**, which is the failure
`tools/preview_surface.gd` exists to catch — a check that goes dark without going
red. `room_names.gd` reported "0 failure(s)" over 0 rooms and exited clean;
`cursors.gd` counted "0 channels" a FAIL and then printed
`ok every pair resolves to an image` over the empty set; `score_diff.gd` printed
"skipped: no exported frames.json" and exited 0. If you write a harness, assert
that the population you are checking is non-empty *first*.

The coverage genuinely lost with them is in `bugs.md` under "Coverage debt".

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
| **F1** | Sprite boxes |
| **F2** | Hit test |
| **F3** | Diagnostic report |
| **F4** | Restart the movie |
| **F5** / **F6** | Step the playhead back / forward |
| **F7** | Fullscreen |
| **F8** | Quit |
| **F10** | Pause |
| **F11** | Copy a diagnostic snapshot |
| **F12** | Container picker (type to filter, Enter to play) |

Every debug binding is an F-key, and `scenes/preview/debug_keys.gd` explains at
length why that is a rule rather than a taste: the movie is offered every key
first, and a debug binding on a key a game wants reads to the player as the game
misbehaving. All twelve are rebindable from `[debug]` in `director_game.cfg`.

The old **F1 debug HUD / F5 save editor / F10 settings panel** were `ui/`, which
belonged to the retired renderer and is gone.
