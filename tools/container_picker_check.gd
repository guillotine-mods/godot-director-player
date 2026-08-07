extends SceneTree
## Does the container picker find every movie, filter, jump — and stay out of the
## game's way while it is shut?
##
##   godot --headless --script tools/container_picker_check.gd
##
## The last part is the one worth a harness. A picker you filter by typing has to
## own the letters while it is open, and the preview shares its keyboard with a
## movie that may test any of them. So the invariant is not "the picker works",
## it is: **closed, it is not consulted at all; open, it takes everything.**
## Getting either half wrong is invisible until a player types into a game that
## is quietly also being driven, or presses a letter in the picker and watches
## the movie behind it walk somewhere.
##
## Title-agnostic: it reads whatever `director_game.cfg` names and filters on a
## term taken from the list itself, rather than knowing a movie by name.

const Harness := preload("res://tools/lib/harness.gd")
const ContainerPicker := preload("res://scenes/preview/container_picker.gd")
const InputRouter := preload("res://scenes/preview/input_router.gd")
const DebugKeys := preload("res://scenes/preview/debug_keys.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")


func _typed(text: String) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.unicode = text.unicode_at(0)
	event.keycode = KEY_NONE
	return event


func _pressed(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	return event


## Clear whatever is typed and type `text` instead, through the real key path.
## Returns the matches, so a check reads as one line.
func _query(preview: Node, text: String) -> Array:
	for _i in str((preview.get("_picker") as Dictionary).get("query", "")).length():
		InputRouter.key_event(preview, _pressed(KEY_BACKSPACE))
	for i in text.length():
		InputRouter.key_event(preview, _typed(text[i]))
	return (preview.get("_picker") as Dictionary)["shown"]


func _init() -> void:
	var h := Harness.new()
	DebugKeys.load_config()
	var open_key := OS.find_keycode_from_string(DebugKeys.key_name("containers"))
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	for _i in 4:
		await process_frame

	# What the picker offers has to be what the engine can open. Both come out of
	# the same index, and this is the assertion that keeps them that way.
	h.begin("it offers every container the engine can resolve")
	var paths = preview.get("_paths")
	var listed: Array[String] = paths.containers()
	h.check("the list is not empty", listed.size() > 0, "%d entries" % listed.size())
	var unresolvable := ""
	for entry in listed:
		if paths.resolve(entry) == "":
			unresolvable = entry
			break
	h.check("every entry resolves to a real file", unresolvable == "", unresolvable)
	var extensions: Dictionary = {}
	for entry in listed:
		extensions[entry.get_extension()] = true
	h.check("and they are containers, nothing else",
		not extensions.keys().any(func(e): return not Paths.CONTAINER_EXTENSIONS.has(e)),
		str(extensions.keys()))
	h.complete("it offers every container the engine can resolve")

	# Closed is the default and the resting state, and the whole point of the
	# design: a movie key must reach the movie.
	h.begin("closed, it takes nothing")
	h.check("it starts closed", not bool((preview.get("_picker") as Dictionary).get("open", false)))
	var before := int(preview.get("_index"))
	InputRouter.key_event(preview, _typed("d"))
	h.check("a letter does not open it",
		not bool((preview.get("_picker") as Dictionary).get("open", false)))
	# The debug map still works, which is the other thing a picker that grabbed
	# keys early would break.
	InputRouter.key_event(preview, _pressed(
		OS.find_keycode_from_string(DebugKeys.key_name("step_forward"))))
	h.check("and the other preview keys still work",
		int(preview.get("_index")) == before + 1,
		"%d -> %d" % [before, int(preview.get("_index"))])
	h.complete("closed, it takes nothing")

	h.begin("open, it takes everything")
	InputRouter.key_event(preview, _pressed(open_key))
	h.check("the key opens it",
		bool((preview.get("_picker") as Dictionary).get("open", false)))
	var held := int(preview.get("_index"))
	# A key that is bound in the debug map, pressed while the picker is open. It
	# must edit the filter or do nothing, never step the playhead behind the list.
	InputRouter.key_event(preview, _pressed(
		OS.find_keycode_from_string(DebugKeys.key_name("step_forward"))))
	h.check("a preview binding does not act behind it",
		int(preview.get("_index")) == held)
	h.complete("open, it takes everything")

	# A filter term taken from the list rather than from a movie this harness
	# knows the name of, so it follows whatever game is configured. A movie
	# rather than a cast, because Enter has to actually play it -- and not the
	# one already loaded, or "it is now playing" would prove nothing.
	var sample := ""
	for entry in listed:
		if not ContainerName.MOVIE.has(entry.get_extension()):
			continue
		if entry.get_file() == str(preview.call("movie_name")).to_lower():
			continue
		# One in a subdirectory if the title has any, so the directory-scoping
		# checks below have something to be about. A flat title falls back to
		# whatever there is and those two checks report as skipped.
		if sample == "" or (sample.get_base_dir() == "" and entry.get_base_dir() != ""):
			sample = entry
		if sample.get_base_dir() != "":
			break
	var stem := sample.get_file().get_basename()
	h.begin("typing filters, and the filter is a filter")
	_query(preview, stem)
	var state: Dictionary = preview.get("_picker")
	h.check("the query is what was typed", str(state["query"]) == stem, str(state["query"]))
	h.check("the wanted entry is among the matches",
		(state["shown"] as Array).has(sample),
		"%d matches" % (state["shown"] as Array).size())
	h.check("and it narrowed the list", (state["shown"] as Array).size() < listed.size(),
		"%d of %d" % [(state["shown"] as Array).size(), listed.size()])
	InputRouter.key_event(preview, _pressed(KEY_BACKSPACE))
	h.check("backspace widens it again",
		((preview.get("_picker") as Dictionary)["shown"] as Array).size()
			>= (state["shown"] as Array).size())
	# A term with no slash matches the filename, not the directory. Matching the
	# whole path is the obvious rule and it is useless: every one of this title's
	# movies is under one folder, so "da" matched 83 of 86 on `pip2data` rather
	# than on `day1`. Asserted against whatever directory this game actually uses,
	# and against the escape hatch: the same term with a slash matches the path.
	var folder := sample.get_base_dir()
	if folder != "":
		h.check("a bare term does not match on the directory",
			_query(preview, folder).size() < listed.size(),
			"'%s' matched %d of %d" % [
				folder, _query(preview, folder).size(), listed.size()])
		h.check("with a slash it does",
			_query(preview, folder + "/").size() > 1,
			"'%s/' matched %d" % [folder, _query(preview, folder + "/").size()])
	else:
		print("this title is flat; the directory-scoping checks have nothing to say")
	h.complete("typing filters, and the filter is a filter")

	h.begin("enter plays the selected movie and closes")
	# Retype the stem, then pick the entry the harness meant rather than whatever
	# row 0 is: several containers can share a stem across directories.
	_query(preview, stem)
	state = preview.get("_picker")
	var wanted := (state["shown"] as Array).find(sample)
	for _i in maxi(wanted, 0):
		InputRouter.key_event(preview, _pressed(KEY_DOWN))
	InputRouter.key_event(preview, _pressed(KEY_ENTER))
	h.check("it closed", not bool((preview.get("_picker") as Dictionary).get("open", false)))
	# The player-visible claim: that movie is now the one playing. Compared on
	# the filename, because `movie_name` reports the filesystem's spelling and
	# the index is keyed lower-case.
	h.check("that container is playing",
		str(preview.call("movie_name")).to_lower() == sample.get_file(),
		"%s, wanted %s" % [str(preview.call("movie_name")), sample.get_file()])
	h.complete("enter plays the selected movie and closes")

	# A cast is in the list and has no score. Enter on one must say so rather
	# than call `go to movie` and leave the player looking at an unchanged stage.
	var cast := ""
	for entry in listed:
		if ContainerName.CAST.has(entry.get_extension()):
			cast = entry
			break
	h.begin("a cast is offered but not pretended to be playable")
	if cast == "":
		h.check("this title ships no casts to try", true)
	else:
		var playing_before := str(preview.call("movie_name"))
		InputRouter.key_event(preview, _pressed(open_key))
		_query(preview, cast.get_file().get_basename())
		state = preview.get("_picker")
		for _i in maxi((state["shown"] as Array).find(cast), 0):
			InputRouter.key_event(preview, _pressed(KEY_DOWN))
		InputRouter.key_event(preview, _pressed(KEY_ENTER))
		state = preview.get("_picker")
		h.check("it stays open", bool(state.get("open", false)))
		h.check("it says why", str(state.get("note", "")).contains("cast"),
			str(state.get("note", "")))
		h.check("and nothing was loaded",
			str(preview.call("movie_name")) == playing_before)
		InputRouter.key_event(preview, _pressed(KEY_ESCAPE))
	h.complete("a cast is offered but not pretended to be playable")

	h.begin("escape closes without going anywhere")
	var playing := str(preview.call("movie_name"))
	InputRouter.key_event(preview, _pressed(open_key))
	InputRouter.key_event(preview, _pressed(KEY_ESCAPE))
	h.check("it closed", not bool((preview.get("_picker") as Dictionary).get("open", false)))
	h.check("and the movie did not change", str(preview.call("movie_name")) == playing)
	h.complete("escape closes without going anywhere")

	quit(h.finish("the container picker"))
