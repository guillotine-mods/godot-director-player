#!/usr/bin/env bash
#
# Capture a reference trace from ScummVM for one movie, for diffing against the
# port's own trace (lingo/lingo_trace.gd, PIPOSH2_TRACE=...).
#
# Usage:
#   tools/capture_scummvm_trace.sh DAY1.DXR [frames] [outfile]
#
#   frames   how many frames to play. Anything other than "all" uses ScummVM's
#            `fewframesonly`, which is a hard-coded 10-frame cap plus whatever
#            the current frame loop finishes, so it stops around frame 19. It is
#            the only built-in bound; "all" plays until the movie ends and is
#            unbounded for a parked hub room, which most of this game's rooms
#            are. Prefer the default.
#
# WHAT THIS ESTABLISHED, and why the script exists rather than a one-liner:
#
# ScummVM detects `director:piposh2` from PIPOSH2.EXE plus PIP2DATA/AIR1.DXR, but
# launching the target plays the PROJECTOR, whose own score is one frame. It
# reports "Finished playback of movie 'PIPOSH2.EXE'" and stops without ever
# opening a movie under PIP2DATA/. So the target is detected-but-not-playable as
# shipped, and the oracle only works when pointed at a game movie explicitly via
# the engine's `start_movie` config key (director.cpp:451, parsed "movie,frame" —
# passing a frame makes it warn "Duplicate startup movie" and ignore it, so this
# script passes the movie alone).
#
# Everything goes through a throwaway config under the output directory. The
# user's real "ScummVM Preferences" is never read or written: `start_movie` is a
# persisted setting, and leaving it behind would silently change what launching
# the game from the ScummVM GUI does.
#
# TRACE STREAMS, and where each comes from:
#   loading @9    per-frame channel dump — Score::formatChannelInfo() is emitted
#                 by debugC(9, kDebugLoading) at score.cpp:2289, NOT by the
#                 console `channels` command. That is what makes this scriptable.
#   events        event dispatch, incl. the no-match path
#   lingoexec     Lingo execution, plus freeze/thaw around `go`
#   lingothe      property get and set
#
# NOTE ON VERSION: ScummVM prints "Starting v850 Director game" — it applies the
# detection entry's 850 engine-wide rather than reading each movie's own config
# version, which is 700 for every movie under PIP2DATA/. See
# openspec/changes/director-playback-machine/director-version.md. Expect
# version-gated behaviour in the trace to be D8.5's, not this game's.

set -euo pipefail

MOVIE="${1:?usage: capture_scummvm_trace.sh MOVIE.DXR [frames] [outfile]}"
FRAMES="${2:-few}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${PIPOSH2_DATA:-$HOME/Downloads/piposh2extracted/piposh2-data}"
SCUMMVM="${SCUMMVM:-/Applications/ScummVM.app/Contents/MacOS/scummvm}"
OUTDIR="${TRACE_OUT:-$REPO/.traces}"
OUT="${3:-$OUTDIR/scummvm-${MOVIE%.*}.log}"

[ -x "$SCUMMVM" ] || { echo "no scummvm at $SCUMMVM (brew install --cask scummvm)" >&2; exit 1; }
[ -d "$DATA" ]    || { echo "no extracted data at $DATA (tools/extract_piposh2_data/run.sh)" >&2; exit 1; }

# The movie may sit at the data root (strtgame.dxr) or under PIP2DATA/.
if [ ! -f "$DATA/$MOVIE" ] && [ ! -f "$DATA/PIP2DATA/$MOVIE" ]; then
  echo "no such movie: $MOVIE (looked in $DATA and $DATA/PIP2DATA)" >&2
  exit 1
fi

mkdir -p "$OUTDIR"
CFG="$OUTDIR/scummvm-trace.ini"

# Written fresh each run so a stale start_movie cannot leak between captures.
cat > "$CFG" <<EOF
[scummvm]
versioninfo=trace

[piposh2-trace]
gameid=piposh2
engineid=director
platform=windows
language=he
path=$DATA
start_movie=$MOVIE
EOF

FLAGS="loading,events,lingoexec,lingothe"
if [ "$FRAMES" != "all" ]; then
  FLAGS="$FLAGS,fewframesonly,noloop,fast"
fi

# SDL_AUDIODRIVER=dummy keeps the capture silent and removes audio timing from
# the diff. The video driver is NOT overridden: `dummy` and `offscreen` both fail
# on this build ("Could not load any graphics mode", then "SDL_BlitSurface
# failed: Parameter 'src' is invalid"), so a real window is required. It opens,
# plays, and closes on its own when frames are bounded.
SDL_AUDIODRIVER=dummy "$SCUMMVM" \
  -c "$CFG" -F \
  --debugflags="$FLAGS" --debuglevel=9 \
  piposh2-trace > "$OUT" 2>&1 || true

frames=$(grep -cE '^Score::renderFrame\(\) finished' "$OUT" || true)
chans=$(grep -cE '^CH: ' "$OUT" || true)
echo "$OUT"
echo "  lines           $(wc -l < "$OUT")"
echo "  frames rendered $frames"
echo "  channel records $chans"
if [ "$frames" -eq 0 ]; then
  echo "  WARNING: no frame rendered. If the log says \"Finished playback of movie" >&2
  echo "  'PIPOSH2.EXE'\" then start_movie did not take effect." >&2
  exit 2
fi
