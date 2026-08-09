extends SceneTree
## Does a whole-sprite puppet actually stop the score, or only stop it where the
## score happens to have let go?
##
##   godot --headless --path . --script tools/puppet_freeze.gd
##   godot --headless --path . --script tools/puppet_freeze.gd -- \
##       --file PIP2DATA/CHESS.dir --channel 8 --wheels 138,175 --span 7
##   godot --headless --path . --script tools/puppet_freeze.gd -- --wheels 175 --span 7
##
##   --file F      the container to play (default `PIP2DATA/CHESS.dir`)
##   --channel N   the channel the score animates and a script freezes (default 8)
##   --wheels A,B  the first frame of each animated run to click through
##   --span N      frames in each run (default 7)
##   --settle N    frames after the click before reading the stage (default 6)
##
## ## The rule, which knows no movie
##
## `docs/DIRECTOR_ENGINE.md` §5.2. Director keeps one live `Sprite` per channel,
## and `puppetSprite N, TRUE` freezes *that object*: `Sprite::replaceFrom` copies
## the script attachment and **returns**, so from the claim onward the score never
## writes that channel again — not its member, not its position, not its size, and
## not its emptiness.
##
## `tools/puppet_persists.gd` asserts one half of that: a puppeted channel is still
## on the frame when the score's record for it is *empty*. That half passes on a
## port that keeps taking the score's record whenever there is one, because the
## only frames it looks at are the frames where there is not one. This is the
## other half, and it is the half that was missing: **a puppeted channel whose
## score record is present must still not take it.**
##
## ## Why it is asserted through a sound
##
## The invariant a player can hear. Director's spin-the-wheel idiom is one frame
## script over a run of frames the score animates:
##
##     on exitFrame
##       if the mouseDown then
##         repeat with i = 8 to 15
##           puppetSprite(i, 1)
##         end repeat
##         sound playFile 1, soundspath & "art" & member(the memberNum of sprite 8).name & ".aif"
##         go(marker(1))
##       end if
##     end
##
## The click freezes the wheel and names the sound from the member it froze. So
## **the sound the movie asked for and the member left on the stage are one
## claim read twice**, and a port where the score can still write a puppeted
## channel plays one name and shows another — inaudibly, until a player says the
## wheel lands on the wrong thing.
##
## Which is what happened. CHESS has two of these runs. The first jumps to frames
## whose score carries no record for the channel, so it was right; the second
## jumps to frames whose score carries `jos`, so **six of its seven landings
## showed `jos` whatever was clicked** while the sound named the real one.
##
## Both halves are checked per landing, so a fix that freezes the stage without
## freezing `the memberNum of sprite` — or the reverse — is still red.
##
## Title-agnostic in the rule and corpus-aware in the subject, as
## `tools/mouse_poll.gd` and `tools/playhead_escape.gd` are: the container, the
## channel and the frames are arguments, and what is asserted about them names
## none of them.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _play(h)
	quit(h.finish("a whole-sprite puppet freezes the channel against the score"))


func _play(h: Harness) -> bool:
	var args := Args.parse()
	var movie := Args.text(args, "file", "PIP2DATA/CHESS.dir")
	var channel := Args.number(args, "channel", 8)
	var span := Args.number(args, "span", 7)
	var settle := Args.number(args, "settle", 6)
	var wheels: Array = []
	for token in Args.text(args, "wheels", "138,175").split(",", false):
		wheels.append(int(str(token).strip_edges()))

	var scene: PackedScene = load("res://scenes/director_preview.tscn")
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	for i in 6:
		await process_frame
	preview.call("lingo_go_movie", movie, null)
	# A movie change is entered by the ticks after the call, not by the call.
	for i in 10:
		await process_frame

	var score = preview.get("_score")
	var table = preview.get("_table")
	if not h.check("%s loaded a score" % movie, score != null and table != null):
		return true

	for start_value in wheels:
		var start := int(start_value)
		var case := "@f%d: every landing of the run keeps what the click froze" % start
		h.begin(case)
		var landings := 0
		var agreed := 0
		var frozen_read := 0
		for offset in span:
			var at := start + offset
			var seen: Dictionary = await _land(preview, start, at, channel, settle)
			if seen.is_empty():
				continue
			landings += 1
			var named := _member_name(table, int(seen["named"]))
			var shown := _member_name(table, int(seen["shown"]))
			var read := _member_name(table, int(seen["read"]))
			var asked := str(seen["asked"])
			if named != "" and named == shown:
				agreed += 1
			if named != "" and named == read:
				frozen_read += 1
			print("   f%d: click froze %-6s stage kept %-6s `the memberNum` %-6s sound %s%s" % [
				at, named, shown, read, asked,
				"" if named == shown and named == read else "   <-- DIVERGED",
			])
		if not h.check("the run had landings to test", landings > 0,
				"%d of %d frame(s) answered the click" % [landings, span]):
			continue
		h.check("every landing leaves on the stage what the click froze",
			agreed == landings, "%d of %d" % [agreed, landings])
		h.check("and `the memberNum of sprite %d` answers the same" % channel,
			frozen_read == landings, "%d of %d" % [frozen_read, landings])
		h.complete(case)
	return true


## One landing: park on `start`, step to `at`, click there, and report what the
## click named, what the stage kept, what the property reads back, and what the
## movie asked to play.
##
## Driven by stepping rather than by ticking, because the subject is *which frame
## the click landed on* and a tick may take several steps of the score in one go.
## `_mouse_down_seen` is the same latch a real press sets
## (`director_preview.gd:_mouse_down_seen`); the press itself is
## `tools/mouse_poll.gd`'s subject and is not re-proved here.
func _land(preview: Node, start: int, at: int, channel: int, settle: int) -> Dictionary:
	preview.set("_paused", true)
	# **Drop what the previous landing claimed**, and this is the difference
	# between a harness and a harness that passes. §5.5: nothing in the frame loop
	# clears a whole-sprite puppet, so the claim the last landing made is still
	# there — and a run of landings that re-parks the playhead by hand never
	# reaches the frame where the *movie* releases it. Left alone, every landing
	# after the first reads back what the first one froze, all seven rows agree
	# with each other, and the check goes green over one measurement repeated.
	# The movie itself only ever arrives here from the top, with the channels
	# unclaimed; this is what makes that true for a landing arrived at sideways.
	(preview.get("_overrides") as Dictionary).clear()
	preview.set("_index", start)
	for i in 4:
		await process_frame
	preview.set("_paused", true)

	var named := -1
	var asked := ""
	for step in settle + 16:
		var index := int(preview.call("current_frame"))
		if index == at and named < 0:
			named = int(preview.call("lingo_sprite_prop", channel, "membernum"))
			preview.set("_mouse_down_seen", true)
		preview.call("_advance")
		preview.set("_mouse_down_seen", false)
		asked = _asked(preview, at, asked)
		if named >= 0 and int(preview.call("current_frame")) != index + 1:
			break
	if named < 0:
		return {}
	for i in settle:
		preview.call("_advance")
		asked = _asked(preview, at, asked)
	return {
		"named": named,
		"shown": _on_stage(preview, channel),
		"read": int(preview.call("lingo_sprite_prop", channel, "membernum")),
		"asked": asked,
	}


## What the channel actually draws as, through the same call the painter, the hit
## test and the cursor all use.
func _on_stage(preview: Node, channel: int) -> int:
	var shown := -1
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		if int(sprite["channel"]) != channel:
			continue
		var live: Dictionary = preview.call("_effective", sprite)
		if not live.is_empty():
			shown = int(live["cast_id"])
	return shown


## The **first** file the movie asked to play after the click, off the preview's
## own trace. Context beside the two assertions rather than a third one: which
## file a title builds out of a member name is that title's business, while
## "the channel keeps what the puppet froze" is Director's.
##
## Sampled every step and kept once found, and matched on **the frame it was
## played from** rather than on a position in the trace. `_traced` is a short
## rolling tail: an index taken before the landing is past the end of it a few
## steps later, and the frame the click jumps to plays a sound of its own that
## would otherwise be the answer. The frame the click was made on names both.
func _asked(preview: Node, at: int, so_far: String) -> String:
	if so_far != "":
		return so_far
	var wanted := "f%d play " % at
	for value in (preview.get("_traced") as Array):
		var line := str(value)
		if not line.begins_with(wanted):
			continue
		var cut := maxi(line.rfind("\\"), line.rfind("/"))
		return line.substr(cut + 1) if cut >= 0 else line
	return ""


func _member_name(table, cast_id: int) -> String:
	if cast_id <= 0 or table == null:
		return ""
	var member: Dictionary = table.get_member(1, cast_id)
	var name := str(member.get("name", ""))
	return name if name != "" else str(cast_id)
