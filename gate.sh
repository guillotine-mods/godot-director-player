#!/bin/bash
# Run the refactor gates. Every step must reproduce the recorded pass/fail SET,
# which is **every entry in ALL passing and none failing**, measured on 4.7.1
# against GATE_ROOT's default by a whole-suite run at the commit this line was
# written. There is no expected failure any more, so any red is a regression and
# needs no triage against a list of excuses.
#
# That set is now enforced rather than only recorded: anything other than PASS
# exits 1. The alternative was a tracked file of expected statuses for CI to diff
# against, which is precisely the list of excuses the paragraph above records
# having escaped from, so it was not built.
#
# How many entries that is on the day you read it is deliberately not written
# here, for the reason README.md gives and the paragraph below demonstrates: the
# set is uniform, so the count says nothing the sentence above does not, and it
# is the only part of this header that has ever been wrong. Run it and count.
#
# The two this line used to carry were not the standing costs they read as:
#
#   debug_bindings  was "config not code": `snapshot = "F10"` in the tracked
#                   director_game.cfg, colliding with a keyCode rating tests at
#                   48 sites, while the code default had already moved to F11.
#                   One word.
#   play_suspends   was "PASS or FAIL, about half and half" on an assertion that
#                   waited a fixed six frames for a movie to load. Waiting on the
#                   condition instead made it deterministic -- and it then failed
#                   every time, because the flake had been hiding a real red
#                   (bugs.md 54). A flake is not noise; it is a result nobody has
#                   to explain.
#
# A count here said 54 entries while ALL held 61, then 62, then 66 while it held
# 68 -- `launcher_surface` (532f1e4b) and `film_loop_scale` (15fab73c) each joined
# in the two commits after the one that wrote 66, and neither moved it. Three
# generations of this comment carried a wrong number and each was corrected by
# somebody who had to go looking for a failure that was not there, which is what
# the paragraph below is about, one paragraph above where it kept happening. So
# the number is gone rather than corrected a fourth time. If you want it:
#
#   sed -n 's/^ALL="\(.*\)"$/\1/p' gate.sh | wc -w
#
# anchored at the line start on purpose, because the obvious `grep -o 'ALL="..."'`
# form matches its own occurrence in a comment like this one and answers one too
# many. That is not a hypothetical; it happened while this line was written.
#
# `boot_state` was the long-standing red in the line this replaces and passes now.
#
# The previous version of this comment said 11 pass / 2 fail with cursor_preview
# red, and none of those three numbers survived being measured. A recorded set
# is the thing the gate exists to compare against, so it is worth more than the
# other comments here: re-measure it when it moves rather than leaving it.
#
# Runs wherever the checkout is, on macOS and on Windows git-bash. Where Godot
# is and what to do without a `timeout` are in gate_env.sh, once, rather than
# in a line here and a second copy of it in check.sh.
cd "$(dirname "$0")" || exit 1
. ./gate_env.sh
G=$(gate_find_godot) || exit 1
gate_announce_godot "$G"
# Before the first harness, because the pack decides what every one of them
# prints. It is not this suite's subject -- nothing in `ALL` is the 3D title --
# and that is exactly why it has to be built rather than skipped: the autoloads
# it carries fail in *every* entry, so an unbuilt pack puts twelve errors into
# each of the 76 results the run is here to produce. See `gate_require_pack`.
gate_require_pack

# Pin the corpus. A gate is only meaningful against the game its baseline was
# recorded on, and the config is a working file that gets pointed at whichever
# title is being looked at -- a run against another game reads as five
# regressions that are really five different movies.
#
# Passed per harness with `--root`, which every reader honours because
# `DirectorPaths.load_config` applies it. This used to rewrite the `root` line
# in director_game.cfg and restore it on exit, which pinned the corpus by
# mutating a file the whole repo shares: two runs at once, which happens the
# moment more than one agent is working, had each other's corpus swapped out
# mid-run and reported the other title's movies as this title's regressions.
# One run measured six that way and none was real. A flag on the command line
# cannot do that to anybody.
ROOT="${GATE_ROOT:-piposh2}"

# Pin the boot movie with the root, for the same reason and in the same breath.
# `--root` alone is half a pin: the boot movie still came from the config, so with
# the tracked config pointing at `rating`'s `mainmenu.dir` every entry below that
# does not name its own `--file` looked for that container under `piposh2`, found
# nothing, and asserted over an empty score. `STRTGAME.dir` is the boot movie of
# both piposh2 and piposh, which are the two roots this list names.
BOOT="${GATE_BOOT:-strtgame.dir}"

# Per-harness ceiling. Raised from 300s because several harnesses now sweep the
# whole corpus, and with a handful of agents running Godot at once a sweep that
# takes 40s alone can exceed five minutes. Override with GATE_TIMEOUT.

# Serialise concurrent runs. Not for the corpus any more -- `--root` is per
# process and no longer touches a shared file -- but for .godot/, which
# concurrent Godot runs contend over badly enough to hang indefinitely rather
# than fail (AGENTS.md). A hang is what the ceiling below turns into a TIMEOUT
# line, and a suite of them is 40 minutes of nothing.
LOCK=".gate.lock"
HELD=""
for _ in $(seq 1 900); do
  if mkdir "$LOCK" 2>/dev/null; then HELD=yes; break; fi
  sleep 1
done
# Refuse rather than proceed. The first version fell through the wait and ran
# anyway, and its EXIT trap then removed *whoever's* lock was there -- so a long
# run lost its lock to a later one, two gates ran against each other, and the
# results of both were fiction. Releasing only a lock we took is the other half:
# without it the trap is a lock-breaker with extra steps.
if [ -z "$HELD" ]; then
  echo "gate: another run has held $LOCK for 15 minutes; not starting a second one." >&2
  echo "gate: if nothing is running, remove $LOCK by hand." >&2
  exit 2
fi
trap '[ -n "$HELD" ] && rmdir "$LOCK" 2>/dev/null' EXIT

echo "corpus: $ROOT"
ALL="game_config root_boot embedded_cast_payload title_mapping title_list export_presets_check preview_surface exit_leaks sound_exit_leak boot_state:--file@PIP2DATA/EXODUS.DIR frame_events window_preview window_order text_and_shapes text_and_shapes:--root@piposh@--file@PIPDATA/CAPROOM.dir text_and_shapes:--root@piposh@--file@PIPDATA/MAINMENU.dir field_expands:--file@PIP2DATA/SAVELOAD.dir field_expands:--root@piposh@--file@PIPDATA/CAPROOM.dir cursor_preview cursor_hotspot cursor_descent:--file@PIP2DATA/SAVELOAD.dir mouse_sprite_props:--file@PIP2DATA/DAY1.dir hint cursor_cross_cast:--root@rating@--boot@mainmenu.dir text_xtra_members vector_shape:--root@piposh-dream text_xtra_members:--root@piposh text_xtra_surface:--root@piposh@--file@PIPDATA/SLOTMACH.dir text_xtra_surface:--file@PIP2DATA/MAP.dir audio_misses container_equality_check lingo_logic_check lingo_designator_check field_designator field_designator:--root@piposh lingo_builtins_check keyboard_check decode_stall decode_stall:--root@piposh-dream@--file@fritz2.dir hotspots trails sprite_drag debug_bindings snapshot_check container_picker_check go_movie_arg drawn_size_stability score_write_mask:--all sprite_constraint sprite_constraint:--root@rating@--file@ARCADE2.dir sprite_true_colour sprite_true_colour:--root@piposh-dream member_ref_round_trip reg_point movie_churn film_loop_cast film_loop_cast:--root@piposh-dream film_loop_scale film_loop_restart:--root@piposh-dream film_loop_nesting:--root@piposh-dream cast_script_sprite:--root@piposh-dream skip_state wait_frames lingo_fault_sink undefined_handler undefined_live:--root@rating@--boot@MAINMENU.dir lingo_execute_boundary mouse_events touch_input hilite playhead_escape puppet_persists puzzle_board:--root@piposh-dream inventory_bag:--root@rating@--boot@mainmenu.dir hex_board:--root@piposh-dream plane_heading:--root@piposh-dream west_walk:--root@piposh-dream west_shoot:--root@piposh-dream puppet_freeze:--file@PIP2DATA/CHESS.dir@--channel@8@--wheels@138,175@--span@7 editable_text:--file@PIP2DATA/SAVELOAD.dir save_movie:--allow-writes save_overlay text_codepage save_state sound_wait sound_rate sound_replay_guard sound_linked_member sound_cue_points sound_tempo_wait:--root@rating@--boot@mainmenu.dir key_polling key_overlay:--root@piposh2@--boot@PIP2DATA/ARCADE2.dir@--touch-input key_overlay:--root@rating@--boot@arcade1.dir@--touch-input key_overlay:--root@rating@--boot@NAVIGATE.dir@--touch-input key_overlay:--root@piposh@--boot@PIPDATA/ROULLETE.dir@--touch-input movie_tempo transition_render transition_render:--root@rating@--boot@EGOZROO1.dir film_loop_children:--root@piposh-dream@--boot@plane1.dir lscr_layout lscr_layout:--root@piposh lscr_disasm_sweep lscr_disasm_sweep:--root@rating lscr_decode lscr_decode:--root@rating script_compile_check script_compile_check:--root@piposh script_compile_check:--root@piposh-en script_compile_check:--root@piposh-ru audio_misses:--root@piposh-ru liveness_sweep:--root@piposh-ru@--limit@12 parse_residue lingo_surface_audit lingo_objects lingo_scope_check lingo_local_diagnosis lingo_file_codepage:--allow-writes timeout_and_actors fileio_xtra buddyapi_xtra:--allow-writes media_surface video_fallback avi_decode video_plugin mpeg1_decode mpeg1_audio video_tempo_wait lingo_movie_surface property_surface lingo_system_builtins update_stage click_eligibility click_chain primary_scripts sprite_lifetime behaviour_me:--file@PIP2DATA/DAY1.dir behaviour_params frame_reentry:--root@piposh@--file@PIPDATA/CANON.dir@--label@game6@--loop-to@350 frame_reentry:--root@rating@--file@NAVIGATE.dir@--label@thepool@--loop-to@542 frame_reentry:--root@rating@--file@NAVIGATE.dir@--label@TheLoby@--loop-to@101 play_suspends play_stack_bound play_return_frame:--root@rating@--boot@mainmenu.dir play_return_frame:--root@piposh-dream sound_paths sound_folder_scope sound_folder_scope:--root@piposh-dream sound_survey:--root@piposh2@--all fast_forward key_chain mouse_poll:--file@PIP2DATA/CHESS.dir@--label@ches1 sprite_collision collision_arms collision_arms:--root@piposh-dream@--boot@hatul3.dir collision_arms:--root@rating@--boot@BLAEGOZ.dir collision_ink mask_ink:--file@PIP2DATA/DAY1.dir hit_hole:--file@PIP2DATA/SAVELOAD.dir hit_hole:--root@piposh@--file@PIPDATA/CAPROOM.dir@--frames@4000 ink_survey:--all channel_occupancy:--max-frames@120 label_index pause_holds:--file@PIP2DATA/SAVELOAD.dir@--label@savegame2@--hotspot cannon_hit:--root@piposh idle_clock idle_clock:--root@piposh@--boot@PIPDATA/DAY1.dir new_game_reset:--root@rating@--boot@NAVIGATE.dir day_checklist:--root@piposh-dream stage_compare:--root@piposh@--boot@PIPDATA/PIANO.dir@--frame@37@--debug-ui@off@--render@PIPDATA/PIANO.dir@--band@8,466,252,9@--skip-top@60 stage_compare:--root@piposh@--boot@PIPDATA/PIANO.dir@--frame@39@--debug-ui@off@--render@PIPDATA/PIANO.dir@--band@8,466,252,9@--skip-top@60 bitmap_geometry palette_cycle palette_corpus audio_coverage liveness_sweep:--limit@12 liveness_sweep:--root@piposh-dream@--only@mainmenu.dir@--scenes@--scene-ticks@60 launcher_keys launcher_surface"
# `exit_leaks` is the one entry whose subject is this suite's own output, and it
# sits beside `preview_surface` because both are about a run being readable rather
# than about the engine. It boots the real player in a second Godot and asserts
# that the process exits with no leaked ObjectDB instances and no resources still
# in use -- which, until `lingo_xtra.gd` took a `WeakRef`, no run of this project
# did. Every entry in this list ended with
#
#   WARNING: N ObjectDB instances were leaked at exit
#   ERROR: 4 resources still in use at exit
#
# and the 4 never moved because it counted the four scripts a single
# host<->Xtra-registry `RefCounted` cycle pinned. A standing ERROR on every line
# of a table whose whole job is to say which lines are clean is the argument
# `AGENTS.md` makes about a standing red, so it is gated rather than tolerated.
#
# Bare on `GATE_ROOT`, and it forwards `--root`/`--boot` to its child the way the
# three other child-spawning entries do (`save_movie`, `text_codepage`,
# `lingo_file_codepage`). Its subject is the exit rather than the corpus, so it is
# pinned for determinism rather than because the corpus decides the answer -- run
# by hand it is 7 of 7 on `piposh` (`PIPDATA/MAINMENU.dir`), on `rating`
# (`mainmenu.dir`) and on `piposh-dream` as well as on `GATE_ROOT`. Four of six
# roots, which is what was measured; that is not the same as "any title answers
# it", and the reason to be careful is that the child breaks out of its wait as
# soon as there is a score and never plays anything. A title whose first frames
# start a sound could red this entry on the `AudioStreamWAV` pair that
# `movie_churn` leaks -- a different leak, and one nobody has explained yet.
#
# `text_and_shapes` appears twice, and the second entry is the only one that
# exercises the field box-type rule at all. `GATE_ROOT` is `piposh2`, and that
# corpus has **no fixed or scrolling field** -- 1,755 of its 1,795 score-placed
# field records are `adjust` and the other 40 are `limit`. So the assertion that a
# fixed field is drawn at `MAX(score rect, initialRect, maxHeight)` passed there
# over an empty set, which is the "passing with 0 checks" failure this file's own
# EMPTY guard exists to catch, one level down: the harness had checks, just none of
# them about this rule. `PIPDATA/CAPROOM.dir` is where the shape lives -- 17 memo
# records that drew at the member's 87px instead of the score's 134px -- and it is
# the fixture the rule was measured against.
#
# Two entries naming one tool is the thing the comment below warns about, and it is
# deliberate here: a full run walks both, and only an explicit `bash gate.sh
# text_and_shapes` is ambiguous, where it takes the bare piposh2 entry because it
# comes first. Name the fixture directly to get the other one.
#
# `go_movie_arg` runs **once**, bare. The rule it asserts -- that `go`'s movie
# argument is found by position and type rather than by looking like a filename
# (`lingo-builtins.cpp:b_go`) -- is title-agnostic, and `GATE_ROOT` proves it.
#
# It had a second entry naming `res://test-games/itamar-magichat`, where the report
# came from: `logo/logo.dir` hands over with `go(1, GetMoviePath(CDpath() &
# DirChar() & "magichat"))`, whose second argument carries no extension at all, and
# before `bugs.md` 95 that argument was dropped and the logo replayed itself for
# ever. **That entry is gone, and so are the three other `test-games/` ones, for a
# reason that has nothing to do with what they asserted: the corpus is not in the
# repository.** `test-games/` is ignored at `.gitignore:73`, no file under it has
# ever been committed on any branch, and it is not a submodule -- so a clean
# checkout, a fresh worktree and both nightly runners have no such directory. What
# those entries did on every machine but the one they were written on was
# `no such container: magichat.dir`, which `go_movie_arg` and `video_plugin`
# reported as a failed assertion: 2 reds in a 92-entry suite, neither of them about
# the engine.
#
# This is `palette_members`' argument (below, and in `AGENTS.md`) reaching a second
# group of entries: **an entry that can only pass against a corpus outside the
# project gates nothing here.** The distinction worth keeping is that the other
# entries on that corpus -- `video_fallback` and `avi_decode` bare, and
# `sprite_lifetime`'s fourth case -- say out loud that they found nothing and assert
# nothing, which is why they stayed green throughout. Asserting against an absent
# fixture instead is what turned a data gap into a red.
#
# Point them at it by hand when somebody has it. That is what a `--root` flag is
# for, and `tools/video_census.gd --roots` still knows the path.
#
# `sprite_collision` checks the engine rule against whatever `GATE_ROOT` is;
# `cannon_hit` names its own root because it plays Piposh 1's cannon round, the
# one place in six titles where the whole chain from `the keyDownScript` to
# `allships` hangs off a single keypress. Two tools rather than one with a flag:
# an entry sharing a name with another resolves to whichever comes first, which
# is the trap the next comment is about.
#
# Neither covers the ship map, and that gap is what made the rule look like a
# trade for half a day -- see `bugs.md` 44.
#
# `collision_arms` is the *ink* half of the same operators and is deliberately a
# third file rather than more cases in `sprite_collision`: that one asserts they
# ignore `the visible of sprite` and this one asserts they do not ignore the ink,
# and a port that "fixed" one by deleting the other's rule has happened once
# (`docs/bugs-closed.md` 43). Two entries, because its last case is the only one
# that needs a title: bare on `GATE_ROOT` it finds `strtgame` f38 `sprite 1
# intersects 2` on the box-on-matte arm, and the `piposh-dream` entry lands on
# `hatul3.dir` f0 `sprite 15 intersects 28` -- the platformer's terrain test, and
# one of the 585 pairs `collision_ink` measured as changing arm. The first sixteen
# checks need no corpus at all: `matte-within` and the null-matte fallback have no
# witness in any of the six titles, so they are asserted against masks the harness
# builds, each paired with the box test that answers the other way.
#
# A third entry on `rating`, because that root carries **512 of the 585** pairs
# that change arm and had no coverage of them at all: its share is not minigames
# but the inventory-drop idiom, eight to twenty pairs per room movie. `BLAEGOZ.dir`
# has the most of any single container.
#
# `collision_ink` is that survey, run bare. 27 s. It is in `ALL` rather than left as
# a one-off because its guards -- the ink byte is live, and *every* Matte record's
# member resolves -- are the difference between "no pair changes arm" and "nothing
# was read", which is exactly the reading `bugs.md` 126 was filed to prevent. The
# second of those was `unresolved * 2 < total` for one commit and passed a run that
# under-read by a factor of seven; it is `== 0` now.
#
# `cursor_cross_cast` names `rating` for the same reason `new_game_reset` does,
# and the reason is the point of the tool rather than a detail of its invocation:
# every cursor pair in `piposh2` names a member of the movie's own cast, so a
# rule about which *library* a member number resolves in cannot be measured
# there at all. Run bare it searches sixteen containers, finds no cross-cast
# pair, and fails saying so -- which is the honest answer and not a passing one.
# `cursor_preview` stays on `GATE_ROOT` and covers everything else about the
# cursor; this covers the one thing that corpus cannot express.
#
# `idle_clock` runs bare, on `GATE_ROOT`: `idle` is an engine event and both
# roots must dispatch it, but only a title with an `on idle` handler can be
# asked what it did with it, so the harness asserts the dispatch everywhere and
# the clock only where there is one. `new_game_reset` names `rating` for the
# opposite reason -- the tables it checks are that title's, and there is nothing
# in `piposh2` for it to measure.
#
# **The three `--root piposh` entries beside it are one finding each, and each
# one is invisible on `GATE_ROOT`.**
#
# `idle_clock:--root piposh --boot PIPDATA/DAY1.dir` is Piposh 1's own clock. Its
# `on idle` calls `ClockScript1`, which lives in `MASTER.CST` and is one of five
# near-identical handlers that did not parse, so `GlobalSecond` stayed 0 and the
# on-screen `GlobalTime` field stayed at `08:00` for the whole game. The bare
# entry cannot see it: `piposh2` has an `on idle` of its own and it compiles.
# Measured with the parser fix reverted: `GlobalSecond 0 -> 0 over 12 tick(s)`,
# and with it, `0 -> 12` and the field reading `08:12`.
#
# `script_compile_check:--root piposh` is what caught those five. The bare entry
# is 3,307 of 3,307 and has been for a long time, which is exactly why it says
# nothing about the language -- `piposh2` is the corpus this parser was written
# against. `piposh` was 8,742 of 8,754 and is 8,754 now (`bugs.md` 39).
#
# `field_designator:--root piposh` covers the typed name lookup. The check finds
# its own fixture -- a library that gives one name to a field and to an earlier
# member of another type -- and `piposh2` has none, so there it prints "nothing
# asserted here" and only `piposh` exercises it (`SLOTMACH.dir`, `credit`: the
# Xtra at 83 that hid the field at 97).
#
# `liveness_sweep` carries `--limit 12` and that number is the whole reason it can
# be here at all: the full sweep of one corpus is 20-30 minutes, because an
# art-heavy room paints at about three score ticks a second headless and the
# sweep has to watch real frames. Twelve is deterministic -- the first twelve
# containers of `GATE_ROOT` in sorted order -- rather than a wall-clock budget,
# which would cover a different set on a loaded machine and turn a regression
# into a coin toss. The sweep prints what it skipped. Run it without the flag,
# and against the other roots, when something is suspected: `bugs.md` 58 was
# found in `piposh-dream`, which no gate entry has ever loaded.
#
# `film_loop_nesting` names `piposh-dream` for the reason `cursor_cross_cast` names
# `rating`: the subject does not exist in `GATE_ROOT`. A census of all six roots
# found exactly **10 sites where a film loop's child is itself a film loop, in 2
# titles** -- three in `piposh-dream/comein.dir`, one in its `hatul1.dir`, one in its
# `show.dir`, five in `rating/blatack1.dir`. `piposh`, `piposh-en`, `piposh-ru` and
# `piposh2` have none between them, so four of the six roots would run this over an
# empty set. The harness asserts its own population first for that reason, but the
# flag is what stops it being asserted and vacuous.
#
# `day_checklist` names `piposh-dream` because the subject is that title's day
# structure and no other corpus has one. It is the first entry that asserts a Lingo
# **global survives `go movie`** using the game's own state rather than a sentinel:
# `new_game_reset` is about Director fields and about resetting them, `go_movie_arg`
# is about which argument of `go` names the movie, and `tools/globals_survive.gd`
# writes its own `__sentinel` and is not in `ALL`. Three movie changes in one run --
# dinner to hub, hub to game, game back to hub -- and the middle one is a **mouse
# press on the hub's own slot**, so the game that loads is the one `1:24` composed
# out of `globalday` and never a name the harness supplied.
#
# It runs one of the seven checklist items, not seven, and says so in its own output.
# The reason is in its header: six of them would each need their own landing and two
# need their own field gates, and six unrelated reds would produce a failure that
# says nothing about the mechanism under test.
#
# **Its `--cold` control is deliberately not here and is expected to fail.** That
# flag runs the same assertions over the probe `bugs.md` 121 warns against, and it
# passes both crux readings -- item 2 says `done`, `1:13` hides the slot -- on a
# global that has been reduced from seven items to `",done"`. The five checks it
# fails are what make this entry mean anything, so a future session tempted to
# simplify them away should run `--cold` first and watch the file go green on a
# corrupt global.
#
# **`tools/puppet_members.gd` is not here and should not be, which is worth
# writing down because it has been reported as a coverage gap once already.** It
# makes **zero** `Harness.check` calls in either of its modes -- it is the
# diagnostic that was written to *find* the nested-loop bug, printing which scenes
# claim which channels and which of their film loops have film-loop children. Run
# against `GATE_ROOT` it reports `0 of 1 scene(s)` -- one and not the none this line
# said until `strtgame.dir`'s rollover menu became derivable, and neither number is
# an assertion -- and `gate.sh` calls that ERROR, correctly: a run that asserted
# nothing has not passed. Its subject is covered by the entry above, which asserts
# the same four things about the same corpus. Adding it would mean writing assertions
# it does not have, not moving a name into `ALL`.
#
# `cast_script_sprite` names `piposh-dream` for the same reason and the population
# is even narrower: **all 12 reads of `the currentSpriteNum` in the six titles are
# in one corpus**, as cast scripts on bitmap members in `hex1`/`hex2`/`hex3`, and 0
# are in behaviours. Bare on `GATE_ROOT` it would have no subject at all. It plays
# the Hexxagon board rather than reading the property back: a click on a piece must
# light tiles and a click on a lit tile must land the piece, because a getter
# agreeing with a setter passes while `lightUp1Hex(0)` still matches no `case` arm.
# 12s, and `--play` walks the movie's whole 200-frame spoken intro instead of
# landing in the score before the init -- same board, 74s, which is what makes the
# short path legitimate rather than convenient.
#
# `film_loop_cast` sits two entries away and **passed throughout the bug this
# catches**, which is why this is a new entry rather than a fourth check in that
# one. It asks whether a loop's child resolves to the right cast -- a question about
# the `ccl ` list, answered off the disc -- and a child resolved perfectly and then
# drawn as nothing answers it correctly. Nothing in the suite asked whether a
# loop-child could *draw*, so a type-2 child fell through `_texture_for`, tallied
# `"child has no art"`, and took its whole inner mini-score with it. The
# player-visible shape was Hatuli's projectile game with no projectiles in it.
#
# `sprite_lifetime` runs against the pinned corpus and asserts three things about
# `beginSprite`/`endSprite` that hold for any movie: the record of what has begun
# matches the score's spans on every sampled frame, a frame the playhead is
# *standing on* sends no `beginSprite` (which is where a Director title spends
# most of its time, and where a wrong trigger becomes a per-frame storm), and
# every begin is matched by an end or by a live sprite. It carries a fourth case
# that only runs against `test-games/itamar-magichat` -- the album screen of
# `bugs.md` 87, which is the title this was found in -- and says so and skips when
# pointed anywhere else.
#
# `sound_rate` sits beside `sound_wait` and asserts the other half of the same
# rule: `sound_wait` says a channel is busy iff a sound is playing on it, and this
# says the sound stops answering in about its own length. Two entries because the
# second is a *clock* and the first is a logic table, and the clock is the one no
# developer machine can fail -- it is 1.12x here, <=1.0x on the Windows runner and
# 2.09x on every macOS runner, which is `bugs.md` 90 and is what `puppet_persists`
# had been red for. Bare: the 2.0x default tolerance is the assertion, and it is
# deliberately generous, because the fault is a device that cannot keep up rather
# than one that is late by a buffer.
#
# **This is expected red on macOS runners until `bugs.md` 90 is fixed.** That is
# the point of it being here rather than an argument against: an ungated harness
# rots into a record of what the engine used to do, which is what left
# `palette_cycle` carrying four reds nobody saw, and a nightly that names the
# cause beside the symptom is one line instead of another investigation.
#
# **`bugs.md` 90 is now fixed, and `sound_replay_guard` is the entry that exists
# because fixing it broke something else.** The ceiling `soundBusy` gained made it
# disagree with `play_file`'s "already playing, leave it alone" guard, which still
# asked `player.playing` alone -- and where those two disagree a channel goes
# silent for the rest of the movie: free to the movie, already-playing to the
# guard, so the replay is skipped, the ceiling is never re-armed, and every later
# replay takes the same early return. Magic Hat then busy-waits three seconds and
# raises `alert("Sound file X is missing !")` for a file that is present, with
# `lingo_alert` pausing the movie behind it. Seen twice in ordinary play.
#
# It runs bare and **forces the window rather than waiting for it**: whether the
# race opens depends on the output device, so a harness built on waiting is green
# on a fast machine for the wrong reason -- the exact shape of the macOS problem
# above. It pushes `_channel_until` into the past on a channel that is genuinely
# still playing, which is the state the race arrives at, and then asks whether a
# movie can climb out using the only thing a movie can do. Controlled: with the
# guard reverted to `player.playing`, 2 of its 6 checks fail.
#
# `lingo_local_diagnosis` and `lingo_file_codepage` are the two harnesses from the
# Itamar work. The first asserts that a script's own local reads as an unset local
# and not as a binding the port owes -- `put x into line N of v` did not register
# `v` as assigned, so a handler building a value chunk by chunk had its first read
# filed under `unbound_name`, which is what sent a session hunting for a builtin
# that does not exist. It carries its own control: a genuinely unknown name must
# still report as a gap. The second is the codepage on the *Lingo file* paths --
# `director_codepage.gd` settled container text and `lingo_fileio`/`lingo_buddyapi`
# never got it, so Magic Hat's login panel drew its saved players as `?????`. Both
# ends move together, so a round trip stays a round trip; `--allow-writes` because
# it writes its fixture, to `user://` and never into a corpus.
#
# `video_fallback` and `avi_decode` run **once each, bare**, and this is the honest
# statement of what that costs. Bare on `GATE_ROOT` they say out loud that the
# corpus holds no video and assert nothing about it -- and `tools/video_census.gd`
# measured **four** video members across all eight corpora, every one of them
# `itamar-magichat`'s, which is not in the repository (see the `go_movie_arg`
# paragraph above). So there is no shipped corpus these two can be pointed at.
#
# **The video decode path therefore has no gate on it, and that is a hole rather
# than a decision.** What is unguarded is specific: `video_fallback` catches a
# `the duration of member` that answers confidently while `the movieTime` stays
# frozen -- which turns Magic Hat's clean one-tick skip into `go(the frame)` for
# ever, a hang rather than a wrong picture -- and `avi_decode` is the only thing
# that would notice MS-RLE producing wrong pixels, a backward seek not reproducing
# frame 0 byte for byte, or the decode falling below the file's own frame rate.
#
# The alternative was to leave four entries red on every machine but one, which
# `palette_cycle` already showed the end of: it spent its whole life outside this
# list and rotted into a record of what the engine used to do, carrying four
# failures nobody saw. A red nobody can act on rots the same way. Closing this
# properly wants a video fixture the project actually owns -- a few frames of
# MS-RLE committed under `games/` or a small generated container -- and until one
# exists these two are a bare honest "nothing here" and `bugs.md` should be read
# rather than this suite for what the decoder is known to do.
#
# `video_plugin` is the third of that group and appears **once, bare** -- and unlike
# the two above it loses almost nothing by it, on its own comment's evidence. It
# guards the one thing the other two structurally cannot: that the extension arm is
# *absent* when no extension is. Two of its checks are a source scan (no engine file
# `preload`s an addon path, which is a parse error and would take down every entry
# above this line before a movie opened) and the rest are the adapter's gate and the
# `getPlaybackEvent` VOID contract. **All of those are corpus-independent**, which
# the version of this paragraph written for the fixture entry already said: a bare
# run "would assert the same five things and add only piposh2 has no media".
#
# Measured, which is why it is bare rather than deleted with its siblings: pointed
# at the absent corpus it reported five `ok` lines and then one `FAIL  the preview
# has a host`, the host check being the only one that needed a movie to open. Bare,
# the five that matter run on every machine.
#
# It found its own first bug on its first run. `ResourceLoader
# .get_recognized_extensions_for_type("VideoStream")` answers `tres, res` on
# stock 4.7.1 -- the generic resource loaders handle every type -- so the
# adapter's "what did an extension add" list had to subtract a measured stock
# set rather than just `ogv`.
#
# **An extension has since been installed and run against it, and what it asserts
# in that state changed as a result** (`docs/DIGITAL_VIDEO.md` §9). The first
# version of the present-case branch asserted "at least one media file opens",
# which made the entry red on a machine with a working install: EIRTeam.FFmpeg
# 1.1.4 has no MPEG-PS demuxer and no MS-RLE decoder, so it opens 0 of that
# corpus's 23. **That is a third party's `configure` flags, not this port's
# behaviour**, and gating on it is the same mistake `palette_corpus` made when it
# failed on a shipped title's bad member numbering. The count is printed as a
# FINDING now and the assertions are the port's: `handles()` matches the loader's
# published list exactly, no stock extension is offered to a plugin, nothing ever
# opens with a duration of nought, every decline is named, and a file the plugin
# declines is still opened by the backend behind it -- which `logo.avi` exercises
# for real, since the build claims `.avi` and cannot decode MS-RLE.
#
# The resolution order (plugin, then sidecar, then AVI) is asserted as a **source
# scan** of `scenes/preview/video.gd` and runs in both branches, so it is
# corpus-independent and survives the bare run here. It has to be a scan: with a
# build that decodes none of the tree's containers there is no file the plugin arm
# and the sidecar arm both want, and a runtime check would pass while asserting
# nothing.

# `behaviour_me` names `PIP2DATA/DAY1.dir` and the flag is the entry, not a
# detail of it: `bugs.md` 93 is about whether a behaviour is one *object* for
# every message it receives, and `GATE_ROOT`'s boot movie carries no
# behaviour-channel script and no sprite behaviour on the frame it settles on --
# so run bare it asserts nothing and the EMPTY guard below is what you get.
# DAY1 has both (`BehaviorScript 55 - what to do everyframe` on the behaviour
# channel, five sprite behaviours beside it), and 7 of its 9 checks failed before
# the fix, which is the point: this is a shipped title's own scripts, not a
# fixture. The harness's third case is Magic Hat's and says so and skips here.
#
# `bitmap_geometry` and `audio_coverage` are bare and fast (seconds each) and are
# the regression guards for two entries the sweep turned up: `bugs.md` 58 and 63.
# Both read the disc rather than play it -- cast records in one case, twelve bytes
# off the front of every file in the other -- which is why they are affordable
# here and the sweep they came from is not.
#
# `palette_cycle` runs bare, beside it, and was **outside this list for its whole
# life** -- which is the only reason it could carry four reds nobody saw. Two were
# its own CLUT case, still asserting the reversed read that
# `director_palette.gd:from_clut` was corrected away from when `palette_members`
# was written; the other two were the renderer case, which drove `puppetPalette`
# and has been re-pointed at a fade, the one palette change a true-colour stage
# still passes to a bitmap. An ungated harness rots into a record of what the
# engine used to do, and both halves of that had happened here. Bare because its
# subject is the tables and the transforms, which need no corpus at all, plus
# `GATE_ROOT`'s one authored palette frame (`strtgame` f38).
#
# `palette_members` is **deliberately not in this list**, and the reason is about
# what this project is rather than about the harness, which is fine.
#
# It needs a corpus whose bitmaps name palette *members*, and `test-games/itamar-park`
# is the only one that does -- 655 of its 657. That title is not part of this
# project: it is not a submodule, it is not tracked, `test-games/` is ignored at
# `.gitignore:73`, and it never shipped with the six titles this engine is for. An
# entry that can only pass against a corpus outside the project is not a gate on
# this project, so it gated nothing and reported red for ever.
#
# **Two claims that used to live here were measured and are false**, so they are
# recorded rather than repeated. "Not one of the six shipped titles carries a
# single `CLUT` chunk or a single palette cast member": `piposh-ru` carries three
# of each, in `Texts.cst`, `pipdata/Texts.cst` and `pipdata/Textold.cst`, and the
# harness scores 7 of 9 against it. And the argument that the gap was only the
# missing corpus: `piposh-ru` cannot reach 9 of 9 either, for reasons that are
# facts about its art rather than defects. No bitmap there names a palette member,
# and the Mac and Windows D5 tables agree at 142 of 256 indices -- so a member
# that decodes the same under both provably uses only those, which is what
# "decoding through it changes the pixels" reads as a failure.
#
# Removing it would have left the CLUT read path ungated, which is how
# `palette_cycle` above came to carry four reds nobody saw, so `palette_corpus`
# was written to cover what the six shipped titles CAN answer. That is 14 checks
# over 6 roots, 651 containers and 118,991 bitmaps, against `palette_members`'s
# 9 over one title -- more coverage than was lost, not less, and all of it on
# data this project owns.
#
# What is still only in `palette_members`: that a bitmap's own named palette
# reaches the decoder and *changes the pixels*. No shipped title can express it.
# `piposh-ru` is the corpus to run it against by hand, at 7 of 9:
#
#   godot --headless --script tools/palette_members.gd -- --root piposh-ru
# A name given on the command line picks up the arguments its ALL entry carries.
# Without this, `bash gate.sh mouse_poll` runs it bare against the boot movie,
# which is not the subject it was written for -- it reported FAIL twice for that
# reason and both times the harness was fine. A harness silently losing its
# subject is the same class of fault as one passing with zero checks.
WANTED=""
for name in "$@"; do
  case "$name" in
    *:*) WANTED="$WANTED $name" ;;
    *)   match=""
         for entry in $ALL; do
           case "$entry" in "$name"|"$name":*) match="$entry"; break ;; esac
         done
         WANTED="$WANTED ${match:-$name}" ;;
  esac
done

RED=0
TOTAL=0
for t in ${WANTED:-$ALL}; do
  TOTAL=$((TOTAL + 1))
  extra=""
  case "$t" in *:*) extra=$(printf %s "${t#*:}" | tr "@" " "); t="${t%%:*}";; esac
  # `--root` first, so an ALL entry that names its own wins: the override takes
  # the last one on the line.
  # `$GATE_GODOT_ARGS` is unquoted so several flags split into several arguments,
  # and it sits before `--` because these are Godot's own rather than the
  # harness's. It exists for the question a runner can be asked and this machine
  # cannot: `puppet_persists` fails on every macOS runner and passes on Windows
  # and here, at an identical score-tick rate, which points at the environment
  # rather than at the clock. Trying `--audio-driver Dummy` against that needs no
  # edit here now.
  out=$(gate_run_capped ${GATE_TIMEOUT:-900} "$G" --headless $GATE_GODOT_ARGS --path . --script "tools/$t.gd" -- --root "$ROOT" --boot "$BOOT" $extra 2>&1)
  status=$?
  # A hang and a crash are not the same finding, and printing both as ERROR is
  # how `movie_churn` got called flaky. 124 is the ceiling, from `timeout` or
  # from the shim that stands in for it.
  if [ "$status" -eq 124 ]; then
    printf '%-26s TIMEOUT  (%ss ceiling; raise GATE_TIMEOUT or close the editor)\n' "$t" "${GATE_TIMEOUT:-900}"
    RED=$((RED + 1))
    continue
  fi
  r=$(printf '%s' "$out" | grep -E "^(PASS|FAIL)" | tail -1)
  # A harness that asserted nothing is not passing, it is dark. Four harnesses
  # today reported success over an empty set -- `cursors` printed "every pair
  # resolves to an image" over zero pairs, `room_names` "every room has a nof"
  # over zero rooms, and `editable_text` sat in this list passing with 0 checks
  # because the boot movie has no editable field, so the entry asserted nothing
  # for as long as it existed. That is the exact failure `preview_surface.gd`
  # exists to catch, and it kept happening anyway.
  checks=$(printf '%s' "$r" | grep -oE '\([0-9]+ checks' | grep -oE '[0-9]+')
  if [ -n "$checks" ] && [ "$checks" -eq 0 ]; then
    echo "$(printf %-26s "$t") EMPTY  (passed with 0 checks -- give it a subject)"
    RED=$((RED + 1))
    continue
  fi
  if [ -z "$r" ]; then
    printf '%-26s ERROR\n' "$t"
    printf '%s\n' "$out" | grep -iE "parse error|script error|Invalid|Cannot|nonexistent" | head -3
    RED=$((RED + 1))
  else
    printf '%-26s %s\n' "$t" "${r:0:4}"
    if [ "${r:0:4}" != PASS ]; then
      RED=$((RED + 1))
      # The failing checks, indented, and this exists for CI rather than for a
      # developer. A run on this machine can be repeated by hand; a run at 03:00
      # on a runner that no longer exists cannot, and until this line the whole
      # of what a nightly failure reported was the four characters above it.
      # `lingo_surface_audit` went red on both platforms and the log could not
      # say which of its eleven checks it was.
      printf '%s\n' "$out" | grep -E "^FAIL" | head -6 | sed 's/^/    /'
      # And then the whole of what the harness said. The lines above are the
      # verdict; this is the evidence, and it was being thrown away.
      #
      # Six FAIL lines are enough to name the check and never enough to explain
      # it. `puppet_persists` fails on every macOS runner and passes on Windows
      # and on a developer Mac, and every measurement that could tell those
      # apart -- the per-room trace, `builtins reached`, the audio index, the
      # detail on the checks that *passed* -- is in here and was being dropped.
      # Four hypotheses were formed and three were wrong from those six lines,
      # at a round trip of eight minutes each, which is the cost this line is
      # weighed against.
      #
      # Under a red only. A passing entry's output says nothing a reader needs
      # and there are 78 of them.
      #
      # Capped, and the cap says what it dropped rather than trimming quietly:
      # a sweep harness prints thousands of lines into a log shared with 77
      # other entries. 400 is over twice the longest failing entry measured, so
      # the note below is the unusual case rather than the normal one.
      spilled=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
      printf '%s\n' "$out" | head -400 | sed 's/^/    | /'
      if [ "$spilled" -gt 400 ]; then
        echo "    | ... and $((spilled - 400)) more line(s); run this entry alone for them."
      fi
    fi
  fi
done

# Counted rather than short-circuited, so a red does not stop the run: the whole
# table is the finding, and a suite that stopped at the first FAIL would hide
# every entry after it behind one.
#
# Every non-PASS branch above increments, so this covers TIMEOUT, EMPTY and ERROR
# and not only FAIL. A run that hung, asserted nothing, or died before it could
# report has not passed, and an exit code counting only FAIL would call all three
# clean -- `EMPTY` especially, which exists precisely because four harnesses have
# silently passed over an empty set.
#
# 1 and not 2: `exit 2` above is "another run holds the lock", a refusal to
# measure rather than a measurement. A caller needs to tell "the gate says no"
# from "the gate did not run".
if [ "$RED" -gt 0 ]; then
  echo "gate: $RED of $TOTAL did not pass."
  exit 1
fi
echo "gate: all $TOTAL passed."
