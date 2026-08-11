#!/usr/bin/env bash
# Checks what stamp_version.sh actually wrote, against a fixture.
#
#   bash tools/ci/stamp_version_test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp=$(mktemp -d)

# One EXIT trap only. Bash keeps the last registration per signal, so cleanup
# and the abort guard have to live in the same handler -- an earlier revision
# registered them separately and the second silently disabled the first,
# leaking a directory per run.
#
# A probe that dies under `set -e` before `check` runs takes the whole suite
# with it and prints nothing -- the shell twin of the aborted-case failure
# `tools/lib/harness.gd` exists to catch, where a case that never completes
# must not read as a pass. `st=$?` is captured before the `rm` so cleanup
# cannot overwrite the suite's own exit status.
verdict=""
finish() {
	st=$?
	rm -rf "$tmp"
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  stamp_version: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

cat >"$tmp/presets.cfg" <<'EOF'
[preset.0.options]

version/code=1
version/name="0.1.0"
package/unique_name="com.guillotinemods.godotdirectorplayer"

[preset.1.options]

application/file_version=""
application/product_version=""

[preset.2.options]

application/short_version=""
application/version=""
application/bundle_identifier="com.guillotinemods.godotdirectorplayer"
EOF

# EVERY call below passes a project fixture explicitly. The fourth argument
# defaults to the real `project.godot`, so a three-argument call from inside the
# repo would stamp the working tree -- a test suite quietly editing the project it
# is testing. That is not hypothetical: every call in this file had three
# arguments before the project-stamping existed.
cat >"$tmp/project.godot" <<'EOF'
[application]

config/name="Godot Director Player"
config/version="0.0.0-dev"
run/main_scene="res://scenes/launcher/launcher.tscn"
EOF

tools/ci/stamp_version.sh v0.2.0 41 "$tmp/presets.cfg" "$tmp/project.godot" >/dev/null

if grep -Fqx 'version/code=41' "$tmp/presets.cfg"; then
	check "version/code takes the run number" 0
else
	check "version/code takes the run number" 1
fi

if grep -Fqx 'version/name="0.2.0"' "$tmp/presets.cfg"; then
	check "version/name drops the leading v" 0
else
	check "version/name drops the leading v" 1
fi

# macOS enforces no version monotonicity, so these two exist to keep the
# artifact self-identifying rather than to keep an update installable.
# `short_version` is the marketing string Finder shows; `version` is the build
# counter, and it takes the run number for the same reason Android's
# `version/code` does.
if grep -Fqx 'application/short_version="0.2.0"' "$tmp/presets.cfg"; then
	check "application/short_version takes the marketing name" 0
else
	check "application/short_version takes the marketing name" 1
fi

if grep -Fqx 'application/version="41"' "$tmp/presets.cfg"; then
	check "application/version takes the run number" 0
else
	check "application/version takes the run number" 1
fi

# Documentation, not verification, and worth saying so plainly: `^` anchors the
# match to the start of the line, so `^application/version=` cannot match
# `application/file_version=` however the sed is spelled. This case therefore
# passes with or without the anchoring it appears to be testing.
#
# It is kept for two reasons. It locks in the intent that the Windows keys are
# deliberately NOT stamped rather than merely forgotten, and it fails loudly if
# someone later reaches for an unanchored or `.*`-prefixed pattern to catch more
# keys at once. That would write a version into the wrong preset while every
# assertion above still passed.
if grep -Fqx 'application/file_version=""' "$tmp/presets.cfg" &&
	grep -Fqx 'application/product_version=""' "$tmp/presets.cfg"; then
	check "the Windows version keys are left alone" 0
else
	check "the Windows version keys are left alone" 1
fi

# Still a pattern rather than a literal: this one asserts the key survived,
# not what its value is.
if grep -q '^package/unique_name=' "$tmp/presets.cfg"; then
	check "neighbouring keys survive" 0
else
	check "neighbouring keys survive" 1
fi

# The only one of the five keys the running game can actually read, and so the
# only one the launcher can show. `+41` is what distinguishes two builds of one
# tag; without it a screenshot of the header cannot identify which run produced
# the binary.
if grep -Fqx 'config/version="0.2.0+41"' "$tmp/project.godot"; then
	check "config/version carries name+code" 0
else
	check "config/version carries name+code" 1
fi

if grep -q '^config/name=' "$tmp/project.godot"; then
	check "neighbouring project settings survive" 0
else
	check "neighbouring project settings survive" 1
fi

# Same class of fault as a missing presets file: a build whose launcher reports
# 0.0.0-dev while its APK reports 0.2.0 is worse than one that failed to build.
if tools/ci/stamp_version.sh v0.3.0 42 "$tmp/presets.cfg" "$tmp/nope.godot" >/dev/null 2>&1; then
	check "a missing project file is refused" 1
else
	check "a missing project file is refused" 0
fi

# A non-numeric code would substitute happily and produce an APK Android will
# not take as an update, so it has to be refused rather than written.
if tools/ci/stamp_version.sh v0.3.0 not-a-number "$tmp/presets.cfg" "$tmp/project.godot" >/dev/null 2>&1; then
	check "a non-numeric version code is refused" 1
else
	check "a non-numeric version code is refused" 0
fi

# A missing file is the same class of fault: silently stamping nothing would
# ship version/code=1 forever.
if tools/ci/stamp_version.sh v0.3.0 42 "$tmp/nope.cfg" "$tmp/project.godot" >/dev/null 2>&1; then
	check "a missing presets file is refused" 1
else
	check "a missing presets file is refused" 0
fi

cat >"$tmp/pristine.cfg" <<'EOF'
[preset.0.options]

version/code=1
version/name="0.1.0"
package/unique_name="com.guillotinemods.godotdirectorplayer"

[preset.1.options]

application/file_version=""
application/product_version=""

[preset.2.options]

application/short_version=""
application/version=""
application/bundle_identifier="com.guillotinemods.godotdirectorplayer"
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
	# The project fixture is created rather than left missing, so the ONLY reason
	# the call can be refused is the tag. With a nonexistent path here the case
	# would keep passing if the charset check were ever reordered after the
	# file-existence checks -- refused, but for the wrong reason, which is the
	# failure mode this whole block is written to avoid.
	cp "$tmp/project.godot" "$tmp/guard.godot"
	cp "$tmp/guard.godot" "$tmp/guard.godot.before"
	if tools/ci/stamp_version.sh "$bad" 42 "$tmp/guard.cfg" "$tmp/guard.godot" >/dev/null 2>&1; then
		check "a tag with metacharacters is refused ($bad)" 1
	else
		check "a tag with metacharacters is refused ($bad)" 0
	fi
	if cmp -s "$tmp/pristine.cfg" "$tmp/guard.cfg"; then
		check "the file is untouched after refusing ($bad)" 0
	else
		check "the file is untouched after refusing ($bad)" 1
	fi
	if cmp -s "$tmp/guard.godot.before" "$tmp/guard.godot"; then
		check "project.godot is untouched after refusing ($bad)" 0
	else
		check "project.godot is untouched after refusing ($bad)" 1
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
