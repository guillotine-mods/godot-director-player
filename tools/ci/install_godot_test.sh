#!/usr/bin/env bash
# Checks the installer without running it.
#
#   bash tools/ci/install_godot_test.sh
#
# The full install is Linux-only and about 1 GB, so this asserts the two things
# that break in practice: the script parses, and the pinned version's assets are
# still where the URLs say they are.
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=4.7.1-stable
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

for asset in "Godot_v${VERSION}_linux.x86_64.zip" "Godot_v${VERSION}_export_templates.tpz" "SHA512-SUMS.txt"; do
	if curl -fsSLI -o /dev/null "$BASE/$asset"; then
		check "$asset resolves" 0
	else
		check "$asset resolves" 1
	fi
done

echo ""
verdict=printed
if [ "$fail" -eq 0 ]; then echo "PASS  install_godot"; else echo "FAIL  install_godot"; fi
exit "$fail"
