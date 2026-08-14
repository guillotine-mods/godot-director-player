extends SceneTree
## `play_file`'s "it is already playing, leave it alone" guard must ask the same
## question `soundBusy` answers -- or a channel goes silent for the rest of the
## movie and nothing recovers it.
##
##   godot --headless --path . --script tools/sound_replay_guard.gd
##   godot --headless --path . --script tools/sound_replay_guard.gd -- --channel 6
##
## Two guards, one channel. `sound_busy` is `player.playing` **and**
## `now < _channel_until`, the ceiling that keeps a slow audio device from
## stretching every speech wait in the corpus (`docs/bugs-closed.md` 90).
## `play_file`'s idempotence guard was `existing.playing` alone, and the two
## stopped agreeing the moment the ceiling was added.
##
## The failure that gap produces is not a glitch, it is permanent. Once the
## ceiling passes while the device is still draining the stream, the channel is
## **free** to the movie and **already playing** to the replay guard. The movie
## asks for the same file again; the guard returns early; `_start` never runs, so
## `_channel_until` is never re-armed; and `soundBusy` answers false for ever.
## Every later replay of that file takes the same early return, so nothing in the
## movie can climb out of it.
##
## Found in ordinary play of `itamar-magichat`, twice -- `MAINMENU_M.MP3` on the
## tools screen and `ALBUM_M.MP3` on magics. Magic Hat's `PlayMusic` busy-waits
## three seconds on `soundBusy` and then raises
## `alert("Sound file X is missing !")` for a file that is present and indexed,
## and `lingo_alert` sets `_paused`, so the movie stops dead behind a modal
## naming the wrong cause. The player sees a hang and a lie about their install.
##
## ## Why this is asserted by forcing the ceiling rather than by waiting for it
##
## The natural repro is a race: play something, wait for the ceiling to pass while
## the device is still draining, then replay. Whether that window opens at all
## depends on the output device, the stream's length and the machine's load, so a
## harness built on it is green on a fast machine for the wrong reason -- which is
## exactly the shape of the macOS-runner problem that produced the ceiling in the
## first place. So the window is **created** here, by moving `_channel_until` into
## the past on a channel that is genuinely still playing. That is the state the
## race arrives at, reached deterministically.
##
## The last check is the one that would have caught the original: a channel in
## that state must be recoverable *by the movie*, using only what a movie can do
## -- ask for the same file again.
##
## Title-agnostic: the file is whatever the configured corpus indexed.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## Long enough that the channel is still playing several frames after the ceiling
## is forced past, short enough to be worth a gate entry.
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
	await _the_guards_agree(h, audio)
	quit(h.finish("the replay guard and `soundBusy` ask the same question"))


func _the_guards_agree(h: Harness, audio: Node) -> void:
	var args := Args.parse()
	var channel := Args.number(args, "channel", 6)
	var title := "a channel whose ceiling has passed can be restarted by the movie"
	h.begin(title)

	var chosen := _a_file(audio)
	if chosen.is_empty():
		# Not a pass over an empty set. A corpus that cannot express the rule is
		# reported as a failure to express it, never as the rule holding.
		h.check("the configured game holds a sound to play", false,
			"nothing indexed, or nothing over %.2fs" % FLOOR_SECONDS)
		h.complete(title)
		return
	var name := str(chosen["key"]) + ".aif"
	print("   %s: %.2fs on channel %d" % [str(chosen["key"]), float(chosen["length"]), channel])

	audio.call("stop_channel", channel)
	audio.call("play_file", channel, name)
	await process_frame
	if not h.check("the sound started", audio.call("sound_busy", channel), name):
		h.complete(title)
		return

	# Create the window rather than wait for it. `_channel_until` is the ceiling
	# `sound_busy` reads; pushing it into the past is precisely the state a slow
	# device arrives at, and it takes no time to get there.
	var until: Dictionary = audio.get("_channel_until")
	var ch := maxi(1, channel)
	if not h.check("the channel armed a ceiling to move", until.has(ch),
			"no `_channel_until` entry: the stream reported no length"):
		h.complete(title)
		return
	until[ch] = Time.get_ticks_msec() - 1000

	var player: AudioStreamPlayer = audio.get("_channels").get(ch)
	h.check("the device is still draining the stream", player != null and player.playing,
		"this is the whole premise: the ceiling has passed and the sound has not")
	h.check("so the movie is told the channel is free",
		not audio.call("sound_busy", channel),
		"`soundBusy` reads the ceiling, and the ceiling is in the past")

	# What a movie does next, and the only thing it *can* do: ask for the same
	# file again. Before the fix this took `play_file`'s early return, `_start`
	# never ran, and the channel stayed silent for the rest of the movie.
	audio.call("play_file", channel, name)
	await process_frame
	h.check("asking for it again restarts it", audio.call("sound_busy", channel),
		"if this fails the channel is wedged: no later replay can reach `_start` either")

	# And the recovery is real rather than a one-frame flicker -- the ceiling was
	# re-armed into the future, which is what makes the *next* poll right too.
	var after: Dictionary = audio.get("_channel_until")
	h.check("and re-arms the ceiling ahead of now",
		after.has(ch) and int(after[ch]) > Time.get_ticks_msec(),
		"a replay that plays but leaves the ceiling behind is the same bug again")

	audio.call("stop_channel", channel)
	h.complete(title)


func _a_file(audio: Node) -> Dictionary:
	# The index is lazy — `_ensure_index` is a one-shot latch the first *play*
	# trips, so reading `_path_index` before anything has played sees an empty
	# dictionary and every check below would report "the corpus has no sound".
	# `tools/sound_rate.gd` and `tools/sound_wait.gd` both call this for the same
	# reason.
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
