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

### Phase 4 — Script attachment: SOLVED

**Corrects an earlier wrong conclusion in this same plan.** I first reported that
the score does not store sprite scripts. That was wrong, and the mistake was
method, not data: I read the first eight entry offsets of DAY1's `VWSC`, saw them
identical, and generalised. DAY1 actually has **3865 non-empty entries**.

The score stores it in the frame intervals that follow the frame-delta stream:

    primary   >= 44 bytes: int32 startFrame, endFrame, unk, unk, spriteNumber
    secondary    8 bytes:  int16 scriptCastLib, scriptMemberNum, unk, unk

`spriteNumber` carries the same +5 bias as the frame buffer, so the real channel
is `spriteNumber - 5`. `tools/dump_sprite_scripts.py` recovers **14,855
script-bearing intervals across 61 movies** and writes
`data/lingo/<MOVIE>/sprite_scripts.json`.

The member number in the secondary is a cast member number, which is exactly how
ProjectorRays names its files. Confirmed on two independent casts:

- DAY1: 100 script members plus 12 non-script members carrying a non-zero
  `scriptId` (int32 index 4 of the `CASt` info block) equals precisely the 112
  `.ls` filenames in its dump. Four of the twelve are `1:217`, `1:218`, `1:219`
  and `1:235`, which `data/movie_context.json` independently documents as
  Gondolin's corpse, handbag, lipstick and third clue.
- MASTER: 36 script members plus 4 with a `scriptId` (57, 59, 69, 77) equals its
  40 `.ls` files. Those four are `invright`, `invleft`, `jokebtl` and `shell`:
  button bitmaps whose script runs on click.

So all three attachment routes are resolvable: sprite behaviours from the
intervals, cast member scripts from the displayed member's `scriptId`, and frame
scripts from the `frame_script` field the export already carries (DAY1's 207 is
the dynamic room redirect).

**Validation, and an independent check on the previous plan.** The scripts found
on slot channels 103-110 match, movie by movie, the attributions made earlier by
reading the Lingo alone:

| Movie | Drop behaviours on the slot channels | Matches the hand-derived reading |
|---|---|---|
| DAY1 | 52, 108, 128 | 108 is the dwarfs variant testing 36/37 |
| NIGHT1 | 52, 108, 110, 111 | 110 is the `sulam` ladder, 111 is mirolo |
| HOTEL1 | 52, 94, 129, 135 | 94 is the fat room, 129 is `ishspec` |
| SEA1 | 52 | 52 is the examine-plus-talk variant |
| AIR1 | 52, 97 | 97 is `planefunk` |

Every attribution in `data/inventory_drops.json` is corroborated. It also settles
the one rule that had been parked: `BehaviorScript 128` sits on DAY1's slot
channels, so the `tools` puzzle is DAY1's and the rule is now enabled.

Still open: `BehaviorScript 93` does not appear on the slot channels of those five
movies, so it is attached somewhere else and has not been placed.

### Phase 4 (original text) — Script attachment, and the score gap

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


---

## Execution record

**Phases 1 to 6 implemented 2026-07-26.** Numbers are measured, not estimated.

| Phase | Result |
|---|---|
| 1 Parser | **3349/3349 scripts (100%)**, 3457 handlers, matching an independent grep count |
| 2 Interpreter | Director value semantics + full control flow, 22 semantic cases verified |
| 3 Host | Original `displayobject` drives the live engine; 60 fields and 1979 member names recovered |
| 4 Attachment | 14,855 script-bearing intervals across 61 movies, validated against the ten known drop behaviours |
| 5 Event loop | `mouseDown`/`mouseUp` through the four-level message hierarchy, behind `AppSettings.use_lingo_clicks` |
| 6 Convergence | **534/540 clickable cases reached (98.9%), 505/534 accounted for (94.6%)** |

### Convergence detail

`tools/lingo_converge.gd` replays every distinct clickable case against the
export's `on_click`, which is an independent oracle: a different tool produced it
from the same originals years earlier.

| Movie | Cases | Reached | Agree | Partial | Differ | Deferred walk |
|---|---:|---:|---:|---:|---:|---:|
| DAY1 | 112 | 112 | 21 | 24 | 1 | 66 |
| NIGHT1 | 126 | 125 | 17 | 39 | 0 | 69 |
| HOTEL1 | 104 | 99 | 29 | 40 | 0 | 30 |
| SEA1 | 131 | 131 | 34 | 56 | 27 | 14 |
| AIR1 | 67 | 67 | 16 | 39 | 1 | 11 |

"Deferred walk" is not a failure: a click on an exit sets `egozh`/`egozv` and lets
`walkonby` carry the player there over later frames, so there is no immediate
navigation to compare. "Partial" means one of navigation or sound matched. Most
partials are semantic equivalences rather than errors, for example the Lingo
going to the label `savegame` where the export lifted it as movie `saveload`.

The 29 remaining disagreements are 27 in SEA1 plus 2 elsewhere, so SEA1 has a
systematic problem of its own and is the next thing to look at.

### Three semantics bugs the convergence run found

Each was silent, and each moved the numbers:

1. **`sound playFile 1, x` parsed as `sound(playFile(1, x))`**, a nested command
   call, so no sound was ever recorded. Director has two-word commands; the
   second word is a literal. Fixed with a `COMMAND_WORDS` table.
2. **An unset global read as 0 instead of VOID.** `effectspath & "saveload.aif"`
   became `"0saveload.aif"`. This affects all 2515 `sound playFile` lines.
   Fixing it took agreement from 48 to 117 and disagreement from 51 to 29.
3. **`dot` and `prop_of` were not assignable targets**, so `sprite(N).visible = 1`
   parsed as a comparison and did nothing. 904 statements across the corpus.

All three are the same shape as the earlier assignment-versus-equality bug: Lingo
is a language where a mistake produces silence rather than an error, so a
measurable oracle is worth more than careful reading.

### State of the switch

`AppSettings.use_lingo_clicks` is **off**. With it on, `DirectorRuntime` builds a
`LingoEngine`, prepares each movie's scripts on load, and lets an interpreted
`mouseUp` take a click whenever one exists, falling back to the lifted `on_click`
when it does not. 94.6% is promising, not finished: turning it on by default
should wait until SEA1 is understood and the deferred-walk path is wired through
`walkonby` rather than counted as out of scope.


---

## exitFrame: implemented, measured, and not switched on

`on exitFrame` is 2504 of the 3457 handlers, so it is the bulk of the migration.
It is now wired: `DirectorRuntime.game_step()` dispatches it through the message
hierarchy, and when the script navigates or holds, the exported nav is not
consulted for that frame. `go(marker(0))` is treated as Director's idle hold
rather than a re-entry, which would otherwise restart the frame's sounds and
delay timer on every step.

Coverage, from `tools/lingo_frames.gd`:

| Movie | Frames | Resolvable frame script | Defines exitFrame |
|---|---:|---:|---:|
| DAY1 | 2784 | 1401 | 1369 (49.2%) |
| NIGHT1 | 2646 | 1268 | 1233 (46.6%) |
| HOTEL1 | 1524 | 675 | 664 (43.6%) |
| SEA1 | 1982 | 771 | 759 (38.3%) |
| AIR1 | 1006 | 472 | 465 (46.2%) |
| **total** | **9942** | **4587** | **4490 (45.2%)** |

**And a warning about that tool.** It reports the frame path identical to the
existing runner for 220/220 ticks in all five movies, which reads like a licence
to switch the flag on. It is not. Turning `use_lingo_frames` on takes
`tests/test_walk_doorways.gd` from 0 failures to 5, `test_day1_navigation` from 0
to 2, and `test_director_runtime` from 28 to 31. Those suites exercise
transitions, walk arrival and movie loads that a straight tick from a single start
point never reaches.

So the frame-path measurement was necessary and insufficient, in the same way the
first eight VWSC offsets were. The 7 regressions are the next piece of work, and
they are the last thing between the interpreter and being the port's real script
engine.

## Honest remaining list

| Item | State |
|---|---|
| `on exitFrame` dispatch | implemented, flag off, 7 test regressions to diagnose |
| `on mouseUp` / `mouseDown` dispatch | implemented, flag off, 94.6% convergence |
| SEA1's 27 click disagreements | not investigated; systematic and localised |
| Deferred walks (190 cases) | `walkonby` not wired; counted, not working |
| Convergence beyond 5 movies | 56 of 61 movies with intervals unmeasured |
| `keyDown`, `startMovie`, `stopMovie`, `idle` | not dispatched |
| Retirement of the guessed tables | nothing retired; `movie_context.json`, `inventory_drops.json` and the lifted `on_click` are still what the game uses |
