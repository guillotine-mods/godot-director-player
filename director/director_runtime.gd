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
## Piposh. Puppeted by every hub's `init all`, so the score never drives it and
## PuppetController is what the channel shows.
const PUPPET_CHANNEL := 30
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
## Built on demand: loading every cast's scripts costs time a normal run should
## not pay when the interpreter is off.
var lingo: LingoEngine = null

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
## The frame the playhead came from, so _run_skipped_entry_scripts() can tell an
## arrival from a step taken inside the room it is already in. -1 means "nowhere in
## this movie", which is the state a movie load leaves behind.
var _entered_from: int = -1
var _hidden_channels: Dictionary = {}
var _head_look_until_ms: float = -1.0

## channel -> SpriteChannel. Director's live channel array: the score writes it when
## the playhead moves, a puppeted channel belongs to Lingo, and drawing and
## hit-testing read it rather than the score frame. Built by reconcile_channels().
var channels: Dictionary = {}


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
	if AppSettings.use_lingo_clicks or AppSettings.use_lingo_frames:
		lingo = LingoEngine.new(self)
	GameState.set_meeting_triggers(context.meeting_triggers())
	return loader.load_index()


func available_movies() -> PackedStringArray:
	return loader.available_movies()


func _mark_movie_transition_attempted() -> void:
	_movie_transition_attempt_generation += 1


func _mark_movie_loaded() -> void:
	_accum_ms = 0.0
	_clear_pending_transition()
	# Channels belong to the movie. Clearing them drops the previous movie's puppet
	# ownership, its `sprite(N).visible = 0` hides and its film-loop cursors in one
	# go: channel N in the next movie is unrelated artwork. The destination's own
	# `init all` re-hides whatever it wants hidden.
	channels.clear()
	# Frame numbers do not carry across a movie, so the previous one says nothing
	# about whether the next entry skipped anything.
	_entered_from = -1
	if context.is_hub(loader.movie_name):
		GameState.enter_hub(loader.movie_name)


func channel_for(channel: int) -> SpriteChannel:
	## Channels are created on demand: a script may puppet and drive a channel the
	## current frame does not mention.
	var existing: Variant = channels.get(channel, null)
	if existing != null:
		return existing
	var made := SpriteChannel.new()
	made.number = channel
	channels[channel] = made
	return made


func effective_sprite(channel: int) -> Dictionary:
	## What channel N actually holds: score sprite with Lingo's writes applied.
	var entry: Variant = channels.get(channel, null)
	return {} if entry == null else (entry as SpriteChannel).sprite


func channel_sprites() -> Array:
	## Every non-empty channel, low to high, which is Director's draw order.
	var out: Array = []
	var numbers: Array = channels.keys()
	numbers.sort()
	for number in numbers:
		var entry: SpriteChannel = channels[number]
		if not entry.is_empty():
			out.append(entry.sprite)
	return out


func reconcile_channels(frame: Dictionary) -> void:
	## Director's per-frame reconcile: overwrite each channel from the incoming
	## frame's sprite, except where a script owns the channel. Channels the frame
	## does not mention are emptied, again except when puppeted.
	##
	## This runs before the frame's own scripts are dispatched, so an `on enterFrame`
	## that reads `the memberNum of sprite N` sees the new frame, not the old one.
	var seen: Dictionary = {}
	var sprites: Variant = frame.get("sprites", [])
	if typeof(sprites) == TYPE_ARRAY:
		for sprite_value in sprites as Array:
			if typeof(sprite_value) != TYPE_DICTIONARY:
				continue
			var sprite: Dictionary = sprite_value
			var number := int(sprite.get("channel", 0))
			if number <= 0:
				continue
			seen[number] = true
			channel_for(number).replace_from_score(sprite)
	for number in channels.keys():
		if not seen.has(number):
			(channels[number] as SpriteChannel).clear_score()
	_sync_film_loops()


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

	# The original `on exitFrame` is 2504 of the game's 3457 handlers. When one
	# exists and navigates, it decides where the score goes and the exported nav
	# is not consulted; a hold stops here too. Anything else falls through to the
	# existing resolution.
	if lingo != null and AppSettings.use_lingo_frames:
		if lingo.dispatch_frame_event("exitFrame", frame_index):
			if lingo.host.stage_dirty:
				lingo.host.stage_dirty = false
				redraw_requested.emit()
			if lingo.host.navigated or lingo.host.held:
				return

	# Only once the interpreter has passed. A room transition ends on
	# BehaviorScript 207, and that script already knows where to go — it reads
	# `item 1 of nextroomdata`, which the room's own mouseUp handler wrote. The
	# redirect below is the stand-in for movies where that script does not run,
	# and it answers the same question out of a hand-authored table.
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

	# Reaching here means the interpreted BehaviorScript 207 did not run or did
	# not navigate, so this is standing in for it — and the whole script, not
	# only its `go`. Its second line is `set the visible of sprite 30 to 1`,
	# which ends the hide the walk's handover started. Dropping it would leave
	# the puppet invisible for the rest of the movie.
	set_channel_visible(PUPPET_CHANNEL, true)

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
	if channel == PUPPET_CHANNEL:
		return not puppet.visible
	if _hidden_channels.has(channel):
		return true
	var entry: Variant = channels.get(channel, null)
	return entry != null and not (entry as SpriteChannel).visible


func set_channel_visible(channel: int, visible: bool) -> void:
	## `sprite(N).visible = 0` from an interpreted script.
	if channel == PUPPET_CHANNEL:
		# Channel 30 is the puppet, so its visibility is the puppet's, not a
		# separate flag on the channel that the renderer would have to consult
		# twice. This is the path `set the visible of sprite 30 to 1` takes out of
		# BehaviorScript 207 and out of SEA1's and AIR1's room scripts.
		if puppet.visible == visible:
			return
		puppet.visible = visible
		redraw_requested.emit()
		return
	var entry := channel_for(channel)
	if entry.visible == visible:
		return
	entry.visible = visible
	redraw_requested.emit()


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
	for slot_channel in slots:
		var channel := int(slot_channel)
		var sprite := effective_sprite(channel)
		if sprite.is_empty() or is_channel_hidden(channel):
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
	var sprite := effective_sprite(channel)
	if sprite.is_empty() or is_channel_hidden(channel):
		return Rect2()
	return sprite_stage_rect(sprite)


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
	var came_from := frame_index
	frame_index = clampi(index, 0, loader.frames.size() - 1)
	_entered_from = came_from
	frame_entered_ms = _time_ms
	var frame: Dictionary = loader.get_frame(frame_index)
	reconcile_channels(frame)
	var fps := float(frame.get("fps", 0))
	if fps > 0.0:
		current_fps = fps
	waiting_for_click = bool(frame.get("wait_click", false))
	var room := marker_name_for_frame(frame_index)
	_hidden_channels = context.hidden_channels(loader.movie_name, room)
	puppet.sync_from_frame(frame, room, loader.stage_size)
	# `on enterFrame` is where the original records which room the player is in.
	# 13 handlers set the `whereami` global here, and 138 mouseUp handlers gate
	# their real behaviour on it: ISLAND2's `arcade1` only sets the movie-launch
	# flag `if whereami = label("arcade")`. Without this dispatch `whereami` is
	# never assigned, every one of those gates is false, and the hotspots fall
	# through to a generic branch that walks nowhere.
	if lingo != null and AppSettings.use_lingo_frames:
		_run_skipped_entry_scripts()
		lingo.host.begin_dispatch()
		lingo.dispatch_sprite_behaviours("enterFrame", frame_index)
		lingo.dispatch_frame_event("enterFrame", frame_index)
		if lingo.host.stage_dirty:
			lingo.host.stage_dirty = false
			redraw_requested.emit()
	AudioDirector.play_frame_sounds(frame)
	GameState.remember_location(loader.movie_name, label_near_frame(frame_index), frame_index)
	frame_changed.emit(frame_index)
	redraw_requested.emit()


func handle_key(code: int) -> bool:
	## Director routes every keypress through `the keyDownScript`. Returns true
	## when a script claimed it, so the caller can leave the event alone.
	if lingo == null or not AppSettings.use_lingo_frames:
		return false
	var script_name := str(lingo.host.key_down_script)
	if script_name == "" or not lingo.interpreter.has_handler(script_name):
		return false
	lingo.host.begin_dispatch()
	lingo.host.key_code = code
	lingo.interpreter.call_handler(script_name)
	lingo.host.key_code = 0
	return true


func _run_skipped_entry_scripts() -> void:
	## Jumping straight to a room's `*go` frame skips the frames the score would
	## have played on the way in, and one of them is where the room announces
	## itself: HOTEL1 frame 436 runs `whereami = label(0)`, and `arcadego` is 437.
	##
	## It cannot be recovered by running enterFrame on the `*go` frame instead,
	## because `label(0)` there resolves to `arcadego` while every hotspot tests
	## against `label("arcade")`. The entry frames have to execute where they sit,
	## so their handlers run here, in score order, before the arrival frame's own.
	##
	## Both events, not just enterFrame. DAY1's dwarfs room is
	## 1473 (script 83, `on enterFrame`) → 1474 (script 286, `on exitFrame`) →
	## 1475 `dwarfsgo`. Script 83 blanks sprites 15, 17 and 33; script 286 is the
	## one that puts them back, scanning `objectsfield` and showing sprite 17
	## unless the player already holds `masor`. Replaying only enterFrame ran the
	## blanking and never the restore, so every collectable in the game stayed
	## invisible.
	##
	## Replayed under `record`, which captures navigation and sound instead of
	## performing them: these frames are being fast-forwarded, so a `go` in one of
	## them must not hijack the arrival, and their entry sounds must not fire.
	var room := marker_name_for_frame(frame_index).to_lower()
	if not room.ends_with("go"):
		return
	var base := loader.lookup_label(room.substr(0, room.length() - 2))
	if base < 0 or base >= frame_index:
		return
	var landed := frame_index
	# Only on arrival from outside the room. Replaying the entry frames re-runs their
	# blanking — `b4 bk's` sets sprites 15, 17 and 33 invisible, which are the
	# collectable channels — so a shell `searchfunk` had just uncovered vanished
	# again. The conditional restore in script 286 does not bring it back: it only
	# ever shows what the player does *not* already hold.
	#
	# "Inside the room" is the marker, not the entry span. The room's own loop is
	# `go(marker(0))`, which jumps the playhead from anywhere in the idle span back to
	# the `*go` frame — 266 → 239 at DAY1's gate, where `gatego` runs 239 to 269 and
	# `gatetoshore` starts at 270. Every one of those jumps looks like an arrival by
	# frame number and is not one. Arriving from the base label is not one either:
	# those frames just played, which is the case this whole function exists to
	# compensate for when they do not.
	if _entered_from >= 0:
		var came_from_room := marker_name_for_frame(_entered_from).to_lower()
		if came_from_room == room or came_from_room == room.substr(0, room.length() - 2):
			return
	var was_recording: bool = lingo.host.record
	lingo.host.begin_record()
	for index in range(base, landed):
		if loader.get_frame(index).get("frame_script") == null:
			continue
		frame_index = index
		lingo.host.begin_dispatch()
		lingo.dispatch_frame_event("enterFrame", index)
		lingo.host.begin_dispatch()
		lingo.dispatch_frame_event("exitFrame", index)
	lingo.host.record = was_recording
	frame_index = landed


func _sync_film_loops() -> void:
	## The loop cursor lives on the channel now, so a puppeted `set the memberNum of
	## sprite N` restarts the loop through SpriteChannel.set_member() rather than
	## going unnoticed because the score frame never changed.
	for number in channels.keys():
		var entry: SpriteChannel = channels[number]
		if entry.is_empty():
			continue
		var cast_lib := int(entry.sprite.get("cast_lib", -1))
		var cast_id := int(entry.sprite.get("cast_id", -1))
		if cast_lib < 0 or cast_id < 0:
			continue
		var film_loop := loader.get_film_loop(cast_lib, cast_id)
		var loop_frame_count := _film_loop_frame_count(film_loop)
		if loop_frame_count == 0:
			entry.loop_cast_lib = -1
			entry.loop_cast_id = -1
			entry.loop_frame = 0
			continue

		var same_loop := entry.loop_cast_lib == cast_lib and entry.loop_cast_id == cast_id
		if not same_loop:
			entry.loop_frame = 0
		else:
			entry.loop_frame = clampi(entry.loop_frame, 0, loop_frame_count - 1)
			if entry.loop_score_frame != frame_index:
				if bool(film_loop.get("looping", false)):
					entry.loop_frame = (entry.loop_frame + 1) % loop_frame_count
				else:
					entry.loop_frame = mini(entry.loop_frame + 1, loop_frame_count - 1)
		entry.loop_cast_lib = cast_lib
		entry.loop_cast_id = cast_id
		entry.loop_score_frame = frame_index


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
	var entry: Variant = channels.get(channel, null)
	return 0 if entry == null else maxi(0, (entry as SpriteChannel).loop_frame)


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

	if lingo != null:
		lingo.prepare_movie(movie_name)
		# The corpus has exactly one `on startMovie`, and all it does is
		# `set the keyDownScript to "fromnow"`, which is what makes a keypress
		# cut the line of speech that is playing. Cheap to honour, and it is the
		# only route key input has into the original scripts.
		if AppSettings.use_lingo_frames and lingo.interpreter.has_handler("startmovie"):
			lingo.host.begin_dispatch()
			lingo.interpreter.call_handler("startmovie")
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
	# Same as goto_movie: the interpreter has to be told which movie it is in, or every
	# script resolves against the one being left. Without this, coming back from the
	# joke window left `_current_movie` on JOKE, so `frame_script(1858)` looked for
	# member 83 in JOKE's casts, found nothing, and the room's entry scripts silently
	# did not run. That is what left every collectable on show after a round trip: the
	# blanking in `b4 bk's` never executed. It killed the room's `enterFrame` work too,
	# so `whereami` went stale and the hotspots gated on it took their dead branches.
	if lingo != null:
		lingo.prepare_movie(loader.movie_name)
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
	# The original script wins when it exists and the interpreter is enabled;
	# otherwise the lifted on_click data stands, so nothing regresses. The flag
	# must be checked here as well as at construction: the engine is built when
	# either flag is on, so testing `lingo != null` alone let use_lingo_frames
	# silently take clicks too, which broke every walk hotspot.
	if lingo != null and AppSettings.use_lingo_clicks:
		var channel_clicked := int(sprite.get("channel", 0))
		if lingo.has_any_handler_for(channel_clicked, frame_index, "mouseUp"):
			lingo.host.mouse_stage = stage_pt
			lingo.dispatch_sprite_event("mouseDown", channel_clicked, frame_index)
			lingo.dispatch_sprite_event("mouseUp", channel_clicked, frame_index)
			if lingo.host.stage_dirty:
				lingo.host.stage_dirty = false
				redraw_requested.emit()
			nav_event.emit("lingo: ch%d mouseUp" % channel_clicked)
			return
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


func _lingo_takes_clicks(channel: int) -> bool:
	## Whether an interpreted script would act on a click here, for sprites the
	## export left with no on_click of their own.
	if lingo == null or not AppSettings.use_lingo_clicks:
		return false
	return lingo.has_any_handler_for(channel, frame_index, "mouseUp")


func clickable_sprites(frame: Dictionary = {}) -> Array:
	## For the frame the playhead is on, this reads channels rather than the score, so
	## a hotspot a script has moved or re-membered is clickable where it is now.
	##
	## An explicit *other* frame still reads that frame's own sprites. Harnesses sweep
	## frames they have not entered (tools/lingo_walk_diff.gd enumerates every walk
	## hotspot in a movie), and channels only ever describe the current frame. Making
	## the argument a no-op took that sweep from 117 cases to 0 while still reporting
	## success, which is the failure mode this repo has been bitten by before.
	var source: Array = []
	var current := frame.is_empty() or int(frame.get("frame_index", frame_index)) == frame_index
	if current:
		source = channel_sprites()
	if source.is_empty() and not frame.is_empty():
		# Either an explicitly different frame, or a frame whose channels were never
		# populated: tools/lingo_walk_diff.gd assigns `frame_index` directly to sweep
		# rooms it does not enter. Fall back to the score's own sprites rather than to
		# nothing, so a caller that never reconciled sees what it saw before.
		var listed: Variant = frame.get("sprites", [])
		source = (listed as Array).duplicate() if typeof(listed) == TYPE_ARRAY else []
		source.sort_custom(func(a, b): return int(a.get("channel", 0)) < int(b.get("channel", 0)))

	var out: Array = []
	for sprite in source:
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		var channel := int(sprite.get("channel", 0))
		if is_channel_hidden(channel):
			continue
		var on_click: Dictionary = sprite.get("on_click", {})
		var nav: Variant = on_click.get("nav", null)
		var inv_v: Variant = on_click.get("inventory", null)
		var snd_v: Variant = on_click.get("sounds", null)
		var has_inv: bool = typeof(inv_v) == TYPE_ARRAY and (inv_v as Array).size() > 0
		var has_sounds: bool = typeof(snd_v) == TYPE_ARRAY and (snd_v as Array).size() > 0
		var lifted: bool = (
			bool(sprite.get("clickable", false))
			and (nav != null or has_inv or has_sounds)
		)
		# A hotspot the export could not lift is still a hotspot. The searchable
		# scenery is the clearest case: `edge1_bench` is island2:74 on channel 8
		# at edge1go with no exported on_click at all, because everything it does
		# lives in MASTER's `searchfunk` — walk over, then reveal the shell on
		# channel 15 with found.aif. Filtering on the lifted data alone made every
		# one of those unclickable, so no shell or bottle could ever be found.
		if not lifted and not _lingo_takes_clicks(channel):
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
