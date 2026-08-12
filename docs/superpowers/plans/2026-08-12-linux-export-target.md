# Linux Export Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `git push origin v0.2.0` produces a fourth release asset, a zip holding `GodotDirectorPlayer.x86_64` and its `.pck`, carrying the same six titles and the piposh-3d embed as the other three.

**Architecture:** Linux becomes a fourth leg of the existing `export` matrix in `.github/workflows/release.yml`, shaped exactly like the other three: an export step gated on `matrix.target`, a target-specific archive check sized to its failure mode, then the shared asset/size/upload steps. No new runner, no new secret, no new file under `tools/ci/`.

**Tech Stack:** Godot 4.7.1-stable, GitHub Actions on `ubuntu-latest`, POSIX shell, Info-ZIP `zip`/`unzip`.

**Spec:** [`docs/superpowers/specs/2026-08-11-linux-export-design.md`](../specs/2026-08-11-linux-export-design.md)

## Global Constraints

- **Linux is a leg like the other three, not a new kind of thing.** Do not add a capability the other legs lack. Specifically: **do not boot the exported artifact in CI**, even though `ubuntu-latest` could. That is excluded by the spec as its own decision.
- **`GODOT_VERSION: 4.7.1-stable`** — the workflow's pinned version. Author the preset with the same version locally.
- **The preset's `include_filter` is copied verbatim from the other four:** `games/*,director_game.cfg,data/*.json,titles/*.pck`
- **Its `exclude_filter` likewise:** `*.md,docs/*,android/*.keystore,reference/*,saves/*,.snapshots/*,build/*,test-games/*`
- **`bash gate.sh` before landing, and grep the output for `FAIL`.** The script exits 0 on a red. `palette_members` is a standing failure from a gitignored fixture and is not yours.
- **Push directly to `main`.** No branches, no PRs in this repo.
- **Do not edit `README.md`.** It has mixed CRLF/CR/LF line endings, so any edit normalises the whole file into a whole-file diff.
- **Commit after every task.**

---

### Task 1: The Linux export preset

Adds `[preset.4]` to `export_presets.cfg` and proves the existing harness covers it.

The test-first step here is not ceremony. The spec claims `export_presets_check.gd` brings a new preset under the gate with no edit, and the only way to know that is to watch it fail on a preset whose `include_filter` is wrong.

**Files:**
- Modify: `export_presets.cfg` (append `[preset.4]` and `[preset.4.options]`)
- Test: `tools/export_presets_check.gd` (existing harness, not modified)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a preset named exactly `Linux`, which Task 2 passes to `--export-release` as `${{ matrix.preset }}`, and whose `export_path` is `build/linux/GodotDirectorPlayer.x86_64`.

- [ ] **Step 1: Generate the preset in the Godot editor, not by hand**

Open the project in Godot 4.7.1-stable, `Project > Export… > Add… > Linux`, and set only:

- **Name:** `Linux`
- **Export Path:** `build/linux/GodotDirectorPlayer.x86_64`
- **Binary Format > Embed PCK:** off
- **Texture Format:** S3TC/BPTC on, ETC2/ASTC off (matching Windows)
- **Resources > Filters to export non-resource files/folders:** paste the `include_filter` value from Global Constraints
- **Resources > Filters to exclude:** paste the `exclude_filter` value

Then close the dialog so Godot writes the file.

Why the editor: `platform=` was spelled `Linux/X11` in Godot 3 and changed in 4.x, and a misspelled option key silently defaults. `export_presets_check.gd` inspects only `include_filter`, so a wrong platform string passes every local check and fails at export time in CI.

The Linux export template is **not** installed on this machine (the template directory holds only `macos.zip` and `ios.zip`), so the dialog will show a missing-template warning. That is expected and does not prevent authoring the preset. Do not download the 1.2 GB template set for this task; Task 5 proves the export on CI.

- [ ] **Step 2: Break the filter on purpose, and watch the harness fail**

Temporarily edit the `[preset.4]` block only:

```
include_filter="director_game.cfg"
```

Run:

```bash
godot --headless --path . --script tools/export_presets_check.gd 2>&1 | tail -30
```

Expected: a `FAIL` line naming the `Linux` preset and listing the uncovered paths, among them `games/rating`, `games/piposh` and `titles/piposh3d.pck`.

If it passes, stop. The harness is not seeing the new preset and nothing below this line is trustworthy.

- [ ] **Step 3: Restore the correct filter**

Put the `include_filter` back to the verbatim value in Global Constraints.

- [ ] **Step 4: Run the harness and confirm it passes**

```bash
godot --headless --path . --script tools/export_presets_check.gd 2>&1 | tail -30
```

Expected: no `FAIL` lines, and the trailing path list printed once. Five presets are now checked.

- [ ] **Step 5: Confirm Godot disturbed nothing else**

```bash
git diff export_presets.cfg
```

Godot rewrites this file wholesale and may reorder or normalise keys across all five presets. Expected: **only** added lines, forming `[preset.4]` and `[preset.4.options]`. In particular confirm these two tracked values are untouched:

```
version/code=1
version/name="0.1.0"
```

If other presets moved, revert and re-apply by hand from the generated block rather than staging a reordering diff.

- [ ] **Step 6: Commit**

```bash
git add export_presets.cfg
git commit -m "Add a Linux export preset

Generated in the editor rather than hand-written: platform= changed
spelling between Godot 3 and 4, and export_presets_check.gd inspects
only include_filter, so a wrong platform string would pass locally and
fail at export time in CI.

Confirmed the harness covers it by breaking the filter first."
```

---

### Task 2: The export leg and its archive check

Adds the matrix entry, the export step, and the target-specific verification.

**Files:**
- Modify: `.github/workflows/release.yml` (matrix `include:` list; two new steps after `Export macOS`'s verification block and before `Export Android`)

**Interfaces:**
- Consumes: the preset named `Linux` from Task 1.
- Produces: `ASSET=build/GodotDirectorPlayer-Linux-${RELEASE_NAME}.zip` in `$GITHUB_ENV`, consumed by the existing shared `Verify an asset was produced`, `Check asset size` and upload steps, and counted by Task 3's gate.

- [ ] **Step 1: Prove the archive check catches both failure modes, before writing it into the workflow**

The check is inline bash and gets no test suite, matching the Android check it is modelled on. It still gets verified once, here, against fixtures. Run this whole block:

```bash
cd "$(mktemp -d)"
mkdir good nopck noexec

printf 'x' > good/GodotDirectorPlayer.x86_64 && chmod +x good/GodotDirectorPlayer.x86_64
printf 'y' > good/GodotDirectorPlayer.pck
( cd good && zip -qr ../good.zip . )

printf 'x' > nopck/GodotDirectorPlayer.x86_64 && chmod +x nopck/GodotDirectorPlayer.x86_64
( cd nopck && zip -qr ../nopck.zip . )

printf 'x' > noexec/GodotDirectorPlayer.x86_64 && chmod 644 noexec/GodotDirectorPlayer.x86_64
printf 'y' > noexec/GodotDirectorPlayer.pck
( cd noexec && zip -qr ../noexec.zip . )

for z in good.zip nopck.zip noexec.zip; do
  echo "--- $z"
  unzip -Z "$z" > listing.txt
  grep -q 'GodotDirectorPlayer\.pck$' listing.txt \
    && echo "  pck:  ok" || echo "  pck:  MISSING"
  awk '/GodotDirectorPlayer\.x86_64$/ && $1 ~ /^-rwx/ {f=1} END {exit !f}' listing.txt \
    && echo "  exec: ok" || echo "  exec: MISSING"
done
```

Expected, exactly:

```
--- good.zip
  pck:  ok
  exec: ok
--- nopck.zip
  pck:  MISSING
  exec: ok
--- noexec.zip
  pck:  ok
  exec: MISSING
```

Each fixture must trip exactly one check. If `nopck.zip` also reports `exec: MISSING`, the two conditions are entangled and the messages will misdiagnose real failures.

- [ ] **Step 2: Add the matrix entry**

In `.github/workflows/release.yml`, the `strategy.matrix.include:` list currently ends with the android entry. Add a fourth:

```yaml
          - target: linux
            preset: Linux
```

- [ ] **Step 3: Add the export step**

Insert after the `Verify the macOS binary is signed and universal` step and before `Export Android`:

```yaml
      # The only target that is not cross-compiled: this runner IS the target
      # platform. That buys nothing extra here on purpose -- the artifact is not
      # executed, because no other leg executes its artifact and this one is not
      # a different shape from the others. See the design doc.
      - name: Export Linux
        if: ${{ matrix.target == 'linux' }}
        run: |
          mkdir -p build/linux
          godot --headless --path . --export-release "${{ matrix.preset }}" build/linux/GodotDirectorPlayer.x86_64
          # Same corpus check and size instrumentation as Windows: with
          # `embed_pck=false` the .pck is where `games/*` actually lands, so a
          # 40 MB .pck instead of multiple GB means the export did not take the
          # paths the preset names.
          ls -lh build/linux/
          # Two files that must travel together, and a mode that must survive.
          ( cd build/linux && zip -qr "../GodotDirectorPlayer-Linux-${RELEASE_NAME}.zip" . )
          echo "ASSET=build/GodotDirectorPlayer-Linux-${RELEASE_NAME}.zip" >> "$GITHUB_ENV"
```

- [ ] **Step 4: Add the archive check step**

Immediately after the export step:

```yaml
      # Modelled on the Android pack check rather than on the macOS signing
      # check: the failure mode is a missing archive member, not a malformed
      # binary, so it needs `unzip` and not a parser.
      - name: Verify the Linux archive is complete and runnable
        if: ${{ matrix.target == 'linux' }}
        run: |
          listing="${{ runner.temp }}/linux-listing.txt"
          if ! unzip -Z "$ASSET" >"$listing"; then
            echo "unzip could not list $ASSET -- the archive itself is missing or corrupt, not merely incomplete." >&2
            exit 1
          fi
          # `binary_format/embed_pck=false`, so the binary alone is inert.
          if ! grep -q 'GodotDirectorPlayer\.pck$' "$listing"; then
            echo "GodotDirectorPlayer.pck is not in $ASSET -- the binary would start and find no engine data." >&2
            cat "$listing" >&2
            exit 1
          fi
          # `zip` preserves the mode, so this asserts something that should
          # already be true. Nothing else in the pipeline would notice if it
          # stopped being true, and the player's symptom is "Permission denied"
          # with nothing to suggest the download is at fault.
          if ! awk '/GodotDirectorPlayer\.x86_64$/ && $1 ~ /^-rwx/ {f=1} END {exit !f}' "$listing"; then
            echo "GodotDirectorPlayer.x86_64 is not executable inside $ASSET -- the player would have to chmod +x it to launch." >&2
            cat "$listing" >&2
            exit 1
          fi
```

- [ ] **Step 5: Confirm the workflow still parses**

```bash
python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/release.yml')); \
print([m['target'] for m in d['jobs']['export']['strategy']['matrix']['include']])"
```

Expected: `['windows', 'macos', 'android', 'linux']`

If PyYAML is unavailable, use Ruby's stdlib, which needs no install:

```bash
ruby -ryaml -e 'd=YAML.load_file(".github/workflows/release.yml"); \
p d["jobs"]["export"]["strategy"]["matrix"]["include"].map{|m| m["target"]}'
```

**Do not use `gh workflow view release --yaml` for this.** It fetches the copy
GitHub has registered, not your working tree, so it parses the pre-edit file and
reports success no matter what you just wrote. Found the hard way during Task 2:
grepping its output for `target: linux` returned nothing while the local edit was
correct.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "Export Linux as a fourth leg

Shaped like the other three: export step, one target-specific check,
then the shared asset/size/upload steps. The check is Android's inline
bash rather than macOS's parser, because the failure mode is a missing
archive member.

It also asserts the exec bit, which unzip -l cannot see -- a binary
that lost it is a download the player cannot run and cannot diagnose."
```

---

### Task 3: The four-asset publish gate

`finalize` refuses to publish an incomplete release. It counts three.

**Files:**
- Modify: `.github/workflows/release.yml` (the `finalize` job's `Publish the draft` step, and one comment above `Upload build summary for inspection`)

**Interfaces:**
- Consumes: the fourth asset produced by Task 2.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Find all three occurrences of the count**

```bash
grep -n "three failing jobs\|-lt 3\|Expected 3 assets" .github/workflows/release.yml
```

Expected: exactly **four** hits.

1. `~636` — a comment about artifact-name collisions saying "three failing jobs".
2. `~668` — a comment illustrating the non-numeric guard with `[ "" -lt 3 ]`.
3. `~677` — the gate itself.
4. `~679` — the gate's error message.

Changing only the gate leaves it correct and lying about why it fired. Leaving the two comments leaves them describing code that no longer exists.

- [ ] **Step 2: Update the gate and its message**

In the `Publish the draft` step:

```bash
          if [ "$count" -lt 4 ]; then
            gh release view "$TAG" --json assets -q '.assets[].name' >&2 || true
            echo "Expected 4 assets (Windows, macOS, Linux, Android); refusing to publish an incomplete release." >&2
            exit 1
          fi
```

**Keep the `|| true`.** Actions runs `bash -e`, so without it a failure of that
diagnostic listing aborts the step on `gh`'s exit status instead of printing the
"Expected 4 assets" message the block exists to print. Changing only the number
is the whole edit here.

- [ ] **Step 3: Update both stale comments**

Above `Upload build summary for inspection`, change `three failing jobs do not collide` to `four failing jobs do not collide`.

In the comment above the `case ${count:-}` guard, change the illustration `[ "" -lt 3 ]` to `[ "" -lt 4 ]` so it matches the gate it is explaining.

- [ ] **Step 4: Confirm no occurrence was missed**

```bash
grep -n "three failing jobs\|-lt 3\|Expected 3 assets" .github/workflows/release.yml
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "Require four assets before publishing

The count lives in three places: the gate, its message, and a comment
about artifact-name collisions. Changing only the gate leaves it
correct and lying about why it fired."
```

---

### Task 4: `docs/LINUX.md`

`ANDROID.md` and `MACOS.md` both exist. Two of three targets have a doc, so the structure the others set says to write this one.

**Files:**
- Create: `docs/LINUX.md`
- Do **not** modify: `README.md` (see Global Constraints)

**Interfaces:**
- Consumes: the asset name from Task 2, `GodotDirectorPlayer-Linux-<tag>.zip`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the file**

Keep it thinner than `MACOS.md`. Linux asks the player for no signing ceremony, so most of that document's length has no analogue here. Write exactly this:

````markdown
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
````

- [ ] **Step 2: Confirm the links resolve**

```bash
ls docs/ANDROID.md docs/MACOS.md
```

Expected: both listed. These are the only two links in the file.

- [ ] **Step 3: Commit**

```bash
git add docs/LINUX.md
git commit -m "Document the Linux build

ANDROID.md and MACOS.md both exist; two of three targets had a doc.
Shorter than either, because Linux asks the player for no signing
ceremony -- just keep the .pck beside the binary."
```

---

### Task 5: Prove it on CI, then land

Nothing above has run a Linux export. The template is not installed locally and this plan deliberately does not download 1.2 GB to change that.

**Files:**
- Modify: none, unless a failure sends you back to an earlier task.

**Interfaces:**
- Consumes: everything from Tasks 1 through 4.
- Produces: a green dispatch run, which is the evidence the design's remaining inferences are correct.

- [ ] **Step 1: Run the local gate**

```bash
bash gate.sh 2>&1 | tee /tmp/gate.log; grep FAIL /tmp/gate.log
```

Expected: the only `FAIL` lines are `palette_members`, which is a standing red from a gitignored fixture. Any other `FAIL` is yours. **Do not trust the exit code** — `gate.sh` exits 0 on a red.

- [ ] **Step 2: Push to main**

```bash
git push origin main
```

- [ ] **Step 3: Start a dispatch dry run**

A dispatch run exports and checks everything and publishes nothing.

```bash
gh workflow run release -f version=0.0.0-linuxcheck
gh run watch "$(gh run list --workflow=release --limit 1 --json databaseId -q '.[0].databaseId')"
```

- [ ] **Step 4: Read the Linux leg's evidence**

```bash
run=$(gh run list --workflow=release --limit 1 --json databaseId -q '.[0].databaseId')
job=$(gh run view "$run" --json jobs -q '.jobs[] | select(.name | contains("linux")) | .databaseId')
gh run view --job "$job" --log | grep -E "GodotDirectorPlayer|ok +build|MiB"
```

Expected, in order:

1. `ls -lh build/linux/` showing a `.pck` in the **gigabytes**, not tens of megabytes. A small `.pck` means the export did not take the paths the preset names, and the archive check would still pass.
2. No output from the archive check step, which is silent on success.
3. `ok    build/GodotDirectorPlayer-Linux-0.0.0-linuxcheck.zip: <n> bytes (<n> MiB)` from the size check.

Record the byte count. The spec predicts it lands beside the Windows zip at roughly 91-92% of the 2 GiB cap; if it is materially higher than the Android APK's 93.9%, say so rather than filing it as fine.

- [ ] **Step 5: Confirm the other three legs are unharmed**

```bash
gh run view "$run" --json jobs -q '.jobs[] | "\(.name)\t\(.conclusion)"'
```

Expected: four `Export …` jobs, all `success`, plus `preflight` success. `finalize` is skipped on a dispatch run, which is correct and not a failure.

- [ ] **Step 6: Record the measurement in the spec**

Add a `## Confirmed in CI` section to `docs/superpowers/specs/2026-08-11-linux-export-design.md`, matching how the macOS design records its run numbers and measured sizes. State the run id, the `.pck` size, the asset size and its percentage of the cap.

- [ ] **Step 7: Commit and push**

```bash
git add docs/superpowers/specs/2026-08-11-linux-export-design.md
git commit -m "Record the Linux export measurements from run <id>"
git push origin main
```

- [ ] **Step 8: Note what remains unproven**

The four-asset publish gate has **not** run: `finalize` is skipped on a dispatch. It fires for the first time on the next real tag. Say so explicitly rather than reporting the target as fully verified.

---

## Notes for the implementer

**Where this can go wrong quietly.** The archive check passes on a `.pck` of any size. Only the `ls -lh` output in Task 5 Step 4 distinguishes "shipped the corpus" from "shipped an empty package", and that is a human reading a number, not a gate. The pipeline's one confirmed real defect was Windows shipping zero game data, and it looked exactly like a green run.

**If the export fails with a missing template.** The cache key is `godot-${GODOT_VERSION}-${hashFiles('tools/ci/install_godot.sh')}`, and cache keys are immutable — re-running alone restores the same entry. The workflow already has a step that detects an empty template directory and says this. If the cached entry is partial, delete it from the repository's Actions cache UI or change the key.

**Do not add a `pull_request` trigger** to make any of this easier to test. Its absence is what keeps the submodule PAT and the release keystore unreachable from a fork PR by construction. `workflow_dispatch` already covers the testing need and requires write access.
