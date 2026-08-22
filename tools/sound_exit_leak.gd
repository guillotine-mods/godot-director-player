extends SceneTree
## A run that exits **mid-sentence** leaves nothing behind. `bugs.md` 132.
##
##   godot --headless --path . --script tools/sound_exit_leak.gd
##   godot --headless --path . --script tools/sound_exit_leak.gd -- --child true
##
## `tools/exit_leaks.gd` asserts the same invariant for the boot path and cannot
## reach this one: its child "breaks out of its wait as soon as there is a score
## and never plays anything", which `gate.sh` already says beside the entry, and
## it then names the gap in as many words -- *a title whose first frames start a
## sound could red this entry on the `AudioStreamWAV` pair `movie_churn` leaks.*
## That pair was `bugs.md` 132, so the guard existed and was aimed elsewhere;
## this file is that guard aimed at it.
##
## ## What it is guarding
##
## `AudioStreamPlayer.playing` is not "this player holds a playback". Godot
## *pauses* a playback when its player leaves the tree, so during teardown a
## channel reads `playing=false, in_tree=false` while its playback is still
## registered with the `AudioServer`, and a paused playback that nothing will
## ever mix again keeps its stream alive past the ObjectDB check:
##
##   Leaked instance: AudioStreamWAV:...          - Reference count: 1
##   Leaked instance: AudioStreamPlaybackWAV:...  - Reference count: 1
##
## Reference count 1 on both is the diagnosis in one line: the player is gone and
## the server's playback list is the last owner. One pair per channel still
## sounding -- measured at 2 objects in 4 of 6 `movie_churn` runs, and at 6 on a
## probe that exited with three channels up.
##
## ## Two arms, and each covers what the other cannot
##
## **The child arm** is the only place the invariant is observable at all: the
## count is printed by the engine *after* the last line any script can run, so a
## second process has to read it. An absence check passes when nothing happened,
## so it is guarded twice -- the child's exit code, and a marker line naming how
## many channels were actually sounding when it quit. A child that booted a
## silent title, died early or found no corpus prints no leak line either, and
## without the marker that reads as a pass.
##
## **The in-process arm** asserts the mechanism, and is the one that fails
## unambiguously: it plays a sound, takes a `WeakRef` to the playback the server
## is holding, pulls the player out of the tree the way teardown does, and asks
## whether `stop_channel` gets the playback released. With the `if player.playing`
## guard this harness was written against, it cannot -- the pull sets `playing`
## false, the guard skips the stop, and the `WeakRef` never clears.
##
## Title-agnostic: it asks the configured title for a sound and says so if it did
## not get one. It never names a movie, a channel or a file.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")

## The two lines the engine prints at cleanup, matched on the wording that is
## stable across 4.x rather than on the whole sentence: the counts vary and the
## `(run with --verbose for details)` tail is dropped when `--verbose` is on.
## The same list as `exit_leaks.gd`, restated rather than shared because a
## harness that imports another harness's constant fails with it.
const LEAK_ALERTS := [
	"ObjectDB instances were leaked",
	"resources still in use",
]

## What the child prints once it has a sound running, and the only evidence the
## parent has that the exit it measured was an exit worth measuring.
const MARKER := "sound_exit_leak child:"

## Score steps the child drives looking for a sound. A ceiling, not a budget: it
## stops at the first sounding channel, and this only decides how long a silent
## title takes to be reported as one.
const SOUND_STEPS := 600

## Seconds the in-process arm waits for the `AudioServer` to let a stopped
## playback go. Wait on the condition under a ceiling (`bugs.md` 131): the loop
## ends the instant the `WeakRef` clears, so a busy machine makes this slower and
## cannot make it wrong.
const RELEASE_CEILING := 10.0


func _init() -> void:
	var args := Args.parse()
	if Args.flag(args, "child") or Args.text(args, "child", "") != "":
		await _child(args)
		return

	var h := Harness.new()
	await _mechanism(h)
	await _exiting_process(h, args)
	quit(h.finish("a run that exits while a sound is playing leaks nothing"))


# ------------------------------------------------------- the mechanism, here

## Play something, take the playback out of the tree, and see it released.
##
## The order is the order teardown uses, and every step of it is asserted rather
## than assumed -- particularly the trap in the middle, because a check that only
## looked at the end would pass for the wrong reason the day Godot changes what
## leaving the tree does to a playback.
func _mechanism(h) -> void:
	var case_name := "a playback survives its player leaving the tree, and `stop` releases it"
	h.begin(case_name)
	# One frame first: autoloads are added to the root by the tree, and a
	# `SceneTree` script's `_init` runs before that has happened. Looking without
	# it reads null and reports the audio director missing on every run.
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if not h.check("the audio director is up", audio != null):
		h.complete(case_name)
		return

	# Synthesised rather than loaded from the corpus: the subject is the
	# playback's lifetime, and a title that happens to ship no sound must not be
	# able to make this arm vacuous.
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(22050 * 2 * 4) # four seconds, so nothing ends on its own
	stream.data = data
	audio.call("play_stream", 1, "sound_exit_leak probe", stream)
	await process_frame

	var player: AudioStreamPlayer = (audio.get("_channels") as Dictionary).get(1)
	if not h.check("the probe reached a player", player != null):
		h.complete(case_name)
		return
	h.check("which is playing", player.playing,
		"nothing to release if the sound never started")
	var watched := _watch(player)
	var watch: WeakRef = watched[0]
	var label: String = watched[1]
	if not h.check("and holds a playback", label != "<none>"):
		h.complete(case_name)
		return

	# The trap, asserted in the middle so the arm cannot pass for the wrong
	# reason: leaving the tree makes `playing` false while the playback is still
	# held, which is exactly what an `if player.playing` guard reads.
	var parent: Node = player.get_parent()
	parent.remove_child(player)
	await process_frame
	h.check("out of the tree, `playing` reads false while the playback is still held",
		not player.playing and not _released(watch),
		"playing=%s, playback=%s" % [player.playing, label])

	audio.call("stop_channel", 1)
	var released := false
	var deadline := Time.get_ticks_msec() + int(RELEASE_CEILING * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _released(watch):
			released = true
			break
	h.check("stopping the channel releases it anyway", released,
		"%s, ceiling %.0f s -- a fail here means the AudioServer never let go"
			% [label, RELEASE_CEILING])
	parent.add_child(player)
	h.complete(case_name)


## `[WeakRef, printable name]` for a player's current playback.
##
## **In a function of its own, and every reader of the `WeakRef` below is too.**
## This harness spent an afternoon reporting that the `AudioServer` never let go
## of a stopped playback, and what was holding it was this file: a `Ref` returned
## by `get_stream_playback()` lands in the calling frame's temporary stack slot,
## and so does one formatted into a `"%s" % [...]` detail string, and a slot that
## is not written again keeps the object alive for as long as the frame does. The
## `WeakRef` then never clears and the harness blames the engine. Returning from a
## function drops the frame and every temporary in it, which is the only way to
## be sure the reference under test is the engine's and not the harness's --
## `porting-fidelity-verification`'s rule about distrusting the harness first,
## paid for in full.
func _watch(player: AudioStreamPlayer) -> Array:
	var live: AudioStreamPlayback = player.get_stream_playback()
	if live == null:
		return [weakref(null), "<none>"]
	return [weakref(live), "AudioStreamPlayback#%d" % live.get_instance_id()]


## Has it gone? Its own function for the reason `_watch` documents: the `get_ref()`
## result lives in this frame's temporaries and dies with the frame, so a poll
## cannot pin the object it is polling for.
func _released(watch: WeakRef) -> bool:
	return watch.get_ref() == null


# --------------------------------------------------- the invariant, out there

func _exiting_process(h, args: Dictionary) -> void:
	var case_name := "a process that exits mid-sound reports no leak"
	h.begin(case_name)
	var child := [
		"--headless", "--verbose",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/sound_exit_leak.gd", "--", "--child", "true",
	]
	# `--verbose` is not decoration: without it the engine prints the count and
	# not the instances, and a run that says only "2 leaked" cannot say whether
	# they were this file's subject or somebody else's.
	#
	# The corpus and the boot movie are forwarded the way the other
	# child-spawning harnesses forward them. A child that fell back to the
	# tracked config would boot whichever title somebody last pointed it at.
	for key in ["root", "boot", "file"]:
		if Args.text(args, key, "") != "":
			child.append_array(["--%s" % key, Args.text(args, key, "")])
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), child, out, true)
	var lines: Array[String] = []
	for chunk in out:
		for row in str(chunk).split("\n"):
			if str(row).strip_edges() != "":
				lines.append(str(row).strip_edges())

	h.check("the child exits cleanly", code == 0, "exit %d" % code)
	var marker := ""
	for row in lines:
		if row.contains(MARKER):
			marker = row
	h.check("the child got a sound out of this title and quit on top of it",
		marker != "" and not marker.contains("0 channel(s)"),
		marker if marker != "" \
			else "no \"%s\" line in %d line(s) of output" % [MARKER, lines.size()])
	for alert in LEAK_ALERTS:
		var found := ""
		for row in lines:
			if row.contains(alert):
				found = row
		h.check("the exiting process reports no \"%s\"" % alert, found == "", found)
	# The instances themselves, when there are any. The count alone cannot say
	# whose leak it is, and this entry is only entitled to claim the audio pair.
	var leaked: Array[String] = []
	for row in lines:
		if row.contains("Leaked instance:"):
			leaked.append(row)
	h.check("and names no leaked instance", leaked.is_empty(), " / ".join(leaked))
	h.complete(case_name)


# ------------------------------------------------------------------ the child

## Boot the real player, get a sound going, and quit on top of it.
##
## **Nothing is stopped or freed on the way out**, on purpose, and that is the
## whole point of the file: the exit under test is the one a player takes when
## they quit mid-sentence, and a `stop_all()` here would measure a path nobody
## runs. Prints one marker line and asserts nothing -- everything this arm
## measures is printed by the engine after the last GDScript statement, and only
## the parent can read it.
func _child(_args: Dictionary) -> void:
	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var audio: Node = preview.get("_audio")
	var sounding := 0
	var steps := 0
	while steps < SOUND_STEPS:
		steps += 1
		preview.call("_advance")
		sounding = _sounding(audio)
		if sounding > 0:
			break
	print("%s %d channel(s) sounding after %d score step(s)" % [MARKER, sounding, steps])
	quit(0)


## How many numbered channels are making a noise right now, asked through the
## same `soundBusy` every line of speech in this corpus waits on.
func _sounding(audio: Node) -> int:
	if audio == null:
		return 0
	var n := 0
	for ch in range(1, 9):
		if bool(audio.call("sound_busy", ch)):
			n += 1
	return n
