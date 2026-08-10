extends SceneTree
## Stand one container on one frame, press what you name, and photograph it.
##
##   godot --path . --script tools/scene_probe.gd -- --root piposh \
##       --movie PIANO.dir --marker playpiano --out /tmp/playpiano.png
##   godot --path . --script tools/scene_probe.gd -- --root piposh \
##       --movie PIANO.dir --marker listenpiano --clicks "ch12;ch13" \
##       --out /tmp/song.png
##
##   --movie C       container to `go to movie`, resolved the way the game does
##   --marker M      where to stand (`--frame N` for a frame number instead)
##   --clicks LIST   `;`-separated presses, each `x,y` in stage pixels or `chN`
##                   for the centre of whatever channel N is drawing
##   --settle N      process frames after each step (default 8)
##   --ticks N       process frames after the last press, before the photo (24)
##   --out PATH      where the PNG goes; omit for the channel table alone
##   --hold          stop the playhead once it arrives, so the frame photographed
##                   is the frame named. Without it the score runs on through the
##                   settle and the ticks.
##   --stage W,H     size the window to the stage, so one photo pixel is one
##                   stage pixel and a crop can be read against the score's own
##                   coordinates. `project.godot` opens maximized, and a shot
##                   scaled by 3.54 cannot be compared with a member's bitmap.
##
##                   **Only an integer scale is comparable, and the window size
##                   that gives one is not the stage size.** The stage takes 75%
##                   of the window's width, so 854x640 yields 641x480 -- a
##                   *fractional* 1.0016 -- and comparing that against a 640x480
##                   render reports 38% of the stage differing, all of it the
##                   capture. `1707,1280` yields exactly 1280x960, scale 2.000;
##                   sample the top-left of each 2x2 block. Check the content
##                   bounding box before trusting any pixel comparison.
##   --fields LIST   `,`-separated field member names to read back through the
##                   same path Lingo uses (`field "x"`), after the presses
##   --quiet         skip the channel table
##
## ## Why this exists
##
## `AGENTS.md` has said for some time that "there is no general 'where did the
## playhead go' probe right now", that the retired `tools/probe.gd` was deleted
## with the renderer it drove, and that rebuilding one on the preview is the
## single most useful tool this repo is missing. This is that, at the size the
## bug in front of it needed rather than at the size of the paragraph.
##
## The three existing views each stop one step short of a room you have to *play*
## to reach. `liveness_sweep` opens every container and asks whether the playhead
## can leave; `qa_walk` photographs what a player reaches but only what its
## budget reaches; `click_trace` explains one click and prints no pixels.
## Nothing lets you say "stand on `playpiano`, press two keys, and let me look at
## it" -- which is the question every wrong-picture report turns into.
##
## **The photograph is the point, so this does not run headless.** Headless Godot
## has a dummy texture storage and never paints, so `Snapshot.grab` would hand
## back null and this would write nothing while looking like it worked.
## `qa_walk` documents the same trap. Run it windowed; it says so and exits if
## you do not.
##
## **`director_render.gd` is not a second opinion about the same picture.** It is
## a separate compositor that skips field members outright -- it prints
## `skipped (field)` and moves on -- so a field drawn wrongly by the player is
## invisible to it. Anything about text on the stage has to come from here, off
## the real preview, or it is a measurement of the wrong renderer.
##
## Title-agnostic: nothing here knows what a game or a room is called.

const Args := preload("res://tools/lib/args.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")


func _init() -> void:
	var args := Args.parse()
	if DisplayServer.get_name() == "headless":
		print("scene_probe paints, so it cannot run headless -- drop --headless")
		quit(1)
		return

	var stage := Args.text(args, "stage", "").split(",", false)
	if stage.size() == 2:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(stage[0]), int(stage[1])))

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var settle := Args.number(args, "settle", 8)
	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		# A movie change is entered by the ticks after the call, not by the call:
		# `prepareMovie`/`startMovie` and the first frame's own scripts run then.
		for i in settle:
			await process_frame

	if preview.get("_score") == null:
		print("no score loaded")
		quit(1)
		return

	var frame := _target_frame(preview, args)
	if frame < 0:
		quit(1)
		return
	if frame != int(preview.call("current_frame")):
		# Entered, not merely indexed. A frame nobody stood on has run no
		# `enterFrame`, so its sprites carry the previous frame's puppet state.
		preview.set("_index", frame)
		for i in settle:
			await process_frame

	for press in Args.text(args, "clicks", "").split(";", false):
		var found: Variant = _point(preview, str(press))
		if found == null:
			continue
		var at: Vector2 = found
		print("press (%d,%d)" % [int(at.x), int(at.y)])
		preview.call("route_press", at)
		preview.call("route_release", at)
		for i in settle:
			await process_frame

	for i in Args.number(args, "ticks", 24):
		await process_frame

	# Held *after* the presses and the ticks, not before: a press has to be able
	# to move the playhead, and `--hold` is about the photograph being of the
	# frame this reports rather than of wherever the score got to while the
	# viewport was being read.
	if Args.flag(args, "hold"):
		preview.set("_paused", true)
		await process_frame

	print("%s  frame %d of %d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame")),
		int(preview.get("_score").frame_count),
	])
	if not Args.flag(args, "quiet"):
		_table(preview)

	# Read through `lingo_field`, not off the cast record: a script asking
	# `field "x"` goes through here, and a member that holds text while this
	# answers "" is the difference between a working branch and a dead one.
	if Args.text(args, "fields", "") != "":
		var overrides: Dictionary = preview.get("_field_text")
		print("field overrides held: %d  %s" % [
			overrides.size(), JSON.stringify(overrides).substr(0, 400)])
	for name in Args.text(args, "fields", "").split(",", false):
		var text: String = str(preview.call("lingo_field", str(name), ""))
		var where: Array = preview.call("_resolve_field", str(name))
		var stored := ""
		if not where.is_empty():
			stored = str(preview.get("_table").get_member(
				int(where[0]), int(where[1])).get("text", ""))
		print("field %-10s : resolves to %-10s  member text %d char(s)  lingo reads %d char(s)  %s" % [
			JSON.stringify(str(name)), str(where), stored.length(), text.length(),
			JSON.stringify(text.substr(0, 40)),
		])

	var out := Args.text(args, "out", "")
	if out != "":
		var image: Image = Snapshot.grab(preview)
		if image == null:
			print("the display server returned no pixels")
			quit(1)
			return
		image.save_png(out)
		print("wrote %s  (%dx%d)" % [out, image.get_width(), image.get_height()])
	quit(0)


## The frame `--marker` or `--frame` names, or the one already playing.
func _target_frame(preview: Node, args: Dictionary) -> int:
	var marker := Args.text(args, "marker", "")
	if marker == "":
		return Args.number(args, "frame", int(preview.call("current_frame")))
	var labels = preview.get("_labels")
	if labels != null:
		for m in labels.markers:
			if str((m as Dictionary)["name"]).to_lower() == marker.to_lower():
				return int((m as Dictionary)["frame"])
	print("no marker '%s' in %s" % [marker, str(preview.call("movie_name"))])
	return -1


## `x,y` as written, or `chN` as the centre of what channel N is drawing now.
func _point(preview: Node, press: String) -> Variant:
	var text := press.strip_edges()
	if text.to_lower().begins_with("ch"):
		var channel := int(text.substr(2))
		for value in _drawn(preview):
			var sprite: Dictionary = value
			if int(sprite["channel"]) == channel:
				var rect: Rect2 = preview.call("_stage_rect", sprite)
				return rect.position + rect.size * 0.5
		print("channel %d is drawing nothing here" % channel)
		return null
	var parts := text.split(",", false)
	if parts.size() != 2:
		print("cannot read a press from '%s'" % text)
		return null
	return Vector2(int(parts[0]), int(parts[1]))


## Every sprite the frame draws, after the scripts have had their say.
func _drawn(preview: Node) -> Array:
	var out: Array = []
	var score = preview.get("_score")
	var frame := int(preview.call("current_frame"))
	for value in (score.frame(frame).get("sprites", []) as Array):
		var sprite: Dictionary = preview.call("_effective", value as Dictionary)
		if not sprite.is_empty():
			out.append(sprite)
	return out


## What is on the stage, with the member's own size beside the rect it is drawn
## at -- because "drawn smaller than itself" is what a squashed picture is, and
## the two numbers side by side is the only way to see it.
func _table(preview: Node) -> void:
	var table = preview.get("_table")
	print("chan   member    name             natural    drawn rect")
	for value in _drawn(preview):
		var sprite: Dictionary = value
		var member: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var rect: Rect2 = preview.call("_stage_rect", sprite)
		var natural := "-"
		if int(member.get("width", 0)) > 0:
			natural = "%dx%d" % [int(member["width"]), int(member["height"])]
		var flag := ""
		if int(member.get("width", 0)) > 0 and (
				int(rect.size.x) != int(member["width"])
				or int(rect.size.y) != int(member["height"])):
			flag = "   <- drawn %.2fx by %.2fx" % [
				rect.size.x / float(member["width"]),
				rect.size.y / float(member["height"]),
			]
		print("ch%-5d %-9s %-16s %-10s (%d,%d %dx%d)%s" % [
			int(sprite["channel"]),
			"%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])],
			str(member.get("name", "")), natural,
			int(rect.position.x), int(rect.position.y),
			int(rect.size.x), int(rect.size.y), flag,
		])
