class_name MovieContext
extends RefCounted
## Per-movie context the render_model export cannot carry.
##
## Hub membership, walk-transition destinations and playability lived in Lingo
## movie scripts rather than in the score, so they are not recoverable from
## frames.json. Hand-maintained parts come from data/movie_context.json; the
## rest is derived from the loaded movie.

const CONTEXT_PATH := "res://data/movie_context.json"

var hubs: PackedStringArray = PackedStringArray(["DAY1", "HOTEL1", "NIGHT1"])

var _shared_transitions: Dictionary = {}
var _movie_transitions: Dictionary = {}
var _known_unmapped: Dictionary = {}
var _hub_return_cache: Dictionary = {}
var _warned_transitions: Dictionary = {}
var _sprite_gates: Dictionary = {}


func _s(v: Variant, fallback: String = "") -> String:
	if v == null:
		return fallback
	return str(v)


func load_context() -> Error:
	if not FileAccess.file_exists(CONTEXT_PATH):
		push_warning("Missing movie context: %s" % CONTEXT_PATH)
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTEXT_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	var data: Dictionary = parsed

	var hub_value: Variant = data.get("hubs", [])
	if typeof(hub_value) == TYPE_ARRAY and not (hub_value as Array).is_empty():
		hubs = PackedStringArray()
		for hub in hub_value:
			hubs.append(_s(hub))

	var transitions_value: Variant = data.get("transitions", {})
	if typeof(transitions_value) == TYPE_DICTIONARY:
		for key in (transitions_value as Dictionary).keys():
			var block: Variant = (transitions_value as Dictionary)[key]
			if typeof(block) != TYPE_DICTIONARY:
				continue
			var lowered: Dictionary = {}
			for label in (block as Dictionary).keys():
				lowered[_s(label).to_lower()] = _s((block as Dictionary)[label]).to_lower()
			if _s(key).to_lower() == "shared":
				_shared_transitions = lowered
			else:
				_movie_transitions[_s(key).to_lower()] = lowered

	var unmapped_value: Variant = data.get("unmapped_transitions", {})
	if typeof(unmapped_value) == TYPE_DICTIONARY:
		for key in (unmapped_value as Dictionary).keys():
			var labels: Variant = (unmapped_value as Dictionary)[key]
			if typeof(labels) != TYPE_ARRAY:
				continue
			var label_set: Dictionary = {}
			for label in labels:
				label_set[_s(label).to_lower()] = true
			_known_unmapped[_s(key).to_lower()] = label_set

	var gates_value: Variant = data.get("sprite_gates", {})
	if typeof(gates_value) == TYPE_DICTIONARY:
		for key in (gates_value as Dictionary).keys():
			var rules: Variant = (gates_value as Dictionary)[key]
			if typeof(rules) == TYPE_ARRAY:
				_sprite_gates[_s(key).to_lower()] = rules
	return OK


func _room_key(room: String) -> String:
	## Rooms appear as both "shore3" and "shore3go"; one gate entry covers both.
	return room.to_lower().trim_suffix("go")


func hidden_channels(movie: String, room: String) -> Dictionary:
	## Score channels that must not draw or accept clicks in this room right now.
	##
	## Director rooms carry every conditional character and object at once and
	## Lingo puppeted away whatever the story had not reached yet. Nothing in the
	## export records those conditions, so they are declared in
	## data/movie_context.json and evaluated against GameState here.
	var out: Dictionary = {}
	var rules_value: Variant = _sprite_gates.get(movie.to_lower(), [])
	if typeof(rules_value) != TYPE_ARRAY:
		return out
	var wanted := _room_key(room)
	for rule_value in (rules_value as Array):
		if typeof(rule_value) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_value
		if not _rule_covers_room(rule, wanted):
			continue
		if _rule_satisfied(rule):
			continue
		var channels_value: Variant = rule.get("channels", [])
		if typeof(channels_value) != TYPE_ARRAY:
			continue
		for channel in (channels_value as Array):
			out[int(channel)] = true
	return out


func _rule_covers_room(rule: Dictionary, wanted: String) -> bool:
	var rooms_value: Variant = rule.get("rooms", [])
	if typeof(rooms_value) != TYPE_ARRAY:
		return false
	for room in (rooms_value as Array):
		if _room_key(_s(room)) == wanted:
			return true
	return false


func _rule_satisfied(rule: Dictionary) -> bool:
	## True once the story has reached the point where the sprites belong.
	var after_value: Variant = rule.get("after_meeting", null)
	if after_value != null and not GameState.is_meeting_done(_s(after_value)):
		return false
	var from_day: Variant = rule.get("from_day", null)
	if from_day != null and GameState.globalday < int(from_day):
		return false
	return true


func is_hub(movie: String) -> bool:
	var wanted := movie.to_lower()
	for hub in hubs:
		if hub.to_lower() == wanted:
			return true
	return false


func transition_destination(movie: String, label: String) -> String:
	## Movie-specific mapping wins over the shared island table.
	var key := label.to_lower()
	var per_movie_value: Variant = _movie_transitions.get(movie.to_lower(), {})
	if typeof(per_movie_value) == TYPE_DICTIONARY:
		var per_movie: Dictionary = per_movie_value
		if per_movie.has(key):
			return _s(per_movie[key])
	return _s(_shared_transitions.get(key, ""))


func note_unmapped_transition(movie: String, label: String, walked: bool) -> void:
	## One warning per movie/label, so a looping score cannot flood the log.
	##
	## `walked` means the player actually started this transition, so a missing
	## destination is a real gap. Otherwise the label came from the marker under
	## the playhead, which on a redirect frame is usually just the room name, and
	## warning about it would bury the real gaps in noise.
	var known_value: Variant = _known_unmapped.get(movie.to_lower(), {})
	var known := (
		typeof(known_value) == TYPE_DICTIONARY
		and (known_value as Dictionary).has(label.to_lower())
	)
	if not walked and not known:
		return
	var key := "%s/%s" % [movie.to_lower(), label.to_lower()]
	if _warned_transitions.has(key):
		return
	_warned_transitions[key] = true
	GameState.emit_log(
		'unmapped transition %s "%s"%s — destination needs the original Lingo or playtesting'
		% [movie, label, " (known gap)" if known else " (NEW, not in data/movie_context.json)"],
		"warn"
	)


func frame_count(index: Dictionary, movie: String) -> int:
	## Zero means the export is a .CST cast library, not a playable movie.
	var wanted := movie.to_lower()
	for entry in index.get("exports", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _s((entry as Dictionary).get("movie", "")).to_lower() == wanted:
			return int((entry as Dictionary).get("frame_count", 0))
	return -1


func is_playable(index: Dictionary, movie: String) -> bool:
	## -1 means the movie is absent from the index; let the loader report that.
	return frame_count(index, movie) != 0


func hub_return(loader: RenderModelLoader) -> Dictionary:
	## Where a movie sends the player once its score runs out.
	##
	## Derived from the movie's own exported cross-movie navs, keeping only those
	## that target a hub. Every non-hub movie that falls off its end declares
	## exactly one distinct hub target, so this is unambiguous. Ambiguous or
	## absent means the caller decides instead.
	##
	## Deliberately not the caller on route_stack: DAY1 frame 153 is `movie sea1`
	## and frame 729 is `movie air1`, so returning SEA1 to its caller would
	## re-enter the frame that launched it and the two would ping pong forever.
	var movie := loader.movie_name
	if movie == "" or is_hub(movie):
		return {}
	if _hub_return_cache.has(movie):
		return _hub_return_cache[movie] as Dictionary

	var best: Dictionary = {}
	var distinct: Dictionary = {}
	for frame_value in loader.frames:
		if typeof(frame_value) != TYPE_DICTIONARY:
			continue
		var frame: Dictionary = frame_value
		_collect_hub_nav(frame.get("nav", null), distinct, best)
		var sprites_value: Variant = frame.get("sprites", [])
		if typeof(sprites_value) != TYPE_ARRAY:
			continue
		for sprite_value in sprites_value:
			if typeof(sprite_value) != TYPE_DICTIONARY:
				continue
			var on_click: Variant = (sprite_value as Dictionary).get("on_click", null)
			if typeof(on_click) == TYPE_DICTIONARY:
				_collect_hub_nav((on_click as Dictionary).get("nav", null), distinct, best)

	var result: Dictionary = best if distinct.size() == 1 else {}
	_hub_return_cache[movie] = result
	return result


func _collect_hub_nav(nav: Variant, distinct: Dictionary, best: Dictionary) -> void:
	## Later frames win the label, matching the order the score would reach them.
	if typeof(nav) != TYPE_DICTIONARY:
		return
	var entry: Dictionary = nav
	if _s(entry.get("kind", "")).to_lower() != "movie":
		return
	var target := _s(entry.get("value", ""))
	if target == "" or not is_hub(target):
		return
	distinct[target.to_lower()] = true
	best["movie"] = target
	best["label"] = _s(entry.get("label", ""))
	best["frame"] = entry.get("frame", null)


func clear_cache() -> void:
	_hub_return_cache.clear()
