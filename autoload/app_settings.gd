extends Node
## Display / QoL / enhancement toggles for the Godot port.

signal settings_changed

enum AspectMode {
	NATIVE_4_3, ## Classic 640x480 letterboxed
	WIDE_16_9, ## Fit 16:9 with letterbox / side gutters for edge hotspots
	ULTRA_21_9, ## Ultrawide test bed
	STRETCH_FILL, ## Stretch stage to full window (distorts)
}

enum UpscaleMode {
	NONE, ## 1x nearest
	X2_NEAREST,
	X3_NEAREST,
	X2_SMOOTH, ## Test path for enhanced / upscaled art
}

const CONFIG_PATH := "user://piposh2_settings.cfg"

var aspect_mode: AspectMode = AspectMode.WIDE_16_9
var upscale_mode: UpscaleMode = UpscaleMode.X2_NEAREST
## Master switch for development aids. Off by default: nothing that only exists
## to help build the game may show up in a normal play session.
var dev_mode: bool = false
var show_debug_overlays: bool = true
var show_hotspot_hints: bool = false
var allow_minigame_skip: bool = true
var controller_cursor_speed: float = 420.0
var test_mode_enhanced_graphics: bool = false
## When true, edge-exit strips expand into widescreen gutters (web player parity).
var expand_edge_hotspots: bool = true


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	aspect_mode = int(cfg.get_value("display", "aspect_mode", aspect_mode)) as AspectMode
	upscale_mode = int(cfg.get_value("display", "upscale_mode", upscale_mode)) as UpscaleMode
	dev_mode = bool(cfg.get_value("debug", "dev_mode", dev_mode))
	show_debug_overlays = bool(cfg.get_value("debug", "overlays", show_debug_overlays))
	show_hotspot_hints = bool(cfg.get_value("qol", "hotspot_hints", show_hotspot_hints))
	allow_minigame_skip = bool(cfg.get_value("qol", "minigame_skip", allow_minigame_skip))
	controller_cursor_speed = float(cfg.get_value("input", "cursor_speed", controller_cursor_speed))
	test_mode_enhanced_graphics = bool(cfg.get_value("display", "enhanced_graphics", test_mode_enhanced_graphics))
	expand_edge_hotspots = bool(cfg.get_value("display", "expand_edge_hotspots", expand_edge_hotspots))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "aspect_mode", aspect_mode)
	cfg.set_value("display", "upscale_mode", upscale_mode)
	cfg.set_value("display", "enhanced_graphics", test_mode_enhanced_graphics)
	cfg.set_value("display", "expand_edge_hotspots", expand_edge_hotspots)
	cfg.set_value("debug", "dev_mode", dev_mode)
	cfg.set_value("debug", "overlays", show_debug_overlays)
	cfg.set_value("qol", "hotspot_hints", show_hotspot_hints)
	cfg.set_value("qol", "minigame_skip", allow_minigame_skip)
	cfg.set_value("input", "cursor_speed", controller_cursor_speed)
	cfg.save(CONFIG_PATH)
	settings_changed.emit()


func notify_changed() -> void:
	save_settings()


func show_press_marks() -> bool:
	## Boxes over every clickable hotspot. A development aid, so it needs dev_mode
	## as well as its own toggle. `show_hotspot_hints` is the player-facing one
	## (H key) and stands on its own.
	return dev_mode and show_debug_overlays


func stage_scale_factor() -> int:
	match upscale_mode:
		UpscaleMode.X2_NEAREST, UpscaleMode.X2_SMOOTH:
			return 2
		UpscaleMode.X3_NEAREST:
			return 3
		_:
			return 1


func use_smooth_filter() -> bool:
	return upscale_mode == UpscaleMode.X2_SMOOTH or test_mode_enhanced_graphics


func target_aspect() -> float:
	match aspect_mode:
		AspectMode.WIDE_16_9:
			return 16.0 / 9.0
		AspectMode.ULTRA_21_9:
			return 21.0 / 9.0
		AspectMode.STRETCH_FILL:
			return -1.0
		_:
			return 4.0 / 3.0


func aspect_mode_name() -> String:
	return AspectMode.keys()[aspect_mode]


func upscale_mode_name() -> String:
	return UpscaleMode.keys()[upscale_mode]
