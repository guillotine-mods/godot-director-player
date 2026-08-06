extends SceneTree
## Is exactly one of each wandering character on screen?
##
## Six rooms place two film loops of the *same* character at two positions — an
## `a` and a `b` variant, named `arinlop1`/`brinlop1`, `apatlop1`/`bpatlop1`,
## `amoglop1`/`bmoglop1`, `atoflop1`/`btoflop1`. The original shows one of each
## pair and moves them as the player re-enters rooms: `peoplefunk` un-puppets
## channels 18-21 and calls `peoplecont(i)`, which advances `item i of inexits`
## 1..10 and shows 18/19 or 20/21 accordingly.
##
## The port drew all four, so every guest appeared twice (bugs.md 21). It also
## drove the conversations wrong: `BehaviorScript 290` and `291` branch on
## `if sprite(18).visible = 1` and `249` picks its channel numbers the same way,
## so with nothing hidden they take the wrong branch too.
##
## The invariant asserted here is the player-visible one — how many of the pair
## are drawn — not that `inexits` and a getter agree. `inexits` is checked
## separately and only as corroboration, because a port could in principle satisfy
## the counter and still draw both.
##
##   godot --headless --script tools/wandering_characters.gd

## `pairs` is [a-channel, b-channel]; exactly one side must be hidden.
const ROOMS := [
	{
		"movie": "DAY1", "label": "field", "slot": 1,
		"pairs": [[18, 21], [19, 20]],
		"note": "Rinati on 18/21, Pat on 19/20 — the reported room",
	},
	{
		"movie": "DAY1", "label": "edge1", "slot": 3,
		"pairs": [[18, 20]],
		"note": "Mogul; on day 3 the original hides both instead",
	},
	{
		"movie": "DAY1", "label": "veranda", "slot": 4,
		"pairs": [[18, 20]],
		"note": "Tofi",
	},
	{
		"movie": "DAY1", "label": "tennis", "slot": 2,
		"pairs": [[18, 20]],
		"note": "not in the report; peoplecont(2) covers it",
	},
]

var _completed: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


## Counted from its own last line. A GDScript runtime error aborts the handler and
## returns the type's zero value, so `failures += _check(...)` scores a dead check
## as a pass — `verify_film_loops.gd` once printed "all 3 ... draw the expected
## members" while every one had aborted.
func _complete(label: String, failed: int) -> int:
	_completed[label] = failed
	return failed


func _run() -> void:
	var failures := 0
	var labels: Array = []
	for room in ROOMS:
		var label := "%s @%s" % [room["movie"], room["label"]]
		labels.append(label)
		failures += _check(room, label)
	for label in labels:
		if not _completed.has(label):
			print("%-18s FAIL: the check did not complete (see the errors above)" % label)
			failures += 1

	print("")
	if failures == 0:
		print("every wandering character is on screen once")
	else:
		print("%d of %d rooms draw a character twice" % [failures, ROOMS.size()])
	quit(1 if failures > 0 else 0)


func _check(room: Dictionary, label: String) -> int:
	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK:
		print("%-18s FAIL: cannot boot" % label)
		return _complete(label, 1)
	# Retire only the two meetings that would otherwise carry the player straight
	# back out of a room under test: `@veranda` on day 1 routes to HATDAY1 and
	# `@field` to PATDAY1, both correct behaviour and neither what this measures.
	# Retiring *all* of them is wrong — day 1's seven are exactly the phase
	# transition's condition, so it fires and the next room resolves against
	# NIGHT1, which is what made `@field` report its guests unplaced.
	var state: Object = root.get_node("GameState")
	for name in ["hatday1", "patpip1"]:
		var at: int = Array(state.meetings).find(name)
		if at >= 0:
			state.meetings[at] = "done"
	if not runtime.goto_movie(room["movie"], null, {"label": room["label"]}):
		print("%-18s FAIL: cannot reach the room" % label)
		return _complete(label, 1)
	runtime.running = false
	# Park on the room's arrival frame rather than wherever the room loop left the
	# playhead. `@veranda` reported its guests "not placed" purely because the
	# playhead had moved off a frame that does carry channels 18 and 20.
	var go_frame: int = runtime.loader.lookup_label(str(room["label"]) + "go")
	if go_frame < 0:
		go_frame = runtime.loader.lookup_label(str(room["label"]))
	if go_frame < 0:
		print("%-18s FAIL: cannot resolve the room's frame" % label)
		return _complete(label, 1)
	runtime.frame_index = go_frame
	runtime.reconcile_channels(runtime.loader.get_frame(go_frame))

	var inexits: String = str(runtime.lingo.interpreter.globals.get("inexits", "<unset>"))
	var failed := 0
	var report: Array = []
	for pair_value in room["pairs"]:
		var pair: Array = pair_value
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		# A channel the score does not place at all is not "hidden", it is absent,
		# and counting it as hidden would let an empty room pass.
		var a_present: bool = not runtime.effective_sprite(a).is_empty()
		var b_present: bool = not runtime.effective_sprite(b).is_empty()
		if not (a_present and b_present):
			report.append("ch%d/%d not both placed" % [a, b])
			failed += 1
			continue
		var a_shown: bool = not runtime.is_channel_hidden(a)
		var b_shown: bool = not runtime.is_channel_hidden(b)
		if a_shown == b_shown:
			report.append("ch%d %s and ch%d %s" % [
				a, "shown" if a_shown else "hidden", b, "shown" if b_shown else "hidden",
			])
			failed += 1
		else:
			report.append("ch%d/%d ok (%d shown)" % [a, b, a if a_shown else b])

	print("%-18s %s  inexits=%-22s %s  %s" % [
		label, "ok  " if failed == 0 else "FAIL", inexits,
		", ".join(PackedStringArray(report)), str(room.get("note", "")),
	])
	return _complete(label, 1 if failed > 0 else 0)
