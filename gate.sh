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
ALL="game_config title_mapping title_list export_presets_check preview_surface boot_state:--file@PIP2DATA/EXODUS.DIR frame_events window_preview text_and_shapes text_and_shapes:--root@piposh@--file@PIPDATA/CAPROOM.dir cursor_preview cursor_cross_cast:--root@rating@--boot@mainmenu.dir container_equality_check lingo_logic_check lingo_designator_check field_designator lingo_builtins_check keyboard_check decode_stall hotspots trails sprite_drag debug_bindings snapshot_check container_picker_check drawn_size_stability member_ref_round_trip reg_point movie_churn film_loop_cast film_loop_scale skip_state mouse_events touch_input hilite playhead_escape puppet_persists puppet_freeze:--file@PIP2DATA/CHESS.dir@--channel@8@--wheels@138,175@--span@7 editable_text:--file@PIP2DATA/SAVELOAD.dir save_movie:--allow-writes text_codepage save_state sound_wait key_polling movie_tempo script_compile_check parse_residue lingo_surface_audit lingo_objects lingo_scope_check timeout_and_actors fileio_xtra buddyapi_xtra:--allow-writes media_surface lingo_movie_surface property_surface lingo_system_builtins update_stage click_eligibility click_chain primary_scripts sprite_lifetime play_suspends sound_paths fast_forward key_chain mouse_poll:--file@PIP2DATA/CHESS.dir@--label@ches1 sprite_collision label_index pause_holds:--file@PIP2DATA/SAVELOAD.dir@--label@savegame2@--hotspot cannon_hit:--root@piposh idle_clock new_game_reset:--root@rating@--boot@NAVIGATE.dir bitmap_geometry palette_cycle palette_corpus audio_coverage liveness_sweep:--limit@12 launcher_keys launcher_surface"
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
