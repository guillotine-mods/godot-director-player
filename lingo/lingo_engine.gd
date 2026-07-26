class_name LingoEngine
extends RefCounted
## Director's event model over the interpreter: which script receives a message,
## in which order.
##
## Director sends a mouse event down a hierarchy, and the first handler that
## exists wins. This port needs four levels:
##
##   1. the sprite's behaviour, from the score's frame intervals
##      (data/lingo/<MOVIE>/sprite_scripts.json, see tools/dump_sprite_scripts.py)
##   2. the script attached to the cast member the sprite displays
##   3. the frame script, which the export already carries as `frame_script`
##   4. any movie script
##
## Frame events (`enterFrame`, `exitFrame`) skip level 1 and 2 and start at the
## frame script, which is how the score's script channel works.

const LINGO_ROOT := "res://data/lingo"

var interpreter: LingoInterpreter
var host: LingoHost
var runtime: Object = null

## Loaded bundle directories, so a movie change only pays for what is new.
var _loaded: Dictionary = {}
## movie -> channel -> [{start, end, script: [castLib, member]}]
var _intervals: Dictionary = {}
var _current_movie: String = ""
## dir name -> bundle keys, so member lookups do not hit the filesystem.
var _cast_keys: Dictionary = {}
## Names of scripts that were reached but had no handler for the event, for
## reporting. Not an error: falling through is normal.
var missing_handlers: Dictionary = {}


func _init(director_runtime: Object) -> void:
	runtime = director_runtime
	host = LingoHost.new(director_runtime)
	interpreter = LingoInterpreter.new(host)
	host.interpreter = interpreter


func prepare_movie(movie: String) -> void:
	## Load the movie's own scripts, every linked cast it uses, and its intervals.
	if movie == "":
		return
	_current_movie = movie.to_upper()
	_load_bundles_for(_current_movie)
	if runtime != null and runtime.get("loader") != null:
		var libs: Dictionary = runtime.loader.cast_libs
		for key in libs.keys():
			var entry: Variant = libs[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var name := str((entry as Dictionary).get("name", "")).strip_edges()
			if name == "" or name.to_lower() == "internal":
				continue
			_load_bundles_for(name.to_upper())
	_load_intervals(_current_movie)


func _load_bundles_for(dir_name: String) -> void:
	if _loaded.has(dir_name):
		return
	_loaded[dir_name] = true
	var dir := DirAccess.open("%s/%s" % [LINGO_ROOT, dir_name])
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".json") and file != "attach.json" and file != "sprite_scripts.json":
			var text := FileAccess.get_file_as_string("%s/%s/%s" % [LINGO_ROOT, dir_name, file])
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				interpreter.load_bundle(parsed, dir_name)
		file = dir.get_next()
	dir.list_dir_end()


func _load_intervals(movie: String) -> void:
	if _intervals.has(movie):
		return
	var path := "%s/%s/sprite_scripts.json" % [LINGO_ROOT, movie]
	var by_channel: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			for interval in (parsed as Dictionary).get("intervals", []):
				if typeof(interval) != TYPE_DICTIONARY:
					continue
				var channel := int((interval as Dictionary).get("channel", -1))
				if channel < 0:
					continue
				if not by_channel.has(channel):
					by_channel[channel] = []
				(by_channel[channel] as Array).append(interval)
	_intervals[movie] = by_channel


## ------------------------------------------------------------ resolution


func _cast_dir_for_lib(cast_lib: int) -> String:
	## The interval names a cast library index. Index 1 is the movie's own cast,
	## whose bundle sits under the movie's directory; the rest are linked casts
	## named in summary.json.
	if runtime == null:
		return ""
	if cast_lib <= 1:
		return _current_movie
	var libs: Dictionary = runtime.loader.cast_libs
	var entry: Variant = libs.get(str(cast_lib), {})
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var name := str((entry as Dictionary).get("name", "")).strip_edges()
	return name.to_upper() if name != "" and name.to_lower() != "internal" else _current_movie


func _cast_key_for_dir(dir_name: String) -> PackedStringArray:
	## Cached: this sits under every member lookup, and the uncached version
	## opened and listed a directory each time.
	if _cast_keys.has(dir_name):
		return _cast_keys[dir_name]
	var keys := _scan_cast_keys(dir_name)
	_cast_keys[dir_name] = keys
	return keys


func _scan_cast_keys(dir_name: String) -> PackedStringArray:
	## Bundles are keyed by the cast name ProjectorRays used inside the movie
	## directory, which is not the cast-library name, so try all of them.
	var out := PackedStringArray()
	var dir := DirAccess.open("%s/%s" % [LINGO_ROOT, dir_name])
	if dir == null:
		return out
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".json") and file != "attach.json" and file != "sprite_scripts.json":
			out.append("%s/%s" % [dir_name, file.get_basename()])
		file = dir.get_next()
	dir.list_dir_end()
	return out


func script_for_member(cast_lib: int, member: int) -> Dictionary:
	var dir_name := _cast_dir_for_lib(cast_lib)
	if dir_name == "":
		return {}
	## ProjectorRays wrote a linked cast's scripts twice: once under the movie
	## that links it (data/lingo/DAY1/wonder.json) and once in the cast's own
	## standalone export (data/lingo/WONDER/External.json). The movie-local copy
	## is the one the attachment data refers to, so it has to win.
	##
	## Both used to be reachable by accident, because every bundle was keyed on
	## the ProjectorRays subdirectory and eleven casts are called "External".
	## Namespacing them fixed the collisions and lost this: DAY1 asking wonder
	## for member 231 stopped finding the igkey pickup, so picking a collectable
	## up fell through to the lifted export, which adds the item but has no way
	## to take the sprite off the stage. The shell stayed on the beach.
	for cast_key in _cast_key_for_dir(_current_movie):
		if cast_key.get_file().to_lower() == dir_name.to_lower():
			var local := interpreter.find_script_by_member(cast_key, member)
			if not local.is_empty():
				return local
	for cast_key in _cast_key_for_dir(dir_name):
		var script := interpreter.find_script_by_member(cast_key, member)
		if not script.is_empty():
			return script
	return {}


func behaviour_for_sprite(channel: int, frame_index: int) -> Dictionary:
	## Frame numbers in the score are 1-based.
	var by_channel: Variant = _intervals.get(_current_movie, {})
	if typeof(by_channel) != TYPE_DICTIONARY:
		return {}
	var list: Variant = (by_channel as Dictionary).get(channel, [])
	if typeof(list) != TYPE_ARRAY:
		return {}
	var frame := frame_index + 1
	for interval_value in list as Array:
		var interval: Dictionary = interval_value
		if frame < int(interval.get("start", 0)) or frame > int(interval.get("end", 0)):
			continue
		var script_ref: Variant = interval.get("script", null)
		if typeof(script_ref) != TYPE_ARRAY or (script_ref as Array).size() < 2:
			continue
		return script_for_member(int(script_ref[0]), int(script_ref[1]))
	return {}


func frame_script(frame_index: int) -> Dictionary:
	if runtime == null:
		return {}
	var frame: Dictionary = runtime.loader.get_frame(frame_index)
	var member: Variant = frame.get("frame_script", null)
	if member == null:
		return {}
	return script_for_member(1, int(member))


## ------------------------------------------------------------ dispatch


func dispatch_sprite_event(event: String, channel: int, frame_index: int) -> bool:
	## Returns true when some level of the hierarchy handled it.
	host.click_on = channel
	host.begin_dispatch()
	interpreter.reset_steps()

	var behaviour := behaviour_for_sprite(channel, frame_index)
	if not behaviour.is_empty() and interpreter.run_handler_in_script(behaviour, event):
		return true

	var sprite := _sprite_in_frame(channel, frame_index)
	if not sprite.is_empty():
		var member_script := script_for_member(
			int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0)))
		if not member_script.is_empty() and interpreter.run_handler_in_script(member_script, event):
			return true

	var frame := frame_script(frame_index)
	if not frame.is_empty() and interpreter.run_handler_in_script(frame, event):
		return true

	if interpreter.has_handler(event):
		interpreter.call_handler(event)
		return true
	missing_handlers["%s:ch%d" % [event, channel]] = true
	return false


func dispatch_sprite_behaviours(event: String, frame_index: int) -> int:
	## Director sends enterFrame and exitFrame to every sprite behaviour in the
	## frame, not only to the frame script. This game depends on it: `whereami`,
	## which 138 mouseUp handlers gate their real behaviour on, is set by an
	## `on enterFrame` in a sprite behaviour (`BehaviorScript 3 - b4 bk's`) rather
	## than by any frame script. Returns how many behaviours ran.
	var frame: Dictionary = {}
	if host != null and host.runtime != null:
		frame = host.runtime.loader.get_frame(frame_index)
	var ran := 0
	host.frame_event_depth += 1
	var seen: Dictionary = {}
	for sprite_value in frame.get("sprites", []):
		if typeof(sprite_value) != TYPE_DICTIONARY:
			continue
		var channel := int((sprite_value as Dictionary).get("channel", 0))
		if channel <= 0 or seen.has(channel):
			continue
		seen[channel] = true
		var behaviour := behaviour_for_sprite(channel, frame_index)
		if behaviour.is_empty() or not _script_handles(behaviour, event):
			continue
		host.click_on = channel
		interpreter.reset_steps()
		if interpreter.run_handler_in_script(behaviour, event):
			ran += 1
	host.click_on = 0
	host.frame_event_depth -= 1
	return ran


func dispatch_frame_event(event: String, frame_index: int) -> bool:
	host.click_on = 0
	host.begin_dispatch()
	interpreter.reset_steps()
	host.frame_event_depth += 1
	var frame := frame_script(frame_index)
	if not frame.is_empty() and interpreter.run_handler_in_script(frame, event):
		host.frame_event_depth -= 1
		return true
	if interpreter.has_handler(event):
		interpreter.call_handler(event)
		host.frame_event_depth -= 1
		return true
	host.frame_event_depth -= 1
	return false


func _sprite_in_frame(channel: int, frame_index: int) -> Dictionary:
	if runtime == null:
		return {}
	var frame: Dictionary = runtime.loader.get_frame(frame_index)
	for sprite in frame.get("sprites", []):
		if typeof(sprite) == TYPE_DICTIONARY and int((sprite as Dictionary).get("channel", 0)) == channel:
			return sprite
	return {}


func has_any_handler_for(channel: int, frame_index: int, event: String) -> bool:
	## Whether an interpreted script would take this click at all, so the runtime
	## can fall back to the exported on_click when it would not.
	var behaviour := behaviour_for_sprite(channel, frame_index)
	if _script_handles(behaviour, event):
		return true
	var sprite := _sprite_in_frame(channel, frame_index)
	if not sprite.is_empty():
		if _script_handles(script_for_member(
				int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0))), event):
			return true
	return _script_handles(frame_script(frame_index), event)


func _script_handles(script: Dictionary, event: String) -> bool:
	if script.is_empty():
		return false
	var key := event.to_lower()
	for handler in script.get("handlers", []):
		if str((handler as Dictionary).get("name", "")).to_lower() == key:
			return true
	return false


func stats() -> Dictionary:
	return {
		"scripts": interpreter.script_count(),
		"movie_handlers": interpreter.movie_handler_names().size(),
		"interval_channels": (_intervals.get(_current_movie, {}) as Dictionary).size(),
		"unhandled_builtins": host.unhandled_names(),
		"errors": interpreter.errors,
	}
