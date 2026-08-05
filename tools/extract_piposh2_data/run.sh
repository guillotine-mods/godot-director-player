#!/usr/bin/env bash
# Recover the Piposh 2 Director movies and casts from the Windows installer by
# running it under Wine in a 32-bit container, so no Windows machine is needed.
#
#   tools/extract_piposh2_data/run.sh ~/Downloads/piposh2.exe ~/Downloads/piposh2extracted/piposh2-data
#
# The run checks the two files ScummVM's detection entry keys on before it
# exits, and fails non-zero if either does not match. Those two are hashed by
# different rules — PIPOSH2.EXE on its last 5000 bytes, PIP2DATA/AIR1.DXR on its
# first 5000 — so the failure message names which form it used. See extract.sh.
#
# For the casts and movies, verify against the installer's own directory
# listing. The --ext filter
# is required: only the casts and movies are recovered, so without it the check
# also demands the 3141 .AIF files and fails.
#
#   python3 tools/list_vise_archive.py ~/Downloads/piposh2.exe \
#       --ext DXR CXT CST DIR --verify <output dir>
#
# On Apple Silicon this runs under qemu-i386 emulation and is slow — budget
# tens of minutes. Screenshots of the installer land in <output dir>/_screens,
# which is where to look first if it stalls.
set -euo pipefail

IMAGE=${IMAGE:-piposh2-extract}
DOCKER=${DOCKER:-docker}

if [ $# -lt 2 ]; then
    echo "usage: $0 <path to piposh2.exe> <output dir> [manual]" >&2
    exit 64
fi

installer=$1
outdir=$2
mode=${3:-auto}

[ -f "$installer" ] || { echo "no installer at $installer" >&2; exit 66; }
mkdir -p "$outdir"

installer_abs=$(cd "$(dirname "$installer")" && pwd)/$(basename "$installer")
outdir_abs=$(cd "$outdir" && pwd)

echo "building $IMAGE (32-bit; the first build pulls and emulates i386)"
"$DOCKER" build --platform linux/386 -t "$IMAGE" "$(dirname "$0")"

echo "running the installer under Wine; output goes to $outdir_abs"
"$DOCKER" run --rm \
    --platform linux/386 \
    -v "$installer_abs":/installer/piposh2.exe:ro \
    -v "$outdir_abs":/out \
    "$IMAGE" "$mode"
