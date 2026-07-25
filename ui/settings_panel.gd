extends PanelContainer

signal close_requested

@onready var aspect_option: OptionButton = %AspectOption
@onready var upscale_option: OptionButton = %UpscaleOption
@onready var debug_check: CheckBox = %DebugCheck
@onready var hints_check: CheckBox = %HintsCheck
@onready var skip_check: CheckBox = %SkipCheck
@onready var enhanced_check: CheckBox = %EnhancedCheck
@onready var edge_check: CheckBox = %EdgeCheck
@onready var cursor_speed: HSlider = %CursorSpeed
@onready var movie_option: OptionButton = %MovieOption

var _player: MoviePlayer
var _syncing: bool = false


func setup(player: MoviePlayer) -> void:
	_player = player
	_syncing = true
	aspect_option.clear()
	for name in AppSettings.AspectMode.keys():
		aspect_option.add_item(str(name))
	aspect_option.select(AppSettings.aspect_mode)

	upscale_option.clear()
	for name in AppSettings.UpscaleMode.keys():
		upscale_option.add_item(str(name))
	upscale_option.select(AppSettings.upscale_mode)

	debug_check.button_pressed = AppSettings.show_debug_overlays
	hints_check.button_pressed = AppSettings.show_hotspot_hints
	skip_check.button_pressed = AppSettings.allow_minigame_skip
	enhanced_check.button_pressed = AppSettings.test_mode_enhanced_graphics
	edge_check.button_pressed = AppSettings.expand_edge_hotspots
	cursor_speed.value = AppSettings.controller_cursor_speed

	movie_option.clear()
	for m in _player.available_movies():
		movie_option.add_item(m)
	_syncing = false


func _apply() -> void:
	if _syncing:
		return
	AppSettings.aspect_mode = aspect_option.selected as AppSettings.AspectMode
	AppSettings.upscale_mode = upscale_option.selected as AppSettings.UpscaleMode
	AppSettings.show_debug_overlays = debug_check.button_pressed
	AppSettings.show_hotspot_hints = hints_check.button_pressed
	AppSettings.allow_minigame_skip = skip_check.button_pressed
	AppSettings.test_mode_enhanced_graphics = enhanced_check.button_pressed
	AppSettings.expand_edge_hotspots = edge_check.button_pressed
	AppSettings.controller_cursor_speed = cursor_speed.value
	AppSettings.notify_changed()


func _on_aspect_option_item_selected(_idx: int) -> void:
	_apply()


func _on_upscale_option_item_selected(_idx: int) -> void:
	_apply()


func _on_debug_check_toggled(_v: bool) -> void:
	_apply()


func _on_hints_check_toggled(_v: bool) -> void:
	_apply()


func _on_skip_check_toggled(_v: bool) -> void:
	_apply()


func _on_enhanced_check_toggled(_v: bool) -> void:
	_apply()


func _on_edge_check_toggled(_v: bool) -> void:
	_apply()


func _on_cursor_speed_value_changed(_v: float) -> void:
	_apply()


func _on_jump_movie_pressed() -> void:
	if _player == null:
		return
	var movie := movie_option.get_item_text(movie_option.selected)
	_player.goto_movie(movie)


func _on_close_pressed() -> void:
	close_requested.emit()
