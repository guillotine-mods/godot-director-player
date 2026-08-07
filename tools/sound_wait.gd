extends SceneTree
## Can a `soundBusy` wait ever be answered? The rule behind the traps.
##
##   godot --headless --path . --script tools/sound_wait.gd
##
## `tools/playhead_escape.gd` catches a playhead that is confined with nothing to
## show for it. This catches the *cause* one step earlier, and it catches it
## without a movie: the commonest inescapable wait in Director is a script that
## plays a line and then polls `soundBusy` for the end of it, and every way the
## engine can answer that poll wrongly turns the poll into a wait for something
## that can never happen.
##
##     on exitFrame
##       if not soundBusy(1) then go(marker(0))
##     end
##
## That is `BehaviorScript 250` of this corpus, and the movie has **no way to ask
## whether its own `playFile` worked**. So the engine owes it one guarantee: a
## channel is busy if and only if a sound the script asked for is playing on it
## now. Two failures follow from breaking it, and they look nothing alike from
## outside:
##
##   - answer **busy** when the request never started, and the poll never
##     releases -- the player sees a scene that never ends;
##   - answer **not busy** while the previous sound is still audible, and the
##     next line is spoken over the last one.
##
## Both are the same missing rule, which is why they are asserted together.
##
## Title-agnostic. The corpus supplies the files -- the cases below discover them
## from the index rather than naming any -- and every rule asserted is Director's.

const Harness := preload("res://tools/lib/harness.gd")

## A channel no other harness and no movie is using, so the state asserted here
## is this file's own. Director has eight.
const SPARE := 6


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	var audio := root.get_node_or_null("AudioDirector")
	if audio == null:
		print("AudioDirector autoload is not present")
		quit(1)
		return
	await process_frame
	await _silence_answers(h, audio)
	await _a_failed_request_takes_the_channel(h, audio)
	_the_folder_decides(h, audio)
	quit(h.finish("a `soundBusy` wait can always be answered"))


## Some file this corpus actually holds, as `<relative path>` and `<full path>`,
## or `{}` when the configured game has no audio at all.
func _any_file(audio: Node) -> Dictionary:
	audio.call("_ensure_index")
	var index: Dictionary = audio.get("_path_index")
	for key in index:
		return {"key": str(key), "path": str(index[key])}
	return {}


# ------------------------------------------------------------------ silence

## The floor: a channel with nothing on it is not busy.
##
## Trivial, and it is the case that decides whether the two below mean anything —
## a `sound_busy` that answered false unconditionally would pass them and fail
## this movie in the opposite direction, so the counterpart is asserted with it.
func _silence_answers(h: Harness, audio: Node) -> void:
	var title := "a channel answers for what is on it"
	h.begin(title)
	audio.call("stop_channel", SPARE)
	h.check("a channel nothing has played is not busy", not audio.call("sound_busy", SPARE))

	var file := _any_file(audio)
	if file.is_empty():
		h.check("the configured game holds at least one sound to play", false,
			"nothing indexed")
		h.complete(title)
		return
	audio.call("play_file", SPARE, str(file["key"]) + ".aif")
	await process_frame
	h.check("and a channel a sound was started on is busy",
		audio.call("sound_busy", SPARE), str(file["key"]))
	audio.call("stop_channel", SPARE)
	h.check("`sound stop` ends it", not audio.call("sound_busy", SPARE))
	h.complete(title)


# ---------------------------------------------------- a request that fails

## The one that turns a poll into a trap.
##
## Director's `sound playFile` claims the channel before it opens the file, so a
## name it cannot satisfy leaves the channel **empty**. This port used to leave
## it exactly as it was: the previous sound kept playing and kept answering
## `soundBusy`, so a script that replaced a line with one the disc does not hold
## waited out the wrong sound — and a script whose channel held something long
## waited for ever.
##
## Driven with a name no disc can hold rather than by deleting one, so the case
## says the same thing about any corpus.
func _a_failed_request_takes_the_channel(h: Harness, audio: Node) -> void:
	var title := "a `playFile` that cannot start leaves the channel free"
	h.begin(title)
	var file := _any_file(audio)
	if file.is_empty():
		h.check("the configured game holds at least one sound to play", false,
			"nothing indexed")
		h.complete(title)
		return

	for request in ["no-such-folder/no-such-sound-a1b2c3.aif", ""]:
		audio.call("stop_channel", SPARE)
		audio.call("play_file", SPARE, str(file["key"]) + ".aif")
		await process_frame
		if not h.check("a sound is playing to be replaced",
				audio.call("sound_busy", SPARE)):
			continue
		audio.call("play_file", SPARE, request)
		var named := "'%s'" % request if request != "" else "nothing at all"
		h.check("after a `playFile` naming %s the channel is not busy" % named,
			not audio.call("sound_busy", SPARE),
			"a `soundBusy` guard after this would never release")
		# The audible half of the same rule. `sound_busy` could answer false while
		# the old sound played on, and then the next line is spoken over the last.
		var player: AudioStreamPlayer = audio.call("_ensure_player", SPARE)
		h.check("and the sound it replaced has actually stopped", not player.playing)
	audio.call("stop_channel", SPARE)
	h.complete(title)


# ------------------------------------------------------- the folder decides

## A request is a path, and the folder in it is meaning.
##
## Scripts build these by concatenation from a global, and the global can be one
## segment short — `soundspath` is `soundspathstart & "days" & "\"`, and
## `soundspathstart` is written by one movie's drive probe, so any entry that
## does not pass through it asks for `days\<name>.aif` against a disc that files
## it under `SOUNDS/DAYS/`. Matching only the whole path or only the bare
## filename throws the folder away in exactly that case, and the failure is
## silent: a sound plays, so nothing looks broken, and it is the wrong take.
##
## Asserted against whichever collision the configured corpus happens to have.
func _the_folder_decides(h: Harness, audio: Node) -> void:
	var title := "a request that carries a folder is answered by that folder"
	h.begin(title)
	audio.call("_ensure_index")
	var index: Dictionary = audio.get("_path_index")
	# Group the index by bare filename, and take the first name two folders share.
	var by_name: Dictionary = {}
	var collision := ""
	for key in index:
		var name := str(key).get_file()
		if not by_name.has(name):
			by_name[name] = []
		(by_name[name] as Array).append(str(key))
		if collision == "" and (by_name[name] as Array).size() > 1:
			collision = name
	if collision == "":
		# Not a failure: a corpus with no same-named files cannot exercise this.
		h.check("this corpus has a filename in more than one folder", true,
			"none, so the rule is unexercised here")
		h.complete(title)
		return

	var keys: Array = by_name[collision]
	h.check("a filename in more than one folder to ask about", true,
		"%s in %d folder(s)" % [collision, keys.size()])
	for key_value in keys:
		var key := str(key_value)
		# The request the script would build: the last folder and the filename,
		# without the leading segments a global was supposed to supply.
		var parts := key.split("/", false)
		if parts.size() < 2:
			continue
		var request := "%s/%s" % [parts[parts.size() - 2], parts[parts.size() - 1]]
		var got := str(audio.call("resolve_path", request + ".aif"))
		h.check("'%s' resolves inside '%s'" % [request, parts[parts.size() - 2]],
			got != "" and str(got.get_base_dir()).to_lower().ends_with(
				str(parts[parts.size() - 2]).to_lower()),
			got if got != "" else "nothing")
	h.complete(title)
