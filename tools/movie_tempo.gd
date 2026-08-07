extends SceneTree
## What rate does each movie in the corpus actually play at?
##
##   godot --headless --path . --script tools/movie_tempo.gd -- --root piposh
##   godot --headless --path . --script tools/movie_tempo.gd -- --root piposh2
##   godot --headless --path . --script tools/movie_tempo.gd -- --movie OPENING.dir
##   godot --headless --path . --script tools/movie_tempo.gd -- --verbose
##
## `DIRECTOR_ENGINE.md` §9.1 says "with no tempo, the previous rate carries
## forward" and never says what the *first* rate is. It is the movie's own
## default, in its config chunk, and a port that assumes one instead runs every
## movie that never writes a tempo at the wrong speed for its whole length --
## silently, because nothing errors and the movie plays.
##
## This exists because that is exactly what happened, twice, and the second time
## the first fix was already in place. Piposh 2's rooms mostly want 8 fps against
## an engine that assumed 15, so `DirectorConfig.default_tempo` was read and
## handed to the clock -- and Piposh 1's `OPENING.dir` still ran at 15, because
## `director_score.gd` resolves a per-frame `fps` by carrying the last tempo
## forward and *seeds that carry with a literal 15*. Every one of that movie's
## 334 frames therefore reported 15 fps although not one of them sets a tempo,
## and `FrameClock.enter_frame` took it on the first frame and threw the stated 8
## away. Nearly twice too fast, for the whole movie, and the only symptom is that
## it feels wrong.
##
## **So this asserts the reading, not the plausibility of a field.** The version
## that shipped before checked only that no movie *states* an absurd default,
## which both corpora passed while one of them played a hundred movies at the
## wrong speed. What is checked now is what the playhead does: every movie in the
## corpus is replayed through a real `FrameClock`, frame by frame, exactly as
## `scenes/preview/frame_loop.gd` drives it, and the rate it settles on is
## compared against the rate the movie's own data asks for. A movie may only ever
## play at a rate it states or a rate one of its tempo cells names -- never at
## the engine's guess.
##
## The tempo cell's two numberings are checked separately, from the reference
## rather than from the corpus: both corpora are D6 or later, so nothing here can
## produce a pre-D6 cell, and the case that reads one byte both ways is the only
## cover the older convention has. See `FrameClock.rate_from_tempo`.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")
const FrameClock := preload("res://director/director_frame_clock.gd")

## Anything outside this is not a frame rate, whatever else the field may be.
const PLAUSIBLE_MIN := 1
const PLAUSIBLE_MAX := 120


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_files():
		if Paths.CONTAINER_EXTENSIONS.has(entry.get_extension().to_lower()):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		_walk(dir_path.path_join(sub), out)


## The rate a tempo cell names, worked out here rather than asked of the clock.
##
## The point of the sweep is to check the clock's reading, so the expectation it
## is checked against may not come from the clock. This is the reference's rule
## restated from the other side: from D6 on the cell is a code and only 246 sets
## a rate, the operand beside it carrying the number; before D6 the cell is the
## rate itself whenever it is in 1-120, and every other value is a delay or a
## wait and leaves the rate standing.
static func _rate_named_by(tempo: int, cue: int, file_version: int) -> float:
	if tempo <= 0:
		return 0.0
	if file_version != 0 and file_version < FrameClock.FILE_VERSION_D6:
		return float(tempo) if tempo <= 120 else 0.0
	if tempo != 246:
		return 0.0
	return float(cue) if cue > 0 else 0.0


## Replay one movie through a real clock and report what it played at.
##
## Driven the way `frame_loop.gd` drives it: the movie's stated rate and version
## go in before the first frame, exactly as `movie_session.gd` sets them, and
## then `enter_frame` is called once per frame change. No time is advanced --
## `tick` paces the playhead and this is about which rate it would be pacing at.
func _replay(score, stated: int, file_version: int) -> Dictionary:
	var clock = FrameClock.new()
	clock.movie_default_fps = float(stated) if stated > 0 else FrameClock.DEFAULT_FPS
	clock.movie_file_version = file_version
	clock.reset()

	var expected := float(clock.movie_default_fps)
	var wrong_at := -1
	var wrong := ""
	var rates: Dictionary = {}
	var writes_a_rate := false
	var before_first := 0
	for i in score.frame_count:
		var frame: Dictionary = score.frame(i)
		var tempo := int(frame.get("tempo", 0))
		var cue := int(frame.get("tempo_cue", 0))
		var named := _rate_named_by(tempo, cue, file_version)
		if not writes_a_rate and named <= 0.0:
			before_first += 1
		if named > 0.0:
			writes_a_rate = true
			expected = named
		clock.enter_frame(frame)
		rates[clock.fps] = int(rates.get(clock.fps, 0)) + 1
		if wrong_at < 0 and not is_equal_approx(clock.fps, expected):
			wrong_at = i
			wrong = "frame %d: tempo %d/%d asks for %.0f, clock plays %.0f" \
				% [i, tempo, cue, expected, clock.fps]
	return {
		"rates": rates,
		"first_rate": clock.movie_default_fps,
		"wrong_at": wrong_at,
		"wrong": wrong,
		"writes_a_rate": writes_a_rate,
		# Frames played before any tempo cell names a rate -- the stretch where
		# the movie's stated default is the only thing saying how fast to run.
		"before_first_rate": before_first,
	}


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return
	var wanted := Args.text(args, "movie", "").to_lower()

	var files: Array[String] = []
	_walk(paths.root, files)
	files.sort()

	var stated_hist: Dictionary = {}
	var version_hist: Dictionary = {}
	var implausible: Array[String] = []
	var misread: Array[String] = []
	var unstated_rate: Array[String] = []
	var fast: Array[String] = []
	var guessing: Array[String] = []
	var silent: Array[String] = []
	var with_config := 0
	var with_score := 0
	var default_frames := 0

	for path in files:
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var name := path.get_file()
		var config = Config.new()
		var has_config: bool = config.read(f)
		var stated := int(config.default_tempo) if has_config else 0
		var file_version := int(config.version) if has_config else 0
		if has_config:
			with_config += 1
			stated_hist[stated] = int(stated_hist.get(stated, 0)) + 1
			version_hist[file_version] = int(version_hist.get(file_version, 0)) + 1
			if stated > PLAUSIBLE_MAX or stated < 0:
				implausible.append("%s states %d" % [name, stated])

		var ids: Array = f.ids_of("VWSC")
		if not ids.is_empty():
			var score = Score.new()
			if score.parse(f.read_chunk(int(ids[0]))) and score.frame_count > 0:
				with_score += 1
				var played := _replay(score, stated, file_version)
				var rates: Dictionary = played["rates"]
				default_frames += int(played["before_first_rate"])
				if int(played["wrong_at"]) >= 0:
					misread.append("%s %s" % [name, played["wrong"]])
				# Reported, never failed. A rate outside the band is what the
				# movie's own cell asks for, and the reference range-checks
				# nothing -- it takes the operand and divides by it. Failing here
				# would be asserting that this corpus is sensible rather than
				# that the engine reads it correctly, and the two are not the
				# same claim. It is worth *seeing*, because a wrong operand
				# offset would show up as a spray of these rather than as one.
				for rate in rates:
					var r := float(rate)
					if r < PLAUSIBLE_MIN or r > PLAUSIBLE_MAX:
						fast.append("%s asks for %.0f fps on %d frames"
							% [name, r, int(rates[rate])])
				if not bool(played["writes_a_rate"]):
					# Nothing in the score ever sets a rate, so the whole movie
					# runs at whatever it was started with. That is the case the
					# stated default is *for*, and the case the bug bit.
					silent.append(name)
					if stated <= 0:
						guessing.append(name)
					elif not is_equal_approx(float(rates.keys()[0]), float(stated)):
						unstated_rate.append("%s states %d, plays at %s"
							% [name, stated, JSON.stringify(rates.keys())])
				if wanted != "" and name.to_lower() == wanted:
					_trace(name, config, has_config, score, played)
		f.close()

	print("%s" % paths.root)
	print("  containers with a config : %d of %d" % [with_config, files.size()])
	print("  containers with a score  : %d" % with_score)
	print("  stated default rate      : %s" % JSON.stringify(stated_hist))
	print("  file version             : %s" % JSON.stringify(version_hist))
	print("  frames before any tempo names a rate: %d (these play at the stated default)"
		% default_frames)
	print("  score never sets a rate  : %d (these play at the stated default all the way)"
		% silent.size())
	if not silent.is_empty():
		var show: int = silent.size() if Args.flag(args, "verbose") else mini(6, silent.size())
		for i in show:
			print("      %s" % silent[i])
		if show < silent.size():
			print("      ... and %d more (pass --verbose)" % (silent.size() - show))
	print("  states none, sets none   : %d (these run on the engine's guess, %.0f fps)"
		% [guessing.size(), FrameClock.DEFAULT_FPS])
	print("  asks for a rate outside %d-%d: %d (reported, not failed -- see above)"
		% [PLAUSIBLE_MIN, PLAUSIBLE_MAX, fast.size()])
	for line in fast.slice(0, 8):
		print("      %s" % line)
	if fast.size() > 8:
		print("      ... and %d more" % (fast.size() - 8))

	h.begin("the tempo cell reads the same as the reference reads it")
	_check_reading(h)
	h.complete("the tempo cell reads the same as the reference reads it")

	h.begin("every movie plays at the rate its own data asks for")
	h.check("at least one container was read", not files.is_empty(), paths.root)
	h.check("at least one score was replayed", with_score > 0, paths.root)
	h.check("no movie states a rate outside %d-%d" % [PLAUSIBLE_MIN, PLAUSIBLE_MAX],
		implausible.is_empty(), ", ".join(implausible.slice(0, 4)))
	# The one that would have caught it. A movie whose score never sets a rate
	# has to play at its stated one for its whole length; `OPENING.dir` states 8
	# and played at 15, and so did the other 55 silent movies in that corpus.
	h.check("a movie whose score sets no rate plays at the rate it states, all the way",
		unstated_rate.is_empty(), ", ".join(unstated_rate.slice(0, 4)))
	# And the general form of it: on every frame of every movie, the rate is the
	# last one a tempo cell named, or the stated default if none has yet. That
	# covers the carry-forward in both directions -- a rate that fails to stick
	# and a rate that changes when nothing asked it to.
	h.check("the clock takes every rate the tempo cells ask for, and no other",
		misread.is_empty(), ", ".join(misread.slice(0, 3)))
	# Coverage, so neither half of the rule can go dark on a corpus. The first is
	# the tempo cell being read at all; the second is the stated default being
	# what the playhead uses in the absence of one, which is the half that was
	# wrong. Counted in frames rather than in movies, because a corpus where
	# every score sets a rate eventually still has a stretch before the first one
	# and that stretch is exactly what has to run at the stated rate.
	h.check("some movie in this corpus sets a rate from its score",
		with_score > silent.size(),
		"%d of %d scores set one" % [with_score - silent.size(), with_score])
	h.check("some frames play at the stated default, so it is exercised",
		default_frames > 0, "%d frames before any tempo names a rate" % default_frames)
	h.complete("every movie plays at the rate its own data asks for")
	quit(h.finish("the rate every movie in the corpus plays at"))


## The two numberings, checked against the reference rather than the corpus.
##
## Both corpora are D6 or later, so no container here can produce a pre-D6 cell
## and no sweep can cover that branch. The case that matters is the collision:
## the same byte 246 means "set the rate to the operand" from D6 on and "delay
## for ten seconds" before it, so a movie read in the wrong convention either
## takes a frame rate out of a pause or misses a rate change entirely. Both
## directions are asserted, because either one alone passes with the version test
## deleted.
func _check_reading(h) -> void:
	var d6 = FrameClock.new()
	d6.movie_file_version = FrameClock.FILE_VERSION_D6
	var d5 = FrameClock.new()
	d5.movie_file_version = FrameClock.FILE_VERSION_D6 - 1
	var unstated = FrameClock.new()

	h.check("D6 reads 246 as 'set the rate to the operand'",
		d6.rate_from_tempo(246, 8) == 8.0, "%s" % d6.rate_from_tempo(246, 8))
	h.check("D6 sets no rate from a delay, a click wait or a sound wait",
		d6.rate_from_tempo(247, 2) == 0.0 and d6.rate_from_tempo(248, 0) == 0.0 \
			and d6.rate_from_tempo(255, -1) == 0.0 and d6.rate_from_tempo(254, -2) == 0.0)
	h.check("D6 sets no rate from an empty cell", d6.rate_from_tempo(0, 0) == 0.0)
	h.check("D6 ignores the operand of a cell that is not 246",
		d6.rate_from_tempo(120, 30) == 0.0, "%s" % d6.rate_from_tempo(120, 30))

	h.check("pre-D6 reads the cell itself as the rate",
		d5.rate_from_tempo(8, 0) == 8.0 and d5.rate_from_tempo(120, 0) == 120.0)
	h.check("pre-D6 reads 246 as a delay, not as a rate",
		d5.rate_from_tempo(246, 8) == 0.0, "%s" % d5.rate_from_tempo(246, 8))
	h.check("pre-D6 sets no rate from a click wait or a sound wait",
		d5.rate_from_tempo(128, 0) == 0.0 and d5.rate_from_tempo(135, 0) == 0.0 \
			and d5.rate_from_tempo(134, 0) == 0.0)

	# A movie whose version went unread is read as D6, because that is the only
	# main-channel layout the score decoder produces. Stated, because the
	# alternative -- guessing the older numbering -- misreads every frame of
	# every container in both corpora.
	h.check("an unstated file version reads as D6",
		unstated.rate_from_tempo(246, 8) == 8.0 and unstated.rate_from_tempo(8, 0) == 0.0)

	# A rate of zero would make the frame infinitely long. The reference divides
	# by the operand without checking it; refusing it leaves the previous rate
	# standing, which is what a frame that named no rate would have done.
	h.check("a zero or negative operand names no rate",
		d6.rate_from_tempo(246, 0) == 0.0 and d6.rate_from_tempo(246, -3) == 0.0)


## Everything one movie's tempo does, frame by frame. `--movie OPENING.dir`.
func _trace(name: String, config, has_config: bool, score, played: Dictionary) -> void:
	print("--- %s ---" % name)
	if has_config:
		print("  config: states %d fps, file version 0x%x, stage %s"
			% [config.default_tempo, config.version, config.rect])
	else:
		print("  config: none (%s)" % config.error)
	print("  score : %d frames, frames version %d, %d channels"
		% [score.frame_count, score.frames_version, score.channels_displayed])
	var lines: Array[String] = []
	var last := -1
	for i in score.frame_count:
		var frame: Dictionary = score.frame(i)
		var tempo := int(frame.get("tempo", 0))
		if tempo == 0 or tempo == last:
			last = tempo
			continue
		last = tempo
		lines.append("      frame %d: cell %d, operand %d"
			% [i, tempo, int(frame.get("tempo_cue", 0))])
	if lines.is_empty():
		print("  tempo : no frame sets one, so the whole movie plays at %.0f fps"
			% float(played["first_rate"]))
	else:
		print("  tempo : %d changes" % lines.size())
		for line in lines.slice(0, 24):
			print(line)
		if lines.size() > 24:
			print("      ... and %d more" % (lines.size() - 24))
	print("  plays : %s (frames at each rate)" % JSON.stringify(played["rates"]))
