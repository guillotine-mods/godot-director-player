extends SceneTree
## Does the Piposh 3D tile actually boot inside the player?
##
##   godot --path . --script tools/piposh3d_boot.gd
##
## The launcher listing the title proves the pack mounted and the config parsed.
## It does not prove the title *runs*, and those are different claims: the scene
## behind it pulls in the whole of that project's code, which resolves its types
## through `const ... = preload(...)` out of the same pack.
##
## **Not `--headless`.** The scene builds 3D nodes and a headless run paints
## nothing, so the interesting failures -- a shader, a mesh, a missing texture --
## would not happen at all and the check would pass by not looking.
##
## Frames are awaited rather than a fixed sleep because the boot scene routes
## onward: `boot.gd` decides between the intro movies and the menu on its first
## frame, so a check that grabbed frame 1 would be asking about a scene that is
## already on its way out.

const SCENE := "res://scenes/boot.tscn"
const SETTLE_FRAMES := 30


func _init() -> void:
	root.call_deferred("set_title", "piposh3d boot check")
	_run.call_deferred()


func _run() -> void:
	# The mount is asked about through a path inside the pack rather than through
	# `Piposh3DPack.mounted`. Naming the autoload here would be a compile-time
	# reference, and in a `--script` run autoloads register a frame in -- so the
	# check would fail to compile before it could look at anything.
	var ok := true
	if not ResourceLoader.exists(SCENE):
		print("FAIL  %s is not in the pack" % SCENE)
		quit(1)
		return
	print("ok    %s resolves" % SCENE)

	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("FAIL  %s did not load" % SCENE)
		quit(1)
		return
	print("ok    it loaded as a PackedScene")

	var node := packed.instantiate()
	if node == null:
		print("FAIL  it did not instantiate")
		quit(1)
		return
	root.add_child(node)
	print("ok    it instantiated and entered the tree (%s)" % node.get_class())

	for i in SETTLE_FRAMES:
		await process_frame
	var live := is_instance_valid(node) or root.get_child_count() > 1
	print("%s  it is still alive after %d frames (%d node(s) under root)"
		% ["ok   " if live else "FAIL ", SETTLE_FRAMES, root.get_child_count()])
	ok = ok and live

	print("\n%s  the piposh 3d boot" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
