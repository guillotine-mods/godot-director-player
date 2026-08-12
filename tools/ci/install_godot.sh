#!/usr/bin/env bash
# Installs a pinned Godot and its export templates.
#
#   tools/ci/install_godot.sh 4.7.1-stable "$HOME/godot-bin" [platform]
#
# Prints the installed binary's path as its LAST line, so a caller can set
# $GODOT from it without hardcoding a version string. `gate_env.sh` honours
# $GODOT ahead of PATH and ahead of the usual install locations, which is what
# lets the nightly workflow point the gate at this without an edit there.
#
# Pinned rather than latest: a binary and a template set that disagree fail the
# export outright, and `project.godot` declares 4.7. Fetched from
# `godotengine/godot-builds` directly rather than through a third-party setup
# action or container, so the version stays under our control and the only
# trust boundary is GitHub's own release hosting -- the same reasoning
# `titles/piposh-3d`'s `verify.yml` follows.
#
# Three platforms, not one. This was Linux-only while the only thing it served
# was `release.yml`, which cross-exports every target from a Linux runner. The
# nightly gate runs the harnesses on macOS and Windows, where they have to run
# natively, so all three cases are live now. `platform` overrides the `uname -s`
# guess for the case where they disagree.
set -euo pipefail

version=${1:?usage: install_godot.sh <version, e.g. 4.7.1-stable> <bindir> [platform]}
bindir=${2:?usage: install_godot.sh <version> <bindir> [platform]}

# `4.7.1-stable` in the download URL is `4.7.1.stable` in the templates path.
dotted=${version//-/.}

# git-bash reports MINGW64_NT-10.0 and MSYS2 reports MSYS_NT-10.0. Both are the
# Windows case, and the first is what a `shell: bash` step gets on a windows
# runner.
detect_platform() {
	case "$(uname -s)" in
		Darwin) echo macos ;;
		Linux) echo linux ;;
		MINGW*|MSYS*|CYGWIN*) echo windows ;;
		*)
			echo "install_godot: unrecognised platform '$(uname -s)'; pass one explicitly" >&2
			return 1
			;;
	esac
}
platform=${3:-$(detect_platform)}

case "$platform" in
	linux)   bin_zip="Godot_v${version}_linux.x86_64.zip" ;;
	macos)   bin_zip="Godot_v${version}_macos.universal.zip" ;;
	windows) bin_zip="Godot_v${version}_win64.exe.zip" ;;
	*)
		echo "install_godot: unknown platform '$platform' (want linux, macos or windows)" >&2
		exit 1
		;;
esac

# `sha512sum` is GNU. macOS ships no such thing, and its `shasum -a 512` reads
# the same `<hash>  <name>` format with `-c`. git-bash carries the GNU one, so
# only the Mac takes the second branch.
sha512_check() {
	if command -v sha512sum >/dev/null 2>&1; then
		sha512sum -c -
	else
		shasum -a 512 -c -
	fi
}

# Godot reads its export templates from one OS-specific path and there is no
# flag to move them, so an install that puts them anywhere else silently has
# none. Needed here even though the gate only runs `--headless --script`:
# `gate_require_pack` builds `titles/piposh3d.pck` through `build_pack.sh`,
# which is an `--export-pack` and does need templates.
templates_root() {
	case "$platform" in
		linux)   printf '%s\n' "$HOME/.local/share/godot/export_templates" ;;
		macos)   printf '%s\n' "$HOME/Library/Application Support/Godot/export_templates" ;;
		windows)
			# `$APPDATA` is a native Windows path with backslashes
			# (`C:\Users\runneradmin\AppData\Roaming`), and `mkdir -p` and `mv`
			# below want the `/c/Users/...` form. `cygpath -u` is what git-bash
			# ships to do that conversion; without it the templates land in a
			# directory named for the whole mangled string, `--export-pack`
			# then finds none, and `gate_require_pack` is never fatal -- so the
			# run continues and every harness carries twelve autoload errors
			# instead of anything naming this.
			appdata=${APPDATA:?APPDATA is unset, so this is not a Windows shell}
			if command -v cygpath >/dev/null 2>&1; then
				appdata=$(cygpath -u "$appdata")
			fi
			printf '%s\n' "$appdata/Godot/export_templates"
			;;
	esac
}

base="https://github.com/godotengine/godot-builds/releases/download/$version"
tpz="Godot_v${version}_export_templates.tpz"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "installing godot $version for $platform"
curl -fsSL --retry 3 -o "$work/$bin_zip" "$base/$bin_zip"
curl -fsSL --retry 3 -o "$work/$tpz" "$base/$tpz"
curl -fsSL --retry 3 -o "$work/SHA512-SUMS.txt" "$base/SHA512-SUMS.txt"

# Verify only the two lines we care about. Checking the whole manifest would
# fail on every asset we did not download.
(cd "$work" && grep -E "  (${bin_zip}|${tpz})\$" SHA512-SUMS.txt | sha512_check)

mkdir -p "$bindir"
unzip -q -o "$work/$bin_zip" -d "$work/bin"

case "$platform" in
	linux)
		mv "$work/bin/Godot_v${version}_linux.x86_64" "$bindir/godot"
		chmod +x "$bindir/godot"
		godot_bin="$bindir/godot"
		;;
	macos)
		# The whole .app is kept rather than the executable lifted out of it.
		# Headless probably does not read anything else in the bundle, but
		# "probably" is doing real work in that sentence and the bundle costs
		# nothing to keep.
		mv "$work/bin/Godot.app" "$bindir/Godot.app"
		godot_bin="$bindir/Godot.app/Contents/MacOS/Godot"
		chmod +x "$godot_bin"
		;;
	windows)
		# There is no separate console download. `Godot_v<version>_win64_console.exe.zip`
		# 404s and the release manifest lists no such asset: both binaries ship
		# inside this one zip, a ~170 MB engine and a ~190 KB console shim.
		#
		# The shim locates its engine by stripping `_console.exe` from its own
		# module filename -- it carries that literal and no hardcoded engine
		# name -- so the two MUST keep matching stems. `godot.exe` and
		# `godot_console.exe` preserve that; renaming only one breaks it in a
		# way nothing here would notice.
		#
		# The console one is what gets invoked, and that is not cosmetic:
		# `gate_env.sh` records that the plain build detaches from the terminal,
		# so `$(...)` captures nothing and every harness reads as ERROR with no
		# output to say why.
		mv "$work/bin/Godot_v${version}_win64.exe" "$bindir/godot.exe"
		mv "$work/bin/Godot_v${version}_win64_console.exe" "$bindir/godot_console.exe"
		godot_bin="$bindir/godot_console.exe"
		# `gate_env.sh` reaches $GODOT through `[ -x ... ]`, which is a real test
		# in git-bash and not a formality: an unzip that left the bit clear makes
		# the gate refuse the binary it was just handed, reporting that $GODOT
		# "is not an executable" about a file that plainly is.
		chmod +x "$bindir/godot.exe" "$godot_bin"
		;;
esac

# The .tpz is a zip whose entries live under `templates/`; Godot wants them
# directly inside a directory named for the dotted version.
templates="$(templates_root)/$dotted"
mkdir -p "$templates"
unzip -q -o "$work/$tpz" -d "$work/tpl"
mv "$work"/tpl/templates/* "$templates/"

"$godot_bin" --version
echo "templates in $templates: $(find "$templates" -type f | wc -l) file(s)"

# Both paths recorded inside `$bindir`, which matters because the caller that
# most needs them is the one that never ran this script: a CI job restoring
# `$bindir` from a cache skips the install entirely, and would otherwise have to
# re-derive the per-OS rules above to know what it just restored.
printf '%s\n' "$godot_bin" > "$bindir/.godot-path"
printf '%s\n' "$templates" > "$bindir/.templates-path"

# LAST line, and the caller reads it as the installed path. Everything above is
# progress output, so nothing may be printed after this.
printf '%s\n' "$godot_bin"
