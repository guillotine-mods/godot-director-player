extends SceneTree
## Does the movie *settle*? A `go to movie` that lands on the wrong frame can
## send the playhead straight back where it came from, and the two movies then
## change places for ever.
##
##   godot --headless --path . --script tools/movie_churn.gd
##   godot --headless --path . --script tools/movie_churn.gd -- --steps 600
##   godot --headless --path . --script tools/movie_churn.gd -- --window map.dxr --label nightmap
##
##   --steps N     how many score steps to watch (default 400)
##   --window F    a Movie-In-A-Window to watch as well (default saveload.dxr)
##   --label L     the marker to open that window on (default savegame)
##   --window-off  stage only
##
## Nothing else in `tools/` detects this class of bug, and it is the one class
## that hides *behind* the renderer: the stage is cleared to black before every
## paint, so a movie that never settles paints nothing over the clear and the
## player sees the screen flickering between black and half-drawn. That reads as
## a rendering fault, and the bug is entirely in control flow.
##
## The reproduction it was written from: `HEZSAVE.DIR`'s
## `go to frame "savegame2" of movie cdsavepath & "saveload.dxr"` reached the
## preview's `_go` as `["to", "frame", "savegame2", <path>]`. Only `to` and
## `movie` were being dropped as command words, so `frame` stood in the argument
## position and was read as the destination marker; no movie has one, the lookup
## fell back to frame 0, and frame 0 of `SAVELOAD` runs back into `HEZSAVE` five
## frames later. 114 movie changes in 400 steps, for ever.
##
## What is asserted is a *rate*, not a count. Changing movie is normal — the boot
## chain does it, every doorway does it — so the question is never "did it
## change" but "did it stop". A cycle shows up as a burst: more changes inside
## any window of `WINDOW` steps than a title could plausibly want, and the same
## small set of movies coming round again. Both are reported, because a high
## count against *many* distinct movies is a sweep and a high count against two
## is a loop, exactly as `probe.gd` distinguishes a wait loop from a hang.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Steps the change rate is measured over, and the most a title may plausibly
## want inside one. Four is generous: the longest legitimate chain in this corpus
## is the boot movie handing off to a room, which is two.
const WINDOW := 100
const MAX_CHANGES_PER_WINDOW := 4


## `{changes, at, movies, worst_window, tail}` for a run of steps.
##
## `at` is the step each change happened on, so a burst is visible as a run of
## close-together numbers rather than having to be inferred from a total.
static func watch(node: Node, steps: int) -> Dictionary:
	var at: Array[int] = []
	var movies: Dictionary = {}
	var tail: Array[String] = []
	var last := ""
	for i in steps:
		var name := str(node.call("movie_name"))
		if last != "" and name != last:
			at.append(i)
		if name != last:
			tail.append("%s:%d" % [name, int(node.call("current_frame"))])
		movies[name] = int(movies.get(name, 0)) + 1
		last = name
		node.call("_advance")

	# The busiest window of `WINDOW` steps, which is what a cycle shows up in.
	var worst := 0
	for i in at.size():
		var n := 0
		for j in range(i, at.size()):
			if at[j] - at[i] >= WINDOW:
				break
			n += 1
		worst = maxi(worst, n)
	return {
		"changes": at.size(),
		"at": at,
		"movies": movies,
		"distinct": movies.size(),
		"worst_window": worst,
		"tail": tail.slice(maxi(0, tail.size() - 8)),
	}


static func report(h: RefCounted, what: String, seen: Dictionary) -> void:
	h.check("%s settles: no more than %d movie change(s) in any %d steps"
			% [what, MAX_CHANGES_PER_WINDOW, WINDOW],
		int(seen["worst_window"]) <= MAX_CHANGES_PER_WINDOW,
		"%d change(s) total across %d movie(s), worst window %d, last: %s" % [
			int(seen["changes"]), int(seen["distinct"]), int(seen["worst_window"]),
			" -> ".join(seen["tail"])])


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var steps := Args.number(args, "steps", 400)

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	h.begin("the stage settles on a movie")
	var stage: Dictionary = watch(preview, steps)
	report(h, "the stage", stage)
	h.complete("the stage settles on a movie")

	if not Args.flag(args, "window-off"):
		# A window is a second movie with its own playhead, and its `go to movie`
		# runs through the same code — so it can cycle on its own while the stage
		# sits still. The reported case was exactly that: nothing was wrong with
		# the stage at all.
		var file := Args.text(args, "window", "saveload.dxr")
		var label := Args.text(args, "label", "savegame")
		h.begin("a Movie-In-A-Window settles on a movie")
		preview.call("lingo_window", file)
		preview.call("lingo_open_window", file)
		var window: Node = preview.call("window_at", Vector2(320, 240))
		if h.check("%s opened as a window" % file, window != null):
			window.call("lingo_go_label", label)
			h.check("it opened on `%s`" % label,
				int(window.call("current_frame"))
					== int(window.get("_labels").labels.get(label, -1)),
				"frame %d" % int(window.call("current_frame")))
			var seen: Dictionary = watch(window, steps)
			report(h, "the window", seen)
			# The save round trip is two hops — into `HEZSAVE` to read the saved
			# names and back — so the window must end on the movie it started as
			# rather than on the helper it borrowed.
			h.check("it ends on the movie it opened with",
				str(window.call("movie_name")).get_basename().to_lower()
					== file.get_basename().to_lower(),
				"ended on %s" % str(window.call("movie_name")))
		h.complete("a Movie-In-A-Window settles on a movie")

	quit(h.finish("no movie changes place with another for ever"))
