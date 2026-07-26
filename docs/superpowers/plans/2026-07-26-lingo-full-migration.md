# Full Lingo Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan phase by phase.

**Goal:** Every one of the 3349 decompiled Lingo scripts executes in the Godot port, rather than being reproduced by hand.

**Architecture:** Parse the Lingo to an AST offline with a Python compiler (`tools/lingo_compile.py`) into per-movie JSON bundles under `assets/lingo/`, then execute those bundles at runtime with a GDScript tree-walking interpreter (`lingo/`) whose host bindings drive the existing `DirectorRuntime`, `PuppetController` and `AudioDirector`. This is GitHub issue #3, and issue #1 falls out of it.

**Tech Stack:** Python 3 (compiler, offline), Godot 4.7 GDScript (interpreter + host), JSON AST bundles.

## Why not hand-translate

The instruction is to migrate all scripts. Hand-writing 3349 GDScript equivalents is rejected on the evidence, not on effort:

- Most scripts are frame scripts (`on exitFrame` → `go to marker(+1)` and similar) that the existing score runner already reproduces. Hand-porting them re-implements working code and introduces divergence.
- Behaviour lives in *combinations* of scripts and score state (`the clickOn`, `marker(0)`, sprite visibility). A per-file translation loses that and needs the same host layer anyway.
- A hand-translated corpus cannot be verified against the original. An AST executed by an interpreter can be diffed against the `.lasm` bytecode beside each `.ls`.

The interpreter is strictly more coverage per unit of work, and it is the only route where "all 3349" is a measurable claim rather than an assertion.

## Corpus measurements (basis for the grammar)

Measured across all 3349 `.ls` files, 31,402 lines:

| Construct | Lines |
|---|---:|
| `end` | 6387 |
| assignment `x = y` | 4601 |
| `on <handler>` | 3457 |
| `global` | 2775 |
| `sound playFile` | 2515 |
| `the <prop> of sprite` | 2506 |
| `if` | 2285 |
| `set … to` | 2112 |
| `item … of` | 1622 |
| visibility (`.visible`, `the visible of`) | 1439 |
| `field` | 1250 |
| `put … into` | 1215 |
| `else` | 1156 |
| `go(…)` | 1066 |
| `the <prop> of member` | 644 |
| `line … of` | 593 |
| `the clickOn` | 390 |
| `repeat with` | 336 |
| `puppetSprite` | 288 |
| `updateStage` | 237 |
| `marker(…)` | 206 |
| `random(…)` | 186 |
| `play frame` | 160 |
| `intersects` | 117 |
| `case … of` | 78 |
| `word`/`char … of` | 55 |
| `repeat while` | 48 |
| `exit`, `return`, xtras, MUI | **0** |

No xtras, no external libraries, no early returns. That is what makes this bounded.

## Phases

Each phase ends with a measurable coverage number, so "all scripts" is never a claim taken on trust.

### Phase 1 — Lexer and parser, 100% parse coverage

`tools/lingo_compile.py`: tokenise and parse all 3349 files to an AST, emit `assets/lingo/<MOVIE>/<cast>.json`, and print a coverage report naming every file that failed and the construct that beat it. Success is **3349/3349 parsed**, not "most".

Statements: handler definitions with parameters; `global`; assignment; `set <place> to`; `put <expr> into <place>`; `if/then/else/end if` including single-line form; `repeat while`; `repeat with i = a to b`; `case <expr> of` with label bodies; bare command calls; `play frame`; `sound playFile` / `sound stop` / `sound fadeOut`; `exit`/`return` (absent from the corpus, cheap to accept).

Expressions: integer, float and string literals; identifiers; parenthesised groups; call syntax both `f(a, b)` and command form `f a, b`; `the <prop> of sprite <expr>`; `the <prop> of member <expr>`; `sprite(<expr>).<prop>`; `member(<expr>[, <cast>]).<prop>`; chunk expressions `line|item|word|char <expr>[ to <expr>] of <expr>`; `field "<name>"` with optional `of castLib <expr>`; `the number of lines|items|words|chars in <expr>`; `the <systemProp>` (`moviename`, `machineType`, `keycode`, `clickOn`, `mouseH`, `mouseV`, `frame`, `timer`); `marker(<expr>)`; `label(<expr>)`; unary `not` and `-`; binary `+ - * / mod & && < > <= >= = <> and or contains starts`; `<expr> intersects <expr>`.

### Phase 2 — Interpreter core, no host

`lingo/lexer.gd` is not needed; the AST arrives as JSON. `lingo/interpreter.gd` walks it: scopes (local, `global`, script-level), arithmetic and string semantics (Lingo `&` concatenation, `&&` with a space, 1-based indexing, `value()` coercion), control flow, handler dispatch and call resolution order (handler in the same script, then movie scripts, then cast scripts, then builtins). Verified by a golden-file suite: hand-written Lingo snippets with expected results, run headless.

### Phase 3 — Host bindings onto the live engine

`lingo/host.gd` maps Director state onto what already exists:

| Lingo | Host |
|---|---|
| `the memberNum of sprite N`, `set … to` | a puppet channel override table in `DirectorRuntime` |
| `the locH/locV of sprite N` | same table, read through to the score frame when unpuppeted |
| `sprite(N).visible` | the existing `_hidden_channels` mechanism |
| `sprite A intersects B` | `Rect2.intersects` on `sprite_stage_rect` |
| `puppetSprite N, 1` | mark channel N as puppeted |
| `go("label")`, `go to frame N`, `play frame` | `enter_frame` / `resolve_label` |
| `go to movie "x"` | `goto_movie` |
| `sound playFile n, path` | `AudioDirector.play_file` (resolves by stem, so paths are ignorable) |
| `soundBusy(n)` | `AudioDirector.sound_busy` |
| `field "name"` read and write | a field table seeded from `reference/chunks/*/STXT-*.bin`, with `objectsfield` aliased onto `GameState.objects_field` |
| `marker(0)`, `label("x")` | `marker_name_for_frame`, `lookup_label` |
| `the clickOn` | the channel of the sprite that received the click |
| `updateStage` | `redraw_requested` |

`objectsfield`, `Dprocess` and `points` must alias `GameState`, not shadow it, so saves keep round-tripping.

### Phase 4 — Script attachment, and the score gap

An `on mouseUp` handler is useless until the runtime knows *which sprite in which frame* owns it. The export dropped the sprite script fields: `assets/render_model/*/frames.json` sprite records carry no script reference. This is the one place the earlier plan's escape hatch becomes mandatory.

`tools/dump_sprite_scripts.py`: parse `VWSC-*.bin` from the ProjectorRays dump (48-byte sprite records per `summary.json`), extract `scriptCastLib` / `scriptMemberNum` per channel per frame, and emit `assets/lingo/<MOVIE>/sprite_scripts.json`. Validate by checking the ten known inventory drop behaviours (`52, 93, 94, 97, 108, 110, 111, 128, 129, 135`) land on channels 103-110 in DAY1, NIGHT1, HOTEL1, SEA1 and AIR1 — a mapping this plan can check against something already known.

Also needed: frame scripts (already exported as `frame_script`) and cast member scripts, both keyed by cast id.

### Phase 5 — Event loop

Wire Director's event model into `DirectorRuntime`: `prepareFrame`, `enterFrame`, `exitFrame`, `idle`, `mouseDown`, `mouseUp`, `mouseEnter`, `mouseLeave`, `keyDown`, `startMovie`, `stopMovie`, with the message hierarchy (sprite behaviour → cast script → frame script → movie script). Interpreted handlers take precedence over the lifted `on_click` data; the lifted data stays as the fallback for anything unattached.

### Phase 6 — Convergence, and retirement

Run the game under the interpreter and compare against the lifted export: every `on_click` nav in `frames.json` should be reproduced by the interpreted script. Divergences are interpreter bugs, and this is the acceptance measure. Then retire what the Lingo now covers: the inferred `meeting_triggers`, `phase_transitions`, `day_advance`, `sprite_gates` and `click_flags` in `data/movie_context.json`, `data/inventory_drops.json` from the previous plan, and the 112 unconditional removes.

## Honest risk list

- **Phase 4 is the hard dependency.** If the VWSC sprite-script fields cannot be recovered, interpreted behaviours have no attachment point and the migration stalls at frame and movie scripts. The dump is available locally at `~/Downloads/piposh2extracted/piposh2-projectorrays/`; the originals are not committed.
- **ProjectorRays is a decompiler, not an oracle.** Where a `.ls` reads oddly the `.lasm` beside it is ground truth. Expect a handful of files to need the bytecode consulted.
- **Field state is global and persistent.** Director fields double as save state. Aliasing `objectsfield`, `Dprocess` and `points` onto `GameState` is required; getting it wrong corrupts saves.
- **This supersedes plans 2 to 6 of the inventory work.** `talkproc`, `searchfunk`, `invleft`/`invright`, `planefunk`, `ishspec`, `Dprocess` and `points` are all just scripts once the interpreter runs. Do not hand-port them.
- **Scale.** Six phases, and phases 3 to 5 each touch the core loop. This is not a one-sitting change.
