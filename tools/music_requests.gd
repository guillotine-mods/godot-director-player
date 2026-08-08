extends SceneTree
## What does a room actually ask its music channel for, and does it arrive?
##
##   godot --headless --path . --script tools/music_requests.gd -- --root piposh --movie PIPDATA/DAY1.dir
##   godot --headless --path . --script tools/music_requests.gd -- --root piposh-en --movie pipdata/DAY1.dir
##   godot --headless --path . --script tools/music_requests.gd -- --channel 2 --frames 400
##
## Background music in this corpus is not a score sound and not a loop flag. It is
## a script polling its own channel every frame:
##
##     on exitFrame
##       if not soundBusy(2) then sound playFile 2, effectspath2 & whichmus
##     end
##
## So "the music does not play" has four distinct causes that look identical from
## the player's chair -- the path globals are unset, the *name* global is unset,
## the composed request names a file the root does not hold, or the file is there
## and the decoder refused it. This prints which one, per channel, by watching the
## requests the movie itself emits.
##
## **Real frames, not a step loop.** `soundBusy` is answered by the mixer, which
## runs on wall-clock; a synthetic `for i in N: preview.call("_advance")` loop
## advances score time and not audio time, so the guard above holds for ever and
## the probe measures its own loop instead of the movie (AGENTS.md, and bugs.md 22
## twice). Every wait here is `await process_frame`.
##
## Title-agnostic: no movie, global or filename is named, and the two globals
## printed are discovered from the request rather than assumed.

const Args := preload("res://tools/lib/args.gd")


func _init() -> void:
	var args := Args.parse()
	var channel := Args.number(args, "channel", 2)
	var frames := Args.number(args, "frames", 400)

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if audio == null:
		print("no AudioDirector; this has to run in the project")
		quit(1)
		return

	var movie := Args.text(args, "movie", "")
	if movie != "":
		preview.call("lingo_go_movie", movie, null)
	# Settle: the room's own entry scripts are what set the path and name globals,
	# and they run on frames rather than on the `go` itself.
	for i in 30:
		await process_frame
	var label := Args.text(args, "label", "")
	if label != "":
		preview.call("lingo_go_label", label)
		for i in 10:
			await process_frame

	print("movie   : %s" % str(preview.call("movie_name")))
	print("channel : %d" % channel)
	print("")

	# request -> {"played": bool, "seen": int}
	var requests: Dictionary = {}
	var order: Array[String] = []
	var busy_frames := 0
	for i in frames:
		await process_frame
		var request := str(audio.call("channel_source", channel))
		if request == "":
			continue
		var busy: bool = audio.call("sound_busy", channel)
		if busy:
			busy_frames += 1
		if not requests.has(request):
			requests[request] = {"played": false, "seen": 0}
			order.append(request)
		requests[request]["seen"] = int(requests[request]["seen"]) + 1
		if busy:
			requests[request]["played"] = true

	if order.is_empty():
		print("the room asked channel %d for nothing in %d frames" % [channel, frames])
	for request in order:
		var row: Dictionary = requests[request]
		var resolved := str(audio.call("resolve_path", request))
		print("  %-6s %s" % ["PLAYS" if row["played"] else "SILENT", request])
		print("         resolves to %s   (%d frame(s))" % [
			resolved if resolved != "" else "<nothing on disc>", int(row["seen"])])

	print("")
	print("channel %d was audible on %d of %d frame(s)" % [channel, busy_frames, frames])

	# The globals the request was built from, found by name in what the room left
	# set rather than named here -- a title that composes its music path from other
	# globals still prints the ones that carry a path or a sound name.
	var interp = preview.get("_interpreter")
	if interp != null:
		var globals: Dictionary = interp.get("globals")
		var keys: Array = globals.keys()
		keys.sort()
		var shown: Array[String] = []
		for key in keys:
			var value := str(globals[key])
			if value.to_lower().contains(".aif") or value.contains("\\") \
					or value.contains(":") or value.contains("/"):
				shown.append("%s = %s" % [key, value])
		if not shown.is_empty():
			print("")
			print("globals that carry a path or a sound name:")
			for line in shown:
				print("  %s" % line)

	quit(0)
