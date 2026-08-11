#!/usr/bin/env bash
# Stamps the release version into the Android and macOS presets.
#
#   tools/ci/stamp_version.sh v0.2.0 41 [export_presets.cfg]
#
# Android refuses to install an update whose versionCode did not increase, so a
# preset shipping the committed `version/code=1` forever makes every release
# after the first uninstallable over its predecessor. That is the
# uninstall-first path that costs the player their saves, which is the whole
# reason the release keystore is a stored secret rather than a generated one.
#
# macOS enforces nothing of the kind -- the player replaces the .app and no
# version is consulted -- so the macOS keys are stamped for a weaker reason: an
# Info.plist reporting 1.0 for every build makes "which version is this?"
# unanswerable from the artifact, and Finder's Get Info reads
# `application/short_version`. The two macOS keys map onto the same two inputs
# Android uses: `short_version` is the marketing string a human reads, `version`
# is the monotonic build counter (Apple's CFBundleShortVersionString and
# CFBundleVersion respectively). Keeping the build counter monotonic costs
# nothing here and is what notarization or any App Store route would later
# require.
#
# The four keys are anchored with `^` and do not collide: `^version/` cannot
# match macOS's `application/version`, and `^application/version=` cannot match
# the Windows preset's `application/file_version` or `application/product_version`.
# Those two Windows keys are a real and separate gap -- the exe reports no
# version at all -- deliberately left alone here rather than fixed in passing.
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
	echo "usage: stamp_version.sh <tag> <code> [presets-file] [project-file]" >&2
	exit 2
}

[ "$#" -ge 2 ] || usage
tag=$1
code=$2
file=${3:-export_presets.cfg}
project=${4:-project.godot}

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

[ -f "$project" ] || {
	echo "stamp_version: no such file: $project" >&2
	exit 2
}

# `-i.bak` then remove: BSD sed needs the suffix, GNU sed accepts it, and this
# script runs on both a developer's macOS and the Linux runner.
sed -i.bak \
	-e "s|^version/code=.*|version/code=$code|" \
	-e "s|^version/name=.*|version/name=\"$name\"|" \
	-e "s|^application/short_version=.*|application/short_version=\"$name\"|" \
	-e "s|^application/version=.*|application/version=\"$code\"|" \
	"$file"
rm -f "$file.bak"

# `grep -Fqx`: the written value is compared as a literal whole line, not as a
# pattern. A semver name is full of `.`, which as a BRE matches any character,
# so the previous form passed on values it had not actually written.
#
# Every key is required rather than stamped-if-present. A preset that has lost
# its version keys is exactly the silent failure this script exists to prevent,
# and "the sed matched nothing, so there was nothing to do" is indistinguishable
# from it. If a preset is ever dropped, this fails and says which key.
expect() { # expect <literal line> <key name>
	grep -Fqx "$1" "$file" || {
		echo "stamp_version: $2 did not take" >&2
		exit 1
	}
}

expect "version/code=$code" "version/code"
expect "version/name=\"$name\"" "version/name"
expect "application/short_version=\"$name\"" "application/short_version"
expect "application/version=\"$code\"" "application/version"

# The only version any of this puts in front of a player.
#
# The export presets above are read at BUILD time and are invisible to the running
# game: nothing in `director/` or `scenes/` can ask what an Android versionName
# was. `application/config/version` is an ordinary project setting, so it survives
# into `project.binary` and `ProjectSettings.get_setting` answers it on every
# platform. That is what `scenes/launcher/launcher.gd` shows in its header.
#
# `<name>+<code>`, semver's build-metadata spelling: the name alone cannot
# distinguish two builds of the same tag, and a bug report naming `0.2.0+41`
# identifies the exact workflow run that produced the binary. Left as
# `0.0.0-dev` in the tracked file, so a build from source is never mistaken for
# a release in a screenshot.
build="$name+$code"
sed -i.bak -e "s|^config/version=.*|config/version=\"$build\"|" "$project"
rm -f "$project.bak"

grep -Fqx "config/version=\"$build\"" "$project" || {
	echo "stamp_version: config/version did not take in $project" >&2
	exit 1
}

# "apple" rather than "macos": the iOS preset carries the same two key names, so
# one sed stamps both and the iOS target needed no separate handling. Saying
# "macos" here would misreport what was written the moment anyone checks.
echo "stamped $file:"
echo "  android: version/name=\"$name\" version/code=$code"
echo "  apple:   application/short_version=\"$name\" application/version=\"$code\" (macOS and iOS)"
echo "stamped $project:"
echo "  runtime: config/version=\"$build\""
