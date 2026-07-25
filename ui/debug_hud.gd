extends PanelContainer

@onready var info_label: RichTextLabel = %InfoLabel
@onready var log_label: RichTextLabel = %LogLabel

var _player: MoviePlayer
var _lines: PackedStringArray = PackedStringArray()


func setup(player: MoviePlayer) -> void:
	_player = player
	_player.movie_changed.connect(_refresh)
	_player.frame_changed.connect(func(_f): _refresh())
	_player.nav_event.connect(_on_nav)
	GameState.log_message.connect(_on_log)
	GameState.state_changed.connect(_refresh)
	AppSettings.settings_changed.connect(_refresh)
	_refresh()


func _on_nav(msg: String) -> void:
	_push(msg, "nav")


func _on_log(msg: String, level: String) -> void:
	_push(msg, level)


func _push(msg: String, level: String) -> void:
	_lines.insert(0, "[%s] %s" % [level, msg])
	if _lines.size() > 40:
		_lines.resize(40)
	if log_label:
		log_label.text = "\n".join(_lines)
	_refresh()


func _refresh(_a: Variant = null) -> void:
	if _player == null or info_label == null:
		return
	var inv_parts: PackedStringArray = PackedStringArray()
	for i in mini(8, GameState.objects_field.size()):
		inv_parts.append(GameState.objects_field[i])
	var inv := ", ".join(inv_parts)
	info_label.text = (
		"[b]%s[/b]  frame %d / %d\n"
		+ "label: %s   day: %d\n"
		+ "aspect: %s   upscale: %s   enhanced: %s\n"
		+ "inv: %s\n"
		+ "[i]F1 debug · F5 save editor · F10 settings · H hint · Esc skip[/i]"
	) % [
		_player.loader.movie_name,
		_player.frame_index + 1,
		_player.loader.frames.size(),
		GameState.current_label,
		GameState.globalday,
		AppSettings.aspect_mode_name(),
		AppSettings.upscale_mode_name(),
		str(AppSettings.test_mode_enhanced_graphics),
		inv,
	]
