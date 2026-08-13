extends SceneTree
## Does any single step stall long enough to be seen?
##
##   godot --headless --script tools/decode_stall.gd -- --file strtgame.dir
##
## Decoding a cast member costs real milliseconds, and a renderer that decodes on
## first appearance pays them inside the step that wants to draw it. Measured
## before `director/director_preloader.gd` existed: `strtgame` frame 38 spent
## **145.7 ms** in one step and DAY1 frame 39 spent **105.5 ms**, against a step
## budget of 66 ms at 15 fps and 125 ms at 8.
##
## The stall is a dropped frame, and it lands exactly where new artwork appears:
## the first frame of a menu's background loop, or a full-screen bitmap arriving.
## From the player's chair it reads as the animation jumping, not as the engine
## loading, which is why it went unattributed for so long.
##
## It used to be bad twice over -- the clock was then *owed* the time and replayed
## up to four steps in one paint, so the movie stopped and then lurched. That half
## is gone: `FrameClock.tick` re-arms the next step's due time absolutely and
## drops what it could not afford, which is `Score::updateNextFrameTime`'s own
## arithmetic. The ceiling below is unchanged, because the stall it measures is
## the half that was always the engine's fault.
##
## This drives the real preview node and times each step's texture work the way
## `_draw` would, so what it measures is what the player waits for. The gate is a
## ceiling on the worst single step rather than on the total: a movie is allowed
## to spend a lot of time decoding overall -- it has a lot of artwork -- and is
## not allowed to spend it all at once.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## A step at 8 fps has 125 ms. Half of that is a stall a player would not notice
## against the frame it lands on; beyond it the frame it lands on is visibly
## long, and — since the clock drops rather than repays — the movie has simply
## lost that time out of its own tempo.
const WORST_STEP_MS := 60.0


func _init() -> void:
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var score = preview.get("_score")
	var preloader = preview.get("_preloader")
	if score == null:
		print("no score")
		quit(1)
		return

	var h := Harness.new()
	h.begin("no step stalls decoding artwork it should already have")
	h.check("the movie has a preloader", preloader != null, "")

	var steps := Args.number(args, "steps", 150)
	var rows: Array = []
	var total := 0.0
	for i in steps:
		var frame := int(preview.call("current_frame"))
		# What the step is about to pay for, timed the way `_draw` would pay it.
		var before := Time.get_ticks_usec()
		for raw in score.frame(frame).get("sprites", []):
			var sprite: Dictionary = preview.call("_effective", raw)
			if sprite.is_empty():
				continue
			preview.call("_preload_one", sprite)
		var ms := (Time.get_ticks_usec() - before) / 1000.0
		total += ms
		rows.append([ms, frame])
		# Then let the preloader run ahead exactly as `_process` does, so the
		# next step's cost reflects the lookahead having done its job.
		if preloader != null:
			preloader.run(frame, Callable(preview, "_preload_one"), Callable(preview, "_effective"))
		preview.call("_advance")

	rows.sort_custom(func(a, b): return a[0] > b[0])
	var worst: float = rows[0][0] if not rows.is_empty() else 0.0
	print("%d steps, %.0f ms of texture work in total" % [rows.size(), total])
	print("slowest steps:")
	for i in mini(6, rows.size()):
		print("   %8.2f ms  frame %d" % [rows[i][0], rows[i][1]])

	h.check("no single step decodes for longer than the budget",
		worst <= WORST_STEP_MS, "worst %.1f ms, ceiling %.0f ms" % [worst, WORST_STEP_MS])
	h.complete("no step stalls decoding artwork it should already have")
	quit(h.finish("first-appearance decode cost, per step"))
