class_name DirectorRuntime
extends RefCounted
## Director score runner: tempo, nav, puppet, audio, save/load.

signal movie_changed(movie: String)
signal frame_changed(frame: int)
signal nav_event(description: String)
signal quit_requested
signal redraw_requested
signal save_ui_requested(mode: String) ## "save" | "load"

const MOVIE_ALIASES := {
	"exodus": "EXODUS",
	"day1": "DAY1",
	"strtgame": "strtgame",
	"startgame": "strtgame",
	"saveload": "SAVELOAD",
	"hezsave": "HEZSAVE",
	"map": "MAP",
	"sea1": "SEA1",
	"air1": "AIR1",
	"chess": "CHESS",
	"tennis": "TENNIS",
	"pptshow": "PPTSHOW",
	"murder1": "MURDER1",
	"hatday1": "HATDAY1",
	"mrfday1": "MRFDAY1",
	"ishday1": "ISHDAY1",
	"patpip1": "PATDAY1",
	"patday1": "PATDAY1",
	"tofircpt": "TOFIRCPT",
	"allin": "ALLIN",
	"goldodead": "GOLDDEAD",
	"golddead": "GOLDDEAD",
	"hotel1": "HOTEL1",
	"night1": "NIGHT1",
}

const MAX_GUARD_HOLD_MS := 20000.0
const MAX_SCORE_STEPS_PER_TICK := 3
## Lingo's dynamic room-redirect handler. Present in DAY1, NIGHT1, HOTEL1 and
## AIR1, so this is not a Day 1 concern. Destinations live in MovieContext.
const DYNAMIC_REDIRECT_SCRIPT := 207
## Boot movies that are never treated as a hub the player can return to.
const BOOT_MOVIES := ["strtgame", "exodus"]
## Piposh's head. Every drop handler tests this first: an item dropped on it is
## examined rather than used.
const EXAMINE_CHANNEL := 100
## master member piphead2, shown for a single stage refresh while he looks.
const PIPHEAD_LOOK_MEMBER := 55

var loader: RenderModelLoader = RenderModelLoader.new()
var puppet: PuppetController = PuppetController.new()
var context: MovieContext = MovieContext.new()
var drag: InventoryDrag = InventoryDrag.new()
var drops: InventoryDrops = InventoryDrops.new()

var frame_index: int = 0
var running: bool = true
var current_fps: float = 15.0
var waiting_for_click: bool = false
var menu_hover_channel: int = -1
var hovered_sprite: Dictionary = {}
var frame_entered_ms: float = 0.0
var route_stack: Array[Dictionary] = []

var _accum_ms: float = 0.0
var _time_ms: float = 0.0
var _movie_transition_attempt_generation: int = 0
var _pending_transition: String = ""
var _pending_destination: String = ""
var _film_loop_channels: Dictionary = {}
var _hidden_channels: Dictionary = {}
var _head_look_until_ms: float = -1.0


func _s(v: Variant, fallback: String = "") -> String:
	## Godot 4.7: String(variant) is invalid — use str().
	if v == null:
		return fallback
	return str(v)


func _init() -> void:
	puppet.arrived.connect(_on_puppet_arrived)
	puppet.changed.connect(func(): redraw_requested.emit())


func boot() -> Error:
	context.load_context()
	drops.load_table()
	GameState.set_meeting_triggers(context.meeting_triggers())
	return loader.load_index()


func available_movies() -> PackedStringArray:
	return loader.available_movies()


func _mark_movie_transition_attempted() -> void:
	_movie_transition_attempt_generation += 1


func _mark_movie_loaded() -> void:
	_accum_ms = 0.0
	_clear_pending_transition()
	_film_loop_channels.clear()
	if context.is_hub(loader.movie_name):
		GameState.enter_hub(loader.movie_name)


func tick(delta: float) -> void:
	_time_ms += delta * 1000.0
	if not running or loader.frames.is_empty():
		return
	_accum_ms += delta * 1000.0
	var frame_ms := 1000.0 / maxf(current_fps, 1.0)
	var steps_due := floori(_accum_ms / frame_ms)
	if steps_due <= 0:
		return
	var steps_to_run := mini(steps_due, MAX_SCORE_STEPS_PER_TICK)
	_accum_ms = fmod(_accum_ms, frame_ms)
	for _step in range(steps_to_run):
		var transition_attempt_generation := _movie_transition_attempt_generation
		game_step()
		if _movie_transition_attempt_generation != transition_attempt_generation:
			break


func game_step() -> void:
	if puppet.is_walking():
		puppet.step()
		redraw_requested.emit()
		return

	var frame: Dictionary = loader.get_frame(frame_index)
	if _try_transition_redirect(frame):
		return
	var nav: Variant = frame.get("nav", null)
	var action: Dictionary = NavActions.resolve(nav, loader, frame_index)

	if bool(frame.get("wait_click", false)) or waiting_for_click:
		waiting_for_click = true
		return

	var delay_ms := float(frame.get("delay_ms", 0))
	if delay_ms > 0.0 and (_time_ms - frame_entered_ms) < delay_ms:
		return

	# soundBusy guard (Director: if not soundBusy then go(...))
	if typeof(nav) == TYPE_DICTIONARY and nav.get("guard_channel") != null:
		var held := _time_ms - frame_entered_ms
		var channel_busy := AudioDirector.sound_busy(int(nav.guard_channel))
		var guard_when := _s(nav.get("guard_when", "idle"), "idle")
		var should_fire := channel_busy if guard_when == "busy" else not channel_busy
		if not should_fire and held < MAX_GUARD_HOLD_MS:
			if nav.get("busy_nav") != null:
				var busy_action: Dictionary = NavActions.resolve(nav.busy_nav, loader, frame_index)
				if _s(busy_action.get("kind", "")) == "frame":
					enter_frame(int(busy_action.index))
				else:
					_advance_or_hold()
			else:
				_advance_or_hold()
			return

	if action.is_empty():
		_advance_or_hold()
		return

	match _s(action.get("kind", "")):
		"hold":
			return
		"quit":
			_handle_quit()
		"frame":
			enter_frame(int(action.index))
		"movie":
			_goto_from_action(action)
		_:
			_advance_or_hold()


func _try_transition_redirect(frame: Dictionary) -> bool:
	## Without this the completed walk animation falls into the adjacent reverse
	## animation and Piposh turns around. Applies to every movie using the
	## handler, not just DAY1.
	if frame.get("frame_script") != DYNAMIC_REDIRECT_SCRIPT:
		return false

	var movie := loader.movie_name
	var transition := _pending_transition
	var walked := transition != ""
	var destination := _pending_destination
	if transition == "":
		transition = marker_name_for_frame(frame_index).to_lower()
	if destination == "":
		destination = context.transition_destination(movie, transition)
	if destination == "":
		if transition != "":
			context.note_unmapped_transition(movie, transition, walked)
		return false

	_clear_pending_transition()
	var destination_frame := loader.resolve_label(destination, false)
	if destination_frame < 0:
		nav_event.emit('%s transition: %s → missing label "%s"' % [movie, transition, destination])
		return false

	enter_frame(destination_frame)
	nav_event.emit("%s transition: %s → %s" % [movie, transition, destination])
	return true


func _remember_transition(nav: Variant) -> void:
	_clear_pending_transition()
	if typeof(nav) != TYPE_DICTIONARY:
		return
	var after: Variant = nav.get("after", null)
	if typeof(after) != TYPE_DICTIONARY or _s(after.get("kind", "")).to_lower() != "label":
		return
	var transition := _s(after.get("value", "")).to_lower()
	var destination := context.transition_destination(loader.movie_name, transition)
	if destination == "":
		return
	_pending_transition = transition
	_pending_destination = destination


func is_channel_hidden(channel: int) -> bool:
	## Story-gated score channel: present in the export, not yet in the story.
	return _hidden_channels.has(channel)


func master_cast_lib() -> int:
	## Every inventory icon, `object0` and both Piposh heads live in the shared
	## `master` cast. Fall back to 2, which is where DAY1 and NIGHT1 put it.
	var index := loader.cast_lib_index("master")
	return index if index > 0 else 2


func head_member_override() -> int:
	## -1 while the score member (piphead1) stands.
	##
	## Timed rather than counted in enter_frame(), because a frame that holds on
	## wait_click, on delay_ms or on the soundBusy guard never re-enters, and the
	## Lingo's restore after one updateStage() is unconditional. Examining on a
	## wait_click frame used to leave Piposh mid-look until the player clicked.
	return PIPHEAD_LOOK_MEMBER if _time_ms < _head_look_until_ms else -1


func slot_sprite_at(stage_pt: Vector2) -> Dictionary:
	## Slot channels never reach clickable_sprites(): that filter drops any
	## sprite whose on_click has no nav, inventory or sounds, which is all of
	## 103-110. Find them by channel in the score frame instead.
	var slots: Array = GameState.slot_channels()
	var frame: Dictionary = loader.get_frame(frame_index)
	for sprite in frame.get("sprites", []):
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		var channel := int((sprite as Dictionary).get("channel", 0))
		if slots.find(channel) < 0:
			continue
		if is_channel_hidden(channel):
			continue
		if sprite_contains(sprite, stage_pt):
			return sprite
	return {}


func begin_inventory_drag(stage_pt: Vector2) -> bool:
	var sprite: Dictionary = slot_sprite_at(stage_pt)
	if sprite.is_empty():
		return false
	var channel := int(sprite.get("channel", 0))
	var slot_index: int = GameState.slot_channels().find(channel)
	var item: String = GameState.item_in_slot(slot_index)
	if item == "":
		# displayobject() gives an empty slot member object0 and no
		# moveableSprite, so there is nothing to pick up.
		return false
	var rect: Rect2 = sprite_stage_rect(sprite)
	drag.begin(channel, item, rect.position + rect.size * 0.5, _item_icon_size(item, rect.size))
	redraw_requested.emit()
	return true


func _item_icon_size(item: String, fallback: Vector2) -> Vector2:
	## displayobject() sets the slot's memberNum to the item, so `intersects`
	## measures the item's own bitmap. The score rect is the stale object0 box.
	var member: Dictionary = GameState.inventory_member_for_item(item, master_cast_lib())
	if member.is_empty():
		return fallback
	var bitmap: Dictionary = loader.get_member(int(member.cast_lib), int(member.cast_id))
	var w := float(bitmap.get("width", 0))
	var h := float(bitmap.get("height", 0))
	return Vector2(w, h) if w > 0.0 and h > 0.0 else fallback


func update_inventory_drag(stage_pt: Vector2) -> void:
	if not drag.active:
		return
	drag.move_to(stage_pt)
	redraw_requested.emit()


func end_inventory_drag(stage_pt: Vector2) -> void:
	if not drag.active:
		return
	drag.move_to(stage_pt)
	var item := drag.item
	if _drag_intersects(EXAMINE_CHANNEL):
		_examine_item(item)
	else:
		for rule_value in drops.rules_for(loader.movie_name):
			var channel := int((rule_value as Dictionary).get("target_channel", -1))
			if channel >= 0 and _drag_intersects(channel):
				if apply_inventory_drop(item, channel):
					break
	# The icon springs home whatever happened, so a wrong target needs no
	# failure branch: nothing intersects, and nothing plays.
	drag.clear()
	redraw_requested.emit()


func _channel_rect(channel: int) -> Rect2:
	var frame: Dictionary = loader.get_frame(frame_index)
	for sprite in frame.get("sprites", []):
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		if int((sprite as Dictionary).get("channel", 0)) != channel:
			continue
		if is_channel_hidden(channel):
			return Rect2()
		return sprite_stage_rect(sprite)
	return Rect2()


func _drag_intersects(channel: int) -> bool:
	## Lingo: `sprite the clickOn intersects <channel>`, a rect overlap between
	## the dragged icon and the target sprite, not a point test.
	var target := _channel_rect(channel)
	if target.size.x <= 0.0 or target.size.y <= 0.0:
		return false
	return drag.icon_rect().intersects(target)


func _examine_item(item: String) -> void:
	## Swap sprite 100 to piphead2, play pi<item>.aif, and restore piphead1 one
	## score frame later: the Lingo calls updateStage() once before restoring.
	_head_look_until_ms = _time_ms + 1000.0 / maxf(current_fps, 1.0)
	AudioDirector.play_file(1, "pi%s.aif" % item)
	nav_event.emit("examine: %s" % item)


func apply_inventory_drop(item: String, target_channel: int) -> bool:
	## Returns false when nothing in the table matched, which is the silent
	## case: the icon springs home and no sound plays.
	var room := marker_name_for_frame(frame_index)
	for rule_value in drops.rules_for(loader.movie_name):
		var rule: Dictionary = rule_value
		if int(rule.get("target_channel", -1)) != target_channel:
			continue
		if not drops.matches(rule, item, room):
			continue
		if not _drop_requirements_met(rule):
			continue
		_run_drop_rule(rule, item)
		return true
	return false


func _drop_requirements_met(rule: Dictionary) -> bool:
	var required: Variant = rule.get("requires_visible", [])
	if typeof(required) != TYPE_ARRAY:
		return true
	for channel in required as Array:
		var rect := _channel_rect(int(channel))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return false
	return true


func _run_drop_rule(rule: Dictionary, item: String) -> void:
	for channel in rule.get("stop_channels", []):
		AudioDirector.stop_channel(int(channel))

	for sound_value in rule.get("sounds", []):
		if typeof(sound_value) != TYPE_DICTIONARY:
			continue
		var sound: Dictionary = sound_value
		var channel := int(sound.get("channel", 1))
		var file := _s(sound.get("file", ""))
		if file != "":
			AudioDirector.play_file(channel, file)
			continue
		var family := _s(sound.get("family", ""))
		if family == "":
			continue
		var from := int(sound.get("from", 1))
		var to := maxi(from, int(sound.get("to", from)))
		AudioDirector.play_file(channel, "%s%d.aif" % [family, randi_range(from, to)])

	var flag := _s(rule.get("sets_flag", ""))
	if flag != "":
		GameState.set_story_flag(flag)
		refresh_sprite_gates()

	if bool(rule.get("consume", false)):
		GameState.remove_inventory_item(item)

	match _s(rule.get("action", "none")):
		"goto_label":
			var label := _s(rule.get("label", ""))
			var idx := loader.resolve_label(label, false)
			if idx >= 0:
				enter_frame(idx)
				running = true
				nav_event.emit("drop %s → %s" % [item, label])
			else:
				nav_event.emit('drop %s → missing label "%s"' % [item, label])
		"reveal":
			nav_event.emit("drop %s → revealed %s" % [item, _s(rule.get("sets_flag", ""))])
		_:
			pass


func refresh_sprite_gates() -> void:
	## Gates normally settle on room entry, but a click can reveal something in
	## the room the player is already standing in.
	var room := marker_name_for_frame(frame_index)
	var next := context.hidden_channels(loader.movie_name, room)
	if next == _hidden_channels:
		return
	_hidden_channels = next
	redraw_requested.emit()


func _clear_pending_transition() -> void:
	_pending_transition = ""
	_pending_destination = ""


func _advance_or_hold() -> void:
	var next := frame_index + 1
	if next >= loader.frames.size():
		_on_movie_end()
	else:
		enter_frame(next)


func enter_frame(index: int) -> void:
	if loader.frames.is_empty():
		frame_index = 0
		return
	frame_index = clampi(index, 0, loader.frames.size() - 1)
	frame_entered_ms = _time_ms
	var frame: Dictionary = loader.get_frame(frame_index)
	_sync_film_loop_channels(frame)
	var fps := float(frame.get("fps", 0))
	if fps > 0.0:
		current_fps = fps
	waiting_for_click = bool(frame.get("wait_click", false))
	var room := marker_name_for_frame(frame_index)
	_hidden_channels = context.hidden_channels(loader.movie_name, room)
	puppet.sync_from_frame(frame, room, loader.stage_size)
	AudioDirector.play_frame_sounds(frame)
	GameState.remember_location(loader.movie_name, label_near_frame(frame_index), frame_index)
	frame_changed.emit(frame_index)
	redraw_requested.emit()


func _sync_film_loop_channels(frame: Dictionary) -> void:
	var active_channels: Dictionary = {}
	var sprites_value: Variant = frame.get("sprites", [])
	if typeof(sprites_value) != TYPE_ARRAY:
		_film_loop_channels = active_channels
		return

	for sprite_value in sprites_value:
		if typeof(sprite_value) != TYPE_DICTIONARY:
			continue
		var sprite: Dictionary = sprite_value
		if not sprite.has("channel") or not sprite.has("cast_lib") or not sprite.has("cast_id"):
			continue
		var channel := int(sprite.channel)
		var cast_lib := int(sprite.cast_lib)
		var cast_id := int(sprite.cast_id)
		var film_loop := loader.get_film_loop(cast_lib, cast_id)
		var loop_frame_count := _film_loop_frame_count(film_loop)
		if loop_frame_count == 0:
			continue

		var previous_value: Variant = _film_loop_channels.get(channel, {})
		var previous: Dictionary = previous_value if typeof(previous_value) == TYPE_DICTIONARY else {}
		var same_loop := (
			int(previous.get("cast_lib", -1)) == cast_lib
			and int(previous.get("cast_id", -1)) == cast_id
		)
		var loop_frame := 0
		if same_loop:
			loop_frame = clampi(int(previous.get("frame", 0)), 0, loop_frame_count - 1)
			if int(previous.get("score_frame", -1)) != frame_index:
				if bool(film_loop.get("looping", false)):
					loop_frame = (loop_frame + 1) % loop_frame_count
				else:
					loop_frame = mini(loop_frame + 1, loop_frame_count - 1)
		active_channels[channel] = {
			"cast_lib": cast_lib,
			"cast_id": cast_id,
			"frame": loop_frame,
			"score_frame": frame_index,
		}

	_film_loop_channels = active_channels


func _film_loop_frame_count(film_loop: Dictionary) -> int:
	var frames_value: Variant = film_loop.get("frames", [])
	if typeof(frames_value) != TYPE_ARRAY:
		return 0
	var loop_frames: Array = frames_value
	if loop_frames.is_empty():
		return 0
	for loop_frame in loop_frames:
		if typeof(loop_frame) != TYPE_DICTIONARY:
			return 0
	return loop_frames.size()


func film_loop_frame(channel: int) -> int:
	var state_value: Variant = _film_loop_channels.get(channel, {})
	if typeof(state_value) != TYPE_DICTIONARY:
		return 0
	return maxi(0, int((state_value as Dictionary).get("frame", 0)))


func goto_movie(stem: String, frame_number: Variant = null, opts: Dictionary = {}) -> bool:
	var raw := stem.get_file().get_basename().to_lower()
	var label_opt := _s(opts.get("label", ""))

	# Intercept HEZSAVE — original opens an external save projector; we use JSON slots.
	if raw == "hezsave" or find_movie_name(stem).to_lower() == "hezsave":
		return _handle_hezsave(label_opt)

	_mark_movie_transition_attempted()
	var movie_name := find_movie_name(stem)
	if movie_name == "":
		GameState.emit_log('go movie "%s" — not in render_model' % stem, "warn")
		nav_event.emit("Missing movie: %s" % stem)
		return false

	var from_movie_name := loader.movie_name
	var from := from_movie_name.to_lower()
	var to := movie_name.to_lower()

	# Fourteen exports hold zero frames: they are .CST cast libraries the export
	# pipeline emitted as movies. Loading one leaves a blank stage and a dead
	# score, so refuse and keep the current movie running.
	if not context.is_playable(loader.index, movie_name):
		GameState.emit_log(
			'go movie "%s" — not a playable movie (empty cast-library export)' % movie_name,
			"warn"
		)
		nav_event.emit("Refused unplayable movie: %s" % movie_name)
		return false

	GameState.emit_log("Loading movie %s …" % movie_name, "info")
	var err := loader.load_movie(movie_name)
	if err != OK:
		GameState.emit_log("Failed to load movie %s" % movie_name, "error")
		return false
	_mark_movie_loaded()

	if to == "exodus" and from in ["strtgame", "saveload", ""]:
		GameState.new_game()

	# A meeting is complete once it hands the player back to any hub. Checking
	# only DAY1 missed ALLIN, ISHDAY1 and TOFIRCPT, which return to HOTEL1 and
	# so could retrigger forever.
	var returning_to_hub := (
		context.is_hub(movie_name)
		and from != ""
		and not context.is_hub(from_movie_name)
		and from not in BOOT_MOVIES
	)
	if returning_to_hub:
		GameState.mark_meeting_done_by_movie(from)
		# Drop the outbound entry this return consumes. The old check compared
		# the stack top against the movie being left rather than the one being
		# entered, so it never matched and the stack grew on every excursion.
		if not route_stack.is_empty():
			var top: Dictionary = route_stack[route_stack.size() - 1]
			if _s(top.get("movie", "")).to_lower() == to:
				route_stack.pop_back()
	elif from_movie_name != "":
		route_stack.append({"movie": from_movie_name, "frame": frame_index})

	AudioDirector.stop_all()

	waiting_for_click = false
	menu_hover_channel = -1
	hovered_sprite = {}

	# Reset only on a fresh run into a hub, never on a return from an excursion.
	if to in BOOT_MOVIES or (context.is_hub(movie_name) and from in (BOOT_MOVIES + [""])):
		puppet.reset()

	var start := 0
	if to == "strtgame" and bool(opts.get("play_opening", false)):
		start = 0
	elif label_opt != "":
		var idx := loader.resolve_label(label_opt, true)
		start = idx if idx >= 0 else loader.resolve_boot_frame()
	elif frame_number != null and str(frame_number) != "":
		var fn := int(frame_number)
		start = maxi(0, fn - 1) if fn > 0 else 0
	else:
		start = loader.resolve_boot_frame()

	if opts.get("arrive_at") != null:
		puppet.set_pending_arrive(opts.arrive_at, opts.get("newsyz", null))

	# SAVELOAD defaults: from title Load → loadgame label when present.
	if to == "saveload" and label_opt == "" and from == "strtgame":
		var load_lbl := loader.lookup_label("loadgame")
		if load_lbl >= 0:
			start = load_lbl

	movie_changed.emit(movie_name)
	enter_frame(start)
	nav_event.emit(
		"go movie: %s%s" % [
			movie_name,
			(' @ "%s"' % label_opt) if label_opt != "" else "",
		]
	)

	var arrival_day := context.day_for_arrival(movie_name, label_opt)
	if arrival_day > 0:
		GameState.advance_day(arrival_day)

	if context.is_hub(movie_name) and label_opt != "" and not bool(opts.get("from_meeting", false)):
		_try_people_funk(label_opt)
	return true


func _handle_hezsave(label: String) -> bool:
	## Original HEZSAVE is a tiny external projector. Map its labels onto JSON slots.
	var mode := label.to_lower()
	match mode:
		"dosave", "save", "savegame":
			nav_event.emit("Save game (slot 1)")
			_snapshot_return_into_state()
			if GameState.save_slot(1, "Quick save") == OK:
				nav_event.emit("Saved slot 1")
			_finish_saveload("aftersave")
			return true
		"doload", "load", "loadgame":
			nav_event.emit("Load game (slot 1)")
			route_stack.clear()
			if GameState.load_slot(1) == OK:
				# GameState.movie_requested navigates via MoviePlayer.
				return true
			nav_event.emit("No save in slot 1 — open Save Editor (F5)")
			save_ui_requested.emit("load")
			_finish_saveload("afterload")
			return true
		"fillnames":
			save_ui_requested.emit("save")
			_finish_saveload("savegame2")
			return true
		"fillnames2":
			save_ui_requested.emit("load")
			_finish_saveload("loadgame2")
			return true
		_:
			save_ui_requested.emit("save" if mode.find("load") < 0 else "load")
			_finish_saveload("")
			return true


func _finish_saveload(next_label: String) -> void:
	## Escape HEZSAVE nav without loading that movie (avoids re-fire loop).
	if loader.movie_name.to_lower() == "saveload":
		if next_label != "":
			var idx := loader.lookup_label(next_label)
			if idx >= 0:
				enter_frame(idx)
				return
		_advance_or_hold()
		return
	go_back()


func _snapshot_return_into_state() -> void:
	if not route_stack.is_empty():
		var top: Dictionary = route_stack[route_stack.size() - 1]
		GameState.current_movie = _s(top.get("movie", GameState.current_movie))
		GameState.current_frame = int(top.get("frame", GameState.current_frame))
		GameState.current_label = label_near_frame(int(top.get("frame", 0)))
	else:
		GameState.remember_location(loader.movie_name, label_near_frame(frame_index), frame_index)


func go_back() -> bool:
	if route_stack.is_empty():
		if loader.movie_name.to_lower() in ["saveload", "hezsave", "map"]:
			goto_movie("strtgame")
			return true
		return false
	var prev: Dictionary = route_stack[route_stack.size() - 1]
	var movie := _s(prev.get("movie", "DAY1"), "DAY1")
	var frame := int(prev.get("frame", 0))
	_mark_movie_transition_attempted()
	var err := loader.load_movie(find_movie_name(movie) if find_movie_name(movie) != "" else movie)
	if err != OK:
		return false
	_mark_movie_loaded()
	route_stack.pop_back()
	AudioDirector.stop_all()
	waiting_for_click = false
	movie_changed.emit(loader.movie_name)
	enter_frame(frame)
	nav_event.emit("back → %s @ %d" % [loader.movie_name, frame + 1])
	return true


func _handle_quit() -> void:
	# In SAVELOAD / MAP / HEZSAVE, quit means close the window (forget window).
	var m := loader.movie_name.to_lower()
	if m in ["saveload", "hezsave", "map"]:
		nav_event.emit("Close overlay → back")
		go_back()
		return
	running = false
	quit_requested.emit()


func _goto_from_action(action: Dictionary) -> void:
	goto_movie(
		_s(action.get("movie", "")),
		action.get("frame", null),
		{
			"label": action.get("label", null),
			"arrive_at": action.get("arrive_at", null),
			"newsyz": action.get("newsyz", null),
		}
	)


func find_movie_name(stem: String) -> String:
	var raw := stem.get_file().get_basename().to_lower()
	var aliased: String = _s(MOVIE_ALIASES.get(raw, raw), raw)
	var wanted := aliased.to_lower()
	for m in loader.available_movies():
		if m.to_lower() == wanted:
			return m
	for candidate in [aliased, aliased.to_upper(), aliased.to_lower(), stem]:
		var path := "%s/%s/frames.json" % [RenderModelLoader.MODEL_ROOT, candidate]
		if FileAccess.file_exists(path):
			return candidate
	return ""


func perform_click(stage_pt: Vector2) -> void:
	if waiting_for_click:
		waiting_for_click = false
		enter_frame(frame_index + 1)
		return

	var frame := loader.get_frame(frame_index)
	for sprite in clickable_sprites(frame):
		if sprite_contains(sprite, stage_pt):
			_activate_sprite(sprite, stage_pt)
			return


func update_hover(stage_pt: Vector2) -> void:
	var frame := loader.get_frame(frame_index)
	hovered_sprite = {}
	menu_hover_channel = -1
	for sprite in clickable_sprites(frame):
		if sprite_contains(sprite, stage_pt):
			hovered_sprite = sprite
			if loader.movie_name.to_lower() == "strtgame":
				menu_hover_channel = int(sprite.get("channel", -1))
			break
	redraw_requested.emit()


func _activate_sprite(sprite: Dictionary, stage_pt: Vector2) -> void:
	var on_click: Dictionary = sprite.get("on_click", {})
	AudioDirector.play_click_sounds(on_click)
	_apply_inventory_ops(on_click.get("inventory", []))
	_apply_click_flag(int(sprite.get("channel", 0)))
	var nav: Variant = on_click.get("nav", null)
	nav_event.emit("click: %s (cast %s:%s)" % [
		NavActions.describe(nav),
		str(sprite.get("cast_lib", 1)),
		str(sprite.get("cast_id", "?")),
	])
	var action: Dictionary = NavActions.resolve(nav, loader, frame_index)
	if action.is_empty():
		return
	match _s(action.get("kind", "")):
		"quit":
			_handle_quit()
		"hold":
			pass
		"walk", "walk_here":
			var walk_nav: Variant = _apply_walk_override(
				action.get("nav", nav), int(sprite.get("channel", 0))
			)
			_clear_pending_transition()
			var ok: bool = puppet.start_walk(
				walk_nav,
				stage_pt,
				loader.stage_size,
				marker_name_for_frame(frame_index)
			)
			if ok:
				_remember_transition(walk_nav)
				running = true
				nav_event.emit("walk started")
			redraw_requested.emit()
		"unsupported":
			GameState.emit_log("unsupported: %s" % _s(action.get("value", "")), "warn")
		"frame":
			enter_frame(int(action.index))
			running = true
		"movie":
			_goto_from_action(action)
			running = true


func _apply_walk_override(nav: Variant, channel: int) -> Variant:
	## Swap in this hotspot's own walk target. The export keyed walk_to and
	## arrive_at per destination label, so a room reachable from two directions
	## handed both of its exits the same pair and one of them points backwards.
	if typeof(nav) != TYPE_DICTIONARY:
		return nav
	var entry := context.walk_override(
		loader.movie_name,
		marker_name_for_frame(frame_index),
		channel,
		_s((nav as Dictionary).get("target_label", ""))
	)
	if entry.is_empty():
		return nav
	var fixed: Dictionary = (nav as Dictionary).duplicate(true)
	if entry.has("walk_to"):
		fixed["walk_to"] = entry["walk_to"]
	if entry.has("arrive_at"):
		fixed["arrive_at"] = entry["arrive_at"]
	return fixed


func _apply_click_flag(channel: int) -> void:
	## Some hotspots exist only to reveal something else — searching the sand
	## turns up the shells. The flag is declared per room and channel in
	## data/movie_context.json; sprite gates wait on it.
	var flag := context.flag_for_click(
		loader.movie_name,
		marker_name_for_frame(frame_index),
		channel
	)
	if flag == "":
		return
	GameState.set_story_flag(flag)
	nav_event.emit("revealed: %s" % flag)
	refresh_sprite_gates()


func _apply_inventory_ops(ops: Variant) -> void:
	if typeof(ops) != TYPE_ARRAY:
		return
	for inv in ops:
		if typeof(inv) != TYPE_DICTIONARY:
			continue
		var op := _s(inv.get("op", "")).to_lower()
		var item := _s(inv.get("item", ""))
		if op in ["add", "put", "+"]:
			GameState.add_inventory_item(item)
		elif op in ["remove", "delete", "-"]:
			GameState.remove_inventory_item(item)


func _on_puppet_arrived(next: Dictionary) -> void:
	var next_movie := _s(next.get("movie", ""))
	if next_movie != "":
		nav_event.emit('arrived → movie %s @ "%s"' % [next_movie, _s(next.get("label", ""))])
		goto_movie(next_movie, null, {
			"label": next.get("label", null),
			"arrive_at": {"x": next.get("x"), "y": next.get("y")},
			"newsyz": next.get("newsyz", null),
		})
		running = true
		return

	var label := _s(next.get("label", ""))
	if label != "":
		var idx := loader.resolve_label(label, true)
		if idx >= 0:
			enter_frame(idx)
			nav_event.emit("arrived → %s (frame %d)" % [label, idx + 1])
		else:
			nav_event.emit('arrived → missing label "%s"' % label)
		_try_people_funk(label)
	running = true


func _try_people_funk(room_label: String) -> void:
	var meet := GameState.people_funk(room_label)
	if meet != "":
		nav_event.emit("peoplefunk → %s" % meet)
		goto_movie(meet, 1, {"from_meeting": true})
		return
	_try_phase_transition()


func _try_phase_transition() -> void:
	## A hub hands the player to the next one once it has nothing left to show.
	## Checked only when no meeting is due, so a pending meeting always wins.
	if not context.is_hub(loader.movie_name):
		return
	var next: Dictionary = context.phase_transition(loader.movie_name, GameState.globalday)
	if next.is_empty():
		return
	var destination := _s(next.get("movie", ""))
	if destination == "" or destination.to_lower() == loader.movie_name.to_lower():
		return
	# One-shot: mark before travelling so the arrival cannot re-trigger it.
	GameState.set_story_flag(_s(next.get("flag", "")))
	nav_event.emit("phase: %s → %s" % [loader.movie_name, destination])
	GameState.emit_log("Phase change: %s → %s" % [loader.movie_name, destination], "info")
	goto_movie(destination)


func _on_movie_end() -> void:
	## Where a movie goes when its score runs out.
	##
	## Previously a hardcoded movie list sent every minigame and meeting to
	## DAY1 @shore2. That teleported ARCADE2 out of the hotel, ignored SEA1's own
	## return label, and left anything off the list — most visibly JOKE, reachable
	## from DAY1, HOTEL1 and AIR1 — frozen on its final frame.
	var movie := loader.movie_name
	if movie == "" or loader.frames.is_empty():
		return

	# Hubs hold. Routing one to its caller would eject the player from the room
	# they are standing in.
	if context.is_hub(movie):
		enter_frame(loader.frames.size() - 1)
		return

	if movie.to_upper() in ["HEZSAVE", "SAVELOAD", "MAP"]:
		go_back()
		return

	# The movie's own declared hub return comes first. Using the caller here
	# would livelock SEA1 and AIR1, whose launching DAY1 frames are themselves
	# `movie sea1` / `movie air1`.
	var hub_return: Dictionary = context.hub_return(loader)
	if not hub_return.is_empty():
		var target := _s(hub_return.get("movie", ""))
		nav_event.emit("movie end: %s → %s" % [movie, target])
		var opts := {"label": hub_return.get("label", null)}
		var routed := goto_movie(target, hub_return.get("frame", null), opts)
		if routed:
			return

	# No declared return, so fall back to whoever called us. This is JOKE's path.
	if go_back():
		nav_event.emit("movie end: %s → caller" % movie)
		return

	var hub := GameState.current_hub()
	if goto_movie(hub):
		nav_event.emit("movie end: %s → hub %s" % [movie, hub])
		return

	# Nothing routed. Hold on the last frame rather than re-running this handler
	# on every tick.
	GameState.emit_log("movie end: %s has nowhere to go — holding" % movie, "warn")
	enter_frame(loader.frames.size() - 1)


func skip_current() -> void:
	if not AppSettings.allow_minigame_skip:
		return
	var m := loader.movie_name.to_upper()
	if m == "STRTGAME":
		var menu_frame := loader.lookup_label("mainmenu")
		if menu_frame >= 0 and frame_index < menu_frame:
			nav_event.emit("QoL skip → main menu")
			enter_frame(menu_frame)
			return
	if m == "EXODUS":
		nav_event.emit("QoL skip → DAY1")
		GameState.new_game()
		goto_movie("DAY1", null, {"label": "shore2"})
		return
	if GameState.is_minigame_movie(m):
		# Skipping a minigame exits the same way finishing it would, so skipping
		# in the hotel arcade no longer drops the player on the Day 1 shore.
		nav_event.emit("QoL skip → %s exit" % m)
		_on_movie_end()


func dev_skip_scene() -> String:
	## Development aid: leave the current movie the way finishing it would, with
	## none of skip_current()'s restrictions. skip_current() only fires for the
	## title, EXODUS and the declared minigames, which is most of what you want
	## to skip while playing but useless when you are trying to reach a specific
	## room. Returns a short description for the caller to surface.
	var movie := loader.movie_name
	if movie == "" or loader.frames.is_empty():
		return "nothing loaded"
	AudioDirector.stop_all()
	waiting_for_click = false
	puppet.reset()
	if context.is_hub(movie):
		# A hub has nowhere to exit to, so hand it to its own phase transition,
		# or fall through to the next room the score would reach.
		_try_phase_transition()
		if loader.movie_name == movie:
			_advance_or_hold()
		nav_event.emit("dev skip: %s" % movie)
		return "advanced %s" % movie
	_on_movie_end()
	nav_event.emit("dev skip: %s → %s" % [movie, loader.movie_name])
	return "%s → %s" % [movie, loader.movie_name]


func hint() -> void:
	var clicks := clickable_sprites(loader.get_frame(frame_index))
	if clicks.is_empty():
		nav_event.emit("Hint: no clickable hotspots")
		return
	var s: Dictionary = clicks[0]
	nav_event.emit("Hint: ch%d → %s" % [int(s.get("channel", 0)), NavActions.describe(s.get("on_click", {}).get("nav", {}))])


func clickable_sprites(frame: Dictionary) -> Array:
	var out: Array = []
	for sprite in frame.get("sprites", []):
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		if not bool(sprite.get("clickable", false)):
			continue
		if is_channel_hidden(int(sprite.get("channel", 0))):
			continue
		var on_click: Dictionary = sprite.get("on_click", {})
		var nav: Variant = on_click.get("nav", null)
		var inv_v: Variant = on_click.get("inventory", null)
		var snd_v: Variant = on_click.get("sounds", null)
		var has_inv: bool = typeof(inv_v) == TYPE_ARRAY and (inv_v as Array).size() > 0
		var has_sounds: bool = typeof(snd_v) == TYPE_ARRAY and (snd_v as Array).size() > 0
		if nav == null and not has_inv and not has_sounds:
			continue
		if typeof(nav) == TYPE_DICTIONARY and _s(nav.get("kind", "")) == "unsupported":
			continue
		out.append(sprite)
	out.sort_custom(func(a, b): return int(a.get("channel", 0)) > int(b.get("channel", 0)))
	return out


func sprite_stage_rect(sprite: Dictionary) -> Rect2:
	var x := float(sprite.get("x", 0))
	var y := float(sprite.get("y", 0))
	var w := float(sprite.get("width", 1))
	var h := float(sprite.get("height", 1))
	if AppSettings.expand_edge_hotspots:
		var stage_w := float(loader.stage_size.x)
		var stage_h := float(loader.stage_size.y)
		var tall := h > stage_h * 0.55 and w < stage_w * 0.12
		var wide := w > stage_w * 0.55 and h < stage_h * 0.12
		if tall and x + w >= stage_w - 8.0:
			w = maxf(w, stage_w - x + 200.0)
		if tall and x <= 8.0:
			x -= 200.0
			w += 200.0
		if wide and y + h >= stage_h - 8.0:
			h = maxf(h, stage_h - y + 200.0)
		if wide and y <= 8.0:
			y -= 200.0
			h += 200.0
	return Rect2(x, y, w, h)


func sprite_contains(sprite: Dictionary, stage_pos: Vector2) -> bool:
	return sprite_stage_rect(sprite).has_point(stage_pos)


func marker_name_for_frame(idx: int) -> String:
	var best := ""
	var best_f := -1
	for m in loader.markers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var f := int(m.get("frame", -1))
		if f <= idx and f >= best_f:
			best_f = f
			best = _s(m.get("name", ""))
	return best


func label_near_frame(idx: int) -> String:
	var best := ""
	var best_f := -1
	for key in loader.labels.keys():
		var f := int(loader.labels[key])
		if f <= idx and f >= best_f:
			best_f = f
			best = _s(key)
	return best
