#!/bin/sh
# Container entrypoint: run the VISE installer under Wine on a virtual display
# and copy the Director casts and movies to /out.
#
# The installer has no unattended switch — its string table offers only the
# interactive "Typical / Compact / Silent Setup" configurations, a language
# dialog and a target-directory dialog — so the GUI is driven with xdotool.
# Every dialog it shows takes the default button, so the drive loop just holds
# Return down on whatever window has focus, and screenshots to /out/_screens so
# a run that stalls can be diagnosed from what was actually on screen rather
# than guessed at.
#
# Usage (inside the container):
#   extract.sh            run the installer and copy the data out
#   extract.sh manual     bring up the display and the installer, then idle,
#                         so `docker exec` can drive it by hand
set -eu

INSTALLER=${INSTALLER:-/installer/piposh2.exe}
OUT=${OUT:-/out}
SCREENS=$OUT/_screens
# Emulated i386 is slow; the install unpacks ~600 MB. An hour is generous.
INSTALL_TIMEOUT=${INSTALL_TIMEOUT:-3600}
MODE=${1:-auto}

log() { echo "[extract] $*"; }

[ -f "$INSTALLER" ] || { log "no installer at $INSTALLER"; exit 2; }
mkdir -p "$OUT" "$SCREENS"

log "starting Xvfb"
Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!
# xdpyinfo is the only honest "is the display up" check; retrying beats sleeping.
i=0
while ! xdpyinfo -display :0 >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && { log "Xvfb never came up"; exit 3; }
    sleep 1
done

log "creating Wine prefix ($(wine --version))"
wineboot -u >/dev/null 2>&1 || { log "wineboot failed — Wine cannot start"; exit 4; }
log "prefix ready"

log "launching installer"
wine "$INSTALLER" >"$OUT/_wine.log" 2>&1 &
WINE_PID=$!

shot() { import -display :0 -window root "$SCREENS/$1.png" 2>/dev/null || true; }

# There is no window manager on the virtual display, so nothing assigns input
# focus and a bare `xdotool key` is delivered to the root window where Wine
# never sees it. Focus each visible window explicitly first; XTEST keystrokes
# then land in the real dialog (unlike `key --window`, which sends a synthetic
# event that Wine ignores).
press_return() {
    for w in $(xdotool search --onlyvisible --name '.' 2>/dev/null); do
        xdotool windowfocus --sync "$w" 2>/dev/null || continue
        xdotool key --clearmodifiers Return 2>/dev/null || true
    done
}

if [ "$MODE" = manual ]; then
    log "manual mode: installer running, display :0 up. Idling."
    n=0
    while kill -0 "$WINE_PID" 2>/dev/null; do
        n=$((n + 1))
        shot "$(printf '%04d' "$n")"
        sleep 15
    done
    exit 0
fi

log "driving the installer GUI"
elapsed=0
n=0
prev_screen=
prev_size=
while [ "$elapsed" -lt "$INSTALL_TIMEOUT" ]; do
    # The wine launcher exits once the installer's own process is gone.
    kill -0 "$WINE_PID" 2>/dev/null || { log "installer process exited"; break; }
    n=$((n + 1))
    name=$(printf '%04d' "$n")
    shot "$name"

    # Only press Return when the installer is genuinely waiting for input.
    # This matters because the copy-progress dialog's one button is Cancel and
    # it holds the focus rectangle, so a keypress on a timer would eventually
    # abort the install. Two independent idle signals have to agree: the screen
    # has not changed, and nothing new has been written under drive_c. The
    # second is what makes this safe — during the copy the tree grows steadily
    # even if a slow file leaves the screen looking static.
    screen=$(md5sum "$SCREENS/$name.png" 2>/dev/null | cut -d' ' -f1)
    size=$(du -sk "$WINEPREFIX/drive_c" 2>/dev/null | cut -f1)
    if [ -n "$prev_screen" ] \
        && [ "$screen" = "$prev_screen" ] \
        && [ "$size" = "$prev_size" ]; then
        press_return
    fi
    prev_screen=$screen
    prev_size=$size

    sleep 5
    elapsed=$((elapsed + 5))
done
shot final

if [ "$elapsed" -ge "$INSTALL_TIMEOUT" ]; then
    log "timed out after ${INSTALL_TIMEOUT}s — copying whatever landed"
fi

# Do not assume C:\Piposh2: find the tree that actually holds the movies.
# .EXE is included for the game projector: ScummVM's detection entry keys on
# PIPOSH2.EXE (5665996 bytes) as well as PIP2DATA/AIR1.DXR, so an extraction
# without it does not identify as a target. That projector is a different file
# from the 328 MB VISE self-installer that shares its name.
log "collecting casts, movies and the projector"

# Locate the install by the directory the game data actually landed in rather
# than hardcoding C:\Piposh2. Copying from the game root (not from drive_c)
# keeps Wine's own tree out of the result — that matters once .EXE is in the
# filter, or the sweep also picks up Wine's builtin programs under
# "Program Files", whose spaces would break the copy loop besides.
data_dir=$(find "$WINEPREFIX/drive_c" -type d -iname PIP2DATA -print 2>/dev/null | head -1)
if [ -n "$data_dir" ]; then
    game_root=$(dirname "$data_dir")
else
    log "no PIP2DATA directory — the install did not produce the game tree"
    exit 5
fi
log "game root: $game_root"

# Newline-separated rather than `for f in $(find ...)`: word splitting on an
# unquoted command substitution breaks any path containing a space.
cd "$game_root"
find . -type f \
    \( -iname '*.DXR' -o -iname '*.CXT' -o -iname '*.CST' -o -iname '*.DIR' \
       -o -iname '*.EXE' \) |
while IFS= read -r f; do
    rel=${f#./}
    mkdir -p "$OUT/$(dirname "$rel")"
    cp -f "$f" "$OUT/$rel"
done

# Counted from the result, because the loop above runs in a pipeline subshell
# and a counter incremented inside it would not survive.
found=$(find "$OUT" -type f \
    \( -iname '*.DXR' -o -iname '*.CXT' -o -iname '*.CST' -o -iname '*.DIR' \
       -o -iname '*.EXE' \) | wc -l)
log "copied $found files to $OUT"
kill "$XVFB_PID" 2>/dev/null || true
[ "$found" -gt 0 ] || exit 5

# Verify the two files ScummVM's detection entry keys on. They are hashed by
# DIFFERENT rules, and applying the wrong one reports a perfectly good
# extraction as broken — which is exactly what happened during this tool's
# development, in both directions. detection_tables.h states which is which by
# prefix: "f:" hashes the FIRST 5000 bytes, "t:" hashes the LAST 5000.
#
#   piposh2.exe        t:9d33c0d6... 5665996   -> tail
#   PIP2DATA/AIR1.DXR  f:cc6c9bb1... 2119111   -> head
#
# A full-file md5 matches neither and is never the right check. For reference,
# the full-file values are ccc1faae... and 909a55d5...; if you see one of those
# you are hashing the whole file.
#
# The projector's hash is not unique to this game — piposh1 carries the same
# t: hash at the same size, so it is a shared launcher stub. AIR1.DXR and the
# filename are what identify piposh2.
detect_fail=0

check_key() {
    rel=$1
    form=$2
    want_md5=$3
    want_size=$4
    path=$OUT/$rel

    if [ ! -f "$path" ]; then
        log "DETECT  $rel: MISSING"
        detect_fail=$((detect_fail + 1))
        return
    fi

    size=$(wc -c < "$path" | tr -d ' ')
    case $form in
        head) got=$(head -c 5000 "$path" | md5sum | cut -d' ' -f1) ;;
        tail) got=$(tail -c 5000 "$path" | md5sum | cut -d' ' -f1) ;;
    esac

    if [ "$size" = "$want_size" ] && [ "$got" = "$want_md5" ]; then
        log "DETECT  $rel OK (size $size, md5 of $form 5000 bytes $got)"
    else
        log "DETECT  $rel FAILED"
        log "        size $size, expected $want_size"
        log "        md5 of the $form 5000 bytes $got"
        log "        expected                     $want_md5"
        log "        (checked the '$form' form, per this file's detection"
        log "         prefix; a full-file md5 would not match and is not the"
        log "         right check)"
        detect_fail=$((detect_fail + 1))
    fi
}

check_key PIPOSH2.EXE       tail 9d33c0d6a4cfb70c33f87f6e8a1f23fd 5665996
check_key PIP2DATA/AIR1.DXR head cc6c9bb1acf76a0697a30d626e89543c 2119111

if [ "$detect_fail" -gt 0 ]; then
    log "$detect_fail of 2 ScummVM detection keys did not verify"
    exit 6
fi
log "both ScummVM detection keys verify"
