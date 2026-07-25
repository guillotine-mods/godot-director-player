class_name MoviePlayer
extends Control
## View + input shell around DirectorRuntime (score runner).

signal movie_changed(movie: String)
signal frame_changed(frame: int)
signal nav_event(description: String)
signal save_ui_requested(mode: String)

const STRTGAME_MENU_HOVER := {
	4: {"normal": 316, "hover": 356},
	5: {"normal": 327, "hover": 355},
	6: {"normal": 336, "hover": 354},
	7: {"normal": 325, "hover": 353},
}

@onready var stage_host: Control = %StageHost
@onready var stage_canvas: Control = %StageCanvas
@onready var virtual_cursor: ColorRect = %VirtualCursor
@onready var letterbox: ColorRect = %Letterbox

var runtime: DirectorRuntime = DirectorRuntime.new()
var _view: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if runtime.boot() != OK:
		push_error("Failed to load render_model index")
		return

	runtime.movie_changed.connect(func(m): movie_changed.emit(m))
	runtime.frame_changed.connect(func(f): frame_changed.emit(f))
	runtime.nav_event.connect(func(d): nav_event.emit(d))
	runtime.quit_requested.connect(func(): get_tree().quit())
	runtime.redraw_requested.connect(func(): if stage_canvas: stage_canvas.queue_redraw())
	runtime.save_ui_requested.connect(_on_save_ui_requested)

	InputRouter.stage_click.connect(_on_stage_click)
	InputRouter.stage_hover.connect(_on_stage_hover)
	InputRouter.hint_requested.connect(func(): runtime.hint())
	InputRouter.skip_requested.connect(func(): runtime.skip_current())
	AppSettings.settings_changed.connect(_on_settings_changed)
	GameState.movie_requested.connect(_on_game_state_movie_requested)

	_on_settings_changed()
	runtime.goto_movie("strtgame", null, {"play_opening": true})
	_log_frame_texture_stats("boot")


func _process(delta: float) -> void:
	_update_view_transform()
	_update_virtual_cursor_visual()
	runtime.tick(delta)
	if stage_canvas:
		stage_canvas.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		InputRouter.notify_mouse_stage_pos(screen_to_stage(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		InputRouter.notify_mouse_click(screen_to_stage(event.position))
		accept_event()


func available_movies() -> PackedStringArray:
	return runtime.available_movies()


func goto_movie(movie: String, at: Variant = null) -> void:
	if typeof(at) == TYPE_STRING and str(at) != "":
		runtime.goto_movie(movie, null, {"label": str(at)})
	elif typeof(at) == TYPE_INT or typeof(at) == TYPE_FLOAT:
		# Convenience: treat as 0-based index from editor tools.
		runtime.goto_movie(movie, int(at) + 1)
	else:
		runtime.goto_movie(movie)


## Compatibility accessors used by HUD / save editor.
var loader: RenderModelLoader:
	get:
		return runtime.loader

var frame_index: int:
	get:
		return runtime.frame_index


func _on_stage_hover(stage_pos: Vector2) -> void:
	runtime.update_hover(stage_pos)


func _on_stage_click(stage_pos: Vector2) -> void:
	runtime.perform_click(stage_pos)


func _on_settings_changed() -> void:
	var filter := (
		CanvasItem.TEXTURE_FILTER_LINEAR
		if AppSettings.use_smooth_filter()
		else CanvasItem.TEXTURE_FILTER_NEAREST
	)
	texture_filter = filter
	if stage_canvas:
		stage_canvas.texture_filter = filter
	_update_view_transform()


func _on_game_state_movie_requested(movie: String, frame_or_label: Variant) -> void:
	goto_movie(movie, frame_or_label)


func _on_save_ui_requested(mode: String) -> void:
	save_ui_requested.emit(mode)


func _registry_score_stage_position(sprite: Dictionary, member: Dictionary) -> Vector2:
	var sprite_width: float = float(sprite.get("width", 1))
	var sprite_height: float = float(sprite.get("height", 1))
	var member_width: float = maxf(float(member.get("width", 1)), 1.0)
	var member_height: float = maxf(float(member.get("height", 1)), 1.0)
	var reg_x: float = float(member.get("reg_offset_x", member_width * 0.5))
	var reg_y: float = float(member.get("reg_offset_y", member_height * 0.5))
	var loc_h: float = float(sprite.get("loc_h", sprite.get("x", 0)))
	var loc_v: float = float(sprite.get("loc_v", sprite.get("y", 0)))
	return Vector2(
		loc_h - reg_x * sprite_width / member_width,
		loc_v - reg_y * sprite_height / member_height,
	)


func _is_film_loop_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _film_loop_initial_rect(film_loop: Dictionary) -> Dictionary:
	var initial_rect_value: Variant = film_loop.get("initial_rect", {})
	if typeof(initial_rect_value) != TYPE_DICTIONARY:
		return {}
	var initial_rect: Dictionary = initial_rect_value
	for field in ["top", "left", "bottom", "right"]:
		if not initial_rect.has(field) or not _is_film_loop_number(initial_rect[field]):
			return {}
	return initial_rect


func _film_loop_parent_rect(sprite: Dictionary, film_loop: Dictionary) -> Rect2:
	var initial_rect := _film_loop_initial_rect(film_loop)
	if initial_rect.is_empty():
		return Rect2()
	var initial_width: float = float(initial_rect.right) - float(initial_rect.left)
	var initial_height: float = float(initial_rect.bottom) - float(initial_rect.top)
	var parent_width: float = float(sprite.get("width", film_loop.get("width", 0)))
	var parent_height: float = float(sprite.get("height", film_loop.get("height", 0)))
	if initial_width <= 0.0 or initial_height <= 0.0 or parent_width <= 0.0 or parent_height <= 0.0:
		return Rect2()

	var loc_h: float = float(sprite.get("loc_h", sprite.get("x", 0)))
	var loc_v: float = float(sprite.get("loc_v", sprite.get("y", 0)))
	return Rect2(loc_h - floor(parent_width * 0.5), loc_v - floor(parent_height * 0.5), parent_width, parent_height)


func _is_valid_film_loop_child(child_value: Variant) -> bool:
	if typeof(child_value) != TYPE_DICTIONARY:
		return false
	var child: Dictionary = child_value
	for field in ["channel", "cast_id", "start_x", "start_y", "width", "height", "ink"]:
		if not child.has(field) or not _is_film_loop_number(child[field]):
			return false
	return true


func _film_loop_child_channel(child: Dictionary) -> int:
	return int(child.channel)


func _draw_film_loop(
	canvas: Control,
	sprite: Dictionary,
	film_loop: Dictionary,
	channel: int,
	sx: float,
	sy: float,
) -> void:
	var parent_rect := _film_loop_parent_rect(sprite, film_loop)
	if parent_rect.size.x <= 0.0 or parent_rect.size.y <= 0.0:
		return
	var frames_value: Variant = film_loop.get("frames", [])
	if typeof(frames_value) != TYPE_ARRAY:
		return
	var frames: Array = frames_value
	if frames.is_empty():
		return

	var selected_index: int = clampi(runtime.film_loop_frame(channel), 0, frames.size() - 1)
	var selected_frame_value: Variant = frames[selected_index]
	if typeof(selected_frame_value) != TYPE_DICTIONARY:
		return
	var selected_frame: Dictionary = selected_frame_value
	var child_sprites_value: Variant = selected_frame.get("sprites", [])
	if typeof(child_sprites_value) != TYPE_ARRAY:
		return
	var child_sprites: Array = []
	for child_value in child_sprites_value:
		if _is_valid_film_loop_child(child_value):
			child_sprites.append(child_value)
	child_sprites.sort_custom(func(a, b): return _film_loop_child_channel(a) < _film_loop_child_channel(b))

	var initial_rect := _film_loop_initial_rect(film_loop)
	if initial_rect.is_empty():
		return
	var initial_left: float = float(initial_rect.left)
	var initial_top: float = float(initial_rect.top)
	var initial_width: float = float(initial_rect.right) - initial_left
	var initial_height: float = float(initial_rect.bottom) - initial_top
	var stage_scale := Vector2(parent_rect.size.x / initial_width, parent_rect.size.y / initial_height)
	var registry_cast_name: String = str(film_loop.get("_registry_cast_name", ""))

	for child_value in child_sprites:
		var child: Dictionary = child_value
		var child_cast_id: int = int(child.cast_id)
		var child_member: Dictionary = runtime.loader.get_registry_member(registry_cast_name, child_cast_id)
		if child_member.is_empty():
			continue
		var child_ink: int = int(child.ink)
		var child_texture: Texture2D = runtime.loader.get_registry_texture(
			registry_cast_name,
			child_cast_id,
			RenderModelLoader.is_transparent_ink(child_ink),
		)
		if child_texture == null:
			continue

		var child_width: float = float(child.width)
		var child_height: float = float(child.height)
		var draw_width: float = child_width * stage_scale.x
		var draw_height: float = child_height * stage_scale.y
		if draw_width <= 0.0 or draw_height <= 0.0:
			continue
		var child_start := parent_rect.position + Vector2(
			(float(child.start_x) - initial_left) * stage_scale.x,
			(float(child.start_y) - initial_top) * stage_scale.y,
		)
		var member_width: float = maxf(float(child_member.get("width", 1)), 1.0)
		var member_height: float = maxf(float(child_member.get("height", 1)), 1.0)
		var reg_x: float = float(child_member.get("reg_offset_x", member_width * 0.5))
		var reg_y: float = float(child_member.get("reg_offset_y", member_height * 0.5))
		var child_top_left := child_start - Vector2(
			reg_x * draw_width / member_width,
			reg_y * draw_height / member_height,
		)
		canvas.draw_texture_rect(
			child_texture,
			Rect2(child_top_left.x * sx, child_top_left.y * sy, draw_width * sx, draw_height * sy),
			false,
		)

func _log_frame_texture_stats(tag: String) -> void:
	var frame: Dictionary = runtime.loader.get_frame(runtime.frame_index)
	var ok := 0
	var miss := 0
	for sprite in frame.get("sprites", []):
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		var has_image: bool = bool(sprite.get("has_image", false))
		if not has_image:
			var member: Dictionary = runtime.loader.get_linked_member(
				int(sprite.get("cast_lib", 1)), int(sprite.get("cast_id", 0))
			)
			if member.is_empty():
				continue
		var tex: Texture2D = runtime.loader.get_texture(
			int(sprite.get("cast_lib", 1)),
			int(sprite.get("cast_id", 0)),
			RenderModelLoader.is_transparent_ink(int(sprite.get("ink", 0)))
		)
		if tex:
			ok += 1
		else:
			miss += 1
	GameState.emit_log(
		"Textures[%s] %s@%d ok=%d miss=%d audio_stems=%d" % [
			tag,
			runtime.loader.movie_name,
			runtime.frame_index + 1,
			ok,
			miss,
			AudioDirector._stem_index.size() if AudioDirector._indexed else -1,
		],
		"info"
	)


func screen_to_stage(local_pos: Vector2) -> Vector2:
	_update_view_transform()
	var stage := Vector2(runtime.loader.stage_size)
	if AppSettings.aspect_mode == AppSettings.AspectMode.STRETCH_FILL:
		return Vector2(
			local_pos.x / maxf(size.x, 1.0) * stage.x,
			local_pos.y / maxf(size.y, 1.0) * stage.y
		)
	var fit: float = _view.get("fit_scale", 1.0)
	var origin: Vector2 = _view.get("origin", Vector2.ZERO)
	return (local_pos - origin) / maxf(fit, 0.0001)


func stage_to_screen(stage_pos: Vector2) -> Vector2:
	_update_view_transform()
	var stage := Vector2(runtime.loader.stage_size)
	if AppSettings.aspect_mode == AppSettings.AspectMode.STRETCH_FILL:
		return Vector2(stage_pos.x / stage.x * size.x, stage_pos.y / stage.y * size.y)
	return _view.get("origin", Vector2.ZERO) + stage_pos * float(_view.get("fit_scale", 1.0))


func _update_view_transform() -> void:
	var stage := Vector2(runtime.loader.stage_size)
	var view := size
	if view.x <= 1.0 or view.y <= 1.0:
		_view = {"fit_scale": 1.0, "origin": Vector2.ZERO, "stage": stage}
		return

	if AppSettings.aspect_mode == AppSettings.AspectMode.STRETCH_FILL:
		_view = {"fit_scale": 1.0, "origin": Vector2.ZERO, "stage": stage, "stretch": true}
		if stage_host:
			stage_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return

	var target_aspect := AppSettings.target_aspect()
	var usable := view
	var usable_origin := Vector2.ZERO
	if target_aspect > 0.0:
		var window_aspect := view.x / view.y
		if window_aspect > target_aspect:
			usable.x = view.y * target_aspect
			usable_origin.x = (view.x - usable.x) * 0.5
		elif window_aspect < target_aspect:
			usable.y = view.x / target_aspect
			usable_origin.y = (view.y - usable.y) * 0.5

	var fit := minf(usable.x / stage.x, usable.y / stage.y)
	var drawn := stage * fit
	var origin := usable_origin + (usable - drawn) * 0.5
	_view = {"fit_scale": fit, "origin": origin, "stage": stage}
	if stage_host:
		stage_host.position = origin
		stage_host.size = drawn
	if letterbox:
		letterbox.visible = true
	InputRouter.set_stage_rect(Rect2(Vector2.ZERO, stage))


func _update_virtual_cursor_visual() -> void:
	if virtual_cursor == null:
		return
	virtual_cursor.visible = InputRouter.using_gamepad
	var screen := stage_to_screen(InputRouter.virtual_cursor)
	virtual_cursor.position = screen - virtual_cursor.size * 0.5


func draw_current_frame(canvas: Control) -> void:
	var frame: Dictionary = runtime.loader.get_frame(runtime.frame_index)
	var sprites: Array = frame.get("sprites", []).duplicate()
	# Low channel under high channel (Director score layering).
	sprites.sort_custom(func(a, b): return int(a.get("channel", 0)) < int(b.get("channel", 0)))
	var sx: float = canvas.size.x / maxf(float(runtime.loader.stage_size.x), 1.0)
	var sy: float = canvas.size.y / maxf(float(runtime.loader.stage_size.y), 1.0)
	var puppet: PuppetController = runtime.puppet

	for sprite in sprites:
		if typeof(sprite) != TYPE_DICTIONARY:
			continue
		var channel: int = int(sprite.get("channel", 0))
		# Puppet overrides score channel 30 while active.
		if puppet.active and channel == 30:
			continue
		# Story-gated: in the score, but the story has not reached it yet.
		if runtime.is_channel_hidden(channel):
			continue

		var cast_lib: int = int(sprite.get("cast_lib", 1))
		var cast_id: int = int(sprite.get("cast_id", 0))
		var inv: Dictionary = GameState.inventory_override_for_channel(channel)
		var draw_lib: int = cast_lib
		if not inv.is_empty():
			draw_lib = int(inv.cast_lib)
			cast_id = int(inv.cast_id)

		if (
			runtime.loader.movie_name.to_lower() == "strtgame"
			and runtime.menu_hover_channel == channel
			and STRTGAME_MENU_HOVER.has(channel)
		):
			cast_id = int(STRTGAME_MENU_HOVER[channel]["hover"])

		if inv.is_empty():
			var film_loop: Dictionary = runtime.loader.get_film_loop(draw_lib, cast_id)
			if not film_loop.is_empty():
				_draw_film_loop(canvas, sprite, film_loop, channel, sx, sy)
				continue

		var member: Dictionary = {}
		var has_image: bool = bool(sprite.get("has_image", false))
		if not has_image and inv.is_empty():
			member = runtime.loader.get_linked_member(draw_lib, cast_id)
			if member.is_empty():
				continue

		var ink: int = int(sprite.get("ink", 0))
		var use_matte: bool = RenderModelLoader.is_transparent_ink(ink) or not inv.is_empty()
		var tex: Texture2D = runtime.loader.get_texture(draw_lib, cast_id, use_matte)
		if tex == null:
			continue

		var x: float = float(sprite.get("x", 0)) * sx
		var y: float = float(sprite.get("y", 0)) * sy
		var w: float = float(sprite.get("width", 1)) * sx
		var h: float = float(sprite.get("height", 1)) * sy

		if not inv.is_empty():
			# Inventory icons: natural size, reg-point on slot center (web parity).
			member = runtime.loader.get_member(draw_lib, cast_id)
			var nw: float = float(tex.get_width()) * sx
			var nh: float = float(tex.get_height()) * sy
			var reg_x: float = float(member.get("reg_offset_x", tex.get_width() * 0.5)) * sx
			var reg_y: float = float(member.get("reg_offset_y", tex.get_height() * 0.5)) * sy
			var cx: float = x + w * 0.5
			var cy: float = y + h * 0.5
			canvas.draw_texture_rect(tex, Rect2(cx - reg_x, cy - reg_y, nw, nh), false)
		else:
			# Score sprites stretch to sprite rect (Director default).
			if member.is_empty():
				member = runtime.loader.get_member(draw_lib, cast_id)
			if member.has("_registry_directory"):
				var stage_position := _registry_score_stage_position(sprite, member)
				x = stage_position.x * sx
				y = stage_position.y * sy
			canvas.draw_texture_rect(tex, Rect2(x, y, w, h), false)

	if puppet.active:
		var ptex: Texture2D = runtime.loader.get_texture(puppet.cast_lib, puppet.cast_id, true)
		if ptex:
			var pmember: Dictionary = runtime.loader.get_member(puppet.cast_lib, puppet.cast_id)
			var prect: Rect2 = puppet.draw_rect(pmember, ptex, sx, sy)
			canvas.draw_texture_rect(ptex, prect, false)

	if AppSettings.show_debug_overlays or AppSettings.show_hotspot_hints:
		for sprite in runtime.clickable_sprites(frame):
			var r: Rect2 = runtime.sprite_stage_rect(sprite)
			var rect: Rect2 = Rect2(r.position.x * sx, r.position.y * sy, r.size.x * sx, r.size.y * sy)
			var color: Color = (
				Color(0.35, 0.8, 1.0, 0.85)
				if AppSettings.show_debug_overlays
				else Color(1.0, 0.9, 0.2, 0.55)
			)
			canvas.draw_rect(rect, color, false, 2.0)

	if not runtime.hovered_sprite.is_empty():
		var hr: Rect2 = runtime.sprite_stage_rect(runtime.hovered_sprite)
		canvas.draw_rect(
			Rect2(hr.position.x * sx, hr.position.y * sy, hr.size.x * sx, hr.size.y * sy),
			Color(1.0, 0.92, 0.35, 0.95),
			false,
			2.0
		)
