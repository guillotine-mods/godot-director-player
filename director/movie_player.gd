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


func _log_frame_texture_stats(tag: String) -> void:
	var frame: Dictionary = runtime.loader.get_frame(runtime.frame_index)
	var ok := 0
	var miss := 0
	for sprite in frame.get("sprites", []):
		if typeof(sprite) != TYPE_DICTIONARY or not bool(sprite.get("has_image", false)):
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

		if not bool(sprite.get("has_image", false)) and inv.is_empty():
			continue

		# Keep the channel-1 scene background opaque. All character/object
		# sprites use the edge-connected white matte, regardless of Director ink.
		var use_matte: bool = channel != 1 or not inv.is_empty()
		var tex: Texture2D = runtime.loader.get_texture(draw_lib, cast_id, use_matte)
		if tex == null:
			continue

		var x: float = float(sprite.get("x", 0)) * sx
		var y: float = float(sprite.get("y", 0)) * sy
		var w: float = float(sprite.get("width", 1)) * sx
		var h: float = float(sprite.get("height", 1)) * sy

		if not inv.is_empty():
			# Inventory icons: natural size, reg-point on slot center (web parity).
			var member: Dictionary = runtime.loader.get_member(draw_lib, cast_id)
			var nw: float = float(tex.get_width()) * sx
			var nh: float = float(tex.get_height()) * sy
			var reg_x: float = float(member.get("reg_offset_x", tex.get_width() * 0.5)) * sx
			var reg_y: float = float(member.get("reg_offset_y", tex.get_height() * 0.5)) * sy
			var cx: float = x + w * 0.5
			var cy: float = y + h * 0.5
			canvas.draw_texture_rect(tex, Rect2(cx - reg_x, cy - reg_y, nw, nh), false)
		else:
			# Score sprites stretch to sprite rect (Director default).
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
