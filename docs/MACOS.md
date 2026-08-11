# Running a macOS build

What the macOS release asset is, and the two things a player has to know that no
other target requires. [`ANDROID.md`](ANDROID.md) is the same document for phones.

The asset is `GodotDirectorPlayer-macOS-<tag>.zip`, holding
`Godot Director Player.app`. Measured on an arm64 machine: it launches, mounts
`piposh3d.pck` and initialises the game globals.

**Universal, and CI refuses to publish it otherwise.** `lipo -archs` reports
`x86_64 arm64`, so it runs natively on both Apple Silicon and Intel with no
Rosetta, and `codesign` confirms both slices are signed. The release workflow runs
`check_macho_signed.py --require arm64,x86_64`, which fails the build if either is
missing. That check exists because a single-architecture binary passes every other
test in the pipeline: the slice that is present is correctly signed, so without
this nothing would notice that half of all Macs got no build.

Universal is also the right choice for the export specifically. Godot's macOS
template ships universal, so `binary_format/architecture="universal"` uses it
as-is, while asking for one architecture would require thinning the binary on a
Linux runner that has no `lipo`.

## macOS will say the app is damaged. It is not.

The build is **ad-hoc signed**: a real code signature, but one with no Apple
Developer certificate behind it, because this project has no paid Apple account.
An ad-hoc signature is what lets the binary execute at all on Apple Silicon,
where a genuinely unsigned binary does not run. What it does not do is satisfy
Gatekeeper.

Measured, not guessed: `codesign -dv` reports `Signature=adhoc` and
`codesign --verify --deep --strict` passes, while `spctl -a -vv` reports
`rejected`. So the signature is valid and Gatekeeper still declines it, which is
exactly the intended state.

The message macOS shows is *"Godot Director Player.app is damaged and can't be
opened. You should move it to the Trash."* This is misleading. The download is
not corrupt. macOS words it that way for any quarantined app it cannot vouch for.

Two ways past it, either is fine:

**Right-click the app and choose Open**, then confirm. This is the per-app
override and it only has to be done once. A plain double-click will not offer it.

**Or clear the quarantine flag directly:**

```sh
xattr -dr com.apple.quarantine "/Applications/Godot Director Player.app"
```

The flag is attached by the browser that downloaded the zip, not by the app, which
is why unzipping with `ditto` or downloading with `curl` sometimes avoids the
prompt entirely.

## Saved games do not work out of the box

The games save by rewriting their own container in place (`saveMovie` into
`HEZSAVE.DIR`, `EGOZSAVE.DIR`, `Saves.dir`). The release bundle carries all six
titles inside a 3.4 GB `.pck` in `Contents/Resources`, and **a `.pck` is read-only
at runtime**, so an in-game save has nowhere to go.

This is not specific to macOS. It is true of the released Windows zip for the same
reason, and of Android because there is no folder beside an APK at all. See
[`ANDROID.md`](ANDROID.md), which explains why shipping the games loose is what
makes saving work.

`director/director_paths.gd` prefers a `games/` folder **beside the executable**
over the packaged copy, testing it by whether it holds a title rather than whether
it exists. On macOS "beside the executable" means inside the bundle, because
`OS.get_executable_path()` points at `Contents/MacOS/`:

```sh
cp -R games "/Applications/Godot Director Player.app/Contents/MacOS/games"
```

Do that once and the titles become ordinary writable folders, so saving behaves as
it does from source. Rebuilds replace the app, so keep the copy somewhere else too.

**Adding files inside the bundle does not break anything**, which is worth stating
because it sounds like it should. Measured: after copying a directory into
`Contents/MacOS/`, `codesign --verify --deep --strict` still passes and the app
still launches. The seal covers `Contents/Resources`, not arbitrary additions
under `Contents/MacOS`.

## Sizes, and why they are worth watching

| | bytes | of the 2 GiB release-asset cap |
|---|---|---|
| the zip | 1,987,623,288 | 92.6% |
| the `.pck` inside it | ~3.4 GB | n/a, compressed into the above |

152 MiB of headroom. GitHub refuses a release asset over 2 GiB outright, and
`tools/ci/check_asset_size.sh` fails the build rather than letting the publish
step discover it. A seventh title, or restoring audio this corpus has not had
transcoded, breaches it. The documented fallback is a narrower `include_filter`
shipping fewer titles; the launcher already hides a title whose data did not ship.
