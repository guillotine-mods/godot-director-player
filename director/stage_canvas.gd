extends Control
## Draws the current Director frame via the parent MoviePlayer.

@onready var player: MoviePlayer = get_parent().get_parent() as MoviePlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if player == null:
		player = get_parent().get_parent() as MoviePlayer
	if player == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK, true)
	player.draw_current_frame(self)
