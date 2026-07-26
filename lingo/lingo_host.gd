class_name LingoHost
extends RefCounted
## Binds the Lingo interpreter to the live engine.
##
## Everything Director-specific lands here: sprite properties become a puppet
## override table that `DirectorRuntime` and `MoviePlayer` read, fields become a
## text table with `objectsfield` aliased onto `GameState` so saves keep working,
## and navigation and sound go straight to the existing runtime and
## `AudioDirector`.

const FIELDS_PATH := "res://data/lingo/fields.json"
const MEMBER_NAMES_PATH := "res://data/lingo/member_names.json"
## Field whose text is the inventory. Aliased rather than copied: GameState owns
## it, the Save Editor edits it, and to_dict/from_dict round-trip it.
const INVENTORY_FIELD := "objectsfield"
## Globals the port already owns. PuppetController is a native implementation of
## Director's walk state machine and carries these exact names, so the interpreter
## must read and write through to it or the two drift apart.
const PUPPET_GLOBALS := {
	"egozh": "egozh", "egozv": "egozv", "whatodo": "whatodo", "syz": "syz",
}
## Handlers the port implements natively, which therefore win even over the
## original Lingo definition.
const NATIVE_HANDLERS := ["walkonby"]

var runtime: Object = null
## Set by LingoEngine. The native handlers read globals through it.
var interpreter: Object = null

## channel -> {property (lower) -> value}. A property present here overrides the
## score; absent falls through to the score frame.
var puppet: Dictionary = {}
## channel -> true once `puppetSprite N, 1` has been seen.
var puppeted: Dictionary = {}
## cast (lower) -> field name (lower) -> text
var fields: Dictionary = {}
## cast (lower) -> member number (int) -> name (lower)
var member_names: Dictionary = {}
var _member_numbers: Dictionary = {}
## The channel that received the current mouse event, for `the clickOn`.
var click_on: int = 0
var mouse_stage: Vector2 = Vector2.ZERO
## Director's `the keyCode`, valid only while a key handler is running.
var key_code: int = 0
## Handler name from `set the keyDownScript to ...`, run on every keypress.
var key_down_script: String = ""
## Builtins that were called but are not implemented, counted once each so a
## missing binding is visible without spamming the log.
var unhandled: Dictionary = {}
var stage_dirty: bool = false
## When true, navigation and sound are captured instead of performed, so a script
## can be compared against the exported on_click without touching the game.
## Set when a script navigated during the current dispatch, so the runtime knows
## not to also apply the exported nav for this frame.
var navigated: bool = false
## `go to the frame` / `go(marker(0))`: Director's idle hold. Distinguished from a
## real navigation so the runtime holds instead of re-entering the frame, which
## would restart its sounds and delay timer every step.
var held: bool = false
var record: bool = false
var recorded_navs: PackedStringArray = PackedStringArray()
var recorded_sounds: PackedStringArray = PackedStringArray()


func _init(director_runtime: Object = null) -> void:
	runtime = director_runtime
	_load_tables()


func _load_tables() -> void:
	fields = _load_lowered(FIELDS_PATH)
	var raw_names: Dictionary = _load_json(MEMBER_NAMES_PATH)
	for cast in raw_names.keys():
		var per_cast: Dictionary = raw_names[cast]
		var by_number: Dictionary = {}
		var by_name: Dictionary = {}
		for number in per_cast.keys():
			var name := str(per_cast[number]).to_lower()
			by_number[int(number)] = name
			if not by_name.has(name):
				by_name[name] = int(number)
		member_names[str(cast).to_lower()] = by_number
		_member_numbers[str(cast).to_lower()] = by_name


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_lowered(path: String) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = _load_json(path)
	for cast in raw.keys():
		var per_cast: Dictionary = raw[cast]
		var lowered: Dictionary = {}
		for name in per_cast.keys():
			lowered[str(name).to_lower()] = str(per_cast[name])
		out[str(cast).to_lower()] = lowered
	return out


# ---------------------------------------------------------------- fields


func _default_cast() -> String:
	## Unqualified `field "x"` means the movie's own cast first, then master,
	## which is where the shared game state lives.
	return "master"


func get_field(name: String, cast: String) -> String:
	var key := name.to_lower()
	if key == INVENTORY_FIELD:
		return "\n".join(Array(GameState.objects_field))
	for candidate in _cast_search_order(cast):
		var per_cast: Variant = fields.get(candidate, {})
		if typeof(per_cast) == TYPE_DICTIONARY and (per_cast as Dictionary).has(key):
			return str((per_cast as Dictionary)[key])
	return ""


func set_field(name: String, cast: String, text: String) -> void:
	var key := name.to_lower()
	if key == INVENTORY_FIELD:
		var lines := LingoValue.split_lines(text)
		# Keep the field's declared length: the scripts index up to line 30 and
		# GameState, the Save Editor and the HUD all assume a fixed size.
		var wanted: int = GameState.objects_field.size()
		var next := PackedStringArray()
		next.resize(wanted)
		for i in wanted:
			var value := str(lines[i]) if i < lines.size() else ""
			next[i] = value if value.strip_edges() != "" else "empty"
		GameState.objects_field = next
		GameState.state_changed.emit()
		return
	for candidate in _cast_search_order(cast):
		var per_cast: Variant = fields.get(candidate, {})
		if typeof(per_cast) == TYPE_DICTIONARY and (per_cast as Dictionary).has(key):
			(per_cast as Dictionary)[key] = text
			return
	# A field the dump did not carry still has to hold what a script writes.
	var owner := _cast_search_order(cast)[0]
	if not fields.has(owner):
		fields[owner] = {}
	(fields[owner] as Dictionary)[key] = text


func _cast_search_order(cast: String) -> PackedStringArray:
	var order := PackedStringArray()
	if cast.strip_edges() != "":
		order.append(cast.to_lower())
	if runtime != null and runtime.get("loader") != null:
		var movie := str(runtime.loader.movie_name).to_lower()
		if movie != "" and order.find(movie) < 0:
			order.append(movie)
	if order.find(_default_cast()) < 0:
		order.append(_default_cast())
	return order


# ---------------------------------------------------------------- sprites


func _score_sprite(channel: int) -> Dictionary:
	if runtime == null:
		return {}
	var frame: Dictionary = runtime.loader.get_frame(runtime.frame_index)
	for sprite in frame.get("sprites", []):
		if typeof(sprite) == TYPE_DICTIONARY and int((sprite as Dictionary).get("channel", 0)) == channel:
			return sprite
	return {}


func get_sprite_prop(channel: int, prop: String) -> Variant:
	var key := prop.to_lower()
	var overrides: Variant = puppet.get(channel, {})
	if typeof(overrides) == TYPE_DICTIONARY and (overrides as Dictionary).has(key):
		return (overrides as Dictionary)[key]
	var sprite := _score_sprite(channel)
	match key:
		"membernum", "castnum", "member":
			return int(sprite.get("cast_id", 0))
		"castlibnum", "castlib":
			return int(sprite.get("cast_lib", 1))
		"loch":
			return int(sprite.get("loc_h", sprite.get("x", 0)))
		"locv":
			return int(sprite.get("loc_v", sprite.get("y", 0)))
		"width":
			return int(sprite.get("width", 0))
		"height":
			return int(sprite.get("height", 0))
		"ink":
			return int(sprite.get("ink", 0))
		"visible":
			if sprite.is_empty():
				return 0
			return 0 if runtime != null and runtime.is_channel_hidden(channel) else 1
		"puppet":
			return 1 if puppeted.has(channel) else 0
		"left":
			return int(sprite.get("x", 0))
		"top":
			return int(sprite.get("y", 0))
		"right":
			return int(sprite.get("x", 0)) + int(sprite.get("width", 0))
		"bottom":
			return int(sprite.get("y", 0)) + int(sprite.get("height", 0))
		"movablesprite", "moveablesprite":
			return 0
		_:
			return 0


func set_sprite_prop(channel: int, prop: String, value: Variant) -> void:
	var key := prop.to_lower()
	if not puppet.has(channel):
		puppet[channel] = {}
	(puppet[channel] as Dictionary)[key] = value
	if key == "visible" and runtime != null:
		# Visibility is the one property the existing renderer already gates, so
		# keep the two in step rather than introducing a second mechanism.
		#
		# Only for a puppeted sprite, though. Director refreshes a non-puppeted
		# sprite's properties from the score on the next frame, so an unpuppeted
		# `sprite(N).visible = 0` is transient. The runtime's hide is permanent,
		# and `BehaviorScript 3 - b4 bk's` blanks channels 15, 17 and 33 on every
		# room entry without puppeting them: honouring that hid 600 collectable
		# records, sciser and sulam and afgan among them, for the whole session.
		if puppeted.has(channel):
			runtime.set_channel_visible(channel, LingoValue.truthy(value))
		elif LingoValue.truthy(value):
			# A show still has to be able to undo an earlier puppeted hide.
			runtime.set_channel_visible(channel, true)
	stage_dirty = true


func sprite_rect(channel: int) -> Rect2:
	if runtime == null:
		return Rect2()
	var sprite := _score_sprite(channel)
	if sprite.is_empty():
		return Rect2()
	var rect: Rect2 = runtime.sprite_stage_rect(sprite)
	var overrides: Variant = puppet.get(channel, {})
	if typeof(overrides) == TYPE_DICTIONARY:
		var over: Dictionary = overrides
		if over.has("loch") or over.has("locv"):
			var centre := rect.position + rect.size * 0.5
			var x := float(LingoValue.to_num(over.get("loch", centre.x)))
			var y := float(LingoValue.to_num(over.get("locv", centre.y)))
			rect.position = Vector2(x, y) - rect.size * 0.5
	return rect


# ---------------------------------------------------------------- members


func member_number(which: Variant, cast: String) -> int:
	## `the number of member "sciser"` and `member(30, "master")` both land here.
	if typeof(which) != TYPE_STRING:
		return LingoValue.to_int(which)
	var wanted := (which as String).to_lower()
	for candidate in _cast_search_order(cast):
		var by_name: Variant = _member_numbers.get(candidate, {})
		if typeof(by_name) == TYPE_DICTIONARY and (by_name as Dictionary).has(wanted):
			return int((by_name as Dictionary)[wanted])
	return 0


func get_member_prop(which: Variant, cast: String, prop: String) -> Variant:
	var key := prop.to_lower()
	if key == "name":
		var number := LingoValue.to_int(which)
		if typeof(which) == TYPE_STRING:
			return which
		for candidate in _cast_search_order(cast):
			var by_number: Variant = member_names.get(candidate, {})
			if typeof(by_number) == TYPE_DICTIONARY and (by_number as Dictionary).has(number):
				return str((by_number as Dictionary)[number])
		return ""
	if key == "number":
		return member_number(which, cast)
	if key == "text":
		return get_field(LingoValue.to_str(which), cast)
	return 0


func set_member_prop(which: Variant, cast: String, prop: String, value: Variant) -> void:
	if prop.to_lower() == "text":
		set_field(LingoValue.to_str(which), cast, LingoValue.to_str(value))


# ---------------------------------------------------------------- system


func get_system_prop(prop: String) -> Variant:
	match prop.to_lower():
		"clickon":
			return click_on
		"moviename":
			if runtime == null:
				return ""
			return "%s.dxr" % str(runtime.loader.movie_name).to_lower()
		"machinetype":
			# 256 is Windows, which is what the shipped game ran on. The scripts
			# only use it to choose a path separator.
			return 256
		"mouseh":
			return int(mouse_stage.x)
		"mousev":
			return int(mouse_stage.y)
		"frame":
			return (runtime.frame_index + 1) if runtime else 0
		"timer", "ticks":
			return int(Time.get_ticks_msec() / 16.667)
		"milliseconds":
			return Time.get_ticks_msec()
		"keycode", "key":
			return key_code
		"shiftdown", "optiondown", "commanddown", "controldown", "doubleclick":
			return 0
		"stagewidth":
			return int(runtime.loader.stage_size.x) if runtime else 640
		"stageheight":
			return int(runtime.loader.stage_size.y) if runtime else 480
		_:
			return 0


func set_system_prop(prop: String, value: Variant) -> void:
	match prop.to_lower():
		"keydownscript":
			## The game's only use of key input. `on startMovie` sets this to
			## "fromnow", which stops sound channel 1 when a key is pressed, so
			## a keypress cuts the line of speech that is playing.
			key_down_script = LingoValue.to_str(value).strip_edges()
		_:
			unhandled["the %s (write)" % prop.to_lower()] = true


# ---------------------------------------------------------------- builtins


func call_builtin(name: String, args: Array) -> Variant:
	match name.to_lower():
		"go", "goto":
			return _go(args)
		"play":
			# `play frame "x"` is a subroutine jump in Director. The port has no
			# play stack, so treat it as a plain go, which is how every use in
			# this game behaves.
			return _go(args)
		"walkonby":
			return _walkonby()
		"puppetsprite":
			if args.size() >= 1:
				var channel := LingoValue.to_int(args[0])
				if args.size() >= 2 and not LingoValue.truthy(args[1]):
					puppeted.erase(channel)
					puppet.erase(channel)
				else:
					puppeted[channel] = true
			stage_dirty = true
			return 0
		"updatestage":
			stage_dirty = true
			return 0
		"sound":
			return _sound(args)
		"soundbusy":
			return 1 if AudioDirector.sound_busy(LingoValue.to_int(args[0] if args.size() > 0 else 1)) else 0
		"random":
			var top := LingoValue.to_int(args[0] if args.size() > 0 else 1)
			return randi_range(1, maxi(1, top))
		"marker":
			return _marker(args)
		"label":
			if runtime == null or args.is_empty():
				return 0
			# `label(0)` is not a lookup of a marker named "0": with a number it
			# means the current marker, the same as `marker(0)`. The rooms record
			# themselves with `whereami = label(0)` and every hotspot compares
			# that against `label("<room>")`, so both spellings must agree.
			if typeof(args[0]) != TYPE_STRING:
				return _marker(args)
			var index: int = int(runtime.loader.lookup_label(LingoValue.to_str(args[0])))
			return index + 1 if index >= 0 else 0
		"rollover":
			if runtime == null or args.is_empty():
				return 0
			return 1 if sprite_rect(LingoValue.to_int(args[0])).has_point(mouse_stage) else 0
		"intersects":
			if args.size() < 2:
				return 0
			var a := sprite_rect(LingoValue.to_int(args[0]))
			var b := sprite_rect(LingoValue.to_int(args[1]))
			if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
				return 0
			return 1 if a.intersects(b) else 0
		"within":
			if args.size() < 2:
				return 0
			return 1 if sprite_rect(LingoValue.to_int(args[1])).encloses(
				sprite_rect(LingoValue.to_int(args[0]))) else 0
		"cursor", "preloadmember", "unloadmember", "alert", "beep", "nothing", "cursorfunk", "updatelock":
			return 0
		_:
			unhandled[name.to_lower()] = true
			return null


func owns_global(name: String) -> bool:
	return runtime != null and PUPPET_GLOBALS.has(name.to_lower())


func get_global(name: String) -> Variant:
	var field := str(PUPPET_GLOBALS.get(name.to_lower(), ""))
	if field == "" or runtime == null:
		return null
	return runtime.puppet.get(field)


func set_global(name: String, value: Variant) -> void:
	var field := str(PUPPET_GLOBALS.get(name.to_lower(), ""))
	if field == "" or runtime == null:
		return
	if field == "whatodo":
		runtime.puppet.whatodo = LingoValue.to_str(value)
	elif field == "syz":
		runtime.puppet.syz = LingoValue.to_int(value)
	else:
		runtime.puppet.set(field, float(LingoValue.to_num(value)))


func is_native_handler(name: String) -> bool:
	return NATIVE_HANDLERS.has(name.to_lower())


func _walkonby() -> Variant:
	## The original sets sprite 30's walk-cycle member and flips whatodo. The port
	## does all of that in PuppetController, so the native version only has to
	## start it moving toward egozh/egozv, which the caller has already set.
	if runtime == null:
		return 0
	var puppet: Object = runtime.puppet
	if not bool(puppet.active):
		puppet.bootstrap(Vector2(float(puppet.loc_h), float(puppet.loc_v)),
			runtime.loader.stage_size,
			str(runtime.marker_name_for_frame(runtime.frame_index)))
	var target_h := float(puppet.egozh)
	if target_h < float(puppet.loc_h) - 10.0:
		puppet.facing = "left"
	elif target_h > float(puppet.loc_h) + 10.0:
		puppet.facing = "right"
	# `nextroomdata` is the original's room handover and item 1 is the destination
	# label; "000" means stay in this room.
	var destination := ""
	if interpreter != null:
		var raw := LingoValue.to_str((interpreter.globals as Dictionary).get("nextroomdata", ""))
		var first := LingoValue.get_chunk(raw, "item", 1, 1)
		if first != "" and first != "000":
			destination = first
		# `ifmovie` outranks it. 130 scripts set this global, and it is the
		# original's answer to "where does the walk actually land", which is not
		# always the room named in `nextroomdata`. ISLAND2's `arcade1` handler
		# walks Piposh to "arcade" and sets `ifmovie = "1,goarcade1"`, and
		# goarcade1 is the label that launches ARCADE1. Reading only
		# `nextroomdata` left him standing in the arcade, which is what made both
		# HOTEL1 machines and the DAY1/NIGHT1 forest exits dead clicks.
		var after := _ifmovie_label()
		if after != "":
			destination = after
	puppet.nextroom = {"label": destination} if destination != "" else {}
	puppet.whatodo = "walktime"
	puppet.walk_tick = 0
	puppet.apply_walk_frame()
	stage_dirty = true
	return 0


func _ifmovie_label() -> String:
	## `ifmovie` is written as "<flag>,<label>". The flag is 1 when the walk ends
	## somewhere other than the room it started in, and "0,0" is the idle value
	## every room resets it to. A few handlers write the bare label with no flag.
	##
	## Consumed here rather than merely read: the original clears it once the
	## handover happens, and leaving it set would redirect the next walk too.
	if interpreter == null:
		return ""
	var globals: Dictionary = interpreter.globals
	var raw := LingoValue.to_str(globals.get("ifmovie", "")).strip_edges()
	if raw == "":
		return ""
	var parts := raw.split(",")
	var label := ""
	if parts.size() >= 2:
		if parts[0].strip_edges() != "1":
			return ""
		label = parts[1].strip_edges()
	else:
		label = parts[0].strip_edges()
	if label == "" or label == "0" or label == "000":
		return ""
	globals["ifmovie"] = "0,0"
	return label


func begin_dispatch() -> void:
	navigated = false
	held = false


func begin_record() -> void:
	record = true
	recorded_navs = PackedStringArray()
	recorded_sounds = PackedStringArray()


func _go(args: Array) -> Variant:
	if runtime == null or args.is_empty():
		return 0
	# `go to frame 5` and `play frame "x"` carry their command words as leading
	# string arguments; `go to movie "x"` keeps "movie" because it changes meaning.
	var trimmed: Array = []
	for arg in args:
		var word := LingoValue.to_str(arg).to_lower()
		if trimmed.is_empty() and word in ["to", "frame", "the", "loop", "done"]:
			continue
		trimmed.append(arg)
	args = trimmed
	if args.is_empty():
		return 0
	if record:
		for arg in args:
			var text := LingoValue.to_str(arg).to_lower()
			if text != "" and text != "movie" and text != "frame":
				recorded_navs.append(text.get_basename())
		return 0
	var first: Variant = args[0]
	# `go to movie "x"` arrives as two arguments in command form.
	if args.size() >= 2 and LingoValue.to_str(first).to_lower() == "movie":
		runtime.goto_movie(LingoValue.to_str(args[1]))
		return 0
	if typeof(first) == TYPE_STRING:
		var text := (first as String)
		if text.to_lower().ends_with(".dxr") or text.to_lower().ends_with(".dir"):
			runtime.goto_movie(text.get_basename())
			return 0
		var index: int = int(runtime.loader.resolve_label(text, false))
		if index >= 0:
			_enter(index)
		else:
			navigated = false
			unhandled['go "%s"' % text] = true
		return 0
	var frame := LingoValue.to_int(first)
	if frame > 0:
		_enter(frame - 1)
	else:
		navigated = false
	return 0


func _enter(index: int) -> void:
	if runtime == null:
		return
	if index == runtime.frame_index:
		# `go to the frame`: hold here rather than re-entering, which would
		# restart the frame's sounds and delay timer on every step.
		held = true
		return
	runtime.enter_frame(index)


func _sound(args: Array) -> Variant:
	if args.is_empty():
		return 0
	var verb := LingoValue.to_str(args[0]).to_lower()
	match verb:
		"playfile":
			if args.size() >= 3:
				if record:
					recorded_sounds.append(
						LingoValue.to_str(args[2]).to_lower().get_file().get_basename())
				else:
					AudioDirector.play_file(LingoValue.to_int(args[1]), LingoValue.to_str(args[2]))
			return 0
		"stop":
			if args.size() >= 2:
				AudioDirector.stop_channel(LingoValue.to_int(args[1]))
			else:
				AudioDirector.stop_all()
			return 0
		"fadeout", "fadein":
			return 0
		_:
			unhandled["sound %s" % verb] = true
			return 0


func _marker(args: Array) -> Variant:
	## `marker(0)` is the label of the current frame; Lingo compares it against
	## `label("x")`, so both must be frame numbers.
	if runtime == null:
		return 0
	var offset := LingoValue.to_int(args[0] if args.size() > 0 else 0)
	var name: String = str(runtime.marker_name_for_frame(runtime.frame_index))
	if offset == 0:
		var index: int = int(runtime.loader.lookup_label(name))
		return index + 1 if index >= 0 else 0
	# +1 / -1 step to the neighbouring marker.
	var frames: Array = []
	for marker in runtime.loader.markers:
		if typeof(marker) == TYPE_DICTIONARY:
			frames.append(int((marker as Dictionary).get("frame", 0)))
	frames.sort()
	var here: int = runtime.frame_index
	if offset > 0:
		for frame in frames:
			if frame > here:
				return frame + 1
		return frames[frames.size() - 1] + 1 if not frames.is_empty() else 0
	var previous := 0
	for frame in frames:
		if frame >= here:
			break
		previous = frame
	return previous + 1


func unhandled_names() -> PackedStringArray:
	var out := PackedStringArray()
	for key in unhandled.keys():
		out.append(str(key))
	out.sort()
	return out
