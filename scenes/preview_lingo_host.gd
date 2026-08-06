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
]
## Answer VOID rather than nothing: these are real Director builtins this host
## has no state to implement, and letting them report as unbound would drown the
## ones that genuinely are.
const IGNORED := [
	"puppettransition", "updatestage", "beep", "delay", "preloadmember",
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
	"clearglobals", "showglobals", "showlocals", "puppetpalette",
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
			# `puppetSound <channel>, <file>` and the one-argument form.
			if args.size() >= 2:
				return _play(LingoValue.to_int(args[0]), str(args[1]))
			if args.size() == 1:
				return _play(1, str(args[0]))
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


## `sound playFile <channel>, <file>` — how every sound in this game is played.
## The score's own sound channels are empty in all 61 movies.
func _sound(args: Array) -> Variant:
	if args.is_empty():
		return 0
	var verb := str(args[0]).to_lower()
	if verb == "playfile" and args.size() >= 3:
		return _play(LingoValue.to_int(args[1]), str(args[2]))
	if verb == "stop":
		if preview != null:
			preview.lingo_stop_sound(LingoValue.to_int(args[1]) if args.size() >= 2 else 0)
		return 0
	return 0


func _play(channel: int, file: String) -> Variant:
	if preview != null:
		preview.lingo_play_sound(channel, file)
	return 0


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
		"keycode":
			# Compared as a string in the corpus (`the keyCode = "49"`) and as a
			# number elsewhere, which Lingo's coercion handles either way.
			return key_code
		"key":
			return key_char
		"keydownscript":
			return key_down_script
	return null


func set_system_prop(prop: String, value: Variant) -> void:
	match prop.to_lower():
		"keydownscript":
			key_down_script = LingoValue.to_str(value).strip_edges()


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


func set_field(_name: String, _cast: Variant, _value: Variant) -> void:
	pass


func member_number(which: Variant, cast: Variant) -> Variant:
	if preview == null:
		return 0
	return preview.lingo_member_number(which, str(cast))
