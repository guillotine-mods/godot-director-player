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

const ContainerName := preload("res://director/director_container.gd")

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
## Director's movie-wide key handler: a handler *name*, run ahead of everything
## else on a keypress. 46 scripts in this game set it, most to `fromnow`.
var key_down_script := ""
## Live only for the duration of a key dispatch. -1 rather than 0 because 0 is a
## real Mac key code (the `A` key), so 0 would read as a keypress that never
## happened.
var key_code := -1
var key_char := ""

## Bound to something real.
const HANDLED := [
	"go", "sound", "puppetsound", "puppetsprite", "updatestage", "cursor",
	"nothing", "dontpassevent", "beep", "delay", "preloadmember", "preload",
	"unloadmember", "unload", "set", "alert", "halt", "quit",
	"window", "open", "close", "forget",
]
## Answer VOID rather than nothing: these are real Director builtins this host
## has no state to implement, and letting them report as unbound would drown the
## ones that genuinely are.
const IGNORED := [
	"updatestage", "beep", "delay", "preloadmember",
	"preload", "unloadmember", "unload", "alert", "cursor", "nothing",
	"dontpassevent", "puppetsprite", "halt", "quit", "starttimer",
	# `cursor` is NOT here any more — see the match above.
	# Bound deliberately inert rather than left unbound. An unbound name is
	# reported as a gap every time it is reached, which buries the ones that
	# matter; these are real Director builtins this preview has no state to
	# implement, and answering VOID is the honest response.
	#
	# `pass` and `stopEvent` control message propagation, which is only
	# equivalent here by accident: this dispatcher stops at the first handler
	# that answers, so there is nothing further along to suppress. If the
	# hierarchy ever queues the whole chain the way Director does, these stop
	# being no-ops and become the mechanism.
	"pass", "stopevent", "printfrom", "savemovie", "unloadmovie",
	"clearglobals", "showglobals", "showlocals",
	"puppettempo", "unloadcast", "preloadcast", "preloadmovie", "restart",
	"shutdown", "abort", "continue", "installmenu", "setcallback",
]


func owns_global(name: String) -> bool:
	return globals.has(name.to_lower())


func get_global(name: String) -> Variant:
	return globals.get(name.to_lower(), 0)


func set_global(name: String, value: Variant) -> void:
	globals[name.to_lower()] = value


## Nothing here overrides a script; the real host does, for the walk machine.
func is_native_handler(_name: String) -> bool:
	return false


func call_builtin(name: String, args: Array) -> Variant:
	var low := name.to_lower()
	reached[low] = int(reached.get(low, 0)) + 1
	match low:
		"go":
			return _go(args)
		"sound":
			return _sound(args)
		"puppetsound":
			# `puppetSound <channel>, <member>`, and the one-argument form,
			# which is channel 1. The argument is a **cast member**, not a
			# file — this used to route to `sound playFile`, which would have
			# looked for a file named after a member and, worse, claimed
			# nothing: `puppetSound` takes the channel off the score until
			# `puppetSound <channel>, 0` gives it back.
			if preview == null:
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
			if preview != null:
				preview.lingo_hold()
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
				preview.lingo_play_done()
				return 0
			preview.lingo_play_push(args)
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
			var which := LingoValue.to_int(args[0]) if not args.is_empty() else 0
			return 1 if preview.lingo_rollover(which) else 0
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
			if preview == null or args.is_empty():
				return 0
			return preview.lingo_marker(LingoValue.to_int(args[0]))
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
			var to_open := _first_window_key(args)
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
			var to_shut := _first_window_key(args)
			if to_shut != "":
				preview.lingo_forget_window(to_shut, low == "forget")
			return 0
	if IGNORED.has(low):
		return 0
	unbound[low] = int(unbound.get(low, 0)) + 1
	return null


## `go to the frame`, `go to frame N`, `go(marker(0))`, `go "label"`.
##
## The first is why a Director room sits still at all: the frame script's
## `exitFrame` sends the playhead back to where it already is, every tick. A
## preview without it runs the score off the end of the room, which looks like a
## rendering fault and is the absence of this one call.
func _go(args: Array) -> Variant:
	if preview == null:
		return 0
	var words: Array = []
	for a in args:
		words.append(str(a).to_lower() if typeof(a) == TYPE_STRING else a)
	# `to` is a bare command word and carries no meaning here. The type test is
	# not decoration: this array mixes the command's bare words with evaluated
	# arguments, and GDScript raises on `int != String` rather than answering
	# true — so `go to marker(+1)` threw on this line every time and the
	# playhead never moved, with the error buried in a lambda.
	var kept: Array = []
	for w in words:
		if typeof(w) == TYPE_STRING and str(w) == "to":
			continue
		kept.append(w)
	words = kept
	if words.is_empty():
		return 0

	# A movie name can arrive in either shape: `go to movie "day1.dir"` puts the
	# bare word `movie` first, and `go(1, "day1.dir")` puts the frame first and
	# the file second. Both are in this game, so the file is found by looking
	# like one rather than by its position.
	var movie := ""
	var where: Variant = null
	for w in words:
		if typeof(w) == TYPE_STRING:
			var text := str(w)
			if text.ends_with(".dir") or text.ends_with(".dxr") or text.ends_with(".cst"):
				movie = text
				continue
			if text == "movie":
				continue
			if where == null:
				where = text
		elif where == null:
			where = w
	if movie != "":
		preview.lingo_go_movie(movie, where)
		return 0

	var first: Variant = words[0]
	if typeof(first) == TYPE_STRING:
		match str(first):
			"the frame", "frame":
				# `go to frame N` names a number; `go to the frame` does not.
				if words.size() >= 2 and typeof(words[1]) != TYPE_STRING:
					preview.lingo_go_frame(LingoValue.to_int(words[1]))
					return 0
				preview.lingo_hold()
				return 0
			"loop":
				preview.lingo_hold()
				return 0
			"next", "previous":
				# Relative score navigation, which nothing here models yet.
				# Holding is closer to right than running on into unrelated
				# frames, and it is visible rather than silent.
				preview.lingo_hold()
				return 0
		preview.lingo_go_label(str(first))
		return 0
	preview.lingo_go_frame(LingoValue.to_int(first))
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
	var verb := str(args[0]).to_lower()
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
static func _first_window_key(args: Array) -> String:
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
			return window_key_of(value)
	# Nothing recognisable: fall back to the last string, which is where a name
	# sits when a command word precedes it, rather than the first.
	for i in range(args.size() - 1, -1, -1):
		if typeof(args[i]) == TYPE_STRING and str(args[i]).strip_edges() != "":
			return window_key_of(args[i])
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


func get_window_prop(which: Variant, prop: String) -> Variant:
	if preview == null or not is_window_ref(which):
		return 0
	return preview.lingo_window_prop(window_key_of(which), prop)


func set_window_prop(which: Variant, prop: String, value: Variant) -> void:
	if preview == null or not is_window_ref(which):
		return
	preview.lingo_set_window_prop(window_key_of(which), prop, value)


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
		"ticks":
			return int(Time.get_ticks_msec() * 60.0 / 1000.0)
		"milliseconds", "timer":
			return Time.get_ticks_msec()
		"machinetype":
			return 256
		"moviename":
			# The file as it is actually named on disk. Deliberately not
			# rewritten to the `.dxr` spelling the scripts were authored
			# against: `LingoValue.same_container` makes the comparison succeed
			# either way, so this can stay honest about what is loaded.
			return preview.movie_name()
		"keycode":
			# Compared as a string in the corpus (`the keyCode = "49"`) and as a
			# number elsewhere, which Lingo's coercion handles either way.
			return key_code
		"key":
			return key_char
		"keydownscript":
			return key_down_script
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
	return null


func set_system_prop(prop: String, value: Variant) -> void:
	match prop.to_lower():
		"keydownscript":
			key_down_script = LingoValue.to_str(value).strip_edges()
		"soundlevel":
			if preview != null:
				preview.lingo_set_sound_level(LingoValue.to_int(value))
		"centerstage", "windowtype", "modal", "title", "titlevisible", \
		"rect", "drawrect", "filename":
			# `tell window("map.dxr") / set the centerStage to 1 / end tell` — the
			# statement is a bare movie property and it lands on whichever movie the
			# `tell` routed it to, which is the window. That is why this needs no
			# window argument: being *in* the right movie is the routing.
			if preview != null:
				preview.set_own_window_prop(prop.to_lower(), value)


func get_sprite_prop(which: int, prop: String) -> Variant:
	if preview == null:
		return 0
	return preview.lingo_sprite_prop(which, prop.to_lower())


func set_sprite_prop(which: int, prop: String, value: Variant) -> void:
	if preview != null:
		preview.lingo_set_sprite_prop(which, prop.to_lower(), value)


func get_member_prop(which: Variant, cast: Variant, prop: String) -> Variant:
	if preview == null:
		return 0
	return preview.lingo_member_prop(which, str(cast), prop.to_lower())


func set_member_prop(_which: Variant, _cast: Variant, _prop: String, _value: Variant) -> void:
	pass


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
