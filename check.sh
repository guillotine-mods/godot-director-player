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
# Before the grep below, which is why this is here and not only in `gate.sh`:
# without the pack the preview surface opens with twelve `Failed to load` lines
# from the 3D title's autoloads, and this script reports exactly that pattern as
# the thing that went wrong. The fast gate would fail loudly on a clean clone,
# naming files nobody touched.
gate_require_pack
out=$(gate_run_capped 120 "$G" --headless --path . --script tools/preview_surface.gd -- "$@" 2>&1)
if [ $? -eq 124 ]; then
  echo "check: preview_surface hit the 120s ceiling. An open editor contends over .godot/."
  exit 1
fi
errors=$(printf '%s\n' "$out" | grep -iE "parse error|Failed to load|Nonexistent|Invalid (call|get|set)" | sort -u | head -5)
result=$(printf '%s\n' "$out" | grep -E "^(PASS|FAIL|ok)" | tail -3)
[ -n "$errors" ] && printf '%s\n' "$errors"
printf '%s\n' "$result"

# An exit code, for the reason gate.sh grew one: a gate that reports only on
# stdout can be run by a human reading it and by nothing else.
#
# Three ways to fail, and the third is the one worth naming. A run that printed
# no PASS at all did not quietly succeed -- it died before it could report, and
# to anything grepping for FAIL that is indistinguishable from a clean run. The
# diagnostic grep counts too: it is why the pack is built above, and a hit means
# the surface resolved against a project that is already broken.
if [ -n "$errors" ]; then exit 1; fi
printf '%s\n' "$result" | grep -q '^FAIL' && exit 1
printf '%s\n' "$result" | grep -q '^PASS' || exit 1
exit 0
