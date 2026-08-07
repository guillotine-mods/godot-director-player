extends SceneTree
## Does an opened Movie-In-A-Window actually put pixels on the screen?
##
##   godot --path . --script tools/window_renders.gd -- --file PIP2DATA/DAY1.dir
##
## **Must be run windowed, not headless.** Headless Godot discards the draw list,
## so every lifecycle check can pass -- window created, visible, processing,
## stepping its own score -- while nothing is painted. That is exactly the state
## this was written to catch: the joke window opened, loaded its 96 frames, ran
## its `startMovie`, and the player saw an unchanged room.
##
## So this reads the framebuffer. It samples the window's rectangle before the
## window is opened and again after, and requires the pixels to have changed. A
## window that renders nothing fails; a window that renders is indistinguishable
## from one that renders *correctly*, which this does not claim to check.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _sample(rect: Rect2i) -> PackedByteArray:
	var image := root.get_texture().get_image()
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return PackedByteArray()
	return image.get_region(clipped).get_data()


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	for i in 6:
		await process_frame

	# Get the host movie somewhere settled before touching anything.
	for i in 200:
		if int(preview.call("current_frame")) == Args.number(args, "frame", 40):
			break
		preview.call("_advance")
	for i in 4:
		await process_frame

	h.begin("an opened window paints")

	var name := Args.text(args, "window", "joke.dxr")
	# Where the window will land, asked before it opens so the "before" sample
	# covers the same pixels as the "after" one.
	var handle: Dictionary = preview.call("lingo_window", name)
	var key := str(handle.get("window", ""))
	h.check("the window movie resolved", key != "", name)
	if key == "":
		h.complete("an opened window paints")
		quit(h.finish("window rendering"))
		return

	var node: Node = (preview.get("_windows") as Dictionary).get(key)
	h.check("the window node exists", node != null, key)
	if node == null:
		h.complete("an opened window paints")
		quit(h.finish("window rendering"))
		return

	# Its geometry is settled by `window_shown`, so open it once to learn the
	# rectangle, sample the screen *without* it, then show it again.
	preview.call("lingo_open_window", name)
	for i in 4:
		await process_frame
	var origin: Vector2 = node.get_global_transform_with_canvas().origin
	var size: Vector2 = Vector2(640, 480) * preview.scale
	var rect := Rect2i(Vector2i(origin), Vector2i(size))
	node.visible = false
	for i in 4:
		await process_frame
	var without := _sample(rect)

	node.visible = true
	for i in 6:
		await process_frame
	var with := _sample(rect)

	h.check("the window's rectangle is on screen", not without.is_empty(),
		"rect %s, viewport %s" % [str(rect), str(root.get_texture().get_image().get_size())])
	var changed := 0
	for i in mini(without.size(), with.size()):
		if without[i] != with[i]:
			changed += 1
	h.check("showing the window changes the pixels under it", changed > 0,
		"%d of %d bytes differ" % [changed, mini(without.size(), with.size())])
	print("window '%s' at %s: %d bytes changed" % [key, str(rect), changed])
	h.complete("an opened window paints")
	quit(h.finish("window rendering"))
