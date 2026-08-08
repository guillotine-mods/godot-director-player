extends SceneTree
## Movie-In-A-Window: does a second movie open, run itself, take the clicks and
## close itself again — and does `tell` stop writing to the wrong movie?
##
##   godot --headless --script tools/window_preview.gd
##   godot --headless --script tools/window_preview.gd -- --file PIP2DATA/DAY1.dir
##
## The bug this exists to keep fixed is not the missing feature. `tell` used to
## run its body on the one stage, so
##
##     tell window("joke.dxr")
##       puppetSprite(3, 1)
##     end tell
##     tell window("joke.dxr")
##       set the memberNum of sprite 3 to the number of member ("joke" & …)
##     end tell
##
## — `MASTER/CastScript 69 - jokebtl`, the handler on the joke bottle — puppeted
## channel 3 of *the room the player was standing in* and swapped its member,
## with no window anywhere. Every check below is about which movie a statement
## landed in, and each asserts state a player would see rather than that a
## function was called.
##
## The Lingo is quoted from the corpus and named at each site, compiled by the
## real compiler and dispatched through the real interpreter against the real
## preview. The only thing synthesised is the trigger.
##
## Works against any boot movie: nothing here needs the room the bottle is in,
## only a stage to be wrongly written to. Run it against DAY1 as well, which is
## where the report came from.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")

## `MASTER/CastScript 69 - jokebtl` lines 19-27, verbatim apart from the member
## number, which the original builds from `globalday` and the bottle's index and
## which is not what is being tested. This is the reproduction.
const JOKE_BOTTLE := """
on openjoke
  window("joke.dxr").windowType = 2
  tell window("joke.dxr")
    set the centerStage to 1
  end tell
  open(window("joke.dxr"))
  tell window("joke.dxr")
    puppetSprite(3, 1)
  end tell
  tell window("joke.dxr")
    set the memberNum of sprite 3 to 40
  end tell
end
"""

## `NIGHT1/night2/BehaviorScript 415` — the map button, and the one opening site
## that `go`es inside the `tell` before the `open`. If the window's movie were
## not loaded until `open`, or if `open` reset the playhead, the map would arrive
## at frame 0 instead of at its night map.
const MAP_BUTTON := """
on openmap
  window("map.dxr").windowType = 2
  tell window("map.dxr")
    set the centerStage to 1
  end tell
  tell window("map.dxr")
    go("nightmap")
  end tell
  open(window("map.dxr"))
end
"""

## `MAP/Internal/BehaviorScript 16`, the tail of it — the reverse direction, and
## by far the commoner one: 135 of the corpus's 194 `tell` statements are `tell
## the stage`, all written inside MAP or SAVELOAD to drive the movie underneath.
## `rir` is the case that decides how `tell` scopes variables: it is assigned
## inside the block and read after `end tell`.
const MAP_DESTINATION := """
on gohome
  global nextroomdata
  tell the stage
    sprite(30).visible = 0
  end tell
  tell the stage
    rir = the movieName
  end tell
  nextroomdata = rir
end
"""

## The rest of §14's window vocabulary, none of which this corpus touches: it
## writes `the windowType` and `the centerStage` and nothing else. Built from the
## reference because this is a Director engine and the next title will use them,
## and exercised here because "implemented but unverified against the corpus" is
## not a licence to leave it unrun — what the checks below prove is that the
## engine does what the code claims, not that Director did.
const WINDOW_VOCABULARY := """
on dressthewindow
  global wlist, wfront
  window("map.dxr").windowType = 0
  tell window("map.dxr")
    set the title to "The Map"
    set the titleVisible to 1
    set the rect to [40, 30, 360, 270]
  end tell
  open(window("map.dxr"))
  wlist = the windowList
  wfront = the frontWindow
end
"""

## `the modal of window` — §14's "a modal window blocks its parent".
const MAKE_MODAL := """
on blockit
  tell window("map.dxr")
    set the modal to 1
  end tell
end
"""

## The **command spelling** of the same three verbs, which is the only spelling
## `rating` uses and which no case above reaches: every handler in this file
## calls `window("x")` first, so the window always exists before anything else
## touches it and the name is always carried by a handle.
##
## `Panel.cst` member 35 — the bag on the panel in every room — is spelled
## entirely without that call:
##
##     set the windowType of window "inventor.dir" to 2
##     open window "inventor.dir"
##
## Split into three handlers because the two halves failed for *different*
## reasons and either alone is fatal, so one combined check could not say which
## broke (`bugs.md` 55). Naming the window is what creates it, and the name has
## to survive as far as the resolver: `window_key_of` is `get_basename()`, so a
## key made too early reached `resolve` as `inventor` and matched nothing.
##
## `joke.dxr` rather than `inventor.dir` on purpose — this is an engine rule, and
## asserting it on the corpus the gate pins to is what makes it one.
const COMMAND_NAME_ONLY := """
on nameit
  set the windowType of window "joke.dxr" to 2
end
"""

const COMMAND_OPEN := """
on openit
  open window "joke.dxr"
end
"""

const COMMAND_FORGET := """
on shutit
  forget window "joke.dxr"
end
"""

## `MASTER/External/MovieScript 12 - jokes funk`. `jokes.dxr` is named at 36
## sites and is not on this disc, and nothing calls `runjokes` either — so this
## is the dead branch, and the point of running it is that a `tell` at a window
## that is not there must drop its body rather than run it on the caller.
const MISSING_WINDOW := """
on runmissing
  window("jokes.dxr").windowType = 2
  tell window("jokes.dxr")
    puppetSprite(7, 1)
  end tell
  tell window("jokes.dxr")
    set the memberNum of sprite 7 to 99
  end tell
end
"""


func _run(preview: Node, source: String, handler: String, name: String) -> bool:
	var compiler := Compiler.new()
	var ast: Dictionary = compiler.compile_source(source, name)
	if ast.is_empty():
		print("  compile failed: %s (line %d)" % [compiler.error, compiler.error_line])
		return false
	return bool(preview.get("_interpreter").run_handler_in_script(ast, handler))


func _init() -> void:
	var h := Harness.new()
	var args := Args.parse()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	# Far enough in for the boot movie to have puppeted something of its own. The
	# window path does not need it; a stage with no puppet state cannot show that
	# the window left its state alone.
	for i in Args.number(args, "steps", 60):
		preview.call("_advance")
	var host_overrides: Dictionary = preview.get("_overrides")
	var host_movie := str(preview.call("movie_name"))
	var host_channel_3_before := JSON.stringify(host_overrides.get(3, {}))

	# ---------------------------------------------------------------- opening
	h.begin("the joke bottle opens a second movie instead of puppeting this one")
	h.check("the handler ran", _run(preview, JOKE_BOTTLE, "openjoke", "harness jokebtl"))

	var window: Node = preview.call("window_at", Vector2(320, 240))
	h.check("a window is over the stage", window != null,
		"" if window == null else str(window.call("movie_name")))
	if window == null:
		h.complete("the joke bottle opens a second movie instead of puppeting this one")
		quit(h.finish("Movie-In-A-Window"))
		return

	h.check("the window is running a different movie from the stage",
		str(window.call("movie_name")).to_lower() != host_movie.to_lower(),
		"%s over %s" % [str(window.call("movie_name")), host_movie])
	h.check("the window brought its own score",
		int(window.get("_score").frame_count) > 0
			and int(window.get("_score").frame_count) != int(preview.get("_score").frame_count),
		"%d frames vs the stage's %d" % [
			int(window.get("_score").frame_count), int(preview.get("_score").frame_count)])
	h.check("the window brought its own cast table",
		window.get("_table") != null and window.get("_table") != preview.get("_table"))

	# The reproduction, stated as the player would see it: the bottle's `tell`
	# puppeted channel 3 and swapped its member. Those writes must be in the
	# window's movie and absent from the stage's.
	var window_overrides: Dictionary = window.get("_overrides")
	h.check("the window's channel 3 is puppeted, as the `tell` asked",
		window_overrides.has(3), JSON.stringify(window_overrides.get(3, {})))
	h.check("the window's channel 3 shows the member the `tell` named",
		int((window_overrides.get(3, {}) as Dictionary).get("membernum", -1)) == 40,
		JSON.stringify(window_overrides.get(3, {})))
	h.check("the stage's channel 3 was not touched",
		JSON.stringify(host_overrides.get(3, {})) == host_channel_3_before,
		"%s -> %s" % [host_channel_3_before, JSON.stringify(host_overrides.get(3, {}))])

	# §4.2 one level up: the front window is hit-tested before the stage. Every
	# movie in this corpus declares a 640x480 stage (`tools/window_survey.gd` over
	# all 61 that have a config) and all 21 opening sites centre the window, so the
	# window covers the stage and takes every point in it.
	var clicked: Node = preview.call("route_click", Vector2(320, 240))
	h.check("a click in the window goes to the window", clicked == window,
		"went to %s" % ("the stage" if clicked == preview else str(clicked)))
	h.complete("the joke bottle opens a second movie instead of puppeting this one")

	# ------------------------------------------- the window runs, and closes itself
	#
	# `JOKE/Internal/BehaviorScript 1` is `on exitFrame / forget(window("joke.dxr"))
	# / end`: the window's own score is what closes it, from inside the window,
	# once its wait-for-click frame is past. That is the teardown path 22 sites in
	# this corpus use, so it is the one worth asserting rather than a `forget`
	# called from the harness.
	h.begin("the window runs its own score and closes itself from inside")
	var window_frame_before: int = window.call("current_frame")
	var host_frame_before: int = preview.call("current_frame")
	window.call("_advance")
	h.check("the window's playhead moved",
		int(window.call("current_frame")) != window_frame_before,
		"%d -> %d" % [window_frame_before, int(window.call("current_frame"))])
	h.check("the stage's playhead did not move with it",
		int(preview.call("current_frame")) == host_frame_before,
		"stage stayed on %d" % host_frame_before)

	# Its own `forget` is a few frames along; step until it fires or give up.
	var closed_after := -1
	for i in 200:
		if preview.call("window_at", Vector2(320, 240)) == null:
			closed_after = i
			break
		window.call("_advance")
	h.check("the window's own `forget(window(\"joke.dxr\"))` closed it",
		closed_after >= 0, "after %d step(s)" % closed_after)
	var after: Node = preview.call("route_click", Vector2(320, 240))
	h.check("the click goes back to the stage", after == preview,
		"went to %s" % ("nothing" if after == null else str(after)))
	h.complete("the window runs its own score and closes itself from inside")
	await process_frame

	# ------------------------------------------------- `tell the stage`, and back
	h.begin("a window drives the stage with `tell the stage`")
	h.check("the map button ran", _run(preview, MAP_BUTTON, "openmap", "harness map button"))
	var map: Node = preview.call("window_at", Vector2(320, 240))
	h.check("the map window is open", map != null,
		"" if map == null else str(map.call("movie_name")))
	if map == null:
		h.complete("a window drives the stage with `tell the stage`")
		quit(h.finish("Movie-In-A-Window in the container-reading preview"))
		return
	# The `go("nightmap")` inside the `tell` happened *before* the `open`, so the
	# window has to have arrived there rather than at frame 0.
	var night_map: int = int(map.get("_labels").labels.get("nightmap", -1))
	h.check("`go` inside the `tell` before `open` chose the frame the window opened on",
		night_map >= 0 and int(map.call("current_frame")) == night_map,
		"label nightmap is frame %d, the window is on %d" % [
			night_map, int(map.call("current_frame"))])

	preview.call("lingo_set_sprite_prop", 30, "visible", 1)
	h.check("the window's handler ran",
		_run(map, MAP_DESTINATION, "gohome", "harness map destination"))
	h.check("`tell the stage / sprite(30).visible = 0` hid the *stage's* sprite",
		int(preview.call("lingo_sprite_prop", 30, "visible")) == 0,
		"stage visible = %s" % str(preview.call("lingo_sprite_prop", 30, "visible")))
	h.check("the window's own channel 30 was not hidden instead",
		not (map.get("_overrides") as Dictionary).has(30),
		JSON.stringify((map.get("_overrides") as Dictionary).get(30, {})))
	# `rir = the movieName` inside a `tell` writes a local of the *calling*
	# handler, and the next line reads it. Fifteen sites depend on that.
	var carried := str(map.get("_interpreter").globals.get("nextroomdata", ""))
	h.check("a variable assigned inside `tell the stage` survived `end tell`",
		carried.to_lower() == host_movie.to_lower(),
		"nextroomdata = '%s', the stage is '%s'" % [carried, host_movie])
	h.check("`the movieName` inside `tell the stage` answered the stage's movie",
		carried.to_lower() != str(map.call("movie_name")).to_lower(),
		"'%s' vs the window's '%s'" % [carried, str(map.call("movie_name"))])
	h.complete("a window drives the stage with `tell the stage`")

	# ----------------------------------------------------------------- globals
	h.begin("the stage and its window share one set of globals")
	map.get("_interpreter").globals["windowcarried"] = "yes"
	h.check("a global set in the window is readable on the stage",
		str(preview.get("_interpreter").globals.get("windowcarried", "")) == "yes")
	preview.call("lingo_forget_window", "map.dxr", true)
	await process_frame
	h.check("the map window is gone",
		preview.call("window_at", Vector2(320, 240)) == null)
	h.check("what the window put in a global outlived it",
		str(preview.get("_interpreter").globals.get("windowcarried", "")) == "yes")
	h.complete("the stage and its window share one set of globals")

	# ------------------------------------- the vocabulary the corpus never uses
	#
	# Everything below is implemented from the reference and is unverified against
	# this corpus, which writes only `the windowType` and `the centerStage`. The
	# checks assert the engine, not Director.
	h.begin("§14's other window properties place, title and block a window")
	h.check("the handler ran",
		_run(preview, WINDOW_VOCABULARY, "dressthewindow", "harness window vocabulary"))
	var dressed: Node = preview.call("window_at", Vector2(200, 150))
	h.check("the window opened where `the rect of window` put it", dressed != null,
		"" if dressed == null else str(dressed.call("own_window_prop", "rect")))
	if dressed == null:
		h.complete("§14's other window properties place, title and block a window")
		quit(h.finish("Movie-In-A-Window in the container-reading preview"))
		return
	var placed: Rect2 = dressed.call("window_frame")
	h.check("the window is 320x240 and not the movie's own 640x480",
		int(placed.size.x) >= 320 and int(placed.size.x) < 640,
		"frame %s, the movie's rect is %s" % [
			str(placed), str(dressed.call("own_window_prop", "sourcerect"))])
	h.check("`the title` is what the script set",
		str(dressed.call("window_title")) == "The Map",
		str(dressed.call("window_title")))
	h.check("a titled window insets its movie by a title bar",
		float((dressed.call("chrome_inset") as Vector2).y) > 1.0,
		"inset %s for windowType %d" % [
			str(dressed.call("chrome_inset")), int(dressed.get("_window_type"))])
	# A window that does not cover the stage leaves the stage clickable, which is
	# the whole reason the hit test is a rectangle and not "is a window open".
	h.check("a click outside the window still reaches the stage",
		preview.call("route_click", Vector2(600, 440)) == preview)
	h.check("a click inside the window reaches the window",
		preview.call("route_click", Vector2(200, 150)) == dressed)

	var listed: Variant = preview.get("_interpreter").globals.get("wlist", [])
	h.check("`the windowList` names the open window",
		typeof(listed) == TYPE_ARRAY and (listed as Array).size() == 1,
		JSON.stringify(listed))
	var front: Variant = preview.get("_interpreter").globals.get("wfront", null)
	h.check("`the frontWindow` answers a reference to it",
		typeof(front) == TYPE_DICTIONARY and str((front as Dictionary).get("window", "")) == "map",
		JSON.stringify(front))

	h.check("the modal handler ran", _run(preview, MAKE_MODAL, "blockit", "harness modal"))
	h.check("a modal window swallows a click aimed past it",
		preview.call("route_click", Vector2(600, 440)) == null)
	h.check("and still takes the ones aimed at it",
		preview.call("route_click", Vector2(200, 150)) == dressed)
	preview.call("lingo_forget_window", "map.dxr", true)
	await process_frame
	h.check("the stage is clickable again once the modal window is forgotten",
		preview.call("route_click", Vector2(600, 440)) == preview)
	h.complete("§14's other window properties place, title and block a window")

	# --------------------------------------------------- a window with no movie
	h.begin("a `tell` at a window that is not there writes to nothing")
	var before_7 := JSON.stringify(host_overrides.get(7, {}))
	h.check("the handler ran",
		_run(preview, MISSING_WINDOW, "runmissing", "harness jokes funk"))
	h.check("no window was opened for a movie that is not on this disc",
		preview.call("window_at", Vector2(320, 240)) == null)
	h.check("the stage's channel 7 was not puppeted by the dropped body",
		JSON.stringify(host_overrides.get(7, {})) == before_7,
		"%s -> %s" % [before_7, JSON.stringify(host_overrides.get(7, {}))])
	h.complete("a `tell` at a window that is not there writes to nothing")

	# ------------------------------------------- the deepest window in the corpus
	#
	# `SAVELOAD.dir` is 255 frames with 35 scripts of its own — 17 `exitFrame`, 17
	# `mouseUp`, one `enterFrame` — so the question it settles is whether a window
	# gets a *frame loop*, not just a picture. Its `BehaviorScript 42` is an
	# `exitFrame` that restores the save and then sends the stage to another movie
	# with `tell the stage / go(nof, …)`, so running it here has real consequences
	# for the stage; this is the last case for that reason.
	h.begin("the save screen runs its own frame loop as a window")
	preview.call("lingo_window", "saveload.dxr")
	preview.call("lingo_open_window", "saveload.dxr")
	var save: Node = preview.call("window_at", Vector2(320, 240))
	h.check("the save screen opened", save != null,
		"" if save == null else str(save.call("movie_name")))
	if save != null:
		h.check("it brought its own 255-frame score",
			int(save.get("_score").frame_count) > 200,
			"%d frames" % int(save.get("_score").frame_count))
		for i in 8:
			save.call("_advance")
		var ran: Dictionary = save.get("_ran")
		h.check("its own `exitFrame` handlers ran in the window",
			int(ran.get("exitFrame", 0)) > 0, JSON.stringify(ran))
		preview.call("lingo_forget_window", "saveload.dxr", true)
	h.complete("the save screen runs its own frame loop as a window")

	# ------------------------------------------ the command spelling of the same
	#
	# The player-visible statement: a script that never calls `window(...)` still
	# gets a window, and it gets the one it named. Both halves are asserted apart
	# because they broke apart.
	h.begin("`open window \"x\"` opens the window a designator already named")
	h.check("the naming handler ran",
		_run(preview, COMMAND_NAME_ONLY, "nameit", "harness command name"))
	# Naming it is what makes it exist (§14). Before this, the designator's bare
	# string failed an `is_window_ref` guard, the write went nowhere, and nothing
	# was created for the `open` on the next line to find.
	var named: Dictionary = preview.get("_windows")
	h.check("naming the window in a designator created it",
		named.has("joke"), JSON.stringify(named.keys()))
	if not named.has("joke"):
		h.complete("`open window \"x\"` opens the window a designator already named")
		quit(h.finish("Movie-In-A-Window in the container-reading preview"))
		return
	var commanded: Node = named["joke"]
	h.check("it resolved to the movie the script named, extension and all",
		str(commanded.call("movie_name")).to_lower().contains("joke"),
		str(commanded.call("movie_name")))
	h.check("`the windowType` the designator set landed on it",
		int(commanded.get("_window_type")) == 2,
		"windowType %d" % int(commanded.get("_window_type")))
	# Named is not shown: `open` is a separate verb, and 21 corpus sites depend on
	# being able to dress a window before showing it.
	h.check("naming it did not show it", not bool(commanded.get("_window_shown")))
	h.check("nothing is over the stage yet",
		preview.call("window_at", Vector2(320, 240)) == null)

	h.check("the opening handler ran",
		_run(preview, COMMAND_OPEN, "openit", "harness command open"))
	h.check("the command form opened the window it named",
		preview.call("window_at", Vector2(320, 240)) == commanded,
		"" if commanded == null else str(commanded.call("movie_name")))
	h.check("it is showing", bool(commanded.get("_window_shown")))
	h.check("it brought its own score", int(commanded.get("_score").frame_count) > 0,
		"%d frames" % int(commanded.get("_score").frame_count))
	h.check("it is still windowType 2 after opening",
		int(commanded.get("_window_type")) == 2,
		"windowType %d" % int(commanded.get("_window_type")))
	h.check("a click in it goes to it, not to the stage",
		preview.call("route_click", Vector2(320, 240)) == commanded)

	# `forget` shares the path and is 52 of `rating`'s 64 window sites, so the
	# teardown is worth the same spelling.
	h.check("the closing handler ran",
		_run(preview, COMMAND_FORGET, "shutit", "harness command forget"))
	await process_frame
	h.check("`forget window \"x\"` closed it",
		preview.call("window_at", Vector2(320, 240)) == null)
	h.check("the click goes back to the stage",
		preview.call("route_click", Vector2(320, 240)) == preview)
	h.complete("`open window \"x\"` opens the window a designator already named")

	quit(h.finish("Movie-In-A-Window in the container-reading preview"))
