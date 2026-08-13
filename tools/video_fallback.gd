extends SceneTree
## Put the playhead on every frame in a title that shows a video, and prove the
## player can get off it again.
##
##   godot --headless --audio-driver Dummy --path . --script tools/video_fallback.gd -- \
##       --root res://test-games/itamar-magichat
##   godot --headless --audio-driver Dummy --path . --script tools/video_fallback.gd -- \
##       --root piposh2
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --ticks N     score ticks to watch each video frame for (default 90)
##   --settle N    score ticks to let a movie open in (default 24)
##   --each        print a line for every target, not only the findings
##
## ## The question, and why it is not the decoder question
##
## This port has no decoder for MPEG-1, AVI or QuickTime, and `bugs.md` 82 and 84
## carry what that costs. **Whether the picture appears is not what this asserts.**
## What it asserts is the half that is a bug regardless of how the decoder
## question is answered:
##
##   * A movie that **skips** a video it cannot play is behaving. The player loses
##     the content and keeps the game.
##   * A movie that **waits** for a video that will never start has lost the game
##     as well, and there is no decoder-shaped excuse for it -- Director itself
##     does the first thing when a codec is missing, which is exactly why every
##     one of these movies has a fallback arm at all.
##
## So the invariant is: **no frame that puts a video sprite on the stage holds the
## playhead there for ever with nothing on the clock.** A frame that parks with a
## tempo delay, a transition, a `pause` or a sound in flight is holding for a
## reason and is not this file's subject; a frame that parks with a video sprite
## on it, no reason, and no way out is.
##
## ## How a target is found
##
## Not by playing the title from the start and hoping to arrive. The score is read
## directly and every (movie, frame) that places a `#digitalVideo` member or a
## video Xtra is a target; the preview is then driven **to** that frame with
## `lingo_go_frame`. That matters for `itamar-magichat`, whose intro region is
## reached only when its own `magichat.ini` says `startframe=intro` -- a normal
## boot with `startframe=mainmenu` never goes near it, so a sweep that only played
## from the top would report the intro clean without ever having looked at it.
##
## `tools/liveness_sweep.gd` is the general form of this and is the right tool for
## "is any movie stuck". It cannot answer this one: it plays from each movie's
## own opening frame, and the frames here are not reachable from there.
##
## ## The second half: the answers are the honest ones, whichever way they go
##
## A skip is only correct because the property surface tells the truth, and the
## truth is now two different answers rather than one. `the mediaReady of member`
## and `the duration of member` are the two values every one of these movies'
## guards actually reads -- Magic Hat's `Check avi` is
## `if sprite(3).movieTime >= FilmLen` -- and this asserts them against a witness
## from **outside** the property surface: whether the file the member names is on
## the disc.
##
##   * media on the disc  -> `the mediaReady` TRUE and a duration above 0
##   * no media           -> `the mediaReady` FALSE and a duration of 0
##
## That split is the whole subject of this file since `director/director_avi.gd`
## landed. `logo.dir` #28 `logo` names `logo.avi`, which is beside it, so it is
## the first member in eight corpora that answers ready; #27 `prelogo` is
## repointed at `prelogo.avi` by `startMovie` and that file does not exist, so it
## answers exactly what it always did. **Neither answer is a default** -- one is
## earned by a decoder opening the file and the other by it declining.
##
## ## The third half, and the reason this file was rewritten rather than relaxed
##
## Making `the duration` real is only safe if `the movieTime` moves. `Check avi`'s
## other arm is `go(the frame)`, so a port that answered a confident duration and
## left the playhead where it was put would convert a clean one-tick skip into an
## **infinite loop** -- the exact failure this file exists to catch, arriving
## through the change that was supposed to be an improvement.
##
## So the watch now samples `the movieRate` and `the movieTime` of the target
## channel every tick, and a frame whose movie *started* a video that *has* media
## must show the playhead advancing. A frozen playhead is reported by name rather
## than as a timeout twenty seconds later.
##
## Title-agnostic: it names no game, no channel and no member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Census := preload("res://tools/video_census.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Config := preload("res://director/director_config.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")

## Score ticks to watch one video frame for. Well past the two a healthy skip
## takes and past any plausible transition, and bounded in wall clock besides.
const WATCH := 90
const SETTLE := 24
## Process frames to let `go to movie` land, the same budget `liveness_sweep`
## uses and for the same reason: the score is parsed and the cast opened inside
## the call, and the first tick after it is the movie's own.
const OPEN_FRAMES := 8
## Wall-clock ceilings. A watch that cannot make its ticks in this long is
## reported as thin rather than left to run.
const OPEN_CAP_MS := 8000
const WATCH_CAP_MS := 20000
## Process frames with no score tick before a watch gives up. A stopped clock is
## `pause` or `halt`, both of which are answers.
const QUIET_STALL := 240


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _sweep(h)
	quit(h.finish("no title waits for a video it will never be able to play"))


func _sweep(h: Harness) -> void:
	var args := Args.parse()
	var ticks := Args.number(args, "ticks", WATCH)
	var settle := Args.number(args, "settle", SETTLE)
	var verbose := Args.flag(args, "each")

	var paths := Paths.new()
	if not paths.load_config():
		h.begin("a corpus to sweep")
		h.check("the config names a game", false, Paths.CONFIG_PATH)
		h.complete("a corpus to sweep")
		return
	var corpus := str(paths.root).get_file()

	var scan := _scan(paths)
	var members: Array[Dictionary] = scan["members"]
	var targets: Array[Dictionary] = scan["targets"]

	print("")
	print("root    : %s" % paths.root)
	print("video members : %d" % members.size())
	for record_value in members:
		var m: Dictionary = record_value
		print("   %-20s #%-5d %-20s %s" % [
			str(m["file"]), int(m["number"]), str(m["name"]), str(m["kind"])])
	print("targets : %d (movie, frame) pair(s) that place one" % targets.size())
	print("")

	# ------------------------------------------------------- the property surface
	#
	# Asserted before the playhead is driven anywhere, because it is what decides
	# which arm every guard below takes. A `--root` with no video member says so
	# out loud rather than passing over an empty list.
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame

	var case := "%s: a video answers what its media is, not a guess" % corpus
	h.begin(case)
	var playable: Dictionary = {}
	if members.is_empty():
		h.check(
			"this corpus holds no video member, so the surface is not exercised here",
			true,
			"run --root res://test-games/itamar-magichat for the only corpus that does")
	else:
		var with_media := 0
		var without := 0
		var wrong: Array[String] = []
		for record_value in members:
			var m: Dictionary = record_value
			if str(m["kind"]) != "digitalVideo":
				# An Xtra member's media is the DLL's, not Director's, so
				# `the mediaReady of member` is not the question to ask of one --
				# `docs/LINGO_SURFACE.md` gives it `interface` and `mediaBusy`
				# instead, and neither is bound. Skipped rather than asserted
				# wrongly.
				continue
			preview.call("lingo_go_movie", str(m["movie"]), null)
			for _i in OPEN_FRAMES:
				await process_frame
			var host = preview.get("_host")
			if host == null:
				continue
			var ready: Variant = host.get_member_prop(
				int(m["number"]), int(m["lib"]), "mediaready")
			var duration: Variant = host.get_member_prop(
				int(m["number"]), int(m["lib"]), "duration")
			# The witness, and it is deliberately not the property surface: the
			# member says which file it wants and the *filesystem* says whether
			# that file is there. Read after `go to movie` so a `startMovie` that
			# repoints the member has already run -- which is exactly what
			# `logo.dir` does to `prelogo`, and without it this would expect a
			# member to be ready because the name in its cast record happens to
			# exist.
			var wanted := str(host.get_member_prop(
				int(m["number"]), int(m["lib"]), "filename"))
			var on_disc := _media_on_disc(str(m["movie"]), paths, wanted)
			if on_disc:
				with_media += 1
				playable["%s#%d" % [str(m["movie"]), int(m["number"])]] = true
				if int(ready) == 0:
					wrong.append("%s #%d names %s, which is on the disc, and answers "
						% [str(m["file"]), int(m["number"]), wanted]
						+ "mediaReady FALSE")
				if int(duration) <= 0:
					wrong.append("%s #%d names %s and answers duration %s" % [
						str(m["file"]), int(m["number"]), wanted, str(duration)])
			else:
				without += 1
				if int(ready) != 0:
					wrong.append("%s #%d names %s, which is not on the disc, and "
						% [str(m["file"]), int(m["number"]), wanted]
						+ "answers mediaReady=%s" % str(ready))
				if int(duration) != 0:
					wrong.append("%s #%d names %s and answers duration=%s" % [
						str(m["file"]), int(m["number"]), wanted, str(duration)])
		h.check(
			"%d with media answer ready and a real duration, %d without answer 0"
				% [with_media, without],
			with_media + without > 0 and wrong.is_empty(),
			("; ".join(wrong) if not wrong.is_empty() else "")
				if with_media + without > 0 else "no digital-video member was read, "
				+ "so this asserted nothing")
		# Both halves have to be *present* or the check above is one of them
		# passing while the other is a claim nobody tested. Said out loud rather
		# than asserted: a corpus with only one kind is a fact about the corpus.
		if with_media == 0 or without == 0:
			print("  (this corpus exercises only one half: %d with media, %d without)"
				% [with_media, without])
	h.complete(case)

	# ------------------------------------------------------------- the playhead
	var park_case := "%s: no video frame holds the playhead with nothing on the clock" % corpus
	h.begin(park_case)
	if targets.is_empty():
		h.check(
			"this corpus scores no video sprite, so no frame can park on one",
			true,
			"%d video member(s) exist but none is placed by a score" % members.size())
		h.complete(park_case)
		preview.queue_free()
		return

	var findings: Array[String] = []
	var thin: Array[String] = []
	var frozen: Array[String] = []
	var moved := 0
	for target_value in targets:
		var target: Dictionary = target_value
		var seen: Dictionary = await _visit(preview, target, settle, ticks)
		var played: Dictionary = seen.get("played", {})
		var line := "%-20s frame %-5d ch%-3d %-18s -> %s%s" % [
			str(target["movie"]), int(target["frame"]), int(target["channel"]),
			str(target["name"]), str(seen["verdict"]),
			"" if str(seen["detail"]) == "" else "  (%s)" % str(seen["detail"])]
		if float(played.get("rate", 0.0)) != 0.0:
			line += "  [rate %.2f, playhead +%d]" % [
				float(played["rate"]), int(played.get("advanced", 0))]
		if verbose or str(seen["verdict"]) == "parked-on-video":
			print("  " + line)
		if str(seen["verdict"]) == "parked-on-video":
			findings.append(line)
		elif str(seen["verdict"]) == "thin":
			thin.append(line)
		# The other half of the bargain `docs/DIGITAL_VIDEO.md` §3 strikes. A
		# frame whose movie **started** a video whose media **is on the disc** must
		# show the playhead move: `Check avi` is `movieTime >= FilmLen`, and a real
		# duration against a frozen playhead is `go(the frame)` for ever.
		#
		# Conditioned on both halves rather than on the target being a video,
		# because neither implies the other. A movie that never sets the rate is
		# not playing anything and has nothing to advance; a member with no media
		# is Director with no codec, and a playhead that moved there would be this
		# port inventing a position.
		if playable.has("%s#%d" % [str(target["movie"]), int(target["number"])]) 				and float(played.get("rate", 0.0)) != 0.0:
			if int(played.get("advanced", 0)) > 0:
				moved += 1
			else:
				frozen.append(line)

	if not thin.is_empty():
		print("")
		print("watches that could not make their ticks -- these judged nothing:")
		for line in thin:
			print("  " + line)

	h.check(
		"%d video frame(s) all released the playhead" % targets.size(),
		findings.is_empty(),
		"; ".join(findings) if not findings.is_empty()
			else "a frame that waits for a video that cannot start is a hang "
				+ "whatever the decoder situation")
	# A watch that never made its ticks judged nothing, and saying so is the
	# difference between a clean run and a blank one -- the dark-harness failure
	# `gate.sh` warns about.
	h.check(
		"every watch made enough ticks to judge",
		thin.is_empty(),
		"%d of %d did not" % [thin.size(), targets.size()])
	h.check(
		"%d started video(s) with media all advanced their playhead" % moved,
		frozen.is_empty(),
		"; ".join(frozen) if not frozen.is_empty()
			else ("a real duration against a frozen playhead turns Magic Hat's "
				+ "one-tick skip into `go(the frame)` for ever"
				if moved > 0 else "no target both had media and was started, so "
				+ "this asserted nothing about playback"))
	h.complete(park_case)
	preview.queue_free()


# ------------------------------------------------------------------- the watch


## Drive to one video frame and read what the playhead does there.
##
## Returns `{"verdict", "detail"}`, where the verdict is one of:
##
##   left              the playhead moved off the frame, or the video sprite left
##                     the stage. The healthy answer and the only common one.
##   held              it stayed, and the clock had a reason every tick -- a tempo
##                     delay, a transition, `pause`, a sound. Not a finding.
##   parked-on-video   it stayed, a video sprite stayed with it, and nothing
##                     explained either. The failure.
##   no-open           `go to movie` loaded no score.
##   thin              the watch could not make enough ticks to judge.
func _visit(preview: Node, target: Dictionary, settle: int, ticks: int) -> Dictionary:
	_reset_between(preview)
	preview.call("lingo_go_movie", str(target["movie"]), null)
	for _i in OPEN_FRAMES:
		await process_frame
	if preview.get("_score") == null:
		return {"verdict": "no-open", "detail": "no score after `go to movie`",
			"played": {"rate": 0.0, "advanced": 0}}
	await _run_ticks(preview, settle, OPEN_CAP_MS)

	# `lingo_go_frame` is 0-based (`current_frame` returns `_index`); the score's
	# own frame numbers and Lingo's are 1-based. One conversion, here.
	preview.call("lingo_go_frame", int(target["frame"]) - 1)
	await process_frame

	var clock = preview.get("_clock")
	var host = preview.get("_host")
	var start := Time.get_ticks_msec()
	var began := int(preview.get("_ticks"))
	var last := began
	var quiet := 0
	var frames: Dictionary = {}
	var video_ticks := 0
	var explained := 0
	var samples := 0
	# The playhead of the *video*, which is a different clock from the score's and
	# is the one `Check avi` reads. Sampled every tick so that "the movie started a
	# video and the video never moved" is a named finding rather than a hang the
	# caller has to diagnose from a timeout twenty seconds later.
	var channel := int(target["channel"])
	var rate_seen := 0.0
	var time_low := -1
	var time_high := 0
	while int(preview.get("_ticks")) - began < ticks \
			and Time.get_ticks_msec() - start < WATCH_CAP_MS:
		await process_frame
		var now := int(preview.get("_ticks"))
		if now == last:
			quiet += 1
			if quiet >= QUIET_STALL:
				break
			continue
		quiet = 0
		last = now
		samples += 1
		frames["%s#%d" % [str(preview.call("movie_name")),
			int(preview.call("current_frame"))]] = true
		if _video_on_stage(preview):
			video_ticks += 1
		if host != null:
			rate_seen = maxf(rate_seen,
				absf(float(host.get_sprite_prop(channel, "movierate"))))
			var at := int(host.get_sprite_prop(channel, "movietime"))
			time_low = at if time_low < 0 else mini(time_low, at)
			time_high = maxi(time_high, at)
		var reason := "" if clock == null else str(clock.call("hold_reason"))
		if host != null and (bool(host.playback_paused) or bool(host.stopped)):
			reason = "pause/halt"
		if reason != "":
			explained += 1

	# What the video did while the watch ran, carried on every verdict so the
	# caller can ask "did it play" separately from "did the playhead leave".
	var played := {"rate": rate_seen, "advanced": time_high - maxi(time_low, 0)}
	if samples < 4:
		return {"verdict": "thin", "played": played,
			"detail": "%d sample(s) in %d ms" % [
				samples, Time.get_ticks_msec() - start]}
	if frames.size() > 1:
		return {"verdict": "left", "played": played,
			"detail": "%d state(s)" % frames.size()}
	if video_ticks == 0:
		# One state, and no video on it -- the sprite left even though the
		# playhead did not, which is `puppetSprite 0` or a script hiding it. The
		# player is not looking at a dead video.
		return {"verdict": "left", "detail": "video sprite left the stage",
			"played": played}
	if explained >= samples:
		return {"verdict": "held", "detail": "the clock had a reason every tick",
			"played": played}
	return {"verdict": "parked-on-video", "played": played,
		"detail": "%d tick(s) on one frame, %d with a video sprite on stage, "
			% [samples, video_ticks] + "%d explained" % explained}


## Is any sprite on the stage right now showing a video member?
##
## Through the node's own effective-sprite read rather than the score record, for
## the reason `media.gd:_member_of_channel` gives at its own: a `puppetSprite`
## write that swapped the member is what the channel is actually showing.
func _video_on_stage(preview: Node) -> bool:
	var table = preview.get("_table")
	if table == null:
		return false
	for raw in preview.call("frame_sprites"):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		var m: Dictionary = table.get_member(
			int(sprite.get("cast_lib", 0)), int(sprite.get("cast_id", 0)))
		if m.is_empty():
			continue
		if _kind_of(m) != "":
			return true
	return false


## Is the file a member names actually on the disc?
##
## The witness the property surface is checked against, and it is deliberately
## **not** `preview/video.gd:media_path` -- asking the engine's own resolver
## whether the engine can find the file would assert nothing. This is the plain
## rule instead: beside the container that names it, then at the corpus root,
## with the separators Director allowed normalised. If the two ever disagree,
## this one is wrong and the check fails, which is the right way round -- a
## harness that follows the code it is testing cannot fail.
static func _media_on_disc(movie: String, paths: Paths, wanted: String) -> bool:
	if wanted == "":
		return false
	var tail := wanted.replace(":", "/").replace("\\", "/")
	while tail.begins_with("/"):
		tail = tail.substr(1)
	# `the fileName of member` answers a container path for a member with no link
	# (`preview/members.gd`), so an answer that is itself a container is "no media
	# file", not a media file that happens to be a movie.
	if ContainerName.ALL.has(tail.get_extension().to_lower()):
		return false
	var container := paths.resolve(movie)
	var bases: Array[String] = []
	if container != "":
		bases.append(container.get_base_dir())
	bases.append(str(paths.root))
	for base in bases:
		if base == "":
			continue
		if FileAccess.file_exists(base.path_join(tail)):
			return true
		if FileAccess.file_exists(base.path_join(tail.get_file())):
			return true
	return false


## `"digitalVideo"`, `"video-xtra"` or `""`, off the census's own table so the two
## tools cannot come to disagree about what counts as a video.
static func _kind_of(m: Dictionary) -> String:
	var code := int(m.get("type", 0))
	if code == Census.VIDEO_TYPE:
		return "digitalVideo"
	if code == Census.XTRA_TYPE \
			and Census.VIDEO_XTRAS.has(str(m.get("xtra_symbol", "")).to_lower()):
		return "video-xtra"
	return ""


## The same three things `liveness_sweep._reset_between` clears, and for the same
## reason: a `halt`, a `pause` or a left-open Movie-In-A-Window from the previous
## target would make this one's verdict about that one.
func _reset_between(preview: Node) -> void:
	var host = preview.get("_host")
	if host != null:
		host.stopped = false
		host.playback_paused = false
	preview.set_process(true)
	var windows: Dictionary = preview.get("_windows")
	if windows != null:
		for key in windows.keys():
			preview.call("lingo_forget_window", str(key), true)


func _run_ticks(preview: Node, count: int, cap_ms: int) -> void:
	var until := int(preview.get("_ticks")) + count
	var start := Time.get_ticks_msec()
	var last := int(preview.get("_ticks"))
	var quiet := 0
	while int(preview.get("_ticks")) < until and Time.get_ticks_msec() - start < cap_ms:
		await process_frame
		var now := int(preview.get("_ticks"))
		quiet = 0 if now != last else quiet + 1
		last = now
		if quiet >= QUIET_STALL:
			return


# ---------------------------------------------------------------- finding them


## Every video member the corpus can address and every frame that places one,
## found in **one** walk of the containers.
##
## Returns `{"members", "targets"}`. Merged rather than kept as two functions
## because opening a cast table on every container of a 124-container title is
## the whole cost of this harness: doing it twice took `piposh` past two minutes,
## which is the difference between an entry `gate.sh` can carry and one it
## cannot.
##
## A member's `movie` is a container that can reach it -- the one this harness
## will `go to movie` before asking about it -- and for a member in a shared cast
## that is whichever container linked it first. Any of them would do; what matters
## is that the member is addressable from the movie the question is asked in.
##
## A target is one per (movie, channel) and not per frame: a video sprite spans a
## run of frames and every one of them would otherwise be a target, which for a
## 200-frame intro is 200 watches of the same behaviour. The **first** frame of
## the run is the one the playhead would arrive at, and it is the one that carries
## the sprite's `beginSprite`.
func _scan(paths: Paths) -> Dictionary:
	var members: Array[Dictionary] = []
	var targets: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry in paths.containers():
		var path := paths.resolve(str(entry))
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
				if m.is_empty():
					continue
				var kind := _kind_of(m)
				if kind == "":
					continue
				var key := "%s#%d" % [
					str(table.cast_libs[lib].get("resolved_path", "")), int(number)]
				if seen.has(key):
					continue
				seen[key] = true
				members.append({
					"movie": str(entry), "file": path.get_file(),
					"lib": int(lib), "number": int(number),
					"name": str(m.get("name", "")), "kind": kind,
				})
		# A cast has no score, so there is nothing to place a sprite in one.
		var vwsc: Array = f.ids_of("VWSC")
		if not vwsc.is_empty() \
				and not ContainerName.CAST.has(str(entry).get_extension().to_lower()):
			var config = Config.new()
			var version := int(config.version) if config.read(f) else 0
			var score = Score.new()
			if score.parse(f.read_chunk(int(vwsc[0])), version):
				var seen_here: Dictionary = {}
				for i in score.frame_count:
					for sprite_value in score.frame(i).get("sprites", []):
						var sprite: Dictionary = sprite_value
						var m: Dictionary = table.get_member(
							int(sprite["cast_lib"]), int(sprite["cast_id"]))
						if m.is_empty() or _kind_of(m) == "":
							continue
						var channel := int(sprite["channel"])
						if seen_here.has(channel):
							continue
						seen_here[channel] = true
						targets.append({
							"movie": str(entry), "frame": i + 1, "channel": channel,
							"name": str(m.get("name", "")), "kind": _kind_of(m),
							# The member, so the watch can ask whether this target
							# is one of the ones the property surface said has
							# media. Without it the playback check would have to
							# re-derive that from the name, and two members can
							# share one.
							"lib": int(sprite["cast_lib"]),
							"number": int(sprite["cast_id"]),
						})
		table.close()
		f.close()
	return {"members": members, "targets": targets}
