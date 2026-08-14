#!/usr/bin/env bash
#
# Fetch the optional video decoder GDExtension, at a pinned release, verified by
# digest, into the git-ignored `addons/` directory.
#
# Nothing in this repository requires it. `scenes/preview/video.gd` asks
# `ClassDB.class_exists` and never a path, so with `addons/` empty the engine is
# byte-for-byte the engine it was and `tools/video_plugin.gd` asserts that. This
# script exists so that installing one is a pinned, checksummed, reversible step
# instead of "download a zip from somewhere and unpack it into the right folder".
#
# ## Read docs/DIGITAL_VIDEO.md §9 before running this
#
# Three things it says that this script cannot say for you:
#
#   1. **It will not play this corpus.** EIRTeam.FFmpeg 1.1.4's bundled FFmpeg
#      has no MPEG-PS demuxer and no MS-RLE decoder — measured, and matching its
#      own build recipe — so it decodes 0 of the 23 media files under
#      `test-games/itamar-magichat`. It plays h264/vp9 in mp4/webm/mkv/mov, which
#      is a replacement-media path, not an original-media one.
#   2. **It is LGPL-2.1+ and ships no licence text.** The archive has no LICENSE,
#      COPYING or NOTICE file. If you distribute a build containing these
#      binaries, §9.3 is the list of what you owe.
#   3. **It has no Android, iOS or macOS binary**, while its own `.gdextension`
#      declares Android and macOS. The export presets exclude `addons/*` on those
#      three platforms for that reason; do not remove those exclusions without
#      reading §9.2, which has what an APK built with them in place actually
#      contained.
#
# Usage:
#   tools/fetch_video_plugin.sh            # fetch and unpack into addons/
#   tools/fetch_video_plugin.sh --remove   # delete addons/ffmpeg again
#
# After fetching, open the Godot editor once and close it. A GDExtension is
# loaded from `.godot/extension_list.cfg`, which only an editor run writes, so a
# headless `--script` run against a fresh `addons/` sees no extension at all and
# reports "none installed" — which looks exactly like a failed download.

set -euo pipefail

# Pinned release. `autobuild-2025-11-12-13-44` is the tag; 1.1.4 is the version
# in the asset name. Pinned rather than `latest` for the same reason the ScummVM
# fetch pins a revision, plus one more: a newer release can raise
# `compatibility_minimum` above this project's Godot, and the failure mode of
# that is silent (the extension simply never registers its classes).
PLUGIN_TAG="autobuild-2025-11-12-13-44"
PLUGIN_ASSET="eirteam-ffmpeg-1.1.4.zip"
PLUGIN_SHA256="1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c"
PLUGIN_SIZE=11003257
PLUGIN_URL="https://github.com/EIRTeam/EIRTeam.FFmpeg/releases/download/${PLUGIN_TAG}/${PLUGIN_ASSET}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/addons"

if [ "${1:-}" = "--remove" ]; then
  rm -rf "${DEST}/ffmpeg"
  echo "removed ${DEST}/ffmpeg"
  echo "open the editor once so .godot/extension_list.cfg stops naming it."
  exit 0
fi

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "fetching ${PLUGIN_ASSET} (${PLUGIN_SIZE} bytes)"
curl -fsSL "${PLUGIN_URL}" -o "${TMP}/${PLUGIN_ASSET}"

# Verified rather than trusted. This is the one step in this repository that
# takes a compiled binary from the network and puts it where the engine will
# load it, and an unverified download there is arbitrary code execution on every
# subsequent editor launch.
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum "${TMP}/${PLUGIN_ASSET}" | cut -d' ' -f1)"
elif command -v shasum >/dev/null; then
  actual="$(shasum -a 256 "${TMP}/${PLUGIN_ASSET}" | cut -d' ' -f1)"
else
  echo "no sha256sum or shasum on PATH; refusing to install an unverified binary" >&2
  exit 1
fi
if [ "${actual}" != "${PLUGIN_SHA256}" ]; then
  echo "digest mismatch" >&2
  echo "  expected ${PLUGIN_SHA256}" >&2
  echo "  got      ${actual}" >&2
  exit 1
fi
echo "digest ok"

mkdir -p "${DEST}"
unzip -q -o "${TMP}/${PLUGIN_ASSET}" -d "${DEST}"

# The `.gdextension` names absolute `res://addons/ffmpeg/...` paths, so the
# directory name is not negotiable: an archive that unpacked to any other name
# leaves an extension that loads nothing and reports nothing, which is
# indistinguishable from not installing it.
if [ ! -f "${DEST}/ffmpeg/ffmpeg.gdextension" ]; then
  echo "unpacked, but ${DEST}/ffmpeg/ffmpeg.gdextension is not there." >&2
  echo "the archive layout changed; the paths inside the .gdextension are" >&2
  echo "absolute res://addons/ffmpeg/... and the directory name must match." >&2
  exit 1
fi

echo
echo "installed to ${DEST}/ffmpeg"
echo
# Reported rather than assumed, because which platforms the asset actually
# carries is the fact that decides whether a mobile export is safe, and it has
# already been wrong once: the .gdextension declares four platforms and the
# archive has carried two.
echo "platform directories present:"
for d in "${DEST}"/ffmpeg/*/; do
  [ -d "$d" ] && echo "  $(basename "$d")"
done
echo
echo "platforms the .gdextension declares:"
sed -n 's/^\([a-z]*\)\..*=.*/  \1/p' "${DEST}/ffmpeg/ffmpeg.gdextension" | sort -u
echo
echo "next: open the Godot editor once and close it, then"
echo "  godot --headless --audio-driver Dummy --path . --script tools/video_plugin.gd -- \\"
echo "      --root res://test-games/itamar-magichat --boot magichat.dir"
