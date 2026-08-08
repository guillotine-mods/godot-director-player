extends SceneTree
## What is on the stage right now, and what the mouse can do with each of it.
##
##   godot --headless --path . --script tools/channel_report.gd -- --save saves/piposh2/x.json
##   godot --headless --path . --script tools/channel_report.gd -- --file PIP2DATA/DAY1.DIR --frame 1025
##   godot --headless --path . --script tools/channel_report.gd -- --root piposh --file PIPDATA/DAY1.dir --label dl1go
##
## A survey, not a gate entry: it prints and asserts nothing, like
## `ink_survey.gd` and `hilite_survey.gd`.
##
## It exists because "I think something is wrong with this thing on screen" is
## the most common shape of bug report here, and answering it used to mean
## standing up the movie, finding the channel, and asking three separate
## questions in three separate places -- is a sprite there, can it be clicked,
## does it carry a cursor. Those three answers only mean anything **side by
## side**: a sprite that is eligible with no cursor is a hotspot that does not
## advertise itself, and one with a cursor that is not eligible is the opposite
## and worse.
##
## The case that prompted it: a player asked whether a shovel leaning against a
## wall should show a hand cursor. One run of this said channel 17 was eligible
## and carried no cursor, while channels 103-110 -- the inventory slots -- all
## did, which is exactly what `DAY1`'s `init all` writes: the hand goes on a slot
## that holds something, never on scenery. The answer was "the original does
## this too", and it took one command instead of half a day.
##
## Pairs with `--save`. A saved state restores the exact movie, frame, globals
## and puppet state, so this reports on the situation the player was actually
## looking at rather than on whatever a fresh boot happens to reach.

const Args := preload("res://tools/lib/args.gd")


func _init() -> void:
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var p: Node = scene.instantiate()
	root.add_child(p)
	for i in 6:
		await process_frame

	# `--frame` steps the playhead rather than jumping it, so the frame is
	# entered the way the movie enters it -- its tempo armed, its scripts run. A
	# jump would report a frame no script had prepared.
	var wanted := Args.number(args, "frame", -1)
	if wanted >= 0:
		for i in 4000:
			if int(p.call("current_frame")) == wanted:
				break
			p.call("_advance")
		for i in 4:
			await process_frame

	var score = p.get("_score")
	var table = p.get("_table")
	if score == null:
		print("no movie loaded")
		quit(1)
		return
	var index := int(p.call("current_frame"))
	var frame: Dictionary = score.frame(index)
	var cursors: Dictionary = p.get("_channel_cursors")
	var sprites: Array = frame.get("sprites", [])

	print("%s  frame %d of %d  |  %d sprite(s), cursors on %s, global cursor %s" % [
		str(p.call("movie_name")), index, score.frame_count, sprites.size(),
		str(cursors.keys()), str(p.get("_global_cursor")),
	])
	print("%-6s %-9s %-20s %-24s %-12s %s" % [
		"chan", "member", "name", "rect", "cursor", "clickable because"])

	for raw in sprites:
		var s: Dictionary = p.call("_effective", raw)
		# `{}` is a sprite a script has hidden. It is not on the stage, and
		# listing it would be listing something the player cannot see.
		if s.is_empty():
			continue
		var channel := int(s["channel"])
		var member: Dictionary = table.get_member(
			int(s["cast_lib"]), int(s["cast_id"]))
		var rect: Rect2 = p.call("_sprite_rect", s)
		# The *reason* rather than a boolean, where the engine can give one: which
		# of the eligibility clauses fired is the answer to "why is this
		# clickable", and a bare yes leaves the reader to work it out again.
		var why := ""
		if p.has_method("_eligibility_reason"):
			why = str(p.call("_eligibility_reason", s))
		elif bool(p.call("_responds_to_mouse", s)):
			why = "yes"
		print("%-6s %-9s %-20s %-24s %-12s %s" % [
			"ch%d" % channel,
			"%d:%d" % [int(s["cast_lib"]), int(s["cast_id"])],
			str(member.get("name", "")).substr(0, 20),
			"(%d,%d %dx%d)" % [rect.position.x, rect.position.y,
				rect.size.x, rect.size.y],
			str(cursors.get(channel, "-")),
			why if why != "" else "- not clickable",
		])
	quit()
