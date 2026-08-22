extends Node
## Unifies mouse + gamepad into a stage-space cursor and click stream.

signal stage_click(stage_pos: Vector2)
signal stage_hover(stage_pos: Vector2)
## Director's inventory mechanic is mouseDown (store home) → drag → mouseUp
## (test intersects), which a click stream alone cannot express.
signal stage_press(stage_pos: Vector2)
signal stage_drag(stage_pos: Vector2)
signal stage_release(stage_pos: Vector2)
signal hint_requested
## There is no `skip_requested` beside it any more, and the asymmetry is
## deliberate rather than an oversight (`bugs.md` 129). It carried Escape to the
## retired renderer's `skip_current()`, which decided "is this a skippable
## minigame" from a table of Piposh 2 titles and then walked to the next marker
## -- and `scenes/director_preview.gd`'s comment on `skip_release` records why
## no title-agnostic version of that walk exists: a marker labels a position,
## and nothing in a `VWLB` says which positions are scenes. So the signal had no
## reachable destination, not merely no listener. `hint_requested` is a
## different feature in the same shape -- also unconnected -- and stays.

var virtual_cursor: Vector2 = Vector2(320, 240)
var using_gamepad: bool = false
var _stage_rect := Rect2(0, 0, 640, 480)
var _enabled: bool = true
var _pressed: bool = false


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
	if _pressed:
		stage_drag.emit(virtual_cursor)
	else:
		stage_hover.emit(virtual_cursor)


func notify_mouse_click(stage_pos: Vector2) -> void:
	virtual_cursor = stage_pos
	stage_click.emit(stage_pos)


func notify_mouse_press(stage_pos: Vector2) -> void:
	_pressed = true
	virtual_cursor = stage_pos
	stage_press.emit(stage_pos)


func notify_mouse_release(stage_pos: Vector2) -> void:
	if not _pressed:
		return
	_pressed = false
	virtual_cursor = stage_pos
	stage_release.emit(stage_pos)
