extends SceneTree
## A **real** wait-for-sound tempo cell holds the playhead, and the sound ending
## releases it.
##
##   godot --headless --audio-driver Dummy --path . --script tools/sound_tempo_wait.gd -- \
##       --root rating --boot mainmenu.dir
##   godot --headless --audio-driver Dummy --path . --script tools/sound_tempo_wait.gd -- \
##       --root rating --boot mainmenu.dir --movie BATZROOM.dir --frame 110
##
## A tempo cell of 255 or 254 is not a frame rate. It is "hold this frame until
## the sound in channel 1 (or 2) finishes", and it is the one tempo arm whose
## release comes from outside the clock entirely — from the audio device, through
## `preview/sound.gd:pump`. `director_score.gd:tempo_waits` decodes it,
## `director_frame_clock.gd:_arm_waits` arms it, `playhead_held()` reports it and
## `frame_loop.gd:tick` is where it actually stops the score.
##
## **All of that was implemented and none of it was tested against a tempo cell
## from a container.** `bugs.md` 115. Every harness that exercised the arm used
## bytes it wrote itself: `frame_events.gd` fabricates `{"tempo": 255,
## "tempo_cue": -1}` and hands it to a bare clock, `movie_tempo.gd` checks that
## 255 names no *rate* and says in as many words that the holds are out of its
## scope, and `sound_wait.gd` — the entry whose name suggests otherwise — never
## touches the tempo channel at all; it is about the `soundBusy` poll idiom and
## talks only to `AudioDirector`. All three run against `GATE_ROOT`, and
## **`piposh2` has zero frames with such a cell**, so pointing any of them at this
## subject would have asserted over an empty set.
##
## `rating` has **276**: 259 cells of tempo 255 and 17 of tempo 254, spread over
## 81 containers, every one of them with the operand −2 ("wait for the end of the
## sound" rather than for a cue point). That is what this drives, and it finds one
## by walking the corpus rather than by naming a movie, so the same entry is
## meaningful on any title that ships one.
##
## ## What it asserts, and why each is needed
##
##   1. the corpus holds such a cell at all, and the score decodes it to the
##      channel the byte names. Without this the run is vacuous and the two below
##      would pass on a movie that simply has nothing to say.
##   2. **landing on that frame arms the clock** — `waiting_sound()` names the
##      channel and `hold_reason()` says so. This is the decode reaching the
##      clock, which is the join `frame_events` proves on a synthetic cell.
##   3. **with a sound playing, the playhead does not move**, over enough real
##      awaited frames that it would have stepped several times at any tempo.
##   4. **the sound ending releases it and the playhead moves on.**
##   5. **the same frame with a silent channel does not hold at all.** This is the
##      control, and it is the check that makes 3 mean anything: a playhead that
##      is stuck for some other reason would satisfy 3 and 4 is the only thing
##      that would catch it, so this catches the reverse — a "hold" that is really
##      the movie having nowhere to go.
##
## Real frames throughout, awaited rather than pumped: a synthetic tick loop
## advances the runtime's clock and not the audio server's, so `soundBusy` never
## goes false and this harness would report a hold that was really a dead
## channel (AGENTS.md, and `bugs.md` 22 twice).
##
## Title-agnostic. It names no movie, no marker and no sound file; the cell, the
## container and the audio are all discovered from whatever `--root` points at.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")

## Tempo cells that mean "wait for the sound in this channel".
const WAIT_SOUND := {255: 1, 254: 2}
## Frames to await while asserting the playhead has *not* moved.
##
## Deliberately far more than a step takes. Measured on this machine, a `rating`
## movie with nothing holding it steps roughly once every three awaited frames --
## the control below moved 9 times in 30 -- so 300 is two orders of magnitude over
## what a missing hold needs to show itself, and it costs a fraction of a second
## headless. A fixed count tuned to *one* machine's ratio is the `play_suspends`
## flake (`bugs.md` 41): the assertion below waits on the condition and this is
## only its ceiling.
const HOLD_FRAMES := 300
## ... and the ceiling for the two assertions that wait for the playhead to move.
## Generous for the same reason and in the other direction: a slow runner that
## fitted no score tick into the window would otherwise read as a hold.
const MOVE_FRAMES := 900
## Frames to await for a `go` to land. The jump is queued and taken on the next
## tick; the rest is slack for a movie whose `enterFrame` does work.
const ARRIVE_FRAMES := 60
## An audio file smaller than this is a click, and a click can end inside the
## hold window and release the wait the harness is trying to observe.
const LONG_ENOUGH_BYTES := 120000


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()

	var paths := Paths.new()
	paths.load_config()
	var root := str(paths.root)

	# --------------------------------------------------------------- the cell
	h.begin("the corpus holds a wait-for-sound tempo cell")
	var found := _find_cell(paths, Args.text(args, "movie", ""),
		Args.number(args, "frame", -1))
	var have := not found.is_empty()
	h.check("a score in %s waits for a sound channel" % root.get_file(), have,
		"none of the containers under %s carries a tempo cell of 255 or 254; "
		% root + "this entry has to name a root that does" if not have
		else "%s frame %d: tempo %d -> channel %d, cue %d (%d cell(s) in %d container(s))"
			% [str(found["movie"]), int(found["frame"]), int(found["tempo"]),
				int(found["channel"]), int(found["cue"]), int(found["total"]),
				int(found["containers"])])
	if not have:
		h.complete("the corpus holds a wait-for-sound tempo cell")
		quit(h.finish("a real wait-for-sound tempo cell holds the playhead"))
		return
	var channel := int(found["channel"])
	h.check("the score decodes the cell to the channel the byte names",
		channel == int(WAIT_SOUND[int(found["tempo"])]),
		"tempo %d decoded to channel %d" % [int(found["tempo"]), channel])
	h.complete("the corpus holds a wait-for-sound tempo cell")

	# A sound long enough that it cannot end during the hold window on its own.
	# Discovered rather than named, for the same reason the cell is.
	var sound := _long_sound(root)

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root_node().add_child(preview)
	await process_frame
	if preview.get("_score") == null:
		print("no score loaded; --root/--boot did not reach a movie")
		quit(1)
		return

	var audio: Node = root_node().get_node_or_null("AudioDirector")
	if audio == null:
		print("no AudioDirector autoload")
		quit(1)
		return

	# ------------------------------------------------- the frame arms the clock
	var arrived := await _land_on(preview, str(found["movie"]), int(found["frame"]))
	var clock = preview.get("_clock")
	h.begin("landing on the frame arms the wait")
	if not h.check("the playhead reached %s frame %d"
			% [str(found["movie"]), int(found["frame"])], arrived,
			"stopped on %s frame %d" % [
				str(preview.call("movie_name")), int(preview.call("current_frame"))]):
		h.complete("landing on the frame arms the wait")
		quit(h.finish("a real wait-for-sound tempo cell holds the playhead"))
		return
	# The control, and it runs *first* on purpose: with nothing on the channel the
	# frame must not hold, so a playhead that sits still in the case below is
	# sitting still because of the sound. `pump` releases the wait on the first
	# tick after arrival, which is why this reads the frame counter rather than
	# `waiting_sound()` -- by the time anything can be asked, the release has
	# already happened, and the movie moving on is the observable.
	audio.call("stop_channel", channel)
	var moved_silent := await _until_move(preview, MOVE_FRAMES)
	h.check("with channel %d silent the frame does not hold" % channel,
		moved_silent >= 0,
		"the playhead sat on frame %d for %d frames with nothing playing"
			% [int(preview.call("current_frame")), MOVE_FRAMES])
	h.complete("landing on the frame arms the wait")

	# --------------------------------------------------- held while it is playing
	h.begin("the playhead is held while the sound plays")
	if sound == "":
		h.check("a sound long enough to hold the frame is on the disc", false,
			"no audio file of %d bytes or more under %s" % [LONG_ENOUGH_BYTES, root])
		h.complete("the playhead is held while the sound plays")
		quit(h.finish("a real wait-for-sound tempo cell holds the playhead"))
		return
	# Started *before* the jump: `frame_loop.gd:tick` pumps the sound before it
	# consults the clock, so a channel that is still silent on the tick the
	# playhead arrives has already released the wait by the time anything can look.
	audio.call("play_file", channel, sound)
	h.check("the sound is playing on channel %d" % channel,
		bool(audio.call("sound_busy", channel)), "%s did not start" % sound)
	var back = await _land_on(preview, str(found["movie"]), int(found["frame"]))
	h.check("the playhead is back on the frame with the cell", back,
		"on %s frame %d" % [
			str(preview.call("movie_name")), int(preview.call("current_frame"))])
	var wait: Dictionary = clock.waiting_sound()
	h.check("the clock is waiting on channel %d" % channel,
		int(wait["channel"]) == channel,
		"waiting_sound() = %s, hold_reason %s" % [str(wait), str(clock.hold_reason())])
	h.check("and says so", str(clock.hold_reason()) == "wait for sound %d" % channel,
		str(clock.hold_reason()))
	var moved := await _until_move(preview, HOLD_FRAMES)
	h.check("the playhead does not move for %d frames" % HOLD_FRAMES, moved < 0,
		"it moved after %d frame(s), ending on frame %d"
			% [moved, int(preview.call("current_frame"))])
	h.check("and the sound is still playing at the end of them",
		bool(audio.call("sound_busy", channel)),
		"channel %d went quiet inside the window; %s is too short" % [channel, sound])
	h.complete("the playhead is held while the sound plays")

	# ------------------------------------------------- released when it finishes
	h.begin("the sound ending releases the playhead")
	var held_at := int(preview.call("current_frame"))
	audio.call("stop_channel", channel)
	var after := await _until_move(preview, MOVE_FRAMES)
	h.check("the wait is dropped", int(clock.waiting_sound()["channel"]) == 0,
		"still waiting on %s" % str(clock.waiting_sound()))
	h.check("and the playhead leaves frame %d" % held_at, after >= 0,
		"it is still on frame %d after %d frames" % [
			int(preview.call("current_frame")), MOVE_FRAMES])
	h.complete("the sound ending releases the playhead")

	quit(h.finish("a real wait-for-sound tempo cell holds the playhead and the sound releases it"))


## The first frame in the corpus whose tempo cell waits for a sound channel, plus
## the corpus-wide totals so a run says how much of the subject it found.
##
## `--movie`/`--frame` pin it; without them the walk decides, which is what keeps
## this entry title-agnostic. Sorted so that two runs pick the same one.
func _find_cell(paths, want_movie: String, want_frame: int) -> Dictionary:
	var containers: Array[String] = paths.containers()
	containers.sort()
	var out: Dictionary = {}
	var total := 0
	var with_any := 0
	for relative in containers:
		# `containers()` answers the index's own *relative* keys; `resolve` turns one
		# back into the file it came from, with the filesystem's spelling.
		var path: String = paths.resolve(relative)
		var f := ContainerFile.new()
		if path == "" or not f.open(path):
			continue
		var config = Config.new()
		var file_version := int(config.version) if config.read(f) else 0
		var ids: Array = f.ids_of("VWSC")
		var here := 0
		if not ids.is_empty():
			var score = Score.new()
			if score.parse(f.read_chunk(int(ids[0])), file_version):
				for i in score.frame_count:
					var cell: Vector2i = score.tempo_at(i)
					if not WAIT_SOUND.has(cell.x):
						continue
					total += 1
					here += 1
					if not out.is_empty():
						continue
					if want_movie != "" and not path.get_file().to_lower() \
							.begins_with(want_movie.get_file().to_lower()):
						continue
					if want_frame >= 0 and i != want_frame:
						continue
					# Through `frame()` and not through the raw byte: what is being
					# asserted is the *decode*, and reading the cell twice by two
					# routes is how a harness ends up agreeing with itself.
					var decoded: Dictionary = score.frame(i)
					out = {
						"movie": path.get_file(), "frame": i, "tempo": cell.x,
						"channel": int(decoded.get("wait_sound_channel", 0)),
						"cue": int(decoded.get("wait_cue", 0)),
					}
		if here > 0:
			with_any += 1
		f.close()
	if not out.is_empty():
		out["total"] = total
		out["containers"] = with_any
	return out


## The biggest audio file under the root, as a path relative to it — which is the
## shape `AudioDirector.resolve_path` takes and the shape a movie's own
## `sound playFile` builds.
func _long_sound(root: String) -> String:
	var best := ""
	var best_size := LONG_ENOUGH_BYTES
	var files: Array[String] = []
	_walk_audio(root, files)
	files.sort()
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var size := f.get_length()
		f.close()
		if size <= best_size:
			continue
		best_size = size
		best = path.trim_prefix(root).trim_prefix("/")
	return best


func _walk_audio(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		var lower := str(name).to_lower()
		if lower.ends_with(".aif") or lower.ends_with(".aiff") \
				or lower.ends_with(".wav"):
			out.append(dir_path.path_join(name))
	for sub in dir.get_directories():
		_walk_audio(dir_path.path_join(sub), out)


## Put the playhead on one frame of one movie and wait for it to actually be
## there. The jump is queued and taken on the next tick, so this awaits real
## frames rather than assuming.
func _land_on(preview: Node, movie: String, frame: int) -> bool:
	if str(preview.call("movie_name")).to_lower() != movie.get_basename().to_lower():
		preview.call("lingo_go_movie", movie, null)
		for _i in ARRIVE_FRAMES:
			await process_frame
			if str(preview.call("movie_name")).to_lower() == movie.get_basename().to_lower():
				break
	preview.call("lingo_go_frame", frame)
	for _i in ARRIVE_FRAMES:
		await process_frame
		if int(preview.call("current_frame")) == frame:
			return true
	return int(preview.call("current_frame")) == frame


## Frames awaited before the playhead first moved, or −1 if it never did inside
## the budget.
##
## Both assertions wait on this one condition rather than on a frame count, which
## is what makes them the same test on a fast machine and a slow one: "held" is
## "did not move in 300" and "released" is "moved within 900", and neither is
## reading a ratio off the runner's clock.
##
## Compared step by step rather than end to end, because a movie that steps away
## and loops back would read as "did not move" from the two endpoints alone --
## exactly the reading a broken hold would produce on a frame the score returns to.
func _until_move(preview: Node, budget: int) -> int:
	var was := int(preview.call("current_frame"))
	for i in budget:
		await process_frame
		if int(preview.call("current_frame")) != was:
			return i
	return -1


func root_node() -> Node:
	return root
