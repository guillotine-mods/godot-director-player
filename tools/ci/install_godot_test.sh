#!/usr/bin/env bash
# Checks the installer without running it.
#
#   bash tools/ci/install_godot_test.sh [version]
#
# A full install is about 1 GB and lands in an OS-specific templates directory,
# so this asserts the things that break in practice without doing one: the
# script parses, it refuses a platform it does not know, and the pinned
# version's assets are still where the URLs say they are. Takes the version as
# an optional argument so the workflow can pass its own `$GODOT_VERSION` --
# without that, a version bump in the workflow leaves this hardcoded to the old
# one, and the "pre-flight" HEADs assets for a version nothing installs anymore
# and reports green.
#
# All three platforms, not just Linux. `release.yml` cross-exports everything
# from a Linux runner, but the nightly gate runs the harnesses natively on macOS
# and Windows, so a macOS or Windows asset that moved breaks a real job.
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=${1:-4.7.1-stable}
BASE="https://github.com/godotengine/godot-builds/releases/download/$VERSION"

# One EXIT trap, and every probe guarded with `if`. A bare `cmd; check ... $?`
# under `set -e` dies on the exact run where the check should have reported
# FAIL, and here that would defeat the suite's whole purpose: a renamed or
# missing release asset makes `curl -f` exit non-zero, which unguarded would
# abort the run instead of naming the asset that moved.
verdict=""
finish() {
	st=$?
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  install_godot: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

if bash -n tools/ci/install_godot.sh 2>/dev/null; then
	check "install_godot.sh parses" 0
else
	check "install_godot.sh parses" 1
fi

# Every asset the installer can reach for, one per platform plus the shared two.
# The templates .tpz carries every platform's set, which is why there is one of
# it rather than three.
for asset in \
	"Godot_v${VERSION}_linux.x86_64.zip" \
	"Godot_v${VERSION}_macos.universal.zip" \
	"Godot_v${VERSION}_win64.exe.zip" \
	"Godot_v${VERSION}_export_templates.tpz" \
	"SHA512-SUMS.txt"
do
	if curl -fsSLI --retry 3 -o /dev/null "$BASE/$asset"; then
		check "$asset resolves" 0
	else
		check "$asset resolves" 1
	fi
done

# Drift guard. The names above are written out here as well as in the installer,
# so an edit to one and not the other would leave this suite HEADing an asset
# nothing installs -- green, and testing nothing. Matched on the
# platform-distinguishing suffix because the installer interpolates the version.
for suffix in "_linux.x86_64.zip" "_macos.universal.zip" "_win64.exe.zip"; do
	if grep -qF "$suffix" tools/ci/install_godot.sh; then
		check "installer still names $suffix" 0
	else
		check "installer still names $suffix" 1
	fi
done

# The Windows pair, which is the subtlest thing the installer does. There is no
# separate console download: both binaries come out of `_win64.exe.zip`, and the
# shim finds its engine by stripping `_console.exe` from its own filename, so
# the two must be installed together with matching stems. Installing one alone
# makes every harness read as ERROR with no output (`gate_env.sh`), which is a
# failure with no signature pointing back here.
for name in "godot.exe" "godot_console.exe"; do
	if grep -qF "$name" tools/ci/install_godot.sh; then
		check "installer still writes $name" 0
	else
		check "installer still writes $name" 1
	fi
done

# Both path files, which a CI job on a cache hit reads INSTEAD of running this
# installer at all. Dropping either one breaks the restore path only -- a fresh
# install would still work, so nothing else here would notice.
for name in ".godot-path" ".templates-path"; do
	if grep -qF "$name" tools/ci/install_godot.sh; then
		check "installer still records $name" 0
	else
		check "installer still records $name" 1
	fi
done

# Refused before any download, so this costs nothing and needs no network. The
# platform `case` runs ahead of the first `curl` precisely so a typo fails in
# milliseconds rather than after a gigabyte.
if bash tools/ci/install_godot.sh "$VERSION" /nonexistent-bindir not-a-platform >/dev/null 2>&1; then
	check "an unknown platform is refused" 1
else
	check "an unknown platform is refused" 0
fi

echo ""
verdict=printed
if [ "$fail" -eq 0 ]; then echo "PASS  install_godot"; else echo "FAIL  install_godot"; fi
exit "$fail"
