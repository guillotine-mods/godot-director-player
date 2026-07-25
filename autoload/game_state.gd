extends Node
## Persistent adventure globals (inventory, day, meetings, location).
## Save format is intentionally editable for the Save Editor tool.

signal state_changed
signal movie_requested(movie: String, frame_or_label: Variant)
signal log_message(message: String, level: String)

const INVENTORY_PATH := "res://assets/inventory_items.json"
const SAVE_DIR := "user://saves"
const FIELD_LINES := 30

const DAY1_MEETINGS_INIT: PackedStringArray = [
	"murder1",
	"hatday1",
	"mrfday1",
	"ishday1",
	"patpip1",
	"tofircpt",
	"allin",
	"goldodead",
]

const MEETING_TRIGGERS: Array[Dictionary] = [
	{"room": "clif2", "day": 1, "index": 0, "movie": "MURDER1"},
	{"room": "veranda", "day": 1, "index": 1, "movie": "HATDAY1", "require_done": []},
	{"room": "shore2", "day": 1, "index": 2, "movie": "MRFDAY1", "require_done": [1]},
	{"room": "field", "day": 1, "index": 4, "movie": "PATDAY1", "require_done": [1]},
]

## Movies treated as skippable minigames when QoL skip is enabled.
const MINIGAME_MOVIES: PackedStringArray = [
	"CHESS", "TENNIS", "SHUFFLE", "ARCADE1", "ARCADE2", "PPTSHOW", "SEA1", "AIR1",
]

var inventory_catalog: Dictionary = {}
var objects_field: PackedStringArray = PackedStringArray()
var globalday: int = 1
var meetings: PackedStringArray = PackedStringArray()
var current_movie: String = "strtgame"
var current_label: String = "mainmenu"
var current_frame: int = 0
var route_stack: Array[Dictionary] = []
var whichsnd: String = "sea"


func _ready() -> void:
	_load_inventory_catalog()
	new_game()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _load_inventory_catalog() -> void:
	if not FileAccess.file_exists(INVENTORY_PATH):
		push_warning("Missing inventory catalog: %s" % INVENTORY_PATH)
		return
	var text := FileAccess.get_file_as_string(INVENTORY_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		inventory_catalog = parsed


func new_game() -> void:
	globalday = 1
	meetings = DAY1_MEETINGS_INIT.duplicate()
	whichsnd = "sea"
	route_stack.clear()
	_init_objects_field()
	current_movie = "strtgame"
	current_label = "mainmenu"
	current_frame = 0
	emit_log("New game globals initialized", "info")
	state_changed.emit()


func _init_objects_field() -> void:
	var lines: int = int(inventory_catalog.get("field_lines", FIELD_LINES))
	objects_field = PackedStringArray()
	objects_field.resize(lines)
	for i in lines:
		objects_field[i] = "empty"


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"globalday": globalday,
		"meetings": Array(meetings),
		"objects_field": Array(objects_field),
		"current_movie": current_movie,
		"current_label": current_label,
		"current_frame": current_frame,
		"whichsnd": whichsnd,
		"route_stack": route_stack.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	globalday = int(data.get("globalday", 1))
	meetings = PackedStringArray(data.get("meetings", Array(DAY1_MEETINGS_INIT)))
	var field: Array = data.get("objects_field", [])
	if field.is_empty():
		_init_objects_field()
	else:
		objects_field = PackedStringArray(field)
	current_movie = str(data.get("current_movie", "DAY1"))
	current_label = str(data.get("current_label", "shore2"))
	current_frame = int(data.get("current_frame", 0))
	whichsnd = str(data.get("whichsnd", "sea"))
	route_stack.clear()
	for entry in data.get("route_stack", []):
		if typeof(entry) == TYPE_DICTIONARY:
			route_stack.append(entry)
	state_changed.emit()


func save_slot(slot: int, note: String = "") -> Error:
	var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
	var payload := to_dict()
	payload["slot"] = slot
	payload["note"] = note
	payload["saved_at"] = Time.get_datetime_string_from_system()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	emit_log("Saved slot %d → %s" % [slot, path], "info")
	return OK


func load_slot(slot: int) -> Error:
	var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	from_dict(parsed)
	movie_requested.emit(current_movie, current_label if current_label != "" else current_frame)
	emit_log("Loaded slot %d (%s @ %s)" % [slot, current_movie, current_label], "info")
	return OK


func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(1, 11):
		var path := "%s/slot_%02d.json" % [SAVE_DIR, i]
		var entry := {"slot": i, "exists": false, "path": path}
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				entry["exists"] = true
				entry["data"] = parsed
				entry["note"] = str(parsed.get("note", ""))
				entry["saved_at"] = str(parsed.get("saved_at", ""))
				entry["movie"] = str(parsed.get("current_movie", ""))
		out.append(entry)
	return out


func add_inventory_item(item_name: String) -> bool:
	var item := item_name.to_lower()
	if item.is_empty() or item == "empty":
		return false
	for existing in objects_field:
		if str(existing).to_lower() == item:
			return false
	for i in objects_field.size():
		if str(objects_field[i]).to_lower() == "empty":
			objects_field[i] = item
			state_changed.emit()
			emit_log("Inventory + %s" % item, "info")
			return true
	return false


func remove_inventory_item(item_name: String) -> bool:
	var item := item_name.to_lower()
	var idx := -1
	for i in objects_field.size():
		if str(objects_field[i]).to_lower() == item:
			idx = i
			break
	if idx < 0:
		return false
	for i in range(idx, objects_field.size() - 1):
		objects_field[i] = objects_field[i + 1]
	objects_field[objects_field.size() - 1] = "empty"
	state_changed.emit()
	emit_log("Inventory - %s" % item, "info")
	return true


func inventory_member_for_item(item_name: String) -> Dictionary:
	var name := item_name.to_lower()
	var cast_lib := int(inventory_catalog.get("cast_lib", 2))
	if name.is_empty() or name == "empty":
		return {"cast_lib": cast_lib, "cast_id": int(inventory_catalog.get("empty_member", 9))}
	var items: Dictionary = inventory_catalog.get("items", {})
	if not items.has(name):
		return {}
	return {"cast_lib": cast_lib, "cast_id": int(items[name])}


func inventory_override_for_channel(channel: int) -> Dictionary:
	var slots: Array = inventory_catalog.get("slot_channels", [103, 104, 105, 106, 107, 108, 109, 110])
	var slot_idx := slots.find(channel)
	if slot_idx < 0 or slot_idx >= objects_field.size():
		return {}
	return inventory_member_for_item(objects_field[slot_idx])


func is_minigame_movie(movie: String) -> bool:
	return movie.to_upper() in MINIGAME_MOVIES


func mark_meeting_done_by_movie(stem: String) -> void:
	var lower := stem.to_lower()
	var aliases := {
		"murder1": 0, "hatday1": 1, "mrfday1": 2, "ishday1": 3,
		"patpip1": 4, "patday1": 4, "tofircpt": 5, "allin": 6,
		"goldodead": 7, "golddead": 7,
	}
	if not aliases.has(lower):
		return
	var idx: int = aliases[lower]
	if idx >= meetings.size():
		return
	if meetings[idx] == "done":
		return
	meetings[idx] = "done"
	state_changed.emit()
	emit_log("Meeting done: %s" % lower, "info")


func people_funk(room_label: String) -> String:
	var room := room_label.to_lower().trim_suffix("go")
	for trig in MEETING_TRIGGERS:
		if str(trig.room) != room:
			continue
		if int(trig.day) != globalday:
			continue
		var idx: int = int(trig.index)
		if idx < meetings.size() and str(meetings[idx]).to_lower() == "done":
			continue
		var req: Array = trig.get("require_done", [])
		var blocked := false
		for r in req:
			if int(r) >= meetings.size() or str(meetings[int(r)]).to_lower() != "done":
				blocked = true
				break
		if blocked:
			continue
		return str(trig.movie)
	return ""


func remember_location(movie: String, label: String, frame: int) -> void:
	current_movie = movie
	current_label = label
	current_frame = frame
	state_changed.emit()


func emit_log(message: String, level: String = "info") -> void:
	log_message.emit(message, level)
	print("[piposh2:%s] %s" % [level, message])
