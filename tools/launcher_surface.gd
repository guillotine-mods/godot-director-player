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
## Preloaded and not reached through the scene: the boot check below asks what
## the launcher's own list layer answers, which is the layer `_on_play` copies
## from, rather than reaching into the built tiles for a value they never carry.
const TitleList := preload("res://scenes/launcher/title_list.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")

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

	# The table above is only as good as its completeness, and it is written by
	# hand: a toggle added to the QoL card and not to `SURFACE` is a control
	# `launcher_shot.gd` cannot reach, and the loop above cannot notice a name it
	# was never given. `bugs.md` 129 is the far side of the same gap --
	# `%MinigameSkip` sat in this table, in the scene and in `launcher.gd`'s
	# read/write for weeks after its only reader went with the renderer.
	#
	# **This guards the table, not the defect class.** "A toggle nothing reads"
	# cannot be gated from here without encoding which of the remaining toggles
	# are wired and which are disclosed-pending, and that list is a separate
	# subject with its own entry. What this asserts is narrower and still worth
	# having: the card and the table agree on which controls exist.
	#
	# Found by name and not by path, so re-parenting the card into a different
	# tab is not a failure. `owned = false`: the checkboxes are owned by the
	# scene root rather than by the card, so the default would find none of them
	# and the case would pass on an empty list -- which is why the count is
	# asserted beside the set.
	case = "the QoL card holds no toggle this table has never heard of"
	h.begin(case)
	var card := scene.find_child("AssistCard", true, false)
	if h.check("there is a QoL card to look at", card != null):
		var boxes := card.find_children("*", "CheckBox", true, false)
		var unlisted: Array[String] = []
		for node in boxes:
			if not SURFACE.has(str((node as Node).name)):
				unlisted.append(str((node as Node).name))
		h.check("it still holds toggles at all", not boxes.is_empty(),
			"%d checkbox(es)" % boxes.size())
		h.check("and every one of them is a name in SURFACE", unlisted.is_empty(),
			", ".join(unlisted))
	h.complete(case)

	_overrides(h, scene)

	if _game_named():
		_bypassed(h, scene)
	else:
		await _menu(h, scene)
	quit(h.finish("the launcher's reflective surface"))


## What `_on_play` may put in the overlay, which is a question about releases and
## not about tidiness.
##
## The overlay is laid over the shipped config, so a key that merely repeats a
## default is a live override of whatever that default becomes next. `v0.3.0-alpha`
## is where that was paid: the launcher wrote `enabled="auto"` on every Play from
## source, the release stamped `enabled="true"` into the config it ships, and every
## machine that had ever pressed Play overrode the release back to off -- no HUD,
## no SKIP, no toast, every F-key dead, and the Developer tab still there because
## it reads the tracked config alone.
##
## `_override` is static, so this asserts the rule in both of this file's modes
## rather than only the one that builds a menu. Reached through the instantiated
## `scene` and **not** through a `preload` of `launcher.gd`: that script names the
## `InputRouter` autoload, autoloads resolve at compile time, and a `--script`
## harness has none -- so preloading it failed to compile, took every dependent
## script with it, and turned this whole file red with five unrelated failures.
func _overrides(h, scene: Node) -> void:
	var case := "the overlay takes only what differs from the shipped config"
	h.begin(case)

	# The release-breaking case, in the direction that broke it: the shipped
	# config has moved to `true` and the switch is showing it, so the stale
	# `auto` underneath has to go rather than be rewritten.
	var shipped := ConfigFile.new()
	shipped.set_value("debug", "enabled", "true")
	var overlay := ConfigFile.new()
	overlay.set_value("debug", "enabled", "auto")
	scene._override(overlay, shipped, "enabled", "true", DebugKeys.AUTO)
	h.check("a stale value is erased once the switch agrees with the build",
		not overlay.has_section_key("debug", "enabled"),
		str(overlay.get_value("debug", "enabled", "<erased>")))

	# ...and the same call is what a phone has instead of a command line. Android
	# has no argv and no writable `res://`, so this erase is the only route from a
	# stale `enabled` back to the build's own answer that does not cost the
	# player every save.
	h.check("which is the whole recovery on a platform with no command line",
		DebugKeys.resolve_switch(overlay, true, []) == DebugKeys.AUTO,
		DebugKeys.resolve_switch(overlay, true, []))

	# A real override still survives, or the switch would be decorative.
	scene._override(overlay, shipped, "enabled", "false", DebugKeys.AUTO)
	h.check("a value that differs is written", overlay.get_value("debug", "enabled", "") == "false",
		str(overlay.get_value("debug", "enabled", "<missing>")))

	# Echoing is what the launcher did, and it did it from source, where the
	# tracked file says `auto` and the switch reads `auto` back off the merge.
	var from_source := ConfigFile.new()
	from_source.set_value("debug", "enabled", "auto")
	var fresh := ConfigFile.new()
	scene._override(fresh, from_source, "enabled", "auto", DebugKeys.AUTO)
	h.check("a Play from source pins nothing at all",
		not fresh.has_section_key("debug", "enabled"),
		str(fresh.get_value("debug", "enabled", "<absent>")))

	# Case and whitespace, because `resolve_switch` reads the switch stripped and
	# lowered and `OS.find_keycode_from_string` reads a key name the same way: an
	# echo in different clothes is still an echo.
	var loud := ConfigFile.new()
	loud.set_value("debug", "enabled", "auto")
	scene._override(loud, from_source, "enabled", "  AUTO ", DebugKeys.AUTO)
	h.check("a differently-cased echo is still an echo",
		not loud.has_section_key("debug", "enabled"))

	# A tracked file that says nothing about a key is not the empty string: the
	# comparison has to be against the value `DebugKeys` would actually use.
	var silent := ConfigFile.new()
	var bound := ConfigFile.new()
	bound.set_value("debug", "boxes", "F1")
	scene._override(bound, silent, "boxes", str(DebugKeys.DEFAULTS["boxes"]),
		str(DebugKeys.DEFAULTS["boxes"]))
	h.check("a binding equal to the shipped default is erased",
		not bound.has_section_key("debug", "boxes"))
	scene._override(bound, silent, "boxes", "F4", str(DebugKeys.DEFAULTS["boxes"]))
	h.check("and a rebound key is kept", bound.get_value("debug", "boxes", "") == "F4",
		str(bound.get_value("debug", "boxes", "<missing>")))

	# An empty value unbinds a command outright, which is a deliberate statement
	# and differs from every default, so it must survive.
	scene._override(bound, silent, "quit", "", str(DebugKeys.DEFAULTS["quit"]))
	h.check("an unbind is an override and is kept",
		bound.has_section_key("debug", "quit")
			and str(bound.get_value("debug", "quit", "<missing>")) == "")

	# Everything above exercises `_override` and would stay green through the one
	# regression that matters: `_on_play` going back to writing `[debug]` keys
	# itself. That is the shape `porting-fidelity-verification` warns about -- an
	# assertion that passes while proving nothing -- so the wiring is asserted too.
	#
	# Read as text because there is no cheaper way to ask. `_on_play` writes the
	# real `user://` overlay and then changes scene, so calling it here would edit
	# a human's config to answer a question about a call site.
	#
	# One site is correct and is `_override`'s own write. Two means a caller has
	# gone around it.
	var source := FileAccess.get_file_as_string("res://scenes/launcher/launcher.gd")
	var direct := source.count('set_value("debug"')
	h.check("and `_on_play` still routes every debug key through it", direct == 1,
		"%d site(s) in launcher.gd write a [debug] key directly" % direct)

	h.complete(case)


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
	# The footer names the build a bug report will quote, and it is assembled from
	# a Latin version inside an RTL Hebrew sentence -- which is a shape that
	# renders wrong by default. `0.0.0-dev` ends in a bidi-neutral hyphen, so the
	# algorithm resolved it against the *next* strong run and pulled the digit out
	# of `5 משחקים` into it: the line read `גרסה 0.0.0-5` with a stray `dev`
	# beside the Godot version. Two facts, each corrupted by the other's
	# neighbour, and every test passed while it happened -- the string was right
	# and only its rendering was not.
	#
	# So the assertion is on the substring staying contiguous, which is what the
	# U+2066/U+2069 isolates in `launcher.gd:_ltr` buy. It cannot see the glyph
	# order, but it does fail if someone removes the isolates and reformats the
	# line around them.
	var case := "the footer names the build"
	h.begin(case)
	var build := scene.get_node_or_null("%Build") as Label
	if h.check("there is a build line", build != null):
		var text := build.text
		h.check("it is not empty", text.strip_edges() != "", text)
		var version := str(ProjectSettings.get_setting("application/config/version", ""))
		h.check("the project version appears in it, unbroken",
			version != "" and text.contains(version), "%s in %s" % [version, text])
		# The isolates are what keep it unbroken; asserting the version alone
		# would still pass on the mangled line if the digits happened to line up.
		# The detail is printed on a pass as well as a failure, so it states what
		# was found rather than asserting a conclusion. "U+2066/U+2069 absent"
		# sitting under an `ok` line reads as a contradiction.
		var lri := text.contains(char(0x2066))
		var pdi := text.contains(char(0x2069))
		h.check("the Latin runs are bidi-isolated", lri and pdi,
			"LRI %s, PDI %s" % ["present" if lri else "absent",
				"present" if pdi else "absent"])
	h.complete(case)

	# The shot tool types into a binding field by walking `%Bindings`'s children
	# and taking the first `LineEdit` in each, which no name protects.
	case = "the binding rows are shaped the way the shot tool walks them"
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

	# The boot override is the one developer field whose *default* decides whether
	# a title launches, because `_on_play` treats anything in it as an override of
	# the selected title's own boot container -- and the developer tab is on by
	# default in a run from source, so a seeded value is nobody's opt-in.
	#
	# It used to be filled from the merged config, which is `strtgame.dir`. Four of
	# the five Director titles boot exactly that, so the fault was invisible in
	# four places and total in the fifth: selecting Rating, whose boot is
	# `mainmenu.dir`, and pressing Play wrote `root = res://games/rating` with
	# `boot_movie = strtgame.dir` and reached "no such container". The title could
	# not be started from this screen at all.
	#
	# The placeholder is asserted with the text, because "empty" is only correct
	# while the screen still says what empty *means*. A blank field under no
	# placeholder reads as a control that failed to load rather than one that
	# defers, and the next person to see it would helpfully fill it back in.
	case = "the boot override defers instead of overriding by default"
	h.begin(case)
	var boot := scene.get_node_or_null("%Boot") as LineEdit
	if h.check("there is a boot field to look at", boot != null):
		h.check("it opens empty, so Play uses the selected title's own boot",
			boot.text == "", "text=%s" % ("<empty>" if boot.text == "" else boot.text))
		h.check("and the placeholder says that is what empty means",
			boot.placeholder_text != "")
	# Both halves, because the empty field alone asserts the *cause* that was
	# removed and not the *effect* that was reported. What a player saw was a
	# title that would not start, so the effect is what is measured below:
	# `_on_play`'s own composition -- the field when it holds something, the
	# selected title's boot when it does not -- has to come out as each title's
	# own container.
	#
	# Composed here rather than reached by pressing Play, which writes the
	# overlay and changes scene: two side effects on the machine running the
	# harness, for an answer that is one `if` wide. The `if` is duplicated from
	# `_on_play` and that is the cost -- so it is written as the same expression,
	# and a change to the rule that is not mirrored here shows up as this check
	# passing while the screen is broken. It caught the seeded field: with the
	# seed back in place, Rating composes `strtgame.dir` and this fails naming
	# it, which is the sentence the bug report was.
	var mismatched: Array[String] = []
	var override := str(boot.text).strip_edges() if boot != null else ""
	for entry in TitleList.build():
		var row := TitleList.default_root(entry) as Dictionary
		# A Godot-project title carries a scene instead of a boot container, and
		# `_on_play` returns before any of this for it. It is not a title with a
		# missing boot; it is a title with no boot to miss.
		if str(row.get("scene", "")) != "":
			continue
		var mine := str(row.get("boot", ""))
		var composed := override if override != "" else mine
		if composed != mine or mine == "":
			mismatched.append("%s boots %s, Play would send %s"
				% [row.get("name", ""), mine, composed])
	h.check("and every title would start on its own boot container",
		mismatched.is_empty(), ", ".join(mismatched))
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
