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
const Grammar := preload("res://lingo/compile/lingo_grammar.gd")

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
## Director's movie-wide key handler: a handler *name*, run ahead of everything
## else on a keypress. 46 scripts in this game set it, most to `fromnow`.
var key_down_script := ""
## The release half of the same mechanism (§8.2 tier 1). Measured rather than
## assumed: `tools/key_script_survey.gd -- --all` finds `the keyUpScript` set at
## **10 sites in Rating and 195 in Piposh Dream**, against 0 in Piposh 2 — so a
## port that had only the down half was right about the title it was built on and
## silently deaf in two of the other five. Rating's `ARCADE1.dir` member 20 does
## `set the keyUpScript to "normalkeysx"`, and `normalkeysx` is the handler that
## leaves a timed scene: with no key-up path at all, those rooms could not be left
## by the key that leaves them however free F10 was made.
var key_up_script := ""
## The mouse half of the same mechanism (§6.3 tier 1). Nothing in this corpus
## sets either, so both are bound for the engine's sake -- see the note on the
## write, which records that Director's own value is a source string and this is
## a handler name.
var mouse_down_script := ""
var mouse_up_script := ""
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

# --------------------------------------------- what this packaging can answer
#
# Five facts about the *player* rather than about the movie, each named here
# rather than written as a bare constant in its arm. That is not decoration: a
# read arm whose whole body is `return 0` is indistinguishable from a stub, to a
# reader and to `tools/lingo_surface_audit.gd` alike, and every one of these is a
# real answer that a subsystem landing later has to come back and change. Naming
# it puts the answer and the reason in one place and leaves exactly one line to
# edit when it stops being true.

## `the quickTimePresent`, `the videoForWindowsPresent`. There is no digital
## video in this port at all -- no member type is decoded for it, no track
## properties are bound, and `docs/ENGINE_TODO.md` records what it would take. A
## movie that guards its video behind either of these takes the branch that does
## not need it, which is the branch that works.
const HAS_DIGITAL_VIDEO := false

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

## `the xtras` -- the Xtras this player has loaded. None are implemented (§7.3),
## and the empty list is what a movie scanning for one reads.
var xtras_loaded: Array = []


## `the beepOn` -- while false, `beep` is silent. D2, and one of the few movie
## settings whose whole observable effect is on another builtin, which is why it
## is bound with the thing it gates rather than stored and forgotten.
var beep_on := true

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
	"preload", "preloadcast", "preloadmember", "preloadmovie", "clearglobals",
	"externalparamcount", "externalparamname", "externalparamvalue",
	"frameready", "ramneeded", "getvolumes", "version",
	"moveablesprite", "editabletext", "immediatesprite", "spritebox",
	"sendsprite", "sendallsprites",
]
## Answer VOID rather than nothing: these are real Director builtins this host
## has no state to implement, and letting them report as unbound would drown the
## ones that genuinely are.
const IGNORED := [
	"updatestage",
	"unloadmember", "unload", "nothing",
	# `updateStage` is the one name in this list whose absence a player *can*
	# notice, and it is here after the alternative was measured rather than
	# assumed. Director redraws the stage inside the call and returns, so a
	# `repeat` loop that moves a sprite and calls this animates; 3,717 sites.
	#
	# Godot cannot present synchronously from inside a handler. `queue_redraw()`
	# marks the canvas item dirty and pushes `NOTIFICATION_DRAW` onto the message
	# queue, which is flushed at the end of the process frame, and GDScript has
	# no way to flush it. `RenderingServer.force_draw()` is the obvious candidate
	# and does not help: it redraws the *viewports* from whatever commands the
	# canvas items already hold, and it does not re-run `_draw`. Measured on
	# 4.7.1, headless and windowed alike -- `queue_redraw()` followed by
	# `force_draw()` and by `force_draw(false)` left a Node2D's `draw` signal
	# emission count unchanged, at one, from the frame before.
	#
	# So a real arm would have to paint through `RenderingServer`'s immediate
	# API instead of through `_draw`, which is the whole of `stage_paint.gd`,
	# `sprite_art.gd`, `text_art.gd`, `film_loop_view.gd` and `trails.gd`. Until
	# that exists there is nothing to bind: `queue_redraw()` is already called
	# from forty sites across the player, including once per score step and once
	# per click, so an arm that only requested a redraw would change nothing a
	# movie can see while reading as implemented from every direction. That is
	# the `intersects` shape and it is worse than this row staying red.
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
	"puppettempo", "unloadcast", "restart",
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
			# `the beepOn` is the movie's own switch over exactly this call, and it
			# is checked here rather than stored and ignored -- a setting nothing
			# consults is a setting that is not implemented.
			if not beep_on:
				return 0
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
			if args.is_empty():
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
			var frame_index: int = preview.current_frame() - 1
			for channel in channels:
				var script: Dictionary = preview.call(
					"_sprite_script", int(channel), frame_index)
				if not script.is_empty():
					preview.call("_dispatch", handler, script)
			return 0
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
	if typeof(first) != TYPE_STRING:
		preview.lingo_go_frame(LingoValue.to_int(first))
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

func get_system_prop(prop: String) -> Variant:
	if preview == null:
		return 0
	match prop.to_lower():
		"frame":
			return preview.current_frame()
		"mouseh":
			return int(preview.stage_mouse().x)
		"mousev":
			return int(preview.stage_mouse().y)
		"clickon":
			return click_sprite
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
			return 1 if Input.is_key_pressed(KEY_SHIFT) else 0
		"optiondown":
			# Option on the Mac the game was authored for; Alt is the key that
			# carries it on the platform this runs on.
			return 1 if Input.is_key_pressed(KEY_ALT) else 0
		"commanddown":
			return 1 if Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL) else 0
		"controldown":
			return 1 if Input.is_key_pressed(KEY_CTRL) else 0
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
			# "Author", "Projector" or "Plugin" in Director. This port is never the
			# authoring environment, and the distinction matters: a script that
			# takes the "Author" branch skips the projector's own setup.
			return "Projector"
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
			return _label_on_frame(preview.current_frame())
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
			# The Xtras this player has loaded, as a list. None: no Xtra is
			# implemented (§7.3), so the honest answer is the empty list and a
			# script scanning it for one finds it absent rather than crashing.
			return xtras_loaded
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
	return null


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
	var record: Dictionary = preview._score.frame(preview.current_frame() - 1)
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
		"selstart", "selend":
			# The other half of §8.4's selection round-trip. Writable, and both
			# ends are clamped against the focused field's own length on the way
			# back out -- a script may legally set a range longer than the text
			# and Director answers what it can honour.
			if preview != null:
				preview.lingo_set_sel(prop.to_lower(), LingoValue.to_int(value))
		"keydownscript":
			key_down_script = LingoValue.to_str(value).strip_edges()
		"keyupscript":
			# The same storage-as-a-name divergence the mouse pair below records:
			# Director holds a string of Lingo source and compiles it on
			# assignment, and every site in either corpus assigns a bare handler
			# name (`normalkeysx`, `normalkeys2`, `normalkeys3`).
			key_up_script = LingoValue.to_str(value).strip_edges()
		"mousedownscript", "mouseupscript":
			# §6.3 tier 1. Stored as a **handler name**, exactly as this port
			# already stores `the keyDownScript`, and that is a divergence worth
			# stating rather than hiding: Director's primary-handler properties
			# hold a *string of Lingo source*, compiled on assignment into a
			# synthetic script. This port has no runtime compile-a-string path, so
			# a name is what it can honour, and every site in this corpus that
			# sets `the keyDownScript` sets it to a name -- `fromnow`, `gomenu` --
			# which is why the shortcut has held so far. Nothing sets either mouse
			# one, so the divergence is unexercised as well as unfixed.
			var name := LingoValue.to_str(value).strip_edges()
			if prop.to_lower() == "mousedownscript":
				mouse_down_script = name
			else:
				mouse_up_script = name
		"soundlevel":
			if preview != null:
				preview.lingo_set_sound_level(LingoValue.to_int(value))
		"beepon":
			beep_on = LingoValue.truthy(value)
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
	if OS.has_environment("TRACE_VIS") and prop.to_lower() == "visible":
		print("VISWRITE ch%d = %s  handler=%s" % [which, str(value), str(preview._interpreter.get("_handler_name")) if preview != null and preview._interpreter != null else "?"])
	if preview == null:
		return
	var low := prop.to_lower()
	if SPRITE_READ_ONLY.has(low):
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
