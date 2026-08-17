#!/usr/bin/env bash
# Checks what stamp_debug_ui.sh actually wrote, against a fixture.
#
#   bash tools/ci/stamp_debug_ui_test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp=$(mktemp -d)

# One EXIT trap only, and the abort guard lives inside it -- see
# `stamp_version_test.sh` for the run that leaked a directory per invocation by
# registering the two separately. A probe that dies under `set -e` before
# `check` runs must not read as a pass.
verdict=""
finish() {
	st=$?
	rm -rf "$tmp"
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  stamp_debug_ui: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

# Shaped like the real `[debug]` block: the switch, then the bindings it gates.
# The bindings are here so the sed has neighbours to damage.
cat >"$tmp/pristine.cfg" <<'EOF'
[game]

root = "res://games/piposh2"

[debug]
enabled = "auto"
boxes = "F1"
hit_test = "F2"
fast_forward = "PageDown"
globals = "Shift+F1"

[qol]

hotspot_hints = false
minigame_skip_enabled = true
EOF

cp "$tmp/pristine.cfg" "$tmp/game.cfg"
tools/ci/stamp_debug_ui.sh true "$tmp/game.cfg" >/dev/null

if grep -Fqx 'enabled = "true"' "$tmp/game.cfg"; then
	check "a pre-1.0 build stamps true" 0
else
	check "a pre-1.0 build stamps true" 1
fi

# The whole point of the stamp is that the F-keys come back, so a sed that
# reached one of them would defeat it while the assertion above still passed.
if grep -Fqx 'boxes = "F1"' "$tmp/game.cfg" &&
	grep -Fqx 'globals = "Shift+F1"' "$tmp/game.cfg" &&
	grep -Fqx 'fast_forward = "PageDown"' "$tmp/game.cfg"; then
	check "the bindings it gates are left alone" 0
else
	check "the bindings it gates are left alone" 1
fi

if grep -Fqx 'hotspot_hints = false' "$tmp/game.cfg" &&
	grep -Fqx 'root = "res://games/piposh2"' "$tmp/game.cfg"; then
	check "neighbouring sections survive" 0
else
	check "neighbouring sections survive" 1
fi

# This one is verification and not documentation, which is worth saying because
# the sibling case in `stamp_version_test.sh` is the other way round. The
# two-key case below cannot test the `^` anchor: the count guard refuses that
# file before the sed ever runs. A key merely ENDING in `enabled` gets past the
# guard -- `grep -c '^enabled = '` does not count it -- and an unanchored sed
# rewrites the tail of the line, leaving `minigame_skip_enabled = "true"`.
# Confirmed by dropping the anchor and watching only this case go red.
if grep -Fqx 'minigame_skip_enabled = true' "$tmp/game.cfg"; then
	check "a key that merely ends in 'enabled' is not stamped" 0
else
	check "a key that merely ends in 'enabled' is not stamped" 1
fi

# v1.0 and later. Writing the value the file already carries has to be a
# success and not a no-op that skips its own verification: this is the release
# where the layer being off matters most, and a renamed key must fail here
# rather than ship.
tools/ci/stamp_debug_ui.sh auto "$tmp/game.cfg" >/dev/null
if cmp -s "$tmp/pristine.cfg" "$tmp/game.cfg"; then
	check "stamping auto back returns the file to what it was" 0
else
	check "stamping auto back returns the file to what it was" 1
fi

# `resolve_switch` warns and falls back to `auto` on a value it does not know,
# which for an alpha means the layer is silently absent again -- the exact
# failure this whole script exists to end. Refused rather than written.
cp "$tmp/pristine.cfg" "$tmp/guard.cfg"
rc=0
tools/ci/stamp_debug_ui.sh yes "$tmp/guard.cfg" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "a value outside true/false/auto exits 2" 0
else
	check "a value outside true/false/auto exits 2" 1
fi
if cmp -s "$tmp/pristine.cfg" "$tmp/guard.cfg"; then
	check "the file is untouched after refusing a value" 0
else
	check "the file is untouched after refusing a value" 1
fi

# A second `enabled` key is a reasonable thing for somebody to add to `[qol]`
# later. An anchored sed would stamp both and change a setting nobody asked
# about, in every release build, silently.
cat >"$tmp/two.cfg" <<'EOF'
[debug]
enabled = "auto"

[qol]
enabled = "false"
EOF
cp "$tmp/two.cfg" "$tmp/two.before"
rc=0
tools/ci/stamp_debug_ui.sh true "$tmp/two.cfg" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
	check "a second enabled key is refused" 0
else
	check "a second enabled key is refused" 1
fi
if cmp -s "$tmp/two.before" "$tmp/two.cfg"; then
	check "the file is untouched after refusing two keys" 0
else
	check "the file is untouched after refusing two keys" 1
fi

# A config that has lost the switch entirely is the same class of fault: the
# build would ship whatever the file happened to say, which is nothing.
cat >"$tmp/none.cfg" <<'EOF'
[debug]
boxes = "F1"
EOF
rc=0
tools/ci/stamp_debug_ui.sh true "$tmp/none.cfg" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
	check "a missing enabled key is refused" 0
else
	check "a missing enabled key is refused" 1
fi

# Same class again, and the reason the path is a parameter at all: a typo in the
# workflow must fail rather than stamp nothing and exit clean.
rc=0
tools/ci/stamp_debug_ui.sh true "$tmp/nope.cfg" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "a missing config file is refused" 0
else
	check "a missing config file is refused" 1
fi

# Missing arguments are bad input (2), not a bash expansion failure (1).
rc=0
tools/ci/stamp_debug_ui.sh >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "no arguments exits 2" 0
else
	check "no arguments exits 2" 1
fi

# The default path is the real tracked config, and every call above names its
# own fixture instead -- for the reason `stamp_version_test.sh` records, where
# a call that omitted the path stamped the working tree it was testing.
if grep -Fqx 'enabled = "auto"' director_game.cfg; then
	check "the tracked config still says auto" 0
else
	check "the tracked config still says auto" 1
fi

# The one case above that is about the REAL file rather than a fixture, and it
# is here to move a failure earlier in time. The two-key refusal is the right
# behaviour, but on its own it lands on a tag push -- in four matrix jobs at
# once, each after a 3.8 GB submodule checkout, blocking a release. Asserting
# the same count here means the commit that adds a second `enabled` key turns
# `push.yml` red instead, six weeks before anybody tags.
if [ "$(grep -c '^enabled = ' director_game.cfg)" = "1" ]; then
	check "the tracked config still has exactly one enabled key" 0
else
	check "the tracked config still has exactly one enabled key" 1
fi

echo ""
verdict=printed
if [ "$fail" -eq 0 ]; then echo "PASS  stamp_debug_ui"; else echo "FAIL  stamp_debug_ui"; fi
exit "$fail"
