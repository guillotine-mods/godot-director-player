#!/bin/bash
# Run the refactor gates. Every step must reproduce the recorded pass/fail SET,
# which is 11 pass / 2 fail -- boot_state and cursor_preview were already red at
# the commit the split started from.
cd /c/Data/Work/Piposh/piposh2-godot || exit 1
G="/c/Program Files/Godot_v4.7.1/Godot_v4.7.1-stable_mono_win64_console.exe"

# Pin the corpus. A gate is only meaningful against the game its baseline was
# recorded on, and the config is a working file that gets pointed at whichever
# title is being looked at -- a run against another game reads as five
# regressions that are really five different movies. Restored on exit.
ROOT="${GATE_ROOT:-piposh2}"

# Per-harness ceiling. Raised from 300s because several harnesses now sweep the
# whole corpus, and with a handful of agents running Godot at once a sweep that
# takes 40s alone can exceed five minutes. A timeout reports as ERROR, which
# reads as a regression and is not one -- `movie_churn` was called flaky on
# exactly this. Override with GATE_TIMEOUT.

# Serialise concurrent runs. Pinning the corpus means writing a file the whole
# repo shares, so two gates running at once -- which happens the moment more
# than one agent is working -- have each other's corpus swapped out from under
# them mid-run. That does not fail loudly: it reports the other title's movies
# as this title's regressions. One run measured six that way and none was real.
LOCK=".gate.lock"
HELD=""
for _ in $(seq 1 900); do
  if mkdir "$LOCK" 2>/dev/null; then HELD=yes; break; fi
  sleep 1
done
# Refuse rather than proceed. The first version fell through the wait and ran
# anyway, and its EXIT trap then removed *whoever's* lock was there -- so a long
# run lost its lock to a later one, two gates pinned the corpus against each
# other, and the results of both were fiction. Releasing only a lock we took is
# the other half: without it the trap is a lock-breaker with extra steps.
if [ -z "$HELD" ]; then
  echo "gate: another run has held $LOCK for 15 minutes; not starting a second one." >&2
  echo "gate: if nothing is running, remove $LOCK by hand." >&2
  exit 2
fi
trap '[ -n "$HELD" ] && rmdir "$LOCK" 2>/dev/null' EXIT

BEFORE=$(grep '^root' director_game.cfg)
trap 'rmdir "$LOCK" 2>/dev/null; python -c "
import sys,re
s=open(\"director_game.cfg\").read()
open(\"director_game.cfg\",\"w\").write(re.sub(r\"^root.*\", sys.argv[1], s, count=1, flags=re.M))" "$BEFORE"' EXIT
python -c "
import sys,re
s=open('director_game.cfg').read()
open('director_game.cfg','w').write(re.sub(r'^root.*', 'root = \"res://games/%s\"' % sys.argv[1], s, count=1, flags=re.M))" "$ROOT"
echo "corpus: $ROOT"
ALL="preview_surface boot_state frame_events window_preview text_and_shapes cursor_preview container_equality_check lingo_logic_check lingo_designator_check lingo_builtins_check keyboard_check decode_stall hotspots trails sprite_drag debug_bindings snapshot_check container_picker_check drawn_size_stability movie_churn film_loop_cast skip_state mouse_events touch_input hilite playhead_escape editable_text:--file@PIP2DATA/SAVELOAD.dir save_movie sound_wait key_polling movie_tempo script_compile_check parse_residue play_suspends sound_paths fast_forward key_chain mouse_poll:--file@PIP2DATA/CHESS.dir@--label@ches1"
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
  out=$(timeout ${GATE_TIMEOUT:-900} "$G" --headless --path . --script "tools/$t.gd" -- $extra 2>&1)
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
