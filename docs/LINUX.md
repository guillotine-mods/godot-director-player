# Running a Linux build

What the Linux release asset is, and the two things a player has to know.
[`ANDROID.md`](ANDROID.md) and [`MACOS.md`](MACOS.md) are the same document for
phones and for Macs.

The asset is `GodotDirectorPlayer-Linux-<tag>.zip`, holding
`GodotDirectorPlayer.x86_64` and `GodotDirectorPlayer.pck`. x86-64 only; there is
no arm64 build, though the Godot templates carry one if it is ever wanted.

## The two files travel together

`binary_format/embed_pck=false`, so the executable on its own is inert: it starts
and finds no engine data. Keep the `.pck` in the same directory as the binary and
keep its name matching. This is the same arrangement as the Windows zip.

```sh
unzip GodotDirectorPlayer-Linux-v0.2.0.zip -d godot-director-player
cd godot-director-player
./GodotDirectorPlayer.x86_64
```

## If it will not run

The zip records the executable bit, and CI refuses to publish an asset where it
is missing, so the usual cause is an extractor that dropped it rather than a bad
build:

```sh
chmod +x GodotDirectorPlayer.x86_64
```

Nothing else is required. There is no signing, no quarantine flag and no
Gatekeeper equivalent, which is why this document is short.

## Saved games do not work out of the box

The games save by rewriting their own container in place (`saveMovie` into
`HEZSAVE.DIR`, `EGOZSAVE.DIR`, `Saves.dir`). The release carries all six titles
inside the `.pck`, and **a `.pck` is read-only at runtime**, so an in-game save has
nowhere to go.

This is not specific to Linux. It is true of the released Windows zip and the macOS
bundle for the same reason, and of Android because there is no folder beside an APK
at all. See [`ANDROID.md`](ANDROID.md), which explains why shipping the games loose
is what makes saving work.

`director/director_paths.gd` prefers a `games/` folder **beside the executable**
over the packaged copy, testing it by whether it holds a title rather than whether
it exists. On Linux "beside the executable" is an ordinary directory, with none of
the bundle-interior complication macOS has:

```sh
cp -R games ./games
```

Do that once and the titles become ordinary writable folders, so saving behaves as
it does from source.
