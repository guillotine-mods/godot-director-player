#!/usr/bin/env bash
# Release notes for a tag, built from the commits since the previous one.
#
#   tools/ci/release_notes.sh v0.4.0-alpha [previous-tag]
#
# Writes markdown to stdout. The previous tag is resolved from history when it is
# not given, so the only required argument is the tag being released.
#
# **Why not `gh release create --generate-notes`.** GitHub's generator builds its
# changelog out of merged pull requests, and this repo pushes to `main` directly.
# Measured rather than assumed: the `releases/generate-notes` API was called for
# `v0.3.0-alpha..v0.3.1-alpha` and for `v0.3.1-alpha..main`, and both returned a
# compare link and nothing else -- the last merged PR was #15 on 2026-08-08, four
# tags and fifty-five commits ago. A `.github/release.yml` category config would
# change nothing either, because it categorises the same empty PR list.
#
# So the commits are the only source. Two consequences shape the rest of this
# file. Their subjects are written as findings rather than as changelog entries,
# which is right for `git log` and long for a release page; and a batch is mostly
# harness work -- fifty-one tool files against forty engine files in the range
# this was written for. A flat list buries the four commits a player would notice
# under thirty-one they would not, so the group is derived from the paths each
# commit touched and the engine goes first, uncollapsed.
#
# Nothing is dropped. The rest is inside a `<details>` block, which is a reading
# order and not a filter: a release note that silently omits work is one nobody
# can use to answer "when did that change".
set -euo pipefail

if [ "$#" -lt 1 ]; then
	echo "usage: tools/ci/release_notes.sh <tag> [previous-tag]" >&2
	exit 1
fi

TAG=$1
PREVIOUS=${2:-}

# Resolved from HEAD rather than from `$TAG`, because this runs in both of the
# two states the release workflow has: a pushed tag, where HEAD *is* `$TAG` and
# the previous tag is the one before it; and a dispatch dry run on `main`, where
# `$TAG` does not exist as a ref at all and the previous tag is simply the latest
# one. `--exact-match` is what tells those apart, and asking it is cheaper than
# asking the caller to know which case it is in.
if [ -z "$PREVIOUS" ]; then
	if git describe --tags --exact-match HEAD >/dev/null 2>&1; then
		PREVIOUS=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)
	else
		PREVIOUS=$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)
	fi
fi

# A shallow clone is the failure this catches. `actions/checkout` defaults to
# `fetch-depth: 1`, which leaves no tags and one commit, and the range below
# would then quietly resolve to nothing and publish empty notes -- the exact
# shape of failure that reads as "there were no changes".
if [ "$(git rev-list --count HEAD 2>/dev/null || echo 0)" -le 1 ]; then
	echo "FAIL  release_notes: history is shallow; this needs fetch-depth: 0" >&2
	exit 1
fi

if [ -n "$PREVIOUS" ]; then
	RANGE="$PREVIOUS..HEAD"
else
	# The first release has no predecessor, and refusing here would mean the
	# very first tag could not be cut by the same path as every later one.
	RANGE="HEAD"
fi

repo=${GITHUB_REPOSITORY:-}
if [ -z "$repo" ]; then
	# Derived so the script is runnable and testable outside Actions. Both SSH
	# and HTTPS remotes reduce to `owner/name`.
	origin=$(git config --get remote.origin.url 2>/dev/null || true)
	repo=$(printf '%s' "$origin" | sed -e 's#^git@[^:]*:##' -e 's#^https\{0,1\}://[^/]*/##' -e 's#\.git$##')
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for area in engine build tools docs other; do
	: >"$tmp/$area"
done

# The paths a commit touched decide its group. A commit that touched more than
# one area is filed under the first match in this order, engine first, because
# "did this change the player's experience" is the question the grouping is for
# and any engine file in the commit answers it yes.
classify() { # classify < paths
	local p engine=0 build=0 tools=0 docs=0
	while IFS= read -r p; do
		[ -n "$p" ] || continue
		case $p in
			director/*|scenes/*|autoload/*|lingo/*|data/*|titles/*)
				engine=1 ;;
			.github/*|tools/ci/*|gate.sh|gate_env.sh|check.sh|build_pack.sh|project.godot|export_presets.cfg|director_game.cfg)
				build=1 ;;
			tools/*|pre-tools/*|scripts/*|reference/*)
				tools=1 ;;
			docs/*|openspec/*|*.md)
				docs=1 ;;
		esac
	done
	if [ "$engine" = 1 ]; then echo engine
	elif [ "$build" = 1 ]; then echo build
	elif [ "$tools" = 1 ]; then echo tools
	elif [ "$docs" = 1 ]; then echo docs
	else echo other
	fi
}

# `%x1f` is the unit separator, and it is here because a subject may contain
# anything a human types -- this corpus has subjects holding colons, backticks,
# quotes and commas. A separator that cannot occur in the text is the only one
# that does not need escaping rules nobody will remember.
#
# Read from a process substitution rather than a pipe: a `while` on the right of
# a pipe runs in a subshell, and every count accumulated in it would be
# discarded at the loop's end.
total=0
while IFS=$'\x1f' read -r sha subject; do
	[ -n "$sha" ] || continue
	area=$(git show --name-only --format= "$sha" | classify)
	printf -- '- %s (%s)\n' "$subject" "${sha:0:8}" >>"$tmp/$area"
	total=$((total + 1))
done < <(git log --reverse --format="%H%x1f%s" "$RANGE")

count() { wc -l <"$tmp/$1" | tr -d ' '; }

emit() { # emit <file> <heading>
	if [ -s "$tmp/$1" ]; then
		printf '### %s\n\n' "$2"
		cat "$tmp/$1"
		printf '\n'
	fi
}

if [ "$total" -eq 0 ]; then
	# Not an error: a tag cut at the same commit as the last one is a real thing
	# to do (a re-release, a corrected asset). Saying so beats an empty page.
	printf 'No commits between %s and %s.\n' "${PREVIOUS:-the start of history}" "$TAG"
else
	if [ -s "$tmp/engine" ]; then
		printf '## Engine\n\n'
		cat "$tmp/engine"
		printf '\n'
	fi

	rest=$((total - $(count engine)))
	if [ "$rest" -gt 0 ]; then
		printf '<details>\n<summary>Harness, build and documentation (%d commits)</summary>\n\n' "$rest"
		emit tools "Harness and tooling"
		emit build "Build and CI"
		emit docs "Documentation"
		emit other "Elsewhere"
		printf '</details>\n'
	fi
fi

# The right-hand side of the compare link is the tag when the tag exists and the
# commit when it does not. A dispatch dry run stamps `0.0.0-dryrun` by default and
# creates no ref, so naming the tag there would put a 404 into the one output a
# dry run exists to let somebody read.
if [ -n "$PREVIOUS" ] && [ -n "$repo" ]; then
	if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
		head_ref=$TAG
	else
		head_ref=$(git rev-parse HEAD)
	fi
	printf '\n**Full Changelog**: https://github.com/%s/compare/%s...%s\n' \
		"$repo" "$PREVIOUS" "$head_ref"
fi
