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
| `gate.sh`, `check.sh`, `gate_env.sh` | The verification gates, and the one copy of what they need to know about the machine |

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
On a machine with no display, or in a script, `godot --headless --editor --quit`
does the same job: it imports the project, writes the cache and exits 0.

## Running a specific game

`director_game.cfg` is the persistent answer to which title runs, and two command
line flags override it per run without editing the file:

```bash
godot --headless -- --root rating --file MAINMENU.dir       # the player
godot --headless --script tools/click_trace.gd -- --root rating --file BATZEGOZ.dir --marker Egoz1 --channel 11
godot --headless --script tools/channel_report.gd -- --save saves/piposh2/x.json  # every sprite on the frame with its rect, its cursor and why it is clickable — reports, never asserts
```

**Both go after `--`.** Godot consumes every argument it recognises and hands the
rest to the movie through `OS.get_cmdline_user_args()`, which is what `--`
separates. Without it the flags never reach the engine, and the run uses the
configured game instead: Godot accepts the unknown parameters and ignores them,
so there is no error to notice. The `game root:` line the player prints on the
way up is what tells you which one you actually got.

`--root` takes a bare name, meaning that folder under `games/`, or a full
`res://` path for a title stored elsewhere. It is applied in
`DirectorPaths.load_config()` rather than at any one call site, because
`AudioDirector` loads the config itself to build its sound index: an override
applied only in `scenes/preview/boot.gd` once moved the movies and left the
sounds indexed against the config, and the game ran silent with nothing saying
why. One root, one place, or the parts disagree.

**`--root` on its own only works where the configured boot movie also exists in
the new root**, since `boot_movie` is not overridden along with it. The five
piposh roots all ship `strtgame.dir`, in two different spellings, so switching
between those needs nothing else and the case does not matter. `rating` boots
`MAINMENU.dir`, so `--root rating` alone dead-ends on a movie that title does
not have. The failure names what is actually there, entry-point-looking movies
first:

```
no such container: strtgame.dir in res://games/rating
  try --file with one of: MAINMENU-old.dir, MAINMENU.dir, ARCADE1.dir, ... (73 more)
```

`--file` is the second half of the pair, and takes a path relative to the root or
a bare filename, matched case-insensitively.

Two things headless does not give you. The player has no reason to exit, so a
`godot --headless --` run of the *game* runs until it is killed; it is useful for
boot-level output and not much else. And headless Godot paints nothing, so any
check that reads the framebuffer back has to run windowed. See the note under
"Verification tools" for which those are.

## Verification tools

There is no test suite.

**`bash gate.sh` is the authority.** Its `ALL` list is the set of harnesses that
actually run against the live player and are expected to pass, and as of a
whole-suite run on 4.7.1 on 2026-08-10 **every entry passes and none fail** --
including `debug_bindings`, which was config rather than code and whose config
moved, and `boot_state`, the long-standing red this paragraph used to name. Treat
a green `play_suspends` as one sample rather than a result: it is the
fixed-frame-count flake of `bugs.md` 41, and passing once does not close it.
The count is deliberately not written here, for the reason `AGENTS.md` gives --
it changed twice in the day that line was last corrected, and a number nobody
re-measures is what sent three readers looking for a failure that was not there.
Run it and count. Anything below that is *not* in `ALL` is a survey
or a one-off — useful, but nothing runs it, so nothing notices when it rots. A
long run of tools listed here rotted exactly that way and was deleted; see
"Retired" at the end of this section.

```
bash gate.sh                                        # the whole suite, ~10 min
bash gate.sh hotspots trails                        # named harnesses only
bash check.sh                                       # fast structural gate: parses, surface resolves
```

Both run on macOS and on Windows git-bash, from wherever the checkout is. What
each needs to know about the machine is in **`gate_env.sh`**, sourced by both,
so there is one copy of it rather than one per script:

| Function | What it settles |
|------|------|
| `gate_find_godot` | `$GODOT` if set, else `godot`/`godot4` on `PATH`, else the usual macOS and Windows install locations. Windows prefers a *console* build, because the plain one detaches and `$(...)` then captures nothing |
| `gate_announce_godot` | prints `godot: <path> (<version>)` every run, and warns off 4.7.x rather than refusing |
| `gate_run_capped` | the per-harness ceiling, through `timeout` or `gtimeout` where they exist and a bash shim where they do not. macOS ships neither |

Set `GODOT` when the binary is somewhere unusual, or when trying another
version against the port:

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot bash gate.sh
```

A harness that hits the ceiling now prints `TIMEOUT` rather than `ERROR`. The
two are not the same finding, and collapsing them is how `movie_churn` was once
called flaky. An open editor contending over `.godot/` is the usual cause.

`GATE_ROOT` (default `piposh2`) pins the corpus for the run, passed to each
harness as `--root`. A gate is only meaningful against the game its baseline was
recorded on: point it at another title and five different movies read as five
regressions. It is passed before each entry's own arguments, so an `ALL` entry
naming its own root still wins.

The lock is still there, and no longer for the corpus. `--root` is per process,
where the previous mechanism rewrote the `root` line in `director_game.cfg` and
restored it on exit: two runs at once, which happens the moment more than one
agent is working, had each other's corpus swapped out mid-run, and one run
measured six regressions that way of which none was real. What remains is
`.godot/`, which concurrent Godot runs contend over badly enough to hang.

To run one harness by hand, expand its `ALL` entry the way `gate.sh` does, with
`@` standing in for the spaces and the `--` in place:

```
ALL entry   mouse_poll:--file@PIP2DATA/CHESS.dir@--label@ches1
by hand     godot --headless --script tools/mouse_poll.gd -- --file PIP2DATA/CHESS.dir --label ches1
```

Dropping the `--` there is the trap from the section above: the harness runs
against the boot movie instead of its subject, and reports FAIL for a reason
that is not in the harness. That is what the argument-carrying entries exist for.

The surveys and one-offs, each printing a number rather than a verdict:

```
python3 tools/lingo_compile.py                      # every script parses
python3 tools/check_cast_coverage.py                # every referenced cast member resolves
python3 tools/dump_sprite_scripts.py                # sprite -> script attachment
python3 tools/dump_fields.py                        # Director fields + member names
python3 tools/add_cast_script_names.py              # linked-cast member names
godot --headless --script tools/film_loop_cast.gd   # a film-loop child draws out of the cast its own container named, whole corpus, pass/fail
godot --headless --script tools/film_loop_scale.gd  # a loop squeezed onto a smaller sprite keeps its children inside it, whole corpus, pass/fail
godot --headless --script tools/drawn_size_stability.gd # no unstretched sprite resizes while its picture and its place hold still, whole corpus, pass/fail
godot --headless --script tools/cursor_preview.gd -- --file PIP2DATA/MAP.DIR  # cursorfunk's cursor per channel, pass/fail
python3 tools/verify_1bit_members.py                # 1-bit members match their CASt rect, pass/fail
python3 tools/repair_1bit_members.py                # re-decode 1-bit members from the raw chunks
python3 tools/generate_sprite_stretch.py            # recover the sprite stretch flags from the containers
python3 tools/generate_sprite_stretch.py --check    # sprite_stretch.json still matches them, pass/fail
python3 tools/dump_movie_chunks.py --verify         # container reader vs the ProjectorRays dumps, pass/fail
python3 tools/dump_movie_chunks.py --out <dir>      # dump chunks straight from the .DXR originals
godot --headless --script tools/frame_events.gd -- --file PIP2DATA/DAY1.dir  # exitFrame at the top of the next step, and the clock, pass/fail
godot --headless --script tools/click_trace.gd -- --root rating --file BATZEGOZ.dir --marker Egoz1 --channel 11  # one click: where the playhead went, what it played, what ran — reports, never asserts
godot --headless --script tools/movie_churn.gd     # the stage and a window each settle on a movie rather than cycling, pass/fail
godot --headless --script tools/liveness_sweep.gd  # every movie in a corpus, opened and watched: stuck, blank, cycling across movies, or a Lingo error, with the holds that legitimately explain a still playhead separated out, pass/fail (`--root R`, `--limit N`, `--only S`, `--click`, `--verbose`)
godot --script tools/qa_walk.gd -- --out /tmp/shots  # play the title from its boot movie, clicking hotspots and pressing the keys its own scripts test, and write a PNG of every state — the only tool here that produces pictures, reports unless `--strict` (`--steps N`, `--patience N`, `--avoid movie:channel`, `--playff N`) — NOT --headless
godot --script tools/scene_probe.gd -- --root piposh --movie PIANO.dir --marker playpiano --clicks ch59;ch20 --fields sngfld1 --stage 854,640 --out /tmp/p.png  # stand one container on one marker, press channels or stage points, read named fields back through `field "x"`, and photograph it — `--stage W,H` makes one photo pixel one stage pixel; reports, never asserts — NOT --headless
godot --headless --script tools/qa_walk.gd -- --sweep  # the same detectors over every container of a corpus rather than the rooms a walk reaches: missing sounds, unresolved members, Lingo errors, a stage that stays empty — reports, or pass/fail with `--strict` (`--ticks N`, `--blank N`)
godot --headless --script tools/bitmap_geometry.gd # every bitmap member's row stride is at least one row long, whole corpus, pass/fail
godot --headless --script tools/audio_coverage.gd  # every file whose bytes say it is a sound resolves through AudioDirector, and resolves to itself rather than to another take, whole corpus, pass/fail
godot --headless --script tools/transition_survey.gd -- --all  # transitions, delays and waits the score asks for
godot --headless --script tools/draw_survey.gd -- --all  # sprite records by the cast type they name, and which would colourise
godot --headless --script tools/sprite_record_bytes.gd -- --all  # what each of the 48 bytes of a sprite record holds, pass/fail
godot --headless --script tools/sprite_size_survey.gd -- --all  # score rect versus the member's natural size, and rects that change mid-span
godot --headless --script tools/tween_survey.gd -- --all  # whether a tweened span carries a value per frame or only keyframes
godot --script tools/sprite_flip.gd -- --file PIPDATA/OPENING.dir  # a flipped sprite is mirrored inside its own rect, pass/fail — NOT --headless
godot --headless --script tools/sprite_collision.gd  # `intersects`/`within` measure a hidden sprite, the mouse does not, pass/fail
godot --headless --script tools/cannon_hit.gd -- --root piposh  # the same rule played: piposh 1's cannon round sinks a ship, pass/fail
godot --headless --script tools/pause_holds.gd -- --file PIP2DATA/SAVELOAD.dir --label savegame2 --hotspot  # `pause` holds the frame that paused, keeps its hotspots, and `continue` does not re-run the handler that paused, pass/fail
godot --headless --script tools/idle_clock.gd -- --root rating --boot NAVIGATE.dir  # `idle` is sent once per step to the movie, and the title's clock advances because of it, pass/fail
godot --headless --script tools/new_game_reset.gd -- --root rating --boot NAVIGATE.dir  # a New Game resets the tables rating schedules its story from, pass/fail
godot --headless --script tools/text_and_shapes.gd -- --file PIP2DATA/DAY1.dir  # fields draw text, invisible shapes stay clickable, pass/fail
godot --script tools/editable_text.gd -- --file PIP2DATA/SAVELOAD.dir  # typing into a field: focus, caret, selection, drag-select, real keys, real pixels, pass/fail — NOT --headless
godot --headless --script tools/save_movie.gd       # `saveMovie` writes a container this engine reopens, and the save outlives the process that made it — runs a second Godot to prove it, pass/fail
godot --script tools/save_state.gd                  # a save state reproduces the session: every field on the node is saved, rebuilt or excluded-and-why; saved in one process and reloaded from `--save` in another; the Shift chords driven as real keys, pass/fail — run windowed for the keys
godot --headless --script tools/text_codepage.gd    # which single-byte codepage the corpus was authored in, measured against the candidates; the decode/encode round trip over every authored string; a Hebrew name written by one process and read by another, pass/fail (`--all` for every root)
godot --headless --script tools/builtin_load.gd     # the player's own route to a saved game — menu, Load, the slot list, a slot, the stage resuming in the room it recorded, pass/fail (`--real` drives the frame clock instead of stepping the score)
godot --headless --script tools/palette_survey.gd -- --all  # what names a palette: CLUT chunks, palette members, clut ids, the score channel
godot --headless --script tools/palette_members.gd -- --root res://test-games/itamar-park  # custom palettes as the renderer uses them: a CLUT read entry 0 first, a bitmap naming its own palette, the member's table reaching the decoder, pass/fail — fails on a corpus with no palettes rather than passing over nothing
godot --headless --script tools/aiff_check.gd       # every .aif decodes, and none carries a reachable cue point, pass/fail
godot --headless --script tools/audio_index.gd      # the sounds the game names resolve and load, pass/fail
godot --headless --script tools/sound_survey.gd -- --all  # whether the score itself ever plays a sound, pass/fail
godot --headless --script tools/score_sound_check.gd # score sound channels, cue points, fades and sound members, on synthesised fixtures, pass/fail
godot --headless --script tools/sound_wait.gd       # every way a `playFile` fails still leaves `soundBusy` answerable, and the folder in a request decides the take, pass/fail
godot --headless --script tools/music_requests.gd -- --root piposh --movie PIPDATA/DAY1.dir  # what a room asks its music channel for and whether it arrives — not pass/fail, this is the "why is it silent" probe
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

All four announce the skip when the renderer is missing rather than passing
quietly, each in its own words, which matters because `gate.sh` runs every
harness with `--headless`, `trails` and `editable_text` among them. Their pixel
cases therefore never run under the gate, and the two PASS lines it prints for
them cover the rules and not the wiring. Run those two by hand, windowed, after
touching the renderer or the text widget.

`palette_cycle.gd`, `sprite_flip.gd` and much of `trails.gd` are **synthetic on
purpose**, and say so: Piposh 2 switches colour cycling on 0 times in 61,371
frames, and neither title sets the trails bit or either flip bit in 2.7 million
sprite records between them, so there is no authored data to assert against.
`palette_members.gd` is the counter-example and the reason to keep looking for
one: the rest of the palette subsystem looked equally unassertable for the same
reason, and had been wrong in three places the whole time — a corpus that names
one palette everywhere cannot tell a right reader from a wrong one. It runs
against `test-games/itamar-park`, which names 145. Both features are Director's, so both are built and driven from
hand-made records — see "Build Director, not this game" in `AGENTS.md`.

The Lingo compiler and interpreter have their own set, all pass/fail, all
checked against `docs/LINGO_SURFACE.md`:

```
godot --headless --script tools/script_compile_check.gd     # every script in the whole game compiles, and no command keyword parsed as a call
godot --headless --script tools/parse_residue.gd            # no designator's trailing clause was dropped into a statement of its own, pass/fail (`--all` for every root)
godot --headless --script tools/lingo_parse.gd -- --file PIP2DATA/DAY1.DIR   # every script in a container compiles
godot --headless --script tools/lingo_compile_check.gd -- --file PIP2DATA/DAY1.DIR  # ASTs against the committed ones
godot --headless --script tools/lingo_builtins_check.gd     # the engine-free builtins, §1
godot --headless --script tools/lingo_logic_check.gd        # `and`/`or` evaluate both operands, §13/§17
godot --headless --script tools/lingo_designator_check.gd   # designator suffixes survive the parser, §16.4
```

`script_compile_check.gd` is the corpus-wide one and the one to reach for first
when a title misbehaves: `lingo_parse.gd` asks the same question of a single
container, which is the wrong scale for a failure that is invisible from inside
the game. A script that does not compile is a handler that never runs and
nothing at run time says so. It reports 3,307 of 3,307 on Piposh 2 and 16
failures on each Piposh 1 localisation (`bugs.md` 39); pointed at
`--root piposh-en` before the parser fix that shipped with it, it reported 43,
of which 27 were one spelling that killed that build's whole CD-drive probe.

`lingo_compile_check.gd` **cannot do its job right now, and reports PASS anyway.**
It diffs the compiler's output against ASTs committed under `data/lingo/`, which
was deleted; with no bundle to compare against it prints
`containers with no bundle under res://data/lingo (1)` and then
`PASS (11 checks, 0 failed)` over the empty set. Treat its green as no
information until either `data/lingo/` comes back or it is rebuilt to diff
against the container's own scripts. It is still the right *idea* for a parser
regression gate, which is why it is still here.

`cursor_preview.gd`, `keyboard_check.gd`, `frame_events.gd`, `movie_churn.gd`,
`text_and_shapes.gd`, `editable_text.gd`, `save_movie.gd`, `save_state.gd`,
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
| **F9** | Pause |
| **F11** | Copy a diagnostic snapshot |
| **F12** | Container picker (type to filter, Enter to play) |
| **PageDown** | Fast-forward toggle (`[debug] fast_forward_fps`, default 60) |
| **PageUp** | Collision-zone overlay |
| **Shift+F1** | Print every global |
| **Shift+F5** / **Shift+F6** | Quick-save / quick-load |
| **Shift+F7** / **Shift+F8** | Save-as / load, with a file dialog |

Almost every binding is an F-key, and `scenes/preview/debug_keys.gd` explains at
length why that is a rule rather than a taste: the movie is offered every key
first, and a debug binding on a key a game wants reads to the player as the game
misbehaving. The two exceptions sit outside the band because it is full and F10
belongs to Rating, which tests that keycode at 48 sites. All of them are
rebindable from `[debug]` in `director_game.cfg`, and an empty value unbinds one
outright.


## Shipping a build without the debug layer

None of the above should reach a player. One switch removes all of it:

```ini
[debug]
enabled = "auto"
```

  * `auto` — **the default.** On when running from source or from a debug
    export; off in a release export.
  * `true` — keep the tools even in a release export. This is the QA build.
  * `false` — off everywhere, including from source.

`--debug-ui on|off` beats the file for a single run.

Off means *off*: no key is bound at all, the SKIP button is neither drawn nor
hit-tested, and the hotspot outlines, the HUD line, the snapshot toast, the
container picker and the exit report are all absent. A shipped game does not have
F3 dumping a report or F12 opening a movie picker.

**Why `auto` rather than `true`.** `director_game.cfg` is tracked, so whatever it
says is what ships. A plain default of `true` means the debug layer reaches
players whenever someone forgets a line — which is the failure this switch exists
to prevent. With `auto`, the safe answer is the one you get by doing nothing, and
shipping a build *with* the tools has to be typed deliberately.

`tools/debug_bindings.gd` asserts it: with the switch off, no keycode is claimed
by the preview at all.
