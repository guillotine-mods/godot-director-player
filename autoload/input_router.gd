extends Node
## Unifies mouse + gamepad into a stage-space cursor and click stream.

signal stage_click(stage_pos: Vector2)
signal stage_hover(stage_pos: Vector2)
signal hint_requested
signal skip_requested

var virtual_cursor: Vector2 = Vector2(320, 240)
var using_gamepad: bool = false
var _stage_rect := Rect2(0, 0, 640, 480)
var _enabled: bool = true


func set_stage_rect(rect: Rect2) -> void:
	_stage_rect = rect
	virtual_cursor = virtual_cursor.clamp(rect.position, rect.position + rect.size)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func _process(delta: float) -> void:
	if not _enabled:
		return

	var stick := Vector2(
		Input.get_axis("cursor_left", "cursor_right"),
		Input.get_axis("cursor_up", "cursor_down")
	)
	if stick.length() > 0.15:
		using_gamepad = true
		virtual_cursor += stick * AppSettings.controller_cursor_speed * delta
		virtual_cursor = virtual_cursor.clamp(_stage_rect.position, _stage_rect.position + _stage_rect.size)
		stage_hover.emit(virtual_cursor)

	if Input.is_action_just_pressed("hint"):
		hint_requested.emit()
	if Input.is_action_just_pressed("skip_minigame"):
		skip_requested.emit()


func _input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventMouseMotion:
		using_gamepad = false
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		using_gamepad = true

	if event.is_action_pressed("click") and not event is InputEventMouseButton:
		# Gamepad A / accept → click at virtual cursor
		stage_click.emit(virtual_cursor)
		get_viewport().set_input_as_handled()


func notify_mouse_stage_pos(stage_pos: Vector2) -> void:
	virtual_cursor = stage_pos.clamp(_stage_rect.position, _stage_rect.position + _stage_rect.size)
	stage_hover.emit(virtual_cursor)


func notify_mouse_click(stage_pos: Vector2) -> void:
	virtual_cursor = stage_pos
	stage_click.emit(stage_pos)
