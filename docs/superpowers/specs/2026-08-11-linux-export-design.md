# A Linux target for the tagged release

Design for adding Linux as a fourth leg of the export matrix that already ships
Windows, macOS and Android. Amends
[`2026-08-10-godot-export-ci-design.md`](2026-08-10-godot-export-ci-design.md)
and [`2026-08-11-macos-export-design.md`](2026-08-11-macos-export-design.md)
rather than replacing either.

## Goal

`git push origin v0.2.0` produces a fourth release asset, a zip holding
`GodotDirectorPlayer.x86_64` and its `.pck`, carrying the same six titles and the
piposh-3d embed as the other three.

## The constraint this design was given

**Linux is a leg like the other three, not a new kind of thing.** This was stated
directly when the work was commissioned, and it settled a question that would
otherwise have been the whole design.

The tempting alternative was that Linux is the *only* target whose artifact the
`ubuntu-latest` runner can execute, so its leg could boot the build and turn CI
from "did this export" into "does this run". That capability is real and no other
target can have it. It is also a thing none of the existing legs do, and adding
it here would make one target's leg a different shape from the other three for
reasons that have nothing to do with Linux. It is deliberately not in this
design. If booting the artifact is worth doing, it is worth doing as its own
decision applied consistently, not smuggled in as a side effect of adding a
platform.

## The structure being matched

Read off `release.yml` rather than recalled. Every leg is the same sequence:

1. `Export <Target>`, gated on `matrix.target`, which sets `ASSET`.
2. A target-specific verification step **only where that platform has a failure
   mode the generic checks miss**.
3. `Verify an asset was produced`.
4. `Check asset size`.
5. The upload to the draft release.

Step 2 is the only one that varies, and it varies by how much work the check is:

| target | verification | why that shape |
| --- | --- | --- |
| Windows | none | no silent failure mode identified |
| macOS | `tools/ci/check_macho_signed.py` + test suite | Mach-O needs a real parser; an unsigned slice passes every other check and then will not launch |
| Android | ~10 lines of inline bash (`unzip -l \| grep piposh3d`) | the failure is "a file is missing from an archive" |

**Linux's failure mode is Android's, not macOS's**, so it gets Android's
treatment. With `embed_pck=false` the export emits `GodotDirectorPlayer.x86_64`
and a sibling `GodotDirectorPlayer.pck`; an archive carrying only the first is a
build that starts and finds no engine data. That is a missing archive member.
No new file in `tools/ci/`, and no test suite, because there is no parsing to get
wrong.

**Two members and one mode.** The check reads the archive with `unzip -Z1 -l`
rather than `unzip -l`, because there is a second way this artifact arrives
broken and it is invisible to a plain listing: a `GodotDirectorPlayer.x86_64`
that lost its executable bit is a download the player cannot run and cannot
easily diagnose. `zip` preserves the mode, so this is an assertion about
something that should already be true rather than a fix — which is exactly the
argument for asserting it, since nothing else in the pipeline would notice.
An earlier draft of this design claimed the bit survives and then specified a
check that could not see it.

## What has to change

**`export_presets.cfg`, a new `[preset.4]`.** `platform="Linux"`,
`export_path="build/linux/GodotDirectorPlayer.x86_64"`, `embed_pck=false` and
`texture_format/s3tc_bptc=true` to match Windows exactly, and the same
`include_filter`/`exclude_filter` strings as the other four, copied verbatim.
Copied rather than narrowed for the reason the macOS design gives: the corpus is
what makes the build worth shipping, and `export_presets_check.gd` fails the
build if a path the engine opens is missing from the filter.

**The preset is generated in the editor, not written from memory.** The macOS
design recorded this as a deliberate practice and the reason applies with more
force here: `platform=` was spelled `Linux/X11` in Godot 3 and changed in 4.x, and
`texture_format` needs at least one of `s3tc_bptc`/`etc2_astc` selected or the
export errors. `export_presets_check.gd` inspects only `include_filter`, so a
preset with a wrong platform string or a misspelled option key passes preflight
and fails at export time in CI, which is the most expensive place to find it.

**`.github/workflows/release.yml`.** One matrix entry (`target: linux`,
`preset: Linux`), one export step, one verification step, and the publish gate
below. The export step zips, mirroring Windows: two files have to ship together,
and `zip` is also what carries the executable bit through a GitHub release asset.

**`finalize`'s asset count.** `-lt 3` becomes `-lt 4`, **and** the message
`Expected 3 assets (Windows, macOS, Android)` changes with it. Two edits, and the
second is the one that gets forgotten, leaving a correct gate that lies about
why it fired. The same slip is available one more time in the comment above
`Upload build summary for inspection`, which says "three failing jobs".

**`docs/LINUX.md`, new.** `docs/ANDROID.md` and `docs/MACOS.md` both exist;
Windows has none. Following the structure the other targets set means writing the
Linux one, and it is genuinely thinner than either because Linux asks the player
for no signing ceremony: extract, keep the `.pck` beside the binary, `chmod +x`
if the extractor dropped the mode, run it. It also carries the one thing a player
will otherwise report as a bug — saving does not work from a read-only `.pck` —
which is platform-wide and already recorded in `MACOS.md`.

Not linked from `README.md`, matching what the macOS design decided and for the
same reason: the file has mixed CRLF/CR/LF line endings, so any edit normalises
it and turns a one-line change into a whole-file diff.

## What does not change

**`tools/export_presets_check.gd`.** It enumerates every `[preset.N]` and derives
its required paths from `KeySites` and from the autoloads' own constants, so a
fifth preset comes under the gate with no edit. The macOS design noted this was
the second time that design had paid for itself; this is the third.

**`tools/ci/stamp_version.sh`.** Unlike macOS, which forced an edit here, the
Linux preset carries no version keys at all: the script's seds target Android's
`version/code`/`version/name` and Apple's `application/version`/
`application/short_version`, and Linux has neither pair. Nothing to stamp, no
test-suite growth. The launcher still reports the build, because that reads
`application/config/version` from `project.godot`, which is stamped once for
every target.

**`tools/ci/install_godot.sh`.** The single `export_templates.tpz` it already
fetches carries the Linux templates alongside the others. **Measured, not
assumed**: the central directory of
`Godot_v4.7.1-stable_export_templates.tpz` was read by range request and lists 35
entries including `templates/linux_release.x86_64`. The development machine could
not answer this — its installed template directory holds only `macos.zip` and
`ios.zip`, so checking there would have produced a confident wrong answer.
`templates/linux_release.arm64` is present too, which is noted only so that
"arm64 Linux is out of scope" reads as a choice rather than a limitation.

**The failure-summary step.** Checked rather than assumed, since it was the one
region of `release.yml` not read before this design was written. Its build
listing is `ls -lR build/`, which is target-generic; the only target-specific
block is the APK content filter, guarded by its own `-f` test. A Linux leg needs
no fourth branch there and loses no diagnostics.

**`tools/ci/check_asset_size.sh`.** A Linux zip is a GitHub release asset like
the rest, so the existing 2 GiB cap is the correct limit rather than an
approximation of one.

**No new secret, and no runner change.** Linux needs no signing, no notarization
and no keystore, and `ubuntu-latest` is already the host. This is the only target
that is not cross-compiled: Windows and macOS are both already exported from
Linux in this workflow.

## Two runtime non-changes, checked rather than assumed

**`the platform` already answers correctly.** `scenes/preview_lingo_host.gd:2177`
matches `OS.get_name()` and falls through to `"Windows,32"` for anything that is
not macOS. That is right for Linux and not merely tolerable: a Director title
comparing `the platform` knows only `"Windows,32"` and
`"Macintosh,PowerPC"`, so there is no third answer that leaves a title in a state
it expects. Reporting `"Linux"` would be more honest and would break titles.

**The loose-`games/` affordance works without a special case.**
`director/director_paths.gd:91` resolves
`OS.get_executable_path().get_base_dir().path_join("games")`. On Linux that is a
plain directory beside the binary, so dropping a title in works the way it does
on Windows. It is strictly simpler than macOS, where the same path lands inside
the `.app` bundle.

## Risk

**A fourth leg is a fourth way to block the publish.** `finalize` has
`needs: export`, so any failed leg skips it; `fail-fast: false` lets the
surviving legs upload into the draft, but nothing goes public. Linux is the leg
least likely to fail, having no signing gate and no keystore, but the coupling is
the actual cost of this change and it is larger than the diff.

**Asset size is tight, not newly risky.** Measured in the macOS design: Windows
91.7%, macOS 92.6%, Android 93.9% of the 2 GiB cap. Linux ships the same corpus
plus a template binary within tens of MB of the Windows one, so it lands beside
Windows at the *loose* end of that table. It does not change the standing problem,
which is that the APK is already published at 93.9% and one more title breaks the
release.

## Out of scope

`.deb`, `.AppImage`, Flatpak, Snap, arm64 Linux, and Steam packaging. Also out:
booting the artifact in CI, per the constraint above.

## Testing

1. `godot --headless --path . --script tools/export_presets_check.gd` passes with
   five presets rather than four, and would fail if the new preset's
   `include_filter` were wrong.
2. `git diff export_presets.cfg` after generating the preset shows **only** the
   added `[preset.4]` and `[preset.4.options]` sections. Godot rewrites the file
   wholesale and may reorder or normalise keys across all five presets, so the
   tracked `version/code=1` and `version/name="0.1.0"` are confirmed undisturbed
   before the diff is staged.
3. A `workflow_dispatch` dry run proves the export and the archive check before
   any tag is pushed. The macOS work established that this is the cheap way to
   answer an export question, and that the earlier reasoning treating a test
   publish as expensive was wrong for a corpus that is already public.
4. `bash gate.sh` before landing, **greping the output for `FAIL`**: the script
   exits 0 on a red, and `palette_members` is a standing failure from a
   gitignored fixture.
5. The first real tag confirms the asset size and the four-asset publish gate.
