extends Node
## Mounts `titles/piposh3d.pck`, the Piposh 3D title, into `res://`.
##
## **Listed first in `project.godot`, and that is load-bearing rather than
## tidy.** The four autoloads after it -- `Piposh3DState`, `LevelRouter`,
## `AudioChannels`, `PiposhDebug` -- are that title's, and their scripts exist
## only inside this pack. Autoloads are instantiated in declaration order, so
## they resolve if and only if the mount has already happened. Measured on a
## scratch project: an autoload whose script lives only in a pack instantiates
## correctly behind a pack-mounting autoload, and a script naming it as a global
## identifier compiles and runs.
##
## **`replace_files` is false, so the player's own files win every collision.**
## The two `res://` namespaces overlap on `icon.svg` and `project.godot`, and a
## pack additionally carries `project.binary`, `.godot/uid_cache.bin` and
## `.godot/global_script_class_cache.cfg`. That last one is why `false` is not
## negotiable: the player's global classes -- `DirectorPaths` and the rest --
## resolve through its own cache, and letting a title's cache replace it would
## break the engine the same way a fresh worktree does before `--import`.
##
## The title itself carries no `class_name` at all, for the other half of that
## same fact: a global class inside a mounted pack never resolves, because the
## host's cache is authoritative and packs do not merge into it. Piposh 3D uses
## `const X = preload(...)` throughout instead.
##
## A missing pack is not an error worth stopping for -- a build that ships only
## the Director titles is a legitimate build -- but it is worth saying out loud,
## because the four autoloads after this one will then fail noisily and the
## reason would otherwise be unobvious.

const PACK_PATH := "res://titles/piposh3d.pck"

## Whether the title is available this run. The launcher asks before offering a
## tile: a tile that cannot launch is worse than no tile.
static var mounted := false


func _init() -> void:
	if not FileAccess.file_exists(PACK_PATH):
		print("[piposh3d] no pack at %s; the 3D title is not in this build" % PACK_PATH)
		return
	mounted = ProjectSettings.load_resource_pack(PACK_PATH, false)
	if mounted:
		print("[piposh3d] mounted %s" % PACK_PATH)
	else:
		push_warning("[piposh3d] pack present but would not mount: %s" % PACK_PATH)
