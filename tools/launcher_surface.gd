extends SceneTree
## The launcher's node names are an API, and this is what asserts they still are.
##
##   godot --headless --path . --script tools/launcher_surface.gd
##   godot --path . --script tools/launcher_surface.gd     (adds the resize case)
##
## `tools/launcher_shot.gd` reaches into the scene by `unique_name_in_owner`
## name, and nothing else instantiates `launcher.tscn` at all: `launcher_keys`
## and `title_list` test pure functions and would still pass with every node in
## the scene renamed. That is `scenes/preview/README.md`'s argument for
## `preview_surface.gd` -- a field moved off the node makes a harness read null
## and report zero rather than fail -- arriving on the other screen.
##
## **It runs in two modes, and neither is the other one quietly doing less.**
## `gate.sh` hands every tool `--root` and `--boot`, and `--root` is exactly what
## makes the launcher play straight through into the movie without building a
## menu -- so under the gate there is no menu here to inspect. Rather than
## reporting zero rows as a pass, that run asserts the bypass itself, which is
## the invariant `launcher.gd:_ready` opens with and which nothing tested
## before:
##
##   a game named      nothing may be built. No theme, no items, no tiles, and
##                     the input router still as it was -- every one of those is
##                     assigned *below* the bypass, so any of them arriving
##                     means work has crept above it.
##   no game named     the menu is the subject: rows, focus map, focus on open.
##
## The names and the classes are checked either way, because they live in the
## scene file rather than in anything `_ready` builds.
##
## Headless is fine, and is the default. `Control` layout is CPU-side and runs
## without a renderer -- containers sort, minimum sizes resolve, the focus map
## gets built -- which is worth stating because this file used to claim the
## opposite and refuse to start. What headless will not do is honour
## `window_set_size`, so the one case that drives a resize is windowed-only and
## says so in the output rather than passing on a window that never moved.

const Harness := preload("res://tools/lib/harness.gd")

const LAUNCHER := "res://scenes/launcher/launcher.tscn"
const SETTLE_FRAMES := 8
## `--bindings` reads every title's scripts, which the launcher's own comment
## calls seconds. Awaited as frames, on the same clock as the UI.
const MEASURE_FRAMES := 900

## Every name a tool reaches by, and what it has to still be.
const SURFACE := {
	"Tabs": "TabContainer",
	"Games": "OptionButton",
	"Flags": "HBoxContainer",
	"Aspect": "OptionButton",
	"Play": "Button",
	"Developer": "Control",
	"Boot": "LineEdit",
	"Codepage": "OptionButton",
	"Debug": "OptionButton",
	"BindingsButton": "Button",
	"BindingsStatus": "Label",
	"Bindings": "VBoxContainer",
	"HotspotHints": "CheckBox",
	"MinigameSkip": "CheckBox",
	"EdgeHotspots": "CheckBox",
	"EnhancedGraphics": "CheckBox",
	"CursorSpeed": "HSlider",
}

## The same three the launcher treats as "a game is named", read the same way.
## Copied rather than called, because calling it would mean instantiating the
## scene first and what this run needs to know is which scene to expect.
const NAMING_FLAGS := ["--root", "--boot", "--save"]


func _init() -> void:
	await _run()


func _run() -> void:
	var h := Harness.new()
	# Autoloads land a frame into a `--script` run and `launcher.gd` names three.
	await process_frame
	var scene: Node = load(LAUNCHER).instantiate()
	root.add_child(scene)
	for i in SETTLE_FRAMES:
		await process_frame

	var case := "every name a tool reaches by is still there, and still its class"
	h.begin(case)
	for name in SURFACE:
		var node := scene.get_node_or_null("%" + str(name))
		if not h.check("%%%s resolves" % name, node != null):
			continue
		h.check("  and is a %s" % SURFACE[name], node.is_class(str(SURFACE[name])),
			node.get_class())
	h.complete(case)

	if _game_named():
		_bypassed(h, scene)
	else:
		await _menu(h, scene)
	quit(h.finish("the launcher's reflective surface"))


func _game_named() -> bool:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		for flag in NAMING_FLAGS:
			if text == flag or text.begins_with(flag + "="):
				return true
	return false


## What a run that named a game asserts instead.
##
## Every one of these is something `_ready` does *after* the bypass returns, so
## finding any of them is the report that work has moved above it -- a theme
## load, an await, a list built "just to have it ready". The comment on
## `_named_on_command_line` says a menu in front of a named game breaks
## `director_paths.gd`'s promise that `--save <file>` is sufficient on its own.
## This is that promise, measured.
func _bypassed(h: Harness, scene: Node) -> void:
	var case := "a game named on the command line builds no menu at all"
	h.begin(case)
	print("  (a game was named, so this run asserts the bypass and not the menu)")
	var games := scene.get_node_or_null("%Games") as OptionButton
	var grid := scene.get_node_or_null("%Grid") as Control
	h.check("the title list was never filled", games != null and games.item_count == 0,
		"%d item(s)" % (games.item_count if games != null else -1))
	h.check("no tile was built", grid != null and grid.get_child_count() == 0,
		"%d tile(s)" % (grid.get_child_count() if grid != null else -1))
	h.check("the theme was never loaded", (scene as Control).theme == null)
	var router := root.get_node_or_null("/root/InputRouter")
	h.check("and the input router was left alone",
		router != null and bool(router.get("_enabled")))
	h.complete(case)


func _menu(h: Harness, scene: Node) -> void:
	# The shot tool types into a binding field by walking `%Bindings`'s children
	# and taking the first `LineEdit` in each, which no name protects.
	var case := "the binding rows are shaped the way the shot tool walks them"
	h.begin(case)
	var button := scene.get_node_or_null("%BindingsButton") as BaseButton
	if not h.check("there is a button to open them", button != null):
		h.complete(case)
		return
	button.emit_signal("pressed")
	var panel := scene.get_node_or_null("%Bindings") as Control
	for i in MEASURE_FRAMES:
		await process_frame
		if panel != null and panel.get_child_count() > 0:
			break
	if not h.check("rows were built", panel != null and panel.get_child_count() > 0,
		"%d row(s)" % (panel.get_child_count() if panel != null else 0)):
		h.complete(case)
		return
	var fields := 0
	for row in panel.get_children():
		for child in (row as Node).get_children():
			if child is LineEdit:
				fields += 1
				break
	h.check("every row has a LineEdit directly under it", fields == panel.get_child_count(),
		"%d field(s) for %d row(s)" % [fields, panel.get_child_count()])
	h.complete(case)

	case = "arrows and the D-pad have somewhere to go from every tile"
	h.begin(case)
	var grid := scene.get_node_or_null("%Grid") as GridContainer
	if not h.check("there is a tile grid", grid != null and grid.get_child_count() > 0,
		"%d tile(s)" % (grid.get_child_count() if grid != null else 0)):
		h.complete(case)
		return
	var dangling: Array[String] = []
	for node in grid.get_children():
		var tile := node as Control
		h.check("%s takes focus" % tile.name, tile.focus_mode == Control.FOCUS_ALL)
		for side in ["focus_neighbor_left", "focus_neighbor_right",
				"focus_neighbor_top", "focus_neighbor_bottom"]:
			var path: NodePath = tile.get(side)
			if not path.is_empty() and tile.get_node_or_null(path) == null:
				dangling.append("%s.%s" % [tile.name, side])
	h.check("no neighbour points at a node that is not there", dangling.is_empty(),
		", ".join(dangling))
	# The seam out of the grid: the bottom row has to reach the row of controls
	# under it, and that row has to reach Play, or a gamepad is stuck in the grid
	# with the button it came for two rows away.
	var last := grid.get_child(grid.get_child_count() - 1) as Control
	h.check("the last tile leads out of the grid",
		not last.focus_neighbor_bottom.is_empty()
			and last.get_node_or_null(last.focus_neighbor_bottom) != null)
	var aspect := scene.get_node_or_null("%Aspect") as Control
	h.check("and the stage-fit menu leads to Play",
		aspect != null and aspect.get_node_or_null(aspect.focus_neighbor_bottom)
			== scene.get_node_or_null("%Play"))
	h.complete(case)

	# `autoload/input_router.gd` marks the gamepad's A handled for every scene it
	# is enabled in, and the launcher switches it off so that A can press a button
	# here instead. Nothing on screen shows whether that call landed, and a
	# launcher that ignores the one button a gamepad has is exactly the failure
	# that reaches nobody until somebody unplugs a keyboard.
	case = "the gamepad's A is not being eaten by the preview's router"
	h.begin(case)
	# Through the tree and not by name. A `--script` tool is compiled before the
	# autoloads exist, so naming one here is a *compile* error in this file --
	# "Identifier not found: InputRouter" -- which reads as the autoload being
	# gone rather than as this script being early. `launcher.gd` may name it,
	# because a scene is loaded long after that point.
	var router := root.get_node_or_null("/root/InputRouter")
	if h.check("the router autoload is there to ask", router != null):
		h.check("and is off while the menu is up", not bool(router.get("_enabled")))
	h.complete(case)

	# `_build_flags` frees the previous row and builds a new one on every
	# selection, and `_focus_start` makes that happen twice before the first
	# frame anybody sees. `queue_free` alone lands at the end of the frame, so a
	# row that was only queued would still answer `get_children()` -- and the
	# focus map built from that list would wire arrows into buttons on their way
	# out. Title-agnostic: it asks whether any child is leaving, not how many
	# there are.
	case = "the edition row holds no button that is already on its way out"
	h.begin(case)
	var flags := scene.get_node_or_null("%Flags") as Control
	var orphans := 0
	if h.check("there is an edition row to look at", flags != null):
		for child in flags.get_children():
			if (child as Node).is_queued_for_deletion():
				orphans += 1
		h.check("every button in it is a live one", orphans == 0,
			"%d of %d queued" % [orphans, flags.get_child_count()])
	h.complete(case)

	case = "something holds focus before anybody touches anything"
	h.begin(case)
	var focused := scene.get_viewport().gui_get_focus_owner()
	h.check("a control has focus on open", focused != null,
		focused.name if focused != null else "")
	h.complete(case)

	await _resizes(h, grid)


## Windowed only, and it says so rather than passing on a window that never
## moved: headless honours `window_set_size` no more than it honours a repaint,
## so both readings would come back identical and the case would be asserting
## that a number equals itself.
##
## What it is for: `_fit_tiles` grows the tiles into whatever height the window
## did not need. Growing is provable from a cold start; the way back down is
## not, and a step that only ever added would leave a shrunk window holding
## tiles taller than the panel they are in. It did, and in both directions --
## the fix was to measure from the floor on every pass and to listen to the
## scroll region's own `resized` as well as the window's.
func _resizes(h: Harness, grid: GridContainer) -> void:
	if DisplayServer.get_name() == "headless":
		print("  (skipped: the tile-fit resize case needs a window this run has not got)")
		return
	var case := "the tiles give the height back when the window takes it away"
	h.begin(case)
	var grown := _tile_height(grid)
	await _resize(Vector2i(1280, 1100))
	var taller := _tile_height(grid)
	await _resize(Vector2i(1280, 620))
	var shorter := _tile_height(grid)
	h.check("a taller window makes them no shorter", taller >= grown,
		"%d -> %d" % [grown, taller])
	h.check("and a shorter one takes it back", shorter < taller,
		"%d -> %d" % [taller, shorter])
	h.complete(case)


func _tile_height(grid: GridContainer) -> int:
	return int((grid.get_child(0) as Control).size.y) if grid.get_child_count() > 0 else 0


## The same drop out of maximized `launcher_shot.gd` documents: a resize on a
## maximized window is ignored, so the mode has to go windowed first or every
## size asked for here is the size the window already had.
func _resize(to: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(to)
	root.content_scale_size = to
	for i in SETTLE_FRAMES * 2:
		await process_frame
