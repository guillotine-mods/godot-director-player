extends SceneTree
## `sprite A intersects B` and `sprite A within B`: what rect they measure, and
## whether a hidden sprite still has one.
##
##   godot --headless --script tools/sprite_collision.gd
##   godot --headless --script tools/sprite_collision.gd -- --root piposh --movie PIPDATA/CANON.dir
##
## **Director's two rect questions are not the same question, and the difference
## is visibility.** `channel.cpp:isMouseIn` opens with `if (!_visible) return
## kCollisionNo` — the mouse cannot reach a sprite nobody can see. `c_within` and
## `c_intersects` (`lingo/lingo-code.cpp`) go straight to `getBbox()`, and
## `_visible` appears at exactly one site in the whole of `channel.cpp`, which is
## that one. So the collision operators measure a hidden sprite exactly as they
## measure a visible one.
##
## That is not a curiosity. It is the idiom: a script parks a 1x1 invisible
## member where it wants to ask a question and asks it. Piposh 1's cannon game is
## the corpus's clearest instance — `CANON.dir` member 496, `on movecannon`,
## puppets channel 48 (the member `dot`, 1x1, `set the visible of sprite 48 to 0`
## in the frame's own `enterFrame`) to where the shell would land and then runs
##
##   repeat with i = 17 to 22
##     if sprite 48 within i then ...
##
## over the six shape sprites that fence the ships. Measuring the probe as empty
## because it is invisible answers "no" to every shot in the game, and what the
## player sees is a shell landing on a ship that does not sink.
##
## Both halves are asserted here, because a port that fixes the first by deleting
## the visibility rule outright breaks the second and no other harness would say
## so: a hidden sprite must keep its rect for the operators **and** stay out of
## reach of the mouse.
##
## Title-agnostic by default. With no arguments it boots whatever
## `director_game.cfg` names and picks its own subject — the busiest frame, and a
## sprite on it big enough to enclose a point — so the rule is checked against
## whichever game is configured rather than against the one it was found in.
##
## `--cannon` adds the corpus witness, and it is opt-in because it names one
## game's channels. It plays Piposh 1's cannon round for real — arms it, walks
## the barrel, raises the angle, fires — and asserts a ship takes the hit. That
## is the only case here that crosses the whole chain, `the keyDownScript` ->
## `movecannon` -> the puppet write -> `within` -> `allships`, and the rule above
## can be green with any link in it broken.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## `movecannon`'s own keys, as Mac key codes: left, right, down, space.
const CANNON_KEYS := {"left": 123, "right": 124, "down": 125, "fire": 49}
## The channels that round uses: the shell probe, the fences the ships sit
## behind, and the barrel the shell leaves from.
const CANNON_SHELL := 48
const CANNON_FENCES := [17, 18, 19, 20, 21, 22]
const CANNON_BARREL := 45


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	if Args.flag(args, "cannon"):
		quit(await _cannon(preview, h, args))
		return

	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		for i in 12:
			await process_frame

	var label := Args.text(args, "label", "")
	if label != "":
		preview.call("lingo_go_label", label)
		for i in 12:
			await process_frame
	preview.set("_paused", true)

	var subject: int = await _subject(preview)
	if subject <= 0:
		print("no frame in %s carries a sprite with a rect to measure" % str(
			preview.call("movie_name")))
		quit(1)
		return

	var name := "%s frame %d channel %d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame")), subject]
	print("")
	print("subject: %s" % name)
	print("")

	h.begin(name)

	var visible_rect: Rect2 = preview.call("lingo_sprite_rect", subject)
	h.check("the sprite has a rect while it is visible", visible_rect.size != Vector2.ZERO,
		str(visible_rect))

	# The mouse and the operators part company here, and only here.
	var reachable := bool(preview.call("lingo_rollover", subject)) or _hit(preview, subject)
	preview.call("lingo_set_sprite_prop", subject, "visible", 0)
	await process_frame

	var hidden_rect: Rect2 = preview.call("lingo_sprite_rect", subject)
	h.check("a hidden sprite keeps the rect the operators measure",
		hidden_rect == visible_rect,
		"visible %s, hidden %s" % [str(visible_rect), str(hidden_rect)])

	h.check("a hidden sprite is out of the mouse's reach", not _hit(preview, subject))

	# The operator itself, through the host arm the interpreter routes to, so
	# what is asserted is the answer a script gets rather than a rect this
	# harness compared for it. A rect is always within itself.
	var host = preview.get("_host")
	h.check("`sprite N within N` answers true while N is hidden",
		int(host.call("call_builtin", "within", [subject, subject])) == 1)
	h.check("`sprite N intersects N` answers true while N is hidden",
		int(host.call("call_builtin", "intersects", [subject, subject])) == 1)

	preview.call("lingo_set_sprite_prop", subject, "visible", 1)
	await process_frame
	h.check("un-hiding restores the sprite to the mouse",
		_hit(preview, subject) == reachable,
		"was %s before the hide" % ("reachable" if reachable else "unreachable"))

	h.complete(name)
	quit(h.finish("the collision operators measure a hidden sprite; the mouse does not"))


## The corpus witness: Piposh 1's cannon round, played.
##
## `CANON.dir` member 496 is `on movecannon`, installed as `the keyDownScript` by
## the round's own `enterFrame`. It walks the barrel 15px a press, adds 3 to the
## field `zavit` per down press, and on the space bar drops the shell at
## `316 - zavit * 3` under the barrel and asks `sprite 48 within i` over the six
## fences. Channel 48's member is `dot`, 1x1, and the same `enterFrame` hides it.
##
## Aimed from the rects it reads rather than from constants, because the round
## deals the ships at random (`set x to random(5)` picks one of five layouts) and
## a hardcoded aim would hit in some runs and miss in others -- which is the worst
## possible failure mode for a regression test, and indistinguishable from the
## bug it guards.
func _cannon(preview: Node, h: Harness, args: Dictionary) -> int:
	var movie := Args.text(args, "movie", "PIPDATA/CANON.dir")
	preview.call("lingo_go_movie", movie, null)
	for i in 12:
		await process_frame
	preview.call("lingo_go_label", Args.text(args, "label", "game1"))

	var interp = preview.get("_interpreter")
	# Waited on rather than counted in ticks. `enterFrame` is what arms the round,
	# and a fixed tick count raced it: the same probe read the globals unset on one
	# run and armed on the next.
	for i in 600:
		if _global(interp, "shotready") == "ready":
			break
		await process_frame

	var name := "%s: a shell that lands on a ship sinks it" % str(preview.call("movie_name"))
	h.begin(name)
	print("")

	if not h.check("the round arms itself", _global(interp, "shotready") == "ready",
		"shotready is %s" % _global(interp, "shotready")):
		h.complete(name)
		return h.finish("the cannon round never started")

	# The widest fence, so the aim has the most room to be right in.
	var target := Rect2()
	var target_channel := 0
	for ch in CANNON_FENCES:
		var r: Rect2 = preview.call("lingo_sprite_rect", ch)
		if r.get_area() > target.get_area():
			target = r
			target_channel = ch
	h.check("the ships are fenced by sprites with rects", target_channel > 0, str(target))

	var aim := target.get_center()
	var steps := int(round((_barrel(preview) - aim.x) / 15.0))
	for i in absi(steps):
		_press(preview, CANNON_KEYS["left"] if steps > 0 else CANNON_KEYS["right"])
	# Three per press, and `316 - zavit * 3` per unit, so nine pixels a press.
	for i in int(round((316.0 - aim.y) / 9.0)):
		_press(preview, CANNON_KEYS["down"])

	var before := _global(interp, "allships")
	_press(preview, CANNON_KEYS["fire"])
	var shell: Rect2 = preview.call("lingo_sprite_rect", CANNON_SHELL)

	print("  fence     : channel %d %s" % [target_channel, str(target)])
	print("  shell     : %s" % str(shell))
	print("  allships  : %s -> %s" % [before, _global(interp, "allships")])
	print("")

	h.check("the hidden shell has a rect at all", shell.size != Vector2.ZERO,
		"channel %d %s" % [CANNON_SHELL, str(shell)])
	h.check("the shell landed inside the fence it was aimed at",
		shell.size != Vector2.ZERO and target.encloses(shell),
		"channel %d %s" % [target_channel, str(target)])
	h.check("the ship the shell landed on took it",
		_global(interp, "allships") != before, _global(interp, "allships"))
	h.complete(name)
	return h.finish("a shell that lands on a ship sinks it")


## The barrel's `locH`, recovered from its rect: `_stage_rect` places a sprite at
## `loc - reg`, and what is to hand here is the rect.
func _barrel(preview: Node) -> int:
	return int((preview.call("lingo_sprite_rect", CANNON_BARREL) as Rect2).get_center().x)


## One key, through `the keyDownScript`'s own handler. Not through `_input`:
## headless Godot has no keyboard focus, and `tools/key_chain.gd` is the harness
## that owns the wiring question.
func _press(preview: Node, mac_code: int) -> void:
	preview.get("_host").set("key_code", mac_code)
	preview.get("_interpreter").call("call_handler", "movecannon", [])


func _global(interp, name: String) -> String:
	return str((interp.get("globals") as Dictionary).get(name, ""))


## Whether the hit test places this channel under the centre of its own rect.
## Asked through the same path a click takes, not through a rect comparison.
func _hit(preview: Node, channel: int) -> bool:
	var rect: Rect2 = preview.call("lingo_sprite_rect", channel)
	if rect.size == Vector2.ZERO:
		# A hidden sprite has no rect to aim at from here, so aim at the one it
		# had. The caller holds it; recovering it is the score's business.
		for sprite in _frame_sprites(preview):
			if int(sprite["channel"]) == channel:
				rect = preview.call("_stage_rect", sprite)
				break
	if rect.size == Vector2.ZERO:
		return false
	return int(preview.call("_channel_at", rect.get_center())) == channel


## The busiest frame's topmost sprite whose rect is big enough to be aimed at.
## Walks the score rather than trusting the frame the movie happened to stop on:
## a boot movie can settle on a frame carrying nothing measurable.
func _subject(preview: Node) -> int:
	var score = preview.get("_score")
	if score == null:
		return 0
	var best_frame := 0
	var best_count := 0
	for index in range(1, int(score.get("frame_count")) + 1):
		var count: int = (score.call("frame", index).get("sprites", []) as Array).size()
		if count > best_count:
			best_count = count
			best_frame = index
	if best_frame == 0:
		return 0
	preview.set("_index", best_frame)
	await process_frame
	var chosen := 0
	for sprite in _frame_sprites(preview):
		var rect: Rect2 = preview.call("_stage_rect", sprite)
		if rect.size.x >= 4.0 and rect.size.y >= 4.0:
			chosen = int(sprite["channel"])
	return chosen


func _frame_sprites(preview: Node) -> Array:
	var score = preview.get("_score")
	if score == null:
		return []
	return score.call("frame", int(preview.call("current_frame"))).get("sprites", [])
