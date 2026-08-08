extends SceneTree
## Piposh 1's cannon round, played: does a shell that lands on a ship sink it?
##
##   godot --headless --script tools/cannon_hit.gd -- --root piposh
##
## The corpus witness for `tools/sprite_collision.gd`. That harness asserts the
## engine rule -- `intersects` and `within` measure a sprite a script has hidden,
## the mouse does not -- against whichever game is configured. This one plays the
## single place in any of the six titles where the whole chain hangs off one
## keypress: `the keyDownScript` -> `movecannon` -> a puppet write onto a hidden
## 1x1 probe -> `within` -> `allships`. The rule can be green with any other link
## in that chain broken, and the reported symptom was the chain, not the rule.
##
## Its own tool rather than a flag on the other, so that `bash gate.sh cannon_hit`
## reaches it. An entry sharing a name with another is one the gate's matcher
## resolves to whichever comes first, which is the trap `gate.sh` documents
## against: a harness silently losing its subject reports PASS for a reason that
## is not in the harness.

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
	quit(await _cannon(preview, h, args))


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
