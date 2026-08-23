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
## **Two of the values below reach something; the other two are plumbing.**
## `cursor_speed` is read by `autoload/input_router.gd`, and `hotspot_hints` is
## read by the same file and applied by `scenes/preview/hilite.gd`
## (`bugs.md` 130): with it on, every sprite the click router can reach is
## outlined for as long as it is on. `upscale_mode` and `enhanced_graphics` and
## `expand_edge_hotspots` are read, written and offered by the launcher and
## nothing acts on them yet -- wiring each to the renderer or the input path is a
## separate piece of work per toggle.
##
## **The launcher's `QolHint` says which is which, and it has to be edited in the
## same change as the wiring.** That is the whole reason the disclosure exists --
## so the first report is not "hotspot hints is broken" -- and a disclosure that
## still says a toggle does nothing after it started doing something is worse
## than the unwired toggle was, because it is the sentence a reader trusts
## instead of testing. It said "the cursor speed is the only one the engine reads
## today" until `hotspot_hints` landed, and moved in the same commit.
##
## **`allow_minigame_skip` is not on that list, because it is not pending: it is
## gone** (`bugs.md` 129). It was the flag on the retired renderer's
## `skip_current()`, which asked `GameState.is_minigame_movie` -- a table of
## Piposh 2 titles -- and then walked to the next marker. That walk is the one
## the engine deleted after four reports, and `scenes/director_preview.gd`'s
## comment on `skip_release` says why it cannot come back in any form: a marker
## labels a position, and nothing in a `VWLB` says which positions are scenes.
## "Which movie is a skippable minigame, and where does skipping it land" is not
## answerable from a container, so there is nothing here for a flag to gate.
## Do not re-add the field. What a debug build has instead is `skip_release`,
## which releases the frame's holds and moves the playhead nowhere.

const GameConfig := preload("res://director/game_config.gd")

## The file this node used to own. Read once, for one value, then never again.
const RETIRED_PATH := "user://player_settings.cfg"

var upscale_mode: int = 1
var enhanced_graphics: bool = false
var expand_edge_hotspots: bool = true
var show_hotspot_hints: bool = false
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
