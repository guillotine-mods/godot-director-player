extends SceneTree
## §9.2's two frame holds, and the movie-boundary state that goes with them.
##
##   godot --headless --path . --script tools/wait_frames.gd -- --root piposh2 --boot strtgame.dir
##
## Four `bugs.md` entries, in one harness because all four are about what a frame
## *hold* does to the rest of the engine and every one of them needs the same
## fixture -- a real movie, a real clock, a real tick:
##
##   60  a tempo delay on a self-holding frame is armed once, where the reference
##       re-arms it on every step
##   61  the click that releases a wait-for-click is delivered to the movie as
##       well, where the reference consumes the mouse-down
##   62  a wait-for-click frame shows no alternating cursor, so a waiting movie
##       looks like a stopped one
##   103 `start_lingo` clears the script casts but not the library keys
##
## **Every case asserts what a player would see, not that a setter and a getter
## agree.** 60 is measured as a *rate* -- how many times the movie's own
## `exitFrame` runs over five seconds of a two-second delay -- because the rate is
## the whole of what the bug is; 61 is measured on the movie-visible facts a press
## writes (`the clickOn`, `the clickLoc`, `the lastClick`), because those are what
## a hotspot's handler reads; 62 on what `cursor_at` answers under the pointer,
## including over a sprite that names a cursor of its own.
##
## Title-agnostic. It finds its own fixture by scanning the loaded score for a
## frame that carries a tempo delay, and says so and skips when the movie has
## none rather than asserting over an empty set.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Cursor := preload("res://scenes/preview/cursor.gd")
const FrameLoop := preload("res://scenes/preview/frame_loop.gd")
const Boot := preload("res://scenes/preview/boot.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")

## Seconds of movie time each simulated tick stands for. 1/60 is the rate a
## desktop `_process` turns over at, and the point of driving the loop by hand is
## that the *clock* must be the thing deciding when a step is due -- not the
## number of ticks.
const TICK := 1.0 / 60.0
## How long the rate case runs the loop for, in movie seconds.
const RATE_WINDOW := 5.0


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	var preview: Node = (load("res://scenes/director_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	for i in 8:
		await process_frame

	_cursor_case(h, preview)
	await process_frame
	_press_case(h, preview)
	await process_frame
	_rate_case(h, preview, Args.number(args, "window", 0))
	await process_frame
	_lib_keys_case(h, preview)

	quit(h.finish("a waiting frame's cursor, its click, its rate, and the keys a movie hands over"))


# ------------------------------------------------------------------ bugs.md 62

## The alternating cursor, its 1000 ms period, and its precedence over the sprite
## stack.
##
## `Score::isWaitingForNextFrame` flips `_waitForClickCursor` once a second while
## the wait stands and re-renders (`score.cpp:417-423`); `Score::renderCursor`
## answers that flag *before* it walks the channels (`score.cpp:1454-1457`). So
## the three things worth asserting are: the wait names a cursor at all, it is a
## different one a second later, and a sprite underneath cannot take it away.
##
## The sprite half is not decoration. Without the precedence the fix would be
## invisible on exactly the frames that matter -- a wait-for-click frame in this
## corpus is usually a full-stage picture with hotspots on it, so the stack almost
## always has an answer and it would always win.
func _cursor_case(h: Harness, preview: Node) -> void:
	h.begin("the wait-for-click cursor")
	var clock = preview.get("_clock")
	# A channel cursor under the probe point, so the precedence below is measured
	# against a stack that genuinely wants to answer rather than against an empty
	# one -- the shape `porting-fidelity-verification` calls a check whose two
	# readings cannot disagree.
	#
	# **The frame is chosen, not accepted.** This used to read whatever frame the
	# eight `process_frame`s in `_init` had left the boot movie on, and then
	# assert that that frame happened to carry a sprite worth probing --
	# a fixture measured in engine ticks rather than in the movie's own
	# structure. `bugs.md` 138 filed it after six runs each way came back
	# 3-of-6 and 2-of-6 on the same command line, and it is the same
	# fixed-window shape as `play_suspends` and `docs/bugs-closed.md` 119.
	# Under `gate.sh` it is worse than a standing red, because a check that
	# fails one run in two teaches everyone to re-run rather than read.
	#
	# So the fixture is found the way `_rate_case` below finds its delay frame
	# and the way this file's header says the whole harness works: by walking
	# the loaded score for the first frame that carries one, going there, and
	# probing that. No tick count is load-bearing, and a movie that genuinely
	# carries no such sprite says which movie it was instead of failing with a
	# probe point that reads like a coordinate bug.
	var score = preview.get("_score")
	if score == null:
		h.check("a score is loaded", false, "no movie")
		h.complete("the wait-for-click cursor")
		return
	var probe := Vector2(8, 8)
	var covered := false
	var on_frame := -1
	for i in int(score.frame_count):
		# `_rate_case`'s idiom for standing the playhead on a chosen frame: set
		# the index, do not `go` to it. A `go` queues a jump and releases the
		# clock, and this case is about to arm a wait on that same clock.
		preview.set("_index", i)
		for sprite in preview.call("frame_sprites"):
			var shown: Dictionary = preview.call("_effective", sprite)
			if shown.is_empty():
				continue
			var rect: Rect2 = preview.call("_sprite_rect", shown)
			if rect.size.x < 4.0 or rect.size.y < 4.0:
				continue
			probe = rect.get_center()
			(preview.get("_channel_cursors") as Dictionary)[int(shown["channel"])] = 260
			covered = true
			on_frame = i
			break
		if covered:
			break
	# The `video_fallback` shape again: if no frame of this movie carries one,
	# say so and assert nothing about the precedence rather than against an
	# empty stack.
	h.check("a sprite under the probe names a cursor of its own", covered,
		("probe %s on frame %d" % [str(probe), on_frame]) if covered
		else "no frame of %s carries a sprite at least 4x4"
			% preview.call("movie_path"))
	if not covered:
		h.complete("the wait-for-click cursor")
		return
	var without: Variant = preview.call("cursor_at", probe)
	h.check("with no wait, the stack answers", str(without) != Cursor.WAIT_CLICK_UP
		and str(without) != Cursor.WAIT_CLICK_DOWN, "answered %s" % str(without))

	clock.enter_frame({"wait_click": true, "delay_ms": 0.0})
	h.check("arming the wait names the mouse-up arrow",
		str(preview.call("cursor_at", probe)) == Cursor.WAIT_CLICK_UP,
		"answered %s" % str(preview.call("cursor_at", probe)))
	h.check("and says the cursor has to be pushed", bool(clock.take_cursor_change()))

	# Just under the period, then just over it: a flip that happened at 600 ms
	# would pass a single "did it change" test and be wrong about the thing the
	# player sees, which is a *rhythm*.
	clock.tick(0.6)
	h.check("half a second in, it has not flipped yet",
		not bool(clock.waiting_click_cursor()) and not bool(clock.take_cursor_change()))
	clock.tick(0.5)
	h.check("a second in, it flips to the mouse-down arrow",
		bool(clock.waiting_click_cursor()) and bool(clock.take_cursor_change()))
	h.check("and the cursor under the sprite is the wait's, not the sprite's",
		str(preview.call("cursor_at", probe)) == Cursor.WAIT_CLICK_DOWN,
		"answered %s" % str(preview.call("cursor_at", probe)))
	clock.tick(1.1)
	h.check("another second and it is back to mouse-up",
		not bool(clock.waiting_click_cursor())
		and str(preview.call("cursor_at", probe)) == Cursor.WAIT_CLICK_UP)

	clock.clicked()
	h.check("the click ends the wait and hands the cursor back to the stack",
		str(preview.call("cursor_at", probe)) == str(without)
		and bool(clock.take_cursor_change()),
		"answered %s" % str(preview.call("cursor_at", probe)))
	h.complete("the wait-for-click cursor")


# ------------------------------------------------------------------ bugs.md 61

## The press that ends a wait ends the wait and does nothing else.
##
## Measured on the three movie-visible facts `Movie::processEvent` writes inside
## the else-arm the wait skips (`events.cpp:249-297`): `the clickOn`, `the
## clickLoc` and `the lastClick`. Seeded with values no press would produce, so
## "unchanged" is a real observation and not the default.
##
## The second half is the control that lives in the harness rather than in a
## reverted build: the *same* press on the *same* point with no wait standing must
## write all three. Without it this case would pass just as well against an engine
## that had stopped delivering presses altogether.
func _press_case(h: Harness, preview: Node) -> void:
	h.begin("the press that ends a wait")
	var clock = preview.get("_clock")
	var host = preview.get("_host")
	var at := Vector2(20, 20)
	for sprite in preview.call("frame_sprites"):
		var shown: Dictionary = preview.call("_effective", sprite)
		if shown.is_empty():
			continue
		var rect: Rect2 = preview.call("_sprite_rect", shown)
		if rect.size.x >= 4.0 and rect.size.y >= 4.0:
			at = rect.get_center()
			break

	# The movie has to have seen a real mouse-down for `route_press` to offer the
	# click to the clock at all (`_saw_press`), which is the same gate a
	# Movie-In-A-Window opening mid-click goes through.
	preview.set("_saw_press", true)
	host.click_sprite = -99
	host.click_loc = Vector2(-1, -1)
	host.last_click_ms = -1
	clock.enter_frame({"wait_click": true, "delay_ms": 0.0})
	preview.call("route_press", at)
	h.check("the wait is released", not bool(clock.waiting_click()))
	h.check("`the clickOn` is not rewritten", int(host.click_sprite) == -99,
		"clickOn %d" % int(host.click_sprite))
	h.check("`the clickLoc` is not rewritten", host.click_loc == Vector2(-1, -1),
		"clickLoc %s" % str(host.click_loc))
	h.check("`the lastClick` is not stamped", int(host.last_click_ms) == -1,
		"lastClick %d" % int(host.last_click_ms))
	h.check("and no sprite is latched for the release",
		int(preview.get("_press_channel")) == 0,
		"press channel %d" % int(preview.get("_press_channel")))
	preview.call("route_release", at)

	# The control: the same click, no wait.
	preview.set("_saw_press", true)
	host.click_sprite = -99
	host.click_loc = Vector2(-1, -1)
	host.last_click_ms = -1
	preview.call("route_press", at)
	h.check("without a wait the same press does reach the movie",
		int(host.click_sprite) != -99 and host.click_loc != Vector2(-1, -1)
		and int(host.last_click_ms) != -1,
		"clickOn %d clickLoc %s lastClick %d" % [
			int(host.click_sprite), str(host.click_loc), int(host.last_click_ms)])
	preview.call("route_release", at)
	h.complete("the press that ends a wait")


# ------------------------------------------------------------------ bugs.md 60

## A frame holding itself with a tempo delay steps once per delay, for ever.
##
## The fixture is built rather than found, because the pair the bug needs -- a
## delay cell *and* a script that holds the frame -- is a property of two
## different chunks and no movie can be relied on to have both on one frame. The
## delay is the movie's own: the first frame of the loaded score whose tempo cell
## decodes to one. The hold is a movie script compiled here and loaded into the
## real interpreter, which is the same `go to the frame` every room in every
## Director title is built on, and it counts its own runs in a global so the
## measurement is the movie's rather than the harness's.
##
## The number: over `RATE_WINDOW` seconds of movie time on a `delay` ms frame,
## Director runs `exitFrame` about `RATE_WINDOW / delay` times. This port armed
## the delay once, so after the first one it ran at the movie's frame rate --
## 15 or 8 times a second. The bound below is deliberately generous in the
## direction of the fix (an extra step for the one in flight when the window
## closes) and hard in the direction of the bug: a free-running frame at even 8
## fps produces forty steps in five seconds and cannot creep under it.
func _rate_case(h: Harness, preview: Node, window_override: int) -> void:
	h.begin("a self-holding delay frame")
	var score = preview.get("_score")
	if score == null:
		h.check("a score is loaded", false, "no movie")
		h.complete("a self-holding delay frame")
		return
	var found := -1
	var delay_ms := 0
	for i in int(score.frame_count):
		var frame: Dictionary = score.frame(i)
		if int(frame.get("delay_ms", 0)) > 0:
			found = i
			delay_ms = int(frame.get("delay_ms", 0))
			break
	if found < 0:
		# The `video_fallback` shape: say out loud that the fixture is absent and
		# assert nothing about it, rather than asserting against an empty set.
		h.check("this movie carries a tempo delay to measure", false,
			"no frame of %s writes one; point this at a movie that does"
			% preview.call("movie_path"))
		h.complete("a self-holding delay frame")
		return

	var holder := Compiler.new()
	var ast: Dictionary = holder.compile_source(
		"on exitFrame\n  global delaysteps\n  delaysteps = delaysteps + 1\n"
		+ "  go to the frame\nend\n", "MovieScript 9001")
	if ast.is_empty():
		h.check("the holding script compiles", false, holder.error)
		h.complete("a self-holding delay frame")
		return
	preview.get("_interpreter").load_bundle(
		{"movie": "WAITFRAMES", "cast": "harness", "scripts": {"MovieScript 9001": ast}},
		"WAITFRAMES")
	preview.get("_interpreter").globals["delaysteps"] = 0

	# Standing *on* the frame, with the entry already accounted for, which is the
	# state a room holding itself is in on every tick after the first.
	preview.set("_index", found)
	preview.set("_entered_index", found)
	preview.get("_clock").reset()
	FrameLoop.rearm_tempo(preview)
	h.check("the frame's delay is armed", preview.get("_clock").playhead_held(),
		"frame %d, %d ms, %s" % [found, delay_ms, preview.get("_clock").status()])

	var window := float(window_override) if window_override > 0 else RATE_WINDOW
	var spent := 0.0
	while spent < window:
		FrameLoop.tick(preview, TICK)
		spent += TICK
		if int(preview.get("_index")) != found:
			break
	var steps := int(preview.get("_interpreter").globals.get("delaysteps", 0))
	h.check("the frame held itself for the whole window",
		int(preview.get("_index")) == found,
		"landed on %d" % int(preview.get("_index")))
	var ceiling := int(ceil(window * 1000.0 / float(delay_ms))) + 1
	h.check("it steps once per delay, not once per frame",
		steps >= 1 and steps <= ceiling,
		"%d step(s) in %.1f s of a %d ms delay; at most %d" % [
			steps, window, delay_ms, ceiling])
	h.complete("a self-holding delay frame")


# ----------------------------------------------------------------- bugs.md 103

## A movie's cast-library keys are the movie's own.
##
## `start_lingo` is called at its own seam rather than through a `go to movie`,
## because the state this is about is established *by* that function and a movie
## handover would also swap the score, the cast table and the stage under it --
## three more reasons for a key to disappear, and no way to tell which one did it.
##
## The stale key is seeded at a library number the movie does not have, which is
## exactly the shape the bug produces: `dinner1.dir` hands over to `eat.dir` and
## leaves `{2: "DINNER1/doc", 3: "DINNER1/hezi", …}` under a movie whose only
## library is 1.
func _lib_keys_case(h: Harness, preview: Node) -> void:
	h.begin("the library keys a movie hands over")
	var keys: Dictionary = preview.get("_lib_keys")
	var libs: Dictionary = preview.get("_table").cast_libs
	var stale := 1
	while libs.has(stale):
		stale += 1
	keys[stale] = "PREVIOUS/doc"
	Boot.start_lingo(preview, preview.call("movie_path"))
	h.check("a key for a library this movie does not have is gone",
		not keys.has(stale), "library %d, keys %s" % [stale, str(keys.keys())])
	var strays: Array = []
	for number in keys:
		if not libs.has(int(number)):
			strays.append(int(number))
	h.check("and every key left names a library the movie declares",
		strays.is_empty(), "strays %s" % str(strays))
	h.check("the movie's own library is still keyed", keys.has(1),
		"keys %s" % str(keys.keys()))
	h.complete("the library keys a movie hands over")
