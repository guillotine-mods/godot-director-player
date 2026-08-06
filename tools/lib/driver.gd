extends RefCounted
## Drives a `DirectorRuntime` the way a player drives it, for the tools.
##
##   const Driver := preload("res://tools/lib/driver.gd")
##   const Hooks := preload("res://tools/lib/game_hooks.gd")
##   var d := Driver.new(self, Hooks.new())
##   d.open({"movie": "<movie>", "label": "<marker>"})
##   await d.run_for(20000, {"click_prompts": true})
##
## Title-agnostic. This file may reach into `director/` and `lingo/` and nothing
## else: no movie name, no channel number, no autoload by name. Everything that
## knows which game this is lives in `game_hooks.gd`, which is the one file
## rewritten when the lib is carried to another Director port. See
## `docs/superpowers/specs/2026-08-06-tools-lib-design.md`.

const RUNTIME_PATH := "res://director/director_runtime.gd"

## What a frame's clickable sprites are re-read at. Matches what the harnesses
## have always passed; the tick rate is not the point, the real time is.
const STEP_DELTA := 0.016

var runtime: RefCounted = null
var hooks: RefCounted = null

var _tree: SceneTree = null
var _counts: Dictionary = {}
var _sequence: Array[String] = []
var _steps := 0


## `tree` is load-bearing, not a convenience. `run_for` awaits this tree's
## `process_frame`, and that await is the difference between a working harness and
## one that hangs for ever: a synthetic `for i in N: tick()` loop advances the
## runtime's clock and *not* the audio server's, so no sound ever finishes, every
## `if soundBusy(1) then go to the frame` guard holds, and the score looks stuck
## when it is only waiting. That is bugs.md 22, which was diagnosed wrong twice.
func _init(tree: SceneTree, game_hooks: RefCounted = null) -> void:
	_tree = tree
	hooks = game_hooks


## Boot a fresh runtime and optionally walk it somewhere.
##
##   movie, label   where to start; omitted leaves the runtime un-navigated
##   frame          a frame number, as an alternative to `label`
##   flags          passed to the hooks, e.g. {"lingo_frames": true}
##   new_game       reset game state first (default true when hooks are present)
func open(opts: Dictionary = {}) -> bool:
	if hooks != null:
		hooks.configure(_tree, opts.get("flags", {}))
	runtime = load(RUNTIME_PATH).new()
	if runtime.boot() != OK:
		return false
	if hooks != null and bool(opts.get("new_game", true)):
		hooks.new_game(_tree)
	var movie := str(opts.get("movie", ""))
	if movie == "":
		return true
	var nav: Dictionary = {}
	if opts.has("label"):
		nav["label"] = str(opts["label"])
	return runtime.goto_movie(movie, opts.get("frame", null), nav)


## Walk an already-open runtime somewhere else, keeping its state. A sweep over
## several rooms wants this; a case that must not inherit the last room's state
## wants a second `open()` instead.
func go(movie_name: String, label: String = "") -> bool:
	var nav: Dictionary = {}
	if label != "":
		nav["label"] = label
	return runtime.goto_movie(movie_name, null, nav)


func movie() -> String:
	return str(runtime.loader.movie_name)


func frame() -> int:
	return int(runtime.frame_index)


## "MOVIE:frame" — the unit the trace counts.
func state() -> String:
	return "%s:%d" % [movie(), frame()]


func clickable() -> Array:
	return runtime.clickable_sprites(runtime.loader.get_frame(runtime.frame_index))


func sprite_on(channel: int) -> Dictionary:
	for s in clickable():
		if int((s as Dictionary).get("channel", 0)) == channel:
			return s
	return {}


func click(sprite: Dictionary) -> void:
	runtime.perform_click(runtime.sprite_stage_rect(sprite).get_center())


func click_channel(channel: int) -> bool:
	var sprite := sprite_on(channel)
	if sprite.is_empty():
		return false
	click(sprite)
	return true


## Step in real time for `ms`, recording the playhead.
##
##   click_prompts      click a sprite once the frame has offered one for `dwell`
##   dwell              frames to look at a prompt before picking (default 120)
##   after_click        frames to ignore prompts after clicking (default 600)
##   pick               Callable(Array) -> Dictionary, which sprite to click
##   until_movie_change stop as soon as the movie changes
##
## Returns {elapsed_ms, steps, clicks, click_frames, movie_changed, movie}.
##
## Detecting a prompt by *what the frame offers*, not by the playhead stalling, is
## deliberate. A Director wait loop ends on `go to marker(0)` and so cycles a whole
## span while it waits; the frame number moves every step and same-frame stall
## detection never fires. What marks a prompt is a clickable sprite being on offer.
func run_for(ms: int, opts: Dictionary = {}) -> Dictionary:
	var click_prompts := bool(opts.get("click_prompts", false))
	var dwell_frames := int(opts.get("dwell", 120))
	var after_click := int(opts.get("after_click", 600))
	var until_change := bool(opts.get("until_movie_change", false))
	var pick: Variant = opts.get("pick", null)
	var start_movie := movie()

	var start_ms := Time.get_ticks_msec()
	var dwell := 0
	var clicks := 0
	var click_frames: Array[int] = []
	var changed := false

	while Time.get_ticks_msec() - start_ms < ms:
		await _tree.process_frame
		runtime.tick(STEP_DELTA)
		_record()
		if movie() != start_movie:
			changed = true
			if until_change:
				break
		if not click_prompts:
			continue
		var offered := clickable()
		if offered.is_empty():
			dwell = 0
			continue
		dwell += 1
		if dwell <= dwell_frames:
			continue
		dwell = -after_click
		var chosen: Dictionary = (pick as Callable).call(offered) if pick is Callable else offered[0]
		if chosen.is_empty():
			continue
		clicks += 1
		click_frames.append(frame())
		click(chosen)

	return {
		"elapsed_ms": Time.get_ticks_msec() - start_ms,
		"steps": _steps,
		"clicks": clicks,
		"click_frames": click_frames,
		"movie_changed": changed,
		"movie": movie(),
	}


## There is deliberately no synthetic-tick helper here. A tool that wants one
## drives `driver.runtime.tick(delta)` itself and owns the decision, because the
## decision is not safe to make casually: stepping without real time is correct
## only where nothing under test waits on a real-time subsystem, and getting it
## wrong does not fail, it hangs.
func _record() -> void:
	_steps += 1
	var key := state()
	_counts[key] = int(_counts.get(key, 0)) + 1
	if _sequence.is_empty() or _sequence[-1] != key:
		_sequence.append(key)


## {distinct, steps, most_repeated, most_repeated_count, transitions, tail}
##
## `most_repeated` is where a score is sitting. High against a low `distinct` is a
## hold; high against a *high* distinct is a cycle, which is what a wait loop looks
## like and what makes it read as an infinite loop when it is not.
func trace(tail_size: int = 12) -> Dictionary:
	var worst := ""
	var worst_n := 0
	for key in _counts:
		if int(_counts[key]) > worst_n:
			worst_n = int(_counts[key])
			worst = str(key)
	var tail: Array[String] = []
	for i in range(maxi(0, _sequence.size() - tail_size), _sequence.size()):
		tail.append(_sequence[i])
	return {
		"distinct": _counts.size(),
		"steps": _steps,
		"most_repeated": worst,
		"most_repeated_count": worst_n,
		"transitions": _sequence.size(),
		"tail": tail,
	}
