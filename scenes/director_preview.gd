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
const SpriteProps := preload("res://scenes/preview/sprite_props.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")
const Toast := preload("res://scenes/preview/toast.gd")
const ContainerPicker := preload("res://scenes/preview/container_picker.gd")
const TextArt := preload("res://scenes/preview/text_art.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const Cursor := preload("res://scenes/preview/cursor.gd")
const Windows := preload("res://scenes/preview/windows.gd")
const Sound := preload("res://scenes/preview/sound.gd")
const Trails := preload("res://scenes/preview/trails.gd")
const PaletteView := preload("res://scenes/preview/palette_view.gd")
const StagePaint := preload("res://scenes/preview/stage_paint.gd")
const FrameLoop := preload("res://scenes/preview/frame_loop.gd")
const Scripts := preload("res://scenes/preview/scripts.gd")
const Members := preload("res://scenes/preview/members.gd")
const MovieSession := preload("res://scenes/preview/movie_session.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")
const DebugReport := preload("res://scenes/preview/debug_report.gd")
const Boot := preload("res://scenes/preview/boot.gd")
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
## The window-type numbers, re-exported from `preview/windows.gd` so the node
## and the module cannot drift apart on what `windowType` 2 means.
const WINDOW_PLAIN_SHADOW := Windows.PLAIN_SHADOW
const WINDOW_DOCUMENT := Windows.DOCUMENT
const WINDOW_TITLE_BAR := Windows.TITLE_BAR
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
## Same keys again, holding the inverted artwork a sprite draws with while it is
## being pressed (§4.6, `preview/hilite.gd`). Kept rather than derived per paint:
## a held button would otherwise cost a full per-pixel pass over its member every
## frame. Each entry carries the `_hit_images` Image it was derived from and is
## discarded when that object is replaced, so it needs no clearing of its own --
## `preview/hilite.gd:_inverted` says why that is not just an optimisation.
var _hilite_textures: Dictionary = {}
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
## The *movie's* `ccl ` list, for the `L` report. Resolution no longer reads it:
## a film loop is a cast member, so its children index into the list of whichever
## container the loop lives in, and `DirectorCastTable.cast_list_for` answers that
## per library. Reading the movie's list for a loop in a linked cast is what drew
## MURDER1's inventory hands out of `tofi`.
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
## The last click as `preview/snapshot.gd` records it: where, which channel,
## which script answered and whether it declared a handler. Kept rather than
## recomputed on demand, because the score keeps running and the frame that was
## clicked is not the frame anybody asks about it on.
var _last_click: Dictionary = {}
## The self-dismissing message in the corner, and when it stops being due.
## `preview/toast.gd` owns the rules; the state is here because that is where the
## harnesses can see it.
var _toast := ""
var _toast_until := 0
## The container picker, as `preview/container_picker.gd` keeps it: whether it is
## open, what has been typed, and which entry is selected. Closed by default and
## consulted only while open -- see `input_router.gd:key_event`.
var _picker: Dictionary = {"open": false}
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
## Which movie took the mouse-DOWN, and which script answered for it. Both are
## latched by the press and consumed by the release, because a click is two
## messages at two moments and `mouseUp` belongs to the thing that received the
## `mouseDown` -- not to whatever the pointer happens to be over when the button
## comes back up. A drag moves the sprite the entire time it is held, so
## resolving either again at release would be answering a different question.
## `preview/interaction.gd:press` has the rest of that argument.
var _press_target: Node = null
var _click_script: Dictionary = {}
## The channel the press landed on, which the release needs and the script does
## not carry: `mouseUp` goes out only when the button came up inside this sprite,
## and `mouseUpOutSide` when it came up anywhere else (§8.1).
var _press_channel := 0
## Where the last input event happened, in this movie's coordinates, and whether
## one has arrived yet. `stage_mouse` has why this is kept rather than asked of
## the DisplayServer -- it is what makes the engine work on a touchscreen.
var _pointer := Vector2.ZERO
var _pointer_seen := false
## Does the pointer come from input events, or from the OS cursor?
##
## `FEATURE_MOUSE` rather than a platform name, because the question is precisely
## "is there a cursor to ask about". A phone answers no. Headless answers no too,
## and that is the right answer for it: a headless harness's pointer is whatever
## it injected, and reading the developer's desktop cursor instead is how a check
## comes to pass or fail depending on where somebody left their mouse.
var _pointer_from_events := not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)
## What the pointer is simply *over*, as against `_hover_channel`, which is what
## a click would reach. §4.5: `the rollOver` applies no eligibility filter and no
## matte, so the two answer different channels over the same pixel and both
## answers are needed. Drives `mouseEnter`/`mouseLeave`/`mouseWithin`.
var _rollover_channel := 0
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


## A window is the same scene standing up a second movie, configured before it
## enters the tree rather than from the command line. Split in
## `preview/boot.gd` so that the one state everything else in this file assumes
## -- a loaded container with a score, a cast table and an interpreter -- is
## reached the same way by both.
func _ready() -> void:
	if _window_key != "":
		Boot.as_window(self)
	else:
		Boot.stage(self)


func _ready_as_window() -> void:
	Boot.as_window(self)


func _start_lingo(path: String) -> void:
	Boot.start_lingo(self, path)


## Open a container and make it the movie now playing.
##
## The per-container work is `preview/movie_session.gd`'s and shared with
## `lingo_go_movie`; what is here is only what opening the *first* movie does
## differently, which is to fail the whole load rather than decline a jump.
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
	MovieSession.adopt(self)
	return true


## `go to movie "day1.dir"` -- open another container and start playing it.
##
## Resolved from the current movie's own directory first, because a linked name
## means the file beside the one that named it; this game ships two containers
## called MASTER.CST and the same hazard applies to movies.
##
## Nothing is torn down until the new container has been opened *and* its score
## has parsed. A jump to a movie that will not load leaves the current one
## playing rather than stranding the player on a dead stage.
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
	MovieSession.adopt(self)
	MovieSession.forget_previous(self, previous_path)
	_preloader = Preloader.new(_score)

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
	get_window().title = "%s  -  %d frames" % [target.get_file(), _score.frame_count]
	print("go movie -> %s frame %d" % [target.get_file(), _index])
	queue_redraw()


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


## Script resolution and dispatch, delegated to `preview/scripts.gd`. The rule
## that matters -- a member number is per cast, so the library is part of the key
## -- lives there with the evidence for it.
func _script_in_lib(cast_lib: int, member: int) -> Dictionary:
	return Scripts.in_lib(_interpreter, _lib_keys, cast_lib, member)


func _script_for_member(member: int) -> Dictionary:
	return Scripts.for_member(_interpreter, _script_casts, member)


func _sprite_script(channel: int, frame_index: int) -> Dictionary:
	return Scripts.for_sprite(self, _score, channel, frame_index)


func _dispatch(handler: String, script: Dictionary) -> void:
	Scripts.dispatch(self, _interpreter, handler, script)


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


## The frame script covering a frame, delegated to `preview/scripts.gd`.
func _frame_script(index: int) -> Dictionary:
	return Scripts.for_frame(self, _score, index)


func _tally(into: Dictionary, key: String) -> void:
	into[key] = int(into.get(key, 0)) + 1


## The debug report, delegated to `preview/debug_report.gd`.
func _report() -> void:
	DebugReport.emit(self)


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


## Trails, delegated to `preview/trails.gd`. The layer stays on the node: it is
## read by name from `tools/trails.gd`, and `_trail_image` is reassigned to null
## on a movie change, which a held reference could not do.
func _wants_trails(frame: Dictionary) -> bool:
	return Trails.wanted(frame, _overrides)


func _settle_trails(placed_now: Dictionary, to_stamp: Array[Dictionary]) -> void:
	Trails.settle(self, placed_now, to_stamp)


func _trail_erase(rect: Rect2) -> void:
	Trails.erase(self, rect)


func _trail_stamp(image: Image, at: Vector2) -> void:
	Trails.stamp(self, image, at)


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
	_hilite_textures.clear()
	queue_redraw()


func _palette_table_for(id: int) -> PackedByteArray:
	return PaletteView.table_for(id, _table)


func _palette_libs() -> Array:
	return PaletteView.libs(_table)


## The frame loop, delegated to `preview/frame_loop.gd`. The playhead, the clock
## and the pending-enter debt stay on the node: `tools/` reads `_index`, `_clock`
## and `_pending_enter` by name, and several harnesses write `_index` directly.
func _process(delta: float) -> void:
	if _score == null or _paused:
		return
	if _score.frame(_index).is_empty():
		return
	# §6.3 step 10 caches the rollover as part of resolving the frame, so it is
	# recomputed per tick and not per pointer movement. Two things depend on that
	# and both are invisible until they are not: a sprite that moves under a
	# stationary cursor changes what is rolled over without the mouse doing
	# anything, and a **touchscreen never sends motion at all** unless a finger is
	# already down -- so a tap would otherwise leave `the rollOver` naming
	# whatever was under the previous gesture.
	track_rollover(stage_mouse())
	# §6.3 step 3: `mouseWithin` is part of the frame update, not of pointer
	# motion -- it fires every tick the cursor is inside the sprite, a stationary
	# cursor included. Ahead of the tick because the reference puts it there,
	# before the playhead can move out from under it.
	Interaction.within(self)
	FrameLoop.tick(self, delta)


func _sync_frame_entry() -> void:
	FrameLoop.sync_frame_entry(self)


func _begin_transition(frame: Dictionary) -> bool:
	return FrameLoop.begin_transition(self, frame, _table)


func _advance() -> Dictionary:
	return FrameLoop.advance(self)


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


## Input, delegated to `preview/input_router.gd`. The routing decisions live
## there because Godot's own reverse-tree `_input` order is invisible to a
## headless harness, and "the click went to the wrong movie" has to be
## assertable.
func _input(event: InputEvent) -> void:
	# **Where the event happened, not where the cursor is now.** The two agree on
	# a desktop and do not on a touchscreen: Godot synthesises the button and
	# motion events from a finger but leaves `DisplayServer.mouse_get_position()`
	# alone, so a click routed by the cursor lands wherever the absent mouse was
	# last -- which is (0,0) on a phone. Measured in `tools/touch_input.gd`.
	# `note_pointer` records it for everything that asks *between* events.
	if event is InputEventMouse:
		var at := (make_input_local(event) as InputEventMouse).position
		note_pointer(at)
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_LEFT:
				InputRouter.mouse_button(self, button, at, SKIP_RECT)
			elif button.button_index == MOUSE_BUTTON_RIGHT:
				InputRouter.right_mouse_button(self, button, at)
			return
		InputRouter.mouse_motion(self, at)
		return
	if not (event is InputEventKey and event.pressed):
		return
	InputRouter.key_event(self, event as InputEventKey)


## Arm the clip rectangle. Re-armed from `_draw` every paint rather than at
## startup: the flag does not survive the command-list clear that precedes each
## paint. See `preview/stage_paint.gd`.
func _clip_to_stage() -> void:
	_clip_rect = StagePaint.clip_to_stage(self, STAGE)


## One paint of the stage, delegated to `preview/stage_paint.gd`.
func _draw() -> void:
	_clip_to_stage()
	# The stage colour, which is what every non-trails repaint fills with. Over
	# the movie's own rect only: the chrome around a window is painted by
	# `_draw_window_chrome` and is not part of the movie.
	draw_rect(Rect2(Vector2.ZERO, window_size() if _window_key != "" else Vector2(STAGE)),
		Color.BLACK, true)
	if _window_key != "":
		_draw_window_chrome()
	if _status != "":
		draw_string(ThemeDB.fallback_font, Vector2(16, 32), _status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.RED)
		return
	if _score == null:
		return

	# Rebuilt from scratch each paint rather than accumulated: it is a record of
	# what is on the stage now, and a field that left the frame must stop being
	# in it or a harness would assert against a channel that is no longer drawn.
	_text_drawn.clear()
	var frame: Dictionary = _score.frame(_index)
	StagePaint.paint_frame(self, frame, _table, STAGE)
	if _show_boxes:
		_draw_hotspots(frame)
	if _window_key != "":
		return
	StagePaint.draw_overlays(self, frame, STAGE, SKIP_RECT)
	# A paused preview does not repaint on its own, so a toast that needs a paint
	# to disappear would stay up until something else asked for one.
	if Toast.draw(self, _toast, _toast_until, STAGE):
		queue_redraw()
	ContainerPicker.draw(self, _picker)


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
	return FilmLoopView.draw(self, sprite, _table, _loops, _ticks, _loop_start)


func _child_lib(child: Dictionary, owner_lib: int) -> int:
	return FilmLoopView.child_lib(child, owner_lib, _table)


func _open_loop(lib: int, member: Dictionary):
	return FilmLoopView.open_loop(lib, member, _table)


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


## The two halves of a click, delegated to `preview/interaction.gd`. They used to
## be one `_click` that dispatched `mouseDown` and `mouseUp` back to back on the
## press; the module's `press` doc comment has why that broke every drop.
func _press_click(at: Vector2) -> void:
	Interaction.press(self, at)


func _release_click(at: Vector2) -> void:
	Interaction.release(self, at)


## Where the pointer is, for `the rollOver` and the D5/D6 hover messages.
##
## A crossing is decided here rather than inside `Interaction` so that the two
## sends are driven by the *change*, not by the position: `mouseEnter` is one
## message per entry, and a version that fired on every motion event inside the
## sprite would be `mouseWithin` under another name.
func track_rollover(at: Vector2) -> void:
	if _score == null:
		return
	if _host != null:
		# `the lastRoll` is "how long since the pointer moved", so the stamp
		# belongs on every motion event and not only on the ones that cross a
		# sprite boundary.
		_host.last_roll_ms = Time.get_ticks_msec()
	var was := _rollover_channel
	_rollover_channel = Interaction.rollover_channel(
		self, at, _score.frame(_index).get("sprites", []))
	Interaction.hover_changed(self, was, _rollover_channel)


## `rightMouseDown` / `rightMouseUp`, delegated to `preview/interaction.gd`.
func route_right_button(at: Vector2, pressed: bool) -> void:
	Interaction.right_button(self, at, pressed)


## `the rollOver` with no argument: the channel the pointer is over, not a
## boolean. §5's own warning — one implementation defaulting the argument to 1
## answers "is the mouse over channel 1" where the script asked "which channel is
## the mouse over", and both are plausible-looking integers.
func lingo_rollover_channel() -> int:
	return _rollover_channel


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
	# Release what this frame is waiting on, and nothing else.
	#
	# This used to jump the playhead to the last frame of the movie, on the
	# assumption that the end of the file is the end of the scene. **A Director
	# movie's last frame is not its ending.** A movie is a strip of
	# independently labelled segments, and the last frame is only the last
	# *segment's* last frame -- so the jump lands somewhere the author never
	# meant to be entered from here, and `tools/skip_state.gd` measures what
	# that costs across this corpus:
	#
	#   MURDER1 f883 runs `go("conect2")`, which is frame 790 -- the jump goes
	#   *backwards* into the tail being skipped and replays 94 frames, so from
	#   the player's chair SKIP did nothing and they press it again;
	#
	#   DAY1 f2783 is the tail of a `play`-called talk clip and runs
	#   `play "done"` with nothing on the stack, so nothing returns and the
	#   score's own advance has nowhere to go. The playhead never moves again.
	#   Every symptom downstream of that reads as something else -- most of a
	#   session went into "the cursor never comes back", which was the cursor
	#   correctly recomputing over a dead playhead.
	#
	# Running the intervening frame scripts instead is not the fix either. That
	# is right for a linear cutscene and catastrophic for a hub: the frames
	# between here and the end of DAY1 are dozens of unrelated rooms, not "the
	# rest of this scene".
	#
	# What a player means by SKIP is "stop waiting", not "go to the end of the
	# file". Releasing the hold lets the movie's own scripts drive to their own
	# exit -- which walks MURDER1 to its `go("clif2","day1.dir")` and does
	# nothing harmful in a hub. Director has no skip, so there is no fidelity
	# question here; this is a judgement about an affordance.
	_clock.release()
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


## The rect `sprite A intersects B` and `sprite A within B` measure: where the
## sprite is **now**, puppet writes included.
##
## Deliberately *not* `lingo_rollover`'s rect, and the difference is the point of
## having two. `rollOver` reads the score because a menu script swaps a button's
## art precisely *because* `rollOver` is true, so measuring the swapped member
## feeds the answer back into the question and nothing ever settles. Nothing
## feeds back here: `intersects` is asked about a sprite the player is dragging,
## and where the player has dragged it to is the entire question.
##
## An empty answer for a hidden sprite rather than its last rect, because
## `_effective` treats `visible` as "not drawn and not measured" -- the same rule
## the hit test uses -- and a sprite nobody can see should not be droppable onto.
func lingo_sprite_rect(channel: int) -> Rect2:
	if _score == null or channel <= 0:
		return Rect2()
	for sprite in _score.frame(_index).get("sprites", []):
		if int(sprite["channel"]) == channel:
			var live: Dictionary = _effective(sprite)
			return Rect2() if live.is_empty() else _sprite_rect(live)
	return Rect2()


func current_frame() -> int:
	return _index


## Where the pointer is, in this movie's own coordinates.
##
## **Not `get_local_mouse_position()` any more, and the reason is the whole of
## the touch story.** That helper ends in `Viewport.get_mouse_position()`, and on
## the *root* viewport that function does not answer from input at all: it falls
## through to `DisplayServer.mouse_get_position()`, the real OS cursor. A
## touchscreen has no OS cursor, and Godot's touch-to-mouse emulation does not
## invent one -- it synthesises the button and motion *events* and leaves the
## DisplayServer's pointer where it was.
##
## Measured, not reasoned: `tools/touch_input.gd` feeds an `InputEventScreenTouch`
## through `Input.parse_input_event()` and, before this change, `mouseDown` went
## out correctly and `the mouseH`/`the mouseV`/`the clickOn` all reported the
## desktop cursor's position instead of the finger's -- so the message fired and
## every coordinate in it was wrong. On a phone that is every hotspot in every
## title answering for a point the player never touched, which looks like a
## broken hit test rather than a missing pointer.
##
## So where the platform **has** a cursor, that cursor stays authoritative --
## nothing about the desktop path changes, and a harness that warps the real
## pointer and then calls a router directly still reads what it warped to.
## `tools/sprite_drag.gd` does exactly that, and it is the check that showed an
## unconditional switch to the cached value was the wrong shape of fix.
##
## Where the platform has none, the position an input event carried is the
## pointer, because nothing else is.
##
## Which of the two is in force is `_pointer_from_events`, and it is a variable
## rather than an inline platform test for one reason: the device branch is the
## one piece of the input path that no run on a development machine can reach,
## and that makes it the piece most likely to be quietly wrong. With a seam,
## `tools/touch_input.gd` drives it on a desktop and asserts the coordinates come
## out right; without one, "touch works on Android" would be a claim in a
## document with nothing behind it.
func stage_mouse() -> Vector2:
	if _pointer_from_events and _pointer_seen:
		return _pointer
	return get_local_mouse_position()


## Record where an input event happened. Called with this movie's own
## coordinates: the stage passes the event through `make_input_local`, and a
## window is told by whoever routed the event into it, because a window node has
## its input processing switched off (`preview/boot.gd`) and never sees one.
func note_pointer(at: Vector2) -> void:
	_pointer = at
	_pointer_seen = true


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


## The window property vocabulary, delegated to `preview/windows.gd`. These stay
## on the node under their Director names because `preview_lingo_host.gd` and the
## window harnesses reach them by those names.
func set_own_window_prop(prop: String, value: Variant) -> void:
	Windows.write_prop(self, prop, value)


func own_window_prop(prop: String) -> Variant:
	return Windows.read_prop(self, prop)


func window_size() -> Vector2:
	return Windows.size_of(self)


func window_origin() -> Vector2:
	return Windows.origin_of(self)


func window_title() -> String:
	return Windows.title_of(self)


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


## Window geometry and chrome, delegated to `preview/windows.gd`. The lifecycle
## stays on the node, because a window here *is* another preview node and
## creating one is node manipulation.
static func _rect_of(value: Variant):
	return Windows.rect_of(value)


func _border_width() -> int:
	return Windows.border_width(_window_type)


func _has_title_bar() -> bool:
	return Windows.has_title_bar(_window_type, _title_visible)


func chrome_inset() -> Vector2:
	return Windows.chrome_inset(_window_type, _title_visible)


func window_scale() -> Vector2:
	return Windows.scale_of(_draw_rect, window_size())


func window_frame() -> Rect2:
	return Windows.frame_of(window_origin(), window_size() * window_scale(),
		chrome_inset(), _border_width())


func _draw_window_chrome() -> void:
	Windows.draw_chrome(self, window_size(), _window_type, _title_visible,
		window_title())


func window_keys() -> Array:
	return Windows.keys(stage_preview())


func _front_window() -> Node:
	return Windows.front(stage_preview())


func modal_window() -> Node:
	return Windows.modal(stage_preview())


func window_at(at: Vector2) -> Node:
	return Windows.at(stage_preview(), at)


## A stage point in one of this window's own coordinates. The inverse of the
## node's transform, written out because `drawRect` scaling makes it more than a
## subtraction.
func stage_to_local(at: Vector2) -> Vector2:
	var factor := window_scale()
	var local := at - position
	if factor.x != 0.0 and factor.y != 0.0:
		local /= factor
	return local


## A whole click at a stage point — press then release — delivered to whichever
## movie owns that point.
##
## Called directly by the harnesses, which is the point of it being a method:
## routing that only exists inside an `InputEvent` handler cannot be asserted
## headlessly, and "the click went to the wrong movie" is precisely the failure
## this change is about. `_input` drives the two halves separately, because a
## real button is down for as long as the player holds it and everything a drag
## does happens in that gap.
##
## Returns the movie that took the click, or null when a modal window swallowed
## one aimed elsewhere.
func route_click(at: Vector2) -> Node:
	var took := route_press(at)
	route_release(at)
	return took


## The mouse-down: which movie owns the point, the holds a press releases, the
## drag it may start, and the `mouseDown` message.
func route_press(at: Vector2) -> Node:
	_press_target = null
	var blocking := modal_window()
	if blocking != null and not blocking.window_frame().has_point(at):
		# §14: a modal window blocks its parent, so a click outside it is
		# discarded rather than delivered to whatever is under it. Unverified.
		return null
	var front := window_at(at)
	if front != null and front != self:
		_press_target = front
		front.route_press(front.stage_to_local(at))
		return front
	_press_target = self
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
	_press_click(at)
	return self


## The mouse-up: it goes to the movie that took the *press*, wherever the pointer
## has since travelled.
##
## Following the pointer instead would be wrong in exactly the case that matters:
## a sprite dragged out of a window, or off the stage's edge and back, would have
## its release answered by whatever it was let go over. Director sends `mouseUp`
## to the recipient of the `mouseDown`, and a release with no press behind it —
## the button coming up over a movie that opened mid-click, or after SKIP took
## the press — is not a click at all and dispatches nothing.
func route_release(at: Vector2) -> Node:
	var target: Node = _press_target
	_press_target = null
	if target == null or not is_instance_valid(target):
		return null
	if target != self:
		target.route_release(target.stage_to_local(at))
		return target
	_release_click(at)
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


## Sound routing, delegated to `preview/sound.gd`. The state is `AudioDirector`'s
## rather than either module's, because the stage and any open window must agree
## about a channel and neither survives a `go to movie`.
func _pump_sound(_delta: float) -> void:
	Sound.pump(self, _audio, _clock)


func play_sound_member(channel: int, cast_lib: int, cast_id: int) -> bool:
	return Sound.play_member(self, _audio, _table, channel, cast_lib, cast_id)


func _begin_score_sound(frame: Dictionary) -> void:
	Sound.begin_score_sound(self, _score_sound, frame)


func lingo_sound_prop(channel: int, prop: String) -> Variant:
	return Sound.read_prop(_audio, channel, prop)


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


## Through `preview/sprite_props.gd`, which translates the name the *script*
## wrote into the key the override table is merged under. The two vocabularies
## differ on `the moveableSprite of sprite`, and nothing used to sit between
## them -- see that file for what that cost.
func lingo_sprite_prop(channel: int, prop: String) -> Variant:
	return SpriteProps.read(channel, prop, _overrides,
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
	SpriteProps.write(channel, prop, value, _overrides,
		_score.frame(_index).get("sprites", []))


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


## Member resolution, delegated to `preview/members.gd`. The rule that matters --
## the library is part of the answer, not a hint -- lives there with the evidence.
func _resolve_member_ref(which: Variant, cast: String) -> Array:
	return Members.resolve_ref(which, cast, _table)


func _resolve_member(which: Variant, cast: String) -> int:
	return int(_resolve_member_ref(which, cast)[1])


func lingo_member_prop(which: Variant, cast: String, prop: String) -> Variant:
	return Members.read_prop(self, _resolve_member_ref(which, cast), prop, _table)


func lingo_member_number(which: Variant, cast: String) -> Variant:
	return _resolve_member(which, cast)

