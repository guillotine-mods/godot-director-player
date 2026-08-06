extends SceneTree
## Point it at any room and watch what the score does. The general one.
##
##   godot --headless --script tools/probe.gd -- --movie MURDER1 --seconds 60 --trace
##   godot --headless --script tools/probe.gd -- --movie DAY1 --label clif2 \
##       --seconds 200 --click-prompts
##
##   --movie X          where to start (required)
##   --label Y          the marker to arrive at
##   --frame N          a frame number instead of a label
##   --seconds N        how long to run in real time (default 30)
##   --click-prompts    click a line once the frame has offered one, as a player would
##   --dwell N          frames to look at a prompt before clicking (default 120)
##   --until-change     stop as soon as the movie changes
##   --trace            print the playhead's last states
##   --no-lingo-clicks  lift clicks from the export instead of interpreting them
##   --no-lingo-frames  likewise for exitFrame/enterFrame
##
## This prints numbers rather than a verdict, so it cannot tell you a scene is
## correct — read `porting-fidelity-verification` before believing any of them. It
## tells you where the playhead *is*, which is the question a stuck scene poses.
##
## What it is for, from the case it came out of: a Director wait loop ends on
## `go to marker(0)` and cycles its whole span while it waits for a click, so a
## high repeat count against a *high* distinct count is a prompt, not a hang. A
## high repeat against a low distinct count is a real hold. Sampling the frame
## number alone cannot tell those apart, and reading a sample as an infinite loop
## is how bugs.md 22 was filed twice.
##
## Real time is not optional. Speech frames hold on `soundBusy(1)`, and a synthetic
## tick loop advances the runtime's clock but not the audio server's, so every such
## guard holds for ever and any scene with speech in it looks stuck.

const Args := preload("res://tools/lib/args.gd")
const Driver := preload("res://tools/lib/driver.gd")
const Hooks := preload("res://tools/lib/game_hooks.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := Args.parse()
	var movie := Args.text(args, "movie")
	if movie == "":
		print("usage: godot --headless --script tools/probe.gd -- --movie X [--label Y] "
			+ "[--seconds N] [--click-prompts] [--trace]")
		quit(2)
		return

	var flags: Dictionary = {}
	if Args.flag(args, "no-lingo-clicks"):
		flags["lingo_clicks"] = false
	if Args.flag(args, "no-lingo-frames"):
		flags["lingo_frames"] = false

	var open: Dictionary = {"movie": movie, "flags": flags}
	if args.has("label"):
		open["label"] = Args.text(args, "label")
	if args.has("frame"):
		open["frame"] = Args.number(args, "frame")

	var driver := Driver.new(self, Hooks.new())
	if not driver.open(open):
		print("FAILED to reach %s%s" % [movie, " @" + Args.text(args, "label") if args.has("label") else ""])
		quit(1)
		return
	print("arrived: %s (asked for %s)" % [driver.state(), movie])

	var seconds := Args.number(args, "seconds", 30)
	# `--click-prompts` clicks whatever the frame offers, which is the point while a
	# scene is waiting and a nuisance once it is not: left running past the exit it
	# will happily click its way around the hub. Pair it with `--until-change` when
	# the question is whether a scene ends rather than what it does next.
	var result: Dictionary = await driver.run_for(seconds * 1000, {
		"click_prompts": Args.flag(args, "click-prompts"),
		"dwell": Args.number(args, "dwell", 120),
		"until_movie_change": Args.flag(args, "until-change"),
	})

	var t: Dictionary = driver.trace()
	print("ran %d s, %d steps" % [int(result["elapsed_ms"]) / 1000, int(result["steps"])])
	print("ended at %s (label %s)" % [
		driver.state(), driver.runtime.label_near_frame(driver.frame())])
	print("distinct states %d, transitions %d" % [int(t["distinct"]), int(t["transitions"])])
	print("most repeated %s x%d" % [str(t["most_repeated"]), int(t["most_repeated_count"])])
	if int(result["clicks"]) > 0:
		print("clicked %d prompt(s) at frames %s" % [
			int(result["clicks"]), str(result["click_frames"])])
	if Args.flag(args, "trace"):
		print("last states: %s" % str(t["tail"]))
	quit(0)
