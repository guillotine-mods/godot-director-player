class_name RenderModelLoader
extends RefCounted
## Loads Director render_model JSON + BMP cast members for a movie.

const INDEX_PATH := "res://assets/render_model/index.json"
const CAST_REGISTRY_PATH := "res://assets/render_model/cast_registry.json"
## The sprite stretch flags the upstream exporter drops, recovered from the
## containers by `tools/generate_sprite_stretch.py`. See `_resolve_sprite_rects`.
const SPRITE_STRETCH_PATH := "res://assets/render_model/sprite_stretch.json"
const MODEL_ROOT := "res://assets/render_model"
## How a sprite's ink keys out its paper colour.
##
## Director draws these two differently and the difference is visible: Matte
## removes only the paper region reachable from the bitmap's edge, so white
## enclosed by artwork stays opaque, while Background Transparent keys the paper
## colour across the whole bitmap, interior pockets included. Ink 36 is by far
## the most common ink in this game (roughly 49k sprite records in DAY1 against
## 15k for ink 8) and it is what characters use, so treating it as Matte left
## white patches wherever the paper was enclosed by artwork.
enum Transparency { NONE, MATTE, BACKGROUND }

## 8=Matte, 9=Mask key only the edge-reachable paper.
const MATTE_INKS := [8, 9]
## 1=Transparent, 36=Background Transparent, 39=Ghost-ish in some exports.
const BACKGROUND_INKS := [1, 36, 39]
const MATTE_TOLERANCE := 14.0 / 255.0
## Widest a member may be and still be treated as cursor art. `trgcur` at 17x17 is
## the largest the game actually uses.
const MAX_CURSOR_SIZE := 32
## Paper is near-white; at or above this in all three channels counts as paper.
const PAPER_MIN_BYTE := 241

var index: Dictionary = {}
var cast_registry: Dictionary = {}
## Which sprite records the score marks as stretched, per movie. A movie absent
## from this is a movie whose score could not be read back, and its rects are left
## exactly as exported.
var sprite_stretch: Dictionary = {}
## Whether the loaded movie's stretch flags were recovered, and how many of its
## sprite rects that put back to the member's own size. Read by
## `tools/sprite_stretch.gd`.
var stretch_flags_known: bool = false
var resolved_sprite_rects: int = 0
var skipped_film_loop_rects: int = 0
var movie_name: String = ""
var frames: Array = []
var members: Dictionary = {}
var cast_libs: Dictionary = {}
var labels: Dictionary = {}
var markers: Array = []
var stage_size := Vector2i(640, 480)
var first_playable_frame: int = 0
var base_path: String = ""

var _texture_cache: Dictionary = {}
var _matte_cache: Dictionary = {}
var _resolved_member_cache: Dictionary = {}
var _missing_member_keys: Dictionary = {}
## Channels this movie's score uses anywhere, computed once per movie. Answers "does
## this channel belong to this movie at all", which is not the same question as "is it
## in the current frame": a room transition span carries no channel 30 even though
## Piposh is standing in it.
var _score_channels: Dictionary = {}
var _missing_linked_member_keys: Dictionary = {}
var _missing_texture_keys: Dictionary = {}
var _registry_member_cache: Dictionary = {}
var _missing_registry_member_keys: Dictionary = {}
var _registry_texture_cache: Dictionary = {}
var _missing_registry_texture_keys: Dictionary = {}
var _film_loop_cache: Dictionary = {}
var _missing_film_loop_keys: Dictionary = {}
## Composed cursor images, keyed by the member pair. Small and few — the game uses
## nine distinct cursors — so they are held for the life of the movie.
var _cursor_cache: Dictionary = {}


func load_index() -> Error:
	if not FileAccess.file_exists(INDEX_PATH) or not FileAccess.file_exists(CAST_REGISTRY_PATH):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	var registry_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAST_REGISTRY_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(registry_parsed) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	var casts: Variant = registry_parsed.get("casts", {})
	if typeof(casts) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	index = parsed
	cast_registry = _resolve_cast_aliases(casts)
	sprite_stretch = _load_sprite_stretch()
	return OK


func _load_sprite_stretch() -> Dictionary:
	## Missing is not fatal: without it every movie keeps the rects the exporter
	## wrote, which is what the port did before the flags were recovered.
	##
	## Flattened to `{movie: {frame index: channels}}` with real integers on the way
	## in. `JSON.parse_string` produces floats and string keys, so the frame lookup
	## and the channel test would both silently miss — which they did, and the two
	## stretched sprites the harness checks were shrunk like the rest.
	if not FileAccess.file_exists(SPRITE_STRETCH_PATH):
		push_warning("No sprite_stretch.json; score sprite rects are used as exported")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPRITE_STRETCH_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("sprite_stretch.json is not readable; rects are used as exported")
		return {}
	var movies: Variant = (parsed as Dictionary).get("movies", {})
	if typeof(movies) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for movie in (movies as Dictionary).keys():
		var entry: Variant = (movies as Dictionary)[movie]
		var by_frame: Dictionary = {}
		var stretched: Variant = (
			(entry as Dictionary).get("frames", {}) if typeof(entry) == TYPE_DICTIONARY else {}
		)
		if typeof(stretched) == TYPE_DICTIONARY:
			for key in (stretched as Dictionary).keys():
				var channels: Variant = (stretched as Dictionary)[key]
				if typeof(channels) != TYPE_ARRAY:
					continue
				var numbers := PackedInt32Array()
				for channel in channels as Array:
					numbers.append(int(channel))
				by_frame[int(str(key))] = numbers
		out[str(movie)] = by_frame
	return out


func _resolve_cast_aliases(casts: Dictionary) -> Dictionary:
	## A movie can link the same cast file under two names: `ISHDAY1` links
	## `hezi.cst` as both `hezi` and `hezi1`. The generator records the second as
	## `{"alias_of": "hezi"}` rather than duplicating 474 members on disk, so the
	## alias is pointed at the real cast here. Doing it once at load keeps every
	## `cast_registry` lookup a plain dictionary access.
	for name in casts.keys():
		var cast: Variant = casts[name]
		if typeof(cast) != TYPE_DICTIONARY:
			continue
		var target: Variant = (cast as Dictionary).get("alias_of", null)
		if typeof(target) != TYPE_STRING:
			continue
		var resolved: Variant = casts.get(target, null)
		if typeof(resolved) == TYPE_DICTIONARY and not (resolved as Dictionary).has("alias_of"):
			casts[name] = resolved
		else:
			push_warning("Cast alias %s points at missing cast %s" % [name, target])
	return casts


func available_movies() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry in index.get("exports", []):
		if typeof(entry) == TYPE_DICTIONARY and entry.has("movie"):
			out.append(str(entry.movie))
	return out


func load_movie(name: String) -> Error:
	var next_base_path := "%s/%s" % [MODEL_ROOT, name]
	var frames_path := "%s/frames.json" % next_base_path
	var members_path := "%s/members.json" % next_base_path
	if not FileAccess.file_exists(frames_path) or not FileAccess.file_exists(members_path):
		return ERR_FILE_NOT_FOUND

	var frames_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	var members_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(members_path))
	if typeof(frames_json) != TYPE_DICTIONARY or typeof(members_json) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA

	var next_frames: Variant = frames_json.get("frames", [])
	var next_labels: Variant = frames_json.get("labels", {})
	var next_markers: Variant = frames_json.get("markers", [])
	var next_cast_libs: Variant = frames_json.get(
		"cast_libs",
		members_json.get("cast_libs", {})
	)
	var next_members: Variant = members_json.get("members", {})
	var next_stage: Variant = frames_json.get("stage", {})
	if (
		typeof(next_frames) != TYPE_ARRAY
		or typeof(next_labels) != TYPE_DICTIONARY
		or typeof(next_markers) != TYPE_ARRAY
		or typeof(next_cast_libs) != TYPE_DICTIONARY
		or typeof(next_members) != TYPE_DICTIONARY
		or typeof(next_stage) != TYPE_DICTIONARY
	):
		return ERR_INVALID_DATA

	var next_first_playable_frame := int(frames_json.get("first_playable_frame", 0))
	var next_stage_size := Vector2i(
		int(next_stage.get("width", 640)),
		int(next_stage.get("height", 480))
	)

	movie_name = name
	base_path = next_base_path
	frames = next_frames
	labels = next_labels
	markers = next_markers
	cast_libs = next_cast_libs
	members = next_members
	first_playable_frame = next_first_playable_frame
	stage_size = next_stage_size
	_score_channels.clear()
	_texture_cache.clear()
	_matte_cache.clear()
	_resolved_member_cache.clear()
	_missing_member_keys.clear()
	_missing_linked_member_keys.clear()
	_missing_texture_keys.clear()
	_registry_member_cache.clear()
	_missing_registry_member_keys.clear()
	_registry_texture_cache.clear()
	_missing_registry_texture_keys.clear()
	_film_loop_cache.clear()
	_missing_film_loop_keys.clear()
	# Keyed by member number, which means nothing across a movie: `1:10:11` is
	# `wlkcur` in DAY1 and whatever holds 10 and 11 in the next one. The gated
	# movies happen to agree — every cursor member is byte-identical across DAY1,
	# AIR1, HOTEL1 and SEA1 — but CHESS sets its own from `cc1`/`cc1b` and is not
	# in cursorfunk's gate, so a collision there would serve DAY1's art.
	_cursor_cache.clear()
	_resolve_sprite_rects()
	return OK


func _resolve_sprite_rects() -> void:
	## Put back the rect Director would have drawn, for every sprite the score does
	## not mark as stretched.
	##
	## A Director sprite draws its member at the member's own size and anchors it on
	## the member's registration point. The width and height in the score are the
	## drawn rect only when the sprite's stretch flag is set; with it clear they are
	## authoring residue — whatever the channel was last resized to, or the size of
	## a member that used to be there. The upstream exporter masks the score's ink
	## byte to its low 6 bits, which throws the flag away, and writes the residue
	## into `frames.json` regardless, so the port scaled 22,806 sprite records to a
	## rect the original ignores — 9,185 of them members `members.json` describes and
	## 13,621 resolved through `cast_registry.json`.
	##
	## ALLIN is the case that shows it: channel 1 holds member `1:1`, a whole hotel
	## room, at the same registration point for all 1438 frames, and the stored
	## width is 1280 on 835 of them, 640 on 259 and 639 on 337. The member's raster
	## is 640 wide. A backdrop that never moves cannot be twice its own width on
	## some frames and 0.998 of it on others; Director drew 640 throughout, and the
	## player saw the right half of the room at double size for most of the scene.
	##
	## Done here, once per movie load, so the channel array, the draw path, hit
	## testing and any script reading the sprite all see one rect. Film loops are
	## left alone: they are scaled against their own initial rect, and the score
	## already agrees with that rect on all 37,329 unstretched film-loop records.
	resolved_sprite_rects = 0
	skipped_film_loop_rects = 0
	stretch_flags_known = sprite_stretch.has(movie_name)
	if not stretch_flags_known:
		return
	var stretched_frames: Dictionary = sprite_stretch[movie_name]
	# One entry per distinct member rather than per sprite record: DAY1 has 40,297
	# records over a few hundred members, and both lookups below format their cache
	# key as a string before they reach their own cache. Keyed on an int so this one
	# does not. Empty means "no bitmap geometry here", which includes film loops.
	var geometry: Dictionary = {}
	var film_loops: Dictionary = {}

	for index in frames.size():
		var frame: Variant = frames[index]
		if typeof(frame) != TYPE_DICTIONARY:
			continue
		var sprites: Variant = (frame as Dictionary).get("sprites", [])
		if typeof(sprites) != TYPE_ARRAY:
			continue
		var stretched_channels: PackedInt32Array = stretched_frames.get(
			index, PackedInt32Array()
		)
		for sprite_value in sprites as Array:
			if typeof(sprite_value) != TYPE_DICTIONARY:
				continue
			var sprite: Dictionary = sprite_value
			if stretched_channels.has(int(sprite.get("channel", 0))):
				# Kept for `SpriteChannel.set_member`, which must not re-anchor a
				# stretched sprite on a new member's registration point.
				sprite["stretch"] = true
				continue
			var cast_lib := int(sprite.get("cast_lib", 1))
			var cast_id := int(sprite.get("cast_id", 0))
			var geometry_key := cast_lib * 100000 + cast_id
			if not geometry.has(geometry_key):
				var is_loop := not get_film_loop(cast_lib, cast_id).is_empty()
				var found: Dictionary = {} if is_loop else member_if_known(cast_lib, cast_id)
				if (
					float(found.get("width", 0.0)) <= 0.0
					or float(found.get("height", 0.0)) <= 0.0
				):
					found = {}
				geometry[geometry_key] = found
				film_loops[geometry_key] = is_loop
			var member: Dictionary = geometry[geometry_key]
			if member.is_empty():
				if film_loops[geometry_key]:
					skipped_film_loop_rects += 1
				continue
			var width := float(member.get("width"))
			var height := float(member.get("height"))
			if is_equal_approx(float(sprite.get("width", 0.0)), width) and is_equal_approx(
				float(sprite.get("height", 0.0)), height
			):
				continue
			var loc_h := float(sprite.get("loc_h", sprite.get("x", 0)))
			var loc_v := float(sprite.get("loc_v", sprite.get("y", 0)))
			sprite["width"] = width
			sprite["height"] = height
			sprite["x"] = loc_h - float(member.get("reg_offset_x", width * 0.5))
			sprite["y"] = loc_v - float(member.get("reg_offset_y", height * 0.5))
			resolved_sprite_rects += 1


func score_uses_channel(channel: int) -> bool:
	## Whether the movie's score mentions this channel on any frame.
	##
	## Used to decide whether a channel belongs to the loaded movie at all. Piposh is
	## channel 30, and JOKE — a Movie In A Window with its own channels — never uses it,
	## so nothing of his may be drawn there. Asking per frame instead breaks the walk:
	## a transition span such as `edge3up` carries no channel 30 for twelve frames while
	## Piposh is mid-animation, and DAY1's `puppetSprite(30, 1)` runs once in `init all`
	## and is lost with the channels on the next movie change, so the puppet flag cannot
	## be relied on to carry him through.
	if _score_channels.is_empty():
		for frame in frames:
			if typeof(frame) != TYPE_DICTIONARY:
				continue
			for sprite in (frame as Dictionary).get("sprites", []):
				if typeof(sprite) == TYPE_DICTIONARY:
					_score_channels[int((sprite as Dictionary).get("channel", 0))] = true
	return _score_channels.has(channel)


func lookup_label(name: String) -> int:
	if labels.has(name):
		return int(labels[name])
	var lower := name.to_lower()
	for key in labels.keys():
		if str(key).to_lower() == lower:
			return int(labels[key])
	return -1


func resolve_label(name: String, prefer_go: bool = false) -> int:
	if prefer_go and not name.to_lower().ends_with("go"):
		var go_frame := lookup_label("%sgo" % name)
		if go_frame >= 0:
			return go_frame
	return lookup_label(name)


func resolve_boot_frame() -> int:
	var idx := first_playable_frame
	if movie_name.to_lower() == "strtgame":
		var menu := lookup_label("mainmenu")
		if menu >= 0:
			return menu
	for marker in markers:
		if typeof(marker) != TYPE_DICTIONARY:
			continue
		if int(marker.get("frame", -1)) == idx:
			var mname := str(marker.get("name", ""))
			if not mname.is_empty() and not mname.to_lower().ends_with("go"):
				var go_frame := lookup_label("%sgo" % mname)
				if go_frame >= 0:
					return go_frame
			break
	return idx


func get_frame(index: int) -> Dictionary:
	if frames.is_empty():
		return {}
	var i := clampi(index, 0, frames.size() - 1)
	var frame: Variant = frames[i]
	return frame if typeof(frame) == TYPE_DICTIONARY else {}


func member_key(cast_lib: int, cast_id: int) -> String:
	var lib_id := "%d:%d" % [cast_lib, cast_id]
	if members.has(lib_id):
		return lib_id
	var bare := str(cast_id)
	if cast_lib == 1 and members.has(bare):
		return bare
	return lib_id


func _linked_cast_name(cast_lib: int) -> String:
	var library: Variant = cast_libs.get(str(cast_lib), {})
	if typeof(library) != TYPE_DICTIONARY:
		return ""
	var name: Variant = library.get("name", "")
	var resolved: String = name.strip_edges().to_lower() if typeof(name) == TYPE_STRING else ""
	# Every movie calls its own cast "internal", so that name identifies nothing in
	# a registry shared by all of them. The movie's own name does, and it is what
	# the registry keys a movie's internal cast under. Without this, a film loop
	# living in the movie's own cast — which is where MURDER1 keeps `tofi right`
	# and `goldolin left` — could never be looked up.
	if resolved == "internal" or resolved == "":
		return movie_name.strip_edges().to_lower()
	return resolved


func cast_lib_index(name: String) -> int:
	## Linked libraries sit at a different index in every movie: `master` is 2
	## in DAY1, 3 in HOTEL1, 4 in SEA1. Returns -1 when the movie does not link
	## the library at all.
	var wanted := name.strip_edges().to_lower()
	for key in cast_libs.keys():
		var library: Variant = cast_libs[key]
		if typeof(library) != TYPE_DICTIONARY:
			continue
		var lib_name: Variant = (library as Dictionary).get("name", "")
		if typeof(lib_name) != TYPE_STRING:
			continue
		if str(lib_name).strip_edges().to_lower() == wanted:
			return int(key)
	return -1


func get_film_loop(cast_lib: int, cast_id: int) -> Dictionary:
	var cache_key := "%d:%d" % [cast_lib, cast_id]
	if _film_loop_cache.has(cache_key):
		return _film_loop_cache[cache_key]
	if _missing_film_loop_keys.has(cache_key):
		return {}
	var local_member: Variant = members.get(member_key(cast_lib, cast_id), {})
	if typeof(local_member) == TYPE_DICTIONARY and not local_member.is_empty():
		return _cache_missing_film_loop(cache_key)

	var cast_name := _linked_cast_name(cast_lib)
	var registry_cast: Variant = cast_registry.get(cast_name, {})
	if typeof(registry_cast) != TYPE_DICTIONARY:
		return _cache_missing_film_loop(cache_key)
	var film_loops: Variant = registry_cast.get("film_loops", {})
	if typeof(film_loops) != TYPE_DICTIONARY:
		return _cache_missing_film_loop(cache_key)
	var film_loop: Variant = film_loops.get(str(cast_id), {})
	if typeof(film_loop) != TYPE_DICTIONARY or film_loop.is_empty():
		return _cache_missing_film_loop(cache_key)
	var initial_rect: Variant = film_loop.get("initial_rect", {})
	var loop_frames: Variant = film_loop.get("frames", [])
	if (
		not _is_valid_film_loop_rect(initial_rect)
		or int(film_loop.get("width", 0)) <= 0
		or int(film_loop.get("height", 0)) <= 0
		or not _has_valid_film_loop_frames(loop_frames)
	):
		return _cache_missing_film_loop(cache_key)
	var resolved_loop: Dictionary = film_loop.duplicate(true)
	resolved_loop["_registry_cast_name"] = cast_name
	_film_loop_cache[cache_key] = resolved_loop
	return resolved_loop


func _is_valid_film_loop_rect(rect: Variant) -> bool:
	if typeof(rect) != TYPE_DICTIONARY:
		return false
	for edge in ["top", "left", "bottom", "right"]:
		if not rect.has(edge) or typeof(rect[edge]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
	return float(rect["right"]) > float(rect["left"]) and float(rect["bottom"]) > float(rect["top"])


func _has_valid_film_loop_frames(loop_frames: Variant) -> bool:
	if typeof(loop_frames) != TYPE_ARRAY or loop_frames.is_empty():
		return false
	for frame in loop_frames:
		if typeof(frame) != TYPE_DICTIONARY or typeof(frame.get("sprites", null)) != TYPE_ARRAY:
			return false
	return true


func _cache_missing_film_loop(cache_key: String) -> Dictionary:
	_missing_film_loop_keys[cache_key] = true
	return {}


func get_registry_member(cast_name: String, cast_id: int) -> Dictionary:
	var normalized_cast_name := cast_name.strip_edges().to_lower()
	var cache_key := "%s:%d" % [normalized_cast_name, cast_id]
	if _registry_member_cache.has(cache_key):
		return (_registry_member_cache[cache_key] as Dictionary).duplicate(true)
	if _missing_registry_member_keys.has(cache_key):
		return {}

	var registry_cast: Variant = cast_registry.get(normalized_cast_name, {})
	if typeof(registry_cast) != TYPE_DICTIONARY:
		return _cache_missing_registry_member(cache_key)
	var registry_members: Variant = registry_cast.get("members", {})
	var directory_value: Variant = registry_cast.get("directory", "")
	if typeof(registry_members) != TYPE_DICTIONARY or typeof(directory_value) != TYPE_STRING:
		return _cache_missing_registry_member(cache_key)
	var directory: String = directory_value.strip_edges()
	var registry_member: Variant = registry_members.get(str(cast_id), {})
	if (
		typeof(registry_member) != TYPE_DICTIONARY
		or registry_member.is_empty()
		or not _is_safe_registry_directory(directory)
	):
		return _cache_missing_registry_member(cache_key)
	var resolved_member: Dictionary = registry_member.duplicate(true)
	resolved_member["_registry_directory"] = directory
	resolved_member["_registry_cast_name"] = normalized_cast_name
	_registry_member_cache[cache_key] = resolved_member
	return resolved_member.duplicate(true)


func _cache_missing_registry_member(cache_key: String) -> Dictionary:
	_missing_registry_member_keys[cache_key] = true
	return {}


func get_registry_texture(
	cast_name: String,
	cast_id: int,
	mode: Transparency = Transparency.NONE
) -> Texture2D:
	var normalized_cast_name := cast_name.strip_edges().to_lower()
	var cache_key := "%s:%d:%d" % [normalized_cast_name, cast_id, int(mode)]
	if _registry_texture_cache.has(cache_key):
		return _registry_texture_cache[cache_key]
	if _missing_registry_texture_keys.has(cache_key):
		return null

	var member := get_registry_member(normalized_cast_name, cast_id)
	if member.is_empty():
		return _cache_missing_registry_texture(cache_key)
	var abs_path := _resolve_bitmap_path(member, false)
	if abs_path.is_empty():
		return _cache_missing_registry_texture(cache_key)
	var img := _load_bmp(abs_path)
	if img == null:
		return _cache_missing_registry_texture(cache_key)
	_apply_transparency(img, mode)
	var texture := ImageTexture.create_from_image(img)
	_registry_texture_cache[cache_key] = texture
	return texture


func _cache_missing_registry_texture(cache_key: String) -> Texture2D:
	_missing_registry_texture_keys[cache_key] = true
	return null


func get_linked_member(cast_lib: int, cast_id: int) -> Dictionary:
	var cache_key := "%d:%d" % [cast_lib, cast_id]
	if _resolved_member_cache.has(cache_key):
		var cached_member: Variant = _resolved_member_cache[cache_key]
		if typeof(cached_member) == TYPE_DICTIONARY and cached_member.has("_registry_directory"):
			return cached_member
		return {}
	if _missing_linked_member_keys.has(cache_key):
		return {}
	var local_key := member_key(cast_lib, cast_id)
	var local_member: Variant = members.get(local_key, {})
	if typeof(local_member) == TYPE_DICTIONARY and not local_member.is_empty():
		return _cache_missing_linked_member(cache_key)
	if cast_lib == 1:
		return _cache_missing_linked_member(cache_key)

	var cast_name := _linked_cast_name(cast_lib)
	if cast_name.is_empty():
		return _cache_missing_linked_member(cache_key)
	var registry_cast: Variant = cast_registry.get(cast_name, {})
	if typeof(registry_cast) != TYPE_DICTIONARY:
		return _cache_missing_linked_member(cache_key)
	var registry_members: Variant = registry_cast.get("members", {})
	var directory_value: Variant = registry_cast.get("directory", "")
	if typeof(registry_members) != TYPE_DICTIONARY or typeof(directory_value) != TYPE_STRING:
		return _cache_missing_linked_member(cache_key)
	var directory: String = directory_value.strip_edges()
	var registry_member: Variant = registry_members.get(str(cast_id), {})
	if (
		typeof(registry_member) != TYPE_DICTIONARY
		or registry_member.is_empty()
		or not _is_safe_registry_directory(directory)
	):
		return _cache_missing_linked_member(cache_key)
	var resolved_member: Dictionary = registry_member.duplicate(true)
	resolved_member["_registry_directory"] = directory
	resolved_member["_registry_cast_name"] = cast_name
	_resolved_member_cache[cache_key] = resolved_member
	return resolved_member


func _cache_missing_linked_member(cache_key: String) -> Dictionary:
	_missing_linked_member_keys[cache_key] = true
	return {}


func member_if_known(cast_lib: int, cast_id: int) -> Dictionary:
	## `get_member` without the complaint. Sweeping a whole movie's score touches
	## members that are film loops, fields or shapes rather than bitmaps, and those
	## are expected absences rather than something to warn about.
	var cache_key := "%d:%d" % [cast_lib, cast_id]
	if _resolved_member_cache.has(cache_key):
		return _resolved_member_cache[cache_key]
	if _missing_member_keys.has(cache_key):
		return {}

	var local_key := member_key(cast_lib, cast_id)
	var local_member: Variant = members.get(local_key, {})
	if typeof(local_member) == TYPE_DICTIONARY and not local_member.is_empty():
		_resolved_member_cache[cache_key] = local_member
		return local_member

	return get_linked_member(cast_lib, cast_id)


func get_member(cast_lib: int, cast_id: int) -> Dictionary:
	var member := member_if_known(cast_lib, cast_id)
	if not member.is_empty():
		return member

	var cache_key := "%d:%d" % [cast_lib, cast_id]
	if _missing_member_keys.has(cache_key):
		return {}
	var cast_name := _linked_cast_name(cast_lib)
	_missing_member_keys[cache_key] = true
	push_warning(
		"Missing cast member for movie %s, linked cast %s, member %d" % [
			movie_name,
			cast_name if not cast_name.is_empty() else "<unknown>",
			cast_id,
		]
	)
	return {}


func get_texture(
	cast_lib: int,
	cast_id: int,
	mode: Transparency = Transparency.NONE
) -> Texture2D:
	# Keyed by mode: the same member can be drawn opaque in one room and keyed
	# in another, so a single cache slot per member would leak the wrong image.
	var key := "%d:%d:%d" % [cast_lib, cast_id, int(mode)]
	var cache: Dictionary = _texture_cache if mode == Transparency.NONE else _matte_cache
	if cache.has(key):
		return cache[key]

	var member := get_member(cast_lib, cast_id)
	if member.is_empty():
		return null
	var abs_path := _resolve_bitmap_path(member)
	if abs_path.is_empty():
		return null

	var img := _load_bmp(abs_path)
	if img == null:
		return null
	_apply_transparency(img, mode)
	var tex := ImageTexture.create_from_image(img)
	cache[key] = tex
	return tex


func _resolve_bitmap_path(member: Dictionary, warn_on_registry_missing: bool = true) -> String:
	var path_value: Variant = member.get("path", "")
	var rel := str(path_value).trim_prefix("./")
	var has_valid_path := typeof(path_value) == TYPE_STRING
	if member.has("_registry_directory"):
		var directory := str(member.get("_registry_directory", "")).strip_edges()
		var cast_name := str(member.get("_registry_cast_name", "")).strip_edges().to_lower()
		var cast_id := int(member.get("cast_id", -1))
		var texture_key := "%s:%d" % [cast_name, cast_id]
		if warn_on_registry_missing and _missing_texture_keys.has(texture_key):
			return ""
		if not has_valid_path or not _is_safe_registry_directory(directory) or not _is_safe_registry_path(rel):
			if not warn_on_registry_missing:
				return ""
			return _cache_missing_registry_bitmap(texture_key, cast_name, cast_id, "Invalid bitmap path")
		var registry_path := MODEL_ROOT.path_join(directory).path_join(rel)
		if FileAccess.file_exists(registry_path):
			return registry_path
		if not warn_on_registry_missing:
			return ""
		return _cache_missing_registry_bitmap(texture_key, cast_name, cast_id, "Missing bitmap")
	if rel.is_empty():
		return ""
	var candidates: PackedStringArray = PackedStringArray([
		base_path.path_join(rel),
		"%s/MASTER/%s" % [MODEL_ROOT, rel],
		"%s/%s" % [MODEL_ROOT, rel],
	])
	# External cast folder by cast_lib_name, e.g. casts/island/...
	var lib_name := str(member.get("cast_lib_name", "")).to_lower()
	if not lib_name.is_empty():
		candidates.append("%s/%s/bitmaps/%s" % [MODEL_ROOT, lib_name.to_upper(), rel.get_file()])
		candidates.append("%s/%s/bitmaps/%s" % [MODEL_ROOT, lib_name, rel.get_file()])
		candidates.append("%s/DAY1/casts/%s/bitmaps/%s" % [MODEL_ROOT, lib_name, rel.get_file()])
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _cache_missing_registry_bitmap(texture_key: String, cast_name: String, cast_id: int, message: String) -> String:
	_missing_texture_keys[texture_key] = true
	push_warning("%s for movie %s, linked cast %s, member %d" % [message, movie_name, cast_name, cast_id])
	return ""


func _is_safe_registry_directory(directory: String) -> bool:
	return (
		not directory.is_empty()
		and directory not in [".", ".."]
		and not directory.is_absolute_path()
		and not directory.begins_with("/")
		and not directory.begins_with("\\")
		and not directory.contains("://")
		and not directory.contains("/")
		and not directory.contains("\\")
	)


func _is_safe_registry_path(path: String) -> bool:
	if (
		path.is_empty()
		or path.is_absolute_path()
		or path.begins_with("/")
		or path.begins_with("\\")
		or path.contains("://")
		or path.contains("\\")
	):
		return false
	for segment in path.split("/"):
		if segment == "..":
			return false
	return true


func _load_bmp(path: String) -> Image:
	## Decode BMP from bytes — works in editor and on export (unlike Image.load(res://)).
	var img := Image.new()
	var err := FAILED
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			err = img.load_bmp_from_buffer(bytes)
	if err != OK and ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is Texture2D:
			var from_tex: Image = (res as Texture2D).get_image()
			if from_tex != null:
				img = from_tex.duplicate()
				err = OK
		elif res is Image:
			img = (res as Image).duplicate()
			err = OK
	if err != OK:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _apply_matte(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var papers: Array[Color] = [Color(1, 1, 1, 1)]
	for corner in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		var c := img.get_pixelv(corner)
		if c.r >= 0.94 and c.g >= 0.94 and c.b >= 0.94:
			papers.append(c)

	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in w:
		_matte_try_enqueue(img, papers, visited, stack, x, 0, w, h)
		_matte_try_enqueue(img, papers, visited, stack, x, h - 1, w, h)
	for y in h:
		_matte_try_enqueue(img, papers, visited, stack, 0, y, w, h)
		_matte_try_enqueue(img, papers, visited, stack, w - 1, y, w, h)

	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		var c := img.get_pixelv(p)
		c.a = 0.0
		img.set_pixelv(p, c)
		_matte_try_enqueue(img, papers, visited, stack, p.x - 1, p.y, w, h)
		_matte_try_enqueue(img, papers, visited, stack, p.x + 1, p.y, w, h)
		_matte_try_enqueue(img, papers, visited, stack, p.x, p.y - 1, w, h)
		_matte_try_enqueue(img, papers, visited, stack, p.x, p.y + 1, w, h)


func _matte_try_enqueue(
	img: Image,
	papers: Array[Color],
	visited: PackedByteArray,
	stack: Array[Vector2i],
	x: int,
	y: int,
	w: int,
	h: int
) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	var idx := y * w + x
	if visited[idx] != 0:
		return
	var px := img.get_pixel(x, y)
	var near := false
	for p in papers:
		if (
			absf(px.r - p.r) <= MATTE_TOLERANCE
			and absf(px.g - p.g) <= MATTE_TOLERANCE
			and absf(px.b - p.b) <= MATTE_TOLERANCE
		):
			near = true
			break
	if not near:
		return
	visited[idx] = 1
	stack.append(Vector2i(x, y))


static func transparency_for_ink(ink: int) -> Transparency:
	var masked := ink & 0x3f
	if masked in BACKGROUND_INKS:
		return Transparency.BACKGROUND
	if masked in MATTE_INKS:
		return Transparency.MATTE
	return Transparency.NONE


func _apply_transparency(img: Image, mode: Transparency) -> void:
	match mode:
		Transparency.MATTE:
			_apply_matte(img)
		Transparency.BACKGROUND:
			_apply_background_key(img)
		_:
			pass


func cursor_image(cast_lib: int, data_id: int, mask_id: int) -> Dictionary:
	## Composes a Director cursor from its two 1-bit members.
	##
	## `set the cursor of sprite N to [member("wlkcur1").memberNum,
	## member("wlkcur2").memberNum]` is a (data, mask) pair, which the pixels
	## confirm: `wlkcur2` is the filled silhouette of `wlkcur1`'s outline. Mask bit
	## clear is transparent; where the mask is set the data bit chooses black or
	## white. The result is what makes a white-on-black cursor readable over dark
	## artwork, which a single-bitmap reading loses.
	##
	## Hotspot is the data member's registration point. These are not the classic
	## 16x16 Mac cursor: `wlkcur` is 13x17, `trgcur` 17x17, `hand` 15x17, so nothing
	## here may assume a size.
	##
	## Returns {} when either member is missing, so the caller falls back to the
	## system arrow rather than drawing a hole.
	var key := "%d:%d:%d" % [cast_lib, data_id, mask_id]
	if _cursor_cache.has(key):
		return _cursor_cache[key]

	var data_img := _member_image(cast_lib, data_id)
	var mask_img := _member_image(cast_lib, mask_id)
	if data_img == null or mask_img == null:
		_cursor_cache[key] = {}
		return {}

	var w := data_img.get_width()
	var h := data_img.get_height()
	# A cursor is small. Anything larger is not one, and composing it anyway puts a
	# piece of scenery or a block of noise under the pointer instead of falling back
	# to the arrow. NIGHT1 and ENDMOVI4 carry cursor members that no local chunk
	# dump covers, so they are still the 8-bit misread the export produced and would
	# otherwise install as static. The biggest real cursor here is `trgcur` at
	# 17x17. See bugs.md 11.
	if w > MAX_CURSOR_SIZE or h > MAX_CURSOR_SIZE:
		_cursor_cache[key] = {}
		return {}
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# The mask is authored at the same size as its data member in every pair
			# the game uses, but clamp rather than trust it: a mismatch should cost
			# an edge pixel, not an out-of-bounds read.
			var mx := mini(x, mask_img.get_width() - 1)
			var my := mini(y, mask_img.get_height() - 1)
			if mask_img.get_pixel(mx, my).r > 0.5:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var ink := data_img.get_pixel(x, y).r <= 0.5
			out.set_pixel(x, y, Color(0, 0, 0, 1) if ink else Color(1, 1, 1, 1))

	var member := get_member(cast_lib, data_id)
	var made := {
		"image": out,
		"hotspot": Vector2i(
			int(member.get("reg_offset_x", w / 2)),
			int(member.get("reg_offset_y", h / 2)),
		),
		# Identifies the pair, so a caller can tell two cursors apart without
		# comparing images. Size and hotspot alone do not: `wlkcur` and `magni` are
		# both 13x17.
		"key": key,
	}
	_cursor_cache[key] = made
	return made


func _member_image(cast_lib: int, cast_id: int) -> Image:
	var member := get_member(cast_lib, cast_id)
	if member.is_empty():
		return null
	var abs_path := _resolve_bitmap_path(member, false)
	return null if abs_path.is_empty() else _load_bmp(abs_path)


func _apply_background_key(img: Image) -> void:
	## Director "Background Transparent": every paper-coloured pixel drops out,
	## not only the ones the edge flood-fill can reach.
	##
	## Works on the raw buffer rather than get_pixel/set_pixel because this
	## touches every pixel of bitmaps up to 640x400.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var i := 0
	var n := data.size()
	while i + 3 < n:
		if (
			data[i] >= PAPER_MIN_BYTE
			and data[i + 1] >= PAPER_MIN_BYTE
			and data[i + 2] >= PAPER_MIN_BYTE
		):
			data[i + 3] = 0
		i += 4
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
