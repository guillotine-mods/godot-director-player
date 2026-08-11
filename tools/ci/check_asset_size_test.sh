#!/usr/bin/env bash
# Checks the size gate against sparse fixtures either side of the limit.
#
#   bash tools/ci/check_asset_size_test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp=$(mktemp -d)

# One EXIT trap only, matching tools/ci/stamp_version_test.sh: cleanup and the
# abort guard share a single handler, or a second `trap ... EXIT` would
# silently disable the first and leak $tmp every run. `st=$?` is captured
# before the `rm` so cleanup cannot overwrite the suite's own exit status, and
# `verdict` is declared before the trap is registered so `set -u` does not
# trip inside the handler on an unset variable.
verdict=""
finish() {
	st=$?
	rm -rf "$tmp"
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  check_asset_size: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

# No files given must not read as "nothing to check, so pass" -- that would
# let a caller with an empty file list publish having verified nothing.
if tools/ci/check_asset_size.sh >/dev/null 2>&1; then
	check "no arguments is refused, not a silent pass" 1
else
	check "no arguments is refused, not a silent pass" 0
fi

# Sparse files: `dd` with a seek and no input allocates nothing on disk but
# reports the full size, which is all the gate reads.
dd if=/dev/null of="$tmp/small.apk" bs=1 seek=$((10 * 1024 * 1024)) 2>/dev/null
dd if=/dev/null of="$tmp/big.apk" bs=1 seek=$((2 * 1024 * 1024 * 1024 + 1)) 2>/dev/null

if tools/ci/check_asset_size.sh "$tmp/small.apk" >/dev/null 2>&1; then
	check "an asset under the limit passes" 0
else
	check "an asset under the limit passes" 1
fi

if tools/ci/check_asset_size.sh "$tmp/big.apk" >/dev/null 2>&1; then
	check "an asset over 2 GiB is refused" 1
else
	check "an asset over 2 GiB is refused" 0
fi

# One bad file among several must still fail the run, or a release goes out
# with one good asset and one that never uploaded.
if tools/ci/check_asset_size.sh "$tmp/small.apk" "$tmp/big.apk" >/dev/null 2>&1; then
	check "one oversize asset fails a multi-file check" 1
else
	check "one oversize asset fails a multi-file check" 0
fi

# An export that produced nothing must not read as a pass.
if tools/ci/check_asset_size.sh "$tmp/never-built.apk" >/dev/null 2>&1; then
	check "a missing asset is refused" 1
else
	check "a missing asset is refused" 0
fi

# The limit itself: GitHub's cap is 2 GiB, and the gate uses `-gt`, so exactly
# 2147483648 bytes must still pass and the very next byte must not. A gate
# that used `-ge` instead would fail this exact-limit case; a gate that
# computed the limit off by a factor (MiB vs GiB, decimal vs binary) would
# fail one side or the other of this pair.
dd if=/dev/null of="$tmp/exact-limit.apk" bs=1 seek=$((2 * 1024 * 1024 * 1024)) 2>/dev/null
dd if=/dev/null of="$tmp/one-over.apk" bs=1 seek=$((2 * 1024 * 1024 * 1024 + 1)) 2>/dev/null

if tools/ci/check_asset_size.sh "$tmp/exact-limit.apk" >/dev/null 2>&1; then
	check "a file at exactly the 2 GiB limit passes" 0
else
	check "a file at exactly the 2 GiB limit passes" 1
fi

if tools/ci/check_asset_size.sh "$tmp/one-over.apk" >/dev/null 2>&1; then
	check "a file one byte over the limit is refused" 1
else
	check "a file one byte over the limit is refused" 0
fi

# `-f` is true for a file that cannot be opened, so without an explicit `-r`
# check the size read fails and `set -e` takes the whole run with it.
if [ "$(id -u)" -eq 0 ]; then
	echo "skip  unreadable-asset cases (running as root: every file is readable)"
else
	printf 'x' >"$tmp/unreadable.apk"
	chmod 000 "$tmp/unreadable.apk"

	if tools/ci/check_asset_size.sh "$tmp/unreadable.apk" >/dev/null 2>&1; then
		check "an unreadable asset is refused" 1
	else
		check "an unreadable asset is refused" 0
	fi

	# The exit code alone proves nothing here: an abort is also nonzero.
	# What distinguishes a report from a crash is that the file is NAMED and
	# that the run continues to the next one.
	out=$(tools/ci/check_asset_size.sh "$tmp/unreadable.apk" "$tmp/small.apk" 2>&1 || true)

	if printf '%s' "$out" | grep -q "not readable"; then
		check "an unreadable asset is named, not crashed on" 0
	else
		check "an unreadable asset is named, not crashed on" 1
	fi

	if printf '%s' "$out" | grep -q "small.apk"; then
		check "files after an unreadable one are still checked" 0
	else
		check "files after an unreadable one are still checked" 1
	fi

	chmod 644 "$tmp/unreadable.apk"
fi

echo ""
verdict=printed
if [ "$fail" -eq 0 ]; then echo "PASS  check_asset_size"; else echo "FAIL  check_asset_size"; fi
exit "$fail"
