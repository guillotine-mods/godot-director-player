# Tagged release builds for Windows and Android

Design for a GitHub Actions workflow that exports the player for Windows and
Android on a version tag and publishes both to a GitHub release.

## Goal

`git push origin v0.1.0` produces a public GitHub release on
`guillotine-mods/godot-director-player` carrying two assets: a Windows zip and a
signed APK, each containing all six Director titles and the piposh-3d embed.

## What was decided, and why

**Public release, games bundled.** The six game submodules (`piposh`, `piposh2`,
`piposh-en`, `piposh-ru`, `rating`, `piposh-dream`) are private repositories;
this one is public. Bundling them into a public release asset makes that data a
public download. Raised and accepted as an owner decision. The practical
consequence for this design is that CI cannot use the default `GITHUB_TOKEN` to
clone them, so a PAT is required.

**No macOS target.** Dropped for now. An unsigned arm64 binary will not execute
on Apple Silicon at all, so macOS is not a "just add a preset" job: it needs at
minimum ad-hoc signing, and a clean launch needs a paid Apple Developer account
plus notarization. Revisit when there is an account or demand. Dropping it also
removes the only reason for a runner matrix.

**Tag-push trigger only.** No `pull_request` trigger. This is the security
design, not just a convenience: with no PR event, the PAT and the keystore are
structurally unreachable from a fork PR rather than guarded by a convention
someone can later relax.

**Release keystore from a secret.** A keystore generated fresh per run would give
every release a different signature, and Android refuses to install an update
signed with a different key. Users would have to uninstall first, losing saves.
A stable keystore held as a secret is the only option that preserves in-place
upgrades.

**One fat build rather than per-title builds.** Accepted with a known risk, see
below.

## Known risk: artifact size

GitHub caps a single release asset at 2 GiB. There is no cap on total release
size, asset count (up to 1000 per release) or download bandwidth, so the only
number that matters is the size of the largest single asset.

`games/` is 3.2 GB raw:

| type | raw | sampled zstd ratio |
| --- | --- | --- |
| `.aif` | 1676 MB | 0.50 |
| `.dir` | 955 MB | 0.32 |
| `.cst` | 397 MB | 0.36 |
| other | 175 MB | ~0.5 |

Weighted, that is roughly 1.3 GB compressed, plus the ~269 MB `piposh3d.pck`
and the engine binary, so call it 1.6 GB. That fits, with less headroom than it
first appears.

**But whether the exported pack is compressed at all is unverified.** Godot
stores the `.pck` inside an APK uncompressed in some configurations so it can be
memory-mapped. If that applies here the APK is north of 3.4 GB and cannot be a
release asset. The measurement was not run locally because no export templates
are installed; the first CI run settles it either way.

Mitigation, in order:

1. The workflow fails with an explicit message if either asset exceeds 2 GiB.
   It must not publish a release it cannot attach to.
2. If it does exceed, the fallback is per-title builds. The largest single game
   is 637 MB raw, safe under either compression outcome. This is a supported
   shape, not a workaround: `scenes/launcher/title_list.gd` documents that
   "narrowing `include_filter` is how one title ships instead of six", and the
   launcher hides tiles whose data did not ship.

## Repository changes required

These are part of the work, not prerequisites the user does separately.

**Widen both `include_filter`s.** Today Android has
`include_filter="games/*,director_game.cfg"` and Windows has only
`include_filter="director_game.cfg"`. Because `**/*.import` is gitignored and
game assets load at runtime from source files rather than as imported resources,
`export_filter="all_resources"` does not sweep `games/` in. The current Windows
export therefore ships zero game data.

Both presets need `games/*`, `director_game.cfg` and a pack entry.

An earlier revision of this document claimed the pack entry was missing from
both presets. That was wrong, and the way it was wrong is worth keeping. The
reading it rested on came from the working tree during a session in which
another checkout was actively mutating that file; committed history has carried
`titles/piposh3d.pck` in both presets since `91a84057`. The claim was true of
the bytes on disk at the moment they were read and false of every commit. Read
`git show <rev>:<path>` rather than the working copy when a file's history is
the thing being asserted.

What survives that correction is the Windows gap, which holds at every commit:
Windows Desktop carried `director_game.cfg` and the pack but never `games/*`,
so the Windows export shipped no game data at all.

The pack entry itself is widened from the literal `titles/piposh3d.pck` to the
glob `titles/*.pck`. That is defensive rather than a fix: it costs nothing and
survives a rename or a second embedded title. It is not exercised by any
assertion, because both spellings match the one path that exists.

**Version stamping in `export_presets.cfg`.** `version/code=1` is hardcoded.
Android requires a strictly increasing `versionCode` to install an update, so
without this every release after the first is uninstallable over its
predecessor. CI patches the preset before export: `version/name` from the tag,
`version/code` monotonic from the run number.

**A release keystore.** Generated once locally with `keytool`, never committed
(`.gitignore` already excludes `android/*.keystore` and `*.jks`), stored
base64-encoded as a secret. Losing it means never being able to ship an
installable update again.

## Workflow structure

Single job on `ubuntu-latest`. Both targets export from the same Linux Godot
binary, and the recursive submodule checkout is ~3.8 GB; splitting into two jobs
would pay that cost twice for no parallelism worth having.

Steps in order:

1. **Checkout** with `submodules: recursive` and `token: SUBMODULES_PAT`.
2. **Run the `tools/ci` suites.** Added after this document was first approved.
   The pre-check found that none of the guards this plan builds were exercised
   in CI at all: the tag charset validation, the errexit handling, the
   unreadable-asset path. Placed before the downloads so a broken guard costs
   seconds rather than a 3.8 GB checkout and a 1 GB install.
   `install_godot_test.sh` doubles as the pre-flight for the Godot step, since
   it HEADs the three pinned release assets.
2. **JDK 17** via `actions/setup-java` (temurin). Godot recommends 17
   specifically; higher versions work but 17 is the supported target.
3. **Android SDK** via `android-actions/setup-android`, for `apksigner` and
   `zipalign`. `gradle_build/use_gradle_build=false`, so Godot uses prebuilt
   templates and needs only the signing tools, not a full Gradle build.
4. **Godot 4.7.1-stable**, binary and `.tpz` export templates, downloaded from
   `godotengine/godot-builds` with a checksum check and unpacked to
   `~/.local/share/godot/export_templates/4.7.1.stable/`. Both cached on a
   version key so reruns skip roughly 1 GB of download.

   The version is pinned to match `project.godot` (`config/features` declares
   4.7; the local editor is `4.7.1.stable.official.a13da4feb`). A binary and
   templates that disagree fail the export outright. Fetching directly rather
   than through `barichello/godot-ci` or a setup action keeps the version under
   our control and removes a trust boundary, consistent with how
   `piposh-3d/verify.yml` is written.
5. **Editor settings** written to `~/.config/godot/editor_settings-4.7.tres`
   carrying `export/android/android_sdk_path`. Godot's docs cover the SDK path
   only through the editor GUI; for a headless run the settings file is the
   only channel.
6. **Keystore** decoded from `ANDROID_KEYSTORE_B64` to a file outside the repo,
   then passed via `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
   `GODOT_ANDROID_KEYSTORE_RELEASE_USER` and
   `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. These override the export menu
   values at export time, so no secret is ever written into
   `export_presets.cfg`.
7. **Import** with `godot --headless --path . --import`. A fresh checkout has no
   `.godot`, and without it `class_name` globals do not resolve.
8. **piposh-3d pack.** `titles/piposh-3d` is its own Godot project. Import it,
   then `--export-pack Pack` to produce `titles/piposh3d.pck` (~269 MB per the
   `.gitignore` note). Note the output name has no hyphen: `piposh3d.pck` is
   what `autoload/piposh3d_pack.gd` mounts, while the source submodule is
   `titles/piposh-3d`. Skipping this step does not fail the build: the launcher
   gates the embed tile on `ResourceLoader.exists()`, so the 3D title would
   silently disappear from the release instead.
9. **Export Windows**, `--export-release "Windows Desktop"`.
10. **Export Android**, `--export-release "Android"`. Release rather than debug:
    a debug export enables the remote debugger and is larger.
11. **Package Windows as a zip.** `binary_format/embed_pck=false`, so the EXE
    alone is inert and needs its `.pck` beside it.
12. **Size gate.** Fail if either asset exceeds 2 GiB, naming the actual size.
13. **Publish** via `softprops/action-gh-release`, attaching both assets, with
    the tag as the release name.

No step carries `continue-on-error`. A failed export must not yield a release.

## Secrets

| name | purpose |
| --- | --- |
| `SUBMODULES_PAT` | Fine-grained PAT, contents:read on the six private game repos and `piposh-3d`. The default `GITHUB_TOKEN` cannot read private repos from a public repo's workflow. |
| `ANDROID_KEYSTORE_B64` | Base64 of the release keystore. |
| `ANDROID_KEYSTORE_PASSWORD` | Key password. |
| `ANDROID_KEY_ALIAS` | Key alias. |

## Out of scope

macOS in any form, Play Store publication (this is sideload-only distribution),
and running `gate.sh` as a release gate. The last is a reasonable follow-up but
is a separate concern from producing artifacts.

## Open at merge

**`bash gate.sh` has never been run in full against this branch.** It was
deferred when the game corpora would not clone into the working worktree, on the
understanding it runs before merge. It is the only check in this plan that has
never executed. `gate.sh` itself was modified here — `export_presets_check` was
added to `ALL` — and that registration has only been exercised one harness at a
time. Run it in a checkout carrying the corpora.

**Deferred minors, none blocking.** A vacuous "an unreadable asset is refused"
assertion in `check_asset_size_test.sh`, kept as a cheap sanity check and
labelled as such; a superfluous `chmod` before its cleanup; the bare happy-path
stamp invocation in `stamp_version_test.sh`, where the abort trap now makes a
death loud rather than silent; `export_presets_check.gd` cannot distinguish
`titles/*.pck` from the literal path, which matters only once a second pack
exists; and that harness requires every preset to carry every `games/*` root, so
a legitimate games-beside-the-binary build would fail it.

**`GITHUB_RUN_NUMBER` is not monotonic across a workflow rename.** It is scoped
per workflow file and restarts at 1 if `release.yml` is renamed or recreated. If
that happens, `versionCode` goes backwards and no user can update in place
again — the exact harm the stored keystore exists to prevent. Deferred rather
than redesigned because the obvious alternative is worse: a semver-derived code
collides on `v0.0.1-ci1` and `v0.0.1-ci2`, so a re-run of the acceptance test
could not install over itself. The workflow carries a comment saying it must not
be renamed. That comment is the whole mitigation.

**A GitHub pre-release is public and downloadable.** `draft` and `prerelease`
are orthogonal. `v0.x` tags ship as pre-releases, which keeps them out of
"Latest release" and signals status — it does not gate access. Nothing in this
pipeline withholds an artifact from public download once a run succeeds.

## Verification

The workflow is only proven by running it. A tag on a throwaway version
(`v0.0.1-test`) exercising the full path, including the size gate and the
release attachment, is the acceptance test. The size measurement in the risk
section above is resolved by the first real run, and the result should be
recorded back into this document.
