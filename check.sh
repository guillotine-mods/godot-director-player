#!/bin/bash
# Fast structural gate: does the project still parse, and does the reflective
# surface still resolve? Seconds, not minutes. The behavioural suite is batched.
#
# No corpus pinning on purpose: this asks whether the project loads and whether
# the preview's surface still resolves, and neither question is about a title.
# It does boot the configured game, though, so a director_game.cfg pointing at a
# root that is not there fails here as six null fields rather than as "no such
# game". Arguments are forwarded, so name one when the config is mid-edit:
#
#   bash check.sh --root piposh2
cd "$(dirname "$0")" || exit 1
. ./gate_env.sh
G=$(gate_find_godot) || exit 1
gate_announce_godot "$G"
out=$(gate_run_capped 120 "$G" --headless --path . --script tools/preview_surface.gd -- "$@" 2>&1)
if [ $? -eq 124 ]; then
  echo "check: preview_surface hit the 120s ceiling. An open editor contends over .godot/."
  exit 1
fi
printf '%s\n' "$out" | grep -iE "parse error|Failed to load|Nonexistent|Invalid (call|get|set)" | sort -u | head -5
printf '%s\n' "$out" | grep -E "^(PASS|FAIL|ok|FAIL )" | tail -3
