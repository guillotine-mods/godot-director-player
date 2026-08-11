#!/usr/bin/env bash
# Tells a headless Godot where the Android SDK is.
#
#   tools/ci/write_editor_settings.sh "$ANDROID_SDK_ROOT" [godot-version]
#
# Godot documents the SDK path only as an Editor Settings field in the GUI.
# There is no environment variable for it, unlike the three keystore ones, so a
# runner has to be handed the settings file itself. Godot names that file for
# the major.minor it belongs to, so the version has to be passed in rather than
# hardcoded here -- this was the one copy of the Godot version not tied to
# `$GODOT_VERSION`, and a version bump elsewhere would silently write a file
# Godot never reads, surfacing later as a missing-SDK error naming no version
# mismatch. Optional, defaulting to 4.7, so existing callers keep working.
set -euo pipefail

sdk=${1:?usage: write_editor_settings.sh <android-sdk-path> [godot-version]}
[ -d "$sdk" ] || {
	echo "write_editor_settings: no such SDK directory: $sdk" >&2
	exit 2
}

# `4.7.1-stable` -> `4.7`: only the first two dot-separated fields matter.
version=${2:-}
if [ -n "$version" ]; then
	major_minor=$(printf '%s' "$version" | cut -d. -f1,2)
else
	major_minor="4.7"
fi

dir="$HOME/.config/godot"
mkdir -p "$dir"
file="$dir/editor_settings-$major_minor.tres"

cat >"$file" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$sdk"
EOF

echo "wrote $file (android_sdk_path = $sdk)"
