# A macOS target for the tagged release

Design for adding macOS to the release workflow that already ships Windows and
Android. Reopens the "No macOS target" decision in
[`2026-08-10-godot-export-ci-design.md`](2026-08-10-godot-export-ci-design.md),
which this document amends rather than replaces.

## Goal

`git push origin v0.2.0` produces a third release asset, a zip containing
`GodotDirectorPlayer.app`, which launches on both Apple Silicon and Intel Macs
and carries the same six titles and the piposh-3d embed as the other two.

## Why the earlier decision is being reopened

The earlier doc dropped macOS on this reasoning: an unsigned arm64 binary will
not execute on Apple Silicon at all, so macOS needs at minimum ad-hoc signing,
and a clean launch needs a paid Apple Developer account plus notarization.

Both ends of that are right. What it skipped is that **ad-hoc signing is not the
same kind of problem as notarization.** Godot's macOS exporter has a built-in
ad-hoc codesign mode that requires no Apple account, no certificate, no keychain
and, we believe, no macOS host. That places the real choice between three
outcomes rather than two:

| signing | account needed | first launch |
| --- | --- | --- |
| none | no | refuses to execute on Apple Silicon |
| ad-hoc | no | runs, after the player clears quarantine once |
| Developer ID + notarized | yes, $99/yr | double-click, nothing asked |

The middle row is new information relative to the earlier decision, and it is
what this design builds. The quarantine step is one right-click Open, or
`xattr -dr com.apple.quarantine`, and it is the same class of friction an
unsigned APK already costs an Android sideloader. That is the whole argument for
it fitting here: this project distributes by sideload already, so ad-hoc does not
introduce a new posture, it matches the existing one.

## What was decided, and why

**Ad-hoc, not notarized.** Per above. Revisit if a paid account ever exists.

**Universal binary, not arm64.** `binary_format/architecture="universal"` costs
tens of megabytes on an asset already over a gigabyte, and arm64-only would
strand every Intel Mac for no measurable saving.

**A zip, not a `.dmg`.** Godot can only produce a `.dmg` on a macOS host, and the
whole point of the ad-hoc route is that the export stays on the Linux job.
Windows already ships as a zip, so this is also the consistent choice.

**Exported from the existing `ubuntu-latest` job.** `install_godot.sh` fetches a
single `export_templates.tpz` that carries `macos.zip` alongside the Android and
Windows templates, and Windows is already cross-exported from Linux in this
workflow, so no matrix and no second runner. This is the clause that depends on
ad-hoc signing working cross-host. See "What is unverified" below.

**The same `include_filter` as the other three presets.** `games/*`,
`director_game.cfg`, `data/*.json`, `titles/*.pck`. Copied verbatim rather than
narrowed: the corpus is what makes the build worth shipping, and
`export_presets_check.gd` will fail the build if a path the engine opens is
missing from it.

**No change to `export_presets_check.gd`.** It enumerates every `[preset.N]`
section and derives its required paths from `KeySites` and from the autoloads'
own constants, so a third preset comes under the gate with no edit. This is the
second time that design has paid for itself and it is worth saying so.

**No change to `check_asset_size.sh`.** A macOS zip is a GitHub release asset
like the others, so the existing 2 GiB cap is the correct limit, not an
approximation of one.

## What has to change

**`tools/ci/stamp_version.sh`.** It seds `version/code` and `version/name`, which
are Android preset keys. The macOS preset carries `application/version` and
`application/short_version` instead, so without this every macOS build reports
the same version forever, which is the same class of bug the script was written
to prevent on Android. `stamp_version_test.sh` grows with it. The tag charset
validation stays exactly as it is: a tag carrying `&` or `|` has broken this
script before and is still refused rather than escaped.

**`.github/workflows/release.yml`.** One export step, one more argument to the
size check, one more line under `files:`. The step goes after `Import` and after
`Verify the export presets`, like the other two exports.

**`docs/MACOS.md`, new.** The quarantine step needs writing down, alongside
`docs/ANDROID.md` which is the same document for phones rather than in `README.md`.
Gatekeeper's message for an ad-hoc binary says the app "is damaged and can't be
opened", which is actively misleading, and a player who hits it with no
instructions will reasonably conclude the download is corrupt.

`README.md` gets no link added, deliberately. It has mixed CRLF/CR/LF line endings,
so any edit normalises the whole file and turns a one-line change into a
whole-file diff. Left for whoever is willing to take that diff on purpose.

**`tools/ci/check_macho_signed.py`, new, plus its test suite.** See "What is still
unverified" for why a signature check has to exist at all, and why it cannot be
`codesign`.

**A `workflow_dispatch` trigger, and the publish step gated behind a tag.** Added
for one reason: the only way to answer the cross-host signing question was
otherwise to publish a real release, which makes six private corpora a public
download. That is far too heavy a price for finding out whether an export works,
and it is not a price that can be refunded.

This does not weaken the security argument the tag-only trigger was making. The
thing that argument protects against is a **fork pull request** reaching the PAT
and the keystore, and the absence of a `pull_request` trigger is what prevents it.
`workflow_dispatch` can only be started by somebody who already has write access,
so it grants nobody anything they did not already hold. A `pull_request` trigger
must still never be added.

The publish step is gated on `startsWith(github.ref, 'refs/tags/')` rather than on
`github.event_name != 'workflow_dispatch'`. A dispatch can be run against a tag as
well as a branch, and the honest question is "is this a tag", not "how was this
started". The event-name form would refuse to publish a dispatch run against a
genuine tag while presenting itself as a safety check.

**One validated version string, `RELEASE_NAME`.** Previously each filename
expanded `$GITHUB_REF_NAME` independently. With two possible sources, that would
let the stamped version and the asset filenames disagree. It is now resolved once
and validated against the same charset `stamp_version.sh` enforces, which also
closes a `$GITHUB_ENV` injection path: both sources require write access, so
neither is untrusted in the fork sense, but a value carrying a newline could
otherwise define arbitrary environment variables for every later step. Tested
against seven inputs including that newline case, a `;touch`, and both-empty.

## What was measured

Exported locally on the development Mac, which is arm64 and runs the same pinned
`4.7.1.stable` the workflow installs. All of the following is observed output, not
inference.

**The export succeeds and the preset is accepted.** Exit 0. The four autoload
errors and the `DRILL.WAV` import error in the log are pre-existing and unrelated
(the piposh3d pack autoloads, and an AIFF carrying a `.WAV` extension).

**The binary is universal and ad-hoc signed.** `lipo -archs` reports
`x86_64 arm64`. `codesign -dv` reports `Signature=adhoc`,
`flags=0x10002(adhoc,runtime)`, `Identifier=com.guillotinemods.godotdirectorplayer`,
and `TeamIdentifier=not set`. `codesign --verify --deep --strict` passes.

**It launches on Apple Silicon.** This was the premise the whole design rested on.
The engine boots, `piposh3d.pck` mounts and the game globals initialise.

**Gatekeeper rejects it,** as expected: `spctl -a -vv` reports `rejected`. So the
quarantine step is real and [`docs/MACOS.md`](../../MACOS.md) has to exist. The
wording macOS uses, "is damaged and can't be opened", is misleading enough on its
own to justify that document.

**The zip is 1,987,623,288 bytes: 92.6% of GitHub's 2 GiB release-asset cap,**
with 152 MiB spare. The `.pck` inside the bundle is 3.4 GB, so the zip is doing
real compression. This is the tightest of the three assets by a wide margin and
the most likely thing to break a future release. It is not a reason to change the
design, but it is a reason not to add a title without re-measuring.

**Adding files inside the bundle is safe.** Relevant because
`director/director_paths.gd` prefers a `games/` folder beside the executable, and
on macOS that means inside the bundle. After copying a directory into
`Contents/MacOS/`, `codesign --verify --deep --strict` still passes and the app
still launches. So the desktop save affordance does translate to macOS, by a
non-obvious path.

**The preset's option keys were not written from memory.** A minimal preset was
authored and the export was run so Godot's own behaviour would name what it wanted,
rather than hand-copying an option block from recollection into a file that looks
plausible and silently defaults anything misspelled.

## What is still unverified

**That ad-hoc signing works when the exporter runs on Linux.** Everything above
was measured exporting *from a Mac*, which does not settle the cross-host
question. The mode is implemented inside Godot rather than by shelling out to
Apple's `codesign`, which is the reason to expect host independence, but that
remains an inference. If it is wrong, the "no matrix" decision collapses and
macOS needs its own `macos-latest` job, with the unmeasured runner disk budget
that implies against a 3.2 GB corpus.

`tools/ci/check_macho_signed.py` exists so that this fails loudly rather than
silently: an unsigned export would otherwise produce a green run and a build that
cannot launch. It parses the Mach-O load commands, checks every slice of the
universal binary, and needs no Mac-only tooling. On a developer's Mac its test
suite additionally cross-checks its verdict against `codesign`, and the two agree
on the real export.

**In-game saving does not work in the released bundle,** because the games ride
inside a read-only `.pck`. This is pre-existing and platform-wide rather than
something macOS introduces: the released Windows zip has the same property for
the same reason. Recorded here because it was discovered while writing the macOS
instructions, and documented in `docs/MACOS.md` with the workaround. Fixing it
properly is out of scope for this design.

## The launcher shows the build

Added on request, and it changes where the version has to live. All five preset
keys above are read at **build** time and are invisible to the running game:
nothing in `director/` or `scenes/` can ask what an Android `versionName` was. So
`application/config/version` in `project.godot` is stamped too, and
`scenes/launcher/launcher.gd` reads it through `ProjectSettings.get_setting`.

Stamped as `<name>+<run number>`, semver's build-metadata spelling. The name alone
cannot separate two builds of one tag, and the run number maps to a workflow run,
so `0.2.0+41` in a screenshot identifies the exact binary. The tracked value is
`0.0.0-dev` so a run from source never reads as a release, and a missing or empty
setting renders `dev` rather than leaving `גרסה  ·`, which would look like a
rendering fault rather than an unstamped build.

**No new node.** The launcher already had a footer `Build` label reporting the
*engine* version and the corpus counts, so the app version is prepended to it.
That keeps `launcher.tscn`, the focus map and `launcher_surface`'s node-name
assertions untouched. Verified by instantiating the real scene: it renders

```
גרסה 0.0.0-dev · Godot 4.7.1-stable (official) · 5 משחקים, 7 ספריות על הדיסק
```

and `גרסה 0.2.0+41 · ...` against a stamped `project.godot`.

`stamp_version.sh` takes the project file as a fourth argument, defaulting to
`project.godot`. Every call in its test suite passes a fixture explicitly, because
a three-argument call from inside the repo would stamp the working tree, which is
a test suite quietly editing the project it is testing.

## iOS: a preset, and deliberately no CI job

An iOS preset is added. No workflow step uses it, and that is not an oversight.

**iOS cannot be built in this pipeline at all**, and the blocker is not the runner.
Free Personal Team signing needs interactive Apple ID sign-in through Xcode and
issues a certificate valid for 7 days; there is no secret that substitutes for it
and nothing to automate. Automated iOS signing requires the paid account's
distribution certificate and provisioning profile. A `macos-latest` job could
therefore only produce an unsigned artifact nobody can install, in exchange for
reintroducing the runner matrix this design avoids.

The preset exists anyway for one reason worth the two dozen lines: it comes under
`export_presets_check.gd` immediately, so the include-filter mistake that silently
ships a title with no data is caught for iOS before anyone attempts a device build.
That harness is the only thing standing between a wrong filter and a build that
looks fine and has no games in it. The preset also picks up version stamping for
free, since it carries the same two key names as macOS.

It is **untested**: there is no Xcode on the development machine, so nothing here
has run an iOS export. Treat the option values as a starting point, not as
verified.

## Out of scope

**iOS, for now, but not for the reason previously given.** An earlier note in
this session claimed every iOS install path needs an enrolled account. That is
wrong and is corrected here: a **free** Apple ID gets a Personal Team
provisioning profile that signs for devices you own. The $99 enrollment buys
TestFlight, the App Store, and distribution to other people.

What rules iOS out of *this* design is not the account, it is the **7-day
expiry** on a free certificate. The installed app stops launching after a week
until it is re-signed, so an IPA cannot be a release asset in any useful sense.
iOS is therefore agreed as a separate, local-only development capability to be
built after macOS lands, never wired into `release.yml`. It additionally needs
Xcode, which is not installed on the development machine, and which costs roughly
16 to 20 GB against 39 GB free.

Truly self-signed or random-key iOS signing does not work at all: iOS requires a
signature chaining to an Apple-issued certificate plus a profile naming the
device's UDID. There is no iOS equivalent of ad-hoc.

**Also out:** notarization, `.dmg`, the Mac App Store, and Play Store
publication, all unchanged from the earlier doc.

## Testing

1. The local export launches on arm64. This is the gate on the whole design.
2. `godot --headless --path . --script tools/export_presets_check.gd` passes with
   three presets rather than two, and would fail if the new preset's
   `include_filter` were wrong.
3. `bash tools/ci/stamp_version_test.sh` covers the two new macOS keys, including
   that a tag outside `[A-Za-z0-9._+-]` is still refused.
4. `bash gate.sh` before landing. The earlier branch waived it deliberately and
   recorded why; that waiver was specific to a branch touching no engine code and
   is not inherited.
5. The first real tag confirms the cross-host signing question and records the
   asset size.
