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
## Null unless PIPOSH2_TRACE asked for dispatch records — see lingo/lingo_trace.gd.
var trace: LingoTrace = null

## Loaded bundle directories, so a movie change only pays for what is new.
var _loaded: Dictionary = {}
## movie -> channel -> [{start, end, script: [castLib, member]}]
var _intervals: Dictionary = {}
var _current_movie: String = ""
## dir name -> bundle keys, so member lookups do not hit the filesystem.
var _cast_keys: Dictionary = {}
## dir name -> handler name -> {handler, cast, script}. Indexed as a directory is
## scanned, which happens once per session, so re-entering a movie rebuilds its
## table from the cache rather than from disk.
var _handlers_by_dir: Dictionary = {}
## The current movie's own table and the archive its linked casts supply, kept
## apart so resolution can say which tier answered.
var _movie_table: Dictionary = {}
var _archive_table: Dictionary = {}
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
	var archive_dirs := PackedStringArray()
	if runtime != null and runtime.get("loader") != null:
		var libs: Dictionary = runtime.loader.cast_libs
		for key in libs.keys():
			var entry: Variant = libs[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var name := str((entry as Dictionary).get("name", "")).strip_edges()
			if name == "" or name.to_lower() == "internal":
				continue
			var dir_name := name.to_upper()
			_load_bundles_for(dir_name)
			if dir_name != _current_movie and not archive_dirs.has(dir_name):
				archive_dirs.append(dir_name)
	_install_handler_table(archive_dirs)
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
				_index_movie_handlers(dir_name, parsed as Dictionary)
		file = dir.get_next()
	dir.list_dir_end()


func _index_movie_handlers(dir_name: String, bundle: Dictionary) -> void:
	## A MovieScript's handlers are the ones reachable without a sprite or member
	## to hang them off, which is what a handler table holds. Indexed per
	## directory, because the directory is what owns them: a movie's own casts
	## fill its own table, a cast library's fill the shared archive.
	##
	## `cast` has to be spelled exactly as `load_bundle` keys `_scripts`,
	## "<dir>/<cast>", or `call_handler` looks the owning script up, finds
	## nothing, and the handler runs with no script to resolve or report from.
	var cast := "%s/%s" % [dir_name, str(bundle.get("cast", ""))]
	var table: Dictionary = _handlers_by_dir.get(dir_name, {})
	var scripts: Dictionary = bundle.get("scripts", {})
	for script_name in scripts.keys():
		if not str(script_name).to_lower().begins_with("moviescript"):
			continue
		var ast: Dictionary = scripts[script_name]
		for handler in ast.get("handlers", []):
			var key := str((handler as Dictionary).get("name", "")).to_lower()
			if key == "" or table.has(key):
				continue
			table[key] = {"handler": handler, "cast": cast, "script": str(script_name),
				"owner": dir_name}
	_handlers_by_dir[dir_name] = table


func _install_handler_table(archive_dirs: PackedStringArray) -> void:
	## Director builds a movie's handler table from that movie's own casts, and a
	## handler another movie defines is not reachable at all. Both tables are
	## replaced wholesale on every movie change, so nothing the previous movie
	## loaded survives into the next one.
	##
	## The archive is the casts *this* movie links, not every cast the session has
	## ever loaded. WONDER, ISLAND2 and BOOK all define `peoplefunk`, so an archive
	## that accumulated would make a movie's resolution depend on which rooms the
	## player passed through on the way in.
	_movie_table = (_handlers_by_dir.get(_current_movie, {}) as Dictionary).duplicate()
	_archive_table = {}
	for dir_name in archive_dirs:
		var table: Dictionary = _handlers_by_dir.get(dir_name, {})
		for key in table.keys():
			if not _archive_table.has(key):
				_archive_table[key] = table[key]
	## The interpreter resolves script-to-script calls against its own table, so
	## the scoping has to reach that table and not only this file's dispatch.
	## Merged with the movie's own entries winning, which is the two-tier lookup:
	## the movie's casts first, the shared archive only after.
	var installed: Dictionary = _archive_table.duplicate()
	installed.merge(_movie_table, true)
	interpreter._movie_handlers = installed


func resolve_movie_handler(name: String) -> Dictionary:
	## Which definition wins for a movie-script handler name, and which tier
	## answered. Empty when the name is in neither table. Dispatch goes through
	## here, so anything else asking the same question gets the game's answer
	## rather than a second opinion.
	var key := name.to_lower()
	if _movie_table.has(key):
		return _resolution("movie", _movie_table[key])
	if _archive_table.has(key):
		return _resolution("archive", _archive_table[key])
	return {}


func _resolution(tier: String, entry: Dictionary) -> Dictionary:
	## `handler` is the AST `call_handler` invokes, not a second lookup of it, so
	## a caller checking what actually runs cannot be fooled by the owner label
	## this table wrote next to it.
	return {
		"tier": tier,
		"owner": str(entry.get("owner", "")),
		"cast": str(entry.get("cast", "")),
		"script": str(entry.get("script", "")),
		"handler": entry.get("handler", {}),
	}


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
		_trace_dispatch(event, "behaviour", channel, behaviour)
		return true

	var sprite := _sprite_in_frame(channel, frame_index)
	if not sprite.is_empty():
		var member_script := script_for_member(
			int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0)))
		if not member_script.is_empty() and interpreter.run_handler_in_script(member_script, event):
			_trace_dispatch(event, "member", channel, member_script)
			return true

	var frame := frame_script(frame_index)
	if not frame.is_empty() and interpreter.run_handler_in_script(frame, event):
		_trace_dispatch(event, "frame", channel, frame)
		return true

	var resolved := resolve_movie_handler(event)
	if not resolved.is_empty():
		_trace_movie_dispatch(event, channel, resolved)
		interpreter.call_handler(event)
		return true
	if trace != null:
		trace.dispatch(event, "unresolved", channel, "", "", "", false)
	missing_handlers["%s:ch%d" % [event, channel]] = true
	_report_unresolved(event)
	return false


func _trace_dispatch(event: String, source: String, channel: int, script: Dictionary) -> void:
	## A record at each tier that answers, not only at the movie tier. The movie
	## tier is the last resort in dispatch_sprite_event, so hooking resolution
	## alone would trace the rarest source and miss every sprite behaviour — and
	## "the source type" is the one field a dispatch record exists to carry.
	## Movie-script identity still comes only from resolve_movie_handler; see
	## _trace_movie_dispatch.
	if trace == null:
		return
	trace.dispatch(event, source, channel, str(script.get("script", "")),
		LingoTrace.UNAVAILABLE, "", true)


func _trace_movie_dispatch(event: String, channel: int, resolved: Dictionary) -> void:
	if trace == null:
		return
	trace.dispatch(event, "movie", channel, str(resolved.get("script", "")),
		str(resolved.get("cast", "")), str(resolved.get("tier", "")), true)


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
			_trace_dispatch(event, "behaviour", channel, behaviour)
			ran += 1
	host.click_on = 0
	return ran


func dispatch_frame_event(event: String, frame_index: int) -> bool:
	host.click_on = 0
	host.begin_dispatch()
	interpreter.reset_steps()
	var frame := frame_script(frame_index)
	if not frame.is_empty() and interpreter.run_handler_in_script(frame, event):
		_trace_dispatch(event, "frame", 0, frame)
		return true
	var resolved := resolve_movie_handler(event)
	if not resolved.is_empty():
		_trace_movie_dispatch(event, 0, resolved)
		interpreter.call_handler(event)
		return true
	if trace != null:
		trace.dispatch(event, "unresolved", 0, "", "", "", false)
	_report_unresolved(event)
	return false


func _report_unresolved(event: String) -> void:
	## A name that reached the movie-script tier and resolved in neither table.
	## Deduplicated by the sink, so an event the game raises on every frame and
	## nobody handles costs one entry and not one per frame.
	interpreter.report(LingoDiagnostics.EVENT, event)


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
		"movie_handlers_own": _movie_table.size(),
		"movie_handlers_archive": _archive_table.size(),
		"interval_channels": (_intervals.get(_current_movie, {}) as Dictionary).size(),
		"unhandled_builtins": host.unhandled_names(),
		"errors": interpreter.errors,
		"diagnostics": interpreter.diagnostics.entries(),
		"diagnostics_dropped": interpreter.diagnostics.dropped,
	}
