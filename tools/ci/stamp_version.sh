#!/usr/bin/env bash
# Stamps the release version into the Android preset.
#
#   tools/ci/stamp_version.sh v0.2.0 41 [export_presets.cfg]
#
# Android refuses to install an update whose versionCode did not increase, so a
# preset shipping the committed `version/code=1` forever makes every release
# after the first uninstallable over its predecessor. That is the
# uninstall-first path that costs the player their saves, which is the whole
# reason the release keystore is a stored secret rather than a generated one.
#
# Writes in place, on a checkout CI is about to throw away. Not meant to be
# committed back.
set -euo pipefail

tag=${1:?usage: stamp_version.sh <tag> <code> [presets-file]}
code=${2:?usage: stamp_version.sh <tag> <code> [presets-file]}
file=${3:-export_presets.cfg}

# `v0.2.0` is the tag; `0.2.0` is what Android shows. Anything not starting with
# a `v` is left alone, so a `2026.1` scheme stamps as itself.
name=${tag#v}

case $code in
	'' | *[!0-9]*)
		echo "stamp_version: version code must be a positive integer, got '$code'" >&2
		exit 2
		;;
esac

[ -f "$file" ] || {
	echo "stamp_version: no such file: $file" >&2
	exit 2
}

# `-i.bak` then remove: BSD sed needs the suffix, GNU sed accepts it, and this
# script runs on both a developer's macOS and the Linux runner.
sed -i.bak \
	-e "s|^version/code=.*|version/code=$code|" \
	-e "s|^version/name=.*|version/name=\"$name\"|" \
	"$file"
rm -f "$file.bak"

# A substitution that matched nothing exits 0, so the write is read back rather
# than assumed.
grep -q "^version/code=$code\$" "$file" || {
	echo "stamp_version: version/code did not take" >&2
	exit 1
}
grep -q "^version/name=\"$name\"\$" "$file" || {
	echo "stamp_version: version/name did not take" >&2
	exit 1
}

echo "stamped $file: version/name=\"$name\" version/code=$code"
