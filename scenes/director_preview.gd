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
const TextFocus := preload("res://scenes/preview/text_focus.gd")
const MovieSave := preload("res://scenes/preview/movie_save.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const Cursor := preload("res://scenes/preview/cursor.gd")
const Windows := preload("res://scenes/preview/windows.gd")
const Sound := preload("res://scenes/preview/sound.gd")
const Trails := preload("res://scenes/preview/trails.gd")
const PaletteView := preload("res://scenes/preview/palette_view.gd")
const StagePaint := preload("res://scenes/preview/stage_paint.gd")
const Paint := preload("res://director/director_paint.gd")
const FrameLoop := preload("res://scenes/preview/frame_loop.gd")
const Scripts := preload("res://scenes/preview/scripts.gd")
const EventChain := preload("res://scenes/preview/event_chain.gd")
const Members := preload("res://scenes/preview/members.gd")
## The digital-video and sound-member property surface (§5, and
## `docs/ENGINE_TODO.md`'s digital-video block). Here for the *write* half of the
## member flags; the read half reaches it through `preview/members.gd`.
const Media := preload("res://scenes/preview/media.gd")
const MovieSession := preload("res://scenes/preview/movie_session.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const SaveState := preload("res://scenes/preview/save_state.gd")
const SaveFiles := preload("res://scenes/preview/save_files.gd")
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

## The stage size to fall back on when the movie states none.
##
## **A fallback, not the rule.** A Director movie carries its own stage rect in
## its config chunk (`director/director_config.gd`, `DRCF` / `VWCF` before D5),
## and the reference resizes the stage window to it on every movie load --
## `movie.cpp:Movie::loadArchive`, "For the stage, always resize to the movie
## rect". `stage_size()` is that rect's size, and it is what the letterbox, the
## clip, the paint, the hit test and the debug overlays all ask.
##
## This number is what a container whose config is missing or will not parse gets
## instead, so such a movie still opens rather than drawing at 0x0. It is 640x480
## because that is what all six titles of the corpus this port was built on
## declare -- which is exactly why it sat here as *the* stage size for so long,
## and why `test-games/itamar-magichat/magichat.dir` at 800x600 is the file that
## says whether the size flows or was only ever assumed.
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
## Frames SKIP has already sent the playhead to, in this movie. A marker list is
## not a list of scenes -- see `skip_to_end` -- and without this the button can
## cycle. Cleared with the rest of the per-movie state.
var _skip_sent: Dictionary = {}
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
## `exitFrame` has already been sent for the frame the playhead is standing on.
##
## `Score::_exitFrameCalled` (`reference/scummvm/score.cpp:672-675`), and it exists
## for one situation: a frame whose `exitFrame` handler calls `pause`. The playhead
## stays on that frame, so without this the *next* runnable step would send its
## `exitFrame` again, call `pause` again, and undo the `continue` that a click just
## ran — the room would sit on the pausing frame re-pausing itself on every click,
## which is a lock and not a pause.
##
## **Cleared where the reference clears it: once per unpaused step, beside the
## `enterFrame` dispatch** (`score.cpp:827-828`), which is `_enter_frame_or_defer`
## here. Not on a frame-number change, which is the tempting spelling and is wrong:
## `frame_loop.gd:sync_frame_entry` early-returns when the index has not moved, so a
## latch cleared there would never clear under `go to the frame` — and that is how
## every room in both corpora stands still. `BLAEGOZ.dir` frames 1051-1076 poll
## `soundBusy` from `exitFrame` on every step of exactly such a hold, and a
## once-per-frame-number latch would answer that poll once and then go deaf.
var _exit_frame_called := false
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
## Synchronous repaints -- `repaint_now`, which is what `updateStage` reaches.
## Counted rather than inferred because "did the stage redraw *inside* the
## handler" is the whole assertion, and a harness that could only look afterwards
## cannot tell one paint from thirty (`tools/update_stage.gd`).
var _repaints := 0
## `updateStage` calls, whether or not they reached a paint. The two differ by
## the ones a hidden or detached node declined, and the difference is what says
## an arm is bound rather than merely present.
var _update_stage_calls := 0
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
## The editable-text widget's state (§8.4), kept here rather than in
## `preview/text_edit.gd` for the reason `scenes/preview/README.md` gives: state
## stays on the node, because `tools/` reads it by name and a field moved off
## makes a harness read null and report zero rather than fail.
##
## `the selStart` and `the selEnd` are **movie-level and not per-field**, which
## is Director's design and not a simplification -- one range, pushed into
## whichever widget holds focus. `_focus_member` is the cast id the focus was
## claimed on, so §7.7's "preserved across a frame when the cast id is unchanged"
## can be tested rather than assumed.
var _focus_channel := 0
var _focus_member := 0
var _sel_start := 0
var _sel_end := 0
## When the caret last moved, so the blink restarts on a keystroke instead of
## possibly blinking out on the character just typed.
var _caret_since := 0
## True between a press that landed inside an editable field and the button
## coming up: the selection's moving end follows the pointer while it is set.
## §8.4. Without it the caret could be *placed* with the mouse and nothing could
## be *selected* with it, which is exactly what a save slot needs.
var _text_drag := false
## Same keys as `_field_text`: `member("x").editable = <n>` from Lingo, overriding
## the member's own authored flag.
var _member_editable: Dictionary = {}
## `set the hilite of member "x" to 1` -- §4.6's *other* hilite, and a different
## mechanism from the one `preview/hilite.gd` is named for.
##
## That one is auto-hilite: a press inverts the sprite while the button is held,
## and nothing in the movie asks for it. This is a **flag a script sets and the
## movie leaves set** -- stored for every member type and drawn for one.
##
## Director keeps it on the cast member base class
## (`castmember.cpp:CastMember::setField(kTheHilite)` accepts it whatever the
## type) and reads it back to draw in a single place, `text.cpp:355` under `case
## kCastButton:`. `bitmap.cpp` and `shape.cpp` never mention it. So this
## dictionary is a store: `the hilite of member` round-trips out of it for any
## member, and `preview/hilite.gd` decides separately whether anything is drawn.
##
## **This said the opposite until 2026-08-09**, and it is the reason Rating's
## Zehava swam in reverse video (`docs/bugs-closed.md` 66): that Rating's `set the
## hilite of member "rectang" to 1`, once per room, was "how Director draws a
## selection" on the shape member it moves to mark the chosen option. It is not.
## Rating writes this flag at 39 sites across 21 containers naming 26 shapes, 5
## bitmaps and 3 film loops and not one button, and Director draws none of them
## differently. Whatever marks the chosen option in that game, it is not this.
##
## Same keys as `_field_text`, for the same reason: a member is `(container,
## library, number)` and two movies can hold the same number.
var _member_hilite: Dictionary = {}
## `set the textSize of member "x" to 24` and the rest of §5's writable text
## style, as `<field key> -> {style name: value}`.
##
## A member record is parsed out of a read-only container, so a property write has
## nowhere to land unless the node keeps one -- the same reason `_field_text` and
## `_member_editable` exist, and they are keyed the same way.
## `preview/text_art.gd:style_for` merges this over the authored run, and
## `preview/members.gd:read_prop` reads through it, so a write reads back as
## itself. Names this cannot merge are **reported and not stored**: a write that
## round-trips through a dictionary nothing paints from is the `moveableSprite`
## shape, and half the point of this table is that the boundary is somewhere.
var _member_style: Dictionary = {}
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
## Outline every sprite, brighter for the one under the cursor.
##
## **Off by default, and it used to be on.** The argument for on was that in a
## preview with no cursor art and no hotspot feedback, "nothing happens" and
## "nothing is there" look the same — which is true while you are debugging the
## hit test and false the rest of the time: every other session, and every person
## the build is handed to, gets a game with white rectangles drawn over the art.
## It is one keypress away (`[debug] boxes`), and a debug affordance that is
## opt-in is one that cannot ship by accident.
var _show_boxes := false
## The channels this movie has asked `intersects` or `within` about, and the
## overlay that outlines them. **The collision zones, which the hotspot overlay
## cannot show**, because they are not hotspots: nothing clicks them, no script is
## attached to them, and most of them are deliberately invisible. `_show_boxes`
## draws what the *mouse* can reach; this draws what the *movie* is measuring.
##
## Title-agnostic, and that is the whole design. The alternative on offer was to
## outline Piposh 1's channels 17-22 -- the shapes fencing the cannon game's
## ships -- which is a per-title mapping in engine code and exactly what
## `AGENTS.md` forbids. Recording the operands the movie's own scripts pass to
## the operators needs no table and lights up every title that uses them: the
## cannon's fences, `SHUFFLE`'s ten drop targets, `ARCADE`'s gates, the ship
## map's fourteen deck zones.
##
## Populated at the moment a script asks, not by scanning, so a zone appears the
## first time it is tested and the overlay reflects what this playthrough has
## actually consulted. Cleared with the rest of the per-movie state.
var _collision_channels: Dictionary = {}
var _show_collisions := false
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
## channel -> `the constraint of sprite N`, 0 for unconstrained. Kept beside the
## cursors and apart from `_overrides` for exactly the same reason, which
## `preview/sprite_props.gd:write` gives at length: the sprite record has no
## constraint field, so the score never writes one, so there is nothing for a
## per-field merge to merge with -- and an override would be discarded by the
## score's next member change, which is the frame the corpus's own constraint
## sites hand over to.
var _channel_constraints: Dictionary = {}
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
## not carry: `mouseUpOutSide` goes out when the button came up anywhere but
## inside this sprite (§8.1). It is also §15's hilite channel -- the reference
## keeps two fields and gates the second on `shouldHilite`, and one is enough
## here because `preview/hilite.gd:artwork` asks that question again at paint
## time, so a channel latched here that cannot hilite simply does not.
var _press_channel := 0
## §15: **was the press in *a* button** -- any button, not this one.
##
## Latched by the mouse-down block and read by the mouse-up block, where it flips
## the hilite of whatever button the release landed on. ScummVM's own comment
## says the rule makes no sense and reproduces it anyway; so does this. Nothing
## flips on the way down, and the button that flips need not be the button that
## was pressed.
##
## 0 of the 51,350 members across the three corpora is of type `button`, so this
## can never become true on any title this engine has been pointed at. It is here
## because it is one of the five things §15's block latches and the block is all
## five or none.
var _mouse_down_in_button := false
## `{"lib":, "id":}` for the member the press landed on, latched at the *start*
## of the mouse-down chain and held until the next press.
##
## §15, and it is the one piece of the click model that a handler can invalidate
## while the click is still running. The reference keeps `_currentMouseDownCastID`
## for exactly this and resolves the mouse-up's cast element against it, so a
## `mouseDown` handler that swaps the member leaves the **old** member's cast
## script answering the `mouseUp` and the swapped-in one never sees the release.
## Reading the channel again at release time would give the new member, which is
## the answer Director had already decided against.
var _press_member: Dictionary = {}
## The queued chain for the mouse message in flight, or `{}`.
##
## §6.3: Director settles the whole list of recipients before it runs the first
## one, so the list is built in `_press_click` / `_release_click` /
## `route_right_button` -- *before* `preview/interaction.gd` sends the message --
## and `_dispatch` runs it rather than resolving a tier at a time.
##
## It is latched on the node rather than passed as an argument because
## `interaction.gd` owns the call site and this file owns the click model's
## state; the two facts meet at `_dispatch`, which is the only reader.
## `{"event": <lowercased handler>, "elements": Array}`.
var _chain: Dictionary = {}
## Was the mouse button down at any point since the last score step?
##
## **`the mouseDown` cannot be answered from the live button alone**, and this is
## the field that says why. A movie's handlers run at the *score's* rate -- 4 to
## 8 steps a second across these two titles, so 125 to 250 ms between one
## `exitFrame` dispatch and the next -- while a click lasts 40 to 100 ms. Read
## `Input.is_mouse_button_pressed` from inside the handler and every click that
## begins and ends between two steps is invisible, so
##
##     on exitFrame
##       if the mouseDown then go("mainscreen")
##     end
##
## -- Director's standard click-to-skip idiom, and the only way out of the
## 449-frame opening of `rating`'s MAINMENU -- answers false for most of the
## clicks a player makes. Measured at that movie's 8 fps, driving real button
## events through `Input.parse_input_event`: a 35 ms click skipped 2 times in 8,
## a 90 ms one 7 times in 8, a 185 ms one 8 times in 8. The player's report is
## "clicking does not skip the opening", and the port looked correct in every
## harness because every harness holds the button for far longer than a hand
## does. It is not a Rating idiom either: `blaegoz` polls it on 12 frames,
## `manaegoz` and `arrivel` on one each, and piposh2's CHESS on four.
##
## So the button is sampled once per process frame -- the engine's own event
## loop, which runs an order of magnitude faster than the score -- and a press
## stays visible to the movie until a step has had the chance to see it. That is
## Director's model rather than a workaround: the press is an *event*, and a
## movie stepping eight times a second still receives every event that happened
## in between.
##
## Reset to the live button after each step (`preview/frame_loop.gd`), so one
## press is offered to exactly one step unless the button is genuinely still
## held. Both halves matter: `if the mouseDown then go(marker(1)) else
## go(marker(0))` -- the charge-and-fire idiom in `blaegoz` and `CHESS` -- fires
## once per click and keeps firing while the button is down, and a latch that
## outlived the press would make it fire twice for one.
var _mouse_down_seen := false
## Where the last input event happened, in this movie's coordinates, and whether
## one has arrived yet. `stage_mouse` has why this is kept rather than asked of
## the DisplayServer -- it is what makes the engine work on a touchscreen.
var _pointer := Vector2.ZERO
var _pointer_seen := false
## Is there an OS cursor on this machine at all?
##
## `FEATURE_MOUSE` rather than a platform name, because the question is precisely
## "is there a cursor to ask about". A phone with no mouse attached answers no.
## Headless answers no too, and that is the right answer for it: a headless
## harness's pointer is whatever it injected, and reading the developer's desktop
## cursor instead is how a check comes to pass or fail depending on where
## somebody left their mouse.
##
## A field rather than the call written inline at each site, and the reason is
## the one `_pointer_from_events` gives below: the no-cursor arm is the piece of
## the input path no run on a development machine can reach, so it needs a seam a
## harness can drive. `tools/touch_input.gd` sets this to pretend to be a desktop
## and asserts the engine still routes a finger correctly.
var _has_os_cursor := DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)
## Does the pointer come from input events, or from the OS cursor?
##
## **A fact about the last event, not about the platform**, and that is the whole
## of what changed here. It used to be `not has_feature(FEATURE_MOUSE)`, latched
## once at load — which is right on a phone with no mouse and on a desktop with
## no touchscreen, and wrong on every machine that has both. Windows laptops with
## touchscreens, Chromebooks, Android with a mouse or in DeX, an iPad with a
## trackpad: all of them report `FEATURE_MOUSE`, so the flag read false, so
## `stage_mouse()` answered from an OS cursor the finger never moved. Measured:
## a touch at stage (238,240) on this Windows box came out of `the mouseH`/`the
## mouseV` as (608,19) — wherever the cursor had been parked — and `the clickOn`
## as 0. That is the exact fault the flag was introduced to fix, alive on every
## platform that owns both input devices.
##
## Godot decides it for us and says so: the mouse events it synthesises from a
## finger carry `device == InputEvent.DEVICE_ID_EMULATION`, and a real mouse
## carries a device index of its own. So `_input` reads the seam off the event.
## A player who plugs a mouse into a tablet mid-game gets the cursor back on the
## first motion it sends, and goes back to the finger on the next tap; neither is
## a case a boot-time test can express at all.
##
## Where the platform has no cursor this stays true whatever arrives, because
## there is nothing else for `stage_mouse()` to fall back to.
var _pointer_from_events := not _has_os_cursor
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
## The save file this session last *loaded*, "" until one has been. Quick-load
## resumes it, which is what makes that key "whatever I was last working with"
## rather than "the quick slot": saving does not move it, so a quick-save while
## iterating on `beach_bug.json` does not silently switch the quick-load target.
var _last_save := ""

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
## The movie's own `DRCF` stage rect, and the rest of its config chunk.
##
## **Not a window property.** It is where this movie's stage size comes from --
## `stage_size()` -- and where its starting tempo and file version come from
## (`preview/movie_session.gd:adopt`). A window uses it for a second thing: the
## size and, through the difference against the stage movie's rect, the place.
##
## Every movie of all six titles this port was built on declares 640x480, so a
## centred window covers the stage exactly and the size looked like a constant for
## as long as nothing else was loaded. `test-games/itamar-magichat/magichat.dir`
## declares 800x600 and is the counter-example.
##
## Null when the container has no config chunk or the chunk does not parse. Every
## reader falls back rather than refusing, because a movie that cannot state its
## own size still has a score to play.
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

# --------------------------------------------- frozen Lingo (§6.1 step 18, §9.4)
#
# Director does not run the rest of a handler that called `play` or `go`. It
# stashes it and requeues it later, and the two verbs differ only in where the
# stash lives and what makes it runnable again: a `go` resumes once the frame it
# chose has been entered, a `play` resumes at `play done`.
#
# The chains are held **here rather than in the interpreter** for one reason:
# `go to movie` builds a new interpreter inside the very call that froze the
# handler, so a chain the interpreter owned would be destroyed by the statement
# that created it. Director keeps frozen states on the window across a movie
# change for the same reason, and a chain resumed after one runs the old movie's
# statements against the new movie -- which is what the reference does.

## Handlers stopped at a `go`, oldest first. The next thaw takes the last.
var _frozen_lingo: Array = []
## The one handler stopped at a `play`. Director keeps a single slot and warns
## when a second `play` clobbers it; so does this.
var _frozen_play: Array = []
## True when `enterFrame` was what froze. §6.1 bails out of the rest of the tick
## in that case, so the resume waits for the step that enters the new frame.
var _enter_frame_froze := false
## How many handlers have been parked over the whole session. The queue drains
## inside the step that filled it, so nothing sampling it between frames can tell
## "suspension is working" from "suspension never happened" -- which is a harness
## that passes over an empty set, and this repo has shipped four of those.
var _frozen_parked := 0
## How many handlers may be parked at once. ScummVM stops recursive freezing at
## depth 2 and calls 64 runaway; the number matters less than there being one,
## because past the cap the request is *declined* -- the handler runs straight
## through, exactly as it did before any of this -- rather than parked somewhere
## nothing will drain.
const MAX_FROZEN := 8


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
	# `the exitLock` needs the close request to arrive here rather than be
	# actioned before anything can refuse it, and that is a tree-wide switch. Set
	# only when this preview *is* the application: a harness adds the scene to its
	# own root, and changing how that process answers a window close would be this
	# file reaching outside the movie it is running.
	if get_tree() != null and get_tree().current_scene == self:
		get_tree().set_auto_accept_quit(false)


## `the exitLock` — the one thing it does.
##
## Director disables the quit *key* while it is set: the command `quit` still
## quits, and so does anything the engine's own operator does. Five sites set it
## and none clears it, so a title that sets it means "not by accident from here
## on"; the reference answers a close request with a confirm dialog rather than
## refusing outright, and the equivalent here is the debug layer's own quit key,
## which is deliberately not gated on this.
##
## A window is never the application, so this only ever fires on the stage.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if get_tree() == null or get_tree().current_scene != self:
		return
	if _host != null and _host.exit_lock:
		_trace("f%d close refused: the exitLock is set" % _index)
		return
	get_tree().quit()


func _ready_as_window() -> void:
	Boot.as_window(self)


func _start_lingo(path: String) -> void:
	Boot.start_lingo(self, path)


## The file version a container states, for whoever needs it *before*
## `preview/movie_session.gd` reads the config into `_config`.
##
## The score does: which convention its tempo cell is written in is a property of
## the movie and nothing in the byte says which, so `DirectorScore.parse` takes
## the version and the config has to be read first. `movie_session.adopt` reads
## the same chunk a moment later for the stage rect and the stated rate; a second
## read of one small chunk is cheaper than reordering the load around it, and
## much cheaper than a decoder that has to be told its own input's format
## afterwards.
func _stated_file_version(container) -> int:
	var config = Config.new()
	return int(config.version) if config.read(container) else 0


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
	if not _score.parse(_movie.read_chunk(vwsc[0]), _stated_file_version(_movie)):
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
	if not score.parse(next.read_chunk(vwsc[0]), _stated_file_version(next)):
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
	# The arriving movie brings its own stage rect, and Director resizes to it on
	# every load rather than only the first (`stage_size`). A title whose rooms are
	# all one size never notices; one that opens a 320x240 movie from a 640x480 one
	# would draw the small movie into the big letterbox with the old clip standing.
	_stage_resized()

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
		# The same pair every other frame entry sends, in the same order
		# (`frame_loop.gd:advance`). The arriving movie's first frame is a frame
		# entry like any other -- `score.cpp:772-779` broadcasts `prepareFrame` and
		# `:827-831` sends `enterFrame` on the update that follows `loadNextMovie`,
		# with only `_newMovieStarted` suppressing `idle` and `exitFrame` -- and
		# sending one half of the pair here is how the two came to disagree.
		var arrived: Dictionary = _frame_script(_index)
		_dispatch("prepareFrame", arrived)
		_enter_frame_or_defer(arrived)
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
	# **Editability travels with the text, for the same reason.** `SAVELOAD` is a
	# window over the stage and writes `member("save1").editable = 1` against a
	# cast the stage also has open; keyed by the cast's file (`_field_key`), the
	# two movies name the same entry, and a copy rather than a share would let one
	# of them go on believing a field is typeable after the other turned it off.
	_member_editable = other._member_editable
	_member_hilite = other._member_hilite
	_member_style = other._member_style


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


## Send one message.
##
## **A mouse message is not one message, it is a queue** (§6.3), and the queue
## was decided before `preview/interaction.gd` reached this call -- see `_chain`.
## Everything else is still one message to one script with Director's movie
## fallback behind it, which is what `preview/scripts.gd:dispatch` is.
##
## The `script` argument is ignored on the chain path. It is the tier
## `interaction.gd:script_for_click` resolved, and that function still runs --
## `the clickOn`, the snapshot record and the click log all read it -- but it
## answers "which tier is first", where the queue answers "which tiers there
## are". Taking the first tier from one and the rest from the other is how the
## two would come to disagree.
func _dispatch(handler: String, script: Dictionary) -> void:
	if str(_chain.get("event", "")) == handler.to_lower():
		EventChain.run(self, _interpreter, handler, _chain["elements"])
		return
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
## **`the keyCode` and `the key` are the *last key pressed*, and they persist.**
## They are engine state, not dispatch state: ScummVM sets `_vm->_key` and
## `_vm->_keyCode` in `events.cpp:337-338` when the key goes down and never
## clears them, and `lingo-the.cpp:680-689` reads that same pair whenever a
## script asks. Nothing scopes them to the handler.
##
## This port used to clear both to `-1` / `""` the moment the dispatch returned,
## on the reasoning that a script reading them outside a key event "should see
## nothing". That reasoning is wrong and it is the whole of a reported bug:
## Rating's `BATZEGOZ.dir` -- the *Aderet* frames -- does
##
##     on exitFrame
##       if (the key = "h") or (the keyCode = 4) then
##         sound playFile 1, soundspath & "h.aif"
##         go("f1")
##       end if
##     end
##
## in three frame scripts (members 6, 7, 8 and 81, for H, J and Q). Polling the
## keyboard from `exitFrame` or `idle` is a documented Director idiom -- §8.6
## says so in as many words -- and against a value cleared on the way out of
## `_dispatch_key` it can never once be true. The keys reached the engine, the
## engine forgot them before the frame that asks ran, and the room did nothing.
##
## `-1` and `""` survive as the *never pressed yet* value (`preview_lingo_host.gd`
## initialises them), which is a deliberate divergence from ScummVM's `0`: 0 is
## the Mac code for `A`, and Rating tests `the keyCode = 0` at 17 sites, so a
## port that starts at 0 has the `A` key held down before the player touches the
## keyboard.
##
## **§8.3: with a focused editable field the message starts at that sprite, not
## at the frame** — "dispatched with the channel id of the sprite owning the
## active widget, not the sprite under the mouse", and channel 0 (the frame) only
## when nothing has focus. That is the one route by which a keypress reaches a
## sprite script at all.
##
## Then the widget itself, and only if no sprite-level handler answered. Director
## suppresses the character when a `keyDown` handler does not `pass`, which is
## the documented idiom for validating typed input. What is deliberately *not*
## allowed to suppress it is `the keyDownScript`: it is a tier-1 primary handler
## and those pass by default (§8.2), and this port's `claimed` from one is not
## evidence the movie wanted the key anyway — `fromnow` is installed by 46
## scripts, acts on key code 49 alone and reports every other key as claimed.
## `preview/input_router.gd` had to reach the same conclusion for the F-keys, and
## a widget that believed `claimed` would be untypeable in most of this game.
##
## **§8.2's default was inverted here, and that is the second half of this
## function's history.** A primary handler — `the keyDownScript`, `the
## keyUpScript`, `when keyDown then` — *passes the event on by default* and has
## to call `dontPassEvent` to stop it, while every other tier consumes by default
## and has to call `pass` to continue. The reference queues the whole chain with
## `passByDefault` true for the primary element and false for the rest
## (`lingo-events.cpp:486-490`), sets `_passEvent` to that default before each
## element runs (`:763`), and skips the next element only when the previous one
## *found a script* and left the flag false (`:756`). This port had the primary
## handler on the consuming side of an `if`/`else`, so while a `keyDownScript`
## was installed — which is 46 scripts of Piposh 2, 97 of Rating and 116 of
## Piposh 1 — `keyDown` never reached a sprite, frame or movie script at all.
##
## Unexercised in Piposh 2, which declares no `on keyDown`; **not** unexercised
## in the corpus: Piposh 1, its English and its Russian build declare 16 each and
## call `dontPassEvent` 42-44 times, and Rating calls it 9 times. A
## `dontPassEvent` is a statement about a chain that continues, so the calls are
## the evidence the chain was wrong even where nothing observable changed.
## `preview_lingo_host.gd:pass_event` is the flag; the two statements that write
## it were bound inert until this landed.
func _dispatch_key(event: InputEventKey) -> bool:
	if not _lingo_on or _interpreter == null or _host == null:
		return false
	_host.key_code = Keys.code_for(event)
	_host.key_char = Keys.char_for(event)
	# The timeout clock's keyboard half (§3). `events.cpp:371` stamps
	# `_lastTimeOut` from the key-DOWN arm and from nowhere else -- there is no
	# key-up stamp -- so a movie held open by a key repeat stays "present" and one
	# whose player merely releases a key does not become present again.
	if _host.timeout_key_down:
		_host.reset_timeout()
	var claimed := _dispatch_key_event("keyDown", _host.key_down_compiled)
	# The widget last, and only if no sprite-level handler answered. The focus
	# arbitration inside `_dispatch_key_event` has already run, so focus is
	# current for the key being delivered rather than for the frame before it.
	if not _typed_away and TextFocus.key(self, event):
		claimed = true
	# Nothing is cleared here. See the note above: `the key` and `the keyCode`
	# hold the last key pressed until the next one, which is what every script
	# that polls them from `exitFrame` or `idle` is reading.
	queue_redraw()
	return claimed


## The release. `the keyUpScript` and `on keyUp`, §8.1 and §8.2, and the exact
## mirror of the press bar three things.
##
## **`the key` and `the keyCode` are not touched.** The reference's `EVENT_KEYUP`
## arm sets `_keyFlags` and dispatches, and nothing else (`events.cpp:378-381`);
## only `EVENT_KEYDOWN` writes the pair. So a `keyUp` handler asking `the keyCode`
## reads the key that went *down*, which is exactly what makes Rating's
## `normalkeysx` work — it is a `keyUpScript` whose whole body tests
## `the keyCode = 109`.
##
## **No widget arm.** Typing happens on the press; a release that reached
## `TextFocus.key` would type every character twice.
##
## **No debug binding arm** — `preview/input_router.gd` offers the release to the
## movie only. A preview command that also ran on the release would toggle itself
## back on every press.
##
## **Measured, and it is not this title's need.** `tools/key_script_survey.gd --
## --all`: `the keyUpScript` is set at 195 sites in Piposh Dream and 10 in
## Rating, and at 0 in Piposh 2 — the title this port was built on, which is why
## the whole release half was missing. `ARCADE1.dir` member 20's
## `set the keyUpScript to "normalkeysx"` is the handler that leaves a timed
## scene, so those rooms had no key exit however free F10 was made.
func _dispatch_key_up(event: InputEventKey) -> bool:
	if not _lingo_on or _interpreter == null or _host == null:
		return false
	# The event carries the key that was released; it is deliberately not stored.
	# Named rather than `_` so the signature says what a caller must hand over.
	var _released := event
	var claimed := _dispatch_key_event("keyUp", _host.key_up_compiled)
	queue_redraw()
	return claimed


## Whether the last key event was consumed by a *sprite-level* handler, which is
## Director's "handled, do not type it". Set by `_dispatch_key_event` and read by
## `_dispatch_key` on the line after, rather than returned, because the return
## value answers a different question — whether any script took the key at all,
## which a `keyDownScript` says yes to for every key it ignores.
var _typed_away := false


## One key event down §8.2's chain: primary handler, then sprite, cast, frame and
## movie scripts, with the pass flag deciding whether the second half runs.
##
## Shared by the press and the release because Director's queue is: the reference
## builds both from the same `case kEventKeyUp: case kEventKeyDown:` arms, with
## the same primary-handler push and the same fall-through to
## sprite → cast → frame → movie.
##
## `primary` is what `the keyDownScript` / `the keyUpScript` compiled to on
## assignment — Director's value is a string of Lingo and this port now compiles
## it as one (`preview_lingo_host.gd:_compile_primary`). Passed in rather than
## read off `_host` here so that the press and the release name their own
## property at the one call site each.
func _dispatch_key_event(handler: String, primary: Dictionary) -> bool:
	var event_key := handler.to_lower()
	_typed_away = false
	# §8.3: the focused sprite, or the frame when nothing holds focus. A sprite
	# script is reachable by a key event only through this line. Arbitrated before
	# anything runs, so a handler that changes focus does not redirect its own
	# event.
	var focus_channel: int = TextFocus.arbitrate(self)

	# ------------------------------------------------------- tier 1, pass by default
	# A primary handler installed by `when keyDown then` runs ahead of everything,
	# which is where Director puts it. `strtgame`'s `gomenu` is nothing but one of
	# these, so without it the intro has no way out. Typed explicitly:
	# `_interpreter` is untyped, so `:=` has nothing to infer the return type from
	# and the file will not compile.
	var claimed := false
	var pass_on := true
	_host.pass_event = true
	var fired: bool = _interpreter.run_primary(event_key)
	if fired:
		_tally(_ran, "when %s" % handler)
		claimed = true
		pass_on = bool(_host.pass_event)
	# Reset per element, not once per event: two primary handlers both pass by
	# default, and the second must not inherit the first's `dontPassEvent`. It is
	# set unconditionally rather than inside the `if`, which is the second of
	# ENGINE_TODO's two event-chain residues: a `when keyDown then dontPassEvent`
	# followed by a `keyDownScript` used to leave the flag false through the
	# second element, so the second primary handler ran with the first's verdict
	# still standing. Nothing in either corpus installs both at once.
	_host.pass_event = true
	if EventChain.run_primary_script(self, _interpreter, primary, "%sScript" % handler):
		claimed = true
		pass_on = bool(_host.pass_event)

	# ------------------------------------------- the rest, consuming by default
	# Reached unless a primary handler said `dontPassEvent`. This is the arm the
	# inverted default cut off entirely.
	if pass_on:
		var owner: Dictionary = _sprite_script(focus_channel, _index) \
			if focus_channel > 0 else {}
		_typed_away = not owner.is_empty() \
			and bool(_interpreter.call("_script_has_handler", owner, event_key))
		if _typed_away:
			_tally(_sent, "%s:ch%d" % [handler, focus_channel])
		# A sprite-level handler that ran is Director's "handled, do not type it"
		# -- the documented way a field validates its own input. With no focused
		# sprite the message starts at the frame script and carries on to the
		# movie scripts.
		#
		# **The same queue the mouse uses** (§6.3): the reference builds a key
		# event's chain from the same `case kEventKeyUp: case kEventKeyDown:` arm
		# that falls through to sprite -> cast -> frame -> movie, so a keypress
		# reaching a focused field gets the member's cast script too, and a
		# handler that says `pass` below the primary tier is honoured here as
		# well. It used to stop at the first script that answered, so a frame
		# script's `pass` never reached a movie script.
		#
		# The flag starts at true because `pass_on` is the primary tier's verdict
		# and it has already been taken; `EventChain.run` sets each element's own
		# default from there.
		_host.pass_event = true
		EventChain.run(self, _interpreter, handler,
			EventChain.build(self, focus_channel, EventChain.member_on(self, focus_channel)))
		claimed = claimed or _typed_away
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
	# The report is ours, not the player's: a shipped build must not dump the
	# dispatch tallies and the interpreter's errors on the way out.
	if _lingo_on and DebugKeys.enabled():
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
func _wants_trails() -> bool:
	return Trails.wanted(frame_sprites(), _overrides)


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


## **How big this movie's stage is.** The one answer, asked by the letterbox, the
## clip rect, the stage fill, the trail layer, the SKIP control, the HUD, the
## toast and every window that has to place itself against the stage.
##
## Read from the movie's own config chunk rather than assumed, because that is
## where Director keeps it: `Cast::loadConfig` decodes the rect and
## `Movie::loadArchive` resizes the stage window to it on **every** movie load,
## not only the first. `MovieSession.adopt` reads the chunk for every container
## this port opens, so the answer follows a `go to movie` the same way.
##
## Falls back to `STAGE` for a container with no config, or one whose config does
## not parse -- `DirectorConfig.read` answers false for both, and `_config` is
## null. A movie that cannot say how big it is still opens.
##
## Deliberately derived rather than cached in a field: the two callers that can
## change it (`_load_container` and `lingo_go_movie`, both through
## `MovieSession.adopt`) would each have to remember to refresh a cache, and a
## stale stage size is invisible until a title with two differently-sized movies
## turns up. Nothing here is hot -- it is a handful of reads per paint.
func stage_size() -> Vector2i:
	if _config != null and _config.rect.size.x > 0 and _config.rect.size.y > 0:
		return _config.rect.size
	return STAGE


## Floating skip control, in stage coordinates so it scales and letterboxes with
## everything else rather than drifting when the window is resized.
##
## Anchored to the stage's own top-right, which is why this is a function and no
## longer a `const`: a const could only be written against one stage width, and
## the one it was written against was 640.
func skip_rect() -> Rect2:
	return Rect2(float(stage_size().x) - 62.0, 8.0, 54.0, 22.0)


## The movie now playing may state a different stage size from the one that left.
##
## `Movie::loadArchive` resizes the stage window to the new movie's rect on every
## load -- "For the stage, always resize to the movie rect" -- so the letterbox is
## recomputed here rather than only at boot. A window re-places itself instead:
## its geometry is in *stage* coordinates and `_apply_window_geometry` is what
## owns it (`preview/boot.gd` on why a window must not fit itself to the OS
## window).
func _stage_resized() -> void:
	if _window_key == "":
		_fit_to_window()
	else:
		_apply_window_geometry()
	queue_redraw()


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
##
## The stage's size is the movie's, not a constant -- see `stage_size()`. Every
## line below used to name a hardcoded 640x480, which fits an 800x600 movie into
## a 640x480 letterbox and then draws 800x600 of artwork through it: the movie is
## both too big for its own box and clipped at the wrong edge, and there is no
## point in the picture where the two errors cancel.
func _fit_to_window() -> void:
	var canvas := get_viewport_rect().size
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		return
	var stage := Vector2(stage_size())
	if stage.x <= 0.0 or stage.y <= 0.0:
		return
	if _aspect == "stretch_fill":
		scale = Vector2(canvas.x / stage.x, canvas.y / stage.y)
		position = Vector2.ZERO
		return
	var area := canvas
	match _aspect:
		"wide_16_9":
			area = _letterbox(canvas, 16.0 / 9.0)
		"ultra_21_9":
			area = _letterbox(canvas, 21.0 / 9.0)
	var factor := minf(area.x / stage.x, area.y / stage.y)
	scale = Vector2(factor, factor)
	position = ((canvas - stage * factor) * 0.5).floor()
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
	# `quit` and `halt` stop the movie (§1.4). The reference sets the score's play
	# state and lets the projector's loop fall out of the bottom; here the loop is
	# `_process` and this is where it falls out. A Movie-In-A-Window that quits
	# stops itself and leaves the stage running, which is what a window is.
	if _host != null and _host.stopped:
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
	FrameLoop.tick(self, _fast_forward_delta(delta))


## The fast-forward toggle's rate, in frames per second; 0 when it is off.
## `preview/input_router.gd` flips it, `preview/debug_keys.gd` reads the number
## out of `director_game.cfg`, and the line above is the whole of its effect.
var _fast_forward_fps := 0.0


## Real seconds in, *score* seconds out.
##
## **Why the delta and not the clock's `fps`.** The rate has exactly one carrier
## and it is `director/director_frame_clock.gd:fps`, which every frame carrying a
## tempo cell overwrites (`_take_rate`). Forcing 60 into it would survive until
## the next tempo cell and no longer, so the fast-forward would switch itself off
## somewhere in the middle of a movie and look like a bug in the toggle. Scaling
## the time the clock is *told about* leaves the score's own rate intact and is
## exact: the clock steps once per `1/fps` of the seconds it is handed, so
## handing it `target/fps` times as many makes it step `target` times a second
## whatever the score asked for.
##
## It scales the holds with it, and that is wanted rather than tolerated: a
## `delay` and a transition are both counted down in `tick` off the same delta,
## and a fast-forward that ran the frames faster but still sat out every
## two-second tempo delay would barely be faster at all -- this corpus spends
## 74 s in tempo delays across thirty-six frames. Sound is the exception and
## cannot be otherwise: the mixer runs on the audio server's clock, so a
## `soundBusy` wait still takes as long as the sound does.
##
## `director_frame_clock.gd:MAX_CATCHUP_STEPS` caps one tick at four score steps,
## so the ceiling is four times the engine's own frame rate however high the
## configured number is. That is a real limit and not worth removing here: the
## clock is another agent's file this week, and 60 fps against a 60 Hz process
## loop is one step per tick.
func _fast_forward_delta(delta: float) -> float:
	if _fast_forward_fps <= 0.0:
		return delta
	var rate := float(_clock.fps)
	if rate <= 0.0:
		return delta
	return delta * (_fast_forward_fps / rate)


func _sync_frame_entry() -> void:
	FrameLoop.sync_frame_entry(self)


func _begin_transition(frame: Dictionary) -> bool:
	return FrameLoop.begin_transition(self, frame, _table)


func _advance() -> Dictionary:
	# Director's `pause`: a step does not begin on a movie that is already paused —
	# no `exitFrame`, no playhead move, no `prepareFrame`, no `enterFrame`.
	#
	# **This guard is not the whole of it, and believing it was is `bugs.md` 52.**
	# `pause` is called from inside an `exitFrame` handler, so on the step that
	# pauses this test has already passed; the reading that keeps the playhead on
	# the frame that paused is the second one, in `frame_loop.gd:advance`, between
	# the `exitFrame` dispatch and the playhead move, where `updateCurrentFrame`
	# has it (`reference/scummvm/score.cpp:443-452`).
	#
	# Deliberately *not* in `_process`: a paused movie in Director stays drawn,
	# keeps its rollover current and keeps taking clicks -- which is the only way
	# the frames that pause (`mainmenu.dir` 92, `hezsave.dir` 8) are ever left.
	# `_paused`, the debug key's flag, is the other thing entirely and stops the
	# tick outright.
	if _host != null and _host.playback_paused:
		return {"exited": -1, "frame": _index}
	_enter_frame_froze = false
	var stepped: Dictionary = FrameLoop.advance(self)
	# §6.1 step 18. The step has entered its frame, run `prepareFrame` and
	# `enterFrame`, and drawn; whatever a `go` earlier in it froze is now runnable,
	# because the frame that `go` chose is the one on screen. An `exitFrame`
	# handler that ends `go("b") / <more>` therefore runs `<more>` on b, which is
	# the whole point.
	#
	# The exception is `enterFrame` itself: the reference bails out of the rest of
	# the tick when *that* freezes, because the frame its `go` chose has not been
	# entered yet. Resuming here would run the tail against the frame the handler
	# was already leaving.
	if not _enter_frame_froze:
		_thaw_lingo()
	return stepped


## Whether another handler may be parked (§6.1 step 18).
##
## No is not a failure: a declined freeze runs the handler straight through, the
## way every one of them ran before this existed. Yes to a `play` always, because
## Director's play slot is a single buffer that a second `play` overwrites --
## clobbering it is the reference's own behaviour and it warns rather than
## refusing.
func lingo_accepts_freeze(kind: String) -> bool:
	if kind == "play":
		return true
	if _frozen_lingo.size() >= MAX_FROZEN:
		_trace("freeze declined: %d handlers already parked" % _frozen_lingo.size())
		return false
	return true


## Take a suspended handler off the interpreter.
func lingo_park_state(chain: Array, kind: String) -> void:
	_frozen_parked += 1
	if kind == "play":
		if not _frozen_play.is_empty():
			# The reference warns here too, and it is worth a trace line rather
			# than a silent overwrite: it means a second `play` started before the
			# first one's `play done`, and the first handler's tail is now lost.
			_trace("play froze over a handler still parked")
		_frozen_play = chain
		return
	_frozen_lingo.append(chain)


## Run whatever is waiting, newest first, until one freezes again.
##
## Stopping at the first re-freeze is not an optimisation. A handler ending in
## `go` freezes, is resumed, and freezes again — so a loop that kept going would
## run a room's whole hold cycle inside one step, at whatever rate the CPU
## allows, and the score would stop pacing anything.
func _thaw_lingo() -> void:
	if _interpreter == null:
		return
	for _i in MAX_FROZEN + 1:
		if _frozen_lingo.is_empty():
			return
		var before := _frozen_lingo.size()
		_interpreter.resume_chain(_frozen_lingo.pop_back())
		if _frozen_lingo.size() >= before:
			return


## Send `enterFrame`, or owe it until the frame has finished arriving.
##
## §6.2 plays a transition inside the render step, which sits between
## `prepareFrame` and `enterFrame`. A handler that runs on entry must not run
## while the frame it is about to touch is still wiping in — that is the whole
## difference between "set the room up once it is visible" and "set it up over
## the top of the room being left". Every path that enters a frame goes through
## here: the step loop, the first frame of a movie, and a `go to movie`.
func _enter_frame_or_defer(script: Dictionary) -> void:
	# The step has entered a frame, so the `exitFrame` owed for it has not been sent
	# yet. `score.cpp:827-828` clears the same flag in the same place, and it is
	# cleared *before* the transition check rather than after: a frame that defers
	# its `enterFrame` has still been entered, and it is the entry that makes the
	# next `exitFrame` due.
	_exit_frame_called = false
	if _clock.holding_transition():
		_pending_enter = script
		return
	var parked := _frozen_lingo.size()
	_dispatch("enterFrame", script)
	# Recorded rather than acted on, because the decision belongs to the step and
	# this is called from inside one. §6.1: a freeze here ends the tick, so the
	# handler waits for the step that enters the frame its `go` chose.
	_enter_frame_froze = _frozen_lingo.size() > parked


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
		# **Who owns the pointer, decided per event rather than per platform.**
		# Godot stamps `DEVICE_ID_EMULATION` on the mouse events it synthesises
		# from a finger, so the event itself says whether the OS cursor followed
		# it. See `_pointer_from_events` for what a boot-time platform test got
		# wrong and on which machines.
		_pointer_from_events = not _has_os_cursor \
			or event.device == InputEvent.DEVICE_ID_EMULATION
		note_pointer(at)
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			# **Where the pointer now is, before the button is routed anywhere.**
			# `Movie::processSysEvent` recomputes `_currentHoveredSpriteId` and
			# `_lastMousePos` from the event's own position at the *top* of the
			# function, ahead of the switch — so a button event re-aims the
			# pointer exactly as a move does, and only then dispatches.
			#
			# On a desktop this costs nothing: the motion that carried the mouse
			# to the button already did it, so nothing changes and no crossing is
			# raised. A finger sends no motion at all, so without this a tap
			# dispatched `mouseDown` with the *previous* gesture's rollover still
			# latched — `the mouseH` naming the new point and `the rollOver`
			# naming the old one, inside one handler. Measured on `SAVELOAD.dir`
			# frame 5: a mouse arriving at a point over channel 5 pressed with
			# `the rollOver` = 5; a finger tapping the same point pressed with
			# `the rollOver` = 4, the channel it had last touched.
			InputRouter.aim_pointer(self, at)
			if button.button_index == MOUSE_BUTTON_LEFT:
				# An empty rect contains no point, so a build with the debug layer
				# off has no SKIP hotspot either — the control is not drawn and the
				# corner it used to occupy goes back to the movie. Passed rather
				# than tested inside the router, because the router's job is where
				# a click goes and this is whether the affordance exists.
				InputRouter.mouse_button(self, button, at,
					skip_rect() if DebugKeys.enabled() else Rect2())
			elif button.button_index == MOUSE_BUTTON_RIGHT:
				InputRouter.right_mouse_button(self, button, at)
			return
		# §8.4: the widget sees the motion before the movie does, for the same
		# reason it sees the press first — a field with no script is not a hit
		# target and the descent below would never reach it. It does not consume
		# the event either: a moveable sprite (§7.6) is dragged with the same
		# button, and `TextFocus.drag` declines every motion that is not
		# extending a selection it started.
		TextFocus.drag(self, at)
		InputRouter.mouse_motion(self, at)
		return
	if not (event is InputEventKey):
		return
	# **The release is an event too** (§8.1: `keyUp`, D4). This line used to read
	# `and event.pressed`, so every key-up in the engine was dropped one call
	# before the router and `the keyUpScript` could not have worked whatever else
	# was built -- 205 sites across the corpus set one. The router decides what
	# the two halves reach; a release is offered to the movie and never to the
	# preview's own bindings.
	InputRouter.key_event(self, event as InputEventKey)


## Arm the clip rectangle. Re-armed from `_draw` every paint rather than at
## startup: the flag does not survive the command-list clear that precedes each
## paint. See `preview/stage_paint.gd`.
func _clip_to_stage() -> void:
	_clip_rect = StagePaint.clip_to_stage(self, stage_size())


## Godot's own entry into the paint below. It clears the command list before it
## notifies, so this adds nothing to `_paint`.
func _draw() -> void:
	_paint()


## Repaint the stage **now**, from inside whatever is running, and present it.
##
## Director's `updateStage` (§9.1) redraws inside the call and returns, which is
## what makes a `repeat` loop that moves a sprite and calls it animate rather
## than teleport. Godot has no way to deliver a `NOTIFICATION_DRAW` on demand --
## `queue_redraw()` pushes the redraw callback onto the message queue and
## GDScript cannot flush it -- so this does what that callback does instead:
## clear the canvas item's command list, run the same `_paint` over it, and ask
## the server to render and swap. `director/director_paint.gd` is what makes the
## second half of that legal outside `_draw`, and it is why there is one painter
## rather than two.
##
## `force_draw()` is the present, and it is a real one: a probe that appended a
## green rectangle from a script and called it read the green back out of the
## viewport texture in the same call, with the node's `draw` count unmoved. That
## is the measurement the old "Godot cannot present synchronously" note was
## missing -- `queue_redraw()` *followed by* `force_draw()` does nothing, because
## the commands never change, and that is the only thing the earlier measurement
## established.
##
## Returns whether it painted, so a caller can be asserted against.
func repaint_now() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	# `the updateLock` -- the other half of this pair (§3). While it is set the
	# stage is not repainted **and the paint is not queued for later**: the canvas
	# item keeps the commands it already holds, so the screen freezes on the last
	# frame drawn rather than going blank or catching up in a burst when the lock
	# clears. A lock that queued would make the first `updateStage` after it
	# present a stale frame, which is the opposite of what `updateStage` is for.
	if _host != null and _host.update_lock:
		return false
	_repaints += 1
	RenderingServer.canvas_item_clear(get_canvas_item())
	_paint()
	RenderingServer.force_draw()
	return true


## Ask Godot to repaint at the end of the process frame -- unless `the
## updateLock` says not to.
##
## The frame loop's own repaint, and the second of the two things `the
## updateLock` gates. Separate from `repaint_now` because they are different
## requests: that one paints inside the call, this one marks the canvas dirty and
## lets Godot paint when it next would. Both have to honour the lock or a movie
## that sets it still sees the score's own frames arrive.
##
## Everything else in this node calls `queue_redraw()` directly and should:
## a window resize, a debug overlay and a palette change are the engine's
## repaints, not the movie's, and Director's lock is over the movie's.
func stage_redraw() -> void:
	if _host != null and _host.update_lock:
		return
	queue_redraw()


## One paint of the stage, delegated to `preview/stage_paint.gd`.
##
## Reached from Godot's `_draw` and from `repaint_now`, and it may not know
## which: everything it draws goes through `director/director_paint.gd`, which
## issues commands to this node's canvas item rather than through
## `CanvasItem.draw_*` -- those assert `drawing`, which is raised only inside
## `NOTIFICATION_DRAW`.
func _paint() -> void:
	_clip_to_stage()
	# The stage colour, which is what every non-trails repaint fills with. Over
	# the movie's own rect only: the chrome around a window is painted by
	# `_draw_window_chrome` and is not part of the movie.
	Paint.rect(self,
		Rect2(Vector2.ZERO,
			window_size() if _window_key != "" else Vector2(stage_size())),
		Color.BLACK, true)
	if _window_key != "":
		_draw_window_chrome()
	if _status != "":
		Paint.text(self, ThemeDB.fallback_font, Vector2(16, 32), _status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.RED)
		return
	if _score == null:
		return

	# Rebuilt from scratch each paint rather than accumulated: it is a record of
	# what is on the stage now, and a field that left the frame must stop being
	# in it or a harness would assert against a channel that is no longer drawn.
	_text_drawn.clear()
	# §8.4: the movie's selection is pushed into the widget of any editable text
	# sprite **every frame**, so focus is re-arbitrated as part of resolving the
	# frame rather than on a frame-change signal. Doing it here is also what makes
	# a paused harness and a running player agree without a second code path --
	# several harnesses set `_index` directly and never tick.
	TextFocus.arbitrate(self)
	var frame: Dictionary = _score.frame(_index)
	var stage := stage_size()
	StagePaint.paint_frame(self, _table, stage)
	# A caret blinks, and a preview holding on `go to the frame` repaints only
	# when asked. Same reason `Toast.draw` asks below, and the ask is confined to
	# the frames that actually have a focused widget on them.
	if _focus_channel > 0:
		queue_redraw()
	# Everything below this line exists for us and not for the movie, so it is all
	# behind the one switch (`preview/debug_keys.gd:enabled`). A shipped build
	# draws the movie and nothing else: no outlines over the artwork, no SKIP
	# button, no HUD, no toast, no picker.
	if not DebugKeys.enabled():
		return
	if _show_boxes:
		_draw_hotspots()
	if _show_collisions:
		_draw_collision_zones()
	if _window_key != "":
		return
	StagePaint.draw_overlays(self, frame, stage, skip_rect())
	# A paused preview does not repaint on its own, so a toast that needs a paint
	# to disappear would stay up until something else asked for one.
	if Toast.draw(self, _toast, _toast_until, stage):
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
	var channel := int(sprite["channel"])
	_text_drawn[channel] = TextArt.paint(
		self, sprite, m, _stage_rect(sprite), _field_text_of(m),
		TextFocus.editable(self, sprite, m), TextFocus.paint_state(self, channel))
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
	return Interaction.channel_at(self, at, frame_sprites(), _hit_pixels, _table)


func _responds_to_mouse(sprite: Dictionary) -> bool:
	return Interaction.responds_to_mouse(self, sprite, _table)


## Which eligibility clause makes this sprite answer the mouse, or `""`.
##
## The reason rather than the boolean above, because "why is this clickable" is
## the question a reader actually has and `responds_to_mouse` is the same
## function with the answer thrown away (`preview/interaction.gd:129`).
##
## Here because nothing on the node answered it. `tools/channel_report.gd` asks
## for it by name and falls back to the boolean when the node does not, so the
## tool has been printing "yes" where it meant to print the clause -- and
## `tools/preview_surface.gd` reports the name as moved, which is the one thing
## that file exists to catch. Unrelated to what the rest of this commit is about.
func _eligibility_reason(sprite: Dictionary) -> String:
	return Interaction.eligibility_reason(self, sprite, _table)


func _declares_mouse_handler(script: Dictionary) -> bool:
	return Interaction.declares_mouse_handler(script, _interpreter)


func _draw_hotspots() -> void:
	Interaction.draw_hotspots(self, _hover_channel, _hit_pixels, _table)


## Outline every channel the movie has measured with `intersects` or `within`.
##
## Drawn through `lingo_sprite_rect`, so what appears is the rect the *operator*
## sees rather than a second opinion about it. That is the point: if a zone is
## outlined somewhere the artwork is not, the operator and the picture disagree
## and the overlay has found the bug rather than illustrated the geometry.
##
## Hidden channels are included, and are most of what this is for -- a collision
## zone is usually an invisible shape, and the cannon game's shell probe is a
## hidden 1x1 dot. An empty channel is skipped: it has no rect and outlining the
## origin would draw a dot in the corner for every channel the score has emptied.
func _draw_collision_zones() -> void:
	for channel in _collision_channels:
		var rect: Rect2 = lingo_sprite_rect(int(channel))
		if rect.size == Vector2.ZERO:
			continue
		Paint.rect(self, rect, Color(1.0, 0.15, 0.15, 0.9), false, 1.0)


## A mouse-down over a moveable sprite starts a drag: Director records the
## channel and the offset from the click to the sprite's position, then follows
## the cursor until mouse-up or until the sprite stops being moveable.
##
## Called from `Interaction.latch_press`, which is §15's mouse-down block, rather
## than from `route_press` where it used to sit -- the reference latches the drag
## in that block along with the hilite, the button flag and the member, and it
## runs the block for the right button too. `channel` comes from the block's own
## descent instead of a second one here.
func _begin_drag(at: Vector2, channel: int) -> void:
	var started: Array = Interaction.begin_drag(
		self, at, channel, frame_sprites())
	if started.is_empty():
		# Not moveable: the reference clears the pair rather than leaving them, so
		# a press on a fixed sprite ends whatever the last press started.
		_drag_channel = 0
		_drag_offset = Vector2.ZERO
		return
	_drag_channel = int(started[0])
	_drag_offset = started[1]


## The two halves of a click, delegated to `preview/interaction.gd`. They used to
## be one `_click` that dispatched `mouseDown` and `mouseUp` back to back on the
## press; the module's `press` doc comment has why that broke every drop.
##
## **The chain is built here, before the message goes out**, which is the whole
## of §6.3's "Director decides the recipients before it runs any of them":
## `press` runs the primary handler and dispatches in the same call, and the
## queue has to exist before either — a `mouseDown` handler that swaps the member
## under the pointer must not be able to change what the rest of its own chain
## resolves to. The descent that answers "which channel" happens **once**, in the
## latch block below; it used to happen a second time inside `press`, which was
## one hit test per press paying for the ordering and is now free.
##
## §15's **latch block runs before the chain is built**, which is the reference's
## own ordering -- "run these steps at the very beginning, i.e. before the first
## source type". It is also what supplies `_press_channel` and `_press_member` to
## the two lines below, so the descent happens once.
##
## `right` carries `rightMouseDown`/`rightMouseUp` through the same path (§8.1,
## D5). One function rather than two, because the entry this closes is explicit
## that the right button latches all five things or none: a second copy of the
## click model with a subset of them is exactly the shape it refuses.
func _press_click(at: Vector2, right := false) -> void:
	# The timeout clock's mouse half (§3), stamped where the reference stamps it
	# (`events.cpp:270`): on the press, for both buttons, before anything is
	# dispatched. A release does not stamp it and neither does a move -- Director
	# counts *clicks* as presence, which is why `the lastRoll` is a separate fact.
	if _host != null and _host.timeout_mouse:
		_host.reset_timeout()
	Interaction.latch_press(self, at, _channel_at(at))
	_chain = {
		"event": "rightmousedown" if right else "mousedown",
		"elements": EventChain.build(self, _press_channel, _press_member),
	}
	# §8.2: the primary element's default. `Interaction.press` runs
	# `when mouseDown then` and `the mouseDownScript` before it dispatches, and
	# `EventChain.run` reads what they left behind -- so the flag has to start at
	# the primary tier's default rather than at whatever the last event left.
	if _host != null:
		_host.pass_event = true
	Interaction.press(self, at, right)
	_chain = {}


## The release, and **the chain is built from the sprite under it** (§15).
##
## That is the half of `the clickOn`-on-mouse-up that the port was missing: the
## reference rewrites the property from `getMouseSpriteIDFromPos` at the release
## *and* delivers the message to that sprite, and one without the other makes a
## single dispatch give two answers to which sprite it is about.
## `interaction.gd:release` carries the corpus measurement.
##
## `_press_member` is still §15's other half and is deliberately *not* re-read:
## the cast element resolves against the member the mouse-DOWN chain started on,
## so a `mouseDown` handler that swaps the member leaves the old one answering.
func _release_click(at: Vector2, right := false) -> void:
	var under: int = _channel_at(at)
	_chain = {
		"event": "rightmouseup" if right else "mouseup",
		"elements": EventChain.build(self, under, _press_member),
	}
	if _host != null:
		_host.pass_event = true
	Interaction.release(self, at, under, right)
	_chain = {}


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
	_rollover_channel = Interaction.rollover_channel(self, at, frame_sprites())
	Interaction.hover_changed(self, was, _rollover_channel)


## `rightMouseDown` / `rightMouseUp`, delegated to `preview/interaction.gd`.
##
## Queued exactly like the left button, because §6.3 puts `rightMouseDown` and
## `rightMouseUp` in the same list and sends them down the same five tiers.
##
## **And latched exactly like the left button**, which is what changed. §15's
## mouse-down block runs at the primary tier for `rightMouseDown` as it does for
## `mouseDown`, and it latches five things in one go: the empty-stage beep, the
## hilite channel, "the press was in a button", the drag channel and grab offset,
## and the cast id the mouse-up resolves against. `the clickOn` is written by the
## right pair too. This used to do none of it, on the recorded grounds that the
## five go in together or not at all -- they are in together now, through the
## same `_press_click` / `_release_click` the left button uses.
##
## §9.2's wait-for-click goes with them, in the body below: the reference clears
## `_waitForClick` in the arm it shares between `EVENT_LBUTTONDOWN` and
## `EVENT_RBUTTONDOWN`, because a frame waits for *a* click and not for a
## particular one.
##
## What is still the left button's alone: §11's palette-cycle abort in
## `route_press`, which the reference does not do from either arm and this port
## does from one — a divergence that predates this and is not made worse by
## leaving it where it is — and `the mouseDownScript` / `the mouseUpScript`,
## which Director files under the left events and gives the right button no
## property to install.
##
## 0 `rightMouseDown` or `rightMouseUp` handlers exist in any of the six titles,
## so all of this is unexercised: built because Director has it.
func route_right_button(at: Vector2, pressed: bool) -> void:
	if pressed:
		# §9.2: a wait-for-click is released by the mouse-DOWN, and the reference
		# clears it on `EVENT_RBUTTONDOWN` in the same arm as the left button --
		# the frame is waiting for a click and not for a particular one. Without
		# this the right button was the one press in the engine a waiting frame
		# ignored, which reads as the movie having stopped.
		if _saw_press:
			_clock.clicked()
		_press_click(at, true)
	else:
		_release_click(at, true)


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
## Deliberately blunt: it cuts the voice, drops whatever the frame is waiting on
## and moves the playhead. Whatever the room was holding for â€” a line of speech,
## a walk â€” is abandoned rather than unwound, so the frame is entered with
## whatever state the skipped frames never got to set. That is fine for looking at
## a movie's end and would not be fine in the game.
func skip_to_end() -> void:
	if _score == null or _score.frame_count <= 0:
		return
	# Two stages, and which one runs depends on whether the frame is waiting.
	#
	# **If something is holding the playhead, release it and stop.** That is a
	# wait-for-click, a tempo delay, a wait-for-sound or a transition, and what
	# the player means by SKIP there is "stop waiting" -- not "leave the scene".
	# Releasing is enough; the movie's own scripts carry on from where they are.
	#
	# **If nothing is holding it, jump to the next marker.** A Director movie is
	# a strip of independently labelled segments, so the marker after the
	# playhead is the start of the next scene and is what "skip this bit" means.
	# EXODUS has 15 markers across 448 frames, MURDER1 34 across 884.
	#
	# The last frame is the fallback and only the fallback, because **a movie's
	# last frame is not its ending** -- it is only the last *segment's* last
	# frame, and entering it from here runs a script that was written to be
	# reached from somewhere else. `tools/skip_state.gd` measures the two ways
	# that goes wrong: MURDER1's f883 runs `go("conect2")` at frame 790, so a
	# jump there goes *backwards* into the tail being skipped and replays 94
	# frames -- which is why SKIP looked like it did nothing and got pressed
	# again -- and DAY1's f2783 runs `play "done"` with nothing on the stack, so
	# the playhead never moves again and every symptom downstream reads as a
	# different bug. Most of a session went into "the cursor never comes back",
	# which was the cursor recomputing correctly over a dead playhead.
	#
	# Releasing alone was the previous attempt and it is not enough: a frame that
	# is simply playing holds nothing, so SKIP did nothing at all in EXODUS.
	# Releasing alone was the first attempt and it is not enough, in two separate
	# ways that both present as "the button does nothing". A frame that is simply
	# playing holds nothing, so there was nothing to release -- that was EXODUS.
	# And a cutscene frame that *is* waiting is typically `go to the frame` with a
	# wait on it, so it **re-arms the wait on the very next entry**: the release is
	# consumed by one step and the playhead is held again before anything is
	# drawn. That was MURDER1. So releasing is paired with a move rather than
	# tried first and returned on.
	#
	# **And what holds the frame is not always the clock.** Piposh 1 gates every
	# line of speech on the sound rather than on a wait, which `_clock.release()`
	# cannot reach:
	#
	#     on exitFrame
	#       if not soundBusy(1) then go(marker(1)) else go(marker(0) + 1)
	#
	# The `else` is the hold -- the segment loops on itself until the voice
	# finishes -- so the release had nothing to release and the jump landed on a
	# segment that ran the same test against the same still-playing sound and
	# waited it out again. The playhead moved and the player heard the identical
	# line to its end, which is why this reads as "SKIP does nothing, ever" rather
	# than as the mis-landings entries 32 and 37 describe. Measured in BRJDAY1
	# from a settled talk, on the movie's own clock: untouched, the segment is left
	# after 1334 ms when the voice ends; jumping alone leaves it in 18 ms **with
	# the voice still playing**, so the next segment re-waits; stopping the channel
	# leaves it in 35 ms with the voice cut, by the movie's own `go(marker(1))`.
	#
	# So the stop is *added* to the release and the jump rather than replacing
	# them, because the corpus needs both levers and neither covers the other.
	# EXODUS is the proof that the jump has to stay: it is not gated on a sound at
	# all, and stopping the channel there moves it 7649 ms against a 7793 ms
	# baseline -- nothing. Both together are what leaves either movie promptly and
	# quietly, 50 ms in EXODUS and 17 ms in BRJDAY1.
	#
	# **Channel 1 only.** 1 is the voice and 2 is the score's background song
	# (`songs\strtgame\songa.aif`), which these movies stop themselves when they
	# mean to -- `sound stop 2` appears in DAY1 six times. Counted over the piposh
	# scripts the gate is `soundBusy(1)` 28 times to `soundBusy(2)` once in
	# STRTGAME and 4 to 0 in BRJDAY1, so stopping 2 as well would silence the music
	# for the rest of the movie to release a wait that is almost never on it. A
	# scene that does wait on 2 still has the jump behind it.
	lingo_stop_sound(1)
	_clock.release_all()
	var target := -1
	if _labels != null:
		for marker in _labels.markers:
			var at := int(marker.get("frame", -1))
			if at > _index and not _skip_sent.has(at):
				target = at
				break
	if target < 0 and not _skip_sent.has(_score.frame_count - 1):
		target = _score.frame_count - 1
	if target < 0 or target <= _index:
		# Every marker ahead has already been skipped to once. Stop rather than
		# wrap, because wrapping is how this becomes a loop the player cannot leave
		# -- and a marker list is not a list of scenes.
		#
		# Rating's `MAINMENU.dir` is the case. Its markers run past the menu into
		# `option1`..`option6`, a CD drive-letter probe entered only by name whose
		# frames end in `go(2)`. SKIP from the menu lands on 587, the probe sends
		# the playhead back to frame 2, and pressing again cycles
		# 14 -> 46 -> 504 -> 587 -> 2 for ever. Each jump is forward and correct;
		# the cycle belongs to the movie, not to the button.
		#
		# Nothing in a `VWLB` says which markers are scenes, so no title-agnostic
		# rule can tell `option1` from `mainscreen` by looking. Refusing to send the
		# playhead to the same marker twice needs no such rule and bounds it.
		print("skip: nothing further to skip to in %s" % movie_name())
		return
	_skip_sent[target] = true
	_index = target
	_held = false
	_clock.reset()
	_pending_enter = null
	# Entered by the next step, the way any jump from outside the step loop is:
	# that step skips `exitFrame`, renders, and sends `enterFrame`.
	_jump_queued = true
	queue_redraw()


## Is the cursor over sprite `channel` right now?
##
## `rollOver` with no argument means "any sprite", which Director answers with
## the channel number rather than a boolean; nothing here needs that yet.
func lingo_rollover(channel: int) -> bool:
	if channel <= 0:
		# §4.5's plain rect test, the same one `the rollOver` answers with, and no
		# longer `_hover_channel` -- see the note at the `rollover` binding in
		# `preview_lingo_host.gd`. The binding routes 0 to the channel form now, so
		# nothing reaches this arm; it agrees with it rather than contradicting it.
		return _rollover_channel > 0
	# Measured against the score's geometry, never the puppeted one. A menu
	# script swaps a button's art *because* rollOver is true, so testing the
	# swapped member's rect feeds the answer back into the question: the
	# highlight changes the rect, the new rect no longer holds the cursor, the
	# highlight drops, and nothing ever settles.
	for sprite in frame_sprites():
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
## **A hidden sprite still has one.** `channel.cpp:isMouseIn` opens with `if
## (!_visible) return kCollisionNo` and is the only site in that file that reads
## `_visible` at all; `c_within` and `c_intersects` go straight to `getBbox()`
## (ScummVM `lingo/lingo-code.cpp` @ `reference/scummvm/REVISION`). The mouse
## cannot reach what nobody can see; the operators measure it anyway.
##
## That is a whole mechanic, because "invisible" is how the idiom *works*: a
## script parks a member where it wants to ask a geometric question and asks it.
## Both of this corpus's users of it hide the sprite they ask about.
##
##   * `CANON.dir` member 496 hides channel 48 -- the 1x1 member `dot` -- puppets
##     it to where the shell lands and runs `repeat with i = 17 to 22 / if sprite
##     48 within i` over the shapes fencing the ships. Measuring the probe as
##     empty answers "no" to every shot in the game.
##   * `MAINMENU.dir` member 287, `on outofthisa`, reads a hidden sprite 20 --
##     the walking Piposh, which member 43 parks on a deck zone and hides --
##     against channels 40-53 to learn which deck the player is standing on.
##     Measuring it as empty matches no zone, so `nof` keeps a stale value and
##     the map cannot tell where the player is.
##
## **The ship map is why this comment is long.** Honouring visibility here was
## the rule for most of this port's life, and when it was lifted a sweep of
## MAINMENU showed `sprite 20 intersects 40..53` going from 0 frames to 85 --
## which was read as a regression and reverted, breaking the cannon again for
## half a day. Those 85 frames are the map *working*: the score itself places
## channel 20 inside a zone (frame 200: sprite 20 at `(157,117)`, channel 44 at
## `(149,107)` 58x27) because that is how the map shows you where you are. A
## behavioural difference in a sweep is not a regression until something the
## player sees is traced to it. What the player had actually seen was
## `bugs.md` 44, which is a `nof` fault and reproduces with this either way.
##
## `tools/sprite_collision.gd` asserts the rule and that the mouse still honours
## visibility; `tools/cannon_hit.gd` plays the cannon round; neither covers the
## map, which is the gap that made this look like a trade.
## Record that a script has asked a geometric question about this channel, so
## the collision overlay can outline it. Called from the operators' host arm
## rather than from `lingo_sprite_rect`, because `tools/` calls that function
## directly and a harness must not populate a debug overlay as a side effect.
func note_collision_channel(channel: int) -> void:
	if channel > 0:
		_collision_channels[channel] = true


func lingo_sprite_rect(channel: int) -> Rect2:
	if _score == null or channel <= 0:
		return Rect2()
	for sprite in frame_sprites():
		if int(sprite["channel"]) == channel:
			var live: Dictionary = _effective(sprite, true)
			return Rect2() if live.is_empty() else _sprite_rect(live)
	return Rect2()


func current_frame() -> int:
	return _index


## What the frame the playhead is on actually shows, in channel order.
##
## **The score's record for this frame is not the answer on its own.** A channel
## a script has whole-sprite puppeted is not reconciled from the score at all
## (`preview/sprite_state.gd:with_puppets`), so it stays on screen through frames
## whose score carries nothing for it -- which is how DAY1's player character
## survives the eleven cut-scene clips that have no channel 30.
##
## Every path that asks what is on the frame comes here rather than reading
## `_score.frame(_index)` itself: drawing, the hit test, the cursor, `rollOver`,
## `the memberNum of sprite`, the text-focus arbitration and the mouse chain.
## They diverged once already over `_effective` -- the screen showed the puppeted
## member while the click was tested against the score's -- and the same split
## here would make a sprite that is drawn unclickable, or the reverse.
func frame_sprites() -> Array:
	if _score == null:
		return []
	return SpriteState.with_puppets(
		_score.frame(_index).get("sprites", []), _overrides)


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
## Asked of the **stage**, because a Movie-In-A-Window has its input processing
## switched off (`preview/boot.gd`) and so never sees an event to decide it from.
## Its own `_pointer` is written by whoever routed the event in, and whether that
## routed point or the OS cursor is the truth is a fact about the machine and the
## last event — both of which belong to the node that received it.
func stage_mouse() -> Vector2:
	if _pointer_seen and bool(stage_preview()._pointer_from_events):
		return _pointer
	return get_local_mouse_position()


## Record where an input event happened. Called with this movie's own
## coordinates: the stage passes the event through `make_input_local`, and a
## window is told by whoever routed the event into it, because a window node has
## its input processing switched off (`preview/boot.gd`) and never sees one.
func note_pointer(at: Vector2) -> void:
	_pointer = at
	_pointer_seen = true


## `the mouseDown` and `the stillDown`, and `the mouseUp` as their exact
## negation. The live button *or* a press this movie has not been stepped since;
## `_mouse_down_seen` is the whole argument for the second half.
##
## A method rather than the field read directly, because the live half has to be
## in it: a button held down while the movie is paused, or during a step that
## never ran, is still down, and a movie asking mid-handler must be told so.
func mouse_button_down() -> bool:
	return _mouse_down_seen or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func lingo_hold() -> void:
	_held = true


## `quit` and `halt` — the application half. The movie half is the host's
## `stopped`, which `_process` reads above.
##
## **Gated on being the application**, and that gate is the reason this can be
## bound at all. Fourteen harnesses instantiate this scene and add it to their
## own root, so `get_tree().current_scene` is not this node in any of them; the
## movie stops, the harness keeps its process, and the assertions after the call
## still run. When the game is the running main scene the tree quits, which is
## what a projector does. A Movie-In-A-Window never quits the application either,
## for the same test — it is not the scene, the stage is.
##
## `the exitLock` is deliberately not consulted: Director locks the quit *key*
## and leaves the command alone (`the exitLock`, and `_notification` below).
func lingo_quit() -> void:
	_trace("f%d quit" % _index)
	set_process(false)
	if get_tree() != null and get_tree().current_scene == self:
		get_tree().quit()


## `beep` and `beep <count>` — the system alert sound, `count` times.
##
## Director spaces repeats 400 ms apart and blocks for the gap; the whole run is
## rendered into one stream here instead, so a `beep 3` is three beeps 400 ms
## apart without the handler that asked for them stopping. Nothing in the corpus
## passes a count, so the gap is unverified and the single beep is not.
##
## Off the numbered sound channels on purpose. Director's beep is the machine's,
## not the movie's, and putting it on channel 1 would make `soundBusy(1)` answer
## true for it — which is the guard every line of speech in this corpus waits on.
func lingo_beep(count: int = 1) -> void:
	if _audio != null:
		_audio.call("system_beep", maxi(count, 1))
	_trace("f%d beep x%d" % [_index, maxi(count, 1)])


## The dialog `alert` raises, found by name rather than held in a field, so that
## a modal the movie put up costs the node no state to save and `ACCOUNTED` no
## entry.
const ALERT_NODE := "LingoAlert"


## `alert "text"` — a modal box with an OK button, and the movie stopped behind
## it until the player dismisses it.
##
## Two sites, one real: `strtgame.dir` 405 tells the player in Hebrew that the
## game runs from the CD only. The player has never seen it.
##
## **Not `OS.alert`, and the reason is measured.** The host platform's own box is
## the obvious choice — it is modal against the whole application exactly as
## Director's is — but on Windows it blocks the calling thread whatever the
## display driver is: `OS.alert` under `--headless` never returned, and a gate
## run that met one would sit there until the ceiling killed it. Every harness in
## `gate.sh` boots a real movie, so a title's `alert` would be a hang nobody
## could attribute.
##
## An engine dialog instead, which is both closer and safer. The player sees a
## box with an OK button; the movie stops behind it, because `_paused` is what
## Director's modal amounts to from the movie's side — no frames, no events, no
## clicks reaching the score; and the engine keeps running, so nothing hangs. The
## divergence from Director is that the *handler* that called `alert` runs on
## instead of blocking inside the call. Recorded rather than hidden: this port
## has no way to block a handler that is not a `go` or a `play`, and blocking the
## process is the thing that cannot be done here at all.
##
## Director also stops recording mouse and key events while the box is up, so
## that the click on OK is not delivered to the movie underneath. `_mouse_down_seen`
## is this port's half of that, and `_paused` is the rest.
func lingo_alert(text: String) -> void:
	_trace("f%d alert %s" % [_index, text])
	_mouse_down_seen = false
	var box: AcceptDialog = get_node_or_null(NodePath(ALERT_NODE)) as AcceptDialog
	if box == null:
		box = AcceptDialog.new()
		box.name = ALERT_NODE
		box.exclusive = true
		box.unresizable = false
		add_child(box)
		# Whatever the movie was doing before the box went up, it goes back to.
		# A player who had paused with the debug key and then triggered an alert
		# must not be un-paused by dismissing it.
		box.confirmed.connect(func() -> void: _paused = bool(box.get_meta("was_paused", false)))
		box.canceled.connect(func() -> void: _paused = bool(box.get_meta("was_paused", false)))
	box.set_meta("was_paused", _paused)
	box.title = movie_name()
	box.dialog_text = text
	box.popup_centered()
	_paused = true


## `delay <ticks>` — hold the playhead for that many 60ths of a second.
##
## The tempo channel's own delay is the same hold with the same reason, so a
## script delay and a score delay cannot disagree about what holding means, and
## the HUD names it the same way. Unverified: 0 sites in either corpus.
func lingo_delay(ticks: int) -> void:
	if ticks <= 0:
		return
	# Through `FrameLoop`'s own preload rather than a second one here, so the two
	# cannot come to name different scripts.
	_clock.hold(ticks * 1000.0 / 60.0, FrameLoop.FrameClock.REASON_DELAY)
	_trace("f%d delay %d ticks" % [_index, ticks])


## `set the searchPath to [...]` — the folders to try when a name does not
## resolve beside the movie that named it.
##
## Handed to the audio resolver, which is the only thing in this port that
## resolves a name to a file at runtime. Absolute paths on a drive that is not
## there simply fail, and that is the answer Piposh 1's CD scan is asking for:
## it writes `d:`, `e:`, `f:` and `b:` in turn and keeps the one whose sounds
## load.
func lingo_search_path(paths: Array) -> void:
	if _audio != null:
		_audio.call("set_search_path", paths)
	_trace("f%d searchPath %s" % [_index, str(paths)])


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


## `puppetTempo <value>`: override the score's tempo, or 0 to hand it back.
##
## §9.1's precedence and its release condition are the clock's -- what a puppet
## overrides is decided where the score's own tempo is read, and nowhere else --
## so this is the routing and not the rule. Zero sites in either corpus.
func lingo_puppet_tempo(value: int) -> void:
	_clock.set_puppet_tempo(value)
	_trace("f%d puppetTempo %d -> %s" % [_index, value, _clock.status()])


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


## `updateStage` — redraw the stage now, without advancing the frame (§9.1).
##
## The most-called name in six titles at 3,717 sites, and inert until this
## existed: every `repeat` loop that animates by moving a sprite and calling it
## drew nothing until the loop ended, so an animation that should play out
## appeared to teleport. What it needed was a paint from inside a handler, which
## `repaint_now` is; the reasoning that said Godot could not do that is answered
## there.
##
## The order is the reference's (`lingo-builtins.cpp:b_updateStage`), and each
## step is here because Director does it rather than because this corpus asks:
##
##   1. **A puppet transition wins over a plain redraw and is consumed.** The
##      reference plays it and drops it on the spot rather than leaving it armed
##      for the next frame change, so a `puppetTransition` followed by
##      `updateStage` spends its transition *here*. Routed through the frame
##      loop's own `begin_transition` with an empty frame, so the puppet source,
##      the resolution and the hold are the one implementation and not a second
##      copy of it. Zero sites across six titles; built because §10 has it.
##   2. **The redraw.** A transition in this port is a timed cut rather than a
##      wipe (`preview/frame_loop.gd`), so the paint happens either way.
##   3. **The cursor is re-resolved.** The reference re-renders it here when it
##      is dirty, and `the cursor of sprite` is one of the two writes that dirty
##      it. Without this a script that changes a cursor and calls `updateStage`
##      keeps the old one until the mouse next moves, because `_resolve_cursor`
##      is otherwise only reached from motion (§7.5).
##
## Not done, and each is a difference worth naming rather than hiding:
##
##   - The reference flushes **queued puppet sounds** here. This port has no
##     queue -- `lingo_puppet_sound` starts the member as it is called -- so the
##     sound a movie is waiting for has already started by the time this runs.
##     Earlier than Director, never later, and `soundBusy` agrees either way.
##   - The reference suppresses `updateStage` entirely while
##     `_disableGoPlayUpdateStage` is set, which it sets around `beginSprite` and
##     `endSprite` dispatch. Neither event exists in this port yet (`AGENTS.md`
##     lists them as open), so there is nothing to suppress it from.
func lingo_update_stage() -> void:
	_update_stage_calls += 1
	if not _puppet_transition.is_empty():
		_begin_transition({})
	repaint_now()
	_resolve_cursor()


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
	# A pending `go to` cancels the waits that are waiting on something — the sound
	# channel, the click, the video — and **not** the frame clock. It is how a
	# script escapes a wait-for-click frame without a click, and without it a room
	# reached by `go` would serve out a wait for a sound the frame it left had
	# queued and it will never hear. The tempo delay is not that: it is how long
	# the frame lasts, the reference's fourth wait arm is the one that does not
	# consult a pending jump, and cutting it short makes the movie play faster than
	# Director did. `FrameClock.release` carries the reference citation.
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


## `the moviePath` — the folder the current movie was opened from, with the
## trailing separator Director put on it so that `the moviePath & "x.dir"` is a
## path and not two names run together.
##
## Unbound, this answered VOID, and `savepath = the moviePath` in `strtgame`'s
## `stonecold()` is the only place this game ever sets `savepath`. Every save and
## every load then asked for `"hezsave.dir"` with a VOID in front of it.
## Resolution recovers from that by bare filename, so it looked harmless; it is
## not the same file when a title ships two of a name, which this one does.
func movie_path() -> String:
	if _movie == null:
		return ""
	return str(_movie.path).get_base_dir() + "/"


## `saveMovie <path>` — write the movie now playing, with everything its scripts
## have put into its fields, to `path`.
##
## §12.4. The decisions are `preview/movie_save.gd`'s and the bytes are
## `director/director_writer.gd`'s; what is here is the reflective name the Lingo
## host calls and the trace line, because a save that refused has to say so
## somewhere the next session can find it.
func lingo_save_movie(where: String) -> Dictionary:
	var report: Dictionary = MovieSave.save(self, where)
	if str(report["error"]) != "":
		_trace("saveMovie %s -> %s" % [where, report["error"]])
	else:
		_trace("saveMovie %s -> %s (%d fields)" % [
			where, report["path"], int(report["written"])])
	return report


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
		#
		# `release_hold` rather than `release`, because `release` is the *jump*'s
		# cancel-everything: it drops the wait-for-sound and the wait-for-video
		# with the timed hold, and a click that aborts a colour cycle is not a
		# jump and releases neither in Director.
		_clock.release_hold(FrameClock.REASON_PALETTE)
	# §8.4: the text widget sees the press before the sprite hit test does, and
	# **does not consume it**. Clicking into a field is a window-manager act, not
	# a Director message -- §4.3's eligibility says nothing about editability, so
	# a field with no script is not a click target and never would be reached by
	# the descent below. Consuming it instead would break the case this exists
	# for: `SAVELOAD`'s slot buttons sit in the channels *above* its eight name
	# boxes, and the `mouseUp` that chooses a slot has to get through.
	TextFocus.press(self, at)
	# The drag used to be started here, one line above the click. It is inside
	# §15's latch block now (`Interaction.latch_press`), which is where the
	# reference puts it and which is what gives the right button one as well.
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
	# §8.4: a text selection follows the pointer only while the button is down,
	# and it is released here rather than in the input router so that a release
	# delivered to a window ends *that* movie's drag.
	TextFocus.release(self)
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
## **Where it comes back to depends on what called it.** `Lingo::func_play`
## records the current frame and then, when `_state->currentChannelId == 0`, adds
## one (`lingo-funcs.cpp:207-213`). Channel zero is "this script is not attached
## to a sprite" — a frame script or a movie script — so a `play` written in a
## frame's `on exitFrame` returns the playhead *past* that frame, and only a
## `play` from a sprite behaviour returns to the frame itself.
##
## That one line is why the reference never re-enters the caller's frame, and it
## is the mechanism this port was missing. `play done` used to land back on the
## caller and suppress its `exitFrame` with a latch, which stopped the interlude
## restarting its caller and reached the same outcome by different means — but the
## difference is observable: landing on the frame re-runs its `on enterFrame` and
## re-arms its score sound, palette and transition, then leaves it without the
## `exitFrame` a room does its exit work in. Landing past it does none of that,
## and the frame it lands on is an ordinary entry that keeps its own events.
##
## `current_sprite_num` is the channel of the chain element running now, which is
## exactly `currentChannelId`; it exists because `the currentSpriteNum` was bound.
func lingo_play_push(args: Array) -> void:
	var from_sprite: bool = _host != null and int(_host.current_sprite_num) > 0
	_play_stack.append({
		"movie": str(_movie.path),
		"frame": _index if from_sprite else _index + 1,
	})
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


## `play done` â€” return to whatever called `play`, and let that handler finish.
##
## Two returns, not one, and the second is the one this port was missing. The
## playhead goes back to the frame `play` left, and the *handler* that called
## `play` -- parked since, mid-statement -- becomes runnable again (§9.4,
## `Window::requeueLingoPlayState`). In Rating's dialogue that handler's next
## statement is the `go` that leaves the conversation, so without the requeue the
## playhead returns to the dialog frame and the option can be clicked for ever.
##
## Requeued rather than resumed here: the handler that wrote `play done` is
## itself still running, and Director refuses to thaw into a live call stack. The
## next step picks it up, which is also what puts the frame `play done` chose on
## screen before the trailing `go` overrides it.
func lingo_play_done() -> void:
	_requeue_play_state()
	if _play_stack.is_empty():
		_held = true
		return
	_pop_play_stack()
	_held = true
	# Returning from an interlude is a jump like any other: the frame it returns to
	# is entered by the next step rather than by this call (§6.1 step 7).
	if not _in_exit_frame:
		_jump_queued = true
	queue_redraw()


## The playhead has run off the end of the score with a `play` outstanding.
##
## **Director's second return from an interlude, and the only one a cut scene that
## simply ends ever reaches.** `score.cpp:462-487` pops the movie stack in the
## `nextFrameNumberToLoad >= getFramesNum()` branch of `updateCurrentFrame`, ahead
## of the wrap to frame 1, and requeues the parked play state as it goes
## (`:474-476`, and `window.cpp:683-684` for the movie-switch half). The stack is
## pushed by `play` and by nothing else, so "the score ended and the stack is not
## empty" is exactly "an interlude ended without saying `play done`".
##
## The port had only the `play done` half. An interlude whose last frame is simply
## the last frame of its score wrapped to frame 0 and played the movie again from
## the top, with the handler that called `play` parked in `_frozen_play` and
## nothing left in the engine that could ever wake it — the same hang, from the
## same cause, as the one `lingo_play_done` above documents. `ENGINE_TODO.md`
## carried it as the first of the three residues of the suspension mechanism.
##
## Returns false when no interlude is outstanding, which is the ordinary
## end-of-score wrap and is left to the caller.
func _return_from_play_stack() -> bool:
	if _play_stack.is_empty():
		return false
	_requeue_play_state()
	_pop_play_stack()
	return true


## The shared half of the two returns: take the caller's position back off the
## stack, cross back into its container if the interlude was in another one, and
## leave the frame entry that follows with the `exitFrame` latch still raised.
func _pop_play_stack() -> void:
	var back: Dictionary = _play_stack.pop_back()
	if str(back["movie"]) != str(_movie.path):
		lingo_go_movie(str(back["movie"]).get_file(), null)
	_index = clampi(int(back["frame"]), 0, maxi(_score.frame_count - 1, 0))
	# **Nothing is suppressed here, because there is nothing to suppress.**
	# `lingo_play_push` recorded the frame *after* the caller's when the `play`
	# came from a frame or movie script, so the entry this return lands on is an
	# ordinary one that has never sent an `exitFrame` and is owed its own.
	#
	# This used to raise `_exit_frame_called` across the entry instead, which
	# stopped the caller's `exitFrame` re-running and re-reaching its own `play`
	# -- the loop that made Piposh Dream's save screen alternate with black
	# (`ques.dir` 803 plays a two-frame errand into `saves.dir`, which has no
	# artwork on those frames). It worked, and it was the wrong mechanism: the
	# reference lands past the frame rather than suppressing an event on it, and
	# the two differ where it shows -- landing on the frame re-runs its
	# `on enterFrame` and re-arms its score sound, palette and transition, then
	# leaves without the `exitFrame` a room does its exit work in. Taking
	# `frameI++` means taking it *instead of* the latch: with both, the entry one
	# frame along would swallow an `exitFrame` that is genuinely owed. See
	# `bugs.md` 54.
	# Returning from an interlude cancels the wait its last frame armed (§9.2).
	# Whether the destination is entered by this call or by the next step is the
	# caller's question and not this one's: `play done` runs from inside a handler
	# and hands the entry to the next step, while the end-of-score return is already
	# standing at the playhead move and the step it is inside enters the frame.
	_clock.release()
	queue_redraw()


## Make the handler a `play` parked runnable again.
##
## Inserted at the *bottom* of the queue, matching `Window::requeueLingoPlayState`:
## anything frozen since the `play` is nearer the surface and finishes first.
## With one `play` outstanding -- which is every case in both corpora -- the queue
## is empty and the distinction never shows.
##
## Called for every `play done`, including the ones with an empty play stack: a
## handler can be parked by a `play` whose movie stack entry has since been
## consumed, and leaving it parked is the shape of hang this whole mechanism has
## to avoid.
func _requeue_play_state() -> void:
	if _frozen_play.is_empty():
		return
	_frozen_lingo.insert(0, _frozen_play)
	_frozen_play = []


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
	return Cursor.at(
		self, at, frame_sprites(), _channel_cursors, _global_cursor)


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
func _effective(sprite: Dictionary, ignore_visible: bool = false) -> Dictionary:
	return SpriteState.effective(sprite, _overrides, _table, ignore_visible)


## `_effective` for a caller that is only *looking* -- the preloader, walking
## frames the playhead has not reached.
##
## The same call now, and kept as its own name rather than folded away: it used to
## need a flag that suppressed the release, because `_effective` released puppets
## as a side effect of being asked and the preloader asks about 24 frames it may
## never play. The release is `sync_frame_entry`'s now and `_effective` is a pure
## read, so the distinction has no code left -- but the *caller* still is the one
## that must never be able to change live state, and a name that says so is what
## makes reintroducing the fault visible in a diff.
func _effective_ahead(sprite: Dictionary) -> Dictionary:
	return _effective(sprite)


## Director's `Sprite::releaseAutoPuppet`, on the event that drives it: the
## playhead has moved from frame `from` to frame `to`, so every property the
## score wrote on the way is handed back to it (§5.3, §5.4).
##
## On the node rather than inside `frame_loop.gd` because both halves it needs
## live here -- the score and the override table -- and because it is the kind of
## thing a harness wants to be able to drive directly.
func _release_auto_puppets(from: int, to: int) -> void:
	if _score == null:
		return
	SpriteState.release_auto_puppets(_score.writes_between(from, to), _overrides)


func _note_member(channel: int, cast_id: int) -> void:
	SpriteState.note_member(channel, cast_id, _last_member, _loop_start, _ticks)


## Through `preview/sprite_props.gd`, which translates the name the *script*
## wrote into the key the override table is merged under. The two vocabularies
## differ on `the moveableSprite of sprite`, and nothing used to sit between
## them -- see that file for what that cost.
func lingo_sprite_prop(channel: int, prop: String) -> Variant:
	# `the loc of sprite N` is the pair, answered as the two-element list this
	# port represents a Lingo point with -- the same shape `the clickLoc`
	# answers, so a script that reads one and writes it back to another sprite
	# never needs a type the language here has no notion of. 361 sites, and
	# `fritz1.dir` swaps two sprites with exactly that read-and-write-back.
	if prop == "loc":
		return [
			LingoValue.to_int(lingo_sprite_prop(channel, "loch")),
			LingoValue.to_int(lingo_sprite_prop(channel, "locv")),
		]
	# `the puppet of sprite N` is the flag `puppetSprite` sets, not a score field.
	# It lives under `channel.gd:PUPPET_KEY` -- the string `"_puppet"` -- and an
	# unrouted read fell through the channel table to `EMPTY_CHANNEL`'s 0, so a
	# channel this movie had just puppeted answered "not puppeted" (§5.2).
	if prop == "puppet":
		return 1 if SpriteState.Channel.at(channel, _overrides).is_puppet() else 0
	_note_sprite_prop(prop)
	return SpriteProps.read(
		channel, prop, _overrides, frame_sprites(), _channel_constraints)


## `the constraint of sprite N`, for `preview/interaction.gd:constraint_box`.
##
## A method rather than a reach into `_channel_constraints`, because the module
## already takes the node untyped and one more `host._field` is one more thing
## that answers `null` instead of failing when it moves.
func lingo_sprite_constraint(channel: int) -> int:
	return int(_channel_constraints.get(channel, 0))


## `puppetSprite N, TRUE/FALSE`.
##
## **The claim takes a copy of the channel as it stands**, and that copy is the
## whole of what §5.2 means for a port shaped like this one. Director keeps a live
## `Sprite` per channel and the puppet freezes *that object* -- `replaceFrom`
## copies the script attachment and returns, so the score never writes the channel
## again. This port has no live sprite: it rebuilds every channel from the score's
## per-frame list on every draw, hit test and property read. So there is nothing
## for the flag alone to freeze, and the record has to be taken here, at the
## moment of the claim, or `with_puppets` has only the score to answer from and
## answers with it.
##
## An **empty** copy is a claim too. A channel puppeted on a frame whose score
## carries no record for it stays empty for as long as the puppet lasts, because
## the score cannot write it any more -- the same rule, read at the other end.
##
## `frame_sprites()` rather than the raw score record, so a channel puppeted twice
## re-claims what it is already carrying instead of falling back to the score.
func lingo_puppet_sprite(channel: int, on: bool) -> void:
	if on:
		var live = SpriteState.Channel.claim(channel, _overrides)
		if not live.is_puppet():
			var here: Dictionary = {}
			for value in frame_sprites():
				var sprite: Dictionary = value
				if int(sprite["channel"]) == channel:
					here = sprite.duplicate()
					break
			live.note_score(here)
	SpriteState.set_puppet(channel, on, _overrides)


func lingo_set_sprite_prop(channel: int, prop: String, value: Variant) -> void:
	_note_sprite_prop(prop)
	# `the cursor of sprite` is channel state, not a puppeted score field: it is
	# not part of the frame delta and survives frame changes and member swaps.
	# Stored in `_overrides` it would be dropped the moment the score moved that
	# channel to another member, which is exactly when a cursor must persist.
	if prop == "cursor":
		_channel_cursors[channel] = value
		_cursor_applied = " "
		_resolve_cursor()
		return
	# `set the puppet of sprite N to 1` and `puppetSprite N, TRUE` are **one
	# operation** in Director -- both assign `Sprite::_puppet` -- so this routes to
	# the builtin's own path rather than storing a field. The distinction is not
	# bookkeeping: the claim takes a copy of the channel as it stands (§5.2), and
	# a flag set without that copy freezes a channel holding nothing.
	#
	# Unrouted it stored `{"puppet": 1}` in the override entry, one underscore
	# from `channel.gd:PUPPET_KEY`, read back as 1 and puppeted nothing -- the
	# `moveableSprite` shape at 12 corpus sites. `preview/sprite_props.gd` has the
	# measurement.
	if prop == "puppet":
		lingo_puppet_sprite(channel, LingoValue.truthy(value))
		return
	# `the locH of sprite` and `the locV of sprite` are one operation in Director
	# and this is where the drag arrives as well, so the constraint is applied in
	# one place for both. See `_write_position`.
	if prop == "loch" or prop == "locv":
		_write_position(channel, prop, value)
		return
	# `set the loc of sprite N to <point>` is those two in one statement, which is
	# what Director's own setter takes. Split here rather than stored under a key
	# of its own: a `loc` override sitting beside `loch` and `locv` would be a
	# third source of a position, and the constraint is applied in exactly one
	# place, which is `_write_position`.
	if prop == "loc":
		var point: Array = value if typeof(value) == TYPE_ARRAY else []
		if point.size() >= 2:
			_write_position(channel, "loch", point[0])
			_write_position(channel, "locv", point[1])
		return
	SpriteProps.write(
		channel, prop, value, _overrides, frame_sprites(), _channel_constraints)


## A sprite property nothing in this port consumes, recorded rather than lost.
##
## **`LingoDiagnostics.SPRITE_PROP` existed and was never once emitted**, and
## that is why property gaps are found by players and builtin gaps are found by
## the gate. An unbound *builtin* reports through `_host_call` and lands in the
## diagnostics; a bound property setter that stores a name nothing reads is
## completely silent, because `sprite_state.write_prop` accepts any key and
## `read_prop` hands it straight back. The write round-trips, every obvious test
## passes, and the only thing that fails is a consumer three modules away.
##
## Five bugs have come out of that one gap -- `moveableSprite`, `editableText`,
## `constraint`, `the member of sprite` and `flipH`/`flipV` -- and each was found
## by someone noticing a sprite had not moved. `preview/sprite_props.gd:CONSUMED`
## is the list this asks, and it is kept beside the alias table because the two
## answer the same question from opposite sides.
##
## Reported, not refused: an unconsumed write is still stored and still reads
## back, exactly as before. The only change is that the session can now say which
## names went nowhere.
func _note_sprite_prop(prop: String) -> void:
	if _interpreter == null or SpriteProps.consumed(prop):
		return
	_interpreter.report(LingoDiagnostics.SPRITE_PROP, prop)


## A position write, through `Channel::setPosition`'s rule (§7.6).
##
## Director has no separate `locH` and `locV` setters: both arrive at
## `setPosition`, which takes a **point**, clamps it into `the constraint of
## sprite`'s channel and stores both coordinates. Two consequences follow, and
## both are the reason this is a function rather than two lines in the caller.
##
## **The constraint is not part of the drag.** Everything that moves a sprite
## comes through here -- `InputRouter.mouse_motion`'s drag writes and a script's
## own `set the locH of sprite N` alike -- so a constrained sprite is constrained
## whether or not anything is dragging it, and whether or not it is moveable at
## all. SHUFFLE says so directly: it constrains sprite 7 as well as sprite 6, and
## only sprite 6 is ever made moveable.
##
## **A write to one axis clamps the other**, because the reference clamps a point
## and then sets both coordinates from it. Stored only when the clamp actually
## moved that other axis, though, and that restraint is not an optimisation:
## puppeting is per field (`preview/sprite_state.gd`), so writing `locV` on every
## `set the locH` would pin an unconstrained sprite's vertical position against
## the score's own animation -- and this game walks its characters by score
## animation.
##
## The unconstrained path stores the value the script wrote, untouched, exactly
## as it did before this existed. A script may legitimately write VOID here --
## `set the locH of sprite 30 to egozh` with `egozh` never set -- and coercing it
## to an int is `sprite_state.effective`'s job, not this one's.
##
## The unconstrained case is also the *hot* case -- this game walks its
## characters by writing `the locH of sprite` every frame -- so it is decided
## before anything else is read, on `constraint_box`'s own answer rather than on
## a second copy of "0 means unconstrained" kept here.
func _write_position(channel: int, prop: String, value: Variant) -> void:
	var sprites: Array = frame_sprites()
	if Interaction.constraint_box(self, channel) == Rect2():
		SpriteProps.write(channel, prop, value, _overrides, sprites, _channel_constraints)
		return
	var axis := 0 if prop == "loch" else 1
	var wanted := Vector2(
		float(LingoValue.to_int(
			SpriteProps.read(channel, "loch", _overrides, sprites, _channel_constraints))),
		float(LingoValue.to_int(
			SpriteProps.read(channel, "locv", _overrides, sprites, _channel_constraints))))
	wanted[axis] = float(LingoValue.to_int(value))
	var at: Vector2 = Interaction.constrain(self, channel, wanted)
	if at[axis] == wanted[axis]:
		SpriteProps.write(channel, prop, value, _overrides, sprites, _channel_constraints)
	else:
		SpriteProps.write(channel, prop, int(at[axis]), _overrides, sprites,
			_channel_constraints)
	var other := 1 - axis
	if at[other] != wanted[other]:
		SpriteProps.write(channel, "locv" if other == 1 else "loch", int(at[other]),
			_overrides, sprites, _channel_constraints)


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
##
## **The library the script named is part of the answer.** Both of these took a
## `cast` and spelled it `_cast`, so `field "x" of castLib "master"` was resolved
## as though it had been written `field "x"` and answered with whichever library
## happened to hold that name first. The reference does not search past a library
## it was given (`movie.cpp:720-759`, and `preview/members.gd`'s own header says
## the same thing about `member(...)`), and this corpus qualifies its field
## references 214 times across the six roots, 170 of them in Piposh 2 alone --
## `field "objectsfield" of castLib "master"` is the inventory and is written on
## every pickup.
func lingo_field(name: String, cast: String) -> Variant:
	var where := _resolve_field(name, cast)
	if where.is_empty():
		return ""
	return _field_text_of(_table.get_member(int(where[0]), int(where[1])))


func lingo_set_field(name: String, cast: String, text: String) -> void:
	var where := _resolve_field(name, cast)
	if where.is_empty():
		return
	_field_text[_field_key(int(where[0]), int(where[1]))] = text
	# The text is drawn straight from here on the next paint, so a write has to
	# ask for one. Without it a HUD updates only when something else happens to
	# redraw.
	queue_redraw()


## `the <prop> of field "x"`, in both directions.
##
## **A field designator carries a property, and it is not always `the text`.**
## `Lingo::getTheField` resolves the designator to a member (`asMemberID`
## preferring a `kCastText`), refuses anything that is not a field, and then
## answers `member->getField(prop)` -- the *member's* property
## (`lingo-the.cpp:2334-2398`). `setTheField` is the same statement written the
## other way. So `the name of field "save1"` is the member's name, `the textSize
## of field "x"` is its point size, and `set the textSize of field "x" to 12`
## changes the size.
##
## This port answered the **text** for every property name and wrote the text for
## every one, so `the name of field "save1"` came back as whatever the player had
## typed into it and `set the textSize of field "x" to 12` replaced the field's
## contents with the string `12`. A write that destroys the value it was not
## addressing is the worst shape here: it round-trips, because the next read of
## `the text` answers what the last write put there.
##
## Routed through the member-property path rather than reimplementing it, so a
## property cannot answer one thing through `member` and another through `field`.
func lingo_field_prop(name: String, cast: String, prop: String) -> Variant:
	return _member_prop_at(_resolve_field(name, cast), prop)


func lingo_set_field_prop(name: String, cast: String, prop: String,
		value: Variant) -> void:
	var where := _resolve_field(name, cast)
	if where.is_empty():
		return
	_set_member_prop_at(where, prop, value)


## `cast` is `of castLib â€¦` as the script spelled it, or `""` for a bare `field
## "x"`. A named library is authoritative and is not searched past; see
## `preview/text_art.gd:resolve`.
##
## **"Authoritative" is asked of the library, not of the clause**, and the
## difference is measured rather than assumed. `tools/field_designator.gd`'s
## survey over all six roots finds 214 distinct `field "x" of castLib Y`
## references, and three of them name a library the movie does not have: Piposh
## 1's `mainmenu.dir` says `castLib "master.cst"` where its own `MCsL` calls that
## library `master`, and ten `piposh-dream` movies say `castLib "panel.cst"` for a
## library that is not loaded at all. `getCastLibIDByName` answers -1 for those
## and the reference then reports "Unknown castLib" and finds nothing â€” which
## would take the money off Piposh 1's slot machine, a field the original draws.
##
## So a library that *resolves* stops the search, which is the rule and the whole
## of the defect this closes; a library name that resolves to nothing falls back
## to the unqualified walk, which is this port's own reading and is recorded here
## as such rather than left to look like the reference.
func _resolve_field(name: String, cast: String = "") -> Array:
	if _table == null:
		return []
	return TextArt.resolve(name, _resolve_member_ref(name, cast), _table,
		Members.library_named(cast, _table) > 0)


func _field_text_of(member: Dictionary) -> String:
	return TextArt.text_of(member, _field_text, _table)


func _field_key(lib: int, number: int) -> String:
	return TextArt.key_for(lib, number, _table)


func _forget_field_text_of(container_path: String) -> void:
	TextArt.forget(container_path, _field_text)
	# The editability overrides are dropped with the text and at the same moment.
	# A movie that is left and re-entered must show the flags its members were
	# authored with, or `SAVELOAD` would come back with whichever slot the player
	# last chose still editable and `save1` -- the one the score arms on entry --
	# not.
	TextFocus.forget(container_path, _member_editable)


## Member resolution, delegated to `preview/members.gd`. The rule that matters --
## the library is part of the answer, not a hint -- lives there with the evidence.
func _resolve_member_ref(which: Variant, cast: String) -> Array:
	return Members.resolve_ref(which, cast, _table)


## `[library, slot]` for a Lingo member reference, packed or bare.
##
## The public spelling of the line above, for callers outside this node that hold
## a reference and need the library it carries -- `preview_lingo_host.gd:script_at`
## is the first. Reaching into `_resolve_member_ref` by name would work and is
## exactly what `scenes/preview/README.md` warns about: a private helper renamed
## makes `get()` answer null and a harness report zero rather than fail.
func lingo_member_where(which: Variant) -> Array:
	return _resolve_member_ref(which, "")


func _resolve_member(which: Variant, cast: String) -> int:
	return int(_resolve_member_ref(which, cast)[1])


## `the <prop> of member N`.
##
## `editable` is answered here rather than in `preview/members.gd` for one
## reason: it is the only member property whose value is not in the parsed member
## record alone. It is the authored flag *or* whatever Lingo last wrote, and the
## override store is the node's. `read_prop`'s fall-through answers 0 for an
## unknown name, so without this arm `the editable of member "save1"` would read
## back 0 immediately after being set to 1 — a write that round-trips as a lie,
## which is the exact failure `preview/sprite_props.gd` was written to prevent.
func lingo_member_prop(which: Variant, cast: String, prop: String) -> Variant:
	return _member_prop_at(_resolve_member_ref(which, cast), prop)


## The same read, against a reference somebody else resolved.
##
## Split out so `the <prop> of field "x"` can be the member property it is in the
## reference without a second copy of these three arms -- `lingo-the.cpp`'s
## `getTheField` is `getField` on the member the designator names, so a field
## property that answered differently from the member property of the same name
## would be a divergence invented here.
func _member_prop_at(raw_where: Array, prop: String) -> Variant:
	# A designator that resolved to nothing is a reference to library 0, which no
	# table has, so every arm below answers what it answers for an absent member
	# -- `""` for the text and the name, 0 for a number. Answering a bare 0 here
	# instead would make `the text of field "x" of castLib 1` come back as the
	# integer 0 where the same field unqualified comes back as "", which is two
	# answers to one question.
	var where: Array = raw_where if not raw_where.is_empty() else [0, 0]
	if prop == "editable":
		return 1 if TextFocus.member_editable(
			self, _table.get_member(int(where[0]), int(where[1]))) else 0
	if prop == "hilite":
		# Answered here rather than in `preview/members.gd` for the reason
		# `editable` is: the value is whatever Lingo last wrote and the override
		# store is the node's. A member has no *authored* hilite -- Director's flag
		# starts clear -- so the store is the whole of it.
		return 1 if bool(_member_hilite.get(
			_field_key(int(where[0]), int(where[1])), false)) else 0
	# `read_prop` answers VOID for a name it has no arm for, and this is the only
	# place that can tell that apart from a member property whose value is
	# genuinely 0. Reported, then answered 0 exactly as before -- an unconsumed
	# read is still a read, and the point is that the session can now say which
	# names went nowhere rather than that they start failing.
	var answer: Variant = Members.read_prop(self, where, prop, _table)
	if answer == null:
		_note_member_prop(prop)
		return 0
	return answer


## `member("save1").editable = 1`. §8.4's focus arbitration is re-run inside
## `TextFocus.set_member_editable`, because this is how a movie *moves* focus:
## `SAVELOAD`'s slot buttons clear the flag on seven fields and set it on the
## eighth inside a single `mouseUp` handler, and the caret has to follow before
## the handler returns.
##
## Written five times in this corpus, all of them in `SAVELOAD.dir`, and until
## now accepted and dropped with a comment saying the port had no in-game text
## entry — which was true and is the thing this change removes.
##
## `text` is the other half of the same `pass`, and it is a *different spelling*
## of a path that already worked rather than a broken feature: `put x into field
## "y"` goes through `lingo_set_field` and always reached the screen, while
## `set the text of member "y"` went nowhere. 0 sites in this corpus use the
## second spelling, which is why it was invisible — and per AGENTS.md that is a
## reason to build it last, not to skip it.
##
## Resolved by reference rather than by name, which is what the deleted
## `lingo/lingo_host.gd` could not do: it forwarded to `set_field(name)`, so
## `set the text of member 12 of castLib 2` — a number, in a named library — had
## no name to forward and was dropped. The library is part of the answer here.
func lingo_set_member_prop(which: Variant, cast: String, prop: String,
		value: Variant) -> void:
	if _table == null:
		return
	_set_member_prop_at(_resolve_member_ref(which, cast), prop, value)


## The same write, against a reference somebody else resolved -- the other half
## of `_member_prop_at`, and there for the same reason: `set the <prop> of field
## "x"` is `setTheField`, which is `member->setField(prop, value)` in the
## reference and must not become a second implementation here.
func _set_member_prop_at(where: Array, prop: String, value: Variant) -> void:
	if _table == null or where.is_empty():
		return
	match prop:
		"editable":
			TextFocus.set_member_editable(
				self, _table.get_member(int(where[0]), int(where[1])),
				LingoValue.to_int(value) != 0)
		"text":
			if int(where[1]) <= 0:
				return
			_field_text[_field_key(int(where[0]), int(where[1]))] = \
				LingoValue.to_str(value)
			queue_redraw()
		"controller", "directtostage", "video", "sound", "crop", "center", \
		"scale", "framerate", "pausedatstart", "loop", "preload":
			# The digital-video authoring flags, stored by `preview/media.gd` so
			# that the write and the read consult one table. Only the flags are
			# writable: `the duration`, `the sampleRate` and the cue points are
			# what the media itself says, and Director does not let a script argue
			# with them either.
			#
			# A write to a member that is not time-based media is **reported and
			# dropped**, the same way the fall-through below reports one with no
			# arm at all: `the loop of member` of a bitmap is a statement about
			# nothing, and storing it would round-trip perfectly and mean nothing.
			# Written out here rather than delegated, because a `match` arm cannot
			# fall through to the default that would otherwise say this.
			if not Media.write_member(self, where, prop, value, _table) \
					and _interpreter != null:
				_interpreter.report(LingoDiagnostics.MEMBER_PROP, prop)
		"hilite":
			# §19's 39-site gap. Its shape was this match knowing `editable` and
			# `text` and dropping everything else, and the consumer is
			# `preview/hilite.gd:artwork` -- already the one place a hilited
			# picture is substituted for the plain one, so the script-set flag and
			# the press-and-hold inversion end up as one substitution rather than
			# two passes that could disagree about flip, blend and the clip.
			if int(where[1]) <= 0:
				return
			_member_hilite[_field_key(int(where[0]), int(where[1]))] = \
				LingoValue.to_int(value) != 0
			queue_redraw()
		"textsize", "fontsize", "textheight", "lineheight", "textalign", "alignment":
			# §5's writable text style. Written into the node's own override and
			# merged by `preview/text_art.gd:style_for`, which is the only place a
			# field's style is assembled -- so the write reaches the screen and
			# `the textSize of member` reads back what was set rather than what was
			# authored.
			#
			# All three of this corpus's `textSize` sites are writes and none is a
			# read (`set the textSize of field "globalmoney" to 24`, Piposh 1's slot
			# machine in three language builds), which is why a read-only binding
			# would have closed the row in §19 and served none of them.
			if int(where[1]) <= 0:
				return
			var key := _field_key(int(where[0]), int(where[1]))
			var over: Dictionary = _member_style.get(key, {})
			match prop:
				"textalign", "alignment":
					over["align"] = LingoValue.to_int(value)
				"textheight", "lineheight":
					over["line_height"] = LingoValue.to_int(value)
				_:
					over["font_size"] = maxi(LingoValue.to_int(value), 1)
			_member_style[key] = over
			queue_redraw()
		_:
			# **Reported rather than dropped.** This match knew two names and
			# silently discarded every other member write, which is the one gap
			# shape with no symptom at all: the statement returns, the read answers
			# the authored value, and nothing anywhere says it did nothing.
			# `LingoDiagnostics.MEMBER_PROP` was declared for exactly this and had
			# never once been emitted (§19). Through the same note as the *read*
			# below, so both halves of one property surface report through one
			# line: the write half was reported and the read half was not, which
			# is half a diagnostic and reads in a log as a clean read surface.
			_note_member_prop(prop)


## A member property nothing in this port consumes, recorded rather than lost.
##
## The twin of `_note_sprite_prop`, and it covers both directions. A write with
## no arm reaches this from `lingo_set_member_prop`'s fall-through; a read with
## no arm reaches it from `lingo_member_prop`, because `preview/members.gd`
## answers VOID rather than 0 for a name its match does not carry.
##
## The read half is the one that was missing and the one that hides better.
## `read_prop` answered **0** for every unbound name, so `the frameRate of member
## 12` -- a real Director property with no arm here -- was a plausible integer
## rather than a hole, and a script that branched on it took a branch. §19 calls
## exactly that shape out about `the top of sprite`: answering 0 is a wrong
## answer, not a missing one. Fifty-odd names had it and nothing said so.
func _note_member_prop(prop: String) -> void:
	if _interpreter == null:
		return
	_interpreter.report(LingoDiagnostics.MEMBER_PROP, prop)


## `the selStart` / `the selEnd` — **movie properties, not field ones** (§8.4).
## One range for the movie, pushed into whichever editable sprite holds focus.
func lingo_sel_start() -> int:
	return int(TextFocus.selection(self)[0])


func lingo_sel_end() -> int:
	return int(TextFocus.selection(self)[1])


## `the selection` — the text between `the selStart` and `the selEnd`, in
## whichever field holds focus.
##
## The same range the two numbers above describe, read out as a string. A movie
## that wants what the player highlighted has no other way to ask: `the selStart`
## and `the selEnd` are offsets into a field the script would otherwise have to
## work out for itself, and the field that has focus is the engine's answer.
func lingo_selection() -> String:
	var text := TextFocus.focused_text(self)
	var range_of := TextFocus.selection(self)
	var start := int(range_of[0])
	var stop := int(range_of[1])
	if start < 0 or start >= text.length() or stop <= start:
		return ""
	return text.substr(start, mini(stop, text.length()) - start)


## `the movieFileSize` — the size on disk of the container now playing, in bytes.
##
## Read from the file rather than remembered from the load, because a movie this
## session has saved over itself is a different size than the one it opened.
func movie_file_size() -> int:
	if _movie == null:
		return 0
	var f := FileAccess.open(str(_movie.path), FileAccess.READ)
	if f == null:
		return 0
	var size := int(f.get_length())
	f.close()
	return size


func lingo_set_sel(prop: String, value: int) -> void:
	if prop == "selstart":
		TextFocus.set_selection(self, value, maxi(value, _sel_end))
	else:
		TextFocus.set_selection(self, mini(_sel_start, value), value)


## The channel owning the active text widget, or 0. What §8.3 routes a keypress
## by, and the one thing a harness needs to see focus arbitration happen.
func lingo_focus_channel() -> int:
	return TextFocus.arbitrate(self)


## `the number of member "x" of castLib "y"`.
##
## Packed, not the bare slot. This and `preview/members.gd:read_prop` are two
## spellings of one question -- the parser gives `the number of member` its own
## node and routes `member("x").memberNum` through the member-property path -- and
## only fixing one of them fixes nothing, because the corpus's cross-cast cursor
## pairs are written in this one.
##
## A member number is per library, so a number handed back without the library it
## was looked up in is not an answer. `the number of member "cutcursor" of castLib
## "panel.cst"` returned a bare 166; 166 is `leftcursor2` in the movie's own cast,
## so Rating's שיחה button drew a silhouette out of the wrong file and masked it
## with an unrelated bitmap out of a third (docs/bugs-closed.md 65). Library 1
## packs to the bare number, so every same-cast site is unchanged.
func lingo_member_number(which: Variant, cast: String) -> Variant:
	var where := _resolve_member_ref(which, cast)
	return Members.pack_ref(int(where[0]), int(where[1]))
