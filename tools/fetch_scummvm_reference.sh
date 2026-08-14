#!/usr/bin/env bash
#
# Fetch the ScummVM `engines/director` files this port reads as its reference
# implementation, at a pinned revision.
#
# ScummVM is GPL-2.0-or-later. These files are read for the model and cited by
# function; no code is copied into this repository. The download directory is
# git-ignored for that reason — it is a local reading aid, not a vendored
# dependency.
#
# Pinning matters: master moves and line citations rot. A previous review of
# this engine cited `master` and had to be redone from scratch. Cite as
#   ScummVM <file>:<function> @ SCUMMVM_REV
#
# Usage:
#   tools/fetch_scummvm_reference.sh [dest]
#
# Default dest is reference/scummvm/, which .gitignore excludes.

set -euo pipefail

# Pinned ScummVM revision. Committed 2026-08-05.
SCUMMVM_REV="805f259a19d71eb12db1e3b0b9b24c27ee18e8b6"

DEST="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/reference/scummvm}"
BASE="https://raw.githubusercontent.com/scummvm/scummvm/${SCUMMVM_REV}"

# The files that carry the mechanisms this change reproduces. Each line is a
# path under engines/director/ followed by why it is here.
FILES=(
  # Playback machine: frame cycle, channel state, delta application, puppets.
  "score.cpp"                     # Score::update() stage ordering, renderFrame, formatChannelInfo
  "score.h"
  "channel.cpp"                   # Channel state, setAutoPuppet, isDirty, matte/mask handling
  "channel.h"
  "frame.cpp"                     # Frame load, sprite delta decode, tempo/sound/script channels
  "frame.h"
  "sprite.cpp"                    # Sprite record fields and their score encoding
  "sprite.h"
  "movie.cpp"                     # Movie-owned cast and script tables, event queue entry
  "movie.h"
  "window.cpp"                    # _frozenLingoStates, processFrozenScripts, go/play stack
  "window.h"
  "director.cpp"                  # Engine loop, version dispatch
  "director.h"
  "types.h"                       # ScriptType, SpriteType, InkType, event enums
  "events.cpp"                    # Mouse/key event capture and routing into the movie
  "cast.cpp"                      # Cast load, member lookup, script ownership
  "cast.h"
  "graphics.cpp"                  # Compositing and ink application
  "util.cpp"                      # Version helpers (humanVersion etc.)
  "util.h"
  "detection_tables.h"            # The piposh2 detection entry and its declared version

  # Cast members whose behaviour the port already implements natively but whose
  # geometry and mask rules the hit-testing work depends on.
  "castmember/bitmap.cpp"         # Bitmap bbox, regX/regY, matte generation
  "castmember/bitmap.h"
  "castmember/filmloop.cpp"       # Film loop advance and its channel expansion

  # Lingo host surface: dispatch, suspension, properties, builtins.
  "lingo/lingo.cpp"               # Lingo::execute, LingoState freeze/thaw
  "lingo/lingo.h"
  "lingo/lingo-events.cpp"        # Message hierarchy, queueEvent, pass/dontPassEvent
  "lingo/lingo-the.cpp"           # The complete `the <property>` tables
  "lingo/lingo-the.h"
  "lingo/lingo-funcs.cpp"         # func_goto, func_play, func_label, frame navigation
  "lingo/lingo-builtins.cpp"      # b_updateStage, b_puppetSprite and the builtin table
  "lingo/lingo-code.cpp"          # Opcode implementations, property get/set paths
  "lingo/lingo-bytecode.cpp"      # Lscr/Lctx/Lnam layout: addCodeV4, the header and handler offsets
  "lingo/lingo-bytecode.h"        # LingoV4Bytecode and LingoV4TheEntity record shapes
  "lingo/lingo-object.cpp"        # Object property dispatch

  # Trace sources the oracle work reads.
  "debugger.cpp"                  # Console commands incl. the channel dump

  # Digital video. The member's specific block and its playback state machine,
  # then the two files `director/director_avi.gd` reproduces: the RIFF/AVI
  # container walk and the Microsoft RLE expansion.
  "castmember/digitalvideo.cpp"   # Specific block layout, getRegistrationOffset, movieTime

  # Frame transitions. `score.cpp:renderTransition` (above) is only the
  # resolution order -- puppet, then the frame's member, then a cut -- and the
  # port already implements that and the member decode. What is missing is every
  # algorithm behind it: `director/director_transition.gd` names all 52 types and
  # draws none of them, holding the playhead for the authored duration and then
  # cutting. AGENTS.md lists "the transition wipe algorithms" among the calls
  # already made the wrong way, so these are the specification for undoing it.
  "transitions.cpp"               # playTransition: the step loop and all 52 algorithms
  "castmember/transition.cpp"     # The type-14 member's 6-byte specific block
  "castmember/transition.h"       # TransParams field names and the TransitionType enum
)

# The same revision, from outside engines/director/. These three are ScummVM's
# shared video and image code rather than the Director engine's, so they take a
# different prefix and cannot go in the list above.
SHARED=(
  "video/avi_decoder.cpp"         # parseNextChunk, handleStreamHeader, readOldIndex
  "video/avi_decoder.h"
  "image/codecs/msrle.cpp"        # MSRLEDecoder::decode8 -- the whole of MS-RLE
  "image/codecs/msrle.h"
)

mkdir -p "$DEST"
printf '%s\n' "$SCUMMVM_REV" > "$DEST/REVISION"

count=0
for entry in "${FILES[@]}"; do
  rel="${entry%% *}"
  out="$DEST/$rel"
  mkdir -p "$(dirname "$out")"
  if ! curl -fsSL "$BASE/engines/director/$rel" -o "$out"; then
    echo "FAILED: engines/director/$rel at $SCUMMVM_REV" >&2
    exit 1
  fi
  count=$((count + 1))
done

for rel in "${SHARED[@]}"; do
  out="$DEST/$rel"
  mkdir -p "$(dirname "$out")"
  if ! curl -fsSL "$BASE/$rel" -o "$out"; then
    echo "FAILED: $rel at $SCUMMVM_REV" >&2
    exit 1
  fi
  count=$((count + 1))
done

echo "Fetched $count files from scummvm/scummvm@${SCUMMVM_REV:0:12} into $DEST"
