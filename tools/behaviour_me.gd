extends SceneTree
## Is a behaviour **one object** for every message it receives, or one object per
## door it is reached through?
##
##   godot --headless --audio-driver Dummy --path . --script tools/behaviour_me.gd -- \
##     --root res://test-games/itamar-magichat --file magichat.dir
##
## `bugs.md` 93. `beginSprite`/`endSprite` and the click chain hand a behaviour a
## real instance; `Scripts.dispatch` (every frame event) and `sendSprite` used to
## call `call_handler` with the default channel 0, which `behaviour_instance`
## reads as "not a behaviour at all" -- so `on exitFrame me` in a
## behaviour-channel script bound `me` to VOID while `on beginSprite me` **in the
## same script** got an object, and a `property` written in one was invisible in
## the other. Nothing failed: a handler ran to completion and only a line that
## says `me` could tell.
##
## That is why this harness exists rather than a reading of the code. It does not
## ask the engine what channel it resolved; it asks the *movie* what `me` was, by
## writing `me` into a global from inside the handlers themselves and comparing
## the two objects with `is_same`. An assertion that compared channel numbers
## would have passed against the bug.
##
## **The scripts under test are the title's own, with statements prepended.**
## Synthesising a whole movie would test the synthesiser; taking a shipped
## behaviour and adding `gExitMe = me` to the front of the `exitFrame` it already
## declares tests the dispatcher that title runs on. Prepended rather than
## appended because a handler that ends in `go` suspends (§6.1) and anything
## after it never runs.
##
## Three cases, and only the third is one corpus's:
##
## 1. *The frame behaviour.* Director's "sprite 0" -- the score's behaviour
##    channel -- is an instance like any other, and `me.spriteNum` inside it is
##    **0**, because the reference answers `spriteNum` from
##    `_currentSpriteNum` (`lingo-object.cpp:719-721`) and the frame tier is
##    queued with channel 0 (`lingo-events.cpp:640`).
## 2. *`sendSprite`.* The caller names the recipient, so the message is delivered
##    on that sprite's own instance and `the currentSpriteNum` is its channel.
## 3. *Magic Hat's album*, named as such. `BehaviorScript 34 - album loop` on
##    frame 42 declares `enterFrame`, `exitFrame`, `mouseUp` and `endSprite` --
##    four of the five doors in one script -- and the screen is entered by a
##    click from the menu, so `beginSprite` genuinely runs and the identity
##    across the two is the real thing rather than a cache lookup.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const FrameLoop := preload("res://scenes/preview/frame_loop.gd")
const LingoObject := preload("res://lingo/lingo_object.gd")

## Magic Hat's own numbers, shared with `tools/sprite_lifetime.gd`.
const MAGICHAT_ALBUM_BUTTON := Vector2(448, 378)
const MAGICHAT_ALBUM_FRAME := 42

## The value written to the instance property in one handler and read in another.
## Any number would do; a memorable one makes a wrong read obvious in the log.
const MARK := 4242

## The name of the synthetic movie handler the fallback check installs. Not a
## name any Director title uses, so it can only ever be reached by this harness.
const FALLBACK := "behaviourmeprobe"


func _init() -> void:
	var h := Harness.new()
	var opts: Dictionary = Args.parse()
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	for _i in 90:
		await process_frame

	var movie := str(preview.call("movie_name")).to_lower()
	var interpreter = preview.get("_interpreter")
	print("movie: %s, frame %d, behaviour instances %d" % [
		movie, int(preview.get("_index")), _cache(interpreter).size()])

	await _frame_behaviour(h, preview, interpreter)
	await _send_sprite(h, preview, interpreter)
	if movie.contains("magichat"):
		await _magichat(h, preview, interpreter)
	else:
		print("note: the album case is Magic Hat's and this is %s" % movie)

	# The leak the fix could have introduced, stated as a number rather than as a
	# reassurance: a dispatcher that *creates* an instance for every channel it
	# messages would grow this cache by a channel per script per movie, for the
	# life of the movie, and nothing else in the port would notice.
	print("behaviour instances at exit: %d" % _cache(interpreter).size())
	quit(h.finish("every message to a behaviour arrives on the same instance"))


func _cache(interpreter) -> Dictionary:
	return interpreter.get("_behaviours") as Dictionary


## The behaviour-channel script covering `index`, or `{}`.
func _frame_script(preview, index: int) -> Dictionary:
	var spans: Dictionary = FrameLoop.sprite_behaviours_at(preview.get("_score"), index)
	if not spans.has(0):
		return {}
	var spec: Array = spans[0]
	return preview.call("_script_in_lib", int(spec[2]), int(spec[3]))


func _declares(script: Dictionary, name: String) -> bool:
	for handler in script.get("handlers", []):
		if str((handler as Dictionary).get("name", "")).to_lower() == name.to_lower():
			return true
	return false


## Compile `source` as a handler body and return its statements.
##
## The interpreter's own compiler, so the probe cannot drift from the language
## the movie is written in -- a hand-built AST would be a second dialect.
func _statements(interpreter, source: String) -> Array:
	var errors: Array = []
	var compiled: Dictionary = interpreter.compile_statements(source, "probe", errors)
	if compiled.is_empty():
		push_error("probe did not compile: %s" % str(errors))
		return []
	return (compiled.get("handler", {}) as Dictionary).get("body", [])


## Put `source` at the front of `script`'s `name` handler, or add the handler.
func _prepend(interpreter, script: Dictionary, name: String, source: String) -> bool:
	var body: Array = _statements(interpreter, source)
	if body.is_empty():
		return false
	for value in script.get("handlers", []):
		var handler: Dictionary = value
		if str(handler.get("name", "")).to_lower() != name.to_lower():
			continue
		handler["body"] = body + (handler.get("body", []) as Array)
		return true
	var made: Dictionary = {"name": name, "params": ["me"], "body": body}
	(script.get("handlers", []) as Array).append(made)
	return true


## Declare `pmark` on the script, so the instance built from it has the slot.
##
## Director's `property` statement is the only thing that creates an instance
## variable (`lingo_object.gd:set_slot`), so a probe that just assigned `pMark`
## would write a local and prove nothing.
func _declare_property(script: Dictionary, instance: Variant) -> void:
	var names: Array = script.get("properties", [])
	if not names.has("pmark"):
		names.append("pmark")
	script["properties"] = names
	if instance != null:
		instance.call("declare", "pmark")


func _object(interpreter, name: String) -> Variant:
	var value: Variant = (interpreter.globals as Dictionary).get(name, null)
	return value if LingoObject.is_object(value) else null


## A global as an integer, or `fallback` when it is not one.
##
## `int(null)` is a GDScript runtime error, and an unassigned Lingo global is
## VOID -- which is exactly the state this harness exists to detect, so reading
## one must report rather than abort the case (`tools/lib/harness.gd`).
func _num(interpreter, name: String, fallback := -1) -> int:
	var value: Variant = (interpreter.globals as Dictionary).get(name, null)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	if typeof(value) == TYPE_STRING and str(value).is_valid_int():
		return int(str(value))
	return fallback


func _shown(interpreter, name: String) -> String:
	var globals := interpreter.globals as Dictionary
	if not globals.has(name):
		return "<never declared>"
	var value: Variant = globals[name]
	return "VOID" if value == null else str(value)


# ---------------------------------------------------------------- case 1


## `exitFrame` in the behaviour channel's script gets the instance `beginSprite`
## made, and the property written on it is still there.
##
## Corpus-agnostic: it takes whatever frame the boot movie settles on. A movie
## whose settling frame carries no behaviour-channel script says so and skips,
## because a check that silently asserts nothing is worse than an absent one.
func _frame_behaviour(h: Harness, preview, interpreter) -> void:
	h.begin("the frame behaviour")
	var index := int(preview.get("_index"))
	var script: Dictionary = _frame_script(preview, index)
	if script.is_empty() or not _declares(script, "exitFrame"):
		print("note: frame %d carries no behaviour-channel script with an exitFrame" % index)
		h.complete("the frame behaviour")
		return
	var name := str(script.get("script", ""))
	var live: Variant = _cache(interpreter).get("0:%s" % name, null)
	if not h.check("the behaviour channel's span has an instance", live != null,
			"cache entry 0:%s is %s" % [name, "there" if live != null else "missing"]):
		h.complete("the frame behaviour")
		return
	# Written on the instance from outside, which is exactly what a `beginSprite`
	# handler's `pMark = ...` does from inside -- the same object, the same slot.
	_declare_property(script, live)
	live.call("set_slot", "pmark", MARK)
	_prepend(interpreter, script, "exitFrame",
		"global gexitme\nglobal gexitmark\nglobal gexitnum\n" +
		"gexitme = me\ngexitmark = pMark\ngexitnum = me.spriteNum")
	for _i in 60:
		await process_frame
	var got: Variant = _object(interpreter, "gexitme")
	h.check("exitFrame ran on an object", got != null,
		"me was %s" % _shown(interpreter, "gexitme"))
	h.check("and it is the instance the span holds", got != null and is_same(got, live),
		"%s vs %s" % [str(got), str(live)])
	h.check("a property written on that instance is readable from exitFrame",
		_num(interpreter, "gexitmark") == MARK,
		"pMark read as %s" % _shown(interpreter, "gexitmark"))
	# `lingo-object.cpp:719-721` answers `spriteNum` from `_currentSpriteNum`, and
	# `lingo-events.cpp:640` queues the frame tier with channel 0. A frame
	# behaviour is not on a sprite, and 0 is the number that says so.
	# `got != null` is part of the assertion and not a guard on it: with `me`
	# VOID, `me.spriteNum` reads 0 as well, so the number alone passes against the
	# bug this harness exists for.
	h.check("me.spriteNum in a frame behaviour is 0",
		got != null and _num(interpreter, "gexitnum") == 0,
		"spriteNum read as %s on %s" % [_shown(interpreter, "gexitnum"), str(got)])
	await _movie_fallback(h, preview, interpreter, script)
	h.complete("the frame behaviour")


## The other direction, and the one a fix for `bugs.md` 93 can break silently:
## a **movie** handler reached through the fallback belongs to no sprite.
##
## `Lingo::processEvent` only pushes an instance for `kScoreScript`
## (`reference/scummvm/lingo-events.cpp:804-813`), and `resolveScriptEvent`'s
## `kMovieHandler` arm never sets one (`:406-425`) -- a movie script is not a
## behaviour and `me.spriteNum` inside it would name a channel it has nothing to
## do with. The trap is that `me` reaches a handler twice, on the frame *and* as
## the first argument, so a fix that resolves the instance one tier too early
## leaks it into the movie tier through the argument list alone and the frame
## half still looks right.
##
## Driven through the same `_dispatch` the frame events use, with a handler the
## behaviour script does not declare, so the message really does fall through.
func _movie_fallback(h: Harness, preview, interpreter, script: Dictionary) -> void:
	var movie_handlers: Dictionary = interpreter.get("_movie_handlers") as Dictionary
	if movie_handlers.is_empty():
		print("note: this movie has no movie handlers to fall through to")
		return
	var borrowed: Dictionary = movie_handlers[movie_handlers.keys()[0]]
	var body: Array = _statements(interpreter, "global gmovieme\ngmovieme = me")
	if body.is_empty():
		return
	# `params` is the whole point: a handler that names `me` is what turns a
	# leaked first argument into a binding, which is what this has to detect.
	movie_handlers[FALLBACK] = {
		"cast": borrowed.get("cast", ""), "script": borrowed.get("script", ""),
		"handler": {"name": FALLBACK, "params": ["me"], "body": body},
	}
	preview.call("_dispatch", FALLBACK, script)
	await preview.get_tree().process_frame
	h.check("a movie handler reached through the fallback gets no me",
		_object(interpreter, "gmovieme") == null,
		"me was %s" % _shown(interpreter, "gmovieme"))


# ---------------------------------------------------------------- case 2


## `sendSprite(n, #probe)` reaches sprite `n`'s own instance.
##
## The channel is the caller's, not the playhead's, so this is the one message in
## the port whose recipient is named rather than resolved -- and it was calling
## `call_handler` with channel 0 like everything else.
func _send_sprite(h: Harness, preview, interpreter) -> void:
	h.begin("sendSprite")
	var target := 0
	var target_script: Dictionary = {}
	var index := int(preview.get("_index"))
	var spans: Dictionary = FrameLoop.sprite_behaviours_at(preview.get("_score"), index)
	var channels: Array = spans.keys()
	channels.sort()
	for channel in channels:
		if int(channel) <= 0:
			continue
		var script: Dictionary = preview.call("_sprite_script", int(channel), index)
		if script.is_empty():
			continue
		target = int(channel)
		target_script = script
		break
	if target == 0:
		print("note: frame %d carries no sprite behaviour to message" % index)
		h.complete("sendSprite")
		return
	var name := str(target_script.get("script", ""))
	var live: Variant = _cache(interpreter).get("%d:%s" % [target, name], null)
	_prepend(interpreter, target_script, "probeme",
		"global gsendme\nglobal gsendnum\ngsendme = me\ngsendnum = me.spriteNum")
	var before := _cache(interpreter).size()
	var run: Dictionary = interpreter.compile_statements(
		"sendSprite(%d, #probeme)" % target, "sendprobe", [])
	interpreter.run_compiled(run)
	for _i in 5:
		await process_frame
	var got: Variant = _object(interpreter, "gsendme")
	h.check("sendSprite ran the behaviour on an object", got != null,
		"me was %s" % _shown(interpreter, "gsendme"))
	h.check("me.spriteNum is the channel that was addressed",
		_num(interpreter, "gsendnum") == target,
		"spriteNum %s, sent to %d" % [_shown(interpreter, "gsendnum"), target])
	if live != null:
		h.check("and it is the instance the sprite already had",
			got != null and is_same(got, live), "%s vs %s" % [str(got), str(live)])
	# The other half of the same fix: a dispatcher that resolves a channel must
	# not *invent* an instance for one, or a `sendAllSprites` over 48 channels
	# leaves 48 objects behind per script for the life of the movie.
	h.check("messaging a sprite created no second instance",
		_cache(interpreter).size() == before,
		"cache went %d -> %d" % [before, _cache(interpreter).size()])
	h.complete("sendSprite")


# ---------------------------------------------------------------- case 3


## Magic Hat's album: `beginSprite` and `exitFrame` in one script, one object.
##
## The screen is entered by clicking the menu's album button, so the instance is
## made by the arrival rather than found in a cache somebody else filled --
## which is the only way to compare the object `beginSprite` saw against the
## object `exitFrame` saw.
func _magichat(h: Harness, preview, interpreter) -> void:
	h.begin("magichat: the album loop is one instance")
	var script: Dictionary = _frame_script(preview, MAGICHAT_ALBUM_FRAME)
	if not h.check("frame %d has a behaviour-channel script" % MAGICHAT_ALBUM_FRAME,
			not script.is_empty(), str(script.get("script", "none resolved"))):
		h.complete("magichat: the album loop is one instance")
		return
	h.check("it is the album loop", str(script.get("script", "")).contains("album loop"),
		str(script.get("script", "")))
	h.check("which declares exitFrame and not beginSprite",
		_declares(script, "exitFrame") and not _declares(script, "beginSprite"),
		"handlers %s" % str(script.get("handlers", []).size()))
	_declare_property(script, null)
	# The idiom the entry is about, written into the title's own behaviour: a
	# property set on arrival and read on every tick after it.
	_prepend(interpreter, script, "beginSprite",
		"global gbeginme\nglobal gbeginnum\ngbeginme = me\ngbeginnum = me.spriteNum\n" +
		"pMark = %d" % MARK)
	_prepend(interpreter, script, "exitFrame",
		"global galbumme\nglobal galbummark\ngalbumme = me\ngalbummark = pMark")
	preview.call("route_click", MAGICHAT_ALBUM_BUTTON)
	for _i in 150:
		await process_frame
	if not h.check("the album button opens the album",
			int(preview.get("_index")) == MAGICHAT_ALBUM_FRAME,
			"frame %d" % int(preview.get("_index"))):
		h.complete("magichat: the album loop is one instance")
		return
	var began: Variant = _object(interpreter, "gbeginme")
	var exited: Variant = _object(interpreter, "galbumme")
	h.check("beginSprite ran on an object", began != null,
		"me was %s" % _shown(interpreter, "gbeginme"))
	h.check("exitFrame ran on an object", exited != null,
		"me was %s" % _shown(interpreter, "galbumme"))
	h.check("both handlers of the one script got the one object",
		began != null and exited != null and is_same(began, exited),
		"beginSprite %s, exitFrame %s" % [str(began), str(exited)])
	h.check("the property beginSprite wrote is what exitFrame reads",
		_num(interpreter, "galbummark") == MARK,
		"pMark read as %s" % _shown(interpreter, "galbummark"))
	h.check("me.spriteNum in the behaviour channel is 0",
		began != null and _num(interpreter, "gbeginnum") == 0,
		"spriteNum %s on %s" % [_shown(interpreter, "gbeginnum"), str(began)])
	h.complete("magichat: the album loop is one instance")
