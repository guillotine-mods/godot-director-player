# Running the gate in CI, nightly, on macOS and Windows

## Goal

`bash gate.sh` is the authority on whether this port works, and until now it has
only ever run on one developer's machine, by hand, when somebody remembered. Run
it nightly on the two platforms development happens on, and make a red suite fail
the build.

## The constraint this design was given

**A red gate fails CI, whether or not the red is new.** That was an explicit
decision, taken against the alternative in the first draft of this document, and
it is what removed most of that draft.

The alternative was a recorded baseline: a file of expected statuses that CI
diffs against, so a known red stays green and only a *change* fails. It was
rejected, and `gate.sh`'s own header (lines 2-6) is the argument against it:

> Every step must reproduce the recorded pass/fail SET, which is **every entry in
> ALL passing and none failing** [...] There is no expected failure any more, so
> any red is a regression and needs no triage against a list of excuses.

A baseline file is that list of excuses. Building one would have re-created,
as a tracked artifact, the thing the header records having escaped from. The
simpler design is also the one the codebase already asked for.

The cost was accepted rather than avoided: two entries were red when this was
written, so the nightly would have been red from its first run. Both were
resolved before it shipped, by different means and only one of them a fix — see
the green-suite section below.

## What the exit code has to count

`gate.sh` prints five statuses, not two, and the loop at lines 207-240 produces
each from a different branch:

| Status | Branch | Meaning |
|---|---|---|
| `PASS` | last `PASS`/`FAIL` line, first four chars | the harness asserted and agreed |
| `FAIL` | same | the harness asserted and disagreed |
| `TIMEOUT` | exit 124 from `gate_run_capped` | hit the ceiling, usually a hang |
| `EMPTY` | `(0 checks` in the result line | passed over an empty set |
| `ERROR` | no `PASS`/`FAIL` line at all | died before it could report |

All four non-`PASS` statuses must fail the run. `EMPTY` especially: it is the
"passing with 0 checks" case that `gate.sh`'s own comment says four harnesses
have silently occupied, and an exit code that counted only `FAIL` would let a
dark harness read as clean — the exact failure the status exists to catch.

## What has to change

### 1. `gate.sh` exits nonzero when any entry does not pass

A counter incremented in each of the four non-`PASS` branches, and a summary line
plus `exit 1` after the loop. Roughly twelve lines.

Nothing scripted calls `gate.sh` today — verified across `*.md`, `*.sh` and
`*.yml`; every reference is prose in `README.md` and `AGENTS.md` or a comment
inside the gate scripts themselves. So no caller can break on the new exit code.

`exit 2` is already taken, by the lock-contention refusal at line 107. Reds take
`exit 1`, which keeps the two distinguishable. The `EXIT` trap that releases the
lock fires on either.

### 2. `tools/ci/install_godot.sh` learns macOS and Windows

Its header currently says "Linux-only. `sha512sum` is GNU; the macOS spelling
differs and this script is never run there." Both halves stop being true.

Platform from `uname -s`, overridable by a third argument. Three differences, all
verified against the real 4.7.1-stable release rather than assumed:

**Asset and binary layout.**

| Platform | Asset | Binary inside |
|---|---|---|
| Linux | `Godot_v${v}_linux.x86_64.zip` | `Godot_v${v}_linux.x86_64` |
| macOS | `Godot_v${v}_macos.universal.zip` | `Godot.app/Contents/MacOS/Godot` |
| Windows | `Godot_v${v}_win64.exe.zip` | **two** files, see below |

**There is no separate Windows console download.** `Godot_v4.7.1-stable_win64_console.exe.zip`
returns 404; the release manifest lists no such asset. The console build ships
*inside* `win64.exe.zip` alongside the real engine: a 170.7 MB
`Godot_v${v}_win64.exe` and a 193.5 KB `Godot_v${v}_win64_console.exe`.

The small one is a launcher shim, and it finds its engine by name. A byte search
of it finds the UTF-16LE literal `_console.exe` and **no hardcoded engine
filename**, so it derives the target by stripping that suffix from its own module
path. Therefore both files are extracted and renamed as a pair, to `godot.exe`
and `godot_console.exe`, and the console one is what gets invoked.

This matters more than its size suggests. `gate_env.sh:19-21` records that the
plain Windows build detaches from the terminal, so `$(...)` captures nothing and
**every harness reads as ERROR with no output to say why**. Installing only the
193 KB shim, or only the plain engine, both produce that failure by different
routes.

**Checksum tool.** `sha512sum` on Linux and in git-bash; `shasum -a 512` on
macOS, which has no stock `sha512sum`. Both accept the manifest's
`<hash>  <name>` format with `-c`.

**Export templates directory**, which Godot puts in a different place on each OS:

| Platform | Path |
|---|---|
| Linux | `~/.local/share/godot/export_templates/${dotted}` |
| macOS | `~/Library/Application Support/Godot/export_templates/${dotted}` |
| Windows | `${APPDATA}/Godot/export_templates/${dotted}` |

The templates are needed even though the gate itself only runs
`--headless --script`: `gate_require_pack` builds `titles/piposh3d.pck` via
`build_pack.sh:78`, which is an `--export-pack` and does need them.

The script prints its resolved binary path as its last line, so the workflow can
set `$GODOT` without hardcoding a version string. `gate_env.sh:24-29` honours
`$GODOT` ahead of everything else.

`install_godot_test.sh` extends to HEAD all three platform assets rather than
only Linux's, keeping its role as the pre-flight that names a renamed or pulled
release before three jobs fail on it at once.

### 3. `.github/workflows/nightly.yml`

`schedule` at 03:00 UTC plus `workflow_dispatch`. Matrix over `macos-latest` and
`windows-latest`, `fail-fast: false` so one platform's failure leaves the other's
verdict standing. All `run:` steps use `shell: bash`, which is git-bash on the
Windows runner.

Steps: checkout with `submodules: recursive` and `SUBMODULES_PAT`; `df -h`;
restore or install Godot from cache; verify `godot --version` answers; import;
`bash gate.sh`.

The Godot cache key includes `runner.os`, unlike `release.yml`'s — that workflow
deliberately shares one key across its matrix because all its legs are Linux and
want the identical entry. Here the entries are genuinely different binaries.

**`restore` and `save` as separate steps, not the combined `actions/cache`.**
This is a direct consequence of the "red is red" decision and is easy to miss:
the combined action saves in a post step that does not run when the job failed,
and this job is *expected* to fail every night for as long as any entry is red.
The cache would therefore never populate, and both runners would re-download
Godot plus ~1 GB of templates nightly, forever — a tax with nothing in the logs
pointing at its cause. The `save` step sits immediately after the install and
before the gate, so it never depends on the verdict at all.

**Templates are verified, not assumed.** `release.yml:296-304` already carries
this guard, with a comment noting that `cache-hit` can be true for a partial
entry and that nothing between restore and first use would catch it. It matters
more here, because `gate_require_pack` is deliberately *never fatal*: templates
in the wrong place make `--export-pack` fail, the run continues, and every
entry carries twelve autoload errors that nothing attributes to the install. The
`--version` output is checked non-empty for the paired reason — on Windows an
empty answer means the non-console build got installed.

The installer records both resolved paths in `$bindir/.godot-path` and
`$bindir/.templates-path`, because the caller that most needs them is the one
that never ran it: a job restoring `$bindir` from cache skips the install and
would otherwise re-derive the per-OS rules to know what it just restored.

`GATE_TIMEOUT: 600` rather than the 900s default. Since the job is expected to
fail, its value is the whole table, and a few hangs at 900s each would push the
tail past the job ceiling and lose the part nobody has seen.

No separate pack-build step: `gate_require_pack` does it inside `gate.sh`, which
is where it belongs, and the templates installed above are what let it succeed.

`timeout-minutes: 90`. A full local run is ~18 minutes (measured, below); the
ceiling is for a hung harness, not for the expected duration. `concurrency` with
`cancel-in-progress: false` so a manual dispatch cannot overlap a scheduled run —
`gate.sh`'s own `.gate.lock` would refuse the second one anyway, at `exit 2`
after a 15-minute wait, which is a slow and confusing way to discover an overlap.

No artifact upload. The status table is the whole output and it lands in the job
log; verbose harness output carries private corpus paths and member names, and
this repository is public. `release.yml` filters even a zip listing for this
reason.

### 4. `.github/workflows/push.yml`

There is no PR flow in this project, so push-to-main is the only integration
point that exists. Two jobs, both on `ubuntu-latest`, because fast feedback
matters more here than platform coverage — that is the nightly's job.

`suites` runs the four `tools/ci/*_test.sh` scripts. `release.yml`'s preflight
already establishes that these need no submodules and no PAT: they test shell and
Mach-O parsing against their own fixtures. ~30 seconds.

`structure` runs `check.sh`. This one does boot the configured game, so it needs
a corpus — but only one. `check.sh` forwards its arguments, so it runs as
`bash check.sh --root piposh2` against a selective submodule init of
`games/piposh2` alone, rather than the ~3.8 GB all-seven checkout. Checkout keeps
credentials so the submodule fetch can authenticate, then initialises the single
path.

### 5. `release.yml` gains one `schedule` line

A weekly dry run, Sundays 04:00 UTC. **This needs no new guard.** On a schedule
`github.ref` is `refs/heads/main`, so every `startsWith(github.ref, 'refs/tags/')`
condition in that file is already false: no draft is opened, nothing is uploaded,
and `finalize` is skipped by its own `if:`. The version resolves to `main` via
`${DISPATCH_VERSION:-$GITHUB_REF_NAME}` and passes the existing charset guard.

**What this does not cover:** `finalize` is exactly what a non-tag run skips, so
the four-asset gate at `release.yml:677` stays untested by it. That gate was
flagged as untested before this change and remains so after it. Covering it needs
a different mechanism and is out of scope here.

## What does not change

`gate_env.sh` is untouched. Its Godot search already covers macOS paths and
prefers a Windows console build, and `$GODOT` takes precedence over all of it, so
the workflow points it at the installed binary without an edit.

`check.sh`'s subject is untouched — it still runs `preview_surface.gd` and still
forwards its arguments, which is what makes the selective-submodule job possible.

`gate.sh`'s `ALL` list is untouched. No entry is added, removed, reordered or
given a flag it did not have.

## A sixth change, found while building the fifth

`check.sh` had the same defect `gate.sh` did, and worse: it printed `PASS` or
`FAIL` and then exited 0 either way, with the single exception of the 120s
ceiling. Put in `push.yml` unchanged it would have been a job that runs Godot,
prints a red, and reports success — a check that cannot fail, which is worse than
no check because it looks like one.

So it grows an exit code on the same rule, with three ways to fail: the
diagnostic grep matched, the result line says `FAIL`, or **no `PASS` line was
printed at all**. The third is the one worth naming. A run that died before it
could report is indistinguishable from a clean one to anything grepping for
`FAIL`, and that is exactly the shape of failure this repository keeps
rediscovering.

Verified both directions: `bash check.sh --root piposh2` exits 0,
`bash check.sh --root no-such-corpus` exits 1.

## The suite is green, and both reds were resolved differently

Measured by a whole-suite run on 4.7.1 on macOS, 2026-08-12: **all 77 entries
pass.** When this document was first written there were two reds and the plan
was to ship the nightly red. Both were dealt with instead, and the two remedies
are worth distinguishing because only one of them is a fix.

**`lingo_surface_audit` was fixed.** It failed for one reason and it was
documentation rather than code: `4b2e9371` bound `the mouseLoc` and never
recorded it in `docs/LINGO_SURFACE.md` §19, whose rule is that every name the
engine binds appears in the claim table. One table row closed it.

Worth keeping as a pattern: that harness carries an explicit anti-suppression
guard, and the fix had to be checked against it. Adding a row for a *live*
binding is what the check asks for; what would have been suppression is touching
the separately-pinned reachable-gap count, which this did not.

**`palette_members` was removed from `ALL`**, which is not a fix and is not
pretending to be one. Its subject is a corpus whose bitmaps name palette
*members*, and the only one is `test-games/itamar-park` — not a submodule, not
tracked, ignored at `.gitignore:73`, never shipped with the six titles this
engine is for. An entry that can only pass against a corpus outside the project
gates nothing here, so it was reporting red for ever while measuring nothing.

Two claims that justified keeping it were measured and are false. `gate.sh` said
no shipped title carries a single `CLUT` chunk or palette cast member:
`piposh-ru` carries three of each, in `Texts.cst`, `pipdata/Texts.cst` and
`pipdata/Textold.cst`, and scores 7 of 9. And re-pointing there would not have
worked either — its two remaining gaps are facts about its art, not defects. No
bitmap there names a palette member, and the Mac and Windows D5 tables agree at
142 of 256 indices, so a member decoding identically under both provably uses
only those. The other four corpora genuinely have none; their apparent matches
are incidental bytes inside `.AIF` audio.

**The coverage it took with it was rebuilt, wider.** Removing it would have left
the CLUT read path ungated, which is how `palette_cycle` came to carry four reds
nobody saw. So `tools/palette_corpus.gd` was written to assert what the six
shipped titles *can* answer: 14 checks over 6 roots, 651 containers, 118,991
bitmaps naming a built-in palette, 167 naming a member, and 482 movie defaults.
The old entry was 9 checks over one title nobody has. Only one thing is now
uncovered — that a bitmap's own named palette reaches the decoder and changes
the pixels — and no shipped title can express it.

**Its first version asserted the wrong thing, which is worth recording.** It
failed on `piposh-dream`'s 167 bitmaps naming member 154, a type-2 member, and
that looked like an engine bug. It is not: the container states file version
`0x57E`, so the D5 layout the reader uses is correct, and the reference resolves
the same pair to the same non-palette. The engine already falls back to the stage
default. A check asserting that a 1990s cast is internally consistent would have
gated this project on data it cannot fix and gone red for ever while measuring
nothing — the same failure this whole change exists to remove. It now asserts the
fallback, which is the part the port owns.

## Risk

**The gate has never run on Windows.** Not once, by anyone. The first run is a
discovery run, and some of what it reports will be genuine Windows bugs in the
port rather than CI faults. Budget for that rather than treating the first red as
a workflow defect.

**Runtime is not the ~10 minutes README.md:236 claims.** Measured at ~18 minutes
for the 78 entries it had then (77 now) on an M-series Mac with nothing else
running. CI runners are
slower and the corpus checkout is ~3.8 GB. `README.md` is corrected to match.

**Disk on non-Linux runners.** macOS and Windows runners carry less headroom than
the Linux ones `release.yml` measured 88 GB on. The `df -h` step is there to make
an ENOSPC legible, since this pipeline's history names that as its least readable
failure mode.

**Scheduled workflows are disabled after 60 days of repository inactivity.** A
silent failure mode: the nightly stops without announcing it. Unlikely to bite at
this repository's commit rhythm, but worth knowing it can happen.

## Out of scope

Fixing `lingo_surface_audit`. Provisioning `test-games/itamar-park`. Covering
`release.yml`'s four-asset finalize gate. Sharding the gate across jobs — at ~18
minutes it does not need it, and `gate.sh:195-205` already resolves named entries
to their `ALL` arguments if it ever does.

## Testing

`install_godot_test.sh` covers the asset-name half on all three platforms, and it
is the only new code with a natural unit test — the rest is workflow YAML, which
is tested by running it.

The `gate.sh` exit-code change was verified directly, in both directions and
with the no-short-circuit case separated out, because exit 1 on its own is also
consistent with a counter that stopped at the first red:

| Command | Expected | Got |
|---|---|---|
| `bash gate.sh game_config` | exit 0 | exit 0, "all 1 passed" |
| `bash gate.sh palette_members` | exit 1 | exit 1, "1 of 1 did not pass" |
| `bash gate.sh palette_members game_config lingo_surface_audit` | exit 1, **3 rows** | exit 1, 3 rows, "2 of 3 did not pass" |
| `bash gate.sh` (full) | exit 1, **78 rows** | exit 1, 78 rows, "1 of 78 did not pass" |

The last two are the ones that matter. Those runs predate removing
`palette_members` from `ALL`; naming it explicitly still runs it, since the
command line accepts any harness name whether or not `ALL` carries it.

`workflow_dispatch` on the nightly is how the workflow itself gets exercised
before a scheduled run happens, on both platforms, without waiting for 03:00.
