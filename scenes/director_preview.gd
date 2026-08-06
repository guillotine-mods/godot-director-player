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
const Cast := preload("res://director/director_cast.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
const PreviewHost := preload("res://scenes/preview_lingo_host.gd")

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
## `[display] aspect` from the game config. See `director_game.cfg`.
var _aspect := "native_4_3"
## "<lib>:<member>:<ink>" -> Texture2D, or null where the member draws nothing.
var _textures: Dictionary = {}
var _interpreter = null
var _host = null
var _audio: Node = null
## Bundle keys to search for a member's script, movie's own cast first.
var _script_casts: Array = []
## cast library number -> its bundle key, so a script named by library and member
## resolves in the cast it actually lives in.
var _lib_keys: Dictionary = {}
## Set by `go to the frame` during an exitFrame: the room asked to stay put.
var _held := false
## channel -> {member, visible} overrides a script has puppeted.
var _overrides: Dictionary = {}
var _lingo_on := true
## handler -> times dispatched, and handler -> times a script was actually found
## to run it. The gap between the two is the whole diagnosis.
var _sent: Dictionary = {}
var _ran: Dictionary = {}


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
	var cfg := ConfigFile.new()
	if cfg.load(Paths.CONFIG_PATH) == OK:
		_aspect = str(cfg.get_value("display", "aspect", _aspect)).to_lower()
	_aspect = Args.text(args, "aspect", _aspect).to_lower()
	get_window().size_changed.connect(_fit_to_window)
	_fit_to_window()

	_lingo_on = not Args.flag(args, "no-lingo")
	if _lingo_on:
		_start_lingo(path)
	_audio = root_node("AudioDirector")
	if _lingo_on and _interpreter != null:
		# Director sends these once, before the first frame is drawn, and this is
		# where a movie's opening sound and its global setup live.
		_dispatch("prepareMovie", {})
		_dispatch("startMovie", {})
		_dispatch("enterFrame", _frame_script(_index))

	get_window().title = "%s  —  %d frames" % [path.get_file(), _score.frame_count]
	print("playing %s from frame %d of %d" % [path.get_file(), _index, _score.frame_count])
	queue_redraw()


func root_node(name: String) -> Node:
	return get_tree().root.get_node_or_null(name) if get_tree() != null else null


## Compile every cast this movie can address, and stand up an interpreter.
##
## The movie's own cast is not enough. A room's `exitFrame` lives there, but the
## handlers that play sound, move inventory and drive the HUD live in the shared
## cast the movie links — `MASTER` here — and a preview that compiles only the
## internal cast runs rooms that hold and say nothing.
func _start_lingo(path: String) -> void:
	var movie := path.get_file().get_basename().to_upper()
	_interpreter = Interpreter.new()
	_host = PreviewHost.new()
	_host.preview = self
	_interpreter.host = _host

	var compiler := Compiler.new()
	var started := Time.get_ticks_usec()
	var total := 0
	_script_casts.clear()
	for lib in _table.cast_libs:
		var cast = _table.cast_for(int(lib))
		if cast == null:
			continue
		var entry: Dictionary = _table.cast_libs[lib]
		var cast_name := str(entry.get("name", "")).to_lower()
		if cast_name == "" or int(lib) == 1:
			cast_name = "internal"
		var bundle: Dictionary = compiler.compile_cast(cast, movie, cast_name)
		var count := (bundle.get("scripts", {}) as Dictionary).size()
		if count == 0:
			continue
		_interpreter.load_bundle(bundle, movie)
		# The movie's own cast is searched first, so it is listed first.
		var key := "%s/%s" % [movie, cast_name]
		_lib_keys[int(lib)] = key
		if int(lib) == 1:
			_script_casts.insert(0, key)
		else:
			_script_casts.append(key)
		total += count
		print("lingo: %-10s %3d script(s)" % [cast_name, count])
	print("lingo: %d script(s) across %d cast(s) in %.0f ms" % [
		total, _script_casts.size(), (Time.get_ticks_usec() - started) / 1000.0,
	])
	if _script_casts.is_empty():
		print("lingo: nothing compiled; %s" % compiler.error)


## A script named by member number *and* the cast library it lives in.
##
## Searching every cast for any script with that number finds something almost
## always — 758 of 758 intervals "resolved" that way — and what it finds is a
## stranger: a frame script's number matching some sprite behaviour in another
## cast. The symptom is not an error but silence, because the script that comes
## back has no `exitFrame` in it. Member numbers are per cast, so the library is
## part of the key, not a hint.
func _script_in_lib(cast_lib: int, member: int) -> Dictionary:
	if _interpreter == null or member <= 0:
		return {}
	var lib := 1 if cast_lib <= 0 or cast_lib == 0xFFFF else cast_lib
	if _lib_keys.has(lib):
		return _interpreter.find_script_by_member(str(_lib_keys[lib]), member)
	return {}


## Without a library to go on — a member script reached through a sprite — the
## movie's own cast wins over a linked one, as Director resolves it.
func _script_for_member(member: int) -> Dictionary:
	if _interpreter == null or member <= 0:
		return {}
	for key in _script_casts:
		var script: Dictionary = _interpreter.find_script_by_member(str(key), member)
		if not script.is_empty():
			return script
	return {}


## The behaviour attached to a sprite channel on this frame, from the score's own
## interval entries — the only place the attachment exists.
func _sprite_script(channel: int, frame_index: int) -> Dictionary:
	if _score == null:
		return {}
	for interval in _score.intervals():
		if str(interval["kind"]) != "sprite" or int(interval["channel"]) != channel:
			continue
		if frame_index < int(interval["start"]) or frame_index > int(interval["end"]):
			continue
		return _script_in_lib(
			int(interval["script_cast_lib"]), int(interval["script_member"])
		)
	return {}


## Director's message hierarchy, as much of it as this preview has: the script
## that owns the message first, then any movie script.
##
## The movie-script fallback is not a nicety. `prepareMovie`, `startMovie` and
## most of a room's sound live in movie scripts, not on the frame, so a dispatch
## that only ever asks the frame script runs nothing at all on a frame that has
## none — which is every frame of some movies.
func _dispatch(handler: String, script: Dictionary) -> void:
	if _interpreter == null:
		return
	_tally(_sent, handler)
	# `call_handler` already resolves Director's order — the owning script, then
	# any movie script — and lowercases the name on the way in. Guarding it with
	# `_script_has_handler` was worse than redundant: that helper compares the
	# handler's lowercased name against the key *as given*, so "exitFrame" never
	# matched "exitframe" and every dispatch was refused before it ran.
	# Whether it ran, not what it returned: a void handler answers null, so a
	# `!= null` test scores every successful dispatch as a miss. The key is
	# lowercased because `_script_has_handler` compares against it as given.
	var key := handler.to_lower()
	var owns: bool = _interpreter.call("_script_has_handler", script, key)
	if owns or _interpreter.has_handler(key):
		_tally(_ran, handler)
	_interpreter.call_handler(handler, [], script)


func _tally(into: Dictionary, key: String) -> void:
	into[key] = int(into.get(key, 0)) + 1


## Everything the run learned about its own Lingo, in one place. Printed on `L`
## and at exit, because "no sound" has at least four distinct causes and only
## this tells them apart: no handler dispatched, none found, none reached a
## builtin, or a builtin reached and did nothing.
func _report() -> void:
	print("lingo dispatched : %s" % JSON.stringify(_sent))
	print("lingo ran        : %s" % JSON.stringify(_ran))
	if _host != null:
		print("builtins reached : %s" % JSON.stringify(_host.reached))
		print("builtins unbound : %s" % JSON.stringify(_host.unbound))
	if _score != null:
		var kinds: Dictionary = {}
		var resolved := 0
		var unresolved: Array = []
		for interval in _score.intervals():
			_tally(kinds, str(interval["kind"]))
			var member := int(interval["script_member"])
			if _script_for_member(member).is_empty():
				if unresolved.size() < 8 and not unresolved.has(member):
					unresolved.append(member)
			else:
				resolved += 1
		print("score intervals  : %s" % JSON.stringify(kinds))
		print("  scripts found  : %d of %d" % [resolved, _score.intervals().size()])
		if not unresolved.is_empty():
			print("  unresolved mbr : %s" % str(unresolved))
		print("  frame %d script: %s" % [
			_index, "found" if not _frame_script(_index).is_empty() else "NONE",
		])
	if _interpreter != null:
		var names: PackedStringArray = _interpreter.movie_handler_names()
		print("movie handlers   : %d  %s" % [names.size(), ", ".join(names)])
		var errors: Array = _interpreter.errors
		if not errors.is_empty():
			print("interpreter errors (%d):" % errors.size())
			for line in errors.slice(0, 8):
				print("   %s" % line)


func _exit_tree() -> void:
	if _lingo_on:
		_report()


## The frame script covering a frame, or `{}`.
##
## The main channel's script slot is only one of the two places this lives, and
## the smaller one. Most frame scripts are interval entries — a span of frames
## with a script attached, the same mechanism that attaches behaviours to sprite
## channels, distinguished by naming sprite 0. Reading only the main channel
## found a script on almost no frame, so `exitFrame` dispatched every tick and
## ran nothing: rooms did not hold and hotspots did not answer.
func _frame_script(index: int) -> Dictionary:
	var member = _score.frame(index).get("frame_script")
	if member != null:
		var direct := _script_for_member(int(member))
		if not direct.is_empty():
			return direct
	if _score == null:
		return {}
	for interval in _score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		if index < int(interval["start"]) or index > int(interval["end"]):
			continue
		var script := _script_in_lib(
			int(interval["script_cast_lib"]), int(interval["script_member"])
		)
		if not script.is_empty():
			return script
	return {}


## Fit the stage into the canvas the way `[display] aspect` asks.
##
## Measured against the viewport, not the OS window. The project stretches with
## `canvas_items`, so Godot has already scaled the canvas to the window before
## this node draws anything; fitting to the window size scales a second time and
## the stage overflows by exactly that factor.
##
## Scaling is fractional rather than snapped to whole multiples: a window that
## fits 2.9x showed the stage at 2x with a third of the screen black. Some source
## pixels then land on one more output row than their neighbours, which is the
## price of filling the window; the aspect ratio stays exact either way, and that
## is the part worth protecting.
func _fit_to_window() -> void:
	var canvas := get_viewport_rect().size
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		return
	if _aspect == "stretch_fill":
		scale = Vector2(canvas.x / STAGE.x, canvas.y / STAGE.y)
		position = Vector2.ZERO
		return
	var area := canvas
	match _aspect:
		"wide_16_9":
			area = _letterbox(canvas, 16.0 / 9.0)
		"ultra_21_9":
			area = _letterbox(canvas, 21.0 / 9.0)
	var factor := minf(area.x / STAGE.x, area.y / STAGE.y)
	scale = Vector2(factor, factor)
	position = ((canvas - Vector2(STAGE) * factor) * 0.5).floor()


## The largest rectangle of the given aspect that fits inside the canvas.
static func _letterbox(canvas: Vector2, aspect: float) -> Vector2:
	var width := canvas.x
	var height := width / aspect
	if height > canvas.y:
		height = canvas.y
		width = height * aspect
	return Vector2(width, height)


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


## Director's tick: the frame script's `exitFrame` runs, and only if it does not
## redirect the playhead does the frame advance. `go to the frame` is how a room
## stays where it is — without it the score simply runs on, which is what this
## preview did before and looks exactly like a rendering fault.
func _advance() -> void:
	if not _lingo_on:
		_index = (_index + 1) % maxi(_score.frame_count, 1)
		return
	_held = false
	_dispatch("exitFrame", _frame_script(_index))
	if _held:
		return
	_index += 1
	if _index >= _score.frame_count:
		_index = 0
	_dispatch("enterFrame", _frame_script(_index))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_click(stage_mouse())
		return
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
		KEY_L:
			_report()
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


# ------------------------------------------------------- what the host calls

## Topmost sprite under the point gets the click, highest channel first — that is
## Director's stacking order, and hit-testing from channel 1 up would hand every
## click to the room background.
func _click(at: Vector2) -> void:
	if not _lingo_on or _interpreter == null:
		return
	var frame: Dictionary = _score.frame(_index)
	var sprites: Array = frame.get("sprites", [])
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = sprites[i]
		if not _sprite_rect(sprite).has_point(at):
			continue
		var channel := int(sprite["channel"])
		_host.click_sprite = channel
		# The sprite's own behaviour, then the member's script, then any movie
		# script — Director's hierarchy, and the first handler that exists wins.
		var script := _sprite_script(channel, _index)
		if script.is_empty():
			script = _script_for_member(int(sprite["cast_id"]))
		_dispatch("mouseUp", script)
		queue_redraw()
		return


func _sprite_rect(sprite: Dictionary) -> Rect2:
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	var size := Vector2(int(m.get("width", 0)), int(m.get("height", 0)))
	if bool(sprite["stretch"]):
		size = Vector2(int(sprite["width"]), int(sprite["height"]))
	var reg := Vector2(int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0)))
	return Rect2(Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - reg, size)


func current_frame() -> int:
	return _index


func stage_mouse() -> Vector2:
	return get_local_mouse_position()


func lingo_hold() -> void:
	_held = true


func lingo_go_frame(frame: int) -> void:
	_held = true
	_index = clampi(frame, 0, maxi(_score.frame_count - 1, 0))


func lingo_go_label(label: String) -> void:
	if _labels == null:
		return
	var frame: int = int(_labels.labels.get(label.to_lower(), -1))
	if frame >= 0:
		lingo_go_frame(frame)
	else:
		_held = true


func lingo_play_sound(channel: int, file: String) -> void:
	if _audio != null:
		_audio.call("play_file", channel, file)


func lingo_sound_busy(channel: int) -> bool:
	if _audio == null or not _audio.has_method("sound_busy"):
		return false
	return bool(_audio.call("sound_busy", channel))


## `label("name")` is the frame a marker sits on. `label(0)` is playhead-relative
## — the marker at or before where the playhead is — which is a different
## question with the same spelling, and the reason a room's `whereami` gate takes
## a dead branch if it is answered by position instead.
func lingo_label(which: Variant) -> int:
	if _labels == null:
		return 0
	if typeof(which) == TYPE_STRING:
		return int(_labels.labels.get(str(which).to_lower(), 0))
	return lingo_marker(int(which))


func lingo_marker(offset: int) -> int:
	if _labels == null or _labels.markers.is_empty():
		return 0
	var here := 0
	for i in _labels.markers.size():
		if int(_labels.markers[i]["frame"]) <= _index:
			here = i
		else:
			break
	var target := clampi(here + offset, 0, _labels.markers.size() - 1)
	return int(_labels.markers[target]["frame"])


func lingo_stop_sound(channel: int) -> void:
	if _audio != null and _audio.has_method("stop_channel"):
		_audio.call("stop_channel", channel)


func lingo_sprite_prop(channel: int, prop: String) -> Variant:
	var over: Dictionary = _overrides.get(channel, {})
	if over.has(prop):
		return over[prop]
	for sprite in _score.frame(_index).get("sprites", []):
		if int(sprite["channel"]) != channel:
			continue
		match prop:
			"membernum", "castnum":
				return int(sprite["cast_id"])
			"loch":
				return int(sprite["loc_h"])
			"locv":
				return int(sprite["loc_v"])
			"width":
				return int(sprite["width"])
			"height":
				return int(sprite["height"])
			"visible":
				return 1
			"ink":
				return int(sprite["ink"])
	return 0


func lingo_set_sprite_prop(channel: int, prop: String, value: Variant) -> void:
	if not _overrides.has(channel):
		_overrides[channel] = {}
	(_overrides[channel] as Dictionary)[prop] = value


func lingo_member_prop(which: Variant, cast: String, prop: String) -> Variant:
	var number := _resolve_member(which, cast)
	var m: Dictionary = _table.get_member(1, number)
	match prop:
		"name":
			return str(m.get("name", ""))
		"width":
			return int(m.get("width", 0))
		"height":
			return int(m.get("height", 0))
		"text":
			return str(m.get("text", ""))
	return 0


func lingo_field(name: String, _cast: String) -> Variant:
	var number := _resolve_member(name, "")
	return str(_table.get_member(1, number).get("text", ""))


func lingo_member_number(which: Variant, cast: String) -> Variant:
	return _resolve_member(which, cast)


## A member reference is a number already, or a name to look up in the movie's
## own cast. Names are what scripts actually use.
func _resolve_member(which: Variant, _cast: String) -> int:
	if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
		return int(which)
	var cast := Cast.new()
	if not cast.open(_movie):
		return 0
	return cast.number_of(str(which))


func _key_paper(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r8 >= PAPER_MIN_BYTE and c.g8 >= PAPER_MIN_BYTE and c.b8 >= PAPER_MIN_BYTE:
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
