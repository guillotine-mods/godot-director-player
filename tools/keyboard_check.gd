extends SceneTree
## Does pressing a key reach the movie's own key handler?
##
##   godot --headless --script tools/keyboard_check.gd -- --file strtgame.dir
##
## Director routes every keypress through `the keyDownScript`, a movie-wide
## handler name the score sets. 46 scripts in this corpus set it, most of them to
## `fromnow`:
##
##   on fromnow
##     if the keyCode = "49" then
##       sound stop 1
##     else
##       nothing()
##     end if
##   end
##
## 49 is the Macintosh virtual key code for the space bar — Director reports Mac
## codes even on Windows — so pressing space stops sound channel 1, which cuts
## the line of speech that is playing. That is the skip a player reaches for
## first, and until now the preview swallowed space for its own pause binding and
## had no keyboard path at all.
##
## This drives the real preview node rather than a restatement of it: it boots
## the scene, runs the score far enough for the movie to install its key script,
## then hands it a synthetic key event and asks what happened.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Keys := preload("res://director/director_keys.gd")


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _init() -> void:
	var h := Harness.new()

	h.begin("the Mac key codes the corpus tests")
	h.check("space is 49", Keys.code_for(_key(KEY_SPACE)) == 49,
		str(Keys.code_for(_key(KEY_SPACE))))
	h.check("the arrows are 123 to 126", (
		Keys.code_for(_key(KEY_LEFT)) == 123
		and Keys.code_for(_key(KEY_RIGHT)) == 124
		and Keys.code_for(_key(KEY_DOWN)) == 125
		and Keys.code_for(_key(KEY_UP)) == 126
	))
	# 0 is the `A` key, so an unmapped key must not answer 0.
	h.check("an unmapped key is -1, not 0", Keys.code_for(_key(KEY_F35)) == -1,
		str(Keys.code_for(_key(KEY_F35))))
	h.complete("the Mac key codes the corpus tests")

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	if scene == null:
		print("no preview scene")
		quit(1)
		return
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	# Far enough in for the score to have run the frame that installs the key
	# script. Stepping the node rather than waiting on the clock keeps this
	# deterministic.
	var installed := ""
	for i in 400:
		preview.call("_advance")
		var host = preview.get("_host")
		if host != null and str(host.key_down_script) != "":
			installed = str(host.key_down_script)
			break

	h.begin("the movie installs a key handler and space reaches it")
	h.check("the score set the keyDownScript", installed != "",
		"'%s'" % installed)
	if installed == "":
		h.complete("the movie installs a key handler and space reaches it")
		quit(h.finish("keyboard routing in the preview"))
		return

	var host = preview.get("_host")
	# `the keyCode` must be live only during the dispatch, or a script reading it
	# outside a key event sees the last key pressed rather than nothing.
	h.check("keyCode is not live outside a key event", int(host.key_code) == -1,
		str(host.key_code))

	var claimed: bool = preview.call("_dispatch_key", _key(KEY_SPACE))
	h.check("space was claimed by the movie", claimed)
	h.check("keyCode was cleared afterwards", int(host.key_code) == -1,
		str(host.key_code))

	var sent: Dictionary = preview.get("_sent")
	var ran: Dictionary = preview.get("_ran")
	var tag := "keyDownScript:%s" % installed
	h.check("the handler was dispatched", sent.has(tag), JSON.stringify(sent))
	h.check("the handler actually ran", ran.has(tag), JSON.stringify(ran))
	h.complete("the movie installs a key handler and space reaches it")

	# `gomenu` is nothing but `when keyDown then go to "mainmenub4"`, so running
	# it *installs* a primary handler rather than navigating. The navigation
	# belongs to the next keypress, and that two-step is Director's, not an
	# approximation: a primary handler fires on the events that follow its
	# installation. Getting this wrong in the other direction is what the old
	# misparse did -- it navigated on every call to `gomenu`, unconditionally.
	var interp = preview.get("_interpreter")
	h.begin("`when keyDown then` installs a primary handler")
	h.check(
		"the first press installed one",
		(interp.primary_handlers as Dictionary).has("keydown"),
		JSON.stringify((interp.primary_handlers as Dictionary).keys())
	)
	preview.call("_dispatch_key", _key(KEY_SPACE))
	var ran2: Dictionary = preview.get("_ran")
	h.check("the second press fired it", ran2.has("when keyDown"), JSON.stringify(ran2))
	h.complete("`when keyDown then` installs a primary handler")

	print("")
	print("installed key script : %s" % installed)
	print("dispatched           : %s" % JSON.stringify(sent))
	quit(h.finish("keyboard routing in the preview"))
