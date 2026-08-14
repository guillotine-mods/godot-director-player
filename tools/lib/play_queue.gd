extends RefCounted
## Reach a screen by **playing into it**, from a script that is a queue.
##
##   const PlayQueue := preload("res://tools/lib/play_queue.gd")
##   var driver := PlayQueue.new(self, preview)          # self is the SceneTree
##   var run: Dictionary = await driver.run(PlayQueue.parse(spec), 560, 12)
##
## This is `tools/scratch/deepplay.gd`'s driver, lifted out of it so that an
## *instrument* can use it too. The reason it had to be lifted is `bugs.md` 108:
## the one question worth asking about Itamar Park's book hotspot -- is channel 94
## eligible at all -- is `tools/hotspots.gd`'s question, and `hotspots.gd` could
## not reach the frame, because getting to `AntPlay` needs the space key.
## `deepplay.gd` could reach it and is a driver rather than an instrument, so the
## session that found the bug had to stop. One driver, two front ends.
##
## ## Why a queue rather than a table of marker -> click
##
## Keying a step on the marker alone can only ever send a title to the *first* of
## its destinations, because a menu whose seven rooms all return to it is one
## marker seven times. Keying each step on `(what is on screen now, in order)`
## makes "menu -> tools -> back -> menu -> trivia" expressible: the head of the
## queue fires the moment its condition matches, and only then does the next step
## become eligible. Returning to a marker already used is therefore ordinary
## rather than a re-trigger.
##
## ## Nothing jumps
##
## Every marker is reached by the movie's own `go`, so every destination frame's
## `prepareFrame` runs. That is not a stylistic preference: the handler that hides
## Magic Hat's Yes/No dialog is a `prepareFrame`, and a marker jump leaves that
## dialog on top of the menu so that every subsequent click lands on it. Two wrong
## diagnoses in this project came from arriving somewhere without running it.
##
## ## The step grammar
##
##   --do "STEP;STEP;..."   the queue, in order. Each STEP is `WHEN=WHAT`.
##
##     WHEN   marker            front movie's current marker (case-insensitive)
##            movie@marker      ... and the front movie's file name matches
##            +N                N ticks after the previous step fired
##            *                 fires immediately
##            marker+N          marker, then N further ticks
##
##     WHAT   ch<N>             click the centre of channel N
##            m:<name>          click the centre of the sprite whose member is
##                              named <name> (the robust form: a title names its
##                              buttons and the score numbers them, and the
##                              numbering differs per screen)
##            xy:<x>,<y>        click that stage point
##            key:<c>           press and release character <c>
##            code:<n>          press and release Mac key code <n>
##            lingo:<stmt>      run one statement in the front movie
##            wait              do nothing (use to hold for a condition)
##
## `run` returns what happened, and the report is that dictionary rather than the
## print stream:
##
##   {"steps": 560, "fired": 3, "unfired": [...], "stopped": false,
##    "visited": [[state, ticks, step], ...]}
##
## **A step that never fired invalidates everything downstream of it**, which is
## why `unfired` is returned rather than merely printed: a harness that reports on
## "the frame the queue reached" has to be able to fail when the queue did not
## reach it.

const Windows := preload("res://scenes/preview/windows.gd")
const Keys := preload("res://director/director_keys.gd")

## The SceneTree, because `await tree.process_frame` is how a real frame is
## waited for and a `RefCounted` has no signal of its own. Awaiting real frames
## rather than ticking a loop is the rule `AGENTS.md` states at length: a
## synthetic tick advances the runtime's clock and not the audio server's, so
## every `soundBusy` guard holds for ever.
var _tree: SceneTree
## The stage preview node. `front()` walks down from it to whichever
## Movie-In-A-Window is on top.
var _p: Node
var _quiet := false
var _last := ""
var _visited: Array = []
## Called with `(index, what, where)` after every step that fired, for a caller
## that wants screenshots. Optional.
var on_step: Callable = Callable()


func _init(tree: SceneTree, preview: Node, quiet := false) -> void:
	_tree = tree
	_p = preview
	_quiet = quiet


## `"a=b;c=d"` -> `[["a", "b"], ["c", "d"]]`. Empty entries are dropped, so a
## trailing `;` is not a step.
static func parse(spec: String) -> Array:
	var out: Array = []
	for entry in spec.split(";", false):
		var bits := str(entry).split("=", true, 1)
		if bits.size() != 2:
			continue
		out.append([str(bits[0]).strip_edges(), str(bits[1]).strip_edges()])
	return out


## The movie a click or a key belongs to: the front-most open window, or the
## stage when none is open.
func front() -> Node:
	var w: Node = Windows.front(_p)
	return _p if w == null else w


## The marker a movie's playhead is inside -- the last one at or before it, which
## is what "which room is this" means in a Director score.
static func marker_of(f: Node) -> String:
	var label := ""
	var labels = f.get("_labels")
	if labels != null:
		for marker in labels.markers:
			if int(marker.get("frame", 0)) <= int(f.get("_index")):
				label = str(marker.get("name", ""))
	return label


func where() -> String:
	var f := front()
	var label := marker_of(f)
	return "%s:%d%s" % [str(f.call("movie_name")), int(f.get("_index")),
		("" if label == "" else " [" + label + "]")]


func _key() -> String:
	var f := front()
	return "%s [%s]" % [str(f.call("movie_name")), marker_of(f)]


## A window stack that is deeper or shallower than it was is a screen change even
## when the front movie's marker did not move, so the depth is part of the key.
func _state() -> String:
	return "%s d%d" % [_key(), _depth()]


func _depth() -> int:
	var n := 0
	for c in _p.get_children():
		if c.has_method("movie_name") and c != _p:
			n += 1
	return n


func _note(step: int) -> void:
	var now := _state()
	if now == _last:
		if not _visited.is_empty():
			_visited[-1][1] = int(_visited[-1][1]) + 1
		return
	_last = now
	_visited.append([now, 1, step])
	if not _quiet:
		print("  t%-5d %s" % [step, where()])


## Where to aim a click for `ch<N>` or `m:<name>`, in the front movie's own
## space, or (-1, -1).
##
## Through `_effective`, which is what the painter and the hit test use.
## `frame_sprites()` merges only whole-sprite puppets, so a sprite whose locH or
## member was puppeted reads at its *score* position here and the click lands
## where the art no longer is.
##
## `ignore_visible` is **false**, and the difference is the whole point: a title
## that puts two alternative button rows in the score and hides one of them in
## `prepareFrame` offers a channel from the hidden row to an ignore-visible
## reading, and a click aimed at it lands on the backdrop -- a miss that reads in
## the log exactly like a button that does not answer.
func sprite_at(f: Node, want_channel: int, want_name: String) -> Vector2:
	var table = f.get("_table")
	var best := Vector2(-1, -1)
	for s in (f.call("frame_sprites") as Array):
		var sprite: Dictionary = s
		sprite = f.call("_effective", sprite, false)
		if sprite.is_empty():
			continue
		var ch := int(sprite.get("channel", 0))
		if want_channel > 0 and ch != want_channel:
			continue
		if want_name != "":
			var m: Dictionary = table.get_member(
				int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0)))
			if str(m.get("name", "")).to_lower() != want_name:
				continue
		var r: Rect2 = f.call("_sprite_rect", sprite)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		best = r.position + r.size * 0.5
	return best


## A press and a release three real frames apart, routed through the stage so
## that the window hit test decides which movie gets it.
func click(at: Vector2, f: Node) -> void:
	var stage_at := at
	if f != _p:
		stage_at = f.position + at * (f.call("window_scale") as Vector2)
	_p.call("route_press", stage_at)
	for i in 3:
		await _tree.process_frame
	_p.call("route_release", stage_at)


## `the keyCode` is derived from the Godot keycode through `Keys.MAC_CODES`, so a
## synthetic press cannot carry a Mac code as metadata -- it has to arrive on a
## key the table maps to that code. Inverted here rather than hand-listed for the
## reason `tools/lib/key_sites.gd` exists: a hand list was already wrong once.
##
## Through `_dispatch_key` rather than `Input.parse_input_event`, or the walk
## presses the preview's own debug bindings -- SKIP, pause, restart -- as it goes.
func press_key(ch: String, code: int) -> void:
	var down := InputEventKey.new()
	down.pressed = true
	if ch != "":
		down.unicode = ch.unicode_at(0)
		down.keycode = ch.to_upper().unicode_at(0)
	if code >= 0:
		for gd in Keys.MAC_CODES.keys():
			if int(Keys.MAC_CODES[gd]) == code:
				down.keycode = gd
				break
	_p.call("_dispatch_key", down)
	for i in 3:
		await _tree.process_frame
	var up := InputEventKey.new()
	up.pressed = false
	up.unicode = down.unicode
	up.keycode = down.keycode
	_p.call("_dispatch_key_up", up)


func _do(what: String) -> String:
	var f := front()
	if what == "wait":
		return "wait"
	if what.begins_with("key:"):
		await press_key(what.substr(4), -1)
		return "key %s" % what.substr(4)
	if what.begins_with("code:"):
		await press_key("", int(what.substr(5)))
		return "code %s" % what.substr(5)
	if what.begins_with("lingo:"):
		# For the state a screen is *gated* on. It is not a substitute for reaching
		# a screen by clicking -- every navigation step here is still a click.
		var interp = f.get("_interpreter")
		var errs: Array = []
		var code = interp.compile_statements(what.substr(6), "playqueue", errs)
		if not errs.is_empty():
			print("     !! lingo compile %s" % str(errs))
			return "COMPILE-FAIL"
		interp.reset_steps()
		interp.run_compiled(code)
		return "lingo %s" % what.substr(6)
	var at := Vector2(-1, -1)
	var label := what
	if what.begins_with("xy:"):
		var bits := what.substr(3).split(",")
		at = Vector2(int(bits[0]), int(bits[1]))
	elif what.begins_with("m:"):
		at = sprite_at(f, 0, what.substr(2).to_lower())
	elif what.begins_with("ch"):
		at = sprite_at(f, int(what.substr(2)), "")
	if at.x < 0:
		print("     !! %s is not on screen in %s" % [what, where()])
		return "MISS %s" % label
	await click(at, f)
	return "%s at (%d,%d)" % [label, at.x, at.y]


## Drive the queue for `total` real frames and report what happened.
##
## `settle` is the cooldown after each step: the ticks the movie is given to get
## where the step sent it before the next step is even looked at. Too small and a
## queue keyed on markers fires two steps into one transition.
##
## `stop_when_drained` is for an **instrument** rather than a driver. A driver
## wants the rest of its budget after the last step, because what the title does
## unattended is part of what it came to see; a tool that is about to report on
## "the frame the queue reached" wants to stop there instead, or the movie plays
## on and the report describes somewhere else. It stops once the queue is empty
## and the last step's `settle` has been paid.
func run(queue: Array, total: int, settle: int,
		stop_when_drained := false) -> Dictionary:
	var since := 0
	var cooldown := 0
	var step := 0
	var fired := 0
	var stopped := false
	while step < total:
		await _tree.process_frame
		step += 1
		since += 1
		_note(step)
		var h = _p.get("_host")
		if h != null and bool(h.stopped):
			# `quit`/`halt` set `stopped` and stop the preview processing, and a
			# driver that carries on clicking a stopped player watches a frozen
			# stage and reports it as a hard freeze.
			print("  t%-5d STOPPED (quit/halt)" % step)
			stopped = true
			break
		if cooldown > 0:
			cooldown -= 1
			continue
		if queue.is_empty():
			if stop_when_drained:
				break
			continue
		var when: String = queue[0][0]
		var hold := 0
		if when.contains("+"):
			hold = int(when.get_slice("+", 1))
			when = when.get_slice("+", 0)
		var ready := false
		if when == "*":
			ready = true
		elif when == "":
			ready = since >= hold
		elif when.contains("@"):
			var f := front()
			ready = str(f.call("movie_name")).to_lower().ends_with(
					when.get_slice("@", 0).to_lower()) \
				and marker_of(f).to_lower() == when.get_slice("@", 1).to_lower()
		else:
			ready = marker_of(front()).to_lower() == when.to_lower()
		if not ready:
			continue
		if hold > 0 and when != "":
			queue[0][0] = when
			# Counted down in place so the marker test is not re-run: the movie may
			# well have left the marker by the time the hold expires, and the step
			# was already decided.
			var waited := 0
			while waited < hold and step < total:
				await _tree.process_frame
				step += 1
				waited += 1
				_note(step)
		var act: Array = queue.pop_front()
		var before := where()
		var did: String = await _do(str(act[1]))
		fired += 1
		print(">> [%s] %s  ->  %s" % [str(act[0]), did, before])
		if on_step.is_valid():
			on_step.call(fired, str(act[1]), before)
		since = 0
		cooldown = settle
	return {
		"steps": step, "fired": fired, "unfired": queue.duplicate(true),
		"stopped": stopped, "visited": _visited,
	}


## The visited list, which is the report: a screen that was reached and a screen
## that was not are one line apart.
func print_visited() -> void:
	print("--- visited (%d state(s)):" % _visited.size())
	for v in _visited:
		print("   t%-6d %-52s held %d tick(s)" % [int(v[2]), str(v[0]), int(v[1])])
