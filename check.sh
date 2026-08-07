#!/bin/bash
# Fast structural gate: does the project still parse, and does the reflective
# surface still resolve? Seconds, not minutes. The behavioural suite is batched.
cd /c/Data/Work/Piposh/piposh2-godot || exit 1
G="/c/Program Files/Godot_v4.7.1/Godot_v4.7.1-stable_mono_win64_console.exe"
out=$(timeout 120 "$G" --headless --path . --script tools/preview_surface.gd 2>&1)
printf '%s\n' "$out" | grep -iE "parse error|Failed to load|Nonexistent|Invalid (call|get|set)" | sort -u | head -5
printf '%s\n' "$out" | grep -E "^(PASS|FAIL|ok|FAIL )" | tail -3
