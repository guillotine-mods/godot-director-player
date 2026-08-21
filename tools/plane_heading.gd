extends SceneTree
## A flight game's heading globals and the artwork its channels draw stay in step
## across held arrow keys.
##
##   godot --headless --script tools/plane_heading.gd -- --root piposh-dream
##
##   --presses N   arrow presses to make, cycling the four (default 8)
##   --hold N      process frames to hold each key down for (default 24)
##   --settle N    process frames after each release (default 10)
##
## Runs headless. Both readings are numbers -- an interpreter global and a channel
## record -- so nothing here paints.
##
## ## The pair, and why the two sides cannot agree by construction
##
## `piposh-dream/plane2.dir` steers with `the keyDownScript`/`the keyUpScript` and
## keeps the aircraft's heading in two integers: `horznum`, 1..13, and `vertnum`,
## 1..6. The frame script of the game loop (`1:82`, f116 onward) moves them one at
## a time, and beside each move it writes the *channels*:
##
##     horznum = horznum + 1
##     set the memberNum of sprite 20 to the memberNum of sprite 20 + 1
##     set the locH of sprite 19 to the locH of sprite 19 + 48
##
## So the aircraft's picture is `13 * vertnum + horznum` plus a constant, and the
## reticle's position is `48 * horznum` and `-80 * vertnum` plus constants. Three
## readings of one truth: where the plane is pointing.
##
## They are independent in the way that matters. The global is a plain integer in
## the interpreter's own table; the two channel writes are **read-modify-writes
## through the channel**, so they read back whatever the override table hands
## them. A release, a revert, or a score write that reaches a puppeted channel
## desynchronises the pair *permanently* -- the next `+ 1` starts from the score's
## member and the offset never recovers -- which is what makes a conserved
## difference the right assertion rather than an equality at one instant.
##
## This is the generalised form of the cross-check that found
## `docs/bugs-closed.md` 120. There the movie's state was a field and the second
## reading was the sixteen tiles' members; here the state is two globals and the
## second reading is one channel's member and another's position. The
## minigame sweep of 2026-08-14 rated this game `YES (1-3)` on criteria that are
## all about *presence*, and said so itself: "visual correctness, at all. Nothing
## measured here looks at colour, size or placement."
##
## ## Why the key has to be **held**
##
## `planedown` only sets `swiv = "ok"`; `1:82`'s `exitFrame` is what reads `the
## keyCode` and moves; `planeup` sets `swiv = "no"` again. A press and release
## inside one process frame therefore leaves `swiv` at `"no"` at every `exitFrame`
## the movie ever runs, and the heading never changes -- measured, with `swiv`
## sampled per frame: seven presses, `horznum` 7 throughout. So each press holds
## the key down across score ticks and releases it after, and the *number* of
## ticks it is held for is deliberately not asserted, because that is a race with
## the clock. What is asserted is the conserved difference, which is
## count-independent.
##
## ## Why the landing is f116 and not the init
##
## `1:79`, which puppets the channels and seeds `horznum`/`vertnum`, is the frame
## script of f85 alone. The game loop `1:82` starts at f116, with `1:84` at f115
## in between. Standing anywhere in f86..f114 leaves a movie with a seeded
## heading, a puppeted channel 20 and **no frame script at all**, so every press
## is swallowed and the run reads as a dead game: that is the first thing this
## file did, and the reason the landing is derived from the score's own frame
## script intervals rather than from a marker.
##
## ## What is not asserted, and why
##
## `1:79` branches on `soundBusy(4)` to seed `field "airocnt"` and
## `field "kereshcnt"` -- the lives and the target counter -- so those two are a
## race with the audio server and nothing here reads them. The heading pair is
## insulated from that branch: no line in the movie writes `horznum` or `vertnum`
## outside the arrow arms.
##
## Title-agnostic driving, title-specific scenario.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")

const MOVIE := "plane2.dir"

## The frame script of the game loop. Its first frame is where the movie can be
## driven, and it is found in the score rather than written down as a number.
const LOOP_SCRIPT := 82

## The init, which puppets the channels and seeds the two globals. Its frame is
## found the same way, and the run has to *pass through* it: landing past it
## leaves both globals VOID, every `int()` of one an aborted handler, and -- with
## nothing left to reach `quit()` -- a headless run that looks like a hang rather
## than like the error it is.
const INIT_SCRIPT := 79

## The aircraft, whose member number is the heading, and the reticle, whose
## position is.
const PLANE := 20
const RETICLE := 19

## How far one step of each global moves each channel reading. Straight out of
## `1:82`: a `vertnum` step is thirteen members of the aircraft's strip and eighty
## pixels of the reticle the other way; a `horznum` step is one member and
## forty-eight pixels.
const PER_VERT := 13
const PER_HORZ := 1
const RETICLE_PER_HORZ := 48
const RETICLE_PER_VERT := -80


func _init() -> void:
	var args := Args.parse()
	var hold := Args.number(args, "hold", 24)
	var settle := Args.number(args, "settle", 10)
	var h := Harness.new()

	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s" % paths.error)
		quit(1)
		return
	var frames := _frame_scripts(paths)
	var landing := int(frames.get(LOOP_SCRIPT, -1))
	var init_at := int(frames.get(INIT_SCRIPT, -1))
	if landing < 0 or init_at < 0:
		print("%s: frame script 1:%d at f%d, 1:%d at f%d -- nothing to drive"
			% [MOVIE, INIT_SCRIPT, init_at, LOOP_SCRIPT, landing])
		quit(1)
		return

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", MOVIE, null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("no score loaded")
		quit(1)
		return

	# Two frames short of the **init**, not of the loop, and left to walk all the
	# way in. The init is thirty score frames before the loop and the frames
	# between them carry no frame script at all, so the walk is cheap -- and
	# skipping it is not an option: `1:79` is what seeds the heading and puppets
	# the channels, and a run that starts after it has neither.
	preview.set("_index", init_at - 2)
	var waited := 0
	while int(preview.call("current_frame")) < landing and waited < 4000:
		await process_frame
		waited += 1
		if waited % 300 == 0:
			print("  walking: f%d after %d frame(s)" % [
				int(preview.call("current_frame")), waited])
	for i in settle:
		await process_frame

	var interp: Object = preview.get("_interpreter")
	var control := _sample(preview, interp)
	var rows: Array[String] = []
	var broke: Array[String] = []
	rows.append("control    %s" % _row(control))

	var codes: Array[Key] = [KEY_RIGHT, KEY_UP, KEY_LEFT, KEY_DOWN]
	var horz_moved := 0
	var vert_moved := 0
	# Which headings the run actually visited. Four presses of the four arrows
	# return the aircraft to where it started, so a fault that reset *both* the
	# global and the channel to the score's own values would leave the conserved
	# difference conserved and the first and last rows identical. Counting the
	# distinct headings away from the control closes that, and it is the same hole
	# `puzzle_board`'s header records for a sequence of sliding-tile moves that
	# ends where it began.
	var visited: Dictionary = {}
	for press in Args.number(args, "presses", 8):
		var code: Key = codes[press % codes.size()]
		var before := _sample(preview, interp)
		_hold(preview, code)
		for i in hold:
			await process_frame
		_release(preview, code)
		for i in settle:
			await process_frame
		var after := _sample(preview, interp)
		if int(after["horznum"]) != int(before["horznum"]):
			horz_moved += 1
		if int(after["vertnum"]) != int(before["vertnum"]):
			vert_moved += 1
		var where := Vector2i(int(after["horznum"]), int(after["vertnum"]))
		if where != Vector2i(int(control["horznum"]), int(control["vertnum"])):
			visited[where] = true
		rows.append("press %d %-6s %s" % [press, _name(code), _row(after)])
		print("  %s" % rows[rows.size() - 1])
		for line in _diverged(control, after):
			broke.append("press %d (%s): %s" % [press, _name(code), line])

	h.begin("a flight game's heading globals and its channels stay in step")
	h.check("the movie seeded a heading", int(control["horznum"]) > 0
		and int(control["vertnum"]) > 0,
		"horznum %s, vertnum %s" % [str(control["horznum"]), str(control["vertnum"])])
	h.check("the aircraft's channel is drawing something",
		int(control["plane"]) > 0 and int(control["reticle"]) > 0,
		"ch%d member %d, ch%d member %d" % [PLANE, int(control["plane"]),
			RETICLE, int(control["reticle"])])
	# Without both of these the conserved difference is conserved because nothing
	# moved, which is the vacuous pass `puzzle_board` guards with its own move
	# count. A held arrow that changes nothing is also the exact symptom of the
	# driving bug this file was first written with.
	h.check("held arrows turned the aircraft horizontally", horz_moved > 0,
		"%d press(es) changed horznum" % horz_moved)
	h.check("held arrows turned the aircraft vertically", vert_moved > 0,
		"%d press(es) changed vertnum" % vert_moved)
	h.check("the run stood on more than one heading away from the control",
		visited.size() > 1, "%d distinct heading(s) other than the control"
			% visited.size())
	h.check("the aircraft's member tracked the heading exactly", _clean(broke, "member"),
		"" if _clean(broke, "member") else "%d divergence(s)" % broke.size())
	h.check("the reticle's position tracked the heading exactly",
		_clean(broke, "reticle"),
		"" if _clean(broke, "reticle") else "%d divergence(s)" % broke.size())
	for line in broke.slice(0, 10):
		print("     %s" % line)
	h.complete("a flight game's heading globals and its channels stay in step")

	print("")
	print(("landing    : f%d, the first frame of frame script 1:%d, walked in from "
		+ "f%d (1:%d) in %d frame(s)")
		% [landing, LOOP_SCRIPT, init_at - 2, INIT_SCRIPT, waited])
	for line in rows:
		print("  %s" % line)
	quit(h.finish("a heading global and the artwork drawn for it cannot drift"))


## Both readings at this instant, plus the two conserved differences.
##
## `loch`/`locv` lower-case: `SpriteProps.read` keys on the lower-cased name, and
## `"locH"` falls through to the empty channel's 0 -- which reads as a reticle
## parked at the origin and is a bug in the harness, not the port. This file
## printed exactly that before it printed anything true.
func _sample(preview: Node, interp: Object) -> Dictionary:
	var globals: Dictionary = interp.get("globals")
	var drawn := _drawn(preview)
	var horz := _num(globals.get("horznum"))
	var vert := _num(globals.get("vertnum"))
	var plane := int(drawn.get(PLANE, -1))
	var loc := Vector2(
		float(_num(preview.call("lingo_sprite_prop", RETICLE, "loch"))),
		float(_num(preview.call("lingo_sprite_prop", RETICLE, "locv"))))
	return {
		"horznum": horz, "vertnum": vert,
		"plane": plane, "reticle": int(drawn.get(RETICLE, -1)),
		"loc": loc,
		"member_offset": plane - (PER_VERT * vert + PER_HORZ * horz),
		"reticle_h": loc.x - RETICLE_PER_HORZ * horz,
		"reticle_v": loc.y - RETICLE_PER_VERT * vert,
	}


## Which of the conserved differences the control set is no longer conserved.
func _diverged(control: Dictionary, now: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if int(now["member_offset"]) != int(control["member_offset"]):
		out.append(("the aircraft's member is %d for heading (%d,%d), which is %d "
			+ "off the %d it was seeded at")
			% [int(now["plane"]), int(now["horznum"]), int(now["vertnum"]),
				int(now["member_offset"]) - int(control["member_offset"]),
				int(control["member_offset"])])
	if not is_equal_approx(float(now["reticle_h"]), float(control["reticle_h"])):
		out.append("the reticle's locH is %.0f off the heading" % [
			float(now["reticle_h"]) - float(control["reticle_h"])])
	if not is_equal_approx(float(now["reticle_v"]), float(control["reticle_v"])):
		out.append("the reticle's locV is %.0f off the heading" % [
			float(now["reticle_v"]) - float(control["reticle_v"])])
	return out


## A Lingo global that no handler has assigned yet is VOID, which arrives here as
## null, and `int(null)` is not a conversion but an aborted handler -- which
## `harness.gd` exists to score as a failure and which, before the first `begin`,
## leaves nothing to reach `quit()` at all.
func _num(value: Variant) -> int:
	return 0 if value == null else int(value)


func _clean(broke: Array[String], which: String) -> bool:
	for line in broke:
		if which == "member" and line.contains("member"):
			return false
		if which == "reticle" and line.contains("reticle"):
			return false
	return true


func _row(sample: Dictionary) -> String:
	return ("horznum %2d vertnum %d  ch%d member %3d  ch%d loc (%4.0f,%4.0f)  "
		+ "offsets %d / %.0f / %.0f") % [
		int(sample["horznum"]), int(sample["vertnum"]),
		PLANE, int(sample["plane"]), RETICLE,
		(sample["loc"] as Vector2).x, (sample["loc"] as Vector2).y,
		int(sample["member_offset"]), float(sample["reticle_h"]),
		float(sample["reticle_v"])]


func _name(code: Key) -> String:
	match code:
		KEY_LEFT: return "left"
		KEY_RIGHT: return "right"
		KEY_UP: return "up"
		_: return "down"


func _hold(preview: Node, code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	preview.call("_dispatch_key", down)


func _release(preview: Node, code: Key) -> void:
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	preview.call("_dispatch_key_up", up)


func _drawn(preview: Node) -> Dictionary:
	var out: Dictionary = {}
	for value in preview.call("frame_sprites"):
		var sprite: Dictionary = value
		var live: Dictionary = preview.call("_effective", sprite)
		if live.is_empty():
			continue
		out[int(sprite["channel"])] = int(live.get("cast_id", sprite.get("cast_id", 0)))
	return out


## The first frame each named frame script covers, read from the score.
##
## A number in this file would be a second authority on where the loop is, and the
## one thing that had to be measured to write this harness at all is that it is
## not where the init is.
func _frame_scripts(paths) -> Dictionary:
	var out: Dictionary = {}
	var path: String = paths.resolve(MOVIE)
	if path == "":
		return out
	var file := ContainerFile.new()
	if not file.open(path):
		return out
	var ids: Array = file.ids_of("VWSC")
	if ids.is_empty():
		file.close()
		return out
	var score = Score.new()
	if not score.parse(file.read_chunk(ids[0])):
		file.close()
		return out
	for interval in score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		var member := int(interval["script_member"])
		var start := int(interval["start"])
		if not out.has(member) or start < int(out[member]):
			out[member] = start
	file.close()
	return out
