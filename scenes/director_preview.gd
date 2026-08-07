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
const PaletteState := preload("res://director/director_palette_state.gd")
const Bitmap := preload("res://director/director_bitmap.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
const PreviewHost := preload("res://scenes/preview_lingo_host.gd")
const FilmLoop := preload("res://director/director_film_loop.gd")

const Ink := preload("res://director/director_ink.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const SpriteState := preload("res://scenes/preview/sprite_state.gd")
const TextArt := preload("res://scenes/preview/text_art.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const Cursor := preload("res://scenes/preview/cursor.gd")
const Shape := preload("res://director/director_shape.gd")
const Text := preload("res://director/director_text.gd")
const Keys := preload("res://director/director_keys.gd")
const Preloader := preload("res://director/director_preloader.gd")
const FrameClock := preload("res://director/director_frame_clock.gd")
const Transition := preload("res://director/director_transition.gd")
const Config := preload("res://director/director_config.gd")
const ScoreSound := preload("res://director/score_sound.gd")
const SoundMember := preload("res://director/director_sound.gd")

const STAGE := Vector2i(640, 480)

## Director's `the windowType` values, from the reference. Plain `const` ints
## rather than an enum: an enum does not survive `preload`, and every consumer of
## this file reaches it that way.
##
## Only 2 occurs in this corpus (21 times). The rest are here because a window
## type decides whether the window has a title bar and a border, and an engine
## that knows one value draws every other title's windows wrong.
const WINDOW_NO_BORDER := -1
const WINDOW_DOCUMENT := 0
const WINDOW_ALERT := 1
const WINDOW_PLAIN := 2
const WINDOW_PLAIN_SHADOW := 3
const WINDOW_DOCUMENT_NO_SIZE := 4
const WINDOW_DOCUMENT_ZOOM := 8
const WINDOW_ROUNDED := 12
const WINDOW_ROUNDED_NO_TITLE := 16
const WINDOW_PALETTE := 49
## The types that carry a title bar. `titleVisible` can still take it away.
const WINDOW_TITLED := [
	WINDOW_DOCUMENT, WINDOW_DOCUMENT_NO_SIZE, WINDOW_DOCUMENT_ZOOM,
	WINDOW_ROUNDED, WINDOW_PALETTE,
]
## The types that draw a frame around the movie at all.
const WINDOW_BORDERED := [
	WINDOW_DOCUMENT, WINDOW_ALERT, WINDOW_PLAIN, WINDOW_PLAIN_SHADOW,
	WINDOW_DOCUMENT_NO_SIZE, WINDOW_DOCUMENT_ZOOM, WINDOW_ROUNDED,
	WINDOW_ROUNDED_NO_TITLE, WINDOW_PALETTE,
]
## Height of the title bar this draws. Schematic rather than period-accurate: the
## point is that a titled window is visibly titled and that the movie inside it
## is offset by the bar, not that it looks like System 7.
const WINDOW_TITLE_BAR := 18
## Floating skip control, in stage coordinates so it scales and letterboxes with
## everything else rather than drifting when the window is resized.
const SKIP_RECT := Rect2(STAGE.x - 62, 8, 54, 22)

var _movie = null
var _score = null
var _labels = null
var _table = null
## The table every indexed bitmap is decoded against. Held beside the state
## rather than read through it on each decode because it is touched per pixel.
var _palette: PackedByteArray
## Which palette is current, and what it is doing to itself. See
## `director/director_palette_state.gd`; this node owns only the wiring —
## resolving each frame's channel, holding the playhead for a blocking cycle,
## and throwing away artwork baked against a table that has changed.
var _palette_state = PaletteState.new()
## The score's own two sound channels and their restart-on-change rule. See
## `director/score_sound.gd`; this node owns only the wiring — resolving a member
## to a stream and handing it to the mixer.
var _score_sound = ScoreSound.new()
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
# The corpus writes exactly two window properties — `the windowType`, 21 times,
# always 2, and `the centerStage`, 21 times, always 1 — and reads none. The rest
# of §14's surface is built anyway and is marked **unverified** where it is: this
# is a Director engine, not a Piposh player, and a property that is absent
# because one title did not use it is a hole the next title falls into. What is
# unverified here: `the rect`/`drawRect`/`title`/`titleVisible`/`modal`/
# `fileName` of a window, the window chrome for every `windowType` other than 2,
# `the windowList`, `the frontWindow` and `the activeWindow`. They are written
# from the reference and nothing in this corpus proves them right.
#
# Genuinely not built, and why: `the picture of window` needs the window's
# composited pixels read back, which this immediate-mode renderer never holds
# (§6.3, gap 16.25 — no dirty rects, nothing retains a surface). §14's movie
# *stack* — push the current movie, return to it, and wrap to frame 1 at the end
# of a movie rather than stopping — is a separate mechanism from windows and is
# not part of this change.

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
## A window must not answer the click that opened it.
##
## `open` is called from inside a `mouseUp` handler, and the window it opens
## may land straight onto a wait-for-click frame -- JOKE does exactly that at
## frame 4, whose script is `forget(window("joke.dxr"))`. Without this the
## mouse-up that opened the joke also satisfies its wait and closes it again,
## so the popup appears for a single frame or never visibly at all, depending
## on where in the tick the click landed. That intermittency is what made it
## look like a rendering fault.
##
## The rule is simply that a movie answers a click whose *press* it saw. A
## window that appeared mid-click has not seen one, so the release passes it
## by and the next real click works normally.
var _saw_press := false
var _window_shown := false
## The movie's own `DRCF` stage rect. Every movie in this corpus declares
## 640x480, so a centred window covers the stage exactly; the rect is read rather
## than assumed because it is what decides both, and a title whose window is
## smaller would otherwise be drawn full-stage.
var _config = null
## `the centerStage` and `the windowType` as a script set them, per §14.
## `centerStage` decides placement at `open`; `windowType` decides the chrome.
var _center_stage := false
## Director's window types. 2 is the plain box with no title bar, which is the
## only value this corpus writes; the rest come from the reference and decide
## whether `_draw_window_chrome` puts a title bar and a border on.
var _window_type := WINDOW_DOCUMENT
## `the rect of window` — where the window sits and how big it is, once a script
## has said. Null means "wherever `centerStage` and the movie's own rect put it",
## which is every window in this corpus. Unverified.
var _window_rect = null
## `the drawRect of window` — the rectangle the movie's stage is *drawn* into, as
## opposed to the window frame. Director scales the movie when the two differ,
## which is the only way a MIAW shows a movie at other than its authored size.
## Null means natural size. Unverified.
var _draw_rect = null
## `the title of window` and `the titleVisible of window`. Director defaults the
## title to the window's name, which is the file stem. Unverified.
var _window_title := ""
var _title_visible := true
## `the modal of window`. A modal window blocks input to every other window in
## the session while it is open — the playhead of the movie underneath keeps
## running, which is why this gates `route_click` and the key dispatch and not
## `_process`. Unverified: nothing in this corpus sets it.
var _modal := false
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
	# Only the stage fits itself to the OS window. A Movie-In-A-Window is a child
	# of the stage and already inherits its scale, so running this on one scales
	# it a second time -- at the default window that is 1.55 twice over, and the
	# joke popup arrives at nearly two and a half times its size. Its geometry
	# comes from `_apply_window_geometry` instead, which places it in *stage*
	# coordinates where it belongs.
	if _window_key == "":
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
	# Palette ids are per movie, so the state resets with the movie rather than
	# carrying the last one's cache and cycling offsets into this one.
	_palette_state.table_for = _palette_table_for
	_palette_state.reset(Palette.SYSTEM_MAC)
	_palette = _palette_state.table
	# The movie's own stage rect. Only a window uses it, but it is read for every
	# movie because a window's placement is the *difference* between its rect and
	# the stage movie's, and the stage is whichever movie happens to be playing.
	var config = Config.new()
	_config = config if config.read(_movie) else null
	# The rate this movie starts at, before its score writes a tempo. Without it
	# every movie that never writes one runs at the engine's guess.
	var stated := int(_config.default_tempo) if _config != null else 0
	_clock.movie_default_fps = float(stated) if stated > 0 else FrameClock.DEFAULT_FPS
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


## Everything sound-driven that happens once a tick: cue points passed, and the
## tempo channel's wait-for-sound.
##
## One pass, because both consume the same thing. `take_cues_passed` is
## destructive — it reports each cue once and then forgets it — so a wait poll
## and an event dispatch that each called it would race, and whichever ran first
## would eat the cue the other was looking for. That is a bug with no symptom
## except a wait that never releases.
func _pump_sound(_delta: float) -> void:
	if _audio == null:
		return
	var wait: Dictionary = _clock.waiting_sound()
	var wait_channel := int(wait["channel"])
	var wait_cue := int(wait["cue"])

	for channel_value in _audio.call("cue_channels"):
		var channel := int(channel_value)
		for cue_value in _audio.call("take_cues_passed", channel):
			var cue: Dictionary = cue_value
			_dispatch_cue_passed(channel, cue)
			if channel != wait_channel:
				continue
			# −1 is "the next cue, whichever it is"; a positive index is that cue
			# or any after it, since a tick can cross more than one. −2 is "the
			# end", which is not a cue at all and is handled below.
			if wait_cue == Score.CUE_NEXT or (wait_cue > 0 and int(cue["index"]) >= wait_cue):
				_clock.sound_arrived()
				wait_channel = 0

	if wait_channel <= 0:
		return
	# "The end" is the *sound* ending, not the last cue passing: a sound with no
	# cue points at all still ends, and reading it as "all cues passed" would
	# release the wait instantly on every unmarked sound -- which is every sound in
	# this corpus. A cue wait releases on the sound ending too, or a frame waiting
	# on a cue that never comes would hold for ever.
	if not bool(_audio.call("sound_busy", wait_channel)):
		_clock.sound_arrived()


## `cuePassed me, <channel>, <cueNumber>, <cueName>`.
##
## A second, independent source of events alongside the frame's (§12). A sound
## carries markers, the audio playhead crosses one, and the movie is told -- which
## is how a Director title syncs animation to speech without counting frames.
## Polled once a tick because there is no callback at a sample position, which is
## the resolution every other Director event gets anyway.
##
## Sent to the frame script and then to the movie, which is where a `cuePassed`
## handler is authored: the event belongs to the *channel*, and a channel has no
## sprite to route it to.
##
## **Unexercised by this corpus.** No script in it names `cuePassed`, and none of
## its 3,141 sounds carries a marker inside its own audio (`tools/aiff_check.gd`),
## so this never fires on this game. The argument order is the reference's.
func _dispatch_cue_passed(channel: int, cue: Dictionary) -> void:
	if _interpreter == null:
		return
	_tally(_sent, "cuePassed")
	_interpreter.call_handler(
		"cuePassed", [channel, int(cue["index"]), str(cue["name"])], _frame_script(_index))


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
	#
	# The chrome sits *outside* the movie's rect — the title bar is above local
	# y=0 and the border to the left of x=0 — so the clip has to be widened by it
	# or a titled window would draw its movie and none of its frame. Zero for
	# `windowType` 2, which is what this corpus uses.
	if _window_key == "":
		_clip_rect = Rect2(Vector2.ZERO, Vector2(STAGE))
	else:
		var inset := chrome_inset()
		var edge := float(_border_width())
		_clip_rect = Rect2(-inset, window_size() + inset + Vector2(edge, edge))
	var item := get_canvas_item()
	RenderingServer.canvas_item_set_clip(item, true)
	RenderingServer.canvas_item_set_custom_rect(item, true, _clip_rect)


## Everything trails sprites have painted, kept across repaints. `DIRECTOR_ENGINE.md`
## §13, and the one part of the renderer that is not rebuilt from the frame.
##
## **What a trails sprite is.** Its old position is never erased: the stage keeps
## the pixels, so a sprite dragged across the stage leaves a stroke behind it.
## §13 puts it as "no erase of the old bbox, and the repaint starts *at* the
## trails channel rather than clearing to the stage colour", which is a property
## of how the stage is painted rather than a flag a sprite can be drawn with.
##
## **How Director gets it and how this does.** Director keeps a persistent
## composite surface and repaints only dirty rectangles; a trails sprite simply
## does not dirty the rectangle it vacated, so those pixels are never repainted.
## This renderer has no dirty rects (§16.25) and repaints everything every frame,
## so the equivalent is §13's own suggestion: an accumulation buffer that is not
## cleared, painted directly after the stage colour and under the current frame.
##
## **The divergence that leaves, stated exactly.** Under dirty rects, a *later*
## sprite moving over an old trail mark dirties that rectangle, so the repaint
## fills it with the stage colour and the mark is erased. Here the mark is in the
## layer underneath and survives, showing through wherever that sprite is keyed
## transparent. Opaque artwork hides it either way, so the two agree except under
## a keyed ink drawn over an old trail. Closing it means implementing §16.25, not
## patching this.
##
## Costs nothing until something sets the flag: the layer is not allocated until
## the first trails sprite is drawn, and this corpus never draws one — 0 of
## 816,318 sprite records (`tools/ink_survey.gd`). It is reachable from Lingo
## through `the trails of sprite`, which is how `tools/trails.gd` exercises it and
## how any movie would.
var _trail_image: Image = null
var _trail_layer: ImageTexture = null
## channel -> {rect, member, trails} as of the last paint. What makes a sprite
## "dirty" is the difference between this and the paint in hand, and dirtiness is
## the whole of the rule in `_settle_trails`.
var _trail_placed: Dictionary = {}
## Whether the layer's pixels changed this paint, so the texture is uploaded once
## per paint rather than once per stamp.
var _trail_dirty := false


## Does anything in this frame ask for trails, from the score or from a script?
## Cheap enough to ask once a paint; the alternative is paying for the tracking
## in every movie that never uses the feature.
func _wants_trails(frame: Dictionary) -> bool:
	for over_value in _overrides.values():
		var over: Dictionary = over_value
		if over.has("trails") and LingoValue.to_int(over["trails"]) != 0:
			return true
	for sprite_value in frame.get("sprites", []):
		var sprite: Dictionary = sprite_value
		if bool(sprite.get("trails", false)):
			return true
	return false


## Update the trail layer for this paint, and put it on the stage.
##
## **This is where §13 stops being a flag and becomes the dirty-rect rule**, and
## the first attempt got it exactly backwards. Painting the layer under the
## frame's sprites is the obvious reading of "the repaint starts at the trails
## channel", and it makes trails invisible in any movie with a backdrop: the
## backdrop is a sprite, it is drawn after the layer, and it covers everything a
## trails sprite ever left. `tools/trails.gd` caught that by reading the
## framebuffer — every headless check passed while nothing was visible on screen.
##
## What Director actually does is repaint **dirty rectangles only**: fill with
## the stage colour, composite every intersecting channel in order. A region no
## changed sprite touches is not repainted at all, so a mark left there stays on
## screen *over* the backdrop that was under it. So:
##
##   a channel that moved or swapped member dirties both the rectangle it left
##   and the one it arrived at, and the layer is cleared there — which is how a
##   non-trails sprite wipes a trail it passes over, and how a sprite whose
##   trails were switched off stops leaving marks behind it;
##
##   a **trails** channel does not dirty the rectangle it left (that is the whole
##   feature), so only its new rectangle is cleared before it stamps itself;
##
##   a channel that did not change dirties nothing, which is why a static
##   backdrop does not wipe the stage every frame.
##
## The layer is then drawn *over* the frame. That is right for everything a
## changed sprite has not repainted, and wrong for a sprite that is genuinely in
## front of an old mark and did not move — it should occlude the mark and does
## not. Closing that means real dirty rects and a persistent composite surface
## (§16.25); this reproduces the visible behaviour of trails without them.
func _settle_trails(placed_now: Dictionary, to_stamp: Array[Dictionary]) -> void:
	if _trail_image != null:
		for channel in _trail_placed:
			var was: Dictionary = _trail_placed[channel]
			var now: Dictionary = placed_now.get(channel, {})
			var gone := now.is_empty()
			var moved: bool = gone \
				or Rect2(now["rect"]) != Rect2(was["rect"]) \
				or int(now["member"]) != int(was["member"])
			if not moved:
				continue
			# The one exception in the whole mechanism: a trails channel leaves
			# its old rectangle alone.
			#
			# Decided by the flag the channel carries **now**, not the one it
			# carried when it painted there. Director asks "do I erase where I
			# was?" as part of the update it is doing, so a sprite whose trails
			# were switched off goes back to erasing behind itself immediately,
			# including the mark it left on the move before. A channel that has
			# left the frame has no current flag to ask, and its last one stands.
			if not bool(now.get("trails", was.get("trails", false))):
				_trail_erase(Rect2(was["rect"]))
			if not gone:
				_trail_erase(Rect2(now["rect"]))
		# A channel that appeared this paint repaints where it landed.
		for channel in placed_now:
			if not _trail_placed.has(channel):
				_trail_erase(Rect2(placed_now[channel]["rect"]))
	for entry in to_stamp:
		_trail_stamp(entry["image"], entry["at"])
	_trail_placed = placed_now
	if _trail_layer == null:
		return
	# One upload per paint rather than one per stamp: a movie with several trails
	# sprites would otherwise push the whole 640x480 layer to the GPU once each.
	if _trail_dirty:
		_trail_dirty = false
		_trail_layer.update(_trail_image)
	draw_texture(_trail_layer, Vector2.ZERO)


## Clear a rectangle of the trail layer: the region was repainted, so whatever a
## trails sprite had left there is gone.
func _trail_erase(rect: Rect2) -> void:
	if _trail_image == null:
		return
	var area := Rect2(Vector2.ZERO, Vector2(STAGE)).intersection(rect)
	if area.size.x < 1.0 or area.size.y < 1.0:
		return
	_trail_image.fill_rect(Rect2i(area), Color(0, 0, 0, 0))
	_trail_dirty = true


## Add what a sprite just painted to the trail layer.
##
## `blend_rect` rather than `blit_rect`: the artwork arrives already keyed by its
## ink, so it carries transparency, and a blit would stamp the transparent parts
## as holes punched through everything the sprite passed over. It also clips to
## the layer, which is the stage, so a trails sprite hanging off the edge
## accumulates only the part that was on screen — the same rule `_clip_to_stage`
## applies to the live paint.
func _trail_stamp(image: Image, at: Vector2) -> void:
	if image == null:
		return
	if _trail_image == null:
		_trail_image = Image.create_empty(STAGE.x, STAGE.y, false, Image.FORMAT_RGBA8)
		_trail_image.fill(Color(0, 0, 0, 0))
		_trail_layer = ImageTexture.create_from_image(_trail_image)
	var source := image
	# `blend_rect` needs both sides in the same format, and a member decoded from
	# an indexed bitmap is not guaranteed to arrive as RGBA8.
	if source.get_format() != Image.FORMAT_RGBA8:
		source = source.duplicate()
		source.convert(Image.FORMAT_RGBA8)
	_trail_image.blend_rect(
		source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(at.floor())
	)
	_trail_dirty = true


## Throw the trail layer away. A movie change repaints the stage, so the marks a
## previous movie left do not belong to the new one; within a movie the layer
## outlives frame jumps, which is the whole point of it.
func _clear_trails() -> void:
	_trail_image = null
	_trail_layer = null
	_trail_placed.clear()
	_trail_dirty = false


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
	# Cue points and the tempo channel's wait-for-sound, before the clock: both
	# can release a hold this tick, and one evaluated after the clock has already
	# decided the tick holds costs the frame it was waiting for. The fade ramp
	# they interact with is stepped by `AudioDirector` itself, one process
	# priority earlier — §12's "from the top of the update".
	_pump_sound(delta)
	# Before the clock, because a cycle or a fade is what the clock is *holding*
	# the playhead for: stepping it after would advance the frame that the effect
	# is the reason for, and the last step of a fade would land on the next one.
	if _palette_state.effect_running() and _palette_state.step(delta * 1000.0):
		_palette_applied()
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
	# Before the transition, deliberately: §12 starts a frame's sounds *in
	# parallel* with its transition rather than after it, so a cut scene's line
	# of speech begins as the wipe does and not a second later.
	_begin_score_sound(frame)
	_begin_palette(frame)
	_begin_transition(frame)


## Play whatever this frame's two score sound channels ask for.
##
## §12, and `director/score_sound.gd` holds the rule — a channel restarts only
## when the member it names *changes*, and a channel a script has puppeted is not
## the score's to touch. This node owns only the wiring: turning a cast member
## into a stream and handing it to the mixer.
##
## **Unexercised by this corpus, and it is worth knowing why rather than only
## that.** The game this port was built on has no `sound` cast member in any of
## its 86 containers and writes neither sound channel in any of its 61,371
## frames, so `changes()` returns nothing on every frame of every room here
## (`tools/sound_survey.gd`). Every sound it plays comes from Lingo instead. The
## path below is therefore reference-shaped rather than observed, and the harness
## that proves the rule is `tools/score_sound_check.gd`, which drives the state
## machine directly.
func _begin_score_sound(frame: Dictionary) -> void:
	var changes: Dictionary = _score_sound.changes(frame.get("sound_channels", []))
	for channel in changes["stop"]:
		lingo_stop_sound(int(channel))
	for entry_value in changes["start"]:
		var entry: Dictionary = entry_value
		play_sound_member(int(entry["channel"]), int(entry["cast_lib"]), int(entry["cast_id"]))


## A sound cast member onto a channel: what the score's channels and
## `puppetSound` both need, and the one path that turns a member into audio.
##
## Returns false when the member does not resolve or does not decode, which is a
## fact about the movie rather than an error to raise — the same contract the
## bitmap path has. It is traced rather than silent, because a sound that does
## not play and says nothing is indistinguishable from a score that asked for
## none, and that ambiguity is what §12 costs most sessions.
func play_sound_member(channel: int, cast_lib: int, cast_id: int) -> bool:
	if _audio == null or _table == null:
		return false
	var member: Dictionary = _table.get_member(cast_lib, cast_id)
	if member.is_empty() or int(member.get("data_chunk_id", -1)) < 0:
		_trace("f%d sound ch%d member %d:%d -> not found" % [_index, channel, cast_lib, cast_id])
		return false
	var file = _table.file_for(cast_lib)
	if file == null:
		return false
	var payload: PackedByteArray = file.read_chunk(int(member["data_chunk_id"]))
	var header := PackedByteArray()
	var header_id := int(member.get("sound_header_chunk_id", -1))
	# `sndH` is the header of the `sndH`/`sndS` pair and never the payload: when
	# the member's own data chunk *is* the header, there are no separate samples
	# to point it at and passing it as both would decode the header twice.
	if header_id >= 0 and header_id != int(member["data_chunk_id"]):
		header = file.read_chunk(header_id)
	var error: Array = []
	var stream := SoundMember.decode(payload, header, error)
	if stream == null:
		_trace("f%d sound ch%d member %d:%d -> %s" % [
			_index, channel, cast_lib, cast_id, "; ".join(error),
		])
		return false
	_audio.call("play_stream", channel, "%d:%d" % [cast_lib, cast_id], stream,
		SoundMember.cue_points(payload))
	_trace("f%d sound ch%d member %d:%d" % [_index, channel, cast_lib, cast_id])
	return true


## Resolve this frame's palette channel and arm whatever effect it asks for.
##
## §11, and `director/director_palette_state.gd` holds the rules. Two things
## happen here that cannot live in the state machine because they are the
## renderer's:
##
## **A palette change invalidates every decoded bitmap.** An indexed member is
## decoded *through* the table, so the texture cache is artwork baked against a
## palette; keeping it across a switch draws the new frame in the old colours,
## which reads as an ink fault rather than a palette one. That makes a palette
## switch expensive here in a way it is not in Director — Director swaps a CLUT
## and the same pixels mean new colours — and it is the price of an RGB
## renderer. It costs nothing until something actually switches.
##
## **A cycle without *over time* holds the playhead.** §11 runs that form to
## completion inside the frame transition, as a loop that sleeps; the clock
## already expresses "this frame takes this long" for transitions and tempo
## delays, so the cycle uses the same mechanism and the process stays live.
func _begin_palette(frame: Dictionary) -> void:
	if _palette_state.enter_frame(frame.get("palette", {})):
		_palette_applied()
	var hold := _palette_state.hold_ms()
	if hold > 0.0:
		_clock.hold(hold, FrameClock.REASON_PALETTE)
		_trace("f%d palette effect for %.0f ms" % [_index, hold])


## The current table changed: publish it and throw away what was baked against
## the old one.
func _palette_applied() -> void:
	_palette = _palette_state.table
	_textures.clear()
	_hit_images.clear()
	queue_redraw()


## An id to a colour table, for the state machine's resolution order. Empty means
## "not loaded", which is what makes §11's re-check at every step meaningful.
##
## A negative id is a built-in and `director_palette.gd` answers for it; a
## positive one is a palette cast member, whose `CLUT` chunk is its payload the
## same way a bitmap's `BITD` is. Searched across every library this movie can
## address rather than assuming library 1: a palette in a shared cast is exactly
## the case that would resolve to the wrong member by number alone.
##
## Unexercised by this corpus, which ships no palette member and no `CLUT`
## chunk at all (`tools/palette_survey.gd`).
func _palette_table_for(id: int) -> PackedByteArray:
	if id < 0:
		return Palette.builtin(id) if Palette.can_build(id) else PackedByteArray()
	if id == 0 or _table == null:
		return PackedByteArray()
	for lib in _palette_libs():
		var m: Dictionary = _table.get_member(lib, id)
		if m.is_empty() or int(m.get("type", 0)) != Palette.MEMBER_TYPE:
			continue
		var chunk_id := int(m.get("data_chunk_id", -1))
		if chunk_id < 0:
			continue
		var f = _table.file_for(lib)
		if f == null:
			continue
		return Palette.from_clut(f.read_chunk(chunk_id))
	return PackedByteArray()


## Every cast library this movie can reach, its own first.
func _palette_libs() -> Array:
	var libs: Array = [1]
	for lib in _table.cast_libs.keys():
		if int(lib) != 1:
			libs.append(int(lib))
	return libs


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
		if (event as InputEventMouseButton).pressed:
			# Recorded on every movie on the stage, windows included, so a window
			# that opens during this click still has not seen its press.
			_saw_press = true
			for key in _windows:
				var w: Node = _windows[key]
				if w != null:
					w._saw_press = true
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
			over._hover_channel = over._channel_at(over.stage_to_local(stage_mouse()))
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
	var focus := modal_window()
	if focus == null:
		focus = window_at(stage_mouse())
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
	# The stage colour, which §14 says is what every non-trails repaint fills
	# with. Over the movie's own rect only: the chrome around a window is painted
	# by `_draw_window_chrome` and is not part of the movie.
	draw_rect(Rect2(Vector2.ZERO, window_size() if _window_key != "" else Vector2(STAGE)),
		Color.BLACK, true)
	if _window_key != "":
		_draw_window_chrome()
	if _status != "":
		draw_string(ThemeDB.fallback_font, Vector2(16, 32), _status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.RED)
		return
	if _score == null:
		return

	# Rebuilt from scratch each paint rather than accumulated: it is a record of
	# what is on the stage now, and a field that left the frame must stop being in
	# it or a harness would assert against a channel that is no longer drawn.
	_text_drawn.clear()
	# Where each channel is this paint, and what it holds, so the trail layer can
	# be told which regions the frame repainted. See `_settle_trails`.
	#
	# Only collected when something is actually using trails: it is a dictionary
	# per drawn sprite per paint, on a path that runs for every sprite of every
	# frame, and 0 of this corpus's 816,318 sprite records ask for it. Once a
	# layer exists the tracking stays on, because the layer's contents then depend
	# on knowing where everything was.
	var placed_now: Dictionary = {}
	var to_stamp: Array[Dictionary] = []
	var frame: Dictionary = _score.frame(_index)
	var track_trails := _trail_image != null or _wants_trails(frame)
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
		_draw_sprite_texture(texture, top_left, sprite,
			Color(1, 1, 1, Ink.blend_alpha(sprite)))
		# A trails sprite is not erased between frames (§13), so what it painted
		# joins the layer that survives the next clear. Collected rather than
		# stamped here: the layer is first cleared where this frame repainted, and
		# stamping before that would wipe what was just added.
		var trails := bool(sprite.get("trails", false))
		if track_trails:
			placed_now[int(sprite["channel"])] = {
				"rect": placed, "member": int(sprite["cast_id"]), "trails": trails,
			}
		if trails:
			to_stamp.append({
				"image": _hit_images.get(_texture_key(sprite, _drawn_size(sprite, m))),
				"at": top_left,
			})
	_settle_trails(placed_now, to_stamp)

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


## The frame around a window's movie: a border, a title bar and a drop shadow,
## as `the windowType` and `the titleVisible` ask for them (§14).
##
## Schematic rather than period-accurate, and that is the honest trade: the point
## is that a titled window is visibly titled and that its movie is inset by the
## bar, not that it looks like System 7. **Unverified** — every window in this
## corpus is `windowType` 2, which has a one-pixel border and nothing else, so
## nothing here proves the titled types right.
##
## Drawn in the window's own local space, where the movie's top-left is the
## origin and the chrome is at negative coordinates above and to the left.
func _draw_window_chrome() -> void:
	var size := window_size()
	var edge := float(_border_width())
	if _window_type == WINDOW_PLAIN_SHADOW:
		# The shadow is under the window and offset, so it is drawn first and
		# outside the frame on the far two sides.
		draw_rect(Rect2(Vector2(4, 4), size + Vector2(edge, edge)), Color(0, 0, 0, 0.4), true)
	if _has_title_bar():
		var bar := Rect2(Vector2(-edge, -edge - WINDOW_TITLE_BAR),
			Vector2(size.x + edge * 2.0, WINDOW_TITLE_BAR))
		draw_rect(bar, Color(0.82, 0.82, 0.82), true)
		draw_rect(bar, Color(0.25, 0.25, 0.25), false, 1.0)
		var title := window_title()
		if title != "":
			draw_string(
				ThemeDB.fallback_font, bar.position + Vector2(6, WINDOW_TITLE_BAR - 5),
				title, HORIZONTAL_ALIGNMENT_LEFT, bar.size.x - 12, 12, Color(0.1, 0.1, 0.1)
			)
	if edge > 0.0:
		var inset := chrome_inset()
		draw_rect(Rect2(-inset, size + inset + Vector2(edge, edge)),
			Color(0.25, 0.25, 0.25), false, edge)


## Artwork, delegated to `preview/sprite_art.gd`. The caches stay on the node --
## `tools/` reads `_textures` and `_hit_images` by name -- and are passed in.
func _texture_for(sprite: Dictionary) -> Texture2D:
	return SpriteArt.texture_for(sprite, _table, _palette, _textures, _hit_images)


func _draw_sprite_texture(texture: Texture2D, at: Vector2, sprite: Dictionary,
		modulate: Color) -> void:
	SpriteArt.draw(self, texture, at, sprite, modulate)


## Does this sprite have a visible pixel at a stage point? The cache lookup is
## here because it is the node's; the sampling rule is the module's.
func _opaque_at(sprite: Dictionary, at: Vector2) -> bool:
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	var key := _texture_key(sprite, _drawn_size(sprite, m))
	if not _hit_images.has(key):
		# Populates the cache as a side effect.
		if _texture_for(sprite) == null:
			return false
	return SpriteArt.sample_opaque(
		_hit_images.get(key), _sprite_rect(sprite), sprite, at)


## Draw a field member's text, and say whether this sprite was one.
##
## True even when there was nothing to draw: the sprite *is* a field, and falling
## through to the bitmap path would only ask the cast for artwork a field does
## not have.
func _draw_text(sprite: Dictionary) -> bool:
	var m: Dictionary = _table.get_member(int(sprite["cast_lib"]), int(sprite["cast_id"]))
	if m.is_empty() or int(m.get("type", 0)) != Ink.TYPE_FIELD:
		return false
	_text_drawn[int(sprite["channel"])] = TextArt.paint(
		self, sprite, m, _stage_rect(sprite), _field_text_of(m))
	return true


# ------------------------------------------------------- what the host calls


## Film loops, delegated to `preview/film_loop_view.gd`. The loop cache and the
## per-channel start ticks stay on the node; the module reaches back through
## `host` for artwork and painting, because the texture cache and the canvas are
## the node's and a loop's children must go through exactly the same path as any
## other sprite.
func _draw_film_loop(sprite: Dictionary) -> bool:
	return FilmLoopView.draw(self, sprite, _table, _loops, _ccl, _ticks, _loop_start)


func _child_lib(child: Dictionary, owner_lib: int) -> int:
	return FilmLoopView.child_lib(child, owner_lib, _table)


func _open_loop(lib: int, member: Dictionary):
	return FilmLoopView.open_loop(lib, member, _table, _ccl)


func _child_sprite(child: Dictionary, lib: int, member: Dictionary) -> Dictionary:
	return FilmLoopView.child_sprite(child, lib, member)


## A child names its cast by name, not by this movie's library number -- and when
## that name resolves to nothing, the loop's own library is the answer.
func _child_texture(child: Dictionary, owner_lib: int = 1) -> Texture2D:
	var lib := _child_lib(child, owner_lib)
	return _texture_for(
		_child_sprite(child, lib, _table.get_member(lib, int(child["cast_id"])))
	)


## Counted for the loop report. Named apart from `_tally` because the module
## calls it back through `host` and a bare `_tally` would read as the node's own.
func _tally_loop(key: String) -> void:
	_tally(_loop_stats, key)


## The mouse, delegated to `preview/interaction.gd`. Everything there takes the
## node as `host`, because the hit test needs puppet state, the artwork cache and
## the script table -- all of which are the node's.
func _channel_at(at: Vector2) -> int:
	return Interaction.channel_at(
		self, at, _score.frame(_index).get("sprites", []), _hit_pixels, _table)


func _responds_to_mouse(sprite: Dictionary) -> bool:
	return Interaction.responds_to_mouse(self, sprite, _table)


func _declares_mouse_handler(script: Dictionary) -> bool:
	return Interaction.declares_mouse_handler(script, _interpreter)


func _draw_hotspots(frame: Dictionary) -> void:
	Interaction.draw_hotspots(self, frame, _hover_channel, _hit_pixels, _table)


## A mouse-down over a moveable sprite starts a drag: Director records the
## channel and the offset from the click to the sprite's position, then follows
## the cursor until mouse-up or until the sprite stops being moveable.
func _begin_drag(at: Vector2) -> void:
	var started: Array = Interaction.begin_drag(
		self, at, _channel_at(at), _score.frame(_index).get("sprites", []))
	if started.is_empty():
		return
	_drag_channel = int(started[0])
	_drag_offset = started[1]


func _click(at: Vector2) -> void:
	if not _lingo_on or _interpreter == null:
		return
	# A click always produces a message. What is under the cursor decides which
	# script sees it first; it does not decide whether one is sent.
	#
	# Bailing out on a miss or a hole is why the menu went from unreliable to
	# dead: its backdrop covers the stage, so the hit test answered "hole" and
	# nothing was ever dispatched -- while the handler the menu actually uses
	# lives in the frame script and reads `the clickOn`.
	var channel := _channel_at(at)
	_host.click_sprite = channel
	var chosen: Array = Interaction.script_for_click(
		self, channel, _score.frame(_index).get("sprites", []))
	var script: Dictionary = chosen[0]
	# Says what was clicked, which script is about to answer for it, and whether
	# a handler actually exists. "clicked nothing" and "clicked something with no
	# mouseUp" look identical on screen and are entirely different faults.
	var has_up: bool = _interpreter.call("_script_has_handler", script, "mouseup") 		or _interpreter.has_handler("mouseup")
	print("clicked (%d,%d) frame %d  ch%d  %s script %s  mouseUp:%s" % [
		int(at.x), int(at.y), _index, channel, str(chosen[1]),
		str(script.get("script", "none")), "yes" if has_up else "NO HANDLER",
	])
	# Director sends both, and a menu may answer either.
	_dispatch("mouseDown", script)
	_dispatch("mouseUp", script)
	queue_redraw()


## Placement, delegated to `preview/sprite_geometry.gd`.
##
## These stay on the node because `tools/` reaches them by name -- `hotspots`,
## `sprite_flip`, `stage_clip`, `text_and_shapes`, `trails` call `_stage_rect`
## and `cursor_preview` calls `_sprite_rect`. The rule itself lives in the
## module; what is left here is the cast-table lookup, which is the only part
## that needs the node at all.
func _stage_rect(sprite: Dictionary) -> Rect2:
	return Geometry.stage_rect(sprite, _table.get_member(
		int(sprite["cast_lib"]), int(sprite["cast_id"])))


func _drawn_size(sprite: Dictionary, member: Dictionary) -> Vector2:
	return Geometry.drawn_size(sprite, member)


func _scaled_reg(member: Dictionary, drawn: Vector2) -> Vector2:
	return Geometry.scaled_reg(member, drawn)


func _texture_key(sprite: Dictionary, drawn: Vector2) -> String:
	return Geometry.texture_key(sprite, drawn)


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
## `puppetPalette <id>`: pin the palette against the score, or 0 to stop.
##
## §11 gives a puppet palette priority over everything else in the resolution
## order, so this is the one place a script can override what the score's palette
## channel says. Zero is "hand it back", not "system Mac" — a movie that meant
## system Mac would say `puppetPalette -1`.
func lingo_puppet_palette(value: Variant) -> void:
	if _palette_state.set_puppet(LingoValue.to_int(value)):
		_palette_applied()


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
	# The rate this movie starts at, before its score writes a tempo. Without it
	# every movie that never writes one runs at the engine's guess.
	var stated := int(_config.default_tempo) if _config != null else 0
	_clock.movie_default_fps = float(stated) if stated > 0 else FrameClock.DEFAULT_FPS
	_ccl = PackedStringArray()
	var ccl_ids: Array = _movie.ids_of("ccl ")
	if not ccl_ids.is_empty():
		_ccl = FilmLoop.read_cast_list(_movie.read_chunk(ccl_ids[0]))

	_textures.clear()
	_hit_images.clear()
	_clear_trails()
	# Palette ids, the score cache and the cycling offsets are all per movie, and
	# the new movie's own default is what it opens on.
	_palette_state.table_for = _palette_table_for
	_palette_state.reset(Palette.SYSTEM_MAC)
	_palette = _palette_state.table
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
	# Restart-on-change compares this frame's sound channels against the frame
	# before. Carried across a movie change, the new movie's first frame would be
	# compared against the last frame of the old one — which in the case that
	# matters, both naming member 3 of their own casts, reads as "no change" and
	# opens the room silent.
	_score_sound.reset()

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


## §14's window vocabulary, write side. Everything but `windowType` and
## `centerStage` is unverified — see the block comment at the top of this file.
func set_own_window_prop(prop: String, value: Variant) -> void:
	match prop:
		"windowtype":
			_window_type = LingoValue.to_int(value)
		"centerstage":
			_center_stage = LingoValue.to_int(value) != 0
		"visible":
			if LingoValue.to_int(value) != 0:
				window_shown()
			else:
				window_hidden()
			return
		"modal":
			_modal = LingoValue.to_int(value) != 0
		"title", "name":
			_window_title = LingoValue.to_str(value)
		"titlevisible":
			_title_visible = LingoValue.to_int(value) != 0
		"rect":
			_window_rect = _rect_of(value)
		"drawrect":
			_draw_rect = _rect_of(value)
		"filename":
			## Director lets one window play a succession of movies. Reached as a
			## `go to movie` inside the window rather than as a reload, so the
			## window keeps its identity, its rect and its place in the stacking
			## order — which is what the property means.
			lingo_go_movie(LingoValue.to_str(value), null)
		_:
			return
	_apply_window_geometry()
	queue_redraw()


## §14's window vocabulary, read side.
func own_window_prop(prop: String) -> Variant:
	match prop:
		"windowtype":
			return _window_type
		"centerstage":
			return 1 if _center_stage else 0
		"visible":
			return 1 if _window_shown else 0
		"modal":
			return 1 if _modal else 0
		"title":
			return window_title()
		"name":
			return _window_key
		"titlevisible":
			return 1 if _title_visible else 0
		"rect":
			var frame := window_frame()
			return [int(frame.position.x), int(frame.position.y),
				int(frame.end.x), int(frame.end.y)]
		"drawrect":
			var drawn := Rect2(window_origin(), window_size() * window_scale())
			return [int(drawn.position.x), int(drawn.position.y),
				int(drawn.end.x), int(drawn.end.y)]
		"sourcerect":
			## The movie's own authored rect, read-only. The one window property
			## that is not a placement decision but a fact about the file.
			# Typed explicitly: `:=` cannot infer through a ternary, and this file
			# does not compile at all without it.
			var source: Rect2i = _config.rect if _config != null else Rect2i(Vector2i.ZERO, STAGE)
			return [int(source.position.x), int(source.position.y),
				int(source.end.x), int(source.end.y)]
		"moviename", "filename":
			return movie_name()
		"picture":
			## Deliberately unimplemented: it is the window's composited pixels,
			## and this renderer never holds a surface to read back (§6.3, gap
			## 16.25). Answering VOID rather than a wrong image.
			return null
	return 0


## `[l, t, r, b]` as Lingo writes a rect, or null. Director also accepts a rect
## value; both arrive here as a four-element list.
static func _rect_of(value: Variant):
	if typeof(value) != TYPE_ARRAY or (value as Array).size() < 4:
		return null
	var v: Array = value
	var left := LingoValue.to_int(v[0])
	var top := LingoValue.to_int(v[1])
	var right := LingoValue.to_int(v[2])
	var bottom := LingoValue.to_int(v[3])
	if right <= left or bottom <= top:
		return null
	return Rect2(left, top, right - left, bottom - top)


## The window's size, before any `drawRect` scaling: `the rect of window` if a
## script set one, otherwise the movie's own `DRCF` rect.
##
## Every movie in this corpus declares 640x480 (`tools/window_survey.gd` over all
## 61 containers that have a config), so in practice a window covers the stage
## exactly — which is why a click anywhere in it goes to it. Read rather than
## assumed, so a title whose window movie is genuinely smaller gets a smaller
## window and the clicks outside it still reach the stage.
func window_size() -> Vector2:
	if _window_rect != null:
		return (_window_rect as Rect2).size
	if _config != null:
		return Vector2(_config.rect.size)
	return Vector2(STAGE)


## Where the window sits, in the stage's coordinates.
##
## `the rect of window` wins if a script set one. Otherwise `the centerStage`
## centres the movie's stage on the screen, and all 21 sites in this corpus set
## it, so that is the path that runs. Failing both, Director puts the window at
## the rect its movie was authored with — a screen coordinate — so it is taken
## relative to the stage movie's own rect, the only other thing here in that
## space.
func window_origin() -> Vector2:
	if _window_rect != null:
		return (_window_rect as Rect2).position
	var mine := window_size()
	if _center_stage:
		return ((Vector2(STAGE) - mine) * 0.5).floor()
	var host = stage_preview()
	if _config != null and host != null and host._config != null:
		return Vector2(_config.rect.position - host._config.rect.position)
	return Vector2.ZERO


## How much the movie is stretched inside its window: `the drawRect of window`
## against the movie's natural size. 1:1 unless a script set one. Unverified.
func window_scale() -> Vector2:
	if _draw_rect == null:
		return Vector2.ONE
	var natural := window_size()
	if natural.x <= 0.0 or natural.y <= 0.0:
		return Vector2.ONE
	return (_draw_rect as Rect2).size / natural


## The window's whole frame on the stage, chrome included. The movie sits inside
## it, below the title bar when there is one.
func window_frame() -> Rect2:
	var at := window_origin()
	var size := window_size() * window_scale()
	var inset := chrome_inset()
	return Rect2(at - inset, size + inset + Vector2(_border_width(), _border_width()))


## How far the movie's own top-left is pushed in by the chrome: the title bar and
## the border. Zero for `windowType` 2, which is what this corpus uses.
func chrome_inset() -> Vector2:
	var edge := float(_border_width())
	var top := edge
	if _has_title_bar():
		top += WINDOW_TITLE_BAR
	return Vector2(edge, top)


func _border_width() -> int:
	return 1 if WINDOW_BORDERED.has(_window_type) else 0


func _has_title_bar() -> bool:
	return _title_visible and WINDOW_TITLED.has(_window_type)


## Director defaults a window's title to its name, which is the file stem.
func window_title() -> String:
	return _window_title if _window_title != "" else _window_key


## Push the node where the geometry says, and stretch it if `drawRect` asks.
func _apply_window_geometry() -> void:
	if _window_key == "":
		return
	position = window_origin()
	scale = window_scale()


## Show the window and let it run. Idempotent: `open` on an open window raises it
## and does not restart the movie.
func window_shown() -> void:
	if _window_shown:
		visible = true
		return
	_window_shown = true
	visible = true
	_apply_window_geometry()
	set_process(true)
	# Paint now, rather than waiting for the first process tick to ask for it.
	# `visible = true` on a canvas item that has never drawn shows nothing --
	# there is no command list to reveal -- and everything that queues a redraw on
	# a window is downstream of `_process`. A window opened by a script that then
	# returns to a host movie doing very little can therefore sit there, correct
	# in every observable way (visible, processing, its score stepping, its
	# `startMovie` run) and blank on screen. That is exactly how the joke window
	# presented: `open` reached, `tell` routed into it, 96 frames loaded, nothing
	# drawn. Headless cannot see it, because headless never paints at all.
	queue_redraw()
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


## `the windowList` — the open windows, back to front, as window keys.
##
## Director's list holds window references and a script may add to or remove from
## it; here it is read-only, because a window in this port exists only as the
## movie behind it and there is nothing to put in the list that `window(...)` has
## not already created. Unverified: no site in this corpus reads it.
func window_keys() -> Array:
	var owner := stage_preview()
	var out: Array = []
	for key in owner._window_order:
		var node: Node = owner._windows.get(key)
		if node != null and node._window_shown:
			out.append(str(key))
	return out


## The front-most open window, or null. Director's active window, which is where
## a keypress goes when the pointer is not over anything.
func _front_window() -> Node:
	var owner := stage_preview()
	for i in range(owner._window_order.size() - 1, -1, -1):
		var node: Node = owner._windows.get(owner._window_order[i])
		if node != null and node._window_shown:
			return node
	return null


## The front-most open *modal* window, or null.
##
## §14: a modal window blocks its parent. Input only — the movie underneath keeps
## running, which is why this gates the click and key routing and not `_process`.
## Unverified: nothing in this corpus sets `the modal of window`.
func modal_window() -> Node:
	var owner := stage_preview()
	for i in range(owner._window_order.size() - 1, -1, -1):
		var node: Node = owner._windows.get(owner._window_order[i])
		if node != null and node._window_shown and node._modal:
			return node
	return null


## The window a stage point lands in, front-most first, or null.
##
## §4.2's search order, one level up: Director hit-tests windows before sprites,
## and the front window takes the click whether or not anything in it answers.
## The whole frame counts, chrome included — a click on a title bar belongs to
## the window it titles.
func window_at(at: Vector2) -> Node:
	var owner := stage_preview()
	for i in range(owner._window_order.size() - 1, -1, -1):
		var node: Node = owner._windows.get(owner._window_order[i])
		if node == null or not node._window_shown:
			continue
		if node.window_frame().has_point(at):
			return node
	return null


## A stage point in one of this window's own coordinates. The inverse of the
## node's transform, written out because `drawRect` scaling makes it more than a
## subtraction.
func stage_to_local(at: Vector2) -> Vector2:
	var factor := window_scale()
	var local := at - position
	if factor.x != 0.0 and factor.y != 0.0:
		local /= factor
	return local


## Deliver a click at a stage point to whichever movie owns that point.
##
## Called from `_input` and directly by the harnesses, which is the point of it
## being a method: routing that only exists inside an `InputEvent` handler cannot
## be asserted headlessly, and "the click went to the wrong movie" is precisely
## the failure this change is about.
##
## Returns the movie that took the click, or null when a modal window swallowed
## one aimed elsewhere.
func route_click(at: Vector2) -> Node:
	var blocking := modal_window()
	if blocking != null and not blocking.window_frame().has_point(at):
		# §14: a modal window blocks its parent, so a click outside it is
		# discarded rather than delivered to whatever is under it. Unverified.
		return null
	var front := window_at(at)
	if front != null and front != self:
		front.route_click(front.stage_to_local(at))
		return front
	# A wait-for-click frame is released by the mouse-down and not by the score
	# (§9.2), and it is released in the movie that was clicked — JOKE's last frame
	# is a wait-for-click that the player ends by clicking the window.
	if _saw_press:
		_clock.clicked()
	# §11: a click aborts a running colour cycle and restores the palette it was
	# rotating. It is the same mouse-down that releases a wait, and for the same
	# reason -- both are things Director lets the player cut short.
	if _palette_state.effect_running():
		if _palette_state.abort():
			_palette_applied()
		# Only the hold the cycle itself asked for. A transition running on the
		# same frame is not the player's to cut short, and releasing by reason
		# rather than unconditionally is what keeps the two apart.
		if _clock.hold_reason() == FrameClock.REASON_PALETTE:
			_clock.release()
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
## sprite that swaps to a member with a different cursor under a stationary
## mouse keeps the old one until something moves.
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


func cursor_at(at: Vector2) -> Variant:
	if _score == null:
		return _global_cursor
	return Cursor.at(self, at, _score.frame(_index).get("sprites", []),
		_channel_cursors, _global_cursor)


func lingo_set_cursor(value: Variant) -> void:
	_cursor_now = Cursor.install(value, _table, _palette, scale.x)


## Kept on the node: `_cursor_image` and `_member_image` are reached by name.
func _cursor_image(data_id: int, mask_id: int):
	return Cursor.compose(data_id, mask_id, _table, _palette)


func _member_image(cast_id: int) -> Image:
	return Cursor.member_image(cast_id, _table, _palette)


func _cursor_for_stage(image: Image, hotspot: Vector2) -> Dictionary:
	return Cursor.for_stage(image, hotspot, scale.x)


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
		"cuepointnames":
			return _audio.call("cue_point_names", channel)
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


## `sound close <channel>` — stop and release, as against `sound stop`, which
## leaves the channel allocated. Written nowhere in this corpus; see
## `AudioDirector.close_channel` for what the difference amounts to here.
func lingo_close_sound(channel: int) -> void:
	if _audio != null:
		_audio.call("close_channel", channel)
	_score_sound.set_puppet(channel, false)
	_trace("f%d close ch%d" % [_index, channel])


func lingo_fade_sound(channel: int, ticks: int, fade_in: bool) -> void:
	if _audio != null:
		_audio.call("fade_in" if fade_in else "fade_out", channel, ticks)
	_trace("f%d fade%s ch%d %d ticks" % [_index, "In" if fade_in else "Out", channel, ticks])


## `puppetSound <channel>, <member>` — a script taking a sound channel off the
## score, exactly as `puppetSprite` takes a sprite channel.
##
## Two things at once, and conflating them is the mistake to avoid: it *claims*
## the channel, so the score stops driving it until the claim is released, and it
## plays a **cast member** — not a file. `puppetSound <channel>, 0` and the
## bare `puppetSound 0` release it, and Director's release also silences the
## channel, which is what makes `puppetSound 0` the idiom for "shut up".
##
## Written nowhere in the corpus this port was built on (`tools/sound_survey.gd`),
## so the member-versus-file reading is the reference's. It is also the reason
## this is not simply `sound playFile` with a different name: the preview host
## used to route it there, which would have played a *file* named after a member
## and claimed nothing.
func lingo_puppet_sound(channel: int, which: Variant, cast: String = "") -> void:
	var ch := maxi(1, channel)
	var releasing := which == null or (
		(typeof(which) == TYPE_INT or typeof(which) == TYPE_FLOAT) and int(which) == 0
	) or (typeof(which) == TYPE_STRING and str(which).strip_edges() == "")
	if releasing:
		_score_sound.set_puppet(ch, false)
		lingo_stop_sound(ch)
		return
	_score_sound.set_puppet(ch, true)
	var ref: Array = _resolve_member_ref(which, cast)
	play_sound_member(ch, int(ref[0]), int(ref[1]))


## Puppet state, delegated to `preview/sprite_state.gd`. The dictionaries stay
## on the node -- `tools/` reads `_overrides` by name -- and are passed in.
func _effective(sprite: Dictionary) -> Dictionary:
	return SpriteState.effective(sprite, _overrides, _table)


func _note_member(channel: int, cast_id: int) -> void:
	SpriteState.note_member(channel, cast_id, _last_member, _loop_start, _ticks)


func lingo_sprite_prop(channel: int, prop: String) -> Variant:
	return SpriteState.read_prop(channel, prop, _overrides,
		_score.frame(_index).get("sprites", []))


func lingo_puppet_sprite(channel: int, on: bool) -> void:
	SpriteState.set_puppet(channel, on, _overrides)


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
	SpriteState.write_prop(channel, prop, value, _overrides,
		_score.frame(_index).get("sprites", []))


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
## this game the shared HUD fields -- the score, the inventory -- live in a
## *linked* cast, so `field "points"` answered "" from a movie that has one on
## screen. And the write was a no-op, so nothing a script put into a field could
## ever be read back or drawn: the score would have rendered its authored
## placeholder for ever.
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
	# The text is drawn straight from here on the next paint, so a write has to
	# ask for one. Without it a HUD updates only when something else happens to
	# redraw.
	queue_redraw()


func _resolve_field(name: String) -> Array:
	if _table == null:
		return []
	return TextArt.resolve(name, _resolve_member_ref(name, ""), _table)


func _field_text_of(member: Dictionary) -> String:
	return TextArt.text_of(member, _field_text, _table)


func _field_key(lib: int, number: int) -> String:
	return TextArt.key_for(lib, number, _table)


func _forget_field_text_of(container_path: String) -> void:
	TextArt.forget(container_path, _field_text)


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

