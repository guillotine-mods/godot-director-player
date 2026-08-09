extends SceneTree
## Play the configured title from its boot movie and photograph every state it
## reaches, driving **both** the mouse and the keyboard.
##
##   godot --path . --script tools/qa_walk.gd -- --out /tmp/shots
##   godot --path . --script tools/qa_walk.gd -- --root rating --steps 60 --out /tmp/shots
##   godot --headless --path . --script tools/qa_walk.gd -- --root piposh2 --steps 40
##
##   --steps N     how many act-and-look turns to take (default 40)
##   --settle N    process frames to let a state settle before it is judged (60)
##   --warmup N    process frames to let the boot movie's opening run (600)
##   --ff N        fast-forward rate during the warmup (default 60, 0 = off)
##   --playff N    fast-forward rate during the walk (default 0 = the movie's own)
##   --avoid M:C   never press channel C of movie M -- repeatable, comma separated
##   --patience N  times a state must recur before this acts on it (default 2)
##   --blank N     inspections a stage must stay empty before it is flagged (30)
##   --stall N     call a state stalled after N turns that do not change it (6)
##   --out DIR     where the PNGs go (default /tmp/qa_walk)
##   --sweep       instead of walking, open every container and inspect it
##   --ticks N     process frames to inspect each container for in --sweep (180)
##   --strict      exit non-zero if anything stalled or looked wrong
##
## ## Why this exists
##
## `gate.sh` tests mechanisms one at a time and `liveness_sweep` opens every
## container **cold** and asks whether the playhead can move. Neither walks the
## first minute of a real game, and `porting-fidelity-verification` names that as
## the largest hole in this repo's verification: `tools/smoke.gd` was that test,
## it would have caught four of five shipped regressions, and it was deleted with
## the renderer it drove. All five of those regressions landed on boot, intro,
## collectables or pickups -- the stretch this walks.
##
## It is also the only tool here that produces **pictures**. A room that moves
## correctly and draws wrongly is invisible to every pass/fail harness in the
## repo, and this port's history is full of that shape: art drawn stretched, a
## face inside a white rectangle, a film loop's children drawn out of the wrong
## cast, a character drawn in front of the thing meant to hide him. Every one of
## those is obvious in a screenshot.
##
## ## The keyboard is not optional, and the keys are not a list
##
## Director gave the movie the whole keyboard, so a title gates a scene on a
## keypress as readily as on a click -- Rating's opening scene is one, and a
## mouse-only walker sits in front of it printing "nothing answers the mouse"
## until it runs out of turns. That reads as a stuck movie and is not.
##
## So which keys to press is a question about the *title*, and it is answered
## from the title's own scripts: `tools/lib/key_sites.gd` reads the Lingo out of
## the `CASt` records of the container that is playing and reports every literal
## `the key = "x"` character and `the keyCode = n` Mac code it tests. That is the
## same rule as everything else here -- ask the data, not a constant -- and it is
## the rule a hand-swept key list already broke once: the list in
## `director_keys.gd` was swept out of `reference/lingo/`, which is Piposh 2 and
## nothing else, and it called F10 free while Rating tests it at 48 sites.
##
## Presses go in through `_dispatch_key`, the way `tools/key_chain.gd` and
## `tools/key_polling.gd` drive them, which reaches the movie **without** passing
## the preview's own F-key bindings. A walker that went in through
## `Input.parse_input_event` would be pressing SKIP and the pause as it went.
##
## ## What it will not do
##
## **It stops when the movie quits.** `quit`/`halt` set the host's `stopped` and
## call `lingo_quit`, which does `set_process(false)` unconditionally and only
## takes the tree down when the preview is the running main scene -- which it is
## in a real game and is not under `--script`. So a walker that presses a menu's
## Exit line carries on clicking a player that has stopped processing, and the
## next movie it opens sits on frame 0 for ever. That reads exactly like a hard
## freeze and is the walker's own doing. `--avoid` is the other half: it names
## the buttons a walk should not press at all.
##
## **Reports, never asserts** -- unless `--strict`, which fails on a stall. There
## is no invariant here that holds across titles: a room with nothing clickable
## on it is an ordinary answer, and so is a cut scene that ignores the keyboard.
## What is worth reporting is a state that neither the mouse nor any key the
## container's own scripts test could move.
##
## ## What it flags while it plays
##
## A screenshot only helps if somebody looks at it, and a walk of any length
## produces more of them than anyone will. So four things the engine already
## knows during play, and which nothing else in this repo collects, are gathered
## as it goes and printed with the movie and frame that produced them:
##
##   * **a Lingo runtime error.** `LingoInterpreter.errors` is cleared at the
##     start of every dispatch and one score step dispatches four events, so this
##     polls on every process frame and accumulates. That makes it lossy in the
##     same way `liveness_sweep` documents -- an error raised in any but the last
##     dispatch of a process frame is gone before this can see it -- so a hit is
##     real and a clean run is not proof.
##   * **a warning the player half logged**: `Audio miss`, `Audio load fail` and
##     anything else that reaches `GameState.emit_log` at `warn`. These print to
##     a log nobody reads, which `audio_director.gd` says in as many words.
##   * **a sprite whose member does not resolve.** The channel is occupied, the
##     score says draw it, and nothing appears. That is a hole in the picture the
##     playhead is perfectly happy about.
##   * **a blank stage that persists** -- nothing drawn, no window open over it,
##     no hold to explain it, for `--blank` inspections running. The persistence
##     is the whole detector: a movie may legitimately *open* on an empty frame
##     and fill it a tick later, and flagging that reported `BADEND`,
##     `BLASNAKE`, `NAVIGAT3` and `MAINMENU-old` as blank when `liveness_sweep`
##     -- which requires a window of consecutive unexplained ticks -- calls all
##     four healthy. One-frame sensitivity is noise, not sensitivity.
##
## `--sweep` trades depth for breadth with the same detectors. A walk reaches
## the rooms a player reaches -- about fourteen of Rating's in two hundred turns
## -- and says nothing about the other seventy containers. The sweep opens every
## one, watches it, and reports the same four kinds. It cannot see anything that
## needs state a real boot sets, which is the standing caveat on every cold open
## here; run both.
##
## Title-agnostic. Nothing in this file knows what a game is called.

const Args := preload("res://tools/lib/args.gd")
const Harness := preload("res://tools/lib/harness.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const Keys := preload("res://director/director_keys.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")

## Pressed when the container that is playing tests no key of its own. Return and
## Space are Director's two conventional "carry on" keys and neither types into
## anything here, but this is a guess where everything above is a measurement --
## so it is said out loud in the log when it is used.
const FALLBACK_KEYS: Array[Key] = [KEY_ENTER, KEY_SPACE]

var _out := ""
var _shot_index := 0
## `<movie>|<marker>|<channel>` already pressed, and `...|k<code>` for keys.
##
## **Keyed by the marker region, not by the frame.** A room in these titles is a
## marker and the frames under it are its animation, so a hotspot that sits on
## every frame -- Rating's inventory bag is on all of `thehall**` -- is a *new*
## button on every one of them under a per-frame key, and the walk spends its
## whole budget opening and shutting the same bag. Per marker, one press is one
## press and the walk moves on to what it has not tried.
var _spent: Dictionary = {}
## `<movie>:<channel>` the caller asked this never to press.
var _avoid: Dictionary = {}
## Every movie change an act caused, as (from, what, to). Without this there is
## no record of which button reached the state being complained about.
var _went: Array = []
## Per-container key measurement, cached: `for_root` is a cast parse.
var _keys_for: Dictionary = {}
## States that neither the mouse nor the keyboard could move.
var _stalls: Array = []
## How many inspections in a row have found nothing on the stage, and how many
## in a row it takes to be worth saying.
var _blank_run := 0
var _blank_after := 30
## Everything that looked wrong, as `kind -> [where, ...]`. Grouped by kind and
## deduplicated, because one unresolved member on a room's backdrop is one
## finding and not one per frame the room is on.
var _flags: Dictionary = {}
var _root := ""


func _init() -> void:
	var args := Args.parse()
	_out = Args.text(args, "out", "/tmp/qa_walk")
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	for entry in Args.text(args, "avoid", "").split(",", false):
		_avoid[str(entry).strip_edges().to_lower()] = true

	var steps := Args.number(args, "steps", 40)
	var settle := Args.number(args, "settle", 60)
	var warmup := Args.number(args, "warmup", 600)
	var stall_after := Args.number(args, "stall", 6)
	_blank_after = Args.number(args, "blank", 30)
	# **A scene that is still going somewhere is not waiting for anything, and
	# pressing a key at it skips content a QA pass is there to look at.** Rating's
	# arrival is 335 frames and one Enter on its fourth frame jumps the whole
	# thing.
	#
	# But "waiting" is not "standing still", and reading it that way makes this
	# tool useless on the first screen it meets: Rating's main menu *animates*,
	# cycling frames 504-521 for ever, so no two turns running ever see the same
	# frame and a walker gated on stillness watches the menu until it runs out of
	# turns. What separates the two is **recurrence** -- a movie going somewhere
	# visits new frames, a movie waiting comes back round -- so an act is offered
	# once a state has been seen before within this visit to this movie.
	var patience := Args.number(args, "patience", 2)

	# **After a frame, and before the preview.** `_init` on a `SceneTree` runs at
	# construction, which is earlier than the autoloads are added to the tree, so
	# connecting here without the await found nothing and silently collected no
	# warnings at all -- a detector that reported clean while `Audio miss` lines
	# were going past on stdout. Reached through the tree rather than as a global
	# because an autoload is not an identifier a `--script` tool compiles
	# against, which is why every harness here uses `root.get_node_or_null` for
	# `AudioDirector` too.
	await process_frame
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state == null:
		print("GameState autoload is not in the tree -- warnings will not be collected")
	else:
		game_state.connect("log_message", _on_log)

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	if preview.get("_score") == null:
		print("no score loaded -- check [game] root and boot_movie")
		quit(1)
		return
	# The root the preview actually booted, read off the node rather than off the
	# config: `--root` is resolved inside `DirectorPaths.load_config`, so the
	# config file is not the answer when a flag overrode it.
	_root = str(preview.get("_paths").root) if preview.get("_paths") != null else ""

	if Args.flag(args, "sweep"):
		await _sweep(preview, Args.number(args, "ticks", 180))
		_report()
		quit(0 if _flags.is_empty() or not Args.flag(args, "strict") else 1)
		return

	# The boot movie's own opening runs before anything answers anything. Let it,
	# under the fast-forward toggle -- Rating's is 625 frames at 8 fps, and a
	# minute and a half of real time buys no pixels nobody has seen.
	#
	# Handed back before the first act unless `--playff` says otherwise. Fast
	# forward scales the clock the score and its holds are told about and *not*
	# the audio server's, so a movie that waits on `soundBusy` behaves
	# differently under it: fine for skipping an opening, wrong for judging what
	# an act did.
	preview.set("_fast_forward_fps", float(Args.number(args, "ff", 60)))
	for i in warmup:
		await process_frame
	preview.set("_fast_forward_fps", float(Args.number(args, "playff", 0)))

	# States seen since this movie was entered, and how many times the walk has
	# come back round to one it had already stood in.
	var visited := {}
	var recurred := 0
	var this_movie := ""
	var turns_here := 0
	for step in steps:
		for i in settle:
			await process_frame
			_poll_errors(preview)

		var state := _state(preview)
		_shot(preview, "%02d-%s-f%d" % [
			_shot_index, str(preview.call("movie_name")).to_lower().get_basename(),
			int(preview.call("current_frame"))])
		print("[%02d] %s" % [step, _describe(preview)])
		_inspect(preview)

		# **The room, not the container.** Rating keeps its whole hotel in
		# `NAVIGATE.dir` -- the hall, the lift and the corridors are marker
		# regions of one movie -- so counting turns per movie called the walk
		# stalled while it was moving between rooms perfectly well, and then it
		# recovered. A stall report that a later turn contradicts is worse than
		# no stall report.
		var movie := "%s|%s" % [
			str(preview.call("movie_name")),
			_marker(preview, int(preview.call("current_frame")))]
		if movie != this_movie:
			this_movie = movie
			visited.clear()
			recurred = 0
			turns_here = 0
		turns_here += 1
		if visited.has(state):
			recurred += 1
		visited[state] = true

		# The safety valve: a movie whose every frame is new for `--stall` turns
		# running is either a very long scene or one this cannot recognise, and
		# either way the walk has to try something rather than watch to the end
		# of its budget.
		if recurred < patience and turns_here < stall_after:
			print("       still moving -- watching")
			continue

		var acted := await _act(preview)
		print("       %s" % acted)

		# A state neither device moved, for `--stall` turns running. Recorded with
		# what was tried, because "nothing happened" is only a finding once it is
		# clear that something was attempted.
		if recurred >= patience and turns_here == stall_after * 2:
			var note := "%s -- %d turns in this room, nothing the mouse or the keys it tests moved it" % [
				state, turns_here]
			_stalls.append(note)
			print("       STALL: %s" % note)

		var host = preview.get("_host")
		if (host != null and bool(host.stopped)) or not preview.is_processing():
			print("       the movie quit -- a real run would have closed the window here")
			break

	_report()
	var h := Harness.new()
	if Args.flag(args, "strict"):
		h.begin("every state the walk stood in could be left, and looked right")
		h.check("nothing stalled", _stalls.is_empty(), "%d stall(s)" % _stalls.size())
		h.check("nothing looked wrong", _flags.is_empty(), "%d kind(s)" % _flags.size())
		h.complete("every state the walk stood in could be left, and looked right")
		quit(h.finish("a walk of the first minute"))
		return
	quit(0)


## Act on the state: press what answers the mouse, else press a key the container
## itself tests. Returns the line describing what was done.
func _act(preview: Node) -> String:
	var from_movie := str(preview.call("movie_name"))
	var target := _hotspot(preview)
	var what := ""
	if not target.is_empty():
		what = "ch%d" % int(target["channel"])
		print("       click ch%d at (%d,%d)  %s" % [
			int(target["channel"]), int(target["at"].x), int(target["at"].y),
			str(target["why"])])
		preview.call("route_press", target["at"])
		await process_frame
		preview.call("route_release", target["at"])
	else:
		var key := _key(preview)
		if key.is_empty():
			return "nothing answers the mouse, and every key this container tests has been tried"
		what = str(key["name"])
		# Press and release both. A press with no release leaves the key down for
		# every `the key` poll after it, and `the keyUpScript` -- 10 sites in
		# Rating, 195 in Piposh Dream -- never fires at all.
		var event := InputEventKey.new()
		event.keycode = key["code"] as Key
		event.pressed = true
		event.unicode = str(key["name"]).unicode_at(0) if str(key["name"]).length() == 1 else 0
		preview.call("_dispatch_key", event)
		await process_frame
		var up := InputEventKey.new()
		up.keycode = key["code"] as Key
		up.pressed = false
		preview.call("_dispatch_key_up", up)
		print("       key %s  (%s)" % [str(key["name"]), str(key["why"])])

	var to_movie := str(preview.call("movie_name"))
	if to_movie != from_movie:
		_went.append("%s %s -> %s" % [from_movie, what, to_movie])
	return "acted: %s" % what


## The movie a click will actually reach, and where its origin sits on the stage.
##
## **An open Movie-In-A-Window takes every click**, modal or merely in front, and
## `route_press` sends it there whole. A walker that goes on reading the stage's
## own score while one is open spends its entire budget pressing sprites the
## pointer cannot reach: measured on Rating's inventory, eleven turns of
## `mouseUp:NO HANDLER` against the window's frame script, then a stall report
## about a movie that was never being clicked.
func _subject(preview: Node) -> Array:
	var blocking = preview.call("modal_window")
	var front = blocking if blocking != null else preview.call("_front_window")
	if front != null and front != preview:
		return [front, (front.call("window_frame") as Rect2).position]
	return [preview, Vector2.ZERO]


## The topmost sprite of the movie a click would reach that answers the mouse and
## has not been pressed in this marker region. Topmost because that is the one a
## real click reaches first, and unspent because a button that re-enters its own
## room would otherwise be the only thing this ever pressed.
func _hotspot(preview: Node) -> Dictionary:
	var pair := _subject(preview)
	var subject: Node = pair[0]
	var origin: Vector2 = pair[1]
	var score = subject.get("_score")
	var table = subject.get("_table")
	if score == null:
		return {}
	var frame := int(subject.call("current_frame"))
	var movie := str(subject.call("movie_name"))
	var where := _marker(subject, frame)
	var best: Dictionary = {}
	# The topmost eligible sprite whether or not it has been pressed. **A walk
	# that only ever presses unspent buttons cannot shut a window it opened**:
	# the window swallows every click, and once its own controls are spent there
	# is nothing left the pointer can reach. Rating's inventory is the case --
	# open the bag, spend the close button, and the walk stands in front of it
	# for the rest of its budget. So an exhausted room gets its buttons a second
	# time rather than nothing.
	var again: Dictionary = {}
	for raw in score.frame(frame).get("sprites", []):
		var sprite: Dictionary = subject.call("_effective", raw)
		if sprite.is_empty():
			continue
		var why: String = Interaction.eligibility_reason(subject, sprite, table)
		if why == "":
			continue
		var channel := int(sprite["channel"])
		if _avoid.has("%s:%d" % [movie.to_lower(), channel]):
			continue
		var rect: Rect2 = subject.call("_stage_rect", sprite)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		again = {"channel": channel, "at": origin + rect.get_center(), "why": why + " (again)"}
		if _spent.has("%s|%s|%d" % [movie, where, channel]):
			continue
		# The window's own coordinates, put back on the stage: `route_press`
		# takes stage coordinates and maps them in with `stage_to_local`.
		best = {"channel": channel, "at": origin + rect.get_center(), "why": why}
	if best.is_empty():
		# Only once the keyboard has also been exhausted, so a scene waiting on a
		# key is not answered by pressing a button at it.
		if _keys_exhausted(subject):
			return again
		return {}
	_spent["%s|%s|%d" % [movie, where, int(best["channel"])]] = true
	return best


## Has every key this container tests already been tried in this room?
func _keys_exhausted(subject: Node) -> bool:
	var movie := str(subject.call("movie_name"))
	var where := _marker(subject, int(subject.call("current_frame")))
	for candidate in _vocabulary(subject, movie):
		if not _spent.has("%s|%s|k%d" % [movie, where, int(candidate["code"])]):
			return false
	return true


## A key the container that is playing actually tests, most-tested first, then
## the two conventional carry-on keys. Spent per (movie, frame) like a hotspot,
## so a scene is offered its whole vocabulary rather than one key repeatedly.
func _key(preview: Node) -> Dictionary:
	# The keyboard goes where the click goes: `input_router` sends a key to the
	# modal window if there is one, and the vocabulary has to be that movie's.
	var subject: Node = _subject(preview)[0]
	var movie := str(subject.call("movie_name"))
	var where := _marker(subject, int(subject.call("current_frame")))
	for candidate in _vocabulary(preview, movie):
		var code := int(candidate["code"])
		if _spent.has("%s|%s|k%d" % [movie, where, code]):
			continue
		_spent["%s|%s|k%d" % [movie, where, code]] = true
		return candidate
	return {}


## What this container asks the keyboard for, measured from its own Lingo.
func _vocabulary(preview: Node, movie: String) -> Array:
	if _keys_for.has(movie):
		return _keys_for[movie]

	var out: Array = []
	var root := _root
	if root != "":
		var sites: Dictionary = KeySites.for_root(root, movie)
		# Mac virtual key codes, back to the Godot key that produces them. Sorted
		# by how many sites test each, because the key a scene is waiting on is
		# usually the one it tests most.
		var by_code: Array = (sites.get("codes", {}) as Dictionary).keys()
		by_code.sort_custom(func(a, b): return _sites(sites, "codes", a) > _sites(sites, "codes", b))
		for mac in by_code:
			var godot_key := _godot_key(int(mac))
			if godot_key == KEY_NONE:
				continue
			out.append({
				"code": godot_key,
				"name": OS.get_keycode_string(godot_key),
				"why": "`the keyCode = %d` at %d site(s) in %s" % [
					int(mac), _sites(sites, "codes", mac), movie],
			})
		var by_char: Array = (sites.get("chars", {}) as Dictionary).keys()
		by_char.sort_custom(func(a, b): return _sites(sites, "chars", a) > _sites(sites, "chars", b))
		for character in by_char:
			var text := str(character)
			if text.length() != 1:
				continue
			var godot_key := OS.find_keycode_from_string(text.to_upper())
			if godot_key == KEY_NONE:
				continue
			out.append({
				"code": godot_key,
				"name": text,
				"why": "`the key = \"%s\"` at %d site(s) in %s" % [
					text, _sites(sites, "chars", character), movie],
			})

	for fallback in FALLBACK_KEYS:
		out.append({
			"code": fallback,
			"name": OS.get_keycode_string(fallback),
			"why": "this container tests no key of its own -- a guess, not a measurement",
		})
	_keys_for[movie] = out
	return out


func _sites(sites: Dictionary, bucket: String, key: Variant) -> int:
	return ((sites.get(bucket, {}) as Dictionary).get(key, []) as Array).size()


## Mac virtual key code back to the Godot key, by inverting `director_keys.gd`'s
## own table rather than keeping a second copy of it.
func _godot_key(mac: int) -> Key:
	for godot_key in Keys.MAC_CODES:
		if int(Keys.MAC_CODES[godot_key]) == mac:
			return godot_key
	return KEY_NONE


## The marker region a frame is inside -- the nearest label at or before it, and
## the movie's own name for the room. `""` where a movie carries no labels.
func _marker(preview: Node, frame: int) -> String:
	var labels = preview.get("_labels")
	if labels == null:
		return ""
	var best := ""
	var best_frame := -1
	for m in labels.markers:
		if int(m["frame"]) <= frame and int(m["frame"]) > best_frame:
			best_frame = int(m["frame"])
			best = str(m["name"])
	return best


## The identity of a state, for telling "the walk moved" from "the walk did not".
##
## An open window is part of it. The stage under one goes on running its own
## idle loop, so a state read from the stage alone recurs whatever the window
## does -- and the window is the movie the player is looking at.
func _state(preview: Node) -> String:
	var out := "%s f%d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame"))]
	var subject: Node = _subject(preview)[0]
	if subject != preview:
		out += " + %s f%d" % [
			str(subject.call("movie_name")), int(subject.call("current_frame"))]
	return out


## Movie, frame, marker, what is drawn, what the clock says is holding it, and
## any Movie-In-A-Window that is open over it.
func _describe(preview: Node) -> String:
	var frame := int(preview.call("current_frame"))
	var drawn := 0
	for raw in preview.call("frame_sprites"):
		if not (preview.call("_effective", raw) as Dictionary).is_empty():
			drawn += 1
	var named := _marker(preview, frame)
	var marker := "  (%s)" % named if named != "" else ""
	var clock = preview.get("_clock")
	var hold := "" if clock == null else str(clock.hold_reason())
	var windows: Dictionary = preview.get("_windows")
	return "%s f%d%s  %d drawn%s%s" % [
		str(preview.call("movie_name")), frame, marker, drawn,
		"  held: %s" % hold if hold != "" else "",
		"  window: %s" % str(windows.keys()) if windows != null and not windows.is_empty() else "",
	]


func _report() -> void:
	print("")
	print("movie changes an act caused:")
	for line in _went:
		print("   %s" % line)
	if _went.is_empty():
		print("   (none -- the walk never left the movie it started in)")
	print("")
	print("things that did not look right:")
	var kinds: Array = _flags.keys()
	kinds.sort()
	for kind in kinds:
		var where: Array = _flags[kind]
		print("   %s  (%d place(s))" % [kind, where.size()])
		for line in where.slice(0, 8):
			print("      %s" % line)
		if where.size() > 8:
			# Said out loud rather than truncated silently: a tool that prints a
			# count and a short list reads as a complete list, and two in this
			# repo shaped decisions for hours that way.
			print("      ... and %d more not printed" % (where.size() - 8))
	if _flags.is_empty():
		print("   (nothing)")
	print("")
	print("stalled states:")
	for line in _stalls:
		print("   %s" % line)
	if _stalls.is_empty():
		print("   (none)")
	print("")
	print("wrote %d shot(s) to %s" % [maxi(_shot_index, 0), _out])


## Open every container the title ships and inspect what it draws.
##
## No clicking and no keys: this is the breadth pass, and a click here would be a
## cold click on a movie entered without the globals a real boot sets -- which is
## exactly the reading `bugs.md` 36 carries two corrections about. What it can
## honestly report is what a container draws when opened, which is enough for a
## missing member, a missing sound or a Lingo error.
func _sweep(preview: Node, ticks: int) -> void:
	var paths = preview.get("_paths")
	if paths == null:
		print("no paths -- cannot enumerate the corpus")
		return
	var containers: Array = paths.containers()
	var movies: Array = []
	for relative in containers:
		if str(relative).to_lower().ends_with(".dir") or str(relative).to_lower().ends_with(".dxr"):
			movies.append(str(relative))
	movies.sort()
	print("sweeping %d movie(s) of %s, %d frame(s) each" % [
		movies.size(), str(paths.root), ticks])

	for relative in movies:
		_blank_run = 0
		preview.call("lingo_go_movie", relative, null)
		# The arriving movie runs its own `prepareMovie`/`startMovie` on the ticks
		# after the call, so nothing is worth reading for a few frames.
		for i in 8:
			await process_frame
		# **The score, not the name.** A movie that immediately hands off to
		# another has opened correctly -- the boot movie of every title does
		# exactly that -- so comparing the name called seventeen of Rating's
		# eighty-one unopenable when they had opened and moved on. This is the
		# test `liveness_sweep` settled on for the same reason.
		if preview.get("_score") == null:
			_flag("Would not open", "%s: no score after `go to movie`" % relative)
			continue
		for i in ticks:
			await process_frame
			_poll_errors(preview)
			_inspect(preview)
		print("  %-28s f%-6d %s" % [
			relative, int(preview.call("current_frame")), _describe(preview)])


## Record one anomaly, deduplicated by where it happened: a room's broken
## backdrop is one finding, not one per frame the room is drawn on.
func _flag(kind: String, where: String) -> void:
	var seen: Array = _flags.get(kind, [])
	if seen.has(where):
		return
	seen.append(where)
	_flags[kind] = seen


## Warnings the player half logs as it runs -- `Audio miss`, `Audio load fail`.
## They go to stdout and nowhere else, which `audio_director.gd` says is the
## whole problem with them.
func _on_log(message: String, level: String) -> void:
	if level == "warn" or level == "error":
		_flag(message.split(":")[0].strip_edges(), message)


## `LingoInterpreter.errors` is cleared at the start of each dispatch, so this
## has to run per process frame rather than per turn, and is still lossy.
func _poll_errors(preview: Node) -> void:
	var interpreter = preview.get("_interpreter")
	if interpreter == null:
		return
	for e in interpreter.errors:
		_flag("Lingo error", "%s f%d: %s" % [
			str(preview.call("movie_name")), int(preview.call("current_frame")), str(e)])


## What the stage looks like, asked of the engine rather than of the pixels.
func _inspect(preview: Node) -> void:
	var pair := _subject(preview)
	var subject: Node = pair[0]
	var movie := str(subject.call("movie_name"))
	var frame := int(subject.call("current_frame"))
	var where := "%s f%d%s" % [
		movie, frame,
		"  (%s)" % _marker(subject, frame) if _marker(subject, frame) != "" else ""]

	var table = subject.get("_table")
	var drawn := 0
	for raw in subject.call("frame_sprites"):
		var sprite: Dictionary = subject.call("_effective", raw)
		if sprite.is_empty():
			continue
		drawn += 1
		# The channel is occupied and the score says draw it. A member that does
		# not resolve is a hole in the picture that the playhead is happy about,
		# and nothing else here would ever mention it.
		#
		# **Both halves, because they come apart.** An empty member record is not
		# by itself "nothing was drawn": a shape has no image and draws, a field
		# has no image and draws its text, and a film loop resolves its children
		# through another path entirely. So the record has to be missing *and*
		# the renderer's own texture lookup has to come back with nothing --
		# which is the question actually being asked, rather than a proxy for it.
		if table != null:
			var member: Dictionary = table.get_member(
				int(sprite["cast_lib"]), int(sprite["cast_id"]))
			if member.is_empty() and subject.call("_texture_for", sprite) == null:
				_flag("Unresolved member", "%s ch%d wants %d:%d" % [
					where, int(sprite["channel"]),
					int(sprite["cast_lib"]), int(sprite["cast_id"])])

	# A bare stage is legitimate under an open window -- the window has its own
	# playhead and the stage under it is meant to be empty, which is the one
	# exemption `liveness_sweep` allows itself -- and equally while the clock is
	# holding for a transition or a palette effect, where nothing is composited
	# yet. Neither is a picture with a hole in it.
	var windows: Dictionary = preview.get("_windows")
	var covered: bool = windows != null and not windows.is_empty()
	var clock = preview.get("_clock")
	var holding: bool = clock != null and str(clock.hold_reason()) != ""
	if drawn == 0 and not covered and not holding:
		_blank_run += 1
		if _blank_run == _blank_after:
			# Once, on the inspection that crosses the threshold. Keyed with the
			# run length it would print the same frame once per frame after that.
			_flag("Blank stage", "%s (empty for %d inspections and counting)" % [
				where, _blank_run])
	else:
		_blank_run = 0


func _shot(preview: Node, name: String) -> void:
	# Asked of the display server rather than of the grab: headless Godot has a
	# dummy texture storage, so `get_image` does not return null quietly, it
	# errors once per turn and buries the walk's own output.
	if DisplayServer.get_name() == "headless":
		if _shot_index == 0:
			print("       (no pixels -- run windowed, without --headless, for shots)")
			_shot_index = -1
		return
	var image: Image = Snapshot.grab(preview)
	if image == null:
		# Headless Godot never paints, so there is nothing to save and saying so
		# beats writing a black rectangle that reads as a rendering bug later.
		if _shot_index == 0:
			print("       (no pixels -- run windowed, without --headless, for shots)")
		return
	image.save_png("%s%s.png" % [_out, name])
	_shot_index += 1
