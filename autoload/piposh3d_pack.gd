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
const CHILD_PATH := "res://titles/piposh-3d"

## Exported next to the real name and renamed onto it, so nothing ever mounts a
## pack that is still being written. Two harnesses started at once on a checkout
## with no pack would otherwise have one reading the file while the other is
## still producing it.
##
## It ends in `.pck` and not in `.building`, because `--export-pack` validates
## the extension and refuses anything else -- measured: `Export path "…
## piposh3d.pck.building" doesn't end with a supported extension`. The name still
## sorts beside the real one and is still covered by `titles/*.pck` in
## `.gitignore`, which a `.building` suffix would not have been.
const BUILDING_PATH := "res://titles/piposh3d.building.pck"

## The submodule commit the pack beside it was built from.
##
## This is what makes a *stale* pack detectable, and it is worth saying why the
## obvious alternative does not work: mtimes cannot answer this. A checkout
## rewrites them, a fresh clone gives every file the same one, and a pack that is
## newer than the sources it was built from is the normal case rather than the
## suspicious one. A commit hash is exact, cheap, and already the thing that
## changed when the submodule moved.
##
## The *checked-out* commit and not the gitlink the parent records. Those differ
## precisely when somebody has bumped the submodule pointer without running
## `git submodule update`, and the pack has to match the source that is on disc,
## which is the checked-out one.
const STAMP_PATH := "res://titles/piposh3d.pck.stamp"

## Whether the title is available this run. The launcher asks before offering a
## tile: a tile that cannot launch is worse than no tile.
static var mounted := false


func _init() -> void:
	# The editor check is here rather than inside `_build`, so that `_stale` --
	# which shells out to `git` -- never runs in a shipped build either. There it
	# would be a subprocess per launch to answer a question with no consequence:
	# an export carries its pack inside itself, cannot write `res://`, and has no
	# submodule to compare against.
	if _buildable() and (not FileAccess.file_exists(PACK_PATH) or _stale()):
		_build()
	if not FileAccess.file_exists(PACK_PATH):
		# The four autoloads after this one are about to fail with twelve engine
		# ERROR lines that say only "File not found" and name scripts that are not
		# on disc. Whoever reads that needs the reason on the line above it, not in
		# a document they do not know to open.
		print("[piposh3d] no pack at %s; the 3D title is missing from the launcher."
			% PACK_PATH)
		print("[piposh3d] run `bash build_pack.sh` to build it from titles/piposh-3d.")
		return
	mounted = ProjectSettings.load_resource_pack(PACK_PATH, false)
	if mounted:
		print("[piposh3d] mounted %s" % PACK_PATH)
	else:
		push_warning("[piposh3d] pack present but would not mount: %s" % PACK_PATH)


## Whether building is a thing this process could do at all.
##
## `OS.has_feature("editor")` is false in an export, where `res://` is inside the
## PCK and unwritable and the binary is the game rather than an editor Godot and
## has no `--export-pack`. The submodule check is the same answer from the other
## side and is not redundant: a source checkout without
## `git submodule update --init` has an editor Godot and nothing to build from.
func _buildable() -> bool:
	if not OS.has_feature("editor"):
		return false
	if not FileAccess.file_exists(CHILD_PATH.path_join("project.godot")):
		# Only worth saying when there is no pack. A checkout that has one and no
		# submodule is a legitimate arrangement -- the pack is what gets mounted,
		# the sources are only how it was made -- and does not need advice.
		if not FileAccess.file_exists(PACK_PATH):
			print("[piposh3d] titles/piposh-3d is not checked out; skipping the pack.")
			print("[piposh3d] run: git submodule update --init titles/piposh-3d")
		return false
	return true


## Builds the pack, here, before the autoloads that need it are instantiated.
##
## **This is why it is in `_init` and not in an `EditorPlugin`.** A plugin runs
## at editor startup, which races the first press of F5 -- and if it loses, the
## run it was meant to fix is the run that still has no 3D title and twelve
## errors. `load_resource_pack` happens after this, and still before autoloads
## six through nine are instantiated, so building here fixes the *current*
## process rather than the next one. Measured, because the ordering is the whole
## claim: `OS.execute` returns its output from inside an autoload `_init` on
## 4.7.1, and the four autoloads resolve behind a mount performed here.
##
## It costs minutes, once per checkout, and says so while it happens rather than
## looking like a hang. That is the trade the alternative loses: a step nobody
## runs is a step that is never paid and never done, and the symptom it produces
## -- a missing title and twelve unexplained errors -- costs more than the wait.
##
## `gate.sh` and `check.sh` still build it themselves through `gate_require_pack`,
## and that is not redundant. They need it done before the first harness rather
## than during one: the minutes would otherwise be spent inside whichever entry
## ran first, under `gate_run_capped`'s ceiling, and be killed and reported as
## that harness failing.
func _build() -> void:
	var godot := OS.get_executable_path()
	var child := ProjectSettings.globalize_path(CHILD_PATH)
	# The child's own `.godot/`, which a fresh submodule checkout has not got.
	# Exporting an unimported project writes a pack missing every imported
	# resource and reports success, so this is a precondition and not a tidy-up --
	# it is the same two-step `build_pack.sh` documents, for the same reason.
	if not DirAccess.dir_exists_absolute(child.path_join(".godot")):
		print("[piposh3d] importing titles/piposh-3d (minutes, once per checkout)…")
		if _run(godot, ["--headless", "--path", child, "--import"]) != OK:
			push_warning("[piposh3d] the import failed; the 3D title will be missing")
			return
	# No "once per checkout" here: `_stale` reaches this too, and having just said
	# which two commits disagree it would be answered by a line claiming this
	# happens only on a fresh clone.
	print("[piposh3d] building %s…" % PACK_PATH)
	var out := ProjectSettings.globalize_path(BUILDING_PATH)
	if _run(godot, ["--headless", "--path", child, "--export-pack", "Pack", out]) != OK:
		push_warning("[piposh3d] the pack export failed; the 3D title will be missing")
		return
	# Godot reports success on an export that found nothing to export, so the
	# size is checked rather than the exit code alone. Under a megabyte means the
	# child was not imported after all, which is a wrong pack rather than none --
	# and a wrong one would mount, and fail later and further away.
	var size := 0
	var f := FileAccess.open(BUILDING_PATH, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	if size < 1_000_000:
		push_warning("[piposh3d] the export produced %d bytes; leaving it alone" % size)
		DirAccess.remove_absolute(out)
		return
	DirAccess.rename_absolute(out, ProjectSettings.globalize_path(PACK_PATH))
	_write_stamp(_head())
	print("[piposh3d] built %d MB" % (size / 1048576))


## Was the pack built from a different commit than the one checked out now?
##
## **Answers false whenever it cannot tell**, which is the direction that matters:
## a wrong "yes" costs a four-minute rebuild on every single run, and a wrong
## "no" costs a stale pack that `bash build_pack.sh --reimport` fixes. Not
## knowing is common and not an error -- a tarball with no `.git`, a machine
## without `git` on PATH, a `git` that fails for any reason at all.
##
## A pack with no stamp beside it is adopted rather than rebuilt. It was built by
## a version of this file that did not stamp, or by hand, and the alternative is
## that everybody with a working pack pays minutes once to prove something the
## next submodule bump would establish anyway.
##
## Uncommitted edits inside the submodule do not register, deliberately. The
## commit is the same, so somebody actively working on the 3D title keeps their
## pack instead of rebuilding it on every launch -- and they are the one person
## here who knows to run the build themselves.
func _stale() -> bool:
	var head := _head()
	if head == "":
		return false
	var f := FileAccess.open(STAMP_PATH, FileAccess.READ)
	if f == null:
		_write_stamp(head)
		return false
	var built := f.get_as_text().strip_edges()
	f.close()
	if built == head:
		return false
	print("[piposh3d] the pack was built from %s, titles/piposh-3d is at %s"
		% [built.substr(0, 8), head.substr(0, 8)])
	return true


## The commit checked out in the submodule, or "" if that cannot be established.
func _head() -> String:
	var out: Array = []
	var args := ["-C", ProjectSettings.globalize_path(CHILD_PATH), "rev-parse", "HEAD"]
	if OS.execute("git", PackedStringArray(args), out, false) != 0:
		return ""
	return "" if out.is_empty() else str(out[0]).strip_edges()


func _write_stamp(head: String) -> void:
	if head == "":
		return
	var f := FileAccess.open(STAMP_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(head)
		f.close()


## Blocking, and with the child's output folded into ours only when it fails.
##
## A successful import prints thousands of lines that belong to another project
## and would bury whatever the run was actually started for; a failed one is the
## only thing anybody needs to read, and dropping it is what turns "the export
## failed" into a message with no cause attached.
func _run(godot: String, args: Array) -> int:
	var out: Array = []
	var code := OS.execute(godot, PackedStringArray(args), out, true)
	if code != 0:
		for line in out:
			push_warning("[piposh3d] %s" % str(line).strip_edges())
		return FAILED
	return OK
