extends SceneTree
## `bugs.md` 45: after a hit, does the submarine's `locV` walk off the top of the
## stage, and is the walk the movie's own arithmetic or the port's?
##
##   godot --headless --path . --audio-driver Dummy --script tools/cannon_sub_drift.gd -- \
##       --root piposh --label game6 --ticks 60
##
##   --movie C     container (default `PIPDATA/CANON.dir`)
##   --label L     the round to stand in (default `game6`)
##   --channel N   the submarine channel to watch (default 12)
##   --ticks N     score ticks to watch after the shot (default 60)
##   --shots N     how many times to fire (default 1)
##   --verbose     print the counter and the rect every tick
##
## ## What the entry needs and what this measures
##
## The entry's open half is stated as mechanical: *"the probe watched 40 ticks and
## the counter needs ~20 `exitFrame`s to reach 1. Extend the tick budget and print
## `the locV of sprite 12` each frame across the whole countdown."* That is this
## tool, and it is a separate one from `tools/cannon_hit.gd` because that harness
## asserts a different thing -- that a shell which lands on a ship registers -- and
## drives `movecannon` by name, which is round 1's handler and not this round's.
## Here the handler comes from `the keyDownScript` the round installed, so the tool
## does not need to know which round it is standing in.
##
## **The verdict this feeds is not "did it move".** `allshipscounter` is doing
## double duty in the movie's *own* script -- a dive timer written 14 and a hit
## timer written 20, both counted down by the same line -- so a port that
## reproduces the drift is a *faithful* port and the entry closes as not ours. So
## this prints the counter beside the position on every tick: what decides the
## verdict is whether the countdown that ends in a `-122` was ever preceded by the
## `+122` its own dive branch writes, and that is visible as the position before
## the countdown started.
##
## Title-agnostic in its mechanism -- it names no handler, no global and no
## member. The two round-specific things it does take are the label and the
## channel, on the command line, because a tool that has to be pointed at a round
## is not the same as an engine that knows about one.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## `movecannon*`'s own keys, as Mac key codes.
const KEY_LEFT := 123
const KEY_RIGHT := 124
const KEY_DOWN := 125
const KEY_FIRE := 49
## The fences the round tests `within` against, and the barrel the shell leaves.
const FENCES := [17, 18, 19, 20, 21, 22]
const BARREL := 45


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	preview.call("lingo_go_movie", Args.text(args, "movie", "PIPDATA/CANON.dir"), null)
	for i in 12:
		await process_frame
	preview.call("lingo_go_label", Args.text(args, "label", "game6"))
	var interp = preview.get("_interpreter")
	for i in 600:
		if _global(interp, "shotready") == "ready":
			break
		await process_frame

	var case := "%s: what a hit does to the submarine's position over the whole countdown" % \
		str(preview.call("movie_name"))
	h.begin(case)
	if not h.check("the round arms itself", _global(interp, "shotready") == "ready",
			"shotready is %s" % _global(interp, "shotready")):
		h.complete(case)
		quit(h.finish("the cannon round never started"))
		return

	var channel := Args.number(args, "channel", 12)
	var handler := Args.text(args, "handler", "")
	if handler == "":
		handler = _key_down_script(preview, interp)
	h.check("the round installed a keyDownScript to drive", handler != "", handler)

	print("")
	print("  keyDownScript : %s" % handler)
	print("  allships      : %s" % _global(interp, "allships"))
	print("  counter       : %s" % _global(interp, "allshipscounter"))
	var before := _top(preview, channel)
	print("  ch%-2d locV/top : %d / %d" % [channel, _locv(preview, channel), before])
	print("")

	# Sweep the barrel across the fences rather than aiming once. The round deals
	# its ships at random and the shell is a 1x1 probe tested with `within`, so a
	# single computed aim hits on some deals and not on others -- which is the
	# worst failure mode available here, because a miss and a fixed engine look
	# identical in the output. Every press is still the movie's own key path.
	var armed_from := _global(interp, "allshipscounter")
	var before_ships := _global(interp, "allships")
	var target_channel := 0
	var target := Rect2()
	var fired := 0
	for ch in FENCES:
		var r: Rect2 = preview.call("lingo_sprite_rect", ch)
		if r.get_area() <= 0.0:
			continue
		# `hitwhere` is `316 - zavit * 3` and `zavit` only ever rises, so the
		# elevation is swept once, downward, across the whole fence stack.
		var elevation := int(round((316.0 - r.get_center().y) / 9.0))
		for i in maxi(0, elevation - _elevation(preview)):
			_press(preview, interp, handler, KEY_DOWN)
		for x in range(int(r.position.x) + 8, int(r.end.x), 15):
			var steps := int(round((_barrel(preview) - float(x)) / 15.0))
			for i in absi(steps):
				_press(preview, interp, handler, KEY_LEFT if steps > 0 else KEY_RIGHT)
			_press(preview, interp, handler, KEY_FIRE)
			fired += 1
			if _global(interp, "allships") != before_ships:
				target_channel = ch
				target = r
				break
		if target_channel != 0:
			break
	var after_shot := _top(preview, channel)
	print("  fired %d shell(s); the one that landed was at fence channel %d %s" % [
		fired, target_channel, str(target)])
	print("  allships      : %s -> %s" % [before_ships, _global(interp, "allships")])
	print("  counter       : %s -> %s" % [armed_from, _global(interp, "allshipscounter")])
	print("  ch%-2d top      : %d -> %d   (a dive would have moved it +122 here)" % [
		channel, before, after_shot])
	print("")
	h.check("a shell landed on a ship, so a counter is armed by a hit",
		_global(interp, "allships") != before_ships,
		"allships %s after %d shell(s)" % [_global(interp, "allships"), fired])

	# The whole countdown, off real awaited frames. A synthetic tick loop would
	# advance the runtime clock and not the audio server's, and this round polls
	# `soundBusy` (AGENTS.md).
	var ticks := Args.number(args, "ticks", 60)
	# All three of the round's submarines, not only the one the entry names: the
	# same `exitFrame` walks `repeat with i = 10 to 12` and the two small ones
	# move by 164 where the large one moves by 122, so watching one channel
	# cannot tell "this sub did not move" from "the loop did not run".
	var watched: Array[int] = [channel - 2, channel - 1, channel]
	var lowest: Dictionary = {}
	var last: Dictionary = {}
	var last_v: Dictionary = {}
	for ch in watched:
		lowest[ch] = _top(preview, ch)
		last[ch] = _top(preview, ch)
		last_v[ch] = _locv(preview, ch)
	var moves: Array[String] = []
	var verbose := Args.flag(args, "verbose")
	for t in ticks:
		await process_frame
		for ch in watched:
			var now := _top(preview, ch)
			var now_v := _locv(preview, ch)
			lowest[ch] = mini(int(lowest[ch]), now)
			if now != int(last[ch]) or now_v != int(last_v[ch]):
				moves.append("tick %-3d ch%-2d locV %d -> %d (%+d), top %d -> %d, counter %s" % [
					t, ch, int(last_v[ch]), now_v, now_v - int(last_v[ch]),
					int(last[ch]), now, _global(interp, "allshipscounter")])
				last[ch] = now
				last_v[ch] = now_v
		if verbose:
			print("  tick %-3d counter %-14s allships %-24s tops %s" % [
				t, _global(interp, "allshipscounter"), _global(interp, "allships"),
				str(last)])

	print("  every move of channels %s across %d tick(s):" % [str(watched), ticks])
	if moves.is_empty():
		print("      none")
	for line in moves:
		print("      %s" % line)
	print("")
	print("  counter at the end : %s" % _global(interp, "allshipscounter"))
	print("  allships at the end: %s" % _global(interp, "allships"))
	for ch in watched:
		print("  ch%-2d top: ended %d, lowest %d" % [ch, int(last[ch]), int(lowest[ch])])

	h.check("the countdown ran to its end inside the tick budget",
		_counter_reached_zero(_global(interp, "allshipscounter")),
		"counter %s after %d tick(s)" % [_global(interp, "allshipscounter"), ticks])
	# The entry's symptom, stated as the invariant a player would notice: a
	# submarine that is still on the stage. A negative top is off the top edge.
	var worst := 1 << 30
	var worst_channel := 0
	for ch in watched:
		if int(lowest[ch]) < worst:
			worst = int(lowest[ch])
			worst_channel = ch
	h.check("every submarine is still inside the stage after the countdown",
		worst >= 0, "lowest top %d on channel %d, ch%d started at %d" % [
			worst, worst_channel, channel, before])
	h.complete(case)
	quit(h.finish("what a hit does to a submarine's position"))


## The handler the round installed, so the tool does not name it. Read off the
## host's own property first and the interpreter's globals second, because
## `the keyDownScript` is a movie property and different movies set it from
## different places.
func _key_down_script(preview: Node, interp) -> String:
	var host = preview.get("_host")
	if host != null:
		var value = host.get("key_down_script")
		if value != null and str(value) != "":
			return str(value)
		# The bare-identifier form is kept on the compiled record beside the
		# source string (`preview_lingo_host.gd:key_down_compiled`), and a save
		# reload rebuilds the compiled half. Read both rather than assume which
		# one this movie's assignment produced.
		var compiled = host.get("key_down_compiled")
		if compiled is Dictionary and str((compiled as Dictionary).get("name", "")) != "":
			return str((compiled as Dictionary)["name"])
	return str((interp.get("globals") as Dictionary).get("keydownscript", ""))


func _press(preview: Node, interp, handler: String, mac_code: int) -> void:
	preview.get("_host").set("key_code", mac_code)
	interp.call("call_handler", handler, [])


## The sprite's top edge in stage pixels. `locV` itself is the registration
## point, and `lingo_sprite_rect` is the placement that a person sees; for a
## sprite whose registration is its top-left the two are the same number, and for
## one whose registration is centred the rect is the honest one to clip against.
func _top(preview: Node, channel: int) -> int:
	return int((preview.call("lingo_sprite_rect", channel) as Rect2).position.y)


## `the locV of sprite N` as the movie's own script reads and writes it, which is
## the number the arithmetic in question is done on. Printed beside `_top`
## because they answer different questions -- "did the script's value move" and
## "did the picture move" -- and a report that conflated them could not say
## which half of a disagreement was broken.
func _locv(preview: Node, channel: int) -> int:
	var value = preview.call("lingo_sprite_prop", channel, "locv")
	return int(value) if value != null else 0


## The elevation the round keeps in its own field, in the units the down key
## moves it by. Read rather than counted, so a sweep that hits the handler's own
## `< 87` ceiling does not go on pressing a key that no longer does anything.
func _elevation(preview: Node) -> int:
	return int(str(preview.call("lingo_field", "zavit", "")).strip_edges()) / 3


func _barrel(preview: Node) -> int:
	return int((preview.call("lingo_sprite_rect", BARREL) as Rect2).get_center().x)


func _counter_reached_zero(counter: String) -> bool:
	for item in counter.split(",", false):
		if int(str(item).strip_edges()) > 1:
			return false
	return true


func _global(interp, name: String) -> String:
	return str((interp.get("globals") as Dictionary).get(name, ""))
