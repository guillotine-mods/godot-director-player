extends SceneTree
## Does a game's own `saveMovie` still persist when its container cannot be
## written — an exported build, and every mobile build?
##
##   godot --headless --path . --script tools/save_overlay.gd -- --allow-writes
##
## **The case this is about.** These titles save by rewriting their own container
## in place (`saveMovie` -> `HEZSAVE.DIR`, `EGOZSAVE.DIR`, `Saves.dir`). From a
## source checkout `games/` is an ordinary folder and that works. In an export
## `games/*` is inside the `.pck` (every preset in `export_presets.cfg` filters it
## in, and `release.yml` asserts the multi-GB `.pck` is where it lands), and a
## `.pck` is read-only at runtime. On Android there is no folder beside the APK to
## fall back to at all. So the write fails, `on dosave` never checks a return
## value Director does not give it, and the player finds out only when there is
## nothing to load. `docs/ANDROID.md` files the shape of the fix.
##
## **Why it needs two processes.** A single process cannot tell "persisted" from
## "still in the override table" — the same distinction `tools/save_movie.gd`'s
## header calls the entire bug for the inert-`saveMovie` case, and it applies
## identically to a redirected write. So the child saves and exits, and this
## process reads the bytes back.
##
## **Why a fixture and not the corpus.** The reproduction needs a game root that
## cannot be written, and `chmod` on a submodule is not a thing to leave behind on
## a failed run. The fixture is one copied container under a gitignored path, and
## a root override only travels as `res://...` (`DirectorPaths._override_root`
## joins anything else onto `games/`), which is why it lives inside the project
## rather than in a temp directory.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")

## Gitignored, and named for what it is so a leftover is self-explaining.
const FIXTURE_PARENT := "res://.gate-fixtures"
const FIXTURE_ROOT := FIXTURE_PARENT + "/save-overlay"
const DEFAULT_SOURCE := "res://games/piposh-dream/Saves.dir"

## The principal an ACL deny entry names on Windows: `Everyone`, by SID rather
## than by name, because there is no shell here to expand `%USERNAME%` and no
## reason to depend on how this Windows spells its groups. See `_deny_writes`.
const DENY_SID := "*S-1-1-0"


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)


## `%SystemRoot%` rather than a bare name: there is no shell to search `PATH`, and
## `OS.execute` on a name it cannot resolve logs an engine `ERROR` before
## returning -1 — the noise `tools/video_sidecar.gd:_find_converter` has its own
## paragraph about avoiding.
func _icacls() -> String:
	var root := OS.get_environment("SystemRoot")
	if root == "":
		root = "C:/Windows"
	return root.replace("\\", "/") + "/System32/icacls.exe"


## `icacls` reads `/` as the start of an option, so the path has to be native.
## Same conversion as `video_sidecar.gd:_native`, for the same reason.
func _native(path: String) -> String:
	var real := _absolute(path)
	return real.replace("/", "\\") if OS.get_name() == "Windows" else real


## The OS's own permission tool, because Godot exposes no mode setter on any
## platform and the reproduction is specifically a directory that refuses a *new*
## file: `director_writer.gd` composes `<target>.saving` beside the target and
## renames it, so an unwritable file inside a writable directory still saves.
##
## Two spellings of one idea. Where there are modes, `chmod`. Where there are not,
## an ACL deny entry on the two rights that create things in a directory — `WD`
## (write data, i.e. a new file) and `AD` (append data, i.e. a new folder) — and
## nothing else, so the container stays readable and the fixture stays deletable.
## The owner keeps `WRITE_DAC` implicitly no matter what a deny entry says, which
## is what lets `_allow_writes` undo this.
##
## Neither exit code is asserted on. What the subject depends on is whether a file
## can be created, which is what the probe at the call site asks.
func _deny_writes(path: String) -> int:
	if OS.get_name() == "Windows":
		return OS.execute(_icacls(),
			[_native(path), "/deny", "%s:(WD,AD)" % DENY_SID], [], true)
	return OS.execute("/bin/chmod", ["a-w", _absolute(path)], [], true)


func _allow_writes(path: String) -> int:
	if not DirAccess.dir_exists_absolute(_absolute(path)):
		return 0
	if OS.get_name() == "Windows":
		return OS.execute(_icacls(),
			[_native(path), "/remove:d", DENY_SID], [], true)
	return OS.execute("/bin/chmod", ["u+w", _absolute(path)], [], true)


## A dozen portable lines instead of `rm -rf`. The shell tool is not the same on
## every platform this gate runs on, and `/bin/rm` is half of what failed the
## nightly's Windows leg: the fixture was left behind for the next run to read as
## the previous run's answer.
func _remove_tree(path: String) -> void:
	var real := _absolute(path)
	if FileAccess.file_exists(real):
		DirAccess.remove_absolute(real)
		return
	if not DirAccess.dir_exists_absolute(real):
		return
	var dir := DirAccess.open(real)
	if dir == null:
		return
	# The probe is a dotfile, and a file left behind is a directory that will not
	# remove.
	dir.include_hidden = true
	for name in dir.get_files():
		DirAccess.remove_absolute(real.path_join(str(name)))
	for name in dir.get_directories():
		_remove_tree(real.path_join(str(name)))
	DirAccess.remove_absolute(real)


## The overlay a redirected write is expected to land in. Keyed by the game root's
## own folder name and the container's path relative to that root, not by bare
## filename: two titles ship containers of the same name, and resolution by tail
## alone has already picked the wrong one once (`director_preview.gd:movie_path`).
func _overlay_for(root: String, relative: String) -> String:
	return "user://games/%s/%s" % [str(root).trim_suffix("/").get_file(), relative]


func _child(root: String, boot: String, field: String, marker: String) -> Array:
	return [
		"--headless", "--audio-driver", "Dummy",
		"--path", _absolute("res://"),
		"--script", "res://tools/save_overlay.gd", "--",
		"--child", "true", "--root", root, "--boot", boot,
		"--field", field, "--marker", marker, "--allow-writes",
	]


# ------------------------------------------------------------------- the child

## Boot the fixture, type into a field, and save. Prints the report for the
## parent's log; asserts nothing, because it is the subject and not the judge.
func _run_child(args: Dictionary) -> void:
	var field := Args.text(args, "field", "save1")
	var marker := Args.text(args, "marker", "OVERLAY")
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await process_frame
	for i in 8:
		await process_frame
	print("child: movie %s" % str(preview.call("movie_name")))
	preview.call("lingo_set_field", field, "", marker)
	var report: Dictionary = preview.call("lingo_save_movie",
		str(preview.call("movie_name")))
	print("child: saveMovie %s" % JSON.stringify(report))
	quit(0)


# ------------------------------------------------------------------ the parent

func _init() -> void:
	var args := Args.parse()
	if Args.flag(args, "child") or Args.text(args, "child", "") != "":
		await _run_child(args)
		return

	var h := Harness.new()
	var source := Args.text(args, "source", DEFAULT_SOURCE)
	var field := Args.text(args, "field", "save1")
	var marker := Args.text(args, "marker", "OVERLAY")
	var relative := source.get_file()
	var overlay := _overlay_for(FIXTURE_ROOT, relative)
	var fixture := FIXTURE_ROOT.path_join(relative)

	# Start from nothing: a fixture or overlay left by a killed run would make
	# every assertion below read the previous run's answer. The permission is
	# lifted before the removal and not only in the teardown -- a run killed
	# between the deny and its restore leaves a fixture root that cannot be
	# emptied, and this checkout is shared with another session.
	_allow_writes(FIXTURE_ROOT)
	_remove_tree(FIXTURE_PARENT)
	_remove_tree(overlay.get_base_dir())

	h.begin("a container that cannot be written still saves")
	if not h.check("the fixture source exists", FileAccess.file_exists(source), source):
		h.complete("a container that cannot be written still saves")
		quit(h.finish("save overlay"))
		return
	DirAccess.make_dir_recursive_absolute(_absolute(FIXTURE_ROOT))
	var copied := DirAccess.copy_absolute(_absolute(source), _absolute(fixture))
	h.check("the fixture container is in place", copied == OK, error_string(copied))
	var before := FileAccess.get_file_as_bytes(_absolute(fixture))

	# Everything from here has to reach the restore, so the failures are collected
	# and the teardown runs unconditionally below rather than behind an early
	# return.
	var denied := _deny_writes(FIXTURE_ROOT)
	# Asked of the filesystem rather than of the tool. An exit code says whether
	# `chmod` ran, and the thing the subject depends on is whether a new file can
	# be created -- which is one question with one answer on every platform, where
	# "did `chmod` run" is not a question Windows can be asked at all. Reading the
	# exit code here is what turned one missing binary into five failures in the
	# nightly, four of them consequences of this line.
	var probe := FIXTURE_ROOT.path_join(".probe")
	var opened := FileAccess.open(probe, FileAccess.WRITE)
	if opened != null:
		opened.close()
		DirAccess.remove_absolute(_absolute(probe))
	h.check("the fixture root refuses a new file", opened == null,
		"deny exit %d" % denied)

	var out: Array = []
	var code := OS.execute(OS.get_executable_path(),
		_child(FIXTURE_ROOT, relative, field, marker), out, true)
	for line in out:
		for row in str(line).split("\n"):
			if str(row).strip_edges() != "":
				print("    | %s" % str(row).strip_edges())
	h.check("the saving process exits cleanly", code == 0, "exit %d" % code)

	# The point of the whole file: the write went somewhere writable.
	h.check("the save landed in the user:// overlay",
		FileAccess.file_exists(overlay), overlay)
	# And it did not pretend to write the packaged copy.
	var after := FileAccess.get_file_as_bytes(_absolute(fixture))
	h.check("the read-only container was left alone", before == after,
		"%d bytes before, %d after" % [before.size(), after.size()])

	if FileAccess.file_exists(overlay):
		var file := ContainerFile.new()
		if h.check("the overlay container reopens here", file.open(overlay), file.error):
			var cast := Cast.new()
			var parsed: bool = cast.open(file)
			var got := str(cast.member(cast.number_of(field)).get("text", ""))
			file.close()
			h.check("the overlay's cast parses", parsed)
			h.check("the field holds what the other process saved", got == marker,
				JSON.stringify(got))

	# The read side: a later open of the same reference has to find the overlay,
	# or the save is written and never seen again.
	# `root` is set directly rather than through `load_config(_, FIXTURE_ROOT)`:
	# `--root` on the command line beats that argument by design, and `gate.sh`
	# passes `--root` to every harness — so going through the config would resolve
	# against whichever title the gate pinned and assert nothing about the fixture.
	var paths := Paths.new()
	paths.root = FIXTURE_ROOT
	var resolved := paths.resolve(relative)
	h.check("resolution prefers the overlay over the read-only copy",
		resolved != "" and resolved.begins_with("user://"), resolved)
	h.complete("a container that cannot be written still saves")

	# The permission first: a delete cannot unlink out of a directory it cannot
	# write.
	_allow_writes(FIXTURE_ROOT)
	_remove_tree(FIXTURE_PARENT)
	_remove_tree(overlay.get_base_dir())
	# The directories too, not only the files in them: `make_dir_recursive` created
	# the fixture's *parent* and the overlay's own folder, and a check that only
	# looked for the leaves passed while both were left behind on a gate run.
	# `user://games` itself stays -- it is shared with every other title's overlay.
	h.check("the fixture and overlay are cleaned up",
		not DirAccess.dir_exists_absolute(_absolute(FIXTURE_ROOT))
			and not FileAccess.file_exists(overlay)
			and not DirAccess.dir_exists_absolute(_absolute(FIXTURE_PARENT))
			and not DirAccess.dir_exists_absolute(_absolute(overlay.get_base_dir())))
	quit(h.finish("save overlay"))
