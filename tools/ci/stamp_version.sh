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
#
# The tag arrives from `$GITHUB_REF_NAME`, which is whatever string the person
# pushing the tag chose, and it used to be spliced into a `|`-delimited sed
# script unescaped. A tag carrying `&` made sed splice the whole matched line
# back into itself and left the file half-stamped; a tag carrying `|` broke the
# delimiter. Both are refused up front rather than escaped, because a version
# name outside this charset is a mistake worth failing on, not a string worth
# quoting.
set -euo pipefail

usage() {
	echo "usage: stamp_version.sh <tag> <code> [presets-file]" >&2
	exit 2
}

[ "$#" -ge 2 ] || usage
tag=$1
code=$2
file=${3:-export_presets.cfg}

[ -n "$tag" ] || usage
[ -n "$code" ] || usage

# `v0.2.0` is the tag; `0.2.0` is what Android shows. Anything not starting with
# a `v` is left alone, so a `2026.1` scheme stamps as itself.
name=${tag#v}

case $code in
	'' | *[!0-9]*)
		echo "stamp_version: version code must be a positive integer, got '$code'" >&2
		exit 2
		;;
esac

case $name in
	'' | *[!A-Za-z0-9._+-]*)
		echo "stamp_version: version name must match [A-Za-z0-9._+-]+, got '$name'" >&2
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

# `grep -Fqx`: the written value is compared as a literal whole line, not as a
# pattern. A semver name is full of `.`, which as a BRE matches any character,
# so the previous form passed on values it had not actually written.
grep -Fqx "version/code=$code" "$file" || {
	echo "stamp_version: version/code did not take" >&2
	exit 1
}
grep -Fqx "version/name=\"$name\"" "$file" || {
	echo "stamp_version: version/name did not take" >&2
	exit 1
}

echo "stamped $file: version/name=\"$name\" version/code=$code"
