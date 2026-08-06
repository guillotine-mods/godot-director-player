extends SceneTree
## Boot the way a player does and report any frame the score sits on.
##
## Headless is fine — the Dummy driver does advance playback, at roughly 0.35x
## real time, so `soundBusy` still goes idle. What is *not* fine is driving this
## on a tight `for i in N: tick()` loop: that advances the runtime's clock and
## not the audio server's, so no sound ever finishes and every
## `if soundBusy(1) then go to the frame` guard holds for ever. The
## `await process_frame` below is load-bearing. See bugs.md 22.
var _r = null
var _counts := {}
var _ticks := 0

func _initialize() -> void:
	root.call_deferred("add_child", load("res://scenes/main.tscn").instantiate())
	_go.call_deferred()

func _go() -> void:
	await process_frame
	await process_frame
	var main := root.get_child(root.get_child_count() - 1)
	var player: Node = main.get_node("MoviePlayer")
	_r = player.runtime
	_r.goto_movie("strtgame", null, {})
	for i in 25:
		_r.game_step()
	var sp: Dictionary = {}
	for x in _r.clickable_sprites(_r.loader.get_frame(_r.frame_index)):
		if int((x as Dictionary).get("channel", 0)) == 4: sp = x
	_r.perform_click(_r.sprite_stage_rect(sp).get_center())
	print("STUCK clicked New Game")
	var last := ""
	var seq := []
	for i in 4000:
		await process_frame
		_r.tick(0.016)
		var k := "%s:%d" % [_r.loader.movie_name, _r.frame_index]
		_counts[k] = int(_counts.get(k, 0)) + 1
		if k != last:
			last = k
			if seq.size() < 400: seq.append(k)
	var worst := ""
	var worstn := 0
	for k in _counts.keys():
		if int(_counts[k]) > worstn:
			worstn = int(_counts[k]); worst = str(k)
	print("STUCK distinct states=", _counts.size(), " most-repeated=", worst, " x", worstn)
	print("STUCK movie now=", _r.loader.movie_name, " label=", _r.label_near_frame(_r.frame_index))
	var tail := []
	for j in range(maxi(0, seq.size() - 12), seq.size()): tail.append(seq[j])
	print("STUCK last states: ", tail)
	quit(0)
