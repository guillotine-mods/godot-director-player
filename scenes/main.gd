extends Control

@onready var movie_player: MoviePlayer = %MoviePlayer
@onready var debug_hud: PanelContainer = %DebugHud
@onready var save_editor: PanelContainer = %SaveEditor
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var dev_bar: HBoxContainer = %DevBar


func _ready() -> void:
	debug_hud.setup(movie_player)
	save_editor.setup(movie_player)
	settings_panel.setup(movie_player)
	debug_hud.visible = false
	save_editor.visible = false
	settings_panel.visible = false
	save_editor.close_requested.connect(func(): save_editor.visible = false)
	settings_panel.close_requested.connect(func(): settings_panel.visible = false)
	movie_player.save_ui_requested.connect(_on_save_ui_requested)
	AppSettings.settings_changed.connect(_sync_dev_bar)
	_sync_dev_bar()


func _sync_dev_bar() -> void:
	dev_bar.visible = AppSettings.dev_mode


func _on_skip_scene_pressed() -> void:
	var what: String = movie_player.runtime.dev_skip_scene()
	GameState.emit_log("Dev skip: %s" % what, "info")


func _on_save_ui_requested(_mode: String) -> void:
	save_editor.visible = true
	save_editor.refresh_from_state()


## Director key codes, for `the keyCode`. The corpus tests exactly one of them:
## `fromnow` compares against "49" and stops sound channel 1, so pressing space
## cuts the line of speech that is playing.
const DIRECTOR_KEY_CODES := {
	KEY_SPACE: 49,
	KEY_ENTER: 36,
	KEY_KP_ENTER: 76,
	KEY_ESCAPE: 53,
	KEY_TAB: 48,
}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = DIRECTOR_KEY_CODES.get((event as InputEventKey).keycode, 0)
		if code != 0 and movie_player.runtime.handle_key(code):
			# Not marked handled: the original's key script runs alongside the
			# port's own shortcuts rather than swallowing them.
			pass
	if event.is_action_pressed("toggle_debug"):
		debug_hud.visible = not debug_hud.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_save_editor"):
		save_editor.visible = not save_editor.visible
		if save_editor.visible:
			save_editor.refresh_from_state()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_settings"):
		settings_panel.visible = not settings_panel.visible
		if settings_panel.visible:
			settings_panel.setup(movie_player)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dev_warp") and AppSettings.dev_mode:
		# Shift+F6 also satisfies the plain action, so the modifier is read here
		# rather than declared as a second binding.
		if event is InputEventKey and (event as InputEventKey).shift_pressed:
			_set_warp_target()
		else:
			_warp_to_target()
		get_viewport().set_input_as_handled()


func _set_warp_target() -> void:
	if GameState.current_movie == "":
		GameState.emit_log("Warp target unchanged: no movie loaded", "warn")
		return
	AppSettings.dev_warp_movie = GameState.current_movie
	AppSettings.dev_warp_label = GameState.current_label
	AppSettings.notify_changed()
	GameState.emit_log("F6 warp target set: %s" % _warp_description(), "info")


func _warp_to_target() -> void:
	## Moves the playhead only. It does not replay the walk that would normally get
	## you here, so `globalday`, inventory and the route stack are whatever they were
	## — set those in the save editor (F5) if the room needs them.
	if AppSettings.dev_warp_movie == "":
		GameState.emit_log("No F6 warp target set — Shift+F6 sets it here", "warn")
		return
	GameState.emit_log("Warping to %s" % _warp_description(), "info")
	movie_player.goto_movie(AppSettings.dev_warp_movie, AppSettings.dev_warp_label)


func _warp_description() -> String:
	if AppSettings.dev_warp_label == "":
		return AppSettings.dev_warp_movie
	return "%s @ %s" % [AppSettings.dev_warp_movie, AppSettings.dev_warp_label]
