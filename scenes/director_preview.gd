extends Node2D
## Plays a Director movie straight from its container, on the stage, in a window.
##
##   godot --path . res://scenes/director_preview.tscn
##   godot --path . res://scenes/director_preview.tscn -- --file PIP2DATA/DAY1.DIR --label shore2
##
## Space pauses, left/right step a frame, R restarts, Esc quits.
##
## Not the engine â€” the engine is `director/director_runtime.gd`, and this does
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
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
const PreviewHost := preload("res://scenes/preview_lingo_host.gd")
const FilmLoop := preload("res://director/director_film_loop.gd")

const Ink := preload("res://director/director_ink.gd")
const Keys := preload("res://director/director_keys.gd")

const STAGE := Vector2i(640, 480)
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
## Hit-test mode. True tests the artwork within the rect, false takes the whole
## rect. `M` toggles; the HUD says which is live.
var _hit_pixels := true
## What the Lingo last asked the cursor to be, shown in the HUD so a cursor that
## never changes can be told from one that changes to the wrong thing.
var _cursor_now := "arrow"
## channel -> the cursor a script set on it. Kept apart from `_overrides` on
## purpose: `the cursor of sprite` lives on the channel, is not part of the frame
## delta, and survives frame changes and member swaps â€” where `_overrides` is
## per-field puppet state that is dropped when the score moves a channel on.
var _channel_cursors: Dictionary = {}
## channel -> the member it last showed, so a genuine swap can be detected.
var _last_member: Dictionary = {}
## channel -> the tick its current film loop began on. A loop restarts from its
## first frame when the member genuinely changes; counting from the movie clock
## instead makes a loop entered a second time resume wherever the first left off.
var _loop_start: Dictionary = {}
## The channel being dragged, and the offset from the cursor to its position.
var _drag_channel := 0
var _drag_offset := Vector2.ZERO
## What the `cursor` builtin last set, used when no channel supplies one.
var _global_cursor: Variant = 0
## What is actually on screen, so the cursor is only pushed when it changes.
var _cursor_applied: String = "?none"
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

	get_window().title = "%s  â€”  %d frames" % [path.get_file(), _score.frame_count]
	print("playing %s from frame %d of %d" % [path.get_file(), _index, _score.frame_count])
	queue_redraw()


func root_node(name: String) -> Node:
	return get_tree().root.get_node_or_null(name) if get_tree() != null else null


## Compile every cast this movie can address, and stand up an interpreter.
##
## The movie's own cast is not enough. A room's `exitFrame` lives there, but the
## handlers that play sound, move inventory and drive the HUD live in the shared
## cast the movie links â€” `MASTER` here â€” and a preview that compiles only the
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
## always â€” 758 of 758 intervals "resolved" that way â€” and what it finds is a
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


## Without a library to go on â€” a member script reached through a sprite â€” the
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
## interval entries â€” the only place the attachment exists.
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
## none â€” which is every frame of some movies.
func _dispatch(handler: String, script: Dictionary) -> void:
	if _interpreter == null:
		return
	_tally(_sent, handler)
	# `call_handler` already resolves Director's order â€” the owning script, then
	# any movie script â€” and lowercases the name on the way in. Guarding it with
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


## Offer a keypress to the movie. True when a script claimed it.
##
## Director routes a keypress through `the keyDownScript` first — a movie-wide
## handler name, set by the score, that runs ahead of everything else. 46 scripts
## in this corpus set it to `fromnow`, which is four lines long and stops sound
## channel 1 when the key code is 49, so pressing space cuts the line of speech
## that is playing. Others set `gomenu`, which leaves the intro for the menu.
##
## `the keyCode` and `the key` are only meaningful during the dispatch, so they
## are set around it and cleared after: a script reading `the keyCode` outside a
## key event should see nothing, not the last key pressed.
func _dispatch_key(event: InputEventKey) -> bool:
	if not _lingo_on or _interpreter == null or _host == null:
		return false
	var script_name := str(_host.key_down_script).strip_edges()
	_host.key_code = Keys.code_for(event)
	_host.key_char = Keys.char_for(event)
	# Tier 1 first: a primary handler installed by `when keyDown then` runs ahead
	# of everything, which is where Director puts it. `strtgame`'s `gomenu` is
	# nothing but one of these, so without it the intro has no way out.
	# Typed explicitly: `_interpreter` is untyped, so `:=` has nothing to infer
	# the return type from and the file will not compile.
	var claimed: bool = _interpreter.run_primary("keydown")
	if claimed:
		_tally(_ran, "when keyDown")
	if script_name != "" and _interpreter.has_handler(script_name.to_lower()):
		_tally(_sent, "keyDownScript:%s" % script_name)
		_tally(_ran, "keyDownScript:%s" % script_name)
		_interpreter.call_handler(script_name)
		claimed = true
	else:
		# No movie-wide script, so the message goes to the frame the way any
		# other event does.
		_dispatch("keyDown", _frame_script(_index))
	_host.key_code = -1
	_host.key_char = ""
	queue_redraw()
	return claimed


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
	# Whether a room set any cursor at all is a question that kept being answered
	# by looking at the screen and seeing an arrow, which cannot distinguish "the
	# cursor code is broken" from "this room asks for no cursor". Most of them ask
	# for none: the game sets `the cursor of sprite` on inventory items and in a
	# handful of rooms, so an arrow is usually correct.
	print("cursors        : %d channel(s) %s, global %s" % [
		_channel_cursors.size(), str(_channel_cursors.keys()), str(_global_cursor)
	])
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
## the smaller one. Most frame scripts are interval entries â€” a span of frames
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
	# room-specific frame scripts and one that spans everything â€” DAY1's
	# `what to do everyframe` covers the whole movie â€” so taking the first match
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
## stays where it is â€” without it the score simply runs on, which is what this
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
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at := stage_mouse()
		if not (event as InputEventMouseButton).pressed:
			# A drag ends on mouse-up, and the cursor is re-resolved then.
			_drag_channel = 0
			_resolve_cursor()
			return
		# Tested before the sprite hit-test, or a hotspot underneath would eat it.
		if SKIP_RECT.has_point(at):
			skip_to_end()
			return
		_begin_drag(at)
		_click(at)
		return
	if event is InputEventMouseMotion:
		var was := _hover_channel
		_hover_channel = _channel_at(stage_mouse())
		if _drag_channel > 0:
			# The dragged sprite follows the cursor by the offset recorded when
			# the drag began, so it does not snap its registration point to the
			# pointer on the first movement.
			var to := stage_mouse() + _drag_offset
			lingo_set_sprite_prop(_drag_channel, "loch", int(to.x))
			lingo_set_sprite_prop(_drag_channel, "locv", int(to.y))
			queue_redraw()
			return
		# The cursor is resolved on mouse movement, not once per frame. Director
		# recomputes it on move, on button-up, on entering the window and on a
		# new movie â€” so a sprite that swaps to a member with a different cursor
		# under a stationary mouse keeps the old one until the mouse moves.
		_resolve_cursor()
		if was != _hover_channel:
			queue_redraw()
		return
	if not (event is InputEventKey and event.pressed):
		return
	# The game's keys are offered first, and the debug bindings below only see
	# what the movie did not claim. Space is the case that matters: `fromnow`,
	# which 46 scripts install, stops sound channel 1 when the key code is 49,
	# and that is how every line of speech in this game is skipped.
	if not (event as InputEventKey).echo and _dispatch_key(event as InputEventKey):
		return
	match (event as InputEventKey).keycode:
		# F10, not space. Space is the game's own key -- Director titles use it to
		# skip a line of speech or a cut scene -- and a debug binding that eats it
		# makes the movie look unresponsive to the one key a player reaches for
		# first.
		KEY_F10:
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
		KEY_M:
			_hit_pixels = not _hit_pixels
			print("hit test: %s" % ("artwork" if _hit_pixels else "full rectangle"))
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
		# still showing the old art â€” which looks like a layering fault and is
		# not one: the draw order here is already ascending channel, which is
		# Director's stacking order.
		var sprite: Dictionary = _effective(raw_sprite)
		if sprite.is_empty():
			continue
		_note_member(int(sprite["channel"]), int(sprite["cast_id"]))
		var over: Dictionary = _overrides.get(int(sprite["channel"]), {})
		# A film loop draws its own children rather than a bitmap of its own.
		if _draw_film_loop(sprite):
			continue
		var texture: Texture2D = _texture_for(sprite)
		if texture == null:
			continue
		# One rule for where a sprite is, shared with the hit test. `loc` is the
		# registration point, not the corner.
		var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var placed := _stage_rect(sprite)
		var top_left := placed.position
		var reg := Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - top_left
		# Only the channels a script is driving. A member swap re-anchors on the
		# new member's registration point, so a walk cycle whose frames register
		# differently moves vertically on every frame unless that is honoured â€”
		# and the symptom is indistinguishable from the loop riding on it being
		# misplaced.
		if not over.is_empty():
			_trace("f%d ch%d m=%d %dx%d reg(%d,%d) -> (%d,%d)" % [
				_index, int(sprite["channel"]), int(sprite["cast_id"]),
				int(m.get("width", 0)), int(m.get("height", 0)),
				int(reg.x), int(reg.y), int(top_left.x), int(top_left.y),
			])
		# Blend is a draw-time alpha, not something baked into the artwork. A
		# blended sprite that ignored this drew fully opaque and unkeyed, which is
		# how EXODUS's selection highlight -- a semi-transparent bar meant to sit
		# over the option you are pointing at -- came out as a solid black
		# rectangle covering the text.
		draw_texture(texture, top_left, Color(1, 1, 1, Ink.blend_alpha(sprite)))

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
	var hud := "frame %d/%d  %s  fps %.0f  hit:%s  cur:%s%s" % [
		_index, _score.frame_count - 1, marker, frame.get("fps", 0.0),
		"art" if _hit_pixels else "rect", _cursor_now,
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
	var m: Dictionary = _table.get_member(lib, id)
	if m.is_empty() or int(m.get("type", 0)) != 1:
		return null
	var key := _texture_key(sprite, _drawn_size(sprite, m))
	if _textures.has(key):
		return _textures[key]

	_textures[key] = null
	var f = _table.file_for(lib)
	if f == null:
		return null
	var chunk: PackedByteArray = f.read_chunk(int(m.get("data_chunk_id", -1)))
	var error: Array = []
	var image: Image = Bitmap.decode(m, chunk, _palette, error)
	if image == null:
		return null
	var drawn := _drawn_size(sprite, m)
	if drawn.x > 0 and drawn.y > 0 \
			and (int(drawn.x) != image.get_width() or int(drawn.y) != image.get_height()):
		image.resize(int(drawn.x), int(drawn.y), Image.INTERPOLATE_NEAREST)
	# Matte keys only the paper a flood fill can reach from the edge; Background
	# Transparent keys the paper colour everywhere. Treating both as the second
	# punches holes through anything whose artwork encloses white -- the gaps
	# inside and between letters on a text button -- and a click then falls
	# straight through the middle of the button.
	#
	# The paper is the sprite's own backColor, resolved through the palette
	# rather than assumed: Director's 8-bit convention puts white at index 0, and
	# 99.9% of this corpus stores exactly that, but a sprite is free to name
	# another colour and the ink rule is defined against whatever it names.
	match Ink.key_for(ink):
		Ink.KEY_MATTE:
			Ink.key_matte(image)
		Ink.KEY_PAPER:
			Ink.key_paper(image, Ink.colour_of(_palette, int(sprite.get("back_color", 0))))
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
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	var key := _texture_key(sprite, _drawn_size(sprite, m))
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

## Topmost sprite under the point gets the click, highest channel first â€” that is
## Director's stacking order, and hit-testing from channel 1 up would hand every
## click to the room background.
##
## A mouse-down over a moveable sprite starts a drag first: Director records the
## channel and the offset from the click to the sprite's position, then follows
## the cursor until mouse-up or until the sprite stops being moveable. The offset
## matters, or the sprite snaps its registration point onto the pointer.
func _begin_drag(at: Vector2) -> void:
	_drag_channel = 0
	var channel := _channel_at(at)
	if channel <= 0:
		return
	if int((_overrides.get(channel, {}) as Dictionary).get("moveable", 0)) == 0:
		return
	for sprite in _score.frame(_index).get("sprites", []):
		if int(sprite["channel"]) != channel:
			continue
		var here := Vector2(
			float(_effective(sprite).get("loc_h", 0)),
			float(_effective(sprite).get("loc_v", 0))
		)
		_drag_channel = channel
		_drag_offset = here - at
		return


func _click(at: Vector2) -> void:
	if not _lingo_on or _interpreter == null:
		return
	# A click always produces a message. What is under the cursor decides which
	# script sees it first; it does not decide whether one is sent.
	#
	# Bailing out on a miss or a hole is why the menu went from unreliable to
	# dead: its backdrop covers the stage, so the hit test answered "hole" and
	# nothing was ever dispatched â€” while the handler the menu actually uses
	# lives in the frame script and reads `the clickOn`.
	var channel := _channel_at(at)
	_host.click_sprite = channel
	# Director's order: the sprite's own behaviour, then the script on the cast
	# member it displays, then the frame script, then any movie script.
	var script: Dictionary = {}
	if channel > 0:
		script = _sprite_script(channel, _index)
		if script.is_empty():
			for sprite in _score.frame(_index).get("sprites", []):
				if int(sprite["channel"]) == channel:
					script = _script_for_member(int(sprite["cast_id"]))
					break
	var tier := "sprite"
	if script.is_empty():
		script = _frame_script(_index)
		tier = "frame" if not script.is_empty() else "movie"
	# Says what was clicked, which script is about to answer for it, and whether
	# a handler actually exists. "clicked nothing" and "clicked something with no
	# mouseUp" look identical on screen and are entirely different faults.
	var has_up: bool = _interpreter.call("_script_has_handler", script, "mouseup") \
		or _interpreter.has_handler("mouseup")
	print("clicked (%d,%d) frame %d  ch%d  %s script %s  mouseUp:%s" % [
		int(at.x), int(at.y), _index, channel, tier,
		str(script.get("script", "none")), "yes" if has_up else "NO HANDLER",
	])
	# Director sends both, and a menu may answer either.
	_dispatch("mouseDown", script)
	_dispatch("mouseUp", script)
	queue_redraw()


## Draw a film-loop sprite by drawing its children. False when the member is not
## a film loop, so the caller falls through to the bitmap path.
##
## Children are positioned relative to the loop's own registration point, and
## stack among themselves by their mini-score channel â€” the loop as a whole still
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

	# The loop's own top-left on the stage. Its registration point is the centre
	# of its rect, so `loc - half the drawn size` â€” the scaled form of the same
	# rule every other cast type uses.
	var parent_w := float(sprite.get("width", m.get("width", 0)))
	var parent_h := float(sprite.get("height", m.get("height", 0)))
	var origin := Vector2(
		float(sprite["loc_h"]) - floor(parent_w * 0.5),
		float(sprite["loc_v"]) - floor(parent_h * 0.5)
	)
	# A child's loc is its registration point inside the loop's own coordinate
	# space, which the loop's rect anchors â€” not a top-left on the stage. Adding
	# it to the sprite's position, as the first version did, places every child
	# by however far the loop's rect happens to sit from the origin, which is
	# why the animations that had never drawn before appeared in the wrong place.
	var rect: Dictionary = m.get("initial_rect", {})
	var loop_origin := Vector2(int(rect.get("left", 0)), int(rect.get("top", 0)))

	# Counted from when this loop arrived on the channel, not from the movie
	# clock: a loop entered a second time starts at its first frame rather than
	# resuming wherever the previous one left off.
	var since := maxi(0, _ticks - int(_loop_start.get(int(sprite["channel"]), 0)))
	var kids: Array = loop.children(since)
	_tally(_loop_stats, "children offered")
	if kids.is_empty():
		_tally(_loop_stats, "loop has no children this tick")
	for child in kids:
		var child_lib := _child_lib(child)
		if child_lib < 0:
			_tally(_loop_stats, "child unresolved cast=%s" % str(child["cast_name"]))
			continue
		var cm: Dictionary = _table.get_member(child_lib, int(child["cast_id"]))
		var texture: Texture2D = _texture_for(_child_sprite(child, child_lib, cm))
		if texture == null:
			_tally(_loop_stats, "child has no art")
			continue
		_tally(_loop_stats, "child drawn")
		# Deliberately NOT scaled by the stretch factor. Scaling it here â€” which
		# is what the stage path does for a stretched sprite â€” measurably moved
		# the animations further from where they belong, so a loop's children
		# anchor in the loop's own coordinate space rather than in the drawn one.
		# Reverted on evidence, not theory; the stage path keeps its scaling.
		# Two subtractions, not one. A child's own start point is first made
		# relative to the loop's rect origin, then placed at where the loop
		# landed on the stage â€” and only then does the child's own registration
		# offset come off, by the same rule as any other sprite. Forgetting
		# either subtraction gives a constant offset: the loop's rect origin, or
		# half the loop's size.
		var child_reg := _scaled_reg(cm, texture.get_size(), bool(child["stretch"]))
		var at := Vector2(float(child["loc_h"]), float(child["loc_v"]))
		# A child carries its own ink and its own blend, and the loop's alpha
		# multiplies through: a blended loop dims everything inside it.
		draw_texture(
			texture,
			origin + (at - loop_origin) - child_reg,
			Color(1, 1, 1, Ink.blend_alpha(child) * Ink.blend_alpha(sprite))
		)
	return true


## A member's registration point, scaled to the size it is actually drawn at.
## Falls back to the centre, which is what Director uses when a member carries no
## registration point of its own.
## A member's registration point, scaled to the size the sprite draws at.
##
## `movie_player._registry_score_stage_position:196-199` is the working version
## and it scales: `loc_h - reg_x * sprite_width / member_width`. A registration
## point is in the member's own pixels, so a sprite drawn at another size has to
## carry it proportionally, and the fallback for a member without one is the
## centre rather than the corner.
## The registration offset, rescaled to the size the sprite is drawn at.
##
## Director keeps the offset proportional: `offset * currentSize / naturalSize`.
## Applying it unscaled puts a scaled sprite off by `(1 - scale) * offset` â€”
## negligible near natural size and growing with the scale, which is exactly how
## a walk cycle drifts progressively rather than being uniformly wrong.
##
## `startPoint` â€” Lingo's `the locH/locV of sprite` â€” is where the registration
## point sits, not the top-left, so the screen corner is `startPoint - offset`.
func _scaled_reg(member: Dictionary, drawn: Vector2, _stretched: bool) -> Vector2:
	var width := maxf(float(member.get("width", 1)), 1.0)
	var height := maxf(float(member.get("height", 1)), 1.0)
	var reg := Vector2(
		float(member.get("reg_offset_x", 0)),
		float(member.get("reg_offset_y", 0))
	)
	if drawn.x <= 0.0 or drawn.y <= 0.0:
		return reg
	return Vector2(reg.x * drawn.x / width, reg.y * drawn.y / height)


## The movie's cast-library number for a child's named cast, or -1.
func _child_lib(child: Dictionary) -> int:
	var name := str(child["cast_name"])
	if name == "":
		return 1
	# A `ccl ` entry is the cast's authoring path â€” Mac colon form, naming a
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
		# A `ccl ` entry is the cast's authoring path â€” Mac colon form, naming a
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
	return _texture_for(
		_child_sprite(child, lib, _table.get_member(lib, int(child["cast_id"])))
	)


## A film-loop child as a sprite record the rest of the renderer understands.
##
## The size rule here is the opposite of the main score's, and deliberately so.
## `tools/film_loop_stretch.gd` separates the two populations on the flag: of the
## 2,053 children carrying it, **zero** have a rect equal to their member's
## natural size, so with the flag clear the recorded rect really is authoring
## residue and the child draws at its member's size. The main score does not
## behave that way — see `_drawn_size` — so the resolution happens here, before
## the shared path sees it, rather than as a branch inside it.
func _child_sprite(child: Dictionary, lib: int, member: Dictionary) -> Dictionary:
	var w := int(member.get("width", 0))
	var h := int(member.get("height", 0))
	if bool(child["stretch"]) and int(child["width"]) > 0 and int(child["height"]) > 0:
		w = int(child["width"])
		h = int(child["height"])
	return {
		"cast_lib": lib, "cast_id": int(child["cast_id"]),
		"ink": int(child["ink"]), "stretch": bool(child["stretch"]),
		"width": w, "height": h,
	}


## A sprite as it currently stands: the score's record with whatever a script has
## puppeted onto it. `{}` when a script has hidden it.
##
## Every path that asks about a sprite goes through this â€” drawing, hit-testing,
## `rollOver`. They diverged before: the screen showed the puppeted member while
## a click was tested against the score's, so a menu button was only clickable
## where its two states happened to overlap, and moving the mouse made it
## flicker in and out of reach.
##
## Notice a member change on a channel, so a film loop arriving there starts at
## its first frame rather than resuming wherever the previous one left off. The
## loop's frame counter is channel state, not member state: two sprites showing
## the same loop animate independently.
##
## This deliberately does *not* adjust the sprite's position. A previous version
## carried a running per-channel correction for the change in registration
## anchor across a swap, on the theory that Director shifts the start point so a
## new offset does not move the sprite. The score changes members on a channel
## constantly — that is how a walk cycle is authored — and it supplies its own
## `loc` for each of those members, so the correction was being added on top of a
## position that was already right, and accumulating. `tools/nudge_drift.gd`
## measures it: 451px of drift on one DAY1 channel, 9 of 17 channels displaced.
func _note_member(channel: int, cast_id: int) -> void:
	if int(_last_member.get(channel, -1)) == cast_id:
		return
	_last_member[channel] = cast_id
	_loop_start[channel] = _ticks


func _effective(sprite: Dictionary) -> Dictionary:
	var channel := int(sprite["channel"])
	var over: Dictionary = _overrides.get(channel, {})
	if over.is_empty():
		return sprite
	# Puppeting is per field, not per sprite. Director tracks which properties a
	# script has written and overwrites everything else from the score on every
	# frame; a sprite is not wholesale handed over because one property was set.
	#
	# The distinction matters when the score changes the member underneath: a
	# script that pinned `locV` once should keep that and still follow the
	# score's member swaps, where holding the whole record freezes the sprite
	# against its own animation.
	if int(over.get("_member", -1)) != int(sprite["cast_id"]) and not over.has("membernum"):
		# The score moved this channel to a different member and no script
		# claimed the member. Geometry belongs to the new member, so positional
		# overrides taken against the old one are stale.
		over = {}
		_overrides.erase(channel)
		return sprite
	if over.has("visible") and int(over["visible"]) == 0:
		return {}
	var out := sprite.duplicate()
	for key in ["membernum", "castnum"]:
		if over.has(key):
			out["cast_id"] = int(over[key])
	# A script that writes `the width of sprite` resizes it. Deliberately without
	# setting `stretch`: the flag does not mean "is resized", it means "the author
	# resized this deliberately", and all it governs is whether a cast swap is
	# allowed to reset the size back to the member's natural one. Forcing it here
	# changed which branch the drawn size and the texture cache took, for a
	# property that should only have changed a number.
	if over.has("width"):
		out["width"] = int(over["width"])
	if over.has("height"):
		out["height"] = int(over["height"])
	if over.has("loch"):
		out["loc_h"] = int(over["loch"])
	if over.has("locv"):
		out["loc_v"] = int(over["locv"])
	return out


## The topmost sprite whose rect contains a point, or 0. Highest channel first,
## which is Director's stacking order and therefore its hit order.
func _channel_at(at: Vector2) -> int:
	# Highest channel first, since channel number is depth â€” but a sprite drawn
	# with a keying ink is only hit where it has pixels, and where it does not
	# the search CONTINUES to the sprite behind.
	#
	# Both simpler rules fail on this game's own menu. A pure bounding-box test
	# hands every click to channel 21, a large keyed sprite covering the stage,
	# so the buttons on channels 4-7 are never reached. Treating a transparent
	# pixel as a hole that ends the search is worse still: nothing is ever hit
	# at all. Transparency means "not this sprite", not "stop looking".
	#
	# Opaque inks are hit anywhere inside their rect, so the pixel test only
	# applies where the sprite is keyed at all.
	# Which of the two is right is an open question. `score.cpp` describes a
	# bounding-box test and no per-pixel matte test â€” but Director also skips
	# sprites that do not respond to the mouse, which this preview has no notion
	# of, and without that filter a pure rect test hands every click to the
	# backdrop on channel 21. The pixel test is standing in for the filter I
	# cannot model yet, so both are available and `M` switches between them.
	var sprites: Array = _score.frame(_index).get("sprites", [])
	for i in range(sprites.size() - 1, -1, -1):
		var sprite: Dictionary = sprites[i]
		if not _sprite_rect(sprite).has_point(at):
			continue
		# Only Matte samples the artwork. Every other ink is a plain rectangle
		# for hit-testing even when it renders per-pixel â€” the asymmetry is
		# deliberate in Director and easy to get wrong in both directions.
		if _hit_pixels and Ink.hits_per_pixel(int(sprite["ink"])) and not _opaque_at(sprite, at):
			continue
		# Eligibility is tested HERE, inside the descent, not applied to the
		# answer afterwards. A sprite the point is over but which cannot respond
		# does not absorb the click: the search carries on to what is beneath.
		# That is the whole reason a backdrop was taking every click.
		if _responds_to_mouse(sprite):
			return int(sprite["channel"])
	return 0


## Can this sprite answer a mouse message at all?
##
## Director asks whether a script attached to the sprite or to its cast member
## actually declares a mouse handler â€” the presence of a script id is not enough
## â€” or whether the sprite is moveable or a button. A backdrop with no handler
## is visible, hit-testable for other purposes, and simply not clickable.
func _responds_to_mouse(sprite: Dictionary) -> bool:
	var channel := int(sprite["channel"])
	var behaviour := _sprite_script(channel, _index)
	if _declares_mouse_handler(behaviour):
		return true
	if _declares_mouse_handler(_script_for_member(int(sprite["cast_id"]))):
		return true
	# A moveable sprite is click-eligible on its own, with no script at all â€”
	# it has to be, or nothing could start a drag.
	var over: Dictionary = _overrides.get(channel, {})
	if int(over.get("moveable", 0)) != 0:
		return true
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	return str(m.get("type_name", "")) == "button"


func _declares_mouse_handler(script: Dictionary) -> bool:
	if script.is_empty() or _interpreter == null:
		return false
	for name in ["mousedown", "mouseup"]:
		if _interpreter.call("_script_has_handler", script, name):
			return true
	return false


## Outline every sprite on the frame, and say which of them a script could
## actually answer for. A sprite with a behaviour attached is a hotspot in the
## ordinary sense; the rest are only reachable if a frame script asks
## `rollOver` or `the clickOn`, which is how this game's menu works â€” so both
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


## The size a sprite is actually drawn at: its own width and height, always.
##
## This used to honour the score's rect only when the stretch flag was set, on
## the reading that the stored rect is authoring residue otherwise —
## `director_score.gd:243-245` says so, and `tools/film_loop_stretch.gd` proves
## it for a film loop's *children*, where the flag separates the two populations
## cleanly. Carrying that rule over to the main score was the mistake.
##
## `tools/drawn_size.gd` settles it against the export, which is the decode the
## previously working renderer drew from. Taking the score's rect and scaling the
## registration offset into it places 98% of STRTGAME's sprites, 99.8% of DAY1's
## and 96% of EXODUS's exactly where the export puts them; taking the member's
## natural size with a raw offset only ever lands when the two sizes happen to
## agree anyway — 7,241 of 11,739 on STRTGAME against 11,483. `DIRECTOR_ENGINE.md`
## §1.2 says the same independently: the sprite's own width and height always
## win, and the member's size enters only as the denominator when scaling the
## offset.
##
## The member's size is the fallback for a record with a degenerate rect, and
## mirrors `_texture_for`'s refusal to resize to one, so the rect and the pixels
## can never disagree about how big the sprite is.
func _drawn_size(sprite: Dictionary, member: Dictionary) -> Vector2:
	var w := int(sprite.get("width", 0))
	var h := int(sprite.get("height", 0))
	if w > 0 and h > 0:
		return Vector2(w, h)
	return Vector2(int(member.get("width", 0)), int(member.get("height", 0)))


## The cache key for a sprite's decoded artwork.
##
## Everything that changes the pixels belongs in it. The drawn size does, because
## one member legitimately appears at several sizes in the same movie and a key
## that omits it hands the second appearance the first one's pixels. So does the
## back colour, because it is what Background Transparent keys against — two
## sprites sharing a member and naming different papers key differently.
##
## The blend amount deliberately does *not*: blending is applied as a draw-time
## modulate rather than baked into the image, so one decode serves every alpha.
func _texture_key(sprite: Dictionary, drawn: Vector2) -> String:
	return "%d:%d:%d:%dx%d:%d" % [
		int(sprite["cast_lib"]), int(sprite["cast_id"]), int(sprite["ink"]),
		int(drawn.x), int(drawn.y), int(sprite.get("back_color", 0)),
	]


## Where a sprite is on the stage. The single placement rule, used by the
## renderer, the hit test, `rollOver` and the debug boxes alike.
##
## There used to be two: the renderer scaled the registration offset by the drawn
## size and the hit test took it raw. They agree at natural size and part company
## as soon as a sprite is resized, so a stretched sprite was clickable somewhere
## it was not drawn — and the further from natural size, the further off.
func _stage_rect(sprite: Dictionary) -> Rect2:
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	var size := _drawn_size(sprite, m)
	var reg := _scaled_reg(m, size, bool(sprite["stretch"]))
	return Rect2(Vector2(int(sprite["loc_h"]), int(sprite["loc_v"])) - reg, size)


func _sprite_rect(sprite: Dictionary) -> Rect2:
	return _stage_rect(sprite)


## Jump to the last frame of the movie currently playing.
##
## Deliberately blunt: it moves the playhead and nothing else. Whatever the room
## was holding for â€” a line of speech, a walk â€” is abandoned rather than
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
## something entirely different there. It reads as a layering fault â€” art missing
## from in front of other art â€” and it is stale state, not stacking order.
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


## `go to movie "day1.dir"` â€” open another container and start playing it.
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
## `the movieName` — the container currently playing, as it is named on disk.
##
## Four scripts in this game compare it against a literal `"day1.dxr"`, and it is
## the only exact filename comparison in the corpus. Those comparisons are
## reconciled in `LingoValue.same_container`, not here, so this stays honest
## about which file is loaded rather than reporting a spelling that is no longer
## true.
func movie_name() -> String:
	if _movie == null:
		return ""
	return str(_movie.path).get_file()


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
	# Channel cursors survive frame changes and cast swaps (DIRECTOR_ENGINE.md 7.5)
	# but not a new movie, which is one of the points Director forces a recompute
	# at. The stored value is a pair of member *numbers*, and those are local to
	# the cast that was open when the script wrote them: MAP leaves [14, 15] on
	# channels 3-14 for `able1`/`able2`, and members 14 and 15 of the next movie's
	# cast are whatever that movie happens to hold. Carried over, the pair does not
	# keep a cursor, it installs a different one. `_cursor_applied` is cleared with
	# them, or the new movie's first genuine assignment compares equal to the stale
	# key and is never pushed to the OS at all.
	_channel_cursors.clear()
	_global_cursor = 0
	_cursor_applied = "?none"
	# Both are keyed by channel and measured against `_ticks`, which restarts
	# below. Left behind, a channel's loop start would sit in the *previous*
	# movie's clock and every film loop in the new room would be asked for a
	# negative frame.
	_last_member.clear()
	_loop_start.clear()
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
	get_window().title = "%s  â€”  %d frames" % [target.get_file(), _score.frame_count]
	print("go movie -> %s frame %d" % [target.get_file(), _index])
	queue_redraw()


## `play frame X` / `play movie Y` â€” go there, remembering where to come back to.
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


## `play done` â€” return to whatever called `play`.
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


## The `cursor` builtin: `cursor N`, `cursor 0`, `cursor [dataMember, maskMember]`.
##
## Score-level state that stands wherever no channel supplies a cursor of its own,
## and persists until changed, like the channel cursors. An id of 0 means "no
## cursor set" â€” something to fall through, not an explicit arrow. Treating 0 as
## the arrow would make every sprite override the global cursor.
##
## Three doc comments had collided above this function and none of them described
## it: a stray line about sound channels, the composition rules that belong to
## `lingo_set_cursor`, and the arbitration that belongs to `cursor_at`. Split back
## apart here, because a comment attached to the wrong function is worse than none.
func lingo_global_cursor(value: Variant) -> void:
	_global_cursor = value
	_cursor_applied = " "
	_resolve_cursor()


## Recompute the cursor under the pointer and push it if it changed.
##
## Called on mouse movement, on mouse-up and whenever a script writes a cursor,
## which is Director's own cadence: the cursor is NOT recomputed per frame, so a
## sprite that swaps to a member with a different cursor under a stationary mouse
## keeps the old one until something moves (DIRECTOR_ENGINE.md 7.5).
func _resolve_cursor() -> void:
	if _score == null:
		return
	var chosen: Variant = cursor_at(stage_mouse())
	# Compared by what was asked for, not by pixels, and only pushed on a change.
	var key := JSON.stringify(chosen)
	if key == _cursor_applied:
		return
	_cursor_applied = key
	lingo_set_cursor(chosen)


## What the cursor should be at a stage point: a channel's pair, or the global.
##
## Descend channels highest first, rect-test, and take the first channel whose
## cursor is non-empty; if none supplies one, the global cursor stands
## (DIRECTOR_ENGINE.md 7.4). The descent deliberately does NOT filter on
## responds-to-mouse: cursor eligibility and click eligibility are different tests
## over the same stack, so a sprite that cannot be clicked can still change the
## cursor over it. `_score.frame()` builds its sprite array in ascending channel
## order, so walking it backwards is highest-first.
##
## Split out of `_resolve_cursor` so the arbitration can be asked a question
## without a real pointer. Headless there is no mouse, so a check that drove
## `_resolve_cursor` alone could only ever observe the global cursor and would
## pass while every channel was mis-resolved — which is exactly the state this
## whole path was in.
func cursor_at(at: Vector2) -> Variant:
	if _score == null:
		return _global_cursor
	var sprites: Array = _score.frame(_index).get("sprites", [])
	for i in range(sprites.size() - 1, -1, -1):
		# `_effective`, not the raw score record, and for the same reason the draw
		# path uses it: a script that hid a channel or moved it returns `{}` or a
		# different rect, and a cursor arbitrated off the score's copy would answer
		# for a sprite that is not where the player sees it — or is not there at
		# all. MAP's own frame script does both (`the locH of sprite 15 to 1000`,
		# `sprite(20).visible = 0`), so this is not a hypothetical shape.
		var sprite: Dictionary = _effective(sprites[i])
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		if not _channel_cursors.has(channel):
			continue
		var candidate: Variant = _channel_cursors[channel]
		if _cursor_is_empty(candidate):
			continue
		if not _sprite_rect(sprite).has_point(at):
			continue
		return candidate
	return _global_cursor


## Is this channel one to fall through rather than stop on?
##
## "Empty" is a distinct state in Director: a cursor counts as empty when its
## resource id is the integer 0 and *not* a list (DIRECTOR_ENGINE.md 7.1). So a
## list always stops the descent, even one that will not compose — which is why
## the corpus's `set the cursor of sprite N to [1, 1]` reads as "arrow here",
## not as "ask the channel underneath".
static func _cursor_is_empty(value: Variant) -> bool:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).is_empty()
	return int(value) == 0


## Install a cursor: a `[data, mask]` member pair, or a built-in number.
##
## A custom cursor is a pair of 1-bit members: the data holds the shape, the mask
## says which of it is opaque. Composed the way `render_model_loader.cursor_image`
## does — a set data bit is black, a clear one white, and the mask decides whether
## the pixel is drawn at all, so the two must be read together or the cursor
## becomes a black rectangle.
func lingo_set_cursor(value: Variant) -> void:
	if typeof(value) == TYPE_ARRAY:
		var pair: Array = value
		if not pair.is_empty():
			var mask_id := int(pair[1]) if pair.size() > 1 else 0
			var composed = _cursor_image(int(pair[0]), mask_id)
			if composed != null:
				Input.set_custom_mouse_cursor(
					ImageTexture.create_from_image(composed["image"]),
					Input.CURSOR_ARROW, composed["hotspot"]
				)
				_cursor_now = "custom %s/%s" % [str(pair[0]), str(mask_id)]
				return
		# A pair that composes to nothing visible would hand Godot a fully
		# transparent image, and the cursor disappears rather than falling back.
		# An invisible cursor and a broken one look the same to the player.
		Input.set_custom_mouse_cursor(null)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_cursor_now = "arrow (pair empty)"
		return
	var which := int(value)
	Input.set_custom_mouse_cursor(null)
	# Director's built-in numbers. -1 and 0 are the arrow; the rest map onto the
	# nearest shape Godot offers, which is a translation rather than the real
	# artwork and is noted as such.
	match which:
		1:
			Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
		2, 3:
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		4:
			Input.set_default_cursor_shape(Input.CURSOR_WAIT)
		200:
			# Director's blank cursor: a transparent 1x1 image, since Godot has
			# no "hidden" shape that survives a custom-cursor reset.
			var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			blank.fill(Color(0, 0, 0, 0))
			Input.set_custom_mouse_cursor(ImageTexture.create_from_image(blank))
		_:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_cursor_now = str(which)


## Compose a 1-bit data/mask pair into a cursor image.
## `{image, hotspot}`, or null when nothing visible came out.
##
## Fixed 16x16, cropped from the members' top-left: larger members are cropped,
## smaller ones padded transparent. The mask's BLACK region is the visible
## silhouette — where the mask is white the pixel is transparent, and where it is
## black the colour comes from the data member. Reading only the data gives a
## black rectangle; inverting the mask gives an invisible cursor.
##
## Null on a fully transparent result, so the caller can fall back to the arrow
## rather than installing a cursor the player cannot see.
const CURSOR_SIZE := 16
## Largest a member may be and still be treated as cursor art. Matches
## `render_model_loader.MAX_CURSOR_SIZE`, and for the same reason: the corpus
## clears a channel's cursor with `set the cursor of sprite N to [1, 1]` 208
## times, and member 1 is not cursor art. Measured in MAP's internal cast it is
## `a1`, a 640x400 backdrop; cropping that to 16x16 puts a patch of scenery under
## the pointer, which reads as a corrupt cursor rather than as the arrow the
## author asked for. The biggest real cursor in this corpus is 17x17.
const MAX_CURSOR_SIZE := 32


func _cursor_image(data_id: int, mask_id: int):
	var data := _member_image(data_id)
	if data == null:
		return null
	if data.get_width() > MAX_CURSOR_SIZE or data.get_height() > MAX_CURSOR_SIZE:
		return null
	var mask := _member_image(mask_id) if mask_id > 0 else null
	var out := Image.create(CURSOR_SIZE, CURSOR_SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var visible := 0
	for y in CURSOR_SIZE:
		for x in CURSOR_SIZE:
			if x >= data.get_width() or y >= data.get_height():
				continue
			var shown := true
			if mask != null:
				if x >= mask.get_width() or y >= mask.get_height():
					shown = false
				else:
					shown = mask.get_pixel(x, y).r < 0.5
			if not shown:
				continue
			visible += 1
			out.set_pixel(x, y, Color.BLACK if data.get_pixel(x, y).r < 0.5 else Color.WHITE)
	if visible == 0:
		return null

	# The hotspot is the data member's registration point, and it is recentred
	# when it falls outside the 16x16 crop — an out-of-range hotspot would put
	# the click somewhere the cursor is not drawn.
	var m: Dictionary = _table.get_member(1, data_id)
	var hotspot := Vector2i(
		int(m.get("reg_offset_x", 0)), int(m.get("reg_offset_y", 0))
	)
	if hotspot.x < 0 or hotspot.y < 0 \
			or hotspot.x >= CURSOR_SIZE or hotspot.y >= CURSOR_SIZE:
		hotspot = Vector2i(CURSOR_SIZE / 2, CURSOR_SIZE / 2)
	return {"image": out, "hotspot": Vector2(hotspot)}


func _member_image(cast_id: int) -> Image:
	var m: Dictionary = _table.get_member(1, cast_id)
	if m.is_empty() or int(m.get("data_chunk_id", -1)) < 0:
		return null
	var f = _table.file_for(1)
	if f == null:
		return null
	var error: Array = []
	return Bitmap.decode(m, f.read_chunk(int(m["data_chunk_id"])), _palette, error)


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
## â€” the marker at or before where the playhead is â€” which is a different
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
	# `the cursor of sprite` is channel state, not a puppeted score field: it is
	# not part of the frame delta and survives frame changes and member swaps.
	# Stored in `_overrides` it would be dropped the moment the score moved that
	# channel to another member, which is exactly when a cursor must persist.
	if prop == "cursor":
		_channel_cursors[channel] = value
		_cursor_applied = " "
		_resolve_cursor()
		return
	if not _overrides.has(channel):
		_overrides[channel] = {}
	var over: Dictionary = _overrides[channel]
	over[prop] = value
	# Which member the override was taken against, so `_effective` can tell a
	# still-valid puppet from one the score has moved out from under.
	for sprite in _score.frame(_index).get("sprites", []):
		if int(sprite["channel"]) == channel:
			over["_member"] = int(sprite["cast_id"])
			break


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
		"number", "membernum", "castnum":
			# `member("able1").memberNum` and `the number of member "able1"` ask the
			# same question by two spellings, and only the second had a path here:
			# the first fell out of this match and returned 0. That is silent,
			# because 0 is a plausible member number. Every `set the cursor of
			# sprite i to [member("able1").memberNum, member("able2").memberNum]`
			# in MAP therefore stored [0, 0] and composed to nothing. The same
			# omission was found and fixed in `lingo/lingo_host.gd` for the other
			# renderer; this host had it too.
			return number
	return 0


func lingo_field(name: String, _cast: String) -> Variant:
	var number := _resolve_member(name, "")
	return str(_table.get_member(1, number).get("text", ""))


func lingo_member_number(which: Variant, cast: String) -> Variant:
	return _resolve_member(which, cast)


## A member reference is a number already, or a name to look up in the movie's
## own cast. Names are what scripts actually use.
##
## Through `_table`, whose internal cast is opened once and cached, rather than a
## fresh `Cast` per call: `number_of` builds its name map by parsing every member
## in the library, so a new instance each time re-reads the CAS* chunk and every
## CASt record behind it. That was tolerable while `member("x").memberNum` had no
## arm above and this was reached rarely. With it, MAP's frame script performs 24
## name lookups per exitFrame and the cost is on the frame path. Measured over 250
## steps of MAP: 125-144 ms before, 65-81 ms after, over three runs each.
func _resolve_member(which: Variant, _cast: String) -> int:
	if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
		return int(which)
	var cast = _table.cast_for(1)
	if cast == null:
		return 0
	return cast.number_of(str(which))


