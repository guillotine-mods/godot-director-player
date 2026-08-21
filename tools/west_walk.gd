extends SceneTree
## A walker's position globals and the position its channel is drawn at stay
## equal across held arrow keys.
##
##   godot --headless --script tools/west_walk.gd -- --root piposh-dream
##
##   --presses N   arrow presses to make, cycling the four (default 8)
##   --hold N      process frames to hold each key down for (default 20)
##   --settle N    process frames after each release (default 10)
##
## Runs headless. Both readings are numbers, so nothing here paints.
##
## ## The pair
##
## `piposh-dream/WEST2.dir` keeps nine people. `ppl` holds their sprite channels,
## `hppl` and `vppl` their positions, and index 1 is the player. The init (`1:140`,
## f276) seeds all three and puts the player's channel exactly where the globals
## say:
##
##     hppl = [360, 1002, ...]   vppl = [240, 1002, ...]
##     set the locH of sprite getAt(ppl, 1) to getAt(hppl, 1)
##     set the locV of sprite getAt(ppl, 1) to getAt(vppl, 1)
##
## and the game loop (`1:152`, f277..f301) moves them with **two separate
## read-modify-writes of two separate stores**:
##
##     setAt(vppl, 1, getAt(vppl, 1) + ve)
##     setAt(hppl, 1, getAt(hppl, 1) + he)
##     set the locH of sprite getAt(ppl, 1) to the locH of sprite getAt(ppl, 1) + he
##     set the locV of sprite getAt(ppl, 1) to the locV of sprite getAt(ppl, 1) + ve
##
## Neither side is derived from the other. The globals live in the interpreter's
## own table; the channel side reads back whatever the override table hands it, so
## a release, a revert or a score write that reaches the puppeted channel makes
## the two disagree and they never recover. This is the generalised form of the
## reading pair that found `docs/bugs-closed.md` 120 -- there the state was a
## field and the second reading was sixteen members, here the state is two lists
## and the second reading is one channel's position.
##
## The minigame sweep of 2026-08-14 rated this game `YES (1-3)` and said what it
## could not see: "visual correctness, at all. Nothing measured here looks at
## colour, size or placement." A walker drawn somewhere other than where the game
## thinks it is passes every one of those four criteria.
##
## ## Three traps, all of them paid for
##
## **The key has to be held.** `westdown` sets `mnv[1]` and `1:152`'s `exitFrame`
## is what reads `the keyCode` and moves; `westup` sets `mnv[1]` back to 1. A
## press and release inside one process frame therefore never moves anybody. Each
## press here holds the key across score ticks, and the number of ticks it is held
## for is not asserted, because that is a race with the clock.
##
## **`ppl[1]` is re-read at every sample.** `strata()` runs on every `exitFrame`
## and swaps `ppl[1]` with another index to reorder the drawing, carrying the loc
## across with the channel. The pair survives that; a harness that cached channel
## 8 would not, and would red on the swap with a message about a position that
## never moved.
##
## **The constraint clamps one of the two axes, so only the other one is
## asserted.** The init sets `the constraint of sprite 8 to 21` *before* it writes
## the position, and §7.6 clamps a position write to the constraint channel's box
## while leaving the global alone. Measured: the box is
## `(-19, 265) 729x294`, `vppl[1]` is seeded at 240, and the channel is drawn at
## **265** -- the box's own top edge -- from the first frame onward. The vertical
## pair therefore differs by 25 for a reason that is the engine obeying the
## reference (`Channel::setPosition` clamps too), and it is *reported* here rather
## than asserted, because the only thing that could predict the 25 is the clamp
## itself: `Interaction.constrain` is the code that applied it, so comparing
## against it would be reading one value through two names -- the shape this whole
## harness exists to avoid.
##
## The horizontal pair has no such problem: `hppl[1]` walks 350..380 inside a box
## that runs from -19 to 710, so no write is clamped and the equality is a real
## equality. That the walk stayed inside the box is a **check** and not an
## assumption, so a run that wandered to the edge fails a case naming the clamp
## instead of looking like a drift.
##
## Only the horizontal keys are pressed, for a second reason as well:
## `westdown`'s up and down arrows carry the ladder branches, which re-point the
## constraint, move the walker by hand and `go(marker(0))` -- three things that
## are the game working correctly and none of them this pair's subject.
##
## ## What is not asserted, and why
##
## `1:140` branches on `soundBusy(4)` for `manleft`, the life count, so that is a
## race with the audio server and nothing here reads it. The waves spawn with
## `random(6)` into indices 2..9. The pair is index 1 only, and no line in the
## movie writes `hppl[1]` or `vppl[1]` outside the arrow arm.
##
## Title-agnostic driving, title-specific scenario.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")

const MOVIE := "WEST2.dir"

## The init, which seeds the three lists and puppets the channels, and the game
## loop, which moves them. Both frames come out of the score.
const INIT_SCRIPT := 140
const LOOP_SCRIPT := 152


func _init() -> void:
	var args := Args.parse()
	var hold := Args.number(args, "hold", 20)
	var settle := Args.number(args, "settle", 10)
	var h := Harness.new()

	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s" % paths.error)
		quit(1)
		return
	var frames := _frame_scripts(paths)
	var landing := int(frames.get(LOOP_SCRIPT, -1))
	var init_at := int(frames.get(INIT_SCRIPT, -1))
	if landing < 0 or init_at < 0:
		print("%s: frame script 1:%d at f%d, 1:%d at f%d -- nothing to drive"
			% [MOVIE, INIT_SCRIPT, init_at, LOOP_SCRIPT, landing])
		quit(1)
		return

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", MOVIE, null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("no score loaded")
		quit(1)
		return

	# Two frames short of the init, and left to walk in. Landing past `1:140`
	# leaves all three lists VOID and the channels unpuppeted, which is not a
	# weaker run but a different one.
	preview.set("_index", init_at - 2)
	var waited := 0
	while int(preview.call("current_frame")) < landing and waited < 4000:
		await process_frame
		waited += 1
	for i in settle:
		await process_frame

	var interp: Object = preview.get("_interpreter")
	var control := _sample(preview, interp)
	var rows: Array[String] = []
	var apart: Array[String] = []
	var outside: Array[String] = []
	rows.append("control    %s" % _row(control))
	_judge(control, apart, outside, "control")

	var wraps := 0
	var last := int(preview.call("current_frame"))
	var moved := 0
	var codes: Array[Key] = [KEY_RIGHT, KEY_RIGHT, KEY_LEFT, KEY_LEFT]
	var presses := Args.number(args, "presses", 8)
	for press in presses:
		var code: Key = codes[press % codes.size()]
		var before := _sample(preview, interp)
		var down := InputEventKey.new()
		down.keycode = code
		down.pressed = true
		preview.call("_dispatch_key", down)
		for i in hold:
			await process_frame
			var here := int(preview.call("current_frame"))
			if here < last:
				wraps += 1
			last = here
		var up := InputEventKey.new()
		up.keycode = code
		up.pressed = false
		preview.call("_dispatch_key_up", up)
		for i in settle:
			await process_frame
			var here2 := int(preview.call("current_frame"))
			if here2 < last:
				wraps += 1
			last = here2
		var after := _sample(preview, interp)
		if (after["said"] as Vector2) != (before["said"] as Vector2):
			moved += 1
		rows.append("press %d %-5s %s" % [
			press, "right" if code == KEY_RIGHT else "left", _row(after)])
		_judge(after, apart, outside, "press %d" % press)

	# The movie's own loop is twenty-six score frames long and jumps back from
	# `1:151` on the last of them, so the presses alone need not have crossed it.
	# Watched until it does, because a run that never wrapped says nothing about
	# anything that has to survive one -- which is the whole subject of 120.
	for i in Args.number(args, "wraps", 1500):
		await process_frame
		var at := int(preview.call("current_frame"))
		if at < last:
			wraps += 1
		last = at
		if wraps > 0:
			break
	for i in settle:
		await process_frame
	var wrapped := _sample(preview, interp)
	rows.append("wrapped    %s" % _row(wrapped))
	_judge(wrapped, apart, outside, "after the wrap")

	h.begin("a walker's position globals and its drawn position stay equal")
	h.check("the movie seeded a walker", int(control["channel"]) > 0
		and (control["said"] as Vector2) != Vector2.ZERO,
		"ch%d at %s" % [int(control["channel"]), str(control["said"])])
	h.check("the walker's channel is drawing something", int(control["member"]) > 0,
		"member %d" % int(control["member"]))
	# Without this the equality below is an equality between two numbers that
	# never changed, which is the vacuous pass `puzzle_board` guards with its own
	# move count -- and a held arrow that moves nobody is the exact symptom of the
	# driving trap this file's header records.
	h.check("held arrows moved the walker", moved > 0,
		"%d of %d press(es) moved it" % [moved, presses])
	h.check("the playhead ran its backward game loop", wraps > 0,
		"%d backward jump(s)" % wraps)
	# Before the equality, because a clamped write makes the two sides differ for
	# a reason that is the engine being right, and the equality below is only a
	# real equality on an axis nothing clamped.
	h.check("the walk stayed inside its constraint box horizontally",
		outside.is_empty(),
		"" if outside.is_empty() else "%d sample(s) at the edge" % outside.size())
	for line in outside.slice(0, 6):
		print("     %s" % line)
	h.check("the drawn position equalled the globals along the unclamped axis",
		apart.is_empty(),
		"" if apart.is_empty() else "%d of %d sample(s) disagree" % [
			apart.size(), rows.size()])
	for line in apart.slice(0, 8):
		print("     %s" % line)
	h.complete("a walker's position globals and its drawn position stay equal")

	print("")
	print(("landing    : f%d, the first frame of frame script 1:%d, walked in from "
		+ "f%d (1:%d) in %d frame(s)")
		% [landing, LOOP_SCRIPT, init_at - 2, INIT_SCRIPT, waited])
	print("constraint : %s" % str(control["box"]))
	print(("vertical   : globals %.0f, drawn %.0f -- reported, not asserted: the "
		+ "init sets the constraint before it writes the position, so §7.6 clamps "
		+ "locV to the box's top edge and leaves the global where it was")
		% [(control["said"] as Vector2).y, (control["drawn"] as Vector2).y])
	for line in rows:
		print("  %s" % line)
	quit(h.finish("a position global and the position drawn for it cannot drift"))


## Both readings at this instant, and the box a write is allowed to land in.
##
## `ppl[1]` is read here rather than once at the start, because `strata` moves the
## player between channels while carrying the loc with them.
func _sample(preview: Node, interp: Object) -> Dictionary:
	var globals: Dictionary = interp.get("globals")
	var channel := _at(globals.get("ppl"), 1)
	var said := Vector2(
		float(_at(globals.get("hppl"), 1)), float(_at(globals.get("vppl"), 1)))
	var drawn := Vector2(
		float(_num(preview.call("lingo_sprite_prop", channel, "loch"))),
		float(_num(preview.call("lingo_sprite_prop", channel, "locv"))))
	return {
		"channel": channel, "said": said, "drawn": drawn,
		"member": int(_drawn(preview).get(channel, -1)),
		"box": Interaction.constraint_box(preview, channel),
	}


## Two verdicts per sample, kept apart so a clamp cannot be reported as a drift.
##
## Both are about the horizontal axis only. The vertical one is clamped by the
## movie's own constraint from the first frame -- see the header -- and no
## assertion here can tell a correctly clamped write from a lost override, because
## the only thing that predicts the clamped value is the clamp.
func _judge(sample: Dictionary, apart: Array[String], outside: Array[String],
		tag: String) -> void:
	var said: Vector2 = sample["said"]
	var drawn: Vector2 = sample["drawn"]
	var box: Rect2 = sample["box"]
	if box != Rect2() and (said.x < box.position.x or said.x > box.end.x):
		outside.append(("%s: the globals say locH %.0f, which is outside %.0f..%.0f "
			+ "-- §7.6 clamps the write and leaves the global alone, so the two "
			+ "must differ here")
			% [tag, said.x, box.position.x, box.end.x])
	if not is_equal_approx(said.x, drawn.x):
		apart.append("%s: ch%d is drawn at locH %.0f, the globals say %.0f" % [
			tag, int(sample["channel"]), drawn.x, said.x])


func _row(sample: Dictionary) -> String:
	return "ch%2d  globals (%4.0f,%4.0f)  drawn (%4.0f,%4.0f)  member %3d" % [
		int(sample["channel"]),
		(sample["said"] as Vector2).x, (sample["said"] as Vector2).y,
		(sample["drawn"] as Vector2).x, (sample["drawn"] as Vector2).y,
		int(sample["member"])]


## One-based `getAt`, answering 0 for a list a handler has not built yet.
func _at(value: Variant, index: int) -> int:
	if value is Array and (value as Array).size() >= index:
		return _num((value as Array)[index - 1])
	return 0


## A Lingo global no handler has assigned yet is VOID, which arrives as null, and
## `int(null)` is an aborted handler rather than a conversion.
func _num(value: Variant) -> int:
	return 0 if value == null else int(value)


func _drawn(preview: Node) -> Dictionary:
	var out: Dictionary = {}
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		var live: Dictionary = preview.call("_effective", sprite)
		if live.is_empty():
			continue
		out[int(sprite["channel"])] = int(live.get("cast_id", sprite.get("cast_id", 0)))
	return out


## The first frame each frame script covers, read from the score rather than
## written down: the init and the loop are twenty-six frames apart here and the
## run has to pass through both.
func _frame_scripts(paths) -> Dictionary:
	var out: Dictionary = {}
	var path: String = paths.resolve(MOVIE)
	if path == "":
		return out
	var file := ContainerFile.new()
	if not file.open(path):
		return out
	var ids: Array = file.ids_of("VWSC")
	if ids.is_empty():
		file.close()
		return out
	var score = Score.new()
	if not score.parse(file.read_chunk(ids[0])):
		file.close()
		return out
	for interval in score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		var member := int(interval["script_member"])
		var start := int(interval["start"])
		if not out.has(member) or start < int(out[member]):
			out[member] = start
	file.close()
	return out
