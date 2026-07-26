extends SceneTree
## Phase 6: does the interpreted Lingo reproduce what the export lifted?
##
## The export's per-sprite `on_click` is the only independent record of what this
## game does when you click something. It was produced by a different tool, from
## the same originals, years earlier. So it is a genuine oracle: for every
## clickable sprite the interpreter should reach the same navigation target and
## the same sounds.
##
##   godot --headless --script tools/lingo_converge.gd
##   godot --headless --script tools/lingo_converge.gd -- DAY1
##
## Agreement is reported as a fraction. Disagreements are printed with both
## sides so they can be read against the Lingo.
##
## The sweep dispatches real handlers, so anything that navigates has to be
## captured rather than performed or the sweep leaves the movie it is measuring.
## `open(window(...))` did not honour `record`, and the first save button it
## dispatched took it into SAVELOAD: DAY1 then read 14 reached of 112 instead of
## 112 of 112, and every movie after the jump was measured against the wrong
## score. Anything added to the host that changes movie must respect `record`.

## Channels the port drives natively rather than through the interpreter: the
## eight inventory slots (InventoryDrag plus data/inventory_drops.json) and the
## two save buttons the SAVELOAD intercept owns. A script producing no nav for
## these is correct, not a divergence.
const NATIVE_CHANNELS := [96, 97, 103, 104, 105, 106, 107, 108, 109, 110]

var _fails := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).strip_edges() != "":
			only = str(arg).to_upper()

	var runtime: RefCounted = load("res://director/director_runtime.gd").new()
	if runtime.boot() != OK:
		print("boot failed")
		quit(1)
		return

	var movies := ["DAY1", "NIGHT1", "HOTEL1", "SEA1", "AIR1"]
	if only != "":
		movies = [only]

	var grand := {"cases": 0, "reached": 0, "agree": 0, "partial": 0, "differ": 0,
		"walk": 0, "native": 0}
	print("%-9s %8s %8s %8s %8s %8s %8s" % ["movie", "cases", "reached", "agree", "partial", "differ", "walk"])
	for movie in movies:
		var row := _check_movie(runtime, movie)
		for key in grand.keys():
			grand[key] += int(row.get(key, 0))
		print("%-9s %8d %8d %8d %8d %8d %8d" % [
			movie, row.cases, row.reached, row.agree, row.partial, row.differ, row.walk])

	var reached: int = int(grand.reached)
	print("\n%d distinct clickable cases, %d reached by an interpreted script (%.1f%%)" % [
		grand.cases, reached,
		0.0 if grand.cases == 0 else reached * 100.0 / int(grand.cases)])
	if reached > 0:
		var accounted: int = (int(grand.agree) + int(grand.partial) + int(grand.walk)
			+ int(grand.native))
		print("  of those reached: %d agree, %d partly agree, %d deferred walks, %d native, %d differ" % [
			grand.agree, grand.partial, grand.walk, grand.native, grand.differ])
		print("  accounted for: %d/%d (%.1f%%)" % [
			accounted, reached, accounted * 100.0 / reached])
	for line in _fails:
		print("  %s" % line)
	quit(0)


func _check_movie(runtime: RefCounted, movie: String) -> Dictionary:
	var row := {"cases": 0, "reached": 0, "agree": 0, "partial": 0, "differ": 0,
		"walk": 0, "native": 0}
	if runtime.loader.load_movie(movie) != OK:
		return row
	var engine: RefCounted = load("res://lingo/lingo_engine.gd").new(runtime)
	engine.prepare_movie(movie)
	var host: RefCounted = engine.host

	# One case per (channel, exported signature): the same sprite over a run of
	# frames is the same behaviour, and there are 90k sprite-frames in total.
	var seen := {}
	var frames: Array = runtime.loader.frames
	for frame_index in frames.size():
		var frame: Dictionary = frames[frame_index]
		for sprite in frame.get("sprites", []):
			if typeof(sprite) != TYPE_DICTIONARY:
				continue
			var on_click: Variant = (sprite as Dictionary).get("on_click", null)
			if typeof(on_click) != TYPE_DICTIONARY:
				continue
			var channel := int((sprite as Dictionary).get("channel", 0))
			var want: Dictionary = _export_signature(on_click)
			var key := "%d|%s|%s" % [channel, want.navs, want.sounds]
			if seen.has(key):
				continue
			seen[key] = true
			row.cases += 1

			runtime.frame_index = frame_index
			if not engine.has_any_handler_for(channel, frame_index, "mouseUp"):
				continue
			row.reached += 1
			host.begin_record()
			engine.dispatch_sprite_event("mouseUp", channel, frame_index)
			var got_navs := _normalise(host.recorded_navs)
			var got_sounds := _normalise(host.recorded_sounds)
			var nav_ok: bool = want.navs.is_empty() or _overlaps(got_navs, want.navs)
			var snd_ok: bool = want.sounds.is_empty() or _overlaps(got_sounds, want.sounds)
			# A click on an exit sets egozh/egozv and lets walkonby carry the
			# player there over later frames, so the export's lifted `walk` nav
			# has no immediate counterpart. Counted apart rather than as a
			# failure.
			if str(want.get("kind", "")).begins_with("walk") and got_navs.is_empty():
				row.walk += 1
			elif nav_ok and snd_ok:
				row.agree += 1
			elif nav_ok or snd_ok:
				row.partial += 1
			else:
				row.differ += 1
				if NATIVE_CHANNELS.has(channel):
					## Not a divergence. The inventory slots are driven by
					## InventoryDrag and the drop table, and the save buttons by
					## the runtime's SAVELOAD intercept, so an interpreted script
					## is expected to produce no nav for them. Counting these as
					## failures put 26 of the 29 gaps down to behaviour the port
					## implements deliberately.
					row.native += 1
					row.differ -= 1
				else:
					_fails.append("%s ch%d frame %d: export nav=%s snd=%s | lingo nav=%s snd=%s" % [
						movie, channel, frame_index + 1,
						str(want.navs), str(want.sounds), str(got_navs), str(got_sounds)])
	host.record = false
	return row


func _export_signature(on_click: Dictionary) -> Dictionary:
	var navs := PackedStringArray()
	var nav: Variant = on_click.get("nav", null)
	if typeof(nav) == TYPE_DICTIONARY:
		for field in ["value", "label", "target_label"]:
			var value: Variant = (nav as Dictionary).get(field, null)
			if typeof(value) == TYPE_STRING and str(value) != "":
				navs.append(str(value).to_lower())
	var sounds := PackedStringArray()
	for sound in on_click.get("sounds", []):
		if typeof(sound) == TYPE_DICTIONARY:
			var file := str((sound as Dictionary).get("file", ""))
			if file != "":
				sounds.append(file.to_lower().get_basename())
	var kind := ""
	if typeof(nav) == TYPE_DICTIONARY:
		kind = str((nav as Dictionary).get("kind", "")).to_lower()
	return {"navs": _normalise(navs), "sounds": _normalise(sounds), "kind": kind}


func _normalise(values: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for value in values:
		var text := str(value).to_lower().strip_edges()
		if text != "" and out.find(text) < 0:
			out.append(text)
	out.sort()
	return out


func _overlaps(a: PackedStringArray, b: PackedStringArray) -> bool:
	for value in a:
		if b.find(value) >= 0:
			return true
	return false
