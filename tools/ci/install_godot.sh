#!/usr/bin/env bash
# Installs a pinned Godot and its export templates on a Linux runner.
#
#   tools/ci/install_godot.sh 4.7.1-stable "$HOME/godot-bin"
#
# Pinned rather than latest: a binary and a template set that disagree fail the
# export outright, and `project.godot` declares 4.7. Fetched from
# `godotengine/godot-builds` directly rather than through a third-party setup
# action or container, so the version stays under our control and the only
# trust boundary is GitHub's own release hosting -- the same reasoning
# `titles/piposh-3d`'s `verify.yml` follows.
#
# Linux-only. `sha512sum` is GNU; the macOS spelling differs and this script is
# never run there. `tools/ci/install_godot_test.sh` is what a developer runs.
set -euo pipefail

version=${1:?usage: install_godot.sh <version, e.g. 4.7.1-stable> <bindir>}
bindir=${2:?usage: install_godot.sh <version> <bindir>}

# `4.7.1-stable` in the download URL is `4.7.1.stable` in the templates path.
dotted=${version//-/.}

base="https://github.com/godotengine/godot-builds/releases/download/$version"
bin_zip="Godot_v${version}_linux.x86_64.zip"
tpz="Godot_v${version}_export_templates.tpz"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "fetching $bin_zip and $tpz"
curl -fsSL --retry 3 -o "$work/$bin_zip" "$base/$bin_zip"
curl -fsSL --retry 3 -o "$work/$tpz" "$base/$tpz"
curl -fsSL --retry 3 -o "$work/SHA512-SUMS.txt" "$base/SHA512-SUMS.txt"

# Verify only the two lines we care about. Checking the whole manifest would
# fail on every asset we did not download.
(cd "$work" && grep -E "  (${bin_zip}|${tpz})\$" SHA512-SUMS.txt | sha512sum -c -)

mkdir -p "$bindir"
unzip -q -o "$work/$bin_zip" -d "$work/bin"
mv "$work/bin/Godot_v${version}_linux.x86_64" "$bindir/godot"
chmod +x "$bindir/godot"

# The .tpz is a zip whose entries live under `templates/`; Godot wants them
# directly inside a directory named for the dotted version.
templates="$HOME/.local/share/godot/export_templates/$dotted"
mkdir -p "$templates"
unzip -q -o "$work/$tpz" -d "$work/tpl"
mv "$work"/tpl/templates/* "$templates/"

"$bindir/godot" --version
echo "templates in $templates: $(find "$templates" -type f | wc -l) file(s)"
