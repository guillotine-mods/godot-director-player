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
## Master switch for development aids (press marks, the Skip scene button).
## ON while the port is being built. FLIP THIS TO false BEFORE SHIPPING, or an
## exported build hands players a skip button and boxes over every hotspot.
var dev_mode: bool = true
## Interpret the original Lingo for mouse clicks instead of the lifted on_click.
##
## OFF, and the blocker is known precisely. Enabling it takes the walk suites from
## 0/0/28 failures to 5/2/31, because the original click handler on an exit sets
## `nextroomdata` and `egozh`/`egozv` and leaves the moving to `walkonby`, which
## this port replaces with walk_doorways.json and has not wired to the
## interpreter. Those are the same 190 cases tools/lingo_converge.gd counts as
## deferred walks. Wire walkonby, then flip this.
var use_lingo_clicks: bool = false
## Interpret `on exitFrame`: 2504 of the game's 3457 handlers, so most of the
## script logic now runs from the original Lingo rather than the lifted score data.
##
## ON, on this evidence: with clicks left off, tools/lingo_walk_diff.gd finds
## 115/117 walk outcomes identical across DAY1, NIGHT1 and HOTEL1, and the two
## differences are improvements (HOTEL1 roomago and roombgo now reach `hallgo`
## instead of stranding at `what`, both listed as unmapped transitions in
## data/movie_context.json). The three deleted suites also returned to their exact
## 0/0/28 baseline with this on.
var use_lingo_frames: bool = true
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
	use_lingo_clicks = bool(cfg.get_value("lingo", "clicks", use_lingo_clicks))
	use_lingo_frames = bool(cfg.get_value("lingo", "frames", use_lingo_frames))
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
	cfg.set_value("lingo", "clicks", use_lingo_clicks)
	cfg.set_value("lingo", "frames", use_lingo_frames)
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
