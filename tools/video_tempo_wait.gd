extends SceneTree
## A wait-for-video tempo instruction holds the playhead while a **real** video
## plays, and lets it go when the video ends.
##
##   godot --headless --audio-driver Dummy --path . --script tools/video_tempo_wait.gd -- \
##       --root piposh2 --boot strtgame.dir
##   godot --headless --audio-driver Dummy --path . --script tools/video_tempo_wait.gd -- \
##       --root res://test-games/itamar-magichat
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --hold N      awaited frames to watch a held playhead for (default 90)
##   --each        print a line for every video member the scan found
##
## ## What was broken
##
## §9.1's fifth tempo instruction is "hold this frame until the digital video in
## sprite channel N finishes". `director/director_frame_clock.gd` decoded it in
## both numberings, armed `_waiting_video`, reported it through `hold_reason` and
## released it through `FrameClock.video_probe` — and **nothing installed
## `video_probe`.** It was declared at :234 and polled at :689 with no caller
## anywhere in the repository, so `_video_holds()` took its `is_valid()` arm on
## every poll and every wait-for-video cell reported *finished* immediately.
##
## That was the right degrade for a port with no decoder. It is the wrong one for
## a port with three (`docs/DIGITAL_VIDEO.md` §4C2, §8, §9), and
## `preview/video.gd:channel_playing` is the answer the clock had been asking for.
## `preview/frame_loop.gd:tick` installs it, because that is the one place that
## holds the clock and the video host at the same time.
##
## ## Why the cell is synthetic and the video is not
##
## **No score in any of the eight corpora carries a wait-for-video cell.**
## `tools/movie_tempo.gd` walks every frame of every movie and says so; the
## `ENGINE_TODO` entry says so; and that is a fact about six shipped 1990s titles
## rather than about the feature, so it is a reason to synthesise the cell and
## not a reason to skip the feature (`AGENTS.md`, "build Director, not this
## game").
##
## The cell is synthesised through **`puppetTempo`**, which is the engine's own
## Lingo verb for exactly this and is routed through
## `director_preview.gd:lingo_puppet_tempo` -> `FrameClock.set_puppet_tempo` ->
## `Score.tempo_waits` — the same decoder a score cell goes through, in the
## verb's own pre-D6 numbering, where `135 + N` is "wait for the video in sprite
## channel N". Nothing here writes `_waiting_video`, calls `enter_frame` by hand
## or installs a probe of its own; the harness asks the movie for the wait in
## Lingo and then watches the score.
##
## That matters for a second reason: a puppet tempo is **re-armed by the engine
## on every score step** (`FrameClock._effective_tempo`, §9.1's precedence), so
## the wait this measures is not a one-shot the harness poked in — it is put back
## by the clock after every step exactly as a score cell would be, and the only
## thing that can get the playhead moving again is the probe answering "finished".
##
## The **video** is real: a member of the corpus in front of it, its media opened
## by whichever of the four backends takes it, its playhead advanced by
## `Video.advance` off real awaited frames. Where the corpus has no such member
## the two cases that need one say out loud that they found nothing and assert
## nothing — the `video_fallback` / `sprite_lifetime` pattern — because
## `test-games/itamar-magichat` is the only corpus in the tree with a video member
## and it is not in the repository (`.gitignore:73`; `gate.sh` carries the rule).
##
## ## The four claims, and why each is needed
##
##   A. **The clock has a probe, and it answers "finished" for every channel that
##      is not playing anything.** The first half is the one check here that is
##      about a `Callable` rather than about the playhead, and it earns its place
##      by being the only thing that goes red when the install is reverted — with
##      no probe the degrade is *indistinguishable* from a correct probe on a
##      corpus with no video, which is the whole point of the degrade. The second
##      half is the probe's own answer, read by calling it, over every channel.
##   B. **A wait-for-video on a channel holding no video does not hold the
##      playhead.** This is the control that costs nothing and catches the hang:
##      a probe that answered "still playing" because it could not find a video
##      would stop dead every movie in this tree that uses the tempo channel, and
##      this check is what fails the moment it does. It runs on any corpus.
##   C. **With a real video playing, the playhead does not move.** Measured over
##      awaited frames on a frame the harness has *already proved steps* with
##      nothing armed, so a still playhead here is the wait and not the movie.
##   D. **The video ending releases it and the playhead moves on**, and a video
##      whose media will not open never held it in the first place
##      (`docs/DIGITAL_VIDEO.md` §3: no media, no claim).
##
## Title-agnostic: it names no movie, no member, no channel and no file.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Census := preload("res://tools/video_census.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Paths := preload("res://director/director_paths.gd")
const Score := preload("res://director/director_score.gd")
const Clock := preload("res://director/director_frame_clock.gd")
const ContainerName := preload("res://director/director_container.gd")

## Awaited frames to watch a playhead that must **not** move. Far more than a
## step takes: the parking frame is chosen by proving it steps inside
## `PROBE_FRAMES`, so a hold that survives ten times that budget is not a movie
## that happened to be slow. Waits on the condition rather than on a ratio, for
## the reason `bugs.md` 41 gives; this is only its ceiling.
const HOLD_FRAMES := 90
## ... and the ceiling for the two assertions that wait for the playhead to move,
## generous in the other direction so that a loaded runner cannot read as a hold.
const MOVE_FRAMES := 900
## Awaited frames a candidate parking frame gets to prove it steps at all.
const PROBE_FRAMES := 240
## Awaited frames for a `go to movie` to land and the arriving movie to settle.
const OPEN_FRAMES := 24
## Awaited frames for a `go to frame` to land.
const ARRIVE_FRAMES := 60
## How many of a movie's opening frames are tried as a parking frame before the
## search gives up. A movie that steps at all steps within its first few.
const CANDIDATE_FRAMES := 12
## The highest sprite channel a `puppetTempo` can name a video wait on: the
## verb's numbering is pre-D6, where the video band is 136..195 biased by 135
## (`director_score.gd:TEMPO_D5_VIDEO_FIRST`), so channels 1..60 and no further.
const MAX_PUPPET_TEMPO_CHANNEL := 60
## Channels swept when asking the probe to answer "finished" for everything.
const SWEEP_CHANNELS := 120
## `the movieTime` is in QuickTime's 600ths (`preview/video.gd:TIME_SCALE`).
const TIME_SCALE := 600


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _drive(h)
	quit(h.finish(
		"a wait-for-video tempo instruction holds the playhead for a real video "
		+ "and for nothing else"))


func _drive(h: Harness) -> void:
	var args := Args.parse()
	var hold_frames := Args.number(args, "hold", HOLD_FRAMES)
	var verbose := Args.flag(args, "each")

	var paths := Paths.new()
	if not paths.load_config():
		h.begin("a corpus to drive")
		h.check("the config names a game", false, Paths.CONFIG_PATH)
		h.complete("a corpus to drive")
		return
	var corpus := str(paths.root).get_file()

	var members := _scan(paths)
	print("")
	print("root          : %s" % paths.root)
	print("video members : %d" % members.size())
	if verbose:
		for record in members:
			print("   %-20s lib %d #%-5d %-20s %s" % [
				str(record["file"]), int(record["lib"]), int(record["number"]),
				str(record["name"]), str(record["kind"])])
	print("")

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	# Several frames, not one. The node's `_process` returns before it reaches
	# `FrameLoop.tick` until the boot movie has a score
	# (`director_preview.gd:_process`), so a single awaited frame is a preview that
	# has never ticked -- and the probe is installed by the tick. Measured: with
	# one awaited frame `video_probe.is_valid()` is false and with two it is true,
	# which would have made check A below read as a missing install.
	for _i in OPEN_FRAMES:
		await process_frame
	if preview.get("_score") == null:
		h.begin("a movie to drive")
		h.check("--root/--boot reached a movie", false, str(paths.root))
		h.complete("a movie to drive")
		preview.queue_free()
		return
	var clock = preview.get("_clock")

	# ------------------------------------------------------------------- A
	await _probe_installed(h, corpus, preview, clock)
	# ------------------------------------------------------------------- B
	await _no_video_does_not_hold(h, corpus, preview, clock)
	# ------------------------------------------------------------------- C, D
	await _real_video(h, corpus, preview, clock, members, hold_frames)

	preview.queue_free()


# ------------------------------------------------------------------------- A


## The clock has something to ask, and what it asks answers "finished" for every
## channel that is not playing a video.
##
## The `is_valid()` check is deliberate and it is deliberately *first*. On its own
## it asserts nothing about behaviour — the task this file was written for says
## so in as many words — but it is the only assertion in this harness that can
## fail on a corpus with no video, because a missing probe and a correct probe
## give byte-for-byte the same playhead there. Without it a reverted install would
## leave this entry green on `GATE_ROOT`, which is precisely the "harness that
## cannot fail" this repository keeps catching itself writing.
##
## The sweep beside it is the behavioural half: the probe is *called*, for every
## channel a D5 score can name, at a moment when nothing has been started, and
## every one of them must answer no. A probe that guessed "playing" for a channel
## it could not resolve would hold every wait-for-video frame in the tree for
## ever, and this is that bug measured over 120 channels rather than argued about.
func _probe_installed(h: Harness, corpus: String, preview: Node, clock) -> void:
	var case := "%s: the frame clock has a video probe to ask" % corpus
	h.begin(case)
	var probe: Callable = clock.video_probe
	h.check("`FrameClock.video_probe` is installed", probe.is_valid(),
		"nothing called `Video.install_probe`, so every wait-for-video cell "
		+ "reports finished on its first poll")
	if not probe.is_valid():
		h.complete(case)
		return
	var claimed: Array[String] = []
	for channel in range(1, SWEEP_CHANNELS + 1):
		if bool(probe.call(channel)):
			claimed.append(str(channel))
	h.check("with nothing started, no channel claims a playing video",
		claimed.is_empty(),
		"channel(s) %s answered 'still playing' on frame %d of %s"
			% [", ".join(claimed), int(preview.call("current_frame")),
				str(preview.call("movie_name"))]
			if not claimed.is_empty()
			else "%d channels asked" % SWEEP_CHANNELS)
	h.check("and it answers for channel 0 and for a negative one too",
		not bool(probe.call(0)) and not bool(probe.call(-1)),
		"a cell decoded to a nonsense channel must not be able to hold a frame")
	h.complete(case)


# ------------------------------------------------------------------------- B


## The control, and the one that catches the hang.
##
## A wait-for-video naming a channel that holds no video is what **every movie in
## this tree would get** if a probe answered wrongly, and it is what Director
## itself answers `finished` to. So: prove the parking frame steps with nothing
## armed, arm the wait on an empty channel, and require that it still steps.
##
## The two halves are not interchangeable. Without the first, a playhead that sat
## still for its own reasons would read as this check passing in the failing
## direction on the next run; without the second there is nothing here at all.
func _no_video_does_not_hold(h: Harness, corpus: String, preview: Node, clock) -> void:
	var case := "%s: a wait-for-video on a channel holding no video does not hold" % corpus
	h.begin(case)
	var idle := _idle_channel(preview)
	var parking := await _free_frame(preview)
	if parking < 0:
		h.check("a frame whose playhead steps with nothing armed", false,
			"none of the first %d frames of %s stepped within %d awaited frames, "
				% [CANDIDATE_FRAMES, str(preview.call("movie_name")), PROBE_FRAMES]
			+ "so there is no parking frame here and this asserts nothing")
		h.complete(case)
		return
	h.check("frame %d of %s steps with nothing armed"
			% [parking, str(preview.call("movie_name"))], true,
		"the control that makes the two checks below mean something")

	# What the value means, from the decoder rather than from this file's
	# arithmetic. The verb reads its argument in the pre-D6 numbering
	# (`FrameClock.PUPPET_TEMPO_NUMBERING`), where 136..195 is "wait for the video
	# in sprite channel `value - 135`".
	var cell := Score.TEMPO_D5_VIDEO_CHANNEL_BIAS + idle
	var decoded: Dictionary = Score.tempo_waits(cell, 0, Clock.PUPPET_TEMPO_NUMBERING)
	h.check("`puppetTempo %d` is a wait for the video in channel %d" % [cell, idle],
		int(decoded.get("wait_video_channel", 0)) == idle, str(decoded))

	# Landed first and armed second, with no `await` between: the verb arms the
	# wait inside the call (`FrameClock.set_puppet_tempo`), and from the next tick
	# on it is the *engine* that puts it back -- §9.1's precedence re-resolves the
	# tempo on every score step and a frame carrying no cell of its own resolves
	# to the puppet. So nothing here holds the wait open; the clock does, exactly
	# as it would for a cell in the score.
	#
	# **`waiting_video()` is deliberately not read here**, and the reason is the
	# feature working. `FrameClock._video_holds()` releases a wait the probe will
	# not vouch for, and it is reached from `playhead_held()` and from `status()`
	# alike -- so the trace line `lingo_puppet_tempo` prints has already cleared
	# this wait before the verb returns. That is the degrade, on a channel that
	# holds no video, which is precisely what this case is about; asserting the
	# flag would be asserting that the release had not happened yet.
	await _land_on(preview, parking)
	preview.call("lingo_puppet_tempo", cell)
	var moved := await _until_move(preview, MOVE_FRAMES)
	h.check("and the playhead moves anyway, because channel %d holds no video" % idle,
		moved >= 0,
		"it sat on frame %d for %d awaited frames -- a probe that holds for a "
			% [int(preview.call("current_frame")), MOVE_FRAMES]
			+ "video it cannot find is a hang in every movie that uses the cell"
		if moved < 0 else "moved after %d awaited frame(s)" % moved)
	preview.call("lingo_puppet_tempo", 0)
	h.complete(case)


# ---------------------------------------------------------------------- C, D


## The two claims that need a video member, run against whichever the corpus has.
##
## The member is *classified by trying to open it*, which is the same partition
## `docs/DIGITAL_VIDEO.md` §3 draws and the one this file needs: a member whose
## media a backend took is the fixture for C, and one no backend would take is the
## fixture for D. Deciding that from the filesystem instead would be a second
## opinion about which files exist, and what C needs is not "the file is there" —
## it is "something is decoding it".
func _real_video(h: Harness, corpus: String, preview: Node, clock,
		members: Array, hold_frames: int) -> void:
	var playable: Dictionary = {}
	var dead: Dictionary = {}
	var channel := _idle_channel(preview)
	for record in members:
		var opened := await _try_member(preview, record, channel)
		if opened.is_empty():
			print("   %-14s #%-5d %-20s could not be mounted from %s" % [
				str(record["file"]), int(record["number"]), str(record["name"]),
				str(record["movie"])])
			continue
		print("   %-14s #%-5d %-20s %s (%s, %.2fs)" % [
			str(record["file"]), int(record["number"]), str(record["name"]),
			"opens" if bool(opened["decoded"]) else "no media",
			str(opened["backend"]) if str(opened["backend"]) != "" else "no backend",
			float(int(opened["duration"])) / TIME_SCALE])
		if bool(opened["decoded"]):
			if playable.is_empty():
				playable = opened
		elif dead.is_empty():
			dead = opened

	# ------------------------------------------------------------------- C, D
	var case := "%s: a real video holds the playhead until it ends" % corpus
	h.begin(case)
	if playable.is_empty():
		h.check("this corpus has no video member a backend will open, so no "
				+ "playhead can be held by one here", true,
			"%d video member(s) scanned; run --root res://test-games/itamar-magichat "
				% members.size()
			+ "for the only corpus in the tree that has one")
		h.complete(case)
		await _no_media_case(h, corpus, preview, clock, dead)
		return

	var record: Dictionary = playable["record"]
	var ch := int(playable["channel"])
	var duration := int(playable["duration"])
	print("fixture       : %s lib %d #%d %s, %.2fs through %s in channel %d" % [
		str(record["file"]), int(record["lib"]), int(record["number"]),
		str(record["name"]), float(duration) / TIME_SCALE,
		str(playable["backend"]), ch])
	# Re-established from scratch: the scan above drove every other video member
	# through this same channel looking for one that opens, so the channel is
	# holding whichever came last.
	await _mount(preview, record, ch)
	_media(preview).set_sprite_prop(ch, "movietime", 0)
	_media(preview).set_sprite_prop(ch, "movierate", 1.0)
	var table = preview.get("_table")
	var member: Dictionary = table.get_member(
		int(record["lib"]), int(record["number"]))
	var loops := bool(member.get("looping", false))

	# The playhead of the *video*, measured rather than asked for: two samples a
	# few awaited frames apart, so "playing" is something this harness watched
	# happen and not something `getPlaybackEvent` told it.
	var before := int(_media(preview).get_sprite_prop(ch, "movietime"))
	for _i in 12:
		await process_frame
	var after := int(_media(preview).get_sprite_prop(ch, "movietime"))
	h.check("the video is decoding: `the movieTime` moved %d -> %d units"
			% [before, after], after > before,
		"a frozen playhead here is `bugs.md` 84's hang, not this file's subject")
	h.check("and the probe says channel %d is still playing" % ch,
		_playing(clock, ch),
		"movieTime %d of %d, movieRate %s" % [
			after, duration, str(_media(preview).get_sprite_prop(ch, "movierate"))])

	var parking := await _free_frame(preview)
	if parking < 0:
		h.check("a frame whose playhead steps with nothing armed", false,
			"no parking frame in %s" % str(preview.call("movie_name")))
		h.complete(case)
		return
	h.check("frame %d of %s steps with nothing armed"
			% [parking, str(preview.call("movie_name"))], true,
		"the control that makes the hold below mean something")

	await _land_on(preview, parking)
	preview.call("lingo_puppet_tempo", Score.TEMPO_D5_VIDEO_CHANNEL_BIAS + ch)
	h.check("the clock is waiting for the video in channel %d" % ch,
		int(clock.waiting_video()) == ch,
		"waiting_video() = %d, hold_reason %s" % [
			int(clock.waiting_video()), str(clock.hold_reason())])
	h.check("and says so", str(clock.hold_reason()) == "wait for video in channel %d" % ch,
		str(clock.hold_reason()))
	var stood_on := int(preview.call("current_frame"))
	var began_at := int(_media(preview).get_sprite_prop(ch, "movietime"))
	var stepped := await _until_move(preview, hold_frames)
	var still := int(_media(preview).get_sprite_prop(ch, "movietime"))
	h.check("the playhead does not move for %d awaited frames" % hold_frames,
		stepped < 0,
		"it moved after %d awaited frame(s), off frame %d" % [stepped, stood_on]
		if stepped >= 0 else
		"frame %d of %s, while `the movieTime` ran %d -> %d of %d units (%.2fs)"
			% [stood_on, str(preview.call("movie_name")), began_at, still, duration,
				float(still - began_at) / TIME_SCALE])
	h.check("and the video is still playing at the end of them",
		_playing(clock, ch),
		"the clip ended inside the hold window (movieTime %d of %d) -- --hold is "
			% [still, duration] + "too long for a video this short"
		if not _playing(clock, ch) else
		"%d units of %d played, so the hold was the wait and not the end of the clip"
			% [still, duration])
	h.complete(case)

	# ------------------------------------------------------------------- D
	var release_case := "%s: the video ending releases the playhead" % corpus
	h.begin(release_case)
	if loops:
		print("note          : the member loops, so the release is `the movieRate` "
			+ "-> 0 (`isActiveVideo() && _movieRate != 0`, the other half of the "
			+ "reference's condition) rather than the end of the clip")
	# Driven to one unit short of the end and then left alone: the release comes
	# from `Video.advance`'s own end-of-clip clamp on the next tick, which is the
	# path a clip that simply ran out takes. Writing `the movieRate` to 0 would
	# release it too and would be testing the *pause* arm of the reference's
	# condition instead.
	#
	# Unless the member loops. `the loop of member` makes `advance` rewind to the
	# in point instead of clamping, so such a clip **never finishes** and the wait
	# is Director's own answer to a movie that authored one — the escape is the
	# rate going to 0 or a queued `go to`, and there is no third. The harness
	# takes the rate arm there and says which arm it took, rather than pretending
	# a looping clip ended.
	if loops:
		_media(preview).set_sprite_prop(ch, "movierate", 0.0)
	else:
		_media(preview).set_sprite_prop(ch, "movietime", duration - 1)
	var freed := await _until_move(preview, MOVE_FRAMES)
	h.check("the playhead leaves frame %d within %d awaited frames"
			% [stood_on, MOVE_FRAMES], freed >= 0,
		"still on frame %d after %d awaited frames"
			% [int(preview.call("current_frame")), MOVE_FRAMES]
		if freed < 0 else "moved after %d awaited frame(s), onto frame %d"
			% [freed, int(preview.call("current_frame"))])
	h.check("and the probe now answers finished for channel %d" % ch,
		not _playing(clock, ch),
		"movieTime %d of %d, movieRate %s" % [
			int(_media(preview).get_sprite_prop(ch, "movietime")), duration,
			str(_media(preview).get_sprite_prop(ch, "movierate"))])
	# **`waiting_video()` is read after the puppet is handed back, not before.**
	# A puppet tempo is re-resolved and re-armed on *every* score step (§9.1), so
	# for as long as it is in force the flag is put back a tick after the probe
	# clears it and a reading taken mid-run catches whichever half of that cycle it
	# lands on -- measured: `waiting_video() = 60` immediately after the playhead
	# had demonstrably moved two frames on. The playhead moving is the observable;
	# this is the tidy-up asserting that nothing is left holding.
	preview.call("lingo_puppet_tempo", 0)
	h.check("and with the tempo handed back nothing is holding the playhead",
		int(clock.waiting_video()) == 0 and not bool(clock.playhead_held()),
		"waiting_video() = %d, hold_reason %s" % [
			int(clock.waiting_video()), str(clock.hold_reason())])
	print("playhead      : %s, released %d awaited frame(s) after the clip ended" % [
		"held for all %d awaited frames of the hold window" % hold_frames
		if stepped < 0 else
		"NOT held -- stepped after %d of %d awaited frames" % [stepped, hold_frames],
		freed])
	h.complete(release_case)

	await _no_media_case(h, corpus, preview, clock, dead)


## `docs/DIGITAL_VIDEO.md` §3's rule, on the tempo channel: a member whose media
## will not open answers *no media*, so it can never hold a playhead.
##
## `logo.dir` #27 `prelogo` is the whole population of this case in eight corpora
## — its `prelogo.avi` was never shipped — and a wait for it would be a wait until
## the process ended. Where the corpus has no such member this says so and asserts
## nothing, which is the honest state and not a passing one.
func _no_media_case(h: Harness, corpus: String, preview: Node, clock,
		dead: Dictionary) -> void:
	var case := "%s: a video whose media will not open never holds the playhead" % corpus
	h.begin(case)
	if dead.is_empty():
		h.check("this corpus has no video member with unopenable media, so the "
				+ "rule is not exercised here", true,
			"`logo.dir` #27 `prelogo` under res://test-games/itamar-magichat is the "
			+ "only one in the tree")
		h.complete(case)
		return
	var record: Dictionary = dead["record"]
	var ch := int(dead["channel"])
	# Re-established rather than assumed: the run above drove other members
	# through the same channel.
	await _mount(preview, record, ch)
	_media(preview).set_sprite_prop(ch, "movierate", 1.0)
	h.check("%s #%d %s reports `the movieRate` 1 and still has no media"
			% [str(record["file"]), int(record["number"]), str(record["name"])],
		not is_zero_approx(float(_media(preview).get_sprite_prop(ch, "movierate"))),
		"the write must land, or the check below is about the write")
	h.check("the probe answers finished for it", not _playing(clock, ch),
		"a playhead held for a video that will never play is the worst outcome "
		+ "available (`docs/DIGITAL_VIDEO.md` §3)")
	var parking := await _free_frame(preview)
	if parking < 0:
		h.check("a frame whose playhead steps with nothing armed", false,
			"no parking frame in %s" % str(preview.call("movie_name")))
		h.complete(case)
		return
	await _land_on(preview, parking)
	preview.call("lingo_puppet_tempo", Score.TEMPO_D5_VIDEO_CHANNEL_BIAS + ch)
	var moved := await _until_move(preview, MOVE_FRAMES)
	h.check("and a wait for it does not stop the playhead", moved >= 0,
		"it sat on frame %d for %d awaited frames"
			% [int(preview.call("current_frame")), MOVE_FRAMES]
		if moved < 0 else "moved after %d awaited frame(s)" % moved)
	preview.call("lingo_puppet_tempo", 0)
	h.complete(case)


# ------------------------------------------------------------------- driving


## Put a member into a channel as a puppet and try to start it.
##
## Returns `{}` when the member cannot be addressed from its own movie at all,
## and otherwise `{record, channel, decoded, backend, duration}` — `decoded` being
## whether a backend actually opened the media, which is how C and D pick their
## fixtures apart.
##
## The sprite is **puppeted** rather than reached by driving to the frame that
## scores it, and that is what makes this harness able to park anywhere. A video
## sprite in a 1990s title lives on a frame whose script is `go(the frame)`, so
## the frame that shows the clip is exactly the frame whose playhead cannot be
## observed to move — the puppet carries the video onto a frame that steps, which
## is Director's own mechanism for holding a channel against the score (§5.2) and
## costs the video nothing: `Video.advance` walks `media_channels`, and
## `member_of_channel` reads the effective member, puppet included.
func _try_member(preview: Node, record: Dictionary, channel: int) -> Dictionary:
	if not await _mount(preview, record, channel):
		return {}
	_media(preview).set_sprite_prop(channel, "movietime", 0)
	_media(preview).set_sprite_prop(channel, "movierate", 1.0)
	await process_frame
	var duration := int(_media(preview).get_member_prop(
		int(record["number"]), int(record["lib"]), "duration"))
	var ready := int(_media(preview).get_member_prop(
		int(record["number"]), int(record["lib"]), "mediaready")) != 0
	var backend := ""
	var entry: Dictionary = _media(preview).video_readers.get(
		"%d:%d" % [int(record["lib"]), int(record["number"])], {})
	var reader = entry.get("reader", null)
	if reader != null:
		backend = str(reader.backend())
	var decoded := reader != null and ready and duration > 0
	if not decoded:
		_media(preview).set_sprite_prop(channel, "movierate", 0.0)
	return {
		"record": record, "channel": channel, "decoded": decoded,
		"backend": backend, "duration": duration,
	}


## `go to movie` the container that can address the member, then puppet the
## channel onto it. False when the member does not resolve there.
func _mount(preview: Node, record: Dictionary, channel: int) -> bool:
	var movie := str(record["movie"])
	preview.call("lingo_go_movie", movie, null)
	for _i in OPEN_FRAMES:
		await process_frame
	if preview.get("_score") == null:
		return false
	preview.call("lingo_puppet_sprite", channel, true)
	_media(preview).set_sprite_prop(channel, "castlibnum", int(record["lib"]))
	_media(preview).set_sprite_prop(channel, "membernum", int(record["number"]))
	await process_frame
	var table = preview.get("_table")
	if table == null:
		return false
	var member: Dictionary = table.get_member(
		int(record["lib"]), int(record["number"]))
	return _kind_of(member) != ""


## The probe's own answer, guarded so that a run with **no probe installed**
## reports failing checks rather than dying on an invalid `Callable`.
##
## That guard is not defensive coding, it is the revert control working: this
## harness has to produce a readable red when `Video.install_probe` is taken out,
## and an aborted case reports "did not complete" instead of naming the four
## claims that stopped being true.
func _playing(clock, channel: int) -> bool:
	var probe: Callable = clock.video_probe
	return probe.is_valid() and bool(probe.call(channel))


## The Lingo host, **read fresh every time**.
##
## `preview/boot.gd:start_lingo` builds a new one per movie, and the digital-video
## state lives on it (`preview_lingo_host.gd`: `media_channels`, `video_readers`
## and the rest die with the movie they belong to, because a `(library, slot)`
## pair names a different member in the next movie's casts). A reference captured
## before a `go to movie` therefore answers about the *previous* movie, and it
## answers rather than failing — which is `scenes/preview/README.md`'s "a harness
## that reads null reports zero rather than failing" one step over.
##
## Measured, because that is exactly what this harness did first: with the host
## captured once at boot, `logo.dir` #28 `logo` answered `the duration` 10.08 s
## through the live host and `video_readers` empty through the stale one, so the
## fixture that had opened perfectly was classified "no media" and the whole
## held-playhead case reported that the corpus had nothing to hold on.
##
## The *clock* is the opposite case and is captured once on purpose:
## `director_preview.gd:135` constructs it at declaration and nothing reassigns
## it, so it outlives every movie in the session.
func _media(preview: Node):
	return preview.get("_host")


## A sprite channel the current frame does not use, low enough for `puppetTempo`
## to be able to name a video wait on it.
##
## Searched from the top of the addressable band down, so a movie that scores its
## first thirty channels still leaves this one alone.
func _idle_channel(preview: Node) -> int:
	var used: Dictionary = {}
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		used[int(sprite["channel"])] = true
	for channel in range(MAX_PUPPET_TEMPO_CHANNEL, 0, -1):
		if not used.has(channel):
			return channel
	return MAX_PUPPET_TEMPO_CHANNEL


## A frame of the current movie whose playhead **steps** with nothing armed.
##
## Every claim about a held playhead in this file is measured against one of
## these, because the alternative is measuring a movie that had nowhere to go and
## calling it a hold. Discovered rather than named: the harness tries the movie's
## opening frames in order and takes the first that moves, so it needs to know
## nothing about the title.
##
## Returns the frame it stepped **from**, 0-based, which is `current_frame`'s own
## numbering (`lingo_go_frame` is 0-based; the score's and Lingo's are 1-based).
##
## **A candidate whose own tempo cell is non-zero is skipped**, and that is not
## fussiness. §9.1's first release condition is that a frame writing a tempo
## cancels the puppet (`FrameClock._effective_tempo`), so parking the wait on such
## a frame would have the engine drop it on the next step — correctly — and the
## harness would be measuring the cancel rather than the probe. Read through the
## score's own `tempo_at`, which is the two bytes and no decode.
func _free_frame(preview: Node) -> int:
	var score = preview.get("_score")
	for candidate in CANDIDATE_FRAMES:
		if score != null and int(score.tempo_at(candidate).x) != 0:
			continue
		await _land_on(preview, candidate)
		if int(preview.call("current_frame")) != candidate:
			continue
		if await _until_move(preview, PROBE_FRAMES) >= 0:
			return candidate
	return -1


func _land_on(preview: Node, frame: int) -> void:
	preview.call("lingo_go_frame", frame)
	for _i in ARRIVE_FRAMES:
		await process_frame
		if int(preview.call("current_frame")) == frame:
			return


## Awaited frames before the playhead first moved, or -1 if it never did.
##
## Compared step by step rather than end to end, for the reason
## `sound_tempo_wait.gd` gives: a movie that steps away and loops back would read
## as "did not move" from the two endpoints alone, which is exactly the reading a
## broken hold produces on a frame the score returns to.
func _until_move(preview: Node, budget: int) -> int:
	var was := int(preview.call("current_frame"))
	for i in budget:
		await process_frame
		if int(preview.call("current_frame")) != was:
			return i
	return -1


# ------------------------------------------------------------------ the scan


## Every video member the corpus can address, one walk of the containers.
##
## A member's `movie` is a container that can reach it — the one this harness
## will `go to movie` before mounting it — and for a member in a shared cast that
## is whichever container linked it first. Any of them would do; what matters is
## that the member is addressable from the movie the question is asked in.
func _scan(paths) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for entry in paths.containers():
		# Movies only. A member in a shared cast is addressable from every movie
		# that links the cast, and only a movie can be `go to movie`'d -- so
		# scanning `.cst` containers as well would name `album.cst` as the place to
		# ask about `magicvideo` and the mount would fail on a container the engine
		# will not open as a movie. Magic Hat's `album.cst` #210 is exactly that
		# case and was reported as unmountable until this line existed.
		if ContainerName.CAST.has(str(entry).get_extension().to_lower()):
			continue
		var path: String = paths.resolve(str(entry))
		if path == "":
			continue
		var f := ContainerFile.new()
		if not f.open(path):
			continue
		var table := CastTable.new()
		if not table.open(f, paths):
			table.close()
			f.close()
			continue
		for lib in table.cast_libs.keys():
			var cast = table.cast_for(int(lib))
			if cast == null:
				continue
			for number in cast.member_numbers():
				var m: Dictionary = cast.member(number)
				var kind := _kind_of(m)
				if kind == "":
					continue
				var key := "%s#%d" % [
					str(table.cast_libs[lib].get("resolved_path", "")), int(number)]
				if seen.has(key):
					continue
				seen[key] = true
				out.append({
					"movie": str(entry), "file": path.get_file(),
					"lib": int(lib), "number": int(number),
					"name": str(m.get("name", "")), "kind": kind,
				})
		table.close()
		f.close()
	return out


## `"digitalVideo"`, `"video-xtra"` or `""`, off the census's own table so that
## this tool and `video_census` / `video_fallback` cannot come to disagree about
## what counts as a video.
static func _kind_of(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	var code := int(m.get("type", 0))
	if code == Census.VIDEO_TYPE:
		return "digitalVideo"
	if code == Census.XTRA_TYPE \
			and Census.VIDEO_XTRAS.has(str(m.get("xtra_symbol", "")).to_lower()):
		return "video-xtra"
	return ""
