> **STALE — read before acting on this change.** This design was written while
> the port ran two stacked engines. The lower one is gone: `director_runtime.gd`,
> `render_model_loader.gd`, `movie_player.gd`, `lingo_host.gd`, `lingo_engine.gd`
> and the `assets/render_model` export have all been deleted, and the
> container-reading preview (`scenes/director_preview.tscn`) is the only engine.
> Unchecked task items in `tasks.md` that target those files cannot be done as
> written, and the run-commands in `surface-gap-backlog.md`, `oracle-status.md`
> and `handler-scope-baseline.md` name harnesses (`check_surface_coverage.gd`,
> `smoke.gd`, `lingo_handler_scope.gd`, `lingo_converge.gd`) that were deleted
> with them. Re-scope against the live engine before continuing.

## Context

The port runs two stacked engines. A native Godot score runner (`director/director_runtime.gd` tempo
clock, `render_model_loader.gd` cast resolution and BMP inks, `movie_player.gd` stage draw and input)
reads Director movies decoded to JSON under `assets/render_model`. On top of it the original game's own
Lingo executes: `tools/lingo_compile.py` parses all 3349 decompiled scripts to ASTs,
`lingo/lingo_interpreter.gd` walks them, `lingo_host.gd` binds Director concepts, `lingo_engine.gd`
reproduces the message hierarchy.

The substrate underneath is the wrong shape, as the proposal sets out. Three facts about the existing code
constrain every decision below.

- `LingoInterpreter` already has a control-signal channel, `enum Flow { NORMAL, EXIT_REPEAT, NEXT_REPEAT,
  RETURN, ABORT }`, propagated upward by `_exec_block`. Suspension extends a pattern that exists.
- `_exec_block` iterates `for stmt in stmts`, unindexed, so there is no position to resume from.
- `LingoHost.set_sprite_prop` writes into `puppet[channel][key]`, and only `visible` and `locH`/`locV` are
  read back, the latter only inside `sprite_rect()`. Everything else written is inert.

Measurements taken for this design, over all 3349 scripts:

| Question | Answer | Consequence |
|---|---|---|
| Can `go` appear in value position? | **0 occurrences** across if/while conditions, rhs of `=`, arithmetic and nested arguments | `_eval` never suspends; only statements do |
| Where is `go` called from? | 973 in event handlers, **95 in helper handlers** (`peoplefunk` 29, `objecttalktime` 25, `whatodoeveryframe` 11) | continuations must span nested `_invoke` frames |
| `go` inside `tell`? | **35 blocks in 31 files** | continuation must restore the tell target |
| `go` inside `repeat`? | **3 blocks, 1 file** (`master/MovieScript 107.ls`, chess) | loop state must be capturable; blast radius is one minigame |

## Goals / Non-Goals

**Goals:**

- Sprite property writes reach the screen, so the original character engine animates without a native
  stand-in.
- A `go` issued from inside frame or click handling behaves as the original does, without replaying entry
  scripts to compensate.
- Handler resolution stays inside the movie that owns the script.
- Unbound surface is named and located when touched, never defaulted to 0.
- **Every semantic decision is checkable against ScummVM's implementation**, by citation now and by
  behavioural diff against the same game once the oracle is standing. See Decision 1.
- `PuppetController`, the `held` flag and `_run_skipped_entry_scripts` become removable.

**Non-Goals:**

- No change to `tools/lingo_compile.py` or the AST shape. The language layer already covers the closed
  semantic surface the bytecode census yields.
- No bytecode VM. The port walks ASTs and will continue to.
- No implementation of transitions, palette cycling, digital video, non-bitmap sprite types or D6 behaviour
  instances. Each has zero reference in the corpus. This bounds what we *build*; it does not bound what we
  *check against*, and the oracle in Decision 1 covers the whole engine regardless.
- No retirement of `data/movie_context.json` or `data/walk_doorways.json` inside this change. They become
  redundant; retirement is sequenced separately.

## Decisions

### 1. ScummVM serves in two roles: cited reference, and executable oracle

**Citation reference, available now.** Every non-obvious semantic decision carries a
`ScummVM <file>:<function>` reference at a **pinned commit**, not at `master`. Master moves and line
citations rot; the previous review of this engine lost its notes entirely and had to be redone from
scratch this session. A `tools/fetch_scummvm_reference.sh` pins the commit and fetches the ~25 relevant
files read-only.

**Executable oracle, once data is extracted.** ScummVM carries an upstream detection entry for this exact
game, keyed on `piposh2.exe` plus `PIP2DATA/AIR1.DXR` md5 `cc6c9bb1acf76a0697a30d626e89543c`. So the
reference implementation can run the same movies the port runs, and it already emits a diffable state
vector:

| ScummVM output | Settles |
|---|---|
| `Score::formatChannelInfo()` — per frame: tempo, sound 1/2, frame-script `actionId`, then `CH: n` per occupied channel with castId, ink, puppet, visible, bbox | channel state, delta application, puppet ownership, sticky visibility |
| `kDebugEvents` level 5 — `processEvents: starting event script (<event>, <scriptType>, <scriptId>, <channel>)` | message hierarchy, `pass` propagation, per-movie handler scoping |
| `kDebugLingoExec` level 4 — per-instruction trace, plus the freeze and thaw messages | suspension ordering, whether a `go` resumed where we resume it |
| `kDebugLingoThe` — property get and set trace | the complete property tables, and which writes auto-puppet |
| `kDebugScreenshot` plus the built-in previous-build comparison | end-state rendering, per frame |

This replaces the port's current verification model, which has no tests and only convergence harnesses
whose agreement scores fall as fidelity rises and whose perfect scores can mean a path was inert.

**Licence position.** ScummVM is GPL-2.0-or-later. Reading it for the model, citing functions, and running
it as a behavioural oracle are all clean. Copying or transliterating code is not, and no code is copied.

### 2. The oracle is not authoritative on this game's semantics; the game's scripts are

The counterexample this decision was originally built on has been **withdrawn**. It claimed ScummVM's
numeric `label()` returns the n-th marker by position, which would give every room the same `whereami` and
kill all 138 gated handlers. Reading the pinned source refutes it: `lingo-builtins.cpp:2967 b_label`
branches on argument type, and only a *string* reaches the position-indexed `func_label`. A number goes to
`func_marker` (`lingo-funcs.cpp:238`), which at `m == 0` returns `Score::getCurrentLabelNumber()`
(`score.cpp:240`) — the last marker at or before the playhead, as a frame number. The game's 54 numeric
sites are all `label(0)` and its 648 `label("<name>")` sites are what `whereami` is compared against, so
both spellings must yield a frame number, and in both engines they do. `lingo_host.gd` already implements
it this way.

The decision itself stands on its own terms — the game's scripts are the ground truth and the oracle is a
second opinion — but it is a precaution, not a response to a known defect. The registry it requires exists
at `data/declared_divergences.json` with no divergences declared and this finding recorded as a verified
agreement, so the next candidate is checked against the source before it is written down.

So the precedence order is: **the game's decompiled Lingo, then the oracle's behaviour, then ScummVM's
source, then Director documentation.** Where we diverge from the oracle deliberately, the divergence is
recorded next to the binding with its evidence, and the differential harness is told to expect it rather
than reporting it as a failure every run.

### 3. Resolve the Director version from the file before building version-sensitive paths

> **RESOLVED (task 2.1).** Full working in `director-version.md`. The movies are **Director 7**: every
> one of the 86 extracted files reports config version `0x57E` at `DRCF` payload offset 36, which
> `humanVersion()` maps to 700, and carries a `VERS` chunk of 7.0. The three sources never actually
> disagreed. `frames_version: 13` and `sprite_record_size: 48` are exactly what a D7 movie writes — 48 is
> `kSprChannelSizeD7`, and ScummVM dispatches sprite layout on the config version, never on
> `framesVersion`. ScummVM's 850 describes the **projector**, and two genuine D8.5 files do ship at the
> install root; they are not part of the game's movie set.
>
> **The real defect is elsewhere, and it is what actually blocks 5.6, 6.6 and 8.4.** `score.cpp:1976`
> hard-codes `_numChannelsDisplayed = 120` when `framesVersion <= 13`, *skipping* the `uint16` that
> follows. That skipped field is the displayed-channel count, and reading it across all 61 score-bearing
> files gives 120 for 40 of them and **150 for 21**. Walking every frame's channel deltas and taking the
> highest byte written confirms the field predicts the data exactly: the 120-group saturates at byte 6024
> (channel 120, never past it), the 150-group at 7464 (channel 150). `ENDMOVI1.DXR` genuinely writes
> sprite channel 150 and is the only file exceeding ScummVM's 6048-byte ceiling — ScummVM truncates it.
>
> So the port reads the per-movie field at VWSC-header offset 18. It must not copy ScummVM's 120, which
> truncates, nor the `director-data-recovery` skill's 200, which over-allocates and makes any "channel N
> is off the end of the score" check vacuous. `MAX_D7_SPRITE_CHANNELS = 200` in
> `tools/director_film_loops.py:12` is fine as a buffer size but must not be reused as a channel count.
>
> One trap recorded for anyone parsing these files: two endiannesses are in play per file. The RIFX
> container follows its magic (`RIFX` big-endian, `XFIR` little-endian), but movie-resource chunk
> payloads (`DRCF`, `VWSC`, `VERS`) are **always big-endian in both**. Established empirically via
> `configLenSanityCheck`'s requirement that `len == 84`: the little-endian reading gives 21504 and a
> nonsense stage rect, the big-endian reading gives 84 and the game's real 640x480 stage, for all 86
> files.

Three sources disagree. ScummVM's detection entry classifies this game as version **850**. The repo's
`director-data-recovery` skill states **Director 7** and pins `MAX_D7_SPRITE_CHANNELS = 200`. The exported
score reports `frames_version: 13` with `sprite_record_size: 48`, which in ScummVM's loader takes the
branch that assumes 120 displayed channels.

This is not cosmetic. It selects the tempo encoding (the D6+ sentinels 255/254/248/247/246 versus the
pre-D6 scheme), the displayed-channel count, and whether automatic puppeting applies at all, since
ScummVM gates it on version 600 and above. Settle it from the movie file's own version field, record the
number, and make version an explicit input to the channel and tempo layers rather than an assumption baked
into them.

### 4. Suspension via an explicit continuation stack, not GDScript `await`

`go` sets a pending target and raises a new `Flow.SUSPEND`, propagating through `_exec_block` exactly as
`Flow.RETURN` does today. On the way up each block records its resume position and each `_invoke` records
its frame, producing a continuation stack the runtime parks. After the frame cycle advances, the stack is
replayed and execution continues at the statement after the `go`.

Alternative rejected: making the interpreter functions coroutines and awaiting a resume signal. In Godot 4
an `await`-containing function called without `await` returns a coroutine object instead of a value, so
every call site in `_exec`, `_eval`, `_call` and `_host_call` would need converting and a single missed
site fails silently rather than loudly. It also allocates per suspension against a 400,000-step budget.
The explicit stack costs nothing when nothing suspends and reuses machinery already in the file.

Model reference: `LingoState` and `Window::_frozenLingoStates`, which park callstack, program counter,
script, locals, `me` and operand stack.

### 5. Suspension is statement-level only

No `go` appears in value position, so `_eval` needs no continuation support. This is the largest available
simplification and it is measured, not assumed. Because the design depends on it, a compile-time check
asserts that no AST node marked `"command": True` ever appears as a subexpression.

### 6. `_exec_block` becomes indexed; blocks are the continuation unit

Resuming needs `(statement list, next index)` per nested block, plus explicit iterator state for `repeat`.
Given one file suspends inside a loop, loop continuations carry their state explicitly rather than the
design being contorted around them.

### 7. Channel state is a layer separate from score data

Frame sprite records stay immutable score data. A channel layer holds live per-channel state: the sprite
fields plus channel-only fields the score never supplies (`visible`, `cursor`, `constraint`, film loop
position). The renderer reads channels only. `sprite_rect()` and the `puppet` override dictionary both
disappear.

### 8. Score application is a delta gated by puppet ownership

On a frame change the loader supplies which fields the score re-specifies; the channel copies only those,
skipping fields it owns. Ownership is acquired explicitly via `puppetSprite` and automatically when Lingo
assigns a property. Clearing a puppet re-applies score data to that channel immediately, which is what
makes `puppetSprite N, 0` visibly snap back.

Ownership releases only when the score explicitly re-specifies the field **on a frame-number change**. A
parked playhead therefore never releases, which is exactly what the parked-room idiom needs. This
asymmetry is easy to implement backwards and is called out for that reason.

### 9. `visible` is channel state with no score counterpart

Not a puppet question. The field initialises visible, is written only by Lingo, and is never restored by
the score. This retires the current special case and the two failed policies before it: suppressing
frame-handler hides, and honouring only puppeted writes.

### 10. `updateStage()` composites; it does not tick

A synchronous composite of current channel state plus queued puppet sounds. No frame advance, no script
dispatch. This is what lets a parked room animate from inside one `exitFrame` without re-entrancy.

### 11. The frame cycle is an ordered sequence with a yield check after every stage

Wait gate, `exitFrame` for the outgoing frame (suppressed when a jump is pending), frame load and delta
apply, tempo and wait decode, render, `enterFrame`, resume parked continuations. After each stage the
runtime checks whether a handler suspended and returns early if so. Ordering is load-bearing and inserting
a stage later is the change most likely to break it subtly, so the sequence is specified as data rather
than as control flow scattered through `game_step()`.

### 12. Handler tables are owned by the movie

One table per loaded movie over that movie's own casts, plus one shared archive consulted afterwards,
rebuilt on movie change. Today's table is flat, first-loaded-wins and never cleared, which is why handler
names with multiple definitions resolve to whichever movie loaded first.

Measured at HEAD by `tools/lingo_handler_scope.gd`, recorded in `handler-scope-baseline.md`. The harness
runs two passes over the real `LingoEngine` — one fresh engine per movie, which is the table this decision
asks for, against one engine carried across every movie, which is what `director_runtime.gd` actually holds
— and reports names whose winning owner differs between them.

| | core (5 movies) | full (71 movies) |
|---|---|---|
| handler names with more than one definition | 10 | 13 |
| distinct names resolving outside their movie | 14 | 53 |
| of those, resolving to DAY1 | 9 | 9 |
| shadowed (movie defines it, loses anyway) | 26 | 63 |
| movies resolving at least one handler outside themselves | 4 of 5 | 70 of 71 |

The estimate of 19 duplicated names that this decision originally carried is **not reproducible**; 4.7 is
checked against the table above. The full-scope leaked-in total is dominated by movies with no
`data/lingo/` directory of their own, which inherit whatever the sweep has accumulated.

### 13. Intersection is matte-level for bitmap inks

`intersects` currently reduces to `Rect2.intersects` at `lingo_host.gd:419`. The 554466 sprites at ink 36
and 1765 at ink 32 are matte inks, where Director tests the shape rather than the box.
`render_model_loader.gd` must expose a per-member mask; bounding box stays the fast reject.

### 14. Property access is table-driven and complete

One table each for sprite, movie and member properties, enumerating every name in a recorded vocabulary
rather than the subset a census finds used. Any name absent raises a located diagnostic. Table-driven
access makes that defect class structurally impossible rather than individually fixable. ScummVM reaches
the same conclusion from the other direction with its `kDebugLingoStrict` mode.

Two premises of this decision were corrected during implementation.

**The parser is not the source of the vocabulary.** `SYSTEM_PROPS` in `tools/lingo_compile.py` is dead
code that nothing references, and `parse_the`, `sprite_prop` and `member_prop` all accept any identifier,
so three of the four categories have no compiler-side closure. The manifest at
`data/lingo_vocabulary.json` is generated from ScummVM's `lingo-the.cpp` and `lingo-builtins.cpp` tables at
the pinned revision, which is the only closed enumeration available, with corpus read/write counts joined
in. Consequence: an arbitrary identifier can still reach dispatch, so "bind everything" cannot mean "never
raise" — an unknown name and a known-but-unsupported name must raise distinguishably.

**"The host binds 23" is not reproducible.** The host binds 24 distinct movie names: 18 in
`get_system_prop` across 12 match arms and 6 in `set_system_prop` across 2 arms, with no overlap. Counting
match arms rather than names is what produced the old figure. The gap is also wider than stated in a way
the count hides: 4 of the 24 (`drawrect`, `rect`, `titlevisible`, `windowtype`) are window fields rather
than movie properties, and 2 (`stagewidth`, `stageheight`) exist in neither ScummVM nor Director and are
this port's own inventions. `get_sprite_prop` shows the same shape, binding 18 names of which `castlib`
and `movablesprite` are outside the vocabulary. Enumerable counts: sprite 52, movie 156, member 80,
builtin 243.

**Reads and writes are separate surfaces.** `set_sprite_prop` accepts any key into the `puppet`
dictionary while `get_sprite_prop` falls through to `return 0`, so today every sprite write is trivially
"bound" and every unbound read silently lies. The tables and the coverage check both carry direction.

## Risks / Trade-offs

- **Oracle prerequisite** → Running ScummVM needs `PIP2DATA` extracted from `~/Downloads/piposh2.exe`, and
  the previously extracted copy is gone from this machine. Mitigation: extract in a Docker image with Wine,
  scripted and committed, so the oracle is reproducible rather than a one-off manual step. ScummVM itself
  is available as a bottled formula.
- **Continuation correctness across nested blocks, `tell` and `repeat`** → The hardest part. Mitigation:
  land the flat case first (973 of 1068 sites are directly in an event handler body), then nested frames,
  then `tell`, then loops. Each tier has a measured site count, and a suspension arriving in an
  unimplemented tier raises rather than silently mis-resuming.
- **Turning on live channel writes makes roughly 1548 previously inert writes take effect at once** →
  Expect visible regressions on first run, not a clean improvement. Mitigation: flag per capability, plus a
  channel-write report naming which channels newly move, diffed against the oracle.
- **`whatodoeveryframe` already double-navigates** because walk globals alias `PuppetController`.
  Mitigation: retire `PuppetController` only after suspension lands, so the original arrival branch runs in
  the right order rather than after a native walk has completed.
- **Step and depth guards interact with suspension** → A parked continuation resumed each cycle must not
  accumulate against `MAX_STEPS` forever, and `_depth` must be restored on resume rather than
  re-incremented. Mitigation: budgets reset per cycle, depth restored from the continuation record.
- **Loud failure will be loud** → Completing the tables and raising on unbound names surfaces a backlog on
  first run. Mitigation: diagnostics deduplicated by name and location, counted, and treated as the backlog
  rather than as a regression.
- **The oracle can be wrong for this game** → Decision 2 exists because it demonstrably is, on `label(0)`.
  Mitigation: divergences are enumerated and expected by the harness, so a growing divergence list is a
  signal to re-read the game's scripts rather than to change the port.

## Migration Plan

Each capability lands behind its own flag, in dependency order, and each phase has a named differential
check against the oracle where the oracle covers it.

0. Oracle standing: Docker plus Wine extraction of `PIP2DATA`, ScummVM installed, trace capture scripted.
   Also settles Decision 3's version question from the file.
1. `surface-diagnostics` and the complete property tables. Independent, and it instruments everything after
   it. Check: property-access trace against `kDebugLingoThe`.
2. `script-resolution` movie scoping. Independent of the channel work and shippable alone. Check: dispatch
   chain against `kDebugEvents`.
3. `sprite-channel-state` channels and delta application. Nothing downstream works without it. Check:
   per-frame channel dump against `formatChannelInfo()`.
4. `channel-hit-testing` onto channel state, matte intersection last.
5. `lingo-suspension`, in the four tiers of the risk above. Check: freeze and thaw points against
   `kDebugLingoExec`.
6. `frame-cycle` re-ordering, then retire `held` and `_run_skipped_entry_scripts`.
7. Retire `PuppetController`.

Rollback is per flag. Note the trap already recorded in `director-port-architecture`: the engine is built
when *any* flag is set, so a guard on "is there an engine" is not a guard on "is this flag on". Guards must
test the specific flag.

## Open Questions

- Which Director version is Piposh 1, the expected next title? It decides how much version branching to
  build into the channel and dispatch layers now. Not blocking this change.
- ~~Does ScummVM's `piposh2` target actually reach playable state?~~ **ANSWERED, task 1.4 —
  `oracle-status.md`.** Detected, and it runs, but far more weakly than this decision assumes. Launching
  the target plays the projector's own one-frame score and stops. With the engine's `start_movie` key it
  plays `strtgame.dxr` (19 frames, 167,400 channel records, clean exit); `DAY1.DXR` and `DAGI.DXR` both
  **segfault** at the transition into playback, after loading fully.

  Worse for Decision 1: **the oracle runs this game as v850 and cannot be told otherwise.** The version is
  seeded from the detection entry and `cast.cpp:630` only ever *raises* it, so a D7 movie stays at 850.
  ScummVM's own VWCF checksum fails as a result. Every version-gated comparison — tempo encoding,
  displayed-channel count, config layout — is therefore invalid; mechanism comparisons (message hierarchy,
  `pass` propagation, freeze/thaw, property sequencing) remain sound, and those are what the port most
  needs. A difference caused by the 850 is a defect in the comparison, not a divergence to declare.
- Does any `tell` block's `go` target a window rather than the host movie? 35 blocks contain one; the
  continuation's tell-target restoration differs if so.
- Do the ink-32 sprites need a different matte rule from ink 36, or does one mask path serve both?
- Should film loop advance be gated on the parked-playhead state, as ScummVM gates it on an explicit-jump
  flag in D4? Confirm against the game rather than assuming.
