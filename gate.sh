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
BEFORE=$(grep '^root' director_game.cfg)
trap 'python -c "
import sys,re
s=open(\"director_game.cfg\").read()
open(\"director_game.cfg\",\"w\").write(re.sub(r\"^root.*\", sys.argv[1], s, count=1, flags=re.M))" "$BEFORE"' EXIT
python -c "
import sys,re
s=open('director_game.cfg').read()
open('director_game.cfg','w').write(re.sub(r'^root.*', 'root = \"res://games/%s\"' % sys.argv[1], s, count=1, flags=re.M))" "$ROOT"
echo "corpus: $ROOT"
ALL="preview_surface boot_state frame_events window_preview text_and_shapes cursor_preview container_equality_check lingo_logic_check lingo_designator_check lingo_builtins_check keyboard_check decode_stall hotspots trails"
for t in ${@:-$ALL}; do
  out=$(timeout 300 "$G" --headless --path . --script "tools/$t.gd" 2>&1)
  r=$(printf '%s' "$out" | grep -E "^(PASS|FAIL)" | tail -1)
  if [ -z "$r" ]; then
    printf '%-26s ERROR\n' "$t"
    printf '%s\n' "$out" | grep -iE "parse error|script error|Invalid|Cannot|nonexistent" | head -3
  else
    printf '%-26s %s\n' "$t" "${r:0:4}"
  fi
done
