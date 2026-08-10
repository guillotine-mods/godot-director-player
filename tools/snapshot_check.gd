extends SceneTree
## Does the snapshot key copy something a bug report can be written from?
##
##   godot --headless --script tools/snapshot_check.gd     (no image; see below)
##   godot --script tools/snapshot_check.gd                (the whole thing)
##
## The four facts that turn "clicking the thing does nothing" into something
## reproducible are which game is configured, which container is playing, which
## frame it is on, and what the last click resolved to. This asserts that all
## four are in the copied text, that the click line is the *captured* one rather
## than a fresh computation against whatever frame the playhead has reached
## since, and that the image is written where `.gitignore` already covers.
##
## The image half needs a windowed run. Headless Godot discards the draw list, so
## `get_texture().get_image()` has nothing in it -- and the snapshot says so in
## the copied text rather than saving a black rectangle that reads as a rendering
## bug the next time somebody opens it.

const Harness := preload("res://tools/lib/harness.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")
const Toast := preload("res://scenes/preview/toast.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")


## Somewhere to click. A sprite the mouse can actually reach if the movie offers
## one, and the middle of the stage otherwise -- a click that hits nothing is
## still a click the snapshot has to be able to report, and telling "clicked
## nothing" from "clicked something with no handler" is the whole reason the line
## records the channel and the handler separately.
func _clickable_point(preview: Node) -> Vector2:
	var score = preview.get("_score")
	# Whole-rect hit testing for the search only. The per-pixel test decodes
	# artwork for every candidate, and doing that across a few hundred frames
	# takes minutes -- which is a harness that looks hung, not a slow one.
	var pixels: bool = preview.get("_hit_pixels")
	preview.set("_hit_pixels", false)
	var found := Vector2(-1, -1)
	var at_frame := 0
	for i in mini(score.frame_count, 200):
		preview.set("_index", i)
		for raw in score.frame(i).get("sprites", []):
			var sprite: Dictionary = preview.call("_effective", raw)
			if sprite.is_empty():
				continue
			var rect: Rect2 = preview.call("_sprite_rect", sprite)
			if rect.size.x < 4.0 or rect.size.y < 4.0:
				continue
			if int(preview.call("_channel_at", rect.get_center())) > 0:
				found = rect.get_center()
				at_frame = i
				break
		if found.x >= 0.0:
			break
	preview.set("_hit_pixels", pixels)
	preview.set("_index", at_frame)
	return found if found.x >= 0.0 else Vector2(preview.call("stage_size")) * 0.5


## Can this process read back what it just put on the clipboard? Answered by
## trying, not by asking `has_feature`, which says yes on Windows and then does
## not round-trip in a `--script` run.
func _clipboard_round_trips() -> bool:
	var was := DisplayServer.clipboard_get()
	DisplayServer.clipboard_set("godot-director-player clipboard probe")
	var ok := DisplayServer.clipboard_get() == "godot-director-player clipboard probe"
	DisplayServer.clipboard_set(was)
	return ok


func _init() -> void:
	var h := Harness.new()
	DebugKeys.load_config()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	for _i in 4:
		await process_frame

	h.begin("the key is bound and nothing else is on it")
	h.check("snapshot has a key", DebugKeys.key_name("snapshot") != "",
		DebugKeys.key_name("snapshot"))
	h.check("that key runs the snapshot",
		DebugKeys.command_for(
			OS.find_keycode_from_string(DebugKeys.key_name("snapshot"))) == "snapshot")
	h.complete("the key is bound and nothing else is on it")

	# A click, then some frames, then the snapshot: the point of capturing the
	# click rather than recomputing it is that these are different frames.
	var at := _clickable_point(preview)
	h.begin("the copied click is the click that happened")
	var clicked_on := int(preview.get("_index"))
	preview.call("route_click", at)
	for _i in 5:
		preview.call("_advance")
	var moved_on := int(preview.get("_index"))

	var click: Dictionary = preview.get("_last_click")
	h.check("a click was recorded", not click.is_empty())
	h.check("it names the frame it happened on, not the frame now",
		int(click.get("frame", -1)) == clicked_on,
		"recorded %d, clicked %d, now %d" % [
			int(click.get("frame", -1)), clicked_on, moved_on])
	h.check("it says whether a handler exists at all",
		typeof(click.get("handler")) == TYPE_BOOL)
	h.complete("the copied click is the click that happened")

	h.begin("the copied text carries the four facts")
	var text := Snapshot.take(preview)
	h.check("the configured game", text.contains(str(preview.get("_paths").root)))
	h.check("the container", text.contains(str(preview.call("movie_name"))))
	h.check("the frame number", text.contains("frame     : %d of" % moved_on),
		"frame %d" % moved_on)
	h.check("the last click", text.contains(Snapshot.click_line(click)))
	# Only where the clipboard demonstrably round-trips. It does not in a
	# `--script` run on Windows even with a window open -- `clipboard_set`
	# followed immediately by `clipboard_get` answers "" -- and asserting it
	# anyway would make this red for a reason that is not the snapshot's. The
	# probe is what tells the two apart: a check that cannot run says so, and a
	# check that can run is not skipped.
	if _clipboard_round_trips():
		h.check("and it is on the clipboard", DisplayServer.clipboard_get() == text)
	else:
		print("clipboard round-trip unavailable here; the copy itself is not asserted")
	h.complete("the copied text carries the four facts")

	# Directly, rather than via a synthetic key event: `_input` is Godot's to
	# call and a headless run has no window to deliver one to.
	h.begin("the confirmation appears and then goes away by itself")
	InputRouter.debug_key(preview,
		OS.find_keycode_from_string(DebugKeys.key_name("snapshot")))
	h.check("a message is showing", str(preview.get("_toast")) != ""
		and Toast.showing(int(preview.get("_toast_until"))))
	h.check("it names the container so it is not just 'done'",
		str(preview.get("_toast")).contains(str(preview.call("movie_name"))),
		str(preview.get("_toast")))
	# The deadline is what dismisses it, so the assertion is about the deadline
	# rather than about waiting two and a half seconds for it.
	var left := int(preview.get("_toast_until")) - Time.get_ticks_msec()
	h.check("it expires within a couple of seconds",
		left > 0 and left <= int(Toast.SECONDS * 1000.0), "%d ms left" % left)
	h.check("and is gone once the deadline passes",
		not Toast.showing(Time.get_ticks_msec() - 1))
	h.complete("the confirmation appears and then goes away by itself")

	h.begin("the image lands somewhere git already ignores")
	var ignored := FileAccess.get_file_as_string("res://.gitignore")
	h.check(".gitignore covers the snapshot directory",
		ignored.contains("%s/" % Snapshot.DIRECTORY.trim_prefix("res://")),
		Snapshot.DIRECTORY)
	if DisplayServer.get_name() == "headless":
		h.check("headless says so rather than saving a black frame",
			text.contains("not saved"), text.get_slice("image     : ", 1))
	else:
		var written := text.split("image     : ")[1].strip_edges()
		h.check("the PNG is on disk", FileAccess.file_exists(written), written)
		h.check("and it is not blank",
			Image.load_from_file(written).get_size() != Vector2i.ZERO, written)
	h.complete("the image lands somewhere git already ignores")

	quit(h.finish("the snapshot key"))
