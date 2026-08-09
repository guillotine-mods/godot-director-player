extends Node
## The player-facing toggles, read from the same config layer as everything else.
##
## This used to own `user://player_settings.cfg` and a dozen fields, and exactly
## one of them was read anywhere: `controller_cursor_speed`, by
## `autoload/input_router.gd`. The rest were duplicates of live config keys
## (`aspect_mode` against `[display] aspect`, `dev_mode` against `[debug]
## enabled`) or documented orphans of a renderer that was deleted. Two names for
## one question is how a setting starts disagreeing with itself.
##
## **The values below are plumbing, and only `cursor_speed` reaches anything.**
## The rest are read, written and offered by the launcher, and nothing acts on
## them yet -- wiring each to the renderer or the input path is a separate piece
## of work per toggle. The launcher labels them as such, so the first report is
## not "hotspot hints is broken".

const GameConfig := preload("res://director/game_config.gd")

## The file this node used to own. Read once, for one value, then never again.
const RETIRED_PATH := "user://player_settings.cfg"

var upscale_mode: int = 1
var enhanced_graphics: bool = false
var expand_edge_hotspots: bool = true
var show_hotspot_hints: bool = false
var allow_minigame_skip: bool = true
var controller_cursor_speed: float = 420.0
var dev_warp_movie: String = "MURDER1"
var dev_warp_label: String = ""


func _ready() -> void:
	load_settings()


## Re-read every value from the config layer.
##
## Called at start, and again by the launcher after it writes the overlay. That
## second call is not optional: this node reads the config once at process
## start and survives the scene change into the movie, so without it the
## launcher's `cursor_speed` -- the one value here a live consumer reads -- would
## be the pre-launcher one for the whole session. `AudioDirector.reset_index`
## exists beside it for the same reason.
func load_settings() -> void:
	GameConfig.invalidate()
	var cfg := GameConfig.merged()
	upscale_mode = int(cfg.get_value("qol", "upscale_mode", upscale_mode))
	enhanced_graphics = bool(cfg.get_value("qol", "enhanced_graphics", enhanced_graphics))
	expand_edge_hotspots = bool(cfg.get_value("qol", "expand_edge_hotspots", expand_edge_hotspots))
	show_hotspot_hints = bool(cfg.get_value("qol", "hotspot_hints", show_hotspot_hints))
	allow_minigame_skip = bool(cfg.get_value("qol", "minigame_skip", allow_minigame_skip))
	controller_cursor_speed = float(cfg.get_value("qol", "cursor_speed", _migrated_speed()))
	dev_warp_movie = str(cfg.get_value("debug", "warp_movie", dev_warp_movie))
	dev_warp_label = str(cfg.get_value("debug", "warp_label", dev_warp_label))


## The one value with a live consumer, and the one an existing install already
## has on disc. Read out of the retired file when the new layer does not carry
## it; after that the overlay does and this is never consulted again. The old
## file is not deleted -- leaving it costs nothing, and removing a file nobody
## asked us to touch is not ours to do.
func _migrated_speed() -> float:
	var old := ConfigFile.new()
	if old.load(RETIRED_PATH) != OK:
		return controller_cursor_speed
	return float(old.get_value("input", "cursor_speed", controller_cursor_speed))


func stage_scale_factor() -> int:
	return clampi(upscale_mode, 1, 3)


func use_smooth_filter() -> bool:
	return enhanced_graphics
