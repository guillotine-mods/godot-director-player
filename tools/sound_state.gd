extends SceneTree
## Sound as the scripts observe it: does a channel report busy, stop being busy,
## and remember its volume?
##
##   godot --headless --script tools/sound_state.gd
##   godot --headless --script tools/sound_state.gd -- --stem clik1
##
## Sound is this game's clock. 245 `soundBusy` calls gate speech, cut scenes and
## the walk machine, so every one of them is a question about *engine state*, not
## about whether anything is audible: a channel that never reports busy lets a
## room talk over itself, and one that never stops reports a wait that never
## ends. Those are the two failures this asserts against, in that order.
##
## **Headless has no audio device, and that turns out not to matter here — but
## only because it was measured.** Godot's `Dummy` driver still mixes on a real
## clock, so an `AudioStreamPlayer` started headless does advance and does clear
## `playing` at the end of the stream; case 1 asserts exactly that, and prints
## the elapsed time against the stream's own length so a driver that ever stops
## advancing shows up as a specific number rather than as a mysterious hang. The
## consequence for every other harness is `tools/lib/driver.gd`'s: real frames
## must be awaited, because a synthetic tick loop advances the runtime's clock
## and not the audio server's (bugs.md 22).
##
## Cases 2 and 3 go through the real compiler and interpreter onto the real
## `lingo/lingo_host.gd`, because the gap they cover was a *missing host method*
## (bugs.md 27): the parser was right and the interpreter routed correctly, and
## `_host_call` discarded the write because the host had no `set_sound_prop`. A
## check that a setter and a getter agree would have passed throughout. These
## assert the state `AudioDirector` ends up in.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Compiler := preload("res://lingo/compile/lingo_compiler.gd")
const Interpreter := preload("res://lingo/lingo_interpreter.gd")
## `lingo/lingo_host.gd` is loaded, not preloaded, and the difference is not
## cosmetic: it names the `GameState` autoload at class scope, and a `const`
## preload compiles this whole file before the autoloads are in the tree, which
## fails with "Identifier not found: GameState" in a file nobody touched.
const HOST_PATH := "res://lingo/lingo_host.gd"

## An effect from the game's own FX folder, long enough that "still playing" and
## "finished" are distinguishable. Named here rather than discovered because the
## case needs a *known* duration to compare against, and a harness is allowed to
## know the corpus it asserts against.
const DEFAULT_STEM := "boom"
## How much longer than the stream itself the channel may stay busy before the
## case gives up. Generous: this is a liveness bound, not a timing assertion.
const OVERRUN_MS := 4000


## `_initialize`, not `_init`: autoloads are not in the tree yet when a
## `--script` tool is constructed, and `AudioDirector` is the whole subject here.
func _initialize() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var audio := root.get_node_or_null("AudioDirector")
	if audio == null:
		print("AudioDirector autoload is not present")
		quit(1)
		return
	# One frame before anything plays: the autoload node exists at `_initialize`
	# but the tree has not iterated, and `AudioStreamPlayer.play()` on a node
	# that is not yet inside the tree is refused outright.
	await process_frame

	await _busy_follows_the_stream(h, audio, Args.text(args, "stem", DEFAULT_STEM))
	_volume_reaches_the_channel(h, audio)
	_sound_level_reaches_the_bus(h, audio)
	await _stop_clears_busy(h, audio)
	_a_missing_binding_is_reported(h, audio)
	quit(h.finish("what a script can observe about a sound channel"))


## Records what a host is asked for and deliberately implements no sound
## properties — the state `lingo/lingo_host.gd` was in for bugs.md 27.
class DeafHost extends RefCounted:
	var interpreter: Object = null

	func call_builtin(_name: String, _args: Array) -> Variant:
		return 0

	func owns_global(_name: String) -> bool:
		return false

	func get_global(_name: String) -> Variant:
		return 0

	func set_global(_name: String, _value: Variant) -> void:
		pass

	func is_native_handler(_name: String) -> bool:
		return false


## Case 1. The invariant every `soundBusy` wait loop rests on, both halves.
func _busy_follows_the_stream(h: Harness, audio: Node, stem: String) -> void:
	var title := "a channel reports busy while a sound plays and stops after it"
	h.begin(title)

	var path: String = audio.resolve_path(stem)
	if not h.check("the fixture sound resolves", path != "", "%s -> %s" % [stem, path]):
		h.complete(title)
		return
	var stream: AudioStream = audio.call("_load_stream", path)
	var length := stream.get_length() if stream != null else 0.0
	if not h.check("it decodes to a stream with audio in it", length > 0.0, "%.2fs" % length):
		h.complete(title)
		return

	audio.play_file(3, stem)
	# One frame, because `AudioStreamPlayer.play()` does not take effect until the
	# audio server next mixes: asserting on the same frame reads the state before
	# the sound started and fails for a reason that has nothing to do with sound.
	await process_frame
	h.check("busy immediately after `sound playFile`", audio.sound_busy(3),
		"channel 3, %s" % stem)

	var started := Time.get_ticks_msec()
	var budget := int(length * 1000.0) + OVERRUN_MS
	while audio.sound_busy(3) and Time.get_ticks_msec() - started < budget:
		await process_frame
	var elapsed := Time.get_ticks_msec() - started
	h.check("not busy once the stream has run out", not audio.sound_busy(3),
		"%d ms elapsed against a %.0f ms stream, budget %d ms" % [
			elapsed, length * 1000.0, budget,
		])
	# The point of printing this is the headless audio question: a Dummy driver
	# that did not advance would sit here for the whole budget and then fail, and
	# one that reported "finished" instantly would pass the check above while
	# breaking every wait loop in the game by ending it early.
	h.check("it ran for about as long as the sound is",
		elapsed > int(length * 500.0), "%d ms for a %.0f ms stream" % [elapsed, length * 1000.0])
	h.complete(title)


## Case 2. `set the volume of sound N`, through the real interpreter and the real
## game host — the 66 statements bugs.md 27 was about.
func _volume_reaches_the_channel(h: Harness, audio: Node) -> void:
	var title := "`the volume of sound N` reaches the channel and reads back"
	h.begin(title)

	audio.set_channel_volume(2, 255)
	audio.set_channel_volume(3, 255)
	# Verbatim shapes from the corpus: a plain write, and the one
	# read-modify-write, which fails differently — it needs its own last write
	# back, so a host that accepted the write and answered a constant would
	# still step the loop wrong.
	var run := _run("""
on setvolumes
  set the volume of sound 2 to 130
  set the volume of sound 3 to the volume of sound 3 - 20
end
""", "setvolumes")
	if not h.check("the fixture compiles", run["ok"], str(run.get("error", ""))):
		h.complete(title)
		return

	h.check("a literal write lands on the channel", audio.channel_volume(2) == 130,
		"channel 2 is %d" % audio.channel_volume(2))
	h.check("a read-modify-write reads its own previous value",
		audio.channel_volume(3) == 235, "channel 3 is %d" % audio.channel_volume(3))

	# Director's 0-255 is linear in amplitude, so half must be about -6 dB and
	# not about -0.1 dB. The player is what actually carries it, and a host that
	# stored the number without applying it would pass the two checks above.
	audio.set_channel_volume(4, 128)
	var player: AudioStreamPlayer = audio.call("_ensure_player", 4)
	h.check("the channel's player carries the volume as a linear-to-dB curve",
		player != null and absf(player.volume_db - linear_to_db(128.0 / 255.0)) < 0.01,
		"%.2f dB" % (player.volume_db if player != null else 0.0))
	audio.set_channel_volume(4, 255)

	# A channel nobody has written starts at Director's default rather than
	# silent: `the volume of sound 1` is read before it is ever set.
	h.check("an untouched channel answers 255", audio.channel_volume(9) == 255,
		"channel 9 is %d" % audio.channel_volume(9))
	h.complete(title)


## Case 3. `the soundLevel`, 0-7 — the system volume, which is a different thing
## from a channel's and was bound on only one of the two hosts.
func _sound_level_reaches_the_bus(h: Harness, audio: Node) -> void:
	var title := "`the soundLevel` reaches the master bus and reads back"
	h.begin(title)

	var run := _run("""
on setlevel
  set the soundLevel to 4
end
""", "setlevel")
	if not h.check("the fixture compiles", run["ok"], str(run.get("error", ""))):
		h.complete(title)
		return
	h.check("the write lands", audio.sound_level == 4, "soundLevel is %d" % audio.sound_level)
	h.check("the master bus followed it",
		absf(AudioServer.get_bus_volume_db(0) - linear_to_db(4.0 / 7.0)) < 0.01,
		"%.2f dB" % AudioServer.get_bus_volume_db(0))

	# The slider handler reads it back on every frame to place the knob, so a
	# read that does not agree with the write leaves the control where it was.
	var interp: Object = run["interp"]
	var back: Variant = interp.host.get_system_prop("soundlevel")
	h.check("a read answers the write", int(back) == 4, "read %s" % str(back))

	audio.set_sound_level(7)
	h.check("restoring 7 puts the bus back to unity",
		absf(AudioServer.get_bus_volume_db(0)) < 0.01,
		"%.2f dB" % AudioServer.get_bus_volume_db(0))
	h.complete(title)


## Case 4. `sound stop N` — 69 statements, and the only other verb the corpus
## uses. What it has to do is end the wait, not merely silence the speaker.
func _stop_clears_busy(h: Harness, audio: Node) -> void:
	var title := "`sound stop` ends the wait, not just the sound"
	h.begin(title)

	var run := _run("""
on cutit
  global soundspath
  sound playFile 2, soundspath & "clik1.aif"
end
""", "cutit")
	if not h.check("the fixture compiles", run["ok"], str(run.get("error", ""))):
		h.complete(title)
		return
	await process_frame
	if not h.check("the line started", audio.sound_busy(2), "channel 2"):
		h.complete(title)
		return

	var stop := _run("""
on stopit
  sound stop 2
end
""", "stopit")
	h.check("the stop fixture compiles", stop["ok"], str(stop.get("error", "")))
	await process_frame
	h.check("the channel is no longer busy", not audio.sound_busy(2), "channel 2")
	h.complete(title)


## Case 5. The other half of bugs.md 27, and the reason it went unnoticed for so
## long: a host that does not implement a property method used to be
## indistinguishable from one that handled the call. This is what keeps case 2
## honest — it demonstrates the failure the fix removed, on the same statement,
## rather than asserting that a setter and a getter agree.
func _a_missing_binding_is_reported(h: Harness, audio: Node) -> void:
	var title := "a host with no sound binding is reported rather than silent"
	h.begin(title)

	audio.set_channel_volume(2, 255)
	var compiler := Compiler.new()
	var script := compiler.compile_source("""
on setvolume
  set the volume of sound 2 to 90
end
""", "SoundState")
	if not h.check("the fixture compiles", not script.is_empty(),
			"line %d: %s" % [compiler.error_line, compiler.error]):
		h.complete(title)
		return

	var host := DeafHost.new()
	var interp := Interpreter.new(host)
	host.interpreter = interp
	interp.call_handler("setvolume", [], script)

	h.check("the write reached nothing", audio.channel_volume(2) == 255,
		"channel 2 is %d" % audio.channel_volume(2))
	var reported := interp.diagnostics.names_in("unbound_name")
	h.check("and the interpreter said so", reported.has("host.set_sound_prop"),
		str(reported))
	h.complete(title)


## Compiles and runs one handler against the real game host. `null` runtime: none
## of these statements reach navigation, and standing up a `DirectorRuntime`
## would make the case depend on a movie loading.
func _run(source: String, handler: String) -> Dictionary:
	var compiler := Compiler.new()
	var script := compiler.compile_source(source, "SoundState")
	if script.is_empty():
		return {"ok": false, "error": "line %d: %s" % [compiler.error_line, compiler.error]}
	var host: Object = load(HOST_PATH).new(null)
	var interp := Interpreter.new(host)
	host.interpreter = interp
	interp.globals["soundspath"] = ""
	interp.call_handler(handler, [], script)
	if not interp.errors.is_empty():
		return {"ok": false, "error": "; ".join(interp.errors), "interp": interp}
	return {"ok": true, "interp": interp, "host": host}
