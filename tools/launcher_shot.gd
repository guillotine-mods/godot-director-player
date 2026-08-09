extends SceneTree
## A picture of the launcher, without a person having to take one.
##
##   godot --path . --script tools/launcher_shot.gd -- --out res://.snapshots/a.png
##   godot --path . --script tools/launcher_shot.gd -- --tab 1 --bindings --bad F5
##   godot --path . --script tools/launcher_shot.gd -- --size 800x600 --focus
##
## **Not `--headless`.** Headless Godot never paints, so the framebuffer grab
## returns an empty image and the file that lands is a black rectangle that reads
## as a rendering bug. The tool refuses rather than writing one.
##
## The switches exist because a single default grab cannot see the three things a
## restyle is most likely to break, and all three were invisible to the first
## version of this tool:
##
##   --size WxH   the launcher at a size somebody actually drags it to. The
##                project opens *maximized*, so the unqualified shot is a
##                desktop-sized image that hides every clipping bug.
##   --tab N      the Developer tab, which is half the screen and which nothing
##                else ever looks at.
##   --bindings   presses `Edit preview keys…` and waits out the corpus read, so
##                the dynamically built binding rows -- the most complex UI in
##                the file, and the only one built in code rather than in the
##                scene -- appear in the picture at all.
##   --bad NAME   types NAME into the first binding field, which is how the
##                invalid state gets captured. Pass a key some title tests (F10)
##                or a name that is not a key (Banana); either turns the field
##                and the Play button.
##   --focus      moves focus onto the first focusable control, so the focus ring
##                is in the shot. A launcher with no visible focus ring is not
##                keyboard-navigable, and that cannot be seen in a shot that
##                never focused anything.
##   --bottom     scrolls every scrolling region to its end. The Developer tab's
##                assists -- four check boxes and a slider, which is every
##                control class the theme styles that nothing else on screen
##                uses -- are past the fold at every size this tool can ask for,
##                so without it they have never appeared in a picture at all.

const Args := preload("res://tools/lib/args.gd")

const LAUNCHER := "res://scenes/launcher/launcher.tscn"
## Frames awaited before the grab. One is not enough: a `Control` tree settles
## its container sizes over the frame after the one it is added on, and a theme
## with fonts in it resolves them later still.
const SETTLE_FRAMES := 8
## `--bindings` reads every title's scripts, which the launcher's own comment
## calls seconds. Awaiting frames rather than sleeping keeps this on the same
## clock as the UI it is waiting for.
const MEASURE_FRAMES := 600


func _init() -> void:
	var args := Args.parse()
	await _shoot(args)


func _shoot(args: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		printerr("launcher_shot: headless paints nothing — drop --headless")
		quit(1)
		return
	_resize(Args.text(args, "size", ""))
	# Autoloads are added a frame into a `--script` run, not before `_init`, and
	# `launcher.gd` names two of them (`AppSettings`, `AudioDirector`). Loading it
	# any earlier fails to *compile* — "Identifier not found: AppSettings" — which
	# reads as a bug in the launcher rather than as this tool being early.
	await process_frame
	# The launcher plays straight through when the command line names a game, so
	# a run of this tool must not name one. `Args` only reads what is after `--`,
	# and none of this tool's switches collide with `--root`/`--boot`/`--save`.
	var scene: Node = load(LAUNCHER).instantiate()
	root.add_child(scene)
	await _settle()

	await _open_tab(scene, Args.number(args, "tab", 0))
	if Args.flag(args, "bindings"):
		await _open_bindings(scene)
	_type_bad(scene, Args.text(args, "bad", ""))
	if Args.flag(args, "bottom"):
		await _scroll_to_end(scene)
	if Args.flag(args, "focus"):
		_focus_first(scene)
	await _settle()

	_write(Args.text(args, "out", "res://.snapshots/launcher.png"))


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _resize(size: String) -> void:
	if size == "":
		return
	var wh := size.split("x")
	if wh.size() != 2:
		printerr("launcher_shot: --size wants WxH, got '%s'" % size)
		return
	# The project opens maximized (`window/size/mode=2`), and a resize on a
	# maximized window is ignored, so the mode has to drop to windowed first or
	# every `--size` silently produces the same desktop-sized grab.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	root.content_scale_size = Vector2i(int(wh[0]), int(wh[1]))


## Reached by name, not by path. `%Tabs` is a `unique_name_in_owner` node and the
## whole point of that marking is that the tree above it may be rearranged; a
## path here would make this tool the reason a layout cannot change.
func _open_tab(scene: Node, tab: int) -> void:
	if tab <= 0:
		return
	var tabs := scene.get_node_or_null("%Tabs")
	if tabs is TabContainer and tab < (tabs as TabContainer).get_tab_count():
		(tabs as TabContainer).current_tab = tab
		await _settle()
	else:
		printerr("launcher_shot: no tab %d" % tab)


func _open_bindings(scene: Node) -> void:
	var button := scene.get_node_or_null("%BindingsButton") as BaseButton
	if button == null:
		printerr("launcher_shot: no %BindingsButton — is the Developer tab hidden?")
		return
	button.emit_signal("pressed")
	var panel := scene.get_node_or_null("%Bindings") as Control
	for i in MEASURE_FRAMES:
		await process_frame
		if panel != null and panel.visible and panel.get_child_count() > 0:
			break
	await _settle()


## Types into the first binding row, which is enough to show the invalid state:
## `_on_binding_changed` revalidates every field and `_refresh_play` re-reads
## Play, so one bad name turns both.
func _type_bad(scene: Node, name: String) -> void:
	if name == "":
		return
	var panel := scene.get_node_or_null("%Bindings") as Control
	if panel == null or panel.get_child_count() == 0:
		printerr("launcher_shot: --bad needs --bindings")
		return
	for row in panel.get_children():
		for child in (row as Node).get_children():
			if child is LineEdit:
				(child as LineEdit).text = name
				# `text` does not emit, so the validation the launcher hangs off
				# `text_changed` would never run and the shot would show a bad
				# name in a field that still looks fine.
				(child as LineEdit).text_changed.emit(name)
				return
	printerr("launcher_shot: no binding field to type into")


## Every region and not the visible one, because which tab is open is another
## switch's business and a scroll on a hidden tab costs nothing.
func _scroll_to_end(scene: Node) -> void:
	for scroll in _scrolls(scene):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _settle()


func _scrolls(node: Node) -> Array[ScrollContainer]:
	var found: Array[ScrollContainer] = []
	if node is ScrollContainer:
		found.append(node as ScrollContainer)
	for child in node.get_children():
		found.append_array(_scrolls(child))
	return found


func _focus_first(scene: Node) -> void:
	var control := _first_focusable(scene)
	if control == null:
		printerr("launcher_shot: nothing on this screen can take focus")
		return
	control.grab_focus()


func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		var control := child as Control
		if control != null and control.visible:
			if control.focus_mode == Control.FOCUS_ALL and not _disabled(control):
				return control
			var found := _first_focusable(control)
			if found != null:
				return found
	return null


func _disabled(control: Control) -> bool:
	return control is BaseButton and (control as BaseButton).disabled


func _write(out: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("launcher_shot: nothing was painted")
		quit(1)
		return
	var dir := out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if image.save_png(out) != OK:
		printerr("launcher_shot: could not write %s" % out)
		quit(1)
		return
	print("wrote %s (%dx%d)" % [ProjectSettings.globalize_path(out), image.get_width(),
		image.get_height()])
	quit(0)
