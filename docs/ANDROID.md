# Android

## What ships

One **game** per APK, and the game is chosen by the export preset's
`include_filter` — not by anything in the code.

```
include_filter="games/piposh2/*,director_game.cfg"
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

To ship a different title, change the game in that filter *and* `root` in
`director_game.cfg`, which must agree.

`reference/` is excluded deliberately: it is the ScummVM source we read for
behaviour and it has no business inside a binary we hand out. `saves/` and
`.snapshots/` are excluded because they are somebody's session.

## Why one game and not six

| root | size |
|---|---|
| `piposh-dream` | 373 MB |
| `rating` | 417 MB |
| `piposh2` | 561 MB |
| `piposh-ru` | 617 MB |
| `piposh` | 637 MB |
| `piposh-en` | 637 MB |
| **all six** | **3.2 GB** |

Sideloading one of these is fine — `adb install` has no practical ceiling at
these sizes, and the APK is a plain zip. Six in one package is not: it would be a
3.2 GB install, and Google Play caps an AAB base module at 200 MB regardless, so
a store build of even one title needs asset packs or a first-run download.

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
