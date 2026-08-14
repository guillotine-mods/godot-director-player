# Builds

Two targets, two layouts, and the difference is not cosmetic.

| | pck carries the games? | where the games are |
|---|---|---|
| `build/pc/` | no | loose in `build/pc/games/` |
| `build/android/` | yes | inside the APK |

**Desktop ships them loose on purpose.** The pck is ~1.7 MB and the titles sit
beside the binary, which buys three things: a title can be added or removed
without a rebuild, the download is not one 3.4 GB file that must be replaced
whole, and -- the one that matters -- the games can **save**. These games save by
rewriting their own container in place (`saveMovie` into `HEZSAVE.DIR`,
`EGOZSAVE.DIR`, `Saves.dir`), and a pck is read-only at runtime. Loose on disk
they behave exactly as they do from source.

Copy `games/` into `build/pc/` **once**. Rebuilds replace only the executable and
the pck, so a tester's saved games survive them.

**Android cannot do this** -- there is no folder beside an APK -- so its games
ride inside the package and are read-only there. Making them writable means
copying to `user://` on first run; that is filed on the board and is why in-game
saving does not work on a phone yet (see below).

## The trap in `res://`, if this ever needs touching

In an **exported** build, `res://games` answers `dir_exists_absolute` true *and*
lists loose subdirectories through `get_directories()`, while `get_files()`
inside one of them returns nothing. So both obvious tests -- "does it exist", and
"does it contain a title" -- choose the packaged branch and the container index
comes back empty, which surfaces as `no such container` with no list attached.
`DirectorPaths.games_dir()` therefore branches on `OS.has_feature("editor")`:
the editor and every `--script` harness keep `res://games` unchanged, and only a
real export looks beside the binary. `KeySites.roots()` asks the same function,
so the launcher can never list a title the engine cannot open.

# Android

## What ships

**All six titles, inside the package**, chosen by the export preset's
`include_filter` and not by anything in the code:

```
include_filter="games/*,director_game.cfg"
```

Two things about that line, because both were wrong before it and neither is
obvious:

- **`games/` has to be named explicitly.** `.dir`, `.cst` and the sound files are
  not Godot resources, so `export_filter="all_resources"` does not see them. The
  filter used to read `data/*.json`, which was the *retired* renderer's
  pre-extracted model — a directory that no longer exists — so the APK shipped
  with no game data at all and this document described packaging something the
  engine stopped using.
- **`director_game.cfg` has to be named too**, for the same reason: it is a
  `.cfg`, nothing imports it, and the boot chain reads it first
  (`DirectorPaths.CONFIG_PATH`). Without it the player opens nothing.

To ship one title instead of six, narrow that filter to `games/<name>/*`. The
launcher lists whatever is present, so nothing else has to change.

`reference/` is excluded deliberately: it is the ScummVM source we read for
behaviour and it has no business inside a binary we hand out. `saves/` and
`.snapshots/` are excluded because they are somebody's session.

## What an APK does not get: video

**No video decoding, on any device.** The optional decoder GDExtension
(`docs/DIGITAL_VIDEO.md` §8) is the only thing that could provide it, and
EIRTeam.FFmpeg 1.1.4 **ships no Android binary** — its `.gdextension` declares
`android.template_{debug,release}.arm64` and the release archive contains
`win64` and `linux64` only.

`addons/*` is therefore in this preset's `exclude_filter`, and that line is not
cosmetic. Measured with it removed: the export **succeeds**, exit 0, after seven
`ERROR: Can't open file from path 'res://addons/ffmpeg/android/…'` lines — and
the APK ships **seven zero-byte `.so` files** in `lib/arm64-v8a/`
(`libgdffmpeg.android.template_debug.arm64.so`, `libavcodec.so`,
`libavfilter.so`, `libavformat.so`, `libavutil.so`, `libswresample.so`,
`libswscale.so`) plus `assets/addons/ffmpeg/ffmpeg.gdextension` naming them.
Godot's exporter writes an empty entry when it cannot read the source file rather
than skipping it. With the exclusion in place: zero errors, and `lib/arm64-v8a/`
holds only Godot's own `libc++_shared.so` and `libgodot_android.so`.

**If such an APK ran anyway it would not crash.** A GDExtension whose library is
missing fails at `GDExtensionManager::load_extensions`, which continues past it:
three `ERROR` lines in logcat, then the engine starts normally, the adapter's
`ClassDB.class_exists` gate answers false, and the video path falls back exactly
as it does with no addon at all. Measured on Windows by pointing the
`.gdextension` at an absent library — `tools/video_plugin.gd` passed its entire
absent-case branch and exited 0.

**Not measured**: whether Android's package installer accepts an APK containing
zero-byte files under `lib/`. No device was attached. It is not a question worth
answering, because the exclusion means such an APK is never built.

The six shipped titles contain no video members at all, so none of this costs a
title anything. The exclusion comes out the day EIRTeam ships an `android/`
directory, in the same commit that fetches it.

## Size

3.2 GB of containers compress to a **1.74 GB APK** — the game data packs at
roughly 0.46, and the engine adds ~100 MB. One title alone is 363 MB.

Sideloading that is fine: `adb install` has no practical ceiling here and an APK
is a plain zip. Two practical notes — installing needs room for the APK *and* its
unpacked copy, so budget 3-4 GB free rather than 1.7, and use `adb install -r` so
a reinstall does not fail against the existing signature.

The store is the constraint, not the device: Google Play caps an AAB base module
at 200 MB, so **any** Play build needs asset packs or a first-run download, even
for a single title.

## Saving does not work yet

**The games save by rewriting their own container in place.** `saveMovie` writes
the `.dir` back to disk — `HEZSAVE.DIR` in Piposh 2, `EGOZSAVE.DIR` in Rating,
`Saves.dir` in Dream are the games' own save files, not ours. Inside an APK
`res://` is read-only, so every one of those writes fails.

What it needs, in the order it has to happen:

1. On first run, copy the containers a game writes into `user://`. Which ones can
   be derived rather than listed — a container that carries a `saveMovie` site is
   one, and `tools/save_movie.gd` already finds field-carrying containers.
2. `DirectorPaths` resolves *writes* to the `user://` copy and reads to whichever
   exists, so a saved game survives and an unsaved one still opens from the APK.
3. `MovieSave.writes_allowed` currently answers "yes" whenever the process is not
   headless, which on Android means yes — and then the write fails at the
   filesystem. It should refuse or redirect when the target is not writable, the
   same way it refuses a headless probe.

The JSON quick-save layer (`save_files.gd`) already falls back from `res://saves`
to `user://saves`, so **that** half works. It is the in-game save the movies do
themselves that does not.

## Unverified

The audio index walks directories with `DirAccess` (`autoload/audio_director.gd`)
over files that mostly have **no extension** — Piposh Dream ships 1,711
extensionless AIFFs against 187 named ones. `DirAccess` can list PCK contents,
but extensionless files inside a PCK are exactly the shape that tends to break,
and it has never been run in an exported build. Check it on device before
believing the sound works.

## Build

Submodules first — `games/` is six private submodules and an APK built without
them contains no game:

```bash
git submodule update --init --recursive
```

Then:

```powershell
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
godot_console --path <checkout> --headless --export-debug Android <checkout>\build\GodotDirectorPlayer.apk
```

One-shot install: `.\scripts\install_android.ps1`

- Package: `com.guillotinemods.godotdirectorplayer`, arm64-v8a only
- Export templates: `4.7.1.stable`; debug keystore: Godot default or `android/debug.keystore`
- Editor Settings → Export → Android: JDK 17 and Android SDK paths

## Phone setup

1. Developer options (tap Build number seven times)
2. USB debugging on
3. USB mode **File Transfer / MTP**, not Charge only
4. Accept the **Allow USB debugging?** dialog

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
```

You want `device`, not `unauthorized` or empty.
