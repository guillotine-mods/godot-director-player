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

var loader: RenderModelLoader = RenderModelLoader.new()
var puppet: PuppetController = PuppetController.new()

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


func _s(v: Variant, fallback: String = "") -> String:
	## Godot 4.7: String(variant) is invalid — use str().
	if v == null:
		return fallback
	return str(v)


func _init() -> void:
	puppet.arrived.connect(_on_puppet_arrived)
	puppet.changed.connect(func(): redraw_requested.emit())


func boot() -> Error:
	return loader.load_index()


func available_movies() -> PackedStringArray:
	return loader.available_movies()


func _mark_movie_transition_attempted() -> void:
	_movie_transition_attempt_generation += 1


func _mark_movie_loaded() -> void:
	_accum_ms = 0.0


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
	var fps := float(frame.get("fps", 0))
	if fps > 0.0:
		current_fps = fps
	waiting_for_click = bool(frame.get("wait_click", false))
	puppet.sync_from_frame(frame, marker_name_for_frame(frame_index), loader.stage_size)
	AudioDirector.play_frame_sounds(frame)
	GameState.remember_location(loader.movie_name, label_near_frame(frame_index), frame_index)
	frame_changed.emit(frame_index)
	redraw_requested.emit()


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

	GameState.emit_log("Loading movie %s …" % movie_name, "info")
	var err := loader.load_movie(movie_name)
	if err != OK:
		GameState.emit_log("Failed to load movie %s" % movie_name, "error")
		return false
	_mark_movie_loaded()

	if to == "exodus" and from in ["strtgame", "saveload", ""]:
		GameState.new_game()

	if to == "day1" and from != "" and from not in ["day1", "strtgame", "exodus"]:
		GameState.mark_meeting_done_by_movie(from)

	if not (to == "day1" and from not in ["", "strtgame", "exodus", "day1"]):
		if from_movie_name != "":
			route_stack.append({"movie": from_movie_name, "frame": frame_index})
	elif not route_stack.is_empty():
		var top: Dictionary = route_stack[route_stack.size() - 1]
		if _s(top.get("movie", "")).to_lower() == from:
			route_stack.pop_back()

	AudioDirector.stop_all()

	waiting_for_click = false
	menu_hover_channel = -1
	hovered_sprite = {}

	if to in ["strtgame", "exodus"] or (to == "day1" and from in ["strtgame", "exodus", ""]):
		puppet.reset()

	var start := 0
	if label_opt != "":
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

	if to == "day1" and label_opt != "" and not bool(opts.get("from_meeting", false)):
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
			var ok: bool = puppet.start_walk(
				action.get("nav", nav),
				stage_pt,
				loader.stage_size,
				marker_name_for_frame(frame_index)
			)
			if ok:
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
	if meet == "":
		return
	nav_event.emit("peoplefunk → %s" % meet)
	goto_movie(meet, 1, {"from_meeting": true})


func _on_movie_end() -> void:
	var m := loader.movie_name.to_upper()
	if m == "EXODUS":
		goto_movie("DAY1", null, {"label": "shore2"})
		return
	if m in ["HEZSAVE", "SAVELOAD", "MAP"]:
		go_back()
		return
	if GameState.is_minigame_movie(m) or m in ["MURDER1", "HATDAY1", "MRFDAY1", "PATDAY1", "ISHDAY1", "TOFIRCPT", "ALLIN", "GOLDDEAD"]:
		GameState.mark_meeting_done_by_movie(m)
		goto_movie("DAY1", null, {"label": "shore2"})
		return
	enter_frame(loader.frames.size() - 1)


func skip_current() -> void:
	if not AppSettings.allow_minigame_skip:
		return
	var m := loader.movie_name.to_upper()
	if GameState.is_minigame_movie(m) or m == "EXODUS":
		nav_event.emit("QoL skip → DAY1")
		if m == "EXODUS":
			GameState.new_game()
		goto_movie("DAY1", null, {"label": "shore2"})


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
