extends SceneTree
## Play one minigame the way a player does, and report whether anything it owns
## actually moved.
##
##   godot --headless --path . --audio-driver Dummy --script tools/minigame_probe.gd -- \
##       --root piposh --movie SLOTMACH.dir --ticks 900 --every 40
##   godot --headless --path . --audio-driver Dummy --script tools/minigame_probe.gd -- \
##       --root piposh-dream --movie hex1.dir --keys --ticks 1200
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --boot B      the boot movie. **Required with `--root rating`**, and not
##                 parsed here: `DirectorPaths.load_config` claims the flag.
##                 `--root` alone takes the boot movie from `director_game.cfg`,
##                 which names `strtgame.dir`; rating ships no such container, so
##                 the boot fails, the preview holds no movie, and the first
##                 `lingo_go_movie` raises `Invalid access to property 'path' on
##                 a base object of type 'Nil'`. Five of rating's minigames were
##                 measured as `no score loaded after go to movie` that way and
##                 not one of them was broken. `gate.sh:70` and `bugs.md` 51
##                 carry the same trap.
##   --movie M     the container to play (required)
##   --await MK    **wait for marker `MK` before the budget starts.** See below.
##   --await-hotspot
##                 wait until the frame offers an eligible hotspot, instead of or
##                 as well as a marker
##   --await-ticks N  ceiling on that wait, in process frames (default 3000)
##   --await-click    press hotspots on the `--every` cadence *during* the wait,
##                 for an intro that hands over on a click rather than by itself
##   --warmup N    process frames to let the *boot* movie run before hopping (240)
##   --ticks N     process frames to play the target for (default 900)
##   --every K     act — one click, or one key — every K process frames (40)
##   --keys        also press the keys this title's own scripts test for
##   --watch a,b   globals to print on every sample, in addition to the diff
##   --poll-mouse  on a tick that offers no hotspot, press the raw button anyway,
##                 for a minigame played by `if the mouseDown` rather than by
##                 sprite scripts. See below.
##   --no-click    watch only; do not touch the mouse
##   --verbose     print every sample rather than every *change*
##
## ## Why this is not `liveness_sweep --click`
##
## The sweep answers "can the playhead leave", which is a question about the
## *movie*. A minigame can answer it perfectly and still be unplayable, and this
## port has shipped exactly that four times: Piposh Dream's platformer and duel
## could not move, its hex board answered no click, its plate game could be
## neither won nor lost, and Hatuli's game had no projectiles. Every one of those
## is a movie whose playhead cycles happily for ever, so every one of them is
## `ok` to the sweep. The sweep also clicks **once** per hotspot and stops at the
## first verdict; a minigame is a loop that needs to be poked for a while before
## it can be won or lost at all.
##
## So the question here is different: **did the state a minigame keeps change?**
## Three sources are watched, and they are watched because between them they are
## what every one of these games scores itself with:
##
##   * the interpreter's **globals**, which is where `slotnums`, `plantcounter`
##     and the rest of the corpus's counters live;
##   * the preview's **`_field_text`**, because Director's HUD is a field and
##     `put value(the text of field "globalmoney") + …` is how three of Piposh
##     1's games pay out;
##   * the **members drawn**, per channel, because a member swap is how the score
##     shows a reel spinning, a piece moving or a projectile existing at all.
##
## A minigame where all three are frozen across hundreds of ticks of clicking is
## the shape of every one of the four bugs above, and no existing harness in this
## repo can see it.
##
## ## Why the boot movie runs first
##
## `director-qa-playthrough` records that `liveness_sweep` opens every container
## cold, so it never arrives carrying the globals a real boot sets, and that
## `bugs.md` 36 carries two corrections that came from exactly that. The warmup
## here is the cheap half of the fix: the title's own boot movie runs for
## `--warmup` frames first, so `setmoviepath`, `soundspath`, `globalday` and the
## rest exist before the target movie is entered. It is **not** a full playthrough
## and does not claim to be — a finding from this tool that depends on game
## progress still has to be re-reached by playing, which is what the skill says
## and what this paragraph exists to keep saying.
##
## The hop itself is `lingo_go_movie`, never a marker jump. A jump does not run
## the destination frame's `prepareFrame`, and two wrong diagnoses in this repo
## came out of exactly that; a movie change enters at frame 0 and plays forward,
## which is what a player's `go to movie` does too.
##
## ## What this tool cannot be pointed at: a Movie-In-A-Window
##
## Two of Piposh 2's set pieces are **windows opened over a room**, not movies the
## playhead ever enters, and probing them here produces a confident false finding
## each time:
##
##   * `JOKE.dir` — 3 sprites, `scripts found: 0 of 3`, `unresolved mbr [2,40,1]`,
##     nothing dispatched over 900 ticks. Reads as a dead movie. It is a window;
##     `tools/window_renders.gd` is the instrument, and its `--window` default is
##     this very file.
##   * `MAP.dir` — every destination button is `tell the stage / peoplefunk()`.
##     Opened standalone the stage *is* this movie, `peoplefunk` is defined in the
##     room's cast and not here, and the probe reports `builtins unbound:
##     {"peoplefunk": 27}` — which looks exactly like `bugs.md` 21's missing
##     character placement and is nothing of the kind.
##
## The tell is `tell the stage` in the movie's own source, or a container that no
## `go to movie` in the corpus names. Grep before believing a verdict from here.
##
## ## Acting on a clock, not on stillness
##
## The skill's rule is that "waiting for input" is recurrence rather than
## stillness — Rating's main menu cycles frames 504-521 for ever, so a walker
## gated on a still frame watches it until its budget runs out. A minigame is
## worse: it animates *while* it waits, and it often wants to be clicked mid
## animation. So this acts on a fixed cadence (`--every`) instead of on a
## settled state, and cycles through the frame's eligible sprites so a game with
## one live button and forty dead ones is still reached.
##
## ## Waiting on a marker, not on a tick budget
##
## **A tick budget cannot tell a dead board from a long intro**, and `bugs.md`
## 113 is that measurement made twice. Piposh 2's chess reached `ches1`,
## drew 16 pieces, swapped members on 5 of 17 channels and offered **0 hotspots
## in 900 ticks**; Piposh Dream's hex never arrived at all, because its intro
## cycles to frame 148 and the board is at 216. The first reads as a dead board
## and the second as an unreachable one, and neither reading is supported: what
## both actually measure is that the budget ran out somewhere inside the intro.
## `bugs.md` 105 is the proof that this instrument has been wrong about exactly
## this — the hex board *does* offer three eligible tiles when it is played into.
##
## So the budget no longer starts when the movie is entered. It starts when the
## movie says it is ready, and the movie says so in the only vocabulary its own
## scripts use: **a marker**. No script in this corpus says `go to frame 216`;
## they all say `go("game")`. `--await <marker>` spins on real awaited frames
## until `_marker` answers that name, and only then does the measured budget
## begin — so "0 hotspots in 900 ticks" becomes a statement about 900 ticks
## *of the board*, which is the sentence somebody wanted in the first place.
##
## `--await-hotspot` is the same idea without needing to know the marker: wait
## until the frame offers something clickable at all. It is weaker evidence —
## an intro's own SKIP button is a hotspot — so the two compose, and where the
## marker is known the marker is better.
##
## **The wait is reported, and a wait that runs out is reported as undecided
## rather than as a zero.** Every marker visited on the way is printed with the
## ticks spent in it, so a run that never arrives says which room it was still
## in. That is the half `bugs.md` 113 asks for: not a bigger budget, but an
## instrument that can tell "the board offered nothing" from "the board was
## never on screen", and that refuses to print the first when it measured the
## second.
##
## ## A minigame with no hotspots is not a dead minigame
##
## The other half of `bugs.md` 113, and the half that turned out to be the whole
## answer for chess. This tool presses *hotspots*: a sprite the engine says
## responds to the mouse, at a point the engine says reaches it. A Director movie
## does not have to be played that way, and Piposh 2's chess is not:
##
##     on exitFrame
##       if the mouseDown then
##         sound playFile 1, soundspath & "art" & member(the memberNum of sprite 8).name & ".aif"
##         repeat with i = 8 to 15
##           puppetSprite(i, 1)
##         end repeat
##         go(marker(1))
##       else
##         go(marker(0))
##       end if
##     end
##
## — `reference/lingo/CHESS/master/BehaviorScript 81.ls`, and three more like it.
## Channel 8 cycles seven members and the button stops it wherever it is; the
## board is a slot machine and **there is no hotspot anywhere in it**. So "0 of
## 900 ticks offered a hotspot" was a true measurement of a movie that has none
## by construction, and reading it as a dead board is the same class of error as
## `bugs.md` 105.
##
## `--poll-mouse` is the answer: on any tick that offers nothing to click, press
## the raw button anyway, through `Input.parse_input_event` exactly as
## `tools/mouse_poll.gd` does — a poll answered from the live button state, which
## is what `the mouseDown` reads. A poll-driven game then moves, and a genuinely
## dead one still does not, which is the distinction the tick budget could never
## draw.
##
## Reports, never asserts. There is no invariant that holds across six titles'
## minigames — a game that ends on the first click is a legitimate answer — so
## this prints and exits 0, and the harness that asserts something comes after.

const Args := preload("res://tools/lib/args.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const Keys := preload("res://director/director_keys.gd")

## How many distinct hotspots to remember having pressed, keyed by
## `(frame-marker, channel)` rather than by frame. `director-qa-playthrough`:
## a room in these titles is a marker and the frames under it are its animation,
## so a hotspot keyed per frame is a brand-new button on every frame and the
## budget goes on opening and shutting the same thing.
var _pressed: Dictionary = {}
## Raw button presses made by `--poll-mouse`, counted so a run that pressed
## nothing and a run that pressed a hundred times do not print the same report.
var _polls := 0
## Process frames a `--poll-mouse` press is held for. These movies run at 4 to 8
## fps and a press released inside one process frame lands between two of the
## movie's own polls; 12 frames is comfortably longer than one score step at 8
## fps and is what `tools/mouse_poll.gd` measured as the difference between 2 of
## 8 clicks seen and 8 of 8.
const POLL_HOLD_FRAMES := 12
var _clicks: Array[String] = []
var _keys_sent: Array[String] = []
var _samples: Array[Dictionary] = []


func _init() -> void:
	var args := Args.parse()
	var movie := Args.text(args, "movie", "")
	if movie == "":
		print("--movie is required")
		quit(1)
		return

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var boot := str(preview.call("movie_name"))
	for i in Args.number(args, "warmup", 240):
		await process_frame
	print("boot     : %s -> %s after warmup" % [boot, str(preview.call("movie_name"))])

	var keys: Array[int] = []
	if Args.flag(args, "keys"):
		# `preview._paths`, which is where the resolver lives — there is **no
		# `DirectorPaths` autoload**, and asking `root` for one returns null, so
		# the first version computed an empty root, `for_root` scanned nothing,
		# and every title printed `keys :` with nothing after it. A key-driven
		# game then reads as one that ignores the keyboard, which is the exact
		# false finding `director-qa-playthrough` opens by warning about.
		# `tools/qa_walk.gd:211` reads it the same way.
		var paths = preview.get("_paths")
		var root_dir := str(paths.root) if paths != null else ""
		if root_dir != "":
			keys = _key_codes(root_dir, movie)
		var names: Array[String] = []
		for code in keys:
			names.append(OS.get_keycode_string(code as Key))
		print("keys     : %s" % ", ".join(names))

	preview.call("lingo_go_movie", movie, null)
	# A movie change is entered by the next step, not by the call, so the
	# playhead is still in the old movie for one frame. `tools/click_trace.gd`
	# carries the same note.
	await process_frame
	await process_frame
	print("entered  : %s frame %d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame"))])

	var interp = preview.get("_interpreter")
	var globals_before := _snapshot_globals(interp)
	var fields_before := _snapshot_fields(preview)
	var members: Dictionary = {}

	var ticks := Args.number(args, "ticks", 900)
	var every := maxi(1, Args.number(args, "every", 40))
	var click := not Args.flag(args, "no-click")
	var poll_mouse := Args.flag(args, "poll-mouse")
	var verbose := Args.flag(args, "verbose")
	var watch := Args.text(args, "watch", "").to_lower().split(",", false)

	# The wait, before anything is measured. `_await_ready` returns what it did,
	# and everything printed below says whether the budget was spent on the thing
	# that was asked about or on whatever came before it.
	var wait: Dictionary = await _await_ready(preview, args, every, click)
	if not wait.is_empty():
		_report_wait(wait)
		# **Re-baselined after the wait**, so the diff is about the budget rather
		# than about the intro. A wait that runs half a minute of speech and two
		# room changes moves dozens of globals, and folding those into the answer
		# is how "nothing moved" and "everything moved" become equally unreadable.
		globals_before = _snapshot_globals(interp)
		fields_before = _snapshot_fields(preview)
		members.clear()

	var last_line := ""
	var key_at := 0
	# How much of the budget offered anything to click at all. `bugs.md` 113 is a
	# zero here that nobody could attribute, so it is now counted beside the
	# marker it was counted in.
	var offering := 0
	var offering_by_marker: Dictionary = {}
	for i in ticks:
		await process_frame
		if _stopped(preview):
			print("stopped  : the movie called quit/halt at tick %d" % i)
			break
		_record_members(preview, members)
		var here := _marker(preview, 0)
		var seen_here: Array = offering_by_marker.get(here, [0, 0])
		seen_here[0] = int(seen_here[0]) + 1
		if _offers_hotspot(preview):
			offering += 1
			seen_here[1] = int(seen_here[1]) + 1
		offering_by_marker[here] = seen_here
		var line := _state_line(preview, interp, watch)
		if verbose or line != last_line:
			_samples.append({"tick": i, "line": line})
			last_line = line
		if i % every != every - 1:
			continue
		if click:
			# `_press_one` returns false when the frame offered nothing. That is
			# the case `--poll-mouse` is for, and it is checked here rather than
			# inside `_press_one` so that a movie which offers a hotspot keeps
			# being driven through the hotspot -- pressing the raw button at a
			# board that *does* have buttons would answer a different question.
			if not _press_one(preview) and poll_mouse:
				await _poll_button(preview)
		if not keys.is_empty():
			_press_key(preview, keys[key_at % keys.size()])
			key_at += 1

	print("")
	print("== timeline (%d change(s) over %d tick(s))" % [_samples.size(), ticks])
	for sample in _samples:
		print("  t%-5d %s" % [int(sample["tick"]), str(sample["line"])])

	print("")
	# **The number `bugs.md` 113 was about, with the marker attached.** "0 of 900
	# ticks offered a hotspot" is unreadable without knowing which room the 900
	# were spent in; this says it per marker, so a zero on the board and a zero in
	# the intro are different lines rather than the same one.
	print("== hotspots offered on %d of %d tick(s)" % [offering, ticks])
	var marker_keys: Array = offering_by_marker.keys()
	marker_keys.sort()
	for marker in marker_keys:
		var pair: Array = offering_by_marker[marker]
		print("  %-16s %d of %d tick(s)" % [
			str(marker) if str(marker) != "" else "<no marker>",
			int(pair[1]), int(pair[0])])

	if _polls > 0:
		print("  raw button pressed %d time(s) on ticks that offered no hotspot "
			% _polls + "(--poll-mouse)")

	print("")
	print("== clicks (%d)" % _clicks.size())
	for entry in _clicks:
		print("  " + entry)
	if not _keys_sent.is_empty():
		print("== keys sent: %s" % ", ".join(_keys_sent))

	print("")
	_report_diff("globals", globals_before, _snapshot_globals(interp))
	_report_diff("fields", fields_before, _snapshot_fields(preview))

	print("")
	print("== members seen per channel (channel: member(s))")
	var changed := 0
	var channels := members.keys()
	channels.sort()
	for channel in channels:
		var seen: Array = members[channel]
		if seen.size() > 1:
			changed += 1
		print("  ch%-4d %s" % [int(channel), str(seen).substr(0, 110)])
	print("  %d of %d channel(s) ever swapped member" % [changed, channels.size()])
	quit(0)


## Spin on real awaited frames until the movie is where the caller asked, and
## report what happened on the way. `{}` when nothing was asked, which leaves the
## old behaviour exactly as it was.
##
## **Real frames, never a synthetic loop.** AGENTS.md's rule, and it is load
## bearing here more than anywhere: what these waits are waiting through is
## speech, and a `for i in N: tick()` advances the runtime's clock and not the
## audio server's, so every `soundBusy` guard holds for ever and the wait can
## never end. `bugs.md` 22 was diagnosed wrong twice on exactly that.
##
## **The ceiling is a ceiling, not a budget.** Reaching it is reported as
## `NOT REACHED` and the caller prints the whole itinerary, because a wait that
## ran out is a measurement of the intro and must not be presented as a
## measurement of the board.
func _await_ready(preview: Node, args: Dictionary, every: int, click: bool) -> Dictionary:
	var want_marker := Args.text(args, "await", "").strip_edges().to_lower()
	var want_hotspot := Args.flag(args, "await-hotspot")
	if want_marker == "" and not want_hotspot:
		return {}
	var ceiling := Args.number(args, "await-ticks", 3000)
	var also_click: bool = click and Args.flag(args, "await-click")
	# marker -> ticks spent in it, in arrival order, so the report reads as an
	# itinerary rather than as a set.
	var visited: Array[String] = []
	var spent: Dictionary = {}
	var reached := false
	var at := 0
	while at < ceiling:
		await process_frame
		at += 1
		if _stopped(preview):
			break
		var here := _marker(preview, 0)
		if not spent.has(here):
			visited.append(here)
		spent[here] = int(spent.get(here, 0)) + 1
		var marker_ok := want_marker == "" or here.to_lower() == want_marker
		var hotspot_ok := not want_hotspot or _offers_hotspot(preview)
		if marker_ok and hotspot_ok:
			reached = true
			break
		if also_click and at % every == every - 1:
			_press_one(preview)
	return {
		"marker": want_marker, "hotspot": want_hotspot, "ticks": at,
		"ceiling": ceiling, "reached": reached, "visited": visited, "spent": spent,
		"clicked": also_click,
	}


func _report_wait(wait: Dictionary) -> void:
	var wanted: Array[String] = []
	if str(wait["marker"]) != "":
		wanted.append("marker '%s'" % str(wait["marker"]))
	if bool(wait["hotspot"]):
		wanted.append("a hotspot")
	print("await    : %s -> %s after %d tick(s) of %d%s" % [
		" and ".join(wanted),
		"REACHED" if bool(wait["reached"]) else "NOT REACHED",
		int(wait["ticks"]), int(wait["ceiling"]),
		", clicking" if bool(wait["clicked"]) else ""])
	var itinerary: Array[String] = []
	var spent: Dictionary = wait["spent"]
	for marker in (wait["visited"] as Array):
		itinerary.append("%s x%d" % [
			str(marker) if str(marker) != "" else "<no marker>",
			int(spent[marker])])
	print("           through: %s" % " -> ".join(itinerary))
	if not bool(wait["reached"]):
		# Said in words, because the whole of `bugs.md` 113 is a reader taking a
		# number measured before the subject arrived as a number about the
		# subject. Everything below this line describes the itinerary above.
		print("           UNDECIDED: the budget below was spent before the wait was "
			+ "satisfied, so it measures the rooms listed above and not the one asked for.")


## Whether this frame offers anything a player could click, by the engine's own
## eligibility and reachability rules — the same two `_press_one` uses, so a
## count of "offered" cannot disagree with what actually gets pressed.
func _offers_hotspot(preview: Node) -> bool:
	for raw in preview.call("frame_sprites"):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty() or not bool(preview.call("_responds_to_mouse", sprite)):
			continue
		if _reachable_point(preview, sprite, int(sprite["channel"])) != null:
			return true
	return false


## Every global as a printable string. Compared by value, so a list that is
## rebuilt with the same contents does not read as movement — the question is
## whether the game's *state* moved, not whether an object was reallocated.
func _snapshot_globals(interp: Variant) -> Dictionary:
	var out: Dictionary = {}
	if interp == null:
		return out
	for key in (interp.globals as Dictionary).keys():
		out[str(key)] = str((interp.globals as Dictionary)[key]).substr(0, 120)
	return out


func _snapshot_fields(preview: Node) -> Dictionary:
	var out: Dictionary = {}
	var text: Variant = preview.get("_field_text")
	if typeof(text) != TYPE_DICTIONARY:
		return out
	for key in (text as Dictionary).keys():
		out[str(key)] = str((text as Dictionary)[key]).substr(0, 120)
	return out


func _report_diff(label: String, before: Dictionary, after: Dictionary) -> void:
	var lines: Array[String] = []
	for key in after.keys():
		if not before.has(key):
			lines.append("  + %s = %s" % [key, after[key]])
		elif str(before[key]) != str(after[key]):
			lines.append("  ~ %s : %s -> %s" % [key, before[key], after[key]])
	for key in before.keys():
		if not after.has(key):
			lines.append("  - %s (was %s)" % [key, before[key]])
	print("== %s changed (%d)" % [label, lines.size()])
	for line in lines:
		print(line)


## What the frame is, in one line, so the timeline collapses to the states the
## game actually visited rather than to one row per tick.
func _state_line(preview: Node, interp: Variant, watch: PackedStringArray) -> String:
	var frame := int(preview.call("current_frame"))
	var drawn := 0
	for raw in preview.call("frame_sprites"):
		if not (preview.call("_effective", raw) as Dictionary).is_empty():
			drawn += 1
	var out := "%s f%-5d %2d drawn  %s" % [
		str(preview.call("movie_name")), frame, drawn, _marker(preview, frame)]
	if interp != null:
		for name in watch:
			out += "  %s=%s" % [
				name, str((interp.globals as Dictionary).get(name, "<unset>")).substr(0, 40)]
	return out


## The marker the frame is inside, which is what a script names and what a
## reader can act on: no script says `go to frame 216`, they all say `go("game")`.
##
## Through `_labels.marker_at`, the engine's own answer, rather than by scanning
## a dictionary here. The first version of this function assumed `_labels` was a
## frame -> label Dictionary, which it is not — it is a `DirectorLabels` object —
## so `typeof(...) != TYPE_DICTIONARY` returned "" for every frame of every
## movie, the click budget was keyed by `("", channel)`, and the whole timeline
## printed with an empty marker column. Silent, and wrong in the direction that
## makes a tool agree with itself.
func _marker(preview: Node, _frame: int) -> String:
	var labels: Variant = preview.get("_labels")
	if labels == null or not (labels as Object).has_method("marker_at"):
		return ""
	return str(labels.call("marker_at", int(preview.get("_index"))))


## Which members each channel has ever held. A minigame that never swaps a member
## on any channel is not drawing anything the score did not already place, which
## is what "the platformer could not move" and "the game had no projectiles"
## both looked like from outside.
func _record_members(preview: Node, into: Dictionary) -> void:
	for raw in preview.call("frame_sprites"):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		var channel := int(sprite.get("channel", 0))
		# `cast_lib:cast_id`, which is what `channel.gd`'s `FIELDS` calls a
		# member — **not** `"member"`, which no sprite record carries. The first
		# version read `sprite["member"]`, got 0 for every sprite of every movie,
		# and printed "0 of 83 channel(s) ever swapped member" for a game that
		# had just made 150 `puppetSprite` calls. A tool whose failure mode is a
		# confident zero is the exact shape this repo's README warns about.
		var member := "%d:%d" % [
			int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0))]
		var seen: Array = into.get(channel, [])
		if not seen.has(member):
			seen.append(member)
			into[channel] = seen


## Press one hotspot this frame offers that has not been pressed under this
## marker yet, cycling so a game with forty dead buttons and one live one is
## still reached. Eligibility and the reachable point are the engine's own, the
## way `liveness_sweep._poke` does it: a sprite with a transparent middle answers
## nowhere near its centre.
## Returns whether anything was pressed, so the caller can tell "this frame has
## no buttons" from "this frame has buttons and one was used". That distinction
## is what `--poll-mouse` hangs off and is the difference between a minigame with
## no hotspots and a minigame whose hotspots do not work.
func _press_one(preview: Node) -> bool:
	var frame := int(preview.call("current_frame"))
	var marker := _marker(preview, frame)
	var offered: Array = []
	for raw in preview.call("frame_sprites"):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty() or not bool(preview.call("_responds_to_mouse", sprite)):
			continue
		var channel := int(sprite["channel"])
		var at: Variant = _reachable_point(preview, sprite, channel)
		if at == null:
			continue
		var key := "%s:%d" % [marker, channel]
		if not _pressed.has(key):
			_do_press(preview, at, key, channel, marker, frame)
			return true
		offered.append({"at": at, "key": key, "channel": channel})
	# Everything on offer here has been pressed once. Press again anyway — a
	# minigame's one button is meant to be pressed repeatedly, and refusing would
	# make this tool report "nothing left to click" at a slot machine's lever.
	#
	# **Least-pressed first, not first-listed.** The first version took the first
	# already-pressed sprite it saw, which on `SLOTMACH.dir` meant 13 of 20
	# presses went to the same channel 23 while the lever was never touched
	# again; a tool that spends its budget on one button cannot answer whether
	# any of the others work.
	if offered.is_empty():
		return false
	offered.sort_custom(func(a, b):
		return int(_pressed.get(a["key"], 0)) < int(_pressed.get(b["key"], 0)))
	var pick: Dictionary = offered[0]
	_do_press(preview, pick["at"], str(pick["key"]), int(pick["channel"]), marker, frame)
	return true


## Press and release the real mouse button, for a movie that reads `the
## mouseDown` from its own `exitFrame` instead of hanging a script on a sprite.
##
## Through `Input.parse_input_event` and not `route_press`, because those answer
## different questions: `route_press` delivers a *click* to whatever sprite is
## under the point, and `the mouseDown` is the live **button state**, which is
## what a polling handler samples. `tools/mouse_poll.gd` drives it the same way
## and its docstring carries the measurement that made this necessary.
##
## **Held across a score step, not for one process frame.** These movies run at 4
## to 8 fps, so two polls are 125-250 ms apart; a press released in the same
## process frame lands between two polls and is never sampled. `mouse_poll` is
## the harness for that and `docs/bugs-closed.md` carries the before/after --
## 2 of 8 clicks seen, then 8 of 8. Awaiting frames rather than sleeping, for
## AGENTS.md's reason: a synthetic loop advances no clock the movie can see.
func _poll_button(preview: Node) -> void:
	var at: Vector2 = Vector2(preview.call("stage_size")) * 0.5
	_button(true, at)
	for i in POLL_HOLD_FRAMES:
		await process_frame
	_button(false, at)
	_polls += 1


static func _button(pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _do_press(preview: Node, at: Variant, key: String, channel: int,
		marker: String, frame: int) -> void:
	_pressed[key] = int(_pressed.get(key, 0)) + 1
	preview.call("route_press", at)
	preview.call("route_release", at)
	_clicks.append("%s f%d ch%d at (%d,%d) x%d" % [
		marker, frame, channel, int((at as Vector2).x), int((at as Vector2).y),
		int(_pressed[key])])


static func _reachable_point(preview: Node, sprite: Dictionary, channel: int) -> Variant:
	var rect: Rect2 = preview.call("_sprite_rect", sprite)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return null
	for iy in 5:
		for ix in 9:
			var at := rect.position + Vector2(
				rect.size.x * (ix + 0.5) / 9.0, rect.size.y * (iy + 0.5) / 5.0)
			if int(preview.call("_channel_at", at)) == channel:
				return at
	return null


## The keys this *container* tests for, never a hand-written list. `key_sites.gd`
## reads them out of the container's own `CASt` records; the list that used to
## be hardcoded was swept out of Piposh 2 and called F10 free while Rating tests
## it at 48 sites.
##
## Returned as Godot keycodes, translated back through `DirectorKeys.MAC_CODES`
## — the engine's own table, inverted, rather than a second copy of it here. A
## Mac code with no Godot key is dropped rather than guessed: pressing the wrong
## key is worse than pressing none, because it produces a finding.
## The whole root is scanned, not only `movie`: a title's key handling lives as
## often in a shared cast as in the movie under test — Piposh 1 arms
## `the mouseDownScript` from `MASTER.CST`'s clock, and Piposh Dream's `throw`
## is a `keyDownScript` installed from one movie and pressed in another. Scoping
## the scan to the container printed an empty key list for six games running,
## which reads as "this title ignores the keyboard" and is never true.
func _key_codes(root_dir: String, _movie: String) -> Array[int]:
	var out: Array[int] = []
	var sites: Dictionary = KeySites.for_root(root_dir)
	var back: Dictionary = {}
	for godot_key in Keys.MAC_CODES.keys():
		back[int(Keys.MAC_CODES[godot_key])] = int(godot_key)
	for mac in (sites.get("codes", {}) as Dictionary).keys():
		var godot_key := int(back.get(int(mac), 0))
		if godot_key != 0 and not out.has(godot_key):
			out.append(godot_key)
	for character in (sites.get("chars", {}) as Dictionary).keys():
		var text := str(character)
		if text.length() != 1:
			continue
		var unicode := text.to_upper().unicode_at(0)
		if unicode >= 32 and not out.has(unicode):
			out.append(unicode)
	return out


## Presses go through `_dispatch_key`, the way `tools/key_chain.gd` drives them.
## `Input.parse_input_event` would instead press the *preview's* own F-key
## bindings — SKIP, pause, restart — as the probe went.
func _press_key(preview: Node, code: int) -> void:
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = code as Key
	if code >= 32 and code < 127:
		down.unicode = code
	preview.call("_dispatch_key", down)
	var up := InputEventKey.new()
	up.pressed = false
	up.keycode = down.keycode
	up.unicode = down.unicode
	preview.call("_dispatch_key_up", up)
	_keys_sent.append(OS.get_keycode_string(code as Key))


func _stopped(preview: Node) -> bool:
	var host = preview.get("_host")
	return host != null and bool(host.stopped)
