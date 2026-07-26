extends SceneTree
## Screenshot each recovered film loop across several score frames, so the
## animation can be looked at rather than inferred from a resolve count.
##
##   godot --script tools/shoot_film_loops.gd
##
## Writes user://film_loops/<cast>-<id>-<n>.png. Needs a real window, so no
## --headless.

const SHOTS := 4
const STEPS_BETWEEN := 3
const OUT_DIR := "user://film_loops"

const CASES := [
	{"cast": "jokers", "id": 101, "movie": "DIVEFIGT", "frame": 5},
	{"cast": "sabmon", "id": 135, "movie": "SABMON2", "frame": 109},
	{"cast": "hatuli", "id": 158, "movie": "MIROLO", "frame": 193},
	{"cast": "heznigt", "id": 297, "movie": "FUGEL", "frame": 0},
	{"cast": "black", "id": 173, "movie": "SAMNIGHT", "frame": 212},
	{"cast": "detectiv", "id": 204, "movie": "ENDMOVI5", "frame": 2528},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.call_deferred("add_child", load("res://scenes/main.tscn").instantiate())
	_drive.call_deferred()


func _drive() -> void:
	await process_frame
	await process_frame
	var main := root.get_child(root.get_child_count() - 1)
	var player: Node = main.get_node("MoviePlayer")
	var runtime = player.runtime

	for case in CASES:
		var movie: String = case["movie"]
		var frame: int = case["frame"]
		if not runtime.goto_movie(movie, frame):
			print("%s: goto_movie failed" % movie)
			continue
		for shot in SHOTS:
			for _step in STEPS_BETWEEN:
				runtime.game_step()
			player.queue_redraw()
			await process_frame
			await process_frame
			var image := root.get_texture().get_image()
			var path := "%s/%s-%d-%d.png" % [OUT_DIR, case["cast"], case["id"], shot]
			image.save_png(path)
		print("%-9s %3d  %-9s captured %d shots" % [case["cast"], case["id"], movie, SHOTS])

	print("wrote to %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)
