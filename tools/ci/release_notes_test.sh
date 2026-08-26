#!/usr/bin/env bash
# Checks the notes generator against a purpose-built history.
#
#   bash tools/ci/release_notes_test.sh
#
# A fixture repository rather than this one: the assertions here are about
# grouping, accounting and quoting, and pinning them to real commits would make
# the suite fail every time somebody pushes.
set -euo pipefail
cd "$(dirname "$0")/../.."

SCRIPT_UNDER_TEST=$PWD/tools/ci/release_notes.sh

tmp=$(mktemp -d)

# One EXIT trap only, matching tools/ci/check_asset_size_test.sh: cleanup and the
# abort guard share a single handler, or a second `trap ... EXIT` would silently
# disable the first and leak $tmp every run.
verdict=""
finish() {
	st=$?
	rm -rf "$tmp"
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  release_notes: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

# `-c` on every invocation rather than a global: the suite must not depend on
# whoever runs it having a git identity, and must not write one into their
# config. Signing is off for the same reason -- a developer with `commit.gpgsign`
# on would otherwise be prompted by a test suite.
git_() { git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "${@:2}"; }

commit() { # commit <repo> <path> <subject>
	mkdir -p "$1/$(dirname "$2")"
	echo "$RANDOM" >>"$1/$2"
	git_ "$1" add -A
	git_ "$1" commit -q -m "$3"
}

# ------------------------------------------------------------------ the fixture

r=$tmp/repo
mkdir -p "$r"
git_ "$r" init -q -b main
commit "$r" README.md "the first commit"
git_ "$r" tag v0.1.0

commit "$r" tools/probe.gd "a harness lands"
commit "$r" director/director_cast.gd "the cast reads a member: with a colon, a \`backtick\` and a \"quote\""
commit "$r" docs/ENGINE.md "docs only"
commit "$r" gate.sh "the gate gains an entry"
# Touches both areas at once, which is the precedence case.
mkdir -p "$r/scenes" "$r/tools"
echo x >>"$r/scenes/thing.gd"
echo y >>"$r/tools/thing.gd"
git_ "$r" add -A
git_ "$r" commit -q -m "engine and harness in one commit"
git_ "$r" tag v0.2.0

out=$(cd "$r" && GITHUB_REPOSITORY=o/n bash "$SCRIPT_UNDER_TEST" v0.2.0 v0.1.0)

# --------------------------------------------------------------- the assertions

if [ "$#" -ge 0 ] && ! bash "$SCRIPT_UNDER_TEST" >/dev/null 2>&1; then
	check "no arguments is refused, not a silent empty page" 0
else
	check "no arguments is refused, not a silent empty page" 1
fi

# A shallow clone must fail loudly. `fetch-depth: 1` leaves exactly one commit,
# and notes generated from it would be empty and read as "nothing changed".
s=$tmp/shallow
mkdir -p "$s"
git_ "$s" init -q -b main
commit "$s" README.md "only commit"
if (cd "$s" && bash "$SCRIPT_UNDER_TEST" v0.1.0 >/dev/null 2>&1); then
	check "a shallow history is refused rather than reported as no changes" 1
else
	check "a shallow history is refused rather than reported as no changes" 0
fi

# The accounting check, and the reason this suite exists. Five commits are in
# range and five bullets must be printed: a grouping bug that drops an area is
# invisible in a spot check and obvious here.
bullets=$(printf '%s\n' "$out" | grep -c '^- ' || true)
check "every commit in range is listed once (5 bullets, got $bullets)" \
	"$([ "$bullets" -eq 5 ] && echo 0 || echo 1)"

printf '%s\n' "$out" | grep -q '^## Engine' \
	&& check "the engine section is a visible heading" 0 \
	|| check "the engine section is a visible heading" 1

printf '%s\n' "$out" | grep -q '<summary>Harness, build and documentation (3 commits)</summary>' \
	&& check "the rest is collapsed and its count excludes the engine commits" 0 \
	|| check "the rest is collapsed and its count excludes the engine commits" 1

# Precedence: a commit touching an engine path and a tools path is engine. Read
# by line number rather than by presence, because both strings appear either way
# and only the order distinguishes a correct grouping from a wrong one.
engine_at=$(printf '%s\n' "$out" | grep -n '^## Engine' | cut -d: -f1)
details_at=$(printf '%s\n' "$out" | grep -n '^<details>' | cut -d: -f1)
mixed_at=$(printf '%s\n' "$out" | grep -n 'engine and harness in one commit' | cut -d: -f1)
if [ -n "$mixed_at" ] && [ "$mixed_at" -gt "$engine_at" ] && [ "$mixed_at" -lt "$details_at" ]; then
	check "a commit touching engine and tools is filed under Engine" 0
else
	check "a commit touching engine and tools is filed under Engine" 1
fi

# The `%x1f` separator's whole purpose: a subject holding the characters a human
# actually types must arrive whole.
printf '%s\n' "$out" | grep -qF 'the cast reads a member: with a colon, a `backtick` and a "quote"' \
	&& check "a subject with a colon, a backtick and a quote survives intact" 0 \
	|| check "a subject with a colon, a backtick and a quote survives intact" 1

printf '%s\n' "$out" | grep -qF '**Full Changelog**: https://github.com/o/n/compare/v0.1.0...v0.2.0' \
	&& check "the compare link names both tags" 0 \
	|| check "the compare link names both tags" 1

# The previous tag is resolved, not required. On a dry run there is no tag at
# HEAD and the answer is the latest tag; with a tag at HEAD it is the one before.
commit "$r" tools/after.gd "a commit after the tag"
resolved=$(cd "$r" && GITHUB_REPOSITORY=o/n bash "$SCRIPT_UNDER_TEST" v0.3.0)
printf '%s\n' "$resolved" | grep -qF 'compare/v0.2.0...' \
	&& check "an untagged HEAD resolves the previous tag as the latest one" 0 \
	|| check "an untagged HEAD resolves the previous tag as the latest one" 1
bullets=$(printf '%s\n' "$resolved" | grep -c '^- ' || true)
check "and lists only what came after it (1 bullet, got $bullets)" \
	"$([ "$bullets" -eq 1 ] && echo 0 || echo 1)"

# A tag that does not exist yet -- every dispatch dry run -- must not put a dead
# ref in the compare link, because the summary is the only place a dry run's notes
# can be read.
sha=$(git_ "$r" rev-parse HEAD)
dry=$(cd "$r" && GITHUB_REPOSITORY=o/n bash "$SCRIPT_UNDER_TEST" 0.0.0-dryrun)
printf '%s\n' "$dry" | grep -qF "compare/v0.2.0...$sha" \
	&& check "an unborn tag compares against the commit, not a 404" 0 \
	|| check "an unborn tag compares against the commit, not a 404" 1

# Two tags on one commit -- a re-release for a corrected asset -- leaves an empty
# range, and it must say so. An empty page here would read as a generator failure
# rather than as the deliberate thing it is.
git_ "$r" tag v0.4.0
git_ "$r" tag v0.5.0
empty=$(cd "$r" && GITHUB_REPOSITORY=o/n bash "$SCRIPT_UNDER_TEST" v0.5.0 v0.4.0)
printf '%s\n' "$empty" | grep -qi 'no commits between' \
	&& check "a range with no commits says so instead of printing nothing" 0 \
	|| check "a range with no commits says so instead of printing nothing" 1

echo ""
if [ "$fail" -eq 0 ]; then
	verdict=PASS
	echo "PASS  release_notes"
else
	verdict=FAIL
	echo "FAIL  release_notes"
fi
exit "$fail"
