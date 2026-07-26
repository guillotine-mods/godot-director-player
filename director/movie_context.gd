class_name MovieContext
extends RefCounted
## Per-movie context the render_model export cannot carry.
##
## Hub membership, walk-transition destinations and playability lived in Lingo
## movie scripts rather than in the score, so they are not recoverable from
## frames.json. Hand-maintained parts come from data/movie_context.json; the
## rest is derived from the loaded movie.

const CONTEXT_PATH := "res://data/movie_context.json"
const DOORWAY_PATH := "res://data/walk_doorways.json"

var hubs: PackedStringArray = PackedStringArray(["DAY1", "HOTEL1", "NIGHT1"])

var _walk_doorways: Dictionary = {}

var _shared_transitions: Dictionary = {}
var _movie_transitions: Dictionary = {}
var _known_unmapped: Dictionary = {}
var _hub_return_cache: Dictionary = {}
var _warned_transitions: Dictionary = {}
var _sprite_gates: Dictionary = {}
var _click_flags: Dictionary = {}
var _meeting_triggers: Array = []
var _phase_transitions: Array = []
var _day_advance: Array = []


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

	var triggers_value: Variant = data.get("meeting_triggers", [])
	if typeof(triggers_value) == TYPE_ARRAY:
		_meeting_triggers = triggers_value
	var phases_value: Variant = data.get("phase_transitions", [])
	if typeof(phases_value) == TYPE_ARRAY:
		_phase_transitions = phases_value
	var advance_value: Variant = data.get("day_advance", [])
	if typeof(advance_value) == TYPE_ARRAY:
		_day_advance = advance_value

	var click_value: Variant = data.get("click_flags", {})
	if typeof(click_value) == TYPE_DICTIONARY:
		for key in (click_value as Dictionary).keys():
			var rules: Variant = (click_value as Dictionary)[key]
			if typeof(rules) == TYPE_ARRAY:
				_click_flags[_s(key).to_lower()] = rules

	var gates_value: Variant = data.get("sprite_gates", {})
	if typeof(gates_value) == TYPE_DICTIONARY:
		for key in (gates_value as Dictionary).keys():
			var rules: Variant = (gates_value as Dictionary)[key]
			if typeof(rules) == TYPE_ARRAY:
				_sprite_gates[_s(key).to_lower()] = rules

	_load_walk_doorways()
	return OK


func _load_walk_doorways() -> void:
	## Per-hotspot walk targets recovered from the export; see the file's own
	## comment. Absent means every hotspot keeps its exported (label-keyed) nav.
	_walk_doorways.clear()
	if not FileAccess.file_exists(DOORWAY_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DOORWAY_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Malformed walk doorways: %s" % DOORWAY_PATH)
		return
	var overrides_value: Variant = (parsed as Dictionary).get("overrides", {})
	if typeof(overrides_value) != TYPE_DICTIONARY:
		return
	for movie in (overrides_value as Dictionary).keys():
		var entries: Variant = (overrides_value as Dictionary)[movie]
		if typeof(entries) == TYPE_DICTIONARY:
			_walk_doorways[_s(movie).to_lower()] = entries


func walk_override(movie: String, room: String, channel: int, target_label: String) -> Dictionary:
	## Corrected walk_to / arrive_at for one exit, or empty to keep the export's.
	##
	## The export stores both points once per destination label, so every exit
	## into the same room shares one room's coordinates and all but one of them
	## sends Piposh the wrong way.
	if target_label == "":
		return {}
	var entries_value: Variant = _walk_doorways.get(movie.to_lower(), {})
	if typeof(entries_value) != TYPE_DICTIONARY:
		return {}
	var key := "%s|%d|%s" % [_room_key(room), channel, target_label.to_lower()]
	var entry: Variant = (entries_value as Dictionary).get(key, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	return entry


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
	## True while the sprites belong on screen.
	##
	## Conditions are a window, not just a start: content can be premature
	## (a corpse before the murder) or stale (a character still sitting where
	## they were before a conversation moved them), so every condition has a
	## "not yet" and an "already over" form.
	var after_meeting: Variant = rule.get("after_meeting", null)
	if after_meeting != null and not GameState.is_meeting_done(_s(after_meeting)):
		return false
	var before_meeting: Variant = rule.get("before_meeting", null)
	if before_meeting != null and GameState.is_meeting_done(_s(before_meeting)):
		return false

	var after_flag: Variant = rule.get("after_flag", null)
	if after_flag != null and not GameState.has_story_flag(_s(after_flag)):
		return false
	var before_flag: Variant = rule.get("before_flag", null)
	if before_flag != null and GameState.has_story_flag(_s(before_flag)):
		return false

	var from_day: Variant = rule.get("from_day", null)
	if from_day != null and GameState.globalday < int(from_day):
		return false
	var until_day: Variant = rule.get("until_day", null)
	if until_day != null and GameState.globalday > int(until_day):
		return false
	return true


func flag_for_click(movie: String, room: String, channel: int) -> String:
	## A hotspot that reveals something: clicking it raises a story flag that a
	## sprite gate can wait on. Lingo did this with globals plus puppetSprite.
	var rules_value: Variant = _click_flags.get(movie.to_lower(), [])
	if typeof(rules_value) != TYPE_ARRAY:
		return ""
	var wanted := _room_key(room)
	for rule_value in (rules_value as Array):
		if typeof(rule_value) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_value
		if not _rule_covers_room(rule, wanted):
			continue
		var channels_value: Variant = rule.get("channels", [])
		if typeof(channels_value) != TYPE_ARRAY:
			continue
		for ch in (channels_value as Array):
			if int(ch) == channel:
				return _s(rule.get("sets_flag", ""))
	return ""


func meeting_triggers() -> Array:
	return _meeting_triggers


func phase_transition(hub: String, day: int) -> Dictionary:
	## The hub that takes over once this one is finished with the player.
	##
	## Inferred, not sourced: no DAY1 to NIGHT1 edge exists anywhere in the
	## score, because the original made that jump from Lingo globals.
	##
	## Returns the destination plus a one-shot flag. NIGHT1 declares a route
	## back to DAY1 @fort, so without the flag a player who walks back would be
	## thrown straight to night again, forever.
	for rule_value in _phase_transitions:
		if typeof(rule_value) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_value
		if _s(rule.get("from_hub", "")).to_lower() != hub.to_lower():
			continue
		if rule.get("day") != null and int(rule.get("day")) != day:
			continue
		var required: Variant = rule.get("require_meetings", [])
		if typeof(required) != TYPE_ARRAY:
			continue
		var satisfied := true
		for meeting in (required as Array):
			if not GameState.is_meeting_done(_s(meeting)):
				satisfied = false
				break
		if not satisfied:
			continue
		var destination := _s(rule.get("to_movie", ""))
		if destination == "":
			continue
		var flag := "phase:%s>%s:day%d" % [hub.to_lower(), destination.to_lower(), day]
		if GameState.has_story_flag(flag):
			continue
		return {"movie": destination, "flag": flag}
	return {}


func day_for_arrival(movie: String, label: String) -> int:
	## -1 when arriving here does not turn the day over.
	if label == "":
		return -1
	for rule_value in _day_advance:
		if typeof(rule_value) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = rule_value
		if _s(rule.get("movie", "")).to_lower() != movie.to_lower():
			continue
		if _s(rule.get("label", "")).to_lower() != label.to_lower():
			continue
		return int(rule.get("set_day", -1))
	return -1


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
