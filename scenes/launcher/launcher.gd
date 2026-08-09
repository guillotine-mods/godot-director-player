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

const GameConfig := preload("res://director/game_config.gd")
const TitleList := preload("res://scenes/launcher/title_list.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const BindingRules := preload("res://scenes/launcher/binding_rules.gd")

const PREVIEW_SCENE := "res://scenes/director_preview.tscn"

## Emoji are not in the project's font. `Open Sans SemiBold` carries Hebrew and
## Cyrillic but no emoji block at all, measured with `has_char` on 4.7.1, so a
## flag label needs the platform's emoji font as a fallback. A platform whose
## emoji font declines regional-indicator pairs -- Windows does -- draws the two
## letters instead, which is `IL`, `US`, `RU`: the label a text-only design
## would have picked, so there is nothing to fall back to.
const EMOJI_FONTS := ["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"]

const ASPECTS := ["native_4_3", "wide_16_9", "ultra_21_9", "stretch_fill"]

const CODEPAGES := ["", "mac_hebrew", "windows_1255"]
const DEBUG_VALUES := [DebugKeys.AUTO, DebugKeys.ON, DebugKeys.OFF]

@onready var _games: OptionButton = %Games
@onready var _flags: HBoxContainer = %Flags
@onready var _aspect: OptionButton = %Aspect
@onready var _play: Button = %Play

var _entries: Array[Dictionary] = []
var _root := ""
var _boot := ""
var _binding_fields: Dictionary = {}
## Set once in `_ready`. `_on_play` reads this rather than calling
## `_developer_visible()` again, for the reason `_refresh_play`'s own comment
## gives about a second reason to disable Play: two call sites computing the
## same answer is two chances for them to compute it differently.
var _show_developer := false


func _ready() -> void:
	if _named_on_command_line():
		_launch()
		return
	_entries = TitleList.build()
	_fill_games()
	_fill_aspect()
	var tabs := %Tabs as TabContainer
	var developer := %Developer as Control
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
	if _entries.size() > 0:
		_on_game_selected(_games.selected)


## `--root`, `--boot` and `--save` each name a game, and each is meant to be
## sufficient without a menu.
func _named_on_command_line() -> bool:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		for flag in ["--root", "--boot", "--save"]:
			if text == flag or text.begins_with(flag + "="):
				return true
	return false


func _fill_games() -> void:
	_games.clear()
	for entry in _entries:
		_games.add_item(str(entry["title"]))
	# One game is not a choice. A single-title build shows no list at all, which
	# is what lets an Android export carry one game without a decision here.
	_games.visible = _entries.size() > 1
	_games.selected = 0


func _fill_aspect() -> void:
	_aspect.clear()
	for name in ASPECTS:
		_aspect.add_item(str(name).replace("_", " "))
	var current := str(GameConfig.merged().get_value("display", "aspect", "native_4_3"))
	_aspect.selected = maxi(ASPECTS.find(current), 0)


## Whether the developer tab is there at all.
##
## **From the tracked file, never from the merged value**, and that is a
## deliberate exception to `debug_keys.gd`'s one-answer-per-process rule. The
## tab contains the control that sets `[debug] enabled`, so a tab whose
## visibility read the overlay would close the door behind itself: set it false
## and the control that would set it back is gone. `--debug-ui on` recovers that
## on a desktop; Android has no command line and is the only export preset, so
## there the only way back would be clearing the app's data.
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
	%Boot.text = str(cfg.get_value("game", "boot_movie", ""))
	%Boot.placeholder_text = "empty: whatever the chosen game boots"
	%Codepage.clear()
	for name in CODEPAGES:
		%Codepage.add_item("engine default (bytes as code points)" if name == "" else name)
	%Codepage.selected = maxi(CODEPAGES.find(str(cfg.get_value("game", "codepage", ""))), 0)
	%Debug.clear()
	for name in DEBUG_VALUES:
		%Debug.add_item(name)
	%Debug.selected = maxi(DEBUG_VALUES.find(
		str(cfg.get_value("debug", "enabled", DebugKeys.AUTO)).strip_edges().to_lower()), 0)


func _on_bindings_pressed() -> void:
	if %Bindings.visible:
		return
	# The third check reads every title's scripts, which is seconds. Say so
	# before doing it rather than freezing a button with no explanation.
	%BindingsStatus.text = "Reading what the games test…"
	await get_tree().process_frame
	BindingRules.measure()
	%BindingsStatus.text = ""
	_build_bindings()
	%Bindings.visible = true
	%BindingsButton.disabled = true


func _build_bindings() -> void:
	var cfg := GameConfig.merged()
	for command in DebugKeys.DEFAULTS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(command)
		label.custom_minimum_size = Vector2(220, 0)
		var field := LineEdit.new()
		field.text = str(cfg.get_value("debug", command, DebugKeys.DEFAULTS[command]))
		field.custom_minimum_size = Vector2(180, 56)
		field.placeholder_text = "empty: unbound"
		field.text_changed.connect(_on_binding_changed.bind(str(command)))
		row.add_child(label)
		row.add_child(field)
		_binding_fields[str(command)] = field
		%Bindings.add_child(row)


## The three checks, in the order that gives the most useful message: a name
## that is not a key first, then the key that is already taken, then the key a
## game wants.
func _on_binding_changed(_text: String, command: String) -> void:
	var field := _binding_fields[command] as LineEdit
	var name := str(field.text).strip_edges()
	var problem := ""
	if name == "":
		problem = ""  # Unbinding is legal, and is how a game gets a key back.
	elif BindingRules.named(name) == KEY_NONE:
		problem = "'%s' is not a key name" % name
	else:
		var current: Dictionary = {}
		for other in _binding_fields:
			current[other] = str((_binding_fields[other] as LineEdit).text).strip_edges()
		var clash := BindingRules.collision(current, command, name)
		if clash != "":
			problem = "%s is already on %s" % [clash, name]
		else:
			var claimed := BindingRules.claimed_by(name)
			var typed := BindingRules.typed_in(name)
			if not claimed.is_empty():
				problem = "%s is a keyCode %s tests" % [name, ", ".join(claimed)]
			elif not typed.is_empty():
				problem = "%s types a character %s tests" % [name, ", ".join(typed)]
	field.modulate = Color.WHITE if problem == "" else Color(1.0, 0.55, 0.55)
	%BindingsStatus.text = problem
	_refresh_play()


func _on_game_selected(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry := _entries[index]
	_build_flags(entry)
	_select_root(TitleList.default_root(entry))


## A row of flags, and only for a title that has more than one root. Piposh is
## the one title in six with localisations; the other three show nothing here.
func _build_flags(entry: Dictionary) -> void:
	for child in _flags.get_children():
		child.queue_free()
	var roots: Array = entry.get("roots", [])
	_flags.visible = roots.size() > 1
	if roots.size() < 2:
		return
	var group := ButtonGroup.new()
	for row in roots:
		var data := row as Dictionary
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = TitleList.flag_emoji(str(data.get("flag", "")))
		button.tooltip_text = str(data.get("name", ""))
		button.custom_minimum_size = Vector2(64, 64)
		button.add_theme_font_override("font", _emoji_font())
		button.add_theme_font_size_override("font_size", 32)
		button.button_pressed = bool(data.get("default", false))
		button.pressed.connect(_select_root.bind(data))
		_flags.add_child(button)


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
	_refresh_play()


## The single owner of `Play`'s enabled state.
##
## One function and not two, because Task 6 adds a second reason to refuse --
## a binding that failed validation -- and two writers on one property means
## whichever ran last decides. That is the same fault `debug_keys.gd` reports
## for two commands on one key, in a place nothing would report it.
func _refresh_play() -> void:
	for command in _binding_fields:
		if (_binding_fields[command] as LineEdit).modulate != Color.WHITE:
			_play.disabled = true
			_play.text = "Fix the highlighted key first"
			return
	if _root == "":
		_play.disabled = true
		_play.text = "No game selected"
		return
	if _boot == "":
		_play.disabled = true
		_play.text = "No boot movie — set one in Developer"
		return
	_play.disabled = false
	_play.text = "Play"


func _on_play() -> void:
	var overlay := GameConfig.overlay()
	overlay.set_value("game", "root", _root)
	overlay.set_value("game", "boot_movie", _boot)
	overlay.set_value("display", "aspect", ASPECTS[maxi(_aspect.selected, 0)])
	if _show_developer:
		# An empty boot override means "whatever the chosen game boots", which is
		# a different statement from the empty string: the key is removed rather
		# than written blank, or `DirectorPaths.load_config` reads "" and reports
		# no game configured.
		var override := str(%Boot.text).strip_edges()
		if override != "":
			overlay.set_value("game", "boot_movie", override)
		var codepage := str(CODEPAGES[maxi(%Codepage.selected, 0)])
		if codepage != "":
			overlay.set_value("game", "codepage", codepage)
		elif overlay.has_section_key("game", "codepage"):
			overlay.erase_section_key("game", "codepage")
		overlay.set_value("debug", "enabled", DEBUG_VALUES[maxi(%Debug.selected, 0)])
		for command in _binding_fields:
			overlay.set_value("debug", str(command),
				str((_binding_fields[command] as LineEdit).text).strip_edges())
	GameConfig.write_overlay(overlay)
	_redrive_autoloads()
	_launch()


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
## `AppSettings.load_settings()` fixes nothing today: it reads
## `user://player_settings.cfg`, which has nothing to do with `director_game.cfg`
## or the overlay this screen writes. It is redriven anyway because that stops
## being true the day `AppSettings` is rewritten to read through `GameConfig` --
## this call is what keeps that later change from silently leaving the autoload
## holding a pre-launcher value, rather than a bug nobody notices until it
## matters.
##
## So both are re-driven explicitly rather than each being left to its own
## luck: one call closes a gap that is real today, the other holds the line
## against a gap that is only coming. An autoload added later that caches
## config belongs on this list, and the fact that the list exists is what
## makes that a thing somebody can notice.
func _redrive_autoloads() -> void:
	AppSettings.load_settings()
	AudioDirector.reset_index()


func _launch() -> void:
	# Deferred rather than immediate. `_launch` is reached from `_ready` on the
	# command-line bypass path, and changing scene from inside the current
	# scene's `_ready` is the standard way to free a node that is mid-
	# initialisation.
	get_tree().change_scene_to_file.call_deferred(PREVIEW_SCENE)
