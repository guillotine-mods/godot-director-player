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
## What it does **not** cover is the chain a script actually runs through these
## operators. `tools/cannon_hit.gd` is that witness: it plays Piposh 1's cannon
## round and asserts a ship takes the hit. The rule here can be green with any
## other link in that chain broken.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

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
	var name := "%s frame %d channel %d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame")), subject]
	print("")
	print("subject: %s" % name)
	print("")

	h.begin(name)
	# The two possible ways to have no subject are different findings and were one
	# message: a root whose boot movie this config does not name loads nothing at
	# all, and reads identically to a movie whose frames carry nothing clickable.
	var loaded: bool = preview.get("_score") != null
	if not h.check("a sprite the mouse can reach", subject > 0,
			"channel %d" % subject if subject > 0
			else ("no movie loaded -- does %s name a boot movie this root has?"
				% Args.text(args, "root", "the config"))
			if not loaded
			else "no frame of %s carries one" % str(preview.call("movie_name"))):
		h.complete(name)
		quit(h.finish("no subject: the two halves below cannot be told apart"))
		return

	var visible_rect: Rect2 = preview.call("lingo_sprite_rect", subject)
	h.check("the sprite has a rect while it is visible", visible_rect.size != Vector2.ZERO,
		str(visible_rect))

	# **Asserted, not recorded.** This was `var reachable := ...` and the two
	# mouse checks below then compared against whatever it happened to be -- so on
	# a subject the mouse could never reach they read `false == false` and passed
	# over a deleted visibility rule. `_subject` now insists on an eligible sprite
	# and this insists it is reachable where it is aimed at, because a harness
	# that only ever confirms its own starting value is the failure it exists to
	# catch (`aiff_check.gd`, `text_and_shapes.gd`, both of them twice).
	h.check("the mouse reaches the sprite before it is hidden", _hit(preview, subject))

	# The mouse and the operators part company here, and only here.
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
	h.check("un-hiding restores the sprite to the mouse", _hit(preview, subject))

	h.complete(name)
	quit(h.finish("the collision operators measure a hidden sprite; the mouse does not"))


## Whether the hit test places this channel under the centre of its own rect.
## Asked through the same path a click takes, not through a rect comparison.
func _hit(preview: Node, channel: int) -> bool:
	var rect: Rect2 = preview.call("lingo_sprite_rect", channel)
	if rect.size == Vector2.ZERO:
		# Only an *absent* channel reaches here now: a hidden sprite keeps its
		# rect, which is the rule this file asserts. Kept so that the aim survives
		# a channel the score has emptied, rather than reading as no hit.
		for sprite in _frame_sprites(preview):
			if int(sprite["channel"]) == channel:
				rect = preview.call("_stage_rect", sprite)
				break
	if rect.size == Vector2.ZERO:
		return false
	return int(preview.call("_channel_at", rect.get_center())) == channel


## The busiest frame's topmost sprite the mouse can actually reach.
##
## Walks the score rather than trusting the frame the movie happened to stop on:
## a boot movie can settle on a frame carrying nothing measurable.
##
## **Eligibility is the load-bearing half of that sentence.** "Topmost with a
## rect" is not enough and picked exactly the wrong sprite: on piposh2 it chose
## channel 21 of `strtgame.dir` frame 122, the 640x485 backdrop that
## `interaction.gd`'s own header names as carrying no behaviour, no member script
## and no moveable bit -- so `_channel_at` can never answer it, and the two mouse
## checks compared "unreachable" against "unreachable" and passed on a port with
## the visibility rule torn out. Returns 0 when the frame has nothing eligible,
## which the caller reports as a failure rather than skipping.
func _subject(preview: Node) -> int:
	var score = preview.get("_score")
	if score == null:
		return 0
	# Busiest first, but *not* busiest only: the frame with the most sprites is
	# not the frame with a clickable one, and on all three roots it turned out to
	# carry none at all. Every frame that has sprites is a candidate, tried in
	# descending order so the first hit is usually the first frame tried.
	var order: Array[Vector2i] = []
	for index in range(1, int(score.get("frame_count")) + 1):
		var count: int = (score.call("frame", index).get("sprites", []) as Array).size()
		if count > 0:
			order.append(Vector2i(count, index))
	order.sort_custom(func(a, b): return a.x > b.x)

	for candidate in order:
		preview.set("_index", candidate.y)
		await process_frame
		# Highest channel last, so the last one that qualifies is the topmost --
		# nothing above it can eat the click aimed at its centre.
		var chosen := 0
		for sprite in _frame_sprites(preview):
			var rect: Rect2 = preview.call("_stage_rect", sprite)
			if rect.size.x < 4.0 or rect.size.y < 4.0:
				continue
			var channel := int(sprite["channel"])
			# Eligible *and* actually answered where it will be aimed at. The
			# second is not implied by the first: a sprite can respond to the
			# mouse and still be covered at its own centre, or be hit-tested per
			# pixel and be transparent there.
			if int(preview.call("_channel_at", rect.get_center())) == channel:
				chosen = channel
		if chosen > 0:
			return chosen
	return 0


func _frame_sprites(preview: Node) -> Array:
	var score = preview.get("_score")
	if score == null:
		return []
	return score.call("frame", int(preview.call("current_frame"))).get("sprites", [])
