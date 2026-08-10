#!/bin/bash
# Shared by gate.sh and check.sh. Sourced, not run.
#
# Both scripts used to carry their own copy of everything below, and every copy
# named one machine: an absolute checkout path, a Windows Godot build and GNU
# `timeout`. That is three assumptions per script and six to keep in step, so
# they are here once instead. Callers cd to the repo root first and then:
#
#   . ./gate_env.sh
#
# Nothing here knows which game is loaded, or that this port is a Director one.

# Where Godot is, in the order worth trying.
#
# $GODOT wins, so a machine with several builds -- or a version being tried
# against this port -- needs no edit here. Then PATH, then where each OS
# actually puts it.
#
# The Windows entry prefers a *console* build, and that is not cosmetic: the
# plain build detaches from the terminal, so `$(...)` captures nothing and every
# harness reads as ERROR with no output to say why.
gate_find_godot() {
	local candidate
	if [ -n "$GODOT" ]; then
		if [ -x "$GODOT" ]; then printf '%s\n' "$GODOT"; return 0; fi
		if command -v "$GODOT" >/dev/null 2>&1; then command -v "$GODOT"; return 0; fi
		echo "gate: \$GODOT is set to '$GODOT', which is not an executable" >&2
		return 1
	fi
	for candidate in godot godot4; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return 0
		fi
	done
	for candidate in \
		/Applications/Godot.app/Contents/MacOS/Godot \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		/opt/homebrew/bin/godot \
		/usr/local/bin/godot \
		"/c/Program Files"/Godot*/*console*.exe \
		"/c/Program Files"/Godot*/*.exe
	do
		if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
	done
	echo "gate: no Godot found on PATH or in the usual install locations." >&2
	echo "gate: set GODOT to the binary, e.g. GODOT=/path/to/godot bash gate.sh" >&2
	return 1
}


# `4.7.1.stable.official.<hash>`. `tr -d '\r'` because git-bash hands back the
# Windows line ending, which turns every downstream comparison into a mismatch
# that prints identically to a match.
gate_godot_version() {
	"$1" --version 2>/dev/null | tr -d '\r' | tail -1
}


# Say which engine produced the numbers, every run.
#
# A gate run against another Godot is a different measurement, and the output
# is the only place that can record which one it was -- the scripts no longer
# name a version, so nothing else does. A mismatch warns rather than refuses,
# because trying the next Godot against this port is a thing worth doing and
# should not need a script edit.
gate_announce_godot() {
	local version
	version=$(gate_godot_version "$1")
	echo "godot: $1 ($version)"
	case "$version" in
		4.7.*) ;;
		"") echo "gate: '$1' did not answer --version; expect every harness to ERROR" >&2 ;;
		*)  echo "gate: this port is developed against 4.7.x; $version is a different measurement" >&2 ;;
	esac
}


# Build `titles/piposh3d.pck` if it is not there, before anything measures.
#
# **This is a precondition of the measurement and not a convenience.** The four
# autoloads after `Piposh3DPack` in `project.godot` have their scripts *inside*
# that pack, so without it every harness -- all of them, not just the launcher's
# -- opens with twelve engine `ERROR` lines before its first check. `gate.sh`
# greps output for errors, so an unbuilt pack does not merely add noise: it puts
# twelve false ones into every entry of a suite whose whole job is to say which
# entries are clean.
#
# The pack is gitignored, correctly -- it is the submodule's own bytes with the
# import saved ahead of time, not new data -- so a clean clone never has one and
# the build step is exactly the kind nobody remembers. Hence here, in the two
# scripts everybody does run, rather than in a document.
#
# Only when missing. The export is ~269 MB and the first one also pays a
# multi-minute submodule import; paying that on every gate run to rebuild bytes
# that have not changed would be its own bad trade. A submodule bump therefore
# needs `bash build_pack.sh --reimport` by hand -- this cannot tell a stale pack
# from a current one, and guessing from mtimes would rebuild on every checkout.
#
# Never fatal. A checkout without the submodule is a legitimate one, and the
# Director titles -- which is every harness in `ALL` -- do not need the pack to
# run. It says what it did either way, because a gate that silently spent four
# minutes building something is worse than one that spent them loudly.
gate_require_pack() {
	# Staleness and not just absence, and this is the half with teeth. The
	# autoload rebuilds a stale pack by itself, which is right for a normal run
	# and wrong here: it would spend those minutes *inside* the first harness,
	# under `gate_run_capped`'s ceiling -- 120s in `check.sh` -- and the run would
	# be killed and reported as that harness failing. Rebuilding out here keeps
	# the cap measuring what it is for.
	if [ -f titles/piposh3d.pck ]; then
		local head stamp
		head=$(git -C titles/piposh-3d rev-parse HEAD 2>/dev/null) || return 0
		stamp=$(cat titles/piposh3d.pck.stamp 2>/dev/null) || return 0
		[ "$head" = "$stamp" ] && return 0
		echo "gate: titles/piposh-3d moved since the pack was built; rebuilding."
		bash build_pack.sh || echo "gate: the pack rebuild failed; it will be stale." >&2
		return 0
	fi
	if [ ! -f titles/piposh-3d/project.godot ]; then
		echo "gate: titles/piposh-3d is not checked out; skipping the 3D pack." >&2
		echo "gate: expect [piposh3d] autoload errors in every harness below." >&2
		return 0
	fi
	echo "gate: titles/piposh3d.pck is missing; building it once (minutes)."
	if bash build_pack.sh; then
		return 0
	fi
	echo "gate: the pack build failed. Harnesses will run, with [piposh3d] errors." >&2
	return 0
}


# `gate_run_capped SECONDS cmd...`, on a platform with a `timeout` and on one
# without.
#
# macOS ships neither `timeout` nor coreutils' `gtimeout` by default, and the
# ceiling is not decoration: a headless run contending with an open editor over
# .godot/ hangs indefinitely rather than failing (AGENTS.md), and several
# harnesses now sweep the whole corpus.
#
# Returns 124 on expiry, which is what GNU timeout returns and what gate.sh
# tests for. Without that the caller cannot tell a hang from a crash, and the
# script's own history says which way it guesses: `movie_churn` was called
# flaky because a timeout printed as ERROR.
gate_run_capped() {
	local secs="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
	if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi

	# The shim. Deliberately bash 3.2, which is what /bin/bash is on macOS:
	# no `wait -n`, no associative arrays.
	"$@" &
	local pid=$!
	local waited=0
	while [ "$waited" -lt "$secs" ]; do
		kill -0 "$pid" 2>/dev/null || break
		sleep 1
		waited=$((waited + 1))
	done
	if kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null
		sleep 2
		kill -9 "$pid" 2>/dev/null
		wait "$pid" 2>/dev/null
		return 124
	fi
	wait "$pid"
	return $?
}
