#!/usr/bin/env bash
# Stamps `[debug] enabled` into the tracked game config before an export.
#
#   tools/ci/stamp_debug_ui.sh true [director_game.cfg]
#
# The tracked file says `auto`, and `scenes/preview/debug_keys.gd` resolves that
# to `OS.has_feature("editor") or OS.is_debug_build()` -- both false under
# `--export-release`. So every published build so far has shipped with the whole
# preview layer off: no F-key bound at all, no hotspot outlines, no SKIP button,
# no container picker, no report at exit. That is right for a release and wrong
# for a pre-1.0 alpha, which is a build handed to people precisely so they can
# report what it did, and `v0.2.0-alpha` was the release where somebody noticed.
#
# **This is why it is stamped rather than committed.** `director_game.cfg` is
# tracked, so a `true` written into it in the repository would put the debug
# layer in every build, including the first one that is not an alpha. The whole
# argument for `auto` in `debug_keys.gd` is that the safe answer must be the one
# you get by doing nothing -- so the unsafe one is written by CI, onto a checkout
# it is about to throw away, and only for the channel that asked for it.
#
# The channel predicate is NOT here. `release.yml` resolves `v0.x` once, in
# `Resolve the release version`, and the same answer drives both this stamp and
# the GitHub pre-release flag -- for the reason that step's own comment gives
# about the version string: two places deriving one answer agree today and are
# one edit away from not agreeing. This script takes the resolved value and is
# responsible only for writing it and proving that it took.
#
# `auto` is passed for v1.0 and later, which writes the value the file already
# carries. That is deliberately not a no-op: it still fails if the key has been
# renamed or removed, so the release that most needs the layer OFF is the one
# that cannot silently lose the switch that turns it off.
#
# Writes in place. Not meant to be committed back.
set -euo pipefail

usage() {
	echo "usage: stamp_debug_ui.sh <true|false|auto> [config-file]" >&2
	exit 2
}

[ "$#" -ge 1 ] || usage
value=$1
file=${2:-director_game.cfg}

# The three spellings `director_game.cfg` documents and the launcher's Developer
# tab offers (`launcher.gd`'s `DEBUG_VALUES`). `debug_keys.gd:resolve_switch`
# also accepts `on`/`1`/`yes` and their opposites, but a stamped file is read by
# humans too, and a fourth spelling appearing only in builds is a difference
# between what CI ships and what the repository documents. Anything else is a
# mistake worth failing on: `resolve_switch` warns and falls back to `auto` on a
# value it does not know, so a typo here would strip the layer from an alpha and
# say so only in a log nobody reads.
case $value in
	true | false | auto) ;;
	*)
		echo "stamp_debug_ui: enabled must be true, false or auto, got '$value'" >&2
		exit 2
		;;
esac

[ -f "$file" ] || {
	echo "stamp_debug_ui: no such file: $file" >&2
	exit 2
}

# `^enabled = ` is anchored, and `[debug]` is the only section in the tracked
# file that has such a key -- but a config is a file people add sections to, and
# `[qol] enabled` would be an entirely reasonable thing for somebody to write.
# An anchored sed would then stamp both, and the one this script does not mean
# to touch would change silently in every release build. Counting first turns
# that into a refusal at the point the second key appears, rather than a defect
# discovered in a shipped artifact.
matches=$(grep -c '^enabled = ' "$file" || true)
if [ "$matches" != "1" ]; then
	echo "stamp_debug_ui: expected exactly one '^enabled = ' line in $file, found $matches" >&2
	echo "stamp_debug_ui: if a second section has gained one, this script has to be told which" >&2
	exit 1
fi

# `-i.bak` then remove: BSD sed needs the suffix, GNU sed accepts it, and this
# runs on both a developer's macOS and the Linux runner. Same reason
# `stamp_version.sh` spells it this way.
sed -i.bak -e "s|^enabled = .*|enabled = \"$value\"|" "$file"
rm -f "$file.bak"

# `grep -Fqx`: a literal whole line, not a pattern, for the reason
# `stamp_version.sh` records -- a value full of `.` read as a BRE passes on
# values it never wrote. There is nothing to substitute in a bare `true`, but
# the next value added might not be so plain.
grep -Fqx "enabled = \"$value\"" "$file" || {
	echo "stamp_debug_ui: [debug] enabled did not take in $file" >&2
	exit 1
}

# What this proves is that the file going INTO the export says so. That the
# `.pck` coming out carries it is the same unproven link every included file
# has, and it is covered the same way: `director_game.cfg` is named in every
# preset's `include_filter`, and `tools/export_presets_check.gd` fails if a
# preset stops naming it.
echo "stamped $file:"
echo "  debug: enabled = \"$value\""
