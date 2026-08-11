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
build that starts and finds no engine data. That is a missing archive member,
which `unzip -l` answers. No new file in `tools/ci/`, and no test suite, because
there is no parsing to get wrong.

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
why it fired.

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
fetches carries the Linux templates alongside the others.

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
2. A `workflow_dispatch` dry run proves the export and the archive check before
   any tag is pushed. The macOS work established that this is the cheap way to
   answer an export question, and that the earlier reasoning treating a test
   publish as expensive was wrong for a corpus that is already public.
3. `bash gate.sh` before landing, **greping the output for `FAIL`**: the script
   exits 0 on a red, and `palette_members` is a standing failure from a
   gitignored fixture.
4. The first real tag confirms the asset size and the four-asset publish gate.
