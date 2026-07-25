extends PanelContainer
## Dev Save Editor — inspect / mutate adventure globals and slots.

signal close_requested

@onready var slot_list: ItemList = %SlotList
@onready var movie_edit: LineEdit = %MovieEdit
@onready var label_edit: LineEdit = %LabelEdit
@onready var day_spin: SpinBox = %DaySpin
@onready var inventory_edit: TextEdit = %InventoryEdit
@onready var meetings_edit: TextEdit = %MeetingsEdit
@onready var note_edit: LineEdit = %NoteEdit
@onready var json_preview: TextEdit = %JsonPreview

var _player: MoviePlayer


func setup(player: MoviePlayer) -> void:
	_player = player
	refresh_from_state()
	_reload_slots()


func refresh_from_state() -> void:
	movie_edit.text = GameState.current_movie
	label_edit.text = GameState.current_label
	day_spin.value = GameState.globalday
	inventory_edit.text = "\n".join(GameState.objects_field)
	meetings_edit.text = ",".join(GameState.meetings)
	json_preview.text = JSON.stringify(GameState.to_dict(), "\t")


func _reload_slots() -> void:
	slot_list.clear()
	for entry in GameState.list_slots():
		var label := "Slot %02d" % int(entry.slot)
		if entry.exists:
			label += " — %s @ %s" % [entry.get("movie", "?"), entry.get("saved_at", "")]
			if str(entry.get("note", "")) != "":
				label += " (%s)" % entry.note
		else:
			label += " — empty"
		slot_list.add_item(label)


func _apply_form_to_state() -> void:
	GameState.current_movie = movie_edit.text.strip_edges()
	GameState.current_label = label_edit.text.strip_edges()
	GameState.globalday = int(day_spin.value)
	var lines := inventory_edit.text.replace("\r", "").split("\n", false)
	var field := PackedStringArray()
	for i in GameState.FIELD_LINES:
		field.append(lines[i] if i < lines.size() and str(lines[i]) != "" else "empty")
	GameState.objects_field = field
	var meet := meetings_edit.text.replace(" ", "").split(",", false)
	GameState.meetings = PackedStringArray(meet)
	GameState.state_changed.emit()
	json_preview.text = JSON.stringify(GameState.to_dict(), "\t")


func _on_apply_pressed() -> void:
	_apply_form_to_state()
	if _player:
		_player.goto_movie(GameState.current_movie, GameState.current_label)


func _on_save_pressed() -> void:
	_apply_form_to_state()
	var slot := slot_list.get_selected_items()
	var idx := slot[0] + 1 if slot.size() else 1
	GameState.save_slot(idx, note_edit.text.strip_edges())
	_reload_slots()


func _on_load_pressed() -> void:
	var slot := slot_list.get_selected_items()
	var idx := slot[0] + 1 if slot.size() else 1
	if GameState.load_slot(idx) == OK:
		refresh_from_state()
		_reload_slots()


func _on_new_game_pressed() -> void:
	GameState.new_game()
	refresh_from_state()
	if _player:
		_player.goto_movie("strtgame")


func _on_add_item_pressed() -> void:
	# Quick cheat: shovel is a common day-1 pickup for testing.
	GameState.add_inventory_item("shovel")
	refresh_from_state()


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_refresh_pressed() -> void:
	refresh_from_state()
	_reload_slots()
