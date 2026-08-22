extends SceneTree
## A run exits with nothing leaked, and the Xtra registry does not own its host.
##
##   godot --headless --path . --script tools/exit_leaks.gd
##   godot --headless --path . --script tools/exit_leaks.gd -- --child true
##
## Until `lingo_xtra.gd` took a `WeakRef`, **every clean-exiting run of this
## project ended with two engine alerts** -- on every harness in `gate.sh` and on
## every launch of the game:
##
##   WARNING: N ObjectDB instances were leaked at exit
##   ERROR: 4 resources still in use at exit
##
## The 4 never moved, because it counts *resources* and not instances:
## `preview_lingo_host.gd`, `lingo_xtra.gd` and the two `factory` scripts
## (`lingo_fileio.gd`, `lingo_buddyapi.gd`) stayed referenced whatever the run
## did. `N` grew with the run because the cycle is per host and
## `boot.gd:start_lingo` builds a fresh one per movie: measured at
## `3 x hosts + 5` exactly -- 8 on this file's own child boot, 11 on
## `lingo_objects` (two hosts), 19 on `movie_churn` (four hosts, plus an
## unrelated `AudioStreamWAV` pair).
##
## That is the reason this harness exists rather than the bug being tolerated: a
## standing `ERROR` on every entry of a suite whose job is to say which entries
## are clean teaches everybody to read past errors, which is `AGENTS.md`'s
## argument about a standing red one level down.
##
## ## Two arms, because one of them cannot be trusted alone
##
## **The child arm** asserts the player-visible invariant: boot the real player in
## a separate process, let it exit the way every run exits, and read what the
## engine says on the way out. That is the only place the invariant is actually
## observable -- the count is printed *after* the last line any script can run.
##
## An absence check passes when nothing happened, so the two "no such line"
## assertions are worth nothing on their own: a child that failed to launch, died
## before boot or found no corpus prints no leak line either. So the child prints
## a marker naming what it built, and the parent fails if the marker is missing.
## `OS.execute`'s exit code is checked beside it for the same reason.
##
## **The in-process arm** asserts the mechanism, and it is the one that fails
## unambiguously: build a host, drop the last reference to it from outside, and
## ask a `WeakRef` whether it went. With a strong `host` field in the registry it
## cannot, and this check reads the cycle directly rather than inferring it from a
## count that other leaks also move.
##
## The marker is deliberately independent of the fix -- it counts registered
## Xtras and score frames, neither of which the `WeakRef` touches -- so reverting
## `lingo_xtra.gd` fails four checks and leaves the marker passing, rather than
## taking the control down with the subject.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const PreviewHost := preload("res://scenes/preview_lingo_host.gd")

## The two lines the engine prints at cleanup, matched on the wording that is
## stable across 4.x rather than on the whole sentence: the counts vary and the
## `(run with --verbose for details)` tail is dropped when `--verbose` is on.
const LEAK_ALERTS := [
	"ObjectDB instances were leaked",
	"resources still in use",
]

## What the child prints once it has a booted movie, and the only evidence the
## parent has that the child got that far.
const MARKER := "exit_leaks child:"

## Frames the child waits for a score. `boot.gd` reads the container off the disc
## and an art-heavy title takes several frames to get there; the ceiling is a
## refusal to wait for ever, not a budget.
const BOOT_FRAMES := 600


func _init() -> void:
	var args := Args.parse()
	if Args.flag(args, "child") or Args.text(args, "child", "") != "":
		await _child(args)
		return

	var h := Harness.new()

	# The mechanism, in this process. `PreviewHost.new()` registers its Xtras in
	# its own `_init` and needs no preview, no movie and no corpus, which is what
	# makes this arm cheap enough to keep beside the child.
	h.begin("the Xtra registry does not own its host")
	var host: Object = PreviewHost.new()
	var registered: Array = host.get("xtras_loaded")
	h.check("the host registers its Xtras", registered.size() == 2,
		"%d registered" % registered.size())
	var xtras: Array[WeakRef] = []
	for entry in registered:
		xtras.append(weakref((entry as Dictionary).get("object", null)))
	var host_ref: WeakRef = weakref(host)
	# The only reference from outside the registry. Dropping it leaves the host
	# reachable only from the Xtras it built, which is the cycle.
	host = null
	registered = []
	h.check("the host is freed once nothing outside holds it",
		host_ref.get_ref() == null, str(host_ref.get_ref()))
	var live := 0
	for ref in xtras:
		if ref.get_ref() != null:
			live += 1
	h.check("its Xtras are freed with it", live == 0, "%d still live" % live)
	h.complete("the Xtra registry does not own its host")

	# The invariant, in a process that exits.
	h.begin("a boot exits with nothing leaked")
	var child := [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/exit_leaks.gd", "--", "--child", "true",
	]
	# The corpus and the boot movie, forwarded the way the three other
	# child-spawning harnesses forward them: a child that fell back to the
	# tracked config would boot whichever title somebody last pointed it at, and
	# a run against another title is not this entry's subject.
	for key in ["root", "boot", "file"]:
		if Args.text(args, key, "") != "":
			child.append_array(["--%s" % key, Args.text(args, key, "")])
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), child, out, true)
	var lines: Array[String] = []
	for chunk in out:
		for row in str(chunk).split("\n"):
			if str(row).strip_edges() != "":
				lines.append(str(row).strip_edges())
	for row in lines:
		print("    | %s" % row)

	h.check("the boot process exits cleanly", code == 0, "exit %d" % code)
	var marker := ""
	for row in lines:
		if row.contains(MARKER):
			marker = row
	h.check("the child booted a movie and built its Xtras", marker != "",
		marker if marker != "" \
			else "no \"%s\" line in %d line(s) of output" % [MARKER, lines.size()])
	for alert in LEAK_ALERTS:
		var found := ""
		for row in lines:
			if row.contains(alert):
				found = row
		h.check("the exiting process reports no \"%s\"" % alert, found == "", found)
	h.complete("a boot exits with nothing leaked")

	quit(h.finish("a run exits with no leaked instances and no resources in use"))


## Boot the real player and exit. Prints one marker line and asserts nothing:
## everything this arm is here to measure is printed by the engine after the last
## GDScript statement, and only the parent can read it.
##
## **Nothing is freed on the way out**, on purpose. The exit this measures is the
## one every harness and every game launch takes, and a `free()` here would
## measure a path nobody else runs.
func _child(_args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	var frames := 0
	while frames < BOOT_FRAMES:
		await process_frame
		frames += 1
		var score: Object = preview.get("_score")
		if score != null and int(score.get("frame_count")) > 0:
			break
	var score: Object = preview.get("_score")
	var lingo_host: Object = preview.get("_host")
	var registered: int = 0
	if lingo_host != null:
		registered = (lingo_host.get("xtras_loaded") as Array).size()
	print("%s %d frame(s) of score after %d process frame(s), %d xtra(s) registered" % [
		MARKER,
		0 if score == null else int(score.get("frame_count")),
		frames,
		registered,
	])
	quit(0)
