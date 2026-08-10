#!/usr/bin/env bash
# Tells a headless Godot where the Android SDK is.
#
#   tools/ci/write_editor_settings.sh "$ANDROID_SDK_ROOT"
#
# Godot documents the SDK path only as an Editor Settings field in the GUI.
# There is no environment variable for it, unlike the three keystore ones, so a
# runner has to be handed the settings file itself. Godot names that file for
# the major.minor it belongs to.
set -euo pipefail

sdk=${1:?usage: write_editor_settings.sh <android-sdk-path>}
[ -d "$sdk" ] || {
	echo "write_editor_settings: no such SDK directory: $sdk" >&2
	exit 2
}

dir="$HOME/.config/godot"
mkdir -p "$dir"
file="$dir/editor_settings-4.7.tres"

cat >"$file" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$sdk"
EOF

echo "wrote $file (android_sdk_path = $sdk)"
