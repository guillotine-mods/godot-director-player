#!/bin/bash
# Run the refactor gates. Every step must reproduce the recorded pass/fail SET,
# which is **every entry in ALL passing and none failing**, measured on 4.7.1
# against GATE_ROOT's default by a whole-suite run at the commit this line was
# written. There is no expected failure any more, so any red is a regression and
# needs no triage against a list of excuses.
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
ALL="game_config title_mapping title_list preview_surface boot_state:--file@PIP2DATA/EXODUS.DIR frame_events window_preview text_and_shapes text_and_shapes:--root@piposh@--file@PIPDATA/CAPROOM.dir cursor_preview cursor_cross_cast:--root@rating@--boot@mainmenu.dir container_equality_check lingo_logic_check lingo_designator_check field_designator lingo_builtins_check keyboard_check decode_stall hotspots trails sprite_drag debug_bindings snapshot_check container_picker_check drawn_size_stability member_ref_round_trip movie_churn film_loop_cast film_loop_scale skip_state mouse_events touch_input hilite playhead_escape puppet_persists puppet_freeze:--file@PIP2DATA/CHESS.dir@--channel@8@--wheels@138,175@--span@7 editable_text:--file@PIP2DATA/SAVELOAD.dir save_movie:--allow-writes text_codepage save_state sound_wait key_polling movie_tempo script_compile_check parse_residue lingo_surface_audit lingo_objects lingo_scope_check timeout_and_actors fileio_xtra buddyapi_xtra:--allow-writes media_surface lingo_movie_surface property_surface lingo_system_builtins update_stage click_eligibility click_chain primary_scripts play_suspends sound_paths fast_forward key_chain mouse_poll:--file@PIP2DATA/CHESS.dir@--label@ches1 sprite_collision label_index pause_holds:--file@PIP2DATA/SAVELOAD.dir@--label@savegame2@--hotspot cannon_hit:--root@piposh idle_clock new_game_reset:--root@rating@--boot@NAVIGATE.dir bitmap_geometry palette_members:--root@res://test-games/itamar-park audio_coverage liveness_sweep:--limit@12 launcher_keys launcher_surface"
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
# `bitmap_geometry` and `audio_coverage` are bare and fast (seconds each) and are
# the regression guards for two entries the sweep turned up: `bugs.md` 58 and 63.
# Both read the disc rather than play it -- cast records in one case, twelve bytes
# off the front of every file in the other -- which is why they are affordable
# here and the sweep they came from is not.
#
# `palette_members` names `test-games/itamar-park` for the same reason
# `cursor_cross_cast` names `rating`: `GATE_ROOT` cannot express its subject at
# all. Not one of the six shipped titles carries a single `CLUT` chunk or a
# single palette cast member, so every custom-palette path in the engine was
# unexercised by every gate entry -- and had been wrong in two places for as long
# as it had existed, in a way no run over this corpus could have shown. Pointed
# at a corpus with no palettes the harness fails and says so, rather than passing
# over nothing.
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

for t in ${WANTED:-$ALL}; do
  extra=""
  case "$t" in *:*) extra=$(printf %s "${t#*:}" | tr "@" " "); t="${t%%:*}";; esac
  # `--root` first, so an ALL entry that names its own wins: the override takes
  # the last one on the line.
  out=$(gate_run_capped ${GATE_TIMEOUT:-900} "$G" --headless --path . --script "tools/$t.gd" -- --root "$ROOT" --boot "$BOOT" $extra 2>&1)
  status=$?
  # A hang and a crash are not the same finding, and printing both as ERROR is
  # how `movie_churn` got called flaky. 124 is the ceiling, from `timeout` or
  # from the shim that stands in for it.
  if [ "$status" -eq 124 ]; then
    printf '%-26s TIMEOUT  (%ss ceiling; raise GATE_TIMEOUT or close the editor)\n' "$t" "${GATE_TIMEOUT:-900}"
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
    continue
  fi
  if [ -z "$r" ]; then
    printf '%-26s ERROR\n' "$t"
    printf '%s\n' "$out" | grep -iE "parse error|script error|Invalid|Cannot|nonexistent" | head -3
  else
    printf '%-26s %s\n' "$t" "${r:0:4}"
  fi
done
