extends Node2D
## Plays a Director movie straight from its container, on the stage, in a window.
##
##   godot --path . res://scenes/director_preview.tscn
##   godot --path . res://scenes/director_preview.tscn -- --file PIP2DATA/DAY1.DIR --label shore2
##
## Space pauses, left/right step a frame, R restarts, Esc quits.
##
## Not the engine — the engine is `director/director_runtime.gd`, and this does
## not touch it. What the runtime's frames carry beyond the score (navigation,
## click targets, sounds) comes from the original Lingo, which nothing here can
## run yet, so this plays what the score alone describes: which member sits in
## which channel, where, at what tempo.
##
## The visible consequence is that rooms do not hold. A room stays put because
## its `exitFrame` handler says `go to the frame`, and that is a script. Here the
## playhead simply advances, so a room draws and animates and then runs on into
## whatever the score has next. That is the score being right and the Lingo being
## absent, not a rendering fault.

const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")
const Palette := preload("res://director/director_palette.gd")
const Bitmap := preload("res://director/director_bitmap.gd")

const STAGE := Vector2i(640, 480)
## Inks that key the paper colour. 8/9 are Matte and 1/36/39 Background
## Transparent; this preview treats them alike, so artwork enclosing white shows
## a hole here that the real renderer does not.
const KEYED_INKS := [1, 8, 9, 36, 39]
const PAPER_MIN_BYTE := 241
## What Director falls back to when no frame has set a tempo.
const DEFAULT_FPS := 15.0

var _movie = null
var _score = null
var _labels = null
var _table = null
var _palette: PackedByteArray
var _index := 0
var _accumulated := 0.0
var _paused := false
var _status := ""
## "<lib>:<member>:<ink>" -> Texture2D, or null where the member draws nothing.
var _textures: Dictionary = {}


func _ready() -> void:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		_fail("no game configured: %s" % Paths.CONFIG_PATH)
		return

	var wanted := Args.text(args, "file", paths.boot_movie)
	var path: String = paths.resolve(wanted)
	if path == "":
		_fail("no such container: %s" % wanted)
		return

	_movie = ContainerFile.new()
	if not _movie.open(path):
		_fail("%s: %s" % [path, _movie.error])
		return
	var vwsc: Array = _movie.ids_of("VWSC")
	if vwsc.is_empty():
		_fail("%s has no score" % path)
		return

	_score = Score.new()
	if not _score.parse(_movie.read_chunk(vwsc[0])):
		_fail("%s: %s" % [path, _score.error])
		return

	_labels = Labels.new()
	var vwlb: Array = _movie.ids_of("VWLB")
	if not vwlb.is_empty():
		_labels.parse(_movie.read_chunk(vwlb[0]))

	_table = CastTable.new()
	_table.open(_movie, paths)
	_palette = Palette.system_mac()

	var label := Args.text(args, "label")
	if label != "":
		_index = int(_labels.labels.get(label.to_lower(), 0))
	_index = clampi(Args.number(args, "frame", _index), 0, max(_score.frame_count - 1, 0))

	# Pixel art: nearest filtering, and whole-number scaling so a source pixel is
	# always a square block. A fractional factor makes some rows one pixel taller
	# than their neighbours, which reads as the art being wrong rather than as
	# the scaling being wrong.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color.BLACK)
	get_window().size_changed.connect(_fit_to_window)
	_fit_to_window()

	get_window().title = "%s  —  %d frames" % [path.get_file(), _score.frame_count]
	print("playing %s from frame %d of %d" % [path.get_file(), _index, _score.frame_count])
	queue_redraw()


## Fit the 640x480 stage into the canvas and centre it, letterboxing the rest.
##
## Measured against the viewport, not the OS window. The project stretches with
## `canvas_items`, so Godot has already scaled the canvas to the window before
## this node draws anything; fitting to the window size scales a second time and
## the stage overflows by exactly that factor.
func _fit_to_window() -> void:
	var canvas := get_viewport_rect().size
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		return
	var factor := minf(canvas.x / STAGE.x, canvas.y / STAGE.y)
	# Fractional, so the stage fills the window rather than snapping down to the
	# next whole multiple: a window that fits 2.9x showed the stage at 2x with a
	# third of the screen black. The cost is that some source pixels land on one
	# more output row than their neighbours; the aspect ratio stays exact, which
	# is the part worth protecting.
	scale = Vector2(factor, factor)
	position = ((canvas - Vector2(STAGE) * factor) * 0.5).floor()


func _fail(message: String) -> void:
	_status = message
	push_error(message)
	print(message)
	queue_redraw()


func _process(delta: float) -> void:
	if _score == null or _paused:
		return
	var frame: Dictionary = _score.frame(_index)
	if frame.is_empty():
		return
	# The score's own clock: a frame's tempo sets the rate and it persists until
	# another frame changes it.
	var fps: float = float(frame.get("fps", 0.0))
	if fps <= 0.0:
		fps = DEFAULT_FPS
	_accumulated += delta
	var step := 1.0 / fps
	while _accumulated >= step:
		_accumulated -= step
		_advance()
		queue_redraw()


func _advance() -> void:
	_index += 1
	if _index >= _score.frame_count:
		_index = 0


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_paused = not _paused
		KEY_RIGHT:
			_paused = true
			_index = mini(_index + 1, _score.frame_count - 1)
			queue_redraw()
		KEY_LEFT:
			_paused = true
			_index = maxi(_index - 1, 0)
			queue_redraw()
		KEY_R:
			_index = 0
			queue_redraw()
		KEY_F:
			var window := get_window()
			window.mode = (
				Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN
				else Window.MODE_FULLSCREEN
			)
		KEY_ESCAPE:
			get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, STAGE), Color.BLACK, true)
	if _status != "":
		draw_string(ThemeDB.fallback_font, Vector2(16, 32), _status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.RED)
		return
	if _score == null:
		return

	var frame: Dictionary = _score.frame(_index)
	for sprite in frame.get("sprites", []):
		var texture: Texture2D = _texture_for(sprite)
		if texture == null:
			continue
		var size := texture.get_size()
		# `loc` is the registration point, not the corner.
		var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var reg := Vector2(int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0)))
		if bool(sprite["stretch"]) and int(m.get("width", 0)) > 0:
			reg.x = round(reg.x * size.x / float(m["width"]))
			reg.y = round(reg.y * size.y / float(m["height"]))
		draw_texture(texture, Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - reg)

	var marker: String = _labels.marker_at(_index) if _labels != null else ""
	var hud := "frame %d/%d  %s  fps %.0f%s" % [
		_index, _score.frame_count - 1, marker, frame.get("fps", 0.0),
		"  PAUSED" if _paused else "",
	]
	draw_string(ThemeDB.fallback_font, Vector2(8, STAGE.y - 8), hud,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))


## Decoded once per (member, ink) and kept. A member costs milliseconds to
## decode and nothing to draw again, so the cost is paid on first appearance.
func _texture_for(sprite: Dictionary) -> Texture2D:
	var lib := int(sprite["cast_lib"])
	var id := int(sprite["cast_id"])
	var ink := int(sprite["ink"])
	var key := "%d:%d:%d:%d" % [lib, id, ink, 1 if sprite["stretch"] else 0]
	if _textures.has(key):
		return _textures[key]

	_textures[key] = null
	var m: Dictionary = _table.get_member(lib, id)
	if m.is_empty() or int(m.get("type", 0)) != 1:
		return null
	var f = _table.file_for(lib)
	if f == null:
		return null
	var chunk: PackedByteArray = f.read_chunk(int(m.get("data_chunk_id", -1)))
	var error: Array = []
	var image: Image = Bitmap.decode(m, chunk, _palette, error)
	if image == null:
		return null
	if bool(sprite["stretch"]):
		var w := int(sprite["width"])
		var h := int(sprite["height"])
		if w > 0 and h > 0 and (w != image.get_width() or h != image.get_height()):
			image.resize(w, h, Image.INTERPOLATE_NEAREST)
	if KEYED_INKS.has(ink):
		_key_paper(image)
	_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]


func _key_paper(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r8 >= PAPER_MIN_BYTE and c.g8 >= PAPER_MIN_BYTE and c.b8 >= PAPER_MIN_BYTE:
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
