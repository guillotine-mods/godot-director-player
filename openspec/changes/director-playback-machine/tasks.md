## 1. Reference and oracle

- [x] 1.1 Add `tools/fetch_scummvm_reference.sh` pinning a ScummVM revision and fetching the ~25 relevant `engines/director` files into an ignored local directory; record the pinned revision in the repo
- [x] 1.2 Add `tools/extract_piposh2_data/Dockerfile` plus a run script that runs the VISE installer under Wine and emits `PIP2DATA` (83 `.DXR`/`.CXT`, `MASTER.CST`, `HEZSAVE.DIR`, `strtgame.dxr`) to a host directory
- [x] 1.3 Verify the extracted `PIP2DATA/AIR1.DXR` matches md5 `cc6c9bb1acf76a0697a30d626e89543c` and size 2119111, which is what ScummVM's detection entry keys on. **Note:** neither detection hash covers the whole file, and the prefix says which 5000 bytes. `f:` hashes the FIRST 5000 (so `head -c 5000 AIR1.DXR | md5` = `cc6c9bb1...`); `t:` hashes the LAST 5000 (so the projector is `tail -c 5000 PIPOSH2.EXE | md5` = `9d33c0d6...`). Full-file md5s match nothing: AIR1.DXR is `909a55d5...`, PIPOSH2.EXE is `ccc1faae...`
- [x] 1.4 Install ScummVM and confirm the `piposh2` target is detected and reaches its first playable frame; record what does and does not work, since the detection entry proves intent and not coverage. **Findings in `oracle-status.md`: detected; plays `strtgame.dxr` only; `DAY1`/`DAGI` segfault; runs as v850 and cannot be lowered**
- [x] 1.5 Script trace capture from ScummVM: `tools/capture_scummvm_trace.sh`. **Correction:** the per-frame channel dump is NOT a console command — it is `debugC(9, kDebugLoading)` at `score.cpp:2289`, which is what makes capture scriptable
- [x] 1.6 Write `tools/oracle_diff.py` that reads a ScummVM trace and a port trace and reports differences, with a declared-divergence list it treats as expected. **Built and runs; NOT yet validated** — rendered-frame vs playback-step alignment is unresolved, so its difference count is not evidence. See `oracle-status.md`

## 2. Director version resolution

- [x] 2.1 Read the version field from a movie file in the extracted data and record the actual Director version, resolving the three-way conflict between ScummVM's detection value 850, the `director-data-recovery` skill's Director 7, and the exported `frames_version: 13`
- [ ] 2.2 Make Director version an explicit input to the runtime rather than an assumption, sourced from the exported render model
- [ ] 2.3 Add the version number to `assets/render_model/*/summary.json` via the export tool, and regenerate
- [ ] 2.4 Record which behaviours the version selects (tempo encoding, displayed channel count, whether automatic puppeting applies, retained-bounds rollover) as a table in the change directory

## 3. Surface diagnostics and complete property tables

- [x] 3.1 Add a diagnostics sink that records name, category, script and handler, deduplicates by name and location, counts occurrences, and emits a machine-readable set
- [x] 3.2 Separate the unset-variable category from the unbound-name category so an uninitialised local is never reported as a missing binding
- [x] 3.3 Extract the compiler's recognised vocabulary from `tools/lingo_compile.py` into a generated manifest of sprite, movie and member property names plus builtin names
- [x] 3.4 Convert `LingoHost` property access to table-driven dispatch for sprite, movie and member properties
- [x] 3.5 Bind the movie properties currently recognised by the compiler but unbound in the host, starting with the six the game reads (`the searchPath`, `the moviePath`, `the soundLevel`, `the mouseDown`, `the exitLock`, `the freeBlock`)
- [x] 3.6 Bind the remaining recognised movie properties, or declare each explicitly unsupported so it raises rather than defaulting
- [x] 3.7 Replace every silent default in the host's property and builtin paths with a diagnostic
- [x] 3.8 Add `tools/check_surface_coverage.gd` comparing bound tables against the generated manifest and reporting gaps per category
- [x] 3.9 Run the coverage check and a play session, and commit the resulting gap list as the starting backlog
- [x] 3.10 Add the declared-divergence registry, with marker-relative numeric label resolution as its first entry and its supporting evidence
- [x] 3.11 Add the trace export required by `surface-diagnostics`, off by default, covering channel state, dispatch decisions and property accesses

## 4. Per-movie script scoping

- [x] 4.1 Add a harness that reports, per movie, which movie-script handler names resolve to a definition owned by a different movie
- [x] 4.2 Run it and record the baseline, expected to show the 19 duplicated handler names resolving to a single movie's copies
- [x] 4.3 Move movie-script handler tables in `lingo_engine.gd` from one flat table to one table per loaded movie, built from that movie's own casts
- [x] 4.4 Add the single shared cast archive as a second lookup consulted only after the current movie's table
- [x] 4.5 Clear and rebuild the table on movie change, before any event is dispatched in the new movie
- [x] 4.6 Raise a diagnostic when a handler name resolves in no table
- [x] 4.7 Re-run 4.1 and confirm no cross-movie resolutions remain
- [ ] 4.8 Diff event dispatch against the oracle trace for at least two movies that share handler names

## 5. Live channel state and delta application

- [x] 5.1 Add the channel record type holding sprite fields plus the channel-only fields (visibility, cursor, constraint, film loop position) — **landed upstream** as `director/sprite_channel.gd` (`visible`, `cursor`, `constraint`, `loop_frame`/`loop_cast_lib`/`loop_cast_id`/`loop_score_frame`)
- [x] 5.2 Build the channel array on movie load and expose channel lookup from the runtime — **landed upstream**: `DirectorRuntime.channel_for()` and `channel_sprites()`
- [ ] 5.3 Emit, from the export tool, which fields each frame's sprite record re-specifies, so delta application has a source; regenerate the render model. **Confirmed still needed**: exported records are fully resolved (`back_color, cast_id, cast_lib, channel, fore_color, has_image, height, ink, loc_h, loc_v, sprite_type, width, x, y`) with no re-specification mask. 5.4's true delta and 5.7's per-field release both block on this
- [ ] 5.4 Implement delta application on frame change: copy only re-specified fields, clear channels absent from the incoming frame. **Half landed upstream**: `reconcile_channels` clears absent channels and skips puppeted ones, but `replace_from_score` copies the whole record rather than the re-specified fields — needs 5.3
- [ ] 5.5 Implement explicit whole-channel ownership via `puppetSprite`, including immediate re-application of score data when ownership is cleared
- [ ] 5.6 Implement automatic per-property ownership on assignment, gated on the Director version established in 2.1. **Now fully specified** in `docs/SCUMMVM_REFERENCE.md` — the property set, the `_puppet || version < 600` gate, and the per-field release map, all cited. Version is 700, so it applies. `sprite_channel.gd` deferred this pending exactly that reading
- [ ] 5.7 Implement ownership release only when the score re-specifies the field and the frame number changes, and add a test that a parked playhead never releases
- [ ] 5.8 Move `visible` onto the channel record as program-owned state the score never restores, and delete the special case in `set_sprite_prop`
- [x] 5.9 Add the composite location point with `locH` and `locV` as views onto it — **landed upstream**: `SpriteChannel.loc()` / `set_loc()`, moving the box by the registration offset rather than recentring
- [x] 5.10 Point `movie_player.gd` and `stage_canvas.gd` at channel state and delete `sprite_rect()` and the `puppet` override dictionary — **landed upstream**: `draw_current_frame` reads `runtime.channel_sprites()`, the `puppet` dictionary is gone, and `sprite_rect()` now reads channel state (kept, not deleted, as the hit-test accessor)
- [ ] 5.11 Add a report counting sprite property writes that change what is drawn, and record the before and after against the current 1954 writes
- [ ] 5.12 Diff per-frame channel state against the oracle for one hub room and one cinematic

## 6. Channel hit testing

- [ ] 6.1 Move all geometry and pointer queries onto channel state
- [ ] 6.2 Expose per-member opaque masks from `render_model_loader.gd`, cached rather than recomputed per query
- [ ] 6.3 Implement shape-level `intersects` for matte inks with a bounding-box fast reject, and a recorded diagnostic where a mask cannot be produced
- [ ] 6.4 Decide from the game whether ink 32 needs a different mask rule from ink 36, and implement accordingly
- [ ] 6.5 Move `rollOver` onto channel state, excluding channels whose visibility is off
- [ ] 6.6 Implement the retained-bounds rollover rule for blank channels, gated on the version from 2.1
- [ ] 6.7 Implement the last-clicked-channel record, including that a release away from any channel does not clear it
- [ ] 6.8 Move per-channel cursor, movement constraint and draggability onto channel state, with dragging marking location as program-owned
- [ ] 6.9 Verify the inventory drop paths against the original scripts' branches rather than against the current hand-authored drop rules

## 7. Handler suspension

- [ ] 7.1 Add `Flow.SUSPEND` to the interpreter's control-signal enum and propagate it through `_exec_block` alongside `Flow.RETURN`
- [ ] 7.2 Convert `_exec_block` to indexed iteration so a resume position exists
- [ ] 7.3 Add the continuation record capturing per frame the statement list, next index, locals, owning script and `me`
- [ ] 7.4 Add the build-time check asserting no command-call AST node appears in a value position, and wire it into the compile check
- [ ] 7.5 Change navigation host bindings to record a pending target and raise `Flow.SUSPEND` instead of navigating
- [ ] 7.6 Park continuations on the runtime and add the resume entry point
- [ ] 7.7 Tier 1: support suspension directly in an event handler body, which is 973 of 1068 call sites
- [ ] 7.8 Tier 2: support suspension across nested handler calls, which is the remaining 95 sites including `whatodoeveryframe` and `peoplefunk`
- [ ] 7.9 Tier 3: support suspension inside a `tell` block, restoring the tell target on resume, for the 35 blocks that contain one
- [ ] 7.10 Tier 4: support suspension inside a `repeat` construct by capturing iteration state, for the 3 blocks in `master/MovieScript 107.ls`
- [ ] 7.11 Raise a located diagnostic when suspension occurs in a tier the build does not yet support, with no partial resume
- [ ] 7.12 Reset the step budget per playback step and restore call depth from the continuation rather than re-incrementing
- [ ] 7.13 Bound suspensions resolved per step and report on reaching the bound
- [ ] 7.14 Diff freeze and resume points against the oracle's Lingo execution trace for a parked hub room

## 8. Frame cycle

- [ ] 8.1 Express the playback step as an ordered stage sequence in data, replacing the inline flow in `game_step()`
- [ ] 8.2 Add the yield check after every stage so a suspension ends the step
- [ ] 8.3 Implement frame-exit suppression when navigation is pending, and once-per-frame exit semantics
- [ ] 8.4 Implement tempo and wait-condition decoding for the version from 2.1, covering frame rate, fixed delay, wait for click and wait for a sound channel
- [ ] 8.5 Ensure a pending navigation cancels an active wait
- [ ] 8.6 Track the parked-playhead state and expose it to film loop advance
- [ ] 8.7 Decide from the game whether film loop advance is gated on the parked state, and implement accordingly
- [ ] 8.8 Reimplement `updateStage()` as a synchronous composite plus queued puppet sounds, with no frame advance and no dispatch
- [ ] 8.9 Implement end-of-score handling: return to a pushed caller position, otherwise the first frame
- [ ] 8.10 Diff the stage ordering against the oracle for a movie that navigates from frame entry

## 9. Retirement

- [ ] 9.1 Confirm each flag guard tests its own flag rather than whether an engine exists, which is the trap recorded in `director-port-architecture`
- [ ] 9.2 Remove `_run_skipped_entry_scripts` and confirm room entry still sets state correctly across the transitions it was covering
- [ ] 9.3 Remove the `held` flag now that the parked-playhead state is explicit
- [ ] 9.4 Remove the transition-redirect guard in `director_runtime.gd`
- [ ] 9.5 Claim `whatodoeveryframe` or let it run, deciding from whether it double-navigates once suspension is in place
- [ ] 9.6 Retire `PuppetController` and let channel writes drive the walk, with the walk globals reading channel state directly
- [ ] 9.7 Record the line-count change for `PuppetController`, the `held` flag and `_run_skipped_entry_scripts` as the acceptance evidence for this change
- [ ] 9.8 Re-run the user-path smoke test and the coverage check, and record the diagnostic count against the 3.9 baseline
- [ ] 9.9 List which rows of `data/movie_context.json` and `data/walk_doorways.json` the original scripts now decide, as the scope of the separate retirement work
