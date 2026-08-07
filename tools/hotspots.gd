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
## hit-tests per pixel, and — the part that usually settles it — whether anything
## gives it a mouse handler.
##
## Reads the real preview node, so what it reports is what the game sees.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")


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
	for i in 400:
		if int(preview.call("current_frame")) == frame:
			break
		preview.call("_advance")

	print("%s frame %d%s" % [
		str(preview.call("movie_name")), frame,
		("  (marker %s)" % marker) if marker != "" else "",
	])
	print("")
	print("ch    member   rect                     ink  hit    responds  why")

	var sprites: Array = score.frame(frame).get("sprites", [])
	var eligible := 0
	for s_value in sprites:
		var raw: Dictionary = s_value
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			print("%-5d %-8s %-24s  %-4s %-6s %-9s %s" % [
				int(raw["channel"]), "%d:%d" % [int(raw["cast_lib"]), int(raw["cast_id"])],
				"-", "-", "-", "no", "hidden by a script",
			])
			continue
		var channel := int(sprite["channel"])
		var ink := int(sprite["ink"])
		var rect: Rect2 = preview.call("_stage_rect", sprite)
		var responds: bool = preview.call("_responds_to_mouse", sprite)
		if responds:
			eligible += 1
		var why := ""
		if not responds:
			var behaviour: Dictionary = preview.call("_sprite_script", channel, frame)
			var member_script: Dictionary = preview.call(
				"_script_for_member", int(sprite["cast_id"])
			)
			why = "no behaviour" if behaviour.is_empty() else "behaviour declares no mouse handler"
			if not member_script.is_empty():
				why += ", member script declares none"
		print("%-5d %-8s %-24s  %-4d %-6s %-9s %s" % [
			channel, "%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])],
			"(%d,%d) %dx%d" % [
				int(rect.position.x), int(rect.position.y),
				int(rect.size.x), int(rect.size.y),
			],
			ink, "pixel" if Ink.hits_per_pixel(ink) else "rect",
			"YES" if responds else "no", why,
		])

	print("")
	print("%d of %d sprites can answer a click" % [eligible, sprites.size()])

	var h := Harness.new()
	h.begin("the frame has at least one live hotspot")
	h.check("something on this frame is clickable", eligible > 0, "%d eligible" % eligible)
	h.complete("the frame has at least one live hotspot")
	quit(h.finish("hotspot eligibility on one frame"))
