## Why

Piposh 2 is a Lingo program that uses the Director score as a tempo clock and a bitmap library, but the
port is built as a score-driven movie with scripts attached to frames. The original's animation idiom
(write `locH`/`locV`/`memberNum of sprite 30`, call `updateStage()`, inside `on exitFrame` with
`go(marker(0))` parking the playhead) has nowhere to land: sprite writes go into an override dictionary
the renderer does not read, so most of the character engine is inert, and three pieces of the port
(`PuppetController`, the `held` flag, `_run_skipped_entry_scripts`) exist only to compensate.

The script census confirms the shape. The game defines `on exitFrame` 2504 times against `on enterFrame`
33 times and calls `go` 1066 times, so playback is driven from inside exit-frame handlers that
immediately jump. That is exactly the case the current frame runner does not model.

## What Changes

**Live channel state.** Add per-channel sprite records that Lingo writes land in and the renderer reads
back. Score frame data is applied as a **delta** gated by puppet ownership, both explicit (`puppetSprite`,
288 calls) and Director 7 automatic on property assignment. Clearing a puppet snaps the channel back to
score data. `the visible of sprite`, the game's most-written property at 1454 uses, becomes sticky channel
state the score never restores, replacing its current special case in `LingoHost.set_sprite_prop`.

**Complete the host property tables rather than the subset in use.** The parser already recognises 73
movie properties; the host binds 23 of them. Six of the unbound ones are used by the game about 158 times
(`the searchPath` 104, `the moviePath` 32, `the soundLevel` 14, `the mouseDown` 4, `the exitLock` 2,
`the freeBlock` 2) and today silently return 0. The sprite property table gets the same treatment. Binding
the whole enumerable table costs little more than binding the nine properties a census finds, and removes
the class of error where a miscount becomes a silent wrong answer.

**Loud failure for anything unbound.** Every unhandled property, builtin, event or member access raises a
named diagnostic carrying its script and handler location instead of returning 0. This is the mechanism
for surfacing what no census can predict. The port's documented recurring failure is scripts that ran and
did plausible-looking nothing, and silent defaults are what produce it.

**Suspend handlers across `go`.** `go`, `play` and movie switches park the running handler's state
(call stack, program counter, locals, `me`) instead of relocating the playhead under it. The frame cycle
advances, then the handler resumes at the statement after the `go`. `exitFrame` is suppressed on a jump
cycle.

**`updateStage()`** (237 calls) becomes a synchronous composite of current channel state, with no frame
advance and no script dispatch.

**Frame cycle ordering.** One playback step runs: wait gate, `exitFrame` for the outgoing frame, frame
load and delta apply, tempo and wait-condition decode, render, `enterFrame`, then resume any suspended
handlers. Each stage yields if a handler suspends.

**Hit testing against live state, at the right fidelity.** `intersects` (129 bytecode operations) is
currently `Rect2.intersects` at `lingo_host.gd:419`, a bounding-box test where Director uses a matte for
bitmap inks. `rollOver` (88), `the cursor of sprite` (155), `the clickOn` (396), `the constraint of sprite`
(10) and `the moveableSprite of sprite` (15) are all bound already but read `sprite_rect()`, which is
score data plus the dead override dictionary. All of them move onto channel state, and intersection moves
to matte level.

**Movie-scoped script resolution.** Handler tables are owned by the movie and rebuilt on movie change,
over the movie's own casts plus one shared archive. **BREAKING** for current behaviour: the table is flat
and first-loaded-wins today, so four of five movies run another movie's logic for handler names they define
themselves. Measured at HEAD (`handler-scope-baseline.md`): 10 duplicated names over the five core movies
and 13 over all 71, with 14 distinct names resolving outside their own movie in the core scope and 53 across
the full sweep; 9 of those resolve to DAY1 in both. The earlier estimate of 19 duplicated names is not
reproducible and 4.7 is checked against the measured baseline instead.
Mouse events resolve through a queue of source-typed entries resolved at dispatch time with `pass` and
`dontPassEvent` propagation, replacing the first-handler-wins walk. Key input keeps dispatching through
`the keyDownScript` handler-name indirection, which is read as well as written and targets at least five
distinct handlers.

**Retire the compensation layer.** `PuppetController`, the `held` flag and `_run_skipped_entry_scripts`
each shrink as the above lands. That shrinking is the acceptance test; a version leaving them the same
size has not moved the substrate.

## Scope boundary

The language layer is already complete and is **not** touched. The bytecode census over all 3349 scripts
yields a closed set of 55 opcodes, and every construct in it (chunk expressions, `tell`, `intersects`,
movie and sprite property access, field access, argument lists, the repeat forms) is already handled by
`tools/lingo_compile.py` and `lingo/lingo_interpreter.gd`. Rewriting the parser would be the most
expensive available mistake. What is missing is the host surface and the playback machine.

Already implemented natively and therefore outside this change: bitmap decode and ink, cast and member
resolution, film loops, audio, save and load.

Omitted, each with zero opcode or score reference anywhere in the corpus, recorded so the omission is
auditable rather than a judgement call: transitions (0 in score data, 0 `puppetTransition`), palette
puppeting and `the colorDepth` (0), digital video and `the movieRate` (0), `the blend`, `the trails` and
`the stretch` (0), non-bitmap sprite types (all 816,590 sprite records are type 16), `sendSprite` and
`the actorList` (0), and the D6 behaviour-instance event surface: `prepareFrame`, `beginSprite`,
`endSprite`, `mouseEnter`, `mouseLeave`, `mouseWithin`, `stepMovie`, `timeout` (0 each). Growth is
expected to be additive: a later title that exercises one of these adds a body, and the diagnostics above
are what will name it.

ScummVM's `engines/director` is the reference for these mechanisms, read for the model and cited by
function. No code is copied; it is GPL-2.0-or-later. It is **not** authoritative on semantics this game
depends on, so where the two disagree the game's own scripts decide and the divergence is declared.

The instance previously cited here does not survive reading the pinned source. `label(<int>)` was said to
return the n-th marker by position; in fact `b_label` branches on argument type and sends a number to
`func_marker`, which returns `getCurrentLabelNumber()` — the last marker at or before the playhead, as a
frame number. That is what the game needs and what the port already does. Recorded with its citations
under `verified_agreements` in `data/declared_divergences.json`. The precedence rule stands; it currently
has no confirmed instance.

## Capabilities

### New Capabilities

- `sprite-channel-state`: live per-channel sprite records, score data applied as a puppet-gated delta,
  explicit and automatic puppet ownership and release, sticky visibility, the complete sprite property
  table, and the composite point that `locH` and `locV` are views onto.
- `frame-cycle`: the ordering and yield points of one playback step, tempo and wait-condition decoding,
  the parked-playhead state and its effect on film loop advance, and `updateStage()` as a render flush.
- `lingo-suspension`: parking and resuming a handler across a frame boundary for `go` and movie switches,
  suppression of `exitFrame` on a jump cycle, recursion bounds, and retirement of the skipped-entry replay.
- `script-resolution`: per-movie handler scoping over the movie's own casts plus one shared archive, the
  source-type dispatch order, late resolution of the target script, `pass` propagation, and
  `the keyDownScript` indirection.
- `channel-hit-testing`: geometry and pointer queries against live channel state, covering matte-level
  intersection, rollover including the stale-bbox rule for blank sprites, `the clickOn`, per-channel
  cursor, movement constraint and draggability.
- `surface-diagnostics`: the complete-table contract and its enforcement. Every unbound property, builtin
  or event raises a located diagnostic rather than a default value, and a coverage report enumerates bound
  against enumerable surface so omissions stay visible.

### Modified Capabilities

None. `openspec/specs/` is currently empty; these are the repository's first specs.

## Impact

- `lingo/lingo_host.gd` — property get and set become channel-backed; the `puppet` override dictionary and
  the `visible` special case are removed; the property tables are completed; unbound names raise.
- `lingo/lingo_interpreter.gd` — must park and resume mid-handler, retaining call stack, program counter,
  locals and `me`. The one item with real implementation risk in GDScript.
- `lingo/lingo_engine.gd` — handler tables become movie-scoped and clear on movie change; event dispatch
  becomes a resolved-late queue.
- `director/director_runtime.gd` — frame cycle re-ordered around the yield points; `held`,
  `_run_skipped_entry_scripts` and the transition-redirect guard retire.
- `director/movie_player.gd`, `director/stage_canvas.gd` — draw from channel state instead of frame records
  plus an override lookup.
- `director/render_model_loader.gd` — must expose per-member masks for matte intersection.
- `director/puppet_controller.gd` — retires once channel writes drive the walk directly.
- `data/movie_context.json`, `data/walk_doorways.json` — hand-reconstructed tables become a second source
  of truth once the original scripts drive these decisions; retirement is sequenced, not immediate.

No new dependencies. No change to the exported asset format or the extraction tools.

Verification: the port has no unit tests, only measurement harnesses whose agreement scores can fall as
fidelity rises, and perfect agreement can mean an interpreted path is inert rather than correct. Each
phase needs its own before-and-after evidence (channel writes that reach the screen, handler resolutions
that stay inside their own movie, intersection results against the original's branches, the diagnostics
count trending down, a user-path smoke run), not a single convergence number.
