class_name LingoInterpreter
extends RefCounted
## Tree-walking interpreter for the ASTs that tools/lingo_compile.py produces.
##
## Everything Director-specific goes through `host`, so this file is testable on
## its own and the engine bindings stay in one place (lingo/lingo_host.gd).
## The host must provide:
##
##   get_field(name, cast) -> String
##   set_field(name, cast, text) -> void
##   get_sprite_prop(channel, prop) -> Variant
##   set_sprite_prop(channel, prop, value) -> void
##   get_member_prop(which, cast, prop) -> Variant
##   set_member_prop(which, cast, prop, value) -> void
##   member_number(which, cast) -> int
##   get_system_prop(prop) -> Variant
##   set_system_prop(prop, value) -> void
##   get_sound_prop(channel, prop) -> Variant
##   set_sound_prop(channel, prop, value) -> void
##   call_builtin(name, args) -> Array  # [handled: bool, value: Variant]
##
## The list is the contract, not a comment: a host missing one of these used to
## fail silently, because `_host_call` returns null both for "no such method" and
## for "handled, nothing to say". Two of them were absent from `lingo_host.gd`
## for that reason (`docs/bugs-closed.md` 27), and a missing method is now
## reported rather than discarded.

enum Flow { NORMAL, EXIT_REPEAT, NEXT_REPEAT, RETURN, ABORT, SUSPEND }

## Runaway guard. `repeat while` with a condition the host never changes would
## otherwise hang the frame.
const MAX_STEPS := 400000

## How often a spinning repeat lets the platform breathe, in milliseconds.
##
## **A loop that polls live input is a Director idiom, not a bug**, and it only
## works where the polled thing keeps changing while the loop runs. Director's
## `the mouseDown` is a hardware read -- ScummVM spells the same thing
## `g_system->getEventManager()->getButtonState()` in `lingo-the.cpp:865` -- so
## `repeat while the mouseDown` in a `mouseDown` handler ends when the player
## lets go, and the standard Director drag loop is built out of exactly that.
##
## Here the handler runs on Godot's main thread, inside `_input`, and Godot's
## button state is only written by the main loop that the handler is blocking.
## So the poll can never observe the release: `itamar-magichat`'s
## `ItemMouseDown` (objects.cst, `Screen items functions`, line 114) spun for
## 400,000 steps and 16 wall-clock seconds on **every** click of its main menu,
## with the window's message pump dead and Windows reporting the process as not
## responding, until this guard aborted the handler. That is the whole of the
## reported freeze.
##
## The fix is to give the platform its turn: `host.breathe()` pumps the OS event
## queue so that the live properties this loop is watching actually move. The
## interval is a compromise -- often enough that a release is seen within a
## frame, rarely enough that a `repeat with i = 1 to 10000` doing arithmetic
## does not pay for a system call per iteration.
const BREATHE_MS := 8

## Cheap pre-filter for the wall-clock check above: only every 64th step of a
## loop asks the clock at all. `Time.get_ticks_msec()` is not expensive, but it
## is not free either and this is the interpreter's hottest path.
const BREATHE_EVERY := 64

var globals: Dictionary = {}
var host: Object = null
var item_delimiter: String = ","
var errors: PackedStringArray = PackedStringArray()
## **How many runtime faults have been raised since this interpreter was built**,
## and the half of `bugs.md` 59 a harness can assert on.
##
## `errors` is the last *dispatch*'s faults and is cleared at the start of the
## next one -- `reset_steps` runs at the head of `preview/scripts.gd:dispatch`,
## `preview/event_chain.gd:run` and the thaw, and one score step dispatches
## `idle`, `exitFrame`, `prepareFrame` and `enterFrame` back to back inside a
## single process frame. So a fault raised in any of them but the last is gone
## before anything outside the interpreter can look, and no tool in `tools/`
## could answer "did any script fault while that room ran".
##
## Half of the sink already existed: `reset_steps` drains to `print` through
## `_reported`, which survives the dispatch, so a fault is at least in the run's
## output. What was missing is a *number*, because a harness cannot assert on
## stdout. These two are it, and neither is touched by `reset_steps`:
##
##   `error_total`   every raise, including the ones past `errors`' 50-entry cap
##                   and including repeats -- a frame script that fails on every
##                   `exitFrame` is 15 faults a second, and that is the shape
##                   worth being able to see.
##   `session_faults()`  the distinct messages, first-seen order, which is what a
##                   report wants to print.
##
## Counted in `_fail` rather than derived from `errors`, because the cap makes
## `errors.size()` stop at 50 and a derived count would report a movie fauting
## fifty times identically to one faulting fifty thousand times.
var error_total := 0
## Names the runtime could not bind, with where each was reached from. Host
## bindings report through here too, via `report()`.
var diagnostics := LingoDiagnostics.new()
## Director 3's primary event handlers, installed by `when <event> then <stmt>`
## and keyed by event name. Tier 1 of the message hierarchy: a primary handler
## fires before the sprite an event landed on, and only for the event it names.
## The body is a statement list, stored rather than executed at the point the
## `when` appears — see the "when" branch in `_exec`.
var primary_handlers: Dictionary = {}

## Handlers reachable from anywhere: movie scripts.
var _movie_handlers: Dictionary = {}
## cast -> script name -> ast, for behaviour and cast scripts.
var _scripts: Dictionary = {}
var _steps: int = 0
## When the platform was last given a turn, for `BREATHE_MS`. Milliseconds on
## the same clock `the ticks` reads, and deliberately *not* reset per handler: a
## handler that runs three loops back to back should breathe on the same
## schedule as one that runs a single loop of the same total length.
var _breathed_at: int = 0
var _return_value: Variant = null
## `the result` -- the value the most recent handler call returned.
##
## Written only when the call was made as a **command**, and only when what came
## back is not VOID: `lingo-code.cpp`'s frame pop stores the dropped return value
## and skips a VOID one, so a handler that returns nothing leaves the previous
## answer standing. That is why a script may call three handlers and then read
## `the result` for the one of them that answered.
##
## A handful of builtins write it instead of returning -- `preLoad` and
## `preLoadCast` report the last item they loaded through it -- and those arrive
## from the host through `take_result_request`.
var _result: Variant = null
## The arguments the running handler was called with, for `param(n)` and `the
## paramCount`. Saved and restored around a nested call by `_invoke`, like the
## script and handler names beside it: a callee must not leave its caller
## reporting the callee's argument list.
var _current_args: Array = []
## `abort` is unwinding. Cleared where a dispatch begins rather than where it
## ends, so a handler that aborts cannot leave the next one refusing to start.
var _aborting := false
var _depth: int = 0
## Where execution is, for locating a diagnostic. Statement granularity: the
## line of the statement being run, not of the expression inside it.
var _script_name: String = ""
var _handler_name: String = ""
var _line: int = 0
var _current_handler: Dictionary = {}
## script|handler -> {name: true}, built the first time a handler reports.
var _assigned_names: Dictionary = {}

# ------------------------------------------------------- suspension (§6.1, §9.4)
#
# `play` and `go` do not return to the statement after them. Director stashes the
# *running handler* and requeues it later: `Lingo::func_goto` sets `_freezeState`
# and the handler resumes once the next frame has been entered;
# `Lingo::func_play` sets `_freezePlay` and the handler resumes at `play done`.
# The statements after the call are therefore not dead — they run, later — and
# running them at the call is the divergence this machinery closes. In Rating's
# dialogue idiom the statement after `play frame` is a `go`, and running it
# immediately overwrote the branch the `play` had just set: the talking loop was
# skipped and the line of speech was cut off a frame after it started.
#
# **What suspending means here.** A tree-walking interpreter cannot be paused
# mid-`_exec`, so what is captured is not a program counter but a *chain of block
# positions*: for every statement list on the way out, the index of the statement
# after the one that suspended, plus enough of each enclosing `repeat` to carry on
# looping. Resuming replays that chain from the inside out, which is exactly what
# returning from the nested `_exec_block` calls would have done.
#
# **What it does not capture** is a suspension that happens part-way through
# evaluating an *expression*: `if talkproc() then` where `talkproc` plays. The
# unwinding is at statement granularity, so the call answers VOID and the rest of
# that one statement runs before the chain is taken. Reported rather than
# silent — `LingoDiagnostics.BUILTIN` "suspend inside an expression".

## Set while a freezing command is unwinding, from the moment the host asks for
## it until the chain it produced has been parked.
var _suspending := false
## "play" or "go" — which buffer the chain belongs in. Director keeps them apart
## because they have different resume triggers.
var _suspend_kind := ""
## The chain being built, innermost position first.
var _suspended: Array = []
## Chains waiting to be resumed when no host is holding them. The interpreter
## stays complete on its own; `park_lingo_state` on the host takes over when
## there is one, because a `go to movie` replaces the *interpreter* and the
## frozen handler has to outlive it.
var _own_frozen: Array = []
var _own_play: Array = []
## `tell` bodies run in the other movie's interpreter, and a chain captured there
## cannot be resumed by the caller's. Suspension is declined inside one.
var _told_depth := 0
## How many dispatches are on the stack. A chain leaves the interpreter when the
## outermost one unwinds and not before, and `_depth` cannot answer that: a
## `when` body and a resumed chain both run with no `_invoke` beneath them, so a
## nested handler call inside either would look outermost and park half a chain.
var _running := 0


func _init(host_object: Object = null) -> void:
	host = host_object


# ---------------------------------------------------------------- loading


func load_bundle(bundle: Dictionary, qualifier: String = "") -> void:
	## One compiled cast: {"movie":…, "cast":…, "scripts": {name: ast}}
	##
	## The bundle's own `cast` is the subdirectory ProjectorRays wrote it to, and
	## eleven casts use "External" — MASTER, ISLAND2, WONDER, BOOK and the rest.
	## Keyed on that alone they share one namespace and the last one loaded wins,
	## so DAY1 asking island2 for member 59 got MASTER's `invleft` instead of
	## `to forest1`, and the click played an inventory sound rather than walking.
	var cast := str(bundle.get("cast", ""))
	if qualifier != "":
		cast = "%s/%s" % [qualifier, cast]
	var scripts: Dictionary = bundle.get("scripts", {})
	var by_name: Dictionary = _scripts.get(cast, {})
	for script_name in scripts.keys():
		var ast: Dictionary = scripts[script_name]
		by_name[str(script_name)] = ast
		# A MovieScript's handlers are globally callable. Behaviour and cast
		# scripts are reached through their owning sprite or member instead.
		if str(script_name).to_lower().begins_with("moviescript"):
			for handler in ast.get("handlers", []):
				var key := str(handler.get("name", "")).to_lower()
				if key != "" and not _movie_handlers.has(key):
					_movie_handlers[key] = {"handler": handler, "cast": cast,
						"script": script_name}
	_scripts[cast] = by_name


func script_count() -> int:
	var total := 0
	for cast in _scripts.keys():
		total += (_scripts[cast] as Dictionary).size()
	return total


func movie_handler_names() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _movie_handlers.keys():
		out.append(str(key))
	out.sort()
	return out


func find_script(cast: String, script_name: String) -> Dictionary:
	var by_name: Variant = _scripts.get(cast, {})
	if typeof(by_name) != TYPE_DICTIONARY:
		return {}
	var ast: Variant = (by_name as Dictionary).get(script_name, {})
	return ast if typeof(ast) == TYPE_DICTIONARY else {}


func find_script_by_member(cast: String, member: int) -> Dictionary:
	## ProjectorRays names a script after the cast member that owns it, so
	## "BehaviorScript 108" is master member 108. That is the whole attachment
	## mechanism (see tools/dump_sprite_scripts.py).
	var by_name: Variant = _scripts.get(cast, {})
	if typeof(by_name) != TYPE_DICTIONARY:
		return {}
	var suffix := " %d" % member
	for script_name in (by_name as Dictionary).keys():
		var name := str(script_name)
		var head := name.split(" - ")[0]
		if head.ends_with(suffix):
			return (by_name as Dictionary)[script_name]
	return {}


# ---------------------------------------------------------------- calling


func has_handler(name: String) -> bool:
	return _movie_handlers.has(name.to_lower())


## Fire the primary handler installed by `when <event> then`, if there is one.
##
## Returns true when one ran. Tier 1: the caller should run this *before* the
## ordinary hierarchy, because that is where Director puts it — ahead of the
## sprite the event landed on.
##
## The body runs in a fresh frame rather than as a closure over wherever the
## `when` was written. A real primary handler is compiled in its own scope, and
## treating it as a closure would let it see locals of a handler that has long
## since returned.
func run_primary(event: String) -> bool:
	var key := event.to_lower()
	if not primary_handlers.has(key):
		return false
	var body: Array = primary_handlers[key]
	if body.is_empty():
		return false
	_running += 1
	_exec_block(body, {})
	_running -= 1
	if _running == 0:
		_park()
	return true


## Compile the string `the mouseDownScript` and friends hold (§6.3 tier 1).
##
## **Director's value is Lingo source, compiled on assignment**, and the
## reference is explicit about the shape it compiles into:
## `Movie::setPrimaryEventHandler` calls `replaceCode(code, kEventScript, event)`
## -- the string becomes a whole script filed under a synthetic slot keyed by the
## event -- and `resolveScriptEvent` then rewrites the event to `kEventGeneric`
## before running it. So what executes is the script's **scopeless** part, its
## bare statements, and an `on <event>` block written inside the string is never
## reached. `set the keyDownScript to "fromnow"` is therefore a one-statement
## script whose statement is a no-argument call, which is why a bare handler name
## has always worked in Director and is not a second mechanism.
##
## Wrapped in a synthetic handler rather than compiled as a bare script for the
## reason `_do` is: a handler is what `_invoke` runs, and `_invoke` is where the
## frame, the reporting location, the recursion guard and `play`/`go` suspension
## all live. Reusing it means a primary handler can `go` exactly like any other
## Lingo, which the statement-list path (`run_primary`) above cannot say.
##
## Returns `{}` on a source that will not compile, with the reason in `error`.
## Static because the compile has no interpreter in it: the **assignment** is
## what compiles (`preview_lingo_host.gd`), and the assignment happens in a host
## that must not have to reach for whichever interpreter is current -- a movie
## change swaps that object and the compiled script has to outlive it.
static func compile_statements(source: String, label: String, error: Array) -> Dictionary:
	if source.strip_edges() == "":
		return {}
	var compiler = DoCompiler.new()
	var compiled: Dictionary = compiler.compile_source(
		"on __%s\n%s\nend\n" % [label, source], label)
	var handlers: Array = compiled.get("handlers", []) if not compiled.is_empty() else []
	if handlers.is_empty():
		error.append(str(compiler.error) if str(compiler.error) != "" else "no statements")
		return {}
	return {"script": compiled, "handler": handlers[0]}


## Run what `compile_statements` produced. True when something ran.
func run_compiled(compiled: Dictionary) -> bool:
	if compiled.is_empty():
		return false
	var handler: Dictionary = compiled.get("handler", {})
	if (handler.get("body", []) as Array).is_empty():
		return false
	_running += 1
	_invoke(handler, [], compiled.get("script", {}))
	_running -= 1
	if _running == 0:
		_park()
	return true


## The script object a sprite behaviour runs on, one per (channel, script).
##
## **A behaviour is an instance, not a script**, and this port ran them as
## scripts with `me` null for its whole life. Everything about that reads as
## working: the handler is found, it runs, and only a handler that says `me`
## notices. What it costs is the two things a behaviour instance is *for* --
## its `property` declarations have nowhere to live, and `me.spriteNum` is VOID.
##
## Magic Hat is where the second one bites. Its buttons are ordinary Director
## screen items whose script is one line:
##
##     on mouseUp me
##       ItemMouseUp(me.spriteNum, (the mouseLoc)[1], (the mouseLoc)[2])
##
## With `me` null that call passed VOID, `GetScreenItem(VOID)` answered VOID,
## and the guard right after it exited -- so every button in the title
## highlighted, played its sound and did nothing at all. Nothing was reported,
## because nothing failed: a handler ran to completion and took an early exit
## the movie itself wrote.
##
## Cached per channel and per script, because that is what an instance is: two
## sprites sharing one behaviour have two independent property bags, and the
## same sprite must get the *same* object every tick or a property written in
## `mouseDown` is gone by `mouseUp`. The cache needs no clearing of its own:
## `preview/boot.gd` builds a fresh `LingoInterpreter` per movie and carries only
## the globals across, so these die with the movie that made them -- which is
## also Director's lifetime for a behaviour instance.
##
## `spriteNum` is declared on the instance whether or not the script names it.
## Director's behaviours all have it -- it is how a behaviour knows which sprite
## it is on -- and a script is free to read it without declaring anything.
## `script_channel` is the score's **behaviour channel** -- Director's "sprite 0",
## the row above the sprite channels where a frame's own behaviour is attached. It
## is an instance like any other and `the currentSpriteNum` inside it is 0, which
## is exactly the number this function otherwise reads as "not a behaviour at
## all". The flag is the only way to tell those two apart, and it is a parameter
## rather than a sentinel channel number because `call_handler` defaults its
## channel to 0 for every ordinary dispatch in the port: widening the guard would
## hand a movie script and a frame script an instance and a `me` they have never
## had.
##
## **A dispatch does not reach for this; it reaches for `live_behaviour`.** The
## span is what makes the instance -- `frame_loop.gd:send_sprite_message` on
## `beginSprite`, which is the port's `Score::createScriptInstances` -- and every
## message afterwards only looks one up. `bugs.md` 93 is what the split cost
## while `exitFrame` had no way to ask.
## **`initializer_params` is the score's own answer to what the author typed into
## this behaviour's parameter dialog**, as a Lingo property-list literal --
## `[#prGotoFrame: "mainmenu"]`, `[#prFrameStep: 4]`. `bugs.md` 83, and it is the
## half of a behaviour that had no path into the engine at all: the properties
## were declared and left VOID, so `go(prGotoFrame)` reached VOID through a
## *declared, unassigned* property and every behaviour in the corpus that takes a
## parameter ran on nothing.
##
## Seeded here rather than by the caller, and only on the pass that *creates* the
## object, because that is the reference's shape exactly: `Score::
## createScriptInstance` runs `new`, and only then evaluates the string and writes
## the pairs onto the fresh instance (`lingo-events.cpp:879-935`). A later message
## finding the instance in the cache must not re-seed it -- a behaviour that
## assigned its own property in `beginSprite` would have the author's value put
## back on the next tick.
##
## **A pair whose name the script never declared is dropped, not created**, which
## is `ScriptContext::setProp`'s own behaviour with its default `force = false`
## (`lingo-object.cpp:742-765`): an undeclared name is offered to the ancestor and
## then goes nowhere. `LingoObject.set_slot` is the same walk and answers false
## for the same case, so the reference's rule is already written down here and
## this only has to not work around it. It matters because the parameter dialog
## and the `property` line are authored separately: a behaviour whose
## `getPropertyDescriptionList` names a property the script forgot to declare is
## an authoring bug that Director silently ignores, and inventing the slot would
## make this port run a script the original could not.
func behaviour_instance(script: Dictionary, channel: int,
		script_channel := false, initializer_params := "") -> Variant:
	if script.is_empty() or (channel <= 0 and not script_channel):
		return null
	var key := "%d:%s" % [channel, str(script.get("script", ""))]
	if not _behaviours.has(key):
		var made := LingoObject.new(script, str(script.get("cast", "")))
		made.call("declare", "spritenum")
		made.call("set_slot", "spritenum", channel)
		_seed_behaviour_params(made, initializer_params)
		_behaviours[key] = made
	return _behaviours[key]


## Write a span's authored parameters onto a freshly built behaviour instance.
##
## The string is evaluated with `value()` and not with a parser of its own, which
## is the reference's choice as well -- `createScriptInstance` pushes it through
## `LB::b_value` rather than reading the bytes it just loaded. That matters more
## here than it looks: `LingoBuiltins._value_of` already knows that a nested `[]`
## is a list, that `point(-10, 0)`'s comma is not the literal's, and that a bare
## `[#a: 1]` is a property list and not a two-element list, all of which turn up
## in the corpus's initialisers (`[#prSpritesList: [], #prFreezJinny: "1"]` is 37
## spans of `trivia.dir`). A second reader here would be a second dialect and a
## second set of those bugs.
##
## Anything that does not evaluate to a property list is ignored and the instance
## is left as declared. The reference warns and returns the instance for both the
## empty-stack and the not-a-PARRAY case (`lingo-events.cpp:914-926`); it does not
## refuse the behaviour, because a behaviour with unset properties is still a
## behaviour and Director runs it.
func _seed_behaviour_params(instance: Variant, initializer_params: String) -> void:
	if initializer_params.strip_edges() == "":
		return
	var handled: Array = []
	var parsed: Variant = Builtins.call_builtin("value", [initializer_params], handled)
	if handled.is_empty() or typeof(parsed) != TYPE_DICTIONARY:
		return
	for name in (parsed as Dictionary):
		instance.call("set_slot", str(name), (parsed as Dictionary)[name])


## Live behaviour instances, keyed `<channel>:<script name>`. See above.
var _behaviours: Dictionary = {}


## The instance `script` is already running as on `channel`, or null.
## **Creates none**, and that is the whole point of it existing beside
## `behaviour_instance`.
##
## A message is delivered on an instance that the score has *already* made, never
## on one the delivery invents. The reference has no other shape available:
## instances are made in exactly one place -- `Score::createScriptInstances`, on
## entering a span (`reference/scummvm/lingo-events.cpp:940-995`) -- and every
## dispatch afterwards only *reads* one. `resolveScriptEvent` reads
## `channel->_scriptInstanceList[i]` for the sprite tier (`:296-303`) and
## `_scriptChannelScriptInstance` for the frame tier (`:369-377`), and both are
## fields that are either populated or not.
##
## **Channel 0 is the frame tier**, Director's "sprite 0": the score row above
## the sprite channels, holding one behaviour at a time. Every message that
## reaches that tier is delivered on its instance -- `exitFrame`, `enterFrame`,
## `idle`, `timeout`, `prepareFrame`, and every mouse and key event that falls
## through the sprite and cast tiers (`:636-641`). So the presence of a `0:<name>`
## entry *is* the score's answer to "is this a behaviour-channel script or a
## plain frame script", and it is the same question the reference asks its field.
##
## Looking up rather than creating is what makes `bugs.md` 93's fix safe in both
## directions. A create here would hand every ordinary frame script and every
## movie script a `me` they have never had -- the wrong fix that entry names --
## and it would leak an instance per channel per script for the life of the
## movie, because `release_behaviour` only ever runs for a span that *began*.
func live_behaviour(script: Dictionary, channel: int) -> Variant:
	if script.is_empty() or channel < 0:
		return null
	return _behaviours.get("%d:%s" % [channel, str(script.get("script", ""))], null)


## The sprite is gone: drop its instance so the next one is a new object.
##
## `Score::killScriptInstances` clears `channel->_scriptInstanceList` right after
## it sends `endSprite` (`reference/scummvm/lingo-events.cpp:866-872`), and a
## behaviour's whole reason for being an instance is that its `property`
## declarations are per sprite. Kept out of `behaviour_instance`'s own cache
## discipline because the cache cannot know the lifetime -- only the frame loop
## can, which is why this is a call and not a timeout.
## Channel 0 is a real key here -- the behaviour channel's instance, see
## `behaviour_instance` -- so the guard is "negative", not "not positive".
func release_behaviour(script: Dictionary, channel: int) -> void:
	if channel < 0 or script.is_empty():
		return
	_behaviours.erase("%d:%s" % [channel, str(script.get("script", ""))])


## Send one message, with Director's movie-script fallback behind it.
##
## `channel` is `the currentSpriteNum` -- **which sprite this message is for**,
## 0 for the frame tier -- and `preview/scripts.gd:dispatch` derives it rather
## than every call site passing one. It selects the recipient's instance and does
## not create it: see `live_behaviour` for why that direction, and `bugs.md` 93
## for the shape of the bug while this defaulted to 0 and read 0 as "not a
## behaviour at all".
func call_handler(name: String, args: Array = [], script: Dictionary = {},
		channel: int = 0) -> Variant:
	_running += 1
	## A behaviour is delivered its own instance as `me`, both as the first
	## argument (which is how `on mouseUp me` binds it) and on the frame (which
	## is how a handler that omits the parameter still reads it).
	var on_object: Variant = behaviour_instance(script, channel)
	# The frame tier, which names no sprite and so cannot ask for an instance to
	# be made: `channel <= 0` is refused by the line above on purpose, and what
	# answers here is the behaviour channel's *live* instance if the score has one
	# -- `bugs.md` 93, and `live_behaviour` for why a lookup and not a create.
	if on_object == null:
		on_object = live_behaviour(script, 0)
	var value: Variant = _resolve_and_call(name, args, script, on_object)
	_running -= 1
	# The outermost dispatch is where a suspended chain leaves the interpreter.
	# Every entry point funnels through here -- the frame loop, the mouse, the
	# keyboard and `_read_var`'s bare-identifier calls alike -- so no dispatch
	# site has to know that suspension exists.
	if _running == 0:
		_park()
	return value


## Run `name` in exactly `script`, and nowhere else. True when a handler ran.
##
## `call_handler` resolves two tiers at once -- the given script, then any movie
## script -- which is the right shape when the caller has one recipient in mind
## and wants Director's fallback behind it. It is the wrong shape for a **queued**
## chain (§6.3): there the script tier and the movie tier are separate elements
## with their own pass flags, and folding them together would run the movie
## script even where the element before it consumed the event.
##
## Same `_running`/`_park` discipline as `call_handler`, because a handler
## reached this way can `play` or `go` exactly like any other.
func call_in_script(name: String, script: Dictionary, channel: int = 0,
		script_channel := false) -> bool:
	var key := name.to_lower()
	for value in script.get("handlers", []):
		var handler: Dictionary = value
		if str(handler.get("name", "")).to_lower() != key:
			continue
		_running += 1
		# The queued sprite tier reaches a behaviour through here rather than
		# through `call_handler`, so the instance has to be offered at both
		# doors or a mouse event sees a `me` a frame event does not.
		var on_object: Variant = behaviour_instance(script, channel, script_channel)
		# The queued **frame** tier, which carries no channel: `event_chain.gd:
		# build` gives its frame element channel 0 because only one tier of the
		# five is a sprite behaviour, and 0 is what `the currentSpriteNum` must
		# read there. The reference still delivers that element on the behaviour
		# channel's instance -- `resolveScriptEvent`'s `kFrameHandler` arm reads
		# `_scriptChannelScriptInstance` for a *mouse* event exactly as it does for
		# `exitFrame` (`lingo-events.cpp:369-377`). Without this, magichat's
		# `BehaviorScript 34 - album loop` would get a `me` in `exitFrame` and none
		# in the `mouseUp` three lines below it, which is `bugs.md` 93 one door
		# along rather than fixed.
		if on_object == null:
			on_object = live_behaviour(script, 0)
		_invoke(handler, [on_object] if on_object != null else [], script, on_object)
		_running -= 1
		if _running == 0:
			_park()
		return true
	return false


## Run `name` in the first movie script that declares it. True when one ran.
##
## The other half of the split above, and the last element of every queued
## chain. Director searches the movie scripts in cast-window order and stops at
## the first match; `_movie_handlers` is that search done once at load time.
func call_movie_handler(name: String) -> bool:
	var key := name.to_lower()
	if not _movie_handlers.has(key):
		return false
	var entry: Dictionary = _movie_handlers[key]
	var owner := find_script(str(entry.get("cast", "")), str(entry.get("script", "")))
	_running += 1
	_invoke(entry["handler"], [], owner)
	_running -= 1
	if _running == 0:
		_park()
	return true


func _resolve_and_call(name: String, args: Array, script: Dictionary,
		on_object: Variant = null) -> Variant:
	## Resolution order is Director's, narrowed to what this port needs: the
	## script that owns the event first, then any movie script.
	##
	## `on_object` is the behaviour instance when the caller named a channel. It
	## goes only to the script's own handler: a *movie* handler reached through
	## the fallback belongs to no sprite, and handing it a `me` would make
	## `me.spriteNum` answer a channel it has nothing to do with.
	##
	## **Both halves of that**, and the second was nearly lost. `me` arrives twice
	## -- on the frame, for a handler that omits the parameter, and as the first
	## *argument*, which is how `on mouseUp me` binds it. The argument used to be
	## substituted in `call_handler`, before this function chose a tier, so an
	## instance resolved for the frame tier travelled into the movie tier whenever
	## the frame script did not declare the handler: the movie's `on exitFrame me`
	## would then bind a behaviour it has nothing to do with. Substituting it here,
	## inside the branch that runs the script's own handler, is what makes the
	## paragraph above true of the argument as well as of the frame.
	var key := name.to_lower()
	if not script.is_empty():
		for handler in script.get("handlers", []):
			if str(handler.get("name", "")).to_lower() == key:
				var own := [on_object] if on_object != null and args.is_empty() else args
				return _invoke(handler, own, script, on_object)
	if _movie_handlers.has(key):
		var entry: Dictionary = _movie_handlers[key]
		var owner := find_script(str(entry.get("cast", "")), str(entry.get("script", "")))
		return _invoke(entry["handler"], args, owner)
	return null


## Run one handler.
##
## `me` is the script object the message was delivered to, or null for every
## other dispatch there is -- a plain frame script and a movie handler. **Not a
## behaviour any more**: `038b79a4` made every message to one arrive on an
## instance (`behaviour_instance`, and `gate.sh behaviour_me`), so the clause that
## used to end this sentence -- "a behaviour this port reaches as a *script*
## rather than as an instance" -- names no dispatch that exists. It goes on the frame
## rather than into a field, because a handler that calls another handler on
## another object must not leave the caller's `me` showing through: the frame is
## already the thing that is saved and restored per call.
##
## Nothing else changes when it is null, which is what makes this safe to add to
## a port that has run without objects: `_read_var` and `_set_var` consult
## `frame["me"]` only when there is one.
func _invoke(handler: Dictionary, args: Array, script: Dictionary,
		me: Variant = null) -> Variant:
	if _depth > 64:
		_fail("handler recursion too deep at %s" % str(handler.get("name", "?")))
		return null
	_depth += 1
	# Saved on the stack rather than pushed onto one: a nested call must not
	# leave the caller reporting from the callee's line.
	var outer_script := _script_name
	var outer_handler := _handler_name
	var outer_body := _current_handler
	var outer_line := _line
	_script_name = str(script.get("script", ""))
	_handler_name = str(handler.get("name", ""))
	_current_handler = handler
	var frame := {
		"locals": {},
		"script": script,
		"globals": {},
		"me": me,
	}
	# **A `global` written outside any handler declares the name for every
	# handler in the script** (§7). The parser has always collected those into
	# `script["globals"]` and nothing read it, so a handler whose only
	# declaration was the script-level one treated the name as an ordinary
	# local: `on startMovie / gFirstRun = 1` wrote into a dictionary that was
	# discarded when the handler returned, and the next reader of `gFirstRun`
	# found no local, no global, and fell through to the unbound-name arm --
	# where a bare identifier is a parameterless handler call, so it answered
	# VOID with nothing on the clock to say why. `itamar-magichat` sat on frame
	# 0 for ever on exactly that: `gGlobalInfo` was reported as an unbound
	# builtin 34 times a boot, `GlobalInfo(#startFrame)` answered VOID, and the
	# frame behaviour re-jumped to where it already was.
	#
	# Applied per invocation rather than once at load, because the declaration
	# is *lexically* the script's but its effect is a name binding on the frame,
	# and the frame is built here. The list is empty for most scripts.
	for name in script.get("globals", []):
		_declare_global(str(name).to_lower(), frame)
	var outer_args := _current_args
	_current_args = args
	var params: Array = handler.get("params", [])
	for i in params.size():
		frame["locals"][str(params[i]).to_lower()] = args[i] if i < args.size() else 0
	_return_value = null
	var flow := _exec_block(handler.get("body", []), frame)
	if flow == Flow.SUSPEND:
		# A handler boundary in the chain. It carries nothing to run: its only job
		# is to be where a `return` from a resumed statement stops unwinding, so
		# that `on mouseUp / talkproc() / <more>` resumes `<more>` after
		# `talkproc` finishes rather than abandoning the caller with it.
		#
		# The caller's value is lost: `_invoke` answers VOID and whatever
		# expression the call sat in completes with that. `_exec_from` reports it
		# ("suspend inside an expression") for any statement that is not a bare
		# call, because the alternative is a wrong number that reads as
		# arithmetic. Zero sites in either corpus.
		_suspended.append({"k": "handler"})
	_script_name = outer_script
	_handler_name = outer_handler
	_current_handler = outer_body
	_current_args = outer_args
	_line = outer_line
	_depth -= 1
	if flow == Flow.RETURN:
		# `the result`, and the VOID guard is the reference's: a handler that
		# returns nothing does not clear what the last one that answered left.
		if _return_value != null:
			_result = _return_value
		return _return_value
	return null


## Run a `tell` body against *this* movie, on behalf of an interpreter driving
## another one. The `tell` arm of `_exec` is the only caller.
##
## Three things move and three do not, and each split is a decision:
##
##   - **Handler resolution and the host move.** That is the whole point: `self`
##     is the told movie, so `peoplefunk()` finds the told movie's movie script
##     and `sprite(30).visible = 0` reaches the told movie's channels.
##   - **`frame["script"]` is dropped.** A message sent to another movie enters
##     its hierarchy at the movie level; there is no sprite or frame script in
##     the target that the `tell` was "in".
##   - **Locals do not move** — the same Dictionary object is handed on, so
##     `tell the stage / rir = the movieName / end tell` writes `rir` into the
##     *caller's* handler where the next line reads it. Fifteen sites in this
##     corpus do exactly that and all of them are how a MAP button decides which
##     movie the stage is showing.
##   - **Declared globals do not move** either, for the same reason: `global
##     nextroomdata` was declared by the calling handler. Globals themselves are
##     application-wide in Director, so the two interpreters are expected to be
##     sharing one dictionary; if they are not, this still reads and writes the
##     told movie's, which is the closer of the two wrong answers.
##   - **The step budget does not move.** A told body is part of the caller's
##     dispatch, so it is charged there and the runaway guard still covers the
##     whole of it. Charging it here instead would let a `tell` inside an
##     every-frame handler accumulate against an interpreter nothing ever
##     resets, and the movie would stop executing after some thousands of
##     frames with no error anyone could attribute.
##   - **The diagnostic location does not move.** The statements are lexically
##     the caller's, so an unbound name inside a `tell` should report the file
##     and line it was written on.
func run_told(body: Array, frame: Dictionary, caller = null) -> int:
	var told: Dictionary = {
		"locals": frame.get("locals", {}),
		"globals": frame.get("globals", {}),
		"script": {},
	}
	var outer_script := _script_name
	var outer_handler := _handler_name
	var outer_line := _line
	var outer_steps := _steps
	if caller != null:
		_script_name = caller._script_name
		_handler_name = caller._handler_name
		_line = caller._line
		_steps = caller._steps
	# **A `tell` body may not suspend.** The chain a `play` or `go` builds is a
	# position inside *this* interpreter's blocks, and the handler that has to
	# resume it is the caller's, running in another one; there is no object that
	# could hold both. So `_take_suspend_request` declines while this is set and
	# reports the gap, and the body runs straight through as it always has —
	# which loses the ordering, not the statements. `tools/suspend_survey.gd`
	# counts the exposure: in Rating, 18 `go` and no `play` are written inside a
	# `tell`; in Piposh 2, 34 `go` and 16 `play`.
	_told_depth += 1
	var flow := _exec_block(body, told)
	_told_depth -= 1
	if caller != null:
		caller._steps = _steps
		# `return` inside a `tell` unwinds the caller's handler, so the value has
		# to travel with the flow. Nothing in this corpus does it; carried anyway,
		# because the alternative is a silently empty result.
		if flow == Flow.RETURN:
			caller._return_value = _return_value
	_script_name = outer_script
	_handler_name = outer_handler
	_line = outer_line
	_steps = outer_steps
	return flow


func run_handler_in_script(script: Dictionary, name: String, args: Array = []) -> bool:
	## Returns false when the script has no such handler, so callers can fall
	## through the message hierarchy.
	var key := name.to_lower()
	for handler in script.get("handlers", []):
		if str(handler.get("name", "")).to_lower() == key:
			_running += 1
			_invoke(handler, args, script)
			_running -= 1
			if _running == 0:
				_park()
			return true
	return false


# ---------------------------------------------------------------- suspension


## Whether anything is waiting to be resumed. A host holding the chains answers
## for itself; this is the interpreter's own buffer, for callers with no host.
func has_frozen_state() -> bool:
	return not _own_frozen.is_empty()


## Move the handler a `play` parked into the queue the next thaw takes from —
## Director's `requeueLingoPlayState`, and the reason `play done` is a *resume*
## rather than a second branch. False when no handler was waiting, which is the
## `play done` written on a frame nobody played into.
##
## Inserted at the bottom of the queue rather than the top, matching the
## reference: anything frozen since the `play` is nearer the surface and finishes
## first. In practice the queue is empty and the distinction never shows.
func requeue_play_state() -> bool:
	if _own_play.is_empty():
		return false
	_own_frozen.insert(0, _own_play)
	_own_play = []
	return true


## Resume one frozen chain. Returns false when there was none.
func thaw() -> bool:
	if _own_frozen.is_empty():
		return false
	resume_chain(_own_frozen.pop_back())
	return true


## Run a chain of block positions to completion, or until it freezes again.
##
## Innermost first: each record finishes the block it was suspended in, and
## reaching the end of one hands control to the record outside it — which is
## exactly what returning from the nested `_exec_block` calls would have done, in
## the same order, with the same frames.
##
## The four abnormal exits have to be honoured across the join or the chain means
## something different from the code it was cut out of:
##
##   - `return` unwinds to the handler it was written in **and no further**, which
##     is what the `handler` markers are in the chain for;
##   - `exit repeat` skips to just past the innermost enclosing loop;
##   - `next repeat` skips to that loop and lets it run its next pass;
##   - an aborted step budget abandons everything, because there is no position
##     left worth trusting.
func resume_chain(chain: Array) -> void:
	if chain.is_empty():
		return
	var outer_script := _script_name
	var outer_handler := _handler_name
	var outer_body := _current_handler
	var outer_line := _line
	_running += 1
	var pending: Array = chain.duplicate()
	while not pending.is_empty():
		var entry: Dictionary = pending.pop_front()
		var flow := _resume_entry(entry)
		if _suspending:
			# Frozen again before it finished. Whatever is left of the old chain is
			# *outside* the new one, so it goes on the end and the two become one.
			_suspended.append_array(pending)
			break
		match flow:
			Flow.RETURN:
				while not pending.is_empty():
					if str((pending.pop_front() as Dictionary).get("k", "")) == "handler":
						break
			Flow.ABORT:
				pending.clear()
			Flow.EXIT_REPEAT:
				while not pending.is_empty():
					if _is_repeat(pending.pop_front()):
						break
			Flow.NEXT_REPEAT:
				while not pending.is_empty() and not _is_repeat(pending[0]):
					pending.pop_front()
	_script_name = outer_script
	_handler_name = outer_handler
	_current_handler = outer_body
	_line = outer_line
	_running -= 1
	_park()


static func _is_repeat(entry: Dictionary) -> bool:
	return str(entry.get("k", "")).begins_with("repeat")


func _resume_entry(entry: Dictionary) -> int:
	var kind := str(entry.get("k", ""))
	if kind == "handler":
		# A marker, not a position. Reaching it means the callee ran out.
		return Flow.NORMAL
	_script_name = str(entry.get("script", ""))
	_handler_name = str(entry.get("handler", ""))
	_current_handler = entry.get("hbody", {})
	var frame: Dictionary = entry.get("frame", {})
	var stmt: Dictionary = entry.get("stmt", {})
	match kind:
		"block":
			return _exec_from(entry["stmts"], frame, int(entry["i"]))
		"repeat_while":
			return _repeat_while(stmt, frame)
		"repeat_forever":
			return _repeat_forever(stmt, frame)
		"repeat_with":
			return _repeat_with(stmt, frame, str(entry["name"]),
				int(entry["i"]), int(entry["to"]), bool(entry["down"]))
		"repeat_in":
			return _repeat_in(stmt, frame, str(entry["name"]),
				entry["items"], int(entry["i"]))
	return Flow.NORMAL


## Hand the finished chain to whoever is holding frozen state.
##
## The host gets it when it has somewhere to put it, and it must: `go to movie`
## replaces the interpreter, and a handler frozen by the `go` that *caused* the
## movie change would die with the object that captured it. Director keeps frozen
## states on the window for the same reason.
func _park() -> void:
	if not _suspending or _running > 0:
		# Still unwinding. Parking now would hand over the inner half of a chain
		# and leave the outer half to run as though nothing had frozen.
		return
	_suspending = false
	var kind := _suspend_kind
	_suspend_kind = ""
	var chain: Array = _suspended
	_suspended = []
	if chain.is_empty():
		return
	if host != null and host.has_method("park_lingo_state"):
		host.call("park_lingo_state", chain, kind)
		return
	if kind == "play":
		_own_play = chain
	else:
		_own_frozen.append(chain)


## Director suspends the handler that ran `play` or `go`, and the host binding
## cannot say so by returning a value: `go to movie` has already replaced the
## preview's interpreter by the time the binding returns, so an interpreter told
## directly would be the wrong one. The binding leaves the request on the host
## object instead, and the interpreter that actually ran the statement takes it.
func _take_suspend_request() -> void:
	if host == null or not host.has_method("take_suspend_request"):
		return
	var kind := str(host.call("take_suspend_request"))
	if kind == "":
		return
	if _told_depth > 0:
		report(LingoDiagnostics.BUILTIN, "suspend across tell")
		return
	if _suspending:
		return
	_suspending = true
	_suspend_kind = kind


## The builtins this object answers itself, ahead of the module and the host.
##
## Each is here because the thing that answers it is *inside* the interpreter:
## `do` runs a string in the caller's frame, `param` reads the running call's
## argument list, `abort` unwinds every frame on the stack, and the object
## messaging family (§7.1) has to *invoke a handler*, which is this file's job
## and nobody else's. `lingo_builtins.gd` is engine-free by definition and the
## host is one frame further out, so neither can answer any of them -- the host
## had `abort` in its IGNORED list, which made it `nothing` under a different
## name.
##
## **Asked from two places on purpose.** `_call` handles `do "x"` and `param(1)`;
## a bare word with no arguments never reaches `_call` at all, because
## `_read_var` treats an unknown identifier as a no-argument call, and that is how
## Lingo spells `abort`. The first version guarded only `_call` and `abort` went
## straight past it.
##
## `handled` distinguishes "answered VOID" from "not mine", the same way
## `lingo_builtins.call_builtin` does and for the same reason.
func _own_builtin(name: String, args: Array, frame: Dictionary,
		handled: Array) -> Variant:
	match name:
		"do":
			# Compile a string and run it **in this handler's frame**. That last
			# part is the whole of the command: `do` sees the caller's locals and
			# globals, which is how a title stores a fragment in a field and runs
			# it. `value("...")` is the expression half of the same idea and
			# belongs to `lingo_builtins.gd`, which parses a literal without an
			# interpreter; this is the statement half.
			handled.append(true)
			return _do(LingoValue.to_str(args[0]) if not args.is_empty() else "", frame)
		"abort":
			# Leave every handler on the stack, not just this one. `exit` returns
			# from the running handler and the caller carries on; `abort` stops the
			# whole dispatch, and a movie using it as its error path ran on through
			# the statements it was trying to escape.
			handled.append(true)
			_aborting = true
			return null
		"param":
			# The nth argument the *running* handler was called with. The reference
			# reads the named parameter first and falls back to the unnamed list, so
			# `param(1)` inside a handler that has reassigned its first argument
			# answers the assigned value rather than what was passed.
			handled.append(true)
			var which := LingoValue.to_int(args[0]) if args.size() > 0 else 0
			if which < 1:
				return null
			var params: Array = (_current_handler.get("params", []) as Array)
			if which <= params.size():
				return _read_var(str(params[which - 1]), frame)
			return _current_args[which - 1] if which <= _current_args.size() else null
		"script":
			# `script("name")`, `script(N)` and the designator spelling `script
			# "name"` -- which needs no parser arm, because an identifier followed
			# by a string is already the command-call form (`_parse_primary`), so
			# all three arrive here as one argument.
			#
			# The answer is a **member reference**, packed the way `member()`'s is
			# (§1.6), and not the script itself: Director's `script` is a cast
			# reference and `the scriptText of script "x"` has to work on it. What
			# turns one into an object is `new` below.
			if args.is_empty():
				return null
			handled.append(true)
			var script_cast := LingoValue.to_str(args[1]) if args.size() > 1 else ""
			return _host_call("member_number", [args[0], script_cast])
		"new":
			# `new(script "Parent", args...)` (§7.1) and `new(xtra "name")`.
			#
			# The instance is created first and its `new` handler is then called
			# with `me` as the first argument, exactly as the reference calls
			# every other handler on an object. **What the expression evaluates to
			# is what `new` returned**, not the instance: the convention is `return
			# me`, and a parent script whose `new` returns something else -- a
			# list of children, VOID for a failed construction -- means it.
			# A script with no `new` handler answers the instance itself.
			if args.is_empty():
				return null
			handled.append(true)
			return _instantiate(args[0], args.slice(1))
		"call", "send":
			# `call(#msg, objectOrList, args...)`. `send` is D4's undocumented
			# spelling of the same builtin and the reference maps both onto one
			# body (`lingo-builtins.cpp:126,149`).
			#
			# A **list** of objects is Director's own broadcast form -- it is what
			# `the scriptInstanceList of sprite` hands back -- and every object in
			# it that answers the message runs; the value is the last one's.
			# An object that does not answer is skipped in silence, which is the
			# reference's `if (sym.type == VOIDSYM) return Datum()`.
			if args.size() < 2:
				return null
			handled.append(true)
			var message := _symbol_text(args[0])
			return _broadcast(args[1], message, args.slice(2), false)
		"callancestor", "sendancestor":
			# `callAncestor(#msg, object, args...)`. The message skips the
			# object's own handler and enters at its ancestor, which is how a
			# child calls the behaviour it has overridden.
			#
			# **The reference stubs this** (`b_callAncestor` prints and drops the
			# stack), so there is no implementation to read: what is built here is
			# Director's documented meaning of the name, and `me` inside the
			# ancestor's handler is the *ancestor* -- the object the message was
			# actually delivered to, which is the rule every other dispatch in
			# this file follows.
			if args.size() < 2:
				return null
			handled.append(true)
			var ancestor_message := _symbol_text(args[0])
			return _broadcast(args[1], ancestor_message, args.slice(2), true)
	return null


## Director spells a message name as a symbol (`#mouseUp`), a string, or -- in
## authored source that predates symbols -- a bare quoted word. All three reach
## here; a symbol is a StringName in this port, and `to_str` would answer the
## same thing, so this exists to say that the coercion is deliberate rather than
## incidental.
static func _symbol_text(value: Variant) -> String:
	return LingoValue.to_str(value).trim_prefix("#")


## `new(<script reference>, args)` -- build the object and run its constructor.
##
## The reference argument is whatever `script(...)` answered, which is a packed
## member reference, so the script AST is fetched through the host: only the
## preview knows which compiled cast a library number names. A host with no
## `script_at` -- a harness driving the interpreter alone -- may hand the AST
## straight in instead, which is the second arm.
func _instantiate(reference: Variant, args: Array) -> Variant:
	# `new(xtra("FileIO"))` (§7.3). An Xtra is not a script and has no `new`
	# handler to run: the registry entry makes the instance itself, and what comes
	# back is a **native object** answering `lingo_perform` rather than a
	# `LingoObject`. Tested by method rather than by type, so nothing here has to
	# know what an Xtra is.
	if reference is Object and (reference as Object).has_method("make_xtra_instance"):
		var made: Variant = (reference as Object).call("make_xtra_instance", args)
		if made == null:
			report(LingoDiagnostics.BUILTIN, "new: xtra would not instantiate")
		return made
	var ast: Dictionary = {}
	if typeof(reference) == TYPE_DICTIONARY:
		ast = reference
	else:
		var found: Variant = _host_call("script_at", [reference])
		if typeof(found) == TYPE_DICTIONARY:
			ast = found
	if ast.is_empty() or (ast.get("handlers", []) as Array).is_empty():
		# Nothing to instantiate. Reported by name rather than answering an empty
		# object, because an object with no handlers accepts every message and
		# does nothing -- the shape §19 calls the worst state there is.
		report(LingoDiagnostics.BUILTIN, "new: no script at %s" % LingoValue.to_str(reference))
		return null
	var obj := LingoObject.new(ast, "")
	var entry: Array = obj.resolve("new")
	if entry.is_empty():
		return obj
	var full: Array = [obj]
	full.append_array(args)
	return _invoke_on(entry[0], entry[1], full)


## Build a script object from a compiled script and run its `new` handler --
## `new(script "x")` reached from GDScript rather than from Lingo (§7.1).
##
## Public because the engine instantiates objects too: a sprite's behaviours
## become instances at frame entry, and a harness builds one without a cast
## behind it. One entry point rather than each caller reaching for
## `_instantiate` by name, which is what `scenes/preview/README.md` warns about.
func make_object(ast: Dictionary, args: Array = []) -> Variant:
	return _instantiate(ast, args)


## Send `message` to a script object, with `me` in front of `args` -- the
## reference's `callBehaviorHandler`, reached from GDScript.
##
## The public spelling of what `call(#msg, obj)` does, for the frame loop's
## `stepFrame` sweep and for anything else in the engine that has to message an
## object. VOID when nothing in the object's chain declares the handler, which is
## the reference's own answer and not an error.
func send_to_object(obj: Variant, message: String, args: Array = []) -> Variant:
	return _broadcast(obj, message, args, false)


## Deliver `message` to an object, or to every object in a list.
##
## `from_ancestor` starts the lookup one link up the chain, which is the whole of
## `callAncestor`. Returns the last recipient's answer, as the reference's
## `b_call` does.
func _broadcast(target: Variant, message: String, args: Array,
		from_ancestor: bool) -> Variant:
	if typeof(target) == TYPE_ARRAY:
		var last: Variant = null
		for item in (target as Array):
			last = _broadcast(item, message, args, from_ancestor)
		return last
	if not LingoObject.is_object(target):
		return null
	var recipient: Variant = target
	if from_ancestor:
		recipient = (target as Object).call("ancestor")
		if recipient == null:
			return null
	var entry: Array = (recipient as Object).call("resolve", message)
	if entry.is_empty():
		return null
	## **`me` is the object the message was sent to, not the ancestor that
	## happens to define the handler.**
	##
	## `resolve` answers `[owner, handler]` after walking the chain, and this
	## passed the *owner* as the first argument -- so an inherited handler ran
	## with `me` bound to the ancestor. Every `me.Something()` inside it then
	## dispatched from the ancestor, which is exactly backwards: the whole point
	## of the chain is that a base handler calls forward into the offspring's
	## override.
	##
	## Magic Hat's menus are that pattern end to end. `MainMenuObject.new` does
	## `ancestor = script("BasicMenuObject").new(MenuName)`, and the base class
	## registers each button with `SetInfo(#menu, me)` from an inherited handler
	## -- so every button stored the *BasicMenuObject* as its menu. A click then
	## reached `BasicMenuObject.MenuMouseUp`, whose entire body is `nothing()`,
	## instead of `MainMenuObject.MenuMouseUp` and its `case … "hatsgame":`
	## dispatch. The buttons highlighted, played their sound and went nowhere.
	##
	## The property half already worked and is what makes this safe: `slot_owner`
	## walks the same chain, so an ancestor's `property` read by its bare name
	## inside its own handler still finds the ancestor's slot even though `me` is
	## now the offspring.
	var full: Array = [recipient]
	full.append_array(args)
	return _invoke_on(entry[0], entry[1], full, recipient)


## Run one handler *on* an object, with the same `_running`/`_park` discipline
## every other entry point uses: a handler reached this way may `play` or `go`
## exactly like one reached from the frame loop, and a chain that is not parked
## is a conversation that never returns.
## `me_on_frame` is the receiver when it differs from the handler's owner, which
## is every inherited message: the *code* comes from the owner and `me` is the
## object the message was sent to. Defaults to the owner for the one caller where
## they are the same object, `new`.
func _invoke_on(obj: Variant, handler: Dictionary, args: Array,
		me_on_frame: Variant = null) -> Variant:
	_running += 1
	var receiver: Variant = me_on_frame if me_on_frame != null else obj
	var value: Variant = _invoke(handler, args, (obj as Object).get("ast"), receiver)
	_running -= 1
	if _running == 0:
		_park()
	return value


## `do "<lingo>"`, run against the caller's own frame.
##
## The frame is handed straight in rather than a fresh one being built: Director's
## `do` is a statement in the handler that wrote it, and a copy of the locals
## would make `do "set x to 1"` write into a scope nothing else can read -- which
## is the failure mode that makes the command look like it works.
##
## Compiled per call. There is no cache and there should not be one: the string is
## usually assembled from a field or a global, so two calls with the same call
## site rarely carry the same source.
func _do(source: String, frame: Dictionary) -> Variant:
	if source.strip_edges() == "":
		return null
	var compiler = DoCompiler.new()
	var compiled: Dictionary = compiler.compile_source(
		"on __do
%s
end
" % source, "do")
	if compiled.is_empty():
		# Director reports a `do` that will not compile and carries on. Reported
		# through the same sink as an unbound name, because "this movie asked for
		# something this port could not run" is the one question the sink answers.
		report(LingoDiagnostics.BUILTIN, "do: %s" % str(compiler.error))
		return null
	var handlers: Array = compiled.get("handlers", [])
	if handlers.is_empty():
		return null
	_exec_block((handlers[0] as Dictionary).get("body", []), frame)
	return null


func reset_steps() -> void:
	_steps = 0
	_drain_errors()
	errors.clear()
	# `abort` unwound the last dispatch and must not refuse this one. Cleared
	# where a dispatch *begins* rather than where it ends, because the ends are
	# `preview/scripts.gd:dispatch`, `preview/event_chain.gd:run` and the thaw,
	# and this is the one line all three already share.
	_aborting = false
	# Diagnostics deliberately survive: they accumulate over a session so the
	# emitted set covers the whole run rather than the last dispatch.


func report(category: String, name: String) -> void:
	## Host bindings report through here, so the location comes from one place.
	diagnostics.report(category, name, _script_name, _handler_name, _line)


func location() -> Array:
	## Where execution is, for a trace record. The same three values `report`
	## hands the sink, so a trace entry and a diagnostic about one access agree.
	return [_script_name, _handler_name, _line]


# ---------------------------------------------------------------- statements


func _exec_block(stmts: Variant, frame: Dictionary) -> int:
	if typeof(stmts) != TYPE_ARRAY:
		return Flow.NORMAL
	return _exec_from(stmts, frame, 0)


## A statement list from `start` onward.
##
## Written with an index rather than `for stmt in stmts` for one reason: resuming
## a suspended handler is re-entering *this* at the statement after the one that
## suspended. The index is the whole of what a block position is.
func _exec_from(stmts: Array, frame: Dictionary, start: int) -> int:
	for i in range(start, stmts.size()):
		if typeof(stmts[i]) != TYPE_DICTIONARY:
			continue
		var flow := _exec(stmts[i], frame)
		# `abort` unwinds every frame, so it is tested here rather than carried as
		# a Flow: the builtin is reached from inside an *expression* and an
		# expression has no way to report a flow at all. Same shape as `_suspending`
		# below and for the same reason.
		if _aborting:
			return Flow.ABORT
		if _suspending:
			# Tested instead of `flow == SUSPEND` so that one check covers both the
			# ordinary case -- a nested block handed SUSPEND up -- and a `play`
			# reached from inside an expression, where the arm that ran it has no
			# way to report anything but its own value.
			if flow != Flow.SUSPEND and str(stmts[i].get("node", "")) != "call_stmt":
				# The second case, named. Unwinding is at statement granularity, so
				# the *rest of this one statement* has already run against the VOID
				# the frozen call answered. `play` and `go` are commands and this is
				# only reachable through a handler that calls one and is then used
				# for its value; zero sites in either corpus, and silence here would
				# make the first one look like arithmetic.
				report(LingoDiagnostics.BUILTIN, "suspend inside an expression")
			_suspended.append(_at_position({
				"k": "block", "stmts": stmts, "i": i + 1, "frame": frame,
			}))
			return Flow.SUSPEND
		if flow != Flow.NORMAL:
			return flow
	return Flow.NORMAL


## Stamp a resume record with where it was written, so a diagnostic raised by a
## resumed statement still names the handler it is lexically in rather than
## whatever was running when the thaw happened.
func _at_position(record: Dictionary) -> Dictionary:
	record["script"] = _script_name
	record["handler"] = _handler_name
	record["hbody"] = _current_handler
	return record


## The four loops, each able to say where it had got to.
##
## They were inline in `_exec` and are functions now for one reason: a suspend
## inside a loop body has to record more than "the rest of this block" — the loop
## has to keep going afterwards, and `repeat with` and `repeat in` have to keep
## going *from the right element*. Resuming re-enters the same function with the
## position the record carried, and the body's own tail is a separate record
## sitting inside this one, so the two compose without the loop knowing about it.
##
## `repeat with`'s bounds are captured rather than re-evaluated on resume:
## Director evaluates `to` once, and an expression that has changed in the
## meantime — which, given the whole point is that a frame went by, it may have —
## would otherwise silently change the trip count mid-loop.
func _repeat_while(stmt: Dictionary, frame: Dictionary) -> int:
	while true:
		var condition: Variant = _eval(stmt.get("cond", {}), frame)
		if _suspending:
			return Flow.SUSPEND
		if not LingoValue.truthy(condition):
			break
		_steps += 1
		if _steps > MAX_STEPS:
			_fail("repeat while did not terminate")
			return Flow.ABORT
		_breathe()
		var flow := _exec_block(stmt.get("body", []), frame)
		if flow == Flow.SUSPEND:
			_suspended.append(_at_position({
				"k": "repeat_while", "stmt": stmt, "frame": frame}))
			return flow
		if flow == Flow.EXIT_REPEAT:
			break
		if flow == Flow.RETURN or flow == Flow.ABORT:
			return flow
	return Flow.NORMAL


func _repeat_with(stmt: Dictionary, frame: Dictionary, name: String,
		from: int, to: int, down: bool) -> int:
	var step := -1 if down else 1
	var i := from
	while (i <= to) if not down else (i >= to):
		_set_var(name, i, frame)
		var flow := _exec_block(stmt.get("body", []), frame)
		if flow == Flow.SUSPEND:
			_suspended.append(_at_position({
				"k": "repeat_with", "stmt": stmt, "frame": frame,
				"name": name, "i": i + step, "to": to, "down": down}))
			return flow
		if flow == Flow.EXIT_REPEAT:
			break
		if flow == Flow.RETURN or flow == Flow.ABORT:
			return flow
		i += step
		_steps += 1
		if _steps > MAX_STEPS:
			_fail("repeat with did not terminate")
			return Flow.ABORT
		_breathe()
	return Flow.NORMAL


func _repeat_in(stmt: Dictionary, frame: Dictionary, name: String,
		items: Array, at: int) -> int:
	for index in range(at, items.size()):
		_set_var(name, items[index], frame)
		var flow := _exec_block(stmt.get("body", []), frame)
		if flow == Flow.SUSPEND:
			_suspended.append(_at_position({
				"k": "repeat_in", "stmt": stmt, "frame": frame,
				"name": name, "items": items, "i": index + 1}))
			return flow
		if flow == Flow.EXIT_REPEAT:
			break
		if flow == Flow.RETURN or flow == Flow.ABORT:
			return flow
	return Flow.NORMAL


func _repeat_forever(stmt: Dictionary, frame: Dictionary) -> int:
	while true:
		_steps += 1
		if _steps > MAX_STEPS:
			_fail("bare repeat did not terminate")
			return Flow.ABORT
		_breathe()
		var flow := _exec_block(stmt.get("body", []), frame)
		if flow == Flow.SUSPEND:
			_suspended.append(_at_position({
				"k": "repeat_forever", "stmt": stmt, "frame": frame}))
			return flow
		if flow == Flow.EXIT_REPEAT:
			break
		if flow == Flow.RETURN or flow == Flow.ABORT:
			return flow
	return Flow.NORMAL


## Let the platform have its turn while a repeat is spinning.
##
## Called from the three loops that can spin without the movie stepping. It is
## **not** a yield: nothing about this interpreter's state is unwound, the
## handler keeps the stack it has, and the loop resumes on the next line. All it
## does is give the host the chance to do whatever a Director host does between
## two machine instructions -- which, on this one, is pump the OS event queue so
## that `the mouseDown`, `the mouseLoc` and the modifier keys are answers about
## now rather than about the moment the handler was entered.
##
## The host is asked rather than told: `lingo_host.gd` and every harness host
## has no window and no event queue, so the absence of the method is the correct
## answer for them and not a missing binding. See `BREATHE_MS` for why this
## exists at all and what it costs.
func _breathe() -> void:
	if (_steps & (BREATHE_EVERY - 1)) != 0:
		return
	var now := Time.get_ticks_msec()
	if now - _breathed_at < BREATHE_MS:
		return
	_breathed_at = now
	if host != null and host.has_method("breathe"):
		host.call("breathe")


func _exec(stmt: Dictionary, frame: Dictionary) -> int:
	_steps += 1
	if _steps > MAX_STEPS:
		_fail("step budget exhausted")
		return Flow.ABORT
	_line = int(stmt.get("line", _line))
	# `the trace`. One boolean test per statement while it is off, which is what
	# lets the switch exist at all -- Director's own trace is a movie property and
	# a script may turn it on for one handler and off again.
	if LingoDiagnostics.trace:
		LingoDiagnostics.trace_line("== %s: %s (%d) %s"
			% [_script_name, _handler_name, _line, str(stmt.get("node", "?"))])
	match str(stmt.get("node", "")):
		"global", "property":
			# **`property` means two different things and the frame decides
			# which.** Inside a handler running on a script object (§7.1) it
			# declares an *instance* variable on that object; everywhere else this
			# port has no object to hang one on, so it does what it has always
			# done and declares a global.
			#
			# That second reading is a divergence and it is deliberate: a **movie
			# or frame script** declaring `property` has nowhere else for the name
			# to live. (This example used to say "a behaviour this port reaches as
			# a script rather than as an instance", which `038b79a4` made false --
			# a behaviour gets a real instance and its `property` names are seeded
			# into it. The rule below is unchanged; only the case it names was
			# stale, and `bugs.md` 83 quoted it as evidence.) Making it a local
			# instead
			# would lose the value between the handlers of one behaviour, which is
			# the one thing a `property` is for. It is narrowed rather than
			# widened -- an object-scoped frame no longer leaks the name into the
			# movie's globals, where a second instance of the same script would
			# have shared it.
			var me: Variant = frame.get("me", null)
			var declaring_props := me != null and str(stmt.get("node", "")) == "property"
			for name in stmt.get("names", []):
				var key := str(name).to_lower()
				if declaring_props:
					(me as Object).call("declare", key)
					continue
				_declare_global(key, frame)
			return Flow.NORMAL
		"assign":
			_assign(stmt.get("target", {}), _eval(stmt.get("value", {}), frame), frame)
			return Flow.NORMAL
		"put":
			var value: Variant = _eval(stmt.get("value", {}), frame)
			var target: Dictionary = stmt.get("target", {})
			var mode := str(stmt.get("mode", "into"))
			if mode == "into":
				_assign(target, value, frame)
			else:
				var existing := LingoValue.to_str(_eval(target, frame))
				var joined := (
					existing + LingoValue.to_str(value)
					if mode == "after"
					else LingoValue.to_str(value) + existing
				)
				_assign(target, joined, frame)
			return Flow.NORMAL
		"put_echo":
			## `put <expr>` with no `into` -- Director's message-window echo.
			##
			## **The expression is evaluated.** In the reference `put` is an
			## ordinary builtin (`lingo-builtins.cpp:b_put`), so its arguments are
			## on the stack before it runs and every side effect in them has
			## already happened; here the parser built the expression and this arm
			## dropped it unevaluated, so `put someHandler()` never called the
			## handler and `put member(x).name` never touched the cast.
			##
			## That is the same shape as an unbound property write and it hid for
			## the same reason: the statement returns cleanly, nothing is missing
			## from a log, and only a caller relying on the side effect can tell.
			## Found by `tools/property_surface.gd` -- its unbound-property probe
			## read through a `put` and no report came out, because nothing had
			## been read.
			##
			## The echo itself goes to the trace rather than to the console. This
			## port has no message window; `the trace` and `the traceLogFile` are
			## what stands in for one (§3), and 9,363 `put` sites means an
			## unconditional print is a flood rather than a diagnostic.
			var echoed: Variant = null
			if stmt.get("value", null) != null:
				echoed = _eval(stmt.get("value", {}), frame)
			if LingoDiagnostics.trace:
				LingoDiagnostics.trace_line("-- %s" % LingoValue.to_str(echoed))
			return Flow.NORMAL
		"put_echo_many":
			## `put a, b, c` -- the same echo with several values. Director joins
			## them with a space in the message window.
			##
			## Every value is evaluated, for the reason the arm above spells out:
			## the reference has `put` as an ordinary builtin, so its arguments are
			## on the stack and their side effects have already happened. Evaluating
			## only the first would be the same silent half-execution.
			var parts := PackedStringArray()
			for value_node in stmt.get("values", []):
				parts.append(LingoValue.to_str(_eval(value_node, frame)))
			if LingoDiagnostics.trace:
				LingoDiagnostics.trace_line("-- %s" % " ".join(parts))
			return Flow.NORMAL
		"call_stmt":
			_eval(stmt.get("call", {}), frame)
			return Flow.NORMAL
		"if":
			var condition: Variant = _eval(stmt.get("cond", {}), frame)
			# A condition that froze part-way answers VOID, and a branch chosen from
			# VOID is a branch nobody wrote. `_exec_from` takes the chain from here.
			if _suspending:
				return Flow.SUSPEND
			if LingoValue.truthy(condition):
				return _exec_block(stmt.get("then", []), frame)
			return _exec_block(stmt.get("else", []), frame)
		"repeat_while":
			return _repeat_while(stmt, frame)
		"repeat_with":
			var name := str(stmt.get("var", "")).to_lower()
			var from := LingoValue.to_int(_eval(stmt.get("from", {}), frame))
			var to := LingoValue.to_int(_eval(stmt.get("to", {}), frame))
			if _suspending:
				return Flow.SUSPEND
			return _repeat_with(stmt, frame, name, from, to,
				bool(stmt.get("down", false)))
		"repeat_in":
			var name := str(stmt.get("var", "")).to_lower()
			var seq: Variant = _eval(stmt.get("seq", {}), frame)
			if _suspending:
				return Flow.SUSPEND
			var items: Array = seq if typeof(seq) == TYPE_ARRAY else []
			return _repeat_in(stmt, frame, name, items, 0)
		"repeat_forever":
			return _repeat_forever(stmt, frame)
		"case":
			var subject: Variant = _eval(stmt.get("subject", {}), frame)
			if _suspending:
				return Flow.SUSPEND
			for branch in stmt.get("branches", []):
				for candidate in (branch as Dictionary).get("values", []):
					if LingoValue.equal(subject, _eval(candidate, frame)):
						return _exec_block((branch as Dictionary).get("body", []), frame)
			return _exec_block(stmt.get("default", []), frame)
		"tell":
			## `tell window("map.dxr") / … / end tell` and `tell the stage / … /
			## end tell` — Director sends the body's *messages* to another movie
			## (DIRECTOR_ENGINE.md §14). This used to run the body here with a
			## comment saying there was only one stage, and that is worse than
			## unimplemented: `tell window("joke.dxr") / puppetSprite(3, 1)` then
			## puppets channel 3 of the *host* room and swaps its member, so
			## clicking the joke bottle in DAY1 corrupted DAY1.
			##
			## What crosses and what does not, measured over the corpus
			## (`tools/window_survey.gd`): 194 `tell` statements, and the bodies
			## contain sprite writes, `the centerStage`, `go`, `play`, handler
			## calls into the target movie (`peoplefunk`, `displayobject`,
			## `cursorfunk`), and — 15 times — a *local* variable assignment,
			## `tell the stage / rir = the movieName / end tell`, whose value is
			## read after `end tell`. So locals stay in the caller's frame and
			## only the messages move. That is Director's rule and it is the one
			## the corpus depends on: MAP's every button reads `the movieName` of
			## the stage this way to decide where to send it.
			##
			## The target's own script hierarchy answers the messages, so
			## `frame["script"]` is dropped for the body: a `tell the stage /
			## peoplefunk()` must reach the *stage's* movie handler and not a
			## same-named handler in the script the `tell` was written in.
			##
			## A host with no `tell_target` is the single-stage case this file
			## started in — `lingo/lingo_host.gd` binds `open`/`forget` as a
			## navigation on one stage — and there the body still simply runs,
			## unchanged. A host that *has* the method and cannot resolve the
			## target is different: the window is not there, and running the body
			## on whoever is asking is the corruption above. So the body is
			## dropped and the miss reported.
			var body: Array = stmt.get("body", [])
			if host == null or not host.has_method("tell_target"):
				return _exec_block(body, frame)
			var target: Variant = _eval(stmt.get("target", {}), frame)
			var other: Variant = _host_call("tell_target", [target])
			if other == null or not (other is Object) \
					or not (other as Object).has_method("run_told"):
				report(LingoDiagnostics.BUILTIN, "tell target")
				return Flow.NORMAL
			return (other as Object).run_told(body, frame, self)
		"when":
			## `when keyDown then go to "mainmenub4"` — Director 3's primary event
			## handler (§6.3, §11.2). **Installed here, not run here.**
			##
			## The distinction is the whole point. Executing the body where the
			## `when` sits turns a conditional statement into an unconditional
			## one, which is what the original misparse did: `then go to
			## "mainmenub4"` became a statement of its own and `strtgame`'s
			## `gomenu` navigated away the moment it was called rather than when a
			## key was pressed. So this stores the body against its event and
			## answers NORMAL, and something else fires it when that event
			## actually happens — `primary(event)` below.
			##
			## This used to be a recorded gap, on the grounds that the port had no
			## tier 1 to install into. It has one now for keys, so the honest
			## answer is no longer a report.
			primary_handlers[str(stmt.get("event", "")).to_lower()] = stmt.get("body", [])
			return Flow.NORMAL
		"delete_chunk":
			## `delete word 1 of str`. The source is read, the chunk and its
			## separator are removed, and the result is written back through
			## `_assign` -- so it works on anything a chunk can be written to: a
			## variable, a field, a member's text.
			##
			## A chunk of something that is not assignable (`delete word 1 of
			## "literal"`) computes and then reports, rather than failing
			## silently: `_assign`'s own fall-through is what says so.
			var doomed: Dictionary = stmt.get("target", {})
			if str(doomed.get("node", "")) != "chunk":
				report(LingoDiagnostics.BUILTIN, "delete of a non-chunk")
				return Flow.NORMAL
			var source: Dictionary = doomed.get("source", {})
			var from := LingoValue.to_int(_eval(doomed.get("start", {}), frame))
			var upto_node: Variant = doomed.get("stop", null)
			var upto := LingoValue.to_int(_eval(upto_node, frame)) if upto_node != null else from
			_assign(source, LingoValue.delete_chunk(
				_chunk_source_text(source, frame),
				str(doomed.get("kind", "line")), from, upto, item_delimiter), frame)
			return Flow.NORMAL
		"exit_repeat":
			return Flow.EXIT_REPEAT
		"next_repeat":
			return Flow.NEXT_REPEAT
		"exit":
			return Flow.RETURN
		"return":
			var node: Variant = stmt.get("value", null)
			_return_value = _eval(node, frame) if node != null else null
			return Flow.RETURN
		_:
			_fail("unknown statement %s" % str(stmt.get("node", "?")))
			return Flow.NORMAL


# ---------------------------------------------------------------- assignment


func _assign(target: Dictionary, value: Variant, frame: Dictionary) -> void:
	match str(target.get("node", "")):
		"var":
			_set_var(str(target.get("name", "")).to_lower(), value, frame)
		"field":
			_set_field_node(target, LingoValue.to_str(value), frame)
		"member_ref":
			## `put readFile(tmp) into member FieldName` -- a write to a bare member
			## reference is a write to its **text**. Director's `field "x"` and
			## `member "x"` name the same castmember and differ only in which
			## property a bare reference stands for; for a field or text member
			## that property is the text, which is why `the text of member "x"` and
			## `member "x"` round-trip through each other.
			##
			## Missing entirely until now, and the shape of the miss is the point:
			## every *read* worked, every `.text` spelling worked, and only the bare
			## write had nowhere to land. It fell to the default arm, which records
			## "cannot assign to member_ref" in `errors` and **returns normally** --
			## so the statement was a silent no-op and the handler ran on to
			## completion, which is why nothing anywhere reported a problem.
			##
			## Magic Hat's `LoadFileToField` is the handler that shows it:
			##
			##     openFile(tmp, Fname, 1)
			##     if status(tmp) = 0 then
			##       put readFile(tmp) into member FieldName   <- dropped
			##       closeFile(tmp)
			##
			## The file opened, the read succeeded, the file closed, and the field
			## stayed empty -- so `ReadInifile` then found no `[PATH]`, no `[END]`
			## and no `[ENDFILE]`, left `the searchPaths` empty, and raised the
			## game's own `alert("[ENDFILE] is missing at the end of the ini
			## file")`. An engine gap wearing a data file's error message.
			##
			## Not one title's idiom, though the shipped corpus survived it. Piposh
			## 1 English and Russian carry 8 sites where the Hebrew build spells the
			## same statement `into field`, and both of the ones measured turn out
			## to be covered:
			##
			##   * `put 1000 into member "GlobalMoney" of castLib 7` (`Day1.dir`) is
			##     idempotent -- the member's authored text is already `1000`, and
			##     the probe reads `1000` with this arm disabled.
			##   * `put item i - 27 of SaveNames into member ("save" & i - 27)`
			##     (`Mainmenu.dir`) is one of *two* loops filling the save-slot
			##     names; the other spells `into field ("save" & i) of castLib 1`
			##     and always ran.
			##
			## Recorded because the coincidence is the warning, not the reassurance:
			## the arm was missing for as long as this port has existed and no title
			## ever showed it, which is precisely how a silent no-op survives.
			_host_call("set_member_prop", [
				_eval(target.get("which", {}), frame),
				_cast_of(target, frame), "text", value,
			])
		"sprite_prop":
			var channel := LingoValue.to_int(_eval(target.get("which", {}), frame))
			_host_call("set_sprite_prop", [channel, str(target.get("prop", "")), value])
		"member_prop":
			_host_call("set_member_prop", [
				_eval(target.get("which", {}), frame),
				_cast_of(target, frame),
				str(target.get("prop", "")),
				value,
			])
		"field_prop":
			## `set the <prop> of field "x" to v` — `setTheField`, which is
			## `member->setField(prop, v)` in the reference
			## (`lingo-the.cpp:2373-2398`) and not a write to the text.
			##
			## This arm wrote the **text** whatever the property was, so
			## `set the textSize of field "globalmoney" to 24` — Piposh 1's slot
			## machine, in all three language builds — replaced the money on screen
			## with the string `24`. A write that lands on the value it was not
			## addressing round-trips perfectly, because the next read of `the text`
			## answers what it put there.
			var set_prop := str(target.get("prop", "")).to_lower()
			if host != null and host.has_method("set_field_prop"):
				_host_call("set_field_prop", [
					_field_designator(target, frame),
					_cast_of(target, frame), set_prop, value,
				])
				return
			# A host with no property spelling can still serve the one property
			# that *is* the text; anything else has nowhere to land and is
			# reported rather than written over the contents.
			if set_prop == "text":
				_set_field_node({"node": "field", "name": target.get("name", {}),
					"cast": target.get("cast", null)}, LingoValue.to_str(value), frame)
				return
			report(LingoDiagnostics.MEMBER_PROP, "%s of field" % set_prop)
		"prop":
			var prop := str(target.get("prop", "")).to_lower()
			if prop == "itemdelimiter":
				item_delimiter = LingoValue.to_str(value)
				return
			# `the result` and `the paramCount` are read-only in Director -- the
			# first is written by returning from a handler and the second by
			# calling one -- so a write is dropped here rather than passed to the
			# host, where it would land in a system-property table that accepts
			# any name and make the property look settable.
			if prop == "result" or prop == "paramcount":
				return
			_host_call("set_system_prop", [prop, value])
		"sound_prop":
			_host_call("set_sound_prop", [
				LingoValue.to_int(_eval(target.get("which", {}), frame)),
				str(target.get("prop", "")), value,
			])
		"cast_prop":
			## Every one of Director's five cast-library properties is read-only
			## except `the preLoadMode`, which this port does not bind. So the
			## write has nowhere to land -- and it goes to the host anyway rather
			## than being dropped here, because the host is where the report comes
			## from and a write silently discarded is the shape §19 exists to
			## catch.
			_host_call("set_cast_prop", [
				_eval(target.get("which", {}), frame),
				str(target.get("prop", "")), value,
			])
		"window_prop":
			## `set the windowType of window "joke.dxr" to 2`, the designator
			## spelling. The dot spelling `window("joke.dxr").windowType = 2` is
			## the same statement and is handled in the `dot` arm below; both now
			## reach the host through `set_window_prop`, so the window the
			## statement addresses is carried rather than discarded.
			##
			## The fallback is the single-stage host this file started against,
			## which has no `set_window_prop`: there the property went to
			## `set_system_prop`, where `lingo_host.gd`'s WINDOW_FIELDS table
			## accepts and drops it, and it still does.
			var which_window: Variant = _eval(target.get("which", {}), frame)
			var window_prop := str(target.get("prop", "")).to_lower()
			if host != null and host.has_method("set_window_prop"):
				_host_call("set_window_prop", [which_window, window_prop, value])
			else:
				_host_call("set_system_prop", [window_prop, value])
		"prop_of":
			var owner: Dictionary = target.get("target", {})
			if str(owner.get("node", "")) == "sprite_ref":
				var channel := LingoValue.to_int(_eval(owner.get("which", {}), frame))
				_host_call("set_sprite_prop", [channel, str(target.get("prop", "")), value])
				return
			# `set the ancestor of me to new(script "base")` -- §7.1's designator
			# spelling of an instance variable. Evaluated rather than pattern
			# matched on the node, because the owner is any expression that yields
			# an object: `me`, a global holding one, an element of a list.
			var prop_owner: Variant = _eval(owner, frame)
			if LingoObject.is_object(prop_owner):
				_set_object_prop(prop_owner, str(target.get("prop", "")), value)
				return
			_fail("cannot assign to prop_of %s" % str(owner.get("node", "?")))
		"dot":
			var owner_node: Dictionary = target.get("target", {})
			var prop_name := str(target.get("prop", ""))
			if str(owner_node.get("node", "")) == "sprite_ref":
				var channel := LingoValue.to_int(_eval(owner_node.get("which", {}), frame))
				_host_call("set_sprite_prop", [channel, prop_name, value])
				return
			if str(owner_node.get("node", "")) == "member_ref":
				_host_call("set_member_prop", [
					_eval(owner_node.get("which", {}), frame),
					_cast_of(owner_node, frame), prop_name, value,
				])
				return
			if str(owner_node.get("node", "")) == "field":
				_assign(_field_prop_node(owner_node, prop_name), value, frame)
				return
			## `window("joke.dxr").windowType = 2` and friends. The owner is a call
			## returning a window handle, and the property belongs to that window
			## — so it goes to the host with the handle, the same as the
			## `the … of window` designator spelling above.
			##
			## The String test below is the single-stage host: `lingo_host.gd`'s
			## `window` builtin answers the movie's stem, there is no window to
			## place, and a `_fail` here would report a gap on every one of the 21
			## sites that set `windowType`.
			var window_owner: Variant = _eval(owner_node, frame)
			# **A sprite reference that arrived through a handler**, which the
			# `sprite_ref` arm above cannot catch because the owner node is a
			# call: `me.ItemSprite().visible = 0`. Ahead of the window route for
			# the same reason the object arm is -- `set_window_prop` accepts any
			# property name and drops it, so a miss here is silent.
			if LingoSpriteRef.is_ref(window_owner):
				_host_call("set_sprite_prop", [
					(window_owner as LingoSpriteRef).channel, prop_name, value])
				return
			# `me.pCount = 3`, the dot spelling of the designator arm above. Ahead
			# of the window route, because a script object is not a window handle
			# and `set_window_prop` would file it under a window named after the
			# object's own `_to_string`.
			if LingoObject.is_object(window_owner):
				_set_object_prop(window_owner, prop_name, value)
				return
			if host != null and host.has_method("set_window_prop"):
				_host_call("set_window_prop", [window_owner, prop_name.to_lower(), value])
				return
			if typeof(window_owner) == TYPE_STRING:
				return
			_fail("cannot assign to %s.%s" % [str(owner_node.get("node", "?")), prop_name])
		"chunk":
			_assign_chunk(target, value, frame)
		"index":
			## `myList[2] = x` and `myPropList[1] = 0` — D5's subscript write,
			## which is `setAt(myList, 2, x)` (§1.3) and reaches the same builtin
			## so the two spellings cannot drift.
			##
			## The read arm has existed for as long as the parser has produced
			## `index` nodes and this one never did, so the write fell to the
			## fall-through below and was *reported* rather than performed. That
			## is the better half of §19 — it says so — but it is still a
			## statement that does not happen: Magic Hat's `RemoveMenu` clears the
			## slot with `gAllMenus[MenuPos] = 0` before deleting it, and
			## `BasicMenuObject.Remove` does the same to `prButtons[1]`.
			##
			## No arm for a point or a rect, and that is not an oversight:
			## `Vector2` and `Rect2` are Godot value types, so the container this
			## evaluates is a *copy* and a write to it would be lost. Reported
			## rather than silently dropped, which is why the `_fail` below is
			## reached rather than a mutation attempted.
			var container: Variant = _eval(target.get("target", {}), frame)
			if typeof(container) == TYPE_ARRAY or typeof(container) == TYPE_DICTIONARY:
				var subscript: Variant = _eval(target.get("index", {}), frame)
				var set_handled: Array = []
				# `myPropList[#key] = v` names the property, and it *adds* one
				# that is not there yet -- `b_setaProp`'s PARRAY arm pushes a new
				# `PCell` on a miss (`lingo-builtins.cpp:1460-1464`).
				if typeof(container) == TYPE_DICTIONARY and not _is_position(subscript):
					Builtins.call_builtin(
						"setaProp", [container, subscript, value], set_handled)
					return
				var slot := LingoValue.to_int(subscript)
				Builtins.call_builtin("setAt", [container, slot, value], set_handled)
				return
			_fail("cannot assign to index of %s" % type_string(typeof(container)))
		_:
			_fail("cannot assign to %s" % str(target.get("node", "?")))


## Write a property on a script object from outside it (§7.1).
##
## **A write from outside creates the property when the chain does not declare
## it.** That is Director's own asymmetry and it is the opposite of the rule
## inside a handler, where only a `property` statement creates one: a parent
## script's caller is expected to be able to configure an instance it has just
## built, and refusing the write would drop it in silence -- the shape §19 calls
## the worst state there is.
func _set_object_prop(obj: Variant, prop: String, value: Variant) -> void:
	if bool((obj as Object).call("set_slot", prop, value)):
		return
	(obj as Object).call("declare", prop)
	(obj as Object).call("set_slot", prop, value)


func _assign_chunk(target: Dictionary, value: Variant, frame: Dictionary) -> void:
	## `put x into line i of field "f"` and the nested forms. The source has to be
	## read, edited and written back, so only sources that are themselves
	## assignable can carry a chunk write.
	var kind := str(target.get("kind", "line"))
	var start := LingoValue.to_int(_eval(target.get("start", {}), frame))
	var stop_node: Variant = target.get("stop", null)
	var stop := LingoValue.to_int(_eval(stop_node, frame)) if stop_node != null else start
	var source: Dictionary = target.get("source", {})
	var text := _chunk_source_text(source, frame)
	var updated := LingoValue.set_chunk(text, kind, start, stop, value, item_delimiter)
	_assign(source, updated, frame)


## The text a chunk expression is taken *from*.
##
## Everything except a cast-member reference is its own string, and for those
## `_eval` is the answer. A member reference is not: `_eval`'s `member_ref` arm
## answers the member's **number**, because that is what `member("x") = 3` and
## `sprite(1).member = member("y")` compare and assign. So
## `member("LevelList").line[i]` read chunks of the *digits of a member number* —
## `line 1 of "217"` is "217" — rather than of the field's text.
##
## Measured on Magic Hat's `FillSectionsInfo`, whose loop is
## `repeat while i <= member(FieldName).line.count`: the field held 94 lines and
## the count came back 1, so the loop ran once, built no sections, and every menu
## in the movie went missing. `the number of lines in field "menudata"` — the
## other spelling of the same question, on the `field` node, which does answer
## text — said 94 in the same run.
##
## Director's rule is that a bare member reference *stands for* its text wherever
## text is wanted, which is the same rule `_assign`'s `member_ref` arm writes by:
## the two are the read and write halves of one behaviour and they now agree, so
## `member("x").line[2] = "a"` round-trips instead of overwriting the member with
## a rewritten member number.
##
## `member_number` is here too. `the number of member "x"` is a different
## expression, but the node shape is the same and a chunk of it means the same
## thing.
func _chunk_source_text(node: Variant, frame: Dictionary) -> String:
	if typeof(node) == TYPE_DICTIONARY:
		var kind := str((node as Dictionary).get("node", ""))
		if kind == "member_ref" or kind == "member_number":
			return LingoValue.to_str(_host_call("get_member_prop", [
				_eval((node as Dictionary).get("which", {}), frame),
				_cast_of(node, frame), "text",
			]))
	return LingoValue.to_str(_eval(node, frame))


## Bind one `global` name for the frame that declared it.
##
## Two callers and they must not drift: the `global` *statement* inside a
## handler, and `_invoke` seeding the script-level declarations that apply to
## every handler in a script. Both do the same two things -- mark the name on
## the frame so `_set_var` writes it to the movie rather than to the locals, and
## give the movie an entry for it if this is the first sighting.
func _declare_global(key: String, frame: Dictionary) -> void:
	(frame["globals"] as Dictionary)[key] = true
	if not globals.has(key):
		# An unset global is VOID, not 0. It matters: `effectspath &
		# "x.aif"` must be "x.aif", and 0 would make it "0x.aif".
		globals[key] = null


func _set_var(name: String, value: Variant, frame: Dictionary) -> void:
	if host != null and host.has_method("owns_global") and host.owns_global(name):
		host.set_global(name, value)
		return
	# The write half of the instance-variable scope above, in the same order and
	# for the same reason. `set_slot` answers false for a name no object in the
	# chain declares, so a handler running on an object still writes ordinary
	# locals and globals -- an assignment does **not** create an instance
	# variable, only a `property` declaration does.
	var me: Variant = frame.get("me", null)
	if me != null and not (frame.get("locals", {}) as Dictionary).has(name):
		if bool((me as Object).call("set_slot", name, value)):
			return
	if (frame.get("globals", {}) as Dictionary).has(name) or globals.has(name):
		globals[name] = value
		return
	(frame["locals"] as Dictionary)[name] = value


## `put x into field <designator>`.
##
## **The designator keeps its type.** `field 122` and `field "122"` are two
## different references in Director -- the first is member number 122, the second
## is a member *named* `122`, which no cast in this corpus has -- and stringifying
## the subscript here collapsed the first onto the second. The host resolves a
## String as a name (`preview/members.gd:resolve_ref`), so every numeric field
## reference resolved to nothing: the write was dropped and the matching read
## answered "".
##
## `eat.dir`'s plate game is what that cost. Its frame script counts nine
## countdown fields down with `repeat with i = 122 to 130 / put value(the text of
## field i) - 1 into field i`, and the click handler on the nine characters gates
## the pass on `value(the text of field ("chara" & n)) <= 4`. The countdown never
## moved, so the gate never opened and the `< 0` arm that ends the game never
## fired either: clicking a character did nothing and the scene could be neither
## won nor lost.
func _set_field_node(node: Dictionary, text: String, frame: Dictionary) -> void:
	_host_call("set_field", [
		_field_designator(node, frame),
		_cast_of(node, frame),
		text,
	])


## The subscript of a `field` designator, **unstringified**.
##
## A number stays a number and everything else becomes its string, which is what
## `resolve_ref` reads: `field ("chara" & n)` is a name and has always worked,
## and it is the same expression node as `field 122`. Only the type tells them
## apart, so only the type may be thrown away.
## The `field_prop` node `field("x").<prop>` means, built from the `field` node the
## dot's owner is. `bugs.md` 76.
##
## **A synthesised node rather than a second copy of the arm**, and that is the
## whole point of the function. Director has two spellings of one thing --
## `the textSize of field "x"` and `field("x").textSize` -- and the reference
## reaches `member->getField(prop)` from both (`lingo-the.cpp:2334-2372` for the
## designator; the dot form is the same `kTheField` access with the object
## supplied by the expression). Two arms doing the property lookup separately is
## how one of them ends up with the cast argument dropped, or with the
## host-without-`get_field_prop` fallback in only one of the two, and neither
## divergence would show up as a failure -- both spellings answer *something*.
##
## What the dot arm did instead: `_eval`'s `dot` had no `field` case, so it
## evaluated the owner -- which yields the field's **text** -- and asked
## `get_member_prop` for a member *named after whatever the player had typed*.
## `field("save1").textSize` therefore read a property of a member called
## `Tal` when the save slot said `Tal`, and answered VOID when nothing was
## named that. `_assign` took the identical route.
##
## 0 sites in the six titles use the spelling, so this is built because Director
## has it and not because the corpus asked -- and it is one arm rather than a
## file for exactly that reason.
static func _field_prop_node(owner: Dictionary, prop: String) -> Dictionary:
	return {
		"node": "field_prop",
		"name": owner.get("name", {}),
		"cast": owner.get("cast", null),
		"prop": prop,
		"line": owner.get("line", 0),
	}


func _field_designator(node: Dictionary, frame: Dictionary) -> Variant:
	var value: Variant = _eval(node.get("name", {}), frame)
	if typeof(value) == TYPE_INT:
		return value
	# A float subscript is a number Lingo happens to hold as one -- `field (i + 1)`
	# where `i` came from a division -- and Director resolves it by number too.
	if typeof(value) == TYPE_FLOAT:
		return int(value)
	return LingoValue.to_str(value)


func _cast_of(node: Dictionary, frame: Dictionary) -> String:
	var cast: Variant = node.get("cast", null)
	if cast == null:
		return ""
	return LingoValue.to_str(_eval(cast, frame))


# ---------------------------------------------------------------- expressions


func _eval(node: Variant, frame: Dictionary) -> Variant:
	if node == null:
		return 0
	if typeof(node) != TYPE_DICTIONARY:
		return node
	var expr: Dictionary = node
	match str(expr.get("node", "")):
		"num":
			return expr.get("value", 0)
		"str":
			return str(expr.get("value", ""))
		"sym":
			# §11.2's symbol literal. A StringName rather than a String, because
			# that is the type `lingo_builtins.gd`'s `ilk` answers `#symbol` for
			# and `symbolP` answers true for -- a String would be a symbol that
			# does not know it is one.
			return StringName(str(expr.get("value", "")))
		"var":
			return _read_var(str(expr.get("name", "")), frame)
		"list":
			var items: Array = []
			for item in expr.get("items", []):
				items.append(_eval(item, frame))
			return items
		"proplist":
			var dict := {}
			for pair in expr.get("pairs", []):
				dict[LingoValue.to_str(_eval((pair as Dictionary).get("key", {}), frame))] = \
					_eval((pair as Dictionary).get("value", {}), frame)
			return dict
		"unary":
			var value: Variant = _eval(expr.get("value", {}), frame)
			if str(expr.get("op", "")) == "not":
				return 0 if LingoValue.truthy(value) else 1
			return LingoValue.sub(0, value)
		"binary":
			return _binary(str(expr.get("op", "")), expr, frame)
		"chunk":
			var kind := str(expr.get("kind", "line"))
			var start := LingoValue.to_int(_eval(expr.get("start", {}), frame))
			var stop_node: Variant = expr.get("stop", null)
			var stop := LingoValue.to_int(_eval(stop_node, frame)) if stop_node != null else start
			var text := _chunk_source_text(expr.get("source", {}), frame)
			return LingoValue.get_chunk(text, kind, start, stop, item_delimiter)
		"count":
			var unit := str(expr.get("unit", "line"))
			var source := _chunk_source_text(expr.get("source", {}), frame)
			return LingoValue.count_of(source, unit, item_delimiter)
		"field":
			# Unstringified, for the reason `_field_designator` gives: `field 122`
			# is a member number and `field "122"` is a member name.
			return _host_call("get_field", [
				_field_designator(expr, frame),
				_cast_of(expr, frame),
			])
		"field_prop":
			## `the <prop> of field "x"` — a **member property**, not the text.
			##
			## `Lingo::getTheField` resolves the designator to a cast member,
			## refuses one that is not a field, and answers `member->getField(prop)`
			## (`lingo-the.cpp:2334-2372`). This arm threw the property name away
			## and answered `get_field`, so `the name of field "save1"` came back as
			## whatever the player had typed into it and every one of the fifty
			## member properties read as the text.
			##
			## The fallback is for a host that predates the pair — `lingo_host.gd`
			## and the stub hosts in `tools/` bind `get_field` alone, and for them
			## `the text of field "x"` is still the whole of what they can answer.
			var field_name: Variant = _field_designator(expr, frame)
			var field_cast := _cast_of(expr, frame)
			if host != null and host.has_method("get_field_prop"):
				return _host_call("get_field_prop", [
					field_name, field_cast, str(expr.get("prop", "")),
				])
			return _host_call("get_field", [field_name, field_cast])
		"sprite_ref":
			## A reference, not a number -- `LingoValue.to_num` unwraps it to the
			## channel for everything that wants one, so this is invisible to
			## every consumer except a property access, which is the one that
			## needed it. See `lingo/lingo_sprite_ref.gd`.
			return LingoSpriteRef.new(
				LingoValue.to_int(_eval(expr.get("which", {}), frame)))
		"member_ref":
			return _host_call("member_number", [
				_eval(expr.get("which", {}), frame), _cast_of(expr, frame),
			])
		"member_number":
			return _host_call("member_number", [
				_eval(expr.get("which", {}), frame), _cast_of(expr, frame),
			])
		"sprite_number":
			return LingoValue.to_int(_eval(expr.get("which", {}), frame))
		"sprite_prop":
			return _host_call("get_sprite_prop", [
				LingoValue.to_int(_eval(expr.get("which", {}), frame)),
				str(expr.get("prop", "")),
			])
		"member_prop":
			return _host_call("get_member_prop", [
				_eval(expr.get("which", {}), frame),
				_cast_of(expr, frame),
				str(expr.get("prop", "")),
			])
		"sound_prop":
			## `the volume of sound 2`. A sound channel is a designator like a
			## sprite, not a call; parsing it as one made every such assignment
			## unreachable, and 52 scripts here set a channel's volume with none
			## of them taking effect.
			return _host_call("get_sound_prop", [
				LingoValue.to_int(_eval(expr.get("which", {}), frame)),
				str(expr.get("prop", "")),
			])
		"cast_prop":
			## `the name of castLib 2` (§5.1). Its own node for the reason
			## `sound_prop` and `window_prop` are: a cast library is a designator,
			## and without an arm the phrase becomes a property of a command-form
			## call to an unbound handler.
			return _host_call("get_cast_prop", [
				_eval(expr.get("which", {}), frame), str(expr.get("prop", "")),
			])
		"window_prop":
			## Read side of the designator above, and it has to reach the same
			## place the write did or the two disagree — which is the fault this
			## node exists to close. `tools/window_survey.gd` counts 21 writes of
			## `the windowType` and no read of any window property in the corpus,
			## so this arm is here for the engine rather than for this title.
			var which_window: Variant = _eval(expr.get("which", {}), frame)
			var window_prop := str(expr.get("prop", "")).to_lower()
			if host != null and host.has_method("get_window_prop"):
				return _host_call("get_window_prop", [which_window, window_prop])
			return _host_call("get_system_prop", [window_prop])
		"prop":
			var prop := str(expr.get("prop", "")).to_lower()
			# Three movie properties the interpreter owns outright, because the
			# thing that answers them is a call frame or a chunk separator and
			# both live here. Routing them out to the host and back would put the
			# state one object away from every consumer of it.
			if prop == "itemdelimiter":
				return item_delimiter
			if prop == "result":
				return _result
			if prop == "paramcount":
				return _current_args.size()
			return _host_call("get_system_prop", [prop])
		"prop_of":
			var owner: Dictionary = expr.get("target", {})
			if str(owner.get("node", "")) == "sprite_ref":
				return _host_call("get_sprite_prop", [
					LingoValue.to_int(_eval(owner.get("which", {}), frame)),
					str(expr.get("prop", "")),
				])
			if str(owner.get("node", "")) == "member_ref":
				return _host_call("get_member_prop", [
					_eval(owner.get("which", {}), frame),
					_cast_of(owner, frame), str(expr.get("prop", "")),
				])
			# `the ancestor of me`, `the pCount of myObject` -- §7.1's designator
			# read. The owner is evaluated once and its type decides, because the
			# same node shape reaches here for a member reference held in a
			# variable, which is what the fall-through below answers.
			return _value_prop(_eval(owner, frame), str(expr.get("prop", "")))
		"dot":
			var owner_node: Dictionary = expr.get("target", {})
			var prop_name := str(expr.get("prop", ""))
			if str(owner_node.get("node", "")) == "sprite_ref":
				return _host_call("get_sprite_prop", [
					LingoValue.to_int(_eval(owner_node.get("which", {}), frame)), prop_name,
				])
			if str(owner_node.get("node", "")) == "member_ref":
				return _host_call("get_member_prop", [
					_eval(owner_node.get("which", {}), frame),
					_cast_of(owner_node, frame), prop_name,
				])
			if str(owner_node.get("node", "")) == "field":
				return _eval(_field_prop_node(owner_node, prop_name), frame)
			return _value_prop(_eval(owner_node, frame), prop_name)
		"index":
			var target: Variant = _eval(expr.get("target", {}), frame)
			var subscript: Variant = _eval(expr.get("index", {}), frame)
			# `myPropList[#key]` is that property's value, not a position.
			if typeof(target) == TYPE_DICTIONARY and not _is_position(subscript):
				var read: Array = []
				return Builtins.call_builtin(
					"getaProp", [target, subscript], read)
			var index := LingoValue.to_int(subscript)
			match typeof(target):
				TYPE_ARRAY, TYPE_DICTIONARY, TYPE_VECTOR2, TYPE_RECT2:
					# **`myPropList[2]` is the second property's value**, and a
					# point and a rect are lists too (§1.3, §1.8). This arm knew
					# only `Array`, so every other container fell through to the
					# character chunk below and `gAllMenus[i]` answered one digit
					# of the printed form of a property list. Magic Hat's
					# `DisableAllMenus`/`HideAllMenus`/`EnableAllMenus` are each
					# `repeat with i = 1 to gAllMenus.count / <Op>Menu(
					# gAllMenus[i].Info(#name))`, so all three walked the right
					# number of times and messaged a string every time.
					#
					# Through `getAt` rather than an inline lookup, so the
					# subscript and the builtin cannot answer differently -- one
					# of them ordering a property list by key and the other by
					# position is the kind of disagreement that survives for
					# years. It also brings §8.6's rule with it: past either end
					# is VOID, where this arm used to answer 0.
					return _list_at(target, index)
			return LingoValue.get_chunk(LingoValue.to_str(target), "char", index, index)
		"call":
			return _call(expr, frame)
		_:
			_fail("unknown expression %s" % str(expr.get("node", "?")))
			return 0


func _binary(op: String, expr: Dictionary, frame: Dictionary) -> Variant:
	## Left, then right, then operate — for every operator including `and` and
	## `or`. **They do not short-circuit** (`docs/LINGO_SURFACE.md` §13 and §14;
	## §17 records this as a correction to §2.3, which said they did). Director
	## compiles them to a single opcode that pops two operands, so the code
	## generator emits no jump and the right side runs whatever the left answered.
	##
	## This port short-circuited until now, and the reason that is worse than a
	## harmless optimisation is Lingo-specific: a bare identifier that is not a
	## variable is a parameterless *handler call* (`_read_var`), so an operand
	## that reads like a variable can be `cursorfunk` or `talkproc`. A
	## short-circuiting interpreter silently stops calling handlers it cannot see
	## it is skipping, and the symptom — a cursor that does not change, a line of
	## speech that never starts — looks like a binding gap rather than a
	## conditional. `tools/lingo_logic_check.gd` asserts both sides run.
	##
	## The result is the integer 0 or 1, not a boolean and not the operand:
	## `5 and 7` is 1, so nothing downstream can read a truth value as data.
	var left: Variant = _eval(expr.get("left", {}), frame)
	var right: Variant = _eval(expr.get("right", {}), frame)
	match op:
		"and": return 1 if LingoValue.truthy(left) and LingoValue.truthy(right) else 0
		"or": return 1 if LingoValue.truthy(left) or LingoValue.truthy(right) else 0
		"+": return LingoValue.add(left, right)
		"-": return LingoValue.sub(left, right)
		"*": return LingoValue.mul(left, right)
		"/": return LingoValue.div(left, right)
		"mod": return LingoValue.modulo(left, right)
		"&": return LingoValue.concat(left, right)
		"&&": return LingoValue.concat_space(left, right)
		"=": return 1 if LingoValue.equal(left, right) else 0
		"<>": return 0 if LingoValue.equal(left, right) else 1
		"<": return 1 if LingoValue.compare(left, right) < 0 else 0
		">": return 1 if LingoValue.compare(left, right) > 0 else 0
		"<=": return 1 if LingoValue.compare(left, right) <= 0 else 0
		">=": return 1 if LingoValue.compare(left, right) >= 0 else 0
		"contains": return 1 if LingoValue.contains(left, right) else 0
		"starts": return 1 if LingoValue.starts(left, right) else 0
		"intersects", "within":
			return _host_call("call_builtin", [op, [left, right]])
		_:
			_fail("unknown operator %s" % op)
			return 0


## Read a property of a script object from outside it (§7.1).
##
## **Below `_binary` on purpose, not beside its two call sites in `_eval`.**
## `tools/lingo_surface_audit.gd` reads the interpreter's own movie properties
## out of the source between `func _eval` and `func _binary`, by scanning for
## `if <x> == "name":` guards -- so a helper placed in that span contributes its
## guards to the audited surface. Written between them, this one's `if key ==
## "script"` was reported as a *system property* the engine binds, and the audit
## then failed for a §19 row that should not exist.
##
## Two names answer without being instance variables, because Director answers
## them for every object: `the script` -- what the instance was made from -- and
## `the count of`, which §7.1 spells `the count of the properties`. Everything
## else is the chain walk, and a name nobody declares is VOID and is *reported*,
## because an object silently answering 0 for a misspelt property is how a script
## takes a branch nobody wrote.
func _object_prop(obj: Variant, prop: String) -> Variant:
	var key := prop.to_lower()
	if key == "script":
		return str((obj as Object).call("script_name"))
	if bool((obj as Object).call("has_slot", key)):
		return (obj as Object).call("get_slot", key)
	report(LingoDiagnostics.MEMBER_PROP, "%s of %s"
		% [key, str((obj as Object).call("script_name"))])
	return null


## Builtins reachable as a **property** of a value, the way ScummVM's
## `getObjectProp` fall-through reaches any one-argument builtin.
##
## Spelled out rather than inferred, because this port's builtin table carries no
## arity: `LingoBuiltins._geometry` answers `point` and `rect` for *any* argument
## count, so an unfiltered fallback would turn `myMember.rect` — a cast member's
## bounding box, read off a member reference held in a variable — into
## `rect(<member number>)`, which is VOID. The three here are the ones Director
## documents as properties of a value rather than as functions of one, and each
## is exercised: `count` by 6 handlers in Magic Hat's `objects.cst`, `length` by
## its scoreboard (`tmpScore.char[tmpScore.length - i + 1]`), `ilk` by
## `case ilk(value(lst[j].item[2])) of`.
const VALUE_PROPS := {"count": true, "ilk": true, "length": true}

## Where a point's and a rect's named accessors live in the list Director says
## they are. `getAt` is the reader; these only say which slot.
const POINT_SLOTS := {"loch": 1, "locv": 2}
const RECT_SLOTS := {"left": 1, "top": 2, "right": 3, "bottom": 4}


## `x.prop` and `the prop of x` on an evaluated **value** — D5's dot read, for
## everything that is not a script instance.
##
## Modelled on ScummVM `Lingo::getObjectProp` (`lingo-the.cpp:2495`), which
## branches on the receiver's type — object, property list, point, rect, cast
## reference, castLib reference, sprite reference — and, when none of them match,
## falls through to *any one-argument builtin of that name called on the
## receiver*. That last step is the whole of `"abc".length`, `myList.count` and
## `x.ilk`: Director has no separate property table for them, the dot form is the
## call form with the receiver moved in front.
##
## Both call sites used to end in `get_member_prop(value, "", prop)` — the
## receiver read as a cast member — so every one of these answered 0:
##
##     [1, 2, 3].count      0   (3)
##     [#talk: 3].talk      0   (3)
##     "hello".length       0   (5)
##     point(3, 4).locH     0   (3)
##     rect(1,2,3,4).width  0   (2)
##
## Magic Hat is built on the first two. `MenuExist` opens
## `if gAllMenus.count = 0`, `DisableAllMenus`/`HideAllMenus`/`RemoveAllMenus`
## are each `repeat with i = 1 to gAllMenus.count`, and a count of 0 makes every
## one of them a no-op that returns cleanly.
##
## **The property list is checked before the builtin, which is where this
## diverges from ScummVM**, and deliberately. ScummVM answers a PARRAY read from
## the pairs alone and never reaches the builtin fallback, so `gAllMenus.count`
## would be VOID there. Director's `count` is documented as a property of *any*
## list, and the corpus depends on it: 6 handlers in `objects.cst` loop on the
## count of a property list and none of those lists carries a `#count` pair. The
## order chosen — pairs first, builtin second — agrees with ScummVM wherever a
## pair of that name exists and with Director where one does not.
##
## The final fall-through is still `get_member_prop`, unchanged, because a bare
## member reference held in a variable evaluates to a member *number* or *name*
## and `myMember.name` has to keep reaching the cast.
func _value_prop(owner: Variant, prop: String) -> Variant:
	# The read side of the sprite-reference arm in `_assign`.
	# `me.ItemSprite().locH > 0` guards the write, so a reference that
	# reads as a member property answers nothing and the guard sends the
	# handler down the wrong branch even once the write is fixed.
	if LingoSpriteRef.is_ref(owner):
		return _host_call("get_sprite_prop", [
			(owner as LingoSpriteRef).channel, prop])
	if LingoObject.is_object(owner):
		return _object_prop(owner, prop)
	var key := prop.to_lower()
	match typeof(owner):
		TYPE_DICTIONARY:
			var pairs: Dictionary = owner
			# Property lists are keyed by the string spelling in this port, and
			# `#talk` and `"talk"` are the same key -- `_eval`'s `proplist` arm
			# writes `to_str` of the key. Case-insensitively, because Lingo is.
			for pair_key in pairs:
				if str(pair_key).to_lower() == key:
					return pairs[pair_key]
		TYPE_VECTOR2:
			# **Director's point and rect are lists** -- `LingoValue` says so at
			# `to_list`, and `getAt(r, 3)` is a rect's right edge -- so the named
			# accessors are *indices into the same list*, not a second set of
			# readers. Going through `getAt` is what keeps `p.locH` and
			# `getAt(p, 1)` the same value and the same **type**:
			# `LingoBuiltins._at` hands a whole component back as an int so that
			# `p.locH / 2` stays on Director's integer-division path, and a
			# reader written here would have answered `Vector2`'s float.
			var point_slot := int(POINT_SLOTS.get(key, 0))
			if point_slot > 0:
				return _list_at(owner, point_slot)
		TYPE_RECT2:
			var rect_slot := int(RECT_SLOTS.get(key, 0))
			if rect_slot > 0:
				return _list_at(owner, rect_slot)
			# `width` and `height` are not stored; Director derives them from the
			# edges and ScummVM `getObjectProp` computes exactly this difference
			# (`lingo-the.cpp:2534-2537`). Subtracting through `LingoValue` keeps
			# them on the same numeric rules as every other Lingo arithmetic.
			if key == "width":
				return LingoValue.sub(_list_at(owner, 3), _list_at(owner, 1))
			if key == "height":
				return LingoValue.sub(_list_at(owner, 4), _list_at(owner, 2))
	if VALUE_PROPS.has(key):
		var handled: Array = []
		var value: Variant = Builtins.call_builtin(prop, [owner], handled)
		if not handled.is_empty():
			return value
	if typeof(owner) == TYPE_DICTIONARY:
		# **A property list with no such pair answers VOID, and that is an
		# answer rather than a miss.** `MenuExist` is
		# `not voidp(gAllMenus.getaProp(MenuName))` — the script asks the
		# question by reading a key that may not be there — so this must not be
		# reported and must not fall through to the cast, where a Dictionary
		# stands for no member and `get_member_prop` would answer 0. ScummVM
		# pushes an empty `Datum` on the same path and warns about nothing
		# (`getObjectProp`'s PARRAY arm, `lingo-the.cpp:2506-2514`).
		return null
	if owner == null:
		# VOID has no properties, and answering 0 for one is the shape §19 calls
		# the worst state there is: the script branches on a value nothing
		# produced. Reported rather than raised, because Director keeps running.
		_fail("property %s read on VOID" % prop)
		return null
	return _host_call("get_member_prop", [owner, "", prop])


## One element of a point or a rect, read the way every other caller reads one.
## Is this subscript a *position*, or a property name?
##
## **`getAt` and `setAt` type-check their index to INT or FLOAT** —
## `lingo-builtins.cpp:1135` and `:1487`, both `TYPECHECK2(indexD, INT, FLOAT)` —
## so a symbol subscript can never have meant either of them, and the only
## reading left for `myPropList[#key]` is `getaProp`/`setaProp`. Those two handle
## a linear list by delegating straight back to `getAt`/`setAt` (`:1101-1104`,
## `:1450-1455`), which is why the split can be made on the subscript alone.
##
## **Positional stays positional**, which is the half that had to be preserved:
## `myPropList[2]` is the second property's *value* in this port on purpose, and
## Magic Hat's `DisableAllMenus`/`HideAllMenus`/`EnableAllMenus` are each a
## `repeat with i = 1 to gAllMenus.count` over exactly that. See the `index` read
## arm for what that cost when it was missing.
##
## What the missing half cost, measured in `itamar-park`: `setFlag`/`getFlag`
## (`utils.cst`, `MovieScript 4 - sprites`) are the whole arcade's state and are
## `gArcadeFlags[myFlag] = myValue` / `return gArcadeFlags[myFlag]` with `myFlag`
## a symbol. Every write coerced `#windowOpen` to slot 0 and was dropped, so
## after 500 frames of play `gArcadeFlags` was still `[:]` and every one of
## `#windowOpen`, `#NewGameOrWorld`, `#NewGameExp`, `#FlagOnStage`, `#LifeSpan`
## and `#BallClicked` read VOID. The world's explanation frame is gated on
## `getFlag(#NewGameOrWorld) = 1`, so it never held and the narration was cut off
## on its first tick.
##
## A numeric *string* is a key, not a position: Director's type check is on the
## datum's type, and `[#a: 1]["1"]` has no position to name.
static func _is_position(subscript: Variant) -> bool:
	return typeof(subscript) == TYPE_INT or typeof(subscript) == TYPE_FLOAT \
		or typeof(subscript) == TYPE_BOOL


func _list_at(container: Variant, index: int) -> Variant:
	var handled: Array = []
	return Builtins.call_builtin("getAt", [container, index], handled)


func _read_var(name: String, frame: Dictionary) -> Variant:
	var key := name.to_lower()
	# Director's spelled-out constants.
	match key:
		"empty": return ""
		"true": return 1
		"false": return 0
		"return", "cr": return "\n"
		"quote": return "\""
		"tab": return "\t"
		"space": return " "
		"void": return null
	var locals: Dictionary = frame.get("locals", {})
	if locals.has(key):
		return locals[key]
	# §7.1's instance variables. A handler running *on an object* sees that
	# object's `property` declarations, and its ancestors', by their bare names --
	# which is the whole of Lingo's object scoping. Checked after the locals so a
	# declared parameter still wins, and before the globals so a parent script's
	# `property gravity` is not silently the movie's global of that name.
	#
	# `me` itself is normally a *parameter* (`on mouseUp me`), so it resolves
	# above; the arm here is for a handler that uses the word without declaring
	# it, which Director's compiler rejects and a decompiled script can still
	# contain.
	var me: Variant = frame.get("me", null)
	if me != null:
		if key == "me":
			return me
		if bool((me as Object).call("has_slot", key)):
			return (me as Object).call("get_slot", key)
	# Globals the host owns: the walk state lives in PuppetController, so
	# `egozh`, `whatodo` and friends must alias it rather than shadow it.
	if host != null and host.has_method("owns_global") and host.owns_global(key):
		return host.get_global(key)
	if globals.has(key):
		var value: Variant = globals[key]
		if value == null:
			# Declared with `global x` and never assigned. VOID is the right
			# answer, but which name and where is still worth knowing, and it is
			# the script's own unset variable rather than a binding the port owes.
			report(LingoDiagnostics.UNSET_VARIABLE, key)
		return value
	# An unknown bare identifier is a parameterless handler call in Lingo.
	if host != null and host.has_method("is_native_handler") and host.is_native_handler(key):
		var native: Variant = _host_call("call_builtin", [key, []])
		return native if native != null else 0
	if has_handler(key) or _script_has_handler(frame.get("script", {}), key):
		return call_handler(key, [], frame.get("script", {}))
	# A bare word is how Lingo spells a no-argument call, so the interpreter's own
	# builtins have to be offered here as well as in `_call` -- `abort` is written
	# exactly this way and never reaches `_call` at all.
	var own: Array = []
	var mine: Variant = _own_builtin(key, [], frame, own)
	if not own.is_empty():
		return mine
	var handled: Variant = _host_call("call_builtin", [key, []])
	if handled != null:
		return handled
	# A bare word is how Lingo spells a no-argument builtin, so the VOID-answering
	# case reaches here too -- `x = getPref` is not legal, but `clearGlobals` and
	# `version` are written exactly this way and one of the host's arms answers
	# nothing on purpose.
	if _host_answered_builtin():
		return null
	# Unknown identifiers are VOID, which concatenates as "" and counts as 0.
	report(
		LingoDiagnostics.UNSET_VARIABLE if _handler_assigns(key) else LingoDiagnostics.UNBOUND_NAME,
		key)
	return null


func _handler_assigns(key: String) -> bool:
	## Whether the running handler assigns this name anywhere. If it does, the
	## read is an uninitialised local — the branch that would have set it was not
	## taken — and not a name the port failed to bind. Scanning the body is only
	## ever paid for by a handler that already has something to report, and the
	## answer is cached per handler.
	var cache_key := "%s|%s" % [_script_name, _handler_name]
	var names: Variant = _assigned_names.get(cache_key, null)
	if names == null:
		names = {}
		for param in _current_handler.get("params", []):
			(names as Dictionary)[str(param).to_lower()] = true
		_collect_assigned(_current_handler.get("body", []), names)
		_assigned_names[cache_key] = names
	return (names as Dictionary).has(key)


func _collect_assigned(stmts: Variant, out: Dictionary) -> void:
	if typeof(stmts) != TYPE_ARRAY:
		return
	for stmt in stmts:
		if typeof(stmt) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = stmt
		match str(node.get("node", "")):
			"assign", "put":
				var base := _assigned_base(node.get("target", {}))
				if base != "":
					out[base] = true
			"if":
				_collect_assigned(node.get("then", []), out)
				_collect_assigned(node.get("else", []), out)
			"repeat_while", "repeat_forever", "tell":
				_collect_assigned(node.get("body", []), out)
			"repeat_with", "repeat_in":
				out[str(node.get("var", "")).to_lower()] = true
				_collect_assigned(node.get("body", []), out)
			"case":
				for branch in node.get("branches", []):
					_collect_assigned((branch as Dictionary).get("body", []), out)
				_collect_assigned(node.get("default", []), out)


## The variable an assignment target ultimately writes into, lowercased, or "".
##
## **`put x into line N of myText` assigns `myText`**, and reading the target's
## own node type answers `chunk` rather than `var`, so a handler that builds a
## value up chunk by chunk looked to `_handler_assigns` like a handler that never
## assigned the name at all. What that costs is a *misfiled diagnostic*, which is
## the kind of fault this project treats as expensive: `getDataLines`
## (`itamar-park`, `MovieScript 1 - Param Handlers`) accumulates the parsed
## arcade.ini into `myNewText` entirely through `put … into line N of myNewText`,
## so the first read of the name was reported under `builtins unbound` — a line
## that means "the port owes a binding" and sent this session looking for a
## builtin called `mynewtext`. It is the script's own uninitialised local, which
## is what `UNSET_VARIABLE` says.
##
## The same line reports `movetofront`, which **is** a binding this port owes
## (§7.4), and mixing the two kinds is precisely what makes the honest entry hard
## to see. One name in the wrong bucket costs more than three in the right one.
##
## Recursive rather than one level deep, because these wrappers nest:
## `put c into char 3 of line 2 of myText` is a chunk of a chunk, and
## `item 1 of myList[2]` is a chunk of an index.
static func _assigned_base(target: Variant) -> String:
	if typeof(target) != TYPE_DICTIONARY:
		return ""
	var node: Dictionary = target
	match str(node.get("node", "")):
		"var":
			return str(node.get("name", "")).to_lower()
		"chunk":
			return _assigned_base(node.get("source", {}))
		"index", "dot", "prop_of":
			return _assigned_base(node.get("target", {}))
	return ""


func _script_has_handler(script: Variant, key: String) -> bool:
	if typeof(script) != TYPE_DICTIONARY:
		return false
	for handler in (script as Dictionary).get("handlers", []):
		if str((handler as Dictionary).get("name", "")).to_lower() == key:
			return true
	return false


func _call(expr: Dictionary, frame: Dictionary) -> Variant:
	var callee: Dictionary = expr.get("callee", {})
	var name := ""
	if str(callee.get("node", "")) == "var":
		name = str(callee.get("name", "")).to_lower()
	elif str(callee.get("node", "")) == "dot":
		# Two statements share this shape and only the receiver tells them apart.
		# `member(x).name` is a property read with an empty argument list, which
		# is what this arm has always answered. `myObject.mSetUp(3)` is a
		# **message** (§7.1): D5's dot notation for `call(#mSetUp, myObject, 3)`,
		# and reading it as a property would answer VOID and run nothing.
		#
		# The receiver is evaluated here only when the target is *not* one of the
		# two designators `_eval`'s own `dot` arm resolves without evaluating
		# (`sprite N`, `member M`). Evaluating those a second time would double
		# every `member(x).name` in the corpus -- 1,453 sites -- and, worse, would
		# run any side effect in the subscript twice.
		var target_node := str((callee as Dictionary).get("target", {}).get("node", ""))
		var receiver: Variant = null
		if target_node != "sprite_ref" and target_node != "member_ref":
			receiver = _eval((callee as Dictionary).get("target", {}), frame)
		if LingoObject.is_object(receiver) or LingoXtra.is_native(receiver):
			var dot_args: Array = []
			for arg in expr.get("args", []):
				dot_args.append(_eval(arg, frame))
			var message := str((callee as Dictionary).get("prop", ""))
			# `myFile.openFile(path, 1)` -- the dot spelling of the D3 method call
			# handled below. A native object gets no `me` in front of the
			# arguments: the receiver *is* the object, and FileIO's own methods
			# take the instance only because the flat spelling puts it there.
			if LingoXtra.is_native(receiver):
				var out: Array = (receiver as Object).call(
					"lingo_perform", message, dot_args)
				if not out.is_empty():
					return out[0]
				report(LingoDiagnostics.BUILTIN, "%s of %s" % [message, str(receiver)])
				return null
			if not (receiver as Object).call("resolve", message).is_empty():
				return _broadcast(receiver, message, dot_args, false)
			return _object_prop(receiver, message)
		if target_node != "sprite_ref" and target_node != "member_ref":
			# **`myList.setaProp(#a, 1)` — D5's dot spelling of a list command**,
			# which is exactly `setaProp(myList, #a, 1)` with the receiver moved
			# in front of the arguments (§1.3, §5). Every list and property-list
			# command has this second spelling and the corpus mixes the two
			# freely; without this arm the dot form fell through to the property
			# read below, which answered VOID and **ran nothing** — a mutation
			# that accepts and drops. `itamar-magichat` sat on frame 0 because of
			# it: `SetGlobalInfo` is one line, `gGlobalInfo.setaProp(Prop, data)`,
			# so the movie's whole configuration list stayed empty and
			# `GlobalInfo(#startFrame)` answered VOID.
			#
			# Narrowed to list receivers. Everything else that reaches here is a
			# member reference held in a variable, a window handle or a host
			# value, and those have properties rather than commands; a builtin
			# like `count` answers for any type and would swallow the read.
			# `LingoBuiltins` declines by leaving `handled` empty, so a name it
			# does not own still reaches the property read.
			var dot_name := str((callee as Dictionary).get("prop", ""))
			# Evaluated once and shared by the two tables below. Two loops would
			# run any side effect in an argument twice for every name the first
			# table declines, which is most of them.
			var on_receiver: Array = [receiver]
			for arg in expr.get("args", []):
				on_receiver.append(_eval(arg, frame))
			if typeof(receiver) == TYPE_ARRAY or typeof(receiver) == TYPE_DICTIONARY:
				var list_handled: Array = []
				var list_value: Variant = Builtins.call_builtin(
					dot_name, on_receiver, list_handled)
				if not list_handled.is_empty():
					return list_value
			# **`script("X").new(args)` — the dot spelling of `new(script "X",
			# args)`**, and the same move as the arm above: the receiver goes in
			# front of the arguments. Offered for every receiver rather than for
			# lists alone, because `_own_builtin` owns nine names — `do`, `abort`,
			# `param`, `script`, `new`, `call`, `send`, `callAncestor`,
			# `sendAncestor` — and not one of them is a cast-member property this
			# port binds, so there is no property read for it to swallow. The
			# member and sprite designators never reach here at all; they return
			# above.
			#
			# `script("X")` answers a **member reference**, not an object (§7.1),
			# so `.new` on it landed in the property read below and came back 0.
			# Magic Hat's `CreateMenu` is `MenuObj = script(MenuScript).new(
			# MenuName)` followed by `gAllMenus.addProp(MenuName, MenuObj)`, so all
			# seven of its menus were stored as the integer 0 and every later
			# `MenuObj.hide()` / `.Enable()` / `.Disable()` was a message to a
			# number. The flat spelling `new(script "X")` always worked, which is
			# why the five older titles never showed it: they spell it that way.
			var own_handled: Array = []
			var own_value: Variant = _own_builtin(
				dot_name.to_lower(), on_receiver, frame, own_handled)
			if not own_handled.is_empty():
				return own_value
			if receiver == null:
				# **A message sent to VOID, dropped in silence.** `x.hide()`
				# where `x` is VOID has no receiver, no handler and no property,
				# and this arm used to hand it to `get_member_prop` -- which
				# answers 0 for a member that is not there, and returns cleanly.
				# So the statement ran, did nothing, reported nothing, and the
				# handler carried on.
				#
				# That is the state §19 calls the worst one, and it is what made
				# the chunk bug above take a day: Magic Hat's `HideMenu` is
				# `MenuObj = GetMenu(MenuName)` then `MenuObj.hide()`, so an empty
				# `gAllMenus` turned into two clean no-ops per call and the only
				# evidence anywhere was a dialog still on the screen. The
				# arguments are not even evaluated, so a side effect in one is
				# lost with the call.
				#
				# Through `_fail` rather than `report`, because this is a
				# statement that did not happen rather than a name that did not
				# bind -- the same path `_assign`'s fall-through uses, and it
				# prints.
				_fail("message %s sent to VOID" % dot_name)
				return null
			# Evaluated above; read the property off the value rather than
			# re-entering `_eval`, which would evaluate the target a second time.
			return _value_prop(receiver, dot_name)
		return _eval(callee, frame)
	var args: Array = []
	for arg in expr.get("args", []):
		args.append(_eval(arg, frame))

	## There is no second builtin table here. This file used to answer `value`,
	## `string`, `integer`, `float`, `abs`, `length`, `chars`, `offset`, `count`
	## and `getAt` from an inline `match` placed *above* the dispatch below, so
	## `lingo/lingo_builtins.gd` — the spec-driven module `tools/lingo_builtins_check.gd`
	## checks — could never be reached for those ten names and the two disagreed
	## in silence. The module is now the only answer. What the inline copies got
	## wrong, name by name, because "we deleted the duplicate" is not a reason:
	##
	##   getAt   answered 0 past either end where the module answers VOID. §8.6 is
	##           explicit that the two are not interchangeable, and 0 is the one
	##           that cannot be told from a stored 0 — `if getAt(l, i) then` reads
	##           the same either way. It also knew only Arrays, so `getAt` on a
	##           property list, a point or a rect answered 0 rather than the
	##           element (§1.3, §1.8).
	##   abs     coerced to float always, so `abs(-7)/2` was 3.5 where Director
	##           answers 3: §2.1's integer-division rule keys off the operand
	##           types, and a builtin that widens its result moves every
	##           expression downstream onto the other arithmetic.
	##   value   coerced with `to_num`, so a string that is not a number answered
	##           0. §1.2 says `value` *parses* — a number, a list or a property
	##           list — and anything else is VOID (§8.6 again). The coercing
	##           version also could not read `value("[1, 2]")` at all.
	##   integer truncated. §1.1 says it rounds; `integer(3.7)` is 4.
	##   offset  ignored the documented third argument (start position) and
	##           answered 1 for an empty needle, so `if offset("", s) then` fired.
	##   count   knew only Arrays, so a property list counted 0 (§1.3).
	##   chars, length, string, float agreed with the module and were duplicated
	##           for nothing — two copies of one rule is how the other six drifted.
	##
	## Deleting them also moves the ten names *below* user-handler resolution,
	## which is where Director puts them: a script may shadow a builtin (§14, and
	## the comment on the dispatch below). No handler in this corpus is named any
	## of the ten, so the corpus behaves the same; the ordering is now a decision
	## rather than an artefact of where the `match` happened to sit.

	# Handlers the host implements natively win even over a user handler: the port
	# reimplements the walk state machine in PuppetController, so running the
	# original `walkonby` would fight it.
	if host != null and host.has_method("is_native_handler") and host.is_native_handler(name):
		var native: Variant = _host_call("call_builtin", [name, args])
		return native if native != null else 0
	# **`new` is the one name a script may not shadow**, and it has to be resolved
	# here rather than with the rest of `_own_builtin` below.
	#
	# In Director `new` is a language construct: the compiler emits the
	# instantiation directly, so the word never goes through handler lookup. Here
	# it would, and the collision is not hypothetical -- it is *universal*. Every
	# parent script declares `on new me`, and the standard way to build an
	# ancestor is `ancestor = new(script "base")` written **inside that very
	# handler**. Resolved as a user handler that is unbounded recursion, which
	# this port answers with "handler recursion too deep" after 64 frames and a
	# VOID object: measured exactly that way before this guard existed.
	if name == "new":
		var built: Array = []
		var made: Variant = _own_builtin(name, args, frame, built)
		if not built.is_empty():
			return made
	# Otherwise a user handler wins over a host builtin, matching Director.
	var script: Dictionary = frame.get("script", {})
	if _script_has_handler(script, name) or has_handler(name):
		return call_handler(name, args, script)
	# `param(n)` -- the nth argument the *running* handler was called with, which
	# neither of the two dispatch targets below can answer. `lingo_builtins.gd` is
	# engine-free by definition and this is a call frame; the host is one frame
	# further out and would answer for the wrong handler. Placed after the user
	# handler for the same reason everything else is: a script may shadow it.
	#
	# The reference reads the *named* parameter first and falls back to the
	# unnamed list, so `param(1)` inside a handler that has assigned its first
	# argument answers the assigned value rather than what was passed. That
	# distinction is kept: the locals hold the named ones.
	var own: Array = []
	var mine: Variant = _own_builtin(name, args, frame, own)
	if not own.is_empty():
		return mine
	# The engine-free builtins — math, strings, lists, geometry, predicates.
	# Offered after a user handler, because Director lets a script shadow a
	# builtin, and before the host, because the host is where a title's own
	# bindings live and nothing engine-free belongs there. `handled` is what
	# distinguishes "answered VOID" from "not mine".
	# **A method call on a native object, written the D3 way** (§7.3):
	# `openFile(myFile, path, 1)`, where the object is the *first argument*. That
	# is the spelling both FileIO-dependent titles use and the only one their
	# authors had; `myFile.openFile(path, 1)` is the same statement and is handled
	# at the `dot` callee above.
	#
	# Placed after the user handlers -- a movie may wrap `openFile` in one of its
	# own, and `itamar-magichat` does exactly that in `loadfiletofield` -- and
	# before the engine-free builtins, so a name like `delete` or `error` reaches
	# the object that was handed it. The guard is the first argument being a
	# native object that *answers* the name, which is narrow enough that a
	# collision with a real builtin cannot happen: nothing else in the language
	# takes an Xtra instance as its first argument.
	# **A name the object does not answer falls through rather than reporting**,
	# and that is not politeness -- it is the difference between working and not.
	# `objectP(f)`, `ilk(f)` and `voidP(f)` all take an object as their first
	# argument and are none of the object's business; a version that claimed
	# every call with an object in front of it answered VOID for all three, which
	# is exactly the "bound and does nothing" shape §19 exists to catch. So the
	# object gets first refusal and the ordinary dispatch continues behind it.
	if not args.is_empty() and LingoXtra.is_native(args[0]):
		var native_out: Array = (args[0] as Object).call(
			"lingo_perform", name, args.slice(1))
		if not native_out.is_empty():
			return native_out[0]
	var handled: Array = []
	var pure: Variant = Builtins.call_builtin(name, args, handled)
	if not handled.is_empty():
		return pure
	var result: Variant = _host_call("call_builtin", [name, args])
	if result == null and name != "":
		# **A bound builtin whose answer is VOID.** `call_builtin` says "no such
		# name" by answering null, which is the contract in this file's header,
		# and that spelling cannot also say "bound, and the answer is nothing".
		# Three builtins need the second and each was broken by the first:
		# `getPref` answers VOID for a preference never written -- how every
		# "first run?" test in Lingo is spelled -- and `externalParamName` and
		# `externalParamValue` answer VOID past the end of the list, which is how
		# a movie knows the loop is over. All three came back as 0 *and* reported
		# themselves missing.
		if _host_answered_builtin():
			return null
		report(LingoDiagnostics.BUILTIN, name)
	return result if result != null else 0


## Whether the host reached an arm for the builtin it was just asked for.
##
## Optional, like every other method on the host contract: a host without it is
## taken at its word, which is the behaviour every caller had before this
## existed.
func _host_answered_builtin() -> bool:
	if host == null or not host.has_method("answered_builtin"):
		return false
	return bool(host.answered_builtin())


## Preloaded rather than reached by its `class_name`: a headless `--script` run
## resolves global classes out of the editor's script cache, so a class added
## since the last editor session fails with "not declared in the current scope"
## in a file nobody touched.
const Builtins := preload("res://lingo/lingo_builtins.gd")
## §7.1's script object. Preloaded for the reason `Builtins` is, and with more
## force: this class was added after the last editor session on any checkout that
## has not opened one since, so a `class_name` reference to it fails at compile
## time in a file nobody touched.
const LingoObject := preload("res://lingo/lingo_object.gd")
## §7.3's native-object protocol -- an Xtra, or an instance of one. Preloaded
## for the reason above; only `is_native` is reached from here, because the
## whole point of the protocol is that this file does not know what an Xtra is.
const LingoXtra := preload("res://lingo/lingo_xtra.gd")
## For `do`. Preloaded here rather than at the top for the same reason `Builtins`
## is: a headless `--script` run resolves global class names out of the editor's
## cache, which a fresh checkout has not built.
const DoCompiler := preload("res://lingo/compile/lingo_compiler.gd")


## A host that does not implement a method answers null, which is
## indistinguishable at the call site from a host that handled the call and had
## nothing to say. That silence hid all 66 `set the volume of sound N` writes in
## this corpus for as long as `lingo/lingo_host.gd` had no `set_sound_prop`
## (bugs.md 27): the parser was right, the interpreter routed correctly, and the
## value went nowhere with nothing recorded.
##
## Reported here rather than at each call site, and deliberately *not* for
## `call_builtin`: `_read_var` probes that for every bare identifier, so a
## blanket report there would refile every unset variable as a missing binding.
## `call_builtin`'s own miss is already reported by its caller, with the name.
func _host_call(method: String, args: Array) -> Variant:
	if host == null:
		return null
	if not host.has_method(method):
		if method != "call_builtin":
			report(LingoDiagnostics.UNBOUND_NAME, "host.%s" % method)
		return null
	var value: Variant = host.callv(method, args)
	# `play` and `go` are builtins, so this is the one place every freezing
	# statement passes through -- rather than the two arms of `_call` and the
	# three of `_read_var` that reach the host, which is five places for one rule
	# and four of them to forget.
	if method == "call_builtin":
		_take_suspend_request()
		# `the result` is the interpreter's and a few builtins write it instead of
		# returning -- `preLoad` and `preLoadCast` report the last item they
		# loaded through it (`lingo-builtins.cpp`). The host has no interpreter to
		# write to, so it leaves the value behind and this takes it, exactly the
		# way the suspend request above travels.
		if host.has_method("take_result_request"):
			var pending: Array = host.take_result_request()
			if not pending.is_empty():
				_result = pending[0]
	return value


func _fail(message: String) -> void:
	# Before the cap, deliberately: see `error_total`.
	error_total += 1
	if errors.size() < 50:
		# The location travels with the message. Without it a report reads
		# "cannot assign to member_ref" and names neither the script nor the
		# line, which is most of the work of finding it.
		errors.append("%s  (%s > %s line %d)" % [
			message, _script_name, _handler_name, _line])


## Say out loud what the last dispatch could not do.
##
## **`errors` existed for the life of this port and nothing on the player's path
## ever read it.** Two harnesses do; a run does not. That is how
## `put readFile(tmp) into member FieldName` -- a statement with no arm in
## `_assign` -- stayed invisible for as long as it did: it recorded itself
## faithfully, into an array cleared at the start of the next dispatch, a few
## milliseconds later.
##
## Drained here rather than at the three dispatch ends, for the same reason
## `_aborting` is cleared here: this is the one line all of them already share.
##
## Deduplicated for the run, because these fire from frame scripts. A statement
## that fails on an `exitFrame` fails again every tick, and an unconditional
## print would bury the movie's own output at 15 lines a second. Once is a
## diagnostic; sixty times a second is a reason to turn diagnostics off.
func _drain_errors() -> void:
	for message in errors:
		var text := str(message)
		if _reported.has(text):
			continue
		_reported[text] = true
		print("lingo: %s" % text)


## The distinct faults raised since this interpreter was built, first-seen order.
##
## `_reported` is the dedup set `_drain_errors` prints against and it deliberately
## outlives `reset_steps`; this is the same set as a value, so a harness or a
## report can ask what faulted without re-reading stdout. Insertion-ordered
## because GDScript's `Dictionary` is, and first-seen order is the order a reader
## wants: the first fault in a room is usually the cause of the rest.
func session_faults() -> PackedStringArray:
	var out := PackedStringArray()
	for message in _reported.keys():
		out.append(str(message))
	return out


var _reported: Dictionary = {}
