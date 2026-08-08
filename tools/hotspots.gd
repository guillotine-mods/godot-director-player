extends SceneTree
## Why a sprite does or does not answer a click.
##
##   godot --headless --script tools/hotspots.gd -- --file PIP2DATA/DAY1.dir --marker shore2
##   godot --headless --script tools/hotspots.gd -- --file PIP2DATA/DAY1.dir --frame 37
##
## "That thing is supposed to be clickable and it isn't" has at least six causes
## and they are indistinguishable from the player's chair: the sprite may not be
## in the frame at all, its member may not resolve, it may have no script that
## declares a mouse handler, it may be a cast type this renderer draws nothing
## for, its ink may make it hit-test per pixel where the artwork is transparent,
## or a higher channel may be eating the click first.
##
## So this reports the whole descent for one frame rather than a verdict: every
## sprite in channel order with its member, its rect, its ink, whether the ink
## hit-tests per pixel, and — the part that usually settles it — **which of
## §4.3's six eligibility clauses fired**, beside what the attached behaviours
## actually declare.
##
## Those last two are different answers and on a D6+ movie they usually disagree,
## which is the thing worth knowing here. From D6 a sprite with any behaviour is
## a click target whatever the behaviour declares, so `D6+ behaviour attached
## [1:207 exitFrame]` is an ordinary and correct line: the sprite absorbs the
## click and the message reaches a script with no handler for it. A sprite that
## looks dead in the game and reads eligible here is that line, and the next
## question is §6.3's chain rather than the hit test.
##
## Reads the real preview node, so what it reports is what the game sees.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")


func _init() -> void:
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var score = preview.get("_score")
	var labels = preview.get("_labels")
	if score == null:
		print("no score loaded")
		quit(1)
		return

	var frame := Args.number(args, "frame", -1)
	var marker := Args.text(args, "marker", "")
	if marker != "" and labels != null:
		for m in labels.markers:
			if str(m["name"]).to_lower() == marker.to_lower():
				frame = int(m["frame"])
				break
		if frame < 0:
			print("no marker '%s'" % marker)
			quit(1)
			return
	if frame < 0:
		frame = 0

	# Step the movie to that frame so puppet state and scripts are as they would
	# be in play, rather than as they are on a cold score read.
	var arrived := false
	for i in 400:
		if int(preview.call("current_frame")) == frame:
			arrived = true
			break
		preview.call("_advance")

	# **The playhead does not always get there, and the report has to be about
	# the frame it names anyway.** `_advance` follows the movie's own flow, so a
	# room that holds on a `go to the frame` never reaches a marker further on --
	# `BATZEGOZ.dir`'s `Egoz1` is frame 194 and 400 steps stop short of it.
	#
	# That silently made this tool wrong rather than incomplete, and the wrongness
	# was quoted as evidence. Everything derived from the *score* was read at
	# `frame` (the sprite list, `_sprite_script(channel, frame)`) while
	# `_responds_to_mouse` read `_index`, wherever the playhead had stopped -- so
	# the three dialogue options at `Egoz1` printed "behaviour declares no mouse
	# handler" **next to a behaviour that declares `mouseUp`**, and that line went
	# into `ENGINE_TODO.md` as the measurement of a missing eligibility clause. The
	# clause was missing; this frame was never the proof of it.
	#
	# Pinned rather than reported-and-left, because a report whose columns
	# disagree about which frame they describe is worse than one with stale
	# puppet state, and stale puppet state is what is left: it is the state of
	# wherever the playhead stopped, which is said out loud below.
	preview._index = frame
	print("%s frame %d%s" % [
		str(preview.call("movie_name")), frame,
		("  (marker %s)" % marker) if marker != "" else "",
	])
	if not arrived:
		print("(the playhead stopped short of this frame; the score is read at"
			+ " %d and any puppet state is from where it stopped)" % frame)
	print("")
	print("ch    member   rect                     ink  hit    responds  why")

	var sprites: Array = score.frame(frame).get("sprites", [])
	var eligible := 0
	var classified := 0
	var table = preview.get("_table")
	for s_value in sprites:
		var raw: Dictionary = s_value
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			print("%-5d %-8s %-24s  %-4s %-6s %-9s %s" % [
				int(raw["channel"]), "%d:%d" % [int(raw["cast_lib"]), int(raw["cast_id"])],
				"-", "-", "-", "no", "hidden by a script",
			])
			classified += 1
			continue
		var channel := int(sprite["channel"])
		var ink := int(sprite["ink"])
		# The cast type decides how a click is tested as much as the ink does: a
		# matte is flooded in from the border of a *bitmap's* image, and a shape
		# has none, so a matte-inked shape is a rectangle. Reporting it as "pixel"
		# would send the next reader looking for artwork that does not exist.
		var member_type: int = int(preview.get("_table").get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"])).get("type", 0))
		var rect: Rect2 = preview.call("_stage_rect", sprite)
		# The clause, not a boolean. §4.3 is six clauses tested in order and which
		# one fired is the whole of what the reader came for -- "YES" alone sends
		# them to read the predicate, and on a D6+ movie the answer is nearly
		# always the *fourth* clause, which is the one nobody expects because it
		# ignores what the behaviour declares. Asked of the engine's own function
		# so that this cannot drift from what the hit test does.
		var why: String = Interaction.eligibility_reason(preview, sprite, table)
		var responds := why != ""
		classified += 1
		if responds:
			eligible += 1
		else:
			var behaviour: Dictionary = preview.call("_sprite_script", channel, frame)
			var member_script: Dictionary = preview.call(
				"_script_for_member", int(sprite["cast_id"])
			)
			why = "no behaviour" if behaviour.is_empty() else "behaviour declares no mouse handler"
			if not member_script.is_empty():
				why += ", member script declares none"
		# What the behaviour actually declares, beside the verdict. From D6 the
		# sprite is a click target whatever that is, so the two answers come
		# apart routinely -- and when they do, "eligible, declares exitFrame" is
		# the line that explains why a click on it runs nothing: the message
		# reaches a script with no handler for it, and §6.3's chain is what
		# decides whether the tiers below still get a turn.
		var attached: Array = Interaction.behaviour_intervals(preview, channel, frame)
		var declares := PackedStringArray()
		for value in attached:
			var interval: Dictionary = value
			var script: Dictionary = preview.call("_script_in_lib",
				int(interval["script_cast_lib"]), int(interval["script_member"]))
			if script.is_empty():
				declares.append("%d:%d unresolved" % [
					int(interval["script_cast_lib"]), int(interval["script_member"])])
				continue
			var names := PackedStringArray()
			for handler in script.get("handlers", []):
				names.append(str((handler as Dictionary).get("name", "")))
			if not (script.get("body", []) as Array).is_empty():
				names.append("<generic body>")
			declares.append("%d:%d %s" % [
				int(interval["script_cast_lib"]), int(interval["script_member"]),
				"/".join(names) if names.size() > 0 else "nothing"])
		if declares.size() > 0:
			why += "%s[%s]" % ["  " if why != "" else "", ", ".join(declares)]
		print("%-5d %-8s %-24s  %-4d %-6s %-9s %s" % [
			channel, "%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])],
			"(%d,%d) %dx%d" % [
				int(rect.position.x), int(rect.position.y),
				int(rect.size.x), int(rect.size.y),
			],
			ink, "pixel" if Ink.hits_per_pixel(ink, member_type) else "rect",
			"YES" if responds else "no", why,
		])

	print("")
	print("%d of %d sprites can answer a click" % [eligible, sprites.size()])

	# Deliberately not "at least one sprite must be clickable". That is not a
	# property of Director and it is not true of real frames: MAP's frame 0 holds
	# a backdrop, a panel and one off-stage sprite, and none of them has a
	# behaviour, because the map's regions arrive a few frames later. A tool that
	# failed on that would be teaching the wrong lesson. What is worth asserting
	# is that every sprite got a verdict rather than being skipped.
	var h := Harness.new()
	h.begin("every sprite on the frame was classified")
	h.check("no sprite was skipped", classified == sprites.size(),
		"%d of %d" % [classified, sprites.size()])
	h.complete("every sprite on the frame was classified")
	quit(h.finish("hotspot eligibility on one frame"))
