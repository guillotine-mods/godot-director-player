extends SceneTree
## §8.2's event chain for the keyboard: does a primary handler **pass by
## default**, does `dontPassEvent` stop it, and does the *release* exist at all?
##
##   godot --headless --path . --script tools/key_chain.gd
##   godot --path . --script tools/key_chain.gd
##   godot --headless --path . --script tools/key_chain.gd -- --root rating --file ARCADE1.dir
##
## **Run it windowed for the last section.** Everything before it drives
## `_dispatch_key` / `_dispatch_key_up` directly, which proves the rules and
## nothing about the wiring; headless Godot has no keyboard focus. The windowed
## section feeds a real press *and release* through `Input.parse_input_event` --
## the player's own path, `_input` -> `preview/input_router.gd` -> the movie --
## which is the only thing that can show a key-up reaching a script at all.
## `tools/key_polling.gd` is the same shape for `the key` and `the keyCode`.
##
## **What was wrong, in two halves.**
##
## *The default was inverted.* `_dispatch_key` had the primary handler on the
## consuming side of an `if`/`else`, so while `the keyDownScript` was installed
## -- 59 sites in Piposh 2, 97 in Rating, 116 in Piposh 1 -- `keyDown` never
## reached a sprite, frame or movie script. Director is the other way round: the
## reference queues the primary element with `passByDefault` **true** and every
## other tier false (`lingo-events.cpp:486-490`), resets `_passEvent` to that
## default before each element runs (`:763`), and skips the next element only
## when the previous one found a script *and* left the flag false (`:756`).
## Piposh 2 declares no `on keyDown`, so nothing in it could see the difference;
## Piposh 1 declares 16 and calls `dontPassEvent` 44 times, Rating 9 times, and
## `dontPassEvent` is a statement about a chain that continues.
##
## *The release did not exist.* `director_preview.gd:_input` dropped every key
## event that was not `pressed`, and the host had no `key_up_script` at all --
## so `the keyUpScript`, set at **195 sites in Piposh Dream and 10 in Rating**,
## could not have worked whatever else was built. Rating's `ARCADE1.dir` member
## 20 sets it to `normalkeysx`, the handler that leaves a timed scene.
##
## **The subject is synthetic, deliberately.** The rules are the engine's, not a
## title's, and no movie in `games/` installs a primary handler that calls
## `dontPassEvent` where a harness could reach it. So a four-handler MovieScript
## is compiled with the port's own compiler and loaded into the live interpreter
## -- which is also what makes this run identically against any `--root`. The
## corpus's own sites are then *reported* rather than asserted, because what they
## prove is that the rule matters here, not that it is implemented.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Keys := preload("res://director/director_keys.gd")
const KeySites := preload("res://tools/lib/key_sites.gd")
const Paths := preload("res://director/director_paths.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")

## The controlled subject. Four handlers and three globals, named so that nothing
## in any title can collide with them:
##
##   * `kcpass` is a primary handler that says nothing, so it takes §8.2's
##     default -- pass.
##   * `kcstop` is the same handler plus `dontPassEvent`, which is the only thing
##     that may stop the chain.
##   * the counters say *which* ran, so "the primary handler fired" and "the
##     chain continued" are separate observations rather than one guess.
##
## Registered as a `MovieScript`, because `LingoInterpreter.load_bundle` makes
## only a movie script's handlers globally callable -- which is what
## `the keyDownScript` needs to resolve a bare name.
const SUBJECT := """
on kcpass
  global kcprimary
  set kcprimary to kcprimary + 1
end

on kcstop
  global kcprimary
  set kcprimary to kcprimary + 1
  dontPassEvent
end
"""


## One keystroke as the OS delivers it, `pressed` either way.
##
## The character matters as much as the code: `director_keys.gd:char_for` reads
## `unicode` first, so an event with only a keycode answers "" for every letter
## and a check about `the key` would pass by measuring nothing.
func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	if code >= 32 and code <= 126:
		event.unicode = String.chr(code).to_lower().unicode_at(0)
	return event


func _count(host, name: String) -> int:
	return int(host.get_global(name))


func _tally(preview: Node, which: String, handler: String) -> int:
	return int((preview.get(which) as Dictionary).get(handler, 0))


## Every handler name this root assigns to `the keyUpScript`, from the source
## lines `tools/lib/key_sites.gd` collected.
##
## Quoted names only: `set the keyUpScript to EMPTY` uninstalls, and three of
## Rating's ten sites are exactly that. Sorted and de-duplicated so the check
## names them in the same order every run.
func _key_up_names(sites: Dictionary) -> Array:
	var re := RegEx.new()
	re.compile("keyupscript\\s+to\\s+\"([^\"]+)\"")
	var out: Array = []
	for line in (sites["lines"] as Dictionary).get("the keyUpScript", []):
		var hit := re.search(str(line).to_lower())
		if hit != null and not out.has(hit.get_string(1)):
			out.append(hit.get_string(1))
	out.sort()
	return out


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var windowed := DisplayServer.get_name() != "headless"

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var wanted := Args.text(args, "file", "")
	if wanted != "":
		preview.call("lingo_go_movie", wanted, null)
		await process_frame

	var host = preview.get("_host")
	var interp = preview.get("_interpreter")
	if host == null or interp == null:
		print("no movie loaded; pass --file")
		quit(1)
		return
	var movie := str(preview.call("movie_name"))
	print("%s, %s" % [movie, "windowed" if windowed else "headless"])

	# ------------------------------------------------------------ the subject
	var compiler = Compiler.new()
	var ast: Dictionary = compiler.compile_source(SUBJECT, "MovieScript 9001 - keychain")
	h.begin("the controlled subject compiles and registers")
	h.check("it compiled", not ast.is_empty(), str(compiler.error))
	interp.load_bundle({"movie": "keychain", "cast": "keychain",
		"scripts": {"MovieScript 9001 - keychain": ast}})
	h.check("`kcpass` is callable by name, which is what a primary handler needs",
		interp.has_handler("kcpass"))
	h.check("and so is `kcstop`", interp.has_handler("kcstop"))
	h.complete("the controlled subject compiles and registers")

	# --------------------------------------------- §8.2, the press, pass by default
	# The claim is about the *second* tier being reached, so it is measured on
	# `_sent`, which `preview/scripts.gd:dispatch` writes the moment the chain
	# arrives there. A global set by a handler would only say the handler ran.
	h.begin("§8.2 a `keyDownScript` passes the event on by default")
	host.set_system_prop("keydownscript", "kcpass")
	h.check("`the keyDownScript` reads back what was set",
		str(host.get_system_prop("keydownscript")) == "kcpass",
		str(host.get_system_prop("keydownscript")))
	host.set_global("kcprimary", 0)
	var sent_before := _tally(preview, "_sent", "keyDown")
	preview.call("_dispatch_key", _key(KEY_H, true))
	h.check("the primary handler ran", _count(host, "kcprimary") == 1,
		str(_count(host, "kcprimary")))
	h.check("and the event carried on to the frame tier, which is the whole fix",
		_tally(preview, "_sent", "keyDown") == sent_before + 1,
		"keyDown dispatches: %d -> %d" % [
			sent_before, _tally(preview, "_sent", "keyDown")])
	h.complete("§8.2 a `keyDownScript` passes the event on by default")

	h.begin("§8.2 `dontPassEvent` in a primary handler stops the chain")
	host.set_system_prop("keydownscript", "kcstop")
	host.set_global("kcprimary", 0)
	sent_before = _tally(preview, "_sent", "keyDown")
	preview.call("_dispatch_key", _key(KEY_H, true))
	h.check("the primary handler ran", _count(host, "kcprimary") == 1,
		str(_count(host, "kcprimary")))
	h.check("and nothing below it was dispatched",
		_tally(preview, "_sent", "keyDown") == sent_before,
		"keyDown dispatches: %d -> %d" % [
			sent_before, _tally(preview, "_sent", "keyDown")])
	# The flag is per element, not per event: a `dontPassEvent` must not be still
	# set when the *next* keypress reaches its primary handler, or one refusal
	# would silence the chain for the rest of the movie.
	host.set_system_prop("keydownscript", "kcpass")
	sent_before = _tally(preview, "_sent", "keyDown")
	preview.call("_dispatch_key", _key(KEY_H, true))
	h.check("and the refusal did not outlive its own event",
		_tally(preview, "_sent", "keyDown") == sent_before + 1,
		"keyDown dispatches: %d -> %d" % [
			sent_before, _tally(preview, "_sent", "keyDown")])
	h.complete("§8.2 `dontPassEvent` in a primary handler stops the chain")

	# --------------------------------------------------------- §8.1, the release
	h.begin("`the keyUpScript` exists, and the release runs it")
	host.set_system_prop("keyupscript", "kcpass")
	h.check("`the keyUpScript` reads back what was set",
		str(host.get_system_prop("keyupscript")) == "kcpass",
		str(host.get_system_prop("keyupscript")))
	host.set_system_prop("keydownscript", "")
	host.set_global("kcprimary", 0)
	var up_before := _tally(preview, "_sent", "keyUp")
	preview.call("_dispatch_key", _key(KEY_H, true))
	# The press must not run it. A port that routed both halves to one handler
	# would look correct on every "did it fire" check and fire twice per key.
	h.check("the press does not run it", _count(host, "kcprimary") == 0,
		str(_count(host, "kcprimary")))
	preview.call("_dispatch_key_up", _key(KEY_H, false))
	h.check("the release does", _count(host, "kcprimary") == 1,
		str(_count(host, "kcprimary")))
	h.check("and it passed on to the frame tier like any primary handler",
		_tally(preview, "_sent", "keyUp") == up_before + 1,
		"keyUp dispatches: %d -> %d" % [
			up_before, _tally(preview, "_sent", "keyUp")])
	h.complete("`the keyUpScript` exists, and the release runs it")

	# `events.cpp:378-381`: the `EVENT_KEYUP` arm sets `_keyFlags` and dispatches,
	# and nothing else -- only `EVENT_KEYDOWN` writes `_key` and `_keyCode`. So a
	# `keyUp` handler asking `the keyCode` reads the key that went down, which is
	# what makes Rating's `normalkeysx` -- a `keyUpScript` whose whole body is
	# `if the keyCode = 109` -- work at all. A port that wrote the pair on the
	# release too would still pass that, and would answer the wrong key for any
	# handler that outlived a second key.
	h.begin("a release does not rewrite `the key` or `the keyCode`")
	preview.call("_dispatch_key", _key(KEY_H, true))
	preview.call("_dispatch_key_up", _key(KEY_J, false))
	h.check("`the key` is still the key that went down",
		str(host.get_system_prop("key")) == "h",
		"'%s'" % str(host.get_system_prop("key")))
	h.check("`the keyCode` too",
		int(host.get_system_prop("keycode")) == int(Keys.MAC_CODES[KEY_H]),
		str(host.get_system_prop("keycode")))
	h.complete("a release does not rewrite `the key` or `the keyCode`")

	# ------------------------------------------------ what this title asks for
	# Reported, not asserted. It says whether the rules above matter here; it
	# cannot say whether they are implemented, and conflating the two is how a
	# corpus with no site for something becomes a reason not to build it.
	var paths := Paths.new()
	paths.load_config()
	var sites := KeySites.for_root(paths.root)
	var asks: Dictionary = sites["asks"]
	print("")
	print("%s asks for the keyboard by:" % str(paths.root).get_file())
	for label in ["the keyDownScript", "the keyUpScript", "on keyDown", "on keyUp",
			"when keyDown then", "when keyUp then", "dontPassEvent"]:
		print("  %-20s %d" % [label, int(asks.get(label, 0))])

	# ...and the one thing about them that *is* assertable: a handler this title
	# names as its own `keyUpScript` is reachable by a release. Found by reading
	# the root's scripts rather than by naming a movie, so it runs wherever there
	# is one and is skipped -- loudly -- where there is not.
	#
	# Rating is the case with a history. `ARCADE1.dir` member 20 does
	# `set the keyUpScript to "normalkeysx"`, and `normalkeysx` is 40 lines whose
	# every branch is behind `if the keyCode = 109` -- F10, the key that leaves a
	# timed scene, tested at 48 sites. Two things had to be true for that to
	# work and neither was: a release has to reach a script at all, and `the
	# keyCode` has to still hold the key that went *down* when it does.
	var named := _key_up_names(sites)
	var reachable: Array = []
	for name in named:
		if interp.has_handler(str(name).to_lower()):
			reachable.append(str(name))
	print("")
	print("`the keyUpScript` names %s; callable from this movie: %s" % [
		JSON.stringify(named), JSON.stringify(reachable)])
	if not reachable.is_empty():
		h.begin("a handler this title installs as its `keyUpScript` is reached by a release")
		for name in reachable:
			host.set_system_prop("keyupscript", name)
			var before := _tally(preview, "_ran", "keyUpScript:%s" % name)
			preview.call("_dispatch_key", _key(KEY_F10, true))
			preview.call("_dispatch_key_up", _key(KEY_F10, false))
			h.check("`%s` ran on the release" % name,
				_tally(preview, "_ran", "keyUpScript:%s" % name) == before + 1)
			# The half that is easy to get right by accident and wrong in use:
			# these handlers read `the keyCode`, and the release does not carry
			# one. Reading -1 here would make every branch of `normalkeysx` false.
			h.check("and `the keyCode` was still F10's %d while it ran"
				% int(Keys.MAC_CODES[KEY_F10]),
				int(host.get_system_prop("keycode")) == int(Keys.MAC_CODES[KEY_F10]),
				str(host.get_system_prop("keycode")))
		host.set_system_prop("keyupscript", "")
		h.complete("a handler this title installs as its `keyUpScript` is reached by a release")

	# ------------------------------------------------------------- the wiring
	# Everything above went in through `_dispatch_key` / `_dispatch_key_up`. None
	# of it shows that a key a *player* presses and lets go of gets there: that
	# path is `_input` -> `preview/input_router.gd` -> the movie, and it needs a
	# window with keyboard focus, which headless Godot does not have.
	if windowed:
		var window := preview.get_window()
		window.grab_focus()
		DisplayServer.window_move_to_foreground()
		await process_frame
		host.set_system_prop("keydownscript", "")
		host.set_system_prop("keyupscript", "kcpass")
		host.set_global("kcprimary", 0)
		h.begin("a real release reaches the movie through `_input`")
		Input.parse_input_event(_key(KEY_H, true))
		await process_frame
		await process_frame
		var after_press := _count(host, "kcprimary")
		h.check("the press alone ran no key-up handler", after_press == 0,
			str(after_press))
		Input.parse_input_event(_key(KEY_H, false))
		await process_frame
		await process_frame
		h.check("the release ran it", _count(host, "kcprimary") == 1,
			str(_count(host, "kcprimary")))
		# The control: with nothing installed the same release must run nothing,
		# or "the counter went up" is satisfied by anything at all that ticks it.
		host.set_system_prop("keyupscript", "")
		host.set_global("kcprimary", 0)
		Input.parse_input_event(_key(KEY_H, true))
		await process_frame
		Input.parse_input_event(_key(KEY_H, false))
		await process_frame
		await process_frame
		h.check("and with none installed, nothing ran", _count(host, "kcprimary") == 0,
			str(_count(host, "kcprimary")))
		h.complete("a real release reaches the movie through `_input`")
	else:
		print("")
		print("headless: the `_input` wiring is unasserted -- rerun without --headless")

	quit(h.finish("§8.2's key chain in %s" % movie))
