class_name PuppetController
extends RefCounted
## Channel-30 Piposh puppet: stand / walk cycles and room transitions.

signal arrived(nextroom: Dictionary)
signal changed

## Internal castLib-1 Piposh walk/stand members by size band (syz).
const PIPOSH_BY_SYZ := {
	9: {"standR": 29, "standL": 30, "walkR": [31, 32, 33, 34, 35, 36], "walkL": [37, 38, 39, 40, 41, 42], "walkRU": [43, 44, 45, 46, 47, 48], "walkLU": [49, 50, 51, 52, 53, 54], "walkD": [189, 190, 191, 192, 193, 194]},
	8: {"standR": 57, "standL": 58, "walkR": [59, 60, 61, 62, 63, 64], "walkL": [65, 66, 67, 68, 69, 70], "walkRU": [71, 72, 73, 74, 75, 76], "walkLU": [77, 78, 79, 80, 81, 82]},
	7: {"standR": 84, "standL": 85, "walkR": [86, 87, 88, 89, 90, 91], "walkL": [92, 93, 94, 95, 96, 97], "walkRU": [98, 99, 100, 101, 102, 103], "walkLU": [104, 105, 106, 107, 108, 109]},
	6: {"standR": 110, "standL": 111, "walkR": [112, 113, 114, 115, 116, 117], "walkL": [118, 119, 120, 121, 122, 123], "walkRU": [124, 125, 126, 127, 128, 129], "walkLU": [130, 131, 132, 133, 134, 135]},
	5: {"standR": 136, "standL": 137, "walkR": [138, 139, 140, 141, 142, 143], "walkL": [144, 145, 146, 147, 148, 149], "walkRU": [150, 151, 152, 153, 154, 155], "walkLU": [156, 157, 158, 159, 160, 161]},
	4: {"standR": 162, "standL": 163, "walkR": [164, 165, 166, 167, 168, 169], "walkL": [170, 171, 172, 173, 174, 175], "walkRU": [176, 177, 178, 179, 180, 181], "walkLU": [182, 183, 184, 185, 186, 187]},
}

var active: bool = false
var cast_lib: int = 1
var cast_id: int = 29
var loc_h: float = 320.0
var loc_v: float = 360.0
var whatodo: String = "stand" ## stand | walktime
var egozh: float = 0.0
var egozv: float = 0.0
var nextroom: Dictionary = {}
var syz: int = 9
var facing: String = "right"
var walk_tick: int = 0
var scene: String = ""
var just_arrived: bool = false
var pending_arrive: Dictionary = {}
## `the visible of sprite 30`. The puppet is channel 30, so this is a real score
## property, not a port invention: every hub's `init all` runs `puppetSprite(30, 1)`
## and from then on Lingo owns the channel, with `visible` its only off switch.
##
## The original uses it to keep exactly one Piposh on screen. Room transitions are
## canned animations that draw Piposh themselves, in a low channel — DAY1's
## `edge2up` runs him up channel 3 for frames 406-421 while channel 30 still holds
## a sprite. `whatodoeveryframe` hides sprite 30 when it hands the playhead to one
## (`sprite(30).visible = 0` before `go`), and `BehaviorScript 207` turns it back
## on when the animation ends. Without this the walking animation and the standing
## puppet are both drawn and Piposh appears twice.
var visible: bool = true


func reset() -> void:
	active = false
	whatodo = "stand"
	nextroom = {}
	pending_arrive = {}
	just_arrived = false
	visible = true
	changed.emit()


func is_walking() -> bool:
	return active and whatodo == "walktime"


func syz_from_stand_cast(id: int) -> int:
	for key in PIPOSH_BY_SYZ.keys():
		var pack: Dictionary = PIPOSH_BY_SYZ[key]
		if int(pack.standR) == id or int(pack.standL) == id:
			return int(key)
	return 7


func _pack() -> Dictionary:
	return PIPOSH_BY_SYZ.get(syz, PIPOSH_BY_SYZ[7])


func apply_stand() -> void:
	var pack := _pack()
	cast_lib = 1
	cast_id = int(pack.standL if facing == "left" else pack.standR)
	changed.emit()


func apply_walk_frame() -> void:
	var pack := _pack()
	var frame_idx := absi(walk_tick) % 6
	var going_up := egozv < loc_v - 10.0
	var going_down := egozv > loc_v + 10.0
	var frames: Array
	if going_down and pack.has("walkD"):
		frames = pack.walkD
	elif facing == "left":
		frames = pack.walkLU if going_up and pack.has("walkLU") else pack.walkL
	else:
		frames = pack.walkRU if going_up and pack.has("walkRU") else pack.walkR
	cast_lib = 1
	cast_id = int(frames[frame_idx])
	changed.emit()


func sync_from_frame(frame: Dictionary, scene_name: String, stage_size: Vector2i) -> void:
	var sprite := _channel_sprite(frame, 30)
	if sprite.is_empty() and not active:
		return
	if sprite.is_empty():
		_apply_pending_arrive()
		return

	var score_h := float(sprite.get("loc_h", float(sprite.get("x", 0)) + float(sprite.get("width", 0)) * 0.5))
	var score_v := float(sprite.get("loc_v", float(sprite.get("y", 0)) + float(sprite.get("height", 0)) * 0.5))
	var id := int(sprite.get("cast_id", 29))

	if not active:
		active = true
		cast_lib = int(sprite.get("cast_lib", 1))
		cast_id = id
		loc_h = score_h
		loc_v = score_v
		syz = syz_from_stand_cast(id)
		var pack := _pack()
		facing = "left" if id == int(pack.standL) else "right"
		whatodo = "stand"
		scene = scene_name
		walk_tick = 0
		_apply_pending_arrive()
		changed.emit()
		return

	if whatodo == "stand" and nextroom.is_empty():
		syz = syz_from_stand_cast(id)
		cast_lib = 1
		cast_id = id
		if just_arrived:
			just_arrived = false
			scene = scene_name
		elif scene != scene_name:
			scene = scene_name
			loc_h = score_h
			loc_v = score_v
		changed.emit()

	_apply_pending_arrive()


func bootstrap(stage_pt: Vector2, stage_size: Vector2i, scene_name: String) -> void:
	active = true
	cast_lib = 1
	cast_id = 29
	loc_h = stage_pt.x if stage_pt.x > 0.0 else stage_size.x * 0.5
	loc_v = stage_pt.y if stage_pt.y > 0.0 else stage_size.y * 0.75
	whatodo = "stand"
	syz = 9
	facing = "right"
	scene = scene_name
	walk_tick = 0
	just_arrived = false
	visible = true
	changed.emit()


func start_walk(nav: Dictionary, stage_pt: Vector2, stage_size: Vector2i, scene_name: String) -> bool:
	var kind := str(nav.get("kind", ""))
	if kind != "walk" and kind != "walk_here":
		return false
	if not active:
		bootstrap(stage_pt, stage_size, scene_name)

	var walk_x: float
	var walk_y: float
	var dest := {}

	if kind == "walk_here":
		walk_x = clampf(stage_pt.x, 8.0, float(stage_size.x) - 8.0)
		walk_y = clampf(stage_pt.y + float(nav.get("offset_v", 0)), 8.0, float(stage_size.y) - 8.0)
	else:
		var walk_to: Dictionary = nav.get("walk_to", {})
		walk_x = float(walk_to.get("x", NAN))
		walk_y = float(walk_to.get("y", NAN))
		if not is_finite(walk_x) or not is_finite(walk_y):
			return false
		var arrive: Dictionary = nav.get("arrive_at", {})
		dest = {
			"label": nav.get("target_label", null),
			"movie": nav.get("target_movie", null),
			"x": float(arrive.get("x", walk_x)),
			"y": float(arrive.get("y", walk_y)),
			"newsyz": nav.get("newsyz", syz),
			# The lifted export's stand-in for `ifmovie`: an `after` means the walk
			# lands on a canned animation or another movie rather than on a spot in
			# this room, which is exactly when the original hides sprite 30.
			"transition": false,
		}
		var after: Variant = nav.get("after", null)
		if typeof(after) == TYPE_DICTIONARY:
			var ak := str(after.get("kind", ""))
			if ak == "movie":
				dest.movie = after.get("value")
				dest.label = after.get("label", dest.label)
				dest.transition = true
			elif ak == "label":
				dest.label = after.get("value")
				dest.movie = null
				dest.transition = true

	if walk_x < loc_h - 10.0:
		facing = "left"
	elif walk_x > loc_h + 10.0:
		facing = "right"

	whatodo = "walktime"
	egozh = walk_x
	egozv = walk_y
	nextroom = dest
	walk_tick = 0
	apply_walk_frame()
	return true


func step() -> bool:
	if not is_walking():
		return false
	if not is_finite(egozh) or not is_finite(egozv):
		whatodo = "stand"
		apply_stand()
		return false

	var dx := egozh - loc_h
	var dy := egozv - loc_v
	var moved := false
	const STEP_H := 12.0
	const STEP_V := 8.0

	if absf(dx) > 10.0:
		loc_h += STEP_H if dx > 0.0 else -STEP_H
		facing = "right" if dx > 0.0 else "left"
		moved = true
	else:
		loc_h = egozh

	if absf(dy) > 10.0:
		loc_v += STEP_V if dy > 0.0 else -STEP_V
		moved = true
	else:
		loc_v = egozv

	walk_tick += 1
	if moved:
		apply_walk_frame()
		return true

	whatodo = "stand"
	var next := nextroom.duplicate(true)
	nextroom = {}
	if not next.is_empty() and (next.get("label") != null or next.get("movie") != null):
		if next.get("newsyz") != null:
			syz = int(next.newsyz)
		loc_h = float(next.get("x", loc_h))
		loc_v = float(next.get("y", loc_v))
		just_arrived = true
		# `whatodoeveryframe`, arrival branch: the handover to a canned animation
		# runs `sprite(30).visible = 0` before its `go`. Hidden here, before
		# apply_stand() emits `changed`, so no frame is drawn with both Piposhes.
		if bool(next.get("transition", false)):
			visible = false
		apply_stand()
		arrived.emit(next)
	else:
		apply_stand()
	return true


func set_pending_arrive(arrive_at: Variant, newsyz: Variant = null) -> void:
	if typeof(arrive_at) != TYPE_DICTIONARY:
		return
	pending_arrive = {
		"x": float(arrive_at.get("x", loc_h)),
		"y": float(arrive_at.get("y", loc_v)),
		"newsyz": newsyz,
	}


func _apply_pending_arrive() -> void:
	if pending_arrive.is_empty() or not active:
		return
	var a := pending_arrive
	pending_arrive = {}
	if a.has("x"):
		loc_h = float(a.x)
	if a.has("y"):
		loc_v = float(a.y)
	if a.get("newsyz") != null:
		syz = int(a.newsyz)
	just_arrived = true
	apply_stand()


func draw_rect(member: Dictionary, tex: Texture2D, sx: float, sy: float) -> Rect2:
	if tex == null:
		return Rect2()
	var nw := float(tex.get_width()) * sx
	var nh := float(tex.get_height()) * sy
	var reg_x := float(member.get("reg_offset_x", tex.get_width() * 0.5)) * sx
	var reg_y := float(member.get("reg_offset_y", tex.get_height() * 0.5)) * sy
	return Rect2(loc_h * sx - reg_x, loc_v * sy - reg_y, nw, nh)


static func _channel_sprite(frame: Dictionary, channel: int) -> Dictionary:
	for sprite in frame.get("sprites", []):
		if typeof(sprite) == TYPE_DICTIONARY and int(sprite.get("channel", -1)) == channel:
			return sprite
	return {}
