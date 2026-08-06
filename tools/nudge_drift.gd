extends SceneTree
## How far the cast-swap "nudge" moves a sprite away from where the score put it.
##
##   godot --headless --script tools/nudge_drift.gd -- --file PIP2DATA/DAY1.DIR
##
## `scenes/director_preview.gd` carries a per-channel positional correction: on a
## member change it adds the difference between the old and new registration
## anchors, and applies the running total to every later draw. The claim behind
## it was that Director shifts the start point so a new registration offset does
## not move the sprite.
##
## The score changes members on a channel constantly — that is how a walk cycle
## is authored — and it supplies its own `loc` for each of those members. So the
## correction is being added on top of a position that was already right. This
## replays the real score and reports, per channel, how many member changes it
## sees and how far the accumulated correction has wandered by the end.
##
## The rule is gone; this is the evidence for why, kept runnable so anyone
## tempted to reintroduce it can see the cost first. It passes when the drift is
## real. `docs/DIRECTOR_ENGINE.md` describes no such correction anywhere in its
## placement chapter — the sprite's own start point is authoritative every frame.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Paths := preload("res://director/director_paths.gd")


## The preview's `_anchor_of`, reproduced exactly so this measures the shipped
## rule rather than a restatement of it.
func _anchor_of(member: Dictionary, sprite: Dictionary) -> Vector2:
	if member.is_empty():
		return Vector2.ZERO
	if int(member.get("type", 0)) == 2:
		var w := float(sprite.get("width", member.get("width", 0)))
		var h := float(sprite.get("height", member.get("height", 0)))
		return -Vector2(floor(w * 0.5), floor(h * 0.5))
	return -Vector2(
		float(member.get("reg_offset_x", 0)), float(member.get("reg_offset_y", 0))
	)


func _init() -> void:
	var args := Args.parse()
	var h := Harness.new()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured")
		quit(1)
		return

	var path: String = paths.resolve(Args.text(args, "file", paths.boot_movie))
	if path == "":
		print("no such container")
		quit(1)
		return

	var movie_file := ContainerFile.new()
	if not movie_file.open(path):
		print("%s: %s" % [path, movie_file.error])
		quit(1)
		return
	var table := CastTable.new()
	table.open(movie_file, paths)
	var vwsc: Array = movie_file.ids_of("VWSC")
	if vwsc.is_empty():
		print("no VWSC in %s" % path)
		quit(1)
		return
	var score := Score.new()
	if not score.parse(movie_file.read_chunk(int(vwsc[0]))):
		print("no score: %s" % score.error)
		quit(1)
		return

	var last_member: Dictionary = {}
	var nudge: Dictionary = {}
	var swaps: Dictionary = {}
	var worst := Vector2.ZERO
	var worst_channel := 0
	var total_swaps := 0
	var limit: int = mini(Args.number(args, "frames", 400), score.frame_count)

	h.begin("the cast-swap correction displaces score-driven animation")
	for i in limit:
		for sprite_value in score.frame(i).get("sprites", []):
			var sprite: Dictionary = sprite_value
			var channel := int(sprite["channel"])
			var cast_id := int(sprite["cast_id"])
			if int(last_member.get(channel, -1)) == cast_id:
				continue
			var previous := int(last_member.get(channel, -1))
			last_member[channel] = cast_id
			if previous < 0:
				continue
			total_swaps += 1
			swaps[channel] = int(swaps.get(channel, 0)) + 1
			var lib := int(sprite["cast_lib"])
			var before := _anchor_of(table.get_member(lib, previous), sprite)
			var after := _anchor_of(table.get_member(lib, cast_id), sprite)
			if before == Vector2.ZERO and after == Vector2.ZERO:
				continue
			var carried: Vector2 = nudge.get(channel, Vector2.ZERO)
			var now: Vector2 = carried + (before - after)
			nudge[channel] = now
			if now.length() > worst.length():
				worst = now
				worst_channel = channel

	print("frames replayed:      %d" % limit)
	print("member changes:       %d across %d channels" % [total_swaps, swaps.size()])
	print("worst drift:          ch%d %s (%d px)" % [
		worst_channel, str(worst), int(worst.length())
	])

	var drifted := 0
	var channels: Array = nudge.keys()
	channels.sort()
	for channel in channels:
		var offset: Vector2 = nudge[channel]
		if offset == Vector2.ZERO:
			continue
		drifted += 1
		if drifted <= 12:
			print("  ch%-3d %6d swaps  ends at %s" % [
				channel, int(swaps.get(channel, 0)), str(offset)
			])
	if drifted > 12:
		print("  ... and %d more channels" % (drifted - 12))

	h.check(
		"the cast-swap correction displaces score-driven animation",
		drifted > 0,
		"%d of %d channels displaced, worst %dpx" % [
			drifted, swaps.size(), int(worst.length())
		]
	)
	h.complete("the cast-swap correction displaces score-driven animation")
	quit(h.finish("why the renderer carries no per-channel positional correction"))
