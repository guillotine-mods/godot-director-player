extends RefCounted
## The only file in `tools/lib/` that knows this is Piposh 2.
##
## `director-port-architecture` puts the loader, the score runner, the interpreter
## host and the engine on the reusable side of a port and game state on the other,
## and `GameState` here is emphatically the other side: `DAY1_MEETINGS_INIT`,
## `HUB_MOVIES`, `people_funk`. Every tool booted through
## `root.get_node("GameState").new_game()`, so hoisting that call as written would
## have made the shared driver non-portable on its first line.
##
## Carrying the lib to another Director port means rewriting this file and nothing
## else. It is rewritten per title, never parameterised: configuration for
## differences between games we have not met would be invention, not design.
##
## Autoloads are reached through the tree, not by their global identifier — the
## identifier does not resolve in a script run under `--script`.

## Called before the runtime is constructed, because `DirectorRuntime.boot()` only
## builds the Lingo engine when one of these is set. Setting them after boot gives
## a runtime with no interpreter and a flag that claims otherwise.
func configure(tree: SceneTree, flags: Dictionary) -> void:
	if flags.is_empty():
		return
	var settings: Node = tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return
	if flags.has("lingo_frames"):
		settings.use_lingo_frames = bool(flags["lingo_frames"])
	if flags.has("lingo_clicks"):
		settings.use_lingo_clicks = bool(flags["lingo_clicks"])
	if flags.has("hotspot_hints"):
		settings.show_hotspot_hints = bool(flags["hotspot_hints"])


func new_game(tree: SceneTree) -> void:
	var state := game_state(tree)
	if state != null:
		state.new_game()


func game_state(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("GameState")
