#!/usr/bin/env bash
# Checks what stamp_version.sh actually wrote, against a fixture.
#
#   bash tools/ci/stamp_version_test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

# A probe that dies under `set -e` before `check` runs takes the whole suite
# with it and prints nothing -- the shell twin of the aborted-case failure
# `tools/lib/harness.gd` exists to catch, where a case that never completes
# must not read as a pass. The trap makes an early death loud.
verdict=""
finish() {
	st=$?
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  stamp_version: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

cat >"$tmp/presets.cfg" <<'EOF'
[preset.0.options]

version/code=1
version/name="0.1.0"
package/unique_name="com.guillotinemods.godotdirectorplayer"
EOF

tools/ci/stamp_version.sh v0.2.0 41 "$tmp/presets.cfg" >/dev/null
grep -q '^version/code=41$' "$tmp/presets.cfg"
check "version/code takes the run number" $?
grep -q '^version/name="0.2.0"$' "$tmp/presets.cfg"
check "version/name drops the leading v" $?
grep -q '^package/unique_name=' "$tmp/presets.cfg"
check "neighbouring keys survive" $?

# A non-numeric code would substitute happily and produce an APK Android will
# not take as an update, so it has to be refused rather than written.
if tools/ci/stamp_version.sh v0.3.0 not-a-number "$tmp/presets.cfg" >/dev/null 2>&1; then
	check "a non-numeric version code is refused" 1
else
	check "a non-numeric version code is refused" 0
fi

# A missing file is the same class of fault: silently stamping nothing would
# ship version/code=1 forever.
if tools/ci/stamp_version.sh v0.3.0 42 "$tmp/nope.cfg" >/dev/null 2>&1; then
	check "a missing presets file is refused" 1
else
	check "a missing presets file is refused" 0
fi

cat >"$tmp/pristine.cfg" <<'EOF'
[preset.0.options]

version/code=1
version/name="0.1.0"
package/unique_name="com.guillotinemods.godotdirectorplayer"
EOF

# The tag comes from $GITHUB_REF_NAME -- whoever pushes the tag picks it.
#
# Not all four cases carry equal weight, and saying so is the point. Against
# the pre-fix script: the space and `;touch` cases discriminate fully (it
# accepted both silently). The `&` case discriminates only on its "untouched"
# half -- the old code exited nonzero too, via its own round-trip check
# catching the corruption it had just written. The `|` case discriminates on
# neither half: sed aborted at parse time on the delimiter collision and left
# the file alone, so it passes identically with or without the guard. It is
# kept because refusing `|` is still the behaviour we want locked in, but it
# is documentation, not verification.
for bad in 'v1.0&2.0' 'v1.0|2.0' 'v1.0 2.0' 'v1.0;touch /tmp/stamp-pwned'; do
	cp "$tmp/pristine.cfg" "$tmp/guard.cfg"
	if tools/ci/stamp_version.sh "$bad" 42 "$tmp/guard.cfg" >/dev/null 2>&1; then
		check "a tag with metacharacters is refused ($bad)" 1
	else
		check "a tag with metacharacters is refused ($bad)" 0
	fi
	if cmp -s "$tmp/pristine.cfg" "$tmp/guard.cfg"; then
		check "the file is untouched after refusing ($bad)" 0
	else
		check "the file is untouched after refusing ($bad)" 1
	fi
done

# Missing arguments are bad input (2), not a bash expansion failure (1).
rc=0
tools/ci/stamp_version.sh >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "no arguments exits 2" 0
else
	check "no arguments exits 2" 1
fi

rc=0
tools/ci/stamp_version.sh v1.0.0 >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "one argument exits 2" 0
else
	check "one argument exits 2" 1
fi

echo ""
verdict=printed
if [ "$fail" -eq 0 ]; then echo "PASS  stamp_version"; else echo "FAIL  stamp_version"; fi
exit "$fail"
