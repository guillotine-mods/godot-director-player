#!/bin/bash
# Builds `titles/piposh3d.pck`, the Piposh 3D title, out of `titles/piposh-3d`.
#
#   bash build_pack.sh
#
# The parent mounts that pack at startup (`autoload/piposh3d_pack.gd`) and the
# launcher offers a tile for it only once it has mounted. Without the pack the
# 3D title is simply absent from the shelf -- and, less quietly, the four
# autoloads whose scripts live *inside* the pack fail to instantiate, so every
# run of the player and every harness prints twelve engine ERROR lines before it
# starts. `gate.sh` counts errors, so an unbuilt pack is noise in every gate.
#
# It is not built by `gate.sh` and not committed. `.gitignore` excludes it
# because it is not new data -- the same bytes already arrive with the
# `titles/piposh-3d` submodule, and this is only the import saved ahead of time
# -- but that meant nothing on a fresh checkout produced it either, and the step
# lived in a design document instead of in a file anybody would run. This is
# that step, and running it twice is harmless.
#
# Two commands and not one. The export reads the child's `.godot/`, which a
# fresh checkout of a submodule does not have, and an export from an unimported
# project produces a pack missing its imported resources rather than an error.
# The import is the slow half (4,879 `.import` files, ~564 MB of source assets)
# and is skipped when the child has been imported already; pass --reimport to
# force it, which is what to do after pulling the submodule.
# No `set -u`: `gate_env.sh` reads `$GODOT` to let a machine pin a build, and an
# unset one is the normal case rather than a mistake.
cd "$(dirname "$0")" || exit 1
. ./gate_env.sh

CHILD=titles/piposh-3d
# Absolute, because `--export-pack`'s output path is resolved against the
# *exported* project's directory and not the shell's. A relative path here
# writes the pack inside `titles/piposh-3d/titles/`, where nothing mounts it and
# the child's own `.gitignore` does not cover it.
PACK="$PWD/titles/piposh3d.pck"
# Exported here and renamed onto `$PACK` only once it is whole, so a reader that
# starts mid-build never mounts a partial pack. Ends in `.pck` because
# `--export-pack` refuses any other extension, which also keeps it inside
# `.gitignore`'s `titles/*.pck`. `autoload/piposh3d_pack.gd` does the same, and
# the two have to agree: either can be the one building when the other looks.
BUILDING="$PWD/titles/piposh3d.building.pck"

REIMPORT=0
for arg in "$@"; do
	case "$arg" in
		--reimport) REIMPORT=1 ;;
		*) echo "build_pack: unknown argument '$arg'" >&2; exit 1 ;;
	esac
done

if [ ! -f "$CHILD/project.godot" ]; then
	echo "build_pack: $CHILD is empty. Run: git submodule update --init $CHILD" >&2
	exit 1
fi
# The preset is named in the child and committed there, so this script names it
# once and the child owns what it contains.
if ! grep -q '^name="Pack"' "$CHILD/export_presets.cfg" 2>/dev/null; then
	echo "build_pack: $CHILD/export_presets.cfg has no preset called 'Pack'" >&2
	exit 1
fi

G=$(gate_find_godot) || exit 1
gate_announce_godot "$G"

if [ "$REIMPORT" = 1 ] || [ ! -d "$CHILD/.godot" ]; then
	echo "build_pack: importing $CHILD (minutes, once per checkout)"
	if ! "$G" --headless --path "$CHILD" --import >/dev/null 2>&1; then
		echo "build_pack: the import failed. Re-run it without the redirect to see why:" >&2
		echo "  $G --headless --path $CHILD --import" >&2
		exit 1
	fi
else
	echo "build_pack: $CHILD is imported already (--reimport to redo it)"
fi

echo "build_pack: exporting Pack -> $PACK"
if ! "$G" --headless --path "$CHILD" --export-pack Pack "$BUILDING" >/dev/null 2>&1; then
	echo "build_pack: the export failed. Re-run it without the redirect to see why:" >&2
	echo "  $G --headless --path $CHILD --export-pack Pack $BUILDING" >&2
	rm -f "$BUILDING"
	exit 1
fi

# Godot reports success on an export that wrote nothing useful, so the size is
# checked rather than the exit code alone. The real pack is ~269 MB; anything
# under a megabyte is an export that found no imported resources, which is the
# unimported-child failure this script's two-step exists to prevent.
if [ ! -f "$BUILDING" ]; then
	echo "build_pack: the export reported success and wrote no pack" >&2
	exit 1
fi
bytes=$(wc -c <"$BUILDING" | tr -d ' ')
if [ "$bytes" -lt 1000000 ]; then
	echo "build_pack: the pack is only $bytes bytes, so the export found no assets." >&2
	echo "build_pack: re-run with --reimport." >&2
	rm -f "$BUILDING"
	exit 1
fi
# Only now does the name anything mounts start existing.
mv "$BUILDING" "$PACK"
# The commit this pack was built from, so `autoload/piposh3d_pack.gd` can notice
# a submodule bump and rebuild by itself. Written by both builders, or a pack
# made here would look stale to the engine and be rebuilt on the next run.
if head=$(git -C "$CHILD" rev-parse HEAD 2>/dev/null); then
	printf '%s' "$head" >"$PACK.stamp"
fi
echo "build_pack: wrote $((bytes / 1048576)) MB to $PACK"
