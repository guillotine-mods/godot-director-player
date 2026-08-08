extends SceneTree
## The player's own route to a saved game: menu, Load, the slot list, a slot, go.
##
##   godot --headless --path . --script tools/builtin_load.gd
##   godot --headless --path . --script tools/builtin_load.gd -- --slot 2
##   godot --headless --path . --script tools/builtin_load.gd -- --real
##
## `tools/save_movie.gd` proves the writer. This proves the *route*, and the two
## are not the same claim: a harness that calls `dosave` and `doload` directly can
## pass while every path a player can take is shut, and that has happened twice in
## this port -- the main menu's Load button was inert for a fortnight behind a
## guard that read `the visible of sprite 30` on an empty channel (`bugs.md` 34),
## and `saveMovie` itself was bound inert and every save "worked" until a restart.
## So nothing here calls a save handler. It clicks.
##
## Six hops, each asserted where it happens rather than at the end, because "the
## game did not come back" is the same observation whichever of them broke:
##
##   1  the menu's Load button is *reachable* -- the channel its guard tests
##      answers TRUE, which for an empty channel is the Director answer
##   2  clicking it opens a window running another movie
##   3  the window reaches its slot list, having gone out to the save container
##      and back for the names
##   4  the eight slots show what the save container holds
##   5  choosing one is answered by a handler in the save screen
##   6  pressing Load sends the *stage* to the movie and the marker the slot
##      recorded, and closes the window
##
## **The slot data is reported, not assumed.** Every slot's recorded movie and
## room is printed with whether that room still names a marker in that movie,
## because a slot that records a room that does not exist loads to frame 0 and
## looks exactly like a broken loader. That is what a real save in this corpus
## does: `HEZSAVE.DIR` slot 1 records `hndcur2`, which is a cursor bitmap and not
## a room -- it is member 12 of library 1, and the save was written before
## `the castNum of sprite 1` learned to carry its library, when `member(<ref>).name`
## resolved a bare 12 in the wrong cast. The loader is fine; the record is not,
## and a save written today records `shore2` like the 1997 one beside it.
##
## Title-agnostic in shape: the Load button, the slot buttons and the load button
## are all found by what their scripts *do* rather than by channel number, and the
## destination is read out of the save container rather than named here. A title
## with no save movie reports that and passes nothing, which is the honest answer.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Cast := preload("res://director/director_cast.gd")
const Labels := preload("res://director/director_labels.gd")
const Paths := preload("res://director/director_paths.gd")

## The guard the in-game menus copy onto the main menu: "not mid-cutscene", read
## off the channel that holds the walking player. On the main menu that channel is
## empty in every frame, and an empty channel is a *visible* channel in Director.
const WALKER_CHANNEL := 30

## How the three buttons are recognised, by what their compiled scripts contain.
## `go("loadgame")` is the menu's Load; `doload` is the slot list's Load; a
## handler that reads `the clickOn` and hides its siblings is a slot.
const OPENS_LOAD := "loadgame"
const LOADS := "doload"
const PICKS_SLOT := "clickon"


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured (director_game.cfg)")
		quit(1)
		return

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var slots := _slots(paths)
	_report(slots)
	var wanted := Args.number(args, "slot", _first_loadable(slots))
	if wanted <= 0:
		print("no slot in the save container records a room that still exists")
		quit(1)
		return
	print("loading slot %d" % wanted)
	print("")

	await _walk(h, preview, args, slots, wanted)
	quit(h.finish("the built-in load, by the route a player takes"))


# --------------------------------------------------------------------- the walk

func _walk(h: Harness, preview: Node, args: Dictionary, slots: Array,
		wanted: int) -> void:
	# --- 1. the menu, and the guard the Load button sits behind ---------------
	h.begin("the main menu's Load button is reachable")
	preview.call("lingo_go_label", Args.text(args, "label", "mainmenu"))
	await _settle(preview, args, 6)
	h.check("the menu movie is open", str(preview.call("movie_name")) != "",
		str(preview.call("movie_name")))
	# Director answers TRUE for a channel with nothing in it -- these are channel
	# properties, and an empty channel is a visible one. This port answered 0 and
	# the whole handler was skipped, silently.
	h.check("`the visible of sprite %d` is TRUE on a channel with no sprite"
		% WALKER_CHANNEL,
		int(preview.call("lingo_sprite_prop", WALKER_CHANNEL, "visible")) == 1,
		"answered %s" % str(preview.call("lingo_sprite_prop", WALKER_CHANNEL, "visible")))
	var button := _channel_doing(preview, OPENS_LOAD)
	h.check("a sprite on the menu opens the save screen", button > 0,
		"channel %d" % button)
	h.complete("the main menu's Load button is reachable")
	if button <= 0:
		return

	# --- 2. clicking it opens the save movie in a window ----------------------
	h.begin("clicking Load opens the save screen")
	var rect: Rect2 = preview.call("lingo_sprite_rect", button)
	h.check("the button has a rectangle to click", rect.size.x > 0.0 and rect.size.y > 0.0,
		str(rect))
	preview.call("route_click", rect.get_center())
	var window: Node = preview.call("window_at", rect.get_center())
	h.check("a window opened over the stage", window != null,
		"" if window == null else str(window.call("movie_name")))
	if window == null:
		h.complete("clicking Load opens the save screen")
		return
	h.check("it is running a different movie from the stage",
		str(window.call("movie_name")).to_lower()
			!= str(preview.call("movie_name")).to_lower(),
		"%s over %s" % [str(window.call("movie_name")), str(preview.call("movie_name"))])
	h.complete("clicking Load opens the save screen")

	# --- 3 & 4. the slot list, filled from the save container ----------------
	h.begin("the slot list arrives filled from the save container")
	var visited := await _settle_window(preview, args, 40)
	window = preview.call("window_at", Vector2(320, 240))
	h.check("the window is still open", window != null)
	if window == null:
		h.complete("the slot list arrives filled from the save container")
		return
	# The names do not live in the save *screen*: it sends its playhead into the
	# save container, which copies them into a global, and comes back. So the
	# proof that the round trip happened is that the window visited a second
	# movie on the way here.
	h.check("the save screen went out to another movie and came back",
		visited.size() >= 2, " -> ".join(visited))
	var shown := _slot_fields(window, slots.size())
	var matching := 0
	for i in slots.size():
		if str(shown.get(i + 1, "")) == str((slots[i] as Dictionary)["name"]):
			matching += 1
	h.check("every slot shows the name the save container holds",
		matching == slots.size(), "%d of %d: %s" % [
			matching, slots.size(), JSON.stringify(shown)])
	h.complete("the slot list arrives filled from the save container")

	# --- 5. choosing a slot --------------------------------------------------
	#
	# What "slot 2 is armed" *is*, in this movie, is that the second of the eight
	# name sprites is the only visible one -- the load handler finds the slot by
	# scanning them. That is a channel-number fact, so it is not asserted here;
	# what is asserted is that the click reached a handler at all, and hop 6 then
	# proves the right slot was read by landing in the room only that slot
	# recorded. A wrong slot lands somewhere else, and says so.
	h.begin("the slot list answers a click")
	var pickers := _channels_doing(window, PICKS_SLOT)
	h.check("the list has one button per slot", pickers.size() == slots.size(),
		"%d buttons, %d slots" % [pickers.size(), slots.size()])
	if pickers.size() < wanted:
		h.complete("the slot list answers a click")
		return
	var picker: int = int(pickers[wanted - 1])
	var before: int = int((window.get("_ran") as Dictionary).get("mouseUp", 0))
	var picker_rect: Rect2 = window.call("lingo_sprite_rect", picker)
	preview.call("route_click", window.position + picker_rect.get_center())
	h.check("a `mouseUp` handler ran in the save screen",
		int((window.get("_ran") as Dictionary).get("mouseUp", 0)) > before,
		JSON.stringify(window.get("_ran")))
	await _settle_window(preview, args, 4)
	h.complete("the slot list answers a click")

	# --- 6. and the game comes back ------------------------------------------
	h.begin("pressing Load resumes the saved game on the stage")
	var slot: Dictionary = slots[wanted - 1]
	var go := _channel_doing(window, LOADS)
	h.check("the list has a load button", go > 0, "channel %d" % go)
	if go <= 0:
		h.complete("pressing Load resumes the saved game on the stage")
		return
	var go_rect: Rect2 = window.call("lingo_sprite_rect", go)
	var was := str(preview.call("movie_name"))
	preview.call("route_click", window.position + go_rect.get_center())
	# **Where it landed, not where it is.** A room's own score runs on the moment
	# it is entered -- this one is a seven-frame idle loop -- so a frame read
	# forty steps later says nothing about where the `go` put the playhead. The
	# frame is taken on the step the stage's movie first changes.
	var arrival := await _land(preview, args, 60, was)

	h.check("the save screen closed itself",
		preview.call("window_at", Vector2(320, 240)) == null)
	h.check("the stage left the menu", not str(arrival.get("movie", "")).is_empty(),
		"still in %s" % was)
	var landed := str(arrival.get("movie", ""))
	h.check("the stage is in the movie the slot recorded",
		_same_container(landed, str(slot["movie"])),
		"%s, the slot says %s" % [landed, str(slot["movie"])])
	# Landing on frame 0 is the failure this exists to catch: `go` to a marker
	# that is not there leaves the playhead at the top of the movie, and the
	# player sees the room's opening cutscene instead of the room they saved in.
	h.check("on the frame the room it recorded starts at (%s = %d)" % [
			str(slot["room"]), int(slot["frame"])],
		int(arrival.get("frame", -1)) == int(slot["frame"]),
		"landed on %s" % str(arrival.get("frame", -1)))
	h.complete("pressing Load resumes the saved game on the stage")


# -------------------------------------------------------------- the save slots

## What the save container records, one entry per slot, joined to the movie each
## one names so that "is this room still a room" can be answered.
##
## Found by shape: a save container is one whose fields are numbered families --
## `nof1`..`nof8` beside `gamename1`..`gamename8` -- and the slot count is however
## many of them there are. Nothing here names a title's save file.
func _slots(paths: Paths) -> Array:
	var out: Array = []
	var best: Dictionary = {}
	for relative in paths.containers():
		var resolved := paths.resolve(str(relative))
		if resolved == "":
			continue
		var fields := _fields_of(resolved)
		if fields.is_empty():
			continue
		var count := 0
		while fields.has("nof%d" % (count + 1)) and fields.has("gamename%d" % (count + 1)):
			count += 1
		if count > int(best.get("count", 0)):
			best = {"count": count, "fields": fields, "path": resolved}
	if best.is_empty():
		return out
	var fields: Dictionary = best["fields"]
	for i in range(1, int(best["count"]) + 1):
		var movie := str(fields.get("dorn%d" % i, "")).strip_edges()
		var room := str(fields.get("nof%d" % i, "")).strip_edges()
		var marker := _marker_in(paths, movie, room)
		out.append({
			"slot": i,
			"name": str(fields.get("gamename%d" % i, "")),
			"movie": movie,
			"room": room,
			"frame": int(marker[0]),
			"next_marker": int(marker[1]),
		})
	return out


## Where a room name lands in a movie, as `[frame, the frame the next marker
## starts on]`. `[-1, -1]` when the movie or the marker is not there.
func _marker_in(paths: Paths, movie: String, room: String) -> Array:
	if movie == "" or room == "":
		return [-1, -1]
	var path := paths.resolve(movie)
	if path == "":
		return [-1, -1]
	var file := ContainerFile.new()
	if not file.open(path):
		return [-1, -1]
	var ids: Array = file.ids_of("VWLB")
	var labels := Labels.new()
	var ok: bool = not ids.is_empty() and labels.parse(file.read_chunk(ids[0]))
	file.close()
	if not ok or not labels.labels.has(room.to_lower()):
		return [-1, -1]
	var frame := int(labels.labels[room.to_lower()])
	var next := 1 << 30
	for entry in labels.markers:
		var at := int((entry as Dictionary)["frame"])
		if at > frame and at < next:
			next = at
	return [frame, next]


func _first_loadable(slots: Array) -> int:
	for entry in slots:
		if int((entry as Dictionary)["frame"]) >= 0:
			return int((entry as Dictionary)["slot"])
	return 0


func _report(slots: Array) -> void:
	print("save slots:")
	for entry in slots:
		var slot: Dictionary = entry
		print("  %d  %-14s %-14s %-12s %s" % [
			int(slot["slot"]), JSON.stringify(str(slot["name"])), str(slot["movie"]),
			str(slot["room"]),
			"frame %d" % int(slot["frame"]) if int(slot["frame"]) >= 0
				else "NO SUCH MARKER -- this slot loads to frame 0"])
	print("")


func _fields_of(path: String) -> Dictionary:
	var file := ContainerFile.new()
	if not file.open(path):
		return {}
	var cast := Cast.new()
	var out := {}
	if cast.open(file):
		out = cast.fields()
	file.close()
	return out


# -------------------------------------------------------------------- plumbing

## Which channel's behaviour on the current frame does `needle`. -1 for none.
func _channel_doing(movie: Node, needle: String) -> int:
	var found := _channels_doing(movie, needle)
	return int(found[0]) if not found.is_empty() else -1


func _channels_doing(movie: Node, needle: String) -> Array[int]:
	var out: Array[int] = []
	var index: int = int(movie.call("current_frame"))
	var score: Variant = movie.get("_score")
	if score == null:
		return out
	for channel in range(1, 121):
		var script: Dictionary = movie.call("_sprite_script", channel, index)
		if script.is_empty():
			continue
		if str(script).to_lower().contains(needle.to_lower()):
			out.append(channel)
	return out


## Step until the stage's movie stops being `was`, and report where it arrived:
## `{movie, frame}`, empty when it never left. The frame is read on the step the
## change is first visible, which is the only moment it means "where the `go`
## sent it" -- one step later the room's own score has moved on.
func _land(preview: Node, args: Dictionary, steps: int, was: String) -> Dictionary:
	var out := {}
	for i in steps:
		var window: Node = preview.call("window_at", Vector2(320, 240))
		if Args.flag(args, "real"):
			for tick in 80:
				await process_frame
				var now := str(preview.call("movie_name"))
				if out.is_empty() and now != was:
					out = {"movie": now, "frame": int(preview.call("current_frame"))}
			continue
		preview.call("_advance")
		if window != null and is_instance_valid(window):
			window.call("_advance")
		var name := str(preview.call("movie_name"))
		if out.is_empty() and name != was:
			out = {"movie": name, "frame": int(preview.call("current_frame"))}
	return out


## The eight name fields, by the numbered family the save screen fills.
func _slot_fields(window: Node, count: int) -> Dictionary:
	var out := {}
	for i in range(1, count + 1):
		var value: Variant = window.call("lingo_field", "save%d" % i, "")
		if value != null:
			out[i] = str(value)
	return out


## `.dxr` and `.dir` are one movie, so a slot that recorded one spelling is
## satisfied by the other.
func _same_container(a: String, b: String) -> bool:
	return a.get_file().get_basename().to_lower() == b.get_file().get_basename().to_lower()


## Step the stage. `--real` drives Godot's own process loop instead, so the frame
## clock, the holds and the waits are the ones a player gets; the default steps
## the score directly, which is faster and is what every other harness here does.
func _settle(preview: Node, args: Dictionary, steps: int) -> void:
	for i in steps:
		if Args.flag(args, "real"):
			for tick in 80:
				await process_frame
		else:
			preview.call("_advance")


## The same, for a stage with a window over it, returning the movies the window
## passed through. The window runs its own score, so it has to be stepped too.
func _settle_window(preview: Node, args: Dictionary, steps: int) -> PackedStringArray:
	var seen := PackedStringArray()
	for i in steps:
		var window: Node = preview.call("window_at", Vector2(320, 240))
		_note(seen, window)
		if Args.flag(args, "real"):
			# Sampled per *process* frame, not per outer step. The save screen's
			# trip out to the save container and back is two frames of its own
			# score, so a sample taken once per eighty process frames misses it
			# and reports a round trip that happened as one that did not.
			for tick in 80:
				await process_frame
				_note(seen, preview.call("window_at", Vector2(320, 240)))
			continue
		preview.call("_advance")
		if window != null and is_instance_valid(window):
			window.call("_advance")
	return seen


static func _note(seen: PackedStringArray, window: Node) -> void:
	if window == null or not is_instance_valid(window):
		return
	var name := str(window.call("movie_name"))
	if seen.is_empty() or seen[seen.size() - 1] != name:
		seen.append(name)
