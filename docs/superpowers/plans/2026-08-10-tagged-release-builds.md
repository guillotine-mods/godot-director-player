# Tagged Release Builds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `git push origin v0.1.0` publishes a GitHub release carrying a Windows zip and a signed APK, each containing all six Director titles and the piposh-3d embed.

**Architecture:** One `ubuntu-latest` job triggered only by a `v*` tag. Logic lives in small shell scripts under `tools/ci/` that run and are tested locally; the workflow YAML is orchestration only. A new GDScript harness under `tools/` asserts the export presets carry every path the engine opens at runtime, so the "artifact silently missing a title" failure is caught by `gate.sh` rather than by a player.

**Tech Stack:** GitHub Actions, Godot 4.7.1-stable headless, JDK 17, Android SDK build-tools, POSIX shell, GDScript.

## Global Constraints

- Godot version is pinned to `4.7.1-stable` everywhere. `project.godot` declares `config/features=PackedStringArray("4.7", ...)`; the local editor is `4.7.1.stable.official.a13da4feb`. A binary and template set that disagree fail the export outright.
- Scripts must run on both macOS (local development) and Linux (CI), except `tools/ci/install_godot.sh`, which is Linux-only by design and is tested locally only for syntax and URL reachability.
- No step may carry `continue-on-error`. A failed export must not yield a release.
- Harnesses follow the existing idiom exactly: `extends SceneTree`, `tools/lib/harness.gd` for reporting, `begin`/`check`/`complete`/`finish`, and title-agnostic (no harness may name a game).
- Never reference an autoload by its registered name inside a `--script` harness. Autoloads resolve at compile time and register a frame into such a run; naming one hangs the gate at its 900s ceiling. Load the script by path instead.
- A fresh checkout has no `.godot`, so `class_name` globals do not resolve. `--import` must run before any export or harness.
- Commit directly to `main`. No branches, no PRs.
- GitHub caps a single release asset at 2 GiB. There is no cap on asset count (1000 per release) or total release size.

---

### Task 1: Assert the presets ship what the runtime mounts

The spec found two presets that disagree with what the engine opens: Windows names only `director_game.cfg`, and neither names `titles/*.pck`. Because `**/*.import` is gitignored and the corpora load from source at runtime, `export_filter="all_resources"` does not sweep them in, so an unnamed path is simply absent from the artifact. The launcher hides an embed whose scene `ResourceLoader.exists()` cannot find, so the symptom is a missing tile and no error at all.

The harness derives its expectations rather than listing them, because a list here is a second place to update when a title is added and the first to be forgotten.

**Files:**
- Create: `tools/export_presets_check.gd`
- Modify: `export_presets.cfg` (both presets' `include_filter`)
- Modify: `gate.sh:106` (the `ALL` list)

**Interfaces:**
- Consumes: `res://tools/lib/harness.gd` (`begin`, `check`, `complete`, `failures`, `finish`), `res://tools/lib/key_sites.gd` (`roots() -> Array` of `res://games/<name>` paths).
- Produces: nothing other tasks consume. This task is a standalone gate.

- [ ] **Step 1: Write the failing harness**

Create `tools/export_presets_check.gd`:

```gdscript
extends SceneTree
## Everything the engine opens at runtime is inside some preset's include filter.
##
##   godot --headless --path . --script tools/export_presets_check.gd
##
## `export_filter="all_resources"` sweeps in imported resources, and this project
## has none for its corpora: `**/*.import` is gitignored on purpose, so the
## containers, the AIFFs and the generated pack all arrive as plain files that
## only `include_filter` can carry. A path the engine opens and the filter does
## not name is not a build error -- the export succeeds, the artifact ships, and
## the title is simply absent. `scenes/launcher/title_list.gd` hides an embed
## whose scene does not resolve, so the symptom is a missing tile rather than a
## crash, which is the quietest kind of wrong.
##
## Derives its expectations rather than listing them. The roots come from
## `KeySites`, and the pack path is read off the autoload's own constant, so
## adding a title does not silently leave this file behind.
##
## Title-agnostic: it names no game.

const Harness := preload("res://tools/lib/harness.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")

const PRESETS := "res://export_presets.cfg"
const PACK_SCRIPT := "res://autoload/piposh3d_pack.gd"


func _init() -> void:
	var h := Harness.new()

	var case := "the presets file parses"
	h.begin(case)
	var cfg := ConfigFile.new()
	var err := cfg.load(PRESETS)
	if not h.check("export_presets.cfg loads", err == OK, error_string(err)):
		h.complete(case)
		quit(h.finish("the export presets"))
		return
	var presets := _preset_sections(cfg)
	# The subject has to exist, or every assertion below passes over nothing.
	if not h.check("there are presets to check", not presets.is_empty(),
			"%d preset(s)" % presets.size()):
		h.complete(case)
		quit(h.finish("the export presets"))
		return
	h.complete(case)

	case = "the runtime paths can be derived"
	h.begin(case)
	var required: Array[String] = ["director_game.cfg"]
	var roots := KeySites.roots()
	h.check("there are game roots on disc", not roots.is_empty(),
		"%d root(s)" % roots.size())
	for root in roots:
		required.append(str(root).trim_prefix("res://"))
	# Read the constant off the script resource, never through the autoload
	# name: naming an autoload is a compile-time reference, autoloads register a
	# frame into a `--script` run, and this is such a run. `title_list.gd`
	# carries the same note for the same reason.
	var script: Script = load(PACK_SCRIPT)
	var pack := ""
	if script != null:
		pack = str(script.get_script_constant_map().get("PACK_PATH", ""))
	h.check("the pack autoload still declares PACK_PATH", pack != "", PACK_SCRIPT)
	if pack != "":
		required.append(pack.trim_prefix("res://"))
	h.complete(case)

	for section in presets:
		var name := str(cfg.get_value(section, "name", section))
		case = "%s carries every runtime path" % name
		h.begin(case)
		var filters := _filters(str(cfg.get_value(section, "include_filter", "")))
		var missing: Array[String] = []
		for path in required:
			if not _covered(path, filters):
				missing.append(path)
		h.check("include_filter covers every path the engine opens",
			missing.is_empty(), ", ".join(missing))
		h.complete(case)

	print("")
	for path in required:
		print("  %s" % path)
	quit(h.finish("the export presets"))


## The `[preset.N]` sections, skipping their `.options` siblings.
static func _preset_sections(cfg: ConfigFile) -> Array[String]:
	var out: Array[String] = []
	for section in cfg.get_sections():
		var s := str(section)
		if s.begins_with("preset.") and not s.ends_with(".options"):
			out.append(s)
	return out


static func _filters(raw: String) -> Array[String]:
	var out: Array[String] = []
	for part in raw.split(",", false):
		var trimmed := str(part).strip_edges()
		if trimmed != "":
			out.append(trimmed)
	return out


## Godot matches an include entry against the project-relative path, with `*`
## standing for any run of characters. `games/*` is what carries everything
## beneath it, and `titles/*.pck` the generated pack.
static func _covered(path: String, filters: Array[String]) -> bool:
	for f in filters:
		if path == f or path.match(f):
			return true
	return false
```

- [ ] **Step 2: Run it and watch it fail**

Run: `godot --headless --path . --script tools/export_presets_check.gd`

Expected: FAIL. `Windows Desktop` reports every game root plus the pack as missing; `Android` reports the pack as missing. The final line reads `FAIL  the export presets (N checks, 2 failed)`.

If it instead reports 0 checks or an ERROR, the harness is dark and must be fixed before proceeding — that is the exact failure `tools/lib/harness.gd` exists to catch.

- [ ] **Step 3: Fix both presets**

In `export_presets.cfg`, set the `include_filter` on `[preset.0]` (Android) and `[preset.1]` (Windows Desktop) to the same value:

```
include_filter="games/*,director_game.cfg,titles/*.pck"
```

Leave `exclude_filter` untouched on both.

- [ ] **Step 4: Run it and watch it pass**

Run: `godot --headless --path . --script tools/export_presets_check.gd`

Expected: PASS, with a check count greater than zero and one case per preset.

- [ ] **Step 5: Register it in the gate**

In `gate.sh:106`, insert `export_presets_check` into `ALL` immediately after `title_list`, so the three config assertions sit together:

```
ALL="game_config title_mapping title_list export_presets_check preview_surface ..."
```

- [ ] **Step 6: Confirm the gate picks it up**

Run: `bash gate.sh export_presets_check`

Expected: a single line reading `export_presets_check         PASS`. Not `EMPTY`, which would mean it asserted nothing.

- [ ] **Step 7: Run the whole gate**

This task touched three files, one of them `gate.sh` itself, so the single-harness run above is not enough to call it clean.

Run: `bash gate.sh`

Expected: every entry PASS, and the new `export_presets_check` line present among them. No entry may read EMPTY, ERROR or TIMEOUT. Compare against the run before this task if anything looks off; entries unrelated to the presets should be unchanged.

- [ ] **Step 8: Commit**

```bash
git add tools/export_presets_check.gd tools/export_presets_check.gd.uid export_presets.cfg gate.sh
git commit
```

Commit message should say what the harness caught: both presets omitted `titles/*.pck` and the Windows one omitted the corpora entirely, so a Windows build shipped no game data at all and neither build could ever have shown the piposh-3d tile.

---

### Task 2: Stamp the release version into the Android preset

`version/code=1` is committed. Android refuses an update whose `versionCode` did not increase, so without this every release after the first is uninstallable over its predecessor, forcing the uninstall-and-lose-saves path that the stable release keystore exists to avoid.

**Files:**
- Create: `tools/ci/stamp_version.sh`
- Create: `tools/ci/stamp_version_test.sh`

**Interfaces:**
- Produces: `tools/ci/stamp_version.sh <tag> <code> [presets-file]`, exit 0 on success, 2 on bad input, 1 if the substitution did not take. Defaults `presets-file` to `export_presets.cfg`. Task 6 calls it as `tools/ci/stamp_version.sh "$GITHUB_REF_NAME" "$GITHUB_RUN_NUMBER"`.

- [ ] **Step 1: Write the failing test**

Create `tools/ci/stamp_version_test.sh`:

```bash
#!/usr/bin/env bash
# Checks what stamp_version.sh actually wrote, against a fixture.
#
#   bash tools/ci/stamp_version_test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp=$(mktemp -d)

# One EXIT trap only. Bash keeps the last registration per signal, so cleanup
# and the abort guard have to live in the same handler -- registering them
# separately means the second silently disables the first and every run leaks a
# directory.
#
# A probe that dies under `set -e` before `check` runs takes the whole suite
# with it and prints nothing -- the shell twin of the aborted-case failure
# `tools/lib/harness.gd` exists to catch, where a case that never completes must
# not read as a pass. `st=$?` is captured before the `rm` so cleanup cannot
# overwrite the suite's own exit status.
verdict=""
finish() {
	st=$?
	rm -rf "$tmp"
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  stamp_version: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

cat >"$tmp/presets.cfg" <<'EOF'
[preset.0.options]

version/code=1
version/name="0.1.0"
package/unique_name="com.guillotinemods.godotdirectorplayer"
EOF

# Every probe is guarded with `if`. A bare `cmd; check ... $?` under
# `set -euo pipefail` kills the suite on the exact run where the check should
# have reported FAIL.
tools/ci/stamp_version.sh v0.2.0 41 "$tmp/presets.cfg" >/dev/null

if grep -Fqx 'version/code=41' "$tmp/presets.cfg"; then
	check "version/code takes the run number" 0
else
	check "version/code takes the run number" 1
fi

if grep -Fqx 'version/name="0.2.0"' "$tmp/presets.cfg"; then
	check "version/name drops the leading v" 0
else
	check "version/name drops the leading v" 1
fi

# Still a pattern rather than a literal: this one asserts the key survived, not
# what its value is.
if grep -q '^package/unique_name=' "$tmp/presets.cfg"; then
	check "neighbouring keys survive" 0
else
	check "neighbouring keys survive" 1
fi

# A non-numeric code would substitute happily and produce an APK Android will
# not take as an update, so it has to be refused rather than written.
if tools/ci/stamp_version.sh v0.3.0 not-a-number "$tmp/presets.cfg" >/dev/null 2>&1; then
	check "a non-numeric version code is refused" 1
else
	check "a non-numeric version code is refused" 0
fi

# A missing file is the same class of fault: silently stamping nothing would
# ship version/code=1 forever.
if tools/ci/stamp_version.sh v0.3.0 42 "$tmp/nope.cfg" >/dev/null 2>&1; then
	check "a missing presets file is refused" 1
else
	check "a missing presets file is refused" 0
fi

cat >"$tmp/pristine.cfg" <<'EOF'
[preset.0.options]

version/code=1
version/name="0.1.0"
package/unique_name="com.guillotinemods.godotdirectorplayer"
EOF

# The tag comes from $GITHUB_REF_NAME -- whoever pushes the tag picks it. These
# reached sed unescaped: `&` splices the whole matched line back into itself and
# leaves the file half-stamped, `|` is the sed delimiter.
#
# The pair matters. "is refused" alone is VACUOUS: the broken version also
# exited non-zero, because its own round-trip check caught the corruption after
# writing it. Only "the file is untouched" tells the two apart. An assertion
# that passes against the bug it was written for is worse than no assertion.
for bad in 'v1.0&2.0' 'v1.0|2.0' 'v1.0 2.0' 'v1.0;touch /tmp/stamp-pwned'; do
	cp "$tmp/pristine.cfg" "$tmp/guard.cfg"
	if tools/ci/stamp_version.sh "$bad" 42 "$tmp/guard.cfg" >/dev/null 2>&1; then
		check "a tag with metacharacters is refused ($bad)" 1
	else
		check "a tag with metacharacters is refused ($bad)" 0
	fi
	if cmp -s "$tmp/pristine.cfg" "$tmp/guard.cfg"; then
		check "the file is untouched after refusing ($bad)" 0
	else
		check "the file is untouched after refusing ($bad)" 1
	fi
done

# Missing arguments are bad input (2), not a bash expansion failure (1).
rc=0
tools/ci/stamp_version.sh >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "no arguments exits 2" 0
else
	check "no arguments exits 2" 1
fi

rc=0
tools/ci/stamp_version.sh v1.0.0 >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "one argument exits 2" 0
else
	check "one argument exits 2" 1
fi

echo ""
verdict=printed
if [ "$fail" -eq 0 ]; then echo "PASS  stamp_version"; else echo "FAIL  stamp_version"; fi
exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tools/ci/stamp_version_test.sh`

Expected: FAIL with `tools/ci/stamp_version.sh: No such file or directory`.

- [ ] **Step 3: Write the script**

Create `tools/ci/stamp_version.sh`:

```bash
#!/usr/bin/env bash
# Stamps the release version into the Android preset.
#
#   tools/ci/stamp_version.sh v0.2.0 41 [export_presets.cfg]
#
# Android refuses to install an update whose versionCode did not increase, so a
# preset shipping the committed `version/code=1` forever makes every release
# after the first uninstallable over its predecessor. That is the
# uninstall-first path that costs the player their saves, which is the whole
# reason the release keystore is a stored secret rather than a generated one.
#
# Writes in place, on a checkout CI is about to throw away. Not meant to be
# committed back.
#
# The tag arrives from `$GITHUB_REF_NAME`, which is whatever string the person
# pushing the tag chose, and it used to be spliced into a `|`-delimited sed
# script unescaped. A tag carrying `&` made sed splice the whole matched line
# back into itself and left the file half-stamped; a tag carrying `|` broke the
# delimiter. Both are refused up front rather than escaped, because a version
# name outside this charset is a mistake worth failing on, not a string worth
# quoting.
set -euo pipefail

usage() {
	echo "usage: stamp_version.sh <tag> <code> [presets-file]" >&2
	exit 2
}

[ "$#" -ge 2 ] || usage
tag=$1
code=$2
file=${3:-export_presets.cfg}

[ -n "$tag" ] || usage
[ -n "$code" ] || usage

# `v0.2.0` is the tag; `0.2.0` is what Android shows. Anything not starting with
# a `v` is left alone, so a `2026.1` scheme stamps as itself.
name=${tag#v}

case $code in
	'' | *[!0-9]*)
		echo "stamp_version: version code must be a positive integer, got '$code'" >&2
		exit 2
		;;
esac

case $name in
	'' | *[!A-Za-z0-9._+-]*)
		echo "stamp_version: version name must match [A-Za-z0-9._+-]+, got '$name'" >&2
		exit 2
		;;
esac

[ -f "$file" ] || {
	echo "stamp_version: no such file: $file" >&2
	exit 2
}

# `-i.bak` then remove: BSD sed needs the suffix, GNU sed accepts it, and this
# script runs on both a developer's macOS and the Linux runner.
sed -i.bak \
	-e "s|^version/code=.*|version/code=$code|" \
	-e "s|^version/name=.*|version/name=\"$name\"|" \
	"$file"
rm -f "$file.bak"

# A substitution that matched nothing exits 0, so the write is read back rather
# than assumed. `-Fqx` compares the written value as a literal whole line: a
# semver name is full of `.`, which as a BRE matches any character, so the
# pattern form of this check passed on values it had not actually written.
grep -Fqx "version/code=$code" "$file" || {
	echo "stamp_version: version/code did not take" >&2
	exit 1
}
grep -Fqx "version/name=\"$name\"" "$file" || {
	echo "stamp_version: version/name did not take" >&2
	exit 1
}

echo "stamped $file: version/name=\"$name\" version/code=$code"
```

- [ ] **Step 4: Make it executable and run the test**

Run:
```bash
chmod +x tools/ci/stamp_version.sh
bash tools/ci/stamp_version_test.sh
```

Expected: `PASS  stamp_version` with 5 `ok` lines.

- [ ] **Step 5: Commit**

```bash
git add tools/ci/stamp_version.sh tools/ci/stamp_version_test.sh
git commit
```

---

### Task 3: Refuse to publish an asset GitHub will not accept

The fat build is 3.2 GB of corpora plus a 269 MB pack. Samples compress to roughly 1.6 GB total, which fits under the 2 GiB asset cap, but whether the pack is compressed inside an APK at all is unverified. This gate is what says so, instead of a half-uploaded release.

**Files:**
- Create: `tools/ci/check_asset_size.sh`
- Create: `tools/ci/check_asset_size_test.sh`

**Interfaces:**
- Produces: `tools/ci/check_asset_size.sh <file>...`, exit 0 if every file exists and is at or under 2 GiB, 1 otherwise. Task 6 calls it with the Windows zip and the APK.

- [ ] **Step 1: Write the failing test**

Create `tools/ci/check_asset_size_test.sh`:

```bash
#!/usr/bin/env bash
# Checks the size gate against sparse fixtures either side of the limit.
#
#   bash tools/ci/check_asset_size_test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

# Sparse files: `dd` with a seek and no input allocates nothing on disk but
# reports the full size, which is all the gate reads.
dd if=/dev/null of="$tmp/small.apk" bs=1 seek=$((10 * 1024 * 1024)) 2>/dev/null
dd if=/dev/null of="$tmp/big.apk" bs=1 seek=$((2 * 1024 * 1024 * 1024 + 1)) 2>/dev/null

if tools/ci/check_asset_size.sh "$tmp/small.apk" >/dev/null 2>&1; then
	check "an asset under the limit passes" 0
else
	check "an asset under the limit passes" 1
fi

if tools/ci/check_asset_size.sh "$tmp/big.apk" >/dev/null 2>&1; then
	check "an asset over 2 GiB is refused" 1
else
	check "an asset over 2 GiB is refused" 0
fi

# One bad file among several must still fail the run, or a release goes out
# with one good asset and one that never uploaded.
if tools/ci/check_asset_size.sh "$tmp/small.apk" "$tmp/big.apk" >/dev/null 2>&1; then
	check "one oversize asset fails a multi-file check" 1
else
	check "one oversize asset fails a multi-file check" 0
fi

# An export that produced nothing must not read as a pass.
if tools/ci/check_asset_size.sh "$tmp/never-built.apk" >/dev/null 2>&1; then
	check "a missing asset is refused" 1
else
	check "a missing asset is refused" 0
fi

echo ""
if [ "$fail" -eq 0 ]; then echo "PASS  check_asset_size"; else echo "FAIL  check_asset_size"; fi
exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tools/ci/check_asset_size_test.sh`

Expected: FAIL with `tools/ci/check_asset_size.sh: No such file or directory`.

- [ ] **Step 3: Write the script**

Create `tools/ci/check_asset_size.sh`:

```bash
#!/usr/bin/env bash
# Refuses to publish an asset GitHub will not accept.
#
#   tools/ci/check_asset_size.sh build/android/GodotDirectorPlayer.apk ...
#
# A release asset is capped at 2 GiB. There is no cap on the number of assets,
# on total release size, or on download bandwidth, so this is the only size that
# matters.
#
# The fallback if it fires is not a larger limit, it is a narrower
# `include_filter`: `scenes/launcher/title_list.gd` describes shipping one title
# instead of six, and the launcher already hides what did not ship.
set -euo pipefail

LIMIT=$((2 * 1024 * 1024 * 1024))

fail=0
for f in "$@"; do
	if [ ! -f "$f" ]; then
		echo "FAIL  $f: not built"
		fail=1
		continue
	fi
	size=$(wc -c <"$f")
	mib=$((size / 1024 / 1024))
	if [ "$size" -gt "$LIMIT" ]; then
		echo "FAIL  $f: ${mib} MiB exceeds the 2048 MiB release-asset limit"
		fail=1
	else
		echo "ok    $f: ${mib} MiB"
	fi
done

exit "$fail"
```

- [ ] **Step 4: Make it executable and run the test**

Run:
```bash
chmod +x tools/ci/check_asset_size.sh
bash tools/ci/check_asset_size_test.sh
```

Expected: `PASS  check_asset_size` with 4 `ok` lines.

- [ ] **Step 5: Commit**

```bash
git add tools/ci/check_asset_size.sh tools/ci/check_asset_size_test.sh
git commit
```

---

### Task 4: Install a pinned Godot and its export templates

**Files:**
- Create: `tools/ci/install_godot.sh`
- Create: `tools/ci/install_godot_test.sh`
- Create: `tools/ci/write_editor_settings.sh`

**Interfaces:**
- Produces: `tools/ci/install_godot.sh <version> <bindir>` leaving an executable at `<bindir>/godot` and templates in `~/.local/share/godot/export_templates/<dotted-version>/`.
- Produces: `tools/ci/write_editor_settings.sh <android-sdk-path>` writing `~/.config/godot/editor_settings-4.7.tres`.

- [ ] **Step 1: Write the failing test**

The download is roughly 1 GB and the binary is Linux-only, so the local test checks the two things that actually break: shell syntax, and whether the pinned version's asset names still resolve. A renamed asset or a wrong version string is caught here rather than eight minutes into a CI run.

Create `tools/ci/install_godot_test.sh`:

```bash
#!/usr/bin/env bash
# Checks the installer without running it.
#
#   bash tools/ci/install_godot_test.sh
#
# The full install is Linux-only and about 1 GB, so this asserts the two things
# that break in practice: the script parses, and the pinned version's assets are
# still where the URLs say they are.
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=4.7.1-stable
BASE="https://github.com/godotengine/godot-builds/releases/download/$VERSION"

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

bash -n tools/ci/install_godot.sh
check "install_godot.sh parses" $?

for asset in "Godot_v${VERSION}_linux.x86_64.zip" "Godot_v${VERSION}_export_templates.tpz" "SHA512-SUMS.txt"; do
	curl -fsSLI -o /dev/null "$BASE/$asset"
	check "$asset resolves" $?
done

echo ""
if [ "$fail" -eq 0 ]; then echo "PASS  install_godot"; else echo "FAIL  install_godot"; fi
exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tools/ci/install_godot_test.sh`

Expected: FAIL on the first check, `install_godot.sh parses`, because the file does not exist.

- [ ] **Step 3: Write the installer**

Create `tools/ci/install_godot.sh`:

```bash
#!/usr/bin/env bash
# Installs a pinned Godot and its export templates on a Linux runner.
#
#   tools/ci/install_godot.sh 4.7.1-stable "$HOME/godot-bin"
#
# Pinned rather than latest: a binary and a template set that disagree fail the
# export outright, and `project.godot` declares 4.7. Fetched from
# `godotengine/godot-builds` directly rather than through a third-party setup
# action or container, so the version stays under our control and the only
# trust boundary is GitHub's own release hosting -- the same reasoning
# `titles/piposh-3d`'s `verify.yml` follows.
#
# Linux-only. `sha512sum` is GNU; the macOS spelling differs and this script is
# never run there. `tools/ci/install_godot_test.sh` is what a developer runs.
set -euo pipefail

version=${1:?usage: install_godot.sh <version, e.g. 4.7.1-stable> <bindir>}
bindir=${2:?usage: install_godot.sh <version> <bindir>}

# `4.7.1-stable` in the download URL is `4.7.1.stable` in the templates path.
dotted=${version//-/.}

base="https://github.com/godotengine/godot-builds/releases/download/$version"
bin_zip="Godot_v${version}_linux.x86_64.zip"
tpz="Godot_v${version}_export_templates.tpz"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "fetching $bin_zip and $tpz"
curl -fsSL --retry 3 -o "$work/$bin_zip" "$base/$bin_zip"
curl -fsSL --retry 3 -o "$work/$tpz" "$base/$tpz"
curl -fsSL --retry 3 -o "$work/SHA512-SUMS.txt" "$base/SHA512-SUMS.txt"

# Verify only the two lines we care about. Checking the whole manifest would
# fail on every asset we did not download.
(cd "$work" && grep -E "  (${bin_zip}|${tpz})\$" SHA512-SUMS.txt | sha512sum -c -)

mkdir -p "$bindir"
unzip -q -o "$work/$bin_zip" -d "$work/bin"
mv "$work/bin/Godot_v${version}_linux.x86_64" "$bindir/godot"
chmod +x "$bindir/godot"

# The .tpz is a zip whose entries live under `templates/`; Godot wants them
# directly inside a directory named for the dotted version.
templates="$HOME/.local/share/godot/export_templates/$dotted"
mkdir -p "$templates"
unzip -q -o "$work/$tpz" -d "$work/tpl"
mv "$work"/tpl/templates/* "$templates/"

"$bindir/godot" --version
echo "templates in $templates: $(find "$templates" -type f | wc -l) file(s)"
```

- [ ] **Step 4: Write the editor-settings script**

Create `tools/ci/write_editor_settings.sh`:

```bash
#!/usr/bin/env bash
# Tells a headless Godot where the Android SDK is.
#
#   tools/ci/write_editor_settings.sh "$ANDROID_SDK_ROOT"
#
# Godot documents the SDK path only as an Editor Settings field in the GUI.
# There is no environment variable for it, unlike the three keystore ones, so a
# runner has to be handed the settings file itself. Godot names that file for
# the major.minor it belongs to.
set -euo pipefail

sdk=${1:?usage: write_editor_settings.sh <android-sdk-path>}
[ -d "$sdk" ] || {
	echo "write_editor_settings: no such SDK directory: $sdk" >&2
	exit 2
}

dir="$HOME/.config/godot"
mkdir -p "$dir"
file="$dir/editor_settings-4.7.tres"

cat >"$file" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$sdk"
EOF

echo "wrote $file (android_sdk_path = $sdk)"
```

- [ ] **Step 5: Make them executable and run the test**

Run:
```bash
chmod +x tools/ci/install_godot.sh tools/ci/write_editor_settings.sh
bash tools/ci/install_godot_test.sh
bash -n tools/ci/write_editor_settings.sh && echo "write_editor_settings.sh parses"
```

Expected: `PASS  install_godot` with 4 `ok` lines, then `write_editor_settings.sh parses`.

- [ ] **Step 6: Commit**

```bash
git add tools/ci/install_godot.sh tools/ci/install_godot_test.sh tools/ci/write_editor_settings.sh
git commit
```

---

### Task 5: Create the keystore and load the four secrets

This is the one task a person does by hand. Nothing after it can be verified without it.

**Files:** none in the repo. The keystore must never be committed; `.gitignore` already excludes `android/*.keystore` and `android/*.jks`.

**Interfaces:**
- Produces: repository secrets `SUBMODULES_PAT`, `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, consumed by Task 6.

- [ ] **Step 1: Generate the keystore**

Godot exposes a single password for the release keystore via `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`, so the store password and the key password must be identical. `keytool` will silently accept different ones and the export will then fail on the key.

Run, choosing your own password:

```bash
mkdir -p ~/keys
read -rsp "keystore password: " KSPASS; echo
keytool -genkeypair -v \
  -keystore ~/keys/godot-director-player-release.keystore \
  -alias godot-director-player \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$KSPASS" -keypass "$KSPASS" \
  -dname "CN=Guillotine Mods, O=Guillotine Mods, C=IL"
```

- [ ] **Step 2: Verify the keystore reads back**

Run:
```bash
keytool -list -v -keystore ~/keys/godot-director-player-release.keystore -storepass "$KSPASS" | head -20
```

Expected: one entry with alias `godot-director-player`, `Entry type: PrivateKeyEntry`, and a validity of about 27 years.

Back this file up somewhere durable now. Losing it means never being able to ship an installable update to anyone who has the app.

- [ ] **Step 3: Create the fine-grained PAT**

At https://github.com/settings/personal-access-tokens/new, create a token with:
- Resource owner: `guillotine-mods`
- Repository access: only `piposh`, `piposh2`, `piposh-en`, `piposh-ru`, `rating`, `piposh-dream`, `piposh-3d`
- Permissions: Contents → Read-only
- Expiration: set a calendar reminder for the day before it lapses; an expired token fails the release build with a submodule clone error that reads like a network fault.

- [ ] **Step 4: Load all four secrets**

Run:
```bash
repo=guillotine-mods/godot-director-player
base64 -i ~/keys/godot-director-player-release.keystore | tr -d '\n' \
  | gh secret set ANDROID_KEYSTORE_B64 --repo "$repo"
printf '%s' "$KSPASS" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$repo"
printf '%s' "godot-director-player" | gh secret set ANDROID_KEY_ALIAS --repo "$repo"
gh secret set SUBMODULES_PAT --repo "$repo"   # paste the PAT when prompted
unset KSPASS
```

- [ ] **Step 5: Verify all four are present**

Run: `gh secret list --repo guillotine-mods/godot-director-player`

Expected: exactly `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `SUBMODULES_PAT`.

- [ ] **Step 6: Nothing to commit**

Confirm with `git status` that no keystore leaked into the working tree.

---

### Task 6: Wire the release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `tools/ci/install_godot.sh`, `tools/ci/write_editor_settings.sh`, `tools/ci/stamp_version.sh`, `tools/ci/check_asset_size.sh` (Tasks 2-4), and the four secrets (Task 5).

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/release.yml`:

```yaml
name: release

# Tag-only, deliberately. With no `pull_request` trigger the submodule PAT and
# the release keystore are unreachable from a fork PR by construction rather
# than by a setting somebody can relax later.
on:
  push:
    tags: ["v*"]

permissions:
  contents: write

env:
  GODOT_VERSION: 4.7.1-stable

jobs:
  release:
    name: Export and publish
    runs-on: ubuntu-latest
    steps:
      # The corpora are private repos and this one is public, so the default
      # GITHUB_TOKEN cannot read them. `fetch-depth: 1` because the submodule
      # checkout is roughly 3.8 GB and no history is needed to export.
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 1
          token: ${{ secrets.SUBMODULES_PAT }}

      # `gradle_build/use_gradle_build=false`, so Godot uses prebuilt templates
      # and needs only apksigner and zipalign, not a full Gradle build.
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - uses: android-actions/setup-android@v3

      - name: Cache Godot and export templates
        id: godot-cache
        uses: actions/cache@v4
        with:
          path: |
            ~/godot-bin
            ~/.local/share/godot/export_templates
          key: godot-${{ env.GODOT_VERSION }}

      - name: Install Godot
        if: steps.godot-cache.outputs.cache-hit != 'true'
        run: tools/ci/install_godot.sh "$GODOT_VERSION" "$HOME/godot-bin"

      - name: Put Godot on PATH
        run: echo "$HOME/godot-bin" >> "$GITHUB_PATH"

      - name: Point Godot at the Android SDK
        run: tools/ci/write_editor_settings.sh "$ANDROID_SDK_ROOT"

      - name: Decode the release keystore
        env:
          KEYSTORE_B64: ${{ secrets.ANDROID_KEYSTORE_B64 }}
        run: printf '%s' "$KEYSTORE_B64" | base64 -d > "$RUNNER_TEMP/release.keystore"

      - name: Stamp the release version
        run: tools/ci/stamp_version.sh "$GITHUB_REF_NAME" "$GITHUB_RUN_NUMBER"

      # A fresh checkout has no `.godot`, and without it `class_name` globals do
      # not resolve, so this has to precede every export.
      - name: Import
        run: godot --headless --path . --import

      # `titles/piposh-3d` is its own Godot project. Skipping this does not fail
      # anything: the launcher gates the embed tile on `ResourceLoader.exists()`,
      # so the 3D title would quietly not be in the release.
      - name: Build the piposh-3d pack
        run: |
          godot --headless --path titles/piposh-3d --import
          godot --headless --path titles/piposh-3d --export-pack Pack "$PWD/titles/piposh3d.pck"
          ls -lh titles/piposh3d.pck

      - name: Export Windows
        run: |
          mkdir -p build/pc
          godot --headless --path . --export-release "Windows Desktop" build/pc/GodotDirectorPlayer.exe

      # Release rather than debug: a debug export enables the remote debugger and
      # is larger. The three env vars override the export menu at export time, so
      # no secret is ever written into export_presets.cfg.
      - name: Export Android
        env:
          GODOT_ANDROID_KEYSTORE_RELEASE_PATH: ${{ runner.temp }}/release.keystore
          GODOT_ANDROID_KEYSTORE_RELEASE_USER: ${{ secrets.ANDROID_KEY_ALIAS }}
          GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
        run: |
          mkdir -p build/android
          godot --headless --path . --export-release "Android" build/android/GodotDirectorPlayer.apk

      # `binary_format/embed_pck=false`, so the .exe on its own is inert and
      # needs its .pck beside it.
      - name: Package the Windows build
        run: |
          cd build/pc
          zip -qr "../GodotDirectorPlayer-Windows-${GITHUB_REF_NAME}.zip" .

      - name: Check asset sizes
        run: |
          tools/ci/check_asset_size.sh \
            "build/GodotDirectorPlayer-Windows-${GITHUB_REF_NAME}.zip" \
            build/android/GodotDirectorPlayer.apk

      - uses: softprops/action-gh-release@v2
        with:
          fail_on_unmatched_files: true
          files: |
            build/GodotDirectorPlayer-Windows-${{ github.ref_name }}.zip
            build/android/GodotDirectorPlayer.apk
```

- [ ] **Step 2: Lint it**

Run:
```bash
command -v actionlint >/dev/null && actionlint .github/workflows/release.yml || \
  python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml parses')"
```

Expected: no output from `actionlint`, or `yaml parses`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit
```

---

### Task 7: Prove it end to end and record the size

Nothing before this has run the export. The measurement the spec left open is settled here.

**Files:**
- Modify: `docs/superpowers/specs/2026-08-10-godot-export-ci-design.md` (the "Known risk: artifact size" section)

- [ ] **Step 1: Push a throwaway tag**

```bash
git push origin main
git tag v0.0.1-ci1
git push origin v0.0.1-ci1
```

- [ ] **Step 2: Watch the run**

Run: `gh run watch --repo guillotine-mods/godot-director-player`

Expected: every step green. The likeliest first failure is the editor-settings file, since Godot documents no headless channel for the SDK path; if the Android export reports a missing SDK, that step is where to iterate.

- [ ] **Step 3: Read the sizes off the run**

Run: `gh run view --repo guillotine-mods/godot-director-player --log | grep -A3 "Check asset sizes"`

Record both numbers. This is the measurement the spec could not make locally.

- [ ] **Step 4: Verify the release actually carries both assets**

Run:
```bash
gh release view v0.0.1-ci1 --repo guillotine-mods/godot-director-player \
  --json assets --jq '.assets[] | "\(.name) \(.size/1048576|floor)MB"'
```

Expected: two assets, a Windows zip and an APK, both non-trivial in size. An APK under 500 MB means the corpora did not make it in and the include filters need rechecking.

- [ ] **Step 5: Verify the APK signature is the release key, not a debug key**

Run:
```bash
gh release download v0.0.1-ci1 --repo guillotine-mods/godot-director-player --pattern '*.apk' --dir /tmp/apkcheck
apksigner verify --print-certs /tmp/apkcheck/*.apk | head
```

Expected: the certificate DN reads `CN=Guillotine Mods`, not `CN=Android Debug`. A debug certificate here means the env vars did not take and every future update would break.

- [ ] **Step 6: Record the measurement in the spec**

Replace the "whether the exported pack is compressed at all is unverified" paragraph in `docs/superpowers/specs/2026-08-10-godot-export-ci-design.md` with the measured sizes and what they mean for headroom. If the APK came in over 2 GiB, the size gate will have failed the run instead, and the follow-up is the per-title `include_filter` narrowing the spec names.

- [ ] **Step 7: Clean up the test release and tag**

```bash
gh release delete v0.0.1-ci1 --repo guillotine-mods/godot-director-player --yes --cleanup-tag
git tag -d v0.0.1-ci1
```

- [ ] **Step 8: Commit the recorded measurement**

```bash
git add docs/superpowers/specs/2026-08-10-godot-export-ci-design.md
git commit
```
