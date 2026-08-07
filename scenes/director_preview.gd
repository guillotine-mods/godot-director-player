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
const Shape := preload("res://director/director_shape.gd")
const Text := preload("res://director/director_text.gd")
const Keys := preload("res://director/director_keys.gd")
const Preloader := preload("res://director/director_preloader.gd")
const FrameClock := preload("res://director/director_frame_clock.gd")
const Transition := preload("res://director/director_transition.gd")
const Config := preload("res://director/director_config.gd")

const STAGE := Vector2i(640, 480)
## Floating skip control, in stage coordinates so it scales and letterboxes with
## everything else rather than drifting when the window is resized.
const SKIP_RECT := Rect2(STAGE.x - 62, 8, 54, 22)

var _movie = null
var _score = null
var _labels = null
var _table = null
var _palette: PackedByteArray
var _index := 0
## Tempo, delays, wait-for-click and the time a transition takes. See
## `director/director_frame_clock.gd`; this node owns only the phase order.
var _clock = FrameClock.new()
## The frame `_clock` was last armed for. The playhead is moved from a dozen
## places — the score's own advance, `go`, a click, `play done` — so a genuine
## frame *entry* is detected by comparing indices rather than by hooking every
## writer, which is a funnel any one of them could quietly forget to use.
var _entered_index := -1
## Set when the playhead was moved by a `go` from outside the step loop. Director
## does not send `exitFrame` for a frame that is being left by a queued `go to`
## (DIRECTOR_ENGINE.md §6.1 step 7), and a click that navigates is exactly that.
var _jump_queued := false
## True only while `exitFrame` is being dispatched. It is what tells a `go` which
## tick it lands in: `exitFrame` runs at step 7 and the playhead is resolved at
## step 10, so a redirect from there is honoured by the same tick — while a `go`
## from `prepareFrame`, `enterFrame`, a mouse handler or a key handler comes
## *after* step 10 and is honoured by the next one, which is also the tick that
## then sends no `exitFrame` of its own (§6.1).
var _in_exit_frame := false
## The frame script whose `enterFrame` is waiting for a transition to finish.
## §6.2 plays the transition inside `renderFrame`, which is after `prepareFrame`
## and before `enterFrame`, so a handler that runs on entry runs when the new
## frame has finished arriving and not while it is still wiping in.
var _pending_enter = null
## What `puppetTransition` last asked for. One-shot: §10 gives a puppet
## transition priority over the frame's own and consumes it at the next frame
## change.
var _puppet_transition: Dictionary = {}
## Transitions actually played, for `_report`.
var _transitions_played := 0
var _paused := false
var _status := ""
## `[display] aspect` from the game config. See `director_game.cfg`.
var _aspect := "native_4_3"
## What `_clip_to_stage` handed the RenderingServer. Held because the server has
## no getter for it, and a harness that cannot see the clip cannot tell a stage
## that clips from one that was never asked to.
var _clip_rect := Rect2()
## "<lib>:<member>:<ink>" -> Texture2D, or null where the member draws nothing.
var _textures: Dictionary = {}
## Same keys as `_textures`, holding the decoded Image so a click can be tested
## against the artwork rather than against its bounding box.
var _hit_images: Dictionary = {}
## "<lib>:<member>" -> what a script last put into that field, overriding the text
## authored into the member's `STXT`. Held here rather than written back into the
## cast because the cast is a parsed view of a read-only container, and because a
## movie change has to forget it: member numbers are local to a cast.
var _field_text: Dictionary = {}
## channel -> what the last paint laid out for the field on it: the text, the box,
## the style and how many lines were drawn. Written by `_draw_text` and read by
## `tools/text_and_shapes.gd`, which has no other way to see a paint that headless
## Godot discards.
var _text_drawn: Dictionary = {}
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
## Decodes the artwork of frames the playhead has not reached yet, so a first
## appearance does not cost its milliseconds inside the step that draws it.
var _preloader = null
var _drag_channel := 0
var _drag_offset := Vector2.ZERO
## What the `cursor` builtin last set, used when no channel supplies one.
var _global_cursor: Variant = 0
## What is actually on screen, so the cursor is only pushed when it changes.
var _cursor_applied: String = "?none"
## Kept so a `go to movie` can resolve the next file the way the first was found.
var _paths = null

# ------------------------------------------------------ Movie-In-A-Window (§14)
#
# A window is another instance of this same scene, added as a child of the stage.
# That is a design decision and not laziness, so here is the reasoning.
#
# A window in Director runs a whole movie: its own score, playhead, tempo, cast
# table, puppet state, cursor, sounds and Lingo. `tools/window_survey.gd` says
# this corpus's three real windows all use that — `SAVELOAD.dir` is 255 frames
# with 35 scripts of its own (17 `exitFrame`, 17 `mouseUp`), `MAP.dir` 81 frames
# with 12 `mouseUp`, `JOKE.dir` 96 frames with 3 `exitFrame` — so a "draw another
# movie's frame over the stage" shortcut would have to grow every one of those
# back. Everything a window needs is already in this file, and a second instance
# of it is a second movie by construction rather than by remembering to duplicate
# each piece. The alternative, threading a "which movie" argument through
# `_advance`, `_draw`, `_click`, `_texture_for` and the forty `lingo_*` methods,
# is the same work spread over the whole file with a chance to forget it in each.
#
# Being a *child* node is doing three jobs at once: the letterboxing transform is
# inherited rather than recomputed, a CanvasItem's children paint after it so the
# window is over the stage for free, and freeing the node tears the movie down.
#
# What is deliberately not built, on the survey's evidence: window titles, window
# rects set from Lingo, `the modal of window`, `moveableSprite` window dragging
# and window chrome. The corpus writes exactly two window-ish properties —
# `the windowType` (21 times, always 2, which is Director's plain box with no
# title bar) and `the centerStage` (21 times, always 1) — and reads none.

## The preview running the stage. Null in the stage itself, set in every window.
var _stage_preview: Node = null
## Windows this preview owns: key -> the preview node running that movie. Only
## the stage's copy is ever populated; a window delegates every lookup upward, so
## `forget(window("saveload.dxr"))` called from *inside* SAVELOAD finds the same
## window the stage opened.
var _windows: Dictionary = {}
## The same keys in the order they were opened. The last is the front-most, which
## is the one a click is offered to first (§4.2).
var _window_order: Array[String] = []
## This preview's key as a window, "" for the stage.
var _window_key := ""
## The container this preview was created to run, when it is a window.
var _window_path := ""
## True between `open(window(...))` and `forget(window(...))`. A window that has
## been referenced but not opened is loaded and addressable and does not draw or
## advance — which is what lets `tell window("x") / set the centerStage to 1`
## run before the `open` that follows it in all 21 sites.
var _window_shown := false
## The movie's own `DRCF` stage rect. Every movie in this corpus declares
## 640x480, so a centred window covers the stage exactly; the rect is read rather
## than assumed because it is what decides both, and a title whose window is
## smaller would otherwise be drawn full-stage.
var _config = null
## `the centerStage` and `the windowType` as a script set them, per §14. Stored
## and honoured at `open`: `centerStage` decides placement, and `windowType` is
## recorded so the value is answerable rather than dropped.
var _center_stage := false
var _window_type := 0
## Where `play` came from, so `play done` can return there.
var _play_stack: Array = []


func _ready() -> void:
	# A window is the same scene standing up a second movie, and it is configured
	# before it enters the tree rather than from the command line. Split here so
	# that the one path everything else in this file assumes — a loaded container
	# with a score, a cast table and an interpreter — is reached the same way by
	# both.
	if _window_key != "":
		_ready_as_window()
		return
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

	_paths = paths
	if not _load_container(path):
		return

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
	# The frame the movie opens on is entered like any other: its tempo arms the
	# clock and its transition, if it has one, is played before anything runs on
	# it. Without this the first frame is paced by the 15 fps default whatever the
	# score says, and `_advance` would then re-enter it and re-arm the same delay.
	_sync_frame_entry()
	if _lingo_on and _interpreter != null:
		# Director sends these once, before the first frame is drawn, and this is
		# where a movie's opening sound and its global setup live.
		_dispatch("prepareMovie", {})
		_dispatch("startMovie", {})
		_enter_frame_or_defer(_frame_script(_index))

	get_window().title = "%s  â€”  %d frames" % [path.get_file(), _score.frame_count]
	print("playing %s from frame %d of %d" % [path.get_file(), _index, _score.frame_count])
	queue_redraw()


## Open a container and take everything that belongs to the movie inside it.
##
## `_paths` must already be set. Shared by the stage's boot and a window's,
## because "what a loaded movie consists of" is one list and two copies of it
## drift: the film-loop cast list was read in `_ready` and in `lingo_go_movie`
## and not here, which is the shape of omission this collapses.
func _load_container(path: String) -> bool:
	_movie = ContainerFile.new()
	if not _movie.open(path):
		_fail("%s: %s" % [path, _movie.error])
		return false
	var vwsc: Array = _movie.ids_of("VWSC")
	if vwsc.is_empty():
		_fail("%s has no score" % path)
		return false

	_score = Score.new()
	if not _score.parse(_movie.read_chunk(vwsc[0])):
		_fail("%s: %s" % [path, _score.error])
		return false
	_preloader = Preloader.new(_score)

	_labels = Labels.new()
	var vwlb: Array = _movie.ids_of("VWLB")
	if not vwlb.is_empty():
		_labels.parse(_movie.read_chunk(vwlb[0]))

	_table = CastTable.new()
	_table.open(_movie, _paths)
	_palette = Palette.system_mac()
	# The movie's own stage rect. Only a window uses it, but it is read for every
	# movie because a window's placement is the *difference* between its rect and
	# the stage movie's, and the stage is whichever movie happens to be playing.
	var config = Config.new()
	_config = config if config.read(_movie) else null
	_ccl = PackedStringArray()
	var ccl_ids: Array = _movie.ids_of("ccl ")
	if not ccl_ids.is_empty():
		_ccl = FilmLoop.read_cast_list(_movie.read_chunk(ccl_ids[0]))
	return true


## Stand up a movie that another movie asked for as a window (§14).
##
## Loaded but not shown and not running: `_process` is off until `open`, so the
## playhead does not move and `startMovie` has not been sent. That ordering is
## the corpus's, not a convenience — every one of the 21 sites reads
##
##     window("x").windowType = 2
##     tell window("x") / set the centerStage to 1 / end tell
##     open(window("x"))
##
## and three of them also `go` to a label inside the `tell`, so the movie has to
## be addressable before it is opened and must not have advanced past the frame
## the `go` chose.
##
## Input is off as well. The stage routes clicks and keys to the front-most
## window explicitly (`route_click`), rather than letting Godot's own reverse-tree
## `_input` order decide, because that order is invisible in a headless harness
## and a click has to be assertable.
func _ready_as_window() -> void:
	_paths = _stage_preview._paths
	_aspect = _stage_preview._aspect
	_lingo_on = _stage_preview._lingo_on
	_audio = root_node("AudioDirector")
	# The debug outlines belong to whoever is looking at the stage, and a window
	# drawn over it should not add a second set.
	_show_boxes = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	set_process(false)
	set_process_input(false)
	if not _load_container(_window_path):
		return
	if _lingo_on:
		_start_lingo(_window_path)
		_share_movie_state_with(_stage_preview)
	print("window %s: %d frames" % [_window_path.get_file(), _score.frame_count])


## A window and the stage are two movies in one Director session, and some state
## belongs to the session rather than to either movie.
##
## **Globals.** Director clears them on `clearGlobals` and on quitting, never on
## opening a window, and this corpus is built on that: `SAVELOAD` sets `nof`,
## `newsyz`, `egozh` and `nextroomdata` in its own handlers and then says `tell
## the stage / go(nof, "day1.dxr")`, and the room that arrives on the stage reads
## those globals to place the player. The dictionaries are *shared*, not copied,
## so a write on either side is visible on the other — and they stay shared
## across a later `go to movie`, because `_start_lingo` carries the same object
## forward rather than a copy of it.
##
## **Field text.** `SAVELOAD` writes seven fields `of castLib "master"` — the
## saved score, inventory and joke state — and the stage reads the same members
## back out of the same shared external cast. So the override store is shared
## too. See `_field_key`, which is why sharing it is safe: the key names the
## cast's *file*, and library numbers are per movie.
func _share_movie_state_with(other: Node) -> void:
	if other == null or other._interpreter == null:
		return
	_interpreter.globals = other._interpreter.globals
	_host.globals = other._host.globals
	_field_text = other._field_text


func root_node(name: String) -> Node:
	return get_tree().root.get_node_or_null(name) if get_tree() != null else null


## Compile every cast this movie can address, and stand up an interpreter.
##
## The movie's own cast is not enough. A room's `exitFrame` lives there, but the
## handlers that play sound, move inventory and drive the HUD live in the shared
## cast the movie links â€” `MASTER` here â€” and a preview that compiles only the
## internal cast runs rooms that hold and say nothing.
## Globals outlive the movie that set them. That is the entire point of a Lingo
## global, and this game is built on it: `EXODUS` sets `syz` and `globalday` and
## then goes to `DAY1`, and `DAY1` reads them. Director clears them only on
## `clearGlobals` or on quitting -- never on `go to movie`.
##
## A movie change stands up a fresh interpreter here, because the scripts, the
## casts and the handler tables all belong to the movie being left. The globals
## do not, so they are carried across. Without this every room began with every
## global VOID, which is not a subtle failure: rooms that decide what to show
## from accumulated state show the wrong thing, and the wrongness looks like a
## rendering fault rather than a lost variable.
##
## The interpreter's own dictionary is the one that matters. `owns_global` on the
## host answers "do I already hold this name", and nothing ever seeds the host's
## dictionary, so it is always false and every global lives here. Both are
## carried anyway, so that stops being load-bearing if the host ever does claim
## one.
func _start_lingo(path: String) -> void:
	var carried_globals: Dictionary = {}
	var carried_host_globals: Dictionary = {}
	if _interpreter != null:
		carried_globals = _interpreter.globals
	if _host != null:
		carried_host_globals = _host.globals

	var movie := path.get_file().get_basename().to_upper()
	_interpreter = Interpreter.new()
	_host = PreviewHost.new()
	_host.preview = self
	_interpreter.host = _host
	_interpreter.globals = carried_globals
	_host.globals = carried_host_globals

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
	# A window's report is the same report for a different movie, and the two
	# would otherwise be indistinguishable in a log where a window opened, ran and
	# was forgotten in the middle of the stage's run.
	if _window_key != "":
		print("--- window %s (%s) ---" % [_window_key, movie_name()])
	print("lingo dispatched : %s" % JSON.stringify(_sent))
	print("lingo ran        : %s" % JSON.stringify(_ran))
	if _host != null:
		print("builtins reached : %s" % JSON.stringify(_host.reached))
		print("builtins unbound : %s" % JSON.stringify(_host.unbound))
	print("ccl cast list  : %s" % str(_ccl))
	print("film loops     : %s" % JSON.stringify(_loop_stats))
	# "The pacing feels wrong" has to be separable into "the score asked for a
	# hold and nothing took it" and "the score asked for nothing". Only five
	# frames in this corpus carry a transition and thirty-six carry a delay, so a
	# run that reports zero of each is usually telling the truth about the movie.
	print("clock          : %s, %d transition(s) played" % [
		_clock.status(), _transitions_played,
	])
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
	# A window's container and cast table are closed here rather than in
	# `lingo_forget_window`, because every `forget` in this corpus is a window
	# closing itself from a handler that is still running: closing the file under
	# that handler would have it reading a closed `FileAccess` for the rest of the
	# statement list.
	if _window_key != "":
		if _table != null:
			_table.close()
			_table = null
		if _movie != null:
			_movie.close()
			_movie = null


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


## Director clips every sprite to the stage; a Godot canvas item does not.
##
## A sprite is placed by its registration point, so art routinely hangs off the
## edge: measured over the corpus, **131,337 of 816,318 drawing sprite records
## (16.1%) reach past the 640x480 stage and 2,121 sit wholly outside it**, in 60
## of the 61 movies. Unclipped, every one of those pixels was painted into the
## letterbox — a walk cycle leaving a room dragged half a character across the
## black bar instead of disappearing behind the edge.
##
## This is the same mechanism `Control.clip_contents` uses, reached through
## `RenderingServer` because this node is a `Node2D` and has no such property.
## Setting it on the node's own canvas item covers every path that paints —
## bitmaps, film loop children, shape primitives and `draw_string` text — rather
## than each of them having to remember to intersect its own rect. The working
## renderer does the same thing one layer up (`director/movie_player.gd:43-44`).
##
## The rect is the stage, not the node's transform: `_fit_to_window` scales and
## offsets this node, and the clip is applied in the node's own coordinates, so
## it follows the stage through any window size without being recomputed.
##
## **Called from `_draw`, every paint, and that is not belt-and-braces.** Godot
## clears a canvas item's command list before each `NOTIFICATION_DRAW`, and the
## clear resets the clip flag along with the commands — the custom rect survives,
## the flag does not. Setting it once at startup therefore holds only until the
## first repaint, which is to say never: with the call in `_ready` alone the two
## screenshots either side of it were byte-identical and the artwork went on
## spilling into the letterbox. `tools/stage_clip.gd` is what caught that, by
## reading back real pixels rather than trusting the call.
func _clip_to_stage() -> void:
	# A window clips to its own movie's rect, not to the host stage's: a window
	# smaller than the stage must not paint outside itself, and one that is the
	# same size (every movie in this corpus) gets the same rectangle either way.
	_clip_rect = Rect2(Vector2.ZERO, window_size() if _window_key != "" else Vector2(STAGE))
	var item := get_canvas_item()
	RenderingServer.canvas_item_set_clip(item, true)
	RenderingServer.canvas_item_set_custom_rect(item, true, _clip_rect)


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
	# The cursor is built at the stage's scale, so a resize invalidates whatever
	# is installed. Forcing the cached key to miss makes the next resolve rebuild
	# it rather than leaving a cursor sized for the previous window.
	_cursor_applied = "?resized"
	_resolve_cursor()


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


## Decode one sprite's artwork ahead of time. Film loops pay for their children
## as well: a loop's members all appear on the same step, which is the worst
## version of the stall this exists to remove.
func _preload_one(sprite: Dictionary) -> void:
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	if m.is_empty():
		return
	if int(m.get("type", 0)) == 2:
		var key := "%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])]
		if not _loops.has(key):
			_loops[key] = _open_loop(int(sprite["cast_lib"]), m)
		var loop = _loops[key]
		if loop != null:
			for child in loop.children(0):
				_child_texture(child, int(sprite["cast_lib"]))
		return
	_texture_for(sprite)


func _process(delta: float) -> void:
	if _score == null or _paused:
		return
	if _score.frame(_index).is_empty():
		return
	# A click or a key may have moved the playhead since the last step. Take the
	# frame it landed on before deciding how much time that frame is owed, or the
	# old frame's tempo paces the new one.
	_sync_frame_entry()
	# Pay for the artwork of frames not yet reached, before asking the clock for
	# work. Time-boxed, so this cannot become the stall it exists to prevent --
	# and measured *and discounted*, because a movie should not owe catch-up
	# steps for time Director would have spent preloading.
	if _preloader != null:
		var loading := Time.get_ticks_usec()
		_preloader.run(_index, _preload_one, _effective)
		_clock.discount((Time.get_ticks_usec() - loading) / 1000000.0)
	var due := _clock.tick(delta)
	if due <= 0:
		return
	for _i in due:
		# Film loops advance on the movie's clock, not the playhead's: a loop
		# keeps animating on a frame the score is holding still on, which is
		# exactly what a talking character does while its line plays. That is why
		# the tick is counted before the wait is tested rather than after — a
		# wait-for-click frame with a character talking on it must not freeze.
		_ticks += 1
		if _clock.playhead_held():
			continue
		if _pending_enter != null:
			# The transition has finished arriving; the frame it revealed gets its
			# `enterFrame` now (§6.2).
			var resumed: Dictionary = _pending_enter
			_pending_enter = null
			_dispatch("enterFrame", resumed)
			continue
		_advance()
	queue_redraw()


## The playhead has landed somewhere this tick has not accounted for yet: take
## the frame's tempo, arm whatever it waits for, and start any transition it
## carries.
func _sync_frame_entry() -> void:
	if _index == _entered_index or _score == null:
		return
	_entered_index = _index
	var frame: Dictionary = _score.frame(_index)
	if frame.is_empty():
		return
	_clock.enter_frame(frame)
	_begin_transition(frame)


## Resolve this frame's transition and hold the playhead for as long as it takes.
##
## §10's three sources in order: a puppet transition set from Lingo, which is
## one-shot and consumed here; the frame's own, which in a D5 score is a
## reference to a transition cast member; or nothing. Only the *time* is
## reproduced — the new frame cuts in rather than wiping — because §10 is
## explicit that a cut reads as a stylistic choice while a wrong wipe reads as a
## bug, and that the duration is the part scripts are timed against.
##
## `tools/transition_survey.gd` says this corpus spends 4.0 s in transitions
## across five frames of three movies, against 74.0 s in tempo delays across
## thirty-six. Both were being skipped entirely.
func _begin_transition(frame: Dictionary) -> bool:
	var puppet := _puppet_transition
	_puppet_transition = {}
	var from_frame: Dictionary = {}
	var number := int(frame.get("transition_member", 0))
	if number > 0 and _table != null:
		var cast = _table.cast_for(int(frame.get("transition_lib", 1)))
		if cast != null:
			from_frame = cast.member(number)
	var transition: Dictionary = Transition.resolve(puppet, from_frame)
	if not Transition.is_transition(transition):
		return false
	_transitions_played += 1
	_clock.hold(Transition.hold_ms(transition), FrameClock.REASON_TRANSITION)
	_trace("f%d transition %s" % [_index, Transition.describe(transition)])
	return true


## One step of the movie, in Director's order (DIRECTOR_ENGINE.md §6.1).
##
## The correction that matters is where `exitFrame` sits. It belongs to the frame
## being *left*, and it runs at the **top of the step that leaves it** — with the
## playhead advance and the redraw after it, and `enterFrame` after those. Firing
## `prepareFrame`, `enterFrame` and `exitFrame` back to back on one frame, as this
## did, runs both halves of the standard "set up in enterFrame, tear down in
## exitFrame" idiom against the same rendered state, and puts `enterFrame` for a
## frame *before* the `exitFrame` of the frame it followed.
##
## For this title `exitFrame` is where everything lives — 2,504 of the corpus's
## handlers are `on exitFrame` against 33 `on enterFrame` and none at all for
## `prepareFrame` — so the walk state machine in `MovieScript 28
## whatodoeveryframe` is stepped from here, once per tick, and the frame it is
## stepped *for* is the one the player is looking at rather than the one the
## score is about to move to.
##
## The first step of a movie sends `exitFrame` for the frame it started on, and
## that is load-bearing rather than tidy: DAY1's frame 0 script `init all` is an
## `on exitFrame` handler that establishes the whole opening state of the room —
## the puppeted channels, `egozh`/`egozv`/`syz`, the inventory slots — and ends
## with `go("shore2")`. Skip it and the room draws with nothing initialised.
##
## Returns what the step did, so a harness can assert the ordering rather than
## infer it: `exited` is the frame `exitFrame` was sent for, -1 when it was
## skipped, and `frame` is the frame the rest of the step ran on.
func _advance() -> Dictionary:
	if not _lingo_on:
		_index = (_index + 1) % maxi(_score.frame_count, 1)
		_sync_frame_entry()
		return {"exited": -1, "frame": _index}

	# A step must never begin with an `enterFrame` still owed for the frame it is
	# about to leave. `_process` normally pays it when the transition's hold runs
	# out; a caller stepping this directly — a harness, the arrow keys — never
	# consults the clock, so the debt is settled here instead of being carried
	# into the next frame and dispatched against the wrong one.
	if _pending_enter != null:
		var owed: Dictionary = _pending_enter
		_pending_enter = null
		_dispatch("enterFrame", owed)
	# A `go to` queued from outside the step loop has already moved the playhead,
	# and Director sends no `exitFrame` for a frame it is leaving that way. The
	# step still runs: it renders and enters the frame the jump landed on, and the
	# *next* step is the one that leaves it.
	var exited := -1
	_held = _jump_queued
	_jump_queued = false
	if not _held:
		exited = _index
		_in_exit_frame = true
		_dispatch("exitFrame", _frame_script(_index))
		_in_exit_frame = false

	# Step 10, `updateCurrentFrame`: the handler above decided where the playhead
	# goes. `go to the frame` — how a room stands still at all — reaches this as a
	# hold, and any other `go` has already written the destination.
	if not _held:
		_index += 1
		if _index >= _score.frame_count:
			_index = 0
	_held = false
	_sync_frame_entry()

	var script := _frame_script(_index)
	_dispatch("prepareFrame", script)
	# Step 14, the draw. Godot paints at the end of the process frame rather than
	# here, so this is a request and not a completed paint: what `enterFrame`
	# writes below still lands in the same painted frame, where Director would
	# have shown it on the next one. A real divergence, and the cheapest one on
	# offer — the alternative is deferring every `enterFrame` by a whole frame.
	queue_redraw()
	_enter_frame_or_defer(script)
	return {"exited": exited, "frame": _index}


## Send `enterFrame`, or owe it until the frame has finished arriving.
##
## §6.2 plays a transition inside the render step, which sits between
## `prepareFrame` and `enterFrame`. A handler that runs on entry must not run
## while the frame it is about to touch is still wiping in — that is the whole
## difference between "set the room up once it is visible" and "set it up over
## the top of the room being left". Every path that enters a frame goes through
## here: the step loop, the first frame of a movie, and a `go to movie`.
func _enter_frame_or_defer(script: Dictionary) -> void:
	if _clock.holding_transition():
		_pending_enter = script
		return
	_dispatch("enterFrame", script)


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
		# Before the window routing too: it is the preview's own control and it is
		# drawn over everything, including a window.
		if SKIP_RECT.has_point(at):
			skip_to_end()
			return
		# A window over this point takes the click, and takes it whole — including
		# releasing *its* wait-for-click rather than the stage's (§9.2, §4.2).
		route_click(at)
		return
	if event is InputEventMouseMotion:
		var over := window_at(stage_mouse())
		if over != null and over != self:
			over._hover_channel = over._channel_at(stage_mouse() - over.position)
			over._resolve_cursor()
			queue_redraw()
			return
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
	#
	# A key goes to the front window when there is one, which is Director's rule
	# (§8.3: the keypress goes to the movie in the active window). Nothing in this
	# corpus installs a `keyDownScript` in a window movie, so this is the engine's
	# rule rather than this title's need — but sending it to the stage instead
	# would have the covered movie skipping speech it is not playing.
	var focus := window_at(stage_mouse())
	if focus == null:
		focus = _front_window()
	if focus == null:
		focus = self
	if not (event as InputEventKey).echo and focus._dispatch_key(event as InputEventKey):
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
			# Restarting from a frame that was holding — a delay, a wait for a
			# click — must not carry that hold onto the frame it restarts at, or
			# `R` looks like it did nothing.
			_clock.reset()
			_entered_index = -1
			_pending_enter = null
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
	# Re-armed here rather than at startup: the clip flag does not survive the
	# command-list clear that precedes every paint. See `_clip_to_stage`.
	_clip_to_stage()
	draw_rect(Rect2(Vector2.ZERO, _clip_rect.size), Color.BLACK, true)
	if _status != "":
		draw_string(ThemeDB.fallback_font, Vector2(16, 32), _status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.RED)
		return
	if _score == null:
		return

	# Rebuilt from scratch each paint rather than accumulated: it is a record of
	# what is on the stage now, and a field that left the frame must stop being in
	# it or a harness would assert against a channel that is no longer drawn.
	_text_drawn.clear()
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
		# A field draws glyphs, not pixels, so it takes the canvas directly rather
		# than going through the texture cache: its text is the one thing in the
		# frame a script rewrites constantly, and a cached texture would have to be
		# thrown away and rebuilt every time it did.
		if _draw_text(sprite):
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

	# The preview's own chrome belongs to the preview, not to every movie in it. A
	# window draws its movie and stops; the SKIP button and the HUD are drawn once,
	# by the stage, and the stage's children paint after it — so they would end up
	# *under* an open window. That is a known cosmetic limit and not worth
	# reordering the scene for: they are debug affordances, and §14's window has no
	# chrome of its own to draw in their place (`the windowType` is 2 at all 21
	# sites, Director's plain box with no title bar).
	if _window_key != "":
		return

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


## Decoded once per (member, ink, size, colours) and kept. A member costs
## milliseconds to decode and nothing to draw again, so the cost is paid on first
## appearance.
##
## Two cast types come through here. A bitmap is decoded, resized, keyed by its
## ink and then colourised; a shape is painted from its own geometry and needs
## none of that, because the shape primitives already draw only what they draw
## (13). Fields do not: they go through `_draw_text` instead.
func _texture_for(sprite: Dictionary) -> Texture2D:
	var lib := int(sprite["cast_lib"])
	var id := int(sprite["cast_id"])
	var ink := int(sprite["ink"])
	var m: Dictionary = _table.get_member(lib, id)
	if m.is_empty():
		return null
	var type_code := int(m.get("type", 0))
	if type_code != Ink.TYPE_BITMAP and type_code != Ink.TYPE_SHAPE:
		return null
	var key := _texture_key(sprite, _drawn_size(sprite, m))
	if _textures.has(key):
		return _textures[key]

	_textures[key] = null
	# Both colours, resolved through the palette once and used by both branches.
	# Director's 8-bit convention puts white at index 0 and black at 255, so the
	# defaults a sprite record carries are fore 255 and back 0 (2.2).
	var fore := Ink.colour_of(_palette, int(sprite.get("fore_color", Ink.INDEX_BLACK)))
	var back := Ink.colour_of(_palette, int(sprite.get("back_color", Ink.INDEX_WHITE)))
	var drawn := _drawn_size(sprite, m)

	if type_code == Ink.TYPE_SHAPE:
		# A shape has no artwork and no registration point: its sprite rect is the
		# whole of its geometry, and the image comes back already keyed — or as
		# null, which is the answer for the invisible hotspot rectangles that are
		# 60,100 of this corpus's 60,914 shape sprite records.
		var painted: Image = Shape.render(m, fore, back, Vector2i(drawn))
		if painted == null:
			return null
		_hit_images[key] = painted
		_textures[key] = ImageTexture.create_from_image(painted)
		return _textures[key]

	var f = _table.file_for(lib)
	if f == null:
		return null
	var chunk: PackedByteArray = f.read_chunk(int(m.get("data_chunk_id", -1)))
	var error: Array = []
	var image: Image = Bitmap.decode(m, chunk, _palette, error)
	if image == null:
		return null
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
			Ink.key_paper(image, back)
	# Colourisation last, and after keying rather than before it, which is not an
	# arbitrary order. A matte is built by flooding *white* in from the border, and
	# Director builds it from the member's own image; repainting the whites first
	# leaves the flood nothing to match and the sprite comes out as a solid
	# rectangle. Keying first also means the pixels this repaints are exactly the
	# ones that survived, so the keyed-out paper cannot come back as a colour.
	if Ink.applies_colour(ink, int(sprite.get("fore_color", Ink.INDEX_BLACK)),
			int(sprite.get("back_color", Ink.INDEX_WHITE))):
		Ink.apply_colour(image, fore, back)
	# Kept alongside the texture for hit-testing: a click lands on a sprite only
	# where the sprite actually has pixels, so a keyed-out region passes the
	# click through to whatever is behind it.
	_hit_images[key] = image
	_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]


## Draw a field member's text, and say whether this sprite was one.
##
## Until now `_texture_for` answered null for every member that was not a bitmap,
## so a field drew nothing: 11,525 sprite records across this corpus, and with
## them the whole HUD — the score, the inventory, the process list — while the
## Lingo that maintains them worked perfectly and had nowhere to show it.
##
## What is drawn is legible text in roughly the right place at roughly the right
## size and in the member's own colour and alignment. It is not period-accurate
## glyph rendering and does not pretend to be; `director/director_text.gd` says
## exactly what is and is not reproduced.
func _draw_text(sprite: Dictionary) -> bool:
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	if m.is_empty() or int(m.get("type", 0)) != Ink.TYPE_FIELD:
		return false
	var rect := _stage_rect(sprite)
	var text := _field_text_of(m)
	var style: Dictionary = Text.style_of(m)
	var lines: int = Text.draw(self, rect, text, style, Ink.blend_alpha(sprite))
	# What the paint actually put on the canvas, kept per channel. Headless Godot
	# builds the draw list and throws it away, so there is no painted surface to
	# read back and a harness has no other way to tell "the text reached the
	# screen" from "the sprite was skipped" — both look like a blank stage.
	_text_drawn[int(sprite["channel"])] = {
		"member": int(sprite["cast_id"]), "name": str(m.get("name", "")),
		"text": text, "lines": lines, "rect": rect,
		"font_size": int(style["font_size"]), "color": style["color"],
		"align": int(style["align"]),
	}
	# True even when there was nothing to draw. The sprite *is* a field, and
	# falling through to the bitmap path would only ask the cast for artwork that
	# a field does not have.
	return true


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
					# Same rule as the eligibility test above: the member's own
					# library decides, or a click runs a handler belonging to a
					# different cast's member of the same number.
					script = _script_in_lib(
						int(sprite["cast_lib"]), int(sprite["cast_id"])
					)
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
		var child_lib := _child_lib(child, lib)
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
func _child_lib(child: Dictionary, owner_lib: int) -> int:
	var name := str(child["cast_name"])
	if name == "":
		return owner_lib
	# A `ccl ` entry is the cast's authoring path, in whichever separator the
	# machine that saved the movie used: Mac colon form in the 1997 originals, a
	# Windows path in a file that has been through a converter. Only the filename
	# is of any use, so both separators are normalised before it is taken.
	var stem := name.replace(":", "/").replace("\\", "/").get_file().get_basename().to_lower()
	for number in _table.cast_libs:
		if str(_table.cast_libs[number].get("name", "")).to_lower() == stem:
			return int(number)
	# Unresolvable, which for a converted file is the normal case rather than the
	# exception: DAY1's `ccl ` holds a single truncated local path
	# (`...\PIP2DATA\won`) that names none of its five libraries.
	#
	# The loop's own library is the answer, not a guess at the name. A film
	# loop's children live in the cast the loop lives in, and that is knowledge
	# the container gives us directly. Guessing from the name is actively worse
	# than dropping the child: matching `won` as a prefix of `wonder` resolved
	# master's loops 2:57 and 2:59 into the *wonder* cast, where the same member
	# numbers name unrelated art -- so the loops drew, with somebody else's
	# pictures in them. A missing asset is a bug you can see; a plausible wrong
	# one is a bug you argue about.
	return owner_lib


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


## A child names its cast by name, not by this movie's library number -- and when
## that name resolves to nothing, the loop's own library is the answer. Same rule
## as `_child_lib`, which this defers to so the two cannot drift apart.
func _child_texture(child: Dictionary, owner_lib: int = 1) -> Texture2D:
	var lib := _child_lib(child, owner_lib)
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
		#
		# `visible` is not geometry and does not go with them. It is channel
		# state, like `the cursor of sprite`: Director does not un-hide a sprite
		# because the score moved that channel to another member, and a port that
		# does gets a very specific bug -- a room hides something during its
		# initialisation and it reappears later, looking like a rendering fault.
		#
		# DAY1 is the case that found this. Its `init all` runs as the frame
		# script on frame 0 and does `sprite(6).visible = 0`, but channel 6 is
		# *empty* on frame 0, so no member was ever recorded against the
		# override. The moment channel 6 acquires a member -- at the beach, 37
		# frames later -- the test below fires and the sprite is un-hidden. The
		# hide was guaranteed to be discarded before it could ever apply.
		var kept: Dictionary = {"_member": int(sprite["cast_id"])}
		if over.has("visible"):
			kept["visible"] = over["visible"]
			_overrides[channel] = kept
		else:
			_overrides.erase(channel)
		over = kept
		if int(LingoValue.to_int(over.get("visible", 1))) == 0:
			return {}
		return sprite
	if int(LingoValue.to_int(over.get("visible", 1))) == 0:
		return {}
	var out := sprite.duplicate()
	for key in ["membernum", "castnum"]:
		if over.has(key):
			out["cast_id"] = int(over[key])
	# Director's `setCast` rule: a member swap replaces the sprite's width and
	# height with the new member's natural size, unless the stretch flag says the
	# author deliberately resized this sprite.
	#
	# It matters here because the score's width and height describe whatever
	# member the *score* put on this channel, and a script that swaps the member
	# leaves them describing the wrong artwork. This game walks its characters
	# entirely by member swap -- `member("walkright" & syz & x)`, where `syz` is
	# one of six size tiers and `x` the animation frame -- and never writes a
	# width or a height anywhere. So without this every frame of the cycle is
	# squashed into the previous one's rect, which reads as the character
	# stretching as his arms move, and all six size tiers draw at one size, which
	# reads as perspective scaling that stopped working.
	if int(out["cast_id"]) != int(sprite["cast_id"]) and not bool(sprite["stretch"]):
		var swapped: Dictionary = _table.get_member(
			int(sprite["cast_lib"]), int(out["cast_id"])
		)
		if int(swapped.get("width", 0)) > 0 and int(swapped.get("height", 0)) > 0:
			out["width"] = int(swapped["width"])
			out["height"] = int(swapped["height"])
	# A script that writes `the width of sprite` resizes it. Deliberately without
	# setting `stretch`: the flag does not mean "is resized", it means "the author
	# resized this deliberately", and all it governs is whether a cast swap is
	# allowed to reset the size back to the member's natural one. Forcing it here
	# changed which branch the drawn size and the texture cache took, for a
	# property that should only have changed a number.
	# Coerced through Lingo's own rules rather than GDScript's. A script can
	# legitimately store VOID here -- `set the locH of sprite 30 to egozh` when
	# `egozh` has never been set does exactly that -- and `int(null)` is not a
	# conversion in GDScript, it is a runtime error that aborts whatever is
	# running. This one aborted `_draw` partway through, every frame, so the
	# sprites after it in channel order simply vanished. VOID is 0 in Director's
	# numeric context, which is what `LingoValue.to_int` answers.
	if over.has("width"):
		out["width"] = LingoValue.to_int(over["width"])
	if over.has("height"):
		out["height"] = LingoValue.to_int(over["height"])
	if over.has("loch"):
		out["loc_h"] = LingoValue.to_int(over["loch"])
	if over.has("locv"):
		out["loc_v"] = LingoValue.to_int(over["locv"])
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
		# Puppet state, not the raw score record. The descent used to read the
		# score directly, which meant a sprite a script had hidden still absorbed
		# every click inside its rect, and a sprite a script had moved absorbed
		# them at the position the score last gave it rather than where it is.
		#
		# Both are invisible from the player's chair and read as "something I
		# cannot see is covering what I am trying to click". DAY1's beach frame
		# script alone hides sprites 15, 17 and 33, all of them on channels above
		# the backdrop and two of them above the character.
		#
		# `visible` is the case the reference is most explicit about: false means
		# not drawn *and* not hit-tested, and it is the first thing `isMouseIn`
		# checks. `_effective` answers `{}` for it.
		var sprite: Dictionary = _effective(sprites[i])
		if sprite.is_empty():
			continue
		if not _sprite_rect(sprite).has_point(at):
			continue
		# Only Matte samples the artwork, and only on a bitmap. Every other ink is
		# a plain rectangle for hit-testing even when it renders per-pixel â€” the
		# asymmetry is deliberate in Director and easy to get wrong in both
		# directions. The cast type is the other half of the same rule: a matte is
		# flooded in from the border of the *member's image*, and a shape has no
		# image, so a matte-inked shape hit-tests as its box. Without that, this
		# game's invisible shape hotspots that happen to carry Matte answered no
		# click at all (`director/director_ink.gd:hits_per_pixel`).
		var member: Dictionary = _table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		if _hit_pixels \
				and Ink.hits_per_pixel(int(sprite["ink"]), int(member.get("type", 0))) \
				and not _opaque_at(sprite, at):
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
	# In the library the sprite names, not by number alone. Member numbers are
	# per cast, so a number-only search answers with a stranger -- and here that
	# is not silence but a false positive: it makes a sprite clickable because
	# some *other* cast happens to have a script at that number, and the click
	# then runs that stranger.
	#
	# DAY1's beach is the case that found it. Channel 1 is `3:10`, the room
	# backdrop `shore2`, a plain bitmap with no script of its own. A number-only
	# search found a mouse handler anyway, so the backdrop answered clicks across
	# its whole 640x400 rect -- and since the walkable ground is a separate Matte
	# sprite on channel 2 covering only the bottom 154 pixels, clicking the *sea*
	# fell through to the backdrop and walked the character up into it.
	if _declares_mouse_handler(_script_in_lib(
		int(sprite["cast_lib"]), int(sprite["cast_id"])
	)):
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
	for raw_sprite in frame.get("sprites", []):
		# Puppet state, exactly as the hit test sees it. A sprite a script has
		# hidden or moved is not where the score says, and outlining it there
		# would be worse than not outlining it at all.
		var sprite: Dictionary = _effective(raw_sprite)
		if sprite.is_empty():
			continue
		var channel := int(sprite["channel"])
		var rect := _sprite_rect(sprite)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		# Only what can actually answer a click. This used to outline every
		# sprite and merely tint the ones with a behaviour attached, which made
		# the overlay a picture of the score rather than of what the mouse can
		# reach -- and eligibility is not "has a behaviour": a member script, a
		# button or `moveable` all qualify, and a behaviour that declares no
		# mouse handler does not.
		if not _responds_to_mouse(sprite):
			continue
		# Green where the whole rectangle answers, amber where only the artwork
		# does. That distinction is the one that costs people time: a Matte
		# sprite is clickable on its pixels and transparent to the mouse
		# everywhere else, so an outline that implies a solid target is a lie.
		var per_pixel := _hit_pixels and Ink.hits_per_pixel(int(sprite["ink"]))
		var hovered := channel == _hover_channel
		var tint := Color(1.0, 0.75, 0.2) if per_pixel else Color(0.2, 1.0, 0.4)
		if hovered:
			draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.18), true)
		draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.95 if hovered else 0.45),
			false, 2.0 if hovered else 1.0)
		if hovered:
			draw_string(font, rect.position + Vector2(2, -3),
				"ch%d  %d:%d  %s" % [
					channel, int(sprite["cast_lib"]), int(sprite["cast_id"]),
					"artwork only" if per_pixel else "whole rect",
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
## So does the fore colour, for two reasons that arrived together: it is what
## colourisation repaints an image's black pixels (2.3), and it is the colour a
## shape's primitives paint with (13). Without it the second sprite to share a
## member gets the first one's colour — and this game recolours one 60x23 shape
## through several colours across 48,570 sprite records, so the omission would be
## visible everywhere the same hotspot is drawn twice.
func _texture_key(sprite: Dictionary, drawn: Vector2) -> String:
	return "%d:%d:%d:%dx%d:%d:%d" % [
		int(sprite["cast_lib"]), int(sprite["cast_id"]), int(sprite["ink"]),
		int(drawn.x), int(drawn.y), int(sprite.get("back_color", 0)),
		int(sprite.get("fore_color", Ink.INDEX_BLACK)),
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
	# A jump cancels every wait (§9.2) — including one this button is being used
	# to escape, since a movie sitting on a wait-for-click frame is exactly when
	# a player reaches for it.
	_clock.reset()
	_pending_enter = null
	# The landing frame is entered by the next step, the way any other jump from
	# outside the step loop is: that step skips `exitFrame`, renders, and sends
	# `enterFrame`. Sending `enterFrame` from here as well ran it twice.
	_jump_queued = true
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


## `puppetTransition <type>[, <chunkSize>, <duration in quarter-seconds>, <area>]`.
##
## Source 1 of §10's three, and the only one a script can reach. It applies to
## the next frame change and is consumed there — Director does not keep it armed,
## which is why the call is always written immediately before the `go` that uses
## it and never has to be cancelled.
##
## The duration argument is in **quarter seconds**, unlike the transition cast
## member's, which is in milliseconds. That is a genuine Director inconsistency
## and not a decoding error; getting it wrong scales every scripted transition by
## 250.
##
## Nothing in this game's 61 movies calls it — `tools/transition_survey.gd` and a
## grep of `reference/lingo/` both say zero — so this exists for the engine's
## sake rather than this title's, and `tools/frame_events.gd` is what exercises
## it.
func lingo_puppet_transition(args: Array) -> void:
	if args.is_empty():
		_puppet_transition = {}
		return
	var type_code := LingoValue.to_int(args[0])
	if type_code <= 0:
		_puppet_transition = {}
		return
	var quarters: int = LingoValue.to_int(args[2]) if args.size() >= 3 else 4
	_puppet_transition = {
		"transition_type": type_code,
		"chunk_size": LingoValue.to_int(args[1]) if args.size() >= 2 else 16,
		"duration_ms": float(maxi(quarters, 1)) * 250.0,
		"change_area": LingoValue.to_int(args[3]) if args.size() >= 4 else 0,
		"flags": 0,
	}


## A frame jump does **not** drop what scripts puppeted.
##
## This used to clear every override whenever a jump crossed a marker boundary,
## on the reasoning that an override should not outlive its room -- a script
## hides sprite 15 to take a collectable off the beach, the playhead moves
## elsewhere, and channel 15 stays invisible over whatever the score puts there
## next.
##
## That symptom is real but the cure was wrong, and wrong in a way that
## destroyed room initialisation wholesale. `DIRECTOR_ENGINE.md` §5.4 is
## explicit: puppet state survives frame jumps and `go to`, and dies only on
## `puppetSprite N, FALSE` or a movie change. Nothing in the frame loop clears
## it implicitly.
##
## DAY1 is the case that found it. Its `init all` is the frame script on frame 0:
## it hides sprites 6, 15 and 33, shows 17 and 23, puppets channels 30, 100 and
## 103-110, and then ends with `go("shore2")` -- a jump to frame 37, a different
## marker. Every one of those writes was thrown away on the way out, so the room
## arrived having initialised nothing. The boat that should have been hidden was
## visible, and the cursors survived only because they are kept in a separate
## dictionary for exactly this reason.
##
## The stale-collectable case is handled by Director's own mechanism instead. The
## score carries no visible flag, so visibility is channel state rather than
## something the score restores, and this game re-establishes it on entry to
## every room: DAY1's own frame script sets the visibility of sprites 15, 17 and
## 33 on every `enterFrame`.
func lingo_go_frame(frame: int) -> void:
	_held = true
	var target := clampi(frame, 0, maxi(_score.frame_count - 1, 0))
	_index = target
	# A pending `go to` cancels every wait — sound, click and delay alike (§9.2).
	# It is how a script escapes a wait-for-click frame without a click, and
	# without it a room reached by `go` would serve out the wait the frame it left
	# had armed.
	_clock.release()
	if not _in_exit_frame:
		# Anywhere but `exitFrame` — a mouse handler, a key handler, `enterFrame`
		# — is after the playhead has already been resolved for this tick, so the
		# jump belongs to the next one. Director sends no `exitFrame` for a frame
		# it is leaving that way (§6.1 step 7); that next step renders and enters
		# the destination, and the step after it is the first to leave it.
		_jump_queued = true


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
		target = _paths.resolve(name.replace(":", "/").replace("\\", "/").get_file(), here)
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

	var previous_path := str(_movie.path) if _movie != null else ""
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
	var config = Config.new()
	_config = config if config.read(_movie) else null
	_ccl = PackedStringArray()
	var ccl_ids: Array = _movie.ids_of("ccl ")
	if not ccl_ids.is_empty():
		_ccl = FilmLoop.read_cast_list(_movie.read_chunk(ccl_ids[0]))

	_textures.clear()
	_hit_images.clear()
	# Field overrides used to be dropped wholesale here, because the key was
	# `<library number>:<member>` and a library number is local to the movie that
	# was open when a script wrote it — carried across, member 10 of the next
	# movie's cast got the last movie's score written into it, which is not a
	# stale value but text appearing on an unrelated field.
	#
	# `_field_key` now names the cast's *file*, so only the movie's own internal
	# cast can collide, and that is exactly what is dropped here. What survives is
	# the shared external cast, and that is a correction rather than a saving: the
	# player's score and inventory live in `field "points"` and
	# `field "objectsfield"` of the linked cast, and clearing them on every `go to
	# movie` reset the HUD at every doorway. It is also what makes a save
	# restorable at all — `SAVELOAD` writes seven of those fields and then sends
	# the stage to another movie in the next statement.
	_forget_field_text_of(str(previous_path))
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
	_preloader = Preloader.new(_score)
	_index = 0
	_ticks = 0
	_held = true
	# The clock belongs to the movie that is being left: its tempo, any wait it
	# had armed and any transition it was still playing all go with it. So does
	# the deferred `enterFrame` a transition was holding — the frame it was owed
	# to is in a container that is now closed.
	_clock.reset()
	_pending_enter = null
	_puppet_transition = {}
	_entered_index = -1
	_jump_queued = false

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
	# Entered like the first frame of any movie: the tempo is taken from the frame
	# rather than inherited, so a room that runs at 30 fps does not open at the
	# rate the movie before it was using.
	_sync_frame_entry()
	if _lingo_on:
		_enter_frame_or_defer(_frame_script(_index))
	get_window().title = "%s  â€”  %d frames" % [target.get_file(), _score.frame_count]
	print("go movie -> %s frame %d" % [target.get_file(), _index])
	queue_redraw()


# --------------------------------------------------------- windows (§14)

## The preview that owns the stage — this one, or the one that opened it.
##
## Every window operation funnels here first. `forget(window(cdsavepath &
## "saveload.dxr"))` is written *inside* `SAVELOAD.dir` and runs on the window's
## own interpreter, so a window that kept its own registry would look for a window
## it does not have and the save screen would never close.
func stage_preview() -> Node:
	return _stage_preview if _stage_preview != null else self


## One window per movie, addressed by its file stem.
##
## The corpus names the same window four ways — `window("saveload.dxr")` and
## `window(cdsavepath & "saveload.dxr")` where `cdsavepath` is a global holding a
## directory, plus the `.dxr` spelling of files that are `.dir` on this disc — and
## all four have to be the same window or `forget` closes nothing.
static func window_key(name: String) -> String:
	return name.strip_edges().replace(":", "/").replace("\\", "/") \
		.get_file().get_basename().to_lower()


## `window("map.dxr")` — the handle, creating the window's movie on first
## reference.
##
## Director makes the window object exist as soon as it is named, which is what
## lets a script set properties on it and `tell` it before `open`. The handle is
## a plain Dictionary rather than a new class so it can travel through the
## interpreter as an ordinary Lingo value; `{"window": ""}` is the stage.
func lingo_window(name: String) -> Dictionary:
	var owner := stage_preview()
	if owner != self:
		return owner.lingo_window(name)
	var key := window_key(name)
	if key == "":
		return {"window": ""}
	if not _windows.has(key):
		_create_window(key, name)
	return {"window": key}


func _create_window(key: String, name: String) -> Node:
	if _paths == null or _movie == null:
		return null
	var here := str(_movie.path).get_base_dir()
	var target: String = _paths.resolve(name.replace(":", "/").replace("\\", "/").get_file(), here)
	if target == "":
		# `runjokes` names `jokes.dxr` and this disc has no such file — the whole
		# 36-site `jokes.dxr` branch of the corpus is dead, and nothing calls
		# `runjokes` either. A window whose movie is missing stays unresolvable, so
		# `tell` reports it rather than running the body on the asking movie.
		_trace("window %s -> not found" % name)
		return null
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var node: Node = scene.instantiate()
	node._stage_preview = self
	node._window_key = key
	node._window_path = target
	_windows[key] = node
	add_child(node)
	return node


## `open(window("joke.dxr"))` — show it, start it and send it its opening events.
func lingo_open_window(name: String) -> void:
	var owner := stage_preview()
	if owner != self:
		owner.lingo_open_window(name)
		return
	var key := window_key(name)
	if not _windows.has(key):
		_create_window(key, name)
	var node: Node = _windows.get(key)
	if node == null:
		_trace("open window %s -> no such movie" % name)
		return
	# Re-opening an open window raises it rather than restarting it, which is what
	# Director does and what the score of a window that opens itself twice needs.
	_window_order.erase(key)
	_window_order.append(key)
	move_child(node, get_child_count() - 1)
	node.window_shown()
	queue_redraw()


## `forget(window("map.dxr"))` and `close(window(...))`.
##
## `forget` destroys the window and its movie; `close` only hides it. This corpus
## calls `forget` 22 times and `close` never, and every one of the 22 is the
## window closing *itself* from its own `exitFrame` or `mouseUp` — MAP's twelve
## destination buttons, SAVELOAD's slots, JOKE's wait-for-click frame. So the
## teardown runs while the window's own script is on the stack: the node is
## detached from the registry now and freed at the end of the frame, and its
## container and cast table are closed in `_exit_tree` rather than here, or the
## handler still running would be reading a closed file.
func lingo_forget_window(name: String, destroy: bool = true) -> void:
	var owner := stage_preview()
	if owner != self:
		owner.lingo_forget_window(name, destroy)
		return
	var key := window_key(name)
	var node: Node = _windows.get(key)
	if node == null:
		return
	node.window_hidden()
	if not destroy:
		return
	_windows.erase(key)
	_window_order.erase(key)
	node.queue_free()
	queue_redraw()


## The interpreter a `tell` should be routed to, or null when there is no such
## window. Null is not the same as "run it here" — see the `tell` arm in
## `lingo/lingo_interpreter.gd`.
func window_interpreter(key: String):
	var owner := stage_preview()
	if key == "":
		return owner._interpreter
	if owner != self:
		return owner.window_interpreter(key)
	var node: Node = _windows.get(key)
	return node._interpreter if node != null else null


## `the windowType` / `the centerStage` of a named window, and `the rect`.
##
## Everything is stored on the window it names rather than on whoever set it,
## which is the correction this whole change is about: before it, `set the
## windowType of window "joke.dxr" to 2` went to the *stage's* system properties.
func lingo_set_window_prop(key: String, prop: String, value: Variant) -> void:
	var owner := stage_preview()
	var node: Node = owner if key == "" else owner._windows.get(key)
	if node == null:
		return
	node.set_own_window_prop(prop, value)


func lingo_window_prop(key: String, prop: String) -> Variant:
	var owner := stage_preview()
	var node: Node = owner if key == "" else owner._windows.get(key)
	if node == null:
		return 0
	return node.own_window_prop(prop)


func set_own_window_prop(prop: String, value: Variant) -> void:
	match prop:
		"windowtype":
			_window_type = LingoValue.to_int(value)
		"centerstage":
			_center_stage = LingoValue.to_int(value) != 0
			if _window_shown:
				position = window_origin()
				queue_redraw()
		"visible":
			if LingoValue.to_int(value) != 0:
				window_shown()
			else:
				window_hidden()


func own_window_prop(prop: String) -> Variant:
	match prop:
		"windowtype":
			return _window_type
		"centerstage":
			return 1 if _center_stage else 0
		"visible":
			return 1 if _window_shown else 0
		"rect":
			var at := window_origin()
			var size := window_size()
			return [int(at.x), int(at.y), int(at.x + size.x), int(at.y + size.y)]
		"moviename", "filename":
			return movie_name()
	return 0


## The window's size on the host stage: its movie's own `DRCF` rect.
##
## Every movie in this corpus declares 640x480 (`tools/window_survey.gd` over all
## 61 containers that have a config), so in practice a window covers the stage
## exactly — which is why no window chrome is drawn and why a click anywhere goes
## to the window. Read rather than assumed, so a title whose window movie is
## genuinely smaller gets a smaller window and the clicks outside it still reach
## the stage.
func window_size() -> Vector2:
	if _config != null:
		return Vector2(_config.rect.size)
	return Vector2(STAGE)


## Where the window sits, in the stage's coordinates.
##
## `the centerStage` centres the movie's stage on the screen, and all 21 sites in
## this corpus set it, so this is the path that runs. Without it Director puts the
## window at the rect its movie was authored with, which is a screen coordinate —
## so it is taken relative to the stage movie's own rect, the only thing here that
## shares that coordinate space.
func window_origin() -> Vector2:
	var mine := window_size()
	if _center_stage:
		return ((Vector2(STAGE) - mine) * 0.5).floor()
	var host = stage_preview()
	if _config != null and host != null and host._config != null:
		return Vector2(_config.rect.position - host._config.rect.position)
	return Vector2.ZERO


## Show the window and let it run. Idempotent: `open` on an open window raises it
## and does not restart the movie.
func window_shown() -> void:
	if _window_shown:
		visible = true
		return
	_window_shown = true
	visible = true
	position = window_origin()
	set_process(true)
	# Entered exactly as a movie's first frame is entered on the stage, and for
	# the same reason: the frame's own tempo has to arm the clock before anything
	# runs on it. The frame may not be 0 — `NIGHT1 BehaviorScript 415` says
	# `tell window("map.dxr") / go("nightmap") / end tell` *before* `open`, so the
	# playhead is wherever that put it.
	_sync_frame_entry()
	if _lingo_on and _interpreter != null:
		_dispatch("prepareMovie", {})
		_dispatch("startMovie", {})
		_enter_frame_or_defer(_frame_script(_index))
	queue_redraw()


## Stop the window drawing and running, without destroying it.
func window_hidden() -> void:
	_window_shown = false
	visible = false
	set_process(false)
	# The clock belongs to the movie that was showing: a wait-for-click or a
	# tempo delay it was holding must not be waiting when it is opened again.
	_clock.reset()
	_pending_enter = null


## The front-most open window, or null. Director's active window, which is where
## a keypress goes when the pointer is not over anything.
func _front_window() -> Node:
	var owner := stage_preview()
	for i in range(owner._window_order.size() - 1, -1, -1):
		var node: Node = owner._windows.get(owner._window_order[i])
		if node != null and node._window_shown:
			return node
	return null


## The window a stage point lands in, front-most first, or null.
##
## §4.2's search order, one level up: Director hit-tests windows before sprites,
## and the front window takes the click whether or not anything in it answers.
func window_at(at: Vector2) -> Node:
	var owner := stage_preview()
	for i in range(owner._window_order.size() - 1, -1, -1):
		var node: Node = owner._windows.get(owner._window_order[i])
		if node == null or not node._window_shown:
			continue
		if Rect2(node.position, node.window_size()).has_point(at):
			return node
	return null


## Deliver a click at a stage point to whichever movie owns that point.
##
## Called from `_input` and directly by the harnesses, which is the point of it
## being a method: routing that only exists inside an `InputEvent` handler cannot
## be asserted headlessly, and "the click went to the wrong movie" is precisely
## the failure this change is about.
func route_click(at: Vector2) -> Node:
	var front := window_at(at)
	if front != null and front != self:
		front.route_click(at - front.position)
		return front
	# A wait-for-click frame is released by the mouse-down and not by the score
	# (§9.2), and it is released in the movie that was clicked — JOKE's last frame
	# is a wait-for-click that the player ends by clicking the window.
	_clock.clicked()
	_begin_drag(at)
	_click(at)
	return self


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
	# Returning from an interlude is a jump like any other: it cancels the wait
	# the interlude's last frame armed, and the frame it returns to is entered by
	# the next step rather than by this call (§6.1 step 7, §9.2).
	_clock.release()
	if not _in_exit_frame:
		_jump_queued = true
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
				var scaled := _cursor_for_stage(
					composed["image"] as Image, composed["hotspot"] as Vector2
				)
				Input.set_custom_mouse_cursor(
					ImageTexture.create_from_image(scaled["image"]),
					Input.CURSOR_ARROW, scaled["hotspot"]
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
## Godot refuses a custom cursor above this, and a cursor that large would be
## absurd anyway. 16x16 art at a 4x stage is 64, so the ceiling only bites on
## genuinely enormous windows, where the cursor stops growing rather than
## disappearing.
const MAX_CURSOR_PIXELS := 128


## A cursor is stage art and has to grow with the stage.
##
## Everything else the movie draws goes through this node's own `scale`, which
## `_fit_to_window` sets from the window size -- 1.5x at the default window. The
## OS cursor does not: `Input.set_custom_mouse_cursor` takes real screen pixels,
## so a 16x16 cursor handed over unscaled is drawn at a third of the size of the
## artwork it is supposed to belong to, which is what "the cursor is tiny" is.
##
## Nearest-neighbour on purpose: this is 1-bit art from 1997 with hard edges, and
## smoothing it produces a grey halo around every pixel. The hotspot scales with
## the image, because Godot reads it in the texture's own pixels.
func _cursor_for_stage(image: Image, hotspot: Vector2) -> Dictionary:
	var factor := maxi(1, int(round(scale.x)))
	if factor <= 1:
		return {"image": image, "hotspot": hotspot}
	var width := image.get_width() * factor
	var height := image.get_height() * factor
	if width > MAX_CURSOR_PIXELS or height > MAX_CURSOR_PIXELS:
		return {"image": image, "hotspot": hotspot}
	var grown := Image.new()
	grown.copy_from(image)
	grown.resize(width, height, Image.INTERPOLATE_NEAREST)
	return {"image": grown, "hotspot": hotspot * float(factor)}


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


## A sound channel's properties. `volume` is the one this game sets: 66 writes
## and 2 reads across channels 1 to 4, measured over `reference/lingo/`.
##
## The state lives in `AudioDirector` rather than here. It used to be a dictionary
## on this node, which meant the two hosts each had their own idea of a channel's
## volume and neither survived a `go to movie` — and `set the volume of sound 3
## to the volume of sound 3 - 20`, the corpus's one read-modify-write, steps a
## loop down over several frames and needs its own previous write back.
func lingo_sound_prop(channel: int, prop: String) -> Variant:
	if _audio == null:
		return 0
	match prop:
		"volume":
			return int(_audio.call("channel_volume", channel))
		"loop", "looping":
			return 0
	return 0


func lingo_set_sound_prop(channel: int, prop: String, value: Variant) -> void:
	if prop != "volume" or _audio == null:
		return
	_audio.call("set_channel_volume", channel, int(value))
	_trace("f%d volume ch%d = %d" % [_index, channel, int(value)])


## `the soundLevel`, 0-7: the system volume, above the per-channel volumes rather
## than one of them. 7 writes and 7 reads in this corpus, all in one movie's
## options screen, where the read is what places the slider knob.
func lingo_sound_level() -> int:
	return int(_audio.get("sound_level")) if _audio != null else 7


func lingo_set_sound_level(level: int) -> void:
	if _audio != null:
		_audio.call("set_sound_level", level)
	_trace("f%d soundLevel = %d" % [_index, level])


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
##
## An immediately repeated line is counted rather than appended. A hold loop that
## calls `sound stop 2` on every tick otherwise writes forty identical lines and
## the forty that mattered fall off the front — which is what a 40-line tail
## looks like when the thing being traced is inside the loop it is diagnosing.
func _trace(line: String) -> void:
	if not _traced.is_empty():
		var last := str(_traced[-1])
		var head := last.split("  x")[0]
		if head == line:
			var seen := 1 if last == line else int(last.substr(head.length() + 3))
			_traced[-1] = "%s  x%d" % [line, seen + 1]
			return
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
	_trace("f%d stop ch%d" % [_index, channel])


func lingo_stop_all_sound() -> void:
	if _audio != null and _audio.has_method("stop_all"):
		_audio.call("stop_all")
	_trace("f%d stop all" % _index)


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
	var where := _resolve_member_ref(which, cast)
	var m: Dictionary = _table.get_member(int(where[0]), int(where[1]))
	match prop:
		"name":
			return str(m.get("name", ""))
		"width":
			return int(m.get("width", 0))
		"height":
			return int(m.get("height", 0))
		"text":
			# Through the same override the renderer reads, or `the text of member`
			# would answer the authored placeholder while the screen showed the
			# current value.
			return _field_text_of(m)
		"number", "membernum", "castnum":
			# `member("able1").memberNum` and `the number of member "able1"` ask the
			# same question by two spellings, and only the second had a path here:
			# the first fell out of this match and returned 0. That is silent,
			# because 0 is a plausible member number. Every `set the cursor of
			# sprite i to [member("able1").memberNum, member("able2").memberNum]`
			# in MAP therefore stored [0, 0] and composed to nothing. The same
			# omission was found and fixed in `lingo/lingo_host.gd` for the other
			# renderer; this host had it too.
			return int(where[1])
	return 0


## `field "name"`, and `put x into field "name"`.
##
## Two things had to change together here, and neither is worth much alone. The
## read used to look only in cast library 1, the movie's own; a `field` a script
## names by itself is resolved across every library the movie can address, and in
## this game the shared HUD fields — the score, the inventory — live in a *linked*
## cast, so `field "points"` answered "" from a movie that has one on screen. And
## the write was a no-op, so nothing a script put into a field could ever be read
## back or drawn: the score would have rendered its authored placeholder for ever.
func lingo_field(name: String, _cast: String) -> Variant:
	var where := _resolve_field(name)
	if where.is_empty():
		return ""
	return _field_text_of(_table.get_member(int(where[0]), int(where[1])))


func lingo_set_field(name: String, _cast: String, text: String) -> void:
	var where := _resolve_field(name)
	if where.is_empty():
		return
	_field_text[_field_key(int(where[0]), int(where[1]))] = text
	# The text is drawn straight from here on the next paint, so a write has to ask
	# for one. Without it a HUD updates only when something else happens to redraw.
	queue_redraw()


## `[cast library, member number]` for a field name, or `[]`.
##
## `_resolve_member_ref` already searches every library the movie can address, in
## Director's own order, and it is asked first so that a `field` and a `member`
## reference to the same name never disagree. What it cannot do is prefer a field:
## a name is unique within a cast and not across casts, so a *bitmap* called
## `points` in the movie's own library would win over the *field* called `points`
## in the shared one, and the write would land on a member that has no text. So the
## answer is accepted only when it really is a field, and otherwise the libraries
## are walked again looking only at fields.
func _resolve_field(name: String) -> Array:
	if _table == null:
		return []
	var first := _resolve_member_ref(name, "")
	if int(first[1]) > 0 \
			and int(_table.get_member(int(first[0]), int(first[1])).get("type", 0)) \
				== Ink.TYPE_FIELD:
		return first
	var libs: Array = _table.cast_libs.keys()
	libs.sort()
	for lib in libs:
		var cast = _table.cast_for(int(lib))
		if cast == null:
			continue
		var number: int = cast.number_of(name)
		if number <= 0:
			continue
		if int(cast.member(number).get("type", 0)) == Ink.TYPE_FIELD:
			return [int(lib), number]
	return []


## What a field member currently holds: what a script last put there, or failing
## that the text authored into its `STXT`.
func _field_text_of(member: Dictionary) -> String:
	if member.is_empty():
		return ""
	var key := _field_key(int(member.get("cast_lib", 1)), int(member.get("cast_id", 0)))
	if _field_text.has(key):
		return str(_field_text[key])
	return str(member.get("text", ""))


## Where a field override lives: the cast's file, then the member number in it.
##
## Not the library number. A library number is local to a movie — `MASTER.CST` is
## library 2 in `SAVELOAD.dir` and need not be 2 in the room the save returns to —
## and `SAVELOAD` writes `field "points" of castLib "master"` for the stage to
## read back out of the same file. Keyed by number, a window and the stage would
## be writing and reading two different entries whenever the two movies happened
## to number the shared cast differently, and agreeing whenever they happened to
## match: a bug that is invisible until the one movie that numbers it otherwise.
func _field_key(lib: int, number: int) -> String:
	var path := ""
	if _table != null and _table.cast_libs.has(lib):
		path = str((_table.cast_libs[lib] as Dictionary).get("resolved_path", ""))
	if path == "":
		# No table, or a library it does not know: fall back to the number so the
		# entry is still addressable, and keep it distinguishable from a real path.
		path = "#%d" % lib
	return "%s:%d" % [path.to_lower(), number]


## Drop the field overrides that belong to one container's own cast.
##
## Called on `go to movie`, with the movie being left. See the call site for why
## the *linked* casts are deliberately not dropped.
func _forget_field_text_of(container_path: String) -> void:
	if container_path == "":
		return
	var prefix := container_path.to_lower() + ":"
	for key in _field_text.keys():
		if str(key).begins_with(prefix):
			_field_text.erase(key)


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
## Which library and member a Lingo member reference names.
##
## The library is part of the answer, not a hint. Member numbers are per cast, so
## `member(64, "island2")` and member 64 of the movie's own cast are different
## members that happen to share a number, and resolving in the wrong one returns
## a stranger rather than nothing -- which is silence, not an error.
##
## `searchfunk` in MASTER is what this cost. It does
## `myname = member(the memberNum of sprite the clickOn, "island2").name` and
## then matches that name against a table to decide what a click on the scenery
## reveals. Resolving in library 1 gave it the name of an unrelated member, no
## line ever matched, and the handler returned having done nothing. Every "I
## clicked the thing and nothing happened" of that shape is this.
##
## An unnamed cast means the movie's own, which is how Director resolves a bare
## `member(N)`; a name that matches no library falls back to the same rather than
## answering nothing, because a wrong-but-present member is easier to see in a
## trace than a silent zero.
func _resolve_member_ref(which: Variant, cast: String) -> Array:
	if _table == null:
		return [1, 0]
	var lib := 1
	var wanted := cast.strip_edges().to_lower()
	if wanted != "":
		for number in _table.cast_libs:
			if str(_table.cast_libs[number].get("name", "")).to_lower() == wanted:
				lib = int(number)
				break
	if typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT:
		return [lib, int(which)]
	# A name, which Director looks up across every cast when the reference does
	# not name one. Searching the named library first keeps an explicit
	# `of castLib "master"` authoritative.
	var named = _table.cast_for(lib)
	if named != null:
		var here: int = named.number_of(str(which))
		if here > 0:
			return [lib, here]
	if wanted != "":
		return [lib, 0]
	var libs: Array = _table.cast_libs.keys()
	libs.sort()
	for other in libs:
		var cast_file = _table.cast_for(int(other))
		if cast_file == null:
			continue
		var found: int = cast_file.number_of(str(which))
		if found > 0:
			return [int(other), found]
	return [lib, 0]


func _resolve_member(which: Variant, cast: String) -> int:
	return int(_resolve_member_ref(which, cast)[1])


