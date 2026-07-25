extends Control

@onready var movie_player: MoviePlayer = %MoviePlayer
@onready var debug_hud: PanelContainer = %DebugHud
@onready var save_editor: PanelContainer = %SaveEditor
@onready var settings_panel: PanelContainer = %SettingsPanel


func _ready() -> void:
	debug_hud.setup(movie_player)
	save_editor.setup(movie_player)
	settings_panel.setup(movie_player)
	save_editor.visible = false
	settings_panel.visible = false
	save_editor.close_requested.connect(func(): save_editor.visible = false)
	settings_panel.close_requested.connect(func(): settings_panel.visible = false)
	movie_player.save_ui_requested.connect(_on_save_ui_requested)


func _on_save_ui_requested(_mode: String) -> void:
	save_editor.visible = true
	save_editor.refresh_from_state()


func _unhandled_input(event: InputEvent) -> void:
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
