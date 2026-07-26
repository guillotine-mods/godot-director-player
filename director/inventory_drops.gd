class_name InventoryDrops
extends RefCounted
## Reads data/inventory_drops.json. Same shape as MovieContext: a hand
## maintained table the Lingo is transcribed into, one citation per rule.

const TABLE_PATH := "res://data/inventory_drops.json"

var _rules: Dictionary = {}


func load_table() -> void:
	_rules.clear()
	if not FileAccess.file_exists(TABLE_PATH):
		GameState.emit_log("Missing drop table: %s" % TABLE_PATH, "warn")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		GameState.emit_log("Drop table is not an object: %s" % TABLE_PATH, "warn")
		return
	var rules: Variant = (parsed as Dictionary).get("rules", {})
	if typeof(rules) != TYPE_DICTIONARY:
		return
	var kept := 0
	for movie in (rules as Dictionary).keys():
		if str(movie).begins_with("_"):
			continue
		var list: Variant = (rules as Dictionary)[movie]
		if typeof(list) != TYPE_ARRAY:
			continue
		var enabled: Array = []
		for rule in list as Array:
			if typeof(rule) != TYPE_DICTIONARY:
				continue
			if not bool((rule as Dictionary).get("enabled", true)):
				continue
			enabled.append(rule)
		if not enabled.is_empty():
			_rules[str(movie).to_upper()] = enabled
			kept += enabled.size()
	GameState.emit_log("Drop rules loaded: %d across %d movies" % [kept, _rules.size()], "info")


func rules_for(movie: String) -> Array:
	var list: Variant = _rules.get(movie.to_upper(), [])
	return list if typeof(list) == TYPE_ARRAY else []


func matches(rule: Dictionary, item: String, room: String) -> bool:
	var items: Variant = rule.get("items", [])
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		return false
	var wanted := item.to_lower()
	var item_ok := false
	for candidate in items as Array:
		var name := str(candidate).to_lower()
		if name == "*" or name == wanted:
			item_ok = true
			break
	if not item_ok:
		return false
	var rooms: Variant = rule.get("rooms", [])
	if typeof(rooms) != TYPE_ARRAY or (rooms as Array).is_empty():
		return true
	var here := room.to_lower().trim_suffix("go")
	for candidate in rooms as Array:
		if str(candidate).to_lower().trim_suffix("go") == here:
			return true
	return false
