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
const FilmLoop := preload("res://director/director_film_loop.gd")

const STAGE := Vector2i(640, 480)
## Inks that key the paper colour. 8/9 are Matte and 1/36/39 Background
## Transparent; this preview treats them alike, so artwork enclosing white shows
## a hole here that the real renderer does not.
const KEYED_INKS := [1, 8, 9, 36, 39]
const PAPER_MIN_BYTE := 241
## What Director falls back to when no frame has set a tempo.
const DEFAULT_FPS := 15.0
## Floating skip control, in stage coordinates so it scales and letterboxes with
## everything else rather than drifting when the window is resized.
const SKIP_RECT := Rect2(STAGE.x - 62, 8, 54, 22)

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
## Same keys as `_textures`, holding the decoded Image so a click can be tested
## against the artwork rather than against its bounding box.
var _hit_images: Dictionary = {}
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
var _traced: Array = []
## The owning container's `ccl ` list, read once: film-loop children index into
## it, not into the movie's cast libraries.
var _ccl := PackedStringArray()
## "<lib>:<member>" -> DirectorFilmLoop, parsed on first draw.
var _loops: Dictionary = {}
## Ticks since the movie started, which is what a loop's own frame counts from.
var _ticks := 0
## What the film-loop path actually managed, per outcome. Written because "it
## compiles and raises no error" says nothing about whether a child reached the
## screen, and a loop that silently draws nothing looks identical to one that
## was never attempted.
var _loop_stats: Dictionary = {}
## Channel under the cursor, 0 for none. Recomputed on motion rather than per
## draw, because `rollOver` asks for it many times a tick.
var _hover_channel := 0
## Outline every sprite, brighter for the one under the cursor. On by default:
## in a preview with no cursor art and no hotspot feedback, "nothing happens" and
## "nothing is there" look the same.
var _show_boxes := true
## Kept so a `go to movie` can resolve the next file the way the first was found.
var _paths = null
## Where `play` came from, so `play done` can return there.
var _play_stack: Array = []
## channel -> Director's 0-255 volume, so a read gives back what was written.
var _sound_volume: Dictionary = {}


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
	_paths = paths

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
	var ccl_ids: Array = _movie.ids_of("ccl ")
	if not ccl_ids.is_empty():
		_ccl = FilmLoop.read_cast_list(_movie.read_chunk(ccl_ids[0]))
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
	print("ccl cast list  : %s" % str(_ccl))
	print("film loops     : %s" % JSON.stringify(_loop_stats))
	if not _traced.is_empty():
		print("sound trace (last %d):" % _traced.size())
		for line in _traced:
			print("   %s" % line)
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
		var fs: Dictionary = _frame_script(_index)
		var handlers: Array = []
		for handler in fs.get("handlers", []):
			handlers.append(str((handler as Dictionary).get("name", "")))
		print("  frame %d script: %s  handlers: %s" % [
			_index, str(fs.get("script", "NONE")), ", ".join(handlers),
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
	var frame: Dictionary = _score.frame(index)
	var member = frame.get("frame_script")
	if member != null:
		# Resolved in the library the score names, not by number alone: the
		# talking loop's last-frame script lives in the shared cast, and a
		# number-only search hands the frame to whichever cast answers first.
		var direct := _script_in_lib(int(frame.get("frame_script_lib", 1)), int(member))
		if direct.is_empty():
			direct = _script_for_member(int(member))
		if not direct.is_empty():
			return direct
	if _score == null:
		return {}
	# The narrowest interval covering this frame wins. A movie carries both
	# room-specific frame scripts and one that spans everything — DAY1's
	# `what to do everyframe` covers the whole movie — so taking the first match
	# hands every frame to the movie-wide script and the room-specific one never
	# runs. In DAY1 that is `go to mrkr 0`, the `go(marker(0))` that holds the
	# room: the playhead simply ran on, with no error anywhere.
	var best: Dictionary = {}
	var narrowest := 0x7FFFFFFF
	for interval in _score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		var from := int(interval["start"])
		var to := int(interval["end"])
		if index < from or index > to:
			continue
		var span := to - from
		if span >= narrowest:
			continue
		var script := _script_in_lib(
			int(interval["script_cast_lib"]), int(interval["script_member"])
		)
		if not script.is_empty():
			best = script
			narrowest = span
	return best


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
		# Film loops advance on the movie's clock, not the playhead's: a loop
		# keeps animating on a frame the score is holding still on, which is
		# exactly what a talking character does while its line plays.
		_ticks += 1
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
	# Director's order within one tick, all on the frame the playhead is on:
	# prepareFrame, enterFrame, then exitFrame. Firing enterFrame after the
	# advance instead makes it a once-per-room event rather than a per-tick one,
	# and a room whose logic hangs off it runs that logic exactly once.
	_held = false
	var script := _frame_script(_index)
	_dispatch("prepareFrame", script)
	_dispatch("enterFrame", script)
	_dispatch("exitFrame", script)
	if _held:
		return
	_index += 1
	if _index >= _score.frame_count:
		_index = 0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at := stage_mouse()
		# Tested before the sprite hit-test, or a hotspot underneath would eat it.
		if SKIP_RECT.has_point(at):
			skip_to_end()
			return
		_click(at)
		return
	if event is InputEventMouseMotion:
		var was := _hover_channel
		_hover_channel = _channel_at(stage_mouse())
		if was != _hover_channel:
			queue_redraw()
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
		KEY_B:
			_show_boxes = not _show_boxes
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
	for raw_sprite in frame.get("sprites", []):
		# What a script puppeted wins over what the score recorded. Ignoring it
		# leaves sprites the Lingo hid still on screen and members it swapped
		# still showing the old art — which looks like a layering fault and is
		# not one: the draw order here is already ascending channel, which is
		# Director's stacking order.
		var sprite: Dictionary = _effective(raw_sprite)
		if sprite.is_empty():
			continue
		var over: Dictionary = _overrides.get(int(sprite["channel"]), {})
		# A film loop draws its own children rather than a bitmap of its own.
		if _draw_film_loop(sprite):
			continue
		var texture: Texture2D = _texture_for(sprite)
		if texture == null:
			continue
		var size := texture.get_size()
		# `loc` is the registration point, not the corner.
		var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var reg := _scaled_reg(m, size, bool(sprite["stretch"]))
		var top_left := Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - reg
		# Only the channels a script is driving. A member swap re-anchors on the
		# new member's registration point, so a walk cycle whose frames register
		# differently moves vertically on every frame unless that is honoured —
		# and the symptom is indistinguishable from the loop riding on it being
		# misplaced.
		if not over.is_empty():
			_trace("f%d ch%d m=%d %dx%d reg(%d,%d) -> (%d,%d)" % [
				_index, int(sprite["channel"]), int(sprite["cast_id"]),
				int(m.get("width", 0)), int(m.get("height", 0)),
				int(reg.x), int(reg.y), int(top_left.x), int(top_left.y),
			])
		draw_texture(texture, top_left)

	if _show_boxes:
		_draw_hotspots(frame)

	# Drawn last so it sits above the stage, and in stage coordinates so it
	# scales with everything else.
	draw_rect(SKIP_RECT, Color(0, 0, 0, 0.55), true)
	draw_rect(SKIP_RECT, Color(1, 1, 1, 0.65), false, 1.0)
	draw_string(
		ThemeDB.fallback_font, SKIP_RECT.position + Vector2(11, 16), "SKIP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9)
	)

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
	# Kept alongside the texture for hit-testing: a click lands on a sprite only
	# where the sprite actually has pixels, so a keyed-out region passes the
	# click through to whatever is behind it.
	_hit_images[key] = image
	_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]


## Does this sprite have a visible pixel at a stage point?
##
## Rect-only hit-testing hands every click to the topmost sprite whose *box*
## contains the point, and one large mostly-transparent sprite in a high channel
## then swallows the whole screen. Director tests the artwork, not the box.
func _opaque_at(sprite: Dictionary, at: Vector2) -> bool:
	var key := "%d:%d:%d:%d" % [
		int(sprite["cast_lib"]), int(sprite["cast_id"]), int(sprite["ink"]),
		1 if sprite["stretch"] else 0,
	]
	if not _hit_images.has(key):
		# Populates the cache as a side effect.
		if _texture_for(sprite) == null:
			return false
	var image: Image = _hit_images.get(key)
	if image == null:
		return false
	var rect := _sprite_rect(sprite)
	var local := (at - rect.position).floor()
	if local.x < 0 or local.y < 0 \
			or local.x >= image.get_width() or local.y >= image.get_height():
		return false
	return image.get_pixel(int(local.x), int(local.y)).a > 0.1


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
		# Transparent pixels pass the click through, as Director does. Without
		# this one large keyed-out sprite in a high channel takes every click on
		# the stage and nothing beneath it is ever reachable.
		if not _opaque_at(sprite, at):
			continue
		var channel := int(sprite["channel"])
		_host.click_sprite = channel
		# The sprite's own behaviour, then the member's script, then any movie
		# script — Director's hierarchy, and the first handler that exists wins.
		# Director's resolution order: the sprite's behaviour, then the script on
		# the cast member it displays, then the frame script, then any movie
		# script. The frame script was missing here, which is a whole tier of
		# hotspot handling that simply never ran.
		var script := _sprite_script(channel, _index)
		if script.is_empty():
			script = _script_for_member(int(sprite["cast_id"]))
		if script.is_empty():
			script = _frame_script(_index)
		_dispatch("mouseUp", script)
		queue_redraw()
		return


## Draw a film-loop sprite by drawing its children. False when the member is not
## a film loop, so the caller falls through to the bitmap path.
##
## Children are positioned relative to the loop's own registration point, and
## stack among themselves by their mini-score channel — the loop as a whole still
## occupies one channel on the stage, so it layers where the score put it.
func _draw_film_loop(sprite: Dictionary) -> bool:
	var lib := int(sprite["cast_lib"])
	var id := int(sprite["cast_id"])
	var m: Dictionary = _table.get_member(lib, id)
	if m.is_empty() or int(m.get("type", 0)) != 2:
		return false

	var key := "%d:%d" % [lib, id]
	if not _loops.has(key):
		_loops[key] = _open_loop(lib, m)
	var loop = _loops[key]
	if loop == null:
		_tally(_loop_stats, "loop unparsed")
		return true # a film loop that will not parse still draws no bitmap
	_tally(_loop_stats, "loop drawn")

	var origin := Vector2(
		int(sprite["loc_h"]) - int(m.get("reg_offset_x", 0)),
		int(sprite["loc_v"]) - int(m.get("reg_offset_y", 0))
	)
	# A child's loc is its registration point inside the loop's own coordinate
	# space, which the loop's rect anchors — not a top-left on the stage. Adding
	# it to the sprite's position, as the first version did, places every child
	# by however far the loop's rect happens to sit from the origin, which is
	# why the animations that had never drawn before appeared in the wrong place.
	var rect: Dictionary = m.get("initial_rect", {})
	var loop_origin := Vector2(int(rect.get("left", 0)), int(rect.get("top", 0)))

	var kids: Array = loop.children(_ticks)
	_tally(_loop_stats, "children offered")
	if kids.is_empty():
		_tally(_loop_stats, "loop has no children this tick")
	for child in kids:
		var child_lib := _child_lib(child)
		if child_lib < 0:
			_tally(_loop_stats, "child unresolved cast=%s" % str(child["cast_name"]))
			continue
		var cm: Dictionary = _table.get_member(child_lib, int(child["cast_id"]))
		var texture: Texture2D = _texture_for({
			"cast_lib": child_lib, "cast_id": int(child["cast_id"]),
			"ink": int(child["ink"]), "stretch": bool(child["stretch"]),
			"width": int(child["width"]), "height": int(child["height"]),
		})
		if texture == null:
			_tally(_loop_stats, "child has no art")
			continue
		_tally(_loop_stats, "child drawn")
		# Deliberately NOT scaled by the stretch factor. Scaling it here — which
		# is what the stage path does for a stretched sprite — measurably moved
		# the animations further from where they belong, so a loop's children
		# anchor in the loop's own coordinate space rather than in the drawn one.
		# Reverted on evidence, not theory; the stage path keeps its scaling.
		var child_reg := Vector2(
			int(cm.get("reg_offset_x", 0)), int(cm.get("reg_offset_y", 0))
		)
		var at := Vector2(int(child["loc_h"]), int(child["loc_v"]))
		draw_texture(texture, origin + (at - loop_origin) - child_reg)
	return true


## A member's registration point, scaled to the size it is actually drawn at.
## Falls back to the centre, which is what Director uses when a member carries no
## registration point of its own.
func _scaled_reg(member: Dictionary, drawn: Vector2, stretched: bool) -> Vector2:
	var width := float(member.get("width", 0))
	var height := float(member.get("height", 0))
	var reg := Vector2(
		float(member.get("reg_offset_x", width * 0.5)),
		float(member.get("reg_offset_y", height * 0.5))
	)
	if not stretched or width <= 0.0 or height <= 0.0:
		return reg
	return Vector2(
		round(reg.x * drawn.x / width),
		round(reg.y * drawn.y / height)
	)


## The movie's cast-library number for a child's named cast, or -1.
func _child_lib(child: Dictionary) -> int:
	var name := str(child["cast_name"])
	if name == "":
		return 1
	# A `ccl ` entry is the cast's authoring path — Mac colon form, naming a
	# volume that has not existed for twenty years. Only the filename survives,
	# and the cast library table names casts without an extension.
	var stem := name.replace(":", "/").get_file().get_basename().to_lower()
	for number in _table.cast_libs:
		if str(_table.cast_libs[number].get("name", "")).to_lower() == stem:
			return int(number)
	return -1


func _open_loop(lib: int, member: Dictionary):
	var chunk_id := int(member.get("data_chunk_id", -1))
	if chunk_id < 0:
		return null
	var f = _table.file_for(lib)
	if f == null:
		return null
	var loop = FilmLoop.new()
	if not loop.parse(f.read_chunk(chunk_id), _ccl, bool(member.get("looping", true))):
		return null
	return loop


## A child names its cast by name, not by this movie's library number.
func _child_texture(child: Dictionary) -> Texture2D:
	var name := str(child["cast_name"])
	var lib := 1
	if name != "":
		# A `ccl ` entry is the cast's authoring path — Mac colon form, naming a
		# volume that has not existed for twenty years. Only the filename
		# survives, and the cast library table names casts without an extension.
		var stem := name.replace(":", "/").get_file().get_basename().to_lower()
		lib = -1
		for number in _table.cast_libs:
			if str(_table.cast_libs[number].get("name", "")).to_lower() == stem:
				lib = int(number)
				break
		if lib < 0:
			return null
	return _texture_for({
		"cast_lib": lib, "cast_id": int(child["cast_id"]),
		"ink": int(child["ink"]), "stretch": bool(child["stretch"]),
		"width": int(child["width"]), "height": int(child["height"]),
	})


## A sprite as it currently stands: the score's record with whatever a script has
## puppeted onto it. `{}` when a script has hidden it.
##
## Every path that asks about a sprite goes through this — drawing, hit-testing,
## `rollOver`. They diverged before: the screen showed the puppeted member while
## a click was tested against the score's, so a menu button was only clickable
## where its two states happened to overlap, and moving the mouse made it
## flicker in and out of reach.
func _effective(sprite: Dictionary) -> Dictionary:
	var over: Dictionary = _overrides.get(int(sprite["channel"]), {})
	if over.is_empty():
		return sprite
	if over.has("visible") and int(over["visible"]) == 0:
		return {}
	var out := sprite.duplicate()
	for key in ["membernum", "castnum"]:
		if over.has(key):
			out["cast_id"] = int(over[key])
	if over.has("loch"):
		out["loc_h"] = int(over["loch"])
	if over.has("locv"):
		out["loc_v"] = int(over["locv"])
	return out


## The topmost sprite whose rect contains a point, or 0. Highest channel first,
## which is Director's stacking order and therefore its hit order.
func _channel_at(at: Vector2) -> int:
	# Score geometry, for the same reason as `lingo_rollover`.
	var sprites: Array = _score.frame(_index).get("sprites", [])
	for i in range(sprites.size() - 1, -1, -1):
		if _sprite_rect(sprites[i]).has_point(at) and _opaque_at(sprites[i], at):
			return int(sprites[i]["channel"])
	return 0


## Outline every sprite on the frame, and say which of them a script could
## actually answer for. A sprite with a behaviour attached is a hotspot in the
## ordinary sense; the rest are only reachable if a frame script asks
## `rollOver` or `the clickOn`, which is how this game's menu works — so both
## are drawn, distinguished rather than filtered.
func _draw_hotspots(frame: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	for sprite in frame.get("sprites", []):
		var channel := int(sprite["channel"])
		var rect := _sprite_rect(sprite)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var scripted := not _sprite_script(channel, _index).is_empty()
		var hovered := channel == _hover_channel
		var tint := Color(0.2, 1.0, 0.4) if scripted else Color(0.35, 0.6, 1.0)
		if hovered:
			draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.18), true)
		draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.95 if hovered else 0.35),
			false, 2.0 if hovered else 1.0)
		if hovered:
			draw_string(font, rect.position + Vector2(2, -3),
				"ch%d  %d:%d%s" % [
					channel, int(sprite["cast_lib"]), int(sprite["cast_id"]),
					"  script" if scripted else "",
				],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)


func _sprite_rect(sprite: Dictionary) -> Rect2:
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	var size := Vector2(int(m.get("width", 0)), int(m.get("height", 0)))
	if bool(sprite["stretch"]):
		size = Vector2(int(sprite["width"]), int(sprite["height"]))
	var reg := Vector2(int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0)))
	return Rect2(Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - reg, size)


## Jump to the last frame of the movie currently playing.
##
## Deliberately blunt: it moves the playhead and nothing else. Whatever the room
## was holding for — a line of speech, a walk — is abandoned rather than
## unwound, so the last frame is entered with whatever state the skipped frames
## never got to set. That is fine for looking at a movie's end and would not be
## fine in the game.
func skip_to_end() -> void:
	if _score == null or _score.frame_count <= 0:
		return
	_index = _score.frame_count - 1
	_held = false
	_accumulated = 0.0
	_dispatch("enterFrame", _frame_script(_index))
	queue_redraw()


## Is the cursor over sprite `channel` right now?
##
## `rollOver` with no argument means "any sprite", which Director answers with
## the channel number rather than a boolean; nothing here needs that yet.
func lingo_rollover(channel: int) -> bool:
	if channel <= 0:
		return _hover_channel > 0
	# Measured against the score's geometry, never the puppeted one. A menu
	# script swaps a button's art *because* rollOver is true, so testing the
	# swapped member's rect feeds the answer back into the question: the
	# highlight changes the rect, the new rect no longer holds the cursor, the
	# highlight drops, and nothing ever settles.
	for sprite in _score.frame(_index).get("sprites", []):
		if int(sprite["channel"]) == channel:
			return _sprite_rect(sprite).has_point(stage_mouse())
	return false


func current_frame() -> int:
	return _index


func stage_mouse() -> Vector2:
	return get_local_mouse_position()


func lingo_hold() -> void:
	_held = true


## Entering a different room drops what scripts puppeted in the last one.
##
## Without this an override outlives its room: a script hides sprite 15 to take
## a collectable off the beach, the playhead moves somewhere else, and channel 15
## stays invisible for the rest of the session even though the score has put
## something entirely different there. It reads as a layering fault — art missing
## from in front of other art — and it is stale state, not stacking order.
func lingo_go_frame(frame: int) -> void:
	_held = true
	var target := clampi(frame, 0, maxi(_score.frame_count - 1, 0))
	if _labels != null and _labels.marker_at(target) != _labels.marker_at(_index):
		_overrides.clear()
	_index = target


func lingo_go_label(label: String) -> void:
	if _labels == null:
		return
	var frame: int = int(_labels.labels.get(label.to_lower(), -1))
	if frame >= 0:
		lingo_go_frame(frame)
	else:
		_held = true


## `go to movie "day1.dir"` — open another container and start playing it.
##
## Resolved from the current movie's own directory first, because a linked name
## means the file beside the one that named it; this game ships two containers
## called MASTER.CST and the same hazard applies to movies.
##
## Everything derived from the old movie is dropped rather than carried: the
## score, labels, cast table, `ccl `, decoded textures and compiled scripts all
## belong to the file that is being left. Keeping any of it means the next movie
## draws with the last one's art and resolves members in the last one's casts,
## which resolves to real members and looks like corruption rather than an error.
func lingo_go_movie(name: String, where: Variant) -> void:
	if _paths == null:
		return
	var here := str(_movie.path).get_base_dir()
	var target: String = _paths.resolve(name, here)
	if target == "":
		target = _paths.resolve(name.replace(":", "/").get_file(), here)
	if target == "":
		_trace("go movie %s -> not found" % name)
		return

	var next := ContainerFile.new()
	if not next.open(target):
		_trace("go movie %s -> %s" % [name, next.error])
		return
	var vwsc: Array = next.ids_of("VWSC")
	if vwsc.is_empty():
		_trace("go movie %s -> no score" % name)
		return
	var score = Score.new()
	if not score.parse(next.read_chunk(vwsc[0])):
		_trace("go movie %s -> %s" % [name, score.error])
		return

	if _table != null:
		_table.close()
	if _movie != null:
		_movie.close()
	_movie = next
	_score = score
	_labels = Labels.new()
	var vwlb: Array = next.ids_of("VWLB")
	if not vwlb.is_empty():
		_labels.parse(next.read_chunk(vwlb[0]))
	_table = CastTable.new()
	_table.open(_movie, _paths)
	_ccl = PackedStringArray()
	var ccl_ids: Array = _movie.ids_of("ccl ")
	if not ccl_ids.is_empty():
		_ccl = FilmLoop.read_cast_list(_movie.read_chunk(ccl_ids[0]))

	_textures.clear()
	_hit_images.clear()
	_loops.clear()
	_overrides.clear()
	_index = 0
	_ticks = 0
	_held = true
	_accumulated = 0.0

	if _lingo_on:
		_start_lingo(target)
		_dispatch("prepareMovie", {})
		_dispatch("startMovie", {})
	# A destination is resolved after startMovie, since a label only exists once
	# the new movie's own labels are loaded.
	if typeof(where) == TYPE_STRING and str(where) != "":
		_index = int(_labels.labels.get(str(where).to_lower(), 0))
	elif where != null:
		_index = clampi(int(where) - 1, 0, maxi(_score.frame_count - 1, 0))
	if _lingo_on:
		_dispatch("enterFrame", _frame_script(_index))
	get_window().title = "%s  —  %d frames" % [target.get_file(), _score.frame_count]
	print("go movie -> %s frame %d" % [target.get_file(), _index])
	queue_redraw()


## `play frame X` / `play movie Y` — go there, remembering where to come back to.
##
## Director keeps a stack, so a cut scene can be entered from anywhere and
## return to its caller. Without it `play done` has nowhere to go and the movie
## reads as having simply stopped at the end of the interlude.
func lingo_play_push(args: Array) -> void:
	_play_stack.append({"movie": str(_movie.path), "frame": _index})
	var movie := ""
	var where: Variant = null
	for a in args:
		if typeof(a) == TYPE_STRING:
			var text := str(a)
			if text.ends_with(".dir") or text.ends_with(".dxr") or text.ends_with(".cst"):
				movie = text
			elif text != "frame" and text != "movie" and where == null:
				where = text
		elif where == null:
			where = a
	if movie != "":
		lingo_go_movie(movie, where)
	elif typeof(where) == TYPE_STRING:
		lingo_go_label(str(where))
	elif where != null:
		lingo_go_frame(int(where) - 1)


## `play done` — return to whatever called `play`.
func lingo_play_done() -> void:
	if _play_stack.is_empty():
		_held = true
		return
	var back: Dictionary = _play_stack.pop_back()
	if str(back["movie"]) != str(_movie.path):
		lingo_go_movie(str(back["movie"]).get_file(), null)
	_index = clampi(int(back["frame"]), 0, maxi(_score.frame_count - 1, 0))
	_held = true
	queue_redraw()


## A sound channel's properties. `volume` is the one this game sets, 52 times.
func lingo_sound_prop(channel: int, prop: String) -> Variant:
	match prop:
		"volume":
			return int(_sound_volume.get(channel, 255))
		"loop", "looping":
			return 0
	return 0


## Director's volume is 0-255. Godot wants decibels, and a linear-to-dB curve is
## what makes 128 sound like half rather than nearly full.
func lingo_set_sound_prop(channel: int, prop: String, value: Variant) -> void:
	if prop != "volume":
		return
	var level := clampi(int(value), 0, 255)
	_sound_volume[channel] = level
	if _audio == null:
		return
	var player: Node = _audio.call("_ensure_player", channel)
	if player != null:
		player.set("volume_db", -80.0 if level <= 0 else linear_to_db(level / 255.0))
	_trace("f%d volume ch%d = %d" % [_index, channel, level])


func lingo_play_sound(channel: int, file: String) -> void:
	if _audio != null:
		_audio.call("play_file", channel, file)
	_trace("f%d play ch%d %s" % [_index, channel, file])


func lingo_sound_busy(channel: int) -> bool:
	if _audio == null or not _audio.has_method("sound_busy"):
		_trace("f%d soundBusy ch%d -> no audio" % [_index, channel])
		return false
	var busy := bool(_audio.call("sound_busy", channel))
	_trace("f%d soundBusy ch%d -> %s" % [_index, channel, busy])
	return busy


## A short tail of what the Lingo asked the world to do. The loop that holds a
## room while a line plays is `soundBusy` answering true on the same channel the
## line was played on, and every way that fails looks identical from outside:
## the room simply moves on.
func _trace(line: String) -> void:
	_traced.append(line)
	if _traced.size() > 40:
		_traced.remove_at(0)


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


## `puppetSprite N, FALSE` returns the channel to the score, which means
## discarding whatever the scripts wrote to it rather than merely stopping.
func lingo_puppet_sprite(channel: int, on: bool) -> void:
	if on:
		if not _overrides.has(channel):
			_overrides[channel] = {}
	else:
		_overrides.erase(channel)


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
