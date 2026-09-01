extends Control
## The screen that picks a game, before anything is loaded.
##
## It writes `user://director_game.local.cfg` and never the tracked file. That
## is the whole point: `director_game.cfg` is tracked, so a screen that edited
## it in place would produce exactly the merge conflicts it exists to remove --
## and in an export it could not, because `res://` is inside the PCK.
##
## **A run that names a game on the command line plays straight through.**
## `director_paths.gd` documents `godot --path . -- --save <file>` as sufficient
## on its own, and a menu in front of it breaks that. A bare run shows the menu,
## and an Android run -- which has no argv -- always does.
##
## The look is `launcher_theme.gd` and the tiles are `game_tile.gd`; this file
## is the wiring between them and the config layer, and holds no colours and no
## metrics of its own.

const GameConfig := preload("res://director/game_config.gd")
const TitleList := preload("res://scenes/launcher/title_list.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const BindingRules := preload("res://scenes/launcher/binding_rules.gd")
const LauncherTheme := preload("res://scenes/launcher/launcher_theme.gd")
const GameTile := preload("res://scenes/launcher/game_tile.gd")
const KeyAffordance := preload("res://scenes/preview/key_affordance.gd")

const PREVIEW_SCENE := "res://scenes/director_preview.tscn"

## Emoji are not in the project's font. `Open Sans SemiBold` carries Hebrew and
## Cyrillic but no emoji block at all, measured with `has_char` on 4.7.1, so a
## flag label needs the platform's emoji font as a fallback. A platform whose
## emoji font declines regional-indicator pairs -- Windows does -- draws the two
## letters instead, which is `IL`, `US`, `RU`: the label a text-only design
## would have picked, so there is nothing to fall back to.
const EMOJI_FONTS := ["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"]

const ASPECTS := ["native_4_3", "wide_16_9", "ultra_21_9", "stretch_fill"]

## What each aspect is called on screen, while `ASPECTS` stays the list of
## values `[display] aspect` is written from. Keyed by the value rather than
## laid out parallel to `ASPECTS`, because a parallel list is one reorder away
## from labelling every entry as its neighbour and nothing would say so: the
## menu would read fine and write the wrong mode.
const ASPECT_LABELS := {
	"native_4_3": "4:3, כפי שנוצר",
	"wide_16_9": "16:9 מסך רחב",
	"ultra_21_9": "21:9 רחב במיוחד",
	"stretch_fill": "מתיחה למסך המלא",
}

const CODEPAGES := ["", "mac_hebrew", "windows_1255"]
const DEBUG_VALUES := [DebugKeys.AUTO, DebugKeys.ON, DebugKeys.OFF]

## The page stops widening here and puts the rest in the margins.
##
## The number bites less often than it looks, and it is worth writing down why.
## `project.godot` stretches a 1280x720 canvas with `aspect = expand`, so the
## scale is `min(window.x / 1280, window.y / 720)` and the layout is measured in
## a space that is *never smaller* than 1280x720 and only grows on whichever
## axis has room to spare. A maximized 3024x1834 window is therefore still 1280
## wide to everything below, and the cap does nothing. It is a 21:9 display that
## reaches it -- 3440x1440 scales by 2.0 and reports 1720 -- and there four
## tiles and a hint line would take 400px each.
const PAGE_WIDTH := 1180
const PAGE_GUTTER := 28
const GRID_SEPARATION := 16
const MAX_COLUMNS := 4

@onready var _games: OptionButton = %Games
@onready var _flags: HBoxContainer = %Flags
@onready var _aspect: OptionButton = %Aspect
@onready var _play: Button = %Play

var _entries: Array[Dictionary] = []
var _tiles: Array[Button] = []
var _root := ""
var _boot := ""
## A scene inside a mounted pack, for a title that is a Godot project rather
## than a Director corpus. Empty for all six disc titles.
var _scene := ""
var _title := ""
var _binding_fields: Dictionary = {}
## command -> the label beside its field, so a row can say what is wrong with it
## where the person typing is looking.
var _binding_problems: Dictionary = {}
## command -> the problem string, absent when the field is valid.
##
## **The validity of a binding field is stored here and not read back off the
## field.** It used to be read back: `_validate_field` wrote a red `modulate` and
## `_refresh_play` asked whether `modulate != Color.WHITE`, which made a *visual*
## property the data channel. That works exactly until something else has a
## reason to tint a `LineEdit` -- a theme, a hover state, a focus ring, a
## disabled look -- and then Play's enabled state is decided by whatever last
## touched the colour. It fails silently and in both directions: a Play that
## never enables, or a Play that launches with a binding the preview will refuse.
var _invalid: Dictionary = {}
## Set once in `_ready`. `_on_play` reads this rather than calling
## `_developer_visible()` again, for the reason `_refresh_play`'s own comment
## gives about a second reason to disable Play: two call sites computing the
## same answer is two chances for them to compute it differently.
var _show_developer := false


func _ready() -> void:
	if _named_on_command_line():
		_launch()
		return
	theme = LauncherTheme.build()
	# The gamepad's A is `ui_accept` and is also the preview's `click`, and
	# `autoload/input_router.gd` marks `click` handled in every scene it is
	# alive in -- which includes this one, where nothing wants a stage click.
	# Left alone, A never reaches a button and a launcher built for a D-pad
	# cannot be pressed with one. `_redrive_autoloads` hands it back on the way
	# into the movie.
	#
	# That is safe only while **Play and Quit are the only ways off this
	# screen**, which they are: the two `_launch()` call sites are the
	# command-line bypass above -- which returns before this line -- and
	# `_on_play`, which re-drives first. A "back" affordance added later that
	# changes scene without going through `_on_play` would leave the router off
	# and the movie deaf to the gamepad, and nothing would report it.
	InputRouter.set_enabled(false)
	_entries = TitleList.build()
	_fill_build_line()
	_fill_games()
	_fill_aspect()
	var tabs := %Tabs as TabContainer
	var developer := %Developer as Control
	# A `TabContainer` labels each tab with its child's *node name*, and those are
	# `Player` and `Developer` -- which the focus map, `launcher_surface` and every
	# `%`-path in this file are written against, so they are not renameable. The
	# titles are set here instead, which is the one place where what the screen
	# says and what the code calls it are allowed to differ.
	tabs.set_tab_title(0, "נגן")
	tabs.set_tab_title(developer.get_index(), "מפתחים")
	_show_developer = _developer_visible()
	# Not `developer.visible = _show_developer`: a `TabContainer` watches every
	# child's `visibility_changed` signal and jumps `current_tab` to whichever
	# one just turned visible, so setting it directly here would open the
	# launcher on the Developer tab instead of Player. `set_tab_hidden` alone
	# adds or removes the tab from the bar without touching which one is
	# current; the child's own `visible` stays under the container's control
	# and only changes when a click -- or this same signal, later -- picks it.
	tabs.set_tab_hidden(developer.get_index(), not _show_developer)
	if _show_developer:
		_fill_developer()
		%BindingsButton.pressed.connect(_on_bindings_pressed)
	_games.item_selected.connect(_on_game_selected)
	_play.pressed.connect(_on_play)
	%Quit.pressed.connect(_on_quit)
	resized.connect(_reflow)
	# And the scrolling region separately, because the two do not settle on the
	# same frame. The window's `resized` arrives while the containers inside it
	# still hold last frame's rects, so a fit computed from it reads a viewport
	# that is mid-move -- measured: taking the window to 1280x1100 left the
	# tiles on their minimum with 288px of room going spare, because nothing
	# fired again once the panel had actually grown. The region's own signal is
	# what fires then.
	(%PlayerScroll as Control).resized.connect(_fit_tiles, CONNECT_DEFERRED)
	_reflow()
	if _entries.size() > 0:
		_select_game(0)
	_focus_start()


## `--root`, `--boot` and `--save` each name a game, and each is meant to be
## sufficient without a menu.
func _named_on_command_line() -> bool:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		for flag in ["--root", "--boot", "--save"]:
			if text == flag or text.begins_with(flag + "="):
				return true
	return false


## What is running and what it found, which is the first thing anybody filing a
## report has to be asked for.
func _fill_build_line() -> void:
	var roots := 0
	for entry in _entries:
		roots += (entry.get("roots", []) as Array).size()
	%Build.text = "גרסה %s · Godot %s · %s, %s על הדיסק" % [
		_ltr(_build_version()),
		_ltr(str(Engine.get_version_info().get("string", ""))),
		_counted(_entries.size(), "משחק", "משחקים"),
		_counted(roots, "ספרייה", "ספריות")]


## Fences a Latin/numeric run so the surrounding Hebrew cannot reorder it.
##
## **This is not decoration; without it the line renders wrong.** `0.0.0-dev` in
## an RTL paragraph ends with a hyphen, which is bidi-neutral, so the algorithm
## resolved it against the next strong run and pulled the digit out of
## `5 משחקים` into it: the footer read `גרסה 0.0.0-5` with a stray `dev` sitting
## beside the Godot version. Two separate facts, each corrupted by the other's
## neighbour. Seen in `tools/launcher_shot.gd` output, not reasoned about --
## reading the format string tells you nothing about this.
##
## U+2066/U+2069 (isolate rather than embed) is the current Unicode advice: an
## isolate also stops the run from affecting how the text *around* it resolves,
## which is exactly the direction the damage travelled here.
##
## Written as escapes because Godot's parser refuses the literal characters:
## "Invisible text direction control character present in the string, escape it".
## That is a good refusal -- pasted literally they are invisible in every editor
## and in every diff.
static func _ltr(text: String) -> String:
	return "\u2066%s\u2069" % text


## The build the player is actually running, for a bug report to quote.
##
## `application/config/version` rather than anything in `export_presets.cfg`: the
## presets are read at BUILD time and are invisible here, so an Android
## versionName or a macOS `short_version` cannot be asked for at runtime.
## `tools/ci/stamp_version.sh` writes this one as `<tag>+<run number>`, and the
## run number is what separates two builds of the same tag -- without it a
## screenshot of this line cannot identify which workflow run produced the binary.
##
## The tracked value is `0.0.0-dev`, so a run from source says so rather than
## impersonating a release. An empty or missing setting reports `dev` for the same
## reason: no version at all must not render as `גרסה  ·`, which reads as a
## rendering bug rather than as "this was not stamped".
static func _build_version() -> String:
	var raw := str(ProjectSettings.get_setting("application/config/version", ""))
	return raw if raw.strip_edges() != "" else "dev"


## "1 titles" is the giveaway that nobody ever ran the screen with one.
##
## Both forms are passed in rather than a suffix being bolted on, because Hebrew
## does not build its plural by appending anything -- `משחק` becomes `משחקים` and
## `ספרייה` becomes `ספריות`, and no rule the caller could apply covers both.
static func _counted(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## How wide the page is allowed to get, and how many tiles fit across it.
##
## Both are answers to the window rather than to the design, so they are
## recomputed on every resize and nowhere else. `PAGE_WIDTH` says which windows
## actually reach the cap; the column count is the half that moves more often,
## because the stretch mode grows the logical space on the wide axis and a 21:9
## window has room for a fifth tile that is not there and a 4:3 one has a third
## of a screen of height the grid has nothing to do with.
func _reflow() -> void:
	var gutter := maxi(PAGE_GUTTER, int((size.x - PAGE_WIDTH) * 0.5))
	%Page.add_theme_constant_override("margin_left", gutter)
	%Page.add_theme_constant_override("margin_right", gutter)
	var inner := size.x - gutter * 2.0
	var fits := int((inner + GRID_SEPARATION) / float(GameTile.MIN_WIDTH + GRID_SEPARATION))
	# Height decides too, and it is the half a width-only rule gets wrong here.
	# The stretch mode hands a 4:3 window a 1280x960 space -- 800x600 is exactly
	# that -- which is a whole extra row of height with nothing in it, and four
	# tiles across leave it as a band of empty card. Fewer columns spend it on a
	# second row of tiles instead. The threshold sits above 16:10, because 80
	# spare pixels are not a row and splitting the grid for them would trade one
	# gap for two half-empty ones.
	var squarish := size.y > size.x * 0.70
	%Grid.columns = clampi(mini(fits, 2 if squarish else MAX_COLUMNS), 1, MAX_COLUMNS)
	_link_focus()
	_fit_tiles.call_deferred()


## The tiles take whatever height the window did not need, up to a limit.
##
## This is what closes the hole the old screen had under its controls: the tab
## panel fills the window whether or not there is anything to put in it, so
## either the content grows into it or it stays a lit rectangle with a gap in
## the bottom half. Growing the row is the honest one -- the tiles are the
## content -- and it costs one measurement rather than a second layout mode.
##
## **Measured from the floor every time, not from wherever the last pass left
## them.** It used to add the leftover to the current height, which is the same
## arithmetic and is not the same function: `resized` fires several times
## through a window drag and some of those frames report a viewport that is
## mid-move, so one bad reading became the new baseline and stayed. That is not
## a theory -- taking the window from 1280x720 to 1280x1100 shrank the tiles to
## their minimum and going back to 620 grew them, which is both directions
## wrong, and `tools/launcher_surface.gd` now asserts the pair. Resetting first
## makes the answer a function of the window alone, so a bad frame is corrected
## by the next one instead of kept.
##
## `%Body`'s minimum counts the tiles, so with them on the floor the slack
## divided over the rows is exactly what each row has room to grow by. Deferred
## because the sizes it reads are the ones this frame's layout produced.
func _fit_tiles() -> void:
	if _tiles.is_empty():
		return
	var columns := maxi((%Grid as GridContainer).columns, 1)
	var rows := ceili(_tiles.size() / float(columns))
	for tile in _tiles:
		tile.custom_minimum_size.y = GameTile.MIN_HEIGHT
	# `HEADROOM` off the slack, because spending all of it lands the content
	# *exactly* on the boundary and a pixel of rounding anywhere then raises a
	# scrollbar -- which takes width, re-lays out, and is the thing this whole
	# function exists to avoid. Found by translating the stage-fit hint: the
	# Hebrew wraps to two lines where the English took three, the extra slack went
	# into the tiles, and the grid started scrolling again on a window where it
	# had not before.
	const HEADROOM := 8
	var slack := (%PlayerScroll as Control).size.y \
		- (%Body as Control).get_combined_minimum_size().y - HEADROOM
	# The floor is `FLOOR_HEIGHT` rather than `MIN_HEIGHT`, so a negative slack
	# shrinks the tiles instead of producing a scrollbar. Five titles make a
	# second row, and on a short window two rows at `MIN_HEIGHT` do not fit --
	# the grid scrolled, and everything below it went with it.
	var height := clampi(GameTile.MIN_HEIGHT + int(slack / rows),
		GameTile.FLOOR_HEIGHT, GameTile.MAX_HEIGHT)
	for tile in _tiles:
		tile.custom_minimum_size.y = height


func _fill_games() -> void:
	_games.clear()
	for entry in _entries:
		_games.add_item(str(entry["title"]))
	# One game is not a choice. A single-title build shows no list at all, which
	# is what lets an Android export carry one game without a decision here.
	#
	# It still says which game, though, and that is not the same thing as a list
	# of one: a picker with a single row invites a decision that does not exist,
	# and the alternative -- taking the grid away and leaving the space it held
	# -- was a 300px hole above the aspect menu with nothing anywhere naming the
	# title. `%Solo` is the identity without the affordance, in the grid's place
	# and in the grid's type.
	%Titles.visible = _entries.size() > 1
	(%Solo as Control).visible = _entries.size() == 1
	_games.selected = 0
	_build_tiles()


## The tiles are the view; **`%Games` is still the record.** It is a hidden
## `OptionButton` and that reads like a leftover, so: a combo box is a bad way to
## show a shelf of titles and a perfectly good way to hold which one is chosen, and
## every path into `_on_game_selected` goes through `item_selected` on it. That
## is the same argument `_refresh_play` and `_invalid` make twice already --
## one owner per answer -- applied to the selection instead of to Play's
## enabled state or to a field's validity.
func _select_game(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_games.selected = index
	_games.item_selected.emit(index)


## Builds nothing when the grid is hidden, so that `_tiles` always means "the
## tiles somebody can see". A single-title build would otherwise hold four
## invisible buttons that `_focus_start` would hand focus to and `_link_focus`
## would wire arrows into, both of them silently.
func _build_tiles() -> void:
	for child in %Grid.get_children():
		%Grid.remove_child(child)
		child.queue_free()
	_tiles.clear()
	if not (%Titles as Control).visible:
		return
	var flags := _emoji_font()
	for i in _entries.size():
		var tile := GameTile.make(_entries[i], flags)
		tile.focus_entered.connect(_select_game.bind(i))
		tile.pressed.connect(_on_tile_pressed.bind(i))
		tile.gui_input.connect(_on_tile_gui_input.bind(i))
		%Grid.add_child(tile)
		_tiles.append(tile)


## Focus selects, and so does a press. Playing is `Play`, or a double click.
##
## Focus-selects is the dashboard reading of a D-pad rather than a form's: the
## tile the stick is on *is* the selection, so there is nothing left for a
## second press to choose, and `ui_accept` can go to Play without a rule about
## where focus happens to be sitting.
##
## A press used to play as well, and that was the fault: every other control on
## this screen describes the *selected* title -- the flag row, Stage Fit, the
## whole Developer tab -- so a click that both selected and launched left no way
## to reach any of them. It also hid a bug rather than causing one, which is how
## it was found: the 3D title had Play disabled for the wrong reason, so
## `if not _play.disabled` was false and clicking it merely selected. Fixing
## Play made it launch on click like the other four, and the inconsistency
## people had learned turned out to be the correct behaviour all along.
## A tile press picks a title. It does **not** play it.
##
## It used to do both, which made every other control on the screen unreachable
## without launching something: the flag row, Stage Fit and the whole Developer
## tab all describe the *selected* title, and the only way to select one was a
## click that immediately left the screen.
##
## Playing is `Play`, or a double click on the tile -- see `_on_tile_gui_input`.
func _on_tile_pressed(index: int) -> void:
	_select_game(index)


## The fast path back: double click a tile to pick and play in one gesture.
##
## On `gui_input` rather than on the `pressed` signal, because a `Button` reports
## that it was pressed and not how many times -- `double_click` lives on the
## event. `_select_game` runs first so a double click on a tile that was not
## selected still plays *that* title rather than the previous one.
##
## Mouse only, and deliberately so. A keyboard or gamepad reaches the tile
## through focus and `ui_accept`, which is a single press with no double form;
## those paths press `Play`, which is why it stays the one control that always
## launches.
func _on_tile_gui_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.double_click or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_select_game(index)
	if not _play.disabled:
		_on_play()


func _fill_aspect() -> void:
	_aspect.clear()
	for name in ASPECTS:
		_aspect.add_item(str(ASPECT_LABELS.get(name, str(name))))
	var current := str(GameConfig.merged().get_value("display", "aspect", "native_4_3"))
	_aspect.selected = maxi(ASPECTS.find(current), 0)


## Whether the developer tab is there at all.
##
## **From the tracked file, never from the merged value**, and that is a
## deliberate exception to `debug_keys.gd`'s one-answer-per-process rule. The
## tab contains the control that sets `[debug] enabled`, so a tab whose
## visibility read the overlay would close the door behind itself: set it false
## and the control that would set it back is gone. `--debug-ui on` recovers that
## wherever there is a command line, which is every desktop run and now the
## Windows Desktop export too -- `export_presets.cfg` grew a second, runnable
## preset in `c0a7c02e`, and the line this replaces still said Android was the
## only one. Android is the case the exception is really for: it has no argv at
## all, so there the only way back is clearing the app's data.
##
## The overlay may still turn the debug *layer* off -- the bindings, the boxes,
## the HUD. It just cannot hide its own door.
##
## The parsing itself lives in `DebugKeys`, not here. It used to be copied --
## matching `--debug-ui=on` only, and missing the documented `--debug-ui on`
## space form that `DebugKeys.resolve_switch` already accepted -- which meant
## the one command-line recovery this comment promises did not exist in code.
## `DebugKeys.enabled_for()` is the same resolution `enabled()` uses, asked of a
## caller-supplied config instead of the merged one, so this and the debug
## layer itself can never disagree about what a flag or a value means.
func _developer_visible() -> bool:
	return DebugKeys.enabled_for(GameConfig.tracked())


## Seeds the developer tab's controls from the merged config, because these are
## what the run will actually use.
func _fill_developer() -> void:
	var cfg := GameConfig.merged()
	# **Left empty, and not seeded from the config.** The placeholder says what
	# the field means -- empty is "whatever the selected game opens" -- and
	# `_on_play` treats anything typed here as an override of the *selected
	# title's* boot container. Seeding it made every launch an override of a
	# value the person had not chosen, and the value it seeded with was
	# `[game] boot_movie` from the tracked file: `strtgame.dir`.
	#
	# Four of the five Director titles boot `strtgame.dir`, so it looked
	# harmless for years. Rating boots `mainmenu.dir`, and selecting Rating and
	# pressing Play wrote `root = res://games/rating` with `boot_movie =
	# strtgame.dir` and reached `no such container` -- the title was not
	# launchable from this screen at all, and the developer tab is on by default
	# in a run from source, so that was every run.
	#
	# It also fed itself: the seed came from the *merged* config, which includes
	# the overlay this screen wrote last time, so one launch of any title pinned
	# its boot container onto the next.
	%Boot.placeholder_text = "ריק: מה שהמשחק הנבחר פותח"
	%Codepage.clear()
	for name in CODEPAGES:
		# The codepage names themselves stay as they are: `mac_hebrew` is the value
		# written into the config and the string the engine matches on, so a
		# translated one would be a different setting wearing the same label.
		%Codepage.add_item("ברירת המחדל של המנוע (בתים כנקודות קוד)" if name == "" else name)
	%Codepage.selected = maxi(CODEPAGES.find(str(cfg.get_value("game", "codepage", ""))), 0)
	%Debug.clear()
	for name in DEBUG_VALUES:
		%Debug.add_item(name)
	%Debug.selected = maxi(DEBUG_VALUES.find(
		str(cfg.get_value("debug", "enabled", DebugKeys.AUTO)).strip_edges().to_lower()), 0)
	%TouchControls.clear()
	for name in KeyAffordance.SWITCH_VALUES:
		%TouchControls.add_item(name)
	%TouchControls.selected = maxi(KeyAffordance.SWITCH_VALUES.find(
		str(cfg.get_value("qol", KeyAffordance.CONFIG_KEY,
			KeyAffordance.AUTO)).strip_edges().to_lower()), 0)
	%HotspotHints.button_pressed = bool(cfg.get_value("qol", "hotspot_hints", false))
	%EdgeHotspots.button_pressed = bool(cfg.get_value("qol", "expand_edge_hotspots", true))
	%EnhancedGraphics.button_pressed = bool(cfg.get_value("qol", "enhanced_graphics", false))
	%CursorSpeed.value = float(cfg.get_value("qol", "cursor_speed", 420.0))
	%CursorSpeed.value_changed.connect(_on_cursor_speed_changed)
	_on_cursor_speed_changed(%CursorSpeed.value)
	_ring_focus(%CursorSpeed, %SpeedRing)


func _on_cursor_speed_changed(value: float) -> void:
	%CursorSpeedValue.text = "%d px/s" % int(value)


## `Slider` is the one focusable control on this screen the theme cannot give a
## ring to: 4.7 gives it styleboxes for its track and its grabber and none for
## focus, so there is no theme entry to fill in. The ring is the panel behind
## it instead, swapped on the slider's own focus signals.
func _ring_focus(control: Control, ring: PanelContainer) -> void:
	ring.add_theme_stylebox_override("panel", LauncherTheme.blank())
	control.focus_entered.connect(func() -> void:
		ring.add_theme_stylebox_override("panel", LauncherTheme.focus_ring()))
	control.focus_exited.connect(func() -> void:
		ring.add_theme_stylebox_override("panel", LauncherTheme.blank()))


func _on_bindings_pressed() -> void:
	if %Bindings.visible:
		return
	# The third check reads every title's scripts, which is seconds. Say so on
	# the control that was pressed rather than freezing it with no explanation --
	# the status line beside it now belongs to whichever key is wrong, and a
	# progress message there would be the one place a person is not looking.
	%BindingsButton.disabled = true
	%BindingsButton.text = "Reading what the games test…"
	await get_tree().process_frame
	BindingRules.measure()
	%BindingsButton.text = "Edit preview keys…"
	_build_bindings()
	%Bindings.visible = true
	# Eighteen rows open below the fold of a card that was already the tallest
	# thing on the tab, so the button answers a press by showing what it built
	# rather than by scrolling nothing. The *first row* and not the panel: the
	# panel is taller than the viewport, and `ensure_control_visible` asked to
	# show all of it scrolls to its last row instead of its first. One frame
	# first, because the rows have no size until the container has laid them out.
	await get_tree().process_frame
	(%Scroll as ScrollContainer).ensure_control_visible(%Bindings.get_child(0) as Control)


## One row per binding: the command, the key it is on, and the room for what is
## wrong with it.
##
## The row stays a plain `HBoxContainer` holding a `LineEdit`, and the problem
## label goes *after* the field rather than before it, because
## `tools/launcher_shot.gd --bad` finds the field to type into by walking
## `%Bindings`'s children and taking the first `LineEdit` in each. That is a
## structural dependency and not a named one, so it does not show up in the list
## of `unique_name_in_owner` names the tool otherwise reaches by.
func _build_bindings() -> void:
	var cfg := GameConfig.merged()
	for command in DebugKeys.DEFAULTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = str(command)
		label.custom_minimum_size = Vector2(190, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var field := LineEdit.new()
		field.text = str(cfg.get_value("debug", command, DebugKeys.DEFAULTS[command]))
		field.custom_minimum_size = Vector2(170, 40)
		field.placeholder_text = "unbound"
		field.text_changed.connect(_on_binding_changed.bind(str(command)))
		var problem := Label.new()
		problem.theme_type_variation = "Note"
		problem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		problem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		row.add_child(field)
		row.add_child(problem)
		_binding_fields[str(command)] = field
		_binding_problems[str(command)] = problem
		%Bindings.add_child(row)


## The three checks, in the order that gives the most useful message: a name
## that is not a key first, then the key that is already taken, then the key a
## game wants. Records the verdict in `_invalid`, which `_refresh_play` reads,
## marks the field, and returns the message so a caller can show it.
func _validate_field(command: String) -> String:
	var field := _binding_fields[command] as LineEdit
	var name := str(field.text).strip_edges()
	var problem := ""
	if name == "":
		problem = ""  # Unbinding is legal, and is how a game gets a key back.
	elif BindingRules.named(name) == KEY_NONE:
		problem = "'%s' אינו שם של מקש" % name
	else:
		var current: Dictionary = {}
		for other in _binding_fields:
			current[other] = str((_binding_fields[other] as LineEdit).text).strip_edges()
		var clash := BindingRules.collision(current, command, name)
		if clash != "":
			problem = "%s כבר יושב על %s" % [clash, name]
		else:
			var claimed := BindingRules.claimed_by(name)
			var typed := BindingRules.typed_in(name)
			if not claimed.is_empty():
				problem = "%s הוא keyCode שנבדק על ידי %s" % [name, ", ".join(claimed)]
			elif not typed.is_empty():
				problem = "%s מקליד תו שנבדק על ידי %s" % [name, ", ".join(typed)]
	if problem == "":
		_invalid.erase(command)
	else:
		_invalid[command] = problem
	_mark_field(command, problem)
	return problem


## How a field says it is wrong, in one place so that restyling it is one edit
## and not a hunt. Nothing reads this back -- `_invalid` is the record -- which
## is what let it stop being a `modulate`. The tint the comment above once
## described was exactly the collision the comment on `_invalid` predicts from
## the other side: it dimmed the placeholder and the caret along with the
## border, and it fought the theme's own `LineEdit` styles for the same
## property. A stylebox and a line of text say it instead, and say *what*.
func _mark_field(command: String, problem: String) -> void:
	var field := _binding_fields[command] as LineEdit
	(_binding_problems[command] as Label).text = problem
	if problem == "":
		field.remove_theme_stylebox_override("normal")
		field.remove_theme_stylebox_override("focus")
		return
	field.add_theme_stylebox_override("normal", LauncherTheme.field_wrong(false))
	field.add_theme_stylebox_override("focus", LauncherTheme.field_wrong(true))


## Retyping one field can clear -- or create -- a collision on another: binding
## `quick_save` onto a key `boxes` already holds turns `boxes` red, and it takes
## a second pass over `boxes` to turn it white again once `quick_save` moves
## off that key, because `boxes`'s own text never changed. So every field is
## revalidated here, not just the one whose signal fired, and `_refresh_play`
## -- the single owner of Play's enabled state -- is asked to look again after.
##
## The status line carries the *count* and not the message. It used to carry the
## edited field's message, which was right while a row could only go red and say
## nothing; now the row says it, and a second copy of the same sentence a few
## pixels away is the one thing on the card a reader has to check twice. The
## count is what the row cannot say -- that a field further down the list, off
## the bottom of the card, is also refusing.
func _on_binding_changed(_text: String, _command: String) -> void:
	for other in _binding_fields:
		_validate_field(str(other))
	%BindingsStatus.text = ("" if _invalid.is_empty()
		else "1 key still needs fixing" if _invalid.size() == 1
		else "%d keys still need fixing" % _invalid.size())
	_refresh_play()


func _on_game_selected(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry := _entries[index]
	_title = str(entry.get("title", ""))
	%SoloTitle.text = _title
	%SoloRoot.text = GameTile.roots_line(entry)
	for i in _tiles.size():
		_tiles[i].set_pressed_no_signal(i == index)
	_build_flags(entry)
	_select_root(TitleList.default_root(entry))


## A row of flags, and only for a title that has more than one root. Piposh is
## the one title in six with localisations; the other three show nothing here.
func _build_flags(entry: Dictionary) -> void:
	# Removed as well as freed: `queue_free` lands at the end of the frame, so a
	# child that is only queued is still in `get_children()` when `_link_focus`
	# runs below and would be handed a focus neighbour on its way out.
	for child in _flags.get_children():
		_flags.remove_child(child)
		child.queue_free()
	var roots: Array = entry.get("roots", [])
	_flags.visible = roots.size() > 1
	# The eyebrow above the row belongs to the row: a heading over nothing reads
	# as a control that failed to load.
	#
	# The row it lives in holds a spring between this column and the stage-fit
	# one, and that is what keeps this from being visible as a *jump*. With the
	# expansion on this column instead, selecting a title with one edition --
	# Rating, in the shipped list -- collapsed it and threw the stage-fit menu
	# from the right edge to the left, halfway across the panel, every time the
	# selection moved between a localised title and a plain one.
	%Language.visible = _flags.visible
	if roots.size() < 2:
		_link_focus()
		return
	var group := ButtonGroup.new()
	for row in roots:
		var data := row as Dictionary
		var button := Button.new()
		button.theme_type_variation = "Flag"
		button.toggle_mode = true
		button.button_group = group
		button.text = TitleList.flag_emoji(str(data.get("flag", "")))
		button.tooltip_text = str(data.get("name", ""))
		button.custom_minimum_size = Vector2(56, 56)
		button.add_theme_font_override("font", _emoji_font())
		button.add_theme_font_size_override("font_size", 26)
		button.button_pressed = bool(data.get("default", false))
		button.pressed.connect(_select_root.bind(data))
		_flags.add_child(button)
	_link_focus()


## Where each arrow and each D-pad press goes.
##
## Godot's own answer is a spatial search in the direction pressed, and it stops
## at the edge of the grid: the tile in the last column has nothing to its
## right, so a walk along a row ends there rather than wrapping into the next.
## The seams out of the grid have the same problem in the other direction --
## nothing below the bottom row is *aligned* with it, so "down" from a tile
## found the aspect menu only by luck of pixel position, and stopped finding it
## the moment the flag row appeared between them.
##
## Recomputed on every resize because the column count is, and rebuilt with the
## flags because the row below the grid is not the same row for every title.
func _link_focus() -> void:
	var count := _tiles.size()
	if count == 0:
		return
	var columns := maxi((%Grid as GridContainer).columns, 1)
	var below := _first_flag() if _flags.visible else _aspect
	for i in count:
		var tile := _tiles[i]
		tile.focus_neighbor_left = tile.get_path_to(_tiles[maxi(i - 1, 0)])
		tile.focus_neighbor_right = tile.get_path_to(_tiles[mini(i + 1, count - 1)])
		tile.focus_neighbor_top = (tile.get_path_to(_tiles[i - columns])
			if i >= columns else NodePath())
		tile.focus_neighbor_bottom = (tile.get_path_to(_tiles[i + columns])
			if i + columns < count else tile.get_path_to(below))
	var last_row := (count - 1) / columns * columns
	for flag in _flags.get_children():
		var button := flag as Control
		button.focus_neighbor_top = button.get_path_to(_tiles[last_row])
		button.focus_neighbor_bottom = button.get_path_to(_play)
	if _flags.visible and _flags.get_child_count() > 0:
		var last := _flags.get_child(_flags.get_child_count() - 1) as Control
		last.focus_neighbor_right = last.get_path_to(_aspect)
		_aspect.focus_neighbor_left = _aspect.get_path_to(last)
	_aspect.focus_neighbor_top = _aspect.get_path_to(_tiles[last_row])
	_aspect.focus_neighbor_bottom = _aspect.get_path_to(_play)
	var quit := %Quit as Control
	_play.focus_neighbor_top = _play.get_path_to(_aspect)
	_play.focus_neighbor_left = _play.get_path_to(quit)
	quit.focus_neighbor_right = quit.get_path_to(_play)
	quit.focus_neighbor_top = quit.get_path_to(_aspect)


func _first_flag() -> Control:
	return _flags.get_child(0) as Control if _flags.get_child_count() > 0 else _aspect


## Something has to hold focus when the screen opens, or the first press of a
## D-pad goes nowhere and a machine with no keyboard cannot tell the launcher
## from a picture of one.
func _focus_start() -> void:
	if not _tiles.is_empty():
		_tiles[0].grab_focus()
	elif not _play.disabled:
		_play.grab_focus()


## There is nothing behind this screen, so the key that means "back" means
## "close the player". A gamepad that can reach Play has to be able to reach the
## way out as well, and `ui_cancel` carries the B button already.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_quit()


func _emoji_font() -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(EMOJI_FONTS)
	var base := FontVariation.new()
	base.base_font = ThemeDB.fallback_font
	base.fallbacks = [system] as Array[Font]
	return base


func _select_root(row: Dictionary) -> void:
	_root = str(row.get("root", ""))
	_boot = str(row.get("boot", ""))
	# Empty for every Director title, and the whole of the difference for a
	# title that is a Godot project: `_launch` changes to this instead of to the
	# preview, and `_on_play` writes no game root, because there is no movie.
	_scene = str(row.get("scene", ""))
	_refresh_play()


## The single owner of `Play`'s enabled state.
##
## One function and not two, because Task 6 adds a second reason to refuse --
## a binding that failed validation -- and two writers on one property means
## whichever ran last decides. That is the same fault `debug_keys.gd` reports
## for two commands on one key, in a place nothing would report it.
##
## The reason moved off the button and into the note beside it. A button whose
## label is the complaint cannot also say what pressing it does, and it changes
## width as the complaint changes; the label now names the title it will start,
## which is the one thing the footer could not say before.
func _refresh_play() -> void:
	var reason := ""
	if not _invalid.is_empty():
		reason = "תקנו את המקש המסומן לפני שמתחילים"
	elif _root == "":
		reason = "בחרו משחק"
	# A title that is a Godot project is entered by changing scene, so it names
	# no container and never will. The complaint below is about a *Director*
	# title whose `[root.*]` section has no `boot` -- a real misconfiguration,
	# and one this must keep catching.
	elif _scene == "" and _boot == "":
		reason = "למשחק הזה לא מוגדר קובץ פתיחה — הגדירו אחד בלשונית המפתחים"
	_play.disabled = reason != ""
	# Just "Play". It used to name the selected title, which was the only thing
	# on screen saying what would launch -- back when a tile press both selected
	# and played, so the selection was never visible for long enough to read.
	# Now a press only selects, the chosen tile is drawn as chosen, and the
	# button naming it again is a second answer to a question the grid already
	# answers. A label that changes width as you arrow across the grid is also a
	# button that moves under the pointer.
	_play.text = "שחק"
	%PlayNote.text = reason
	%PlayNote.visible = reason != ""


func _on_quit() -> void:
	get_tree().quit()


func _on_play() -> void:
	# A Godot-project title has no movie, so none of the below applies to it:
	# writing a `game.root` that holds no containers would leave the overlay
	# pointing at something the preview cannot open, and the next launch of a
	# Director title would inherit it.
	if _scene != "":
		_redrive_autoloads()
		_launch()
		return
	var overlay := GameConfig.overlay()
	overlay.set_value("game", "root", _root)
	overlay.set_value("game", "boot_movie", _boot)
	overlay.set_value("display", "aspect", ASPECTS[maxi(_aspect.selected, 0)])
	if _show_developer:
		# An empty boot override means "whatever the chosen game boots", which is
		# a different statement from the empty string: the key is removed rather
		# than written blank, or `DirectorPaths.load_config` reads "" and reports
		# no game configured.
		#
		# Skipping is enough to clear a stale one: the selected title's own boot
		# is written unconditionally above, so a blank field leaves *that* in the
		# overlay rather than whatever a previous run pinned there.
		var override := str(%Boot.text).strip_edges()
		if override != "":
			overlay.set_value("game", "boot_movie", override)
		var codepage := str(CODEPAGES[maxi(%Codepage.selected, 0)])
		if codepage != "":
			overlay.set_value("game", "codepage", codepage)
		elif overlay.has_section_key("game", "codepage"):
			overlay.erase_section_key("game", "codepage")
		# `_override` and not `set_value`, and this is the `%Boot` lesson above
		# arriving on the two controls that were still echoing. Both are seeded
		# from the *merged* config and were written back unconditionally, so a
		# value nobody chose became a per-machine override of the shipped one.
		#
		# It cost a release. Running from source the tab is always visible and the
		# switch reads `auto`, so every Play pinned `enabled="auto"` into
		# `user://` -- and `user://` is keyed on the project name, so it is the
		# same file the exported build reads. `v0.3.0-alpha` stamps `true` into
		# the config it ships and every machine that had ever pressed Play here
		# overrode it back to `auto`, which in a release export is off. The build
		# was right and the overlay switched it off: no HUD, no SKIP, no toast,
		# and every F-key dead, with the Developer tab still visible because that
		# reads the tracked config alone.
		var tracked := GameConfig.tracked()
		_override(overlay, tracked, "enabled",
			DEBUG_VALUES[maxi(%Debug.selected, 0)], DebugKeys.AUTO)
		for command in _binding_fields:
			_override(overlay, tracked, str(command),
				str((_binding_fields[command] as LineEdit).text).strip_edges(),
				str(DebugKeys.DEFAULTS[command]))
		overlay.set_value("qol", KeyAffordance.CONFIG_KEY,
			KeyAffordance.SWITCH_VALUES[%TouchControls.selected])
		# `enabled()` caches its answer in a `static var`, and the preview is
		# loaded into *this* process rather than spawned -- so a cache warmed
		# before this write would outlive it and the switch would appear to do
		# nothing until the launcher was restarted. -1 is the uncomputed state.
		KeyAffordance.force(-1)
		overlay.set_value("qol", "hotspot_hints", %HotspotHints.button_pressed)
		overlay.set_value("qol", "expand_edge_hotspots", %EdgeHotspots.button_pressed)
		overlay.set_value("qol", "enhanced_graphics", %EnhancedGraphics.button_pressed)
		overlay.set_value("qol", "cursor_speed", float(%CursorSpeed.value))
	GameConfig.write_overlay(overlay)
	_redrive_autoloads()
	_launch()


## Write a `[debug]` key into the overlay only when it is genuinely an override.
##
## A value equal to what the shipped config says is *not* an override, so the key
## is erased instead of written. An overlay that repeats a default is
## indistinguishable from one that deliberately pins it, and the moment the
## shipped default moves -- which is precisely what a release stamping
## `enabled = "true"` does -- every repeat turns into a silent override of the new
## value. See `_on_play` for the release that cost.
##
## `fallback` is what `DebugKeys` uses when the tracked file says nothing, so the
## comparison is against the value that would actually apply rather than against
## the empty string. Compared case-insensitively and stripped, because
## `resolve_switch` reads the switch that way and `OS.find_keycode_from_string`
## reads a key name that way: a differently-cased echo is still an echo.
##
## **Erasing is what makes this work on a phone.** Android has no command line,
## so `--debug-ui on` does not exist there, and `res://` lives inside the APK, so
## there is no file to hand-edit either -- `game_config.gd` records that the
## recovery from a bad `[debug] enabled` on Android was clear-app-data, which
## costs the player every save. With this, the switch in the Developer tab reaches
## every state on its own: choosing the value the build ships erases the key and
## hands the decision back to the build, choosing any other one overrides it. One
## tap, no data loss, and identical on desktop.
static func _override(overlay: ConfigFile, tracked: ConfigFile, key: String,
		value: String, fallback: String) -> void:
	var shipped := str(tracked.get_value("debug", key, fallback))
	if value.strip_edges().to_lower() == shipped.strip_edges().to_lower():
		if overlay.has_section_key("debug", key):
			overlay.erase_section_key("debug", key)
		return
	overlay.set_value("debug", key, value)


## Autoloads read the config once, at process start, and survive a scene change.
##
## **This is `director_paths.gd`'s `--root` lesson arriving through a new door.**
## That comment records what happens when the movies move and something that
## cached the old root does not: `AudioDirector` indexed its sounds against the
## previous title and every lookup missed, so the game ran silent. The launcher
## changes the root *after* every autoload has already started, which is the
## same situation reached a different way.
##
## `AudioDirector` happens to survive it today -- `audio_director.gd:96` defers
## the index to the first `resolve_path`, which is after the preview has loaded
## -- but that is an implementation detail of one file and `_indexed` is a
## one-shot latch, so anything that touches audio before Play would poison it.
## `AppSettings.load_settings()` now reads through `GameConfig` too -- its
## `cursor_speed` is the one field in that node with a live consumer
## (`input_router.gd`) -- so without this call it would hold whatever the
## config said at process start, before the player touched the Developer tab
## at all.
##
## So both are re-driven explicitly rather than each being left to its own
## luck: one call closes a gap that is real today, the other holds the line
## against a gap that is only coming. An autoload added later that caches
## config belongs on this list, and the fact that the list exists is what
## makes that a thing somebody can notice.
##
## The third is not a config re-read. `InputRouter` was switched off in `_ready`
## so that the gamepad's A could reach a button on a menu; it is the movie's
## again from here, and it is on this list because "the launcher turned an
## autoload off" is exactly the kind of thing that gets left off.
func _redrive_autoloads() -> void:
	AppSettings.load_settings()
	AudioDirector.reset_index()
	InputRouter.set_enabled(true)


func _launch() -> void:
	# Deferred rather than immediate. `_launch` is reached from `_ready` on the
	# command-line bypass path, and changing scene from inside the current
	# scene's `_ready` is the standard way to free a node that is mid-
	# initialisation.
	get_tree().change_scene_to_file.call_deferred(_scene if _scene != "" else PREVIEW_SCENE)
