extends SceneTree
## Why a sprite does or does not answer a click.
##
##   godot --headless --script tools/hotspots.gd -- --file PIP2DATA/DAY1.dir --marker shore2
##   godot --headless --script tools/hotspots.gd -- --file PIP2DATA/DAY1.dir --frame 37
##   godot --headless --script tools/hotspots.gd -- --root piposh-dream --file hex1.dir \
##     --do "*+40=ch11;board=wait" --settle 12 --steps 400
##
## "That thing is supposed to be clickable and it isn't" has at least six causes
## and they are indistinguishable from the player's chair: the sprite may not be
## in the frame at all, its member may not resolve, it may have no script that
## declares a mouse handler, it may be a cast type this renderer draws nothing
## for, its ink may make it hit-test per pixel where the artwork is transparent,
## or a higher channel may be eating the click first.
##
## So this reports the whole descent for one frame rather than a verdict: every
## sprite in channel order with its member, its rect, its ink, whether the ink
## hit-tests per pixel, and — the part that usually settles it — **which of
## §4.3's six eligibility clauses fired**, beside what the attached behaviours
## actually declare.
##
## Those last two are different answers and on a D6+ movie they usually disagree,
## which is the thing worth knowing here. From D6 a sprite with any behaviour is
## a click target whatever the behaviour declares, so `D6+ behaviour attached
## [1:207 exitFrame]` is an ordinary and correct line: the sprite absorbs the
## click and the message reaches a script with no handler for it. A sprite that
## looks dead in the game and reads eligible here is that line, and the next
## question is §6.3's chain rather than the hit test.
##
## Reads the real preview node, so what it reports is what the game sees.
##
## ## Two ways in, and the report says which one it took
##
## **Cold** (`--frame` / `--marker`) steps the movie with `_advance` from frame 0
## and pins `_index`. That runs the movie's own flow and **nothing a player
## does**, so any state a click, a keypress or another movie would have set is
## absent — including members a script swaps in. `bugs.md` 105 is what that costs
## when it is not said out loud: on `piposh-dream/hex1.dir` frame 216 this tool
## arrived, printed no caveat, and reported all 58 board channels as the score's
## member `1:56` with no script, concluding "4 of 71 sprites can answer a click"
## — about a board that has three clickable pieces on it once the movie's own init
## has run. That reading was quoted as the state of the frame and cost a session.
## So the cold arm now always prints the caveat, and prints beside it the one
## number that would have shown the difference: how many sprites are displaying a
## member other than the one the score gave them.
##
## **Played in** (`--do`) drives the title with `tools/lib/play_queue.gd` — the
## same queue `tools/scratch/deepplay.gd` takes — and then reports on the frame
## the front movie is actually sitting on, windows included. Nothing jumps: every
## marker is reached by the movie's own `go`, so every destination frame's
## `prepareFrame` runs. A marker jump does not, and that has produced two wrong
## diagnoses in this project already.
##
## `bugs.md` 108 is why the second arm exists at all. Itamar Park's `AntPlay` is
## behind a frame that holds on `play frame the frame` until its own `on keyDown`
## sees the space bar, so a mouse-only walk sits there for ever — measured at 596
## ticks — and the cold arm cannot get there either. The question "is channel 94
## eligible" is this tool's question and this tool could not be pointed at it.
##
## A step that never fired invalidates every step behind it, so the queue's
## `unfired` list is a **failed check** rather than a note: a report about "the
## frame the queue reached" is worthless when the queue did not reach it.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Ink := preload("res://director/director_ink.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")
const PlayQueue := preload("res://tools/lib/play_queue.gd")
const SpriteArt := preload("res://scenes/preview/sprite_art.gd")
const Bitmap := preload("res://director/director_bitmap.gd")


## How many sprites on the frame are showing a member the score did not give them.
##
## The cheapest evidence that the frame's own initialisers ran. It is evidence
## and not proof — a frame whose init sets globals and swaps nothing scores zero
## either way — which is why it is printed beside the caveat rather than used to
## decide whether to print one.
static func _swapped_members(f: Node, sprites: Array) -> int:
	var n := 0
	for raw_value in sprites:
		var raw: Dictionary = raw_value
		var live: Dictionary = f.call("_effective", raw)
		if live.is_empty():
			continue
		if int(live["cast_lib"]) != int(raw["cast_lib"]) \
				or int(live["cast_id"]) != int(raw["cast_id"]):
			n += 1
	return n


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame

	var spec := Args.text(args, "do", "")
	var marker := Args.text(args, "marker", "")
	var frame := Args.number(args, "frame", -1)
	# The node the report is about. In a played-in run that is whichever
	# Movie-In-A-Window is on top, because that is the movie the player's next
	# click would reach; on the cold arm there are no windows to be on top.
	var f: Node = preview
	var provenance := ""
	var caveat := ""

	if spec != "":
		var driver := PlayQueue.new(self, preview, Args.flag(args, "quiet"))
		var run: Dictionary = await driver.run(
			PlayQueue.parse(spec), Args.number(args, "steps", 560),
			Args.number(args, "settle", 25), true)
		f = driver.front()
		var unfired: Array = run["unfired"]
		h.begin("the queue reached the frame this report is about")
		h.check("every step of --do fired", unfired.is_empty(),
			"%d of %d never fired: %s" % [
				unfired.size(), int(run["fired"]) + unfired.size(), str(unfired)])
		h.check("the player was not stopped by quit/halt", not bool(run["stopped"]))
		h.complete("the queue reached the frame this report is about")
		frame = int(f.get("_index"))
		provenance = "played in: %d step(s) over %d tick(s), --do %s" % [
			int(run["fired"]), int(run["steps"]), spec]

	var score = f.get("_score")
	var labels = f.get("_labels")
	if score == null:
		print("no score loaded")
		h.begin("a score was loaded")
		h.check("the front movie has a score", false)
		quit(h.finish("hotspot eligibility on one frame"))
		return

	if spec == "":
		if marker != "" and labels != null:
			for m in labels.markers:
				if str(m["name"]).to_lower() == marker.to_lower():
					frame = int(m["frame"])
					break
			if frame < 0:
				print("no marker '%s'" % marker)
				h.begin("the marker exists")
				h.check("marker '%s' is in the score" % marker, false)
				quit(h.finish("hotspot eligibility on one frame"))
				return
		if frame < 0:
			frame = 0

		# Step the movie to that frame so puppet state and scripts are as they would
		# be in play, rather than as they are on a cold score read.
		var arrived := false
		for i in 400:
			if int(f.call("current_frame")) == frame:
				arrived = true
				break
			f.call("_advance")

		# **The playhead does not always get there, and the report has to be about
		# the frame it names anyway.** `_advance` follows the movie's own flow, so a
		# room that holds on a `go to the frame` never reaches a marker further on --
		# `BATZEGOZ.dir`'s `Egoz1` is frame 194 and 400 steps stop short of it.
		#
		# That silently made this tool wrong rather than incomplete, and the wrongness
		# was quoted as evidence. Everything derived from the *score* was read at
		# `frame` (the sprite list, `_sprite_script(channel, frame)`) while
		# `_responds_to_mouse` read `_index`, wherever the playhead had stopped -- so
		# the three dialogue options at `Egoz1` printed "behaviour declares no mouse
		# handler" **next to a behaviour that declares `mouseUp`**, and that line went
		# into `ENGINE_TODO.md` as the measurement of a missing eligibility clause. The
		# clause was missing; this frame was never the proof of it.
		#
		# Pinned rather than reported-and-left, because a report whose columns
		# disagree about which frame they describe is worse than one with stale
		# puppet state.
		f._index = frame
		provenance = "cold: %d `_advance` step(s) from frame 0%s" % [
			frame, "" if arrived else ", WHICH STOPPED SHORT"]
		# **Always, not only when the walk stopped short.** `bugs.md` 105: the
		# dangerous run is the one that arrives. `_advance` runs the score and the
		# frame scripts and nothing else, so an init a click or another movie would
		# have run has not run, and every column below then describes the score
		# rather than the game.
		caveat = ("this is a COLD read: `_advance` ran the movie's own flow and"
			+ " nothing a player does, so any member a script would have swapped in,"
			+ " any puppet a click would have set and any global another movie would"
			+ " have written is absent. Use --do to play into this frame.")
		if not arrived:
			caveat += (" The playhead also stopped short of frame %d: the score is"
				+ " read there and any puppet state is from where it stopped.") % frame

	print("%s frame %d%s" % [
		str(f.call("movie_name")), frame,
		("  (marker %s)" % marker) if marker != "" else "",
	])
	print("how this frame was reached: %s" % provenance)
	var sprites: Array = score.frame(frame).get("sprites", [])
	print("%d of %d sprite(s) show a member the score did not give them" % [
		_swapped_members(f, sprites), sprites.size()])
	if caveat != "":
		print("!! %s" % caveat)
	print("")
	print("ch    member   rect                     ink  hit    responds  why")

	var eligible := 0
	var classified := 0
	var table = f.get("_table")
	for s_value in sprites:
		var raw: Dictionary = s_value
		var sprite: Dictionary = f.call("_effective", raw)
		if sprite.is_empty():
			print("%-5d %-8s %-24s  %-4s %-6s %-9s %s" % [
				int(raw["channel"]), "%d:%d" % [int(raw["cast_lib"]), int(raw["cast_id"])],
				"-", "-", "-", "no", "hidden by a script",
			])
			classified += 1
			continue
		var channel := int(sprite["channel"])
		var ink := int(sprite["ink"])
		# The cast type decides how a click is tested as much as the ink does: a
		# matte is flooded in from the border of a *bitmap's* image, and a shape
		# has none, so a matte-inked shape is a rectangle. Reporting it as "pixel"
		# would send the next reader looking for artwork that does not exist.
		var member_type: int = int(table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"])).get("type", 0))
		var rect: Rect2 = f.call("_stage_rect", sprite)
		# The clause, not a boolean. §4.3 is six clauses tested in order and which
		# one fired is the whole of what the reader came for -- "YES" alone sends
		# them to read the predicate, and on a D6+ movie the answer is nearly
		# always the *fourth* clause, which is the one nobody expects because it
		# ignores what the behaviour declares. Asked of the engine's own function
		# so that this cannot drift from what the hit test does.
		var why: String = Interaction.eligibility_reason(f, sprite, table)
		var responds := why != ""
		classified += 1
		if responds:
			eligible += 1
		else:
			var behaviour: Dictionary = f.call("_sprite_script", channel, frame)
			var member_script: Dictionary = f.call(
				"_script_for_member", int(sprite["cast_id"])
			)
			why = "no behaviour" if behaviour.is_empty() else "behaviour declares no mouse handler"
			if not member_script.is_empty():
				why += ", member script declares none"
		# What the behaviour actually declares, beside the verdict. From D6 the
		# sprite is a click target whatever that is, so the two answers come
		# apart routinely -- and when they do, "eligible, declares exitFrame" is
		# the line that explains why a click on it runs nothing: the message
		# reaches a script with no handler for it, and §6.3's chain is what
		# decides whether the tiers below still get a turn.
		var attached: Array = Interaction.behaviour_intervals(f, channel, frame)
		var declares := PackedStringArray()
		for value in attached:
			var interval: Dictionary = value
			var script: Dictionary = f.call("_script_in_lib",
				int(interval["script_cast_lib"]), int(interval["script_member"]))
			if script.is_empty():
				declares.append("%d:%d unresolved" % [
					int(interval["script_cast_lib"]), int(interval["script_member"])])
				continue
			var names := PackedStringArray()
			for handler in script.get("handlers", []):
				names.append(str((handler as Dictionary).get("name", "")))
			if not (script.get("body", []) as Array).is_empty():
				names.append("<generic body>")
			declares.append("%d:%d %s" % [
				int(interval["script_cast_lib"]), int(interval["script_member"]),
				"/".join(names) if names.size() > 0 else "nothing"])
		if declares.size() > 0:
			why += "%s[%s]" % ["  " if why != "" else "", ", ".join(declares)]
		print("%-5d %-8s %-24s  %-4d %-6s %-9s %s" % [
			channel, "%d:%d" % [int(sprite["cast_lib"]), int(sprite["cast_id"])],
			"(%d,%d) %dx%d" % [
				int(rect.position.x), int(rect.position.y),
				int(rect.size.x), int(rect.size.y),
			],
			ink, "pixel" if Ink.hits_per_pixel(ink, member_type) else "rect",
			"YES" if responds else "no", why,
		])

	print("")
	print("%d of %d sprites can answer a click" % [eligible, sprites.size()])

	# What the descent actually answers at a point, which is a different question
	# from "is this sprite eligible" and the one a dead hotspot is usually about:
	# a higher channel that is eligible takes the click first.
	var probe := Args.text(args, "at", "")
	if probe != "":
		for point in probe.split(" ", false):
			var bits := str(point).split(",")
			if bits.size() != 2:
				continue
			var at := Vector2(int(bits[0]), int(bits[1]))
			var took: int = f.call("_channel_at", at)
			print("(%d,%d) -> channel %d%s" % [at.x, at.y, took,
				"" if took > 0 else "  (nothing eligible under the point)"])
			# Every sprite whose rect contains the point, top down, with its
			# verdict. "Nothing answers here" and "something above it answered"
			# look identical from the chair and are different bugs.
			for i in range(sprites.size() - 1, -1, -1):
				var raw: Dictionary = sprites[i]
				var live: Dictionary = f.call("_effective", raw)
				if live.is_empty():
					continue
				if not f.call("_sprite_rect", live).has_point(at):
					continue
				var member: Dictionary = table.get_member(
					int(live["cast_lib"]), int(live["cast_id"]))
				var per_pixel: bool = Ink.hits_per_pixel(
					int(live["ink"]), int(member.get("type", 0)))
				var opaque: bool = (not per_pixel) or bool(f.call("_opaque_at", live, at))
				var reason: String = Interaction.eligibility_reason(f, live, table)
				print("    over ch%-4d %d:%-4d %-16s %s  %s" % [
					int(live["channel"]), int(live["cast_lib"]), int(live["cast_id"]),
					str(member.get("name", "?")),
					"opaque" if opaque else "TRANSPARENT HERE",
					reason if reason != "" else "not eligible"])

	# The matte's own picture of itself. `--opaque <ch>` samples `_opaque_at` over
	# the channel's whole rect and prints the map, because "the ink hit-tests per
	# pixel" and "there is no pixel anywhere in this sprite" are the two halves of
	# the same line and only the second is a bug. A Matte sprite that is
	# transparent at the point the player aimed at is authentic; one that is
	# transparent at **every** point is a hit test reading the wrong image, and no
	# number of single-point probes distinguishes them.
	var opaque_channel := Args.number(args, "opaque", 0)
	if opaque_channel > 0:
		for s_value in sprites:
			var raw: Dictionary = s_value
			if int(raw["channel"]) != opaque_channel:
				continue
			var live: Dictionary = f.call("_effective", raw)
			if live.is_empty():
				print("ch%d is hidden by a script" % opaque_channel)
				break
			var member: Dictionary = table.get_member(
				int(live["cast_lib"]), int(live["cast_id"]))
			var box: Rect2 = f.call("_sprite_rect", live)
			print("")
			print("ch%d %d:%d %s  ink %d  rect (%d,%d) %dx%d  hit %s" % [
				opaque_channel, int(live["cast_lib"]), int(live["cast_id"]),
				str(member.get("name", "?")), int(live["ink"]),
				int(box.position.x), int(box.position.y),
				int(box.size.x), int(box.size.y),
				"per pixel" if Ink.hits_per_pixel(
					int(live["ink"]), int(member.get("type", 0))) else "whole rect"])
			# **"No pixel here" and "no picture at all" are different findings.**
			# `_opaque_at` answers false for both -- it returns false when
			# `_texture_for` hands back null -- so a member whose artwork does not
			# decode reads as a fully transparent matte, and the reader goes looking
			# for a flood-fill bug in a sprite that has no image to flood.
			var texture: Texture2D = f.call("_texture_for", live)
			var hit_images = f.get("_hit_images")
			var cached := 0
			if hit_images != null:
				for k in (hit_images as Dictionary).keys():
					if str(k).begins_with("%d:%d" % [
							int(live["cast_lib"]), int(live["cast_id"])]):
						cached += 1
			print("   member: type %d (%s) %s  %dx%d  reg (%d,%d)  keys %s" % [
				int(member.get("type", 0)), str(member.get("type_name", "?")),
				str(member.get("name", "?")),
				int(member.get("width", 0)), int(member.get("height", 0)),
				int(member.get("reg_x", 0)), int(member.get("reg_y", 0)),
				str(member.keys())])
			print("   texture: %s   hit image(s) cached for this member: %d" % [
				"%dx%d" % [texture.get_width(), texture.get_height()] \
					if texture != null else "NONE (the artwork did not decode)",
				cached])
			if texture == null:
				# There are two reasons for null and only one of them is a bug:
				# a member type this renderer draws nothing for is correct
				# behaviour (`sprite_art.gd:decline_reason`), and a bitmap that
				# will not decode is not. Say which, and for the second say what
				# the decoder said, because "no picture" with no error line is
				# where a decode bug hides behind a hit-test one.
				var declined: String = SpriteArt.decline_reason(live, table)
				if declined != "":
					print("   declined: %s -- correct, not a decode failure" % declined)
				else:
					var container = table.file_for(int(live["cast_lib"]))
					var chunk_id := int(member.get("data_chunk_id", -1))
					var chunk: PackedByteArray = PackedByteArray() if container == null \
						else container.read_chunk(chunk_id)
					var errors: Array = []
					var raw_image: Image = Bitmap.decode(
						member, chunk, f.get("_palette"), errors)
					print("   cast lib %d (%s) -> %s%s" % [
						int(live["cast_lib"]), str(member.get("cast_lib_name", "?")),
						"NO CONTAINER" if container == null else str(container.path),
						"" if container == null or str(container.error) == "" \
							else "   read error: " + str(container.error)])
					print("   decode: chunk %d, %d byte(s) -> %s   %s" % [
						chunk_id, chunk.size(),
						"NULL" if raw_image == null else "%dx%d" % [
							raw_image.get_width(), raw_image.get_height()],
						str(errors)])
					# **The same chunk id, read out of the movie the library is
					# embedded in.** A cast library with no file path of its own is
					# a *second cast inside this container* -- `cast_libs[n].path`
					# is empty and `resolved_path` is the movie's own file -- so if
					# the movie has the bytes and `file_for` handed back nothing,
					# the member is fine and the container lookup is what failed.
					# Reading it here rather than fixing it here, because the
					# lookup is `director/`'s and this is a tool.
					var entry: Dictionary = table.cast_libs.get(
						int(live["cast_lib"]), {})
					var own = f.get("_movie")
					if own != null and container == null:
						var direct: PackedByteArray = own.read_chunk(chunk_id)
						var errors2: Array = []
						var image2: Image = Bitmap.decode(
							member, direct, f.get("_palette"), errors2)
						print("   library entry: %s" % str(entry))
						print("   same chunk read from %s: %d byte(s) -> %s   %s" % [
							str(own.path).get_file(), direct.size(),
							"NULL" if image2 == null else "%dx%d" % [
								image2.get_width(), image2.get_height()],
							str(errors2)])
			var hits := 0
			var total := 0
			var rows := PackedStringArray()
			var step := maxi(1, int(box.size.x / 60.0))
			var row_step := maxi(1, int(box.size.y / 30.0))
			var y := box.position.y
			while y < box.end.y:
				var row := ""
				var x := box.position.x
				while x < box.end.x:
					total += 1
					var on: bool = f.call("_opaque_at", live, Vector2(x, y))
					if on:
						hits += 1
					row += "#" if on else "."
					x += step
				rows.append(row)
				y += row_step
			for row in rows:
				print("   %s" % row)
			print("%d of %d sampled point(s) are opaque" % [hits, total])
			break

	# Deliberately not "at least one sprite must be clickable". That is not a
	# property of Director and it is not true of real frames: MAP's frame 0 holds
	# a backdrop, a panel and one off-stage sprite, and none of them has a
	# behaviour, because the map's regions arrive a few frames later. A tool that
	# failed on that would be teaching the wrong lesson. What is worth asserting
	# is that every sprite got a verdict rather than being skipped.
	h.begin("every sprite on the frame was classified")
	h.check("no sprite was skipped", classified == sprites.size(),
		"%d of %d" % [classified, sprites.size()])
	h.complete("every sprite on the frame was classified")
	quit(h.finish("hotspot eligibility on one frame"))
