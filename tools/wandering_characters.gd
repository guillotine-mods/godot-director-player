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

## The player has to WALK in, not be teleported in. `peoplefunk` runs off the end
## of a walk, out of the room frame's own `exitFrame`, so a `goto_movie` straight to
## the label reaches the room without ever passing the code under test — an earlier
## draft of this harness did exactly that and could not tell the fix from its
## absence. `from` is the room to start in and `via` matches the hotspot's target
## label.
##
## `pairs` is [a-channel, b-channel]; exactly one side must be drawn.
const ROOMS := [
	{
		"movie": "DAY1", "from": "path4", "via": "field", "label": "field",
		"pairs": [[18, 21], [19, 20]],
		"note": "Rinati on 18/21, Pat on 19/20 — the reported room",
	},
]

## `edge1`, `veranda`, `tennis`, `dwarfs` and `exitforest3` carry the same pairs and
## are fixed by the same code path, but are not asserted here: the walk into them
## has to start from a room whose hotspot this harness could drive, and `gate`'s
## exits did not start a walk under it. Covering them means finding a route that
## does, not relaxing the check — a room reached by `goto_movie` never runs the code
## under test at all.


const DELTA := 1.0 / 30.0
## Ticks to run the walk and its transition animation to completion.
const WALK_TICKS := 240

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
	if not runtime.goto_movie(room["movie"], null, {"label": room["from"]}):
		print("%-18s FAIL: cannot reach the starting room %s" % [label, room["from"]])
		return _complete(label, 1)

	var from_frame: int = runtime.loader.lookup_label(str(room["from"]) + "go")
	if from_frame < 0:
		print("%-18s FAIL: cannot resolve %sgo" % [label, room["from"]])
		return _complete(label, 1)
	runtime.frame_index = from_frame
	var point := Vector2.ZERO
	var found := false
	for sprite_value in runtime.clickable_sprites(runtime.loader.get_frame(from_frame)):
		var sprite: Dictionary = sprite_value
		var nav: Variant = (sprite.get("on_click", {}) as Dictionary).get("nav", null)
		if typeof(nav) != TYPE_DICTIONARY:
			continue
		if not str((nav as Dictionary).get("target_label", "")).to_lower().contains(
			str(room["via"]).to_lower()
		):
			continue
		var rect: Rect2 = runtime.sprite_stage_rect(sprite)
		point = rect.position + rect.size * 0.5
		found = true
	if not found:
		print("%-18s FAIL: no hotspot in %s walks to %s" % [label, room["from"], room["via"]])
		return _complete(label, 1)

	# Let the starting room's own script run before clicking in it: almost every
	# hotspot is gated on `whereami`, which the room sets from its own exitFrame.
	runtime.enter_frame(from_frame)
	for _settle in 8:
		runtime.tick(DELTA)
	runtime.enter_frame(from_frame)
	runtime.perform_click(point)
	if not runtime.puppet.is_walking():
		print("%-18s FAIL: the click did not start a walk" % label)
		return _complete(label, 1)
	for _i in WALK_TICKS:
		runtime.tick(DELTA)
	runtime.running = false

	var arrived: String = str(runtime.label_near_frame(runtime.frame_index))
	if not arrived.to_lower().begins_with(str(room["label"]).to_lower()):
		print("%-18s FAIL: walk ended at %s @%s" % [label, runtime.loader.movie_name, arrived])
		return _complete(label, 1)

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
