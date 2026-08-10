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

echo ""
if [ "$fail" -eq 0 ]; then echo "PASS  stamp_version"; else echo "FAIL  stamp_version"; fi
exit "$fail"
