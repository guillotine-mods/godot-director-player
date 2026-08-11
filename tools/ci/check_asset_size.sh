#!/usr/bin/env bash
# Refuses to publish an asset GitHub will not accept.
#
#   tools/ci/check_asset_size.sh build/android/GodotDirectorPlayer.apk ...
#
# A release asset is capped at 2 GiB. There is no cap on the number of assets,
# on total release size, or on download bandwidth, so this is the only size that
# matters.
#
# The fallback if it fires is not a larger limit, it is a narrower
# `include_filter`: `scenes/launcher/title_list.gd` describes shipping one title
# instead of six, and the launcher already hides what did not ship.
set -euo pipefail

LIMIT=$((2 * 1024 * 1024 * 1024))

fail=0

# No arguments is not "nothing to check, so pass" -- it means the caller's
# file list was empty, which is itself a bug worth failing loudly on rather
# than exiting 0 having checked nothing.
if [ "$#" -eq 0 ]; then
	echo "FAIL  check_asset_size: no files given to check"
	exit 1
fi

for f in "$@"; do
	if [ ! -f "$f" ]; then
		echo "FAIL  $f: not built"
		fail=1
		continue
	fi
	# `-f` says it is a regular file, not that it can be opened. Without this,
	# `wc -c <"$f"` fails on an unreadable file and `set -e` takes the whole run
	# with it: a raw shell error instead of a named FAIL, and every file after
	# this one goes unchecked. A gate that stops halfway and reports in the
	# wrong voice is the failure this script exists to prevent, turned inward.
	if [ ! -r "$f" ]; then
		echo "FAIL  $f: not readable"
		fail=1
		continue
	fi
	size=$(wc -c <"$f")
	mib=$((size / 1024 / 1024))
	# MiB alone is truncated, so a file one byte over the limit prints the same
	# "2048 MiB" as the limit itself -- the message that most needs to be
	# unambiguous reads as a contradiction. Bytes alongside settle it.
	if [ "$size" -gt "$LIMIT" ]; then
		echo "FAIL  $f: ${size} bytes (${mib} MiB) exceeds the ${LIMIT} byte limit"
		fail=1
	else
		echo "ok    $f: ${size} bytes (${mib} MiB)"
	fi
done

exit "$fail"
