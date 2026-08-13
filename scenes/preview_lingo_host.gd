extends RefCounted
## The smallest host that lets `LingoInterpreter` drive the preview scene.
##
## `lingo/lingo_host.gd` is the real one — 1,200 lines bound to `DirectorRuntime`,
## the puppet walker, the save system and the inventory HUD. This binds the few
## things a room needs to *hold and speak*: the playhead, sprite member and
## visibility, fields, and `sound playFile`. Everything else answers VOID and is
## counted, so what a scene actually reaches is a number rather than a guess.
##
## The interpreter's host contract is duck-typed and small: `owns_global` /
## `get_global` / `set_global`, `is_native_handler`, `call_builtin`, and a handful
## of `get_*`/`set_*` property calls. Returning `null` from `call_builtin` means
## "no such builtin" and raises a diagnostic; returning 0 means "bound, did
## nothing". The difference is the whole point of `unbound` below.

## Preloaded rather than reached by its `class_name`. A global class name is
## resolved from the editor's class cache, which a fresh headless run has not
## built -- so `LingoBuiltins` parsed in the editor and failed to compile at
## boot, taking the whole host with it. Every other module here is preloaded for
## the same reason.
const Builtins := preload("res://lingo/lingo_builtins.gd")
const ContainerName := preload("res://director/director_container.gd")
const GameConfig := preload("res://director/game_config.gd")
const Grammar := preload("res://lingo/compile/lingo_grammar.gd")
## For the four `*Script` properties, which hold Lingo source and compile it on
## assignment (§6.3 tier 1). Only the compiler half is reached from here -- the
## interpreter that *runs* what this compiles is whichever one the movie has, and
## a host that held one would be holding a stale one after every movie change.
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
## §5.1's third qualified entity, `the <prop> of castLib N`. Its own module for
## the reason `windows.gd` and `sound.gd` are theirs: it needs its own dispatch
## path, and the last entity that did not have one lost every write it was given.
const CastLibs := preload("res://scenes/preview/cast_libs.gd")
## §7.3's Xtra registry entry, and the one Xtra this player implements.
const LingoXtra := preload("res://lingo/lingo_xtra.gd")
const FileIO := preload("res://lingo/lingo_fileio.gd")
const BuddyAPI := preload("res://lingo/lingo_buddyapi.gd")

## The bare words `go`'s own grammar puts in front of its arguments.
##
## Taken from the parser's table rather than restated, because a command's words
## and the host that has to skip them are one rule: the parser emitted them, so
## the parser's list is the authority on what can arrive. Restating it is what
## left `frame` unhandled while `to` and `movie` were dropped — see `_go`.
const GO_WORDS: Dictionary = Grammar.COMMAND_WORDS["go"]

var preview: Node = null
## Lingo globals. The real host aliases several of these onto engine state; here
## they are just storage, which is correct until something needs to observe them.
var globals: Dictionary = {}
## builtin name -> times reached, including the ones deliberately ignored. What a
## room needs is a fact to measure, not a list to guess at.
var reached: Dictionary = {}
var unbound: Dictionary = {}
## Set by the interpreter's caller before a mouse message.
var click_sprite := 0

## `the currentSpriteNum` — the channel whose **behaviour** is running, 0 when
## nothing's is.
##
## §7.1 calls it synthesised rather than stored, and it is: Director has no such
## field on the movie either, it is set as each queued sprite behaviour is
## entered and cleared as it leaves, so the property is a read of "where am I"
## rather than of anything the score holds. A behaviour is the *only* tier that
## answers a channel — a cast script, a frame script and a movie script all read
## 0 during the same click, because none of them belongs to a sprite.
##
## It is here rather than on `preview/event_chain.gd` because two unrelated paths
## enter a behaviour and both have to agree: the event queue, and `sendSprite` /
## `sendAllSprites`, which the reference brackets with a save and a restore
## exactly so that a behaviour messaging another sprite reads its own channel
## again afterwards. Both write this one field, and both restore what they found.
##
## Piposh Dream's hex board is the corpus site, 12 of them across `hex1`, `hex2`
## and `hex3`: one behaviour is attached to every tile, and `jumpFrom = the
## currentSpriteNum` is how the tile it is on tells itself apart from the other
## fifty. Answering 0 there is not a missing value, it is every tile claiming to
## be the same tile.
var current_sprite_num := 0
## `the clickLoc` — the stage point of the last mouse-down.
var click_loc := Vector2.ZERO
## When the last press and the last pointer move happened, in engine
## milliseconds. `the lastClick` and `the lastRoll` are Director's "how long ago"
## forms of the same two facts, reported in ticks, and `the doubleClick` is the
## first of them compared against the system interval.
##
## -1 rather than 0 for the click, because 0 is a real timestamp at boot and
## would make the very first press of a session read as a double-click.
var last_click_ms := -1
var last_roll_ms := 0
var double_click := false
## Director's movie-wide key handler: **a string of Lingo**, compiled the moment
## it is assigned and run ahead of everything else on a keypress (§6.3 tier 1).
## 46 scripts in this game set it, most to `fromnow`.
##
## The four `*Script` properties are the only place in the language where an
## assignment changes the event model, and each of them is one field plus one
## compiled copy. The compile happens in the **setter**, so it happens once per
## assignment and it happens on every path that writes the field -- a script's
## `set the keyDownScript to`, and `preview/save_state.gd` putting a restored
## session back. A compile at dispatch time instead would recompile per keypress
## and would let a save reload a script that had never been through the compiler.
var key_down_script := "":
	set(value):
		key_down_script = value
		key_down_compiled = _compile_primary(value, "keyDownScript")
## The release half of the same mechanism (§8.2 tier 1). Measured rather than
## assumed: `tools/key_script_survey.gd -- --all` finds `the keyUpScript` set at
## **10 sites in Rating and 195 in Piposh Dream**, against 0 in Piposh 2 — so a
## port that had only the down half was right about the title it was built on and
## silently deaf in two of the other five. Rating's `ARCADE1.dir` member 20 does
## `set the keyUpScript to "normalkeysx"`, and `normalkeysx` is the handler that
## leaves a timed scene: with no key-up path at all, those rooms could not be left
## by the key that leaves them however free F10 was made.
var key_up_script := "":
	set(value):
		key_up_script = value
		key_up_compiled = _compile_primary(value, "keyUpScript")
## The mouse half of the same mechanism (§6.3 tier 1). Nothing in this corpus
## sets either, so both are bound for the engine's sake rather than for this
## title's need -- §6.3 lists five events with primary handlers and the mouse
## pair is two of them.
var mouse_down_script := "":
	set(value):
		mouse_down_script = value
		mouse_down_compiled = _compile_primary(value, "mouseDownScript")
var mouse_up_script := "":
	set(value):
		mouse_up_script = value
		mouse_up_compiled = _compile_primary(value, "mouseUpScript")

## What each of the four above compiled to, and the whole of §6.3's tier 1 as
## this port runs it.
##
## `{}` for "nothing installed"; `{"name": <lowercased>}` for the bare-identifier
## form; `{"script":, "handler":}` for compiled source
## (`LingoInterpreter.compile_statements`).
##
## **The identifier form is not a second mechanism and is not a shortcut.** In
## Director `set the keyDownScript to "fromnow"` compiles a one-statement script
## whose statement is the no-argument call `fromnow`, so naming a handler is
## what the source form *does* with a bare word; running the named handler
## directly reaches the same handler by the same rules. It is kept separate for
## two reasons that are about this port rather than about Director: the whole
## corpus is that form (`fromnow`, `gomenu`, `normalkeysx` -- 747 `keyDownScript`
## sites and 205 `keyUpScript` sites across the six roots, every one a bare
## name), so it is the path that must not move; and a name that resolves to no
## handler is skipped in silence here, where compiled source would run and
## report an unbound builtin every single keypress. `fromnow` is installed by 46
## scripts and sees every key in the game.
var key_down_compiled: Dictionary = {}
var key_up_compiled: Dictionary = {}
var mouse_down_compiled: Dictionary = {}
var mouse_up_compiled: Dictionary = {}
## The last key pressed. -1 rather than 0 because 0 is a real Mac key code (the
## `A` key), so 0 would read as a keypress that never happened.
##
## **Written on the key going down and never on it coming up.** That is the
## reference's, not a shortcut: `events.cpp:337-338` sets `_keyCode` and `_key`
## in the `EVENT_KEYDOWN` arm, and the `EVENT_KEYUP` arm two dozen lines below
## sets only `_keyFlags` before dispatching. So a `keyUp` handler asking
## `the keyCode` is reading the key that went down — which is what makes
## Rating's `normalkeysx`, a `keyUpScript` that tests `the keyCode = 109`, work
## at all.
##
## Written through a setter so that `the lastKey` -- Director's "how long since
## the last keypress", in ticks -- has an origin without `director_preview.gd`
## having to know it exists. The one writer outside this file is
## `_dispatch_key`, which assigns this field; a setter keeps the timestamp in the
## same place as the value it is a timestamp *of*, which is the only way the two
## cannot drift.
var key_code := -1:
	set(value):
		key_code = value
		last_key_ms = Time.get_ticks_msec()
var key_char := ""
## When the last key went down, in engine milliseconds. 0 rather than -1: unlike
## `the lastClick`, Director has no "no key yet" answer here, and a session that
## has seen no key reports the age of the session, which is what it is.
var last_key_ms := 0

## The modifier word, §8.3, and it is **latched with the event rather than read
## live**.
##
## `the shiftDown`, `the optionDown`, `the commandDown` and `the controlDown` are
## four reads of this one number, and the number is written where the reference
## writes `_keyFlags`: in the key-down arm and again in the key-up arm
## (`events.cpp:357` and `:380`), and nowhere else. A modifier key is the one key
## that updates it *without* dispatching anything -- shift, control, alt and the
## command keys record their state and return, which is §8.3's "modifier keys do
## not generate keyDown events".
##
## Asking the keyboard at the moment of the read instead is what this replaces,
## and it is wrong in the direction that is hardest to see: the four properties
## are almost always read from inside a handler, the handler runs some
## milliseconds after the event that started it, and a chord released in that gap
## reads as never having been held. It is also wrong the other way -- a script
## polling from `exitFrame` saw a modifier the *engine* had never been sent,
## because `Input.is_key_pressed` answers for the OS keyboard and not for the
## event queue this movie is being driven from. A harness that synthesises an
## `InputEventKey` with `shift_pressed` could not make `the shiftDown` true at
## all, which is why nothing tested it.
##
## Four bits rather than Godot's own `KeyModifierMask`, because the word is
## *saved and restored* and a mask whose numeric value belongs to the engine
## would be a Godot version number written into a save file.
const MOD_SHIFT := 1 << 0
const MOD_ALT := 1 << 1
const MOD_CTRL := 1 << 2
const MOD_META := 1 << 3
var key_flags := 0

## `the timeoutKeyDown` -- does a keypress reset the timeout clock?
##
## One of the three "what counts as the player still being here" switches
## (`the timeoutMouse` and `the timeoutPlay` are the others), and the only one
## §8.3 mentions by name: "a key event also refreshes the timeout clock when
## `the timeoutKeyDown` is set". The reference stamps `_lastTimeOut` from the
## key-down arm when it is true.
##
## **The clock it feeds exists now** (`scenes/preview/actors.gd`), so this is
## live rather than the inert store the paragraph this replaces described: a
## key-down stamps `last_timeout_ms` when it is true, exactly as
## `events.cpp:371` stamps `_lastTimeOut`, and a movie that turns it *off* to
## stop the timeout being refreshed by typing now gets that.
##
## Director's default is **true** (`movie.cpp:92`). This port defaulted it false
## while it was inert, which was harmless then and is not now: with the clock
## running, false means typing does not count as the player being present.
var timeout_key_down := true
## `the timeoutMouse`, `the timeoutPlay` -- the other two switches. Director's
## defaults, from `movie.cpp:93-94`: the mouse counts, a `play` does not.
var timeout_mouse := true
var timeout_play := false
## `the timeoutLength`, in ticks. 10800 is three minutes, which is Director's own
## default (`movie.cpp:90`). 0 or less disables the clock -- see
## `preview/actors.gd:check_timeout` for why that is written here rather than
## left to the reference's arithmetic.
var timeout_length := 10800
## When the timeout clock was last reset, in engine milliseconds. `the
## timeoutLapsed` is the distance from here to now, in ticks.
##
## Stamped at construction rather than left at 0, which is `movie.cpp:89`'s
## `_lastTimeOut = _lastEventTime` at the point a movie is made. Left at 0 it
## would read as "the player has been away since the engine started", which is
## only wrong by the seconds a boot takes -- and is exactly wrong for a harness
## that boots, sets a one-tick timeout and expects to control when it fires.
var last_timeout_ms := Time.get_ticks_msec()
## `the timeoutScript` -- a **string of Lingo**, compiled on assignment, run as
## the primary handler for the `timeOut` event (§6.3 tier 1). The fifth member of
## the `*Script` family and the same mechanism exactly: the reference's write arm
## is `movie->setPrimaryEventHandler(kEventTimeout, d.asString())`, which is the
## call the other four make.
var timeout_script := "":
	set(value):
		timeout_script = value
		timeout_compiled = _compile_primary(value, "timeoutScript")
var timeout_compiled: Dictionary = {}

## `the actorList` -- the objects sent `stepFrame` once per frame (§6.1).
##
## A plain Array of script objects. Director accepts anything in it and only
## messages the objects, which is what `preview/actors.gd` does rather than
## filtering on assignment: a movie may legitimately park a placeholder in the
## list and replace it later.
var actor_list: Array = []
## `the perFrameHook` -- one object, sent `stepFrame` before the list.
var per_frame_hook: Variant = null

## `the updateLock` -- TRUE suppresses stage updates until it is cleared.
##
## The other half of `updateStage`, and the reference implements neither the read
## nor the write (`lingo-the.cpp` declares `kTheUpdateLock` and has no arm), so
## there is no behaviour to copy and what is built here is the property's
## documented meaning: while it is set, a repaint is *skipped* rather than
## queued, and clearing it does not replay the ones that were missed. That is the
## reading `updateStage` forces -- a lock that queued would make the next
## `updateStage` paint an old frame.
##
## Consumed by `director_preview.gd:repaint_now` and by the frame loop's own
## repaint, which are the two things that put pixels on the screen.
var update_lock := false


## Ticks since the timeout clock was last reset -- `the timeoutLapsed`.
func timeout_lapsed_ticks() -> int:
	return _ticks_since(last_timeout_ms)


## The player did something that counts as being present, or the timeout fired.
##
## One writer for all four resets (mouse, key, play, and the event itself),
## because the reference stamps the same field from each and four copies of
## `last_timeout_ms = Time.get_ticks_msec()` is four places for the unit to drift.
func reset_timeout() -> void:
	last_timeout_ms = Time.get_ticks_msec()

# --------------------------------------------- what this packaging can answer
#
# Five facts about the *player* rather than about the movie, each named here
# rather than written as a bare constant in its arm. That is not decoration: a
# read arm whose whole body is `return 0` is indistinguishable from a stub, to a
# reader and to `tools/lingo_surface_audit.gd` alike, and every one of these is a
# real answer that a subsystem landing later has to come back and change. Naming
# it puts the answer and the reason in one place and leaves exactly one line to
# edit when it stops being true.

## `the quickTimePresent`, `the videoForWindowsPresent`. **No decoder**, which is
## a narrower statement than the one that used to stand here: the digital-video
## *property surface* is bound now (`scenes/preview/media.gd`) and a movie can
## drive a video sprite and read every property back, but nothing can open the
## media behind a `#digitalVideo` member, so `the mediaReady of member` is FALSE
## and nothing ever plays. These two are the questions a movie asks *before* it
## commits to a video, and FALSE sends it down the branch that works.
const HAS_DIGITAL_VIDEO := false

## The digital-video and sound-member model (`docs/ENGINE_TODO.md`'s digital
## video block). The playhead half is reached from here -- the sprite property
## arms and the four track builtins -- and the member half through
## `preview/members.gd`, so both sides of one surface consult one module.
const Media := preload("res://scenes/preview/media.gd")

## The digital-video state `scenes/preview/media.gd` owns, kept here because the
## host is rebuilt per movie (`preview/boot.gd:start_lingo`) and every one of the
## three dies with the movie it belongs to. A playhead is meaningless once the
## score that held the sprite is gone; a decoded sound's numbers are keyed by
## library and slot, and that pair names a different member in the next movie's
## casts.
##
##   `media_channels`  channel -> the playhead: rate, time, in/out, volume, cue
##   `media_members`   "lib:id" -> the authoring flags a script has written
##   `media_facts`     "lib:id" -> what the member's own bytes say, decoded once
##   `video_readers`   "lib:id" -> `{wanted, reader, path}` — the open AVI
##   `video_frames`    channel -> `{frame, member, size, texture}` — the picture
##   `video_players`   channel -> the `AudioStreamPlayer` its soundtrack runs on
##   `video_streams`   channel -> the hidden `VideoStreamPlayer` a Theora sidecar
##                     decodes on. Separate from `video_players` because the two
##                     hold different node types for different backends and a
##                     dictionary that held either would need a type test at
##                     every use.
##
## The three video entries are the decoder's, and they die with the movie for a
## fourth reason on top of the three above: each holds an open file handle and a
## 1.2 MB RGBA buffer, and a `go to movie` that left them behind would keep both
## for a session. `preview/video.gd:release` is what closes them and
## `preview/boot.gd` is what calls it.
var media_channels: Dictionary = {}
var media_members: Dictionary = {}
var media_facts: Dictionary = {}
var video_readers: Dictionary = {}
var video_frames: Dictionary = {}
var video_players: Dictionary = {}
var video_streams: Dictionary = {}

## `the digitalVideoTimeScale` — the units per second Director converts a video
## sprite's `movieTime` into when a movie asks for one time scale across members
## that disagree.
##
## **0 is Director's own default and means "each member's own scale"**, which is
## why it is not seeded to 60 or to QuickTime's 600: a movie that never writes it
## must get the member's units back, and a non-zero default would silently
## rescale every `the movieTime` in the language.
var digital_video_time_scale := 0

## `the safePlayer`. TRUE only inside Shockwave's sandbox, where file access and
## `open` are refused. This is a projector, so it is FALSE and a movie's own save
## and load paths run.
const SAFE_PLAYER := false

## `the serialNumber`. Director read the projector's registration number. There
## is no registration, and 0 is what an unserialised player answered.
const SERIAL_NUMBER := 0

## `ramNeeded(from, to)`. Bytes that would have to be freed to preload a frame
## range. This port decodes members on demand and purges none of them, so there
## is never anything to make room for. A purge model would answer here.
const RAM_NEEDED := 0

## `the movieFileFreeSize`. Bytes a save would reclaim. `director_writer.gd` lays
## a container out fresh rather than appending, so a saved movie carries no
## slack; a writer that appended would report it here.
const MOVIE_FILE_SLACK := 0

## `the externalParamCount` and its two accessors -- the parameters a page passes
## to an embedded Shockwave movie, as `[[name, value], ...]`. A projector is
## handed none, so this is empty and stays empty until something embeds this
## player; it is a list rather than a constant 0 because a movie reads the count
## and the entries through one another and all three have to agree.
var external_params: Array = []

## `the xtras`, and the list `xtra(...)` looks a name up in — **one list, read
## from both sides**, so the two can never disagree about what this player has.
##
## Each entry is `{"name": <as registered>, "object": <the native object>}`.
##
## **Two entries: FileIO and BudAPI**, and both are here for the same reason --
## they are the Xtras titles are *blocked on* rather than merely missing.
##
## `lingo/lingo_fileio.gd` came first: two movies pointed at this engine stop at
## startup without it, both while reading a configuration file (see that file's
## header). An instance answers `lingo_responds_to`, `lingo_message_list` and
## `lingo_perform`, which is what `respondsTo` and a method call need, so §7.3's
## object surface is cleared rather than approximated.
##
## `lingo/lingo_buddyapi.gd` is the second and its shape is different: BuddyAPI's
## surface is **global**, so the entry here exists only so that `the xtras` and
## `xtra("BudAPI")` agree with the player about what is loaded, while the `ba*`
## names themselves are arms of `call_builtin` below. `itamar-magichat` parks on
## frame 0 without it (`bugs.md` 78) because an unbound `baReadIni` answers the
## integer 0 to a script that tests `= EMPTY`.
##
## Kept as a list of records rather than as bare names because `xtra("name")`
## returns the **object**, not the name: a registry of strings would make the
## lookup succeed and the value it handed back useless, which is the shape §7.3
## warns about at its own `respondsTo`.
var xtras_loaded: Array = []


## Register the Xtras this player implements.
##
## Called from `_init` rather than written as a `var` initialiser because each
## entry needs `self` -- an instance reaches the movie's paths and the write
## guard through the host, and an Xtra that could not would resolve every path
## literally and write wherever it was told.
func _init() -> void:
	xtras_loaded.append({
		"name": "FileIO",
		"object": LingoXtra.new("FileIO", FileIO, self),
	})
	xtras_loaded.append({
		"name": BuddyAPI.XTRA_NAME,
		"object": LingoXtra.new(BuddyAPI.XTRA_NAME, BuddyAPI, self),
	})


## `the beepOn` -- D2, and it does **not** gate the `beep` builtin.
##
## What it gates is §15's one rule: a mouse-down that reached no sprite beeps
## while this is set. `Movie::resolveScriptEvent` is the only reader
## (`if (!event.channelId && _isBeepOn)`), and `LB::b_beep` never asks -- so a
## script's own `beep()` sounds whether or not this is on, and 154 corpus sites
## call it that way.
##
## **False by default**, which is the reference's ("Beep is off by default in the
## original", `movie.cpp:96`) and which the empty-stage rule makes load-bearing:
## most of this game's stage is ineligible backdrop, so with it on every click
## that misses a hotspot would beep. It read `true` here for as long as it was
## gating the builtin instead, where true was the only value that let `beep()`
## make a sound.
var beep_on := false

## `the soundEnabled` -- the movie's own mute. Director stops the audio hardware
## rather than muting each channel, so this gates every path out of this host:
## `sound playFile`, `puppetSound` and the fades alike. `the soundLevel` is a
## different property (a 0-7 volume) and the two are independent in Director.
var sound_enabled := true

## `the randomSeed` and `the floatPrecision` are deliberately *not* fields here.
## Both are read and written through the module that consumes them --
## `LingoBuiltins` owns the generator `random` draws from, and `LingoValue` owns
## the one place a float becomes a string -- so there is no second copy to fall
## out of step with the behaviour it is supposed to control. A setting stored on
## the host and consulted nowhere is the `moveableSprite` shape: it round-trips
## perfectly and changes nothing.

## `the searchPath` — the folders Director looks in when a name does not resolve
## beside the movie that named it.
##
## **A list with one empty element, not an empty list.** Piposh 1 scans for its
## CD in all three language builds by writing one drive letter at a time and
## reading it straight back — `the searchPath = ["d:\sounds\strtgame\"]` then
## `x = getAt(the searchPath, 1)`, 326 sites — so a read that falls off the end
## is the difference between "no disc in D:" and a VOID the loop cannot compare.
## The retired host seeded it the same way and the reason was never written down.
##
## It is consulted as well as stored: `lingo_search_path` hands it to the audio
## resolver, which tries each entry before giving up on a sound. On a machine
## with no D: drive every one of those lookups fails, which is the right answer
## and not the same as never having asked.
var search_path: Array = [""]

## `the exitLock` — while true, the window manager's quit is refused.
##
## Five sites, all writes, all `set the exitLock to 1` or `to true`: Piposh 1's
## `master.cst` and `day1.dir`, and Piposh 2's `strtgame.dir`. Director disables
## the quit *key* with it and leaves the `quit` command alone, so this gates
## `NOTIFICATION_WM_CLOSE_REQUEST` and nothing else. The debug layer's own quit
## key stays unconditional — it exists for us rather than for the movie, and a
## movie must not be able to take away the way out.
var exit_lock := false

## When `the timer` was last set to zero, in engine milliseconds.
##
## Director's `the timer` is **ticks since the last reset**, not a wall clock,
## and both `startTimer` and `set the timer to N` move the origin. This host
## answered `Time.get_ticks_msec()` for it — milliseconds since the process
## started — which is wrong twice over, by a factor of 60 and by an origin.
##
## 91 sites, and the idiom is always the same pair: `if the timer > clockspeed
## then ... set the timer to 0`. Against a number that only ever grows and starts
## in the thousands, every one of those tests was true on every frame, so Piposh
## 1's in-game clock advanced once per frame instead of once per `clockspeed`
## ticks. The write half did not exist at all, so nothing could ever reset it.
##
## Seeded to now rather than to 0, because the host is built when the movie is
## adopted and that is where the reference sets its own origin — a movie that
## never touches the timer should read a few ticks, not the age of the process.
var timer_reset_ms := Time.get_ticks_msec()

## Director's `pause` / `continue` pair (§1.4): the playhead stops where it is
## and the movie stays drawn, interactive and audible.
##
## Per *window*, as the reference has it — each Movie-In-A-Window is its own
## preview node with its own host, so this lands where Director puts it.
##
## **`exitFrame` does not fire while it is set**, which is what keeps the pause
## from cancelling itself: every room holds itself with `go to the frame`, and a
## `go` of any form clears the pause as its first act. So a paused movie is
## released by `continue`, or by a `go` from a handler that still runs — a
## click, a key, a sprite behaviour — and by nothing else. `mainmenu.dir` and
## `hezsave.dir` each have a frame whose whole `exitFrame` handler is `pause`,
## and that is the shape it is for.
var playback_paused := false

## `quit` and `halt`: the movie has stopped.
##
## The reference sets the score's play state to stopped and lets the projector
## fall out of its loop; the loop ending is what quits the application. Split the
## same way here — this is the movie half, and it is what a Movie-In-A-Window or
## a harness sees. The application half is `lingo_quit`'s, and it fires only when
## this preview *is* the application.
var stopped := false

## §8.2's one propagation flag, as Director has it: `pass` sets it true,
## `dontPassEvent` sets it false, and the dispatcher sets it to the *default for
## the tier about to run* before running it — true for a primary handler, false
## for everything else.
##
## It lives on the host because the builtins that write it are answered here,
## and because a flag on the interpreter would belong to whichever agent owns
## `lingo/`. **Every chain reads it now**, mouse and keyboard alike:
## `scenes/preview/event_chain.gd` is the runner, and it is handed a queue that
## `director_preview.gd` built before the first element ran. The mouse half used
## to be inert -- the tiers stopped at the first handler that answered, so a
## `pass` had nothing to continue into -- and `ISLAND2/External/BehaviorScript
## 325`, whose entire body is `on mouseUp / pass() / end`, was a dead zone for as
## long as that was true.
##
## `dontPassEvent` was bound inert until now, alongside `pass`, on the reasoning
## that "this dispatcher stops at the first handler that answers, so there is
## nothing further along to suppress". That reasoning held only because the
## dispatcher had the default inverted: it stopped at the primary handler, which
## is the one tier Director passes *out of* by default. Rating calls
## `dontPassEvent` 9 times and Piposh 1 44 times, and a `dontPassEvent` is a
## statement about a chain that continues.
var pass_event := true

## "play", "go" or "" — set by a freezing command and taken by the interpreter
## that ran it, one statement later.
##
## Director suspends the handler that called `play` or `go` (§6.1 step 18). The
## binding cannot say so by returning a value and it cannot tell an interpreter
## directly either: `go to movie` opens the next container inside the call, so by
## the time `_go` returns, `preview._interpreter` is a *different object* from the
## one whose blocks have to be unwound. Leaving the request here and letting the
## running interpreter take it in `_host_call` is what makes the two agree.
var _suspend_request := ""

## Bound to something real.
const HANDLED := [
	"go", "sound", "puppetsound", "puppetsprite", "cursor",
	"beep", "delay", "starttimer",
	"set", "alert", "halt", "quit", "pause", "continue",
	"window", "open", "close", "forget", "savemovie",
	"pass", "dontpassevent", "stopevent",
	"xtra",
	# BuddyAPI, whose names are global builtins rather than methods on an
	# instance (`lingo/lingo_buddyapi.gd`).
	"bareadini", "bawriteini", "baflushini",
	"bafileexists", "bafilesize", "badeletefile", "bacopyfile", "barenamefile",
	"bafilelist", "bafolderlist", "bafolderexists", "bacreatefolder",
	"badeletefolder", "baopenurl",
	"trackcount", "tracktype", "trackstarttime", "trackstoptime",
	"ispastcuepoint",
	"preload", "preloadcast", "preloadmember", "preloadmovie", "clearglobals",
	"externalparamcount", "externalparamname", "externalparamvalue",
	"frameready", "ramneeded", "getvolumes", "version",
	"moveablesprite", "editabletext", "immediatesprite", "spritebox",
	"sendsprite", "sendallsprites",
	"updatestage",
]
## Answer VOID rather than nothing: these are real Director builtins this host
## has no state to implement, and letting them report as unbound would drown the
## ones that genuinely are.
const IGNORED := [
	"unloadmember", "unload", "nothing",
	# `updateStage` was here, at 3,717 sites -- the largest inert binding this
	# port had -- on a measurement that was true and an inference from it that
	# was not. The measurement: `queue_redraw()` marks the canvas item dirty and
	# pushes the redraw callback onto the message queue, which is flushed at the
	# end of the process frame, GDScript cannot flush it, and a `queue_redraw()`
	# followed by `RenderingServer.force_draw()` leaves a Node2D's `draw`
	# emission count unmoved. All still true. The inference -- "so Godot cannot
	# present synchronously from inside a handler" -- was not: `force_draw()`
	# presents whatever commands the canvas items *already hold*, so the fix is
	# to change the commands first rather than to ask for a `_draw` that will
	# never arrive. `director/director_paint.gd` issues the player's painting
	# through `RenderingServer` instead of through `CanvasItem.draw_*`, which
	# makes `director_preview.gd:repaint_now()` legal from anywhere, and this is
	# bound to it at the match below. The same note also feared a partial arm
	# that "only requested a redraw" and read as live while doing nothing; that
	# fear was right, and it is why the arm paints and presents rather than
	# calling `queue_redraw`.
	#
	# Bound deliberately inert rather than left unbound. An unbound name is
	# reported as a gap every time it is reached, which buries the ones that
	# matter; these are real Director builtins this preview has no state to
	# implement, and answering VOID is the honest response.
	#
	# `pass`, `dontPassEvent` and `stopEvent` were here, on the reasoning that
	# this dispatcher stops at the first handler that answers so there is
	# nothing further along to suppress. That was true only because the key
	# dispatcher had §8.2's default inverted -- it stopped at the *primary*
	# handler, the one tier Director passes out of by default. They are bound
	# for real now, at `pass_event` above and the match below, and the key
	# chain reads them.
	# `saveMovie` was here, and being here is what made this game unsaveable.
	# Every `put x into field "y"` before it landed in the preview's override
	# table and nothing ever reached the disk, so the save survived exactly as
	# long as the process did -- which looks like a working save right up until
	# the player restarts. It is bound for real now, at `_save_movie` below.
	#
	# `beep`, `alert`, `quit`, `halt`, `continue`, `delay` and `startTimer` were
	# here too, and every one of them is bound for real below. `continue` is the
	# one worth naming: `pause` was live and its other half was not, so a movie
	# that paused could never be resumed and the pair had to land together.
	# `preLoad`, `preLoadCast`, `preLoadMember`, `preLoadMovie` and
	# `clearGlobals` were here and are bound for real below. The first four are
	# the correction worth naming: they were recorded as deliberate no-ops on the
	# grounds that this port loads on demand, and the loading half of that is
	# right -- but every one of them reports what it loaded through `the result`,
	# so a movie can observe them and the `noop` channel never applied.
	"printfrom", "unloadmovie",
	"showglobals", "showlocals",
	# `puppetTempo` was here, and being here is what made the tempo channel the
	# only thing in the movie that could change the rate. §9.1 gives a puppet
	# tempo precedence over the score's until the score takes it back, so an
	# inert binding is not "the score wins" -- it is a rate change that never
	# happens and a movie that keeps playing at the last rate a cell named. It is
	# bound for real now, at `puppettempo` below.
	"unloadcast", "restart",
	"shutdown", "installmenu", "setcallback",
]

## `the result`, waiting for the interpreter to take it.
##
## A one-element Array rather than a bare Variant, because VOID is a value a
## builtin may legitimately publish and `null` cannot mean both "nothing to
## publish" and "publish VOID". Empty means nothing happened. The same shape and
## the same reason as `_suspend_request` above.
var _result_request: Array = []


## What the last builtin left for `the result`, and clear it. `[]` for nothing.
func take_result_request() -> Array:
	var pending := _result_request
	_result_request = []
	return pending


func owns_global(name: String) -> bool:
	return globals.has(name.to_lower())


func get_global(name: String) -> Variant:
	return globals.get(name.to_lower(), 0)


func set_global(name: String, value: Variant) -> void:
	globals[name.to_lower()] = value


## Nothing here overrides a script; the real host does, for the walk machine.
func is_native_handler(_name: String) -> bool:
	return false


## Ask for the running handler to be suspended here (§6.1 step 18, §9.4).
##
## Declined when the preview says it cannot hold another frozen handler, and a
## declined request means the old behaviour — the rest of the handler runs at the
## call. That is the safe direction: too little suspension is a wrong ordering,
## while a chain nothing will ever thaw is a conversation that never returns.
func request_suspend(kind: String) -> void:
	if preview == null or not preview.call("lingo_accepts_freeze", kind):
		return
	_suspend_request = kind


func take_suspend_request() -> String:
	var kind := _suspend_request
	_suspend_request = ""
	return kind


## A spinning `repeat` is asking the platform for its turn.
##
## The interpreter calls this from inside a loop that has been going for a while
## (`lingo_interpreter.gd:BREATHE_MS`), so that a loop polling `the mouseDown`,
## `the mouseLoc` or a modifier key can see those answers change. Only the
## preview can do anything about it — it owns the window and the event queue —
## and only the live host has one, which is why this is here and not on
## `lingo_host.gd`.
func breathe() -> void:
	if preview != null:
		preview.call("lingo_breathe")


## Where a suspended handler goes. The preview holds it rather than the
## interpreter, because `go to movie` replaces the interpreter and Director keeps
## frozen state on the window across exactly that.
func park_lingo_state(chain: Array, kind: String) -> void:
	if preview != null:
		preview.call("lingo_park_state", chain, kind)


## Whether the last `call_builtin` reached an arm.
##
## `call_builtin` answers null for "no such name" -- the whole of the contract in
## `lingo_interpreter.gd`'s header -- and that spelling cannot also say "bound,
## and the answer is VOID". `getPref` needs the second: Director answers VOID for
## a preference that has never been written, which is how every "first run?" test
## in the language is written, and an empty string is a *value* a movie cannot
## tell apart from one. So did `externalParamName` and `externalParamValue`, which
## answer VOID past the end of the list.
##
## Set by `call_builtin` itself rather than kept as a list beside it, because a
## list of "names this host binds" is a second copy of the `match` below and would
## drift from it the first time an arm was added.
var _answered_builtin := false


func answered_builtin() -> bool:
	return _answered_builtin


func call_builtin(name: String, args: Array) -> Variant:
	var low := name.to_lower()
	reached[low] = int(reached.get(low, 0)) + 1
	_answered_builtin = true
	match low:
		"go":
			return _go(args)
		"pass", "dontpassevent", "stopevent":
			# §8.2's one flag, written by the two statements that exist to write
			# it. `stopEvent` is Director's older spelling of `dontPassEvent` and
			# means the same thing.
			#
			# Not a no-op any more. The chain runner sets the flag to the running
			# element's default before that element runs, so a handler that says
			# nothing keeps the default: a primary handler passes, everything
			# else consumes. Both chains read it -- `preview/event_chain.gd` runs
			# the mouse and the keyboard from one queue -- so a `pass` in a
			# sprite behaviour reaches the member's cast script, the frame script
			# and the movie scripts behind it.
			pass_event = low == "pass"
			return 0
		"savemovie":
			return _save_movie(args)
		"sound":
			return _sound(args)
		"puppetsound":
			# `puppetSound <channel>, <member>`, and the one-argument form,
			# which is channel 1. The argument is a **cast member**, not a
			# file — this used to route to `sound playFile`, which would have
			# looked for a file named after a member and, worse, claimed
			# nothing: `puppetSound` takes the channel off the score until
			# `puppetSound <channel>, 0` gives it back.
			#
			# Muted by `the soundEnabled` for the same reason `sound playFile` is:
			# Director's switch is at the device, so it covers the scripted
			# channels and the score's alike.
			if preview == null or not sound_enabled:
				return 0
			if args.size() >= 2:
				preview.lingo_puppet_sound(LingoValue.to_int(args[0]), args[1])
				return 0
			if args.size() == 1:
				preview.lingo_puppet_sound(1, args[0])
			return 0
		"puppetsprite":
			# `puppetSprite N, TRUE` hands a channel to the scripts; FALSE gives
			# it back to the score. Ignoring it meant a script's writes outlived
			# the moment the score should have taken the channel back.
			if preview != null and args.size() >= 2:
				preview.lingo_puppet_sprite(
					LingoValue.to_int(args[0]), LingoValue.to_int(args[1]) != 0
				)
			return 0
		"pause":
			# Halts the playhead where it is. The room stays drawn and its
			# scripts keep running, which is what distinguishes it from `halt`.
			#
			# It used to hold for a *single step* (`lingo_hold`), which looked
			# right because the frame's own `go to the frame` re-armed the hold on
			# the next tick -- but only for a frame whose `exitFrame` also holds.
			# The frames that actually call this are `on exitFrame / pause` and
			# nothing else (`mainmenu.dir` 92, `hezsave.dir` 8, `psyday1.dir` 200),
			# so the pause was being kept alive by the very handler Director stops
			# dispatching. See `playback_paused`.
			playback_paused = true
			return 0
		"continue":
			# The other half, and it had to land with `pause` rather than after
			# it: a movie that paused with only half the pair bound never resumes.
			# `exchange.dir` 33 and `docroom.dir` 301 are the shape -- an
			# `exitFrame` that either `continue`s or jumps, so "carry on" and "go
			# elsewhere" are the two arms of one decision.
			playback_paused = false
			return 0
		"quit", "halt":
			# The reference makes these one function: `b_halt` calls `b_quit` and
			# adds a log line. Both stop the movie; the projector quits because
			# its play loop ended, not because the builtin exited the process.
			#
			# Split the same way here, and the split is what makes this safe to
			# bind at all: `stopped` is the movie half and every caller sees it,
			# while the application half is `lingo_quit`'s and fires only when this
			# preview is the running main scene. A harness instantiates the preview
			# as a child of its own root, so a movie cannot take a gate run down
			# with it -- and `the exitLock` does not enter into it, because
			# Director locks the quit *key* and not the command.
			stopped = true
			if preview != null:
				preview.lingo_quit()
			return 0
		"beep":
			# `beep` and `beep <count>`: the system alert sound, repeated with
			# Director's own 400 ms between repeats. 154 sites, every one of them
			# `beep()` with no argument, and all of them silent until now.
			#
			# **`the beepOn` is not a switch over this call**, which is what it was
			# read as here. `LB::b_beep` calls `func_beep` unconditionally; the one
			# thing the property gates is §15's empty-stage click
			# (`preview/interaction.gd:latch_press`). Gating the builtin with it
			# meant a movie that turned the setting off went silent where Director
			# would still have beeped, and it forced the default to `true` to make
			# the 154 corpus sites audible at all -- which in turn would have made
			# every click on bare stage beep once the empty-stage rule landed.
			if preview != null:
				preview.lingo_beep(
					LingoValue.to_int(args[0]) if not args.is_empty() else 1)
			return 0
		"alert":
			# A modal box with an OK button, and the movie stopped behind it.
			# Director also stops recording mouse and key events while it is up,
			# so that the click on OK is not delivered to the movie underneath;
			# `lingo_alert` is where that half lives.
			if preview != null:
				preview.lingo_alert(
					LingoValue.to_str(args[0]) if not args.is_empty() else "")
			return 0
		"delay":
			# `delay <ticks>` -- hold the playhead for that many 60ths of a
			# second. The same channel the tempo cell's delay uses, so a script
			# delay and a score delay cannot disagree about what holding means.
			# 0 sites in this corpus; bound because Director has it.
			if preview != null:
				preview.lingo_delay(
					LingoValue.to_int(args[0]) if not args.is_empty() else 0)
			return 0
		"starttimer":
			# Move `the timer`'s origin to now. 0 sites -- this corpus resets it
			# with `set the timer to 0` instead, which is the same act through the
			# property (§3) and reaches `set_system_prop` below.
			timer_reset_ms = Time.get_ticks_msec()
			return 0
		"play":
			# `play frame X` pushes the playhead and `play done` pops it back.
			# 48 authored statements in this game use `play done`, so treating
			# the whole builtin as inert loses a real control-flow path — the
			# return from a cut scene reads as the movie simply stopping.
			if preview == null:
				return 0
			# The timeout clock's third switch (§3). `the timeoutPlay` is the one
			# of the three the reference **stores and never reads** -- there is no
			# `_timeOutPlay` consumer anywhere in the vendored tree -- so this is
			# built from Director's documented meaning of the property, "the
			# timeout period is restarted when a movie is played", rather than
			# copied. Hung on `play` rather than on `go` because that is the verb
			# the property is named after, and because a title that navigates on a
			# timer would otherwise never be able to let the timer expire.
			# Unverified against Director running.
			if timeout_play:
				reset_timeout()
			var verb := str(args[0]).to_lower() if not args.is_empty() else ""
			if verb == "done":
				# The *thaw*, not a freeze: `play done` is what makes the handler
				# that called `play` runnable again, and Director suppresses the
				# freeze its internal `go` would otherwise raise (`_playDone`
				# guards `_freezeState`). So the handler that wrote `play done`
				# keeps running, which is what lets a cut scene's last frame do
				# `play done` and then tidy up after it.
				preview.lingo_play_done()
				return 0
			preview.lingo_play_push(args)
			# §9.4: the branch is taken, and then the handler stops. The statement
			# after `play frame` is Rating's trailing `go`, and running it here is
			# what overwrote the branch this line just set.
			request_suspend("play")
			return 0
		"updatestage":
			# Redraw the stage now, mid-handler, without advancing the frame
			# (§9.1). 3,717 sites across six titles, and the point of every one
			# of them: a `repeat` loop that moves a sprite and calls this is how
			# Director animates without a score, and with this inert the whole
			# loop drew once, at the end, so the sprite teleported.
			#
			# The work is the preview's -- see `lingo_update_stage`, which also
			# spends a pending `puppetTransition` and re-resolves the cursor,
			# because those are the other two things the reference does here.
			if preview == null:
				return 0
			preview.lingo_update_stage()
			return 0
		"cursor":
			# Was bound inert, which is why the cursor never changed: this game
			# drives it from a `cursorfunk` handler that calls this every tick,
			# and every call was being swallowed. `cursor 0` and `cursor -1` mean
			# the arrow; a list is a custom pair of 1-bit cast members, data and
			# mask; anything else is a built-in number.
			if preview == null:
				return 0
			preview.lingo_global_cursor(args[0] if not args.is_empty() else 0)
			return 0
		"puppetpalette":
			# `puppetPalette <id>` pins the palette against the score, and 0 hands
			# it back — which is not the same as `puppetPalette -1`, because -1 is
			# system Mac and 0 is "stop overriding". A built-in is named by its
			# negative number and a custom palette by its member, exactly as the
			# score's own palette channel names them (§11).
			#
			# The corpus calls this zero times — `reference/lingo/` does not
			# contain the string "palette" at all — so it is bound for the
			# engine's sake rather than this title's, the same way
			# `puppetTransition` is.
			if preview != null:
				preview.lingo_puppet_palette(args[0] if not args.is_empty() else 0)
			return 0
		"puppettempo":
			# `puppetTempo <fps>` overrides the tempo channel until the score
			# writes a tempo of its own, and `puppetTempo 0` hands it straight
			# back (§9.1). Unlike the palette and the transition, the value is
			# not a member id: it is one integer in the tempo channel's own
			# vocabulary, which is a rate in 1-120 and a wait or a delay above
			# it. `director_frame_clock.gd:set_puppet_tempo` is where the
			# precedence and the release condition live.
			#
			# 0 sites in either corpus; bound because Director has it, and
			# because an inert binding here reads as "the score decides the
			# rate" from every direction while being a rate change that silently
			# never happened.
			if preview != null:
				preview.lingo_puppet_tempo(
					LingoValue.to_int(args[0]) if not args.is_empty() else 0)
			return 0
		"puppettransition":
			# A scripted transition: one-shot, applied at the next frame change.
			# Nothing in this game calls it, so it is bound for the engine's sake
			# rather than this title's — but bound rather than ignored, because
			# "the frame's own transition wins over a scripted one" is a bug that
			# only ever shows up once something does.
			if preview != null:
				preview.lingo_puppet_transition(args)
			return 0
		"rollover":
			# The whole of this game's menu is built on it: a frame script asks
			# `rollOver(4)` every tick and swaps the button art. Unbound it
			# answers 0, so nothing ever highlights and nothing looks clickable —
			# which is indistinguishable from the score being wrong.
			if preview == null:
				return 0
			# Two functions sharing one name, and §5 of `LINGO_SURFACE.md` warns
			# about exactly this: with no argument `rollOver` answers the *channel*
			# the pointer is over, with one it answers a boolean about that
			# channel. Defaulting the argument to 1 -- the obvious implementation --
			# silently answers "is the mouse over channel 1" to a script asking
			# "which channel is the mouse over", and both are plausible integers.
			# **`rollOver(0)` is the no-argument form, not "channel 0".** `b_rollOver`
			# starts from `Datum(0)` and only overwrites it when an argument was
			# passed, so `nargs == 0` and an explicit 0 arrive at the same `arg == 0`
			# branch and both answer `getRollOverSpriteIDFromPos` -- the channel
			# under the pointer. Routed here to `lingo_rollover(0)` instead, this
			# answered `_hover_channel > 0`, which is the wrong question twice over:
			# it is the eligibility-filtered *click* channel rather than §4.5's plain
			# rect test, and it is the one rollover field nothing recomputes per tick
			# -- so on a touchscreen, where no motion arrives between taps, it never
			# left whatever the last drag had put there.
			if args.is_empty() or LingoValue.to_int(args[0]) == 0:
				return preview.lingo_rollover_channel()
			return 1 if preview.lingo_rollover(LingoValue.to_int(args[0])) else 0
		"intersects", "within":
			# `sprite A intersects B` -- do the two channels' rects overlap -- and
			# `sprite A within B`, does B contain A. The interpreter routes both
			# here as operators rather than as calls, so `left`/`right` arrive
			# already evaluated to channel numbers.
			#
			# **This is how every drop in the corpus is decided.** Director's
			# inventory idiom drags a moveable sprite and then asks, in `on
			# mouseUp`, what it was let go over: `MASTER/External/BehaviorScript
			# 52` tests `sprite the clickOn intersects 100` (Piposh's head, "what
			# is this?") and then channels 18-21 in turn, and eleven near-copies
			# of it across the corpus do the same. Unbound, the operator answered
			# `null` -- falsy -- so *no* drop target ever matched in any room, in
			# any title. That is not a missing nicety: it is the answer to the
			# question the whole mechanic asks, hardcoded to "nothing".
			#
			# A zero-size rect is an *empty* channel -- one the score puts nothing
			# on -- and answers 0 rather than overlapping everything at the
			# origin. Not a hidden one: `lingo_sprite_rect` measures a sprite a
			# script has hidden, because the reference does. See that function.
			if preview == null or args.size() < 2:
				return 0
			# Both operands are noted for the collision overlay before either is
			# measured, so a zone appears the first time a script asks about it
			# even when the answer is 0.
			preview.note_collision_channel(LingoValue.to_int(args[0]))
			preview.note_collision_channel(LingoValue.to_int(args[1]))
			var first: Rect2 = preview.lingo_sprite_rect(LingoValue.to_int(args[0]))
			var second: Rect2 = preview.lingo_sprite_rect(LingoValue.to_int(args[1]))
			if first.size == Vector2.ZERO or second.size == Vector2.ZERO:
				return 0
			if low == "intersects":
				return 1 if first.intersects(second) else 0
			return 1 if second.encloses(first) else 0
		"soundbusy":
			# Scripts wait on this before speaking. Unbound it answers 0, which
			# reads as "nothing is playing" and lets a room talk over itself.
			if preview == null:
				return 0
			return 1 if preview.lingo_sound_busy(
				LingoValue.to_int(args[0]) if not args.is_empty() else 1
			) else 0
		"label":
			# `label("shore2")` is the frame a marker sits on; `label(0)` is the
			# marker at or before the playhead. Both answer a frame number.
			if preview == null or args.is_empty():
				return 0
			return preview.lingo_label(args[0])
		"marker":
			# **Two argument types, two different questions.** A *number* is
			# playhead-relative -- 0 is the marker at or before the playhead, +n
			# counts forward -- and `LINGO_SURFACE.md` §1.5 is emphatic about it
			# because a port that resolved every `marker()` by name collapsed all
			# 49 of `strtgame`'s markers onto the first and looped a cinematic for
			# ever. That warning is about numbers, and it was read here as "never
			# resolve by name", which is the other half of the same mistake.
			#
			# A *string* is a marker name, and the corpus says so plainly rather
			# than by inference: `marker("mainroom")` appears 11 times in Piposh 1
			# alongside `marker("doc6")`, `marker("dars6")` and `marker("all6")`,
			# and Piposh 2 has eight more -- `marker("stg1go")` through
			# `marker("stg5go")`, `marker("hezanswer")`, `marker("rinclicktalk")`,
			# `marker("patclicktalk")`, `marker("hezfldclicktalk")`. Nobody writes
			# the same string literal 11 times expecting 0.
			#
			# Coerced to 0, every one of those went to "the marker at or before
			# the playhead", and the ship map is where it showed: `outofthisa`
			# hands the player back with `go(marker(nof))`, `nof` being a deck code
			# like "dl1", so the destination was always wherever the playhead
			# already happened to be. Piposh walked to a spot on the map and the
			# game returned him to the frame it was parked on.
			#
			# The numeric path is unchanged and still covers `marker(x)` where a
			# script computed `x` -- Rating's three sites are all
			# `set x to the clickOn` then `x - 7`, so they are integers and stay
			# playhead-relative.
			if preview == null or args.is_empty():
				return 0
			var where: Variant = args[0]
			# A numeric string is a number: Lingo does not distinguish, and only a
			# name that cannot be read as one is a name.
			if typeof(where) == TYPE_STRING and not str(where).strip_edges().is_valid_int():
				# Through `label`, which is the same lookup under the other
				# spelling, so the two cannot answer differently for one name.
				# An unknown name answers 0 there and answers 0 here.
				return preview.lingo_label(str(where))
			return preview.lingo_marker(LingoValue.to_int(where))
		"window":
			## `window("joke.dxr")` — Movie-In-A-Window (§14). Naming a window is
			## what brings it into existence in Director, so this loads the movie if
			## it is not loaded already; `open` is a separate verb that shows it and
			## starts it running. Every one of the 21 opening sites in this corpus
			## depends on the split, because all of them set `the windowType` and
			## `tell` the window before the `open` that follows.
			if preview == null or args.is_empty():
				return stage_handle()
			return preview.lingo_window(LingoValue.to_str(args[0]))
		"open":
			## `open(window("joke.dxr"))`. Director's other `open` — `open <file>
			## with <application>` — is a desktop verb and appears nowhere here.
			if preview == null or args.is_empty():
				return 0
			var to_open := _first_window_name(args)
			if to_open != "":
				preview.lingo_open_window(to_open)
			return 0
		"forget", "close":
			## `forget` destroys the window and its movie; `close` only hides it.
			## Twenty-two sites, all `forget`, and every one of them is a window
			## closing itself — MAP's twelve destination buttons, SAVELOAD's slots,
			## JOKE's wait-for-click frame.
			if preview == null or args.is_empty():
				return 0
			var to_shut := _first_window_name(args)
			if to_shut != "":
				preview.lingo_forget_window(to_shut, low == "forget")
			return 0
		"windowpresent":
			# `windowPresent("map.dxr")` -- does that window exist right now. The
			# question `window("x")` cannot be used to ask, because *naming* a
			# window is what creates it (§14), so a script that probes with
			# `window(...)` brings into being the thing it was testing for. That is
			# the whole reason Director has a separate predicate.
			#
			# Keyed through this file's own `window_key_of`, which is the same
			# `get_basename().to_lower()` rule `director_preview.window_key` uses to
			# build the keys being searched. Comparing the caller's spelling against
			# the stored key directly is the mistake `_first_window_name` documents
			# at length: `"inventor.dir"` never equals `inventor`.
			if preview == null or args.is_empty():
				return 0
			var wanted := window_key_of(LingoValue.to_str(args[0]))
			for key in preview.window_keys():
				if str(key) == wanted:
					return 1
			return 0
		"constrainh", "constrainv":
			# `constrainH(<channel>, <value>)` clamps a coordinate into the named
			# channel's rectangle and answers the clamped number; `constrainV` is
			# the vertical half. Director's own idiom for keeping a dragged sprite
			# inside a tray, and the arithmetic form of `the constraint of sprite`
			# -- the property makes the engine do the clamping every frame, this
			# lets a script do it once and see the answer.
			#
			# Measured against the same rect `intersects` uses, so a script that
			# clamps into a channel and then tests overlap against it cannot get
			# two different rectangles for one sprite.
			if preview == null or args.size() < 2:
				return 0
			var box: Rect2 = preview.lingo_sprite_rect(LingoValue.to_int(args[0]))
			var value := LingoValue.to_int(args[1])
			if box.size == Vector2.ZERO:
				# An empty channel constrains nothing. Clamping into a zero-size
				# rect at the origin would snap every value to 0, which is a wrong
				# answer rather than a missing one.
				return value
			if low == "constrainh":
				return clampi(value, int(box.position.x), int(box.end.x))
			return clampi(value, int(box.position.y), int(box.end.y))
		"cast":
			# D4's older spelling of `member`: `cast "shore2"` answers the member's
			# number. Answered from the same resolver `member(...)` uses, so the
			# two spellings cannot disagree about which member a name is.
			if preview == null or args.is_empty():
				return 0
			return preview.lingo_member_number(args[0], "")
		"getnthfilenameinfolder":
			return _nth_file(args)
		"getpref", "setpref":
			return _pref(low, args)

		# ------------------------------------------------------ the memory hints
		#
		# **They are not no-ops, and recording them as such was wrong.** Every one
		# of these reports what it loaded through `the result` -- the reference's
		# `b_preLoad` writes `_theResult` before it returns, and `b_preLoadCast`
		# writes 1 -- so a movie *can* observe them, which is the whole test the
		# `noop` channel is supposed to apply.
		#
		# What they do not do is change when anything loads: this port opens a
		# container and decodes members on demand, `director_preloader.gd` walks
		# ahead of the playhead on its own budget, and there is no purge to
		# preempt. So the loading half is genuinely nothing and the answer is
		# genuinely something, which is the honest shape of a 1997 memory hint on
		# a machine with 1997's whole heap to spare.
		"preload":
			# With no argument, Director answers the last frame of the movie: it
			# preloaded all of them. With one or two it answers the last frame
			# asked for.
			if args.is_empty():
				_result_request = [get_system_prop("lastframe")]
			else:
				_result_request = [args[args.size() - 1]]
			return 0
		"preloadcast", "preloadmember", "preloadmovie":
			_result_request = [args[args.size() - 1] if not args.is_empty() else 1]
			return 0
		"clearglobals":
			# Every global back to VOID. Director's own reset, and the one thing
			# in this group that is not a hint: a movie that calls it and then
			# reads a global must see nothing there.
			#
			# **Two tables, and clearing one is clearing none.** The globals a
			# script reads and writes are the *interpreter's*; this host keeps a
			# second one for the names it aliases onto engine state, and
			# `lingo_interpreter.gd:_read_var` consults the host's first. A movie
			# that asked for a clean slate and got half of one would read its old
			# values back out of whichever table was missed.
			globals.clear()
			if preview != null and preview._interpreter != null:
				preview._interpreter.globals.clear()
			return 0

		# --------------------------------------------------- the projector's own
		#
		# Questions with a real answer here rather than a stub. A Shockwave movie
		# is handed parameters by the page that embeds it and a projector is not,
		# so the empty answers below are Director's answers for the packaging this
		# port is -- and a movie that loops over them takes the branch that does
		# not need them.
		"externalparamcount":
			return external_params.size()
		"externalparamname", "externalparamvalue":
			# Director indexes them from 1 and answers VOID past the end, which is
			# how a movie loops over them without knowing the count.
			var which := LingoValue.to_int(args[0]) if not args.is_empty() else 0
			if which < 1 or which > external_params.size():
				return null
			var pair: Array = external_params[which - 1]
			return pair[0] if low.ends_with("name") else pair[1]
		"frameready":
			# "Is every member the frame needs in memory?" This port decodes on
			# demand and blocks until it has what it draws, so by the time a
			# script can ask, the answer is yes. TRUE is the truth and not a
			# placeholder; the movies that poll this poll it in a `repeat` and
			# would otherwise never leave it.
			return 1
		"ramneeded":
			return RAM_NEEDED
		"getvolumes":
			# The mounted volumes, by name. Piposh 1 scans for its CD by writing
			# drive letters into `the searchPath` one at a time (see `search_path`
			# above); this is the other way Director offered to ask, and it
			# answers the same machine.
			var volumes: Array = []
			for i in DirAccess.get_drive_count():
				var drive := DirAccess.get_drive_name(i)
				if drive != "":
					volumes.append(drive)
			return volumes
		"version":
			# `version` with no arguments -- D3's spelling, before `the
			# productVersion` existed. The reference builds "major.minor" from the
			# engine's version number and this port runs D6 containers.
			return "6.0"

		# ------------------------------------------------- D2's sprite commands
		#
		# `moveableSprite 5, TRUE` is `set the moveableSprite of sprite 5 to TRUE`
		# written the way D2 wrote it, and the same for the other three. They are
		# routed to the property rather than reimplemented, which is the whole
		# reason they are cheap: one spelling reaching one setter cannot drift
		# from the other spelling reaching the same setter.
		"moveablesprite", "editabletext", "immediatesprite":
			if args.size() >= 2:
				set_sprite_prop(LingoValue.to_int(args[0]), low, args[1])
			return 0
		"spritebox":
			# `spriteBox n, left, top, right, bottom` -- D2's resize-and-move, and
			# the only command in the language that writes a sprite's rectangle.
			# Split onto the four properties Director derives that rectangle from,
			# so the constraint and the auto-puppet rules apply exactly once, in
			# the place they already apply.
			if args.size() >= 5:
				var channel := LingoValue.to_int(args[0])
				var l := LingoValue.to_int(args[1])
				var t := LingoValue.to_int(args[2])
				var r := LingoValue.to_int(args[3])
				var b := LingoValue.to_int(args[4])
				set_sprite_prop(channel, "width", r - l)
				set_sprite_prop(channel, "height", b - t)
				# The registration point is the *centre* of the box Director sets
				# here, because `spriteBox` describes the drawn rectangle and
				# `locH`/`locV` describe the registration point (§8.10).
				set_sprite_prop(channel, "loch", l + int((r - l) / 2.0))
				set_sprite_prop(channel, "locv", t + int((b - t) / 2.0))
			return 0

		# -------------------------------------------------- messages to a sprite
		#
		# `sendSprite(5, #mouseUp)` and `sendAllSprites(#prepareFrame)`. Director
		# sends the message to the sprite's behaviour rather than to whatever the
		# event chain would have chosen, so this reaches the same resolver the
		# frame's own dispatch uses and no further -- there is no movie fallback
		# on this path, because the caller named the recipient.
		"sendsprite", "sendallsprites":
			if preview == null or args.is_empty():
				return 0
			var handler := LingoValue.to_str(
				args[1] if low == "sendsprite" and args.size() > 1 else args[0])
			var channels: Array = []
			if low == "sendsprite":
				channels.append(LingoValue.to_int(args[0]))
			else:
				for sprite in preview.frame_sprites():
					channels.append(int((sprite as Dictionary)["channel"]))
			# The playhead's index, as every other `_sprite_script` caller passes
			# it (`event_chain.gd`, `hilite.gd`, `interaction.gd` all pass
			# `_index`). Subtracting one resolved the behaviours of the frame
			# before the playhead, so a `sendAllSprites` on the first frame of a
			# new segment messaged the segment it had just left.
			var frame_index: int = preview.current_frame()
			# §7.1: a behaviour reached this way reads its **own** channel from
			# `the currentSpriteNum`, and the caller's is put back afterwards. The
			# reference brackets each send with the same save and restore, and the
			# nesting is not hypothetical -- `sendAllSprites` is how a behaviour
			# broadcasts, so the sender is itself a behaviour with a channel of its
			# own to go back to.
			var outer := current_sprite_num
			for channel in channels:
				var script: Dictionary = preview.call(
					"_sprite_script", int(channel), frame_index)
				if not script.is_empty():
					current_sprite_num = int(channel)
					preview.call("_dispatch", handler, script)
			current_sprite_num = outer
			return 0

		# ------------------------------------------------------------- `xtra(x)`
		"xtra":
			return _xtra(args)

		# ------------------------------------------------------- BuddyAPI (§19)
		#
		# **Global names, not methods**, which is what makes them arms here rather
		# than an entry in an instance's `METHODS`: BuddyAPI's whole surface is
		# registered as builtins, a movie writes `baReadIni(...)` bare, and all 46
		# call sites in `itamar-magichat` do. `lingo/lingo_buddyapi.gd` carries the
		# implementations, the path and write rules they share with FileIO, and --
		# at the bottom of its header -- every published name that is deliberately
		# *not* here, with a reason each. An absent name is reported by the
		# unbound-name diagnostic; that is the honest state and the point of
		# enumerating it.
		#
		# `baReadIni` answering a **String** is the whole of `bugs.md` 78. Unbound,
		# it answered the integer 0, `if tmp = EMPTY` was false, and magichat's
		# playhead never left frame 0.
		"bareadini":
			return BuddyAPI.read_ini(self, args)
		"bawriteini":
			return BuddyAPI.write_ini(self, args)
		"baflushini":
			return BuddyAPI.flush_ini(self, args)
		"bafileexists":
			return BuddyAPI.file_exists(self, args)
		"bafilesize":
			return BuddyAPI.file_size(self, args)
		"badeletefile":
			return BuddyAPI.delete_file(self, args)
		"bacopyfile":
			return BuddyAPI.copy_file(self, args)
		"barenamefile":
			return BuddyAPI.rename_file(self, args)
		"bafilelist":
			return BuddyAPI.file_list(self, args)
		"bafolderlist":
			return BuddyAPI.folder_list(self, args)
		"bafolderexists":
			return BuddyAPI.folder_exists(self, args)
		"bacreatefolder":
			return BuddyAPI.create_folder(self, args)
		"badeletefolder":
			return BuddyAPI.delete_folder(self, args)
		"baopenurl":
			# Declined on purpose, and reported rather than silent. A movie
			# handing the host OS a URL it read out of a configuration file is
			# not something a player does without being asked.
			return BuddyAPI.open_url(self, args)

		# ------------------------------------------------- digital video's tracks
		#
		# `trackCount(sprite N)`, `trackType(sprite N, t)`, `trackStartTime` and
		# `trackStopTime` the same, and `isPastCuePoint(sprite N, cue)`.
		#
		# **The reference and Director's own documentation disagree about the
		# arity**, and both spellings are accepted rather than one being picked:
		# `lingo-builtins.cpp` gives all four track functions 1..1 and stubs every
		# body, while the language takes a track number as a second argument for
		# three of them. A one-argument call is read as track 1, which is the only
		# track a member with one media stream has, so the two readings agree
		# wherever the reference's arity could have been right.
		#
		# What they answer is `preview/media.gd`'s, and its header is the honest
		# account: a digital video's tracks are in a file nothing here can open, so
		# the count is 0 and `trackType` answers VOID rather than a symbol a script
		# would then switch on.
		"trackcount":
			if preview == null or args.is_empty():
				return 0
			return Media.track_count(
				preview, LingoValue.to_int(args[0]), preview._table)
		"tracktype":
			if preview == null or args.is_empty():
				return null
			return Media.track_type(preview, LingoValue.to_int(args[0]),
				LingoValue.to_int(args[1]) if args.size() > 1 else 1,
				preview._table)
		"trackstarttime", "trackstoptime":
			if preview == null or args.is_empty():
				return 0
			return Media.track_time(preview, LingoValue.to_int(args[0]),
				LingoValue.to_int(args[1]) if args.size() > 1 else 1,
				"start" if low == "trackstarttime" else "stop", preview._table)
		"ispastcuepoint":
			if preview == null or args.size() < 2:
				return 0
			return Media.is_past_cue_point(
				preview, LingoValue.to_int(args[0]), args[1], preview._table)
	if IGNORED.has(low):
		return 0
	_answered_builtin = false
	unbound[low] = int(unbound.get(low, 0)) + 1
	return null


## `go to the frame`, `go to frame N`, `go to frame "x" of movie "y"`,
## `go(marker(0))`, `go "label"`.
##
## The first is why a Director room sits still at all: the frame script's
## `exitFrame` sends the playhead back to where it already is, every tick. A
## preview without it runs the score off the end of the room, which looks like a
## rendering fault and is the absence of this one call.
##
## `go` is a *command*, so what arrives here is the command's own bare words in
## front of its evaluated arguments: `go to frame "savegame2" of movie X` reaches
## this as `["to", "frame", "savegame2", X]`. They are split off as a set rather
## than filtered one name at a time, because filtering one name at a time is how
## this went wrong. Only `to` and `movie` were dropped, so `frame` was left
## standing in the argument position and read as the destination *marker*. No
## movie has a marker called `frame`, so the lookup fell back to frame 0 — and
## frame 0 of `SAVELOAD` runs back into `HEZSAVE` five frames later, so the two
## movies changed places for ever, reloading the stage every few ticks and
## painting it black in between. Every spelled-out `go to frame ... of movie ...`
## in this corpus is a save/load hop, so the whole save screen was unreachable.
##
## `saveMovie <path>` — write the movie now playing to a file.
##
## The path is optional in Director (no argument means "over itself"), so an
## empty argument list saves in place rather than doing nothing. What is written
## and where is `scenes/preview/movie_save.gd`'s decision; this only carries the
## argument across.
##
## Answers 0 either way, because Lingo's `saveMovie` is a command and not a
## function: a movie that could test its return value would be a movie this port
## could not have run before. The reason a refusal is not silent is the trace
## line in `lingo_save_movie`.
func _save_movie(args: Array) -> Variant:
	if preview == null:
		return 0
	preview.lingo_save_movie(str(args[0]) if not args.is_empty() else "")
	return 0


## The word set is `go`'s own grammar entry — what the parser emitted the words
## from — so the two cannot drift apart. Only *leading* words are taken, which
## leaves a marker genuinely named `frame` reachable as the first argument.
func _go(args: Array) -> Variant:
	if preview == null:
		return 0
	# **Every form of `go` releases a pause, before anything else happens.** The
	# reference does it on the first line of `func_goto` and again in each of
	# `func_gotoloop`, `func_gotonext` and `func_gotoprevious`, which is all four
	# spellings this function covers.
	#
	# It is what makes `pause` safe rather than a trap: the frame that paused
	# stops receiving `exitFrame`, so its own `go to the frame` cannot cancel the
	# pause, and any *other* handler that still runs -- a click, a key, a sprite
	# behaviour -- releases it by navigating. Without this line a movie that
	# paused could only be resumed by an explicit `continue`, and the corpus's
	# paused frames are escaped by their buttons rather than by one.
	playback_paused = false
	var words: Array = []
	for a in args:
		words.append(str(a).to_lower() if typeof(a) == TYPE_STRING else a)

	# The type test is not decoration: this array mixes bare words with evaluated
	# arguments, and GDScript raises on `int != String` rather than answering
	# true — so `go to marker(+1)` threw on this line every time and the playhead
	# never moved, with the error buried in a lambda.
	var spoken: Dictionary = {}
	var values: Array = []
	for w in words:
		if values.is_empty() and typeof(w) == TYPE_STRING and GO_WORDS.has(str(w)):
			spoken[str(w)] = true
			continue
		values.append(w)

	# A movie name arrives in one of three shapes: `go to movie "day1.dir"`,
	# `go(1, "day1.dir")`, and `go to frame "x" of movie "day1.dir"`. All three
	# are in this game, so the file is found by looking like one rather than by
	# its position — and by the engine's own list of container extensions rather
	# than a third hand-written copy that omitted `.dcr`, `.cxt` and `.cct`.
	var movie := ""
	var where: Variant = null
	for w in values:
		if typeof(w) == TYPE_STRING and ContainerName.is_container(str(w)):
			movie = str(w)
			continue
		if where == null:
			where = w
	# `go to movie "day1"` may leave the extension off, and then nothing in the
	# arguments looks like a container: the command word is the only thing saying
	# a movie was named at all. Director resolves the name either way.
	if movie == "" and spoken.has("movie") and where != null:
		movie = str(where)
		where = null
	# **The two-argument function form is positional, and nothing above covers
	# it when the name carries no extension.** `lingo-builtins.cpp:b_go` pops the
	# last argument first and branches on its *type*, not on how it is spelled: a
	# STRING there is the movie and the remaining argument is the frame; an INT
	# there means the first argument is the frame and the rest is discarded. No
	# extension is consulted anywhere -- `Window::setNextMovie` is handed the raw
	# string and `findMoviePath` appends the extensions itself.
	#
	# Recognising the movie by its extension alone is therefore a narrower rule
	# than Director's, and the corpus reaches past it. Magic Hat's `logo.dir`
	# frame 6 is
	#
	#     go(1, GetMoviePath(CDpath() & DirChar() & "magichat"))
	#
	# and `GetMoviePath` (`utils.cst`, the movie's own handler) hands back its
	# argument unchanged when the ini has no `[MOVIE]` section -- so the second
	# argument is a path with **no extension at all**. Nothing looked like a
	# container, nothing said the word `movie`, and the loop above had already
	# taken the `1` as the destination, so the path was dropped on the floor and
	# the statement degraded to `go(1)`. Measured before this line: the playhead
	# ran f4, f5, then **f0 of logo.dir**, replaying the ten-second logo for ever
	# (`bugs.md` 95). It was never a path-resolution fault -- `resolve` was not
	# reached with the name at all.
	#
	# Ordered after the two rules above rather than replacing them, because those
	# two also serve the *command* spellings (`go to movie "x"`,
	# `go to frame "y" of movie "x.dir"`), whose word stripping leaves the values
	# in an order the stack rule was never written for. This only adds the case
	# they both decline, which is exactly the case `b_go` handles by position.
	if movie == "" and not spoken.has("movie") and values.size() == 2 \
			and typeof(values[1]) == TYPE_STRING:
		movie = str(values[1])
		where = values[0]
	if movie != "":
		preview.lingo_go_movie(movie, where)
		request_suspend("go")
		return 0

	if values.is_empty():
		# `go loop`, `go next`, `go previous`. Relative score navigation is not
		# modelled; holding is closer to right than running on into unrelated
		# frames, and it is visible rather than silent.
		#
		# **These three do not suspend.** `func_gotoloop`, `func_gotonext` and
		# `func_gotoprevious` set only `_skipFrameAdvance`; `_freezeState` belongs
		# to `func_goto`, which is the destination-taking form below. It is a
		# distinction the reference makes explicitly and one nothing else would
		# ever recover, because the three are spelled like the form that does.
		preview.lingo_hold()
		return 0

	var first: Variant = values[0]
	if first == null:
		# **`go(VOID)` navigates nowhere.** The reference's `func_goto` answers a
		# VOID destination and a VOID movie by returning immediately, *before* it
		# sets the skip-advance and freeze flags -- so the statement is not a jump
		# to frame 0, it is a jump that does not happen, and the score advances
		# out of the frame on its own as if the line were not there.
		#
		# Coercing it instead is silent and self-perpetuating: `go(VOID)` became
		# `go frame 0`, which is a re-entry into the frame the handler was already
		# in, so the same `on exitFrame` ran again and the movie stopped for ever
		# with nothing on the clock and no error. That is `itamar-magichat`'s
		# black screen -- `go(GlobalInfo(#startFrame))` with `#startFrame` unset.
		#
		# Reported as well as declined, because a destination that evaluated to
		# nothing is nearly always a global the movie failed to fill in, and the
		# diagnostic names the script, the handler and the line.
		if preview != null and preview._interpreter != null:
			preview._interpreter.report(LingoDiagnostics.BUILTIN, "go: destination is VOID")
		return 0
	if typeof(first) != TYPE_STRING:
		# `go 5` names Director's fifth frame, not the sixth. This passed the
		# number through as an index, which cancelled against `the frame` for the
		# relative forms everybody writes (`go(the frame + 1)`) and was wrong for
		# every absolute one -- `go(1)` at 32 sites in `reference/lingo/` landed on
		# the second frame while `go(1, "movie")` two lines away landed on the
		# first. See `director_preview.lingo_frame_index`.
		preview.lingo_go_frame(
			preview.lingo_frame_index(LingoValue.to_int(first)))
		request_suspend("go")
		return 0
	match str(first):
		"the frame":
			# `go to the frame` *is* `func_goto` with a frame number -- the number
			# happening to be the one already playing does not change which call it
			# is -- so it suspends like any other. It is also the single most
			# frequent statement in the corpus, every room's hold loop, and it is
			# always the last statement of its handler: the chain it parks is empty
			# and resuming it runs nothing. That is the shape of the whole change.
			preview.lingo_hold()
			request_suspend("go")
			return 0
		"loop", "next", "previous":
			preview.lingo_hold()
			return 0
	# Director's frame argument is a number *or* a marker name, and both spellings
	# reach here: `go to frame item 1 of nextroomdata` is how MASTER puts the
	# player back in the room they came from, and that item is a marker name.
	# Reading the bare word `frame` as the destination made that statement hold
	# instead of jump.
	preview.lingo_go_label(str(first))
	request_suspend("go")
	return 0


## The `sound` command, all five verbs.
##
## What this corpus reaches, counted over `reference/lingo/`: **2,515
## `sound playFile`** over channels 1 (2,196), 2 (201), 3 (100) and 4 (18), and
## **69 `sound stop`**. `close`, `fadeIn` and `fadeOut` are written nowhere here
## and are bound anyway — they are Director's, and a title that uses them should
## not find a hole where the verb was.
##
## The score's own sound channels are a separate source and are driven elsewhere
## (`director/score_sound.gd`). In *this* game they are silent, for a reason
## worth recording: its 86 containers hold 15,297 cast members and not one is of
## type `sound`, so no frame here can name one (`tools/sound_survey.gd`). That is
## the argument, and not "those bytes are zero" — several bytes of the main
## channel block are non-zero across the corpus and this port does not yet know
## what all of them mean (bugs.md 31).
func _sound(args: Array) -> Variant:
	if args.is_empty() or preview == null:
		return 0
	# `the soundEnabled` is the movie's own mute and Director applies it at the
	# device, so every verb that would *start* audio is refused while it is off
	# and every verb that stops audio still runs -- a movie that mutes itself
	# mid-line must not be left with the line playing.
	var verb := str(args[0]).to_lower()
	if not sound_enabled and (verb == "playfile" or verb == "fadein"):
		return 0
	var channel := LingoValue.to_int(args[1]) if args.size() >= 2 else 0
	match verb:
		"playfile":
			if args.size() >= 3:
				return _play(channel, str(args[2]))
			return 0
		"stop":
			# All 69 `sound stop` statements in this game name a channel — 57 on
			# 2, 9 on 1, 3 on 3. The channel-less form stops everything rather
			# than defaulting to 1, which is what `lingo/lingo_host.gd` does and
			# what a channel argument of 0 would otherwise silently become.
			if args.size() >= 2:
				preview.lingo_stop_sound(channel)
			else:
				preview.lingo_stop_all_sound()
			return 0
		"close":
			preview.lingo_close_sound(maxi(channel, 1))
			return 0
		"fadein", "fadeout":
			# `sound fadeIn <channel>, <ticks>`; Director's default when the
			# duration is omitted is one second, which is 60 ticks.
			var ticks := LingoValue.to_int(args[2]) if args.size() >= 3 else 60
			preview.lingo_fade_sound(maxi(channel, 1), ticks, verb == "fadein")
			return 0
	return 0


func _play(channel: int, file: String) -> Variant:
	if preview != null:
		preview.lingo_play_sound(channel, file)
	return 0


## `getNthFileNameInFolder(<folder>, <n>)` — the n'th name in a directory, 1-based,
## and `EMPTY` once n runs past the end.
##
## Director's only directory listing, and the one a title uses to find out what
## save games exist rather than guessing at names. The empty string terminator is
## the whole protocol: every script that uses this counts up until it gets one,
## so answering VOID instead would make the loop compare against the wrong thing
## and either stop at 1 or never stop.
##
## Folders and files both count, and the order is the filesystem's, which is what
## Director's is too. `@` is not resolved — Director's own relative-path prefix is
## a `moviePath` question and `lingo_search_path` already owns that seam.
func _nth_file(args: Array) -> Variant:
	if args.size() < 2:
		return ""
	var folder := LingoValue.to_str(args[0]).replace("\\", "/")
	var which := LingoValue.to_int(args[1])
	if which < 1:
		return ""
	var dir := DirAccess.open(folder)
	if dir == null:
		# A folder that is not there lists nothing. Director answers EMPTY rather
		# than raising, and a script that cannot tell "no such folder" from "no
		# more files" is one that terminates either way.
		return ""
	var names: Array = []
	names.append_array(dir.get_directories())
	names.append_array(dir.get_files())
	return str(names[which - 1]) if which <= names.size() else ""


## `xtra("name")` and `xtra(n)` — §7.3's lookup into the registry of Xtras this
## player has loaded.
##
## Director takes either spelling: a **name**, matched case-insensitively, or a
## **1-based index** into the loaded list, and it raises a script error when
## neither finds anything. Both are here, against the one list `the xtras` reads,
## so a movie cannot be told an Xtra exists by one name and not by the other.
##
## §7.3's name normalisation is applied to the lookup as well as to the entries:
## the platform extensions (`.xlib`, `.dll`, `.x16`, `.x32`) and the Mac path
## separators come off first, so the same library named three ways in three
## movies resolves once. That is Director's rule and not a convenience — a movie
## that says `xtra("FileIO.x32")` and one that says `xtra("fileio")` are asking
## for the same object.
##
## **The registry is empty, so every lookup fails, and a failure is reported by
## name.** That is the honest state and it is deliberately not silence: an
## unbound *builtin* is reported and lands in the diagnostics, and an Xtra that
## does not exist has to read the same way, or a movie's `xtra("net")` becomes
## the one kind of miss this port cannot see. Director's own answer is a script
## error; VOID plus a named diagnostic is the closest this interpreter has, and
## it is what every "probe for an Xtra, take the branch that does not need it"
## script wants anyway.
##
## The arity check is Director's: `xtra` takes exactly one argument. The corpus's
## only two sites are `xtra(#net, 2, type & "thud.aif")` in Piposh Dream's
## `ratA.dir`, inside a handler called `__` that nothing calls — three arguments,
## which is an error in Director too. Reporting it is the difference between
## "this port has no Xtras" and "this script was already broken in 1997".
func _xtra(args: Array) -> Variant:
	if args.size() != 1:
		report_xtra("xtra/%d arguments" % args.size())
		return null
	var wanted: Variant = args[0]
	# The index form first, and only for a real integer: a symbol or a string is
	# a name even when it looks like a number, because `xtra("2")` names an Xtra
	# called "2" and `xtra(2)` is the second one loaded.
	if typeof(wanted) == TYPE_INT or typeof(wanted) == TYPE_FLOAT:
		var which := int(wanted)
		if which >= 1 and which <= xtras_loaded.size():
			return (xtras_loaded[which - 1] as Dictionary).get("object", null)
		report_xtra("xtra %d" % which)
		return null
	var name := xtra_key(LingoValue.to_str(wanted))
	for entry in xtras_loaded:
		if xtra_key(str((entry as Dictionary).get("name", ""))) == name:
			return (entry as Dictionary).get("object", null)
	report_xtra("xtra \"%s\"" % name)
	return null


## §7.3's normalised form of an Xtra or XObject name: no platform extension, no
## path in front of it, case-folded. The lookup key on both sides of the
## registry, so registering `FileIO.x32` and asking for `fileio` is one Xtra.
static func xtra_key(name: String) -> String:
	var bare := name.replace(":", "/").replace("\\", "/").get_file().strip_edges()
	for suffix in [".xlib", ".dll", ".x16", ".x32", ".xtra"]:
		if bare.to_lower().ends_with(suffix):
			bare = bare.substr(0, bare.length() - suffix.length())
			break
	return bare.to_lower()


## A lookup that found nothing, or an Xtra call this player refused, named in the
## diagnostics the way an unbound builtin is. Through the interpreter because
## that is where the script name, the handler and the line live; silently dropped
## when there is no interpreter to tell, which is only the case in a harness that
## built a host on its own.
##
## Public, not `_`-prefixed, because `lingo/lingo_buddyapi.gd` is the other
## caller: BuddyAPI answers 1 or 0 and has no `status` channel for a reason to
## arrive through, so a refused write and a declined `baOpenURL` say so here or
## nowhere.
func report_xtra(what: String) -> void:
	if preview == null or preview._interpreter == null:
		return
	preview._interpreter.report(LingoDiagnostics.BUILTIN, what)


## `getPref(<name>)` and `setPref(<name>, <value>)` — Director's own small
## key/value store, and the only persistence a Shockwave movie has.
##
## Real storage rather than a stub, because the alternative is the shape this
## whole audit exists to catch: a `setPref` that accepts and drops leaves every
## `getPref` answering VOID, which reads exactly like a first run, for ever.
##
## Under `user://`, which is where Godot puts per-user writable state on every
## platform this exports to; Director puts it beside the projector on Windows and
## in Preferences on the Mac, and neither location is writable on a modern
## machine. The name is sanitised to a bare filename for the obvious reason: a
## movie must not be able to write outside the preference folder by naming
## `../../something`.
const PREFS_DIR := "user://prefs"


func _pref(which: String, args: Array) -> Variant:
	if args.is_empty():
		return null if which == "getpref" else 0
	var name := LingoValue.to_str(args[0]).replace("\\", "/").get_file()
	name = name.strip_edges().to_lower()
	if name == "" or name.begins_with("."):
		return null if which == "getpref" else 0
	var path := PREFS_DIR.path_join(name + ".txt")
	if which == "getpref":
		# VOID when the preference has never been written, which is what Director
		# answers and what every "first run?" test in the language is written
		# against. An empty string would be a *value*, and a movie cannot tell the
		# two apart any other way.
		if not FileAccess.file_exists(path):
			return null
		return FileAccess.get_file_as_string(path)
	DirAccess.make_dir_recursive_absolute(PREFS_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return 0
	f.store_string(LingoValue.to_str(args[1] if args.size() > 1 else ""))
	f.close()
	return 0


# --------------------------------------------------------------------- windows
#
# A window reference is a Lingo *value* — it is passed to `open`, stored, and
# named as a `tell` target — so it has to survive a trip through the interpreter
# as a Variant. It is a one-entry Dictionary rather than a new class because that
# needs nothing of `LingoValue` and cannot be confused with a String the way a
# bare movie name could: `tell "map.dxr"` is not a thing, and a handle that was
# just a String would make it look like one.
#
# `{"window": ""}` is the stage. `the stage` and `window("")` therefore agree,
# which they should.

const WINDOW_HANDLE := "window"


static func stage_handle() -> Dictionary:
	return {WINDOW_HANDLE: ""}


## The window a Lingo value addresses: a handle, or a bare name for the spellings
## that skip `window(...)`. "" is the stage, which is why the caller has to test
## `is_window_ref` rather than treat "" as a failure.
## The first argument that names a window, rather than whichever one happened to
## be first.
##
## `open` and `forget` are command words as well as functions, so the argument
## array can arrive carrying the command's own bare words alongside the evaluated
## value -- the same hazard `_go` documents above, where a bare `to` sits in
## front of the real argument. Reading `args[0]` then hands `window_key_of` a
## word like `window`, which keys to nothing, and `open` returns having silently
## done nothing at all.
##
## That is exactly how the joke popup failed: `open` was reached -- it shows in
## `builtins reached` -- the window existed, and it was never shown. Scanning for
## the first argument that yields a key makes the binding indifferent to how the
## call was spelled.
## **It answers the name, not the key**, and that distinction is the whole of
## `bugs.md` 55. `window_key_of` is `get_basename()`, so it throws the extension
## away — and the two calls below hand their answer to `lingo_open_window` /
## `lingo_forget_window`, which take a *name*: they key it themselves, and on a
## miss they call `_create_window`, which resolves the name against the disc.
## Keyed first, `open window "inventor.dir"` reached the resolver as `inventor`,
## and `ContainerName.spellings` refuses to try container extensions on a bare
## stem on purpose (`director/director_container.gd:73-75`, "`day1` is not
## `day1.dxr`"), so it resolved to nothing. Every one of `rating`'s twelve opens
## failed that way, including the bag on the panel in every room.
##
## A handle carries no name — only the key it was made with — but a handle only
## exists because `window(...)` already created the window, so the key hits
## `_windows` and never reaches the resolver. `window_key` is idempotent, so
## passing one back as a name is a no-op.
static func _first_window_name(args: Array) -> String:
	# A handle is unambiguous, so it wins wherever it sits.
	for value in args:
		if is_window_ref(value):
			return window_key_of(value)
	# Otherwise the argument that looks like a container: `open` and `forget` are
	# command words, so `open(window("joke.dxr"))` arrives as the bare word
	# `window` followed by the filename -- measured, `["window", "joke.dxr"]`.
	# Keying the first non-empty string returns "window", which names nothing,
	# and the call silently does nothing at all.
	for value in args:
		if typeof(value) == TYPE_STRING and ContainerName.is_container(str(value)):
			return str(value)
	# Nothing recognisable: fall back to the last string, which is where a name
	# sits when a command word precedes it, rather than the first.
	for i in range(args.size() - 1, -1, -1):
		if typeof(args[i]) == TYPE_STRING and str(args[i]).strip_edges() != "":
			return str(args[i])
	return ""


static func window_key_of(value: Variant) -> String:
	if typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has(WINDOW_HANDLE):
		return str((value as Dictionary)[WINDOW_HANDLE])
	if typeof(value) == TYPE_STRING:
		return str(value).strip_edges().replace(":", "/").replace("\\", "/") \
			.get_file().get_basename().to_lower()
	return ""


static func is_window_ref(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has(WINDOW_HANDLE)


## Which interpreter a `tell` body should run against.
##
## The interpreter calls this and drops the body when it answers null, so "no
## such window" has to be distinguishable from "the stage": a `tell
## window("jokes.dxr")` naming a file this disc does not have must not run on
## whoever asked. That was the old behaviour and it is what puppeted DAY1's
## channel 3 when the player clicked a joke bottle.
func tell_target(value: Variant) -> Object:
	if preview == null:
		return null
	if not is_window_ref(value):
		# A `tell` at anything that is not a window reference. Director also
		# accepts a script instance here; nothing in this corpus does, and running
		# the body on the current movie is what this change exists to stop.
		return null
	return preview.window_interpreter(window_key_of(value))


## The compiled script a `script(...)` reference names, for `new` (§7.1).
##
## The interpreter cannot resolve this on its own and that is the whole reason
## the method exists: `script("foo")` answers a **packed member reference**, and
## only the preview knows which compiled cast a library number stands for --
## which is `preview/scripts.gd`'s own rule that a member number is per cast and
## the library is part of the key, not a hint. Searching every cast for a script
## at that number is what that module exists to stop.
##
## `{}` when the reference names no script, which is what `new` reports rather
## than building an object that answers every message with nothing.
func script_at(reference: Variant) -> Dictionary:
	if preview == null:
		return {}
	var where: Array = preview.lingo_member_where(reference)
	if where.size() < 2 or int(where[1]) <= 0:
		return {}
	return preview.call("_script_in_lib", int(where[0]), int(where[1]))


## The window a property designator named, brought into existence by being named.
##
## `set the windowType of window "inventor.dir" to 2` arrives here with a bare
## String: the designator spelling contains no `window(...)` call, so nothing has
## created the window yet. Director does not require one — naming a window is
## what makes it exist (§14), which is the rule `lingo_window` implements and
## which `director_preview.gd:2400` states in as many words. Requiring a handle
## instead silently dropped every designator write: `rating` sets `the
## windowType` twelve times and spells all twelve this way, so the window that
## the next line's `open` looks for had never been made.
##
## Returning "" rather than the stage's key for an unnamed window matters —
## `lingo_set_window_prop` treats "" as the stage, and a write meant for a window
## must not land there. That was the defect the window-property change fixed
## once already.
func _named_window_key(which: Variant) -> String:
	if is_window_ref(which):
		return window_key_of(which)
	if typeof(which) == TYPE_STRING and str(which).strip_edges() != "":
		var handle: Dictionary = preview.lingo_window(str(which))
		return str(handle.get(WINDOW_HANDLE, ""))
	return ""


func get_window_prop(which: Variant, prop: String) -> Variant:
	if preview == null:
		return 0
	var key := _named_window_key(which)
	if key == "":
		return 0
	return preview.lingo_window_prop(key, prop)


func set_window_prop(which: Variant, prop: String, value: Variant) -> void:
	if preview == null:
		return
	var key := _named_window_key(which)
	if key == "":
		return
	preview.lingo_set_window_prop(key, prop, value)


# ------------------------------------------------------------------ properties

## One `*Script` assignment, compiled (§6.3 tier 1). See `key_down_compiled`.
##
## Everything is compiled, and a **bare identifier is compiled and also named**.
## Both keys on one record, resolved in that order at dispatch: if the name is a
## handler the movie declares, that handler runs; otherwise the compiled
## statement does, which for a bare word is Lingo's no-argument call and reaches
## the same builtin Director would have reached. Keeping both is what makes
## `set the mouseDownScript to "beep"` work while leaving all 952 of the corpus's
## named sites on the path they have always taken.
##
## `""` installs nothing, which is Director's own way of *removing* a primary
## handler. 0 corpus sites do it; that is not a reason to drop it.
##
## A source that will not compile installs nothing and says so on the log rather
## than throwing: Director reports a bad `do` and carries on, this is the same
## kind of run-time compile, and a movie that assembles a script out of a field
## has to be able to get it wrong without taking the movie with it. There is
## nowhere better to report from -- `LingoDiagnostics` belongs to an interpreter
## and the assignment deliberately does not reach for one (see `Interpreter`).
func _compile_primary(source: String, label: String) -> Dictionary:
	var text := source.strip_edges()
	if text == "":
		return {}
	var failed: Array = []
	var compiled: Dictionary = Interpreter.compile_statements(text, label, failed)
	if compiled.is_empty() and not text.is_valid_identifier():
		push_warning("the %s would not compile: %s" % [
			label, str(failed[0]) if not failed.is_empty() else "empty"])
		print("the %s would not compile: %s" % [
			label, str(failed[0]) if not failed.is_empty() else "empty"])
	if text.is_valid_identifier():
		compiled["name"] = text.to_lower()
	return compiled


## `[game] run_mode` from the config, or "Author". Read through `GameConfig` so
## the launcher's `user://` overlay reaches it like every other setting, and
## cached because a movie may ask on every frame.
static var _run_mode_cached := ""


static func _run_mode() -> String:
	if _run_mode_cached == "":
		var wanted := str(GameConfig.merged().get_value("game", "run_mode", ""))
		_run_mode_cached = wanted if wanted != "" else "Author"
	return _run_mode_cached


func get_system_prop(prop: String) -> Variant:
	if preview == null:
		return 0
	match prop.to_lower():
		"frame":
			# 1-based, like `the lastFrame` beside it and like every frame number
			# a script writes — `director_preview.lingo_frame_number` carries the
			# reference citation and what the raw index cost. Answering the index
			# made `the frame = the lastFrame` unsatisfiable on the last frame and
			# `play frame the frame` walk backwards.
			return preview.lingo_frame_number(preview.current_frame())
		"mouseh":
			return int(preview.stage_mouse().x)
		"mousev":
			return int(preview.stage_mouse().y)
		"mouseloc":
			# **The pair, and its absence is what freezes a software cursor.**
			# `the mouseH` and `the mouseV` were bound and this was not, so a
			# title that reads the pair got VOID -- and the commonest thing to do
			# with the pair is drive a sprite:
			#
			#     set the loc of sprite CursorCh to the mouseLoc
			#
			# That is Itamar Park's `on idle`, and it is the whole of how the
			# title moves its pointer: `InitVariables` calls `HideWindowsCursor()`
			# and channel 100 draws the cursor from then on. With this unbound the
			# assignment took VOID, `set the loc of sprite` needs a pair and drops
			# anything shorter, and the drawn cursor stood still on a stage with
			# no system cursor either -- reported, exactly, as "the mouse doesn't
			# move".
			#
			# A two-element list, like `the clickLoc` above and `the loc of
			# sprite`, so all three read the same way and feed each other.
			var at: Vector2 = preview.stage_mouse()
			return [int(at.x), int(at.y)]
		"clickon":
			return click_sprite
		"currentspritenum":
			# Not `the clickOn` by another name, and the difference is the whole
			# reason both exist: `the clickOn` is the channel the *player* hit and
			# survives the click, while this is the channel whose behaviour is on
			# the stack right now. A behaviour reached by `sendSprite`, by a key
			# event or by a frame message has no click behind it at all.
			return current_sprite_num
		# ------------------------------------------------------- the mouse, live
		#
		# Every one of these is a *read* of hardware or of a timestamp, with no
		# engine state behind it and nothing to get out of step. They are grouped
		# because they were missing together: the live host bound `mouseH`,
		# `mouseV` and `clickOn` and answered VOID for the rest of §6's mouse
		# list, so `if the mouseDown then` -- four sites in this corpus, polling
		# for a button that is still held -- took the false branch for ever.
		#
		# `the mouseUp` is not the complement of `the mouseDown` by accident:
		# Director defines it as "the button is not down", so the two are exact
		# negations and a title can poll either.
		#
		# The left button is the one exception to "a read of hardware with no
		# engine state behind it", and it has to be: these three are polled from
		# `exitFrame`, which runs at the score's rate, and a click is shorter than
		# one score step. Asking the live button alone made the click-to-skip
		# idiom answer false for most real clicks --
		# `director_preview.gd:_mouse_down_seen` has the measurements. Nothing in
		# either corpus spins on `the stillDown` or `the mouseUp` inside a repeat
		# loop, which is what would make holding a press for one step visible as a
		# hang rather than as the fix.
		"mousedown", "stilldown":
			return 1 if preview.mouse_button_down() else 0
		"mouseup":
			return 0 if preview.mouse_button_down() else 1
		"rightmousedown":
			return 1 if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else 0
		"rightmouseup":
			return 0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else 1
		"doubleclick":
			return 1 if double_click else 0
		"clickloc":
			# A point, which the interpreter's `point()` values are two-element
			# lists of -- so `the locH of the clickLoc` reads the way a script
			# expects rather than needing a Vector2 the language has no notion of.
			return [int(click_loc.x), int(click_loc.y)]
		"lastclick":
			# Ticks since, not the timestamp itself: Director's `the lastClick` is
			# an elapsed time, and a script comparing it against a constant is
			# asking "how long has it been". -1 for "no click yet" would compare
			# as recent, so an unclicked session reports a very long time.
			return 0x7FFFFFFF if last_click_ms < 0 else _ticks_since(last_click_ms)
		"lastroll":
			return _ticks_since(last_roll_ms)
		"lastevent":
			return mini(
				0x7FFFFFFF if last_click_ms < 0 else _ticks_since(last_click_ms),
				_ticks_since(last_roll_ms))
		"shiftdown":
			return 1 if (key_flags & MOD_SHIFT) != 0 else 0
		"optiondown":
			# Option on the Mac the game was authored for; Alt is the key that
			# carries it on the platform this runs on.
			return 1 if (key_flags & MOD_ALT) != 0 else 0
		"commanddown":
			# Command is Meta on a Mac keyboard and has no key of its own on a PC
			# one, so Control stands in for it -- and Control therefore answers
			# both this and `the controlDown`, exactly as the reference does
			# (`lingo-the.cpp:594-599` reads KBD_CTRL for `the commandDown` on
			# every platform but the Mac).
			return 1 if (key_flags & (MOD_META | MOD_CTRL)) != 0 else 0
		"controldown":
			return 1 if (key_flags & MOD_CTRL) != 0 else 0
		"timeoutkeydown":
			return 1 if timeout_key_down else 0
		"timeoutmouse":
			return 1 if timeout_mouse else 0
		"timeoutplay":
			return 1 if timeout_play else 0
		"timeoutlength":
			return timeout_length
		"timeoutlapsed":
			return timeout_lapsed_ticks()
		"timeoutscript":
			# The installed source, as the reference answers it: it reads the
			# movie's primary handler string for `kEventTimeout` back out
			# (`lingo-the.cpp:1168`), so a movie can ask what it installed.
			return timeout_script
		"actorlist":
			# The live Array, not a copy. Director's `the actorList` is a list
			# value like any other and `append(the actorList, x)` is how a title
			# adds to it, which needs the reference to be the list the frame loop
			# reads -- a copy here makes the idiom silently do nothing.
			return actor_list
		"perframehook":
			return per_frame_hook
		"updatelock":
			return 1 if update_lock else 0
		"mousecast", "mousemember":
			# The member displayed by the sprite the pointer is over, or -1 for
			# "over nothing" -- which is Director's answer and not 0, because 0 is
			# a real member slot.
			if preview == null:
				return -1
			var rolled: int = preview.lingo_rollover_channel()
			if rolled <= 0:
				return -1
			return preview.lingo_sprite_prop(rolled, "membernum")
		"ticks":
			return int(Time.get_ticks_msec() * 60.0 / 1000.0)
		"milliseconds":
			# Since the machine started, and the one elapsed-time property in the
			# language that is *not* relative to anything a script can move.
			return Time.get_ticks_msec()
		"timer":
			# Ticks since the last reset, not since boot, and ticks rather than
			# milliseconds. See `timer_reset_ms` for what the old answer cost.
			return _ticks_since(timer_reset_ms)
		"searchpath":
			# Answers the list itself. Piposh 1 reads element 1 straight back out
			# of it with `getAt`, so this must never be VOID and never be empty.
			return search_path
		"exitlock":
			return 1 if exit_lock else 0
		"machinetype":
			return 256
		"moviename", "movie":
			# The file as it is actually named on disk. Deliberately not
			# rewritten to the `.dxr` spelling the scripts were authored
			# against: `LingoValue.same_container` makes the comparison succeed
			# either way, so this can stay honest about what is loaded.
			#
			# `the movie` is Director's older spelling of the same property and
			# answers here rather than in a row of its own, so the two cannot
			# drift: 41 sites read it and every one of them got VOID.
			return preview.movie_name()
		"lastkey":
			# Ticks since the last keypress, as `the lastClick` is for the mouse.
			# Both are elapsed times rather than timestamps, which is why the pair
			# read alike and why a script can compare either against a constant.
			return _ticks_since(last_key_ms)
		"pausestate":
			# Whether `pause` is holding the playhead. The read half of the
			# `pause`/`continue` pair, and the only way a script can ask -- there is
			# no `the paused`.
			return 1 if playback_paused else 0
		"beepon":
			return 1 if beep_on else 0
		"soundenabled":
			return 1 if sound_enabled else 0
		"randomseed":
			# Answered by the module that owns the generator. A copy here would be
			# a second seed to keep in step with the sequence it is supposed to
			# describe.
			return Builtins.random_seed()
		"floatprecision":
			return LingoValue.float_precision
		"maxinteger":
			# Director's largest integer, and the idiom is always the same: seed a
			# "smallest so far" loop with it. Unbound it answered VOID, which
			# compares as 0, so every such loop kept its first candidate.
			return 0x7FFFFFFF
		"pi":
			# The same constant `pi()` answers, reached through `the` -- §1.15's
			# spelling and §3's spelling of one value, so they answer from one
			# place rather than two.
			return PI
		"colordepth":
			# Bits per pixel. This renderer composites RGBA8 whatever the movie's
			# palette says, so 32 is a fact about the engine rather than a
			# placeholder; a 1997 script guarding a colour path on `>= 8` takes the
			# branch it was written for.
			return 32
		"colorqd":
			# "Is Color QuickDraw available." Always, here. D2-era art paths test
			# it before drawing in colour at all, and VOID sends them down the
			# 1-bit branch.
			return 1
		"multisound":
			# Whether more than one sound channel can play at once. This engine
			# mixes eight, so the answer is yes -- and a title that asks is
			# deciding whether it may start music under speech.
			return 1
		"memorysize", "freebytes":
			# The same 16 MB `the freeBlock` answers, and answered together on
			# purpose: a script that compares one against the other -- "is the
			# largest block most of the free space" -- gets a consistent pair
			# rather than a number and a VOID.
			return 16 * 1024 * 1024
		"platform":
			# Director's own spelling, which scripts compare literally against
			# "Windows,32" and "Macintosh,PowerPC". Reported for the machine this
			# is actually running on rather than for the one the title was
			# authored against.
			match OS.get_name():
				"macOS":
					return "Macintosh,PowerPC"
				"Windows", "UWP":
					return "Windows,32"
			return "Windows,32"
		"runmode":
			# "Author", "Projector" or "Plugin" in Director, and this port is none
			# of the three -- so the question is which answer leaves a title in the
			# state it expects, not which label fits.
			#
			# **"Author", because that is the position this player is actually in.**
			# A projector *embeds* its movie and does the startup work before the
			# movie runs; this engine opens a bare `.dir` and nothing has set it up.
			# That is precisely the condition a title tests for. Magic Hat:
			#
			#     on startMovie
			#       if not Projector() then
			#         clearGlobals()
			#         if SingleGameMode() then InitProgram("magichat.ini")
			#
			# Answering "Projector" made it skip its own initialisation, wait for a
			# projector that does not exist, and loop its intro for ever instead of
			# reaching its menus. Answering "Author" it reads its ini, takes
			# `startframe = mainmenu` and settles on the menu with no errors.
			#
			# The previous comment argued the other way -- that the Author branch
			# skips the projector's own setup -- and that is true of a *real*
			# projector, which is the thing this port is not. Nothing does that
			# setup here unless the movie does.
			#
			# **Free of risk for the shipped corpus, measured**: `the runMode`
			# appears in 0 of the six titles' scripts, so no Piposh or Rating
			# behaviour depends on either answer. The config key exists for the
			# title that eventually disagrees.
			return _run_mode()
		"applicationpath":
			# The folder the running application lives in, with a trailing
			# separator, as `the moviePath` has. Not the movie's folder -- the two
			# differ the moment a title is run from a disc.
			return OS.get_executable_path().get_base_dir() + "/"
		"stageleft", "stagetop", "stageright", "stagebottom":
			# The stage's rectangle in screen coordinates, one edge per property.
			# Read from the *stage* rather than from whichever movie is asking:
			# inside `tell window("map.dxr")` these still mean the stage, which is
			# the whole reason Director spells them `stage...` instead of making
			# them window properties.
			var stage: Node = preview.stage_preview()
			var edges: Variant = (stage if stage != null else preview) \
				.call("own_window_prop", "rect")
			if typeof(edges) != TYPE_ARRAY or (edges as Array).size() < 4:
				return 0
			var at := ["stageleft", "stagetop", "stageright", "stagebottom"] \
				.find(prop.to_lower())
			return (edges as Array)[at]
		"date", "long date", "short date", "abbr date", "abbrev date", \
		"abbreviated date":
			return _formatted_date(prop.to_lower())
		"time", "long time", "short time", "abbr time", "abbrev time", \
		"abbreviated time":
			return _formatted_time(prop.to_lower())
		"pathname":
			# D2's spelling of `the moviePath`, and the same answer rather than a
			# second one: the two have always meant the folder the movie was opened
			# from, and a port where they disagree is a port where a D2-era script
			# and a D4-era script in the same title build different paths.
			return preview.movie_path()
		"searchpaths":
			# D5's spelling of `the searchPath`. One list, two names -- writing
			# through one and reading back through the other is exactly what a
			# title mixing script vintages does.
			return search_path
		"moviepath":
			# The folder the movie was opened from, with its trailing separator.
			# `strtgame`'s `stonecold()` is the only place this game ever sets
			# `savepath`, and it sets it to exactly this; unbound, every
			# `saveMovie(savepath & "hezsave.dir")` and every
			# `go("doload", savepath & "hezsave.dir")` asked for a filename with
			# a VOID in front of it.
			return preview.movie_path()
		"keycode":
			# Compared as a string in the corpus (`the keyCode = "49"`) and as a
			# number elsewhere, which Lingo's coercion handles either way.
			return key_code
		"key":
			return key_char
		"selstart", "selend":
			# §8.4: **movie properties, not field ones.** One range for the whole
			# movie, pushed into whichever editable text sprite holds focus, which
			# is why setting `the selStart` before focusing a different field
			# behaves oddly in real Director. Bound to the widget rather than to
			# storage so a read after the player has typed answers where the caret
			# actually is.
			return preview.lingo_sel_start() if prop.to_lower() == "selstart" \
				else preview.lingo_sel_end()
		"keydownscript":
			return key_down_script
		"keyupscript":
			return key_up_script
		"mousedownscript":
			return mouse_down_script
		"mouseupscript":
			return mouse_up_script
		"soundlevel":
			# The system volume, 0-7, not a channel property. Seven scripts write
			# it and one reads it back on every frame to place a slider knob: an
			# unbound read answers 0, the knob's `if the soundLevel = N` chain
			# takes no branch, and the control the player just clicked does not
			# move.
			#
			# Reached through `preview` rather than by naming the `AudioDirector`
			# autoload, and that is not a style choice: a tool that builds the
			# preview scene from `_init` compiles this file before the autoloads
			# are registered, and a global singleton named here is a compile
			# error in a file nobody touched. Every other binding in this host
			# goes through `preview` for the same reason.
			return preview.lingo_sound_level()
		"stage":
			# `tell the stage` — the reverse direction of Movie-In-A-Window, and by
			# far the commoner one: 135 of the corpus's 194 `tell` statements say
			# this, all of them written *inside* MAP or SAVELOAD to drive the movie
			# underneath. The stage is a window like any other (§14), so it answers
			# a window reference and `tell` needs no special case for it.
			return stage_handle()
		"centerstage", "windowtype", "modal", "title", "titlevisible", \
		"rect", "drawrect", "sourcerect", "picture":
			# Read on whichever movie is asking. Inside `tell window("x")` that is
			# the window, which is where the 21 `set the centerStage to 1` sites
			# put it and where they mean it. Everything but `centerStage` and
			# `windowType` is unverified — no site in this corpus reads any of them.
			return preview.own_window_prop(prop.to_lower())
		"windowlist":
			# §14. The open windows as window references, back to front, so
			# `repeat with w in the windowList / tell w / … ` works. Unverified.
			var handles: Array = []
			for key in preview.window_keys():
				handles.append({WINDOW_HANDLE: str(key)})
			return handles
		"frontwindow", "activewindow":
			# Director distinguishes them — the front window is the top of the
			# stacking order, the active one is the window with focus — and this
			# port has no separate focus: opening a window raises it and gives it
			# the keys, so the two are the same node. Answers the stage when no
			# window is open, which is what Director does. Unverified.
			var front: Node = preview.call("_front_window")
			return {WINDOW_HANDLE: str(front._window_key)} if front != null else stage_handle()
		"freeblock":
			# Largest free memory block, in bytes. `DAY1 wonder/BehaviorScript 310`
			# refuses to open the map below 12K and `GOLDDEAD BehaviorScript 23`
			# unloads DAY1 below 100K; both guard a 1997 Mac's heap. Unbound this
			# answered VOID, `the freeBlock > 12 * 1024` was false, and the map
			# button played the "no" sound instead of opening the map — which is
			# indistinguishable from the window code not working. Same value the
			# other renderer's host has answered all along (`lingo_host.gd`).
			return 16 * 1024 * 1024

		# ------------------------------------------------- the score, as a movie
		#
		# Director exposes the main channel of the frame the playhead is on as
		# eight ordinary properties, and a movie reads them to find out what the
		# author put there without having to be that frame's script. Every one is
		# already decoded -- `director_score.gd`'s frame snapshot carries the
		# script member, the tempo cell, the palette, the transition and the two
		# sound channels, and `director_labels.gd` carries the markers -- so these
		# are a spelling for facts this port has had all along and nothing could
		# ask for.
		#
		# Read-only here. Director makes the frame properties writable during a
		# **score recording session** (D5+), and this port has no score recording;
		# the write half is recorded in `docs/ENGINE_TODO.md` with what it needs.
		"lastframe":
			return preview._score.frame_count if preview._score != null else 0
		"framelabel":
			# The marker on *this* frame, and "" when the frame carries none --
			# not the marker in force, which is what `marker(0)` answers. Director
			# distinguishes them and a script that tests `the frameLabel = "x"`
			# to decide it has arrived depends on the distinction.
			# `_label_on_frame` takes the number, not the index -- it says so and
			# it was handed the index anyway, so it hunted for a marker one frame
			# past the playhead and answered "" for every frame that carries one.
			# Itamar Park's `Hand script`, `Tele script` and `Study Button script`
			# all open `if not (the frameLabel contains "play") then exit`, so all
			# three buttons in the arcade absorbed their click and did nothing.
			return _label_on_frame(
				preview.lingo_frame_number(preview.current_frame()))
		"labellist":
			# Every marker name in score order, one per line. Director separates
			# them with CR and this port normalises CR to LF everywhere a Lingo
			# string is split (`LingoValue.split_lines`), so `line N of the
			# labelList` reads the same either way.
			var names := PackedStringArray()
			if preview._labels != null:
				for marker in preview._labels.markers:
					var label := str((marker as Dictionary).get("name", ""))
					if label != "":
						names.append(label)
			return "\n".join(names)
		"framescript", "frametempo", "framepalette", "frametransition", \
		"framesound1", "framesound2":
			return _frame_channel(prop.to_lower())

		# ------------------------------------------------- what the host can see
		#
		# Facts the engine already holds and had no spelling for. Each is a read
		# of live state rather than a stored setting, which is the difference
		# between this group and the one below it.
		"rollover":
			# **The no-argument form.** `rollOver(n)` is a different function --
			# "is the mouse over channel n" -- and is a builtin; this is "which
			# channel is the mouse over", 0 for none. §8.15 records that the two
			# spellings are separate functions and this is the half that was
			# missing.
			return preview.lingo_rollover_channel()
		"selection":
			# The text currently selected in whichever field holds focus. `the
			# selStart` and `the selEnd` are the same range as two numbers and
			# were already bound; this is the string between them, which is what
			# a script copying what the player typed reads.
			return preview.lingo_selection()
		"keypressed":
			# The character of the key that is **down now**, "" when none is.
			# Distinct from `the key`, which is the last key pressed and outlives
			# the release: `the keyPressed` is how a repeat loop polls, and
			# reading `the key` for it never ends.
			return key_char if Input.is_anything_pressed() and key_char != "" else ""
		"moviefilesize":
			return preview.movie_file_size()
		"moviefilefreesize":
			return MOVIE_FILE_SLACK
		"desktoprectlist":
			# One rect per screen, in Director's [left, top, right, bottom] list
			# of lists. Read from the display server, so a two-monitor machine
			# answers two entries.
			var screens: Array = []
			for i in DisplayServer.get_screen_count():
				var box := DisplayServer.screen_get_usable_rect(i)
				screens.append([int(box.position.x), int(box.position.y),
					int(box.end.x), int(box.end.y)])
			return screens

		# ------------------------------------------- what the machine can answer
		#
		# 1997 capability probes. Every one of these is a real question with a
		# real answer here, and the answer is the honest one rather than the
		# flattering one: this port has no QuickTime and no Video for Windows, so
		# a movie that guards its digital video behind either takes the branch
		# that does not need it -- which is the branch that works.
		"quicktimepresent", "videoforwindowspresent":
			return 1 if HAS_DIGITAL_VIDEO else 0
		"digitalvideotimescale":
			# The scale `the movieTime of sprite` is reported in when a movie wants
			# one across members that disagree. 0 means each member's own, which is
			# Director's default and the reason this is stored rather than fixed.
			return digital_video_time_scale
		"romanlingo":
			# Whether Lingo's string functions work a byte at a time rather than
			# in a double-byte script. They do here: `director_codepage.gd` maps a
			# single-byte codepage onto Unicode, so `char 3 of` is a byte and
			# TRUE is the truth.
			return 1
		"productname":
			return "Director Player"
		"productversion":
			# What the movies were authored against, which is what a version test
			# in a 1997 script is asking. `the fileVersion` of every container in
			# both corpora is D6.
			return "6.0"
		"username", "organizationname":
			# Director read these from the projector's own registration. There is
			# none, and "" is what an unregistered player answered.
			return ""
		"serialnumber":
			return SERIAL_NUMBER
		"xtras":
			# The Xtras this player has loaded, as a list of their objects — the
			# same registry `xtra(...)` resolves against, so `the number of xtras`
			# and a lookup by name are two questions with one answer. Two are
			# registered, FileIO and BudAPI, and a script scanning the list for a
			# third finds it absent rather than crashing.
			var names: Array = []
			for entry in xtras_loaded:
				names.append((entry as Dictionary).get("object", null))
			return names
		"safeplayer":
			# Shockwave's sandbox. A projector is not sandboxed and answers FALSE,
			# which is what lets a movie's file and `open` paths run at all.
			return 1 if SAFE_PLAYER else 0

		# ----------------------------------------------------- settings, honored
		#
		# Stored *and consulted*, which is the only kind of setting worth binding.
		# `the moveableSprite of sprite` round-tripped perfectly for years and
		# moved nothing, and a movie property stored on this host and read by
		# nobody is the same shape one level up. The rest of Director's settings
		# -- `the buttonStyle`, `the checkBoxType`, `the searchCurrentFolder`, the
		# preload and CPU budgets -- are deliberately *not* bound here for exactly
		# that reason; each is recorded in `docs/ENGINE_TODO.md` with the consumer
		# it is waiting for.
		"trace":
			# Director's statement trace. Honoured by `lingo/lingo_interpreter.gd`,
			# which writes one line per statement into the diagnostics while it is
			# on -- the thing this port has otherwise had to be rebuilt by hand
			# with `print` every time a handler did something unexpected.
			return 1 if LingoDiagnostics.trace else 0
		"tracelogfile":
			# Where that trace goes. "" is Director's own default and means the
			# message window, which here is the diagnostics buffer; a path sends
			# it to a file as well.
			return LingoDiagnostics.trace_log_file
	# The match ran out of arms, so this movie property is not bound here at all.
	# VOID is still the answer -- nothing about what a script sees moves -- and
	# the name is now recorded instead of vanishing. See `_note_movie_prop`.
	_note_movie_prop(prop)
	return null


## A movie property nothing in this port answers, recorded rather than lost.
##
## The third of the three notes, and the last one to exist:
## `director_preview.gd:_note_sprite_prop` covers `the X of sprite`,
## `_note_member_prop` beside it covers `the X of member`, and this covers
## `the X`. All three now report through `LingoDiagnostics`, which declared the
## categories from the day it was written and emitted none of them.
##
## **It lives on the host because the host is the movie's property surface.** The
## two `match` statements above and below are the whole of what this engine binds
## for `the X`, so their fall-throughs *are* the derivation -- there is no list
## to keep in step, and a name gains an arm and leaves the report in one edit.
## That is the same guarantee `sprite_props.gd:consumed` buys with a table, which
## it needs only because `sprite_state.write_prop` accepts every key and so has
## no fall-through to reach.
##
## Both directions, and the write half matters more than it looks. A read that
## answers VOID at least makes an `if` take the false branch and a `put` print
## nothing; a **write** that falls off the end of `set_system_prop` returns
## cleanly, moves nothing, and is indistinguishable from a write that worked --
## which is the shape that shipped as `moveableSprite`, `editableText`,
## `constraint`, `the member of sprite` and `flipH` one entity along.
##
## Reported through the preview's interpreter because that is where the script,
## the handler and the line are; the host has the property and not the location.
## `clearGlobals` above already reaches the interpreter the same way.
func _note_movie_prop(prop: String) -> void:
	if preview == null or preview._interpreter == null:
		return
	preview._interpreter.report(LingoDiagnostics.MOVIE_PROP, prop.to_lower())


## The marker named on exactly this frame, or "".
##
## `the frameLabel` is not `marker(0)`: the second answers the label in force,
## walking back to the last marker at or before the playhead, and the first is
## empty on every frame that does not carry one of its own.
func _label_on_frame(frame: int) -> String:
	if preview == null or preview._labels == null:
		return ""
	for marker in preview._labels.markers:
		var row: Dictionary = marker
		# The port's markers are 0-based and `the frame` is 1-based.
		if int(row.get("frame", -1)) + 1 == frame:
			return str(row.get("name", ""))
	return ""


## The main channel of the frame the playhead is on, by Lingo's own spelling.
##
## Answers a *member number* where Director answers one, and 0 for a frame that
## carries nothing in that cell -- which is what an unset main-channel cell is,
## and is distinguishable from member 0 because there is no member 0.
func _frame_channel(prop: String) -> Variant:
	if preview == null or preview._score == null:
		return 0
	# `current_frame()` is already the score's own index (`director_labels.gd`:
	# 0-based everywhere in the runtime), so the cell wanted is at that index.
	# Subtracting one here read the frame *before* the playhead: every one of
	# these four properties answered the previous frame's cell, and
	# `tools/lingo_movie_surface.gd` agreed with it because it made the same
	# subtraction on the other side of the comparison.
	var record: Dictionary = preview._score.frame(preview.current_frame())
	match prop:
		"framescript":
			var script_member: Variant = record.get("frame_script", null)
			return int(script_member) if script_member != null else 0
		"frametempo":
			# The cell as authored. Director reports the tempo the frame *sets*,
			# so a frame that sets none reports 0 rather than the rate in force --
			# the same distinction `the frameLabel` makes above.
			return int(record.get("tempo", 0))
		"framepalette":
			var palette: Dictionary = record.get("palette", {})
			return int(palette.get("member", 0))
		"frametransition":
			return int(record.get("transition_member", 0))
		"framesound1", "framesound2":
			var want := 1 if prop.ends_with("1") else 2
			for entry in (record.get("sound_channels", []) as Array):
				var row: Dictionary = entry
				if int(row.get("channel", 0)) == want:
					return int(row.get("cast_id", 0))
			return 0
	return 0


## Milliseconds ago, in Director's ticks — 60ths of a second, the unit every
## elapsed-time property in the language reports in.
func _ticks_since(when_ms: int) -> int:
	return int((Time.get_ticks_msec() - when_ms) * 60.0 / 1000.0)


func set_system_prop(prop: String, value: Variant) -> void:
	match prop.to_lower():
		"digitalvideotimescale":
			# Negative is not a scale. Director clamps at 0, which is its own "use
			# each member's" value, so a movie writing nonsense gets the default
			# back rather than a divisor that would invert every time it reports.
			digital_video_time_scale = maxi(LingoValue.to_int(value), 0)
		"selstart", "selend":
			# The other half of §8.4's selection round-trip. Writable, and both
			# ends are clamped against the focused field's own length on the way
			# back out -- a script may legally set a range longer than the text
			# and Director answers what it can honour.
			if preview != null:
				preview.lingo_set_sel(prop.to_lower(), LingoValue.to_int(value))
		"keydownscript", "keyupscript", "mousedownscript", "mouseupscript":
			# §6.3 tier 1, and **the one assignment in the language that changes
			# the event model**. Director compiles the string on assignment
			# (`Movie::setPrimaryEventHandler` -> `replaceCode`), so the compile is
			# in the field's setter and the property below reads back exactly the
			# source that was assigned -- Director answers the string, not the
			# script it became.
			#
			# This used to store a handler *name*, on the recorded grounds that the
			# port had no runtime compile-a-string path. It has one: `do` landed and
			# compiles Lingo at run time, and `LingoInterpreter.compile_statements`
			# is that same path with the same wrapper. A bare name is still a bare
			# name -- see `_compile_primary` for why both forms are kept on one
			# record rather than one being made to stand in for the other.
			var text := LingoValue.to_str(value).strip_edges()
			match prop.to_lower():
				"keydownscript": key_down_script = text
				"keyupscript": key_up_script = text
				"mousedownscript": mouse_down_script = text
				_: mouse_up_script = text
		"soundlevel":
			if preview != null:
				preview.lingo_set_sound_level(LingoValue.to_int(value))
		"beepon":
			beep_on = LingoValue.truthy(value)
		"timeoutkeydown":
			timeout_key_down = LingoValue.truthy(value)
		"timeoutmouse":
			timeout_mouse = LingoValue.truthy(value)
		"timeoutplay":
			timeout_play = LingoValue.truthy(value)
		"timeoutlength":
			timeout_length = LingoValue.to_int(value)
		"timeoutlapsed":
			# **Writable, and the reference says so against the documentation.**
			# `lingo-the.cpp:1496` records that D3.1's manual claims it cannot be
			# set and that D2 and D3 Mac let you anyway, with a shipped title
			# relying on it. Writing it moves the *origin*, so `set the
			# timeoutLapsed to 0` restarts the clock -- which is what a movie
			# writing it means.
			last_timeout_ms = Time.get_ticks_msec() - int(LingoValue.to_int(value) * 1000.0 / 60.0)
		"timeoutscript":
			timeout_script = LingoValue.to_str(value).strip_edges()
		"actorlist":
			# Anything that is not a list empties it, which is how a movie clears
			# the list: `set the actorList to []` and `to 0` are both written.
			actor_list = value if typeof(value) == TYPE_ARRAY else []
		"perframehook":
			# VOID or 0 removes the hook; anything else is stored and
			# `preview/actors.gd` messages it only if it is a script object, so a
			# movie assigning something that cannot answer gets nothing rather
			# than an error every frame.
			per_frame_hook = null if not LingoValue.truthy(value) else value
		"updatelock":
			update_lock = LingoValue.truthy(value)
		"soundenabled":
			# Director stops the device, so turning this off silences what is
			# already playing rather than only what starts next. Nothing here holds
			# the running voices, so the preview is asked to stop them all -- which
			# is the observable half, and without it a movie that mutes mid-line
			# keeps talking.
			sound_enabled = LingoValue.truthy(value)
			if not sound_enabled and preview != null:
				preview.lingo_stop_all_sound()
		"randomseed":
			Builtins.set_random_seed(LingoValue.to_int(value))
		"floatprecision":
			# Director clamps to 0..19 and this does too, rather than letting a
			# script ask for a precision the formatter cannot honour and then
			# reading back a number that does not describe the output.
			LingoValue.float_precision = clampi(LingoValue.to_int(value), 0, 19)
		"searchpaths":
			# D5's spelling. Routed through the same write as `the searchPath`
			# below rather than kept beside it: one list with two names is one
			# write, and a second copy is a second thing to forget to hand to the
			# audio resolver.
			set_system_prop("searchpath", value)
		"timer":
			# `set the timer to 0` is how this corpus resets it -- 91 sites, always
			# paired with the `if the timer > clockspeed` above it. Director stores
			# the *origin* rather than the value, so writing N means "pretend N
			# ticks have passed", which is what `the timer` then answers.
			timer_reset_ms = Time.get_ticks_msec() \
				- int(LingoValue.to_int(value) * 1000.0 / 60.0)
		"searchpath":
			# Director takes a list; a bare string is one path and is wrapped, and
			# anything else empties the search back to its one-empty-element rest
			# state rather than to nothing (see `search_path`).
			if typeof(value) == TYPE_ARRAY:
				search_path = (value as Array).duplicate()
			elif typeof(value) == TYPE_STRING:
				search_path = [str(value)]
			else:
				search_path = [""]
			if search_path.is_empty():
				search_path = [""]
			if preview != null:
				preview.lingo_search_path(search_path)
		"exitlock":
			# The write is the whole of the corpus's use of it: five sites, all
			# setting it, none reading it back. What it *does* is refuse the window
			# manager's quit; `director_preview.gd:_notification` is the consumer.
			exit_lock = LingoValue.to_int(value) != 0
		"trace":
			# Director's statement trace, on and off from inside the movie. The
			# consumer is `lingo_interpreter.gd:_exec`, which is the only place
			# that can see a statement about to run.
			LingoDiagnostics.trace = LingoValue.to_int(value) != 0
		"tracelogfile":
			# Where the trace goes as well as the console. `user://` rather than
			# beside the projector, for the reason `PREFS_DIR` gives: Director's
			# own location is not writable on a modern machine, and a movie that
			# names a bare filename means "somewhere I can write".
			var where := LingoValue.to_str(value).strip_edges()
			if where == "":
				LingoDiagnostics.trace_log_file = ""
			else:
				LingoDiagnostics.trace_log_file = "user://" \
					+ where.replace("\\", "/").get_file()
		"centerstage", "windowtype", "modal", "title", "titlevisible", \
		"rect", "drawrect", "filename":
			# `tell window("map.dxr") / set the centerStage to 1 / end tell` — the
			# statement is a bare movie property and it lands on whichever movie the
			# `tell` routed it to, which is the window. That is why this needs no
			# window argument: being *in* the right movie is the routing.
			if preview != null:
				preview.set_own_window_prop(prop.to_lower(), value)
		_:
			# A movie property with no write arm. Dropped before this existed, and
			# dropped now -- the only change is that the name is recorded. This
			# includes the properties Director makes read-only (`the frame`, `the
			# stageLeft`), which a movie cannot write there either; a refusal and
			# an absence look the same from here and both are worth seeing,
			# because the port has no read-only list for `the X` to tell them
			# apart and inventing one here would be the hand-written table
			# `sprite_props.gd` exists to argue against.
			_note_movie_prop(prop)


## `the locH of sprite N`, and the five properties that are *derived* rather than
## stored.
##
## `the rect`, `left`, `top`, `right` and `bottom` are read-only in Director: they
## are the sprite's drawn rectangle, composed from its position, its registration
## point and its member's size, and a script changes them by moving the sprite
## rather than by assigning to them. This port accepted a write for all five,
## stored it in the override table and let it be read straight back -- so they
## looked implemented from every direction while `sprite_state.effective` merged
## none of them and no read ever reflected where the sprite actually was. `the
## rect of sprite` has 20 corpus sites and `the top of sprite` 4, and every one of
## them was answering a stale override or 0.
##
## Answered here, ahead of the property tables, from the same
## `lingo_sprite_rect` that `intersects`, `within` and `constrainH` measure --
## the whole point being that a script cannot get two different rectangles for
## one sprite depending on which question it asked.
##
## A rect is a four-element list, which is what this port represents Lingo's rect
## with everywhere else (`windows.gd` answers `the rect of window` the same way).
func get_sprite_prop(which: int, prop: String) -> Variant:
	if preview == null:
		return 0
	var low := prop.to_lower()
	match low:
		"rect", "left", "top", "right", "bottom":
			var box: Rect2 = preview.lingo_sprite_rect(which)
			match low:
				"left":
					return int(box.position.x)
				"top":
					return int(box.position.y)
				"right":
					return int(box.end.x)
				"bottom":
					return int(box.end.y)
			return [int(box.position.x), int(box.position.y),
				int(box.end.x), int(box.end.y)]

		# ---------------------------------------------- the digital-video playhead
		#
		# Fourteen names that are not properties of the *drawn sprite* at all --
		# they describe the movie playing in the channel, which is why they are
		# answered here rather than merged into `preview/channel.gd:FIELDS`.
		# Putting them in the channel record would subject them to the score's
		# auto-puppet release rules (§5.3), and Director applies none of those to a
		# playhead: a video does not stop because the score rewrote the channel's
		# position on the next frame.
		#
		# `scenes/preview/media.gd` is the model, and its header is the honest
		# account of what plays here, which is nothing: the properties round-trip
		# and there is no media that can be decoded to move.
		"movierate", "movietime", "starttime", "stoptime", "volume", \
		"currenttime", "mostrecentcuepoint", "tracktext", "trackenabled", \
		"settrackenabled", "tracknextkeytime", "tracknextsampletime", \
		"trackpreviouskeytime", "trackprevioussampletime":
			var answer: Variant = Media.read_sprite(preview, which, low)
			return answer if answer != null else 0

		# ------------------------------------------- the video Xtra's own surface
		#
		# `sprite(N).getPlaybackEvent`, `sprite(N).play()` and `sprite(N).stop()`
		# — not Director's names but the media Xtra's, and the ones Magic Hat's
		# intro and album are driven by. `preview/media.gd` says why the two
		# commands arrive as property reads.
		#
		# **`null` is passed through here rather than folded to 0**, which is the
		# one difference from the arm above and is the whole reason this is a
		# separate arm. `docs/DIGITAL_VIDEO.md` §3 forbids answering
		# `getPlaybackEvent` with a plausible value while nothing can play, and
		# VOID is what the name answered when it was bound to nothing at all —
		# so a member with no media goes on producing exactly the value all three
		# of that title's video frames already skip on. Folding it to 0 would take
		# the same branch in these two movies and be a different value to
		# `voidP()` in any title nobody has run yet.
		"getplaybackevent", "play", "stop":
			return Media.read_sprite(preview, which, low)
	return preview.lingo_sprite_prop(which, low)


## The five derived properties above are **read-only in Director**, so a write is
## refused here rather than passed on.
##
## That is not tidiness. `sprite_state.write_prop` stores any key at all, so a
## write that reaches it round-trips through `read_prop` and looks like it
## worked; with the read now answering the sprite's real rectangle, a stored
## override would be a value the script can set, cannot read back, and cannot
## discover was dropped. Refusing it at the seam leaves one answer to the
## question "where is this sprite", which is the whole point of the read above.
const SPRITE_READ_ONLY := ["rect", "left", "top", "right", "bottom"]


func set_sprite_prop(which: int, prop: String, value: Variant) -> void:
	if preview == null:
		return
	var low := prop.to_lower()
	if SPRITE_READ_ONLY.has(low):
		return
	# The playhead before the sprite record, matching the read above. A write that
	# fell through to `lingo_set_sprite_prop` would land in the channel's override
	# table, read back from there, and be invisible to the model that owns it --
	# which is the `moveableSprite` shape, one entity along.
	if Media.write_sprite(preview, which, low, value):
		return
	preview.lingo_set_sprite_prop(which, low, value)


func get_member_prop(which: Variant, cast: Variant, prop: String) -> Variant:
	if preview == null:
		return 0
	return preview.lingo_member_prop(which, str(cast), prop.to_lower())


## `member("save1").editable = 1` and `set the text of member "x"`.
##
## This was a bare `pass` — an **unreported** no-op, which is the worst shape a
## gap can take here: an unbound write is counted and named, and this one
## returned cleanly and did nothing while `docs/LINGO_SURFACE.md` §9.3 listed
## both properties as implemented. The doc was describing the *retired* renderer's
## host, which did bind them and has since been deleted.
##
## `editable` is the write that was actually being lost: five sites, all in
## `SAVELOAD.dir`, and they decide which of the eight save slots the player can
## type a name into. With it dropped the authored flag alone decided, so `save1`
## was editable for ever and the other seven never — a slot could be chosen and
## then not named.
##
## `text` had 0 sites, and is a second spelling of a path that already worked:
## `put x into field "y"` goes through `set_field`. Built anyway, because "0 uses
## in the corpus" is a reason to build something last (`AGENTS.md`).
func set_member_prop(which: Variant, cast: Variant, prop: String, value: Variant) -> void:
	if preview == null:
		return
	preview.lingo_set_member_prop(which, str(cast), prop.to_lower(), value)


## A sound channel's own properties, `the volume of sound 2` above all.
## `the <prop> of castLib N` (§5.1). VOID for anything this port does not bind,
## and the miss is reported -- `the preLoadMode` and `the selection` are absent
## on purpose and `preview/cast_libs.gd` says why for each.
func get_cast_prop(which: Variant, prop: String) -> Variant:
	if preview == null:
		return null
	var value: Variant = CastLibs.read_prop(which, prop, preview._table)
	if value == null:
		_note_movie_prop("%s of castLib" % prop.to_lower())
	return value


## A cast library has no writable property in this port. Reported rather than
## dropped: Director makes `name`, `fileName` and `number` read-only and this
## does not bind `the preLoadMode`, so a movie writing any of them is asking for
## something that is not here and a log should say so.
func set_cast_prop(which: Variant, prop: String, _value: Variant) -> void:
	_note_movie_prop("set %s of castLib %s" % [prop.to_lower(), LingoValue.to_str(which)])


func get_sound_prop(channel: int, prop: String) -> Variant:
	if preview == null:
		return 0
	return preview.lingo_sound_prop(channel, prop.to_lower())


func set_sound_prop(channel: int, prop: String, value: Variant) -> void:
	if preview != null:
		preview.lingo_set_sound_prop(channel, prop.to_lower(), value)


func get_field(name: String, cast: Variant) -> Variant:
	if preview == null:
		return ""
	return preview.lingo_field(name, str(cast))


## `put x into field "y"`. Was a no-op, which was invisible while nothing drew
## fields: the value went nowhere, `field "y"` read back the authored placeholder,
## and the screen showed nothing either way. With fields rendered, dropping the
## write is the difference between a live score and one frozen at `000`.
func set_field(name: String, cast: Variant, value: Variant) -> void:
	if preview != null:
		preview.lingo_set_field(name, str(cast), LingoValue.to_str(value))


## `the <prop> of field "x"` and `set the <prop> of field "x" to v`.
##
## A field designator carries a property in Director and this port had no
## spelling for it: the interpreter sent both directions to `get_field` /
## `set_field`, which know only the text, so every property name answered the
## text and every write replaced it. `lingo-the.cpp:2334-2398` is the rule --
## `getTheField`/`setTheField` resolve the designator to a member and then read
## or write *that member's* property. `preview.lingo_field_prop` therefore lands
## on the same code `the <prop> of member` does.
func get_field_prop(name: String, cast: Variant, prop: String) -> Variant:
	if preview == null:
		return ""
	return preview.lingo_field_prop(name, str(cast), prop.to_lower())


func set_field_prop(name: String, cast: Variant, prop: String, value: Variant) -> void:
	if preview != null:
		preview.lingo_set_field_prop(name, str(cast), prop.to_lower(), value)


func member_number(which: Variant, cast: Variant) -> Variant:
	if preview == null:
		return 0
	return preview.lingo_member_number(which, str(cast))


# --------------------------------------------------------------- date and time
#
# `the date` and `the time`, in Director's own three shapes each. The adjective
# is part of the property phrase -- `the long date`, `the abbrev time` -- and the
# parser carries it through to here, which it did not before: it read the last
# word of the phrase and threw the adjective away, so all six spellings arrived
# as `date` or `time` and the long and short forms were the same string.
#
# Written against the calendar rather than transcribed: Director asks the system
# for a broken-down local time and lays the fields out in the US formats below.
# The month is 1-based here; the reference's own short-date format indexes it
# 0-based, which its neighbouring comment contradicts.

const MONTHS := ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
	"Friday", "Saturday"]


## `the date`     8/6/26            -- and `the short date`, which is the same
## `the long date`      Thursday, August 6, 2026
## `the abbreviated date`  Thu, Aug 6, 2026  -- and `abbrev`, and `abbr`
func _formatted_date(prop: String) -> String:
	var now := Time.get_datetime_dict_from_system()
	var month := clampi(int(now["month"]), 1, 12)
	var day := int(now["day"])
	var year := int(now["year"])
	# `weekday` is 0 for Sunday, which is the order `WEEKDAYS` is written in.
	var weekday := clampi(int(now["weekday"]), 0, 6)
	if prop.begins_with("long"):
		return "%s, %s %d, %d" % [WEEKDAYS[weekday], MONTHS[month - 1], day, year]
	if prop.begins_with("abbr"):
		return "%s, %s %d, %d" % [
			WEEKDAYS[weekday].substr(0, 3), MONTHS[month - 1].substr(0, 3), day, year]
	return "%d/%d/%02d" % [month, day, year % 100]


## `the time`     3:45 PM           -- and `the short time`, and `the abbrev time`
## `the long time`      3:45:12 PM
func _formatted_time(prop: String) -> String:
	var now := Time.get_datetime_dict_from_system()
	var hour := int(now["hour"])
	var suffix := "AM" if hour < 12 else "PM"
	# Twelve, not zero. Director shows midnight as 12:00 AM and noon as 12:00 PM;
	# a bare `hour % 12` shows both as 0, which is not a time anybody writes.
	var shown := hour % 12
	if shown == 0:
		shown = 12
	if prop.begins_with("long"):
		return "%d:%02d:%02d %s" % [shown, int(now["minute"]), int(now["second"]), suffix]
	return "%d:%02d %s" % [shown, int(now["minute"]), suffix]
