extends SceneTree
## Does a sound take as long to finish as it lasts? The clock behind `soundBusy`.
##
##   godot --headless --path . --script tools/sound_rate.gd
##   godot --headless --path . --script tools/sound_rate.gd -- --tolerance 1.5
##
##   --tolerance F  how many times its own length a sound may take (default 2.0)
##   --channel N    the channel to play on (default 6, as `sound_wait.gd`)
##
## `tools/sound_wait.gd` asserts that a channel is busy if and only if a sound the
## script asked for is playing on it. That is the *logic* of `soundBusy`, and it
## is only half of what a movie depends on. The other half is the **clock**: a
## line of speech that lasts four seconds must stop answering `soundBusy` in about
## four seconds, because that is the only thing a script polling it is measuring.
##
##     on exitFrame
##       if soundBusy(1) then go(marker(0))
##     end
##
## `BehaviorScript 250`'s counterpart, and the shape most of this corpus's speech
## is built on: the talking animation loops back to its own marker for as long as
## the channel is busy. Nothing in the movie sets a duration -- the sound *is* the
## duration -- so a `soundBusy` that runs slow does not make the speech slow, it
## makes the **playhead** slow, and every frame budget downstream of it is wrong
## by the same factor.
##
## ## Why this is not a restatement of `sound_wait.gd`
##
## `soundBusy` here is `AudioStreamPlayer.playing`, and that flag is retired by
## the **audio server**, when the mix thread has consumed the stream. So it is
## paced by the output device's throughput and not by the wall clock. On hardware
## the two are the same thing to within a fraction of a percent, which is why this
## rule can sit unasserted for a long time and look like an identity.
##
## They come apart where there is no hardware. A driver that mixes slower than
## real time -- because it sleeps a whole buffer between callbacks, or because the
## machine is a throttled VM, or because there is no device to pull from it at all
## -- retires the flag late, and every `soundBusy` poll in the corpus waits by
## that factor. This was measured: `puppet_persists` passed on a developer Mac and
## on a Windows runner and failed on every macOS runner, at an *identical*
## score-tick rate, because a talk clip that finishes in 295 score ticks needed
## more than 400 there. The playhead was not slow. The sound was.
##
## Asserted as a ratio rather than as a duration, because the length of the file
## is the only reference that is the same on every machine and in every corpus.
## Generous on purpose -- this catches a clock that is wrong by a factor, not one
## that is late by a buffer -- and it prints the measurement either way, because
## the number is the finding and a green check that only says "under 2.0" cannot
## be compared against the next machine's.
##
## Title-agnostic: the file comes from whatever the configured corpus indexed.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Ample. The rule is about a clock that is wrong by a factor: the macOS runner
## this was written for came in at least 1.38x slow on the movie that found it,
## and a healthy machine measures within a few percent of 1.0. Anything between
## is a device that cannot keep up, which is the fault being named.
const TOLERANCE := 2.0

## Long enough that the measurement is not dominated by the poll interval, and
## short enough to be worth a gate entry. A sound under this is played whole; the
## budget below is what a longer one is cut off at.
const FLOOR_SECONDS := 0.35


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
	await _a_sound_ends_when_it_ends(h, audio)
	quit(h.finish("a sound stops answering `soundBusy` in about its own length"))


## Play the longest short file the corpus has, and time the flag.
##
## Timed off the wall clock and not off `process_frame`, and the distinction is
## the whole measurement: a frame count would be measuring the same thing twice.
## The engine's own frame rate is what a headless run varies most between
## machines, and it is *not* what a movie's `soundBusy` poll is paced by.
func _a_sound_ends_when_it_ends(h: Harness, audio: Node) -> void:
	var args := Args.parse()
	var channel := Args.number(args, "channel", 6)
	var tolerance := float(Args.text(args, "tolerance", str(TOLERANCE)).to_float())
	if tolerance <= 0.0:
		tolerance = TOLERANCE
	var title := "a sound releases the channel in about the time it lasts"
	h.begin(title)

	var chosen := _a_short_file(audio)
	if chosen.is_empty():
		# Not a pass over an empty set: say so and fail, the way every other
		# harness here does when its corpus cannot express the rule.
		h.check("the configured game holds a sound long enough to time", false,
			"nothing indexed, or nothing over %.2fs" % FLOOR_SECONDS)
		h.complete(title)
		return
	var length := float(chosen["length"])
	print("   %s: %.2fs" % [str(chosen["key"]), length])

	audio.call("stop_channel", channel)
	audio.call("play_file", channel, str(chosen["key"]) + ".aif")
	await process_frame
	if not h.check("the sound started", audio.call("sound_busy", channel),
			str(chosen["key"])):
		h.complete(title)
		return

	# The budget is the assertion's own tolerance and a little over, so a device
	# that has stalled outright is reported as a ratio like everything else
	# rather than by hanging until the gate's ceiling kills the entry and loses
	# the number. `playhead_escape.gd` makes the same trade.
	var budget := length * (tolerance + 1.0) + 2.0
	var start := Time.get_ticks_msec()
	var waited := 0.0
	var polls := 0
	while audio.call("sound_busy", channel):
		await process_frame
		polls += 1
		waited = float(Time.get_ticks_msec() - start) / 1000.0
		if waited > budget:
			break
	var ratio := waited / length
	# The poll count is here to say the measurement is not an artifact of its own
	# sampling: a handful of polls over a short sound would make the ratio a
	# statement about the frame rate, which is the thing this is distinguishing
	# itself from.
	print("   took %.2fs for %.2fs of sound: %.2fx real time, over %d poll(s)"
		% [waited, length, ratio, polls])

	h.check("the sound stopped answering `soundBusy` at all", not audio.call(
		"sound_busy", channel), "after %.2fs of a %.2fs budget" % [waited, budget])
	# One-sided. Finishing *early* is the other failure in this family -- the
	# next line spoken over the last -- and `sound_wait.gd` already owns it from
	# the logic side; asserting a lower bound here would fail on a device that
	# is merely ahead of its latency, which no movie can observe.
	h.check("and it took no more than %.1fx its own length" % tolerance,
		ratio <= tolerance,
		"%.2fx: every `soundBusy` poll in the corpus waits by this factor"
			% ratio)
	audio.call("stop_channel", channel)
	h.complete(title)


## Some indexed file with a real length, as `{key, length}`, or `{}`.
##
## The shortest one over the floor rather than the first: this runs in a gate, the
## corpus holds files of half a minute, and the rule does not need one.
func _a_short_file(audio: Node) -> Dictionary:
	audio.call("_ensure_index")
	var index: Dictionary = audio.get("_path_index")
	var best := {}
	for key in index:
		var stream: AudioStream = audio.call("_load_stream", str(index[key]))
		if stream == null:
			continue
		var length := stream.get_length()
		if length < FLOOR_SECONDS:
			continue
		if best.is_empty() or length < float(best["length"]):
			best = {"key": str(key), "length": length}
		if not best.is_empty() and float(best["length"]) < FLOOR_SECONDS * 2.0:
			break
	return best
