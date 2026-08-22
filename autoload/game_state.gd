extends Node
## The player half's log bus. Despite the name, it holds no game state.
##
## What is here is one signal and one function. Anything the engine wants a
## harness to be able to see -- `Audio miss`, `Audio load fail`, a WAV this port
## does not decode -- goes through `emit_log`, which fans it out twice: to
## `log_message` for a listener, and to stdout as `[player:<level>] <message>`
## for a run that is reading the transcript. `tools/qa_walk.gd` connects the
## signal (after `await process_frame`, because `_init` on a `SceneTree` runs
## before the autoloads are in the tree); `autoload/audio_director.gd` is the
## only caller.
##
## ## Why a log bus is called `GameState`
##
## Because it used to be one. This file was the retired renderer's Piposh 2 game
## model: `HUB_MOVIES` as `["DAY1", "HOTEL1", "NIGHT1"]`, `MINIGAME_MOVIES`
## naming CHESS/TENNIS/SHUFFLE/ARCADE1/ARCADE2/PPTSHOW/SEA1/AIR1, a day counter,
## a meetings table with `people_funk` routing over it, an eight-slot inventory
## keyed to score channels 103-110, story flags, a route stack, and a
## JSON save-slot API under `user://saves`. All of it mirrored
## `data/movie_context.json`, which was deleted with the renderer that read it,
## and every member was referenced only from inside this file. `bugs.md` 127
## removed them: `AGENTS.md`'s third standing rule is that no room name,
## character or per-title mapping belongs in engine code, and that was the
## plainest breach of it in the tree. The real save path is
## `scenes/preview/save_state.gd`, `save_files.gd` and `movie_save.gd`, and it
## never touched this node.
##
## The name and the path stayed, and that is a deliberate call rather than an
## oversight. `audio_director.gd` binds `GameState` as a parse-time identifier,
## `qa_walk.gd` reaches it by string with a comment explaining why, and the
## piposh-3d embedding's `res://` collision analysis
## (`docs/superpowers/specs/2026-08-10-embedding-piposh-3d-design.md`) is written
## against this exact path and its `.uid`. Renaming is a separate change at those
## three sites; it is not a prerequisite for the model being gone.
##
## Nothing that was removed is missing. Where a title wants "which sound is
## playing" or "which day is it", the interpreter already holds the movie's own
## Lingo globals -- Piposh Dream's `Hquest.dir` keeps `global whichsnd` and
## compares it itself -- and engine-side bookkeeping of a movie's global is the
## wrong shape for a general Director engine.

signal log_message(message: String, level: String)


func emit_log(message: String, level: String = "info") -> void:
	log_message.emit(message, level)
	print("[player:%s] %s" % [level, message])
