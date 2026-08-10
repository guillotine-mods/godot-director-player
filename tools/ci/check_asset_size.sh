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
for f in "$@"; do
	if [ ! -f "$f" ]; then
		echo "FAIL  $f: not built"
		fail=1
		continue
	fi
	size=$(wc -c <"$f")
	mib=$((size / 1024 / 1024))
	if [ "$size" -gt "$LIMIT" ]; then
		echo "FAIL  $f: ${mib} MiB exceeds the 2048 MiB release-asset limit"
		fail=1
	else
		echo "ok    $f: ${mib} MiB"
	fi
done

exit "$fail"
