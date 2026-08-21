extends SceneTree
## Stand one container on one frame, press what you name, and photograph it.
##
##   godot --path . --script tools/scene_probe.gd -- --root piposh \
##       --movie PIANO.dir --marker playpiano --out /tmp/playpiano.png
##   godot --path . --script tools/scene_probe.gd -- --root piposh \
##       --movie PIANO.dir --marker listenpiano --clicks "ch12;ch13" \
##       --out /tmp/song.png
##
##   --movie C       container to `go to movie`, resolved the way the game does
##   --marker M      where to stand (`--frame N` for a frame number instead)
##   --clicks LIST   `;`-separated presses, each `x,y` in stage pixels or `chN`
##                   for the centre of whatever channel N is drawing
##   --settle N      process frames after each step (default 8)
##   --ticks N       process frames after the last press, before the photo (24)
##   --out PATH      where the PNG goes; omit for the channel table alone
##   --hold          stop the playhead once it arrives, so the frame photographed
##                   is the frame named. Without it the score runs on through the
##                   settle and the ticks.
##   --stage W,H     size the window to the stage, so one photo pixel is one
##                   stage pixel and a crop can be read against the score's own
##                   coordinates. `project.godot` opens maximized, and a shot
##                   scaled by 3.54 cannot be compared with a member's bitmap.
##
##                   **Only an integer scale is comparable, and the window size
##                   that gives one is not the stage size.** The stage takes 75%
##                   of the window's width, so 854x640 yields 641x480 -- a
##                   *fractional* 1.0016 -- and comparing that against a 640x480
##                   render reports 38% of the stage differing, all of it the
##                   capture. `1707,1280` yields exactly 1280x960, scale 2.000;
##                   sample the top-left of each 2x2 block. Check the content
##                   bounding box before trusting any pixel comparison.
##   --fields LIST   `,`-separated field member names to read back through the
##                   same path Lingo uses (`field "x"`), after the presses
##   --fields-per-click
##                   read those fields after *each* press as well, naming the
##                   press each reading followed, so a change can be attributed
##                   to the click that caused it
##   --channels-per-click
##                   the same for the drawn channel table: what every channel
##                   holds after each press, and which channels moved. The other
##                   reading of the same state, and independent of `--fields`
##   --quiet         skip the channel table
##
## ## Why this exists
##
## `AGENTS.md` has said for some time that "there is no general 'where did the
## playhead go' probe right now", that the retired `tools/probe.gd` was deleted
## with the renderer it drove, and that rebuilding one on the preview is the
## single most useful tool this repo is missing. This is that, at the size the
## bug in front of it needed rather than at the size of the paragraph.
##
## The three existing views each stop one step short of a room you have to *play*
## to reach. `liveness_sweep` opens every container and asks whether the playhead
## can leave; `qa_walk` photographs what a player reaches but only what its
## budget reaches; `click_trace` explains one click and prints no pixels.
## Nothing lets you say "stand on `playpiano`, press two keys, and let me look at
## it" -- which is the question every wrong-picture report turns into.
##
## **The photograph is the point, so this does not run headless.** Headless Godot
## has a dummy texture storage and never paints, so `Snapshot.grab` would hand
## back null and this would write nothing while looking like it worked.
## `qa_walk` documents the same trap. Run it windowed; it says so and exits if
## you do not.
##
## **`director_render.gd` is not a second opinion about the same picture.** It is
## a separate compositor that skips field members outright -- it prints
## `skipped (field)` and moves on -- so a field drawn wrongly by the player is
## invisible to it. Anything about text on the stage has to come from here, off
## the real preview, or it is a measurement of the wrong renderer.
##
## ## Why `--fields-per-click` is not the same question as `--fields`
##
## `--fields` reads once, at the end, which says where a movie's state *ended up*
## and nothing about which input put it there. For a movie that keeps its state
## in a field that is enough only when the opening state is known, and the
## interesting ones randomise it: `piposh-dream/puzzle.dir` holds its whole 4x4
## board in `field "pazel"` and `1:2` shuffles it on entry, so an end-of-run read
## cannot tell a click that moved a tile from a different shuffle. Start-against-
## end does not close it either -- a sequence of legal sliding-tile moves can
## return the board to its opening position, which `tools/puzzle_board.gd` first
## reported as "the clicks never arrived" after eight moves that each worked.
##
## Reading a movie's own state field against the channel table beside it is the
## cheapest bug this project has found: `docs/bugs-closed.md` 120 is exactly that
## disagreement, and the sweep criterion it belongs to -- "input changes something
## a control run does not" -- is unanswerable without a per-press reading.
##
## **The sample is indexed by position in `--clicks`, not by presses that
## landed.** `_point` skips a `chN` that is drawing nothing, and numbering only
## the presses that landed would shift every later attribution by one, which is
## the one thing the click identity exists to prevent. A skipped position gets a
## row saying no sample was taken.
##
## Title-agnostic: nothing here knows what a game or a room is called.

const Args := preload("res://tools/lib/args.gd")
const Snapshot := preload("res://scenes/preview/snapshot.gd")


func _init() -> void:
	var args := Args.parse()
	if DisplayServer.get_name() == "headless":
		print("scene_probe paints, so it cannot run headless -- drop --headless")
		quit(1)
		return

	var stage := Args.text(args, "stage", "").split(",", false)
	if stage.size() == 2:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(stage[0]), int(stage[1])))

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var settle := Args.number(args, "settle", 8)
	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
		# A movie change is entered by the ticks after the call, not by the call:
		# `prepareMovie`/`startMovie` and the first frame's own scripts run then.
		for i in settle:
			await process_frame

	if preview.get("_score") == null:
		print("no score loaded")
		quit(1)
		return

	var frame := _target_frame(preview, args)
	if frame < 0:
		quit(1)
		return
	if frame != int(preview.call("current_frame")):
		# Entered, not merely indexed. A frame nobody stood on has run no
		# `enterFrame`, so its sprites carry the previous frame's puppet state.
		preview.set("_index", frame)
		for i in settle:
			await process_frame

	# Read once here rather than per press: `Args` is a parse of the command line
	# and nothing in the loop can change it, and the fields have to be sampled
	# before the first press for click 1's row to mean anything.
	var watched := Args.text(args, "fields", "").split(",", false)
	var per_click := Args.flag(args, "fields-per-click") and watched.size() > 0
	var per_channel := Args.flag(args, "channels-per-click")
	var seen: Dictionary = {}
	var table_seen: Dictionary = {}
	if per_click:
		print("per-click fields (%d): sampled after every press in --clicks"
			% watched.size())
		_sample(preview, watched, seen, 0, "-- before any press --")
	if per_channel:
		print("per-click channels: what every drawn channel holds, after every press")
		_sample_channels(preview, table_seen, 0, "-- before any press --")

	var position := 0
	var landed := 0
	var moved: Dictionary = {}
	var table_moved := 0
	for press in Args.text(args, "clicks", "").split(";", false):
		position += 1
		var found: Variant = _point(preview, str(press))
		if found == null:
			if per_click or per_channel:
				print("sample %-2d  %-28s  no press, so no sample" % [
					position, str(press).strip_edges()])
			continue
		var at: Vector2 = found
		# Read *before* the press: a handler that `go`es somewhere leaves a
		# different sprite under the same point, so asking afterwards would name
		# the wrong thing as the cause.
		var under := ""
		if per_click or per_channel:
			under = _under(preview, str(press), at)
		print("press (%d,%d)" % [int(at.x), int(at.y)])
		preview.call("route_press", at)
		preview.call("route_release", at)
		for i in settle:
			await process_frame
		# After the settle, not before it: a mouse handler that `go`es somewhere
		# has not run its destination's scripts until the frames after the press.
		if per_click:
			for name in _sample(preview, watched, seen, position, under):
				moved[name] = int(moved.get(name, 0)) + 1
		if per_channel:
			if _sample_channels(preview, table_seen, position, under) > 0:
				table_moved += 1
		if per_click or per_channel:
			landed += 1

	# Summarised here rather than at the end, because it is a statement about the
	# click loop and the trailing ticks are not part of it. `landed` and
	# `position` are printed separately on purpose: they differ exactly when a
	# `chN` was drawing nothing, and a reader who does not know that cannot tell
	# a click that changed nothing from a click that never happened.
	if per_click:
		for name in watched:
			print("per-click %s : changed after %d of %d press(es) that landed, of %d asked for" % [
				JSON.stringify(str(name).strip_edges()),
				int(moved.get(str(name).strip_edges(), 0)), landed, position])
	if per_channel:
		print("per-click channels : moved after %d of %d press(es) that landed, of %d asked for" % [
			table_moved, landed, position])

	for i in Args.number(args, "ticks", 24):
		await process_frame

	# Held *after* the presses and the ticks, not before: a press has to be able
	# to move the playhead, and `--hold` is about the photograph being of the
	# frame this reports rather than of wherever the score got to while the
	# viewport was being read.
	if Args.flag(args, "hold"):
		preview.set("_paused", true)
		await process_frame

	print("%s  frame %d of %d" % [
		str(preview.call("movie_name")), int(preview.call("current_frame")),
		int(preview.get("_score").frame_count),
	])
	if not Args.flag(args, "quiet"):
		_table(preview)

	# Read through `lingo_field`, not off the cast record: a script asking
	# `field "x"` goes through here, and a member that holds text while this
	# answers "" is the difference between a working branch and a dead one.
	if Args.text(args, "fields", "") != "":
		var overrides: Dictionary = preview.get("_field_text")
		print("field overrides held: %d  %s" % [
			overrides.size(), JSON.stringify(overrides).substr(0, 400)])
	for name in Args.text(args, "fields", "").split(",", false):
		var text: String = str(preview.call("lingo_field", str(name), ""))
		var where: Array = preview.call("_resolve_field", str(name))
		var stored := ""
		if not where.is_empty():
			stored = str(preview.get("_table").get_member(
				int(where[0]), int(where[1])).get("text", ""))
		print("field %-10s : resolves to %-10s  member text %d char(s)  lingo reads %d char(s)  %s" % [
			JSON.stringify(str(name)), str(where), stored.length(), text.length(),
			JSON.stringify(text.substr(0, 40)),
		])

	var out := Args.text(args, "out", "")
	if out != "":
		var image: Image = Snapshot.grab(preview)
		if image == null:
			print("the display server returned no pixels")
			quit(1)
			return
		image.save_png(out)
		print("wrote %s  (%dx%d)" % [out, image.get_width(), image.get_height()])
	quit(0)


## One row per watched field, and the names of the ones that moved since the last
## sample.
##
## Read through `lingo_field` for the same reason the end-of-run block does: a
## script's own `field "x"` goes through there, and the cast record is a different
## question. The value is printed as well as the verdict, because "changed" alone
## cannot be checked against anything and a field that changes *back* looks
## identical to one that never moved.
##
## `where` is what the press was, and it is on every row rather than in a header:
## a reader grepping one field's rows out of a long run has to be able to see
## which press each reading followed.
func _sample(preview: Node, names: PackedStringArray, seen: Dictionary,
		position: int, where: String) -> Array[String]:
	var changed: Array[String] = []
	for raw in names:
		var name := str(raw).strip_edges()
		var text := str(preview.call("lingo_field", name, ""))
		var state := "first read"
		if seen.has(name):
			state = "changed" if str(seen[name]) != text else "same"
			if state == "changed":
				changed.append(name)
		seen[name] = text
		print("sample %-2d  %-28s  %-14s %-10s %4d char(s)  %s" % [
			position, where, JSON.stringify(name), state, text.length(),
			JSON.stringify(_flat(text).substr(0, 120)),
		])
	return changed


## The other reading of the same truth: what every drawn channel is holding, and
## what moved since the last sample. Returns how many channels moved.
##
## **This is not a check that the field and the channels agree**, and the
## distinction matters because agreement is the more valuable question and this
## cannot answer it. Agreement needs a mapping from a field's cells to channels
## and to member names -- `puzzle.dir`'s is "the grid in reading order, channels
## 1..16, member `paz<item>`, `x` is the hole", which `tools/puzzle_board.gd`
## carries because it is about that movie. Nothing general can know it, and an
## engine tool may not: `AGENTS.md`'s rule is that no per-title mapping belongs in
## engine code, and a probe that took one on the command line would be a small
## language for expressing one movie's board.
##
## What it does answer is the *shape* of a disagreement, which needs no mapping:
## two independent readings of one state, each reported as moved or not, per
## press. `docs/bugs-closed.md` 120 is a "the field is right and the channels
## reverted" — so a press where the field moved and the drawn table did not, or
## the reverse, is the signature, and it is visible here without this tool knowing
## what a tile is.
func _sample_channels(preview: Node, store: Dictionary, position: int,
		where: String) -> int:
	var now := _members_drawn(preview)
	if not store.has("last"):
		store["last"] = now
		print("channel %-2d %-28s  %d drawn, first read" % [
			position, where, now.size()])
		return 0
	var was: Dictionary = store["last"]
	store["last"] = now
	var moved: Array[String] = []
	for channel in now:
		if not was.has(channel):
			moved.append("+ch%d %s" % [channel, str(now[channel])])
		elif str(was[channel]) != str(now[channel]):
			moved.append("ch%d %s->%s" % [
				channel, str(was[channel]), str(now[channel])])
	for channel in was:
		if not now.has(channel):
			moved.append("-ch%d %s" % [channel, str(was[channel])])
	var what := "unchanged"
	if not moved.is_empty():
		what = "%d moved: %s" % [moved.size(), " ".join(moved.slice(0, 6))]
	print("channel %-2d %-28s  %d drawn, %s" % [
		position, where, now.size(), what])
	return moved.size()


## Channel -> the member it is drawing, named. The channels the frame does not
## offer are absent rather than blank, which is the reading `puzzle_board.gd`
## documents: a hidden sprite leaves `_effective` altogether, so "not drawn" and
## "drawn as something else" are different answers and both are wanted here.
func _members_drawn(preview: Node) -> Dictionary:
	var table = preview.get("_table")
	var out: Dictionary = {}
	for value in _drawn(preview):
		var sprite: Dictionary = value
		var member: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var name := str(member.get("name", ""))
		if name.is_empty():
			name = "%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])]
		out[int(sprite["channel"])] = name
	return out


## A field's text on one line, because a board is four lines and a probe's row is
## one. `/` rather than a space so an empty line is still visible as a gap.
func _flat(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", " / ")


## What the press was aimed at, named so a reader can tell one press from another.
##
## The member *name* is the load-bearing half. On a board the movie shuffles on
## entry, `ch7` names a different tile every run, so a row saying only `ch7`
## cannot be read as cause and effect.
##
## **A `chN` press reports channel N, not a hit test**, and the difference is not
## academic: `puzzle.dir` draws a 349x89 decoration in channel 24 across the top
## of its board, so the topmost drawn sprite containing a tile's own centre is
## that decoration and every row of a sixteen-press run named it instead of the
## tile. `chN` already says which channel was meant -- `_point` took its centre
## from that channel -- so the hit test answers a question nobody asked. It is
## kept for an `x,y` press, where nothing else says what was hit, and the row
## says which of the two readings it is.
func _under(preview: Node, press: String, at: Vector2) -> String:
	var table = preview.get("_table")
	var text := press.strip_edges()
	var wanted := -1
	if text.to_lower().begins_with("ch"):
		wanted = int(text.substr(2))
	var best := ""
	var top := -1
	for value in _drawn(preview):
		var sprite: Dictionary = value
		var channel := int(sprite["channel"])
		if wanted >= 0 and channel != wanted:
			continue
		if wanted < 0:
			if channel <= top:
				continue
			if not (preview.call("_stage_rect", sprite) as Rect2).has_point(at):
				continue
		var member: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var name := str(member.get("name", ""))
		if name.is_empty():
			name = "%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])]
		top = channel
		if wanted >= 0:
			best = "ch%d %s" % [channel, name]
		else:
			best = "(%d,%d) hits ch%d %s" % [
				int(at.x), int(at.y), channel, name]
	if best == "":
		if wanted >= 0:
			return "%s drawing nothing" % text
		return "(%d,%d) hits nothing" % [int(at.x), int(at.y)]
	return best


## The frame `--marker` or `--frame` names, or the one already playing.
func _target_frame(preview: Node, args: Dictionary) -> int:
	var marker := Args.text(args, "marker", "")
	if marker == "":
		return Args.number(args, "frame", int(preview.call("current_frame")))
	var labels = preview.get("_labels")
	if labels != null:
		for m in labels.markers:
			if str((m as Dictionary)["name"]).to_lower() == marker.to_lower():
				return int((m as Dictionary)["frame"])
	print("no marker '%s' in %s" % [marker, str(preview.call("movie_name"))])
	return -1


## `x,y` as written, or `chN` as the centre of what channel N is drawing now.
func _point(preview: Node, press: String) -> Variant:
	var text := press.strip_edges()
	if text.to_lower().begins_with("ch"):
		var channel := int(text.substr(2))
		for value in _drawn(preview):
			var sprite: Dictionary = value
			if int(sprite["channel"]) == channel:
				var rect: Rect2 = preview.call("_stage_rect", sprite)
				return rect.position + rect.size * 0.5
		print("channel %d is drawing nothing here" % channel)
		return null
	var parts := text.split(",", false)
	if parts.size() != 2:
		print("cannot read a press from '%s'" % text)
		return null
	return Vector2(int(parts[0]), int(parts[1]))


## Every sprite the frame draws, after the scripts have had their say.
func _drawn(preview: Node) -> Array:
	var out: Array = []
	var score = preview.get("_score")
	var frame := int(preview.call("current_frame"))
	for value in (score.frame(frame).get("sprites", []) as Array):
		var sprite: Dictionary = preview.call("_effective", value as Dictionary)
		if not sprite.is_empty():
			out.append(sprite)
	return out


## What is on the stage, with the member's own size beside the rect it is drawn
## at -- because "drawn smaller than itself" is what a squashed picture is, and
## the two numbers side by side is the only way to see it.
func _table(preview: Node) -> void:
	var table = preview.get("_table")
	print("chan   member    name             natural    drawn rect")
	for value in _drawn(preview):
		var sprite: Dictionary = value
		var member: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		var rect: Rect2 = preview.call("_stage_rect", sprite)
		var natural := "-"
		if int(member.get("width", 0)) > 0:
			natural = "%dx%d" % [int(member["width"]), int(member["height"])]
		var flag := ""
		if int(member.get("width", 0)) > 0 and (
				int(rect.size.x) != int(member["width"])
				or int(rect.size.y) != int(member["height"])):
			flag = "   <- drawn %.2fx by %.2fx" % [
				rect.size.x / float(member["width"]),
				rect.size.y / float(member["height"]),
			]
		print("ch%-5d %-9s %-16s %-10s (%d,%d %dx%d)%s" % [
			int(sprite["channel"]),
			"%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])],
			str(member.get("name", "")), natural,
			int(rect.position.x), int(rect.position.y),
			int(rect.size.x), int(rect.size.y), flag,
		])
