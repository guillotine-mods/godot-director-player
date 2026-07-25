class_name RenderModelLoader
extends RefCounted
## Loads Director render_model JSON + BMP cast members for a movie.

const INDEX_PATH := "res://assets/render_model/index.json"
const MODEL_ROOT := "res://assets/render_model"
## Director ink types that key a background as transparent (web player parity).
## 1=Transparent, 8=Matte, 9=Mask, 36=Background Transparent, 39=Ghost-ish in some exports.
const TRANSPARENT_INKS := [1, 8, 9, 36, 39]
const MATTE_TOLERANCE := 14.0 / 255.0

var index: Dictionary = {}
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


func load_index() -> Error:
	if not FileAccess.file_exists(INDEX_PATH):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	index = parsed
	return OK


func available_movies() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry in index.get("exports", []):
		if typeof(entry) == TYPE_DICTIONARY and entry.has("movie"):
			out.append(str(entry.movie))
	return out


func load_movie(name: String) -> Error:
	movie_name = name
	base_path = "%s/%s" % [MODEL_ROOT, name]
	var frames_path := "%s/frames.json" % base_path
	var members_path := "%s/members.json" % base_path
	if not FileAccess.file_exists(frames_path) or not FileAccess.file_exists(members_path):
		return ERR_FILE_NOT_FOUND

	var frames_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	var members_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(members_path))
	if typeof(frames_json) != TYPE_DICTIONARY or typeof(members_json) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA

	frames = frames_json.get("frames", [])
	labels = frames_json.get("labels", {})
	markers = frames_json.get("markers", [])
	cast_libs = frames_json.get("cast_libs", members_json.get("cast_libs", {}))
	members = members_json.get("members", {})
	first_playable_frame = int(frames_json.get("first_playable_frame", 0))
	var stage: Dictionary = frames_json.get("stage", {})
	stage_size = Vector2i(int(stage.get("width", 640)), int(stage.get("height", 480)))
	_texture_cache.clear()
	_matte_cache.clear()
	return OK


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
	if members.has(bare):
		return bare
	return lib_id


func get_member(cast_lib: int, cast_id: int) -> Dictionary:
	var key := member_key(cast_lib, cast_id)
	var m: Variant = members.get(key, {})
	return m if typeof(m) == TYPE_DICTIONARY else {}


func get_texture(cast_lib: int, cast_id: int, use_matte: bool = false) -> Texture2D:
	var key := "%d:%d" % [cast_lib, cast_id]
	if use_matte and _matte_cache.has(key):
		return _matte_cache[key]
	if not use_matte and _texture_cache.has(key):
		return _texture_cache[key]

	var member := get_member(cast_lib, cast_id)
	if member.is_empty():
		return null
	var abs_path := _resolve_bitmap_path(member)
	if abs_path.is_empty():
		return null

	var img := _load_bmp(abs_path)
	if img == null:
		return null
	if use_matte:
		_apply_matte(img)
		var tex := ImageTexture.create_from_image(img)
		_matte_cache[key] = tex
		return tex
	var plain := ImageTexture.create_from_image(img)
	_texture_cache[key] = plain
	return plain


func _resolve_bitmap_path(member: Dictionary) -> String:
	var rel := str(member.get("path", "")).trim_prefix("./")
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


static func is_transparent_ink(ink: int) -> bool:
	return (ink & 0x3f) in TRANSPARENT_INKS
